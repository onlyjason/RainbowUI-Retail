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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Paladin-Retribution','Paladin-Holy',}; local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adaila:BAAALAAECgcIDwAAAA==.',Ai='Aiir:BAAALAADCggIFwAAAA==.',Al='All:BAAALAADCggICAAAAA==.Alwayspala:BAAALAAECgUIBgAAAA==.Alwaysraging:BAAALAADCggICAABLAAECgUIBgABAAAAAA==.',Am='Amaterasu:BAAALAADCgUIBQAAAA==.Amelandra:BAAALAADCgcIEQAAAA==.',An='Ansela:BAAALAADCgcIBwAAAA==.',Ap='Aphaea:BAAALAAECgUIBQAAAA==.',As='Ashtomb:BAAALAADCgMIAwABLAAECgYIDAABAAAAAA==.Astrothunder:BAAALAAECgcIDwAAAA==.',Av='Avari:BAAALAADCgUIBQABLAAECgMIBAABAAAAAA==.',Az='Azshalia:BAAALAADCgIIAgAAAA==.',Ba='Baelos:BAAALAADCgYIBgAAAA==.Baishu:BAAALAAECgMIAwAAAA==.Banilibug:BAAALAAECgMIBAAAAA==.Barkforheals:BAAALAADCgUIBQAAAA==.Barrmage:BAAALAAECgYIBwAAAA==.Baxstabba:BAAALAAECgMIBAAAAA==.',Bl='Blackmoon:BAAALAAECgYIDAAAAA==.Bleekz:BAAALAADCggICAAAAA==.Bloodspot:BAAALAAECgIIAgAAAA==.',Bo='Bobbybrady:BAAALAAECgMIBAAAAA==.Boggnarley:BAAALAAECgMIBAAAAA==.Bosshogshift:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.Bosshogshock:BAAALAAECgYIDQAAAA==.Boushh:BAAALAAECgIIAwAAAA==.',Br='Brakhwet:BAAALAAECgcIDwAAAA==.',Bu='Burnit:BAAALAADCgMIAwAAAA==.Butterbean:BAAALAAECgcIDwAAAA==.',Ch='Chanchan:BAAALAADCgMIBAAAAA==.Chickenhawk:BAAALAADCgcIBwAAAA==.Chicxulub:BAAALAAECgEIAQAAAA==.Chido:BAAALAADCgYICgABLAAECgMIBAABAAAAAA==.',Cl='Classfantasy:BAAALAAECgcIDwAAAA==.',Co='Confluent:BAAALAAECgYICwAAAA==.Cooties:BAAALAADCggIDgAAAA==.',Cr='Crimson:BAAALAAECgYIDAAAAA==.',Da='Dairellzik:BAAALAADCgEIAQAAAA==.Darknizz:BAAALAADCggIDgAAAA==.Daruta:BAAALAADCgMIAwAAAA==.Daytona:BAAALAAECgEIAQAAAA==.',Dd='Ddccssff:BAAALAADCggIEQAAAA==.',De='Deboisly:BAAALAAECgcIEAAAAA==.Denia:BAAALAADCgMIAwAAAA==.Dethrahzen:BAAALAAECgEIAQAAAA==.Deàthwish:BAAALAAECgYIBgAAAA==.',Di='Dipika:BAAALAADCgYIBgAAAA==.Dispriest:BAABLAAECoEUAAICAAgIIyFvBQAEAwACAAgIIyFvBQAEAwAAAA==.',Do='Douglit:BAAALAADCgcIBwAAAA==.',Dr='Dragonboy:BAAALAAECgMIBQAAAA==.Dreamelf:BAAALAAECgYICgAAAA==.',Du='Dugatotems:BAAALAAECgYIDQAAAA==.Dunkle:BAAALAAECgMIAwAAAA==.Duskhawk:BAAALAAECgEIAQAAAA==.',Ea='Earthycakes:BAAALAADCgMIAwAAAA==.',Eb='Ebonise:BAAALAADCgMIAwAAAA==.',Ed='Edrelang:BAAALAADCgUIBQAAAA==.',Er='Erisa:BAAALAADCggICAAAAA==.Erommêl:BAAALAADCgMIAwAAAA==.',Fa='Farsha:BAAALAADCgYIDAABLAAECgMIBAABAAAAAA==.',Fe='Feathbris:BAAALAADCgYIBgAAAA==.Feyr:BAAALAADCgMIAwAAAA==.',Fu='Furrystorm:BAAALAADCgMIAwAAAA==.',Ga='Galandre:BAAALAADCgcICQAAAA==.',Gh='Ghast:BAAALAADCggIDwAAAA==.',Gi='Gigaflare:BAAALAAECgcIDwAAAA==.',Gl='Glahmgold:BAAALAADCgMIBAAAAA==.Glaivemaster:BAAALAADCgEIAQAAAA==.Glickiwik:BAAALAADCgMIBAAAAA==.',Go='Goathunter:BAAALAAECgYIDAAAAA==.Golokan:BAAALAAECgMIBAAAAA==.',Gr='Grandpawolf:BAAALAADCgMIAwAAAA==.Graymoon:BAAALAADCggICAAAAA==.Grelmamn:BAAALAADCgcIBwAAAA==.Greywings:BAAALAAECgIIAgAAAA==.Grimroxs:BAAALAAECgMIAwAAAA==.',Gw='Gwendalynny:BAAALAADCgYICQAAAA==.',Ha='Hadrian:BAAALAAECgQIBAAAAA==.Hairydragon:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Hakalah:BAAALAADCgEIAQAAAA==.Handerboogle:BAAALAADCggIDQABLAAECgcIDwABAAAAAA==.Handerbug:BAAALAAECgcIDwAAAA==.Handerbugg:BAAALAADCgYIDAABLAAECgcIDwABAAAAAA==.Haschel:BAAALAADCgEIAQAAAA==.Hazmati:BAAALAAECgcIDAAAAA==.',He='Healthis:BAAALAAECgEIAQAAAA==.Hectors:BAAALAADCgYICgAAAA==.Heiler:BAAALAAECgUIBwAAAA==.Heinrich:BAAALAAECgMIAwAAAA==.',Hi='Hi:BAAALAAECgMIAwAAAA==.',Ho='Hogglethorp:BAAALAADCggIEAAAAA==.Hotchick:BAAALAADCggIDQAAAA==.',Hu='Huntion:BAAALAAECgEIAQAAAA==.Hupu:BAAALAAECgMIBQAAAA==.',Hz='Hz:BAAALAADCgUIBQAAAA==.',Il='Illadron:BAAALAAECgUICAAAAA==.',In='Indiras:BAAALAADCgcICAAAAA==.',Ja='Jarra:BAAALAADCgIIAgAAAA==.',Jd='Jdpot:BAAALAADCgMIAwAAAA==.',Je='Jenaaidy:BAAALAAECgMIBgAAAA==.',Jh='Jhannae:BAAALAADCggIEwAAAA==.',Jj='Jjh:BAAALAAECgYIDAAAAA==.',Jo='Joshed:BAAALAAECgcIEQAAAA==.',Ju='Judge:BAAALAAECgIIAgAAAA==.Junnko:BAAALAADCggIDwABLAAECgMIBAABAAAAAA==.',Jy='Jynrokka:BAAALAAECgMIBAAAAA==.',Ka='Kaycee:BAAALAAECgEIAQAAAA==.',Ke='Ketura:BAAALAADCgMIBQAAAA==.',Ki='Kianthos:BAAALAAECgMIBAAAAA==.Kimetshu:BAAALAADCgEIAQAAAA==.',Ko='Korialstratz:BAAALAAECgUIBwAAAA==.',Kr='Kraphtdinner:BAAALAAECgcIBwAAAA==.Kravin:BAAALAADCgcIEAAAAA==.',Ku='Kudrani:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.',Ky='Kyborgshifty:BAAALAAECgIIAgAAAA==.Kyraellina:BAAALAADCgUIBwAAAA==.',La='Lauxy:BAAALAADCgEIAQAAAA==.',Le='Leliànà:BAAALAADCggICAAAAA==.Leonuss:BAAALAAECgcIDwAAAA==.Letmekillu:BAAALAAECgEIAQAAAA==.Levìstus:BAAALAAECgMIBAAAAA==.Leylaní:BAAALAAECgUIBwAAAA==.Leyva:BAAALAADCgcIBwAAAA==.',Li='Lie:BAAALAAFFAIIAgAAAA==.Lillinth:BAAALAADCgYIDAAAAA==.',Lo='Loroessan:BAAALAADCgcICgAAAA==.Lounar:BAAALAAECgEIAQAAAA==.',Lu='Luckylynn:BAAALAAECgEIAQAAAA==.',Ly='Lytheum:BAAALAAECgcIDwAAAA==.',Ma='Majoc:BAAALAAECgEIAQAAAA==.Malachar:BAAALAAECgMIBAAAAA==.Malboro:BAAALAAECgMIAwAAAA==.Maled:BAAALAADCggIDwAAAA==.Mayheal:BAAALAADCgMIAwAAAA==.',Me='Meldin:BAAALAAECgUIBwAAAA==.Mennia:BAAALAADCgYICAAAAA==.Method:BAAALAAECgcIDwAAAA==.',Mi='Miannya:BAAALAAECgYICgAAAA==.Mignons:BAAALAAECgcIDwAAAA==.Mineos:BAAALAADCgcICwAAAA==.Miyore:BAAALAADCggICQABLAAECgEIAQABAAAAAA==.',Mo='Moahuntress:BAAALAAECgEIAQAAAA==.Moardibe:BAAALAADCgcIDgAAAA==.Moderation:BAAALAADCggICgAAAA==.Monspeet:BAAALAADCgcIBwAAAA==.',Mu='Munchmaquchi:BAAALAADCgEIAQAAAA==.Muradìn:BAAALAADCggICwAAAA==.',Na='Nasath:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.',Ne='Needagrip:BAAALAAECgUIBwAAAA==.Neonod:BAAALAAECgUIBwAAAA==.Nerrd:BAAALAAECgUICgAAAA==.Ness:BAAALAADCgYIBgAAAA==.Netherman:BAAALAAECgMIAwAAAA==.Newman:BAAALAAECgIIAgAAAA==.',Ni='Nizmô:BAAALAADCgYIBgAAAA==.',Nu='Nunsense:BAAALAADCgYIBgAAAA==.',Ny='Nynevans:BAAALAAECgMIBAAAAA==.Nystannia:BAAALAADCgcIDgABLAAECgMIBAABAAAAAA==.',Or='Orbitx:BAAALAADCgIIAQAAAA==.Orlandbro:BAAALAAECgcIDwAAAA==.',Ot='Otohime:BAAALAADCgcIBwAAAA==.',Oy='Oy:BAAALAADCgEIAQAAAA==.',Pa='Papapedro:BAAALAADCggICAAAAA==.Pars:BAAALAADCgcIBwAAAA==.Patantrad:BAAALAAECgEIAQAAAA==.Patchs:BAAALAADCggICgAAAA==.',Pe='Persefone:BAAALAADCggICAAAAA==.',Ph='Photon:BAAALAADCgUIBQAAAA==.Phumsukrit:BAAALAADCggIEAAAAA==.',Pi='Pitviper:BAAALAADCgcICgAAAA==.',Pl='Plina:BAAALAAECgUIBwAAAA==.',Po='Ponponte:BAAALAAECgYICgAAAA==.Potatolor:BAAALAAECgMIAwAAAA==.',Pr='Prettycolorz:BAAALAAECgYICwAAAA==.',Pu='Pulli:BAAALAADCgcICAAAAA==.',Ra='Ragni:BAAALAADCggIDwAAAA==.Raiina:BAAALAAECgMIAwAAAA==.Rathane:BAAALAAECgcIDwAAAA==.Razhj:BAAALAADCgQIBQAAAA==.',Re='Remillia:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.Respite:BAAALAAECgYICQAAAA==.',Rh='Rhapsody:BAAALAAECgMIBAAAAA==.',Ri='Ricknar:BAAALAADCggICAAAAA==.Ricosmonk:BAAALAADCgYIDAAAAA==.Rina:BAAALAAFFAMIAwAAAA==.',Ro='Rockruff:BAAALAADCgcICAAAAA==.',Ru='Ruw:BAAALAADCggIFwAAAA==.',Sa='Sarumon:BAAALAADCgMIAwAAAA==.',Se='Seniortotem:BAAALAAECgEIAQAAAA==.',Sh='Shaanael:BAAALAADCgMIAwAAAA==.Shaokahn:BAAALAADCgUIBQAAAA==.Shapòópy:BAAALAAECgIIAgAAAA==.Shavv:BAAALAADCgMIBAAAAA==.Shawesome:BAAALAADCgUIBQAAAA==.Shelbycobra:BAAALAADCggICAAAAA==.Shrinkydinks:BAAALAADCgIIAgAAAA==.Shädôwlôck:BAAALAAECgIIAgAAAA==.',Si='Siltrois:BAAALAAECgEIAQAAAA==.Siryn:BAAALAADCgcIBwAAAA==.',Sm='Smashn:BAAALAADCggIDwAAAA==.',Sq='Squeeze:BAAALAADCgQIBQAAAA==.',St='Stixxie:BAAALAADCgYIDAAAAA==.Stonehammer:BAAALAAECgIIAgAAAA==.Stormbound:BAAALAADCgcIBwAAAA==.',Su='Suboptimal:BAAALAADCgcIDQAAAA==.Sugarpop:BAAALAADCgMIAwAAAA==.',Sy='Syladra:BAAALAAECgMIAwAAAA==.Sylesta:BAAALAAECgcIDgAAAA==.',Ta='Tancia:BAAALAADCgYICwAAAA==.Tarissa:BAAALAADCgYIBgAAAA==.',Te='Teremen:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.',Th='Thelati:BAAALAADCgcIBwAAAA==.Thniper:BAAALAADCggICgAAAA==.',Ti='Tiamaria:BAAALAAECgYIBgAAAA==.',Tr='Truzt:BAAALAAECgMIBQABLAAECgcIDwABAAAAAA==.',Ty='Tyinviril:BAAALAAECgYIDwAAAA==.',Ve='Veraz:BAABLAAECoEWAAMDAAgIUR5FDAC+AgADAAgIUR5FDAC+AgAEAAIIWwW5LQBgAAAAAA==.Versoco:BAAALAAECgUIBQAAAA==.',Vl='Vlada:BAAALAADCgIIAgABLAAECgIIAwABAAAAAA==.',Vo='Voldemortt:BAAALAADCgQIBAAAAA==.Vonawesome:BAAALAADCgcIDAAAAA==.Vorpalblade:BAAALAAECgcIDwAAAA==.',Wa='Warlorok:BAAALAADCgYIBgAAAA==.Warpsmithoor:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',We='Wedge:BAAALAAECgEIAQAAAA==.Wend:BAAALAAECgcIDwAAAA==.',Wi='Windshaper:BAAALAAECgYIDAAAAA==.',Wy='Wychlord:BAAALAAECgEIAQAAAA==.',Xi='Xiomara:BAAALAADCgMIAwAAAA==.',Yn='Yn:BAAALAAECgMIAwAAAA==.',Za='Zanrois:BAAALAAECgEIAQAAAA==.',Zh='Zhulk:BAAALAADCgIIAgAAAA==.',['Äm']='Ämana:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end