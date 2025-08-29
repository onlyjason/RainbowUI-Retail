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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Mage-Frost','Warrior-Protection','Evoker-Devastation','Druid-Balance','Druid-Restoration','Druid-Feral',}; local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaiyanna:BAAALAADCgcIDgAAAA==.',Ad='Adraa:BAAALAAECgIIAgAAAA==.',Ae='Aeon:BAAALAAECggIAwAAAA==.',Ag='Agilio:BAAALAAECgcICgAAAA==.',Ai='Aiedan:BAAALAADCgEIAQAAAA==.Airie:BAAALAADCgcIBwAAAA==.Airwrecka:BAAALAAECgYIDAAAAA==.',Al='Alaster:BAAALAAECgEIAQAAAA==.Alexhunter:BAAALAAECgEIAQAAAA==.Alexmurder:BAAALAADCgMIAwAAAA==.Aloriann:BAAALAADCgcICQAAAA==.Alåten:BAAALAAECgcIDAAAAA==.',Am='Ambrossee:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.Amebeliever:BAAALAAECgYICwAAAA==.Ameris:BAAALAADCggIFQAAAA==.',An='Antheralina:BAAALAADCgcIBwAAAA==.',Ar='Archidilia:BAAALAAECgYICAAAAA==.',As='Asukà:BAAALAAECgIIAgAAAA==.',Au='Aura:BAAALAADCggICAAAAA==.',Az='Azorae:BAAALAAECggICgAAAA==.',Ba='Bambu:BAAALAADCggICwAAAA==.Baz:BAABLAAECoEXAAICAAgIEBjPEAA6AgACAAgIEBjPEAA6AgAAAA==.',Be='Bellarg:BAAALAAECgMIBAAAAA==.',Bi='Biff:BAAALAAECgcIEQAAAA==.',Bo='Bonkus:BAAALAADCgQIBAAAAA==.Bowlo:BAAALAAECgMIAwAAAA==.',Br='Bralson:BAAALAAECgEIAQAAAA==.Bro:BAAALAAECgMIAwAAAA==.Broo:BAAALAAECgYIDAABLAAECgMIAwABAAAAAA==.Brozeit:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',Ca='Caarcus:BAAALAAECggIEgAAAA==.Calculusx:BAAALAAECgYICAAAAA==.Caline:BAAALAADCgcIEAAAAA==.Caol:BAAALAAECgYIDAAAAA==.Captpunch:BAAALAADCgEIAQAAAA==.Cattlock:BAAALAADCggIDwAAAA==.Cattzu:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.Caèlynn:BAAALAAECgIIAgAAAA==.',Ce='Cellice:BAACLAAFFIEFAAIDAAMIAB5hAAAXAQADAAMIAB5hAAAXAQAsAAQKgRgAAgMACAhGJnUAAHUDAAMACAhGJnUAAHUDAAAA.',Ch='Chatha:BAAALAAECgQICQAAAA==.',Ci='Cielo:BAAALAADCgEIAQAAAA==.',Cl='Claw:BAAALAAECgMIAwAAAA==.Cloúd:BAAALAADCgQIBAAAAA==.',Co='Coleco:BAAALAAECgYIDAAAAA==.Colmacka:BAAALAADCgUIBQAAAA==.',Da='Daaman:BAAALAADCggICAAAAA==.Daphe:BAAALAADCgcIDwAAAA==.Darclink:BAAALAADCgYIBgAAAA==.',De='Debz:BAAALAAECgYIDAAAAA==.Deegee:BAAALAAECgMIBQAAAA==.Demithrees:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.Deshield:BAAALAAECgcIEQAAAA==.Dewry:BAAALAAECgMIAwAAAA==.',Dh='Dhudamuthi:BAAALAAECgYIBwAAAA==.',Di='Dimes:BAAALAAECgMIBAAAAA==.',Dj='Djabb:BAAALAAECgIIAgAAAA==.',Do='Dohka:BAAALAAECgYIDAAAAA==.Donnajuan:BAAALAAECgcICwAAAA==.',Dr='Draaxelro:BAAALAADCggIEQAAAA==.Dragonboufas:BAAALAADCggIDwAAAA==.Dre:BAAALAADCgEIAQAAAA==.Drippy:BAAALAADCggIBgAAAA==.',Du='Duckboy:BAAALAADCgcIBwAAAA==.',Dy='Dynas:BAAALAADCggIDQAAAA==.',El='Elimere:BAAALAAECgYIDAAAAA==.Elminstér:BAAALAAECgEIAQAAAA==.Elywen:BAAALAAECgMIBQAAAA==.',Em='Embertal:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',En='Endezoth:BAAALAAECgYIBwAAAA==.Enfuegó:BAAALAADCgcIBwAAAA==.',Es='Esh:BAAALAAECggIEAAAAA==.',Ex='Extracting:BAAALAAECgMIBAAAAA==.',Fe='Featherpaw:BAAALAAECgMIAwAAAA==.Felkinahn:BAAALAAECgcIEAAAAA==.',Fi='Fiammetta:BAEBLAAFFIEFAAIEAAMIahLHAQDkAAAEAAMIahLHAQDkAAAAAA==.Fiddlesticks:BAAALAADCgcIBgABLAAECggIEgABAAAAAA==.',Fl='Flickerbeat:BAAALAADCgcIDQAAAA==.Fluxer:BAAALAADCgQIAwAAAA==.',Fr='Frisbee:BAAALAAECgYIDQAAAA==.Frogbiscuit:BAAALAADCggIFQAAAA==.Frís:BAAALAAECgYIDQAAAA==.',Ge='Getusum:BAAALAADCgcIBwAAAA==.',Gi='Gilrathor:BAAALAAECgEIAQAAAA==.',Go='Gobiasinds:BAAALAAECgEIAQAAAA==.Gofetch:BAAALAAECgMIBQAAAA==.',Gr='Grafenwohr:BAAALAADCgcIBwAAAA==.Grazzt:BAAALAADCggICAAAAA==.Grissúm:BAAALAAECgMIBAAAAA==.',Ha='Hackam:BAAALAAECgYIDQAAAA==.Hal:BAAALAADCggIEQAAAA==.Harold:BAAALAADCggICAAAAA==.',He='Healingkiss:BAAALAADCggIFQAAAA==.Helper:BAAALAAECgQIBAAAAA==.',Ho='Hollypallz:BAAALAADCggIFAAAAA==.Holymages:BAAALAAECgMIAwAAAA==.',Il='Ilyanna:BAAALAAECgYIDAAAAA==.',Jh='Jhops:BAAALAAECgMIBAAAAA==.',Ji='Jilliebean:BAAALAADCgQIBAAAAA==.',Ju='Jukedknelf:BAAALAADCgcIBwAAAA==.Jukenukem:BAAALAAECgMIAwAAAA==.',Ka='Kaeira:BAAALAADCgcIBwAAAA==.Kaidia:BAAALAAECgYICQAAAA==.Kaiyann:BAAALAADCgIIAgAAAA==.Karanda:BAAALAAECgIIAgAAAA==.',Ke='Kelleah:BAAALAAECgIIAwAAAA==.Kerafyrm:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Kerleyina:BAAALAAECgYICQAAAA==.',Ki='Kinz:BAAALAAECgQIBQAAAA==.Kisa:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Kitsúne:BAAALAADCgcIBwAAAA==.',Ko='Kookler:BAAALAAECgYICQAAAA==.',Ku='Kushmon:BAAALAADCgcICwAAAA==.',Ky='Kyirr:BAAALAAECgcIDgAAAA==.Kynthya:BAAALAADCgQIBAAAAA==.Kyralen:BAAALAAECgYICAAAAA==.',La='Lamedevil:BAAALAAECgcIBwAAAA==.Lasagnadaddy:BAAALAAECgYIBgAAAA==.',Le='Leonheartt:BAAALAAECgMIBAAAAA==.Lettuce:BAAALAADCgUIBQAAAA==.',Lf='Lfrith:BAAALAADCggIDgAAAA==.',Li='Lifeless:BAAALAAECgMIBAAAAA==.Littleboat:BAAALAAECgYIBgAAAA==.',Ll='Llela:BAAALAAECgEIAQAAAA==.Llynryn:BAAALAADCggIEQAAAA==.',Lo='Lockanise:BAAALAADCgEIAQAAAA==.',Ma='Magicae:BAAALAADCgYIBgABLAADCggIGAABAAAAAA==.Magicmanzz:BAAALAAECgEIAQAAAA==.Magicpanda:BAAALAADCgcIDgAAAA==.Magnifuso:BAAALAADCgEIAQAAAA==.Mallow:BAAALAAECgYICAAAAA==.Mamajune:BAAALAADCgcIBwAAAA==.Mastab:BAAALAAECgcIDgAAAA==.Matcollector:BAAALAADCgYIBgAAAA==.',Mi='Michanise:BAAALAADCgQIBAAAAA==.Mikio:BAAALAADCgYIBgAAAA==.Miliani:BAAALAADCgYICQAAAA==.Milinka:BAAALAAECgYIDAAAAA==.',Mo='Moiryn:BAAALAADCggICAAAAA==.',My='Mythicc:BAAALAADCgQIBwAAAA==.',Na='Navillus:BAABLAAECoEVAAIFAAgI0iOhAwASAwAFAAgI0iOhAwASAwAAAA==.',Ne='Nefarious:BAAALAADCgIIAgAAAA==.',Ni='Nightstriker:BAAALAADCgEIAQAAAA==.',No='Nori:BAAALAAECgEIAgAAAA==.Notavaliible:BAAALAAECgYICwAAAA==.',Op='Ophindis:BAAALAAECgIIAgAAAA==.',Pe='Permanence:BAAALAAECgMIBAAAAA==.Pewpop:BAAALAAECgYIDAAAAA==.',Pu='Purification:BAAALAADCggIGAAAAA==.',Qp='Qpti:BAAALAADCggIDwAAAA==.',Ra='Raios:BAAALAADCgcIEAAAAA==.',Rc='Rckola:BAABLAAECoEWAAIGAAgIFSWFAgBBAwAGAAgIFSWFAgBBAwAAAA==.',Re='Relice:BAAALAADCgQIBAAAAA==.Rennx:BAABLAAECoEWAAIGAAgI9iXdAABwAwAGAAgI9iXdAABwAwAAAA==.Reverend:BAAALAADCgQIBAAAAA==.',Ri='Ringmasta:BAAALAADCggIFQAAAA==.',Ro='Rotgut:BAAALAADCggIBwAAAA==.Roxanya:BAAALAAECgEIAQAAAA==.',Ru='Rucket:BAAALAAECgcIDQAAAA==.',['Rè']='Rènza:BAAALAAECgEIAQAAAA==.',Sa='Sachra:BAAALAAECgQIBQAAAA==.Saelybrosa:BAAALAAECgEIAQAAAA==.Saiyan:BAAALAAECgMIBgAAAA==.Sannagna:BAAALAAECgYIDAAAAA==.Saphia:BAEALAAECggICAABLAAFFAMIBQAEAGoSAA==.',Sh='Shadda:BAAALAAECgMIAwAAAA==.Shadowzlord:BAAALAAECgIIAgAAAA==.Shinru:BAAALAAECgYICwAAAA==.Shùmáni:BAAALAADCgcIEAAAAA==.',Si='Sickdayze:BAAALAADCgcIDQAAAA==.Sickhymns:BAAALAAECgQIBgAAAA==.Sicktides:BAAALAADCgcIEAAAAA==.Sinsuna:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.',Sk='Skipandstep:BAAALAAECgMIAwAAAA==.',Sl='Slyxxar:BAAALAAECgMICQAAAA==.',So='Soph:BAABLAAECoEWAAMHAAgIkSKfAwDVAgAHAAgIkSKfAwDVAgAGAAEIDxtaRABNAAABLAAFFAIIAgABAAAAAA==.Sophie:BAAALAAFFAIIAgAAAA==.Sophievokie:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.Sophisticate:BAAALAAECgYIDAABLAAFFAIIAgABAAAAAA==.Sophlax:BAAALAAECgUICAABLAAFFAIIAgABAAAAAA==.Sophs:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.Sox:BAAALAAECgYIDAAAAA==.',Sp='Spankgg:BAAALAAECgEIAQAAAA==.Spectre:BAAALAAECgIIAgAAAA==.Spookyougi:BAAALAAECgYICwAAAA==.',Sq='Squattinchop:BAAALAAECgYICAAAAA==.',Sr='Sryphren:BAAALAAECgMIBQAAAA==.',St='Stormcaller:BAAALAAECgMIBgAAAA==.',Su='Suji:BAAALAAECgIIAgAAAA==.Supergogeta:BAAALAAECgUICAAAAA==.',Sy='Syanas:BAAALAADCgcIBwAAAA==.Sylla:BAAALAAECgIIAgAAAA==.',Ta='Tak:BAAALAADCgcIBwAAAA==.Takoda:BAAALAAECgIIAgAAAA==.',Th='Thatguy:BAAALAAECgYICQAAAA==.Thorish:BAAALAAECgcIDwAAAA==.',Ti='Timbit:BAAALAAECgYIDAAAAA==.',Tr='Trinjac:BAAALAADCgYIBgAAAA==.Trout:BAAALAADCgcIBwAAAA==.',Ty='Tyranis:BAAALAADCggIGAAAAA==.',Va='Vale:BAAALAAECgMIBAAAAA==.Vanda:BAAALAADCgYIBgAAAA==.',Ve='Vee:BAAALAAECgYICgAAAA==.',Vo='Voltage:BAAALAADCgYIBwABLAAECgYIDAABAAAAAA==.',We='Welgo:BAAALAAECgYICwAAAA==.',Wh='Whimsical:BAAALAAECgMIBQAAAA==.',Wi='Wickeddemon:BAAALAADCggIFQAAAA==.',['Wì']='Wìzzqt:BAAALAAECgYIDAAAAA==.',Xh='Xhiin:BAAALAADCggIEgAAAA==.Xhinoy:BAAALAADCgIIAgABLAADCggIEgABAAAAAA==.',Yi='Yia:BAACLAAFFIEFAAIIAAMIhReyAAAWAQAIAAMIhReyAAAWAQAsAAQKgRQAAggACAhfI5gAAE0DAAgACAhfI5gAAE0DAAAA.',Za='Zarghr:BAAALAADCgQIBAAAAA==.',Zo='Zobah:BAAALAADCggIDQAAAA==.',Zu='Zugaisback:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end