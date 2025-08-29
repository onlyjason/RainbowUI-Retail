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
 local lookup = {'Unknown-Unknown','Warrior-Fury','DeathKnight-Frost','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Priest-Shadow',}; local provider = {region='US',realm='EarthenRing',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adestar:BAAALAADCggIDwAAAA==.Adorèè:BAAALAAECgEIAQAAAA==.',Ae='Aetheros:BAAALAADCgUICAAAAA==.',Ag='Aggorru:BAAALAADCggIDwAAAA==.',Ah='Ahood:BAAALAADCggIDQAAAA==.Ahvb:BAAALAADCgYIBgABLAADCggIEAABAAAAAA==.',Ai='Airlinna:BAAALAAECgcIDwAAAA==.Airoach:BAAALAADCggIFwAAAA==.',Al='Alaraen:BAAALAAECgQIBQAAAA==.Alayyna:BAAALAAECgMIAwAAAA==.Aleve:BAAALAADCgIIAgAAAA==.Alexxandria:BAAALAADCgYIBgAAAA==.Almarii:BAAALAAECgEIAQAAAA==.Almwat:BAAALAADCggIFQAAAA==.Alvara:BAAALAAECgYICgAAAA==.',An='Andaayy:BAAALAAECgIIAgAAAA==.Andius:BAAALAADCgcIEwAAAA==.Andrini:BAAALAADCgcIBwAAAA==.Anirra:BAAALAAECgEIAQAAAA==.Antimage:BAAALAADCggIEAAAAA==.Antiquity:BAAALAADCggICAAAAA==.',Ar='Arcandia:BAAALAADCggICAAAAA==.Aresian:BAAALAADCgMIAwAAAA==.Ariairi:BAAALAADCgMIBQABLAAECgEIAQABAAAAAA==.',As='Asensio:BAAALAAECgEIAQAAAA==.Ashayo:BAAALAADCgcIBwAAAA==.Ashenmoor:BAAALAADCggIDwAAAA==.Ashsoul:BAAALAADCgMIAwAAAA==.Asmion:BAAALAADCgcIBwAAAA==.Astrana:BAAALAADCggIDwAAAA==.Asymmetry:BAAALAADCgQIBAAAAA==.',At='Athelstan:BAAALAAECgIIAwAAAA==.',Au='Audaria:BAAALAADCgcIDwAAAA==.Aureldor:BAAALAAECgMIBQAAAA==.Aurimis:BAAALAADCggICQAAAA==.Automatic:BAAALAAECgQICgAAAA==.',Av='Avorik:BAAALAAECgEIAgAAAA==.',Ay='Ayesia:BAAALAADCgcIEgAAAA==.',Az='Azrat:BAAALAADCgYICwAAAA==.',Ba='Baelzabob:BAAALAADCgYIBwAAAA==.Banddaid:BAAALAADCgIIAgAAAA==.Bannedforwqs:BAABLAAECoEXAAICAAgIGiaUAgBNAwACAAgIGiaUAgBNAwAAAA==.Barcmaul:BAAALAADCggIDwAAAA==.Baylel:BAAALAADCgcIEAAAAA==.',Be='Beamz:BAAALAADCggIDgAAAA==.Berleos:BAAALAAECgMIAwAAAA==.Bezdk:BAAALAADCgMIAwABLAAECgUICQABAAAAAA==.Bezvoker:BAAALAAECgUICQAAAA==.',Bi='Bigpork:BAAALAAECgIIAgAAAA==.Bigzig:BAAALAADCggIFQAAAA==.Birra:BAAALAADCgcIBwAAAA==.',Bl='Blackicewolf:BAAALAADCggICAAAAA==.Blackschwarz:BAAALAADCgcIBwAAAA==.Bladewalker:BAAALAADCggIDwABLAAECgcIDwABAAAAAA==.Bleake:BAAALAADCgcIDgAAAA==.Bleed:BAAALAADCgcIBwAAAA==.Blueberrypie:BAAALAAECgYIDgAAAA==.',Bm='Bmogue:BAAALAADCgYIBgAAAA==.',Bo='Bobbydigital:BAAALAADCgEIAQAAAA==.Bonbarrion:BAEALAADCggIFwABLAAECgcIDwABAAAAAA==.Borbory:BAAALAAECgYICQAAAA==.Borogove:BAAALAADCgMIBQAAAA==.',Br='Brasca:BAAALAAECgYICQAAAA==.Bruhmal:BAAALAAECgYICQAAAA==.Bryaxiis:BAAALAAECgQIBAAAAA==.Brynndolin:BAAALAAECgYICQAAAA==.',Bu='Burzolog:BAAALAAECgYICQAAAA==.',['Bä']='Bärk:BAAALAAECgEIAQAAAA==.',Ca='Calethron:BAAALAADCgEIAQAAAA==.Callahann:BAAALAADCgcIBwAAAA==.Caraseymour:BAAALAAECgQIBQAAAA==.Carynthian:BAAALAADCgIIAwAAAA==.Caysia:BAAALAADCggIEQAAAA==.Cazor:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Cazx:BAAALAADCgcIBgABLAAECgEIAQABAAAAAA==.',Ce='Cef:BAAALAAECgIIAgABLAAECgMIBQABAAAAAA==.Cefkru:BAAALAAECgEIAQABLAAECgMIBQABAAAAAA==.Celadrithien:BAAALAADCggIDwAAAA==.Celindre:BAAALAADCgIIAgAAAA==.Celsia:BAAALAADCgcIEAAAAA==.Cennial:BAAALAAECgYICwAAAA==.Cerrid:BAAALAADCgcICwAAAA==.',Ch='Chemfutzu:BAAALAAECgMIAwAAAA==.Cherrybomb:BAAALAADCggIFQAAAA==.Chewbie:BAAALAAECgEIAQAAAA==.Chippy:BAAALAADCggIEAAAAA==.Chrok:BAAALAADCgIIAgAAAA==.Chronobee:BAAALAAECgQIBwAAAA==.',Ci='Cisor:BAAALAADCgIIBAAAAA==.',Ck='Cklyde:BAAALAAECgcIDQAAAA==.',Cl='Claiyre:BAAALAAECgMIBgAAAA==.Cloaca:BAAALAADCgcIBwAAAA==.',Co='Cochino:BAAALAADCgcIBwAAAA==.Concentrate:BAAALAAECgYICQAAAQ==.Connan:BAAALAADCgYIDAABLAAECgMIAwABAAAAAA==.Cordrann:BAAALAAECgEIAQAAAA==.Corrgan:BAAALAAECgIIAgAAAA==.Cowi:BAAALAAECggIEAAAAA==.',Cr='Crisisangel:BAAALAAECgMIAgAAAA==.Crusherr:BAAALAAECgIIAgAAAA==.',Cy='Cylesia:BAAALAADCggIDQAAAA==.Cylthia:BAAALAADCgYICgAAAA==.',Da='Daemata:BAAALAAECgQIBgAAAA==.Damián:BAAALAAECgQIBgAAAA==.Dankinia:BAAALAADCgMIAwAAAA==.Danrith:BAAALAAECgEIAQAAAA==.Darkhammer:BAAALAAECgMIAwAAAA==.Darkility:BAAALAADCgQIBAABLAADCggIEAABAAAAAA==.Darkswift:BAAALAAECgcIDQAAAA==.Darowyn:BAAALAAECgYIBwAAAA==.',De='Deaxus:BAAALAADCggIFQABLAAECgEIAQABAAAAAA==.Delbelfine:BAAALAADCggIEAAAAA==.Delfar:BAAALAAECgMIAwAAAA==.Delinais:BAAALAAECgcIEAAAAA==.Dethyler:BAAALAAECgYICQAAAA==.Deydine:BAAALAADCggIEAAAAA==.Deyv:BAAALAAECgYICQAAAA==.Deyvi:BAAALAADCgcIDAABLAAECgYICQABAAAAAA==.',Di='Diancie:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.Dianonique:BAAALAADCgYIDQAAAA==.Diddibeau:BAAALAAECgEIAQAAAA==.Dimira:BAAALAADCgUIBwAAAA==.Dinozza:BAAALAADCggICQAAAA==.Distillate:BAAALAAECgYICQAAAA==.',Do='Donkey:BAAALAADCggIBwAAAA==.Dooganitis:BAAALAAECgYICQAAAA==.Dorne:BAAALAADCgcIDgAAAA==.',Dr='Dracothian:BAAALAADCgcIBwAAAA==.Draenite:BAAALAADCggIDwAAAA==.Dragginballz:BAAALAADCggIEAAAAA==.Dragonwi:BAAALAADCggICAAAAA==.Drakos:BAAALAADCgcIDAABLAAECgYICQABAAAAAA==.Drrush:BAAALAAECgQIBgAAAA==.Druzz:BAAALAADCgMIAwAAAA==.',Ed='Edovard:BAAALAADCggIFwAAAA==.',Ee='Eeragon:BAAALAADCgcIFAAAAA==.',Ek='Ekimuno:BAAALAADCgUIBQAAAA==.',El='Electroo:BAAALAAECgcIEAAAAA==.Elijáh:BAAALAAECgcIEAAAAA==.Eliud:BAAALAADCggICAAAAA==.Elladjinn:BAAALAAECgMIAwAAAA==.Elmagoz:BAAALAADCgcIBwABLAAECgQIBQABAAAAAA==.Eltanari:BAAALAADCggIFwAAAA==.Elyncute:BAAALAADCgcIBwAAAA==.Elynthil:BAAALAAECgcIEQAAAA==.',Ep='Ephimonk:BAAALAAECgYICwAAAA==.',Ex='Exegesis:BAAALAADCggICAAAAA==.',Fa='Falrenthil:BAAALAADCgYICgAAAA==.',Fe='Fefe:BAAALAADCgYIBgAAAA==.Felix:BAAALAAECgUIBgAAAA==.Felortisma:BAAALAAECgYIBgAAAA==.Felthorne:BAAALAAECgIIAgAAAA==.Fetche:BAAALAADCgcIDAAAAA==.Fezpaw:BAAALAADCgcIDAAAAA==.',Fi='Firenhai:BAAALAAECgUIBQAAAA==.',Fl='Flagonslayer:BAAALAAECgMIAwAAAA==.Flaime:BAAALAADCggIFwAAAA==.Fluffystorm:BAAALAADCgcIEwAAAA==.',Fo='Forzod:BAAALAADCgQIBQAAAA==.Foss:BAAALAAECgYICAAAAA==.',Fr='Frogstomper:BAAALAAECgMIBAAAAA==.',Fu='Furn:BAAALAAECgYIBgAAAA==.Fuzzydruid:BAAALAADCgcIDAAAAA==.',Ga='Galaswen:BAAALAAECgQIBgAAAA==.Galavenat:BAAALAAECgYICAAAAA==.Garavin:BAAALAADCgMIAwAAAA==.Garbarrion:BAAALAADCgcIBwAAAA==.Garbolicious:BAAALAADCgQIBgAAAA==.Gariidin:BAAALAAECgMIAwAAAA==.Garyh:BAAALAAECgYICQAAAA==.Gavir:BAAALAAECgQIBAAAAA==.',Ge='Geldklerk:BAAALAAECgYICQAAAA==.Geldverdamnt:BAAALAADCgcIDAAAAA==.Germangirld:BAAALAADCgcIBwAAAA==.',Gi='Giacomo:BAAALAAECgEIAQAAAA==.Gigglnash:BAAALAADCggIDQAAAA==.Gildina:BAAALAAECgEIAQAAAA==.Ginggy:BAAALAAECgcIDwAAAA==.',Go='Goosepriest:BAAALAADCgcIDgAAAA==.Gori:BAAALAAECgYICQAAAA==.Gortac:BAAALAADCgUIBQAAAA==.Gowther:BAAALAADCgQIBAAAAA==.',Gr='Graath:BAAALAAECgIIAgAAAA==.Greggotgreen:BAAALAAECgMIAwAAAA==.Greyantheril:BAAALAAECgIIAgAAAA==.Greyji:BAAALAAECgYICQAAAA==.Grothorn:BAAALAADCgcIEQAAAA==.Gruckmuncher:BAAALAAECgQIBQAAAA==.Grumb:BAAALAAECgcIEAAAAA==.',Gu='Guar:BAAALAAECgMIAwAAAA==.Guldañ:BAAALAAECgQIBQAAAA==.Gunthar:BAAALAADCgQIBAAAAA==.Gustytail:BAAALAAECgYICQAAAA==.',Gw='Gwendk:BAEBLAAECoEWAAIDAAgI3iYoAACYAwADAAgI3iYoAACYAwAAAA==.Gwenpriest:BAEALAADCgQIBAABLAAECggIFgADAN4mAA==.',Ha='Haardrada:BAAALAAECgYICQABLAAECgYICQABAAAAAA==.Habit:BAAALAAECgYIBwAAAA==.Hadrien:BAAALAAECgIIAgAAAA==.Hagr:BAAALAADCggICAAAAA==.Halapeño:BAAALAADCggICAAAAA==.Hanzul:BAAALAAECgYICQAAAA==.Hawkfoot:BAAALAADCggIDwAAAA==.',He='Healiane:BAAALAADCgEIAQAAAA==.Hellbore:BAAALAAECgYIDgAAAA==.Hellishdawn:BAAALAADCggIFgAAAA==.Hellrage:BAAALAAECgQIBgAAAA==.Hemmy:BAAALAAECgcIDgAAAA==.Hermer:BAAALAADCggIEwAAAA==.Hermerz:BAAALAADCgYIDQAAAA==.Hewbejeebees:BAAALAADCggIDAAAAA==.Hezzakan:BAAALAAECgEIAQAAAA==.',Hi='Hipn:BAAALAADCgQIBAAAAA==.',Ho='Holycannoli:BAAALAAECgYICQAAAA==.Holycef:BAAALAAECgMIBQAAAA==.Hotspur:BAAALAAECgYICQAAAA==.',Hu='Huevomuerto:BAAALAADCgIIAgAAAA==.Huevonyque:BAAALAAECgcIDwAAAA==.Hugues:BAAALAADCgcIBwAAAA==.Hungryhippo:BAAALAADCgEIAQAAAA==.Huntsthewind:BAAALAAECgIIAgAAAA==.Hunttaco:BAAALAADCgUIBQAAAA==.',Ii='Iiarian:BAAALAAECgYICQAAAA==.',Il='Ilivarra:BAAALAAECgYICQAAAA==.',In='Infoxy:BAAALAAECgEIAQAAAA==.Insanityalex:BAAALAAECgEIAQAAAA==.',Ir='Irimon:BAAALAAECgMIAwAAAA==.Irogram:BAAALAAECgQICAAAAA==.Ironside:BAAALAADCggICAABLAADCggIEAABAAAAAA==.',It='Itako:BAAALAADCgcIEgAAAA==.Itoldhimso:BAAALAAECggIBwAAAA==.',Iz='Iz:BAAALAADCggICAAAAA==.',Ja='Jadelark:BAAALAADCgcIBgAAAA==.Jairus:BAAALAADCggIDwAAAA==.Jammerwoch:BAAALAAECgYICQAAAA==.Jaxina:BAAALAADCgIIAgABLAAECgYICwABAAAAAA==.Jaxordamus:BAAALAAECgYICwAAAA==.',Je='Jeanaw:BAAALAADCgQIBAAAAA==.Jekle:BAAALAADCgMIAwAAAA==.Jema:BAAALAADCggIDwAAAA==.Jenilea:BAAALAAECgMIAwAAAA==.',Ji='Jimeni:BAAALAADCggIEgAAAA==.Jimwee:BAAALAAECgYIDgAAAA==.Jinha:BAAALAADCggICAAAAA==.Jinsu:BAAALAADCgcIGQAAAA==.Jinus:BAAALAADCgMIAwAAAA==.Jinxyjinx:BAAALAAECgQIBAAAAA==.',Jo='Joejogun:BAAALAADCggICAAAAA==.Jonfidence:BAAALAAECgUIBQAAAA==.Jordend:BAAALAADCgIIAwAAAA==.Jordyn:BAAALAADCgIIAgAAAA==.Joseppii:BAAALAADCgcICgAAAA==.',Ju='Jungyuul:BAAALAAECggICAAAAA==.',['Jå']='Jåzzy:BAAALAAECgIIAgAAAA==.',Ka='Kaandew:BAAALAAECgEIAQAAAA==.Kaganost:BAAALAADCggIDQAAAA==.Kaorin:BAAALAADCggIDQAAAA==.Kardinal:BAAALAADCgYICwAAAA==.Karonte:BAAALAAECgcIDQAAAA==.Karái:BAAALAAECgEIAQAAAA==.Kaylith:BAAALAADCggIFQAAAA==.',Ke='Kegwalker:BAAALAAECgcIDwAAAA==.Keirrah:BAAALAADCgQIBwAAAA==.Kennifur:BAAALAADCgQIBgAAAA==.Kenstraza:BAAALAADCgQIBAAAAA==.Kessia:BAAALAADCggIFwAAAA==.',Kh='Khaetri:BAAALAAECgYICQAAAA==.Khalistra:BAAALAAECgYICQAAAA==.Khitt:BAAALAADCggICAAAAA==.Khoyor:BAAALAADCggIGgAAAA==.',Ki='Killos:BAAALAAECgYIDgAAAA==.Kintsukuroï:BAAALAADCggIDwAAAA==.Kiropaly:BAAALAAECgIIAwAAAA==.Kithedrael:BAAALAADCgYIBgAAAA==.',Kl='Klouded:BAAALAAECgYIDgAAAA==.',Ko='Koa:BAAALAADCgcICwAAAA==.Kodokushi:BAAALAAECgYIBgABLAAECggIGAAEANgjAA==.Kokuto:BAAALAAECgYIDgAAAA==.Kolossus:BAAALAAECgYICAAAAA==.',Kr='Krispybacon:BAAALAADCgcICQAAAA==.Krygarre:BAAALAAECgEIAQAAAA==.Kryptica:BAAALAADCgYIBgAAAA==.',Ku='Kuzco:BAAALAAECgQICQAAAA==.',Kw='Kwahaw:BAAALAADCggICAAAAA==.',Ky='Kyttin:BAAALAADCgcIEgAAAA==.',La='Ladeeda:BAAALAADCgUIBQAAAA==.Lalena:BAAALAADCggIFgAAAA==.Lamisa:BAAALAAECgUICAAAAA==.Lashand:BAAALAAECgQIBAAAAA==.Lastalar:BAAALAAECgQIBAAAAA==.Laundryslayr:BAAALAADCggIEAAAAA==.',Le='Lemmiwinks:BAAALAADCgMIAwAAAA==.Lennethal:BAAALAADCggIFwAAAA==.Leonineone:BAAALAAECgcIEAAAAA==.Lergonath:BAAALAADCgUIBQAAAA==.',Li='Lightlady:BAAALAAECgEIAQAAAA==.Lilium:BAAALAADCggIEAAAAA==.Lillythorne:BAAALAADCggIDwAAAA==.Linas:BAAALAAECgIIAgAAAA==.Lithou:BAAALAAECgEIAQAAAA==.',Lo='Loocivar:BAAALAADCggIDwAAAA==.Lostsoul:BAAALAADCgYIBgAAAA==.Lothlum:BAAALAADCggIDAAAAA==.',Lu='Lunalia:BAAALAADCgUIBwAAAA==.Lupen:BAAALAAECgMIAwAAAA==.Luxlock:BAAALAAECgQIBAAAAA==.',Ly='Lyrr:BAAALAAECgEIAQAAAA==.',Ma='Maadurga:BAAALAAECgUIBgAAAA==.Maestrox:BAAALAADCgYIBgAAAA==.Malandras:BAAALAADCggIEgAAAA==.Malignities:BAAALAAECgQIBAAAAA==.Maltheradis:BAAALAAECgMIBgAAAA==.Malthruin:BAAALAADCggIDwABLAAECgEIAQABAAAAAA==.Manajamba:BAAALAAECgYIBwAAAA==.Mancubus:BAAALAAECgYIBwAAAA==.Marsest:BAAALAADCgcICQAAAA==.Maxidorf:BAAALAAECgEIAQAAAA==.',Me='Meilichia:BAAALAAECgYIDgAAAA==.Methyl:BAAALAADCgcIBwAAAA==.Meushi:BAABLAAECoEYAAIEAAgI2CNYBQAsAwAEAAgI2CNYBQAsAwAAAA==.',Mi='Mikaz:BAAALAADCgcIDQAAAA==.Mineral:BAAALAADCggIEAAAAA==.Miniroar:BAAALAAECgMIAwAAAA==.Miphisto:BAAALAADCgcIEwAAAA==.Mirandee:BAAALAADCggIFQAAAA==.Mirari:BAAALAADCggICAAAAA==.Mirranor:BAAALAADCgEIAQAAAA==.Mishrani:BAAALAAECgEIAQAAAA==.',Mo='Molding:BAAALAADCggIDQAAAA==.Molleesi:BAAALAAECgMIAwAAAA==.Moojersey:BAAALAADCgEIAQAAAA==.Moonstôrm:BAAALAAECgEIAQAAAA==.Mordraug:BAAALAADCggIDgAAAA==.Morinoe:BAAALAAECgEIAQAAAA==.',Mu='Mumrablink:BAAALAADCgcIBwAAAA==.Muncher:BAAALAAECgEIAQAAAA==.Murdermohawk:BAAALAAECgYIBgAAAA==.',['Mæ']='Mæcenia:BAAALAADCgcIDAAAAA==.',['Mÿ']='Mÿthunn:BAAALAAECgIIBQAAAA==.',Na='Nagratz:BAAALAAECgYICwAAAA==.Naichingeru:BAAALAADCgcIEwAAAA==.Nala:BAAALAAECgcIDwAAAA==.Nalibrown:BAAALAADCgcIBwAAAA==.Nalu:BAAALAADCggICgAAAA==.Naumin:BAAALAADCgcIDAAAAA==.Nayuu:BAAALAADCggICAAAAA==.',Ne='Necessities:BAAALAAECgMIAwAAAA==.Needalight:BAAALAADCggIEQAAAA==.Neiraah:BAAALAADCggIFAAAAA==.Nelithas:BAAALAAECgcICgAAAA==.Nenea:BAAALAADCgMIBAAAAA==.',Ni='Nichiwa:BAAALAAECgIIAgAAAA==.',No='Noadelgazo:BAAALAADCgEIAQAAAA==.Noamsky:BAAALAAECgEIAQABLAAECgcIDwABAAAAAA==.Nolmac:BAAALAAECgEIAQAAAA==.Noralea:BAAALAADCggICAAAAA==.Nosleep:BAAALAADCgcIEwAAAA==.',Nu='Nurple:BAAALAAECgIIAwAAAA==.',Ny='Nyinna:BAAALAADCgcIBwAAAA==.Nythros:BAAALAADCgEIAQAAAA==.',Nz='Nz:BAAALAAECggICAAAAA==.',Ob='Obifizzle:BAAALAADCggIDwAAAA==.Obtusepanda:BAAALAADCggIFwAAAA==.',Oc='Ocupocorrer:BAAALAAECgIIAgAAAA==.',Of='Offthechaeni:BAAALAADCggIFwAAAA==.',Og='Ogna:BAAALAAECgQIBgAAAA==.',Oh='Ohkqohr:BAAALAADCgQIBAAAAA==.',Oi='Oisin:BAAALAAECgEIAQAAAA==.',Om='Omathra:BAAALAAECgEIAQAAAA==.',On='Onikai:BAAALAAECgUICAAAAA==.Onruk:BAAALAAECgMIBgAAAA==.',Or='Orchestra:BAAALAADCggIEAAAAA==.',Ow='Owzla:BAAALAADCggIEAAAAA==.',Ox='Oxidising:BAAALAAECgYICgAAAA==.',Pa='Paladullahan:BAAALAAECgQIBQAAAA==.Palagrum:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Pallythepal:BAAALAAECgMIBQAAAA==.Pandead:BAAALAAFFAIIAgAAAA==.Patadas:BAAALAAECgIIAwAAAA==.Pawplay:BAEALAADCggIFgABLAAECggIFgADAN4mAA==.',Pe='Peekabòó:BAAALAADCggICAAAAA==.Pennonteller:BAAALAADCgIIAgAAAA==.Perhaps:BAAALAAECgQIBgAAAA==.Petríchor:BAAALAAECgEIAQAAAA==.',Ph='Phantsu:BAAALAADCgYIBgAAAA==.Phrenominon:BAAALAAECgMIAwAAAA==.',Pl='Plagueniss:BAAALAAECgcIEAAAAA==.',Po='Poge:BAAALAAECgQIBQAAAA==.Pognak:BAEALAAECgQIBQAAAA==.Pompino:BAAALAAECgEIAQAAAA==.',Ps='Psychó:BAAALAAECgYIDgAAAA==.',Pu='Purplêlotus:BAAALAAECgMIAwAAAA==.Purrl:BAAALAAECgIIAwAAAA==.',Py='Pyana:BAAALAADCggIFwAAAA==.Pyke:BAAALAADCgYIBgAAAA==.',Qs='Qserie:BAAALAADCgcICwAAAA==.',Qu='Questor:BAAALAADCgYIBgAAAA==.',Ra='Raankohmojo:BAAALAADCggICAAAAA==.Raevie:BAAALAAECgMIAwAAAA==.Rahner:BAAALAADCgYICQABLAADCggICAABAAAAAA==.Raidgriefer:BAAALAAECgcIDAAAAA==.Raiynz:BAAALAADCgEIAQAAAA==.Rakwell:BAAALAAECgMIAwAAAA==.Ramil:BAAALAADCgEIAQAAAA==.Ramorash:BAAALAADCgQIBAAAAA==.Ranarae:BAAALAADCgcIDQAAAA==.Rastacef:BAAALAADCggIDAABLAAECgMIBQABAAAAAA==.Ravielly:BAAALAAECgQIBQAAAA==.',Re='Reddit:BAAALAADCggIEAAAAA==.Redmaple:BAAALAADCgQIBAABLAAECgEIAQABAAAAAA==.Refaim:BAAALAADCgYIBgAAAA==.Reneilla:BAAALAADCggICAAAAA==.Resk:BAAALAADCgYICQAAAA==.Reteril:BAAALAAECgIIAwAAAA==.Reyis:BAAALAAECgIIAwAAAA==.Reyvinite:BAAALAAECgYICwAAAA==.',Rh='Rhodaria:BAAALAADCggIFwAAAA==.Rhyme:BAAALAAECgcIEAAAAA==.',Ri='Rimuru:BAAALAAECgcIDwAAAA==.Rintalasin:BAAALAAECgEIAQAAAA==.Risuu:BAAALAAECgcIDgAAAA==.',Ro='Roasted:BAAALAAECgEIAQAAAA==.Romeow:BAAALAADCggICAAAAA==.Rookie:BAAALAADCgMIAwAAAA==.Roper:BAAALAAECgIIAgAAAA==.Rousou:BAAALAAECgQIBgAAAA==.',Ru='Rukia:BAAALAAECgYICwAAAA==.',Ry='Ryoushen:BAAALAAECgcIEAAAAA==.',['Ró']='Ró:BAAALAAECgIIAgAAAA==.',Sa='Sadie:BAAALAADCgYICQAAAA==.Sapphism:BAAALAAFFAIIAgAAAA==.Sarbo:BAAALAADCgUIBwAAAA==.Sarma:BAAALAADCgUIBwAAAA==.Saskwatch:BAAALAADCggICAABLAAECgcIDwABAAAAAA==.Savat:BAAALAAECgEIAQAAAA==.',Sc='Scerla:BAAALAAECgEIAQAAAA==.Sckritch:BAAALAAECgEIAQAAAA==.Scoochacho:BAAALAAECgYICQAAAA==.Scottyhunter:BAAALAAECgQIBAAAAA==.',Se='Serrendipity:BAAALAAECgYIDgAAAA==.Sethôs:BAAALAADCgIIAgAAAA==.',Sh='Shadowfang:BAAALAAECgMIAwAAAA==.Shadowfàng:BAAALAADCggICAAAAA==.Shalarina:BAAALAADCgIIAgAAAA==.Shamarq:BAAALAADCgcIEwAAAA==.Shandrahli:BAAALAADCggIDwAAAA==.Shaylina:BAAALAAECgEIAQAAAA==.Shiftyhart:BAAALAADCggIEAAAAA==.Shintazhi:BAAALAAECgEIAQAAAA==.Shirkan:BAAALAAECgYICQAAAA==.Shiyotso:BAAALAAECgMIBAAAAA==.Shojobeat:BAAALAAECgUICgAAAA==.',Si='Sigillaria:BAAALAADCgYIBgAAAA==.Sinku:BAAALAADCggIDgAAAA==.Sinza:BAAALAADCggICAABLAADCggIDgABAAAAAA==.Siné:BAABLAAECoEUAAMDAAcIjhpmIQD8AQADAAcIKBhmIQD8AQAFAAQIURrgFwA7AQAAAA==.',Sk='Skadooshh:BAAALAAECgMIAwAAAA==.Skaranda:BAAALAADCggIEAAAAA==.Sklountst:BAAALAADCgcICAAAAA==.Skuldd:BAAALAADCgYIBgAAAA==.',Sm='Smokedbbq:BAAALAADCggIFgAAAA==.',So='Soulmates:BAEALAAECgcIDwAAAA==.Soup:BAAALAAECgYICAAAAA==.Sousp:BAAALAAECgEIAQAAAA==.',Sp='Spiara:BAAALAAECgMIAwAAAA==.Spyroh:BAAALAAECgQIBQAAAA==.',St='Stonebrew:BAAALAADCgcIEwAAAA==.Stormbrook:BAAALAAECgQIBQAAAA==.Sturmdorf:BAAALAAECgEIAQAAAA==.',Su='Suhpplieds:BAAALAAECgcIDwAAAA==.Summannuz:BAAALAADCgEIAQAAAA==.Surdor:BAAALAADCgUIBgAAAA==.',Sw='Sweets:BAAALAAECgEIAQAAAA==.',Sy='Sykko:BAABLAAECoEVAAMGAAgITB9HBAC7AgAGAAgI6R1HBAC7AgAHAAUIJA7cSgAHAQAAAA==.Sylvanyass:BAAALAAECgcICwAAAA==.Symet:BAAALAADCgQIBAAAAA==.',Ta='Tabb:BAAALAADCgcIBwAAAA==.Tache:BAAALAAECgEIAQAAAA==.Taera:BAAALAADCggIEwAAAA==.Talandroz:BAAALAAECgMIAwAAAA==.Tanashi:BAAALAADCgIIAgAAAA==.Tape:BAAALAAECgEIAQAAAA==.Tayllore:BAAALAAECgYICQAAAA==.',Te='Tearsheet:BAAALAADCgcIEwABLAAECgYICQABAAAAAA==.Teraall:BAAALAADCggIDwAAAA==.Terendelev:BAAALAAECgcIEAAAAA==.Terraviridis:BAAALAAECgYICQAAAA==.Tevran:BAAALAAECgQIBgAAAA==.',Th='Thalassairi:BAAALAAECgEIAQAAAA==.Thaldin:BAAALAADCggIDAAAAA==.Thaleris:BAAALAAECgUIBgAAAA==.Thalstein:BAAALAADCggICAABLAAECgUIBgABAAAAAA==.Thaugtlesz:BAAALAADCgcIDQABLAAECgQIBQABAAAAAA==.Thelonious:BAAALAAECgEIAQAAAA==.Thronjak:BAAALAAECgQIBQAAAA==.Thunderwoman:BAAALAADCgcIBwAAAA==.Thurine:BAAALAADCgcICQAAAA==.Tháht:BAAALAADCggIFgAAAA==.',Ti='Tiandra:BAAALAADCgEIAQAAAA==.Tidepod:BAAALAAECgcIDwAAAA==.Tidêpod:BAAALAADCggICgAAAA==.Tipride:BAAALAAECgcIEAABLAADCggIEAABAAAAAA==.Tiralie:BAAALAAECgUIBgAAAA==.Tiryl:BAAALAADCggIFgAAAA==.',To='Toogodly:BAAALAAECgMIBQAAAA==.Totemwalker:BAAALAADCggICAABLAAECgcIDwABAAAAAA==.',Tr='Tranak:BAAALAADCgYIBgAAAA==.Trickcast:BAABLAAECoEWAAIIAAgIgCXuAAB1AwAIAAgIgCXuAAB1AwAAAA==.Trystern:BAAALAAECgQIBQAAAA==.',Ts='Tsonett:BAAALAAECgUIBwAAAA==.',Tu='Turmeric:BAAALAADCggICAAAAA==.',Ty='Tyberos:BAAALAADCgQIBQAAAA==.',['Tä']='Tänya:BAAALAAECgQIBQAAAA==.',Ui='Uitaar:BAAALAAECgYIBgAAAA==.',Ul='Ultoshaolin:BAAALAAECgEIAQAAAA==.',Va='Valhalina:BAAALAADCggICAAAAA==.Valri:BAAALAADCgcIDAAAAA==.Valtari:BAAALAADCggIEQAAAA==.Vancasper:BAAALAAECgIIAwAAAA==.Varidall:BAAALAAECgEIAgAAAA==.Varl:BAAALAAECgcIEAAAAA==.Varlock:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Vasileia:BAAALAADCggIEwAAAA==.',Ve='Vellious:BAAALAAECgYIBgAAAA==.Velmathris:BAAALAAECgEIAQAAAA==.Ventnor:BAAALAADCgEIAQAAAA==.Verinax:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Vi='Viely:BAAALAAECgQIBAAAAA==.Vil:BAAALAAECgQIBgAAAA==.Vincentlight:BAAALAADCggIEQAAAA==.Vintorez:BAAALAAECgQIBgAAAA==.Viralmaster:BAEALAAECgYICQAAAA==.',Vo='Voidweaver:BAAALAAECgMIBQAAAA==.Volteer:BAAALAAECgMIBwAAAA==.Voodooshiftn:BAAALAADCggICAABLAAECgUIBwABAAAAAA==.Vorticia:BAAALAADCgMIAwAAAA==.',Vy='Vyara:BAAALAAECgEIAQAAAA==.Vynddradoria:BAAALAAECgYIDgAAAA==.Vynlock:BAAALAAECgcIEAAAAA==.Vynmage:BAAALAAECgEIAQAAAA==.',Wa='Wabe:BAAALAADCgYICAAAAA==.Walt:BAAALAAECgQIBAAAAA==.Wanderit:BAAALAADCggIFgAAAA==.',We='Webby:BAAALAADCgEIAQABLAAECgEIAQABAAAAAA==.Wetgrills:BAAALAAECgcIDQAAAA==.',Wh='Whachow:BAAALAADCgEIAQAAAA==.Whithers:BAAALAADCggIFAAAAA==.',Wi='Wickerflame:BAAALAADCgcIBwAAAA==.Willidan:BAAALAAECgcIBwAAAA==.Wilyy:BAAALAAECgMIAwAAAA==.Wintergreen:BAAALAADCgYIBgAAAA==.Wishque:BAAALAAECgIIAgAAAA==.',Wo='Woodsylver:BAAALAAECgIIAwAAAA==.Worski:BAAALAAECgEIAQAAAA==.',Wr='Wratharion:BAAALAADCgUIBQABLAAECgYICQABAAAAAA==.Wratherael:BAAALAAECgYICQAAAA==.Wrathiechan:BAAALAADCggIDwABLAAECgYICQABAAAAAA==.Wraîth:BAAALAAECgYICgAAAA==.',Wu='Wurdiz:BAAALAADCgcICwABLAAECgYICQABAAAAAA==.',Wy='Wyllownite:BAAALAADCggICAABLAAECgQIBAABAAAAAA==.Wynilla:BAAALAAECgEIAQAAAA==.',Xa='Xanamage:BAAALAADCggICAAAAA==.Xanathar:BAAALAAECgMIBAAAAA==.Xandu:BAAALAADCggIFAAAAA==.Xanto:BAAALAADCgYIBwAAAA==.Xaphoris:BAAALAADCgcIBwAAAA==.Xayleficent:BAAALAADCgcIDQAAAA==.Xaylia:BAAALAAECgQIBQAAAA==.',Xe='Xenolith:BAAALAADCgcIEAAAAA==.Xerial:BAAALAADCgYIBgABLAAECgQIBQABAAAAAA==.',Xi='Xiaren:BAAALAAECgMIAwAAAA==.Xifangbaihu:BAAALAAECgcICgAAAA==.Xilith:BAAALAADCggIAwAAAA==.',Ya='Yaotl:BAAALAADCgYIBgABLAAECgQIBQABAAAAAA==.Yaoxt:BAAALAAECgQIBQAAAA==.Yassi:BAAALAAECgQIBgAAAA==.',Ye='Yefimovich:BAAALAADCggIDgAAAA==.Yeyiayotl:BAAALAADCgUIBQAAAA==.',Yn='Ynkdragon:BAAALAAECgcIDwAAAA==.',Yu='Yurgen:BAAALAADCgMIAwAAAA==.Yuzuriha:BAAALAAECgcIEgAAAA==.',Yv='Yvade:BAAALAADCgUIBQAAAA==.Yvane:BAAALAADCggIDQAAAA==.',Za='Zanduran:BAAALAAECgIIAwAAAA==.Zarik:BAAALAAECgEIAQAAAA==.Zarith:BAAALAADCggIBgAAAA==.Zarron:BAAALAAECgIIAgAAAA==.',Ze='Zekiel:BAAALAADCggICAAAAA==.Zerah:BAAALAADCgUIBQAAAA==.',Zh='Zhend:BAAALAAECgEIAQAAAA==.',Zo='Zooangel:BAAALAAECgMIBQAAAA==.Zooearth:BAAALAAECgIIAgAAAA==.',Zu='Zukaza:BAAALAAECgQIBgAAAA==.Zunch:BAAALAAECgIIAwAAAQ==.',['Àz']='Àzazel:BAAALAAECgYIDgAAAA==.',['Öt']='Ötzi:BAAALAADCgcICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end