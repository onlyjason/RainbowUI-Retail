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
 local lookup = {'Unknown-Unknown','Monk-Windwalker','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation','Warrior-Protection','Warrior-Fury','Priest-Holy','Mage-Frost','DemonHunter-Havoc','DeathKnight-Frost','Mage-Arcane',}; local provider = {region='US',realm='Garona',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Aculockk:BAAALAAECgEIAQAAAA==.',Ad='Adarus:BAAALAADCgcIBwAAAA==.',Ai='Airz:BAAALAAECgMIBAAAAA==.',Ak='Akigarmemer:BAAALAADCgYIBgAAAA==.Akrichie:BAAALAADCggICAAAAA==.Akâkiôs:BAAALAAECgEIAQAAAA==.',Al='Aladorman:BAAALAAECgEIAQAAAA==.Alamo:BAAALAAECgEIAQAAAA==.Albertlin:BAAALAAECgEIAQAAAA==.Alexpaladin:BAAALAAECgIIAgAAAA==.Alheria:BAAALAAECgYICQAAAA==.Altagrave:BAAALAADCgEIAQAAAA==.Altex:BAAALAAECgcIEAAAAA==.Altexa:BAAALAAECgIIAgABLAAECgcIEAABAAAAAA==.Alyosha:BAAALAADCgIIAgAAAA==.',Am='Amakuagsak:BAAALAAECgMIBAAAAA==.',An='Anfrin:BAAALAAECgMIAwAAAA==.Angelcastiel:BAAALAAECgMIBAAAAA==.Angrylizard:BAAALAADCgEIAQAAAA==.Aniravia:BAABLAAECoEWAAICAAgIOhqcBwBXAgACAAgIOhqcBwBXAgAAAA==.Annthea:BAAALAADCgUIBQAAAA==.Anthren:BAAALAAECgMIAwAAAA==.',Ao='Aoifè:BAAALAADCgcIBwAAAA==.',Ap='Apollo:BAAALAAECgcIDwAAAA==.',Ar='Aragaren:BAAALAADCggICAAAAA==.Arakis:BAAALAADCgQIBAAAAA==.Arasthel:BAAALAAECgMIAwAAAA==.Archdiocese:BAAALAAECgMIAwAAAA==.Areliete:BAAALAADCgcIBwAAAA==.',As='Ashe:BAABLAAECoEXAAIDAAgIPiX7AQA1AwADAAgIPiX7AQA1AwAAAA==.Ashebringer:BAAALAADCgUIBQAAAA==.',At='Atownzozo:BAAALAAECgYICwAAAA==.Attaraxia:BAABLAAECoEYAAIEAAgI5iG0BwDnAgAEAAgI5iG0BwDnAgAAAA==.',Au='Augtistic:BAAALAAECgUICAAAAA==.Austyn:BAAALAADCggICAAAAA==.',Av='Avalora:BAAALAADCgcICwAAAA==.Aviandras:BAAALAAECgUICAAAAA==.',Ba='Baphomett:BAAALAAECgUICQAAAA==.Bartolomew:BAAALAAECgYIDgAAAQ==.',Be='Bedemere:BAAALAAECgIIAgAAAA==.Beepers:BAAALAAECgcIDwAAAA==.Behodahlia:BAAALAAECgIIBAAAAA==.Bendover:BAAALAADCgEIAQAAAA==.Bersurkel:BAAALAAECgEIAQAAAA==.',Bi='Bibleman:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Bipolar:BAAALAAECgEIAQAAAA==.Bitterblood:BAAALAAECgcIEAAAAA==.',Bl='Blackmuu:BAAALAADCggICAAAAA==.',Bo='Bonchum:BAAALAADCgMIAwAAAA==.Boomzura:BAAALAADCgUIBQAAAA==.Bowiiesenpai:BAAALAAECgQIBwAAAA==.',Br='Bragontix:BAABLAAECoEWAAIFAAgIZBunCQCBAgAFAAgIZBunCQCBAgAAAA==.Brightxan:BAAALAAECgcIDQAAAA==.Brownbeard:BAAALAAECgIIAgAAAA==.',Bu='Bufftanks:BAAALAAFFAIIAgAAAA==.Bullgogi:BAAALAAECgEIAQAAAA==.Burninator:BAAALAAECgYIBwAAAA==.Bus:BAACLAAFFIEFAAIGAAUIqg6TAACJAQAGAAUIqg6TAACJAQAsAAQKgSEAAwYACAjvI8cBACsDAAYACAh5I8cBACsDAAcACAhcHHkSAD0CAAAA.Butterrs:BAAALAAECggIFQAAAQ==.',Ca='Cahm:BAAALAADCgcIBwAAAA==.Cainballo:BAAALAADCgcIDAAAAA==.Captnstabbin:BAAALAADCgQIBAAAAA==.',Ce='Celadorn:BAAALAADCggIEAAAAA==.',Ch='Chaosfist:BAAALAADCggIAQAAAA==.Charizardy:BAAALAADCgUICQAAAA==.Charuzu:BAAALAAECgMIAwAAAA==.Chaurana:BAAALAAECgMIAwAAAA==.',Cl='Clapncheeks:BAAALAAECggICAAAAA==.',Co='Coleb:BAAALAAECgMIAwAAAA==.Cortc:BAAALAAECgYICQAAAA==.',Cu='Cuigy:BAAALAAECgIIBAAAAA==.Cunday:BAAALAADCgUIBQAAAA==.',Cy='Cyriene:BAAALAAECgMIAwAAAA==.',Da='Daevas:BAAALAAECgYIBgABLAAECgYICAABAAAAAA==.Dagadin:BAAALAAECgEIAQAAAA==.Daylen:BAAALAAECgMIAwAAAA==.',De='Deafknights:BAAALAAECgcIEAAAAA==.Deathfaces:BAAALAADCgYIBgAAAA==.Deku:BAAALAADCgcIDAAAAA==.Dendrada:BAAALAAECgMIAwAAAA==.Dey:BAAALAADCgMIAwAAAA==.',Dh='Dhobren:BAAALAADCgEIAQAAAA==.',Di='Dirtynome:BAAALAADCggICAAAAA==.Disclexic:BAAALAAECgEIAQAAAA==.Discofiend:BAAALAAECgYIBgAAAA==.',Do='Doncowleone:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Dotharoar:BAAALAAECgYICwAAAA==.Dotisa:BAAALAAECgIIAwAAAA==.Dotmaetricks:BAAALAADCggIDwAAAA==.',Dr='Draccorr:BAAALAADCgYIBgAAAA==.Dragonite:BAAALAAECgQIBQAAAA==.Drazi:BAAALAADCgEIAQAAAA==.Drelythir:BAAALAADCgEIAQAAAA==.Drfumanchu:BAAALAAECgYICQAAAA==.Drotgar:BAAALAADCggIEQAAAA==.',Du='Duna:BAAALAAECgMIAwAAAA==.Dungoofed:BAAALAADCgQIBQAAAA==.Durge:BAAALAAECgYICAAAAA==.',Ed='Edisonn:BAAALAAECgcIEAAAAA==.',Ee='Eestella:BAAALAADCgMIBgAAAA==.',El='Elarine:BAAALAAECgcIDQAAAA==.Elghinn:BAAALAAECgcIDwAAAA==.Elizataylor:BAAALAADCgcICgAAAA==.Ellie:BAAALAAECgMIAwAAAA==.Elroy:BAAALAADCgcIBwAAAA==.',Em='Emernantus:BAAALAAECgMIBgAAAA==.',En='Enderath:BAAALAADCggIDQAAAA==.Entara:BAAALAAECgEIAQAAAA==.',Et='Ethallas:BAAALAAECgIIAgAAAA==.',Eu='Eunbyeol:BAAALAAECgMIBQAAAA==.',Ex='Excidium:BAAALAAECgcIDwAAAA==.',Fa='Faeria:BAAALAAECgMIBQAAAA==.Fatnchunkydk:BAAALAAECgMIBAAAAA==.',Fe='Feeblemind:BAAALAAECgMIAwAAAA==.Felhorns:BAAALAAECgEIAQAAAA==.Feli:BAAALAAECgIIAgAAAA==.Fellastin:BAAALAADCgQIBAAAAA==.Felmommy:BAAALAADCgcIBwAAAA==.Felrindan:BAAALAAECgMIAwAAAA==.Fender:BAAALAAECgEIAQAAAA==.',Fh='Fhtägndazs:BAAALAAECgQICQAAAA==.',Fi='Finfangfoom:BAAALAADCgMIAwABLAAECgYICQABAAAAAA==.Fishermonk:BAAALAAECgYIBwABLAAFFAIIAgABAAAAAA==.Fistsgoburr:BAAALAADCgMIAwAAAA==.Fizban:BAAALAADCggICAAAAA==.',Fl='Flory:BAAALAAECgYICgAAAA==.Floweroflife:BAAALAAECgYIBgAAAA==.Flyinweasle:BAAALAAECgYICgAAAA==.Flyntt:BAAALAAECgYIDgAAAA==.',Fo='Four:BAAALAAECgIIAgAAAA==.',Fr='Freepuppies:BAAALAAECgEIAQAAAA==.',Fu='Fuzzycheese:BAAALAAECgEIAQAAAA==.',Fw='Fwakos:BAAALAADCgIIAgAAAA==.',['Fä']='Fätherdoc:BAAALAAECgEIAQAAAA==.',Ga='Gainflings:BAAALAAFFAEIAQAAAA==.Gaivahros:BAAALAAECgMIAwAAAA==.Gakdruid:BAAALAAECgYIDAAAAA==.Gakmonk:BAAALAAECgIIAgAAAA==.Galathil:BAAALAAECgMIAwAAAA==.Galaway:BAAALAADCggIEAAAAA==.Gartah:BAAALAAECgIIBAAAAA==.Gausse:BAAALAADCgcIBwAAAA==.',Gd='Gdlez:BAAALAADCgUIBQAAAA==.',Ge='Gerionier:BAAALAADCggIDwAAAA==.',Gh='Gholdnor:BAABLAAECoEWAAIIAAgIwBnpCgB8AgAIAAgIwBnpCgB8AgAAAA==.',Gi='Gigazap:BAAALAAECgEIAQAAAA==.',Gl='Glandree:BAAALAAECgEIAQAAAA==.Gleesonn:BAAALAADCggICAAAAA==.',Go='Goatroth:BAAALAADCgcIBwAAAA==.Golosan:BAAALAAECgcIDwAAAA==.Goododie:BAAALAAECgMIAwAAAA==.',Gr='Grayback:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.',Gw='Gwain:BAAALAADCgMIAwAAAA==.',Ha='Hafnia:BAAALAAECgMIAwAAAA==.Haoasakura:BAAALAAECgQICAAAAA==.Harco:BAAALAAECgcIDwAAAA==.Harite:BAAALAADCgUIBQAAAA==.Haybuse:BAAALAAECgcIDQAAAA==.',He='Healzforfood:BAAALAAECgQIBQAAAA==.Heap:BAAALAAECgcIEAAAAA==.Hellraising:BAAALAAECgMIAwAAAA==.Heslashhymn:BAAALAAECgMIBAAAAA==.Hewnoshaqa:BAAALAAECgYICwAAAA==.',Hi='Hitormist:BAAALAAECgMIBQABLAAECgYICAABAAAAAA==.',Ho='Holdmydk:BAAALAADCgQIBAAAAA==.Holycrix:BAAALAAECgcIDwAAAA==.Honkmyudders:BAAALAADCgQIBQAAAA==.Horns:BAAALAADCgEIAQAAAA==.Hotlunch:BAAALAADCggIDwAAAA==.',Hu='Huntar:BAAALAAECgIIBAAAAA==.',Hy='Hydrine:BAAALAAECgMIBgAAAA==.',['Hæ']='Hædés:BAAALAADCgcIBwAAAA==.',Ic='Iceyboy:BAAALAAECgIIAgAAAA==.Icoulddowork:BAAALAAECgcIDwAAAA==.Icyveins:BAAALAADCgYIBwAAAA==.',Id='Idoworkz:BAAALAADCgcIBwABLAAECgcIDwABAAAAAA==.',Ih='Ihatesunday:BAAALAADCggIEgAAAA==.',Ik='Ikazuchi:BAAALAAECgQIBgAAAA==.',Im='Imagirl:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.Imk:BAAALAAECgMIAwAAAA==.Impassion:BAAALAADCgQIBAAAAA==.Imreadytodie:BAAALAAECgIIBAAAAA==.',In='Intentions:BAAALAAECgEIAQAAAA==.',Io='Iock:BAAALAAECgcIDwAAAA==.',Ir='Ironarms:BAAALAAECgcIDwAAAA==.',Is='Isaa:BAAALAADCgEIAQAAAA==.',Iw='Iwdominate:BAAALAAECgYIDAAAAA==.',Iz='Izanagí:BAAALAADCggICAABLAAECggIDwABAAAAAA==.',Ja='Jaida:BAAALAAECgMIBAAAAA==.Jambo:BAAALAADCgcIBwAAAA==.Jardarkbinks:BAAALAAECgIIAgAAAA==.',Jj='Jjennypoo:BAAALAAECgIIBAAAAA==.',Jo='Johnwarrior:BAAALAAECgIIAgAAAA==.',Jr='Jrobocop:BAAALAAECgUICQAAAA==.',Ju='Juduspriestt:BAAALAAECgEIAQAAAA==.Justjake:BAAALAAECgIIAgAAAA==.Justyna:BAAALAADCgcIBwAAAA==.',['Jí']='Jímmy:BAAALAAECgIIAwAAAA==.',Ka='Kaekko:BAAALAAECgEIAQAAAA==.Kaekoh:BAAALAAECgcIDwAAAA==.Kaelathaniel:BAAALAAECgYICQAAAA==.Kains:BAAALAAECgQIBQAAAA==.Kalerito:BAAALAAECgUICAAAAA==.Kalilm:BAAALAADCggICAAAAA==.Kanox:BAAALAADCgUIBQAAAA==.Kassmara:BAAALAADCgMIAwAAAA==.Kayblood:BAAALAAECgcIDgAAAA==.Kazaf:BAAALAAECgMIBwAAAA==.',Ke='Kehen:BAAALAAECgMIAwAAAA==.Keitrek:BAAALAAECgYIDgAAAA==.Keomag:BAAALAADCgQIBAAAAA==.',Ki='Kibalion:BAAALAAECgIIBAAAAA==.Killbent:BAAALAADCgcIEwAAAA==.Kinnky:BAAALAAECgIIBAAAAA==.Kittyglitter:BAAALAAECgIIAgAAAA==.Kivdruid:BAAALAAECgcICgAAAA==.',Kk='Kkty:BAAALAADCgMIAwABLAADCgMIAwABAAAAAA==.',Kn='Knez:BAAALAAECgIIBAAAAA==.',Ko='Kodexia:BAAALAAECgYICwAAAA==.',Kr='Kreettip:BAAALAAECgYIDgAAAA==.Kror:BAAALAAECgcIEAAAAA==.Krystalynn:BAAALAADCgUIBQAAAA==.',Ku='Kugamoo:BAAALAAECgIIAgAAAA==.Kugome:BAAALAADCgcIDAAAAA==.',Ky='Kylex:BAAALAADCgQIBAABLAADCggIEQABAAAAAA==.Kyuyoung:BAAALAADCgMIAwABLAAECgMIBQABAAAAAA==.',Lc='Lckdown:BAAALAAECgMIAwAAAA==.',Le='Ledonna:BAAALAADCgYICAAAAA==.Leopole:BAAALAADCgUICQAAAA==.Leviste:BAAALAADCgcIBwAAAA==.',Li='Lightly:BAAALAAECgIIBAAAAA==.Lightsocket:BAAALAADCgcICQAAAA==.Liltroy:BAAALAADCgMIAwAAAA==.',Ll='Llysadia:BAAALAADCgcIBwAAAA==.',Lo='Loaksdh:BAAALAAECgcIEAAAAA==.Lorilei:BAAALAADCgcIBwAAAA==.Lovi:BAAALAAECggICwAAAA==.',Lu='Luckyboi:BAAALAAECgMIBwAAAA==.Lumos:BAAALAAECgcIDwAAAA==.Lunasael:BAAALAADCgcIBwAAAA==.',Ly='Lykie:BAAALAAECgcIDwAAAA==.Lyone:BAAALAAECgQICQAAAA==.',Ma='Mafic:BAAALAAECgcICgAAAA==.Magaggie:BAAALAADCggIHAAAAA==.Magalis:BAAALAAECgIIBQAAAA==.Mageyoulookk:BAAALAAECgUIBQAAAA==.Maharri:BAAALAADCgEIAQAAAA==.Maliki:BAAALAAECgYIBgAAAA==.Manatramp:BAAALAADCgcIFAAAAA==.Mandothion:BAAALAAECggIBgAAAA==.Mantissa:BAAALAADCgYIBgAAAA==.Marìe:BAAALAADCggICAAAAA==.Masacre:BAAALAAECgEIAQAAAA==.Maverickdog:BAAALAAECgcIDwAAAA==.',Me='Meeshie:BAAALAAECgYIDQAAAA==.',Mi='Mikexfire:BAAALAAECgMIBAAAAA==.Misonte:BAAALAAECgIIAgAAAA==.',Mo='Monreeyy:BAAALAADCgcIBQAAAA==.Moochella:BAAALAAECgIIBAAAAA==.Moonq:BAAALAAECgMIAwAAAA==.Moorti:BAAALAAECgQIBgAAAA==.Moosaurus:BAAALAAECgYIDQAAAA==.Mosrael:BAAALAAECgMIAwAAAA==.Moxflip:BAAALAAECgEIAQAAAA==.Moñitos:BAAALAADCgMIBgAAAA==.',Mu='Muffy:BAAALAAECgQICQAAAA==.Mugin:BAAALAADCgYIBgAAAA==.',My='Myangel:BAAALAADCgUIBQAAAA==.Mythnarra:BAAALAAECgcIDwAAAA==.',['Mí']='Mísanthrope:BAAALAADCgcIBQABLAADCgcIBwABAAAAAA==.',['Mø']='Mønstèr:BAAALAAECgMIBQAAAA==.',Na='Nanukimon:BAAALAAECgMIAwAAAA==.',Ne='Neckslicer:BAAALAAECgMIAwAAAA==.Nelivath:BAAALAADCgYIBgAAAA==.',Ni='Nihm:BAAALAAECgMIAwAAAA==.Nikwillig:BAAALAADCgYIBgAAAA==.Nilae:BAAALAAECgQIBAAAAA==.',No='Nokorii:BAAALAAECgMIAwAAAA==.Nomadd:BAAALAADCgQIBAAAAA==.Nomecoma:BAAALAAECgcIDwAAAA==.Noodlepants:BAAALAADCgMIAQAAAA==.',['Nè']='Nèlo:BAAALAAECgIIBAAAAA==.',Ob='Obscurial:BAAALAAECgEIAQAAAA==.',Oc='Oceansgrave:BAAALAAECgMIBAAAAA==.',Og='Ogtrnz:BAAALAADCggICAAAAA==.',On='Ondestra:BAAALAADCgQIBAAAAA==.',Or='Orave:BAAALAAECgEIAQAAAA==.Orionah:BAAALAADCggIDQAAAA==.',Os='Ossuly:BAAALAAECgMIBAAAAA==.Osysham:BAAALAAECgEIAQABLAAECggIFQAJAFkiAA==.',Ov='Overture:BAAALAAECgIIBAAAAA==.',Pa='Panacea:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Pandamonious:BAAALAAECgIIAgAAAA==.Pandymandy:BAAALAADCggIDQAAAA==.Papawoof:BAAALAAECgYICAAAAA==.Parkour:BAAALAAECgYIDQAAAA==.Patata:BAAALAADCgIIAgAAAA==.Paullymorph:BAAALAAECgcIDwAAAA==.Payal:BAAALAADCggIDwABLAAECgcIEAABAAAAAA==.',Pe='Perpndicular:BAAALAAECgEIAQABLAAECgYIDgABAAAAAA==.',Pi='Pipeline:BAAALAADCgYIBgAAAA==.Pithers:BAAALAAECgUIBgAAAA==.',Po='Popkorn:BAACLAAFFIEFAAIKAAMIaSK9AQA7AQAKAAMIaSK9AQA7AQAsAAQKgRcAAgoACAj6JbYBAG4DAAoACAj6JbYBAG4DAAAA.Popkornshrmp:BAAALAAECgYIBgABLAAFFAMIBQAKAGkiAA==.Poplocks:BAAALAADCggIDAAAAA==.Porrana:BAAALAAECgIIAgAAAA==.Powaqa:BAAALAAECgEIAQAAAA==.Pozhdnyshev:BAAALAADCggICAAAAA==.',Qu='Quasient:BAAALAAECgYIBgAAAA==.Quickspell:BAAALAAECgUICQAAAA==.',Ra='Radaghast:BAAALAADCgEIAQABLAADCgcIDAABAAAAAA==.Raedstar:BAAALAADCgUIBQAAAA==.Raedyyn:BAAALAADCggIDwAAAA==.Raelynna:BAAALAADCgUIBQAAAA==.Ragarth:BAAALAADCggICAAAAA==.Ragendecay:BAAALAAECgIIBAAAAA==.Ragequits:BAACLAAFFIEGAAIHAAMIRiVFAQBRAQAHAAMIRiVFAQBRAQAsAAQKgRsAAgcACAipJUEBAG0DAAcACAipJUEBAG0DAAAA.Rakshadow:BAAALAAECgIIBAAAAA==.Ratedmxk:BAAALAADCgcIDQAAAA==.Razrscale:BAAALAAECgIIAgAAAA==.',Re='Reignasuwish:BAAALAADCggICAAAAA==.Rekritan:BAAALAADCgYIBgAAAA==.Renn:BAAALAAECgMIBAAAAA==.Reze:BAAALAADCgEIAQAAAA==.',Rh='Rholdentodor:BAAALAADCggICQABLAAECgQIBwABAAAAAA==.',Ro='Rockabye:BAAALAADCgQIBAAAAA==.Roóz:BAAALAAECgYIDwAAAA==.',Ru='Runecast:BAAALAAECgYIBgAAAA==.Rustystorm:BAAALAADCggICAAAAA==.Rustywarlock:BAAALAAECgUIBQAAAA==.',Ry='Rynk:BAAALAAECgcIDwAAAA==.Ryuko:BAAALAADCgYICQAAAA==.',Sa='Sabryelle:BAAALAADCgcICwAAAA==.Sarapheena:BAAALAAECgcIDwAAAA==.Saravian:BAAALAADCgYIBgAAAA==.Saterli:BAAALAAECgcIEAAAAA==.Saucyredwing:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.',Sc='Scalvert:BAAALAAECgQIBwAAAA==.Scalypanda:BAAALAAECgcIDwAAAA==.Scarléth:BAAALAADCgYIBgAAAA==.Sculi:BAAALAAECgQICQAAAA==.',Se='Seiishiro:BAAALAAECgYICQAAAA==.Senyor:BAAALAAECggICwAAAA==.Seokwoo:BAAALAADCggICAAAAA==.Seraphiel:BAAALAADCggIDwABLAADCggIDwABAAAAAA==.Seraphymm:BAAALAADCggICAAAAA==.Servingcvnt:BAAALAADCgcIBwAAAA==.',Sh='Shacklebolt:BAAALAAECgcIEAAAAA==.Shadowshot:BAAALAAECgYICQAAAA==.Shadowtoe:BAAALAADCggICAAAAA==.Shaelistra:BAAALAAECgMIBAAAAA==.Shalai:BAAALAAECgIIAgAAAA==.Shamirah:BAAALAADCgYIBgAAAA==.Shawover:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Sheldondh:BAAALAADCgMIAwAAAA==.',Si='Silshara:BAAALAADCgcIBwAAAA==.Silverjustis:BAAALAAECgMIAwAAAA==.Silvertoad:BAAALAADCggICAAAAA==.Simpo:BAAALAAECgIIAgAAAA==.Siwe:BAAALAAECgYIDgAAAA==.',Sk='Skribblez:BAAALAAECgMIAwAAAA==.',Sl='Sloot:BAAALAAECgYIEAAAAA==.',Sm='Smashems:BAAALAAECgIIBAAAAA==.',Sn='Snerd:BAAALAADCggIDgAAAA==.',So='Sockszz:BAAALAAECgcIDwAAAA==.Sofiia:BAAALAADCgQIBAAAAA==.Sourcorpse:BAAALAAECgQIBwAAAA==.',Sp='Spirillium:BAAALAAECgIIAgAAAA==.Splendorae:BAAALAAECgcIDwAAAA==.Sprints:BAAALAAECgUICQAAAA==.Spritz:BAAALAAECgMIAwAAAA==.Sprucewillis:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Spwany:BAAALAADCgYIBgAAAA==.Spyderelite:BAAALAAECgYICAAAAA==.',Sq='Squirrel:BAAALAAECgcIEgAAAA==.',St='Stankstarstu:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Starspeaker:BAAALAADCggIEAAAAA==.Stumbler:BAAALAADCggIDwAAAA==.Størmbrew:BAAALAAECgcIEAAAAA==.',Sw='Sweetnilita:BAAALAADCgMIBgAAAA==.',Sy='Syliva:BAAALAADCgcIBwAAAA==.Sylvarian:BAAALAAECgIIAwAAAA==.Syrodeus:BAAALAADCggICwAAAA==.',Ta='Tabarnack:BAAALAADCgcIDgAAAA==.Tachaka:BAAALAADCgcIDQAAAA==.Tadeus:BAAALAADCgcICwAAAA==.Talagirin:BAAALAADCgEIAQAAAA==.Taterdotz:BAAALAADCggICAAAAA==.Tatyrra:BAAALAADCggIDAAAAA==.Tayza:BAAALAADCgEIAQAAAA==.',Th='Thatisntmilk:BAAALAAECgcIEAAAAA==.Thaymor:BAAALAADCgIIAQAAAA==.Thelonecone:BAABLAAECoEXAAILAAgI4iJEBAAvAwALAAgI4iJEBAAvAwAAAA==.Theodor:BAAALAAECgEIAgAAAA==.Thomwizard:BAAALAAECgMIBAAAAA==.Thunnha:BAAALAAECggIEQAAAA==.Thuny:BAAALAAECgcIDgAAAA==.',Ti='Tidepods:BAAALAAFFAEIAQAAAA==.',To='Tontusk:BAAALAAECgEIAQAAAA==.Toodamsirius:BAAALAADCggIDwAAAA==.Toofwess:BAAALAAECgQIBQABLAAECgYICAABAAAAAA==.Torok:BAAALAADCgMIAwAAAA==.Toulk:BAAALAADCggICAAAAA==.',Tr='Traael:BAAALAAECgMIAwAAAA==.Traehkrad:BAAALAADCgcIDQAAAA==.Treebranch:BAAALAAECgcIDwAAAA==.Trybal:BAAALAAECgQIBgAAAA==.Træumatize:BAAALAADCgEIAQABLAAECggIFQAJAFkiAA==.',Tu='Tularana:BAABLAAECoEVAAMJAAcIWSLJBACoAgAJAAcIWSLJBACoAgAMAAQIIgraUgDJAAAAAA==.',Tw='Twinkie:BAAALAAECgUICAAAAA==.Twodogz:BAAALAAECgMIBQAAAA==.',Ty='Tyious:BAAALAAECgcIDwAAAA==.Tyndara:BAAALAAECgMIBAAAAA==.',['Tü']='Tüesdaÿ:BAAALAADCgcIDQAAAA==.',Ub='Ubabarrier:BAAALAAECgIIBAAAAA==.',Un='Underaiki:BAAALAADCgcIBwAAAA==.Unhoe:BAAALAADCgIIAgAAAA==.Unholybowner:BAAALAADCggIDwAAAA==.',Ur='Ursane:BAAALAAECgYIDQAAAA==.',Va='Valyrior:BAAALAAECgMIAgAAAA==.Vanish:BAAALAAECgEIAQAAAA==.Vanncint:BAAALAAECgMIBAAAAA==.Vaporeon:BAAALAAECgQIBwAAAA==.',Ve='Velfn:BAAALAAFFAIIBAAAAA==.Vexile:BAAALAADCgcIDQAAAA==.Vexmore:BAAALAADCgEIAQAAAA==.',Vo='Void:BAAALAAECgIIAgAAAA==.Voidrunner:BAAALAAECgMIAgAAAA==.Voidstrider:BAAALAAECgEIAQAAAA==.Vordarian:BAAALAAECgYICwAAAA==.',Wa='Walolas:BAAALAADCggIEwAAAA==.',We='Wednesdays:BAAALAADCgQIBwAAAA==.',Wh='Whaler:BAAALAADCggIEAAAAA==.Whos:BAAALAAECggICwAAAA==.',Wr='Wroon:BAAALAAECgIIAgAAAA==.',Wu='Wugzug:BAAALAADCggIEwAAAA==.',Xa='Xaven:BAAALAAECgMIAwAAAA==.',Xe='Xenyoxas:BAAALAAECgcIEAAAAA==.',Xi='Xideris:BAAALAAECgcIDwAAAA==.',Xy='Xyzcorp:BAAALAAECgEIAQAAAA==.',Ye='Yellenheller:BAAALAAECgMIAwAAAA==.',Yh='Yhoshii:BAAALAAECggIDwAAAA==.',Yo='Yoan:BAAALAAECgYIDgAAAQ==.Yoondo:BAAALAAECgEIAQAAAA==.',Yu='Yuffie:BAAALAADCgUIBQAAAA==.',Za='Zabra:BAAALAADCgUIBQAAAA==.Zahvoker:BAAALAAECgEIAQAAAA==.Zantex:BAAALAADCgcICgAAAA==.Zaylian:BAAALAAECgMIBQAAAA==.',Ze='Zeerkk:BAAALAAECgYIDgAAAA==.Zelanta:BAAALAADCgYICQAAAA==.',Zi='Ziiz:BAAALAADCgcIBwAAAA==.',Zt='Ztaziki:BAAALAADCggIDgAAAA==.',Zu='Zulmex:BAAALAADCggIDgAAAA==.',['Åb']='Åbon:BAAALAADCgcIDQAAAA==.',['Ûn']='Ûnstable:BAAALAADCggIDAAAAA==.',['ßr']='ßrûh:BAAALAAECgIIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end