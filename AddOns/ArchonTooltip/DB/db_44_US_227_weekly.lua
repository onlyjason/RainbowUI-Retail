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
 local lookup = {'Unknown-Unknown','Warrior-Fury','Mage-Arcane',}; local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abeon:BAAALAAECgUIBgAAAA==.',Ae='Aetus:BAAALAAECgMIAwAAAA==.',Ag='Agoneer:BAAALAAECgEIAQAAAA==.',Ah='Ahnano:BAAALAADCgEIAQAAAA==.',Ak='Akeera:BAAALAADCggICAAAAA==.',An='Anaesthetize:BAAALAAECgEIAQAAAA==.Animagon:BAAALAADCgUIBQAAAA==.Animaker:BAAALAAECgYIDAAAAA==.',Ar='Archadeus:BAAALAAECgEIAQAAAA==.Ariannara:BAAALAADCgUIBAABLAADCggIDQABAAAAAA==.Arwen:BAAALAADCgQIBAAAAA==.',Ba='Bachadin:BAAALAAECgcICAAAAA==.Baerjin:BAAALAADCgcIBwAAAA==.Battlewagon:BAAALAADCgUIBQAAAA==.',Be='Bearlylisten:BAAALAAECgYIDgAAAA==.',Bo='Boompew:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Boujie:BAAALAADCgQIBAAAAA==.',Br='Brewdhism:BAAALAADCgMIAwABLAADCgcIDQABAAAAAA==.',Ca='Calamidade:BAAALAAECgYIDAAAAA==.Calandus:BAAALAAECgEIAQAAAA==.Carnelengua:BAAALAADCgMIAwAAAA==.',Ch='Chaoticprime:BAAALAADCgIIAwAAAA==.',Cl='Clal:BAAALAAECgQIBwAAAA==.Clother:BAABLAAECoEUAAICAAcI3iRkBwD0AgACAAcI3iRkBwD0AgAAAA==.',Cu='Curses:BAAALAAECgYIDAAAAA==.',Da='Darkrobin:BAAALAAECgMIBAAAAA==.',De='Decerto:BAAALAADCgEIAQABLAADCggIEgABAAAAAA==.Defafurry:BAAALAADCgIIAgAAAA==.',Do='Donkie:BAAALAAECgQIBgAAAA==.',Du='Dugkill:BAAALAAECgEIAQAAAA==.',Ed='Edd:BAAALAADCgcICQAAAA==.',Eg='Egrok:BAAALAADCgEIAQAAAA==.',Em='Emaeel:BAAALAAECgMIBQAAAA==.',Ez='Ezekiel:BAAALAADCgMIAwABLAAECgUIBQABAAAAAA==.',Fa='Faithful:BAAALAADCggIEAABLAAECgUIBQABAAAAAA==.',Fi='Firesoul:BAAALAADCgcICAAAAA==.',Fo='Foros:BAAALAAECgIIAgAAAA==.',Fr='Freezerburn:BAAALAADCgQIBAAAAA==.Fryiertuck:BAAALAAECgMIBQAAAA==.',Ge='Gendorosan:BAAALAAECgMIBQAAAA==.',Gi='Gigabyte:BAAALAAECgIIAgAAAA==.',Gr='Grayfoxx:BAAALAAECgMIBQAAAA==.',['Gô']='Gôôdbye:BAAALAAECgEIAQAAAA==.',Ha='Hate:BAAALAAECgUIBQAAAA==.',He='Hellstomper:BAAALAADCgMIAwAAAA==.',Hi='Highmoontain:BAAALAAECgUIBQAAAA==.',Ho='Homdal:BAAALAADCgcIBwAAAA==.',Hu='Hunna:BAAALAAECgIIAwAAAA==.Hurtzdonit:BAAALAADCgYIBgAAAA==.',Ig='Ignignok:BAAALAADCgcIBwAAAA==.',In='Inebriated:BAAALAADCgcIBwAAAA==.',Io='Iondia:BAAALAAECgQIBAAAAA==.',Ka='Kaname:BAAALAADCggIEQAAAA==.',Ke='Keliden:BAAALAAECgMIAwAAAA==.',Ki='Kirlo:BAAALAAECgEIAQAAAA==.',Ko='Kombu:BAAALAADCgMIBAAAAA==.',Kr='Kring:BAAALAAECgcIEAAAAA==.',Ks='Ksauce:BAAALAAECgMIBQAAAA==.',Ky='Kylli:BAAALAADCgEIAQAAAA==.Kynon:BAAALAAECgQIBgABLAAECgcIDgABAAAAAA==.Kyran:BAAALAAECgcIDgAAAA==.',La='Lathina:BAAALAADCggIDQAAAA==.',Li='Linta:BAAALAADCggIEgAAAA==.',Lo='Lokix:BAAALAAECgEIAQAAAA==.',Ma='Magikishi:BAAALAADCgcIBwAAAA==.Malifecent:BAAALAAECgcICwAAAA==.Marquista:BAAALAADCggIEAAAAA==.',Mc='Mcbébéchat:BAAALAADCgIIAgAAAA==.',Me='Merilinda:BAAALAADCgYIDAAAAA==.Merolance:BAAALAADCgYICgAAAA==.Mey:BAAALAAECgYIDQAAAA==.',Mi='Mitenalla:BAAALAAECggIDQAAAA==.',Mu='Muatahawa:BAAALAADCgMIAwAAAA==.',Na='Nagasake:BAAALAAECgIIAgAAAA==.',Ni='Nitrochrist:BAAALAAECgYIDAAAAA==.',No='Nordathair:BAAALAAECgEIAQAAAA==.Nori:BAACLAAFFIEFAAIDAAMIkSNlAgA2AQADAAMIkSNlAgA2AQAsAAQKgRYAAgMACAjAIjkLANYCAAMACAjAIjkLANYCAAAA.Nosathro:BAAALAADCggICgAAAA==.',['Nï']='Nïeko:BAAALAAECggICAAAAA==.',Or='Orecarke:BAAALAADCgcIDAAAAA==.Originals:BAAALAAECggIEgAAAA==.',Ov='Overcharge:BAAALAADCgQIBAAAAA==.',Pa='Pages:BAAALAAECgEIAQAAAA==.Parker:BAAALAADCgQIBgAAAA==.Parsemae:BAAALAAECgcIEQAAAA==.',Pe='Perta:BAAALAADCgcIDgAAAA==.',Pm='Pmsavenger:BAAALAADCggIDAAAAA==.',Po='Pooshot:BAAALAAECgcICgAAAA==.',Pr='Priestalisha:BAAALAAECgYIDwAAAA==.Priestyheals:BAAALAADCgUIBQAAAA==.',Py='Pyrite:BAAALAADCgQIBAAAAA==.',Ra='Raelana:BAAALAAECgEIAQAAAA==.Ragetatertot:BAAALAADCggICAAAAA==.Rawsteak:BAAALAADCggIDAAAAA==.Razdaz:BAAALAADCggICAAAAA==.',Re='Reheal:BAAALAAECgYIDAAAAA==.Reinlyn:BAAALAADCgYIBAAAAA==.Rengokuu:BAAALAADCgcICAAAAA==.',Ri='Rixxy:BAAALAAECggIEwAAAA==.',Ro='Roderigo:BAAALAADCgcIBwAAAA==.Rompetoto:BAAALAADCgUIBQAAAA==.',Ru='Ruslah:BAAALAADCggIEAAAAA==.',Sa='Saisaith:BAAALAAECggIEQAAAA==.Sauronn:BAAALAAECgcIDwAAAA==.Savadar:BAAALAAECgEIAQAAAA==.',Se='Sealyboi:BAAALAADCggIDQAAAA==.Serpeng:BAAALAAECgEIAQAAAA==.Setareh:BAAALAAECgIIAgAAAA==.',Sh='Shakira:BAAALAAECgIIAgAAAA==.Shakuru:BAAALAAECgQIBwAAAA==.Shanta:BAAALAADCgEIAQAAAA==.Shieldrobin:BAAALAAECgEIAQAAAA==.Shizari:BAAALAAECgEIAQAAAA==.Shkar:BAAALAAECggIDgAAAA==.Shokan:BAAALAADCgcIDQAAAA==.Shryke:BAAALAADCgYIBgAAAA==.',Sl='Slenderama:BAAALAADCgYICgAAAA==.Slenderella:BAAALAADCgIIAgAAAA==.',So='Sorenn:BAAALAAECgYIDgAAAA==.',St='Sthpicy:BAAALAADCgQIBAAAAA==.Stinkstink:BAAALAADCggIDAAAAA==.Striptotem:BAAALAAECgYICQAAAA==.Strongmandan:BAAALAADCggICAAAAA==.',Su='Sumbish:BAAALAAECgEIAQAAAA==.',Sw='Swaboom:BAAALAAECgIIAgAAAA==.',Ta='Talebios:BAAALAADCgcIFQAAAA==.',Th='Thhee:BAAALAAECgIIAwAAAA==.Thromx:BAAALAADCgEIAQAAAA==.Thumbelyna:BAAALAAECgIIAgAAAA==.Thunderhide:BAAALAADCgcICAAAAA==.',To='Towelp:BAAALAADCgcIBwAAAA==.',Tw='Twentÿfourk:BAAALAAECgEIAQAAAA==.',Ty='Tyeshall:BAAALAADCgYICwAAAA==.',Va='Valmette:BAAALAADCgcIBwAAAA==.Valtas:BAEALAADCggIDwABLAAECgYIBwABAAAAAA==.',Ve='Velleynyia:BAEALAAECgYIBwAAAA==.',Vy='Vynjashi:BAAALAADCggICAAAAA==.',Wa='Waghdaddy:BAAALAAECgUICAAAAA==.Wannatry:BAAALAADCgcIEAAAAA==.Wayya:BAAALAAECgMIBAAAAA==.',Wi='Wixxy:BAAALAAECgcICwAAAA==.',Wo='Wobiwabi:BAAALAADCgcIBwAAAA==.',Wr='Wratheon:BAAALAAECggIDgAAAA==.',Xa='Xablau:BAAALAADCgMIAwAAAA==.',['Xí']='Xí:BAAALAAECgMIAwAAAA==.',Ye='Yeli:BAAALAAECgEIAQAAAA==.',Zy='Zynaria:BAAALAADCggIDwAAAA==.',['Íl']='Íllenium:BAAALAAECgIIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end