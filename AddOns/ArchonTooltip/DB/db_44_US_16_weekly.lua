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
 local lookup = {'Unknown-Unknown','Druid-Feral','Mage-Frost','Hunter-BeastMastery','Paladin-Retribution','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Destruction','Rogue-Assassination','Shaman-Elemental',}; local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Absoul:BAAALAAECgYICwAAAA==.',Ac='Acedia:BAAALAAECgYICgAAAA==.',Ad='Adellas:BAAALAAECgYIDgAAAA==.Adern:BAAALAAECgYIDgAAAA==.',Ae='Aelali:BAAALAADCgMIAwAAAA==.Aertic:BAAALAADCggIDgAAAA==.',Ag='Ageling:BAAALAADCgcICwAAAA==.',Ai='Ailene:BAAALAADCgIIAgABLAADCgcIBwABAAAAAA==.',Ak='Akmandoxan:BAAALAADCggIFwAAAA==.Akshammy:BAAALAADCgcIBwAAAA==.',Al='Aladestar:BAAALAAECgcICQAAAA==.Albinorogue:BAAALAAECgMIAwAAAA==.Alderleise:BAAALAADCgcIDgAAAA==.Alexein:BAAALAAECgcIDgAAAA==.Alianna:BAAALAAECgMIAwAAAA==.Alldwasha:BAAALAADCgcIBwAAAA==.',Am='Amets:BAAALAAECgYICwAAAA==.',An='Anabel:BAAALAADCgEIAQAAAA==.Anamii:BAAALAAECgQIBAAAAA==.Ansuz:BAAALAADCggIDAAAAA==.',Ar='Arachne:BAAALAADCggICAAAAA==.Architeleaf:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.Argem:BAAALAADCgcIBwAAAA==.Arillin:BAAALAADCgUICQABLAADCggIDgABAAAAAA==.Aryya:BAABLAAECoEWAAICAAgItBZaBQBTAgACAAgItBZaBQBTAgAAAA==.',As='Ascaris:BAAALAAECgIIAwAAAA==.',At='Athelia:BAABLAAECoEUAAIDAAgIlCLhAQAjAwADAAgIlCLhAQAjAwAAAA==.',Av='Avanolatwo:BAAALAAECgEIAQABLAAECgYIDQABAAAAAA==.Avashammy:BAAALAAECgYIDQAAAA==.Aviendah:BAAALAAECgYICQAAAA==.Avon:BAAALAAECgEIAQAAAA==.',Az='Azdfghop:BAABLAAECoEVAAIEAAgIFiLaCADTAgAEAAgIFiLaCADTAgAAAA==.',Ba='Babezila:BAAALAAECgYICgAAAA==.Barbiegrill:BAAALAAECgEIAQAAAA==.Baykin:BAAALAAECgYIDAAAAA==.',Bb='Bbeastt:BAAALAADCgEIAQAAAA==.',Be='Berkowitz:BAAALAAECgEIAQAAAA==.Beyy:BAAALAADCggICQABLAAECgMIAwABAAAAAA==.',Bi='Bigbear:BAAALAADCgIIAgAAAA==.Biggy:BAAALAAECgEIAQAAAA==.Bimmer:BAAALAAECgIIAgAAAA==.',Bl='Blaaze:BAAALAAECgYICAAAAA==.Blackôut:BAAALAADCgcIBwAAAA==.Blaiddyd:BAAALAAECgUICQAAAA==.Bloodboi:BAAALAADCgcIBwAAAA==.Bloodångel:BAAALAAECggICAAAAA==.',Bo='Boreas:BAAALAAECgYIDQAAAA==.',Br='Brahms:BAAALAADCgcIBwAAAA==.Brain:BAACLAAFFIEGAAIFAAQI+BKgAABeAQAFAAQI+BKgAABeAQAsAAQKgRYAAgUACAh/IxELAM4CAAUACAh/IxELAM4CAAAA.Brainx:BAAALAAECgEIAQAAAA==.Branwarden:BAAALAADCggIFwAAAA==.',Bu='Bullchitz:BAAALAAECgYICAAAAA==.',['Bã']='Bãyy:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',['Bä']='Bäyy:BAAALAAECgMIAwAAAA==.',Ca='Caedes:BAAALAADCgcIBwAAAA==.Calador:BAAALAAECgYICQAAAA==.Carwasabi:BAAALAADCgcIBwAAAA==.',Ce='Celyne:BAAALAAECgUICAAAAA==.',Ch='Cheburashka:BAAALAADCggIEgABLAAECgMICAABAAAAAA==.Chenlow:BAAALAADCgYIBgAAAA==.',Ci='Civilian:BAAALAAECgYICgAAAA==.',Cl='Clevis:BAAALAADCggIDwAAAA==.',Co='Coconutcat:BAAALAAECgcIDwAAAA==.Coldbro:BAAALAADCggICQAAAA==.Coppernutcat:BAAALAADCgIIAgABLAAECgcIDwABAAAAAA==.Cordragu:BAAALAAECgYIDAAAAA==.Cordran:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Corinthin:BAAALAAECgMICAAAAA==.',Cr='Cristî:BAAALAADCgEIAQAAAA==.Crizmon:BAAALAAECgYICwAAAA==.Crowing:BAAALAAECgMIAwAAAA==.Crõwley:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.',Cy='Cyanas:BAAALAAECggIAQAAAA==.',Da='Darazarke:BAAALAAECgMIAwABLAAECgYICwABAAAAAA==.Darkami:BAAALAAECgcICQAAAA==.Darkndeadly:BAAALAAECgYIDgAAAA==.Darksaphira:BAAALAADCggIDwAAAA==.Darkstryder:BAAALAAECgYIDAAAAA==.Darps:BAAALAADCgEIAQAAAA==.',De='Deadaddie:BAAALAAECgYIDAAAAA==.Deamoneyes:BAAALAADCgQIBAAAAA==.Deamonlock:BAAALAADCgYIBgAAAA==.Deathshocker:BAAALAADCgcIBwAAAA==.Delin:BAAALAADCgcIDQABLAAECgYICwABAAAAAA==.Demaratus:BAAALAADCgEIAQAAAA==.Demonicwrath:BAAALAAECgYIBgAAAA==.Dendrel:BAAALAADCgYIBgAAAA==.Derpspally:BAAALAADCggICAAAAA==.Derpspunch:BAAALAADCggIEAAAAA==.',Di='Diane:BAEALAADCgcIDgAAAA==.Dieselcon:BAAALAAECgYIDAAAAA==.Dinotogs:BAAALAADCgIIAgAAAA==.',Do='Domdog:BAAALAAECgYIDgAAAA==.Dookiesmash:BAAALAAECgYICwAAAA==.',Dr='Draftymonk:BAAALAAECgUIBwAAAA==.Drakthar:BAACLAAFFIEFAAIGAAMI9hETAgD4AAAGAAMI9hETAgD4AAAsAAQKgRcAAgYACAigIy4EABQDAAYACAigIy4EABQDAAAA.Drax:BAAALAADCgcIBwAAAA==.Draxilara:BAABLAAECoEUAAMHAAgIXCBWAwCNAgAHAAcINCBWAwCNAgAIAAcIZh4UHAAaAgAAAA==.Dreadknuckle:BAAALAAECgcIEAAAAA==.',Dy='Dynamyte:BAAALAADCgcIBwAAAA==.',El='Elandrus:BAAALAAECgMIBQAAAA==.Elanora:BAAALAAECggIBwAAAA==.Elishiveth:BAAALAADCggIEAAAAA==.',Em='Emmara:BAAALAAECgEIAQAAAA==.',Er='Erata:BAAALAADCggICAAAAA==.Errl:BAAALAAECgYIBgABLAAECgYIDAABAAAAAA==.',Ez='Ezlok:BAAALAAECgMIAwAAAA==.',Fa='Faeth:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.Fairchild:BAAALAADCgQIBAAAAA==.Falcyon:BAAALAADCgcIDgAAAA==.Falerin:BAAALAAECgIIAgAAAA==.Farenheit:BAAALAAECgYIBwAAAA==.',Fe='Felzbrez:BAAALAADCgYIBgAAAA==.',Fi='Figala:BAAALAAECgMIAwAAAA==.Figlock:BAAALAAECgEIAQAAAA==.Firedealer:BAAALAAECgUIBwABLAAECgYIBgABAAAAAA==.',Fl='Flahash:BAAALAADCggIFAAAAA==.Flashmaster:BAAALAADCgQIAwAAAA==.Flyntflossy:BAAALAAECgUIBwAAAA==.Flöo:BAAALAAECgYIBwAAAA==.',Ge='Gerry:BAAALAAECgUIDAAAAA==.',Gg='Ggkando:BAAALAADCggIDwAAAA==.',Gi='Gingerail:BAAALAADCggIDAAAAA==.',Gl='Glory:BAAALAAECgMIBgAAAA==.Glyniang:BAAALAAECgYICwAAAA==.',Gr='Grainisack:BAAALAADCgUIBQAAAA==.Gravedygger:BAAALAAECgYICwAAAA==.Grenswood:BAAALAAECgYIBwAAAA==.Grimmkin:BAAALAAECgIIAwAAAA==.Grimmwall:BAAALAADCgUIBgAAAA==.',Gu='Gunnerr:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.',Ha='Hadiirus:BAAALAADCgMIAwAAAA==.Handivhe:BAAALAADCgUIBQAAAA==.Hannaquinn:BAAALAAECgQIBAAAAA==.Hasew:BAAALAAECgYICwAAAA==.',He='Heyner:BAAALAAECgYIBgAAAA==.',Hi='Hinral:BAAALAAECgUICQAAAA==.Hippodrome:BAAALAADCgcIBwAAAA==.',Ho='Hollamonk:BAAALAADCggICAAAAA==.Holysmacker:BAAALAAECgYIDQAAAA==.',Ic='Iceyrage:BAAALAADCggIFgAAAA==.Icomeinpeace:BAAALAAECgMIBQAAAA==.',Il='Illaynne:BAAALAAECgYIDgAAAA==.',Im='Immensepain:BAAALAAECgYICQAAAA==.',In='Inoshikacho:BAAALAAECgYIBwAAAA==.Invý:BAAALAAECgYICwAAAA==.',Ir='Irishtotems:BAAALAAECgcIDAAAAA==.',It='Itharillys:BAAALAAECgMIBgAAAA==.',Ja='Jaesin:BAAALAADCggIFgAAAA==.',Je='Jeennkiins:BAAALAADCgcIDAAAAA==.Jessibella:BAAALAADCggIEwAAAA==.',Ji='Jigari:BAAALAAECgYIDgAAAA==.Jintetra:BAAALAADCggICQAAAA==.Jinx:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.',Jo='Jozan:BAAALAADCgcIDgAAAA==.',['Jö']='Jöhnblaze:BAAALAAECgYIDgAAAA==.',Ka='Kahoona:BAAALAADCggIDwAAAA==.Kaishias:BAAALAAECgEIAQAAAA==.Kando:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.Kanimeh:BAAALAADCgcICQAAAA==.Kankuró:BAAALAAECgcIDwAAAA==.Kasdeya:BAAALAAECggIBwAAAA==.',Ke='Kelerono:BAAALAAECgYICAAAAA==.',Ki='Kidokato:BAAALAAECgEIAQAAAA==.Kiiako:BAAALAADCgMIAwAAAA==.Killudead:BAAALAAECgUICQAAAA==.',Ko='Korimya:BAAALAADCgcIBwAAAA==.',Kr='Krankalank:BAAALAADCggIDgAAAA==.Kristie:BAAALAAECgMIAwAAAA==.',Ky='Kyle:BAAALAAECggIDgAAAA==.',La='Lairia:BAAALAADCgcIBwABLAAFFAMIBQAGAPYRAA==.Laserchicken:BAAALAADCgIIAgAAAA==.Lawdogg:BAAALAADCggIFAAAAA==.',Le='Lekal:BAAALAAECgQIBAABLAAECgYICwABAAAAAA==.Leonora:BAAALAAECgIIAgAAAA==.Letdownbyrh:BAAALAADCggIGQAAAA==.Lezene:BAAALAADCggIGAAAAA==.',Li='Liaysa:BAAALAAECgYICQAAAA==.Liquorfront:BAAALAAECgQIBAABLAAECgUICQABAAAAAA==.Lisondrel:BAAALAADCgYIBgAAAA==.Lissari:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Lizie:BAAALAADCggICAAAAA==.',Lo='Lorette:BAAALAAECgYICwAAAA==.',Lu='Luckynyx:BAAALAADCggIDQAAAA==.Lussasshol:BAAALAADCggICAAAAA==.',Ly='Lyseroth:BAAALAAECgcIDgAAAA==.',['Lü']='Lüñä:BAAALAADCgQIBAAAAA==.',Ma='Machotedan:BAAALAAECgYIDAAAAA==.Macmittens:BAAALAAECgQIBAAAAA==.Madox:BAAALAADCgQIBAAAAA==.Makc:BAAALAADCgUIBQAAAA==.Mamadrag:BAAALAAECgEIAQAAAA==.Manalia:BAAALAADCgYIBgAAAA==.Mario:BAAALAAECgYIDAABLAAECgYIDQABAAAAAA==.Mastashifu:BAAALAADCggIFgAAAA==.Matryoshka:BAAALAADCgYICwAAAA==.Mayihmpurleg:BAAALAAECgYIBgAAAA==.',Me='Meilin:BAAALAADCgcIBwAAAA==.Mellachion:BAAALAADCgcIDgABLAAECgYIDQABAAAAAA==.Menagetotem:BAAALAADCggICAAAAA==.Merle:BAAALAAECgYIDAAAAA==.Meta:BAAALAAECgYIBgAAAA==.Metaphysis:BAAALAADCggICAAAAA==.',Mi='Mineba:BAAALAADCgUIBQAAAA==.Missteak:BAAALAAECgMIBAAAAA==.Missî:BAAALAAECgMIBQAAAA==.Mistlykapa:BAABLAAECoEUAAIJAAgIDiA7CADKAgAJAAgIDiA7CADKAgAAAA==.Miththrawndo:BAAALAAECgQIBQAAAA==.',Ml='Ml:BAAALAAECgMIAwAAAA==.',Mo='Momjeans:BAAALAAECggIBAAAAA==.Morterra:BAAALAAECgIIAwAAAA==.',My='Myfriendtold:BAAALAADCgcIBwAAAA==.Myrkur:BAAALAADCggIDAABLAAECgEIAQABAAAAAA==.Mythion:BAAALAAECgEIAQAAAA==.',['Mä']='Mäylä:BAAALAAECgUICQAAAA==.',['Mí']='Míst:BAAALAAECgYIEwAAAA==.',Ne='Necropheeler:BAAALAADCggIDwABLAAECgUICQABAAAAAA==.Nephie:BAAALAAECgYIDgAAAA==.Netazia:BAAALAADCggIDwAAAA==.Nezqk:BAAALAAECgcIDgAAAA==.',Ni='Nightflier:BAAALAADCgYIBgAAAA==.',Nm='Nmnenthe:BAAALAAECgIIAgAAAA==.',No='Noelytv:BAAALAADCgcIDgAAAA==.Nohru:BAAALAAECgEIAQAAAA==.Notrealword:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.Novaman:BAAALAADCgcIBwAAAA==.Noxren:BAAALAAECgMIAwAAAA==.',Ny='Nyquill:BAAALAAECgIIAgAAAA==.Nyxara:BAAALAADCgQIBAAAAA==.',Ob='Obadiah:BAAALAADCggIDAAAAA==.Obin:BAAALAAECgMIBAAAAA==.',Ok='Okukoy:BAAALAADCggIFwAAAA==.',Ow='Owendriel:BAAALAAECgUIBwAAAA==.',Pa='Palivok:BAAALAADCgcIBwAAAA==.Pandress:BAAALAADCggICAAAAA==.',Pe='Peetza:BAAALAADCggIEAABLAAECgYIDAABAAAAAA==.Perturabo:BAAALAADCgUIBQAAAA==.Peryite:BAAALAAECgYIDAAAAA==.Pewtrid:BAAALAAECgMIBwAAAA==.',Pi='Pisscat:BAAALAADCggIDwAAAA==.Pitipanda:BAAALAAECgMIBAAAAA==.',Po='Poisonedfang:BAAALAAECgMIBAAAAA==.Poisongooch:BAAALAADCgYIBgAAAA==.Poofbegone:BAAALAADCggIDQAAAA==.',Pp='Ppg:BAAALAADCggICAAAAA==.',Pr='Prometheusx:BAAALAAECgMIAwAAAA==.Protròast:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.',Ps='Psypriest:BAAALAAECgYIAwABLAAFFAEIAQABAAAAAA==.',Qu='Quarionn:BAAALAAECgYIBwAAAA==.',Ra='Rabbi:BAAALAADCggIFgAAAA==.Radaster:BAAALAADCggIFwAAAA==.Rayyvn:BAAALAADCggICAAAAA==.',Re='Reesespbc:BAAALAAECgUICgAAAA==.Reina:BAAALAAECgQIBAAAAA==.Reinir:BAAALAAECgYICwAAAA==.Rektagar:BAAALAAECgYICwABLAAFFAMIBQAGAPYRAA==.Renarin:BAAALAADCggIEAABLAAECgYIDAABAAAAAA==.Rethrius:BAAALAAECgcIDgAAAA==.Retnuh:BAAALAADCgcIBwAAAA==.Revshot:BAAALAADCggICAAAAA==.Reàper:BAAALAADCgMIAQAAAA==.',Rh='Rhoun:BAAALAAECgYICQAAAA==.',Ro='Rogrokim:BAAALAADCgcICQAAAA==.Rohalya:BAAALAADCgcIBwAAAA==.Roshara:BAAALAADCggICwAAAA==.',Ru='Rut:BAAALAAECgYIBgABLAAECgYIDAABAAAAAA==.',Ry='Rysi:BAAALAAECgMIBwAAAA==.',['Rö']='Rös:BAAALAAECgcIDgAAAA==.',['Rü']='Rübblë:BAAALAADCgYIBgAAAA==.Rüthless:BAAALAAECgYICwAAAA==.',Sa='Saberie:BAAALAADCgcIEQAAAA==.Saely:BAAALAAECgYIDgAAAA==.Salen:BAAALAAECgYIDAAAAA==.Salina:BAEALAAECgQIBQAAAA==.Sallandron:BAAALAADCgYIBgAAAA==.Sandstique:BAAALAAECgYICgAAAA==.Sanjira:BAAALAAECgYICAAAAA==.Sarlak:BAAALAADCgcIBwAAAA==.Sarusuby:BAAALAAECgYIDgAAAA==.',Sc='Schlappy:BAAALAADCggIEAABLAAECgYICwABAAAAAA==.Schwoft:BAAALAADCgcIBwAAAA==.Scottydh:BAAALAADCgcIDgABLAAECgYIDgABAAAAAQ==.Scottytank:BAAALAAECgYIDgAAAQ==.',Se='Seeta:BAAALAADCgcIBwAAAA==.Selesha:BAAALAADCgEIAQAAAA==.',Sh='Shadadie:BAAALAADCggICwAAAA==.Shoobis:BAAALAADCgEIAQAAAA==.Shroomgirl:BAAALAAECgcIDgAAAA==.',Si='Simyurgh:BAAALAAECgEIAQAAAA==.',Sl='Slipperyboi:BAABLAAECoEXAAIKAAgI0htECACoAgAKAAgI0htECACoAgAAAA==.',Sm='Smellsofpee:BAAALAADCgcIBwAAAA==.Smokintotems:BAAALAAECgEIAQAAAA==.',Sn='Sneakgasm:BAAALAADCgcIBwAAAA==.Snickerdoodl:BAAALAADCggIDwAAAA==.',So='Soldraca:BAAALAADCggIFgAAAA==.Solicitation:BAAALAAECgcIDgAAAA==.',Sp='Spookz:BAAALAAECggIEgAAAA==.Spriggs:BAAALAAECgQIBwAAAA==.',St='Stutters:BAAALAAECgYIDAAAAA==.',Su='Subayyru:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Sunnyräy:BAAALAADCggIFwAAAA==.Suntzusie:BAAALAAECgIIAwAAAA==.',Sv='Svatos:BAAALAADCgUIBQAAAA==.',Sw='Swineflu:BAAALAAECgIIAgAAAA==.',Sy='Symurgh:BAAALAAECgMIAwAAAA==.Syrabane:BAAALAADCggICAAAAA==.',['Sý']='Sýndrá:BAAALAADCgMIAwAAAA==.',Ta='Tacobob:BAAALAAECgcIDgAAAA==.Taffyboy:BAAALAADCggICAAAAA==.Talysiah:BAAALAADCggIFgAAAA==.Talzind:BAAALAADCgUICAAAAA==.Tarik:BAAALAADCgQIAQAAAA==.Tarogen:BAAALAADCggICAABLAAECgUICQABAAAAAA==.Taurìel:BAAALAADCgcIBwAAAA==.Tavok:BAAALAAECgUICQAAAA==.',Te='Tenacious:BAAALAADCggIEAAAAA==.',Th='Thalmyra:BAAALAADCgcIDgABLAAECgMIAwABAAAAAA==.Themyscira:BAAALAAECgcIDgAAAA==.Thenna:BAAALAAECgIIAgAAAA==.Thiux:BAAALAAECgEIAQAAAA==.Thrappy:BAAALAAECgYICwAAAA==.',Ti='Tiddyhammer:BAAALAAECgMIAwAAAA==.Tintaglia:BAAALAAECgIIAgABLAAECgYIDQABAAAAAA==.Tirtun:BAAALAAECgYIDgAAAA==.',Tr='Traumatize:BAAALAAECgQIBwAAAA==.Trickss:BAAALAAECgQIBwAAAA==.Triggeer:BAAALAAECgYICgAAAA==.Trolldemort:BAAALAAECgMIAwAAAA==.Tríxy:BAAALAADCggIDQAAAA==.',Ts='Tsarran:BAAALAAECgYICgAAAA==.',Tu='Tully:BAAALAAECgMIAwAAAA==.',Tw='Twelvekill:BAAALAAECgcIDgAAAA==.',Ty='Tyliaa:BAAALAAECgYIEQAAAA==.',Ub='Ubisami:BAAALAAECgMIAwAAAA==.',Ur='Urgoochness:BAAALAAECgQICAAAAA==.',Va='Valanora:BAAALAAECgQIBAAAAA==.Vapturov:BAAALAADCggIFwAAAA==.',Ve='Veeks:BAAALAAECgMIAwAAAA==.Velikirn:BAAALAAECgUICAAAAA==.Velras:BAAALAADCgEIAQAAAA==.Venefica:BAAALAADCgcIBwAAAA==.Verieleta:BAAALAADCggIEgAAAA==.Vesspin:BAAALAADCggIFwAAAA==.',Vi='Vixxon:BAAALAAECgUICQAAAA==.',Vu='Vukodlak:BAAALAADCgYIBgABLAAECgYIDQABAAAAAA==.Vulpixie:BAAALAADCgcICAAAAA==.',Wa='Wanheda:BAAALAAECgMIBQABLAAECgUIDAABAAAAAA==.Waterbender:BAAALAAECgEIAQAAAA==.',We='Wedlock:BAAALAADCggIDwAAAA==.Weep:BAAALAADCggICAAAAA==.Werkjathal:BAABLAAECoEWAAILAAgIsCW2AACAAwALAAgIsCW2AACAAwAAAA==.',Wi='Willowbark:BAAALAADCggICAAAAA==.',Wo='Wolfblitzer:BAAALAAECgQIBAAAAA==.Wolfmanbro:BAAALAADCgYIBgAAAA==.Worldbane:BAAALAAECgEIAQAAAA==.',Xa='Xalatath:BAAALAAECgYIDAAAAA==.Xanin:BAAALAADCgcICwAAAA==.Xanthos:BAAALAAECgEIAQAAAA==.',Xe='Xeraphim:BAAALAADCggICAAAAA==.',Xi='Xianyu:BAAALAADCggIDwAAAA==.Ximmer:BAAALAAECgcIDgAAAA==.',Xo='Xoxaan:BAAALAAECggICAAAAA==.',Yu='Yuck:BAAALAAECgYIBgABLAAECggIFgALALAlAA==.Yueyin:BAAALAADCgcIBwAAAA==.',Za='Zan:BAAALAAECgcIDgAAAA==.',Zu='Zultrix:BAAALAADCggIDwAAAA==.',Zy='Zylaeri:BAAALAAECgYICAAAAA==.',['Ël']='Ëllër:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end