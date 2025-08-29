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
 local lookup = {'Unknown-Unknown',}; local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=44,date='2025-08-29',data={Ai='Airoh:BAAALAADCgUICgAAAA==.',Am='Amellwind:BAAALAADCggIDwAAAA==.',An='Anga:BAAALAADCgYICAAAAA==.',Ar='Ariosto:BAAALAAECgYICQAAAA==.Arkkeon:BAAALAAECgYICQAAAA==.',Ay='Ayrwen:BAAALAADCggIFwAAAA==.',Ba='Badgerbadger:BAAALAAECgQIBQAAAA==.Bagelqt:BAAALAADCgYIBgAAAA==.Battletank:BAAALAAECgMIBAAAAA==.',Be='Beatrixx:BAAALAADCggICwAAAA==.',Bl='Blackfeet:BAAALAAECgUIBQAAAA==.Bllackout:BAAALAAECgYICgAAAA==.Bloodhardt:BAAALAADCgEIAQAAAA==.Bluekoolaid:BAAALAAECgYICgAAAA==.',Bu='Butters:BAAALAADCgIIAgAAAA==.',Ch='Cheba:BAAALAAECgMIBAAAAA==.Chesleigh:BAAALAADCgcIEQAAAA==.',Co='Coffeecream:BAAALAAECgMIBAAAAA==.Coldncrispy:BAAALAADCgYIBgAAAA==.Corrupt:BAAALAADCgcICwABLAAECgYICQABAAAAAA==.Corvell:BAAALAAECgYICQAAAA==.',Cr='Crilynn:BAAALAAECgYIEgAAAA==.Crivet:BAAALAADCggIEwAAAA==.',Cy='Cyssor:BAAALAADCgYICQAAAA==.Cyvoid:BAAALAADCgcICgAAAA==.',Da='Dancingfox:BAAALAADCgcIEQAAAA==.Darkfly:BAAALAADCgMIBAAAAA==.Darkníght:BAAALAAECgIIAgAAAA==.Darktimês:BAAALAADCgUIBQAAAA==.Dathcure:BAAALAAECgMIAwAAAA==.Davlindhag:BAAALAADCgcIBwAAAA==.',De='Demonhunted:BAAALAAECgMIBAAAAA==.Demonhuntris:BAAALAADCgMIAwAAAA==.Demonsfall:BAAALAADCgMIAwAAAA==.',Di='Dillapuss:BAAALAADCgYICAAAAA==.Dimensius:BAAALAADCggIEAABLAAECgUIBwABAAAAAA==.',Do='Docteaux:BAAALAAECgMIAwAAAA==.Dotdotded:BAAALAADCgcIBwAAAA==.',Dr='Dragonkiller:BAAALAAECgMIBAAAAA==.',El='Elleath:BAAALAADCggICAAAAA==.',Eo='Eo:BAAALAAECgIIAwAAAA==.',Er='Ertzul:BAAALAADCgcIDgAAAA==.',Fe='Fertvert:BAAALAADCgQIBAAAAA==.',Fi='Fiercealexis:BAAALAADCgIIAgAAAA==.',Fl='Flamingpax:BAAALAADCgcICQAAAA==.Floin:BAAALAAECgYICQAAAA==.Fluffinbaked:BAAALAADCgQIBAABLAAECgEIAQABAAAAAA==.Fluffinhigh:BAAALAAECgEIAQAAAA==.Fluffybúnny:BAAALAADCgcIEQAAAA==.',Ga='Gargorg:BAAALAAECgYICgAAAA==.Gathle:BAAALAADCgUICgAAAA==.',Gl='Glasc:BAAALAAECgMIAwAAAA==.',Go='Gortolomew:BAAALAADCgUIBQABLAAECgYICgABAAAAAA==.',Gr='Gregiruma:BAAALAADCggIDgABLAAECgYICgABAAAAAA==.Grimfur:BAAALAADCggIDQAAAA==.',Gy='Gyslaen:BAAALAAECgMIAwAAAA==.',Ha='Hadurzen:BAAALAAECgMIAwAAAA==.',He='Hesitant:BAAALAAECgIIAgAAAA==.',Hi='Highgreen:BAAALAADCgMIAwAAAA==.',Ho='Hoptoad:BAAALAADCgcIBwAAAA==.',Hu='Hurt:BAAALAADCggICgABLAAECgUIBwABAAAAAA==.',In='Incision:BAAALAAECgYIDgAAAA==.Inyourmuffin:BAAALAADCgMIAwAAAA==.',It='Itzli:BAAALAAECgYICQAAAA==.',Ja='Jayquellin:BAAALAAECgMIAwAAAA==.',Jo='Jojen:BAAALAAECgMIBAAAAA==.Jorj:BAAALAAECgYICQAAAA==.',Ju='Judgerrnut:BAAALAAECgMIBAAAAA==.',Ka='Katrex:BAAALAADCgcIEQAAAA==.Kavix:BAAALAAECgMIBAAAAA==.Kayos:BAAALAAECgYIDAAAAA==.',Ke='Kelzen:BAAALAAECgMIBAAAAA==.',Kh='Khalock:BAAALAAECgYIDAAAAA==.',Ki='Kimarah:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.',Ko='Kohle:BAAALAADCgQIBAAAAA==.Kortin:BAAALAADCgUIBQAAAA==.',Ku='Kula:BAAALAAECgMIAwAAAA==.',Ky='Kylewithac:BAAALAADCgcIEgAAAA==.Kyraes:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.',La='Latro:BAAALAADCggIFgABLAAECgUIBwABAAAAAA==.',Le='Leginerz:BAAALAAECgMIAwAAAA==.Lepo:BAAALAAECgMIBAAAAA==.',Lo='Lochnessy:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.Lortharon:BAAALAADCgIIAgAAAA==.',Lu='Luisbn:BAAALAAECgMIAwAAAA==.Lunden:BAAALAAECgMIBAAAAA==.Lupus:BAAALAADCgEIAQAAAA==.Luvalee:BAAALAADCgcICwAAAA==.',Ma='Magnusthered:BAAALAAECgMIBAAAAA==.Maladroit:BAAALAADCgMIAwABLAAECgYICQABAAAAAA==.Maldus:BAAALAAECgYICQABLAAECgYICQABAAAAAA==.Manimul:BAAALAADCgIIAgAAAA==.Marina:BAAALAAECgMIBAAAAA==.Marloke:BAAALAADCgcIEgAAAA==.',Me='Merrymanalow:BAAALAADCgcICAAAAA==.Metamucil:BAAALAADCgIIAgAAAA==.',Mo='Molez:BAAALAAECggIBQAAAA==.Morblodplez:BAAALAAECgMIAwAAAA==.',Mu='Murvadin:BAAALAADCggIIgAAAA==.Murvinator:BAAALAADCgQIBAABLAADCggIIgABAAAAAA==.',My='Mysticmurv:BAAALAADCgIIBAABLAADCggIIgABAAAAAA==.',['Mà']='Mày:BAAALAADCgIIAgAAAA==.',Ne='Necronamacon:BAAALAADCgQIBQABLAADCgcICQABAAAAAA==.Nessy:BAAALAAECgMIAwAAAA==.',Ni='Nicksamurai:BAAALAAECgMIBAAAAA==.',Ol='Oldrellik:BAAALAADCggICAAAAA==.',Om='Ombos:BAAALAAECgYICQAAAA==.',Or='Ortinchi:BAAALAADCggIEwAAAA==.',Ph='Pheldorai:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Phelinthria:BAAALAAECgYICQAAAA==.',Pr='Property:BAAALAAECgcIEAAAAA==.Protector:BAAALAAECgUIBwAAAA==.',Pu='Puma:BAAALAAECgMIAwAAAA==.Puregreen:BAAALAADCgcIBwAAAA==.Purpleme:BAAALAADCgMIAwAAAA==.',Ra='Raelinn:BAAALAAECgMIAwAAAA==.Raevynn:BAAALAAECgcIDwAAAA==.Raiinzen:BAAALAAECgMIBAAAAA==.Rasälghul:BAAALAADCgEIAQAAAA==.Razelda:BAAALAADCgcICwAAAA==.Razelka:BAAALAAECgMIBgAAAA==.',Re='Rededagain:BAAALAADCgQIBAAAAA==.Rentetsuken:BAAALAAECgYIDwAAAA==.Research:BAAALAADCgcICgAAAA==.',Ro='Rozco:BAAALAAECgYIBgAAAA==.',Ru='Rubmywolf:BAAALAAECgMIAwAAAA==.',Sa='Sadguy:BAAALAADCgMIAwAAAA==.Salad:BAAALAAECgMIAwAAAA==.',Se='Sela:BAAALAADCgcICAAAAA==.',Sh='Shamtastic:BAAALAADCgMIAwAAAA==.Shrub:BAAALAADCgcIDgAAAA==.',Si='Sid:BAAALAAECgYICQAAAA==.',So='Sophié:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Sorwyn:BAAALAAECgEIAQAAAA==.Soupcatcher:BAAALAAECgMIBAAAAA==.',Sp='Spike:BAAALAADCgcIDgABLAAECgUIBwABAAAAAA==.Sprout:BAAALAAECgMIAwAAAA==.',St='Starlost:BAAALAADCgcIEgAAAA==.Starsdruid:BAAALAADCgMIAwAAAA==.',Su='Suelock:BAAALAAECgMIAwAAAA==.Suldes:BAAALAADCgMIBgABLAADCgcICwABAAAAAA==.',Ta='Taali:BAAALAAECgMIAwAAAA==.Tarrant:BAAALAADCgUICQAAAA==.',Te='Telloh:BAAALAAECgcIDgAAAA==.Tequilas:BAAALAADCgUIBQAAAA==.Termtu:BAAALAAECgIIAgAAAA==.Terrificus:BAAALAADCgUIBQAAAA==.',Th='Thankful:BAAALAAECggIDAAAAA==.Thomasten:BAAALAAECgQIBQAAAA==.Thomasthree:BAAALAAECgIIAgABLAAECgQIBQABAAAAAA==.',Tr='Tranquil:BAAALAADCggIFQABLAAECgUIBwABAAAAAA==.Treemendus:BAAALAADCgcICwAAAA==.',Tu='Tuckinfank:BAAALAADCgcIBgAAAA==.',Ty='Tyreus:BAAALAADCgQIBAAAAA==.',['Tã']='Tãrvil:BAAALAAECgMIBAAAAA==.',Ut='Utopea:BAAALAAECgIIAgAAAA==.',Va='Vanillacream:BAAALAAECgMIBAAAAA==.',Ve='Velzerd:BAAALAAECgUIBQAAAA==.Verelia:BAAALAADCgEIAQAAAA==.',Vi='Viddar:BAAALAAECgMIAwAAAA==.',Vo='Voidhuntress:BAAALAADCgcIDgAAAA==.Voltamore:BAAALAADCgMIAwABLAADCgcICQABAAAAAA==.',Wi='Winkle:BAAALAADCgcIEQAAAA==.',Wo='Woralaz:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.',Wy='Wyll:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.',Xa='Xarava:BAAALAAECgMIBAAAAA==.',Za='Zarhanna:BAAALAADCgYIBgAAAA==.',Ze='Zenogias:BAAALAADCgcICAAAAA==.',Zo='Zombieshaman:BAAALAAECgYIDgAAAA==.',['Ña']='Ñameless:BAAALAADCggICwAAAA==.',['ße']='ßenzyte:BAAALAADCgUICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end