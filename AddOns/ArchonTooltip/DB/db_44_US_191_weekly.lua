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
 local lookup = {'Unknown-Unknown','Mage-Fire','Mage-Arcane','Mage-Frost','Rogue-Assassination',}; local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acebets:BAAALAAECgIIAgAAAA==.',Ad='Adorie:BAAALAAECgUIBwAAAA==.',Ae='Aetherventus:BAAALAADCggIDwAAAA==.',Ag='Aggen:BAAALAADCgcIFAAAAA==.',Ai='Aitt:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Al='Aladrium:BAAALAADCgEIAQAAAA==.Alasiais:BAAALAADCgQIAgAAAA==.Alexanderath:BAAALAADCgEIAQAAAA==.Alfo:BAAALAAECgcIDwAAAA==.Alissedranna:BAAALAADCgEIAQAAAA==.Allister:BAAALAADCgIIAgAAAA==.',Am='Amberness:BAAALAAECgcIEgAAAA==.Amordion:BAAALAAECgMIBQAAAA==.Amperslam:BAAALAADCgMIAwAAAA==.Ampz:BAAALAADCgUIBQAAAA==.Amøs:BAAALAADCggIDwAAAA==.',An='Angeløfdeath:BAAALAAECgMIAwAAAA==.',Ao='Aoeslave:BAAALAAECgEIAQAAAA==.',Ap='Applebunz:BAAALAAECgEIAQAAAA==.',Ar='Arenamasterz:BAAALAADCggICQAAAA==.Aresalexan:BAAALAAECgIIAgAAAA==.Arrisia:BAAALAAECgEIAQAAAA==.Arthedain:BAAALAAECgcIDwAAAA==.Arthedaine:BAAALAAECgcICgABLAAECgcIDwABAAAAAA==.',As='Asiriusfox:BAAALAADCgcICQAAAA==.',Au='Augmentmyass:BAAALAAECgcICwAAAA==.Aurelia:BAAALAADCgQIBAAAAA==.Auvry:BAAALAAECgcIEwAAAA==.',Ax='Axomomma:BAAALAADCgIIAgAAAA==.',Ba='Bajablast:BAAALAAECgUIBwAAAA==.Bakala:BAAALAAECgEIAQAAAA==.Baloth:BAAALAAECgIIAgAAAA==.Bangbang:BAAALAAECgYIBwAAAA==.',Be='Belegaer:BAAALAAECgYICAAAAA==.Bendini:BAAALAAECgcIDwAAAA==.Benmaverick:BAAALAADCgUIBQAAAA==.',Bi='Billystrings:BAAALAAECgYIDAAAAA==.Bishop:BAAALAAECgMIAwAAAA==.',Bl='Blackbird:BAAALAADCgIIAgAAAA==.Blas:BAAALAADCgQIAwABLAAECgEIAQABAAAAAA==.Bloodbelt:BAAALAADCggICAAAAA==.',Bo='Bobe:BAAALAADCggIFwAAAA==.Bobedruid:BAAALAADCgIIAgAAAA==.',Br='Brolockobama:BAAALAADCggIEwAAAA==.Brëwsleë:BAAALAAECgcIDwAAAA==.',Bw='Bwasamdi:BAAALAADCgYIBgAAAA==.',Ce='Ceindra:BAAALAAECgIIAgAAAA==.Celerity:BAAALAAECgIIAgAAAA==.Celiñ:BAAALAAECgMIBAAAAA==.',Ch='Chered:BAABLAAECoEaAAQCAAgIhCUsAABUAwACAAgIhCUsAABUAwADAAYIcxnRNgCEAQAEAAIIvxZQLwCaAAAAAA==.Chronocandy:BAAALAAECgYICwAAAA==.',Co='Coachney:BAAALAADCggICAAAAA==.Corrosive:BAAALAAECggIBgAAAA==.',Cr='Crowe:BAAALAAECgcIEAAAAA==.',Cu='Cuddlymethod:BAAALAADCgcIEAAAAA==.',['Có']='Cól:BAAALAAECgcIDAAAAA==.',Da='Dahealzrhere:BAAALAADCgIIAgAAAA==.Dalash:BAAALAADCgQIBAAAAA==.Dalel:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Dalester:BAAALAAECgEIAQAAAA==.',De='Deathkratos:BAAALAADCggICAAAAA==.Demi:BAAALAAECgcIDwAAAA==.Demiurgos:BAAALAAECgcIDQAAAA==.Demonicteli:BAAALAAECgcIDwAAAA==.',Do='Dolemen:BAAALAAECgEIAgAAAA==.Dozy:BAAALAADCgcIBAAAAA==.',Dr='Dranthrax:BAAALAAECgEIAQAAAA==.Druidíot:BAAALAADCggIFwAAAA==.',Du='Dunigan:BAAALAAECgEIAQAAAA==.Durlan:BAAALAAECgcICwAAAA==.Duskhoof:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.',Ea='Eastwind:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.',Eb='Ebeast:BAAALAAECgYICwAAAA==.Ebingus:BAAALAADCgcIBwAAAA==.',Ei='Eillim:BAAALAADCgcIBwAAAA==.',El='Elexidor:BAAALAADCggIEAAAAA==.Elorrna:BAAALAAECgMIBAAAAA==.',Es='Estarossa:BAAALAADCgcIBwAAAA==.',Ev='Evianda:BAAALAADCgcIDQAAAA==.',Fa='Facepalm:BAAALAAECgUIBwAAAA==.Falyy:BAAALAADCgQIBAAAAA==.Faradai:BAAALAADCgcIBwAAAA==.Fatherhots:BAAALAADCggIDwAAAA==.Fayla:BAAALAADCgYIBgAAAA==.',Fe='Fentdealer:BAAALAADCggICAAAAA==.Ferm:BAAALAAECgEIAQAAAA==.',Fi='Finnikuz:BAAALAADCgYIBgAAAA==.',Fo='Forgotmymeds:BAAALAAECgMIBQAAAA==.',Ge='Gellywoo:BAAALAAECgEIAgAAAA==.',Go='Golaoth:BAAALAAECgMIBQAAAA==.Gooftoo:BAAALAAECgEIAQAAAA==.Gorkath:BAAALAAECgIIBAAAAA==.',Gr='Greymoon:BAAALAAECgEIAQAAAA==.',Ha='Hanashi:BAAALAADCgYIBgAAAA==.Harash:BAAALAADCggIDwAAAA==.Hatori:BAAALAADCgQIBAAAAA==.',He='Helbafx:BAAALAADCgcIEAAAAA==.Hello:BAAALAADCggIDgAAAA==.Hexanthorn:BAAALAADCggIDwAAAA==.',Hi='Hiroshì:BAAALAAECgEIAQAAAA==.',If='Ifearnobeer:BAAALAADCggIFwAAAA==.',In='Inters:BAAALAADCggICAAAAA==.',Ja='Jadedrienne:BAAALAADCgMIBAAAAA==.Jadus:BAAALAADCggICAAAAA==.Jaiantobea:BAAALAAECgMICAAAAA==.Jawn:BAAALAAECgIIAgAAAA==.',Jo='Joeldakiller:BAAALAADCggICAAAAA==.Jorazak:BAAALAADCgUIBwAAAA==.',Ju='Jude:BAAALAADCggIFwAAAA==.',Ka='Kalahandra:BAAALAAECgcIEAAAAA==.Kalraven:BAAALAAECgEIAQAAAA==.Kantmiss:BAAALAAECgEIAQAAAA==.Kawk:BAAALAADCgYIBgAAAA==.Kazen:BAAALAADCggIEgAAAA==.',Ke='Kenziedadght:BAAALAAECgYICAAAAA==.',Kl='Klazarth:BAAALAAECgcIDwAAAA==.',Kr='Krestisnack:BAAALAAECgIIAgAAAA==.',La='Lazer:BAAALAAECggICgAAAA==.',Le='Lesabor:BAAALAADCggICQAAAA==.',Li='Lir:BAAALAADCgYIBgAAAA==.',Lo='Lotuss:BAAALAADCgcICQABLAAECgEIAQABAAAAAA==.',Lu='Luciä:BAAALAAECgMIBQAAAA==.Luminarus:BAAALAADCgcICgAAAA==.Luntra:BAAALAADCggICAAAAA==.',Ly='Lyñx:BAAALAADCgMIBAAAAA==.',Ma='Maace:BAAALAADCggIFAAAAA==.Marabelle:BAAALAAECgQIBAAAAA==.Martrik:BAAALAADCggIDwAAAA==.Massack:BAAALAAECgUIBwAAAA==.',Mc='Mcboyz:BAAALAADCggICAAAAA==.',Me='Meeow:BAAALAADCggIDwAAAA==.Mellari:BAAALAADCggICAAAAA==.',Mi='Micballs:BAAALAADCgcIBwAAAA==.Mikebeard:BAAALAADCgEIAQAAAA==.Minniemint:BAAALAADCgYIBgAAAA==.',Mo='Moktar:BAAALAAECgcICQAAAA==.Mommyy:BAAALAAECgEIAgAAAA==.Moobear:BAAALAADCggIDwAAAA==.Mortishiin:BAAALAAECgQICAAAAA==.Moushuhan:BAAALAAECgMIBgAAAA==.',Mu='Muldooni:BAAALAAECgUIBwAAAA==.',My='Mystrall:BAAALAAECgYICQAAAA==.',Na='Naanaa:BAAALAAECgcICQAAAA==.',Ne='Netherrogue:BAAALAAECgYIBgAAAA==.',No='Noridi:BAAALAADCggIDwAAAA==.',Ny='Nyteshayed:BAAALAAECgcIDwAAAA==.',Ob='Obmakare:BAAALAAECgEIAQAAAA==.Obonsmark:BAAALAAECgEIAQAAAA==.Obsfuyung:BAAALAADCggIDwAAAA==.',Ok='Okdaz:BAAALAADCgIIAgAAAA==.',Pa='Padremike:BAAALAADCgUIBQAAAA==.Paley:BAAALAADCggIEAAAAA==.',Pe='Percula:BAAALAAECgMIBQAAAA==.Performance:BAAALAAECgcIDAAAAA==.Perun:BAAALAAECgEIAQAAAA==.',Ph='Phoebus:BAAALAADCgUIBQAAAA==.',Po='Poppapatty:BAAALAAECgEIAQAAAA==.Poîsonivy:BAAALAAECgEIAQAAAA==.',Pr='Preauxlock:BAAALAADCgIIAgAAAA==.',Qu='Quådrix:BAAALAAECgUIBwAAAA==.',Ra='Ralvin:BAAALAADCggICQAAAA==.',Re='Reciprocate:BAAALAAECgcIBwAAAA==.Remorse:BAAALAAECgcICwAAAA==.Renaissan:BAAALAADCgEIAQABLAADCggIGQABAAAAAA==.Revivall:BAAALAAECgMIBQAAAA==.',Ri='Ritsen:BAAALAAECgEIAQAAAA==.',Ro='Rocklawbster:BAAALAADCggIDwAAAA==.Roija:BAAALAAECggIAQAAAA==.Rotspawn:BAAALAAECggIBQAAAA==.',Ru='Rurahk:BAAALAAECgYICwAAAA==.',['Rë']='Rën:BAAALAADCggIGQAAAA==.',Sa='Sabaak:BAAALAAECgEIAQAAAA==.Sanorasong:BAEALAADCggIDwABLAAECgMIBQABAAAAAA==.Sarylin:BAAALAADCgYIBgAAAA==.',Sc='Schio:BAAALAAECgEIAQAAAA==.',Se='Severussnape:BAAALAAECgUIBwAAAA==.',Sh='Shyvanna:BAAALAADCgIIAgAAAA==.',Si='Sighah:BAAALAAECgIIAgAAAA==.',Sk='Skarletflame:BAAALAAECgMIBQAAAA==.Skone:BAAALAAECgUIBwAAAA==.',Sl='Slaycie:BAAALAAECgEIAQAAAA==.',So='Songli:BAEALAAECgMIBQAAAA==.Sothis:BAAALAADCggIDgAAAA==.Souldevourer:BAAALAADCgQIBAAAAA==.',Sp='Springtotem:BAAALAAECgIIAgAAAA==.',Su='Sugondese:BAAALAAECgMIBQABLAAECgcIFAAFAKQfAA==.Superneo:BAAALAADCggIDgAAAA==.',Ta='Tacotruck:BAAALAAECgEIAQAAAA==.Tael:BAAALAAECgEIAQAAAA==.Tangylizard:BAAALAAECgUICQAAAA==.Tattoospyder:BAAALAAECgYIDgAAAA==.Tatyanafour:BAAALAADCgcICAAAAA==.Tatyanathirt:BAAALAADCggIDQAAAA==.',Te='Tekton:BAAALAADCgMIAwAAAA==.Tercesx:BAAALAAECgEIAQAAAA==.',Th='Thruul:BAAALAAECgYIDAAAAA==.',Ti='Tiklemefelmo:BAAALAADCggIDwAAAA==.Timmy:BAAALAAECgYIBgAAAA==.Tinapay:BAAALAADCgcIBwAAAA==.Tinypipi:BAAALAADCgMIAwAAAA==.',To='Torgoth:BAAALAAECgEIAQAAAA==.Toshido:BAAALAADCgEIAQAAAA==.',Tr='Traetor:BAAALAAECgUICQAAAA==.',Ug='Uggs:BAAALAADCggIFAAAAA==.',Ul='Ultane:BAAALAADCgUICAAAAA==.Ultragohan:BAAALAADCgMIAwAAAA==.',Un='Underlok:BAAALAAECgEIAQAAAA==.',Ut='Utterpuncher:BAAALAADCgcIBwAAAA==.',Va='Valastras:BAAALAADCggIFAAAAA==.Valiantaine:BAAALAAECgcIDQAAAA==.Valiantrain:BAAALAADCgYIBgABLAAECgcIDQABAAAAAA==.Valiantroar:BAAALAADCggIDgABLAAECgcIDQABAAAAAA==.',Ve='Velherun:BAAALAAECgUIBwAAAA==.Vendel:BAAALAAECgcIDQAAAA==.Vendeldh:BAAALAADCgUIBQABLAAECgcIDQABAAAAAA==.Veni:BAAALAAECgcIDQAAAA==.Vexxaa:BAAALAAECgMIBAAAAA==.',Vi='Vi:BAAALAAECgUICgABLAAECgYIDAABAAAAAA==.Virajr:BAAALAADCggIDwAAAA==.Vistine:BAAALAAECgEIAQAAAA==.',We='Wendy:BAAALAADCgYIBgAAAA==.',Wi='Wildigosa:BAAALAAECgMIBQAAAA==.Winkster:BAAALAAECgcIDQAAAA==.Winnie:BAAALAAECgEIAgAAAA==.',Wu='Wuxutain:BAAALAADCggIDwAAAA==.',Xd='Xdynasty:BAABLAAECoEUAAIFAAcIpB+lCwBlAgAFAAcIpB+lCwBlAgAAAA==.',Xo='Xo:BAAALAAECgYIDAAAAA==.',Xy='Xyfarion:BAAALAADCgcIDgAAAA==.',Ye='Yeast:BAAALAAECgUIBgAAAA==.',Za='Zabazz:BAAALAAECgUICAAAAA==.Zabenir:BAAALAAECgMIBQAAAA==.Zaraina:BAAALAAECgMIBQAAAA==.',Ze='Zerokiaa:BAAALAAECgMIBQAAAA==.',['Âm']='Âmy:BAAALAADCggICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end