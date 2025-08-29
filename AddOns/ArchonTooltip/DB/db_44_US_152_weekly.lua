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
 local lookup = {'Unknown-Unknown','Monk-Windwalker','Warrior-Fury','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy',}; local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaylasecura:BAAALAAECgYICwAAAA==.',Ab='Abscynth:BAAALAADCgcIBwABLAAECgcIDQABAAAAAA==.Absolutezero:BAAALAAECgcIDQAAAA==.',Ag='Agmaa:BAAALAAECgEIAQAAAA==.',Ai='Airfriend:BAAALAAECgYIDgAAAA==.',Ak='Akodam:BAAALAADCgYIBgAAAA==.',Al='Alphard:BAAALAAECgYICAAAAA==.Alterboy:BAAALAADCgIIAgAAAA==.Aluriel:BAAALAAECgcIDgAAAA==.',An='Anelowyn:BAAALAAECgYICAAAAA==.',Ap='Apocal:BAAALAAECggIDwAAAA==.',Ar='Arcailos:BAAALAADCgcIDgABLAAECgIIAgABAAAAAA==.Archlock:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.Arete:BAAALAADCgYIBwAAAA==.Arngaz:BAAALAADCgMIAwAAAA==.',As='Assasinátion:BAAALAADCgEIAQAAAA==.',At='Atonemick:BAAALAAECgMIBgAAAA==.',Az='Azgrntea:BAAALAADCggIFwAAAA==.',Ba='Baraden:BAAALAAECgYIDAAAAA==.',Be='Beefshamburg:BAAALAAFFAIIAgAAAA==.Beefthrash:BAAALAAECggIBgAAAA==.Beefy:BAAALAAECgcIDQAAAA==.',Bi='Bigtimmehss:BAAALAADCgUIBQAAAA==.Bikerz:BAAALAADCgMIAwAAAA==.Birgetta:BAAALAAECgcIDQAAAA==.Birus:BAABLAAECoEYAAICAAgIaSOZAgAQAwACAAgIaSOZAgAQAwAAAA==.',Bl='Blaek:BAAALAAECgcIDQAAAA==.',Bo='Bobodaklown:BAAALAAECgYICQAAAA==.Boomnberzerk:BAAALAADCgcICwABLAAECgcICwABAAAAAA==.Boomnbrew:BAAALAAECgcICwAAAA==.Bownir:BAAALAAECgcIEAAAAA==.',Br='Brucesico:BAAALAAECgIIAgAAAA==.',Bu='Bubonic:BAAALAAECgMIAwAAAA==.Buenasalud:BAAALAAECgYIBwAAAA==.Butterman:BAAALAADCgEIAQAAAA==.',Ca='Cacophobia:BAAALAAECgMIAwAAAA==.',Ch='Chalis:BAAALAAECgYIDQAAAA==.Challen:BAABLAAECoEVAAIDAAcIuSA/EQBOAgADAAcIuSA/EQBOAgAAAA==.Cheezypoofs:BAAALAAECgcIDgAAAA==.Chimonkey:BAAALAAECgMIAwAAAA==.Chorn:BAAALAAECgQIBQAAAA==.',Ci='Ciderbear:BAAALAADCggICAAAAA==.Ciderbearr:BAAALAAECgcIDgAAAA==.Ciera:BAAALAADCgYIBgAAAA==.',Cl='Clambreath:BAAALAAECgcIDQAAAA==.',Co='Colecainee:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Cr='Crimsonbow:BAAALAADCgMIAwAAAA==.Crysis:BAAALAAECgcIDgAAAA==.',Cu='Cuddleßear:BAAALAADCggIDwAAAA==.',Da='Daddysixinch:BAABLAAECoEVAAIEAAgIEiRiBgAMAwAEAAgIEiRiBgAMAwAAAA==.Daelin:BAAALAAECgYICAAAAA==.',De='Dead:BAAALAADCgQIBAAAAA==.Deathblitz:BAAALAAECgcIEAAAAA==.Deathrite:BAAALAAECgIIAgAAAA==.Dejabrew:BAAALAADCgcIDQAAAA==.Deshal:BAAALAADCgcIBwAAAA==.Deäthrose:BAAALAAECgcIDQAAAA==.',Dh='Dhailos:BAAALAAECgIIAgABLAAECgIIAgABAAAAAA==.',Di='Dirtydisease:BAAALAADCgIIAgAAAA==.',Do='Doominatrix:BAAALAAECgcIDQAAAA==.Dopray:BAAALAAECgYICQAAAA==.',Dr='Dreadraven:BAAALAADCggIEQAAAA==.Dreadshamm:BAAALAAECgcIDgABLAADCggIEQABAAAAAA==.Dreckt:BAAALAAECgYICAAAAA==.Drip:BAAALAAECgMIAwAAAA==.Druidhams:BAAALAAECgcIDQAAAA==.',Eg='Egri:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.',Ek='Eku:BAAALAADCgUIBQAAAA==.',El='Electro:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.Elisha:BAAALAAECgEIAQAAAA==.Elowyn:BAAALAAECgIIAgABLAAECgYIDgABAAAAAA==.',Er='Eraqus:BAAALAADCgcIDQAAAA==.Erebostro:BAAALAAECgYICAAAAA==.',Ev='Evillux:BAAALAAECgcIEwAAAA==.',Ew='Ewie:BAAALAADCgcIBwAAAA==.',Ex='Exxonerate:BAAALAADCgcIBwAAAA==.',Ey='Eyeguy:BAAALAAECgUIBwAAAA==.',Fa='Fabulous:BAAALAAECgMIAwAAAA==.Fathercow:BAAALAAECgcIBwAAAA==.Fauxtotem:BAAALAAECgMIAwAAAA==.',Fe='Felwoven:BAAALAAECgQIBwAAAA==.',Fi='Fingies:BAAALAAECgYIDgAAAA==.',Fr='Frostfang:BAAALAADCggIDwAAAA==.Fry:BAAALAAECgYIDgAAAA==.',['Fë']='Fënn:BAAALAAECgcIDQAAAA==.',Ga='Gaijin:BAAALAAECgEIAgABLAAECgYIEAABAAAAAA==.Galaxsea:BAAALAAECgcIEAAAAA==.',Ge='Gerthquake:BAAALAAECgYIBwAAAA==.',Gh='Ghoul:BAAALAAECgMIBQAAAA==.',Go='Gobø:BAAALAADCgYIBgAAAA==.',Gr='Grima:BAAALAAECgcICwAAAA==.',Gu='Gulasher:BAAALAADCgYIBQABLAAECgMIBQABAAAAAA==.',He='Heimlichkeit:BAAALAADCggIEAAAAA==.',Ho='Homevoker:BAAALAADCggICAABLAADCgcIBwABAAAAAA==.Homlock:BAACLAAFFIEFAAMFAAMIJRC4CQCgAAAFAAIIsA24CQCgAAAGAAEIDhW3CQBYAAAsAAQKgRcABAUACAjVIvoKAJsCAAUABwglIPoKAJsCAAYABQgtJW4OAJUBAAcAAgi8Dx8dAJYAAAEsAAMKBwgHAAEAAAAA.Homly:BAAALAAECgQIBQABLAADCgcIBwABAAAAAA==.Homsorc:BAAALAADCgcIBwAAAA==.Hope:BAAALAAECgUIDAAAAA==.Hotwings:BAAALAADCgUIBQABLAAFFAIIAgABAAAAAA==.',['Hô']='Hôûnd:BAAALAADCgYIBgAAAA==.',Ic='Icons:BAAALAADCgcIBwAAAA==.',Id='Idun:BAAALAAECgIIAgAAAA==.',Il='Illiandray:BAAALAAECgcICwAAAA==.Ilswyn:BAAALAAECgYICAAAAA==.',In='Incredible:BAAALAAECgIIAgAAAA==.Infuséd:BAAALAADCgMIAwAAAA==.',Jo='Jonash:BAAALAADCggIDgAAAA==.',Jy='Jynn:BAAALAADCgcICAABLAAECgYIEAABAAAAAA==.',Ka='Kaalg:BAAALAADCgYIBwAAAA==.Katla:BAAALAAECgMIAwAAAA==.',Ke='Kestra:BAAALAAECgcIDgAAAA==.',La='Lazdrake:BAAALAAECgcIDgAAAA==.',Le='Leaddh:BAAALAADCgYIBgAAAA==.',Li='Lifewar:BAAALAADCgcIDQAAAA==.',Lu='Luciferr:BAAALAADCgEIAQAAAA==.Lukafox:BAACLAAFFIEFAAIIAAMIqxG9AgDiAAAIAAMIqxG9AgDiAAAsAAQKgRcAAggACAgnGMkQAC0CAAgACAgnGMkQAC0CAAAA.Lunchbox:BAAALAADCggICQABLAAECgYIEAABAAAAAA==.',Ma='Madoka:BAAALAADCggICAAAAA==.Maleficênt:BAAALAAECgcIEgAAAA==.Malira:BAAALAADCgYIDAAAAA==.Mardríft:BAAALAAECggIDwAAAA==.Maveric:BAAALAADCgYIBgAAAA==.',Me='Meowmix:BAAALAAECgYIDAAAAA==.Merus:BAAALAAECgIIAgABLAAECggIGAACAGkjAA==.Meteos:BAAALAADCgUIBQAAAA==.',Mi='Mick:BAAALAADCgcIDAABLAAECgMIBgABAAAAAA==.Mist:BAAALAAECgMIAwABLAAECgcIEgABAAAAAA==.',Mo='Moji:BAAALAAECgMIBQAAAA==.Monkjer:BAAALAAECgUIBQAAAA==.Monstermayi:BAAALAAECgcIDQAAAA==.Morteesha:BAAALAADCgUIBQABLAAECgYICAABAAAAAA==.',Mu='Muggyvagoo:BAAALAAECgMIAwAAAA==.',My='Mylër:BAAALAAECgQICQAAAA==.Myst:BAAALAAECgYIDQAAAA==.Mytastical:BAAALAAECgcIEAAAAA==.',['Mæ']='Mæve:BAAALAAECgcIDgAAAA==.',Na='Namalis:BAAALAAECgcIDgAAAA==.Nanielito:BAAALAAECgYIDgAAAA==.Nasir:BAAALAADCgYICQAAAA==.Nasty:BAAALAADCgcIBwAAAA==.',No='Nonae:BAAALAAECgcIEgAAAA==.Nosliw:BAAALAAECggICAAAAA==.',Om='Omagg:BAAALAADCgQIBAAAAA==.Omegá:BAAALAAECgcIDQAAAA==.Omerta:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.',Op='Optìmusprìme:BAAALAAECgYICAAAAA==.',Or='Ora:BAAALAADCgMIAwABLAAECgYIDgABAAAAAA==.Ordovic:BAAALAADCgcIBwAAAA==.',Pa='Papiblanco:BAAALAAECgYIDQAAAA==.Pawfu:BAAALAAECgcIEgAAAA==.',Pi='Pilo:BAAALAADCgcIAwAAAA==.',Pl='Planeteer:BAAALAADCgYIBgAAAA==.',Pr='Practice:BAAALAAECgYIEAAAAA==.',Ps='Psijic:BAAALAAECgIIAgAAAA==.Psychic:BAAALAADCgIIAgABLAAECgYIEAABAAAAAA==.',Qu='Quick:BAAALAAECgMIBQAAAA==.',Ra='Raddh:BAABLAAECoEXAAIJAAgIGSDYCADzAgAJAAgIGSDYCADzAgAAAA==.Ratha:BAAALAAECgcIEgAAAA==.',Re='Reaper:BAAALAAECgMIAwAAAA==.Reeb:BAAALAAECgQIBAAAAA==.',Rh='Rhettconn:BAAALAAECgIIAgAAAA==.',Ri='Ribbette:BAAALAADCgcIBwAAAA==.Rick:BAAALAAECgYICwAAAA==.',Ro='Rokomah:BAAALAADCggICAAAAA==.',Ru='Runa:BAAALAADCggIDgAAAA==.',Sa='Saereus:BAAALAADCggICQAAAA==.',Se='Segfault:BAAALAADCggIEgAAAA==.',Sh='Shailos:BAAALAAECgIIAgAAAA==.Shmadu:BAAALAAECgYICQAAAA==.Shockk:BAAALAAECgQIBgAAAA==.',Sk='Skoochie:BAAALAADCgcIBwAAAA==.',Sl='Slithicious:BAAALAAECgMIBQAAAA==.Slithisis:BAAALAAECgMIAwAAAA==.',Sm='Smeeb:BAAALAADCgcIBwAAAA==.',So='Sona:BAAALAAECgYICAAAAA==.Sonen:BAAALAAECgYICQAAAA==.Soola:BAAALAAECgMIAwAAAA==.',Sp='Spoof:BAAALAADCgYIBgAAAA==.Sprigg:BAABLAAECoEUAAMKAAcIBxGjLQCyAQAKAAcIBxGjLQCyAQALAAMILhDPJAC7AAAAAA==.Spritze:BAAALAADCgcIAQAAAA==.',St='Stepbro:BAAALAADCgcIDQAAAA==.Stonedpriest:BAAALAAECgYIEgAAAA==.',Sy='Syllubear:BAAALAAECgcIDQAAAA==.Sylvanäs:BAAALAADCgcIBwABLAAECgcICwABAAAAAA==.',Ta='Tahlreth:BAAALAAECgYICAAAAA==.Tanidgetotem:BAAALAAECgUICAAAAA==.Tanth:BAAALAADCgcIBwAAAA==.Tayanna:BAAALAADCgcIDAAAAA==.',Te='Teias:BAAALAAECgcIEgAAAA==.Tersus:BAAALAAECgYICgAAAA==.',Ti='Tigerscale:BAAALAADCgIIAgAAAA==.Tirence:BAAALAAECgcIDQAAAA==.',To='Toesham:BAAALAAECgYIDgAAAA==.Tongar:BAAALAADCggIBgAAAA==.Toohotforyou:BAAALAAECgcICgAAAA==.Toòthbrush:BAAALAAECggIEAAAAA==.',Tr='Tricko:BAAALAAECgYICwAAAA==.Trollidan:BAAALAAECgYICAAAAA==.Trollskingx:BAAALAAECgYICQAAAA==.Trunkmonkey:BAAALAAECgEIAQAAAA==.',Ts='Tsaagan:BAAALAAECgcIDQAAAA==.',Tu='Tuona:BAAALAADCgEIAQABLAAECgcIDQABAAAAAA==.Turdferguson:BAAALAAECgYIDQAAAA==.',Un='Unseeing:BAAALAADCggIFQAAAA==.',Va='Valkyruid:BAAALAAECgcIEgAAAA==.Varaxis:BAAALAADCgcIBwAAAA==.',Ve='Veledreyssa:BAAALAADCgcIDQAAAA==.',Vr='Vrðr:BAAALAADCgEIAQAAAA==.',Vz='Vza:BAAALAAECgcIEAAAAA==.',Wa='Waitnbleed:BAAALAAECgcIDQAAAA==.',Wi='Wiccaflame:BAAALAAECgcIDgAAAA==.',Wu='Wulgan:BAAALAAECgMIBAAAAA==.',Xe='Xencure:BAAALAAECgYICQAAAA==.Xerk:BAAALAAECgcIEgAAAA==.',Xy='Xybos:BAAALAAECgYICAAAAA==.',Ya='Yareli:BAAALAAECgMIAwAAAA==.',Ys='Yseria:BAAALAAECgMIBgAAAA==.',Za='Zaezar:BAAALAAECgUICAAAAA==.',Ze='Zekröm:BAAALAAECgMIAwABLAAECgcIEgABAAAAAA==.Zetetic:BAAALAAECgMIBAABLAAECgYIDgABAAAAAA==.Zez:BAAALAAECgIIAwABLAAECgUICAABAAAAAA==.Zezer:BAAALAADCggICAAAAA==.',Zi='Zinbar:BAAALAAECgIIAgAAAA==.',Zu='Zune:BAAALAAECgcIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end