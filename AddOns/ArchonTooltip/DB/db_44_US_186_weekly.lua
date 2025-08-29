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
 local lookup = {'Unknown-Unknown','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Rogue-Subtlety','Rogue-Assassination',}; local provider = {region='US',realm="Sen'jin",name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aalliyah:BAAALAAECgMIBgAAAA==.',Ac='Acathaya:BAAALAAECgYIBgAAAA==.',Ah='Ahsoka:BAAALAADCgMIBAAAAA==.',Ai='Aim:BAAALAAECgYICQAAAA==.',Al='Alaina:BAAALAADCgMIAwAAAA==.Albinoo:BAAALAAECgQIBAAAAA==.Alestraza:BAAALAADCgMIAwAAAA==.Alice:BAAALAAECgMIAwAAAA==.Alicil:BAAALAAECgUIBQAAAA==.Aliveagain:BAAALAADCgIIAwAAAA==.Allek:BAAALAADCgEIAQAAAA==.Alohasnakbar:BAAALAAECgMIAwAAAA==.',Am='Amako:BAAALAAECgMIBQAAAA==.Amaterasu:BAAALAAECgcIEAAAAA==.Amergin:BAAALAADCgYIBgAAAA==.Ammathos:BAAALAADCgQIBAAAAA==.',An='Angelbyday:BAAALAADCggIDwAAAA==.Annagul:BAAALAADCgIIAgAAAA==.Annieoaklea:BAAALAADCgIIAwAAAA==.',Aq='Aquillus:BAAALAADCgcIDAAAAA==.',Ar='Argathne:BAAALAADCggICQAAAA==.Argussy:BAAALAAECgcIEQAAAA==.Arkad:BAAALAADCgcICQAAAA==.',As='Asherbug:BAAALAADCgcIBQABLAAECgQIBwABAAAAAA==.Asoonaa:BAAALAADCggIFQAAAA==.Astana:BAAALAADCgcIBwAAAA==.Astraii:BAAALAAECgMIBQAAAA==.',At='Attrox:BAAALAAECgYICQAAAA==.Atulzul:BAAALAADCggIFwAAAA==.',Au='Auridia:BAAALAADCgIIAwAAAA==.',Av='Avakai:BAAALAAECgEIAQAAAA==.Avalef:BAAALAAECgMIBwAAAA==.',Az='Azalin:BAAALAADCgUIBQAAAA==.Azbaal:BAAALAADCgEIAQAAAA==.Azbeel:BAAALAADCgEIAQAAAA==.',Ba='Backtrak:BAAALAAECgYICgAAAA==.Bamboomnster:BAAALAADCggICAAAAA==.Bareeye:BAAALAADCgIIAgAAAA==.Bassinel:BAAALAAECgEIAQAAAA==.Bastian:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.',Be='Beefout:BAAALAAECgMIBAAAAA==.Beesbok:BAAALAAECgIIAgAAAA==.',Bi='Bigdaddydan:BAAALAAECgMIAwAAAA==.Bishämon:BAAALAAECgIIAwAAAA==.',Bl='Blasphemian:BAAALAAECgcIEAAAAA==.Bled:BAAALAADCgcIBwAAAA==.Blinddate:BAAALAAECgcIEAAAAA==.Blindside:BAAALAAECgUICAAAAA==.Bluejayne:BAAALAAECgMIAwAAAA==.',Bo='Bobbyrrzz:BAAALAADCgQIBAAAAA==.Bohe:BAAALAAECgYICgAAAA==.Bopya:BAAALAAECgMIBAAAAA==.Borke:BAAALAAECgYICQAAAA==.Bosconovitch:BAAALAAECgYIBgAAAA==.Bouseman:BAAALAADCgcICgAAAA==.',Br='Brandn:BAAALAAECgcIEAAAAA==.Brewtis:BAAALAADCggIFgAAAA==.Bridgett:BAAALAAECgYICgAAAA==.Brockton:BAAALAADCgMIAQAAAA==.',Bu='Buffarcane:BAAALAADCggIEAAAAA==.Bunnyhoper:BAAALAAECgQIBwAAAA==.',['Bü']='Bümps:BAAALAADCggIEAAAAA==.',Ca='Cabrakan:BAAALAAECgYIDQAAAA==.Caladur:BAAALAADCgQIBAABLAAECgcIEAABAAAAAA==.Caledor:BAAALAAECgcIEAAAAA==.Carves:BAAALAAECgYICQAAAA==.Cataclysmïc:BAAALAADCgIIAgABLAAECgcIDgABAAAAAA==.Catrin:BAAALAADCgcIBwAAAA==.Caunyi:BAAALAADCgYIBgAAAA==.',Ce='Cerdide:BAAALAAECgMIAwAAAA==.Cerebn:BAAALAAECgMIBgAAAA==.',Ch='Champeon:BAAALAADCgIIAgAAAA==.Chapo:BAAALAAECgMIAwAAAA==.Cheesedog:BAAALAAECgIIAgAAAA==.Chrís:BAAALAADCgYIDAAAAA==.',Ci='Cintiak:BAAALAADCgEIAgAAAA==.',Cl='Clambake:BAAALAADCgYIBgAAAA==.Clankerion:BAAALAADCgcIDQABLAAECgQIBQABAAAAAA==.Clashe:BAAALAAECgMIBgAAAA==.',Co='Coalesce:BAAALAAECgEIAQAAAA==.Coursouvra:BAAALAAECgEIAQAAAA==.',Cr='Crazylegs:BAAALAAECgMIBAAAAA==.Creelope:BAAALAADCgEIAQAAAA==.Crimes:BAAALAADCggIDAAAAA==.Crimsonsong:BAAALAAECgMIBQAAAA==.Crössblesser:BAAALAAECgMIAwAAAA==.',Cy='Cyrial:BAAALAAECgYICgAAAA==.',Da='Dai:BAAALAADCgMIAwAAAA==.Darctricity:BAAALAAECgMIBwAAAA==.Daredelf:BAAALAADCgcICwAAAA==.Darkhart:BAAALAADCgYIBgAAAA==.Darmadious:BAAALAADCggICAAAAA==.Dazao:BAAALAADCggICAAAAA==.',De='Deathsranger:BAAALAAECgEIAQAAAA==.Deianne:BAAALAAECgYIDgAAAA==.Dekar:BAAALAAECgIIAwAAAA==.Deks:BAAALAAECgYIDAAAAA==.Dellexis:BAAALAADCgYIBwAAAA==.Demonas:BAAALAADCgcIBwAAAA==.Depletechkn:BAAALAAECgcIDgAAAA==.Dewiaychardi:BAAALAAECgMIBgAAAA==.Deäthcowd:BAAALAAECgcIEQAAAA==.',Do='Dorania:BAAALAAECgYICQAAAA==.Dorei:BAAALAAECgUICAAAAA==.Dotmasta:BAAALAAECgYICQAAAA==.Doublecup:BAAALAAECgMIAwAAAA==.Downsie:BAAALAADCgQIBAAAAA==.',Dr='Dracoora:BAAALAAECgUICAAAAA==.Dracora:BAAALAAECgUIBQABLAAECgUICAABAAAAAA==.Dracorashamm:BAAALAAECgEIAQAAAA==.Dragonmo:BAAALAADCgIIAgAAAA==.Draktorus:BAAALAADCgcICwAAAA==.Draziel:BAAALAAECgMIBQAAAA==.Droggon:BAAALAAECgEIAQAAAA==.Droski:BAAALAAECgEIAQAAAA==.Dryádalis:BAAALAADCgcIDgAAAA==.',Du='Dubstêp:BAAALAADCgIIAgAAAA==.Dunhammer:BAAALAAECgYICAAAAA==.Dustzen:BAAALAAECgMIBAAAAA==.',Dy='Dyhrd:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.',Ed='Eddiebravo:BAAALAADCggIDwAAAA==.',Ei='Eirtae:BAAALAAECgMIBQAAAA==.',El='Elpa:BAAALAADCgEIAQAAAA==.Elthar:BAAALAADCggIEgAAAA==.',En='Envy:BAAALAAECgcIEAAAAA==.',Et='Etro:BAAALAADCggIDwAAAA==.',Ev='Evangila:BAAALAAECgMIBAAAAA==.Evoked:BAAALAADCgIIAwAAAA==.',Ew='Ewaker:BAAALAAECgEIAQAAAA==.',Fa='Faerundur:BAAALAAECgEIAQAAAA==.Fayeth:BAAALAADCggICAAAAA==.',Fe='Felco:BAAALAAECgcIEgAAAA==.Ferhunz:BAAALAAECgEIAQAAAA==.Festerdragon:BAAALAADCgcIDgAAAA==.',Ff='Ffejshock:BAAALAAECgMIBAAAAA==.',Fi='Filthypally:BAAALAADCggIDwAAAA==.Fistbump:BAAALAAECgYICQAAAA==.Fitzjuno:BAAALAAECgYIBgAAAA==.',Fl='Flathnagin:BAAALAADCggICAAAAA==.Floorpov:BAAALAAECgMIAwABLAAECgQIBAABAAAAAA==.',Fo='Formintoall:BAAALAADCgIIAgAAAA==.Fortified:BAAALAAECgcIDgAAAA==.Fostock:BAAALAAECgEIAQAAAA==.',Fr='Frisket:BAAALAADCgUIBQAAAA==.Frostatexam:BAAALAADCgQIBAAAAA==.Frostyolaf:BAAALAADCgcIDAAAAA==.Frottle:BAAALAAECgcIEAAAAA==.',Ga='Gaius:BAAALAADCggICAAAAA==.Gamonwan:BAAALAADCgcIBwAAAA==.',Ge='Gertha:BAAALAADCggICAAAAA==.',Gi='Girthen:BAAALAADCggIDgAAAA==.',Gl='Glad:BAAALAADCgQIBAABLAAECgYIBwABAAAAAA==.',Go='Goq:BAAALAADCgcICAAAAA==.',Gr='Grampy:BAAALAADCgIIAwAAAA==.Gruash:BAAALAADCgQIBAAAAA==.',Gu='Guliyami:BAAALAAECggICAAAAA==.Gullurg:BAAALAAECgUIBQAAAA==.',Gw='Gwalsby:BAAALAADCggICQAAAA==.Gweneviere:BAAALAAECgEIAQAAAA==.',['Gá']='Gáthix:BAAALAADCgMIAwAAAA==.',Ha='Hadesfalcon:BAAALAAECgYICAAAAA==.Hainne:BAAALAADCggICQAAAA==.Hamburgalur:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Handrob:BAAALAAECgYICgAAAA==.Haniris:BAAALAADCgYIBgAAAA==.Happybear:BAAALAADCgcIBwAAAA==.Happyguy:BAAALAADCgcIBwAAAA==.Harilas:BAAALAADCgUICAAAAA==.Harrier:BAAALAAECgYIDAAAAA==.Hayles:BAAALAAECgUIBwAAAA==.',He='Healteamsix:BAAALAAECgYIDAAAAA==.Heaps:BAAALAADCgcICAAAAA==.Hebrews:BAAALAAECgQIBQAAAA==.Hebrêws:BAAALAADCgcIDgABLAAECgQIBQABAAAAAA==.Hefty:BAAALAAECgYIBwAAAA==.Helann:BAAALAAECgEIAQAAAA==.Heliös:BAAALAADCgMIAwAAAA==.Hempgirl:BAAALAADCggIEAAAAA==.',Hi='Hitowerr:BAAALAADCgMIAwAAAA==.',Ho='Hollywoodx:BAAALAAECgQIBwAAAA==.Hotstickfast:BAAALAAECgMIBAAAAA==.',Hr='Hruken:BAAALAAECgIIAgAAAA==.',Hu='Hungrymuffin:BAAALAADCggICAAAAA==.Hungrywaffle:BAAALAADCgcICQAAAA==.',Hy='Hynestus:BAAALAADCgcICAAAAA==.',Ia='Iamgroot:BAAALAADCgcIDAAAAA==.',Ig='Igneel:BAAALAAECgEIAQAAAA==.',Il='Illanea:BAAALAADCgQIBgAAAA==.Illidur:BAAALAADCgMIAwAAAA==.Illidùr:BAAALAADCgMIAQAAAA==.Illïdur:BAAALAADCggIDgAAAA==.',Im='Immunogoblin:BAAALAAECgIIAgAAAA==.',In='Inkarnata:BAAALAAECgYIBgAAAA==.Interitüs:BAAALAADCgcIBwAAAA==.',Ir='Irok:BAAALAAECgMIBAAAAA==.Irokchaos:BAAALAADCgMIAwABLAAECgMIBAABAAAAAA==.Irokrage:BAAALAADCgUIBQABLAAECgMIBAABAAAAAA==.',Iy='Iykyk:BAAALAAECgMIBgAAAA==.',Ja='Jarlak:BAAALAAECgcIEAAAAA==.',Je='Jegintarth:BAAALAAECgEIAQAAAA==.',Jh='Jhyl:BAAALAAECgYICQAAAA==.',Ji='Jimithing:BAAALAADCgcICgAAAA==.',Jo='Johnis:BAAALAADCgMIAwAAAA==.Jordroy:BAAALAAECgcIEAAAAA==.',Ju='Julnar:BAAALAADCgQIBgAAAA==.',Ka='Kaanuu:BAAALAAECgYICQAAAA==.Kabbage:BAAALAAECgYIEQAAAA==.Kadon:BAAALAAECgYIBwABLAAECgcIEAABAAAAAA==.Kalter:BAAALAAECgMIAwAAAA==.Kappa:BAAALAADCgUIBQAAAA==.Kaprisun:BAAALAADCggIEAAAAA==.',Ke='Keigo:BAAALAAECgEIAQAAAA==.Keizth:BAAALAADCgIIAgAAAA==.Kemanthuurel:BAAALAAECgMIBQAAAA==.Keyring:BAAALAADCgYIBQAAAA==.',Kh='Khage:BAAALAAECggIEgAAAA==.Khaoticus:BAAALAAECgEIAQAAAA==.',Ki='Kiaz:BAAALAAECgcIDgAAAA==.Killayla:BAAALAADCgQICAAAAA==.Kissmycowlip:BAAALAADCgQIBAAAAA==.',Kn='Knucknuckk:BAAALAADCggIEAAAAA==.',Ko='Kobi:BAAALAADCgIIAgAAAA==.Korfane:BAAALAAECgYICgAAAA==.Korja:BAAALAADCgMIBAAAAA==.Kossak:BAAALAAECgMIAwAAAA==.Kozal:BAAALAADCgYIBgAAAA==.',Kr='Krazystrike:BAAALAADCggIEAAAAA==.Krusher:BAAALAAECgUIBgAAAA==.',Ku='Kuber:BAAALAAECgcIEAAAAA==.Kurousagi:BAAALAADCggICAAAAA==.',Ky='Kyrenna:BAAALAADCgIIAgAAAA==.',['Kí']='Kímahri:BAAALAADCgcICAAAAA==.Kísh:BAAALAADCgcIDgABLAAECgQIBQABAAAAAA==.',La='Laelene:BAAALAADCggIHwAAAA==.Lailapp:BAAALAADCgIIAgAAAA==.Lamonda:BAABLAAECoEVAAICAAgIcBaBCAAmAgACAAgIcBaBCAAmAgAAAA==.Laurelina:BAAALAADCgcIDAAAAA==.',Li='Lightydragon:BAAALAAECgMIAwAAAA==.Linthia:BAAALAADCgcIBwAAAA==.Littlesam:BAAALAAECgMIAwAAAA==.',Ll='Llucas:BAAALAAECgcIEQAAAA==.',Lo='Lock:BAAALAAECgMIAwAAAA==.Lockofwar:BAAALAADCgYICgAAAA==.Loeky:BAAALAADCgUIBQAAAA==.Lonk:BAAALAADCgQIBAAAAA==.Lowgravity:BAAALAAECgYICgAAAA==.Loycen:BAAALAAECgcIDgAAAA==.',Lu='Lunarosá:BAAALAAECgQIBwAAAA==.Lupodruidia:BAAALAADCggICAAAAA==.',Ly='Lyllyth:BAAALAADCgcIDAAAAA==.Lyzyrdwyzyrd:BAAALAADCggICAABLAAECgYICgABAAAAAA==.',Ma='Madren:BAAALAAECgMIAwAAAA==.Magnimus:BAAALAAECgYICgAAAA==.Manikk:BAAALAAECgYIBwAAAA==.Manu:BAAALAAECgEIAQAAAA==.Maplefoxx:BAAALAAECgYICQAAAA==.Marlik:BAAALAAECgMIBwAAAA==.Maylyn:BAAALAADCgYIBgAAAA==.',Me='Meducea:BAAALAADCgIIAgAAAA==.Megadööm:BAAALAAECgcIEQAAAA==.Meldormra:BAAALAADCgEIAQAAAA==.',Mi='Michurion:BAAALAADCggIFAAAAA==.Mikori:BAAALAAECgMIAwAAAA==.Milhelia:BAAALAADCgcICAAAAA==.Milliim:BAAALAAECgEIAQAAAA==.Ministerry:BAAALAADCgQIBAAAAA==.Missfyre:BAAALAADCggICAABLAAECggIAgABAAAAAA==.Mistalia:BAAALAADCggIDwAAAA==.',Mo='Mobium:BAAALAADCggIDwAAAA==.Monkryial:BAAALAADCggICAABLAAECgYICgABAAAAAA==.Montyopython:BAAALAAECgYICQAAAA==.Moocowd:BAAALAADCggICAAAAA==.Morgrus:BAAALAADCggICAAAAA==.Morgund:BAAALAADCgYIBgAAAA==.Mortissia:BAAALAADCgIIAwAAAA==.Mournin:BAAALAAECgYICQAAAA==.',Mu='Murista:BAAALAAECgMIBQAAAA==.',My='Myslicer:BAAALAADCgMIAwAAAA==.',['Mà']='Màcaria:BAAALAADCgMIAwAAAA==.',['Mì']='Mìss:BAAALAADCgUIBQAAAA==.',Na='Naenia:BAAALAADCgEIAQAAAA==.Nazzaryth:BAAALAADCgcIDAAAAA==.',Ne='Neekmillz:BAAALAAECgcIDwAAAA==.Nefret:BAAALAAECgMIAwAAAA==.Neilos:BAAALAADCggICwAAAA==.Nergal:BAAALAAECgIIAwAAAA==.Neverslucky:BAAALAADCggICAAAAA==.Nevertanked:BAAALAAECgYICQAAAA==.',Ni='Niipplets:BAABLAAECoESAAQDAAcIDyMfGAD4AQADAAUIbiQfGAD4AQAEAAMIqCKYEAAqAQAFAAEIPRgpSwBAAAAAAA==.Nilophyte:BAAALAAECgcIDwAAAA==.Nitrous:BAAALAAECgMIBAAAAA==.',No='Nockers:BAAALAADCgYICgAAAA==.Nolenardan:BAAALAAECgYICgAAAA==.Notahuntard:BAAALAADCgYIBgAAAA==.Notspanky:BAAALAAECgcIDAAAAA==.',Ny='Nyrrazhy:BAAALAADCggICwAAAA==.',['Nô']='Nôvus:BAAALAAECgYIBgAAAA==.',Ob='Obiion:BAAALAAECgcIEQAAAA==.',Om='Omërta:BAAALAADCgMIAwAAAA==.',On='Onion:BAAALAAECgEIAQAAAA==.',Or='Orgazmoo:BAAALAAECgYICwAAAA==.',Ov='Overraided:BAAALAAECgYICQAAAA==.',Pa='Pagtuga:BAAALAADCggIHQAAAA==.Pandaìd:BAAALAADCggICAAAAA==.Paschendale:BAAALAADCggIFAAAAA==.Paulooch:BAAALAAECgIIAgAAAA==.',Pe='Pesobeshiftn:BAAALAADCgUIBwAAAA==.Petals:BAAALAAECgEIAQAAAA==.',Ph='Phatemage:BAAALAADCgYIBgABLAAECgcIEQABAAAAAA==.Phatemonk:BAAALAADCggICQABLAAECgcIEQABAAAAAA==.Phatepriest:BAAALAADCggICAABLAAECgcIEQABAAAAAA==.Phateshaman:BAAALAAECgcIEQAAAA==.Phatpanda:BAAALAADCggIDQAAAA==.',Pi='Pico:BAAALAAECgYIBgAAAA==.Pieeftw:BAAALAADCggIDwAAAA==.Pippy:BAAALAADCgYIBgAAAA==.',Po='Pokcmvmxckm:BAAALAAECgYICgAAAA==.Pokcmxmvkcm:BAAALAADCggICAAAAA==.Ponie:BAAALAAECgUIBQAAAA==.Porax:BAAALAADCgcIBwAAAA==.',Pr='Praimfaya:BAAALAADCgQIBAAAAA==.Primygosa:BAAALAAECgQIBQAAAA==.',Pt='Ptsdthegamer:BAAALAADCgcIEQAAAA==.',Pu='Pugg:BAAALAAECgMIBwAAAA==.Punchco:BAAALAADCggICQABLAAECgcIEgABAAAAAA==.',Qu='Quikclot:BAAALAAECgEIAQAAAA==.Quivers:BAAALAAECggIBgAAAA==.Qusay:BAAALAAECgMIBAAAAA==.',Ra='Raidedx:BAAALAADCgEIAQAAAA==.Raimee:BAAALAAECgcIDQAAAA==.Raynes:BAAALAADCgYIBgABLAAECgUIBwABAAAAAA==.',Re='Retrovibe:BAEALAAECgMIBwAAAA==.Rev:BAAALAADCgEIAQAAAA==.Reygar:BAAALAADCgEIAQABLAADCgUIBgABAAAAAA==.',Rh='Rhyleejo:BAAALAADCgIIAwAAAA==.',Ri='Rictuss:BAAALAADCgcICAAAAA==.Rien:BAAALAAECgMIBwAAAA==.Rione:BAAALAAECgQIBQAAAA==.',Ro='Rocq:BAAALAAECgcIDAAAAA==.Roflcoptor:BAAALAAECgIIAwAAAA==.Rot:BAAALAAECgEIAQAAAA==.Rothrahn:BAAALAADCgUIBQABLAAECgcIDQABAAAAAA==.Rothron:BAAALAAECgcIDQAAAA==.',Ru='Ruvurongtime:BAAALAADCgIIAgABLAAECgYIBgABAAAAAA==.',Sa='Saelylda:BAAALAAECgYIBgABLAAECgYICwABAAAAAA==.Saeyn:BAAALAAECgYICwAAAA==.Sarasvati:BAAALAAECgcIEAAAAA==.Savriemina:BAAALAAFFAIIAgAAAA==.',Sc='Scheckles:BAAALAAECgMIAwAAAA==.Schweppesy:BAAALAADCgQICAAAAA==.',Se='Seezar:BAAALAADCgYIBgAAAA==.Seleny:BAAALAADCgcIDAAAAA==.Semya:BAAALAAECgEIAQAAAA==.Senistus:BAAALAADCgIIAgAAAA==.Sennkargash:BAAALAADCgcIDgAAAA==.Sepsislol:BAAALAADCgEIAQAAAA==.Seraphíne:BAABLAAECoEYAAIGAAgIuBRBEwAaAgAGAAgIuBRBEwAaAgAAAA==.Serasmash:BAAALAAECgUIBQAAAA==.Serzul:BAAALAAECgYIBgAAAA==.Sewazbek:BAAALAADCggIDAAAAA==.',Sh='Shamanate:BAAALAAECgIIAgAAAA==.Sharin:BAAALAADCgcIEQAAAA==.Shepard:BAAALAADCggICAAAAA==.Shepburn:BAAALAADCgEIAQABLAAECgYICgABAAAAAA==.Shninzy:BAABLAAECoEVAAMHAAgI2yNRAwBJAgAHAAYI2iJRAwBJAgAIAAUIsiQOEwD5AQAAAA==.Shocktiger:BAAALAADCggIDwAAAA==.Shrilla:BAAALAAECgYICQAAAA==.',Si='Sidonay:BAAALAADCggICAAAAA==.Sikarr:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Sikomode:BAAALAAECgMIAwAAAA==.Sinnershep:BAAALAAECgYICgAAAA==.Sinnister:BAAALAAECgcIEQAAAA==.Siouxii:BAAALAAECgIIAgAAAA==.',Sl='Slamaros:BAAALAAECgMIBQAAAA==.Slugbug:BAAALAAECgEIAgABLAAECgYIDAABAAAAAA==.',So='Soffereel:BAAALAAECggIBAAAAA==.Soyonami:BAAALAADCgEIAQAAAA==.',Sp='Spamsalot:BAAALAAECggIDgAAAA==.Sparklenips:BAAALAAECgIIAwAAAA==.Spazzn:BAAALAAECgIIAgAAAA==.',St='Staraynne:BAAALAADCgIIAwAAAA==.Starfiery:BAAALAADCggIEgAAAA==.Starfrenzy:BAAALAADCgMIBAABLAADCggIEgABAAAAAA==.Starheist:BAAALAADCgQIAQABLAADCggIEgABAAAAAA==.Starmaster:BAAALAADCgEIAQABLAADCggIEgABAAAAAA==.Stihll:BAAALAAECgMIBQAAAA==.Stormlight:BAAALAAECgYICwAAAA==.Strea:BAAALAAECgYIBwAAAA==.Stryk:BAAALAADCggICAAAAA==.Stèllar:BAAALAADCggIEQAAAA==.',Su='Sundari:BAAALAADCgcIBwAAAA==.Sunnybrew:BAAALAADCgcIEQAAAA==.Suzushiiro:BAEALAADCggICQAAAA==.',Sw='Sweetangel:BAAALAADCgQIBAAAAA==.',Sy='Sylerolan:BAAALAADCgYICwABLAADCgcIBwABAAAAAA==.Sylvauk:BAAALAAECgEIAQAAAA==.Syndel:BAAALAAECgIIAgAAAA==.',['Så']='Såyoko:BAAALAAECgMIBgAAAA==.',Ta='Tacødemøn:BAAALAADCgcIDAAAAA==.Tadinanefer:BAAALAAECgEIAQAAAA==.Tailstwo:BAAALAAECgQIBwAAAA==.Taintslammer:BAAALAADCgcIDgAAAA==.Talmi:BAAALAADCgIIAwAAAA==.Tamiria:BAAALAAECgYICQAAAA==.Tanora:BAAALAADCgQIBAAAAA==.',Te='Terryfied:BAAALAADCgcIDAAAAA==.Tethlis:BAAALAAECgQIBwAAAA==.',Th='Thalamar:BAAALAAECgMIAwAAAA==.Thanlelak:BAAALAADCgYIBwAAAA==.Thecollector:BAAALAAECgUIBwAAAA==.Thecrazyt:BAAALAADCgcIBwAAAA==.Thefearful:BAAALAAECgcIDQAAAA==.Thelios:BAAALAAECgcIEQAAAA==.Theomore:BAAALAADCgEIAQAAAA==.Thiccum:BAAALAADCggICAABLAAECgYICgABAAAAAA==.Thorixxes:BAAALAADCgMIAwAAAA==.Thragar:BAAALAAECgYICgAAAA==.Thunderstorm:BAAALAAECgYIBgAAAA==.Thwisher:BAAALAADCggICAAAAA==.',Ti='Timtalks:BAAALAAECgUIBQAAAA==.Tishoro:BAAALAADCgUIBgAAAA==.Titan:BAAALAADCgIIAwAAAA==.',Tm='Tmagnome:BAAALAADCgcICgAAAA==.',To='Tooggy:BAAALAAECggIEQAAAA==.',Tr='Tragic:BAAALAADCggICQAAAA==.Tranqulizer:BAAALAAECgMIAwAAAA==.Tremira:BAAALAADCgMIBAAAAA==.Trickshot:BAAALAADCggIEAAAAA==.Triggered:BAAALAAECgUIBQAAAA==.Trogdot:BAAALAADCgMIAwAAAA==.Trogtotem:BAAALAADCgcIBwAAAA==.Trynior:BAAALAAECgEIAQAAAA==.',Ts='Tsarelina:BAAALAADCgEIAQAAAA==.',Tu='Tuatha:BAAALAAECgcIDQAAAA==.Tueten:BAAALAADCggIEAAAAA==.',Tw='Twisteddemon:BAAALAAECgIIAgABLAAECggIBQABAAAAAA==.Twisteddruid:BAAALAAECgEIAQABLAAECggIBQABAAAAAA==.Twistedpally:BAAALAAECggIBQAAAA==.',Ty='Tyrranax:BAAALAAECgcIEQAAAA==.',['Tî']='Tîmshel:BAAALAAECgcIEAAAAA==.',Uh='Uhohdh:BAAALAAFFAIIAgAAAA==.',Um='Umbraursa:BAAALAADCggIDQAAAA==.',Un='Uncledeath:BAAALAAECggIAgAAAA==.Unos:BAAALAAECggIAgABLAAECggIBgABAAAAAA==.Unosdk:BAAALAADCgcICQABLAAECggIBgABAAAAAA==.',Ur='Urmombangs:BAAALAAECgMIBAAAAA==.Urvin:BAAALAAECgEIAQAAAA==.',Uw='Uwupal:BAAALAAECgEIAQAAAA==.',Va='Valkoros:BAAALAADCggICAAAAA==.Vaniille:BAAALAAECgIIAgAAAA==.Vanitas:BAAALAAECgMIBwAAAA==.',Ve='Veddus:BAAALAAECgMIBAAAAA==.Veleice:BAAALAADCgIIAgAAAA==.Vennisa:BAABLAAECoEVAAIGAAgI3SJ/AgAgAwAGAAgI3SJ/AgAgAwAAAA==.',Vh='Vhelkan:BAAALAAECgMIBQAAAA==.',Vi='Vinikings:BAAALAAECgUIBgAAAA==.',Vo='Vonns:BAAALAAECgMIBAAAAA==.',['Vé']='Véex:BAAALAAECgIIAgAAAA==.Véstria:BAAALAAECgEIAQAAAA==.',Wa='Walayso:BAAALAADCgIIAgABLAADCgYICgABAAAAAA==.Warlaner:BAAALAADCgEIAQAAAA==.Warlokholmes:BAAALAAECgQIBAAAAA==.',We='Wedel:BAAALAAECgcIDgAAAA==.Wesup:BAAALAAECgMIBAAAAA==.',Wh='Whodahoda:BAAALAADCgQIBAAAAA==.',Wo='Woodhøuse:BAAALAADCgYICwAAAA==.Woof:BAAALAAECgIIAgAAAA==.Wookieemulch:BAAALAAECgEIAQAAAA==.',Wu='Wumbo:BAAALAAECgcIDwAAAA==.',Xa='Xandabull:BAAALAADCgIIAwAAAA==.Xaniengenn:BAAALAADCgcIDAAAAA==.Xanuel:BAAALAADCggICAAAAA==.',Xe='Xem:BAAALAADCgcIBwAAAA==.Xenity:BAAALAAECgQIBQAAAA==.Xerosyn:BAAALAAECgYIBgAAAA==.',Xo='Xochil:BAAALAAECgYICAAAAA==.',Xp='Xp:BAAALAADCgYIBgAAAA==.',Ya='Yagob:BAAALAADCgMIAwAAAA==.Yaight:BAAALAADCgcIBwAAAA==.Yaimahuntard:BAAALAAECgIIAwAAAA==.',Ye='Yeezùs:BAAALAAECgYICgAAAA==.',Ys='Yserà:BAAALAADCgYIBgAAAA==.',Yu='Yuffie:BAAALAADCggIFAAAAA==.',['Yò']='Yògibear:BAAALAADCgcIDAAAAA==.',Za='Zackiris:BAAALAADCgYIBgAAAA==.Zaknafein:BAAALAAECgYICAAAAA==.Zanazoth:BAAALAAECgYICQAAAA==.Zangetzu:BAAALAADCgMIAwAAAA==.Zanziri:BAAALAAECgEIAQAAAA==.',Ze='Zeffyre:BAAALAADCgcIDAAAAA==.Zeknor:BAAALAAECgQIBwAAAA==.',Zh='Zhindia:BAAALAADCgEIAQAAAA==.',Zi='Zigves:BAAALAADCgYIBgAAAA==.Zillaby:BAAALAAECgMIBAAAAA==.Zips:BAAALAADCgcIBwAAAA==.',Zo='Zolo:BAAALAADCgcIBwAAAA==.Zoltair:BAAALAAECgEIAQAAAA==.Zorrteck:BAAALAAECgQIBwAAAA==.',Zp='Zp:BAAALAAECgcIDQAAAA==.',Zu='Zug:BAAALAAECgMIBQAAAA==.Zuuk:BAAALAAECgQIBAAAAA==.',Zx='Zxerm:BAAALAADCggIEgAAAA==.',['Zé']='Zérö:BAAALAADCgUICAAAAA==.',['Ân']='Ânnié:BAAALAADCgYIBgAAAA==.',['Év']='Éviljèsus:BAAALAAECgMIBAAAAA==.',['Ìs']='Ìsis:BAAALAADCggICAAAAA==.',['Ïl']='Ïllidur:BAAALAADCgQIBAAAAA==.',['Ôm']='Ômëñ:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end