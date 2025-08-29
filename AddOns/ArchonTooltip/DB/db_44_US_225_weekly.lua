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
 local lookup = {'Unknown-Unknown','Warlock-Destruction','Monk-Windwalker','Warrior-Fury','Warrior-Arms','Druid-Balance','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Priest-Discipline',}; local provider = {region='US',realm='Trollbane',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adomar:BAAALAADCgUICAAAAA==.',Ag='Aggrum:BAAALAAECgUIBQAAAA==.',Ah='Ahzek:BAAALAADCgMIAwAAAA==.',Ai='Aidren:BAAALAAECgYICAAAAA==.Aieral:BAAALAADCgcIBwAAAA==.Aiur:BAAALAAECgIIAwAAAA==.',Ak='Akredfox:BAAALAAECgIIAgAAAA==.',Al='Alainna:BAAALAAECgQIBQAAAA==.Alchesay:BAAALAAECgYIDAAAAA==.Aldri:BAAALAADCggICwABLAAECgYIDAABAAAAAA==.Alicedelight:BAAALAAECgIIAgAAAA==.Alinare:BAAALAADCgYIBAAAAA==.Alpips:BAAALAADCgYIBgAAAA==.',Am='Amabeast:BAAALAAECgYICgAAAA==.Amisia:BAAALAAECgIIAgAAAA==.Amoran:BAAALAAECgMIAwAAAA==.',An='Anamira:BAAALAADCgcIBwAAAA==.Anathas:BAAALAAECgMIBQAAAA==.Ancestor:BAAALAADCggIDgAAAA==.Ango:BAAALAAECgYICgAAAA==.Angoa:BAAALAADCgcICgABLAAECgYICgABAAAAAA==.Angrybeavor:BAAALAAECgUICAAAAA==.Aniistea:BAAALAADCgcIDgAAAA==.Annu:BAAALAADCgIIAgABLAADCgcIEQABAAAAAA==.Antiodney:BAAALAAFFAIIAgAAAA==.Anzrack:BAAALAADCgcIBwAAAA==.',Ap='Apocalypse:BAAALAAECgMIAwABLAAECgYIBgABAAAAAA==.',Ar='Arcadion:BAAALAAECgIIAgAAAA==.Arcanenine:BAAALAAECgUIBgAAAA==.Arenahawke:BAAALAAECgIIAgAAAA==.Arkevna:BAAALAADCgcIDgAAAA==.Arkki:BAAALAAECgMIBQAAAA==.Arktieus:BAAALAADCgYIBgAAAA==.Arsy:BAAALAAECgYICAAAAA==.Artichoke:BAAALAADCggIAQABLAAECgIIAwABAAAAAA==.',As='Ashidora:BAEALAAECgMIAwAAAA==.Ashtoreth:BAAALAAECgEIAQAAAA==.Ashx:BAAALAADCgcICwAAAA==.Assukun:BAAALAAECgMIBwAAAA==.',Au='Aurezia:BAAALAAECgQIBgAAAA==.',Ax='Axelr:BAAALAAECgcIDwAAAA==.Axxerii:BAAALAAECgIIAgAAAA==.',Az='Azeritepower:BAAALAAECgYIDAAAAA==.Azmodel:BAAALAADCgQIBAAAAA==.Azraman:BAAALAADCggICAAAAA==.',Ba='Baddmojo:BAAALAAECgUICQAAAA==.Badmac:BAAALAAECgcIEAAAAA==.Baekn:BAAALAAECggICAAAAA==.Baellini:BAAALAAECgUIBwAAAA==.Baium:BAAALAAECgIIAgAAAA==.Bakora:BAAALAADCgUICQAAAA==.Ballzee:BAAALAADCgIIAgAAAA==.Banishedbull:BAAALAADCgEIAQABLAAECgMIBQABAAAAAA==.Banishedfate:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Banishedholy:BAAALAAECgMIBQAAAA==.',Be='Beary:BAAALAADCgQIBAAAAA==.Beastboi:BAAALAAECgIIBAAAAA==.Belbert:BAAALAAECgMIBAAAAA==.Bercouli:BAAALAADCgYIBgAAAA==.Berry:BAAALAAECggIDQAAAA==.Besneakies:BAAALAAECgMIBwAAAA==.',Bi='Biaxident:BAAALAAECgYIBgAAAA==.Bigblackwick:BAAALAAECgQIBwAAAA==.Binnah:BAAALAADCggIEgAAAA==.Bitzy:BAABLAAECoEXAAICAAcIxgSKMAA4AQACAAcIxgSKMAA4AQAAAA==.',Bl='Blackfang:BAAALAAECgEIAQABLAAECgUIBQABAAAAAA==.Bless:BAAALAADCgcIDAAAAA==.Blindside:BAAALAADCggIDAABLAAECgYIBgABAAAAAA==.Blknsty:BAAALAADCggICAAAAA==.Bloodgaze:BAAALAAECgMIBAAAAA==.',Bo='Bovinna:BAAALAADCgcIEwAAAA==.Boxeybrown:BAAALAAECgQIBgAAAA==.Bozanjorn:BAAALAAECgYICAAAAA==.',Br='Breccia:BAAALAAECgEIAQAAAA==.Brotherchaos:BAAALAADCggIDwAAAA==.Brutanious:BAAALAADCgcIDQAAAA==.',Bu='Buffwarrior:BAAALAAECgMIBgAAAA==.Buk:BAAALAADCgYIBgAAAA==.Butterface:BAAALAAECgIIAwAAAA==.Buuruug:BAAALAADCgcIEQAAAA==.',Ca='Cabbagebroth:BAAALAAECgYICQAAAA==.Calicey:BAAALAADCgcIBwAAAA==.Cambuchatea:BAAALAAFFAIIAgAAAA==.Candycanes:BAAALAAECgMIBAAAAA==.Cantmilkem:BAAALAAECgYIBwAAAA==.Capellaz:BAAALAAECgIIAgAAAA==.Carnage:BAAALAAECgYIBgAAAA==.Castiann:BAAALAADCgYIBgAAAA==.Catchhands:BAAALAAECgEIAQABLAAECgUICAABAAAAAA==.',Ce='Celerynn:BAAALAAECgIIAgAAAA==.Celestaine:BAAALAADCgcIBwAAAA==.Celydrea:BAAALAAECgMIAwAAAA==.',Ch='Chamantha:BAAALAAECgMIAwAAAA==.Chawpa:BAAALAADCgMIAwAAAA==.Cheetohpuff:BAAALAADCgQIBAAAAA==.Chicho:BAAALAADCgcIBwAAAA==.Chiwhiz:BAAALAADCggIEgAAAA==.',Cl='Clarrisse:BAAALAADCgcICQABLAAECgQIBgABAAAAAA==.',Co='Cocaineclaw:BAAALAADCgYICwAAAA==.Coorsenjoyer:BAAALAAECgcIEAAAAA==.Coorslite:BAAALAADCgYIBgABLAAECgcIEAABAAAAAA==.Corthechosen:BAAALAAECgYIBgAAAA==.Cosmo:BAAALAAECgUIBQAAAA==.Cowler:BAAALAAECgMIBwAAAA==.Cowmbustion:BAAALAAECgIIAgAAAA==.',Cr='Crippyclaw:BAAALAAECgIIAgABLAAECgUICgABAAAAAA==.Crippyx:BAAALAAECgUICgAAAA==.Crippyy:BAAALAADCggIDAABLAAECgUICgABAAAAAA==.Cruelshaman:BAAALAAECgYICwABLAAECgYIDAABAAAAAA==.Cryppi:BAAALAADCgUIBQABLAAECgUICgABAAAAAA==.Crysis:BAAALAAECgIIAwAAAA==.',Cu='Cured:BAAALAADCgYIBgAAAA==.',['Cä']='Cästíel:BAAALAADCgQIBAAAAA==.',Da='Dageron:BAAALAADCggIEwABLAAECggICAABAAAAAA==.Daggoth:BAAALAAECgMIAwAAAA==.Dalinyth:BAAALAAECgQIBQAAAA==.Dalrak:BAAALAAECgcIEAAAAA==.Damp:BAAALAADCgcICAAAAA==.Dandelion:BAAALAAECggICgAAAA==.Dangercakes:BAAALAADCgcIBwABLAAFFAIIAgABAAAAAA==.Dante:BAAALAADCgUICQAAAA==.Darkenling:BAAALAAECggICAAAAA==.Darkothy:BAAALAAECgUICQAAAA==.Dasdann:BAAALAADCggICAAAAA==.Datbuddy:BAAALAADCgQIBAAAAA==.Datdude:BAAALAADCgMIAwAAAA==.Datis:BAAALAAECgEIAQAAAA==.Datshammy:BAAALAADCgcICQAAAA==.Datvoodoomon:BAAALAAFFAIIAgAAAA==.Daïn:BAAALAAECgEIAQAAAA==.',De='Deadboii:BAAALAADCggICAAAAA==.Deafnite:BAAALAADCggICQAAAA==.Deathlok:BAAALAAECgYIBgAAAA==.Deathtoaxe:BAAALAADCggICAABLAAECgYICwABAAAAAA==.Deleralia:BAAALAAECgYIDAAAAA==.Demonclover:BAAALAAECgUIBQAAAA==.Demonwoolf:BAAALAADCgEIAQAAAA==.Devonia:BAAALAAECgIIAgAAAA==.',Di='Dieric:BAAALAADCggIFwAAAA==.Digbam:BAAALAAECggIAQAAAA==.Dimsum:BAAALAADCgcIBwAAAA==.Dinkle:BAAALAADCgQIBAAAAA==.Dionea:BAAALAADCgIIAgAAAA==.Divinetroll:BAAALAAECgYICQAAAA==.',Do='Doggestyle:BAAALAAECgMIAwAAAA==.Dorastrain:BAAALAAECgcIEAAAAA==.Dorime:BAAALAAECgQIBwAAAA==.',Dr='Dracovoid:BAAALAADCgcIEQABLAAECgUICAABAAAAAA==.Dragin:BAAALAAECgMIBQAAAA==.Dragonsage:BAAALAADCgUICAAAAA==.Dragonwyck:BAAALAAECgIIAgAAAA==.Dragooncawk:BAAALAADCgcICQAAAA==.Drizzella:BAAALAAECgMIBgAAAA==.Drkknife:BAAALAADCggIAQAAAA==.Dryrub:BAAALAAECgEIAgABLAAECgcIEAABAAAAAA==.',Du='Ducklow:BAAALAAECgMIBwAAAA==.Ducksalot:BAAALAAECgIIAgAAAA==.Durenree:BAAALAADCgUIBQAAAA==.Durkk:BAAALAADCgEIAQAAAA==.',Dx='Dxmonjay:BAAALAAECgIIAgAAAA==.',['Då']='Dåjizzler:BAAALAADCgcIDgAAAA==.',['Dì']='Dìabetus:BAAALAADCgcIBwAAAA==.',Ec='Eckko:BAAALAADCgMIAwAAAA==.',Eg='Egamegam:BAAALAAECgIIAgABLAAECgIIAwABAAAAAA==.',El='Eld:BAAALAADCgUIBwAAAA==.Eleman:BAAALAAECgQICAAAAA==.Elementalsha:BAAALAAECgEIAQAAAA==.Elfclover:BAAALAAECgYIEAAAAA==.Elijahx:BAAALAAECgYICAAAAA==.Eljayye:BAAALAADCggIEgAAAA==.Elva:BAAALAAECgIIAgAAAA==.',Em='Emisha:BAAALAADCggIEAAAAA==.Emmshunter:BAAALAAECgIIAwAAAA==.',En='Enthea:BAAALAADCgcIDgAAAA==.Envi:BAAALAADCgIIAwAAAA==.',Ep='Epicpal:BAAALAADCgIIAgAAAA==.Epona:BAAALAAECgQIBgAAAA==.',Er='Eraedan:BAAALAADCgIIAgAAAA==.Eresa:BAAALAADCgEIAQAAAA==.Erzá:BAAALAAECgMIBQAAAA==.',Eu='Eurodice:BAAALAADCggIEAAAAA==.',Ev='Ev:BAAALAAECgQIBgAAAA==.Eveliri:BAAALAADCgEIAQAAAA==.Evilkaren:BAAALAADCgcIDQAAAA==.Evocation:BAAALAAECgIIBAABLAAECgcIEAABAAAAAA==.',Ex='Excelcior:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.Exeçutie:BAAALAADCgEIAQAAAA==.',Fa='Falconseye:BAAALAADCgMIBQABLAADCgUIBQABAAAAAA==.Fandrael:BAAALAAECgMIAwAAAA==.Faykan:BAAALAAECgIIAgAAAA==.Faùst:BAAALAAECgYICAAAAA==.',Fe='Fedrameda:BAAALAAECgQICAAAAA==.Felix:BAAALAAECgMIAwAAAA==.Fennil:BAAALAAECgMIBQAAAA==.',Fl='Flexus:BAAALAAECgMIBAAAAA==.Flintstones:BAAALAAECgcICwAAAA==.',Fo='Fowlplay:BAAALAADCggICgAAAA==.',Fr='Frankenstacy:BAAALAAECgMIAwAAAA==.Freewaterfoo:BAAALAADCgQIBAABLAAECgYIBwABAAAAAA==.',Fu='Fuegodiego:BAAALAADCgcIBwAAAA==.Fujee:BAAALAAECgQICAAAAA==.Funkyt:BAAALAAECgIIAgAAAA==.',['Fé']='Fénrír:BAAALAADCgIIAgAAAA==.',Ga='Garrod:BAAALAAECgMIAwAAAA==.Gattsu:BAAALAADCgQIBAAAAA==.',Ge='Genisìs:BAAALAAECgQICAAAAA==.Gennil:BAAALAAECgcIEQAAAA==.',Gi='Gilgarond:BAAALAAECgYICQABLAADCggIDgABAAAAAA==.',Gl='Glascz:BAAALAAECgUIBQAAAA==.',Gn='Gnomedruid:BAAALAADCgUIBQAAAA==.Gnomerbella:BAAALAADCgcIDwAAAA==.',Go='Goblintopher:BAAALAADCgcICgAAAA==.Gorgrin:BAAALAADCgcIBwAAAA==.Gormash:BAABLAAECoEUAAIDAAgIUx8BBgCMAgADAAgIUx8BBgCMAgAAAA==.Gorrax:BAAALAADCggIDwAAAA==.',Gr='Greyseer:BAAALAAECgIIAgAAAA==.Grica:BAAALAADCgUIBQAAAA==.Grumpybrews:BAAALAAECgEIAQABLAAECgYIDAABAAAAAA==.Grumpyroots:BAAALAAECgUIBgABLAAECgYIDAABAAAAAA==.Grumpytusk:BAAALAAECgYIDAAAAA==.Gryphonheart:BAAALAADCgUIBQAAAA==.',Gu='Guladis:BAAALAADCgEIAQAAAA==.Gunchiggins:BAAALAAECgYICQAAAA==.Guymontag:BAAALAAECgQIBgAAAA==.',['Gä']='Gändalf:BAAALAAECgEIAQAAAA==.',Ha='Hadriel:BAAALAAECgMIAwAAAA==.Halal:BAAALAADCggIDgAAAA==.Hana:BAAALAADCgMIAwAAAA==.Harbard:BAAALAADCggICAAAAA==.Harlowx:BAAALAADCggIDgAAAA==.Hawthorne:BAAALAADCgcIBwAAAA==.',He='Heaf:BAABLAAECoEXAAMEAAgI4CGhCwCoAgAEAAgIux6hCwCoAgAFAAEITCToEgBRAAAAAA==.Heal:BAAALAAECgQICgAAAA==.Healz:BAAALAAECgYICgAAAA==.Hedgewitch:BAAALAADCgMIAwAAAA==.Helort:BAAALAADCggIDgABLAAECgEIAQABAAAAAA==.',Hi='Hiiro:BAAALAADCgcIDQAAAA==.Hijinkz:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.Hikons:BAAALAAECgYICQAAAA==.Hippierage:BAAALAADCgIIAgAAAA==.',Ho='Hobbits:BAAALAADCggICQAAAA==.Honsta:BAAALAADCgQIBAAAAA==.Hopcrush:BAAALAADCgYICwAAAA==.Hopstop:BAAALAAECgIIAgAAAA==.Hotscales:BAAALAADCgcICQABLAAFFAMIBQAGAJkgAA==.',Hu='Hugo:BAAALAAECgUIDAAAAA==.Hurding:BAAALAAECgcIEAAAAA==.Huwglyndur:BAAALAAECgIIAgAAAA==.',['Hå']='Håyhå:BAAALAADCgYIBgAAAA==.',Ia='Ianar:BAAALAADCgMIBAAAAA==.Iannis:BAAALAADCgEIAQAAAA==.',Ib='Ibiswar:BAAALAADCgIIAgAAAA==.',Ic='Icypop:BAAALAADCgIIAgABLAAECgUICgABAAAAAA==.',Id='Idispizhorde:BAAALAAECgcIEAAAAA==.',Il='Illissia:BAAALAADCgQIBgAAAA==.',Im='Imizael:BAAALAAECgUIBwAAAA==.',In='Infinis:BAAALAAECgEIAQAAAA==.',Ir='Ironbrew:BAAALAADCgEIAQAAAA==.Ironpreacher:BAAALAADCggIEAAAAA==.',Is='Isolie:BAAALAADCgMIAwAAAA==.Isseult:BAAALAADCgQIBAAAAA==.',Iv='Ivok:BAAALAADCgMIAwAAAA==.',Iz='Izabellä:BAAALAADCgYIBwAAAA==.',Ja='Jackcarverb:BAAALAAECgIIAgAAAA==.Jarraid:BAAALAADCgYICgAAAA==.Jaxzz:BAAALAADCgIIAgAAAA==.',Jd='Jdubs:BAAALAADCgcIBwAAAA==.',Je='Jeerio:BAAALAAECgYICQAAAA==.Jers:BAAALAAECgMIBwAAAA==.',Ji='Jiib:BAAALAAECgMIBQAAAA==.Jilong:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.',Jk='Jkizzle:BAAALAAECgYICQAAAA==.',Jo='Jogo:BAAALAAECgMIBgAAAA==.Johnnyrotten:BAAALAADCgcIBwAAAA==.Jonile:BAAALAADCgcIEwAAAA==.Joyfulflame:BAAALAADCgcICAAAAA==.',Jr='Jrpagcu:BAAALAADCgIIAgAAAA==.',Ju='Juicyjuice:BAAALAADCgYIBwAAAA==.',['Jä']='Jäzmine:BAAALAAECgYIBgAAAA==.',['Jô']='Jôseph:BAAALAAECgIIAwAAAA==.',Ka='Kaalin:BAAALAADCgcICAAAAA==.Kabutosan:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Kailfin:BAAALAAECgMIBwAAAA==.Kamots:BAAALAAECgYIDQAAAA==.Kareokee:BAAALAAECgcIEAAAAA==.Karral:BAAALAADCggIDgAAAA==.Karronna:BAAALAADCgcICwAAAA==.Kaytopia:BAAALAADCgYIBwAAAA==.Kazdormu:BAAALAAFFAIIAgAAAA==.',Ke='Kealia:BAAALAADCgcIBwAAAA==.Keloth:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.Kenku:BAAALAAECggIDQAAAA==.Kent:BAAALAADCggICAABLAADCgYICQABAAAAAA==.Kenzee:BAAALAAECggIAgAAAA==.Kerber:BAAALAADCggIDgAAAA==.Kerrage:BAAALAAECggIAQAAAA==.Kerrval:BAAALAAECggIAgAAAA==.Keystone:BAAALAADCgYIBgAAAA==.',Ki='Kidkill:BAAALAADCgMIAwAAAA==.Killinrapidy:BAAALAADCggIDQAAAA==.Kithros:BAAALAADCgIIBAAAAA==.Kitsuki:BAAALAADCgMIAwABLAADCgcIBwABAAAAAA==.',Kn='Knokkelmann:BAAALAAECgYIDAAAAA==.Knottybits:BAAALAADCgcIDgAAAA==.',Ko='Kodera:BAAALAAECgEIAQAAAA==.Konân:BAAALAAECgMIBQAAAA==.Korvous:BAAALAADCggICQAAAA==.',Kr='Krasis:BAAALAAECgMIAwAAAA==.Kreaton:BAAALAADCggICwAAAA==.Kroger:BAAALAADCgcIDAAAAA==.Kronch:BAAALAADCgQIBAAAAA==.',Ky='Kyllïan:BAAALAADCggIEwAAAA==.',La='Lafty:BAAALAADCgIIAgAAAA==.Lamark:BAAALAADCgYIBgAAAA==.Lavi:BAAALAAECgMIBQAAAA==.',Le='Lecreme:BAAALAAECgEIAQAAAA==.Leizil:BAAALAAECgMIBwAAAA==.Lemb:BAAALAADCgcIBwAAAA==.Lennox:BAAALAAECgMIBQAAAA==.Lesaire:BAAALAADCggIDgAAAA==.Lextor:BAAALAADCgcIDQAAAA==.',Lh='Lhuani:BAAALAAECgYIBwAAAA==.',Li='Liaevel:BAAALAADCgMIAwAAAA==.Lickmyspellz:BAAALAAECgYICgAAAA==.Lightmage:BAAALAAECgEIAQABLAAFFAIIAgABAAAAAA==.Liverless:BAAALAADCggIDAABLAAECgEIAQABAAAAAA==.Lizan:BAAALAADCgMIAwAAAA==.',Ll='Llcoolfred:BAAALAADCgIIAgAAAA==.Llillianna:BAAALAADCggIDgAAAA==.',Lo='Logiteck:BAAALAADCgUICQAAAA==.Lolkitten:BAAALAADCgcICwAAAA==.Loopy:BAAALAAECgMIBQAAAA==.Lorm:BAAALAADCgcIBwAAAA==.Lougan:BAAALAAECgMIAwAAAA==.Lovely:BAAALAADCgYICAAAAA==.',Lu='Lucarien:BAAALAAECgYICQAAAA==.Luckyloa:BAAALAADCgUIBQAAAA==.',Ly='Lyev:BAAALAADCgYIBgAAAA==.Lynnel:BAAALAAECgMIBgAAAA==.',Ma='Macaria:BAAALAADCggICAABLAAECgQIBgABAAAAAA==.Maelos:BAAALAAECgcIEAAAAA==.Magnathul:BAAALAAECgcIEQAAAA==.Makeah:BAAALAAECgcIDwAAAA==.Marianne:BAAALAADCgUIDAAAAA==.Marjohunt:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Marrior:BAAALAADCgcIDgAAAA==.Maryboop:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Maulmokigg:BAAALAAECgEIAQAAAA==.Mausi:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.',Mc='Mcshaft:BAAALAADCgYICwAAAA==.',Me='Medo:BAAALAADCgIIAgAAAA==.Meisuru:BAAALAAECgQIBAAAAA==.Mekeena:BAAALAAECgEIAQAAAA==.Melesandre:BAAALAADCgcIBwAAAA==.Melidee:BAAALAAECgMIBQAAAA==.Meltdown:BAAALAAECgYICgAAAA==.Menharith:BAAALAADCggIEAAAAA==.Mesmile:BAAALAAECgMIBAAAAA==.Mesöthorny:BAAALAADCgMIAwAAAA==.',Mi='Micrømist:BAAALAADCggIDAAAAA==.Midrok:BAAALAAECgQIBgAAAA==.Mikåh:BAAALAADCggIDwAAAA==.Milanova:BAAALAAECgMIAwAAAA==.Minke:BAAALAADCgQIBAAAAA==.Miquellá:BAAALAADCgYIBgAAAA==.Miselah:BAAALAADCgcIEwAAAA==.Missfrosty:BAAALAAECgQIBQAAAA==.',Mm='Mmbhpta:BAAALAADCgcIBwAAAA==.',Mo='Mobythicc:BAAALAAECgYICwAAAA==.Moderatemufn:BAAALAAECgYIBgAAAA==.Moonboomfred:BAAALAAECgMIAwAAAA==.Moonshower:BAAALAADCgcIBwAAAA==.Mordekaiserx:BAAALAAECgQIBwAAAA==.Mordris:BAAALAADCgQIBAAAAA==.Moridwyn:BAAALAADCgcIBwAAAA==.Morrgenn:BAAALAAECgEIAQAAAA==.',Mt='Mtastyck:BAAALAAECgEIAQAAAA==.',Mu='Muggyclover:BAAALAADCgMIAwAAAA==.Munkamanbezy:BAAALAAECggIBAAAAA==.Murdiûs:BAAALAAECgYIDgAAAA==.Mutilate:BAAALAAECgcIEAAAAA==.',['Mì']='Mìlkman:BAAALAADCgYIBgAAAA==.',Na='Nacks:BAAALAAECgcICgAAAA==.Nacksp:BAAALAAECgMIAwABLAAECgcICgABAAAAAA==.',Ne='Neosuna:BAAALAAECgEIAQAAAA==.Nerotic:BAAALAAECgMIBQAAAA==.Nessië:BAAALAAECgQIBwAAAA==.Nevandelm:BAAALAAECgIIAwAAAA==.',Ni='Nimidh:BAAALAAECgcIEwAAAA==.Ninjahealer:BAAALAADCggIDAAAAA==.',No='Nochnitsa:BAAALAADCgYIBgAAAA==.Noobtotem:BAAALAADCggICwAAAA==.',Nu='Nurarose:BAAALAADCgcIDQAAAA==.Nurglé:BAAALAAECgMIBAAAAA==.',['Nì']='Nìghtmare:BAAALAAECgYICwAAAA==.',['Nî']='Nîghtwing:BAAALAADCgcIBQABLAAECgYICQABAAAAAA==.',Ob='Obnoxiousego:BAAALAAFFAIIAgAAAA==.',Od='Odarthedrake:BAAALAADCgYIBgAAAA==.Oddknee:BAAALAADCggIDQABLAAFFAIIAgABAAAAAA==.Odney:BAAALAAECgMIAwABLAAFFAIIAgABAAAAAA==.',Ol='Olivebetray:BAABLAAECoEhAAIHAAYIXxnVLQCrAQAHAAYIXxnVLQCrAQAAAA==.',On='Onionpancake:BAAALAADCgYIBgAAAA==.',Oo='Oopsybear:BAAALAAECgMIAwAAAA==.',Op='Opalrai:BAAALAAECgQIBgAAAA==.Opeline:BAAALAAECgMIAwAAAA==.',Or='Oridox:BAAALAAECgQICAAAAA==.Orumine:BAAALAAECgcIDgAAAA==.Orwan:BAAALAAECgIIAgAAAA==.',Ov='Overwherre:BAAALAAECgEIAQAAAA==.',Pa='Pachii:BAAALAADCgMIAwAAAA==.Paganagain:BAAALAADCgYICQABLAAECgMIAwABAAAAAA==.Palcan:BAAALAADCgEIAQAAAA==.Papii:BAAALAAECgEIAQAAAA==.Paratussum:BAAALAAECgUICQAAAA==.Parselock:BAAALAAECggIDQAAAA==.Pauladino:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.',Pe='Peanutpets:BAAALAADCggICAAAAA==.Petrichor:BAAALAAECgMIAwAAAA==.',Pi='Pity:BAAALAADCgUIBQAAAA==.',Pl='Plongo:BAAALAADCgIIAgAAAA==.',Po='Poi:BAAALAADCggICAAAAA==.Pokemen:BAAALAADCgYICQABLAAECgcIEAABAAAAAA==.Pollywog:BAAALAADCgMIAwABLAAECgIIAwABAAAAAA==.Poobear:BAAALAAECgYIBgAAAA==.Powertotem:BAAALAADCgQIBgAAAA==.',Pr='Predathor:BAAALAADCgcIBwAAAA==.Prollimix:BAAALAAECgEIAQAAAA==.Prîme:BAAALAAECgIIAwAAAA==.',Ps='Psychoshorts:BAAALAAECgQIBQAAAA==.',['Pä']='Pälädin:BAAALAADCgEIAQABLAAECgUIBgABAAAAAA==.Pätience:BAAALAADCggICwAAAA==.',Qu='Qualiti:BAAALAADCgUIBQAAAA==.',Ra='Rahnah:BAAALAADCgIIAgABLAAECgYICwABAAAAAA==.Raidhero:BAAALAAECgcIDgAAAA==.Raise:BAAALAAECgEIAQAAAA==.Raked:BAAALAAECgEIAgAAAA==.Rapidly:BAAALAADCgcIAgAAAA==.Raviolio:BAAALAADCggIEQABLAAECgYICQABAAAAAA==.Rayiia:BAAALAAECgMIAwAAAA==.Rayzard:BAAALAADCgcIBwAAAA==.',Re='Redmental:BAAALAADCgcIEgAAAA==.Reflection:BAAALAAECgYICwAAAA==.Refugë:BAAALAADCgcIBwAAAA==.Regicidall:BAAALAADCgcIDgAAAA==.Rekcutnerd:BAAALAAECgIIAwAAAA==.Reseal:BAAALAADCggIEAAAAA==.Reseri:BAAALAADCggICAABLAAFFAQICQAIAGAZAA==.Retiniris:BAAALAAECgQIBgAAAA==.Reweldone:BAAALAADCgcIBwAAAA==.',Rh='Rhonun:BAAALAADCggIEAAAAA==.Rhoxstar:BAAALAADCgYIBgAAAA==.',Ri='Ricecake:BAAALAAECgMIBgAAAA==.',Ro='Rockem:BAAALAAECgEIAQAAAA==.Rockhardfred:BAAALAADCgYICQAAAA==.Rom:BAAALAADCggICAAAAA==.',Ru='Rubb:BAAALAAECgIIAgAAAA==.Ruru:BAAALAADCggICAAAAA==.',Sa='Saarge:BAAALAAECgUIBQAAAA==.Saddeath:BAAALAAECgYICwAAAA==.Saeylaura:BAAALAAECgMIAwAAAA==.Salanaar:BAAALAAFFAIIAgAAAA==.Sancteum:BAACLAAFFIEJAAMIAAQIYBkmAQB3AQAIAAQIYBkmAQB3AQAJAAEI0gBRDgA+AAAsAAQKgRgAAggACAhPJegBAFUDAAgACAhPJegBAFUDAAAA.Sapdaddy:BAAALAADCgYIBgABLAAECgYIBwABAAAAAA==.Sarja:BAAALAAECgIIAgAAAA==.Sarranwrap:BAAALAADCgcIDgAAAA==.Sarzenka:BAAALAADCgUIBQAAAA==.Sathelyn:BAAALAADCggIEAAAAA==.Saurone:BAAALAAECgMIAwAAAA==.Savalinda:BAAALAADCgIIAgAAAA==.Savion:BAAALAAECgYICwAAAA==.Sayy:BAAALAAECgYIDgAAAA==.',Sc='Schronuts:BAAALAAECgcIEAAAAA==.Schutz:BAAALAADCgcICwAAAA==.Scorpionius:BAAALAAECgYIDQAAAA==.Scottyhotty:BAAALAAECgYIAwAAAA==.',Se='Segxygreen:BAAALAADCgUIBQAAAA==.Sekorkahn:BAAALAADCgUIBQAAAA==.Sekvir:BAAALAAECgUIBQAAAA==.Selindae:BAAALAADCgQIBAAAAA==.Serapheik:BAAALAAECgQICQAAAA==.Seraz:BAAALAAECgcIEQAAAA==.Serenitey:BAAALAADCgcIEQAAAA==.Sergi:BAAALAADCgcIEQAAAA==.Serraglyndur:BAAALAAECgIIAgAAAA==.',Sh='Shaddaí:BAAALAADCgEIAQAAAA==.Shamidzi:BAAALAADCggICQAAAA==.Sharaccid:BAAALAAECgYIBgAAAA==.Shifty:BAAALAADCgcICAAAAA==.Shizze:BAAALAADCgIIAgAAAA==.Shmorg:BAAALAAECgYIDgABLAADCgYICQABAAAAAA==.Shunaiman:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.',Si='Sifferr:BAAALAADCgcIDwAAAA==.Silus:BAAALAAECgEIAQAAAA==.',Sk='Skiè:BAAALAAECgIIBAAAAA==.Skyjericho:BAAALAAECgEIAQAAAA==.',Sl='Slattpal:BAAALAAECgcIEgAAAA==.Sliverstrike:BAAALAADCgcIBwAAAA==.',Sn='Snackysteak:BAEALAAECgUICAAAAA==.',So='Somallena:BAAALAADCggICAAAAA==.Somarlar:BAAALAAECgEIAQAAAA==.Somvanah:BAAALAADCgMIAwAAAA==.Sonciré:BAAALAAECgQICAAAAA==.Sopho:BAAALAAECgMIBQAAAA==.Sophoknight:BAAALAADCggICQABLAAECgMIBQABAAAAAA==.Sorcerer:BAEALAAECgIIAgAAAA==.Soulvok:BAAALAADCgYIDAAAAA==.',Sp='Spacetiger:BAAALAAECgIIAgAAAA==.Spaggers:BAAALAAECgMIAwAAAA==.Specialtea:BAAALAAECgMIBQAAAA==.Speity:BAAALAAECgYIDgAAAA==.Spencerhunt:BAAALAADCgQIBAAAAA==.Spikedice:BAAALAADCggIDgAAAA==.Spártan:BAAALAADCgcIBwAAAA==.',St='Stardos:BAAALAADCggIEAAAAA==.Starran:BAAALAADCgYIBgAAAA==.Stelia:BAAALAADCgYIBwAAAA==.Stonebones:BAAALAADCgcIDgAAAA==.Stormjibbers:BAAALAAECgYICQAAAA==.Strifex:BAAALAAECgcICgAAAA==.Stryfe:BAAALAAECgMIAwAAAA==.Stryper:BAABLAAECoEWAAIEAAgICRnfDwBkAgAEAAgICRnfDwBkAgAAAA==.',Su='Summër:BAAALAADCgYIBgAAAA==.Surâ:BAAALAAECgYIDAAAAA==.',Sw='Sweetea:BAAALAAECgQIBAAAAA==.',Sy='Syann:BAAALAADCgYIBgAAAA==.Sylvanàsdoxy:BAAALAADCggICQAAAA==.Symbol:BAAALAADCggIDQABLAAECggIDQABAAAAAA==.Sympissal:BAAALAADCgEIAQAAAA==.Sysuck:BAAALAADCgcIBwAAAA==.',['Sé']='Séance:BAAALAADCgUIBgAAAA==.',['Sò']='Sònya:BAAALAAECgMIBwAAAA==.',['Sü']='Süsej:BAAALAAECgQIBQAAAA==.',Ta='Tabhunter:BAAALAADCggIEAAAAA==.Taenil:BAAALAADCgcIDAAAAA==.Talanas:BAAALAAECgEIAQAAAA==.Talenat:BAABLAAECoEUAAIKAAcIpiHjAAC/AgAKAAcIpiHjAAC/AgAAAA==.Tankaman:BAAALAADCgEIAQABLAAECgMIBQABAAAAAA==.Taurpal:BAAALAADCgMIAwAAAA==.',Te='Teinga:BAAALAADCgUIBQAAAA==.Teivell:BAAALAADCgMIAwAAAA==.',Th='Thankyöu:BAAALAAECgMIAwAAAA==.Thastress:BAAALAADCggIEAAAAA==.Thegremlin:BAAALAADCgYIDgAAAA==.Theiceknight:BAAALAAECgUICAAAAA==.Thorvin:BAAALAAECgIIAgAAAA==.Thoryyn:BAAALAAECgUICAAAAA==.Thundertatas:BAAALAAECggIAgAAAA==.',Ti='Tinko:BAAALAADCggICAABLAAFFAMIBQAGAJkgAA==.Tirnoir:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Tk='Tkenga:BAAALAAECgEIAQAAAA==.',To='Toastedbread:BAAALAADCgMIBQAAAA==.Tonicdeath:BAAALAAECgMIBQAAAA==.Toxicmage:BAAALAADCggICgABLAAECgMIBAABAAAAAA==.Toxicoxygen:BAAALAAECgEIAQABLAAECgMIBAABAAAAAA==.Toxicvoid:BAAALAAECgMIBAAAAA==.Toxicxocygen:BAAALAADCgYICQABLAAECgMIBAABAAAAAA==.Toxicxoxygen:BAAALAADCgcICQABLAAECgMIBAABAAAAAA==.',Tr='Tracked:BAAALAADCgMIAwAAAA==.Truthsayer:BAAALAAECgQICAAAAA==.',Ts='Tskuared:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Tsquared:BAAALAAECgYICQAAAA==.',Tu='Tumnina:BAAALAAECgMIAwAAAA==.Turnipcake:BAAALAAECgYICQAAAA==.',Ty='Tyce:BAAALAAECgEIAQAAAA==.Tylannis:BAAALAAFFAIIAgAAAA==.Tyrz:BAAALAAECgIIAgAAAA==.',Ug='Ugacoop:BAAALAAECgcIDwAAAA==.',Un='Unclejosh:BAAALAADCggIBwAAAA==.Undight:BAAALAADCgIIAgAAAA==.Unholyforce:BAAALAADCgcICwABLAAECgYIBwABAAAAAA==.Unholyone:BAAALAADCgQIBAABLAADCgcIBwABAAAAAA==.Unleashed:BAAALAADCgcIBwABLAADCggIDgABAAAAAA==.',Va='Vaelisara:BAAALAADCgIIAgAAAA==.Vanlladrin:BAAALAADCggICAABLAADCggIDgABAAAAAA==.Vanyel:BAAALAADCggIDwAAAA==.Variena:BAAALAAECgIIAgAAAA==.Varis:BAAALAADCgIIAgAAAA==.Varradis:BAAALAADCgcICQAAAA==.Varsconic:BAAALAAECgMIBQAAAA==.',Ve='Vehe:BAAALAAECgUICAAAAA==.Veldrys:BAAALAADCgcIBwABLAAECgQICAABAAAAAA==.Veledaa:BAAALAAECgYIDAAAAA==.Vendethiel:BAAALAADCggIDgAAAA==.Vessyria:BAAALAADCggICAAAAA==.',Vi='Vickos:BAAALAADCggIDQAAAA==.Vixyn:BAAALAADCgQIBAAAAA==.',Vo='Voilet:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.Volvagia:BAAALAAFFAIIAgAAAA==.Voodoostabs:BAAALAADCgUIBQAAAA==.Voodoothunda:BAAALAAECgIIAgAAAA==.Vorellyn:BAAALAAECgIIAwAAAA==.',Vy='Vynllianin:BAAALAADCgMIAwAAAA==.',['Vè']='Vèlkhànà:BAAALAAECgYIDAAAAA==.',Wa='Wagyuroll:BAAALAADCgYIBgAAAA==.Walkabout:BAAALAADCgUIBQAAAA==.Warglaíves:BAAALAAECgYIDQAAAA==.Warrien:BAAALAADCgcIDgABLAAECgYICAABAAAAAA==.',We='Wevaren:BAAALAADCgcIBwAAAA==.',Wh='Whynoheals:BAAALAADCggICAABLAAECgYICQABAAAAAA==.',Wi='Wigsplitter:BAAALAADCgYIBAAAAA==.Wild:BAAALAAECgEIAQABLAAECggIDQABAAAAAA==.Wildheart:BAAALAAECgMIAwABLAAECgYIBgABAAAAAA==.Wildstaff:BAAALAADCgcIDQAAAA==.Wilumi:BAAALAADCggICAAAAA==.Winkel:BAAALAADCgMIAwAAAA==.',Wo='Wolfyhuntres:BAAALAADCggICgAAAA==.Worfia:BAEALAAECgYICQAAAA==.',Wu='Wussy:BAAALAADCggICAABLAAECgYICQABAAAAAA==.',['Wø']='Wøøzì:BAAALAAECgMIAwAAAA==.',Xa='Xaraxi:BAAALAADCggIEgAAAA==.Xariarra:BAAALAADCgcICQAAAA==.Xayah:BAAALAADCggICAAAAA==.',Xe='Xenolocks:BAAALAADCgQIBwAAAA==.',Xi='Xionz:BAAALAAECgMIAwAAAA==.',Ya='Yaep:BAAALAADCgMIAwAAAA==.Yakella:BAAALAAECgUICAAAAA==.',Yd='Yd:BAAALAAECgMIBQAAAA==.',Ye='Yelgrun:BAAALAADCggIDgAAAA==.Yellcat:BAAALAAECgcIEAAAAA==.',Yg='Yggdrasil:BAAALAADCgcIBwAAAA==.',Yo='Yocha:BAAALAAECgYICQAAAA==.',Yu='Yuhjay:BAAALAADCgYIBgAAAA==.',Za='Zabidu:BAAALAAECgcIEQAAAA==.Zaria:BAAALAAECgcIEQAAAA==.Zauriel:BAAALAAECgIIBAAAAA==.',Ze='Zeazalynn:BAAALAADCgcIEQAAAA==.Zelenã:BAAALAAECgQICAAAAA==.Zephon:BAAALAAFFAIIAgAAAA==.Zeroshadow:BAAALAAECgIIAgAAAA==.',Zi='Ziggley:BAAALAADCgcIDAAAAA==.',Zo='Zoggle:BAAALAADCgYICQAAAA==.',['Zè']='Zèphyr:BAAALAAECgYICQAAAA==.',['Zé']='Zéd:BAAALAAECgcIDwAAAA==.',['Âx']='Âxel:BAAALAAECgEIAQABLAAECgcIDwABAAAAAA==.',['Æm']='Æmon:BAAALAAECgMIBQAAAA==.',['Ðe']='Ðeadpool:BAAALAAECgQIBAAAAA==.',['Ñí']='Ñíghtmáre:BAAALAADCgIIAgAAAA==.',['Ñî']='Ñîghtmare:BAAALAADCgcIBwAAAA==.',['ßl']='ßlackheart:BAAALAAECgMIAwAAAA==.',['ßr']='ßrß:BAAALAAECgcIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end