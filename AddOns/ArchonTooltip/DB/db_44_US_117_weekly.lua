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
 local lookup = {'Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Rogue-Subtlety','Druid-Balance','Hunter-BeastMastery','Druid-Restoration',}; local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abrupt:BAAALAAECggICAAAAA==.',Ad='Adielia:BAAALAAECgMIBAAAAA==.',Ag='Agiermodinn:BAAALAADCggIAgAAAA==.',Ai='Aia:BAAALAADCgcIDAAAAA==.',Aj='Ajudrah:BAAALAAECgMIAwAAAA==.',Al='Alcahawlick:BAAALAADCggIDwAAAA==.Alexious:BAAALAAECgYICQAAAA==.Allasta:BAAALAAECgEIAQAAAA==.Alopix:BAAALAAECgMIAwAAAA==.Alothos:BAAALAAECgEIAQAAAA==.',An='Anqi:BAAALAADCgYIBgAAAA==.Ansatz:BAAALAADCgcIBgAAAA==.',Ap='Apokalypto:BAAALAAECgIIAgAAAA==.',Aq='Aquaholic:BAAALAAECgEIAQAAAA==.',Ar='Araspeth:BAAALAAECggIAwAAAA==.Arknee:BAAALAADCgEIAQAAAA==.Arnolt:BAAALAADCgUIBQAAAA==.Arîse:BAAALAAECgIIAgAAAA==.',As='Asootlo:BAAALAAECggIAQAAAA==.Assphyxiate:BAAALAAECgYICwAAAA==.Astaaria:BAAALAADCgMIAwAAAA==.Asteriia:BAAALAAECgIIAgAAAA==.',At='Atradiez:BAAALAADCgUIBQAAAA==.',Au='Aubrin:BAAALAADCgMIAwAAAA==.Augustino:BAAALAADCgQIBAAAAA==.Aunliu:BAAALAADCgYIBgAAAA==.Aurene:BAAALAADCgUIBQAAAA==.Auroris:BAAALAAECgMIAwAAAA==.',Ax='Axi:BAAALAADCggICAAAAA==.',Az='Azaria:BAAALAAECgIIAgAAAA==.Azka:BAAALAAECgIIAgAAAA==.Azkadk:BAAALAADCgcIBwAAAA==.Azkamage:BAAALAADCgcIBwAAAA==.',Ba='Baddieelf:BAAALAADCggIAQAAAA==.Badmoon:BAAALAAECgEIAQAAAA==.Bamfpally:BAAALAADCgEIAQAAAA==.Bamfpriest:BAAALAADCgcICAAAAA==.Bast:BAAALAAECgcIDwAAAA==.Bayn:BAAALAADCggICwAAAA==.',Be='Benif:BAAALAAECgYICQAAAA==.Bertorod:BAAALAAECgMIAwAAAA==.',Bl='Bloodark:BAAALAADCggIDwAAAA==.Bloodstoned:BAAALAADCgcICgAAAA==.Bluepally:BAAALAADCgYIBgAAAA==.Blxckcattv:BAAALAADCgEIAQAAAA==.',Br='Brauck:BAAALAAECgYICQAAAA==.Braugorl:BAAALAADCgYIBgABLAAECggIFgABAH0gAA==.Braugorlle:BAAALAAECgEIAQAAAA==.Brixlo:BAAALAAECgYICgAAAA==.Brokenface:BAAALAAECgEIAQAAAA==.Brokkenn:BAAALAADCgUICgAAAA==.',Bu='Burp:BAABLAAECoEfAAMCAAgI3yMWBQAYAgACAAcIZyEWBQAYAgADAAYI6RtWGQDsAQAAAA==.',Ca='Callipyge:BAAALAADCggICAAAAA==.',Ce='Cedrill:BAACLAAFFIEFAAIEAAMI9hzFAAASAQAEAAMI9hzFAAASAQAsAAQKgRYAAgQACAiRJEsBAD8DAAQACAiRJEsBAD8DAAAA.',Ch='Chalada:BAAALAADCgMIAwAAAA==.Chalastorm:BAABLAAECoEUAAMFAAYIfCJjGwDbAQAFAAUI3iFjGwDbAQAGAAYIhwqsLQA9AQAAAA==.Chatnoir:BAAALAAECgMIBgAAAA==.Chronormu:BAAALAADCgYICwAAAA==.Chulu:BAAALAADCgMIAwAAAA==.Chunklleria:BAAALAAECgEIAQABLAAECgEIAQAHAAAAAA==.',Ci='Cirrak:BAAALAADCgUIBQAAAA==.',Cl='Claerity:BAAALAADCggIEAAAAA==.Clonetastic:BAAALAAECgIIAgAAAA==.',Co='Cokiess:BAAALAADCgEIAQAAAA==.Corklaw:BAABLAAECoEXAAIDAAgIJRxADACIAgADAAgIJRxADACIAgAAAA==.Courist:BAAALAAECgcIDgAAAA==.',Cp='Cptcrunch:BAAALAADCgYIBgAAAA==.',Cr='Crassius:BAAALAAECgEIAQAAAA==.Creditcheck:BAAALAADCgcIBwAAAA==.Cryptkeeperr:BAAALAADCgMIAwAAAA==.',Ct='Ctrlaltd:BAAALAAFFAIIAgAAAA==.Ctrlffive:BAAALAAECgYIBgAAAA==.',Da='Daddywarbuck:BAAALAADCgcIDQAAAA==.Darkzula:BAAALAAECgYIDAAAAA==.',De='Deadmarks:BAAALAADCgcICgAAAA==.Delrith:BAAALAAECgEIAQAAAA==.Demonlizzy:BAAALAAECgcIEgAAAA==.Depose:BAAALAADCgIIAgAAAA==.Derrewyn:BAAALAAECgIIBgAAAA==.Devildj:BAAALAAECgMIAwAAAA==.Devinerage:BAAALAADCgcICwAAAA==.Dezwrath:BAAALAADCgcICQAAAA==.',Di='Diezzel:BAAALAADCggICAAAAA==.',Do='Docken:BAAALAADCgcICwAAAA==.Docwho:BAAALAAECgIIAgAAAA==.Doomguyy:BAAALAADCgYIBgAAAA==.',Dr='Drkwing:BAAALAAECggICAAAAA==.',Du='Dumag:BAAALAAECgYIDQAAAA==.Dustdruid:BAAALAAECgcIEQAAAA==.',['Dà']='Dànktànk:BAAALAADCgEIAQAAAA==.',El='Ellcrys:BAAALAAECgUICwAAAA==.',Em='Emillie:BAAALAAECgIIAgAAAA==.',En='Enombe:BAAALAAECgIIAgAAAA==.Enttäuschung:BAAALAADCggICgAAAA==.',Er='Erisian:BAAALAADCgYIBwAAAA==.Erza:BAAALAADCgcICwAAAA==.',Es='Escanør:BAAALAADCggICQAAAA==.',Ev='Evengelist:BAAALAAECgMIAwABLAAECgYICQAHAAAAAA==.',Fa='Falin:BAAALAADCgcIBwAAAA==.Fall:BAAALAADCgcIBwAAAA==.Faqueueeight:BAAALAAECgYIBgAAAA==.Faqueuefive:BAAALAAFFAIIAgAAAA==.Faqueuetoo:BAAALAADCgYIBgABLAAFFAIIAgAHAAAAAA==.Fatsloth:BAAALAADCggIEAAAAA==.',Fe='Fearspammer:BAAALAADCgIIAwAAAA==.Felíx:BAAALAADCgQIBAAAAA==.',Fh='Fhenris:BAAALAAECgQIBgAAAA==.',Fi='Fimtastic:BAAALAAECgcIDQAAAA==.Finasy:BAAALAAECgIIAgAAAA==.Finbezy:BAAALAADCggIBQAAAA==.Fincain:BAAALAADCggICAAAAA==.Fistymisty:BAAALAAECgQICAAAAA==.Fizik:BAAALAADCggICAAAAA==.',Fl='Fleecejohnsn:BAAALAADCggICAAAAA==.',Fo='Foriest:BAAALAADCgcIBwAAAA==.Fortyouncee:BAAALAADCgQIBAAAAA==.Foxkit:BAAALAAECgIIAgAAAA==.',Fu='Furearia:BAAALAADCgQIBwAAAA==.Furrybowner:BAAALAADCgcIBwAAAA==.Fuzzychunks:BAAALAAECgEIAQAAAA==.',Fy='Fynenewa:BAAALAAECgYICgAAAA==.',Ga='Galaz:BAAALAAECgQICgAAAA==.Gallethline:BAAALAADCgcIEQAAAA==.',Ge='Gekoni:BAAALAAECgMICQAAAA==.Gemelli:BAAALAAECgYICQAAAA==.',Gl='Gloomshak:BAAALAADCgIIAgAAAA==.',Go='Gohma:BAAALAADCgcICgAAAA==.',Gr='Grimmjöw:BAABLAAECoEUAAIIAAcI4B+jAgBzAgAIAAcI4B+jAgBzAgAAAA==.Grullander:BAAALAAECgUICQAAAA==.',Gu='Guiguiie:BAAALAADCggICAAAAA==.Gulan:BAAALAADCggICwAAAA==.',Ha='Hantegord:BAAALAADCgcIBwAAAA==.Hardwood:BAAALAADCgEIAQAAAA==.Havetotossme:BAAALAAECgEIAQAAAA==.',He='Healuid:BAAALAAECgMIBAAAAA==.Herkharu:BAAALAAECgIIAgAAAA==.',Ho='Honeypack:BAAALAADCgMIAwAAAA==.Hoother:BAABLAAECoEVAAIJAAgIvh2RBwDAAgAJAAgIvh2RBwDAAgAAAA==.',Hu='Hunia:BAAALAAECgEIAgAAAA==.Hunterhodge:BAAALAADCggIDgAAAA==.',Ic='Iceepriest:BAAALAADCgcIBwAAAA==.Iceeshot:BAABLAAECoEVAAIKAAcIriRiCADbAgAKAAcIriRiCADbAgAAAA==.',Id='Idruid:BAAALAAECgIIAwAAAA==.',If='Ifightdikes:BAABLAAECoEWAAIFAAgIrB7WBgCfAgAFAAgIrB7WBgCfAgAAAA==.',Il='Illidarilord:BAAALAADCggIDAAAAA==.',Im='Imu:BAAALAADCgQIBAAAAA==.',Ir='Iraa:BAAALAAECgcIDQAAAA==.Irric:BAAALAADCgYIBgAAAA==.',Is='Isback:BAAALAADCgYIBgAAAA==.Isfet:BAAALAADCgcICQAAAA==.',Iv='Ivantis:BAAALAAECgMIBgAAAA==.Ivieenfuego:BAAALAAECgUICAAAAA==.',Ja='Jadednurse:BAAALAAECgMIBAAAAA==.Jaidentg:BAAALAADCgYIBgAAAA==.Jaiydiean:BAAALAADCgcIDAAAAA==.Janjor:BAAALAAECgMIBgAAAA==.Janjorski:BAAALAADCggIDwAAAA==.',Je='Jeffbeck:BAAALAADCgUIBQAAAA==.',Jo='Joclaymo:BAAALAADCgcICAAAAA==.Jontxu:BAAALAAECgIIAgAAAA==.Joyina:BAAALAADCgcIBwAAAA==.',Jt='Jteampaly:BAAALAADCgIIAgAAAA==.',Ka='Kaddar:BAAALAADCgUIBwAAAA==.Kadinsky:BAAALAAECgMIBAAAAA==.Kaelvorn:BAAALAAECgEIAQAAAA==.Kandeh:BAAALAADCgYIDgAAAA==.Karlldun:BAAALAAECgMIBAAAAA==.Kasmir:BAAALAADCgcIBwAAAA==.Katelynn:BAAALAAECgcICwAAAA==.Katira:BAAALAADCgUICgAAAA==.Katrina:BAAALAAECgMIBAAAAA==.',Ke='Kelink:BAAALAADCggICAAAAA==.Kelisii:BAAALAAECggICwAAAA==.',Kf='Kfoy:BAAALAADCgQIBQAAAA==.',Kh='Khogent:BAAALAAECgYICQAAAA==.Khronik:BAAALAAECgMIAwAAAA==.Khyle:BAAALAAECgEIAQAAAA==.',Ki='Kitheros:BAAALAADCgUIBwAAAA==.',Kl='Klauszhou:BAAALAAECgEIAQAAAA==.',Km='Kmarti:BAAALAAECgYIDAAAAA==.',Kn='Kna:BAAALAADCgQIBAAAAA==.Knah:BAAALAADCgcIDgAAAA==.Knas:BAAALAADCgcIBwAAAA==.Kneesntoes:BAAALAADCgUIBQAAAA==.Knuckifubuck:BAAALAADCggIEAAAAA==.',Ko='Kodeshand:BAAALAAECgEIAQAAAA==.Konalari:BAAALAADCgQIBgAAAA==.Konarande:BAAALAADCggIEwAAAA==.Koreanese:BAAALAAECgEIAQAAAA==.Kosmic:BAAALAADCggIFAAAAA==.',Kr='Kronick:BAAALAADCgcICAAAAA==.Kréäp:BAAALAAECgEIAQAAAA==.',Ky='Kynaragon:BAAALAAFFAMIAgAAAA==.',La='Lammoth:BAAALAADCgIIAgAAAA==.Landrella:BAAALAADCgEIAQAAAA==.Lasthope:BAAALAADCggICQAAAA==.',Le='Leafu:BAAALAADCggIEwABLAAECgMIAwAHAAAAAA==.Leasin:BAAALAAECgMIAwAAAA==.Lekänik:BAAALAAECgYICwAAAA==.Leonax:BAAALAADCgMIAwAAAA==.',Li='Lighthusk:BAAALAAECgMIAwAAAA==.Lilibejeane:BAAALAADCgYICAABLAAECgMIBAAHAAAAAA==.Lilsquirtboy:BAAALAAECgUICAAAAA==.Linithara:BAAALAADCgUIBQABLAAECgcIBwAHAAAAAA==.Liralinara:BAABLAAECoFKAAILAAgImSYsAAB9AwALAAgImSYsAAB9AwABLAAFFAMIAgAHAAAAAA==.',Lo='Lockersz:BAAALAAECgIIAgAAAA==.Lookatmyhorn:BAAALAAECggICAAAAA==.',Ls='Lsali:BAAALAADCgEIAgAAAA==.',Lu='Lucthedk:BAAALAADCgEIAQAAAA==.Lukis:BAAALAADCgQIBQAAAA==.Lunarpally:BAAALAAECgMIAwAAAA==.',Ly='Lyio:BAAALAAECgYICAAAAA==.',Ma='Madhoof:BAAALAADCgEIAQAAAA==.Madmanpally:BAAALAADCgYIBQAAAA==.Madviridian:BAAALAADCgMIAwAAAA==.Malvean:BAAALAADCgUIBgAAAA==.Marx:BAAALAADCggIEQAAAA==.Mathinis:BAAALAADCgUICQAAAA==.Matokar:BAAALAADCgcIBwAAAA==.',Me='Melloetta:BAAALAADCggICAAAAA==.Melodras:BAAALAAECgMIAwAAAA==.Memis:BAAALAADCgcIDAAAAA==.',Mi='Midorya:BAAALAADCgcIBwAAAA==.Miluk:BAAALAADCggIDgAAAA==.Mindfull:BAAALAADCgYIBgAAAA==.Misconduct:BAAALAADCggIDwAAAA==.',Mo='Moobiwan:BAAALAADCgcICAAAAA==.Moociffer:BAAALAADCggIFgAAAA==.Moolefficent:BAAALAAECgYICQABLAADCgEIAQAHAAAAAA==.',Mt='Mtadidit:BAAALAADCggICAAAAA==.',Mu='Mushrambo:BAAALAAECgQIBgAAAA==.',My='Mystiicmoo:BAAALAADCgEIAQAAAA==.',['Mé']='Mérika:BAAALAAECgcIBwAAAA==.',Na='Nainportekan:BAAALAADCgYIBgAAAA==.',Ni='Nightscar:BAAALAADCgYIBgAAAA==.',No='Nobudeg:BAAALAADCgIIAgAAAA==.Nogare:BAAALAADCggIEQAAAA==.Noktis:BAAALAAECgcIBwAAAA==.Noracabbage:BAAALAADCggIDwAAAA==.',['Nà']='Nàstasha:BAAALAADCgcIBgABLAAECgcICwAHAAAAAA==.',Or='Orchaze:BAAALAAECgQICAAAAA==.',Os='Osla:BAAALAAECgMIAwAAAA==.',Pa='Paapineau:BAAALAADCggIDwAAAA==.Packes:BAAALAADCgEIAQABLAAECgYICQAHAAAAAA==.Pakkohruun:BAAALAAECgYICwAAAA==.Papapoison:BAAALAADCgUIBQAAAA==.',Pe='Penellaphe:BAAALAADCggIDgAAAA==.Pepperjk:BAAALAADCgUIBwAAAA==.Peppersolis:BAAALAAECgIIAgAAAA==.',Ph='Phillyblunt:BAABLAAECoEUAAIFAAYIABXeKwByAQAFAAYIABXeKwByAQAAAA==.Photoresist:BAAALAAECgEIAQAAAA==.',Pi='Piyo:BAAALAAECgYICQAAAA==.',Po='Poky:BAAALAAECgMIBgAAAA==.Poolius:BAAALAADCgcIDAAAAA==.Poptartits:BAAALAADCgcIBwAAAA==.',Pr='Praedor:BAAALAAECgIIAgAAAA==.Pridemoore:BAAALAAECgEIAQAAAA==.Priesty:BAAALAADCgcICAAAAA==.Prisley:BAAALAAECgYICQAAAA==.Prêdøßêâr:BAAALAAECggICAAAAA==.',Pu='Puppi:BAAALAADCggIEAAAAA==.',Pz='Pz:BAAALAADCggICQAAAA==.',Ra='Rain:BAAALAADCgIIAgAAAA==.Rainblood:BAAALAADCgUIBQAAAA==.Rampagarex:BAAALAADCgYIBgAAAA==.Raptorizer:BAAALAADCgEIAQABLAADCggICAAHAAAAAA==.Razormolly:BAAALAAECgQIBgAAAA==.',Re='Reversi:BAAALAADCggIFAAAAQ==.',Rg='Rgent:BAAALAADCgYICwABLAAECgEIAQAHAAAAAA==.',Rh='Rhenin:BAAALAADCggICgAAAA==.',Ri='Richardluis:BAAALAADCggIGQAAAA==.Rick:BAAALAADCgIIAgAAAA==.Rivër:BAAALAAECgYIBgAAAA==.',Ro='Robbell:BAAALAAECgEIAQAAAA==.Roblbell:BAAALAADCgMIAwAAAA==.Roselynn:BAAALAADCggIEwAAAA==.',Ru='Ruerl:BAAALAADCggIDAAAAA==.Rungin:BAAALAADCgcIBwAAAA==.Ruushjr:BAAALAADCgcICAAAAA==.',Sa='Saiki:BAAALAADCgEIAQAAAA==.Saj:BAAALAADCggIBwAAAA==.Salocin:BAAALAADCgYIBgAAAA==.Sathenset:BAABLAAECoEWAAIBAAgIfSBQBgDQAgABAAgIfSBQBgDQAgAAAA==.',Sc='Scandium:BAAALAAECgYICQAAAA==.Scission:BAAALAADCggICAAAAA==.Screams:BAAALAADCggIEAAAAA==.Scrembiblion:BAAALAAECgMIAwAAAA==.',Se='Sebastianmc:BAAALAADCggIDgAAAA==.Seperael:BAAALAADCggICAABLAAECgYIDwAHAAAAAA==.Sepulchrè:BAAALAAECgYIDwAAAA==.',Sh='Shadeyheals:BAAALAADCggIBwAAAA==.Shadówzzxz:BAAALAADCgMIAwAAAA==.Shaladar:BAAALAADCgMIAwAAAA==.Shamwowwz:BAAALAADCgEIAQAAAA==.Shelandria:BAAALAADCgUIBgAAAA==.Shhmokin:BAAALAADCggIEQAAAA==.Shiftmypants:BAAALAADCgQIBwAAAA==.Shizukuu:BAAALAADCgMIAgAAAA==.Shnipishnap:BAABLAAECoE3AAIFAAgIqiYbAACLAwAFAAgIqiYbAACLAwAAAA==.Shãdøwzzxz:BAAALAADCgYIBgAAAA==.',Sk='Skädoosh:BAAALAAECgIIAgAAAA==.',Sl='Slapshappy:BAAALAAECgEIAQAAAA==.Slippednip:BAAALAAECgUICQAAAA==.Slowdown:BAAALAADCggIDgAAAA==.',Sm='Smoaky:BAAALAADCgQIBAAAAA==.Smokeyhaze:BAAALAADCgYIBgAAAA==.Smokin:BAAALAAECgIIBQAAAA==.',Sn='Snowdrift:BAAALAAECgYIBgAAAA==.',So='Solomus:BAAALAADCgYICgAAAA==.Soontofu:BAAALAADCggICAAAAA==.',Sp='Spaceballz:BAAALAAECgMIBQABLAAECggIFgAFAKweAA==.Sparke:BAAALAADCgIIAgAAAA==.Sporktheorc:BAAALAAECggICAAAAA==.',St='Stamuerte:BAAALAADCgcIBwAAAA==.Staranaria:BAAALAADCgIIAgAAAA==.Stool:BAAALAADCggICAAAAA==.Stormroid:BAAALAADCggICgAAAA==.Stormynuts:BAAALAADCggIDwAAAA==.Strangulate:BAAALAADCgYIBgAAAA==.',Su='Sulliihunts:BAAALAAECgcIDQAAAA==.Sunmx:BAAALAAECgYICgAAAA==.Surewould:BAAALAAECggIDQAAAA==.',Sw='Swurves:BAAALAADCgYIDAAAAA==.',['Sã']='Sãvãge:BAAALAADCgcIBwAAAA==.',['Sê']='Sêlene:BAAALAADCgYIBgAAAA==.',Ta='Talegos:BAAALAAECgIIAwAAAA==.Talonstryke:BAAALAAECgcIDQAAAA==.Tanthedra:BAAALAADCgQIBAAAAA==.Tarindria:BAAALAADCgEIAQAAAA==.',Te='Teatoh:BAAALAADCgYIBgABLAAECggIEgAHAAAAAA==.Teethgnasha:BAAALAADCgIIAgAAAA==.Terranis:BAAALAADCgYIDQABLAAECgEIAQAHAAAAAA==.Terrokar:BAAALAAECgIIAwAAAA==.Tevelah:BAAALAAECgMIBAAAAA==.Tevers:BAAALAADCgcIBwAAAA==.',Th='Thalior:BAAALAADCgEIAQAAAA==.Thebadtouch:BAAALAAECgEIAQAAAA==.Thorfinn:BAAALAAECgYICQAAAA==.Thqp:BAAALAADCgcIBwAAAA==.',Ti='Tiamät:BAAALAAECgEIAQAAAA==.Tibbzz:BAAALAADCggIEAAAAA==.Titancocke:BAAALAADCggIDwAAAA==.Titø:BAAALAAECggIEgAAAA==.',To='Tourmalynne:BAAALAAECgYIDQAAAA==.',Tr='Tragicpants:BAAALAADCgYIBgAAAA==.Treadgy:BAAALAADCgUIBQAAAA==.Tristanias:BAAALAAECggIBgAAAA==.Trollsson:BAAALAADCgIIAgAAAA==.Trunch:BAAALAADCgcICAAAAA==.',Tu='Tuna:BAAALAAECgcIDgAAAA==.',Tv='Tvak:BAAALAAECgEIAQAAAA==.',Tw='Twopump:BAAALAAECgUICAAAAA==.',['Tó']='Tónka:BAAALAAECgMIAwABLAAECgYICgAHAAAAAA==.',Uw='Uwish:BAAALAADCgQIBAAAAA==.',Va='Vainqueur:BAAALAADCgQIBQAAAA==.Valerie:BAAALAAECgYIDQAAAA==.Vandersus:BAAALAAECgIIAgAAAA==.Vat:BAAALAADCgMIAwAAAA==.Vazed:BAAALAADCgcIDAAAAA==.',Ve='Veigar:BAAALAADCggIDwAAAA==.Velion:BAAALAADCggICAAAAA==.Velithril:BAAALAADCgEIAQAAAA==.',Vg='Vgx:BAAALAAECgMIBAAAAA==.',Vh='Vhela:BAAALAADCgYIEAAAAA==.',Vi='Videmo:BAAALAADCgQIBgAAAA==.',Vu='Vulkan:BAAALAADCgIIAgAAAA==.',Vy='Vyo:BAAALAADCgcIBwABLAAECggIFgAFAKweAA==.',Wa='Waidmanns:BAAALAAECgcIEQAAAA==.Wangp:BAAALAAECgMIAwAAAA==.',Wh='Wheramii:BAAALAAECggICQAAAA==.Whoangry:BAAALAADCgcICQAAAA==.',Wi='Wickedchick:BAAALAADCgcICwAAAA==.',Xa='Xans:BAAALAADCgYICgAAAA==.',Xr='Xrythan:BAAALAADCgIIAgAAAA==.',Ya='Yakhuangii:BAAALAADCgIIAgAAAA==.Yamihunter:BAAALAADCgcIBwAAAA==.',Ye='Yemier:BAAALAADCgYIDwAAAA==.Yequi:BAAALAADCgUIBgAAAA==.',Yo='Yoggitha:BAAALAAECgMIBwAAAA==.Yogsothoth:BAEBLAAECoEYAAIKAAgIChqUDgCAAgAKAAgIChqUDgCAAgAAAA==.Yomaku:BAAALAADCgcIBwAAAA==.',Yu='Yukihira:BAAALAAECgYIBgAAAA==.',Za='Zaartyn:BAAALAAECgYIDgAAAA==.Zafiro:BAAALAAECgIIAgAAAA==.',Ze='Zeebeth:BAAALAAECgMIAwAAAA==.Zelos:BAAALAADCgMIAwAAAA==.Zerokai:BAAALAAECgYIBgAAAA==.Zestclaw:BAAALAADCgUIBQAAAA==.',Zo='Zombieaids:BAAALAADCggIEgAAAA==.',Zt='Ztormcaller:BAAALAADCgYIBgAAAA==.',Zu='Zulyas:BAAALAAECgYIAgAAAA==.',Zy='Zyfpaa:BAAALAAECgcIDAAAAA==.',['ßl']='ßlâckßêâr:BAAALAAECggICAAAAA==.',['ßu']='ßuzzibee:BAAALAADCgYIBgABLAADCggIDwAHAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end