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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Warrior-Protection',}; local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adem:BAAALAAECgEIAQAAAA==.',Ae='Aelyn:BAAALAADCgcIDgAAAA==.Aevari:BAAALAAECgMIAwAAAA==.Aevelee:BAAALAADCgcIFQAAAA==.',Al='Alahra:BAAALAAECgMIBwAAAA==.Aleeta:BAAALAADCgYIBgAAAA==.Alleriae:BAAALAAECgcIEAAAAA==.Alliecat:BAAALAADCggICAAAAA==.Allucard:BAAALAADCggIDgAAAA==.Alopex:BAAALAAECgYIBwAAAA==.Altusrescari:BAAALAAECgQICgAAAA==.',Am='Amapanda:BAAALAAECgMIBAAAAA==.Amaria:BAAALAAECgUICAAAAA==.',An='Anduîn:BAAALAADCggIEAAAAA==.Angelsdêmon:BAAALAADCgIIAgAAAA==.Angelstörm:BAAALAAECgcIEAAAAA==.Antarias:BAAALAAECgMIBAAAAA==.Antqt:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.',Ap='Apocalypto:BAAALAAECgMIBQAAAA==.',Ar='Aradrys:BAAALAADCgEIAQAAAA==.Arckenon:BAAALAAECgUICAAAAA==.Artimer:BAAALAADCggIDAAAAA==.',Au='Aurros:BAAALAADCggIEAAAAA==.Austenpally:BAAALAADCggIFAAAAA==.',Av='Avalôn:BAAALAAECgEIAQAAAA==.',Ax='Axeflack:BAAALAAECgQIBwAAAA==.',Az='Azerzeal:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Azuka:BAAALAADCgIIAgAAAA==.',Ba='Bacuda:BAAALAAECgMIAwAAAA==.Bahamut:BAAALAADCggICAAAAA==.',Bl='Blackined:BAAALAADCggICAAAAA==.Blindslayer:BAABLAAECoEWAAICAAgIsiBoCQDrAgACAAgIsiBoCQDrAgAAAA==.Bloodrun:BAAALAADCgcICAAAAA==.Bloodtooth:BAAALAADCgYIBwAAAA==.',Bo='Boagriuss:BAAALAAECgcIEAAAAA==.Botia:BAAALAAECgEIAQAAAA==.',Br='Brashmoore:BAAALAAECgUICAAAAA==.Brocken:BAAALAAECgcIDQAAAA==.Brunae:BAAALAAECgIIAwAAAA==.Brunnera:BAAALAADCgcIDQAAAA==.Bruul:BAAALAADCgMIAgAAAA==.',Ca='Caenji:BAAALAAECgEIAQAAAA==.Calcima:BAAALAAECgIIAgAAAA==.Caleigh:BAAALAADCgIIAgAAAA==.Callyn:BAAALAADCgcIEAAAAA==.Cams:BAAALAADCgQIBAAAAA==.Carcharoth:BAAALAADCggIDwAAAA==.',Ch='Chadgar:BAAALAADCggICAAAAA==.Chey:BAAALAAECgcICQAAAA==.Chilai:BAAALAAECgQICAAAAA==.Chipsahoy:BAAALAAECgMIBAAAAA==.Choctaw:BAAALAADCgcIDQAAAA==.Chooka:BAAALAADCggIBwAAAA==.Chíef:BAAALAAFFAEIAQAAAA==.',Ci='Cia:BAAALAADCggICAAAAA==.',Co='Conorix:BAAALAADCggIDwAAAA==.',Cr='Crataxxis:BAAALAAECgYICwAAAA==.Cronga:BAAALAADCgMIAwAAAA==.Crysandra:BAAALAADCgYIDAAAAA==.',Cy='Cydon:BAAALAAECgEIAQAAAA==.',Da='Damienfox:BAAALAADCgcIDQAAAA==.Darrwin:BAAALAAECgMIBwAAAA==.Dasia:BAAALAADCgQIBAAAAA==.Dassem:BAAALAAECgEIAQAAAA==.Dawicker:BAAALAADCgYICgAAAA==.Dawne:BAAALAADCggICAAAAA==.Daylight:BAAALAAECgMIAwAAAA==.Dazarz:BAAALAADCggIDwAAAA==.',De='Deathkrim:BAAALAADCggICAAAAA==.Denero:BAAALAAECgMIAwAAAA==.Desamus:BAAALAAECgMIBAAAAA==.',Di='Dinnu:BAAALAAECgEIAQAAAA==.',Dm='Dmitri:BAAALAAECgcIEgAAAA==.',Dr='Dracthayr:BAAALAAECgYICwAAAA==.Dragonhammer:BAAALAAECgcIDQAAAA==.',Ei='Eitherindel:BAAALAADCgcICAAAAA==.',El='Elderbosco:BAAALAAECgMIBAAAAA==.Elicithy:BAAALAADCgcIBwAAAA==.Eller:BAAALAADCgYICQAAAA==.Ellie:BAAALAAECgcIDwAAAA==.Ellvian:BAAALAADCgYIBgAAAA==.Elseb:BAAALAAECgEIAQAAAA==.',Ev='Everios:BAAALAADCgcIAgAAAA==.Evic:BAAALAADCggICQAAAA==.',Fa='Faeleader:BAAALAAECgMIAwAAAA==.Faevelina:BAAALAAECgIIAwAAAA==.Fartze:BAAALAAECgMIBAAAAA==.',Fe='Felgrrl:BAAALAADCgcIBwAAAA==.',Fi='Fistmaxxing:BAAALAADCggIDAAAAA==.Fizwik:BAAALAAECgcIEAAAAA==.',Fl='Florigrowl:BAAALAADCgcIDQAAAA==.',Fo='Forlo:BAAALAADCggIDAAAAA==.Forrester:BAAALAADCgEIAQAAAA==.',Fr='Frankenkeg:BAAALAADCgcICAAAAA==.',Ga='Galbur:BAAALAAECgcIEAAAAA==.Ganacus:BAAALAADCgcIBwAAAA==.Garras:BAAALAAECgMIAwAAAA==.Gaspode:BAAALAADCgcICwAAAA==.Gassann:BAAALAAECgEIAQAAAA==.',Ge='Geers:BAAALAAECgMIBgAAAA==.Gemkeeper:BAAALAADCggICQAAAA==.Getarage:BAAALAAECgcIDQAAAA==.Getatame:BAAALAADCgcIBwABLAAECgcIDQABAAAAAA==.',Gh='Ghil:BAAALAAECgMIAwAAAA==.Ghoulsnbeans:BAAALAADCgcIBwAAAA==.',Gi='Gildersleeve:BAAALAADCgIIAgAAAA==.Gilia:BAAALAAECgMIAwAAAA==.Girthfist:BAAALAADCggICAABLAAECggIFQADACEjAA==.',Gn='Gnafluug:BAAALAADCgYICwAAAA==.',Gr='Grallia:BAAALAAECgEIAQAAAA==.Graymayn:BAAALAAECgEIAQAAAA==.Grimmthorn:BAAALAAECgIIAwAAAA==.Grumpally:BAAALAAECgcIEAAAAA==.Gryzor:BAAALAADCgcICgAAAA==.',Gu='Gulhwa:BAAALAADCggICAAAAA==.Guloot:BAAALAAECgEIAQAAAA==.Gunboyten:BAAALAAECgEIAQAAAA==.Gunderthirth:BAABLAAECoEVAAIDAAgIISOYAgD9AgADAAgIISOYAgD9AgAAAA==.',Gw='Gwaeniiha:BAAALAAECgEIAQAAAA==.Gward:BAAALAAECgMIAwAAAA==.',Ha='Handsoap:BAAALAAECgIIAwAAAA==.Haquar:BAAALAADCgcIDQAAAA==.',He='Helkite:BAAALAAECgIIAwAAAA==.Hellumph:BAAALAAECgMIAwAAAA==.Hevensrath:BAAALAAECgEIAQAAAA==.',Ho='Hokuden:BAAALAAECgYICwAAAA==.Horsebananas:BAAALAAECgMIAwAAAA==.',Hu='Huddington:BAAALAAECgMIBwAAAA==.',Hy='Hydraness:BAAALAADCgcIBwABLAAECggIFgACALIgAA==.',['Hø']='Hørse:BAAALAADCgcIBwAAAA==.',Il='Illidankk:BAAALAAECgcIDQAAAA==.',Im='Impquisitor:BAAALAAECgMIBAAAAA==.Impthrower:BAAALAADCggIDwABLAAECgYIDAABAAAAAA==.',In='Indy:BAAALAAECgMIBwAAAA==.',Iz='Izomar:BAAALAADCgIIAgABLAAECgYIDAABAAAAAA==.',Ja='Jackieneighs:BAAALAAECgcICwAAAA==.Jackierains:BAAALAADCggIAQABLAAECgcICwABAAAAAA==.Jakku:BAAALAADCgIIAgAAAA==.',Je='Jedîdîah:BAAALAADCggIDwAAAA==.',Ji='Jintao:BAAALAAECgMIBQAAAA==.',Jj='Jjericho:BAAALAADCgcIDQAAAA==.',Jo='Jollachi:BAAALAAECgMIAwAAAA==.',Ju='Jungying:BAAALAADCgYIBgAAAA==.Jutic:BAAALAAECgYICwAAAA==.',Ka='Kaatris:BAAALAADCgcIBwAAAA==.Kageken:BAAALAADCggIEAAAAA==.Kaia:BAAALAAECgMIBQAAAA==.Kalisadora:BAAALAADCgYIBgAAAA==.Kanao:BAAALAAECgcICQAAAA==.Kardas:BAAALAAECgMIBAAAAA==.Kardio:BAAALAAECgcIDAAAAA==.Kayj:BAAALAAFFAEIAQAAAA==.Kayrina:BAAALAADCgcICAAAAA==.',Ke='Kegger:BAAALAAECgEIAQAAAA==.Kekaro:BAAALAADCgYIBgAAAA==.Keylerin:BAAALAAFFAEIAQAAAA==.',Kl='Klepal:BAAALAADCgcICAAAAA==.',Ko='Koharu:BAAALAADCgYIBgAAAA==.Kondred:BAAALAAECgYICwAAAA==.',Kr='Krampus:BAAALAAECgMIBwAAAA==.Kranok:BAAALAAECgIIAwAAAA==.',Ku='Kunac:BAAALAAECgIIAwAAAA==.',Ky='Kynessa:BAAALAADCgcIDQAAAA==.Kyrun:BAAALAADCggIDAAAAA==.',La='Lapz:BAAALAAECgMIAwAAAA==.',Le='Leafboat:BAAALAAECgcIEAAAAA==.Lerel:BAAALAADCgYIBgAAAA==.',Lh='Lhani:BAAALAAECgIIAwAAAA==.',Li='Liljebby:BAAALAADCgIIAgAAAA==.Lirrasha:BAAALAADCgIIAgAAAA==.',Ll='Llyrael:BAAALAAECgEIAQAAAA==.',Lu='Luck:BAAALAAECgcIDgAAAA==.',Ly='Lyrev:BAAALAAECgIIAgAAAA==.',Ma='Maedre:BAAALAADCgcIBwAAAA==.Magnon:BAAALAAECgUIBgAAAA==.Majayjay:BAAALAADCggICAAAAA==.Malaah:BAAALAAECgcIDgAAAA==.Malstruma:BAAALAAECgMIAwAAAA==.Mangojuice:BAAALAAECgMIBAAAAA==.Maochan:BAAALAAECgIIAwAAAA==.Mapachote:BAAALAADCggIFwAAAA==.Maregasm:BAAALAAECgMIBwAAAA==.Marodin:BAAALAADCgcICwAAAA==.Mazboda:BAAALAAECgEIAQAAAA==.',Me='Mekanik:BAAALAADCgQIBAAAAA==.Melectrada:BAAALAAECgEIAQAAAA==.',Mi='Miggydogg:BAAALAAECgYIDwAAAA==.Mileta:BAAALAAECgEIAQAAAA==.Misa:BAAALAADCgYIBgAAAA==.',Mo='Morgorra:BAAALAAECgMIBQAAAA==.Mormekil:BAAALAAECgUICAAAAA==.',['Mô']='Môlly:BAAALAADCggIDgABLAAECgEIAQABAAAAAA==.',Na='Narnluz:BAAALAAECgUICAAAAA==.Natheren:BAAALAADCgQIBAAAAA==.Nayethelor:BAAALAADCggIFgAAAA==.Nazatrat:BAAALAADCgQIBAAAAA==.',Ne='Nebullion:BAAALAAECgIIBwAAAA==.Necroreign:BAAALAAECgQIBgAAAA==.Nelethara:BAAALAAECgcIDwAAAA==.Nessee:BAAALAADCgcIDAAAAA==.',Ni='Nilithis:BAAALAADCgcIBwAAAA==.',Ny='Nyghtchyld:BAAALAADCggIDwAAAA==.',Om='Oman:BAAALAAECgEIAQAAAA==.',Or='Ortalbem:BAAALAAECgYIDAAAAA==.',Os='Oshiwatt:BAAALAADCggIGQABLAAECggIEQABAAAAAA==.',Pa='Parzval:BAAALAADCgUIBQAAAA==.',Pe='Penta:BAAALAADCgcIEwAAAA==.Petflixnkill:BAAALAADCggICAAAAA==.',Ph='Pherix:BAAALAAECgMIAwAAAA==.',Po='Poomacha:BAAALAAECgIIAgAAAA==.',Pu='Puffthemagic:BAAALAAECgEIAQAAAA==.',Py='Pyree:BAAALAAECgMIBwAAAA==.',['Pì']='Pìous:BAAALAADCggIFAAAAA==.',Qu='Quackinblast:BAAALAAECggIDgAAAA==.',Ra='Rahi:BAAALAAECgYICwAAAA==.Rahja:BAAALAADCgcIBwAAAA==.Raifuhogosha:BAAALAAECgEIAQAAAA==.Raistlain:BAAALAAECgUICAAAAA==.Rallsdemon:BAAALAAECgUIBQAAAA==.Ravarath:BAEALAAECgcIEQAAAA==.',Re='Reldarus:BAEALAAECgMIBwAAAA==.Rellor:BAAALAADCggICAAAAA==.Rena:BAAALAAECgcIDQAAAA==.Revilation:BAAALAADCggICAAAAA==.Rezzyk:BAAALAAECgIIAwAAAA==.',Rh='Rhonus:BAAALAADCgQIBAAAAA==.',Ri='Rickosuave:BAAALAADCggICQAAAA==.Riidefi:BAAALAADCgcIBwAAAA==.Riis:BAAALAADCgcIDQAAAA==.Rikon:BAAALAAECgEIAQAAAA==.',Sa='Saevus:BAAALAADCgcICAAAAA==.Sagerremeseb:BAAALAADCgcIDQAAAA==.Sakarias:BAAALAADCgUIBQAAAA==.Sakii:BAAALAAECgMIAwAAAA==.Samvimes:BAAALAAECgIIAgAAAA==.Sangreene:BAAALAAECgUIBgAAAA==.Saradorina:BAAALAAECgEIAQAAAA==.Sargis:BAAALAAECgYICgAAAA==.',Sc='Schrödinger:BAAALAADCgYIBgAAAA==.Schwarzwölf:BAAALAAECgMIBgAAAA==.',Sh='Shadowbrooks:BAAALAAECgEIAQAAAA==.Shagol:BAAALAAECgMIAwAAAA==.Shalriss:BAAALAAECgIIAwAAAA==.Shalue:BAAALAAECgIIAgAAAA==.Shamemoon:BAAALAAECgIIAwAAAA==.Shamunroe:BAAALAAECgMIBwAAAA==.Shatterhoof:BAAALAAECgEIAQAAAA==.Shayhara:BAAALAADCgcICwAAAA==.Shelle:BAAALAADCgcIDQAAAA==.Shingra:BAAALAAFFAEIAQAAAA==.Shiory:BAAALAADCgcIDQAAAA==.Shotdwn:BAAALAADCggIDgAAAA==.',Si='Sinz:BAAALAAECgQIBAAAAA==.',Sk='Skeevés:BAAALAAECgIIAgAAAA==.Skillidan:BAAALAAECgUICAAAAA==.Skær:BAAALAAECgYICQAAAA==.',Sl='Slighttrash:BAAALAAECgMIAwAAAA==.Slöppy:BAAALAADCgcICAAAAA==.',Sm='Smallcrow:BAAALAAECggIDwAAAA==.',Sn='Snowsong:BAAALAADCgQIBAAAAA==.',So='Souleaterr:BAAALAAECgMIDAAAAA==.',Sp='Spamton:BAAALAADCgcIBwAAAA==.Spaz:BAAALAAECgQIBgAAAA==.Spheredfrog:BAAALAAECgIIAwABLAAECgMIBQABAAAAAA==.',St='Starge:BAAALAAECgMIBgAAAA==.Starre:BAAALAADCgcIBwAAAA==.Steffey:BAAALAAECgEIAQAAAA==.Steveholt:BAAALAADCgEIAQAAAA==.Sturgeson:BAAALAAFFAEIAQAAAA==.',Su='Sulabal:BAAALAAECgEIAQAAAA==.Sulwen:BAAALAAECgcIDgAAAA==.Superjail:BAAALAADCgcICAAAAA==.',Sw='Sweatysarah:BAAALAADCgcIDgAAAA==.Swiftfeet:BAAALAAECgUICAAAAA==.',Sy='Sy:BAAALAAECgQIBwAAAA==.',['Sé']='Sésho:BAAALAADCgcIBwAAAA==.',['Sö']='Söranin:BAAALAADCgcICQAAAA==.',Ta='Taeili:BAAALAAECgMIAwAAAA==.Tanequil:BAAALAAECgcIEAAAAA==.Taurbolt:BAAALAADCgYIBgAAAA==.',Te='Techromancer:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Tedd:BAAALAADCgIIAgAAAA==.',Th='Thantasia:BAAALAADCgYICQAAAA==.Thorden:BAAALAADCgIIAgAAAA==.Thoughtfull:BAAALAADCgUIBQAAAA==.Thunderbane:BAAALAAECgcICAAAAA==.',Ti='Timothy:BAAALAAECgMIBAAAAA==.Timpany:BAAALAAECgYICwAAAA==.Tinkphooey:BAAALAAECgMIAwAAAA==.',To='Toklore:BAAALAADCgEIAQABLAADCgcIBwABAAAAAA==.Tonepavone:BAAALAAECgUICAAAAA==.',Tr='Traazz:BAAALAADCgMIAwAAAA==.',Ts='Tsuruga:BAAALAAECgMIBgAAAA==.',Tu='Turkwise:BAAALAAECgUICAAAAA==.',Tw='Twists:BAAALAADCgcIEAAAAA==.',Ul='Ulodude:BAAALAADCgcICAAAAA==.',Va='Valton:BAAALAAECgcIEAAAAA==.Vancede:BAAALAAECgYIDAAAAA==.',Ve='Vendettas:BAAALAADCgYIBgAAAA==.Vestrae:BAAALAAECgcIEAAAAA==.',Vi='Vilten:BAAALAADCggICAAAAA==.',Vo='Volkatz:BAAALAAECgYICwAAAA==.Vostok:BAAALAAECgUICAAAAA==.',['Vä']='Väder:BAAALAADCggICAAAAA==.',Wa='Warranni:BAAALAAECgIIAwAAAA==.',Wh='Whatafox:BAAALAAECgMIBAAAAA==.',Wi='Wikket:BAAALAAECgMIBQAAAA==.',Wr='Wrax:BAAALAADCgYICQAAAA==.',Wy='Wynono:BAAALAADCgMIAwAAAA==.',Xa='Xalttar:BAAALAADCgIIAgAAAA==.',Xc='Xcassandra:BAAALAADCgEIAQAAAA==.',Xe='Xeritos:BAAALAADCgcIEAAAAA==.Xerond:BAAALAAECgMIAwAAAA==.',Xu='Xulec:BAAALAADCgcIFQAAAA==.',Ye='Yeah:BAAALAAECgMIAwAAAA==.',Yu='Yuji:BAAALAAECgIIAgAAAA==.',Za='Zarisedra:BAAALAAFFAEIAQAAAA==.',Ze='Zerdah:BAAALAADCgQIBAAAAA==.Zernacho:BAAALAAECgUICAAAAA==.Zevvo:BAAALAAECgIIBAAAAA==.',Zo='Zouup:BAAALAADCgEIAQAAAA==.',Zu='Zuganova:BAAALAAFFAEIAQAAAA==.Zuzuzuzuzuzu:BAAALAADCgcIBwAAAA==.',['Às']='Àshaman:BAAALAAECgMIBAAAAA==.',['Ëd']='Ëdën:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end