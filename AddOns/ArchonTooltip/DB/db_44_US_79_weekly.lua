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
 local lookup = {'Druid-Feral','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship',}; local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaronius:BAAALAADCggIEAAAAA==.',Ad='Adoe:BAAALAAECgIIAwAAAA==.',Ag='Agaliarept:BAAALAADCggIDAAAAA==.Agathosia:BAAALAADCgQIBAAAAA==.',Ai='Aidenator:BAAALAAECgIIAwAAAA==.',Ak='Akkah:BAAALAAECgIIAwAAAA==.',Al='Alger:BAAALAADCggICAAAAA==.Algorithm:BAAALAAECgIIAwAAAA==.Allbert:BAAALAADCgIIAgAAAA==.',An='Angelneko:BAAALAAECgMIAwAAAA==.',As='Asterior:BAABLAAECoEUAAIBAAgI8Rn9AwCNAgABAAgI8Rn9AwCNAgAAAA==.',Au='Auroraa:BAAALAADCgYIBgAAAA==.',Az='Azmodeaz:BAAALAADCgcIGQAAAA==.',Ba='Babaorca:BAAALAADCgIIAgAAAA==.Bajapanti:BAAALAAECgMIBwAAAA==.Banchory:BAAALAADCgcIBwAAAA==.Bandaron:BAAALAADCgcIBwAAAA==.Baxstab:BAAALAAECgYICgAAAA==.',Be='Belladeon:BAAALAAECgIIAgAAAA==.',Bi='Billysmolts:BAAALAAECgMIAwAAAA==.',Bl='Blackpatch:BAAALAAECgMIBwAAAA==.Blooming:BAAALAAECgEIAQAAAA==.',Bo='Bonusevoker:BAAALAAECgMIAwAAAA==.Booneboy:BAAALAAECgMIAwAAAA==.Boonique:BAAALAADCggIDwAAAA==.Boreassiel:BAAALAADCgEIAQAAAA==.Botemedel:BAAALAADCgYIBgABLAAECgMIAwACAAAAAA==.',Br='Brennor:BAAALAAECgYICgAAAA==.Brewslunt:BAABLAAECoEUAAIDAAgI2xqCBQCAAgADAAgI2xqCBQCAAgAAAA==.',Ca='Cabbagehunt:BAAALAADCgcICwAAAA==.Caffpow:BAAALAAECgIIAwAAAA==.Caiya:BAAALAADCgUIBQABLAAECgMIBwACAAAAAA==.Caratou:BAAALAAECgQIBAAAAA==.Carl:BAABLAAECoEUAAIEAAgI2x8lAwDCAgAEAAgI2x8lAwDCAgAAAA==.Cartman:BAAALAADCgcIBwAAAA==.Carvil:BAAALAAECgYICgAAAA==.',Ce='Celaris:BAAALAAECgIIBAAAAA==.Celisa:BAAALAADCgcIBwABLAAECgIIBAACAAAAAA==.',Ch='Charisma:BAAALAAECgYIDAAAAA==.Charmcaster:BAAALAAECgYICgAAAA==.Charîzard:BAAALAAECgcICwAAAA==.Chipp:BAAALAAECggIDwAAAA==.Chleo:BAAALAADCgEIAQAAAA==.Choco:BAAALAAECgYIEgAAAA==.',Co='Coggler:BAAALAAECgEIAQAAAA==.',Cu='Curmudge:BAAALAAECgMIBAAAAA==.Curveball:BAAALAADCgcIDgABLAAECgMICAACAAAAAA==.',Cy='Cyaani:BAAALAADCgEIAQAAAA==.',Db='Dbring:BAAALAADCgIIAgAAAA==.',De='Deathball:BAAALAAECgMIBwAAAA==.Deathstars:BAAALAADCgcIDgAAAA==.Delritha:BAAALAAECgMIAwAAAA==.Deluzion:BAAALAADCgIIAgAAAA==.Demaratus:BAAALAAECgMIAwAAAA==.Demonagent:BAEALAAECgIIAgABLAAECgIIAgACAAAAAA==.Despaladian:BAAALAADCggIDAAAAA==.Desrogue:BAAALAAECgUIBgAAAA==.',Di='Dippindotz:BAAALAAECgEIAQABLAAECgQIBAACAAAAAA==.',Dm='Dmarvs:BAAALAADCgUIBQABLAAECgEIAQACAAAAAA==.',Do='Dookiehouser:BAAALAADCgYIBgAAAA==.Doombuggy:BAAALAADCgUIBQAAAA==.Dornoch:BAAALAADCgYICgAAAA==.Dottyhotty:BAAALAADCgcIBwAAAA==.',Dr='Dragonflaco:BAAALAAECgIIAgAAAA==.Dreadnight:BAAALAADCgQIBAAAAA==.Dremon:BAAALAAECgIIAwAAAA==.Drew:BAAALAAECgIIAwAAAA==.Drhkillinger:BAEALAAECgIIAgAAAA==.',El='Elakuma:BAAALAADCgIIAgAAAA==.Elessaria:BAAALAAECgMIAwAAAA==.Elfatheàrt:BAAALAADCggIDAAAAA==.Elisyan:BAAALAADCgIIAwAAAA==.Ellenna:BAAALAADCgcIBwAAAA==.Elsen:BAAALAADCggIBwAAAA==.',Es='Estherras:BAAALAAECgIIAwAAAA==.',Ez='Ezarath:BAAALAAECgYICwAAAA==.',Fa='Faience:BAAALAAECgIIAwAAAA==.',Fe='Feardotrun:BAAALAAECgMIAwAAAA==.Felicious:BAAALAADCgYIBwAAAA==.Felora:BAAALAAECgYICwAAAA==.Felune:BAAALAADCgMIAwAAAA==.',Fi='Finally:BAAALAADCgYICgAAAA==.Fizzbanger:BAAALAAECgEIAQAAAA==.',Fl='Floorior:BAAALAADCggIBwAAAA==.',Fo='Folgers:BAAALAADCgcIDgAAAA==.',Fr='Frostbight:BAAALAAECgEIAQAAAA==.Frostied:BAAALAAECgEIAQAAAA==.',Fu='Futnuraz:BAAALAADCgQIBAAAAA==.',Fy='Fyrakkobama:BAAALAAECgYICwAAAA==.Fyriat:BAAALAAECgIIAwAAAA==.',Ga='Gazardiel:BAAALAADCgYIBgAAAA==.',Go='Goldstorm:BAAALAAECgIIAwAAAA==.Goliath:BAAALAADCgcIDgAAAA==.',Gr='Graythers:BAAALAADCgcICQAAAA==.Grimfelborn:BAAALAAECgcIDgAAAA==.',Ha='Haggo:BAAALAADCggICAABLAAECggIDwACAAAAAA==.Hairylarry:BAAALAAECgIIAwAAAA==.Hammerhead:BAAALAADCgMIAwAAAA==.Hanoverfiste:BAAALAADCgcIBwABLAADCgcIBwACAAAAAA==.Hapsburg:BAAALAAECgYICgAAAA==.Harrytongue:BAAALAADCgYICQAAAA==.Havince:BAAALAAECgYICgAAAA==.',He='Hercboyy:BAAALAAECgUIBQAAAA==.Hersheeys:BAAALAAECgMIAwAAAA==.',Hi='Higgs:BAAALAADCgUIBgAAAA==.',Ho='Hollyna:BAAALAAECgMIAwAAAA==.',['Hê']='Hêra:BAAALAADCgIIAgAAAA==.',Il='Illidai:BAAALAADCggIEAAAAA==.',It='Ithea:BAAALAAECggIAwAAAA==.',Ja='Jamjar:BAAALAAECgIIAwAAAA==.',Je='Jeffha:BAAALAAECgUICQAAAA==.',Jo='Joejr:BAAALAAECgMIBQAAAA==.Jof:BAAALAAECgcIDQAAAA==.',Jw='Jwise:BAAALAADCgEIAQAAAA==.',Ka='Kalaziel:BAAALAADCgQIBAAAAA==.Kalierix:BAAALAAECgYIDgAAAA==.Karaden:BAAALAADCgcIDgAAAA==.Katrishy:BAAALAAECgcIDgAAAA==.',Ke='Keedrid:BAAALAAECgYIBgAAAA==.Keiselshaman:BAAALAAECgIIAgAAAA==.Kelemenohpea:BAAALAAECgMIAwAAAA==.Kelsie:BAEALAADCggIEwAAAA==.',Kk='Kkthanx:BAAALAADCgcIBwAAAA==.',Kr='Kreeona:BAAALAAECgMIBwAAAA==.',Ky='Kyarlen:BAAALAAECgMIAwAAAA==.',['Kí']='Kíkí:BAAALAADCgEIAgAAAA==.',Le='Legacy:BAAALAADCgYIBgAAAA==.Legendàiry:BAAALAAECgEIAQAAAA==.Legreecast:BAAALAADCgQIBAAAAA==.Leskovar:BAAALAADCgQIBAAAAA==.',Li='Liathos:BAAALAADCggICgAAAA==.Litheliice:BAAALAAECgYICgAAAA==.',Lo='Loboc:BAAALAADCgUIBQAAAA==.Lodur:BAAALAAECgIIAwAAAA==.Lonen:BAAALAAECgIIAwAAAA==.Losat:BAAALAAECgMIBwAAAA==.Lovegoddess:BAAALAADCgcIBwAAAA==.',Lu='Luguna:BAAALAADCggIDwAAAA==.Lursk:BAAALAAECgIIAwAAAA==.Luthian:BAAALAAECgcIDAAAAA==.',Ma='Macarthur:BAAALAAECgMIBwAAAA==.Mackkie:BAAALAAECgMIAwAAAA==.Madonkadonk:BAAALAAECgYIBwAAAA==.Magrog:BAAALAADCgMIAwAAAA==.Malacadaver:BAAALAADCggIEgAAAA==.Maldive:BAAALAAECgMIBwAAAA==.Mallicia:BAAALAAECgYICQAAAA==.Mallika:BAAALAADCggIDQABLAAECgYICQACAAAAAA==.Mallwizard:BAAALAADCggICgAAAA==.Manslain:BAEALAADCggICwABLAAECgIIAgACAAAAAA==.Massoflice:BAAALAAECgYICwAAAA==.Maxilla:BAAALAAECgEIAQABLAAECgMICAACAAAAAA==.',Me='Methinkbig:BAAALAADCgUIBQAAAA==.',Mi='Mindhorn:BAAALAAECggIDAAAAA==.Misstangy:BAAALAAECgUIBgAAAA==.',Mo='Moct:BAAALAAECgMIBwAAAA==.',Ne='Necrochade:BAAALAAECgYIDgAAAA==.',Ni='Nightseeker:BAAALAAECgIIAwABLAAECgMIBwACAAAAAA==.Nishal:BAAALAADCggICAAAAA==.',No='Norano:BAAALAADCgMIAwAAAA==.Nost:BAAALAAECgMIBgAAAA==.',Om='Omnixia:BAAALAAECgIIAwAAAA==.',Or='Ormendahl:BAAALAAECgQIBQABLAAECggIFgAFAI8jAA==.',Pe='Peppert:BAAALAAECgIIAgAAAA==.Petrie:BAAALAADCggIDwAAAA==.',Ph='Phane:BAAALAAECgIIAgAAAA==.Phson:BAAALAADCgYIDQAAAA==.',Pi='Pillowfluff:BAAALAADCgMIAwAAAA==.Pillowstain:BAAALAADCgIIAwAAAA==.',Po='Poonwagoon:BAAALAADCgcIBwAAAA==.',Pr='Pretzelz:BAAALAAECggIBQAAAA==.',Pu='Puffer:BAAALAAECgEIAQAAAA==.',Py='Pyrrhus:BAABLAAECoEXAAMGAAcIfBwYFQA3AgAGAAcIfBwYFQA3AgAHAAEIExt+RwBNAAAAAA==.Pyt:BAAALAADCggICgAAAA==.',Ra='Rabone:BAAALAADCgYICAAAAA==.Raito:BAAALAAECgMIAwAAAA==.Rakshasa:BAAALAAECgIIAgAAAA==.Rasetsungo:BAAALAAECgMIBAAAAA==.Rashmi:BAABLAAECoEWAAIFAAgIjyNeAwAqAwAFAAgIjyNeAwAqAwAAAA==.Ravishing:BAAALAADCgcIBwAAAA==.',Re='Recalcitrent:BAAALAADCggIFgAAAA==.Redblueblurr:BAAALAAECgMIAwAAAA==.Redpandarian:BAAALAADCgUIBAAAAA==.Remi:BAAALAAECggIDgAAAA==.',Ri='Rilani:BAAALAADCgUIBQAAAA==.',Ro='Rolan:BAAALAAECgYIDAAAAA==.Rosalian:BAAALAAECgIIAwAAAA==.Roseyposey:BAAALAAECgQIBAAAAA==.Roweene:BAAALAAECgIIAgAAAA==.',Ry='Ryusei:BAAALAADCgYIBgAAAA==.',['Rà']='Ràziel:BAAALAADCgMIAwAAAA==.',Sa='Sabiel:BAAALAAECgMIAwAAAA==.Salin:BAAALAADCgEIAQAAAA==.Saphria:BAAALAADCgUIBQAAAA==.',Se='Sehrdumm:BAAALAAECgMIAwAAAA==.Selindal:BAAALAAECgUIDAAAAA==.Selryth:BAAALAAECggIBAAAAA==.Selvey:BAAALAADCggIDwAAAA==.',Sh='Shamwow:BAAALAADCgMIAwAAAA==.Shineontome:BAAALAAECgMIBAAAAA==.Shouhuzhee:BAAALAAECgYICQAAAA==.Shugo:BAAALAADCgYIBgAAAA==.',Si='Simone:BAAALAAECgYICgAAAA==.',So='Sonknight:BAAALAADCggIFAAAAA==.Sotto:BAAALAADCgcIDgAAAA==.',Sp='Spitefulcrow:BAAALAAECgMIBQAAAA==.Spyrø:BAAALAADCgYIDAAAAA==.',St='Stabyaballz:BAAALAAECgIIAgAAAA==.Steelbolt:BAAALAAECgcIDQAAAA==.',Su='Superball:BAAALAAECgMICAAAAA==.Suria:BAAALAAECgMIBwAAAA==.',Sy='Syker:BAAALAAECgMIAwAAAA==.',Ta='Tahrovin:BAAALAADCgcIBwAAAA==.Talayska:BAAALAADCgYICgAAAA==.Tallyman:BAAALAAECggICAAAAA==.Tavik:BAAALAAECgIIAgAAAA==.Taytorchips:BAAALAAECgMIBwAAAA==.',Te='Tebone:BAAALAADCgYIBgAAAA==.',Th='Thelm:BAAALAADCgcICQAAAA==.Thickyboi:BAAALAADCgcIDgAAAA==.Thillas:BAAALAAECgMIAwAAAA==.Threign:BAEALAAECgQIBQAAAA==.Thundercups:BAAALAAECgYICgAAAA==.Thørathesara:BAAALAAECgMIBAAAAA==.',Ti='Tigerstarr:BAAALAAECgUIBgAAAA==.Timboslicé:BAAALAADCggICAAAAA==.Tindra:BAAALAADCgEIAQAAAA==.',Tr='Treborlock:BAAALAAECgMIBwAAAA==.',Tu='Tustustus:BAAALAAECgcIDQAAAA==.',Ty='Tyránt:BAAALAAECggIDAAAAA==.',Ur='Urmarina:BAAALAAECgIIAgAAAA==.',Va='Vagglord:BAAALAAECgYIDwAAAA==.Valha:BAAALAAECgYICgAAAA==.Vanitus:BAAALAADCgYIBgAAAA==.Vared:BAEALAAECgIIAgAAAA==.Varteras:BAAALAAECgYICQAAAA==.',Ve='Velarissa:BAAALAAECgMIBgAAAA==.Vellron:BAAALAAECgMIBQAAAA==.',Vo='Voiddemon:BAAALAADCggICAAAAA==.',Wa='Wardemon:BAAALAAFFAIIAgAAAA==.Warint:BAAALAADCggICAAAAA==.',Wo='Wolfdude:BAAALAAECgIIAwAAAA==.',Wy='Wydge:BAAALAAECgMIBwAAAA==.Wymonath:BAAALAADCgEIAQAAAA==.',Xa='Xanddoria:BAAALAAECgMIBwAAAA==.Xannydevito:BAAALAAECgIIAwAAAA==.Xaoc:BAAALAAECgEIAQAAAA==.',Xh='Xhared:BAAALAAECgMIAwAAAA==.',Ya='Yawnarrow:BAAALAADCgMIAwAAAA==.',Ye='Yesenia:BAAALAADCggIDwAAAA==.',Ze='Zephy:BAAALAADCgcIDQAAAA==.',Zi='Zilcyra:BAAALAADCgQIBQAAAA==.',['Ël']='Ëlle:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end