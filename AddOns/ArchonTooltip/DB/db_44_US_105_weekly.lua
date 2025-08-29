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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Warrior-Fury','Priest-Holy','Monk-Mistweaver','Mage-Arcane','DemonHunter-Vengeance','Evoker-Devastation','DeathKnight-Frost','DemonHunter-Havoc',}; local provider = {region='US',realm='Garrosh',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aadolin:BAAALAADCgcIBwAAAA==.Aarranus:BAAALAADCgIIAgAAAA==.',Ac='Acalionna:BAAALAADCggICAAAAA==.Accessdenied:BAAALAADCgMIAwAAAA==.',Ae='Aelrik:BAAALAADCggICQAAAA==.Aeovina:BAAALAAECggIDgAAAA==.Aertenn:BAAALAADCgEIAQAAAA==.',Ah='Ahsnap:BAAALAADCgYIBgAAAA==.',Ai='Airasault:BAAALAADCgIIAgAAAA==.Airassault:BAAALAADCgYIBgAAAA==.Airazzault:BAAALAADCgEIAQAAAA==.',Ak='Akag:BAAALAADCggIEAAAAA==.Akirasin:BAAALAADCgcIBwABLAADCgcIDQABAAAAAA==.',Al='Alisi:BAAALAAECgIIAgAAAA==.Aloradannan:BAAALAADCgYIBgAAAA==.',Am='Amaellara:BAAALAAECgUIBwAAAA==.Amoralanth:BAAALAAECgMIAwAAAA==.',An='Anthatheal:BAAALAADCgcICgAAAA==.Anthathein:BAAALAADCgYIBgABLAADCgcICgABAAAAAA==.',Ap='Apollox:BAAALAADCgUIBgAAAA==.Apologies:BAABLAAECoEXAAICAAgI8iV8AQBzAwACAAgI8iV8AQBzAwABLAAFFAIIAgABAAAAAA==.',Aq='Aquilos:BAAALAADCggICwAAAA==.',Ar='Archblade:BAAALAAECgYIBgAAAA==.Archlord:BAAALAADCgcIDQAAAA==.Arckaius:BAAALAAECgMICQAAAA==.Argerd:BAAALAADCgQIBAAAAA==.Arkheals:BAAALAADCgcIBAAAAA==.Artemisia:BAAALAADCgcICgAAAA==.Aryia:BAAALAADCgcICgABLAAECgEIAgABAAAAAA==.',As='Asrielle:BAAALAADCgEIAQABLAAECgMIAwABAAAAAA==.Assasinator:BAAALAADCgcIBwAAAA==.',Au='Audare:BAAALAAECgMIBwAAAA==.',Av='Avarya:BAAALAAECgYICQAAAA==.',Ay='Ayumî:BAAALAADCgcIBwAAAA==.',Az='Azarin:BAAALAAECgEIAQAAAA==.Azulvedor:BAAALAADCgIIAgAAAA==.',Ba='Backyard:BAAALAADCgUIBQAAAA==.Bahm:BAAALAAECgQICQAAAA==.Bainek:BAAALAADCgQIBQAAAA==.Basixx:BAAALAAECgMIAwAAAA==.Bawitab:BAAALAAECgQIBQAAAA==.',Be='Bearfist:BAAALAADCgcIBwAAAA==.Bearykyns:BAAALAADCgcIFAAAAA==.Beepee:BAAALAAECgEIAQAAAA==.Bejay:BAAALAADCggIEAAAAA==.Belareth:BAAALAAECgQIBAAAAA==.Belindraina:BAAALAADCgMIAwABLAADCggIEAABAAAAAA==.',Bi='Bigsock:BAAALAADCgMIAwAAAA==.Biyanshi:BAAALAAECgMIBAAAAA==.',Bl='Blackdusk:BAAALAAECgEIAQAAAA==.Blackgranite:BAAALAADCgcICAAAAA==.Blackwave:BAAALAADCgcIFQAAAA==.Blep:BAAALAAECgQIBwAAAA==.Blindluck:BAAALAAECgMIAwAAAA==.Blitzø:BAAALAADCggIEwAAAA==.Bluestampede:BAAALAADCgcIDQAAAA==.',Bo='Boldntanky:BAAALAAECgIIAgAAAA==.Boro:BAAALAADCgYIDAAAAA==.Bowlinder:BAAALAAECgcIBwAAAA==.',Br='Braldar:BAAALAAECgIIAwAAAA==.Brando:BAAALAAECgYIDwAAAA==.Braxiss:BAAALAAECgYICwAAAA==.Brilin:BAAALAAECgUIBgAAAA==.Brithio:BAAALAADCgMIAgAAAA==.Brofrodeath:BAAALAADCgYIBgAAAA==.Broguë:BAAALAADCggIFgAAAA==.Brucarus:BAAALAAECggIBQAAAA==.Brueld:BAAALAADCgcIDAAAAA==.',Bu='Burgerwrthit:BAAALAADCgYIDAAAAA==.Buymyftpics:BAAALAAECgQICwAAAA==.',Ca='Calademon:BAAALAAECgYICQAAAA==.Calzone:BAAALAADCgEIAQAAAA==.Cavick:BAAALAAECgQIBQAAAA==.Cawnor:BAAALAADCgcIDgAAAA==.',Cc='Ccunter:BAAALAAFFAIIAgAAAA==.',Ch='Chainsoul:BAAALAAECgIIAwAAAA==.Chancec:BAAALAADCgcICwAAAA==.Chanvoker:BAAALAADCgIIAgAAAA==.Charliedog:BAAALAADCgcICAAAAA==.Charlottee:BAAALAADCggICQAAAA==.Charrcharr:BAAALAADCgQIBQAAAA==.Charsham:BAAALAADCggIFAAAAA==.Cherrii:BAAALAADCgMIAwAAAA==.Chervil:BAAALAAECgcIBwABLAAECggIFwADAE4hAA==.Chickeypox:BAAALAAECgcICQAAAA==.Chiillyy:BAAALAAECgMIAwAAAA==.Chiselin:BAAALAADCgcICwAAAA==.Chishu:BAAALAADCgcIBwAAAA==.Chriscornell:BAAALAADCgMIAwAAAA==.Chunkernot:BAABLAAECoEUAAIEAAcI5BtvEABaAgAEAAcI5BtvEABaAgAAAA==.',Cl='Clerikyns:BAAALAADCgYIBwABLAADCgcIFAABAAAAAA==.',Co='Coalgrim:BAAALAAECgYICwAAAA==.Combonk:BAAALAADCggICQAAAA==.Coranna:BAAALAAECgYIBwAAAA==.Cordarus:BAAALAADCgIIAgAAAA==.Cormier:BAAALAADCggIEAAAAA==.Cozmos:BAAALAAECgEIAQAAAA==.Cozytree:BAAALAAECgIIAgAAAA==.',Da='Dahkeus:BAAALAADCgcIBwAAAA==.Daigon:BAAALAADCggIFQAAAA==.Dankestdad:BAAALAADCgEIAQAAAA==.Dankweaver:BAAALAAECgMIAwAAAA==.Darthxander:BAAALAAECgYICwAAAA==.Darvain:BAAALAAECgcICwAAAA==.',Dc='Dctrstrange:BAAALAADCggIDgAAAA==.',De='Deithis:BAAALAADCgcIBwAAAA==.Demoncookie:BAAALAADCgcIDgAAAA==.Demonixx:BAAALAADCgMIAwAAAA==.Demonstix:BAAALAAECgEIAQAAAA==.Demontoki:BAAALAAECgcIAgAAAA==.Deë:BAAALAADCgQIBQAAAA==.',Di='Dikheal:BAAALAADCggIDwAAAA==.Dinda:BAAALAAECgMIBAAAAA==.Dirtypapin:BAAALAADCgcIBwAAAA==.',Do='Donir:BAAALAAECgEIAQAAAA==.',Dr='Draganna:BAAALAADCgcIFAAAAA==.Drakarii:BAAALAAECgYIBgABLAAECgYIDgABAAAAAA==.Drelka:BAAALAADCggICwAAAA==.Druidia:BAAALAAECgMIAwAAAA==.Drunkeysnek:BAAALAAECgQICAAAAA==.Drámá:BAAALAADCggICAAAAA==.',Du='Dubbies:BAAALAAECgUICAAAAA==.Duller:BAAALAADCgMIBAAAAA==.Dullerdog:BAAALAAECgYIDQAAAA==.Dumpz:BAAALAAECgMIAwAAAA==.Duraggodx:BAAALAADCgEIAQAAAA==.Durgardal:BAAALAADCgcIBwABLAADCggIDgABAAAAAA==.',Dv='Dvf:BAAALAADCggIFgAAAA==.',Dy='Dymloseshamy:BAAALAAECgYICgAAAA==.',Ei='Eien:BAAALAAECgYICgAAAA==.',El='Elanduin:BAAALAADCgEIAQAAAA==.Elani:BAAALAAECgYIBgAAAA==.Elcici:BAAALAADCggIFgAAAA==.Electroll:BAAALAADCggICAAAAA==.Elenii:BAAALAAECgYIDgAAAA==.Elhoss:BAAALAADCgUIBQAAAA==.Elidinis:BAAALAADCgcIFQAAAA==.Elladraxia:BAAALAADCgMIAwAAAA==.Elontusked:BAAALAADCgQIBAAAAA==.Elranid:BAAALAADCgEIAQAAAA==.Elroyjenkins:BAAALAADCgcICgAAAA==.Elshorbaa:BAAALAAECgQIBAAAAA==.Elysya:BAAALAADCgIIAgAAAA==.',Em='Emptyside:BAAALAADCggIFQAAAA==.',En='Enchorxxi:BAAALAAECgMIBQAAAA==.Enetrenazara:BAAALAADCgMIAwAAAA==.',Ep='Epicgooner:BAAALAADCgUIBQAAAA==.',Er='Erahm:BAAALAADCgcICwAAAA==.Erahmm:BAAALAADCggICgAAAA==.',Eu='Eurydicie:BAAALAADCgEIAQAAAA==.',Ev='Evelynna:BAAALAADCgEIAQABLAADCggIEAABAAAAAA==.Evle:BAAALAAECgcIDwAAAA==.',Ex='Excorcist:BAAALAADCgEIAQAAAA==.',Ez='Ezdeathh:BAAALAADCgQIBAAAAA==.',Fa='Farnzhu:BAAALAADCggIFgAAAA==.Fathlia:BAAALAAECggIEAAAAA==.',Fe='Fely:BAAALAADCggIEAAAAA==.Feraah:BAAALAADCgcIDwAAAA==.Fezzjin:BAAALAAECgQIBQAAAA==.',Fi='Fidgetspin:BAAALAAECgYIBwAAAA==.Fireguard:BAAALAADCggIDwAAAA==.Firethrone:BAAALAAECgMIBAAAAA==.Fishslapper:BAAALAAECgEIAQAAAA==.Fizzelbob:BAAALAADCgQIBQAAAA==.',Fl='Flameknight:BAAALAADCgEIAQAAAA==.Flashlights:BAAALAAECgEIAQAAAA==.Flightkiller:BAAALAAECgMIBAAAAA==.',Fo='Foobar:BAAALAADCgQIBAAAAA==.Foot:BAAALAADCgcIBwAAAA==.Forcefaith:BAABLAAECoEVAAICAAgIbyTpAwBFAwACAAgIbyTpAwBFAwAAAA==.Forcemonk:BAAALAAECgUICAAAAA==.Forcerogue:BAAALAADCgEIAQAAAA==.',Fr='Frankenstena:BAAALAADCgcIBAAAAA==.Freezer:BAAALAAECgYIDAAAAA==.Freva:BAAALAAECggIEAAAAA==.Frostfiree:BAAALAADCgcIDQAAAA==.Fruitocean:BAAALAAECgYIBgAAAA==.Fruitpuddle:BAAALAAECgQIBAABLAAECgYIBgABAAAAAA==.',Fu='Furyos:BAAALAADCgcIDQAAAA==.',Fy='Fyone:BAEALAAECgYIBgABLAAECggIEAABAAAAAA==.',Ga='Gadionir:BAAALAADCgQIAwAAAA==.Gambriniss:BAAALAADCggIDQAAAA==.Garrylarry:BAAALAADCggICAAAAA==.',Gi='Gizzinuz:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.',Gn='Gnomercyy:BAAALAADCgIIAgAAAA==.',Go='Gokus:BAAALAADCggICQAAAA==.Goldlust:BAAALAADCgcIBwAAAA==.Gona:BAAALAADCgcIBwAAAA==.Goroz:BAAALAAECgMIAwAAAA==.',Gr='Graystaf:BAAALAADCggICwAAAA==.Greyowl:BAAALAADCgcIBwAAAA==.Grifflez:BAAALAAECgEIAQAAAA==.Grimacefour:BAAALAADCgQIBAAAAA==.',Gu='Guldane:BAAALAADCgIIAgAAAA==.',['Gö']='Gödsmäcked:BAAALAADCgcIBwAAAA==.',Ha='Halsten:BAAALAADCgcIDQAAAA==.Halvanhelev:BAAALAAECgYIEAAAAA==.Hardrockgirl:BAAALAAECgIIAgAAAA==.Harmonechi:BAAALAADCgQIBAAAAA==.Hazeymae:BAAALAADCgcICgAAAA==.',He='Healstepdad:BAAALAADCggICAAAAA==.Hellhowse:BAAALAADCggICAAAAA==.Hellrisíng:BAAALAADCgYIBgAAAA==.Hellzcrusade:BAAALAAECgMIAwAAAA==.',Hi='Hitohito:BAAALAADCgIIAgABLAAECgYIBwABAAAAAA==.',Ho='Hobodrunk:BAAALAAECgYICAAAAA==.Holstice:BAAALAADCgIIAgAAAA==.Holyfocks:BAAALAADCgcIDAAAAA==.Holyholdy:BAAALAAECgIIAwAAAA==.Holypoon:BAAALAADCgMIAwAAAA==.Holypuuss:BAAALAAECgcICwAAAA==.Holyskinny:BAAALAAECgYIBgAAAA==.Homelander:BAAALAADCggIEwAAAA==.Hoplitee:BAAALAADCggIDAAAAA==.Hoplitetotem:BAAALAADCggICAABLAADCggIDAABAAAAAA==.Hortwaz:BAAALAAECgYICQAAAA==.',Ht='Htiál:BAAALAAECgQIBQAAAA==.',Il='Ilyamurometz:BAAALAAECggIEAAAAA==.',Im='Immorta:BAAALAAECgYIDAAAAA==.',In='Indura:BAAALAADCgcIBwAAAA==.Interwoven:BAAALAAECgEIAgAAAA==.',Ir='Iritar:BAAALAAECgYICAAAAA==.',Is='Isaacthetall:BAAALAADCgcIDgAAAA==.',Ja='Jacknblack:BAAALAADCgcIBwAAAA==.Jadefires:BAAALAADCgQIBAAAAA==.Jandda:BAAALAAECgYICQAAAA==.Jankum:BAAALAAECgMIAgAAAA==.Jarsham:BAAALAAECgQIBQAAAA==.Jayhunter:BAAALAAECgMIBAAAAA==.Jaywin:BAAALAAECgYICQAAAA==.',Je='Jeeperscreep:BAAALAADCgYIDAAAAA==.',Jk='Jkm:BAAALAADCggIFgAAAA==.',Jo='Josephhyuga:BAAALAAECgMIAwAAAA==.',Jr='Jrocmfka:BAAALAAECgIIAwAAAA==.',Ju='Junesong:BAAALAAECgEIAQABLAAECgcIFAAFAEATAA==.',Ka='Kalinuz:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.Kaotiknuckle:BAABLAAECoEVAAIGAAgICBlLBwBHAgAGAAgICBlLBwBHAgAAAA==.Kattara:BAAALAADCgcIBwAAAA==.Kazgin:BAAALAADCgIIAgAAAA==.',Ke='Keemster:BAAALAADCgcIDAAAAA==.Kenté:BAAALAAECgcIDQAAAA==.',Kh='Khalifaz:BAAALAAECgMIBwAAAA==.Khaotikdraco:BAAALAAECgcIEQAAAA==.',Ki='Kilbo:BAAALAAECgUICQAAAA==.Kilhok:BAAALAAECggICQAAAA==.Kilshouts:BAAALAAECggIEgAAAA==.Kiltree:BAAALAAECgIIAgABLAAECggIEgABAAAAAA==.Kimagure:BAAALAADCgUIBwABLAAECgYICgABAAAAAA==.Kiyoshie:BAAALAAECgYICQAAAA==.',Ko='Kobl:BAAALAAECgMIAwAAAA==.Koftimu:BAAALAAECgMIBAAAAA==.Kontroll:BAEALAADCggICwAAAA==.Korbinian:BAAALAADCgMIAwABLAADCggIDgABAAAAAA==.Korothir:BAAALAADCggIDgAAAA==.',Kr='Kravickx:BAAALAADCgYIBgAAAA==.Krieghelm:BAAALAAECgcIBwAAAA==.',Ku='Kumaa:BAAALAADCggIDwAAAA==.Kurayamiryu:BAAALAADCgcIBwAAAA==.',Ky='Kyrakka:BAAALAAECgEIAQABLAAECgcIDQABAAAAAA==.',La='Laitue:BAAALAADCggICQAAAA==.Laj:BAAALAADCgQIBAAAAA==.Lajjad:BAAALAADCgEIAQAAAA==.Larissa:BAAALAAECgIIBQAAAA==.Laserdisc:BAAALAAECgEIAQAAAA==.Lathillea:BAAALAAECgIIAgAAAA==.Lavendertown:BAAALAADCggIDAAAAA==.Lazzirus:BAAALAAECgYIBgAAAA==.',Le='Ledorocky:BAAALAADCgQIBAAAAA==.Lepeigne:BAAALAADCgEIAQAAAA==.Lethis:BAAALAADCgcIDQAAAA==.Levalock:BAAALAAECgMIAwAAAA==.',Li='Life:BAAALAADCggIDwAAAA==.Linthiril:BAAALAAECgIIAgAAAA==.Littlefat:BAAALAADCgYICQAAAA==.',Lo='Lockk:BAAALAAECggIEAAAAA==.Loggann:BAAALAADCgcIBwAAAA==.Lorily:BAAALAAECgYICQAAAA==.Lostdogg:BAAALAAECgYIDgAAAA==.',Lu='Lukashenko:BAAALAAECgMIBwAAAA==.Lunasia:BAAALAADCgIIAQAAAA==.',Ly='Lymka:BAAALAADCgQIBAAAAA==.Lyserra:BAAALAADCgMIAwAAAA==.',Lz='Lz:BAAALAAECgEIAQAAAA==.',Ma='Madhowse:BAAALAAECgEIAQAAAA==.Magicpants:BAAALAADCggIFgAAAA==.Mahohyuga:BAAALAAECgIIAgAAAA==.Manndo:BAAALAADCggIDgAAAA==.Margdan:BAAALAADCgQIBAAAAA==.Martenbcloak:BAAALAAECgQICAAAAA==.Mastocarpus:BAAALAADCgYIBgAAAA==.Maxmiup:BAAALAADCgYIBgAAAA==.',Me='Mechawar:BAAALAADCgEIAQABLAAECgIIAwABAAAAAA==.Mechussy:BAAALAAECgEIAQAAAA==.Medarela:BAAALAADCggIDgAAAA==.Meeke:BAAALAAECgcIEwAAAA==.Melmin:BAAALAAECgQIBwAAAA==.Metamora:BAAALAAECgEIAQAAAA==.Meuria:BAAALAAECgMIAwAAAA==.',Mi='Missyann:BAAALAADCgcIDQAAAA==.Mistahclean:BAAALAADCgEIAQAAAA==.Mistamec:BAAALAAECgIIAwAAAA==.',Mo='Mojin:BAAALAADCgIIAgAAAA==.Mojofoko:BAAALAADCggICgAAAA==.Mojomender:BAAALAADCgcIBgAAAA==.Moltaan:BAAALAADCggICAAAAA==.Momô:BAAALAAECgIIAgAAAA==.Moneebagz:BAAALAAECgIIAgAAAA==.Monomis:BAAALAADCggIFgAAAA==.Moondust:BAAALAADCgcIBwAAAA==.Moonem:BAAALAAECgQIBQAAAA==.',Mu='Mukaag:BAAALAADCgcICwAAAA==.Munglung:BAAALAADCgcICgAAAA==.Mustacheguy:BAAALAADCgYIBgAAAA==.',My='Mysticfox:BAAALAADCgIIAgAAAA==.Mysticwarior:BAAALAADCgYIBgAAAA==.',Mz='Mzmiyagy:BAAALAADCgMIAwAAAA==.',['Mé']='Méta:BAAALAADCggICwABLAAECgEIAQABAAAAAA==.',Na='Nachopapa:BAAALAADCgcIDgAAAA==.Namyssia:BAAALAADCgQIBAAAAA==.Nasturtium:BAAALAADCggIDwABLAAECggIFwADAE4hAA==.Naturae:BAAALAADCgUIBgAAAA==.Nazarick:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Nazaricksm:BAAALAAECgIIAgAAAA==.',Ne='Necroid:BAAALAADCgYIBgAAAA==.Nemesís:BAAALAADCgcIDgAAAA==.Nerclopse:BAAALAAECgYICwAAAA==.Neverender:BAABLAAECoEUAAIFAAcIQBM1HADEAQAFAAcIQBM1HADEAQAAAA==.',Ni='Niarwodahs:BAAALAAECgYIBgAAAA==.Nightiee:BAAALAADCggICAAAAA==.Nishalzin:BAAALAADCgMIAwAAAA==.',Nm='Nmoney:BAAALAADCgIIAgAAAA==.',No='Noobilite:BAAALAAECgMIAwAAAA==.Norde:BAAALAADCggICAAAAA==.Noritotem:BAAALAADCgYICAAAAA==.',Nu='Nunontharun:BAAALAADCgQIBAAAAA==.Nutnbolt:BAAALAADCggIEAABLAAECgcIEAABAAAAAA==.',Ny='Nymn:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.',['Nú']='Númb:BAAALAAECgQIBAAAAA==.',Ob='Obizuuth:BAAALAADCgMIAwAAAA==.',Ol='Olstonie:BAAALAADCgcIBwAAAA==.',Om='Omegawuulf:BAAALAADCgUIBQAAAA==.Omneknight:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.',On='Onebutton:BAAALAAECgMIAwAAAA==.Onelock:BAAALAADCgcIBwAAAA==.',Oo='Ookko:BAAALAAECgMIAwAAAA==.',Op='Opalite:BAAALAAECgEIAQAAAA==.',Or='Orbiting:BAAALAAECgMIAwAAAA==.Orgargo:BAAALAAECgMIBAAAAA==.Orvon:BAAALAADCgcIBwAAAA==.',Pa='Pallyzombi:BAAALAADCgcIDQABLAAECgUIBwABAAAAAA==.Papakobe:BAAALAADCggIEAABLAAECgYICAABAAAAAA==.Papakoble:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Paperplate:BAAALAADCgMIAwAAAA==.Pasqal:BAAALAAECgYICQAAAA==.Pattycake:BAAALAADCgIIAwABLAAECgcIEwABAAAAAA==.Pattyhealsu:BAAALAAECgcIEwAAAA==.',Pe='Peachizz:BAAALAADCgcIBwAAAA==.Peeksmania:BAAALAADCggIEQAAAA==.',Ph='Phaonis:BAAALAADCgcIDQAAAA==.',Pi='Pinkerton:BAAALAADCgUICQAAAA==.Piptheshort:BAAALAADCgMIAwAAAA==.',Pl='Playdate:BAAALAADCgUIBgAAAA==.',Po='Poof:BAAALAAECgYIEAAAAA==.Porshaa:BAAALAADCgIIAgAAAA==.Portablemage:BAAALAADCgUIBgAAAA==.',Ps='Psychoclaw:BAAALAADCgcIBwAAAA==.',Pu='Pureza:BAAALAADCgMIAwAAAA==.Putrefya:BAAALAADCgIIAwAAAA==.',Qu='Quickbrown:BAAALAADCggIFgAAAA==.',Ra='Randomin:BAAALAADCgcICQAAAA==.Raphag:BAAALAAECgEIAQAAAA==.Razenot:BAAALAADCgUIBQAAAA==.',Re='Redadin:BAAALAADCgcICQAAAA==.Redneckrouge:BAAALAADCgQIBAAAAA==.Redniles:BAAALAADCgQIBAAAAA==.Reno:BAAALAAECgEIAQAAAA==.Renthyr:BAAALAADCggICwAAAA==.Rentiano:BAAALAAECgMIAwAAAA==.Reportcard:BAAALAAECgUICQAAAA==.Reurog:BAAALAAECgMIAwAAAA==.Reyalswodahs:BAAALAAECgMIAwAAAA==.',Rh='Rhakier:BAAALAADCgUIBQAAAA==.',Ri='Rightoustorm:BAAALAADCgcICgAAAA==.Ripthemaster:BAAALAADCgcIBwAAAA==.Ritalia:BAAALAADCggICQAAAA==.',Ro='Roadiee:BAAALAAECgMIBQAAAA==.Roadkyll:BAAALAADCggIFgAAAA==.Rocknstoned:BAAALAADCgYIBgAAAA==.Rocochon:BAAALAAECgMIBAAAAA==.Roobern:BAAALAAECgUIBgAAAA==.Rootbound:BAAALAADCgEIAQAAAA==.Rosamoon:BAAALAADCggIFgAAAA==.Rovi:BAACLAAFFIEFAAIHAAMIRBHnBQDjAAAHAAMIRBHnBQDjAAAsAAQKgSEAAgcACAgRJaQDAD0DAAcACAgRJaQDAD0DAAAA.',Ru='Rune:BAAALAADCggICAABLAAFFAMIBQAHAEQRAA==.',['Rã']='Rãine:BAAALAADCgcIBwAAAA==.',Sa='Sahmash:BAAALAAECgMIAwAAAA==.Salasong:BAAALAADCgIIAgAAAA==.Samburai:BAAALAADCgcICgAAAA==.Sandrinea:BAAALAAECgMIBAAAAA==.Sanguinore:BAAALAADCggICAAAAA==.Sardenaris:BAAALAAECgMIBgAAAA==.Sarusx:BAAALAADCgcIDgAAAA==.Sasquatchwar:BAAALAADCgcIBwAAAA==.Satephwar:BAAALAAECgIIBAAAAA==.Sathrean:BAAALAADCgUIBQAAAA==.',Sc='Scryix:BAAALAAECggIEAAAAA==.',Se='Sedale:BAAALAADCgcIEgAAAA==.Seesdeline:BAAALAAECgYIDAAAAA==.Seiros:BAAALAAECgMIBAAAAA==.Sentaku:BAAALAADCgMIAwAAAA==.Seo:BAAALAAECgUIBwAAAA==.',Sh='Shadowerise:BAAALAADCgcIAwAAAA==.Shelon:BAAALAAECgYICwAAAA==.Shibal:BAAALAAECgYICAAAAA==.Shigwyn:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Shigz:BAAALAAECgEIAQAAAA==.Shilan:BAAALAADCgcIBwAAAA==.Shinjoh:BAAALAAECgQIBQAAAA==.Shivsham:BAAALAADCgIIAgAAAA==.',Si='Sicknezz:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.Sildrusil:BAAALAADCgEIAQAAAA==.Sill:BAEALAAECggIEAAAAA==.Silvercore:BAAALAAECggIDgAAAA==.Silverstarz:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.Silverweave:BAAALAAECgYICQAAAA==.Sindari:BAAALAAECgIIBAAAAA==.Sinturio:BAAALAAECgEIAQAAAA==.',Sk='Skarg:BAAALAADCggICAAAAA==.Skittlesdk:BAAALAADCggICAAAAA==.Skyeashe:BAAALAADCggIGwAAAA==.Skyeluna:BAAALAADCggIDgAAAA==.Skyerunner:BAAALAAECgIIAgAAAA==.',Sl='Slappyhands:BAAALAAECgEIAQABLAAECgQIBwABAAAAAA==.Slowmo:BAAALAAECgIIAgAAAA==.Slypunkit:BAAALAADCgIIBAAAAA==.',Sm='Smittles:BAAALAAECgIIAwAAAA==.',So='Sophus:BAAALAAECgcIDgAAAA==.Soren:BAAALAAECgIIAwABLAAECgYIDAABAAAAAA==.Sorien:BAAALAADCgYIBwABLAAECgYIDAABAAAAAA==.Sorä:BAAALAAECgMIBAAAAA==.Soèi:BAAALAADCgcIBwAAAA==.',Sp='Spagooter:BAAALAAECgcIEAAAAA==.Sparq:BAAALAADCgcICAAAAA==.',Sr='Sren:BAAALAADCgQIAgABLAAECgYIDAABAAAAAA==.Srgtmilk:BAAALAAECggIBwAAAA==.',St='Sta:BAAALAAECgUICgAAAA==.Stabzya:BAAALAADCggIDAAAAA==.Startitan:BAAALAAECgMIAwAAAA==.Stonemason:BAAALAAECgEIAQAAAA==.',Sw='Swagruid:BAAALAAECgMIBQAAAA==.Swampslinger:BAAALAAECgIIAgAAAA==.Swordlady:BAAALAADCgcIBwABLAAECgYIDgABAAAAAA==.',Sx='Sx:BAAALAAFFAIIAgAAAA==.',Sy='Syndragos:BAAALAADCgYIBgAAAA==.Synoria:BAAALAAECggIBQAAAA==.Syntari:BAAALAAECggIEwAAAA==.Syntary:BAAALAAECgIIAgAAAA==.',['Sì']='Sìn:BAAALAAECgYIBgAAAA==.',Ta='Talenalat:BAAALAAECgEIAQAAAA==.Talzik:BAAALAADCgQIBAAAAA==.Tanaros:BAAALAADCggIFgAAAA==.Tarnuz:BAAALAADCgUICgAAAA==.Taymatt:BAAALAAECgEIAQAAAA==.',Td='Tdsdarkuha:BAAALAAECgYICAAAAA==.',Te='Tednuget:BAAALAADCgUIBQAAAA==.Tejasgeek:BAAALAADCggIFgAAAA==.Tenleron:BAAALAADCgcIEAAAAA==.Tenntoes:BAAALAAECgYIDQAAAA==.Terrorbladee:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.',Th='Thagabagool:BAAALAADCggICwAAAA==.Thannil:BAAALAAECgMIBAAAAA==.Thebgboss:BAAALAADCgEIAQAAAA==.Themuffinman:BAAALAADCgcIBwAAAA==.Thesickness:BAAALAAECgMIAwAAAA==.Thestev:BAAALAADCgcIDgAAAA==.Thingolo:BAAALAADCgcICgAAAA==.Thunderflame:BAAALAAECgYIBwAAAA==.Thur:BAAALAAECgQIBgAAAA==.',Ti='Tigrillo:BAAALAADCgQIBQAAAA==.Tinyclash:BAAALAAECgIIAgAAAA==.Tirieni:BAAALAADCggIAQAAAA==.Tizef:BAAALAADCgMIAwAAAA==.',To='Toasterr:BAAALAADCgcICAAAAA==.Tokispin:BAAALAADCggIDwAAAA==.Toldyousoul:BAAALAAECgMIBQAAAA==.Tommyd:BAAALAAECgIIBAAAAA==.Toon:BAAALAADCggIDgAAAA==.Tormentaa:BAAALAADCgUIBQAAAA==.Totempie:BAAALAAECgYICQAAAA==.Totimz:BAAALAAECgYICQAAAA==.Toxicyuri:BAAALAADCgcICwAAAA==.',Tr='Traelirra:BAAALAADCggIEAAAAA==.Travellondon:BAAALAADCgcICAAAAA==.Treebirth:BAAALAAECgcIEwAAAA==.Trixss:BAAALAADCgMIAwAAAA==.Trunder:BAAALAAECgQIBQAAAA==.',Tu='Tuskgwel:BAAALAAECgYIBwAAAA==.',Tv='Tvath:BAAALAADCgIIAgAAAA==.',Tw='Twinkletows:BAAALAADCgcIBwAAAA==.',Ui='Uil:BAAALAAECgEIAQAAAA==.',Up='Upngo:BAABLAAECoEXAAIEAAgIZB1yCgC+AgAEAAgIZB1yCgC+AgAAAA==.',Ur='Urabus:BAAALAADCgcIDQAAAA==.Uraume:BAAALAADCgEIAQAAAA==.Urlacher:BAAALAADCgcIDwAAAA==.Urmomi:BAAALAADCgcIDQAAAA==.',Va='Valorna:BAAALAADCggIFgAAAA==.Vandeador:BAAALAAECgMIAwABLAAECggIFgAIAK4kAA==.Vandredor:BAABLAAECoEWAAIIAAgIriTUAABAAwAIAAgIriTUAABAAwAAAA==.Vaporeon:BAAALAADCgUIBQABLAAECgYIBwABAAAAAA==.',Ve='Velarria:BAAALAADCgcICAAAAA==.Velicelia:BAAALAAECgMIBQAAAA==.',Vi='Vivinono:BAAALAAECgIIAgAAAA==.Viølence:BAAALAAECgQIBQAAAA==.',Vl='Vluthe:BAAALAAECgEIAQAAAA==.',Vo='Vodoriik:BAAALAAECgEIAQAAAA==.',Vr='Vraelgrizz:BAAALAAECgIIAgAAAA==.',Vv='Vvnono:BAAALAADCgYIBwAAAA==.',['Vä']='Vääko:BAAALAADCggIFgAAAA==.',Wa='Wagwun:BAAALAADCgQIBwAAAA==.Waluigi:BAAALAAECgEIAQAAAA==.',We='Welimarx:BAAALAADCggICAAAAA==.Westinghouse:BAAALAAECgEIAQAAAA==.',Wh='Whippoorwill:BAAALAAECgYICQAAAA==.',Wi='Wildsmile:BAAALAADCgYIBgAAAA==.Willmoon:BAABLAAECoEXAAIDAAgITiEtCADMAgADAAgITiEtCADMAgAAAA==.',Wo='Woe:BAAALAADCggIDgAAAA==.Wolfnacht:BAAALAADCggIDwAAAA==.Woljin:BAAALAAECgEIAQAAAA==.',Wr='Wrathfil:BAABLAAECoEYAAIJAAgI1SGbBAD4AgAJAAgI1SGbBAD4AgAAAA==.',Wu='Wukangmei:BAAALAADCgcIFwAAAA==.',Xa='Xandai:BAAALAAECgEIAQABLAAECgUICgABAAAAAA==.Xandaï:BAABLAAECoEYAAIKAAgIQxPrHwAGAgAKAAgIQxPrHwAGAgAAAA==.',Xe='Xene:BAAALAAECgYIDQAAAA==.',Xo='Xorthos:BAAALAADCgEIAQAAAA==.',Xp='Xpectrum:BAABLAAECoEVAAILAAcINR8WFABjAgALAAcINR8WFABjAgAAAA==.',Xr='Xrs:BAAALAADCggIDQAAAA==.',Ya='Yanasai:BAAALAADCggICAAAAA==.',Yu='Yukonîcus:BAAALAADCggICgABLAAECgcIDgABAAAAAA==.Yukonïcus:BAAALAAECgcIDgAAAA==.Yurinoryu:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.',Za='Zammorak:BAAALAAECggICQAAAA==.Zarculo:BAAALAAECgEIAQAAAA==.',Ze='Zektrovi:BAAALAAECgcIDQABLAAFFAMIBQAHAEQRAA==.Zelrin:BAAALAAECgYICQAAAA==.',Zi='Zimeko:BAAALAADCgQIBAAAAA==.Zippee:BAAALAAECgMIAwAAAA==.',Zu='Zukran:BAAALAADCgIIAgAAAA==.Zusi:BAAALAAECgQIBwAAAA==.',Zy='Zywie:BAAALAADCgMIAwABLAAECgcIEwABAAAAAA==.',['ßl']='ßluesteel:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end