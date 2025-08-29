local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
 local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Monk-Windwalker','Monk-Mistweaver','Mage-Arcane','Mage-Fire','DeathKnight-Frost',}; local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aantis:BAAALAADCgMIAwAAAA==.',Ab='Abyssius:BAAALAADCgcIBwAAAA==.',Ac='Acnologias:BAAALAADCgYIBgAAAA==.',Ag='Agares:BAAALAADCgcIDgABLAAECgYICAABAAAAAA==.Aggrenox:BAAALAADCgUIBgAAAA==.',Al='Alottarage:BAAALAADCgMIAwAAAA==.Alunantre:BAAALAAECgEIAgAAAA==.',Am='Amberscale:BAAALAAECgYICgAAAA==.',An='Ancientuur:BAAALAAECgYICAAAAA==.Angravar:BAAALAAECgYICAAAAA==.Angrulus:BAAALAAECgUICAAAAA==.Animlshiftr:BAAALAADCggIDwAAAA==.',Ap='Apollo:BAAALAAECgMIBgAAAA==.',Ar='Aradunn:BAAALAAECgYIDwAAAA==.Arrill:BAEALAADCgUIBQAAAA==.Aruix:BAAALAADCggICAAAAA==.Aryllyn:BAAALAADCgcIDAAAAA==.',As='Asti:BAAALAAECgYIBgAAAA==.Astrilea:BAAALAADCggIFgAAAA==.',Ba='Baldguyph:BAAALAAECgcIDQAAAA==.Barber:BAAALAAECgEIAQAAAA==.Basspro:BAAALAAECgMIAwAAAA==.',Be='Bern:BAAALAAECgEIAgAAAA==.Bernd:BAAALAAECgEIAQAAAA==.Beörn:BAAALAAECgEIAQAAAA==.',Bi='Bissell:BAAALAAECgYIEAAAAA==.',Bl='Blazéoné:BAAALAAECgEIAQAAAA==.Bloodieshoes:BAAALAADCgcIAgAAAA==.',Br='Bro:BAAALAADCgUIBQAAAA==.Bruche:BAAALAAECgYICQAAAA==.',Bu='Bugaboo:BAAALAAECgYICwAAAA==.',Bw='Bwca:BAAALAAECgYIAwAAAA==.',By='Byanca:BAAALAAECgcICgAAAA==.',Ca='Cahootz:BAAALAAECgUIBQAAAA==.Cakébob:BAAALAADCgQIBAAAAA==.Cataaria:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.',Ce='Cellina:BAAALAAECggIBgAAAA==.',Ch='Cheyberry:BAAALAAECgEIAQAAAA==.',Cl='Classá:BAAALAAECgYICgAAAA==.',Co='Coldbreww:BAAALAADCgcICwAAAA==.Comradeprime:BAAALAADCgMIAwAAAA==.Corlys:BAAALAAECgEIAQAAAA==.',Cr='Crispìn:BAAALAAECgMIAwAAAA==.Crownfalkor:BAAALAADCgYIBgAAAA==.Crue:BAAALAAECgQIBgAAAA==.',Cy='Cynboom:BAAALAADCgcIEQAAAA==.Cyndee:BAAALAAECgUICAAAAA==.Cynth:BAAALAADCgUIBQAAAA==.Cytenk:BAAALAAECgYICAAAAA==.',Da='Dadda:BAABLAAECoEbAAICAAYIoxtWFQDOAQACAAYIoxtWFQDOAQAAAA==.Damascus:BAAALAADCggIDwAAAA==.Dankmonk:BAAALAADCggIFgAAAA==.Darkstrikes:BAAALAAECgEIAQAAAA==.Darthyuki:BAAALAAECgMIAwAAAA==.Dartos:BAAALAAECgQIBwAAAA==.',De='Deathsbff:BAAALAAECgMIAwABLAAECgYIDQABAAAAAA==.Deathstár:BAAALAAECgEIAQAAAA==.Deep:BAAALAAECgYIBgAAAA==.Deepbloom:BAAALAADCgcIBwAAAA==.Dendran:BAAALAAECgEIAQAAAA==.',Di='Diluvium:BAAALAAECgEIAQAAAA==.Dinglemire:BAAALAADCgYIBgAAAA==.Dizz:BAAALAAECgYICwAAAA==.',Dr='Drudem:BAAALAADCgcIBwAAAA==.',Ea='Earlison:BAAALAADCgcIBwAAAA==.Eatmorpizza:BAAALAADCgcIFAAAAA==.',Ee='Eegroll:BAABLAAECoEWAAMDAAgIBBjyBwBOAgADAAgIBBjyBwBOAgAEAAcIug2fEQBiAQAAAA==.',Eg='Egraw:BAAALAAECgEIAQAAAA==.',El='Elementwolf:BAAALAAECgMIBQAAAA==.Elsä:BAAALAADCgMIAwAAAA==.Elémental:BAAALAADCgMIAwAAAA==.',Em='Emilwhaury:BAAALAADCgcIDQAAAA==.',Ep='Epia:BAAALAAECggIAwAAAA==.',Et='Etherwalker:BAAALAAECgIIAgAAAA==.',Ev='Evocati:BAAALAAECgQIBAAAAA==.Evoka:BAAALAAECgcIDAAAAA==.',Ex='Excision:BAAALAAECgIIAwAAAA==.',Fa='Fahbio:BAAALAADCgcIDAAAAA==.Fallenlock:BAAALAADCggICgAAAA==.Famfriendly:BAAALAAECggIBgAAAA==.Fanskar:BAAALAADCgcIBwAAAA==.',Fe='Felinia:BAAALAAECgMIBQAAAA==.',Fi='Fistsmither:BAAALAADCgUIBQAAAA==.',Fl='Flailpriest:BAAALAADCggIEAAAAA==.Flailuid:BAAALAADCgcIDQAAAA==.',Fo='Forron:BAAALAADCgcICAAAAA==.',Fr='Frozarke:BAAALAAECgMIBQAAAA==.',Fu='Fudd:BAAALAADCgcIDgAAAA==.Fupa:BAAALAADCggIDwAAAA==.',Fy='Fyrand:BAAALAADCgIIAgAAAA==.',['Fí']='Fí:BAAALAAECgMIAwAAAA==.',Ga='Galand:BAAALAADCggICAAAAA==.Garres:BAAALAADCgcICQAAAA==.',Ge='Genius:BAAALAADCgcIEwAAAA==.Gethrow:BAAALAADCgYIBgAAAA==.',Gi='Gillruen:BAAALAADCggIFAAAAA==.Gillygirl:BAAALAADCgQIBAAAAA==.',Gl='Gladorf:BAAALAADCgcIDgAAAA==.',Gn='Gnomad:BAAALAADCggIEwAAAA==.',Go='Goosepally:BAAALAADCgcIDQAAAA==.Gouge:BAAALAAECgYIBgAAAA==.',Gr='Griffynshu:BAAALAADCggIDwAAAA==.Grudgetotem:BAAALAAECgMIBgAAAA==.Grundy:BAAALAAECgEIAQAAAA==.Grunewald:BAAALAAECgIIBQAAAA==.Gráve:BAAALAADCggICAAAAA==.',Gw='Gwaihir:BAAALAAECgEIAQAAAA==.',Gy='Gyrashun:BAAALAAECgEIAQAAAA==.',Ha='Hawkeye:BAAALAADCgMIAwAAAA==.',He='Hellabrew:BAAALAADCgcIBwAAAA==.Hellavva:BAAALAADCgcICQAAAA==.Henchling:BAAALAADCggICwAAAA==.',Ho='Holexios:BAAALAADCgUIBQABLAADCggICAABAAAAAA==.Holygemm:BAAALAAECgEIAQAAAA==.Hotnrdy:BAAALAAECgIIAgAAAA==.',Hu='Hunt:BAAALAADCgcIDgAAAA==.Huruk:BAAALAADCgEIAQAAAA==.',Ic='Icieblade:BAAALAADCggICAAAAA==.Icyene:BAAALAADCgQIBAAAAA==.',Ik='Ikorarey:BAAALAADCgYIBgAAAA==.',Im='Immeira:BAAALAAECgMIAwAAAA==.',In='Infernokeep:BAAALAADCgMIBQAAAA==.Insanezane:BAAALAADCggICQAAAA==.',Ja='Jack:BAAALAAECgIIAgAAAA==.Jackcsi:BAAALAAECgIIAwAAAA==.Jalapenzo:BAAALAADCgcIBwAAAA==.Jang:BAAALAADCgUICAAAAA==.',Jc='Jcvoker:BAAALAADCgQIBAAAAA==.',Ji='Jingo:BAAALAAECgMIAwAAAA==.Jitb:BAAALAADCggICAAAAA==.',Jo='Journei:BAAALAAECgIIBQAAAA==.',Ju='Judging:BAAALAAECgEIAgAAAA==.',Ke='Kellayna:BAAALAAECgEIAQAAAA==.Kenseimogaku:BAAALAAECgEIAQAAAA==.Kevknight:BAAALAADCgYIBgAAAA==.',Ki='Kiellannis:BAAALAAECgMIAwAAAA==.Kimigosa:BAAALAAECgMIAwAAAA==.Kirkland:BAAALAADCgMIAwAAAA==.',Kl='Klerik:BAAALAAECgYICwAAAA==.',Ko='Konstantina:BAAALAAECgEIAQAAAA==.Koragg:BAAALAAECggIDwAAAA==.Kozarke:BAAALAAECgEIAQAAAA==.',Kr='Krindel:BAAALAADCgEIAQAAAA==.Krissia:BAAALAAECgUIBgAAAA==.',['Kî']='Kîn:BAAALAADCgcIDgAAAA==.',La='Laisera:BAAALAAECgYIEgAAAA==.Lalipop:BAAALAAECgMIBQAAAA==.Lastkissgbye:BAAALAADCgMIAgAAAA==.Lauma:BAAALAAECgYIAQABLAAECgYIAwABAAAAAA==.',Le='Leif:BAAALAADCgcIBwAAAA==.Lexusis:BAAALAADCgEIAQAAAA==.',Li='Libero:BAAALAAECgMIBAAAAA==.Lightsmasher:BAAALAADCgYIBgAAAA==.Lildipper:BAAALAAECggIBgAAAA==.Lilïth:BAAALAADCggICAAAAA==.Lio:BAAALAADCggICwAAAA==.Lissetteliz:BAAALAAECgEIAQAAAA==.',Lo='Lovis:BAAALAADCgUIBQAAAA==.',Lu='Lumillras:BAAALAAECgMIAwAAAA==.Luthus:BAAALAAECgEIAQAAAA==.',Ma='Madax:BAAALAAECgEIAQABLAAECgYICAABAAAAAA==.Madpig:BAAALAADCgUICwAAAA==.Mads:BAAALAADCgEIAQAAAA==.Madspirit:BAAALAAECgMIAgAAAA==.Mageymutt:BAAALAAECgYIDQAAAA==.Malistaire:BAAALAADCgYIBgAAAA==.Manthamen:BAAALAAECgIIAgAAAA==.',Me='Megamilk:BAAALAAECgMIAwAAAA==.Meimeí:BAAALAADCgMIAwAAAA==.Merle:BAAALAADCgUIBQAAAA==.',Mi='Micalknight:BAAALAAECgEIAQAAAA==.Milliy:BAAALAAECgMICAAAAA==.Minime:BAAALAADCggICAAAAA==.Missbehaving:BAAALAADCgYIBgAAAA==.',Mo='Mojorisin:BAAALAADCgcIEwAAAA==.Moonshaadow:BAAALAADCgQIBAAAAA==.Mosmos:BAAALAAECgYICQAAAA==.',Mu='Mumra:BAAALAAECgIIAwAAAA==.',My='Mykawk:BAAALAADCgQIBAAAAA==.Mystblade:BAAALAADCggIDAAAAA==.Mystlord:BAAALAAECgEIAQAAAA==.',Na='Nachopi:BAAALAAECgMIAwAAAA==.Nalassa:BAAALAAECgQIBQAAAA==.Nannette:BAAALAADCgcIDgAAAA==.Naomi:BAAALAADCggIAgAAAA==.Narag:BAAALAAECgEIAQAAAA==.Naturesgrace:BAAALAADCgEIAQAAAA==.',Ne='Neva:BAAALAADCgMIAwAAAA==.Newport:BAAALAAECgIIAwAAAA==.',Ni='Ninevolt:BAAALAAECgEIAgAAAA==.',No='Notnerb:BAAALAADCggICAAAAA==.Nowhere:BAAALAAECgQICQAAAA==.',['Nâ']='Nârse:BAAALAAECgIIAgAAAA==.',Op='Opalohko:BAAALAADCgcIDgAAAA==.',Or='Orphiee:BAAALAADCgMIAwAAAA==.Oruka:BAAALAADCgcICwAAAA==.',Os='Oslagsi:BAAALAADCgcIDAAAAA==.',Ow='Owthpela:BAAALAAECgMIBAAAAA==.',Ox='Oxmink:BAAALAAECgMIAwAAAA==.',Pa='Pallydane:BAAALAAECgEIAQAAAA==.',Pe='Penderin:BAAALAAECggICAAAAA==.Perlindree:BAAALAAECgMIAwAAAA==.',Pg='Pgorlelgy:BAAALAAECgMIAwAAAA==.',Pl='Platious:BAAALAAECgMIAwAAAA==.',Po='Pookaboo:BAAALAADCggIFQAAAA==.',Pr='Proximo:BAAALAAECgEIAQAAAA==.',Ps='Psysion:BAAALAADCggICQAAAA==.',Pu='Purdie:BAAALAAECgYICQAAAA==.Purplestraza:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.',Qe='Qeesa:BAAALAAECgQIBAAAAA==.',Ra='Rafel:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Raindrop:BAAALAAECgIIAgAAAA==.Ravizulo:BAAALAADCggICAAAAA==.Razors:BAAALAAECgEIAQAAAA==.',Re='Renew:BAAALAAECgMIAwAAAA==.Renix:BAAALAAECgYIDgAAAA==.Reverendtaff:BAAALAADCgcIBwAAAA==.Reyqwaza:BAAALAAECgMIAwAAAA==.',Ri='Righton:BAAALAADCgcICgAAAA==.',Ro='Robomage:BAAALAADCggICAAAAA==.',Sa='Sabyna:BAAALAAECgMIBgAAAA==.',Se='Semi:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Semmi:BAAALAAECgYIDAAAAA==.Sephîeroth:BAAALAADCgQIBwAAAA==.',Sh='Shankya:BAAALAAECgEIAQAAAA==.Shelly:BAAALAADCggIDwAAAA==.Shlumpa:BAAALAAECgcICwAAAA==.Shámjackson:BAAALAAECggIEAAAAA==.',Si='Silvey:BAAALAAECgEIAQAAAA==.',Sl='Slate:BAAALAAECgMIBAAAAA==.Slipnslide:BAAALAAECgEIAQAAAA==.',So='Softy:BAAALAADCgMIAwAAAA==.Sortie:BAAALAAECgEIAQAAAA==.Soulparade:BAAALAADCgYICwAAAA==.',Sp='Spanana:BAAALAAFFAIIAgAAAA==.Spicychopz:BAABLAAECoEVAAMFAAgIfB5vCQDsAgAFAAgIex5vCQDsAgAGAAcIIRdRAwCVAQAAAA==.Spitmother:BAAALAADCggIDQAAAA==.Spooties:BAAALAAECggIDAAAAA==.',Ss='Sscarlet:BAAALAAECgUIBgAAAA==.',St='Starzia:BAAALAAECgEIAQAAAA==.Steve:BAAALAAECgEIAQAAAA==.',Su='Surreal:BAAALAAECgIIAgAAAA==.',Sw='Swiftblossom:BAAALAADCgcIDgAAAA==.',Sy='Sylvir:BAAALAADCggIBwAAAA==.',Sz='Szef:BAAALAAECggIAQAAAA==.',Ta='Taily:BAAALAADCggICAAAAA==.Tailynasura:BAAALAADCggICQAAAA==.Talanot:BAAALAADCggICAAAAA==.Talarus:BAAALAAECgYICQAAAA==.Tangerene:BAAALAAECgQICgAAAA==.Tankabot:BAAALAADCgcIDQAAAA==.Tap:BAAALAADCgcIDQAAAA==.Tarazah:BAAALAAECgEIAQAAAA==.',Te='Telm:BAAALAAECgYICQAAAA==.Tentilious:BAAALAADCgMIAwAAAA==.',Th='Thalorien:BAAALAADCgcIBwAAAA==.Thebestpally:BAAALAAECgMIBgAAAA==.Thenemisis:BAAALAADCggIDwAAAA==.Theyne:BAAALAAECgEIAQAAAA==.Thunderpig:BAAALAAECgEIAQAAAA==.',To='Toolgun:BAAALAAECgEIAQAAAA==.',Tr='Traedaei:BAAALAADCgcIDgAAAA==.Tralth:BAAALAAECgQIBwAAAA==.Troioi:BAAALAADCgcIBwAAAA==.',Ug='Ugard:BAAALAADCggIFgAAAA==.',Uj='Ujio:BAAALAADCgcIDQAAAA==.',Va='Vahloc:BAAALAADCgQIBAAAAA==.Valefyre:BAAALAADCgcICQAAAA==.Valnixia:BAAALAAECgcIDgAAAA==.Vance:BAAALAADCgcIBwAAAA==.Vanvis:BAAALAAECgUIBgAAAA==.',Ve='Velissa:BAAALAADCgQIBAAAAA==.Vexxius:BAAALAAECgMIBQAAAA==.',Vi='Viale:BAAALAADCgcIBwAAAA==.',Vy='Vylana:BAAALAADCggICwAAAA==.',['Và']='Vàlkyrie:BAAALAAECgYIBwAAAA==.',Wa='Warienta:BAAALAAECggICAAAAA==.Warity:BAAALAAECgIIAgAAAA==.Wavestabe:BAAALAAECgMIBgABLAAECggICAABAAAAAA==.',We='Weneyan:BAAALAADCgIIAgAAAA==.',Wh='Whome:BAAALAADCggIDwAAAA==.',Wt='Wtfisfury:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.Wtfrtotems:BAAALAAECgMIAwAAAA==.',Xe='Xeral:BAAALAADCgIIAgAAAA==.',['Xì']='Xìon:BAAALAADCgMIAwAAAA==.',Ya='Yayrri:BAAALAAECgEIAQAAAA==.',Yu='Yurî:BAAALAADCgcIDAAAAA==.',Yv='Yverari:BAAALAADCgcICQAAAA==.',Za='Zahalu:BAAALAAECgIIAgAAAA==.Zahne:BAAALAADCgYIBwAAAA==.Zalyn:BAAALAAECgEIAQAAAA==.Zant:BAAALAADCggIEAAAAA==.Zathamax:BAAALAAECgEIAQAAAA==.',Ze='Zelkris:BAABLAAECoEZAAIHAAcIciFwDQCrAgAHAAcIciFwDQCrAgAAAA==.',Zi='Ziaya:BAAALAADCgcIDgAAAA==.Zidiouz:BAAALAAECgYICgAAAA==.',Zu='Zuboo:BAAALAAECgEIAQAAAA==.',Zy='Zyrai:BAAALAAECgMIBAABLAAECgMIBgABAAAAAA==.',['Éh']='Éhomi:BAAALAAECgMIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end