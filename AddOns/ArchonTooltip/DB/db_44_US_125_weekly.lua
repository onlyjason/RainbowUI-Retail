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
 local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','DemonHunter-Havoc','Shaman-Restoration','DeathKnight-Frost','Hunter-BeastMastery','Shaman-Enhancement','Hunter-Survival','Paladin-Holy','Hunter-Marksmanship','Druid-Balance','Warrior-Fury','Mage-Arcane','Mage-Fire','Warlock-Affliction','Druid-Restoration',}; local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abeist:BAAALAAECggIDwAAAA==.',Ac='Activion:BAAALAAECgIIAQAAAA==.',Ad='Adelyda:BAAALAADCgYICgAAAA==.',Ae='Aelr:BAAALAAECgYIDAAAAA==.Aevin:BAAALAADCgUIBgAAAA==.',Ah='Ahnakka:BAAALAADCgcIBwAAAA==.',Ak='Akey:BAAALAAECgMIBgAAAA==.Akillar:BAAALAAECgMIAwABLAAECgMIBAABAAAAAA==.Akimis:BAAALAADCgYIBgAAAA==.',Al='Alaaris:BAAALAAECgcIDQAAAA==.Alcomahol:BAAALAADCggICAAAAA==.Ale:BAAALAAECgMIAwAAAA==.Aleine:BAAALAAECgMIAwAAAA==.Alexmeister:BAABLAAFFIEFAAMCAAMIBh4eAgC9AAACAAIIkB0eAgC9AAADAAIIlRwaBgC8AAAAAA==.Alliete:BAAALAAFFAIIAgAAAA==.Alliyah:BAAALAAECgMIBQAAAA==.Aloine:BAAALAAECgYIDQAAAA==.',Am='Amazon:BAAALAAECgYIBgAAAA==.Amorallan:BAAALAAECgMIAwAAAA==.',An='Anivar:BAAALAADCgcICwAAAA==.Anoos:BAAALAAECgIIAgAAAA==.',Ar='Aradox:BAAALAADCggIBgAAAA==.Arckracthyr:BAAALAADCgcIBwAAAA==.Arkona:BAAALAADCgYICQAAAA==.Arkvoodle:BAAALAAECgMIBwAAAA==.',As='Ashbringer:BAABLAAECoEXAAIEAAgIFBa8FgBHAgAEAAgIFBa8FgBHAgAAAA==.',At='Athenis:BAAALAAECgYIDwAAAA==.Aticus:BAAALAADCgIIAgAAAA==.',Az='Azazêll:BAAALAAECgMIBQAAAA==.Azurearrow:BAAALAAECgMIAwAAAA==.Azurgosa:BAAALAAECgQIBwAAAA==.',Ba='Baazan:BAAALAAECggICAAAAA==.Badheals:BAAALAAECgYICwAAAA==.Balenciaga:BAAALAAECgYICQAAAA==.Balthazor:BAAALAAECgMIBwAAAA==.Banan:BAAALAADCgUIBQAAAA==.Bazaseal:BAAALAADCgcIBwAAAA==.',Be='Beargrylls:BAAALAAECgcIDwAAAA==.Bearzz:BAAALAADCgUIBQAAAA==.Beatbix:BAAALAADCggICAAAAA==.Beauranged:BAAALAAECgYIBwAAAA==.Bellamere:BAAALAAECgMIAwAAAA==.Bellanoth:BAAALAAECgUIBgAAAA==.Belyne:BAAALAADCgYIDAAAAA==.Bendyendy:BAAALAAECgYICQAAAA==.Bewley:BAAALAADCggIFgAAAA==.',Bf='Bfev:BAAALAAECgYICgAAAA==.',Bi='Bid:BAAALAAECgQICQAAAA==.Bierfiendx:BAAALAAECgYICAAAAA==.Bigalo:BAAALAAECgQICQAAAA==.Bigdps:BAAALAADCgYIBgAAAA==.Bigdragon:BAAALAAECgUIBgAAAA==.Bigjer:BAAALAAECgEIAQAAAA==.Bigpenace:BAAALAAECgcIDwAAAA==.Bigpullnjøyr:BAAALAADCgEIAQABLAADCgYIBgABAAAAAA==.',Bl='Blaisy:BAAALAAECgQIBwAAAA==.Blessedbubby:BAAALAAECgcIEwAAAA==.Blindanddeaf:BAAALAADCgQIBAAAAA==.',Bo='Boakus:BAAALAAECgYICAAAAA==.Bongmeat:BAAALAAECgYIDAAAAA==.Boogeyman:BAAALAADCgcIDAAAAA==.Boohbooh:BAAALAAECgMIAwAAAA==.Booli:BAAALAADCggICAABLAAFFAMIBgAFABIlAA==.Bowrat:BAAALAAECgYICQAAAA==.',Br='Breztok:BAAALAAECgMIAwAAAA==.Brickabranch:BAAALAADCgcIBwAAAA==.Brode:BAAALAADCgMIAwAAAA==.Bromorc:BAAALAADCgMIBgAAAA==.Brox:BAAALAAECgMIAwAAAA==.Brynjolf:BAAALAAECgMIBgAAAA==.',Bu='Bumhead:BAAALAAECgMIAwAAAA==.Buratt:BAAALAADCgMIBgAAAA==.',['Bé']='Béllâ:BAAALAAECggIBgAAAA==.',Ca='Callieope:BAAALAAECgUIBQAAAA==.Cameronbrink:BAAALAADCggICAAAAA==.Capacitør:BAAALAAECgQICQAAAA==.Cattabloom:BAAALAAECgIIAgAAAA==.Cattamend:BAAALAAECgMIAwAAAA==.Cattazap:BAAALAAECgcICgAAAA==.Cazstiel:BAAALAAECgQIBwABLAADCgcIBwABAAAAAA==.',Ce='Ceefu:BAAALAAECgIIAgABLAAECggIFwAGACwdAA==.Ceress:BAAALAAECgMIAwAAAA==.',Ch='Charbel:BAAALAAECgMIBgAAAA==.Chavadidas:BAAALAAECgEIAQAAAA==.Chilliheeler:BAAALAAECgIIAgAAAA==.Chioturkey:BAAALAAECgMIBwAAAA==.Choj:BAAALAADCgUIBQAAAA==.Chomd:BAAALAADCgcIBwAAAA==.Chompar:BAAALAADCgMIAwAAAA==.Chopzuey:BAAALAADCgcIDgAAAA==.Chuye:BAAALAAECgYICgAAAA==.',Ci='Cinderaz:BAAALAADCgMIBgAAAA==.Ciyus:BAAALAAECgYIDAAAAA==.',Cl='Clann:BAAALAADCgMIAwAAAA==.',Co='Cognitoau:BAAALAADCgUICQAAAA==.Compactdoom:BAAALAADCggICAAAAA==.Conquest:BAAALAAECgMIBAAAAA==.Coquina:BAAALAADCgcIDQAAAA==.Corant:BAAALAADCgcIBwAAAA==.Cordeilia:BAAALAAECgYICgAAAA==.Corot:BAAALAAECgMIBgAAAA==.Cosmi:BAAALAAECgUIBQABLAAECgcIDgABAAAAAQ==.Costiigan:BAAALAADCgcIDQAAAA==.',Cr='Crossblesser:BAAALAADCgMIAwAAAA==.',Cy='Cygeance:BAAALAAECgMIAwAAAA==.',['Cø']='Cønverse:BAAALAAECgIIAgAAAA==.',Da='Dankozdravic:BAAALAADCgYICAAAAA==.Daqueta:BAAALAAECgMIBAAAAA==.Darknstormy:BAAALAADCgcIDQAAAA==.Dazato:BAAALAAECgMIBQAAAA==.Dazbubble:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.Dazrawr:BAAALAADCgYICQABLAAECgYICQABAAAAAA==.Dazxd:BAAALAAECgYICQAAAA==.',De='Dekkae:BAAALAADCgcICwAAAA==.Deliaz:BAAALAADCgMIBgAAAA==.Dendar:BAAALAADCgQIBAAAAA==.Denrishan:BAAALAAECgMIAwAAAA==.Despectre:BAAALAADCgQIBAAAAA==.',Di='Dippa:BAAALAAECgMIAwAAAA==.Dirtybob:BAAALAAECgEIAQAAAA==.Dixenormous:BAAALAADCggICAAAAA==.',Dj='Djapana:BAAALAADCgYICgAAAA==.',Dn='Dnomm:BAAALAADCgMIBgAAAA==.',Do='Dopeyplane:BAAALAAFFAEIAQAAAA==.Douknowdaway:BAAALAADCgMIAwAAAA==.Doùbt:BAAALAAECgYICwAAAA==.',Dr='Draenussy:BAAALAADCgcIBwAAAA==.Dreaddlord:BAAALAAECgYICgAAAA==.Dreadiedude:BAAALAAECgMIBgAAAA==.Dreyfus:BAAALAAECgMIAwAAAA==.Drowlie:BAAALAADCgMIBAABLAAECgMICAABAAAAAA==.Druzie:BAAALAADCggICAABLAAECgQIBQABAAAAAA==.',Du='Durrin:BAAALAAECgEIAQAAAA==.Dusktoday:BAAALAADCggIDQAAAA==.Dutchman:BAAALAAECgIIAwAAAA==.',Dw='Dwaka:BAEALAAFFAIIBAABLAAFFAIIAgABAAAAAA==.Dweeb:BAAALAADCgMIAwAAAA==.',Ea='Earthhoof:BAAALAAECgMIAwAAAA==.',Eb='Ebonflow:BAAALAADCggIDwAAAA==.',Ee='Eetswah:BAAALAAECgEIAQAAAA==.',Ei='Eith:BAAALAAECgYIBwAAAA==.',El='Eleesa:BAAALAAECgIIBAAAAA==.Eleice:BAAALAAECgEIAQAAAA==.Elfrost:BAAALAADCgYIBwAAAA==.',En='Enve:BAAALAADCgYIDAAAAA==.',Er='Eristira:BAAALAADCgcIBwAAAA==.',Ev='Evaelfie:BAABLAAECoEWAAIHAAgIFiC2BgAGAwAHAAgIFiC2BgAGAwAAAA==.Evokunt:BAAALAADCgYIBgAAAA==.Evolute:BAAALAADCgMIAwAAAA==.',Ex='Extintion:BAAALAAECgYIDAAAAA==.',Fa='Fanks:BAAALAAECgIIAgAAAA==.Fatrider:BAAALAAECgYIDQAAAA==.',Fe='Felicia:BAAALAAECgMIBwAAAA==.Feloris:BAAALAAECgMIAwAAAA==.',Fi='Fiveheadtiti:BAAALAAECgEIAQAAAA==.',Fl='Flashheart:BAAALAAECgMIAwAAAA==.',Fo='Forlorn:BAAALAAECgYIBgAAAA==.Fortnitelord:BAAALAAECgMIBwAAAA==.',Fr='Freezefauker:BAAALAAECgMIBAAAAA==.Fridge:BAAALAAECgQICQAAAA==.Frostxfury:BAAALAAECgIIAgAAAA==.Frøstynips:BAABLAAECoEXAAIHAAgIuiOPBgAJAwAHAAgIuiOPBgAJAwAAAA==.',Fu='Furrbulous:BAAALAAECgQICQAAAA==.Furysdeath:BAAALAADCgcIBAAAAA==.',Fy='Fyre:BAAALAAECgcICQAAAA==.',['Fí']='Fírnen:BAAALAADCgMIAwAAAA==.',['Fù']='Fùñk:BAAALAAECgQIBwAAAA==.',Ga='Gablay:BAAALAADCgcIBwAAAA==.Garius:BAAALAAECgYIDAAAAA==.',Gh='Ghostedlt:BAAALAADCggIFAAAAA==.',Gi='Gigitentagon:BAAALAAECgMIBwAAAA==.Gillidan:BAAALAADCgYIBwAAAA==.Ginganinja:BAAALAADCgcIBwAAAA==.Giochino:BAAALAAECgIIAwAAAA==.Girlsdayoni:BAAALAAECgUIBgAAAA==.Girthquakè:BAAALAADCgIIAgAAAA==.',Gl='Glaxxon:BAAALAADCgEIAQAAAA==.',Go='Gohan:BAABLAAECoEVAAIIAAgIryVrAQBkAwAIAAgIryVrAQBkAwAAAA==.Goku:BAAALAADCggIDwABLAAECggIFQAIAK8lAA==.Gommo:BAAALAADCgYIBgAAAA==.Gooblento:BAAALAAECgMIBQAAAA==.',Gr='Groundizzle:BAAALAAECgYICAABLAAECgcIFQAHAPscAA==.',Gu='Guldorc:BAAALAADCggICAAAAA==.Gummii:BAAALAAECgYICQAAAA==.',Gw='Gwiyomie:BAAALAADCggIBgAAAA==.',Gy='Gymbro:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.',Ha='Haerinr:BAAALAAFFAEIAQAAAA==.Hamiegirl:BAAALAADCgQIBAAAAA==.Hangthedj:BAAALAADCgcIBwAAAA==.Hardinggrim:BAAALAADCgcIDgAAAA==.Haruk:BAAALAAECgYIDgAAAA==.Hazchum:BAAALAAECgYICgAAAA==.',He='Hekthrey:BAAALAADCgIIAgAAAA==.Hellsént:BAAALAAECgMIAwAAAA==.Heåls:BAAALAAECgEIAQAAAA==.',Hh='Hhet:BAAALAAECgIIAwAAAA==.',Ho='Holiday:BAAALAAECgEIAQAAAA==.Holiesha:BAAALAADCgcICwAAAA==.Hollynova:BAAALAADCgMIAwAAAA==.Hommicidum:BAAALAAECgYICQABLAAECggICAABAAAAAA==.Homícidúm:BAAALAAECggICAAAAA==.Honeydew:BAAALAAFFAIIBAAAAA==.Honkers:BAAALAADCggICAAAAA==.Hoochimama:BAAALAADCgMIBgAAAA==.Hotteemie:BAAALAADCgMIAwAAAA==.',Hr='Hrkz:BAAALAAECgMIBQAAAA==.',Hu='Hugehorns:BAAALAAECgIIAgAAAA==.Hugesac:BAAALAAECgMIBwAAAA==.Humilitatem:BAAALAAECgMIAwAAAA==.',Hy='Hysterical:BAAALAADCgcIBwAAAA==.',['Hà']='Hàmshamwich:BAAALAADCgUIBwAAAA==.',If='Ifrit:BAAALAADCggIDwABLAAECggIFwAGACwdAA==.',Il='Ildera:BAAALAADCgMIBQAAAA==.',Im='Imortallemon:BAACLAAFFIEEAAIIAAIIGhiMBQCyAAAIAAIIGhiMBQCyAAAsAAQKgRcAAggACAghID8JAMwCAAgACAghID8JAMwCAAAA.Impriell:BAAALAADCgEIAQAAAA==.Imugi:BAAALAAECgEIAQABLAAFFAIIAgABAAAAAA==.',In='Indraz:BAAALAAECgUIBQAAAA==.Inspectadeck:BAAALAAECgYICwAAAA==.Interia:BAAALAAECgYICgAAAA==.',Io='Ionsw:BAAALAADCggICAAAAA==.',Ja='Jackillz:BAAALAAECgMIAwAAAA==.Jackmage:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Jacknjill:BAAALAADCggIDwAAAA==.Jackpriest:BAAALAAECgIIAgAAAA==.Jalianne:BAAALAADCgMIAQAAAA==.Jayar:BAAALAAECgYICgAAAA==.',Jd='Jdy:BAAALAADCgEIAQAAAA==.',Je='Jee:BAAALAAECgMIBgAAAA==.',Ji='Jibberwísh:BAAALAAECgQICAAAAA==.',Ka='Kaedeh:BAAALAADCgYICQAAAA==.Kaherd:BAAALAAECgMIAwAAAA==.Kallandor:BAAALAAECgEIAgAAAA==.Kalmyth:BAAALAADCgcICgABLAAECgYIDAABAAAAAA==.Kaltizdat:BAAALAAECgMIBQAAAA==.Kamonklle:BAAALAAECgEIAQAAAA==.Kapsalon:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Karáh:BAAALAADCggICAAAAA==.Kayteeparry:BAAALAAECgcIDQAAAA==.Kaytrina:BAAALAADCggICAAAAA==.',Ke='Kelynada:BAAALAADCgcIBwAAAA==.Keymage:BAAALAADCgIIAgAAAA==.',Ki='Kidkorma:BAAALAADCgQIBAAAAA==.Kieldaz:BAAALAAECgQIBQAAAA==.Kimjeongheal:BAAALAAECgIIAgAAAA==.Kin:BAAALAADCgcIBwAAAA==.Kinore:BAAALAAECgQIBwAAAA==.Kisandra:BAAALAADCgYIBgABLAAECgYIEAABAAAAAA==.Kitchenboss:BAAALAAECgYIDAAAAA==.',Ko='Kolgan:BAAALAADCgcICwABLAAECgcIFQAHAPscAA==.Konradcurze:BAAALAADCggIEgAAAA==.Korell:BAAALAAECgMIAwAAAA==.Korosenai:BAAALAADCgcIBwAAAA==.',Kr='Kraejekta:BAAALAADCgcIBwAAAA==.Krankiekunt:BAAALAAECggIDgAAAA==.Krellhim:BAAALAAECgYICAAAAA==.',Ku='Kuckledrager:BAAALAAECgYIDwAAAA==.Kurisu:BAAALAAECgIIAgAAAA==.',Ky='Kyaryii:BAAALAAECgMIAwAAAA==.',La='Landwalker:BAAALAAECgYIDgAAAA==.Langasenh:BAAALAAECggIBQAAAA==.Langsuir:BAAALAAECgYIDgAAAA==.Larodar:BAAALAAECgIIAgAAAA==.Lawbsterpaly:BAAALAADCgcIEAAAAA==.Laylowmay:BAAALAAECgYIBgABLAAECggIFgADAKsfAA==.Lazziel:BAAALAAECgEIAQAAAA==.',Le='Leiyahigh:BAAALAADCggICAABLAAECggIFgADAKsfAA==.Lensaros:BAAALAADCgQIBAAAAA==.Lettucelordh:BAAALAAECgYIDQAAAA==.',Li='Lightan:BAAALAADCgYIBgAAAA==.Lilpowpow:BAAALAADCggICAAAAA==.Littlecoops:BAAALAADCgUIBQAAAA==.Littleduckk:BAAALAAECgUIBQAAAA==.',Lo='Lom:BAAALAAECgIIAQAAAA==.Lootminator:BAAALAAECgEIAQAAAA==.Loptr:BAAALAADCgcICgAAAA==.Lorelai:BAAALAAECgEIAQAAAA==.',Lu='Luminite:BAAALAADCgIIAgAAAA==.Luxsthighs:BAAALAADCgEIAQAAAA==.',Ly='Lyianara:BAAALAAECgEIAQAAAA==.',Ma='Mace:BAAALAADCggICQAAAA==.Macmillan:BAAALAAECggICAAAAA==.Magharitta:BAAALAAECgIIAgAAAA==.Malatang:BAAALAAECgMIBgAAAA==.Maraku:BAAALAADCgEIAQAAAA==.Mattdêmon:BAAALAADCgUIBQAAAA==.Mauri:BAAALAADCgEIAQAAAA==.Mavshaman:BAAALAADCgcIBAAAAA==.',Mc='Mclame:BAAALAADCgMIAwAAAA==.',Me='Medesin:BAAALAADCgMIBgAAAA==.Megsaac:BAAALAADCgYIBgAAAA==.Mek:BAAALAAECgMIAwAAAA==.Mekhanite:BAAALAAECgMIBgAAAA==.',Mi='Milfdella:BAAALAAECgIIAgAAAA==.Minami:BAAALAAECgMIBgAAAA==.Minhiriath:BAAALAAECgIIAwAAAA==.Mistz:BAAALAADCgcIDQABLAADCggIDAABAAAAAA==.',Mo='Mocmoc:BAAALAAECgMIAwAAAA==.Moistmaker:BAAALAAECggICQAAAA==.Momotaku:BAAALAAECgMIBgAAAA==.Moofasa:BAAALAADCgMIAwAAAA==.Moomoos:BAAALAAECgQIBQAAAA==.Moonsblades:BAAALAAECgEIAQAAAA==.Mooseloose:BAAALAAECgMIAwAAAA==.Morena:BAAALAADCggIDgAAAA==.Morgaina:BAAALAAECgEIAQAAAA==.Mortadellah:BAAALAADCgcIDQAAAA==.Mortarion:BAAALAADCggIDQAAAA==.',Mu='Mudoken:BAAALAADCgcIBwAAAA==.Muffín:BAAALAADCgMIAwAAAA==.Musek:BAAALAAECgMIBAAAAA==.',My='Mysterymeat:BAAALAAECgIIAgAAAA==.Mysticalzz:BAAALAADCgUICgAAAA==.Mysze:BAAALAADCgcIBwAAAA==.',['Mä']='Mäya:BAAALAADCgQIBQAAAA==.',Na='Narîsa:BAEALAAECgMIAwAAAA==.Natria:BAAALAAECgYICwAAAA==.Naw:BAAALAAECgYIEAAAAA==.Nazgore:BAAALAADCgIIAgAAAA==.',Ne='Neeb:BAAALAAECgQICQAAAA==.Neebd:BAAALAADCggIFAAAAA==.Nephiilim:BAAALAADCggICAAAAA==.Nephthys:BAAALAAECgMIAwABLAAECgMIAwABAAAAAA==.',Ni='Niskus:BAAALAAECgYIDwAAAA==.Niyàti:BAAALAAECgIIBAAAAA==.',No='Nobbiepally:BAAALAAECgEIAQAAAA==.Nokharom:BAAALAADCggICAAAAA==.Noolie:BAAALAAECgMICAAAAA==.Notahealer:BAAALAADCggICAAAAA==.Notnina:BAAALAAECgMIAwAAAA==.Nozdaddy:BAAALAAECgEIAQAAAA==.',Nu='Nubishe:BAAALAAECgYICwAAAA==.Nutsdormu:BAAALAAECgUIBQAAAA==.',Nv='Nvè:BAAALAADCgEIAQAAAA==.',Ob='Obliveration:BAAALAADCgQIBAAAAA==.Obskur:BAAALAADCgcICAAAAA==.',Od='Odinwolf:BAABLAAECoEXAAMGAAgILB1pCACJAgAGAAgILB1pCACJAgAJAAUIMBSADAAwAQAAAA==.',Oh='Ohhkunt:BAABLAAECoEWAAMKAAgIZx8OAQC9AgAKAAgIXR0OAQC9AgAIAAcIQxNRJQC8AQAAAA==.',Ok='Okdal:BAAALAADCggICAAAAA==.',On='Onlyfåns:BAAALAAECgMIBAAAAA==.',Or='Orcrimmar:BAAALAAECgMIBgAAAA==.Orkky:BAAALAAECgMIBwAAAA==.Orynden:BAAALAADCgYICQAAAA==.',Os='Osveta:BAAALAAECgYICwAAAA==.',Pa='Padrin:BAAALAADCgYICAAAAA==.Page:BAAALAAECgQIBQAAAA==.Pallatress:BAAALAADCgMIBgAAAA==.Pallyprime:BAAALAAECgEIAQAAAA==.Pampi:BAAALAADCgcIDQAAAA==.Pangilnoon:BAAALAADCggICAAAAA==.Panginoon:BAAALAAECgYIBwAAAA==.Papipalala:BAAALAAECgMIAwAAAA==.Papíaíyúyü:BAAALAADCggIDwAAAA==.',Pe='Pennant:BAEALAAECggICAABLAAECggICAABAAAAAA==.Pepíopí:BAAALAADCgUICQABLAAECgMIAwABAAAAAA==.Perden:BAAALAADCgUICgAAAA==.',Pg='Pgundry:BAAALAAECgMIAwAAAA==.',Ph='Phakin:BAAALAADCggICQAAAA==.',Pi='Piddlesworth:BAAALAADCgYIAwAAAA==.Pinkwarrior:BAAALAADCgcIBwAAAA==.Pinkyblue:BAABLAAECoEWAAMDAAgIlhbCEwAlAgADAAgIIhLCEwAlAgACAAYIBRmtEQB5AQAAAA==.Pipung:BAAALAAECgMIAwAAAA==.',Pr='Primitive:BAAALAADCggIDwAAAA==.Prizdale:BAAALAADCgQIBAAAAA==.Probably:BAAALAAECgMIAwABLAAECgYIBgABAAAAAA==.',Ps='Psyched:BAAALAAECgUICgAAAA==.',Pu='Pudgeydh:BAAALAAECgQIBwAAAA==.Punj:BAAALAAECgIIAgAAAA==.Puppybonks:BAABLAAECoEVAAILAAgIjRh+BACWAgALAAgIjRh+BACWAgAAAA==.',Py='Pytranze:BAAALAADCgcIBwAAAA==.',['Pï']='Pïckles:BAAALAADCggIFwAAAA==.',Qq='Qqmoreimo:BAAALAAECgMIAwAAAA==.',Qu='Quarizma:BAABLAAECoEZAAIMAAgIRiZ3AABqAwAMAAgIRiZ3AABqAwAAAA==.',Ra='Rageinc:BAAALAADCgMIAwAAAA==.Rano:BAAALAAECgYICwAAAA==.',Re='Readytowork:BAAALAADCgcIBwAAAA==.Realistrambo:BAAALAAECgEIAQAAAA==.Restoro:BAABLAAECoEWAAINAAgInCL/BQDoAgANAAgInCL/BQDoAgAAAA==.Restro:BAAALAADCggICAABLAAECggIFgANAJwiAA==.Revarix:BAAALAAECgMIBgAAAA==.',Rh='Rhadea:BAAALAAECgYIBgAAAA==.Rhaella:BAAALAAECgMIBgAAAA==.Rhea:BAAALAAECgMIBAAAAA==.Rhutribution:BAAALAAECgYICQAAAA==.Rhysdogg:BAAALAAECgEIAQAAAA==.Rhãsta:BAAALAADCgYICwABLAAECggIFQAIAK8lAA==.',Ri='Riggerized:BAAALAAECgYIDgAAAA==.Riiven:BAAALAADCgcIAgAAAA==.Riseth:BAAALAAECgYIDgAAAA==.Rivendul:BAAALAADCgMIBAABLAAECgEIAQABAAAAAA==.',Ro='Robotrogue:BAAALAADCggIDwABLAAECgYIDgABAAAAAA==.Rockato:BAAALAAECgcICwAAAA==.Rorgen:BAAALAADCgcIBwAAAA==.Rousay:BAAALAAECgUIBgAAAA==.Roxe:BAEALAAECgMIAwAAAA==.',Ru='Rutee:BAAALAAECgUICAAAAA==.',Ry='Ryangosling:BAAALAAECgYIBgAAAA==.',['Ré']='Réíayánámí:BAAALAADCgQIBQAAAA==.',Sa='Saebrinn:BAAALAAECgYIBgAAAA==.Safo:BAAALAAECgYIDwAAAA==.Saleina:BAAALAADCgQIBwAAAA==.Saltz:BAAALAADCggIEgAAAA==.Samchif:BAAALAADCgUIBQAAAA==.Sangreazul:BAAALAADCgIIAgAAAA==.Sartoc:BAAALAAECgYIDAAAAA==.',Sc='Scabbo:BAAALAAECgQICQAAAA==.Scalesoul:BAAALAAECgcIDgAAAQ==.Schmoof:BAAALAADCgEIAQAAAA==.',Se='Seeaew:BAAALAAECgUICgAAAA==.Seiferoth:BAAALAADCggICAABLAAECggIFwAGACwdAA==.Seiveril:BAACLAAFFIEGAAIFAAMIEiWMAQBMAQAFAAMIEiWMAQBMAQAsAAQKgRgAAgUACAjxJjAAAJsDAAUACAjxJjAAAJsDAAAA.Septwolves:BAAALAADCgYIBgAAAA==.',Sh='Shaddai:BAAALAAECgYIDAAAAA==.Shadowdemon:BAAALAAECgQIBgAAAA==.Shadowspine:BAAALAADCggICAAAAA==.Shaggiee:BAAALAADCgUIBQAAAA==.Shakylight:BAAALAADCgcICwAAAA==.Shaladar:BAAALAAECgEIAQAAAA==.Shalash:BAAALAADCgIIAgAAAA==.Shamankiller:BAAALAAECgcIDAAAAA==.Shamlen:BAAALAADCgIIAgAAAA==.Shamon:BAAALAADCggIEAABLAAECgYIDQABAAAAAA==.Sharftay:BAAALAAECgIIAgAAAA==.Shayds:BAAALAADCgYICgAAAA==.Shúlaes:BAAALAAECgIIAgAAAA==.',Si='Silverspulse:BAAALAAECgMIAwAAAA==.Sinfulheals:BAAALAADCggICgABLAAECggIFAAOABoaAA==.Sinistercrow:BAABLAAECoEUAAIOAAgIGhrzDQCDAgAOAAgIGhrzDQCDAgAAAA==.Sixy:BAAALAAECgMIAwABLAAECggIDgABAAAAAA==.Sizeli:BAAALAADCggICAAAAA==.',Sl='Sleepyshark:BAAALAADCgYIBwAAAA==.Slopain:BAAALAAECgQICQAAAA==.Sloppymoist:BAAALAAECgMIBwAAAA==.Slåppery:BAAALAAECgQICgAAAA==.',Sm='Smokeybae:BAAALAAECgYIBgAAAA==.Smokeyz:BAABLAAECoEWAAMPAAgIISORDADIAgAPAAgIbiKRDADIAgAQAAQIph/tAwBrAQAAAA==.',Sn='Snorlax:BAAALAAECgEIAQAAAA==.Snorty:BAAALAAECgYICwAAAA==.',So='Sonotafurry:BAAALAADCgcIDQAAAA==.Sourgumybear:BAAALAAECgYICgAAAA==.Sozenn:BAAALAADCgQIAwAAAA==.',Sp='Splort:BAAALAAECgQIBAAAAA==.Spunkmonk:BAAALAADCgcIBwAAAA==.',St='Sthetic:BAABLAAECoEWAAQDAAgIqx/6CwCMAgADAAcIwB76CwCMAgACAAUIxR/7EwBmAQARAAIInhbEGwCgAAAAAA==.Stormy:BAAALAAECgQICQAAAA==.Stoutbrew:BAAALAAECgcIDQAAAA==.Stuy:BAAALAAECgcIDQAAAA==.Stãria:BAAALAADCgcIBwAAAA==.',Su='Sugarburst:BAAALAAECgIIAgAAAA==.Sugoidekai:BAAALAADCggIEAAAAA==.Sumcat:BAAALAAECgcIEAAAAA==.Sunmoonsun:BAAALAAECgUICAAAAA==.Suprayray:BAAALAADCgEIAQAAAA==.',Sw='Swinginwilly:BAAALAADCggICAAAAA==.Swirlo:BAAALAAECgMIBgAAAA==.Swirlyball:BAAALAADCgcIDQABLAAECgMIBgABAAAAAA==.Switchpets:BAAALAAECgYIBgAAAA==.Switchskin:BAABLAAECoEWAAISAAgIHhyjCgBOAgASAAgIHhyjCgBOAgAAAA==.',Sy='Sylphira:BAAALAAECgYICQABLAAECgMIAwABAAAAAA==.Sylz:BAAALAADCggIDAAAAA==.Syra:BAAALAADCgcIBwAAAA==.',Ta='Taffy:BAAALAAECgMIBgAAAA==.Takahe:BAAALAADCgcIBwAAAA==.Takixan:BAAALAAECgQIBAAAAA==.Tallinor:BAAALAAECgMIAwAAAA==.Tamoko:BAAALAADCgEIAQAAAA==.Tanags:BAAALAADCggIDgAAAA==.Tanktup:BAAALAADCgYICwAAAA==.Tardkun:BAAALAAECgMIBAAAAA==.Taumast:BAABLAAECoEVAAIHAAcI+xz4IQD5AQAHAAcI+xz4IQD5AQAAAA==.Tauter:BAAALAADCgMIBgAAAA==.Tazzee:BAAALAADCgQIBgAAAA==.',Th='Thesean:BAAALAADCgIIAQAAAA==.Theshowerman:BAAALAAECggICQAAAA==.Thogon:BAAALAADCggIEAAAAA==.Tholinika:BAAALAAECgYICwAAAA==.Thunderzz:BAAALAADCgcIDQAAAA==.',Tl='Tlo:BAAALAAECgYIDQAAAA==.',To='Tokilolz:BAAALAAECgYICQAAAA==.Tokpa:BAAALAADCggIDQAAAA==.Tormént:BAABLAAECoEUAAIHAAcIqRzSFABbAgAHAAcIqRzSFABbAgAAAA==.',Tr='Traena:BAAALAADCgQIBAAAAA==.Traytas:BAAALAAECgQICAAAAA==.Treelady:BAAALAADCgYIBgAAAA==.Tronixo:BAAALAAECgIIBAABLAAECgYICgABAAAAAA==.Tronixs:BAAALAAECgYICgAAAA==.',Tu='Tubbquake:BAAALAADCggICAAAAA==.Tufflock:BAAALAADCgcIDgAAAA==.Tuffpal:BAAALAAECgEIAQAAAA==.Tuffsham:BAAALAADCgQIBAAAAA==.',Ty='Tyth:BAAALAAECgEIAQAAAA==.',['Tå']='Tånk:BAAALAADCgcIBwAAAA==.',['Tó']='Tóm:BAAALAADCgMIAwAAAA==.',Uh='Uhts:BAAALAADCgUIBQAAAA==.',Un='Unggoy:BAAALAADCgEIAQAAAA==.Unholykníght:BAAALAADCgcIBwAAAA==.',Uw='Uwuheadpats:BAAALAAECgUICgAAAA==.',Va='Vars:BAAALAAECgEIAQAAAA==.Vazwitch:BAAALAAECgMIAwAAAA==.',Ve='Veledor:BAAALAAECgQIBAAAAA==.Velrayne:BAAALAAECgcIDQAAAA==.Verailde:BAAALAADCgIIAgAAAA==.',Vi='Vindicor:BAAALAAECgMIAwAAAA==.Vinee:BAAALAADCgcIBwAAAA==.',Vo='Voidberg:BAAALAAECgcICwAAAA==.',Vy='Vynburn:BAAALAAECgYICwAAAA==.Vynsteve:BAAALAADCgEIAQAAAA==.',Wa='Watson:BAAALAAECgMIBQAAAA==.',We='Weclone:BAAALAADCggICQAAAA==.Wecurse:BAAALAADCgQIBAAAAA==.Wednesdâyx:BAAALAADCgEIAQAAAA==.Wemblitz:BAAALAADCgMIBgAAAA==.Wesh:BAAALAADCggICAAAAA==.',Wh='Whisp:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Wi='Wildcigg:BAAALAADCgcIBwAAAA==.Wintersfence:BAAALAADCggIEwAAAA==.',Wo='Wogglet:BAAALAADCgEIAQAAAA==.Woolieslyfe:BAAALAAECgYIDgABLAAECgYIDgABAAAAAA==.',Xe='Xenoruin:BAAALAAECgMIBgAAAA==.',Xi='Xiongzzqt:BAAALAAECgIIAgAAAA==.',['Xê']='Xêv:BAAALAAECgYIBgAAAA==.',Yi='Yij:BAAALAADCggIDwAAAA==.',Za='Zatasia:BAAALAAECgYIDgAAAA==.',Ze='Zelendorm:BAAALAAECgQIBwAAAA==.Zeltx:BAAALAAECgEIAQAAAA==.Zenojakh:BAAALAAECgQIBwAAAA==.',Zi='Zibzab:BAAALAADCgEIAQAAAA==.Zintt:BAAALAADCggICAAAAA==.Zionara:BAAALAADCgcIDgABLAAECgIIAgABAAAAAA==.',Zu='Zutana:BAAALAADCggIEQAAAA==.',['Ãk']='Ãkillies:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end