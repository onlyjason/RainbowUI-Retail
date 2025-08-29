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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','Shaman-Enhancement','Warrior-Fury','Warrior-Protection','Evoker-Devastation','DeathKnight-Frost',}; local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aesthetik:BAAALAADCgcIBwAAAA==.',Ag='Agerax:BAAALAADCgEIAQABLAAECgUIBgABAAAAAA==.',Ai='Aiedel:BAAALAADCggIFwAAAA==.',Ar='Arelith:BAAALAADCggIDgAAAA==.Ariosx:BAAALAAECgUIBgAAAA==.Arisseda:BAAALAADCgMIAwAAAA==.Aru:BAAALAAECgcIDwAAAA==.',Au='Aurky:BAAALAADCgcICAAAAA==.',Av='Avah:BAAALAADCgMIAwAAAA==.',Ba='Bald:BAAALAADCggICAAAAA==.Balob:BAABLAAECoEWAAICAAgI3CRjAwA7AwACAAgI3CRjAwA7AwAAAA==.Bambooyeezus:BAAALAADCgYIBgAAAA==.Bandar:BAAALAADCgIIAwAAAA==.Barkbarkbark:BAAALAAECgMIAwAAAA==.',Bl='Blacksteve:BAAALAADCgMIAwAAAA==.',Bm='Bmxdh:BAAALAAECgMIBAAAAA==.',Bu='Bubblelove:BAAALAAECgMIAwAAAA==.Bubblohseven:BAAALAAECgYIBgAAAA==.Bubbly:BAAALAADCggICgAAAA==.Bufux:BAAALAADCggICAAAAA==.',Ca='Caelum:BAAALAADCgUIBgAAAA==.Carbonchaos:BAAALAAECgYIBgAAAA==.Carbondark:BAAALAAECgIIAgAAAA==.Carbonlight:BAAALAAECgMIBQAAAA==.Carbonsteel:BAAALAADCgIIAgAAAA==.',Ch='Chucklez:BAAALAAECgQIBAAAAA==.',Cl='Clickwerk:BAAALAADCgIIAgAAAA==.',Cu='Cursed:BAAALAAECgQIBQAAAA==.',De='Dezric:BAAALAADCgYIBgABLAADCgcIDQABAAAAAA==.',Dr='Draxxios:BAAALAAECgMIAwAAAA==.Dreadenfear:BAAALAADCggIDwAAAA==.Drowarchon:BAAALAADCgcIDgAAAA==.Drownix:BAAALAADCgIIAgABLAADCgcIDgABAAAAAA==.',Dy='Dynamis:BAAALAAECgMIBgAAAA==.',El='Elli:BAAALAAECgYIDAAAAA==.Elnaris:BAAALAAECgMIBAAAAA==.',Eo='Eon:BAAALAAECgMIBQAAAA==.',Er='Eriu:BAAALAAECgEIAQABLAAECgUIBgABAAAAAA==.',Fa='Fate:BAAALAADCgIIAgAAAA==.',Fr='Fraudexposer:BAABLAAECoEWAAIDAAgIcyYTAACKAwADAAgIcyYTAACKAwAAAA==.',['Fû']='Fûran:BAAALAAECgIIAgAAAA==.',['Fü']='Füran:BAAALAAECgMIBwAAAA==.',Gi='Giltordon:BAAALAAECgYICwAAAA==.Gitzi:BAAALAAECgcIEAAAAA==.',Gl='Glaciea:BAAALAAECgMIBAAAAA==.',Gr='Greasytotems:BAAALAAECgMIAwAAAA==.Greyswtpnts:BAAALAADCgMIBgAAAA==.',Gy='Gypsytears:BAAALAAECgEIAQAAAA==.',He='Heartt:BAAALAADCgcIBwAAAA==.',Ho='Holyperineum:BAAALAADCgcIBwABLAAECgcIDQABAAAAAA==.Hordend:BAAALAAECgIIAgAAAA==.',In='Inogoldfarm:BAAALAADCgMIAwAAAA==.',Ji='Jimbukknik:BAAALAADCgIIAgAAAA==.',Jr='Jrbacnchee:BAAALAAECgIIBAAAAA==.Jrbaconcheze:BAAALAADCgcIBwAAAA==.',Ju='Julix:BAAALAAECgIIAgAAAA==.',Ka='Kainicus:BAAALAAECgcIEAAAAA==.Kalisa:BAAALAADCgcIDgAAAA==.Kaylenna:BAAALAADCgQICAAAAA==.',Ke='Keoni:BAAALAAECgMIBQAAAA==.',Ki='Kitsyune:BAAALAAECgIIAgAAAA==.',Kr='Krawl:BAAALAADCgEIAQAAAA==.Krya:BAAALAADCgYIBwAAAA==.',Kw='Kwansa:BAAALAADCgcIDQAAAA==.',Ky='Kylito:BAAALAADCgYIBgAAAA==.',La='Lanadra:BAAALAADCgIIAgAAAA==.',Le='Lesíon:BAAALAADCgIIAgAAAA==.',Li='Lithli:BAAALAADCgQIBAAAAA==.',Lu='Luminusrayne:BAAALAAECgcIDgAAAA==.',Me='Meheret:BAAALAAECgcIDgAAAA==.Mero:BAAALAAECgMIBQAAAA==.',Mo='Moosey:BAAALAADCgIIAgAAAA==.',Mu='Munt:BAAALAAECgcIEgAAAA==.',My='Mystx:BAAALAAECgIIAgABLAAECgUIBgABAAAAAA==.Mythx:BAABLAAECoESAAMEAAcI8Bk2FgAQAgAEAAcI8Bk2FgAQAgAFAAEITAluMQAqAAAAAA==.',Na='Nami:BAAALAAECgQIBgAAAA==.Nartik:BAAALAADCggIDQAAAA==.',Ne='Nercyl:BAAALAADCgQIBAAAAA==.',Ni='Nilari:BAAALAADCggICAAAAA==.',No='Nordsnipe:BAAALAAECgUIBQAAAA==.Nostrildamus:BAAALAAECgcIEAAAAA==.',Ow='Owls:BAAALAAECgcIDwAAAA==.',Pi='Pillidan:BAAALAADCgYICAAAAA==.',Pr='Prayforme:BAAALAADCgUIBQAAAA==.Prayxx:BAAALAADCgYICQAAAA==.Presterjon:BAAALAADCgcIBwAAAA==.Priests:BAAALAAECgIIAgAAAA==.Proved:BAAALAAECgYICgAAAA==.',Pu='Puddingface:BAAALAAECgcIDQAAAA==.Puggar:BAAALAADCgUIBQAAAA==.',Re='Regerax:BAAALAADCgIIAgABLAAECgUIBgABAAAAAA==.Rek:BAAALAAECgUIBwAAAA==.Rendani:BAAALAADCgEIAQAAAA==.Rez:BAAALAAECgMIAwAAAA==.',Rh='Rhalger:BAAALAAECgEIAQAAAA==.Rhysan:BAAALAAECgcIDgAAAA==.',Ro='Robonord:BAAALAAECgMIAwAAAA==.Rougaroux:BAAALAAECgEIAQAAAA==.',Ru='Rude:BAAALAADCgcIBwAAAA==.',Ry='Rynhart:BAAALAADCggICAAAAA==.Ryugen:BAAALAAECgcIDgAAAA==.Ryushi:BAAALAADCggICAAAAA==.',Sa='Sacerdote:BAAALAADCggICAAAAA==.Sandara:BAAALAADCggICAAAAA==.',Se='Sebnoth:BAAALAAECgMIBQAAAA==.',Sh='Shaconis:BAAALAAECgIIAgAAAA==.Shamillion:BAAALAADCgIIAgABLAAECgcIEAABAAAAAA==.Shammich:BAAALAAECggIAQAAAA==.',Si='Sidepiece:BAAALAAECgIIAgAAAA==.',St='Stinkyboy:BAAALAADCggIDgAAAA==.',Su='Sunwa:BAAALAADCggICQABLAAECgUIBgABAAAAAA==.',['Sí']='Sírvívor:BAAALAADCgMIAwAAAA==.',['Sï']='Sïmba:BAAALAADCgcIBwAAAA==.',Ta='Taulia:BAAALAADCgcIBwAAAA==.',To='Tool:BAAALAAECgMIAwABLAAECgYICwABAAAAAA==.Tooms:BAAALAAECgYICQAAAA==.Touchi:BAAALAAECgQIBgAAAA==.',Tr='Tripleclaw:BAAALAADCggICwAAAA==.Truck:BAAALAAECgQIBAABLAAECgcIEAABAAAAAA==.',Va='Valksmash:BAAALAAECgIIAgAAAA==.',Ve='Velas:BAAALAADCgMIAwAAAA==.',Vo='Voutecomer:BAAALAADCgYICAAAAA==.',Wa='Wariür:BAAALAAECgMIAgAAAA==.',Wi='Wingedlizard:BAACLAAFFIEFAAIGAAMIOCHVAQAiAQAGAAMIOCHVAQAiAQAsAAQKgRUAAgYACAg6I+UDAAsDAAYACAg6I+UDAAsDAAAA.',Xs='Xsi:BAAALAAECgMIBgAAAA==.',Yo='Yogurt:BAAALAAECgIIAgAAAA==.',Za='Zazuu:BAAALAAECgMIAwAAAA==.',Zh='Zhal:BAAALAAECgIIAgAAAA==.Zhalentine:BAABLAAECoEcAAIHAAgI2R5WCwDHAgAHAAgI2R5WCwDHAgABLAAECgIIAgABAAAAAA==.Zhuwu:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end