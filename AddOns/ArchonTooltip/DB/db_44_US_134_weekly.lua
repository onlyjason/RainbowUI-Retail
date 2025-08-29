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
 local lookup = {'Unknown-Unknown','Druid-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Rogue-Assassination',}; local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abartheris:BAAALAAECgEIAQAAAA==.Abraxxas:BAAALAADCgMIAwAAAA==.',Ac='Acanoffood:BAAALAAECgEIAQAAAA==.',Ag='Agriopas:BAAALAAECgEIAQAAAA==.',Al='Alassomorph:BAAALAAECgIIAwAAAA==.Alazaie:BAAALAAECgEIAQAAAA==.Albus:BAAALAAECggIEQAAAA==.Allayna:BAAALAAECgYIBwAAAA==.Alline:BAAALAAECgcICgAAAA==.Alloy:BAAALAADCgUIBgAAAA==.Aloha:BAAALAAECgYICAAAAA==.Alysen:BAAALAADCgYIBgABLAADCggIFwABAAAAAA==.',Am='Amishdruid:BAAALAAECgcIEAAAAA==.Amleth:BAAALAADCggIEgAAAA==.Amory:BAAALAADCgYICAABLAADCggIDwABAAAAAA==.',An='Andja:BAAALAAECgcIBwAAAA==.Andromedae:BAAALAAECgMIBAAAAA==.Andurox:BAAALAADCggIEQAAAA==.Angela:BAAALAADCgQIBwAAAA==.',Ap='Apollinius:BAAALAADCgYIBgAAAA==.',Ar='Arborelai:BAAALAADCggIEAAAAA==.Arthrex:BAAALAAECgEIAgAAAA==.',As='Asmobob:BAAALAADCgMIAwAAAA==.',Au='Autumm:BAAALAADCgcIFQAAAA==.',Ax='Axecop:BAAALAADCgcIDAABLAAECgYICQABAAAAAA==.',Ba='Babycoffee:BAAALAAECgIIAwAAAA==.Bahwee:BAAALAADCgMIAwAAAA==.Bandito:BAAALAADCgcICQAAAA==.Bastor:BAAALAADCggIEAAAAA==.',Be='Bearnekkid:BAAALAADCgcICgABLAADCggIFQABAAAAAA==.Bearsgomoo:BAAALAAECgYIDAAAAA==.Bellatrix:BAAALAADCgcIDgAAAA==.Benebeorn:BAAALAAFFAEIAQAAAA==.Bernon:BAAALAADCgYIBwAAAA==.',Bi='Bigal:BAAALAADCgYIDAAAAA==.Bignose:BAAALAAECgIIAgAAAA==.Bike:BAAALAAECgUIBgAAAA==.Bittronoxus:BAAALAAECgIIBAAAAA==.Biörn:BAAALAAECgMIBAAAAA==.',Bl='Blindleg:BAAALAAECgUIBwAAAA==.',Bo='Bobbysmerica:BAAALAADCggIFgAAAA==.Boboarcane:BAAALAAECgIIBAAAAA==.Bodikhan:BAAALAADCggIDwAAAA==.Bojak:BAAALAADCgcIEAAAAA==.Bolfor:BAAALAADCggIBQABLAAECgYICQABAAAAAA==.Boopersnoot:BAAALAADCggIDwAAAA==.Boorock:BAAALAADCggICAAAAA==.Bop:BAAALAAECgQIBgAAAA==.',Br='Brahurah:BAAALAADCggIDgAAAA==.Brainslug:BAAALAADCggIDwAAAA==.Braxte:BAAALAAECgcICgAAAA==.Britziola:BAAALAADCgMIAwABLAADCggIDwABAAAAAA==.',Bu='Buggies:BAAALAAFFAEIAQAAAA==.Buggs:BAAALAADCgUIBQABLAAFFAEIAQABAAAAAA==.Buldozz:BAAALAAECgQIBwAAAA==.Bundlez:BAAALAADCgUIBQAAAA==.Burnination:BAAALAADCggIDwAAAA==.Butterfayce:BAAALAADCgQIBAAAAA==.',By='Byce:BAAALAADCgYIBgAAAA==.',Ca='Cadastrasz:BAAALAAECgYIDAAAAA==.Cateurize:BAAALAAECgYIBwAAAA==.Cazadorr:BAAALAADCgcICwAAAA==.',Ce='Ceenit:BAAALAAECgYICwAAAA==.Celawyn:BAAALAADCggIDAAAAA==.Celebro:BAAALAADCgcIDwAAAA==.',Ch='Chainedfire:BAAALAADCgcICAAAAA==.Chaøtical:BAAALAADCggIDwAAAA==.Chilehunter:BAAALAADCgMIAwAAAA==.Chillaf:BAAALAADCgcIDgABLAAECgEIAQABAAAAAA==.Chillfist:BAAALAADCgUIBgAAAA==.',Ci='Cine:BAAALAADCggIDwABLAAECgYIBwABAAAAAA==.',Cl='Clamer:BAAALAADCgcICgAAAA==.Cleansinq:BAAALAAECgMIBAAAAA==.Cleave:BAAALAAECgIIAgABLAAECgQIBgABAAAAAQ==.Clerico:BAAALAADCggICwAAAA==.Cloudsmoker:BAAALAAECgQIBAAAAA==.',Co='Corien:BAAALAADCggIDwAAAA==.',Cr='Crimsonmoon:BAAALAAECgYIBwAAAA==.Cruella:BAAALAAECgIIAgAAAA==.Cryomara:BAAALAADCgcIBwAAAA==.',Cy='Cyanotik:BAAALAADCgMIAwAAAA==.Cynia:BAAALAADCggIFwAAAA==.',Da='Daizy:BAAALAADCgQIBAAAAA==.Danklins:BAAALAAECgcICgAAAA==.Darkndemonic:BAAALAADCgYIBgAAAA==.Darthvada:BAAALAAECgIIAwAAAA==.Darthys:BAAALAADCgYIBwAAAA==.Davue:BAAALAADCggICwAAAA==.',De='Deadpoint:BAAALAADCggIFwAAAA==.Deathlords:BAAALAADCggICAAAAA==.Deathzgrace:BAAALAAECgcIDwAAAA==.Delia:BAAALAADCgUIBQAAAA==.Demonaria:BAAALAAECgYICQAAAA==.Derpnface:BAAALAADCggIEgAAAA==.Desecration:BAAALAAECgMIAwAAAA==.Devilhandler:BAAALAAECgEIAQAAAA==.',Dh='Dhoro:BAAALAAECgYIDAAAAA==.',Di='Dirgir:BAAALAAECgMIBAAAAA==.Disa:BAAALAADCgYICgAAAA==.Disk:BAAALAAFFAEIAQAAAA==.',Do='Doc:BAAALAAECgIIAgAAAA==.Doriya:BAAALAADCgYIBgAAAA==.',Dr='Dracheo:BAAALAAFFAEIAQAAAA==.Dragonbrr:BAAALAADCgcICgAAAA==.Dralize:BAAALAADCgQIBAAAAA==.Dranix:BAAALAAECgIIAwAAAA==.Droiden:BAAALAAECgIIAgAAAA==.Droopy:BAAALAADCgYIBgABLAADCgYIDAABAAAAAA==.Drotar:BAAALAAECgEIAQAAAA==.',Du='Dumbdog:BAABLAAECoEXAAICAAgIqR9zAgD0AgACAAgIqR9zAgD0AgAAAA==.Dumichauch:BAAALAAFFAEIAQAAAA==.Duskseeker:BAAALAAECgcIDwAAAA==.',Ee='Eedrah:BAAALAADCggIEQAAAA==.',Ek='Ekhor:BAAALAADCgcICgAAAA==.',El='Ellyon:BAAALAADCgcICgAAAA==.Elorie:BAAALAADCgUIBQABLAAFFAEIAQABAAAAAA==.',Em='Emberleaf:BAAALAADCggIEAAAAA==.',En='Enoch:BAAALAADCgQIBQAAAA==.',Ep='Epicstalker:BAAALAADCgcICQAAAA==.',Ev='Evinith:BAAALAAECgYICQAAAA==.',Ew='Ewik:BAAALAAECgUIBQAAAA==.',Fa='Faent:BAAALAADCggIDQAAAA==.Falinora:BAAALAAFFAEIAQAAAA==.Fantasticfox:BAAALAAECgIIAwAAAA==.',Fe='Felbyte:BAAALAADCggICAAAAA==.Feloron:BAAALAADCgMIAwAAAA==.Felsocks:BAAALAADCgMIAwAAAA==.Feodin:BAAALAADCggIFAABLAAECgcIEAABAAAAAA==.',Fi='Fion:BAAALAAECgYIBwAAAA==.Fitzchivalry:BAAALAADCgQIBwAAAA==.',Fl='Flee:BAAALAAECgIIAwAAAA==.',Fo='Forcewild:BAAALAADCgcIBwAAAA==.Foxdragon:BAAALAAECgYICQAAAA==.',Fr='Friz:BAAALAADCgUIBQAAAA==.Frostitut:BAAALAAECgYIBwAAAA==.',Fu='Fuddrucker:BAAALAAECgIIAwAAAA==.Fuegita:BAAALAADCgUIBQAAAA==.Furaffinity:BAAALAADCggIDwAAAA==.Furgam:BAAALAADCggIFwAAAA==.Fuzzychunks:BAAALAADCggIEgAAAA==.',Ga='Garmagar:BAAALAADCgYIBwAAAA==.Garruto:BAAALAAECgcICgAAAA==.Gazdk:BAAALAAECgcIDAAAAA==.',Ge='Gellus:BAAALAADCggIEgAAAA==.Getsomechico:BAAALAADCgMIBQAAAA==.',Gh='Ghostdrake:BAAALAADCgQIBwAAAA==.',Go='Goonthar:BAAALAAFFAEIAQAAAA==.Gottafly:BAAALAAECgUIBwAAAA==.Goze:BAAALAADCggICAAAAA==.',Gr='Granoch:BAAALAAECgIIAgAAAA==.Greatballs:BAAALAAECgEIAQAAAA==.Greatthanos:BAAALAADCggICAAAAA==.Grindknight:BAAALAAECgYIBgAAAA==.Grokmar:BAAALAADCgYIBgAAAA==.Gromps:BAAALAADCgQIBAABLAAFFAEIAQABAAAAAA==.Grompy:BAAALAAFFAEIAQAAAA==.Grunlok:BAAALAADCgcIBwAAAA==.',Gu='Guccicarryon:BAAALAADCggIDwAAAA==.Guff:BAAALAADCgMIAwAAAA==.Gugudou:BAAALAAECgIIBAAAAA==.',Gw='Gwegg:BAAALAADCgUIBQAAAA==.',Gy='Gyxx:BAAALAAECgEIAQAAAA==.',Ha='Haddice:BAAALAAECgIIAgAAAA==.Hafarti:BAAALAAECggIBQAAAA==.Hammermommy:BAAALAADCggIFwAAAA==.Havárti:BAAALAADCgYIBgAAAA==.Hawthorn:BAAALAADCgcIBwAAAA==.',He='Heebiejeebie:BAAALAAECgYIDAAAAA==.Hellaeus:BAAALAADCggICAAAAA==.Hemaroids:BAAALAADCgYIBwAAAA==.',Hi='Hisokä:BAAALAAECgUIBQAAAA==.',Ho='Hollabakacha:BAAALAAECggIEQAAAA==.Holycreambar:BAAALAAECgYIDAAAAA==.Hoofsbane:BAAALAADCggICAAAAA==.Hotdoge:BAAALAAECgUIBgAAAA==.',Hu='Huntingale:BAAALAADCgYIBwAAAA==.Hunttheloro:BAAALAADCgQIBAAAAA==.',Hy='Hygelak:BAAALAADCggIFwAAAA==.',Il='Illuminance:BAAALAAECgEIAQAAAA==.',Im='Imbarryobama:BAAALAAECgYIBwAAAA==.',In='Infidius:BAAALAADCggIEQAAAA==.Infligo:BAAALAAECgYIBwAAAA==.Invocation:BAAALAADCggICwAAAA==.',Ir='Ironstag:BAAALAADCggIDwAAAA==.',Is='Isitcuffs:BAAALAADCgcIBAAAAA==.',Ja='Jaboody:BAAALAADCgcIBwAAAA==.Jard:BAAALAADCggIDwAAAA==.',Je='Jehtadin:BAAALAAECgYIBwAAAA==.Jehtlock:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.',Ji='Jimvisible:BAAALAADCggIDgAAAA==.',Jo='Johadro:BAAALAADCgEIAQAAAA==.',Ju='Judgejobrown:BAAALAADCgMIBAAAAA==.Judgenawt:BAAALAAECgUICAAAAA==.',Ka='Kaiá:BAAALAADCgcICwAAAA==.Kalkunlai:BAAALAADCggIFwAAAA==.Karambit:BAAALAADCggICAAAAA==.Karn:BAAALAAECgYIBwAAAA==.Karti:BAAALAADCgYIBwAAAA==.Karzdormi:BAEALAAECgcIDwABLAADCgYIBgABAAAAAA==.Karzen:BAEALAADCgYIBgAAAA==.Kassicker:BAAALAADCgUIBQAAAA==.Kathell:BAAALAADCgYIBgABLAAECgcIEAABAAAAAA==.',Ke='Kennaea:BAAALAADCgUIBQABLAAFFAEIAQABAAAAAA==.',Kh='Kharizma:BAAALAADCgYIBgAAAA==.',Ki='Killigula:BAAALAAECgcIDwAAAA==.Kinks:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Kinuye:BAAALAADCgYIBwAAAA==.',Ko='Kondolo:BAAALAADCggICAAAAA==.Korash:BAAALAAECgEIAQAAAA==.Korpce:BAAALAADCggIDwAAAA==.Korza:BAAALAADCggICAAAAA==.',Kr='Krenolarian:BAAALAADCgEIAQAAAA==.',Kw='Kwonderwoman:BAAALAADCggIDwAAAA==.',La='Lamora:BAAALAADCgUIBQAAAA==.Larissah:BAEALAAECgMIBAAAAA==.Latinhunter:BAAALAAECgEIAQAAAA==.Latinmonkt:BAAALAADCgYIBgAAAA==.Latinshamy:BAAALAAECgIIAgAAAA==.Lavande:BAAALAAECgYICwAAAA==.',Le='Legendàiry:BAAALAAECgcIEAAAAA==.Legomyagro:BAAALAAECgcICgAAAA==.Leonaá:BAAALAAECgcICgAAAA==.',Li='Lilbessy:BAAALAAECgIIAwAAAA==.Lishaliel:BAAALAADCgUIBQABLAAECgcIEAABAAAAAA==.Lizzia:BAAALAAECgQIBAAAAA==.',Lo='Lootah:BAAALAADCggIDgAAAA==.',Lu='Lunabellz:BAAALAAECgIIAwAAAA==.Lunavia:BAAALAADCggIDwAAAA==.',Ma='Macleish:BAAALAADCgcIDQAAAA==.Mad:BAAALAADCgQIBwAAAA==.Maeby:BAAALAADCggIDQABLAADCggIFwABAAAAAA==.Maery:BAAALAADCgQIBwAAAA==.Maizy:BAAALAADCggIFwAAAA==.Margad:BAAALAADCgcIBwAAAA==.Matchamist:BAAALAADCgUIBQAAAA==.Mayyhem:BAAALAAECgcIDAABLAAECggIFwACAKkfAA==.',Mc='Mcallister:BAAALAADCgcIBwABLAADCggIDwABAAAAAA==.Mcjudgin:BAAALAAECgcICgAAAA==.Mcsquid:BAAALAADCgYIBgAAAA==.',Me='Meatbubble:BAAALAADCgQIBAAAAA==.Mechee:BAAALAADCggIDwAAAA==.',Mi='Mimiker:BAAALAAFFAEIAQAAAA==.Mimilock:BAAALAADCggIDAABLAAFFAEIAQABAAAAAA==.Minime:BAAALAAECgMIAwABLAAECggIGAADAOYkAA==.Mirabella:BAAALAADCggIEAAAAA==.Mizahella:BAAALAADCgQIBwAAAA==.',Mo='Mobo:BAAALAADCggIDwAAAA==.Mokei:BAAALAADCggICAAAAA==.Mokipnos:BAAALAADCgUICgAAAA==.Moonsilver:BAAALAADCggIBwAAAA==.Moriko:BAAALAAECgYICAAAAA==.Mourn:BAAALAAFFAEIAQAAAA==.',Ms='Msmayhem:BAAALAADCggIDwAAAA==.',Mu='Muertomarrow:BAAALAADCggIFwAAAA==.Musasa:BAAALAAECgYIBwAAAA==.Mustardseed:BAAALAADCggICAAAAA==.',Na='Nasrith:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.Nastro:BAAALAADCgQIBwAAAA==.Naughtica:BAAALAAECgMIBgAAAA==.Navellint:BAAALAAECgMIAwAAAA==.Nawtishot:BAAALAAECgUIBwAAAA==.',Ne='Nefra:BAAALAADCggIEAAAAA==.Nekk:BAAALAAECgEIAQAAAA==.Nevanthi:BAAALAAECgEIAQAAAA==.',Ni='Nicejacket:BAAALAADCgUIBQAAAA==.Niqhtsong:BAAALAAECgEIAQAAAA==.Nitebrite:BAAALAADCggIDwAAAA==.',No='Noimia:BAAALAAECgYICwAAAA==.Noraina:BAAALAADCgMIAgAAAA==.Normanosborn:BAAALAADCggICwAAAA==.',Oc='Oceanspray:BAAALAADCgMIBQAAAA==.',Od='Oden:BAAALAAECgcIDQAAAA==.',Og='Oggy:BAAALAAFFAEIAQAAAA==.',Ok='Oksanabaiul:BAAALAAFFAEIAQAAAA==.',On='Onlydelves:BAAALAADCgcIBwAAAA==.',Pa='Pacoes:BAAALAADCgcIFQAAAA==.Pacoesette:BAAALAADCgcIBwAAAA==.Padray:BAAALAAECgcIEAAAAA==.Panda:BAAALAAECgMIBQAAAA==.',Pe='Peaseblossom:BAAALAADCggICAAAAA==.Pecoes:BAAALAADCgUIBQAAAA==.Pelasius:BAAALAADCgQIBwAAAA==.Pen:BAAALAAECgQICQAAAA==.Pepperbottom:BAAALAAECgYICQAAAA==.Perseuss:BAAALAADCgUICQAAAA==.',Pf='Pfft:BAAALAADCggIFQAAAA==.',Ph='Phaedril:BAAALAADCgUIBQAAAA==.',Pi='Pineapples:BAAALAAECgYICQAAAA==.',Po='Poppi:BAAALAADCggIDwAAAA==.Poyoh:BAAALAAECgYIBwAAAA==.',Pr='Pravoce:BAAALAADCgQIBAAAAA==.',Pu='Puddintaters:BAAALAADCgIIAgAAAA==.',Ra='Radjason:BAAALAADCggIHgAAAA==.Raeagald:BAAALAADCggIEAABLAAFFAEIAQABAAAAAA==.Raelyni:BAAALAAECgYIBwAAAA==.Ragingjohnny:BAAALAADCggICAAAAA==.Rainfuego:BAAALAAECgMIAwAAAA==.Rakup:BAAALAADCggICAAAAA==.Ranann:BAAALAADCgcICwAAAA==.Random:BAAALAADCgcICgAAAA==.Rantan:BAAALAAECgEIAQAAAA==.Rapha:BAAALAADCgQIBQAAAA==.Raveniss:BAAALAADCggICAAAAA==.Rawrie:BAAALAAECgEIAQAAAA==.Raygun:BAAALAAECgEIAQABLAADCggIDwABAAAAAA==.Razkal:BAAALAADCgIIAQAAAA==.',Re='Rederick:BAAALAADCgcICgAAAA==.Redhilda:BAAALAADCggIFgAAAA==.',Rh='Rhymulus:BAAALAADCgQIBwAAAA==.',Ri='Rillao:BAAALAAECgMIBAAAAA==.Rissaria:BAAALAAFFAEIAQAAAA==.',Ro='Rocknëss:BAAALAADCgIIAgAAAA==.Rotblade:BAAALAAECgEIAQAAAA==.',Ru='Rudewenn:BAAALAADCggIEAAAAA==.',Ry='Ryline:BAAALAAECgMIBAAAAA==.',['Rø']='Røøtsftw:BAAALAADCggICAAAAA==.',Sa='Safary:BAAALAAECgEIAQAAAA==.Sarrmage:BAAALAAECgUIBQAAAA==.Sarrwarr:BAAALAAECgMIBAAAAA==.Sassa:BAAALAADCggIDwAAAA==.Sassymoo:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.Sañtoro:BAAALAADCggIDgAAAA==.',Sc='Scarletdaisy:BAAALAADCggIDAAAAA==.Scy:BAAALAAECgIIAwAAAA==.',Se='Seipora:BAAALAADCgcICgAAAA==.',Sh='Shambali:BAAALAAECgUICQAAAA==.Shamidozz:BAAALAADCgcIBwAAAA==.Shandro:BAAALAAECgYIBwAAAA==.Shaniallon:BAAALAAECgcICgAAAA==.Shanulu:BAAALAADCgQIBAAAAA==.Sharana:BAAALAADCggICAAAAA==.Shockirah:BAAALAADCggICQAAAA==.Shot:BAAALAAECgMIBQABLAAECgQIBgABAAAAAQ==.Shouzen:BAAALAADCggICAAAAA==.',Si='Silentaska:BAAALAADCgUIBQAAAA==.Silentbruce:BAAALAAECggIEgAAAA==.Silentchill:BAAALAAECgYIDAAAAA==.Siqness:BAAALAADCgQIBwAAAA==.',Sn='Snowcake:BAAALAADCgcIBwAAAA==.',So='Sofiavers:BAAALAAECgEIAQAAAA==.Soilwork:BAAALAADCggIDQAAAA==.Sornafayne:BAAALAADCgQIBAAAAA==.Souy:BAAALAADCggICAAAAA==.',Sp='Spaceaìds:BAAALAADCggIAQAAAA==.Spacerae:BAAALAADCggIDAAAAA==.Spareme:BAAALAADCgMIAwABLAADCgYIDAABAAAAAA==.Spy:BAAALAAECgMIBgAAAA==.',St='Starrie:BAAALAAECgEIAQAAAA==.Steelhoof:BAAALAAECgYICQAAAA==.Steil:BAAALAADCgcICgAAAA==.Stonesoul:BAAALAADCggICAAAAA==.Stories:BAAALAADCggIDwAAAA==.Struckerdots:BAAALAADCggIDwABLAAECgYIBwABAAAAAA==.Struckrucker:BAAALAAECgYIBwAAAA==.Stygian:BAAALAAFFAEIAQAAAA==.',Su='Sudimmoc:BAAALAAFFAEIAQAAAA==.Suffocator:BAAALAADCgEIAQAAAA==.Sushie:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',Sw='Swingingpeen:BAAALAAECgEIAQAAAA==.',Ta='Tabby:BAAALAADCgQIBwAAAA==.Taconight:BAAALAADCggIFwAAAA==.Tagilro:BAAALAADCgcIBwAAAA==.Taintblaster:BAAALAADCgIIAgAAAA==.Tarlgreyhair:BAAALAADCgcICgAAAA==.Tarîs:BAAALAAECgYICAAAAA==.Tawneestone:BAAALAAECgcICgAAAA==.Tazeneth:BAAALAADCggIEgAAAA==.',Te='Technics:BAAALAAECgIIAgABLAADCggIDwABAAAAAA==.Teg:BAAALAADCgYIBgAAAA==.Tethercat:BAAALAADCgcICgAAAA==.',Th='Theldara:BAAALAAECgcIEAAAAA==.Themock:BAAALAADCggIEgAAAA==.Theshift:BAAALAAECgEIAQAAAA==.Thisisjustin:BAAALAAECgMIBAAAAA==.Thoreen:BAAALAADCgQIBwAAAA==.Thrish:BAAALAAFFAEIAQAAAA==.Thundarfury:BAAALAADCgQIBwAAAA==.Thunderfist:BAAALAAECgcIEAAAAA==.',Ti='Timothy:BAAALAAECgMIAwAAAA==.Tizzlefizzle:BAAALAADCgYICgAAAA==.Tizzlesizzle:BAAALAADCgIIAQAAAA==.',To='Toothy:BAAALAADCgQIBAAAAA==.',Tr='Tranarious:BAAALAADCgYIBgAAAA==.Trandor:BAAALAADCgIIAgAAAA==.Truni:BAAALAADCggIDgABLAADCggIFwABAAAAAA==.',Tw='Twixaldo:BAAALAADCggIDwAAAA==.',Ty='Tylus:BAAALAADCgcIBwAAAA==.Tyriais:BAAALAADCgcIBwAAAA==.',Ub='Ubpriest:BAAALAADCgYIBwAAAA==.',Ug='Uglybarnacle:BAAALAAECgQIBgAAAA==.',Up='Upinya:BAAALAAECgYIBwAAAA==.',Uz='Uzumaki:BAAALAADCgIIAgAAAA==.',Va='Vallasha:BAAALAAECgEIAQAAAA==.Valyssaa:BAAALAADCggIDwABLAAECgYIBwABAAAAAA==.Vayne:BAAALAAFFAEIAQAAAA==.',Ve='Veratyr:BAAALAADCggIDwAAAA==.Verita:BAAALAADCgMIAwAAAA==.',Vi='Vinge:BAEALAADCggIDgAAAA==.Violetrain:BAAALAADCgcIBwAAAA==.',Vo='Voodoomagic:BAAALAADCgYIBgAAAA==.',Vy='Vyrista:BAAALAAECgEIAgAAAA==.Vyzualize:BAAALAAECggIEgAAAA==.',Wa='Warotoka:BAAALAADCgQIBAAAAA==.Wauwen:BAAALAADCggIDwAAAA==.',We='Wednesdáy:BAAALAAECgcIDwAAAA==.Weeps:BAAALAAFFAEIAQAAAA==.Weetbix:BAAALAAECgEIAQAAAA==.Wept:BAAALAADCgcIDAAAAA==.',Wh='Wheresjohnny:BAAALAAECgYIBwAAAA==.',Wi='Wiccked:BAAALAAECgQIBAAAAA==.Wigglecakes:BAAALAADCgQIBAAAAA==.Winterice:BAAALAADCgMIAwAAAA==.',Wo='Woodscale:BAAALAADCgQIBwAAAA==.',Wr='Wrexham:BAAALAADCgEIAQAAAA==.',Xy='Xyloth:BAAALAAECgEIAQABLAAECgEIAQABAAAAAA==.',Ye='Yeast:BAAALAAECgUIBgAAAA==.Yergat:BAABLAAECoEYAAMDAAgI5iQzBwCzAgADAAcI4CQzBwCzAgAEAAEIESXUYgBsAAAAAA==.',Yo='Yongu:BAAALAAECgEIAQAAAA==.',Ys='Ysabela:BAAALAADCgcIDQABLAADCggIFwABAAAAAA==.',Yu='Yuliane:BAAALAADCgUIBQABLAADCggIFwABAAAAAA==.Yupa:BAAALAAECgIIAwABLAAECgYICAABAAAAAA==.',Za='Zafira:BAAALAAECgQIBwAAAA==.Zakluliz:BAAALAADCgcICgAAAA==.Zarena:BAAALAADCgYICQAAAA==.',Ze='Zelrex:BAABLAAECoEYAAIFAAgIDxmdCQCOAgAFAAgIDxmdCQCOAgAAAA==.Zerazer:BAAALAAECgcIDwAAAA==.',Zh='Zhuntyr:BAAALAADCggIFwAAAA==.',Zi='Zierro:BAAALAADCggIEwAAAA==.',Zo='Zoomies:BAAALAADCggICAAAAA==.',['Ár']='Áres:BAAALAAECgMIAwAAAA==.',['Ìz']='Ìzz:BAAALAADCggIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end