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
 local lookup = {'Unknown-Unknown',}; local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aelaanallina:BAAALAADCgUIBQAAAA==.Aelless:BAAALAAECgIIAgAAAA==.',Al='Alakere:BAAALAADCgQIBAAAAA==.Aledil:BAAALAADCgEIAQAAAA==.',Am='Ameliari:BAAALAADCggICAAAAA==.',An='Anchortits:BAAALAADCgcIBwAAAA==.Anume:BAAALAADCgMIAwAAAA==.',Ap='Apally:BAAALAADCgEIAQAAAA==.',Ar='Arese:BAAALAAECgUIBgAAAA==.',At='Athar:BAAALAADCgMIAwAAAA==.Attlass:BAAALAADCgQIBAAAAA==.',Au='Autodefe:BAAALAADCgEIAQAAAA==.',Ba='Babybluz:BAAALAADCggICgAAAA==.Baliel:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.Bandayde:BAAALAADCgYIBQAAAA==.Baunshee:BAAALAAECgIIAwAAAA==.',Be='Bearlylegal:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Beauriley:BAAALAAECgYICQAAAA==.Behomethan:BAAALAAECgYICAAAAA==.Berth:BAAALAADCgEIAQAAAA==.',Br='Bratticusrex:BAAALAAECgEIAgAAAA==.',Bu='Bunnyhopp:BAAALAADCgcIBwABLAAECgUICAABAAAAAA==.Bunnylicious:BAAALAAECgUICAAAAA==.Buzlightyear:BAAALAADCgcICQAAAA==.',Ca='Caebrylla:BAAALAAECgMIBAAAAA==.',Ce='Cecidaemon:BAAALAAECgMIBAAAAA==.',Ch='Chonker:BAAALAAECgMIBgAAAA==.',Ci='Cihato:BAAALAAECgYICwAAAA==.',Cl='Claxious:BAAALAAECgMIAwAAAA==.Claye:BAAALAAECgYIDQAAAA==.Cleveland:BAAALAADCgUIBAAAAA==.',Co='Cordessa:BAAALAADCggICAAAAA==.Corelas:BAAALAAECgEIAQAAAA==.',Da='Damo:BAAALAAECggIDQAAAA==.Dawnson:BAAALAAECgIIAgAAAA==.',De='Deadzexcs:BAAALAADCgYIBgAAAA==.Desmond:BAAALAADCgEIAQAAAA==.',Dh='Dharknight:BAAALAADCgcIDQAAAA==.',Di='Didimissfire:BAAALAAECgMIBwAAAA==.Dieasap:BAAALAADCgUIBQAAAA==.',Dp='Dpsmaster:BAAALAADCgQIBwAAAA==.',Dr='Dreadnought:BAAALAAECggICQAAAA==.Dredlok:BAAALAADCgcIFQAAAA==.',Du='Dumonster:BAAALAAECgIIAgAAAA==.',['Dè']='Dèäth:BAAALAAECgMIAwAAAA==.',Ed='Edgelord:BAAALAAECgEIAQAAAA==.',El='Elaasolyssa:BAAALAADCgYIBgAAAA==.Elev:BAAALAADCgMIAwAAAA==.Elizabeth:BAAALAADCgMIAwAAAA==.Ellise:BAAALAADCggIEQAAAA==.Elvìs:BAAALAADCgcIBwAAAA==.',En='Entrepreneur:BAAALAADCgEIAQAAAA==.',Eo='Eowynn:BAAALAADCgcIFAAAAA==.',Er='Erzascar:BAAALAADCgcIBwAAAA==.',Fa='Failadin:BAAALAAECgIIAgAAAA==.Fatbox:BAAALAAECgUIBQAAAA==.Faythh:BAAALAAECgYICwAAAA==.',Fe='Fearblade:BAAALAAECgUICAAAAA==.',Fi='Fiobhe:BAAALAAECgEIAQAAAA==.Fixeruper:BAAALAAECgMIBAAAAA==.Fizie:BAAALAADCgYIBgAAAA==.',Fo='Fonz:BAAALAAECgcICAAAAA==.Footdig:BAAALAAECgMIAwAAAA==.',Gl='Glenroyce:BAEALAADCggIDgAAAA==.Gless:BAAALAADCgcIDgAAAA==.',Gn='Gnoretreat:BAAALAAECgMIBwAAAA==.',Ha='Harleydk:BAAALAAECgYICAAAAA==.',He='Helon:BAAALAAECgMIBQAAAA==.',Ic='Icandy:BAAALAADCgcICgAAAA==.',Ii='Iikeomgikr:BAAALAAECgQIBgAAAA==.',Il='Ilidank:BAAALAAECgIIAgAAAA==.',In='Indigo:BAAALAAECgUICAAAAA==.Ineffablyss:BAAALAADCggICAABLAAECgQIBgABAAAAAA==.Innron:BAAALAAECgMIBwAAAA==.',Is='Isyclic:BAAALAAECgUICAAAAA==.',Jd='Jd:BAAALAADCgQIBAAAAA==.',Je='Jezzea:BAAALAADCgMIAwAAAA==.',Ji='Jimmayheals:BAAALAADCgcIBwAAAA==.Jinnkabus:BAAALAADCgcIBwAAAA==.',['Jâ']='Jâtens:BAAALAAFFAEIAQAAAA==.',Ka='Kairring:BAAALAAECgIIAgAAAA==.Kamehameha:BAAALAAECgMIBQAAAA==.Kattia:BAAALAAECgUICAAAAA==.',Kh='Khat:BAAALAADCgcIFQAAAA==.Khir:BAAALAAECgQIBAAAAA==.',Ki='Kinomihime:BAAALAAECgYICwAAAA==.Kirajoy:BAAALAAECgUICAAAAA==.',Kn='Knyghtt:BAAALAAECgMIBAAAAA==.',Kr='Kraqen:BAAALAAECgQIBAAAAA==.Krystle:BAAALAAECgIIAgAAAA==.',Li='Lilivara:BAAALAAECgEIAQAAAA==.',Lo='Lockofdeath:BAAALAADCgYIBwAAAA==.Logarth:BAAALAADCggIEAAAAA==.Lopseng:BAAALAADCgYIBgAAAA==.Lorcan:BAAALAAECgYICgAAAA==.',Lu='Luckyleet:BAAALAADCgMIAwAAAA==.Lucyfer:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Ludicrispeed:BAAALAADCgMIAwAAAA==.Lunamina:BAAALAAECgUICAAAAA==.',Ly='Lytemaul:BAAALAADCgcIBwAAAA==.',Ma='Mallas:BAAALAADCgcIBwAAAA==.Mariophra:BAAALAAECgMIBAAAAA==.Maxtheb:BAAALAAECgIIBAAAAA==.',Mc='Mcspicy:BAAALAADCggIDQAAAA==.',Mi='Mikka:BAAALAAECgYIBgAAAA==.Misstorgo:BAAALAAECgEIAQAAAA==.',Mo='Mofuucka:BAAALAADCgMIAwABLAAECgUIBgABAAAAAA==.Mogue:BAAALAADCgMIAwAAAA==.Monfro:BAAALAAECgIIAgAAAA==.Moonbane:BAAALAAECgYICgAAAA==.Moonmist:BAAALAADCgcIDgAAAA==.',My='Myaquean:BAAALAADCgMIAwAAAA==.',Na='Nakeefa:BAAALAAECgIIBAAAAA==.Nanaimo:BAAALAAECgEIAQAAAA==.Natsuu:BAAALAAECgUICAAAAA==.Naturan:BAAALAAECgUICAAAAA==.Naturewolf:BAAALAADCggIDwAAAA==.',Ne='Nekona:BAAALAAECgQIBQAAAA==.Neron:BAAALAAECgYIDAAAAA==.',Ni='Niany:BAAALAADCgMIAwAAAA==.',Oc='Ocatarineta:BAAALAADCgYIBAAAAA==.',Om='Omegalich:BAAALAAECgMIAwAAAA==.',Ot='Othaerion:BAAALAAECgQIBAAAAA==.',Ou='Outerlimits:BAAALAAECgIIAwAAAA==.',Pa='Pamboo:BAAALAAECgMIBwAAAA==.',Pe='Pearle:BAAALAAECgUICAAAAA==.',Pi='Pistol:BAAALAAECgIIAgAAAA==.',Pl='Playmaker:BAAALAAECgIIAgAAAA==.',Pr='Propaly:BAAALAADCgYIBgAAAA==.',Ra='Ramindizzle:BAAALAAECgIIAwAAAA==.Rangewolf:BAAALAAECgMIBgAAAA==.',Re='Redmurk:BAAALAAECgYICAAAAA==.Rei:BAAALAADCgcIBwAAAA==.Rejuvasap:BAAALAAECgMIBwAAAA==.',Ri='Rigmarole:BAAALAADCgcIBwAAAA==.Rikal:BAAALAADCgMIAwAAAA==.',Ro='Rokomut:BAAALAADCgcIBwAAAA==.Rook:BAAALAAECgYICgAAAA==.',Ru='Ruffiyo:BAAALAAECgYICgAAAA==.Rugrahh:BAAALAAECgQICgAAAA==.Ruthen:BAAALAADCgcIDgAAAA==.Ruìn:BAAALAAECgEIAQAAAA==.',Sa='Sabina:BAAALAAECgYICwAAAA==.Sadness:BAAALAADCgcIFQAAAA==.Sadorick:BAAALAADCgcIBwAAAA==.Sahugoni:BAAALAADCgUIBQAAAA==.Sango:BAAALAAECgIIAwAAAA==.',Sc='Scotch:BAAALAAECgUIBQAAAA==.Scotchtea:BAAALAADCgIIAgAAAA==.',Sh='Shadornia:BAAALAAECgMIBgAAAA==.Shadowcrwlr:BAAALAAECgEIAgAAAA==.Shamangroo:BAAALAADCggICAAAAA==.',Si='Silverywolfe:BAAALAADCgcIFQAAAA==.Simony:BAAALAAECgIIAgAAAA==.',Sk='Skovak:BAAALAADCgcICQAAAA==.',Sl='Sluggerssham:BAAALAAECgIIAgAAAA==.',So='Solyndra:BAAALAAECgMIAwAAAA==.Sorayae:BAAALAAECgMIBwAAAA==.',Sp='Specialk:BAAALAADCgcIFQAAAA==.Splooshh:BAAALAAECgIIAgABLAAECgYICgABAAAAAA==.',St='Stormkissed:BAAALAAECgEIAQAAAA==.Stuckstepsis:BAAALAADCgQIBAAAAA==.',Su='Sulvazud:BAAALAAECgUICAAAAA==.Sunil:BAAALAAECgUIBQAAAA==.',Sy='Syclic:BAAALAADCgcIBwAAAA==.Syclone:BAAALAADCgcIDgAAAA==.',Ta='Talmi:BAAALAADCgcIBwAAAA==.Tattianna:BAAALAADCgcICwAAAA==.',Te='Tegh:BAAALAADCgcIBwAAAA==.Tera:BAAALAAECgMIBAAAAA==.',Th='Theodawg:BAAALAADCggIDgAAAA==.',Ti='Tigreth:BAAALAAECgYICgAAAA==.Timotheus:BAAALAADCgUIBQAAAA==.Tintaglia:BAAALAAECgMIAwAAAA==.',Tr='Tragik:BAAALAAECgMIBgAAAA==.',Tu='Tuugadark:BAAALAAECgMIBwAAAA==.',['Tî']='Tîtan:BAAALAAECgYICgAAAA==.',Va='Vaesha:BAAALAADCgcIBwAAAA==.',Ve='Verothzemeus:BAAALAADCggIAgAAAA==.Vexahllia:BAAALAADCgcIBwAAAA==.',Vo='Vorukh:BAAALAAECgEIAQAAAA==.Vorükh:BAAALAAECgMIAwAAAA==.',Vy='Vynas:BAAALAADCgcIBwAAAA==.',Wa='Warriorgroo:BAAALAADCgcICwABLAADCggICAABAAAAAA==.',We='Wertyda:BAAALAAECgQIBwAAAA==.',Wi='Wickdlovly:BAAALAADCgYIBgABLAADCgcIDgABAAAAAA==.',Xo='Xoren:BAAALAADCggICAAAAA==.',Xx='Xxmonkz:BAAALAAECgMIAwAAAA==.',Yo='Youremo:BAAALAADCgMIAwAAAA==.',Yu='Yuriko:BAAALAAECgYICwAAAA==.',Ze='Zenbaby:BAAALAAECgMIBAAAAA==.Zevgrip:BAAALAADCgEIAQAAAA==.',Zo='Zodiacc:BAAALAAECgMIBwAAAA==.Zornhealer:BAAALAAECgEIAQAAAA==.',Zs='Zsasz:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end