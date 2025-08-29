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
 local lookup = {'Unknown-Unknown','Monk-Mistweaver','Mage-Arcane','Shaman-Elemental','Hunter-BeastMastery','Evoker-Preservation','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Devastation','Warlock-Affliction','Warlock-Destruction','Warrior-Fury','Paladin-Retribution','Monk-Windwalker','Priest-Holy','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination',}; local provider = {region='US',realm="Aman'Thul",name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abroi:BAAALAADCgIIAgAAAA==.Abronar:BAAALAAECgMIAwAAAA==.',Ad='Addchild:BAAALAADCgcIBwAAAA==.Adderall:BAAALAADCgMIAwABLAADCgQIBAABAAAAAA==.Adrenalin:BAAALAAECgYICgAAAA==.',Ae='Aedros:BAAALAAECgYIDAAAAA==.Aegis:BAAALAADCgIIAgAAAA==.Aellan:BAAALAAECgYICgAAAA==.',Ag='Agnomaly:BAAALAAECgMIAwAAAA==.',Ah='Ahnahbrah:BAAALAADCgcICAAAAA==.',Aj='Ajira:BAAALAAECgEIAQAAAA==.',Ak='Akke:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.',Al='Aladenan:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.Alarian:BAAALAADCgcIBwAAAA==.Alarogue:BAAALAAECgMIBAAAAA==.Aldai:BAAALAAECgEIAQAAAA==.Alendros:BAAALAADCggICAAAAA==.Aliiah:BAAALAADCgQIBAAAAA==.Alista:BAAALAADCgcIBwAAAA==.Allerya:BAAALAADCgcIDQAAAA==.Allythriea:BAAALAADCgIIAgAAAA==.Alwaays:BAACLAAFFIEGAAICAAMIcw0hAgD0AAACAAMIcw0hAgD0AAAsAAQKgRgAAgIACAj1HowEAKACAAIACAj1HowEAKACAAAA.Alwaystoo:BAAALAAECgYIDAAAAA==.',Am='Ambertwo:BAAALAAECgQIBwAAAA==.Americana:BAAALAADCgMIBQAAAA==.',An='Anareal:BAAALAAECgYIBwAAAQ==.Andond:BAAALAADCgYIBwAAAA==.Andrasal:BAAALAADCgYIBgAAAA==.Andreb:BAAALAAECgMIAwAAAA==.Anima:BAAALAADCgEIAQAAAA==.Ankalru:BAAALAADCgEIAQAAAA==.Anthro:BAAALAAECgIIAgAAAA==.Anubiset:BAAALAADCgQIBAAAAA==.',Ar='Aralak:BAAALAADCgcICgAAAA==.Arbiteaux:BAAALAAECgQIBQAAAA==.Arcathal:BAAALAAECgYIDwAAAA==.Arcshottx:BAAALAAECgYICgAAAA==.Ardejah:BAAALAAECgUIAgAAAA==.Arliis:BAAALAADCgMIAwAAAA==.Arnoldrimmer:BAAALAADCgcIDQAAAA==.Arozen:BAAALAAECgQICAAAAA==.Artey:BAAALAAECgMIAwAAAA==.Arthérmis:BAAALAAECgcIEAAAAA==.Arva:BAAALAAECgEIAQAAAA==.',As='Ashaa:BAAALAAECgMIAwAAAA==.Assam:BAAALAADCgcIBwAAAA==.Assuri:BAAALAAECgYICwAAAA==.Astrou:BAAALAAECggIEgAAAA==.Asyluun:BAAALAADCggIFgAAAA==.',Au='Auchioane:BAAALAAECgMIBQAAAA==.Auslan:BAAALAAECgYIDAAAAA==.Autoprot:BAAALAAECgIIAgAAAA==.',Az='Azador:BAAALAAECgMIBgAAAA==.Azayzel:BAAALAADCgYIBgAAAA==.Azázel:BAAALAAECgQICAAAAA==.',Ba='Babybones:BAAALAAECgQIBAAAAA==.Baddieboy:BAAALAADCggICQAAAA==.Badghostie:BAAALAADCgYICQAAAA==.Balefiree:BAAALAAECgQIBAAAAA==.Balfor:BAAALAAECgMIAwAAAA==.Bamz:BAAALAADCgcIBwAAAA==.Bananathief:BAAALAADCgcICgAAAA==.Bananawoman:BAAALAADCggIFgAAAA==.Bandarshammy:BAAALAADCggIFAAAAA==.Barakuda:BAAALAADCggICwAAAA==.Barthanos:BAAALAAECgEIAQAAAA==.Basketballs:BAAALAAECgMIBQABLAAECgMICAABAAAAAA==.Batiibat:BAAALAADCgcICgAAAA==.',Be='Bearlytankin:BAAALAAECgEIAQAAAA==.Bears:BAAALAADCggICgAAAA==.Beebos:BAAALAADCgYIBgAAAA==.Beelzedud:BAAALAAECgQIBwAAAA==.Belkelmor:BAAALAADCgIIAgAAAA==.Bellaros:BAAALAAECgIIAgAAAA==.Belè:BAAALAADCggIFgAAAA==.Berediction:BAAALAADCggIFwABLAAECgEIAQABAAAAAA==.Bereynne:BAEBLAAECoEYAAIDAAcIMB9wFQBnAgADAAcIMB9wFQBnAgAAAA==.Bermagi:BAAALAAECgEIAQAAAA==.Bermot:BAAALAADCgYIBgAAAA==.',Bh='Bhumsecs:BAAALAAECgIIAgAAAA==.',Bi='Bigdawgrico:BAAALAAECgcIEAAAAA==.Bigkek:BAAALAAECgMIAwAAAA==.Billpie:BAAALAAECgIIBQAAAA==.',Bl='Blackdamian:BAAALAAECgcIEwAAAA==.Blazlock:BAAALAAECgMIBgAAAA==.Blinkscale:BAAALAADCgIIAgAAAA==.Bluebrood:BAAALAAECgIIAgAAAA==.',Bo='Boewr:BAAALAAECgMIBgAAAA==.Bofreddy:BAAALAAECgYICgAAAA==.Bojack:BAAALAAECgMIAwAAAA==.Bombshot:BAAALAADCggIEAAAAA==.Bonezone:BAAALAAECgcIDwAAAA==.Bonkgoblikon:BAAALAAECgIIAgAAAA==.Booshies:BAAALAADCgMIAwAAAA==.Bougiesavage:BAAALAADCgYIBgAAAA==.Bovinei:BAAALAADCggIFwAAAA==.',Br='Brackk:BAAALAADCgMIBQAAAA==.Braedaevia:BAAALAADCgYIBgAAAA==.Brahnson:BAAALAADCgcIEQAAAA==.Breldyr:BAAALAAECgUICAAAAA==.Broganz:BAAALAADCgIIAgAAAA==.Bronic:BAAALAAECgYIBwAAAA==.Brostorm:BAAALAADCgEIAQAAAA==.Brreach:BAAALAAECgQICAAAAA==.Brylen:BAABLAAECoEWAAIEAAgIwyXiAQBdAwAEAAgIwyXiAQBdAwAAAA==.',Bu='Bulkbilling:BAAALAADCgMIAwAAAA==.Bullus:BAAALAAECgYICgAAAA==.Bumblesnuff:BAAALAADCgMIAgAAAA==.Bushlord:BAAALAADCgMIAwAAAA==.Butchër:BAABLAAECoEXAAIFAAgIxByhEABoAgAFAAgIxByhEABoAgAAAA==.',['Bè']='Bèéz:BAAALAADCggIEAABLAAECgcIDwABAAAAAA==.',['Bë']='Bëlts:BAAALAADCgcIBwAAAA==.',Ca='Cable:BAAALAADCgUICQAAAA==.Cablex:BAAALAAECgYICQAAAA==.Caladisa:BAAALAAECgYICgAAAA==.Calardan:BAAALAAECgEIAQABLAAECgYICwABAAAAAA==.Carb:BAAALAAECgQIBAABLAAECggIEwAGAIEkAA==.Carlsberg:BAAALAADCggIEAAAAA==.Cassano:BAAALAAECgEIAQABLAAECgMIBwABAAAAAA==.Castrhoe:BAAALAAECgQIBQAAAA==.',Ce='Cearindark:BAAALAADCgcIDAAAAA==.Celad:BAAALAAECgQICAAAAA==.Celaste:BAAALAAECgYICAAAAA==.Celestina:BAAALAADCgMIAwAAAA==.Cerlina:BAAALAADCgcIBwAAAA==.',Ch='Chaoticc:BAAALAADCgYIBgAAAA==.Chilldawg:BAAALAADCggICAAAAA==.Chillidrood:BAAALAADCgMIAwAAAA==.Chipsy:BAAALAADCgcIDgAAAA==.Chroren:BAAALAAECgcIEAAAAA==.Chéesy:BAAALAADCgcIBwAAAA==.',Ci='Cinderchin:BAAALAAECgYICQAAAA==.',Cl='Clayson:BAAALAAECgQIBQAAAA==.Cleaveedge:BAAALAAECgYICgAAAA==.Cleavís:BAAALAAECgMIBgAAAA==.',Co='Cogedor:BAAALAADCgcIBwAAAA==.Completer:BAAALAAECgMIAwAAAA==.Complicated:BAAALAAECgEIAQAAAA==.Compy:BAAALAADCgYIDAAAAA==.Conoroy:BAAALAADCgcIBwAAAA==.Corahofpan:BAAALAADCggIDwAAAA==.Corem:BAAALAAECgMIAwAAAA==.Corvyncos:BAAALAADCgcIBwAAAA==.Cozymonday:BAAALAAECgYICgAAAA==.',Cr='Crakeld:BAAALAADCgEIAQAAAA==.Cramberly:BAAALAAECgIIAwAAAA==.Crikeys:BAAALAADCgcIDQAAAA==.Critneyfearz:BAAALAADCggICAAAAA==.Crobat:BAAALAADCgUIBQAAAA==.Cromonk:BAAALAAECgQICAAAAA==.Cryptc:BAAALAADCgcIDAAAAA==.',Cu='Cucklemcgee:BAAALAADCggIDwAAAA==.Custodes:BAAALAADCgcICAAAAA==.',Cy='Cyaneum:BAAALAAECgQICAAAAA==.Cybeles:BAAALAADCgMIAwAAAA==.Cyrida:BAAALAADCggIFwAAAA==.',Da='Dabita:BAAALAAECgMIBAAAAA==.Daemonbane:BAAALAAECgEIAgAAAA==.Daisuke:BAAALAADCgcICgAAAA==.Dajango:BAAALAAECgYICgAAAA==.Dake:BAAALAAECgYICQAAAA==.Dakm:BAAALAADCggICAAAAA==.Daknar:BAAALAAECgYIBgAAAA==.Dalarac:BAAALAADCgcIDQAAAA==.Dalenhammer:BAAALAADCgYICAAAAA==.Dalenvoidy:BAAALAADCggIFgAAAA==.Dalgom:BAAALAAECgIIAgAAAA==.Dashdk:BAAALAADCggIDQAAAA==.Dashhunt:BAAALAAECgMIAwAAAA==.Dashmoon:BAAALAADCggIDQAAAA==.Dastorthor:BAAALAAECggICgAAAA==.Davy:BAAALAAECgcIEAAAAA==.',De='Deadlyyrage:BAAALAAECggICAAAAA==.Deameath:BAAALAADCggIDwAAAA==.Deet:BAAALAADCggIDgAAAA==.Defyndm:BAAALAAECgEIAQAAAA==.Defynds:BAAALAADCggIFwABLAAECgEIAQABAAAAAA==.Delen:BAAALAADCgcIDQAAAA==.Delind:BAAALAADCgEIAQAAAA==.Dellie:BAAALAADCggIFgAAAA==.Dementor:BAAALAADCggICAAAAA==.Demimonarch:BAAALAAECgEIAQAAAA==.Denardiir:BAAALAADCggIGAABLAAECgYIDQABAAAAAA==.Depleter:BAAALAADCgEIAQAAAA==.Desir:BAAALAAECgIIAgAAAA==.Destanna:BAAALAADCgcIDQAAAA==.Detached:BAAALAAECgIIAgAAAA==.Dewy:BAAALAAECgIIAgAAAA==.',Dh='Dhukkha:BAAALAAECgYIDwAAAA==.',Di='Dinie:BAAALAAECgUIBQAAAA==.Dipshi:BAAALAADCgIIAgAAAA==.Discofever:BAAALAADCgMIAwAAAA==.Diseased:BAAALAAECgcICgAAAA==.Disperse:BAAALAAECgcIDQAAAA==.Disrespects:BAAALAADCgIIAgAAAA==.Divinebehind:BAAALAADCgcIBwAAAA==.Dizzimajizz:BAAALAAECgMIBQAAAA==.',Do='Doeballs:BAAALAAECgMIAwAAAA==.Dollcinq:BAAALAAECgIIAgAAAA==.Doomstaff:BAAALAAECgMIBAAAAA==.Dorasel:BAAALAADCgEIAQAAAA==.Downpour:BAAALAAECgYICgAAAA==.',Dr='Dragonhopes:BAAALAAECgMIBQAAAA==.Dragonladyt:BAAALAADCgcIBwAAAA==.Drakane:BAAALAAECgYICwAAAA==.Drated:BAABLAAECoEXAAMHAAgIChr1GQAuAgAHAAgIUBj1GQAuAgAIAAQIyQ9MHwDXAAAAAA==.Drazalgor:BAAALAAECgIIAgAAAA==.Drenka:BAAALAAECgIIAwAAAA==.',Du='Duckpunch:BAAALAAECgQIBwAAAA==.Dustiny:BAAALAADCggIEAAAAA==.',Dw='Dwagoon:BAAALAADCgQIBQAAAA==.Dworgin:BAAALAAECgMIBgAAAA==.',Dy='Dygha:BAAALAADCgIIAgAAAA==.Dying:BAABLAAECoEWAAMIAAgIWCYoAACIAwAIAAgIWCYoAACIAwAHAAEI/B4ZgABLAAAAAA==.Dyrtysouth:BAAALAADCgMIAwAAAA==.',['Dâ']='Dârkxtc:BAAALAADCgcICwAAAA==.',Ea='Eaglekick:BAAALAAECgQIBQAAAA==.Eatmeout:BAAALAADCgIIAgAAAA==.',Ec='Eclips:BAAALAADCgcIDQAAAA==.',Ed='Eddo:BAAALAADCgMIAwAAAA==.Edendil:BAAALAAECgUIBwAAAA==.Edosonfire:BAAALAADCgcIDwAAAA==.Edrissa:BAAALAADCgcIEgAAAA==.',Ei='Eijie:BAAALAADCgcIBwAAAA==.Eilystraee:BAAALAAECgEIAQABLAAECgQICQABAAAAAA==.Einlanzer:BAAALAAECgMIBAAAAA==.',El='Elektrify:BAAALAADCggICgAAAA==.Elerae:BAAALAAECgQIBwAAAA==.Elisandë:BAAALAADCgcIBwAAAA==.Elleryl:BAAALAAECgEIAQAAAA==.Elyleata:BAAALAADCgQIBAAAAA==.',Em='Emptyrogue:BAAALAADCgcIBwAAAA==.',En='Enarium:BAAALAADCggIEAAAAA==.Envyy:BAAALAAECgcIEAAAAA==.',Et='Eternalenvy:BAAALAAECgIIAgAAAA==.Etyeehaw:BAAALAAECgYIDAAAAA==.',Eu='Euc:BAAALAAECgMIBAAAAA==.Eurel:BAAALAADCgEIAQAAAA==.Eurul:BAAALAAECgMIBgAAAA==.',Ev='Eviltank:BAAALAAECgcIEAAAAA==.Eväh:BAAALAAECgIIAgAAAA==.',Ez='Ezzbot:BAAALAAECgYIDQAAAA==.',Fa='Faildingers:BAAALAAECgMIBAAAAA==.Fallèn:BAAALAADCggIFwABLAAECgEIAQABAAAAAA==.Falnyr:BAAALAAECgUIBgAAAA==.Fanchone:BAAALAAECgQIBQAAAA==.Fantail:BAAALAAECgEIAQAAAA==.Farkeww:BAAALAAECggIBgAAAA==.Faroosh:BAAALAAECgQIBwAAAA==.Fauxtrix:BAAALAAECgEIAQAAAA==.',Fe='Felanthropy:BAAALAAECgQIBQAAAA==.Feldyr:BAAALAADCgcIDQAAAA==.Felfliction:BAAALAAECgIIAwAAAA==.Felinae:BAAALAADCggIFgAAAQ==.Felrrak:BAAALAAECgcIEwAAAA==.Felschoo:BAAALAAECgYICAAAAA==.Ferynis:BAAALAADCggIFgAAAA==.',Fi='Fifitang:BAAALAADCgcIBwABLAAECgQIBQABAAAAAA==.Firefingêrs:BAAALAADCgcIBwAAAA==.Firekhan:BAAALAAECgYICgAAAA==.Fishdh:BAAALAAECgcIDwAAAA==.Fishwick:BAAALAADCgYIBgABLAAECgcIDwABAAAAAA==.',Fl='Flador:BAAALAAECgMIAwAAAA==.Flamma:BAAALAAECgYIBgAAAA==.Flickatotem:BAAALAAECgIIAwAAAA==.Florimel:BAAALAAECgEIAQAAAA==.Flumble:BAAALAADCgIIAgAAAA==.Fluticasone:BAAALAADCgcIEgAAAA==.',Fo='Foklen:BAAALAADCgQIBAAAAA==.Foongus:BAAALAAECgMIBAAAAA==.Foreveraz:BAAALAADCgYIBgAAAA==.Foxhound:BAAALAAECgYICgAAAA==.Fozzydh:BAAALAAECgYIDwAAAA==.',Fr='Freakazoid:BAAALAADCgcIDwAAAA==.Freebies:BAAALAAECgYICQAAAA==.Frell:BAAALAADCgcIDQAAAA==.Freshchurros:BAAALAADCggICwAAAA==.Freshdonuts:BAAALAADCggIEAAAAA==.Freshguac:BAAALAADCggIDwAAAA==.Freshnachos:BAAALAADCgIIAgAAAA==.Freshpico:BAAALAADCgUIBwAAAA==.Freshsteak:BAAALAADCggICgAAAA==.Freshtequila:BAAALAADCgMIAwAAAA==.Frostbourne:BAAALAAECgYIDAAAAA==.Frostyfruit:BAAALAAECgcIDwAAAA==.Frostykarnt:BAAALAAECgIIAgAAAA==.',Fu='Furchos:BAAALAADCgMIAwAAAA==.Furryarrows:BAAALAADCgMIAwAAAA==.',Ga='Gaary:BAAALAAECgMIBAAAAA==.Gacrux:BAAALAADCgUIBQAAAA==.Galvin:BAAALAAECgIIAwAAAA==.Gandal:BAAALAADCgEIAQAAAA==.Gant:BAAALAADCgEIAQAAAA==.Gargahunt:BAAALAAECgEIAgAAAA==.Gargamoyle:BAAALAADCgMIAwABLAAECgEIAgABAAAAAA==.Gateweaver:BAAALAAECgIIAgAAAA==.',Ge='Gemashmage:BAAALAADCggIEAABLAAECgMIBgABAAAAAA==.Gemashpally:BAAALAAECgMIBgAAAA==.Gertzak:BAAALAAECgYIBgAAAA==.',Gh='Ghalroy:BAAALAADCgMIAwAAAA==.Gherkinz:BAAALAAECgYICAAAAA==.',Gi='Gibsonguo:BAAALAAECgQICAAAAA==.Giga:BAAALAADCgQIBAAAAA==.',Gl='Glaiveboi:BAAALAADCgcIBwAAAA==.Glitty:BAABLAAECoEXAAIJAAgI+yCDCQCDAgAJAAgI+yCDCQCDAgAAAA==.Glodslock:BAAALAADCggIFwAAAA==.',Go='Goffy:BAAALAAECgIIAgAAAA==.Gosly:BAAALAAECgYICAAAAA==.',Gr='Greeneyes:BAAALAADCgcIBwAAAA==.Greyblades:BAAALAADCgYIBgAAAA==.Grimdak:BAAALAADCgYICgAAAA==.Grimgirthy:BAAALAAECgIIAgAAAA==.Grimlock:BAAALAAECgEIAQAAAA==.Grnrktpriest:BAAALAADCgUIBQAAAA==.',Gu='Guilty:BAAALAAECgEIAQAAAA==.Guma:BAAALAAECgEIAQAAAA==.',Gy='Gyatso:BAAALAAECgEIAQAAAA==.Gyftable:BAAALAAECgMIBQAAAA==.',['Gí']='Gíngercookíe:BAAALAADCgQIBAAAAA==.',['Gó']='Gódzilla:BAAALAAECggICAAAAA==.',Ha='Haenei:BAAALAADCggIDwAAAA==.Haiping:BAAALAADCggIDwAAAA==.Hakoda:BAAALAAECgEIAQAAAA==.Halas:BAAALAADCgcIBwAAAA==.Haneth:BAAALAAECgEIAQAAAA==.Hardort:BAAALAADCggIEQAAAA==.Harriet:BAAALAADCgYIBgAAAA==.Haruchi:BAABLAAFFIEGAAICAAQIrQy1AABVAQACAAQIrQy1AABVAQAAAA==.Harude:BAAALAAFFAIIAgABLAAFFAQIBgACAK0MAA==.Harushear:BAAALAAECgYICAABLAAFFAQIBgACAK0MAA==.Haruvoked:BAAALAAECgYIDAABLAAFFAQIBgACAK0MAA==.Haruwhuh:BAAALAAECgEIAQABLAAFFAQIBgACAK0MAA==.Havocbringer:BAAALAADCgYIBgAAAA==.',He='Headhunterss:BAAALAAECgIIAgAAAA==.Healthcare:BAAALAADCgQIBAAAAA==.Hearte:BAAALAAECgYIDwAAAA==.Hellweaver:BAAALAAECgYIBgAAAA==.Hexades:BAAALAAECgMIAwAAAA==.',Hi='Hierophant:BAAALAAECgcIEAAAAA==.Hirobryne:BAAALAADCggIDwAAAA==.',Ho='Holing:BAAALAAECgYICQAAAA==.Holydeth:BAAALAAECgQIBAAAAA==.Holymama:BAAALAADCgMIAwAAAA==.Hormonal:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Hornyhunt:BAAALAAECgYIDAAAAA==.Hospitallers:BAAALAADCggICAAAAA==.Hotwave:BAAALAAECgEIAQAAAA==.',Hu='Hugmydruid:BAAALAAECgQIAwAAAA==.Hunterwoman:BAAALAADCggIDwAAAA==.Huntzha:BAAALAAECgEIAQAAAA==.',Hy='Hybrid:BAAALAAECgIIAgAAAA==.Hyzal:BAABLAAECoEXAAMKAAgIThYuAwBmAgAKAAgInhUuAwBmAgALAAgImw8AAAAAAAAAAA==.',['Hé']='Héälzgöd:BAAALAADCgUIBQAAAA==.',['Hí']='Híppiechick:BAAALAAECgIIAwAAAA==.',Ia='Iamurs:BAAALAADCgQIBAAAAA==.Ianix:BAAALAAECgQIBgAAAA==.',Ic='Iceni:BAAALAAECgMIBgAAAA==.Icetooth:BAAALAADCgcIDQAAAA==.',Id='Idanu:BAAALAAECgIIAgAAAA==.',If='Ifelforu:BAAALAADCgYIBgAAAA==.',Ih='Ihasarms:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.',Im='Imaddore:BAAALAAECgcIDQAAAA==.Iminentdeath:BAAALAADCgcICgAAAA==.Implication:BAAALAAECgMIAwAAAA==.',In='Ingranata:BAAALAADCgYIBgAAAA==.Interrupted:BAAALAADCggIFQAAAA==.',Ip='Ipooptotems:BAAALAAECgMIAwAAAA==.',Ir='Irict:BAAALAADCgEIAQABLAAECgYIDgABAAAAAA==.Ironbeard:BAAALAADCgMIAwAAAA==.Irraeline:BAAALAADCggIEAAAAA==.',Is='Ishayln:BAAALAADCgYIBAAAAA==.Ishootstuff:BAAALAAECgEIAgAAAA==.',It='Itsnotbatman:BAAALAAECgYICwAAAA==.',Iz='Izahbeau:BAAALAADCgIIAgAAAA==.',['Iì']='Iìe:BAAALAADCgYIBgAAAA==.',Ja='Jagermaster:BAAALAADCgcIDQAAAA==.Jaland:BAAALAAECgMIBwAAAA==.Jamdrop:BAAALAAECgMIBQAAAA==.Janeygirl:BAAALAAECgMIAwAAAA==.Jaqlle:BAAALAADCgcICQAAAA==.',Je='Jebs:BAAALAADCgcICwAAAA==.Jessblood:BAAALAAECgYICQAAAA==.Jezebel:BAAALAADCgcICAABLAAECgMIAwABAAAAAA==.',Ji='Jillard:BAAALAADCgIIAgAAAA==.Jizlober:BAAALAADCgYIBgAAAA==.',Jj='Jjaki:BAAALAAECgMIAwAAAA==.',Jo='Joesef:BAAALAAECgQIBQAAAA==.Johngoblikon:BAAALAADCgcIDAAAAA==.Johnyf:BAAALAADCgIIAgAAAA==.Jonesy:BAAALAAECgcIDwAAAA==.Jonononomonk:BAAALAAECgMIAwAAAA==.Jonz:BAAALAAECgMIBQAAAA==.Joshington:BAAALAAECgQIBQAAAA==.',Jp='Jpat:BAAALAAECggICAAAAA==.',Ju='Judex:BAAALAAECgQIBAAAAA==.',Ka='Kagomkum:BAAALAAECgEIAQAAAA==.Kakurzul:BAAALAAECgYICAAAAA==.Kalakash:BAAALAAECgMIBAAAAA==.Kalanix:BAAALAADCggIFgAAAA==.Kalliadaes:BAAALAADCggIDgAAAA==.Kanatari:BAAALAAECgYICAAAAA==.Karaleigh:BAAALAAECgYICQAAAA==.Karalka:BAAALAADCgEIAQAAAA==.Karmic:BAAALAADCgcIEwAAAA==.Kattadin:BAAALAAECgUIBQAAAA==.Kauraku:BAAALAAECgYIBQAAAA==.Kawaiisham:BAAALAADCggIDgAAAA==.Kazrik:BAAALAADCgcICAAAAA==.',Kc='Kcolypmup:BAAALAADCgQIBAAAAA==.',Ke='Keamuu:BAAALAADCgcIBwAAAA==.Keanoo:BAAALAADCggICAAAAA==.Kelraku:BAAALAAECgYICgAAAA==.Kernni:BAAALAADCggIEAAAAA==.Keyaenarc:BAAALAAECgEIAQABLAAECgEIAQABAAAAAA==.',Ki='Killdaan:BAAALAADCgYIBgAAAA==.Kimmur:BAAALAAECgEIAQAAAA==.Kirastaleron:BAAALAADCgQIBwAAAA==.',Kn='Knarr:BAAALAAECgYIDgAAAA==.Knor:BAAALAAECgYICAAAAA==.',Ko='Kook:BAAALAAECgcIEAAAAA==.Kordos:BAAALAADCgcIDgAAAA==.Koro:BAAALAAECgYICwAAAA==.Korrack:BAAALAADCggIFwAAAA==.',Kr='Krehea:BAAALAADCgUIBQAAAA==.Krielis:BAAALAADCgIIAgAAAA==.Kryraearc:BAAALAAECgEIAQAAAA==.',Ku='Kuddy:BAAALAAECggIBAAAAA==.Kumamizu:BAAALAADCgIIAgAAAA==.Kurarra:BAAALAAECgIIAgAAAA==.',Kw='Kwr:BAAALAADCggIEQAAAA==.Kwyn:BAAALAADCgcICAABLAAECgMIBgABAAAAAA==.',Ky='Kysyn:BAAALAAECgQIBgAAAA==.Kyxa:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.Kyü:BAAALAADCgQIBAAAAA==.',['Kè']='Kèw:BAAALAADCggIFgAAAA==.',La='Lalyria:BAAALAADCggIFwAAAA==.Lastrights:BAAALAADCgMIAwAAAA==.',Le='Lebronjr:BAAALAAECgMIAwAAAA==.Lechoso:BAAALAADCgUIBQAAAA==.Legolash:BAAALAAECgYICgAAAA==.Leniishii:BAAALAADCgcICwAAAA==.Lertice:BAABLAAECoEXAAIMAAgISx4wEABeAgAMAAgISx4wEABeAgAAAA==.Lesliey:BAAALAADCgcICwAAAA==.Lewy:BAAALAAECgIIAgAAAA==.Leàfy:BAAALAAECgQICAAAAA==.',Li='Liandari:BAAALAAECgMIAwAAAA==.Licharthas:BAAALAADCgEIAQAAAA==.Lightblade:BAAALAAECgMIAwAAAA==.Likeabauz:BAAALAAECgEIAQAAAA==.Lilibewhan:BAAALAADCggIDwAAAA==.Lillistara:BAAALAADCgcICAAAAA==.Limoncello:BAAALAAECgQIBQAAAA==.Lionkat:BAAALAADCggIFgAAAA==.',Lo='Longicorn:BAAALAAECgYIEQAAAA==.Lotion:BAAALAAECgYICAAAAA==.',Lu='Luckyy:BAAALAADCggICAAAAA==.Luhau:BAAALAAECgcIEAAAAA==.Lukê:BAAALAADCgMIAwAAAA==.Lunablanca:BAAALAADCggICAAAAA==.Lunen:BAAALAAECgcIEAAAAA==.Lunàris:BAAALAAECgIIAwAAAA==.Luvlyjublies:BAAALAADCggIFwAAAA==.',['Lé']='Léáf:BAAALAADCgEIAQABLAAECgMIAwABAAAAAA==.Léäf:BAAALAAECgMIAwAAAA==.',['Lê']='Lêafy:BAAALAADCgcIDQAAAA==.',['Lõ']='Lõx:BAAALAAECgYIDgAAAA==.',Ma='Mackerell:BAAALAAECgIIAgAAAA==.Macloven:BAAALAADCgIIAgAAAA==.Madamgrey:BAAALAAECgYICgAAAA==.Maedor:BAAALAADCgcIDQAAAA==.Maelock:BAAALAADCggIDgAAAA==.Magicboi:BAAALAAECgQIBgAAAA==.Magictacos:BAAALAAECgYICgAAAA==.Magnastar:BAAALAADCgYIBgAAAA==.Mags:BAAALAADCgcIBwAAAA==.Makisig:BAAALAAECgQICAAAAA==.Malarky:BAAALAAECgMIAwAAAA==.Malu:BAAALAADCgcIBwAAAA==.Malys:BAAALAAECgYIDAAAAA==.Maraach:BAAALAAECgQICAAAAA==.Mardaran:BAAALAAECgYICAAAAA==.Mariandor:BAAALAADCggIFwAAAA==.Markusama:BAAALAAECgMIAwAAAA==.Marles:BAAALAAECgcIEAAAAA==.Marsword:BAAALAADCgcIDgAAAA==.Marthaus:BAAALAAECgMIAwAAAA==.Matdemon:BAAALAAECgQIBAAAAA==.Mathias:BAAALAAECgQIBwAAAA==.Matilda:BAAALAAECgMIBAAAAA==.Matrempit:BAAALAAECgQIBwAAAA==.Mattrik:BAAALAAECgMIBgAAAA==.Mawsandpaws:BAAALAAECgQIBQAAAA==.Maximilia:BAAALAAECgYIDwAAAA==.Mayne:BAAALAADCgYIBgAAAA==.',Mc='Mcclappin:BAAALAAECgMIBQAAAA==.Mcduff:BAAALAAECgIIAgAAAA==.',Me='Meaningreen:BAAALAADCggICAAAAA==.Meatcough:BAAALAADCgcIBwAAAA==.Meatshièld:BAAALAAECgQIBgAAAA==.Medalion:BAAALAADCgcIDwAAAA==.Meelo:BAAALAADCgcIDQAAAA==.Melazaelf:BAAALAADCgcIDQAAAA==.Melchan:BAAALAADCgcIDAAAAA==.Melville:BAAALAAECgMIBgAAAA==.Meowdy:BAAALAAECgQICgAAAA==.Merde:BAAALAAECgMIBAAAAA==.Meyj:BAAALAADCgIIAgAAAA==.',Mi='Midknîght:BAAALAAECgEIAQAAAA==.Midwa:BAABLAAECoEXAAINAAgIfiXlAQBrAwANAAgIfiXlAQBrAwAAAA==.Miidge:BAAALAADCgUIBwAAAA==.Mikasaro:BAAALAADCggIDwAAAA==.Missblade:BAAALAAECgMIAwAAAA==.Mista:BAAALAADCgQIBAAAAA==.Mistae:BAAALAAFFAIIAgAAAA==.Mixer:BAACLAAFFIEHAAIOAAMIlCSbAABCAQAOAAMIlCSbAABCAQAsAAQKgR0AAg4ACAi5JoEAAHEDAA4ACAi5JoEAAHEDAAAA.',Mm='Mmelodyy:BAAALAAECgIIAQAAAA==.',Mo='Moguai:BAAALAADCgcIDQAAAA==.Moistrov:BAAALAAECgYICQAAAA==.Mojitoo:BAAALAADCgMIAwAAAA==.Molloch:BAAALAAECgUICQAAAA==.Moneycollect:BAAALAADCgcIDgAAAA==.Monotonetorz:BAAALAADCgYIBwABLAAECggIEAABAAAAAA==.Monris:BAAALAADCgUIBQAAAA==.Moordie:BAAALAAECgYICgAAAA==.Mordekaizerl:BAAALAADCgYICQAAAA==.Morgainne:BAAALAADCggIDAAAAA==.Mortanah:BAAALAAECgYIDgAAAA==.Morá:BAAALAAECgcIDwAAAA==.Mozire:BAAALAADCggIEAAAAA==.Moötality:BAAALAAECgYICgAAAA==.',Mt='Mtnaan:BAAALAADCggIFgAAAA==.',Mu='Mukaii:BAAALAADCggIDgAAAA==.Munting:BAAALAAECgEIAQAAAA==.Musde:BAAALAADCgcIBwAAAA==.',Mw='Mwisho:BAAALAAECgMIAwAAAA==.',My='Myctlan:BAAALAADCgcICgAAAA==.Myrddn:BAAALAADCgEIAQAAAA==.Myrsham:BAAALAAECgcIDwAAAA==.Mystra:BAAALAAECgcIEAAAAA==.Mythbrediir:BAAALAAECgYIDQAAAA==.',['Mü']='Müläflaga:BAAALAADCggIFgAAAA==.',Na='Naadina:BAAALAADCgcICAAAAA==.Nacht:BAAALAAECgYICwAAAA==.Natriyanna:BAAALAAECgYICAAAAA==.Naturëswrath:BAAALAADCggIDAAAAA==.Navillas:BAAALAAECgQIBQAAAA==.Nazaha:BAABLAAECoEXAAIPAAgI7CTyBgC9AgAPAAgI7CTyBgC9AgAAAA==.',Ne='Nekhrimah:BAAALAAECgIIAwAAAA==.Neorogue:BAAALAAECgMIBAAAAA==.Nerii:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Nerolein:BAAALAADCgIIAgAAAA==.',Ni='Nidaruid:BAAALAAECgEIAgAAAA==.Niteañgel:BAAALAAECgEIAQAAAA==.Nitexp:BAAALAADCgEIAQAAAA==.Niç:BAAALAAECgEIAQAAAA==.',No='Nojruh:BAAALAADCgcICAAAAA==.Notbeezy:BAAALAAECgcIDwAAAA==.Nox:BAAALAADCgcIBAAAAA==.',Nu='Numnutts:BAAALAAECgQICAAAAA==.',['Nè']='Nèrp:BAAALAADCgMIAwAAAA==.',['Në']='Nërp:BAAALAAECgYICAAAAA==.',['Nó']='Nóc:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.',['Nö']='Nöddy:BAAALAADCgcIDQAAAA==.',Ol='Olos:BAAALAADCgMIAwAAAA==.Olunaija:BAAALAAECgIIAgAAAA==.',On='Onslawt:BAAALAADCggICAAAAA==.',Or='Orillimagus:BAAALAAECgQICgAAAA==.Oriwrathbane:BAAALAAECgIIAgAAAA==.',Os='Oswicklorcan:BAAALAADCggIEwAAAA==.',Ou='Ouchiheal:BAAALAAECgYIDQAAAA==.',Ov='Overhealer:BAAALAAECgQIBAAAAA==.',Pa='Pachi:BAAALAADCgcIBwAAAA==.Pachá:BAAALAADCgMIAwAAAA==.Paladumb:BAABLAAECoEXAAINAAgIih6EGwAgAgANAAgIih6EGwAgAgAAAA==.Panchovy:BAABLAAECoEUAAIOAAgIaR1gBADKAgAOAAgIaR1gBADKAgAAAA==.Pandoc:BAAALAAECgYIDwAAAA==.Paperhands:BAAALAAECgcIEAAAAA==.',Pe='Peculiar:BAAALAAECgIIAgAAAA==.Pequod:BAAALAAECgMIBAAAAA==.Petrius:BAAALAADCggIDwAAAA==.',Ph='Phatboii:BAAALAADCggICAAAAA==.Phokmyahz:BAAALAAECgQIBAAAAA==.',Pl='Plaxina:BAAALAAECgcIDQAAAA==.Plazmapoke:BAAALAAECgUIBwAAAA==.Plazzmma:BAAALAAECgMIBgAAAA==.',Pm='Pmoc:BAAALAADCgMIAwAAAA==.',Po='Pogo:BAABLAAECoETAAIGAAgIgSSoAQDcAgAGAAgIgSSoAQDcAgAAAA==.Ponderoso:BAAALAADCggIDwAAAA==.Poofartsmell:BAAALAAECgcIDAAAAA==.Poppylotus:BAAALAADCggIGQAAAA==.Posthaste:BAAALAADCgEIAQAAAA==.Powerwordsad:BAAALAAECgQIBQAAAA==.',Pr='Precioùs:BAAALAADCgcIDQABLAAECgIIAgABAAAAAA==.Presto:BAAALAAECgQICAAAAA==.Proctölogist:BAAALAAECgEIAQAAAA==.Protagonist:BAAALAADCgQIBAABLAAECggIFgAEAMMlAA==.Prototank:BAAALAAECgEIAQAAAA==.Protêk:BAABLAAECoEWAAIDAAgIgCIMEACfAgADAAgIgCIMEACfAgAAAA==.',Ps='Psychótic:BAAALAAECgYIDQAAAA==.',Pt='Pthree:BAAALAAECgQIBAABLAAECgYICgABAAAAAA==.',Pu='Pungar:BAAALAAECgcIDAAAAA==.Purepassion:BAAALAADCgcIBwAAAA==.',Pw='Pwwned:BAAALAAECgIIAwAAAA==.',['Pâ']='Pânadol:BAAALAAECgEIAQAAAA==.',['Pä']='Pänya:BAAALAADCgcIBwAAAA==.',Qa='Qazdes:BAAALAADCgEIAQAAAA==.',Qq='Qqklan:BAAALAAECgQIBAAAAA==.',Qu='Quaetro:BAAALAAECgMIBwAAAA==.Qub:BAAALAAECgEIAgAAAA==.Quinny:BAAALAAECgMIBgAAAA==.Quinnybear:BAAALAADCggIDgAAAA==.Quintar:BAAALAAECgYICwAAAA==.',['Qú']='Qúantúm:BAAALAADCgEIAQAAAA==.',Ra='Raeka:BAAALAAECgQIBQAAAA==.Ragarlem:BAAALAAECgEIAQAAAA==.Rageie:BAAALAAECgQICQAAAA==.Ragequìt:BAAALAAECgEIAQAAAA==.Raggorg:BAAALAADCgcIBwAAAA==.Rahmawaty:BAAALAADCgQIBAAAAA==.Raiteq:BAAALAAECgYICAAAAA==.Ralare:BAAALAADCgcIBwAAAA==.Raman:BAAALAADCgcICwAAAA==.Raputaa:BAAALAADCgUIBQAAAA==.Rathenoth:BAAALAAECgMIAwAAAA==.Rathovirr:BAAALAAECgcIEAAAAA==.Rawlôck:BAAALAAECgcIEAAAAA==.Rawromg:BAAALAAECgYICQAAAA==.Raxor:BAAALAAECgYICQAAAA==.Razzpriest:BAAALAAECgMIBAAAAA==.',Re='Redfoxxy:BAAALAADCgcIDAAAAA==.Regret:BAAALAAECggIBQABLAAECggIFgAIAFgmAA==.Reika:BAAALAADCgcIDQABLAAECgYICAABAAAAAA==.Rekwon:BAAALAAECgMIBgAAAA==.Rell:BAAALAADCggIDwAAAA==.Rellab:BAAALAADCgcICQAAAA==.Rendaxe:BAAALAAECgcIEAAAAA==.Renli:BAAALAAECgIIAgAAAA==.Retalica:BAAALAAECgcIEAAAAA==.Retrishi:BAAALAAECgMIBQAAAA==.Reverb:BAAALAADCggICAAAAA==.Rexhun:BAAALAADCggIDwAAAA==.Reyku:BAAALAADCgcIBwAAAA==.',Ri='Ricard:BAAALAADCgcIEgAAAA==.Richnight:BAAALAAECgUIBQAAAA==.Rickettsia:BAAALAAECgYICgAAAA==.Rippen:BAAALAADCgYIDQAAAA==.Risto:BAAALAADCgYIBgAAAA==.',Ro='Robyngdfelow:BAAALAADCggIFQAAAA==.Rodger:BAAALAADCggICwAAAA==.Rollingrick:BAAALAADCggIDwAAAA==.Roxina:BAAALAAECgQICQAAAA==.',Ru='Rulgor:BAAALAADCggICAAAAA==.Ruripe:BAAALAAECgQIBQAAAA==.Rustycrack:BAAALAAECgMIBQAAAA==.',Ry='Ryneastera:BAAALAADCgUIBQAAAA==.Ryri:BAAALAADCggIDwAAAA==.Ryther:BAAALAADCggIEwAAAA==.',Sa='Saccromycaes:BAAALAAECgEIAQAAAA==.Saelestar:BAAALAADCggIDgAAAA==.Saerin:BAAALAADCgYIBgAAAA==.Sahas:BAAALAAECgcIDAAAAA==.Saiesha:BAAALAADCgEIAQAAAA==.Saipher:BAAALAADCgYIBgABLAAECgQIBQABAAAAAA==.Sammiches:BAAALAADCggIFAAAAA==.Samwinchesta:BAAALAAECgUIBgAAAA==.Sarakatawen:BAAALAADCgIIAgAAAA==.Sarumash:BAAALAADCgIIAgAAAA==.Savarge:BAAALAADCgcIDQAAAA==.Saxify:BAAALAAECgMIBQAAAA==.',Sc='Scotchfiend:BAAALAADCgQIBAAAAA==.Scratcha:BAAALAADCggICwAAAA==.Scub:BAAALAADCgYIBgAAAA==.Scur:BAAALAAECgYIDAAAAA==.',Se='Securityboss:BAAALAAECgcIDgAAAA==.Seemenow:BAAALAADCgcIBwAAAA==.Selten:BAAALAAECgcIEAAAAA==.Senderson:BAAALAADCgQIBAAAAA==.Senu:BAAALAAECggIEwAAAA==.Serahunter:BAAALAAECgMIBgABLAAECgUICAABAAAAAA==.Seramage:BAAALAAECgUICAAAAA==.Serrilia:BAAALAAECggIEAAAAA==.Setanti:BAAALAADCgcICAAAAA==.',Sh='Shadowrae:BAAALAAECgIIBAABLAAECgQIBwABAAAAAA==.Shadstab:BAAALAADCggIDwAAAA==.Shadyllama:BAAALAAECgMIBgAAAA==.Shamanrager:BAAALAAECggIEQAAAA==.Shammah:BAAALAADCgcIDQABLAAECgQIBAABAAAAAA==.Shamonk:BAAALAADCgcIBwAAAA==.Shamón:BAAALAADCgYIBgAAAA==.Shape:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Shardface:BAAALAAECgIIAwAAAA==.Sharn:BAAALAADCgYIBwAAAA==.Sharnie:BAAALAAECgMIBgAAAA==.Shazdap:BAAALAADCggIFAAAAA==.Shellatrix:BAAALAAECgYIDAAAAA==.Shellzy:BAAALAADCgcIBwAAAA==.Shepp:BAAALAAECgQICAAAAA==.Shimron:BAAALAAECgMIBAABLAAECgQIBAABAAAAAA==.Shinryu:BAAALAAECgEIAQAAAA==.Shirazz:BAAALAADCgIIAgAAAA==.Shockinglyba:BAAALAAECgQIBAAAAA==.Shojo:BAAALAADCgcIDQAAAA==.Shootette:BAAALAAECgMIBgAAAA==.Shuaigege:BAAALAAECgIIAwAAAA==.Shutenz:BAAALAADCggICAAAAA==.Shãdow:BAAALAAECgQIBgAAAA==.Shí:BAAALAAECgQICAAAAA==.',Si='Sijjamus:BAAALAAECgIIAgAAAA==.Silandryn:BAAALAAECgEIAQAAAA==.Sinderela:BAAALAAECggICgAAAA==.Sinisterwing:BAAALAAECgYIDgAAAA==.Sipah:BAAALAADCgUIBQAAAA==.',Sk='Skadì:BAAALAADCgMIAwAAAA==.Skeptikk:BAAALAAECgcIEAAAAA==.Skinnery:BAAALAADCgIIAgAAAA==.Skittlz:BAAALAAECgcIEAAAAA==.Skyvandior:BAAALAADCgEIAQAAAA==.',Sl='Slateray:BAAALAAECgMIAwAAAA==.Slayerbarbie:BAAALAAECgIIAgAAAA==.Slyr:BAAALAAECgYICQAAAA==.',Sm='Smokingpally:BAAALAADCgcIDAAAAA==.Smoldergrin:BAAALAADCgQIBAAAAA==.',Sn='Sneaksohard:BAAALAADCgYIBgAAAA==.',So='Sog:BAAALAADCgYICAABLAAECgYICAABAAAAAA==.Sogrezlerk:BAAALAAECgYICwAAAA==.Solarquakes:BAAALAAECggICwAAAA==.Somnus:BAAALAAECgMIBAAAAA==.Sorachan:BAAALAADCgcIBwAAAA==.',Sp='Sparhawker:BAAALAAECggICAAAAA==.Spenbobsdh:BAAALAAECgEIAQAAAA==.Spenna:BAAALAADCgcICwAAAA==.Spiritvoid:BAAALAAECgMIBQAAAA==.Spudacus:BAAALAAECgMIBQAAAA==.Spàz:BAAALAADCgcIDQAAAA==.',St='Stariel:BAAALAADCgcIBwAAAA==.Stellaa:BAAALAADCgIIAgAAAA==.Stevenballs:BAAALAAECgMICAAAAA==.Stickler:BAAALAAECgYICgAAAA==.Stigo:BAAALAADCggIDwAAAA==.Storblastor:BAAALAADCgcIDgAAAA==.Streuth:BAAALAAECgcIEAAAAA==.Strikar:BAAALAADCgEIAQAAAA==.Strummer:BAABLAAECoEXAAIFAAgITiaCAgBJAwAFAAgITiaCAgBJAwAAAA==.',Su='Suaidrai:BAAALAAECgYIDAAAAA==.Subaru:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Subaruu:BAAALAAECgEIAQAAAA==.Subasaiyan:BAAALAADCgEIAQABLAAECgEIAQABAAAAAA==.Subsiding:BAAALAAECgQIBQAAAA==.Subtera:BAAALAAECgYICAAAAA==.Sucubutt:BAAALAAECgIIAgAAAA==.Superdiger:BAAALAAECgEIAQAAAA==.Supernothing:BAAALAAECgIIAgAAAA==.Superswede:BAAALAADCgIIAgAAAA==.',Sv='Svelar:BAAALAADCgcIBwAAAA==.',Sw='Sweatypunch:BAAALAADCgYICgAAAA==.Swirlza:BAAALAAECgcIEAAAAA==.',Sy='Syaarpally:BAAALAADCgcICgAAAA==.Sylanthia:BAAALAAECgMIDQAAAA==.Sylea:BAAALAADCgcIBwAAAA==.Sylerislock:BAAALAAECgYICgAAAA==.',['Sê']='Sêphiroth:BAAALAADCggICAAAAA==.',['Só']='Sóg:BAAALAADCggIDwABLAAECgYICAABAAAAAA==.',['Sô']='Sôg:BAAALAAECgYICAAAAA==.',['Sù']='Sùnjin:BAAALAAECgYICgAAAA==.',Ta='Tabknight:BAAALAAECgYIDwAAAA==.Taelron:BAAALAADCggICAAAAA==.Taelstard:BAAALAADCggIFgAAAA==.Taithos:BAAALAAECgMIBAAAAA==.Talian:BAAALAAECgMIBgAAAA==.Tanki:BAAALAADCgEIAQAAAA==.Taranisis:BAAALAAECgQIBAAAAA==.Targetone:BAAALAAECgcIDwAAAA==.Taryion:BAAALAAECgIIAgAAAA==.Taylorswift:BAAALAADCgQIBAAAAA==.Tazer:BAAALAADCggIDwAAAA==.',Te='Tech:BAAALAAECgQICAAAAA==.Teenaflay:BAAALAADCgMIAwAAAA==.Teleman:BAAALAADCgcIEgAAAA==.Telyndra:BAAALAADCgEIAgAAAA==.Tenleigh:BAAALAADCggIGQAAAA==.Terongore:BAAALAADCgYIBgAAAA==.Terrorizor:BAAALAAECgQIBQAAAA==.Teylielock:BAAALAADCgIIAgAAAA==.',Th='Thaldh:BAAALAAECgYIBgABLAAECggICAABAAAAAA==.Thalpally:BAAALAAECggICAAAAA==.Thargor:BAAALAAECgYICAAAAA==.Thatmongrel:BAAALAAECgQICAAAAA==.Thazix:BAAALAADCgcIDQABLAAECgQICAABAAAAAA==.Thefluffyman:BAAALAAECgMIBAAAAA==.Themuffinmañ:BAAALAADCgcIBwAAAA==.Thendroz:BAAALAAECgMIAwAAAA==.Thiss:BAAALAAECgQICAAAAA==.Threepercent:BAABLAAECoEXAAMQAAgIVxbfBwBLAgAQAAgIVxbfBwBLAgARAAEIjAGELAAWAAAAAA==.Thwakette:BAAALAADCgcICAAAAA==.',Ti='Tianjiao:BAAALAADCgYIBgAAAA==.Tinnysmasher:BAAALAADCggIDwAAAA==.',To='Toehacker:BAAALAAECgcIDgAAAA==.Toenibbler:BAAALAAECgYICgAAAA==.Toliman:BAAALAADCgcIBwAAAA==.Tomicko:BAAALAADCgYIBgAAAA==.Totek:BAAALAAECgMIBAAAAA==.Totemraiser:BAAALAADCgIIAgAAAA==.Touched:BAAALAADCgYIBgAAAA==.',Tr='Trailblayze:BAAALAAECgQIBQAAAA==.Traser:BAAALAADCgYIBgAAAA==.Trenhard:BAAALAADCgUIBQAAAA==.Trishula:BAAALAAECgIIAgAAAA==.Trixkiddo:BAAALAADCgQIBAAAAA==.Trollgar:BAAALAADCgcICAAAAA==.Trollhog:BAAALAADCgYIBgAAAA==.Trucmuche:BAAALAAECgIIAgAAAA==.Truenorth:BAAALAADCggIFgAAAA==.Trugg:BAAALAADCgMIAwAAAA==.',Ts='Tsunda:BAAALAAECgYICwAAAA==.',Tu='Tubular:BAAALAAECgMIAwAAAA==.Tuckks:BAAALAADCgYIBgAAAA==.Tuns:BAAALAADCgIIAgAAAA==.Tuskwarden:BAAALAADCgcIDAAAAA==.',Tw='Twobladebray:BAAALAAECgIIAgAAAA==.Twofresh:BAAALAAECgcIDQAAAA==.',Ty='Tychronus:BAAALAAECgMIBQAAAA==.Tycse:BAAALAAECgMIAwAAAA==.Tyladrel:BAAALAADCgYIBgAAAA==.Tyraceon:BAAALAADCggIBwAAAA==.Tyrazar:BAABLAAECoEYAAINAAgIOyTpBAAzAwANAAgIOyTpBAAzAwAAAA==.Tyrowa:BAAALAADCgcIBwAAAA==.Tyth:BAAALAADCgcIBwAAAA==.Tyths:BAAALAAECgMIBQAAAA==.',Ug='Uglymother:BAAALAADCgEIAQAAAA==.',Ul='Ultuulla:BAAALAAECgYICAAAAA==.',Un='Unceunce:BAAALAADCgcIBwAAAA==.',Ur='Urbanpandaa:BAAALAAECgMIAwAAAA==.Urôt:BAAALAAECgYIDwAAAA==.',Uw='Uwusue:BAAALAAECggIEAAAAA==.',Va='Vaeboss:BAAALAADCgYIBgAAAA==.Vahennys:BAAALAAECgMIAwAAAA==.Valcoran:BAAALAADCggICQAAAA==.Valkyriecain:BAAALAADCggIFQAAAA==.Valsurin:BAAALAADCgcIEQAAAA==.Vanye:BAAALAADCgMIAwAAAA==.Varainne:BAAALAAECgYICwAAAA==.Varidina:BAAALAAECgQIBQAAAA==.',Ve='Velgath:BAABLAAECoEXAAISAAgIiSIUAgCiAgASAAgIiSIUAgCiAgAAAA==.Velkhana:BAAALAADCggICAAAAA==.Veluna:BAAALAADCggIEgAAAA==.Venmonk:BAAALAAECgYICgAAAA==.Veratis:BAAALAADCggIFAAAAA==.Verdisa:BAAALAADCgcICgAAAA==.Verii:BAAALAAECgYICAAAAA==.',Vh='Vhorach:BAAALAADCggIFwAAAA==.',Vi='Vioneva:BAAALAAECgQICAAAAA==.Viscelia:BAAALAAECgYICAAAAA==.Vivyregosa:BAAALAAECgMIBgAAAA==.Vizir:BAAALAAECgMIAwAAAA==.',Vo='Volcanoth:BAAALAAECgEIAQABLAAECgYICAABAAAAAA==.',Vv='Vvevv:BAAALAADCggICAAAAA==.Vvoid:BAAALAAECgMIAwAAAA==.',Vx='Vxi:BAABLAAFFIEGAAITAAMIshXeAQAfAQATAAMIshXeAQAfAQAAAA==.',Wa='Wain:BAAALAADCggIFgAAAA==.Wangmar:BAAALAADCgQIBwAAAA==.Warder:BAAALAAECgYIBwAAAA==.Wardon:BAAALAADCgYICwAAAA==.Warpig:BAAALAAECgQIBQAAAA==.Warriormilan:BAAALAADCgcICgAAAA==.Warstrength:BAAALAADCgUICgAAAA==.',Wh='Whiteopal:BAAALAAECgQICAAAAA==.',Wi='Willum:BAAALAAECgMIAwAAAA==.Winbayn:BAAALAADCggIGAAAAA==.',Wo='Wolfmort:BAAALAADCgcIEgAAAA==.Wolfà:BAAALAAECgYICAAAAA==.',Wy='Wytglary:BAAALAADCgYICQAAAA==.',Xa='Xanetia:BAAALAADCggIDwAAAA==.',Xb='Xblàdes:BAAALAADCgcIDgABLAAECggICAABAAAAAA==.',Xe='Xeara:BAAALAADCgcIDQABLAAECgEIAQABAAAAAA==.Xenmage:BAAALAADCgcIDAAAAA==.',Xi='Xinee:BAAALAADCgUIBQAAAA==.Xinhui:BAAALAADCggIDQABLAAECgMIBgABAAAAAA==.Xint:BAAALAAECgQIBAAAAA==.Xinti:BAAALAAECgUICAAAAA==.',Xt='Xtee:BAAALAAECgMIAwAAAA==.',Ya='Yahuu:BAAALAADCggICAAAAA==.Yamasharma:BAAALAADCggIGQAAAA==.',Ye='Yelbodha:BAAALAADCgcIDQAAAA==.Yesbeezy:BAAALAADCggIDQABLAAECgcIDwABAAAAAA==.',Yu='Yuber:BAAALAAECgYICAAAAA==.',Za='Zagrax:BAAALAADCgIIAwAAAA==.Zaharax:BAAALAAECgQIBQAAAA==.Zakron:BAAALAAECgYIBwAAAA==.Zandalarihee:BAAALAADCgEIAQAAAA==.Zazfradaz:BAAALAADCgIIAgAAAA==.',Ze='Zex:BAAALAAECgQICAAAAA==.',Zh='Zhanqui:BAAALAAECgQIBQAAAA==.',Zi='Ziba:BAAALAAECgcIDQAAAA==.Zitalth:BAAALAADCgYIBgAAAA==.',Zo='Zoomiezoomz:BAAALAADCgQIBAAAAA==.',Zu='Zudo:BAAALAAECgMIBQAAAA==.Zuthrais:BAAALAAECgYICwAAAA==.Zuulik:BAAALAAECgQIBwAAAA==.',['Zè']='Zèn:BAAALAADCgcIBwAAAA==.',['ßo']='ßocleèe:BAAALAAECgYICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end