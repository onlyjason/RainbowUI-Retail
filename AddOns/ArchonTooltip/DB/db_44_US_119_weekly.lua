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
 local lookup = {'Mage-Arcane','Unknown-Unknown','Warrior-Arms','Warrior-Fury','Monk-Mistweaver','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Paladin-Holy',}; local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aarix:BAAALAAECgYICQAAAA==.',Ab='Aboot:BAAALAADCgEIAQAAAA==.',Ac='Acekid:BAAALAADCgMIAwAAAA==.Achmed:BAAALAADCgcICwAAAA==.',Ad='Adreithria:BAAALAAECgMIAwAAAA==.Adron:BAAALAADCggIDAABLAAECggIFgABAIYkAA==.',Ae='Aeo:BAAALAAECgcICgAAAA==.',Ai='Aiel:BAAALAAECgcICgAAAA==.Aiolus:BAAALAADCgMIAwAAAA==.',Al='Alice:BAAALAADCgIIAgABLAADCgQIBAACAAAAAA==.Allzaroz:BAAALAAECgMIBgAAAA==.Allzera:BAAALAADCggIFQABLAAECgMIBgACAAAAAA==.',Am='Ambowlynn:BAAALAAECgYIDwAAAA==.Ametsuchi:BAAALAAECgMIAwAAAA==.',An='Anidagio:BAAALAADCggICwABLAAECgMIAwACAAAAAA==.Anihelion:BAAALAAECgMIAwAAAA==.Ankhu:BAAALAADCgMIBAAAAA==.Antons:BAAALAAECgUIBgAAAA==.Antraxus:BAAALAAECgMIBgAAAA==.Anugregamin:BAAALAADCgcIBwAAAA==.Anuke:BAAALAADCggIDwAAAA==.',Ap='Apostrophe:BAAALAADCgMIAwAAAA==.',Ar='Armin:BAAALAAECgUICAAAAA==.Arrowhoof:BAAALAADCgYICQAAAA==.',As='Ashmage:BAAALAAECgQIBgAAAA==.Ashmorph:BAAALAAECgIIBAAAAA==.Ashýra:BAAALAAECgcIDAAAAA==.Asiimov:BAAALAAECgcIDgAAAA==.Asterisk:BAAALAAECgYICwAAAA==.Astrocytoma:BAAALAADCggIDAAAAA==.Asya:BAAALAAECggIAgAAAA==.',At='Atom:BAAALAAECgYIDgAAAA==.Attilathepun:BAAALAADCggIDwAAAA==.',Au='Augmentious:BAAALAADCggIDQAAAA==.Aureal:BAAALAADCggIDwAAAA==.Autoknight:BAAALAAECgMIAwAAAA==.',Az='Azelenia:BAAALAADCgcIBwAAAA==.Aztecthewolf:BAAALAAECgUIAQAAAA==.',['Añ']='Aña:BAAALAAECgYICQAAAA==.Añarchist:BAAALAADCggIDgABLAAECgYICQACAAAAAA==.',Ba='Badmagics:BAAALAADCggICwAAAA==.Baelethal:BAAALAAECgQIBAAAAA==.Baelzharon:BAAALAAECgUIBQAAAA==.Baeryl:BAAALAAECgIIAgAAAA==.Balgrim:BAAALAAECgYIDQAAAA==.Barbearian:BAAALAAECgMIAwAAAA==.Barrlidan:BAAALAAECgcICgAAAA==.Barrthas:BAAALAAECgEIAQABLAAECgcICgACAAAAAA==.Baràthrum:BAAALAAECgYIBgAAAA==.Basalt:BAAALAAECgIIBAAAAA==.Bastenwode:BAAALAAECgEIAQAAAA==.',Be='Beartab:BAAALAAECgMIAwAAAA==.Becký:BAAALAAECgYICQAAAA==.Beisenberger:BAAALAADCgUIBgAAAA==.Beloril:BAAALAADCgQIBAAAAA==.Beroan:BAAALAAECgIIBAAAAA==.Berryshots:BAAALAADCgcIDQAAAA==.',Bi='Bigcøøkie:BAAALAAECgUIBwAAAA==.Bigdotenergy:BAAALAAECgYICQAAAA==.Bigjim:BAAALAAECgQIBAAAAA==.Biglasaga:BAAALAAECgYICwAAAA==.Biglul:BAAALAADCggIDAABLAAECgYICwACAAAAAA==.Bigolcrities:BAAALAADCgEIAQAAAA==.Bigpapaw:BAAALAADCgUIBQAAAA==.Birttok:BAAALAADCggICAAAAA==.Bivivi:BAAALAADCgcIEAAAAA==.',Bl='Blackmagma:BAAALAADCggIFgABLAAECgIIBAACAAAAAA==.Blackpiink:BAAALAAECgIIAwAAAA==.Blackppink:BAAALAAFFAIIBAAAAA==.Blackppinkk:BAAALAAECgEIAQAAAA==.Bladefi:BAAALAAECgUICAAAAA==.Bloodbunny:BAAALAAECgEIAQAAAA==.',Bo='Boneless:BAAALAAECgIIAgAAAA==.Bonnierotten:BAAALAADCggICAABLAAECgYIDAACAAAAAA==.Bopity:BAAALAADCggICAAAAA==.Bosstradamus:BAAALAAECgQICAAAAA==.Bows:BAAALAADCgMIAwAAAA==.',Br='Brickaton:BAAALAAECgMIBQAAAA==.Britva:BAAALAADCggIDwAAAA==.Brocknor:BAAALAAECgYIDgAAAA==.Brucebanners:BAAALAAECgcICwAAAA==.Brunhyll:BAAALAADCggICAAAAA==.Bruur:BAAALAADCgQIBAAAAA==.',Bu='Burbon:BAAALAAECgMIBQAAAA==.Butterdtoast:BAEALAAECgIIBAAAAA==.',['Bá']='Báwlz:BAAALAADCggIDwAAAA==.',['Bí']='Bírd:BAAALAAECgMIAwAAAA==.',Ca='Cabbresoa:BAAALAAECgYICQAAAA==.Caboose:BAAALAAECgQIBQAAAA==.Cachaviejas:BAAALAAECgMIBQAAAA==.Caelaes:BAAALAADCgcIBwAAAA==.Calshaman:BAAALAADCgYIBgAAAA==.Caltonan:BAAALAADCggICAAAAA==.Canadianbrew:BAAALAADCgUIBQAAAA==.Carhuul:BAABLAAECoEWAAIBAAgIhiTgBQAaAwABAAgIhiTgBQAaAwAAAA==.Carysa:BAAALAADCgIIAgAAAA==.',Ce='Cerrvantes:BAAALAADCgIIAgAAAA==.Cerydwen:BAAALAADCggIDAAAAA==.Cesarius:BAAALAAECgEIAQAAAA==.',Ch='Chaneoku:BAAALAADCgYIBgAAAA==.Charizord:BAAALAADCgEIAQAAAA==.Chevelot:BAAALAADCgQIBAAAAA==.Chibbo:BAAALAAECgMIBAAAAA==.Chiblet:BAAALAAECgcICwAAAA==.Chilaquiles:BAAALAAECgIIAwAAAA==.',Cl='Cloudsinger:BAAALAADCggIEAAAAA==.',Co='Cocomuffin:BAAALAADCgUIBQAAAA==.Conarvil:BAAALAADCggICAABLAAECgUIDAACAAAAAA==.Conrad:BAAALAADCgcIEAAAAA==.Corenthos:BAAALAADCggICAAAAA==.',Cr='Crashedot:BAAALAADCgYIBgAAAA==.Crashedruid:BAAALAADCggICAAAAA==.Crazyhorse:BAAALAAECgEIAQABLAAECggIFwADAGEgAA==.Creammius:BAAALAADCgYIBgAAAA==.Croketita:BAAALAADCgcIBgAAAA==.Crumdumpster:BAAALAADCgYIBgABLAAECgIIBQACAAAAAA==.Crumfu:BAAALAAECgIIBQAAAA==.',Cu='Cultofmage:BAAALAAECgcIEAAAAA==.Cupru:BAAALAAECgUICQAAAA==.',['Câ']='Câp:BAAALAAECggIDgAAAA==.',Da='Dagthunderer:BAAALAAECgQIBQAAAA==.Dalatras:BAAALAAECgMIBAAAAA==.Dalistra:BAAALAAECgMIAwABLAAECgMIBAACAAAAAA==.Dalweaver:BAAALAADCgQIBAABLAAECgMIBAACAAAAAA==.Dalzz:BAAALAAECgMIAwABLAAECgMIBAACAAAAAA==.Daniellia:BAAALAADCgcIDQAAAA==.Dantes:BAAALAADCggIDQAAAA==.Dar:BAAALAADCggIDwAAAA==.Darkflame:BAAALAAECgUICAAAAA==.',De='Deathgimbo:BAAALAAECgUIDAAAAA==.Deathromo:BAAALAAECgUICQAAAA==.Deathrose:BAAALAADCgYIBgAAAA==.Deathsoath:BAAALAAECgIIAwAAAA==.Deathstomper:BAABLAAECoEXAAMDAAgIYSAJAgByAgADAAcIGR4JAgByAgAEAAQIkxtSMAAmAQAAAA==.Deckay:BAAALAAECgIIAgAAAA==.Deebee:BAAALAADCgMIAwAAAA==.Delirious:BAAALAADCgcIBwABLAAECgcIEAACAAAAAA==.Demeter:BAAALAADCgcIBwAAAA==.Demondono:BAAALAAECgUIBwAAAA==.Deregorn:BAAALAAECgMIAwAAAA==.Desmorphia:BAAALAADCggICAAAAA==.Destromo:BAAALAADCgYIBgAAAA==.Destruir:BAAALAADCgEIAQAAAA==.',Di='Diegopally:BAAALAADCgQIBQAAAA==.Dilligafnope:BAAALAADCgcICgAAAA==.Dimentía:BAAALAAECgMIAwAAAA==.Dinohunter:BAAALAAECgYIBgAAAA==.Dirtslinger:BAAALAADCgYICwAAAA==.Discôdancing:BAAALAADCgIIAgAAAA==.',Do='Doctriage:BAAALAADCgYIBgAAAA==.Dogue:BAAALAADCgEIAQAAAA==.Doomdz:BAAALAAECgQIBgAAAA==.Dorimane:BAAALAADCgcIBwAAAQ==.Dorlock:BAAALAADCggICAAAAA==.',Dr='Drama:BAAALAADCgcIBwAAAA==.Draxestraza:BAAALAADCggIDQAAAA==.Draykor:BAAALAAECggIBQAAAA==.Dred:BAAALAAECgYIDgAAAA==.Dreddh:BAAALAADCgcIBwAAAA==.Dredpala:BAAALAADCggIEAAAAA==.Drgreenthumm:BAAALAAECgYICwAAAA==.Drizzlebone:BAAALAAECgMIAwAAAA==.Droni:BAAALAADCgcICwAAAA==.Drotara:BAAALAAECgYIDgAAAA==.Drykias:BAAALAAECgIIAgAAAA==.',Du='Duhvinedh:BAAALAAECgUICwAAAA==.',Dy='Dydonks:BAAALAAECgYICQAAAA==.',['Dò']='Dòt:BAAALAAECgEIAQABLAAECggIFwAFAOUjAA==.',Ea='Earthscar:BAAALAADCggICgAAAA==.',Ec='Economos:BAAALAAECgUICAAAAA==.',Ed='Edrius:BAAALAAECgMIBAAAAA==.Edroh:BAAALAAECgMIBgAAAA==.',Ei='Eidur:BAAALAAECgQIBQAAAA==.',El='Electricyeet:BAAALAAECgIIAgAAAA==.Eljeffa:BAAALAADCggIDQAAAA==.',Em='Emagonagate:BAAALAAECgQIBAABLAAECgcICAACAAAAAA==.Emerey:BAAALAADCgIIAwAAAA==.',Er='Erikprince:BAAALAAECgIIAgAAAA==.Erso:BAAALAADCgYICgAAAA==.',Et='Eternalpaín:BAAALAAECgcIDQAAAA==.',Ev='Evanee:BAAALAAECgMIAwAAAA==.Evanrude:BAAALAADCgYICQAAAA==.',Ex='Extinguish:BAAALAADCgcIBAAAAA==.',Ez='Ezykeul:BAAALAADCggICQAAAA==.',Fa='Fafarafa:BAAALAADCgcIEAAAAA==.Fal:BAAALAAECgQIBAAAAA==.Falcyon:BAAALAAECgMIAwABLAAECggIFgABAIYkAA==.Fatherpsyx:BAAALAAECgEIAQAAAA==.',Fe='Fel:BAAALAAECgIIAgAAAA==.Felbrooks:BAAALAAECgIIAwAAAA==.Fendretta:BAAALAAECgUIDAAAAA==.',Fi='Firstaid:BAAALAADCgEIAQAAAA==.Fistö:BAAALAAECgMIAwAAAA==.',Fl='Flah:BAAALAAECgcIDwAAAA==.Flexinator:BAAALAAECgUICAAAAA==.',Fo='Forestflex:BAAALAAECgUIBgAAAA==.',Fr='Frinju:BAAALAADCgcIBwABLAAECgEIAQACAAAAAA==.Frostana:BAAALAADCggIDgABLAAECgYICgACAAAAAA==.Frostysquid:BAAALAADCgcIBwABLAADCgcIEgACAAAAAA==.',Fu='Fuchaz:BAAALAADCggIDQAAAA==.Fulta:BAAALAAECgMIBQAAAA==.Funkymonký:BAEALAADCgMIAwABLAAECggIDwACAAAAAA==.Fuzzypalms:BAAALAAECgEIAQAAAA==.',['Fí']='Fírnen:BAAALAADCgUIBQAAAA==.',Ga='Gadoon:BAAALAADCgMIAwAAAA==.Garadin:BAAALAAECgUICAAAAA==.',Ge='Geniver:BAAALAAECgEIAQAAAA==.Gerla:BAAALAAECgMIBgAAAA==.',Gh='Ghettoshout:BAAALAAECgYICAAAAA==.',Gi='Gilgameshh:BAAALAAECgYIDQAAAA==.Gingervoid:BAAALAAECgYICAAAAA==.Girthbrooks:BAAALAAECgQIBAAAAA==.Gitgood:BAAALAAECgYICwAAAA==.',Gl='Glasskeg:BAAALAADCgMIAwAAAA==.',Go='Gomory:BAAALAAECgEIAQAAAA==.Gondark:BAAALAADCgIIAgAAAA==.Goobly:BAAALAAECgYICgAAAA==.Goofyghoul:BAAALAADCgQIBAAAAA==.Gorgoz:BAAALAADCgMIAwAAAA==.',Gr='Greybow:BAAALAADCgUIBQAAAA==.Greywolf:BAAALAAECgYICgAAAA==.Gricham:BAAALAAECgQIAgAAAA==.Grundil:BAAALAAECgEIAQAAAA==.',['Gá']='Gándálf:BAAALAAECgYICgAAAA==.',Ha='Haedes:BAAALAAECgEIAQAAAA==.Haktori:BAAALAAECgIIAgAAAA==.Hammerknee:BAAALAAECgEIAQAAAA==.Hard:BAAALAAECgEIAQAAAA==.Harleii:BAAALAAECgMIAwAAAA==.Harlequins:BAAALAADCggICAAAAA==.Harmonix:BAAALAADCggICAAAAA==.Harrypalm:BAAALAADCgEIAQAAAA==.',He='Heiios:BAAALAADCggICQAAAA==.Hellhawk:BAAALAAECgIIAgAAAA==.Hellmagi:BAAALAADCgcIDgAAAA==.Heptandew:BAAALAAECgEIAQAAAA==.',Hi='Himbolight:BAAALAADCggICAABLAAECgYIDAACAAAAAA==.',Ho='Holypickle:BAAALAADCggICAAAAA==.Holyshiza:BAAALAAECgYICQAAAA==.Hoosyerdaddy:BAAALAADCggIDwAAAA==.Hoshino:BAAALAADCgYIBgAAAA==.',Ht='Htownglaivez:BAAALAADCgUIBQAAAA==.Htownhunter:BAAALAADCggIDwAAAA==.',Hu='Hungsten:BAAALAAECgUICAAAAA==.Huntfromhell:BAAALAAECgUICAAAAA==.',Hw='Hwhat:BAAALAADCgcIBwAAAA==.Hwoarang:BAAALAAECgQIBQAAAA==.',Hy='Hypocrisy:BAAALAADCgUIBgAAAA==.',Ic='Iceicepally:BAAALAAECgcICwAAAA==.',Id='Idonttank:BAAALAAECgMIAwAAAA==.',Ik='Ikara:BAAALAAECgQIBQAAAA==.',Il='Illo:BAAALAADCggIDAABLAADCggIDQACAAAAAA==.Ilysium:BAAALAADCggICAAAAA==.',Im='Imyx:BAAALAAECgMIAwAAAA==.',In='Infamuspikel:BAAALAAECgcIDAAAAA==.Infel:BAAALAAECggICAAAAA==.Innovoker:BAAALAAECgMIBAAAAA==.Intervene:BAAALAADCggICAABLAAECgcIDQACAAAAAA==.',Is='Isaßeau:BAAALAAECgYIDQAAAA==.Isfas:BAAALAAECgYICQAAAA==.',Ix='Ixli:BAAALAAECgMIAwAAAA==.',Iz='Izuael:BAAALAAECgcIDAAAAA==.',Ja='Jackjr:BAAALAAECgIIAgAAAA==.',Je='Jerff:BAAALAADCggICAAAAA==.Jetpilot:BAAALAAECgMIAwAAAA==.',Jg='Jg:BAAALAADCggICAAAAA==.',Ji='Jibi:BAAALAADCgMIAwAAAA==.Jincai:BAAALAADCgcIBwAAAA==.Jiq:BAAALAADCggICAAAAA==.Jitter:BAAALAADCggIHQABLAAECgYIDgACAAAAAA==.',Jk='Jk:BAAALAAECgUIBQAAAA==.',Jo='Johnxina:BAAALAAECgUIBwAAAA==.',Ju='Judi:BAAALAAECgMIAwAAAA==.Juggernáut:BAAALAADCggICQAAAA==.',Ka='Kabilos:BAAALAAECgMIAwAAAA==.Kadara:BAAALAADCgQIBAAAAA==.Kalesmora:BAAALAAECgUIBgAAAA==.Kamikaze:BAAALAAECgEIAQAAAA==.Kasarel:BAAALAADCgQIBAABLAADCgQIBAACAAAAAA==.Katalyst:BAAALAADCgYICQAAAA==.Katuloo:BAAALAAECgUICAAAAA==.Kav:BAAALAADCgMIAwAAAA==.Kaylbrora:BAAALAADCgYIBgAAAA==.Kazari:BAAALAADCgYIBwAAAA==.',Ke='Kelfogardinn:BAAALAADCggIDgAAAA==.Kellyzz:BAAALAADCgIIAgAAAA==.Keltharious:BAAALAAECgYIDgAAAA==.',Kh='Khall:BAAALAADCgcICAAAAA==.Khei:BAAALAADCggIDQAAAA==.Kheims:BAAALAADCgcIBwABLAADCggIDQACAAAAAA==.Khrism:BAAALAADCgcIBwABLAAECgEIAQACAAAAAA==.Khrizmo:BAAALAAECgEIAQAAAA==.Khylar:BAAALAADCgQIBAAAAA==.',Ki='Killduran:BAAALAAECgQIBAAAAA==.Kimaga:BAAALAADCggIDQAAAA==.Kirahrah:BAAALAADCgcIBwAAAA==.Kirasha:BAAALAADCgYIBgAAAA==.Kitom:BAAALAAECgMIAwAAAA==.',Kn='Knuckz:BAAALAAECgEIAQAAAA==.',Ko='Korley:BAAALAADCggIDwAAAA==.Korray:BAAALAADCggIDwAAAA==.Kortar:BAAALAAECgEIAQAAAA==.',Kr='Kreigan:BAAALAAECgYIDgAAAA==.Krelid:BAAALAAECgIIAgAAAA==.Kryptônite:BAAALAADCgUIBQAAAA==.Krystil:BAAALAADCgcICwAAAA==.Krüsh:BAAALAAECgEIAQAAAA==.',Ku='Kuhne:BAAALAADCgcICwAAAA==.Kuromie:BAAALAADCggICwAAAA==.Kushn:BAAALAADCggICAAAAA==.',Ky='Kyther:BAAALAADCgIIAgAAAA==.',La='La:BAAALAADCggICAAAAA==.Ladeiene:BAAALAAECgMIAwAAAA==.Laelwyn:BAAALAAECgEIAQAAAA==.Laeritides:BAAALAAECgIIBAAAAA==.Lardna:BAAALAAECgMIBgAAAA==.',Le='Leges:BAAALAAECgMIAwAAAA==.Levir:BAAALAADCggICAAAAA==.',Li='Lightrising:BAAALAAECgIIAwAAAA==.Lilmonstrman:BAAALAAECgcICQAAAA==.Liltree:BAAALAADCgcIBwAAAA==.Linger:BAAALAAECgMIBgAAAA==.Litany:BAAALAAECgUICQAAAA==.Lithiedrael:BAAALAADCgYIBgAAAA==.',Lo='Lohengon:BAAALAADCgcICwAAAA==.',Lu='Lucas:BAAALAADCgYICAAAAA==.Lul:BAAALAAECgYICwAAAA==.Lunamor:BAAALAADCgcIBwABLAAECgYIDgACAAAAAA==.',Ly='Lyrrah:BAAALAADCgcIBwAAAA==.',['Lð']='Lðvergirl:BAAALAADCgcICwAAAA==.',Ma='Mageblood:BAAALAAECgEIAQAAAA==.Magmadh:BAAALAADCggICwAAAA==.Maidenofbees:BAABLAAECoEYAAIGAAgIpxhqEAAxAgAGAAgIpxhqEAAxAgAAAA==.Malenïa:BAAALAADCgMIAwAAAA==.Malignantt:BAAALAAECgUICAAAAA==.Maliya:BAAALAAECgQIBAABLAAECgYIDgACAAAAAA==.Mallegoth:BAAALAAECgMIAwAAAA==.Maloriak:BAAALAAECgIIAgAAAA==.Malovia:BAAALAADCgcIDgAAAA==.Maurphious:BAAALAADCgcICgAAAA==.Mavria:BAAALAAECgMIBQAAAA==.',Me='Melodrama:BAAALAADCggIDwAAAA==.Merek:BAAALAADCgIIAgAAAA==.Messdk:BAAALAAECgMIBgAAAA==.',Mi='Minimaged:BAAALAADCgUIBgAAAA==.Mirgaree:BAAALAAECgMIBgAAAA==.Mistweaving:BAABLAAECoEXAAMFAAgI5SMKAQA1AwAFAAgI5SMKAQA1AwAHAAEI5QjvKgA9AAAAAA==.',Mo='Monkwrld:BAAALAAECgYICQAAAA==.Monty:BAAALAADCgcICwAAAA==.Mordet:BAAALAADCgcIBwABLAADCgcIBwACAAAAAQ==.Moridane:BAAALAAECgMIAwABLAADCgcIBwACAAAAAQ==.Mossmane:BAAALAADCgEIAQAAAA==.Moxxie:BAAALAADCgYIBgAAAA==.Moòn:BAAALAADCgYIBgAAAA==.',Mu='Muffinz:BAAALAAECgMIBgAAAA==.',My='Myau:BAAALAAECgMIBQAAAA==.Mynia:BAAALAAECgUIDAAAAA==.Mythic:BAAALAAECgMIBwAAAA==.Mythrius:BAAALAAECgUICAAAAA==.',Na='Nachofries:BAAALAADCggIEAAAAA==.Nano:BAAALAAECgMIBAAAAA==.Naphaele:BAAALAAECgEIAQAAAA==.Narusk:BAAALAADCgYIBgAAAA==.Natnat:BAAALAAECgMIBQAAAA==.Nazdreg:BAAALAAECgYIEAAAAA==.',Ne='Neep:BAAALAAECgcIEAAAAA==.Neotoldir:BAAALAAECgYIDgAAAA==.Nerfdruids:BAAALAADCggIDwAAAA==.Nerozond:BAAALAADCggIDQAAAA==.Neshan:BAAALAADCgcICgAAAA==.',Ni='Nibroc:BAAALAADCgEIAQAAAA==.Nightboat:BAAALAAECgMIAwAAAA==.',No='Noldrasil:BAAALAADCgEIAQAAAA==.Notintheface:BAAALAAECgIIBAAAAA==.Novata:BAAALAADCgYIDwAAAA==.',Ny='Nyarlothotep:BAAALAADCggIEAAAAA==.Nykto:BAAALAAECgMIAwAAAA==.Nyxarion:BAAALAADCggICgAAAA==.',['Nø']='Nøx:BAAALAAECgcIEAAAAA==.',Oa='Oakbreaker:BAAALAADCgQIBAAAAA==.',Od='Odwalla:BAAALAAECgMIAwAAAA==.',Ok='Okkata:BAAALAAECgEIAQAAAA==.Oktal:BAAALAAECgUIBQAAAA==.',Om='Omnibine:BAAALAAECgUICAAAAA==.',On='Onlydesert:BAAALAAECgMIAgAAAA==.Onslaught:BAAALAADCgcIDQABLAAECgYIDgACAAAAAA==.',Op='Ophiel:BAAALAADCgIIAgAAAA==.Optiks:BAAALAAECgIIBAAAAA==.',Or='Orcthas:BAAALAAECgMIBAAAAA==.Orksauce:BAAALAAECgYIDAAAAA==.Orsafeli:BAAALAADCgIIAgAAAA==.',Ot='Otsu:BAAALAAECgYIDAAAAA==.',['Oß']='Oß:BAAALAAECgYIDwAAAA==.',Pa='Pajama:BAAALAAECgYIBgAAAA==.Pallytree:BAAALAADCgEIAQAAAA==.Parzival:BAAALAAECggICQAAAA==.Patchface:BAAALAAECgQIBgAAAA==.',Pe='Percepcions:BAAALAADCggIDAAAAA==.Percksmash:BAAALAAECggICAAAAA==.Perkbane:BAAALAAECgMIAwAAAA==.Perkyl:BAAALAAECgEIAQAAAA==.Petraeus:BAAALAAECggIAwAAAA==.',Ph='Phage:BAAALAADCggIDwAAAA==.Pheel:BAAALAADCgcIBwAAAA==.',Pi='Pig:BAAALAADCggIDQAAAA==.Pikevarr:BAAALAADCggIEAAAAA==.Pisáper:BAAALAADCgEIAQAAAA==.Pivy:BAAALAAECgYICgAAAA==.',Pk='Pkrage:BAAALAAECgYIDQAAAA==.',Pl='Plangee:BAAALAADCggICAAAAA==.',Po='Polyethylene:BAAALAAECgUIBgAAAA==.Powerpuffy:BAAALAAECgEIAQAAAA==.',Pw='Pwnman:BAAALAADCgMIAgAAAA==.',['Pë']='Pëaches:BAAALAAECgMIBAAAAA==.',Qu='Quanlain:BAAALAAECgIIBAAAAA==.Quartz:BAAALAADCgcIDQAAAA==.Quidproquo:BAAALAADCggIEwAAAA==.Quillathe:BAAALAAECgUIDAAAAA==.Quit:BAAALAADCggIDAABLAAECgYIDgACAAAAAA==.',Ra='Rashdar:BAAALAAECgcIDAAAAA==.Rattge:BAAALAADCgcICAAAAA==.',Re='Regen:BAAALAADCggICAAAAA==.Revoltêra:BAAALAAFFAIIAgAAAA==.',Rh='Rhadamenth:BAAALAAECgMIBAAAAA==.',Ri='Riie:BAAALAAECgYICQAAAA==.Rinjielune:BAAALAAECgIIAgAAAA==.',Ro='Rockyroad:BAAALAADCgcIEQAAAA==.Roxso:BAABLAAECoEXAAMBAAgIeiOtBQAdAwABAAgIaiOtBQAdAwAIAAcIcBRXEgCsAQAAAA==.',Rx='Rxse:BAAALAAECgEIAQAAAA==.',['Rë']='Rëdmagma:BAAALAAECgIIBAAAAA==.',Sa='Sacrelicious:BAAALAAECgMIAwAAAA==.Safetravels:BAAALAADCggICAAAAA==.Sagewynn:BAAALAADCgYICQAAAA==.Salfroc:BAAALAAECgUIDAAAAA==.Salsaverdé:BAAALAAECgIIAgAAAA==.Saplo:BAAALAAECgIIBAAAAA==.Sapphirosa:BAAALAADCggIDQABLAADCggIEAACAAAAAA==.Sarif:BAAALAAECgYIBgAAAA==.Sarkozy:BAAALAAECgYICgABLAAECgYIDQACAAAAAA==.Saxel:BAAALAAECgQIBwAAAA==.',Sc='Scarletteeth:BAAALAADCggICAAAAA==.Scyras:BAAALAADCgUICAAAAA==.',Se='Sedecho:BAAALAADCgYICgAAAA==.Selcia:BAAALAAECgMIAwAAAA==.Selokk:BAAALAADCgUIBQAAAA==.',Sh='Shadeoraid:BAAALAAECggIBQAAAA==.Shadephoenix:BAAALAAECgIIAgAAAA==.Shamadingdon:BAAALAADCgIIAgAAAA==.Sharavia:BAAALAAECgMIBgAAAA==.Shiftstâins:BAEALAADCggIBgABLAAECggIDwACAAAAAA==.Shisune:BAAALAADCgcIBwAAAA==.Shocktuah:BAAALAAECgUIDAAAAA==.',Si='Sierraah:BAAALAADCgMIAwAAAA==.Sike:BAAALAADCgQIBAAAAA==.Sinful:BAAALAAECgYICAAAAA==.',Sk='Skalagrim:BAAALAAECgMIAwAAAA==.Skeptyk:BAAALAAECgUICAAAAA==.Skolivia:BAAALAAECgcIDQAAAA==.Skood:BAAALAADCggIEAAAAA==.Skophie:BAAALAADCgQIBAABLAAECgcIDQACAAAAAA==.Skèéton:BAAALAADCggIDgAAAA==.',Sl='Slapnutz:BAAALAAECgMIBQAAAA==.Slightdawn:BAAALAAECgMIBgAAAA==.',Sm='Smiley:BAAALAAECgMIBgAAAA==.Smite:BAAALAAECgIIAgAAAA==.Smitti:BAAALAADCgcIBwAAAA==.Smug:BAAALAAECgcIDAAAAA==.',Sn='Snarlock:BAAALAAECgYICwAAAA==.Sneakycommie:BAAALAAECgYIDAAAAA==.Sniffledoo:BAAALAAECgIIBAAAAA==.Snuuf:BAAALAADCgcIDAAAAA==.',So='Sonata:BAAALAAECgYICQAAAA==.Sourfangs:BAAALAAECgcIDwAAAA==.',Sp='Sparklymayhm:BAAALAAECgIIAgAAAA==.Spearz:BAAALAADCggICAAAAA==.Spicymilk:BAAALAAECgYICgAAAA==.Sprawl:BAAALAAECgUICAAAAA==.',Sq='Squidshadow:BAAALAADCgcIEgAAAA==.Squrrlydan:BAAALAAECgYICQAAAA==.',St='Stains:BAAALAADCgYIBgAAAA==.Staint:BAAALAAECgIIAgAAAA==.Staints:BAAALAADCgYIBgAAAA==.Starnights:BAAALAAECgYIBgAAAA==.Statman:BAAALAAECgIIBAAAAA==.Steelbubble:BAAALAAECgcICgAAAA==.Stella:BAAALAAECgIIAgAAAA==.Stengah:BAAALAAECgQIBAAAAA==.Stonedog:BAAALAADCgYIBgABLAAECgcICgACAAAAAA==.Stonimane:BAAALAADCgYIBgABLAADCgcIBwACAAAAAA==.Stopresistng:BAAALAADCgYIBQAAAA==.Strela:BAAALAAECgYICgAAAQ==.',Su='Sunberry:BAAALAAECgEIAQAAAA==.Suraki:BAAALAAECgYICQAAAA==.',Sy='Syand:BAAALAADCgcIDQAAAA==.Syradora:BAAALAADCgYICQAAAA==.Syynner:BAAALAADCggICAAAAA==.',['Sï']='Sïer:BAAALAADCgcIDgAAAA==.',Ta='Tahrin:BAAALAAECgMIAwAAAA==.Talamon:BAAALAAECgYIDgAAAA==.Talatsu:BAAALAAECgMIBAAAAA==.Tanmage:BAAALAAECgcIDAAAAA==.Tanmonk:BAAALAADCgQIBAABLAAECgcIDAACAAAAAA==.Tasina:BAAALAAECgMIBAAAAA==.Taurenamos:BAAALAAECgUICAAAAA==.Taurym:BAAALAAECgMIAwAAAA==.',Te='Tebas:BAAALAAECgIIAwAAAA==.Tenchu:BAAALAADCgYIBgAAAA==.Tenseven:BAAALAAECgMIAwAAAA==.Terrørßlade:BAAALAADCgYIDgAAAA==.',Th='Thalion:BAAALAAECgMIAwAAAA==.Thaurin:BAAALAADCggICAAAAA==.Throwd:BAAALAAECgUIDAAAAA==.Thunderwave:BAAALAAECgEIAQAAAA==.',Ti='Timbok:BAAALAAECgEIAgAAAA==.Tinymend:BAAALAAECgcIDAAAAA==.Tinytony:BAAALAADCggICAAAAA==.',To='Tommib:BAAALAAECgYIDgAAAA==.Toranis:BAAALAADCgcICwAAAA==.Torrents:BAAALAAECgUIDAAAAA==.',Tr='Trinytee:BAAALAAECgQIBQAAAA==.Trottoarkant:BAAALAAECgMIAwAAAA==.',Ty='Tyanol:BAAALAAECgUICQAAAA==.',['Tà']='Tàyla:BAAALAADCgMIAwAAAA==.',['Tð']='Tðxîc:BAAALAAECgMIBQAAAA==.',Um='Umberlee:BAAALAADCggIFwAAAA==.Umbrathal:BAAALAAECgYICQAAAA==.Umbraxakar:BAAALAAECgYIDgAAAA==.Umbris:BAAALAAECgMIBgAAAA==.',Un='Ungroggy:BAAALAAECgUIBgAAAA==.Unhooly:BAAALAADCgcIDQAAAA==.',Ut='Uthookem:BAAALAADCgUIBQAAAA==.',Va='Valad:BAAALAADCggIDQAAAA==.Valkoienne:BAAALAADCgcIEQAAAA==.',Ve='Vegan:BAAALAADCgUIBQAAAA==.Velessa:BAAALAAECgIIAgAAAA==.Veng:BAAALAADCgcIBwABLAAECgIIAgACAAAAAA==.Verind:BAAALAAECgMIAwABLAAECggIFwAFAOUjAA==.Vertheras:BAAALAAECgUIDAAAAA==.',Vi='Vin:BAAALAADCggICAAAAA==.Vincentius:BAAALAAECgMIAwAAAA==.Vinhelsin:BAAALAADCgUIBwAAAA==.',Vo='Voidwrld:BAAALAADCggICAAAAA==.Voron:BAAALAAECgIIAgAAAA==.',Wa='Warlex:BAAALAAECgYICQAAAA==.Warstin:BAAALAADCgYIBgAAAA==.Warstina:BAAALAADCggICAAAAA==.Waterwhip:BAAALAAECgEIAQAAAA==.',We='Westfall:BAAALAAECgcIDwAAAA==.',Wh='Whirl:BAAALAADCgYIBgABLAAECgcICgACAAAAAA==.',Wi='Willrun:BAAALAADCgcIDAAAAA==.Willy:BAAALAAECggICQAAAA==.Witheredyam:BAAALAADCgcICgAAAA==.',Wo='Wompeal:BAAALAADCggIEAAAAA==.Wonkwonk:BAAALAAECgIIAwAAAA==.',Wr='Wravlock:BAAALAAECgcIDAAAAA==.',Wy='Wystan:BAAALAAECgUIDAAAAA==.',['Wé']='Wés:BAAALAAECgUIDAAAAA==.',['Wí']='Wíckedwítch:BAAALAAECggIBgAAAA==.',Xa='Xamsuciteey:BAAALAADCggICAABLAAECgIIAgACAAAAAA==.Xayla:BAAALAADCgcIFQAAAA==.',Xe='Xentow:BAAALAAECgUICAAAAA==.',Xt='Xtrasweet:BAAALAAECgEIAQAAAA==.',Ya='Yarel:BAAALAADCggICQABLAAECggIFwAJAGIiAA==.',Ye='Yesinea:BAAALAADCgQICAAAAA==.',Yi='Yiro:BAAALAAECgMIAwAAAA==.',Ys='Ysaluna:BAAALAADCgUIBQAAAA==.',Yu='Yukiina:BAAALAADCgIIAgAAAA==.',Za='Zaccheus:BAAALAADCgMIAwABLAAECgEIAQACAAAAAA==.',Ze='Zeebra:BAAALAAECgEIAQAAAA==.Zeesaw:BAAALAAECgQIBwAAAA==.Zeretrix:BAAALAAECgcIBwAAAA==.Zeriph:BAAALAADCgUIBQAAAA==.',Zy='Zynothrian:BAAALAAECgUIDAAAAA==.',['Ðe']='Ðemonic:BAAALAADCgQIBAAAAA==.',['Ñu']='Ñublo:BAAALAAECgMIBQAAAA==.',['Üb']='Überhealz:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end