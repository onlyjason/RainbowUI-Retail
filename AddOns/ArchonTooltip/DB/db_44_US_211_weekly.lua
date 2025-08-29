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
 local lookup = {'Warrior-Fury','Unknown-Unknown','Druid-Balance','Monk-Windwalker','Druid-Restoration','Druid-Feral',}; local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Achooe:BAAALAAECgMIBAAAAA==.',Ad='Adversity:BAABLAAECoEWAAIBAAgIliO1BAAkAwABAAgIliO1BAAkAwAAAA==.',Ae='Aevint:BAAALAAECgIIAwAAAA==.Aevintz:BAAALAADCgcIBwAAAA==.',Ag='Agathorz:BAAALAAECgMIAwAAAA==.',Ai='Aiur:BAAALAADCggIDQAAAA==.',Ak='Akyra:BAAALAADCggIEgAAAA==.',Al='Alacer:BAAALAADCgIIAgABLAAECgYIDwACAAAAAA==.Aladia:BAAALAADCgEIAQAAAA==.Alatáriel:BAAALAAECgUICQAAAA==.Alexx:BAAALAAECgMIBAAAAA==.Allexisana:BAAALAAECgIIAgAAAA==.',An='Anaraith:BAAALAAECgEIAQAAAA==.Anastazia:BAABLAAECoEVAAIDAAgIxxuUCQCVAgADAAgIxxuUCQCVAgAAAA==.Andlindvis:BAAALAADCggICgAAAA==.Anejo:BAAALAADCgEIAQAAAA==.Anilex:BAAALAADCgcIDAAAAA==.Anjerial:BAAALAADCgYICQABLAAECgMIAwACAAAAAA==.Anul:BAAALAADCggICAAAAA==.',Ao='Aohikari:BAAALAAFFAIIAgAAAA==.',Ap='Aprigity:BAAALAADCgcIBwAAAA==.',Ar='Arashinigon:BAAALAAECgEIAQAAAA==.Argoroth:BAAALAAECgMIBQAAAA==.Ariandise:BAAALAAECgYICgAAAA==.Arick:BAAALAAECgEIAQAAAA==.Arili:BAAALAAECgEIAQAAAA==.Ark:BAAALAAECgcIEAAAAA==.',At='Atemporal:BAAALAADCggICQAAAA==.',Au='Aureia:BAAALAADCggICAABLAAECggIEwACAAAAAA==.Auriea:BAAALAAECggIEwAAAA==.',Ba='Balatro:BAAALAADCgMIAwAAAA==.',Be='Beezuldonut:BAAALAADCggICwAAAA==.Belgaron:BAAALAAECgQIBwAAAA==.Belmaris:BAAALAAECgMIBAAAAA==.Beng:BAAALAADCggIDwAAAA==.',Bi='Bigcupcakes:BAAALAADCgcIBwAAAA==.Bigdaddykong:BAAALAAECgEIAQAAAA==.Bill:BAAALAADCgMIAwAAAA==.',Bl='Blasteyes:BAAALAADCgYICQAAAA==.',Bo='Borik:BAAALAAECgIIAgAAAA==.Borknagar:BAAALAADCgcIBwAAAA==.',Br='Brenor:BAAALAAECgIIAgAAAA==.Brighteye:BAAALAAECgQIBAAAAA==.Brittany:BAAALAADCgYIBgAAAA==.Brotherpsy:BAAALAAECgEIAQAAAA==.',Bu='Buckme:BAAALAADCggIDAAAAA==.Builttoheal:BAAALAAECgQICQAAAA==.Bukayo:BAAALAADCgMIAwAAAA==.Bulova:BAAALAADCggICAAAAA==.Busby:BAAALAADCggICAAAAA==.',Ca='Caco:BAAALAAECgYIDgAAAA==.Caiphage:BAAALAAECgYIDAAAAA==.Caladelm:BAAALAAECgUIBwAAAA==.Calipally:BAAALAAECgYIDQAAAA==.Calirri:BAAALAADCgMIAwAAAA==.Caralhan:BAAALAAECgEIAQAAAA==.',Ce='Cedra:BAAALAAECgQIBwAAAA==.Cegeo:BAAALAAECgYIBwAAAA==.',Ch='Cheepdeeps:BAAALAAECgYIDAAAAA==.Chrisdeath:BAAALAADCgQIBAAAAA==.',Ci='Ciell:BAAALAAECgYICAAAAA==.Ciennajewel:BAAALAAECgIIAgAAAA==.Cirdle:BAAALAADCggIFAAAAA==.',Co='Cocasmoka:BAAALAAECgYIBwAAAA==.Coletta:BAAALAAECgEIAQAAAA==.',Cr='Craytos:BAAALAAECgIIAgAAAA==.Crystyl:BAAALAAECgMIAwAAAA==.',Cy='Cyia:BAAALAADCgMIAwABLAAECgMIAwACAAAAAA==.',Da='Daddy:BAAALAAECgYIDwAAAA==.Danir:BAAALAADCgMIBgAAAA==.Darayia:BAAALAADCgMIAwAAAA==.Darkcarnival:BAAALAAECgMIBAAAAA==.Darkeone:BAAALAADCggICAAAAA==.Darkknightx:BAAALAAECgYIEAAAAA==.Darkphoenixx:BAAALAAECgIIAwAAAA==.Darktotems:BAAALAADCgUIBwAAAA==.Davrøs:BAAALAAECgMIAwAAAA==.',De='Deaddshot:BAAALAADCgQIAQAAAA==.Deathbae:BAAALAADCgIIAgAAAA==.Deemon:BAAALAAECgMIBQAAAA==.Dehaka:BAAALAADCgEIAQAAAA==.Delathatha:BAAALAADCgQIBAAAAA==.Demiish:BAAALAAECgMIAwAAAA==.Denedin:BAAALAAECgcIEAAAAA==.Denidan:BAAALAADCgMIAwAAAA==.Desdemona:BAAALAAECgMIAwAAAA==.',Do='Dominathan:BAAALAAECgMIAwAAAA==.Doomace:BAAALAADCggICwAAAA==.',Dr='Dragon:BAAALAADCgQIBAAAAA==.Dragpie:BAAALAADCgMIAwAAAA==.Driftyshaman:BAAALAADCgcIFQAAAA==.Drzalot:BAAALAAECgUICQAAAA==.Dræghoule:BAAALAAECgMIAwAAAA==.',Du='Durrgen:BAAALAAECgYICAAAAA==.',Dy='Dyamï:BAAALAAECgMIBQAAAA==.Dysko:BAAALAADCgcICwAAAA==.',Ed='Edrik:BAAALAAECgQIBAAAAA==.',Eg='Eglosira:BAAALAADCgUIBAAAAA==.',El='Elbuhero:BAAALAADCgcIBwAAAA==.Elrythe:BAAALAAECgcIDgAAAA==.Elviric:BAAALAADCgQIBAAAAA==.',Em='Emmandreyn:BAAALAAECgcIDgAAAA==.Emmawatsonqt:BAAALAADCgcIBwAAAA==.',Er='Erika:BAAALAADCgEIAQAAAA==.',Es='Esjho:BAAALAADCgYIDAAAAA==.',Ev='Everfloof:BAAALAAECgYIDgAAAA==.',Ew='Ewiyar:BAAALAAECgYIDAAAAA==.',Fa='Faced:BAAALAADCgQIBQAAAA==.Fahari:BAAALAAECgIIAwAAAA==.',Fe='Felebash:BAAALAAECgIIAgAAAA==.Felknar:BAAALAAECgQIBgAAAA==.',Fi='Fistdaddy:BAAALAAECgYIDAAAAA==.',Fl='Flexmetallo:BAAALAAECgQIBgAAAA==.Floofies:BAAALAAECgYIEAAAAA==.Floofyfu:BAAALAAECgIIAwAAAA==.',Fr='Fredrickk:BAAALAADCgIIAgABLAAECgYICgACAAAAAA==.Froza:BAAALAADCgYIBwABLAAECgYIDwACAAAAAA==.Frubar:BAAALAAECgYICQAAAA==.',Fu='Funhao:BAAALAADCgUIBQAAAA==.Furryphase:BAAALAAECgQIBAAAAA==.',Gh='Gherkinn:BAAALAAECgcIDgAAAA==.Gherkkin:BAAALAADCggIDQABLAAECgcIDgACAAAAAA==.',Gi='Gilin:BAAALAAECgUICQAAAA==.',Gl='Glaur:BAAALAAECgEIAQAAAA==.',Go='Goatastica:BAAALAAECgQIBgAAAA==.',Gr='Greyblade:BAAALAADCgUIBQAAAA==.Grimalkin:BAAALAADCgYIBgAAAA==.Gripisrdy:BAAALAAECgMIBAAAAA==.Grunch:BAAALAADCgcIBwAAAA==.',Gu='Guldon:BAAALAADCgYIBgAAAA==.Gunslingr:BAAALAAECgMIBgAAAA==.Gusgus:BAAALAADCggIEAAAAA==.',['Gü']='Günzz:BAAALAAECgMIAwAAAA==.',Ha='Halleberries:BAAALAAECgYICwAAAA==.Halowendy:BAAALAAECgQIBgAAAA==.Hartnello:BAAALAADCgYIBgAAAA==.',He='Headaches:BAAALAADCggIDgAAAA==.Heartshot:BAAALAADCgUIBQAAAA==.Helly:BAAALAAECgYIDAAAAA==.',Hi='Hime:BAAALAAECgMIBAAAAA==.',Ho='Holyarceus:BAAALAAECgIIAgAAAA==.Hosemachine:BAAALAAECgUIBQAAAA==.',Hr='Hruggul:BAAALAADCgUIBgABLAAECgYIBwACAAAAAA==.',Hu='Huntzors:BAAALAADCggICAAAAA==.',In='Inside:BAACLAAFFIEFAAIEAAMIWiG9AAAyAQAEAAMIWiG9AAAyAQAsAAQKgRcAAgQACAgeJP4BACoDAAQACAgeJP4BACoDAAAA.',Ir='Ireko:BAAALAAECgMIAwAAAA==.',Iz='Izznix:BAAALAAECgUICQAAAA==.',Ja='Jadde:BAAALAADCgMIAwAAAA==.Jadienne:BAAALAAECgMIBQAAAA==.Jasmind:BAAALAAECgYICgAAAA==.',Je='Jee:BAAALAADCgcIBwAAAA==.Jevi:BAAALAADCgQIBAAAAA==.Jevibooz:BAAALAADCggICAAAAA==.',Jo='Joanna:BAAALAAECgEIAQAAAA==.Joecool:BAAALAAECgMIBAAAAA==.Johnnyboy:BAAALAADCgcIEQAAAA==.Joner:BAAALAAECgcIDQAAAA==.Joss:BAAALAADCggIEAAAAA==.',Ka='Kadan:BAAALAAECgYIDwAAAA==.Kadilan:BAAALAADCggICAAAAA==.Kahlan:BAAALAAECgUIBwAAAA==.Kahless:BAAALAADCgcIBwAAAA==.Kakwaa:BAAALAAECgQIBwAAAA==.Kalipo:BAAALAADCgQIBAAAAA==.Kattrin:BAAALAADCgMIBQAAAA==.',Ke='Keenin:BAAALAAECgQIBgAAAA==.Keyadistor:BAAALAAECgIIAgAAAA==.',Kh='Khaarim:BAAALAAECgMIAwAAAA==.Khareese:BAAALAAECggIEAAAAA==.Khazorin:BAAALAAECgIIAwAAAA==.',Ki='Kiamara:BAAALAAECgMIAwAAAA==.Kinderlin:BAAALAAECgMIAwAAAA==.',Ko='Kolgan:BAAALAADCgcICAAAAA==.Korstruck:BAAALAAECgcIDQAAAA==.',Kr='Kraggnarr:BAAALAADCgQIBAAAAA==.Kravvelocity:BAAALAAECgcIDQAAAA==.Krelix:BAAALAAECgMIAwAAAA==.Krendis:BAAALAAECgYICAAAAA==.',['Ká']='Káz:BAAALAAECggIEQAAAA==.',La='Laguerre:BAAALAAECgQIBgAAAA==.Laksa:BAAALAADCgUIBQABLAAECgYIDAACAAAAAA==.Lancaban:BAAALAADCgcIEQAAAQ==.Laojin:BAAALAADCgIIAgAAAA==.',Li='Lifeispain:BAAALAADCgYIAwAAAA==.Liniara:BAAALAADCggIEAAAAA==.',Lo='Loaldan:BAAALAAECgEIAQAAAA==.Lockedin:BAAALAAECgQIBwAAAA==.Lokung:BAAALAAECgUICAAAAA==.Lolbolt:BAAALAADCgYIBgAAAA==.',Lu='Lucianas:BAAALAAECgEIAQAAAA==.',Ly='Lycàn:BAAALAADCgIIAgAAAA==.',Ma='Madaea:BAAALAADCggIEAAAAA==.Madameuyen:BAAALAADCgMIAwAAAA==.Madlyn:BAAALAADCgYIBwAAAA==.Madrigal:BAAALAAECgQIBQAAAA==.Magepuppy:BAAALAAECgIIAwAAAA==.Malholis:BAAALAAECgIIAgAAAA==.Marrilyn:BAABLAAECoEWAAQFAAgIFxYeFQDOAQAFAAgIFxYeFQDOAQADAAYIABtmGADHAQAGAAIIMw/tGABsAAAAAA==.Mashbrownie:BAAALAAECgQIBgAAAA==.Matagi:BAAALAAECgIIAwAAAA==.Maxxine:BAAALAAECgMIBAAAAA==.',Me='Meatloaf:BAAALAADCgEIAQAAAA==.Melbeast:BAAALAADCggIFgAAAA==.Melorea:BAAALAAECgEIAQAAAA==.Merdin:BAAALAAECgEIAQAAAA==.Merlock:BAAALAAECgEIAQAAAA==.Metricdotem:BAAALAADCgUIBQAAAA==.',Mi='Miloughah:BAAALAADCgcICQAAAA==.Missiah:BAAALAAECgMIAwAAAA==.',Mo='Moldybread:BAAALAADCgIIAgAAAA==.Molfise:BAAALAAECgUICQAAAA==.Moofazza:BAAALAAECgMIAwAAAA==.Moonarrow:BAAALAAECgMIAwAAAA==.Moonfell:BAAALAAECgMIBQAAAA==.Moonlight:BAAALAADCggIEgAAAA==.Moonlilly:BAAALAADCggIFgAAAA==.Moonstab:BAAALAAECgEIAQAAAA==.Morena:BAAALAADCgcIBwAAAA==.Morin:BAAALAADCgcIFQAAAA==.',My='Mylilhunter:BAAALAAECgMIBAAAAA==.Mysticrainne:BAAALAADCggIEwAAAA==.',Na='Nachtelf:BAAALAAECgYIDAAAAA==.Nagan:BAAALAAECgIIAwAAAA==.Natadawn:BAAALAAECgYIDAAAAA==.Natadusk:BAAALAADCggIDgAAAA==.',Ni='Nirra:BAAALAAECgIIAgAAAA==.',No='Noctrediiran:BAAALAADCgYIBwAAAA==.Nonphatmilk:BAAALAADCgMIAwAAAA==.Notoriginal:BAAALAAECgYIDAAAAA==.',Om='Omee:BAAALAAECgMIAwAAAA==.Omgwolves:BAAALAAECgYIDgAAAA==.Omnislasher:BAAALAAECgEIAQAAAA==.Omy:BAAALAAECgEIAQAAAA==.',Or='Orioncheats:BAAALAAECgIIAwAAAA==.',Ov='Overpwerd:BAAALAADCgcIEwAAAA==.',Ow='Owo:BAAALAAECgEIAQAAAA==.',Pa='Paladingbat:BAAALAADCggIDAAAAA==.Palomita:BAAALAADCgcICQAAAA==.Pandabell:BAAALAADCgIIAgAAAA==.Paoldi:BAAALAAECgIIAwAAAA==.Paranoia:BAAALAADCgMIAwAAAA==.Pasghetti:BAAALAADCggICAAAAA==.',Pe='Ped:BAAALAAECgIIAwAAAA==.',Ph='Pharune:BAAALAAECgMIBAAAAA==.Pheromoan:BAAALAADCggICAAAAA==.',Pl='Pluto:BAEALAAECggIAQAAAA==.',Po='Poisyn:BAAALAAECgYICQAAAA==.Post:BAAALAADCggIDgAAAA==.Postmortym:BAAALAADCgEIAQAAAA==.',Pr='Procalypse:BAAALAAECgYICQAAAA==.Provoker:BAAALAAECgYICQAAAA==.',Ps='Psykoo:BAAALAAECgQIBAAAAA==.',['Pä']='Pängari:BAAALAAECgMIBQAAAA==.',Qe='Qee:BAAALAADCgIIAgAAAA==.',Qu='Quattro:BAAALAAECgMIAwAAAA==.',Ra='Raestia:BAAALAADCgYIDAAAAA==.Raivyn:BAAALAAECgQIBAABLAAECgQIBwACAAAAAA==.Raylaira:BAAALAADCgcIEQAAAA==.',Re='Remulis:BAAALAAECgMIBAAAAA==.Reposado:BAAALAADCgcIDQAAAA==.Rethyrian:BAAALAADCggIFgAAAA==.Revelare:BAAALAAECgMIBAAAAA==.Rexbi:BAAALAAECgUIBwAAAA==.',Rh='Rhylee:BAAALAADCgUIBgAAAA==.',Ri='Rianne:BAAALAAECgUICAAAAA==.Riffru:BAAALAADCgQIAQAAAA==.',Ro='Rockyevoker:BAAALAAECgUIBwAAAA==.Rockyhunterr:BAAALAADCgYIBgAAAA==.Rooth:BAAALAAECgUICQAAAA==.Rowdan:BAAALAADCgcIBwAAAA==.',Ru='Rubï:BAAALAAECgIIAgAAAA==.Rugiia:BAACLAAFFIEFAAIFAAMIUCauAABcAQAFAAMIUCauAABcAQAsAAQKgRgAAgUACAhlJkUAAHMDAAUACAhlJkUAAHMDAAAA.Rustinpieces:BAAALAAECgUIBQAAAA==.Rustycupp:BAAALAAECgMIAwAAAA==.',Ry='Ryleth:BAAALAADCgcIBwAAAA==.Ryvoker:BAAALAADCgEIAQAAAA==.',Sa='Sabindeus:BAAALAAECgQIBgAAAA==.Samedi:BAAALAAECgMIAwAAAA==.Sandwich:BAAALAADCgMIAwAAAA==.Sanguinius:BAAALAADCgQIBAAAAA==.Sarissa:BAAALAAECgIIAgAAAA==.Sathanas:BAAALAAECgMIBgAAAA==.Satyaru:BAAALAAECgUIBwAAAA==.',Se='Secretbear:BAAALAAECgMIBgAAAA==.Selarra:BAAALAAECgYIBwAAAA==.',Sh='Shabalaba:BAAALAAECgcIDwAAAA==.Shadowdancèr:BAAALAAECgUICQAAAA==.Shaiden:BAAALAAECgQIBgAAAA==.Shatõ:BAAALAAECggIDgAAAA==.',Si='Sibella:BAAALAAECgQIBgAAAA==.',Sk='Skoto:BAAALAAECgMIBQAAAA==.',Sl='Slambamwhoo:BAAALAAECgYICQAAAA==.',Sm='Smallheals:BAAALAAECgMIAwAAAA==.Smoochybooty:BAAALAADCgcIBwAAAA==.',So='Solnar:BAAALAAECgQIBwAAAA==.',St='Stache:BAAALAADCggICAAAAA==.Starii:BAAALAAECgMIAwAAAA==.',Su='Suffer:BAAALAADCgEIAQAAAA==.',Sw='Switchgidget:BAAALAADCgMIAwAAAA==.',Sy='Sylvenna:BAAALAADCggIDgAAAA==.Syngy:BAAALAADCgUIBgAAAA==.',Ta='Taintedkoma:BAAALAADCgYIBwAAAA==.Tastesgreat:BAAALAAECgIIAgAAAA==.Taurenator:BAAALAAECgcIEAAAAA==.',Te='Temajin:BAAALAADCgQIBAAAAA==.Teranidas:BAAALAADCgcIEQAAAA==.Teron:BAAALAAECgMIAwAAAA==.Tesh:BAAALAADCgMIAwAAAA==.',Th='Thaea:BAAALAAECgQIBAAAAA==.Thallor:BAAALAADCgUIBQAAAA==.Tharjin:BAAALAADCgYIBgAAAA==.Thasun:BAAALAADCggIDgAAAA==.Thelawl:BAAALAADCgcIBwAAAA==.Themyscira:BAAALAAECgYIBgAAAA==.Theonorf:BAAALAAECgQICgAAAA==.Thewarrior:BAAALAAECgMIAwAAAA==.Thiccimus:BAAALAADCgIIAgAAAA==.',To='Toxx:BAAALAADCgEIAQAAAA==.',Tr='Tristyana:BAAALAAECgYIDAAAAA==.',Ts='Tsiddahn:BAAALAADCgcIBwAAAA==.Tsubasa:BAAALAAECgEIAQABLAAFFAIIAgACAAAAAA==.Tsuki:BAAALAAECgYIBgABLAAFFAIIAgACAAAAAA==.Tsunâde:BAAALAAECgYIDAAAAA==.',Tu='Tungpo:BAAALAADCgMIAwAAAA==.',Ty='Tylurien:BAAALAAECgMIBAAAAA==.',Ul='Ultima:BAAALAAECgcIDQAAAA==.',Ur='Urbanprey:BAAALAADCgYICQAAAA==.Ursa:BAAALAAECgMIBAAAAA==.',Va='Valkoinen:BAAALAAECgQIBwAAAA==.Valora:BAAALAAECgYIDAAAAA==.Vargen:BAAALAAECgMIAwAAAA==.Vayla:BAAALAAECgQIBAAAAA==.',Ve='Vergil:BAAALAAECgUIBQAAAA==.Vespertina:BAAALAAECgQIBgAAAA==.Vexari:BAAALAADCgYIBgAAAA==.',Vi='Virti:BAAALAAECgYIDAAAAA==.',Vu='Vula:BAAALAAECgIIAwAAAA==.',Wa='Wardancer:BAAALAADCgcIBwAAAA==.Warspriest:BAAALAAECgMIBAAAAA==.Warwizard:BAAALAAECgcIDgAAAA==.',Wh='Whiisper:BAAALAAECgcIBwAAAA==.',Wi='Wickedywaque:BAAALAADCgMIAwAAAA==.Wilnas:BAAALAAECgMIAwABLAAECgYIDAACAAAAAA==.Wilshammy:BAAALAADCgIIAgAAAA==.Wisper:BAAALAAECgMIBAABLAAECgcIBwACAAAAAA==.Wispy:BAAALAAECgYICQAAAA==.Wisè:BAAALAADCgcIBwAAAA==.',Wr='Wrathbarrage:BAAALAAECgMIAwABLAAECgYICQACAAAAAA==.Wrathbourne:BAAALAAECgYICQAAAA==.',Xa='Xandï:BAAALAAECgYIDgAAAA==.',Xe='Xebryo:BAAALAAECgIIAwAAAA==.',['Xè']='Xèrlyn:BAAALAAECgUIBQAAAA==.',Ya='Yazoth:BAAALAADCgEIAQAAAA==.Yazoura:BAAALAADCggIDgAAAA==.',Ye='Yenko:BAAALAADCgcIBwAAAA==.',Yo='Yookock:BAAALAADCgcIBwAAAA==.',Za='Zallyrael:BAAALAAECgIIAwAAAA==.Zarumaz:BAAALAADCgUIBQAAAA==.',Ze='Zeddiccus:BAAALAAECgMIBQAAAA==.Zerozza:BAAALAADCggIFAAAAA==.Zevur:BAAALAAECgYICwAAAA==.',Zi='Ziden:BAAALAAECgIIAgAAAA==.',Zz='Zztatsuya:BAAALAAECgMIBAAAAA==.',['Ér']='Éric:BAAALAAECgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end