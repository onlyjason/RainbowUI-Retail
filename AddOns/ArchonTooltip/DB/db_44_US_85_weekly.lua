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
 local lookup = {'Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Paladin-Retribution',}; local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Achillys:BAAALAADCgYICAAAAA==.',Al='Alcina:BAAALAAECgYICAAAAA==.Alys:BAAALAAECgEIAQAAAA==.',An='Annabellelee:BAAALAAECgMIBQAAAA==.',Ap='Apold:BAAALAAECgMIBAAAAA==.',Ar='Arathan:BAAALAADCgIIAgAAAA==.Arforias:BAAALAADCgcIBwAAAA==.Ariiana:BAAALAAECgMIAwAAAA==.',Au='Augmentor:BAAALAADCggICAAAAA==.Autharia:BAAALAAECgYIDQAAAA==.',Az='Azenserath:BAAALAAECgYICwAAAA==.',Ba='Barrii:BAAALAADCgMIAgAAAA==.',Be='Bellabelle:BAAALAADCgYIDQAAAA==.Betrayeres:BAAALAAECgIIAgAAAA==.',Bi='Biggiepants:BAAALAAECgUIBQAAAA==.Biggnome:BAAALAADCgEIAQABLAADCgMIAwABAAAAAA==.Bighead:BAAALAADCgMIAwAAAA==.Bintje:BAAALAADCgIIAgAAAA==.',Bl='Bloodwake:BAAALAADCggICAAAAA==.Blueivvy:BAAALAADCgMIAQAAAA==.',Bu='Burntisback:BAAALAAECgEIAQAAAA==.',Ce='Celds:BAAALAADCgQIBAABLAAECgYICAABAAAAAA==.',Ch='Chaichi:BAABLAAECoEUAAQCAAgIARPODQCqAQACAAcIFxHODQCqAQADAAcIvAl0FgBJAQAEAAMIvwrvGgBvAAAAAA==.Chaoz:BAAALAAECgIIAgAAAA==.Choggy:BAEALAAECgMIBQAAAA==.Chogs:BAEALAADCggIDwABLAAECgMIBQABAAAAAA==.',Ci='Cimbline:BAAALAADCggICAAAAA==.',Cl='Clairerick:BAAALAAECgIIAgAAAA==.',Co='Comegetpsalm:BAAALAADCgMIAwAAAA==.Confessionn:BAAALAADCgMIAwAAAA==.Conjurebeer:BAAALAAECgMIBwAAAA==.',Cr='Crinklecut:BAAALAAECgEIAQAAAA==.Crystilpixy:BAAALAADCggIDQAAAA==.',Da='Darizus:BAAALAADCgMIAwAAAA==.',De='Deadlychi:BAAALAAECgYICwAAAA==.Deadlyshift:BAAALAADCgcIDAABLAAECgYICwABAAAAAA==.Deadlystorm:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.Deadlywrath:BAAALAADCggICAABLAAECgYICwABAAAAAA==.Deadmenace:BAAALAAECgMIBAAAAA==.Deadspock:BAAALAAECgYIBwAAAA==.Delrok:BAAALAADCggIEwAAAA==.',Di='Diagnosis:BAAALAAECgYIBwAAAA==.Divine:BAAALAADCgUIBwAAAA==.',Do='Donnabb:BAAALAAECgMIBgAAAA==.',Dr='Draedis:BAAALAADCgYIBgAAAA==.Draelus:BAAALAAECgMIAwAAAA==.Dragoneye:BAAALAADCgEIAgAAAA==.Drakoil:BAAALAAECgMIBQAAAA==.Dreademperor:BAAALAADCggIDgAAAA==.Dreadnight:BAAALAADCggICgAAAA==.Dreadsorc:BAAALAADCgUIBQAAAA==.Dreadsteed:BAAALAADCgIIAgAAAA==.Dregg:BAAALAAECgUIBQAAAA==.Drenash:BAAALAAECgMIAwAAAA==.Drenish:BAAALAADCgIIAgAAAA==.Drenrah:BAAALAAECgYIBgAAAA==.Druxy:BAAALAADCgYIBwAAAA==.',['Dà']='Dàrthyodà:BAAALAADCggICAABLAAECgcIDAABAAAAAA==.',Ed='Edaddylock:BAAALAAECgMIAwAAAA==.Edgelörd:BAAALAADCggICAAAAA==.Edreth:BAAALAAECgIIAgAAAA==.',El='Elmorphius:BAAALAADCgUIBgAAAA==.',En='Enthalpy:BAAALAAECgMIBgAAAA==.Envy:BAAALAADCggICwAAAA==.',Es='Esperzoa:BAAALAAECgMIAwAAAA==.',Fa='Farde:BAAALAADCgEIAQABLAADCgMIAQABAAAAAA==.Fate:BAAALAADCgYICQAAAA==.',Fl='Floppydisc:BAAALAAECgcIEAAAAA==.',Fo='Forculus:BAAALAAECgMIAwAAAA==.Fordinn:BAAALAAECgMIAwAAAA==.',Ga='Galadren:BAAALAADCggIBwAAAA==.Garzhvog:BAAALAADCggICAABLAAECgcIDAABAAAAAA==.Gauteng:BAAALAAECgUICgAAAA==.',Gr='Grëzel:BAAALAAECgMIAwAAAA==.',Gu='Gummybear:BAAALAADCgUIBQAAAA==.',Ha='Hark:BAAALAAECgYICQAAAA==.Harpin:BAAALAADCgcIBwAAAA==.Harvin:BAAALAAECgMIBwAAAA==.',He='Healnshield:BAAALAADCgQIBgAAAA==.Hektobish:BAAALAADCgcICAAAAA==.',Hi='Hippopotamus:BAAALAADCgMIAgAAAA==.Hit:BAAALAADCggIDwAAAA==.',Ho='Holytide:BAAALAAECgMIBwAAAA==.',Hu='Hunger:BAAALAADCgcIDQAAAA==.',['Há']='Hárk:BAAALAADCggIDwAAAA==.',Ib='Ibaar:BAAALAAECggICQAAAA==.',Ic='Icialiaa:BAAALAADCgMIAwAAAA==.',Il='Iluma:BAAALAADCgMIAwABLAAECggICQABAAAAAA==.',In='Inno:BAAALAAECgYICQAAAA==.Inthewoods:BAAALAADCggICAAAAA==.',It='Ithacus:BAAALAADCggICAAAAA==.',Ja='Jandaar:BAAALAADCgMIAwAAAA==.',Je='Jestall:BAAALAAECgMIAwAAAA==.',Jo='Jorek:BAAALAAECgYICwAAAA==.',Ju='Juicyjen:BAAALAADCgYIBgAAAA==.',Ka='Kairae:BAAALAADCggICAAAAA==.Kairangi:BAAALAAECgYIBgAAAA==.Kardorand:BAAALAADCgYIBgAAAA==.Kazbodan:BAAALAAECgEIAQAAAA==.',Ke='Keemo:BAAALAADCgEIAQAAAA==.Keemosaki:BAAALAADCgYIBgAAAA==.Kehau:BAAALAADCgIIAgAAAA==.Kelash:BAAALAADCgcICAAAAA==.',Kh='Khaas:BAAALAAECgMIBwAAAA==.Khaleeb:BAAALAADCgUICAAAAA==.Kharvanna:BAAALAADCgcIBwAAAA==.',Ko='Kobeni:BAAALAAECgYICwAAAA==.Kookachoo:BAAALAAECgMIBAAAAA==.Korihor:BAAALAAECgMIAwAAAA==.Korison:BAAALAADCgcIBwAAAA==.',Ky='Kyndil:BAAALAAECgMIBAAAAA==.',La='Landreielea:BAAALAAECgEIAQAAAA==.',Le='Leafyboi:BAAALAADCgUIBQAAAA==.Leevoker:BAAALAAECgMIAwAAAA==.',Li='Licelyne:BAAALAAECgMIAwAAAA==.Liyara:BAAALAAECgUICgABLAAECgUICgABAAAAAA==.',Ll='Llorsa:BAAALAAECgMIBwAAAA==.',Lu='Luxian:BAAALAAECgUICAAAAA==.',['Lä']='Ländrei:BAAALAAECgEIAQAAAA==.',Ma='Magejones:BAAALAADCgcICwAAAA==.Maikagond:BAAALAADCgMIAQABLAAECgIIAgABAAAAAA==.Makaria:BAAALAAECgEIAQAAAA==.Maladic:BAAALAAECgMIAwAAAA==.Mandragora:BAAALAADCgMIAwAAAA==.',Mc='Mcgrowlin:BAAALAAECgYIDQAAAA==.',Mi='Mickey:BAAALAAECgYIEwAAAA==.Mikiik:BAAALAAECgMIBwAAAA==.Mildoo:BAAALAAECgYICQAAAA==.Milkymoo:BAAALAADCggICAAAAA==.Millina:BAAALAADCggIDgABLAAECgEIAQABAAAAAA==.',Mo='Monq:BAAALAAECgYICQAAAA==.Morithus:BAAALAAECgMIBQAAAA==.Moón:BAAALAADCgIIAgAAAA==.',Mu='Murdrmittens:BAAALAADCgcIBwAAAA==.',Na='Naofummi:BAAALAADCgEIAQAAAA==.Narus:BAAALAADCggICwABLAAECgMIAwABAAAAAA==.',Ne='Neeston:BAAALAAECgMIBAAAAA==.Neltharidan:BAAALAADCgUIBQAAAA==.Neodin:BAAALAAECgEIAQAAAA==.Nephadin:BAAALAAECgYICQAAAA==.Neviaa:BAAALAAECgYICgAAAA==.',Ni='Nickypoo:BAAALAADCgMIAgAAAA==.',No='Nothealster:BAAALAAECgYIBwAAAA==.',Ny='Nyxaria:BAAALAADCggIFwAAAA==.',Ob='Obsidion:BAAALAADCggICgABLAAECgMIAwABAAAAAA==.',Ol='Oliviamoon:BAAALAADCgIIAgAAAA==.',On='Onlyfangs:BAAALAAECgMIBQAAAA==.',Op='Operian:BAAALAADCgcIDQABLAAECgYICAABAAAAAA==.',Pa='Padivyn:BAAALAAECgYIDAAAAA==.',Po='Pozufuma:BAAALAAECgMIBgAAAA==.',Ps='Psychomantis:BAAALAAECgYICQAAAA==.',Ra='Ragingnads:BAAALAADCgYICQAAAA==.Ragner:BAAALAADCgYICgAAAA==.Raknaron:BAAALAADCggICAAAAA==.',Re='Reddington:BAAALAADCggIDwAAAA==.Redscööter:BAAALAAECgMIBgAAAA==.Rey:BAAALAAECgYICwAAAA==.',Ri='Ristvakbaen:BAAALAAECgcIDAAAAA==.',Ro='Robynlee:BAAALAADCggICAABLAAECgcIEQABAAAAAA==.Rohini:BAAALAADCgcIBwAAAA==.',Sa='Sammylammy:BAAALAADCgcIBwAAAA==.',Sc='Sceryna:BAAALAADCggICAABLAAECggIFAACAAETAA==.Scrmndemn:BAAALAAECgMIBgAAAA==.',Se='Sepviva:BAAALAADCgEIAQAAAA==.Serea:BAAALAAECgcIEQAAAA==.',Sh='Shakolat:BAAALAAECgMIBAAAAA==.Shamadeus:BAAALAADCggIDQABLAAECgcIDAABAAAAAA==.Shambutgood:BAAALAAECgYICAAAAA==.Shewhoruns:BAAALAADCggIFwAAAA==.Shikita:BAAALAAECgMIBAAAAA==.Shimadin:BAABLAAECoEVAAIFAAgImyE4DAC/AgAFAAgImyE4DAC/AgAAAA==.Shimvoker:BAAALAAECgMIAwABLAAECggIFQAFAJshAA==.Shipsu:BAAALAADCgcIDgAAAA==.Shmerek:BAAALAAECgYICwAAAA==.',Si='Sinners:BAAALAADCgYIBgAAAA==.',Sk='Skeith:BAAALAAECgYIEAAAAA==.',Sm='Smidyy:BAAALAADCgcIDAAAAA==.',So='Solbin:BAAALAADCgcIDgAAAA==.Solitudé:BAAALAADCggICgAAAA==.Soteirian:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.',St='Staphyloco:BAAALAAECgEIAQAAAA==.',Su='Supereclipse:BAAALAAECgMIBwAAAA==.',Sy='Sydvicious:BAAALAAECgYICQAAAA==.',Ta='Tanesong:BAAALAADCgcIDwAAAA==.',Te='Tecks:BAAALAAECgYICwAAAA==.',Th='Thathealguy:BAAALAADCgMIAwAAAA==.Thefreeman:BAAALAADCgcICgAAAA==.Theinovan:BAAALAAECgMIAwAAAA==.Then:BAAALAADCgMIAgAAAA==.Thiarap:BAAALAAECgMIAwAAAA==.Thrain:BAAALAAECgIIAgAAAA==.Threat:BAAALAAECgYIDAAAAA==.',Ti='Tiamaat:BAAALAAECgYICwAAAA==.Tinysanta:BAAALAADCgcIBwAAAA==.',Tj='Tjorvi:BAAALAADCggIDwAAAA==.',Tr='Trout:BAAALAAECgYICwAAAA==.',Tu='Tungus:BAAALAAECgMIAwABLAAECgYIDQABAAAAAA==.',Ty='Tygras:BAAALAADCggIDwAAAA==.Tyletos:BAAALAAECgIIAgAAAA==.',Ur='Uriél:BAAALAAECgYICQAAAA==.',Va='Valerius:BAAALAADCggIDwAAAA==.Vandaris:BAAALAADCggICAAAAA==.',Ve='Veiler:BAAALAAECgYIBwAAAA==.Vellus:BAAALAADCggICwAAAA==.Veruca:BAAALAADCgMIAwAAAA==.Veviseron:BAAALAAECgYICQAAAA==.',Vi='Vinstalation:BAAALAAECgQIBAAAAA==.',Vo='Vonbismarck:BAAALAAECgMIBgAAAA==.',Vr='Vritraz:BAAALAAECgMIBwAAAA==.',We='Wendypini:BAAALAAECgYICQAAAA==.',Wi='Wildestdream:BAAALAAECgEIAQAAAA==.',Wu='Wudeeps:BAAALAAECgcIEAAAAA==.',Wy='Wyncæstr:BAAALAADCgYIBgAAAA==.',Ye='Yennefer:BAAALAADCggIDwAAAA==.',Ze='Zedisdead:BAAALAADCgMIBAAAAA==.',Zo='Zodiaac:BAAALAAECgYICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end