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
 local lookup = {'Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Shaman-Restoration','DeathKnight-Frost','Paladin-Protection','Druid-Balance','Druid-Restoration','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','Priest-Shadow','Priest-Discipline','Warrior-Fury',}; local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aamodar:BAAALAADCgcIEQAAAA==.',Ab='Abadon:BAAALAAECgIIAwAAAA==.',Ac='Action:BAACLAAFFIEGAAIBAAMIuxgDAwAaAQABAAMIuxgDAwAaAQAsAAQKgRgAAwEACAibI8cEABADAAEACAibI8cEABADAAIAAQiNDrcsAD4AAAAA.',Ad='Adalea:BAAALAADCgcIBwAAAA==.Adino:BAAALAAECgYICgAAAA==.Adoraßell:BAAALAADCggICAABLAAECgYIDQADAAAAAA==.',Ae='Aelyna:BAAALAADCgcIBwAAAA==.Aeryn:BAAALAAECgcIDQAAAA==.Aerís:BAAALAADCgcIDAAAAA==.',Ah='Ahote:BAAALAAFFAIIAgAAAA==.Ahtee:BAAALAAECgYIDAAAAA==.',Ak='Akane:BAAALAAECgMIAwAAAA==.',Al='Alexazsharia:BAAALAADCgYIBgAAAA==.Alianesmor:BAAALAADCgMIAwAAAA==.Alseena:BAAALAAECgMIAwAAAA==.Alysiita:BAAALAADCgEIAQAAAA==.',Am='Amadeux:BAAALAAECgcIEAAAAA==.Amicae:BAAALAAECgYIBgAAAA==.',An='Andenarras:BAAALAAECgIIAwAAAA==.Andria:BAAALAADCgMIAwAAAA==.Anform:BAAALAAECgEIAQAAAA==.Anvar:BAAALAAECgMIAwAAAA==.Anyhelpers:BAAALAADCgQIBAAAAA==.',Ar='Arctreus:BAAALAADCgUIBwAAAA==.Articos:BAAALAAECgQICAAAAA==.Arx:BAABLAAECoEjAAMEAAgIryCRAQClAgAEAAgIYR2RAQClAgAFAAYI2yL0BgBTAgAAAA==.',As='Ashleyk:BAAALAAECgUICgAAAA==.',At='Atrumdeus:BAAALAAECgYICgAAAA==.',Au='Aurikon:BAAALAADCgcICQAAAA==.',Aw='Awkykit:BAAALAAECgUICAAAAA==.',Ba='Baadaaboom:BAAALAADCggIEAABLAAECgMIAwADAAAAAA==.Baimriryn:BAAALAADCgUIBQAAAA==.Bangerz:BAAALAADCgMIAwAAAA==.Bannann:BAAALAAECggIAgAAAA==.Banned:BAAALAAECgYICQAAAA==.',Be='Beaksbigdk:BAAALAAECgYIDQAAAA==.Belldia:BAAALAAECgYIDQAAAA==.Benniru:BAAALAAECgEIAQAAAA==.Bennyblipz:BAAALAAECgcIDgAAAA==.',Bf='Bfresh:BAAALAADCgYIBgABLAAECgYICgADAAAAAA==.',Bh='Bhain:BAAALAADCgcIBwAAAA==.',Bi='Bini:BAAALAADCgQIBwAAAA==.Binlawldin:BAAALAAECgMIAwABLAAECgYIBgADAAAAAA==.Birdbear:BAAALAAECgIIAgAAAA==.Bishøp:BAAALAADCgYIBgAAAA==.',Bl='Blackribbon:BAAALAAECgMIAwAAAA==.Blightedmilk:BAAALAAECgEIAQAAAA==.Blindbluff:BAAALAADCgMIAwAAAA==.Blueblueblue:BAAALAADCgMIAwAAAA==.Blufox:BAAALAAECgYICQAAAA==.',Bo='Bobfresh:BAAALAAECgYICgAAAA==.Bolo:BAAALAAECgEIAQAAAA==.Bomboclat:BAAALAAECgEIAQAAAA==.',Br='Bronzer:BAAALAAECgMIAwAAAA==.Bronzetusk:BAAALAADCgEIAQAAAA==.Brothalynch:BAAALAADCggIFgAAAA==.Brönks:BAAALAADCgMIAwAAAA==.',Bu='Bullzerker:BAAALAADCgYIBwAAAA==.Bustylusty:BAABLAAECoEUAAIGAAcImRD/KgB3AQAGAAcImRD/KgB3AQAAAA==.',['Bà']='Bàhamut:BAAALAADCgUIBQAAAA==.',Ca='Calphius:BAAALAAECgYICQAAAA==.Carritha:BAAALAADCgIIAgAAAA==.Cattywompus:BAAALAADCgcIBwAAAA==.',Ch='Charlixchix:BAAALAAECgEIAQAAAA==.Chialliance:BAAALAAECgYICQAAAA==.Chimaster:BAAALAAECgcICwAAAA==.Chriswong:BAAALAAECgQICAAAAA==.Chrysamere:BAAALAAECgMIAwAAAA==.',Ci='Cinopah:BAAALAADCggIFgAAAA==.',Cl='Clairebenet:BAAALAAECgYIBwAAAA==.Cloft:BAAALAAECgYICgAAAA==.Cloudnine:BAAALAAECgEIAQAAAA==.',Co='Code:BAAALAAECggIAQAAAA==.Consfearacy:BAAALAADCgIIAgAAAA==.Coolynn:BAAALAADCggICAAAAA==.Corin:BAAALAAECgEIAQAAAA==.Coxienormus:BAAALAADCgIIAgAAAA==.',Cr='Crayzie:BAAALAADCgYIBgAAAA==.Crazybubble:BAAALAADCggICgAAAA==.Crazyeye:BAAALAAECgEIAQAAAA==.Croy:BAAALAADCgcICAAAAA==.',Cw='Cwdd:BAAALAAECgUICAAAAA==.Cwds:BAAALAADCggIDQABLAAECgUICAADAAAAAA==.',Da='Damacraze:BAAALAAECgcIDQAAAA==.Daoloth:BAAALAAECgUIBwAAAA==.Darkfalcon:BAAALAADCggICAAAAA==.Daxine:BAAALAADCggIDwAAAA==.',De='Deadwill:BAAALAADCggIDgAAAA==.Deaminase:BAAALAAECgYIAQAAAA==.Deathpulse:BAAALAAECgcIEAAAAA==.Delphoxx:BAAALAADCggIDAAAAA==.Deltonio:BAAALAADCggICAAAAA==.Demidru:BAAALAAECgIIAgAAAA==.Demimo:BAAALAADCgcIDgAAAA==.Demonnoodle:BAAALAAECgEIAQAAAA==.Derzbec:BAAALAADCggIFgAAAA==.Desrook:BAAALAADCgUIBQAAAA==.',Dh='Dhqt:BAAALAAECgQIBAAAAA==.',Di='Dicol:BAAALAAECgYIBwAAAA==.Divineshock:BAAALAAECgYICQAAAA==.Dizzie:BAAALAAECggICwAAAA==.',Do='Donki:BAAALAADCgYIBgAAAA==.Doomguy:BAAALAADCggIDwAAAA==.',Dr='Drakblak:BAAALAAECgcIDQAAAA==.Dramione:BAAALAADCgEIAQAAAA==.Drathgar:BAAALAAECgMIBQAAAA==.Dreadrend:BAABLAAECoERAAIHAAgIoCRdBQAcAwAHAAgIoCRdBQAcAwAAAA==.Droni:BAAALAAECgYICAAAAA==.',Du='Dumbshaman:BAAALAADCgYICAAAAA==.',Eg='Eggdrop:BAAALAAECgMIAwAAAA==.Eggrolla:BAAALAAECgEIAQAAAA==.Egufro:BAAALAADCgcIBwABLAAECgcIDgADAAAAAA==.',El='Eleaya:BAAALAAECgEIAQAAAA==.Elfro:BAAALAADCgcIBwAAAA==.Elsham:BAAALAADCgcIBwAAAA==.',Em='Empusa:BAAALAADCggICAAAAA==.',En='Enaeria:BAAALAADCgcIDgAAAA==.Endervish:BAAALAADCgcIEgAAAA==.',Ep='Epiliphz:BAAALAAECgYIBgAAAA==.',Er='Erhmer:BAAALAAECggIDgAAAA==.Ericrog:BAAALAAECgYICwAAAA==.Ericwym:BAAALAADCgUIBgAAAA==.',Et='Ethersong:BAAALAADCgYIBwAAAA==.',Ev='Evobwhaha:BAAALAADCgYICwAAAA==.',Ex='Execuwute:BAAALAADCgMIAwAAAA==.Exit:BAAALAADCgYIBgAAAA==.Exodes:BAAALAADCggIDQAAAA==.',Fa='Fairyhunter:BAAALAADCgcIBwAAAA==.Fairymonk:BAAALAADCgYIBgAAAA==.Fañgrat:BAAALAADCgMIAwABLAAECgQIBAADAAAAAA==.',Fe='Fellaris:BAAALAADCggIFAAAAA==.Fellriaris:BAAALAADCgMIAwAAAA==.Ferdinandos:BAAALAAECgUIBAAAAA==.',Fl='Flamebringer:BAAALAADCgYIBgAAAA==.Fleen:BAAALAADCgcICgABLAAECgYICgADAAAAAA==.Floppyterri:BAAALAADCgEIAQAAAA==.Floppyterry:BAAALAAECgIIAgAAAA==.Flow:BAAALAAECgcIDgAAAA==.',Fo='Forezen:BAAALAAECgYIDQAAAA==.',Fr='Franciss:BAAALAAECgIIAgAAAA==.Frostbringer:BAAALAAECgIIAgAAAA==.Froznlight:BAAALAADCggIDwAAAA==.Fruitsnacks:BAAALAAECgIIAgABLAAFFAMIBQAIADgbAA==.',Ft='Ftreefiddy:BAAALAAECggIEAAAAA==.',Fu='Fulgurvulpes:BAAALAADCgQIBAAAAA==.',Fy='Fylerian:BAACLAAFFIEGAAIJAAQI6hGlAABcAQAJAAQI6hGlAABcAQAsAAQKgRgAAwkACAjNJXUBAF0DAAkACAjNJXUBAF0DAAoAAQjjARldAB8AAAAA.Fylerianhunt:BAAALAADCgEIAQAAAA==.Fylerianmage:BAAALAAECgYICwABLAAFFAQIBgAJAOoRAA==.',Ga='Galaras:BAAALAADCgMIBAAAAA==.Galeredas:BAAALAAECgYICwAAAA==.Ganjja:BAAALAAECgMIAwAAAA==.Gardengoblin:BAAALAAECgQIBQAAAA==.',Gh='Ghettomike:BAAALAAECgYICAAAAA==.',Gi='Giny:BAAALAAECgYIDAAAAA==.',Gl='Glacierbrew:BAAALAAECgIIAgAAAA==.',Go='Gobbledeez:BAAALAAECgMIAwAAAA==.Gobby:BAAALAADCgcIBwAAAA==.Goboom:BAAALAADCgcIBwAAAA==.Gothsquirter:BAAALAAECgMIAwAAAA==.',Gr='Grandcodex:BAAALAAECgQIBgAAAA==.Graysing:BAAALAAECgIIAgAAAA==.Greatness:BAAALAAECgMICQAAAA==.Greeze:BAAALAADCggIEQAAAA==.Grimwrath:BAACLAAFFIEJAAILAAQIrCJVAACUAQALAAQIrCJVAACUAQAsAAQKgRkAAgsACAihJkIAAIkDAAsACAihJkIAAIkDAAAA.Grizzy:BAAALAAECgMIAwAAAA==.',Gu='Gulluulanu:BAAALAADCgIIAwABLAAECgIIAgADAAAAAA==.',Gw='Gwendilyn:BAAALAADCggIDwAAAA==.',Gy='Gyndrinolara:BAAALAAECgUIBwAAAA==.Gyomei:BAAALAADCgMIBAAAAA==.',Ha='Hakkel:BAAALAADCgcIDAAAAA==.Haliya:BAAALAADCggIAwAAAA==.Hazeluff:BAAALAADCggICwAAAA==.',He='Hellfate:BAAALAAECgYIDAAAAA==.Hellron:BAAALAADCgcIEgAAAA==.Hexokinase:BAAALAADCggICAAAAA==.Hexou:BAAALAAECgcIDgAAAA==.',Hi='Hikiru:BAAALAAECggIBgAAAA==.',Hk='Hkinc:BAAALAADCgYIBgABLAAECgMIBgADAAAAAA==.',Ho='Horick:BAAALAAECgcIDAAAAA==.',Hr='Hruan:BAAALAAECgMIAwAAAA==.',Hy='Hypnôtoâd:BAAALAADCgcIBgABLAAECgQIBAADAAAAAA==.',['Hè']='Hèbe:BAAALAADCgcICwABLAAECgUIBQADAAAAAA==.',Ia='Iamatank:BAAALAADCgQIAgAAAA==.Iamstronge:BAAALAAECgYIDAAAAA==.',Il='Illydan:BAAALAAECgIIAgAAAA==.',In='Incinetater:BAAALAADCggIFgAAAA==.Infectedmush:BAAALAADCggICAAAAA==.Inmortem:BAAALAADCgIIAgABLAAECgUIBAADAAAAAA==.Inquisition:BAACLAAFFIEFAAIIAAMIOBvzAAAAAQAIAAMIOBvzAAAAAQAsAAQKgRgAAggACAhkJFgBADsDAAgACAhkJFgBADsDAAAA.Invisiweave:BAAALAAECgYICQAAAA==.',It='Itai:BAAALAAECgcIEAAAAA==.Itchynipps:BAAALAAECgIIBAAAAA==.Itsdone:BAAALAAECgEIAQABLAAECgYIDQADAAAAAA==.Itswheats:BAAALAADCggIFAABLAAECgEIAQADAAAAAA==.',Ja='Jadefists:BAAALAADCgQIBAAAAA==.Jasmonk:BAAALAAECgQIBwAAAA==.',Je='Jeniko:BAAALAAECgIIAgAAAA==.',Jo='Joey:BAAALAADCgcIAwAAAA==.Jorhel:BAAALAAECgYIDAAAAA==.',Ju='Jumbles:BAAALAADCggIDwAAAA==.',Jy='Jynxy:BAAALAADCgYICAAAAA==.',['Já']='Jáydn:BAAALAADCgIIAgAAAA==.',['Jä']='Jäyna:BAABLAAECoEVAAIMAAgIdhzeDQCIAgAMAAgIdhzeDQCIAgAAAA==.',['Jø']='Jøshu:BAAALAADCgMIAwAAAA==.',Ka='Kacsuhcyr:BAAALAADCgcICQAAAA==.Kaeya:BAAALAAECgMIBQAAAA==.Kalletsu:BAAALAADCggIDgAAAA==.Kalvis:BAAALAADCgcIDgAAAA==.Katatonik:BAAALAADCgYIBgAAAA==.Kate:BAAALAADCgYICAABLAAECgcIEAADAAAAAA==.Katebkinsale:BAAALAAECgYIDAABLAAECgcIEAADAAAAAA==.Katedolores:BAAALAAECgcIEAAAAA==.Katrein:BAAALAADCggICwAAAA==.',Kb='Kbeckinsale:BAAALAAECgUICAABLAAECgcIEAADAAAAAA==.Kbw:BAAALAAECgMIBQAAAA==.',Kd='Kdh:BAAALAADCggICAABLAAECggIAQADAAAAAA==.',Ke='Keket:BAAALAADCgEIAQAAAA==.Keladun:BAAALAADCgUIAgAAAA==.Kemosawbe:BAAALAADCgcIBwAAAA==.Keseraya:BAAALAADCgcICgAAAA==.',Kh='Khonan:BAAALAAECgMIBQAAAA==.',Ki='Kiamar:BAAALAAECgEIAQAAAA==.Kidrix:BAAALAADCgcIBwAAAA==.Kijyo:BAAALAAECgMIAwAAAA==.Killabill:BAAALAADCgcICwAAAA==.Killian:BAAALAADCgYIDAAAAA==.Kilroc:BAAALAAECgUICAAAAA==.Kinilaw:BAAALAADCgMIAwAAAA==.Kishak:BAAALAAECgIIAgAAAA==.',Kk='Kkura:BAAALAAECgMIBAAAAA==.',Kn='Kníght:BAAALAADCgQIBAAAAA==.',Ko='Koderazarke:BAAALAADCgMIAwAAAA==.Kompulsive:BAAALAAECgIIAwAAAA==.',Kr='Krayolacat:BAAALAADCgUIBgAAAA==.Kröw:BAAALAAECgIIAgAAAA==.',Ku='Kudrix:BAAALAAECgQIBQAAAA==.Kurø:BAAALAAECgYIDQAAAA==.Kuzco:BAAALAADCgcICAAAAA==.',['Kà']='Kàri:BAAALAAECgcIDQAAAA==.',La='Laurijaydn:BAAALAAECgcIDAAAAA==.Laurynn:BAAALAADCggIFgAAAA==.Lauríe:BAAALAAECgEIAQAAAA==.',Le='Lefty:BAAALAADCggICAAAAA==.Lelink:BAAALAADCgEIAQAAAA==.Leowo:BAAALAADCgYIBgAAAA==.',Li='Liath:BAAALAADCggICAAAAA==.Liechtenauer:BAAALAAECgYIBwAAAA==.Lightlana:BAAALAAECgYIBgAAAA==.Lilchamp:BAAALAADCgQIAwABLAAECgcICwADAAAAAA==.Littlestarz:BAAALAAECgYIBgAAAA==.Lizzieag:BAEALAAECgYICwAAAA==.',Lo='Lockyshepard:BAAALAADCggIEAAAAA==.Locopoco:BAEALAAECgYICQAAAA==.Lohueng:BAAALAAECgYICQAAAA==.Lokung:BAAALAAECgYICQAAAA==.Lootah:BAAALAADCgYIBgAAAA==.',Lu='Lucielle:BAAALAAECgMIBAAAAA==.Lucifurr:BAAALAAECgIIAgAAAA==.Luke:BAAALAAECggIDAAAAA==.Luminali:BAAALAADCgEIAQAAAA==.Luxst:BAAALAADCggIEAAAAA==.',Ly='Lyxon:BAAALAADCgcIFAAAAA==.',Ma='Magnanimity:BAEALAADCggICwAAAA==.Malzahar:BAAALAAECgMIBAAAAA==.Marilag:BAAALAADCgUIBQAAAA==.Maximillian:BAAALAADCgEIAQAAAA==.',Me='Meatbomb:BAAALAADCgcICwAAAA==.Medizine:BAAALAADCgcIBwAAAA==.Medleys:BAAALAADCgcIBwAAAA==.Memorypearl:BAAALAADCgcIBwAAAA==.Mendietta:BAAALAAECgIIBAAAAA==.Meochung:BAAALAAECgYICwAAAA==.Meowi:BAAALAAECgIIAgAAAA==.Metus:BAAALAAECgYICQAAAA==.',Mi='Miistral:BAAALAAECgMIAwAAAA==.Minisid:BAAALAAECgYIEQAAAA==.Minki:BAAALAAECgYICAAAAA==.Mistinmae:BAAALAADCgYIBgABLAAECgIIAgADAAAAAA==.Mistrjenkins:BAAALAADCgcIAwAAAA==.',Mo='Mokotrize:BAAALAAECgYIBwAAAA==.Montivarius:BAAALAADCggIDwAAAA==.Moodangjones:BAAALAADCgYIBgAAAA==.Mootation:BAAALAADCggIDwAAAA==.Mordred:BAAALAAECggIBgAAAA==.',Mu='Murlooze:BAAALAADCggICAAAAA==.Mustachee:BAAALAADCgYICAAAAA==.',Na='Naarf:BAAALAADCggIDAABLAAECgMIAwADAAAAAA==.Naku:BAAALAADCggICAAAAA==.Nanoko:BAAALAADCgIIAgAAAA==.Nappyjay:BAAALAAECgUIBQAAAA==.Nasha:BAAALAADCgYIBgAAAA==.Nayaelements:BAAALAADCgQIBAAAAA==.Nayasylpha:BAAALAAECgcIEQAAAA==.',Ne='Neuro:BAAALAAECgcIDgAAAA==.',Ni='Nightevolved:BAABLAAECoEUAAINAAcIUyAgEQB+AgANAAcIUyAgEQB+AgAAAA==.Nightfaze:BAAALAAECgYICQAAAA==.Nitefall:BAAALAAECgMIBAAAAA==.',No='Nootella:BAAALAADCggIEAAAAA==.Notionalheal:BAAALAADCgIIAgAAAA==.',Ny='Nymphía:BAAALAADCggIDgABLAAECgcIDgADAAAAAA==.',['Nî']='Nîco:BAAALAAECgYIEAAAAA==.',Oc='Octin:BAAALAAECgYICQAAAA==.',Ok='Okowilly:BAAALAAECgEIAQAAAA==.',On='Onafudabibbl:BAAALAADCgIIAgAAAA==.',Oo='Oonaki:BAAALAAECgcIDQAAAA==.',Ot='Othin:BAAALAAECgEIAQAAAA==.Ottocon:BAAALAADCgYIBgAAAA==.',Ou='Ourbad:BAAALAADCggICAAAAA==.',Pa='Pakost:BAAALAADCgcIBwAAAA==.Pallyboar:BAAALAAECgQIBgAAAA==.Pallypig:BAAALAAECgQIAwAAAA==.Papagenu:BAAALAAECgYICAAAAA==.Parlay:BAAALAADCgYIBgAAAA==.',Pi='Pichael:BAAALAAECgIIAgAAAA==.',Po='Pointybrows:BAAALAADCgUIBQAAAA==.Powerflower:BAAALAAECgMIAwAAAA==.',Pr='Primerecall:BAAALAAECgYICQAAAA==.Prowl:BAAALAAECgQIBAABLAAFFAMIBQAIADgbAA==.Prudeix:BAAALAADCgcICAAAAA==.',Pu='Punklockbeak:BAAALAAECgUIBQABLAAECgYIDQADAAAAAA==.',Qu='Quikkmex:BAAALAADCgIIAgAAAA==.',Ra='Radhound:BAAALAAECgQIBAAAAA==.Rakuun:BAAALAADCggICAAAAA==.Randomdude:BAAALAADCgEIAgAAAA==.Raptormortis:BAAALAAECgYICgAAAA==.Rayhawk:BAAALAADCggIEAAAAA==.Raylen:BAAALAADCggIDwAAAA==.',Re='Recharge:BAAALAADCggIBAAAAA==.Refusaltodie:BAAALAAECgcIDwAAAA==.Retrisan:BAAALAAECgYIDAAAAA==.',Rh='Rhinn:BAAALAADCgcIFAAAAA==.',Ri='Rickypeepee:BAAALAADCgcIDgAAAA==.Ritsui:BAAALAAECgEIAQAAAA==.Ritsuio:BAAALAADCgIIAwAAAA==.Ritsuri:BAAALAAECgEIAQAAAA==.',Ro='Roastedz:BAAALAADCgYIBwAAAA==.Robmagetat:BAAALAADCggIFQAAAA==.Rojen:BAAALAADCgcIBwAAAA==.Rorthu:BAAALAADCggIDwAAAA==.Roru:BAAALAAECgMIAwAAAA==.Rou:BAAALAADCggIDAAAAA==.',Ru='Rukias:BAAALAADCggICAAAAA==.Rukélie:BAAALAADCgcIBwAAAA==.',Sa='Sana:BAAALAAECgcIDgAAAA==.Sanlorastik:BAAALAADCgcIBwAAAA==.Sapthedad:BAAALAADCggICAAAAA==.Sarayu:BAAALAADCgcIFAAAAA==.Sarzen:BAAALAAECgMIBQAAAA==.',Sc='Scarllett:BAAALAAECgYICQAAAA==.Scorpyon:BAAALAADCgEIAQAAAA==.Scrytearia:BAAALAADCgYIBgAAAA==.',Se='Seniorpenny:BAAALAADCgQIBAAAAA==.Serenade:BAAALAAECgYIDQAAAA==.',Sh='Shabbs:BAAALAAECgMIAwAAAA==.Shabbyy:BAAALAADCggICgAAAA==.Shadowpump:BAAALAAECgYICQAAAA==.Shalais:BAAALAAECgEIAQAAAA==.Shamsel:BAAALAAECgIIAgAAAA==.Shaunpj:BAAALAAECgYIBgAAAA==.Shobogenzo:BAAALAAECgUIBQAAAA==.Shockcaller:BAAALAAECgUICwAAAA==.',Si='Simmara:BAAALAAECgYICAAAAA==.Sinner:BAEBLAAECoEXAAQOAAgIQwkfIgCUAQAOAAgIQwkfIgCUAQAPAAQI6wpWNwC/AAAQAAMITwKYEgB1AAAAAA==.Siøk:BAAALAADCggIDwAAAA==.',Sk='Skywalkah:BAAALAADCgMIAwAAAA==.',Sl='Slamuraijack:BAAALAADCgYIBgAAAA==.Slyvna:BAAALAADCggIEAAAAA==.',So='Solstica:BAAALAADCgUIBQAAAA==.',Sp='Spazzis:BAAALAADCgcIBwAAAA==.Spiritualone:BAAALAAECgEIAQAAAA==.',Sq='Squirt:BAAALAAECgIIAQAAAA==.',St='Stabbysoul:BAAALAADCgYIBgAAAA==.Stienman:BAAALAADCgIIAgAAAA==.Stonystark:BAAALAADCgcIBwAAAA==.Stormspeed:BAAALAADCgQIBAAAAA==.Straam:BAAALAAECgYIBwAAAA==.Stupiddk:BAAALAAECgEIAQAAAA==.Stupiddruid:BAAALAADCgYIDAAAAA==.Støney:BAAALAADCggICAAAAA==.',Su='Subtractive:BAABLAAECoEYAAMFAAcI0CM8BgBrAgAFAAYIqyQ8BgBrAgARAAMIgR+WNQDyAAAAAA==.Suiiciide:BAAALAADCgUIBQAAAA==.Suitedhunt:BAAALAAECgYICAAAAA==.Surani:BAAALAAECgMIAwAAAA==.',Sy='Sylerokos:BAAALAADCggIEgAAAA==.',['Så']='Såcred:BAAALAAECgEIAQAAAA==.',Ta='Takoi:BAAALAADCgcICAAAAA==.Talethia:BAAALAAECgYICQAAAA==.Talusian:BAAALAADCggICAAAAA==.Tamsîn:BAAALAAECgYICAAAAA==.Tarbara:BAAALAADCggICwAAAA==.Tarecgosa:BAAALAADCgEIAQABLAAECgIIAgADAAAAAA==.',Tb='Tbonez:BAAALAADCgcIFAAAAA==.',Te='Testmanfour:BAAALAADCgIIAgAAAA==.',Th='Thoorz:BAAALAAECgMIAwAAAA==.Thorzy:BAAALAADCgcICwABLAAECgMIAwADAAAAAA==.Thotter:BAAALAADCgcIDgAAAA==.Thraxacious:BAAALAAECgUIBwAAAA==.Thulcandra:BAAALAAECgMIBgAAAA==.Thulsadoomm:BAAALAAECgIIAgAAAA==.Thundermay:BAAALAAECgIIAgAAAA==.',Ti='Tiff:BAAALAADCgMIAwAAAA==.Tigris:BAAALAADCgUIBQAAAA==.Tigó:BAAALAAECgMIAwAAAA==.Tiik:BAAALAADCgcIFAAAAA==.Tireliaa:BAAALAAECgMIBgAAAA==.Tisem:BAAALAADCggICAAAAA==.',To='Tolkien:BAAALAAECgEIAQAAAA==.Toyotathon:BAAALAADCggIEQAAAA==.',Tr='Tragrax:BAAALAADCgcIBwAAAA==.Travishead:BAAALAAECgIIAgAAAA==.Trìps:BAAALAADCgQIBAABLAAECgIIAwADAAAAAA==.',Ty='Tydz:BAAALAAECgYIBwAAAA==.',Ua='Uafraidofme:BAAALAADCgUIBwAAAA==.',Ud='Uddertrouble:BAEALAADCggIAQABLAADCggICwADAAAAAA==.',Ul='Ulfghar:BAAALAADCggIDwAAAA==.',Um='Umotherfathe:BAAALAADCgQIBAABLAAECgMIBgADAAAAAA==.',Un='Uncletat:BAAALAAECgYIDAAAAA==.Unex:BAAALAADCgcIBwAAAA==.Unholytiran:BAAALAADCgMIAwAAAA==.Unopunch:BAAALAAECgIIAgAAAA==.',Ur='Urmami:BAAALAAECgYICgAAAA==.',Vc='Vcautionzz:BAAALAADCgEIAQAAAA==.',Ve='Vengeta:BAAALAAECgYIDAAAAA==.Versa:BAAALAADCgYIDQAAAA==.',Vi='Vitaminn:BAAALAAECgYIDAAAAA==.',Vl='Vlaen:BAAALAADCgYIBgAAAA==.',Vo='Voidgasm:BAAALAAECgYIBgAAAA==.Vorxx:BAAALAADCgUIBQAAAA==.',Vy='Vynagosa:BAAALAADCgYICgAAAA==.Vyndrith:BAAALAAECgMIBAAAAA==.Vynni:BAAALAADCgEIAQAAAA==.Vynora:BAAALAAECgEIAQAAAA==.Vyrse:BAAALAAECgcIBwAAAA==.',Wa='Wafflez:BAAALAAECgIIAgAAAA==.Warpstrike:BAAALAADCgcICAAAAA==.Waypoint:BAAALAAECgEIAQAAAA==.',We='Welios:BAAALAAECgUICAAAAA==.',Wh='Whisa:BAAALAAECgQIBgAAAA==.Whiteliter:BAAALAADCgcIDgAAAA==.',Wi='Wildboar:BAAALAADCgcIBwAAAA==.Wildwolff:BAAALAADCggIDgAAAA==.Wilhedin:BAABLAAECoEbAAMEAAcIzSNNAQDBAgAEAAcIpyNNAQDBAgARAAYIwiLtEQBEAgAAAA==.Winton:BAAALAADCgUIBQAAAA==.',Wu='Wulfnbolt:BAAALAADCgcIFgAAAA==.',Wy='Wyon:BAAALAAECgYICQAAAQ==.',Xs='Xsun:BAAALAAECgYIDAAAAA==.',Ya='Yabai:BAAALAADCggICAABLAAECgcIEAADAAAAAA==.Yams:BAAALAAECgMIAwAAAA==.',Yu='Yukkionna:BAAALAADCgQIBQAAAA==.',Za='Zailen:BAAALAADCgYIBgAAAA==.Zandrial:BAAALAAECgYIDAAAAA==.Zanzer:BAAALAADCgcIBwAAAA==.Zathara:BAAALAAECgYICQAAAA==.Zavvier:BAAALAADCgUIBQAAAA==.',Ze='Zeppee:BAAALAAECgEIAQAAAA==.Zeshlock:BAAALAAECgcIDQAAAA==.Zeshom:BAAALAADCggICAAAAA==.',Zi='Zitrobd:BAAALAAECgEIAQAAAA==.',Zu='Zuluk:BAAALAADCgYIBgAAAA==.',['Ób']='Óbzedat:BAAALAADCggICAABLAAECgQIBAADAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end