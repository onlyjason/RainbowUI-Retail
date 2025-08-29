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
 local lookup = {'Unknown-Unknown','Warlock-Destruction','Monk-Windwalker',}; local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acallia:BAAALAADCggIDQAAAA==.Achkmed:BAAALAAECggICAAAAA==.',Ad='Adolin:BAAALAAECgMIBgAAAA==.',Ae='Aevoss:BAAALAADCgEIAQAAAA==.',Ai='Airesyll:BAAALAADCgcIBwAAAA==.',Ak='Akalon:BAAALAAECgMIBAAAAA==.',Al='Allfrost:BAAALAADCgMIAwAAAA==.Aluda:BAAALAAECgIIAgAAAA==.Alyssaia:BAAALAAECgMIBAAAAA==.',Am='Amimela:BAAALAADCgUIBQAAAA==.',Ao='Aoeina:BAAALAAECgMIBgAAAA==.',Ap='Apollo:BAAALAADCgcIFAAAAA==.',Aq='Aquinas:BAAALAADCgcIEAABLAAECgMIBQABAAAAAA==.',Ar='Ariaves:BAAALAAECgcIDgAAAA==.Arioriaa:BAAALAAECgIIAgAAAA==.Artovias:BAAALAAECgYICQAAAA==.',Au='Augmussy:BAAALAADCgcIDwAAAA==.',Av='Avelyn:BAAALAAFFAEIAQABLAAFFAIIBAABAAAAAA==.',Az='Azem:BAAALAAECgMIAwAAAA==.',Ba='Bahamut:BAAALAADCggICAAAAA==.',Bl='Blackendmoon:BAAALAADCgMIBAAAAA==.Blackløtus:BAAALAADCgMIAwAAAA==.Bluebeary:BAAALAADCgMIAwAAAA==.Bluelocks:BAAALAAECgYIDAAAAA==.',Ca='Calcypher:BAAALAAECgQIBAAAAA==.Camiliana:BAAALAADCggIDQAAAA==.',Ce='Cellturin:BAAALAADCgYICQAAAA==.',Ch='Charizard:BAAALAAECgMIAwAAAQ==.Chiarakai:BAAALAADCgUICwAAAA==.',Cl='Cloudia:BAAALAADCgcIDwAAAA==.',Cr='Crawley:BAAALAAECgMIBwAAAA==.Creeder:BAAALAAECgcIDwAAAA==.Cringe:BAAALAADCggIBgABLAADCggIDgABAAAAAA==.Crixus:BAAALAAECgMIBAAAAA==.',Cy='Cynise:BAAALAAECgEIAQAAAA==.',Da='Dagolux:BAAALAADCgQIBAAAAA==.Darkbread:BAAALAADCggIFgAAAA==.',De='Deaanor:BAAALAADCggIDwAAAA==.Deathcòw:BAAALAAECgYIDAAAAA==.Demonmode:BAAALAAECgMIBQAAAA==.Deween:BAAALAADCggIBQAAAA==.',Di='Dionysuz:BAAALAADCgIIAgAAAA==.',Do='Dojoro:BAAALAAECgMIBQAAAA==.',Dr='Draegare:BAAALAAECgMIAwAAAA==.Drdeer:BAAALAAECgMIBQAAAA==.Drdruid:BAAALAADCggICAAAAA==.',Eo='Eoghain:BAAALAAECgIIAgAAAA==.',Et='Eternalx:BAAALAADCgMIAwAAAA==.',Ev='Evaelfie:BAAALAAECgYICQAAAA==.Everd:BAAALAADCgcICAAAAA==.Evilkitty:BAAALAAECgIIBAAAAA==.',Fa='Faelar:BAAALAADCgEIAQAAAA==.',Fe='Felphox:BAAALAAECgEIAQAAAA==.',Fi='Fiametta:BAAALAAECgEIAQAAAA==.',Fl='Flameward:BAAALAADCgYIBgAAAA==.Florisaa:BAAALAADCggICQABLAAECgYIBQABAAAAAA==.',Fr='Frostborn:BAAALAAECgMIAwAAAA==.',Gl='Glendria:BAAALAADCggICAAAAA==.',Ha='Haplo:BAAALAADCgMIAwAAAA==.Harps:BAAALAADCggICAAAAA==.',He='Healthstoned:BAAALAADCggICAAAAA==.Hey:BAAALAAECgYICQAAAA==.',Ho='Hotstreak:BAAALAADCgYIBgAAAA==.',Hu='Huntmeister:BAAALAAECggIEgAAAA==.Huogmi:BAAALAADCgYIBgAAAA==.',Ic='Iceehawt:BAAALAAECgMIBQAAAA==.',Il='Illuminara:BAAALAADCgUIDQAAAA==.',Ir='Irmis:BAAALAAECgMIBQAAAA==.',Iu='Iupiter:BAAALAAECgEIAQAAAA==.',Iz='Izabeth:BAAALAAECgMIBAAAAA==.Izari:BAAALAADCgcIDQAAAA==.',Ja='Jamella:BAAALAAECgMIAwAAAA==.',Je='Jennjenn:BAAALAAECgUICAAAAA==.Jexams:BAAALAAECgMIAwAAAA==.',Ji='Jinshi:BAAALAADCgcIDwAAAA==.',['Jê']='Jêricho:BAAALAADCgUIBgAAAA==.',Ka='Kaceylan:BAAALAAECgIIAgAAAA==.Kagosi:BAAALAAECgMICAAAAA==.Kalaedin:BAAALAADCgYIBgAAAA==.Karrh:BAAALAADCgUIBQAAAA==.Kat:BAAALAAECgMIAwAAAA==.Kate:BAAALAADCgcIEAAAAA==.Kazakusan:BAAALAADCgQIBAAAAA==.',Ki='Kialla:BAAALAADCgUICQAAAA==.Kirayne:BAAALAAECgMIBAAAAA==.Kittie:BAAALAAECgMIBQAAAA==.',Ko='Kobie:BAAALAADCggICAAAAA==.Kogra:BAAALAADCgUIBQAAAA==.',Kr='Kreyaline:BAAALAAECgMIBAAAAA==.Krinj:BAAALAAECgcIDgAAAA==.',Ky='Kyarla:BAAALAAECgUIBwAAAA==.',Le='Leahim:BAAALAAECgMICAAAAA==.Ledani:BAAALAAECgMIBQAAAA==.Lenicore:BAAALAAECgYICAAAAA==.',Li='Lividzhealer:BAAALAAECgEIAgAAAA==.',Lo='Lockmeup:BAAALAAECgMIBQAAAA==.Lohith:BAAALAAECgcIDwAAAA==.Lonedawg:BAAALAADCgMIAwAAAA==.',Lu='Lumberjak:BAAALAADCgEIAQAAAA==.',Ma='Mayael:BAAALAAECgMIAwAAAA==.',Me='Medreaux:BAAALAAECgQIBwAAAA==.',Mi='Miniknyte:BAAALAAECgMIBAAAAA==.',Mo='Mohu:BAAALAADCggICQAAAA==.',Mu='Mugmug:BAAALAAECgMIBAAAAA==.',My='Mychelle:BAAALAAECgMIBQAAAA==.',['Mä']='Mägë:BAAALAADCgMIAwAAAA==.',['Mø']='Møgwai:BAAALAADCggICAAAAA==.',Na='Naryeth:BAAALAADCgIIAgAAAA==.Natja:BAAALAADCgUICQABLAAECgMIBAABAAAAAA==.Nayki:BAAALAAECgMIBAAAAA==.',Ni='Nightmares:BAAALAADCgcIDgAAAA==.Niterend:BAAALAAECgUICQABLAABCgMIAwABAAAAAA==.',Nu='Nugehuts:BAAALAADCgUIBQABLAAFFAUICwACALUlAA==.',Ny='Nyra:BAAALAAECgYIDQAAAA==.',Oc='Ocelott:BAAALAADCgcICgAAAA==.',Or='Oriel:BAAALAAECgMIBAAAAA==.',Pa='Pain:BAAALAADCgQIBAAAAA==.Pandøra:BAAALAADCggIBQABLAAECgYIBQABAAAAAA==.',Pl='Plumpcheeks:BAAALAADCgcIBwAAAA==.',Po='Poc:BAAALAAECgIIAQAAAA==.Poppett:BAAALAADCgUIBQAAAA==.',Pr='Prinsana:BAAALAAECgMIBAAAAA==.',Re='Reaperlord:BAAALAAECgMIBwAAAA==.Redknyte:BAAALAAECgMIBAAAAA==.Redtooth:BAAALAAECgMIBAAAAA==.',Rl='Rlyeh:BAAALAAECgQIBwAAAA==.',Ro='Rodikus:BAAALAAECgMIBAAAAA==.Rorax:BAAALAAECgIIAgAAAA==.',['Rê']='Rêlix:BAAALAADCgIIBQAAAA==.',Sa='Sakeena:BAAALAADCgMIAwAAAA==.Sandp:BAAALAAECgIIAgAAAA==.Saora:BAAALAAECgIIAgAAAA==.',Sh='Shamomile:BAAALAADCggIDQAAAA==.Shinokishi:BAAALAAECgIIAgAAAA==.Shrezsan:BAAALAADCgMIAwAAAA==.Shìvaa:BAAALAADCgEIAQABLAADCgQIBAABAAAAAA==.',Si='Silentninjaa:BAAALAAECgMIBAAAAA==.Sinfel:BAAALAAECgMIBQAAAA==.',Sk='Skorivoker:BAAALAAECgcIDwAAAA==.',Sn='Snapgodx:BAABLAAECoEdAAIDAAgIbiXJAABhAwADAAgIbiXJAABhAwAAAA==.',So='Sonett:BAAALAADCgMIAwAAAA==.',Sp='Spankii:BAAALAADCgcIDAAAAA==.Spankysdwarf:BAAALAADCggIDgAAAA==.',St='Stariya:BAAALAADCgMIAwAAAA==.Stormrunner:BAAALAAECgEIAQAAAA==.Strawyã:BAAALAAECgMIAwAAAA==.',Sy='Syridia:BAAALAADCgQIBAAAAA==.',['Sì']='Sìrocco:BAAALAAECgcIBwAAAA==.',Ta='Tamerizer:BAAALAAECgMIBgAAAA==.Tanky:BAAALAAECgcIDwAAAA==.',Te='Tealera:BAAALAAECgYIBQAAAA==.Tebiki:BAAALAADCgUIAgAAAA==.Terrana:BAAALAAECgMIAwAAAA==.Tevah:BAAALAAECgMIBAAAAA==.',Th='Thirge:BAAALAAECgMIBQAAAA==.Thump:BAAALAAECgEIAQAAAA==.',Ti='Tinksy:BAAALAADCgEIAQAAAA==.',To='Tolak:BAAALAAECgMIBQAAAA==.Tomoto:BAAALAAECgMIBAAAAA==.Torturousôwl:BAAALAADCgUIBQAAAA==.',Tr='Trisky:BAAALAAECgMIAwAAAA==.',Tu='Tunip:BAAALAAECgMIAwAAAA==.',Ty='Tyflos:BAAALAAECgMIAwAAAA==.',['Tá']='Tánatos:BAAALAAECgMIBAAAAA==.',Un='Ungabonk:BAAALAAECgMICAAAAA==.',Va='Vaceriss:BAAALAAECgIIAgAAAA==.Valdrakkquin:BAAALAAECgcIDwAAAA==.Valhunta:BAAALAAECgQIBAAAAA==.',Vo='Vorpine:BAAALAAECgMIBQAAAA==.',Wa='Warturtle:BAAALAAECgEIAQAAAA==.Wazcrates:BAAALAAECgEIAQAAAA==.Wazrome:BAAALAADCgcIDAAAAA==.',Wh='Whitemonster:BAAALAADCgIIAgAAAA==.',Xa='Xanthrash:BAAALAADCgcIFgAAAA==.Xantia:BAAALAAECgMIBgAAAA==.Xaridari:BAAALAAECgcICAAAAA==.',Za='Zaizel:BAAALAAFFAIIAgAAAA==.Zalulu:BAAALAAECgYICAAAAA==.Zathennyx:BAAALAADCggIBwABLAAECgYIBQABAAAAAA==.',Ze='Zercus:BAAALAADCgcIBwAAAA==.',Zo='Zoel:BAAALAADCgQIBAAAAA==.',Zu='Zuwumom:BAAALAADCggIDgAAAA==.',['Åf']='Åffie:BAAALAADCggIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end