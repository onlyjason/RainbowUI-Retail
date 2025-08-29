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
 local lookup = {'Unknown-Unknown','Druid-Restoration',}; local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aandrea:BAAALAAECgYICQAAAA==.Aarmorr:BAAALAAECgMIBAAAAA==.',Ac='Ace:BAAALAADCgcIBwAAAA==.Aceshadow:BAAALAAECgIIAwAAAA==.Achey:BAAALAADCgcIBwAAAA==.',Ae='Aechelus:BAAALAAECgEIAQABLAAECggIAgABAAAAAA==.Aeyndria:BAAALAADCgcICgAAAA==.',Ak='Akkadian:BAAALAADCgYIDAAAAA==.',Al='Alchon:BAAALAAECgUIBwAAAA==.Aldera:BAAALAAECgEIAQAAAA==.Alestrasia:BAAALAADCggIFQAAAA==.Allornan:BAAALAADCgUIBwAAAA==.Allykat:BAAALAAECgQIBwAAAA==.Alma:BAAALAADCgIIAgAAAA==.Alvagíngras:BAAALAAECgMIBAAAAA==.',Am='Ammastary:BAAALAADCgUIBQAAAA==.',An='Ananiel:BAAALAAECgMIBAAAAA==.',Ar='Archiven:BAAALAAECgIIAgAAAA==.',As='Ashuranadi:BAAALAADCgcIEQAAAA==.',At='Atonement:BAAALAAECgMIBAAAAA==.',Au='Aumaril:BAAALAAECgQIBQAAAA==.',Av='Averus:BAAALAAECgYICQAAAA==.',Az='Azariel:BAAALAADCggICAAAAA==.Azuriah:BAAALAAECgYICQAAAA==.',Ba='Bagel:BAAALAAECgIIAgAAAA==.Batchslip:BAAALAADCgQIBAAAAA==.',Be='Bedhead:BAAALAAECgYICQAAAA==.Bejorn:BAAALAADCgcIEQAAAA==.Belaim:BAAALAADCgQIBAAAAA==.Belovis:BAAALAAECgIIAQAAAA==.Benevolence:BAAALAADCgUIBQABLAADCggIDgABAAAAAA==.',Bi='Biegeltop:BAAALAADCgcIBwAAAA==.Bigjohnii:BAAALAADCggIFQAAAA==.Binkyo:BAAALAAECgUICAAAAA==.',Bl='Blackcoat:BAAALAADCgIIAgAAAA==.Bloodwraith:BAAALAADCgMIAwAAAA==.',Bo='Borrowedsoul:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Bosshog:BAAALAADCggICAAAAA==.',Br='Brabanzio:BAAALAAECgIIAgABLAAECgQICwABAAAAAA==.Brasnite:BAAALAAECgQIBAAAAA==.Brewrock:BAAALAADCggIFwAAAA==.',Bu='Buffwarlock:BAAALAAECgYICQAAAA==.Burningblunt:BAAALAADCgcIBwAAAA==.',Ca='Carnissa:BAAALAADCgcIDQAAAA==.Catsneverdie:BAAALAAECggIAgAAAA==.',Ch='Chillykiller:BAAALAADCgEIAQAAAA==.Chokk:BAAALAADCgIIAgAAAA==.Chrismessiah:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Chunknoriss:BAAALAAECgIIAgAAAA==.',Cl='Clurethyr:BAAALAAECgUIBwAAAA==.',Co='Cobblestone:BAAALAADCgQIBAAAAA==.Collukcivan:BAAALAADCgQICAAAAA==.Constella:BAAALAADCgYIBgAAAA==.Coppertan:BAAALAADCgIIAgAAAA==.Corrosion:BAAALAAECgIIAwAAAA==.',Cr='Crazyshammy:BAAALAAECgIIAgAAAA==.Crunchynuget:BAAALAAECgEIAQAAAA==.',Cu='Cujotaro:BAAALAADCgcIDAAAAA==.',Cv='Cvhamster:BAAALAADCggICgAAAA==.',Cy='Cybeast:BAAALAAECgQIBQAAAA==.Cynriel:BAAALAADCgMIAwAAAA==.',Da='Daciana:BAAALAADCgcIBwAAAA==.Dados:BAAALAAECgYICAAAAA==.Darkbell:BAAALAADCgMIAwAAAA==.Darkkromdor:BAAALAAECgUICAAAAA==.Darloct:BAAALAADCggIFQAAAA==.',De='Deadelff:BAAALAAECgIIAgAAAA==.Deathmeta:BAAALAADCgIIAgABLAAECgMIBAABAAAAAA==.Deathshayde:BAAALAADCgIIAgAAAA==.Demonio:BAAALAAECgEIAQAAAA==.Demonkoh:BAAALAAECgMIBAAAAA==.Des:BAAALAAECgMIBAAAAA==.Dezath:BAAALAADCggIFAABLAAECgMIBAABAAAAAA==.',Dk='Dkpheonix:BAAALAAECgQIBgAAAA==.',Do='Dolemite:BAAALAAECgQIBgAAAA==.Donalbain:BAAALAAECgQICwAAAA==.Dotsforfun:BAAALAADCgcIBwAAAA==.',Dr='Drana:BAAALAADCgQIBAAAAA==.',Du='Dudepriest:BAAALAAECgYIDQAAAA==.Dumpsterfyre:BAAALAAECgUICQAAAA==.',Eg='Eggroll:BAAALAADCggIDgAAAA==.',El='Elayle:BAAALAAECgYICQAAAA==.Ellipsís:BAAALAADCgcIBwAAAA==.Elyssaris:BAAALAAECgYICwAAAA==.',Em='Emìly:BAAALAAECgYICQAAAA==.',En='Enelya:BAAALAADCgcICwAAAA==.Ennellya:BAAALAADCgQIBAABLAADCgcICwABAAAAAA==.Entaria:BAAALAAECgMIBwAAAA==.',Ep='Episkey:BAAALAAECgYICQAAAA==.',Eq='Eq:BAAALAAECgYIBwAAAA==.',Er='Ereviss:BAAALAADCggIDwAAAA==.Eroversion:BAABLAAECoEcAAICAAcIqROfGwCPAQACAAcIqROfGwCPAQAAAA==.',Es='Esmay:BAAALAAECgYIBwAAAA==.Eso:BAAALAADCggIDwAAAA==.',Et='Ethren:BAAALAAECgYICQAAAA==.',Eu='Eudoxos:BAAALAAECgMIBAAAAA==.',Ey='Eyebrows:BAAALAAECgYIBgAAAA==.',Fa='Falcone:BAAALAAECgMICAAAAA==.',Fe='Felbolter:BAAALAAECgEIAQAAAA==.',Fi='Filgulfin:BAAALAAECgYICwAAAA==.Finkate:BAAALAADCggICAAAAA==.Firebringer:BAAALAAECgYICwAAAA==.',Fl='Flaakk:BAAALAADCgcICAAAAA==.Flameclaws:BAAALAADCgYIBgAAAA==.Flamehunter:BAAALAAECgYIDwAAAA==.Floki:BAAALAAECgIIAgAAAA==.',Fo='Foods:BAAALAAECgYICQAAAA==.Fotmxd:BAAALAAECggIEwAAAA==.',Fr='Froslass:BAAALAADCgcIDgAAAA==.Frostydog:BAAALAADCgEIAQAAAA==.',Fu='Furryfury:BAAALAAECgYICwAAAA==.Fustín:BAAALAAECgYICgAAAA==.',Ga='Gaboo:BAAALAAECgEIAQAAAA==.Gasketmaker:BAAALAADCgcIBwAAAA==.Gaufrette:BAAALAADCggICAAAAA==.',Gl='Gloomwalker:BAAALAAECgQIBAAAAA==.',Gn='Gnomearra:BAAALAAECgUICAAAAA==.',Go='Goburina:BAAALAAECgcICwAAAA==.Goldhawk:BAAALAADCgYIBgAAAA==.',Gr='Grumblegut:BAAALAADCgUICAAAAA==.',['Gí']='Gímlí:BAAALAAECgMIAwABLAAECgYIBgABAAAAAA==.',Ha='Halcyndraag:BAAALAAECgYICQAAAA==.Hartu:BAAALAAECgYICwAAAA==.',He='Healsofpain:BAAALAAECgEIAgAAAA==.',Hi='Hittuumn:BAAALAAECgMIBgAAAA==.',Ho='Hollyheck:BAAALAAECgEIAQAAAA==.',Ic='Ichigoson:BAAALAAECgUIBwAAAA==.',Id='Idiocracy:BAAALAAECgMIBgAAAA==.',Im='Imwithfloki:BAAALAAECgYIAgAAAA==.',In='Incredabo:BAAALAADCgQIBAAAAA==.',Ir='Irolen:BAAALAADCgQIBAAAAA==.Irys:BAAALAADCgIIAgAAAA==.',Is='Ishida:BAAALAAECggIEgAAAA==.Ismokeu:BAAALAAECgMIBgAAAA==.',Ja='Jackoneal:BAAALAAECgEIAgAAAA==.Jalidelo:BAAALAAECgUIBwAAAA==.Jaytoonice:BAAALAADCgEIAQAAAA==.',Je='Jenifurr:BAAALAADCgcICwAAAA==.',Ji='Jimbowaboki:BAAALAAECggIEAAAAA==.',Jo='Joeexxotic:BAAALAAECgUIBwAAAA==.Johan:BAAALAAECgYICQAAAA==.Joranbragi:BAAALAADCggIFQAAAA==.Jordanjr:BAAALAADCgcIBwAAAA==.Jotoonice:BAAALAADCgcIBwAAAA==.',Jt='Jtoothaordan:BAAALAAECggIEwAAAA==.',Ju='Judeau:BAAALAADCgUIBQAAAA==.',Ka='Kaana:BAAALAAECgYICQAAAA==.Kaesteyclaws:BAAALAAECgUIBwAAAA==.Kallura:BAAALAAECgYICgAAAA==.Kamoniwana:BAAALAADCgcIBwAAAA==.Kaotic:BAAALAAECgYICQAAAA==.Karungash:BAAALAAECgcIDQAAAA==.Karvell:BAAALAAECgUIBwAAAA==.',Kc='Kchowchow:BAAALAAECgYICQAAAA==.',Ke='Kelonaar:BAAALAAECgYIDQAAAA==.',Kh='Khazri:BAAALAAECgQIBAAAAA==.',Ki='Kikflipcombo:BAAALAAECgYICAAAAA==.',Kl='Klub:BAAALAADCgMIAwAAAA==.',Ko='Koranthia:BAAALAAECgYIBwAAAA==.Koval:BAAALAAECgEIAQAAAA==.',Kr='Krooler:BAAALAAECgMIAwAAAA==.',Ku='Kungfoumoo:BAAALAADCggIEwAAAA==.Kuraokami:BAAALAAECgUIBQAAAA==.',La='Ladgark:BAAALAAECgIIAgAAAA==.Lameshock:BAAALAAECgYICgAAAA==.Lanval:BAAALAAECgYICwAAAA==.',Le='Leetah:BAAALAAECgYICgAAAA==.',Li='Lilithh:BAAALAAECgEIAQAAAA==.Lilyoptra:BAAALAADCggIFQAAAA==.Lindalia:BAAALAADCggICwAAAA==.',Lm='Lminus:BAAALAADCgEIAQAAAA==.',Lo='Loriane:BAAALAADCgcICAAAAA==.Lovegood:BAAALAADCgQIBAAAAA==.',Lu='Lumbermill:BAAALAAECgQIBAAAAA==.',['Lá']='Láw:BAAALAADCgIIAgAAAA==.',['Lê']='Lêmonaide:BAAALAAECgYICQAAAA==.',Ma='Majandra:BAAALAADCggIDwAAAA==.Malyndra:BAAALAAECgYICgAAAA==.Marshe:BAAALAAECgcICQAAAQ==.Marvolt:BAAALAADCggICAAAAA==.Mathis:BAAALAADCgUIBQAAAA==.',Mc='Mcrae:BAAALAADCgYIBgAAAA==.',Me='Meatwod:BAAALAADCgIIAgAAAA==.Melon:BAAALAAECgIIAgAAAA==.Meriam:BAAALAAECgYICgAAAA==.Mesmash:BAAALAAECgQIBAAAAA==.Metahunt:BAAALAAECgEIAQABLAAECgMIBAABAAAAAA==.Metamasters:BAAALAAECgMIBAAAAA==.Metavoker:BAAALAADCgcIEAABLAAECgMIBAABAAAAAA==.',Mi='Mialtaa:BAAALAADCgYIAQABLAAECgMIBAABAAAAAA==.Mihile:BAAALAADCggIBwAAAA==.Mikko:BAAALAADCggIDAAAAA==.Miles:BAAALAADCgUIBQAAAA==.Minidude:BAAALAADCgYIBgAAAA==.Mizuoh:BAAALAAECgYICgAAAA==.',Mo='Moejojojo:BAAALAAECgIIAgAAAA==.Moofasaha:BAAALAAECgIIAgAAAA==.Mortegom:BAAALAADCgcIEQAAAA==.',Na='Nabû:BAAALAADCgIIAgAAAA==.Naral:BAAALAADCgcIBwAAAA==.Nashalie:BAAALAAECgQIBAAAAA==.',Ne='Nefele:BAAALAAECgYIBwAAAA==.Nexbasia:BAAALAAECgYICQAAAA==.',Ni='Nickyboy:BAAALAAECgYIDAAAAA==.Nightevel:BAAALAAECgMIAwAAAA==.',No='Northiko:BAAALAADCggIEAAAAA==.',Nu='Nukras:BAAALAAECggIAgAAAA==.',['Né']='Néxus:BAAALAADCgcIBwAAAA==.',Or='Oriqh:BAAALAADCgIIAgAAAA==.Orìon:BAAALAADCgIIAgABLAAECgYICQABAAAAAA==.',Ot='Otherrhu:BAAALAADCggIFAAAAA==.',Oz='Ozo:BAAALAADCgMIAwAAAA==.',Pa='Pallyscorned:BAAALAAECgUIBgAAAA==.',Ph='Phleau:BAAALAAECgQIBgAAAA==.Phoebell:BAAALAADCggIFQAAAA==.',Pi='Piggy:BAAALAAECgcIDQAAAA==.',Po='Portals:BAAALAADCgIIAgAAAA==.',Pr='Principessa:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.',Pu='Punka:BAAALAADCggICAAAAA==.Pus:BAAALAADCggICAAAAA==.',['Pé']='Péach:BAAALAAECgIIAgAAAA==.',Qu='Quasar:BAAALAAECgUIBQAAAA==.',Ra='Raeku:BAAALAAECgUIBwAAAA==.Rainnir:BAAALAADCgIIAgAAAA==.Raisins:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.Ralokain:BAAALAADCgIIAgAAAA==.Rathalo:BAAALAADCgcIBwAAAA==.Rayy:BAAALAAECgQIBAAAAA==.',Re='Realpotato:BAAALAADCggICAAAAA==.Rengai:BAAALAADCgIIAgAAAA==.',Ri='Richcraniums:BAAALAADCgcIEQAAAA==.Richie:BAAALAAECgEIAQAAAA==.Rivr:BAAALAAECgYICQAAAA==.',Ro='Robomurph:BAAALAADCgIIAgAAAA==.Romfax:BAAALAADCgcIBwABLAAECggIEQABAAAAAA==.Ronfax:BAAALAAECggIEQAAAA==.Ronnan:BAAALAAECgIIAwAAAA==.Roqli:BAAALAAECgUIBwAAAA==.',Ry='Ryuusythe:BAAALAAECgEIAQAAAA==.',Sa='Saltsqurrell:BAAALAADCggICAAAAA==.Sanivan:BAAALAAECgYIDAAAAA==.Sarmuc:BAAALAAECgYIBwAAAA==.',Sc='Schadoww:BAAALAAECgIIAgAAAA==.Scratchy:BAAALAADCgQIBQAAAA==.Scubagal:BAAALAADCggIFQAAAA==.',Se='Sempra:BAAALAADCgUIBQAAAA==.Senryi:BAAALAADCgIIAgAAAA==.Seä:BAAALAAECgMIBQAAAA==.',Sh='Shivant:BAAALAAECgEIAQAAAA==.Shmeegleroop:BAAALAADCggICgAAAA==.',Si='Sinderela:BAAALAADCggIDwAAAA==.Sistul:BAAALAADCgIIAgAAAA==.',Sl='Slammy:BAAALAAECgYICQAAAA==.Slewg:BAAALAAECgMIAwAAAA==.',Sm='Smalltwngirl:BAAALAADCgEIAQABLAAECggIEQABAAAAAA==.',So='Solaspirus:BAAALAAECgQIBgAAAA==.',Sp='Sperg:BAAALAADCgMIAwAAAA==.',St='Standinfire:BAAALAAECgYIDgAAAA==.Stardre:BAAALAAECgEIAQAAAA==.',Sw='Sweetstorm:BAAALAAECgEIAQAAAA==.',Sy='Sylphrenä:BAAALAAECgUIBwAAAA==.Syphis:BAAALAAECgIIBAAAAA==.Syrius:BAAALAADCgEIAQABLAADCgQICAABAAAAAA==.',Ta='Taedrin:BAAALAADCggICAAAAA==.Taekoad:BAAALAAECgMIBAAAAA==.Tanedarel:BAAALAAECggICQAAAA==.',Te='Teasa:BAAALAADCggIFQAAAA==.Tekeela:BAAALAADCgcIDQABLAADCgcIDgABAAAAAA==.Tekeelà:BAAALAADCgcIDgAAAA==.Tenzen:BAAALAADCgIIAgAAAA==.',Th='Theacë:BAAALAADCggIDAAAAA==.Thianna:BAAALAADCgMIAwAAAA==.Thobu:BAAALAADCgcICQAAAA==.Thodos:BAAALAAECgYICQAAAA==.Thornscale:BAAALAAECgUIBgAAAA==.',Ti='Tigolcrittys:BAAALAAECgYIBgAAAA==.Tinymarks:BAAALAADCgQIBAAAAA==.',To='Torcerotops:BAAALAADCgcICwAAAA==.Totem:BAAALAADCggIEAAAAA==.Totenz:BAAALAADCggIDgAAAA==.',Tr='Triloq:BAAALAADCgMIAwAAAA==.',Tu='Tusago:BAAALAAECgYICgAAAA==.',Ul='Ularden:BAAALAADCgQIBAAAAA==.Uller:BAAALAAECgIIAgAAAA==.',Um='Umbrafang:BAAALAADCgEIAQAAAA==.',Va='Vaimei:BAAALAAECgYICgAAAA==.Valairia:BAAALAAECgYICQAAAA==.Vantiktos:BAAALAADCgcIEQAAAA==.Vapor:BAAALAADCggIDgAAAA==.',Ve='Veebs:BAAALAADCggICwAAAA==.Vento:BAAALAAECgQIBgAAAA==.Veridian:BAAALAADCgUIBQAAAA==.Veterpeinss:BAAALAADCgIIAgAAAA==.',Vi='Virauca:BAAALAAECgYICwAAAA==.',Vo='Voltimand:BAAALAADCgUIBQABLAAECgQICwABAAAAAA==.',Wa='Walkabout:BAAALAAECgYICwAAAA==.Wankz:BAAALAAECgIIAgAAAA==.Warriorguyes:BAAALAADCgcIBwAAAA==.',We='Wezmerelda:BAAALAAECgYICAAAAA==.',Wh='Whisperingei:BAAALAADCggICAAAAA==.',Wi='Widowx:BAAALAAECgYICAAAAA==.Wintersolace:BAAALAAECgYICQAAAA==.Wisehoof:BAAALAADCggIDwAAAA==.',Wo='Wolftheonly:BAAALAAECgEIAQAAAA==.',Wr='Wryn:BAAALAAECgEIAQAAAA==.',Xi='Xisera:BAAALAADCggICwAAAA==.',Xs='Xsuns:BAAALAAECgYICQAAAA==.',Yo='Yodapan:BAAALAADCggIFQAAAA==.',Yv='Yve:BAAALAADCgIIAgAAAA==.',Za='Zarathiel:BAAALAAECgcICQAAAA==.',Ze='Zeddicus:BAAALAAECgQIBgAAAA==.Zeepher:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.',['Ëu']='Ëulogy:BAAALAADCgQIBAABLAAECgMIBAABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end