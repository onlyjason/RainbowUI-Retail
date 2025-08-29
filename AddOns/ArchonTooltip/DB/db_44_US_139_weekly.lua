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
 local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Protection','Hunter-BeastMastery','Warrior-Fury','Warrior-Arms','Rogue-Assassination','Rogue-Subtlety','Mage-Arcane','Mage-Frost',}; local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aemond:BAAALAAECgEIAQAAAA==.Aeoliana:BAAALAAECgYICwAAAA==.',Al='Alakazam:BAAALAAECgMIBAAAAA==.Aleraz:BAAALAAECgYIDgAAAA==.',An='Anbrew:BAAALAAECgMIBQAAAA==.Ancalagonn:BAAALAADCgUIBQAAAA==.Angela:BAAALAAECgYIDwAAAA==.',Ap='Apeople:BAAALAAECgcIEgAAAA==.Apocalýpsè:BAAALAADCgQIBAAAAA==.Applebottum:BAAALAADCgYIBgAAAA==.Appärition:BAAALAAECgQIBQAAAA==.',Ar='Arondael:BAAALAAECgQIBQAAAA==.',Av='Avanti:BAAALAAECgMIBQAAAA==.',Az='Azirgos:BAAALAAECgEIAQAAAA==.Azstayn:BAAALAADCgUIBgAAAA==.',Ba='Backmoist:BAAALAAECgYIBgAAAA==.Baeden:BAAALAAECgIIAgAAAA==.Bagmaster:BAAALAAECgcIEgAAAA==.Balatro:BAAALAADCgQIBAAAAA==.Bandon:BAAALAADCgcIBwAAAA==.Battosai:BAAALAADCgYIBgAAAA==.',Bi='Bigzuki:BAAALAADCggICAAAAA==.Birgite:BAAALAADCgYIBgAAAA==.',Bl='Blackshirt:BAAALAADCgYIBgAAAA==.Blazeknight:BAAALAAECgIIBgAAAA==.Blazemaker:BAAALAADCggIFAAAAA==.Blazemaster:BAAALAADCgcICQAAAA==.Blocktor:BAAALAAECgYICQAAAA==.',Bo='Bodybob:BAAALAAECgYICQAAAA==.Bolgrom:BAAALAAECgMIBgAAAA==.Boydik:BAAALAADCgcIDgAAAA==.',Br='Brewlin:BAAALAADCgMIAwAAAA==.Brewsterdude:BAAALAADCgcIBwAAAA==.Brickdisk:BAAALAAECgQIBwAAAA==.Brickgrimes:BAAALAADCggIDgAAAA==.Brink:BAAALAAECgMIBgAAAA==.Brokil:BAAALAADCgQIBAAAAA==.Bromaster:BAAALAADCgEIAQAAAA==.Bruceless:BAAALAAECgIIAgAAAA==.',Bu='Bubblegal:BAAALAADCgMIAwAAAA==.Burningmagic:BAAALAAECgMIBgAAAA==.Burningtree:BAAALAADCggICAAAAA==.',Ca='Camatats:BAAALAADCgYIBgAAAA==.Camazotz:BAAALAAECgYIDQAAAA==.Canexxc:BAAALAADCggIDwAAAA==.Caplevi:BAAALAAECgMIAwAAAA==.Catechism:BAAALAAECgEIAQAAAA==.',Ce='Cemeo:BAAALAAECgcIEwAAAA==.Cerberusalfa:BAAALAAECgcIEgAAAA==.',Ch='Chaotix:BAAALAAECgMIAwAAAA==.Chiphoof:BAAALAAECgMIAwAAAA==.Chocofox:BAAALAAECgMIBgAAAA==.Chokemagic:BAAALAAECgMIBQAAAA==.',Cl='Clarabuns:BAAALAAECggIBwAAAA==.Clarasbuns:BAAALAADCgYIBgABLAAECggIBwABAAAAAA==.',Co='Colosie:BAAALAAECgQIBwAAAA==.',Cr='Creatlach:BAAALAAECggIEQAAAA==.Crogrim:BAAALAADCgYIBgAAAA==.Crucifilth:BAAALAADCgMIAwAAAA==.',Cu='Curseyou:BAAALAAECgIIAgAAAA==.',Cy='Cyaniidee:BAAALAADCgUIBQAAAA==.Cytherea:BAAALAAECgEIAQAAAA==.',Da='Dadbodz:BAAALAAECgMIAwAAAA==.Dandelo:BAAALAADCgcICAAAAA==.Dans:BAAALAADCgYIBgAAAA==.Darktaynt:BAAALAAECgEIAQAAAA==.',De='Dedranis:BAAALAADCgMIBQAAAA==.Demolish:BAAALAAECgUIBwAAAA==.Demonclem:BAAALAAECgMIAwAAAA==.Demonkoala:BAABLAAECoEWAAQCAAgIChSYBgD7AQACAAgIIBOYBgD7AQADAAYIeA5fKQBrAQAEAAUIjwogEAAxAQAAAA==.Denayethran:BAAALAADCgEIAQAAAA==.Depakote:BAAALAADCgIIAgAAAA==.Deserving:BAAALAAECgcIEgAAAA==.',Di='Dirksbentley:BAAALAADCggIBQABLAAECggIFQAFAJYRAA==.Dirkuatah:BAAALAAECggIBQAAAA==.Diré:BAAALAADCgMIBwAAAA==.Divinebehind:BAAALAAECgcIEAAAAA==.',Do='Doppio:BAAALAADCgEIAQAAAA==.',Dr='Drakin:BAAALAAECgYIDgAAAA==.Drakzos:BAAALAADCgcIBwAAAA==.Dranessa:BAAALAAECgYICQAAAA==.Dre:BAAALAAECgQIBAAAAA==.Dreya:BAAALAAECgYICwAAAA==.',Du='Dutchman:BAABLAAECoEXAAIGAAgIxyVLAQBoAwAGAAgIxyVLAQBoAwAAAA==.',Ei='Eiffel:BAAALAADCggICAAAAA==.Eiriana:BAAALAADCgEIAQAAAA==.',El='Elandria:BAAALAADCgcIDAAAAA==.Eldrene:BAAALAAECgMIBQAAAA==.Elethrigos:BAAALAADCgMIAwAAAA==.Elyaen:BAAALAAECgQICQAAAA==.',Em='Empower:BAAALAAECgYICgAAAA==.',En='Enpower:BAAALAADCgQIBAABLAAECgYIDQABAAAAAA==.',Es='Españamor:BAAALAAECgMIAwAAAA==.Española:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Fa='Falkorne:BAABLAAECoEVAAQFAAgIlhE0FgAwAQAHAAYIBxD1JgB5AQAFAAYIXxA0FgAwAQAIAAIIKxOJDgCZAAAAAA==.Faridehs:BAAALAAECgIIAQAAAA==.Fatalminn:BAAALAAECgcIDwAAAA==.',Fi='Fineok:BAAALAADCggICAAAAA==.',Fl='Fluvoker:BAAALAAECgcIEgAAAA==.',Fo='Fortissáx:BAAALAADCgcIBgAAAA==.',Fr='Frassk:BAAALAAECgMIAwAAAA==.Freehots:BAAALAAECggICwAAAA==.Frostedtips:BAAALAADCgcIBwAAAA==.Frozat:BAAALAADCggICwABLAAECggIEgABAAAAAA==.Frösting:BAAALAAECgUICAAAAA==.',Fu='Fushae:BAAALAAECgUIBwAAAA==.',Ga='Garudo:BAAALAADCgcIBwAAAA==.',Ge='Geminizen:BAAALAAECgYIDQAAAA==.',Gh='Ghandy:BAAALAADCgcIDAABLAAECgQIBAABAAAAAA==.',Gi='Gimis:BAAALAADCgQIBAAAAA==.Giä:BAAALAAECgQIBQAAAA==.',Gl='Glamoroüs:BAAALAADCggICAAAAA==.',Go='Goblindatbut:BAAALAAECgYICQAAAA==.Gobm:BAAALAAFFAEIAQAAAA==.Goldhammer:BAAALAADCgcIBwAAAA==.Golem:BAAALAADCgMIAwAAAA==.Gottamoo:BAAALAAECggIEgAAAA==.',Gr='Grasstickles:BAAALAADCgIIAgAAAA==.Green:BAAALAADCggICAAAAA==.Grâcè:BAAALAAECgMIAwAAAA==.',Gs='Gs:BAAALAADCggICAAAAA==.',Ha='Hacantkillme:BAAALAADCgQIBgAAAA==.Hannrr:BAAALAAECgMIAwAAAA==.Haomi:BAAALAADCgYIBgAAAA==.Harmen:BAAALAADCggIDgABLAAECgQICgABAAAAAA==.Haunt:BAAALAAECgcIEAAAAA==.',He='Helii:BAAALAAECgQIBAAAAA==.Herrow:BAAALAADCgYIBwAAAA==.',Hi='Hiver:BAAALAAECgMIBAAAAA==.',Ho='Holier:BAAALAAECgcIEAAAAA==.Holycows:BAAALAADCgYIBgAAAA==.Holyregrets:BAAALAAECgYIDwAAAA==.Hopperstotem:BAAALAADCgcIDgAAAA==.',Hu='Hukano:BAAALAADCgcIAQAAAA==.Hulo:BAAALAAECgcIDwAAAA==.Hunteress:BAAALAADCgEIAQAAAA==.Hurrdurr:BAAALAAECgMIBQAAAA==.',Hy='Hyb:BAAALAAECgIIAgAAAA==.',Ic='Icebuffalo:BAAALAADCgcIBwAAAA==.',Il='Ilara:BAAALAADCgUIBQAAAA==.Illumi:BAAALAADCgEIAQAAAA==.',Ir='Irked:BAAALAADCgYIBgAAAA==.Irri:BAAALAADCgEIAQAAAA==.',Is='Ishara:BAAALAADCgYIBgAAAA==.',Ja='Jaceswrath:BAAALAAECggIBgAAAA==.',Je='Jeanjean:BAAALAAECgEIAQAAAA==.Jellybea:BAAALAAECgMIAwAAAA==.Jellybru:BAAALAAECgMIAwAAAA==.Jennisen:BAAALAAECgMIAwAAAA==.',Jo='Johnnycakes:BAAALAADCgYIBgAAAA==.',Ju='Jurisdiction:BAAALAAECgMIAwAAAA==.Justbill:BAAALAAECgYICwAAAA==.',Ka='Kadath:BAAALAADCgUIBwAAAA==.Kalru:BAAALAADCgQIBAAAAA==.Kalthesra:BAAALAAECgYIBwAAAA==.Kaneki:BAAALAAECgQIBgAAAA==.Karlan:BAAALAADCgEIAQAAAA==.',Ke='Keahi:BAAALAADCggICwAAAA==.Keihoe:BAAALAAECgMIBgAAAA==.',Ki='Killaban:BAAALAADCggICwAAAA==.Killbydeath:BAAALAADCgUIBwAAAA==.Kimberlyhárt:BAAALAAECgYIBwAAAA==.Kitaya:BAAALAAECgMIAwAAAA==.Kitharae:BAAALAAECgMIBgAAAA==.',Kl='Klarabun:BAAALAADCgIIAgAAAA==.Klot:BAAALAAECgIIAgAAAA==.',Ko='Kolosie:BAAALAAECgIIAgABLAAECgQIBwABAAAAAA==.',Kr='Kraiger:BAAALAADCgQIBgAAAA==.Krftpnk:BAAALAAECgYICQAAAA==.Kronotek:BAAALAAECgMIAwAAAA==.Krystlin:BAAALAADCgEIAQAAAA==.',Ku='Kurze:BAAALAAECgYIBwAAAA==.',La='Laimaster:BAAALAADCgYICQAAAA==.Lakeri:BAAALAAECgEIAQAAAA==.Larebarely:BAAALAADCgcIDgAAAA==.Lascivia:BAAALAAECgMIAwAAAA==.Layila:BAAALAAECgIIAgAAAA==.Lazerqt:BAAALAAECgMIAwAAAA==.',Le='Leadmln:BAAALAAECgQIBQAAAA==.Lekeri:BAAALAADCgMIAwAAAA==.Lep:BAAALAAECggIEgAAAA==.Lethalkrit:BAAALAAECggICAAAAA==.',Li='Liberté:BAAALAADCgcICwAAAA==.Licciano:BAAALAAECgQIBAAAAA==.Lilzuki:BAAALAAECgMIAwAAAA==.Lilïth:BAAALAADCggICAABLAAECggICwABAAAAAA==.Limas:BAAALAADCgYIBgAAAA==.Lisalisa:BAAALAAECgMIBwAAAA==.Littlebuss:BAAALAADCgcIDAAAAA==.Littlejohn:BAAALAADCgIIAgAAAA==.',Lo='Loknasta:BAAALAADCgUIBQAAAA==.Lorenth:BAAALAADCgcIBwAAAA==.Loss:BAAALAADCgEIAQAAAA==.Lotara:BAAALAAECgYIDQAAAA==.',Lu='Lucksfate:BAAALAAECggIAwAAAA==.Lucky:BAAALAAECgYIBwAAAA==.Ludology:BAAALAADCgEIAQAAAA==.Lumis:BAAALAADCggICAAAAA==.Lumity:BAAALAADCgYIBgAAAA==.',Ly='Lyyindria:BAAALAADCggICAAAAA==.',['Lï']='Lïlith:BAAALAAECggIBAAAAA==.',Ma='Madorn:BAAALAADCgUIBgAAAA==.Magicmoo:BAAALAAECgIIAgABLAAECgYIBwABAAAAAA==.',Me='Meatballs:BAAALAAECgQIBwAAAA==.Medìcus:BAAALAAECgYICQAAAA==.Megajoo:BAAALAAECgYIDAAAAA==.',Mi='Missluana:BAAALAADCgYICAAAAA==.',Mo='Moarf:BAAALAADCggIDgAAAA==.Moistdozie:BAAALAAECgMIAwAAAA==.Moofatsa:BAAALAADCgcIDgAAAA==.Moomookachu:BAAALAADCggIDgABLAAECgIIAgABAAAAAA==.Moonythecow:BAAALAAECgMIBgAAAA==.Morechie:BAAALAAECgYIBgAAAA==.Morecowbell:BAAALAAECgQIBAAAAA==.',My='Myth:BAAALAADCgcIBwAAAA==.',Na='Nachoheals:BAAALAAECgcIEAAAAA==.Naissa:BAAALAADCgcIAgAAAA==.Nakoví:BAAALAADCggICAAAAA==.Naughtyelf:BAAALAADCgYIBgAAAA==.',Ne='Necrotion:BAAALAADCgUIBQAAAA==.Nekros:BAAALAADCgcICgAAAA==.Nerrisa:BAAALAAECgYICQAAAA==.Nertmage:BAAALAAECgcIDQAAAA==.',Ni='Nicodemus:BAAALAAECgEIAQAAAA==.Ninjatstone:BAAALAADCgcIBwAAAA==.',No='Noblewarrior:BAAALAAECgUIBwAAAA==.Noctilus:BAAALAADCgcIBwAAAA==.Nooj:BAACLAAFFIEHAAMJAAQIJRlfAQArAQAJAAMIFx5fAQArAQAKAAEIUAq9AwBWAAAsAAQKgRgAAwkACAhUJlsJAJICAAkACAhUJlsJAJICAAoAAwglFwAAAAAAAAAA.Notakoala:BAAALAADCgIIAQABLAAECggIFgACAAoUAA==.Notmoose:BAAALAAECggIEwAAAA==.',Ob='Obern:BAAALAAECgYIDQAAAA==.',Od='Odiumaeterna:BAAALAADCgcIBwAAAA==.',Of='Offensivé:BAAALAAECgMIAwAAAA==.',Ol='Oldmanbliz:BAAALAAECgIIAgAAAA==.',On='Onebuttondps:BAAALAADCgIIAgAAAA==.',Os='Osoja:BAAALAAECgIIAgAAAA==.Osteer:BAAALAADCgMIAgAAAA==.',Ot='Otpshaman:BAAALAADCgQIBAAAAA==.',Pa='Palnix:BAAALAADCgIIAgAAAA==.Palpatinee:BAAALAAECgMIBAAAAA==.Papazilla:BAAALAAECgYIBwAAAA==.Parakka:BAAALAAECgQICAAAAA==.Pawp:BAAALAAECgIIAgAAAA==.',Pe='Pepps:BAAALAADCgUICAAAAA==.Pepsisprite:BAAALAAECgMIBgAAAA==.',Ph='Phoivos:BAAALAAECgcIDwAAAA==.Phoosh:BAAALAADCggIDgAAAA==.Phovoker:BAAALAADCgYIBgAAAA==.',Pi='Picklez:BAAALAAECgIIAwAAAA==.',Po='Poison:BAAALAADCgYIDQAAAA==.Poplock:BAAALAADCgUIBQAAAA==.Portwings:BAAALAADCgcICAAAAA==.',Pr='Primalhybrid:BAAALAADCggICAAAAA==.Professahoak:BAAALAAECgcIDQAAAA==.',Pu='Puggy:BAAALAAECgMIBAAAAA==.',Ra='Rakuurah:BAAALAADCgcIEAAAAA==.Ravioli:BAAALAADCgcIDQAAAA==.Ray:BAAALAADCggICAAAAA==.',Re='Reegrets:BAAALAADCgYIBgABLAAECgYIDwABAAAAAA==.Relynna:BAAALAADCgcICAAAAA==.Resyek:BAAALAAECgcIEAAAAA==.',Ro='Roder:BAAALAADCgMIAwAAAA==.Rollinburn:BAAALAADCgcIBwAAAA==.Romanoff:BAAALAAECgYICQAAAA==.Rowdey:BAAALAAECgcIDQAAAA==.',Ry='Ryllandaras:BAAALAAECgMIBQABLAAECgcIDQABAAAAAA==.',Sa='Saffronspark:BAAALAAECgYICgAAAA==.Samadeath:BAAALAAECgUICQAAAA==.Sapsu:BAAALAAECgEIAQAAAA==.Sargatana:BAEALAAECgYIDAAAAA==.Sars:BAAALAAECgEIAQAAAA==.',Sc='Schaglader:BAAALAADCgMIAwAAAA==.',Se='Selicia:BAAALAADCgcICwAAAA==.Severum:BAAALAAECgMIBgAAAA==.',Sh='Shadrad:BAAALAAECgMIAwAAAA==.Shamaltoe:BAAALAADCgYIBgAAAA==.Shantz:BAAALAAECgQIBQAAAA==.Shortbuss:BAAALAADCgYIBwAAAA==.Shullkk:BAAALAADCggICAAAAA==.Shäde:BAAALAAECgEIAQAAAA==.',Si='Sinfullygood:BAAALAADCgEIAQAAAA==.',Sk='Skatervan:BAAALAADCggICwAAAA==.',Sl='Slasure:BAAALAAECgcIEgAAAA==.',So='Sooners:BAAALAAECgIIAgAAAA==.Soryan:BAAALAAECgMIAwAAAA==.',Sp='Sparry:BAAALAADCggICAAAAA==.Sprtstr:BAAALAAECgYICQAAAA==.',Sq='Squishÿ:BAAALAAECgYICwAAAA==.',St='Starbies:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Staychiill:BAAALAAECgYIEAAAAA==.Stormknight:BAAALAAECgIIAgAAAA==.',Su='Suja:BAAALAAECgEIAgAAAA==.Sumisa:BAAALAAECgEIAQAAAA==.Supermages:BAAALAAECgUICAABLAAFFAEIAgABAAAAAA==.Supermonks:BAAALAAECgYIBgABLAAFFAEIAgABAAAAAA==.Superret:BAAALAAFFAEIAgAAAA==.',Sw='Sweetwood:BAAALAADCgcIBwAAAA==.Swiftay:BAAALAADCgUICAABLAADCgcIEQABAAAAAA==.Swiftia:BAAALAADCgcIEQAAAA==.Swiftybutt:BAAALAAECgMIBAAAAA==.',Sy='Sydrak:BAAALAADCggICAAAAA==.',Ta='Talixis:BAAALAAECgMIBQAAAA==.Tandarì:BAAALAAECgMIBQAAAA==.Tankenstine:BAAALAADCgIIAgABLAAECgEIAgABAAAAAA==.',Te='Teilin:BAAALAAFFAIIAgAAAA==.Teylarose:BAAALAAECgIIAgAAAA==.',Th='Theßigshot:BAAALAAECgQICgAAAA==.Thundurus:BAAALAAECgUICQAAAA==.',Ti='Tie:BAAALAAECgcIDwAAAA==.Tindrill:BAAALAAECgQICgAAAA==.Tiredactyl:BAAALAAECgcIEQAAAA==.Tireiron:BAAALAADCgcIDgABLAAECgcIEQABAAAAAA==.',To='Tomraedisk:BAAALAAECgMIBQAAAA==.Tonlee:BAAALAAECgQIBQAAAA==.Totemlyfine:BAAALAAECgMIAwAAAA==.Towerz:BAAALAADCgYIBgAAAA==.',Tr='Trajann:BAABLAAECoEXAAMDAAgINh2WCwCSAgADAAgINh2WCwCSAgACAAMI6hP7QABgAAAAAA==.Treeguy:BAAALAADCgcIBwAAAA==.Treehugger:BAAALAADCgYIBgAAAA==.Treeshield:BAAALAAECgQIBQAAAA==.',Tu='Turbobunz:BAAALAAECgIIAwAAAA==.Turbocheeks:BAABLAAECoEWAAMLAAgIwyBmDADKAgALAAgIWh5mDADKAgAMAAIIcxe9NQBzAAAAAA==.',Tw='Twentyfour:BAAALAAECgYICQAAAA==.',Un='Undeadmonks:BAAALAAECgEIAQAAAA==.',Ur='Uruloki:BAAALAAECgcIEAAAAA==.',Va='Valedrach:BAAALAADCggIDwAAAA==.Valkillrie:BAAALAADCgcICAAAAA==.Vashi:BAAALAAECgMIAwAAAA==.',Ve='Vedbow:BAAALAAECgQIBAAAAA==.Vedronas:BAAALAAECgcIEgAAAA==.Verman:BAAALAADCgYIBgAAAA==.Vernah:BAAALAADCggICAAAAA==.Vernak:BAAALAADCggICAABLAADCggICAABAAAAAA==.Vespenegas:BAAALAADCggICQAAAA==.',Vi='Vixenpunch:BAAALAADCgYICgAAAA==.',Vo='Vomitself:BAAALAADCgYIBgAAAA==.Vonaria:BAAALAAECgMIAwAAAA==.Vornwin:BAAALAAECgcIEAAAAA==.',Wa='Waamchifu:BAAALAAECgMIBgAAAA==.Wapiti:BAAALAAECgEIAQAAAA==.Warwuff:BAAALAADCggICwAAAA==.',Wi='Winzig:BAAALAAECgUIBgAAAA==.Witherman:BAAALAADCgcIBwAAAA==.',Wo='Worgana:BAAALAAECgMIAwAAAA==.',Xp='Xplosiv:BAAALAAECgIIAgABLAAECggIEQABAAAAAA==.',Ye='Yeddy:BAAALAADCggIFgAAAA==.Yel:BAAALAAECgMIBQAAAA==.',Za='Zanghonghua:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.',Ze='Zeezzus:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.',Zo='Zodshot:BAAALAADCgYIBgAAAA==.Zodstrike:BAAALAAECgIIBAAAAA==.',['ßl']='ßlisster:BAAALAADCgcIFAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end