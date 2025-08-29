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
 local lookup = {'Unknown-Unknown','Paladin-Holy','Shaman-Restoration','Priest-Holy','Druid-Restoration','Priest-Shadow','DemonHunter-Havoc','Paladin-Retribution',}; local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abdulaan:BAAALAADCgYIEAAAAA==.Abracadabruh:BAAALAAECgYICgAAAA==.',Ac='Academe:BAAALAAECgMIAwAAAA==.',Ad='Adün:BAAALAAECgQIBAAAAA==.',Ae='Aellopus:BAAALAAECgMIBAAAAA==.Aero:BAAALAAECgQICAAAAA==.Aerwin:BAAALAADCgYIBgAAAA==.',Ag='Agarosi:BAAALAAECgMIAwAAAA==.Agility:BAAALAAECgYICgAAAA==.Agorrash:BAAALAADCgcIDAAAAA==.Agròm:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.',Ah='Ahria:BAAALAAECgcIDgAAAA==.',Ai='Ainnare:BAAALAADCgcIDAAAAA==.',Al='Alisryong:BAAALAAECgMIBgAAAA==.Alocane:BAAALAADCgEIAQABLAAECgUICAABAAAAAA==.Alune:BAAALAADCgMIAQAAAA==.',Am='Amiliane:BAAALAAECgMIBgAAAA==.Amunshi:BAAALAAECgMIAwAAAA==.',An='Anadrien:BAAALAAECgMIBQAAAA==.Andrae:BAAALAADCgUIBwAAAA==.Angrimia:BAAALAAECgQIBgAAAA==.Anjul:BAAALAAECgMIAwAAAA==.Anthelyn:BAAALAADCgcIBwAAAA==.',Ar='Araelun:BAAALAAECgYICQAAAA==.Archielgh:BAAALAAECgYICAAAAA==.Arit:BAAALAADCgMIAwABLAAECgMIBwABAAAAAA==.Arix:BAAALAADCgcIBwAAAA==.Arore:BAAALAAECgMIBwAAAA==.Arrowdynamic:BAAALAADCgcICwABLAADCggICgABAAAAAA==.Arsham:BAAALAADCgUIBQABLAAECgMIBwABAAAAAA==.Arzec:BAAALAAECgMIBQAAAA==.',Au='Aubrey:BAAALAADCgcIBwAAAA==.',Av='Avestara:BAAALAAECgQICAAAAA==.',Az='Azoril:BAAALAAECgQIBwAAAA==.Azraael:BAAALAAECgYICQAAAA==.',Ba='Baal:BAAALAADCgcIDAAAAA==.Bababowie:BAAALAAECgYIDgAAAA==.Babs:BAAALAADCgcIBwAAAA==.Baelnorn:BAAALAAECgYICQAAAA==.Bakatare:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Barlton:BAAALAAECgYICwAAAA==.Barry:BAAALAAECgIIAgAAAA==.Basicbenja:BAAALAADCggIFQAAAA==.Battykoda:BAAALAAECgMIAwAAAA==.Bazir:BAAALAAECgIIAwABLAAECgYIDQABAAAAAA==.',Be='Bearpawz:BAAALAADCgUIBQAAAA==.Bearserker:BAAALAAECgIIAgAAAA==.Beastcleave:BAAALAADCgcIBwAAAA==.Bekens:BAAALAAECgMIBQAAAA==.Beni:BAAALAAECgYIBwAAAA==.Bernardboggs:BAAALAAECgIIAgAAAA==.Bethbathory:BAAALAAECgYICQAAAA==.',Bh='Bheefknight:BAAALAADCggIDwAAAA==.Bheefshot:BAAALAADCgcIDQAAAA==.',Bi='Bierbro:BAAALAAECgUICAAAAA==.Bigbootyjudy:BAAALAAECgMIBQAAAA==.Bigsofty:BAAALAAECgYIBgAAAA==.Bigtotem:BAEALAAECgMIAwAAAA==.Birdman:BAAALAAECgEIAQAAAA==.Bixus:BAAALAADCgcIBwAAAA==.',Bl='Blightheaded:BAAALAADCggIFwAAAA==.Blumir:BAAALAAECgQIBAAAAA==.',Bo='Bogatyri:BAAALAADCgcIBwAAAA==.Bolbzap:BAAALAADCgcIBwAAAA==.Bomgan:BAAALAAECgQICAAAAA==.Bonchonn:BAAALAAECgYIBgAAAA==.Boyoboi:BAAALAADCgcICAAAAA==.',Br='Brae:BAAALAAECgIIAgAAAA==.Briciferdrip:BAAALAADCgQIBAABLAAECggICAABAAAAAA==.Briciferkong:BAAALAAECggICAAAAA==.Bricifernope:BAAALAAECgQIBAABLAAECggICAABAAAAAA==.Brightblayde:BAAALAAECgQICAAAAA==.',Bu='Buanto:BAAALAAECgIIAgAAAA==.Bubblegumm:BAAALAAECgMIBgAAAA==.Bubblesuds:BAAALAADCgMIAwABLAAECgMIBgABAAAAAA==.Bubbllz:BAAALAADCgUIBQAAAA==.Bullshatner:BAAALAADCgYIBgAAAA==.Burim:BAAALAAECgYICQAAAA==.Butterknight:BAAALAAECgYICwAAAA==.Buttertotem:BAAALAADCgUIBQAAAA==.',Ca='Callistine:BAAALAAECgYICQABLAAECgYICQABAAAAAA==.Canyouseame:BAAALAADCggICAAAAA==.Captevil:BAAALAADCggIFAAAAA==.Casey:BAAALAAECgQIBgAAAA==.Cattroll:BAAALAADCgEIAQABLAADCgEIAQABAAAAAA==.',Cd='Cdubb:BAAALAAECgEIAQAAAA==.',Ce='Celidori:BAAALAADCgEIAQAAAA==.Celithila:BAAALAAECgMIBgAAAA==.Ceolfang:BAAALAAECgMIAwAAAA==.Cervantés:BAAALAAECgUICgAAAA==.',Ch='Chise:BAAALAAECgYIDAAAAA==.Chrispyloa:BAAALAADCggIDwAAAA==.Chulip:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.',Ci='Ciceler:BAAALAADCgYIBwAAAA==.',Cl='Clychi:BAAALAAECgMIAwAAAA==.',Co='Coachbeard:BAABLAAECoEUAAICAAgIXgkQEgC1AQACAAgIXgkQEgC1AQAAAA==.Coldhands:BAAALAADCgEIAQABLAAECgcIFQADAFEjAA==.Colzaratha:BAAALAAECgIIAgAAAA==.',Cr='Crankdhog:BAAALAAECgEIAQAAAA==.Critliquor:BAAALAAECgQIBQAAAA==.Crosby:BAAALAAECgYICAAAAA==.',Cy='Cyberfang:BAAALAADCggICgAAAA==.Cygna:BAAALAAECgUICwAAAA==.Cygnum:BAAALAAECgMIAwAAAA==.Cyntheis:BAAALAADCgcIBwAAAA==.Cyntheria:BAAALAAECgYIDAAAAA==.',Da='Daddydemonic:BAAALAAECgMIAwAAAA==.Dagrizzly:BAAALAADCgUIBwAAAA==.Dajubah:BAAALAAECgYICQAAAA==.Darksaxon:BAAALAAECgMIAwAAAA==.Darthornix:BAAALAADCgcIBwAAAA==.',De='Deadhampster:BAAALAADCgQIBAAAAA==.Deathbylight:BAAALAADCgcIDAAAAA==.Deathnethal:BAAALAADCgUIBQAAAA==.Delsanra:BAAALAADCgQIBAAAAA==.Delythy:BAAALAADCgcIBwAAAA==.Demenico:BAABLAAECoEXAAIEAAgIGR2aCACgAgAEAAgIGR2aCACgAgAAAA==.Demonica:BAAALAAECgQIBgAAAA==.Dendrax:BAAALAAECgMIBQAAAA==.Derivation:BAAALAADCggIDwAAAA==.Dethwing:BAAALAAECgEIAQAAAA==.Deviance:BAAALAAECgMIAwAAAA==.Dexterous:BAAALAAECgEIAQAAAA==.',Di='Dienmage:BAAALAAECgUICAAAAA==.Dinius:BAAALAAECgMIAwAAAA==.',Dj='Djanga:BAAALAAECgYICQAAAA==.',Dk='Dkdiso:BAAALAAECgMIAwAAAA==.',Do='Dorena:BAAALAAECgUICAAAAA==.',Dr='Dragontales:BAAALAADCgMIAwAAAA==.Drakkisath:BAAALAAECgQICAAAAA==.Drango:BAAALAAECgMIBQAAAA==.Draugdae:BAAALAAECgMIBgAAAA==.Drinksomuch:BAAALAADCgEIAQAAAA==.Drome:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.Drukhi:BAAALAAECgYICQAAAA==.',Du='Dumpsterfirê:BAAALAADCgcIDgAAAA==.Dungrough:BAAALAADCgcIBwAAAA==.Durtkal:BAAALAAECgYICgAAAA==.',Ea='Earnhardt:BAAALAADCggICAAAAA==.',Ed='Edgeboy:BAAALAADCggIDAABLAAECgYIDQABAAAAAA==.',El='Eljaye:BAAALAADCgcIFAAAAA==.',Em='Embershadow:BAAALAADCggIFQAAAA==.',Er='Erovoker:BAAALAADCgIIAgAAAA==.',Es='Esméralda:BAAALAAECgMIAwAAAA==.Espeeon:BAAALAADCggICwAAAA==.',Eu='Eurythmics:BAAALAAECgMIAwAAAA==.',Ev='Evileen:BAAALAADCggIFQAAAA==.',Ex='Exodiance:BAAALAAECgcIDAAAAA==.',Fa='Fahooquazaad:BAAALAADCgcIEwAAAA==.Falere:BAAALAADCggICAAAAA==.Faloway:BAAALAADCgcICQAAAA==.Fancy:BAAALAAECgYIDAAAAA==.Faythlis:BAAALAADCggICAAAAA==.',Fe='Feetlesmcdee:BAAALAAECgEIAQAAAA==.Feirgë:BAAALAAECgYICQAAAA==.Felfáádaern:BAAALAAECgMIBgAAAA==.Felowship:BAAALAADCgIIAQAAAA==.Felporch:BAAALAAECgIIAgAAAA==.Felstorm:BAAALAAECgIIAwAAAA==.Fendralix:BAAALAADCgcICgAAAA==.',Fi='Firminator:BAABLAAECoEVAAIDAAcIUSOaBQC3AgADAAcIUSOaBQC3AgAAAA==.',Fl='Flaccidphil:BAAALAADCggIFwAAAA==.Flowermound:BAAALAADCgQIBAAAAA==.',Fo='Fookmifuku:BAAALAADCgMIAwAAAA==.Fourqto:BAAALAADCggICAAAAA==.Foxybains:BAAALAAECgYICQAAAA==.',Fr='Fredmenethil:BAAALAAECgIIAwAAAA==.Frona:BAAALAAECgQIBwAAAA==.Frone:BAAALAAECgEIAQAAAA==.',Fu='Fujikujaku:BAAALAAECgIIAgAAAA==.Fulmetal:BAAALAAECgMIAwAAAA==.Funerris:BAAALAADCggIBwAAAA==.Funkalicious:BAAALAAECgYICgAAAA==.Fuzzycursed:BAAALAAECgYICAAAAA==.',Ga='Galinduh:BAAALAADCgcIDAAAAA==.Gazreyna:BAAALAADCgEIAQAAAA==.',Gc='Gcarne:BAAALAAECgQIBgAAAA==.',Ge='Genós:BAAALAAECgYICQAAAA==.Gerardo:BAAALAADCgcIFAAAAA==.Getgud:BAAALAAECgYICQAAAA==.',Gh='Ghurri:BAAALAAECgQIBwAAAA==.',Gi='Gigaslicer:BAAALAAECgQIBgAAAA==.Ginnee:BAAALAADCgcIDAAAAA==.Ginnion:BAAALAAECgMIAwAAAA==.Giraffe:BAAALAAECggICAAAAA==.Gitachela:BAAALAADCggIEgAAAA==.',Gl='Glaedor:BAAALAADCgcIBwAAAA==.Glakenspheal:BAAALAAECgQIBQAAAA==.',Gn='Gnomana:BAAALAADCgYIBgAAAA==.',Go='Gogorath:BAAALAADCgIIAgAAAA==.Gojano:BAAALAAECgcIDwAAAA==.',Gr='Graestoke:BAAALAAECgYICwAAAA==.Grassman:BAAALAADCgIIAgAAAA==.Gregorizz:BAAALAADCgMIAwAAAA==.Greybeast:BAABLAAECoEVAAIFAAgI3RZbDwAPAgAFAAgI3RZbDwAPAgAAAA==.Greyfoxy:BAAALAAECgEIAQABLAAECgYICgABAAAAAA==.Gripz:BAAALAADCggICgAAAA==.Grizelda:BAAALAAECgMIBgAAAA==.Growls:BAAALAAECgMIBQAAAA==.Grumpyazpapa:BAAALAADCgEIAQABLAAECgMIBAABAAAAAA==.Grèyfòx:BAAALAAECgYICgAAAA==.',Gu='Gudela:BAAALAADCggICAAAAA==.',['Gõ']='Gõldenchild:BAAALAAECgEIAQAAAA==.',Ha='Hairypitts:BAAALAAECgYICgAAAA==.Halfwayz:BAAALAAECgMIAwAAAA==.Handleup:BAAALAADCgcIDAAAAA==.Haniel:BAAALAAECgMIAwAAAA==.Happychaos:BAAALAAECgQICAAAAA==.Hazzbek:BAAALAAECgEIAQAAAA==.',He='Healthysnack:BAAALAAECgYICwAAAA==.Heiboss:BAAALAAECgIIAwABLAAECgYIDAABAAAAAA==.Heimister:BAAALAADCgMIAwABLAAECgYIDAABAAAAAA==.Heipal:BAAALAAECgEIAQABLAAECgYIDAABAAAAAA==.Heithyr:BAAALAADCgUIBQABLAAECgYIDAABAAAAAA==.Helani:BAAALAAECgYICwAAAA==.Helfyrefang:BAAALAADCgcIDAAAAA==.Hellbane:BAAALAADCggICAAAAA==.Help:BAAALAAECgEIAQABLAAECgYICwABAAAAAA==.Hewwo:BAAALAAECgcIDQAAAA==.',Hi='Hildegarde:BAAALAAECgEIAQAAAA==.Hinomiko:BAAALAAECgEIAQABLAAECgQIBwABAAAAAA==.Hiyori:BAAALAADCgcIEAABLAADCggIDQABAAAAAA==.',Ho='Holycharlie:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.Honeyb:BAAALAADCgcIBwAAAA==.Hotshiften:BAAALAAECgYIDgAAAA==.',Hu='Hughjaz:BAAALAAECgQICAAAAA==.Huran:BAAALAAECgYIDAAAAA==.',Ig='Ignignokt:BAEALAAECgQIBgAAAA==.',Im='Immorallight:BAAALAADCgUIBQAAAA==.',In='Inaspirit:BAAALAAECgQIBQAAAA==.',Ir='Ira:BAAALAAECgMIBQAAAA==.Ironshield:BAAALAAECgcIEQAAAA==.',It='Itsnotbutter:BAAALAADCggICAAAAA==.',Iv='Iveymectin:BAAALAADCgcIBwAAAA==.Ivie:BAAALAADCgcICQAAAA==.',Iw='Iwishiknew:BAAALAAECgYIDAAAAA==.',Iz='Izzit:BAAALAADCggIFwAAAA==.',Ja='Jakiepoobear:BAAALAAECgMIBgAAAA==.',Je='Jedery:BAAALAAECgMIAwAAAA==.Jellydragon:BAAALAAECgYICwAAAA==.',Jo='Johannes:BAAALAAECgYIEAAAAA==.Johnkeating:BAAALAADCgcIDAABLAAECgMIAwABAAAAAA==.Jolynn:BAAALAAECgUICAAAAA==.Joroldess:BAAALAAECgUICAAAAA==.',Ju='Jubbawookie:BAAALAADCggIDQAAAA==.',Jy='Jynxie:BAAALAAECgMIAwAAAA==.',['Jé']='Jénova:BAAALAAECgIIAgAAAA==.',Ka='Kahndumb:BAAALAADCgQIBAAAAA==.Kaida:BAAALAAECgIIAgAAAA==.Kaio:BAAALAAECgYICQAAAA==.Kaizoe:BAAALAAECgIIAgAAAA==.Kalahan:BAAALAAECgMIAwAAAA==.Kalimaa:BAAALAADCggIDwAAAA==.Karigyn:BAAALAAECgQICAAAAA==.Karun:BAAALAAECgMIBQAAAA==.Kaskaa:BAAALAADCggIDwAAAA==.Kasumi:BAAALAAECgYICwAAAA==.Katren:BAAALAADCgMIAwAAAA==.Katrienne:BAAALAAECgQIBwAAAA==.Kaylid:BAAALAAECgMIAwAAAA==.Kazioiron:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Kazzoth:BAAALAAECgYICQAAAA==.',Ke='Keikyu:BAAALAADCgYICAAAAA==.Keilen:BAAALAADCggIDQAAAA==.Kelasha:BAAALAADCggIFgAAAA==.',Ki='Killari:BAAALAADCgcICQAAAA==.Killdeath:BAAALAADCgcIDwAAAA==.',Kl='Klax:BAAALAADCggICAAAAA==.',Ko='Kombit:BAAALAAECgQIBAAAAA==.Konokusotare:BAAALAADCggICAAAAA==.Kortek:BAAALAAECgYICQAAAA==.Kozath:BAAALAADCgcIFAAAAA==.',Kr='Kralkor:BAAALAADCgcIBwAAAA==.Kreckon:BAAALAADCggIDwAAAA==.Krowley:BAAALAADCgMIAgAAAA==.',Ku='Kukulkan:BAAALAAECgEIAQAAAA==.Kuulan:BAAALAAECgYICQAAAA==.',Ky='Kyrei:BAAALAAECgMIAwAAAA==.Kythra:BAABLAAECoEbAAIFAAgIiSMrAwDiAgAFAAgIiSMrAwDiAgAAAA==.',La='Lanstin:BAAALAAECgIIAgAAAA==.Lateralus:BAABLAAECoEWAAMGAAcI2A7oJgBdAQAGAAUItBPoJgBdAQAEAAYIQg13KgBTAQAAAA==.Lathora:BAAALAAECgEIAQAAAA==.',Le='Leakie:BAAALAADCggIDgABLAAECgYIDAABAAAAAA==.Leancuisine:BAAALAAECgEIAQAAAA==.Leetlebug:BAAALAAECgQICAAAAA==.Lenag:BAAALAAECgYICwAAAA==.Lettÿ:BAAALAADCgcIFAABLAAECgEIAQABAAAAAA==.',Li='Lightzwrath:BAAALAADCggIDgABLAAECgMIAwABAAAAAA==.Lilgaydar:BAAALAAECgIIAwAAAA==.Lilith:BAAALAADCggICAAAAA==.Lilium:BAAALAAECgMIAwAAAA==.Linitharieda:BAAALAADCgYIBgABLAAECgYIEAABAAAAAA==.',Lo='Lockbealady:BAAALAAECgIIAgAAAA==.Lodiso:BAAALAADCgEIAQAAAA==.Loganlo:BAAALAADCgcIDgAAAA==.Loreix:BAAALAAECgMIBAAAAA==.Lowping:BAAALAADCgcIBwAAAA==.',Lu='Luvineas:BAAALAAECgIIAgAAAA==.Luvinz:BAAALAADCgcIFAAAAA==.',Ma='Maarc:BAAALAAECgEIAQAAAA==.Maddragon:BAAALAAECgEIAgAAAA==.Madfurion:BAAALAADCgcIEgAAAA==.Mahlygos:BAAALAAECgIIAgAAAA==.Majestic:BAAALAAECgYIDQAAAA==.Malvenue:BAAALAAECggIDAAAAA==.Marex:BAAALAAECgYICQAAAA==.Matali:BAAALAADCggIFwABLAAECgYIDAABAAAAAA==.Mauwy:BAAALAAECgYIDAAAAA==.',Mc='Mcbullseye:BAAALAAECgQIBAAAAA==.',Me='Melshaman:BAAALAADCgcIBwAAAA==.Menados:BAAALAAECgYICgAAAA==.Mercury:BAAALAAECgEIAQAAAA==.Meretrix:BAAALAAECgMIAwAAAA==.Metanya:BAAALAAECgQIBQAAAA==.Mew:BAAALAADCgcIFAAAAA==.',Mi='Miateh:BAAALAAECgEIAQAAAA==.Mistique:BAAALAADCgIIAgAAAA==.Mitsuu:BAAALAADCgEIAQAAAA==.Miwah:BAAALAAECgYICQAAAA==.',Mo='Modin:BAAALAAECgUICAAAAA==.Modnarii:BAAALAAECgMIBgAAAA==.Mogarr:BAAALAAECgMIBQAAAA==.Moktal:BAAALAADCgcIBwAAAA==.Mooglewing:BAAALAAECgEIAQAAAA==.Mordicanta:BAAALAAECgYICQAAAA==.',Ms='Msbaddie:BAAALAAECgEIAQAAAA==.',Mu='Muerr:BAAALAAECgYICwAAAA==.Muerrizond:BAAALAADCggIFwABLAAECgYICwABAAAAAA==.Muerrlin:BAAALAADCggICAABLAAECgYICwABAAAAAA==.Muggel:BAAALAADCggIBgAAAA==.Mushroohead:BAAALAAECgUICwAAAA==.Mushystorm:BAAALAADCgcIBwAAAA==.',My='Mysterbyrnes:BAAALAAECgYIDgAAAA==.Myykiel:BAAALAAECgMIAwAAAA==.',Na='Naina:BAAALAAECgMIBgAAAA==.Nayna:BAAALAAECgEIAQAAAA==.',Ne='Nephie:BAAALAADCgcIDgAAAA==.',Ni='Nickodemus:BAAALAADCgYIBgAAAA==.Nightle:BAAALAADCgcIEQAAAA==.Nihil:BAAALAAECgYICwAAAA==.Nikano:BAAALAAECgYIBgAAAA==.Nirø:BAAALAAECgYICQAAAA==.',No='Nogard:BAAALAADCgEIAQAAAA==.Nooky:BAAALAADCgYIBgAAAA==.Novodivincus:BAAALAADCgcICwAAAA==.Novomortem:BAAALAAECgMIBgAAAA==.',Nu='Nuuwuub:BAAALAADCgYIBwAAAA==.',Ny='Nyctaro:BAAALAAECgMIAwABLAAECgQIBgABAAAAAA==.Nyrikah:BAAALAADCgcIDAAAAA==.',['Né']='Néxus:BAAALAADCgQIBAAAAA==.',Ob='Obidiah:BAAALAAECgMIBgAAAA==.',Om='Omegablivet:BAAALAAECggICAAAAA==.Omens:BAAALAADCgYIBgAAAA==.',On='Onlyforms:BAAALAADCgcIDQAAAA==.',Oo='Ooeygooey:BAAALAADCgQIAgAAAA==.',Or='Oralle:BAAALAADCgEIAQAAAA==.Orpheus:BAAALAAECgIIAgABLAAECgcIEQABAAAAAA==.',Ou='Ourg:BAAALAADCgMIAwAAAA==.',Pa='Pandahands:BAAALAAECgMIAwAAAA==.Papabill:BAAALAAECgMIBAAAAA==.Paragorn:BAAALAADCgMIAwAAAA==.Pawp:BAAALAAECgIIAgAAAA==.Pazûzû:BAAALAADCgcICQAAAA==.',Pe='Peace:BAAALAADCgcIBwAAAA==.Pechay:BAAALAAECgUICQAAAA==.Peenidin:BAAALAAECgYICQAAAA==.Pemerd:BAAALAAECgIIAgAAAA==.',Ph='Phoze:BAAALAAECgMIBAAAAA==.Phozzack:BAAALAADCgUIBQAAAA==.Phyai:BAAALAAECgMIBQAAAA==.',Pi='Pizzarollzz:BAAALAAECgMIAwAAAA==.',Pr='Prophet:BAAALAAECgEIAQAAAA==.Pryxi:BAAALAAECgMIBQAAAA==.',Py='Pyrothanax:BAAALAADCgYIDQAAAA==.',['Pó']='Pótatò:BAAALAADCgEIAQAAAA==.',Qa='Qawool:BAAALAAECgYICQAAAA==.',Qu='Quepinga:BAAALAADCgYIAQAAAA==.',Ra='Racaveli:BAAALAAECgEIAQAAAA==.Radu:BAAALAAECgYIBgAAAA==.Rawaxis:BAAALAADCgEIAQAAAA==.',Re='Reckoner:BAAALAADCgYIBgAAAA==.Redwingxd:BAAALAADCgcIDQAAAA==.Rellster:BAAALAAECgYICgAAAA==.Rennyo:BAAALAAECgMIBQAAAA==.Rescuecat:BAAALAADCgcIBgAAAA==.Resolve:BAAALAADCgYIBgAAAA==.Rexion:BAAALAAECgMIBgAAAA==.',Rh='Rhea:BAAALAADCggIDgAAAA==.Rhyash:BAAALAAECgYIBgAAAA==.',Ri='Ridicutie:BAAALAAECgMIAwAAAA==.Rigg:BAAALAADCgcIBQABLAADCggICAABAAAAAA==.Riggsy:BAAALAADCggICAAAAA==.Rirac:BAAALAAECgIIAgAAAA==.',Ro='Roari:BAAALAAECgMIAwAAAA==.Rocknroll:BAAALAAECgQICQAAAA==.Roll:BAAALAAECgMIBQAAAA==.Roqui:BAAALAADCgcIBwAAAA==.Rornix:BAAALAADCgMIAQAAAA==.Rothound:BAAALAADCggICAAAAA==.Roundtuit:BAAALAADCgMIAwAAAA==.',Ru='Rumlidorgah:BAAALAAECgQIBgAAAA==.',['Ré']='Réven:BAAALAAECgYICQAAAA==.',Sa='Sabinthy:BAAALAAECgMIAwAAAA==.Salmissra:BAAALAADCgMIAwAAAA==.Salttine:BAAALAADCggIFwAAAA==.Samus:BAAALAADCggICAAAAA==.Sandrï:BAAALAAECgIIAgAAAA==.Sane:BAAALAAECgMIBgAAAA==.Saoiirse:BAAALAAECgMIBgAAAA==.Sasso:BAAALAAECgEIAQAAAA==.',Se='Searshaa:BAAALAADCgYICQAAAA==.Sevencharlie:BAAALAAECgEIAgAAAA==.',Sh='Shabushabu:BAAALAADCgcIBwAAAA==.Shadowbee:BAAALAADCgcIBgAAAA==.Shadowfist:BAAALAAECgUIBgAAAA==.Shambulance:BAAALAAECgIIAwAAAA==.Shamutty:BAAALAAECgQIBAABLAAECgYICwABAAAAAA==.Sharasdal:BAAALAAECgYICgAAAA==.Shellshocked:BAAALAADCgcIDQAAAA==.Shinjô:BAAALAADCggIDwAAAA==.Shouganai:BAAALAAECgEIAQAAAA==.Shénron:BAAALAADCggICAAAAA==.',Si='Sinaar:BAAALAAECgIIAgAAAA==.Sinisterpaly:BAAALAADCgYIBwAAAA==.Sittingbull:BAAALAADCggICAAAAA==.',Sk='Skippie:BAAALAADCgcIEQAAAA==.Skjaldborg:BAAALAADCgMIAwAAAA==.Skompy:BAAALAAECgIIAgAAAA==.Skyemage:BAAALAAECgMIAwAAAA==.',Sl='Sleepi:BAAALAADCgUIBQAAAA==.Sliveer:BAAALAADCgEIAQAAAA==.Slotz:BAAALAAECgQICAAAAA==.',Sm='Smike:BAAALAAECgMIBQAAAA==.Smitmittens:BAAALAAECgcIBwAAAA==.',Sn='Sneakybains:BAAALAADCgcIBwAAAA==.',So='Soterria:BAAALAAECgMIBAAAAA==.Soulbent:BAAALAADCgcIBwAAAA==.Soulforsale:BAAALAAECgMIAwAAAA==.',Sp='Spiké:BAAALAADCgEIAQAAAA==.Sputty:BAAALAAECgYIBgABLAAECgYICwABAAAAAA==.',St='Stonedfrog:BAAALAADCgcIDAAAAA==.Strangelets:BAAALAADCggICgAAAA==.Strangewayes:BAAALAAECgMIBgAAAA==.Stönk:BAAALAADCgEIAQAAAA==.',Su='Succulentman:BAABLAAECoEWAAIHAAgIux7ECwDKAgAHAAgIux7ECwDKAgAAAA==.Sunscream:BAAALAAECgQICAAAAA==.Supreme:BAAALAAECgMIAwAAAA==.Surolath:BAAALAAECgQIBgAAAA==.',Sw='Swaggles:BAAALAAECgYICQAAAA==.',Sy='Syntherizena:BAAALAADCggICAAAAA==.',Ta='Tacitus:BAAALAAECgMIAwAAAA==.Tairrad:BAAALAADCgcIDQAAAA==.Takeru:BAAALAADCggIFQAAAA==.Talasmar:BAAALAADCgMIAwAAAA==.Talkurimalys:BAAALAADCggICAAAAA==.Tarirn:BAAALAADCggIDwAAAA==.Tauntsinpvp:BAAALAAECgEIAQAAAA==.',Te='Tekster:BAAALAAECgMIAgAAAA==.Tenryu:BAAALAAECgMIBQAAAA==.',Th='Thajeebus:BAAALAADCgcIDgAAAA==.Thann:BAAALAADCgcIDQAAAA==.Thatsneat:BAAALAAECgMICAAAAA==.Thecapt:BAAALAAECgcICwAAAA==.Thorinfel:BAAALAAECgcIEQAAAA==.',Ti='Tiaoma:BAAALAAECgcIDAAAAA==.Tieriadk:BAAALAAECgMIAwAAAA==.Tikao:BAAALAAECgMIBAAAAA==.Tindle:BAAALAAECgMIBQAAAA==.Tinylock:BAAALAADCgEIAQAAAA==.',To='Tobajal:BAAALAAECgYICQAAAA==.Toreshii:BAAALAADCgEIAQAAAA==.Totumpole:BAAALAAECgIIAgAAAA==.',Tr='Treeperson:BAAALAAECgMIAwAAAA==.Treyni:BAAALAAECgIIAgAAAA==.Trinitey:BAAALAAECgQIBwABLAAFFAMIBQAIAMgSAA==.Tropicalia:BAAALAADCgEIAQABLAAECgcIEQABAAAAAA==.',Ts='Tsuyoimono:BAAALAAECgQIBwAAAA==.',Tw='Twiddydh:BAAALAADCgcIBwAAAA==.Twiddymage:BAAALAAECgQIAwAAAA==.Twoinchtotem:BAAALAADCgIIAwAAAA==.Twylan:BAAALAADCgYIBgAAAA==.',Un='Uncivilized:BAAALAAECgEIAwAAAA==.',Ur='Uratsukasama:BAAALAADCgcIFAAAAA==.',Ut='Utter:BAAALAADCgMIAwAAAA==.',Va='Vacaite:BAAALAAECgEIAQAAAA==.',Ve='Velveen:BAAALAAECgMIBQAAAA==.Verdraeos:BAAALAADCggIFwAAAA==.Vexahalia:BAAALAAECgYICgAAAA==.',Vi='Vidus:BAAALAADCggICAAAAA==.Vilesilencer:BAAALAAECgMIAwAAAA==.Viridius:BAAALAAECgEIAQAAAA==.',Vo='Voki:BAAALAAECgIIAgAAAA==.Vosswava:BAAALAADCgIIBAAAAA==.',Wa='Walletsized:BAAALAAECgYICQAAAA==.Warzak:BAAALAAECgMIAwAAAA==.Waterswet:BAAALAADCgMIAwAAAA==.',Wh='Whateverdude:BAAALAADCgMIBgAAAA==.Whoami:BAAALAADCgMIAwAAAA==.Whytè:BAAALAAECgYICAAAAA==.',Wi='Wicketdh:BAAALAADCgMIAwABLAAECgYIEAABAAAAAA==.Wickt:BAAALAADCgYIBgABLAAECgYIEAABAAAAAA==.Wield:BAAALAAECgYIDwAAAA==.Wigeon:BAAALAAECgIIAgAAAA==.Wiickett:BAAALAAECgYIEAAAAA==.Wilbur:BAAALAADCggIEwAAAA==.Wildebeard:BAAALAAECgYICgAAAA==.Winrybell:BAAALAAECgEIAQAAAA==.',Wo='Wolfenfang:BAAALAADCggIBwAAAA==.Wondershots:BAAALAAECgMIAwAAAA==.',Wu='Wugawuga:BAAALAADCgEIAQAAAA==.',Xa='Xanesh:BAAALAADCgIIAgAAAA==.',['Xá']='Xánada:BAAALAAECgIIAwABLAAECggIGwAFAIkjAA==.',Za='Zaiel:BAAALAAECgMIBQAAAA==.Zalajin:BAAALAADCgYIBAAAAA==.Zappybains:BAAALAADCgYICQAAAA==.',Ze='Zenotter:BAAALAADCggICAAAAA==.',Zu='Zushin:BAAALAADCggICQAAAA==.',Zy='Zyllos:BAAALAAECgYICQAAAA==.',['Èl']='Èlo:BAAALAAECgcIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end