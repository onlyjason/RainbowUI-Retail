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
 local lookup = {'Druid-Restoration','Unknown-Unknown','Hunter-BeastMastery','Warlock-Destruction','Druid-Balance','Monk-Windwalker',}; local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Ababear:BAABLAAECoEUAAIBAAgI8xZtDQAoAgABAAgI8xZtDQAoAgAAAA==.',Ae='Aedaria:BAAALAAECgMIAwAAAA==.Aeira:BAAALAAECgYICgAAAA==.',Ag='Agakk:BAAALAAECgcIDwAAAA==.',Ai='Ai:BAAALAAECgMIBQAAAA==.Ainseley:BAAALAAECgIIAgAAAA==.',Ak='Ako:BAAALAAECgcIDgAAAA==.',Al='Albarius:BAAALAAECgEIAQAAAA==.Alestoria:BAAALAAECgUIBQAAAA==.Alliestrasza:BAAALAADCgYIBgAAAA==.Allimental:BAAALAADCgEIAQAAAA==.Allionys:BAAALAADCggIDwAAAA==.Aloris:BAAALAAECgMIBQAAAA==.',Am='Amilara:BAAALAAECgIIAgAAAA==.',An='Andinestiri:BAAALAAECgMIAwAAAA==.Andolastrasz:BAAALAAECgYICQAAAA==.Andoren:BAAALAADCgIIAgABLAAECgYICQACAAAAAA==.Anightsong:BAAALAADCgcICwAAAA==.Anthria:BAAALAADCgIIAgAAAA==.',Aq='Aquilla:BAABLAAECoEUAAIDAAgIThkIDwB6AgADAAgIThkIDwB6AgAAAA==.',Ar='Archenea:BAAALAAECgYICgAAAA==.Argord:BAAALAADCgcIDQAAAA==.Argorwal:BAAALAADCgQIBAAAAA==.Aroused:BAAALAAECgYIDAAAAA==.',As='Asterr:BAAALAAECgYICQAAAA==.Asukka:BAAALAAECgUICQABLAAECgcIDgACAAAAAA==.Asëya:BAAALAAECgYIBwAAAA==.',At='Attenborough:BAABLAAECoEUAAIDAAcIfCBVDQCRAgADAAcIfCBVDQCRAgAAAA==.',Au='Autumnl:BAAALAADCggIEgAAAA==.',Av='Avesa:BAAALAADCgcIGgAAAA==.',Ay='Ayurveda:BAAALAADCggICAAAAA==.',Az='Azanadra:BAAALAAECgYICQAAAA==.',Ba='Baptis:BAAALAAECgQICgAAAA==.Bazookabob:BAAALAADCgYIBgAAAA==.',Be='Bettarina:BAAALAADCgIIAgAAAA==.',Bf='Bfp:BAAALAAECgYICAAAAA==.',Bi='Bigbutter:BAAALAADCggIEAAAAA==.Bittydrood:BAAALAADCgYICQAAAA==.Bittylexis:BAAALAADCgcIEgAAAA==.',Bl='Blessica:BAAALAADCgcIDgAAAA==.Blèu:BAAALAAECgYICwAAAA==.',Bo='Bobspally:BAAALAAECgMIBAAAAA==.',Br='Breathe:BAAALAAECgYIBgAAAA==.Brewballs:BAAALAAECgMIBgAAAA==.Brundir:BAAALAADCgcICgAAAA==.',Bu='Bubbletea:BAAALAADCgIIAgAAAA==.Buff:BAAALAADCgEIAQAAAA==.Bulltwiggy:BAAALAAECgMIBgAAAA==.Bunnicula:BAAALAAECgUICAAAAA==.',Ca='Caelphia:BAAALAAECgMIBQAAAA==.',Ce='Ceeni:BAAALAAECgEIAQAAAA==.Celeana:BAABLAAECoEVAAIEAAgICRMXFgAMAgAEAAgICRMXFgAMAgAAAA==.Celencia:BAAALAADCggICAAAAA==.',Ch='Chakabad:BAAALAADCgcICgAAAA==.Chalgar:BAAALAADCggICAAAAA==.Cheetoe:BAAALAAECggIAgAAAA==.Chenahala:BAAALAADCgcICQAAAA==.Chibilune:BAAALAADCggIFwAAAA==.Chogh:BAAALAAECgUIBQAAAA==.',Cl='Classican:BAAALAADCgcIDAABLAADCgcIHAACAAAAAA==.Cloudburst:BAAALAAECgQIBwAAAA==.',Co='Conanascus:BAAALAAECgQIBgABLAAECgYICwACAAAAAA==.',Cr='Crazybuns:BAAALAAECgMIAwAAAA==.Crispysock:BAAALAAECgIIAgAAAA==.Crunchysock:BAAALAAECgIIAgAAAA==.',Cy='Cylndra:BAAALAADCgcIBwAAAA==.Cynderr:BAAALAAECgIIAgAAAA==.',Cz='Czarina:BAAALAAECgYICQAAAA==.',Da='Dagodeiwos:BAAALAADCgUIBQAAAA==.Daquilla:BAAALAAECgEIAQAAAA==.Darknara:BAAALAAECgcIDAAAAA==.Darkterror:BAAALAADCgcIDAAAAA==.Darkzy:BAAALAAECgYIDAAAAA==.Dawni:BAAALAAECgUIBgAAAA==.',De='Deathjeff:BAAALAAECgMIBgAAAA==.Deathsgates:BAAALAAECgYICwAAAA==.Decasia:BAAALAAECgMIBAAAAA==.Dewy:BAAALAADCgEIAQAAAA==.Dezzyy:BAAALAAECgQIBwAAAA==.',Dh='Dhfig:BAAALAADCgMIAwAAAA==.',Di='Dinoll:BAAALAADCggICQAAAA==.Divinehëll:BAAALAADCgIIAgABLAADCggICAACAAAAAA==.',Do='Doodoopal:BAAALAAECgQIBwAAAA==.',Dr='Draconaught:BAAALAADCgEIAQAAAA==.Draksvoid:BAAALAAECgYICgAAAA==.Dranlu:BAAALAADCgQIBAAAAA==.Dranog:BAAALAADCggIHAAAAA==.Drekkara:BAAALAADCgQIBAAAAA==.Drolow:BAAALAADCgEIAQAAAA==.Dromarhun:BAAALAADCgcIBwAAAA==.Druidbod:BAEALAAECgEIAQABLAAECggIFAABAJ4ZAA==.',Du='Duckwurth:BAAALAAECgYIBwAAAA==.Durga:BAAALAAECgMIBAAAAA==.Duuid:BAAALAADCgcIBwABLAAECgYICQACAAAAAA==.',['Dâ']='Dâññy:BAAALAADCggIEAAAAA==.',Ea='Earthesance:BAAALAADCggIGAAAAA==.',Eb='Ebeb:BAAALAAECgYICgAAAA==.',El='Eleanne:BAAALAAECgQIBAAAAA==.Ellebasi:BAAALAAECgMIBwAAAA==.Elzorro:BAAALAAECgMIBQAAAA==.',En='Enazen:BAAALAAECgIIAgAAAA==.',Er='Erui:BAAALAADCgcIDAAAAA==.',Es='Escanor:BAAALAAECgIIAgAAAA==.Essabrie:BAAALAAECgMIBAAAAA==.',Ev='Evilherb:BAAALAADCgYIBgAAAA==.Evilrayne:BAAALAAECgYICgAAAA==.Evoxus:BAAALAAECgIIAgAAAA==.',Fa='Fatherfingur:BAAALAADCgcIDwAAAA==.Fauxpas:BAAALAADCggIDwAAAA==.Fauxy:BAAALAAECgIIAgABLAADCgUIBQACAAAAAA==.Fawnzy:BAAALAAECgUIBQAAAA==.',Fc='Fckingdiabla:BAAALAAECgIIAgAAAA==.',Fe='Feralfur:BAAALAAECgMIBQAAAA==.Feredir:BAAALAAECgIIAgAAAA==.',Fi='Firebringer:BAAALAAECgYICwAAAA==.Fishee:BAAALAADCgcIBwAAAA==.Fistandilius:BAAALAADCggIDwAAAA==.',Fo='Forgery:BAAALAADCggIDwAAAA==.Forvaaka:BAAALAAECgIIAgAAAA==.Foshnu:BAAALAAECgMIAwABLAAECgMIAwACAAAAAA==.',Fr='Frankgrim:BAAALAAECgEIAQAAAA==.Frostman:BAAALAAECgUICQAAAA==.Frostymage:BAAALAADCgcIDgAAAA==.Frostyoxy:BAAALAADCgcIBwAAAA==.',Fu='Fujie:BAAALAAECgcIBwAAAA==.Furryfury:BAAALAADCgYIBgAAAA==.Fuzzyshammy:BAAALAADCgcIBwAAAA==.',['Fé']='Fée:BAAALAADCgcIDQAAAA==.',Ga='Garag:BAAALAADCggICQAAAA==.Garlstedt:BAAALAADCgcIEAAAAA==.',Ge='Gengar:BAAALAAECgIIAgABLAAECgUICAACAAAAAA==.George:BAAALAAECgIIBAAAAA==.',Gh='Ghulrokk:BAAALAADCgQIBAAAAA==.',Gi='Gilidan:BAAALAAECgEIAQAAAA==.',Gl='Gluum:BAAALAADCgcIDAAAAA==.',Go='Gobo:BAAALAADCgYIBgAAAA==.Gohi:BAAALAAECgIIAgAAAA==.Gossamerfeet:BAAALAAECgMIBAAAAA==.',Gr='Graceosilver:BAAALAADCggIFwAAAA==.Gregnor:BAAALAAECgYICAAAAA==.Grizzlyadams:BAAALAAECgEIAQAAAA==.Grumpybunbun:BAAALAAECgUICAAAAA==.',Gu='Guldrosi:BAAALAAECgYICAAAAA==.Gummitrix:BAAALAADCgYIBgAAAA==.',['Gå']='Gårrus:BAAALAAECgYICQAAAA==.',Ha='Haarl:BAAALAADCgcIDAAAAA==.Hairysquater:BAAALAAECgMIAwAAAA==.Hallie:BAAALAADCggIDwAAAA==.Harlu:BAAALAAECgYICgAAAA==.Hartbroke:BAAALAAECgYICQAAAA==.',He='Healsdruids:BAAALAADCgMIAwAAAA==.Helbourne:BAAALAADCggIDwAAAA==.',Hi='Highskillcap:BAAALAAECgEIAQAAAA==.',Ho='Holfor:BAAALAADCgIIAgAAAA==.Holliestraza:BAAALAAECgYICQAAAA==.',Hw='Hwanwok:BAAALAADCggIDwAAAA==.',Ig='Ignited:BAAALAAECgIIAgAAAA==.',Im='Imadragon:BAAALAAECgMIBAAAAA==.Imdeadguy:BAAALAAECgUICAAAAA==.Imhard:BAAALAAECgMIBAAAAA==.',Ja='Jacestar:BAAALAAECgIIAgAAAA==.Jacquelynn:BAAALAAECgMIAwAAAA==.Jadealock:BAAALAAECgMIBAAAAA==.Jaldazja:BAAALAADCgcIDgAAAA==.Janinoo:BAAALAAECgMIBgAAAA==.Jazlee:BAAALAAECgEIAQAAAA==.',Je='Jefflock:BAAALAAECgIIAgAAAA==.Jegyan:BAAALAADCggIFQAAAA==.',Ji='Jinathy:BAAALAAECgYICgAAAA==.',Jo='Jolyñ:BAAALAAECgQIBgABLAAECgUICAACAAAAAA==.Joroma:BAAALAADCggIFgAAAA==.',Js='Jsttrons:BAAALAADCgMIAwAAAA==.',Ju='Justdrood:BAAALAAECgMIBQAAAA==.Juulripz:BAAALAADCgUICgAAAA==.',Ka='Kagna:BAAALAADCgYIDAAAAA==.Kaldonor:BAAALAAECgYICQAAAA==.Kalenia:BAAALAADCggICAAAAA==.Kalvayre:BAAALAAECgYICQAAAA==.Karaha:BAAALAADCgMIAwAAAA==.Kareshka:BAAALAAECgYIBgAAAA==.Karpana:BAEALAAECgUICAAAAA==.Kashir:BAAALAAECgMIBQAAAA==.Kashira:BAAALAADCggICwAAAA==.Kaylys:BAAALAAECgEIAQAAAA==.Kazender:BAAALAADCggIFQAAAA==.Kazimirah:BAAALAADCggICgAAAA==.',Ke='Kellogin:BAAALAADCggIDQAAAA==.Keloha:BAAALAAECgMIAwAAAA==.',Kh='Khaind:BAAALAADCgYICwABLAAECgMIBQACAAAAAA==.',Ki='Kiamei:BAAALAAECgYICQAAAA==.Kittykitty:BAAALAAECgUIBwAAAA==.',Ko='Kollared:BAAALAADCgcIDAAAAA==.Kolzane:BAABLAAECoEbAAIDAAgI4CXQAQBZAwADAAgI4CXQAQBZAwAAAA==.',Kr='Krandel:BAAALAAECgUICAAAAA==.Krezz:BAAALAADCggIDwAAAA==.Kriegnash:BAAALAADCgcICQAAAA==.',Ky='Kyth:BAAALAAECgcIDAAAAA==.Kythera:BAAALAAECgIIAwABLAAECgcIDAACAAAAAA==.',['Kø']='Køda:BAAALAAECgYICgAAAA==.',La='Laceylightz:BAAALAAECgIIAgAAAA==.Lariael:BAAALAAECgYICwAAAA==.',Le='Legibly:BAAALAAECgMIBAAAAA==.',Li='Lilpawpaw:BAAALAAECgIIAgAAAA==.Linadrala:BAAALAADCgQIBAAAAA==.Littlehell:BAAALAAECgYICwAAAA==.Lizzie:BAAALAADCgEIAQAAAA==.',Lo='Lokaroki:BAAALAAECgMIAwAAAA==.Lorethane:BAAALAADCggIFQAAAA==.',Lu='Luclangevin:BAAALAAECgEIAQAAAA==.Luda:BAAALAAECgMIBgAAAA==.Ludabebe:BAAALAAECgIIAgAAAA==.Lunamoonclaw:BAAALAAECgMIBAAAAA==.',Ly='Lyllith:BAAALAADCgUIBQAAAA==.Lyzoldas:BAAALAAECgMIBgAAAA==.',['Lö']='Löwryder:BAAALAADCggIFgAAAA==.',Ma='Maemura:BAAALAAECgIIAgAAAA==.Maiyora:BAAALAADCgYIBgAAAA==.Malchromatus:BAAALAAECgEIAQAAAA==.Mankey:BAAALAADCgcIBwAAAA==.Marcosio:BAAALAADCgcIEAAAAA==.Marsala:BAABLAAECoEUAAIFAAcIDBEPGQDBAQAFAAcIDBEPGQDBAQAAAA==.Mayael:BAAALAAECgIIAgAAAA==.Maylater:BAAALAADCgUIBQAAAA==.',Mc='Mcdavid:BAAALAADCgMIAwAAAA==.',Me='Me:BAAALAAECgUIBgAAAA==.Mearkman:BAAALAADCggIFQAAAA==.Meatyfajita:BAAALAAECgYICgAAAA==.Medousa:BAAALAAECgUICAAAAA==.Megaera:BAAALAAECgIIAgAAAA==.Meladie:BAAALAAECgMIBAAAAA==.Mellene:BAAALAAECgYICgAAAA==.Mememagician:BAAALAAECgYICwAAAA==.Merlhyna:BAAALAADCgYIBgAAAA==.Merlinthos:BAAALAADCgYIBwABLAAECgYICwACAAAAAA==.Metaljack:BAAALAAECgYICAAAAA==.',Mi='Miasoku:BAAALAAECgUIBQAAAA==.Mishaweha:BAAALAAECgMIBgAAAA==.Misohangry:BAAALAADCgIIAgAAAA==.Mitama:BAAALAAECgcICwAAAA==.',Mo='Modar:BAAALAAECgYIDgAAAA==.Monkas:BAAALAAECgcIDwAAAA==.Mooveit:BAAALAAECgIIAwAAAA==.Mornanden:BAAALAADCgYIBAAAAA==.Mousehouse:BAAALAAECgUICAAAAA==.',Na='Nasdarke:BAAALAAECgMIBAAAAA==.',Ne='Nepheleah:BAAALAAECgYICwAAAA==.Nesmoth:BAAALAAECgYICAAAAA==.',Ni='Niiborracho:BAAALAAECgcIDAAAAA==.Niisera:BAAALAADCggIBwAAAA==.',No='Norntrox:BAAALAAECgYICgAAAA==.Nosa:BAAALAADCggICAAAAA==.',Ob='Obyn:BAAALAADCgcIBwAAAA==.',Ol='Oldmaned:BAAALAADCgcIDgAAAA==.',Ow='Owlsonatotem:BAAALAAECgYICAAAAA==.',Ox='Oxymage:BAAALAADCgcIBwAAAA==.',Pa='Pakno:BAAALAAECgUICAAAAA==.Pandook:BAAALAAECgYIBgAAAA==.Pathojenic:BAAALAADCggIDgABLAAECgMIAwACAAAAAA==.',Ph='Phonominal:BAAALAAECggIBgAAAA==.Phumanchop:BAAALAADCggIFgAAAA==.',Pr='Praystâtion:BAAALAADCgcIBwAAAA==.Preacherheal:BAAALAAECgMIBQAAAA==.',Pu='Puramalum:BAAALAADCgcIBwAAAA==.',['Pé']='Péach:BAAALAADCgcIDQAAAA==.',Qo='Qorban:BAAALAAECgIIAgAAAA==.',Qw='Qwackin:BAAALAADCggICAAAAA==.',Ra='Rasriann:BAAALAAECgMIAwAAAA==.Rata:BAAALAAECgEIAQAAAA==.Ratana:BAAALAADCgYIBgAAAA==.',Re='Redrider:BAAALAAECgIIAgAAAA==.Reeality:BAAALAAECgUICAAAAA==.Rekha:BAAALAAECgcIDAAAAA==.Rekkora:BAAALAAECgEIAgAAAA==.Remake:BAAALAAECgYICwAAAA==.',Ri='Ridemytotem:BAAALAAECgMIAwAAAA==.',Ro='Rockfish:BAAALAADCgYIBgAAAA==.Rottin:BAAALAADCggICAAAAA==.',Ru='Ruroni:BAAALAADCgcIDAAAAA==.',Ry='Ryanabxy:BAAALAADCgYIBgAAAA==.Rylandros:BAAALAADCggICQAAAA==.Ryniel:BAAALAADCggIFwAAAA==.',['Rø']='Røse:BAAALAAECgMIBQAAAA==.',Sa='Saika:BAAALAADCggIFQAAAA==.Sanasta:BAAALAADCggIFwAAAA==.Sandspur:BAAALAADCgUIBQAAAA==.Sanielin:BAAALAAECgYICgAAAA==.Saramoon:BAAALAADCgcICwAAAA==.Sarkaney:BAAALAADCgEIAQAAAA==.Sashchi:BAAALAAECgMIBgAAAA==.',Sc='Schanks:BAAALAAECgMIAwAAAA==.',Se='Sehmet:BAAALAADCggIFQAAAA==.Seliria:BAAALAAECgYICAAAAA==.Sephaman:BAAALAAECgMIBAAAAA==.Set:BAAALAAECgYICAAAAA==.',Sh='Shadoezz:BAAALAADCgcIDQAAAA==.Shayle:BAAALAADCgIIAgABLAAECgMIAwACAAAAAA==.Shazrra:BAAALAADCgcIBwAAAA==.Sheani:BAAALAAECgMIAwAAAA==.Shköll:BAAALAADCggIDwAAAA==.Shong:BAAALAAECgYICQAAAA==.Shotfoot:BAAALAADCggIDgAAAA==.Shurdy:BAAALAAECgYICAAAAA==.Shwang:BAAALAAECgYICgAAAA==.',Si='Sicshammy:BAAALAADCgYICQAAAA==.Sigmar:BAAALAAECgMIAwAAAA==.Sijan:BAAALAAECgYIBgAAAA==.Silentio:BAAALAAECgYICwAAAA==.Sinofwrath:BAAALAAECgYICQAAAA==.Sinsaurus:BAAALAADCggICAAAAA==.Sinsidious:BAAALAADCggIDwAAAA==.Siwin:BAEBLAAECoEUAAMBAAgInhloDAA2AgABAAgInhloDAA2AgAFAAMIxx5DLgDxAAAAAA==.',Sl='Slamfrost:BAAALAADCggICAAAAA==.Slapchóp:BAAALAAECgYICAAAAA==.',Sm='Smoko:BAAALAAECgUICAAAAA==.',Sn='Sneakyduubb:BAAALAAECgYICQAAAA==.Snoopÿ:BAAALAADCgcIBwAAAA==.Snowxstorm:BAAALAAECgYICAAAAA==.',So='Solrare:BAAALAAECggIDAAAAA==.',Sp='Spekktrum:BAAALAADCggIFQAAAA==.Spoom:BAAALAADCgcIDAAAAA==.',St='Stainedtoo:BAAALAADCggIDwAAAA==.Staqua:BAAALAADCggIFQAAAA==.Stateomatter:BAAALAAECgMIBQAAAA==.Stimpak:BAAALAADCgcIBwAAAA==.Streamesance:BAAALAADCgEIAQAAAA==.',Su='Summdari:BAAALAAECgIIAgAAAA==.Summrot:BAAALAAECgMIBgAAAA==.',Sy='Sylkaanto:BAAALAAECgMIBAAAAA==.Sylvalesta:BAAALAADCggIFQAAAA==.',Ta='Talyon:BAAALAADCggIDQAAAA==.Tatertotem:BAAALAAECgMICAAAAA==.',Te='Teal:BAAALAAECgYIDgAAAA==.Tekeelà:BAAALAAECgMIBgAAAA==.Telrondis:BAAALAAECgMIAwAAAA==.Tepaartos:BAAALAADCggICgAAAA==.',Th='Thalstrasza:BAAALAADCggIEwAAAA==.The:BAAALAADCggIFwAAAA==.Thiara:BAAALAADCggIDwABLAAECgYICwACAAAAAA==.Thiccychiccy:BAAALAAECgYIBgAAAA==.Thumadre:BAAALAADCggICAAAAA==.Thundrfury:BAAALAADCgcICgAAAA==.',Ti='Tibbles:BAAALAADCggIFwAAAA==.Tietus:BAAALAAECgMIBAAAAA==.Tinka:BAAALAADCgYIBgAAAA==.',To='Tokra:BAAALAAECggICAAAAA==.Totallyadrag:BAAALAAECgEIAQAAAA==.Totempull:BAAALAADCgcIDQAAAA==.',Tr='Treeko:BAAALAADCgUIBQAAAA==.Treston:BAAALAADCgcIDwAAAA==.Tristanthia:BAAALAAECgcIDAAAAA==.Trollii:BAAALAADCgYIBgAAAA==.',Tw='Twatters:BAAALAADCggIDwAAAA==.',Ty='Tybs:BAAALAAECggIBgAAAA==.',Ul='Uldric:BAAALAADCggIDwAAAA==.',Un='Undeaddude:BAAALAADCggICAAAAA==.Undeadziggy:BAAALAAECgEIAQAAAA==.Unslayable:BAAALAADCggIDwAAAA==.',Va='Valereux:BAAALAADCgcIDQAAAA==.Vassago:BAAALAAECgEIAQAAAA==.',Ve='Veggy:BAAALAADCgYICAAAAA==.Veldorie:BAAALAADCgUIBQAAAA==.Veranox:BAAALAAECgMIBgAAAA==.Verbera:BAAALAAECgUICAAAAA==.Verrenth:BAAALAADCggIDgAAAA==.',Vi='Vigol:BAAALAAECgMIBQAAAA==.Villain:BAAALAAECgUIBwAAAA==.Vinton:BAAALAADCggICQAAAA==.',Vo='Voldemort:BAAALAADCgQIBQAAAA==.Volini:BAAALAADCgcIBwABLAAECgMIAwACAAAAAA==.',Wa='Waabakwa:BAAALAAECgMIAwAAAA==.Wabisabi:BAAALAAECgYICwAAAA==.Wakenbake:BAABLAAECoEYAAIGAAcI9CTVAwDeAgAGAAcI9CTVAwDeAgAAAA==.Warbot:BAAALAADCgcIBwAAAA==.',We='Wetrag:BAAALAADCgcIHAAAAA==.',Wi='Wickedsmaht:BAAALAAECgUICAABLAADCgUIBQACAAAAAA==.Widget:BAAALAADCgQIBAAAAA==.Widowghast:BAAALAAECgcICwAAAA==.Wilford:BAAALAADCggIDwAAAA==.Wiz:BAAALAAECgUICAAAAA==.',Wo='Woggers:BAAALAAECgMIAwAAAA==.',Xa='Xanarin:BAAALAADCgYIBgAAAA==.Xanda:BAAALAAECgYICAABLAAECgYICwACAAAAAA==.Xansus:BAAALAAECgMIAwABLAAECgYICwACAAAAAA==.',Xi='Xinyan:BAAALAAECgMIBAAAAA==.',Xo='Xobos:BAAALAADCgcICwAAAA==.',Xp='Xpdvaedir:BAAALAAECgcIDQAAAA==.',Xu='Xuxo:BAAALAADCgUIBQAAAA==.',Yo='Youcantseeme:BAAALAAECgEIAQAAAA==.',Za='Zabo:BAAALAADCgYIBgAAAA==.Zaco:BAAALAAECgMIAwAAAA==.Zae:BAAALAADCgYICwAAAA==.Zarikas:BAAALAAECgEIAQAAAA==.Zata:BAAALAAECgIIAgAAAA==.Zazabeast:BAAALAADCgcIBwAAAA==.Zazafrost:BAAALAADCgcICAAAAA==.',Ze='Zekken:BAAALAADCggICQAAAA==.',Zi='Zinovia:BAAALAAECgcICgAAAA==.Ziwei:BAAALAAECgMIBAAAAA==.',Zo='Zookee:BAAALAAECgYICAAAAA==.Zookidan:BAAALAADCgcIFAAAAA==.',['Øp']='Øphiücus:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end