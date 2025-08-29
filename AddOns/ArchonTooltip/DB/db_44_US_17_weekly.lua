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
 local lookup = {'Unknown-Unknown','Druid-Restoration','Monk-Windwalker','DeathKnight-Frost','Shaman-Enhancement','Shaman-Elemental',}; local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aanaleaa:BAAALAAECgMIBAAAAA==.',Ad='Adrus:BAAALAAECggIBwAAAA==.',Ae='Aeliel:BAAALAAECgcIDgAAAA==.',Ak='Akakage:BAAALAAECgIIAgAAAA==.',Al='Alea:BAAALAAECgcICwAAAA==.',An='Anomander:BAAALAAECgMIBAAAAA==.',Ap='Apiconan:BAAALAAECgQIBAAAAA==.',Ar='Arienca:BAAALAAECgYIDQAAAA==.',As='Ashborne:BAAALAAECgMIAQAAAA==.Aster:BAAALAADCgMIAwABLAAECgMIBAABAAAAAA==.Asu:BAAALAADCgYIBwAAAA==.',At='At:BAAALAAECgEIAQAAAA==.',Au='Aubrey:BAAALAAECggIEgAAAA==.',Av='Avengion:BAAALAADCgcIDgAAAA==.',Be='Beav:BAAALAADCgYIBgABLAAECggIFQACACoeAA==.Bepis:BAAALAAECgcICwAAAA==.',Bl='Blazeofglory:BAAALAADCggICAAAAA==.Blinklock:BAAALAAECgEIAgABLAAECgYICgABAAAAAA==.Blitzkreig:BAAALAAECgMIBAAAAA==.Bloodborne:BAAALAAECgEIAQAAAA==.',Bo='Booty:BAAALAAECgcICwAAAA==.',Br='Brightblayde:BAAALAAECgIIAgAAAA==.',Bu='Buum:BAAALAAECgMIBAAAAA==.',['Bä']='Bämba:BAAALAAECgQIBwAAAA==.',Ce='Cedertree:BAAALAAECgcIDwAAAA==.',Ch='Chorizo:BAAALAADCgIIAgAAAA==.Chumleif:BAAALAADCgEIAQAAAA==.Chérry:BAAALAAFFAIIAgAAAA==.',Co='Courslabrume:BAAALAADCgcICAAAAA==.',Cr='Croh:BAAALAAECgEIAQAAAA==.Cruknar:BAAALAAECgcIDwAAAA==.',Cy='Cynestra:BAAALAAECgMIBAAAAA==.',Da='Daddio:BAAALAAECgEIAQAAAA==.Daftmonk:BAABLAAECoEUAAIDAAcIYCVLAwD0AgADAAcIYCVLAwD0AgAAAA==.Daitanfuteki:BAAALAAECgYICQAAAA==.Dari:BAAALAAECgMIBAAAAA==.Darkyst:BAAALAADCgcIDwAAAA==.Darmonevil:BAAALAAECgYIBgAAAA==.Dartran:BAAALAAECgMIAwAAAA==.Dasarus:BAAALAAECgEIAQAAAA==.',De='Destok:BAAALAADCgQIBAABLAAECgcIDwABAAAAAA==.Dethblow:BAAALAAECgIIAgAAAA==.',Di='Dium:BAAALAAECgMIBQAAAA==.Diwa:BAAALAAFFAIIAgAAAA==.',Dr='Dragolot:BAAALAAECgEIAQAAAA==.Dragu:BAAALAADCggICAAAAA==.Draviin:BAAALAAECgMIBwAAAA==.Driade:BAAALAADCgcIBwAAAA==.',Ep='Epitaph:BAAALAADCgYICgAAAA==.',Es='Esdeath:BAAALAADCgcIBwAAAA==.',Ex='Extremefear:BAAALAAECgIIAgAAAA==.',Ey='Eyeofmako:BAAALAADCggIFAABLAAECgYIDQABAAAAAA==.',Fa='Fatima:BAAALAADCggIDwAAAA==.',Fe='Feebop:BAAALAADCggIDQAAAA==.Fenrisfangs:BAAALAAECgMIBAAAAA==.',Fo='Forfoxsake:BAAALAAECgYICAAAAA==.',Fr='Freeswinger:BAAALAADCgQIBAAAAA==.Frogteeth:BAAALAADCggIDwAAAA==.',Fu='Furibeav:BAABLAAECoEVAAICAAgIKh6IBgCPAgACAAgIKh6IBgCPAgAAAA==.',['Fû']='Fûrrow:BAAALAAECgEIAQAAAA==.',Ga='Gallindral:BAAALAAECgcIEAAAAA==.',Ge='Genericnpc:BAAALAAECgEIAQAAAA==.Geobrando:BAAALAADCgYIBgABLAAECgYIDQABAAAAAA==.',Gl='Glasshunter:BAAALAAECgMIAwAAAA==.',Gn='Gnosh:BAAALAAECgMIBAAAAA==.Gnova:BAAALAADCgcIBwAAAA==.',Gr='Grogg:BAAALAADCggIDQAAAA==.Grêêd:BAAALAAECgYICAAAAA==.Grôot:BAAALAAECgMIBQAAAA==.',Ha='Harle:BAAALAAECgMIBAAAAA==.',He='Heigel:BAAALAAECgYICgAAAA==.',Ho='Holyshortguy:BAAALAADCggICAAAAA==.',Ia='Ian:BAAALAAECgQIBAAAAA==.',Ic='Icelmo:BAAALAAECgMIBgAAAA==.Ichthyhome:BAAALAAECgcIDwAAAA==.',In='Inai:BAAALAADCgYICQAAAA==.Inosukesan:BAAALAADCgQIBQAAAA==.',Ja='Jamzz:BAAALAADCggIDQAAAA==.Jaskow:BAAALAAECgQIBgAAAA==.',Jo='Joji:BAAALAAECgUIBQAAAA==.Jorlmare:BAABLAAECoEUAAIEAAgIyCHGCQDbAgAEAAgIyCHGCQDbAgAAAA==.Jorls:BAAALAAECgEIAQABLAAECggIFAAEAMghAA==.Jorltic:BAAALAADCgcIBwABLAAECggIFAAEAMghAA==.',Jy='Jyn:BAAALAADCgcIBwAAAA==.',Ka='Kaelleirra:BAAALAADCgYIBgABLAAECgYIDQABAAAAAA==.Kalandros:BAAALAADCgYIBgAAAA==.Kameshoga:BAAALAADCggIEAAAAA==.',Ke='Kesko:BAAALAADCgYICAAAAA==.',Ki='Kickpunch:BAAALAAECgcIDQAAAA==.Kittêh:BAAALAADCggICQAAAA==.',Ko='Koky:BAAALAAECgUIBQABLAAECggIBwABAAAAAA==.Korijack:BAAALAAECgYIDQAAAA==.Kotar:BAAALAADCggIFQAAAA==.',Kr='Krag:BAAALAAECgYIDQAAAA==.Krasis:BAAALAAECgYIBgAAAA==.Krazermonk:BAAALAADCgUIBQAAAA==.Krispinwah:BAAALAAECgYIDQAAAA==.Kristysavage:BAAALAADCgEIAQAAAA==.Krunkzug:BAAALAAECgMIAwAAAA==.',La='Lanc:BAAALAAECgcIDAAAAA==.',Le='Lexistral:BAAALAADCgcIBwAAAA==.',Lo='Lover:BAAALAAECgYICQABLAAECgYICQABAAAAAA==.',Lt='Ltroflcopter:BAAALAADCgQIBQAAAA==.',Lu='Lubu:BAAALAAECgYICQAAAA==.Lumiette:BAAALAADCgYIAwAAAA==.Lunastraza:BAAALAADCggICQAAAA==.',Lv='Lvispriestly:BAAALAAECgEIAQABLAAECgYICgABAAAAAA==.',['Lá']='Lándwhale:BAAALAAECgcIDAAAAA==.',['Læ']='Lægolas:BAAALAADCggIEQAAAA==.',['Lî']='Lîlith:BAAALAAECgUIBQABLAAECgYICQABAAAAAA==.',Ma='Mago:BAAALAADCgMIAwAAAA==.Maingel:BAAALAADCgcIBwAAAA==.Mamamoo:BAAALAAECgUIBQAAAA==.Marltonder:BAAALAADCgIIAgAAAA==.',Me='Merigold:BAAALAADCgcIBwAAAA==.Metapaws:BAAALAADCgcIDgABLAAECgQIBAABAAAAAA==.',Mi='Minoc:BAAALAADCgYIBwAAAA==.',My='Mylodon:BAAALAADCgUIBQAAAA==.Mysternia:BAAALAAECgMIBAAAAA==.',Na='Nayth:BAAALAAECgMIAwAAAA==.',Ne='Nella:BAAALAADCgEIAQAAAA==.Nelle:BAAALAADCgcIDQAAAA==.',Ni='Nickalos:BAAALAAECgYIDgAAAA==.',No='Nory:BAAALAADCgYICgABLAAECggIBwABAAAAAA==.Notorckrag:BAAALAADCgcIDgAAAA==.',Nu='Nulara:BAAALAADCgcIDgAAAA==.Nut:BAAALAAECgcICwAAAA==.',Ny='Nythira:BAAALAADCgIIAgABLAAECgYICQABAAAAAA==.Nythos:BAAALAADCggICAABLAAECgcIDwABAAAAAA==.',Of='Offbrandcleo:BAAALAADCgQIBAAAAA==.',Or='Originalhunt:BAAALAADCgcIDAAAAA==.',Pa='Padrethyndir:BAAALAADCgcIBwAAAA==.',Ph='Phingerphood:BAAALAADCgEIAQAAAA==.Phoenixx:BAAALAADCgEIAQABLAAFFAIIAwABAAAAAA==.',Pi='Pinkk:BAAALAAECgIIAwAAAA==.',Pl='Planetmfkr:BAAALAAECgEIAQAAAA==.',Po='Potatoteng:BAAALAADCggICAAAAA==.',Pr='Praimfaya:BAAALAADCgYIBgAAAA==.Proto:BAAALAAECgUIBQAAAA==.',Pu='Puf:BAAALAADCgIIAgABLAAECgQIBAABAAAAAA==.',['Pâ']='Pâiñ:BAAALAAECgEIAQAAAA==.',Ra='Raelwyn:BAAALAADCgcIBwAAAA==.Ragel:BAAALAADCgUIBQAAAA==.Rainesage:BAAALAADCggIEwAAAA==.Ralphel:BAAALAAECgEIAQAAAA==.Ranuvin:BAAALAAECgMIAwAAAA==.',Rh='Rhubarb:BAAALAAECgQICQAAAA==.',Ry='Ryan:BAAALAAECgYICQAAAA==.Rylorthas:BAAALAAECgcIDAAAAA==.Rylosh:BAAALAAECgEIAQABLAAECgcIDAABAAAAAA==.',Sa='Sabot:BAAALAAECgMIBAAAAA==.Sacredforge:BAAALAAECgUIBQAAAA==.Salorian:BAAALAAECgMIAwAAAA==.Samfoo:BAAALAADCggIEAAAAA==.',Sc='Scottypimpin:BAAALAADCggICQAAAA==.',Se='Seaborne:BAAALAADCgcIBwAAAA==.Seath:BAAALAAECgYIDQAAAA==.Selene:BAAALAADCgUIBwABLAAECggIBwABAAAAAA==.',Sg='Sgaeyl:BAAALAAECgYICQAAAA==.',Sh='Shadowsbane:BAAALAADCgEIAQAAAA==.Shamerica:BAEBLAAECoEUAAMFAAgIZyH5AQDSAgAFAAgIZyH5AQDSAgAGAAEI/BkBTQBGAAAAAA==.Shiftyboi:BAAALAADCgYIBgAAAA==.Shocknawe:BAAALAAECgcICgAAAA==.Shortleedin:BAAALAADCgYIBgAAAA==.Shottysnipes:BAAALAAECgMIBAAAAA==.Shreeder:BAAALAADCggICAAAAA==.',Si='Sigtryggr:BAAALAADCgEIAQAAAA==.',Sk='Skileaz:BAAALAADCgcIBwAAAA==.',Sm='Smeesha:BAAALAAECgMIAwAAAA==.',Sn='Snaxwell:BAAALAADCgIIAgAAAA==.Sneeze:BAAALAAECgcICAAAAA==.Snùffles:BAAALAAECgQIBwAAAA==.',Sp='Spekaleks:BAAALAAECgIIAgAAAA==.Spring:BAAALAADCgIIAgABLAAECgYICQABAAAAAA==.',St='Starbuxx:BAAALAAECgMIAwAAAA==.Stillbourn:BAAALAADCgIIAgABLAAECgYICQABAAAAAA==.Stonedork:BAAALAADCgIIAgAAAA==.',Ta='Taha:BAAALAAECgEIAQAAAA==.Tanookii:BAAALAAECgIIAgAAAA==.',Tc='Tchillz:BAAALAAECgcICwAAAA==.',Te='Teehee:BAAALAADCgYIDwAAAA==.Telafar:BAAALAAECggIBgAAAA==.',Th='Thanyssa:BAAALAADCgMIAwAAAA==.Theinsider:BAAALAADCggIDgABLAAECgYIDQABAAAAAA==.',To='Tokuwu:BAAALAADCgIIAgABLAAECgYICQABAAAAAA==.Tootiroo:BAAALAADCggIHQAAAA==.Totemmalotes:BAAALAAECgEIAQAAAA==.',Tr='Trandis:BAAALAAECgYIBgAAAA==.Tranza:BAAALAAECgYICQAAAA==.',Uz='Uzgle:BAAALAAECgMIAwAAAA==.',Wa='Waif:BAAALAAECgYICgAAAA==.',We='Wendys:BAAALAAECgcICwAAAA==.',Wi='Winter:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.Wisceo:BAAALAADCgEIAQAAAA==.',Wo='Woollydragon:BAAALAADCgYIBgAAAA==.',Wr='Wrap:BAAALAAECgYICAAAAA==.',Wt='Wtfmate:BAAALAAFFAIIAgAAAA==.',Xa='Xaioli:BAAALAAECgcICwAAAA==.',Xe='Xethani:BAAALAAECgMIBAAAAA==.',Xs='Xsaber:BAAALAADCgMICAAAAA==.',Ya='Yangyin:BAAALAADCggICAAAAA==.',Ye='Yemeel:BAAALAADCgcIBwAAAA==.',Za='Zalmo:BAAALAAECgQIBwAAAA==.Zatiel:BAAALAAECgIIAgAAAA==.',Zo='Zolmarok:BAAALAAECgEIAQAAAA==.',Zy='Zyrissa:BAAALAAECgMIBAAAAA==.',['Øa']='Øak:BAAALAADCggIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end