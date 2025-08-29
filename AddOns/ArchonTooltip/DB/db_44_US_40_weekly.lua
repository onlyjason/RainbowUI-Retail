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
 local lookup = {'Unknown-Unknown','Shaman-Enhancement','Paladin-Protection','Paladin-Retribution','Priest-Holy',}; local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Aberforthd:BAAALAADCggIDwAAAA==.',Ad='Aditu:BAAALAAECgIIAgAAAA==.',Ag='Aggroholic:BAAALAADCgcIBwABLAADCggIDQABAAAAAA==.',Ai='Airent:BAAALAADCggIEwAAAA==.',Al='Alaestel:BAAALAAECgYIDQAAAA==.Aletheia:BAAALAAECgYIDQAAAA==.',An='Angina:BAAALAADCgcIBwAAAA==.Annarcis:BAAALAADCggIFwAAAA==.Anothersham:BAAALAAECgMIBgAAAA==.Antiman:BAAALAAECgEIAQAAAA==.Anäster:BAAALAADCggICAAAAA==.',Ap='Aplcyder:BAAALAAECgYIDQAAAA==.Apocryphea:BAAALAADCgUIBQAAAA==.',Ar='Arabisa:BAAALAAECgIIAQAAAA==.Arachnid:BAAALAAECgYICgAAAA==.Aratyn:BAAALAADCggIDwAAAA==.',As='Assgardian:BAAALAAECgEIAQAAAA==.Asurä:BAAALAADCggIDwAAAA==.',Au='Audwizard:BAAALAAECgMIAwAAAA==.',Ba='Badweather:BAAALAADCggICAAAAA==.Baerrn:BAAALAADCggIDwAAAA==.Baiccan:BAAALAAECgEIAQAAAA==.Baricia:BAAALAADCggIFwAAAA==.Barikgrel:BAAALAADCgMIAwAAAA==.Barix:BAAALAADCgEIAQAAAA==.Barrin:BAAALAADCgcIDgAAAA==.Bastim:BAAALAADCgYIBwAAAA==.Bawnchu:BAAALAADCgYIBwAAAA==.',Be='Beiki:BAAALAAECgEIAQAAAA==.Belthar:BAAALAAECgYIEwAAAA==.Bently:BAAALAAECgYIDQAAAA==.Bentlymage:BAAALAADCggIFQAAAA==.',Bi='Bissafiyah:BAACLAAFFIEFAAICAAMI6SA9AAAyAQACAAMI6SA9AAAyAQAsAAQKgRoAAgIACAgRJUQAAGYDAAIACAgRJUQAAGYDAAAA.',Bl='Blakethyr:BAAALAADCggICwAAAA==.Bloodgon:BAAALAAECgYICwAAAA==.',Bo='Bokkachewa:BAAALAADCggICAAAAA==.Bokue:BAAALAADCgYIBgAAAA==.Bonice:BAAALAADCggICAAAAA==.Boonesfarm:BAAALAADCgYICAAAAA==.Boyakasha:BAAALAADCggIFwAAAA==.',Br='Brewsome:BAAALAAECgYICgAAAA==.Bryycelest:BAAALAAECgMIBAAAAA==.',Bu='Bunnybane:BAAALAAECgEIAQAAAA==.Burny:BAAALAAECgcIDAAAAA==.',Ca='Canadani:BAAALAAECgEIAQAAAA==.Capita:BAAALAAECgMIBQAAAA==.Cariboo:BAAALAADCgYIBgAAAA==.Cassica:BAAALAAECgMIBgAAAA==.Catskin:BAAALAAECgEIAQAAAA==.',Ch='Charkle:BAAALAAECgYICAAAAA==.Chedallig:BAAALAADCgQIBAAAAA==.Chillylilly:BAAALAAECgYICgAAAA==.Chronokai:BAAALAAECgQICAAAAA==.Chummie:BAAALAAECgIIAwAAAA==.',Cr='Crimsondeath:BAAALAADCggIFAAAAA==.',Cu='Cuckenjoyer:BAAALAADCggIFwAAAA==.',Cy='Cyprus:BAAALAAECgMIBAAAAA==.',Da='Daelric:BAAALAADCgcIBwAAAA==.Daender:BAAALAAECgMIBgAAAA==.Darcside:BAAALAADCggIFwAAAA==.Daritar:BAEALAADCggICAAAAA==.Darkfeatherr:BAAALAADCgcIBwAAAA==.Datsombeech:BAAALAAECgMIBAAAAA==.',De='Deathvìxen:BAAALAADCgEIAQAAAA==.Debauch:BAAALAAECgIIAgAAAA==.Demonhunter:BAAALAAECgcIEQAAAA==.Densamin:BAAALAAECgEIAQAAAA==.',Dn='Dna:BAAALAAECgIIBAAAAA==.',Do='Donngaz:BAAALAADCgMIAwAAAA==.',Dr='Dreadgnar:BAAALAADCgEIAQAAAA==.Drminnowphd:BAACLAAFFIEGAAIDAAMI8Rr0AAD/AAADAAMI8Rr0AAD/AAAsAAQKgRkAAgMACAiMI9IBACADAAMACAiMI9IBACADAAAA.Drpiscisphd:BAAALAAECgMIAwAAAA==.Drspoon:BAAALAADCgYIBgAAAA==.Drugpala:BAAALAAECgMIBAAAAA==.Druji:BAAALAADCgcICwAAAA==.',Ds='Dsancho:BAAALAAECgMIBQAAAA==.',Du='Duckey:BAAALAADCggICQAAAA==.Duffuna:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Duffunha:BAAALAAECgYICQAAAA==.',Dy='Dyre:BAAALAADCggIFgAAAA==.Dyslexic:BAAALAAECgUIBgAAAA==.Dyspepsia:BAAALAAECgYIDAAAAA==.',['Dõ']='Dõngus:BAAALAADCgUIBQAAAA==.',El='Elimee:BAAALAAECgcICQAAAA==.Elirria:BAAALAAECgQIBgAAAA==.Ellasia:BAAALAADCggIFwAAAA==.Elric:BAAALAAECgYICQAAAA==.Elvenbane:BAAALAAECgMIBQAAAA==.',Em='Emart:BAAALAAECgEIAQAAAA==.',Er='Erayna:BAAALAAECgYICQAAAA==.Ereillea:BAAALAADCgcIBwAAAA==.',Es='Esquirlo:BAAALAADCgcICQAAAA==.Essence:BAAALAAECgUICwAAAA==.',Eu='Eukoa:BAAALAAECgYICQAAAA==.',Ev='Evelimash:BAAALAAECgYIDAAAAA==.Evepriest:BAAALAAECggICAAAAA==.',Fa='Failee:BAAALAAECgMIBgAAAA==.Falconclaw:BAAALAADCggIGAAAAA==.Falconplume:BAAALAADCggIFQAAAA==.Falcontail:BAAALAADCggIEAAAAA==.Falconwing:BAAALAADCggIEQAAAA==.Falkensnoman:BAAALAAECgEIAQAAAA==.Fayedra:BAAALAADCggICAAAAA==.',Fe='Feenii:BAAALAAECgYICQAAAA==.Fenix:BAAALAAECgYIDQAAAA==.Ferngully:BAAALAADCggICAAAAA==.',Fi='Finni:BAAALAADCgYIBgAAAA==.Fiocubez:BAAALAADCggIDQAAAA==.Fizzlelich:BAAALAADCgEIAQAAAA==.',Fo='Forreal:BAAALAADCgcIBwABLAADCggIDQABAAAAAA==.Fortlum:BAAALAADCgcIDAAAAA==.',Fr='Frozenfard:BAAALAADCgIIAgAAAA==.',Fu='Fufighter:BAAALAADCggICAAAAA==.Fungies:BAAALAAECgYIDQAAAA==.',Ga='Galadriell:BAAALAADCgUIBwAAAA==.Galvis:BAAALAADCgcIBwAAAA==.Gandálfr:BAAALAADCgIIAgAAAA==.Gannir:BAAALAAECgIIAgAAAA==.Garryy:BAAALAADCgQIBAAAAA==.',Ge='Gemswarlock:BAAALAADCggICAAAAA==.',Gh='Ghrak:BAAALAAECgIIAgAAAA==.',Gi='Giantsbanê:BAAALAADCgQIBQAAAA==.Giramar:BAAALAAECgIIAgAAAA==.',Go='Gochujang:BAAALAAECgYIDQAAAA==.Goldeelock:BAAALAADCggIDwAAAA==.Gorduul:BAAALAAECgMIBQAAAA==.Goteem:BAAALAAECgYICQAAAA==.',Gr='Grall:BAAALAADCgEIAQAAAA==.Grandad:BAAALAADCgMIAwAAAA==.Grantaire:BAAALAADCgcIDgAAAA==.Grazen:BAAALAAECgIIAgAAAA==.Grimrox:BAAALAAECgMIAwAAAA==.Grootiam:BAAALAAECgYIDAAAAA==.',Gu='Gulaney:BAAALAADCgUIBQAAAA==.Guzstaff:BAAALAADCgEIAQABLAAECgYICAABAAAAAA==.',Gw='Gwendalyn:BAAALAADCgYIBgAAAA==.',Ha='Hakela:BAAALAAECgEIAQAAAA==.Hardlyevoker:BAAALAAECgQIBAAAAA==.Hawhyy:BAAALAAECgMIAwAAAA==.Haynk:BAAALAADCgEIAQABLAAECgQICAABAAAAAA==.',He='Heavyarm:BAAALAADCggIDgAAAA==.Heilagr:BAAALAADCggIDgAAAA==.Hellzbellz:BAAALAAECgMIBgAAAA==.',Hi='Himawarí:BAAALAADCggIDwAAAA==.',Ho='Holdmyagro:BAAALAAECgMIAwAAAA==.Holemeister:BAAALAAECgYIDgAAAA==.Holihands:BAAALAAECgIIAgAAAA==.Holymann:BAAALAADCggIDgAAAA==.Holyz:BAAALAAECgMIAwAAAA==.',Hu='Hundred:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.',['Hí']='Hílthaen:BAAALAAECgMIBAAAAA==.',Ia='Iago:BAAALAADCggICQAAAA==.',Ib='Ibuprofeno:BAAALAAECgMIAwAAAA==.',Ic='Icebones:BAAALAAECgcICAAAAA==.',Im='Imposed:BAAALAAECgEIAQAAAA==.',In='Incübus:BAAALAAECgQIBAAAAA==.',Io='Iocanepowder:BAAALAAECgYICgAAAA==.',Is='Ishkala:BAAALAAECggIEQAAAA==.Isochron:BAAALAADCgYIDAAAAA==.',It='Itzeal:BAAALAAECgQIBAAAAA==.',Ja='Jarvense:BAAALAAECgIIAgAAAA==.',Je='Jeri:BAAALAAECgIIAgAAAA==.Jessilyn:BAAALAADCgYIBwAAAA==.Jetlui:BAAALAAECgIIAgAAAA==.',Jo='Jorlena:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.',Ju='Juulpod:BAAALAADCggICwABLAAECgYICQABAAAAAA==.',Ka='Kaelei:BAAALAAECgIIAgABLAAECgYICgABAAAAAA==.Kaerei:BAAALAAECgYICgAAAA==.Kaiane:BAAALAADCggICAAAAA==.Kalagrag:BAAALAAECgEIAQAAAA==.Kaleb:BAAALAADCggICAAAAA==.Kalirkaz:BAAALAAECgUIBQABLAAECgYIDAABAAAAAA==.Kallipsa:BAAALAADCggIFwAAAA==.Karasu:BAAALAAECgYICgAAAA==.Karst:BAAALAADCgQIBAABLAAECgYIDQABAAAAAA==.Kaël:BAAALAAECgEIAQAAAA==.',Ke='Kedzilla:BAAALAAECgMIBQAAAA==.Kelaryn:BAAALAADCgQIBAAAAA==.',Ki='Kiemen:BAAALAAECgYIBwAAAA==.Killedtwice:BAAALAAECgEIAQAAAA==.Kirisen:BAAALAAECgIIAgAAAA==.',Ko='Konno:BAAALAADCgcIBwABLAAFFAMIBQACAOkgAA==.',Kr='Krickette:BAAALAADCggICAAAAA==.Krovmar:BAAALAAECgIIAgAAAA==.',Ks='Kspanxx:BAAALAADCgEIAQABLAADCgcIBwABAAAAAA==.',Kt='Kthanksbai:BAAALAADCgYIBgAAAA==.',Ku='Kuraki:BAAALAADCggIDwAAAA==.',Ky='Kyricia:BAAALAADCgQIBAAAAA==.',['Kå']='Kål:BAAALAADCggIDwAAAA==.',La='Ladorek:BAAALAADCgMIAwAAAA==.Lanadiel:BAAALAAECgYICQAAAA==.Lavamancer:BAAALAADCggIDwAAAA==.',Le='Legend:BAAALAAECgQIBwAAAA==.Leotheron:BAAALAAECgMIBAAAAA==.',Lg='Lghtninghunt:BAAALAADCgMIAwAAAA==.',Li='Lian:BAAALAAECgUICgAAAA==.Lichbane:BAAALAAECgYICQAAAA==.Lictoria:BAAALAAECgIIAgAAAA==.Liliara:BAAALAAECgYICwAAAA==.Lillyslight:BAAALAADCgUIBQAAAA==.Lillytae:BAAALAADCggICAAAAA==.Linglang:BAAALAADCgcIDAABLAADCggIDQABAAAAAA==.Linkhunter:BAAALAAECgYICAAAAA==.Linkmage:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Lizardwizard:BAAALAADCgYIBgAAAA==.',Lo='Lodise:BAAALAAECgMIBQAAAA==.Lokusnake:BAAALAAECgYIDQAAAA==.Lollie:BAAALAADCggIDwAAAA==.Lorzz:BAAALAAECgYIDQAAAA==.',Ly='Lylinette:BAAALAAECgMIBQAAAA==.',['Lí']='Lízandor:BAAALAADCgIIAgAAAA==.',Ma='Mageman:BAAALAAECgMIBAAAAA==.Mairisella:BAAALAAECgIIAgAAAA==.Makeawish:BAAALAADCgMIAwAAAA==.Malak:BAAALAADCggICAAAAA==.Manbearhaynk:BAAALAAECgQICAAAAA==.Mandrallea:BAAALAADCgEIAQAAAA==.Maurin:BAAALAAECgIIAgAAAA==.Maximumhonk:BAAALAAECgMIBgAAAA==.Mazikene:BAAALAAECgQIBwAAAA==.',Me='Meissa:BAAALAADCggICgAAAA==.Mekkadaddy:BAAALAADCggIEAAAAA==.Mellow:BAAALAAECgYICQAAAA==.Mendelia:BAAALAAECgIIAgAAAA==.Mercyovrwtch:BAAALAADCgIIAgABLAAECgQIBAABAAAAAA==.Mervenious:BAAALAAECgMIBAAAAA==.Meshaw:BAAALAADCggICAAAAA==.',Mi='Mindplague:BAAALAAECgIIAgAAAA==.Minisicwidit:BAAALAAECgYICQAAAA==.Minrô:BAAALAAECgYICgAAAA==.',Mo='Mogwaï:BAAALAAECgMIBQAAAA==.Moonscale:BAAALAAECgEIAQAAAA==.',Ms='Mskelsier:BAAALAADCgcIDgAAAA==.',Mt='Mtaur:BAAALAAECgYIDQAAAA==.',Mu='Muclor:BAAALAAECgcICQAAAA==.',['Må']='Måzikeen:BAAALAADCgcIBwAAAA==.',Na='Nardena:BAAALAADCgIIAgAAAA==.Narz:BAAALAADCggIDwAAAA==.Nazumi:BAAALAAECgEIAQAAAA==.',Nd='Ndiz:BAAALAADCggIEwAAAA==.',Ne='Neeva:BAAALAADCggIDQAAAA==.',Ni='Nightbreeze:BAAALAADCggICAAAAA==.Nikaido:BAAALAAECgUIBwAAAA==.Nirdail:BAAALAADCgYIBgAAAA==.Nisa:BAAALAADCggICAAAAA==.',Nr='Nros:BAAALAADCggIDAAAAA==.',Nz='Nzoth:BAAALAAECgYICQAAAA==.',['Nä']='Närz:BAAALAAECgYICgAAAA==.',Ok='Okifistz:BAAALAAECgMIBQAAAA==.',Ol='Olgon:BAAALAAECgYICgAAAA==.Olstinkyboot:BAAALAAECgMIBQAAAA==.',On='Onebuttonish:BAAALAADCgcIBwAAAA==.',Oo='Oogachewga:BAAALAAECgEIAQAAAA==.',Op='Opsidian:BAAALAADCgMIAwAAAA==.',Or='Orgodemirr:BAAALAADCggIDwAAAA==.',Os='Oshani:BAAALAAECgIIAgAAAA==.',Pa='Paigor:BAAALAADCgYIBwAAAA==.Pakkswagger:BAAALAADCggIEAAAAA==.Pandemonia:BAAALAAECggICAAAAA==.Parsie:BAAALAAECgIIAgAAAA==.Pathibas:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Patiënce:BAAALAADCgUIBQAAAA==.Pattycakes:BAAALAAECgYICgAAAA==.',Pe='Pella:BAAALAADCgYICwAAAA==.Pencil:BAAALAADCgYICgAAAA==.Pentagram:BAAALAADCggIDwAAAA==.Pewpuji:BAAALAAECgEIAQAAAA==.Pewthree:BAAALAAECgMIAwAAAA==.',Ph='Pherocious:BAAALAAECgYIDAAAAA==.',Pi='Pizzanwings:BAAALAAECgMIBQAAAA==.',Po='Pokitz:BAAALAAECgEIAQAAAA==.',Pr='Primordinor:BAAALAAECgMIBQAAAA==.',Ra='Raikai:BAAALAADCggICAABLAAECgYICgABAAAAAA==.Rakan:BAAALAAECgYIDQAAAA==.Rallick:BAAALAAECgYIDQAAAA==.Ranì:BAAALAAECgYICQAAAA==.Rathger:BAAALAAECgYIBwAAAA==.',Re='Reallyded:BAAALAADCgUIBwAAAA==.Rellekdk:BAAALAAECgEIAQAAAA==.Relwof:BAAALAAECgMIBQAAAA==.Rendwee:BAAALAAECgYICAAAAA==.Reps:BAAALAADCgcIBwAAAA==.',Rh='Rhatchet:BAAALAAECgIIAgABLAAECgYICwABAAAAAA==.',Ri='Riccflairr:BAAALAAECgMIBQAAAA==.Rimuru:BAEALAAECgIIAgAAAA==.',Ro='Rock:BAAALAADCgEIAQAAAA==.Rocklockstar:BAAALAADCgQIBAAAAA==.Rodcet:BAAALAAECgYIDgAAAA==.Roflbubble:BAAALAAECgMIBAAAAA==.Rognan:BAAALAADCgQIBgAAAA==.Roku:BAAALAADCgYIBgAAAA==.Rookgue:BAAALAAECgYICgAAAA==.Rookoker:BAAALAAECgYIDgAAAA==.Roothion:BAAALAADCgMIAwAAAA==.Rosa:BAAALAADCggIDAAAAA==.Rosewynde:BAAALAADCgcIBwAAAA==.',Sa='Sabo:BAAALAAECgIIAgAAAA==.Sack:BAAALAADCgIIAgAAAA==.Saelara:BAAALAAECgMIBwAAAA==.Samgee:BAABLAAECoEZAAIEAAgIHyJmCgDYAgAEAAgIHyJmCgDYAgAAAA==.Sancdruary:BAEALAAECgMIBgAAAA==.Sandlit:BAAALAAECgYICQAAAA==.Sandormu:BAAALAADCgIIAgABLAAECgMIBQABAAAAAA==.Sarip:BAAALAADCgMIAwAAAA==.',Sc='Scattered:BAAALAAECgMIAwAAAA==.Schecter:BAAALAAECgcIEgAAAA==.Scooter:BAAALAAECgEIAQAAAA==.',Se='Selesne:BAAALAADCggIDwAAAA==.Seriana:BAAALAAECgMIAwAAAA==.Serral:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.Seràphina:BAAALAADCggIDwAAAA==.',Sh='Shaggmz:BAAALAADCggIFwAAAA==.Shatterstone:BAAALAAECgMIBQAAAA==.Shinma:BAAALAADCggIFwAAAA==.Shoushin:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Shymary:BAAALAADCggIFwAAAA==.',Si='Siete:BAAALAAECgYIDwABLAAECgcICAABAAAAAA==.Silëx:BAAALAAECgIIAgAAAA==.',Sk='Skirtoo:BAAALAADCgIIAgAAAA==.Skyrah:BAAALAAECgQIBQAAAA==.',Sl='Slappysocks:BAAALAAECgcIDQAAAA==.',Sm='Smallmike:BAAALAADCgQIBAAAAA==.',Sn='Snowkim:BAAALAAECgIIAgAAAA==.Snuzzle:BAAALAAECgEIAgAAAA==.',So='Sorvahr:BAEALAADCggICgAAAA==.Soullessboom:BAAALAAECgQIBgAAAA==.',Sp='Spacebongos:BAAALAAECgMIBQAAAA==.',Sq='Squibbles:BAAALAAECgYICQAAAA==.',Sr='Srasjet:BAAALAAECgEIAQAAAA==.',St='Stabytha:BAAALAADCggIDwAAAA==.Starlight:BAAALAAECgYIDAAAAA==.Stars:BAAALAAECgIIAgAAAA==.Stealthed:BAAALAAECggICAAAAA==.Stormcall:BAAALAADCgcIBwAAAA==.',Su='Sukul:BAAALAAECgcIDAAAAA==.Sunderpants:BAAALAADCgQIBAAAAA==.Sunnarah:BAAALAADCggIEgAAAA==.Supersoaker:BAAALAAFFAIIBAAAAA==.',['Sá']='Sáëgárón:BAAALAAECgEIAQAAAA==.',Ta='Taliden:BAAALAADCgcIBwAAAA==.Taraylda:BAAALAAECgMIBQAAAA==.',Te='Temla:BAAALAAECgYICQAAAA==.Tenchin:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.Tenga:BAAALAAECgIIAgAAAA==.Terroza:BAAALAAECgMIAwAAAA==.',Th='Thalsandris:BAAALAADCgYIBgAAAA==.Thartilidan:BAAALAAECgMIBQAAAA==.Theavan:BAAALAADCgEIAQAAAA==.Theokoles:BAAALAADCgUIBQABLAADCgUIBQABAAAAAA==.Thepaladin:BAAALAAECgEIAQAAAA==.Thiccboii:BAAALAADCggIGQAAAA==.Thorly:BAAALAAECgMIAwAAAA==.',To='Toospookie:BAAALAADCgcIDgAAAA==.',Tr='Tramplip:BAAALAAECgMIBAAAAA==.Treecloud:BAAALAAECgYICQAAAA==.Trevian:BAAALAADCggIDwAAAA==.Trigore:BAAALAAECgEIAQAAAA==.',Tu='Tuesday:BAAALAADCgcIDgAAAA==.Tuluxxi:BAAALAAECgYICQAAAA==.Turbokinetic:BAAALAADCgcIDgAAAA==.',Tw='Tweetty:BAAALAADCgIIAgAAAA==.Twostrikes:BAAALAADCgcIDgAAAA==.',Ty='Tyg:BAABLAAFFIEFAAIFAAMIURWxAgAMAQAFAAMIURWxAgAMAQAAAA==.',Ug='Uglyforge:BAAALAADCggIDwAAAA==.',Uj='Ujimas:BAAALAAECgIIAgAAAA==.',Up='Uprisin:BAAALAADCggIBwABLAAECggICAABAAAAAA==.',Va='Valemon:BAAALAADCgEIAQAAAA==.Vampireshade:BAAALAAECgMIBAAAAA==.Vanimao:BAAALAAECgYICQAAAA==.Vankman:BAAALAAECgMIAwAAAA==.',Vb='Vbull:BAAALAAECgYICQAAAA==.',Ve='Vega:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Velinth:BAAALAAECgMIBQAAAA==.Velissari:BAAALAADCggIDwAAAA==.Velouria:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Venatra:BAAALAADCgIIAgAAAA==.',Vi='Victory:BAAALAAECgMIBQAAAA==.Vindict:BAAALAADCgQIBAAAAA==.Violette:BAAALAAECgMIBQAAAA==.Vion:BAAALAADCgMIAwAAAA==.',Vo='Voidlink:BAAALAAECgEIAQABLAAECgYICAABAAAAAA==.Vorius:BAAALAADCgUIBQAAAA==.',Vy='Vynlan:BAAALAAECgIIAgABLAAECgYICgABAAAAAA==.',Wa='Wakaekwondo:BAAALAAECgMIAwAAAA==.Wap:BAAALAADCgIIAgAAAA==.Warolderoy:BAAALAAECgYICQAAAA==.',We='Weedshaman:BAAALAAECgMIAwAAAA==.Weil:BAAALAADCggICAAAAA==.',Wh='Whytlightnin:BAAALAADCgUIBQAAAA==.',Wi='Winslo:BAAALAAECgMIBwAAAA==.',Wl='Wldeagle:BAAALAADCgcICgAAAA==.',Wo='Woker:BAAALAADCgQICAABLAAECgYICQABAAAAAA==.',Wr='Wrenegade:BAAALAADCggIFQAAAA==.',['Wì']='Wìndrûnner:BAAALAADCgcIBwAAAA==.',Xa='Xader:BAAALAAECgEIAgAAAA==.',Xe='Xenna:BAAALAADCggIFwAAAA==.Xeq:BAAALAADCgcICwAAAA==.',Xi='Xiata:BAAALAAECgIIAgAAAA==.',Ya='Yaboitom:BAAALAADCgQIBAAAAA==.',Ye='Yeoman:BAAALAAECgIIAgAAAA==.Yesindra:BAAALAADCgMIAwAAAA==.',Yg='Yggdralith:BAAALAAECgMIBgAAAQ==.',Yu='Yunohealme:BAAALAAECgMIBQAAAA==.Yunosmart:BAAALAADCgQIBAAAAA==.',Za='Zaen:BAAALAAECgYIDQAAAA==.Zagreus:BAAALAAECgIIAgAAAA==.Zakkah:BAAALAAECggIDwAAAA==.Zanuu:BAAALAADCgcIBwAAAA==.Zané:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.Zarkir:BAAALAAECgYIDQAAAA==.Zayiruan:BAAALAADCgEIAQAAAA==.',Ze='Zelily:BAAALAAECgMIBAAAAA==.Zenarri:BAAALAADCgUIBQAAAA==.Zepha:BAAALAAECgMIBQAAAA==.',Zh='Zharvakko:BAAALAAECgYIDAAAAA==.',Zl='Zlydormi:BAAALAAECgMIBQAAAA==.',Zu='Zulrich:BAABLAAECoEVAAIFAAcIGhfVFgD0AQAFAAcIGhfVFgD0AQAAAA==.',['Zü']='Zülim:BAAALAAECgMIAwAAAA==.',['Ëu']='Ëuni:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end