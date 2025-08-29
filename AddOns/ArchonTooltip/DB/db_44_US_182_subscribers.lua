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
 local lookup = {'Unknown-Unknown','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Feral','Druid-Balance','Paladin-Retribution','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Mage-Frost','Shaman-Restoration','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Priest-Discipline','Paladin-Holy','DeathKnight-Frost','Druid-Restoration','Mage-Arcane',}; local provider = {region='US',realm='Sargeras',name='US',type='subscribers',zone=44,date='2025-08-29',data={Ad='Adventures:BAEALAAECgcIBwAAAA==.',Ai='Aiferian:BAEALAAECgYICQAAAA==.Aimbolts:BAEALAAECgMIAwABLAAFFAMIAgABAAAAAA==.Aimflays:BAEALAADCgYIBgABLAAFFAMIAgABAAAAAA==.Aimshifts:BAEALAAECgMIBQABLAAFFAMIAgABAAAAAA==.Aimsucks:BAEALAAFFAMIAgAAAA==.',Ar='Archimtiros:BAECLAAFFIEIAAICAAUIXCAuAAAhAgU5DAAAAgBjADsMAAABAFcAOgwAAAMAYwA8DAAAAQA/AD0MAAABAD8AAgAFCFwgLgAAIQIFOQwAAAIAYwA7DAAAAQBXADoMAAADAGMAPAwAAAEAPwA9DAAAAQA/ACwABAqBGAACAgAICC0m/AAAdQMAAgAICC0m/AAAdQMAAAA=.',Ba='Babylonisus:BAEALAAECgUICQAAAA==.Bantley:BAEALAADCgYIBgAAAA==.',Be='Beccastarr:BAEALAAECgcIEQAAAA==.',Bl='Blizinator:BAEBLAAECoEeAAQDAAgI1iH/BgDiAgg5DAAABABeADsMAAAEAEsAOgwAAAQAVAA8DAAABABYADIMAAAEAFsAPQwAAAQAVgA+DAAABABSAD8MAAACAFkAAwAICNYh/wYA4gIIOQwAAAMAXgA7DAAABABLADoMAAABAFQAPAwAAAMAWAAyDAAAAwBbAD0MAAADAFYAPgwAAAMAUgA/DAAAAgBZAAQABAhxGZgeACEBBDkMAAABAFcAOgwAAAMASAA9DAAAAQA8AD4MAAABACgABQACCDsLPh4AjgACPAwAAAEABwAyDAAAAQAxAAAA.Blizitres:BAEALAADCggICgABLAAECggIHgADANYhAA==.Blopsamdi:BAEALAADCggIEAABLAAECgUIBgABAAAAAA==.Bløødhaven:BAEALAAECgcIEgAAAA==.',Da='Dalailarma:BAEALAADCggIFwAAAA==.Daraceae:BAEALAAECgcIEQAAAA==.Dauraane:BAEALAAECggICAABLAAFFAIIAgABAAAAAA==.Davebtw:BAECLAAFFIEFAAMGAAMI+Ra8AAAUAQM5DAAAAgA8ADsMAAABAF8AOgwAAAIAFQAGAAMIxBa8AAAUAQM5DAAAAgA8ADsMAAABAF8AOgwAAAEAEwAHAAEIRQg6CQBFAAE6DAAAAQAVACwABAqBGQADBgAICD8lGwEAKwMABgAICJ4kGwEAKwMABwAICAIfjAgAqgIAAAA=.',De='Deaddari:BAEALAADCggICAABLAAECgcIEQABAAAAAA==.',Di='Divineincel:BAEBLAAECoEWAAIIAAgIcSHJDAC2Agg5DAAAAwBhADsMAAADAFAAOgwAAAMAWQA8DAAAAwBYADIMAAADAFoAPQwAAAMAYQA+DAAAAgBFAD8MAAACAEYACAAICHEhyQwAtgIIOQwAAAMAYQA7DAAAAwBQADoMAAADAFkAPAwAAAMAWAAyDAAAAwBaAD0MAAADAGEAPgwAAAIARQA/DAAAAgBGAAAA.Divinelightx:BAEALAADCgQIBAAAAA==.',Do='Dommiemommy:BAEALAAECgYIBgAAAA==.',Dr='Droovi:BAEALAAECgYICwABLAAFFAYIDAAJAD0mAA==.',['Dï']='Dïâna:BAEALAADCgcICgABLAAECgYICQABAAAAAA==.',En='Endzö:BAEALAAECggICQAAAA==.',Ev='Evokur:BAECLAAFFIEGAAMKAAQINBRLAQAfAQQ5DAAAAgBgADsMAAABABwAOgwAAAIASQA8DAAAAQAIAAoAAwjXGUsBAB8BAzkMAAACAGAAOwwAAAEAHAA6DAAAAgBJAAsAAQiJA8IJAFEAATwMAAABAAkALAAECoEXAAIKAAgIyyRjAABTAwAKAAgIyyRjAABTAwAAAA==.',Fa='Fatdari:BAEALAAECgcIEQAAAA==.',Fe='Felcantgetup:BAEALAADCggICAABLAAECgcIFAAMAOwjAA==.',Ga='Gabelust:BAECLAAFFIEGAAINAAYI7hE1AADtAQY5DAAAAQAbADsMAAABADUAOgwAAAEARgA8DAAAAQAWADIMAAABAC0APQwAAAEANwANAAYI7hE1AADtAQY5DAAAAQAbADsMAAABADUAOgwAAAEARgA8DAAAAQAWADIMAAABAC0APQwAAAEANwAsAAQKgRUAAg0ACAjAHysFAL8CAA0ACAjAHysFAL8CAAAA.Gabeprayge:BAEBLAAFFIEGAAIOAAQIxxfHAABqAQQ5DAAAAgBDADsMAAABACoAOgwAAAIAUAA8DAAAAQA1AA4ABAjHF8cAAGoBBDkMAAACAEMAOwwAAAEAKgA6DAAAAgBQADwMAAABADUAASwABRQGCAYADQDuEQA=.Gahdamn:BAEALAAECgIIAgAAAA==.Gahdsie:BAEALAADCgYIBgABLAAECgIIAgABAAAAAA==.',Gi='Ginjaoo:BAEALAADCggICAABLAAFFAMIBQAPAGYhAA==.',Gl='Gloombunni:BAEALAAECgYICQAAAA==.',Gr='Groovchi:BAEALAADCgIIAgABLAAFFAYIDAAJAD0mAA==.Groovee:BAECLAAFFIEMAAMJAAYIPSYuAADDAQY5DAAAAgBkADsMAAACAGMAOgwAAAMAYwA8DAAAAgBgADIMAAABAGQAPQwAAAIAWwAJAAQIrCUuAADDAQQ5DAAAAgBkADsMAAACAGMAOgwAAAIAXgA9DAAAAgBbABAAAwibJkcAAF4BAzoMAAABAGMAPAwAAAIAYAAyDAAAAQBkACwABAqBGQADCQAICAAnFwAAmgMACQAICOkmFwAAmgMAEAAGCO0mvQEAvwIAAAA=.',Ha='Hazeÿ:BAEALAAECgYIDwABLAAECgcIFAARAJwlAA==.',He='Hedvine:BAEALAAECgUIBwAAAA==.Hetror:BAECLAAFFIEGAAISAAMI6iFwAQAcAQM5DAAAAgBeADsMAAACAFgAOgwAAAIATQASAAMI6iFwAQAcAQM5DAAAAgBeADsMAAACAFgAOgwAAAIATQAsAAQKgRgAAhIACAiKI6UCACMDABIACAiKI6UCACMDAAAA.',Ho='Holysele:BAEALAADCggICgABLAAECggIFAAHAMwcAA==.',Hu='Huntaga:BAEBLAAECoEWAAMTAAgIBSRNAABLAwg5DAAAAwBfADsMAAADAGIAOgwAAAMAYQA8DAAAAwBaADIMAAADAF8APQwAAAMAXwA+DAAAAgBTAD8MAAACAFEAEwAICMUiTQAASwMIOQwAAAEAXwA7DAAAAQBiADoMAAABAF4APAwAAAEAWgAyDAAAAQBMAD0MAAABAFwAPgwAAAEAUgA/DAAAAQBRABEACAhBI/wEABYDCDkMAAACAFgAOwwAAAIAYgA6DAAAAgBhADwMAAACAFkAMgwAAAIAXwA9DAAAAgBfAD4MAAABAFMAPwwAAAEASwAAAA==.',Hy='Hydrosplash:BAEALAAFFAIIAgAAAA==.',['Hâ']='Hâzêy:BAEALAADCggICAABLAAECgcIFAARAJwlAA==.',['Hä']='Häzey:BAEBLAAECoEUAAMRAAcInCU4BgAAAwc5DAAAAwBjADsMAAADAGMAOgwAAAMAXQA8DAAAAwBiADIMAAADAGIAPQwAAAMAWwA+DAAAAgBcABEABwicJTgGAAADBzkMAAACAGMAOwwAAAIAYwA6DAAAAgBdADwMAAACAGIAMgwAAAIAYgA9DAAAAwBbAD4MAAACAFwAEgAFCG8cAhsAkQEFOQwAAAEAYQA7DAAAAQBUADoMAAABAFsAPAwAAAEAQQAyDAAAAQAZAAAA.',['Hò']='Hòlýnìght:BAEALAADCgcIBwAAAA==.',Ib='Ibdapopo:BAECLAAFFIEFAAIRAAMIDhb1AQANAQM5DAAAAgBWADsMAAABAB8AOgwAAAIAMwARAAMIDhb1AQANAQM5DAAAAgBWADsMAAABAB8AOgwAAAIAMwAsAAQKgRcAAhEACAjjI/cDACgDABEACAjjI/cDACgDAAAA.',Ka='Kajse:BAEALAAFFAIIBAAAAQ==.',Ke='Kemmyy:BAEALAAECgEIAQABLAAECgYICQABAAAAAA==.',Le='Lembar:BAEALAADCgcIBwAAAA==.',Lo='Lockhaven:BAEALAADCggICAABLAAECgcIEgABAAAAAA==.',Ma='Machfive:BAEALAAFFAIIAgAAAA==.',Mi='Minicharge:BAEALAADCggICAABLAAFFAUICwALADUbAA==.Minidead:BAEALAAECggIDwABLAAFFAUICwALADUbAA==.Minigodzilla:BAEBLAAFFIELAAILAAUINRuiAADjAQU5DAAAAwBcADsMAAACADQAOgwAAAMAPAA8DAAAAgBFAD0MAAABAEkACwAFCDUbogAA4wEFOQwAAAMAXAA7DAAAAgA0ADoMAAADADwAPAwAAAIARQA9DAAAAQBJAAAA.Minipet:BAEALAAECgEIAQABLAAFFAUICwALADUbAA==.',Mo='Moîstweaver:BAEALAAECgIIAgAAAA==.',Mu='Murtwarr:BAEALAAECggIBgAAAA==.',My='Mykroft:BAEALAAECgYICQAAAA==.',Ni='Nistral:BAEALAAECggIBgAAAA==.',No='Notoriousrip:BAEALAAECggIDgABLAAECggIFwASAG8iAA==.Nozw:BAEALAAECgcIDgAAAA==.',Ph='Pheebi:BAEALAAECgcIAQAAAA==.',Po='Powers:BAEALAAECgYIBgAAAA==.',Qu='Queveighnne:BAEBLAAECoEXAAITAAcI3CMAAQDHAgc5DAAABABiADsMAAAEAGEAOgwAAAQAYgA8DAAABABiADIMAAADAEoAPQwAAAIAXAA+DAAAAgBSABMABwjcIwABAMcCBzkMAAAEAGIAOwwAAAQAYQA6DAAABABiADwMAAAEAGIAMgwAAAMASgA9DAAAAgBcAD4MAAACAFIAAAA=.Quillty:BAEALAADCggICAAAAA==.',Ra='Ragegasm:BAEALAAECgYICQABLAABCgEIAQABAAAAAA==.',Re='Reead:BAEBLAAECoEYAAMUAAgI8hbkBAC4AQg5DAAAAwBHADsMAAADADkAOgwAAAMAHAA8DAAAAwAxADIMAAADAEkAPQwAAAMAWQA+DAAAAwA8AD8MAAADACcADgAICIMVYREALAIIOQwAAAIARwA7DAAAAgA5ADoMAAACABwAPAwAAAIAHwAyDAAAAgBJAD0MAAACAFkAPgwAAAIAMAA/DAAAAwAnABQABwi5EeQEALgBBzkMAAABACwAOwwAAAEALwA6DAAAAQARADwMAAABADEAMgwAAAEARwA9DAAAAQAbAD4MAAABADwAAAA=.',Sa='Saphataph:BAEALAADCggIEAABLAAECgYICwABAAAAAA==.Saphigon:BAEALAAECgYICwAAAA==.Sayuri:BAEALAAECgMIBAABLAAECggIFQALAH0cAA==.',Se='Seagie:BAEBLAAECoEWAAIVAAgI3hvyAwCmAgg5DAAAAwAxADsMAAADAGAAOgwAAAMAYQA8DAAAAgA5ADIMAAADAFkAPQwAAAMAVQA+DAAAAgANAD8MAAADAFIAFQAICN4b8gMApgIIOQwAAAMAMQA7DAAAAwBgADoMAAADAGEAPAwAAAIAOQAyDAAAAwBZAD0MAAADAFUAPgwAAAIADQA/DAAAAwBSAAAA.Seagy:BAEALAAECgYIDAABLAAECggIFgAVAN4bAA==.Selermoon:BAEBLAAECoEUAAIHAAgIzBzXCACkAgg5DAAAAwBeADsMAAADAEMAOgwAAAMATwA8DAAAAwAqADIMAAADAEsAPQwAAAMAWwA+DAAAAQBSAD8MAAABADgABwAICMwc1wgApAIIOQwAAAMAXgA7DAAAAwBDADoMAAADAE8APAwAAAMAKgAyDAAAAwBLAD0MAAADAFsAPgwAAAEAUgA/DAAAAQA4AAAA.Serlem:BAEALAAECgcICAABLAAFFAIIBAABAAAAAA==.Serlen:BAEALAAFFAIIBAAAAA==.',Sh='Shampage:BAEALAAECgMIBAAAAA==.Sheepdk:BAEALAADCggIDgABLAAFFAMIBQAGAFMjAA==.Sheepdruid:BAEBLAAFFIEFAAIGAAMIUyN2AAAwAQM5DAAAAgBgADsMAAABAFIAOgwAAAIAWwAGAAMIUyN2AAAwAQM5DAAAAgBgADsMAAABAFIAOgwAAAIAWwAAAA==.Shockaga:BAEALAADCggIDgABLAAECggIFgATAAUkAA==.Shunky:BAEALAAECgEIAQAAAA==.',Sk='Skoldevoker:BAEALAADCgMIAwABLAAECggIFgAWAB0kAA==.Skoldknight:BAEBLAAECoEWAAIWAAgIHSQnAwBFAwg5DAAAAwBfADsMAAADAGEAOgwAAAMAYAA8DAAAAwBaADIMAAADAGAAPQwAAAMAYQA+DAAAAgBKAD8MAAACAFoAFgAICB0kJwMARQMIOQwAAAMAXwA7DAAAAwBhADoMAAADAGAAPAwAAAMAWgAyDAAAAwBgAD0MAAADAGEAPgwAAAIASgA/DAAAAgBaAAAA.Skoldwarrior:BAEALAAECgIIAgABLAAECggIFgAWAB0kAA==.',Sl='Slammywhammy:BAEBLAAECoEpAAIVAAgI5h2nAwCwAgg5DAAABQBjADsMAAAGAEgAOgwAAAYAWwA8DAAABgA1ADIMAAAGAF4APQwAAAYASQA+DAAABABLAD8MAAACADQAFQAICOYdpwMAsAIIOQwAAAUAYwA7DAAABgBIADoMAAAGAFsAPAwAAAYANQAyDAAABgBeAD0MAAAGAEkAPgwAAAQASwA/DAAAAgA0AAAA.',Sn='Snuggless:BAEBLAAECoEXAAMSAAgIbyKiBADwAgg5DAAAAwBjADsMAAADAGEAOgwAAAMATwA8DAAAAwBbADIMAAADAF0APQwAAAMAYQA+DAAAAwBiAD8MAAACAC8AEgAICDQiogQA8AIIOQwAAAMAYwA7DAAAAwBhADoMAAADAE8APAwAAAMAWwAyDAAAAwBdAD0MAAADAGEAPgwAAAIAXQA/DAAAAgAvABEAAQhMJqBlAGEAAT4MAAABAGIAAAA=.',So='Solmana:BAEALAAECggIEwAAAA==.',Sp='Sparkidan:BAEALAADCggIEAAAAA==.Spwizz:BAEALAAECgcIDQAAAA==.',St='Starshall:BAEBLAAECoEVAAIXAAgIExn7DQAgAgg5DAAAAwBKADsMAAADAEAAOgwAAAMATgA8DAAAAwBHADIMAAADAEwAPQwAAAMALQA+DAAAAgBNAD8MAAABABgAFwAICBMZ+w0AIAIIOQwAAAMASgA7DAAAAwBAADoMAAADAE4APAwAAAMARwAyDAAAAwBMAD0MAAADAC0APgwAAAIATQA/DAAAAQAYAAAA.Straain:BAEALAAECgEIAQAAAA==.Stylesqt:BAEALAADCgcIBwAAAA==.',Te='Tempestborn:BAEALAAECgYICQAAAA==.',Th='Theokar:BAEALAAECgQIBAABLAAECgcIEgABAAAAAA==.Theomag:BAEALAAECgcIEgAAAA==.',Tr='Triplnine:BAEBLAAECoEUAAMMAAcI7CNRBwBgAgc5DAAABQBgADsMAAAEAGEAOgwAAAQAWQA8DAAAAgBPADIMAAACAFwAPQwAAAIAYAA+DAAAAQBaAAwABgh+I1EHAGACBjkMAAABAGAAOwwAAAIAYQA6DAAAAQBZADwMAAABAEcAMgwAAAEAXAA9DAAAAQBgABgABwjGHBcgAA8CBzkMAAAEAFMAOwwAAAIAXwA6DAAAAwBFADwMAAABAE8AMgwAAAEAMQA9DAAAAQAwAD4MAAABAFoAAAA=.Trippymagus:BAEALAADCggICgABLAAECgcIFAAMAOwjAA==.Troybolton:BAEALAAECgMIBAAAAA==.',Us='Usonja:BAECLAAFFIEFAAIPAAMIZiHHAQAtAQM5DAAAAQBhADsMAAACAE0AOgwAAAIAUQAPAAMIZiHHAQAtAQM5DAAAAQBhADsMAAACAE0AOgwAAAIAUQAsAAQKgRgAAg8ACAhFJo8AAIQDAA8ACAhFJo8AAIQDAAAA.',Va='Vaettr:BAEALAADCgIIAgABLAAECgYICQABAAAAAA==.',Wi='Wilferrels:BAEBLAAECoEXAAIGAAgISSLgAQD7Agg5DAAAAwBUADsMAAADAGMAOgwAAAMAXAA8DAAAAwBaADIMAAADAFcAPQwAAAMAYAA+DAAAAwBRAD8MAAACAEUABgAICEki4AEA+wIIOQwAAAMAVAA7DAAAAwBjADoMAAADAFwAPAwAAAMAWgAyDAAAAwBXAD0MAAADAGAAPgwAAAMAUQA/DAAAAgBFAAAA.',Xa='Xathras:BAEBLAAECoEWAAILAAgILRwtCACgAgg5DAAAAwBhADsMAAADAFcAOgwAAAMATQA8DAAAAwBWADIMAAADADQAPQwAAAQASAA+DAAAAgBJAD8MAAABAB0ACwAICC0cLQgAoAIIOQwAAAMAYQA7DAAAAwBXADoMAAADAE0APAwAAAMAVgAyDAAAAwA0AD0MAAAEAEgAPgwAAAIASQA/DAAAAQAdAAAA.',Zi='Zimbzy:BAEALAAECgcIEQAAAA==.',Zk='Zkitano:BAEALAADCgcIBwABLAAECgcIEQABAAAAAA==.',['Ða']='Ðaybreak:BAEBLAAECoEWAAIPAAgIrB9BBgD0Agg5DAAABABgADsMAAADAFwAOgwAAAMAUAA8DAAAAwBQADIMAAADAE8APQwAAAMAVQA+DAAAAgBYAD8MAAABACwADwAICKwfQQYA9AIIOQwAAAQAYAA7DAAAAwBcADoMAAADAFAAPAwAAAMAUAAyDAAAAwBPAD0MAAADAFUAPgwAAAIAWAA/DAAAAQAsAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end