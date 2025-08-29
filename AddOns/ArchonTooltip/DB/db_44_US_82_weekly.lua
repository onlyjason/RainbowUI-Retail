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
 local lookup = {'Unknown-Unknown',}; local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abrigus:BAAALAAECgMIAwAAAA==.',Ac='Acanthel:BAAALAADCgQIBQAAAA==.',Ad='Adhira:BAAALAADCgcICgAAAA==.',Ae='Aedrias:BAAALAAECgEIAQAAAA==.Aegennai:BAAALAAECgIIAwAAAA==.Aegon:BAAALAAECggIEgAAAA==.Aelirie:BAAALAADCgEIAQABLAAECgEIAQABAAAAAA==.Aerine:BAAALAADCgcIBwAAAA==.Aevaela:BAAALAAECgYICQAAAA==.',Ag='Agilaz:BAAALAAECgMIBAAAAA==.Agravain:BAAALAAECgIIAgAAAA==.',Ak='Akey:BAAALAADCggIDwAAAQ==.Akhae:BAAALAAECgYIBgAAAA==.',Al='Albinism:BAAALAADCggIDgAAAA==.Algernon:BAAALAADCgYICgAAAA==.',An='Anaeda:BAAALAAECgMIBQAAAA==.Anakin:BAAALAADCgcICgAAAA==.Andrömëdä:BAAALAAECggICAAAAA==.Anistasia:BAAALAADCggIDAAAAA==.Antarrez:BAAALAAECgMIAwAAAA==.Anthmahr:BAAALAADCgEIAQAAAA==.Anubisre:BAAALAADCggIEgAAAA==.',Ap='Apostolo:BAAALAAECgcIDwAAAA==.',Aq='Aquateal:BAAALAADCgMICAAAAA==.Aquindra:BAAALAADCgcICwAAAA==.',As='Ashvyr:BAAALAAECgMIAwAAAA==.',Ba='Backoff:BAAALAADCggICAAAAA==.Baeyik:BAAALAADCggIDgAAAA==.Baldpunch:BAAALAADCgMIBAAAAA==.Barnabus:BAAALAAECgEIAQAAAA==.',Be='Beachbecrazy:BAAALAAECgMIAwAAAA==.Beanplant:BAAALAAECgMIBQAAAA==.',Bi='Bigmonk:BAAALAAECgYIDAAAAA==.Bilac:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Binxy:BAAALAAECgEIAQAAAA==.',Bl='Bloodsharp:BAAALAAECgEIAQAAAA==.',Bo='Borimius:BAAALAADCggIDwAAAA==.Boston:BAAALAADCgMIAwAAAA==.',Br='Brewtholomew:BAAALAAECgEIAQAAAA==.Briggsey:BAAALAAECgMIBQAAAA==.Briznot:BAAALAADCgcIEAAAAA==.Brodysseus:BAAALAAECgIIAgAAAA==.Brounee:BAAALAAECgYIBgAAAA==.Brownycake:BAAALAADCggICwAAAA==.Brownytank:BAAALAADCgEIAQAAAA==.Bryce:BAAALAAECgMIAwAAAA==.Brèanna:BAAALAADCgYIBwAAAA==.',Bu='Burningwolf:BAAALAAECgMIBQAAAA==.',Ca='Catbrin:BAAALAAECgMIAwAAAA==.Cattiegazer:BAAALAAECgMIBQAAAA==.Cayssabria:BAAALAAECgMIAwAAAA==.',Ce='Celáena:BAAALAAECgYICQAAAA==.',Ch='Chapslop:BAAALAADCggICAAAAA==.Christopher:BAAALAAECgYIBgAAAA==.Chulip:BAAALAAECgIIAgABLAAECgYIBwABAAAAAA==.',Cl='Cloudbreaker:BAAALAAECgIIAgAAAA==.',Co='Cobue:BAAALAADCgQIBAAAAA==.',Cz='Cztalone:BAAALAAECgMIAwAAAA==.',['Cè']='Cèlane:BAAALAAECgYICQAAAA==.',Da='Daewulf:BAAALAAECgEIAQAAAA==.Damitsu:BAEALAAECgMIAwAAAA==.Darkdeath:BAAALAADCgYIBwAAAA==.Darnaya:BAAALAADCgUIBQAAAA==.Darquin:BAAALAAECgYICgAAAA==.Datemike:BAAALAADCgUIBQAAAA==.Dazen:BAAALAADCgYIBwAAAA==.',De='Deathberry:BAAALAAECgEIAgAAAA==.Deathdoodles:BAAALAAECgYIBgAAAA==.Deekan:BAAALAAECgMIAwAAAA==.Dejavù:BAAALAAECgMIBAAAAA==.Deräth:BAAALAADCggIDwAAAA==.Destrobear:BAAALAAECgYIBQAAAA==.Dethraiser:BAAALAADCggICAAAAA==.',Df='Dfresh:BAAALAAECgIIAwAAAA==.',Dh='Dhdawg:BAAALAADCgcICgAAAA==.',Di='Dittshicker:BAAALAADCggIFwAAAA==.Diviinity:BAAALAADCggIDwAAAA==.',Do='Dodgeramthis:BAAALAADCgYIBgAAAA==.Donar:BAAALAADCgYIBgAAAA==.',Dr='Dragondude:BAAALAAECgMIAwAAAA==.Drfeelbad:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',Du='Durango:BAAALAAECgIIAgAAAA==.Dustyshafts:BAAALAAECgYIBAAAAA==.',Dy='Dyelin:BAAALAAECgMIAwAAAA==.',['Dà']='Dàddy:BAAALAAECgMIAwAAAA==.',El='Eldacar:BAAALAADCggIDwAAAA==.Elisia:BAAALAADCgUIBQAAAA==.Elyron:BAAALAAECgMIAwAAAA==.',En='Enaid:BAAALAADCggICAAAAA==.',Et='Ethelwulf:BAAALAADCgcIBwAAAA==.',Ev='Evilorc:BAAALAADCgEIAQAAAA==.Evozker:BAAALAADCgcICgAAAA==.',Ex='Exerphus:BAAALAADCgUICgAAAA==.Extinguish:BAAALAADCggICAAAAA==.',Ey='Eyeofdabeast:BAAALAAECgMIBgAAAA==.',Ez='Ezkriel:BAAALAAECgMIAwAAAA==.',Fa='Fakename:BAAALAAECgMIAwAAAA==.Fakesaint:BAAALAAECgQIBQAAAA==.Falcore:BAAALAADCggIDgAAAA==.Fanaris:BAAALAADCggIEAAAAA==.Fangstorm:BAAALAAECgMIAwAAAA==.Farorê:BAAALAADCggICwAAAA==.Fazz:BAAALAAECgMIBAAAAA==.',Fe='Felbladerip:BAAALAADCgcIDgAAAA==.Felica:BAAALAAECgYIBgAAAA==.',Fl='Flexecute:BAAALAADCggIEgAAAA==.Florencia:BAAALAADCgcIDgAAAA==.',Fo='Fondera:BAAALAADCgcIAwAAAA==.Fordwin:BAAALAADCggIDwAAAA==.',Fr='Fritopaws:BAAALAAECgMIAwAAAA==.',Ga='Gael:BAAALAADCggICgAAAA==.',Gi='Gideòn:BAAALAAECgEIAQAAAA==.',Gl='Glard:BAAALAADCgEIAQAAAA==.',Go='Goodbye:BAAALAAECgMIBgAAAA==.Gospel:BAAALAADCggICAAAAA==.',Gr='Greatchez:BAAALAAECgQICQAAAA==.Grimlox:BAAALAADCgYIBgAAAA==.',Gu='Gudge:BAAALAAECgMIAwAAAA==.Gummypenguin:BAAALAADCggICAAAAA==.',['Gô']='Gôd:BAAALAADCggIDwABLAAECgYIBgABAAAAAA==.',Ha='Hadhox:BAAALAAECgQIBAAAAA==.Harbiin:BAAALAADCggICwAAAA==.Hazelnoot:BAAALAAECgYICQAAAA==.',He='Hexcist:BAAALAAECgEIAQAAAA==.',Ho='Hokogo:BAAALAAECgYICAAAAA==.Hollyanne:BAAALAAECgIIAgAAAA==.Holymilk:BAAALAADCgMIAwAAAA==.Hoonicorn:BAAALAAECgMIBAAAAA==.',Hy='Hyades:BAAALAAECgIIAgAAAA==.',Im='Imporor:BAAALAADCgMIAwAAAA==.',In='Inkwell:BAAALAAECgQICwAAAA==.Innexboomer:BAAALAADCggICQAAAA==.Insaint:BAAALAAECgYICwAAAA==.',Ir='Ironfield:BAAALAAECgEIAQAAAA==.',Ja='Jaballsags:BAAALAAECgcIDQAAAA==.',Je='Jeggred:BAAALAADCgUIBQAAAA==.Jessamine:BAAALAAECgYICQAAAA==.Jetta:BAAALAADCggIDgAAAA==.Jezzak:BAAALAAECgMIBAAAAA==.',Jo='Jorien:BAAALAADCgUIBQAAAA==.',Jp='Jpd:BAAALAAECgEIAQAAAA==.',Ka='Kabage:BAAALAADCggIEAAAAA==.Kaboonsky:BAAALAAECgYICgAAAA==.Kaetlyn:BAAALAADCggIDgAAAA==.Kambriya:BAAALAADCggICAAAAA==.Kamikori:BAAALAAECgMIBQAAAA==.Karagtar:BAAALAAECgEIAQAAAA==.Karnadaz:BAAALAADCggICAAAAA==.Kavorcian:BAAALAAECgQIBgAAAA==.',Ki='Kilanor:BAAALAAECgQIBAAAAA==.Killerpluto:BAAALAAECggIDwAAAA==.Kiplet:BAAALAAECgYIBwAAAA==.',Ko='Korxana:BAAALAADCgMIAwAAAA==.Korxon:BAAALAAECgIIAgAAAA==.Kotus:BAAALAAECgMIBQAAAA==.',Kr='Krastikon:BAAALAADCgcIBwAAAA==.',Ks='Ksyusha:BAAALAADCggIDAAAAA==.',Ku='Kungpu:BAAALAADCggIDAAAAA==.',La='Lammi:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.Lamunio:BAAALAAECgMIBAAAAA==.Lanaria:BAAALAADCgQIAwAAAA==.Lasagne:BAAALAADCggICAAAAA==.Lashà:BAAALAAECgIIAgAAAA==.',Le='Legitpoopoo:BAAALAAECgMIAwAAAA==.Lethalbimbo:BAAALAADCgYIBwAAAA==.Letsummon:BAAALAAECgMIBQAAAA==.',Li='Likhan:BAAALAADCggICAAAAA==.',Lu='Ludwig:BAAALAADCgIIAgAAAA==.',Ma='Madsharona:BAAALAAECgYIDAAAAA==.Markos:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Martlok:BAAALAADCgcIBwAAAA==.Mathdebater:BAAALAADCgcIBwAAAA==.Mavangeria:BAAALAADCgMIBAAAAA==.Mazik:BAAALAADCggIBwAAAA==.',Mc='Mcbrynhammer:BAAALAADCgcIEQAAAA==.',Me='Metho:BAAALAADCgcIBwAAAA==.',Mi='Micflinigan:BAAALAADCggIEgAAAA==.Mishelö:BAAALAADCgUIBgAAAA==.Missingno:BAAALAADCgYIBgAAAA==.Mistrixx:BAAALAADCgMIAwAAAA==.',Mo='Moofosa:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.Moonshae:BAAALAAECgYICQAAAA==.Mooshaman:BAAALAAECgYIDQAAAA==.Moovanish:BAAALAAECgMIBQAAAA==.Morninvoodoo:BAAALAAECgEIAQAAAA==.',['Mó']='Mórganá:BAAALAADCgIIAgAAAA==.',Na='Naithin:BAAALAADCgEIAQAAAA==.Nalarah:BAAALAADCggICAAAAA==.Natur:BAAALAADCggICAAAAA==.',Ne='Nezal:BAAALAADCgYIBgAAAA==.',Ni='Nishaya:BAAALAAECgEIAQAAAA==.',No='Nootbricks:BAAALAAECgIIAwABLAAECgYICQABAAAAAA==.Noriisa:BAAALAAECgMIAwABLAAECgMIBAABAAAAAA==.Noril:BAAALAAECgMIBAAAAA==.',Ob='Obie:BAAALAAECgMIAwAAAA==.Obtuse:BAAALAAECgEIAQAAAA==.',Od='Odinhand:BAAALAAECgYICQAAAA==.',Om='Omgz:BAAALAADCggICAAAAA==.',Or='Oronoc:BAAALAAECgMIBQAAAA==.',Pa='Panduh:BAAALAAECgcIEAAAAA==.Pandóra:BAAALAADCgcICwAAAA==.Pariousa:BAAALAAECgEIAQAAAA==.',Pe='Perla:BAAALAADCgcIDAAAAA==.',Ph='Phalock:BAAALAADCgQIBAAAAA==.',Pi='Picklelicker:BAAALAAECgYIDgAAAA==.Pinkeepink:BAAALAADCggIDAAAAA==.Pinkfu:BAAALAAECgYICQAAAA==.',Pl='Plaguedheals:BAAALAADCgcIDgAAAA==.',Po='Polox:BAAALAADCgEIAQAAAA==.',Pr='Praeforprocs:BAAALAADCggICAAAAA==.',['Pë']='Përses:BAAALAADCggICQAAAA==.',Ra='Radîance:BAAALAAECgMIAwAAAA==.Ragefull:BAAALAADCgcIBwAAAA==.Rakurge:BAAALAAECgYIBgAAAA==.Ralganor:BAAALAAECgYICQAAAA==.Raynfists:BAAALAAECgEIAQAAAA==.',Rh='Rhyzzy:BAAALAADCgEIAQAAAA==.',Ri='Rina:BAAALAAFFAIIAgAAAA==.',Ro='Roflwafllol:BAAALAADCgcIBwAAAA==.',Ry='Rydia:BAAALAADCgQIBAAAAA==.',Sa='Sabelana:BAAALAADCgQIBAAAAA==.Sacamano:BAAALAADCgcIDgAAAA==.Sarazah:BAAALAAECgcIBwAAAA==.Satuno:BAAALAADCgcICAAAAA==.',Sc='Scribs:BAAALAADCgcIDQAAAA==.',Se='Seasalt:BAAALAADCggICAAAAA==.Selineda:BAAALAAECggIBAAAAA==.Serein:BAAALAAECgMIAwAAAA==.Severànce:BAAALAAECgMIBAAAAA==.',Sh='Shablammy:BAAALAAECgMIBQAAAA==.Shadowolves:BAAALAADCgEIAQAAAA==.Shifty:BAAALAADCgcIBwAAAA==.',Sk='Skarbrand:BAAALAAECgMIAwAAAA==.Skinnier:BAAALAADCgIIAgAAAA==.Skullbad:BAAALAADCgMIBAAAAA==.',Sn='Snorp:BAAALAADCgQIBAAAAA==.',So='Solarbubble:BAAALAAECgMIAwAAAA==.',St='Stout:BAAALAADCggICAAAAA==.',Su='Sul:BAAALAAECgYICAAAAA==.Sums:BAAALAAECgEIAQAAAA==.',Ta='Taurasst:BAAALAADCgcIBwABLAAECgYIDQABAAAAAA==.Taurasthunt:BAAALAAECgYIDQAAAA==.Tazerface:BAAALAADCgMIAwAAAA==.Tazllidan:BAAALAADCggICAAAAA==.',Te='Teetau:BAAALAAECgMIAwAAAA==.',Th='Thadrethresh:BAAALAAECgMIAwAAAA==.Thander:BAAALAADCgcIDgAAAA==.Thedarkskull:BAAALAADCgMIBQAAAA==.Thehardsock:BAAALAADCgcICwAAAA==.',Ti='Tif:BAAALAAECgQIBwAAAA==.Tiffy:BAAALAADCgMICAAAAA==.Tirnotham:BAAALAADCggIDwAAAA==.',Tm='Tmtglizzy:BAAALAAECgIIAwAAAA==.',To='Tonjudsonson:BAAALAAECgcIBwAAAA==.Totes:BAAALAADCggIFwAAAA==.',Tr='Trillmg:BAAALAAECgIIAgAAAA==.',Tw='Twiki:BAAALAADCggIDQAAAA==.Twobricks:BAAALAAECgYICQAAAA==.',Ty='Tyranirok:BAAALAAECgYICQAAAA==.Tyrssana:BAAALAADCggIDwABLAAECgYICQABAAAAAA==.Tyrwll:BAAALAAECgIIAwAAAA==.',Ur='Urbanmystery:BAAALAAECgcIEgAAAA==.Urdeadtoo:BAAALAAECgMIBQAAAA==.',Va='Val:BAAALAADCggIDwAAAA==.Varnzdort:BAAALAAECgMIBQAAAA==.Vaterunser:BAAALAADCggIDwAAAA==.',Ve='Velskud:BAAALAADCgcIDgAAAA==.Vengfull:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.',Vi='Vincenzo:BAAALAAECgYICQAAAA==.Vinsteam:BAAALAADCgUIBgAAAA==.Visea:BAAALAADCgYIBgAAAA==.',Vl='Vlarett:BAAALAAECgUIBQAAAA==.',Vo='Voznje:BAAALAADCgcIBwAAAA==.',Wa='Warkistla:BAAALAAECgMIAwAAAA==.',Wu='Wulfpan:BAAALAADCgIIAgAAAA==.Wulver:BAAALAAECgMIBgAAAA==.',Wy='Wybieboy:BAAALAAECgIIAwAAAA==.',Xa='Xalabro:BAAALAAECgMIBQAAAA==.',Xz='Xz:BAAALAAECgUIBQABLAAECgMIAwABAAAAAA==.',Yh='Yhorn:BAAALAAECgIIAgAAAA==.',Ys='Yssuplef:BAAALAADCggIDwAAAA==.',Yu='Yuefei:BAAALAADCgcICgAAAA==.',Za='Zaiyra:BAAALAADCgUICQAAAA==.Zakoor:BAAALAADCgcIDgAAAA==.Zareena:BAAALAADCgcIDgAAAA==.Zarrock:BAAALAADCgcIBwAAAA==.Zaug:BAAALAADCgMIBwAAAA==.',Ze='Zebrow:BAAALAADCgcIDgAAAA==.Zedex:BAAALAADCgYIBgAAAA==.',Zi='Zinnkura:BAAALAADCggIDgAAAA==.',Zo='Zorsa:BAAALAADCggIDAAAAA==.',['Ød']='Ødis:BAAALAADCgYICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end