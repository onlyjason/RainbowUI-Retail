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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Frost','Priest-Shadow','Warrior-Fury','Paladin-Retribution','Evoker-Devastation','Rogue-Assassination','Rogue-Subtlety','Hunter-Survival',}; local provider = {region='US',realm='Executus',name='US',type='weekly',zone=44,date='2025-08-29',data={Ai='Aishana:BAAALAAECggICgAAAA==.',Aj='Ajin:BAAALAAECgcIEAAAAA==.',Al='Alabasterr:BAAALAADCggICAAAAA==.',An='Ando:BAAALAADCgIIAgABLAADCgcICAABAAAAAA==.Andryu:BAAALAAECgYICwAAAA==.Annikya:BAAALAADCggICAABLAADCggIEAABAAAAAA==.',Aq='Aquastar:BAAALAADCggICQAAAA==.',Ar='Arfor:BAAALAAECgYIDAAAAA==.Arïel:BAAALAAECgIIAwAAAA==.',Be='Becka:BAAALAAECgYICAAAAA==.',Bj='Björn:BAAALAADCgcIBwAAAA==.',Bo='Bonsai:BAAALAAECgEIAgAAAA==.',Br='Brandysavage:BAAALAADCgUIBwAAAA==.Broadfang:BAABLAAECoEXAAICAAgIaSORAwAyAwACAAgIaSORAwAyAwAAAA==.Broadwing:BAAALAAECgMIAwAAAA==.',Bu='Bullorly:BAABLAAECoEWAAIDAAgIxR/mDACyAgADAAgIxR/mDACyAgAAAA==.',Ca='Capriestsunn:BAAALAAECgYICQAAAA==.',Cl='Clickshot:BAAALAAECgYIDQAAAA==.Clipe:BAAALAADCgcICQAAAA==.Clipeskeg:BAAALAAECgYICwAAAA==.Clipey:BAAALAADCgIIAgAAAA==.Clove:BAAALAADCgYIBgAAAA==.',Co='Cobene:BAAALAADCgYIBgABLAADCgcIBAABAAAAAA==.Corben:BAAALAAECgEIAQAAAA==.',Cr='Crispifriied:BAAALAAECgMIAwAAAA==.',Cy='Cynîc:BAAALAAECgEIAQAAAA==.',Da='Darenas:BAABLAAECoEWAAIEAAgIkBpDDgBfAgAEAAgIkBpDDgBfAgAAAA==.Dasu:BAAALAAECgYICwAAAA==.',De='Deathkmikee:BAAALAADCgMIAwABLAAECgYICwABAAAAAA==.Deathmikee:BAAALAAECgYICwAAAA==.Deirdre:BAAALAAECgIIAgAAAA==.Demonix:BAAALAADCgMIAwAAAA==.Denari:BAAALAADCgcICAAAAA==.',Do='Doketerum:BAAALAAECgEIAQAAAA==.',Dr='Dracocide:BAAALAAECgYIAwABLAAFFAIIAwABAAAAAQ==.',Du='Durton:BAAALAAECgYICQAAAA==.',Ed='Edrency:BAAALAAECgIIAwAAAA==.',El='Elderdorje:BAAALAAECgYICwAAAA==.Elondre:BAAALAAECgYICgAAAA==.',Em='Employee:BAACLAAFFIEFAAIFAAMIiBbDAgATAQAFAAMIiBbDAgATAQAsAAQKgRYAAgUACAgLJOgDADQDAAUACAgLJOgDADQDAAAA.',Ev='Evangeliné:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Ex='Exavier:BAAALAAECgMIAwAAAA==.',Fe='Ferror:BAAALAAECgEIAQABLAAECgQICAABAAAAAA==.',Fn='Fntcvulcan:BAAALAADCgcIBwAAAA==.',Fo='Fortwooh:BAAALAADCggICAAAAA==.',Ga='Galatea:BAAALAAECgcIDwAAAA==.Galifen:BAAALAAECgYICwAAAA==.Gank:BAAALAAECgQIBwAAAA==.',Ge='Gelidon:BAAALAAECgQICAAAAA==.',Gh='Ghreen:BAAALAADCggICAAAAA==.',Gi='Gilgahmesh:BAAALAADCggIFQABLAAECgUIBwABAAAAAA==.',Gn='Gnomegrown:BAAALAAECgMIBQAAAA==.Gnrlvulcan:BAAALAADCggIDgAAAA==.',Go='Golden:BAAALAADCgYIBgAAAA==.',Gr='Grievér:BAAALAADCggIEAAAAA==.',Ha='Haera:BAAALAADCgEIAQAAAA==.Halyer:BAAALAAECgUICQAAAA==.Hamalainen:BAAALAAECgUICQABLAAECgcICgABAAAAAA==.',He='Helioboops:BAAALAADCgcICgAAAA==.',Ho='Hobbz:BAABLAAECoEYAAIGAAcIhB6aEACDAgAGAAcIhB6aEACDAgAAAA==.Hodge:BAAALAADCgYICgAAAA==.',Il='Illandros:BAAALAADCggIDwAAAA==.Ilovecougars:BAAALAADCgUICQAAAA==.',In='Invain:BAAALAAECgMIBAAAAA==.',Is='Isinia:BAAALAAECgMIAwAAAA==.',Ja='Janitor:BAAALAAECgEIAQAAAA==.',Ji='Jiren:BAAALAAECgcICgAAAA==.',Jo='Joran:BAAALAAECgEIAQAAAA==.',Ke='Kelekii:BAAALAADCgcIBAAAAA==.',Ko='Koduh:BAAALAADCggIDgAAAA==.',La='Lackluster:BAAALAAECgYICQAAAA==.',Le='Lenayuh:BAAALAADCgIIAgAAAA==.',Li='Liera:BAAALAAECgQIBQAAAA==.Lishau:BAAALAADCgcIBQAAAA==.',Lo='Longfist:BAAALAADCgcIBgAAAA==.',Lu='Luminå:BAAALAAECgYIDwAAAA==.',Ly='Lynx:BAAALAADCgUIBwAAAA==.',Ma='Maibisan:BAAALAAECgQICwAAAA==.Majick:BAAALAADCgIIAgAAAA==.Malificent:BAAALAAECgYICwAAAA==.Malighn:BAAALAAECgUIBwAAAA==.',Me='Meern:BAAALAAECggIEgAAAA==.',Mo='Moolight:BAAALAADCggICAAAAA==.Moonsliver:BAAALAADCgYIBgAAAA==.Morganä:BAAALAAECgMIBQAAAA==.',Na='Natryi:BAAALAAECgMIBAAAAA==.Nax:BAAALAAECgIIAgAAAA==.',Ni='Niccelndime:BAAALAAECgIIAgAAAA==.Nightski:BAAALAADCgcICQAAAA==.',No='Nobraincells:BAAALAAECgEIAQAAAA==.',Nv='Nvr:BAAALAAECgYIBwAAAA==.',Of='Offline:BAAALAAECggICAAAAA==.',Or='Orwasithim:BAAALAAECgIIAgAAAA==.',Pa='Pacs:BAAALAAECgMIAwAAAA==.',Pj='Pjxyo:BAAALAADCgcIDQAAAA==.',Po='Polyvoke:BAABLAAECoEWAAIHAAgIFA97EgDlAQAHAAgIFA97EgDlAQAAAA==.Portyou:BAAALAADCgMIAwAAAA==.',Qi='Qiller:BAAALAAECgEIAQAAAA==.',Ra='Radical:BAAALAAECgcICgAAAA==.Razius:BAAALAAECggICAAAAA==.',Re='Rebexha:BAAALAAECgEIAQAAAA==.Renatox:BAAALAAECgQIBwAAAA==.',Ro='Roxette:BAAALAAECgIIAgAAAA==.',Se='Selys:BAABLAAECoEVAAMIAAgIBh99CwBpAgAIAAgIjxp9CwBpAgAJAAQIeR7LCQBKAQAAAA==.Senorawr:BAAALAAECgQIBwAAAA==.Senosurprise:BAAALAADCgYIBgAAAA==.',Sh='Shasato:BAAALAAECgQICQAAAA==.Shazrast:BAAALAADCgYIBgAAAA==.',Sn='Snugwalnut:BAAALAAECgcIEAAAAA==.',So='Soejoedi:BAAALAADCgYICAABLAADCgcICAABAAAAAA==.',St='Stitchzpls:BAAALAADCgIIAgAAAA==.',Su='Sussanno:BAAALAADCgUICQAAAA==.',Ta='Tachi:BAAALAADCgcIDgAAAA==.Tazz:BAAALAADCggIEAAAAA==.',Th='Thanossnap:BAAALAADCgcICQABLAAECgYICwABAAAAAA==.Thejigga:BAAALAAECgUIBQAAAA==.Thelandlord:BAAALAADCgYIBgAAAA==.Thunderblast:BAAALAAECgEIAQAAAA==.Thuss:BAAALAADCgQIBgAAAA==.',Tr='Tris:BAAALAAECgYIBgAAAA==.',Tw='Twodini:BAAALAAECgEIAQAAAA==.',Va='Vander:BAAALAAECgEIAQAAAA==.Vayphear:BAAALAAECgYICAAAAA==.',Ve='Vexiæn:BAAALAADCgMIAwAAAA==.',Vi='Vizzax:BAAALAAECgYICQAAAA==.',Vo='Voklin:BAAALAAECgMIAwAAAA==.',We='Weezymage:BAAALAADCggIEAAAAA==.',Wi='Wildfire:BAABLAAECoEWAAIKAAgI+CYDAACtAwAKAAgI+CYDAACtAwAAAA==.',Wo='Wolfhammer:BAAALAAECgYICgAAAA==.Wolfmend:BAAALAAECgEIAQABLAAECgUICAABAAAAAA==.Wolfthorn:BAAALAAECgUICAAAAA==.',Xa='Xan:BAAALAAECgYICQAAAA==.',['Xê']='Xêndâr:BAAALAAECgMIAwAAAA==.',Yn='Yn:BAAALAAECgEIAQAAAA==.',Za='Zaia:BAAALAADCggICAAAAA==.Zandara:BAAALAAECgQIBQAAAA==.',['Zî']='Zîmìk:BAAALAAECgMIBQAAAA==.',['Às']='Àsh:BAAALAAECgYICQAAAA==.',['Év']='Évangeline:BAAALAAECgMIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end