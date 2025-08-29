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
 local lookup = {'Unknown-Unknown','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Havoc','Druid-Feral','DemonHunter-Vengeance',}; local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aamamiya:BAAALAAECgIIAgAAAA==.',Ab='Abswarrior:BAAALAADCgMIBAAAAA==.',Ac='Acacia:BAAALAADCgUIBwAAAA==.Acallyne:BAAALAADCgcICgAAAA==.',Ad='Adema:BAAALAADCgUIBwAAAA==.',Ag='Ageowri:BAAALAADCgMIBwAAAA==.',Ai='Airplains:BAAALAADCgEIAQAAAA==.',Al='Alanderath:BAAALAADCgMIAwAAAA==.Aldarin:BAAALAAECgMIBQAAAA==.Alexinath:BAAALAADCggICAAAAA==.Algana:BAAALAADCgcICwAAAA==.Alicia:BAAALAADCgUIBQAAAA==.Allmights:BAAALAAECgIIAgAAAA==.Alunee:BAAALAADCgcIBwAAAA==.Alymental:BAAALAAECgYICQAAAA==.',Am='Amoranol:BAAALAADCgUIBwAAAA==.Amoxicillin:BAAALAADCgIIAgAAAA==.',An='Angcamundead:BAAALAADCgcIDwAAAA==.Angelyn:BAAALAADCgcIEgAAAA==.Anhell:BAAALAADCggICAAAAA==.Anitadrink:BAAALAAECgUIBgAAAA==.Anitapiss:BAAALAADCggICAAAAA==.Annaesthesia:BAAALAADCgcIBwAAAA==.Anubisra:BAAALAADCgcIDQAAAA==.',Aq='Aquana:BAAALAADCgcICgAAAA==.',Ar='Araeli:BAAALAADCgYIBgAAAA==.Arbysmeats:BAAALAAECgEIAQAAAA==.Ardelle:BAAALAAECgYIBgAAAA==.Ardil:BAAALAAECgYICQAAAA==.Ariella:BAAALAADCgQIBgAAAA==.Arodin:BAAALAAECgcIDgAAAA==.',As='Astería:BAAALAADCgcIBwAAAA==.',At='Atomoonk:BAAALAADCggICAAAAA==.',Av='Avelan:BAAALAAECgQIBwAAAA==.',Az='Azrina:BAAALAADCgYIBgAAAA==.Aztanara:BAAALAAECgcIDQAAAA==.',['Aü']='Aüras:BAAALAADCgQIBAAAAA==.',Ba='Baameansno:BAAALAAECgMIAwAAAA==.Badboi:BAAALAADCgYICAAAAA==.',Be='Bearpah:BAAALAAECgYIBwAAAA==.Beefmiester:BAAALAADCgMIAwAAAA==.Beelzeblub:BAAALAADCggIBwAAAA==.Behealzabub:BAAALAADCgcICgAAAA==.Belpepper:BAAALAAECgYICwAAAA==.',Bh='Bhakta:BAAALAAECgYICgAAAA==.',Bi='Bigchungus:BAAALAADCgcIBwAAAA==.Bigdicer:BAAALAADCggIEgABLAAECgEIAQABAAAAAA==.Biggiepoppa:BAAALAAECgcIEAAAAA==.Bindinglight:BAAALAAECggIEwAAAA==.',Bl='Blarr:BAAALAAECgUIBQAAAA==.Blindvoid:BAAALAAECgMIBQAAAA==.Blockhead:BAAALAAECgYICwAAAA==.Blubtide:BAAALAAECgQIBQAAAA==.',Bm='Bmacprime:BAAALAADCgcICQAAAA==.',Bo='Bonesteel:BAAALAAECgQIBQAAAA==.Borednow:BAAALAAECgYIDgAAAA==.Bourritos:BAAALAADCgUIAwAAAA==.Boxbeater:BAAALAAECgYIDAAAAA==.',Br='Braunsonn:BAAALAADCgQIBAAAAA==.Breadloaf:BAAALAADCgYIBgAAAA==.Bretickus:BAAALAADCgYIBgABLAAECggIFAACAGEZAA==.Breticus:BAABLAAECoEUAAMCAAgIYRkSDgBUAgACAAgIYRkSDgBUAgADAAEIUgPrTQA0AAAAAA==.Bretitron:BAAALAADCgYIBQABLAAECggIFAACAGEZAA==.',Bu='Bubbasquez:BAAALAAECgYICwAAAA==.Bubblefett:BAAALAAECgMIAwAAAA==.Bubbletown:BAAALAAECgYIBgAAAA==.Burntbernie:BAAALAADCgQIBAAAAA==.',Ca='Carandir:BAAALAADCgQIBAAAAA==.Careless:BAAALAADCgIIAgAAAA==.',Ce='Celedaris:BAAALAAECgEIAQAAAA==.Celiasa:BAAALAAECgUIBwAAAA==.',Ch='Chipunch:BAAALAAECgMIAwAAAA==.',Ci='Cinderkit:BAAALAAECgcIEAAAAA==.',Cl='Clarinase:BAAALAADCgUIBwAAAA==.Clawed:BAAALAAECgMIBgAAAA==.Cleomenes:BAAALAADCgYIBgAAAA==.Cloakndagger:BAAALAAECgEIAQAAAA==.',Co='Cocinegr:BAAALAAECggIBgAAAA==.Cocinegrö:BAAALAAECgYIDQAAAA==.Cocinegrø:BAAALAAECggIEgAAAA==.Colmcille:BAAALAADCgMIAwABLAADCgcIBwABAAAAAA==.Columcille:BAAALAADCgcIBwAAAA==.Coneja:BAAALAAECgIIAgAAAA==.Coompi:BAAALAAECgUIBQAAAA==.Coomspit:BAAALAAFFAIIAgAAAA==.',Cr='Craiso:BAAALAAECgMIAwAAAA==.Crystalmac:BAAALAADCgUIBQAAAA==.',Cu='Cuddlesama:BAAALAADCgcIBwAAAA==.Cudleyknight:BAAALAAECgIIAgAAAA==.Current:BAAALAAECgYICQAAAA==.',Cy='Cynesh:BAACLAAFFIEHAAQEAAUItBcjAQAsAQAEAAMIPyIjAQAsAQAFAAEIYg8MCQBdAAAGAAEIZAD3AABUAAAsAAQKgRgAAwQACAhHJvcBAFUDAAQACAhHJvcBAFUDAAYAAggEHJIIALwAAAAA.Cypri:BAAALAADCgIIAgABLAADCggICAABAAAAAA==.',['Cô']='Cômbustiôn:BAAALAADCgcICgAAAA==.',Da='Dabigdad:BAAALAADCgYIBwAAAA==.Daisylight:BAAALAADCgMIAwAAAA==.Dandoris:BAAALAAECggICAAAAA==.Dangybangy:BAAALAAECgMIAwAAAA==.Darkkarma:BAAALAADCggIDwAAAA==.Darkrabbit:BAAALAADCgQIBwAAAA==.Darromar:BAAALAAECgQIBgAAAA==.Darthdraoi:BAAALAADCgQIBAAAAA==.',De='Deadenjet:BAAALAADCgcIBwAAAA==.Deadmez:BAAALAAECgIIAgAAAA==.Deadspace:BAAALAADCgIIAgAAAA==.Deadèyédonny:BAAALAAECgEIAQAAAA==.Deathpal:BAAALAAECgYIDAABLAAECggIGgAFABUjAA==.Deathpenguin:BAAALAADCgYICQAAAA==.Deathscythe:BAAALAADCgcICgAAAA==.Deba:BAAALAADCgcICwAAAA==.Defe:BAAALAAECgEIAgAAAA==.Demodrana:BAAALAADCgEIAQAAAA==.Denethin:BAAALAAECggIEAAAAA==.Derazand:BAAALAADCgMIAwAAAA==.Dervkin:BAAALAADCgIIAgAAAA==.Despott:BAAALAAECgYICgAAAA==.Dethfox:BAAALAADCggIDgAAAA==.Deystanne:BAAALAADCgQIBAAAAA==.',Di='Diaba:BAAALAAECgYICAAAAA==.Diiviiniity:BAAALAADCgcICQAAAA==.Dinelli:BAAALAAECgcIEwAAAA==.',Dk='Dkmiasma:BAAALAAECgMIAwAAAA==.',Do='Domado:BAAALAAECgYICAAAAA==.Domedamaga:BAAALAADCggICAAAAA==.',Dr='Draaeevin:BAAALAADCgEIAQAAAA==.Dragdoner:BAAALAADCgUIBgAAAA==.Dragonbjorn:BAAALAAECgYIBwAAAA==.Dragonperson:BAAALAADCggIEAAAAA==.Dreadspell:BAAALAADCggIDAAAAA==.Dreamzy:BAAALAADCggICwAAAA==.Dreamzyboy:BAAALAADCgcIDQAAAA==.Drenarx:BAAALAADCgMIAwAAAA==.Dreyden:BAAALAAECgIIAgAAAA==.Drunkendrago:BAAALAADCgYIBgAAAA==.',Dw='Dworrin:BAAALAADCgEIAQAAAA==.',['Dü']='Dürinn:BAAALAADCgYIDwAAAA==.',Ea='Earthenness:BAAALAADCgMIBQAAAA==.Eazzinow:BAAALAADCggIEAAAAA==.',Ec='Ecclesia:BAAALAAECgcICgAAAA==.Echina:BAAALAADCgYIBgAAAA==.Echodecay:BAAALAADCggIDwABLAAECgEIAgABAAAAAA==.Echofoxxy:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.Echokaylee:BAAALAAECgEIAgAAAA==.Echolaylee:BAAALAADCgEIAQABLAAECgEIAgABAAAAAA==.Echomentium:BAAALAADCgcICgABLAAECgEIAgABAAAAAA==.Echothulhu:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.',Ed='Eddings:BAAALAAECgQIBQAAAA==.',Eh='Ehud:BAAALAAECgUIBwAAAA==.',Ei='Eievoker:BAEALAADCggICAAAAA==.Eisengießer:BAAALAADCggICAAAAA==.',El='Elexiel:BAAALAADCgEIAQAAAA==.Elianie:BAAALAADCgcIBwAAAA==.Elieva:BAAALAADCggIDAAAAA==.Eliteshaman:BAAALAAECgQIBAAAAA==.Elrithien:BAAALAADCgcIBwAAAA==.',Em='Emberstalker:BAAALAADCggICAAAAA==.Emerhy:BAAALAADCgYICgAAAA==.',En='Enderartica:BAAALAADCgcIBwAAAA==.Entropy:BAAALAADCgMIAwABLAAECgIIAgABAAAAAA==.',Er='Erni:BAAALAAECgMIAwAAAA==.',Es='Esthana:BAAALAADCgcIBwAAAA==.',Ex='Executè:BAAALAADCgEIAQABLAAECggIFgAHAEAcAA==.',Fa='Facundo:BAAALAADCgQIBwAAAA==.Faeriedustt:BAAALAADCgcIBwAAAA==.Faeveline:BAAALAADCgcIBwAAAA==.Fake:BAAALAAECgEIAQAAAA==.Fanorage:BAAALAADCggIDwAAAA==.',Fe='Feetuspickle:BAAALAADCggICAAAAA==.Feltaarna:BAAALAADCgYIDQAAAA==.Ferlena:BAAALAAECgEIAQAAAA==.Ferzhurt:BAAALAADCgYIDAAAAA==.',Fl='Flaffergan:BAAALAAECgcICgAAAA==.Flickrgoon:BAAALAADCggIEQAAAA==.',Fo='Focinnet:BAAALAADCgUICQAAAA==.Fourform:BAAALAAECgYICQAAAA==.Foxshrine:BAAALAAECgEIAQAAAA==.',Fr='Frakel:BAAALAAECggIAQAAAA==.Frostbite:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.',Fu='Furgan:BAAALAADCggICQAAAA==.Furiõsa:BAAALAADCgYIBwAAAA==.',Ga='Gaalit:BAAALAADCggICQAAAA==.Galedric:BAAALAAECgcIDQAAAA==.Ganthamonk:BAAALAAECgcICQAAAA==.Garli:BAAALAADCgYIBgAAAA==.Garzett:BAAALAAECgcIDgAAAA==.',Ge='Geisterjäger:BAAALAAECgcIDgAAAA==.Gengar:BAAALAADCgMIAwAAAA==.Gentlelover:BAAALAADCgMIAwAAAA==.',Go='Goblinbone:BAAALAADCgcIBwAAAA==.Goldendagger:BAAALAADCgYICAAAAA==.Goobly:BAAALAAECgMIAwAAAA==.Gooseburglar:BAAALAADCgcIBwAAAA==.Gosling:BAAALAADCgcIBwAAAA==.Goswick:BAAALAAECgEIAQAAAA==.Gotarrows:BAAALAADCgUIBQAAAA==.',Gr='Grardor:BAAALAADCgcIBwAAAA==.Gregs:BAAALAAECgIIAgAAAA==.Griffinlance:BAAALAAECgMIAwAAAA==.Grim:BAABLAAECoEYAAIIAAgI+yDCAQABAwAIAAgI+yDCAQABAwAAAA==.Grimvalde:BAAALAAECgEIAQAAAA==.Gruevin:BAAALAAECgYIBgAAAA==.',Gu='Guzzing:BAAALAADCgIIAgAAAA==.',Gw='Gwory:BAAALAADCgcICQAAAA==.',Ha='Haeli:BAAALAADCgcIBwAAAA==.Halibel:BAAALAADCggIAQAAAA==.Hammerceleid:BAAALAAECgMIAwAAAA==.Haramzadi:BAAALAADCgYICAAAAA==.Harukà:BAAALAAECgEIAQAAAA==.Hasthin:BAAALAADCgcIBwAAAA==.Havvik:BAAALAADCgYICgAAAA==.',He='Heeler:BAAALAAECgYIDAAAAA==.Helfon:BAABLAAECoEWAAMHAAgIQBzNGQAuAgAHAAcIxxvNGQAuAgAJAAMIvgwYHQCdAAAAAA==.Henrywells:BAAALAADCgIIAgAAAA==.Herbsnspices:BAAALAADCgYIDAAAAA==.Herrotas:BAAALAAECgEIAQAAAA==.',Hi='Highguytamus:BAAALAADCgcIBwAAAA==.Highrisk:BAAALAADCgMIBQAAAA==.Hiira:BAAALAADCggICAAAAA==.',Ho='Holycharlie:BAAALAAECgQIBQAAAA==.Holyely:BAAALAAECgIIAgAAAA==.Holykopi:BAAALAAECgMIAwAAAA==.Holyrager:BAAALAADCgEIAQABLAADCggIDwABAAAAAA==.Holyvez:BAAALAAECgIIAgAAAA==.Hozdiso:BAAALAADCgMIAwAAAA==.',Hu='Huxian:BAAALAAECgMIBAAAAA==.',['Hø']='Hørus:BAAALAADCgYIBgAAAA==.',Ia='Iatromanteis:BAAALAAECgUICwAAAA==.',Ic='Iccyhot:BAAALAAECgEIAQAAAA==.',Id='Ideasniper:BAAALAADCggIDgAAAA==.',Il='Iliraelis:BAAALAADCggIDwAAAA==.',In='Inâs:BAAALAADCggIDwAAAA==.',Io='Ioannis:BAAALAADCggIFQAAAA==.',Iu='Iutasta:BAAALAAECgYIDAAAAA==.',Iy='Iyams:BAAALAADCgUIBQAAAA==.Iykyk:BAAALAADCgcICAABLAAECgMIBgABAAAAAA==.',Ja='Jaarvis:BAAALAADCgcIBwAAAA==.Jandel:BAAALAADCgYICQAAAA==.',Je='Jessicax:BAAALAADCgcIBwAAAA==.',Ji='Jinurzah:BAAALAADCgcIDwAAAA==.Jinxedsilent:BAAALAAECgMIAwAAAA==.Jizter:BAAALAADCgMIBAAAAA==.',Jr='Jrgrinder:BAAALAADCgQICAAAAA==.',Ju='Julip:BAAALAADCggICAAAAA==.Justgoodman:BAAALAAECgIIBAAAAA==.',Ka='Kaebe:BAAALAADCgIIAgAAAA==.Kaifre:BAAALAAECgMIAwAAAA==.Kalashnikov:BAAALAADCgYIBgAAAA==.Kandicee:BAAALAADCgEIAQAAAA==.Kanekirenji:BAAALAAECgYIDAAAAA==.',Ke='Kellyx:BAAALAADCgEIAQAAAA==.Kenbone:BAAALAAECgcICAAAAA==.Keninumaki:BAAALAADCgUIBQAAAA==.Kennope:BAAALAADCgcIBwAAAA==.Kenz:BAAALAAECgMIAwAAAA==.Keony:BAAALAAECgMIBgAAAA==.',Ki='Kiarly:BAAALAADCggICAABLAAECgcIFAAIAAUbAA==.Kickiarly:BAAALAAECgIIAwABLAAECgcIFAAIAAUbAA==.Kirozen:BAAALAADCgcICwAAAA==.Kittyarly:BAABLAAECoEUAAIIAAcIBRveBQBBAgAIAAcIBRveBQBBAgAAAA==.',Kn='Kneeler:BAAALAAECgEIAQAAAA==.',Ko='Kodokan:BAAALAADCgMICAAAAA==.Kopitres:BAAALAADCgYIBgAAAA==.Koshima:BAAALAAECgcIDgAAAA==.Kothnah:BAAALAADCgEIAQAAAA==.',Kr='Kreamer:BAAALAAECgYICwAAAA==.Krimhit:BAAALAADCgcICAAAAA==.Krithix:BAAALAADCggICAAAAA==.Kronkle:BAAALAAECgIIAgAAAA==.',Ku='Kudranne:BAAALAADCgEIAQABLAADCgcICgABAAAAAA==.Kugia:BAAALAAECgQIBQABLAAECgcIEAABAAAAAA==.Kulikitaka:BAAALAADCggIFgAAAA==.Kuorie:BAAALAAECgcICgAAAA==.',Ky='Kynndell:BAAALAADCgcICQAAAA==.',['Ká']='Kárurosu:BAAALAADCgMIAwAAAA==.',La='Laellinar:BAAALAAECgIIAgAAAA==.Lanastaul:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Larryhoover:BAAALAAECgMIAwAAAA==.Lavert:BAAALAADCgIIAgAAAA==.',Le='Leetheal:BAABLAAECoEbAAICAAgITxniDwA+AgACAAgITxniDwA+AgAAAA==.Lepaladin:BAAALAADCgMIAwAAAA==.',Li='Lightbound:BAAALAADCgUIBQAAAA==.Ligmanut:BAAALAADCgMIAwAAAA==.Lilheal:BAAALAAECgEIAQAAAA==.Lionël:BAAALAAECgIIAgAAAA==.Lirkö:BAAALAAECggIEgAAAA==.Lizakos:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.Lizbethe:BAAALAAECgYICAAAAA==.Lizzana:BAAALAADCgYIBgABLAAECgYICAABAAAAAA==.',Lo='Loltank:BAAALAADCggICQAAAA==.Lopiazo:BAAALAADCgYICQAAAA==.Lorshadow:BAAALAADCgIIAgAAAA==.Lorwater:BAAALAADCgcICwAAAA==.',Lu='Lu:BAAALAADCggICAAAAA==.Luminivira:BAAALAADCgQIBwAAAA==.Lummy:BAAALAAECgQIBwAAAA==.Lunandre:BAAALAAECgYICQAAAA==.Lunaru:BAAALAAECgMIAwAAAA==.Lunaryon:BAAALAADCgcICwAAAA==.Lunascalesht:BAAALAAECgYIDgAAAA==.Lurelune:BAAALAAECgYIDgAAAA==.',Ly='Lyndisius:BAAALAAECgMIAwAAAA==.Lyndiss:BAAALAADCgYIBwAAAA==.',['Lÿ']='Lÿcos:BAAALAADCgEIAQAAAA==.',Ma='Maamzyn:BAAALAAECgMIBQAAAA==.Mackie:BAAALAAECgQIBAABLAAECgUIBQABAAAAAA==.Magaica:BAAALAAECggICAAAAA==.Magarr:BAAALAADCggICAAAAA==.Magnar:BAAALAAECgEIAgAAAA==.Magnustitus:BAAALAADCggICAAAAA==.Mallowe:BAAALAADCgcICwAAAA==.Malphite:BAAALAADCgYIBgAAAA==.Malystryx:BAAALAAECgMIBgAAAA==.Maritand:BAAALAADCgcIBwAAAA==.Marsi:BAAALAADCgQIBAAAAA==.Matchplayr:BAAALAADCggICAAAAA==.Maxximus:BAAALAAECgMIAwAAAA==.',Me='Meeteor:BAAALAAECgYICwAAAA==.Melviera:BAAALAADCggICQAAAA==.Memeep:BAAALAAECgcIDwAAAA==.Metadrone:BAAALAADCgYIBgAAAA==.',Mi='Miasmaa:BAAALAAECgMIBgAAAA==.Michi:BAAALAADCgYIBgAAAA==.Mikaeldh:BAAALAADCgcIBwAAAA==.Mikoshii:BAAALAAECgMIBQAAAA==.Milkytheman:BAAALAAECgMIBQAAAA==.Minority:BAAALAAECgMIBAAAAA==.Mirandax:BAAALAADCgIIAgAAAA==.Missbehavior:BAAALAADCgcICgAAAA==.Mithril:BAAALAADCgEIAQAAAA==.',Mo='Montekar:BAAALAADCgQIBAAAAA==.Moocowlady:BAAALAADCggICAAAAA==.Moogan:BAAALAAECgMIBQAAAA==.Moonfishing:BAAALAAECgYICQAAAA==.Moozi:BAAALAAECgUICAAAAA==.Morax:BAAALAADCgcIBwAAAA==.Morgian:BAAALAADCggICAAAAA==.',Mu='Munn:BAAALAAECgQIBwAAAA==.',['Mì']='Mìlo:BAAALAAECgIIAgAAAA==.',['Mï']='Mïlinsky:BAAALAADCggICwAAAA==.',['Mø']='Mørgàna:BAAALAADCgcICgAAAA==.',['Mÿ']='Mÿstres:BAAALAADCgcIEwAAAA==.',Ne='Necrotica:BAAALAAECgIIAQAAAA==.Nemessis:BAAALAAECgYIBwAAAA==.Nervouz:BAAALAAECgYIDgAAAA==.',Ni='Nightzone:BAAALAAECgMIAwAAAA==.Niisheo:BAAALAAECgQIBAABLAAECgUIBwABAAAAAA==.Nisheo:BAAALAAECgUIBwAAAA==.',No='Nobbs:BAAALAADCgcIDwAAAA==.Noctis:BAAALAAECgMIAwAAAA==.Nokurai:BAAALAAECgQIBQAAAA==.Norex:BAAALAADCgcIBwAAAA==.Nosaj:BAAALAAECgMICwAAAA==.Novas:BAAALAAECgcIEwAAAA==.Novie:BAAALAAECgYICwAAAA==.',Ol='Olaraine:BAAALAADCgIIAgAAAA==.',On='Onolyr:BAAALAAECgYICwAAAA==.',Or='Ornawsan:BAAALAADCgMIAwAAAA==.',Ou='Outdps:BAAALAADCgYIDgAAAA==.',Pa='Pacificadora:BAAALAADCgcIBwAAAA==.Palapla:BAAALAADCgEIAQAAAA==.Palasox:BAAALAADCggICAAAAA==.Pamella:BAAALAADCgYIBgAAAA==.Pathran:BAAALAAECgYICQAAAA==.',Pe='Penguinpunch:BAAALAAECgIIAgAAAA==.Pepperlina:BAAALAADCggIEwABLAAECgYICwABAAAAAA==.Perzeval:BAAALAADCgIIAgAAAA==.Perzevil:BAAALAADCgEIAQAAAA==.Pewpewdmgtwo:BAAALAAECgEIAQAAAA==.',Ph='Phardurp:BAAALAADCgYIBgAAAA==.Pharmacology:BAAALAADCgcIFAAAAA==.',Pi='Pieceofchit:BAAALAADCgcIBwAAAA==.Pighead:BAAALAADCgYIBgAAAA==.',Pl='Platebait:BAAALAAECgMIBQAAAA==.',Pr='Prathe:BAAALAAECgYICQAAAA==.Preistiest:BAAALAADCggICAAAAA==.Premorry:BAAALAADCgMIAwAAAA==.Premory:BAAALAADCgYICQAAAA==.Priestspence:BAAALAADCgcIDAAAAA==.Prodas:BAAALAADCgUIBQAAAA==.',Ps='Psilocy:BAAALAAECgYIDAAAAA==.Pspspspspsps:BAAALAADCggICAAAAA==.',Pt='Pterodactrol:BAAALAADCggIDwAAAA==.',Pw='Pwrhôuse:BAAALAADCggICQAAAA==.',Py='Pyroclastic:BAAALAADCgcIDwAAAA==.Pyromourne:BAAALAAECgQIBQAAAA==.',['Pé']='Pétro:BAAALAADCgcICgAAAA==.',['Pø']='Pøseïdøn:BAAALAAECgUICAAAAA==.',Qi='Qiz:BAAALAADCggIDwAAAA==.',Qu='Quignite:BAAALAADCgcICQAAAA==.',Ra='Radlock:BAAALAADCgUICAAAAA==.Radmaster:BAAALAADCgYIBgAAAA==.Rahzimbo:BAAALAADCgYIBwAAAA==.Raidens:BAAALAADCgUIBQAAAA==.Rayzac:BAAALAADCggIDwAAAA==.',Re='Reanthus:BAAALAADCgcIBwAAAA==.Redhand:BAAALAADCgYICwAAAA==.Rexdruidiae:BAAALAADCgcICgAAAA==.Reyra:BAAALAADCgcIBwAAAA==.',Ri='Rienno:BAAALAAECgEIAQAAAA==.Risu:BAAALAADCggICAAAAA==.',Ro='Rockmuncher:BAAALAAECgYICQAAAA==.',Ru='Rubberduck:BAAALAADCgMIBAAAAA==.Rufustitus:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',Ry='Rylain:BAAALAADCggICAAAAA==.',Sa='Safedruid:BAAALAADCgUIBQAAAA==.Salestia:BAAALAADCgcICQAAAA==.Saniblaze:BAAALAADCgcIEQAAAA==.Sarrazine:BAAALAAECgYIDgAAAA==.Sasive:BAAALAADCgcIDgAAAA==.',Sc='Scuseme:BAAALAADCgcICQAAAA==.Scärlët:BAAALAAECgQIBQAAAA==.',Se='Seanoodlex:BAAALAADCgEIAQAAAA==.Septìctank:BAAALAADCggIDQABLAAECggIEwABAAAAAA==.',Sh='Shadewalker:BAAALAADCgcIDQAAAA==.Shadoshamy:BAAALAADCgcIBwAAAA==.Shadowkiarly:BAAALAADCggICAAAAA==.Shadowxbane:BAAALAAECgEIAQAAAA==.Shaft:BAAALAADCgcICAAAAA==.Shamanhaze:BAAALAADCggIDQAAAA==.Shambasta:BAAALAADCgYIDAAAAA==.Shamonella:BAAALAADCggIEAAAAA==.Shaquayvia:BAAALAADCgQIBwAAAA==.Shnaggletoof:BAAALAADCgUIBQAAAA==.',Si='Sigismund:BAAALAAECgIIBAAAAA==.Sikorr:BAAALAADCgcIBwAAAA==.Sillthoren:BAAALAADCgIIAgAAAA==.Silthela:BAAALAADCgcICQAAAA==.Silvaine:BAAALAADCgcICgAAAA==.Silversunn:BAAALAADCggICAAAAA==.Sinnful:BAAALAADCgcICAAAAA==.',Sk='Skyscourge:BAAALAADCgUIBQAAAA==.',Sl='Slowhealing:BAAALAAECgYICQAAAA==.',Sm='Smas:BAAALAADCggICAAAAA==.Smiteclub:BAAALAAECgMIBAAAAA==.Smorheal:BAAALAAECgUIBgAAAA==.',Sn='Snipez:BAAALAADCggICAAAAA==.',So='Solclipeus:BAAALAAECggIBgAAAA==.Soulkiss:BAAALAADCgIIAgAAAA==.Soultaker:BAAALAAECgIIAgAAAA==.Soupz:BAAALAAECgQIBAAAAA==.',Sp='Spendruid:BAAALAADCgcIDAAAAA==.Spiezo:BAAALAAECgYICgAAAA==.',Sr='Sramarillo:BAAALAADCgIIAgAAAA==.Sririacha:BAAALAAECgYICQABLAAECgYIDgABAAAAAA==.',Ss='Ssilky:BAAALAADCggIDwAAAA==.',St='Statick:BAAALAADCggIEQAAAA==.Stonefayth:BAAALAADCggICAAAAA==.',Sy='Sylthorn:BAAALAAECgMIAwAAAA==.',Ta='Taezanx:BAAALAADCgcIBwAAAA==.Talok:BAAALAAECgEIAQAAAA==.Talonhand:BAAALAADCgUIBQAAAA==.Tanburn:BAAALAADCgIIAgAAAA==.Tanduinex:BAAALAAECgMIBAAAAA==.Tanduino:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.Tarrna:BAAALAADCgYICwAAAA==.',Te='Teaglizzy:BAAALAADCgEIAQAAAA==.Teehole:BAAALAAECgYICAAAAA==.',Th='Theadrin:BAAALAADCgEIAQAAAA==.Theladydruid:BAAALAAECgYIDAAAAA==.Thendris:BAAALAADCggIFAAAAA==.Theshadowtwo:BAABLAAECoEXAAIHAAgIqQ0/JwDRAQAHAAgIqQ0/JwDRAQAAAA==.Thighsoffel:BAAALAAECggIBgAAAA==.Thirdtjme:BAAALAADCgMIAwAAAA==.Thordam:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Thorrig:BAAALAADCgEIAQAAAA==.',Ti='Tigerpa:BAAALAAECggIBwAAAA==.Tilonius:BAAALAADCgcIBwAAAA==.Tinydarts:BAAALAAECgEIAQAAAA==.Tioklarus:BAAALAAECgMICgAAAA==.',To='Tofulady:BAAALAAECgIIAgAAAA==.',Tr='Tralandrov:BAAALAAECgQIBwAAAA==.Trazarì:BAAALAADCgcICgAAAA==.Tricket:BAAALAADCgUIBQAAAA==.Trim:BAAALAADCgYIBgAAAA==.',Tt='Ttempest:BAAALAADCggIDQAAAA==.',Tw='Twoblind:BAAALAAECggIEwAAAA==.',Ty='Tyania:BAAALAAECgEIAQAAAA==.Tylorlandis:BAAALAADCgIIAgAAAA==.',Tz='Tzifardem:BAAALAADCgcIDwAAAA==.',Ul='Ulala:BAAALAADCggIDwAAAA==.',Um='Umbarda:BAAALAADCgUIBQAAAA==.',Va='Valdanna:BAAALAADCgcICgAAAA==.Vatica:BAAALAAECgEIAQAAAA==.',Ve='Velenice:BAAALAADCggIFAAAAA==.Venvalzhar:BAAALAADCggIFgAAAA==.Vexlore:BAAALAADCgcIBwAAAA==.',Vo='Voidknight:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.',Vy='Vyri:BAAALAAECgIIAgAAAA==.',['Vê']='Vêzz:BAAALAAECgEIAQAAAA==.',Wa='Warbeast:BAAALAADCgcIDgAAAA==.',We='Weirdowl:BAAALAAECgYICQAAAA==.Wells:BAAALAAECgEIAQAAAA==.Wetramin:BAAALAAECgMIAwAAAA==.',Wh='Whiplashh:BAAALAAECgMIAwAAAA==.',Wi='Wingedlady:BAAALAAECgEIAQAAAA==.',Wr='Wreaper:BAAALAADCggIDwAAAA==.Wrøth:BAAALAAECgUICAAAAA==.',Xg='Xgnomercy:BAAALAADCgUIBQAAAA==.',Xi='Xiing:BAAALAAECgcIDgAAAA==.',Xw='Xwhitesnow:BAAALAADCgQIBAAAAA==.',Yo='Yoshinö:BAAALAADCggIEwAAAA==.',Ys='Ysmir:BAAALAADCggIDgAAAA==.',Yu='Yunjin:BAAALAAECgQIBAAAAA==.',['Yü']='Yüto:BAAALAAECgEIAQAAAA==.',Za='Zabuto:BAAALAAECgcIDQAAAA==.Zaing:BAAALAADCgYIBgAAAA==.Zarzul:BAAALAADCgcICQAAAA==.Zazmo:BAAALAAECgEIAQAAAA==.',Ze='Zeratul:BAAALAAECgQIBAAAAA==.',Zh='Zhaoming:BAAALAADCggICAAAAA==.',Zi='Zicatriz:BAAALAADCgIIAgAAAA==.',Zo='Zoë:BAAALAADCgcICwAAAA==.',Zs='Zshot:BAABLAAECoEaAAIFAAgIFSNQAwAPAwAFAAgIFSNQAwAPAwAAAA==.',Zu='Zuggýzug:BAAALAADCgcIEwAAAA==.',['Äb']='Äbracadabruh:BAAALAAECgQIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end