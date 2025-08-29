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
 local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Warrior-Fury','Paladin-Protection','Monk-Mistweaver','Mage-Frost','Monk-Brewmaster','Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Shaman-Enhancement','Shaman-Elemental','Evoker-Preservation','Shaman-Restoration','Druid-Balance','Monk-Windwalker','Rogue-Assassination','Druid-Feral','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Havoc','Mage-Arcane','Mage-Fire','Warrior-Protection','Druid-Guardian',}; local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaeise:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.',Ad='Addy:BAAALAAECgUICAAAAA==.',Ae='Aeonis:BAAALAADCgcICgAAAA==.',Ag='Agamesh:BAAALAADCgIIAgAAAA==.',Ai='Ailysely:BAAALAADCggIFAAAAA==.Aioli:BAAALAADCggICAAAAA==.Airees:BAAALAADCgcIBwAAAA==.',Al='Aldamojo:BAAALAAECgMIBAAAAA==.Aletheia:BAAALAADCgQIBAAAAA==.Alledria:BAAALAAECgYIDAAAAA==.Allfiction:BAAALAADCggICAAAAA==.Allundiel:BAAALAADCgcICwAAAA==.',Am='Amphi:BAAALAAECgcICwAAAA==.',An='Andramalych:BAAALAADCggIDwAAAA==.Angbar:BAAALAAECgMIBgAAAA==.Animefiller:BAAALAADCgcIBwAAAA==.',Ar='Arcadian:BAAALAAECgYIDwAAAA==.Arextheelder:BAAALAAECgMIAwAAAA==.Argentum:BAAALAADCgcIBwABLAAECgUICAABAAAAAA==.Armorscales:BAAALAAECgQIBAAAAA==.Arntraz:BAAALAADCggIDgAAAA==.',As='Asena:BAAALAADCgMIAwAAAA==.Ashlynd:BAAALAADCgIIAgAAAA==.Ashnikko:BAAALAAECgEIAQAAAA==.Asotcha:BAAALAADCgQIBQAAAA==.',Au='Auberon:BAAALAADCggIEAAAAA==.',Az='Azi:BAABLAAECoEWAAICAAgIpiIZBAD9AgACAAgIpiIZBAD9AgAAAA==.',Ba='Backpedal:BAAALAAECgIIAgAAAA==.Badankhadonk:BAAALAAECgcIDgAAAA==.Balen:BAAALAAECgMIBAAAAA==.Balthazär:BAAALAADCgcIDQAAAA==.Bandrösh:BAAALAAECgYICQAAAA==.',Be='Bearlyliable:BAAALAADCggICAAAAA==.Bearmetalx:BAAALAAECgEIAQAAAA==.Beefmuffinz:BAAALAADCggICAAAAA==.Beethozart:BAAALAADCggICAAAAA==.Beliice:BAAALAADCggIEQAAAA==.Bellawesome:BAAALAADCgcICQAAAA==.Belmako:BAAALAADCgcICwAAAA==.Bendeekay:BAAALAAECgQIBAAAAA==.Berek:BAAALAADCgcIDwAAAA==.Bessiepea:BAAALAAECgMIAwAAAA==.',Bi='Bigcenergy:BAAALAADCgcIBwABLAAECgIIBAABAAAAAA==.',Bl='Blackblood:BAAALAAECgMIBAAAAA==.Blackclouds:BAAALAAECgEIAQAAAA==.Blacktemplar:BAAALAADCgcIBwAAAA==.Bloodache:BAAALAADCgcICAAAAA==.Bloodkissed:BAAALAAECgYICQAAAA==.Bluxx:BAAALAAECgYIDQAAAA==.',Bo='Boo:BAAALAAECgcIDQAAAA==.',Br='Brakeable:BAAALAADCgUICQAAAA==.Brewbu:BAAALAAECgYIBgAAAA==.Brewskies:BAAALAAECgcIDQAAAA==.Broombolt:BAAALAADCggICAAAAA==.Brownington:BAAALAAECgYIDAAAAA==.Brìonik:BAAALAAFFAIIAwAAAA==.',Ca='Cabezaeponke:BAAALAADCgIIAgAAAA==.Caldrelin:BAAALAAECgIIAgAAAA==.Calibarn:BAAALAADCggICAAAAA==.Cariagne:BAAALAAECgcIDQAAAA==.Catnap:BAAALAADCgcIDgAAAA==.',Ch='Charbol:BAAALAADCgYIBgAAAA==.Chelraani:BAAALAAECgMIBAAAAA==.Chunn:BAAALAADCgIIAgAAAA==.Chychard:BAAALAADCgcIDgAAAA==.',Ci='Cigar:BAAALAADCgcICgABLAAECgIIAgABAAAAAA==.Cinderburn:BAAALAADCgYIDQAAAA==.',Cl='Claymore:BAAALAAECgcICwAAAA==.Clazzicola:BAAALAAECgcIDwAAAA==.Clue:BAAALAADCgcIBwAAAA==.',Cp='Cptncrush:BAAALAAECgMIBAAAAA==.',Cr='Crackstalion:BAAALAAECgEIAQAAAA==.Crowshadow:BAAALAADCgYICQAAAA==.',Cu='Cukeemonster:BAAALAADCgcIBwAAAA==.Cupcakes:BAAALAADCggICAAAAA==.',Cy='Cyther:BAACLAAFFIEFAAIDAAMIthpXAgAbAQADAAMIthpXAgAbAQAsAAQKgRcAAgMACAhGIwsFAB8DAAMACAhGIwsFAB8DAAAA.',Da='Dabzmage:BAAALAADCgUIBQAAAA==.Daddydawson:BAAALAADCggIEAAAAA==.Daennerys:BAAALAAECgYIBgAAAA==.Darkdottie:BAAALAAECgEIAQAAAA==.Dayday:BAAALAAECggIAwAAAA==.',De='Deadbeatdeeb:BAAALAAECgEIAQAAAA==.Deadtofall:BAAALAADCgYIBwAAAA==.Decix:BAABLAAECoEXAAIEAAgIBCbHAABfAwAEAAgIBCbHAABfAwABLAAFFAEIAQABAAAAAA==.Deity:BAAALAAECgIIAgAAAA==.Demonicpets:BAAALAADCggICAAAAA==.Dempselmae:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Denni:BAAALAADCgcIBwAAAA==.Desolation:BAAALAAECgcIDQAAAA==.Despia:BAAALAAECgMIBAAAAA==.',Di='Dicot:BAAALAAECgMIBAAAAA==.Discjockey:BAAALAAECgcICQAAAA==.',Do='Doughy:BAAALAADCggICAAAAA==.',Dr='Dragnyr:BAAALAAECgMIBAAAAA==.Dragoncurry:BAAALAAECgYIDQAAAA==.Draktor:BAAALAAECgMIAwABLAAECggIFgADABEhAA==.Draktyr:BAABLAAECoEWAAIDAAgIESF1CQDQAgADAAgIESF1CQDQAgAAAA==.Druadh:BAAALAAECgMIAwABLAAECgYIDQABAAAAAA==.',Ef='Effmonk:BAAALAAECgEIAQAAAA==.',El='Elanora:BAAALAAECgMIBAAAAA==.',En='Enamorada:BAAALAAECgMIBQABLAAECgYIDQABAAAAAA==.',Er='Ereithelda:BAACLAAFFIEFAAIFAAMIGRXDAQAAAQAFAAMIGRXDAQAAAQAsAAQKgRcAAgUACAgkHlgEAKgCAAUACAgkHlgEAKgCAAAA.Eryss:BAAALAAECgMIAwAAAA==.',Ev='Evill:BAAALAADCggIDgAAAA==.Evox:BAAALAAECgEIAQAAAA==.',Fa='Fann:BAAALAAECgMIBAAAAA==.Faytl:BAAALAAECgQIBwAAAA==.',Fe='Fewz:BAABLAAECoEWAAIGAAcIWiAUBgCBAgAGAAcIWiAUBgCBAgAAAA==.',Fi='Filog:BAAALAADCgcIBwAAAA==.Fireflake:BAAALAAECgMIAwAAAA==.Fission:BAAALAADCgQIBAAAAA==.',Fl='Flakflap:BAAALAAECgQIBAABLAAECgcIFAAHAJ0ZAA==.Flakiron:BAAALAADCgYIBgABLAAECgcIFAAHAJ0ZAA==.Flakov:BAABLAAECoEUAAIHAAcInRluCADxAQAHAAcInRluCADxAQAAAA==.',Fo='Forbacon:BAAALAAECgMIAwAAAA==.Force:BAAALAAECgMIBAAAAA==.Fornost:BAAALAADCggICAAAAA==.',Fr='Fremosth:BAAALAAECgMIBgAAAA==.Freshe:BAAALAADCgcICgAAAA==.Fridgie:BAACLAAFFIEFAAIIAAMI9gqmAgDvAAAIAAMI9gqmAgDvAAAsAAQKgRcAAggACAjcFkkTAEkCAAgACAjcFkkTAEkCAAAA.Frozenflyer:BAAALAAECgcIDwAAAA==.',Fu='Furburglar:BAAALAADCgcIDgAAAA==.',Ga='Garcutt:BAAALAAFFAMIBAAAAA==.Gazember:BAAALAAECgEIAQAAAA==.',Ge='Genericck:BAAALAADCggICgAAAA==.Genericdh:BAAALAADCggIDgAAAA==.Generickmonk:BAAALAAECgYIDAAAAA==.Genericlock:BAAALAADCggIDgAAAA==.Gensis:BAAALAADCgYICAAAAA==.',Gi='Ginrai:BAAALAADCgcIBwAAAA==.Giovannucci:BAAALAAECgQIBQAAAA==.',Go='Goatreaper:BAAALAAECgMIAwAAAA==.',Gr='Grasstomouth:BAAALAADCgUIDAABLAAECgIIBAABAAAAAA==.Grayeyes:BAAALAADCgYIBwAAAA==.Greenngoblin:BAAALAADCgUIBgAAAA==.',Gu='Guino:BAAALAADCgIIAgAAAA==.Guinodk:BAAALAADCgcIDgAAAA==.Guinodruid:BAAALAADCgcIDAAAAA==.',['Gô']='Gôdzilla:BAAALAAECgYIDgAAAA==.',Ha='Hail:BAAALAADCgMIAwAAAA==.Harddrugs:BAAALAADCgQIBAAAAA==.Hazis:BAAALAAFFAIIAgAAAA==.',Ho='Holy:BAABLAAECoEUAAIJAAcISB7uCAA3AgAJAAcISB7uCAA3AgAAAA==.Holyhoette:BAAALAADCgQIBAAAAA==.Holymoki:BAAALAADCgcICwAAAA==.Holyroundie:BAAALAAECgYIDAAAAA==.Holyshock:BAABLAAFFIEFAAIKAAMIdxfHAQAHAQAKAAMIdxfHAQAHAQAAAA==.Honeybutter:BAAALAAECgIIAgAAAA==.Hordebreaker:BAAALAAECgIIBAAAAA==.',Hu='Huntrx:BAAALAAECgQIBAAAAA==.Huukend:BAAALAAECgcIDAAAAA==.',Ic='Icebabyman:BAAALAAECgYICQAAAA==.',In='Inkypal:BAAALAAECgYICQAAAA==.',Ir='Ironea:BAAALAADCgQIBAAAAA==.Irukox:BAAALAAECgMIAwAAAA==.',Jb='Jbournz:BAAALAADCggIFQAAAA==.',Je='Jemma:BAAALAAECgMIAwAAAA==.Jettatotes:BAABLAAECoEXAAMLAAgIDx/bAQDbAgALAAgIDx/bAQDbAgAMAAEIiwLSUgAxAAAAAA==.',Ji='Jimmystrazsa:BAABLAAECoEWAAINAAgIEh5kAgCyAgANAAgIEh5kAgCyAgAAAA==.',Ju='Jubba:BAAALAAECgMIAwAAAA==.Jurlkani:BAAALAAECgYICgABLAAECgcIDwABAAAAAA==.Jusskidinn:BAAALAADCggICAAAAA==.',['Jé']='Jéks:BAAALAAECgMIAwABLAAFFAMIBQAOAPoWAA==.',['Jë']='Jëks:BAACLAAFFIEFAAIOAAMI+hYiAgDxAAAOAAMI+hYiAgDxAAAsAAQKgRcAAw4ACAhzHo4NAE0CAA4ABwifHY4NAE0CAAwABgj0H9EeAK0BAAAA.',Ka='Kaelenmonk:BAAALAAECgMIBAAAAA==.Kaghroxxar:BAAALAADCggICQAAAA==.Kaitou:BAAALAADCggIDwAAAA==.Kaladjin:BAAALAADCgEIAQAAAA==.Kalamiti:BAAALAAECgEIAQAAAA==.',Ke='Keeper:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.Kegshock:BAAALAAECgEIAQAAAA==.Keiyona:BAAALAADCgYIBgAAAA==.Kennethv:BAAALAAECgEIAQAAAA==.Kethra:BAAALAADCgUIBwAAAA==.Kev:BAAALAAECgYIAQAAAA==.',Kh='Khibanee:BAAALAADCgcIDQAAAA==.Khiell:BAABLAAECoEXAAIDAAgI5RszDACfAgADAAgI5RszDACfAgAAAA==.',Ki='Kinigit:BAAALAAECgQIBAABLAAECgcIFAAPAPYaAA==.Kirïtö:BAAALAADCgQIBQAAAA==.Kitarah:BAAALAAECgUICAAAAA==.',Kr='Kras:BAAALAAECgMIAwAAAA==.Krátos:BAAALAAECgcIDQAAAA==.',Ku='Kukalak:BAAALAAECgMIBQAAAA==.Kuranaa:BAAALAADCggIEgAAAA==.Kurrox:BAABLAAECoEUAAIQAAcI1h1PCABFAgAQAAcI1h1PCABFAgAAAA==.',Ky='Kynn:BAAALAADCgMIAwAAAA==.',['Kö']='Köögaca:BAAALAAECgMIBAAAAA==.',La='Lacerveza:BAAALAAECgEIAQAAAA==.Lahyanhou:BAAALAAECgIIAgAAAA==.Lalin:BAAALAAECgcICwAAAA==.Lamprey:BAAALAAECgQIBAAAAA==.Landonorris:BAAALAAECgMIAwAAAA==.',Le='Leeroy:BAAALAAECgQIBAAAAA==.',Li='Ligmasak:BAAALAAECgMIBQAAAA==.Lilandri:BAAALAADCgYIBgAAAA==.Lilbaddie:BAAALAAECgIIAgAAAA==.Lingyu:BAAALAAECgYICgAAAA==.',Lo='Locsul:BAAALAAECgMIAwAAAA==.Lorath:BAAALAADCggIDQAAAA==.',Lu='Lutola:BAAALAAECgYICgAAAA==.',Ma='Magolock:BAAALAADCgMIAwAAAA==.Mahadevah:BAAALAAECgMIAwAAAA==.Mahgìk:BAAALAADCgcIBwABLAADCgcIDQABAAAAAA==.Maidrim:BAABLAAECoEWAAIRAAgI0h8lBQDrAgARAAgI0h8lBQDrAgAAAA==.Majeh:BAAALAADCgcIDgAAAA==.Malygoss:BAAALAAECgMIBQAAAA==.Mamajumbo:BAAALAAECgEIAQAAAA==.Marellias:BAABLAAECoEUAAMIAAgI+yHVCgC0AgAIAAcIuiPVCgC0AgACAAQISxCTMADXAAAAAA==.Mayukä:BAAALAAECgEIAQAAAA==.',Me='Metahorfasis:BAAALAADCggIDQAAAA==.Metavanq:BAAALAAECggIEQAAAA==.',Mi='Midari:BAAALAADCggICAAAAA==.Mierín:BAABLAAECoEUAAISAAcI6SFEAwCvAgASAAcI6SFEAwCvAgAAAA==.Migrains:BAAALAAECgcIDQAAAA==.Miststress:BAAALAAECgcICQAAAA==.',Ml='Mlgmagescope:BAAALAAECgYICAAAAA==.',Mo='Mobal:BAAALAAECgMIAwAAAA==.Mojogreens:BAAALAAECgYIDAAAAA==.Morinth:BAAALAADCgcIBwAAAA==.',Mu='Muninn:BAAALAADCgQIBQABLAADCgYICQABAAAAAA==.',Na='Naessarra:BAAALAADCgcICgAAAA==.Naksu:BAAALAADCgcIDgAAAA==.Natlès:BAAALAAECgIIBAAAAA==.Nazgrim:BAAALAAECgEIAQAAAA==.',Ne='Nemäin:BAAALAADCgMIAwABLAADCgYICQABAAAAAA==.',Ni='Nihilist:BAAALAADCgYIBgAAAA==.Nikcrosis:BAAALAADCgUIBQAAAA==.Nikkolos:BAAALAADCgcIFAAAAA==.',No='Nogusta:BAACLAAFFIEFAAIDAAMI3QyPAwD8AAADAAMI3QyPAwD8AAAsAAQKgRcAAgMACAikH+cJAMYCAAMACAikH+cJAMYCAAAA.Norberta:BAAALAAECgUICAAAAA==.Nossellia:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.',Nu='Nurana:BAAALAADCgIIAgAAAA==.',Ny='Nyima:BAAALAAECgYICwAAAA==.',Od='Odell:BAAALAADCgMIAwAAAA==.',On='Onlyshams:BAAALAAECgcIDAAAAA==.Onlytides:BAEALAAECgMIAwAAAA==.Onu:BAAALAADCggICAABLAAECggIFQAEANkjAA==.Onudk:BAAALAAECgQIBAABLAAECggIFQAEANkjAA==.Onulight:BAABLAAECoEVAAIEAAgI2SOiAQAqAwAEAAgI2SOiAQAqAwAAAA==.Onulite:BAAALAAECgcICQABLAAECggIFQAEANkjAA==.Onux:BAAALAADCggICAABLAAECggIFQAEANkjAA==.',Or='Orondo:BAAALAAECgEIAQAAAA==.',Ou='Oumura:BAAALAAECgMIAwAAAA==.',Pa='Paarthürnax:BAAALAAECgcIDAAAAA==.Pandarina:BAAALAAECgMIBQAAAA==.Patamae:BAAALAADCgIIAgAAAA==.',Pe='Peste:BAAALAAECgMIAwAAAA==.',Ph='Phanbot:BAAALAAECgYICgAAAA==.Phantöm:BAAALAADCgcIBwAAAA==.',Po='Podan:BAAALAAECgcIDwAAAA==.Polypa:BAAALAADCgMIAwAAAA==.Poppapew:BAAALAADCggICgAAAA==.',Pr='Prestoh:BAAALAADCgcIBwAAAA==.',Pu='Puffmac:BAABLAAECoEXAAMTAAgImyFHDgCgAgATAAgIVCFHDgCgAgAUAAMIyCEsGgAeAQAAAA==.Purplehaze:BAAALAADCgUIBQAAAA==.Purplepickle:BAAALAADCgYICAABLAAECgIIBAABAAAAAA==.',Pv='Pvlolz:BAAALAAECgMIAwAAAA==.',Pw='Pwnstarz:BAAALAADCgcIDQAAAA==.',Qp='Qplus:BAAALAAECgMIBAAAAA==.',Qu='Quaenie:BAAALAAECgMIBAAAAA==.',Ra='Ragearrow:BAAALAADCgIIAwAAAA==.Raged:BAAALAAECgcIEAAAAA==.Ragenchi:BAAALAAECgEIAQAAAA==.Ragewarg:BAAALAADCgMIAwAAAA==.Ralvarr:BAAALAAECgMIAwAAAA==.Randana:BAAALAADCgEIAQAAAA==.Raptorjésus:BAAALAAECgEIAQAAAA==.Razenoe:BAAALAADCgYIBgAAAA==.',Re='Redchord:BAAALAAECgEIAQAAAA==.Redg:BAAALAAECgcIBwAAAA==.Relik:BAAALAAECgMIBAAAAA==.Rellana:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Resith:BAAALAADCgMIAwAAAA==.Retaliation:BAAALAADCgUIBQABLAAECgMIBQABAAAAAA==.Retpaladin:BAAALAADCgYICAAAAA==.',Rh='Rhaella:BAAALAADCggIAQAAAA==.Rhuath:BAAALAADCgUIBwAAAA==.',Ri='Rinaki:BAAALAAECgMIAwAAAA==.Ripmeta:BAABLAAECoEUAAQVAAcIeBdpFABjAQAVAAYIshVpFABjAQAWAAIIEw6hSQCLAAAXAAEIGh3gJABYAAAAAA==.Ripnandtearn:BAAALAAECgcIDQAAAA==.',Rk='Rk:BAAALAADCgUIBgAAAA==.',Ro='Robïn:BAAALAADCgQIBQABLAAECgIIBAABAAAAAA==.Rondon:BAAALAAECgMIBAAAAA==.Rookdh:BAABLAAFFIEFAAIYAAMIXghbBADvAAAYAAMIXghbBADvAAAAAA==.',Ru='Rugsalon:BAABLAAECoEWAAIGAAcI9RjfCwAIAgAGAAcI9RjfCwAIAgAAAA==.Rustedbarrel:BAAALAAECgcIEAAAAA==.Rustedgecko:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.',['Ré']='Réxxar:BAAALAADCgIIAgAAAA==.',Sa='Sagesse:BAAALAADCgUIBQAAAA==.Sammy:BAAALAAECgMIBAAAAA==.Santaclaaws:BAABLAAECoEVAAIYAAcIDCL/DQCrAgAYAAcIDCL/DQCrAgAAAA==.Santafuego:BAAALAAECgIIAgABLAAECgcIFQAYAAwiAA==.Santapal:BAAALAAECgYIDwABLAAECgcIFQAYAAwiAA==.Santhin:BAAALAAECgYIBgAAAA==.Saphotic:BAAALAAFFAEIAQAAAA==.Saren:BAAALAAECgYICQAAAA==.Sayvil:BAAALAAECgUIBwABLAAECgYICQABAAAAAQ==.',Sc='Schazemare:BAAALAAECgEIAQABLAAECgcIDwABAAAAAA==.',Se='Seawolph:BAAALAAECgUICAAAAA==.Semmers:BAAALAAECgQIBgAAAA==.Senadia:BAAALAADCgcIBwAAAA==.Sensational:BAAALAAECgUIBwAAAA==.',Sh='Shadowvoker:BAAALAAECggIAgAAAA==.Shadríelle:BAAALAADCggICAAAAA==.Shampooh:BAAALAADCgYIDAAAAA==.Shaokhan:BAAALAAECgcIEAAAAA==.Sharazugro:BAAALAAECgMIBAAAAA==.Sharthud:BAAALAADCgIIBAAAAA==.Shian:BAAALAAECgMIBAAAAA==.Shimto:BAAALAADCgYIBgAAAA==.Shockeei:BAACLAAFFIEFAAIZAAMI+hlgAwAZAQAZAAMI+hlgAwAZAQAsAAQKgRcAAxkACAhPJC0HAAoDABkACAgoIi0HAAoDABoAAQjLI3UJAGcAAAAA.',Si='Silverwar:BAAALAAECgUICAAAAA==.Sinarala:BAAALAADCggICAAAAA==.',Sk='Skepti:BAAALAAECgUICAAAAA==.',Sl='Slunkyspit:BAAALAADCgMIAwAAAA==.Slybearclaw:BAAALAADCgcIBwAAAA==.',Sm='Smeeta:BAAALAAECgEIAQAAAA==.',Sn='Sneakers:BAAALAAECgQIBAABLAAECggIFQAEANkjAA==.',So='Socorrista:BAAALAAECgYIDQAAAA==.Solo:BAAALAADCgIIAgAAAA==.Soomaa:BAABLAAECoEXAAITAAgI5htPDgCgAgATAAgI5htPDgCgAgAAAA==.Soro:BAAALAADCgQIBAAAAA==.Sosmall:BAAALAADCggICAABLAAECggIEQABAAAAAA==.',Sp='Spacepants:BAAALAADCgYIBgAAAA==.Spookywar:BAAALAADCgMIAwAAAA==.Spudvoke:BAAALAAECgEIAgAAAA==.Spudz:BAAALAADCgEIAQAAAA==.',St='Stormii:BAAALAAECgcIDAAAAA==.Strangerdk:BAAALAAECgMIBQAAAA==.Sturtime:BAAALAAECgMIBQAAAA==.',Su='Suet:BAABLAAECoEUAAIbAAgItyDCAwDMAgAbAAgItyDCAwDMAgAAAA==.Sundy:BAAALAADCgcICgAAAA==.',Sw='Swamppeople:BAAALAADCgIIAgAAAA==.Swishersweet:BAAALAAECgYIDwAAAA==.Swordfish:BAAALAADCgYIBgAAAA==.',Sy='Sydonie:BAAALAADCggICAAAAA==.Synccubus:BAAALAAECgYICQAAAA==.Synnøve:BAAALAADCggICAAAAA==.',['Sã']='Sãmmyliciõus:BAAALAADCgcIBwAAAA==.',['Sú']='Súnflower:BAAALAAECgIIAgAAAA==.',Ta='Tabrius:BAAALAAECgcIDQAAAA==.Tadokof:BAAALAADCgcIBwAAAA==.Talanth:BAAALAAECgIIAgAAAA==.Talitha:BAAALAAECgYICAAAAA==.Tamamo:BAAALAAECgYIBwAAAA==.Tamlyn:BAAALAAECggIEAAAAA==.Tanzil:BAAALAADCggICAAAAA==.Tayon:BAAALAAECgEIAQAAAA==.',Te='Tengen:BAAALAAECgYICwAAAA==.Termana:BAACLAAFFIEFAAIbAAMIgRtNAQAHAQAbAAMIgRtNAQAHAQAsAAQKgRcAAhsACAgqJYYBADoDABsACAgqJYYBADoDAAAA.',Th='Thiccpickle:BAAALAADCggICwABLAAECgIIBAABAAAAAA==.Thundersylph:BAAALAADCgYIBgAAAA==.Thør:BAAALAADCgcIBwAAAA==.',Ti='Tiann:BAAALAADCgEIAQAAAA==.Tiferet:BAAALAAECgUICAAAAA==.Tigiw:BAAALAADCgIIAgAAAA==.Tinysunshine:BAAALAAECgIIAgAAAA==.',To='Toddler:BAAALAAECgYIDAAAAA==.Tolenkar:BAAALAAECgMIBAAAAA==.Tomato:BAAALAAFFAEIAQAAAA==.Torvalar:BAAALAAECgcIDQAAAA==.',Tr='Treemendous:BAAALAADCgcIDAAAAA==.Troggdor:BAAALAADCgcIBwAAAA==.Trunks:BAAALAAECgcIDgAAAA==.',Ty='Tyfelsion:BAAALAAECgQIBQAAAA==.Tyleaon:BAAALAADCgEIAQAAAA==.',['Tô']='Tôx:BAAALAAECgcIDQAAAA==.',Ud='Udyrr:BAAALAADCggIEAAAAA==.',Um='Umbranwings:BAAALAAECgMIBAAAAA==.',Va='Vadican:BAAALAADCgMIAwAAAA==.Valydrin:BAAALAAECgcIDwAAAA==.Vanquished:BAAALAAECgYIBgABLAAECggIEQABAAAAAA==.',Ve='Velindala:BAAALAADCgMIAwAAAA==.Velonara:BAAALAADCgMIAwAAAA==.Velrion:BAAALAADCggICgAAAA==.Veristoros:BAAALAADCgcICQAAAA==.',Vi='Vinsmoke:BAAALAAECggIDAAAAA==.',Vy='Vysis:BAAALAAECggICgAAAA==.',Wa='Warbenny:BAAALAAECgcICwAAAA==.',Wi='Wickèr:BAAALAADCggIFwAAAA==.Wieldblade:BAAALAAECgUIBwAAAA==.',Wu='Wunderbar:BAAALAAECgMIBAAAAA==.',Wy='Wyldfire:BAABLAAECoEUAAMPAAcI9hrhDwArAgAPAAcI9hrhDwArAgAcAAYIWw99BwAiAQAAAA==.',Xa='Xanith:BAAALAAECgQIBwAAAA==.',Yo='Yokgagu:BAAALAADCgIIAgAAAA==.',Ys='Ysa:BAAALAAECgcIDQAAAA==.',Za='Zakhin:BAAALAAECgIIAgAAAA==.Zarathul:BAAALAADCggICAAAAA==.',Ze='Zenico:BAAALAADCggICAAAAA==.Zephona:BAAALAAECgMIBAAAAA==.',Zi='Zirael:BAAALAAECgYIDQAAAA==.',Zo='Zombiemahna:BAAALAAECgcIDQAAAA==.',Zu='Zu:BAAALAADCgMIAwABLAADCgYIDQABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end