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
 local lookup = {'Druid-Feral','Unknown-Unknown','Paladin-Retribution',}; local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adylina:BAAALAAECgYICwAAAA==.',Al='Alcholic:BAAALAADCggIEwAAAA==.Alindril:BAAALAADCgcIBwAAAA==.',Ap='Applejâcks:BAAALAAECgYIEgAAAA==.',Ar='Aranzeb:BAAALAAECgMIBAAAAA==.',At='Atpl:BAAALAADCggICAAAAA==.Atthegates:BAAALAAECgMIAwAAAA==.',Au='Auryx:BAAALAADCgcIEQAAAA==.',Az='Azrel:BAAALAADCggICAAAAA==.',Ba='Balbo:BAAALAADCgIIAgABLAAECggIHAABACEmAA==.Balto:BAABLAAECoEcAAIBAAgIISYdAAB/AwABAAgIISYdAAB/AwAAAA==.Bamcis:BAAALAADCggIDAAAAA==.Bananabread:BAAALAADCggIGAAAAA==.Bayleef:BAAALAAECgYICQAAAA==.',Be='Belac:BAAALAADCgQIBgABLAADCggICwACAAAAAA==.Beldr:BAAALAAECgMIBwAAAA==.',Bl='Bladè:BAAALAAECgEIAQAAAA==.',Bo='Boggieman:BAAALAAECgIIAgAAAA==.',Br='Brotherhood:BAAALAAECgYIDAAAAA==.Brèè:BAAALAADCgYICwAAAA==.',Bu='Bubblewood:BAAALAADCgYIBgAAAA==.Buckspally:BAAALAAECgEIAQAAAA==.Bushmaster:BAAALAADCggIDwAAAA==.',['Bæ']='Bær:BAAALAADCgYIBgAAAA==.',Ch='Chartreuse:BAAALAAFFAEIAQAAAA==.',Ci='Cindal:BAAALAADCggIEQAAAA==.',Cl='Cl:BAAALAADCggICwAAAA==.Cles:BAAALAADCgMIAwAAAA==.',Co='Conall:BAAALAAECgcIDwAAAA==.',Cu='Cuckymonster:BAAALAADCggICAAAAA==.Cupnewdle:BAAALAAECgYICQAAAA==.',Da='Dalkin:BAAALAAECgYIDAAAAA==.Damion:BAAALAADCggICwAAAA==.',De='Deathbygyatt:BAAALAADCgMIAwAAAA==.Deeznts:BAAALAADCgUIBQAAAA==.Dellarin:BAAALAADCggICAAAAA==.Deynaria:BAAALAADCgQIBAAAAA==.',Di='Dimfate:BAAALAAECgMIAwAAAA==.',Do='Doublfisting:BAAALAAECgMIBgAAAA==.',Dr='Dracdonny:BAAALAAECgcIDQAAAA==.Dragonsloot:BAAALAAECgYICQAAAA==.Drizzitt:BAAALAADCggIFAAAAA==.',Ec='Eclegun:BAAALAAFFAIIAwAAAA==.',Ed='Edgyuwu:BAAALAADCgYIDQAAAA==.',Eh='Ehunter:BAAALAADCgQIBAAAAA==.',El='Elaina:BAAALAADCgQIBAAAAA==.Eldrogarax:BAAALAAECgIIAgAAAA==.Elementtamer:BAAALAADCgcICQAAAA==.',Er='Erinathras:BAAALAAECgIIAgAAAA==.',Es='Espressó:BAAALAAECgEIAQAAAA==.',Ev='Evillynn:BAAALAADCgUIBQAAAA==.',Fo='Forlath:BAAALAAECgIIBAAAAA==.',Fr='Frogsbreath:BAAALAADCgEIAQAAAA==.',Ga='Galdrel:BAAALAADCgcIDgAAAA==.',Gi='Gilmar:BAAALAADCgYIBgAAAA==.',Gu='Gullveig:BAAALAADCgUIBAAAAA==.Guzzug:BAAALAADCgUIBQAAAA==.',Ha='Harveyspectr:BAAALAADCgcIDAABLAAECgcICwACAAAAAA==.',He='Heide:BAAALAADCggICgAAAA==.',Ho='Hoofling:BAAALAADCggICAAAAA==.Hordeelf:BAACLAAFFIEGAAIDAAMI0iMCAQAnAQADAAMI0iMCAQAnAQAsAAQKgRgAAgMACAjKJqAAAIoDAAMACAjKJqAAAIoDAAAA.Hordeforsure:BAAALAAECgcICAABLAAFFAMIBgADANIjAA==.',Ig='Igris:BAAALAAECgcICwAAAA==.',In='Inocruz:BAAALAADCgMIAwAAAA==.',Is='Isel:BAAALAAECgcIDgAAAA==.',Iz='Izanamì:BAAALAADCggICAABLAAECgYIEgACAAAAAA==.Izugzug:BAAALAAECgcIEwAAAA==.',Ja='Jadedxenvy:BAAALAAECgEIAQAAAA==.Jaffejoffer:BAAALAAECgYIDAAAAA==.Jak:BAAALAAECgYIDAAAAA==.Jayson:BAAALAADCgIIAgAAAA==.',Je='Jezuz:BAAALAADCgMIAwAAAA==.',Ju='Jullian:BAAALAADCgEIAQAAAA==.',Ka='Kachowdk:BAAALAAECgUIBAAAAA==.Kalea:BAAALAADCgYIBgAAAA==.Karlfucious:BAAALAADCgUIBQAAAA==.Kaysoon:BAAALAADCggICAAAAA==.',Ke='Kekson:BAAALAAECgMIAwAAAA==.',Li='Lilleyna:BAAALAAECgYICQAAAA==.Lizana:BAAALAADCgYICgAAAA==.',Lo='Lohwas:BAAALAADCgMIAwAAAA==.',Lu='Lunaticaxd:BAAALAAECgQICQAAAA==.',Ma='Magital:BAAALAAECgEIAQABLAAECgYICQACAAAAAA==.Makisan:BAAALAAECgIIAwAAAA==.',Mc='Mcherbin:BAAALAAECgMIAwAAAA==.',Me='Merune:BAAALAAECgEIAQAAAA==.',Mi='Miasmata:BAAALAAECgYICQAAAA==.Michaelj:BAAALAADCgYICAAAAA==.',Mo='Money:BAAALAAECgcIEQAAAA==.Moneyshotinc:BAAALAAECgMIAwAAAA==.',My='Mylene:BAAALAADCgEIAQAAAA==.',Na='Narrun:BAAALAAECgYICQAAAA==.',Ne='Neogosa:BAAALAAECgYIDAAAAA==.',No='Nobara:BAAALAADCggICAAAAA==.',Nu='Nuxo:BAAALAADCgcICgAAAA==.',Pr='Profitt:BAAALAAECgYICQAAAA==.Progar:BAAALAAECgYICAAAAA==.',Pu='Puglyfe:BAAALAAECgEIAQAAAA==.',Ra='Rabbidhalo:BAAALAAFFAIIAwAAAA==.',Re='Reevoke:BAAALAADCggICAAAAA==.',Ro='Ronoc:BAAALAADCgcICgAAAA==.',Se='Seearra:BAAALAADCgUIBwAAAA==.Semip:BAAALAAECgEIAQAAAA==.',Sh='Shamará:BAAALAADCgIIAgAAAA==.Shizznitt:BAAALAADCgIIAgAAAA==.',Si='Silverfoce:BAAALAADCgYICQAAAA==.',Sl='Slicey:BAAALAADCgYIBgAAAA==.',Sn='Snowscar:BAAALAAECgQIBAAAAA==.',St='Stan:BAAALAAECgIIAgABLAAFFAIIAwACAAAAAA==.Stantic:BAAALAAFFAIIAwAAAA==.Stantoo:BAAALAAECgcIBwABLAAFFAIIAwACAAAAAA==.Stormydaniel:BAAALAADCgYIBgAAAA==.',Sw='Swaglaives:BAAALAAECgYIDAAAAA==.',Ta='Tatertots:BAAALAADCgYICAAAAA==.Tauriel:BAAALAAECgQICAAAAA==.Taurrkil:BAAALAADCgcIBwAAAA==.',Ti='Tiberiius:BAAALAADCgYIBgAAAA==.Titus:BAAALAADCgMIAwAAAA==.',Tu='Turk:BAAALAADCgIIAgABLAAECgcICwACAAAAAA==.',Tw='Tweak:BAAALAADCgEIAQAAAA==.',Up='Uppercut:BAAALAADCggICAAAAA==.',Us='Ussford:BAAALAADCgIIAgAAAA==.',Va='Vanillasquid:BAAALAADCggICgAAAA==.',Vi='Vincentius:BAAALAAECgMIAwAAAA==.',Vo='Volteil:BAAALAADCggICwAAAA==.Voyicewylde:BAAALAAECgYICAAAAA==.',Wa='Warstomp:BAAALAAECgYIDQAAAA==.',We='Weak:BAAALAADCgUIBQAAAA==.',Wh='Whixx:BAAALAAECgMIBQAAAA==.Whý:BAAALAAECgMIBwAAAA==.',Wo='Wonsa:BAAALAADCgQIBAAAAA==.',Xn='Xnaisa:BAAALAAECgIIBAAAAA==.',Ye='Yekjr:BAAALAADCgQIBAAAAA==.',Zm='Zmr:BAAALAAECgYIDwAAAA==.',Zo='Zorkdog:BAAALAADCggIDgAAAA==.',['Æl']='Ælshaddai:BAAALAADCgYICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end