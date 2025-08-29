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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Frost',}; local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=44,date='2025-08-29',data={Al='Alucarde:BAAALAAECgIIAgAAAA==.',Ba='Bastas:BAAALAAECgcIDQAAAA==.',Be='Beefyy:BAAALAADCgQIBAAAAA==.Beekro:BAAALAAECgcIEAAAAA==.Belatink:BAAALAAECgcIEgAAAA==.',Bi='Bilando:BAAALAAECgcIDgAAAA==.',Bl='Blueberry:BAAALAAFFAEIAQAAAA==.',Bo='Borden:BAAALAAECgMIBAAAAA==.',Bu='Busher:BAAALAADCggIFQAAAA==.',Ca='Cactoo:BAAALAAECgEIAQAAAA==.Calaart:BAAALAAECgMIBAAAAA==.',Ch='Chainer:BAAALAAECgcIEAAAAA==.',Da='Daelen:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.',De='Dedgret:BAAALAADCgYIBwAAAA==.Denarron:BAAALAAECgcIEAAAAA==.Dezarke:BAAALAADCggIDgAAAA==.',Do='Dolt:BAAALAAECgYIDwAAAA==.Doomer:BAAALAADCggIDQAAAA==.',Dr='Drezzarnbez:BAAALAADCggIDwAAAA==.',Du='Durgrim:BAAALAAECgcIEAAAAA==.',Ed='Edine:BAAALAADCggICAAAAA==.',Ee='Eeèva:BAAALAADCggIDAAAAA==.',Ef='Efah:BAAALAADCggIEgABLAADCggIFQABAAAAAA==.',Ek='Ekko:BAAALAADCggICAAAAA==.',En='Enslay:BAAALAAECgMIAwABLAAECgcIDQABAAAAAA==.',Ev='Evokin:BAAALAAECgEIAQAAAA==.',Fa='Faithh:BAAALAAECgEIAQAAAA==.',Ga='Gaartak:BAAALAADCgIIAgABLAAECgcIEAABAAAAAA==.Garurumon:BAAALAADCgcIBwAAAA==.Gawrgura:BAAALAADCggICAAAAA==.',Ge='Geg:BAAALAADCgcIBwAAAA==.',Gh='Ghogrim:BAAALAAECgcIDgAAAA==.',Gi='Girlypop:BAAALAADCggICQAAAA==.Githdk:BAAALAADCggICgAAAA==.Githon:BAAALAADCgcIBgAAAA==.Githpriest:BAAALAAECgQIBAAAAA==.',Go='Goatcheese:BAAALAADCgIIAgABLAAECgMIBAABAAAAAA==.',Gr='Grogrin:BAAALAAECgYIDwAAAA==.',Ha='Harlíequinn:BAAALAADCggIDgAAAA==.',He='Herms:BAAALAAECgEIAQAAAA==.',Hi='Him:BAAALAADCgQIBAAAAA==.Himiko:BAAALAADCgQIBAAAAA==.',Ho='Hologrin:BAAALAADCgcICgAAAA==.Hontu:BAAALAADCgUIBQABLAADCggIFQABAAAAAA==.Horelock:BAAALAADCgcIBwABLAAECggIGQACAOYgAA==.Hotsytotsy:BAAALAADCggIFQAAAA==.Houtoku:BAAALAAECgYIBgAAAA==.',Il='Illidanmello:BAAALAAECgcIEgAAAA==.',Im='Imkrispy:BAAALAADCgQIBAAAAA==.Imtrying:BAAALAAECgcIEgAAAA==.',Ja='Jasnah:BAAALAAECgMIBAAAAA==.',Je='Jessïe:BAAALAAECgEIAQAAAA==.',Jo='Jothnir:BAAALAADCgUIBQAAAA==.',Ka='Kagome:BAAALAADCgEIAQAAAA==.Katbelle:BAAALAAECgcIEQAAAA==.',Ke='Keynallan:BAAALAADCggIDgAAAA==.Keynlor:BAAALAADCgUIBQABLAAECgcIDgABAAAAAA==.',Ki='Kinkykelly:BAABLAAECoEZAAICAAgI5iAdBwAOAwACAAgI5iAdBwAOAwAAAA==.',Ku='Kuroishi:BAAALAADCggICAAAAA==.',La='Lahar:BAAALAADCgcIBwABLAAECgcIDwABAAAAAA==.Lalalan:BAAALAADCgcIBgABLAAECgcIEAABAAAAAA==.Lalavo:BAAALAADCgcICAAAAA==.',Le='Leof:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.',Li='Litlam:BAAALAAECgIIAgAAAA==.',Lo='Locrock:BAAALAAECgQIBQAAAA==.Loxsmith:BAAALAADCgcIBwABLAADCggIEAABAAAAAA==.',Lt='Ltcclover:BAAALAADCggIDgAAAA==.',Ly='Lyssandra:BAAALAADCgcIBwAAAA==.',Ma='Mageywagey:BAAALAADCggIDgAAAA==.Main:BAAALAAECgMIAwAAAA==.Maize:BAAALAAECgMIBAAAAA==.Manatree:BAAALAADCgcIBgAAAA==.Mayalaran:BAAALAAECgMIBAAAAA==.',Me='Merikaya:BAAALAAECgcIBwAAAA==.',Mi='Mipaladin:BAAALAAECgMIAwAAAA==.Mistafridge:BAAALAADCggIEAAAAA==.',Mo='Moocelee:BAAALAADCggIDwAAAA==.',Mu='Murk:BAAALAAECgIIAgAAAA==.',Na='Nano:BAAALAADCggICAABLAADCggIEAABAAAAAA==.Nanome:BAAALAADCgcIBgABLAADCggIEAABAAAAAA==.',Nh='Nhaszul:BAAALAAECgcIEgAAAA==.',Nv='Nvious:BAAALAAECgMIBAAAAA==.',Ny='Nyvara:BAAALAAECggIBgAAAA==.',Ow='Owlbread:BAAALAAECgMIBAAAAA==.',Pa='Paulwallace:BAAALAADCggIDAABLAAECggIEgABAAAAAA==.',Pe='Peccator:BAAALAAECgcIDwAAAA==.',Pg='Pgw:BAAALAAECgYICgAAAA==.',Ph='Phatality:BAAALAADCggICAAAAQ==.',Pi='Pizzarolls:BAAALAAECgUIBQAAAA==.',Pk='Pkfire:BAAALAADCgYIBgAAAA==.',Pl='Platsearthen:BAAALAADCggICAAAAA==.Ploo:BAAALAAECgEIAQAAAA==.',Pr='Praeisidium:BAAALAAECgEIAQABLAAECgcIDwABAAAAAA==.',Re='Rebyen:BAAALAADCgQIBAAAAA==.',Ri='Riskante:BAAALAAECgcIDQAAAA==.',Ro='Rosehip:BAAALAADCgcIBgABLAAECgcIEAABAAAAAA==.Rosey:BAAALAAECgcIEAAAAA==.Rozey:BAAALAADCggICAAAAA==.',Sh='Shalltear:BAAALAADCggIEQAAAA==.Shaluestaa:BAAALAAECgMIBQAAAA==.Shalundraa:BAAALAADCgEIAQAAAA==.Shamtreyu:BAAALAAECgIIAgAAAA==.Shanithell:BAAALAADCgIIAgAAAA==.Shanksx:BAAALAADCgMIAwAAAA==.',Si='Sicklecell:BAAALAAECgIIAgAAAA==.Sins:BAABLAAECoEVAAIDAAgIACJfBAAsAwADAAgIACJfBAAsAwAAAA==.',Sn='Sneakyhand:BAAALAAECgcIEgAAAA==.',So='Soupson:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.',St='Stealthan:BAAALAAECggIEgAAAA==.',Su='Supden:BAAALAAECgQIBAAAAA==.',Sy='Sylvi:BAAALAAECgMIBAAAAA==.',Ta='Takitsu:BAAALAAECgcIEAAAAA==.Tatp:BAAALAADCgUIBQAAAA==.',Th='Thedoctor:BAAALAAECgYICgAAAA==.Theguy:BAAALAADCgUIBAAAAA==.',Ti='Tired:BAAALAADCgIIAgAAAA==.',To='Towa:BAAALAADCggIDwAAAA==.',Ug='Ughwarrior:BAAALAAECgMIAwAAAA==.',Ur='Uroboros:BAAALAAECgMIAwAAAA==.Ursa:BAAALAAECgYICAAAAA==.',Ve='Veil:BAAALAAECgIIAgAAAA==.',Wa='Wallê:BAAALAADCggICAAAAA==.Wallë:BAAALAADCgcIBwAAAA==.',We='Wetasscat:BAAALAAECgIIAwAAAA==.',['Xë']='Xëna:BAAALAADCgMIAgABLAADCggIFQABAAAAAA==.',Ya='Yakoot:BAAALAADCgUIBQAAAA==.',Za='Zargus:BAAALAAECgcICAAAAA==.Zarlunce:BAAALAAECgYICwAAAA==.',Ze='Zetsuon:BAAALAAECgYIDwAAAA==.',['Èr']='Èrza:BAAALAADCgMIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end