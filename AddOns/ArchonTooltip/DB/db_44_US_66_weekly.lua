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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Warrior-Protection','Druid-Restoration','Druid-Balance','Priest-Shadow','Priest-Holy',}; local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaragath:BAEALAAECgUIBwAAAA==.',Ae='Aenlora:BAAALAAFFAMIAwAAAA==.',Ag='Agesilaus:BAAALAADCgMIAwAAAA==.Agesipolis:BAAALAAECgMIAwAAAA==.',Ai='Aikar:BAAALAAECgMIAwAAAA==.',Ak='Akebono:BAAALAADCgYIBgAAAA==.',Al='Alaninu:BAAALAADCgEIAQAAAA==.Aldebaran:BAAALAADCggIFAAAAA==.',As='Ashke:BAAALAAECgIIAgAAAA==.',Av='Avarice:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.',Be='Beaupeep:BAAALAAECgEIAQAAAA==.Benedictine:BAAALAAECgMIBQAAAA==.',Bi='Bigfellow:BAAALAAECgIIAgAAAA==.Bigfellowxx:BAAALAADCgcIBwAAAA==.Bigoof:BAAALAADCgUIBQAAAA==.',Bo='Bobi:BAAALAAECgIIAgAAAA==.Bogal:BAAALAAECgUIBgAAAA==.Boyacky:BAAALAADCgcIDgAAAA==.',Br='Braiglock:BAAALAAECgMIAwAAAA==.Bricked:BAAALAAECgMIBQAAAA==.',By='Bygz:BAAALAADCgMIAwAAAA==.',['Bé']='Béésty:BAAALAADCgMIAwAAAA==.',Ca='Caarjack:BAAALAAECgcIEAAAAA==.Callmemeg:BAAALAADCgcICgAAAA==.',Ce='Celestial:BAAALAAECgMIAwAAAA==.Celestte:BAAALAADCgMIAwAAAA==.',Ch='Chewwyy:BAAALAAECgYIDwAAAA==.Chyse:BAAALAAECgMIBAAAAA==.Chéetto:BAAALAAECgYIDgAAAA==.',Ci='Cindroz:BAAALAADCgcICgAAAA==.Cizrena:BAAALAAECgIIBAAAAA==.',Da='Dakazax:BAAALAADCgQIBAAAAA==.Dalrathrus:BAAALAADCggIDgAAAA==.Dannetheoff:BAAALAADCgMIAwAAAA==.Daxhamma:BAAALAAECgEIAQABLAAECggIFgACACIkAA==.',De='Deathphish:BAAALAAECgUIBwAAAA==.Deathshir:BAAALAAECgQIBQAAAA==.Dedsckull:BAAALAADCgYIBgAAAA==.Demistørmz:BAAALAAECgIIAgAAAA==.Denardirn:BAAALAAECgcIEQAAAA==.Denizin:BAAALAAECgEIAgAAAA==.Derfla:BAAALAADCgcIBwAAAA==.Deshler:BAAALAAECgEIAQAAAA==.',Di='Dildro:BAAALAADCgQIBAABLAADCgcIFAABAAAAAA==.Dincy:BAAALAADCgcIBwAAAA==.Dirtyblonde:BAAALAAECgEIAQAAAA==.Ditlutz:BAAALAAECgMIBAAAAA==.',Do='Dom:BAABLAAECoEXAAIDAAgISB9+BACqAgADAAgISB9+BACqAgAAAA==.',Dr='Drewid:BAAALAADCggIDgAAAA==.',Dw='Dwanco:BAAALAADCgUIBQAAAA==.',Dy='Dybby:BAAALAADCgIIBAAAAA==.',Ea='Eatapple:BAAALAADCggIFQAAAA==.',El='Eldarath:BAAALAADCgMIAwAAAA==.Elenara:BAAALAAECgMIBAAAAA==.Elrondus:BAAALAAECgIIAQAAAA==.',Em='Emridion:BAAALAAECgMIAwAAAA==.',En='Entropy:BAAALAAECgUIBQAAAA==.',Fa='Faebryn:BAAALAAECgMIBAAAAA==.',Fe='Fellord:BAAALAADCgcIBwAAAA==.Felmaiden:BAAALAADCgYICgAAAA==.Femfatal:BAAALAAECgUIBgAAAA==.Fenirean:BAAALAADCgcICgAAAA==.Fenrir:BAAALAAECgMIAwAAAA==.',Fi='Fierycloaca:BAAALAAECgEIAQAAAA==.',Fo='Forcas:BAAALAAECgIIBAAAAA==.',Fu='Furyshammy:BAAALAAECgYIBwAAAA==.Furysmite:BAAALAADCgcIDAAAAA==.',Ga='Gabbar:BAAALAADCgYIBgAAAA==.Gallifrey:BAAALAAECgYICQAAAA==.Ganksterqt:BAAALAADCgIIAgAAAA==.Ganyin:BAAALAADCgQIBQAAAA==.Garthilin:BAAALAADCgUIBQAAAA==.Gazzik:BAAALAADCgcIBwAAAA==.',Gl='Glacies:BAAALAADCggIFAAAAA==.',Go='Gopherlock:BAAALAAECggIEQAAAA==.',Gr='Grimlokk:BAAALAAECgYIBgAAAA==.',Gu='Guillak:BAAALAAECgIIBAAAAA==.',Ha='Hammond:BAAALAADCgIIAgAAAA==.',He='Hej:BAAALAADCgYIBgABLAAECgcIDQABAAAAAA==.',Hi='Highsociety:BAAALAADCggICAABLAAECgUICQABAAAAAA==.',Ho='Hollybell:BAAALAADCggICQAAAA==.Holîcow:BAAALAADCgMIAwAAAA==.Hoofingit:BAAALAADCggIDwAAAA==.Howlingdoom:BAAALAAECgEIAQAAAA==.Howzeeir:BAAALAADCgYIBgAAAA==.',Hy='Hyeixia:BAAALAADCgMIAwAAAA==.',Ib='Ibull:BAAALAADCgUIBQAAAA==.',If='Iffy:BAAALAAECgMIBQAAAA==.',Il='Ilian:BAAALAAECgcICwAAAA==.',Im='Imortalchaos:BAAALAAECgcIDgAAAA==.',In='Ingward:BAAALAADCgcICwAAAA==.',Io='Ionsta:BAAALAADCgQIBAAAAA==.',Ja='Jawless:BAAALAADCgQIBAAAAA==.Jayaatu:BAAALAADCggICQAAAA==.',Jd='Jdmagisdruid:BAAALAAECgMIBAAAAA==.Jdmagishuntr:BAAALAADCgIIAgABLAAECgMIBAABAAAAAA==.',Je='Jeffrey:BAAALAADCgcIFAAAAA==.',Jo='Journee:BAAALAADCgQIBwAAAA==.',Ju='Juan:BAAALAAECgMIBAAAAA==.Jubadin:BAAALAAECgEIAQAAAA==.Jumbo:BAAALAAECgIIBAAAAA==.Jumpeor:BAABLAAECoEWAAICAAgIIiQdBQAwAwACAAgIIiQdBQAwAwAAAA==.',Ka='Kalder:BAAALAADCggICAAAAA==.Katacola:BAACLAAFFIEFAAIEAAMI3x2mAQANAQAEAAMI3x2mAQANAQAsAAQKgRcAAwQACAhVE9YWALwBAAQACAhVE9YWALwBAAUABAhaFnMqABwBAAAA.',Ke='Keloretta:BAAALAAECgMIBAAAAA==.Kenaf:BAAALAADCgcICQAAAA==.Kenthus:BAAALAADCggICAAAAA==.Kethria:BAAALAAECgYICgAAAA==.',Ki='Kiira:BAAALAAECgMIAwAAAA==.Kikiliki:BAAALAADCggIFAAAAA==.Kilthgar:BAAALAAECgMIBAAAAA==.Kizmit:BAAALAADCgcIDAAAAA==.',Ko='Koa:BAAALAAECgMIBAAAAA==.',Ku='Kurau:BAAALAADCgMIAwAAAA==.',La='Lachesos:BAAALAADCggICAAAAA==.Lalasama:BAAALAADCgYIBgAAAA==.',Li='Lillithe:BAAALAADCggIEAAAAA==.',Lo='Locj:BAAALAAECgcIDQAAAA==.Lokarr:BAAALAADCgUIBQAAAA==.Lokiel:BAAALAAECgUIBgAAAA==.Loosie:BAAALAADCgQIBAAAAA==.',Ly='Lyaenna:BAAALAAECgQIBgAAAA==.Lydius:BAAALAAECgQIBAAAAA==.',Ma='Magegee:BAAALAAECgEIAQAAAA==.Magrat:BAAALAADCgYIBgAAAA==.Maletherion:BAAALAAECgMIBAAAAA==.Maltherion:BAAALAAECgIIAgAAAA==.Maraka:BAAALAAECgYIBwAAAA==.Mayple:BAAALAADCggICAAAAA==.',Mj='Mjolnir:BAAALAAECgMIBAAAAA==.',Mo='Momioki:BAAALAADCgMIAwAAAA==.Moosewillis:BAAALAADCgcIBwAAAA==.',My='Mystaris:BAAALAADCgcIBwAAAA==.',Na='Nalstaria:BAAALAADCgcIBwAAAA==.Navybum:BAAALAADCgcIBwAAAA==.Nazgüll:BAAALAADCgcIBwAAAA==.',Ne='Nehen:BAAALAAECgYICQAAAA==.Nequins:BAAALAAECgIIAgAAAA==.Nequinss:BAAALAAECgQIBgABLAAECgIIAgABAAAAAA==.Nevermore:BAAALAAECgIIAgAAAA==.',Ng='Ngatii:BAAALAADCgIIAgAAAA==.',Ni='Niobe:BAAALAADCggIDwAAAA==.Nirvaná:BAABLAAECoEWAAMGAAgIYR5SBwDeAgAGAAgIYR5SBwDeAgAHAAEIohLYWAAzAAAAAA==.',No='Noehtyar:BAAALAAECgEIAQAAAA==.Noie:BAAALAAECgMIAwAAAA==.',Ny='Nyxia:BAAALAADCggICwAAAA==.',Oa='Oakily:BAAALAADCggIEAAAAA==.',Oi='Oilliphéist:BAAALAAECgEIAQAAAA==.',On='Oneclickonly:BAAALAADCgEIAQAAAA==.',Or='Ornot:BAAALAAECgIIAwAAAA==.',Os='Ostie:BAAALAADCgcIDQAAAA==.',Pa='Paws:BAAALAADCgcIBwAAAA==.',Pe='Peposhammy:BAAALAADCgYIBgAAAA==.',Pi='Pierre:BAAALAADCggICAAAAA==.',Po='Pomocalypse:BAAALAADCggICQAAAA==.Pounds:BAAALAAECgUIBgAAAA==.',Pr='Priechrawr:BAAALAAECgMIAwAAAA==.Provost:BAAALAAECgIIAgAAAA==.',Py='Pyrazus:BAAALAAECgMIBAAAAA==.',Ra='Ravia:BAAALAADCgMIAwAAAA==.',Re='Remulüs:BAAALAAECgQIBAAAAA==.Rezdpriest:BAAALAAECgEIAQAAAA==.',Ri='Riilyn:BAAALAAECgQIBQAAAA==.Rimeholt:BAAALAAECgMIBAAAAA==.',Ro='Roan:BAAALAAECgYICQAAAA==.Rockbrain:BAAALAADCgcICAAAAA==.Roh:BAAALAADCgEIAQAAAA==.',Sa='Saina:BAAALAADCggIDwAAAA==.',Sc='Scalebeard:BAAALAAECgYICQAAAA==.Scawmfmage:BAAALAADCgYIBgAAAA==.Scecretzs:BAAALAAECgUIBgAAAA==.',Se='Sedrelari:BAAALAAECgMIBwABLAAECgYICgABAAAAAA==.Sengseng:BAAALAADCgIIAgAAAA==.Sepsis:BAAALAAECgEIAQAAAA==.Sesamo:BAABLAAECoEaAAICAAgIPyViAgBhAwACAAgIPyViAgBhAwAAAA==.',Si='Sixoneseven:BAAALAADCgIIAgAAAA==.',Sl='Slok:BAAALAADCggIFQAAAA==.',Sm='Smolhatka:BAAALAADCgcICgAAAA==.',So='Solatic:BAAALAADCgcIBQAAAA==.Soule:BAAALAADCggIFgAAAA==.',St='Startle:BAAALAADCgYICAAAAA==.',Su='Subtlesyther:BAAALAAECgYIBwAAAA==.Sumting:BAAALAAECgIIAgAAAA==.',Sy='Syphã:BAAALAAECgMIBAAAAA==.',['Sö']='Sören:BAAALAADCgEIAQABLAADCgMIBQABAAAAAA==.',Ta='Takoda:BAAALAAECggICQAAAA==.Taomi:BAAALAAECgMIBAAAAA==.Tashamia:BAAALAAECgEIAQAAAA==.',Te='Tetsuro:BAAALAADCgYIBAAAAA==.',Th='Thisrogue:BAAALAADCgMIAwAAAA==.Thror:BAAALAADCgcIBwAAAA==.Throwglaive:BAAALAADCggICAAAAA==.',Ti='Tidereign:BAAALAADCgcICgAAAA==.Tinytotems:BAAALAAECgMIBQAAAA==.Tiriell:BAAALAADCgYIBgAAAA==.',Tr='Traedorissel:BAAALAAECgQIBAAAAA==.Traeron:BAAALAADCggIDAAAAA==.Trinanah:BAAALAAECgcIEAAAAA==.',Tt='Ttvtracixs:BAAALAADCgcICQAAAA==.',Ty='Tylang:BAAALAADCgcIBwAAAA==.',Uz='Uzu:BAAALAADCgcIBwAAAA==.',Va='Valgal:BAAALAAECgEIAQAAAA==.',Ve='Velrez:BAAALAADCgEIAQAAAA==.',Vo='Voidblade:BAAALAADCgcIBwAAAA==.Voidelicious:BAAALAAECgMIBQAAAA==.',We='Wef:BAAALAAECgQIBAAAAA==.',Wi='Wimbly:BAAALAADCggIDwAAAA==.Wings:BAAALAAECgIIAgAAAA==.Wintel:BAAALAADCgIIAgAAAA==.Wizzler:BAAALAAECgMIBQAAAA==.',Wo='Wolfhound:BAAALAAECgEIAQAAAA==.',Xa='Xantheus:BAAALAADCgYIBgAAAA==.',Yo='Yo:BAAALAAECgEIAQAAAA==.',Za='Zabbykinz:BAAALAADCgEIAQABLAADCgUIBQABAAAAAA==.Zabinki:BAAALAADCgUIBQAAAA==.Zaldesh:BAAALAADCggIFQAAAA==.Zappyscyther:BAAALAADCgEIAQAAAA==.',['Âx']='Âxel:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end