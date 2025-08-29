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
 local lookup = {'Unknown-Unknown','Warrior-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Devastation',}; local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abi:BAAALAADCggIAwAAAA==.Abyssel:BAAALAADCgcIBAAAAA==.',Ac='Aceon:BAAALAADCggIEQAAAA==.Aceonarcher:BAAALAADCgYIBgAAAA==.',Ad='Adfectia:BAAALAAECgQIBgAAAA==.Admeia:BAAALAADCggIDwAAAA==.',Ae='Aelintodas:BAAALAADCgcIEwAAAA==.Aelyt:BAAALAADCgQIBAAAAA==.Aeryana:BAAALAAECgYICQAAAA==.Aethér:BAAALAADCggICAABLAAECgcIDgABAAAAAA==.',Ah='Ahsokaa:BAAALAADCggIDwAAAA==.',Ak='Akhnatun:BAAALAADCgcICgAAAA==.',Al='Aldazan:BAAALAADCgQIBAAAAA==.Allarol:BAAALAAECggICQAAAA==.Alynas:BAAALAADCggIDgAAAA==.Alysona:BAAALAAECgIIAwAAAA==.',Am='Amelthia:BAAALAADCgUIBQAAAA==.Amewow:BAAALAADCgMIAwAAAA==.Amìko:BAAALAADCgcIDAAAAA==.',Ap='Apoundofcake:BAAALAADCgMIAwAAAA==.',Ar='Arindel:BAAALAADCgYIBgAAAA==.Arnolaf:BAAALAADCgcICAAAAA==.Arnold:BAAALAAECgIIAgAAAA==.Artíco:BAAALAADCgQIBAAAAA==.',As='Asheronmight:BAAALAADCggIEgABLAAECgIIBQABAAAAAA==.Asherous:BAAALAAECgIIBQAAAA==.Ashflower:BAAALAADCggIDwAAAA==.Asril:BAAALAADCggICAAAAA==.Asutaiya:BAAALAADCgYICAAAAA==.',Au='Auntiedruid:BAAALAADCgUIBQAAAA==.Auntiemom:BAAALAADCgQIBAAAAA==.Auranhis:BAAALAAECgMIAwAAAA==.',Ay='Ayrîa:BAAALAADCgIIAgAAAA==.',Az='Azozol:BAAALAADCggIDQAAAA==.',Ba='Balør:BAAALAAECgMIBAAAAA==.Basementcat:BAAALAAECgMIAwAAAA==.',Be='Beenah:BAAALAAECgEIAQAAAA==.Bel:BAAALAADCgEIAQAAAA==.Beran:BAAALAADCgQIBAAAAA==.',Bi='Bighealy:BAAALAADCggIEQABLAAECgIIBQABAAAAAA==.',Bl='Blaker:BAAALAADCgYICgAAAA==.Blindchicken:BAAALAADCgYIBgAAAA==.Blodeuedd:BAAALAAECgYIDgAAAA==.Bloodrain:BAAALAAECgIIAgAAAA==.Blueaurora:BAAALAAECgMIBgAAAA==.',Bo='Boopty:BAAALAADCgQIBAAAAA==.Booptyboop:BAAALAADCggIDgAAAA==.Bowhawk:BAAALAADCggIDgAAAA==.',Br='Brokenmind:BAAALAADCgMIAwAAAA==.Brotund:BAAALAAECgcIDQAAAA==.Brubble:BAAALAAECgYIDQAAAA==.',Bu='Bubblzmgee:BAAALAADCgUIBQAAAA==.',Ca='Caedus:BAAALAAECgMIAQAAAA==.Cakeman:BAAALAADCgcIDQAAAA==.Calabim:BAAALAADCggICAAAAA==.Carachupa:BAAALAAECgMIAwAAAA==.Carindria:BAAALAADCgYIBgAAAA==.Cassamarle:BAAALAAECgIIAwAAAA==.',Ce='Celaylria:BAAALAADCggICQAAAA==.Celeal:BAAALAADCgYIBgAAAA==.',Ch='Chabz:BAAALAAECgMIAwAAAA==.Cheryll:BAAALAADCggIDwAAAA==.Chinoo:BAAALAAECgYIBwAAAA==.',Ci='Cicnus:BAAALAADCgcIBwAAAA==.',Cl='Cloudedjade:BAAALAAECgIIAwAAAA==.Cloudedmonk:BAAALAADCgQIBwAAAA==.',Co='Coding:BAAALAADCgIIAgAAAA==.Copedh:BAAALAADCggIDwAAAA==.Copedogg:BAAALAADCgMIAwAAAA==.Corrode:BAAALAAECgMIAwAAAA==.',Cr='Cricky:BAAALAAECgEIAQAAAA==.Crimslite:BAAALAAECgMIBAAAAA==.Crìmsònnyx:BAAALAAECgIIAgAAAA==.',Ct='Ctrlshred:BAAALAADCggIEAAAAA==.',Cy='Cybeldin:BAAALAAECgMIBAAAAA==.',['Có']='Cówgirl:BAAALAAECgUIBgAAAA==.',Da='Daark:BAAALAADCgcICAAAAA==.Darazanot:BAAALAADCgcIEAAAAA==.Dardeathicus:BAAALAAECgMICQAAAA==.Darwarricus:BAAALAADCgcIBwAAAA==.',De='Deathrus:BAAALAADCgYIBgAAAA==.Deepika:BAAALAADCgcICAAAAA==.Despondent:BAAALAADCgcIAQAAAA==.',Dr='Dracthra:BAAALAADCgcICgABLAADCgcIDQABAAAAAA==.Dreamlesnite:BAAALAAECgMIBAAAAA==.',Du='Duoda:BAAALAAECgYIEAAAAA==.',Dy='Dylora:BAAALAAECgMIBAAAAA==.Dysfunctiona:BAAALAAECgMIBAAAAA==.',Ed='Eddgíánts:BAAALAADCgYIBgAAAA==.',Eg='Egølifter:BAAALAADCggIDgAAAA==.',El='Ele:BAAALAADCgcICAAAAA==.Elistraa:BAAALAAECgYICAAAAA==.Ellaria:BAAALAAECgMIBAAAAA==.Elluna:BAAALAAECgIIAwAAAA==.Elsali:BAAALAADCgQIBAAAAA==.',Em='Emokins:BAAALAAECgMIBAAAAA==.',En='Endesh:BAAALAAECgMIBAAAAA==.',Ev='Evalynn:BAAALAADCgcIBwAAAA==.Evilzsoul:BAAALAAECgYIDQAAAA==.Evoked:BAAALAAECgIIAwAAAA==.',Fa='Faeliel:BAAALAADCggICwAAAA==.Falidd:BAAALAADCgEIAQAAAA==.Fanden:BAAALAADCggIDAAAAA==.Fartrellish:BAAALAADCgIIAgAAAA==.Fawcue:BAAALAADCgIIAgAAAA==.Fayell:BAAALAADCgUICAAAAA==.',Fd='Fdk:BAAALAAECgIIAwAAAA==.',Fe='Feathering:BAAALAAECgUIBgAAAA==.Felithlithe:BAAALAADCgQIAwAAAA==.Fernandaa:BAAALAAECgMIAwAAAA==.',Fl='Flameoutt:BAAALAAECgYIDAAAAA==.Fláreon:BAAALAAECgYICwAAAA==.',Fo='Forthill:BAAALAADCgIIAgABLAABCgMIAgABAAAAAA==.',Fr='Frostberries:BAAALAAECgIIAgAAAA==.',Fu='Funkadelic:BAAALAADCgUIBQAAAA==.',['Fà']='Fàmous:BAAALAAECgIIBQAAAA==.',Ga='Galabris:BAAALAAECgMIBAAAAA==.Gamerpogi:BAAALAADCgYICQAAAA==.Gawayn:BAAALAADCgYIBgAAAA==.Gazzik:BAAALAADCgcIDAAAAA==.',Ge='Genny:BAAALAADCgQIBAABLAADCgQIBAABAAAAAA==.Gerion:BAAALAADCgcIBwAAAA==.',Gh='Ghoulmania:BAAALAAECggICAAAAA==.',Gi='Gitchusum:BAAALAADCgEIAQAAAA==.',Gl='Glaedry:BAAALAADCgUIBgAAAA==.Glaivenez:BAAALAAECggICAAAAA==.Glendor:BAAALAADCgYIDQAAAA==.',Go='Gormladin:BAAALAADCgMIAwAAAA==.',Gr='Grief:BAAALAADCgYIAQAAAA==.Grimsreaper:BAAALAADCgMIAgAAAA==.',Gu='Guntherus:BAAALAADCggIDgAAAA==.',Ha='Hairylock:BAAALAADCgIIAgAAAA==.Halfang:BAAALAADCgEIAQAAAA==.Halphas:BAAALAADCgMIAwAAAA==.Hamalvin:BAAALAADCgcIDQAAAA==.',He='Hellscreamx:BAAALAADCgEIAQAAAA==.',Ho='Hobbikeen:BAAALAAECgQIBgAAAA==.Holymana:BAAALAAECgEIAQAAAA==.Holyvyse:BAAALAADCgUIBgAAAA==.Holywielder:BAAALAADCggICAAAAA==.Hoshea:BAAALAAECgYIDQAAAA==.Houzukimaru:BAAALAADCggICAAAAA==.',Hu='Hukak:BAAALAADCgcIDAAAAA==.',Ia='Iakopa:BAAALAADCgMIAwAAAA==.',Ic='Icelord:BAAALAADCgYIBgAAAA==.',Im='Imfiredup:BAAALAAECgcIBQAAAA==.',Iw='Iwasprepared:BAAALAAECgMIBAAAAA==.',Ja='Jacoblack:BAAALAADCggICAAAAA==.Jaefury:BAAALAAECgMIAwAAAA==.',Jo='Johnnypopoff:BAAALAADCggIDwAAAA==.Jojohunts:BAAALAAECgUICQAAAA==.Jonesy:BAAALAAECgYIBgAAAA==.',Ju='Juanjo:BAAALAAECgcIDAAAAA==.Justylln:BAAALAADCggIDgAAAA==.',['Jà']='Jàccuse:BAAALAADCgcICgAAAA==.',Ka='Kaeladra:BAAALAADCgcIBwAAAA==.Kagé:BAAALAADCgIIAgAAAA==.Kait:BAAALAADCgEIAQAAAA==.Kalecrusader:BAAALAAECgUIBQAAAA==.Kamàhl:BAAALAADCgQIBAAAAA==.Kassaalaa:BAAALAAECgIIAgAAAA==.Katdawg:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Kayos:BAAALAADCgEIAQAAAA==.',Ke='Keleira:BAAALAADCgIIAgAAAA==.Kevo:BAAALAADCgYICQAAAA==.',Kh='Khaös:BAAALAADCgMIAwAAAA==.Khristina:BAAALAADCgMIBQAAAA==.',Ki='Kippo:BAABLAAECoEVAAICAAgIchmaCQAOAgACAAgIchmaCQAOAgAAAA==.Kithiri:BAAALAADCggIDgAAAA==.',Ko='Koralie:BAAALAAECgMIBwAAAA==.Koyomí:BAAALAADCgcIBwAAAA==.',Ky='Kyliekat:BAAALAADCggIEQAAAA==.Kyra:BAAALAADCgQIBAAAAA==.',La='Lanceelot:BAAALAADCgYIFgAAAA==.Lanel:BAAALAAECgYIBwAAAA==.Latech:BAAALAADCgYIBgAAAA==.',Le='Leag:BAAALAADCgcICQABLAAECgYIDgABAAAAAA==.',Li='Lifebloom:BAAALAAECgIIAgABLAAFFAIIAgABAAAAAA==.Lightt:BAAALAAECgUICQAAAA==.Lildrinky:BAAALAADCgcIBQAAAA==.Lilnug:BAAALAAECgMIAwAAAA==.Lilstabystab:BAAALAADCgcIBwAAAA==.Lital:BAAALAADCgYIBgAAAA==.Lizbethstar:BAAALAAECgIIAgAAAA==.',Lo='Loryanna:BAAALAADCgQIBwAAAA==.Louie:BAABLAAECoEWAAMDAAgIsSH2AQDhAgADAAgIsSH2AQDhAgAEAAEIIguheQA3AAAAAA==.',Lu='Lunita:BAAALAADCgYIBgAAAA==.',['Lõ']='Lõrs:BAAALAAECgEIAQAAAA==.',['Lø']='Lørs:BAAALAADCgYICQAAAA==.',Ma='Main:BAAALAAECgMIBwAAAA==.Majrmiståke:BAAALAAECgYIDQABLAAECgcIGgAFAI8bAA==.Malantir:BAAALAAECgcIDAAAAA==.Malec:BAAALAADCgIIAgAAAA==.Maliceone:BAAALAADCggICAAAAA==.Manchuryan:BAAALAADCggIEwAAAA==.Mandaryn:BAAALAADCgQIBAAAAA==.Manek:BAAALAADCgQIBwAAAA==.Manthra:BAAALAADCgcIDQAAAA==.Max:BAAALAAECgUICQAAAA==.',Me='Mego:BAAALAADCggICAAAAA==.Mehlar:BAAALAADCggICAAAAA==.Mel:BAAALAADCgMIAwAAAA==.Melancholy:BAAALAADCggIEQAAAA==.Melodae:BAAALAAECgIIAwAAAA==.Mentor:BAAALAAECgIIAwAAAA==.',Mi='Microscratch:BAAALAADCgMIAwABLAAECgUIBgABAAAAAA==.Milan:BAAALAADCgEIAQAAAA==.Milenad:BAAALAADCggIEAAAAA==.Misscleo:BAAALAAECgMIBAAAAA==.',Mn='Mnesarte:BAAALAAECgYIEAAAAA==.',Mo='Mobmagnet:BAAALAAECgcIDQAAAA==.Monia:BAAALAADCgQIAgAAAA==.Monsoon:BAAALAAFFAIIAgAAAA==.Moonkist:BAAALAAECgIIAwAAAA==.Moose:BAAALAAECgYICwAAAA==.Mordácity:BAAALAAECgMIBgAAAA==.Morpheos:BAAALAAECgMIBgAAAA==.Morroe:BAAALAADCgcICgAAAA==.Moxiliz:BAAALAAECgMIBAAAAA==.',My='Mystala:BAAALAAECgEIAQAAAA==.',Ni='Nictolia:BAAALAADCgUIBQAAAA==.',Ny='Nyank:BAAALAAECgEIAQAAAA==.',['Nõ']='Nõ:BAAALAAECgMIAwAAAA==.',Od='Odemon:BAAALAADCgQIBAAAAA==.Odysseus:BAAALAAECgYICAAAAA==.',Ol='Olgann:BAAALAADCgUIBQAAAA==.',Om='Omgowned:BAAALAADCgYIBwAAAA==.',On='Onehothealer:BAAALAADCgUIBgAAAA==.',Op='Opheliastar:BAAALAAECgQICgAAAA==.',Or='Orlucicia:BAAALAAECgIIAgAAAA==.',Pa='Pad:BAAALAAECgIIAwAAAA==.Paedyn:BAAALAADCgQIBAAAAA==.Paladerp:BAAALAAECgYICQAAAA==.Pallyown:BAAALAAECgIIAgAAAA==.Partybus:BAAALAADCggIDwAAAA==.',Pe='Pentandra:BAAALAAECgcIDAAAAA==.',Ph='Phelement:BAAALAAECgMIAwAAAA==.Phoebester:BAAALAADCgIIBAAAAA==.Phonk:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.',Pi='Pimmscup:BAAALAADCgQIBAAAAA==.',Po='Porgoon:BAAALAAECgMIAwAAAA==.',Ra='Radre:BAAALAADCgMIAwAAAA==.Raenya:BAAALAADCggIEAAAAA==.Ramcharger:BAAALAADCgMIAwAAAA==.Rayvin:BAAALAADCggICAAAAA==.',Re='Reanatilax:BAAALAADCgIIAgAAAA==.Redalmighty:BAAALAADCgcIDQAAAA==.Redrûm:BAAALAAECgIIAgAAAA==.Rennara:BAAALAAECgMIBgAAAA==.',Ri='Riddrianna:BAAALAADCggIDgAAAA==.Rikashae:BAAALAADCgUIBQAAAA==.',Ro='Rosebud:BAAALAADCgQIBwAAAA==.',Ru='Ruki:BAAALAADCgcIDAAAAA==.Rumshwizzle:BAAALAADCgQIBAAAAA==.Rune:BAAALAADCggIDQABLAAECgIIAgABAAAAAA==.',Ry='Rylinn:BAAALAADCggIFQAAAA==.',Sa='Salarcyn:BAAALAAECgYIDAAAAA==.Samiracy:BAAALAAECgMIBAAAAA==.Sannrin:BAAALAADCgcICwAAAA==.',Se='Sekk:BAAALAADCgIIAgAAAA==.Serina:BAAALAADCggIDAAAAA==.Sessybeast:BAAALAADCgEIAQAAAA==.Sethrow:BAAALAAECgEIAgAAAA==.',Sh='Shadoh:BAAALAAECggIDgAAAA==.Shamchowda:BAAALAAECgUICgAAAA==.Shammwow:BAAALAADCgcIBwAAAA==.Shamston:BAAALAAECggIAwAAAA==.Shannonesta:BAAALAADCgIIAwAAAA==.Shizatseperi:BAAALAADCggIDwAAAA==.Shortbussin:BAAALAADCgcIBwABLAAFFAIIAgABAAAAAA==.Shylá:BAAALAAECgEIAgAAAA==.',Si='Siley:BAAALAAECgIIAgAAAA==.Sindandor:BAAALAADCgEIAQAAAA==.',Sk='Skarletfaith:BAAALAADCgQIBwAAAA==.',Sn='Sneakysneak:BAAALAAECgIIBQAAAA==.Snooptrogg:BAAALAADCgcIBwAAAA==.',So='Song:BAAALAADCgUIBQAAAA==.',Sp='Specksynder:BAAALAADCgUICAAAAA==.Spiderdk:BAAALAAECgMIBQABLAAECgcIEwABAAAAAA==.',Sq='Squigglefizz:BAAALAADCgQIBAAAAA==.Squishypoo:BAAALAAECgYIDAAAAA==.',Su='Submarinevet:BAAALAADCgYIBAAAAA==.Sugrace:BAAALAADCgQIBAAAAA==.Sunren:BAAALAADCggIEgAAAA==.Superdruidzz:BAAALAADCgcIDQABLAAECgcIGgAFAI8bAA==.Superevokerz:BAABLAAECoEaAAIFAAcIjxsxDQA6AgAFAAcIjxsxDQA6AgAAAA==.Superpallyz:BAAALAAECgIIAgABLAAECgcIGgAFAI8bAA==.Supershamanz:BAAALAADCgUIBQABLAAECgcIGgAFAI8bAA==.',['Sá']='Sáchi:BAAALAAECgIIAgAAAA==.',['Sô']='Sôlmyr:BAAALAADCgYIBgAAAA==.',Ta='Taiynn:BAAALAADCggIDgAAAA==.Taldazlian:BAAALAADCgMIAgAAAA==.Tassadar:BAAALAADCgMIAwAAAA==.',Te='Teleion:BAAALAAECgMIAwAAAA==.Tellinor:BAAALAADCggICAAAAA==.Temporal:BAAALAAECgMIAwAAAA==.Tendie:BAAALAAECgEIAQAAAA==.Teranius:BAAALAADCggIEAAAAA==.Testify:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.',Th='Thaddaues:BAAALAAECgcIEAAAAA==.Thalorn:BAAALAAECgIIAgAAAA==.Theodóre:BAAALAADCgcIDgAAAA==.Theronides:BAAALAADCgMIAwAAAA==.Thralkaz:BAAALAAECgcIDAAAAA==.Thundermace:BAAALAADCggIAQAAAA==.',To='Toeren:BAAALAAECgcIEwAAAA==.Toros:BAAALAADCgEIAQAAAA==.Townsley:BAAALAAECgEIAgAAAA==.',Tr='Triplecanopy:BAAALAADCgQIBAAAAA==.Tristrim:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.',Ty='Tygragon:BAAALAADCggIDwAAAA==.Tyinorin:BAAALAADCgEIAQAAAA==.Tyto:BAAALAADCgEIAQAAAA==.',Tz='Tzipporah:BAAALAADCgcIBwAAAA==.',Ub='Ub:BAAALAAECgMIAwAAAA==.',Ug='Uglyelf:BAAALAAECgIIAgAAAA==.',Un='Uncertainty:BAAALAADCgMIAwABLAADCgcIDAABAAAAAA==.',Va='Vaeellidan:BAAALAADCgcIBwAAAA==.Vainglory:BAAALAADCgEIAQAAAA==.Vantrix:BAAALAAECgEIAQAAAA==.Varabo:BAAALAADCgcIDAAAAA==.Varolina:BAAALAADCgQIBAAAAA==.',Ve='Vehemencê:BAAALAADCgQIBAAAAA==.Velthala:BAAALAAECgEIAQAAAA==.',Vi='Vikymonibags:BAAALAAECgMIAwAAAA==.',Vo='Vosaleana:BAAALAADCgYIBgAAAA==.',Vr='Vraak:BAAALAAECgcIDgAAAA==.',Vu='Vulcus:BAAALAADCggICAABLAAECgcIDgABAAAAAA==.Vulpii:BAAALAADCgYIAgABLAAECgUIBgABAAAAAA==.',Wa='Watcherseye:BAAALAADCgQIBAAAAA==.',We='Weau:BAAALAAECgQIBAAAAA==.',Wh='Whitestain:BAAALAAECgEIAQAAAA==.',Wi='Wiiheal:BAAALAAECgYICQAAAA==.Winions:BAAALAADCgYICwAAAA==.Winterhide:BAAALAADCgcICAAAAA==.Witt:BAAALAADCgIIAgAAAA==.',Wo='Womdalie:BAAALAADCgUIBQAAAA==.Worship:BAAALAAFFAIIAgABLAAFFAIIAgABAAAAAA==.',Xa='Xanthös:BAAALAAECgMIAwABLAAECgcIDgABAAAAAA==.Xavaal:BAAALAADCgEIAQAAAA==.',Xe='Xemnastraza:BAAALAAECgEIAQAAAA==.Xenodozer:BAAALAAECgQICgAAAA==.',Xo='Xolither:BAAALAADCggIIQAAAA==.',Xp='Xpiree:BAAALAADCgUIBwABLAAECgcIFwAFAOYhAA==.',Xs='Xsvoker:BAABLAAECoEXAAIFAAcI5iFbCACeAgAFAAcI5iFbCACeAgAAAA==.',Yo='Youngdip:BAAALAAECgcIBQAAAA==.',Ys='Ysira:BAAALAADCggICAAAAA==.',Ze='Zephymoo:BAAALAAECgYICAAAAA==.Zeyana:BAAALAAECgIIAgAAAA==.',Zh='Zhyonn:BAAALAADCgcIBwAAAA==.',Zi='Ziggië:BAAALAAECgcIDAAAAA==.',Zo='Zoder:BAAALAADCggIEgAAAA==.Zoho:BAAALAAECgMIAwAAAA==.Zoll:BAAALAAECgEIAQAAAA==.Zoose:BAAALAAECgMIBAAAAA==.Zoser:BAAALAAECgMIBAAAAA==.',['Zé']='Zéphyrine:BAAALAADCgUIBQAAAA==.',['Ér']='Érubus:BAAALAADCgUIBQAAAA==.',['ßu']='ßugs:BAAALAAECgQIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end