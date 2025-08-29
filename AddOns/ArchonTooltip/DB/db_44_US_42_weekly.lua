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
 local lookup = {'Unknown-Unknown','Shaman-Restoration','Warlock-Destruction','Warlock-Demonology','Rogue-Subtlety','Evoker-Devastation','Warrior-Fury','DemonHunter-Havoc','Warlock-Affliction','Hunter-Marksmanship','Paladin-Protection',}; local provider = {region='US',realm='Bonechewer',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acelliste:BAAALAADCgcIDQAAAA==.Acrylix:BAAALAADCgIIAgAAAA==.',Ae='Aesveld:BAAALAADCgcIEwAAAA==.',Af='Afrit:BAAALAAECgcICwAAAA==.',Ag='Agramon:BAAALAADCgEIAQAAAA==.',Ah='Aheagan:BAAALAADCggICAAAAA==.',Ai='Airwalkin:BAAALAADCgUIBQAAAA==.',Ak='Akholymomma:BAAALAADCgcIDAAAAA==.',Al='Alzulra:BAAALAADCggICAAAAA==.',Am='Ambrosya:BAAALAADCgYIBgAAAA==.Amoridal:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Amyth:BAABLAAECoEUAAICAAgIjSMgAgANAwACAAgIjSMgAgANAwAAAA==.',An='Analiverson:BAAALAADCggIDQAAAA==.Anamay:BAAALAAECgMIAwAAAA==.Anesti:BAAALAADCggICAAAAA==.Ang:BAAALAAECgEIAQAAAA==.Angmonkey:BAAALAADCggICAAAAA==.Angrydragon:BAAALAADCggIEgAAAA==.Annabelle:BAAALAADCgcIBwAAAA==.Annylah:BAAALAADCgEIAQAAAA==.',Ap='Apocolypse:BAAALAAECgEIAQAAAA==.',Aq='Aqualily:BAAALAADCgYIBgAAAA==.',Ar='Armsnagos:BAAALAADCgYIBgAAAA==.Artanis:BAAALAAECgYICQAAAA==.Articüno:BAAALAADCgUIBwAAAA==.',As='Astarouge:BAAALAAECgYIDwAAAA==.Astraprowl:BAAALAAECgcICQAAAA==.',At='Atchafalaya:BAAALAAECgMIBAAAAA==.',Au='Aurianz:BAAALAADCgcIBwAAAA==.',Av='Avayl:BAAALAAECgIIAgAAAA==.',Aw='Awa:BAAALAAECggIAwAAAA==.Awesham:BAAALAAECgEIAQAAAA==.',Az='Azgra:BAAALAADCgMIAwAAAA==.Azrion:BAAALAADCgcIDAAAAA==.Azuraa:BAAALAAECgMIAwAAAA==.Azuroki:BAAALAADCggIDQAAAA==.Azylrog:BAAALAADCggIDgAAAA==.',Ba='Baalrin:BAAALAADCgcIDQAAAA==.Balehorn:BAAALAAECgcIBwAAAA==.Bantoou:BAAALAADCggIFgAAAA==.Baratheion:BAAALAADCggIFwAAAA==.',Be='Beardran:BAAALAAECgYIBwAAAA==.Beardybear:BAAALAAECgYICAAAAA==.Bearhug:BAAALAADCgYICAAAAA==.Bearrelroll:BAAALAAECgYICgAAAA==.Beautiful:BAAALAADCgcIBwAAAA==.Beaverino:BAAALAADCgUIBwAAAA==.Beefcakedup:BAAALAAECgMIBwAAAA==.Beefshaft:BAAALAADCggIDwAAAA==.Belldren:BAAALAADCgMIBAAAAA==.Bellonna:BAAALAADCgUIBQAAAA==.Bellroch:BAAALAADCgUIBAAAAA==.Bendru:BAAALAAECgMIAwAAAA==.Bergidum:BAAALAADCgIIAgAAAA==.Berryhealtwo:BAAALAAECgIIAgAAAA==.Bestbuybully:BAAALAAECggIEAAAAA==.Bewbadeboo:BAAALAADCgUIBQAAAA==.Bewmy:BAAALAADCgcIDQAAAA==.',Bi='Bigboybob:BAAALAADCgcICAAAAA==.Biglett:BAAALAAECgYIDgAAAA==.Bigpoomper:BAAALAADCgYIBgABLAAECgIIBAABAAAAAA==.Bigweez:BAAALAADCgMIAwAAAA==.Billyjean:BAAALAADCgEIAQAAAA==.Binascary:BAAALAADCgcICgAAAA==.Bizzymage:BAAALAADCgYIBgAAAA==.',Bl='Blackk:BAAALAAECgcIEAAAAA==.Blastur:BAAALAADCgIIAgAAAA==.Blazenhaze:BAAALAAECgcICgAAAA==.Bloodruines:BAAALAADCgcIBwAAAA==.Blorglock:BAABLAAECoEUAAMDAAgIYxd6DwBYAgADAAgIYxd6DwBYAgAEAAYIKgnAHgAgAQAAAA==.Blorgon:BAAALAADCgcICAABLAAECggIFAADAGMXAA==.Blowaegis:BAAALAADCgQIBwAAAA==.Blupenguiny:BAAALAAECgYIDQAAAA==.',Bo='Bobasaurus:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.Bohngjitsu:BAAALAAECgEIAQAAAA==.Bombastik:BAAALAADCgEIAQAAAA==.Borelane:BAAALAADCgcIBwAAAA==.Bountie:BAAALAAECgMIAwAAAA==.Bourthun:BAAALAAECgEIAQAAAA==.Bovinepally:BAAALAAFFAEIAQAAAA==.Bowldur:BAAALAADCggICwAAAA==.',Br='Braando:BAAALAADCggIDQAAAA==.Brand:BAAALAADCgMIAwAAAA==.Braz:BAAALAADCgIIAgAAAA==.Brickaroni:BAAALAADCggICgAAAA==.Bronnxx:BAAALAAECggIEgAAAA==.Bryanna:BAAALAADCgMIAwAAAA==.',Bt='Bty:BAAALAAECgMIAwAAAA==.',Bu='Bubblebitc:BAAALAADCgcIBwAAAA==.Bugatti:BAAALAADCgcIBwAAAA==.Buhtpluhg:BAAALAADCgIIAgAAAA==.Bullrûsh:BAAALAAECgIIAgAAAA==.Bulwa:BAAALAAECgYICgAAAA==.Burgy:BAEALAADCggIEgAAAA==.Busterb:BAAALAAECgMIAwAAAA==.Butwhistle:BAAALAADCgEIAgAAAA==.',By='Byebyeyou:BAAALAADCggIDQAAAA==.Byte:BAAALAAECgEIAQAAAA==.',Ca='Califax:BAAALAAECgMIBAAAAA==.Cannonbaul:BAAALAADCggIEAAAAA==.Canuckcow:BAAALAADCgYIBgAAAA==.Captantrips:BAAALAADCgcICQAAAA==.Carltonswag:BAAALAADCggIDwAAAA==.Caronagiver:BAAALAAECgEIAQAAAA==.Catbear:BAAALAADCgYIBgAAAA==.Catclown:BAAALAADCgcIFQAAAA==.Cavonesee:BAABLAAECoEXAAIFAAgIER9pAQDcAgAFAAgIER9pAQDcAgAAAA==.Cazzu:BAAALAADCgcIBwAAAA==.',Ch='Chalio:BAAALAADCgYIBgAAAA==.Channis:BAAALAADCggICwAAAA==.Chaosgoblin:BAAALAAECgMIAwAAAA==.Charyss:BAAALAADCgYIBgAAAA==.Chinobear:BAAALAAECgIIAgAAAA==.Choculaa:BAAALAADCgMIAwAAAA==.Chomi:BAAALAAECgQIBwAAAA==.Chugiak:BAAALAAECgQICAAAAA==.Chun:BAAALAADCgYIBgAAAA==.',Ci='Cidemon:BAAALAAECgYIBgAAAA==.',Cl='Claimore:BAAALAADCgQICAAAAA==.Class:BAAALAADCggIBwAAAA==.',Co='Coldsnacks:BAAALAADCgYIBgAAAA==.Colettee:BAAALAADCggIDgAAAA==.Copper:BAAALAADCggIEAAAAA==.Cornan:BAAALAADCgcIDgAAAA==.Cosdapanda:BAAALAADCgcIDQAAAA==.Cow:BAAALAADCgcIBwAAAA==.Cowspots:BAAALAAECgEIAQAAAA==.',Cr='Cracken:BAAALAADCgcIEgAAAA==.Cranksta:BAAALAAECgMIAwAAAA==.Crazymilkman:BAAALAADCgcIBAAAAA==.Crisantemo:BAAALAADCgcIBwABLAAECggIFgADAL4VAA==.Critndotz:BAAALAAFFAIIAgAAAA==.Crusherlul:BAAALAAECgYICQAAAA==.',Cu='Cubu:BAAALAAECgIIAgAAAA==.Cuerpo:BAAALAADCggIEAAAAA==.Curamendor:BAAALAADCgcIDgAAAA==.',['Cÿ']='Cÿ:BAAALAADCggICAAAAA==.',Da='Daboomkin:BAAALAAECgMIBAAAAA==.Daddy:BAAALAADCgEIAQAAAA==.Dahlya:BAAALAADCgYIBgABLAADCggIDwABAAAAAA==.Darieri:BAAALAAECgMIAwAAAA==.Darkroyal:BAAALAADCggICAAAAA==.Darkroyalt:BAAALAADCgcIBwAAAA==.Darkvagician:BAAALAADCggIDwAAAA==.Darralic:BAAALAAECgIIAwAAAA==.Darthjomal:BAAALAAECgEIAQAAAA==.Darthkitsune:BAAALAAECgMIBQAAAA==.Datbubblelol:BAAALAAECgEIAQAAAA==.Datfoxxie:BAAALAADCgcIDQAAAA==.Dazbek:BAAALAAECgUIBgAAAA==.',De='Deali:BAAALAADCgYIBgAAAA==.Deathkillz:BAAALAADCgMIAwAAAA==.Deathmethod:BAAALAADCgcIEQAAAA==.Deejie:BAAALAADCgEIAQAAAA==.Degeneffe:BAAALAAECgMIAwAAAA==.Delisenna:BAAALAAECgYIBgAAAA==.Demoreknight:BAAALAAECgYIDQAAAA==.Derelictt:BAAALAAECgEIAQAAAA==.Derelictx:BAAALAADCgMIAwAAAA==.Dertkalklu:BAAALAADCgcIBwAAAA==.Devilboy:BAAALAAECgYIDAAAAA==.Devinhunter:BAAALAADCggIDwAAAA==.Dezin:BAAALAAECgQICAAAAA==.',Di='Diablosagony:BAAALAADCgMIAwAAAA==.Diippndotss:BAAALAAECggIAwAAAA==.Dirtydaggers:BAAALAADCgcICAAAAA==.Discbrown:BAAALAADCgcIBwAAAA==.Discmemommy:BAAALAAECgIIAgABLAAECgIIBAABAAAAAA==.Discontent:BAAALAADCggIDQAAAA==.',Dj='Djblink:BAAALAAECgYIBwAAAA==.',Dk='Dkmonkey:BAAALAADCggIEQAAAA==.Dknuggs:BAAALAAECgIIAwAAAA==.Dkteek:BAAALAADCgcIAQAAAA==.',Do='Dogeared:BAAALAAECgIIAgABLAAECgMIBAABAAAAAA==.Dollparts:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.Dolour:BAAALAADCgcIBwAAAA==.Domïnatorz:BAAALAADCgMIAwAAAA==.Donaldgump:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.Doomlakalaka:BAAALAAECgIIBAAAAA==.Doomshamalam:BAAALAADCggIDgAAAA==.Doomslaayer:BAAALAAECgEIAQAAAA==.Doongsu:BAAALAAECgcIEwAAAA==.',Dr='Dracthwnd:BAAALAAFFAIIAgAAAA==.Dragbrown:BAABLAAECoEUAAIGAAgI2hzeCACSAgAGAAgI2hzeCACSAgAAAA==.Dragonjuice:BAAALAADCgcIBwAAAA==.Dragonsins:BAAALAAECgcIEAAAAA==.Dragonzx:BAAALAAECgQIAwAAAA==.Drahron:BAAALAADCggICAAAAA==.Drarrior:BAAALAADCggICAAAAA==.Dratér:BAAALAADCgUIBQAAAA==.Dreadshade:BAAALAADCgMIAwAAAA==.Drippymfdave:BAAALAAECgMIAwAAAA==.Droptopp:BAAALAAECgUICAAAAA==.Drtoolow:BAAALAADCggIDAAAAA==.Druidknight:BAAALAADCgMIBgABLAAECgYIDQABAAAAAA==.Drusys:BAAALAADCgcIDgAAAA==.Dryrod:BAAALAADCgYIBgAAAA==.',Du='Duckeye:BAAALAAECgcIEgAAAA==.Dunranger:BAAALAAECggICAAAAA==.Durto:BAAALAADCgcIBwAAAA==.',Dw='Dwntwnstabby:BAAALAADCgcIDQAAAA==.',['Dã']='Dãftmõnk:BAAALAAECgUIBQAAAA==.',['Dï']='Dïlf:BAAALAADCggIDwAAAA==.',['Dö']='Dötz:BAAALAADCgYICwABLAAECgEIAQABAAAAAA==.',Ee='Eelysa:BAAALAADCggIDgAAAA==.Een:BAAALAADCgcIDgAAAA==.',Eg='Egdar:BAAALAADCgcIBgAAAA==.',Ek='Ekiki:BAAALAADCggICwAAAA==.',El='Elathos:BAAALAAECgEIAQAAAA==.Elementothro:BAAALAADCgYIBgAAAA==.Elisaveta:BAAALAAECgMIAwAAAA==.Elliaa:BAAALAAECgMIAwAAAA==.Ellonia:BAAALAADCggIDwAAAA==.Elmahikera:BAAALAADCggIDQAAAA==.Eltrucko:BAAALAAECgIIAgAAAA==.',Em='Emordon:BAAALAADCgcIBwAAAA==.Empharmd:BAAALAAECgYICAAAAA==.',Ep='Epocharium:BAAALAADCgEIAQAAAA==.',Er='Eredar:BAAALAAECgIIAgAAAA==.',Es='Esteagee:BAAALAADCgIIAgAAAA==.',Ev='Everthell:BAAALAADCgcICQAAAA==.',Ex='Excite:BAAALAADCggIAgAAAA==.',['Eô']='Eôwyn:BAAALAAECgEIAQAAAA==.',Fa='Faelasong:BAAALAAECgIIAgAAAA==.Faesdelin:BAAALAAECgMIAwAAAA==.Faketurkey:BAAALAADCggICAAAAA==.Falkhor:BAAALAADCggIFQAAAA==.Fallenvixen:BAAALAAECgYIBgAAAA==.Farikarina:BAAALAADCgcIDQAAAA==.Fatlootz:BAAALAAECgIIBAAAAA==.Fatticus:BAAALAADCgcIBwAAAA==.Fattyonce:BAAALAAECgYICQAAAA==.',Fe='Feingsung:BAAALAADCgUIBQAAAA==.Feldia:BAAALAAECgEIAQAAAA==.Felpanda:BAAALAAECgcIDQAAAA==.Fender:BAAALAADCggIDwAAAA==.',Fi='Fiftyxis:BAAALAAECgYICgAAAA==.Fiorina:BAAALAAECgYICgAAAA==.Firewood:BAAALAADCgMIAwAAAA==.Fishnet:BAAALAADCgcIDgAAAA==.Fishthicc:BAAALAADCggIDgAAAA==.Fizzènator:BAAALAADCggICwAAAA==.Fizzënator:BAAALAADCgEIAQAAAA==.',Fj='Fjourd:BAAALAADCgcIBwAAAA==.',Fl='Flameborn:BAAALAAECgYIBgAAAA==.Flamerite:BAAALAADCggICAAAAA==.Flexkin:BAAALAAECgYICgAAAA==.',Fo='Fornor:BAAALAAECgMIBAAAAA==.Foxfù:BAAALAADCggIDAAAAA==.Foxkníght:BAAALAAECggIEgAAAA==.',Fr='Franký:BAAALAADCggIDAAAAA==.Fritobandito:BAABLAAECoEVAAIHAAgIgCV3AQBnAwAHAAgIgCV3AQBnAwAAAA==.Frostynips:BAAALAADCgEIAQAAAA==.Fruitbowl:BAAALAADCgYIBgABLAAECgcIEQABAAAAAA==.',Fu='Fungbuck:BAAALAADCggICAAAAA==.Furryglitch:BAAALAADCgQIBAAAAA==.Fushigi:BAAALAADCgcICgAAAA==.Fuzzymittens:BAAALAAECgYIDAAAAA==.',Fy='Fyrdrakon:BAAALAAECgUICAAAAA==.',Ga='Gamil:BAAALAAECgYICgAAAA==.Gandalar:BAAALAADCgIIAgAAAA==.Gashrot:BAAALAADCgcIDAAAAA==.',Gh='Gheezpal:BAAALAAECgEIAQAAAA==.Gheezrogue:BAAALAADCgEIAQAAAA==.Gheros:BAAALAADCgcIDgAAAA==.Ghettox:BAAALAADCgUIBwAAAA==.Ghrell:BAEALAAECgYICgAAAA==.',Gi='Gigglepeak:BAAALAAECgQIBwAAAA==.Girlhands:BAAALAADCggIDgAAAA==.Girthen:BAAALAAECgYIBgAAAA==.',Gn='Gnaumarsh:BAAALAADCgYIBgAAAA==.Gnormage:BAAALAAECgQIBwAAAA==.',Go='Gonuhreeuh:BAAALAADCgEIAQAAAA==.Gooninggoat:BAAALAADCgYIBgAAAA==.Gorecrush:BAAALAAECgIIAwAAAA==.Gorimath:BAAALAAECgYIBgAAAA==.Gorrtusk:BAAALAADCgIIAgABLAAECgYIBgABAAAAAA==.Gothrin:BAAALAADCgcIBwAAAA==.',Gr='Grattick:BAAALAADCggIFgAAAA==.Graultan:BAAALAADCgcIBgAAAA==.Greenlightt:BAAALAADCgYIBgAAAA==.Greenxll:BAAALAAECgYIDAAAAA==.Greypa:BAAALAADCgcIDgAAAA==.Gribbo:BAAALAAECgMIAwAAAA==.Grimben:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Grimm:BAAALAAECggIEgAAAA==.Grin:BAAALAADCgQIBAAAAA==.Grolk:BAAALAAECgEIAQAAAA==.Grrimad:BAAALAADCgcIBwAAAA==.',Ha='Habibii:BAAALAADCgEIAQAAAA==.Halfhorn:BAAALAADCgcIBgAAAA==.Halfordium:BAAALAAECgIIBAAAAA==.Hardlylokdup:BAAALAAECgMIBAAAAA==.Hardlystabz:BAAALAADCgEIAQAAAA==.Harryplopper:BAAALAADCgEIAQAAAA==.Harvine:BAAALAADCgUIAwAAAA==.Hat:BAAALAADCggIFAAAAA==.Hatedbymany:BAAALAAECgEIAQAAAA==.Hawkmees:BAAALAAECgYICgAAAA==.',He='Heavyhanu:BAAALAADCggICwAAAA==.Hellebron:BAAALAADCggICAAAAA==.Hellmageddon:BAAALAAECggIBgAAAA==.Hellsphyre:BAAALAAECgUIBgAAAA==.Hellxan:BAAALAAECgcIDQAAAA==.Herrbunger:BAAALAADCgEIAQAAAA==.Hexuz:BAAALAAECgMIAwAAAA==.',Hi='Hidngingardn:BAAALAADCgMIAwAAAA==.Hipster:BAAALAAECgYICwAAAA==.',Ho='Hoarfrahst:BAAALAAECgYIBgAAAA==.Hofficer:BAAALAADCggIDwAAAA==.Hoji:BAAALAADCggIFgAAAA==.Holycow:BAAALAADCgcIBwAAAA==.Holyfok:BAAALAADCgYIBgAAAA==.Hoodeeni:BAAALAADCgcIBwAAAA==.Hotimisprime:BAAALAAECgEIAQAAAA==.Hourglass:BAAALAADCgcICAABLAAECgUIBQABAAAAAA==.Hozrozlok:BAAALAADCggIEAAAAA==.Hoöd:BAAALAAECgEIAQAAAA==.',Hu='Huntardoh:BAAALAADCgQIBAAAAA==.Hurkola:BAAALAADCgEIAQAAAA==.',Hy='Hyacïnth:BAAALAAECggIEgAAAA==.Hypereon:BAAALAAECgYIDgAAAA==.',['Hü']='Hülksmash:BAAALAADCggIDgAAAA==.',Ic='Iciaroyalvix:BAAALAADCggIDwAAAA==.Iconocrypt:BAAALAAECgMIBAAAAA==.',Id='Idkdude:BAAALAAECgYICgAAAA==.',Il='Illadarina:BAAALAADCgcIFQAAAA==.Illyza:BAAALAADCgcICAAAAA==.',Im='Imgooning:BAAALAADCgcIBwAAAA==.',In='Ingara:BAAALAAECgMIBAAAAA==.Invel:BAAALAADCgcIBwAAAA==.',Ip='Iprotectu:BAAALAADCgYIBAAAAA==.',Ir='Iradoria:BAAALAAECgcIEAAAAA==.',Is='Isabellayx:BAAALAADCgYIBgAAAA==.',It='Itamï:BAAALAAECgYICgAAAA==.Ithostus:BAAALAAECgQIBwAAAA==.',Ja='Jaagren:BAAALAAECgUICAAAAA==.Jacby:BAAALAAECggIEgAAAA==.Jakaxe:BAAALAADCggIDQAAAA==.Jayneb:BAAALAADCgQIBAAAAA==.Jayrel:BAAALAAECggIEgAAAA==.Jaytheg:BAAALAAECgYIEQAAAA==.Jaythep:BAAALAADCgQIBAAAAA==.',Jj='Jjaann:BAAALAAECgIIAwAAAA==.',Jo='Jocoby:BAAALAADCggIDAABLAAECggIEgABAAAAAA==.Joeyexotic:BAAALAADCgcIDgAAAA==.Jokem:BAAALAADCgEIAQAAAA==.Jomal:BAAALAADCggIDQAAAA==.',Ju='Juankkii:BAAALAADCgYICAAAAA==.Juggerbear:BAAALAAECgMIAwAAAA==.Juiçy:BAAALAADCggIDgAAAA==.Juls:BAAALAAECgYICgAAAA==.Junbee:BAAALAAECgcIDQAAAA==.Junebug:BAAALAAECgQIBgAAAA==.',['Já']='Jáckfrost:BAAALAAECgcICgAAAA==.',Ka='Kabage:BAAALAAECgMIBAAAAA==.Kabera:BAAALAADCgIIAgAAAA==.Kaeby:BAAALAAECgYIBgAAAA==.Kaelexi:BAAALAADCgYIBgAAAA==.Kalatai:BAAALAAECgcIEAAAAA==.Kalindora:BAAALAAECgYIBgAAAA==.Kantbreathe:BAAALAADCgEIAQAAAA==.Karavin:BAAALAADCgQIBAAAAA==.Karayna:BAAALAAECgYICQAAAA==.Katyparry:BAAALAADCgIIAgAAAA==.',Ke='Keadron:BAAALAAECgEIAQAAAA==.Kerriandra:BAAALAADCgUIBwAAAA==.Keystorm:BAAALAADCgYIBgAAAA==.Kezwik:BAAALAAECgIIAgAAAA==.',Kh='Khalanji:BAAALAAECgMIAwAAAA==.Khaotic:BAAALAADCgUICAAAAA==.Khóríc:BAAALAADCgcIDgAAAA==.',Ki='Killabreath:BAAALAAECgcIDgAAAA==.Killgoro:BAAALAAECgQIBQAAAA==.',Ko='Koodsy:BAAALAAECgYICAAAAA==.Korv:BAAALAADCgcIBwAAAA==.Kourtnee:BAAALAAECgQIBAAAAA==.',Kr='Kreiedril:BAAALAADCggIFAAAAA==.',Ky='Kyu:BAAALAAECgMIBQAAAA==.',['Kí']='Kíngcoyote:BAAALAADCgYIBwAAAA==.',['Kò']='Kòdlak:BAAALAADCggICAAAAA==.',['Ký']='Kýnareth:BAAALAADCgMIAwABLAADCggIDwABAAAAAA==.',La='Labrat:BAAALAADCgMIAwAAAA==.Lacedfent:BAAALAAECgYICwAAAA==.Ladiluxanna:BAAALAADCgcIBwAAAA==.Laeri:BAAALAADCgYIBgAAAA==.Larry:BAAALAADCgIIAgAAAA==.Last:BAAALAADCgcIBwAAAA==.Lavaken:BAAALAADCggIDQAAAA==.Laviish:BAAALAAECgEIAQAAAA==.',Le='Leaffist:BAAALAADCggIDgAAAA==.Leica:BAAALAADCgcIBwAAAA==.Letena:BAAALAAECgMIAwABLAAECgcIDQABAAAAAA==.Levyymage:BAAALAAECgQIBQAAAA==.',Li='Lieandis:BAAALAADCgQIBAAAAA==.Lilballohate:BAAALAADCggICAAAAA==.Lilspunky:BAAALAADCgIIAgAAAA==.Lilsxe:BAAALAADCgYIBgAAAA==.Linane:BAAALAADCggICgAAAA==.Litharin:BAAALAADCgIIAgAAAA==.',Lo='Locholiss:BAAALAADCgQIBAAAAA==.Losthobo:BAAALAADCgIIAgAAAA==.Lougim:BAAALAADCgYICwAAAA==.',Lu='Lunafrey:BAAALAADCgIIAgAAAA==.Lunakhaleesi:BAAALAADCgQIBAAAAA==.Lunti:BAAALAADCgQIBAAAAA==.Lurang:BAAALAADCggIEAAAAA==.Lursepal:BAAALAADCgIIAgAAAA==.',Ly='Lyphloria:BAAALAADCggICAAAAA==.',['Lü']='Lüna:BAAALAAECgEIAQAAAA==.',Ma='Madetolock:BAAALAADCgYIBgAAAA==.Maestro:BAAALAAECgMIBAAAAA==.Magebrew:BAAALAAECgIIAQAAAA==.Magicchris:BAAALAAECgYIBgAAAA==.Makroth:BAAALAADCgcIBwAAAA==.Maldraxxus:BAAALAAFFAEIAQAAAA==.Maliun:BAAALAAECgQIBQAAAA==.Mallaki:BAAALAAECgIIBAAAAA==.Malthael:BAAALAAECgYICgAAAA==.Malusdemon:BAAALAAECgYICgAAAA==.Mamasota:BAAALAAECgMIAwAAAA==.Mangø:BAABLAAECoEVAAIIAAcIcCSVCwDNAgAIAAcIcCSVCwDNAgAAAA==.Maraanawe:BAAALAADCgYIBgAAAA==.Marileth:BAAALAADCgIIAwAAAA==.Marisol:BAAALAADCgYIBgAAAA==.Markfunk:BAAALAAECgcIDgABLAAECggIBgABAAAAAA==.Markiepoo:BAAALAAECgIIAgABLAAECggIBgABAAAAAA==.Markyto:BAAALAAECggIBgAAAA==.Marquilias:BAAALAADCgEIAQAAAA==.Maryjaiyne:BAAALAAECgcIEQAAAA==.Maylibog:BAAALAAECgMIBQAAAA==.Mazterbeastn:BAAALAADCggIFwABLAAECgMIBAABAAAAAA==.',Mc='Mccoyastrasz:BAAALAADCgcICQAAAA==.',Me='Mechamuppet:BAAALAAECgcICQAAAA==.Meditations:BAAALAADCggICAAAAA==.Meleria:BAAALAAECgYICgAAAA==.Melledris:BAAALAADCggICAAAAA==.Menethall:BAAALAADCgMIAwAAAA==.Menopaws:BAAALAAECgEIAQAAAA==.Mexiflip:BAAALAAECgEIAQAAAA==.',Mi='Mikeropiness:BAAALAADCggICAAAAA==.Milgan:BAAALAAECgcIDQAAAA==.Minohtar:BAAALAADCggIEAAAAA==.Misthunder:BAAALAADCgUIBQAAAA==.Mizukitoushi:BAAALAADCgEIAQAAAA==.',Mo='Mogrokrim:BAAALAADCgcIBwAAAA==.Moldfeet:BAAALAADCgYIBgAAAA==.Molestisimo:BAAALAADCgcIBwAAAA==.Moloc:BAEALAAECgMIBAAAAA==.Moogul:BAAALAAECgIIAQAAAA==.Moomoodles:BAAALAAECgMIAwAAAA==.Mooseknukkle:BAAALAADCgQIBAAAAA==.Morbidknight:BAAALAAECggICAAAAA==.Moyali:BAAALAADCgcIBwAAAA==.',Ms='Mswilliams:BAAALAADCgcIDAAAAA==.',Mu='Mug:BAEALAAECgEIAQAAAA==.Multiblox:BAAALAAECgYIDAAAAA==.Muphistophol:BAAALAADCgcIBwAAAA==.Must:BAAALAADCgcIBwAAAA==.',My='Mykungfu:BAAALAADCgMIAwAAAA==.Myravantha:BAAALAADCgcICQAAAA==.Myrokorllan:BAAALAAECgQIBQAAAA==.',Na='Nadrin:BAAALAAECgQIBgAAAA==.Naedora:BAAALAAECgYICAAAAA==.Narugami:BAAALAADCggICAAAAA==.Naruwnd:BAAALAADCgQIBAAAAA==.Nazen:BAAALAADCggICAAAAA==.',Ne='Necrodamus:BAAALAAECgEIAQAAAA==.Nefar:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.Nekara:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Nekoashi:BAAALAAECgYICwAAAA==.Nem:BAAALAADCggIEAAAAA==.Nergaoul:BAAALAADCggICAAAAA==.Nerradin:BAAALAADCgcIBwAAAA==.Nevvss:BAAALAAECgUIBgAAAA==.Nezdin:BAAALAAECgMIAwAAAA==.Nezo:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.',Ni='Nickus:BAAALAADCgUIBwAAAA==.Nicoroben:BAAALAADCgcICgABLAADCggIDwABAAAAAA==.Ninean:BAAALAAECgMIAwAAAA==.Nirza:BAAALAAECgIIAwAAAA==.Niziel:BAAALAAECgcIDwAAAA==.',No='Noranis:BAAALAADCgEIAQAAAA==.Normann:BAAALAAECggICAAAAA==.Normò:BAAALAADCggICAABLAAECggICAABAAAAAA==.',Nu='Nuflana:BAAALAAECgMIBAAAAA==.',['Nì']='Nìcholas:BAAALAADCggIFwAAAA==.',Og='Ogazo:BAAALAAECgEIAQAAAA==.',Oj='Ojaqass:BAAALAAECgEIAQAAAA==.',Ol='Olddeadboy:BAAALAADCggICAABLAAECgcICwABAAAAAA==.Oldmagicalmo:BAAALAADCgQIBAAAAA==.Olgaa:BAAALAADCgYIBgAAAA==.',Om='Omenbane:BAAALAADCgQIBAAAAA==.',On='Oneman:BAAALAADCgcIBwAAAA==.Onlypans:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Or='Orkk:BAAALAADCgcIBwAAAA==.',Os='Oshenman:BAAALAAECgEIAQAAAA==.',Ou='Ouroborocrow:BAEALAAECgEIAQABLAAECgMIBAABAAAAAA==.',Ow='Owlgore:BAAALAADCggICAAAAA==.',Pa='Packtastic:BAAALAAECgIIAgAAAA==.Parketor:BAAALAADCggICAAAAA==.Pawchi:BAAALAADCgUICAAAAA==.Pawsitive:BAAALAADCggICQAAAA==.',Pe='Peludo:BAAALAADCgYIBwAAAA==.Perixi:BAAALAAECgcIDwAAAA==.',Ph='Phayge:BAAALAAECgMIAwAAAA==.Phedragon:BAAALAAECgcICwAAAA==.Phedrah:BAAALAADCggICAAAAA==.',Pi='Pilto:BAAALAAECgQIBwAAAA==.Pinkpwnagedk:BAAALAAECgYIDQAAAA==.Pinkpwnages:BAAALAAECgIIAgAAAA==.Pirada:BAAALAAECgMIAwAAAA==.Pistolwhip:BAAALAADCgIIAgAAAA==.',Po='Poachedeggs:BAAALAADCgEIAQAAAA==.Polymorph:BAAALAADCgEIAQAAAA==.Poosiehunter:BAAALAAECgYIBgAAAA==.Porkadobo:BAAALAAECgcICQAAAA==.',Pr='Preon:BAAALAADCgMIAwABLAAECgYIDQABAAAAAA==.Priestgaming:BAAALAADCggICQAAAA==.Pritasth:BAAALAAECgMIAwAAAA==.Protidal:BAAALAADCgQIBAAAAA==.Prutsloche:BAAALAAECgMIBgAAAA==.Prutsmere:BAAALAADCgYIBgAAAA==.Prutswyrth:BAAALAADCggIDQABLAAECgMIBgABAAAAAA==.',Ps='Psammophile:BAAALAAECgQIBgAAAA==.',Pu='Punchkick:BAAALAADCgUIBwAAAA==.Puntastic:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Purpleshroom:BAAALAADCggIDQAAAA==.Puuraann:BAAALAAECgQIBgAAAA==.',Py='Pyrat:BAAALAAECgIIBAAAAA==.Pyroangel:BAAALAADCggIFgAAAA==.',['Pá']='Páth:BAAALAAECgYICQAAAA==.',['Pÿ']='Pÿrö:BAAALAADCgcICwAAAA==.',Qu='Quinbroz:BAAALAADCgcIDwAAAA==.Quinexorable:BAAALAADCggICAAAAA==.Quinfernal:BAAALAAECggIEgAAAA==.Quintillion:BAAALAADCgcIBwAAAA==.Quitness:BAAALAADCgcIDwAAAA==.Quitnezz:BAAALAADCggIEgAAAA==.Qumgutters:BAAALAAECgIIAwAAAA==.',Ra='Raau:BAAALAAECgcIDQAAAA==.Raensfaer:BAAALAADCgYICwAAAA==.Ragnari:BAAALAAECgMIBAAAAA==.Rainndance:BAAALAAECgIIAwAAAA==.Ramrodveazy:BAAALAADCgMIAwAAAA==.Ranocthan:BAAALAADCggIDwAAAA==.Rarcher:BAAALAAECgMIAwAAAA==.Razorsharp:BAAALAAECgYICwAAAA==.Razwarlock:BAAALAADCgQIBAAAAA==.',Rb='Rbel:BAAALAADCgQICAAAAA==.',Re='Reapercreep:BAAALAADCgYIBgABLAAECgQIBQABAAAAAA==.Reckyourface:BAAALAADCggIFQAAAA==.Redghosst:BAABLAAECoEWAAQDAAgIvhUTGwDdAQADAAcIKxYTGwDdAQAJAAUI5QdzEwD8AAAEAAMIphVqKwDOAAAAAA==.Reedeemer:BAAALAADCgYIDAAAAA==.Reefermadnes:BAAALAAECgUIDAAAAA==.Relnamah:BAAALAADCgcIBwAAAA==.Reyofsun:BAAALAAECgYICQAAAA==.Reyzer:BAAALAADCgMIAwAAAA==.',Rh='Rhuna:BAAALAADCgEIAQAAAA==.Rhyllii:BAAALAAECgUICAAAAA==.',Ri='Rippler:BAAALAAECgYIDQAAAA==.',Ro='Rocksalt:BAAALAADCgYIBgAAAA==.Rompas:BAAALAADCggIDgABLAAECgUIBQABAAAAAA==.',Rs='Rsek:BAAALAADCgEIAQAAAA==.',Ru='Ruinah:BAAALAADCgcIFQABLAADCgEIAQABAAAAAA==.Rundazz:BAAALAAECgcIEQAAAA==.',Ry='Ryderye:BAAALAADCgcICwAAAA==.',['Rå']='Råz:BAAALAAECgMIAwAAAA==.',['Rí']='Rían:BAAALAADCgcIEAAAAA==.',Sa='Sacerdota:BAAALAADCggIEwAAAA==.Safezone:BAAALAADCggICAAAAA==.Sairadoka:BAAALAADCggIEAAAAA==.Sandwick:BAAALAADCgYIBgAAAA==.Sargerasboi:BAAALAAECgYICgAAAA==.Saroot:BAAALAAECgEIAQAAAA==.Sarris:BAAALAADCgcIBgAAAA==.',Sc='Scarlaffy:BAAALAAECgIIAgAAAA==.Scârlett:BAAALAADCgUIBQAAAA==.',Se='Seanasy:BAAALAADCgQIBAAAAA==.Sedaea:BAAALAAECgYIBgAAAA==.Seelu:BAAALAADCggICwAAAA==.Seepally:BAAALAADCggIDwAAAA==.Seerawh:BAAALAAECgIIAgAAAA==.Selune:BAAALAADCggIEQAAAA==.',Sg='Sgtgoku:BAAALAADCgcICwAAAA==.',Sh='Shadowbóurne:BAAALAADCgMIAwAAAA==.Shadownd:BAAALAADCggICgAAAA==.Shamergency:BAAALAAECgUIBwAAAA==.Shammymymy:BAAALAAECgMIAwAAAA==.Shammyrock:BAAALAADCggICAAAAA==.Shammywhammy:BAAALAADCggICAAAAA==.Sharayse:BAAALAAECgYIEQAAAA==.Sharked:BAAALAAECgIIAgAAAA==.Sharmee:BAAALAADCgcICwABLAAECgYIEQABAAAAAA==.Sharsu:BAAALAADCgQIBAABLAAECgYIEQABAAAAAA==.Sheepdrood:BAAALAAECgMIAwAAAA==.Shezowicked:BAAALAAECgEIAQAAAA==.Shiftysham:BAAALAAECgQIBAAAAA==.Shmacken:BAAALAADCgcIDQAAAA==.Shosannaa:BAAALAAECgMIBAAAAA==.Shoulderpad:BAAALAAECgYIDgAAAA==.Shredz:BAAALAADCgcIDwAAAA==.Shreknor:BAAALAAECgYIDAAAAA==.Shuriken:BAABLAAECoEUAAIKAAgI0ByqCQB/AgAKAAgI0ByqCQB/AgAAAA==.Shurra:BAAALAADCggICAABLAADCggIDwABAAAAAA==.Shàllteàr:BAAALAADCgMIAwAAAA==.Shèáthen:BAAALAADCgYICgAAAA==.',Si='Simpher:BAAALAADCgQIBAAAAA==.Sindazia:BAAALAADCgYIBgAAAA==.Siopau:BAAALAAECgEIAQAAAA==.',Sk='Skronkles:BAAALAAECgEIAQAAAA==.Skullthorn:BAAALAADCggIDwAAAA==.',Sl='Slomar:BAAALAAECgIIAwAAAA==.',Sm='Smoggely:BAAALAAECgIIAwAAAA==.Smòke:BAAALAADCggIDQAAAA==.',Sn='Snaw:BAAALAADCgEIAgAAAA==.Sneakypeet:BAAALAADCgQIBAAAAA==.Sneky:BAAALAAECgEIAQAAAA==.Snowbreeze:BAAALAADCggIDgAAAA==.',So='Solodk:BAAALAAECgYICwAAAA==.Soobatai:BAAALAADCgcICwAAAA==.Soot:BAAALAAECgMIBAAAAA==.Soots:BAAALAADCggIEwAAAA==.Sootzy:BAAALAAECgIIAgAAAA==.Soswordy:BAAALAADCgEIAQAAAA==.',Sp='Spadex:BAAALAAECgcIEAAAAA==.Spankky:BAAALAAECgMIAwAAAA==.Sparkkzz:BAAALAADCgQIBAAAAA==.Sparklite:BAAALAADCgcICwAAAA==.Speed:BAAALAAFFAEIAQABLAAFFAEIAQABAAAAAA==.Spicynoodles:BAAALAAECgEIAQAAAA==.',Sq='Squachy:BAAALAADCgQIAwABLAAECggIEgABAAAAAA==.Squirmer:BAAALAADCgYICQAAAA==.',St='Staybehindme:BAAALAADCgcICAAAAA==.Stdsrgodsdot:BAAALAADCgYICAAAAA==.Steadchi:BAAALAAECgYICgAAAQ==.Stealthgump:BAAALAAECgYIBwAAAA==.Steinhause:BAAALAADCggICAAAAA==.Stolibear:BAAALAAECgQIBAAAAA==.Stolimonk:BAAALAADCgcIBwAAAA==.Stolip:BAAALAADCgIIAgAAAA==.Stoliwar:BAAALAADCgYICQAAAA==.Stonehide:BAAALAADCgMIAwAAAA==.Straywalker:BAAALAAECgYICwAAAA==.Stublimë:BAAALAAECgQIBAAAAA==.Stupid:BAAALAAECggIEgAAAA==.',Su='Sugarfree:BAAALAADCgEIAQAAAA==.Summersunn:BAAALAADCggIFgAAAA==.Sungjinwooz:BAAALAADCgcIBwAAAA==.Sunshinenj:BAAALAADCgcIBwAAAA==.Sussin:BAAALAADCgcIBwAAAA==.',Sw='Swiftmourne:BAAALAADCgEIAQABLAAECggIBgABAAAAAA==.Swiftyar:BAAALAAECgUIBQAAAA==.Swudge:BAAALAAECgIIAgAAAA==.',Sy='Sylandrus:BAAALAADCgIIAgAAAA==.Syldronis:BAAALAADCgQIAwAAAA==.',['Sá']='Sápphíre:BAAALAADCgcICwAAAA==.',['Sâ']='Sâkÿ:BAAALAADCgcICAAAAA==.',Ta='Tachaka:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Tamedchaos:BAAALAADCgMIAwAAAA==.Tankass:BAAALAAECgEIAQAAAA==.Tankêthat:BAAALAADCgEIAQAAAA==.Tanzee:BAAALAADCggICAAAAA==.Taraya:BAAALAAECgMIAwAAAA==.Targuus:BAAALAADCgIIAgABLAAECgUIBQABAAAAAA==.Tarmarion:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Tarmesan:BAAALAAECggIDwAAAA==.',Te='Tegadin:BAAALAADCgYIBgAAAA==.Telluwhut:BAAALAAECgEIAQAAAA==.Tembu:BAAALAAECgIIAgAAAA==.Tenet:BAAALAADCggIDgAAAA==.Tennchuu:BAAALAAECgIIAgAAAA==.Tensarion:BAAALAADCgcICQABLAAECgMIAwABAAAAAA==.Tenspeed:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Tentickler:BAAALAADCgYIBgAAAA==.Tesse:BAAALAAECgYIDAAAAA==.Testsubjeck:BAAALAADCggIFAABLAAECgQIBQABAAAAAA==.',Th='Thacthephone:BAAALAAECgcICgAAAA==.Thannos:BAAALAAECgcIEQAAAA==.Thanos:BAAALAAECgcICQAAAA==.Tharick:BAAALAAECgMIAwAAAA==.Thawnn:BAAALAADCggICAAAAA==.Thebella:BAAALAADCgcICQAAAA==.Thebigd:BAAALAADCgYICgAAAA==.Thedagda:BAAALAADCgcIBwAAAA==.Thono:BAAALAADCggICAAAAA==.Thoring:BAAALAADCgYIBwAAAA==.Thraegar:BAAALAADCgcIDQAAAA==.Threem:BAAALAADCgcIBwAAAA==.Threew:BAAALAADCgcIBwAAAA==.Throad:BAAALAADCggIEAAAAA==.Throwbackhlz:BAAALAADCggIDQAAAA==.',Ti='Tides:BAABLAAECoEgAAICAAgIOB+OAgAAAwACAAgIOB+OAgAAAwAAAA==.Tideup:BAEALAAECgMIBAAAAA==.Timerush:BAAALAAECgcIDwAAAA==.Tinarii:BAAALAAECgIIAwAAAA==.Tiâ:BAAALAADCgUIBQAAAA==.',To='Toolow:BAAALAAECgYIDAAAAA==.Tornholio:BAEALAAECgMIBQABLAAECgMIBAABAAAAAA==.Toureg:BAAALAADCgMIAwAAAA==.Toxin:BAAALAADCgUIBQAAAA==.',Tr='Trashpanddi:BAAALAAECgMIBQAAAA==.Treehex:BAAALAADCggIDQAAAA==.Trell:BAAALAAECgEIAQAAAA==.Triblet:BAAALAADCgcIBwAAAA==.Tripel:BAAALAADCgUIBQAAAA==.Trollatarms:BAAALAAECgIIAgAAAA==.Trunksz:BAAALAAECgYIDgAAAA==.',Tu='Turkkey:BAAALAADCgUIBQAAAA==.',Tw='Twoman:BAAALAAECgYIDAAAAA==.Twylla:BAAALAADCgIIAgAAAA==.',Ty='Tyler:BAAALAAECgUICgAAAA==.Tynak:BAAALAAECgEIAQAAAA==.Tyolann:BAAALAADCgYIBgAAAA==.',Ul='Uldarin:BAAALAADCgUIBQAAAA==.',Um='Umbrâ:BAAALAADCgYIBgAAAA==.',Un='Unholybane:BAAALAADCgcIDgAAAA==.',Va='Vaader:BAAALAADCgMIAwAAAA==.Vakyr:BAAALAADCgUIBwAAAA==.Valifrit:BAAALAAECgYICgAAAA==.Valkanine:BAAALAADCggIEAAAAA==.Valonthir:BAAALAADCgYICQAAAA==.Valorak:BAAALAADCgEIAQAAAA==.Vanadrys:BAAALAADCggIDgAAAA==.Vancleave:BAAALAADCgcIEgAAAA==.Vanderas:BAAALAAECgMIBQAAAA==.',Ve='Veliøna:BAAALAAECgMIAwAAAA==.Vellichor:BAAALAADCgcIDAAAAA==.Veloy:BAAALAAECgMIAwAAAA==.Veraaheals:BAAALAADCggIDwAAAA==.',Vh='Vharka:BAAALAADCgMIAwAAAA==.',Vi='Viceless:BAAALAADCgYIBgAAAA==.Vildri:BAAALAADCggIEAAAAA==.Village:BAAALAADCgUIBQAAAA==.Vishus:BAEALAADCgYIBgABLAAECgEIAQABAAAAAA==.',Vo='Vornash:BAAALAADCggICwAAAA==.',Vy='Vylent:BAAALAADCgQIBwAAAA==.',Wa='Wardogsix:BAAALAADCgEIAQAAAA==.Warorwar:BAAALAADCgcICgAAAA==.',We='Weezfleez:BAAALAAECgIIAgAAAA==.Westlo:BAAALAADCggICwAAAA==.',Wh='Whiteraisins:BAAALAADCgQIBAAAAA==.',Wi='Wilfòrd:BAAALAAECgMIAwAAAA==.Willhelt:BAAALAADCggIDQAAAA==.Willows:BAAALAAECggIEAAAAA==.Wind:BAAALAADCggICQAAAA==.Wintersbear:BAAALAADCgcIEAAAAA==.Winterslock:BAAALAADCgYIBAAAAA==.',Wo='Wokecraftbad:BAAALAADCgcIBwAAAA==.',Wu='Wulflock:BAAALAAECgYICQAAAA==.Wulfmage:BAAALAADCgIIAgABLAAECgYICQABAAAAAA==.Wulfpriest:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.',Xa='Xanith:BAAALAADCgcIBwAAAA==.Xanthim:BAAALAAECgEIAQABLAAECggIGAALAKsaAA==.Xanthym:BAABLAAECoEYAAILAAgIqxrYBQBKAgALAAgIqxrYBQBKAgAAAA==.',Xc='Xcentrik:BAAALAADCgYIBgAAAA==.',Xe='Xelas:BAAALAADCgcIBwAAAA==.',Xo='Xoog:BAAALAADCggIFgAAAA==.',Xt='Xtremerundwn:BAAALAADCgEIAQAAAA==.',['Xâ']='Xân:BAAALAADCgUIBQAAAA==.',Ya='Yamina:BAAALAAECgcIDgAAAA==.',Ye='Yetirogue:BAAALAAECgMIAwAAAA==.',Yi='Yingolna:BAAALAAECgMIAwAAAA==.Yinkerbinker:BAAALAADCgcIBwABLAAECggIEgABAAAAAA==.',Yo='Yogr:BAAALAADCgIIAgAAAA==.',Yu='Yugaden:BAAALAAECgYICQAAAA==.Yungsoo:BAAALAADCggIEAAAAQ==.Yurii:BAAALAADCgcIBgAAAA==.Yurrie:BAAALAAECggIEgAAAA==.Yuzuhmi:BAAALAADCgIIAgAAAA==.',Za='Zarakynel:BAAALAADCggIDgAAAA==.Zath:BAAALAAECgMIBAAAAA==.Zaziki:BAAALAAECgMIBQAAAA==.Zazzerpän:BAAALAAECgIIAgAAAA==.',Ze='Zenolinwæ:BAAALAAECgIIAgAAAA==.',Zh='Zhufor:BAAALAADCgcIBwAAAA==.',Zi='Zingis:BAAALAADCggIEAAAAA==.Zivanya:BAAALAAECgMIAwAAAA==.',Zu='Zugomdai:BAAALAADCggIEwAAAA==.Zupaï:BAAALAAECgYICAAAAA==.',Zy='Zyloche:BAAALAADCgcIDQAAAA==.Zyp:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.',['Zë']='Zënolinwaë:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.',['Ãm']='Ãmillia:BAAALAADCgQIBAABLAADCgUIBQABAAAAAA==.',['Ém']='Émberthal:BAAALAAECgIIAwAAAA==.',['Îc']='Îcyhot:BAAALAAECgYICgAAAA==.',['Öv']='Överkill:BAAALAAECgMIBAAAAA==.',['ßi']='ßiøhâzzârd:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end