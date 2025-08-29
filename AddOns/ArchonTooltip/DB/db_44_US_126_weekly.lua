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
 local lookup = {'Evoker-Preservation','Evoker-Devastation','Priest-Holy','Unknown-Unknown','Hunter-Marksmanship','Monk-Brewmaster','Shaman-Elemental','Warrior-Fury','Warrior-Arms','Shaman-Restoration','Monk-Windwalker','Monk-Mistweaver',}; local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adonys:BAAALAADCgYIBgAAAA==.Adorraa:BAAALAADCgUIBQAAAA==.Adowyrm:BAABLAAECoEXAAMBAAgIHBc+BQA1AgABAAgIHBc+BQA1AgACAAcInBKQFADFAQAAAA==.',Ai='Airali:BAAALAAECgcICQAAAA==.Airedale:BAAALAAECggIAQAAAA==.',Ak='Akairo:BAABLAAECoEWAAIDAAgIOyHnAwD4AgADAAgIOyHnAwD4AgAAAA==.Akelia:BAAALAAECgEIAQAAAA==.Akula:BAAALAADCgYIBgAAAA==.',Al='Aldori:BAAALAAECgYICQAAAA==.Aleebobwa:BAAALAAECgYIDAAAAA==.Alexanderxl:BAAALAAECgMIAwAAAA==.Aleybobwa:BAAALAAECgIIAgAAAA==.Althalas:BAAALAAECgIIAgAAAA==.Alyméré:BAAALAAECgUIBQAAAA==.',An='Andlissa:BAAALAADCgEIAQAAAA==.Andramedae:BAAALAAECgUIBwAAAA==.Angyavocado:BAAALAAECgYIDQAAAA==.',Ao='Aolus:BAAALAAECgcIDwAAAA==.',Ap='Apogee:BAAALAAECgEIAQAAAA==.Apoliis:BAAALAAECgMIBAAAAA==.',Ar='Arcaina:BAAALAAECgMIAwAAAA==.Arcidaes:BAEALAAECgMIBQAAAA==.Ares:BAAALAAECgEIAQAAAA==.Arez:BAAALAAECgYICAAAAA==.Artèmís:BAAALAAECgMIAwABLAAECgYICAAEAAAAAA==.',As='Ashylarry:BAAALAAECgMIBQAAAA==.Asurna:BAAALAAECgYICAAAAA==.',Au='Aurelyn:BAAALAAECgUICAAAAA==.',Av='Avendesoraa:BAAALAADCgYIBgAAAA==.',Aw='Awooga:BAAALAAECgYICAAAAA==.',Ba='Badoosh:BAAALAAECgMIAwAAAA==.Baeli:BAAALAADCggICAAAAA==.Bajablaster:BAAALAAECgMIBQAAAA==.Balto:BAAALAAECgEIAgAAAA==.Bandoliers:BAAALAAECgMIBQAAAA==.Banugg:BAAALAAECgEIAQAAAA==.',Bc='Bchung:BAAALAAECgcIDwAAAA==.',Be='Beeftender:BAAALAADCgcIBwAAAA==.Belip:BAAALAAECgMIBQAAAA==.Berlwrynn:BAAALAAECgEIAQAAAA==.Bertus:BAAALAADCgQIBAAAAA==.',Bh='Bhain:BAAALAAECgQIBAAAAA==.',Bi='Bieorne:BAAALAAECgMIBQAAAA==.Birdiie:BAAALAADCgcIBwAAAA==.',Bo='Boondocks:BAAALAAECgUICQAAAA==.Boonfire:BAAALAAECgMIAwAAAA==.',Br='Brainiac:BAAALAADCgIIAgAAAA==.Brewtime:BAAALAAECgMIAwAAAA==.Brownbar:BAAALAADCggICwAAAA==.',Bs='Bstrike:BAAALAAECggICAAAAA==.',Bu='Bubbletruble:BAAALAAECgIIAwAAAA==.Bulltaura:BAAALAADCgcIBwAAAA==.Bullymaguire:BAAALAAECgcIDQAAAA==.',Ca='Caeme:BAAALAAECgMIBgAAAA==.Camila:BAAALAADCggIDwAAAA==.',Ce='Ceromaar:BAAALAAECgYICAAAAA==.Cerrako:BAAALAADCgQIBAAAAA==.',Ch='Checkúrback:BAAALAAECgQIBQAAAA==.Cherrypìe:BAAALAADCggIEgAAAA==.Chipcle:BAAALAADCgEIAQAAAA==.',Co='Cobellex:BAAALAADCgQIAwAAAA==.Cokarott:BAAALAAECgYICAAAAA==.Cops:BAAALAAECgMIBAAAAA==.Coriander:BAAALAADCgEIAQAAAA==.',Da='Daemonix:BAAALAADCgcIBwAAAA==.Dalgrenn:BAAALAADCgMIAwAAAA==.Darkenergy:BAAALAAECgUICQAAAA==.Dashyll:BAAALAAECgEIAQAAAA==.',De='Deadrat:BAAALAAECgIIAgAAAA==.Deathfish:BAAALAAECgUIBgAAAA==.Demeter:BAAALAAECgUICAAAAA==.Deseroth:BAAALAADCgcIBwABLAAECgYICAAEAAAAAA==.',Di='Diagnos:BAAALAADCggICgAAAA==.Diddlesz:BAAALAADCgcIFQABLAAECgMIAwAEAAAAAA==.Dimeniare:BAAALAADCgYIBgAAAA==.Dirgen:BAAALAADCggIDwAAAA==.Ditto:BAAALAADCgQIAwAAAA==.',Do='Dogslobber:BAAALAADCgIIAgAAAA==.Dookiee:BAAALAAECgMIBQAAAA==.',Dr='Draggnar:BAAALAAECgMIAwAAAA==.Dragontalon:BAAALAADCgMIAwAAAA==.',Dy='Dyharmis:BAAALAAECgUICAAAAA==.',Ea='Earthhöwler:BAAALAAECgQIBQAAAA==.',Eb='Ebojager:BAAALAAECgMIBQAAAA==.',Ei='Eibon:BAAALAAECggICAAAAA==.',El='Elejefe:BAAALAADCggIDwAAAA==.Elsaiduna:BAAALAADCggIDQAAAA==.',Em='Emmpunity:BAAALAAECgIIAgAAAA==.',Er='Erk:BAAALAADCgEIAQAAAA==.Erus:BAAALAADCgYIBgAAAA==.',Ev='Evalizana:BAAALAADCgcIBwAAAA==.Evdoggy:BAAALAAECgIIAgAAAA==.',Ex='Exterminate:BAAALAAECgIIAwAAAA==.',Fa='Faeyella:BAAALAADCgQIBAAAAA==.Fallenfire:BAAALAADCggICAAAAA==.Fallguys:BAAALAADCgMIAwAAAA==.Fay:BAAALAADCggICgAAAA==.Fayella:BAAALAADCgcIBwAAAA==.',Fe='Felipito:BAAALAAECgQIBwAAAA==.Felparsnip:BAAALAAECgMIBgABLAAECgQIBQAEAAAAAA==.Fengorn:BAAALAADCgUIBQAAAA==.Ferrara:BAACLAAFFIEFAAIFAAMIyCFkAQAfAQAFAAMIyCFkAQAfAQAsAAQKgRcAAgUACAiCJTkBAEwDAAUACAiCJTkBAEwDAAAA.',Fi='Fizzbang:BAAALAADCgcIBwAAAA==.',Fl='Flandri:BAAALAAFFAIIAgAAAA==.Flandrie:BAAALAAFFAEIAQAAAA==.',Fr='Fredfuchs:BAAALAADCgEIAQABLAAECgUICQAEAAAAAA==.Frostednip:BAAALAAECgcIDwAAAA==.',Fu='Fur:BAAALAAECgEIAQAAAA==.Furchy:BAAALAADCgcICQAAAA==.',['Fá']='Fáyt:BAAALAADCgMIAwAAAA==.',Ga='Gabiru:BAAALAAECgcIDgAAAA==.Galnarn:BAACLAAFFIEFAAIGAAMIsxLOAQDhAAAGAAMIsxLOAQDhAAAsAAQKgRcAAgYACAjKIjcCAP4CAAYACAjKIjcCAP4CAAAA.Gankstar:BAABLAAECoEUAAIHAAcI7SIkCQDEAgAHAAcI7SIkCQDEAgAAAA==.Garlicbae:BAAALAADCgcIDAAAAA==.',Ge='Geeno:BAAALAAECgMIBQAAAA==.Geenoo:BAAALAADCgMIAwAAAA==.Gefaustet:BAAALAAECgUICQAAAA==.Gelroos:BAAALAAECgYIDwAAAA==.',Gl='Glazeddonut:BAAALAAECgIIAwAAAA==.',Go='Goop:BAAALAAECgcIDwAAAA==.Gorbachev:BAAALAADCggIFAAAAA==.',Gr='Grayes:BAAALAAECgMIAwAAAA==.Graystorm:BAAALAADCgYIBgABLAAECgMIAwAEAAAAAA==.Grimcybel:BAAALAAECgEIAQAAAA==.Grimsmite:BAAALAAECggIAwAAAA==.Gruxin:BAAALAAECgUIBwAAAA==.',['Gâ']='Gâbrîel:BAAALAADCgcIBwAAAA==.',Ha='Hail:BAAALAAECgMIBAAAAA==.Halbarad:BAAALAAECgYICQAAAA==.Harambesdik:BAAALAAECgcIEwAAAA==.Harmôny:BAAALAADCgYIDAAAAA==.Hatredyes:BAAALAADCggIFAAAAA==.',He='Helare:BAAALAAECgIIAgAAAA==.Heris:BAAALAADCgQIBAAAAA==.Hexenbane:BAAALAAECgIIAgAAAA==.',Ho='Holyman:BAAALAAECgEIAQAAAA==.Holyzap:BAAALAAECgMIAwAAAA==.',Hu='Hugs:BAAALAAECgUICAAAAA==.',Il='Illastian:BAAALAADCgUIBQAAAA==.Illiae:BAAALAAECgIIAgAAAA==.',Im='Imtheteapot:BAAALAAECgcIDwAAAA==.',In='Innex:BAAALAAECgMIBQAAAA==.Inpesca:BAAALAADCgcIBwAAAA==.',Is='Issidora:BAAALAAECgMIBAAAAA==.',Ja='Jakeakuma:BAAALAAECgMIAwAAAA==.Jascob:BAAALAADCgMIAwAAAA==.',Jc='Jcpax:BAAALAAECgEIAQAAAA==.',Jo='Johnnybravo:BAAALAADCggIEAAAAA==.',Ju='Jujutsu:BAAALAADCgIIAwAAAA==.Julio:BAAALAAFFAIIAgAAAA==.Junfan:BAAALAADCggICAAAAA==.Justpeachie:BAAALAAECgUICAAAAA==.',Ka='Kaashaa:BAAALAAECgYIDwAAAA==.Kaelsgf:BAAALAAECgcIEQAAAA==.Kahllan:BAAALAADCggIDwAAAA==.Kataltoholic:BAAALAAECgIIAgAAAA==.Kazel:BAAALAADCgcIBwAAAA==.',Ke='Kelinïsha:BAAALAAECgYICQAAAA==.Kendry:BAAALAAECgMIBAAAAA==.Kevinbacon:BAAALAADCgcIDAAAAA==.',Ki='Kiiras:BAAALAAECgYICQAAAA==.Kilgín:BAAALAADCggIDgAAAA==.Killngseason:BAAALAADCgYIBwAAAA==.Kimbubbles:BAAALAADCgEIAQABLAADCgQIBAAEAAAAAA==.Kimoora:BAAALAADCgQIBAAAAA==.Kirakira:BAAALAADCgUIBQAAAA==.Kirathein:BAAALAADCgcIBwAAAA==.',Kl='Klefthoof:BAAALAAECggIAQAAAA==.',Kn='Knotsozenn:BAAALAAECgIIAwAAAA==.',Ko='Kodey:BAAALAADCggIDwAAAA==.Kordra:BAAALAADCggIFAAAAA==.',Kr='Kraniah:BAAALAADCggIDwAAAA==.Krystallight:BAAALAAECgMIBAAAAA==.Krìsta:BAAALAADCgEIAQAAAA==.',Ku='Kuggul:BAAALAADCgUIBQAAAA==.',Ky='Kyokan:BAAALAADCgMIAwAAAA==.',La='Lanwulf:BAAALAADCgcIBwAAAA==.Lastgasp:BAAALAADCggICAAAAA==.Lazra:BAAALAAECgEIAQAAAA==.',Le='Leapy:BAAALAADCggICAAAAA==.Ledróllan:BAAALAADCgQIAwABLAAECgcIDQAEAAAAAA==.Legaloas:BAAALAAECgMIBAAAAA==.Lenah:BAAALAAECgMIAwAAAA==.Leondero:BAAALAAECgYIDQAAAA==.',Li='Lila:BAAALAAECgEIAQABLAAECgcIEQAEAAAAAA==.Lintelworth:BAAALAADCgcIDgAAAA==.Liver:BAAALAADCggICAAAAA==.',Ll='Llinaigh:BAAALAADCgMIAwAAAA==.',Lo='Loanna:BAAALAADCgcIDQABLAAECgcIEQAEAAAAAA==.Lomu:BAAALAAECgQIBQAAAA==.Lorilei:BAAALAADCgEIAQAAAA==.',Lu='Lucíewilde:BAAALAADCgcIBwAAAA==.',['Lá']='Lázsló:BAAALAAECgEIAQAAAA==.',['Lè']='Lèdrollan:BAAALAAECgcIDQAAAA==.',['Lî']='Lîly:BAAALAADCggIDgAAAA==.',Ma='Machinehead:BAAALAAECgIIBAAAAA==.Magicus:BAAALAAECgEIAQAAAA==.Magidude:BAAALAADCggICwAAAA==.Magnetar:BAAALAADCgEIAQAAAA==.Mainson:BAAALAADCgcIBwAAAA==.Malladaz:BAAALAAECggICwAAAA==.Malorane:BAAALAAECgcIEAAAAA==.Manie:BAAALAADCgQIBAAAAA==.Marisi:BAAALAADCgEIAQABLAADCgcIBwAEAAAAAA==.Materialize:BAAALAAECgQIBgAAAA==.Maut:BAAALAAECggIBQAAAA==.Maz:BAAALAAECgUIBQAAAA==.',Mc='Mcpallypants:BAAALAAECgYICQAAAA==.',Me='Meerchi:BAAALAAECgYICQAAAA==.',Mi='Mickieta:BAAALAAECgUICQAAAA==.Microsurge:BAAALAAECgUIBgAAAA==.Mikalau:BAAALAAECgYICQAAAA==.Miqkail:BAAALAADCgYIBgABLAAECgYICwAEAAAAAA==.Mistrunner:BAAALAADCggICAAAAA==.Mistspell:BAAALAAECgcIEQAAAA==.',Mj='Mjolnir:BAABLAAECoEXAAIHAAgI4B7CCQC4AgAHAAgI4B7CCQC4AgAAAA==.',Mo='Mochizard:BAAALAAECgUIAwAAAA==.Mognel:BAAALAAECgYIBwAAAA==.Mogrungar:BAAALAAECgYIDgAAAA==.Monkilicious:BAAALAADCgcICwAAAA==.Monklee:BAAALAADCggICAAAAA==.Moofaace:BAAALAAECgEIAQAAAA==.',Mu='Murali:BAAALAADCgUIBQAAAA==.',My='Mysterica:BAAALAAECgYIDAAAAA==.',Na='Natureswish:BAAALAAECgcIEwAAAA==.',Ne='Neathe:BAAALAADCgcIBwAAAA==.Net:BAAALAAECgMIAwAAAA==.',Ni='Nicegauges:BAAALAAECgQIBQAAAA==.Nicola:BAAALAADCgYICAAAAA==.Nightrocks:BAAALAAECgUICAAAAA==.Nilfgard:BAAALAADCggIDQAAAA==.Nivix:BAAALAAECgMIAwAAAA==.',No='Nordryds:BAAALAAECgEIAQAAAA==.',Nu='Nuhpie:BAABLAAFFIEFAAMIAAMIMhUHAwANAQAIAAMIMhUHAwANAQAJAAEIARdhAQBYAAAAAA==.',Ny='Nymphetamine:BAAALAADCggIEAABLAAECgMIBQAEAAAAAA==.',['Nï']='Nïghthöwler:BAAALAAECgEIAQABLAAECgQIBQAEAAAAAA==.',Ol='Olimdar:BAACLAAFFIEFAAIKAAMINRrnAQD7AAAKAAMINRrnAQD7AAAsAAQKgRgAAgoACAiNIHEDAOkCAAoACAiNIHEDAOkCAAAA.',Om='Omnidraconus:BAAALAADCggIEgAAAA==.',On='Onyxarme:BAAALAADCgEIAQABLAAECgUICAAEAAAAAA==.',Or='Oraion:BAAALAAECgEIAQAAAA==.Oricelle:BAAALAADCggICAABLAAECgUICAAEAAAAAA==.',Pa='Palldude:BAAALAADCgcIBwAAAA==.Pan:BAAALAADCgYIBgAAAA==.Patrici:BAAALAADCgEIAQAAAA==.',Pd='Pdg:BAAALAADCggIFQAAAA==.',Pe='Petbirb:BAAALAAECgEIAgAAAA==.',Ph='Phya:BAAALAAECgYIBwAAAA==.',Pi='Pilk:BAAALAAECgYIDAAAAA==.',Pl='Plágué:BAAALAAECgQIBQAAAA==.',Pr='Proxema:BAAALAAECgUICAAAAA==.',Qu='Qualzer:BAAALAAECgEIAQAAAA==.Quehacesnada:BAAALAADCgYICAAAAA==.Quoril:BAAALAAECgMIBQAAAA==.',Ra='Radioh:BAAALAADCgYIBgAAAA==.Radoseng:BAAALAADCgYIBgAAAA==.Raediance:BAAALAAECgEIAQAAAA==.Raidru:BAAALAAECgUICAAAAA==.Rainstormin:BAAALAAECgYICQAAAA==.Raisha:BAAALAAECgIIAgAAAA==.Raymond:BAAALAAECgMIAwAAAA==.',Re='Reilin:BAAALAAECgMIAwAAAA==.Rejuvenation:BAAALAADCgQIBAAAAA==.Remsham:BAAALAAECgIIAgAAAA==.Renwyck:BAAALAAECgYICwAAAA==.Revengemoon:BAAALAAECgcIDwAAAA==.',Rh='Rhava:BAAALAAECgQIBQAAAA==.',Ri='Rinfal:BAAALAAECgYIBgAAAA==.',Ro='Rouen:BAAALAAECgIIAgAAAA==.',Ru='Ruckus:BAEALAADCggIDgAAAA==.Ruebane:BAAALAAECgYICQAAAA==.',Ry='Rykken:BAAALAAECgUICQAAAA==.',Sa='Saber:BAAALAAECgcIEQAAAA==.Saintanic:BAAALAAECgYICQAAAA==.Saltytoad:BAAALAADCggICAAAAA==.Sandkat:BAAALAAECggIBQAAAA==.Sanguineous:BAAALAADCgcIBwAAAA==.Saray:BAAALAAECgMICQAAAA==.',Sc='Scratchs:BAAALAADCgcIBAABLAAECgYICQAEAAAAAA==.',Se='Serahstia:BAAALAADCgcIBwAAAA==.Sesame:BAAALAADCgYICgAAAA==.',Sh='Shadòw:BAAALAAECgIIAgAAAA==.Shaiy:BAAALAAECgMIBAAAAA==.Shamanroll:BAAALAADCggICwAAAA==.Shelliroo:BAAALAADCgMIBAAAAA==.Shiftydragon:BAAALAAECgMIAwAAAA==.',Si='Sidecake:BAAALAAECgYIBgAAAA==.Singars:BAAALAAECgcIDwAAAA==.Sisterkind:BAAALAADCgcIBwAAAA==.Siypra:BAAALAAECgUICQAAAA==.',Sk='Skardust:BAAALAAECgIIAgAAAA==.Skarsurge:BAAALAAECgIIAwAAAA==.Skrump:BAAALAAECgYICwAAAA==.',Sp='Spacedmysts:BAAALAAECgYICgABLAABCgYIAwAEAAAAAA==.Sprodage:BAAALAAECgMIBQAAAA==.Spåwny:BAAALAAECgEIAQAAAA==.',St='Steezydks:BAAALAADCgUICwAAAA==.Stoutbrew:BAAALAADCgYIBgAAAA==.Stylö:BAAALAAECgYICgAAAA==.',Su='Suelly:BAAALAADCgYIBgABLAAECgUICQAEAAAAAA==.Suetonius:BAAALAAECgYIDwAAAA==.Suguru:BAAALAAECgEIAQAAAA==.Sukedame:BAAALAAECgUICAAAAA==.',Sw='Swisscake:BAAALAAECgUICAAAAA==.',Ta='Tagda:BAAALAADCgEIAQAAAA==.Talalia:BAAALAAECgUIBwAAAA==.Tannatax:BAAALAAECgMIBQAAAA==.',Te='Tekvet:BAAALAAECggICAAAAA==.',Th='Thewretch:BAAALAAECgMIBQAAAA==.Thorninn:BAAALAAECgYIBwAAAA==.Thumpthump:BAAALAAECgQIBQAAAA==.',Ti='Tindaria:BAAALAADCggIEgAAAA==.Tindoranis:BAAALAADCgYIBgAAAA==.Titiera:BAAALAAECgYICAAAAA==.',To='Totemjunkie:BAAALAAECgIIAgAAAA==.',Tr='Tranquility:BAAALAAECgEIAgAAAA==.Traumatism:BAAALAADCggIDwAAAA==.Triank:BAAALAADCggIBgAAAA==.Trollpie:BAAALAADCgYIBgABLAAFFAMIBQAIADIVAA==.',Ts='Tshark:BAAALAAECgIIAgAAAA==.Tsumí:BAAALAAECgIIAwAAAA==.',Tw='Twareg:BAAALAADCgMIAwAAAA==.Twotom:BAAALAADCgYIBgAAAA==.',Un='Unclepeepers:BAACLAAFFIEFAAILAAMIgBkcAQAOAQALAAMIgBkcAQAOAQAsAAQKgRcAAwsACAhVISQDAPkCAAsACAhVISQDAPkCAAwAAggkBxckAFkAAAAA.',Va='Valtar:BAAALAAECgQIBAAAAA==.',Ve='Vessael:BAAALAADCgcICQAAAA==.',Vi='Vicsen:BAAALAAECgYICQAAAA==.Vikivonvavoo:BAAALAADCgcIBwAAAA==.Vilevixon:BAAALAAECgUICQAAAA==.Vitalorange:BAAALAAECgMIBQAAAA==.',Vo='Vore:BAAALAADCggICAAAAA==.',Wa='Walla:BAAALAAFFAIIAgAAAA==.Warriorlobo:BAAALAAECgUICQAAAA==.',We='Webhead:BAAALAAECgMIAwAAAA==.Weyekîn:BAAALAADCggIHAAAAA==.',Wi='Wildfang:BAAALAAECgMIBgAAAA==.',Xa='Xandronys:BAAALAADCggIDQAAAA==.',Xe='Xebec:BAAALAAECgEIAQAAAA==.',Ya='Yalik:BAAALAAECgIIAgAAAA==.',Ye='Yereld:BAAALAADCgYIDQAAAA==.',Yz='Yzugzugo:BAAALAAECgMIBQAAAA==.',Za='Zalandra:BAAALAADCgYICwAAAA==.Zalckar:BAAALAAECgQIBQAAAA==.',Ze='Zeerinn:BAAALAADCggIEwAAAA==.Zehan:BAABLAAECoEUAAIIAAgIlRPhFAAiAgAIAAgIlRPhFAAiAgAAAA==.Zendead:BAAALAAECgQIBQAAAA==.',Zi='Zigar:BAAALAAECgMIAwAAAA==.Ziggs:BAAALAADCgcIBwAAAA==.Zionspartan:BAAALAADCggICAAAAA==.Zivann:BAAALAAECgEIAQAAAA==.',Zu='Zulas:BAAALAADCggIDgAAAA==.',['Üz']='Üzumaki:BAAALAADCggICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end