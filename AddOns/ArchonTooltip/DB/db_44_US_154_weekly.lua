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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','Druid-Restoration','Warrior-Fury','DeathKnight-Frost','Warlock-Destruction','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Druid-Balance','Warlock-Demonology',}; local provider = {region='US',realm='Mannoroth',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aadda:BAAALAAECggIEgAAAA==.',Ab='Abbynormal:BAAALAADCggIDAABLAAECgIIAgABAAAAAA==.Abena:BAAALAAECgEIAQAAAA==.Abusive:BAAALAAECggIDAAAAA==.',Ad='Adamxz:BAAALAAECgUICAAAAA==.Admire:BAAALAADCgQIBAAAAA==.Adog:BAAALAAECggIEgAAAA==.',Ae='Aerogosa:BAABLAAECoEXAAICAAgI/SLhBADxAgACAAgI/SLhBADxAgAAAA==.',Af='Afflictious:BAAALAAECgEIAQAAAA==.Affrika:BAAALAADCgUIBQAAAA==.',Ag='Agogagog:BAAALAAECgcIEQAAAA==.',Ah='Ahraa:BAAALAADCgMICgAAAA==.',Ai='Aidannt:BAAALAADCgIIAgAAAA==.',Aj='Ajasf:BAAALAADCggIDgAAAA==.',Al='Alishar:BAAALAADCgYICAAAAA==.Allitha:BAEALAADCgcIDAABLAAECgcIDAABAAAAAA==.Altazar:BAAALAADCgUIBQAAAA==.Alzin:BAAALAAECgEIAQABLAAECgcIEAABAAAAAA==.',Am='Amidalah:BAAALAAECgQIBAAAAA==.',An='Anaheita:BAAALAADCgQIBAAAAA==.Anic:BAAALAAECgQIBAAAAA==.Anjelika:BAAALAADCggICwAAAA==.Anklestabber:BAAALAAECgcICAAAAA==.',Aq='Aquáfina:BAAALAAECgYICQAAAA==.',Ar='Araanna:BAAALAADCggICAAAAA==.Arannaa:BAAALAADCgMIAwABLAADCggICAABAAAAAA==.Arannafury:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Archchad:BAAALAADCgEIAQAAAA==.Archdruid:BAAALAAECgUICAAAAA==.Archipal:BAAALAADCgMIAwAAAA==.Archipriest:BAAALAADCgcIBwAAAA==.Arleos:BAAALAAECgcIDgAAAA==.Arrandor:BAAALAADCgQIBAAAAA==.Artemasz:BAAALAADCgUIBgAAAA==.Aryuncrimson:BAAALAAECggIEgAAAA==.',As='Asrelle:BAAALAAECgUIBwAAAA==.',At='Atrophied:BAAALAAECgcIDgAAAA==.',Au='Audeline:BAAALAAECgQIBAAAAA==.',Aw='Awfuldruid:BAAALAADCggICAAAAA==.',Az='Azreluna:BAAALAAECgcIDgAAAA==.',Ba='Baalthur:BAAALAADCgYIBgAAAA==.Babonim:BAAALAAECgMIBQAAAA==.Backshocks:BAAALAADCgMIAgAAAA==.Bajablessed:BAAALAADCgcIDAAAAA==.Bantery:BAAALAADCgIIAwAAAA==.Banuu:BAAALAAECgMIAwAAAA==.Baradoon:BAAALAAECgMIBQAAAA==.Bayow:BAAALAAECggIEAAAAA==.',Be='Beachcubes:BAAALAAECgYICgAAAA==.Bekax:BAAALAAECgMIBAAAAA==.Berce:BAAALAADCggICAAAAA==.',Bi='Bibbity:BAAALAADCgEIAQAAAA==.Bigberenice:BAAALAAECgUIBwAAAA==.Bigbluetaco:BAAALAAECgcIDAAAAA==.Bigchug:BAAALAAECgcIEAAAAA==.Bigdoinkz:BAAALAAECgEIAQAAAA==.Bigtim:BAAALAADCgcICAAAAA==.Bizzul:BAAALAADCgQIBgAAAA==.',Bl='Blindgìrl:BAAALAAECgUICQAAAA==.Bluberyscone:BAAALAADCggICAAAAA==.Blìnk:BAAALAADCgUIBQAAAA==.',Bo='Bokrago:BAAALAADCgMIAwAAAA==.Bookerneg:BAAALAADCgcIBwAAAA==.Borlen:BAAALAADCggICAAAAA==.Boyfriend:BAAALAAECggIAgAAAA==.',Br='Braids:BAAALAADCgcICgAAAA==.Brasstorque:BAAALAADCgcIBwAAAA==.Brewcifer:BAAALAADCgcIBwAAAA==.Brezzon:BAAALAAECgYIDAAAAA==.Brizzletwo:BAAALAAECgYICQAAAA==.Brookesie:BAAALAAECgQIBAAAAA==.Broskiie:BAAALAADCgQIBAAAAA==.Brozz:BAAALAADCgEIAQABLAAECgYIDAABAAAAAA==.Bryanka:BAAALAAECgEIAQAAAA==.Brãnn:BAAALAAECggIEAAAAA==.Brättie:BAABLAAECoEVAAIDAAgIDgtqHQCAAQADAAgIDgtqHQCAAQAAAA==.Bróx:BAABLAAECoEVAAIEAAgIWBzeCgC1AgAEAAgIWBzeCgC1AgAAAA==.',Bu='Bunkie:BAAALAAECgIIBQAAAA==.',Ca='Calmpressure:BAAALAAFFAEIAQAAAA==.Cargy:BAAALAAECgEIAQAAAA==.Catastorm:BAAALAAECgIIAgABLAAECgcIEQABAAAAAA==.Catavoker:BAAALAAECgcIEQAAAA==.Caveatemptor:BAAALAADCggICAABLAAECggIFwACANAjAA==.',Ce='Celaina:BAAALAAECgQIBAAAAA==.Celiena:BAAALAADCgcIDgAAAA==.',Ch='Chiridrake:BAAALAAECgYIBgAAAA==.Chirilidan:BAAALAADCgYIBgAAAA==.Chontosh:BAAALAAECgIIAwAAAA==.',Ci='Cindymccain:BAAALAAECgMICQAAAA==.Cinnadin:BAAALAADCggICgAAAA==.',Co='Context:BAAALAAECgYICQAAAA==.Corursa:BAAALAADCgYIEQABLAAECgQIBwABAAAAAA==.',Cr='Creepymage:BAAALAAECgIIAgAAAA==.Critterr:BAAALAADCgcIBwAAAA==.Crolly:BAAALAADCgYIBgAAAA==.Crypticfire:BAAALAAECggIAgAAAA==.',Cu='Cumchulainn:BAAALAAECgYIDQAAAA==.Curanderá:BAAALAADCgYIBgAAAA==.Curtaíns:BAAALAADCgcIBwAAAA==.Curvy:BAAALAAECgYICgAAAA==.',['Cä']='Cäsabonita:BAAALAAECgEIAQAAAA==.',Da='Danasty:BAAALAAECgMIAwAAAA==.Dante:BAAALAAECgMIAwAAAA==.Darkkstalker:BAAALAADCgYIBgAAAA==.Darkvalk:BAAALAADCgMIBAAAAA==.Daroc:BAAALAAECggIBAAAAA==.Darquarius:BAAALAADCggIFAAAAA==.Darvax:BAAALAAECgYICQAAAA==.',De='Deathnut:BAAALAAECgYICwABLAAECgYIDQABAAAAAA==.Deathtone:BAAALAAECgYIDQAAAA==.Demoinc:BAAALAAECgQIBwAAAA==.Denus:BAAALAADCgcICgAAAA==.',Di='Dimsumfatboy:BAAALAADCgUIBQAAAA==.Dionelli:BAAALAAECgEIAQAAAA==.Dippiedoe:BAAALAADCggICAAAAA==.Disctater:BAAALAADCggIDwAAAA==.Divalatina:BAAALAAECgcIEQAAAA==.',Dk='Dkb:BAAALAADCggICAAAAA==.',Dl='Dlxtrap:BAAALAAECgYICwAAAA==.',Dm='Dmega:BAAALAADCggICAAAAA==.',Do='Doodoofarted:BAAALAADCgcIDgAAAA==.Doombringerr:BAAALAAECgQIBwAAAA==.',Dr='Draenoth:BAAALAADCgUIBQAAAA==.Dragondeezn:BAAALAADCgcIDQAAAA==.Dragonmans:BAAALAAECgYIDQAAAA==.Drakthorn:BAAALAAECgQIBAAAAA==.Dreamyeyes:BAAALAAECgUICAAAAA==.Dreeva:BAAALAADCgMIAwAAAA==.Dregoth:BAAALAADCgcIBwAAAA==.Drinkingtime:BAAALAADCgYIBgAAAA==.Druiswurm:BAAALAADCgEIAQABLAAECggIEQABAAAAAA==.Drutah:BAAALAADCgcICQAAAA==.Drånøsh:BAAALAADCgIIAgAAAA==.',Du='Dupichu:BAAALAAECgIIAgAAAA==.Durlougim:BAAALAADCgMIAwAAAA==.',Dw='Dwarfpalidad:BAAALAADCgcIDAAAAA==.',Dy='Dynamo:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.',Eg='Egdorp:BAAALAADCggIEAAAAA==.',El='Ellzee:BAAALAAECgMIAwAAAA==.',Er='Erashi:BAAALAAECgUICAAAAA==.Eryxus:BAAALAADCggIDwAAAA==.',Ev='Evavoker:BAAALAADCggICAAAAA==.Everbidiwi:BAAALAADCgIIAgAAAA==.',Ez='Ezaneath:BAAALAADCgcIDQAAAA==.',Fa='Fadingember:BAAALAAECgMIAwAAAA==.Fallaena:BAAALAAECgEIAQAAAA==.Fallendevil:BAAALAADCgUIBQAAAA==.',Fe='Fearhazard:BAAALAAECgYIDAAAAA==.Felbrook:BAAALAADCggIFgAAAA==.Felwyth:BAAALAADCgcIBwAAAA==.',Fi='Firesign:BAAALAAECgQIBwAAAA==.Fishee:BAAALAAECgEIAQAAAA==.Fishhawk:BAAALAAECgYICQAAAA==.Fistz:BAAALAADCggIEQAAAA==.',Fl='Flarehammer:BAAALAAECgcIEAAAAA==.Flashton:BAAALAADCgUIBQAAAA==.Fleurdumal:BAEALAAECgcIEAAAAA==.Flogh:BAAALAAECgMIAwAAAA==.Florle:BAAALAADCgYICQAAAA==.',Fo='Fobbos:BAAALAADCgcIBwAAAA==.',Fr='Franko:BAAALAAECgMIBQAAAA==.Freq:BAAALAADCgMIAwAAAA==.Fright:BAAALAAECgUICAAAAA==.Frobama:BAAALAADCgUIBQAAAA==.Frozatrath:BAAALAADCgYIBwAAAA==.',Fu='Fuchurbolts:BAAALAADCgYIBgAAAA==.Funkyo:BAAALAADCggIEQAAAA==.Fure:BAAALAADCgcIBwAAAA==.Furyallos:BAAALAADCggIFQABLAAECgMIBQABAAAAAA==.',['Fö']='Förbindelse:BAAALAAECgcICAAAAA==.',Ga='Gallien:BAAALAADCggICAAAAA==.Gatszu:BAAALAADCggICAAAAA==.',Gi='Gilgamessh:BAAALAADCgYIBgAAAA==.',Go='Gorgami:BAAALAADCgcIBwAAAA==.Gothhooters:BAAALAAECgUIBwAAAA==.',Gr='Grandma:BAAALAADCgQIBAAAAA==.Gretham:BAAALAADCgYIBgAAAA==.Grumbleface:BAAALAAECggIEgAAAA==.Grumpyares:BAAALAAECgcICAAAAA==.',Gu='Gudmund:BAAALAAECgMIAwAAAA==.Gulmolv:BAAALAAECgIIBAAAAA==.Gumbotron:BAAALAADCgQIBAAAAA==.Gurddon:BAAALAADCgIIAgAAAA==.',Ha='Haawee:BAAALAAECgMIBQABLAAECgUIBgABAAAAAA==.Hailyourself:BAAALAADCgcIBwAAAA==.Handorn:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Handrik:BAAALAADCggIDQAAAA==.Hazkul:BAAALAAECgQIBQABLAAECgQIDAABAAAAAA==.Hazkull:BAAALAADCggIDwABLAAECgQIDAABAAAAAA==.Hazzkul:BAAALAAECgQIDAAAAA==.',He='Heartay:BAAALAADCgcIEQAAAA==.Heavyranger:BAAALAADCgcIBwAAAA==.Heetbag:BAAALAADCgcIFAAAAA==.Helldwarf:BAABLAAECoEWAAIFAAgInxI5IAAEAgAFAAgInxI5IAAEAgAAAA==.Helloboys:BAAALAAECgcIBwAAAA==.Helloda:BAAALAAECgYICAABLAAECggIFgAFAJ8SAA==.Henzo:BAAALAADCgcICwAAAA==.',Hi='Hiereus:BAAALAADCgcIBwAAAA==.Highrise:BAAALAADCggICwAAAA==.Higitus:BAAALAAECgEIAQAAAA==.Himi:BAAALAAECgMIBAAAAA==.',Hs='Hsk:BAAALAAECgcIEAAAAA==.',Hu='Hulkaholic:BAAALAAECgYIDAAAAA==.Hulkhunts:BAAALAAECgMIAwAAAA==.',Hy='Hybie:BAAALAAECgMIBAAAAA==.',In='Inseratum:BAAALAADCgYIBgAAAA==.Inurend:BAAALAAECgIIAgAAAA==.',Io='Iovar:BAAALAADCgcICQAAAA==.',Ip='Ipokeyouhard:BAAALAADCgIIAgAAAA==.',Is='Israfell:BAAALAAECgQIBAAAAA==.',Ja='Janaela:BAAALAADCggICAAAAA==.Jangidget:BAAALAADCggIDAAAAA==.Jarnar:BAAALAADCggICAAAAA==.',Jh='Jhatolos:BAAALAADCgYIBgAAAA==.',Ji='Jinxtd:BAAALAAECgYICQAAAA==.Jinzy:BAAALAADCgUIBgAAAA==.',Jo='Johhnyp:BAAALAAECgcIDwAAAA==.Josa:BAEALAAECgcIDAAAAA==.',Ju='Judgments:BAAALAAECgYICQAAAA==.Juneya:BAAALAADCggIEAAAAA==.Jurbil:BAAALAADCgEIAQAAAA==.',['Jê']='Jêkyl:BAAALAAECgEIAQAAAA==.',Ka='Kaddy:BAAALAADCggICAAAAA==.Kaeles:BAAALAADCgYIBgAAAA==.Kajimoto:BAAALAAECgMIAwAAAA==.Kassu:BAAALAADCgMIAwAAAA==.Kauni:BAAALAAECgYIBgAAAA==.Kazama:BAAALAAECgYICQAAAA==.Kazmo:BAAALAAECgYICQAAAA==.Kaïju:BAAALAAECgUIBgAAAA==.',Ke='Kelintok:BAAALAADCggICAAAAA==.Kesem:BAAALAADCgEIAQAAAA==.Keìra:BAAALAAECgMIBQAAAA==.',Kg='Kgwho:BAAALAAECgIIAgAAAA==.',Ki='Kirowillhelm:BAAALAAECgYIBgAAAA==.',Kl='Klitor:BAAALAADCggIDwAAAA==.',Kn='Knitbeanie:BAAALAADCgYIBgAAAA==.Knobie:BAAALAAECgcIDAAAAA==.',Kr='Kragden:BAAALAAECgIIAgAAAA==.Krasius:BAAALAADCgQIBAAAAA==.Kronkk:BAAALAADCgcICAAAAA==.Krypticsneak:BAEALAAECgYIDAABLAAECggICAABAAAAAA==.',Ku='Kugora:BAAALAADCgYIBwAAAA==.Kuroom:BAAALAADCggIFwAAAA==.Kurorn:BAAALAADCgcIBwAAAA==.',['Kî']='Kîriko:BAAALAADCgMIAwAAAA==.',La='Ladrian:BAAALAADCgcICgABLAAECgYICAABAAAAAA==.Lagunitas:BAAALAADCgcIAgABLAAECgMIBQABAAAAAA==.Langers:BAAALAAECgEIAQAAAA==.Larood:BAAALAADCgEIAQAAAA==.Larrykpinga:BAAALAAECgEIAQAAAA==.Laryngology:BAAALAADCgYIBgAAAA==.Larüd:BAAALAADCgMIAwAAAA==.',Le='Legallyblind:BAAALAAECgYIDQAAAA==.',Li='Likkho:BAAALAADCgcICAAAAA==.Likuono:BAAALAADCgMIAwAAAA==.Livekiller:BAAALAAECgQICAAAAA==.',Lo='Loni:BAAALAAECgUICAAAAA==.Loonar:BAAALAADCggIEwAAAA==.Lotzapulls:BAAALAADCgQIBgAAAA==.Loviane:BAAALAAECgQIBQAAAA==.',Lu='Lucientia:BAAALAADCggICwAAAA==.Lucithalle:BAAALAAECgUIBwAAAA==.Ludki:BAAALAAECgUICAAAAA==.Lundi:BAAALAAECgIIAgAAAA==.Lusekiller:BAAALAADCggICAAAAA==.',Ly='Lyllth:BAAALAADCggICAAAAA==.Lythandriel:BAAALAADCggIEAAAAA==.',Ma='Maeivalla:BAAALAAECgYIDQAAAA==.Malvious:BAAALAADCgEIAQAAAA==.Mana:BAAALAADCgYIBgABLAAECgUICAABAAAAAA==.Margolis:BAAALAAFFAEIAQABLAAFFAMIBQAGAKMWAA==.Marivelous:BAAALAAECgMIAwAAAA==.Mathath:BAAALAAECgYICQAAAA==.Matroshka:BAAALAADCgIIAgAAAA==.Maxthegreat:BAAALAADCgcICAAAAA==.Mazapan:BAAALAADCgcIBwAAAA==.',Me='Mercourier:BAAALAADCgEIAQABLAAECggIEQABAAAAAA==.Mericaa:BAAALAAECgQIBwAAAA==.',Mi='Minidk:BAAALAAECgcIDgAAAA==.Minivalk:BAAALAADCgQIBQAAAA==.Mintfish:BAAALAADCgYIBgAAAA==.Misfortune:BAAALAAECgMIAwAAAA==.Mitsy:BAAALAAECgMIAwAAAA==.',Mo='Mobaybe:BAAALAADCgcICAAAAA==.Moistbuns:BAAALAAECgcIEAAAAA==.Moistmatthew:BAAALAAECgMIAwAAAA==.Mokthrar:BAAALAADCggICAAAAA==.Molatova:BAAALAAECgUICAAAAA==.Montaro:BAAALAADCgYIBgAAAA==.Morgiana:BAAALAAECgIIAgAAAA==.Morthis:BAAALAADCggICQAAAA==.',Mu='Munnyshot:BAAALAAECgMIAwAAAA==.Muridan:BAAALAADCgcIDQAAAA==.',My='Mystics:BAAALAAECgcIDgAAAA==.',['Mò']='Mòbane:BAAALAADCgcIBwAAAA==.',['Mô']='Môbâne:BAAALAAECgcICAAAAA==.',Na='Naeb:BAAALAADCggIBQAAAA==.Naebadin:BAAALAAECgIIAgAAAA==.Nagafen:BAAALAAECgUIBQAAAA==.Nakotak:BAAALAADCgcICQAAAA==.Natenda:BAAALAADCgcIBwABLAAECggIBwABAAAAAA==.Natendo:BAAALAAECggIBwAAAA==.Nathandrias:BAAALAADCgMIAwABLAAECggIBwABAAAAAA==.Naturecallz:BAAALAADCggIDgAAAA==.',Ne='Nelan:BAAALAADCgEIAQAAAA==.Nethril:BAAALAAECgQIBQAAAA==.Nezzthena:BAAALAAECgMIAwAAAA==.',No='Norowareta:BAAALAADCgcIBwAAAA==.',Nu='Nukitt:BAAALAADCggICAAAAA==.Nutwand:BAAALAADCgcIBwAAAA==.',Ny='Nyemm:BAAALAADCgQIBAAAAA==.',Ob='Obliterate:BAAALAADCgcICQAAAA==.',Od='Odonn:BAAALAAECgMIBQAAAA==.',Og='Ogkushh:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Ogsleepy:BAAALAAECgMIBQAAAA==.Ogun:BAABLAAECoEWAAIHAAgItBbOEAAtAgAHAAgItBbOEAAtAgAAAA==.',On='Onecoldboi:BAAALAADCgUIBQAAAA==.Onryo:BAAALAADCgYIBgAAAA==.',Oo='Oopii:BAAALAAECgYICQAAAA==.',Ou='Ouijaboard:BAAALAADCgIIAgABLAADCgQIBwABAAAAAA==.',Ov='Overkill:BAAALAADCggICAAAAA==.Overtheline:BAAALAADCgUIBwAAAA==.',Pa='Paladicaprio:BAAALAAECggIBAAAAA==.Pallos:BAAALAADCgUIBQAAAA==.Palmdale:BAAALAADCggICgAAAA==.Pan:BAAALAADCgQIBAAAAA==.Pandamilf:BAAALAAECgUIBQABLAAFFAMIBQAGAKMWAA==.Pannmann:BAAALAADCgcICQAAAA==.Paperalza:BAAALAAECgYICAAAAA==.Parkway:BAAALAADCgIIAgAAAA==.Pathofpain:BAAALAAECgcIEQAAAA==.Pattypat:BAAALAADCggICwAAAA==.',Pe='Pewpeworc:BAAALAADCggICAAAAA==.',Ph='Philpriest:BAAALAAECgYICwAAAA==.',Pi='Piggsy:BAAALAADCgUIBQAAAA==.Pisspissboy:BAAALAADCgYIBgAAAA==.',Pl='Plagueheart:BAAALAAECgYIBwAAAA==.Pliocene:BAABLAAECoEXAAICAAgI0CP6AgAkAwACAAgI0CP6AgAkAwAAAA==.',Po='Pochaccob:BAAALAAECgIIAgAAAA==.Pounddcake:BAAALAADCgcIEAAAAA==.',Pr='Pressbuttons:BAAALAADCgcIEwABLAAFFAEIAQABAAAAAA==.',Ps='Pseudonym:BAAALAADCggICAAAAA==.Psychoo:BAAALAADCgcIDQAAAA==.',Pu='Puchini:BAAALAADCgUIBQAAAA==.',['Pé']='Pémbali:BAAALAADCggIDwAAAA==.',['Pó']='Póe:BAAALAAECgcICwAAAA==.',Qo='Qokk:BAAALAAECgUICAAAAA==.',Ra='Ragnalock:BAAALAAECgIIAgAAAA==.Ragnarök:BAAALAAECgIIAgAAAA==.Rakoboom:BAAALAADCgQIBAAAAA==.Rambunctious:BAAALAADCggIBwAAAA==.Ramogin:BAAALAADCgMIAwAAAA==.Randisavage:BAAALAAECgMIBAAAAA==.Rarh:BAAALAAECgMICQAAAA==.Rathhorn:BAAALAAECgEIAQAAAA==.Ravixx:BAAALAAECgMIBAAAAA==.Razure:BAAALAAECgYICAAAAA==.',Re='Reble:BAAALAADCgQIBAAAAA==.Relarian:BAAALAAECgMIAwAAAA==.Releimus:BAAALAAECgMIBQAAAA==.Renuko:BAAALAAECgUIBQAAAA==.Reubs:BAAALAADCggICQAAAA==.Revengeance:BAAALAAECgcIDgAAAA==.',Ro='Rosalíe:BAAALAADCggIDAAAAA==.Roxen:BAAALAAECgYICgAAAA==.',Ru='Rukam:BAAALAADCgYIBgAAAA==.Rusticles:BAAALAAECgEIAgAAAA==.',Ry='Ryuunosuke:BAAALAAECgcIDgAAAA==.',['Rà']='Ràgnarok:BAAALAADCgYICAAAAA==.',['Rè']='Rèdboi:BAAALAADCgYIBgAAAA==.',['Rë']='Rëvan:BAAALAAECgMIAwAAAA==.',Sa='Sabers:BAAALAAECgUIBwAAAA==.Sabriinaa:BAAALAAECgIIAgAAAA==.Sabrinachi:BAAALAADCggICAAAAA==.Sacrednips:BAAALAADCgcICAAAAA==.Sakkraa:BAAALAAECgYICQAAAA==.Salty:BAAALAAECgQIBgAAAA==.Samwish:BAACLAAFFIEFAAIIAAMINRcPAgAaAQAIAAMINRcPAgAaAQAsAAQKgRcAAwgACAj9ImwDABEDAAgACAj9ImwDABEDAAkABQjSCzwMAAUBAAAA.Sandwittch:BAAALAADCgMIAwAAAA==.Sapperpoppij:BAAALAADCgcIDAAAAA==.Sarid:BAAALAAECgUICAAAAA==.Sarima:BAAALAAECgIIAgAAAA==.Sarthrel:BAAALAADCgQIBAAAAA==.Sarumon:BAAALAADCggIDwAAAA==.Sauron:BAAALAAECgQIBQAAAA==.Saynomore:BAAALAADCgcIDAAAAA==.',Sc='Schnibs:BAAALAAECggICAAAAA==.Scumbpa:BAAALAAECgUIBQAAAA==.Scurvydan:BAAALAADCgEIAQAAAA==.',Se='Seeingeyedog:BAAALAAECgUICQAAAA==.Seerenity:BAAALAADCggIEAAAAA==.Seigjr:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.Seiracon:BAAALAADCgcIBwAAAA==.Selidori:BAAALAAECgYIBwAAAA==.Sentinel:BAAALAADCgQIBAAAAA==.Serai:BAAALAAECgIIBAAAAA==.Serathresh:BAAALAADCggICAAAAA==.Setazer:BAAALAADCgIIAgABLAADCgMIAwABAAAAAA==.',Sh='Shadowscales:BAAALAAECgcIEAAAAA==.Shadowshock:BAAALAAECgMIAwAAAA==.Shadowzar:BAAALAADCgYIBwABLAAECgMIAwABAAAAAA==.Shamefull:BAAALAAECgUIBgAAAA==.Shamslay:BAAALAAECgcIDwAAAA==.Shaundel:BAAALAAECgEIAQAAAA==.Shortyy:BAAALAAECgUIBwAAAA==.Shredztastic:BAABLAAECoEYAAMEAAgIPiaxAACAAwAEAAgIJiaxAACAAwAKAAEI2iaKEAB1AAAAAA==.Shunt:BAAALAADCgcIDQAAAA==.',Si='Sillycharly:BAAALAADCggICQAAAA==.Silvänus:BAAALAAECgcIDwAAAA==.',Sl='Slanesh:BAAALAADCgcIBwAAAA==.Slapcheek:BAAALAADCggIDgAAAA==.Slèèp:BAAALAAECgIIAgAAAA==.',Sm='Smallman:BAAALAADCgcIBwAAAA==.',Sn='Snacs:BAAALAADCgYICgAAAA==.',So='Someperson:BAAALAADCgUIBgAAAA==.',Sp='Spaceghost:BAAALAADCgYIBgAAAA==.Spaghettiman:BAAALAADCgMIAwABLAADCgcIBwABAAAAAA==.Speedshot:BAAALAAECgcIDgAAAA==.Spitfirev:BAABLAAECoEWAAICAAgIUB+hBwCvAgACAAgIUB+hBwCvAgAAAA==.Spitfirex:BAAALAAECgYICQABLAAECggIFgACAFAfAA==.',Sr='Srasmodeo:BAAALAADCgQIBAAAAA==.',St='Steinydragon:BAAALAADCggIEAAAAA==.Stompsky:BAABLAAECoEXAAILAAgIlh1QBgDgAgALAAgIlh1QBgDgAgAAAA==.Stormeagle:BAAALAADCgMIAwAAAA==.Stunamgid:BAAALAAECgUICQABLAAECgYIDQABAAAAAA==.',Su='Sumtingwong:BAAALAADCgcICQAAAA==.Sunbunz:BAAALAADCggIDwAAAA==.Susumu:BAAALAAECgYIEAAAAA==.',Sy='Syrenn:BAAALAADCgUIBQAAAA==.Syrio:BAAALAAECgUIBwAAAA==.',Ta='Taerun:BAAALAADCgYICwAAAA==.Tahu:BAAALAAECgEIAQABLAAECgYICgABAAAAAA==.Takal:BAAALAADCggIEwAAAA==.',Te='Teddyholynow:BAAALAAECgYICwAAAA==.Teddyready:BAAALAAECgEIAQAAAA==.Terrence:BAAALAADCgcICQAAAA==.Terrorize:BAAALAAECgUICAAAAA==.',Th='Thehawee:BAAALAAECgUIBgAAAA==.Thrine:BAAALAADCggIDwAAAA==.',Ti='Timmytom:BAAALAADCgcIBwAAAA==.',To='Toastcubee:BAAALAADCgYICAAAAA==.Tobogganmd:BAAALAAECgMIAwAAAA==.Tokajok:BAAALAAECggIEAAAAA==.Tokash:BAAALAAECgEIAQABLAAECggIEAABAAAAAA==.Tommygubanc:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.Topazd:BAAALAADCggIFQAAAA==.Tornadofang:BAAALAAECgcIDQAAAA==.',Tr='Treyrin:BAAALAAECgMIBQAAAA==.Trolldemon:BAACLAAFFIEFAAIGAAMIoxZDAwAUAQAGAAMIoxZDAwAUAQAsAAQKgRoAAwYACAgxIDIJALkCAAYACAgxIDIJALkCAAwACAgAFUkIAOABAAAA.',Ts='Tsumego:BAAALAAECgIIAgAAAA==.',Tu='Turtle:BAAALAAECggIEAAAAA==.',Ty='Tyluwu:BAAALAAECgYIBgAAAA==.Typhis:BAAALAADCggICAAAAA==.Tytanya:BAAALAADCgIIAgAAAA==.Tyzz:BAAALAADCgYIBgAAAA==.',['Tè']='Tèa:BAAALAADCgcIDQAAAA==.',['Tö']='Tökashi:BAAALAADCgcICQABLAAECggIEAABAAAAAA==.',['Tÿ']='Tÿ:BAAALAADCggICAAAAA==.',Ul='Uliquiorra:BAAALAADCgEIAQAAAA==.',Un='Unknownuser:BAAALAADCgUIBQAAAA==.',Ur='Urnn:BAAALAADCgcICAAAAA==.',Va='Vajaiina:BAAALAADCgUICQAAAA==.Vakar:BAAALAADCgUIBQAAAA==.Valkyriee:BAAALAADCgMIBAAAAA==.Vallck:BAAALAAECggIEQAAAA==.Varonos:BAAALAAECgYICwAAAA==.Vasha:BAAALAADCgQIBwABLAAECgQIBwABAAAAAA==.Vashrael:BAAALAADCgYIBgAAAA==.',Ve='Veingogh:BAAALAAECgMIBgAAAA==.Ventee:BAAALAAECgEIAQAAAA==.Veratyn:BAAALAADCgQIBAAAAA==.Vervallen:BAAALAAECggICAAAAA==.Vexandra:BAAALAADCggIFAAAAA==.Vexthul:BAAALAADCggICAAAAA==.',Vi='Virtuositee:BAAALAADCgUIBQAAAA==.Vitadin:BAAALAADCgMIBwAAAA==.',Wa='Wanklezilla:BAAALAADCggIFgAAAA==.Warslaya:BAAALAADCgEIAQAAAA==.Warthog:BAAALAADCgcIDwAAAA==.Warwar:BAAALAADCggIDwAAAA==.Washu:BAAALAADCgcIBwAAAA==.',We='Weedtrimmer:BAAALAAECgEIAQAAAA==.',Wi='Windhelm:BAAALAADCggIFwAAAA==.Winly:BAAALAADCgEIAQAAAA==.',Wo='Wokker:BAAALAAECgEIAQAAAA==.Woopy:BAAALAADCgEIAgAAAA==.Worstwaifu:BAAALAAECgYICwAAAA==.',Wq='Wqwwqw:BAAALAADCggIFQAAAA==.',Xa='Xalatoes:BAAALAAECgcIDwAAAA==.',Xe='Xeum:BAAALAADCggICAAAAA==.',Xh='Xhyros:BAAALAAECgcIBwAAAA==.',Xi='Xiahou:BAAALAAECgcIDgAAAA==.',Yi='Yinghou:BAAALAADCgEIAQAAAA==.',Yo='Youw:BAAALAAECgMIBAAAAA==.',Ys='Ysl:BAAALAAECgMIBQAAAA==.',Yu='Yunaraz:BAAALAADCgUIBQAAAA==.',Za='Zaeletazs:BAAALAADCgcIEQAAAA==.Zanjo:BAAALAADCggIEwAAAA==.Zaq:BAAALAAECgIIBAAAAA==.Zarg:BAAALAAECgIIAgAAAA==.Zaxc:BAAALAADCgEIAQAAAA==.Zazie:BAAALAAECgYIDQAAAA==.',Zi='Zidzap:BAAALAADCgYICwAAAA==.',Zo='Zooape:BAAALAAECgYICgAAAA==.Zoobadooba:BAAALAADCgcIDgAAAA==.Zowa:BAAALAAECgYIBgAAAA==.',['ßl']='ßløødëmprêss:BAAALAAECgMIAwAAAA==.',['ßu']='ßuzz:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end