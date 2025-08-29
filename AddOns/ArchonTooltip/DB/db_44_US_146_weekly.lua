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
 local lookup = {'Unknown-Unknown','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc','Hunter-Survival',}; local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aadrik:BAAALAAECgQIBQAAAA==.',Ac='Actualegirl:BAAALAAECggICQABLAAECggIEgABAAAAAA==.',Ak='Akiraha:BAAALAAECgEIAQAAAA==.',An='Annaesthetic:BAAALAADCggIBAABLAAECggICAABAAAAAA==.Annihilus:BAAALAADCgYICAABLAADCggIDgABAAAAAA==.',Ao='Aoibhe:BAAALAADCggICwAAAA==.',Ar='Ardaddie:BAAALAAECgMIBgAAAA==.Ardcher:BAAALAADCgcIDAABLAAECgMIBgABAAAAAA==.Arragorn:BAAALAAECgYIDgAAAA==.',As='Asendra:BAAALAAECgIIAgAAAA==.Asha:BAAALAAECgYIBgAAAA==.',At='Atulru:BAAALAAECgMIBQAAAA==.',Av='Avaelyn:BAAALAADCgMIAwAAAA==.Avylth:BAAALAADCgcIBwAAAA==.',Az='Azerath:BAAALAADCgYICQAAAA==.Azulá:BAAALAAECgIIAgAAAA==.Azuren:BAAALAAECgMIAwAAAA==.',Ba='Bacon:BAAALAAECgUIDAAAAA==.Baela:BAAALAADCgcIDQAAAA==.Barngoddess:BAAALAAECgMIBAAAAA==.Battlejester:BAAALAAECgYICQAAAA==.Batwayne:BAAALAAECgEIAQAAAA==.',Be='Beartalk:BAAALAAECgMIAwAAAA==.Beryleiah:BAAALAADCggIDAAAAA==.Beyla:BAAALAAECgQIBwAAAA==.',Bi='Bishamon:BAAALAAECgYICwAAAA==.',Bl='Bleau:BAAALAADCggICwAAAA==.Bloodimary:BAAALAADCgcIBwAAAA==.Bloodimess:BAAALAADCggICAAAAA==.Blôodräge:BAAALAADCgcIBwAAAA==.',Bo='Bosand:BAAALAADCggIBgAAAA==.',Br='Bradsun:BAAALAAECgMIAwAAAA==.Bralinnis:BAAALAAECgMIAwAAAA==.Bridh:BAAALAAECgMIAwAAAA==.',Bu='Butterkip:BAAALAAECggICwAAAA==.Butterkipz:BAAALAADCgQIBAAAAA==.',Ce='Celestial:BAAALAAECgcICgAAAA==.',Ch='Chaoslentlez:BAAALAAECgMIBAABLAAECgcICgABAAAAAA==.Cheww:BAAALAAECgMIAwAAAA==.Chicharrones:BAAALAADCggIDwABLAAECgUIDAABAAAAAA==.Chipahoy:BAAALAAECgEIAQAAAA==.',Cl='Clamius:BAABLAAECoEUAAICAAgIViIgCQDvAgACAAgIViIgCQDvAgAAAA==.',Co='Cobblee:BAAALAADCgYICgAAAA==.Coldass:BAAALAADCgYIBgAAAA==.Coombrain:BAAALAAECgcICwAAAA==.Corrupption:BAAALAADCgcIBwAAAA==.',Cr='Crazyboi:BAAALAADCgcIBwAAAA==.Critterzz:BAAALAAFFAIIAgAAAA==.',Da='Dachyy:BAAALAAECgYICwAAAA==.Darco:BAAALAADCgYICAAAAA==.',De='Deathkitten:BAAALAADCggICAAAAA==.Deathlentlez:BAAALAAECgcICgAAAA==.Deathshroom:BAAALAADCgYIBgAAAA==.Deepend:BAAALAAECgEIAQAAAA==.Demonhunter:BAAALAAECgIIAgAAAA==.Denger:BAAALAADCgEIAQAAAA==.Detharbinger:BAAALAADCgYIBgAAAA==.Devàna:BAAALAAECgQIBwAAAA==.',Di='Dizzle:BAAALAAECgcICgAAAA==.',Dj='Djazz:BAAALAADCgUIBwAAAA==.',Dk='Dkerhaze:BAAALAAECgMIBgAAAA==.',Do='Dolore:BAAALAADCgUIBQAAAA==.',Dr='Dreddnaught:BAAALAAECgMIBQAAAA==.Drunkard:BAAALAADCgYIBgAAAA==.',Ed='Eddie:BAAALAAECgIIAgAAAA==.',Eh='Ehlsa:BAAALAAECgcICgAAAA==.',Ei='Eirinny:BAAALAAECgUIBQAAAA==.',El='Eldes:BAAALAAECgQIBwAAAA==.Eldingbring:BAAALAADCgMIAwAAAA==.',Ez='Ezmee:BAAALAADCgcIDQAAAA==.',Fa='Fablê:BAAALAADCgcIBwAAAA==.',Fe='Featherstep:BAAALAADCgIIAQAAAA==.',Fu='Fundip:BAAALAADCgcIDgAAAA==.',['Fù']='Fùrìeüx:BAAALAAECgUICAAAAA==.',Ga='Galvanis:BAAALAAECgYICQAAAA==.Gamaikuba:BAAALAAECgEIAQAAAA==.Gart:BAAALAADCggIDwAAAA==.Gatlu:BAAALAADCgcIBwAAAA==.Gawdsmackk:BAAALAAECgQIBwAAAA==.Gazokks:BAAALAAECgYICAAAAA==.',Ge='Getrektpos:BAAALAADCgcICAAAAA==.',Gh='Ghoztface:BAAALAAECgIIBAAAAA==.Ghöstbeef:BAABLAAECoESAAMDAAgISB1TBACQAgADAAgISB1TBACQAgAEAAQIrQjNYQC5AAAAAA==.',Gi='Gibbii:BAAALAADCgcICAAAAA==.Gibs:BAAALAADCgcIBwAAAA==.',Gl='Glacialwrath:BAAALAADCgUIBQAAAA==.Glitterboy:BAAALAAECgIIAgABLAAECgcICgABAAAAAA==.',Gr='Gralmerte:BAAALAAECgMIBQAAAA==.Grawfern:BAAALAAECgYIDgAAAA==.',Gw='Gwarf:BAAALAADCggICAAAAA==.Gwrath:BAAALAAECgEIAgAAAA==.',Gy='Gypsum:BAAALAADCgcIDgAAAA==.',Ha='Haether:BAAALAAECgQIBwAAAA==.Hatsu:BAAALAAECgYICQAAAA==.',He='Healulngtime:BAAALAAECgEIAQAAAA==.Helon:BAAALAADCgcICgAAAA==.',Ho='Holygral:BAAALAADCgMIAwAAAA==.Holylentlezz:BAAALAADCggICAABLAAECgcICgABAAAAAA==.Holyox:BAAALAAECgQICAAAAA==.',Ht='Hturtledk:BAAALAADCgUIBwAAAA==.',Hu='Huntardiq:BAAALAADCggICAAAAA==.',Ie='Ieatmana:BAAALAADCgIIAgAAAA==.',Im='Imdatroll:BAAALAAFFAIIAgAAAA==.',In='Incantada:BAAALAADCgYICwAAAA==.Inexorable:BAAALAAECgcICwAAAA==.',Ir='Irakwa:BAAALAADCgMIBQAAAA==.Iristuk:BAAALAADCgYIBgAAAA==.',It='Itches:BAAALAAECgcICgAAAA==.',Ja='Jaiferre:BAAALAADCgEIAQAAAA==.Jarbito:BAAALAAECgcIEQAAAA==.',Ji='Jigokukita:BAEALAADCggICAABLAAECggIEgABAAAAAA==.Jinfizz:BAAALAAECgYICQAAAA==.',Jo='Jocommande:BAAALAAECgMIAwAAAA==.Jorrlock:BAAALAADCggIDwAAAA==.',Jp='Jpdh:BAEALAAECgYICwAAAA==.',Ju='Junksvil:BAAALAADCggIDgAAAA==.',Ke='Kernalangus:BAAALAADCgcICAAAAA==.',Kh='Khalyon:BAAALAAECgYICwAAAA==.',Ki='Kinini:BAAALAADCgYIBgAAAA==.',Kl='Klid:BAAALAAECgYICQAAAA==.Kllaita:BAAALAADCgYIBgAAAA==.',Ko='Korinth:BAEALAAECggIEgAAAA==.',Ku='Kurzon:BAAALAAECgYICQAAAA==.',Ky='Kyra:BAAALAADCggIDQAAAA==.',['Kä']='Kätajj:BAAALAADCggIDgAAAA==.',La='Lazuli:BAAALAADCggIDgABLAAECgUIDAABAAAAAA==.',Le='Leeflord:BAAALAAFFAIIAgAAAA==.Legault:BAAALAAECgEIAQAAAA==.Legionofboom:BAAALAADCgcIDQAAAA==.Lenitol:BAAALAADCgMIAwABLAADCgcICgABAAAAAA==.Lethfel:BAAALAADCgEIAQAAAA==.Lethtel:BAAALAAECgMIBQAAAA==.',Li='Lich:BAAALAAECgEIAQAAAA==.Likaratzu:BAAALAADCgUIBQAAAA==.Lillithfaust:BAAALAADCggIDAAAAA==.Limbø:BAAALAADCgYIBgAAAA==.Liquidturtle:BAAALAADCgUIBQAAAA==.Livie:BAAALAADCggIDgAAAA==.',Lo='Longwood:BAAALAAECgYICQAAAA==.Loraddesmos:BAAALAAECgQIBgAAAA==.',Lu='Lucaas:BAAALAAECgYICgAAAA==.Luminå:BAAALAADCgcIBwAAAA==.',Ly='Lyship:BAAALAAECgUICQAAAA==.',['Lè']='Lègolas:BAAALAAECgMIAwABLAAECgcICgABAAAAAA==.',Ma='Manfred:BAAALAAECgMIBgAAAA==.Mataquay:BAAALAADCgMIAwAAAA==.Mawz:BAABLAAECoEXAAIFAAgIZCG+BAATAwAFAAgIZCG+BAATAwAAAA==.',Me='Meascii:BAAALAADCgYIAwAAAA==.Merc:BAAALAAECggIDwAAAA==.',Mi='Mirespike:BAAALAAFFAIIAgAAAA==.',Mo='Morlis:BAAALAADCgQIBgAAAA==.',Mu='Munny:BAAALAADCgcIBwAAAA==.',My='Mystris:BAAALAADCggIDQAAAA==.',Na='Nadia:BAAALAADCgMIAwAAAA==.',Ne='Nevicus:BAAALAADCgEIAQAAAA==.',Ni='Nisdenar:BAAALAADCgYIBgAAAA==.',No='Nohealzforu:BAAALAADCggIDwAAAA==.Noobacleese:BAAALAAECgYICQAAAA==.Noreda:BAAALAAECgYIDAAAAA==.Notit:BAAALAADCgMIBgAAAA==.',Ny='Nyghtrider:BAAALAADCggIDgAAAA==.Nykayla:BAAALAADCgYIBgAAAA==.Nyneeve:BAAALAADCgUIBQAAAA==.',['Nÿ']='Nÿmera:BAAALAAECgQIBwAAAA==.',Ol='Olgrin:BAAALAADCggIEAABLAADCggIGAABAAAAAA==.',Or='Orw:BAAALAADCgMIBQAAAA==.',Pa='Pain:BAAALAADCgcIBwAAAA==.Partita:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.',Pb='Pbmage:BAAALAADCgQIBAAAAA==.',Pe='Percocetpete:BAAALAAECggIEgAAAA==.Peregrine:BAAALAADCgcICAAAAA==.',Ph='Phaet:BAABLAAECoETAAMGAAgIwCGwBgDoAgAGAAgIqx+wBgDoAgAHAAcIUB6pBwDqAQAAAA==.Phaux:BAAALAADCgQIBAAAAA==.Phos:BAAALAADCgcICwABLAADCgcIEwABAAAAAA==.Phosdormu:BAAALAADCggICAABLAAECggIEgADAEgdAA==.',Pi='Pinguino:BAAALAADCgYIBgAAAA==.',Pl='Plâgue:BAAALAAECgYICQAAAA==.',Pr='Providence:BAAALAAECgYICQAAAA==.',Pu='Puntthegnome:BAAALAADCgYIBgABLAAECggIFgACAA0gAA==.',Ra='Raezan:BAAALAAECgcIDgAAAA==.Rahkon:BAAALAAECgMIAwAAAA==.Rainforest:BAAALAADCggIDwAAAA==.Ramdem:BAAALAADCggICAAAAA==.Ramden:BAAALAAECgUICQAAAA==.Rampant:BAAALAADCgcIDgAAAA==.Ratherton:BAABLAAECoEWAAICAAgIDSCqCwDSAgACAAgIDSCqCwDSAgAAAA==.',Re='Redasurk:BAAALAADCggICAAAAA==.Resoluteone:BAAALAAECgYICwAAAA==.Retnu:BAAALAAECgEIAQAAAA==.Revytwohand:BAAALAAFFAIIAgAAAA==.',Rh='Rhok:BAAALAADCgUIBQAAAA==.',Ro='Rohdey:BAAALAAECgcICgAAAA==.',Sa='Sallyd:BAAALAADCgMIBgAAAA==.Sandy:BAAALAADCgcIDQAAAA==.Sardmongo:BAAALAAECgMIAwAAAA==.Sarduccini:BAABLAAECoEMAAMHAAYI9QlcHgAiAQAHAAYIKAlcHgAiAQAIAAMITQbNHACYAAAAAA==.Sargeritoz:BAAALAAECgIIAgAAAA==.',Sc='Scoobydubius:BAABLAAECoEWAAIJAAcIZB7nEwBlAgAJAAcIZB7nEwBlAgAAAA==.Scootbob:BAAALAAECgQIBAAAAA==.',Se='Sekhmet:BAAALAADCggIEwAAAA==.',Sh='Shanarea:BAAALAADCgQIBAAAAA==.',Si='Silvalus:BAAALAADCggIGAAAAA==.Sin:BAAALAADCgcIBwAAAA==.',Sl='Slitherus:BAAALAAECgEIAQAAAA==.',So='Soad:BAAALAAECgMIAwAAAA==.Soifure:BAAALAADCgcIBwAAAA==.Solvenia:BAAALAAECgYICQAAAA==.Sondaar:BAAALAADCgcIDAAAAA==.',Sp='Spicyboy:BAAALAAECgYICQAAAA==.',St='Staccato:BAAALAAECgYICQAAAA==.Stalrun:BAAALAADCgQIBAABLAADCggIDgABAAAAAA==.Stormlux:BAAALAADCggICQAAAA==.Stormslight:BAAALAADCgcICwAAAA==.Stormynature:BAAALAADCggICAAAAA==.',Sw='Swiftdéath:BAAALAADCggIDwAAAA==.Swtbabybilly:BAAALAADCgcIDwAAAA==.',Ta='Taby:BAAALAADCgQIBAAAAA==.Talas:BAAALAAECgYIBgAAAA==.Tamarack:BAAALAAECgYIBwAAAA==.',Te='Teefa:BAAALAADCgcIBwAAAA==.Tehmber:BAAALAADCggIBwAAAA==.Tenssid:BAAALAADCgcIEAAAAA==.',Th='Thefaker:BAAALAADCgcIDAAAAA==.',Tr='Traevok:BAAALAADCgUIBwAAAA==.Trywind:BAAALAADCgEIAQAAAA==.',Ty='Typicaldrood:BAAALAADCggICAAAAA==.Typicalfriar:BAAALAADCgcIBwAAAA==.Typicalsham:BAAALAADCgEIAQAAAA==.',Ul='Ulysius:BAAALAAECgYICwAAAA==.',Un='Unicorneater:BAAALAAECgYICQAAAA==.',Ur='Urund:BAAALAAECgMIBQAAAA==.',Va='Valarfax:BAAALAADCgEIAQAAAA==.Valfreude:BAAALAADCgUIBQAAAA==.Valkisek:BAAALAAECgUIBQAAAA==.Valkonigen:BAAALAADCgEIAQAAAA==.Vallkia:BAAALAAECgcIEQAAAA==.Vandal:BAAALAADCgQIBgAAAA==.Vanelfsing:BAAALAAECggICAAAAA==.Vash:BAAALAAFFAIIAgAAAA==.',Ve='Velaric:BAAALAAECgYICQAAAA==.Veldu:BAAALAAECgYIEgAAAA==.Veloe:BAAALAAECgYIBgABLAAECgYIEgABAAAAAA==.Vespyr:BAAALAAECgMIAwAAAA==.',Vi='Vizimir:BAAALAAECgEIAQAAAA==.',Vo='Voodoomkin:BAAALAADCgEIAQAAAA==.',Wa='Waifu:BAAALAADCggICAAAAA==.Wascii:BAAALAADCgcICQAAAA==.',Wh='Whiskeybear:BAAALAADCggIEgAAAA==.',Wy='Wyrmheal:BAAALAAECgcICgAAAA==.Wyvernwool:BAAALAAECgUICAAAAA==.',Xa='Xander:BAAALAADCgQIBAAAAA==.',Xi='Xiba:BAAALAADCgMIAwAAAA==.',Ya='Yamihime:BAAALAAECgYICgAAAA==.',Za='Zalará:BAAALAAECggICAAAAA==.Zapslap:BAAALAADCgcIEwAAAA==.Zapzokks:BAAALAADCggICAAAAA==.',Ze='Zeaket:BAABLAAECoEWAAIKAAgIGBuEAQB5AgAKAAgIGBuEAQB5AgAAAA==.Zephyr:BAAALAADCggIEQABLAAECgMIAwABAAAAAA==.',Zi='Zindari:BAAALAADCgcIDgAAAA==.',Zo='Zorcan:BAAALAADCggIFQAAAA==.',Zu='Zulfilith:BAAALAADCgQIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end