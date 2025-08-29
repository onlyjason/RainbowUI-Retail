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
 local lookup = {'Warrior-Fury','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology',}; local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aeliona:BAAALAAECgYIBwAAAA==.Aeternia:BAAALAAECgYIDwAAAA==.',Ag='Aginor:BAAALAAECgcIDAAAAA==.',Ah='Ahzamir:BAABLAAECoEVAAIBAAgIkCERBwD6AgABAAgIkCERBwD6AgAAAA==.',Ai='Aiunar:BAAALAADCggIDwAAAA==.',Al='Alakaxander:BAAALAADCgcICwAAAA==.Aleinara:BAAALAADCggIDwAAAA==.Alleriah:BAAALAADCggICQABLAAECgYIDgACAAAAAA==.Allhanla:BAAALAADCgUIBQABLAAECgUICQACAAAAAA==.Allidian:BAAALAAECgcIDgAAAA==.',An='Andsey:BAAALAADCgYIBgAAAA==.Anitaman:BAAALAADCgcIBwAAAA==.',Aq='Aquiel:BAAALAADCggIDwAAAA==.Aqular:BAAALAAECgEIAQAAAA==.',Ar='Ardian:BAAALAADCgYIBgAAAA==.',As='Asclepius:BAAALAAECgUICwAAAA==.Astraeuss:BAAALAAECgYICgAAAA==.',At='Atsunvhi:BAAALAADCgcIGAAAAA==.',Au='Aurorra:BAAALAAECgEIAQAAAA==.Aurroraa:BAAALAADCgcIBwAAAA==.',Az='Azrael:BAAALAAECgYICgAAAA==.',Ba='Balestrom:BAAALAADCgcICAABLAADCgcIGAACAAAAAA==.Barackobooma:BAAALAADCggIDAAAAA==.',Be='Beatdk:BAAALAADCggICAAAAA==.Beatman:BAAALAADCggICAAAAA==.Beatmán:BAAALAADCgIIAgAAAA==.Beefeater:BAAALAAECgcIDwAAAA==.Beniochan:BAAALAAECgMIAwAAAA==.Berryknight:BAAALAAECgYIBwAAAA==.Betwixt:BAAALAADCgcIBwAAAA==.',Bi='Biere:BAAALAADCgcIDAAAAA==.Bigzytix:BAAALAAECgMIAwAAAA==.Biirai:BAAALAAECgYICgAAAA==.Binky:BAAALAADCggICAAAAA==.',Bl='Blinktodome:BAAALAAECgEIAQABLAAECgIIAgACAAAAAA==.',Bo='Bonetatter:BAAALAADCgYICAABLAABCgMIAwACAAAAAA==.Booyä:BAAALAAECgIIAgAAAA==.Bownyxia:BAAALAAECgIIAgABLAAECggIGwADACklAA==.Bowtiekwondo:BAAALAADCggICgABLAAECggIGwADACklAA==.Bowties:BAABLAAECoEbAAMDAAgIKSWMBACHAgADAAYInyWMBACHAgAEAAcIYByyIAABAgAAAA==.',Br='Brucekneeroy:BAAALAADCggIEgAAAA==.',Bt='Btmanight:BAAALAADCgIIAgAAAA==.',Bu='Buugada:BAAALAAECgIIAgAAAA==.',Ca='Caedo:BAAALAADCgUIBQAAAA==.Calischism:BAAALAADCgcIDgAAAA==.Cassabry:BAAALAADCgcIBwAAAA==.Cato:BAAALAADCgYIBQAAAA==.Cayllia:BAAALAAECgQIBgAAAA==.',Ch='Cherrypepsï:BAAALAADCgYIBgAAAA==.Choom:BAAALAADCgcICwABLAAECgcIFAAFALclAA==.',Ci='Citrus:BAAALAAECgQIBQAAAA==.',Co='Codeman:BAAALAAECgYIDgAAAA==.Contemplate:BAAALAAECgQIBAAAAA==.Cordine:BAAALAADCgYIBgAAAA==.Corpsepoker:BAAALAAECgMIAwAAAA==.Cowabunga:BAAALAADCgcIBwAAAA==.',Cu='Cupow:BAAALAADCgEIAQAAAA==.',Cy='Cybergoth:BAAALAAECgMIAwAAAA==.',Cz='Czin:BAAALAAECgMIAwAAAA==.',Da='Dalealmighty:BAAALAAECgYICAAAAA==.Dalkill:BAAALAAECgcICgAAAA==.Darkdeaths:BAAALAAECgcIEgAAAA==.',De='Deathverses:BAAALAAECgQIBQAAAA==.Demhunts:BAAALAAECggICQAAAA==.Demonditto:BAAALAADCgMIAwABLAAECgYICgACAAAAAA==.Derpydawg:BAAALAADCgUIBQABLAAECggIFQAEAFchAA==.',Di='Diddy:BAAALAADCgYIDQAAAA==.Dikslapp:BAAALAAECgYIDgAAAA==.Disrupt:BAAALAAECgYIDAAAAA==.Ditto:BAAALAAECgYICgAAAA==.',Do='Doesgriddy:BAAALAAECgYICgAAAA==.Donoph:BAAALAAECgYICAAAAA==.Doomar:BAAALAAECgcICQAAAA==.Doomsdazar:BAAALAAECgEIAQAAAA==.Dotudown:BAAALAADCggICAAAAA==.',Dr='Dragindznuts:BAAALAAECgQIBQAAAA==.Dragoisua:BAAALAADCgMIBQAAAA==.Drakedonut:BAAALAAECgYICQAAAA==.Dreadexa:BAAALAADCgMIAwAAAA==.',Du='Dundun:BAAALAAECgEIAQAAAA==.',Dy='Dynabol:BAAALAADCgIIAgAAAA==.',Ee='Eelane:BAAALAAECgYICwAAAA==.',El='Elucidator:BAAALAADCgcIEQAAAA==.Elvania:BAAALAADCgIIAgAAAA==.',En='Entrøpy:BAAALAAECgEIAQAAAA==.',Er='Eredin:BAAALAADCggIDgAAAA==.Erågon:BAAALAAECgEIAQAAAA==.',Et='Eternallife:BAAALAADCgMIAwAAAA==.',Ev='Everfale:BAAALAAECgEIAQAAAA==.',Ey='Eye:BAAALAADCgcIBwAAAA==.',Fa='Fahlafflez:BAAALAAECgcIDwAAAA==.',Fi='Firevvolf:BAAALAADCgcIBwAAAA==.Fishie:BAAALAADCgcIEAAAAA==.Fishinfridge:BAAALAAECgUICgAAAA==.',Fl='Flatlined:BAAALAADCgUIBQAAAA==.Flloyd:BAAALAAECgYIDQAAAA==.Floorpov:BAAALAAECgYICgAAAA==.Flugarbin:BAAALAAECgMIAwAAAA==.',Fo='Folid:BAAALAADCgYIBwAAAA==.',Fr='Frostbeard:BAAALAAECgEIAQAAAA==.Frostbiter:BAAALAADCggIEAABLAAECgcIDwACAAAAAA==.Frostyschmax:BAAALAADCgcIBwAAAA==.',['Fö']='Föxxÿ:BAAALAAECggIEwAAAA==.',Ga='Galadrîel:BAAALAADCgYIBgAAAA==.',Ge='Gelaeda:BAAALAADCgQIBAAAAA==.',Go='Goodestboy:BAAALAADCgYICgAAAA==.',Gr='Grawler:BAAALAADCggIDwAAAA==.Greeny:BAAALAADCgYIAQAAAA==.Grumbly:BAAALAADCggICAAAAA==.Grumpyhunter:BAAALAAECgQIBQAAAA==.Gryphonyx:BAAALAADCgcICgAAAA==.Grónk:BAAALAADCggICgAAAA==.',Gu='Gumgumfury:BAAALAAECgIIAgAAAA==.Gundrix:BAAALAADCgcIBwAAAA==.',Ha='Halia:BAAALAAECgIIAgAAAA==.Harmful:BAAALAAECgQIBAAAAA==.Haylonor:BAAALAADCgcICAAAAA==.',Hi='Hiblast:BAAALAAECgYIDgAAAA==.Hilarie:BAAALAADCgIIAgAAAA==.',Ho='Hoid:BAAALAADCgcIBwAAAA==.Holyknightt:BAAALAAECgYIDgAAAA==.Hosannah:BAAALAAECgMIAwAAAA==.Hotsndots:BAAALAADCgcIBwAAAA==.',Hu='Hunterschmax:BAAALAADCgYIBgAAAA==.Huntguin:BAAALAADCgcIBwAAAA==.Huulu:BAAALAADCgUIBQAAAA==.',Hy='Hycinadra:BAAALAADCgMIAwAAAA==.',Ic='Iciaalta:BAAALAADCggICwAAAA==.',Il='Iloveit:BAAALAAECgEIAgAAAA==.',Im='Imæge:BAAALAAECgcICQAAAA==.',In='Indishaman:BAAALAAECgcIDQAAAA==.',Iz='Izedeth:BAAALAAECgMIAwAAAA==.',Ja='Jabronygos:BAAALAAECgcIDwAAAA==.Jareth:BAAALAAECgEIAQAAAA==.Jaythirian:BAAALAAECgcIDwAAAA==.',Je='Jeatalena:BAAALAAECgEIAQAAAA==.Jehadal:BAAALAADCggIFgAAAA==.Jexar:BAAALAADCgYIBgAAAA==.',Jo='Joffrey:BAAALAAECgQICgAAAA==.Johneggbert:BAABLAAECoEUAAIFAAcItyW9AQD4AgAFAAcItyW9AQD4AgAAAA==.',Ju='Junior:BAAALAADCgUIBgABLAAECgQIBgACAAAAAA==.',['Jö']='Jörõ:BAAALAADCgcIEQAAAA==.',Ka='Kablinkiaa:BAAALAAECgEIAQAAAA==.Kaeydun:BAAALAADCgcIBwAAAA==.Kaizoku:BAAALAADCgMIAwAAAA==.Kaliie:BAAALAADCgQIBAAAAA==.Katastrophic:BAAALAAECgQIBQAAAA==.Katazul:BAAALAAECgEIAQAAAA==.Katiyana:BAAALAAECgEIAQAAAA==.',Ke='Keelanllan:BAAALAAECgEIAQAAAA==.Keilun:BAEALAADCggIEAAAAA==.',Ki='Kildorwyrnn:BAAALAADCgcIBwAAAA==.Kirsche:BAAALAAECgYIBgAAAA==.',Kn='Knightxl:BAAALAAECgMIAwAAAA==.',Ko='Kokuten:BAAALAADCgIIAgABLAAECgEIAgACAAAAAA==.Koral:BAAALAADCgcIBwAAAA==.',Kr='Krascus:BAAALAAECgMIBQABLAAECgUICAACAAAAAA==.',Ky='Kyrian:BAAALAADCgYIBgAAAA==.',La='Laeral:BAAALAAECgYIDgAAAA==.Larrydale:BAAALAADCggIDgAAAA==.',Le='Leondis:BAAALAAECgYICgAAAA==.Lexipriest:BAAALAAECgUICQAAAA==.',Lf='Lfgothgf:BAAALAADCggICAAAAA==.',Li='Lictenstein:BAAALAAECgEIAQAAAA==.Lintoo:BAAALAAECgUICAAAAA==.Lionhart:BAAALAADCggIEQAAAA==.',Ll='Llamamamma:BAAALAADCggICAABLAAECgYIDgACAAAAAA==.',Lo='Loendor:BAAALAADCggIFwAAAA==.Lolck:BAAALAADCgcIBwAAAA==.Lorp:BAAALAAECgMIAwAAAA==.',Lt='Ltfreggin:BAAALAAECgYIDgAAAA==.',Lu='Lumosmaxiima:BAAALAAECgEIAQAAAA==.Lunarette:BAAALAADCgEIAQAAAA==.',Ly='Lyrine:BAAALAAECgUICAAAAA==.',Ma='Madpriest:BAAALAAECgYIBwAAAA==.Mageboytwo:BAAALAADCgcIBwAAAA==.Malarananan:BAAALAADCggIGQAAAA==.Malistavias:BAAALAADCggIDwAAAA==.Malliki:BAAALAAECgYICAAAAA==.Mathan:BAAALAAECgMIBgAAAA==.Maudib:BAAALAAECgYICQAAAA==.Maurizio:BAAALAAECggIAQAAAA==.Mawile:BAAALAAECgMIBAAAAA==.',Me='Melinarra:BAAALAAECgEIAQAAAA==.Messe:BAAALAADCggIDgABLAAECgQIBQACAAAAAA==.',Mi='Milicious:BAAALAADCgYIDAAAAA==.Mistake:BAAALAADCgcIEQAAAA==.',Mo='Montagne:BAAALAADCgUIBQAAAA==.Mooawdeeb:BAAALAADCgcIBwAAAA==.Morghul:BAAALAADCgUIBAAAAA==.Motyka:BAAALAADCggICAAAAA==.Mournblade:BAAALAADCgEIAQAAAA==.',Mu='Mudderman:BAAALAAECgMIAwAAAA==.Munkee:BAAALAADCgYIBgAAAA==.',Na='Nachoma:BAAALAADCgEIAQAAAA==.Narsha:BAAALAAECgEIAQAAAA==.',Ne='Nephelia:BAAALAADCgcIDgAAAA==.',Ni='Nightxl:BAAALAAECgcIDQAAAA==.Nitazat:BAAALAADCgYICAAAAA==.Nivan:BAAALAAECgEIAQAAAA==.Niço:BAAALAAECggICgAAAA==.',No='Noicce:BAAALAAECgcIDwAAAA==.Noiceshm:BAAALAADCgEIAQAAAA==.Norael:BAAALAADCggIEAAAAA==.Notabu:BAAALAAECgcIEAAAAA==.Novaenea:BAAALAADCgEIAgAAAA==.',Nu='Numrea:BAAALAAECgEIAQAAAA==.',Ny='Nyatko:BAAALAADCgYICAAAAA==.Nyxar:BAAALAADCgcIDwAAAA==.',['Nï']='Nï:BAAALAAECgcIDwAAAA==.',Oa='Oakmoss:BAABLAAECoEXAAIBAAgIuh8KCwCzAgABAAgIuh8KCwCzAgAAAA==.',Oc='Octonado:BAAALAADCggIDwAAAA==.',Od='Odwin:BAAALAADCggICAAAAA==.',Ol='Oldemort:BAAALAADCgcIBwAAAA==.',Om='Ombravuota:BAAALAAECgIIBAAAAA==.',Op='Ophelia:BAAALAADCgcIBwAAAA==.',Or='Oralian:BAAALAAECgYIDgAAAA==.',Ou='Outofmana:BAAALAADCgMIAwAAAA==.',Ow='Owlet:BAAALAADCgcIEQABLAADCgcIGAACAAAAAA==.',Oy='Oysterkid:BAAALAADCggIBwAAAA==.',Oz='Ozempic:BAAALAAECgEIAwAAAA==.',Pa='Paladîn:BAAALAAECgcIBwAAAA==.Pancake:BAAALAADCggIEAAAAA==.Papajohn:BAAALAADCgcICAAAAA==.Paragus:BAAALAAECgEIAQAAAA==.Passtheboof:BAAALAAECgIIAgAAAA==.',Pe='Peanutz:BAAALAAECgMIBAAAAA==.Perrymason:BAAALAADCgMIAwAAAA==.',Pi='Pisslowmage:BAAALAAECgQIBAAAAA==.',Qr='Qronos:BAAALAAECgEIAgAAAA==.',Qu='Quorra:BAAALAADCgMIBAAAAA==.',Qw='Qwarrior:BAAALAADCgYICQAAAA==.',Ra='Rabieshots:BAAALAAECgYICAAAAA==.Radnads:BAAALAADCgcIBwAAAA==.Rahzgor:BAAALAAECgMIBQAAAA==.Ramsey:BAAALAAECgcIDwAAAA==.',Re='Rendwolf:BAAALAADCggIEQAAAA==.Restobiscuit:BAAALAAFFAEIAQAAAA==.Reue:BAABLAAECoEWAAIGAAgIKyB+AgDvAgAGAAgIKyB+AgDvAgAAAA==.Reyz:BAAALAAECgUIBQAAAA==.',Rh='Rhaegos:BAAALAADCgEIAQAAAA==.Rhoz:BAAALAADCgcIBwAAAA==.Rhyseris:BAAALAADCggICQAAAA==.Rhythm:BAAALAADCggICAABLAAECgQIBAACAAAAAA==.',Ri='Rickgrimes:BAAALAAECgYICQAAAA==.',Ro='Rolex:BAAALAAECgIIAgAAAA==.',Ru='Runswithu:BAAALAADCgUIBwAAAA==.',Sa='Safi:BAABLAAECoEVAAQHAAgI+SUaAgBPAwAHAAgI9iUaAgBPAwAIAAQIkhuSDgBOAQAJAAMIWSQxKwDPAAAAAA==.Saintloot:BAAALAAECgMIAwAAAA==.Salithil:BAAALAADCgEIAQAAAA==.Salla:BAAALAADCgcIBwAAAA==.Sammich:BAAALAAECgYICAAAAA==.Sanguindeath:BAAALAAECgIIAgAAAA==.Sapphist:BAAALAAECggICwAAAA==.',Sc='Scrapyjack:BAAALAAECgUICAAAAA==.',Se='Senna:BAAALAADCgYIBgAAAA==.Senzu:BAAALAAECgMIAwAAAA==.',Sh='Shadowpimp:BAAALAAECgIIAgAAAA==.Shale:BAAALAAECgYIDQAAAA==.Shammytyme:BAAALAAECgUIBQAAAA==.Shaunt:BAAALAAECgUICQAAAA==.Shearwater:BAAALAAECgEIAQAAAA==.Shootsgoo:BAAALAAECgIIAgAAAA==.',So='Solarise:BAAALAAECgcIDwAAAA==.',St='Stala:BAAALAADCgcIBwAAAA==.Starßurst:BAAALAAECgYIDgAAAA==.Steezey:BAAALAAECgIIAwAAAA==.Stormsoul:BAAALAAECgIIBAABLAAECgEIAQACAAAAAA==.Stunny:BAAALAADCgEIAQAAAA==.',Sv='Svecenica:BAAALAAECgIIAgABLAAECgIIAgACAAAAAA==.Svetha:BAAALAAECgMIBAAAAA==.',Sw='Sweetbunny:BAAALAADCgIIAgAAAA==.',Sy='Sylrian:BAAALAADCgQIBQAAAA==.Sylvaniss:BAAALAAECgYIDgAAAA==.',Ta='Tackshi:BAAALAADCggICAAAAA==.Talonsnwings:BAAALAAFFAIIAgAAAA==.Tankinit:BAAALAAECgIIAgAAAA==.Tasogare:BAAALAAECgYIDgAAAA==.',Te='Tenstusî:BAAALAAECgcIDQAAAA==.Terrylynn:BAAALAADCgcIBwABLAADCgcIGAACAAAAAA==.',Th='Thedrew:BAAALAADCggICAAAAA==.Thirteen:BAAALAADCgcIBwAAAA==.Thrus:BAAALAAECgQIBQAAAA==.Théworld:BAAALAADCgQICQAAAA==.',To='Toes:BAAALAAECgYIDQAAAA==.Towani:BAAALAADCggICwAAAA==.',Tr='Traddles:BAAALAADCggICAAAAA==.Trammatize:BAAALAAECgYIDQAAAA==.Transmogging:BAAALAADCggICAAAAA==.Trevanche:BAAALAADCgYIBgAAAA==.Triptamean:BAAALAADCgYIDQAAAA==.Tristjen:BAAALAAECgIIAwAAAA==.',Tt='Ttvgravewow:BAAALAADCgEIAQAAAA==.',Ud='Udawutabunga:BAAALAAECgYIDQAAAA==.',Un='Undeadmagics:BAAALAADCgcIBwAAAA==.Undeadnite:BAAALAAECgMIBQAAAA==.Unglaus:BAAALAAECggIDAAAAA==.Unglausp:BAAALAAECgEIAQAAAA==.',Va='Valeta:BAAALAADCgYICAAAAA==.Vali:BAAALAAECgIIAgAAAA==.Vaso:BAAALAADCgMIAwAAAA==.',Ve='Velineda:BAAALAADCgQIBAAAAA==.Velinieron:BAAALAAECgcIDwAAAA==.Velinvile:BAAALAADCgEIAQABLAAECgcIDwACAAAAAA==.Vendétta:BAAALAAECgMIAwAAAA==.',Vo='Voidchild:BAAALAADCgcIBwAAAA==.',Vy='Vynlandis:BAAALAAECgQIBQAAAA==.',Wa='Wateringlass:BAAALAADCgYIBgAAAA==.',We='Wellanalin:BAAALAADCgEIAQAAAA==.',Wh='Whaco:BAAALAAECgYIDgAAAA==.Whatisaggro:BAAALAAECgEIAQAAAA==.Whispertree:BAAALAAECgYICwAAAA==.',Wi='Wildblood:BAAALAADCgcIBwAAAA==.Wiseguys:BAABLAAECoEVAAIEAAgIVyFiBwD8AgAEAAgIVyFiBwD8AgAAAA==.Wixjones:BAAALAAECgQIBAAAAA==.',Wo='Wockyslush:BAAALAAECgUICAAAAA==.',Wu='Wuxian:BAAALAAECgEIAgAAAA==.',Wy='Wyyn:BAAALAAECgQICAAAAA==.',Xa='Xanboi:BAAALAAECgYIDgAAAA==.',Xu='Xuen:BAAALAAECgUIBwAAAA==.',Ye='Yerfdogsson:BAAALAAECgMIBAAAAA==.',Ys='Ysar:BAAALAAECgUICAAAAA==.',Za='Zaddymurph:BAAALAAECgYICwAAAA==.Zalidora:BAAALAAECgQIBAAAAA==.',Ze='Zeebu:BAAALAADCggIDwAAAA==.Zenokitsune:BAAALAAECggIBQAAAA==.',Zh='Zhilan:BAAALAAECgMIBAAAAA==.',Zm='Zmajarac:BAAALAAECgIIAgAAAA==.',Zu='Zuc:BAAALAADCggIEwAAAA==.Zuzuk:BAAALAAECgQIBwAAAA==.',['Ðe']='Ðemaea:BAAALAAECgUIBQAAAA==.',['Ði']='Ðittø:BAAALAADCgcIEQABLAAECgYICgACAAAAAA==.',['Ør']='Øreø:BAAALAAECgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end