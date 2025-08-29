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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Monk-Mistweaver','DeathKnight-Frost','Hunter-Marksmanship','Priest-Discipline','Priest-Holy','Mage-Arcane','Mage-Fire','Druid-Restoration','Paladin-Retribution','Paladin-Protection','DemonHunter-Vengeance','Warlock-Affliction','Warlock-Destruction','DeathKnight-Unholy','Hunter-Survival','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Hunter-BeastMastery','Warrior-Fury','Warrior-Protection',}; local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aatw:BAAALAADCggIBwAAAA==.',Ab='Abacabb:BAAALAAECgYIDAAAAA==.Abharrug:BAAALAAECgIIAgAAAA==.',Ad='Adondias:BAAALAAECgYICQAAAA==.',Ae='Aelanthus:BAAALAADCgUIBQAAAA==.',Ag='Agrevail:BAAALAADCggICAAAAA==.',Ai='Aidendk:BAAALAAECgcIDQAAAA==.',Ak='Akryllic:BAAALAAECgYICwAAAA==.',Al='Aldari:BAAALAAECgYIAwAAAA==.Aleynreiel:BAAALAAECgQIBwAAAA==.Allydk:BAAALAAECgYIDwAAAA==.Altrag:BAAALAAECgcIEAAAAA==.Aluc:BAAALAAECgYICQAAAA==.',An='Anslayer:BAAALAADCggIDQAAAA==.Antidotum:BAAALAADCgYIBgAAAA==.',Ar='Arctodus:BAAALAAECgQIBgAAAA==.Arêmis:BAAALAADCggIFQAAAA==.',At='Attack:BAAALAAECgMIAwAAAA==.',Ay='Ayrmag:BAAALAAECgYIDAAAAA==.',['Aë']='Aëlana:BAAALAAECgYICQAAAA==.',Ba='Babancho:BAAALAAECgIIAgAAAA==.Baconn:BAAALAAECgcIDQAAAA==.Baymar:BAAALAADCgIIAgAAAA==.',Be='Beauregarde:BAAALAAECgIIAgAAAA==.Beefstew:BAAALAAECgYICAAAAA==.Belerion:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Berzink:BAAALAADCgcICgAAAA==.',Bi='Bigtot:BAAALAAECgEIAQAAAA==.Bij:BAAALAAECgYICQAAAA==.Bishop:BAACLAAFFIEFAAICAAMIYB/hAQAoAQACAAMIYB/hAQAoAQAsAAQKgRgAAgIACAj4JUYBAGgDAAIACAj4JUYBAGgDAAAA.Bistato:BAAALAAECgIIAwAAAA==.Bistopher:BAAALAAECgUICAAAAA==.Bistyhoodle:BAAALAADCggICAABLAAECgUICAABAAAAAA==.',Bl='Blindspirit:BAAALAAECgYIDgAAAA==.Blindvngence:BAAALAAECgMIBgAAAA==.Blizzerker:BAAALAADCgYIBgAAAA==.Bloodrayne:BAAALAADCggIDQAAAA==.',Bo='Boomshankz:BAAALAADCgMIAwAAAA==.',Br='Brauntora:BAAALAADCgcIBwAAAA==.Brinebeard:BAAALAADCggICgAAAA==.Brøx:BAAALAAECgYICQAAAA==.',Bu='Bubblehealzz:BAAALAAFFAEIAQAAAA==.Burt:BAAALAAECgYICgAAAA==.Buumy:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.',['Bî']='Bîrth:BAAALAAECgcIEgAAAA==.',Ca='Caelem:BAAALAADCgYIBwAAAA==.Calic:BAAALAAECgYIBgAAAA==.Calryuu:BAAALAAECgQIBgAAAA==.Caltrask:BAAALAAECgIIAgAAAA==.Capricious:BAAALAADCgcIDgAAAA==.Catharsis:BAAALAAECggIDAAAAA==.',Ce='Celendorian:BAAALAADCggIDgAAAA==.',Ch='Chalt:BAAALAADCgcIBwAAAA==.Chantyu:BAAALAADCgcIFgABLAAECgMIBQABAAAAAA==.Chaotichugs:BAAALAAECggICAAAAA==.Chiaddict:BAAALAAECgMIBgAAAA==.Chickenman:BAAALAAECgYIEAAAAA==.Chiflado:BAAALAAECgcIDgAAAA==.Child:BAAALAADCgQIBAABLAAECggIFgADAFUhAA==.Chinpokodin:BAAALAAECgcIEAAAAQ==.Chubbychi:BAAALAAECgMIBQAAAA==.',Ci='Ciei:BAAALAADCggIFAAAAA==.Cilyac:BAAALAAECgcICwAAAA==.Ciryal:BAAALAADCgQIBAAAAA==.',Cl='Clinic:BAAALAADCgQIBAAAAA==.',Co='Cole:BAAALAAECgYICwAAAA==.Corpsecat:BAAALAADCgEIAQAAAA==.',Cr='Crabdrangoon:BAAALAADCgQIBAAAAA==.Creamcorn:BAAALAADCgEIAgAAAA==.Crinkle:BAAALAADCgQIBAAAAA==.Crityvoker:BAAALAAECgcIDgAAAA==.',Cv='Cvrcvss:BAAALAADCgEIAQAAAA==.',Da='Dabadjuju:BAAALAAECgIIAgAAAA==.Daerik:BAAALAAECgYIDwAAAA==.Dandowaz:BAAALAAFFAIIAgAAAA==.Dandyrandy:BAAALAAECgYIDwAAAA==.Dani:BAAALAADCgcICQAAAA==.Darklotus:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Darthavenger:BAAALAAECgMIAwAAAA==.Davidblaine:BAAALAADCgEIAQAAAA==.Dawnsreaper:BAAALAAECgcICwAAAA==.Dayday:BAAALAAECggIAwAAAA==.',De='Deadlyarms:BAAALAADCgQIBAAAAA==.Deepfist:BAAALAAECgYICQAAAA==.Delicia:BAAALAAECgQIBgAAAA==.Dellbelphine:BAAALAAECgQIBQAAAA==.Demlyt:BAAALAAECgYICAAAAA==.Demonbud:BAAALAAECgMIAwAAAA==.Demoncarlos:BAAALAADCgUIBQABLAADCgcIDQABAAAAAA==.Demonskii:BAAALAAECgEIAQAAAA==.Demton:BAAALAAECgYICQAAAA==.Dezmage:BAEALAADCgIIAgABLAAECgcICAABAAAAAA==.Dezodin:BAEALAAECgcICAAAAA==.',Dg='Dgkprodigy:BAAALAAECgcIEgAAAA==.',Dh='Dhjck:BAAALAADCgMIAwAAAA==.',Di='Diatonic:BAAALAADCgcIBwAAAA==.Direcow:BAAALAAECgYIDwAAAA==.',Do='Dojaz:BAAALAAECgYIDwAAAA==.Doof:BAAALAAECgYIDAAAAA==.Doomhammer:BAABLAAECoEVAAIEAAgIJiUWAgBZAwAEAAgIJiUWAgBZAwAAAA==.Dosk:BAAALAADCgcIDgAAAA==.',Dr='Draconica:BAAALAAECgMIAwAAAA==.Dragar:BAAALAAECgYIDwAAAA==.Dragonler:BAAALAADCggICAABLAAECgcIEQABAAAAAA==.Drdoctor:BAAALAAECgMIAwAAAA==.Dreampuff:BAAALAADCggIDQAAAA==.Dreddful:BAAALAAECgYIDwAAAA==.Drkelso:BAAALAAECgYIBgAAAA==.Drum:BAAALAAECgcICAAAAA==.',Ds='Dshankzz:BAAALAADCgcICQAAAA==.',Dw='Dwarrfie:BAAALAADCggICAAAAA==.',Dy='Dymnala:BAAALAADCgEIAQAAAA==.',['Dè']='Dèz:BAAALAAECgIIAgAAAA==.',['Dø']='Døng:BAAALAADCggICAAAAA==.',Ed='Edith:BAAALAAECgYICwAAAA==.',Ei='Eione:BAAALAAECgUIDAAAAA==.Eiris:BAAALAAECgYICQAAAA==.',El='Ellcrys:BAAALAAECgYIDQAAAA==.Elvinshiznic:BAAALAAECgIIBAAAAA==.Elyzah:BAAALAADCggICAAAAA==.',Em='Emagine:BAAALAAECgcIDgAAAA==.Emeraldbeast:BAAALAAECgYICQAAAA==.',En='Endela:BAAALAAECgEIAQABLAAECgQIBgABAAAAAA==.Enlightnment:BAAALAAECgMIBQAAAA==.Enni:BAAALAAECgcIBwAAAA==.',Es='Escanør:BAAALAADCggIFgABLAAECgYIEAABAAAAAA==.',Ev='Evokalic:BAAALAADCggIDgABLAAECggIFwAFAFUlAA==.',Ex='Excellen:BAAALAAECgMIBQAAAA==.Exo:BAAALAAECgYIDwAAAA==.Exylan:BAAALAADCgMIAwABLAAECgIIAgABAAAAAA==.',Ez='Ezknight:BAAALAAECgYICwAAAA==.',['Eñ']='Eñkei:BAAALAADCgYIBQAAAA==.',Fa='Fables:BAAALAADCgcICgAAAA==.Falkichu:BAAALAADCgIIAwAAAA==.',Fe='Felsae:BAAALAAECgcICgAAAA==.Feralnerfplz:BAAALAAECgcIEQAAAA==.',Ff='Ffresh:BAAALAADCggIDgABLAAECgYIBgABAAAAAA==.',Fi='Fierysquish:BAAALAADCgYIDQAAAA==.Firemight:BAAALAADCggICAAAAA==.Fisten:BAAALAADCggICAABLAAECgcIFQACAFwhAA==.Fistn:BAABLAAECoEVAAQCAAcIXCHDCwCJAgACAAcIXCHDCwCJAgAGAAEIdBFaFwBBAAAHAAEIxgOxWAA0AAAAAA==.',Fl='Flexx:BAAALAAECgYICQAAAA==.',Fo='Fort:BAAALAAECggICgAAAA==.',Fr='Freezing:BAAALAAECgYICQAAAA==.Freshhunt:BAAALAADCgcIEgABLAAECgYIBgABAAAAAA==.Freshlock:BAAALAAECgYIBgAAAA==.Fright:BAAALAAECgEIAQAAAA==.Friska:BAAALAADCgEIAgAAAA==.Frostedtips:BAAALAAECggIBQAAAA==.Frostytoez:BAACLAAFFIEFAAMIAAMISQ9rBQD0AAAIAAMISQ9rBQD0AAAJAAEI1QMAAwA5AAAsAAQKgRgAAggACAhJHC8TAH0CAAgACAhJHC8TAH0CAAAA.Frostyvoker:BAAALAAECgIIAgAAAA==.',Fu='Fullbright:BAAALAADCggIDgAAAA==.Furiousbruja:BAAALAAECgIIAgAAAA==.',Fy='Fyre:BAAALAAECgYICQAAAA==.',Ga='Galadhriel:BAAALAAECgYICQAAAA==.Ganador:BAAALAAECgYIDwAAAA==.Gazzerfroz:BAAALAADCggICwABLAAECgYIDwABAAAAAA==.',Ge='Gelge:BAAALAADCggIEAAAAA==.Genorian:BAAALAAECgYIDAAAAA==.Getcrit:BAAALAADCgcIBwAAAA==.',Gi='Gimbal:BAAALAAECgUICAAAAA==.',Go='Gogric:BAAALAAECggIDgAAAA==.Gokusan:BAAALAAECgYICAAAAA==.Gomgar:BAAALAADCggIDQAAAA==.Goobrt:BAAALAADCgcICgAAAA==.Goosly:BAAALAADCgMIAwAAAA==.Gorg:BAAALAAECgEIAQAAAA==.',Gr='Greentide:BAAALAAECgcIEgAAAA==.Grexistian:BAAALAADCggIDQAAAA==.Greysham:BAAALAADCgcIBwAAAA==.Groovybun:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Groovycake:BAAALAAECgYICQAAAA==.',Gu='Guccimaybe:BAAALAAECgQIBwAAAA==.Guppy:BAAALAADCgIIAwAAAA==.',Gw='Gwynneth:BAABLAAECoEXAAIKAAgIDSJsAwDbAgAKAAgIDSJsAwDbAgAAAA==.',Ha='Habakkos:BAAALAADCgcIEQAAAA==.Haelyr:BAAALAAECgMIBAAAAA==.Halea:BAAALAAECgUIBQAAAA==.Halepurr:BAAALAAECgYIDQAAAA==.Hammerferge:BAAALAADCgUIBQAAAA==.Handsofelune:BAAALAAECgcIDwAAAA==.Happa:BAAALAAECgYICQABLAAECgcICgABAAAAAA==.Harrowe:BAAALAADCggIDgAAAA==.Haywire:BAAALAADCggICAAAAA==.Hazelena:BAAALAADCgEIAQAAAA==.',He='Healingbrew:BAAALAAECgcICwAAAA==.Healroy:BAAALAADCggIDgAAAA==.Helical:BAAALAADCgQIBAAAAA==.Heretoohelp:BAAALAAECgMIAwAAAA==.',Ho='Holydiscdow:BAAALAADCgcICAABLAAECgMIBQABAAAAAA==.Holysquish:BAABLAAECoEVAAMLAAgIbCHgCgDRAgALAAgIbCHgCgDRAgAMAAMI2QLPIABrAAAAAA==.Honésty:BAAALAAECgUIBgAAAA==.Horns:BAAALAADCgYICQAAAA==.Horsegirl:BAAALAAECgYIBwAAAA==.',Hr='Hrakharuirn:BAAALAADCgcIBwAAAA==.',Hu='Hussle:BAAALAAECgcIEAAAAA==.',Ic='Iceleaf:BAAALAAECgIIAgAAAA==.',Ik='Ikmoti:BAAALAAECgMIAwAAAA==.',Il='Ileinaa:BAAALAAECgYIEgAAAA==.Iliketrains:BAAALAAECgYICQAAAA==.',Im='Imop:BAAALAAECgMIBAAAAA==.',In='Intensevok:BAAALAAECgIIAgAAAA==.Intensifiedx:BAAALAADCggICgABLAAECgIIAgABAAAAAA==.',It='Italo:BAAALAADCgYIBgAAAA==.',Ja='Jabjo:BAAALAADCgYIBgAAAA==.Jayfizzle:BAAALAAECgEIAQAAAA==.Jayseekay:BAAALAAECgcIBwAAAA==.',Jc='Jckie:BAAALAADCgUIBQAAAA==.',Je='Jestyr:BAAALAAECgYICQAAAA==.Jestyrmo:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Jet:BAAALAAECgIIAgAAAA==.Jetchi:BAAALAADCgIIAgAAAA==.',Jo='Joehendry:BAAALAAECgYIBwAAAA==.Jonny:BAAALAAECgEIAQAAAA==.Joobeilol:BAAALAAECgMIBAABLAAFFAEIAQABAAAAAA==.Joojekabab:BAAALAADCgIIAgAAAA==.',Ju='Jubei:BAAALAAFFAEIAQAAAA==.Jurik:BAAALAADCgQIBAAAAA==.Juw:BAAALAAECgMIBQAAAA==.',Ka='Kalidra:BAABLAAECoEUAAINAAgImBMKCQDRAQANAAgImBMKCQDRAQAAAA==.Kazuresetra:BAAALAADCgQIBAAAAA==.',Ke='Keane:BAAALAAECgEIAQAAAA==.Kellelor:BAAALAADCgQIBAAAAA==.',Ki='Killkillkill:BAAALAADCggIDwAAAA==.Kindled:BAAALAAECgcIDQAAAA==.Kirklandbeef:BAAALAAECgIIAgAAAA==.Kits:BAAALAAECgUIBQABLAAECgYIDQABAAAAAA==.',Kn='Kniavez:BAAALAAECgYICQAAAA==.',Ko='Korro:BAAALAAECgMIBQAAAA==.',Kr='Krack:BAAALAAECgYICwAAAA==.Kratoo:BAAALAADCggICAAAAA==.',Ku='Kuler:BAAALAAECgUICwAAAA==.Kungfushrub:BAAALAAECgIIAgAAAA==.',['Kè']='Kèèn:BAAALAAECgcIEQAAAA==.',['Ké']='Két:BAAALAAECgYICAAAAA==.',['Kí']='Kítkat:BAAALAAECgYIDQAAAA==.',['Kÿ']='Kÿra:BAAALAADCggIFgAAAA==.',La='Lalunaa:BAAALAAECgEIAQAAAA==.',Le='Leeroyjenko:BAAALAAECgYICQAAAA==.Levelcláp:BAAALAAECgQIBAAAAA==.',Li='Liakä:BAAALAADCgcIFQAAAA==.Lifesavers:BAAALAAECgcIEAAAAA==.Liishen:BAAALAAECgMIBAAAAA==.Lilshaxx:BAAALAAECgYIDAAAAA==.',Lo='Lockpow:BAAALAADCggIDwAAAA==.Lorienb:BAAALAAECgYICQAAAA==.Lowkydead:BAAALAAECgYICQAAAA==.',Lu='Luckehlock:BAACLAAFFIEFAAMOAAMINCMGAABQAQAOAAMINCMGAABQAQAPAAEIoxaUDQBYAAAsAAQKgRgAAg4ACAhTJhYAAJMDAA4ACAhTJhYAAJMDAAAA.Luminar:BAAALAADCgcIBwAAAA==.Luxcn:BAAALAAECgYIBgAAAA==.',Ma='Macgibbins:BAAALAAECgYICQAAAA==.Macgillivray:BAAALAADCggICAAAAA==.Mageli:BAAALAAECgUIBwAAAA==.Maluck:BAAALAAECgMIBAAAAA==.Mamamaggie:BAAALAAECgIIAgAAAA==.',Mc='Mcscroogeduc:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.',Me='Melylen:BAAALAAECgYICQAAAA==.Mental:BAAALAAECgYIDAAAAA==.Merkus:BAAALAADCgcICgAAAA==.',Mi='Miicow:BAAALAAECgIIBQAAAA==.Milkpi:BAAALAAECgYIDAAAAA==.Minigolf:BAAALAADCgEIAQAAAA==.Missfu:BAAALAAECgIIAwAAAA==.Mizukï:BAAALAAECgYICAAAAA==.',Mo='Moaralts:BAAALAADCggIAwABLAAECgQIBgABAAAAAA==.Molyver:BAAALAAECgYIDgAAAA==.Momak:BAAALAAECgQIBQAAAA==.Monascary:BAAALAADCgcIBwAAAA==.Moonmellow:BAAALAADCgcIBwAAAA==.Morphy:BAAALAADCgcIBwAAAA==.Mozgus:BAAALAAECgYICwAAAA==.',Mp='Mpatt:BAAALAADCgcIDQAAAA==.',Mu='Multudinous:BAAALAADCgMIAwAAAA==.Munder:BAAALAAECgEIAQAAAA==.Murghen:BAAALAADCgEIAQABLAAECgYIDAABAAAAAA==.Musculate:BAABLAAECoEaAAIFAAgIDiMRBQDkAgAFAAgIDiMRBQDkAgAAAA==.',Na='Nartou:BAAALAAECgYIDwAAAA==.Natreamu:BAAALAAECgQIBwAAAA==.',Ni='Nightxangel:BAAALAADCggIEAAAAA==.Nightxxangel:BAAALAADCgYIBgAAAA==.',No='Noolore:BAABLAAECoEVAAIQAAgINh8OAwDIAgAQAAgINh8OAwDIAgAAAA==.Nordin:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Nosferatu:BAAALAADCgcIBwAAAA==.',Nu='Nurfvoid:BAAALAAECgYICQAAAA==.',Ny='Nysselyne:BAAALAADCgUIBQAAAA==.',Od='Odimus:BAAALAAFFAIIAwAAAA==.',Ol='Olanix:BAAALAADCgIIAgABLAADCgMIAwABAAAAAA==.Oldmacdonald:BAAALAADCgYIDAAAAA==.',On='Onana:BAAALAAECgcIEgAAAA==.Onodar:BAAALAADCggIDQABLAAECgYIDwABAAAAAA==.',Ox='Oxen:BAAALAAECgMIBAAAAA==.',Pa='Padraig:BAAALAAECgcICAAAAA==.Pandaxpress:BAAALAADCgYIBgAAAA==.Pandela:BAAALAADCgYIBgABLAAECgQIBgABAAAAAA==.',Pe='Peekamoo:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.Peepyalic:BAAALAAECgUIBwABLAAECggIFwAFAFUlAA==.Pega:BAAALAAECgcICgAAAA==.Penniwing:BAAALAAECgQIBAAAAA==.Percival:BAABLAAECoEYAAMRAAgIliOIAAAZAwARAAgIliOIAAAZAwAFAAEIxAigTwAvAAAAAA==.Perhero:BAAALAADCgEIAQAAAA==.Persephone:BAAALAADCgcIEQAAAA==.',Ph='Phaedra:BAAALAAECgcIEAAAAQ==.Phak:BAAALAADCgUIBgABLAADCggICAABAAAAAA==.Phealock:BAAALAAECgYICQAAAA==.',Pi='Piffboy:BAAALAADCggICAAAAA==.',Po='Popeyes:BAAALAAECgYICQAAAA==.Powrwordaddy:BAAALAADCgIIAwABLAAECgIIAgABAAAAAA==.',Pr='Prangsz:BAAALAAECgQIBQAAAA==.Priestfeet:BAAALAAECgYICgAAAA==.Priestler:BAAALAAECgcIEQAAAA==.',Pu='Pullbarg:BAAALAADCggIEQAAAA==.',['Pï']='Pïng:BAAALAADCgcIDAAAAA==.',Qu='Quickwinnter:BAAALAADCgMIAwAAAA==.Quimn:BAAALAADCgEIAQAAAA==.',Ra='Raantoks:BAAALAADCggIEAABLAAECgMIAwABAAAAAA==.Radey:BAAALAAECgIIAgAAAA==.Ragemcgoo:BAAALAADCgcICQAAAA==.Rakk:BAAALAAECgYIDAAAAA==.Ranntokh:BAAALAAECgMIAwAAAA==.',Re='Reggienoble:BAAALAADCgcIBgAAAA==.Reiner:BAACLAAFFIEFAAIEAAMICxxzAgAQAQAEAAMICxxzAgAQAQAsAAQKgRgAAgQACAhmJZMBAGUDAAQACAhmJZMBAGUDAAAA.Remmii:BAAALAADCggICAAAAA==.Reverendmini:BAAALAAECgYICQAAAA==.Reynaria:BAAALAAECgcICwAAAA==.',Rh='Rhiisa:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.',Ri='Rimetail:BAAALAADCggIDgAAAA==.Ringless:BAAALAAECgcIDAAAAA==.Riskah:BAAALAAECgIIAgAAAA==.',Ro='Rodoan:BAAALAADCggIFwAAAA==.Rolan:BAAALAAECgIIAgAAAA==.Rosan:BAAALAAECgMIBQAAAA==.',Ru='Ruaid:BAAALAAECgIIAgAAAA==.',Sa='Salazzar:BAAALAADCggICAAAAA==.Sallysoo:BAAALAADCgMIAwAAAA==.Sandraiya:BAAALAAECgYICgAAAA==.Sankyu:BAAALAAECgYIDwAAAA==.',Sc='Scaley:BAAALAAECgYICQAAAA==.Scraps:BAAALAADCgcIBwAAAA==.Scredwin:BAAALAAECgYICQAAAA==.',Se='Sealclubbing:BAAALAADCgcIDQABLAAECgIIAgABAAAAAA==.Senorboboxx:BAAALAAECgYICwAAAA==.Senorxx:BAAALAADCgcIDgABLAAECgYICwABAAAAAA==.Sern:BAAALAADCgcIBQAAAA==.Serni:BAAALAAECgMIAwAAAA==.',Sh='Shablammer:BAAALAADCgYIDAABLAAECgMIBQABAAAAAA==.Shadora:BAAALAADCgYIBgAAAA==.Shammknight:BAAALAAECgcIEAAAAA==.Shanksinatrá:BAACLAAFFIEFAAMSAAMI7h50AwDNAAASAAIIjR90AwDNAAATAAEIsB1hAwBaAAAsAAQKgR0ABBIACAgwI8UHALMCABIABwg0IsUHALMCABMAAwjKHwgMAAkBABQAAQhRHpsMAFcAAAAA.Shankxz:BAAALAADCgUICgAAAA==.Shankzz:BAAALAADCggICwAAAA==.Shatt:BAAALAAECgMIAwAAAA==.Shedari:BAAALAADCggIDAAAAA==.Shephrah:BAAALAAECgcIDQAAAA==.Shizzdk:BAAALAAECgMIAwAAAA==.Shizzpog:BAAALAADCgcICgAAAA==.Shootalic:BAABLAAECoEXAAQFAAgIVSWyAQA/AwAFAAgIVSWyAQA/AwAVAAIIKAoMZgBfAAARAAEIZSLVCwBNAAAAAA==.',Si='Sideways:BAAALAADCggICAAAAA==.Simzealot:BAAALAAECgYICQAAAA==.Simzerker:BAABLAAECoEXAAIWAAgIwyMXBAAwAwAWAAgIwyMXBAAwAwAAAA==.',Sk='Skibidibha:BAAALAAECgYIBgAAAA==.',Sl='Slamina:BAAALAAECgcIEAAAAA==.Slikshotgrey:BAAALAAECgIIAgAAAA==.',Sn='Sniiffle:BAAALAAECgYICAAAAA==.Snowli:BAAALAAECgMIBQAAAA==.',So='Softly:BAABLAAECoEWAAIDAAgIVSGrAgDoAgADAAgIVSGrAgDoAgAAAA==.Solanis:BAAALAAECgYICQAAAA==.',Sp='Splínter:BAAALAADCggICAAAAA==.Sprucejenner:BAAALAAECgYICQAAAA==.',Sq='Squap:BAAALAADCgMIAwAAAA==.',St='Stalagstrype:BAABLAAECoEVAAILAAcIdhkFHwAHAgALAAcIdhkFHwAHAgAAAA==.Stalizzy:BAAALAAECgEIAQAAAA==.Starkisses:BAAALAAECgYIDwAAAA==.Stellae:BAAALAADCggIDgAAAA==.Storebrandps:BAAALAADCggIDgABLAAECgIIAgABAAAAAA==.Stratego:BAAALAADCgQIBAAAAA==.Styrth:BAACLAAFFIEFAAIXAAMIYSXHAABJAQAXAAMIYSXHAABJAQAsAAQKgRgAAhcACAhfJk4AAIgDABcACAhfJk4AAIgDAAAA.',Su='Subtractive:BAAALAADCgUIBQAAAA==.',Sw='Swiftheals:BAAALAADCgcIDgAAAA==.',Ta='Talkimas:BAAALAAECgYICQAAAA==.Talvisota:BAAALAAECgYICQAAAA==.Tastemyheal:BAAALAAECgEIAQAAAA==.',Te='Tekoslul:BAAALAAECggICAAAAA==.Teldravine:BAAALAADCggICAAAAA==.Tempestas:BAAALAADCggIEwAAAA==.Tendeda:BAAALAAECgYICQAAAA==.',Th='Thalunar:BAAALAAECgQIBwAAAA==.Thander:BAAALAAECgQIBQABLAAECgcIEQABAAAAAA==.Thepastor:BAAALAADCggIDgAAAA==.Thunderdrum:BAAALAAECgMIAwAAAA==.Thunderkat:BAAALAAECgMIAwAAAA==.Thørck:BAAALAAECgYIBwAAAA==.',Ti='Tinklewinkle:BAAALAAECgcIDgAAAA==.',To='Topher:BAAALAAECgYICAABLAAECggIFgADAFUhAA==.Toppo:BAAALAADCgUIBQAAAA==.Totemsquish:BAAALAADCgYICAAAAA==.',Tp='Tpofosho:BAAALAAECgEIAQAAAA==.',Tr='Tree:BAAALAAECgYICgAAAA==.Treemother:BAAALAAECgYIDAAAAA==.Trulla:BAAALAAECgMIAwAAAA==.',Ts='Tsohg:BAAALAAECgIIAgAAAA==.',Tu='Tuhalla:BAAALAAECgYIDAAAAA==.Tumlock:BAAALAAECgYICgAAAA==.Turbulence:BAAALAAECgIIAgAAAA==.Turrok:BAAALAAECgYIDgAAAA==.',Ua='Uandikillhim:BAAALAAECgMIBQAAAA==.',Un='Uneraser:BAAALAADCggIDAAAAA==.Uninfluenced:BAAALAADCgcICgAAAA==.Unremorseful:BAAALAAECgYICwAAAA==.',Uo='Uoyredrum:BAAALAADCgEIAQABLAAECgYICQABAAAAAA==.',Ur='Uranus:BAAALAADCggIDAAAAA==.Urban:BAAALAADCggICAAAAA==.',Va='Vadym:BAAALAADCgEIAQAAAA==.Vaelia:BAAALAAECgUICAAAAA==.Varandra:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Ve='Vent:BAAALAADCgIIAgAAAA==.Venttres:BAAALAAECgYIEAAAAA==.Vexice:BAAALAAFFAMIBAAAAA==.',Vi='Views:BAAALAADCgcICAAAAA==.Vilienar:BAAALAAECgIIAgAAAA==.',Vo='Voldy:BAAALAAECgQIBAAAAA==.',Vu='Vuloolu:BAAALAAECgYICAAAAA==.',['Vø']='Vøgue:BAAALAAECgYIDwAAAA==.',Wa='Warmason:BAAALAAECgIIBAAAAA==.Watchitpal:BAAALAAECgEIAQAAAA==.',We='Wealthy:BAAALAAECgYICQAAAA==.Weßall:BAAALAADCgIIAwAAAA==.',Wh='Whiskeywild:BAAALAAECgMIAwAAAA==.',Wi='Wiiska:BAAALAAECgcIDQAAAA==.Wingdingler:BAAALAADCggICAAAAA==.',Wu='Wurship:BAAALAADCgYIDAAAAA==.',Xo='Xombi:BAAALAADCggIDAAAAA==.',Ya='Yamato:BAAALAAECgIIAwAAAA==.Yamm:BAAALAADCgYICAAAAA==.',Yu='Yuhwoo:BAAALAAECgYIDwAAAA==.',Za='Zamoody:BAAALAADCgQIBAAAAA==.Zandelah:BAAALAADCgQIBAAAAA==.Zangla:BAAALAADCggIDAAAAA==.',Ze='Zemi:BAAALAAECgYIDAAAAA==.Zenana:BAAALAAECgYIDAAAAA==.Zephang:BAAALAAECgYIDQAAAA==.Zero:BAAALAAECggIEgAAAA==.Zeroith:BAAALAAECgMIBgAAAA==.',Zm='Zmz:BAAALAADCggICAAAAA==.',Zu='Zugrotic:BAAALAADCggIDQABLAAECgQIBQABAAAAAA==.',Zy='Zymandias:BAAALAAECgYICQAAAA==.',['Ða']='Ðavid:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end