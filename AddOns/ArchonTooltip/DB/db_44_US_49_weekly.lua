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
 local lookup = {'Unknown-Unknown','Paladin-Holy','DemonHunter-Havoc','Warrior-Protection',}; local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abelresurekt:BAAALAADCgMIAwAAAA==.',Ac='Acra:BAAALAADCggIEAAAAA==.',Ae='Aellemman:BAAALAAECgMIAgAAAA==.',Ai='Aidrien:BAAALAAECgMIAwAAAA==.',Al='Aliane:BAAALAAECgMIBAAAAA==.Almondbutter:BAAALAADCgYIBgAAAA==.Aly:BAAALAAECgIIAgAAAA==.Alydara:BAAALAAECgMIAwAAAA==.',Am='Amadezon:BAAALAAECgEIAQAAAA==.Amahinto:BAAALAADCggICAAAAA==.',An='Anetra:BAAALAADCgIIAgAAAA==.Angzt:BAAALAADCgcIBwAAAA==.Antisabra:BAAALAADCggIBwABLAAECgUIBwABAAAAAA==.Anugra:BAAALAADCgIIAgABLAADCgcIBwABAAAAAA==.',Ar='Aramith:BAAALAADCgIIAgAAAA==.Aramoonsong:BAAALAAECgYIDwAAAA==.Arazaler:BAAALAAECgYICAAAAA==.',Au='Auraborealis:BAAALAAECgMIAwAAAA==.',Ba='Badaboom:BAAALAADCggIDwAAAA==.Balzamon:BAAALAAECgMIBAAAAA==.Bamblebee:BAAALAAECgEIAQAAAA==.Bamsis:BAAALAADCgcIBwAAAA==.Bandgeek:BAAALAAECgIIAwAAAA==.',Be='Beegood:BAAALAADCgMIAwAAAA==.Bendicion:BAAALAAECgcIBwAAAA==.',Bi='Biebert:BAAALAAECgMIBgAAAA==.Bizzy:BAAALAAECgEIAQAAAA==.',Bl='Bloodegg:BAAALAAECgYICQAAAA==.',Br='Broomphondle:BAAALAADCggIDwAAAA==.',Bs='Bshoottu:BAAALAAECgEIAQAAAA==.',Bu='Bunyuck:BAAALAAECgIIAwAAAA==.Buttmuscles:BAAALAAECgMIBQAAAA==.',Bz='Bzabas:BAAALAADCgIIAgAAAA==.',Ch='Chawn:BAAALAAECgIIAgAAAA==.Cheveyo:BAAALAADCggIDAAAAA==.Chipster:BAAALAADCgEIAQAAAA==.Chromesatan:BAAALAAECgMIBgAAAA==.',Cu='Cupper:BAAALAADCgEIAQAAAA==.',Da='Daedri:BAAALAAECggIDwABLAADCgEIAQABAAAAAA==.Daeragon:BAAALAADCgMIAwAAAA==.Daespells:BAAALAADCgEIAQAAAA==.Dak:BAAALAADCgYIBgAAAA==.Darkdrittz:BAAALAADCggICgAAAA==.',De='Deathbynade:BAAALAAECgEIAQAAAA==.Deathclaw:BAAALAAECgYIDQAAAA==.Decimate:BAAALAAECgIIAgAAAA==.Deldúwath:BAAALAAECgEIAQAAAA==.Delenn:BAAALAAECgMIAwAAAA==.Deroera:BAABLAAECoEWAAICAAgIbh90AwC2AgACAAgIbh90AwC2AgAAAA==.',Di='Dionus:BAAALAAECgMIAwAAAA==.',Do='Dolorquedura:BAAALAADCgQIBAAAAA==.Donkeyman:BAAALAAECgMIBAAAAA==.',Dr='Drapaco:BAAALAADCgMIBQAAAA==.',['Dü']='Düümdüüdy:BAAALAAECgMIAwAAAA==.',Em='Embers:BAAALAADCggIEwAAAA==.Emishan:BAAALAADCgUIBQAAAA==.',En='Enux:BAAALAADCgMIBAAAAA==.',Er='Erina:BAAALAAECgEIAQAAAA==.',Es='Esmër:BAAALAADCgcICQAAAA==.',Ev='Evokyn:BAAALAADCgYICgAAAA==.',Fl='Flubb:BAAALAAECgYIDAAAAA==.',Fo='Followmenot:BAAALAADCgIIAgAAAA==.',Fu='Fundip:BAAALAAECgEIAQAAAA==.Fungurl:BAAALAADCgYIAgAAAA==.',Ga='Garethbryne:BAAALAAECgMIAwAAAA==.',Ge='Gerpejuice:BAAALAAECgcIEQAAAA==.',Gl='Gleaming:BAAALAADCggIFwABLAAECggIFgACAG4fAA==.',Go='Gosudizzle:BAAALAAECgEIAQABLAAECgYIBAABAAAAAA==.',Gr='Grexai:BAAALAADCggICQAAAA==.Grogu:BAAALAADCgIIAgAAAA==.Grungý:BAAALAADCggICAAAAA==.',Gw='Gwendolyn:BAAALAAECgUICQABLAAECgYIDwABAAAAAA==.',He='Hekaté:BAAALAAECgMIBgAAAA==.',Hm='Hmooß:BAAALAADCgQIBAAAAA==.',Ho='Holypowder:BAAALAADCgUIBQAAAA==.Holypriést:BAAALAADCgcIBwAAAA==.Hoss:BAAALAADCgMIAwAAAA==.',Ib='Iboinky:BAAALAADCgYICQAAAA==.',Il='Illimommy:BAABLAAECoEWAAIDAAgIUCWVAQBxAwADAAgIUCWVAQBxAwAAAA==.',Ip='Iplayleague:BAAALAAECgUIBwAAAA==.',Iz='Izzyrael:BAABLAAECoEYAAIEAAcIySOkAwDQAgAEAAcIySOkAwDQAgAAAA==.',Je='Jerey:BAAALAAECgUIBQAAAA==.',Ji='Jitlo:BAAALAAECggIDwAAAA==.',Ju='Juanillo:BAAALAADCgQIBgAAAA==.',Ka='Kairos:BAAALAADCggIEAAAAA==.Kalanrahl:BAAALAAECgMIAwAAAA==.Kaldaern:BAAALAAECgUIBQAAAA==.Kapootz:BAAALAADCgcICwAAAA==.',Kh='Khaiduus:BAAALAAECgMIBQAAAA==.Khéma:BAAALAADCggICAAAAA==.',Ko='Kolora:BAAALAADCggIFgAAAA==.Kottenmouth:BAAALAAECggIEgAAAA==.',Kr='Kritea:BAAALAAECgcIDAAAAA==.',Ku='Kurastrasz:BAAALAAECgUIBwAAAA==.',Ky='Kydeath:BAAALAADCggIDwAAAA==.',La='Lanasia:BAAALAAECgEIAQAAAA==.',Le='Lebron:BAAALAADCggICAAAAA==.Legionish:BAAALAADCgUIBQAAAA==.',Li='Life:BAAALAADCggIEAAAAA==.Lightsrael:BAAALAAECgMIAwAAAA==.Littledope:BAAALAAECgYIBAAAAA==.',Lo='Locura:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.',Lu='Luanabubana:BAAALAADCgYIBgAAAA==.Luewd:BAAALAADCgYIBgAAAA==.',Ma='Madame:BAAALAADCgUIBQAAAA==.Makarii:BAAALAAECgYICgAAAA==.Maniacal:BAAALAADCgcIBwAAAA==.Markonis:BAAALAAECgMIAwAAAA==.Maven:BAAALAADCgYIBgAAAA==.Maximovrdrve:BAAALAADCgMIBQAAAA==.',Me='Merion:BAAALAADCgYIAgAAAA==.Metashot:BAAALAAECgIIAgAAAA==.',Mi='Missxaxas:BAAALAADCggICAAAAA==.',Mo='Mockruji:BAAALAADCgEIAQAAAA==.Moira:BAAALAADCgYICQAAAA==.Moloken:BAAALAAECgEIAQAAAA==.Moraldecay:BAAALAAFFAIIAgABLAADCgUIBQABAAAAAQ==.Morwen:BAAALAADCgEIAQAAAA==.Motryn:BAAALAADCgcIBwAAAA==.Movalon:BAAALAAECgcIDQAAAA==.',My='Mymonk:BAAALAAECgMIBAAAAA==.',Na='Naarugopal:BAAALAADCgcIBwAAAA==.Nativelock:BAAALAADCggIFQAAAA==.Nativetank:BAAALAADCggIEgAAAA==.Nativéhunter:BAAALAADCggIDgAAAA==.',Ne='Nephilim:BAAALAAECgIIAQAAAA==.Nerishana:BAAALAADCgcIDQAAAA==.',No='Noctavian:BAAALAAECgMIBgAAAA==.',Ny='Nynnaeve:BAAALAAECgMIAwAAAA==.',['Nú']='Núrnen:BAAALAADCgYIBgAAAA==.',On='Onthecoda:BAAALAAECgEIAQAAAA==.',Op='Opani:BAAALAADCgUIBQAAAA==.',Or='Orish:BAAALAAECgMIAwAAAA==.',Pa='Pantherarosa:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Papalock:BAAALAADCgcIEgAAAA==.',Pe='Persymphony:BAAALAAECgMIBgAAAA==.',Ph='Phabio:BAAALAAECgMIBgAAAA==.',Pi='Pineappletea:BAAALAAECgYIDQAAAA==.Pinklock:BAAALAADCggICAAAAA==.',Ps='Psychonut:BAAALAADCggIDwAAAA==.',Qu='Quesy:BAAALAAECgYICgAAAA==.',Ra='Rasz:BAAALAAECgMIBgAAAA==.',Re='Rebelmonk:BAAALAADCgIIAgAAAA==.Rennl:BAAALAADCgcICAAAAA==.',Rh='Rhodeo:BAAALAADCgQIBAAAAA==.Rhutuuzy:BAAALAADCgYICQAAAA==.',Ri='Ripsets:BAAALAAECgMIAwAAAA==.Rizzgodizz:BAAALAADCgcIBwAAAA==.',Ro='Rosalind:BAAALAAECgMIBgAAAA==.',['Rä']='Rägnämagixx:BAAALAAECgEIAQAAAA==.',Sa='Sanxyn:BAAALAADCgMIAwAAAA==.Sarigos:BAAALAAECgMIAQAAAA==.',Sc='Schieldemon:BAAALAAECgYICQAAAA==.Scrythe:BAAALAAECgMIBgAAAA==.Scylla:BAAALAAFFAMIBAAAAA==.',Se='Senas:BAAALAADCgUIBQAAAA==.',Sh='Shalerwina:BAAALAADCggIEAAAAA==.Shaleshok:BAAALAADCggIFAAAAA==.Sharkyf:BAAALAADCgUICAAAAA==.Shiggz:BAAALAAECgIIAgAAAA==.Shorthunter:BAAALAADCgUIBgAAAA==.Shrodwrah:BAAALAAECgMIBQAAAA==.Shôckolate:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',Sk='Skkarrgh:BAAALAADCgcICgAAAA==.Skroc:BAAALAADCgcICQAAAA==.',Sm='Smalliebiggs:BAAALAADCgEIAQAAAA==.',St='Steelehorn:BAAALAAECgUICgAAAA==.Stubb:BAAALAADCgYIBgAAAA==.Stuef:BAAALAAECgYIDAAAAA==.Stylish:BAAALAAECgMIAwAAAA==.',Su='Suzel:BAAALAADCgQIBAAAAA==.',Sy='Syryn:BAAALAADCggIDgAAAA==.',Ta='Talasacerdos:BAAALAAECgUIBgAAAA==.',Te='Tekk:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.',Th='Thicc:BAAALAADCgMIAwAAAA==.Thorgrum:BAAALAAECgMIBgAAAA==.Thundersrest:BAAALAADCgYIBgAAAA==.Thvrzday:BAAALAADCgcIBwAAAA==.',Ti='Tillandra:BAAALAAECgEIAQAAAA==.',Tr='Trastuzumab:BAAALAADCgEIAQAAAA==.Treant:BAAALAAECgMIAwAAAA==.Trenezath:BAAALAADCggIAgAAAA==.',Tw='Twistedpally:BAAALAADCgUICgAAAA==.',Tz='Tzzird:BAAALAAECgMIAwAAAA==.',Va='Vain:BAAALAADCgcIBwAAAA==.Valatonin:BAAALAADCggICAAAAA==.',Ve='Verb:BAAALAADCgEIAQAAAA==.',Vi='Violentse:BAAALAADCgQIBAAAAA==.',Wa='Waltz:BAAALAAECgYICwAAAA==.Wartrick:BAAALAAECgUIBgAAAA==.',Wh='Whoudini:BAAALAAECgMIBAAAAA==.',Xe='Xerãth:BAAALAAECgMIBgAAAA==.',Ya='Yaviel:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.',Yo='Yoshimitsu:BAAALAADCgEIAQAAAA==.',Yu='Yuugerel:BAAALAADCgcICAAAAA==.',Za='Zaaren:BAAALAADCgMIBAABLAAECgUIBwABAAAAAA==.Zackaran:BAAALAADCggIFwAAAA==.',Ze='Zelderk:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Zeromus:BAAALAAECgMIAwAAAA==.',Zh='Zhenlim:BAAALAAECggIEgAAAA==.',Zo='Zoidbergg:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Zortmier:BAAALAAECgMIBgAAAA==.',Zu='Zurugorash:BAAALAADCgUICQAAAA==.',['Ès']='Èsmer:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end