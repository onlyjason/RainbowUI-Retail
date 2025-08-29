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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Vengeance','Warlock-Destruction','Priest-Holy','Druid-Feral','Warrior-Fury','Monk-Brewmaster','Druid-Restoration',}; local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adalaidê:BAAALAADCggIFgAAAA==.Adriel:BAAALAADCgQIBQABLAAECgcIEQABAAAAAA==.Adu:BAAALAADCgcIBwAAAA==.',Ae='Aelirenn:BAAALAADCgcIBwAAAA==.Aeluu:BAAALAAECgcIEAAAAA==.Aerynne:BAAALAAECgIIAwAAAA==.Aetarius:BAAALAADCgYIBgABLAADCggICQABAAAAAA==.',Ai='Ailis:BAAALAAECgEIAQABLAAECggIFQACAIYcAA==.Airie:BAAALAAECgMIBwAAAA==.Aita:BAAALAADCgcICQABLAADCgQIBAABAAAAAA==.',Ak='Akuso:BAAALAADCggICwAAAA==.',Al='Alluna:BAAALAADCgEIAQAAAA==.Aloy:BAABLAAECoEUAAIDAAgIeB2xCwCoAgADAAgIeB2xCwCoAgAAAA==.Aluciene:BAAALAADCgcIBwAAAA==.Alulà:BAAALAAECgIIAgAAAA==.Alyndria:BAAALAAECgMIBwAAAA==.',An='Anaeli:BAAALAAECgMIBAAAAA==.Anathialin:BAAALAADCgMIAwAAAA==.Angita:BAAALAADCggIFQAAAA==.Annaris:BAABLAAECoEWAAMEAAgIriNmBAD1AgAEAAgIIiJmBAD1AgAFAAcI8iFjAQCNAgAAAA==.Antipæn:BAAALAAECgYICAABLAAECgcIEAABAAAAAA==.',Ap='Apollobean:BAAALAAECgYIBgAAAA==.Apologia:BAAALAAECgMIBgAAAA==.Apoqe:BAAALAADCgEIAQAAAA==.',Ar='Ares:BAAALAAECgEIAQAAAA==.Arilynx:BAAALAAECgYIBgAAAA==.Armorgorden:BAAALAAECgYICAAAAA==.Aryxe:BAAALAADCgcICAAAAA==.',As='Ashtareth:BAAALAAECgYIDAAAAA==.Asuna:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',Au='Aurore:BAAALAADCgMIAwAAAA==.Aurti:BAAALAAECgYIDAAAAA==.',Av='Avanel:BAAALAAECgYIDwAAAA==.',Ax='Axw:BAAALAAECgMIAwAAAA==.',Ay='Ayobi:BAAALAAECgIIAgAAAA==.',Az='Azbogah:BAAALAAECgcIEQAAAA==.',['Aè']='Aègis:BAAALAAECgMIAwAAAA==.',Ba='Baddragons:BAAALAADCgcIDAAAAA==.Badskippy:BAAALAADCgYIBgAAAA==.Bahahaknight:BAAALAAECgMIBwAAAA==.Barnette:BAAALAAECgcIEAAAAA==.',Be='Bearussy:BAAALAAECgYICQAAAA==.Bedd:BAAALAAECgMIAwAAAA==.Belthos:BAAALAAECgIIAwAAAA==.Benwabbles:BAAALAAECgMIAwAAAA==.Beorin:BAAALAADCgUIBQAAAA==.Berzhus:BAAALAAECggIEgAAAA==.',Bl='Bluespruce:BAAALAAECgcIEAAAAA==.Bluewitchpa:BAAALAADCgcIEAAAAA==.',Bo='Bombaclat:BAAALAAECgQIBAAAAA==.Boudiicca:BAAALAAECgIIAwAAAA==.Boxmasterr:BAAALAAECgYIDAAAAA==.',Br='Brassmonky:BAAALAAECgQICAAAAA==.',Bu='Bubblement:BAAALAAFFAIIAgAAAQ==.Buckchoy:BAAALAADCgMIAwAAAA==.Buckhunter:BAAALAAECgQIBAAAAA==.',['Bö']='Börk:BAAALAADCggIFQAAAA==.',Ca='Cassyn:BAAALAADCgcIBwAAAA==.Catalyst:BAAALAADCggICQAAAA==.Catona:BAAALAADCgUICAABLAAECgcIEQABAAAAAA==.Cayda:BAAALAADCgMIAwAAAA==.Caylara:BAAALAAECgEIAQAAAA==.Cayssaber:BAAALAAECgQIBwAAAA==.',Ce='Celistia:BAAALAAECgYIDAAAAA==.Celrythis:BAAALAAECgEIAQAAAA==.',Ch='Chiakí:BAAALAAECgUICQAAAA==.Chiji:BAAALAAECgIIAgAAAA==.',Ci='Cirilaa:BAAALAADCgMIAwAAAA==.',Cl='Claes:BAAALAAECgYICQAAAA==.Clausewïtz:BAAALAAECggICAAAAA==.Clawdia:BAAALAADCgcIDQAAAA==.Clipperz:BAAALAADCgQIBAAAAA==.',Co='Comotion:BAAALAADCgYIBgAAAA==.Coralorchid:BAAALAADCgcIEwAAAA==.',Cr='Crashout:BAAALAAECgYICAAAAA==.Cromenockle:BAAALAADCgQIBAAAAA==.',Ct='Cthula:BAAALAADCggICAAAAA==.',Cu='Curissan:BAAALAADCggIDwAAAA==.',Cy='Cynalinn:BAAALAAECgIIAwAAAA==.Cyrinn:BAAALAADCggICAAAAA==.',['Cè']='Cères:BAAALAAECgYICgAAAA==.',Da='Dahl:BAAALAAECgYICgAAAA==.Daick:BAAALAADCggIDAAAAA==.Dalir:BAAALAADCgcIEgAAAA==.Dalthepal:BAAALAAFFAIIAgAAAA==.Danky:BAAALAADCgEIAQAAAA==.Darkdahlia:BAAALAADCgYICQAAAA==.Darkseide:BAAALAADCgcIBwAAAA==.',De='Deathennaric:BAAALAADCgYIBgAAAA==.Deathsaberss:BAAALAAECgYICwAAAA==.Debauch:BAAALAAECgMIAwAAAA==.Dejamoo:BAAALAADCgMIBgAAAA==.Demonkayk:BAAALAAECgEIAgAAAA==.Dendahn:BAAALAADCgcIBwAAAA==.Deskillaa:BAAALAAECgUICAAAAA==.',Di='Diladrin:BAAALAAECgcIEAAAAA==.Dilawyr:BAAALAADCgIIAgAAAA==.Dinglesquirt:BAAALAAECgIIAgABLAAECgcIEQABAAAAAA==.Diode:BAABLAAECoEVAAMGAAgIwx5vBgBMAgAGAAcIJxlvBgBMAgAHAAcIABcuIQD9AQAAAA==.',Do='Doileag:BAAALAAECgIIAgAAAA==.Dominick:BAAALAADCgcIDwAAAA==.Dottmatrix:BAAALAADCggIFQAAAA==.',Dr='Drall:BAAALAAECgYICgAAAA==.Dreadwing:BAAALAAECgIIAwAAAA==.Drfoster:BAAALAADCggIBgAAAA==.Drubreeze:BAAALAADCggICAAAAA==.',Du='Dufdh:BAABLAAECoEVAAIIAAgIJSMDAQAuAwAIAAgIJSMDAQAuAwAAAA==.Dunlock:BAAALAAECgIIAgABLAAECgIIAgABAAAAAA==.Dustbunny:BAAALAAECgMIBAAAAA==.',['Dà']='Dàl:BAAALAAECgcIDQABLAAFFAIIAgABAAAAAA==.Dàlaboom:BAAALAAECgEIAQABLAAFFAIIAgABAAAAAA==.',['Dì']='Dìzzy:BAAALAAECgEIAQAAAA==.',['Dû']='Dûn:BAAALAAECgIIAgAAAA==.',Ei='Eira:BAAALAADCgcIDAAAAA==.',El='Elaatia:BAAALAAECgYIDAAAAA==.Elbatmon:BAAALAADCgcIBwAAAA==.Elduke:BAAALAADCgEIAQAAAA==.Elidria:BAAALAADCgYIBwAAAA==.Elketha:BAAALAAECgcIEAAAAA==.Ellannah:BAAALAAECgEIAQAAAA==.Elrric:BAAALAAECgUICQAAAA==.',Em='Emberfang:BAAALAADCgcIDQABLAAECgYIDAABAAAAAA==.Emese:BAAALAAECgEIAQAAAA==.Emnys:BAAALAADCgQIBwABLAAECgEIAQABAAAAAA==.',Er='Erovvia:BAAALAAECgYIDAAAAA==.',Ex='Exander:BAAALAADCgQIBQAAAA==.',Ez='Ezothen:BAAALAAECgUIBQAAAA==.',Fa='Fatgoku:BAAALAAECgYICQAAAA==.',Fe='Felcroissant:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Feldaedra:BAAALAAECgYICQAAAA==.Felpak:BAAALAAECgYIDAAAAA==.',Fi='Firebrande:BAAALAADCggIFQAAAA==.Firefoxx:BAAALAAECgYICAAAAA==.Fisticuffs:BAAALAADCgcICgAAAA==.Fizzllebang:BAAALAAECgUICQAAAA==.',Fl='Flamewhisker:BAAALAADCggIFQAAAQ==.',Fr='Fraublucher:BAAALAAECgMIAwAAAA==.Fredrik:BAAALAAECgIIAgABLAAECgQIBwABAAAAAA==.Frewyn:BAAALAADCgcIDwAAAA==.Friggola:BAAALAAECgMIBgAAAA==.Fromunda:BAAALAADCgQIBAAAAA==.Frostimoth:BAAALAAECgIIAgAAAA==.Frozty:BAAALAAECgMIAwAAAA==.',Ga='Galandel:BAAALAADCgcIEAAAAA==.Galial:BAAALAAECgYIDAAAAA==.Garradin:BAAALAADCggIDwAAAA==.Gaznol:BAAALAAECgIIAgAAAA==.',Ge='Geddy:BAAALAAECgUICAAAAA==.Gelasera:BAAALAADCggIFQAAAA==.Gentlestorm:BAAALAADCggIDwAAAA==.',Gl='Glaivethras:BAAALAAECgUICQAAAA==.',Gr='Gridin:BAAALAAECgUICAAAAA==.Groot:BAAALAAECgIIAgABLAAECgMIBgABAAAAAA==.',He='Hearthstone:BAAALAAECgYICQAAAA==.Heckk:BAAALAAECgIIAgAAAA==.',Hi='Hilimed:BAAALAAECgUICQAAAA==.',Ho='Holi:BAAALAADCgcIDQAAAA==.Hollowníght:BAAALAADCgIIAgAAAA==.Holyßloodelf:BAAALAAECgYIDAAAAA==.Honcho:BAAALAAECgEIAQAAAA==.Hornbrez:BAAALAAECgYICgAAAA==.Hotandspicey:BAAALAADCgcICAAAAA==.Hozluz:BAAALAAECgQIBwAAAA==.',Hu='Humungous:BAAALAAECgIIAgAAAA==.Huskerdude:BAAALAADCggIDgAAAA==.',Hy='Hyve:BAAALAAECgMIBAAAAA==.',Ib='Ibedrinkin:BAAALAADCggIEQAAAA==.Ibloom:BAAALAADCgIIAgAAAA==.',Il='Illiðan:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',In='Indicà:BAAALAADCggICAAAAA==.',Ir='Irkenfox:BAAALAAFFAIIAgAAAA==.',Is='Isogni:BAAALAADCgYICAABLAAECgIIAgABAAAAAA==.',Ix='Ixitt:BAAALAAECgYIDAAAAA==.',Ja='Jama:BAAALAADCggIBwAAAA==.Janaa:BAAALAAECgUIBQAAAA==.Jarre:BAAALAAECgYICgAAAA==.Jayrod:BAAALAAECggIEwAAAA==.',Je='Jeremywillia:BAAALAADCgcIBwAAAA==.',Jh='Jhonson:BAAALAAECgEIAQAAAA==.',Ji='Jimboberjim:BAABLAAECoEVAAIJAAgIVyFkBQABAwAJAAgIVyFkBQABAwAAAA==.Jimbobwhey:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Jiminie:BAAALAAECgEIAQAAAA==.',Jo='Jojokiller:BAAALAADCgIIAgAAAA==.Jolio:BAAALAADCgEIAQAAAA==.Jordyy:BAAALAAECgUIBgAAAA==.Joshe:BAAALAADCggICAABLAAECgYICgABAAAAAA==.Joshie:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.',Ju='Judgejudie:BAAALAADCgYIBgAAAA==.Jujubean:BAAALAADCgMIAwAAAA==.Jujubeans:BAAALAAECgYICAAAAA==.Jujudd:BAAALAADCgcIBwAAAA==.Juniornite:BAAALAADCggIEgABLAAECgMIBAABAAAAAA==.',Jy='Jylek:BAAALAAECgEIAQAAAA==.',['Jø']='Jøsh:BAAALAADCgUIBQAAAA==.',Ka='Kagemaro:BAAALAADCgcICQAAAA==.Kainan:BAAALAAECgUIBwABLAAECgYIDgABAAAAAA==.Kalzod:BAAALAAECgYIDwAAAA==.Kativeria:BAAALAADCggIDwAAAA==.Kattara:BAAALAAECgcIEwAAAA==.Kayssaber:BAAALAADCggIEAAAAA==.Kazarale:BAAALAAECgQIBgAAAA==.',Ke='Keeferan:BAAALAADCgMIAwAAAA==.Kekleshmeck:BAAALAAECgYICgAAAA==.Kemprei:BAAALAAECgEIAQAAAA==.Kepleton:BAAALAADCgUIBQAAAA==.',Ki='Killmora:BAAALAADCgcIEAAAAA==.Kip:BAAALAADCgUIBQAAAA==.',Ko='Kodazoff:BAAALAAECgEIAQAAAA==.Korevash:BAAALAAECgcIEAAAAA==.Korlash:BAAALAAECgYICAAAAA==.Korupta:BAAALAAECgYICwAAAA==.Korvari:BAAALAAECgIIAwAAAA==.Korà:BAAALAADCgcIDAAAAA==.Kozandrov:BAAALAADCggIFQAAAA==.',Kr='Krissylu:BAAALAADCgcICwAAAA==.Krothix:BAAALAAECgIIAwAAAA==.Krydem:BAAALAADCgIIAgAAAA==.Krysham:BAAALAADCgMIAwAAAA==.',Ku='Kurorø:BAAALAAECgEIAQAAAA==.',Ky='Kyrayna:BAAALAADCgEIAQAAAA==.',La='Laima:BAAALAADCgMIBgAAAA==.Laminegordon:BAAALAAECgcIBwAAAA==.Lamlam:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.Landil:BAAALAADCgcIDgAAAA==.Lanea:BAAALAADCgcIBwAAAA==.Latvias:BAAALAAECgEIAQAAAA==.Laudso:BAAALAADCgEIAQAAAA==.Lavitz:BAAALAAECgEIAQAAAA==.Layssaelyyia:BAAALAADCgcICQAAAA==.',Le='Leilanii:BAAALAADCgIIAgAAAA==.',Lh='Lhei:BAAALAAECgEIAQAAAA==.',Li='Liamthedrunk:BAAALAAECgEIAQAAAA==.Lightstormer:BAAALAADCgYIDwAAAA==.Lilach:BAAALAADCgYIDAAAAA==.Lilarielle:BAAALAAECgUIBgAAAA==.Lilielá:BAAALAAECgIIAgAAAA==.Linca:BAAALAADCgcIBwAAAA==.',Lo='Lowchin:BAAALAADCgcIDwAAAA==.',Lu='Lumia:BAABLAAECoEWAAIKAAgI/gvoHgCuAQAKAAgI/gvoHgCuAQAAAA==.',Ly='Lycemmas:BAAALAAECgMIBQAAAA==.',['Lï']='Lïlly:BAAALAADCggICQAAAA==.',Ma='Macoun:BAAALAAECgYICQAAAA==.Magaa:BAAALAADCgYICQAAAA==.Magicshowers:BAAALAAECgYIDAAAAA==.Martei:BAABLAAECoEVAAILAAgI0x+3AQAEAwALAAgI0x+3AQAEAwAAAA==.Maríneth:BAAALAAECgEIAQAAAA==.Matou:BAAALAAECgMIBgAAAA==.',Me='Melaestra:BAAALAADCggIFQAAAA==.Melinoë:BAAALAADCggIFQAAAA==.Mentalglow:BAAALAADCgIIAgAAAA==.Merali:BAAALAAECgEIAgAAAA==.',Mh='Mhorro:BAAALAAECgIIAwAAAA==.',Mi='Mikewazowski:BAAALAADCgcICQABLAAECgcIEQABAAAAAA==.Mindgames:BAAALAADCgcIBwAAAA==.Mini:BAAALAAECgYICAAAAA==.Mistrariel:BAAALAAECgYICgAAAA==.',Mo='Mojomarv:BAAALAADCgcIBwAAAA==.Monach:BAAALAADCgQIBQAAAA==.Monarch:BAAALAAECggIAQAAAA==.Monbear:BAAALAAECgEIAQAAAA==.Monktusken:BAAALAADCgMIAwAAAA==.',['Mô']='Mônteså:BAAALAADCgcICwAAAA==.',Na='Naturebait:BAAALAADCggIEAAAAA==.Nazuros:BAAALAAECgUICAAAAA==.',Ne='Necia:BAAALAAECgUICQAAAA==.Nellond:BAAALAADCgcIDQAAAA==.Nevermøre:BAAALAADCgUIBQAAAA==.',Ni='Nicepriest:BAAALAADCgEIAgAAAA==.Nimravidae:BAAALAAECgMIBwAAAA==.Ninelives:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Nitecrawler:BAAALAADCgUIBQAAAA==.Niteryu:BAAALAAECgMIBAAAAA==.',No='Novu:BAAALAAECgIIAgAAAA==.Noxolon:BAAALAAECgUIBwAAAA==.Noxturne:BAAALAADCggIDwAAAA==.',Nu='Nufy:BAAALAAECgYIDgAAAA==.Nuu:BAAALAAECgIIAgABLAAECgYIEwABAAAAAA==.',Ob='Obernasus:BAAALAAECgIIAgAAAA==.',Oi='Oili:BAAALAAECgEIAQAAAA==.',Ol='Oldrøse:BAAALAADCggIDwAAAA==.Olera:BAAALAAECgMIAwAAAA==.',Ot='Ottuk:BAAALAAECgYIDAAAAA==.',Oz='Ozzay:BAAALAADCgYICgAAAA==.',Pa='Pablom:BAAALAADCgMIBgAAAA==.Paksenarrion:BAAALAAECgMIBwAAAA==.Pandemönium:BAAALAAECgIIAwAAAA==.Patchington:BAAALAAECgEIAQAAAA==.Patchmax:BAAALAADCgMIAwAAAA==.',Pe='Peryite:BAAALAAECgYICgAAAA==.',Pi='Piingu:BAAALAAECgEIAQAAAA==.',Pl='Pleggster:BAAALAAECgUICQAAAA==.',Po='Pooff:BAAALAADCgQIBAAAAA==.Poppalock:BAAALAAECgEIAQAAAA==.',Pr='Protricity:BAAALAADCgQIBAABLAAECgUICAABAAAAAA==.',Pu='Pulcheria:BAAALAADCgUIBQAAAA==.Puppytoes:BAAALAAECgQIBwAAAA==.',['Pà']='Pàradise:BAAALAADCggIDAAAAA==.',['Pæ']='Pæn:BAAALAAECgcIEAAAAA==.',Qu='Quan:BAAALAADCggIFQAAAA==.Quartermain:BAAALAADCgcIDAAAAA==.Quenkiller:BAAALAADCggIDAAAAA==.',Ra='Rancooll:BAAALAADCgcIEAAAAA==.Rasic:BAAALAADCggICAAAAA==.Rasniir:BAAALAAECgUIBQAAAA==.Ravise:BAAALAADCgMIAwAAAA==.Rayuh:BAAALAADCggICQAAAA==.Raz:BAAALAAECgMIBAAAAA==.',Re='Regna:BAABLAAECoEUAAIMAAcIOyRfCQDRAgAMAAcIOyRfCQDRAgAAAA==.Remaked:BAACLAAFFIEFAAINAAMIERPPAQDhAAANAAMIERPPAQDhAAAsAAQKgRcAAg0ACAhtIUcDALwCAA0ACAhtIUcDALwCAAAA.Requinix:BAAALAAECgMIBAAAAA==.Reta:BAAALAAECgUICQAAAA==.',Ri='Rickjamesb:BAAALAAECggIEwAAAA==.Rickyybobbie:BAAALAAECgQIBQAAAA==.Ririko:BAAALAAECgMIBwAAAA==.Rivèrwind:BAAALAADCgcIBwAAAA==.Rizzla:BAAALAAECgMIAwAAAA==.',Ro='Roguebâit:BAAALAADCgUIBQAAAA==.',Ru='Rumi:BAAALAAECggIEAAAAA==.',Ry='Ryeekan:BAAALAAECgIIAgAAAA==.Ryuma:BAAALAADCggIDgAAAA==.',Sa='Saava:BAAALAADCgYIBgAAAA==.Sabrosura:BAAALAAECgMIBgAAAA==.Salsinor:BAAALAAECgMIAwAAAA==.Sanosagara:BAAALAAECgMIAwAAAA==.Sarahkka:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.Sareen:BAAALAAECgEIAQAAAA==.',Sc='Schaden:BAAALAAECgUICQABLAAECgYICgABAAAAAA==.',Se='Seijo:BAAALAADCgcIBwAAAA==.Sentence:BAAALAADCgYIBwAAAA==.',Sh='Shammylam:BAAALAADCgcICgABLAAECgYIDAABAAAAAA==.Shamwowee:BAAALAADCgcIEAAAAA==.Shamzee:BAAALAAECgIIAgAAAA==.Shandalf:BAAALAAECgIIAwAAAA==.Shuddarun:BAABLAAECoEUAAIDAAgI2SKQAwAyAwADAAgI2SKQAwAyAwAAAA==.',Si='Siavan:BAAALAADCggIEAAAAA==.Silvah:BAAALAADCgYICAAAAA==.Simn:BAAALAAECgIIAgAAAA==.',Sl='Slayvylora:BAAALAAFFAIIAgAAAA==.Slicedbread:BAABLAAECoEXAAIOAAgIDRsDCwBIAgAOAAgIDRsDCwBIAgAAAA==.Slices:BAAALAADCgEIAQAAAA==.',Sm='Smoldersham:BAAALAADCgYIBgAAAA==.',Sp='Spicymaker:BAAALAADCggIFgAAAA==.Spoils:BAAALAADCggIBwAAAA==.',St='Steviathan:BAAALAAECgMIAwAAAA==.Strifewood:BAAALAAECgIIAgAAAA==.Stumper:BAAALAAECgIIAwABLAAECgMIAwABAAAAAA==.Stórm:BAAALAADCgcIBwAAAA==.',Su='Suri:BAAALAAECgYICQAAAA==.',Sy='Sybrina:BAAALAADCggIEgAAAA==.',['Sí']='Síf:BAAALAADCgQIBAAAAA==.',['Sø']='Søurdough:BAAALAADCgIIAgAAAA==.',Ta='Talisa:BAAALAADCggIBwAAAA==.Tanleros:BAAALAADCggIDQAAAA==.',Te='Tealeth:BAAALAAECgMIBwAAAA==.Telana:BAAALAADCgcICgAAAA==.Tequitos:BAAALAAECgEIAQAAAA==.Tessla:BAAALAADCgQIBAAAAA==.',Th='Thoriase:BAAALAAECgcIDgAAAA==.',To='Tonbó:BAAALAADCgcIFAAAAA==.Torag:BAAALAAECgEIAQAAAA==.Torment:BAAALAAECgMIAwAAAA==.Totemtugger:BAAALAADCgYIBgAAAA==.Totorö:BAAALAAECgYICwAAAA==.',Tr='Trapiana:BAAALAADCggIEAAAAA==.Trepania:BAABLAAECoEVAAIKAAgIahDfGwDHAQAKAAgIahDfGwDHAQAAAA==.Tristén:BAAALAAECgYIDgAAAA==.Trollycarp:BAAALAAECgEIAQAAAA==.',Tu='Tumbler:BAAALAAECgIIAgAAAA==.Tumni:BAAALAADCgcIBwAAAA==.',Ug='Uglychick:BAAALAAECgIIAgAAAA==.',Ul='Ulnuk:BAAALAAECggIEQAAAA==.',Un='Unaf:BAAALAAECgYICQAAAA==.Unholyshan:BAAALAADCgcICQABLAAECgIIAwABAAAAAA==.',Up='Uphellyaa:BAABLAAECoEVAAICAAgIhhyYDQC8AgACAAgIhhyYDQC8AgAAAA==.',Ur='Ursoc:BAAALAAECgIIAgAAAA==.',Va='Vadka:BAAALAADCggIDgAAAA==.Vaha:BAAALAAECgEIAQAAAA==.Vairian:BAAALAADCggIDwAAAA==.Vallamere:BAAALAAECgQIBgAAAA==.Valsavis:BAAALAADCggICAAAAA==.',Ve='Verulan:BAAALAADCgcIEgAAAA==.Veth:BAAALAAECgUICAAAAA==.Vexomous:BAAALAAECgEIAQAAAA==.',Vi='Vicy:BAAALAADCgcIDQABLAAECgIIAgABAAAAAA==.',Vo='Voidmayne:BAAALAAECgYICwAAAA==.Voker:BAAALAADCggICQAAAA==.Volandiir:BAAALAADCgEIAQABLAAECgcIFAAMADskAA==.Voltar:BAAALAADCggIFgAAAA==.Vonhelsing:BAAALAADCgcIFgAAAA==.',Vy='Vyolent:BAAALAADCgcIBwAAAA==.',Wa='Wayadra:BAAALAAECgYICwAAAA==.',We='Weiand:BAAALAAECgYICAAAAA==.',Wh='Whatami:BAAALAADCggIDgAAAA==.Why:BAAALAADCggIDgAAAA==.',Wi='Wilhellena:BAAALAAECgYIDAAAAA==.',Xa='Xalatath:BAAALAAECgYICQAAAA==.Xandir:BAAALAAECgIIAwAAAA==.Xarhunt:BAAALAAECgEIAQAAAA==.Xaric:BAAALAAECgUICQAAAA==.',Xk='Xkra:BAAALAADCgcIEwAAAA==.',Xp='Xpi:BAAALAAECgIIAwAAAA==.',Xs='Xsnuxsnu:BAAALAAECgMIBQAAAA==.',Xy='Xyal:BAAALAADCgYICQAAAA==.Xyp:BAAALAADCgEIAQABLAADCgcIEgABAAAAAA==.',Yi='Yiago:BAAALAAECgEIAQAAAA==.',Za='Zanlex:BAAALAADCgcIDwAAAA==.Zaxhdk:BAEALAAECgUIBQAAAA==.',Ze='Zendrov:BAAALAADCgEIAQABLAADCggICAABAAAAAA==.Zephyrion:BAAALAADCggIFgAAAA==.Zetsumae:BAAALAAECgMIBQAAAA==.',Zi='Zilvræ:BAAALAAECgYIDQAAAA==.Ziparoo:BAAALAAECgIIAwAAAA==.',Zo='Zoinx:BAAALAAECgcICwAAAA==.',Zr='Zraven:BAAALAAECgIIAgAAAA==.',Zu='Zuhichii:BAAALAADCgcIBwAAAA==.',Zy='Zyrvog:BAAALAADCggIEgAAAA==.',['Èr']='Èrís:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end