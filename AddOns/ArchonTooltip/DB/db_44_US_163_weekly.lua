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
 local lookup = {'Paladin-Holy','Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Druid-Feral','Paladin-Retribution','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Warrior-Fury','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','Priest-Discipline','Priest-Shadow','Druid-Restoration','Rogue-Outlaw',}; local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=44,date='2025-08-29',data={Ag='Aggro:BAAALAADCgUIBgAAAA==.',Al='Alailea:BAAALAAECgcIDwAAAA==.',Am='Amazabloom:BAAALAADCgcIBwAAAA==.Amazadin:BAABLAAECoEZAAIBAAgIcRH7DAD4AQABAAgIcRH7DAD4AQAAAA==.Amazashock:BAAALAADCggIDwAAAA==.',An='Andromalius:BAAALAADCgcIBwAAAA==.Anzul:BAAALAADCgcIDAAAAA==.',As='Astraloud:BAAALAADCgYICQABLAAECgMIAwACAAAAAA==.',Au='Aubbrey:BAAALAAECgYIBgAAAA==.',Ba='Bamboo:BAAALAADCggICAAAAA==.',Be='Bearforceone:BAAALAADCgcICAAAAA==.Benzmonk:BAAALAAECgcIDAAAAA==.',Bh='Bhullistic:BAAALAADCgEIAQAAAA==.',Bi='Bianka:BAAALAAECgcICAAAAA==.Bigusdixus:BAAALAAECgIIAgAAAA==.',Bl='Blakitoa:BAAALAAECgQIBQAAAA==.',Br='Bringer:BAAALAADCggIDgAAAA==.',Bu='Bussiah:BAAALAAECgQIBAAAAA==.',Ca='Cadbury:BAAALAADCggICAABLAADCggICAACAAAAAA==.Canestoast:BAAALAAECgEIAQAAAA==.Cantona:BAAALAADCgMIAwAAAA==.',Ce='Celum:BAAALAADCgcIBwAAAA==.',Ch='Chaw:BAABLAAECoEWAAQDAAgIMh+4DgAjAgADAAcISRq4DgAjAgAEAAcISBr7GQANAgAFAAEImg3wCwBJAAAAAA==.Chenkenichi:BAAALAADCgcIDgAAAA==.Chronixss:BAAALAADCgQIBwAAAA==.',Ci='Cityairlines:BAAALAAECgYICgAAAA==.',Co='Cooldukenuke:BAAALAAECgYIDgAAAA==.Cosmo:BAAALAAECgQIBAAAAA==.',Cr='Creepychalk:BAAALAADCggIDwAAAA==.',Cu='Cursedshape:BAABLAAECoEWAAIGAAgI9yLRAAA8AwAGAAgI9yLRAAA8AwAAAA==.',Da='Daenessa:BAAALAADCgcIBwAAAA==.Daggy:BAAALAADCgIIAgAAAA==.Danit:BAAALAADCgEIAQAAAA==.',De='Deacon:BAAALAADCgQIBgABLAAECgMIAwACAAAAAA==.Dejavu:BAAALAAECgcIDwAAAA==.Delerium:BAAALAADCggICgABLAAECgMIAwACAAAAAA==.Demonicsoulx:BAAALAADCgcIBwAAAA==.Deppthcharge:BAAALAADCgQIBAAAAA==.',Di='Dispal:BAAALAADCgYIBgABLAAECgYIBgACAAAAAA==.Dissin:BAAALAAECgYIBgAAAA==.',Dr='Drathanbourn:BAAALAADCgEIAQAAAA==.',Ea='Eatchìken:BAAALAADCgcICAABLAAECgYIDQACAAAAAA==.',Eg='Egohakai:BAABLAAECoEWAAIHAAgIbCMcBQAwAwAHAAgIbCMcBQAwAwAAAA==.',Em='Emieretta:BAAALAAECgcIEAAAAA==.',En='Enfurion:BAAALAADCggICAAAAA==.',Er='Erret:BAABLAAECoEWAAIIAAgIyB36AwDIAgAIAAgIyB36AwDIAgAAAA==.Erreth:BAAALAAECgYICQABLAAECggIFgAIAMgdAA==.',Et='Eth:BAAALAAECgYIBgAAAA==.Ethel:BAAALAADCgcIBwAAAA==.',Ey='Eyebeam:BAAALAAECgYICgAAAA==.',Ez='Ezinder:BAAALAAECgEIAgAAAA==.',Fa='Falorina:BAAALAAECgQIBwAAAA==.Fathernature:BAAALAAECgYIDgAAAA==.Fauna:BAAALAADCgcICAAAAA==.Fazeup:BAAALAAECgYIBwAAAA==.',Fe='Feldra:BAAALAAECgYICwAAAA==.Felfaith:BAAALAADCggIDgAAAA==.',Fi='Fiddles:BAAALAAECgQIBAAAAA==.Finnin:BAAALAAECgYICAAAAA==.',Fl='Florbus:BAAALAADCggICAAAAA==.',Fo='Foxxybrown:BAAALAAECgMIBQAAAA==.',Fr='Freidafondle:BAAALAAECgIIAgAAAA==.',Fu='Furioushealz:BAAALAAECgMIBwAAAA==.Furybolt:BAAALAADCgcIDgAAAA==.',Ga='Galatea:BAAALAADCggICgAAAA==.',Gi='Giranimo:BAAALAADCgcIDgAAAA==.',Gl='Glabados:BAAALAADCgUIBQABLAAECgYICgACAAAAAA==.Glossy:BAABLAAECoEWAAMJAAgIXCNrAwBDAgAJAAYIAiJrAwBDAgAKAAUIZyPtEAATAgAAAA==.Glossyglaive:BAAALAADCgYIBgAAAA==.',Go='Gondor:BAAALAAECgEIAQAAAA==.Goth:BAAALAAECgYICgAAAA==.',Gr='Grargolgox:BAAALAADCgcIBwAAAA==.Greathoof:BAAALAADCgEIAQAAAA==.',Gu='Guwugga:BAAALAADCgcIBwAAAA==.',Ha='Hammered:BAAALAAECgcIDAAAAA==.Harmshock:BAAALAAECgcIEgAAAA==.Hathina:BAABLAAECoEWAAILAAgIpCNiAwA+AwALAAgIpCNiAwA+AwAAAA==.Haylo:BAAALAADCgEIAQAAAA==.',He='Heiligermann:BAAALAADCgcIDAAAAA==.Heket:BAAALAAECgUICQAAAA==.Hellfrøst:BAAALAADCgcIBwAAAA==.Helpinghandz:BAAALAADCggICAAAAA==.',Hi='Hill:BAAALAAECgEIAgAAAA==.',Ho='Hobble:BAAALAADCggICAAAAA==.Hotdogwater:BAAALAAECgEIAQAAAA==.',Hu='Huudied:BAAALAAECgMIAwAAAA==.',Ic='Icaron:BAAALAADCggIBwAAAA==.Icyblaze:BAAALAAECgQIBQAAAA==.',Ig='Igomer:BAAALAADCggICAAAAA==.',Im='Imsorry:BAAALAAECgQIBwAAAA==.',In='Incca:BAAALAADCgcICQAAAA==.Indomitabull:BAABLAAECoEWAAIMAAgIxhyiBwCvAgAMAAgIxhyiBwCvAgAAAA==.Infermoo:BAAALAADCgEIAQAAAA==.',Ja='Jackstands:BAAALAAECgcIDQAAAA==.',Je='Jesse:BAAALAADCgcIBwAAAA==.',Ji='Jinxsmon:BAAALAADCgcIEAAAAA==.',Kh='Khathani:BAAALAADCgQIBgAAAA==.',Ki='Kieran:BAAALAADCgYIBgAAAA==.Kindfawn:BAAALAADCgcIBwAAAA==.',Ko='Kofadin:BAAALAAECgMIAwAAAA==.Komojo:BAAALAAECgEIAQAAAA==.Konstantyn:BAAALAAECgEIAQAAAA==.Korkha:BAAALAAECgIIAgAAAA==.Kou:BAAALAAECgcIEAAAAA==.',Kp='Kpopbussy:BAAALAADCgYIBgAAAA==.',Kr='Krea:BAAALAAECgMIAwAAAA==.Krystagosa:BAAALAAECgMIBQAAAA==.',Ku='Kurkash:BAAALAADCgEIAQABLAAECgcIDwACAAAAAQ==.',La='Lang:BAAALAAECgMIBQAAAA==.Larimar:BAAALAAECgMIBQAAAA==.',Le='Leodemortem:BAAALAADCgIIAgAAAA==.',Li='Linah:BAAALAAECgIIBAAAAA==.',Lo='Loopey:BAAALAAECgUIBQAAAA==.',Lu='Luciàn:BAAALAAECgYICwAAAA==.',Ma='Magwar:BAABLAAECoEWAAILAAgIBCI8BQAbAwALAAgIBCI8BQAbAwAAAA==.Maike:BAAALAADCgcIDgAAAA==.March:BAAALAAECgMIAwAAAA==.Marlyth:BAAALAAECgEIAQAAAA==.Marothius:BAABLAAECoEWAAQNAAgIOhd/DgBnAgANAAgIOhd/DgBnAgAOAAUI0w3vJAD4AAAPAAEIQhgYJgBUAAAAAA==.Martaug:BAAALAAECgcIEAAAAA==.Marune:BAAALAAECgYICQAAAA==.Maverage:BAAALAAECgMIAwAAAA==.Mayia:BAAALAADCgcICAAAAA==.',Mc='Mcslaxs:BAAALAADCgIIAgAAAA==.',Me='Melee:BAABLAAFFIEGAAIHAAIIzCaoAgDnAAAHAAIIzCaoAgDnAAAAAA==.',Mi='Mikeyy:BAAALAADCgcICAAAAA==.Mirquizz:BAAALAAECgcIEAAAAA==.',Mo='Mog:BAAALAAECgUICQAAAA==.Moonkin:BAAALAAECgMIAwAAAA==.Mooplexity:BAAALAAECgYIDQAAAA==.Morior:BAAALAAECgcIDwAAAA==.Morningstar:BAAALAADCgcIDAAAAA==.Morî:BAAALAADCgIIAgAAAA==.',Mu='Murrda:BAAALAAECggIBQAAAA==.Musk:BAAALAADCgcICQAAAA==.',['Mö']='Möokss:BAAALAADCggICQAAAA==.',Na='Nailo:BAAALAAECgcIEAAAAA==.Narcïssa:BAAALAADCgQIBAAAAA==.Nathanos:BAAALAAECgUICQAAAA==.',Ni='Nightwatcher:BAAALAADCgcIBwAAAA==.Niuzao:BAAALAAECgMIAwAAAA==.',No='Noebudie:BAABLAAECoEWAAIQAAgIOB88DQCuAgAQAAgIOB88DQCuAgAAAA==.Noel:BAAALAADCggIDwAAAA==.Nonospot:BAAALAAECgIIAgAAAA==.Noodette:BAAALAAECgEIAQAAAA==.Noraboo:BAAALAAECgUICwAAAA==.Nosugar:BAAALAADCgMIAwAAAA==.Nowi:BAAALAADCgYIBgAAAA==.',Ny='Nyctt:BAAALAAECgYIDAAAAA==.Nyzstra:BAAALAAECgcIEAAAAA==.',Ot='Otem:BAAALAAECgMIBwAAAA==.',Pa='Pastrydragon:BAABLAAECoEUAAIMAAgICiJPBAAAAwAMAAgICiJPBAAAAwAAAA==.Pastrypriest:BAAALAAECgIIAgABLAAECggIFAAMAAoiAA==.',Pi='Pistachio:BAAALAADCggIDAAAAA==.Pitviper:BAAALAAECgYICgAAAA==.',Ps='Psarchasm:BAAALAAECgMIAwAAAA==.Psiyaad:BAAALAAECgMIBQAAAA==.',Qu='Quandolf:BAAALAADCggICwAAAA==.',Ra='Rafa:BAAALAAECgYICgAAAA==.Rai:BAAALAAECgMIBQAAAA==.Rakdar:BAAALAADCgYIBgAAAA==.Ramenboi:BAAALAAECgIIAgAAAA==.Raynger:BAAALAAECgYICgAAAA==.',Re='Realtree:BAAALAAECgYIDAAAAA==.Reprimanded:BAAALAADCgYIBQAAAA==.',Sc='Scher:BAAALAADCggIEAAAAA==.Scufalufagus:BAAALAADCggIFgABLAAECggIFgANADoXAA==.',Se='Sel:BAABLAAECoEWAAMRAAgIKyUaAAB1AwARAAgIKyUaAAB1AwASAAEI8AUFTAA6AAAAAA==.Sevatar:BAAALAAECgYICgAAAA==.',Sh='Shrederz:BAAALAADCgcICgAAAA==.',Si='Silverbarb:BAAALAADCgIIAgAAAA==.',Sl='Slamminham:BAAALAADCgMIAwAAAA==.',Sn='Snomedeesi:BAAALAADCgUIBQAAAA==.',Ss='Ssgwarner:BAAALAADCgcIBwAAAA==.',St='Stregoica:BAAALAADCggICAABLAAECggIFgANADoXAA==.',Su='Sugartatas:BAAALAADCgEIAQAAAA==.Supæsugoto:BAAALAADCgQIBAAAAA==.Surrs:BAAALAADCgYIBgABLAAECgMIAwACAAAAAA==.Sushhii:BAAALAADCgcIBwAAAA==.Sushisdruid:BAAALAADCggICAAAAA==.',Ta='Tallron:BAABLAAECoEWAAITAAgIIiGqAwDUAgATAAgIIiGqAwDUAgAAAA==.Tankzert:BAAALAAECgcIEQAAAA==.',Te='Telenor:BAAALAADCgUIBQAAAA==.',Th='Thôr:BAAALAADCgMIAwABLAADCgcIBwACAAAAAA==.',Ti='Tipadis:BAAALAADCgYIBAAAAA==.',To='Tojikitoushi:BAAALAAECgcIEAAAAA==.Tombs:BAAALAADCggIEgAAAA==.Totemhammer:BAAALAADCgYIBgAAAA==.Totenhammer:BAAALAAECgMIAwAAAA==.Totenplage:BAAALAADCgIIAgAAAA==.Touchurbible:BAAALAAECgYIBgAAAA==.',Ts='Tsundere:BAAALAAECgQIBgAAAA==.',Tw='Twinkii:BAAALAADCgYIBgAAAA==.',Ty='Tyrolia:BAAALAAECgYICgAAAA==.',Va='Valliya:BAAALAADCgYIBwAAAA==.',Ve='Veklir:BAAALAADCggIDwAAAA==.Venji:BAAALAAECgMIAwAAAA==.Vesi:BAABLAAECoEWAAMKAAgIESROAQBOAwAKAAgIDSROAQBOAwAUAAMIgRuuCADzAAAAAA==.Vextt:BAAALAAECgYIBgAAAA==.',Vi='Vicsta:BAAALAAFFAIIAgAAAA==.',Vo='Volke:BAAALAAECgYIBgAAAA==.',Vs='Vsi:BAAALAADCgcIBwAAAA==.',Vu='Vulpes:BAAALAAECgIIAwAAAA==.',We='Weledish:BAAALAAECgMIBQAAAA==.Wetwilly:BAAALAAECgMIBAAAAA==.',Wh='Whitetotem:BAAALAAECgcIDAAAAA==.',Xe='Xebeche:BAAALAAECgUICQAAAA==.',Xu='Xurn:BAAALAAECgIIBAAAAA==.',Ze='Zelto:BAAALAADCgYIBAAAAA==.',Zh='Zhang:BAAALAADCgcIBQAAAA==.',Zo='Zodiark:BAAALAADCgEIAQABLAAECgMIAwACAAAAAA==.Zomgofwar:BAAALAAECgcIEAAAAA==.Zowku:BAAALAAECgMIAwAAAA==.',Zr='Zr:BAAALAADCgUIBQAAAA==.',Zu='Zurishmi:BAAALAAFFAEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end