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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Druid-Restoration','DeathKnight-Frost','Mage-Fire','Mage-Frost','DeathKnight-Unholy','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Evoker-Devastation','Warrior-Protection','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Warrior-Arms','Shaman-Restoration','Evoker-Preservation',}; local provider = {region='US',realm='Frostmourne',name='US',type='subscribers',zone=44,date='2025-08-29',data={Af='Afflictweave:BAEALAAECgMIAwABLAAECgcIDQABAAAAAA==.',Ai='Airwreckah:BAEALAAFFAIIAgAAAA==.',An='Andralis:BAEALAADCgYIBgABLAAFFAEIAQABAAAAAA==.Annastrea:BAEALAAECgYICgAAAA==.',Ar='Archmageytÿ:BAEBLAAECoEVAAICAAgI2CYUAACgAwg5DAAAAwBjADsMAAACAGMAOgwAAAMAYwA8DAAAAwBhADIMAAADAGMAPQwAAAMAYwA+DAAAAgBjAD8MAAACAGMAAgAICNgmFAAAoAMIOQwAAAMAYwA7DAAAAgBjADoMAAADAGMAPAwAAAMAYQAyDAAAAwBjAD0MAAADAGMAPgwAAAIAYwA/DAAAAgBjAAAA.Ardez:BAEALAAFFAEIAQAAAA==.',Bu='Budgetmarma:BAEALAAECgMIAwABLAAFFAMIBQADAKImAA==.',Ca='Casanovaa:BAEALAADCggICAABLAAECggIFgAEANsiAA==.',Ce='Ceruuledge:BAEALAADCgYIBgABLAAECggIFQAFAGEgAA==.',Co='Coneofcodes:BAEBLAAECoESAAMCAAgIMx83DgC0Agg5DAAABABhADsMAAADAF8AOgwAAAIAQgA8DAAAAgBNADIMAAADAFAAPQwAAAIAUgA+DAAAAQBNAD8MAAABAD0AAgAICDMfNw4AtAIIOQwAAAMAYQA7DAAAAwBfADoMAAACAEIAPAwAAAIATQAyDAAAAwBQAD0MAAACAFIAPgwAAAEATQA/DAAAAQA9AAYAAQihDhNFADIAATkMAAABACUAAAA=.',Cr='Crooxy:BAEALAAECgcIEQAAAA==.',Cx='Cxdez:BAEALAAECgIIAgABLAAECggIEgACADMfAA==.',Di='Divail:BAEALAAECgUIAwABLAAECggIFQAFAGEgAA==.',Dw='Dwakakiwi:BAEALAAFFAIIAgAAAA==.',Ep='Epiarcane:BAEALAAFFAIIAgAAAA==.Epifrostmage:BAEALAAECgYIBgABLAAFFAIIAgABAAAAAA==.',Er='Eredots:BAEALAAECgQIBAAAAA==.',Fi='Fiendin:BAEALAAECgcIDQAAAA==.',Fl='Floorqt:BAECLAAFFIEFAAIEAAMIXCQpAQBWAQM5DAAAAgBjADoMAAACAGMAPQwAAAEATwAEAAMIXCQpAQBWAQM5DAAAAgBjADoMAAACAGMAPQwAAAEATwAsAAQKgRgAAwQACAjDJmMAAIkDAAQACAjDJmMAAIkDAAcAAQjTJDYrAGkAAAAA.',Ga='Gardevoiir:BAEBLAAECoEVAAMFAAYIYSDiAQAYAgY5DAAABABeADsMAAAEAFIAOgwAAAQAYAA8DAAABABNADIMAAADAEEAPQwAAAIATwAFAAYIpx/iAQAYAgY5DAAAAwBeADsMAAAEAFIAOgwAAAQAYAA8DAAAAwBNADIMAAACADYAPQwAAAIATwAGAAMIChUXLACwAAM5DAAAAQBDADwMAAABABwAMgwAAAEAQQAAAA==.',Gh='Ghostwolf:BAEALAADCggICAABLAAECggIGAAIAHYjAA==.',Go='Goonlordx:BAEALAADCggICAABLAAECggIEwAEALMiAA==.',Gr='Grimfleur:BAEALAAECgMIAwABLAAECgYIDAABAAAAAA==.Grimlils:BAEALAADCggICAABLAAECgYIDAABAAAAAA==.Grimstrider:BAEALAAECgYIDAAAAA==.',Gu='Guzmonk:BAEALAADCgYIBgABLAAECggIFwAJAJ4jAA==.Guzrogue:BAEBLAAECoEXAAQJAAgIniPUAgAeAwg5DAAAAwBjADsMAAADAGEAOgwAAAMAWwA8DAAAAwBIADIMAAADAE8APQwAAAMAYwA+DAAAAwBgAD8MAAACAF4ACQAICP4h1AIAHgMIOQwAAAMAYwA7DAAAAwBhADoMAAACAFsAPAwAAAEAJgAyDAAAAgBPAD0MAAACAGMAPgwAAAIAYAA/DAAAAgBeAAoABAhZESEMAAcBBDwMAAABAEgAMgwAAAEABAA9DAAAAQBRAD4MAAABABQACwACCI4YqwoAmQACOgwAAAEARwA8DAAAAQA2AAAA.',Ha='Hadjivoker:BAEBLAAECoEWAAIMAAcI3haRFADFAQc5DAAABQArADsMAAADAEUAOgwAAAMAKAA8DAAAAwApADIMAAADAEAAPQwAAAMASQA+DAAAAgBMAAwABwjeFpEUAMUBBzkMAAAFACsAOwwAAAMARQA6DAAAAwAoADwMAAADACkAMgwAAAMAQAA9DAAAAwBJAD4MAAACAEwAAAA=.Happyxo:BAEALAAFFAMIAwAAAA==.',Ka='Kaelvoker:BAEALAADCgYIBgABLAAECggIFQAFAGEgAA==.',Kl='Klaradin:BAEBLAAECoEUAAIIAAgIuySoBAA4Awg5DAAAAgBjADsMAAACAGEAOgwAAAIAVQA8DAAAAwBbADIMAAADAF8APQwAAAMAXAA+DAAAAwBiAD8MAAACAFoACAAICLskqAQAOAMIOQwAAAIAYwA7DAAAAgBhADoMAAACAFUAPAwAAAMAWwAyDAAAAwBfAD0MAAADAFwAPgwAAAMAYgA/DAAAAgBaAAAA.',Ko='Komi:BAEBLAAECoEWAAINAAgIKCSCAQA7Awg5DAAAAwBeADsMAAADAGMAOgwAAAMAWAA8DAAAAwBTADIMAAADAGIAPQwAAAMAYwA+DAAAAgBTAD8MAAACAF0ADQAICCgkggEAOwMIOQwAAAMAXgA7DAAAAwBjADoMAAADAFgAPAwAAAMAUwAyDAAAAwBiAD0MAAADAGMAPgwAAAIAUwA/DAAAAgBdAAAA.Komiknight:BAEALAADCggICAABLAAECggIFgANACgkAA==.Komimonk:BAEALAADCggICAABLAAECggIFgANACgkAA==.',['Kì']='Kìnetyk:BAECLAAFFIEJAAIOAAQIhBgsAQB8AQQ5DAAAAwBbADsMAAACAEoAOgwAAAMAQQA8DAAAAQATAA4ABAiEGCwBAHwBBDkMAAADAFsAOwwAAAIASgA6DAAAAwBBADwMAAABABMALAAECoEYAAIOAAgI+iOpAwA0AwAOAAgI+iOpAwA0AwAAAA==.',Lc='Lcd:BAECLAAFFIEFAAIDAAMIoiarAABgAQM5DAAAAgBhADsMAAABAGMAOgwAAAIAYwADAAMIoiarAABgAQM5DAAAAgBhADsMAAABAGMAOgwAAAIAYwAsAAQKgRcAAgMACAgmJjcAAHkDAAMACAgmJjcAAHkDAAAA.',Li='Lilgup:BAEBLAAECoETAAIEAAgIsyKxBQAXAwg5DAAAAwBhADsMAAADAGMAOgwAAAIAYAA8DAAAAwBVADIMAAADAGMAPQwAAAMAWgA+DAAAAQBOAD8MAAABAD4ABAAICLMisQUAFwMIOQwAAAMAYQA7DAAAAwBjADoMAAACAGAAPAwAAAMAVQAyDAAAAwBjAD0MAAADAFoAPgwAAAEATgA/DAAAAQA+AAAA.',Lo='Loquewl:BAEBLAAECoEXAAMPAAgI5SCsBgDoAgg5DAAAAgBVADsMAAADAFsAOgwAAAMAVgA8DAAAAwBRADIMAAADAF8APQwAAAMAYQA+DAAAAwAsAD8MAAADAFsADwAICKkgrAYA6AIIOQwAAAEAVQA7DAAAAgBbADoMAAACAFYAPAwAAAIAUQAyDAAAAwBfAD0MAAACAFwAPgwAAAIALAA/DAAAAwBbABAABgg+F6kQAIEBBjkMAAABAFEAOwwAAAEAAAA6DAAAAQBRADwMAAABAEkAPQwAAAEAYQA+DAAAAQAXAAAA.',Lu='Lunahuntt:BAEALAAECgcIEQAAAA==.Lunnacyy:BAEALAADCgcIBwABLAAECgcIEQABAAAAAA==.',Ly='Lyke:BAEBLAAECoEXAAIRAAgISSNOAABbAwg5DAAAAwBjADsMAAADAGEAOgwAAAMAXQA8DAAAAwBPADIMAAADAGEAPQwAAAMAYgA+DAAAAwBiAD8MAAACADgAEQAICEkjTgAAWwMIOQwAAAMAYwA7DAAAAwBhADoMAAADAF0APAwAAAMATwAyDAAAAwBhAD0MAAADAGIAPgwAAAMAYgA/DAAAAgA4AAAA.Lykem:BAEALAAECgMIBAABLAAECggIFwARAEkjAA==.Lykeqt:BAEALAAECgMIBQABLAAECggIFwARAEkjAA==.Lykew:BAEALAADCgIIAgABLAAECggIFwARAEkjAA==.Lykex:BAEALAADCgMIAwABLAAECggIFwARAEkjAA==.Lykexd:BAEALAAECgEIAQABLAAECggIFwARAEkjAA==.',Ma='Madorimage:BAECLAAFFIEIAAICAAMImRpoAwAYAQM5DAAAAwBRADsMAAACABsAOgwAAAMAXgACAAMImRpoAwAYAQM5DAAAAwBRADsMAAACABsAOgwAAAMAXgAsAAQKgRgAAgIACAiTIjMGABYDAAIACAiTIjMGABYDAAAA.Maybedh:BAEALAAFFAIIAgABLAAFFAUICAABAAAAAQ==.Maybedk:BAEALAAFFAEIAQABLAAFFAUICAABAAAAAQ==.Maybepl:BAEALAAFFAUICAAAAQ==.Maybergthree:BAEALAADCggICAABLAAFFAUICAABAAAAAQ==.',Mu='Muddymudster:BAEALAAFFAEIAQABLAAFFAUICwASAFIgAA==.Mudpriest:BAEALAADCgIIAgABLAAFFAUICwASAFIgAA==.Mudwuffstar:BAECLAAFFIELAAMSAAUIUiA3AAAaAgU5DAAAAgBjADsMAAADAGQAOgwAAAIAXwA8DAAAAgAxAD0MAAACAEQAEgAFCEogNwAAGgIFOQwAAAIAYwA7DAAAAgBjADoMAAACAF8APAwAAAIAMQA9DAAAAgBEABMAAQgQJ/0AAHQAATsMAAABAGQALAAECoEWAAMSAAgI2iaDAACHAwASAAgIuSaDAACHAwATAAUI7yb8AgAvAgAAAA==.',Ne='Neptista:BAEALAAECggIDgABLAAFFAIIAgABAAAAAA==.',Pa='Pandatv:BAEBLAAECoEYAAIIAAgIdiOdBQAnAwg5DAAAAwBjADsMAAADAGMAOgwAAAQAVwA8DAAABABZADIMAAADAF0APQwAAAMAYgA+DAAAAwBhAD8MAAABAD0ACAAICHYjnQUAJwMIOQwAAAMAYwA7DAAAAwBjADoMAAAEAFcAPAwAAAQAWQAyDAAAAwBdAD0MAAADAGIAPgwAAAMAYQA/DAAAAQA9AAAA.Parobola:BAEBLAAECoEXAAMUAAgI/iLzAgD0Agg5DAAAAwBjADsMAAADAF8AOgwAAAQAWwA8DAAAAwBjADIMAAADAGMAPQwAAAMAWgA+DAAAAgBLAD8MAAACAEEAFAAICP4i8wIA9AIIOQwAAAIAYwA7DAAAAgBfADoMAAADAFsAPAwAAAIAYwAyDAAAAwBjAD0MAAACAFoAPgwAAAIASwA/DAAAAgBBAA4ABQjaFy0kAIUBBTkMAAABAEcAOwwAAAEAUgA6DAAAAQAqADwMAAABAB4APQwAAAEATQAAAA==.Parobõla:BAEALAAECgIIAgABLAAECggIFwAUAP4iAA==.Paroker:BAEALAADCggIDwABLAAECggIFwAUAP4iAA==.',Ra='Rainons:BAEALAAFFAIIAgABLAAFFAQIBwAOALUiAA==.Rainonsh:BAECLAAFFIEHAAIOAAQItSIGAQCYAQQ5DAAAAQBSADsMAAACAF4AOgwAAAMAWwA8DAAAAQBWAA4ABAi1IgYBAJgBBDkMAAABAFIAOwwAAAIAXgA6DAAAAwBbADwMAAABAFYALAAECoEXAAIOAAgI2yYYAACgAwAOAAgI2yYYAACgAwAAAA==.Ramm:BAECLAAFFIEHAAMPAAQIXhoDAgBLAQQ5DAAAAgAhADsMAAACAFoAOgwAAAIAMwA8DAAAAQBeAA8ABAheFwMCAEsBBDkMAAABAAIAOwwAAAIAWgA6DAAAAQAzADwMAAABAF4AEAACCHEMSwUApQACOQwAAAEAIQA6DAAAAQAeACwABAqBFwAEEQAICAQiqgAAGwMAEQAHCGglqgAAGwMADwAFCEUgwxsA1wEAEAABCOkmeT0AcQAAAAA=.Rammtwo:BAEALAAECggIDgABLAAFFAQIBwAPAF4aAA==.Razzldazzlee:BAEBLAAECoEWAAIEAAgI2yI/BgAOAwg5DAAAAwBZADsMAAADAGEAOgwAAAMAWgA8DAAAAwBhADIMAAADAEoAPQwAAAMAXgA+DAAAAgBZAD8MAAACAFAABAAICNsiPwYADgMIOQwAAAMAWQA7DAAAAwBhADoMAAADAFoAPAwAAAMAYQAyDAAAAwBKAD0MAAADAF4APgwAAAIAWQA/DAAAAgBQAAAA.',Ro='Rosaura:BAECLAAFFIEFAAIJAAMIpRQQAgAaAQM5DAAAAgBbADsMAAABACcAOgwAAAIAGwAJAAMIpRQQAgAaAQM5DAAAAgBbADsMAAABACcAOgwAAAIAGwAsAAQKgRcAAwkACAiNI+YBADoDAAkACAiNI+YBADoDAAoAAQgHFXsXADkAAAAA.',Sa='Savingpvtras:BAEBLAAECoEVAAMVAAgIUhbABQAgAgg5DAAAAwAxADsMAAADAEkAOgwAAAMAOgA8DAAAAwA3ADIMAAADADsAPQwAAAMASgA+DAAAAgBBAD8MAAABABMAFQAICFIWwAUAIAIIOQwAAAMAMQA7DAAAAwBJADoMAAADADoAPAwAAAMANwAyDAAAAwA7AD0MAAACAEoAPgwAAAIAQQA/DAAAAQATAAwAAQhuDVQ0AD4AAT0MAAABACIAAAA=.',Se='Seriousnes:BAEALAAECgcIBwAAAA==.',['Sä']='Sänct:BAEALAAECgcIDQAAAA==.',Th='Theßetrayer:BAEALAAECgMIAwABLAAECggIGAAEAOskAA==.',Ti='Tieprier:BAEALAAECgYIDgAAAA==.',To='Toppfang:BAEBLAAECoEXAAIOAAgIPiIQBwDtAgg5DAAAAwBiADsMAAADAFsAOgwAAAMAVQA8DAAAAwBSADIMAAADAGAAPQwAAAMATgA+DAAAAwBYAD8MAAACAE8ADgAICD4iEAcA7QIIOQwAAAMAYgA7DAAAAwBbADoMAAADAFUAPAwAAAMAUgAyDAAAAwBgAD0MAAADAE4APgwAAAMAWAA/DAAAAgBPAAAA.Touchofsimp:BAEALAAECggIEAABLAAFFAMIBQAEAFwkAA==.',Ul='Ultimatthunt:BAEALAAECggIAQAAAA==.',Um='Umbrreon:BAEALAADCgcIBwABLAAECggIFQAFAGEgAA==.',Uw='Uwurawrxd:BAEALAADCggIDQABLAAECgcIFgAMAN4WAA==.',Ve='Vellastrian:BAEALAADCgcIAQABLAAFFAEIAQABAAAAAA==.Vendrix:BAEBLAAECoEYAAIEAAgI6yQJBgARAwg5DAAAAwBjADsMAAAEAGIAOgwAAAMAYQA8DAAAAwBbADIMAAADAF8APQwAAAMAWQA+DAAAAgBgAD8MAAADAFgABAAICOskCQYAEQMIOQwAAAMAYwA7DAAABABiADoMAAADAGEAPAwAAAMAWwAyDAAAAwBfAD0MAAADAFkAPgwAAAIAYAA/DAAAAwBYAAAA.',Wa='Warknatty:BAEALAADCgUICAAAAA==.Washed:BAEALAAECgQIBAABLAAECggIGAAIAHYjAA==.',Ze='Zenalation:BAEALAADCgQIBAAAAA==.',Zo='Zorthargirl:BAEALAAECgcIAgABLAAFFAIIAgABAAAAAA==.Zorthax:BAEALAAECggIAgABLAAFFAIIAgABAAAAAA==.Zorxoth:BAEALAAFFAIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end