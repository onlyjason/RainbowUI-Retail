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
 local lookup = {'Unknown-Unknown','Paladin-Holy','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance',}; local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abadon:BAAALAAECgIIAgABLAAECgcICwABAAAAAA==.',Ac='Accilatem:BAAALAAECgMIAwAAAA==.',Ae='Aeriea:BAAALAAECgMIBAAAAA==.',Af='Afternoontea:BAAALAADCgUIBQAAAA==.',Ai='Aiba:BAAALAAECgIIAgAAAA==.',Ak='Akcloud:BAAALAAECgYIBgAAAA==.Akilles:BAAALAADCgQIAgAAAA==.',Al='Alaeris:BAAALAAECgcIDwAAAA==.Albertehbeef:BAAALAAECgMIAwAAAA==.Albetabeef:BAAALAAECgMIAwAAAA==.Aldrif:BAAALAADCgQIBAAAAA==.Allhopeisded:BAAALAAECgIIAgAAAA==.',Am='Amadeus:BAAALAAECgYIBwAAAA==.Amanita:BAAALAADCgcIBwAAAA==.Amelaista:BAAALAAECgMIAwAAAA==.',An='Andii:BAAALAAECgMIAwAAAA==.Androllex:BAAALAADCgcIBwAAAA==.Angusbeef:BAAALAAECgMIAwAAAA==.Anx:BAAALAAECgIIAgAAAA==.',Ap='Apocalypse:BAAALAADCggICAAAAA==.',Aq='Aquario:BAAALAADCgQIBAABLAAECgcICwABAAAAAA==.',Ar='Arclo:BAAALAADCgYIDAAAAA==.Ardeno:BAAALAADCgcIBwAAAA==.Ardon:BAAALAAECgQIBAAAAA==.Artémîs:BAAALAADCgYICAAAAA==.',As='Asteruis:BAAALAAECgQIBwAAAA==.',Ba='Bangerz:BAECLAAFFIEGAAICAAII5iP4AgDRAAACAAII5iP4AgDRAAAsAAQKgR0AAgIACAgbJW8AAEsDAAIACAgbJW8AAEsDAAAA.Barkenddh:BAAALAAECgMIAwAAAA==.',Be='Belalugosi:BAAALAADCgEIAQAAAA==.',Bj='Bjorum:BAAALAAECgYIBwAAAA==.',Bl='Blorp:BAAALAAECgIIAgAAAA==.',Bo='Bodytwodafa:BAAALAAECgMIAwAAAA==.',Br='Bradinia:BAAALAADCggIEAAAAA==.Brolux:BAAALAADCgYIBgAAAA==.',Bu='Bubbleyou:BAAALAADCggICAAAAA==.',Ca='Cantarella:BAAALAAECgEIAQAAAA==.Carlyle:BAAALAAECgMIAwAAAA==.Casadora:BAAALAADCgcICwABLAAECgEIAQABAAAAAA==.Casadoro:BAAALAAECgEIAQAAAA==.',Ce='Ceci:BAAALAADCggICwAAAA==.Celthon:BAAALAADCgIIAgAAAA==.',Ch='Cheekyteetah:BAAALAADCgYIBgAAAA==.Chromehound:BAAALAADCgMIAwAAAA==.Chumdungler:BAAALAAECgUICQAAAA==.',Co='Cobradeth:BAAALAADCggIDwAAAA==.Collossuss:BAAALAAECgYICAAAAA==.',Cr='Crivens:BAAALAAECgEIAQAAAA==.',Cu='Cuh:BAAALAAECgYIDAAAAA==.',['Cí']='Cíora:BAAALAADCgcIAQAAAA==.',Da='Dabtime:BAAALAADCgMIAwAAAA==.Dafa:BAAALAAECgMIAwAAAA==.',De='Deez:BAAALAADCgQIBAABLAAECgMIBQABAAAAAA==.Deezfists:BAAALAAECgMIBQAAAA==.Dekaar:BAAALAAECgEIAQAAAA==.Demonarden:BAAALAAECgQIBQAAAA==.Derpwar:BAAALAADCgIIAgAAAA==.Desdemonica:BAAALAADCggIEQAAAA==.',Do='Donfalprun:BAAALAADCgcIBwAAAA==.',Dz='Dz:BAAALAADCgcIBwAAAA==.',El='Elij:BAAALAAECgYICAAAAA==.Elunaire:BAAALAAECgcICwAAAA==.',Em='Emelec:BAAALAAECgQIBgAAAA==.Emeraldwish:BAAALAAECgYIBgAAAA==.',En='Encanis:BAAALAADCgYIBgAAAA==.',Ev='Evinco:BAAALAADCggIDwAAAA==.',Fa='Fancy:BAAALAADCgYIBwAAAA==.',Fe='Ferinex:BAAALAAECgYICAAAAA==.',Fi='Fieryember:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.',Fr='Frostwave:BAAALAAECgIIAgAAAA==.',Fu='Fujiyama:BAAALAAECgMICgAAAA==.',Ga='Gaybowser:BAAALAADCggICAAAAA==.',Ge='Geodude:BAAALAADCggICAAAAA==.',Gh='Ghouldylocks:BAAALAADCgcIBwAAAA==.',Gl='Glenndanzig:BAAALAADCgcIDgAAAA==.',Go='Goldenelf:BAAALAAECgMIAwAAAA==.Goldenshield:BAAALAAECgcIDAAAAA==.',Gu='Gupperrino:BAAALAADCgcICQABLAADCggIDwABAAAAAA==.',Ha='Harjatan:BAAALAAECgIIAgAAAA==.',He='Heatindabs:BAAALAAECgQIBwAAAA==.',Ir='Irepa:BAAALAADCgQIBAAAAA==.Irondawn:BAAALAADCgcIBgAAAA==.',Ja='Jamocalypse:BAAALAAECgYICQAAAA==.',Ji='Jinxy:BAAALAAECgEIAQAAAA==.',Ka='Kaalli:BAAALAAECgEIAQAAAA==.Kariopha:BAAALAADCgEIAQAAAA==.',Ke='Kelisa:BAAALAAECgUIBwAAAA==.Kenophobia:BAAALAADCgYICQAAAA==.',Kh='Kharlito:BAAALAADCggIDgAAAA==.',Ki='Kinkster:BAAALAAECgYICAAAAA==.Kirianserey:BAAALAADCgEIAQAAAA==.Kitosol:BAACLAAFFIEKAAIDAAUIexyYAADxAQADAAUIexyYAADxAQAsAAQKgRQAAgMACAh9JHoFAA8DAAMACAh9JHoFAA8DAAAA.',Ks='Kschwev:BAAALAADCgYIBgAAAA==.',Ku='Kuratcha:BAAALAADCggIDQABLAAECgYIBgABAAAAAA==.',Ky='Kyý:BAAALAADCgYIBAAAAA==.',['Kí']='Kíng:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.',Li='Lilicha:BAAALAAECgYICwAAAA==.Listmore:BAAALAADCggIDQAAAA==.',Lo='Locote:BAAALAAECgIIAgAAAA==.',Lu='Lunarqt:BAAALAADCgQIBAAAAA==.Luthais:BAAALAAECgUIBwAAAA==.',Ma='Maaddocta:BAAALAADCgQICQAAAA==.Maadsham:BAAALAADCgEIAQAAAA==.Magicpie:BAAALAADCgMIAwAAAA==.Marthita:BAAALAADCgYIBgAAAA==.',Mc='Mcguzzlin:BAAALAADCgIIAgAAAA==.',Me='Mepawnyou:BAAALAAECgYIBgAAAA==.Mertok:BAAALAAECgIIAgAAAA==.',Mi='Minimum:BAAALAAECgMIAwAAAA==.Mirax:BAAALAADCggICAAAAA==.Mitchmayyne:BAAALAAECgEIAQAAAA==.',Mo='Model:BAAALAAECgMIAwAAAA==.',My='Myfurissoft:BAAALAADCgEIAQAAAA==.Mylianne:BAAALAADCggIEAAAAA==.Mynameiscole:BAABLAAECoEVAAIEAAgI4x9TCAD7AgAEAAgI4x9TCAD7AgAAAA==.Myrolan:BAAALAAECgMIBgAAAA==.',Na='Nakijo:BAAALAAECgEIAQAAAA==.',Ne='Nevyn:BAAALAAECgcIEAAAAA==.',Ni='Nightsage:BAAALAAECgIIAgAAAA==.Nininhp:BAAALAAECgMIBAAAAA==.Nithari:BAAALAAECgMIAwAAAA==.',No='Nost:BAAALAADCgUIBQAAAA==.Nosturi:BAAALAADCgUIBQABLAADCgYICQABAAAAAA==.Now:BAAALAAECgYIBgAAAA==.',Oj='Ojikan:BAAALAAECgYIBgAAAA==.',Pe='Peachoolong:BAAALAAECgMIAwAAAA==.Pepecry:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Petmesoftly:BAAALAAECgIIAgAAAA==.',Ph='Phoblade:BAAALAAECgIIAgAAAA==.',Pi='Pigtenders:BAAALAADCgcIBwAAAA==.Pirotess:BAAALAAECgMIBAAAAA==.',Po='Poofimabear:BAAALAADCgQIBAAAAA==.Poseidess:BAAALAADCgcIBwAAAA==.',Pr='Presibro:BAAALAADCggIDwAAAA==.',Pu='Puck:BAAALAADCggIDwAAAA==.Puppye:BAAALAAECgYIBgAAAA==.',Py='Pyroeuphoria:BAAALAAECgIIAgAAAA==.',Ra='Raboniel:BAAALAADCgUIBQAAAA==.',Re='Reeapally:BAAALAAECgQIBAAAAA==.Reepicheep:BAAALAAECgMIAwAAAA==.',Rh='Rheizen:BAAALAAECgIIBQAAAA==.',Ri='Rice:BAAALAADCgMIAwAAAA==.',Ru='Rumnstuff:BAAALAADCgYICQAAAA==.',Sa='Sakurafire:BAAALAADCggICAAAAA==.Sarafyn:BAAALAAECgIIAgAAAA==.Savagery:BAAALAAECgMIAwAAAA==.',Sc='Schmit:BAAALAADCgYIBwAAAA==.Schreck:BAAALAADCgYIBgAAAA==.',Se='Serenade:BAAALAADCggICAAAAA==.',Sh='Sheepofdeath:BAAALAAECgQIBwAAAA==.Sheepshaman:BAAALAAECgUIBwAAAA==.Sheman:BAAALAADCgUIBwAAAA==.Shotslol:BAAALAAECgQIBwAAAA==.',Si='Siegescale:BAAALAADCgYIBgAAAA==.Sillidari:BAAALAADCgcIBwAAAA==.Sionshope:BAAALAAECgIIAwAAAA==.',Sl='Slayerhunt:BAAALAAECgYICAAAAA==.Slayertin:BAAALAADCgMIAwABLAAECgYICAABAAAAAA==.Slayervoker:BAAALAADCggIDAAAAA==.Sleptforever:BAAALAAECgMIAwAAAA==.',Sn='Snkrsotoole:BAAALAAECgYICAAAAA==.',So='Sorian:BAAALAADCggICAAAAA==.Sorrianna:BAAALAAECgIIAgAAAA==.Soulgar:BAAALAAECggIEQAAAA==.',St='Staggers:BAAALAADCggIEQAAAA==.Stinkfest:BAAALAAECgYIBgAAAA==.Stravas:BAAALAADCgIIAgAAAA==.',Su='Subudai:BAAALAADCggIDQAAAA==.Summondeez:BAAALAADCgcIDAABLAAECgMIBQABAAAAAA==.',Ta='Tacoy:BAAALAAECgMIAwAAAA==.',Tb='Tbizkut:BAAALAAECgMIAwAAAA==.',Th='Then:BAAALAAECgYICQAAAA==.',Ti='Timehunter:BAAALAADCggIFAAAAA==.Timeofdab:BAAALAADCgQIBAAAAA==.',To='Tongpakfu:BAAALAAECgEIAQAAAA==.Topflight:BAAALAAECgMIAwAAAA==.',Tr='Troiikâ:BAAALAAECgcIDQAAAA==.',Tt='Ttevinn:BAAALAAECgMIBwAAAA==.',Tu='Tupacaroni:BAAALAAECgIIAgAAAA==.',Ty='Tycone:BAAALAADCggICwAAAA==.',Uw='Uwantwar:BAAALAADCggIEgAAAA==.',['Vî']='Vîxen:BAAALAAECgIIAgAAAA==.',Wi='Windfuraoibh:BAAALAAECgIIBAAAAA==.',Wr='Wrönged:BAAALAAECgQIBwAAAA==.',Wu='Wunderbar:BAAALAAECgMIBQAAAA==.',Xa='Xannada:BAAALAAECgMIAwAAAA==.',Ya='Yaoli:BAAALAADCgEIAQAAAA==.',Yo='Yoh:BAAALAAECgYIBgAAAA==.',Za='Zaknafeîn:BAAALAAECgYICAAAAA==.Zapali:BAAALAAECgMIBgAAAA==.',Zi='Zip:BAAALAAECggICAAAAA==.',Zu='Zue:BAAALAAECgIIAgAAAA==.',['Zô']='Zôôm:BAABLAAECoEUAAIFAAgIpht7BABeAgAFAAgIpht7BABeAgAAAA==.',['Ðo']='Ðongknight:BAAALAAECgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end