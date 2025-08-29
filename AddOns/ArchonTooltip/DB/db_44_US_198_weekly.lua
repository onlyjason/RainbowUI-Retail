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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','Mage-Frost','Mage-Arcane','DeathKnight-Frost','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Druid-Restoration','Paladin-Retribution','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc',}; local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaratrath:BAAALAADCgMIAwAAAA==.Aaylia:BAAALAAECgMIAwAAAA==.',Ab='Abzdh:BAAALAADCgYIBwABLAAECgYIDQABAAAAAA==.Abzdk:BAAALAADCgYIDQABLAAECgYIDQABAAAAAA==.Abzlock:BAAALAAECgYIBgABLAAECgYIDQABAAAAAA==.Abzmage:BAAALAAECgYIDQAAAA==.Abzsh:BAAALAADCgUIBQAAAA==.',Ad='Adramelk:BAAALAAECgYIDAAAAA==.',Ae='Aeiay:BAAALAADCggIFwAAAA==.',Af='Aftershok:BAAALAADCgYIBgAAAA==.',Ag='Again:BAAALAADCgcIBwAAAA==.',Ai='Aibhe:BAAALAAECgYIBgABLAAECgYIDQABAAAAAA==.',Ak='Akäne:BAAALAAECgIIAgAAAA==.',Al='Alexandrap:BAAALAADCggIFgAAAA==.Allmighto:BAEALAAFFAIIAgAAAA==.Althasha:BAAALAADCggICAAAAA==.Alyssaxoo:BAAALAADCgcIDAAAAA==.',An='Androstraz:BAABLAAECoEXAAICAAgIxCLOAwANAwACAAgIxCLOAwANAwAAAA==.Anjkh:BAAALAADCgMIAwAAAA==.Anniesthesia:BAAALAAECgMIAwAAAA==.Annolyn:BAAALAADCggICQABLAAECgQICAABAAAAAA==.Anorexorcist:BAAALAAECgYICgAAAA==.Ansky:BAAALAADCggIEAAAAA==.',Ap='Apara:BAAALAADCgQIBAABLAAECgYIDQABAAAAAA==.',Ar='Arozoth:BAAALAADCgIIAgAAAA==.Arun:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Arune:BAAALAAECgEIAQAAAA==.',As='Aspyrx:BAAALAAECgUICAAAAA==.Assol:BAAALAADCgUIBQAAAA==.Astelan:BAAALAAECgYIDAAAAA==.',Ay='Ayeola:BAAALAADCgYIBgAAAA==.',Az='Azril:BAAALAADCggICAAAAA==.Azshera:BAAALAAECgMIAwAAAA==.',Ba='Babywipes:BAAALAAECgUICAAAAA==.Bachaterah:BAAALAAECgEIAQAAAA==.Baeldaeg:BAAALAADCggICAABLAAECgYICgABAAAAAA==.Bannett:BAABLAAECoEXAAMDAAgI6SEvBAC/AgADAAgI1BsvBAC/AgAEAAgIbx0kFwBYAgAAAA==.Baoboi:BAAALAADCgcIDQAAAA==.Bastét:BAAALAAECgIIBAAAAA==.Baxterfdk:BAAALAAECgcICgAAAA==.Baylifê:BAAALAAECgcIDQAAAA==.',Be='Beefyweefy:BAAALAADCggIEAABLAAECgEIAQABAAAAAA==.Belmønt:BAAALAAECgQIBAAAAA==.Benaddiction:BAAALAADCgcICQAAAA==.Beryn:BAAALAAECgQIBgAAAA==.',Bi='Bienfrosty:BAAALAADCggIDwAAAA==.Bigpumpa:BAAALAADCggICAAAAA==.Billmurray:BAAALAADCggICAAAAA==.Billygoatgrf:BAAALAAECgMIAwAAAA==.',Bl='Blakbeard:BAAALAADCgYICgAAAA==.Bleached:BAAALAAECgYICQAAAA==.Blightmommie:BAAALAAECgYIBgAAAA==.Bloodshadow:BAAALAADCgcIBwAAAA==.Blôô:BAAALAAECgMIAwAAAA==.',Bo='Boreddruid:BAAALAAECgMIAwAAAA==.',Br='Brainlesswar:BAAALAAECgYICQAAAA==.Breach:BAAALAAECggIEAAAAA==.Breemonic:BAAALAAECgYIDQAAAA==.Breeutiful:BAAALAADCgcIBwABLAAECgYIDQABAAAAAA==.Bruce:BAAALAAECgcIDwAAAA==.Brëna:BAAALAAECgYICQAAAA==.',Bu='Bullshifter:BAAALAAECgEIAQAAAA==.',['Bø']='Bøneçrusher:BAAALAADCgcIDAAAAA==.',Ca='Camelhumps:BAABLAAECoEVAAIFAAgIdCONBAAqAwAFAAgIdCONBAAqAwAAAA==.Caraxes:BAAALAAECgYIEgAAAA==.',Ch='Chaosvader:BAAALAADCgMIBwAAAA==.Chartruce:BAAALAADCgEIAQAAAA==.Cheesus:BAAALAAECgEIAQAAAA==.Cheyenne:BAAALAAECgMIAwAAAA==.Chodda:BAAALAADCggICgAAAA==.Christophe:BAAALAADCgMIAgAAAA==.Chronriddle:BAAALAADCgYIDAAAAA==.Chumle:BAAALAADCggIBwAAAA==.Chuna:BAAALAADCgMIAwAAAA==.',Ci='Cinnamen:BAAALAAECgMIAwAAAA==.',Co='Coaa:BAAALAAECgUICAAAAA==.Coldcrit:BAAALAADCggIFQAAAA==.Colossus:BAAALAAECgYICgAAAA==.Corkcrush:BAAALAADCgMIAwABLAADCggIFQABAAAAAA==.',Cz='Czpz:BAAALAAECgIIAgAAAA==.',Da='Daddysiren:BAAALAADCgIIAwAAAA==.Dargons:BAAALAADCggICAAAAA==.Darkmeadow:BAAALAAECgIIAgAAAA==.Dastard:BAAALAAECgcIDwAAAA==.',Dc='Dcmp:BAABLAAECoEXAAIGAAgIlx9RCQDSAgAGAAgIlx9RCQDSAgAAAA==.',De='Deadlymagic:BAAALAADCgcIBwAAAA==.Deathlyfrost:BAAALAAECgMIBAAAAA==.Deathwarz:BAAALAADCgMIAwAAAA==.Deathwolfy:BAAALAADCgcIBwAAAA==.Deftonia:BAAALAAECgMIBgAAAA==.Degenerate:BAAALAAECgUIDAAAAA==.Dementïa:BAAALAAECgYICQAAAA==.Destrotim:BAAALAAECgYIDQAAAA==.Dethspall:BAAALAAECgYICQAAAA==.Devotion:BAAALAADCgcIBwABLAAFFAIIAgABAAAAAA==.Devotional:BAAALAAFFAIIAgAAAA==.Dezz:BAAALAAECgYIDAAAAA==.',Dh='Dhaos:BAAALAADCgcIBwAAAA==.',Di='Dinkellberg:BAAALAADCggIDQAAAA==.Ditbirtbirt:BAAALAAECgMIAwABLAAECgYICgABAAAAAA==.Divinacurita:BAAALAAECgEIAQAAAA==.',Dj='Djx:BAAALAAECgYIDAAAAA==.',Dm='Dmatch:BAAALAAECgIIAgAAAA==.',Do='Dodel:BAAALAAECgIIBAAAAA==.Dommiemommie:BAAALAAECgMIBQABLAAECgYIBgABAAAAAA==.Doozee:BAAALAAECgYIDAAAAA==.Dorinmigrane:BAAALAAECgMIBAAAAA==.Dotfearwin:BAAALAADCgcICwAAAA==.Downset:BAAALAADCgYIBgAAAA==.',Dr='Drac:BAAALAAECgMIAwAAAA==.Drakthorr:BAAALAAECgYIBwAAAA==.Draynen:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Druidsteve:BAAALAAECgYIBgAAAA==.',Dw='Dwarfshmussy:BAAALAAECgcIDgAAAA==.',['Dé']='Déäth:BAAALAADCgMIAwAAAA==.',El='Elitistjerk:BAAALAADCgQIBQAAAA==.Ellisis:BAAALAAECgQIBgAAAA==.Elvarg:BAAALAAECgMIBAAAAA==.',En='Endezar:BAAALAAECgMIAwAAAA==.',Er='Eraquxx:BAAALAADCggICAAAAA==.',Eu='Eugima:BAAALAADCgYIBwAAAA==.',Ev='Evocurr:BAAALAAECgYICgAAAA==.',Ex='Exekuteur:BAAALAADCgYIBgAAAA==.Exxitus:BAAALAAECgYIDQAAAA==.',Fa='Falsoqt:BAAALAADCgcIBwAAAA==.',Fb='Fblthp:BAAALAAECgYICQAAAA==.',Fe='Felachio:BAAALAAECgUICAAAAA==.',Fi='Fidelitaslex:BAAALAADCgcIBwAAAA==.Firerage:BAAALAAECgEIAQAAAA==.Fischbubbles:BAAALAADCgcIBwAAAA==.Fischcakes:BAAALAAECggIBAAAAA==.Fischlips:BAAALAADCgcIBwAAAA==.',Fj='Fjörgyn:BAACLAAFFIEFAAIHAAMIjB0IAgAgAQAHAAMIjB0IAgAgAQAsAAQKgRgAAgcACAgEJjIBAG8DAAcACAgEJjIBAG8DAAAA.',Fl='Flaxamax:BAAALAADCgYIBgAAAA==.Fluf:BAAALAADCgUIBQAAAA==.',Fo='Forsetí:BAAALAAECgcIDwAAAA==.Fotosynthsis:BAAALAAECgMIBAAAAA==.Foxxer:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.',Fr='Franksuncle:BAAALAAECgcIAQAAAA==.Frets:BAAALAADCggIDAAAAA==.',Fs='Fsod:BAAALAAECgEIAQAAAA==.',['Fì']='Fìsto:BAAALAADCgYIBgAAAA==.',Ga='Gambitex:BAAALAADCgQIBAAAAA==.Gargaroth:BAAALAADCggIDgAAAA==.',Ge='Gekk:BAAALAAECgUICAAAAA==.Geodaddy:BAAALAADCgUIBgAAAA==.',Gi='Gigimagi:BAAALAAECgMIBAAAAA==.Gimmeh:BAAALAAECgIIAgAAAA==.',Gl='Glorified:BAAALAAECgMIAwAAAA==.Glucose:BAAALAAECgMIAwAAAA==.',Go='Goldenbelly:BAAALAAECgEIAQABLAAECgYIDAABAAAAAA==.Goonerman:BAAALAAECgUIBwAAAA==.Goopyscoopy:BAAALAAECgcIEAAAAA==.Goosetrainer:BAAALAADCgYIBgAAAA==.Gorecutz:BAAALAADCggIDQAAAA==.Gorlack:BAAALAADCgMIAwAAAA==.Goub:BAABLAAECoEUAAIIAAcIwR5sCgBuAgAIAAcIwR5sCgBuAgAAAA==.',Gr='Grapefroot:BAAALAADCgUIBQAAAA==.Graveyards:BAAALAAECgUICAAAAA==.Grimost:BAAALAAECgYICgAAAA==.Groscolice:BAAALAADCgIIAgAAAA==.',Gu='Gullibull:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.',Gw='Gwyne:BAAALAAECgcIEAAAAA==.',Ha='Halfstack:BAAALAAECgYICAAAAA==.Halucid:BAAALAADCggIDQAAAA==.Harddon:BAAALAAECgQIBAAAAA==.Hashed:BAAALAAECgIIAgAAAA==.Hays:BAAALAADCggIDwAAAA==.Hayspriest:BAAALAAFFAIIAgAAAA==.',Ho='Hogra:BAAALAAECgIIAgAAAA==.Holyjebuss:BAAALAADCgEIAQAAAA==.Hoodler:BAEBLAAFFIEFAAIJAAMINhbNAQAFAQAJAAMINhbNAQAFAQAAAA==.Hoodlere:BAEALAADCggIDwABLAAFFAMIBQAJADYWAA==.Hoodlery:BAEALAAECgcIDQABLAAFFAMIBQAJADYWAA==.Hoofjobs:BAABLAAECoEWAAIKAAgIDiLWCQDgAgAKAAgIDiLWCQDgAgAAAA==.Hornball:BAAALAADCgYICgAAAA==.',Hy='Hypothermik:BAAALAAECgMIBwAAAA==.Hyur:BAAALAADCggIDgAAAA==.',['Hö']='Hörnstar:BAAALAADCgcIDQAAAA==.',Ib='Iblastpants:BAAALAAECgIIAgAAAA==.',Ic='Icepick:BAAALAADCgcICAAAAA==.',Ig='Iggyy:BAAALAAECgIIAgAAAA==.',Im='Imsuperlost:BAAALAADCggICAAAAA==.',In='Inflammo:BAAALAADCggICQAAAA==.Insaneisbad:BAAALAADCgEIAQAAAA==.',Io='Iose:BAAALAAECgYIEQAAAA==.',Ir='Irshingwary:BAAALAADCgQIBAAAAA==.',Iz='Izatay:BAAALAADCgcICAABLAADCggIFgABAAAAAA==.Izumî:BAAALAADCggIDwAAAA==.',Ja='Jakè:BAAALAADCgEIAQAAAA==.',Jo='Jomgpallie:BAAALAAECgEIAQAAAA==.Jonac:BAAALAAECgMIBAAAAA==.Jorecht:BAAALAADCgEIAQAAAA==.Josefbugman:BAAALAAECgMIBAAAAA==.',Ju='Juktal:BAAALAAECgQIBgAAAA==.',Ka='Kabrona:BAAALAADCgYIBgAAAA==.Kadah:BAAALAAECggIDQAAAA==.Kagarn:BAAALAADCgUIBQAAAA==.Kagos:BAAALAAECgMIAwAAAA==.Kancho:BAAALAADCgUIBQAAAA==.Karesh:BAABLAAECoEXAAIHAAgITiXuAgBEAwAHAAgITiXuAgBEAwAAAA==.Katreneth:BAAALAADCgUICwAAAA==.Katyhairy:BAAALAADCgcIDAAAAA==.Kazaju:BAAALAAECggIEQAAAA==.Kazgarf:BAAALAAECgMIAwAAAA==.Kazuje:BAABLAAECoEVAAMLAAgI6CRSAwC7AgALAAcIpSRSAwC7AgAFAAYIQhlnMwCYAQAAAA==.',Ke='Keelnl:BAAALAAECgMIAwAAAA==.Kelais:BAAALAAECgMIBAABLAAECgYIBwABAAAAAA==.Kelzey:BAAALAAECgIIAgAAAA==.Kev:BAAALAADCgcIBwAAAA==.',Kh='Kheezis:BAAALAAFFAIIAwAAAA==.Khuz:BAAALAAECgIIAgAAAA==.',Ki='Kinzington:BAAALAAECgYICwAAAA==.Kirbo:BAAALAAECgEIAQAAAA==.Kitagawa:BAAALAADCgIIAgAAAA==.',Kl='Klacksmonk:BAABLAAECoEXAAMMAAgIOSIXAwD8AgAMAAgILSIXAwD8AgANAAgIeBaeCgCvAQAAAA==.Klaud:BAAALAADCggICgAAAA==.',Ko='Kouwcookies:BAAALAAECgMIAwAAAA==.',Kr='Kriixadin:BAAALAAECgMIBQAAAA==.',Ku='Kungfukenny:BAAALAAECgEIAQAAAA==.Kuothe:BAAALAAECgYIBgAAAA==.',Kw='Kwazzi:BAAALAAECgYIDAAAAA==.',La='Lad:BAAALAAECgcIDwAAAA==.Lafeedso:BAAALAADCgYIBgAAAA==.Lasituation:BAAALAADCgUIBQAAAA==.Lazsi:BAAALAAECgIIAgAAAA==.',Lc='Lcc:BAAALAAECggIBAAAAA==.',Le='Legoland:BAAALAADCgYIBgAAAA==.Lenalover:BAAALAADCggIDwAAAA==.Lenaría:BAAALAADCgMIAwABLAAECgYIBwABAAAAAA==.Lesnichii:BAAALAAECgYIDQAAAA==.Lewakex:BAAALAAECggIAgAAAA==.Leyendaz:BAAALAAECgEIAQAAAA==.',Li='Lifegrip:BAAALAAECgMIAwAAAA==.Lightbrngr:BAAALAAECgYIDQAAAA==.Lihuai:BAAALAAECgYICAAAAA==.Limitlessone:BAAALAAECgEIAQAAAA==.Lindhardt:BAAALAADCggICAAAAA==.Lissandine:BAAALAAECgYIDQAAAA==.',Ly='Lystra:BAAALAADCggICAAAAA==.',['Lî']='Lîlîth:BAAALAADCggIDwAAAA==.',Ma='Magetim:BAAALAADCggICAAAAA==.Magnusa:BAAALAADCgcIBwAAAA==.Magnuss:BAAALAAECgYICQAAAA==.Manafreak:BAAALAADCggICgABLAAECgcIDwABAAAAAA==.Manion:BAAALAAECgYICQAAAA==.Manipulation:BAAALAADCgYICAAAAA==.Mannarchy:BAAALAADCgUIBQAAAA==.Margot:BAAALAADCggIEgABLAADCggIFgABAAAAAA==.Mashene:BAAALAADCgUIBQABLAAECgQICAABAAAAAA==.Masochista:BAABLAAECoEXAAIOAAgISiXfAABYAwAOAAgISiXfAABYAwAAAA==.Mastric:BAEALAAECgYICQAAAA==.Matark:BAAALAAECgIIAgAAAA==.Matarkbro:BAAALAAECgEIAQAAAA==.',Mc='Mccaffrey:BAAALAAECgUICAAAAA==.',Me='Meetch:BAAALAAFFAIIAgAAAA==.Megdar:BAAALAADCgcIDgAAAA==.Meldbot:BAAALAAECgYIBgAAAA==.Melitha:BAAALAADCgYIBgAAAA==.',Ml='Mlee:BAAALAADCgQIBAAAAA==.',Mo='Mojobtw:BAAALAAECgYIDgAAAA==.Monkgiler:BAAALAADCgYIBwAAAA==.Moontouched:BAAALAADCggIDwAAAA==.Mortamur:BAAALAAECgcIDQAAAA==.Mortelinnos:BAAALAAECgYICQAAAA==.',Mu='Murney:BAAALAAECgIIAgAAAA==.',My='Mysticguru:BAAALAAECgcIEAAAAA==.Mythyethunis:BAAALAADCgYICAAAAA==.',['Mì']='Mìkehawk:BAAALAAECgYIEwAAAA==.',Na='Naisu:BAAALAADCgYIDgAAAA==.Nasti:BAAALAADCggIEAAAAA==.Naughtybot:BAAALAADCgcICgAAAA==.Naughtyrawr:BAAALAADCggIFQAAAA==.',Ne='Nebula:BAAALAADCgIIAgAAAA==.Neco:BAAALAAECgYICQAAAA==.Necropete:BAAALAAECgYIBwAAAA==.Nerdbolt:BAAALAADCgYIBgAAAA==.',Ni='Nigelpolice:BAAALAAECgYIDAAAAA==.Nika:BAAALAADCggICAABLAAECggIFwAOAEolAA==.Nilla:BAAALAADCgIIAgAAAA==.Nimit:BAAALAAECgIIBAAAAA==.Nirdarosa:BAAALAAECgEIAQAAAA==.Niyka:BAAALAAECgYIBgABLAAECggIFwAOAEolAA==.',No='Nooblez:BAAALAADCggIDwAAAA==.Notsenka:BAAALAAECgMIAwAAAA==.Novic:BAAALAAECgcIDwAAAA==.',Nu='Nualia:BAAALAAECgIIAgAAAA==.',Ny='Nydiesel:BAAALAADCgIIAgAAAA==.',Ob='Oberron:BAAALAADCgEIAQAAAA==.',Of='Offthechain:BAAALAAECgYICQAAAA==.',Or='Orixa:BAAALAADCgMIAwAAAA==.Orobus:BAAALAAECgUICgAAAA==.',Os='Oscassey:BAAALAAECgUIBgAAAA==.Osconspark:BAAALAADCgMIAwAAAA==.Oscontree:BAAALAADCgcICAAAAA==.',Ox='Oxbóxen:BAAALAAECgUIBwAAAA==.Oxley:BAAALAAECgUICAAAAA==.',Pa='Paladingus:BAAALAAECgQIBgAAAA==.Palapk:BAAALAAECgMIBAAAAA==.Pandalee:BAAALAAECgcIEAAAAA==.Pandidin:BAAALAAECgMIBAAAAA==.',Pe='Peenar:BAAALAAECgMIAwAAAA==.Pew:BAAALAAECgcIDQAAAA==.',Pi='Pizpad:BAAALAADCgMIAwAAAA==.',Pk='Pk:BAAALAAECgcIEAAAAA==.Pkbeastmode:BAAALAAECgcICwAAAA==.',Pl='Plloxx:BAAALAADCggIEAAAAA==.Ploxx:BAAALAADCggICAAAAA==.',Po='Polaroid:BAAALAAECgMIBQAAAA==.Poojy:BAAALAAECgMIAwAAAA==.',Pr='Priesttess:BAAALAADCgMIAwAAAA==.Prohealin:BAAALAAECgYIBwAAAA==.Pruz:BAAALAAECgIIAgAAAA==.',Ps='Psyonia:BAAALAAECgIIAgAAAA==.',Pt='Ptiteagacee:BAAALAAECgMIAwAAAA==.',Pu='Pudundu:BAAALAAECgcIDgAAAA==.Puffymuffinz:BAAALAADCgcIBwABLAAECggIDQABAAAAAA==.Puffymüffins:BAAALAADCgcIDgABLAAECggIDQABAAAAAA==.Pupruin:BAAALAAECgEIAQAAAA==.Pupsub:BAAALAADCgYIBAAAAA==.Purin:BAAALAAECgYIDAAAAA==.',['Pì']='Pìkachu:BAAALAAECgYICQAAAA==.',Ra='Rahgequake:BAACLAAFFIEFAAMHAAMI0ht5AgATAQAHAAMI0ht5AgATAQAIAAEIYw3tDABEAAAsAAQKgRcAAwcACAh/IxsDAEEDAAcACAh/IxsDAEEDAAgAAQifEU52ADgAAAAA.Ran:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.Rasmus:BAAALAAECgYICQAAAA==.Rayquaza:BAAALAAECgYICQAAAA==.Razmatazz:BAAALAAECgQIBwAAAA==.',Re='Reva:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.',Rh='Rhoma:BAEALAAECgUICAAAAA==.',Ri='Ribone:BAAALAADCgYIBgABLAAECgQIBgABAAAAAA==.',Ro='Roasted:BAAALAAECgMIAwAAAA==.Rocksee:BAAALAAECgMIAwAAAA==.Rosao:BAAALAAECgYICwAAAA==.',Ry='Ryuke:BAAALAADCgYIBgAAAA==.',['Rã']='Rãmbõ:BAAALAAECgMIAwAAAA==.',['Rí']='Ríchter:BAAALAAECgcIEAAAAA==.',Sa='Sangrina:BAAALAAECgMIBgAAAA==.Sanstormrage:BAAALAADCggIDwABLAAECgMIAwABAAAAAA==.Sark:BAAALAAECggICgAAAA==.Saucyjenkins:BAAALAAECgEIAQAAAA==.',Sc='Scranton:BAAALAADCgMIAwAAAA==.',Se='Sense:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Serrangel:BAAALAADCgQIBAAAAA==.Setaal:BAAALAADCgcIBwAAAA==.',Sf='Sfida:BAAALAAECgEIAQAAAA==.',Sh='Shalanot:BAAALAAECgMIAwABLAAECgcIEAABAAAAAA==.Shamaculous:BAAALAAECgEIAQAAAA==.Shamaniel:BAAALAADCggICAAAAA==.Shamun:BAAALAADCggICQABLAAECgMIAwABAAAAAA==.Shamyshaman:BAAALAAECgYIDAAAAA==.Shattra:BAAALAAECgQICAAAAA==.Shiftdh:BAAALAADCgEIAQAAAA==.Shondo:BAAALAADCgcIBwAAAA==.',Si='Silverz:BAAALAADCgcIBwAAAA==.Simohiya:BAAALAAECgEIAQAAAA==.Simp:BAEALAAECgUIBQABLAAFFAIIAgABAAAAAA==.',Sk='Skülly:BAAALAADCgcIBwAAAA==.',Sn='Snekk:BAAALAAECgMIAwAAAA==.Snowen:BAAALAAECgMIAwABLAAECgcICAABAAAAAA==.',So='Soziin:BAAALAAECgMIAwAAAA==.',Sp='Spintor:BAAALAAECgIIAgAAAA==.Spnookz:BAAALAADCggICAAAAA==.Spooke:BAAALAADCgcIBwAAAA==.',St='Steeldruid:BAAALAAECgQIBAAAAA==.Stlez:BAAALAADCggIDgABLAAECgQIBgABAAAAAA==.Stonelock:BAAALAADCgUIBQAAAA==.Stërben:BAAALAADCggICAAAAA==.',Su='Sucrose:BAAALAAECgMIAwAAAA==.Sukuta:BAAALAAECgEIAQAAAA==.Sunamue:BAAALAADCgcIDAAAAA==.',Sw='Swaggie:BAAALAADCgYIBwAAAA==.Swizzlerr:BAAALAAECgIIAgAAAA==.Swolchungis:BAAALAAECgMIBAAAAA==.',Sy='Symmas:BAAALAAECggICwAAAA==.Syphian:BAAALAADCgQICAAAAA==.Syrenda:BAAALAADCgQIBQAAAA==.',Ta='Taishigi:BAAALAAECgYICAAAAA==.Tapewyrm:BAAALAAECgUICAAAAA==.Tarise:BAAALAADCgcIDAAAAA==.Tartarus:BAAALAADCgYIBgAAAA==.Taurox:BAAALAADCggICAAAAA==.',Te='Tecknique:BAAALAAECgYICgAAAA==.Telsan:BAAALAADCgMIAwAAAA==.Terd:BAAALAADCgcIDgAAAA==.Terraphy:BAAALAADCgYIBgAAAA==.Terrene:BAAALAADCggIDQAAAA==.',Th='Thalthar:BAAALAADCggIDwAAAA==.Theheretic:BAAALAADCgcIBwAAAA==.Thekwaz:BAACLAAFFIEIAAMPAAUIkheiAQB/AQAPAAQIPRSiAQB/AQAQAAIIfxT7AgC1AAAsAAQKgRgABA8ACAhwJRQDADcDAA8ACAjWJBQDADcDABAABQjoH0sJANEBABEAAwjHHQoTAAMBAAAA.Theslayer:BAAALAADCggIDwAAAA==.Thralia:BAAALAAECgQIBAAAAA==.',Ti='Tikitikitiki:BAAALAAECgYIBgAAAA==.Timmer:BAAALAADCggICAAAAA==.Tippolas:BAABLAAECoEVAAISAAgI7RzqDgCfAgASAAgI7RzqDgCfAgAAAA==.',To='Totemtartt:BAAALAAECgYICgAAAA==.Toughpig:BAAALAAECgYICAABLAAECggIFQAFAHQjAA==.Tovelo:BAAALAADCgYIBgAAAA==.Toxcinerate:BAAALAADCgcIBwABLAAECgQIBAABAAAAAA==.Toxice:BAAALAAECgQIBAAAAA==.Toxichots:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.Toxicshok:BAAALAADCgcIBwABLAAECgQIBAABAAAAAA==.Toxictotem:BAAALAADCgcIBwABLAAECgQIBAABAAAAAA==.',Tr='Trakeus:BAABLAAECoEXAAISAAgI5SN/BgAXAwASAAgI5SN/BgAXAwAAAA==.Treat:BAAALAAECgMICwAAAA==.Treetartt:BAAALAADCggICAAAAA==.Treyman:BAAALAAECgcIDwAAAA==.',Ts='Tsunadè:BAAALAAECgYICgAAAA==.',Tu='Turtlehermit:BAAALAAECgIIAgAAAA==.Tuskticular:BAAALAADCgQIBAAAAA==.',Ty='Tyzon:BAAALAADCgcICwAAAA==.',Ud='Udderownage:BAAALAAECgIIAgAAAA==.',Ug='Ugrikk:BAAALAADCgIIAgAAAA==.',Ul='Ulsoga:BAAALAAECgQIBwAAAA==.',Un='Unfair:BAAALAAECgYICAAAAA==.',Va='Valah:BAAALAAECgQIAQAAAA==.Varibash:BAAALAAECgYICQAAAA==.Vaspara:BAAALAAECgYIDQAAAA==.',Ve='Vedestril:BAAALAAECgUICQAAAA==.Vetsky:BAAALAAECgQIAQAAAA==.',Vi='Victor:BAAALAADCgcIDAAAAA==.',Vo='Volcarona:BAAALAADCgYIBgAAAA==.Vorronni:BAAALAADCgMIAwAAAA==.Vospox:BAAALAADCgMIAwABLAAECgMIBQABAAAAAA==.Vospoz:BAAALAAECgMIBQAAAA==.',Wa='Wardo:BAAALAADCggIDwAAAA==.',We='Wellen:BAAALAAECgIIAwAAAA==.Werewolf:BAAALAADCgYIDQAAAA==.',Wh='Whissa:BAAALAAECgcICAAAAA==.Whitepikmin:BAAALAAECgMIAwAAAA==.',Wi='Wildshade:BAAALAAECgMIAwAAAA==.Wilmer:BAAALAAECgcIDwAAAA==.Winterblast:BAAALAADCgUIBQAAAA==.Winterbrew:BAAALAADCgIIAgAAAA==.',Wo='Wohounoyi:BAAALAAECgEIAQAAAA==.',Wr='Wrar:BAAALAADCgcIBwAAAA==.Wravc:BAAALAAECgcIEwAAAQ==.Wrinkle:BAAALAADCgcIBwAAAA==.',['Wó']='Wólfsbane:BAAALAAECgYIBwAAAA==.',Xa='Xaspen:BAAALAAECgEIAQAAAA==.',Xe='Xert:BAAALAADCgEIAQAAAA==.',Xk='Xkos:BAAALAAECgQIBAAAAA==.',Xm='Xmysticxz:BAAALAADCggICAAAAA==.',Xn='Xnookz:BAAALAAECgYICAAAAA==.',Xt='Xtruuh:BAAALAAECgMIBAAAAA==.',Xx='Xxannii:BAAALAADCggICAAAAA==.',Ya='Yanyo:BAAALAAFFAEIAQAAAA==.Yargonz:BAAALAADCgcIBwAAAA==.Yargzdk:BAACLAAFFIEFAAIOAAMINwfJAQDGAAAOAAMINwfJAQDGAAAsAAQKgRcAAg4ACAgqIegCAMsCAA4ACAgqIegCAMsCAAAA.',Ye='Yeahyo:BAABLAAFFIEFAAIIAAMI/BEUAgDzAAAIAAMI/BEUAgDzAAAAAA==.Yeyol:BAAALAAECggIBgAAAA==.',Yo='Yoey:BAAALAADCgIIAgAAAA==.Yolius:BAAALAAECgEIAQAAAA==.Yoogi:BAAALAAECgEIAQAAAA==.Yoruhana:BAAALAADCgcIBwAAAA==.Youronfire:BAAALAAECgEIAQAAAA==.',Yu='Yunikon:BAAALAAECgYICgAAAA==.',Yy='Yyee:BAAALAADCggIDwAAAA==.',['Yè']='Yènnefer:BAAALAADCggICAABLAAECgYICgABAAAAAA==.',Za='Zanan:BAAALAADCgcIBwAAAA==.',Ze='Zekuru:BAAALAAECgcIEAAAAA==.Zell:BAAALAAECgMIBQAAAA==.Zensei:BAAALAAECgIIAgAAAA==.Zensix:BAAALAAECgMIAwAAAA==.Zeranyx:BAAALAAECgYIDAAAAA==.',Zh='Zhul:BAAALAADCgYIDAABLAAECgQIBgABAAAAAA==.',Zi='Zinkal:BAAALAADCggIEAAAAA==.',Zo='Zoohki:BAAALAAECgIIAgAAAA==.',Zu='Zuggzug:BAABLAAECoEUAAIHAAcI6h5eDgBnAgAHAAcI6h5eDgBnAgAAAA==.',['Çh']='Çhrõmié:BAAALAAECgUICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end