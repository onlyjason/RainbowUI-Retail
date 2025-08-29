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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Druid-Feral','DeathKnight-Frost','DeathKnight-Blood','Shaman-Restoration','Druid-Balance','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Holy','Druid-Restoration',}; local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adawna:BAAALAADCggICAAAAA==.Adsaw:BAAALAAECgIIAgAAAA==.',Ae='Aelindia:BAAALAADCgMIBQAAAA==.Aelín:BAAALAAFFAEIAQAAAA==.',Af='Aftershocks:BAAALAAECgMIBAAAAA==.',Ah='Ahnanji:BAAALAAECgIIAgAAAA==.',Al='Alabeard:BAAALAAECgYIDgAAAA==.Alak:BAAALAADCgIIAgAAAA==.Alejandrita:BAAALAADCggICAAAAA==.Aliakin:BAAALAAECgIIBAAAAA==.Allerìa:BAAALAADCggIBwAAAA==.Alteredbeest:BAAALAADCgIIAgAAAA==.Alyssachik:BAAALAAECgQIBQAAAA==.',Am='Amarxd:BAAALAAECgMIBQAAAA==.Ambosi:BAAALAAECgEIAQAAAA==.Amenadiel:BAAALAAECgYICwAAAA==.Amp:BAAALAADCgUIBQAAAA==.',An='Andesipa:BAAALAADCggICQAAAA==.Anduin:BAAALAADCggIDQAAAA==.Angerclaw:BAAALAAECgMIBgAAAA==.Annulled:BAAALAADCggIFwAAAA==.Antorg:BAAALAADCggICAAAAA==.',Ap='Apearlo:BAAALAAECgIIBQAAAA==.Apoth:BAAALAAECgEIAQABLAAECgYIBgABAAAAAA==.Apotheke:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.',Ar='Arakisa:BAAALAADCgcIDgAAAA==.Arcadiah:BAAALAAECgMIAwAAAA==.Arenan:BAAALAADCgIIAgAAAA==.Arkileous:BAAALAAECgMIAwAAAA==.Arokou:BAAALAADCgQIBAAAAA==.Arrowk:BAAALAADCgYIBgAAAA==.Artemmis:BAAALAADCgcICgAAAA==.',At='Attack:BAAALAADCggIDgAAAA==.',Au='Auldenar:BAAALAADCgEIAQAAAA==.Auldrenott:BAAALAADCggICAAAAA==.',Av='Avoken:BAAALAAECgMIBgAAAA==.',Ba='Baed:BAAALAAECgMIAwABLAAECgMIBgABAAAAAA==.Bagel:BAAALAADCgMIBAAAAA==.Balror:BAAALAADCgQIBAAAAA==.Banhmi:BAAALAADCgUIBQABLAADCgYIDQABAAAAAA==.Barntzert:BAAALAADCgcIBwAAAA==.Bartholomew:BAAALAADCgUIBgAAAA==.Basementman:BAAALAADCgUIBQABLAAECggICgABAAAAAA==.Battlebelle:BAAALAADCggICAAAAA==.Baxx:BAAALAADCggICwAAAA==.',Be='Beeloved:BAAALAADCgcIBwAAAA==.Beenu:BAAALAADCggIEAABLAAECgMIAwABAAAAAA==.Bellybert:BAAALAADCgUIBQAAAA==.Benzos:BAAALAAECggIBAAAAA==.Berrd:BAAALAADCgQIBAAAAA==.',Bh='Bhangbhang:BAAALAAECgMIAwAAAA==.',Bi='Biba:BAABLAAECoE8AAICAAgIyiY7AACRAwACAAgIyiY7AACRAwAAAA==.Bigmacs:BAAALAADCggIDwAAAA==.Billyams:BAAALAAECggIEAAAAA==.Bizzarro:BAAALAADCggICAAAAA==.',Bj='Bjornsy:BAAALAAECgYIDQAAAA==.',Bl='Blackstoned:BAAALAADCgcIBwAAAA==.Blazic:BAAALAADCggIDgAAAA==.Bloodycat:BAAALAAECgYIBgAAAA==.Bluerose:BAAALAADCgcIBwAAAA==.Blurry:BAAALAADCgcIEwAAAA==.',Bo='Bohanjiang:BAAALAADCgEIAQAAAA==.Boomtillioom:BAAALAAECgEIAQAAAA==.',Br='Brallen:BAAALAADCggIDgAAAA==.Brewmango:BAAALAADCgYIBgAAAA==.Bricksanchez:BAAALAADCggICAAAAA==.Brindo:BAAALAADCgEIAQAAAA==.Brotherman:BAAALAAECgIIAgAAAA==.',Bu='Bubbleheart:BAAALAADCgcIBwAAAA==.Bullshiftaur:BAAALAADCgYIBgAAAA==.Bunniez:BAAALAAECgQIBAAAAA==.Buschheal:BAAALAADCgEIAQAAAA==.Butterbeers:BAAALAAECgEIAQAAAA==.',['Bö']='Bööse:BAAALAADCgcIDgABLAAECgQIBQABAAAAAA==.',Ca='Cakevswaffle:BAAALAADCggICAAAAA==.Cameltötem:BAAALAADCgEIAQAAAA==.Carl:BAEALAAECgIIAgABLAAECgYICgABAAAAAA==.Catawba:BAAALAADCgIIAgAAAA==.Catiany:BAAALAADCgQIBAAAAA==.',Ce='Cerywen:BAAALAADCggIDAAAAA==.',Ch='Chaddius:BAAALAADCgQIBQAAAA==.Chadwik:BAAALAADCgcIHAAAAA==.Chamtote:BAAALAADCgUIBQAAAA==.Charbzenberg:BAAALAAECgMIAwAAAA==.Charisma:BAAALAAECgYIDgAAAQ==.Cheeseburgrr:BAAALAAECggIAwAAAA==.Chilijayleen:BAAALAAECgEIAQAAAA==.Chøppy:BAAALAAECgIIAwABLAAECggIFgADAC0gAA==.',Cl='Cloax:BAAALAADCgcIBwAAAA==.Clownmeat:BAAALAADCgcIBwAAAA==.',Co='Cobask:BAAALAADCgUIBQAAAA==.Cooleybmc:BAAALAADCggICQAAAA==.Cordelya:BAAALAADCgMIBAAAAA==.Couraegus:BAAALAAECgcIEQAAAA==.Cowchipp:BAAALAADCgYIBgAAAA==.',Cp='Cptchef:BAAALAADCgQIBAAAAA==.',Cr='Crabemoji:BAAALAAECgYIDAAAAA==.Cragasaurus:BAAALAADCgUIBQAAAA==.Critchicken:BAAALAAECgQIBwAAAA==.Croskus:BAAALAADCgUIBgAAAA==.Cryhavok:BAAALAAECgcIEQAAAA==.',Cu='Cutepandaa:BAAALAAECggIBgAAAA==.',Cy='Cyther:BAAALAAECgYICgAAAA==.',Da='Daghar:BAAALAAECggICgAAAA==.Dandoran:BAAALAADCgMIAwAAAA==.Daquavius:BAAALAADCggICAAAAA==.Darknrahll:BAAALAAECgUIBgAAAA==.Davosi:BAAALAAECgIIAgAAAA==.',De='Deadtalini:BAAALAAECgcIEgAAAA==.Deathhead:BAABLAAECoEXAAMEAAgIGyLQBwD2AgAEAAgIGyLQBwD2AgAFAAQIkwUVFgCgAAAAAA==.Deathstarr:BAAALAADCgUIBQAAAA==.Demomachin:BAAALAAECgYIDAAAAA==.Derathen:BAAALAAECgMIBQAAAA==.Desaran:BAAALAADCgYIBgABLAADCggIFgABAAAAAA==.Detalervis:BAAALAAECgYICwAAAA==.Devours:BAABLAAECoEVAAIGAAgIShguDABbAgAGAAgIShguDABbAgAAAA==.Devourss:BAAALAAECgcIEQABLAAECggIFQAGAEoYAA==.',Di='Diadhaid:BAAALAAECgMIAwAAAA==.Dianaah:BAAALAADCgYICgAAAA==.Diddies:BAAALAADCgcIBwAAAA==.Dinonuggie:BAABLAAECoEWAAIHAAgIeiHbBQDsAgAHAAgIeiHbBQDsAgAAAA==.Dirtyhooves:BAAALAADCgcIBwAAAA==.',Do='Docto:BAAALAADCgIIAgAAAA==.Doepfer:BAAALAADCgYIDQAAAA==.Donelei:BAAALAAECgQIBAAAAA==.Donfoga:BAAALAADCgcIBwAAAA==.Doovu:BAAALAADCgQIBAAAAA==.Dora:BAAALAADCgcIBwAAAA==.Dorable:BAAALAADCgIIAgAAAA==.Doragan:BAAALAADCggIEQAAAA==.',Dr='Dragapult:BAAALAAECgcIDwAAAA==.Dragoonn:BAAALAADCgIIAQAAAA==.Dragusysmash:BAAALAADCgEIAQAAAA==.Drakainaa:BAAALAADCgcICgAAAA==.Dralvira:BAAALAAECgYIDgAAAA==.Drugraybush:BAAALAADCggIDgAAAA==.',['Dã']='Dãth:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',Ec='Echpochmak:BAAALAAECggIBgAAAA==.',Ed='Ediurd:BAAALAADCgUIBwAAAA==.',Eg='Eggsheeran:BAABLAAECoEWAAIIAAgIHh8ADgClAgAIAAgIHh8ADgClAgAAAA==.Egirl:BAAALAAECgUIBQABLAAECgYIAwABAAAAAA==.',Eh='Ehayron:BAAALAAECgcIDgAAAA==.',Ei='Eirrin:BAAALAAECgMIAwAAAA==.',El='Elaineh:BAAALAADCggICAAAAA==.Elainer:BAAALAADCggIDwAAAA==.Elendira:BAAALAAECgUIBgAAAA==.Elf:BAAALAADCggICAAAAA==.Elidé:BAAALAADCggIEAABLAAECgEIAgABAAAAAA==.Elleredreaux:BAAALAAECgMIAwAAAA==.',Em='Emurog:BAAALAADCgYIBgAAAA==.',En='Energyturtle:BAAALAADCgcIBwAAAA==.',Er='Eranthis:BAAALAADCgQIBAAAAA==.Erisarra:BAAALAAECgMIAwAAAA==.',Ex='Excanthios:BAAALAADCggICQAAAA==.Exception:BAAALAADCgIIAgAAAA==.',Ez='Ezmelora:BAAALAAECgYICQAAAA==.',Fa='Faiyd:BAAALAADCgcIBwAAAA==.Fancydemon:BAAALAADCgIIAgAAAA==.Fantasie:BAAALAADCgUIBQABLAAECgMIBAABAAAAAA==.Fatsmellycow:BAAALAAECgMIAwAAAA==.Fayia:BAAALAAECgcIEQAAAA==.',Fe='Fearshaman:BAAALAAECggIDgAAAA==.Felbrew:BAAALAAECgYIDgAAAA==.',Fi='Fightor:BAAALAADCgEIAQAAAA==.Firaman:BAAALAADCgcICQAAAA==.Fizzibix:BAAALAAECgIIAQAAAA==.',Fl='Flexxed:BAAALAAECggIEgAAAA==.Florelai:BAAALAADCggIDQAAAA==.',Fo='Foomboosa:BAAALAADCgYIBgABLAAECgQIBQABAAAAAA==.Foopz:BAAALAADCgUIBQABLAADCgYIBgABAAAAAA==.Foreheadkiss:BAAALAAECgEIAQAAAA==.Forgloryy:BAAALAAECgcIDgAAAA==.Foxylock:BAAALAADCgEIAQABLAAECgEIAQABAAAAAA==.',Fr='Frampton:BAAALAAECgEIAgABLAAECgYIDQABAAAAAA==.Freedomfry:BAAALAADCggIDwAAAA==.Friskie:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.Frostway:BAAALAADCgYIBgAAAA==.',['Fé']='Félbringer:BAAALAADCgIIAQAAAA==.',Ga='Gabeowners:BAAALAAECgYIDQAAAA==.Galillei:BAAALAADCggICAAAAA==.',Ge='Gemelo:BAABLAAECoEXAAMJAAgIjxlADwAcAgAJAAcIAhpADwAcAgAKAAII8wz/XgB7AAAAAA==.Getoffmyback:BAAALAAECgIIAgAAAA==.Gettuff:BAAALAADCgMIAwAAAA==.',Gh='Ghhon:BAAALAADCgEIAQAAAA==.',Gi='Gibayy:BAAALAADCggIDwAAAA==.Gigadrake:BAAALAADCgcIBAAAAA==.Gilliamm:BAAALAAECgMIBwAAAA==.Gimborn:BAAALAADCggICAAAAA==.',Gl='Glancey:BAAALAAECgEIAQAAAA==.Glimmer:BAAALAAECgMIBgAAAA==.Glowza:BAAALAAECgMIAwAAAA==.',Go='Golath:BAAALAAECgEIAQAAAA==.Gonthielhunt:BAAALAADCggIFAAAAA==.Goobygumby:BAAALAADCggICgAAAA==.Gorcazzo:BAAALAAECgIIAgAAAA==.Gorgonzormu:BAAALAAECgQIBQAAAA==.',Gr='Graybushh:BAAALAAECgMIBQAAAA==.Graybushpri:BAAALAAECgIIAgAAAA==.Gremlinganks:BAAALAADCgcIBwABLAAECgcIDQABAAAAAA==.Gremsham:BAAALAAECgcIDQAAAA==.Grendar:BAAALAAECgMIBAAAAA==.Griezadin:BAAALAAECgQIBQAAAA==.',Gu='Gumpiz:BAAALAADCggIDQAAAA==.Gunelas:BAAALAADCgcIBwAAAA==.Gunnerbe:BAAALAADCgcIDwAAAA==.',Ha='Haniesh:BAEALAAECgYIDQAAAA==.Hatengar:BAAALAAECgIIAwAAAA==.Haysz:BAAALAADCgYIBgAAAA==.Hazben:BAAALAADCgUICQAAAA==.',He='Healingeyes:BAAALAAECgQIBgAAAA==.Healthcare:BAAALAADCgQICAAAAA==.Hearnzak:BAAALAADCgYIBAAAAA==.',Hi='Hi:BAAALAADCgcIBwAAAA==.Hiatum:BAAALAADCgEIAQAAAA==.Hilltop:BAAALAADCgYIBgAAAA==.Hippo:BAAALAADCgcIEQAAAA==.',Ho='Hodorr:BAAALAADCgcIDgABLAAECgMIBAABAAAAAA==.Hodr:BAAALAAECgMIBAAAAA==.Holrhyn:BAAALAAECgYIDAAAAA==.Holyfaiyd:BAAALAAECgYICgAAAA==.Holynite:BAAALAADCggICAAAAA==.Honami:BAAALAAECgQICQAAAA==.Hotguysixpac:BAAALAADCggICAAAAA==.',Hu='Huntressron:BAAALAADCgcIBwAAAA==.',Ia='Iandra:BAAALAAECgIIAgAAAA==.',Ic='Icebox:BAAALAADCgEIAQAAAA==.',Id='Idarkl:BAAALAADCgcIBwAAAA==.',Ig='Iggyd:BAAALAAECgEIAgAAAA==.',Il='Illidayum:BAAALAADCgQIAwAAAA==.Ilvara:BAAALAADCgcIBwAAAA==.',Im='Imatrollol:BAAALAADCgMIAwAAAA==.Imcooleddown:BAAALAAECgYIBgAAAA==.Imodeein:BAAALAADCgYIBgAAAA==.Impdaddy:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.Impierna:BAAALAAECgIIAgAAAA==.Impierno:BAAALAADCgIIAwABLAAECgIIAgABAAAAAA==.Impknight:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.Implilith:BAAALAADCgcIDAABLAAECgIIAgABAAAAAA==.',Is='Isos:BAAALAAECgYIDgAAAA==.',Iv='Ivremoine:BAAALAAECgYICQAAAA==.',Ja='Jackbeef:BAAALAAECgYIDQAAAA==.Jadeinhell:BAAALAAECgYIDAAAAA==.Jaggedshammy:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Janná:BAAALAAECgMIAwAAAA==.',Je='Jeanna:BAAALAADCgIIAgAAAA==.Jecynth:BAAALAADCggICwAAAA==.Jengun:BAAALAAECgEIAQAAAA==.Jerryfour:BAAALAADCgYIBgAAAA==.Jerryseven:BAAALAADCggIEgAAAA==.Jerrysix:BAAALAADCggIFQAAAA==.',Jo='Joethethird:BAAALAADCggICAAAAA==.',Ju='Jujujalal:BAAALAAECgcIDAAAAA==.Justbeginner:BAAALAADCggICgAAAA==.',Jy='Jyloti:BAAALAADCgQIBAAAAA==.',['Jà']='Jàxx:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.',['Jå']='Jåggy:BAAALAADCgEIAQABLAAECgEIAQABAAAAAA==.',Ka='Kalona:BAAALAADCgUIBwAAAA==.Kalrock:BAAALAAECgMIBgAAAA==.Kango:BAABLAAECoEWAAIKAAgIZCFrBQAPAwAKAAgIZCFrBQAPAwAAAA==.Kanisurra:BAAALAAECgIIAgAAAA==.Karkit:BAAALAADCggIDQAAAA==.Karl:BAAALAAECgEIAQAAAA==.Kathyrine:BAAALAADCgcIBQAAAA==.Kaygoogii:BAABLAAECoEXAAIKAAcILyDCDgB9AgAKAAcILyDCDgB9AgAAAA==.',Ke='Kercipre:BAAALAADCgcIDAAAAA==.',Kh='Khago:BAAALAAECgYIDAAAAA==.Khalaster:BAAALAADCgYICAAAAA==.Khraxus:BAAALAADCggICAAAAA==.',Ki='Killingspre:BAAALAAECgEIAgAAAA==.Kitagawa:BAAALAAECgMIAwAAAA==.Kitesama:BAAALAADCggIEwAAAA==.',Kn='Kneeonater:BAAALAADCgcIBwAAAA==.Knurlin:BAAALAAECgQIBQAAAA==.',Ko='Kobito:BAAALAAECggIEgAAAA==.Komachii:BAAALAADCgYIBgAAAA==.Koup:BAAALAAECggIEQAAAA==.Koupe:BAAALAADCggIDwABLAAECggIEQABAAAAAA==.Koupl:BAAALAADCggICAABLAAECggIEQABAAAAAA==.Koupt:BAAALAADCgIIAgABLAAECggIEQABAAAAAA==.',Kr='Krachiolla:BAAALAADCgUIBQAAAA==.Kranx:BAAALAADCggICwAAAA==.Kriss:BAAALAADCgcIBwAAAA==.Krukkare:BAAALAADCgUIBQAAAA==.',Ku='Kundak:BAAALAADCggIDwAAAA==.',Ky='Kylvanas:BAAALAADCgYIBgAAAA==.',La='Lagginwaggin:BAAALAADCgUIBQAAAA==.Laowan:BAAALAADCgcICgAAAA==.Las:BAAALAAECgYIBwABLAADCggICAABAAAAAA==.Lastlight:BAAALAADCggIEQAAAA==.Latinaslayx:BAAALAAECgMIBQAAAA==.Lavs:BAAALAAECgcIDgAAAA==.Lazy:BAAALAADCgIIAgAAAA==.',Le='Legendweaver:BAAALAADCggIDQABLAAECgEIAQABAAAAAA==.Lelgard:BAAALAADCgMIAwAAAA==.Lev:BAAALAADCgIIAgAAAA==.',Li='Lightsbane:BAAALAAECgcICwAAAA==.Lilytily:BAAALAADCgcIBwAAAA==.Linthera:BAAALAAECgMIAwAAAA==.Lithdrel:BAAALAAECgEIAQAAAA==.Lithilia:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Lo='Loamathor:BAAALAADCgIIAgAAAA==.Lonníe:BAAALAAECgMIAwAAAA==.Lorilyn:BAAALAAECgcIDgAAAA==.Lostarkangel:BAAALAADCggIDwAAAA==.',Lu='Lucciola:BAAALAADCgcIDAAAAA==.Lumineia:BAAALAAECggICAAAAA==.Lunachick:BAAALAADCgIIAgAAAA==.Lunarfire:BAAALAADCggIDwAAAA==.Lunarus:BAAALAADCggIEwAAAA==.Lurline:BAAALAAECgYIBgAAAA==.Luxiu:BAAALAAECgEIAQAAAA==.',Ly='Lynnu:BAAALAADCgIIAgAAAA==.',Ma='Madapipa:BAAALAADCgYICAAAAA==.Maelona:BAAALAAECgIIAgAAAA==.Magthars:BAAALAADCgQIBAAAAA==.Mammaztok:BAAALAADCggIEgAAAA==.Mangorki:BAAALAADCgMIAwAAAA==.Marshmalow:BAAALAAECgQIBQAAAA==.Masarrap:BAAALAADCggICAAAAA==.',Mc='Mctigly:BAAALAAECgEIAgAAAA==.',Me='Megadefi:BAAALAAECgQIBgAAAA==.',Mi='Mikelmyers:BAAALAADCgQIBAAAAA==.Mimir:BAAALAADCgcIEAAAAA==.Minacold:BAAALAAECgIIAgAAAA==.Miniblué:BAAALAAECgUICAAAAA==.Miniime:BAAALAADCgUIBwAAAA==.Miniweed:BAAALAAECgIIAgAAAA==.Mistyfist:BAAALAADCgQIBAAAAA==.',Mo='Moadeab:BAAALAADCggIDQAAAA==.Mogando:BAAALAADCgUIBQABLAAECgUIBQABAAAAAA==.Mogdeknarg:BAAALAADCggIDAABLAAECgMIBwABAAAAAA==.Mogdemgarg:BAAALAADCgMIAwABLAAECgMIBwABAAAAAA==.Mogpalgarg:BAAALAAECgEIAQABLAAECgMIBwABAAAAAA==.Mogrodrag:BAAALAADCggICAABLAAECgMIBwABAAAAAA==.Mogrogarg:BAAALAAECgMIBwAAAA==.Molleficence:BAAALAADCggICAAAAA==.Moonangel:BAAALAADCggICAAAAA==.Morgaliice:BAAALAAECgYICQAAAA==.Morgas:BAAALAAECgQIBAAAAA==.',Mu='Mummakay:BAAALAADCgEIAQAAAA==.Munkatron:BAAALAAECgYIDQAAAA==.Munric:BAAALAAECgYICQAAAA==.Murlock:BAAALAAECgMIAwAAAA==.Murozond:BAAALAADCggIBgAAAA==.Muskycrit:BAAALAADCgEIAQAAAA==.Mussopo:BAAALAADCggIDwAAAA==.',My='Mykerz:BAAALAADCggICgAAAA==.Mysaeris:BAAALAADCgcIEAAAAA==.Myw:BAABLAAECoEYAAIGAAgIiiGgAgD9AgAGAAgIiiGgAgD9AgAAAA==.',['Mó']='Mórningstar:BAAALAAECgMIAwAAAA==.',Na='Nachothings:BAAALAAECgcIEQAAAA==.Nattsu:BAAALAADCgEIAQAAAA==.Nautico:BAAALAADCgUIBQAAAA==.',Nd='Ndnlove:BAAALAADCgIIAgAAAA==.',Ni='Nickelos:BAAALAADCgcICQAAAA==.Nightmist:BAAALAADCgQICAAAAA==.',No='Nolaki:BAAALAADCggIEwABLAAECggICgABAAAAAA==.Noodledrake:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.Noodleman:BAAALAADCgUICQABLAAECgMIBQABAAAAAA==.Noodlestang:BAAALAAECgMIBQAAAA==.Norgand:BAAALAAECgUIBQAAAA==.Nornar:BAAALAAECgMIBwAAAA==.Nosleepz:BAAALAAECgcIEAAAAA==.Notanowl:BAAALAAECgQIBAAAAA==.Notprepared:BAAALAADCgEIAQAAAA==.Noxra:BAAALAADCgcIBwAAAA==.Nozenxo:BAAALAADCgIIAgAAAA==.',Ny='Nyduss:BAAALAADCgEIAQAAAA==.Nyxia:BAAALAADCgcICwAAAA==.Nyxøs:BAAALAADCgUIBQAAAA==.',Od='Odeeinstill:BAAALAADCggIDQAAAA==.',Om='Omaboa:BAAALAAECgIIAgAAAA==.',On='Onoda:BAAALAAECgMIAwAAAA==.',Oo='Oosceola:BAAALAAECgEIAQAAAA==.',Op='Optimize:BAAALAAECggICAAAAA==.',Or='Oraga:BAAALAAECgIIBAAAAA==.Orastal:BAAALAADCgcIBwAAAA==.',Pa='Palabash:BAAALAADCgMIAwAAAA==.Pandadander:BAAALAADCggIFwABLAADCgEIAQABAAAAAA==.Pantszilla:BAAALAADCgEIAQAAAA==.Papideleche:BAAALAADCgYIBgAAAA==.',Pe='Pebbles:BAAALAADCgUIBQAAAA==.Pee:BAABLAAECoEXAAICAAgIxiBoBgDwAgACAAgIxiBoBgDwAgAAAA==.Peghane:BAAALAADCgUIBwAAAA==.Peri:BAAALAAECgEIAQAAAA==.',Ph='Phoenixburn:BAAALAADCgcIDAAAAA==.Physiodemon:BAAALAAECgcIEAAAAA==.',Po='Ponchoe:BAAALAAECgIIAgAAAA==.Poobahdrag:BAAALAAECgcIDgAAAA==.',Pr='Predatauren:BAAALAADCgQIBAAAAA==.Primalpaw:BAAALAAECgEIAQAAAA==.',Ps='Psyfox:BAAALAAECgMIBQAAAA==.',Pu='Pumpington:BAAALAADCgcICQAAAA==.Push:BAAALAADCgEIAQAAAA==.',Pw='Pwepew:BAAALAAECgYIBgAAAA==.',Py='Pyrei:BAAALAADCggICAAAAA==.',Qi='Qid:BAAALAADCgEIAQAAAA==.',Qt='Qtlol:BAAALAAECgcIDgAAAA==.',Qy='Qyopy:BAAALAADCgUIBgAAAA==.',Ra='Racken:BAAALAAECgYICgAAAA==.Ragestrike:BAAALAADCgcIBwAAAA==.Ramped:BAAALAAECgEIAQAAAA==.Rangedbusch:BAAALAADCgYICQAAAA==.Ranzor:BAAALAAECgYICgAAAA==.Raveyn:BAAALAAECgYICQAAAA==.Raynorx:BAAALAADCgYICwAAAA==.',Re='Redagarn:BAAALAADCgcIBwAAAA==.Reef:BAAALAAECgIIAgAAAA==.Rekiehunter:BAAALAAECgYIDAAAAA==.Remsie:BAABLAAECoEWAAIEAAgILyPLBQAVAwAEAAgILyPLBQAVAwAAAA==.Retnuh:BAAALAAECgYIDAAAAA==.Revivified:BAAALAAECgMIBAAAAA==.',Rh='Rheiner:BAAALAADCgcICQAAAA==.Rhynai:BAAALAADCggIEAAAAA==.',Ri='Rikori:BAAALAADCgcICAABLAAECgIIAgABAAAAAA==.Riptobits:BAAALAADCgQIBAAAAA==.Riskfree:BAAALAAECgYIDAAAAA==.Riskfreedk:BAAALAADCgMIAwAAAA==.Ristin:BAAALAADCgUIBgAAAA==.',Ro='Roderika:BAAALAADCgcIBwABLAAECgcIDwABAAAAAA==.Rollthebeef:BAAALAAECgUIBQAAAA==.Rord:BAAALAAECgYIEwAAAA==.Rosalei:BAAALAAECgEIAQAAAA==.Rottensword:BAAALAADCgEIAgAAAA==.',Ru='Rufío:BAAALAADCgMIAwAAAA==.Rumblez:BAAALAADCggICAAAAA==.Runeth:BAAALAADCggIFgAAAA==.Runicstrike:BAAALAAECggIDgAAAA==.',Ry='Ryab:BAAALAADCgMIAwAAAA==.Ryuck:BAAALAADCgMIAwAAAA==.',Sa='Sahra:BAAALAAECgYIDAAAAA==.Sanstik:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Saraphina:BAAALAAECgEIAQAAAA==.',Sc='Schnooks:BAAALAADCggICAAAAA==.',Se='Selfcestyuri:BAAALAAECgEIAQAAAA==.Selithil:BAAALAADCgcIDwAAAA==.Selvalamhi:BAAALAADCgEIAQABLAAECgUIBQABAAAAAA==.Semi:BAAALAAECgEIAgAAAA==.Senh:BAAALAAECgEIAQAAAA==.Serafyne:BAAALAADCgYICQAAAA==.Serpompom:BAAALAAECgYIDQAAAA==.Seukaslock:BAAALAADCgYIBgAAAA==.',Sh='Shadesz:BAAALAAECgMIBAAAAA==.Shadowborne:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Shamyshida:BAAALAADCgcIBwAAAA==.Shardy:BAAALAADCggIDgABLAADCggIFgABAAAAAA==.Sharknurse:BAAALAADCgQIBAAAAA==.Sherfight:BAAALAAECgMIBAAAAA==.Shnyaga:BAABLAAECoE8AAILAAgI6yYVAACVAwALAAgI6yYVAACVAwAAAA==.Shockuary:BAAALAAECgcIDQAAAA==.Shotty:BAAALAADCgcIBwAAAA==.Shruikansz:BAAALAADCggICAAAAA==.Shund:BAAALAADCgcIDAAAAA==.',Si='Sibindzi:BAAALAADCgIIAgAAAA==.Silvrq:BAAALAADCgYIBgAAAA==.',Sk='Skinwalk:BAAALAAECgIIAgAAAA==.',Sl='Slaanesh:BAAALAADCgcIDQAAAA==.Slackerftw:BAAALAADCggIEAAAAA==.Slamhog:BAAALAAECgIIAwAAAA==.Slick:BAAALAADCgcICAAAAA==.Släshträp:BAAALAAECgYIDQAAAA==.',Sn='Sneakyyaki:BAAALAADCgMIAwAAAA==.Snowfae:BAAALAADCgEIAQABLAAECgYICQABAAAAAA==.Snowmonkey:BAAALAAFFAEIAQAAAA==.',So='Soroku:BAAALAAECgMIBQAAAA==.',Sp='Spacetiger:BAAALAADCgIIAgAAAA==.Sparo:BAAALAADCgEIAQAAAA==.Specsdraco:BAAALAAECgYIDgAAAA==.Spewpuke:BAAALAAECgMIBQAAAA==.Spicytomato:BAAALAAECgIIAgAAAA==.',Sq='Squeese:BAAALAADCgcIBwABLAADCggIFwABAAAAAA==.',St='Staci:BAAALAAECgYICwAAAA==.Starstorm:BAAALAAECgIIAwAAAA==.Stee:BAAALAADCgUIBQAAAA==.Steelhoof:BAAALAADCggIDwAAAA==.Steelsham:BAAALAAECgIIAgAAAA==.Stonedd:BAAALAADCgQIBAAAAA==.Strawmanual:BAAALAADCgcIEQAAAA==.',Sy='Sylrana:BAAALAAECgYICQAAAA==.',Ta='Taano:BAAALAADCggIEAAAAA==.Tabuta:BAAALAADCggIEAAAAA==.Taktikil:BAAALAADCggIDwAAAA==.Talrad:BAAALAAECgYICwAAAA==.Tamerlein:BAAALAADCggICAAAAA==.Tankington:BAAALAADCgEIAQAAAA==.Taylorswift:BAAALAADCgcIDgAAAA==.Tazffs:BAAALAADCgcICwAAAA==.Tazlmao:BAAALAADCgMIAwAAAA==.Tazomfg:BAAALAADCggICAAAAA==.',Te='Teldrasa:BAAALAAECgcIDwAAAA==.Telisa:BAAALAADCgYICQAAAA==.Telori:BAAALAAECgIIBAAAAA==.Tempér:BAAALAAECgEIAgAAAA==.Tensoon:BAAALAAECgUICQAAAA==.',Th='Tharot:BAAALAADCgcICgAAAA==.Thebeefchief:BAAALAAECgEIAQABLAAECgUIBQABAAAAAA==.Thebigiron:BAAALAAECgEIAQAAAA==.Thebigmon:BAAALAADCggIGwAAAA==.Thedabara:BAAALAADCgcIDAAAAA==.Thegriddler:BAAALAADCgMIAwAAAA==.Theory:BAAALAAECgYICgAAAA==.Thiccjinbei:BAAALAADCgQIBAAAAA==.Thoumoos:BAAALAADCgMIAwAAAA==.Thowra:BAAALAADCgMIAwAAAA==.Thrashworld:BAAALAAECgcICgAAAA==.Thurman:BAEALAAECgYICgAAAA==.Thôr:BAAALAADCgcIBwAAAA==.',Ti='Tiallan:BAAALAADCgUICQAAAA==.Timoleon:BAAALAADCgQICAAAAA==.Tinkytank:BAAALAADCgcIBwAAAA==.',Tl='Tlaloc:BAAALAADCgYIBgAAAA==.',To='Toastyshamy:BAAALAADCggICAAAAA==.Tofrenm:BAAALAADCggIFgAAAA==.Togashi:BAAALAAECgMIAwAAAA==.Tomekeeper:BAAALAADCgUIBwAAAA==.Totalzug:BAAALAADCgEIAQABLAAECgYIEwABAAAAAA==.',Tr='Treespirit:BAAALAADCgIIAgAAAA==.Tremorvoid:BAAALAADCgIIAwAAAA==.Trunkmuffin:BAAALAADCgYIBgAAAA==.',Tu='Tunksfly:BAAALAADCgQIBAAAAA==.',Tw='Twoporkchops:BAAALAADCgcIDQAAAA==.',Ty='Tyrur:BAAALAAECgIIAgAAAA==.',Ug='Uggobug:BAAALAAECgEIAQAAAA==.Uglyashell:BAAALAAECgUIBgAAAA==.',Um='Umbrielagosa:BAAALAAECgEIAQAAAA==.Umbriella:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Un='Unmalgache:BAAALAADCggIEAAAAA==.',Va='Valerian:BAAALAADCgEIAQAAAA==.Valiath:BAAALAADCgUIBQAAAA==.Valoren:BAAALAADCgcIBwAAAA==.Valtaea:BAAALAAECgMIAwAAAA==.',Vi='Virides:BAAALAADCgIIAgAAAA==.Vixol:BAAALAAECgEIAQAAAA==.',Vy='Vyldrok:BAAALAAECgMIBQAAAA==.Vylric:BAAALAADCgUIBwAAAA==.',Wa='Waarsêer:BAAALAAECgEIAQAAAA==.Wackah:BAAALAAECgcIDgAAAA==.Wanpisu:BAAALAAECgYIDQAAAA==.Wargud:BAAALAADCgYIBgAAAA==.Warlucifer:BAAALAAECgEIAQAAAA==.',We='Weeniehutjr:BAAALAAECgMIBgAAAA==.',Wh='Whalephant:BAAALAAECgYIDAAAAA==.Whyvara:BAAALAADCggIDwAAAA==.Whyvawa:BAAALAADCggICAAAAA==.',Wi='Wintergreen:BAAALAAECgEIAQAAAA==.',Wo='Wolnney:BAAALAAECgMIBwAAAA==.Wownow:BAAALAADCgEIAQAAAA==.',Xa='Xandi:BAAALAAECgUIBQABLAAECggIFgAHAHohAA==.',Xo='Xoion:BAAALAADCggIBwAAAA==.',Ya='Yakimage:BAAALAADCgUIAQAAAA==.',Ye='Yern:BAAALAADCggIBwAAAA==.',Yu='Yuhaneun:BAAALAAECgMIAwAAAA==.',Za='Zaakk:BAAALAADCgcIBwAAAA==.Zanza:BAAALAAECgQIBQAAAA==.Zapupa:BAAALAAFFAMIAgAAAA==.',Ze='Zegzmashin:BAAALAAECgEIAQAAAA==.Zekama:BAACLAAFFIEHAAIMAAQIXBHBAABRAQAMAAQIXBHBAABRAQAsAAQKgRoAAgwACAj5Go8LAEECAAwACAj5Go8LAEECAAAA.Zeregerevyn:BAAALAADCgMIBQAAAA==.',Zo='Zodin:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Zoltav:BAAALAADCgYIBgAAAA==.Zoltaz:BAAALAADCgcIBwAAAA==.',Zu='Zumaloo:BAAALAAECgEIAQAAAA==.',['Zä']='Zäbe:BAAALAAECgIIAgAAAA==.',['Âb']='Âbaddön:BAAALAADCgYIBgAAAA==.',['Çh']='Çharles:BAAALAAECgYICgAAAA==.Çhefhunter:BAAALAAECgEIAQAAAA==.',['Ðr']='Ðrpèppèr:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end