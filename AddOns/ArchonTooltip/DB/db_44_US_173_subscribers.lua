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
 local lookup = {'Monk-Brewmaster','Unknown-Unknown','Mage-Arcane','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Holy','Shaman-Elemental','Priest-Shadow','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Havoc','Shaman-Restoration','Paladin-Retribution',}; local provider = {region='US',realm='Proudmoore',name='US',type='subscribers',zone=44,date='2025-08-29',data={Ak='Akzari:BAEALAADCggIAQAAAA==.',Al='Alaskannatif:BAEALAAECggIEQAAAA==.Allthatjazz:BAECLAAFFIEFAAIBAAMIVAwfAgDPAAM5DAAAAgA1ADsMAAABABgAOgwAAAIAEAABAAMIVAwfAgDPAAM5DAAAAgA1ADsMAAABABgAOgwAAAIAEAAsAAQKgRsAAgEACAhlHbcEAHYCAAEACAhlHbcEAHYCAAAA.Altercations:BAEALAAECgYIBgABLAAECggIDgACAAAAAA==.',Ap='Apsmage:BAECLAAFFIEFAAIDAAMIQSKcAgAuAQM5DAAAAgBOADsMAAABAFYAOgwAAAIAYgADAAMIQSKcAgAuAQM5DAAAAgBOADsMAAABAFYAOgwAAAIAYgAsAAQKgRkAAgMACAjJJlsAAIgDAAMACAjJJlsAAIgDAAAA.',Ar='Arcies:BAEALAAECgMIBAAAAA==.Armyofme:BAEALAAECgcIEAAAAA==.',As='Aspir:BAEALAAECgYICAAAAA==.Aspèn:BAEALAAECgMIBAABLAAECggIEgACAAAAAA==.',Ba='Balefîre:BAEALAAECgYIEQABLAAFFAMIBQAEACoVAA==.',Be='Bearzo:BAEALAAECgcIDQAAAA==.',Bh='Bhujamga:BAEALAADCggICAABLAAECgUIBgACAAAAAA==.',Bl='Blacksesame:BAEALAADCggIFAAAAA==.Blisskiller:BAEALAAECgEIAQABLAAECgMIBgACAAAAAA==.',Bo='Bossonova:BAEALAADCgYIBgABLAAECgMIAwACAAAAAA==.',Bu='Bussybolt:BAEBLAAECoEWAAQFAAgIsCLsCgCcAgg5DAAAAwBjADsMAAADAGIAOgwAAAMAYAA8DAAAAwBZADIMAAADAFYAPQwAAAMAYQA+DAAAAgA3AD8MAAACAFYABQAHCD4i7AoAnAIHOQwAAAIAYwA7DAAAAgBiADwMAAACAFkAMgwAAAIAVgA9DAAAAgBhAD4MAAACADcAPwwAAAIAVgAGAAMI7SHcIQAMAQM6DAAAAwBgADwMAAABAFAAPQwAAAEAUwAHAAMIWRhsFADrAAM5DAAAAQBFADsMAAABAEUAMgwAAAEAMAAAAA==.',Ca='Caamm:BAEALAAFFAEIAQAAAA==.Carynna:BAEALAAFFAIIAgABLAAFFAUICQAIADIaAA==.',Co='Cobalamine:BAEALAADCggICAABLAAECggIIAAJAOocAA==.Coralirodeth:BAEBLAAECoEWAAIKAAgIVBtVCwCQAgg5DAAAAwBbADsMAAADAE0AOgwAAAMARgA8DAAAAwBKADIMAAADAE4APQwAAAMARwA+DAAAAgA1AD8MAAACACoACgAICFQbVQsAkAIIOQwAAAMAWwA7DAAAAwBNADoMAAADAEYAPAwAAAMASgAyDAAAAwBOAD0MAAADAEcAPgwAAAIANQA/DAAAAgAqAAAA.',De='Decototem:BAEALAAECgMIAwAAAA==.Deliriums:BAEALAAECgcIEAABLAAFFAUICAAFAIEPAA==.Deprecated:BAEALAAECgYIDAAAAA==.',Ec='Ecksblaster:BAEALAAECggICwABLAAFFAQICAALALgfAA==.Ecksfever:BAEBLAAFFIEIAAILAAQIuB+pAACXAQQ5DAAAAwBTADsMAAABAD8AOgwAAAMAXQA9DAAAAQBUAAsABAi4H6kAAJcBBDkMAAADAFMAOwwAAAEAPwA6DAAAAwBdAD0MAAABAFQAAAA=.',Ef='Effe:BAEALAAECggICAAAAA==.',Eg='Egirlrogue:BAEBLAAECoEdAAMMAAgIwh+0BQDeAgg5DAAABABaADsMAAAEAGEAOgwAAAUAVgA8DAAABABFADIMAAADAFsAPQwAAAQAXwA+DAAAAwBTAD8MAAACACMADAAICBwftAUA3gIIOQwAAAMAWgA7DAAAAwBhADoMAAAEAFYAPAwAAAIARAAyDAAAAwBbAD0MAAADAF8APgwAAAIAUwA/DAAAAQAXAA0ABwgUGQoEABsCBzkMAAABAFAAOwwAAAEAVAA6DAAAAQBDADwMAAACAEUAPQwAAAEAVQA+DAAAAQAaAD8MAAABACMAAAA=.',Eq='Equinnóx:BAEALAAECggIEgAAAA==.',Er='Eremitt:BAEALAADCgYIBgABLAAECgQIBwACAAAAAA==.',Gl='Glaivegoon:BAEALAAECgEIAQABLAAECgIIAgACAAAAAA==.',Gu='Gummidk:BAEALAAECgUIBQABLAAECggIGQAKAAsfAA==.Gummishadow:BAEBLAAECoEZAAIKAAgICx8HCQC6Agg5DAAABABhADsMAAAEAE8AOgwAAAMATQA8DAAAAwA/ADIMAAADAFMAPQwAAAQAXwA+DAAAAwBXAD8MAAABADIACgAICAsfBwkAugIIOQwAAAQAYQA7DAAABABPADoMAAADAE0APAwAAAMAPwAyDAAAAwBTAD0MAAAEAF8APgwAAAMAVwA/DAAAAQAyAAAA.',Ha='Hantevoker:BAEALAADCggIFgABLAAECgIIAgACAAAAAA==.',Hu='Huddie:BAEBLAAECoEVAAMDAAgIJiEkEQCTAgg5DAAAAwBaADsMAAADAGIAOgwAAAMAVwA8DAAAAwA5ADIMAAADAFoAPQwAAAMAYQA+DAAAAgBgAD8MAAABADsAAwAHCEYgJBEAkwIHOQwAAAIAUQA7DAAAAwBiADoMAAADAFcAPAwAAAIAOQAyDAAAAgBaAD0MAAABAEAAPgwAAAIAYAAOAAUIkhxEFgB/AQU5DAAAAQBaADwMAAABADMAMgwAAAEAQwA9DAAAAgBhAD8MAAABADsAAAA=.',Ic='Icewîng:BAECLAAFFIEFAAIEAAMIKhUNAwAMAQM5DAAAAgBMADsMAAABADQAOgwAAAIAIQAEAAMIKhUNAwAMAQM5DAAAAgBMADsMAAABADQAOgwAAAIAIQAsAAQKgRsAAgQACAjYJOwEACADAAQACAjYJOwEACADAAAA.',Jo='Jombola:BAEALAAECgUIBgAAAA==.',Ju='Judson:BAEALAAECgcIDQAAAA==.',Ka='Kalazar:BAECLAAFFIEKAAIPAAUIoSEQAAAjAgU5DAAAAwBiADsMAAACAGMAOgwAAAMAXQA8DAAAAQAxAD0MAAABAFkADwAFCKEhEAAAIwIFOQwAAAMAYgA7DAAAAgBjADoMAAADAF0APAwAAAEAMQA9DAAAAQBZACwABAqBFQADDwAICE4jJAYAAQMADwAICC4jJAYAAQMAEAACCOIjezIAyQAAAAA=.Kaosistine:BAEALAAECgEIAQAAAA==.Karurael:BAEALAAECgEIAQABLAAECggIDAACAAAAAA==.Kaykó:BAEALAAECgIIAgABLAAECgcIDgACAAAAAA==.',Kn='Knifeman:BAEALAADCgYIBgABLAAECgIIAgACAAAAAA==.',Kr='Kraite:BAEALAAECgUICAAAAA==.',Le='Leatherlad:BAEALAADCgcIBwABLAAECgIIAgACAAAAAA==.',Lu='Luciferin:BAEALAAECgIIAgAAAA==.',Ly='Lynkalla:BAEALAAECgMIBAAAAA==.Lynmakara:BAEALAADCggIEAABLAAECgMIBAACAAAAAA==.',Me='Meddah:BAEALAAECgMIBAAAAA==.Merl:BAEALAADCggIEAABLAAFFAMIBQARAFMjAA==.',Mh='Mhitra:BAEALAAECgYICAABLAAECggIFAALAMkiAA==.',Mo='Moltrøn:BAEALAADCggIFgABLAAECggIFQALALwjAA==.Moltøn:BAEBLAAECoEVAAILAAgIvCOOBAAqAwg5DAAAAwBjADsMAAADAGMAOgwAAAMAVAA8DAAAAwBQADIMAAADAGEAPQwAAAMAYQA+DAAAAgBQAD8MAAABAFsACwAICLwjjgQAKgMIOQwAAAMAYwA7DAAAAwBjADoMAAADAFQAPAwAAAMAUAAyDAAAAwBhAD0MAAADAGEAPgwAAAIAUAA/DAAAAQBbAAAA.Monkhon:BAEALAADCgcICwABLAAECgIIAgACAAAAAA==.',My='Mystcaller:BAEALAAECggIEAAAAA==.Mythonomicon:BAEBLAAECoEUAAILAAgIySJKBQAdAwg5DAAAAwBfADsMAAADAGEAOgwAAAMATAA8DAAAAwBTADIMAAACAF8APQwAAAMAYAA+DAAAAgBaAD8MAAABAEwACwAICMkiSgUAHQMIOQwAAAMAXwA7DAAAAwBhADoMAAADAEwAPAwAAAMAUwAyDAAAAgBfAD0MAAADAGAAPgwAAAIAWgA/DAAAAQBMAAAA.',Ni='Niven:BAEALAAECgUIBwAAAA==.',No='Nokkturnal:BAEALAAECgMIBgAAAA==.Nolazax:BAEALAAECgcICQAAAA==.Norkitk:BAEALAAECgMIAwAAAA==.',Ny='Nyrae:BAEALAAECgMIAwAAAA==.',Om='Omgtotem:BAEALAAECgYIDAAAAA==.',Pa='Pantothenik:BAEBLAAECoEgAAMJAAgI6hzVCgClAgg5DAAABABgADsMAAAEAFsAOgwAAAQANwA8DAAABQBLADIMAAAEADcAPQwAAAQAVwA+DAAABABFAD8MAAADAD0ACQAICOoc1QoApQIIOQwAAAQAYAA7DAAABABbADoMAAAEADcAPAwAAAUASwAyDAAABAA3AD0MAAAEAFcAPgwAAAQARQA/DAAAAQA9ABIAAQiDBjN7AC0AAT8MAAACABAAAAA=.Parkpark:BAEALAADCgUIBQABLAADCgYIBgACAAAAAA==.',Po='Pocketadin:BAEALAAECgMIAwAAAA==.',Ps='Psyká:BAEALAAECgQIBAAAAA==.',Ra='Ragingjazzy:BAEALAAECgYIEQABLAAFFAMIBQABAFQMAA==.',Re='Rejuju:BAEALAAECggIDgAAAA==.',Ry='Ryykker:BAEALAADCgEIAQABLAAECgcICAACAAAAAA==.',Sh='Shamhon:BAEALAAECgIIAgAAAA==.Shelannigans:BAECLAAFFIEJAAIIAAUIMho5AADtAQU5DAAAAwBUADsMAAACAFgAOgwAAAIAYAA8DAAAAQAjAD0MAAABAB4ACAAFCDIaOQAA7QEFOQwAAAMAVAA7DAAAAgBYADoMAAACAGAAPAwAAAEAIwA9DAAAAQAeACwABAqBFAACCAAICJEmVAAAewMACAAICJEmVAAAewMAAAA=.Shirael:BAEALAAECggIDAAAAA==.',St='Stebpaladin:BAEALAAECgEIAQABLAAFFAMIAwACAAAAAA==.Stebrogue:BAEALAADCgQIBAABLAAFFAMIAwACAAAAAA==.Stebshaman:BAEALAAFFAMIAwAAAA==.Stephíe:BAEALAADCggICAABLAAECgcIDgACAAAAAA==.Steví:BAEALAADCggIEAABLAAECgcIDgACAAAAAA==.',Ti='Tierán:BAEALAAECgcIEAAAAA==.',To='Tobis:BAEALAAECgQIBwAAAA==.Tocopherol:BAEALAAECgQIBAABLAAECggIIAAJAOocAA==.',Tr='Tragicmike:BAEALAADCggICAABLAAECgMIAwACAAAAAA==.Tremens:BAECLAAFFIEIAAMFAAUIgQ/3AQBUAQU5DAAAAgBEADsMAAABAAMAOgwAAAMASgA8DAAAAQAPAD0MAAABACUABQAECCcM9wEAVAEEOQwAAAEARAA7DAAAAQADADwMAAABAA8APQwAAAEAJQAGAAIIpBkRAwC0AAI5DAAAAQA5ADoMAAADAEoALAAECoEWAAQGAAgIoCMBBwD0AQAGAAYIvyABBwD0AQAFAAQIuiMmIwCYAQAHAAMIPho7EQAhAQAAAA==.Trolosarushx:BAEALAAECgIIAwABLAAECggIGAATANoeAA==.',Tw='Twlvepeers:BAEALAAECgYIDwAAAA==.',['Tó']='Tóva:BAEALAAECgYICQAAAA==.',Xa='Xania:BAEALAAECgcICAAAAA==.',Za='Zayvointh:BAEALAADCggIDgABLAAECggIFgAKAFQbAA==.',Zo='Zoéy:BAEALAAECgcIDgAAAA==.',Zu='Zuriel:BAEALAADCggIEQABLAAECggICAACAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end