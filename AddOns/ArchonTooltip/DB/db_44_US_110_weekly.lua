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
 local lookup = {'Monk-Windwalker','Unknown-Unknown','Druid-Balance','Shaman-Restoration','Warlock-Demonology','Monk-Brewmaster','DeathKnight-Frost','Hunter-BeastMastery','Priest-Holy','Priest-Shadow',}; local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abuki:BAAALAAECgMIBQAAAA==.',Ae='Aethir:BAAALAADCgEIAQAAAA==.',Ag='Agua:BAAALAADCgcIBwAAAA==.',Ak='Akagane:BAAALAADCggICwAAAA==.Akalla:BAAALAADCgcIBwAAAA==.',Al='Alfuric:BAAALAADCggICwAAAA==.Altercation:BAAALAADCgcIBQAAAA==.Althraniir:BAAALAADCggIEAAAAA==.Aly:BAAALAAECgYICwAAAA==.',Am='Amorsith:BAAALAADCgYICQAAAA==.Amyst:BAAALAAECgMICQAAAA==.',An='Aneyna:BAAALAADCgEIAQAAAA==.Angryfox:BAAALAAECgEIAQAAAA==.Animuggus:BAEALAADCgcIBwAAAA==.Anjunabeets:BAAALAAECgYIBwAAAA==.Anthran:BAAALAAECgcIDgAAAA==.',Ao='Ao:BAAALAADCggICAAAAA==.',Ap='Applebottom:BAAALAADCgcIBQAAAA==.',Ar='Arcscyth:BAAALAADCgcIBwAAAA==.Aren:BAAALAADCgYIBgAAAA==.',As='Astrobear:BAAALAADCgIIAgAAAA==.',At='Attia:BAAALAADCggICAAAAA==.',Ba='Balgith:BAAALAAECgMIAwAAAA==.Balrus:BAAALAADCgMIAwAAAA==.Bastid:BAAALAADCggIDQAAAA==.',Be='Bearshäre:BAABLAAECoEiAAIBAAgIkx3oBACzAgABAAgIkx3oBACzAgAAAA==.Beasthandle:BAAALAAECgYICAAAAA==.Bellianna:BAAALAADCgEIAQABLAAECgEIAQACAAAAAA==.Beoron:BAAALAAECgcIEAAAAA==.Bettyßastion:BAAALAAECgMIAwAAAA==.',Bi='Big:BAAALAADCgcIDQAAAA==.Bigflex:BAAALAAECgEIAQAAAA==.Bizi:BAAALAAECgIIAgAAAA==.',Bl='Blastrakhan:BAAALAAECgcIEAAAAA==.Blodreina:BAAALAADCggICAAAAA==.Bloodbather:BAAALAAECgYIBgAAAA==.',Br='Brageus:BAAALAADCgYIBgAAAA==.Brontag:BAAALAADCgcIBwAAAA==.Brughar:BAAALAADCgcIBwAAAA==.Bruus:BAAALAADCggIBwAAAA==.',Bu='Busterbrown:BAAALAADCggIDwAAAA==.',By='Byrnholf:BAAALAADCggICAAAAA==.',Ca='Calißoy:BAAALAADCggIDQAAAA==.Canekii:BAAALAAECgMIAwAAAA==.Cathrîne:BAAALAADCggIDQAAAA==.',Ce='Cervantés:BAAALAADCgQIBAAAAA==.',Ch='Chaboomy:BAEBLAAECoEXAAIDAAgIwyBpBgDfAgADAAgIwyBpBgDfAgAAAA==.Cheezypal:BAAALAADCgcIBQAAAA==.',Ci='Cindre:BAABLAAECoEXAAIEAAgIWRwyDQBRAgAEAAgIWRwyDQBRAgAAAA==.Cingz:BAABLAAECoEWAAIEAAgIKBP+HwC7AQAEAAgIKBP+HwC7AQAAAA==.',Cl='Clintopolis:BAAALAADCgcIBQAAAA==.Clunkage:BAAALAADCgcIBwAAAA==.',Co='Collie:BAAALAAECgcIEAAAAA==.Corpsman:BAAALAAECgYICgAAAA==.',Cr='Critwithabow:BAAALAAECgEIAQAAAA==.Croissant:BAAALAAECgYIDgAAAA==.',Cy='Cycko:BAAALAAECgMIBgAAAA==.',Da='Dangerdoc:BAAALAAECgcIDQAAAA==.Darkis:BAAALAAECgQIBAAAAA==.Darkseph:BAAALAADCgUIBwABLAADCgcICgACAAAAAA==.',De='Deathsteak:BAAALAADCgIIAgAAAA==.Delessia:BAAALAADCggIEwAAAA==.Demonologist:BAAALAADCgQIBAAAAA==.Demonsraph:BAAALAADCggICQAAAA==.Deo:BAAALAAECgcIEAAAAA==.Depthcharge:BAAALAADCgEIAQAAAA==.',Di='Diplodotocus:BAAALAADCgcIBwAAAA==.Disastrous:BAAALAAECgcIEAABLAAECgcIEAACAAAAAA==.Disperse:BAAALAADCgcICQAAAA==.Distraction:BAAALAADCggIDwAAAA==.Divinesloth:BAAALAAECgcIEAAAAA==.',Do='Dookie:BAAALAADCggIEgAAAA==.Doomangel:BAAALAADCgcIBwAAAA==.Downbad:BAAALAAECgMIBQAAAA==.',['Dø']='Døc:BAAALAADCgcIBwABLAAECgcIDQACAAAAAA==.',Ea='Eaghlan:BAAALAAECggICwAAAA==.',Ed='Eddie:BAAALAADCggIDQAAAA==.',Eg='Eggwhites:BAAALAAECgEIAQAAAA==.',Ei='Eielmolate:BAABLAAECoEXAAIFAAgILiIZAQCrAgAFAAgILiIZAQCrAgAAAA==.',En='Enimed:BAAALAAECgcIEAAAAA==.',Er='Erilea:BAAALAADCgYIBgAAAA==.',Es='Esbern:BAAALAADCgUIBQAAAA==.Eski:BAAALAADCgYIBgABLAAECgYIDAACAAAAAA==.',Fa='Farfik:BAAALAADCgYIBgABLAAECgYIDgACAAAAAA==.Fatherseph:BAAALAADCgcICAABLAADCgcICgACAAAAAA==.',Fe='Feldestro:BAAALAADCggIEQAAAA==.',Fi='Fisterdobble:BAAALAAECgcIEAAAAA==.',Fl='Flasheiel:BAAALAADCgMIAwABLAAECggIFwAFAC4iAA==.Flesh:BAAALAADCggICAAAAA==.Fleurdelys:BAAALAADCggIDQAAAA==.',Fo='Forestpump:BAAALAAECgQIBgAAAA==.Forgedd:BAAALAADCgcIBQAAAA==.Forgeddemon:BAAALAAECgcIEAAAAA==.Forkinaround:BAAALAAECgMIAwAAAA==.Foxysham:BAAALAADCgIIAgAAAA==.',Fr='Frostbanshee:BAAALAADCggICAAAAA==.Frostborne:BAAALAAECgEIAQAAAA==.Frostheart:BAAALAAECgYIBwAAAA==.Frostina:BAAALAADCggIDgAAAA==.',['Fé']='Féannas:BAAALAAECgUICQAAAA==.',Ga='Galebrew:BAAALAADCgYIBgAAAA==.',Ge='Geezergrass:BAAALAAECgQIBAAAAA==.Geezermonk:BAAALAAECgEIAQAAAA==.',Gh='Ghamik:BAAALAADCgcIBwAAAA==.',Gi='Girouxh:BAAALAAECgEIAQAAAA==.',Go='Goldeen:BAAALAAECgcIEwAAAA==.',Gr='Grackalackin:BAAALAAECgIIAgAAAA==.Gravytrain:BAAALAADCgYIBgAAAA==.Gruvac:BAAALAADCgUIBQABLAADCgcICgACAAAAAA==.',Gu='Gulaj:BAAALAADCggIDwAAAA==.Gumdrops:BAAALAAECgEIAQAAAA==.',Ha='Hanada:BAAALAAECgYICgAAAA==.',He='Healgimp:BAAALAAECgYICAAAAA==.',Ho='Hope:BAAALAAECgYIDwAAAA==.Hortzel:BAAALAADCgcIBwAAAA==.Howdoiheal:BAAALAAECgcIEAAAAA==.Howdoitotem:BAAALAADCgQIBAABLAAECgcIEAACAAAAAA==.',Hu='Huntus:BAAALAAECgcIEAAAAA==.',Ic='Icy:BAAALAADCgcIBwAAAA==.',Il='Illidurr:BAAALAADCgcIBwAAAA==.',Im='Immersa:BAAALAAECgYIBgAAAA==.',In='Indacookie:BAAALAAECgIIAwAAAA==.Indadeath:BAAALAAECgYIBgAAAA==.Inzili:BAAALAAECggIBgAAAA==.',Ja='Jabtath:BAAALAAECgYIDgAAAA==.Jakamu:BAAALAADCgYIBwAAAA==.Janga:BAAALAAECgMICAAAAA==.',Je='Jellibean:BAAALAADCggIDAAAAA==.',Ji='Jibjabjibjab:BAAALAAECgcIDAAAAA==.Jimm:BAABLAAECoEVAAIGAAgIZQgsDwBBAQAGAAgIZQgsDwBBAQAAAA==.',Jo='Johnnypizza:BAAALAADCggICAAAAA==.',Ju='Judge:BAAALAAECgMIBQAAAA==.Juroda:BAAALAADCgcIBwABLAADCgcICgACAAAAAA==.',Ka='Kalaina:BAAALAADCgUIBQAAAA==.Kazath:BAAALAADCgUIBQAAAA==.',Ke='Kelchi:BAAALAADCgEIAQAAAA==.Keranos:BAAALAADCgcIDQAAAA==.Kerizan:BAABLAAECoEXAAIHAAgILiNxCADuAgAHAAgILiNxCADuAgAAAA==.',Kf='Kfp:BAAALAAECgEIAQAAAA==.',Ki='Kidslaps:BAAALAADCggIDwAAAA==.',Ko='Koffeebean:BAAALAAECgYICAAAAA==.',Ku='Kurisutina:BAAALAAECgYIDAAAAA==.',La='Lafiel:BAAALAAECgIIAgAAAA==.',Le='Leethalfu:BAAALAAECgIIAwAAAA==.Leethalrot:BAAALAADCgYIBgABLAAECgIIAwACAAAAAA==.Lefunbags:BAAALAAECgcIEAAAAA==.Lemegegen:BAAALAAECgcIEAAAAA==.',Li='Liftborne:BAAALAAECgMIAwAAAA==.',Lo='Lopen:BAAALAAECgcIDAAAAA==.',Lt='Ltsurge:BAAALAAECgcIDAAAAA==.',Lu='Luceean:BAAALAADCgUIBQAAAA==.Luxmunkii:BAAALAADCgUIBQAAAA==.',Ly='Lyxxie:BAAALAAECgcIEAAAAA==.',Ma='Machommy:BAAALAADCgcIBwAAAA==.Magentic:BAAALAAECggIEAAAAA==.Mageus:BAAALAADCgYIBgAAAA==.Mainpulse:BAAALAADCgEIAQAAAA==.Martyr:BAAALAAECgMIBQABLAAECgcIDwACAAAAAA==.',Me='Metsutan:BAAALAAECgcIEAAAAA==.',Mi='Minideath:BAAALAAECgEIAQAAAA==.Mixlife:BAAALAADCgcIEQAAAA==.',Mo='Mog:BAAALAAECgUIBwAAAA==.Molathom:BAAALAADCgYIBgAAAA==.Monkslux:BAAALAAECgYIBwAAAA==.Moskeebee:BAABLAAECoEWAAIIAAgICCXgAQBXAwAIAAgICCXgAQBXAwAAAA==.',['Mâ']='Mâtthêw:BAAALAADCggICAAAAA==.',Na='Nakedlobster:BAAALAAECgcICgAAAA==.',Ne='Nedyost:BAAALAAECgEIAQAAAA==.Nekromant:BAAALAAECgYICgAAAA==.Nemriel:BAAALAADCgYIBgAAAA==.',No='Nohric:BAAALAAECgYICQAAAA==.Norsem:BAAALAADCggIDwAAAA==.',Om='Ommoran:BAAALAADCgcIBwAAAA==.',On='Onfleek:BAAALAAECgEIAQAAAA==.',Or='Orakrak:BAAALAAECggICQAAAA==.Orcmachine:BAAALAAECgMIAwAAAA==.',Ou='Ouchyfixer:BAAALAADCggIEQAAAA==.',Pa='Paladian:BAAALAADCgYICgAAAA==.Pallom:BAAALAAECgMIAwAAAA==.Pandoodoo:BAAALAADCgUIBgABLAADCgYICgACAAAAAA==.Parra:BAAALAAECgYIDgAAAA==.Parstout:BAAALAAECgcICgAAAA==.Pawsitivity:BAAALAAECgcIEAAAAA==.',Pd='Pdbm:BAAALAADCgEIAQAAAA==.',Pe='Peut:BAAALAADCggIDwAAAA==.',Ph='Physix:BAAALAADCgcIBwAAAA==.',Pl='Plagued:BAAALAAECggIEgAAAA==.',Po='Porkins:BAAALAAECgcIEAAAAA==.',Pr='Priestus:BAAALAADCggIDgAAAA==.Primeslice:BAAALAADCgYIBgABLAAECgcIEAACAAAAAA==.',Py='Pyraxx:BAAALAAECgQIBwAAAA==.',Qt='Qtip:BAAALAADCgUIBQAAAA==.',Qu='Quillvo:BAAALAADCggIDQAAAA==.',Ra='Rahnd:BAAALAADCgcIBwAAAA==.Rayjax:BAAALAADCgcIBwAAAA==.Raìdèn:BAAALAADCggIFAAAAA==.',Re='Reacharond:BAAALAAECgEIAQAAAA==.Resisted:BAABLAAECoEXAAMJAAgIGRu2CgCAAgAJAAgIGRu2CgCAAgAKAAEIYAfvTAA3AAAAAA==.Rewcore:BAAALAAECgcIBwAAAA==.',Ro='Rotboi:BAAALAAECgcIDgAAAA==.',Ru='Ruintofurrys:BAAALAADCggIDQAAAA==.',Ry='Ryanqt:BAAALAAECgcIEAAAAA==.Ryri:BAAALAAECgUIDAAAAA==.',Sa='Sacrillege:BAAALAADCgcIDwAAAA==.Sahaquiel:BAAALAADCgcIBwAAAA==.Samavati:BAAALAAECgMIAwAAAA==.Sarah:BAAALAAECgUIBQAAAA==.Sarge:BAAALAADCgYIDAAAAA==.Sassyface:BAAALAAECgcIEAAAAA==.Saveena:BAAALAADCgcIBQAAAA==.Sawk:BAAALAAECgMIAwAAAA==.',Sc='Scottybones:BAAALAAECgIIBQAAAA==.',Se='Septimog:BAAALAADCgcIBwAAAA==.',Sh='Shanalister:BAAALAADCggICwAAAA==.',Si='Sibbrena:BAAALAAECgQIBwAAAA==.Sipep:BAAALAADCgcIBwAAAA==.',Sl='Sleepymunk:BAAALAAECgEIAQAAAA==.',Sm='Smellsgreat:BAAALAAECgcIDgAAAA==.Smunk:BAAALAADCggIDwAAAA==.',So='Soltohein:BAAALAADCgEIAQAAAA==.Soulfire:BAAALAADCggIDwAAAA==.',Sp='Spleen:BAAALAADCggIDwAAAA==.Sporki:BAAALAADCgcIBwAAAA==.Sprisepickle:BAAALAAECgcIDQAAAA==.',St='Starella:BAAALAAECgMIAwAAAA==.Steamlock:BAAALAAECgMIAgAAAA==.Steamsham:BAAALAAECgEIAQABLAAECgMIAgACAAAAAA==.Stellar:BAAALAADCgYIBgAAAA==.Steveseagal:BAAALAADCgYICAAAAA==.',Su='Sugarpop:BAAALAADCggICAAAAA==.Superlame:BAAALAADCggIDwAAAA==.',Sw='Swiper:BAAALAAECgcIDwAAAA==.',Sy='Synecgos:BAAALAADCgcIDAAAAA==.',Ta='Tazath:BAAALAAECgUIBQABLAAECgcIEAACAAAAAA==.',Th='Theory:BAAALAAECgIIAgAAAA==.Theradric:BAAALAADCgYICwAAAA==.',Ti='Tihani:BAAALAADCgQIBAAAAA==.Tilambucano:BAAALAADCgIIAQAAAA==.',Tr='Treevive:BAAALAAECgcICQAAAA==.',Tw='Twojoints:BAAALAAECgMIAwAAAA==.Twoports:BAAALAAECgIIAwABLAAECgMIAwACAAAAAA==.',Ul='Ullirus:BAAALAADCgYIBgAAAA==.Ultima:BAAALAADCgQIBAAAAA==.',Un='Unshookable:BAAALAAECgYICgAAAA==.',Va='Valiantinter:BAAALAADCgMIAwAAAA==.',Ve='Velria:BAAALAAECgUICAAAAA==.Vermax:BAAALAAECgMIAwAAAA==.',Vi='Violetshammy:BAAALAAECgcICwAAAA==.Viviera:BAAALAADCgcICgAAAA==.',Vo='Voidlockus:BAAALAADCgYICQAAAA==.',Wh='Whimsy:BAAALAADCggIDgAAAA==.Whyz:BAAALAADCggIFgAAAA==.',['Wí']='Wíllíam:BAAALAAECgYIEAAAAA==.',Xa='Xalacrack:BAAALAADCgEIAgAAAA==.',Xi='Xiaomaomi:BAEALAADCgcICQAAAA==.',Xy='Xyfin:BAAALAAECgYICgAAAA==.',Xz='Xziron:BAAALAAECgYIBwAAAA==.',Za='Zaboo:BAAALAADCgYIBgAAAA==.Zacattack:BAAALAADCgMIBAABLAADCgYICgACAAAAAA==.Zacopoodyy:BAAALAADCgIIAgAAAA==.Zandramadas:BAAALAAECgcIEAAAAA==.Zaraline:BAAALAAECgMIAwAAAA==.',Ze='Zenhunter:BAAALAADCgcIBgAAAA==.Zeolock:BAAALAAECgYICgAAAA==.',Zi='Zipzoop:BAAALAADCgcIBQAAAA==.',Zo='Zoomiez:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end