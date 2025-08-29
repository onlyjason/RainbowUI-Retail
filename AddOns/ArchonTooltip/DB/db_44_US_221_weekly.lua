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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Evoker-Preservation','Warrior-Protection','Monk-Windwalker','Evoker-Devastation','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Rogue-Assassination','Warrior-Arms','Warrior-Fury','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Havoc',}; local provider = {region='US',realm='Thunderlord',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaliyah:BAAALAAECgUIBQAAAA==.',Ab='Abbandonato:BAAALAAECgMIBgAAAA==.',Ac='Acesso:BAAALAAECgIIAgAAAA==.',Ad='Adathorne:BAAALAADCggICAAAAA==.Adralis:BAAALAADCgcIBwAAAA==.',Ae='Aecheron:BAAALAADCggIDwABLAAECgMIBgABAAAAAA==.Aeliniani:BAAALAAECgIIAgAAAA==.Aethise:BAAALAADCgYIBgAAAA==.',Ag='Agronon:BAAALAAECgMIAwAAAA==.',Ai='Air:BAAALAAECgEIAQAAAA==.Aisec:BAAALAADCgcICwAAAA==.',Ak='Akariah:BAAALAADCgMIAwAAAA==.Akayaa:BAAALAAECgMIAwAAAA==.',Al='Alanamus:BAAALAADCgcIBwAAAA==.Alexdruids:BAAALAADCgMIAwAAAA==.Alexhunt:BAABLAAECoEUAAICAAcISCUgBgABAwACAAcISCUgBgABAwAAAA==.Alexwithfur:BAAALAADCgcIBwAAAA==.Alleralle:BAAALAADCggIFgAAAA==.Alleryanna:BAAALAADCggIDwAAAA==.Alplarn:BAAALAAECgQIBAAAAA==.Alregion:BAAALAADCgcIEAAAAA==.',Am='Amaeha:BAAALAADCgMIAwAAAA==.Amconfused:BAAALAADCgUIBQAAAA==.Ammaelanstus:BAAALAADCgcIBwAAAA==.',An='Ancá:BAAALAADCgcIBwAAAA==.Andùrile:BAAALAAECgMIAwAAAA==.Annihilape:BAAALAAECgYICQAAAA==.',Ap='Apollyon:BAAALAADCgYIBgAAAA==.',Ar='Arandiel:BAAALAAECgEIAQAAAA==.Aranina:BAAALAAECgIIAgAAAA==.Arcisse:BAAALAAECgEIAQABLAAECggIGAADALodAA==.Arcone:BAAALAADCggIFgAAAA==.Arcuss:BAAALAAECgYIEAAAAA==.Arestocat:BAAALAADCgMIBQAAAA==.Arimas:BAAALAADCgYICAAAAA==.Arlenric:BAAALAADCgcIBwAAAA==.Arnaga:BAAALAAECgEIAQAAAA==.Arrwyn:BAAALAADCgUIBQABLAAECggIFgAEAGslAA==.Artesian:BAAALAAECgMIAwAAAA==.Aryhm:BAAALAADCggICAAAAA==.',As='Asandi:BAAALAADCgQIBAAAAA==.Asatralth:BAAALAAECgEIAQAAAA==.Ascoobis:BAAALAADCggIEAAAAA==.Ashelynn:BAAALAADCggIEAAAAA==.',At='Atomvoke:BAAALAADCggICAAAAA==.',Au='Autaila:BAAALAAECgMIAwAAAA==.',Av='Avirian:BAAALAAECgMIAwAAAA==.',Ay='Aymine:BAAALAAECgEIAQAAAA==.',Ba='Babylego:BAABLAAECoEWAAIFAAgI6yPrAQAtAwAFAAgI6yPrAQAtAwAAAA==.Badney:BAAALAAECgYICQAAAA==.Badwolff:BAAALAADCggIEAAAAA==.Bahobilat:BAAALAAECgMIAwAAAA==.Balidtotem:BAAALAADCgYIBgAAAA==.Basadito:BAAALAADCgYIBgAAAA==.Bater:BAAALAAECgcIDQAAAA==.Bawana:BAAALAADCgUIBQAAAA==.Baycon:BAAALAAECgUIBwAAAA==.',Be='Beanslol:BAAALAAECgEIAQAAAA==.Bearbella:BAAALAADCgQIBAAAAA==.Beelzaboot:BAAALAAECgcIEAAAAA==.Belanor:BAAALAAECgYIEwAAAA==.Belialoin:BAAALAADCgMIAgAAAA==.Berry:BAAALAAECgcIDAAAAA==.',Bi='Bigbe:BAAALAADCggIEwAAAA==.Bigdamfury:BAAALAADCggIBwAAAA==.Bigdikdaryll:BAAALAADCgMIAwABLAAECggIFgAGAC0fAA==.Bighog:BAAALAADCggICgAAAA==.Biglego:BAAALAADCggICAABLAAECggIFgAFAOsjAA==.Bignipsmcgee:BAAALAADCgcIDAABLAADCgcIDQABAAAAAA==.Bigstepladdr:BAAALAADCgQIBAAAAA==.Bismilahimps:BAAALAADCggICAAAAA==.Bixxnogath:BAAALAAECgEIAgAAAA==.',Bl='Blacktastic:BAAALAAECgIIAwAAAA==.Blastme:BAAALAAECgYIEQAAAA==.',Bo='Bos:BAAALAAECgEIAQAAAA==.Boxaman:BAAALAADCgIIAgAAAA==.',Br='Braynnissa:BAAALAAECgEIAQABLAADCgIIAgABAAAAAA==.Brikhouse:BAAALAADCgYIBgAAAA==.Bronzehoofs:BAAALAAECgEIAgAAAA==.Brutalspirit:BAAALAADCgQIBAAAAA==.',Bu='Bullfrog:BAAALAADCgYIBgAAAA==.Bulvine:BAAALAADCggICAAAAA==.Bunnix:BAAALAAECgMIAwAAAA==.Buttermilkk:BAAALAAECgIIAwAAAA==.',Ca='Cahri:BAAALAADCggICwAAAA==.Camyr:BAAALAAECgEIAQAAAA==.Canon:BAAALAAECgEIAQAAAA==.',Ce='Ceanexia:BAAALAADCgcIDAAAAA==.Celasong:BAAALAADCgcICgAAAA==.Cerburiss:BAAALAAECgYIBgAAAA==.Ceri:BAAALAADCgYIBgABLAAECgUIBgABAAAAAA==.',Ch='Champ:BAAALAAECgYIEgAAAA==.Chaoszhtai:BAAALAAECggICAAAAA==.Chaseglitch:BAAALAAECgQIBAAAAA==.Chatgptbot:BAAALAAECgEIAQAAAA==.Chesty:BAAALAADCgIIAgAAAA==.Chillaiya:BAAALAADCgEIAQAAAA==.Chiwi:BAAALAAECgYICAAAAA==.Chronicmoo:BAAALAAECggICAAAAA==.Chubbsmcgee:BAAALAAECgMIAwAAAA==.',Ci='Ciso:BAAALAADCggIDgAAAA==.',Cl='Clawandordèr:BAAALAADCgcIDQAAAA==.Clearlyshiny:BAAALAADCgcIBwAAAA==.',Co='Cogblock:BAAALAADCggIDwAAAA==.Coleridge:BAAALAADCgMIAgAAAA==.Corviana:BAAALAAECgIIAQAAAA==.Cosmicpally:BAAALAADCggIFwAAAA==.Cosmicshaman:BAAALAADCgIIAgAAAA==.Cowberries:BAAALAADCgYIBgAAAA==.',Cr='Craigory:BAAALAAECgMIBgAAAA==.Crampöarcher:BAAALAADCgYIEgAAAA==.Crazyajax:BAAALAAECgMIAwAAAA==.Crescendoll:BAAALAAECgIIAgAAAA==.Criminul:BAAALAAECggIEAAAAA==.Crozmax:BAAALAAECggIDgAAAA==.Crushesturts:BAAALAAECgUIBgAAAA==.Crushgroove:BAAALAAECgYICQAAAA==.Crxx:BAAALAADCgUICAABLAAECggIDgABAAAAAA==.Cryptosec:BAAALAADCgYIBgAAAA==.Crzylgs:BAAALAADCgIIAgAAAA==.',Ct='Ctenasaurus:BAAALAADCggIEAAAAA==.',Cu='Cursemyshirt:BAAALAADCgUIBQAAAA==.Cutz:BAAALAADCgMIAwAAAA==.',Cy='Cybrochis:BAAALAADCgEIAQAAAA==.Cyndrin:BAAALAAECgcIEAAAAA==.',['Cô']='Cônstantine:BAAALAAECgUIBwAAAA==.',Da='Daemunn:BAAALAADCggICAAAAA==.Daerlith:BAAALAADCgcICQAAAA==.Daerper:BAAALAAECgIIBAAAAA==.Daguvster:BAAALAADCgcICwAAAA==.Damitara:BAAALAAECgYICAAAAA==.Darkaar:BAAALAADCgMIBQAAAA==.Darkbil:BAAALAADCgIIAgAAAA==.Darknite:BAAALAADCgcIDAAAAA==.Darksign:BAAALAADCggICAAAAA==.Darthiono:BAAALAAECgYICQAAAA==.Dasarran:BAAALAAECgQIBQAAAA==.Davemage:BAAALAADCgcIEAAAAA==.Dayzend:BAAALAADCgcIBwAAAA==.',De='Dealanach:BAAALAAECgIIAgAAAA==.Deathmite:BAAALAAECgUICgAAAA==.Defdh:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.Defilers:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.Deiene:BAAALAADCgYICQAAAA==.Deliada:BAAALAADCgEIAQAAAA==.Delillama:BAAALAAECgQIBQAAAA==.Demolior:BAAALAADCgcIDgAAAA==.Demonzong:BAAALAADCgcIBwAAAA==.Denzite:BAAALAAECgIIAgAAAA==.Derfla:BAAALAADCggICQAAAA==.',Di='Dillpo:BAAALAAECgIIAgAAAA==.Dimetri:BAAALAAECgIIAgAAAA==.Dis:BAABLAAECoEXAAQHAAgIFCXEAgB2AgAIAAgITSK3BwDTAgAHAAYIHyPEAgB2AgAJAAUIWhYcGgA9AQAAAA==.Diyånna:BAAALAAECgIIAgAAAA==.',Dj='Djrogue:BAAALAADCggICAAAAA==.',Do='Donmazza:BAAALAADCgUIBQAAAA==.Dorae:BAAALAAECgEIAQAAAA==.Doughbeam:BAABLAAECoEVAAMIAAgIex8QCQC8AgAIAAgIPB8QCQC8AgAJAAYIlRN8GQBBAQAAAA==.',Dr='Draennie:BAAALAAECgEIAQAAAA==.Dragobuster:BAAALAADCgcIBwAAAA==.Dragon:BAAALAAECggIEwAAAA==.Dragonbender:BAAALAADCgcIDAAAAA==.Dread:BAAALAAECgIIAgAAAA==.Drogi:BAAALAADCgcIDgAAAA==.Drpiranha:BAAALAAECgcIEQAAAA==.Druidllama:BAAALAAECgEIAQAAAA==.Druidofthetp:BAAALAADCggICAABLAAECgIIBQABAAAAAA==.Drxvo:BAAALAAECgIIAQAAAA==.',Du='Dulcenini:BAAALAAECgEIAQAAAA==.Durdaicww:BAAALAADCgIIAgAAAA==.',Dw='Dwarvanhand:BAABLAAECoEWAAIKAAgIpSAkBADzAgAKAAgIpSAkBADzAgAAAA==.',Dy='Dysscordia:BAAALAADCggIIAAAAA==.',Dz='Dz:BAAALAADCgYIBgAAAA==.',Ea='Earthrender:BAAALAAECgMIBAAAAA==.',Eb='Ebbur:BAAALAADCggIDwAAAA==.Ebrawr:BAAALAADCgcICAAAAA==.',Ei='Eiwa:BAAALAADCgMIAwAAAA==.',El='Eldari:BAAALAAECgEIAQAAAA==.Elemenope:BAAALAADCgcIBwAAAA==.Elementos:BAAALAADCgcIBwAAAA==.Elidori:BAABLAAECoEWAAILAAgIGyJrBAD7AgALAAgIGyJrBAD7AgAAAA==.Elishammy:BAAALAADCgcICgAAAA==.Elitegamerx:BAAALAADCggIEAAAAA==.Elmerfuudd:BAAALAADCgYIBgAAAA==.Elzaria:BAAALAAECgEIAQAAAA==.',Em='Emnight:BAAALAAECgYIDwAAAA==.',En='Enyeto:BAAALAAECgYIDAAAAA==.',Er='Erdort:BAAALAADCgQIBAAAAA==.Erobor:BAAALAAECgEIAQAAAA==.',Es='Espiridus:BAAALAADCgMIAwAAAA==.',Ev='Everybody:BAAALAAECgEIAQAAAA==.',Ex='Exiledlight:BAAALAADCgYIBgAAAA==.',Ez='Ezekielsix:BAAALAAECgEIAQAAAA==.',Fe='Feelsright:BAAALAADCggICAAAAA==.Felgazelle:BAAALAADCgYIBgAAAA==.Felshaman:BAAALAADCgQIBAABLAADCggIDgABAAAAAA==.',Fi='Fisty:BAAALAADCgIIAgAAAA==.Fiveshot:BAAALAADCgcIDQABLAADCggIEAABAAAAAA==.',Fl='Flamefenix:BAAALAAECgMIBAAAAA==.Flasky:BAAALAAECgMIBAABLAAECgQIBAABAAAAAA==.Flintfire:BAAALAADCgIIAgAAAA==.Florabella:BAAALAAECgcIDQAAAA==.',Fo='Foodtruck:BAAALAAECgQIBAAAAA==.Forester:BAAALAADCgcICgAAAA==.Foxikins:BAAALAAECgUIBgAAAA==.Foxyldy:BAAALAAECgIIAgAAAA==.',Fr='Fraeyaa:BAAALAADCgEIAQAAAA==.Frozenwater:BAAALAADCgEIAQAAAA==.',Fu='Fubar:BAAALAADCgcIBwAAAA==.Furidas:BAAALAAECgMIAwAAAA==.',Fx='Fxnrirarc:BAAALAADCgQIBAAAAA==.',Fy='Fysteryfluid:BAAALAAFFAIIAgAAAA==.',['Fö']='Föxfïre:BAAALAADCgMIAwAAAA==.',Ga='Galanarth:BAAALAAECgYIBwAAAA==.Garakni:BAAALAADCgIIAgAAAA==.Garogg:BAAALAAECgMIAwAAAA==.Gartzarn:BAAALAADCgcICAAAAA==.Gaulbatorix:BAAALAADCgEIAQAAAA==.',Ge='Gelin:BAAALAAECgQIBQAAAA==.Geridian:BAAALAADCgQIBAAAAA==.Gettilted:BAAALAAECggIBgAAAA==.',Gi='Giirthquakee:BAAALAADCgQIBAABLAADCgcIDQABAAAAAA==.Girthbrookss:BAAALAADCgcIDQAAAA==.',Gl='Glorbruid:BAAALAADCggICAAAAA==.',Gn='Gnkngrceries:BAAALAAECgUIBgAAAA==.',Go='Gooeylouie:BAAALAAECgMIAwABLAAECgcIDQABAAAAAA==.Goonahr:BAAALAADCgcIBwABLAAECgQIBQABAAAAAA==.Gorblo:BAAALAAECgEIAQAAAA==.Gorgibite:BAAALAAECgcICgAAAA==.Gorgismaug:BAAALAAFFAEIAQAAAA==.Gotcowbell:BAAALAAECgQIBAAAAA==.',Gr='Greenfart:BAAALAAECgYICAAAAA==.Greenperor:BAAALAAECgEIAQAAAA==.Grenvar:BAAALAAECgcIEwAAAA==.Griffey:BAAALAAECgYIBgAAAA==.Grigdor:BAAALAAECgcIEgAAAA==.Griplord:BAAALAADCgUIBQAAAA==.Gruko:BAAALAADCggICgAAAA==.Gruusha:BAABLAAECoETAAMMAAcIRh8EBAD6AQAMAAcIuBoEBAD6AQANAAUI6RnlJgB5AQAAAA==.Grynchyn:BAAALAAECgcIEAAAAA==.Gràcias:BAAALAAECgMIAwAAAA==.',Gu='Guass:BAAALAAECggIEwAAAA==.Guhflerkin:BAAALAADCggICQAAAA==.Gullibull:BAAALAADCgcICQAAAA==.Gunrites:BAAALAAECgEIAQAAAA==.',Gw='Gwinever:BAAALAAECgcIDgAAAA==.',['Gö']='Göbstöpper:BAAALAADCggIEAAAAA==.',Ha='Hadish:BAAALAADCggIEQAAAA==.Hamilton:BAAALAADCgYICQAAAA==.Hannibul:BAAALAAECgYICAAAAA==.Hansvonbeck:BAAALAADCggIEAAAAA==.Hatebreeding:BAAALAAECgMIAwAAAA==.Hazesamaa:BAAALAAECgYICAAAAA==.',He='Healsforfree:BAAALAADCgYIBgAAAA==.Healsu:BAAALAAECgEIAQAAAA==.Hectatee:BAAALAADCgcICQAAAA==.Henrick:BAAALAAECgIIAgAAAA==.Heruss:BAAALAAECgIIAgAAAA==.Hexmenixy:BAAALAADCggIDgAAAA==.',Ho='Hodoran:BAAALAADCggIDgAAAA==.Holybox:BAAALAAECgUIBQAAAA==.Holyfilers:BAAALAAECgIIAgAAAA==.Holyhal:BAAALAAECgEIAQAAAA==.Holynixy:BAAALAAECgUIBgAAAA==.Holyunicorn:BAAALAADCgQIBQAAAA==.Horator:BAAALAAECgEIAQAAAA==.Hordak:BAAALAADCggIDwAAAA==.Hordelportal:BAAALAADCgUIBQAAAA==.Hotstuffbaby:BAAALAADCgMIAwAAAA==.House:BAAALAADCgUIBQAAAA==.Howdi:BAAALAAECgYIDwAAAA==.Howitsir:BAAALAADCgEIAQAAAA==.',Hu='Hurkgurkin:BAAALAADCgUIBQAAAA==.',Hy='Hybridkaidou:BAAALAADCgUIBQAAAA==.Hypd:BAABLAAECoEUAAMOAAgIPyIDAgAFAwAOAAgIPyIDAgAFAwAPAAIIewTQRQBFAAAAAA==.Hypm:BAAALAADCgYIBgABLAAECggIFAAOAD8iAA==.Hyps:BAAALAAECgYIEgABLAAECggIFAAOAD8iAA==.Hypt:BAAALAAECgUICAABLAAECggIFAAOAD8iAA==.',['Hä']='Hätredcopter:BAAALAADCgEIAQAAAA==.',Ib='Ibichi:BAAALAAECgEIAgAAAA==.Ibowla:BAAALAADCgUIBQAAAA==.',Ig='Iggar:BAAALAAECgMIBQAAAA==.',Il='Illshankya:BAAALAADCgcIDQAAAA==.',In='Ineedthat:BAAALAADCggIFgABLAAECgcIEwAMAEYfAA==.Insidio:BAAALAADCgcIDAAAAA==.Instantdeath:BAAALAAECgYICwAAAA==.Invìctús:BAAALAAECgYICgAAAA==.',It='Itscdonkick:BAAALAADCgMIAwAAAA==.',Iz='Izume:BAAALAAECgcIDgAAAA==.',Ja='Jackodes:BAAALAAECgIIAgAAAA==.Jambonnes:BAAALAADCgQIBAAAAA==.Jariu:BAAALAADCgUICAAAAA==.Jawo:BAAALAAECgIIAgAAAA==.',Je='Jesca:BAAALAAECgEIAQAAAA==.',Ji='Jinji:BAAALAADCggIEAAAAA==.',Jp='Jp:BAABLAAECoEbAAIQAAgI2yYQAACbAwAQAAgI2yYQAACbAwAAAA==.',Jx='Jx:BAAALAADCgYIBgAAAA==.',Ka='Kaevthas:BAAALAADCgcIDQAAAA==.Kagren:BAAALAAECgEIAQAAAA==.Kalilock:BAAALAADCggIGwAAAA==.Kallib:BAAALAAECgYIDAAAAA==.Kalorian:BAAALAADCgMIAQAAAA==.Kamode:BAAALAADCgIIAgAAAA==.Kamwar:BAAALAAFFAIIAgAAAA==.Karswell:BAAALAADCgcICQAAAA==.Kasamir:BAAALAADCggICAAAAA==.Kasumitiki:BAAALAADCgcICAAAAA==.Kaylax:BAAALAADCggIFwAAAA==.Kaylost:BAAALAADCgUICAAAAA==.',Ke='Keatonos:BAAALAADCgYIBgAAAA==.Kegsmash:BAAALAAECgQIBQAAAA==.Kerash:BAAALAADCgUIBQAAAA==.Kevinsm:BAAALAADCgYIBgAAAA==.Kevintt:BAAALAAECgYIEgAAAA==.',Kh='Khaliope:BAAALAAECgIIAwAAAA==.',Ki='Killerhunter:BAAALAADCgQIBQAAAA==.Killero:BAAALAADCggIGQAAAA==.Killianred:BAAALAADCgEIAQAAAA==.',Kl='Kleine:BAAALAADCgcIFQAAAA==.',Kn='Knugget:BAAALAAECgYIBwAAAA==.',Ko='Kolapsa:BAAALAADCggICAAAAA==.Kordessa:BAAALAAECgMIBAAAAA==.Korgigammi:BAABLAAECoEUAAIQAAgIwxt1BQCBAgAQAAgIwxt1BQCBAgAAAA==.Korgigammii:BAAALAAECgMIAwABLAAECggIFAAQAMMbAA==.',Kr='Kracky:BAAALAAECgMIAwAAAA==.Kryo:BAAALAADCggICAABLAAECggIDgABAAAAAA==.Kryopain:BAAALAAECggIDgAAAA==.',Ku='Kugot:BAAALAADCggICAAAAA==.Kuumarr:BAAALAAECgYICQAAAA==.Kuumàrr:BAAALAAECgMIBgABLAAECgYICQABAAAAAA==.',Ky='Kydrea:BAAALAADCggIFgAAAA==.Kylle:BAAALAADCgcIBwABLAADCggIFgABAAAAAA==.Kyne:BAAALAADCgcIBwAAAA==.',['Kú']='Kúsúri:BAAALAAECgcIEQAAAA==.',La='Larien:BAAALAAECgMIAwAAAA==.Larkos:BAAALAADCgMIAwAAAA==.Lashawnda:BAAALAAECgcIDAAAAA==.',Le='Leatherkink:BAAALAAECgcIEAAAAA==.Leechygos:BAAALAAECgEIAQAAAA==.Leonz:BAAALAAECgMIAwAAAA==.Lethedemon:BAAALAAECgMIAwAAAA==.Levas:BAAALAADCgcIBwAAAA==.Lexinight:BAAALAADCggIFwAAAA==.',Li='Lichthrall:BAAALAAECgEIAQAAAA==.Lilet:BAAALAAECgYIDAAAAA==.Lilitsune:BAAALAADCgcIBwAAAA==.Lisri:BAAALAAECgQIBQAAAA==.Lizolio:BAAALAADCgYIDgAAAA==.',Ll='Llomelwigh:BAAALAAECgIIAwAAAA==.',Lo='Lockadamtp:BAAALAAECgIIBQAAAA==.Locturnal:BAAALAADCgYIBQAAAA==.Loriannis:BAAALAADCgEIAQAAAA==.Lornix:BAAALAAECgEIAQAAAA==.',Ma='Machi:BAAALAAECgMIBgAAAA==.Magdelene:BAAALAADCgcIBgAAAA==.Mageunal:BAAALAADCgIIAgAAAA==.Magikkosa:BAAALAAECgYICQAAAA==.Maginature:BAAALAADCgMIAwAAAA==.Malefic:BAAALAADCgcIBwAAAA==.Malnourished:BAAALAADCggICAAAAA==.Manchufu:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.Marchpally:BAAALAADCgcIFAAAAA==.Mariza:BAAALAADCgQIBAAAAA==.Masikå:BAAALAADCgcIDQAAAA==.Maybeafurry:BAAALAAECgEIAQAAAA==.Mazzy:BAAALAADCgYICAAAAA==.',Mc='Mclùven:BAAALAAECgYIBgAAAA==.',Me='Meatcreature:BAAALAADCggICwAAAA==.Meathole:BAAALAADCgIIAgABLAAECggIFwARAAgeAA==.Medali:BAAALAAECgMIBQAAAA==.Meldyn:BAAALAADCggICAAAAA==.Melmei:BAAALAAECgIIAgAAAA==.Meriweather:BAAALAAECgIIAgAAAA==.Meszyra:BAABLAAECoEWAAIGAAgItiEkBQDrAgAGAAgItiEkBQDrAgAAAA==.',Mi='Microcosm:BAAALAADCgMIAwAAAA==.Misofurious:BAAALAAECgIIAgAAAA==.Mixelplix:BAAALAAECgMIAwAAAA==.',Mo='Momenjoyer:BAAALAADCggICAAAAA==.Monkyato:BAAALAAECgQIBQAAAA==.Monthlyvex:BAAALAAECgMIAwAAAA==.Moonclaw:BAAALAADCgcIDgAAAA==.Mordath:BAAALAAECgMIBQAAAA==.Mordetkai:BAAALAADCggIDAAAAA==.Mordoom:BAAALAAECgMIBgAAAA==.Mordrayn:BAAALAADCggIDgAAAA==.Morganlefae:BAAALAAECgYIBwAAAA==.Morikai:BAAALAADCggIDgAAAA==.Moushou:BAAALAAECgcIDQAAAA==.',Ms='Mspacman:BAAALAAECgUIBgAAAA==.',Mu='Muehlastrasz:BAAALAADCggIGwAAAA==.Muggle:BAAALAADCgMIAwAAAA==.',My='Mycowss:BAAALAADCgMIAwAAAA==.Myrrha:BAAALAAECgcIDwAAAA==.',['Mä']='Mälaria:BAAALAADCgMIAwAAAA==.',['Mô']='Mônah:BAAALAADCggIDwAAAA==.',['Mö']='Möon:BAAALAADCgcIBwAAAA==.',Na='Nachtritter:BAAALAAECgUICQAAAA==.Nameredacted:BAAALAAECgIIAwAAAA==.Natalienunn:BAAALAADCgEIAQAAAA==.',Ne='Neofarus:BAAALAADCgIIAgAAAA==.',Ni='Ninn:BAAALAADCggICAAAAA==.Nitewang:BAABLAAECoEWAAIEAAgIayXOAABkAwAEAAgIayXOAABkAwAAAA==.Nitewing:BAAALAADCgcIDgABLAAECggIFgAEAGslAA==.',Nj='Njall:BAAALAADCgEIAQAAAA==.',No='Nocs:BAAALAADCgcIDAAAAA==.Nocturnia:BAAALAAECgUICQAAAA==.Nofeasts:BAAALAADCggICgABLAAECgMIAwABAAAAAA==.Nogra:BAAALAADCggIFAAAAA==.Noktand:BAAALAADCgYIBwAAAA==.',Ny='Nysa:BAAALAAECgQIBgAAAA==.',Ob='Obnixa:BAAALAAECgQIBQAAAA==.Obrox:BAAALAAECgIIAgAAAA==.',On='Onryo:BAAALAADCgMIAwAAAA==.',Oo='Ooghatsu:BAAALAAECgUIBwAAAA==.',Op='Opierus:BAAALAAECgIIBAABLAAECgcIDQABAAAAAA==.Opigon:BAAALAAECgcIDQAAAA==.Oppalina:BAAALAADCggIFgAAAA==.',Os='Ostjo:BAAALAAECgEIAQAAAA==.',Oy='Oyogo:BAAALAAECgUIBQAAAA==.Oyumi:BAAALAADCgEIAQABLAAECgUIBQABAAAAAA==.',Pa='Pachaia:BAAALAADCgYIBgAAAA==.Paech:BAAALAADCgcIBwAAAA==.Paladingo:BAAALAADCggIDgABLAAECgcIDwABAAAAAA==.Pasam:BAAALAADCgUIBgAAAA==.',Pe='Peedmypants:BAAALAAECgYICQAAAA==.Pelandris:BAAALAADCgEIAQAAAA==.Penetron:BAAALAAECgYICgAAAA==.Penoy:BAAALAADCggICwAAAA==.Peperoll:BAAALAADCggICAAAAA==.Pepetuff:BAAALAAECggIEwAAAA==.Petflixñkill:BAAALAADCgUIBQAAAA==.',Ph='Phantomlord:BAAALAADCgYIBgAAAA==.Phephraan:BAAALAAECgQIBQAAAA==.Phocough:BAAALAADCgYIBgABLAAFFAIIAgABAAAAAA==.Phoenixmagi:BAAALAAECgYICgAAAA==.Phwaz:BAAALAAECgIIAgAAAA==.',Pi='Pinktress:BAAALAAECgQIBAAAAA==.Pixxle:BAAALAADCgYIBgAAAA==.Pizzadough:BAAALAADCgYIBgABLAAECggIFQAIAHsfAA==.Pizzapurse:BAAALAADCgcIDAAAAA==.',Pl='Plskillmie:BAAALAADCgcIBwAAAA==.',Po='Poppasyn:BAAALAADCgEIAQAAAA==.Possecutor:BAAALAAECggIEwAAAA==.Posseslayer:BAAALAADCggICAABLAAECggIEwABAAAAAA==.',Pr='Priestachio:BAAALAADCggIFAAAAA==.',Ps='Psylôcybyn:BAAALAAECgEIAQAAAA==.',Pu='Pulladin:BAAALAADCgQIBAAAAA==.Pumachaka:BAAALAADCgYIBAAAAA==.Pumpkinspice:BAAALAADCggICgAAAA==.Pureogs:BAAALAADCggICQAAAA==.Purk:BAAALAADCgIIAgAAAA==.Pushstick:BAAALAAECgUICAAAAA==.',Pv='Pvp:BAAALAADCgYIBgAAAA==.Pvtjokr:BAABLAAECoEXAAIRAAgICB7ZBwClAgARAAgICB7ZBwClAgAAAA==.',Py='Pyrcella:BAAALAADCgMIAwAAAA==.',Qu='Quelkatina:BAAALAADCgYIBgABLAAECgcIEwAMAEYfAA==.',Qw='Qwertysquid:BAAALAADCgcIBwAAAA==.',Ra='Raeven:BAAALAADCgcIBwAAAA==.Raiin:BAAALAADCggIEAAAAA==.Rathrus:BAAALAAECgMIAwAAAA==.Raxmanus:BAAALAAECgUIBgAAAA==.Rayna:BAAALAADCggICAAAAA==.Razath:BAAALAADCggIDwABLAAECgcIEwAMAEYfAA==.Raziks:BAAALAADCggIFAAAAA==.',Re='Reapblood:BAAALAAECgcICgAAAA==.Redestro:BAAALAADCggICAABLAAECgUICgABAAAAAA==.Rednuth:BAAALAADCggICAAAAA==.Reilini:BAAALAAECggIDAAAAA==.Remedradys:BAAALAAECgMIBAABLAAECgcIEAABAAAAAA==.Renascor:BAAALAADCggIDwAAAA==.Repöman:BAAALAAECgEIAQAAAA==.Restrainless:BAAALAAECgMIBAAAAA==.Restrainsham:BAAALAADCggICAAAAA==.Reydar:BAAALAAECgEIAQAAAA==.',Ri='Rickiebear:BAAALAADCggIEgAAAA==.Riksanchez:BAAALAADCggICAAAAA==.',Ro='Roachnout:BAAALAADCgYIBgAAAA==.Roachout:BAAALAADCgUIBQABLAADCgYIBgABAAAAAA==.Roboice:BAAALAADCgEIAQAAAA==.Ronhin:BAAALAAECgIIAgAAAA==.Rosael:BAAALAADCgMICAAAAA==.Rouñders:BAAALAAECgIIAgAAAA==.',Rs='Rsthrea:BAAALAADCgcICgAAAA==.',Ru='Ruforreal:BAAALAADCgYIBgAAAA==.Ruhan:BAAALAAECgMICAAAAA==.Rumpl:BAAALAAECgEIAQAAAA==.',Ry='Ryzor:BAAALAADCggIEQABLAAECgcIEwAMAEYfAA==.',['Ré']='Réka:BAAALAAECgMIBAAAAA==.',Sa='Saltpepper:BAAALAADCggIEAAAAA==.Samlock:BAABLAAECoEYAAIIAAcIiRcRGwDdAQAIAAcIiRcRGwDdAQAAAA==.Sammette:BAAALAADCggIFQAAAA==.Saphiraa:BAAALAAECgQIBgAAAA==.Satyrlord:BAAALAAECgYICQAAAA==.Savella:BAAALAAECgYIBwAAAA==.',Sc='Scaleyhope:BAAALAADCgMIAwAAAA==.Scarletblade:BAAALAAECgUIBQAAAA==.Schamwoww:BAAALAAECgEIAQAAAA==.Sclas:BAAALAADCgIIAgAAAA==.Scubar:BAAALAAECgIIAgAAAA==.Scyla:BAAALAAECgIIAgAAAA==.Scyllabus:BAAALAAECgEIAQAAAA==.',Se='Seafox:BAAALAAECgEIAQAAAA==.Sebak:BAAALAADCggICAAAAA==.Selarius:BAAALAADCgcIBwAAAA==.Selleck:BAAALAAECgcIEQAAAA==.Seraphiina:BAAALAADCgcIDQAAAA==.Serenity:BAAALAADCgYIBgAAAA==.',Sf='Sfx:BAAALAAECgMIAwAAAA==.',Sh='Shadowbinder:BAAALAADCgEIAQAAAA==.Shadowbrynne:BAAALAAECgYICgAAAA==.Shadowpope:BAAALAADCgEIAQAAAA==.Shandwhich:BAAALAADCgUIBQAAAA==.Sharatsec:BAAALAADCgUIBQAAAA==.Shataree:BAAALAADCgYICwAAAA==.Shaycena:BAAALAADCgcIBwAAAA==.Shazno:BAAALAADCgYIBgAAAA==.Shestank:BAAALAADCgIIAgAAAA==.Shockerfist:BAAALAAECgcIEAAAAA==.Shockujin:BAAALAAECgcIDAAAAA==.Shoze:BAAALAADCgcICQAAAA==.Shweba:BAAALAAECgIIAgAAAA==.Shámánism:BAAALAADCgEIAQAAAA==.',Si='Silanris:BAAALAADCggICAAAAA==.Sippa:BAAALAAECgYICgAAAA==.Situna:BAAALAAECgIIAgAAAA==.',Sk='Skairipa:BAAALAAECgYICAAAAA==.Skimshh:BAAALAADCggICgAAAA==.',Sl='Slarti:BAAALAADCgIIAgAAAA==.Sleepinndh:BAAALAADCgUIBQAAAA==.Slojam:BAAALAAECgYIDQAAAA==.Sloth:BAAALAAECgYIDAAAAA==.Slowcase:BAAALAADCgYIBgAAAA==.Slÿ:BAAALAADCggICwAAAA==.',Sn='Sneaksmgoo:BAAALAADCgcIBwAAAA==.',So='Socketss:BAAALAADCgcIBwAAAA==.Solindre:BAAALAADCgIIAgAAAA==.Sollanis:BAAALAADCgMIAwAAAA==.',Sp='Spooppy:BAAALAAECgYICAAAAA==.',Sq='Squatcase:BAAALAAECgQIBAAAAA==.Squeekstoy:BAAALAADCgcICgAAAA==.',St='Staggsette:BAAALAADCggICQAAAA==.Staheekum:BAAALAAECgIIAgAAAA==.Stealthfire:BAAALAAECgIIBAAAAA==.Stichy:BAAALAADCggIDAAAAA==.Stormstrikes:BAAALAAECgEIAQAAAA==.Strwbyfrosty:BAAALAAECgQIBAAAAA==.Stterny:BAAALAADCgQIBAAAAA==.',Su='Sukunà:BAAALAADCgYIBwAAAA==.Summwun:BAAALAADCggIEAAAAA==.Superace:BAABLAAECoEVAAISAAgIiB7PCADKAgASAAgIiB7PCADKAgAAAA==.',Sw='Swiftys:BAAALAAECgIIAwAAAA==.',Sy='Synkareaper:BAAALAADCgYIBgAAAA==.Synkaweeds:BAAALAADCgcIHgAAAA==.Syssareith:BAAALAADCgUIBQAAAA==.',Ta='Tabbathejutt:BAAALAADCgUICAAAAA==.Tacostuffing:BAAALAAECgMIBQAAAA==.Taids:BAABLAAECoEWAAIGAAgILR9QBwC2AgAGAAgILR9QBwC2AgAAAA==.Tail:BAAALAAECgEIAgAAAA==.Talyethe:BAAALAADCggIAwAAAA==.Tanmand:BAAALAADCggIDwAAAA==.Tanthus:BAAALAAECgYIBgAAAA==.Tastybeef:BAAALAAECgMIBAABLAAECgcIDwABAAAAAA==.Tatchi:BAAALAAFFAEIAQAAAA==.',Te='Teddymouse:BAAALAAECgEIAQAAAA==.Telasmir:BAAALAADCgMIAwAAAA==.Terranin:BAAALAADCgEIAQAAAA==.Texmonk:BAAALAAECgcIDwAAAA==.',Th='Thebohemian:BAAALAADCggIDwAAAA==.Thebutler:BAAALAADCgcIDQAAAA==.Thecowkiing:BAAALAAECgUIBQAAAA==.Thehuntard:BAAALAADCgcIDgAAAA==.Thekeres:BAAALAADCgcICAAAAA==.Themm:BAAALAADCgEIAgAAAA==.Thiçç:BAAALAADCgMIAgAAAA==.Thongers:BAAALAADCgcIDAAAAA==.Thoreden:BAAALAADCggICgAAAA==.Thrillgage:BAAALAADCggIFgAAAA==.Thulu:BAAALAADCggIDAAAAA==.Thunrage:BAAALAADCggICAABLAAECgQIBQABAAAAAA==.',Ti='Tiget:BAAALAADCgcIFAAAAA==.Tigoldbittys:BAAALAADCgYIBgAAAA==.',To='Tokaido:BAAALAADCggICgAAAA==.Tokeyes:BAAALAAECgQIBQAAAA==.Tolt:BAAALAADCgYIBgAAAA==.Tomshelby:BAAALAAECggICAAAAA==.Toospooky:BAAALAADCgUIBQAAAA==.Toxiicmage:BAAALAADCgcIBwAAAA==.',Tr='Trakshot:BAAALAADCgYIBQABLAAFFAIIAgABAAAAAA==.Treecthaeh:BAAALAAECgEIAQAAAA==.Triva:BAAALAADCggIBwAAAA==.',Ts='Tservo:BAAALAAECgEIAQAAAA==.',Tu='Tuturu:BAAALAADCggICAAAAA==.Tuuluubu:BAAALAADCgUIBQAAAA==.',Tw='Twirlys:BAAALAADCggIDgAAAA==.',Ty='Tyinarth:BAAALAADCgUIBQAAAA==.Tylenoller:BAAALAAECgMIAwABLAAECgQIBAABAAAAAA==.Typhal:BAAALAAECgYIDgAAAA==.Tyrandee:BAAALAADCgUIBQAAAA==.',Uh='Uhtan:BAAALAAECgUIBgAAAA==.',Un='Undoug:BAAALAADCggICAAAAA==.Ungee:BAAALAADCggICgAAAA==.Unikorn:BAAALAADCgQIBAAAAA==.Unreelistic:BAAALAADCgIIAgAAAA==.Untapped:BAAALAADCgcIBwAAAA==.',Up='Uplink:BAAALAADCggIEQAAAA==.Upsyndrome:BAAALAAECgYICwAAAA==.',Ur='Urmoove:BAAALAADCgcICwAAAA==.',Us='Ushiamdi:BAAALAAECgcIEQAAAA==.',Va='Vanci:BAAALAAECgYICwAAAA==.',Ve='Verissimus:BAAALAAECgYICgAAAA==.Veroon:BAAALAADCgEIAQAAAA==.Veroshia:BAAALAAECgEIAgAAAA==.Vesal:BAAALAADCgcIDQAAAA==.Vexthorne:BAAALAAECgUIBgAAAA==.',Vi='Vihablav:BAAALAADCgcIBwAAAA==.Virali:BAAALAAECgYICQAAAA==.Vispper:BAAALAAECgYICQAAAA==.Vixenvalk:BAAALAADCgUICAAAAA==.',Vo='Vociva:BAAALAAECgYICAAAAA==.Voidedstarz:BAAALAADCggICAAAAA==.Voidfister:BAAALAAECgEIAQAAAA==.Voodooshock:BAAALAAECgEIAQAAAA==.',Vr='Vriknort:BAABLAAECoETAAINAAYINBDsJQCCAQANAAYINBDsJQCCAQAAAA==.',Vu='Vuthar:BAAALAADCggICAAAAA==.',['Vö']='Völk:BAAALAADCggIEgAAAA==.',['Vü']='Vülpix:BAAALAADCgUIBwAAAA==.',Wa='Walaje:BAAALAADCggICAAAAA==.Wallapriest:BAAALAADCggIEQAAAA==.Wataruph:BAAALAADCgUIBQAAAA==.',We='Weebscum:BAAALAADCgUICAAAAA==.Wendysfan:BAAALAAECgMIAwABLAAECgQIBAABAAAAAA==.Wereturtle:BAAALAADCgYIBgAAAA==.',Wh='Whynotlock:BAAALAADCgYIBwAAAA==.',Wi='Wigrix:BAAALAADCgIIAgAAAA==.Willowblessu:BAAALAAECgEIAgAAAA==.Willòw:BAAALAADCgcICgAAAA==.Wishofloki:BAAALAAECgEIAQAAAA==.',Wo='Wolfpriest:BAAALAADCgEIAQAAAA==.Wolty:BAAALAADCggIDQAAAA==.Word:BAAALAAECgIIAgAAAA==.',Wr='Wrayvin:BAAALAADCgcIDgAAAA==.',Xa='Xalgage:BAAALAADCgcIEgAAAA==.Xalgor:BAAALAADCgEIAQAAAA==.Xannastia:BAAALAADCgYIBgAAAA==.Xanthes:BAAALAADCgYICgAAAA==.',Xe='Xemnas:BAAALAAECgMIAwAAAA==.',Xi='Xiidra:BAAALAAECgIIAgABLAAECgcIEAABAAAAAA==.',Xx='Xxcronosxxpr:BAAALAADCgEIAQAAAA==.',Xy='Xyebane:BAAALAAECgEIAQAAAA==.',['Xá']='Xándric:BAAALAAECgQIBAAAAA==.',Ya='Yaani:BAAALAADCgMIAQAAAA==.Yamaiko:BAACLAAFFIEFAAITAAII8R58BQDEAAATAAII8R58BQDEAAAsAAQKgRgAAhMACAhiHpoMAL8CABMACAhiHpoMAL8CAAAA.Yanshira:BAAALAADCgcIBwAAAA==.',Yo='Yokuz:BAAALAAECgIIAgABLAAECgcIDAABAAAAAA==.',Yu='Yurdond:BAAALAAECgEIAgAAAA==.',Za='Zaiquel:BAAALAAECgMIAwAAAA==.Zaivama:BAAALAADCgcIBwAAAA==.Zalith:BAAALAADCgMIAwAAAA==.Zaliya:BAAALAAECggICAAAAA==.Zandren:BAAALAADCgcIBwAAAA==.Zaoshanghao:BAAALAAECgIIAgAAAA==.',Ze='Zeathas:BAAALAAECgQIBgAAAA==.Zeenalizard:BAAALAADCgEIAQABLAAECgQIBAABAAAAAA==.',Zi='Zigwalla:BAAALAADCgcICwAAAA==.',Zo='Zoot:BAAALAADCgIIAgAAAA==.',Zu='Zuess:BAAALAAECgIIAgAAAA==.',Zy='Zyga:BAAALAAECgIIAgAAAA==.Zyzyy:BAAALAADCgMIBAAAAA==.',['Çr']='Çrimes:BAAALAAECggIAwAAAA==.',['Çu']='Çutty:BAAALAADCggIDQAAAA==.',['Ði']='Ðisforðemonz:BAAALAADCgYIDAAAAA==.',['Ðo']='Ðom:BAAALAAECgYICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end