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
 local lookup = {'Unknown-Unknown','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','DemonHunter-Havoc','Warrior-Protection','Monk-Brewmaster','Warrior-Fury','Druid-Restoration','Shaman-Elemental',}; local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaragon:BAAALAADCggIDAABLAAECgIIAgABAAAAAA==.',Ad='Adamdracthyr:BAAALAAECgQIBwAAAA==.',Ae='Aeila:BAAALAADCgYIBgAAAA==.Aeriona:BAAALAAECgMIAwAAAA==.',Af='Affalon:BAABLAAECoEYAAICAAYIpBhqHADRAQACAAYIpBhqHADRAQAAAA==.',Ag='Agape:BAAALAAECgIIAgAAAA==.',Ai='Aine:BAAALAAECgEIAQAAAA==.',Ak='Akyospirit:BAAALAAECgMIAwAAAA==.',Al='Alanash:BAAALAADCggICAAAAA==.Alfa:BAAALAAECgQIBQAAAA==.Aliatra:BAAALAAECgIIAgAAAA==.Alroy:BAAALAADCgMIBQAAAA==.Aluina:BAAALAAECgEIAQAAAA==.Alustryelle:BAAALAADCgcIBwAAAA==.',Am='Amaglave:BAAALAAECgQIBQAAAA==.Amathore:BAAALAADCgUIBQAAAA==.',An='Angelove:BAAALAADCgcIEAAAAA==.Angen:BAAALAADCgcICQABLAAECgYIBgABAAAAAA==.Anguishgaze:BAAALAADCgcIBwAAAA==.Anomandaris:BAAALAAECgMIBQAAAA==.Antien:BAAALAAECgMIAwAAAQ==.',Ap='Appolymi:BAAALAAECgMIAwAAAA==.',Ar='Arcohunt:BAAALAAECgYICQAAAA==.Argentavis:BAAALAADCgEIAQAAAA==.Arkken:BAAALAAECgQIBwAAAA==.Arrkan:BAAALAADCgcIBwABLAAECgQIBwABAAAAAA==.Aruser:BAABLAAECoEUAAMDAAgIFCB3BACLAgADAAgItR53BACLAgAEAAYIahpaCQC0AQAAAA==.',As='Ashvalis:BAAALAAECgMIAwAAAA==.Asillyhunter:BAAALAAECgMIBAAAAA==.Askr:BAAALAADCggIDwAAAA==.Asphar:BAAALAAECgIIAwAAAA==.',Au='Aung:BAAALAAECgEIAQAAAA==.',Av='Avitarkorra:BAAALAADCgIIAgAAAA==.',Az='Azamii:BAAALAAECgQICAABLAAECgYICQABAAAAAA==.Azarion:BAABLAAECoEZAAICAAgI9hUSFAAhAgACAAgI9hUSFAAhAgAAAA==.Azoth:BAAALAADCgIIAgAAAA==.',Ba='Bartrak:BAAALAADCgUIBQAAAA==.Basil:BAAALAADCggICAABLAAECggIFQAFAN4iAA==.',Be='Bearrific:BAAALAAECgQIBgAAAA==.Bedtimestory:BAAALAADCgYIBgAAAA==.Behind:BAAALAADCgIIAgAAAA==.Beyond:BAAALAADCgcIEgAAAA==.',Bf='Bfresh:BAAALAADCgcICAAAAA==.',Bi='Bigbada:BAAALAAECgYIDQAAAA==.Bigbuddha:BAAALAADCgYIBgAAAA==.Bighurt:BAABLAAECoEWAAIGAAgIsxczFQBYAgAGAAgIsxczFQBYAgAAAA==.Bigimpin:BAAALAADCgcIBwAAAA==.Billybobb:BAAALAADCgcIBwAAAA==.Billybutcher:BAAALAAFFAEIAQAAAA==.Biscuit:BAABLAAECoEVAAIHAAgI7SAyAwDjAgAHAAgI7SAyAwDjAgAAAA==.',Bl='Blaam:BAAALAAECgIIAgAAAA==.Blacklisted:BAAALAADCgcICwAAAA==.Blep:BAAALAAFFAIIAgAAAA==.Blueknight:BAAALAAECgQIBwAAAA==.',Bo='Borealis:BAAALAAECgMIAwAAAA==.Borkbuster:BAAALAADCgYIBgAAAA==.Borlok:BAAALAAECgQICAAAAQ==.',Br='Braahmin:BAAALAAECgQICAAAAA==.Breebbs:BAAALAAECgYIDAAAAA==.Breebers:BAAALAADCgIIAgABLAAECgYIDAABAAAAAA==.Briantu:BAAALAAECgMIAwAAAA==.Bromio:BAAALAAECgYIBwAAAA==.Brownstain:BAAALAAECgIIAgAAAA==.Brud:BAAALAAECgMICAAAAA==.Bruisilla:BAAALAAECgEIAQAAAA==.Brönwyn:BAAALAADCgUIBQAAAA==.',Bu='Buckets:BAAALAADCgUIBQABLAAECgQIBwABAAAAAA==.',['Bä']='Bärkler:BAAALAAECgYICgAAAA==.',['Bè']='Bècklèy:BAAALAAECgcIEAAAAA==.Bèckléy:BAAALAADCggICAAAAA==.',Ca='Caimdownbro:BAAALAAECgIIBAAAAA==.Caleanone:BAAALAAECggIBwAAAA==.Camo:BAAALAAECgcIEQABLAAECgQIBQABAAAAAA==.Carahail:BAAALAAECgMIBAAAAA==.Carbonara:BAAALAAECgEIAQAAAA==.Carolbaskin:BAAALAAECgMIAwAAAA==.Catriona:BAAALAAECgUIBQAAAA==.Caulifla:BAAALAAECgYIEgAAAA==.',Ch='Charcuterie:BAAALAAFFAIIAgAAAA==.Cheezeburg:BAAALAAECgMIBQAAAA==.Chippmagi:BAAALAADCggICAAAAA==.Chipprawr:BAAALAADCgcIDgABLAADCggICAABAAAAAA==.Chira:BAAALAADCgUIBQAAAA==.Chronosaren:BAAALAAECgMIBQAAAA==.Chunkndunks:BAAALAADCgcIBwABLAADCggIGAABAAAAAA==.',Cl='Cloudnine:BAAALAAECgIIAgAAAA==.',Co='Codypendent:BAAALAAECggIAQAAAA==.Coloringbook:BAAALAADCgYIBgAAAA==.Colpy:BAAALAADCgcIDQAAAA==.Combopie:BAAALAADCgQIBAAAAA==.Corellon:BAAALAAECgYICQAAAA==.Cowmagic:BAAALAAECgIIAgAAAA==.',Cr='Cranee:BAAALAAECgMIAwAAAA==.Cranium:BAAALAAECgYICwAAAA==.Crazytasty:BAAALAAECgMIAwAAAA==.',Da='Daario:BAAALAADCgMIAwAAAA==.Dabßod:BAABLAAECoEVAAIIAAgIqyIcAwDFAgAIAAgIqyIcAwDFAgAAAA==.Dahpeht:BAAALAADCgcIBwAAAA==.Darige:BAAALAAECgQICgAAAA==.Darim:BAAALAADCgMIAwABLAAECgYIDQABAAAAAA==.Darthspawn:BAAALAADCgcIDQAAAA==.Daryn:BAAALAADCgUIBQAAAA==.Dathromir:BAAALAAECgEIAgAAAA==.Davidbowy:BAAALAADCgYICwABLAADCggIEwABAAAAAA==.',De='Deathrhino:BAAALAADCgEIAQAAAA==.Defy:BAAALAADCggICAAAAA==.Degrace:BAAALAAECgMIAwAAAA==.Demina:BAAALAADCggIDQABLAAECgYIDgABAAAAAA==.Demonainkor:BAAALAADCggIEAABLAAECgYICAABAAAAAA==.Demonicfury:BAAALAADCggIEwAAAA==.Dencity:BAAALAAECgMIAwAAAA==.Dendin:BAAALAADCgQIBAAAAA==.Desden:BAAALAAECgMIAwAAAA==.Devianchi:BAAALAAECgUICQAAAA==.Devicy:BAAALAADCggICwABLAAECgUICQABAAAAAA==.Devitodevour:BAAALAAECgUICAAAAA==.',Dh='Dhbert:BAAALAAECgIIAgAAAA==.',Di='Dirtfurry:BAAALAADCgQIBAAAAA==.Disastrophy:BAAALAAECgIIAgAAAA==.Disturbed:BAAALAAECgYICQAAAA==.',Dk='Dkson:BAAALAADCggICAAAAA==.',Do='Doudouzz:BAAALAADCgMIAwAAAA==.',Dr='Dragonfist:BAAALAADCggIEAAAAA==.Dragosamore:BAAALAADCggICAAAAA==.Dragthyr:BAAALAADCgMIAwAAAA==.Druiaier:BAAALAADCgYICAAAAA==.Drunkdragon:BAAALAAECgYIDgAAAA==.Drzeus:BAAALAAECgQIBQAAAA==.',Dy='Dyavola:BAAALAAECgMIBAAAAA==.',Ea='Earthquack:BAAALAAECgYIDAAAAA==.Earthwurm:BAAALAADCggIEAABLAAECgQIBQABAAAAAA==.',Ed='Edge:BAAALAAECgQIBwAAAA==.',Ee='Eel:BAAALAADCgEIAQABLAAECggIFQAHAO0gAA==.',Eg='Egirl:BAAALAADCggICAAAAA==.',El='Eleathe:BAAALAAECgYIDgAAAA==.Eleros:BAAALAAECgQIBAAAAA==.Elphinia:BAAALAADCgYIBgABLAADCggIEAABAAAAAA==.Elyas:BAAALAAECgUIBQAAAA==.',Em='Emeralde:BAAALAADCgYIBwAAAA==.Emt:BAAALAADCgQIBAAAAA==.',En='Enoki:BAAALAAECgQICAABLAAECggIFQAFAN4iAA==.',Er='Ertai:BAAALAAECgIIAwAAAA==.',Ex='Expiredsushi:BAAALAAECgcIEQAAAA==.',Fa='Fallingflame:BAAALAADCggIFwABLAAECgYICAABAAAAAA==.',Fe='Fedders:BAAALAAECgYIBwAAAA==.Felaids:BAAALAADCgUIBQAAAA==.Felidoria:BAAALAADCgYIBwABLAAECgYIBgABAAAAAA==.Felimonk:BAAALAAECgYIBgAAAA==.Fenndru:BAAALAADCggICAAAAA==.Fenramm:BAAALAAECgUIBQAAAA==.',Fi='Fishfood:BAAALAAECgMIAwAAAA==.Fixer:BAAALAADCgcIDAAAAA==.',Fl='Flöwër:BAAALAADCgcICAAAAA==.',Fo='Foudo:BAAALAAECgYICAAAAA==.',Fr='Frimm:BAAALAAECgUICwAAAA==.Frostmaster:BAAALAADCgcIBwAAAA==.',Fu='Fujitora:BAAALAADCgcIDwAAAA==.',Ga='Gangrene:BAAALAAECgQICAAAAA==.Garaharn:BAAALAADCggICwAAAA==.Gaviin:BAAALAAECgUICAAAAA==.',Ge='Gerhart:BAAALAAECgYIDgAAAA==.',Gi='Gibbthok:BAAALAAECgMIAwAAAA==.Gigarius:BAAALAAECgUICwAAAA==.',Go='Goldenthorn:BAAALAADCgMIAwAAAA==.Goncor:BAAALAAECgUICwAAAA==.Goopymane:BAAALAADCgcICwAAAA==.Gortar:BAAALAADCgYIBQAAAA==.Gotstone:BAAALAADCgcICAAAAA==.',Gr='Gracekellie:BAAALAADCgYICAAAAA==.Grayhuln:BAAALAAECgUICgAAAA==.Graywarden:BAAALAAECgYIBAABLAAECgYIAgABAAAAAA==.Griffpal:BAAALAAECgQICAAAAA==.Grokthar:BAAALAADCgMIAwAAAA==.Grumpygnome:BAAALAADCgMIAwAAAA==.',Gu='Gussy:BAAALAAECgQIBwAAAA==.',Ha='Hardord:BAAALAAECgMIAwAAAA==.Harmsxway:BAAALAAECgEIAQAAAA==.Haryle:BAAALAAECgEIAgAAAA==.Hayanne:BAAALAAECgQICAAAAA==.',He='Healisha:BAAALAAECgIIAgAAAA==.',Ho='Holikow:BAAALAAECgMIBQAAAA==.Holymousey:BAAALAAECgIIAgAAAA==.Holypie:BAAALAAECgIIAgAAAA==.Honorlife:BAAALAAECgcIEAAAAA==.',Hy='Hyam:BAAALAADCgcIDgAAAA==.',['Hâ']='Hârley:BAAALAADCgcIBwAAAA==.',Il='Ilharess:BAAALAAECgMIBgAAAA==.Ilthurial:BAAALAADCgIIAgAAAA==.',Im='Imbolc:BAAALAADCgIIAgAAAA==.',In='Inko:BAAALAAECgYICQAAAA==.Inkwell:BAAALAAECgcIEQAAAA==.',Is='Issola:BAAALAADCgcIBwAAAA==.',Ja='Jaardrius:BAAALAAECgMIAwAAAA==.Jagerdragon:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Jaskar:BAAALAAECgIIAgAAAA==.Jazmand:BAAALAAECgYICAAAAA==.',Ji='Jinnie:BAAALAAECgIIAgAAAA==.',Jl='Jlamborghini:BAAALAADCgcICwAAAA==.',Jo='Joe:BAAALAADCgIIAgABLAAECgYIDQABAAAAAA==.Johnnsnow:BAAALAAECgcIDwAAAA==.',Ju='Judaz:BAAALAAECgIIAgAAAA==.Judokeg:BAAALAAECgIIAgAAAA==.Junknthtrunk:BAAALAADCgcIEQAAAA==.',Ka='Kaboomkiñ:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.Kadune:BAAALAADCggIDwAAAA==.Kaisel:BAAALAAECgIIAwAAAA==.Kally:BAAALAADCgMIAwAAAA==.Kamgrim:BAAALAADCgcIBwAAAA==.Katyenka:BAAALAADCgYIBgAAAA==.',Kd='Kda:BAAALAADCggICgABLAAECgYIBgABAAAAAA==.',Ke='Keanew:BAAALAAECgYICwAAAA==.Keenry:BAAALAADCggIGQAAAA==.Kenryy:BAAALAADCgYIBgAAAA==.Keonna:BAAALAADCgUIBQAAAA==.Keppra:BAAALAADCgYIBgAAAA==.Kerlin:BAAALAAECgIIAQAAAA==.Keyman:BAAALAADCgQIBAAAAA==.',Ki='Killthrog:BAAALAAECgYICwAAAA==.Kilotanker:BAAALAADCgcICAAAAA==.Kimchi:BAABLAAECoEVAAIFAAgI3iKnAgAaAwAFAAgI3iKnAgAaAwAAAA==.Kinoxo:BAACLAAFFIEEAAIJAAMIbRRxAwABAQAJAAMIbRRxAwABAQAsAAQKgRgAAgkACAioI9IEACEDAAkACAioI9IEACEDAAAA.',Kr='Krissycat:BAAALAAECgIIAgAAAA==.Kronker:BAAALAADCgUIBQAAAA==.',Ku='Kundo:BAAALAADCggIEAAAAA==.',Ky='Kyraelna:BAEALAAECgIIAwAAAA==.',La='Lawdnijal:BAAALAAECgYIBQAAAA==.',Le='Leb:BAAALAADCggIGQAAAA==.Ledikins:BAAALAADCgcIBwAAAA==.Legnase:BAAALAAECgYICQAAAA==.Leht:BAAALAAECgMIAwAAAA==.Leiche:BAAALAAECgIIAQAAAA==.Lennykoggins:BAAALAADCgQIBQAAAA==.Lessgibbon:BAAALAAECgYIDAAAAA==.Lewolu:BAAALAAECgIIBAAAAA==.',Li='Lightning:BAAALAAECgIIAwAAAA==.Lilnasty:BAAALAAECgUICwAAAA==.',Ll='Llaerel:BAAALAADCgcICwAAAA==.',Lo='Locklocket:BAAALAAECgYIBgAAAA==.Locknut:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Longhornpibe:BAAALAAECgIIAgAAAA==.Lorethann:BAAALAADCgUIBQAAAA==.Lovethisgirl:BAAALAAECgYICAAAAA==.',Lu='Lucibrew:BAAALAADCggICAAAAA==.',Ma='Malus:BAAALAAECgEIAQAAAA==.Mandrack:BAAALAADCgMIAQAAAA==.Marthafirst:BAAALAAECgQIBwAAAA==.Martiex:BAAALAAECgIIAgAAAA==.Marypoppinss:BAAALAADCgUICAAAAA==.Mavramune:BAAALAAECgYIDQAAAA==.',Mc='Mcfürry:BAAALAAECgIIAgAAAA==.',Me='Meekal:BAAALAADCgQIBAAAAA==.Mehealgood:BAAALAAECgMIAwAAAA==.Melini:BAAALAADCgcIBwAAAA==.Melodeè:BAAALAADCgcIBwAAAA==.Mendool:BAAALAAECgMIBAAAAA==.Mendoon:BAAALAADCgUIBQABLAAECgMIBAABAAAAAA==.',Mi='Milki:BAAALAADCgcIBwAAAA==.Mincksie:BAAALAAECgMIAwAAAA==.Mirage:BAAALAAECgYIBgAAAA==.Mistbot:BAAALAAECgMIBQABLAAECgYIBgABAAAAAA==.',Mo='Moiraîne:BAAALAADCgcIBwABLAAECgUIBQABAAAAAA==.Mortemore:BAABLAAECoEVAAIGAAgIKiGFCQDpAgAGAAgIKiGFCQDpAgAAAA==.Motet:BAAALAAFFAIIAgAAAA==.Motoxman:BAAALAADCgMIAwAAAA==.Mozzarella:BAAALAADCggIDwABLAAFFAIIAgABAAAAAA==.',My='Mynoghra:BAAALAAECgMIBgAAAA==.',Na='Naraku:BAAALAADCgYIBgAAAA==.Nawé:BAAALAADCggIHAAAAA==.',Ne='Nemiroff:BAAALAADCggICAAAAA==.Nes:BAAALAADCggIEQAAAA==.Neshock:BAAALAADCgEIAQABLAADCggIEQABAAAAAA==.',Ni='Nissycc:BAAALAADCgcICAAAAA==.',No='Noctes:BAAALAAECgMIAwAAAA==.Novakhan:BAAALAAECgQIBAAAAA==.Noxveritas:BAAALAAECgYIDQAAAA==.',Ny='Nymphetamine:BAAALAAECgEIAgAAAA==.Nyym:BAAALAADCggIDAAAAA==.',Nz='Nzoth:BAAALAAECgYICAAAAA==.',['Nø']='Nør:BAAALAADCgQIBAAAAA==.',Om='Omorc:BAAALAAECgYIDQAAAA==.',Op='Opbra:BAAALAAECgMIAwABLAAECgYIBQABAAAAAA==.',Ow='Owenwilson:BAAALAADCgIIAgAAAA==.',Pa='Papaya:BAAALAAECgIIAgABLAAECggIFQAFAN4iAA==.Pawpatrol:BAAALAADCgYICgABLAAECgQIBwABAAAAAA==.',Pe='Peak:BAAALAADCgYIBgAAAA==.Pearlescence:BAAALAAECgYIEQAAAA==.Peda:BAAALAAECgYICwAAAA==.Perun:BAAALAAECgMIBgAAAA==.',Ph='Phaba:BAAALAADCgUIBQAAAA==.',Pi='Pinecone:BAAALAADCgMIAwAAAA==.Pistolshrimp:BAAALAADCggIDgAAAA==.',Pn='Pneumonya:BAAALAADCggIFgAAAA==.',Po='Poochie:BAAALAAECgEIAQAAAA==.Porteagarder:BAAALAADCggIDwAAAA==.Potatodruid:BAAALAADCgQIBAAAAA==.',Pr='Pringler:BAAALAADCgMIAwABLAAECggIFQAHAO0gAA==.Prometeus:BAAALAAECgYIDQAAAA==.',Pu='Puffthemagic:BAAALAAECgYICQAAAA==.Purplenutz:BAAALAADCgcIBwAAAA==.',Py='Pyatt:BAAALAAECgUICAAAAA==.',Qu='Quelana:BAAALAAECgMIAwABLAAECgUICwABAAAAAA==.Quilae:BAAALAADCgYICgAAAA==.',Ra='Rassputin:BAAALAAECgQICAAAAA==.Raïn:BAAALAADCggICQAAAA==.',Re='Rendezvous:BAAALAADCgcIBwAAAA==.Renkà:BAAALAADCggIEAAAAA==.Requestor:BAAALAADCggICAAAAA==.Rezkal:BAAALAADCgcIDAAAAA==.',Rh='Rheas:BAAALAADCgUIBgAAAA==.Rhelaka:BAAALAAECgEIAQAAAA==.',Ri='Rice:BAAALAAECgUICAABLAAECggIFQAHAO0gAA==.Ritoshiba:BAAALAAECgYIBwAAAA==.',Ro='Roereker:BAAALAADCggIDwAAAA==.Roketraccoon:BAAALAAECgIIAgAAAA==.Roshamandes:BAAALAAECgUICAAAAA==.',Rt='Rtee:BAAALAAECgQIBwAAAA==.',Ru='Rubyshaman:BAAALAADCgUICAABLAAECgQIBwABAAAAAA==.',Ry='Rysera:BAAALAAECgEIAgAAAA==.',Sa='Saiki:BAAALAADCgcIDAAAAA==.Salythia:BAAALAADCgYICQABLAAECgYIDgABAAAAAA==.Sanataanna:BAAALAADCgYIBgAAAA==.Sandvichus:BAAALAAECgIIAgAAAA==.Saphiro:BAAALAAECgMIBgAAAA==.Sardine:BAAALAAECgEIAgABLAAECggIFQAFAN4iAA==.Sasukie:BAAALAADCgMIBgAAAA==.',Se='Seers:BAAALAAECgIIAgAAAA==.Sevencharlie:BAAALAAECgYICQAAAA==.',Sg='Sgathaich:BAEALAAECgYICQAAAA==.',Sh='Shadtae:BAAALAAECgEIAQAAAA==.Shambrume:BAAALAAECgMIAwAAAA==.Sheji:BAAALAADCgcIBwAAAA==.Shenare:BAAALAADCggICAAAAA==.',Si='Siete:BAAALAAECgQICAAAAA==.Sigvolden:BAAALAAECgEIAQAAAA==.Silver:BAAALAAECgIIAwAAAA==.Siona:BAAALAAECgQICAAAAA==.',Sk='Skadie:BAAALAAECgcIDwAAAA==.Skyler:BAAALAAECggIAgAAAA==.',Sl='Slavalous:BAAALAAECgEIAQAAAA==.',Sm='Smiteslay:BAAALAAECgUIBQAAAA==.',Sn='Snackpack:BAAALAADCggIDAAAAA==.Snivels:BAAALAAECgQIBAAAAA==.',So='Soap:BAAALAADCgIIAgABLAAECgQIBwABAAAAAA==.Soil:BAAALAAECgcIDwAAAA==.Sookie:BAAALAADCgUIBQAAAA==.',Sp='Sparrkle:BAAALAAECgYICgAAAA==.Spawnkis:BAAALAADCgcIBwAAAA==.Spillin:BAAALAADCgcIBwAAAA==.Spinecrawler:BAAALAAECgcIDQAAAA==.Spyro:BAAALAADCggIFAAAAA==.Spyrø:BAAALAAECgMIBgAAAA==.',St='Starfallen:BAAALAADCggICAAAAA==.Starlia:BAAALAADCgYIBgAAAA==.Stellanova:BAAALAAECgYICQAAAA==.Sthomely:BAAALAADCggIFwAAAA==.Stiblesnbits:BAAALAAECgYIDQAAAA==.Stibly:BAAALAADCgQIBAAAAA==.Stickshamm:BAAALAADCgcIDgAAAA==.Stiick:BAAALAAECgQICAAAAA==.Streakycat:BAAALAADCgMIAwAAAA==.',Su='Subzerow:BAAALAADCgcICAAAAA==.',Sw='Swaine:BAAALAADCggIGAAAAA==.Sweetbippy:BAAALAAECgMIAwAAAA==.Swifthealss:BAAALAAECgUICwAAAA==.',Sy='Sygvalden:BAAALAADCgcIBwAAAA==.Sylenar:BAAALAADCgcIBwAAAA==.Sylphie:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Sylunae:BAAALAADCggICAAAAA==.Syluné:BAAALAAECgIIAwAAAA==.',Ta='Taebae:BAAALAADCgUIBQAAAA==.Takeluck:BAAALAADCgYIBgAAAA==.Tambot:BAAALAAECgMIBAAAAA==.Tariced:BAAALAADCgUIBQAAAA==.Taunted:BAAALAADCgQIBAAAAA==.',Te='Tessa:BAAALAAECgQICAAAAA==.',Th='Thahtmana:BAAALAADCgEIAQAAAA==.Thalooze:BAAALAAECgIIAgABLAADCggIEwABAAAAAA==.Thedoctorwho:BAAALAAECgMIAwAAAA==.Theplant:BAAALAADCgcIBwAAAA==.Thornytoad:BAAALAADCgIIAgAAAA==.Thulir:BAAALAADCgUIBQABLAADCggIGAABAAAAAA==.Thundda:BAAALAAECgIIAwAAAA==.Thyone:BAAALAADCgMIAwAAAA==.',Ti='Timarri:BAAALAADCgcIBwAAAA==.',To='Tolstoi:BAAALAAECgIIAwAAAA==.Tomcatt:BAAALAAECgQICAAAAA==.Torghar:BAAALAADCggICAAAAA==.Toxin:BAAALAADCgUIBgAAAA==.',Tr='Tremblay:BAAALAAECgYIBwAAAA==.Triketia:BAAALAAECgYIAgAAAA==.',Tu='Turin:BAAALAAECgYIDQAAAA==.Tutonik:BAAALAADCgcICwAAAA==.',Tw='Twelves:BAAALAADCgUIBQAAAA==.Twiizted:BAAALAADCgYIBAAAAA==.Twilghtdawn:BAAALAAECgcIEAAAAA==.',Ty='Tybo:BAAALAAECgQICAAAAA==.Tysh:BAAALAADCgQIBAAAAA==.',['Të']='Tëmporus:BAAALAAECgMIAwAAAA==.',Un='Underbear:BAABLAAECoEUAAIKAAgISBIEEwDlAQAKAAgISBIEEwDlAQAAAA==.Ungieblinks:BAAALAAECgYICwAAAA==.Unholyherpes:BAAALAAECgcICwAAAA==.Union:BAAALAAECgIIAgAAAA==.',Va='Vaekicks:BAAALAAECgEIAgAAAA==.Vaeshoots:BAAALAADCggIDwAAAA==.Vainagos:BAAALAAECgIIAgAAAA==.Valdra:BAAALAAECgYIDAAAAA==.Valoryan:BAAALAAECgQICAAAAA==.Valyteilssra:BAAALAADCgQIBAAAAA==.Vanaris:BAAALAADCgMIAwAAAA==.Vasoline:BAAALAAECgQIBgAAAA==.',Ve='Vegà:BAAALAAECgUICwAAAA==.Vercina:BAAALAADCggIDwAAAA==.Vetraugr:BAAALAAECgMIAwAAAA==.Vextaerin:BAAALAADCgcICAABLAAECgMIAwABAAAAAA==.',Vi='Virulent:BAAALAADCgYIBgAAAA==.Vivienreed:BAAALAADCggIEwAAAA==.',Vo='Voiddragon:BAAALAAECgYIDgAAAA==.Voidhax:BAAALAADCgcIBwAAAA==.Voidnight:BAAALAADCggICAAAAA==.Voidshamz:BAAALAAECgEIAgAAAA==.Voranne:BAAALAAECgMIAwAAAA==.',Wa='Warpaínt:BAAALAADCggICgAAAA==.Warraxemo:BAAALAADCgYIBgABLAAECgQIBQABAAAAAA==.Warraxhunt:BAAALAADCggICAABLAAECgQIBQABAAAAAA==.Warraxmonk:BAAALAADCgIIAgABLAAECgQIBQABAAAAAA==.Warraxrage:BAAALAAECgQIBQAAAA==.',Wh='Whattheduck:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Whiskeyjak:BAAALAAECgYICwAAAA==.',Wi='Willowest:BAAALAAECgMIAwAAAA==.Wintresdotir:BAAALAADCgUIBQAAAA==.Wizbizzler:BAAALAAECgYICgAAAA==.',Wr='Wrathstorm:BAAALAAECgYIDAAAAA==.',Wt='Wtfpie:BAAALAAECgcIDwAAAA==.',Wu='Wurm:BAAALAAECgQIBQAAAA==.',Xa='Xalgas:BAAALAAECgUIBQAAAA==.Xane:BAAALAADCggIDwAAAA==.Xanier:BAAALAADCgUIBQAAAA==.',Xe='Xeshio:BAAALAAECgcIEAAAAA==.',Xi='Xiangyang:BAAALAADCgUIBwAAAA==.',Xy='Xyndylyne:BAAALAADCgQIBAAAAA==.',Ya='Yanella:BAAALAAECgYIDQAAAA==.',Yi='Yishunter:BAAALAAECgYIBwAAAA==.Yisshaman:BAAALAAECgYIBgAAAA==.',Za='Zandarbribbs:BAAALAAECgMIAwAAAA==.Zarinia:BAAALAAECgMIAwAAAA==.',Ze='Zenainkor:BAAALAAECgYICAAAAA==.Zennya:BAAALAAECgYIDQAAAA==.Zenofchaos:BAAALAADCgMIBAAAAA==.Zephis:BAAALAAECgYIDAAAAA==.',Zo='Zoeso:BAAALAAECgEIAgAAAA==.',['Zè']='Zèrà:BAAALAADCggIDAAAAA==.',['Öp']='Öprahwinfury:BAABLAAECoEUAAILAAcIhBhPGADpAQALAAcIhBhPGADpAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end