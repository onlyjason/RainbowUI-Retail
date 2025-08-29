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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','Druid-Restoration','Monk-Mistweaver','Rogue-Outlaw','Monk-Brewmaster','Druid-Balance','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Paladin-Protection',}; local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Absalon:BAAALAADCgcICQAAAA==.',Ac='Aceldamor:BAAALAADCgEIAQAAAA==.Acense:BAAALAAECgMIAwAAAA==.Aciddk:BAAALAADCgMIAwAAAA==.Acidlock:BAAALAAECgMIBAAAAA==.Acidpriest:BAAALAADCgMIAwAAAA==.',Ad='Adacey:BAAALAADCggICAAAAA==.Adragon:BAAALAAECgMIBAAAAA==.Adrillion:BAAALAADCgcIBwAAAA==.',Ae='Aein:BAAALAAECgQIBAABLAAECgYICQABAAAAAA==.',Ai='Aisen:BAAALAADCgQIBAAAAA==.',Ak='Aktras:BAAALAAECgIIAgAAAA==.',Al='Alaunu:BAAALAAECgIIAwAAAA==.Alauyia:BAAALAADCgcIBwAAAA==.Alear:BAAALAADCgcIDQAAAA==.Alkhan:BAAALAAECgIIAwAAAA==.Alndvia:BAAALAADCgQIBAAAAA==.Alnonie:BAAALAAECgYIDQAAAA==.Altarmommy:BAAALAAECgUICAAAAA==.',Am='Amethyn:BAAALAADCgcIDgAAAA==.',An='Anorak:BAAALAADCggIDQAAAA==.',Ap='Aprilys:BAAALAADCggICAAAAA==.',Ar='Arazar:BAAALAADCgEIAQAAAA==.Archdemon:BAAALAAECgMIBQAAAA==.Arkhanx:BAAALAAECgMIAwAAAA==.Artemisia:BAAALAADCgcIBwAAAA==.Arthurio:BAAALAAECgQIBwAAAA==.',As='Asevenx:BAAALAADCgMIAwAAAA==.Asterra:BAAALAAECgEIAQAAAA==.',At='Athyr:BAAALAAECgMIBQAAAA==.',Au='Auani:BAAALAAECgYIDQAAAA==.Aurani:BAAALAAECgEIAQAAAA==.',Az='Azarix:BAAALAAECgMIAwAAAA==.',Ba='Babyrinsjr:BAAALAAECgIIAgAAAA==.Baile:BAAALAADCgIIAgAAAA==.Baird:BAABLAAECoEXAAICAAgIXB19CACaAgACAAgIXB19CACaAgAAAA==.Barrada:BAAALAAECgMIAwAAAA==.Bathöry:BAAALAADCggIDgAAAA==.',Be='Bearcane:BAAALAAECgcIDAABLAADCggICAABAAAAAA==.Beefkeg:BAAALAADCgcIBwAAAA==.Beefsupreme:BAAALAADCgYIBgAAAA==.Bellanisa:BAAALAAECgMIBAAAAA==.Berincil:BAAALAAECgMIBwAAAA==.Berzardûnost:BAAALAAECgMIAwAAAA==.',Bl='Bloaf:BAAALAADCgIIAgABLAADCgcIDQABAAAAAA==.',Bo='Bo:BAAALAAECgYIDQAAAA==.Bobsledbob:BAAALAADCggIDwAAAA==.Borahae:BAAALAADCgcIBwAAAA==.',Br='Brewshido:BAAALAADCgcIBwAAAA==.Brigadeer:BAAALAADCgYIBwAAAA==.Brünhilde:BAAALAAECgMIBQAAAA==.',Bs='Bstbll:BAABLAAECoEXAAIDAAgI1BvgCwA8AgADAAgI1BvgCwA8AgAAAA==.',Bu='Bubbleheals:BAAALAADCgUIBQABLAAECgYIDAABAAAAAA==.Buella:BAAALAAECgYICgAAAA==.Bunzi:BAAALAADCggIFAAAAA==.Buttsnacks:BAAALAAECgMIBQAAAA==.',Ca='Callistrah:BAAALAAECgEIAQAAAA==.Caltaa:BAAALAAECgYIDQAAAA==.Camael:BAAALAAECgIIBAAAAA==.Cambrie:BAAALAADCggICwAAAA==.Canverian:BAAALAAECgIIAgAAAA==.Carber:BAAALAADCgcIBwAAAA==.Carmedic:BAAALAADCggICgAAAA==.Catharsis:BAAALAADCgYICwAAAA==.Caticus:BAAALAAECgMIAwAAAA==.',Ce='Cereys:BAAALAAECgEIAQAAAA==.',Ch='Chat:BAAALAAECgYICQAAAA==.Chickenwing:BAAALAAECgMIBQAAAA==.Chilin:BAAALAADCggICAAAAA==.Christano:BAAALAAECgMIBgAAAA==.Christhecold:BAAALAAECgYICgAAAA==.Chèveyo:BAAALAADCgQIBAAAAA==.',Ci='Cindesh:BAAALAAECggICgABLAAFFAEIAQABAAAAAA==.',Cl='Clarke:BAAALAADCgMIAwAAAA==.Closets:BAAALAADCgcIBwAAAA==.',Co='Cocotaso:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Codemon:BAAALAAECgMIAwAAAA==.Conqueeftada:BAAALAAECgMIBQAAAA==.',Cp='Cptcharis:BAAALAADCgcIBgAAAA==.',Cr='Criminal:BAAALAAECgYIEgAAAA==.',Cy='Cylvara:BAAALAADCggIEAAAAA==.Cyntrill:BAAALAAECgEIAQAAAA==.',Da='Dalacia:BAAALAAECgMIAwAAAA==.Dalliah:BAAALAADCggIBwAAAA==.Darealis:BAAALAAECgEIAQAAAA==.Darkevo:BAAALAAECgYIDQAAAA==.Darkfire:BAAALAAECgEIAQAAAA==.Darknature:BAAALAAECgYICQAAAA==.Darkodin:BAAALAAECgMIAwAAAA==.Datnagadrake:BAAALAAFFAIIAgAAAA==.Dawinchy:BAAALAAECggIEwAAAA==.',Dc='Dchalla:BAAALAADCgYIBgAAAA==.',De='Deadlylocks:BAAALAAECgMIAwAAAA==.Deadlypsycho:BAAALAADCgIIAgAAAA==.Deasth:BAAALAADCggIEAABLAADCggIDwABAAAAAA==.Deathcatt:BAAALAADCgcIBwAAAA==.Deathchanges:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.Deathlyill:BAAALAAECgMIAwAAAA==.Deathness:BAAALAADCgEIAQAAAA==.Deekk:BAAALAADCggICAAAAA==.Dekutree:BAAALAAECgIIBAAAAA==.Dellistia:BAAALAADCgcICQAAAA==.Demmi:BAAALAADCgYICAAAAA==.Desdamona:BAAALAAECgEIAQAAAA==.Desdin:BAAALAAECgYICQAAAA==.Devorick:BAAALAAECgYIDQAAAA==.',Di='Diadem:BAAALAAFFAIIAgAAAA==.Diaval:BAAALAADCgcIFQAAAA==.Dinodk:BAAALAADCgIIAgAAAA==.Disciplineme:BAAALAAECgMIAwAAAA==.Discodrake:BAAALAAECgEIAQAAAA==.Divineknight:BAAALAADCgUIBwAAAA==.',Dj='Djingrogu:BAAALAAECgYICAAAAA==.',Do='Doodlebob:BAAALAADCggIDwABLAAECgUIBwABAAAAAA==.Dopatonin:BAAALAADCgUIBQAAAA==.Dotsandrocks:BAAALAADCgMIAwAAAA==.',Dr='Drael:BAAALAADCgcICQAAAA==.Draelyn:BAAALAAECgIIAgAAAA==.Dragbin:BAAALAADCgIIAgAAAA==.Dragonmight:BAAALAAECgMIBQAAAA==.Draickin:BAAALAAECgMIBQAAAA==.Drelian:BAAALAAECgEIAQAAAA==.Drevy:BAAALAADCgMIAwAAAA==.Drumira:BAAALAAECgMIBgAAAA==.Drummer:BAAALAADCggICAAAAA==.Drumroleplz:BAAALAADCgYIBgABLAAECgMIBgABAAAAAA==.',Ds='Dsanatrestk:BAAALAAECgYICgAAAA==.',Du='Duud:BAAALAADCggIDQAAAA==.',Dw='Dwigtsnoot:BAAALAADCgcICwAAAA==.',Dy='Dysmas:BAAALAADCggICAAAAA==.',['Dà']='Dàddybear:BAAALAADCgcICQAAAA==.',El='Eldrinne:BAAALAAECgMIAwAAAA==.',Em='Emariel:BAAALAADCgUIBQAAAA==.',En='Enchäntress:BAAALAADCgYIDAAAAA==.Endolar:BAAALAAECgIIAwAAAA==.Energizer:BAAALAAECgUIBwAAAA==.Enfer:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Enhanced:BAAALAADCgUIBQAAAA==.Enterprise:BAAALAADCgMIAwAAAA==.',Er='Erianthe:BAAALAAECgYIDQAAAA==.Erosonie:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.Erovos:BAAALAAECgIIAgAAAA==.Errina:BAAALAADCgIIAgABLAAECgIIAwABAAAAAA==.',Es='Escarnium:BAAALAADCgIIAgAAAA==.Eshera:BAAALAADCgMIAwAAAA==.',Fa='Fables:BAAALAADCgYIBgAAAA==.Faroda:BAAALAAECgMIAwAAAA==.Fatties:BAAALAADCgcIDQAAAA==.',Fe='Fearios:BAAALAAECgIIAwAAAA==.Felbound:BAAALAADCgQIBAAAAA==.',Fi='Finatic:BAABLAAECoEXAAIEAAgIdR3hBQBxAgAEAAgIdR3hBQBxAgAAAA==.',Fo='Foxylockxoxo:BAAALAAECgMIBAAAAA==.',Fr='Frostysnake:BAAALAADCgYIBgAAAA==.',Fu='Fulldraw:BAAALAAECgEIAgAAAA==.',Ga='Gangster:BAAALAADCgUIBQAAAA==.',Ge='Gein:BAAALAADCgYIBgAAAA==.',Gh='Ghosimoon:BAAALAAECgIIAgAAAA==.',Gi='Gil:BAAALAAECgYIDQAAAA==.',Gl='Glizzygobler:BAAALAAECgcIDwAAAA==.Glocket:BAAALAADCgYICAAAAA==.',Go='Gotdro:BAAALAAECgEIAQAAAA==.',Gr='Graciedoof:BAAALAAECgMIBAAAAA==.Granny:BAAALAADCggIDgAAAA==.Greedisgood:BAAALAAECgMIAwAAAA==.',Gu='Gurni:BAAALAADCgUIBQAAAA==.',Gw='Gwendsele:BAAALAADCgcIBwAAAA==.',Ha='Hantonos:BAAALAADCgcICQAAAA==.Happylotss:BAAALAAECgQIBQAAAA==.Hardsus:BAAALAAECgEIAQAAAA==.Havaxia:BAAALAAECgEIAQAAAA==.',He='Hecate:BAAALAAECgEIAQAAAA==.Hekth:BAAALAAECgMIBAAAAA==.',Ho='Hohenheim:BAAALAAECgYICQAAAA==.Holydes:BAAALAADCgcICQABLAAECgEIAQABAAAAAA==.Hordor:BAAALAAECgEIAQAAAA==.Hornyshrimp:BAAALAADCggICAAAAA==.Hotak:BAAALAAECggICAAAAA==.',Hu='Hunger:BAAALAADCgcIBwAAAA==.Hunkahunka:BAAALAAECgEIAQAAAA==.Huunaron:BAAALAAECgIIBAAAAA==.',['Hè']='Hèx:BAABLAAECoEVAAIFAAgI9x8gAQDcAgAFAAgI9x8gAQDcAgAAAA==.',Ia='Ianiel:BAAALAAECgYICgAAAA==.',Id='Idkmyname:BAAALAADCgYIBgAAAA==.',Ik='Ikki:BAAALAAECggIDgAAAA==.',In='Ink:BAAALAADCggIEAAAAA==.Instakill:BAAALAADCgUIBQAAAA==.Insulin:BAAALAADCgIIAgAAAA==.',Ir='Iradori:BAAALAADCggICAAAAA==.',Is='Iskandar:BAAALAADCgIIAgAAAA==.Isparian:BAAALAADCgQIBAAAAA==.',It='Itwaswalters:BAAALAADCgcICQAAAA==.',Ja='Jackalite:BAAALAAECgIIAwAAAA==.Jargan:BAAALAADCgcIBwABLAAECgIIAwABAAAAAA==.',Je='Jess:BAABLAAECoEUAAIDAAgIXCYxAAB6AwADAAgIXCYxAAB6AwAAAA==.',Jk='Jknight:BAAALAAECgEIAgAAAA==.',Ju='Jukenastyrox:BAAALAADCgcICgAAAA==.',Ka='Kaelpae:BAAALAAECgMIBQAAAA==.Kainis:BAAALAADCgYIEAAAAA==.Kalhmera:BAAALAAECgYIDAAAAA==.Kalinnia:BAAALAAECgEIAQAAAA==.Kanyer:BAAALAADCgMIBQAAAA==.Karial:BAAALAAECgYICwAAAA==.Karmus:BAAALAAECgEIAQAAAA==.Kau:BAAALAADCgcIEAAAAA==.',Ke='Keatonrsmith:BAAALAADCggIEgAAAA==.Keilas:BAAALAAECgMIAwAAAA==.Keyes:BAACLAAFFIEGAAIGAAMIQBw3AQARAQAGAAMIQBw3AQARAQAsAAQKgRgAAgYACAhsIewBAA4DAAYACAhsIewBAA4DAAAA.Keylala:BAAALAAECgIIAgAAAA==.',Kh='Kharnaz:BAAALAADCggIEgAAAA==.',Ki='Kiafera:BAAALAAECgEIAQAAAA==.Kimunkamuy:BAAALAAECgMIAwAAAA==.Kirlia:BAAALAAECgEIAQAAAA==.',Kn='Knull:BAAALAADCggIDQAAAA==.',Ko='Koretha:BAAALAADCgYIBgABLAAECggIFwADANQbAA==.',Kr='Krispitreat:BAAALAADCgIIAgAAAA==.Krobelus:BAAALAAECgYIDQAAAA==.',Ku='Kuboo:BAAALAAECgIIAgAAAA==.',Kv='Kvedaheillr:BAAALAADCgcICQAAAA==.Kvedaroðull:BAAALAADCgYIBgAAAA==.Kvedathulr:BAAALAADCgIIAgAAAA==.Kvedavrækæ:BAAALAADCggICQAAAA==.Kvedærilaz:BAAALAADCggIFQAAAA==.Kvóthe:BAAALAADCgYIBgABLAAECgIIAwABAAAAAA==.',['Kì']='Kìllstheweak:BAAALAAECgYICgAAAA==.',La='Laura:BAAALAADCgMIAwAAAA==.Layliah:BAABLAAECoEUAAIHAAgIVib3AABtAwAHAAgIVib3AABtAwAAAA==.',Le='Legaia:BAAALAAECgYIBwAAAA==.',Lf='Lfpaulopueri:BAAALAAECgEIAQAAAA==.',Li='Lildrinky:BAAALAADCggICAAAAA==.',Lo='Loafai:BAAALAAECgIIAwAAAA==.Lockrocks:BAAALAAECgIIBAAAAA==.Loktrah:BAAALAAECgMICAAAAA==.Lorcán:BAAALAADCgcIDwAAAA==.',Lu='Ludleth:BAAALAADCgYIBgAAAA==.Lunella:BAAALAADCggIGQABLAAECgcIFAAIAJEPAA==.Lunellia:BAABLAAECoEUAAMIAAcIkQ9HCQC3AQAIAAcIYwlHCQC3AQAJAAcIVg6wIgCcAQAAAA==.Lurkaslayer:BAAALAADCgcIBwAAAA==.',Ly='Lyka:BAAALAAECgIIAgAAAA==.',Ma='Mageistmage:BAAALAADCggIDgAAAA==.Malegar:BAAALAADCgcIGAAAAA==.Mango:BAAALAADCgYICQAAAA==.Marispera:BAAALAADCggICQAAAA==.Marvv:BAAALAAECgMIBAAAAA==.Marwen:BAAALAADCgcICQAAAA==.Maug:BAAALAADCgQIBAAAAA==.',Mc='Mclarie:BAAALAAECgEIAQAAAA==.',Me='Mehv:BAAALAADCggIFAAAAQ==.Melisan:BAAALAAECgEIAQABLAAECgcIEAABAAAAAA==.Mev:BAAALAADCgMIAwABLAADCggIFAABAAAAAQ==.',Mi='Midnightski:BAAALAADCgcIBwAAAA==.Miladybast:BAAALAADCggIEAAAAA==.Milaua:BAAALAADCgcIBwAAAA==.Minde:BAAALAAECgMIBQAAAA==.Mirra:BAAALAAECgIIBAAAAA==.',Mn='Mnr:BAAALAAECgEIAQAAAA==.',Mo='Monkrechaun:BAAALAAECgYIDQABLAAFFAIIAgABAAAAAA==.Moodys:BAAALAADCgEIAQAAAA==.Morionso:BAAALAADCggIEAAAAA==.Mortarion:BAAALAAECgYICgAAAA==.',My='Myaliki:BAAALAADCgYICAAAAA==.Myregards:BAAALAADCgcIEAAAAA==.Myspaceshria:BAAALAAECgcICAAAAA==.Mysstical:BAAALAADCgcIBwABLAAECggIEgABAAAAAA==.Mythis:BAAALAADCggIEwAAAA==.',Na='Naridiirne:BAAALAADCgUIBQABLAAECgIIAwABAAAAAA==.Narrezza:BAAALAAECgEIAQAAAA==.Natethaman:BAAALAADCgEIAQAAAA==.',Nc='Nc:BAAALAADCgcIDAAAAA==.',Ne='Nearn:BAAALAAECgMIAwAAAA==.Necropally:BAAALAADCgcICQAAAA==.Neonsalmandr:BAAALAADCggIFgAAAA==.',Ni='Nilianth:BAAALAAECgQIBQAAAA==.',Nn='Nnoitra:BAAALAADCgYIBgAAAA==.',No='Nonattarius:BAAALAAECgIIAgAAAA==.Norezfou:BAAALAAECgYIDQAAAA==.Notelonmusk:BAAALAADCgcIBwAAAA==.',Nu='Nurobi:BAAALAAECgYICQAAAA==.',Ny='Nyxy:BAAALAAECgMIAwAAAA==.',Oc='Ocey:BAAALAAECgEIAQAAAA==.',Od='Odanobunaga:BAAALAAECgcIEAAAAA==.Odyn:BAAALAAECgEIAQAAAA==.',Ol='Oldestgreg:BAAALAADCgQIBAAAAA==.',On='Onadin:BAAALAADCgIIAQAAAA==.',Or='Orisham:BAAALAADCgQIBAAAAA==.Oríon:BAAALAAECgEIAQAAAA==.',Pa='Paintress:BAAALAADCgYIBgAAAA==.Paleknight:BAAALAADCgcICQAAAA==.Pancake:BAAALAADCgYIBgABLAAECggIEgABAAAAAA==.Pancakedup:BAAALAAECggIEgAAAA==.Pankratos:BAAALAAECgMICwAAAA==.Paradias:BAAALAAECggIEgAAAA==.Pastor:BAAALAAECgEIAQAAAA==.Paxxul:BAAALAADCggIEwAAAA==.',Pe='Peaky:BAAALAAECgIIAgAAAA==.Peppersham:BAAALAAECgIIAgAAAA==.Petesdragin:BAAALAAECgIIAgAAAA==.',Pf='Pfftpfft:BAAALAADCgYIBwAAAA==.',Po='Poisonspirit:BAAALAADCgcIBwAAAA==.Powadin:BAAALAAECgYICQAAAA==.',Pr='Primed:BAAALAAECgYICwAAAA==.Privm:BAAALAADCgcIDQAAAA==.',Pu='Pungla:BAAALAAECgEIAQAAAA==.Purefire:BAABLAAECoEVAAIKAAcIwh5FEgByAgAKAAcIwh5FEgByAgAAAA==.',Ra='Racob:BAAALAADCgEIAQAAAA==.Radical:BAAALAADCgcIDQAAAA==.Ragestar:BAAALAADCgMIAwAAAA==.Randomclown:BAAALAADCggICAAAAA==.Ranii:BAAALAADCgcIBwAAAA==.Rashii:BAAALAAECgEIAQAAAA==.Rawör:BAAALAAECgMIAwAAAA==.',Re='Rebaderchi:BAAALAADCgMIAwABLAADCggICAABAAAAAA==.Remo:BAAALAADCgUIBQAAAA==.Remoria:BAAALAAECgMIBAAAAA==.Reuvir:BAAALAAECgYIDAAAAA==.Rev:BAAALAAECggIAQAAAA==.',Ri='Ritz:BAAALAADCgcICwAAAA==.River:BAAALAADCggIFgAAAA==.Rizzoy:BAAALAAECgIIBAAAAA==.',Ro='Ronrie:BAAALAAECgYICgAAAA==.Rowinna:BAAALAADCggIGAAAAA==.',Ru='Ruckabis:BAAALAAECgIIAgAAAA==.Ruthless:BAAALAAECgEIAQAAAA==.',Ry='Rybearkin:BAAALAADCggICAAAAA==.Ryumi:BAAALAAECgMIBAAAAA==.',Sa='Saberbtsrock:BAAALAAECgMIAwAAAA==.Saintjeb:BAAALAAECgMIAwAAAA==.Saitami:BAAALAAECgYICQAAAA==.Saladmuncher:BAAALAADCgMIAwAAAA==.Salinity:BAAALAAECgYIBgAAAA==.Samanaras:BAAALAAECgEIAgAAAA==.Sancarlos:BAAALAAECgMIBAAAAA==.Sangwyn:BAAALAAECgMIAwAAAA==.Sarkana:BAAALAAECgMIBAAAAA==.Saxonn:BAAALAAECgMIBQAAAA==.Saydis:BAAALAADCggIEgAAAA==.',Se='Seleinai:BAAALAAECgYIDQAAAA==.Seloric:BAAALAAECgMIAwAAAA==.Selunella:BAAALAADCgUIBQABLAAECgcIFAAIAJEPAA==.Serendrin:BAAALAAECgcIBwAAAA==.',Sh='Shadowskyz:BAAALAAECgMIBQABLAAECgYIDAABAAAAAA==.Shalami:BAAALAAECgEIAQAAAA==.Shamanizor:BAAALAADCgYIFAAAAA==.Shamina:BAAALAAECgYIDAAAAA==.Shammalin:BAAALAAECgMIBQAAAA==.Shamorex:BAAALAAECgMIBQAAAA==.Sharkbones:BAAALAAECgIIAgAAAA==.Sharpon:BAAALAAECgYICQAAAA==.Shax:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.Sherbert:BAAALAAECgMIBgAAAA==.Shi:BAAALAADCgUIBQAAAA==.Shiftit:BAAALAAECgYIDwAAAA==.Shiftyy:BAAALAADCgMIAwAAAA==.',Si='Simi:BAAALAADCgcICAAAAA==.',Sk='Skedaddler:BAAALAAECgMIBAAAAA==.',Sl='Slayn:BAAALAAECgYICQAAAA==.Slicé:BAAALAAFFAEIAQAAAA==.',Sm='Smokescale:BAAALAAECgIIAgAAAA==.',Sn='Snackie:BAAALAADCggIFgAAAA==.',So='Solanis:BAAALAADCgEIAQAAAA==.Solowner:BAAALAADCgYIBgAAAA==.Sorscrasus:BAAALAAECgMIAwAAAA==.',Sp='Spaceage:BAAALAADCggIDQAAAA==.Spikedriver:BAAALAAECgIIBAAAAA==.Spooky:BAAALAADCggIBwAAAA==.',St='Stariane:BAAALAAECgMIBQAAAA==.Starlittle:BAAALAADCgYIBgAAAA==.Starshatter:BAAALAAECgcIBQAAAA==.Steelfist:BAAALAADCggIDwAAAA==.Stony:BAAALAAECgMIBQAAAA==.Stormur:BAAALAADCgIIAgAAAA==.',Su='Summers:BAAALAADCgcIEAAAAA==.',Sw='Swaahy:BAAALAAECgYICgAAAA==.Swiftbreeze:BAAALAADCggIDgAAAA==.',Sy='Syletage:BAAALAAECgMIAwAAAA==.Syral:BAAALAADCgcICQAAAA==.',Ta='Talanea:BAAALAAECgYIDQAAAA==.Taurnator:BAAALAADCgMIAwAAAA==.Taylorswift:BAAALAAFFAIIAgAAAA==.',Tc='Tchiratha:BAAALAADCggIFAAAAA==.',Te='Telain:BAAALAAECgMIBQAAAA==.Temsham:BAAALAAECgQICAAAAA==.Tendertoby:BAAALAADCgcIBwAAAA==.Tentacoolz:BAAALAAECgMIAwAAAA==.Teslah:BAAALAADCgYICAAAAA==.',Th='Thakilla:BAAALAAECgYICQAAAA==.Thoreza:BAAALAAECgEIAQAAAA==.Thoryndin:BAAALAAECgcIDQAAAA==.Thraine:BAAALAAECgUIBQAAAA==.',Ti='Tinnyheals:BAAALAAECgMIAwAAAA==.',To='Tohnat:BAAALAAECgMIBQAAAA==.Tonythetiger:BAAALAADCggICAABLAAECgIIAwABAAAAAA==.Topchache:BAAALAADCgYIBgAAAA==.',Tr='Trinjal:BAAALAAECgMIBwAAAA==.Trishift:BAAALAAECgEIAQAAAA==.Trollan:BAAALAAECgEIAQAAAA==.Trollosarus:BAEALAADCgcIBwABLAAECggIGAAKANoeAA==.Trollosaurs:BAEALAAECgIIAgABLAAECggIGAAKANoeAA==.Trolosarushx:BAEBLAAECoEYAAMKAAgI2h4cDwCVAgAKAAgI2h4cDwCVAgALAAUI9BNTEwAZAQAAAA==.',['Tâ']='Tâfa:BAAALAAECgIIAwAAAA==.',['Tö']='Töxîñ:BAAALAAECgIIAgAAAA==.',Ul='Ultima:BAAALAAECgIIAgAAAA==.',Va='Valentine:BAAALAADCgcIDgAAAA==.',Ve='Venustar:BAAALAADCgUICAAAAA==.Veravibes:BAAALAADCgMIAwAAAA==.Vespor:BAAALAAECgYIBgAAAA==.',Vi='Viloria:BAAALAAECgMIAwAAAA==.Vincent:BAAALAADCgcICQAAAA==.Virrard:BAAALAAECgMIBQAAAA==.Vitalorange:BAACLAAFFIEFAAIHAAMIhx4VAQAlAQAHAAMIhx4VAQAlAQAsAAQKgRgAAwcACAhfIokFAPQCAAcACAhfIokFAPQCAAMAAQiRCQ9cACIAAAAA.',Vl='Vladimor:BAAALAADCggICAAAAA==.Vladimyrr:BAAALAAECgEIAQAAAA==.',Vo='Volkov:BAAALAAECgcIDAAAAA==.Vortrox:BAAALAADCgUIBgAAAA==.Voslaarum:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.',['Vé']='Vénom:BAAALAAECgMIBgAAAA==.',['Vë']='Vëda:BAAALAAECgMIBQAAAA==.',Wa='Warpony:BAAALAAECgEIAQAAAA==.',Wi='Wiçker:BAAALAAECgYICQAAAA==.',Wo='Wompwomp:BAAALAADCgQIBAABLAADCggIDwABAAAAAA==.',Wr='Wras:BAAALAADCggIFwAAAA==.Wreckt:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.Wreked:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Wretched:BAAALAAECggIBQAAAA==.',Xa='Xandrah:BAAALAAECgIIAgAAAA==.Xanslash:BAAALAAECgYICwAAAA==.Xantana:BAAALAADCgMIAQAAAA==.',Xi='Xiansai:BAAALAAECgMIBAAAAA==.',Ye='Yehni:BAAALAAECgQIBAAAAA==.Yesfielia:BAAALAADCgEIAQAAAA==.',Yo='Yoraz:BAAALAADCgIIAgAAAA==.',['Yê']='Yêti:BAAALAADCggIAgAAAA==.',Za='Zandino:BAAALAADCgQIBAAAAA==.',Ze='Zezie:BAAALAADCgYICQAAAA==.',Zo='Zombiehippo:BAAALAAECgMIAwAAAA==.',Zz='Zztopless:BAAALAADCgUIBQAAAA==.',['Ða']='Ðandy:BAAALAAECgQICQAAAA==.',['Ðe']='Ðemøn:BAAALAADCgcICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end