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
 local lookup = {'Warlock-Destruction','Unknown-Unknown','Warrior-Protection',}; local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adinirin:BAAALAADCggIFgAAAA==.',Ae='Aellynn:BAAALAADCgUIBQAAAA==.',Al='Altruis:BAAALAADCgcIBwAAAA==.',Am='Amarawyn:BAAALAADCggIFQAAAA==.Amoragan:BAAALAAECgMIBAAAAA==.Amöre:BAAALAADCgEIAQAAAA==.',Ap='Apexy:BAAALAADCgcIBgAAAA==.',Ar='Arci:BAAALAAECgUICAAAAA==.Arnóra:BAAALAADCgMIAwAAAA==.',As='Ashwagandha:BAAALAAECgMIAwAAAA==.',Au='Augidget:BAAALAAECgIIAwAAAA==.',Av='Averlessa:BAAALAADCgcICwAAAA==.Aviane:BAAALAADCggICAAAAA==.',Ba='Badsilk:BAAALAADCggICAAAAA==.Bastael:BAAALAAECgMIBAAAAA==.Bayakoa:BAAALAADCgcIDQAAAA==.',Bi='Bigladx:BAAALAAECgEIAQABLAAECggIFAABAEQeAA==.Bitxi:BAAALAADCgcIBgAAAA==.',Bl='Bladesong:BAAALAADCgcIBgAAAA==.',Bo='Boldbane:BAAALAADCgcIDAAAAA==.Boshen:BAAALAAECgMIAwAAAA==.',Bu='Bulldozzer:BAAALAADCggICAAAAA==.Bullz:BAAALAADCggIEwAAAA==.Burda:BAAALAAECgYICAAAAA==.',Ca='Caenae:BAAALAADCgcIDQAAAA==.Cattlerage:BAAALAADCgYIBgABLAADCgcIBwACAAAAAA==.',Ch='Chanthane:BAAALAADCgcIDQAAAA==.',Cl='Clamor:BAAALAADCgcIEQAAAA==.',Co='Contractor:BAAALAADCggIDwABLAAECgYICgACAAAAAA==.Cooltiran:BAAALAADCggIDgAAAA==.Corri:BAAALAADCggIFAAAAA==.',Cr='Crag:BAAALAADCgcIBgAAAA==.Credon:BAAALAADCgcIBgAAAA==.Crixxe:BAAALAADCggIDwAAAA==.',Da='Darkelocke:BAAALAADCgQIAwAAAA==.',De='Dethdeej:BAAALAAECgUIBwAAAA==.Dethrage:BAAALAADCgUIBQAAAA==.',Di='Dierlyn:BAAALAADCggIFQAAAA==.Dimir:BAAALAADCgMIAwAAAA==.Dirtytaters:BAAALAADCgcIBgAAAA==.Divastating:BAAALAADCgYIDQABLAADCgcIEwACAAAAAA==.',Do='Doomeshade:BAAALAAECgMIAwAAAA==.',Dt='Dtothed:BAAALAADCggICgAAAA==.',['Dò']='Dòro:BAAALAADCgcIDAAAAA==.',Ea='Earadin:BAAALAADCgcIBwAAAA==.Earthmorp:BAAALAADCgQIBwAAAA==.',Ec='Ecthelorn:BAAALAADCgcIDQAAAA==.',El='Elasong:BAAALAADCggIFwAAAA==.Elletal:BAAALAADCggIDwABLAAECgIIAwACAAAAAA==.Elunar:BAAALAADCggIDwAAAA==.',Ev='Everleigh:BAAALAADCgQIBAAAAA==.',Fa='Fairamir:BAAALAADCgMIBgAAAA==.',Fi='Figbe:BAAALAADCggICAAAAA==.Fizzlyn:BAAALAAECgYIDgAAAA==.',Fl='Flandchaos:BAAALAADCgUIBQAAAA==.Flatdh:BAAALAADCgcIBwABLAAECgUICAACAAAAAA==.Flatron:BAAALAAECgUICAAAAA==.Flol:BAAALAADCgIIAgABLAAECgUIBwACAAAAAA==.',Go='Goatshadow:BAAALAADCggICAAAAA==.',Gr='Greedayde:BAAALAAECgEIAQAAAA==.Greedus:BAAALAADCgUIBQAAAA==.Grotusque:BAAALAAECgYICQAAAA==.',Ha='Haiiro:BAAALAAECgMIBAAAAA==.Hardim:BAAALAADCggIFQAAAA==.Harknesse:BAAALAADCgcIBgAAAA==.Haxxis:BAAALAADCggIDgAAAA==.',He='Heftydwarf:BAAALAADCggIFgAAAA==.Hemirlinia:BAAALAAECgIIAgAAAA==.Hewhospins:BAAALAAECgIIAwAAAA==.',Ho='Hog:BAAALAAECgcICgABLAAFFAMIBQADAEgfAA==.Holyboy:BAAALAADCgcIFAAAAA==.',Ia='Ianthvel:BAAALAADCgEIAQAAAA==.',In='Inalla:BAAALAADCggICAAAAA==.',Ja='Jacksmite:BAAALAADCggICAAAAA==.Jasmirana:BAAALAADCgcICgAAAA==.Jaunhulio:BAAALAADCgUIBQAAAA==.',Jo='Jolreal:BAAALAAECgcIDwAAAA==.Josh:BAAALAAECgIIAgAAAA==.',Ju='Julez:BAAALAADCggIDwAAAA==.Julezara:BAAALAADCgcICwAAAA==.Junkai:BAAALAAECgYICgAAAA==.',Jy='Jyntazlyn:BAAALAADCgUIBQAAAA==.',Ka='Kanzashi:BAAALAADCggICAAAAA==.',Ke='Keco:BAAALAADCgcIEwAAAA==.Kenchie:BAAALAADCgYIBgABLAAECgIIBAACAAAAAA==.Kennie:BAAALAAECgUICAAAAA==.',Kh='Khalician:BAAALAADCgcIBgAAAA==.',Kl='Kladibo:BAAALAAECgMIBAAAAA==.Kladivo:BAAALAADCgcIBwABLAAECgMIBAACAAAAAA==.',Ko='Kom:BAAALAAECgQIBQAAAA==.',Ky='Kyntala:BAAALAADCgMIAwAAAA==.',La='Lahlania:BAAALAADCggIDwAAAA==.Lanaki:BAAALAAECgQIBAAAAA==.',Le='Leagolas:BAAALAADCgcIBwAAAA==.',Ma='Mailaria:BAAALAAECgMIBAAAAA==.Malific:BAAALAAECgYICQAAAA==.Mantoecore:BAAALAADCgMIAwAAAA==.Marellaa:BAAALAADCgcIDQAAAA==.',Me='Meingsolin:BAAALAADCggIDwAAAA==.',Mo='Morp:BAAALAADCggIDAAAAA==.',Mu='Mucklord:BAAALAADCggICwAAAA==.',My='Myuk:BAAALAAECgMIAwAAAA==.',Na='Narbash:BAAALAAECgYICQAAAA==.',Ne='Nekia:BAAALAAECgMIAwAAAA==.Neroz:BAAALAAECgUICAAAAA==.',Ni='Nightfallz:BAAALAADCgEIAQAAAA==.',Nk='Nkript:BAAALAAECgIIBAAAAA==.',No='Nortel:BAAALAADCgIIAgAAAA==.',Ok='Oksite:BAAALAADCgUIBQAAAA==.',On='Onari:BAAALAAECgMIBAAAAA==.Onlyfannz:BAAALAADCggIFwAAAA==.',Pe='Perce:BAAALAAECgEIAQAAAA==.',Po='Popcorns:BAAALAAECgcIDwAAAA==.',Ps='Psych:BAAALAADCgYICQAAAA==.',Ra='Raynier:BAAALAADCgUIBQAAAA==.',Re='Reshar:BAAALAAECgUIBwAAAA==.Reyaieleron:BAAALAADCggIFwAAAA==.',Ri='Rivenaer:BAAALAAECgMIBwAAAA==.',Ro='Roldrick:BAAALAADCgUIBQAAAA==.',Ru='Ruindsoul:BAAALAADCgYICgAAAA==.Rus:BAAALAAECgMIAwAAAA==.',Sa='Salith:BAAALAADCgQIBgAAAA==.Saphi:BAAALAADCggICQAAAA==.Saulei:BAAALAADCggICAAAAA==.Savarra:BAAALAAECgMIAwAAAA==.',Sc='Scaletal:BAAALAADCgMIAwAAAA==.Schmoopsy:BAAALAAECgMIAwAAAA==.',Se='Sealalicious:BAAALAAECgUIBwAAAA==.Seboom:BAAALAADCggICAAAAA==.Secondbreath:BAAALAADCgcIBgAAAA==.',Sh='Shammywow:BAAALAADCggICQAAAA==.Sharkzilla:BAAALAAECgMIAwAAAA==.Shaureesa:BAAALAAECgEIAQAAAA==.Shine:BAAALAADCgcIBwAAAA==.Shiny:BAAALAADCgcIBwAAAA==.Shwoman:BAAALAADCgIIAgAAAA==.',Si='Silksmilk:BAAALAADCgcIDgAAAA==.',Sm='Smôkey:BAAALAAECgMIBAAAAA==.',So='Soggyaugi:BAAALAADCgcIDAAAAA==.Solbinder:BAAALAADCgYIBgAAAA==.',Su='Sunwälker:BAAALAADCgIIAgAAAA==.',Sw='Swiftheals:BAAALAADCggICAAAAA==.Swifty:BAAALAAECgEIAQAAAA==.',Ta='Tallchief:BAAALAADCgcIDQAAAA==.Tax:BAAALAADCgcICgAAAA==.',Te='Tenchie:BAAALAAECgIIBAAAAA==.Tenjo:BAAALAAECgYICwAAAA==.',Th='Thanmorp:BAAALAADCgMIAwAAAA==.Thatonehuntr:BAAALAAECgIIAgAAAA==.Theophilus:BAAALAADCgcICQAAAA==.',Ti='Timdeath:BAAALAAECgEIAQAAAA==.',Tr='Trublood:BAAALAADCgcIBgAAAA==.',Tv='Tvp:BAAALAADCgMIAwABLAAECgMIAwACAAAAAA==.',Ty='Tyrra:BAAALAADCgcIBgAAAA==.',['Tâ']='Tâwen:BAAALAAECgIIAwAAAA==.',Ve='Vesaryn:BAAALAADCgMIAwAAAA==.',Vi='Victory:BAAALAADCgUIBQAAAA==.Vintar:BAAALAADCgUIBQAAAA==.',Vy='Vyu:BAAALAADCgMIAwAAAA==.',Wa='Wanayu:BAAALAAECgMIBAAAAA==.Wanweasley:BAAALAADCgcIDAAAAA==.',Wi='Willic:BAAALAADCggICAAAAA==.Wizagon:BAAALAAECgMIBAAAAA==.',Wo='Woodsy:BAAALAAECgMIBAAAAA==.Woody:BAAALAADCgUIBQAAAA==.Woundliquor:BAAALAADCggIDQAAAA==.',Wu='Wunna:BAAALAADCggIEAAAAA==.',Xe='Xemnas:BAAALAADCggIBgAAAA==.',Xi='Xiototem:BAAALAADCgYIBgAAAA==.',Za='Zalael:BAAALAADCggIFwAAAA==.Zaryala:BAAALAADCggIFwAAAA==.',Ze='Zedruu:BAAALAADCggIFgAAAA==.Zenshift:BAAALAADCgUIBAAAAA==.',Zg='Zgnilka:BAAALAAECgMIBAAAAA==.',Zi='Zitpally:BAAALAAECgUICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end