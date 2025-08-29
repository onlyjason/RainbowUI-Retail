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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Mage-Frost',}; local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aeladrel:BAAALAADCgcICQAAAA==.',Ag='Agulin:BAAALAADCggIDwAAAA==.',Ak='Akirie:BAAALAADCgcIEgAAAA==.Akumua:BAAALAADCgMIAwABLAAECgYIEAABAAAAAA==.',Al='Albsygos:BAAALAADCggIDwAAAA==.Aldebar:BAAALAADCgUIBQAAAA==.Aldien:BAAALAADCgcICwAAAA==.Aleister:BAAALAAECgYICwAAAA==.Alerandish:BAAALAADCgUIBQAAAA==.',An='Andil:BAAALAAECgEIAQAAAA==.Andyplayzyt:BAAALAADCgIIAgAAAA==.Annicon:BAAALAAECgYICAAAAA==.',Ar='Arienna:BAAALAAECgEIAQAAAA==.Arteñ:BAAALAADCgEIAQAAAA==.',As='Aslaan:BAAALAADCgQIAgAAAA==.Astraldruid:BAAALAADCgcIBwAAAA==.',At='Attitudyjudy:BAAALAADCgEIAQAAAA==.',Ba='Banegrim:BAAALAAECgUIBgAAAA==.',Be='Beefypaladin:BAAALAADCggIDgAAAA==.Belysiuh:BAAALAAECgEIAQAAAA==.',Bi='Bigcow:BAAALAADCgcIBwAAAA==.',Bl='Blindwalker:BAAALAAECgcIEAAAAA==.Blissfuleigh:BAAALAADCgcIDgAAAA==.',Br='Brewfest:BAAALAADCgcICgAAAA==.',Ca='Candymanfu:BAAALAADCggICAAAAA==.Caromangus:BAAALAADCgYIBgAAAA==.Castigate:BAAALAAECgEIAQAAAA==.',Ch='Cheesepally:BAAALAAECgYICwAAAA==.Cheesewhelp:BAAALAAECgQIBQAAAA==.Chensoman:BAAALAADCgYIBwABLAADCggICQABAAAAAA==.Chewbåcca:BAAALAADCgMIAwAAAA==.Chong:BAAALAAECgIIAgAAAA==.',Co='Coconut:BAAALAADCgYIBgAAAA==.Cold:BAAALAADCgEIAgAAAA==.Corgus:BAAALAADCggIEAAAAA==.',Cr='Crathis:BAAALAADCggICQAAAA==.Crittoriss:BAAALAADCgcIBwAAAA==.Crosyphilis:BAAALAADCggICwAAAA==.',Cy='Cyanide:BAAALAAECgYIBgAAAA==.Cymburleigh:BAAALAADCgYIBgABLAADCgcIDgABAAAAAA==.',Da='Daddywarbuks:BAAALAADCggIDQAAAA==.Dagin:BAAALAADCgcIBwAAAA==.Dagny:BAAALAADCgUIBQAAAA==.',Dc='Dcomposing:BAAALAADCgYIBgAAAA==.',De='Deathman:BAAALAAECgYICAAAAA==.Deathsdevice:BAAALAADCgEIAQAAAA==.Denasrogue:BAAALAAECgMIAwAAAA==.Denaswar:BAAALAADCggICAAAAA==.',Di='Dirtydrago:BAAALAADCggIEwAAAA==.',Do='Dominhoes:BAAALAADCggICQAAAA==.',Dr='Druzzaj:BAAALAADCggIEAAAAA==.',Ec='Echoez:BAAALAADCggIDwAAAA==.',Ef='Effirie:BAAALAADCggICAABLAAECgYICAABAAAAAA==.',Ej='Ejreborn:BAAALAADCggIDQAAAA==.',El='Eliplan:BAAALAADCgMIAwABLAAECgMIBwABAAAAAA==.',Fa='Fantastic:BAAALAAECgcIEAAAAA==.Fartwizard:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.',Fi='Findonlok:BAAALAADCggIEQAAAA==.Fire:BAAALAADCgYIBgAAAA==.',Fl='Flakwaz:BAAALAADCggIDQAAAA==.Fleur:BAAALAAECgYIBgAAAA==.',Ga='Gabethelock:BAAALAADCgUIBQAAAA==.',Gl='Gloomy:BAAALAADCggIDwAAAA==.',Gr='Grandclap:BAAALAAECgYIDAAAAA==.Grandmeta:BAAALAADCggICQAAAA==.Grippybunz:BAAALAADCgUIBQAAAA==.',Gu='Gungoa:BAAALAAECgYICAAAAA==.Gunthar:BAAALAADCgYIBgAAAA==.',Ha='Hambonine:BAAALAADCgMIAwAAAA==.Hannsolo:BAAALAADCgIIAgAAAA==.Hasted:BAAALAAECgYIBwAAAA==.',He='Heldarram:BAAALAAECgYICQAAAA==.Hellalust:BAAALAAECgIIAgAAAA==.Hemaroid:BAAALAADCgcICAAAAA==.',Ho='Hotsforthots:BAAALAAECgMIBQAAAA==.',Hr='Hrizul:BAAALAAECgMIBQAAAA==.',Ja='Jagerz:BAAALAAECgYICAAAAA==.',Ji='Jirenman:BAAALAADCggIEAAAAA==.',Jo='Johntrabolta:BAAALAAECgIIAgAAAA==.Jonsi:BAAALAAECgYICgAAAA==.',Ju='Juniper:BAAALAAECgEIAQAAAA==.',Ka='Katamine:BAAALAAECgMIBwAAAA==.Katoz:BAAALAAECgMIBAAAAA==.',Ki='Kielex:BAAALAADCgUIBQAAAA==.Killnall:BAAALAAECgIIAgAAAA==.Kiyohime:BAAALAAECgEIAQAAAA==.',Kl='Kladon:BAAALAAECgYICQAAAA==.',Kr='Krystarin:BAAALAAECgIIAgAAAA==.Kráytos:BAAALAADCggIFQAAAA==.',Ku='Kurodh:BAAALAADCggICAAAAA==.',Ky='Kynria:BAAALAAECgYIBgAAAA==.',Li='Life:BAAALAADCgcICwAAAA==.Liferips:BAAALAADCgcICAAAAA==.Lightbullb:BAAALAADCgUIBgAAAA==.Likhalo:BAAALAAECgYIBgAAAA==.Littlezo:BAAALAAECggIDgAAAA==.',Lo='Lonelymage:BAAALAADCgYIBgAAAA==.',Lu='Luflew:BAAALAADCgIIAgAAAA==.',Ma='Mahduriel:BAAALAAECgYICAAAAA==.Maiko:BAAALAADCgcIBwAAAA==.Makoha:BAAALAAECgIIAgAAAA==.',Me='Meathéad:BAAALAADCgcICwAAAA==.',Mo='Modelotime:BAAALAAECgMIBAAAAA==.Moops:BAAALAAECgMIBAAAAA==.Mordacity:BAEALAADCggIDwAAAA==.',Na='Nalth:BAAALAADCgMIAgAAAA==.Namí:BAAALAADCgcIBwAAAA==.Nara:BAAALAADCggICQAAAA==.',Ni='Nikos:BAAALAAECgMIBwAAAA==.',No='Nordikmage:BAAALAADCgcICwAAAA==.',['Nü']='Nüclear:BAAALAAECgMICAABLAAECgYIBwABAAAAAA==.',Pa='Pallypower:BAAALAAECgYICAAAAA==.Panthro:BAAALAAECgYIEAAAAA==.',Pi='Pinkylove:BAAALAAECgcIEAAAAA==.',Pn='Pnda:BAAALAAECgEIAQAAAA==.',Po='Positivity:BAAALAAECgEIAQAAAA==.',Pr='Promathia:BAEALAAECggIEAAAAA==.Proxi:BAAALAAECgYICQAAAA==.',Pu='Puff:BAAALAADCggICwAAAA==.',Ra='Rangërdangër:BAAALAAECgcIDAAAAA==.Rat:BAAALAAECgcIDQAAAA==.',Re='Redrouges:BAAALAAECgUICAAAAA==.Rendo:BAAALAADCgEIAQABLAAECgYIBgABAAAAAA==.',Ru='Ruekh:BAAALAADCggIFQABLAAECgQIBAABAAAAAA==.',Sa='Sandrider:BAAALAADCgIIAQAAAA==.Sanity:BAAALAADCgcICwAAAA==.Sathia:BAAALAADCgcICwABLAADCgcIBwABAAAAAA==.',Se='Seaursus:BAAALAADCggIDwAAAA==.Seerblade:BAAALAADCgYIBgAAAA==.',Sh='Shadowbann:BAAALAAECgEIAQAAAA==.Shocktheclit:BAAALAADCgMIAwAAAA==.Shortrage:BAAALAADCgEIAQABLAADCgUIBQABAAAAAA==.Shortzo:BAAALAAECgYICQABLAAECggIDgABAAAAAA==.Shÿtstorm:BAAALAAECgMIBAAAAA==.',Si='Sigmachad:BAAALAAECgIIAgAAAA==.Sizzlore:BAAALAADCgYIBgAAAA==.',Sm='Smallwood:BAAALAADCgYICQAAAA==.',Sn='Sneakay:BAAALAAECgYICAAAAA==.',So='Southernways:BAAALAADCggIDwAAAA==.',Sq='Squigglybutt:BAAALAAECgIIAwAAAA==.',St='Stranger:BAAALAADCgEIAQAAAA==.',Su='Sungchaluka:BAAALAAECgIIAgAAAA==.Sunsett:BAAALAADCgIIAgAAAA==.',Sw='Sway:BAAALAAECgEIAQAAAA==.',Ta='Talsomething:BAAALAAECgMIBQAAAA==.Tannari:BAAALAADCggIDQAAAA==.Tars:BAAALAADCgcIBwAAAA==.Tats:BAAALAAECgIIAwAAAA==.',Te='Terthaith:BAAALAAECgYICAAAAA==.',Th='Thedru:BAAALAAECgUIBwAAAA==.Throdwran:BAAALAAECgUICAABLAADCgcIBwABAAAAAA==.',To='Toohbooh:BAEALAAECgEIAQAAAA==.',Tr='Tranqx:BAAALAAECgYIDwAAAA==.Treva:BAAALAAECgcIEAAAAA==.',Tw='Twistedfells:BAAALAADCggICAAAAA==.',Ty='Typhonn:BAAALAADCgcICAAAAA==.',Up='Uproar:BAAALAAECgcIDQAAAA==.',Va='Valfei:BAAALAADCgcIBwABLAAECggIGQACAP4lAA==.Valfy:BAABLAAECoEZAAMCAAgI/iXQAQBeAwACAAgI/iXQAQBeAwADAAEIjR5oQAA/AAAAAA==.Valisera:BAAALAAECgMICAAAAA==.',Ve='Vellinamun:BAAALAADCggIDwAAAA==.Venture:BAAALAAECgMIAwAAAA==.Vescovo:BAAALAAECgIIBAAAAA==.',Vo='Vodyanoi:BAAALAAECgcIEAAAAA==.Voltage:BAAALAADCgEIAQAAAA==.',Wa='Warunoshi:BAAALAADCgYIBgABLAAECgYIEAABAAAAAA==.Wasson:BAAALAADCgQIBAAAAA==.',We='Wegetituvape:BAAALAADCgcIBwAAAA==.',Wi='Wingback:BAAALAADCggIDAAAAA==.Wispaway:BAAALAADCgIIAgABLAADCgYIBgABAAAAAA==.',Wp='Wphoenix:BAAALAAECgIIAgAAAA==.',Wr='Wrathian:BAAALAADCggIEQAAAA==.',Wt='Wtfsteve:BAAALAADCggICAAAAA==.',Xa='Xanus:BAAALAAECgMIAwAAAA==.',Xh='Xhenshini:BAAALAAECgcIEAAAAA==.',Za='Zalethe:BAAALAADCggIDQAAAA==.',Zo='Zombaè:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end