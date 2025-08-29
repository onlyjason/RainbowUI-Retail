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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Feral','Warrior-Protection','Shaman-Restoration',}; local provider = {region='US',realm='Saurfang',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acinio:BAAALAADCgEIAQAAAA==.',Ae='Aedaenia:BAAALAADCgUIBQAAAA==.',Ag='Aginakou:BAAALAADCggIDwAAAA==.Aglerion:BAAALAAECgIIAgAAAA==.',Ah='Ahlya:BAAALAAECgYIDwAAAA==.',Ai='Aimei:BAAALAAECgUICAAAAA==.Aineryn:BAAALAAECgYIDgAAAA==.Aionxz:BAAALAAECgYIDgAAAA==.Aiphaton:BAAALAAECgMIAwAAAA==.',Al='Alatreon:BAAALAAECgMIBgAAAA==.Aldavir:BAAALAADCggIDAABLAAECgcIEwABAAAAAA==.Aleseanzero:BAAALAAECgEIAQAAAA==.Alighieri:BAAALAAECgMIAwAAAA==.Alijo:BAAALAAECgUIBQAAAA==.Alinassa:BAAALAAECgQICgAAAA==.Alithraz:BAAALAADCgMIAwAAAA==.Alponyoman:BAAALAAECgYICQAAAA==.Altaira:BAAALAADCggIDAAAAA==.Alyren:BAAALAADCggICAAAAA==.',Am='Amaizen:BAAALAADCgcIEgAAAA==.Ambér:BAAALAADCgEIAQAAAA==.Amelior:BAAALAAECgUICAAAAA==.Amoro:BAAALAADCggICAAAAA==.Amorthian:BAAALAADCggIDAAAAA==.Amoth:BAAALAADCgIIAgAAAA==.Amruss:BAAALAAECgUIBQAAAA==.',An='Andykandy:BAAALAADCgQIBAAAAA==.Anela:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.Angelblaze:BAAALAADCgMIBgAAAA==.Angerbear:BAAALAAECgMIAwAAAA==.Angertotem:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Anginka:BAAALAADCggIEAAAAA==.Angkor:BAAALAADCgMIAwAAAA==.Anigme:BAAALAADCgQIBAAAAA==.Aniska:BAAALAADCgcIBwAAAA==.Annallessa:BAAALAADCgcIBwAAAA==.',Ap='Appowulf:BAAALAAECgYIDgAAAA==.',Ar='Araceae:BAAALAADCgcIBwAAAA==.Aragornne:BAAALAAECgEIAQAAAA==.Archeuz:BAAALAAECgIIAgAAAA==.Argosash:BAAALAAECgYICQAAAA==.Ariath:BAAALAAECgMIAwAAAA==.Arithrozar:BAAALAADCgcIDQAAAA==.Arjen:BAAALAAECgEIAQAAAA==.Arulli:BAAALAADCgcIBwAAAA==.',As='Ashanath:BAAALAAECgcIEwAAAA==.Ashkaa:BAAALAAECgMIAwAAAA==.Ashoda:BAAALAAECgYIDwAAAA==.Aslagosa:BAAALAADCggIDAAAAA==.Astagil:BAAALAADCgcIBwAAAA==.Astrodukes:BAAALAADCgcIDQAAAA==.',At='Atlantia:BAAALAADCgEIAQAAAA==.',Au='Augment:BAAALAADCgYIBgAAAA==.Autisticus:BAAALAADCgIIAgAAAA==.',Av='Avellar:BAAALAAECgMIBwAAAA==.Avie:BAABLAAECoEaAAICAAgIpiPQAwA6AwACAAgIpiPQAwA6AwAAAA==.',Ax='Axelfoley:BAAALAAECgEIAQAAAA==.',Az='Azraezel:BAAALAADCgcIBwAAAA==.Azstora:BAAALAAECgYIDwAAAA==.Azzinot:BAAALAADCgcICwAAAA==.',Ba='Badbreath:BAAALAADCgcICAAAAA==.Badshot:BAAALAAECgIIAgAAAA==.Baelrog:BAAALAAECgIIBAAAAA==.Ballshaft:BAAALAAECgMIBAAAAA==.Barron:BAAALAADCggIDgAAAA==.Barthom:BAAALAAECgcIEgAAAA==.Baràk:BAAALAAECgYIDgAAAA==.Battabang:BAAALAADCgEIAQAAAA==.',Be='Bearzpally:BAAALAAECgYICQAAAA==.Beatrix:BAAALAAECgMIBAAAAA==.Beerington:BAAALAAECgMIBwAAAA==.Belevoker:BAAALAAECgQICgAAAA==.Bellei:BAAALAADCgIIAgAAAA==.Belphegorr:BAAALAAECgYICgAAAA==.Bewmp:BAAALAAECgIIAgAAAA==.',Bi='Bigbirdie:BAAALAAECgEIAQAAAA==.Bigoltrollop:BAAALAAECgEIAQAAAA==.Bimbohd:BAAALAADCggIEwAAAA==.Bistavert:BAAALAADCgMIAwAAAA==.Bithel:BAAALAADCgcICQABLAAECgYICgABAAAAAA==.Bizz:BAAALAAECgMIBwAAAA==.',Bj='Bjornogal:BAAALAADCggICAAAAA==.Björnhorny:BAAALAAECggIBwAAAA==.',Bl='Blazebringer:BAAALAADCggICgAAAA==.Bleedblood:BAAALAADCgYICgAAAA==.Blinkinpark:BAAALAADCgcIDgAAAA==.Bllisster:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Bllissticks:BAAALAAECgIIAgAAAA==.Bloodhide:BAAALAADCggICAAAAA==.Blxckhollow:BAAALAAECgYICwAAAA==.',Bo='Bogus:BAAALAAECgEIAQAAAA==.Boofstofsky:BAAALAADCgYICQAAAA==.',Br='Bradsie:BAAALAAECgUICwAAAA==.Brawler:BAAALAAECgYICgAAAA==.Breakdown:BAAALAAECgcIDgAAAA==.Brewsleeroy:BAAALAAECgYIAwABLAAECgYICgABAAAAAA==.Brewslei:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.Brewtalîty:BAAALAAECgIIAgAAAA==.Briskzilla:BAAALAADCggICwAAAA==.Brownman:BAAALAADCggICwAAAA==.Brush:BAAALAAECgQICAAAAA==.Bruteroot:BAAALAADCgIIAgAAAA==.',Bt='Btkt:BAAALAADCggICAAAAA==.',Bu='Bunnyball:BAAALAADCgUIBQAAAA==.Burga:BAAALAAECgMIAwAAAA==.',By='Bytes:BAAALAAECgUIBwAAAA==.',['Bá']='Bálerion:BAAALAAECgcIBwAAAA==.',['Bä']='Bähamut:BAAALAAECgYIBwAAAA==.',['Bü']='Bünny:BAAALAADCgcIDQAAAA==.',Ca='Cachandra:BAAALAADCgYICQAAAA==.Calafiori:BAAALAAECgUICAAAAA==.',Ce='Cedricks:BAAALAADCgYIBgAAAA==.Celariviane:BAAALAADCgEIAQAAAA==.Celendra:BAAALAAECgYICAAAAA==.Celtic:BAABLAAECoEWAAIDAAgIjyDeAwDNAgADAAgIjyDeAwDNAgAAAA==.Ceredan:BAAALAADCgcIBwAAAA==.',Ch='Challisa:BAAALAAECgcIDgAAAA==.Charnaby:BAAALAAECgYICQAAAA==.Charnibald:BAAALAADCgcIBwAAAA==.Chellê:BAAALAAECgQIBgAAAA==.Chepuha:BAAALAADCgcIBwAAAA==.Chezzaa:BAAALAAECgcIDwAAAA==.Chicknburgah:BAAALAAECgYIBwAAAA==.Chinchanzu:BAAALAADCgcIBwAAAA==.Chorim:BAAALAAECgMIAwAAAA==.Chovabub:BAAALAAECggIAQAAAA==.Chunks:BAAALAAECgcICwAAAA==.Chuzz:BAAALAAECgEIAQAAAA==.',Ci='Cia:BAAALAADCgcIBwAAAA==.Ciaras:BAAALAADCgEIAQAAAA==.Cigar:BAAALAAECgMIAwAAAA==.Circus:BAAALAAECgMIBgAAAA==.Civil:BAAALAADCgUIAwAAAA==.',Cl='Clarc:BAAALAAECgQIBgABLAAECgcIDwABAAAAAA==.Clánker:BAAALAAECgEIAQAAAA==.',Co='Cobólt:BAAALAAECgQIBAAAAA==.Coldshower:BAAALAADCgQIBAAAAA==.Comêt:BAAALAADCgUIBQAAAA==.Convoy:BAAALAAECgIIAgAAAA==.Coornholio:BAAALAAECgIIAgAAAA==.Corte:BAAALAAECgQIBQAAAA==.',Cp='Cptnovna:BAAALAADCgYIDwAAAA==.',Cr='Crazedorc:BAAALAAECgcICwAAAA==.Creambun:BAAALAAECgMIAwAAAA==.Crimie:BAAALAADCgMIAwAAAA==.Croescrane:BAAALAAECgQICAAAAA==.Crooked:BAAALAAECgUICAAAAA==.Crossblessër:BAAALAAECgMIAwAAAA==.Crownclown:BAAALAAECgYICQAAAA==.Cruella:BAAALAADCgcIDgABLAAECgYIBwABAAAAAA==.',Cu='Cummo:BAAALAADCgMIAwAAAA==.',Cv='Cvmsock:BAAALAADCggICAAAAA==.',Cy='Cyclone:BAAALAAECgMIAwAAAA==.Cynthus:BAAALAAECgYIDgAAAA==.',['Cé']='Cérberus:BAAALAAECgYICQAAAA==.',Da='Dainashi:BAAALAADCgcIBwAAAA==.Daki:BAAALAADCgYIDwAAAA==.Damisia:BAAALAAECgMIBQAAAA==.Damstraight:BAAALAAECgIIAgAAAA==.Darksox:BAAALAAECgIIAwAAAA==.Daylisha:BAAALAAECgMIBgAAAA==.Dayn:BAAALAAECgEIAQAAAA==.Dazzles:BAAALAAECgQIBgAAAA==.Daïsy:BAAALAAECgIIAgAAAA==.',De='Deablohuntsu:BAAALAADCggIDwAAAA==.Deabloknight:BAAALAADCgcIBwAAAA==.Deablosdemon:BAAALAAECgIIAgAAAA==.Deadrose:BAAALAADCgIIAgAAAA==.Deathfromozz:BAAALAAECgMIAwAAAA==.Deathraider:BAAALAADCgYICwAAAA==.Demmy:BAAALAADCgMIAwAAAA==.Demongasher:BAAALAADCgcIDQAAAA==.Derk:BAAALAADCggIDgAAAA==.Desdeydra:BAAALAADCgYIBgAAAA==.Dessane:BAAALAAECgQIBwAAAA==.Deviantall:BAABLAAECoEZAAICAAgIPCMgBwALAwACAAgIPCMgBwALAwAAAA==.Devpriest:BAAALAAECgQIBAAAAA==.',Di='Diessel:BAAALAADCgMIAwAAAA==.Dijonshammy:BAAALAAECgMIBAAAAA==.Diora:BAAALAAFFAIIAgAAAA==.Dishdruid:BAAALAADCggIBgABLAAECgcICQABAAAAAA==.Dishman:BAAALAAECgcICQAAAA==.Divineon:BAAALAAECgcIDwAAAA==.Diéthyl:BAAALAADCggIDAAAAA==.',Dj='Dj:BAAALAAECgQIBgAAAA==.',Dl='Dlymea:BAAALAAECgEIAQAAAA==.',Do='Dominationn:BAAALAAECgYICQAAAA==.Dominusjéjé:BAAALAADCggIEAAAAA==.Doncoggy:BAAALAAECgYIDgAAAA==.Donfandangle:BAAALAAECgMIAwAAAA==.Donkeykongg:BAAALAAECggIEwAAAA==.Doomadin:BAAALAAECgYIDgAAAA==.Dora:BAAALAAECgYICAAAAA==.Dovarkin:BAAALAADCgcIDwAAAA==.',Dr='Dracthyrial:BAAALAADCgcIBwAAAA==.Draghit:BAAALAADCgcIDAABLAAECggIFgAEAE0VAA==.Dragmire:BAAALAADCgYIBgAAAA==.Dragritto:BAAALAAECgYIBgAAAA==.Dragsnek:BAABLAAECoEWAAMEAAgITRXHDwAlAgAEAAcIChfHDwAlAgAFAAQIFglJDQDoAAAAAA==.Dragöndeez:BAAALAAECgcIEgAAAA==.Draiky:BAAALAAECgMIBwAAAA==.Draykora:BAAALAAECgIIAgAAAA==.Dreambreaker:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Drekthedk:BAAALAAECgMIBgAAAA==.Drifthammer:BAAALAADCgQIAgAAAA==.Driptrayy:BAAALAADCggICAAAAA==.Drmat:BAAALAAECgMIBQAAAA==.Drmax:BAAALAADCggIEAAAAA==.Dropkick:BAAALAADCggIEQAAAA==.Drppdatbirth:BAAALAAECgEIAQAAAA==.Druïd:BAAALAADCgIIAgAAAA==.Dryath:BAAALAADCgcIDAAAAA==.',Du='Durtty:BAAALAADCggIFwAAAA==.',Dw='Dwarfslaya:BAAALAADCgEIAQAAAA==.',Dy='Dylme:BAAALAADCgYIBgAAAA==.Dynó:BAAALAAECgYIDwAAAA==.',Ea='Easyflow:BAAALAAECgMIAwAAAA==.',Ei='Eiluaq:BAAALAADCggIDAAAAA==.',El='Elcrabbette:BAAALAAECgEIAQAAAA==.Eledrip:BAAALAADCggIEAAAAA==.Elegant:BAAALAAECgYICQAAAA==.Eleviozs:BAAALAADCgEIAQAAAA==.Elfmon:BAAALAADCgQIBAAAAA==.Elilgosa:BAAALAADCgUIBQAAAA==.Elillor:BAAALAADCgMIAwAAAA==.Ellatrix:BAAALAADCggIDwAAAA==.Elundara:BAAALAAECgYIDgAAAA==.Elunedara:BAAALAADCgcIDAAAAA==.',Es='Estardra:BAAALAAECgYIBgAAAA==.',Et='Ethot:BAAALAADCgcIBwAAAA==.',Ev='Evaporate:BAAALAAECgIIAgAAAA==.Everlei:BAAALAAECgYIDgAAAA==.Eviely:BAAALAAECgEIAQAAAA==.Evilmoofasá:BAAALAAECgYIDQAAAA==.Evilnattie:BAAALAAECgYIDAAAAA==.',Ex='Exiledpally:BAAALAADCggIDQAAAA==.Exorcis:BAAALAAECgEIAQAAAA==.',Ez='Ezle:BAAALAADCgcIBwAAAA==.',['Eã']='Eãrthen:BAAALAADCgMIAwAAAA==.',Fa='Falcanis:BAAALAADCggIDwAAAA==.Fangster:BAAALAAECgcICQAAAA==.Faniel:BAAALAAECgYICQAAAA==.Faranight:BAAALAAECgEIAQAAAA==.',Fe='Feara:BAAALAADCgUIBQAAAA==.Feistyfist:BAAALAAECgMIAwAAAA==.Feloney:BAAALAAECgMIAwAAAA==.Fengliu:BAAALAAECgcIEgAAAA==.',Fi='Fiamma:BAAALAADCggICAAAAA==.Fieryroota:BAAALAAECgYIDgAAAA==.Filthwizard:BAAALAADCggIFAAAAA==.Filthyfred:BAAALAAECgIIAwAAAA==.Finalbreath:BAAALAADCgYIBgAAAA==.Findewin:BAAALAAECgUICAAAAA==.Fingerfart:BAAALAAECgIIAgAAAA==.Finsotjun:BAAALAADCgIIAgAAAA==.Fionoria:BAAALAADCggICAAAAA==.Fiyerite:BAAALAAECgcIDgAAAA==.',Fl='Flameeater:BAAALAAECgYICQAAAA==.Fleehzy:BAAALAADCggICAAAAA==.Flickademon:BAAALAADCgcIBwAAAA==.Fluffpaw:BAAALAADCggICQAAAA==.Flynnyzyzz:BAAALAAECgYIDgAAAA==.',Fo='Forcain:BAAALAADCgYIBgAAAA==.Fozzyy:BAAALAADCgcICQAAAA==.',Fr='Frood:BAAALAAECgMIBQAAAA==.',Fu='Fuzzlicia:BAAALAAECgMIAwAAAA==.',Fy='Fyaha:BAAALAAECgIIAgAAAA==.',['Fä']='Fätboy:BAAALAAECgQICQAAAA==.',Ga='Galanthae:BAAALAAECgEIAQABLAAECgcIEwABAAAAAA==.Galawain:BAAALAAECgYIBgAAAA==.Galeidan:BAAALAAECgUICAAAAA==.Gamumush:BAAALAAECgYICgAAAA==.Gamush:BAAALAADCgcIBwAAAA==.Gandlemian:BAAALAADCgYICAAAAA==.Gargola:BAAALAAECgYICQAAAA==.Garntek:BAAALAAECgQIBgAAAA==.Gastoon:BAAALAADCggICgAAAA==.',Gi='Gilletté:BAAALAAECgQIBwAAAA==.Gistos:BAAALAADCgcIBwAAAA==.',Go='Gorag:BAAALAADCgMIAwAAAA==.Gotno:BAACLAAFFIEFAAIGAAMIjAXsAQDKAAAGAAMIjAXsAQDKAAAsAAQKgRgAAgYACAjQGbkHAFQCAAYACAjQGbkHAFQCAAAA.Gotsalt:BAAALAAECgYIDgAAAA==.',Gr='Greendoor:BAAALAAECgMIBgAAAA==.Greenfox:BAAALAADCgYIBgAAAA==.Grender:BAAALAADCgcIEgAAAA==.Grimmeye:BAAALAAECgUICAAAAA==.Grinbar:BAAALAADCgUIAQABLAADCggIEwABAAAAAA==.Grindblast:BAAALAADCggIBwAAAA==.Grindfrost:BAAALAAECgcICgAAAA==.Gripmedaddy:BAAALAAECgYIDgAAAA==.',['Gì']='Gìggitty:BAAALAADCggIDwAAAA==.',['Gø']='Gødslapp:BAAALAAECgIIAgAAAA==.',Ha='Hagenthehorn:BAAALAADCgUIBQAAAA==.Hakega:BAAALAADCggIAgAAAA==.Halliday:BAAALAAECgMIAwAAAA==.Hapax:BAAALAAECgYICgAAAA==.Harrowhark:BAAALAAECgMIAwAAAA==.Hasrin:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.Hastas:BAAALAADCgYICgAAAA==.Hatchi:BAAALAAECgIIAgAAAA==.Haxxor:BAAALAAECgEIAQAAAA==.',He='Headbeegirl:BAAALAADCgEIAQAAAA==.Healiia:BAAALAAECgYIDgAAAA==.Helenaj:BAAALAAECgMIBAAAAA==.Hellà:BAAALAAECgIIAgAAAA==.Helynna:BAAALAADCgYIBgAAAA==.Hendo:BAAALAAECgQIBgAAAA==.Herar:BAAALAADCggIEQAAAA==.Hexecuted:BAAALAAECgMIBAAAAA==.Heyyaits:BAAALAAECgYICQAAAA==.',Hi='Hikahi:BAAALAAECgMIBAAAAA==.Himbee:BAAALAADCgYIBwABLAADCgcIDAABAAAAAA==.Himborage:BAAALAADCgMIBAABLAADCgcIDAABAAAAAA==.Himbrew:BAAALAADCgcIDAAAAA==.Hishoko:BAAALAADCggICwAAAA==.',Hm='Hmaltyy:BAAALAAECgIIAgAAAA==.',Ho='Holdmyballz:BAAALAAECgYIDAAAAA==.Holyshiet:BAAALAAECgEIAQAAAA==.Holystorm:BAAALAADCgUIBQAAAA==.Holytankk:BAAALAADCgcIBwAAAA==.Hotstreakqt:BAAALAAECgMIAwAAAA==.Howdowhodo:BAAALAAECgEIAgAAAA==.',Hr='Hreeza:BAAALAAECgMIAwAAAA==.',Hu='Hugall:BAAALAAECgYICAAAAA==.Hunin:BAAALAAECgQIBAAAAA==.Huntingjohn:BAAALAAECgIIAwAAAA==.Huntly:BAAALAADCggIDgAAAA==.Huntsketchup:BAAALAAECgMIAgAAAA==.Huntssy:BAAALAAECgQICAAAAA==.',Hw='Hwired:BAAALAAECgcIBwAAAA==.',Hy='Hyori:BAAALAADCgUIBQAAAA==.Hypersleep:BAAALAAECgQIBgAAAA==.',Hz='Hz:BAAALAADCggIEAAAAA==.',['Hà']='Hàuntress:BAAALAADCgcICwAAAA==.',['Hâ']='Hâxxor:BAAALAAECgMIAgAAAA==.',['Hé']='Héstia:BAAALAADCgYIDAAAAA==.',['Hö']='Hötnhòrdey:BAAALAAECgMIBgAAAA==.',['Hø']='Høstile:BAAALAAECgMIAwAAAA==.',Ik='Ikoré:BAAALAADCgcIBwAAAA==.',Il='Ilishot:BAAALAADCggIEAAAAA==.Illiidann:BAAALAAECgMIAwAAAA==.',Im='Imaginative:BAAALAAECgUIAgAAAA==.Imcooked:BAAALAAECgUIAgAAAA==.Imladrisse:BAAALAADCgcIEgAAAA==.',In='Inamoonstar:BAAALAADCgcIAwAAAA==.Iny:BAAALAAECgMIBgAAAA==.',Ip='Ipangoo:BAAALAADCgUICAAAAA==.',Ir='Iradra:BAAALAADCggICwAAAA==.Ironboar:BAAALAAECgYICAAAAA==.Ironfistt:BAAALAAECgQIAwAAAA==.Ironmage:BAAALAAECgIIAgAAAA==.',Is='Ishellheal:BAAALAAECgYICQAAAA==.',It='Itsgroot:BAAALAADCgMIBQAAAA==.',Iv='Ivamoonstar:BAAALAADCgcICAAAAA==.',Iy='Iyoppy:BAAALAADCgEIAQAAAA==.',Ja='Jademender:BAAALAAECgYIBgAAAA==.Jagoanneon:BAAALAAECgMIBQAAAA==.Jamak:BAAALAAECgMIBAAAAA==.Jammychan:BAAALAAECgMIBgAAAA==.Jasireth:BAAALAAECgcIEgAAAA==.Jaylanda:BAAALAAECgYICQAAAA==.',Je='Jebilitus:BAAALAAECgcIDQAAAA==.Jedwarus:BAAALAAECgYICgAAAA==.Jelia:BAAALAAECgYIDgAAAA==.Jelwar:BAAALAADCgcIBwAAAA==.Jelya:BAAALAAECgMIAwAAAA==.Jelyah:BAAALAADCgYIBwAAAA==.Jerô:BAAALAAECgIIAgABLAAECgMIBAABAAAAAA==.',Jf='Jf:BAAALAADCggICAAAAA==.',Jh='Jhandles:BAAALAAECgIIBAAAAA==.',Jo='Johnbones:BAAALAAECgMIBAAAAA==.Jojowood:BAAALAADCgIIBAAAAA==.Jones:BAAALAADCggICQAAAA==.Jorgie:BAAALAADCggIDwABLAAECgYIBgABAAAAAA==.',Js='Jsultry:BAAALAADCggICAAAAA==.',Ju='Juicewrld:BAAALAAECgQIBAAAAA==.Jujubug:BAAALAADCgYIBgAAAA==.Jungchi:BAAALAAECgMIBAAAAA==.Junior:BAAALAAECgYICQAAAA==.',['Jú']='Júdgemental:BAAALAADCgYIBwAAAA==.',Ka='Kakana:BAAALAAECgUICAAAAA==.Kalleii:BAAALAADCggICAAAAA==.Kamatiz:BAAALAADCggICAAAAA==.Kandals:BAAALAADCgcIBwAAAA==.Kanehammer:BAAALAADCgcIBwAAAA==.Kariala:BAAALAAECgYIDAAAAA==.Katilaine:BAAALAAECgMIAwAAAA==.Katiyana:BAAALAAECgIIAgAAAA==.',Ke='Kedaelia:BAAALAADCgIIAgAAAA==.Keilanea:BAAALAADCggIDwAAAA==.Keksiq:BAAALAAECgYIDwAAAA==.Keys:BAAALAADCgMIAwAAAA==.',Kh='Khurs:BAAALAAECgcICgAAAA==.',Ki='Kiadiasundon:BAAALAAECgMIAgAAAA==.Kidfork:BAAALAAECgMIAwAAAA==.Kilataris:BAAALAAECgIIAwAAAA==.Killahurty:BAAALAAECgMIBAAAAA==.Killarharpy:BAAALAADCgMIAwABLAAECgMIBAABAAAAAA==.Killjòy:BAAALAADCgcIBwAAAA==.Kinesra:BAAALAAECgMIBAAAAA==.Kiralia:BAAALAAECgYIDgAAAA==.Kirigolmer:BAAALAAECgMIBQAAAA==.Kirygosa:BAAALAADCgYIBwAAAA==.',Kl='Klobey:BAAALAAECgEIAQAAAA==.',Kn='Kngleonidas:BAAALAAECgMIAgAAAA==.Knivver:BAAALAAECgIIAgAAAA==.',Ko='Koberin:BAAALAADCgIIAgAAAA==.Kodiakjack:BAAALAADCgcIAgAAAA==.Kou:BAAALAAECgYIDgAAAA==.',Kr='Krash:BAAALAAECgcIDAAAAA==.Krazan:BAABLAAECoEWAAMEAAgITRyfCAChAgAEAAgIGBufCAChAgAFAAMIhgjpEACYAAAAAA==.',Ku='Kulvetaroth:BAAALAAECgEIAQAAAA==.Kushie:BAAALAAECgMIBgAAAA==.',['Ká']='Kál:BAAALAAECgMIBgAAAA==.',La='Lagger:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Lagock:BAAALAAECgMIAwAAAA==.Lancaran:BAAALAAECgMIAgAAAA==.Laydeekimii:BAAALAADCgcIBwAAAA==.',Le='Learia:BAAALAADCggICAAAAA==.Learris:BAAALAAECgMIBgAAAA==.Lerazure:BAAALAADCggIDwAAAA==.',Li='Lickyy:BAAALAAECgMIBgAAAA==.Lildoki:BAAALAAECgYIDAAAAA==.Lilmis:BAAALAAECgUIBQAAAA==.Lilnyte:BAAALAADCgYIBgAAAA==.Lissuin:BAAALAAECgUICQAAAA==.',Lo='Locnár:BAAALAAECgQIBgAAAA==.Loeth:BAAALAADCgIIAgAAAA==.Logosh:BAAALAADCgcIBwAAAA==.Lollobionda:BAAALAAECgMIBgAAAA==.Lolxsorzz:BAAALAAECgUICAAAAA==.Loono:BAAALAAECgEIAQAAAA==.Loopholes:BAAALAADCggIDwAAAA==.',Lu='Lulingqï:BAAALAAECgMIAgAAAA==.Luminei:BAAALAAECgYICwAAAA==.Lurii:BAAALAAECggIEAAAAA==.Lushiann:BAAALAAECgMIAwAAAA==.Lutz:BAAALAAECgQIBgAAAA==.',Ly='Lyfedruid:BAAALAADCgcIBwAAAA==.Lysithea:BAAALAADCgYIBgAAAA==.Lyter:BAAALAAECgEIAQAAAA==.Lythane:BAAALAADCgQIBAAAAA==.Lythorn:BAAALAAECgMIAwAAAA==.',['Lù']='Lùffy:BAAALAAECgQICAAAAA==.',Ma='Macetro:BAAALAADCggIDQAAAA==.Mackyla:BAAALAADCggICAABLAAECgMIBwABAAAAAA==.Mafdett:BAAALAAECgEIAQAAAA==.Magnella:BAAALAADCggICAAAAA==.Magneric:BAAALAAECgEIAQAAAA==.Magnis:BAAALAADCgMIAwAAAA==.Mahimahi:BAAALAAECgYIDgAAAA==.Mamasboi:BAAALAADCggIDwAAAA==.Manicmoose:BAAALAADCgcICwAAAA==.Mantova:BAAALAAECgYICgAAAA==.Marapi:BAAALAADCggIFAAAAA==.Margolotta:BAAALAAECgIIAwAAAA==.Masiath:BAAALAADCgcICgAAAA==.Matthxw:BAAALAAECgcIDwAAAA==.Mavaria:BAAALAADCggICAAAAA==.Mayohunter:BAAALAAECgMIBAAAAA==.',Mc='Mcbain:BAAALAAECgIIAgAAAA==.',Md='Mdoctor:BAAALAADCgYIBwAAAA==.',Me='Melwyn:BAAALAADCgcIDAAAAA==.Melyara:BAAALAAECgYICQAAAA==.Mezzelune:BAAALAADCgcIDAAAAA==.',Mg='Mgunit:BAAALAAECgYICQAAAA==.',Mi='Miikehunt:BAAALAADCgcIEgAAAA==.Mikotö:BAAALAAECgQICAAAAA==.Milkyjoe:BAAALAAECgUICgAAAA==.Milkymaid:BAAALAAECgMIAwABLAAECgMIBgABAAAAAA==.Milkyprayed:BAAALAAECgMIBgAAAA==.Miriath:BAAALAAECgEIAQAAAA==.Mirielle:BAAALAAECgMIBQAAAA==.Miserable:BAAALAAECgIIBAAAAA==.Mithraswarr:BAAALAADCgcIBwABLAADCggIFAABAAAAAA==.',Mo='Modigularna:BAAALAAECgIIAgAAAA==.Mollydooker:BAAALAADCggIEAAAAA==.Mollydookerr:BAAALAADCgUIBQAAAA==.Momordika:BAAALAAECgQIBAAAAA==.Monglin:BAAALAAECgIIAgAAAA==.Monkess:BAAALAADCgYIBgAAAA==.Monkeymagick:BAAALAAECgUICAAAAA==.Monkguru:BAAALAAECgMIBAAAAA==.Moogli:BAAALAAECgMIAwAAAA==.Mooneymooney:BAAALAADCgcIDAAAAA==.Morbidfetus:BAAALAADCgYIBgAAAA==.Morganfree:BAAALAADCggICAABLAADCggICwABAAAAAA==.Morgothian:BAAALAAECgUIBwAAAA==.Morrizman:BAAALAADCggIDwAAAA==.Mortarkye:BAAALAAECgUICAAAAA==.Mortira:BAAALAAFFAIIAgAAAA==.Morzierz:BAAALAAECgUICAAAAA==.Mouldycashew:BAAALAAECgMIAwAAAA==.',Ms='Mstrodemon:BAAALAAECgYIDQAAAA==.',Mu='Mudduck:BAAALAAECgYICgAAAA==.Muffdivein:BAAALAADCgYIBgAAAA==.Mulder:BAAALAADCgQIAgAAAA==.',My='Mymistyboo:BAAALAAECgIIAgAAAA==.Mythdolas:BAAALAADCgUIBQAAAA==.',['Mé']='Mécouilles:BAAALAAECgMIAwAAAA==.',['Më']='Mëphistò:BAAALAAECgIIAgAAAA==.',Na='Nadariä:BAAALAADCgcIDAAAAA==.Naguala:BAAALAAECgEIAQAAAA==.Nailahpriest:BAAALAAECgMIAwAAAA==.Nascia:BAAALAADCgcIEAAAAA==.Nasmiange:BAAALAADCgcICAAAAA==.Natocomander:BAAALAAECgEIAQAAAA==.Natsumi:BAAALAADCgcIBwABLAAECgcIDgABAAAAAA==.Navimie:BAEALAAECgUICAAAAA==.',Ne='Neerzul:BAAALAADCgMIAgAAAA==.',Nh='Nhael:BAAALAAECgEIAQAAAA==.',Ni='Nialdo:BAAALAAECgYICgAAAA==.Nihilism:BAAALAADCgYIBgAAAA==.Nineveh:BAAALAAECgMIBAAAAA==.Nisefayth:BAAALAAECgYICQAAAA==.Niterix:BAAALAAECggIAwAAAA==.',No='Nocturnè:BAAALAAECgIIAgAAAA==.Nookislice:BAAALAADCgQIBgAAAA==.Northmand:BAAALAAECgYIDAAAAA==.',Nu='Nunueggplant:BAAALAADCgcICAAAAA==.Nurani:BAAALAADCgcICQAAAA==.',['Nà']='Nàmewastaken:BAAALAAECgMIAwAAAA==.Nàmewàstaken:BAAALAAECgEIAQAAAA==.',['Nâ']='Nârissâ:BAAALAAECgEIAQAAAA==.',['Ní']='Níls:BAAALAAECgMIBAAAAA==.',Ob='Obake:BAAALAAECgMIAwAAAA==.Obamalives:BAAALAAECgEIAQAAAA==.Obseen:BAAALAADCggIDwAAAA==.Obsoleet:BAAALAAECgMIBwAAAA==.',Ol='Olderhoreath:BAAALAAECgMIBAAAAA==.Olderion:BAAALAADCgEIAQAAAA==.Oldtimér:BAAALAADCgcICgAAAA==.',On='Oneofmany:BAAALAADCgYIBgAAAA==.Onikage:BAAALAAECgYIDAAAAA==.Onitaniwha:BAAALAADCgcIBwAAAA==.Onlyfrends:BAAALAAECgUICAAAAA==.',Op='Opfotmjr:BAAALAADCgUIBQAAAA==.',Ot='Otl:BAAALAAECgMIAwAAAA==.',Ov='Overt:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Overtqt:BAAALAAECgYICAAAAA==.',Pa='Palargo:BAAALAADCgQIBAAAAA==.Pallyative:BAAALAAECgMIAgAAAA==.Palomar:BAAALAAECgEIAQAAAA==.Palyplegic:BAAALAADCggIBgAAAA==.Pancake:BAAALAAECgUIBwAAAA==.Panoramix:BAAALAAECgYIDgAAAA==.Para:BAABLAAECoEVAAQHAAgIziQ3AQCmAgAHAAcIPCU3AQCmAgAIAAUIaCMbEwDpAQAJAAUI1B54MQB2AQAAAA==.Paulson:BAAALAADCggIDwAAAA==.',Pe='Peepeedemon:BAAALAAECgYICgAAAA==.Peepeedemons:BAAALAAECgIIAgAAAA==.Petitenova:BAAALAADCgQIBAAAAA==.Pewpews:BAAALAAECgYIBwAAAA==.',Pi='Piki:BAAALAAECgEIAQAAAA==.Pilsam:BAAALAAECgUIBwAAAA==.Pinkfluf:BAAALAAECgMIAwAAAA==.Pisspriest:BAAALAADCgUIBQABLAAECggIFQAHAM4kAA==.',Pk='Pk:BAABLAAECoEYAAMEAAgIYCJ+BAD6AgAEAAgIHyB+BAD6AgAFAAIIKhz3EACXAAAAAA==.',Pl='Plslemmehit:BAAALAADCgcIBwAAAA==.Plutoorouge:BAAALAAECgQICQAAAA==.',Po='Poundtownbus:BAAALAAECgMIAwAAAA==.',Pr='Prey:BAAALAAECgYIDgAAAA==.Primàl:BAAALAAECgMIAwAAAA==.Prottozoa:BAAALAADCggIDgAAAA==.',Pt='Pthaummaghus:BAAALAAECgYIBgAAAA==.',Pu='Purrpleelff:BAAALAAECgQICwAAAA==.',['Pé']='Péndekar:BAAALAAECgMIBgAAAA==.',['Pö']='Pöë:BAAALAADCggICAAAAA==.',Ql='Ql:BAAALAAECgMIAwAAAA==.',Qu='Quazievil:BAAALAAECgcIEQAAAA==.Queeshi:BAAALAADCgcIEgAAAA==.Quick:BAAALAAECgQIBgAAAA==.',Ra='Raghoof:BAAALAAECgMIAwAAAA==.Ragilas:BAAALAAECgYICQAAAA==.Ragilus:BAAALAAECgcIDQAAAA==.Rainz:BAAALAAECgMIBgAAAA==.Rambro:BAAALAAECgMIBwAAAA==.Rameel:BAAALAAECgEIAQAAAA==.Ranfin:BAAALAAECgMIAwABLAAECgMIBQABAAAAAA==.Raph:BAAALAADCggICQAAAA==.Raptace:BAAALAAECgIIAwAAAA==.Ravalt:BAAALAADCgYIDwAAAA==.Ravindrannor:BAAALAADCggIDQAAAA==.Rawkalot:BAAALAADCggIDwAAAA==.Rayoong:BAAALAAECgEIAQAAAA==.Razorded:BAAALAADCgYIBgAAAA==.Razorsledge:BAAALAADCggIGAAAAA==.Razukar:BAAALAAECgYIBgAAAA==.Razzles:BAAALAAECgcIDgAAAA==.',Re='Reeshar:BAAALAADCgcIDQAAAA==.Rena:BAAALAADCggIDwAAAA==.Renaus:BAAALAAECgMIAwAAAA==.Rendorei:BAAALAAECgEIAQAAAA==.Repolyo:BAAALAAECgYIDAAAAA==.Ress:BAAALAAECgEIAQAAAA==.',Ri='Rina:BAAALAADCggIBwABLAAECgcIDgABAAAAAA==.Rissla:BAAALAAECgMIBgAAAA==.Rizz:BAAALAAECgEIAgAAAA==.',Ro='Robbington:BAAALAAECgEIAQAAAA==.',Ru='Rubyrage:BAAALAADCgIIAgAAAA==.Rumblybear:BAAALAAECgQIBwAAAA==.Ruthia:BAAALAAECgQICAAAAA==.',Ry='Ryogen:BAAALAAECgQIBgAAAA==.Ryujìn:BAAALAAECgMIBwAAAA==.',['Rà']='Ràndomhero:BAAALAAECgEIAQAAAA==.',['Rá']='Ráka:BAAALAAECgEIAQAAAA==.',Sa='Sabretoothed:BAAALAAECgUIBQAAAA==.Safaitmal:BAAALAAECgMIBAAAAA==.Saifere:BAAALAAECgQIBQAAAA==.Samonki:BAAALAAECgcIDAAAAA==.Samvicious:BAAALAADCgcIBwAAAA==.Santera:BAAALAAECgEIAQAAAA==.Sardorer:BAAALAAECgQIBgAAAA==.Sareille:BAAALAADCgcIDAAAAA==.Satire:BAAALAAECgEIAQAAAA==.Savriel:BAAALAAECgYIDAAAAA==.',Sc='Scaffmanjohn:BAAALAADCgcICwAAAA==.Scathfiach:BAAALAADCgcIBwAAAA==.Scentless:BAAALAAECgIIAgAAAA==.Scratchies:BAAALAAECgYIDwAAAA==.Scrêwêdûp:BAAALAAECgQIBQAAAA==.Scyler:BAAALAAECgIIAgAAAA==.',Se='Seb:BAABLAAECoEVAAIKAAgIZiVFAABpAwAKAAgIZiVFAABpAwAAAA==.Selaine:BAAALAADCggIFAAAAA==.Seltic:BAAALAAECgEIAQAAAA==.Senjougahara:BAAALAAECgEIAQAAAA==.',Sg='Sgtsquat:BAABLAAECoEVAAILAAgIBhfQCwDeAQALAAgIBhfQCwDeAQAAAA==.',Sh='Shadowthief:BAAALAAECgYIDgAAAA==.Shaetore:BAAALAAECgYIDAAAAA==.Shamplet:BAAALAAECgMIAwAAAA==.Shaokarne:BAAALAADCgcIDAAAAA==.Shar:BAAALAADCgYIDAAAAA==.Sharaginix:BAAALAAECgEIAQAAAA==.Sharmtor:BAAALAAECgYIDgAAAA==.Shauthra:BAAALAADCgcICgAAAA==.Shedra:BAAALAADCgUIBQAAAA==.Sheetywok:BAAALAADCgcIBwAAAA==.Shellstalker:BAAALAADCgEIAQABLAAECgYICQABAAAAAA==.Shieldbreaka:BAAALAADCgcIBwAAAA==.Shieldcorpse:BAAALAAECggICQAAAA==.Shiftytoe:BAAALAADCgUIBQAAAA==.Shin:BAAALAADCgcIDgAAAA==.Shini:BAAALAAECgIIAgAAAA==.Shiné:BAAALAAECgMIBgAAAA==.Shockale:BAAALAADCggIBgAAAA==.Shockavin:BAAALAADCggICQAAAA==.Shokkati:BAAALAADCgYIBgAAAA==.Shyften:BAAALAADCgcICwAAAA==.Shyftzilla:BAAALAAECgIIAgAAAA==.Shåmanigans:BAAALAADCgUIBQABLAADCgcIBwABAAAAAA==.Shô:BAAALAAECgMIBgAAAA==.',Si='Sidis:BAAALAAECgQICgABLAAECgQICgABAAAAAA==.Sife:BAAALAAECgMIBAAAAA==.Sifear:BAAALAADCggICAABLAAECgQIBQABAAAAAA==.Silvox:BAAALAAECgMIBQAAAA==.Singkamaz:BAAALAADCgcIBwAAAA==.',Sk='Skanktank:BAAALAAECgMICQAAAA==.Skathlok:BAAALAAECgYICwAAAA==.Skest:BAAALAAECgIIAgAAAA==.Skills:BAAALAADCggIIQAAAA==.Skragrott:BAAALAAECgcIEwAAAA==.Skybomb:BAAALAAECgYIDgAAAA==.Skyvoker:BAAALAADCgMIAwAAAA==.',Sl='Slavryx:BAAALAAECgMIAwAAAA==.',Sm='Smegiest:BAAALAAECggIAwAAAA==.Smolpox:BAAALAADCgYIBgAAAA==.Smuggle:BAAALAADCgcIDAAAAA==.',Sn='Snack:BAAALAADCggICAAAAA==.Snarfèy:BAAALAAECgQICAAAAA==.Sneaksz:BAAALAAECgcIBwAAAA==.Snorbix:BAAALAADCgMIAwAAAA==.Snârfey:BAAALAADCgMIAwAAAA==.',So='Sofapaladin:BAAALAAECgQICgAAAA==.Solaras:BAAALAADCgcIBwAAAA==.Soondead:BAAALAADCggIFwAAAA==.Sormo:BAAALAAECgIIAgAAAA==.Sorrybud:BAAALAADCgUIBQABLAADCggICgABAAAAAA==.Soulkeepa:BAAALAAECgIIAgAAAA==.Soulsmf:BAAALAADCgcIBwAAAA==.',Sp='Speeddevil:BAAALAAECgQICgAAAA==.Speiluhr:BAAALAAECgMIAwAAAA==.Sphinxydh:BAAALAADCggICAABLAADCggICwABAAAAAA==.Sphinxymage:BAAALAADCggICwAAAA==.Spuddy:BAAALAAECgEIAQAAAA==.Spudribution:BAAALAAECgIIAgAAAA==.',St='Stakka:BAAALAADCgYIBwAAAA==.Stalaris:BAAALAAECgMIBAAAAA==.Stalgic:BAAALAAECgIIAgABLAAECgMIBAABAAAAAA==.Staraverus:BAAALAADCggICAAAAA==.Starshopping:BAAALAAECgEIAQAAAA==.Stevehound:BAAALAADCgIIAgAAAA==.Stockyx:BAAALAAECgMIAwAAAA==.Stormtotem:BAAALAADCgYIDQAAAA==.Strikebam:BAAALAAECgYIDAAAAA==.Sturdy:BAAALAADCgYICgAAAA==.',Su='Sudowoodo:BAAALAAECgYICQAAAA==.Sugarkane:BAAALAAECgEIAgAAAA==.Sunila:BAAALAAECgYIDgAAAA==.Suntigerr:BAAALAAECgMIBQAAAA==.Superevan:BAABLAAECoEXAAIJAAgIESPlAgBBAwAJAAgIESPlAgBBAwAAAA==.Superhanz:BAAALAAECgUIBwAAAA==.',Sw='Sweetkritty:BAAALAADCgcIEgAAAA==.Sweetmemeboy:BAAALAADCggIFgAAAA==.',Sy='Sylvias:BAAALAADCggIEAABLAAECgIIAwABAAAAAA==.Syrend:BAAALAAECgMIBAAAAA==.',['Sé']='Séhkmet:BAAALAAECgMIBAAAAA==.',Ta='Taffatups:BAAALAADCgcIEgAAAA==.Takagar:BAAALAAECgIIAgAAAA==.Tallgnome:BAAALAADCgYIBgAAAA==.Talrak:BAAALAADCgEIAQABLAAECgMIAwABAAAAAA==.Talus:BAAALAADCggICAAAAA==.Tamayura:BAAALAAECgYIBgAAAA==.Tandreyne:BAAALAAECgQICQAAAA==.Tankärd:BAAALAAECgQICAAAAA==.Tanwa:BAAALAAECgcIEwAAAA==.Tanwamagi:BAAALAADCggIFgAAAA==.Targetedass:BAAALAADCgYICQAAAA==.Tartare:BAAALAADCgcIEgAAAA==.Tasindra:BAAALAADCggIDwAAAA==.Tatopants:BAAALAAECgEIAQAAAA==.',Te='Tena:BAAALAAECgMIAwAAAA==.Tenoftowers:BAAALAAECgcICgAAAA==.Tenticool:BAAALAADCgMIAwAAAA==.Teranzil:BAAALAADCggICwABLAAECgMIBwABAAAAAA==.Tevstar:BAAALAAECgMIAwAAAA==.',Th='Thalassaemia:BAAALAADCggICAAAAA==.Thalidomide:BAAALAAECgYIDQAAAA==.Theavenger:BAAALAAECgMIBAAAAA==.Thedis:BAAALAADCgcIEgAAAA==.Theholytogo:BAAALAAECgMIAwAAAA==.Thevie:BAAALAAECgEIAQAAAA==.Thrahis:BAAALAADCgYIBgAAAA==.Thronduil:BAAALAADCgMIAwAAAA==.Thugatros:BAAALAADCggICAABLAAECgIIBAABAAAAAA==.Thunderhawke:BAAALAADCgcIEgAAAA==.Thuxis:BAAALAAECgYIDAAAAA==.',Ti='Tigervirus:BAAALAADCgcIDAAAAA==.Timmypi:BAAALAADCgcIBwAAAA==.Timmythedrgn:BAAALAAECgcIEQAAAA==.Tishandrus:BAAALAADCgUIBQAAAA==.',To='Tobeherox:BAAALAAECgIIAgAAAA==.Tokot:BAAALAAECgMIBAAAAA==.Tolyr:BAAALAADCgEIAQAAAA==.Tombstone:BAAALAAECgcIDQAAAA==.Toothefairy:BAAALAADCgMIAwAAAA==.',Tr='Tradrel:BAAALAAECgMIAwAAAA==.Treewars:BAAALAADCgcIDAAAAA==.Trentman:BAAALAADCgIIAgAAAA==.Trinitylimit:BAAALAAECgMIAwAAAA==.Tripo:BAAALAADCggICAAAAA==.Trippen:BAAALAAECgcIDAAAAA==.Trippihippie:BAAALAADCggICAAAAA==.Trippy:BAAALAAECgYIBgAAAA==.Trycondus:BAAALAAECgQICQAAAA==.',Ts='Tsanchez:BAAALAAECgEIAQAAAA==.Tsunamie:BAAALAADCgUIBQAAAA==.',Tu='Tubby:BAAALAADCgIIAgAAAA==.Tulathros:BAAALAAECgIIBAAAAA==.Tulatros:BAAALAADCgcIBwABLAAECgIIBAABAAAAAA==.',Ul='Ulterbae:BAAALAADCgcIEQAAAA==.',Um='Umbrasanctum:BAAALAAECgMIBQAAAA==.Umbravex:BAAALAADCgIIAgAAAA==.',Un='Unishu:BAAALAADCgUIBQAAAA==.Unlok:BAAALAADCgEIAQAAAA==.',Va='Valanore:BAAALAAECgIIAgAAAA==.Valheru:BAAALAADCgcIBwAAAA==.Vallack:BAAALAADCgYIBwAAAA==.Valreconquis:BAAALAADCgcIEQAAAA==.Vanateil:BAAALAADCgcICgAAAA==.Vandalanth:BAAALAADCgQIBAAAAA==.Vasirion:BAAALAAECgMIBwAAAA==.',Ve='Veenus:BAAALAAECgQIBQAAAA==.Velinoe:BAAALAAECgQIBgAAAA==.Verdari:BAAALAAECgIIAgAAAA==.Verlene:BAAALAADCgcIBwAAAA==.Vestamoon:BAAALAADCgIIAgAAAA==.Vestamoonn:BAAALAAECgMIAwAAAA==.Vestà:BAAALAADCgcIDQABLAAECgcIDwABAAAAAA==.Vesuviús:BAAALAADCgYIBgAAAA==.',Vi='Vichyssoise:BAAALAADCgQIBAAAAA==.Vilaïne:BAAALAADCgcICQABLAAECgYIDgABAAAAAA==.Vindicatar:BAAALAAECgYIDwAAAA==.Vindicator:BAAALAAECgEIAQAAAA==.Vindrozalth:BAAALAADCggIEAAAAA==.Virek:BAAALAAECgMIBAAAAA==.',Vo='Voidtree:BAAALAAECgIIAgAAAA==.Vornda:BAAALAAECgYIDwAAAA==.',Vt='Vtank:BAAALAAECgcICQAAAA==.',Vu='Vulpelle:BAAALAAECgMIAwAAAA==.Vunderbear:BAAALAADCggICgAAAA==.',Vy='Vynerva:BAAALAADCgIIAgAAAA==.Vynis:BAAALAADCgYIAwAAAA==.',Wa='Warlockvx:BAAALAADCgYIBgAAAA==.Warpayne:BAAALAADCgIIAgAAAA==.Warrvx:BAAALAAECgMIAwAAAA==.Warvoid:BAAALAADCgMIAwABLAAECgcIEgABAAAAAA==.Wattamage:BAAALAAECgMIBgAAAA==.Wavepool:BAAALAADCggICAAAAA==.',We='Weetbiix:BAAALAADCgQIBAAAAA==.Wendâal:BAAALAADCgcIDAAAAA==.Wenike:BAAALAADCgcIBwAAAA==.',Wh='Wholegrains:BAAALAAECgQIBgAAAA==.Whycloth:BAAALAADCggICAAAAA==.Whytefall:BAAALAAECgIIAgAAAA==.Whytevoid:BAAALAADCgQIBAAAAA==.',Wi='Wildbynature:BAAALAADCgYIDAAAAA==.Wileyroo:BAAALAAECgMIAwAAAA==.Windrider:BAAALAAECgMIBgAAAA==.Wizid:BAAALAAECgIIAgAAAA==.',Wo='Wobbugos:BAAALAADCgYIBgAAAA==.Wogmage:BAAALAADCgYIBgAAAA==.Worgdeeznuts:BAAALAAECgIIBAAAAA==.',Wr='Wrathlon:BAAALAADCgcICgAAAA==.Wrongkey:BAAALAAECgMIAwAAAA==.',Ws='Wsz:BAAALAAECgIIAgAAAA==.',Xa='Xannar:BAAALAAECgYIDQAAAA==.Xanth:BAAALAADCgcIBwABLAAECggIAwABAAAAAA==.Xarmina:BAAALAAECggIEQAAAA==.',Xe='Xerron:BAAALAADCgYIDwAAAA==.',Ye='Yentra:BAAALAADCggICgAAAA==.',Yg='Yggdrasil:BAAALAADCggIEgABLAADCggIFAABAAAAAA==.',Yi='Yippy:BAAALAAECgMIBAAAAA==.',Yo='Yolngu:BAAALAAECgMIAwAAAA==.Yoshiko:BAAALAAECgcIDgAAAA==.',Yr='Yrbane:BAAALAADCgcIEgAAAA==.',Yu='Yuja:BAAALAAECgQIBgAAAA==.',Yv='Yvel:BAAALAAECgMIAwABLAAECgQIBAABAAAAAA==.',Za='Zaahir:BAAALAADCgcIBwAAAA==.Zaiyura:BAAALAADCgYIBwAAAA==.Zalayä:BAAALAAECgYIDgAAAA==.Zaljan:BAABLAAECoEVAAIMAAgIuR5sBgCnAgAMAAgIuR5sBgCnAgAAAA==.Zalkatraz:BAAALAADCgcIDQAAAA==.Zanshin:BAAALAAECgYIBgAAAA==.Zaruuk:BAAALAADCgIIAgAAAA==.Zavrall:BAAALAAECgIIAgAAAA==.',Ze='Zelarni:BAAALAADCgcICQAAAA==.Zeldarie:BAAALAADCgMIBQAAAA==.Zelidar:BAAALAADCgcIBwAAAA==.Zendaiya:BAAALAAECgYICAAAAA==.Zeriera:BAAALAADCgQIBQAAAA==.',Zh='Zhànshi:BAAALAAECgQIBgAAAA==.',Zi='Zippizap:BAAALAAECgMIBgAAAA==.',Zo='Zoavits:BAAALAADCgMIAwAAAA==.',Zu='Zudzug:BAAALAADCggICAAAAA==.Zugfu:BAAALAAECggIDwAAAA==.',['Ðe']='Ðed:BAAALAAFFAIIAgAAAA==.Ðemonraptor:BAAALAADCggIDAAAAA==.',['Ñë']='Ñëgus:BAAALAAECgMIAwAAAA==.',['Ør']='Ørchasm:BAAALAADCgcICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end