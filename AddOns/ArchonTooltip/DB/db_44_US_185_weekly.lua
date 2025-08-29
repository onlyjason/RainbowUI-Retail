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
 local lookup = {'Unknown-Unknown','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Druid-Guardian','Mage-Arcane','DemonHunter-Havoc','Druid-Feral','Monk-Brewmaster','Mage-Frost','Paladin-Retribution','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','Priest-Shadow','Hunter-Marksmanship',}; local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aedrius:BAAALAAECgEIAgAAAA==.',Ai='Ai:BAAALAADCgYIBgAAAA==.Aiwass:BAAALAAECgYIBgAAAA==.',Al='Alaira:BAAALAAECgMIAwAAAA==.Alexander:BAAALAADCggIFAAAAA==.',Am='Amathricus:BAAALAAECgMIAwAAAA==.',As='Ashuk:BAAALAADCgYIBgAAAA==.',At='Athena:BAAALAADCgQIBAABLAADCggIHQABAAAAAA==.',Au='Aura:BAAALAADCggIHQAAAA==.',Az='Azelia:BAAALAADCgcIEAAAAA==.',Ba='Barkybarnes:BAAALAADCgcIBwAAAA==.Basherboy:BAAALAAECgIIAwAAAA==.',Bo='Boldguy:BAAALAAECgMIBgAAAA==.',Bu='Bubbawubbaz:BAABLAAECoEUAAICAAgI6iCQCQDeAgACAAgI6iCQCQDeAgAAAA==.',Ca='Canneednew:BAAALAADCgQIBAABLAAECgYIBwABAAAAAA==.',Ch='Changarang:BAAALAAECggIEwAAAA==.Chaoslady:BAAALAADCgMIAwAAAA==.',Ci='Cia:BAAALAAECgMIAwAAAA==.',Cl='Claybigsby:BAABLAAECoETAAMDAAgIqByIEgA0AgADAAcIXB2IEgA0AgAEAAUI5BONHQAnAQAAAA==.Clif:BAAALAAECggIEwAAAA==.',Cr='Crowns:BAAALAAECgEIAQAAAA==.',Cy='Cyleste:BAAALAAECgIIAgAAAA==.',Da='Damien:BAAALAAECgIIAgAAAA==.Darkmaga:BAAALAADCggICgAAAA==.',De='Demonifrita:BAAALAADCggICAAAAA==.Derpy:BAAALAADCgcIBwAAAA==.',Di='Dippindotz:BAAALAADCggICAAAAA==.',Dj='Djwarlock:BAAALAAECgIIAgAAAA==.',Dr='Drachese:BAAALAADCgcIBwABLAAECgIIAwABAAAAAA==.Draincounter:BAAALAADCggICQAAAA==.Druchese:BAAALAAECgIIAwAAAA==.',Du='Duplicity:BAAALAAECgUIBgAAAA==.',Ea='Eagleeye:BAAALAADCggICgAAAA==.',Ei='Eiliwyn:BAAALAADCggICAAAAA==.',El='Ellcanay:BAAALAAECgEIAQAAAA==.',Em='Emsie:BAAALAADCggICAAAAA==.Emsley:BAAALAAECgcIDgAAAA==.',Er='Erebos:BAAALAADCgYIBgABLAADCggIFAABAAAAAA==.',Fo='Focalors:BAAALAAECgYIBgAAAA==.Foobear:BAABLAAECoEUAAIFAAgISCKIAAAJAwAFAAgISCKIAAAJAwAAAA==.',Fr='Freasey:BAAALAADCggICAAAAA==.',Fu='Furlock:BAAALAADCggICAAAAA==.',Ga='Gabriel:BAAALAADCgYIBwAAAA==.Galicia:BAAALAADCggICgAAAA==.',Gg='Ggheezus:BAAALAADCgIIAgAAAA==.',Gh='Gheezpriest:BAAALAADCgMIAwAAAA==.Gheezu:BAAALAADCgUIBQAAAA==.',Gi='Gir:BAAALAADCgUIBQAAAA==.',Go='Gochese:BAAALAAECgIIAgABLAAECgIIAwABAAAAAA==.',Gr='Grognag:BAAALAADCggICAAAAA==.',Gw='Gwaralmighty:BAAALAAECgcIDQAAAA==.',Ha='Haagen:BAAALAAECgUIBwAAAA==.Haagoon:BAAALAADCgYIBgAAAA==.Haiwen:BAAALAADCgEIAQAAAA==.Hatch:BAAALAAECgYIDgAAAA==.',Ho='Horsdoeuvres:BAAALAAECgEIAgAAAA==.',Ht='Ht:BAAALAADCgIIAgAAAA==.',Ib='Ibedruid:BAAALAADCgcIBwAAAA==.',If='Ifrita:BAABLAAECoEVAAIGAAcIqhECKgDPAQAGAAcIqhECKgDPAQAAAA==.Ifrite:BAAALAADCgYIBgAAAA==.',Im='Imafraid:BAABLAAECoEUAAIHAAgI3xsMEQCGAgAHAAgI3xsMEQCGAgAAAA==.Imbasoul:BAAALAAECgYIBwAAAA==.',Ja='Jackoneill:BAAALAAECgcIDQAAAA==.',Jo='Johnnydeeps:BAAALAAECggIBgAAAA==.Jormi:BAAALAAECgUIBwAAAA==.',Ka='Kabaayi:BAAALAADCgYIBgAAAA==.Kalthael:BAAALAADCgEIAQAAAA==.Kasaurus:BAAALAADCgYIBgAAAA==.Kasura:BAAALAADCgcIDQAAAA==.',Ko='Kowalski:BAACLAAFFIEFAAIIAAMIciCKAAAnAQAIAAMIciCKAAAnAQAsAAQKgRcAAggACAg7IdABAP4CAAgACAg7IdABAP4CAAAA.',Ku='Kurapika:BAAALAAECgUICAAAAA==.',La='Lambo:BAAALAADCggIFwAAAA==.',Li='Limedro:BAAALAAECgQIBAAAAA==.',Lo='Lochese:BAAALAADCgUIBQABLAAECgIIAwABAAAAAA==.Lockme:BAACLAAFFIEFAAMEAAMIUBmWAgC4AAAEAAIImR2WAgC4AAADAAIICBA/CACrAAAsAAQKgRcAAwQACAioJJcCAF0CAAQABwhYJJcCAF0CAAMABAisI9EjAJIBAAAA.Lockrock:BAAALAAECgUICAAAAA==.Loveanaga:BAAALAAECgEIAQAAAA==.',Ma='Magicdro:BAAALAADCggIDwAAAA==.Mary:BAAALAAECgUICgAAAA==.',Me='Mero:BAAALAADCgYIBgAAAA==.',Mi='Miorine:BAAALAAECgQIBAABLAAECgYIBgABAAAAAA==.Misskatherin:BAAALAAECgIIAgAAAA==.Mistbehavin:BAABLAAECoEUAAIJAAgIihsOBQBpAgAJAAgIihsOBQBpAgAAAA==.',Mo='Moginndar:BAAALAADCgMIAwAAAA==.Moochese:BAAALAADCgcIBwABLAAECgIIAwABAAAAAA==.Moostache:BAAALAADCgcICwAAAA==.',My='Myeongsoo:BAAALAADCggIDwAAAA==.Mytz:BAAALAAECgQIBwAAAA==.',Ne='Nedendos:BAAALAADCggICQAAAA==.',Ny='Nylannis:BAAALAADCgEIAQAAAA==.Nytrix:BAAALAAECgMIBAAAAA==.',Ob='Obhilis:BAAALAAECgQIBAABLAAECgYIBwABAAAAAA==.',On='Ono:BAAALAAECgYIDQAAAA==.',Or='Orionbtch:BAAALAADCggICAAAAA==.',Pe='Pepo:BAAALAADCgEIAQAAAA==.Persephone:BAAALAADCggICAAAAA==.Pettraner:BAABLAAECoETAAIIAAgIihY+BQBXAgAIAAgIihY+BQBXAgAAAA==.',Po='Poppy:BAAALAADCggICAAAAA==.Pouncer:BAAALAADCggICAAAAA==.',Pr='Primelight:BAAALAADCggIDgAAAA==.',Qw='Qwixx:BAAALAADCgIIAgAAAA==.',Ra='Raiden:BAAALAAECgMIAwAAAA==.Rataplague:BAAALAAECgUIBwAAAA==.Ratidari:BAAALAADCgQIBAABLAAECgUIBwABAAAAAA==.Ravenstorm:BAAALAADCgYIBgAAAA==.',Re='Remmîngton:BAAALAAECgUIBwAAAA==.',Ri='Riptidedro:BAAALAAECgcIDQAAAA==.',Ru='Runslikedeer:BAAALAAECgIIAgAAAA==.',Se='Sean:BAABLAAECoEUAAMGAAgIbiIXCAD9AgAGAAgIbiIXCAD9AgAKAAMIgRTvKwCxAAAAAA==.',Sh='Shadowstorm:BAAALAAECgQIBQAAAA==.Sheppy:BAABLAAECoEUAAILAAgIaSCPCQDlAgALAAgIaSCPCQDlAgAAAA==.Shimakaze:BAABLAAECoEUAAMMAAcIGRblCADCAQAMAAcIGRblCADCAQACAAEIMgRpjwAnAAAAAA==.Shizaam:BAABLAAECoEUAAINAAgIQSAGBwDtAgANAAgIQSAGBwDtAgAAAA==.Shy:BAAALAAECgIIAgAAAA==.',Si='Silly:BAAALAAECgIIAgAAAA==.Sinfxl:BAAALAAECgIIAgAAAA==.',Sk='Skullmages:BAAALAAECgcICgAAAA==.',Sl='Slapdaddy:BAAALAADCgYIBgAAAA==.Slayur:BAAALAADCgcIEAAAAA==.Slinkeril:BAAALAAECgEIAQAAAA==.Sloppydro:BAAALAADCggICAAAAA==.',Sm='Smileyp:BAACLAAFFIEHAAMOAAMIxRwNAgAaAQAOAAMIxRwNAgAaAQAPAAEImx4uCgBcAAAsAAQKgRgAAw4ACAgMIAQHALwCAA4ACAgMIAQHALwCAA8AAwhbHlYxAPoAAAEsAAUUAggCAAEAAAAA.',So='Socksimus:BAAALAADCgcIDQAAAA==.Sotari:BAAALAAECgEIAQAAAA==.Sozie:BAAALAAECgMIBgAAAA==.',Sp='Sproot:BAAALAADCggICAAAAA==.',St='Stabberz:BAAALAAECgcIEAAAAA==.Stoatshenge:BAABLAAECoEUAAIQAAgIsx8ABwC5AgAQAAgIsx8ABwC5AgAAAA==.',Su='Sushiroll:BAAALAAECgcIDAAAAA==.',Sw='Sweetfel:BAAALAAECgUIBwAAAA==.',Sy='Synkron:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.',Th='Thefriend:BAAALAAECgMIAwAAAA==.Thelasthope:BAAALAADCggIDwAAAA==.Thrass:BAAALAADCgEIAQAAAA==.',To='Tombslayer:BAAALAADCgUIBQAAAA==.',Tr='Trash:BAAALAADCggICAAAAA==.Trunk:BAAALAADCggICAAAAA==.',Va='Vannia:BAAALAADCgcIBwAAAA==.Variam:BAAALAAECgMIBQAAAA==.',Ve='Velannis:BAAALAAECgYICAAAAA==.Vessel:BAAALAAECgEIAQAAAA==.',Vi='Virikas:BAAALAAECgUIBwAAAA==.',Vo='Voidangel:BAAALAADCgQIBAAAAA==.',Vu='Vuo:BAAALAAECgUIBwAAAA==.',We='Wenzhuzhu:BAAALAADCgEIAQAAAA==.',Wr='Wrather:BAAALAAECgIIAgAAAA==.',Wu='Wuchese:BAAALAADCgcIDQAAAA==.',Xf='Xfreshh:BAAALAADCgMIAwAAAA==.',Ya='Yamalock:BAAALAAECgIIAgAAAA==.Yamá:BAAALAADCgEIAQABLAAECgcIDwABAAAAAA==.Yamå:BAAALAAECgcIDwAAAA==.',Za='Zapchese:BAAALAADCggIDgABLAAECgIIAwABAAAAAA==.Zavalu:BAAALAAECgcIDAAAAA==.',Zu='Zugszy:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end