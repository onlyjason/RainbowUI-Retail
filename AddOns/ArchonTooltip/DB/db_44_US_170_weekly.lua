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
 local lookup = {'Unknown-Unknown','Paladin-Protection','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','Druid-Restoration',}; local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abrácadabra:BAAALAAECgIIAgABLAAECgMIBAABAAAAAA==.',Ac='Acherind:BAAALAADCgcIBwAAAA==.Achilles:BAABLAAECoEXAAICAAgIAR1WBQBhAgACAAgIAR1WBQBhAgAAAA==.Acinorev:BAAALAADCggIEwAAAA==.',Ad='Ademin:BAAALAAECgEIAQAAAA==.',Ae='Aeon:BAAALAAECgIIAgAAAA==.',Ah='Ahsokatano:BAAALAAECgIIAwAAAA==.',Ai='Aimspet:BAAALAADCggICAAAAA==.',Aj='Ajdath:BAAALAAECgcIDQAAAA==.',Ak='Akela:BAAALAAECgEIAgAAAA==.',Al='Alvyrian:BAAALAAECgEIAQAAAA==.',Am='Ames:BAAALAADCgcIBwAAAA==.Amonet:BAAALAADCgQICQAAAA==.',An='Anamis:BAAALAAECgMIBwAAAA==.Angras:BAAALAADCgYIBgAAAA==.Anolana:BAAALAAECgIIBQAAAA==.',Ap='Aphalock:BAAALAAECgIIAgAAAA==.',Ar='Ariûs:BAAALAADCggICwAAAA==.Arlorian:BAAALAAECgQIBgAAAA==.Arrowsmites:BAAALAAECgYICwAAAA==.',As='Astu:BAAALAADCggIDwAAAA==.',Au='Aubani:BAAALAAECgYICwAAAA==.Aurelora:BAAALAADCgMIAwAAAA==.',Av='Avatarzuko:BAAALAAFFAIIAgAAAA==.',Ay='Ayperos:BAAALAADCggICAAAAA==.',Az='Aza:BAAALAADCgQIBAABLAAECgQIBgABAAAAAA==.Aztmouf:BAAALAADCgYIBgAAAA==.',Ba='Bakedpally:BAAALAAECgUICAAAAA==.Bandomar:BAAALAAECgMIAwAAAA==.',Be='Beanediction:BAAALAADCgYIBgAAAA==.Beanjaeden:BAAALAAECgMIBgAAAA==.Beckett:BAAALAAECgEIAQAAAA==.Beefflaps:BAAALAADCgIIAgAAAA==.Benimarú:BAAALAAECgYIBgAAAA==.Benjamon:BAAALAADCgQIBAAAAA==.Bereth:BAAALAADCgQICQAAAA==.Berreydingle:BAAALAADCggIDgAAAA==.',Bi='Bigkitty:BAAALAAECgYIDAAAAA==.Bigntall:BAAALAADCgIIAgABLAADCggICwABAAAAAA==.',Bl='Blindfail:BAAALAAECgQICQAAAA==.Blindfred:BAAALAADCgcIDgAAAA==.Blinkerfluid:BAAALAAECgEIAQAAAA==.Bloodredsky:BAAALAAECgEIAQAAAA==.Bloodymagi:BAAALAAECgEIAQAAAA==.Bloodâce:BAAALAADCggICwAAAA==.',Bo='Borthuur:BAAALAADCggICAAAAA==.',Br='Brawlhaki:BAAALAAECgYIDQAAAA==.Brendameeks:BAAALAADCgcICAAAAA==.Brewrain:BAAALAADCgYIBgAAAA==.Brom:BAAALAADCgcICAAAAA==.Brutah:BAAALAAECggICAAAAA==.Brïn:BAAALAAECgEIAQAAAA==.',Bu='Buttercups:BAAALAAECgIIAgAAAA==.',['Bã']='Bãthory:BAAALAAECgYIBgAAAA==.',Ca='Calvert:BAAALAADCgUIBQAAAA==.Cararey:BAAALAADCgYIDQAAAA==.Carnelian:BAAALAADCgQICQAAAA==.Castration:BAAALAAECgEIAQAAAA==.',Ce='Ceylan:BAAALAAECgYICwAAAA==.',Ch='Chaleb:BAAALAADCgMIAwAAAA==.Charlz:BAAALAAECgYIDAAAAA==.Charsifood:BAAALAAECgYICQAAAA==.Charutre:BAAALAADCgEIAQAAAA==.Cheatpriest:BAAALAAECgMIAwAAAA==.Chesthyr:BAAALAAECgMIBgAAAA==.Chuwhee:BAAALAAECgYIDwAAAA==.',Co='Cognition:BAAALAAECgMIBAAAAA==.Coldvengance:BAAALAAECgMIBwAAAA==.',Cr='Cryomancer:BAABLAAECoEZAAIDAAcI0SL1CgDMAgADAAcI0SL1CgDMAgAAAA==.',Cy='Cymindel:BAAALAAECgQIBQAAAA==.',Da='Dakotà:BAAALAADCgcIDgAAAA==.Darktroll:BAAALAADCgYIBgAAAA==.Day:BAAALAAECgMIAwAAAA==.',De='Deathluster:BAAALAADCgYIBwAAAA==.Dejno:BAAALAAECgYICwAAAA==.Dethra:BAAALAADCgUIBwAAAA==.',Di='Discounttotm:BAAALAAECgYIDQAAAA==.Divinitÿ:BAAALAADCggIFAABLAAECgQIBQABAAAAAA==.',Do='Dologony:BAAALAAECgEIAQAAAA==.',Dr='Dragonz:BAAALAADCgQICQAAAA==.Dreåm:BAAALAADCgUIBQABLAAECgQIBQABAAAAAA==.Drikken:BAAALAAECgQIBQAAAA==.Drogoñ:BAAALAADCggICAAAAA==.Drëmägë:BAAALAAECgEIAQAAAA==.',Du='Duressa:BAAALAADCgYICAAAAA==.Durkdurk:BAAALAAECgMIAwAAAA==.',Ef='Effindin:BAAALAAECgEIAQAAAA==.Effinshady:BAAALAADCgYICAAAAA==.',El='Ellesthara:BAAALAADCggIDwAAAA==.Ellycia:BAAALAADCgIIAgAAAA==.Elwòod:BAAALAAECgMIBAAAAA==.',Em='Emmakyn:BAAALAAECgMIBgAAAA==.',Ep='Epsolon:BAAALAADCgMIBAAAAA==.',Ev='Evuul:BAAALAADCggIDwAAAA==.',Ex='Expel:BAAALAADCgUIBQAAAA==.',Ey='Eyedontknow:BAAALAAECgEIAQAAAA==.',Fa='Farnsworth:BAAALAAECgEIAgAAAA==.Façade:BAAALAAECgYIDQAAAA==.',Fe='Fefifredrich:BAAALAADCgcICwAAAA==.Fernbiee:BAAALAADCggIDwAAAA==.',Fi='Firelite:BAAALAADCgcIDQAAAA==.Fistersister:BAAALAADCgIIAgAAAA==.',Fl='Flairlock:BAAALAAECgMIBAAAAA==.Flexo:BAAALAADCgYIBgABLAAECgEIAgABAAAAAA==.',Fr='Frodon:BAAALAAECgMIBgAAAA==.',Ga='Ga:BAAALAAECgYIBgAAAA==.Garythenpc:BAAALAADCgMIBAAAAA==.',Gh='Ghimli:BAAALAADCgQIBAAAAA==.Ghøstranger:BAAALAADCgEIAQAAAA==.Ghøstslayer:BAAALAADCgYIBgAAAA==.',Gl='Glacialkitty:BAAALAAECgYICgAAAA==.',Go='Goldequinox:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.Googoobler:BAAALAAECgEIAQAAAA==.Gottrik:BAAALAAECgMIBAAAAA==.Goudatime:BAAALAADCgQIBAABLAAECgYIDAABAAAAAA==.',Gr='Graydot:BAAALAADCgcIBwAAAA==.Graymage:BAAALAAECgcICwAAAA==.Greenmagus:BAAALAADCgYICAAAAA==.Grenadon:BAAALAADCgQICQAAAA==.Grooveliciou:BAAALAADCggICAAAAA==.',Gu='Gunz:BAAALAAECgcIEQAAAA==.',Gy='Gyna:BAAALAADCgQIBAABLAAECgIIAwABAAAAAA==.',Ha='Hadorya:BAAALAAECgMIBwAAAA==.Halianaxus:BAAALAADCgYIBgAAAA==.Handey:BAAALAADCggIDQAAAA==.Hannibal:BAAALAADCgUIBQAAAA==.Harleyqûinn:BAAALAADCgEIAQAAAA==.Harthis:BAAALAAECgQIBAAAAA==.Hazard:BAAALAAECgMIBwAAAA==.',He='Hellboii:BAAALAAECgYICQAAAA==.Hexmourne:BAAALAADCgIIAgAAAA==.Heyitsrat:BAAALAAECgIIAgAAAA==.',Hf='Hfxpuck:BAAALAAECggIEwAAAA==.',Hi='Hidesto:BAAALAAECgEIAQAAAA==.Hinata:BAAALAADCgQIBAAAAA==.Hinder:BAAALAAECgUIBgAAAA==.',Ho='Holo:BAAALAAECggICAAAAA==.',Hu='Hurvis:BAAALAADCggICAAAAA==.Hutero:BAAALAAECgEIAQAAAA==.Huuginn:BAAALAADCgYIBwAAAA==.',Ic='Icculus:BAAALAAECgMIAwAAAA==.Icecold:BAAALAADCgEIAQAAAA==.',Im='Imamunch:BAAALAADCggICwAAAA==.Imavictim:BAAALAADCgIIAgAAAA==.Iminyou:BAAALAAECgQIBwAAAA==.',Io='Iolz:BAAALAAECgcIDwAAAA==.Iop:BAAALAADCgMIBAAAAA==.',Ja='Jaceventura:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.Jadoo:BAAALAAECgMIBQAAAA==.Jaggr:BAAALAADCgYIBwAAAA==.',Je='Jeeb:BAAALAAECgMIAwAAAA==.Jelly:BAAALAAECgMIAwAAAA==.',Jj='Jjrockman:BAAALAADCgIIAwAAAA==.',Jo='Joeeo:BAAALAADCggICAAAAA==.',Ju='Julytonidas:BAAALAAECgQIBAAAAA==.',Ka='Kaelnis:BAAALAAECgIIAgAAAA==.Kaimargonar:BAAALAAECgIIAwAAAA==.Kairos:BAAALAADCggICAABLAADCggICwABAAAAAA==.Kaitoi:BAAALAAECgEIAQAAAA==.Kamakizeg:BAAALAAECgYICAAAAA==.Kamayla:BAAALAAECgEIAQAAAA==.',Kh='Khui:BAAALAAECgcIDQAAAA==.',Ki='Kicsi:BAAALAADCggICAAAAA==.Kirenn:BAAALAADCgIIAgAAAA==.',Kn='Knìghtmàrè:BAABLAAECoEXAAIDAAgIGCGxDQCnAgADAAgIGCGxDQCnAgAAAA==.',Ko='Kozan:BAAALAAECgQIBwAAAQ==.Kozatra:BAAALAAECgEIAQAAAA==.',Kr='Krokk:BAAALAADCggICAAAAA==.',Ky='Kytania:BAAALAAECgMIBwAAAA==.',La='Lawluss:BAAALAADCgYIDgAAAA==.',Li='Lighthouse:BAAALAAECgMIBwAAAA==.Littlekitty:BAAALAAECgEIAQAAAA==.',Lo='Loladragon:BAAALAAECgMIBQAAAA==.',Lu='Luculia:BAAALAAECgEIAQAAAA==.',Ly='Lynaria:BAAALAADCggIFQAAAA==.Lypally:BAAALAAECgEIAQAAAA==.',['Lâ']='Lâdyamber:BAAALAADCgEIAQAAAA==.',Ma='Madcoil:BAAALAAECgIIAwAAAA==.Madeah:BAABLAAECoEXAAMEAAgIMhrCCQCLAgAEAAgIIRjCCQCLAgAFAAQIfhMFDAAJAQAAAA==.Manira:BAAALAAECggICAAAAA==.Marijwana:BAAALAAECgEIAQAAAA==.Marynne:BAAALAAECgQICAAAAA==.Mazuko:BAAALAAECgMIBwAAAA==.',Mc='Mcdo:BAAALAAECgQIBQABLAAECggIFAAGAMMWAA==.',Me='Meranda:BAAALAADCggIEQABLAAECgYIDAABAAAAAA==.Merrikwolf:BAAALAADCgIIBAAAAA==.',Mi='Mikokat:BAAALAADCggIDwAAAA==.',Mo='Monteman:BAAALAAECgMIBAAAAA==.Morthos:BAAALAADCgQIBAAAAA==.Mourneblood:BAAALAADCgEIAQAAAA==.',My='Mystik:BAAALAADCgYICAAAAA==.',['Mâ']='Mâgs:BAAALAAECgYICwAAAA==.',['Mè']='Mèxy:BAAALAADCgIIAgAAAA==.',Na='Nabbed:BAEALAAECggIAwAAAA==.Nakasid:BAAALAAECgMIAwAAAA==.Nashoba:BAAALAADCgcICgAAAA==.Natooka:BAAALAADCgcIBwAAAA==.Nazuul:BAAALAADCgEIAQAAAA==.',Ne='Nero:BAAALAADCgcIBwAAAA==.Netherkeeper:BAAALAAECgMIAwAAAA==.Nevaehstar:BAAALAAECgYIBQAAAA==.Nezin:BAAALAADCgcIDgAAAA==.',Ni='Nightshear:BAAALAADCgYIBgAAAA==.Nijun:BAEALAAECgYIDAAAAA==.Ninx:BAAALAAECgEIAQAAAA==.',Ob='Obesedenice:BAAALAAECgMIBAAAAA==.',On='Oneiros:BAAALAAECgcIEAAAAA==.',Or='Oraclespyro:BAAALAADCgcIDQAAAA==.',Pa='Papadragon:BAAALAADCgUIBQAAAA==.Papasbich:BAAALAADCgcICgAAAA==.Paprkut:BAAALAADCgUIBQAAAA==.Passhole:BAAALAAECgIIAwAAAA==.Patronous:BAAALAAECgMIBAAAAA==.',Pi='Pixie:BAAALAAECgYICQAAAA==.',Po='Porkchopw:BAAALAAECgEIAQAAAA==.',Pr='Proteinfarts:BAABLAAECoEUAAIGAAgIwxboDQAiAgAGAAgIwxboDQAiAgAAAA==.',Pu='Pumdmuc:BAAALAAECgYICQAAAA==.',['Pâ']='Pâlly:BAAALAADCgUICAAAAA==.',Qu='Quikglaives:BAAALAAECgEIAQAAAA==.Quiksilver:BAAALAAECgMIBAAAAA==.Quille:BAAALAAECgEIAgAAAA==.',Ra='Rahhem:BAAALAADCggIDgAAAA==.Rayspaly:BAAALAADCgMIBQAAAA==.',Re='Redwinter:BAAALAAECgMIBAAAAA==.Revrund:BAAALAADCggICAAAAA==.',Ri='Rightclick:BAAALAADCgQIBAAAAA==.Riqua:BAAALAAECgMIAwAAAA==.',Ro='Rodeo:BAAALAADCggIDwAAAA==.',Ru='Rubycaster:BAAALAADCgYICQAAAA==.Runty:BAAALAAECgMIAwAAAA==.',Sa='Sacket:BAAALAADCgUIBQAAAA==.Saeti:BAAALAAECgYICQAAAA==.',Se='Seresin:BAAALAAECgMIBgAAAA==.',Sh='Shaydesong:BAAALAADCgEIAQAAAA==.Shimluk:BAAALAADCgQIBQAAAA==.Shortwarrior:BAAALAAECgMIBgAAAA==.',Sk='Skyscales:BAEALAAECgMIBAAAAA==.',Sm='Smileyboy:BAAALAADCgIIAgAAAA==.',So='Sofiophya:BAAALAADCgQICQAAAA==.Solarêclipse:BAAALAADCgMIAwAAAA==.Sooki:BAAALAAECgMIAwAAAA==.Sophie:BAAALAADCggIDwAAAA==.Sorlis:BAAALAADCgcIBwAAAA==.Sourdew:BAAALAAECgMIBwAAAA==.',Sq='Squished:BAAALAAECgEIAQAAAA==.',St='Starrdust:BAEALAADCgMIBAAAAA==.Stelle:BAAALAAECgEIAQAAAA==.Stãrburst:BAAALAAECgMIAwAAAA==.',Su='Subrinea:BAAALAAECgQIBQABLAAECgYIBQABAAAAAA==.Sumofwhy:BAAALAADCgIIAgAAAA==.',Sw='Swarli:BAAALAAECgMIBAAAAA==.',Ta='Taffeez:BAAALAADCgMIAwAAAA==.Talovan:BAAALAADCgIIAgAAAA==.Tatertotz:BAAALAADCgcIEgAAAA==.',Te='Teghorn:BAAALAAECgYICQAAAA==.Tekko:BAAALAAECgMIBQAAAA==.',Th='Theholymatt:BAAALAAECgQIBQAAAA==.Thelockmatt:BAAALAAECgQIBQAAAA==.Thendari:BAAALAAECgMIBwAAAA==.Theodus:BAAALAAECgYIDgAAAA==.Therayen:BAAALAADCgcICgAAAA==.',Ti='Times:BAAALAADCgUIBQAAAA==.Tiris:BAAALAAECggICAAAAA==.Tizzy:BAAALAADCgMIAwAAAA==.',To='Tobiquer:BAAALAAECgEIAgAAAA==.',Tr='Traydra:BAAALAADCgcIEgAAAA==.Tricarys:BAAALAAECgYIDQAAAA==.Troglodyte:BAAALAAFFAIIAwAAAA==.',Ty='Tye:BAAALAAECggIAgAAAA==.Tyedeath:BAAALAADCggICAAAAA==.Tyranastrasz:BAAALAAECgIIAwAAAA==.',['Tâ']='Tâjik:BAAALAAECgQIBQAAAA==.',Va='Valgavoth:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Vassyra:BAAALAAECgQIBgAAAA==.',Ve='Velinna:BAAALAADCgcIBwAAAA==.',Vi='Vivilee:BAAALAADCgIIAwAAAA==.',Vo='Volundr:BAAALAAECgMIBwAAAA==.',Vy='Vynel:BAAALAAECgQIBQAAAA==.',Wa='Warlockbob:BAAALAADCgUIBQAAAA==.Warlockskull:BAAALAAECgMIBAAAAA==.',Wh='Whytefeather:BAAALAAECgYICgAAAA==.',Wm='Wmd:BAAALAAECgIIAwAAAA==.',['Wù']='Wùsthof:BAAALAAECgYIDAAAAA==.',Xe='Xenk:BAAALAADCggIDgAAAA==.',Xi='Xiae:BAAALAAECgMIBwAAAA==.',Xo='Xorrin:BAAALAADCggIDwAAAA==.',Yi='Yiffweaver:BAAALAAECgMIBAAAAA==.',Yo='Yokoriazen:BAAALAAECgYIDwAAAA==.',Yv='Yv:BAAALAADCgYIBwAAAA==.Yvesass:BAAALAADCgcICwAAAA==.',Za='Zacthyr:BAAALAADCgYIBAAAAA==.Zancrow:BAAALAAECgYICQAAAA==.Zaraelius:BAAALAADCggICAAAAA==.Zarriena:BAAALAADCgcIDQAAAA==.',Ze='Zendroz:BAAALAAECgMIAwAAAA==.',Zi='Zitalan:BAAALAADCggIGgAAAA==.',Zm='Zmona:BAAALAAECgEIAgAAAA==.',Zo='Zorsche:BAAALAADCggICAAAAA==.',Zu='Zulrok:BAAALAAECgYICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end