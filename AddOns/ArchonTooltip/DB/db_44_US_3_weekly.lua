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
 local lookup = {'Unknown-Unknown','Warrior-Fury','Mage-Frost','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Warlock-Demonology','DeathKnight-Blood','Monk-Brewmaster','Priest-Shadow','Rogue-Assassination',}; local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Accursed:BAAALAADCgcIBwAAAA==.',Ad='Adareyna:BAAALAAECgcIDgAAAA==.',Ae='Aegrias:BAAALAAECggIDAAAAA==.Aerithel:BAAALAAECgEIAQAAAA==.Aerodria:BAAALAAECgcIEQAAAA==.',Ak='Akeno:BAAALAAECgcIDgAAAA==.',An='Annå:BAAALAADCggICAABLAAECgcIEQABAAAAAA==.',Ar='Arachnae:BAAALAAECgMIAwAAAA==.Arfor:BAAALAADCggIDwAAAA==.',As='Ashton:BAAALAADCggIDwAAAA==.',Au='Aurvandil:BAAALAAECgEIAQAAAA==.',Az='Azala:BAAALAADCgcIBwAAAA==.Azzy:BAABLAAECoEWAAICAAgItiJ0BQAWAwACAAgItiJ0BQAWAwAAAA==.',Ba='Barkeep:BAAALAAECgYIDAAAAA==.Bassham:BAAALAADCgEIAQABLAAECgYICAABAAAAAA==.Bassoon:BAAALAAECgYICAAAAA==.',Be='Beefs:BAAALAADCgQIBAAAAA==.',Bi='Billshat:BAAALAAECggIEQAAAA==.',Bl='Blitzy:BAAALAADCgQIBAAAAA==.Blobknight:BAAALAAECgEIAgAAAA==.Blobpally:BAAALAADCgYIBgAAAA==.',Bo='Boogfloog:BAAALAADCgcIDAAAAA==.Bookofmoon:BAAALAAECgIIAwAAAA==.Bothenheim:BAAALAAECgYIBwAAAA==.',Br='Brüisér:BAAALAAECgYICAAAAA==.',Bu='Bubbles:BAAALAAECgcIBwAAAA==.',By='Byucknah:BAAALAADCggIEAAAAA==.',Ca='Caylen:BAAALAAECgcIDgAAAA==.',Ce='Centri:BAABLAAECoEYAAMDAAgILyXKAABgAwADAAgILyXKAABgAwAEAAEIXwLkcwAvAAAAAA==.',Ch='Chicknorris:BAAALAAECgcIDwAAAA==.',Cl='Clahowd:BAAALAAECgYICAABLAAECgYICAABAAAAAA==.Cleverlev:BAAALAAECgEIAQAAAA==.',Cr='Crixa:BAAALAADCggICgAAAA==.Cruellev:BAAALAAECgUIBQAAAA==.',Cu='Cuttyflam:BAAALAAECgMIBgAAAA==.',Cz='Czernobog:BAAALAADCgUIBQAAAA==.',Da='Daeland:BAAALAAECgMIAwAAAA==.Dalsham:BAAALAAECgQIDwAAAA==.Danta:BAAALAADCgcIBwAAAA==.Darkrai:BAAALAADCgYIBgAAAA==.',De='Deathsgrace:BAAALAADCggIBwAAAA==.Deimos:BAAALAAECgMIBQAAAA==.Demeter:BAAALAAECgcIDgAAAA==.Demonicrav:BAABLAAECoEVAAMFAAgIbxZ2FAAcAgAFAAcIyxV2FAAcAgAGAAMI9wxCFgDUAAAAAA==.',Dj='Djtotem:BAAALAADCgcIBwAAAA==.',Dp='Dpsrogue:BAAALAAECgIIAgAAAA==.',Dr='Dracolyte:BAAALAAECgYICAAAAA==.Draynorr:BAAALAADCgEIAQAAAA==.',El='Eliheals:BAAALAADCgYIBgAAAA==.Elmdor:BAAALAADCggICAAAAA==.',Em='Emylie:BAAALAAECgEIAQAAAA==.',Er='Erazena:BAAALAADCgcIDQAAAA==.',Es='Estrella:BAAALAAECgEIAQAAAA==.',Ev='Evilwitch:BAAALAADCgYICgAAAA==.Evvie:BAAALAADCgYIBgABLAAECggIGAADAC8lAA==.',Ex='Excentric:BAAALAADCgYIBgABLAAECggIGAADAC8lAA==.Exertian:BAAALAADCgYIBgABLAAECggIGAADAC8lAA==.',Ez='Ezindeth:BAAALAADCggIEwAAAA==.',Fa='Fartimus:BAAALAADCgEIAQAAAA==.',Fe='Fearious:BAAALAAECgcIDQAAAA==.Feimai:BAAALAADCgMIAwAAAA==.Felfart:BAAALAADCgEIAQAAAA==.',Fl='Flayer:BAAALAAECgcIDgAAAA==.',Fo='Foss:BAAALAADCgIIAgAAAA==.',Fr='Fraternite:BAAALAADCggIHAAAAA==.Fruto:BAAALAADCgEIAQAAAA==.',Ga='Gartuckle:BAAALAADCgcIBwAAAA==.',Ge='Gerzarnzul:BAAALAADCggICAAAAA==.',Gi='Giterdonee:BAABLAAECoEVAAICAAgIGxvIDQCGAgACAAgIGxvIDQCGAgAAAA==.',Go='Goblinbeans:BAABLAAECoEWAAIHAAgIqhxdCgBvAgAHAAgIqhxdCgBvAgAAAA==.',Gr='Gremolesto:BAAALAADCgcIBwAAAA==.Griningent:BAAALAAECgEIAQAAAA==.Gripfunkle:BAAALAAECgEIAQAAAA==.',Ha='Hadoker:BAAALAADCggIEAAAAA==.Hammerthumb:BAAALAAECgQIBQAAAA==.Hathemagi:BAAALAADCggIEQAAAA==.',Hu='Hulkbuster:BAAALAADCgEIAQAAAA==.',Hy='Hyara:BAABLAAECoEWAAIIAAgI/BBZGAAbAgAIAAgI/BBZGAAbAgAAAA==.',['Hû']='Hûntard:BAAALAAECgYIEAAAAA==.',Il='Ilganurh:BAAALAAECggICAAAAA==.',Ir='Irooh:BAAALAAECgQIBgAAAA==.',Ja='Jackston:BAAALAAECgcIDgAAAA==.Jacopo:BAABLAAECoEUAAMJAAYIygu8FQBUAQAJAAYIaAq8FQBUAQAKAAMIyARGeQBnAAAAAA==.',Jo='Jordi:BAAALAAECgMIBgAAAA==.Jorry:BAAALAADCgMIAwAAAA==.',Ka='Kanree:BAABLAAECoEWAAILAAgIcBESCwDlAQALAAgIcBESCwDlAQAAAA==.',Ke='Kek:BAAALAAECgUIBwAAAA==.',Ki='Kinnagh:BAAALAAECgcIDgAAAA==.',Kn='Knucklesammy:BAAALAAECggICAAAAA==.',Ko='Korxin:BAABLAAECoEVAAIIAAgIER29CwCnAgAIAAgIER29CwCnAgAAAA==.',Ku='Kusharys:BAAALAADCgcIBwAAAA==.',Le='Levitticus:BAAALAADCggICQAAAA==.',Li='Liale:BAAALAAECgEIAQAAAA==.Linqi:BAAALAADCgEIAQAAAA==.',Lo='Lohgan:BAAALAADCggIEAAAAA==.Lovetrapq:BAAALAAECgIIAwAAAA==.',Lu='Lulak:BAAALAAECgEIAQAAAA==.Lull:BAAALAAECgIIAgAAAA==.Luxia:BAAALAADCgcIBwAAAA==.',Ly='Lydarasia:BAAALAAECgEIAQAAAA==.',Ma='Magidragon:BAAALAADCggICgAAAA==.',Me='Melt:BAABLAAECoEWAAMFAAgIPyNCBwDcAgAFAAgICyJCBwDcAgAMAAQI2iIDIgALAQAAAA==.Meowmix:BAAALAAECgUICAAAAA==.Metons:BAAALAADCggICQAAAA==.',Mi='Michael:BAABLAAECoEbAAQFAAgIWiWLAQBfAwAFAAgIWiWLAQBfAwAMAAYIwhhYEACDAQAGAAIIARd2GgCrAAAAAA==.Mike:BAEBLAAECoEVAAIGAAgI9CNSAABYAwAGAAgI9CNSAABYAwAAAA==.Miroslav:BAAALAADCgQIBQAAAA==.Misfitdk:BAAALAADCgEIAQAAAA==.',Mo='Mommon:BAAALAAECgEIAQAAAA==.Monkeydead:BAAALAAECgYICAAAAA==.',Na='Naminé:BAAALAADCgYICgAAAA==.Naughtynewt:BAAALAAECgMIAwAAAA==.',Ne='Nemoz:BAAALAAECgYIDQAAAA==.Neryssa:BAABLAAECoEVAAMFAAgIeCIeCADMAgAFAAgIDSEeCADMAgAMAAUIIxcQHAAwAQAAAA==.',Ni='Nibrastraz:BAAALAAECgUIBQAAAA==.Nik:BAAALAADCgMIAwAAAA==.',No='Nocter:BAABLAAECoEVAAQGAAgIgB/tAAD4AgAGAAgIdB/tAAD4AgAFAAMImyLJNwAAAQAMAAEI6x+vRABOAAAAAA==.Noktur:BAAALAADCggIBQAAAA==.Nonameyo:BAAALAADCgcICAAAAA==.Noqtir:BAAALAADCgcICQAAAA==.',Ny='Nymura:BAAALAAECgMIAwAAAA==.',Oa='Oakhugger:BAAALAADCggICAABLAAECgQIBQABAAAAAA==.',Ol='Oldeone:BAAALAADCgYICAAAAA==.',Om='Omgega:BAAALAAECgIIAgAAAA==.',On='Onimeek:BAAALAAECgcIEAAAAA==.',Op='Optìmus:BAAALAAECgMIAwAAAA==.',Or='Oryn:BAAALAAECgcIEQAAAA==.',Pa='Pallywahwah:BAAALAAECgEIAQAAAA==.Pandazuko:BAAALAADCgMIAwAAAA==.Pandussy:BAAALAADCgcIDAAAAA==.Paper:BAAALAAFFAEIAQAAAQ==.',Pe='Peacefullev:BAABLAAECoEUAAILAAcIIyAWBgBpAgALAAcIIyAWBgBpAgAAAA==.Pelagius:BAAALAADCgIIAgAAAA==.Penelopea:BAAALAADCggICAAAAA==.',Ph='Phantomthief:BAAALAADCgcICwAAAA==.',Pi='Pictureplane:BAAALAADCgcIAgAAAA==.',Po='Pootatoo:BAAALAAECgIIAgAAAA==.',['Pé']='Pépega:BAAALAAECgMIAwAAAA==.',Qu='Quinny:BAAALAADCgYICQAAAA==.',Re='Redeemedlev:BAAALAADCgUIBAAAAA==.',Ri='Rixin:BAEBLAAECoEWAAMJAAgIICM4AgDxAgAJAAgIICM4AgDxAgANAAIIYw9aGgBhAAAAAA==.',Ro='Rokom:BAAALAAECggIEQAAAA==.',Ru='Runed:BAAALAAECgYICgAAAA==.',Sa='Saebella:BAAALAAECgUICQAAAA==.Saluuknir:BAAALAAECgYICAAAAA==.',Se='Selleck:BAAALAADCgEIAQAAAA==.',Sh='Shaddoot:BAAALAAECgIIAgAAAA==.Shauray:BAAALAADCgUIBQAAAA==.Shortpally:BAAALAAECgYIDQAAAA==.',Si='Sipz:BAAALAADCgcICgAAAA==.',Sl='Slingshotz:BAAALAAECgcIDwAAAA==.',So='Solari:BAAALAAECgcIEAAAAA==.Solia:BAAALAADCgYIBgAAAA==.Solvy:BAAALAADCgYIDAAAAA==.Sophiagraze:BAAALAAECggICQAAAA==.Sophispapa:BAAALAAECggICQAAAA==.',St='Starlighter:BAAALAAECgYICAAAAA==.Starsomave:BAAALAADCgEIAQABLAAECgYICAABAAAAAA==.Stinkylev:BAAALAADCgcIDAAAAA==.Stormrider:BAAALAAECgQIBQAAAA==.',Sw='Swyft:BAAALAADCggIDwAAAA==.',Ta='Taehausx:BAACLAAFFIEFAAIOAAMIzxp1AQD8AAAOAAMIzxp1AQD8AAAsAAQKgRcAAg4ACAj6I2QBAC4DAA4ACAj6I2QBAC4DAAAA.Taraka:BAAALAAECgYICgAAAA==.',Te='Tehmilkman:BAAALAADCgUIBQAAAA==.',Th='Thauriel:BAAALAADCgYIBgAAAA==.Theexecution:BAAALAAECgMIAwAAAA==.Thorgadin:BAAALAADCgUIBQAAAA==.Thraggh:BAAALAADCgYIBwAAAA==.',Ti='Timeprayer:BAAALAADCggIFAAAAA==.Titania:BAAALAADCgIIAgABLAAECgYIDAABAAAAAA==.',To='Toecurlin:BAAALAADCgMIAwAAAA==.Toesnatcher:BAAALAAECgYICQAAAA==.Toothsayer:BAAALAAECggICQAAAA==.',Ty='Tynita:BAAALAADCggIDQAAAA==.',Ub='Ubeltater:BAAALAAECgIIAgAAAA==.',Ug='Uggogobbo:BAAALAAECgYICAAAAA==.',Um='Umbrainc:BAAALAAECgMIBgAAAA==.',Un='Unholylord:BAAALAADCgUIBQABLAAECggIFQAPAPYjAA==.Unholymisfit:BAAALAADCgEIAgAAAA==.',Ur='Uriel:BAAALAADCgYIBgAAAA==.',Us='Usha:BAAALAADCgEIAQAAAA==.',Ve='Vela:BAAALAADCgMIAwAAAA==.Velissavia:BAABLAAECoEYAAIQAAgIOyJKAwATAwAQAAgIOyJKAwATAwAAAA==.Vengefullev:BAAALAADCgQIBAAAAA==.',We='Weeblewoble:BAAALAAECgEIAQAAAA==.',Xi='Xilbalbá:BAAALAAECgYIBwAAAA==.',Yo='Yomah:BAAALAAECgEIAQAAAA==.',Za='Zarrona:BAAALAAECgEIAQAAAA==.',Ze='Zeta:BAAALAADCggICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end