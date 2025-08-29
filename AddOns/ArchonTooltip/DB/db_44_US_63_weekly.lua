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
 local lookup = {'Warlock-Affliction','Unknown-Unknown','Paladin-Holy','DeathKnight-Frost','Warrior-Fury','Warlock-Destruction','Evoker-Augmentation','Warrior-Protection','Monk-Windwalker','Monk-Mistweaver',}; local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abdalhazred:BAABLAAECoETAAIBAAgICSGvAAAZAwABAAgICSGvAAAZAwAAAA==.Abira:BAAALAADCgMIAwABLAAECgYIDwACAAAAAA==.',Ad='Adorra:BAAALAAECgEIAQABLAAECgYICwACAAAAAA==.Adric:BAAALAAECgMIAwAAAA==.',Ai='Aithanar:BAAALAAECgYIDAAAAA==.Aitheron:BAAALAAECgIIAwABLAAECgMIBQACAAAAAA==.',Aj='Ajakana:BAAALAADCgYICgAAAA==.',Al='Alarak:BAAALAAECgIIAgAAAA==.Alchemist:BAAALAAECgEIAQAAAA==.',Am='Amoradis:BAAALAADCggICQAAAA==.',An='Anoth:BAAALAADCgYIBgAAAA==.Anthestria:BAAALAAECgMIBQAAAA==.',Aq='Aqurala:BAAALAAECgMIBAAAAA==.',Ar='Arasham:BAAALAADCgIIAgABLAAECgYIDAACAAAAAA==.Aravenn:BAAALAAECgYIDAAAAA==.Archidamia:BAAALAADCgcICAAAAA==.Archimetes:BAAALAAECgYICgAAAA==.Arkangel:BAAALAAECgMIAwAAAA==.Arthäs:BAAALAADCgQIBgAAAA==.',Av='Avarious:BAAALAAECgYICgAAAA==.Avatarkuruk:BAAALAAECgcICgAAAA==.Avatartouka:BAAALAAECgYIBwAAAA==.Avraria:BAAALAAECgYIBgAAAA==.',Ax='Axxain:BAAALAADCggICAAAAA==.',Az='Azshala:BAAALAAECgMIAwAAAA==.',['Aí']='Aísling:BAAALAADCggIFQAAAA==.',Ba='Badhorse:BAAALAADCggIDAABLAAFFAIIAgACAAAAAA==.Banesnarl:BAAALAADCggICAAAAA==.Basedz:BAAALAADCgcIDwAAAA==.',Bc='Bcc:BAAALAADCggICAAAAA==.',Be='Bekabeka:BAABLAAECoEVAAIDAAgICxcECQA2AgADAAgICxcECQA2AgAAAA==.Belindria:BAAALAADCggICAAAAA==.Benerrarros:BAAALAAECgcIDQAAAA==.Bergamot:BAAALAADCggIFAAAAA==.',Bl='Bluud:BAAALAADCggIFAAAAA==.',Bo='Boamere:BAAALAADCggICAAAAA==.Boosserbro:BAAALAADCggIDQAAAA==.',Br='Brakkar:BAAALAADCggIEAAAAA==.Brieaddyjr:BAAALAADCggICAABLAAECggIFwAEABcmAA==.Brutaal:BAAALAADCgcIDAAAAA==.',Ca='Cacellice:BAAALAAECgIIAgAAAA==.Carnïfex:BAAALAAECgcIEQAAAA==.Catgirl:BAAALAADCgYIBgAAAA==.',Ce='Celaian:BAAALAAECgMIAwAAAA==.Celestraza:BAAALAADCgUIBQAAAA==.',Ch='Cheekclap:BAAALAADCgcIBwAAAA==.Chidõri:BAAALAAFFAIIAgAAAA==.Chopstix:BAAALAADCgQIBAAAAA==.',Co='Cosset:BAAALAADCggIEAABLAAECgcIEgAFAIoPAA==.',Cr='Crumblcookie:BAAALAAECgUIBgAAAA==.Crysania:BAAALAAECgEIAQAAAA==.',Cy='Cyralai:BAAALAAECgcICgAAAA==.',Da='Daircan:BAAALAADCggICAAAAA==.Dalilight:BAAALAADCggICAAAAA==.Dankley:BAABLAAECoESAAIFAAcIig/oHADPAQAFAAcIig/oHADPAQAAAA==.',De='Deafknighte:BAAALAAECgMIAwAAAA==.Deathcuddles:BAAALAADCgcICgAAAA==.Deathlesself:BAAALAADCgYIBwAAAA==.Demosummoner:BAAALAADCgcIBwAAAA==.Demure:BAAALAAECgMIBAAAAA==.Deydreama:BAAALAADCggIDwAAAA==.',Di='Diablow:BAAALAADCgcIBwABLAAECgYICQACAAAAAA==.Diana:BAAALAAECgMIAwAAAA==.',Do='Dontjudgemê:BAAALAADCgQIBAAAAA==.',Dr='Dracion:BAAALAADCgcICQAAAA==.Draltina:BAAALAAECgMIBAAAAA==.Dresstokill:BAAALAADCgQIBAABLAADCggIDwACAAAAAA==.',Du='Duskstrider:BAAALAADCggIFAAAAA==.Dustylock:BAAALAADCggIFQAAAA==.',Ea='Earlydonset:BAAALAAECgQIAQAAAA==.',Em='Emmel:BAAALAAECgMICAAAAA==.',Eq='Equeslucis:BAAALAADCgcICwAAAA==.',Er='Erodrana:BAAALAADCgMIAwAAAA==.',Eu='Euphiee:BAAALAAECgYIEQAAAA==.',Fb='Fbiravebae:BAAALAAECgcIDwAAAA==.',Fe='Feldeathhell:BAAALAAECgMIBAAAAA==.Felfuoco:BAAALAAECgIIAgAAAA==.Fellamayyne:BAAALAADCgUIBgAAAA==.Ferrus:BAAALAAECgcICgAAAA==.',Fi='Finbane:BAAALAADCggIDgAAAA==.Fioricet:BAAALAADCggIBgAAAA==.',Fo='Foundyou:BAAALAAECgMIBgAAAA==.',Fu='Furyspudd:BAAALAAECgYIDAAAAA==.',Ga='Galoreus:BAAALAADCgcICQAAAA==.Garlic:BAAALAADCgQIBAABLAADCggIDwACAAAAAA==.Gavawham:BAAALAADCgYIBgAAAA==.',Gl='Glarung:BAAALAADCggIEAABLAAECggIEgACAAAAAA==.Glimbo:BAAALAAECgEIAQAAAA==.',Gr='Greyfeather:BAAALAADCgQIBAAAAA==.Grippyjob:BAABLAAECoEXAAIEAAgIFyZKAACMAwAEAAgIFyZKAACMAwAAAA==.Grumpywz:BAAALAADCgQIBAAAAA==.Grundle:BAAALAADCggICAAAAA==.',Gu='Gunduin:BAAALAAECgYIDgAAAA==.Gurzoom:BAAALAADCgYIBgAAAA==.',Gy='Gyda:BAAALAAECgcIDgAAAA==.',Ha='Halabel:BAEALAAECgMIBgABLAAFFAEIAQACAAAAAA==.',He='Hearthzilla:BAAALAADCgEIAQAAAA==.',Ho='Holysheet:BAAALAADCgcICQAAAA==.Hots:BAAALAAECggIDgAAAA==.',Hu='Huntingwolf:BAAALAAECgMIBAAAAA==.',Ic='Iconis:BAAALAADCgQIBAAAAA==.',Ii='Iichimaru:BAAALAADCggIEAAAAA==.',Il='Ilin:BAAALAADCgIIAgAAAA==.Illidupe:BAAALAAECgEIAQAAAA==.',Im='Impish:BAAALAAECgYICgAAAA==.',In='Injection:BAAALAADCggIDgAAAA==.',Iv='Ivey:BAAALAAFFAIIAgAAAA==.',Ja='Jacenne:BAAALAADCggIDgAAAA==.Jairus:BAAALAADCggICAAAAA==.Jaylenbrown:BAAALAAECgMIAwAAAA==.',Je='Jess:BAAALAAECgcIDwAAAA==.',Jo='Johnnyt:BAAALAADCgYICAAAAA==.Josh:BAAALAADCgYIBgABLAADCggIDwACAAAAAA==.',Ju='Jugernaut:BAAALAADCgMIAwAAAA==.',Ka='Kaedin:BAAALAADCggICQAAAA==.Kakuta:BAAALAAECgUIBQABLAAECgcICgACAAAAAA==.Kakutå:BAAALAAECgcICgAAAA==.Kalru:BAAALAADCgIIAgAAAA==.Kalsongryck:BAAALAADCgMIBAAAAA==.',Ke='Keba:BAAALAADCggIEAABLAAECggIFQADAAsXAA==.Kept:BAAALAADCggIDQAAAA==.',Ki='Killerelf:BAAALAADCgYIBgAAAA==.',Kk='Kkrown:BAAALAAECgMIBgAAAA==.',Ko='Koraleena:BAAALAAECgEIAQAAAA==.Korbo:BAAALAADCggIFQAAAA==.Korbulo:BAAALAAECgIIAgAAAA==.Korlothel:BAAALAAECgEIAQABLAAECgYIDAACAAAAAA==.',Ku='Kungfuuy:BAAALAAECgQIBwAAAA==.',La='Laofutzu:BAAALAADCgQIBwAAAA==.Lapinn:BAAALAADCggIDAAAAA==.Laukini:BAAALAADCgYIBgAAAA==.Lav:BAEALAAECgYICwAAAA==.Lavanthor:BAEALAAECgEIAQABLAAECgYICwACAAAAAA==.',Li='Lianya:BAAALAADCgIIAgABLAAECgYICwACAAAAAA==.Liskeardite:BAAALAADCgcIEgAAAA==.',Lo='Locknload:BAAALAADCgYIDAAAAA==.Loneshadow:BAAALAADCgUIBQAAAA==.Loriél:BAAALAAECggIEQAAAA==.Loìsbethe:BAAALAADCggIDwAAAA==.',Lu='Lumian:BAAALAADCgYICwAAAA==.Lumiëre:BAAALAADCgQIBAAAAA==.',Ma='Maelera:BAAALAADCggICAAAAA==.Maendor:BAAALAAECgYIBgAAAA==.Maetromundo:BAAALAADCgYIBgAAAA==.Maeva:BAAALAADCgYIDAAAAA==.Maletsy:BAAALAADCgEIAQABLAAECgYIDgACAAAAAA==.Maliboo:BAAALAAECgYIBgAAAA==.Marblefox:BAAALAAECgYICwAAAA==.Maxamus:BAAALAAECgMIBQAAAA==.Mayln:BAAALAADCgcIBwABLAADCggICAACAAAAAA==.',Me='Medívh:BAAALAADCgEIAQAAAA==.Merkenier:BAAALAADCggICAAAAA==.',Mi='Midchaos:BAAALAADCgQIBAAAAA==.Midnitestorm:BAAALAADCgYIAQAAAA==.Midpeckr:BAAALAADCgcIBwAAAA==.',Mo='Modaxel:BAAALAADCgYICQAAAA==.Modifiedmix:BAAALAAECgMIBgAAAA==.Modsabadtank:BAAALAADCgEIAQABLAAECgMIBgACAAAAAA==.Moneyshok:BAAALAADCgYIBgAAAA==.Monmon:BAAALAADCggICgAAAA==.Mooncows:BAAALAAECgYICQAAAA==.Mordormu:BAAALAADCggIDgAAAA==.Morella:BAABLAAECoEgAAIGAAgIiBBMFQAUAgAGAAgIiBBMFQAUAgAAAA==.',Mu='Mustakrakish:BAABLAAECoEUAAIHAAgIrRz+AACwAgAHAAgIrRz+AACwAgAAAA==.',My='Mystych:BAAALAAECgMIBAAAAA==.',Na='Nailedit:BAAALAAECgUIBQAAAA==.Naste:BAAALAADCgMIAwAAAA==.',Nd='Ndigo:BAAALAADCgYIBgAAAA==.',Ne='Nelaros:BAAALAADCgcIDQAAAA==.Nerfdks:BAAALAADCgYIBgAAAA==.',Ni='Nickiminaj:BAAALAADCggICAAAAA==.Nightbird:BAAALAAECgYICwAAAA==.Niluxe:BAAALAADCgQIBAAAAA==.Nivella:BAAALAADCgYICgAAAA==.',Ob='Obsaedia:BAAALAAECgQIBAAAAQ==.Obsedien:BAAALAAECgIIAwAAAA==.',Of='Ofanite:BAAALAAECgIIAgAAAA==.',Og='Ogmadmonk:BAAALAAECgcIEAAAAA==.',Ok='Oktobra:BAAALAADCggIDwAAAA==.',Ol='Olfert:BAAALAADCgEIAQAAAA==.',On='Ono:BAAALAAECgMIBQAAAA==.',Os='Osash:BAAALAAECgYIBgAAAA==.Osun:BAAALAADCgYIBgAAAA==.',Pa='Pachoso:BAABLAAECoEWAAMFAAgI9SPdAwA1AwAFAAgI9SPdAwA1AwAIAAEIhxxJKwBUAAAAAA==.Palantyr:BAAALAAECggIEgAAAA==.Patroklos:BAAALAADCggIFQAAAA==.',Pi='Picklemorty:BAAALAADCgEIAQABLAAECgMIAwACAAAAAA==.Pikapurple:BAAALAADCgIIAgAAAA==.Pixyfire:BAAALAADCgcICAABLAAECgYICwACAAAAAA==.',Py='Pyraxi:BAAALAADCgYIBgAAAA==.',Ra='Radahnthis:BAAALAAECgMIBwAAAA==.Raddish:BAAALAADCggIDwAAAA==.Ramranch:BAAALAADCgMIAwAAAA==.Ratadinamika:BAAALAADCgQIBAAAAA==.Rathix:BAAALAADCgcICAAAAA==.Raylee:BAAALAAECgYICwAAAA==.Razuki:BAAALAAECgYICwAAAA==.',Rh='Rhuac:BAAALAAECgEIAQAAAA==.',Ri='Riorson:BAAALAADCgYIBgAAAA==.',Ro='Rocknrólla:BAAALAAECgMIBAAAAA==.Rollexi:BAAALAAECgEIAQABLAAECgYICwACAAAAAA==.Rosefist:BAEBLAAECoEWAAMJAAgIXx+wAwDjAgAJAAgIXx+wAwDjAgAKAAcIXhYBDQC8AQAAAA==.Rosemourne:BAEALAADCggICAABLAAECggIFgAJAF8fAA==.Roserawr:BAEALAAECgYICgABLAAECggIFgAJAF8fAA==.Roserogue:BAEALAAECgYICQABLAAECggIFgAJAF8fAA==.',Ru='Rubmytotems:BAAALAADCgYIBgAAAA==.Ruckus:BAAALAAECgcIDgAAAA==.',Sa='Saintsfear:BAAALAADCgcIDAAAAA==.Sareenastar:BAAALAAECgYIDAAAAA==.',Se='Seir:BAAALAADCgcIBwAAAA==.',Sh='Shadowzbane:BAAALAAECggIAQAAAA==.Shakey:BAAALAAECgMIAwAAAA==.Shalen:BAAALAAECgMIBAAAAA==.Sheraa:BAAALAADCggIEQAAAA==.Shifushield:BAAALAADCggICgAAAA==.',Si='Silmarkthree:BAAALAAECgYICwAAAA==.Sinbåd:BAAALAADCggIEgAAAA==.Sisterstar:BAAALAADCgYIDAAAAA==.',Sk='Skitty:BAAALAAECgEIAQAAAA==.',Sl='Slangnmagic:BAAALAADCgUIBQAAAA==.Slumztote:BAAALAAECgYIBgAAAA==.',So='Solari:BAAALAADCggIEwAAAA==.Solona:BAAALAAECgMIBAAAAA==.Sorean:BAAALAAECggIEwAAAA==.Soulgem:BAAALAAECgUIBQAAAA==.Soup:BAAALAADCggIFgAAAA==.',Sp='Spinel:BAAALAAECgEIAQAAAA==.',St='Starlune:BAAALAAECgMIBAAAAA==.Stepraider:BAAALAADCgcIBwAAAA==.Stoneward:BAAALAADCgcIBwAAAA==.',Su='Supersoaker:BAAALAADCggICgAAAA==.',Sy='Sylverdrake:BAAALAADCgcIDQABLAAECgYICwACAAAAAA==.Sylverfox:BAAALAAECgYICwAAAA==.Symadin:BAAALAADCgQIBAABLAADCggIFAACAAAAAA==.',['Sä']='Sälie:BAAALAAECgEIAQAAAA==.',Ta='Tadagain:BAAALAADCgcIDgAAAA==.Tankskie:BAAALAADCgcIBQAAAA==.Tarmalok:BAAALAAFFAIIAgAAAA==.',Te='Telekinesis:BAAALAAECgEIAQAAAA==.Tenbinza:BAAALAADCgcICgAAAA==.Teos:BAAALAAECgYICQAAAA==.',Th='Thald:BAAALAADCgUIBQAAAA==.Thaliak:BAAALAADCgcICgABLAAECgMIBQACAAAAAA==.Thaliarian:BAAALAADCggIDAAAAA==.Theedk:BAAALAADCggIEQAAAA==.Thinmint:BAAALAAECgIIAwABLAAECggIFwAEABcmAA==.Thorny:BAAALAADCgMIAwAAAA==.Thromar:BAAALAAECgYICwAAAA==.',Ti='Tinderbeef:BAAALAADCgcICAAAAA==.Tinychaos:BAAALAAECgEIAQAAAA==.Tinypita:BAAALAADCgYICAAAAA==.Tishribul:BAAALAADCgcIBwAAAA==.',Tr='Tredders:BAAALAAECgUIBgAAAA==.Treekeg:BAAALAAECgYICwAAAA==.Tripz:BAAALAADCgEIAgAAAA==.Trée:BAAALAAECgEIAQABLAAECgYICwACAAAAAA==.',Tu='Tubbo:BAAALAADCggIDAAAAA==.',Ty='Tyson:BAAALAAECgEIAQAAAA==.',Va='Valarea:BAAALAADCgEIAQAAAA==.Valeryne:BAAALAAECgMIBAAAAA==.Valock:BAAALAADCggIFAAAAA==.Valress:BAAALAADCgQIBAAAAA==.',Ve='Velhyana:BAAALAADCgMIAgAAAA==.Venli:BAAALAADCgIIAgAAAA==.Vestta:BAAALAADCggIEQAAAA==.Vexwar:BAAALAADCggICAAAAA==.',Vy='Vyx:BAAALAADCggIFQAAAA==.',Wa='Waffle:BAAALAAECgMIAwAAAA==.Wasprepared:BAAALAADCgYIBgAAAA==.Waylan:BAAALAADCgIIAgAAAA==.',We='Weeaboo:BAAALAADCgQIBAAAAA==.',Wh='Whoopstwo:BAAALAADCggIDwAAAA==.',Xa='Xaiosk:BAAALAAECgcICgAAAA==.',Xi='Xilbo:BAAALAADCgcIBwABLAAECgIIAwACAAAAAA==.Xilstab:BAAALAAECgYIDwAAAA==.Xilya:BAAALAAECgIIAwAAAA==.',Yu='Yuzu:BAAALAAECgMIBQAAAA==.',Za='Zarynn:BAAALAAECgEIAQAAAA==.',Zd='Zdk:BAAALAADCgQIBAABLAADCggIDwACAAAAAA==.',Ze='Zeboosh:BAAALAAECgEIAQAAAA==.Zedargrekk:BAAALAAECgMIAwAAAA==.Zeldy:BAAALAAECgMIBAAAAA==.Zenbum:BAAALAAECgMIBAAAAA==.',Zm='Zmaster:BAAALAADCggIDwAAAA==.',Zu='Zunarri:BAAALAADCggIFQAAAA==.',['Zè']='Zèn:BAAALAAECgMIAwAAAA==.',['Áz']='Ázrael:BAAALAADCgMIAwAAAA==.',['Ða']='Ðark:BAAALAAECgYICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end