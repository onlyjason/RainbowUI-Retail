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
 local lookup = {'Unknown-Unknown','Monk-Windwalker','Mage-Frost','Druid-Restoration','Evoker-Devastation','Priest-Holy','Warrior-Fury','DemonHunter-Havoc',}; local provider = {region='US',realm='Elune',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Aceofspade:BAAALAAECggICAAAAA==.',Ai='Aib:BAAALAAECgcIDQAAAA==.Aio:BAAALAAECgYIBwAAAA==.',Ak='Akashah:BAAALAAECgcIEAAAAA==.Aknologia:BAAALAAECgEIAQABLAAECgIIBAABAAAAAA==.Akshân:BAAALAADCggIDwAAAA==.Aku:BAAALAADCgUIBgAAAA==.',Al='Alarick:BAAALAAECgYIDQAAAA==.Alatha:BAAALAADCgcIEQAAAA==.Alathea:BAAALAAECgMIAwAAAA==.Albumin:BAAALAAECgYICwAAAA==.Aledis:BAAALAAECgcIEAAAAA==.Aliang:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.Allanøn:BAAALAADCggIDwAAAA==.Alliria:BAAALAAECgMIAwAAAA==.Almuqit:BAAALAAECgQIBwAAAA==.Alyrical:BAAALAAECgMIAwAAAA==.',Am='Amowrath:BAAALAAECgQIBwAAAA==.Amyasia:BAAALAAECgcIDgAAAA==.Amára:BAAALAAECgYIDAAAAA==.',An='Andarnaurram:BAAALAAECgEIAQAAAA==.Ankin:BAAALAAECgEIAQAAAA==.Anom:BAAALAAECgMIAwAAAA==.Antipode:BAAALAAECgIIBAAAAA==.',Ap='Apocaliss:BAAALAADCggIDwAAAA==.',Ar='Aradoa:BAAALAAECgMIBQAAAA==.Aranya:BAAALAADCggICQAAAA==.Arashin:BAAALAAECgEIAQAAAA==.Arelaena:BAAALAAECgEIAQAAAA==.Ark:BAAALAAECgIIBAAAAA==.Aruune:BAAALAADCggICAAAAA==.',As='Aster:BAAALAADCgcIBwAAAA==.Asthenn:BAAALAADCgYIBwAAAA==.Astreae:BAAALAAECgYICgAAAA==.Astreri:BAAALAAECgYICQAAAA==.',Av='Avi:BAAALAAECgMIAwAAAA==.',Ay='Ayekillu:BAAALAAECgEIAQAAAA==.Ayiasofia:BAAALAAECgcIDQAAAA==.Ayire:BAAALAAECgQIBgAAAA==.Aylan:BAAALAAECgUICAAAAA==.Ayumfox:BAAALAADCggIEwAAAA==.',Az='Aztez:BAAALAAECgIIAgAAAA==.Azureshal:BAAALAAECgMIAwAAAA==.',Ba='Bacamarte:BAAALAAECgYICgAAAA==.Badger:BAAALAAECgYICwAAAA==.Baelfrost:BAAALAADCggIDgABLAAECgIIBAABAAAAAA==.Balloon:BAAALAADCggIDQAAAA==.Bandâid:BAAALAADCgcIDAABLAADCgcIDQABAAAAAA==.Barathiel:BAAALAAECgcIDgAAAA==.Baryll:BAAALAAECgIIBAAAAA==.Baulde:BAAALAAECgYICwAAAA==.',Be='Bellne:BAAALAAECgMIBAAAAA==.Bezalel:BAAALAAECgQIBAAAAA==.',Bi='Bigflavor:BAAALAAECgEIAgAAAA==.Bimbi:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.',Bl='Bllass:BAAALAADCgYIBgAAAA==.Blush:BAAALAADCggIFQAAAA==.',Bo='Boiledfrogz:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.Boomfuzz:BAAALAAECgMIAwAAAA==.',Br='Bralder:BAAALAAECgEIAQAAAA==.Briset:BAAALAAECgMIAwAAAA==.',Bu='Buffiey:BAAALAADCgcIBwAAAA==.',Ca='Cait:BAAALAAECgIIBAAAAA==.Cantgoonnow:BAAALAADCggICAAAAA==.Canuckranger:BAAALAADCggIEgAAAA==.Captnubcakes:BAAALAAECgIIBAAAAA==.Capziestrian:BAAALAADCggIEAAAAA==.Carefreè:BAABLAAECoEWAAICAAgIcyJzAgAYAwACAAgIcyJzAgAYAwAAAA==.Carefrida:BAAALAADCggIEAABLAAECggIFgACAHMiAA==.Carepriest:BAAALAADCgYIDQABLAAECggIFgACAHMiAA==.Casarial:BAAALAADCgQIBAAAAA==.Castallia:BAAALAAECgYICgAAAA==.Casuna:BAAALAADCgMIAwAAAA==.',Ce='Celerity:BAAALAAECgQIBwAAAA==.Celestë:BAAALAADCggICAAAAA==.',Ch='Chainsoflove:BAAALAAECgQIBQAAAA==.Chamanita:BAAALAAECgIIBAAAAA==.Chaospho:BAAALAAECgcIEAAAAA==.Cheesebread:BAAALAADCgcIBwAAAA==.Chewbacka:BAAALAADCggICAAAAA==.Chi:BAAALAAECgYICgAAAA==.Choson:BAAALAAECgQIBwAAAA==.',Ci='Cindezath:BAAALAADCgMIBgAAAA==.Cire:BAAALAAECgcIBwAAAA==.Cired:BAAALAAECgIIAgAAAA==.Cirillaa:BAAALAADCgYIBgAAAA==.',Cj='Cjg:BAAALAADCgYIBwAAAA==.',Cl='Claudiuss:BAAALAAECgQIBwAAAA==.Clavela:BAAALAADCgYICAAAAA==.Clovagosa:BAAALAAECgYIBwAAAA==.',Co='Conakazi:BAAALAADCgYIBgAAAA==.Cosmicmoon:BAAALAADCgMIAwAAAA==.Cowpuckey:BAAALAAECgYIBwAAAA==.',Cr='Critkiller:BAAALAAECgEIAQAAAA==.Crownroyalb:BAAALAADCgQIBAAAAA==.',Cu='Curzøn:BAABLAAECoEWAAIDAAYITiY/BQCYAgADAAYITiY/BQCYAgAAAA==.',Cy='Cynardria:BAAALAAECgMIBgAAAA==.',Da='Daedengerek:BAAALAAECgYICwAAAA==.Daedra:BAAALAADCgMIAwAAAA==.Daggers:BAAALAADCgcICAAAAA==.Dakotã:BAAALAAECgMIAwAAAA==.Danabell:BAAALAAECgIIBAAAAA==.Danigos:BAAALAAFFAYICwAAAQ==.Dantrag:BAAALAAECgEIAQAAAA==.Dawnshott:BAAALAAECgEIAgAAAA==.Daxiron:BAAALAADCgcIBwAAAA==.Dazanji:BAAALAADCgQIBAAAAA==.',De='Deathadder:BAAALAAECgYICwAAAA==.Deathhounds:BAAALAADCgcIDQAAAA==.Deekåy:BAAALAADCggICAAAAA==.Deepstrøm:BAAALAADCgEIAQAAAA==.Delaena:BAAALAADCggICAAAAA==.Demiphant:BAAALAAECgQIBgAAAA==.Demonballz:BAAALAAECgEIAQAAAA==.Demonickirby:BAAALAADCgcICAAAAA==.Demoniicone:BAAALAADCgcICAAAAA==.',Di='Dishware:BAAALAADCgYICQAAAA==.',Do='Donniy:BAAALAAECgQIBwAAAA==.Dorrag:BAAALAAECgMIAwAAAA==.',Dp='Dpx:BAAALAAFFAIIAgAAAA==.',Dr='Draconîs:BAAALAAECggICgAAAA==.Draczeal:BAAALAAECgMIBAAAAA==.Dragö:BAAALAAECgMIBAAAAA==.Dreidels:BAAALAAECgYICgAAAA==.Drift:BAAALAAECgUIBwAAAA==.Droppinmoons:BAAALAAECgIIAwAAAA==.Druantia:BAAALAADCgcICQAAAA==.Drunky:BAAALAAECgMIAwAAAA==.Drysua:BAAALAAECgcIEgAAAA==.',Du='Dundim:BAAALAADCgQIBAAAAA==.',['Dé']='Démön:BAAALAADCgQIBQAAAA==.',Ec='Echô:BAAALAAECgIIAgAAAA==.Echôes:BAAALAAECggIBwAAAA==.',Ed='Edith:BAAALAADCggIBAAAAA==.',Eg='Egino:BAAALAADCggIDwAAAA==.',El='Elanuo:BAAALAADCgcIDAAAAA==.Elarisiel:BAAALAADCggIDwAAAA==.Elaynne:BAAALAAECgcIEAAAAA==.Eldrith:BAAALAAECgEIAQAAAA==.Elementhal:BAAALAADCgYIBgAAAA==.Elfaa:BAAALAADCggIEwAAAA==.Eliteelf:BAAALAAECgQIBQAAAA==.Ellenianth:BAAALAADCggIDgAAAA==.Ellenora:BAAALAAECgYICgAAAA==.Ellessdee:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.Elloro:BAAALAAECggIEgAAAA==.Elopeppe:BAAALAAECgIIAwAAAA==.Eloro:BAAALAAECgEIAQABLAAECggIEgABAAAAAA==.Elveanana:BAAALAADCgUIBQAAAA==.Elwesingollo:BAAALAADCgcIDAAAAA==.Elyrhae:BAAALAADCgcIDQAAAA==.',Em='Emoticon:BAAALAADCgcIBwAAAA==.',En='Enrgizernelf:BAAALAAECgcIDgAAAA==.',Er='Erathena:BAAALAADCgcIDwAAAA==.Eriya:BAAALAAECgEIAQAAAA==.Eryndra:BAAALAADCgEIAQAAAA==.',Ev='Evangeeline:BAAALAAECgEIAQAAAA==.Evirence:BAAALAADCgIIAgAAAA==.Evoldruid:BAAALAADCgQIBAAAAA==.',Ey='Eyeback:BAAALAADCgQIBAAAAA==.',Fa='Fannis:BAAALAADCggICAAAAA==.Fatthead:BAAALAADCgcIBwAAAA==.Fax:BAAALAAECgIIBAAAAA==.',Fe='Felaros:BAAALAADCgUIBQAAAA==.Ferang:BAAALAAECgcIDwAAAA==.Fevion:BAAALAAECgEIAQAAAA==.',Fi='Finduilas:BAAALAAECgcIEAAAAA==.Fingaz:BAAALAAECgEIAQAAAA==.Firefest:BAAALAADCgcIDAAAAA==.Firepower:BAAALAAECgMIAwAAAA==.Firepriest:BAAALAAECgEIAQAAAA==.',Fl='Flamewolf:BAAALAAECgEIAQAAAA==.',Fo='Foamcutout:BAAALAAECgYICAAAAA==.Foog:BAAALAAECgYIDwAAAA==.Fortt:BAAALAAECgcIDgAAAA==.',Fr='Freakaleake:BAAALAAECgYICQAAAA==.Freeport:BAAALAAECggIDgAAAA==.Freesum:BAAALAAECgYICgABLAAECggIDgABAAAAAA==.Froggy:BAAALAAECgMIAwABLAAECggIFgAEAJ0iAA==.',Fu='Fuchu:BAAALAADCgQIBwAAAA==.Funnymuffin:BAAALAAECgQICQAAAA==.Furyane:BAAALAADCgMIAwAAAA==.Furyia:BAAALAAECgEIAQAAAA==.Fuzzleprime:BAAALAADCgcIDgAAAA==.Fuzzybuddy:BAAALAAECgMIBQAAAA==.',Ga='Gaebora:BAAALAAECgEIAQAAAA==.Galatea:BAABLAAECoEWAAIFAAgIgR1pCQCGAgAFAAgIgR1pCQCGAgAAAA==.Gauza:BAAALAAECgMIBAAAAA==.',Gb='Gbr:BAAALAADCgMIAwAAAA==.',Gh='Ghouldann:BAAALAAECgMIAwAAAA==.',Gl='Glagglag:BAAALAAECgYICwAAAA==.',Gn='Gnorman:BAAALAADCgMIAwAAAA==.',Go='Gorothai:BAAALAADCgcICgAAAA==.',Gr='Grasha:BAAALAAECgMIAwAAAA==.Graxion:BAAALAAECgMIBgAAAA==.Grindelwald:BAAALAADCggICAAAAA==.Gruffypal:BAAALAAECgQICgAAAA==.Grumpy:BAAALAAECgMIAwAAAA==.',Gw='Gwaine:BAAALAAECgcIEgAAAA==.Gwynorra:BAAALAAECgEIAQAAAA==.',Ha='Habibi:BAAALAAECgcIDgAAAA==.Hammur:BAAALAAECgYIBwAAAA==.Hampter:BAAALAADCgcIDAAAAA==.Hanasam:BAAALAADCgEIAQAAAA==.Hansohee:BAAALAADCgEIAQAAAA==.Haralda:BAAALAAECgIIBAAAAA==.Harshblue:BAAALAAECgcIEAAAAA==.Hasdormu:BAAALAADCgEIAQAAAA==.Hatsune:BAAALAADCggIDwAAAA==.Hawtnhordy:BAAALAADCgMIBQAAAA==.',He='Healeydan:BAAALAADCgcIBwAAAA==.Healinfool:BAAALAADCgQICAAAAA==.Hedlock:BAAALAADCggICAABLAAECgMIBgABAAAAAA==.Hedwink:BAAALAADCgYIDAABLAAECgMIBgABAAAAAA==.Heiligfeuer:BAAALAADCggIEQAAAA==.Hellodc:BAAALAAECgcIDwAAAA==.Herrick:BAAALAAECggIBwAAAA==.Heyzues:BAAALAADCgMIBAABLAAECgcIDQABAAAAAA==.',Hi='Hippay:BAAALAAECgcIDgAAAA==.',Ho='Holypowerr:BAAALAAECgYIDgAAAA==.Holyshift:BAAALAADCgMIAwAAAA==.Holysmith:BAAALAADCgcIBwAAAA==.Holyspoons:BAAALAAECgYIBwAAAA==.Hommer:BAAALAADCgcICAAAAA==.Houndwar:BAAALAADCgcIDAAAAA==.',Hu='Huntli:BAAALAAECgIIBAABLAAECgUIBwABAAAAAA==.',Hy='Hylaa:BAAALAADCgYIBwAAAA==.',Ic='Icecreamcake:BAABLAAECoEbAAIGAAgIbRKtFAALAgAGAAgIbRKtFAALAgAAAA==.',Ik='Ikin:BAAALAADCgYIBgAAAA==.',Ip='Iphei:BAAALAADCggIEAAAAA==.',Ir='Irulanni:BAAALAAECgIIAwAAAA==.',Iv='Iva:BAAALAADCgcIBwAAAA==.',Ja='Jalaven:BAAALAAECgQIBwAAAA==.',Ji='Jinian:BAAALAADCgcIBwAAAA==.',Jo='Johchi:BAAALAAECgcIEAAAAA==.Jordane:BAAALAADCgcIDQAAAA==.Joust:BAAALAAECgIIAgAAAA==.',Ju='Juvenate:BAAALAAECgQIBwAAAA==.Juyani:BAAALAADCgcIDAAAAA==.',Ka='Kaatara:BAAALAAECgMIBAABLAAECgMIBgABAAAAAA==.Kaella:BAAALAAECgMIBQAAAA==.Kaiyah:BAAALAADCggIEgAAAA==.Kalrom:BAAALAADCgUIBQAAAA==.Kamikazee:BAAALAADCgcICgAAAA==.Kanab:BAAALAAECgMIAwAAAA==.Kasim:BAAALAAECgEIAQAAAA==.Kato:BAAALAAECgEIAQAAAA==.Kava:BAAALAAECgcIEwAAAA==.Kayllea:BAAALAADCgQIBAAAAA==.Kaytara:BAAALAAECgQIBwAAAA==.',Kh='Khrianii:BAAALAADCgcIBwAAAA==.',Ki='Kitherry:BAAALAAECgIIBAAAAA==.',Ko='Koristil:BAAALAADCgIIAgAAAA==.',Kr='Krisdk:BAAALAAECgcIDgAAAA==.Krystil:BAAALAAECgcICwAAAA==.',Kt='Ktosh:BAAALAADCgMIAwAAAA==.',Ku='Kurenay:BAAALAADCgUIBQAAAA==.Kurzul:BAAALAADCgMIAwAAAA==.',Kv='Kv:BAAALAADCgEIAQAAAA==.',Kw='Kweri:BAAALAAECgMIBAAAAA==.',Ky='Kynlari:BAAALAADCggIDAAAAA==.Kytre:BAAALAADCgQIBAAAAA==.',La='Lanthinas:BAAALAADCgYICgAAAA==.Larat:BAAALAADCgQIBAAAAA==.Latriah:BAAALAAECgcIDQAAAA==.Lazer:BAAALAADCggIBQAAAA==.',Le='Leafybabe:BAAALAADCgYIEAAAAA==.Leicht:BAAALAADCgcICAAAAA==.Leviasaint:BAAALAAECgcIEAAAAA==.Levo:BAAALAAECgYICgAAAA==.',Li='Licitten:BAAALAAECgUICQAAAA==.Lifeinsuranc:BAAALAADCgcIDQAAAA==.Lightmaidén:BAAALAAECgYICAAAAA==.Lightstim:BAAALAADCgIIAgAAAA==.Lightswitch:BAAALAADCgEIAQAAAA==.Liliíth:BAAALAADCgEIAQAAAA==.Lilmiji:BAAALAAECgYICwAAAA==.Liptan:BAAALAAECgYICwAAAA==.',Lo='Lodtuspuch:BAAALAADCgIIAgAAAA==.Loh:BAAALAADCgcIDQAAAA==.Lohplauge:BAAALAADCgcIDAAAAA==.Lonesnipa:BAAALAAECgYICAAAAA==.Lorealyn:BAAALAADCgcIBwAAAA==.',Lu='Luciferias:BAAALAADCgEIAQAAAA==.Luipu:BAAALAADCgMIAwAAAA==.Lulubeth:BAAALAAECgYIBgAAAA==.Lunasano:BAAALAADCgcIDAAAAA==.Lunâire:BAAALAADCgQIBAAAAA==.',Ly='Lycandra:BAAALAAECgIIAgAAAA==.Lyceaun:BAAALAADCggIDwAAAA==.Lyroll:BAAALAAECgEIAQAAAA==.',['Lú']='Lúnthiel:BAAALAADCggICgAAAA==.',Ma='Madglowup:BAAALAAECgMIAwAAAA==.Maelforge:BAAALAADCgcIDgAAAA==.Maevisara:BAAALAAECgYICgAAAA==.Magdalayna:BAAALAADCggIEwAAAA==.Mahthu:BAAALAAECgEIAQAAAA==.Malfron:BAAALAADCgEIAQAAAA==.Malifrion:BAAALAADCgIIAgAAAA==.Mani:BAAALAAECgEIAQAAAA==.Marvel:BAAALAAECgMIAwAAAA==.Maulfurion:BAAALAAECgYICQAAAA==.',Me='Melaynna:BAAALAADCgMIAwAAAA==.Mephiselenia:BAAALAADCgEIAQAAAA==.Mephysta:BAAALAAECgMIAwAAAA==.Meree:BAAALAADCgYICwAAAA==.Mereideris:BAAALAAECgMIBQAAAA==.Merisiel:BAAALAAECgQIBwAAAA==.Meryzbeth:BAAALAADCggIEwAAAA==.Mewtilation:BAAALAADCggIDwAAAA==.',Mi='Minervaa:BAAALAAECgIIAgAAAA==.Mirrari:BAAALAAECgMIBAAAAA==.Misojos:BAAALAADCgUIBQAAAA==.Missfrossty:BAAALAADCgcIDQAAAA==.',Mo='Molten:BAAALAAECgMIBAAAAA==.Mox:BAAALAAECgIIAgAAAA==.',Mu='Muun:BAAALAADCgcICgAAAA==.',My='Myrabeth:BAAALAADCgcIBwAAAA==.Mythh:BAAALAADCgMIAwAAAA==.',['Må']='Mågîk:BAAALAADCgUICAAAAA==.',Na='Naldon:BAAALAAECgMIBQAAAA==.Nalorin:BAAALAAECgIIAwAAAA==.Naraine:BAAALAAECgIIAwAAAA==.',Ne='Nelai:BAAALAADCggIDwAAAA==.Nephtyys:BAAALAAECgEIAQAAAA==.Nes:BAAALAAECgIIBAAAAA==.Neza:BAAALAADCgQIBwAAAA==.Neîth:BAAALAADCgIIAgAAAA==.',Ni='Niavy:BAAALAADCgIIAgAAAA==.Nightgecko:BAAALAAECgYICwAAAA==.Nihalunk:BAAALAAECgcIDwAAAA==.Nihavoker:BAAALAADCgQIBAAAAA==.',No='Nofoxgivn:BAAALAADCggIFwAAAA==.Nogdem:BAAALAAECgIIBAAAAA==.Novaprime:BAAALAAECgIIAgAAAA==.Novastorm:BAAALAAECgIIAgAAAA==.',['Nà']='Nàra:BAAALAADCggICgAAAA==.',['Nó']='Nóe:BAAALAAECgYICgAAAA==.',['Nù']='Nùrse:BAAALAAECgQIBQAAAA==.',Ob='Obeel:BAAALAAECgIIAgAAAA==.',Pa='Paepae:BAAALAAECgcIEgAAAA==.Paku:BAAALAADCggICQAAAA==.Pandalhão:BAAALAADCgEIAQAAAA==.Papua:BAAALAADCgcIDQABLAADCggIEwABAAAAAA==.Patientzero:BAAALAAECgMIAwAAAA==.',Pe='Peachiekeen:BAAALAADCggIEgAAAA==.Peekãboo:BAAALAAECgYICAAAAA==.Peewheewoo:BAAALAADCgcIDgAAAA==.Peliossa:BAAALAADCgUIBQAAAA==.',Ph='Pharact:BAAALAAECgUIBgAAAA==.Pholia:BAAALAADCgcIEwAAAA==.',Pi='Pieni:BAAALAADCgYIBgAAAA==.Pinkrose:BAAALAAECgMIBAAAAA==.',Pl='Platomatrixx:BAAALAAECgUICAAAAA==.',Ps='Psyop:BAAALAAECgYIDAAAAA==.',Pu='Punish:BAAALAADCgEIAQAAAA==.',Qb='Qberks:BAAALAAECgYIEgAAAA==.',Qu='Quadspecs:BAAALAAECgEIAQAAAA==.Quik:BAAALAAECgMIBAAAAA==.',Ra='Radtiz:BAAALAADCggICgAAAA==.Raenin:BAAALAAECgMIBgAAAA==.Raganthor:BAACLAAFFIEFAAIHAAMItQvGAwDuAAAHAAMItQvGAwDuAAAsAAQKgRYAAgcACAiXI3UDADwDAAcACAiXI3UDADwDAAAA.Ragingdraem:BAAALAAECgMIAwAAAA==.Raidei:BAAALAAECgcIDAAAAA==.Ramzi:BAAALAADCggIDgAAAA==.Ramzizz:BAAALAADCgcIDwAAAA==.Raon:BAAALAADCgQIBAAAAA==.Ravenmagica:BAAALAAECgYICwAAAA==.',Re='Rebirthz:BAAALAADCgQICAAAAA==.Redpawedfox:BAAALAAECgYICgAAAA==.Rekviem:BAAALAAECgQIBwAAAQ==.Relifus:BAAALAAECgEIAgAAAA==.Reshu:BAAALAADCgcICgAAAA==.',Rh='Rhavaniel:BAAALAADCgcIEgAAAA==.Rhenin:BAAALAAECgIIAwAAAA==.',Ri='Riest:BAAALAADCgcIDQAAAA==.Riften:BAAALAADCgcIBwABLAAECgQIBgABAAAAAA==.Riverwolf:BAAALAAECggIBQAAAA==.',Ro='Rockfyst:BAAALAADCggICAAAAA==.Roktscorch:BAAALAADCgMIBQAAAA==.Roni:BAAALAADCggIEgAAAA==.Roww:BAAALAADCgQIBAAAAA==.Royalnewb:BAAALAAECgcIDgAAAA==.Royston:BAAALAAECgYICAAAAA==.',Ru='Rucereal:BAAALAADCggICAAAAA==.Runicpowers:BAAALAADCggIEgAAAA==.Rustyaf:BAAALAADCgcIDQAAAA==.',Ry='Rynsidious:BAAALAAECgcIEAAAAA==.Rythia:BAAALAAECgIIBAAAAA==.',Sa='Sabelle:BAAALAAECgMIBgAAAA==.Saeton:BAAALAAECgYICwAAAA==.Sahlaris:BAAALAAECgIIBAAAAA==.Saladfingrs:BAABLAAECoEWAAIEAAgInSKkAgDwAgAEAAgInSKkAgDwAgAAAA==.Salno:BAAALAADCgYIBgAAAA==.Samsonite:BAAALAAECgQICQAAAA==.Satelite:BAAALAADCgEIAQAAAA==.',Sc='Scillia:BAAALAAECgIIAgAAAA==.',Se='Sefreyn:BAAALAADCgcIBwAAAA==.Sekhet:BAAALAAECgYICgAAAA==.Sekstrasza:BAAALAADCgcIDgAAAA==.Serafinai:BAAALAAECgMIBAAAAA==.Serelith:BAAALAADCgcIBwABLAADCggICQABAAAAAA==.',Sh='Shaazaam:BAAALAADCgcIDQABLAADCggIEgABAAAAAA==.Shadowveel:BAAALAAECgQIBQABLAAECgcIEAABAAAAAA==.Shakothaa:BAAALAADCgMIAwAAAA==.Shamamama:BAAALAADCgcIBwAAAA==.Shamanoid:BAAALAAECgMIAwAAAA==.Shamone:BAAALAADCgIIAgAAAA==.Shasta:BAAALAAECgYICAAAAA==.Shekelshaker:BAAALAADCgcIDgABLAAECgYICgABAAAAAA==.Shiftngears:BAAALAADCgUICAAAAA==.Shiftnhealz:BAAALAADCgQIBAAAAA==.Shoutinfool:BAAALAADCgMIAwAAAA==.Shádé:BAAALAADCgYICgAAAA==.',Si='Siddlock:BAAALAADCggIAQAAAA==.Siik:BAAALAADCggIDAABLAAECgMIAwABAAAAAA==.Silaena:BAAALAAECgcIDgAAAA==.Silverlocke:BAAALAAECgMIAwAAAA==.Sinder:BAAALAADCgUIBgABLAAECgUIBgABAAAAAA==.Sinæstro:BAAALAADCgUIBQAAAA==.',Sk='Skagirl:BAAALAAECgcIDQAAAA==.Skillbeam:BAAALAAECgcIDgAAAA==.Skitter:BAAALAADCgYICwAAAA==.Skyblaze:BAAALAADCgcIEQAAAA==.Skyeira:BAAALAAECgMIAwAAAA==.Skyfallen:BAAALAAECgcIEAAAAA==.Skyler:BAAALAADCgcIBwAAAA==.',Sl='Sleepysoufle:BAAALAADCggICAAAAA==.Slink:BAAALAAECgIIAgAAAA==.',Sm='Smoosh:BAAALAAECgMIBQABLAAECgYIEgABAAAAAA==.Smurp:BAAALAADCggICAAAAA==.',So='Solanea:BAAALAAECgYICQAAAA==.Solgon:BAAALAAECgMIAwAAAA==.Solä:BAAALAAECgIIBAAAAA==.Sonchakra:BAAALAAECgIIAgAAAA==.Sonic:BAAALAADCggICAAAAA==.Sorcero:BAAALAAECgEIAQAAAA==.Sorcforce:BAAALAADCgUICgAAAA==.Sosie:BAAALAADCgYIBgAAAA==.Soulreap:BAAALAADCgIIAgAAAA==.Sourwine:BAAALAAECgcIEQAAAA==.',Sp='Spellbind:BAAALAADCgUIBQAAAA==.Spritemage:BAAALAADCgEIAQAAAA==.Spritemonk:BAAALAADCgYIBgAAAA==.',St='Starghost:BAAALAADCgIIAwAAAA==.Stencil:BAAALAAECgEIAQAAAA==.Stormdancer:BAAALAAECgcIEAAAAA==.Strangiatie:BAAALAADCgUIAgAAAA==.Stumpyfoot:BAAALAAECgIIBAAAAA==.Stãrs:BAAALAAECgcIDgAAAA==.',Su='Sugär:BAAALAADCgQIBAAAAA==.',Sy='Synrax:BAAALAAECgIIAgAAAA==.',Ta='Taffigosa:BAAALAADCgQIBAAAAA==.Taffy:BAAALAADCgMIAwAAAA==.Takodaddy:BAAALAAECgcIEAAAAA==.Tanthel:BAAALAAECgEIAQAAAA==.Tantrykmagyk:BAAALAADCgEIAQAAAA==.',Te='Telitha:BAAALAADCggICgAAAA==.Tellie:BAAALAAECgMIBAAAAA==.Tempest:BAAALAAECgIIBAAAAA==.Terraquis:BAAALAAECgcIEAAAAA==.Testarossa:BAAALAAECgIIBAAAAA==.',Th='Thdor:BAAALAADCgYIBgAAAA==.Theonas:BAAALAADCgcIDgAAAA==.Thesloth:BAAALAAECgIIAwAAAA==.Thiccbiddies:BAAALAAECgcIEAAAAA==.Thorad:BAAALAADCgYIBgAAAA==.Thundermug:BAAALAAECggICAAAAA==.Thunderwings:BAAALAADCgcIDQAAAA==.',Ti='Tigan:BAAALAAECgYICQAAAA==.Tigra:BAAALAAECgYICwAAAA==.Timeweaver:BAAALAAECgYICwAAAA==.Tirmone:BAAALAADCggIDwAAAA==.Tirogue:BAAALAAECgMIAwAAAA==.',To='Toadie:BAAALAADCgMIAQAAAA==.Toranaar:BAAALAAECgIIAgAAAA==.',Tr='Trabeajin:BAAALAAECgMIAwAAAA==.Trayfu:BAAALAAECgMIBgAAAA==.Trice:BAAALAADCgYIDAAAAA==.Trostani:BAAALAAECgYIDAAAAA==.Trusker:BAAALAAECgMIBgAAAA==.Trypticon:BAAALAADCgcIBwAAAA==.',Tu='Turniphead:BAAALAAECgEIAQAAAA==.Turok:BAAALAADCgUIBQAAAA==.',Tw='Tweakin:BAAALAADCgUIBQAAAA==.Twinbladez:BAAALAADCgcIDQAAAA==.Twitty:BAAALAAECgUIBwAAAA==.',Ty='Tychocaine:BAAALAADCggIEAAAAA==.Tyraxis:BAAALAAECgMIBQAAAA==.Tyrâ:BAAALAAECggIEAAAAA==.',Ul='Ulasar:BAAALAADCggIEgAAAA==.',Un='Underworld:BAABLAAECoEZAAIIAAgINhpqEQCBAgAIAAgINhpqEQCBAgAAAA==.Unholyviper:BAAALAAECgMIAwAAAA==.Untarot:BAAALAADCggICgAAAA==.',Va='Valcia:BAAALAADCgcIBwAAAA==.Valdanyr:BAEALAAECgMIBAAAAA==.Valharrow:BAAALAAECgQIBQAAAA==.Valliant:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Valloria:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Vandar:BAAALAAECgIIAgAAAA==.Vandrilia:BAAALAAECgYIBwAAAA==.Varmav:BAAALAADCgcICgAAAA==.Vauxe:BAAALAADCgcIBwAAAA==.',Ve='Veganox:BAAALAAECgEIAQAAAA==.Vendorin:BAAALAAECgMIBAAAAA==.Vendre:BAAALAAECgYICwAAAA==.Veroswen:BAAALAAECgEIAQAAAA==.Verrona:BAAALAADCgUIBQAAAA==.Vett:BAAALAAECgMIAwAAAA==.Veyra:BAAALAADCggICAAAAA==.',Vi='Viltrumita:BAAALAADCggICAAAAA==.Virusgt:BAAALAAECgIIAwAAAA==.',Vk='Vkandis:BAAALAAECgEIAgAAAA==.',Vo='Voltaris:BAAALAAECgYIBgAAAA==.Voxyn:BAAALAADCgYICgAAAA==.',Vr='Vriska:BAAALAADCggICAAAAA==.',['Vè']='Vèel:BAAALAAECgcIEAAAAA==.',Wa='Wackwackwack:BAAALAAECgcIEQAAAA==.Wakawaka:BAAALAAECgIIBAABLAAECgUIBwABAAAAAA==.Wardoll:BAAALAADCgQIBAAAAA==.Washackedd:BAAALAAECgMIBAAAAA==.',We='Webucifer:BAAALAAECgEIAQAAAA==.Weewhoa:BAAALAAECgMIAwAAAA==.Weirdward:BAAALAAECgIIAgAAAA==.',Wi='Witkin:BAAALAAECgMIBgAAAA==.Witpally:BAAALAADCggICQABLAAECgMIBgABAAAAAA==.Wiznitch:BAAALAADCgcIBwAAAA==.',Wo='Wobblin:BAAALAADCgIIAgAAAA==.Woofing:BAAALAADCgYIBgAAAA==.',Wy='Wytrim:BAAALAADCgMIAwAAAA==.',Xa='Xaida:BAAALAAECgQIBwAAAA==.Xalanissa:BAAALAADCgYIBgAAAA==.',Xc='Xcaps:BAAALAAECgEIAQAAAA==.',Xi='Xiaoyan:BAAALAADCgQIBAAAAA==.Xishi:BAAALAAECgMIAwAAAA==.',Xu='Xuing:BAAALAAECgYICwAAAA==.',Ya='Yarro:BAAALAAECgYICgAAAA==.',Ym='Ym:BAAALAAECgQIBwAAAA==.',Yo='Yoloshi:BAAALAAECgEIAQAAAA==.Youngblud:BAAALAADCgcIDQAAAA==.',Yt='Ytg:BAAALAADCgMIAwAAAA==.',Yu='Yurk:BAAALAADCgEIAQAAAA==.',Za='Zaela:BAAALAAECgQIBwAAAA==.Zaku:BAAALAADCgYIBQAAAA==.Zax:BAAALAAECgEIAgAAAA==.',Ze='Zendeth:BAAALAAECgIIAgAAAA==.Zerlin:BAAALAADCggICwAAAA==.Zeroximo:BAAALAADCgYIBwAAAA==.',Zi='Zipline:BAAALAAECgEIAQAAAA==.',Zo='Zofie:BAAALAADCggIEAAAAA==.Zombiex:BAAALAAECgIIAgABLAAECgIIAgABAAAAAA==.Zombiexx:BAAALAAECgIIAgAAAA==.Zonex:BAAALAADCgcIBwAAAA==.Zoouno:BAAALAAECgYICQAAAA==.Zoraell:BAAALAAECgMIAwAAAA==.Zordiak:BAAALAAECgIIBAAAAA==.',Zu='Zuki:BAAALAAECgIIAgAAAA==.',['Äñ']='Äñûßîs:BAAALAADCggICAAAAA==.',['Éx']='Éxörcîst:BAAALAADCgEIAQAAAA==.',['Üb']='Übertanker:BAAALAADCgcICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end