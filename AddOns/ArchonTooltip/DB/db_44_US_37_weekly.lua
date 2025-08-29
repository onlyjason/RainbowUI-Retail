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
 local lookup = {'Druid-Restoration','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Druid-Balance','Warlock-Destruction','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution',}; local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abluehunter:BAAALAAECgMIAwAAAA==.Abominable:BAAALAADCgcIBwAAAA==.',Ac='Accuser:BAAALAADCgcIDAAAAA==.',Ag='Agõny:BAAALAAECgMIAwAAAA==.',Ai='Ailuria:BAAALAAECgIIAgAAAA==.',Al='Alehoof:BAAALAADCgQIBwAAAA==.Alikith:BAAALAAECgIIAgAAAA==.',Am='Ambrìel:BAAALAADCggIDwAAAA==.Amethrandor:BAAALAAECgEIAQAAAA==.Amèlia:BAAALAAECgYICgAAAA==.',An='Angando:BAAALAADCggICgAAAA==.Anneliesë:BAAALAADCggIDQAAAA==.Antuco:BAAALAAECgYIDgAAAA==.',Ap='Apophis:BAAALAAECgUIBQAAAA==.',Ar='Arrows:BAAALAADCggIAQAAAA==.Artemidoros:BAAALAAECgMIBQAAAA==.',As='Ashkaari:BAAALAAECgYIDAAAAA==.',Au='Aursuna:BAAALAAECgMIBAAAAA==.',Az='Azu:BAAALAAECgEIAQABLAAECggIFgABABYkAA==.',Ba='Backerrz:BAAALAAFFAIIAgAAAA==.',Be='Beefbrownie:BAAALAAECgMIAwAAAA==.Berzerked:BAAALAAECgcIEgAAAA==.',Bi='Bigfluffbutt:BAAALAAECgEIAQAAAA==.Bigjimslade:BAAALAADCggICAABLAAECgcIEQACAAAAAA==.',Bl='Bluedknight:BAAALAADCgMIAwAAAA==.Bluethelock:BAAALAADCgMIAwABLAADCgMIAwACAAAAAA==.',Br='Brasa:BAAALAADCgcIDgAAAA==.Brejevol:BAAALAAECgIIBAAAAA==.Brejiboii:BAAALAADCggIDwABLAAECgIIBAACAAAAAA==.Brotherdread:BAAALAAECgUICAAAAA==.',Bu='Burningdruid:BAAALAAECgYIBgAAAA==.',Bw='Bwonsamdi:BAAALAAECgYICgAAAA==.',Ca='Calliopè:BAAALAADCgcIBwAAAA==.Calnaultenjr:BAAALAAECgYIDQAAAA==.Cannibella:BAAALAADCgcIBwAAAA==.',Ch='Chainhealz:BAAALAADCgEIAQAAAA==.Cheefqueef:BAAALAADCgQIBQAAAA==.',Cl='Cleth:BAAALAAECgIIAgAAAA==.',Co='Cochese:BAAALAADCgQIBAAAAA==.Connie:BAAALAAECgMIAwAAAA==.Cornpop:BAAALAAECgIIBAAAAA==.Cozyhunter:BAAALAADCgQICAAAAA==.',Da='Darksteldt:BAAALAADCggIDwAAAA==.Daydalus:BAAALAADCgYIBgAAAA==.',De='Deimös:BAAALAADCggIDAAAAA==.Demonnick:BAEBLAAECoEWAAMDAAgIIhrxFwA/AgADAAgIYBjxFwA/AgAEAAMI7BSVHACjAAAAAA==.Derazalth:BAABLAAECoEVAAIFAAgIShnHDgBXAgAFAAgIShnHDgBXAgAAAA==.',Di='Dillexis:BAAALAAECgYIDAAAAA==.',Do='Donald:BAAALAAECgUICAAAAA==.Doublea:BAAALAADCggIDgAAAA==.',Dr='Drac:BAAALAAECgIIBAAAAA==.Dragonchest:BAAALAAECgEIAQAAAA==.Dragonswolf:BAAALAAECgEIAQAAAA==.Draksil:BAAALAADCgcIDQAAAA==.Dregon:BAAALAAFFAIIAgAAAA==.Dreinara:BAAALAAECgEIAQAAAA==.Drunken:BAAALAADCgcIDgAAAA==.',Du='Dummysezwhut:BAAALAADCgcIDgAAAA==.',Eb='Ebrose:BAAALAADCggICQAAAA==.',Ei='Eilyn:BAAALAAECgEIAQAAAA==.',El='Elböw:BAAALAADCggICQABLAAECgcIDwACAAAAAA==.Elesis:BAAALAADCgQIBAAAAA==.Elssá:BAAALAADCgcIDgAAAA==.',Em='Emastoned:BAAALAADCgcIBwAAAA==.',Et='Ettal:BAAALAAECgIIBAAAAA==.Etti:BAAALAADCgYIBgAAAA==.',Ev='Evilpeachie:BAAALAADCgQIBAAAAA==.',Fa='Falfougin:BAAALAADCggICAAAAA==.Farelisan:BAAALAAECgMIBQAAAA==.Fayora:BAAALAAECgMIAwAAAA==.',Fe='Felnir:BAAALAADCggICgAAAA==.Felzwaz:BAAALAADCggIDwAAAA==.Fenasha:BAAALAADCgcIBwABLAAECgYIDAACAAAAAA==.Fenyo:BAAALAADCgcIBwAAAA==.',Fi='Fivebigbooms:BAABLAAECoEWAAMBAAgIFiT5AAA3AwABAAgIFiT5AAA3AwAGAAYIoCF4FgDaAQAAAA==.',Fl='Fluttershy:BAAALAADCgcIBwAAAA==.',Fu='Furryem:BAAALAAECgMIAwAAAA==.',Ga='Ganden:BAAALAADCggICAAAAA==.Gatelina:BAAALAAECgEIAQAAAA==.Gateto:BAAALAAECgMIBwAAAA==.',Ge='Genfinmonk:BAAALAADCgQIAgAAAA==.',Gi='Gimmli:BAAALAAECgYIDAAAAA==.',Gl='Glaivegazm:BAAALAADCgcIBwAAAA==.Glare:BAAALAADCgcICQAAAA==.',Ha='Harok:BAAALAAECgUIBQAAAA==.Hartley:BAAALAADCggICwAAAA==.Hawtpotato:BAABLAAECoEVAAIHAAgIvhq5EABKAgAHAAgIvhq5EABKAgAAAA==.',He='Hellravage:BAAALAADCggIGAAAAA==.Hellshaman:BAAALAADCgcIBwAAAA==.',Ho='Holeshot:BAAALAADCggIDgAAAA==.Holyfreya:BAAALAAECgEIAQAAAA==.Holylights:BAAALAADCgcIBwABLAAECgIIAgACAAAAAA==.Hooters:BAAALAAECgMIBQAAAA==.',Hu='Huntris:BAAALAAECgMIBQAAAA==.',Ir='Irim:BAAALAAECgYIBgAAAA==.',Ja='Jadedbabe:BAAALAADCgIIAgAAAA==.Jazzabell:BAAALAADCggIDwAAAA==.',Js='Jsn:BAAALAADCggIFQAAAA==.',['Jæ']='Jægerinde:BAAALAAECgYIDQAAAA==.',Ka='Kaiser:BAAALAADCggICAAAAA==.Kaniicus:BAAALAAECgEIAQAAAA==.Kansai:BAAALAADCggICAAAAA==.Karwl:BAAALAAECgEIAQAAAA==.',Ke='Keiry:BAAALAAECgcIDwAAAA==.',Kh='Khadgarjr:BAAALAADCgYIBgAAAA==.Khagoroth:BAAALAAECgEIAQABLAAECgYIBgACAAAAAA==.',Ki='Kickstarter:BAAALAADCgYIDAAAAA==.Kierana:BAAALAADCgcIDAAAAA==.Kiy:BAAALAAECgEIAQAAAA==.',Kn='Knìghtmare:BAAALAADCgIIAgAAAA==.',Ko='Korethral:BAAALAAECgEIAQAAAA==.Korosensei:BAAALAADCgcIBwABLAAECgYIDAACAAAAAA==.',Kr='Krakenyoheed:BAAALAAECgIIBAAAAA==.Krimsin:BAAALAAECgIIAgAAAA==.Kronas:BAAALAADCggIFAAAAA==.',Ku='Kumojoru:BAAALAADCgMIAwAAAA==.',['Kê']='Kêÿ:BAAALAAECggIEgAAAA==.',La='Lazyheal:BAAALAAECgYICQAAAA==.',Le='Leigor:BAABLAAECoEVAAIIAAgImiKhAgAaAwAIAAgImiKhAgAaAwAAAA==.',Li='Lionitus:BAAALAAECgUIBwAAAA==.',Lo='Looting:BAAALAADCggIDwAAAA==.Lovesteak:BAAALAAECgYIBwAAAA==.',Ma='Madds:BAAALAAECgIIBAAAAA==.Malvina:BAAALAAECgYIBgAAAA==.Managarmr:BAAALAADCgMIBAABLAABCgIIAgACAAAAAA==.Marohen:BAAALAADCgEIAQAAAA==.',Mc='Mcksquizy:BAAALAAECgcICwAAAA==.',Me='Meatsicle:BAAALAADCgUIBgAAAA==.',Mi='Mikedraven:BAAALAADCgcIBwAAAA==.Misaligned:BAAALAADCggICAAAAA==.Misidian:BAAALAAECgIIAgAAAA==.',Mo='Monkdarth:BAAALAAECgEIAQAAAA==.Moonsorrow:BAAALAAECgMIAwAAAA==.Moritura:BAAALAAECgIIAgAAAA==.',Mu='Muffin:BAAALAADCggICAAAAA==.',My='Mykana:BAAALAADCggICAAAAA==.Mythofsevin:BAAALAADCggIEAAAAA==.',Na='Nacirema:BAAALAADCggIDwAAAA==.Naklek:BAAALAAECgMIAwAAAA==.Nazal:BAAALAAECggICAAAAA==.',Ne='Netheryn:BAAALAADCggIDwAAAA==.',Ni='Nickoftime:BAEALAAECgEIAQABLAAECggIFgADACIaAA==.Nistik:BAAALAAECgMIBQAAAA==.',Ny='Nyxilis:BAAALAAECgcIDwAAAA==.',Op='Ophiuchus:BAAALAADCgYICAABLAADCggICgACAAAAAA==.',Os='Ostpeppar:BAAALAADCggIEAAAAA==.',Pa='Pamelina:BAAALAADCggICgAAAA==.Panzerfäust:BAAALAAECgYICAAAAA==.',Pe='Pernicious:BAAALAAECgIIAgAAAA==.',Ph='Phillis:BAAALAAECgMIBQAAAA==.',Pl='Plump:BAAALAAECgIIAgAAAA==.',Ps='Psychic:BAAALAAECgMIAwAAAA==.',Pv='Pvp:BAAALAADCgQIBAAAAA==.',Py='Pylonshots:BAAALAAECgYICAAAAA==.Pyria:BAAALAADCgcIDAAAAA==.',Qi='Qiyana:BAAALAAECgYIEQAAAA==.',Ra='Rathus:BAAALAAECggIDwAAAA==.',Re='Rebecca:BAAALAAECgMIBQAAAA==.Rebeka:BAAALAAECgMIAwABLAAECgMIBQACAAAAAA==.Ressie:BAAALAADCggIDQAAAA==.Reverendlion:BAAALAADCggICgAAAA==.',Rh='Rhllor:BAAALAADCgQIBQAAAA==.Rholan:BAAALAADCgMIAwAAAA==.',Ri='Rinsalem:BAAALAADCgUIBAAAAA==.',Rj='Rjhappeh:BAAALAAECgYIDQAAAA==.',Sa='Samdruid:BAAALAADCggICAAAAA==.Samwar:BAAALAAECgIIBAAAAA==.Samwield:BAABLAAECoEaAAMJAAcIYhQgFQDgAQAJAAcI2RIgFQDgAQAKAAYI/w7KCABmAQAAAA==.',Se='Seireitei:BAAALAAECgIIBAAAAA==.Selaheal:BAAALAAECgIIBAAAAA==.Serath:BAAALAAECgEIAQAAAA==.',Sh='Shamehameha:BAAALAADCgIIAgAAAA==.Shangdi:BAAALAADCgIIAgAAAA==.Shnood:BAAALAADCggIEQAAAA==.',Sk='Skadush:BAAALAAECgIIAgAAAA==.',Sl='Slivamane:BAAALAAECgEIAQAAAA==.',Sp='Spacebubby:BAAALAADCggICgAAAA==.',St='Standby:BAAALAAECgcICgAAAA==.Stepfist:BAAALAAECgYIDAAAAA==.Stormyknight:BAAALAAECgYIDgAAAA==.Strogenuoff:BAAALAAECgEIAQAAAA==.Stãerfaêste:BAAALAAECgEIAQAAAA==.',Su='Subwai:BAAALAAECgYICQAAAA==.Sukunå:BAAALAADCgMIAwAAAA==.Suswar:BAAALAADCggICAAAAA==.Suvulaan:BAAALAAECgUIBwAAAA==.',Sw='Swifix:BAAALAADCggIEwAAAA==.Swordsmyth:BAAALAADCgYIBgAAAA==.',Sy='Syntrope:BAAALAADCgUIBQAAAA==.Syravia:BAAALAAECgEIAQAAAA==.',Ta='Tatoo:BAAALAAECgcIEQAAAA==.',Te='Teo:BAAALAADCggICgAAAA==.',Th='Theriott:BAAALAAECgMIBgAAAA==.Thianá:BAAALAADCgcIDgAAAA==.Thiccnoodle:BAAALAADCggICAABLAAECgIIAgACAAAAAA==.Thunis:BAAALAAECgMIAwAAAA==.',Ti='Tinkerspell:BAAALAADCggICgAAAA==.',Tl='Tlitlitzin:BAAALAAECgEIAQAAAA==.',To='Toosus:BAABLAAECoEWAAILAAgI5yL0AQAQAwALAAgI5yL0AQAQAwAAAA==.Tootsiepop:BAAALAADCggICAAAAA==.Toridian:BAAALAAECgMIAwAAAA==.',Tt='Tturtle:BAAALAAFFAIIAgAAAA==.',Uh='Uhmm:BAAALAAECgYIDAAAAA==.',Un='Unsub:BAAALAAECgMIBQAAAA==.',Va='Valstad:BAAALAADCgcIBwAAAA==.Vandiirn:BAAALAAECgEIAQAAAA==.',Ve='Vedonna:BAAALAAECgMIBgAAAA==.Velluna:BAAALAADCgcICwAAAA==.Vezzena:BAAALAAECgQIBAAAAA==.',Vo='Voidedge:BAAALAAECgYICQAAAA==.Voidgazer:BAAALAADCggIGgAAAA==.',Vs='Vs:BAAALAAECgcIEQAAAA==.',Vy='Vyzeera:BAAALAAECgYIDAAAAA==.',Wa='Waterfaucet:BAAALAAFFAIIAgAAAA==.',Wi='Willybcastin:BAAALAAECgQIBgAAAA==.Willybwankin:BAACLAAFFIEFAAIMAAMI+BunAAAkAQAMAAMI+BunAAAkAQAsAAQKgRgAAwwACAjtJaAAAFcDAAwACAjtJaAAAFcDAA0AAQhSE8KKADIAAAAA.',Wo='Wolven:BAAALAADCgcICgAAAA==.Wowgazm:BAAALAAECgMIBgAAAA==.',Xa='Xaveri:BAAALAADCggIAwAAAA==.',Ya='Yawsnyx:BAAALAAECgEIAQAAAA==.',Yo='Yoshua:BAAALAADCgcIDgAAAA==.',Za='Zadok:BAAALAAECgEIAgAAAA==.Zalarian:BAAALAAECgQIBAAAAA==.Zarlokk:BAAALAADCgQIBAAAAA==.',Ze='Zemos:BAAALAADCgEIAQAAAA==.Zesdragon:BAAALAAECgEIAQAAAA==.Zeseroth:BAABLAAECoEWAAIOAAgIiyVmBAA8AwAOAAgIiyVmBAA8AwAAAA==.',Zy='Zyrok:BAAALAAECgMIBQAAAA==.',['Âs']='Âshê:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end