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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination',}; local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Aceroth:BAAALAAECgMIAwAAAA==.Achnologia:BAAALAAECgQIBwAAAA==.',Ad='Adarus:BAAALAAECgMIAwAAAA==.',Ae='Aelin:BAAALAAECgcIDQAAAA==.',Ah='Ahlarian:BAAALAADCgYIBgAAAA==.',Al='Alaysia:BAAALAAECgYICQAAAA==.Alestair:BAAALAAECgEIAQAAAA==.Alexsandra:BAAALAADCgcIDQAAAA==.',An='Anbu:BAAALAADCgYICwABLAAECgMIAwABAAAAAA==.Angrä:BAAALAADCgYIEAAAAA==.Anja:BAAALAADCgYIBgAAAA==.',Ar='Arrethyn:BAAALAAECgUICQAAAA==.Arrowsmith:BAAALAADCgcIFQAAAA==.',Az='Azaelara:BAAALAAECgMIAwAAAA==.',Ba='Babelez:BAAALAADCgcIDgAAAA==.Badgerlord:BAAALAAECgQIBAAAAA==.Barbatosrex:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.',Be='Beauvine:BAAALAAECgYICQAAAA==.',Bi='Bigbootydood:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.',Bl='Blitzkrîeg:BAAALAAECgIIAgAAAA==.Blpbusty:BAAALAADCgMIAwAAAA==.',Bo='Bobsalami:BAAALAAECgYICQAAAA==.',Br='Breezysham:BAAALAAECgQIBAAAAA==.Brightblade:BAAALAAECgcIEQAAAA==.',Bu='Bubonic:BAAALAAECgMIBgAAAA==.Bumblebetuna:BAAALAADCgcIDQAAAA==.',Ch='Chainhealman:BAAALAADCgEIAQAAAA==.Chickynuggy:BAAALAAECgMIBgAAAA==.Chillypickle:BAAALAAECgMIBgAAAA==.',Cl='Cloudcaller:BAAALAADCggIFwAAAA==.',Co='Cobrakai:BAAALAADCggICAAAAA==.',Cr='Cripticwrath:BAAALAADCgEIAQAAAA==.',Cu='Curse:BAAALAAECgMIAwAAAA==.',['Cö']='Cöunter:BAABLAAECoEYAAICAAgIyiXyAQBqAwACAAgIyiXyAQBqAwAAAA==.',Da='Dairydefendr:BAAALAAECgMIAwAAAA==.Damyn:BAAALAAECgQIBQAAAA==.',De='Deadish:BAAALAADCggICwABLAAECgMIBQABAAAAAA==.Dedicated:BAEALAAECgYICQAAAA==.Demark:BAAALAAECgQIAwAAAA==.Dergara:BAAALAAECgEIAQAAAA==.Devana:BAAALAAECgMIAwAAAA==.Devman:BAAALAAECgcIEQAAAA==.Dezzolation:BAAALAADCggICwAAAA==.',Dj='Djcaster:BAAALAAECgYICgAAAA==.',Do='Dodgeroach:BAAALAAECgcIEQAAAA==.Doody:BAAALAAECgcIEAAAAA==.',Dr='Drîxx:BAAALAAECgQIBAAAAA==.',Du='Dumblesnore:BAAALAADCgcIBwAAAA==.Durutan:BAAALAADCggIDQAAAA==.',Ea='Easypeasey:BAAALAADCgUIBQAAAA==.',Ei='Eitru:BAAALAAECgYICwAAAA==.',El='Electricardo:BAAALAAECgYICAAAAA==.Ellaide:BAAALAAECgUIBwAAAA==.',Et='Etreum:BAAALAADCggICAAAAA==.',Fa='Fatrolls:BAAALAADCggICAAAAA==.Faxelx:BAAALAADCgcIBwAAAA==.',Fe='Felbane:BAAALAADCggICAAAAA==.Felygos:BAABLAAECoEWAAMDAAgIpyKsAwAwAgAEAAcIPh39CQCGAgADAAYIDx+sAwAwAgAAAA==.',Fl='Flanuora:BAAALAADCggIEgAAAA==.',Fo='Fooksdk:BAAALAAECgQIBAAAAA==.Fooksdruid:BAAALAAECgMIAwAAAA==.Fookswarlock:BAAALAAECgMIAwAAAA==.Foxx:BAAALAAECggIBwAAAA==.',Fr='Freshpickle:BAAALAADCgUIBQAAAA==.Frick:BAAALAAECgMIBQAAAA==.',Fw='Fwank:BAAALAADCggIDwAAAA==.',Ga='Galaxus:BAAALAADCggICAAAAA==.Galstad:BAAALAAECgYICgAAAA==.',Gg='Ggangrel:BAAALAADCgUIBQABLAADCgcICAABAAAAAA==.',Gi='Gisokaashi:BAAALAADCggIDQAAAA==.',Gk='Gkeegkeegkee:BAAALAAECgMIBQAAAA==.',Go='Goobling:BAAALAAECgIIAgAAAA==.',Gr='Gradywhite:BAAALAAECgUIBQAAAA==.Griffin:BAAALAADCgcICAAAAA==.Gromguts:BAAALAADCgYIBgAAAA==.',Gw='Gwimace:BAAALAADCggIDgAAAA==.',Ha='Hamicks:BAAALAADCgMIAwAAAA==.Happyflappy:BAAALAAECgQIBAABLAAECgYICAABAAAAAA==.Happylights:BAAALAAECgYICAAAAA==.Harambe:BAAALAADCgQIBAABLAAECgcIEAABAAAAAA==.Hawtee:BAAALAADCgIIAgAAAA==.',He='Heilung:BAAALAAECgcIEQAAAA==.',Hi='Hirradee:BAAALAAECgMIBgAAAA==.',Hy='Hygea:BAAALAAECgEIAQAAAA==.',Ic='Icecweam:BAAALAADCgIIAgAAAA==.Ichigo:BAAALAAECgEIAQAAAA==.Icthelight:BAAALAAECgYICAAAAA==.',Ih='Ihavebeef:BAAALAADCgYIDAABLAAECgcIEQABAAAAAA==.',Is='Ishkur:BAAALAADCggIDAABLAAECgMIAwABAAAAAA==.',Iz='Izuala:BAAALAADCgYIBgAAAA==.',Ja='Jayar:BAAALAADCgYIBgAAAA==.Jayton:BAAALAADCgcIDgABLAAECgQIBAABAAAAAA==.',Je='Jeem:BAAALAAECgMIAwAAAA==.Jenn:BAAALAAECggIBgAAAA==.',Jo='Joesepi:BAAALAADCgcIBwAAAA==.Jom:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.',Ka='Kaijin:BAAALAAECgIIAgAAAA==.Kandrianna:BAAALAAECgIIAgAAAA==.',Ki='Kilrav:BAAALAADCgEIAQAAAA==.Kiryanna:BAAALAADCgYIBgAAAA==.',Kl='Klaya:BAAALAADCgIIAgAAAA==.Klayah:BAAALAADCgQIBAAAAA==.Klaytana:BAAALAAECgMIBgAAAA==.',Kn='Kniveshadows:BAAALAADCgEIAQAAAA==.',Ko='Koogrr:BAAALAAECgMIBAAAAA==.Koogs:BAAALAAECgIIAgAAAA==.Kordelia:BAAALAADCggIDgABLAAECgMIAwABAAAAAA==.',Kr='Kryptiq:BAAALAADCgcICgAAAA==.',La='Lazye:BAAALAADCgQIAwAAAA==.Lazykitty:BAAALAADCgIIAgAAAA==.',Le='Levi:BAAALAADCgQIBAAAAA==.',Li='Liadrin:BAAALAAECgMIBAAAAA==.Liftoras:BAAALAADCgcIBwAAAA==.Lilshout:BAAALAAECgYIBgAAAA==.Littlefaith:BAAALAADCgMIAwAAAA==.',Ll='Llillies:BAAALAADCgcICQAAAA==.',Lo='Loor:BAAALAADCgcIBwAAAA==.',Lu='Lucinarose:BAAALAADCggIDwAAAA==.Lucinia:BAAALAAECgMIBAAAAA==.Lunapriest:BAAALAADCggICQAAAA==.',Ma='Madcuzbad:BAAALAAECgEIAQAAAA==.Magebuff:BAAALAAECgMIAwAAAA==.Marjella:BAAALAADCggIDQAAAA==.',Mc='Mcheals:BAAALAAECgQIBAAAAA==.',Mi='Midnytstorm:BAAALAADCggICAAAAA==.Milkmannte:BAAALAADCgcIBwAAAA==.Miso:BAAALAADCgEIAQAAAA==.',Mo='Moogar:BAAALAAECgMIAwAAAA==.',Mu='Muskricardo:BAAALAADCgMIAwAAAA==.',Na='Narcyon:BAAALAAECgYICgAAAA==.Nardoric:BAAALAAECgIIAgAAAA==.',Nc='Ncplbighoof:BAAALAADCgcIBwAAAA==.',No='Nogard:BAEALAADCgMIAwABLAAECgYICQABAAAAAA==.Noobîtîs:BAAALAAECgIIAgAAAA==.Norcron:BAAALAAECgEIAgAAAA==.',Oh='Ohrion:BAAALAAECgIIAgAAAA==.',Op='Optomee:BAAALAADCgcICgAAAA==.',Pa='Padi:BAAALAAECgMIBQAAAA==.Palykid:BAAALAAECgcIDQAAAA==.',Pe='Pelco:BAAALAAECgMIAwAAAA==.Pelondar:BAAALAADCgQIBAAAAA==.Pennlad:BAAALAAECgEIAQAAAA==.Peppermint:BAAALAAECgYICwAAAA==.',Po='Posie:BAAALAADCgYIBgAAAA==.Possessed:BAAALAAECgEIAQAAAA==.',Pr='Prídé:BAAALAADCgcIEAAAAA==.',Pu='Pulmypigtail:BAAALAAECgIIAgAAAA==.',Ra='Rawrina:BAAALAAECgQIBAAAAA==.Rayven:BAAALAAECgYICQAAAA==.',Re='Reepper:BAAALAAECgIIAgAAAA==.Relein:BAAALAAECgIIAgAAAA==.',Rh='Rhyvaugn:BAAALAADCgMIAQAAAA==.',Ri='Rinji:BAAALAAECgQIBwAAAA==.Risto:BAAALAAECgMIAwAAAA==.Riveir:BAAALAADCgEIAQAAAA==.',Ro='Ronzertnin:BAAALAAECgMIAwAAAA==.Roody:BAAALAAECgEIAQABLAAECgcIEAABAAAAAA==.Roofman:BAAALAAECgMIBgAAAA==.',['Rä']='Rävënna:BAAALAADCggIDgAAAA==.',Sa='Sarah:BAAALAAECgcIEQAAAA==.',Sc='Scarlêt:BAAALAADCgYIBgAAAA==.',Sh='Shadowhoblin:BAAALAAECgcIDQAAAA==.Shadowshift:BAAALAADCgcIBwAAAA==.Shaldorei:BAAALAADCgcIDgAAAA==.Shapeshifte:BAAALAAECgEIAQAAAA==.Shinerbock:BAAALAAECgMIAwAAAA==.Shock:BAAALAAECgEIAgAAAA==.Shocktop:BAAALAADCggIEAAAAA==.',Sk='Skipharls:BAAALAAECgQIBAAAAA==.',Sm='Smacksthat:BAAALAAECgMIBgAAAA==.',So='Sorrowgrave:BAAALAADCgUIBQAAAA==.Soulofarc:BAAALAAECgcIDQAAAA==.',Su='Success:BAEALAAECgIIAgABLAAECgYICQABAAAAAA==.',Te='Tehblink:BAAALAAECgIIAgAAAA==.',Th='Thane:BAAALAAECgMIAwAAAA==.Thathnda:BAAALAADCgcIBwAAAA==.',To='Toomez:BAAALAADCggICAAAAA==.',Us='Usopp:BAAALAADCgMIAwAAAA==.',Va='Vampire:BAAALAAECgIIAgAAAA==.',Ve='Velea:BAAALAADCgYIBgAAAA==.Vespera:BAAALAADCggIDAAAAA==.',Wa='Wacko:BAAALAAECgMIAwAAAA==.Wafflecake:BAAALAAECgcIDgAAAA==.Warcrimez:BAAALAAECgEIAQAAAA==.Warpstone:BAAALAADCggIDQAAAA==.',Wh='Wheresmypet:BAAALAADCggIDgAAAA==.',Wo='Worlock:BAAALAAECgIIAgAAAA==.',Xa='Xaxii:BAAALAADCgYIBgABLAAECgMIBgABAAAAAA==.',Ye='Yeehaw:BAAALAADCgUIBQAAAA==.',Yo='Yolandeve:BAAALAAECgYICQAAAA==.',Ys='Ysayle:BAAALAAECgMIAwAAAA==.',Za='Zandragon:BAAALAADCgYIBgAAAA==.Zanial:BAAALAADCgcIBwABLAAECgUICQABAAAAAA==.',Ze='Zenro:BAAALAAECgEIAQAAAA==.',Zi='Zina:BAAALAADCgcIBwAAAA==.',['Ðu']='Ðumo:BAAALAAECgYICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end