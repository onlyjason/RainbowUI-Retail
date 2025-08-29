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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Devastation',}; local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abeslock:BAAALAADCggIEAABLAAECgUIBQABAAAAAA==.',Ad='Adeloreithe:BAAALAAECgEIAQAAAA==.Adouken:BAAALAAECgIIAgAAAA==.Adrok:BAAALAAECgcIDwAAAA==.',Ae='Aellyria:BAAALAAECgQIBQAAAA==.',Ai='Ainsworth:BAEALAAECgMIBAAAAA==.',Ak='Akaili:BAAALAAECgIIAwAAAA==.Akintharo:BAAALAAECgEIAQAAAA==.',Al='Alangrant:BAAALAADCgcIBwAAAA==.Aletia:BAAALAADCggICAAAAA==.Alexiya:BAAALAAECgIIAgAAAA==.Allisandra:BAAALAAECgMIBAAAAA==.Allumer:BAAALAADCgcIEQAAAA==.Allyndre:BAAALAADCggICAAAAA==.Alythas:BAAALAADCgcICgAAAA==.',Am='Amorial:BAAALAAECgMIBAAAAA==.',An='Andruix:BAAALAADCgMIAwAAAA==.Angmaro:BAAALAADCggIDgAAAA==.Antibear:BAAALAAECgIIAgAAAA==.Antinoth:BAAALAADCgUICAABLAAECgIIAgABAAAAAA==.',Ap='Apito:BAAALAADCggICAAAAA==.Apoldelon:BAAALAADCgcIEQAAAA==.',Ar='Arakar:BAAALAAECgIIAgAAAA==.Aralynne:BAAALAAECgIIAgAAAA==.Arcann:BAAALAADCgIIAgAAAA==.Arch:BAAALAAECgEIAQAAAA==.Arieah:BAAALAAECgIIAgAAAA==.Armorya:BAAALAAECgEIAQAAAA==.Armyofone:BAAALAAECgIIAgAAAA==.Artaius:BAAALAAECgUIBwAAAA==.',As='Astariel:BAAALAAECgYIDQAAAA==.Astarog:BAAALAAECgEIAQAAAA==.',At='Atafloosy:BAEALAAECgMIBQAAAA==.Athelf:BAAALAAECgcIEAAAAA==.',Au='Audri:BAAALAADCgcIBwAAAA==.Augtistic:BAAALAAECgQIBAAAAA==.',Ax='Axël:BAAALAAECgIIAgAAAA==.',Ay='Ayrnerdam:BAAALAADCggIFwAAAA==.',Az='Azeva:BAAALAADCgQIBAAAAA==.Azhurea:BAAALAAECgIIAgAAAA==.Azush:BAAALAAECgMIAwAAAA==.',Ba='Bagelstealth:BAAALAAECgMICAAAAA==.Bashylad:BAAALAAECgIIBQAAAA==.',Be='Bearbarian:BAAALAAECgMIAwAAAA==.Beliir:BAAALAAECgMIBAAAAA==.Berick:BAAALAAECgMIAwAAAA==.Betzalel:BAAALAADCggIDwAAAA==.',Bi='Bigblake:BAAALAAECgIIAgAAAA==.Bingo:BAAALAAECgMIBAAAAA==.',Bl='Blackheárt:BAAALAAECgEIAQAAAA==.Blax:BAAALAADCggIFAAAAA==.Blaxx:BAAALAADCgYIBgABLAADCggIFAABAAAAAA==.Bloodyaggro:BAAALAADCggIDAAAAA==.Blur:BAAALAADCgYIBgAAAA==.Blutengell:BAAALAAECgEIAQAAAA==.',Bo='Bolener:BAAALAAECgcICgAAAA==.Boomsday:BAAALAADCgUIBQAAAA==.',Br='Brewnelle:BAAALAADCgQIBAAAAA==.Bristra:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',Bu='Bureiku:BAAALAAECgMIBAAAAA==.',Ca='Caitali:BAAALAAECgYICAAAAA==.Caliahk:BAAALAADCgcIBwAAAA==.Cammus:BAAALAAECggICgAAAA==.Carmey:BAAALAAECgMIBQAAAA==.Carrin:BAAALAAECgYICgAAAA==.Castanza:BAAALAADCgUIBQAAAA==.Catalyia:BAAALAAECgEIAQAAAA==.Catreas:BAAALAADCggIDgAAAA==.Catris:BAAALAAECgEIAQAAAA==.',Ce='Celsica:BAAALAAECgYICAAAAA==.Cerul:BAAALAAECgMIAwAAAA==.',Ch='Chainsaw:BAAALAADCgcIBwAAAA==.Chewie:BAAALAAECgYIDwAAAA==.',Ci='Cilvuss:BAAALAADCgcIDQAAAA==.',Cl='Clashtodd:BAAALAADCggICAAAAA==.Cliss:BAAALAAECgEIAQAAAA==.',Co='Cococadaver:BAAALAAECgIIAgAAAA==.Concorde:BAAALAADCggIEQAAAA==.Copiousconns:BAAALAAECgMIAwAAAA==.Corinne:BAAALAADCgIIAgAAAA==.Corlock:BAAALAADCgUIBQAAAA==.',Cp='Cptstabn:BAAALAAECgYICAAAAA==.',Cr='Craitos:BAAALAADCgYIBgAAAA==.Crimsonfury:BAAALAADCggIFgAAAA==.',Cu='Culurien:BAAALAADCggIDAAAAA==.Cutlash:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Cutzap:BAAALAAECgEIAQAAAA==.',Da='Daieniceis:BAAALAADCggICwAAAA==.Dalkurn:BAAALAAECgEIAQABLAAECgcIDwABAAAAAA==.Darkdead:BAAALAADCgcIBwAAAA==.Darvoset:BAAALAADCgcIBwAAAA==.Darxam:BAAALAADCgYIBAAAAA==.',De='Deadelf:BAAALAAECgIIAgAAAA==.Deathshade:BAAALAAECgQIBQAAAA==.Decaylol:BAAALAADCggICAAAAA==.Deceptakahn:BAAALAAECgYIDAAAAA==.Deelee:BAAALAAECgIIAgAAAA==.Dekayy:BAAALAAECgcIDwAAAA==.Deldron:BAAALAADCgcIFAAAAA==.Dellin:BAAALAAECgQIAwAAAA==.Deydora:BAAALAAECgcICgAAAA==.Deydoralia:BAAALAAECgcICgAAAA==.',Di='Dimaria:BAAALAADCggICAAAAA==.Diô:BAAALAAECgMIAwAAAA==.',Dj='Djs:BAAALAAECgEIAQAAAA==.',Dn='Dnme:BAAALAAECgYIDAAAAA==.',Do='Dominyx:BAAALAAECgQIBwAAAA==.Doneldus:BAAALAAECgMIBAAAAA==.Donnovan:BAAALAADCgcIBwAAAA==.Doo:BAAALAAECgQIBAAAAA==.Doomedshot:BAAALAADCgcIEQAAAA==.Dorfdragon:BAAALAAECgYICgAAAA==.Dorfe:BAAALAAECgYICgAAAA==.Dorflock:BAAALAAECgMIBAAAAA==.Dornogal:BAAALAAECgcIDQAAAA==.',Dr='Draconas:BAAALAAECgMIAwAAAA==.Dragndeznuts:BAAALAAECgMIBQAAAA==.Dragonpants:BAAALAAECgcIDwAAAA==.Drakona:BAAALAADCggIEQAAAA==.Draych:BAAALAAFFAIIAgAAAA==.Drewgarymore:BAAALAAECgMIAwAAAA==.',Du='Durandall:BAAALAAFFAEIAQAAAA==.Durleap:BAAALAADCggIDAAAAA==.Dustall:BAAALAAFFAIIAgAAAA==.',Dy='Dylpickl:BAAALAAECgMIBwAAAA==.Dymàs:BAAALAAECgIIAgAAAA==.',Ei='Einkil:BAAALAAECgMIAwAAAA==.',El='Elfwynn:BAAALAADCgcIBwAAAA==.Elinolais:BAAALAADCgYIBgAAAA==.Elixir:BAABLAAECoEWAAICAAgIQhbQEAA6AgACAAgIQhbQEAA6AgAAAA==.Eluned:BAAALAAECgQIBAAAAA==.Elurah:BAAALAAECgMIAwAAAA==.',Em='Emberlée:BAAALAAECgMIBAABLAAECgcICgABAAAAAA==.',En='Enloquecera:BAAALAADCgQIBAAAAA==.',Er='Eralthenetre:BAAALAAECgIIAgAAAA==.Erazminash:BAAALAAECgMIAwAAAA==.Ertlok:BAAALAADCggIDgAAAA==.',Es='Esmae:BAAALAADCgUIBQAAAA==.Ess:BAAALAAECgEIAQAAAA==.',Fa='Fabulosoo:BAAALAAECgMIBAAAAA==.Fae:BAAALAAECgYIBgAAAA==.Farvah:BAAALAADCgcICwAAAA==.',Fe='Feoreo:BAAALAADCggIDgAAAA==.Feypanda:BAAALAAECgMIAwAAAA==.',Fi='Fibbs:BAAALAAECgMIBAAAAA==.Fikti:BAAALAAECgQIBAAAAA==.Firocios:BAAALAAECgEIAQAAAA==.',Fl='Flamesteel:BAAALAADCgUIBQAAAA==.Flappyboy:BAAALAAECgYICAAAAA==.',Fo='Forza:BAAALAADCgUICgAAAA==.',Fr='Frankyzappa:BAAALAAECgMIAwAAAA==.Freecandies:BAAALAADCgYICAAAAA==.Frink:BAAALAAECgEIAQAAAA==.Frostyfella:BAAALAAECgcIDgAAAA==.Frozenphinex:BAAALAADCgcIBwAAAA==.',Fu='Fulk:BAAALAADCgUIBQAAAA==.',Fy='Fyreball:BAAALAAECgYIDQABLAAECgcICAABAAAAAA==.Fyrewood:BAAALAAECgcICAAAAA==.',Ga='Gabriella:BAEBLAAECoEaAAIDAAgIhiJCBgD/AgADAAgIhiJCBgD/AgAAAA==.Gallowglass:BAAALAAECgEIAQAAAA==.Galpaladin:BAAALAADCggIEAAAAA==.Gardlier:BAAALAAECgEIAQAAAA==.Gazooks:BAAALAADCgMIAwAAAA==.',Go='Gojira:BAAALAAECgIIBAAAAA==.Gowancomando:BAAALAAECgEIAQAAAA==.',Gr='Grandd:BAAALAAECgMIAwAAAA==.Gremer:BAAALAADCgUIBQAAAA==.Greyluxen:BAAALAAECgMIBAAAAA==.Grindelbald:BAAALAAECgcIEgAAAA==.Groggler:BAAALAADCggICQAAAA==.Grìp:BAAALAADCgcIFAAAAA==.',Gu='Gushee:BAAALAAECgYICAAAAA==.',Ha='Habiru:BAAALAADCgcIDgAAAA==.Hagaroth:BAAALAAECgIIAgAAAA==.Hanamari:BAAALAAECgYICAAAAA==.Harleyquìnn:BAAALAADCgIIAgAAAA==.Hashacha:BAAALAAECgMIAwAAAA==.Hawkslayer:BAAALAAECgEIAQAAAA==.',He='Hendil:BAAALAAECgMIBAAAAA==.',Ho='Hobe:BAAALAAECgQICAAAAA==.Home:BAAALAAECgEIAgAAAA==.Hoodmagik:BAAALAADCgcIBwAAAA==.',Hu='Humoresque:BAAALAAECgEIAQAAAA==.',Ic='Icyblades:BAAALAAECgYIDQAAAA==.',Il='Illuminate:BAAALAADCgcIBwAAAA==.Ilyna:BAAALAADCggICAAAAA==.',In='Inukchuk:BAAALAADCggICAAAAA==.',Ir='Iroar:BAAALAAECgMIAwAAAA==.',It='Itscell:BAAALAAECgMIBQAAAA==.Ittyycakes:BAAALAADCggICQAAAA==.',Ja='Jane:BAAALAADCggIDwAAAA==.Janet:BAAALAAECgIIAgAAAA==.',Ji='Jiah:BAAALAADCgYIBgAAAA==.Jiraipo:BAAALAAECgEIAQAAAA==.',Jm='Jmorg:BAAALAADCgIIAgAAAA==.',Jo='Jone:BAAALAADCggIDAAAAA==.',Ju='Justifieð:BAAALAADCgcIDQAAAA==.',Ka='Kaidance:BAAALAADCgcIEQAAAA==.Kaisaze:BAAALAADCggICAAAAA==.Kapachka:BAAALAADCgcICwAAAA==.Kathrea:BAAALAAECgUIBwAAAA==.Katmarie:BAAALAAECgEIAQAAAA==.Katsup:BAAALAAECgQIBAAAAA==.Kaydeethree:BAAALAAECgIIAgAAAA==.Kazothor:BAAALAAECgEIAQAAAA==.',Kc='Kcarlewot:BAAALAADCggIDQAAAA==.',Ke='Keria:BAABLAAECoEWAAIEAAgIaSRRAwBOAwAEAAgIaSRRAwBOAwAAAA==.Kerred:BAAALAAECgEIAQAAAA==.',Kh='Kharfáz:BAAALAADCgcICwAAAA==.',Ki='Kibbwarrior:BAAALAAECgEIAgAAAA==.Kieda:BAAALAADCggIDAAAAA==.Kileenna:BAAALAADCgYIBgAAAA==.Kilgannon:BAAALAAECgMIAwAAAA==.Killteam:BAAALAAECgcICQAAAA==.Kiretsu:BAAALAAECgMIBAAAAA==.',Ko='Koder:BAAALAAECgMIAwAAAA==.Korana:BAAALAADCgIIAgAAAA==.Koreska:BAAALAADCgEIAQAAAA==.Kovus:BAAALAADCggICAAAAA==.Kowboy:BAAALAAECgMIBAAAAA==.',Kr='Krask:BAAALAAECgEIAQAAAA==.Krelien:BAAALAAECgYIBgAAAA==.Krron:BAAALAADCgIIAgAAAA==.',Kv='Kvotthe:BAAALAADCgcICwAAAA==.',La='Lawlipopkid:BAAALAAECgMIAwAAAA==.',Le='Legendarea:BAAALAAECgEIAQAAAA==.Leshadow:BAAALAAECgYICAAAAA==.Lexiê:BAAALAAECgMIBAAAAA==.',Li='Lightspring:BAAALAADCggIDQAAAA==.Lilillidari:BAAALAAECgMIBAABLAAECgUICAABAAAAAA==.Lilmontaro:BAAALAAECgUICAAAAA==.Linali:BAAALAAECgYICgAAAA==.',Lo='Locksorab:BAAALAAECgEIAQAAAA==.',Lu='Ludk:BAAALAAECgQIBAAAAA==.Lunì:BAAALAADCgYIBgAAAA==.',Ma='Maggnut:BAAALAAECgYICgAAAA==.Mairek:BAAALAAECgIIAgAAAA==.Malkuri:BAAALAAECgUIDAAAAA==.Maranne:BAAALAADCgYIBgAAAA==.',Mc='Mcgreen:BAAALAAECgMIBQAAAA==.',Me='Mechaljaxon:BAAALAADCgUIBQAAAA==.Mercyxtreme:BAAALAAECgQIBAAAAA==.Merriik:BAAALAADCgcIDQAAAA==.Metapal:BAAALAAECgcIDQAAAA==.',Mi='Milane:BAAALAAECgEIAQAAAA==.',Mo='Modsognir:BAAALAADCggICAABLAAECgUIBwABAAAAAA==.Moirasha:BAAALAAECgIIAgAAAA==.Mokoko:BAAALAADCggICAAAAA==.Monkeydluffy:BAAALAADCgIIAgAAAA==.Monktini:BAAALAADCgcIBwAAAA==.Monran:BAAALAAECgIIAgAAAA==.Moosand:BAAALAAECgMIBAAAAA==.Mortichen:BAAALAAECgcIDwAAAA==.Mortivus:BAAALAADCggIDgAAAA==.Mothy:BAAALAADCgcIBwAAAA==.',Mu='Muggs:BAAALAADCgcICQAAAA==.Mulvane:BAAALAADCggIDgAAAA==.Mustachio:BAAALAAECgIIAgAAAA==.',Mv='Mvpj:BAAALAAECgEIAQAAAA==.',My='Myrrim:BAAALAAECgMIAwAAAA==.Mysweetness:BAAALAADCggIDwAAAA==.',Na='Naenaelord:BAAALAADCggIDgAAAA==.Nalexia:BAAALAADCgYICgAAAA==.Narbw:BAAALAADCggIFwAAAA==.Nashia:BAAALAADCgMIBAAAAA==.Naytear:BAAALAAECgIIAgAAAA==.',Ne='Neall:BAAALAAECgIIAgAAAA==.Nendetre:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Ni='Niane:BAAALAAECgEIAQAAAA==.Nightbird:BAAALAADCgcICAAAAA==.Nightheals:BAAALAADCggIFgAAAA==.Nikal:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Nixs:BAAALAAECgEIAQAAAA==.',No='Noeasytimes:BAAALAAECgEIAQAAAA==.Notorious:BAAALAAECgcIEAAAAQ==.',Od='Odb:BAAALAAECgIIAgAAAA==.',Ol='Olmanjankins:BAAALAADCggICgAAAA==.',On='Onlydks:BAAALAAECggIBQABLAAECggICwABAAAAAA==.Onlytomes:BAAALAAECgIIAQABLAAECggICwABAAAAAA==.',Oo='Oopygoopy:BAAALAADCgUIBgAAAA==.',Or='Oraku:BAAALAADCggICAAAAA==.Orlandeau:BAAALAADCgcICAAAAA==.Orter:BAAALAAECgQICAAAAA==.',Ot='Ottan:BAAALAADCgYIBwAAAA==.',Pa='Papamess:BAAALAADCggICwABLAAECgMIBAABAAAAAA==.',Pe='Pequod:BAAALAADCgUIBQAAAA==.Permatrago:BAAALAAECgIIAgAAAA==.',Ph='Phiba:BAAALAADCggICAABLAAECgYIEAABAAAAAA==.Phydaux:BAAALAAECgEIAQAAAA==.',Pi='Piggypops:BAAALAAECgIIAgAAAA==.Pinkietoe:BAAALAADCgcIBwAAAA==.Pinpow:BAAALAADCgEIAQAAAA==.Pizzaman:BAAALAAECgIIAgAAAA==.',Po='Poison:BAAALAAECgMIAwAAAA==.',Pr='Proxima:BAAALAADCgcICwAAAA==.',Pt='Ptoughneigh:BAAALAAECgEIAQAAAA==.',Pu='Puckish:BAAALAAECgMIAwAAAA==.Purifie:BAAALAAECgEIAQAAAA==.',['Pä']='Päiñ:BAAALAADCgMIBwAAAA==.',Qu='Quickbeam:BAAALAAECgIIAwAAAA==.',Ra='Radünz:BAAALAAECgIIAgAAAA==.Raeliannaa:BAAALAAECgIIAgAAAA==.Rahlthyr:BAAALAADCgQIBAABLAAECgEIAQABAAAAAA==.Ramenfueled:BAAALAAECgEIAQAAAA==.Ramyus:BAAALAAECgMIAwAAAA==.Rancîd:BAAALAAECgIIAgAAAA==.Raphael:BAAALAAECgIIAwAAAA==.Rasik:BAAALAAECgQIBAAAAA==.Rayel:BAAALAADCggICAAAAA==.Raylashade:BAAALAADCgUIBQAAAA==.',Re='Renac:BAAALAAECgMIAwAAAA==.Renojackson:BAAALAADCggICAAAAA==.',Rh='Rheanon:BAAALAAECgEIAQAAAA==.Rhoana:BAAALAAECgMIBAAAAA==.',Ri='Rialu:BAAALAAECgQIBwAAAA==.Ribald:BAAALAAECgMIBAAAAA==.Rigg:BAAALAADCgEIAQAAAA==.Rilaria:BAAALAADCgYIBgAAAA==.Rioshi:BAAALAAECgEIAQAAAA==.',Ro='Robynne:BAAALAADCgcICgAAAA==.',Ru='Ruddam:BAAALAADCggIDAAAAA==.',['Rä']='Rägekäge:BAAALAADCgQIBAAAAA==.Räveñ:BAAALAAECgEIAQAAAA==.',['Rì']='Rìnn:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.',Sa='Saintabes:BAAALAAECgUIBQAAAA==.Saiorse:BAAALAAECgQIBAAAAA==.Saiyun:BAAALAADCggICAAAAA==.Sarahmoon:BAAALAAECgEIAQABLAAECggIFAAFAFgXAA==.Sareinai:BAAALAADCggIDgAAAA==.Sargnarg:BAAALAAECgMIAwAAAA==.Saryeth:BAAALAADCggICAAAAA==.',Sc='Scapegoat:BAEALAAECgQIBAAAAQ==.Scaryspice:BAAALAAECgIIAgAAAA==.Schmie:BAAALAADCggICAAAAA==.Scraime:BAAALAAECgUIBwAAAA==.Scrubbles:BAAALAAECgMIBAAAAA==.',Se='Seethe:BAAALAAECgIIAgAAAA==.Seilah:BAAALAAECgMIBAAAAA==.Sennitha:BAAALAAECgMIBAAAAA==.',Sh='Shadowglade:BAAALAAECgQIBAAAAA==.Shadowseek:BAAALAADCgcICwAAAA==.Shakiera:BAAALAADCggIFwAAAA==.Shammydavis:BAAALAAECggIAQAAAA==.Shammylove:BAAALAADCggIBwAAAA==.Shamty:BAAALAADCgcICwAAAA==.Shangra:BAAALAADCggICAAAAA==.Shatterpeak:BAAALAADCgEIAQAAAA==.Sheegan:BAAALAAECgIIAgAAAA==.Shiggles:BAAALAADCgcICQAAAA==.Shijah:BAAALAADCgcICQAAAA==.Shmeepshmop:BAAALAADCgcICAAAAA==.Shockoctopus:BAAALAADCgEIAQAAAA==.Shraan:BAAALAAECgEIAQAAAA==.Shrapnel:BAAALAAECgEIAQAAAA==.Shypride:BAAALAADCggICAAAAA==.Shàytan:BAAALAAECgYICQAAAA==.',Si='Sinistral:BAAALAAECgIIAwAAAA==.Sinvyx:BAAALAAECgEIAQAAAA==.',Sl='Slicing:BAAALAAECgEIAQAAAA==.Slooterous:BAAALAADCgEIAQAAAA==.',Sm='Smithers:BAAALAAECgQIBQAAAA==.Smokeymcdot:BAAALAADCgcICAAAAA==.',Sn='Snappycakes:BAAALAADCgMIAwAAAA==.Sneakybunny:BAAALAAECgQIBAAAAA==.Snipey:BAAALAAECgIIAgAAAA==.',So='Soladriel:BAAALAAECgMIBAAAAA==.Sooh:BAAALAADCgcICAAAAA==.Sorin:BAAALAADCgcICAAAAA==.Soulbreaker:BAAALAAECgMIAwAAAA==.Soulstice:BAAALAAECgEIAQAAAA==.',Sp='Spit:BAAALAADCggICAAAAA==.Spookz:BAAALAADCgIIAgAAAA==.',St='Staia:BAAALAADCgcIBwAAAA==.Starblunder:BAAALAADCgYIBgAAAA==.Steelflame:BAAALAAECgIIAgAAAA==.Stormforged:BAAALAAECgEIAQAAAA==.',Su='Sunsparrow:BAAALAADCgUIBQAAAA==.',Sw='Swagakazam:BAAALAAECgMIAwAAAA==.Swamp:BAAALAAECgIIAgAAAA==.Swiftysarah:BAABLAAECoEUAAIFAAgIWBcMDABQAgAFAAgIWBcMDABQAgAAAA==.Swyggy:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.',Sy='Syuli:BAAALAADCgMIAwAAAA==.Syvarris:BAAALAAECgcIEwAAAA==.',Ta='Tahner:BAAALAAECgYICQAAAA==.Taikwondoh:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.Taner:BAAALAAECgYICgAAAA==.Tarayn:BAAALAADCgIIAgABLAAECgMIBAABAAAAAA==.Tattletail:BAAALAAECgIIAgAAAA==.',Te='Tenac:BAAALAADCgEIAQABLAAECgMIAwABAAAAAA==.Teraania:BAAALAADCgcIBwAAAA==.',Th='Thorin:BAAALAAECgEIAQAAAA==.Thors:BAAALAAECgMIAwAAAA==.Thélvis:BAAALAADCgIIAgAAAA==.Thìerry:BAAALAAECgcIDwAAAA==.',Ti='Tilpin:BAAALAADCgIIAgAAAA==.Tippocalypse:BAAALAAECgcIDQAAAA==.Titzie:BAAALAAECgIIAgAAAA==.',To='Toad:BAAALAAECgYIBgAAAA==.Tonytonychop:BAAALAAECgMIBAAAAA==.Toshidot:BAAALAAECgcIDQAAAA==.Toshy:BAAALAADCgEIAQABLAAECgcIDQABAAAAAA==.Totesmygoats:BAAALAADCgcIDQAAAA==.',Tr='Translucent:BAAALAAECgMIBgAAAA==.Travawizard:BAAALAAECgIIAgAAAA==.Trazatra:BAAALAAECgMIAwAAAA==.',Ts='Tsyedet:BAAALAADCgEIAQAAAA==.',Tu='Tuonai:BAAALAAECgEIAQAAAA==.Tust:BAAALAAECgYIEAAAAA==.',Tw='Twistmist:BAAALAAECgcIDwAAAA==.',Ty='Tywal:BAAALAADCgYIBgAAAA==.',Uz='Uzrael:BAAALAAECgYIDwAAAA==.',Va='Valaeh:BAAALAAECgMIBAAAAA==.Valgor:BAAALAAECgcIDwAAAA==.Valifor:BAAALAAECgcIDwAAAA==.Valkuridk:BAAALAAECggIDwAAAA==.Valkuridruid:BAAALAADCgYIBgABLAAECggIDwABAAAAAA==.Valkurifel:BAAALAADCgcIDQABLAAECggIDwABAAAAAA==.Valorlight:BAAALAADCggIEwAAAA==.Valyrie:BAAALAADCgcIBwAAAA==.Vanthe:BAAALAAECgMIBAAAAA==.',Ve='Vedo:BAAALAADCggIDQAAAA==.Velhalla:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Veradis:BAAALAADCgUIBQAAAA==.',Vo='Voc:BAAALAAECgIIAgAAAA==.Voleria:BAAALAADCgcICgABLAAECgEIAQABAAAAAA==.',Vv='Vv:BAAALAAECgIIAgAAAA==.',Wa='Waggi:BAAALAADCggICwAAAA==.Waghnak:BAAALAADCgUIBQABLAAECgYICQABAAAAAA==.Waghnaka:BAAALAAECgYICQAAAA==.Waymán:BAAALAADCgMIAwAAAA==.',We='Weebjones:BAAALAADCgcIDgAAAA==.',Wu='Wufer:BAAALAAECgYIBgAAAA==.',Xa='Xaranthia:BAAALAAECgMIBAAAAA==.',Xy='Xylarra:BAAALAAECgQIBAAAAA==.',Ya='Yagison:BAAALAAECgIIAgAAAA==.Yautja:BAAALAAECgUIBwAAAA==.',Yu='Yucahu:BAAALAADCgcICQAAAA==.',Za='Zacaree:BAAALAAECggIEwAAAA==.Zamali:BAAALAAECgIIAgAAAA==.Zaraus:BAAALAAECgMIBAAAAA==.Zarazel:BAAALAAECgIIAgAAAA==.Zartella:BAAALAAECgEIAQAAAA==.',Ze='Zetai:BAAALAAECgYIEAAAAA==.',Zi='Zionus:BAAALAADCgYIBgAAAA==.Zizer:BAAALAADCgMIAwAAAA==.',Zr='Zreydyn:BAAALAADCgcIBwAAAA==.',Zu='Zurgantha:BAAALAADCggICAAAAA==.',Zy='Zybeam:BAAALAADCggIDAAAAA==.Zyther:BAAALAAECgQICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end