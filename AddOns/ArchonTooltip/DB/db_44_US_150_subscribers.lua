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
 local lookup = {'Paladin-Protection','Unknown-Unknown','Warrior-Fury','Mage-Frost','Priest-Holy','Priest-Discipline','Mage-Arcane','Druid-Balance','Druid-Guardian','Evoker-Devastation','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Paladin-Holy','DeathKnight-Frost','Druid-Feral','Rogue-Outlaw','Evoker-Augmentation','Druid-Restoration','Monk-Mistweaver','Priest-Shadow','DeathKnight-Blood','Warrior-Protection','Shaman-Elemental','Rogue-Assassination','Hunter-BeastMastery',}; local provider = {region='US',realm="Mal'Ganis",name='US',type='subscribers',zone=44,date='2025-08-29',data={Ad='Addichan:BAECLAAFFIEFAAIBAAMIgxz1AAD/AAM5DAAAAgBNADsMAAABAEsAOgwAAAIAQgABAAMIgxz1AAD/AAM5DAAAAgBNADsMAAABAEsAOgwAAAIAQgAsAAQKgRcAAgEACAhdJh8AAJUDAAEACAhdJh8AAJUDAAAA.Addiequell:BAEALAAECgcIEAABLAAFFAEIAQACAAAAAA==.Addierain:BAEALAAFFAEIAQAAAA==.Addieroll:BAEALAADCgQIBAABLAAFFAEIAQACAAAAAA==.',Af='Afteil:BAEALAAECgIIAwAAAA==.',Ak='Akefalos:BAEALAADCgcIDAABLAAECgcIDAACAAAAAA==.',Ar='Argo:BAEALAAFFAQICQAAAQ==.',As='Asgorath:BAEALAAECgQICAAAAA==.',At='Atrianna:BAEALAAECggICAAAAA==.',Az='Azurri:BAEALAAECggIEAAAAA==.',Ba='Bahamabrahma:BAEALAAECgYIDQAAAA==.Barkboy:BAEALAAECgcIDgABLAAFFAQICAADAOsVAA==.Barria:BAEALAAECgYIDQAAAA==.Bashtoons:BAEBLAAECoEVAAIEAAgI9iWGAABwAwg5DAAAAwBjADsMAAADAGMAOgwAAAMAYgA8DAAAAwBiADIMAAADAGMAPQwAAAMAYQA+DAAAAgBfAD8MAAABAFgABAAICPYlhgAAcAMIOQwAAAMAYwA7DAAAAwBjADoMAAADAGIAPAwAAAMAYgAyDAAAAwBjAD0MAAADAGEAPgwAAAIAXwA/DAAAAQBYAAAA.',Bh='Bhorgaen:BAEALAAECgYIDwAAAA==.',Bi='Bigdum:BAEALAAECgIIAgABLAAECgIIAwACAAAAAA==.Bigolesham:BAEALAAECgYIBgAAAA==.',Bl='Blopsamdi:BAEBLAAECoEYAAMFAAgIwhxOCQCVAgg5DAAAAwBaADsMAAADAEwAOgwAAAQAXAA8DAAAAwAZADIMAAADAE0APQwAAAMAWAA+DAAAAwA/AD8MAAACAEwABQAICDUcTgkAlQIIOQwAAAIAWgA7DAAAAgBMADoMAAACAFEAPAwAAAMAGQAyDAAAAwBNAD0MAAADAFgAPgwAAAMAPwA/DAAAAgBMAAYAAwhEFMcNALwAAzkMAAABAAQAOwwAAAEAOgA6DAAAAgBcAAAA.',Bo='Bobmanzari:BAEBLAAECoEYAAIHAAgIlCMBBgAZAwg5DAAAAwBgADsMAAADAGMAOgwAAAMAXgA8DAAAAwBQADIMAAADAGAAPQwAAAQAYwA+DAAAAwBjAD8MAAACAD8ABwAICJQjAQYAGQMIOQwAAAMAYAA7DAAAAwBjADoMAAADAF4APAwAAAMAUAAyDAAAAwBgAD0MAAAEAGMAPgwAAAMAYwA/DAAAAgA/AAAA.',Ca='Caides:BAEALAAECgMIBAAAAA==.Calula:BAEALAADCgYIAwABLAAECgcIDwACAAAAAA==.',Ch='Chungywungy:BAEALAAECgYICgAAAA==.',Ci='Cileena:BAECLAAFFIEFAAIIAAQIdAvSAAA5AQQ5DAAAAQBMADsMAAACAB4AOgwAAAEABgA8DAAAAQADAAgABAh0C9IAADkBBDkMAAABAEwAOwwAAAIAHgA6DAAAAQAGADwMAAABAAMALAAECoEYAAMIAAgIDBzwCgB7AgAIAAgIDBzwCgB7AgAJAAEI4wxIEgAxAAAAAA==.',Cr='Crapter:BAEALAAECgMIAwABLAAFFAMIBQAKAIkcAA==.Craptor:BAECLAAFFIEFAAIKAAMIiRzwAQAdAQM5DAAAAgBUADsMAAABACkAOgwAAAIAXQAKAAMIiRzwAQAdAQM5DAAAAgBUADsMAAABACkAOgwAAAIAXQAsAAQKgRgAAgoACAjLJUgCADoDAAoACAjLJUgCADoDAAAA.Crescence:BAEALAAECgEIAQABLAAECgYIBwACAAAAAA==.Cryptfree:BAEBLAAECoEUAAILAAgIxRvkEACHAgg5DAAAAwBYADsMAAADAF0AOgwAAAMAPQA8DAAAAwBVADIMAAADAEAAPQwAAAMAVAA+DAAAAQAnAD8MAAABADMACwAICMUb5BAAhwIIOQwAAAMAWAA7DAAAAwBdADoMAAADAD0APAwAAAMAVQAyDAAAAwBAAD0MAAADAFQAPgwAAAEAJwA/DAAAAQAzAAAA.Cryptstone:BAEALAAECgYIBgABLAAECggIFAALAMUbAA==.',Cy='Cyrake:BAEALAAECggIDwAAAA==.',Da='Daanu:BAEALAAECgEIAgABLAAECgIIAwACAAAAAA==.Danvash:BAEBLAAFFIEKAAQMAAUI/BxvAQCOAQU5DAAAAwBcADsMAAACAE0AOgwAAAMAVQA8DAAAAQA5AD0MAAABADkADAAECJEebwEAjgEEOQwAAAMAXAA7DAAAAgBNADoMAAACAFUAPQwAAAEAOQANAAEIZSEECABmAAE6DAAAAQBVAA4AAQioFuwAAGUAATwMAAABADkAAAA=.Davolain:BAEALAAECgMIAwAAAA==.',De='Decryptzz:BAEALAAECggICAABLAAECggIFAALAMUbAA==.Demecop:BAEBLAAECoEXAAMPAAgIaSY7AwBSAwg5DAAAAwBjADsMAAADAGIAOgwAAAIAYQA8DAAAAgBeADIMAAADAGMAPQwAAAMAYwA+DAAAAwBiAD8MAAAEAGMADwAICGkmOwMAUgMIOQwAAAMAYwA7DAAAAwBiADoMAAACAGEAPAwAAAIAXgAyDAAAAwBjAD0MAAADAGMAPgwAAAMAYgA/DAAAAgBjABAAAQjxBUoxADoAAT8MAAACAA8AAAA=.Demecosham:BAEALAAECgcIEwABLAAECggIFwAPAGkmAA==.Democin:BAEALAADCggIFgABLAAECgMIAwACAAAAAA==.',Do='Dodgenstone:BAEALAADCggIDwAAAA==.',Du='Duglasr:BAEALAAECggIAgAAAA==.Dunkadormu:BAEALAADCggICAAAAA==.',El='Elmerflood:BAEALAAECgEIAQAAAA==.',Ep='Eptori:BAEALAAECggIEAAAAA==.',Ev='Evrimorr:BAEALAAECgYICQAAAA==.',Fe='Fenvy:BAEALAAFFAEIAQAAAQ==.',Fi='Finney:BAEALAAECgQIBQAAAA==.Finxo:BAEALAADCgYIBgAAAA==.',Fo='Formaknight:BAEBLAAECoEXAAIRAAgIfyXHAgBMAwg5DAAAAwBiADsMAAADAGMAOgwAAAMAXgA8DAAAAwBfADIMAAADAGEAPQwAAAMAYwA+DAAAAwBeAD8MAAACAFgAEQAICH8lxwIATAMIOQwAAAMAYgA7DAAAAwBjADoMAAADAF4APAwAAAMAXwAyDAAAAwBhAD0MAAADAGMAPgwAAAMAXgA/DAAAAgBYAAAA.Formatical:BAEALAAECgMIAwABLAAECggIFwARAH8lAA==.Formaticall:BAEALAADCgYIBgABLAAECggIFwARAH8lAA==.Formedicals:BAEALAAECgYIBgABLAAECggIFwARAH8lAA==.',Fr='Freeck:BAECLAAFFIEFAAIIAAMIHxTwAQD+AAM5DAAAAgBKADsMAAABAC4AOgwAAAIAIQAIAAMIHxTwAQD+AAM5DAAAAgBKADsMAAABAC4AOgwAAAIAIQAsAAQKgRcAAggACAh/JBcDADADAAgACAh/JBcDADADAAAA.Freeckidan:BAEALAADCggIFwABLAAFFAMIBQAIAB8UAA==.Freeckthyr:BAEALAAECgMIBAABLAAFFAMIBQAIAB8UAA==.Freefeetpics:BAEALAADCggICAAAAA==.Frozendwarf:BAEALAADCggIFgABLAAECggIFQAEAPYlAA==.',Fu='Fubår:BAEALAAECgYIBwAAAA==.Furg:BAEALAADCgMIAwABLAAECgEIAQACAAAAAA==.Furgdh:BAEALAAECgEIAQAAAA==.',Ga='Gaeove:BAEALAAECgcIEAAAAA==.',Go='Gonzopally:BAEALAAECgEIAQAAAA==.',Gr='Griefink:BAEALAAECgYIEQABLAAFFAUICAASAJoVAA==.',Gu='Gummy:BAEALAAECgYICAAAAA==.',Hi='Hikamiro:BAEALAADCgcICwAAAA==.',Hu='Hucin:BAEALAAECgMIAwAAAA==.',Il='Illusionzz:BAEALAAFFAMIBAABLAAFFAQIBAACAAAAAA==.',In='Inkbtw:BAECLAAFFIEIAAISAAUImhUxAADAAQU5DAAAAQAdADsMAAACAFAAOgwAAAMATgA8DAAAAQAMAD0MAAABAEwAEgAFCJoVMQAAwAEFOQwAAAEAHQA7DAAAAgBQADoMAAADAE4APAwAAAEADAA9DAAAAQBMACwABAqBFgACEgAICBcmoAAASgMAEgAICBcmoAAASgMAAAA=.',Is='Iser:BAECLAAFFIEFAAILAAMIpSDHAQA4AQM5DAAAAgA+ADsMAAABAF0AOgwAAAIAXwALAAMIpSDHAQA4AQM5DAAAAgA+ADsMAAABAF0AOgwAAAIAXwAsAAQKgRcAAgsACAg2JWkDAEwDAAsACAg2JWkDAEwDAAAA.',Jt='Jtks:BAEALAAECgYIEAAAAA==.',Ke='Keycloak:BAEALAAECgYICgAAAA==.',Ki='Kidbanguela:BAEALAADCgMIAQAAAA==.',Kn='Knoct:BAEALAADCgYIBgABLAAECgcIEAACAAAAAA==.',Ku='Kurios:BAEALAAECgQICAAAAA==.',Ky='Kyrrus:BAEALAAECgcIDAAAAA==.',['Kù']='Kùshìe:BAEALAADCgMIAwABLAAECgcIEQACAAAAAA==.',['Kû']='Kûshie:BAEALAAECgcIEQAAAA==.',La='Lasagnalarry:BAEALAADCgcIBwABLAADCggICAACAAAAAA==.',Li='Lightbow:BAEALAADCggICwABLAAECggIEgACAAAAAA==.Lightpost:BAEALAAECggIEgAAAA==.Likeafox:BAEALAADCgYICQABLAADCggIEAACAAAAAA==.',Ma='Maldehv:BAEALAADCggIEAAAAA==.',Me='Memermo:BAEALAAECgcIBwAAAA==.Menrva:BAEALAAECgMIAwABLAAECggIFQAKAIEaAA==.Metastrasza:BAEALAADCggIEAAAAA==.',Mi='Mindslyde:BAEALAAECgQIBgAAAA==.',['Mé']='Méchanïc:BAEALAADCgUIBQABLAAECgQIBwACAAAAAA==.Médïc:BAEALAAECgQIBwAAAA==.',No='Nomtez:BAEALAADCgcIDQAAAA==.Noodleboi:BAECLAAFFIEFAAIKAAMINBwgAgAWAQM5DAAAAgBSADsMAAABAEwAOgwAAAIAOQAKAAMINBwgAgAWAQM5DAAAAgBSADsMAAABAEwAOgwAAAIAOQAsAAQKgRcAAgoACAh8IbMDABADAAoACAh8IbMDABADAAAA.',Ny='Nyx:BAEBLAAECoEVAAIKAAgIgRrfCwBTAgg5DAAAAgBTADsMAAACADAAOgwAAAMAPQA8DAAAAwBSADIMAAADAFAAPQwAAAMAQQA+DAAAAwBNAD8MAAACACkACgAICIEa3wsAUwIIOQwAAAIAUwA7DAAAAgAwADoMAAADAD0APAwAAAMAUgAyDAAAAwBQAD0MAAADAEEAPgwAAAMATQA/DAAAAgApAAAA.',Om='Omenga:BAEALAAECgYICQAAAA==.',On='Onstarsniper:BAEALAAECgEIAQAAAA==.',Ot='Otsdarvaa:BAECLAAFFIEKAAITAAUIuxsKAAALAgU5DAAAAwBiADsMAAACAGQAOgwAAAMASgA8DAAAAQAUAD0MAAABAD0AEwAFCLsbCgAACwIFOQwAAAMAYgA7DAAAAgBkADoMAAADAEoAPAwAAAEAFAA9DAAAAQA9ACwABAqBHgACEwAICHglLwAAYgMAEwAICHglLwAAYgMAAAA=.',Ph='Photodragon:BAEALAAFFAMIBAAAAA==.Photoshield:BAEALAADCggICAABLAAFFAMIBAACAAAAAA==.Photoweave:BAEALAAFFAEIAQABLAAFFAMIBAACAAAAAA==.',Po='Pocketyuumi:BAECLAAFFIEKAAIUAAUInxYhAADVAQU5DAAAAgBNADsMAAADAEoAOgwAAAMAMgA8DAAAAQAUAD0MAAABAEMAFAAFCJ8WIQAA1QEFOQwAAAIATQA7DAAAAwBKADoMAAADADIAPAwAAAEAFAA9DAAAAQBDACwABAqBIAADFAAICI0jNQAATgMAFAAICI0jNQAATgMACgAICCUNGhYArwEAAAA=.',Pr='Prefab:BAEALAAECggIDwAAAA==.',Py='Pyromend:BAEBLAAECoEYAAIVAAgIByKNAQAaAwg5DAAAAwBhADsMAAADAGIAOgwAAAMAYAA8DAAAAwA2ADIMAAADAE8APQwAAAMAYAA+DAAAAwBbAD8MAAADAFIAFQAICAcijQEAGgMIOQwAAAMAYQA7DAAAAwBiADoMAAADAGAAPAwAAAMANgAyDAAAAwBPAD0MAAADAGAAPgwAAAMAWwA/DAAAAwBSAAEsAAUUAwgHABYARBUA.Pyromists:BAECLAAFFIEHAAIWAAMIRBWOAQAKAQM5DAAAAwA/ADoMAAADAEkAMgwAAAEAGgAWAAMIRBWOAQAKAQM5DAAAAwA/ADoMAAADAEkAMgwAAAEAGgAsAAQKgRgAAhYACAi7JIIAAFkDABYACAi7JIIAAFkDAAAA.Pyrotides:BAEALAAFFAIIAgABLAAFFAMIBwAWAEQVAA==.',Qu='Queasytwang:BAECLAAFFIEFAAIFAAMIFh5DAgAVAQM5DAAAAgBOADsMAAABAEgAOgwAAAIATwAFAAMIFh5DAgAVAQM5DAAAAgBOADsMAAABAEgAOgwAAAIATwAsAAQKgRwAAwYACAjSHtECACECAAUACAgyHL0MAGUCAAYABwjjGtECACECAAAA.',Ra='Raegi:BAEALAADCggICAABLAAECggIFQAXAD8gAA==.Raegx:BAEBLAAECoEVAAIXAAgIPyCHBgDtAgg5DAAAAwBcADsMAAADAGEAOgwAAAMAVAA8DAAAAwBVADIMAAADAFEAPQwAAAMAWgA+DAAAAgBSAD8MAAABAC4AFwAICD8ghwYA7QIIOQwAAAMAXAA7DAAAAwBhADoMAAADAFQAPAwAAAMAVQAyDAAAAwBRAD0MAAADAFoAPgwAAAIAUgA/DAAAAQAuAAAA.',Rc='Rctdk:BAEBLAAECoEXAAIYAAgI8iW1AABiAwg5DAAAAwBhADsMAAADAGIAOgwAAAMAYQA8DAAAAwBfADIMAAADAGIAPQwAAAMAYQA+DAAAAwBiAD8MAAACAF0AGAAICPIltQAAYgMIOQwAAAMAYQA7DAAAAwBiADoMAAADAGEAPAwAAAMAXwAyDAAAAwBiAD0MAAADAGEAPgwAAAMAYgA/DAAAAgBdAAAA.',Re='Recursion:BAEALAADCgIIAgAAAA==.',Ri='Ribblesz:BAEALAAECgMIBAABLAAECggIFgALAIcmAA==.Ribblez:BAEBLAAECoEWAAILAAgIhyZqAACQAwg5DAAAAwBjADsMAAADAGEAOgwAAAMAYwA8DAAAAwBjADIMAAADAGMAPQwAAAMAYwA+DAAAAwBhAD8MAAABAGAACwAICIcmagAAkAMIOQwAAAMAYwA7DAAAAwBhADoMAAADAGMAPAwAAAMAYwAyDAAAAwBjAD0MAAADAGMAPgwAAAMAYQA/DAAAAQBgAAAA.Riemiwar:BAECLAAFFIEFAAIZAAMIlh8LAQAgAQM5DAAAAgBaADsMAAABAEIAOgwAAAIAVgAZAAMIlh8LAQAgAQM5DAAAAgBaADsMAAABAEIAOgwAAAIAVgAsAAQKgRcAAhkACAhNJpgAAHIDABkACAhNJpgAAHIDAAAA.',Sa='Salessara:BAEALAAECgUIBwABLAAECggIEAACAAAAAA==.Samozi:BAEBLAAECoEfAAIWAAgINCFzAgDxAgg5DAAABABIADsMAAAEAF0AOgwAAAQAWgA8DAAABABGADIMAAAEAGEAPQwAAAQATgA+DAAABABfAD8MAAADAFEAFgAICDQhcwIA8QIIOQwAAAQASAA7DAAABABdADoMAAAEAFoAPAwAAAQARgAyDAAABABhAD0MAAAEAE4APgwAAAQAXwA/DAAAAwBRAAAA.',Se='Sentrytotems:BAEBLAAECoEYAAIaAAgI8x6WCQC7Agg5DAAAAwBcADsMAAADAFUAOgwAAAMASwA8DAAAAwBWADIMAAADADwAPQwAAAMAWAA+DAAAAwBHAD8MAAADAEgAGgAICPMelgkAuwIIOQwAAAMAXAA7DAAAAwBVADoMAAADAEsAPAwAAAMAVgAyDAAAAwA8AD0MAAADAFgAPgwAAAMARwA/DAAAAwBIAAAA.',Sh='Shaadh:BAEALAAECgcIDQAAAA==.Shamdanny:BAEALAAECgcIEAAAAA==.Shaox:BAEALAAECgMIAwAAAA==.',Si='Sillik:BAEBLAAECoEYAAIIAAgI1yLNBgDUAgg5DAAAAwBhADsMAAADAGEAOgwAAAMAUgA8DAAAAwBQADIMAAADAF0APQwAAAMAYQA+DAAAAwBJAD8MAAADAFwACAAICNcizQYA1AIIOQwAAAMAYQA7DAAAAwBhADoMAAADAFIAPAwAAAMAUAAyDAAAAwBdAD0MAAADAGEAPgwAAAMASQA/DAAAAwBcAAEsAAUUBggNAAcAbBwA.',Sk='Skarodk:BAEALAAECgEIAQABLAAECggIFQAbAGweAA==.Skàro:BAEBLAAECoEVAAIbAAgIbB4DBwDCAgg5DAAAAwBVADsMAAADAGIAOgwAAAMAPwA8DAAAAwAwADIMAAADAEgAPQwAAAMAXgA+DAAAAgBHAD8MAAABAFgAGwAICGweAwcAwgIIOQwAAAMAVQA7DAAAAwBiADoMAAADAD8APAwAAAMAMAAyDAAAAwBIAD0MAAADAF4APgwAAAIARwA/DAAAAQBYAAAA.',Sl='Slapsmcquack:BAEALAAECgcIDQABLAAFFAIIAgACAAAAAA==.Slonedog:BAECLAAFFIEIAAIDAAQI6xUXAQB9AQQ5DAAAAgAXADsMAAACAGEAOgwAAAMATgA9DAAAAQAZAAMABAjrFRcBAH0BBDkMAAACABcAOwwAAAIAYQA6DAAAAwBOAD0MAAABABkALAAECoEZAAIDAAgIgSQ7AwBAAwADAAgIgSQ7AwBAAwAAAA==.',So='Sonton:BAEALAAFFAQIBAAAAA==.',St='Stebwarlock:BAEALAAECgIIAgABLAAFFAMIAwACAAAAAA==.',Su='Suracha:BAEALAADCggICAABLAAECgYIBwACAAAAAA==.Surara:BAEALAAECgYIBwAAAA==.',Ti='Tinnblade:BAEBLAAECoEUAAILAAgIOhVhGwAgAgg5DAAAAwBGADsMAAADAEUAOgwAAAIAKgA8DAAAAwAvADIMAAADABwAPQwAAAMAMgA+DAAAAQA4AD8MAAACAEQACwAICDoVYRsAIAIIOQwAAAMARgA7DAAAAwBFADoMAAACACoAPAwAAAMALwAyDAAAAwAcAD0MAAADADIAPgwAAAEAOAA/DAAAAgBEAAEsAAQKCAgaABoAdiUA.Tinnfury:BAEBLAAECoEaAAIaAAgIdiWgAQBjAwg5DAAABABjADsMAAAEAGAAOgwAAAQAXwA8DAAAAwBgADIMAAACAGMAPQwAAAIAYQA+DAAAAwBfAD8MAAAEAFYAGgAICHYloAEAYwMIOQwAAAQAYwA7DAAABABgADoMAAAEAF8APAwAAAMAYAAyDAAAAgBjAD0MAAACAGEAPgwAAAMAXwA/DAAABABWAAAA.Tinnsoul:BAEALAAECgcIDQABLAAECggIGgAaAHYlAA==.',Tr='Trikki:BAECLAAFFIENAAMQAAYIhhkqAAA9AgY5DAAAAwA1ADsMAAACAFMAOgwAAAMAIwA8DAAAAgBeADIMAAABADQAPQwAAAIASAAQAAYIhhkqAAA9AgY5DAAAAgA1ADsMAAACAFMAOgwAAAMAIwA8DAAAAgBeADIMAAABADQAPQwAAAIASAAPAAEIoRCwCwBKAAE5DAAAAQAqACwABAqBGAADDwAICLkmKgAAowMADwAICLkmKgAAowMAEAAHCPofYwYAaAIAAAA=.Trikkikun:BAEALAAFFAIIAgABLAAFFAYIDQAQAIYZAA==.Trillithia:BAECLAAFFIENAAIHAAYIbBwOAABmAgY5DAAAAwBjADsMAAACAFoAOgwAAAMAYQA8DAAAAgAoADIMAAABADIAPQwAAAIAOgAHAAYIbBwOAABmAgY5DAAAAwBjADsMAAACAFoAOgwAAAMAYQA8DAAAAgAoADIMAAABADIAPQwAAAIAOgAsAAQKgRgAAgcACAh3JjoAAJEDAAcACAh3JjoAAJEDAAAA.Triphoon:BAEALAAECgYIBgABLAAECggIFQAWACUjAA==.',Un='Underdrivedh:BAECLAAFFIEFAAILAAMIswZpBADrAAM5DAAAAgAPADsMAAABABYAOgwAAAIADQALAAMIswZpBADrAAM5DAAAAgAPADsMAAABABYAOgwAAAIADQAsAAQKgR4AAgsACAgrIIEJAOoCAAsACAgrIIEJAOoCAAAA.Underdríve:BAEALAAECgMIAwABLAAFFAMIBQALALMGAA==.Unmedìcated:BAEALAADCgcIBgABLAAECgYIDAACAAAAAA==.',Uz='Uzara:BAEALAAFFAIIAgAAAA==.',Va='Vaesan:BAEALAADCggIDQAAAA==.Vashdan:BAEALAAECggIDgABLAAFFAUICgAMAPwcAA==.',Vi='Visaliano:BAEALAAECgcIDwAAAA==.',Vo='Voladis:BAEALAAECgMIAwAAAA==.Volkovod:BAECLAAFFIEGAAIcAAQIrxhaAACIAQQ5DAAAAgBeADoMAAACAEYAPAwAAAEAFAA9DAAAAQBEABwABAivGFoAAIgBBDkMAAACAF4AOgwAAAIARgA8DAAAAQAUAD0MAAABAEQALAAECoEYAAIcAAgIHiSPAgBIAwAcAAgIHiSPAgBIAwAAAA==.',Wi='Winti:BAEALAAECgcIBwABLAAFFAIIAgACAAAAAA==.',Wr='Wraethue:BAEALAADCgcIBwABLAAFFAMIBQAFABYeAA==.',Wu='Wuvs:BAEBLAAECoEXAAIFAAgIUB7iBwCrAgg5DAAAAwBGADsMAAADAFMAOgwAAAMAUwA8DAAAAwBPADIMAAADAFkAPQwAAAMAUwA+DAAAAwBOAD8MAAACADUABQAICFAe4gcAqwIIOQwAAAMARgA7DAAAAwBTADoMAAADAFMAPAwAAAMATwAyDAAAAwBZAD0MAAADAFMAPgwAAAMATgA/DAAAAgA1AAAA.',Xy='Xybeaned:BAEBLAAFFIEDAAIMAAIIRxA+CQClAAI5DAAAAgBHADoMAAABAAwADAACCEcQPgkApQACOQwAAAIARwA6DAAAAQAMAAEsAAUUBggLABoArxcA.Xyroleaf:BAEBLAAFFIELAAIaAAYIrxddAAAvAgY5DAAAAgBjADsMAAACAFcAOgwAAAMAPgA8DAAAAgBGADIMAAABAAAAPQwAAAEAKgAaAAYIrxddAAAvAgY5DAAAAgBjADsMAAACAFcAOgwAAAMAPgA8DAAAAgBGADIMAAABAAAAPQwAAAEAKgAAAA==.',Yi='Yitimo:BAEBLAAECoEVAAIWAAgIJSNcAQAiAwg5DAAAAwBgADsMAAADAF0AOgwAAAMAXAA8DAAAAwBiADIMAAADAGAAPQwAAAMAYgA+DAAAAgBUAD8MAAABADoAFgAICCUjXAEAIgMIOQwAAAMAYAA7DAAAAwBdADoMAAADAFwAPAwAAAMAYgAyDAAAAwBgAD0MAAADAGIAPgwAAAIAVAA/DAAAAQA6AAAA.',Ze='Zenfiddles:BAEALAAFFAIIAgAAAA==.',Zo='Zohe:BAEALAAECgQIBAABLAAFFAQIBQACAAAAAA==.Zohhe:BAEALAAFFAQIBQAAAQ==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end