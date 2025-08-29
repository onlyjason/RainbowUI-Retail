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
 local lookup = {'Druid-Restoration','Unknown-Unknown','Hunter-BeastMastery','Warrior-Fury','Shaman-Enhancement',}; local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aedas:BAAALAAECgYIBwAAAA==.Aeleya:BAAALAAECgUICQAAAA==.Aerouant:BAAALAAECgYICgAAAA==.Aetherion:BAAALAADCggICgABLAAECggIFQABAP0SAA==.',Ah='Ahnkhan:BAAALAAECgQIBQABLAAECgYICQACAAAAAA==.',Ai='Aidix:BAAALAADCgcIDgAAAA==.Aierox:BAAALAADCgYIDAAAAA==.Airieani:BAAALAADCgcIBwAAAA==.',Al='Alcyone:BAAALAAECgYIDQAAAA==.Alextrebek:BAABLAAECoEXAAIDAAgIryD2BgDyAgADAAgIryD2BgDyAgAAAA==.Alleksev:BAAALAAECgYIDAAAAA==.Allophone:BAAALAADCggIFgAAAA==.Allpurp:BAAALAAECgYICAAAAA==.Alorades:BAAALAADCgcICgABLAAECgYIDgACAAAAAA==.Alphawarlock:BAAALAADCgIIAgAAAA==.',Am='Amirstrianah:BAAALAADCgQIBAAAAA==.',An='Andrena:BAAALAADCgcIBwAAAA==.Andrius:BAAALAADCgcIBwAAAA==.',Ar='Arcanenug:BAAALAADCgcIBwAAAA==.Armiggy:BAAALAAECgYICQAAAA==.',As='Astrâeâ:BAAALAAECgcIDwAAAA==.',At='Attilla:BAAALAAECgcICAAAAA==.',Av='Avarockstar:BAAALAADCgcIBwABLAAECgYIDgACAAAAAA==.Avraellia:BAAALAAECgYIDQAAAA==.',Ba='Bairdy:BAAALAAECgMIAwAAAA==.Barbåtos:BAAALAAECgEIAQAAAA==.',Bf='Bfalocklul:BAAALAAECgMIAwAAAA==.',Bi='Biblehumping:BAAALAAECgYICgAAAA==.Bicboi:BAAALAADCgYIBgAAAA==.Bidness:BAAALAAECgMIBAAAAA==.Bietk:BAAALAADCgUIBQAAAA==.Bigrichard:BAAALAAECgQIBQAAAA==.',Bl='Blackjedi:BAAALAADCgYIBgAAAA==.Bladë:BAAALAAECgYICQAAAA==.Blasphemous:BAAALAADCgMIAwAAAA==.Bloodelfmage:BAAALAADCggICQAAAA==.Bloodhunterx:BAAALAADCgUIBgAAAA==.Bloodwolff:BAAALAADCgYIBgAAAA==.Bluntlord:BAAALAADCgcIBwAAAA==.',Bo='Bobolo:BAAALAADCggICAABLAAECgYIBwACAAAAAA==.Boflexxin:BAAALAADCgMIAwAAAA==.Boomshroom:BAAALAAECgYIBwAAAA==.Boxorocks:BAAALAADCgIIAwAAAA==.Bozberaz:BAAALAAECgUIBgAAAA==.',Br='Bradtism:BAAALAADCgcICAAAAA==.Brawlwurst:BAAALAADCggIDgAAAA==.Brickdiskie:BAAALAADCggIDgAAAA==.',Bu='Bullszi:BAAALAADCgUIBQAAAA==.Bungus:BAAALAADCgcIFgAAAA==.Bunniemonk:BAAALAADCgYIBgAAAA==.Burgerz:BAAALAADCggIDgAAAA==.Butpistol:BAAALAADCgMIAgAAAA==.',['Bò']='Bòwjob:BAAALAADCggIFwAAAA==.',Ca='Cassïe:BAAALAAECgYICAAAAA==.',Ce='Celement:BAAALAADCggIDAAAAA==.Celestraza:BAAALAADCggIEAAAAA==.Celirra:BAAALAAECgYIDgAAAA==.Ceriann:BAAALAADCgMIAwAAAA==.',Ch='Chadthetank:BAAALAADCggIGgAAAA==.Chaosa:BAAALAADCggIDwAAAA==.Cheekybaby:BAAALAAECgMIBQAAAA==.Chels:BAAALAADCgUIBQAAAA==.Chikinga:BAAALAAECgMIBAAAAA==.Chupapii:BAAALAAECgIIBAAAAA==.Chëfc:BAAALAAECgIIAgAAAA==.',Ci='Ciglock:BAAALAADCgcIBwAAAA==.Cigrune:BAAALAADCgUIBQAAAA==.Cinnascatter:BAAALAADCgUIBgAAAA==.Cinx:BAAALAADCgcIBwAAAA==.',Cl='Clapton:BAAALAADCgQIBAAAAA==.Clasmor:BAAALAADCgEIAQAAAA==.Cleversoul:BAAALAADCgMIAwAAAA==.Clyyve:BAAALAAECgMIAwABLAAECgYIDQACAAAAAA==.',Co='Compensation:BAAALAADCgYIBgAAAA==.Compressed:BAAALAADCggICgAAAA==.Contrivex:BAAALAAECgMIAwAAAA==.Cooploopa:BAAALAADCgMIAwAAAA==.Coopvoker:BAAALAADCgcICQAAAA==.',Cr='Crispytender:BAAALAADCgUIBQAAAA==.',Cu='Cune:BAAALAADCgYIBgAAAA==.Curzondax:BAAALAAECgYICQAAAA==.',Cy='Cyphinx:BAAALAAECgEIAQAAAA==.',['Cä']='Cät:BAAALAAECgcICwAAAA==.',Da='Daevis:BAAALAADCgcIBwAAAA==.Daewar:BAAALAAECgcIDgAAAA==.Daizr:BAAALAAECggIAwAAAA==.Dallarshtone:BAAALAAECgMIAwAAAA==.Dalìnar:BAAALAAECgMIBAAAAA==.Damadafacker:BAAALAAECgYIDQAAAA==.Darklia:BAAALAAECgIIBAAAAA==.Darksidedes:BAAALAADCggIFAABLAAECgYIDgACAAAAAA==.Darkzen:BAAALAADCgYIBgAAAA==.Darkøs:BAAALAAECgIIAgAAAA==.Daïn:BAAALAAECgQIBAAAAA==.',Db='Dbenuts:BAAALAAECgYIDAAAAA==.',De='Deadestmoon:BAAALAADCgcIBwAAAA==.Deadfire:BAAALAADCgUIBAAAAA==.Deathbunnies:BAAALAADCggICAAAAA==.Deathshotz:BAAALAAECgYIDQAAAA==.Deathvoid:BAAALAADCgcICQAAAA==.Decu:BAAALAADCgcIBwAAAA==.Demonarian:BAAALAADCgYIBgAAAA==.Desporator:BAAALAAECgYIDgAAAA==.Deswillhuntu:BAAALAADCggIFAABLAAECgYIDgACAAAAAA==.Dewkookem:BAAALAAECgIIAgAAAA==.Deäthtouch:BAAALAADCgcIDQAAAA==.',Dh='Dhzilla:BAAALAADCgcICgAAAA==.',Di='Dirtyczech:BAAALAADCgUIBQAAAA==.Disterb:BAAALAADCggICAAAAA==.',Dj='Djoroz:BAAALAAECgMIAwAAAA==.',Dk='Dkmata:BAAALAADCggICAAAAA==.',Do='Dotulism:BAAALAADCggICAAAAA==.',Dr='Dragontails:BAAALAADCgEIAQAAAA==.Drakismon:BAAALAAECgYICAABLAAECgYICQACAAAAAA==.Drakujin:BAAALAADCgMIAgAAAA==.Drizzell:BAAALAAECgIIAgAAAA==.Drpayne:BAAALAADCgEIAQAAAA==.Drtryhardd:BAAALAAECgEIAgAAAA==.Druidicdrug:BAAALAAECgMIAwAAAA==.',Du='Durz:BAAALAADCgcIBwAAAA==.',['Dï']='Dïngus:BAAALAADCgYIBgAAAA==.',Ed='Edaladalrian:BAAALAAECgIIAwAAAA==.',Ef='Efickaçi:BAAALAAECgcIDAAAAA==.',El='Elgrangordo:BAAALAAECgEIAgAAAA==.Elleya:BAAALAADCgYIBgAAAA==.Elontronic:BAAALAADCgcICgAAAA==.',En='Enhydra:BAAALAADCggIDQAAAA==.',Er='Ericolson:BAAALAADCggIDwAAAA==.Erinor:BAAALAAECgEIAQAAAA==.',Ev='Evocakes:BAAALAADCggICAABLAAECggIFQABAP0SAA==.Evé:BAAALAADCgEIAQABLAAECgYIBwACAAAAAA==.',Ey='Eye:BAAALAADCggICAABLAAECgcIDAAEABgWAA==.Eyllis:BAAALAAECgYICwAAAA==.',Fa='Fandangö:BAAALAAECgEIAQAAAA==.',Fe='Feared:BAAALAADCgUIBQAAAA==.Fearthelight:BAAALAAECgIIAgAAAA==.Felstruggle:BAAALAADCgcIBwAAAA==.',Fi='Firenerve:BAAALAADCggICwAAAA==.',Fl='Fl:BAAALAAECgEIAQAAAA==.Fletcchh:BAAALAADCgMIAwAAAA==.Fletchh:BAAALAADCgYIBgAAAA==.Flourie:BAAALAAECgYIDQAAAA==.Flyhawk:BAAALAADCgYIEAAAAA==.',Fo='Fongku:BAAALAADCggICAAAAA==.',Fr='Frodoos:BAAALAAECgYIBwAAAA==.Frostbane:BAAALAADCgQIBAAAAA==.Frostbang:BAAALAADCggIAQAAAA==.Fryingpan:BAAALAAECggIBQAAAA==.',Fu='Funlao:BAAALAADCgcIBwAAAA==.Fupette:BAAALAADCggICAAAAA==.Fuzzosaurus:BAAALAAECgIIAgAAAA==.',Ga='Galadri:BAAALAAECgcIEwAAAA==.Galairan:BAAALAAECgIIAwAAAA==.Gandogarr:BAAALAADCggICAAAAA==.Gaze:BAAALAADCgIIAgAAAA==.',Ge='Geartryx:BAAALAAECgQIBgAAAA==.Georgedroid:BAAALAADCgcIBwAAAA==.Gett:BAAALAADCgEIAQAAAA==.',Gi='Gigabust:BAAALAAECgEIAQAAAA==.Gizztard:BAAALAAECgYICwAAAA==.',Gl='Glaistig:BAAALAADCgIIAgAAAA==.Globerin:BAAALAADCgQIBAAAAA==.Globius:BAAALAAECgYIDQAAAA==.Gloriouscole:BAAALAAECgEIAQAAAA==.',Go='Gothicboi:BAAALAAECgcICAAAAA==.',Gr='Gratyr:BAAALAAECgUIBwAAAA==.Greatcredit:BAAALAADCgcICgAAAA==.Grimby:BAAALAAECggIDQAAAA==.Grumby:BAAALAAECgIIAgAAAA==.',Gu='Gubgubs:BAAALAAECgMIAgAAAA==.Guldean:BAAALAAECgYIDAAAAA==.Gutragus:BAAALAAECgIIAgAAAA==.',Ha='Hairyweaver:BAAALAADCgcIDAAAAA==.Hakubar:BAAALAADCgcICQAAAA==.Harridotter:BAAALAADCggIFQAAAA==.Hatebrêêd:BAAALAAECgcIBwAAAA==.',He='Healsornahh:BAAALAADCgIIAgAAAA==.Healylady:BAAALAADCggIDwAAAA==.Hel:BAAALAADCgYICQAAAA==.Helganord:BAAALAAECgYICQAAAA==.Hellinferno:BAAALAADCggICAAAAA==.Hellsyng:BAAALAAECgYIDgAAAA==.Hercueles:BAAALAAECgEIAQABLAAECgMIAwACAAAAAA==.Hexkick:BAAALAADCggIDAAAAA==.Hexngone:BAAALAAECgQIBgAAAA==.',Hi='Hissatsuu:BAAALAADCggIEQAAAA==.',Ho='Holywarrior:BAAALAADCggIEQAAAA==.Holyzaimon:BAAALAADCgYIBgAAAA==.',Hu='Huhdean:BAAALAADCggICgAAAA==.Hungfu:BAAALAAECgYICgAAAA==.Hunterryan:BAAALAAECggIAQAAAA==.Huntinstuff:BAAALAADCgcIBwAAAA==.Huntnwabits:BAAALAAECgEIAQAAAA==.',Il='Illengeance:BAAALAAECgEIAQAAAA==.Ilynx:BAAALAADCgYICwAAAA==.',In='Indicaplague:BAAALAADCgYIBgAAAA==.Indor:BAAALAADCgMIAwAAAA==.',Iw='Iwillcrushyo:BAAALAAECgYIBgAAAA==.Iwupata:BAAALAADCgEIAQAAAA==.',Iy='Iynx:BAAALAADCggIDwAAAA==.',Ja='Jadasdemon:BAAALAADCgcIBwAAAA==.Jafarr:BAAALAAECgIIAgAAAA==.Jake:BAAALAADCgQIBAAAAA==.Jaon:BAAALAAECgUIBgAAAA==.Jaximoos:BAAALAADCgYIBgAAAA==.Jazira:BAAALAAECgMIAwAAAA==.',Jc='Jccymonk:BAAALAADCgcIBwAAAA==.',Je='Jermus:BAAALAADCggIDgAAAA==.',Jh='Jhacobo:BAAALAAECgYIBwAAAA==.',Jo='Jokerjenkins:BAAALAAECgMIAwAAAA==.',Jr='Jragon:BAAALAAECgIIAgAAAA==.',Ju='Juiceloc:BAAALAADCgcIBwAAAA==.Juraik:BAAALAAECgEIAQAAAA==.',['Já']='Jáinà:BAAALAAECgYIDQAAAA==.',['Jú']='Júnjúnwälä:BAAALAAECgYICAAAAA==.',Ka='Kallzone:BAAALAADCgcICwAAAA==.Kannokan:BAAALAAECgYICQAAAA==.Kareena:BAAALAADCgQIBAAAAA==.Karolg:BAAALAADCgIIAgAAAA==.Kaysera:BAAALAADCggICQAAAA==.',Ke='Keempus:BAAALAADCgYIBgAAAA==.Kenrock:BAAALAAECgEIAQAAAA==.',Ki='Kimohsahbee:BAAALAADCgIIAQAAAA==.Kirimi:BAAALAAECgMIBQAAAA==.',Kr='Krisjun:BAAALAADCgYIBwAAAA==.',La='Laenda:BAAALAADCgQIBQAAAA==.Laojin:BAAALAADCgUIBQAAAA==.Lathorius:BAAALAAECgEIAQAAAA==.',Le='Leopards:BAAALAADCggICgAAAA==.Lexist:BAAALAAECgEIAQAAAA==.',Li='Lickma:BAAALAAECgYIBgAAAA==.Lifeblood:BAAALAAECgMIBQABLAAECgYIBwACAAAAAA==.Lilina:BAAALAAECgIIAgAAAA==.',Lo='Locktighter:BAAALAADCgQIBAAAAA==.Loneorc:BAAALAAECgIIAgAAAA==.Lostmydps:BAAALAADCgQIBAABLAAECgYIDgACAAAAAA==.Lothandra:BAAALAAECgMIBgAAAA==.',Lu='Lulafairy:BAAALAADCggIDgAAAA==.Lunatick:BAAALAAECggIDAAAAA==.Lunawa:BAAALAAECgYICwAAAA==.Lup:BAAALAADCgQIBAAAAA==.',['Lì']='Lìghtwìng:BAAALAADCgMIAwAAAA==.',['Lí']='Líï:BAAALAAECgMIAwAAAA==.',Ma='Maahn:BAAALAADCgUIBgAAAA==.Magdagni:BAAALAAECgcICgAAAA==.Maprotec:BAAALAAECgEIAQAAAA==.Marlonwayans:BAAALAAECgYIDQAAAA==.Maroonfive:BAAALAADCgMIAwAAAA==.Marximilian:BAAALAAECgMICAAAAA==.Maryola:BAAALAAECgYIBgAAAA==.Masondragon:BAAALAADCggICAAAAA==.',Me='Medlock:BAAALAADCggICwAAAA==.Meeds:BAAALAADCgIIAgAAAA==.Meewcow:BAAALAADCgQIBAAAAA==.Meiuyesungmi:BAAALAAECgMIBAAAAA==.Melad:BAAALAADCggICQAAAA==.Meow:BAAALAAECgYICQAAAA==.Meowmander:BAAALAAECgQICAAAAA==.Merkén:BAAALAAECgYICAAAAA==.Messatsu:BAAALAADCgYIBgAAAA==.Metajuicer:BAAALAAECgcIDQAAAA==.Mezzoo:BAABLAAECoEVAAIBAAgI/RJ2EwDfAQABAAgI/RJ2EwDfAQAAAA==.',Mi='Miaomiaoyo:BAAALAAECgUICAAAAA==.Midget:BAAALAAECgMIAwAAAA==.Mikeyfuntime:BAAALAAECgEIAQAAAA==.Millic:BAAALAAECgMIBwAAAA==.Millish:BAAALAADCgUIBQAAAA==.Minax:BAAALAAECgYICQAAAA==.Mindari:BAAALAAECgYICQAAAA==.Mirthen:BAAALAAECgMIAwAAAA==.Mistle:BAAALAADCggICQAAAA==.',Mo='Moiduh:BAAALAAECgIIAgAAAA==.Monsterbig:BAAALAAECgUIBQAAAA==.Moralanna:BAAALAADCgcICQAAAA==.Mozus:BAAALAAECgYIDQAAAA==.',Mt='Mtxboy:BAAALAADCgcIBwABLAAECggIHAAFADAhAA==.',Mu='Muckstab:BAAALAAECggIEwAAAA==.Murkyspoons:BAAALAAECgMIBQAAAA==.',My='Myniel:BAAALAADCgcIDAAAAA==.Myrú:BAAALAAECgcIDAAAAA==.Mytholdor:BAAALAADCgcIBwAAAA==.',['Mé']='Mélkôr:BAAALAAECgQIBgAAAA==.',Na='Narayeda:BAAALAAECgEIAQAAAA==.Nargnarg:BAAALAAECgEIAQAAAA==.',Ne='Necromommy:BAAALAADCgQIBAAAAA==.Neoswrath:BAEALAADCgYIBgAAAA==.Nerftraps:BAAALAAECggICAAAAA==.',Ni='Nicobelina:BAAALAADCggICwAAAA==.Nigini:BAAALAADCgIIAgAAAA==.Nikos:BAAALAADCgYICwAAAA==.Nimou:BAAALAAECggIEAAAAA==.',No='Nocturnâ:BAAALAADCgcIDAAAAA==.Notåredneck:BAAALAAECgIIAgAAAA==.',Nu='Nuvi:BAAALAADCggIFAAAAA==.Nuvostaph:BAAALAAECgYICgAAAA==.',Ny='Nyxthera:BAAALAADCgYIBgAAAA==.',['Nì']='Nìghtmared:BAAALAADCgcIBwAAAA==.',Oa='Oakshror:BAAALAAECgMIAwAAAA==.',Oc='Ochylah:BAAALAADCgcIBwAAAA==.',Od='Odecias:BAAALAADCgcIBwAAAA==.',Of='Oftheshadows:BAAALAADCgIIAgAAAA==.',Oi='Oirazana:BAAALAADCgMIAwAAAA==.',Ol='Ollomer:BAAALAAECgYIBgABLAAECgcIEwACAAAAAA==.',On='Onlyflan:BAAALAAECgYICQAAAA==.',Op='Optanious:BAAALAADCgYIBgAAAA==.',Or='Orionember:BAAALAADCggIDgABLAADCggIEQACAAAAAA==.Oros:BAAALAAECgIIAQAAAA==.',Os='Oshellith:BAAALAADCggIGgAAAA==.',Pa='Pandapumper:BAAALAAECgEIAgAAAA==.',Pe='Perønistard:BAAALAADCggICQAAAA==.',Ph='Phalance:BAAALAADCgQIBAAAAA==.Phtevany:BAAALAADCgYIBgAAAA==.',Pi='Pif:BAAALAADCgYIBgAAAA==.',Po='Pokayou:BAAALAAECgYIDAAAAA==.Popedragon:BAAALAAECgMIAwAAAA==.Porkys:BAAALAADCgcIBwAAAA==.Poôch:BAAALAAECgYICgAAAA==.',Pr='Prometheüs:BAAALAADCgUIBQAAAA==.Pryome:BAAALAADCgcIBwABLAAECgYICQACAAAAAA==.',Pu='Punkz:BAAALAADCgMIAwABLAAECgcIEwACAAAAAA==.',Ra='Ragnorock:BAAALAADCggICAAAAA==.Rahja:BAAALAAECgMIBgAAAA==.Raiynn:BAAALAADCggIDgAAAA==.',Re='Reborn:BAAALAADCgYIBgAAAA==.Redneckrick:BAAALAADCggIDwAAAA==.Redpizza:BAAALAADCgcICgAAAA==.Reebs:BAAALAAECgUIBQAAAA==.Remodel:BAAALAAECgMIBAAAAA==.Renownboken:BAAALAAECgQIBAAAAA==.Requese:BAAALAADCggIEAAAAA==.Restöfarian:BAAALAAECgQIBAABLAAECggIFQABAP0SAA==.',Rr='Rraarrk:BAAALAADCgMIAwAAAA==.',Ru='Ruggzzi:BAAALAAECgUICAAAAA==.',Sa='Saberyn:BAAALAAECgMIBgAAAA==.Sacredly:BAAALAAECgYIBgAAAA==.Samavanas:BAAALAADCgcIBwAAAA==.Sarathel:BAAALAAECgMIAwAAAA==.Sassyruby:BAAALAADCggIDgAAAA==.',Sc='Schaughn:BAAALAAFFAEIAQAAAA==.Schvitz:BAAALAAECgEIAQAAAA==.Scottyk:BAAALAADCgcIDAABLAAECggIFQAFAEMfAA==.',Se='Seberology:BAAALAAECgMIAwAAAA==.Seral:BAAALAAECgYICwAAAA==.',Sh='Shadne:BAAALAADCggIEQAAAA==.Shagojyo:BAAALAADCggICAAAAA==.Shamagooly:BAAALAAECgEIAQAAAA==.Shamownage:BAAALAAECgYICQAAAA==.Shockilla:BAAALAAECgYIBwAAAA==.Shoeknee:BAAALAADCgcIFAAAAA==.',Si='Silkysmoothe:BAAALAADCgEIAQAAAA==.Sindramalygo:BAAALAADCgMIAwAAAA==.Sizzlinghots:BAAALAADCgQIBAAAAA==.',Sk='Skyfax:BAAALAADCgQIBAAAAA==.',Sl='Slabunnie:BAAALAADCggICAAAAA==.Sliverbane:BAAALAADCgIIAgAAAA==.',Sm='Smeagole:BAAALAAECgcICAAAAA==.Smittae:BAAALAAECgEIAQAAAA==.Smolgrog:BAAALAADCgcIEAABLAADCggICgACAAAAAA==.Smolpriest:BAAALAADCggICgAAAA==.',Sn='Snazzydruid:BAAALAADCgQIBAAAAA==.',So='Soyäzul:BAAALAADCgMIAwAAAA==.',Sp='Sparkles:BAAALAAECgUIBQAAAA==.Spazer:BAAALAADCgQIBAAAAA==.',Ss='Ssimin:BAAALAAECgYICAAAAA==.',St='Stankytotems:BAAALAAECgIIAgAAAA==.Stargaryen:BAAALAADCggIDgABLAAECgYICQACAAAAAA==.Stkme:BAAALAAECggIAwAAAA==.Stluca:BAAALAADCgUIBQAAAA==.Stumpedtotem:BAAALAAECgYIDwAAAA==.Stärrdust:BAAALAADCgYICwAAAA==.',Su='Succma:BAAALAADCgIIAgAAAA==.',Sw='Swarmer:BAAALAADCgcICwAAAA==.',['Sí']='Sírén:BAAALAADCgQICQAAAA==.',Ta='Talpha:BAAALAADCgcIBwAAAA==.Targus:BAAALAAECgIIAgAAAA==.Taylorswift:BAAALAAECgMIAwAAAA==.Tazoo:BAAALAADCgcIDgAAAA==.',Te='Tektut:BAAALAAECgEIAQAAAA==.Tera:BAAALAADCgIIAgAAAA==.Texagar:BAAALAADCggIFQAAAA==.',Th='Thadeouss:BAAALAAECgYICgAAAA==.Thebigboom:BAAALAAECgMIAwAAAA==.Thecarter:BAAALAADCggICAAAAA==.Thelordmunzo:BAAALAAECgIIAgAAAA==.Theparish:BAAALAAECgYIDQAAAA==.Thewicked:BAAALAAECgUICQAAAA==.Thicchorns:BAAALAADCgcIBwAAAA==.Thorion:BAAALAADCgcICgAAAA==.Throatdemon:BAAALAAFFAIIAgAAAA==.Thudthudkill:BAAALAADCgcIBwAAAA==.Thudthudlaze:BAAALAADCgcIBwAAAA==.',Ti='Tichalock:BAAALAAECgEIAQAAAA==.Tirdrae:BAAALAADCggIDQAAAA==.',To='Totemcuck:BAAALAADCgUIBQAAAA==.',Tr='Treelimbs:BAAALAAECgYIDQAAAA==.Treemoo:BAAALAAECgIIAgAAAA==.Treeshooter:BAAALAADCgEIAQAAAA==.Tristey:BAAALAAECgMIAwAAAA==.',Tu='Turos:BAAALAAECgYICAAAAA==.',Un='Unavaluable:BAAALAADCgcIBwAAAA==.Untöuchable:BAAALAAECgYICgAAAA==.',Ur='Urskrog:BAAALAADCgYIBgAAAA==.',Va='Vadhal:BAAALAADCgcIBwAAAA==.Vanirion:BAAALAADCgEIAQAAAA==.',Ve='Vendatha:BAAALAADCgcICgAAAA==.Verdtual:BAAALAADCggIDwAAAA==.Verxl:BAAALAADCggIFwAAAA==.',Vi='Visarch:BAAALAAECgYIDQABLAADCgcICgACAAAAAA==.',Vo='Voidair:BAAALAADCgMIAwAAAA==.Voidnyou:BAAALAADCgMIAwAAAA==.Volund:BAAALAAECgUIBgAAAA==.',Wa='Wafflexpress:BAAALAADCgYIBgAAAA==.Warm:BAAALAADCgcICgAAAA==.Warwalkerz:BAAALAADCgcIBwAAAA==.Watermalorne:BAAALAAECgMIBQAAAA==.',Wi='Widowbaker:BAAALAAECgMIAgAAAA==.Wilbeats:BAAALAADCgYICgAAAA==.Winnototem:BAAALAAECgYIDQAAAA==.',Wr='Wranarror:BAAALAADCggIDAAAAA==.',Xa='Xakarius:BAAALAAECgMIAwAAAA==.Xalren:BAAALAAECgUIBgAAAA==.',Xp='Xpsz:BAAALAAECgIIAwAAAA==.',Xu='Xugos:BAAALAAECgYICQAAAA==.',Xy='Xyno:BAAALAAECgYIDQAAAA==.',Yo='Yooper:BAAALAADCgYIBgAAAA==.',Yu='Yulioz:BAAALAADCgcIDAAAAA==.',Za='Zamzams:BAAALAADCgQIAgAAAA==.Zatannaí:BAAALAAECgUIBgAAAA==.',Zd='Zdod:BAAALAADCgEIAQAAAA==.',Ze='Zeenie:BAAALAADCggICAAAAA==.Zendrost:BAAALAADCgEIAQAAAA==.',Zi='Zillidan:BAAALAADCgYIBgAAAA==.',Zo='Zoerik:BAAALAAECgYIDAAAAA==.Zongajuice:BAAALAAECgEIAQAAAA==.Zotoperen:BAAALAAECgYIDQAAAA==.',Zu='Zulazlok:BAAALAAECgMIBQAAAA==.Zuldindjarin:BAAALAADCgYIBwAAAA==.',['Zä']='Zäyder:BAAALAADCggICAAAAA==.',['Àm']='Àmunra:BAAALAAECgQICgAAAA==.',['Àn']='Àncksunamun:BAAALAAECgIIBAAAAA==.',['Áf']='Áfkautoshot:BAAALAAECgEIAQAAAA==.',['Ði']='Ðim:BAAALAAECgIIAgABLAAECgYIBwACAAAAAA==.',['Ñe']='Ñewt:BAAALAAECgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end