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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Paladin-Retribution','Hunter-Survival','Warlock-Destruction','Evoker-Devastation','Shaman-Restoration','Priest-Shadow','DemonHunter-Havoc','Warrior-Fury','Druid-Balance','Druid-Restoration','Monk-Windwalker','DeathKnight-Frost','Warlock-Affliction','Rogue-Outlaw','Rogue-Assassination','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Holy','DeathKnight-Unholy','DemonHunter-Vengeance','Shaman-Elemental','Warlock-Demonology','Monk-Brewmaster','Monk-Mistweaver',}; local provider = {region='US',realm='Destromath',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adeille:BAAALAAECgUIBwAAAA==.',Ae='Aenestriel:BAAALAAECgMIBgAAAA==.',Af='Affpriest:BAAALAADCgcICAAAAA==.',Ak='Akinjii:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Akstar:BAABLAAECoEVAAICAAgILxcvGgA+AgACAAgILxcvGgA+AgAAAA==.',Al='Alalletsa:BAAALAAECgMIAwAAAA==.Alchemical:BAAALAAECggICAAAAA==.Alistier:BAAALAAECgMIBgAAAA==.Allegrata:BAAALAAECgQIBgAAAA==.Aloemon:BAAALAADCgcIDAAAAA==.Aloezilla:BAAALAAECgYICAAAAA==.Alouna:BAAALAAECgMIAwAAAA==.',Am='Amaúnet:BAAALAADCggICAABLAAECggIFgADAKwkAA==.Amonchakai:BAAALAADCgQIBAAAAA==.',An='Anarius:BAAALAADCggIDQAAAA==.Andandalam:BAAALAADCgcICAAAAA==.Andromedar:BAAALAADCgMIAwAAAA==.Anduu:BAAALAADCgcIBwAAAA==.Anjori:BAAALAADCgcIDgAAAA==.',Ap='Aphroditii:BAAALAAECgEIAgAAAA==.',Ar='Arazzo:BAAALAADCgEIAQAAAA==.Arlaeyna:BAAALAADCggICAAAAA==.Artivicious:BAAALAAECgMIBgAAAA==.',As='Askaris:BAAALAADCgMIAwAAAA==.',At='Athandor:BAAALAADCggIEQAAAA==.',Au='Aurorania:BAAALAAECgIIAgAAAA==.',Av='Avasarala:BAAALAADCggIEAAAAA==.',Ba='Baalhamoon:BAAALAAECgcIEQAAAA==.Baangsan:BAEALAADCgcIBwAAAA==.Bacsilog:BAAALAAECgYICQAAAA==.Bajoojoo:BAABLAAECoEVAAIEAAgILh7hAADYAgAEAAgILh7hAADYAgAAAA==.Baka:BAAALAADCgcIBgAAAA==.Bamßooty:BAAALAAECgQIBwAAAA==.Barrymanalow:BAAALAADCgMIAwABLAAECgIIAwABAAAAAA==.',Be='Bearmancow:BAAALAAECgEIAQAAAA==.Belsara:BAAALAADCgcICwAAAA==.Berrystrong:BAAALAADCgcIBwAAAA==.',Bh='Bhardum:BAAALAADCgcIDAAAAA==.',Bi='Biff:BAAALAADCgQIBAAAAA==.Biggestdump:BAAALAADCggICAAAAA==.',Bl='Blaumeux:BAAALAADCgYIBgAAAA==.Bleidd:BAAALAAECgMIBAAAAA==.Blindbank:BAAALAAECgMIBQAAAA==.Blinkish:BAAALAADCgQIBAAAAA==.Bluesworthy:BAAALAADCgcICwAAAA==.Bluetron:BAAALAADCgEIAQAAAA==.Blumentanzer:BAAALAADCgcIBwABLAAECggIFgAFAIQkAA==.',Bo='Bolthir:BAAALAADCgcIDQABLAAECggIKQAGAGshAA==.Bolthirvokee:BAAALAAECgEIAQABLAAECggIKQAGAGshAA==.Bolthirvoker:BAABLAAECoEpAAIGAAgIayE7BQDoAgAGAAgIayE7BQDoAgAAAA==.Boss:BAAALAAECgMIBAAAAA==.Boxghost:BAAALAADCggICAAAAA==.',Br='Brightslap:BAAALAAECgEIAQAAAA==.Brontides:BAAALAAECgcIDwAAAA==.',Bu='Bubbz:BAAALAAECgMIBQAAAA==.Buffox:BAAALAADCggIFQAAAA==.Bullpup:BAABLAAECoEkAAIHAAgIdRPKGQDmAQAHAAgIdRPKGQDmAQAAAA==.Bumpis:BAAALAAECgMIAwAAAA==.Burakîp:BAAALAAECgMIBQAAAA==.Burrett:BAAALAAECgMIBgAAAA==.Burt:BAAALAAECgMICQAAAA==.',['Bå']='Båbz:BAAALAAECgIIAgAAAA==.Båstët:BAAALAAECgcIDgAAAA==.',Ca='Caalis:BAAALAADCgcIBwAAAA==.Calcula:BAABLAAECoEXAAIIAAgIcB/7BwDQAgAIAAgIcB/7BwDQAgAAAA==.Calithil:BAAALAADCggICQAAAA==.Callea:BAABLAAECoEpAAIIAAgIvxUQEgApAgAIAAgIvxUQEgApAgAAAA==.Camellia:BAAALAAECgMIBQAAAA==.Carried:BAAALAAECgMIAwAAAA==.Catboidaddy:BAAALAAECgQIBAABLAAECggIFgAFAIQkAA==.Catherd:BAAALAADCgQIBAAAAA==.Cathord:BAAALAAECgQIBAAAAA==.Caxtro:BAAALAAECgUICwAAAA==.',Ce='Cenna:BAABLAAECoEUAAIJAAgIbRyIDgCkAgAJAAgIbRyIDgCkAgAAAA==.',Ch='Cheesedragon:BAAALAAECgYICAAAAA==.Chipchops:BAAALAADCggIEQAAAA==.Chugbug:BAABLAAECoEUAAIKAAgI7CTXAgBIAwAKAAgI7CTXAgBIAwAAAA==.',Ci='Citori:BAAALAADCgcIDgAAAA==.',Cl='Clearlylight:BAAALAAECgIIAgAAAA==.Cleave:BAAALAAECgIIAwAAAA==.Cloudburst:BAAALAAECgMIAwAAAA==.Clubberlang:BAAALAAECgEIAgAAAA==.',Co='Corolly:BAAALAAECgcICgAAAA==.Corrndog:BAAALAAECgYICAAAAA==.Cowbizarre:BAAALAAECgMIBAAAAA==.',Cr='Crazydemon:BAAALAADCgEIAQAAAA==.Crilla:BAAALAADCggIDwAAAA==.Crotchchop:BAAALAADCgEIAQAAAA==.Crunkster:BAAALAADCgYICQAAAA==.Crushadin:BAAALAAECgYICQAAAA==.Crushedwings:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Crushlock:BAAALAAECgEIAQABLAAECgYICQABAAAAAA==.',Cu='Cubeghost:BAAALAADCgcIBwAAAA==.Cursedhunter:BAAALAAECgMIAwAAAA==.Cuttymofukuh:BAAALAADCggICwABLAAECgcIDwABAAAAAA==.',Cy='Cyclonespam:BAABLAAECoEWAAMLAAgIjRtTCwB1AgALAAgIjRtTCwB1AgAMAAEI3AM0XAAiAAAAAA==.Cynakai:BAAALAADCggIDwAAAA==.',['Câ']='Câprisun:BAAALAADCgYIBwAAAA==.',['Cê']='Cêlænâ:BAAALAAECgEIAQAAAA==.',Da='Daggcastit:BAABLAAECoEkAAICAAgILx6vEgCCAgACAAgILx6vEgCCAgAAAA==.Dali:BAAALAAECgIIAwAAAA==.Dandylions:BAAALAADCgEIAQAAAA==.Dangnabbit:BAAALAAECgEIAQABLAAECggIJAACAC8eAA==.Daniellol:BAAALAADCgcIBwAAAA==.Dannaris:BAAALAAFFAIIAgAAAA==.Daranir:BAAALAADCggIDQAAAA==.Darkershaes:BAAALAAECgMIBQAAAA==.Darkwingdoc:BAAALAADCgEIAQAAAA==.Davlock:BAAALAADCggICAAAAA==.',De='Deadbølt:BAAALAADCgcICgAAAA==.Deadlyzlock:BAAALAADCgUICAAAAA==.Deadlyzmage:BAAALAADCgcIBwAAAA==.Deadpinch:BAAALAAECgEIAQAAAA==.Deadwolv:BAAALAAECgUICQAAAA==.Deathslap:BAAALAADCgYIDgAAAA==.Decayedshrmp:BAAALAADCgYIBgAAAA==.Decoy:BAAALAADCggIEAABLAAECggIFgAKALUjAA==.Deeztun:BAAALAAECgMIBwAAAA==.Delith:BAAALAADCggICAAAAA==.Derps:BAAALAAECgQIBQAAAA==.Devilmaykry:BAAALAADCgQIBAAAAA==.',Di='Dibjorfmage:BAAALAAECgUIBgAAAA==.Dilydilyuwu:BAAALAAECgUICQABLAAECggIEwABAAAAAA==.Diploid:BAAALAAECggIEwAAAA==.',Dj='Djankmaimer:BAAALAADCgcIBwAAAA==.Djiamond:BAAALAAECgMIAwAAAA==.',Dl='Dliqnt:BAAALAAECgQIBQAAAA==.',Do='Docevol:BAAALAAECgYIDAAAAA==.Dogwalk:BAAALAADCgEIAQABLAAECggICwABAAAAAA==.Domoarogato:BAAALAAECgEIAQAAAA==.Donainen:BAAALAAECgEIAQAAAA==.',Dr='Draconectar:BAAALAAECgEIAQAAAA==.Dragonlinks:BAAALAAECgEIAQAAAA==.Drakho:BAAALAAECgMIBQAAAA==.Drakkar:BAAALAAECgIIAwAAAA==.Dreadfuse:BAAALAAECggIBAAAAA==.Dreezius:BAAALAAFFAIIAgAAAA==.Drelle:BAAALAAECgcIDgAAAA==.Droobie:BAAALAAECgEIAQAAAA==.',Du='Ducknorrís:BAAALAADCgEIAQAAAA==.',Dw='Dwahlin:BAAALAADCgcICAAAAA==.Dweesal:BAAALAAECgEIAQAAAA==.',Dy='Dylan:BAABLAAECoEWAAINAAgIfSVoAAB3AwANAAgIfSVoAAB3AwAAAA==.',Ei='Eian:BAAALAADCgUIBQAAAA==.',El='Elanderera:BAAALAADCggIFgAAAA==.Elunemoonbae:BAAALAADCgMIAwAAAA==.',En='Enchannttres:BAAALAADCggICAAAAA==.Engfish:BAAALAADCggICAAAAA==.',Er='Erashar:BAAALAAECgUIBgAAAA==.Eriaelyn:BAAALAADCgYIBgAAAA==.',Es='Eshonai:BAAALAADCgcIDgAAAA==.',Ev='Evalasting:BAAALAAECgMIAwAAAA==.',Ex='Exeris:BAAALAAECgMIBgAAAA==.',Fa='Facestarwind:BAAALAADCggICAAAAA==.Faceventura:BAAALAADCggICAABLAAECgUIBgABAAAAAA==.Fade:BAAALAAECgYIBgAAAA==.',Fe='Fellularslap:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Felmommy:BAAALAAECgcIDgAAAA==.Ferasila:BAAALAAECgMIBQAAAA==.Ferchinsc:BAAALAADCggICAAAAA==.',Fh='Fhab:BAAALAADCggICAAAAA==.',Fi='Figmentation:BAAALAAECgMIAwAAAA==.Fivewishes:BAAALAAECgQIBwAAAA==.',Fl='Floorpov:BAAALAADCgEIAQABLAAECgYIDQABAAAAAA==.',Fo='Forsakemz:BAAALAADCgIIAgAAAA==.',Fr='Frostydurp:BAAALAAECggIDwAAAA==.Frozenblood:BAAALAADCggICwAAAA==.Frozon:BAAALAADCgIIAgAAAA==.',Fu='Fussy:BAAALAADCgIIAgAAAA==.Futasaur:BAAALAAECgEIAgAAAA==.',Ga='Gabiru:BAAALAAECgUIBgAAAA==.Gambles:BAAALAADCgIIAgAAAA==.Garruks:BAAALAADCgMIAwAAAA==.',Gh='Ghouldan:BAAALAADCgQIBAAAAA==.',Gi='Giftig:BAAALAADCggICAABLAAECggIFgAFAIQkAA==.Gilith:BAAALAAECgEIAQAAAA==.Gillbinz:BAAALAAECgEIAQAAAA==.Gingersnaper:BAAALAADCgYIBwAAAA==.',Gl='Glazerr:BAAALAADCgIIAgAAAA==.Glenmoril:BAAALAADCggIDQAAAA==.Glickfre:BAAALAADCgIIAgAAAA==.Glicklock:BAAALAAECgUICgAAAA==.Glickswap:BAAALAADCgcIDwAAAA==.Glicktate:BAAALAAECgUIBQAAAA==.Glipbobotank:BAABLAAFFIELAAIOAAUIwBlqAADTAQAOAAUIwBlqAADTAQAAAA==.',Gn='Gnate:BAAALAADCggIFwAAAA==.Gnomeproblèm:BAAALAAECgcIDwAAAA==.',Go='Goren:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.Gorgrimskull:BAAALAAECgEIAgAAAA==.Goshevan:BAAALAADCggICAAAAA==.Gotnogrncard:BAAALAADCgcIBwAAAA==.',Gr='Grandy:BAAALAAECggIAwAAAA==.Granmaspi:BAAALAADCggICAAAAA==.Grapple:BAAALAAECgQICQAAAA==.Graspheart:BAAALAADCgQIBAAAAA==.Greybull:BAAALAADCggICAAAAA==.Greytoes:BAAALAAECgIIAwAAAA==.Grinnlock:BAAALAAECgMIAwAAAA==.',Gu='Guaplord:BAAALAAECggIDgABLAAECggIDwABAAAAAA==.Gulfna:BAAALAAECgYIDgAAAA==.',Gw='Gwinbell:BAAALAADCgMIBQAAAA==.',Ha='Hammerdaddi:BAAALAADCgYIBwAAAA==.Harrokk:BAAALAAECgcIDwAAAA==.Hautebussy:BAABLAAECoEWAAMFAAgIhCTTAgA8AwAFAAgIhCTTAgA8AwAPAAIIgBFpHACbAAAAAA==.',He='Healjean:BAAALAADCgcIBwAAAA==.Heaton:BAABLAAECoEWAAIKAAgItSP6AwAyAwAKAAgItSP6AwAyAwAAAA==.Hellreiser:BAABLAAECoEWAAIDAAgIrCTRAwBHAwADAAgIrCTRAwBHAwAAAA==.Hellvoker:BAAALAADCggICAABLAAECggIFgADAKwkAA==.Hewhohunts:BAAALAAECgEIAQAAAA==.',Hi='Him:BAAALAADCgcIDAAAAA==.His:BAAALAADCgYIBgAAAA==.',Ho='Holybox:BAAALAADCgEIAQAAAA==.Holymofuk:BAAALAAECgUIBQABLAAECgcIDwABAAAAAA==.Holypony:BAAALAAECgMIBAAAAA==.Holyshift:BAAALAADCgcIDgAAAA==.Holywolff:BAAALAADCgMIAgAAAA==.Hongkongcow:BAAALAAECgMIAwAAAA==.Howtoplaydh:BAAALAAECgMIAwAAAA==.',Hu='Hubbabubba:BAAALAAECgEIAQAAAA==.Huntnomnom:BAAALAAECgYIBwAAAA==.Husbear:BAAALAADCgQIBAAAAA==.Huskernuts:BAAALAADCgYICgAAAA==.',['Hö']='Hölly:BAAALAADCggICQAAAA==.',Ia='Iabrat:BAAALAADCgcIBwAAAA==.',Ic='Ichbingeil:BAAALAADCgQIBAAAAA==.',Ii='Iinjyapan:BAAALAADCgcICAAAAA==.',Il='Illfrostya:BAAALAADCggIDwAAAA==.Illiarior:BAAALAAECgMIBQAAAA==.',Ip='Iplugbarrels:BAAALAADCgQIBAAAAA==.',Is='Ishikuma:BAAALAADCgcIBwABLAADCggIDwABAAAAAA==.Ishinotsuno:BAAALAADCggIDwAAAA==.',It='Itshebum:BAAALAAECgMIBgAAAA==.',Iz='Izukumidorya:BAAALAADCggIDwAAAA==.',Ja='Jadizeth:BAAALAADCggIDwAAAA==.Jaky:BAABLAAECoEVAAQQAAgIRBg+AwANAgAQAAcITBg+AwANAgARAAYIFxUFFgDVAQASAAIIEhVHEgB+AAAAAA==.',Jc='Jcraad:BAAALAAECgcIDgAAAA==.',Je='Jedikenobi:BAAALAAECgMIBgAAAA==.Jedimindtrx:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.Jennirivera:BAAALAAECgIIAgABLAAECggIEwABAAAAAA==.Jephph:BAABLAAECoEYAAMTAAgIViH9BQDPAgATAAgIViH9BQDPAgAUAAEImx+daABTAAAAAA==.Jereno:BAABLAAECoEWAAMIAAgI8xb6DwBFAgAIAAgI8xb6DwBFAgAVAAEI1QEWXAArAAAAAA==.Jesenna:BAAALAADCggIFwAAAA==.',Ji='Jisun:BAAALAADCgEIAQAAAA==.',Ju='Judgemoont:BAAALAAECgYIDAAAAA==.',['Jö']='Jöhari:BAAALAADCggICAAAAA==.',Ka='Kaamah:BAAALAADCgMIAwAAAA==.Kabrxis:BAAALAAECgIIAgAAAA==.Kaedarril:BAAALAADCgYIBgAAAA==.Kalterrai:BAAALAADCgMIAwAAAA==.Karaxxes:BAAALAADCgYIBwAAAA==.Karisuta:BAAALAADCgUIBQAAAA==.Kassiaa:BAAALAAECgMIAwAAAA==.Kavax:BAAALAAECgMIAwAAAA==.',Ke='Kelibastus:BAAALAAECgQIBQAAAA==.Ketheric:BAAALAAECgQIBQAAAA==.Keyka:BAAALAAECgMIAwABLAAECgQIBAABAAAAAA==.',Kh='Khaster:BAABLAAECoEPAAMOAAgIeRofIQD+AQAOAAgI4BYfIQD+AQAWAAEI8iCBLgBIAAAAAA==.',Ki='Kickinwaynes:BAAALAADCgYICgAAAA==.Kiikka:BAAALAAECgQIBAAAAA==.',Kl='Kleiin:BAAALAAECgYICAAAAA==.',Ku='Kuloz:BAAALAAECgEIAQABLAAECgQIBgABAAAAAA==.Kusal:BAAALAADCgcIBwAAAA==.',Ky='Kylexy:BAAALAADCggICwAAAA==.',['Kö']='Königs:BAAALAAECgcICQAAAA==.Königsberg:BAAALAAECgMIBQABLAAECgcICQABAAAAAA==.',La='Laranth:BAAALAAECgEIAQABLAAECggIJAAJAHsXAA==.Larasia:BAABLAAECoEkAAMJAAgIexfmFQBRAgAJAAgIexfmFQBRAgAXAAMIbBCIHwCGAAAAAA==.Larxéne:BAAALAAECgUICAAAAA==.Laufey:BAAALAADCggIEgABLAAECgYICAABAAAAAA==.',Le='Legendáry:BAAALAAECgIIAgAAAA==.Lemminkainen:BAAALAADCgEIAQAAAA==.Leroysimpkin:BAAALAADCggIEAAAAA==.',Li='Ligia:BAAALAADCgYIBgAAAA==.Lildeadboy:BAAALAADCgcIDgABLAAECgMIAwABAAAAAA==.Lilstonks:BAAALAAECggIDwAAAA==.Livia:BAAALAAECgQIBwAAAA==.',Lo='Lockandroll:BAAALAAECggICAAAAA==.Lockoholic:BAAALAADCggICAAAAA==.Lonron:BAAALAAECggIBAAAAA==.Lorstan:BAAALAADCggIDwAAAA==.',Lu='Lunagoodlove:BAAALAAECgEIAQAAAA==.Lunamorpf:BAAALAADCgcIDgAAAA==.Lustdaddy:BAAALAAECgIIAgAAAA==.Lutes:BAAALAAECgIIAgABLAAECggIFQAOAI8hAA==.Lutesectomy:BAABLAAECoEVAAMOAAgIjyEZHQAZAgAOAAcIeh4ZHQAZAgAWAAQIZiTPDwCeAQAAAA==.Lutesifer:BAAALAADCggICAABLAAECggIFQAOAI8hAA==.Luuigii:BAAALAAECggIAQAAAA==.',Ly='Lyghtbryght:BAAALAADCggIDwAAAA==.',Ma='Malou:BAAALAADCggICAAAAA==.Mamallhama:BAAALAADCgcICAAAAA==.Manbarepig:BAEALAAECgMIBQAAAA==.Mantiself:BAAALAAECgYICAAAAA==.Marlon:BAAALAAECgUIBQABLAAECgYIDwABAAAAAA==.Mateow:BAAALAADCggIDgAAAA==.Mathbruh:BAAALAAECgIIAgAAAA==.Maudroar:BAAALAADCggICAABLAAECggIGAAYAH0XAA==.Mazikean:BAAALAAECgMIAwAAAA==.',Me='Melgor:BAAALAADCgQIBAAAAA==.Melodý:BAAALAADCgYIBgABLAAECgUIBgABAAAAAA==.Meltryllis:BAAALAADCgcIBwAAAA==.Meshuugo:BAAALAAECgcIDwAAAA==.Messmer:BAAALAADCggICwAAAA==.',Mi='Midgetmage:BAAALAADCgYIBgAAAA==.Milfportal:BAAALAADCgYICgAAAA==.Milicia:BAAALAADCggIDwAAAA==.Milkkratem:BAAALAAECgYICwAAAA==.Missvanjie:BAAALAAECggIEwAAAA==.Miutsuki:BAABLAAECoEWAAIZAAgISh0UAgByAgAZAAgISh0UAgByAgAAAA==.',Mo='Mogoo:BAAALAADCggIDAAAAA==.Moofellow:BAAALAADCgIIAgAAAA==.Moolord:BAAALAADCgcIBwAAAA==.Mooskie:BAAALAAECgEIAQAAAA==.Moraledr:BAAALAAECgMIAwAAAA==.Moralemage:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.',Mu='Muckmoo:BAAALAAECgMIBgAAAA==.Mudslap:BAAALAADCgcIDQABLAAECgEIAQABAAAAAA==.Muffìns:BAAALAAECgUIBgAAAA==.Mupphins:BAAALAADCgcIBwAAAA==.',My='Mysticelf:BAAALAADCgcIBwAAAA==.Mystichuman:BAAALAAECgYICgAAAA==.',['Mà']='Màrv:BAAALAADCgIIAgAAAA==.',['Mü']='Mürdanden:BAAALAADCgMIAwAAAA==.',Na='Nachtigall:BAAALAAECgMIAwAAAA==.Naedice:BAAALAADCgUIBQAAAA==.Nawss:BAAALAADCggIDgAAAA==.',Ne='Nephìs:BAAALAADCgcIBwAAAA==.Nesopriest:BAAALAADCggICAAAAA==.Netalan:BAAALAAECgMIBgAAAA==.',Ni='Nifler:BAAALAADCgIIAgAAAA==.Nikon:BAAALAAECgIIAgAAAA==.Nimonathius:BAAALAADCggIHwAAAA==.Ninjasocks:BAAALAAECgEIAwAAAA==.',No='Nodrogeast:BAAALAADCgcIDwAAAA==.Noridra:BAAALAAECgMIBQAAAA==.Notzoth:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Nowioaws:BAAALAADCgMIAwAAAA==.',Ny='Nysiss:BAAALAADCggIDgAAAA==.',Oa='Oaddvar:BAAALAADCgQIBgAAAA==.',Ob='Obembe:BAAALAAECgEIAQAAAA==.Obsïdïous:BAAALAAECgIIAgAAAA==.',Oc='Oceanlab:BAAALAAECgQIBQAAAA==.Octavìa:BAAALAADCgUIBQABLAAECgUIBgABAAAAAA==.Octorissi:BAAALAAECgcIDQAAAA==.',Og='Ogdead:BAAALAADCgUIBQAAAA==.',Ol='Oldfart:BAAALAADCgUICQAAAA==.Olianna:BAAALAADCgQIBAAAAA==.',Om='Om:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Omnilach:BAAALAAECgcIDgAAAA==.',On='Onionn:BAAALAADCgcICAAAAA==.Onji:BAAALAADCgUIBQAAAA==.',Oo='Ookamigin:BAAALAAECgEIAQAAAA==.',Op='Opiopio:BAAALAADCgUIBQAAAA==.',Ov='Overpew:BAAALAAECgIIAgAAAA==.',Pa='Padussy:BAAALAADCgMIAwAAAA==.Palcook:BAAALAADCgcIBwAAAA==.Pantanna:BAAALAADCgcICwAAAA==.',Ph='Phatsy:BAAALAADCggIDwAAAA==.Phlux:BAAALAAECgEIAQAAAA==.',Pi='Picklebumps:BAAALAAECgMIBAAAAA==.Piker:BAAALAAECggIEQAAAA==.',Pl='Pluck:BAAALAADCggIBQAAAA==.',Po='Poe:BAAALAADCgcIBwAAAA==.Pokiehl:BAAALAADCgcIBwAAAA==.Popozhao:BAABLAAECoEVAAQNAAgIxiAoAwD5AgANAAgIxiAoAwD5AgAaAAIILgJaHgBEAAAbAAEIXgF6KgAgAAAAAA==.',Pr='Preheater:BAAALAADCgcIBwAAAA==.Probait:BAAALAADCggICAAAAA==.',Pu='Pubikcrabs:BAAALAADCgYICAAAAA==.Puffthemagic:BAAALAAECggIAwAAAA==.Pumpkindh:BAAALAADCgEIAQAAAA==.Pumpkinpally:BAAALAAECgEIAQABLAADCgEIAQABAAAAAA==.',Pw='Pwncess:BAAALAAECgYICgABLAAECgYIDAABAAAAAA==.',Qb='Qballs:BAAALAAECgMIBQAAAA==.',Qe='Qeq:BAAALAADCgYIBgAAAA==.',Qu='Quackiechan:BAAALAAECgYICQAAAA==.',Ra='Rabidhippo:BAAALAAECgIIAwAAAA==.Raer:BAAALAAECgMIBgAAAA==.Ragnaroks:BAAALAADCgYICwAAAA==.Rakka:BAAALAAECgMIBQAAAA==.Ralderex:BAAALAADCgIIAgAAAA==.Ralvia:BAAALAADCgEIAQAAAA==.Razzellian:BAAALAAECgQIBAAAAA==.',Re='Restorianguy:BAAALAADCgMIAwAAAA==.Retahrl:BAAALAAECgEIAQAAAA==.Revan:BAAALAAECggIEAAAAA==.',Rh='Rhayle:BAAALAAECgMIBwAAAA==.',Ri='Rikeji:BAAALAAECgEIAQAAAA==.Ritzcracker:BAAALAAECgEIAQAAAA==.',Ro='Rokash:BAAALAAECgYIDwAAAA==.Roknstoon:BAAALAADCgcIBwAAAA==.Ronewa:BAAALAADCgcIBwAAAA==.Roobarb:BAAALAADCgcIDwAAAA==.',Ru='Rumplez:BAAALAAECggIBgAAAA==.Runist:BAAALAADCgUIBQAAAA==.Runtzz:BAAALAADCggIEwAAAA==.',['Rö']='Rög:BAAALAADCgEIAQAAAA==.',Sa='Saelzington:BAABLAAECoEXAAIPAAgIHiUuAAB0AwAPAAgIHiUuAAB0AwAAAA==.Safiyal:BAAALAAECgEIAgAAAA==.Sahari:BAAALAAECgEIAQAAAA==.Samaranacht:BAAALAADCgcIDQAAAA==.Samuraibicep:BAAALAADCgYIDgAAAA==.Sanlard:BAAALAADCggICAAAAA==.Sarahc:BAAALAADCgIIAgAAAA==.Sasiona:BAAALAADCgcIDQAAAA==.',Sc='Scadillac:BAAALAADCgUIBQAAAA==.Scootmoose:BAAALAAECgMIBgAAAA==.Scroatotem:BAAALAADCgcICAAAAA==.',Se='Semias:BAAALAAECgQIBgAAAA==.Senosvin:BAAALAADCgQIBAAAAA==.Senseisuske:BAAALAAECgUICAAAAA==.Seras:BAAALAADCgcICAAAAA==.',Sg='Sgrbear:BAAALAADCgcIDQAAAA==.',Sh='Shadowbert:BAAALAAECgEIAQABLAAECgYIDAABAAAAAA==.Shadowdeadma:BAAALAAECgMIAwAAAA==.Shadowelf:BAAALAADCggIDQAAAA==.Shadowhuman:BAAALAAECgYICgAAAA==.Shadowstrom:BAAALAADCgcIDgAAAA==.Sharlit:BAAALAADCgcIDQAAAA==.Sharpshift:BAAALAADCggICAAAAA==.Shawdyrocz:BAAALAADCgcIBwAAAA==.Shimmersion:BAAALAADCggICAAAAA==.Shimmew:BAABLAAECoEWAAMTAAgI7SDNBwCmAgATAAgIciDNBwCmAgAUAAEIhCNYZABmAAAAAA==.Shimmu:BAAALAADCggICAAAAA==.Shopstick:BAAALAAECgQIBQAAAA==.Shyvixen:BAAALAADCgcICQAAAA==.Shÿtstorm:BAAALAADCgcICAAAAA==.',Si='Sinfulness:BAAALAAECgcIDgAAAA==.Sixtyninedh:BAAALAAECgEIAQAAAA==.',Sk='Skillerr:BAAALAADCgMIAwAAAA==.',Sl='Slaygolas:BAAALAAECgEIAQAAAA==.Slippyfistt:BAAALAAECgMICAAAAA==.Slushies:BAAALAAECggIDgAAAA==.',Sm='Smittysen:BAAALAADCggICAAAAA==.',Sn='Sneakibles:BAAALAADCgYIBgAAAA==.Sneeg:BAAALAADCgYIBgABLAAECgYIDQABAAAAAA==.Sniped:BAAALAADCgUIBQABLAAECggIFgAKALUjAA==.Snoflake:BAAALAADCggICAAAAA==.',So='Sober:BAAALAAECgYICQAAAA==.Softfleur:BAAALAADCgEIAQAAAA==.',Sp='Spahrta:BAAALAADCgcIBwAAAA==.Spartystrasz:BAAALAAECgQICAAAAA==.Spiritjeeg:BAAALAADCgcICgAAAA==.',Ss='Ssariusly:BAAALAADCgIIAgAAAA==.',St='Stabuloso:BAAALAAECgcIDwAAAA==.Stalladin:BAAALAAECgcIDwAAAA==.Starck:BAAALAAECgcIDwAAAA==.Stonemover:BAAALAAECgYICQAAAA==.Stormfire:BAAALAADCgYICwAAAA==.Stormsound:BAAALAADCgYIDQAAAA==.Strumpët:BAAALAAECgEIAQAAAA==.Stuuida:BAAALAADCgIIAgAAAA==.',Su='Sungjiinwoo:BAAALAAECgMIBgAAAA==.Surmar:BAAALAAECgEIAQAAAA==.',Sw='Swagmonsta:BAAALAAECgUIBQAAAA==.Swampgarbage:BAAALAAECgYIBgAAAA==.Swaycos:BAAALAAFFAIIAgAAAA==.Swazzit:BAAALAADCgIIAgAAAA==.Swiddles:BAAALAAECgYIDQAAAA==.',Sy='Symbiote:BAAALAAECgcIDQAAAA==.',Ta='Tabris:BAAALAADCggICQAAAA==.Tacheron:BAAALAADCgcIBwAAAA==.Taevis:BAAALAADCggIDgAAAA==.Takas:BAAALAAECgQIBAAAAA==.Takop:BAAALAAECgYIBgAAAA==.',Te='Teapot:BAAALAAECgUICAAAAA==.Tedktheuna:BAAALAAECgEIAQABLAAECggIJAAHAHUTAA==.Terribull:BAAALAAECgEIAQAAAA==.',Th='Thalorion:BAAALAADCgcIDgAAAA==.Thecutenesz:BAAALAAECgUIBgAAAA==.Thedrood:BAAALAADCgUIBQAAAA==.Themistake:BAAALAAECgEIAQAAAA==.Thickbottom:BAAALAAECgcICAAAAA==.Thickshadow:BAAALAADCgcIBwABLAAECgcICAABAAAAAA==.Thugbug:BAAALAADCggIFgAAAA==.Thuk:BAAALAADCgMIAwAAAA==.Thursday:BAAALAADCgQIBAAAAA==.Thébígtúñá:BAAALAADCgMIAwAAAA==.',Ti='Ticklemytots:BAAALAAECgYIDAAAAA==.Tirynis:BAEBLAAECoEWAAIDAAgIdiW+BAA2AwADAAgIdiW+BAA2AwAAAA==.Titanheart:BAAALAADCgcIBwAAAA==.',Tl='Tlow:BAAALAAECgMIBgAAAA==.',Tm='Tmsmdfcrcls:BAAALAAECgMIAwAAAA==.',To='Totemtankn:BAAALAADCgYIBgAAAA==.Totemtastic:BAAALAAECgQIBQAAAA==.Toukouri:BAAALAADCgEIAQAAAA==.',Tr='Trazara:BAAALAAECgcIDgAAAA==.Tricksy:BAAALAADCgIIAgAAAA==.Trumpdog:BAAALAADCgIIAgAAAA==.',Tu='Turokjit:BAAALAAECgcICwAAAA==.',Tw='Twrksicle:BAAALAAECgMIAwAAAA==.',Ty='Tyrael:BAAALAADCgYIBwAAAA==.Tyrannosaur:BAAALAAECggIDgAAAA==.',Ul='Ulfsark:BAAALAADCgQIBwAAAA==.Ultrasteve:BAAALAADCgUIBgAAAA==.',Us='Usaytacobell:BAAALAADCggICAAAAA==.Usdaprime:BAAALAAECgMIBAAAAA==.',Va='Vacuöus:BAAALAADCgcICAAAAA==.Vallium:BAAALAAECgQIBQAAAA==.Varinessa:BAAALAAECgQIBAAAAA==.Varlem:BAAALAAECgMIAwAAAA==.Varvaros:BAAALAADCgYIBwAAAA==.',Ve='Velanor:BAAALAAECgYIBwAAAA==.Velastraa:BAAALAAECgcIDwAAAA==.Velithara:BAAALAADCggICAABLAADCggIFwABAAAAAA==.Velpha:BAAALAAECgQIBQAAAA==.Venjuu:BAAALAAFFAEIAQAAAA==.Venusx:BAABLAAECoEWAAIIAAcI0RVSFgD1AQAIAAcI0RVSFgD1AQAAAA==.Vergo:BAAALAAECgIIAwAAAA==.Verz:BAAALAAECgYICgAAAA==.Vexington:BAAALAADCgEIAgAAAA==.Vextheriá:BAAALAAECgQIBQAAAA==.Veygg:BAABLAAECoEVAAICAAgIDCPjCQDmAgACAAgIDCPjCQDmAgAAAA==.',Vh='Vhaghar:BAAALAAECgMIBAAAAA==.',Vi='Vierei:BAAALAADCggICAAAAA==.Virjeanity:BAAALAAECgIIAwAAAA==.Visago:BAAALAADCgYICgAAAA==.',Vo='Vold:BAAALAADCgYIBQAAAA==.Vorztrix:BAAALAAECgcICAABLAAECgcIFgAIANEVAA==.',Wa='Waifuqt:BAAALAAECgcIDwAAAA==.Wamojo:BAAALAAECgIIAwAAAA==.Warenn:BAAALAADCgEIAQAAAA==.Warts:BAAALAAECgMIAwAAAA==.Warwa:BAAALAADCgEIAQAAAA==.Waterincone:BAAALAAECgYIEQAAAA==.',Wh='Whiterra:BAAALAAECgcIDgAAAA==.',Wi='Widdleitch:BAAALAADCgcIDQAAAA==.',Wo='Wogawogawoga:BAAALAADCggIFQAAAA==.',Wr='Wrak:BAAALAAECgMIAwAAAA==.',Wy='Wyatta:BAAALAADCgcIBwAAAA==.',['Wì']='Wìsdom:BAAALAAECgYIEQAAAA==.',Xa='Xaltwer:BAAALAAECgEIAQAAAA==.Xasp:BAAALAAECgYIDAAAAA==.Xathi:BAAALAADCggIFgAAAA==.',Xi='Xiaorourou:BAAALAADCgQIBAAAAA==.',Xl='Xleander:BAAALAAECgYIBgAAAA==.',Xo='Xovyt:BAAALAADCgEIAQABLAAECggIFgAFAIQkAA==.',Yo='Yoniss:BAAALAADCgYIBgAAAA==.',Za='Zarin:BAAALAADCgcIBwAAAA==.Zarzlek:BAAALAAECgEIAQAAAA==.',Zu='Zulna:BAAALAADCgMIAwAAAA==.',Zw='Zw:BAAALAAECggICwAAAA==.',Zy='Zyprëxa:BAAALAAECgEIAQAAAA==.',['Çr']='Çracked:BAAALAADCgIIAgAAAA==.',['ßr']='ßreezy:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end