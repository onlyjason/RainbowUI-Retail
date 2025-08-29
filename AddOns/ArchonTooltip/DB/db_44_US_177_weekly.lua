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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','DemonHunter-Havoc','Paladin-Holy','Paladin-Retribution','Druid-Restoration',}; local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abelas:BAAALAADCgIIAgAAAA==.',Ac='Acell:BAAALAAECgMIBgAAAA==.Acolyte:BAAALAAECgYIDgAAAA==.',Ad='Adiliia:BAAALAADCgIIAgAAAA==.Adzen:BAAALAADCgUIBQAAAA==.Adêrna:BAAALAAECgMIAwAAAA==.',Ag='Agba:BAAALAAECgUICAAAAA==.',Ak='Akando:BAAALAADCgQIBAAAAA==.',Al='Alaidan:BAAALAAECgMIAwAAAA==.Alanus:BAAALAAECgMIBQAAAA==.Alatara:BAAALAADCgcICQAAAA==.',An='Anbey:BAAALAAECgEIAQAAAA==.Andìel:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Anirev:BAAALAADCgYIBgAAAA==.Annafe:BAAALAAECgMIBAAAAA==.Annale:BAAALAADCggICAAAAA==.Anota:BAAALAADCggIGAAAAA==.Anzala:BAAALAADCggICAAAAA==.',Ar='Aralae:BAAALAADCgMIAwAAAA==.Argas:BAAALAADCgMIAwAAAA==.Armsmaster:BAAALAAECgUIBQAAAA==.Aruneea:BAAALAAECgMIAwAAAA==.',At='Atorius:BAAALAADCgcIBwAAAA==.',Av='Avengharambe:BAAALAADCggIDwAAAA==.Averan:BAAALAADCggIFwAAAA==.Averybug:BAAALAADCgQIBAAAAA==.Avtermath:BAAALAAECgMIAwABLAAECgcIFwACAGMlAA==.Avtershock:BAAALAADCggICAABLAAECgcIFwACAGMlAA==.',Az='Azybra:BAAALAADCgYIBgAAAA==.',Ba='Badmojo:BAAALAADCgcICgAAAA==.Bagofdonuts:BAAALAAECgcIEAAAAA==.Balduun:BAAALAADCggIFQAAAA==.Baridar:BAAALAADCgcIBwAAAA==.',Bb='Bbawbhy:BAAALAADCgYIBgAAAA==.',Bj='Bjorii:BAAALAADCgEIAQAAAA==.',Bl='Blacat:BAAALAAECgYIBgAAAA==.Bloodbenders:BAAALAAECgIIAgAAAA==.Bloodstrain:BAAALAAECgYICAAAAA==.',Br='Braswell:BAAALAADCgQIBAAAAA==.Brondeadeye:BAAALAADCggICAAAAA==.',Bu='Buddypriest:BAAALAAECgMIAwAAAA==.Buttonsmashr:BAAALAADCgMIAwAAAA==.',Ca='Catizard:BAAALAADCggICAAAAA==.',Ch='Chlorox:BAAALAAECgEIAQAAAA==.',Co='Cosmicdragon:BAAALAADCgcIDgAAAA==.',Cr='Crovaxis:BAAALAAECgMIBgAAAA==.',Da='Daedrìc:BAAALAAECgEIAQAAAA==.Damagetaken:BAAALAADCggICAAAAA==.Darkliege:BAAALAADCgcIDQAAAA==.Darktalyn:BAAALAAECgMIBgAAAA==.Dasserlond:BAAALAAECgMIAwAAAA==.',De='Deadclef:BAAALAADCggICAAAAA==.Deathphoenix:BAAALAAECgIIAgAAAA==.Deekura:BAAALAADCggIIwAAAA==.Deetee:BAAALAADCgYIBgAAAA==.Delusion:BAAALAADCgcIEgAAAA==.Demondancer:BAAALAADCgYIBgAAAA==.Derfzak:BAAALAADCgYIBAAAAA==.',Di='Diezelrific:BAAALAAECgYICQAAAA==.Dionan:BAAALAAECgMIBgAAAA==.Disa:BAAALAADCgcIDwAAAA==.',Do='Doks:BAAALAAECgIIAgAAAA==.Dotdotjezz:BAAALAAECgcIEAAAAA==.',Dr='Dragda:BAAALAADCggIFwAAAA==.Dragõn:BAAALAADCgcIDgAAAA==.Drakon:BAAALAAECgEIAQAAAA==.',Ea='Ealara:BAAALAAECgIIAwAAAA==.',Ei='Eifel:BAAALAADCggICAAAAA==.',El='Elendriel:BAAALAAECgEIAQAAAA==.Elvrag:BAAALAAECgEIAQAAAA==.',Em='Emiira:BAAALAADCgMIAwAAAA==.',Ev='Evilrages:BAAALAADCggICAAAAA==.',Ex='Exyle:BAAALAADCgYIBgAAAA==.',Ez='Ezaral:BAAALAADCggIEAAAAA==.',Fa='Fallen:BAAALAADCggIDwAAAA==.Faustnyr:BAAALAAECgEIAQAAAA==.Fayenia:BAAALAADCgYIBgAAAA==.Faynor:BAAALAADCggIFwAAAA==.',Fe='Felstrike:BAAALAADCgEIAQABLAADCgcICgABAAAAAA==.',Fi='Finimus:BAAALAADCggICAAAAA==.',Fl='Flowers:BAAALAAECgMIBgAAAA==.',Fr='Frostbité:BAAALAAECgMIAwAAAA==.Fruit:BAAALAADCgcIDgAAAA==.',Fu='Fuzzbâll:BAAALAADCgQIBAAAAA==.',Ga='Gali:BAAALAADCggIFwAAAA==.',Ge='Gertrude:BAAALAADCgMIAwABLAAECgMIBAABAAAAAA==.',Gl='Glaistiguain:BAAALAAECgMIBAABLAAECgUIBQABAAAAAA==.Gloomstalkin:BAAALAADCgYIDAABLAAECgMIAwABAAAAAA==.',Gr='Gr:BAAALAAECgMIBgAAAA==.Grendelsmama:BAAALAADCggIFQAAAA==.Greninjaa:BAAALAADCggIDwAAAA==.Gryffs:BAAALAAECgYICQAAAA==.',Gu='Gudwin:BAAALAAECgIIAgAAAA==.Gutts:BAAALAAECgMIBgAAAA==.',Gy='Gypsia:BAAALAADCgMIAwABLAAECgEIAgABAAAAAA==.',Ha='Happi:BAAALAADCgYIBgABLAAECggIGAADACskAA==.Hardwire:BAAALAADCgcIBwABLAAECgcIFwACAGMlAA==.Harlemix:BAAALAADCggIFQAAAA==.Harsetti:BAAALAADCgcIAgAAAA==.Haruun:BAAALAADCggIEgAAAA==.',He='Helltowicked:BAAALAADCggIDwAAAA==.Hesmydaddy:BAAALAAECgMIAwAAAA==.Heztok:BAAALAAECgQIBwAAAA==.',Ho='Horse:BAAALAAECgMIAwAAAA==.',Hp='Hpmor:BAAALAAECgMIBAABLAAECgUIBQABAAAAAA==.',['Hö']='Höneÿdew:BAAALAAECgYICgAAAA==.',Ia='Iashai:BAAALAAECgMIBAAAAA==.',Ik='Ikkaj:BAAALAADCgQIBQABLAADCgYIBgABAAAAAA==.',Im='Immortalhulk:BAAALAADCgcIBwAAAA==.',In='Infernoak:BAAALAADCgMIBAAAAA==.',Ir='Ironsights:BAAALAAECgcIDQAAAA==.',Is='Ishkah:BAAALAADCggIDAAAAA==.',Iz='Izuall:BAAALAADCgIIAgAAAA==.Izånåmi:BAAALAADCgMIAwAAAA==.',Ja='Jarrack:BAAALAADCggIFwAAAA==.',Je='Jessicae:BAAALAAECgEIAQAAAA==.',Ka='Kayfabe:BAAALAAECgMIBAAAAA==.',Ke='Kenel:BAAALAAECgMIAwAAAA==.Keris:BAAALAADCggIFwAAAA==.Kerztek:BAAALAAECgMIAwAAAA==.',Ki='Kicken:BAAALAADCggIGAAAAA==.Kikanila:BAAALAADCggIFAAAAA==.Kitschy:BAAALAADCggIDwAAAA==.',Ko='Koana:BAAALAAECggICAAAAA==.Korthelan:BAAALAAECgMIAwAAAA==.Kothara:BAAALAADCgIIAgAAAA==.Koufax:BAAALAADCggIGAAAAA==.',Kr='Krimzin:BAABLAAECoEXAAICAAcIYyUMBwDxAgACAAcIYyUMBwDxAgAAAA==.Krystine:BAAALAADCgcIDgAAAA==.',Ku='Kuball:BAAALAADCgcICQABLAAECgMIBgABAAAAAA==.',Ky='Kymu:BAAALAADCgcIBwAAAA==.',['Kî']='Kîllara:BAAALAAECgYICQAAAA==.',La='Landskies:BAAALAADCgYIBwAAAA==.Lanskies:BAAALAAECgMIAwAAAA==.',Le='Leiluna:BAAALAAECgIIAgAAAA==.',Li='Libertinne:BAAALAAECgMIBQAAAA==.Limmewinks:BAAALAADCgcIDQAAAA==.Lionel:BAAALAADCgYIBgAAAA==.Lirinen:BAAALAADCggIDgAAAA==.Littleaedonn:BAAALAADCgYICQAAAA==.Litty:BAAALAAECgYICwAAAA==.',Ll='Lluched:BAAALAAECgMIBgAAAA==.',Lo='Lohken:BAAALAADCgQIBAAAAA==.Loreste:BAAALAAECgMIBAABLAAECgMIBgABAAAAAA==.Lox:BAAALAADCggIFwAAAA==.',Lu='Lunaxis:BAAALAADCgYIBgAAAA==.',Ly='Lydirn:BAAALAAECgMIBgAAAA==.Lyonel:BAAALAAECgIIBAAAAA==.',Ma='Macabro:BAAALAADCgUIBQAAAA==.Mahariel:BAAALAADCgcIBwAAAA==.Mahdy:BAAALAAECgIIAgAAAA==.Makito:BAAALAADCggIFQAAAA==.Malakmekahel:BAAALAADCgcICgAAAA==.Malediction:BAAALAADCggIDgAAAA==.Malva:BAAALAAECgEIAgAAAA==.Marcie:BAAALAADCggIDwAAAA==.',Mc='Mchammer:BAAALAADCgUIBgAAAA==.',Mi='Mirei:BAAALAADCggIGAAAAA==.Mitsurugi:BAAALAAECgYICQAAAA==.',Mo='Mojam:BAAALAADCggIFQAAAA==.Moovidlin:BAAALAAECgMIAwAAAA==.Mopowned:BAAALAAECgMIAwAAAA==.Mordian:BAAALAAECgIIAgABLAAECgcIDQABAAAAAA==.',Mu='Munkeez:BAAALAAECgMIBQAAAA==.Mushhead:BAAALAAECgYIDAAAAA==.',Ne='Necrobadger:BAAALAADCgEIAQABLAADCgcICgABAAAAAA==.Necrostalker:BAAALAADCgcICgABLAADCgcICgABAAAAAA==.Nephriel:BAAALAAECgEIAQAAAA==.Nephvìa:BAAALAAECgIIAgAAAA==.Nethershade:BAAALAADCggIGAAAAA==.',Ni='Nihn:BAAALAAECggICAABLAAECggICAABAAAAAA==.',No='Noborû:BAAALAAECgMIAwABLAAECgcIDQABAAAAAA==.Noircoeur:BAAALAAECgMIBAAAAA==.',Ny='Nyhn:BAAALAAECggICAAAAA==.Nyxstonia:BAAALAAECgYICgAAAA==.',['Nä']='Nämi:BAAALAADCgcIDQAAAA==.',Or='Orcdem:BAAALAAECgMIBgAAAA==.',Os='Oshaunlo:BAAALAADCgYIBgAAAA==.',Ot='Otkspring:BAAALAADCgcIBwAAAA==.Otto:BAAALAADCggIFwAAAA==.',Pa='Palliate:BAAALAADCgMIAwABLAAECgYICQABAAAAAA==.Pampoovy:BAAALAADCgYICwAAAA==.Panacemaris:BAAALAAECgEIAQAAAA==.Pandoc:BAAALAADCggIEAAAAA==.Payah:BAAALAAECgYICAAAAA==.',Pe='Persephoneia:BAAALAAECgMIBgAAAA==.',Pi='Pitnick:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.',Pr='Pravaarestis:BAAALAAECgIIAgAAAA==.',Ra='Rathend:BAAALAADCgYIBgAAAA==.Ravendarlin:BAAALAADCggIDgAAAA==.Raylen:BAAALAADCgQIBAAAAA==.',Re='Reiko:BAAALAADCggIDwABLAADCggIGAABAAAAAA==.Renriss:BAAALAAECgQIBwAAAA==.Restodabesto:BAAALAADCgEIAQAAAA==.',Ri='Rilanaar:BAAALAADCgMIAwAAAA==.Rilz:BAAALAAECgMIBgAAAA==.',Ro='Rodgerwabbet:BAAALAADCggIFwAAAA==.Rosaline:BAAALAADCggIDwAAAA==.Rottn:BAAALAAECgYIBgABLAAECgEIAQABAAAAAA==.',Ru='Ruine:BAAALAAECgIIBAAAAA==.',Ry='Ryalin:BAAALAADCgcIBwAAAA==.',Sa='Saraid:BAAALAAECgMIBgAAAA==.Saravase:BAAALAADCgYIBgAAAA==.Satank:BAAALAADCggICQAAAA==.',Sc='Scáth:BAAALAADCggIFQAAAA==.',Se='Secsi:BAAALAADCgYIBgABLAAECgEIAgABAAAAAA==.Seli:BAAALAADCgcIBwAAAA==.Senpaipls:BAAALAADCggIDwAAAA==.',Sh='Shadowgo:BAAALAAECgMIAwAAAA==.Shamtara:BAAALAADCgcIDQAAAA==.Shinoto:BAAALAAECgEIAQAAAA==.',Si='Silvein:BAAALAAECgEIAQAAAA==.Silverstead:BAAALAADCggIAgAAAA==.Sino:BAAALAADCggIFwAAAA==.Six:BAAALAAECgIIAgAAAA==.',Sk='Skrufi:BAAALAADCggIEQAAAA==.',Sm='Smitch:BAAALAADCggIDAAAAA==.',Sn='Snowynn:BAAALAADCggIFQAAAA==.',So='Soh:BAAALAADCgcICQAAAA==.Sormagetin:BAAALAADCgMIAwAAAA==.',Sp='Spyro:BAAALAAECggIDgAAAA==.',Sr='Sron:BAAALAAECgQIBgAAAA==.',St='Stahburs:BAAALAADCgcIBwAAAA==.Stormie:BAAALAADCggICgAAAA==.',Sy='Sylailillea:BAAALAADCggICwAAAA==.Syndicate:BAAALAAECgYICAAAAA==.',Ta='Taaman:BAAALAADCgQIBAAAAA==.Taartis:BAAALAAECgMIBgAAAA==.Taishar:BAAALAADCgYIBgAAAA==.Tarlyn:BAABLAAECoEUAAMEAAgIPxLwDAD4AQAEAAgIPxLwDAD4AQAFAAcI2hTbJQDdAQAAAA==.',Ti='Timthedemon:BAAALAAECgMIBAABLAAECgEIAgABAAAAAQ==.Timthehunter:BAAALAAECgEIAgAAAQ==.Tisiphoneia:BAAALAADCgcICQAAAA==.',To='Toberson:BAAALAAECgEIAQAAAA==.Toxicbanana:BAAALAADCggIFgAAAA==.',Tr='Tradarynn:BAAALAAECgMIAwAAAA==.',Tu='Turambar:BAAALAADCggIDQAAAA==.',Ty='Tylinall:BAAALAAECgYIBgAAAA==.',Um='Umbrax:BAAALAADCgYIBgAAAA==.',Un='Uncle:BAAALAAECgMIAwAAAA==.',Va='Valhalia:BAAALAAECgMIBgAAAA==.Varistius:BAAALAAECgMIAwAAAA==.',Vi='Vidoq:BAAALAADCggIFgAAAA==.',Vy='Vynedra:BAAALAADCgYICwAAAA==.Vypally:BAAALAADCggIDgAAAA==.Vyprania:BAAALAAECgMIAwAAAA==.Vyrul:BAAALAADCggICAAAAA==.',Wa='Warframe:BAAALAAECgYIBwABLAAECgcIFwACAGMlAA==.',Wi='Wildefaux:BAABLAAECoEXAAIGAAgIIxSuEgDoAQAGAAgIIxSuEgDoAQAAAA==.',Ye='Yelhsa:BAAALAADCggIDgAAAA==.',Yo='Yoyoko:BAAALAAECgMIAwAAAA==.',Za='Zaphod:BAAALAADCggICAAAAA==.Zardan:BAAALAADCggIGAAAAA==.',Ze='Zeppik:BAAALAADCgYIBgAAAA==.',Zn='Zny:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end