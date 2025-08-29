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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','DemonHunter-Havoc','Warrior-Fury',}; local provider = {region='US',realm='Misha',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acidburn:BAAALAAECgcIDwAAAA==.',Ah='Ahndrumon:BAAALAADCgcIBwAAAA==.',Ai='Airwaves:BAAALAAECggICgAAAA==.',Al='Albedorouge:BAAALAADCgEIAQAAAA==.Alendria:BAAALAADCgYICQAAAA==.Alorillan:BAAALAAECgIIAgAAAA==.Altair:BAAALAAECgUIBgAAAA==.',Am='Amaroo:BAAALAAECgYICQAAAA==.',An='Anneck:BAAALAAECgMIBQAAAA==.',Ap='Appless:BAAALAAECgYIBgAAAA==.',Aq='Aquareina:BAAALAADCggIEgAAAA==.',Ar='Aridella:BAAALAAECgcICwAAAA==.Aristor:BAAALAADCgUICAAAAA==.Arkenea:BAAALAADCgUIBQAAAA==.',As='Asumi:BAAALAADCgQIBAAAAA==.',Au='Audros:BAAALAADCgMIAwAAAA==.',Av='Averry:BAAALAADCgcIBwAAAA==.',Az='Azusie:BAAALAAECgIIBQAAAA==.',Ba='Baddate:BAAALAADCgUICQAAAA==.Baddragøn:BAAALAAECgYICQAAAA==.Badkeenie:BAAALAADCggIHQAAAA==.Badmood:BAAALAADCgYIBwAAAA==.Baldina:BAAALAADCggICAAAAA==.Baldine:BAAALAADCgcIBwAAAA==.Balthinator:BAAALAAECgYICQAAAA==.Bastria:BAAALAAECgQIBAAAAA==.',Be='Beenn:BAAALAADCgMIAwAAAA==.',Bi='Billywitchdr:BAAALAAECgYICQAAAA==.Bipolarbear:BAAALAADCgMIAwAAAA==.',Bl='Bluetoykawi:BAAALAAECgYICwAAAA==.',Bo='Boltspark:BAAALAADCggIDwAAAA==.Bossofsauce:BAAALAAECgYIDwAAAA==.Bounces:BAAALAADCgMIAgAAAA==.Bozilla:BAAALAADCgMIAwAAAA==.',Bu='Bussypiper:BAAALAADCgYIBgAAAA==.',Ca='Cawksuquah:BAAALAAECgMIAwAAAA==.',Ch='Charbaby:BAAALAAECgcIDAAAAA==.',Co='Contrlurself:BAAALAADCgIIAgAAAA==.',Cu='Cubesly:BAAALAAECgMIAwAAAA==.',Cy='Cyonna:BAAALAADCgcIBwAAAA==.',Da='Dadghar:BAAALAADCgEIAQAAAA==.Darkestwish:BAAALAADCgMIAwAAAA==.Darkfoxgrime:BAAALAAECgYICgAAAA==.Darkjager:BAAALAAECgcIDgAAAA==.Darlah:BAAALAAECgEIAQAAAA==.Dawnbreaker:BAAALAADCggIFQAAAA==.',De='Deadmetal:BAAALAADCgQIBAAAAA==.Deathbean:BAAALAADCgUIBwABLAADCggIFQABAAAAAA==.',Di='Dilea:BAAALAADCggIGAAAAA==.',Do='Docblade:BAAALAADCggICwAAAA==.Donangus:BAAALAAECgMIAwAAAA==.',Dr='Dracomyst:BAAALAAECgQIBQAAAA==.Dread:BAAALAADCgcIBwAAAA==.',Dv='Dvsmage:BAAALAADCgEIAQABLAADCggIFQABAAAAAA==.',['Dí']='Díscø:BAAALAAECgYICgAAAA==.',El='Elarred:BAAALAADCggIDQAAAA==.Elisepoo:BAAALAAECgIIAgAAAA==.Ellwin:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',Em='Emridion:BAAALAAECgMIBAABLAAECgcIDwABAAAAAQ==.',En='Endeaver:BAAALAAECgYICgAAAA==.Ennox:BAAALAAECgMIBAAAAA==.',Ep='Epifany:BAAALAAECgQIBwAAAA==.',Fe='Felhound:BAAALAADCggICwAAAA==.',Fi='Finhead:BAAALAAECgUICAAAAA==.Firereina:BAAALAADCgYICwABLAADCggIEgABAAAAAA==.',Fl='Flarixi:BAAALAADCgQIBAAAAA==.Fleurminator:BAAALAAECgYICgAAAA==.',Fr='Frieia:BAAALAADCggIFQAAAA==.Frostiilocks:BAAALAAECgEIAQAAAA==.Frostitüte:BAAALAADCgEIAQABLAAECgYICgABAAAAAA==.',Fu='Fubuki:BAAALAADCggIEAAAAA==.Fupasniffer:BAAALAADCggIEQABLAAECgEIAQABAAAAAA==.Furrypelt:BAAALAADCgcIDQAAAA==.',Ga='Galahad:BAAALAAECggIAQAAAA==.Galarína:BAAALAAECgQIBwAAAA==.Gandora:BAAALAAECgYICgAAAA==.Gangrene:BAAALAADCgYIBgAAAA==.',Ge='Gentonord:BAAALAAECgcIEgAAAA==.',Gl='Glym:BAAALAAECgEIAQAAAA==.',Go='Gogoat:BAAALAADCgMIAwAAAA==.Gorthaur:BAAALAADCggIFwAAAA==.',Gr='Grassmön:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Greasemunky:BAAALAADCggIDwAAAA==.Griiv:BAABLAAECoEYAAICAAgIZyWlBAA4AwACAAgIZyWlBAA4AwAAAA==.Grislyflock:BAAALAAECgYICQAAAA==.',['Gð']='Gðn:BAAALAADCgcIDwAAAA==.',Ha='Hairymartini:BAAALAADCgcIBwAAAA==.Hana:BAAALAAECgMIBAAAAA==.Haymáker:BAAALAADCgcIBwAAAA==.',He='Heights:BAAALAADCgMIAwAAAA==.Heyu:BAAALAAECgMIAwAAAA==.',Ho='Holycrime:BAAALAADCgEIAQAAAA==.Holyhench:BAAALAAECgcIDQAAAA==.Horick:BAAALAADCgUICAAAAA==.',Hr='Hrsho:BAAALAAECgQIBAAAAA==.Hrshoo:BAAALAAECgYIDAAAAA==.',Ic='Icerage:BAAALAADCggICAAAAA==.',Ik='Ike:BAAALAADCggIDgAAAA==.',Il='Illumi:BAAALAAECgUIBwAAAA==.',In='Infernum:BAAALAAECgcIDwAAAQ==.',Iz='Izzyf:BAAALAADCgcIBwAAAA==.',Ja='Jared:BAAALAADCgMIAwAAAA==.',Jo='Jollibee:BAAALAAECgEIAQAAAA==.',Ka='Kaietsuka:BAAALAADCgQIBAAAAA==.Kalzious:BAAALAADCggICgAAAA==.',Ke='Kelana:BAAALAAECgYIDAAAAA==.',Ki='Kitsuney:BAAALAADCgcIDgAAAA==.',Kn='Knaughty:BAABLAAECoEbAAIDAAgIyBtxEACMAgADAAgIyBtxEACMAgAAAA==.',Kr='Krÿg:BAAALAADCgIIAgAAAA==.',Ky='Kyleata:BAAALAAECgUIDwAAAA==.Kyzula:BAAALAADCggIEAAAAA==.',La='Laytone:BAAALAADCgcIEwAAAA==.',Li='Lilygoesboom:BAAALAADCgYIBgAAAA==.Lilylocks:BAAALAAECgIIAQAAAA==.',Lu='Lucintov:BAAALAADCgQIBAABLAADCggICwABAAAAAA==.',Ly='Lyanah:BAAALAAECgYICQAAAA==.',['Lú']='Lúcifér:BAAALAADCgcIDAAAAA==.',Ma='Maggrus:BAAALAAECgIIBAABLAAECgMIAwABAAAAAA==.Malical:BAAALAAECgMIBwAAAA==.Malor:BAAALAADCgQIBQAAAA==.Manshoon:BAAALAADCgcIBwAAAA==.',Mc='Mcden:BAAALAADCgIIAgAAAA==.Mctubby:BAAALAADCgUIBQAAAA==.',Me='Meigz:BAAALAADCgUICAAAAA==.Melinda:BAAALAADCgcIDgAAAA==.Meowa:BAAALAAECgEIAQAAAA==.Metalicana:BAAALAAECgcICQAAAA==.',Mi='Mikaeljayfox:BAAALAAECgcIDQAAAQ==.Miyawaki:BAAALAADCgIIAgAAAA==.',Mo='Monetta:BAAALAADCgYIBgAAAA==.Moonblood:BAAALAADCggICwABLAAECgMIAwABAAAAAA==.Moons:BAAALAAECgMIAwAAAA==.Moontann:BAAALAADCgYIBgAAAA==.Motown:BAAALAADCgQIBAAAAA==.',Mu='Murdalok:BAAALAAECgMIBAAAAA==.Murderousish:BAAALAAECgMIAwAAAA==.',My='Mysterioñ:BAAALAADCgYICQAAAA==.',Na='Nagara:BAAALAAECgEIAQAAAA==.Nancydrew:BAAALAADCgcIBgAAAA==.Natstryker:BAAALAAECgYICwAAAA==.Naturemyth:BAAALAADCggICQAAAA==.',Nb='Nbayoungboy:BAAALAAECggICAAAAA==.',Ni='Nir:BAAALAAECgcICgAAAA==.',Og='Ogmudbone:BAAALAADCgMIAwAAAA==.',Oh='Ohbadhi:BAAALAADCgcIBwAAAA==.',Or='Organa:BAAALAADCggIFQAAAA==.',Ou='Outofthedark:BAAALAADCgcIBwAAAA==.',Pl='Plowmcballs:BAAALAAECgMIAwAAAA==.Plumpduck:BAAALAADCggICAAAAA==.',Po='Potooòooóoo:BAAALAAECgcICQAAAA==.',Pr='Prime:BAAALAAECgYICQAAAA==.',Pu='Purin:BAAALAAECgMIAwAAAA==.',['Pë']='Përdü:BAAALAADCggICwAAAA==.',Ra='Raethu:BAAALAADCggIGAAAAA==.Ratapew:BAAALAADCggICwAAAA==.Rayinator:BAAALAAECgIIAwAAAA==.',Re='Redmon:BAAALAADCgMIAwAAAA==.Reignne:BAAALAADCgcIBwAAAA==.Resusc:BAAALAADCggICQAAAA==.',Ri='Rivergem:BAAALAADCggIFwAAAA==.',Ro='Roguerash:BAAALAAECgYICwAAAA==.Rogun:BAAALAADCggIFwAAAA==.Rokmora:BAAALAAECgYICgAAAA==.Roxoxoxanne:BAAALAADCgEIAQAAAA==.',Ru='Rug:BAAALAAECgYICgAAAA==.Rustybray:BAAALAAECgYICQAAAA==.',Ry='Ryvulz:BAAALAADCgcIBwAAAA==.',Sa='Sangol:BAAALAAECgQIBwAAAA==.',Se='Sena:BAAALAAECgEIAQAAAA==.Serendipity:BAAALAADCgUIBQAAAA==.Sernoob:BAAALAAECgEIAQAAAA==.',Sh='Shadowgiant:BAAALAADCgUIBQAAAA==.Shalalia:BAAALAADCgcIBwAAAA==.Shanori:BAAALAAECgIIAwAAAA==.Shinsha:BAAALAADCgcIFAAAAA==.Shnizelnazee:BAAALAAECgMIBAAAAA==.Shänks:BAAALAAECgcICgAAAA==.',Si='Silik:BAAALAADCgUICAAAAA==.',Sk='Skybladee:BAAALAAECgIIAgAAAA==.',Sl='Slaymen:BAAALAADCgUIBQAAAA==.',Sm='Smelo:BAAALAAECgUICAAAAA==.Smerlin:BAAALAAECgIIAgAAAA==.',Sn='Sneevie:BAAALAAECgYICQAAAA==.Snorehees:BAAALAAECgIIAwAAAA==.',So='Songstar:BAAALAAECgYICgAAAA==.Soullraven:BAAALAADCgcICwAAAA==.Soulzpally:BAAALAADCgYIBgAAAA==.',St='Starblaze:BAAALAAECgMIAwAAAA==.Stopdropnbop:BAAALAADCgIIAgAAAA==.',Su='Sugarhoof:BAAALAADCgYIDwAAAA==.',Sy='Synman:BAAALAADCgUICgAAAA==.Syntheria:BAAALAADCgYIBgAAAA==.',Te='Telantre:BAAALAADCgcIBwABLAAECgcIDwABAAAAAQ==.',Th='Tharion:BAAALAADCggIFQAAAA==.Thedvsbean:BAAALAADCggIFQAAAA==.Thesarius:BAAALAAECgMIBAAAAA==.',Ti='Tinatwofeet:BAAALAADCggICAAAAA==.Tinfizzle:BAAALAADCgEIAQAAAA==.',To='Tockley:BAAALAADCgcIBwAAAA==.Tofino:BAAALAADCggICAAAAA==.Tonimâster:BAAALAADCgcICQAAAA==.Totemlyawsom:BAAALAADCgcIBwAAAA==.',Tr='Traps:BAAALAADCgMIAwAAAA==.Trenbologna:BAAALAADCggICwAAAA==.Trill:BAAALAADCgQIBAAAAA==.',Ty='Tyindron:BAAALAADCggIDgAAAA==.Tyshus:BAAALAADCggICAAAAA==.',Va='Valarion:BAAALAAECgYICgAAAA==.Valorían:BAAALAAECgYICwAAAA==.Vanza:BAAALAADCgUICAAAAA==.Varcos:BAAALAADCgEIAQAAAA==.Varthayn:BAAALAAECgMIBwAAAA==.',Ve='Verinferno:BAAALAADCgUIBQAAAA==.Verrá:BAAALAAECgMIAwAAAA==.',Vo='Volbain:BAAALAAECgEIAQAAAA==.',Vu='Vulpsinculta:BAAALAADCggIFQAAAA==.',Vy='Vynderoth:BAAALAADCgYIBgAAAA==.',Wa='Wasntmee:BAAALAADCgYIBgAAAA==.',Wi='Wichitwo:BAAALAAECgYICQAAAA==.Wickedwayz:BAAALAAECggICAAAAA==.Winnythebrew:BAAALAADCgcIDAAAAA==.',Wt='Wtfguën:BAAALAADCggIFQAAAA==.Wtfkaidã:BAAALAADCgUIBQABLAADCggIFQABAAAAAA==.Wtftiffany:BAAALAADCgMIAwABLAADCggIFQABAAAAAA==.',Wu='Wutäng:BAAALAADCgYIBgAAAA==.',Ya='Yarria:BAAALAADCggIFwAAAA==.',Yi='Yinh:BAAALAADCggIFwAAAA==.',Zu='Zug:BAABLAAECoEVAAIEAAgIuBaJEwAyAgAEAAgIuBaJEwAyAgAAAA==.',['Än']='Ängron:BAAALAAECgQIBgAAAA==.',['Ço']='Çonstantíne:BAAALAADCggIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end