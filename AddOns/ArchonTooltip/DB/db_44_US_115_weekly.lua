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
 local lookup = {'Unknown-Unknown','Monk-Mistweaver','Evoker-Preservation','DeathKnight-Blood','Priest-Shadow','DemonHunter-Havoc','DeathKnight-Frost','Mage-Arcane','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Monk-Windwalker','Hunter-BeastMastery','DeathKnight-Unholy',}; local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Aceridder:BAAALAAECgMIBAAAAA==.',Ai='Aiden:BAAALAADCgMIAwAAAA==.',Am='Aminal:BAAALAAECgQIBQAAAA==.',An='Andronicas:BAAALAAECgEIAQAAAA==.Anghul:BAAALAADCggIBwAAAA==.Antimage:BAAALAADCgQIBAAAAA==.',Ar='Arumat:BAAALAADCgIIAgAAAA==.',As='Aseria:BAAALAAECgUICwAAAA==.',Au='Auramo:BAAALAAECggIDgAAAA==.',Av='Avi:BAAALAADCggICwABLAAECgYIDQABAAAAAA==.',Ba='Baesuzy:BAAALAAECgYIBwAAAA==.Baragas:BAAALAAECgIIAwAAAA==.',Be='Beecee:BAAALAADCgQIBAAAAA==.Beeny:BAABLAAECoEXAAICAAgIbCG9AQAOAwACAAgIbCG9AQAOAwAAAA==.Berzerker:BAAALAADCgcICQAAAA==.',Bi='Binari:BAAALAADCgYICAABLAAECgYICQABAAAAAA==.',Bl='Blackwell:BAAALAAECgIIAgAAAA==.Bladebear:BAAALAAECgIIBAAAAA==.',Br='Brewmæster:BAAALAADCggIFgAAAA==.Brownkent:BAAALAADCgcIBwAAAA==.Bréwmaster:BAAALAAECgMICAAAAA==.',Bu='Bubblôseven:BAAALAAECgMIAwAAAA==.Bucketz:BAAALAADCggIEAAAAA==.Buckiies:BAACLAAFFIEFAAIDAAIIOwMZBQCBAAADAAIIOwMZBQCBAAAsAAQKgRgAAgMACAjTDg4JALQBAAMACAjTDg4JALQBAAAA.Budeen:BAAALAADCgcIBwAAAA==.Budin:BAAALAADCgUIBQAAAA==.',Ca='Cannibal:BAAALAAECgMIBQAAAA==.Capri:BAAALAADCggIFwAAAA==.',Ce='Cellerstar:BAAALAAECgUICAAAAA==.',Ch='Choomoo:BAAALAAECgMIAwAAAA==.',Cr='Crikey:BAAALAADCggIEAAAAA==.',Cv='Cvmage:BAAALAAECgYIDgAAAA==.',Da='Daga:BAAALAAECgcIEAAAAA==.',De='Deborah:BAAALAADCgcIBwABLAAECgYIDwABAAAAAA==.Desariana:BAAALAAECgMIBgAAAA==.Deshar:BAAALAAECgcICwAAAA==.',Do='Dormas:BAAALAADCgcICQAAAA==.Doxy:BAAALAAECgMIAwAAAA==.',Dr='Drabrew:BAAALAADCgQIBAAAAA==.Drunkdriving:BAAALAADCgcIBwAAAA==.',El='Eldh:BAAALAAECgIIAwAAAA==.Elisoly:BAAALAADCgYIBgAAAA==.',Em='Emrald:BAAALAAECgUICwAAAA==.',En='Endlessly:BAAALAAECgcIEgAAAA==.',Es='Eshaylad:BAAALAADCggICAAAAA==.',Ev='Evelinar:BAAALAAECgMIAwAAAA==.Evoslex:BAAALAAECgYIDgAAAA==.',Ex='Exo:BAABLAAECoEWAAIEAAgIzh3UAwCVAgAEAAgIzh3UAwCVAgAAAA==.',Fa='Facerolleh:BAAALAADCgEIAQABLAAFFAMIBQAFAJ0aAA==.Fatalcoholic:BAAALAADCgUIBQAAAA==.Fatedx:BAAALAADCggIEAAAAA==.',Fi='Fidah:BAAALAADCgcIDwAAAA==.Fishiefist:BAAALAADCgcIBwAAAA==.',Fl='Flappyboï:BAAALAAECgYICQAAAA==.',Fr='Frieren:BAAALAAECgYIDwAAAA==.Frostmere:BAAALAADCgcIDQAAAA==.',Fu='Fuknazum:BAAALAAECgMIAwAAAA==.Furcht:BAAALAADCggIDgAAAA==.',Gi='Girthtotem:BAAALAADCgcIBwAAAA==.Giteff:BAACLAAFFIEFAAIGAAMIYBZrAwAOAQAGAAMIYBZrAwAOAQAsAAQKgRcAAgYACAjFJlsAAJMDAAYACAjFJlsAAJMDAAAA.Giveroflife:BAAALAADCggIFQAAAA==.',Gr='Granny:BAAALAADCggICAAAAA==.Grumblefluff:BAAALAAECgYIDgAAAA==.',Gu='Gulnah:BAAALAADCgcIBwAAAA==.',Ha='Harcon:BAAALAADCgMIAwAAAA==.',He='Hellbourne:BAAALAADCgcIDgAAAA==.Heât:BAAALAAECgEIAQAAAA==.',Ho='Horsé:BAAALAADCggIDQABLAADCggIEAABAAAAAA==.',Hu='Huntchoq:BAAALAAECgYICgAAAA==.',['Hð']='Hðly:BAAALAAECggIAQAAAA==.',In='Infest:BAAALAAECgMIBgAAAA==.',Ir='Iraia:BAAALAADCgQIBAAAAA==.',Iu='Iuna:BAAALAADCgYIBgAAAA==.',Ji='Jimmothy:BAAALAAECgEIAQAAAA==.',Jj='Jjthomas:BAAALAAECgEIAQAAAA==.',Jo='Jothundar:BAAALAADCgYIBgAAAA==.',Ka='Kalzaketh:BAAALAAECgMIAwAAAA==.Kashari:BAAALAADCggICAAAAA==.Katarina:BAAALAAECgEIAQAAAA==.Katälyst:BAAALAADCgYIBgAAAA==.Kazuggar:BAAALAAECgYIBwAAAA==.',Ke='Kelis:BAAALAADCggIDgAAAA==.',Kh='Khhan:BAAALAAECgIIAgAAAA==.Khorgus:BAAALAADCgUICgAAAA==.',Ki='Killerman:BAACLAAFFIEFAAIHAAMIcRxKAgAVAQAHAAMIcRxKAgAVAQAsAAQKgRcAAgcACAiPJhIBAHIDAAcACAiPJhIBAHIDAAAA.Kirjek:BAAALAADCgcIDQAAAA==.Kitingbrb:BAACLAAFFIEFAAIIAAMI9hcnBQD7AAAIAAMI9hcnBQD7AAAsAAQKgRgAAwgACAi3JssAAHgDAAgACAi3JssAAHgDAAkAAQi4Gws/AEQAAAAA.',Ko='Korana:BAAALAADCgcIBwAAAA==.',Kr='Kregnar:BAAALAAECgIIAwAAAA==.',Ku='Kuroha:BAAALAAECggIAwAAAA==.',Kw='Kwichang:BAAALAADCggIDAAAAA==.',Ky='Kyndariae:BAAALAADCggIFwAAAA==.',La='Lapinhom:BAAALAADCgcIEwAAAA==.Lapinhours:BAAALAAECgcIDQAAAA==.',Li='Lickynose:BAAALAAECgMICAAAAA==.',Lu='Lunaless:BAAALAAECgMIBAAAAA==.Lurr:BAAALAAECgYIBwAAAA==.',Ly='Lyth:BAAALAAECgcIEAAAAA==.Lyån:BAAALAAECgUICgAAAA==.',Ma='Mann:BAAALAAECgMICAAAAA==.Mantisar:BAAALAADCgMIAgAAAA==.Marmite:BAAALAAECgYIBgAAAA==.',Mi='Mightymuffin:BAAALAAECgcICgAAAA==.Mirrorimage:BAAALAAECgMICAAAAA==.Mirrorx:BAAALAAFFAEIAQAAAA==.',Mo='Mongon:BAAALAADCgUIBQAAAA==.Moosfel:BAAALAADCgcIBwAAAA==.Morpheus:BAAALAAECgIIAgAAAA==.',Mt='Mtzz:BAAALAADCgQIBAAAAA==.',Mu='Mudcake:BAAALAAECgMIBwAAAA==.Mudrock:BAAALAAECgYIBgAAAA==.',My='Mystweaverr:BAAALAAECgYIDwAAAA==.',Na='Nahalura:BAAALAAECgYIDQAAAA==.Natery:BAAALAADCggICAAAAA==.',Ni='Nikonii:BAAALAAECgQIBwAAAA==.',No='Nofingers:BAAALAAECgEIAQAAAA==.November:BAAALAADCgQIBAAAAA==.',Nu='Numb:BAAALAAECggIEwAAAA==.',Oa='Oakinhoof:BAAALAAECggIEQAAAA==.',Om='Omnishifts:BAAALAADCggICAAAAA==.',Po='Pokoklongan:BAAALAADCgcIBwAAAA==.Popemangali:BAAALAADCggICAAAAA==.',Pr='Priestrolleh:BAACLAAFFIEFAAIFAAMInRrMAQArAQAFAAMInRrMAQArAQAsAAQKgRcAAgUACAiWIy4EAB8DAAUACAiWIy4EAB8DAAAA.Prothero:BAAALAAECgcIDwAAAA==.',['På']='Påthor:BAAALAADCgcIDQAAAA==.',Qu='Quickjolt:BAAALAADCgMIAwAAAA==.',Re='Rebelsister:BAAALAADCggIFAAAAA==.',Ri='Ridgemonk:BAAALAAECgUIBgAAAA==.Riggse:BAACLAAFFIEGAAMKAAMIgiBsAAAoAQAKAAMIgiBsAAAoAQALAAEIBCLxCABhAAAsAAQKgRgAAwsACAgGJncBAEgDAAsACAh1JXcBAEgDAAoACAh2IOAAABgDAAAA.Riggshunt:BAAALAAECgIIAgABLAAFFAMIBgAKAIIgAA==.Riotthunder:BAAALAADCggIEQAAAA==.',Ro='Roadkill:BAAALAAECgEIAQAAAA==.Rolltoor:BAABLAAECoEdAAIMAAgIth0XBQCrAgAMAAgIth0XBQCrAgAAAA==.',Sa='Safeword:BAAALAAECgIIAwAAAA==.Saiko:BAAALAAECgMIAwAAAA==.Sansa:BAABLAAECoEUAAINAAgITR7uCgCyAgANAAgITR7uCgCyAgAAAA==.Saso:BAACLAAFFIEFAAIIAAMInBIOBQD8AAAIAAMInBIOBQD8AAAsAAQKgRcAAggACAgcJRkFACUDAAgACAgcJRkFACUDAAAA.Sastroll:BAAALAADCgYIBwAAAA==.Sathina:BAAALAADCggIEAAAAA==.Saxobeats:BAAALAADCgcIBwAAAA==.',Sc='Scroll:BAAALAAECggIDgAAAA==.',Se='Selil:BAAALAADCggIEAAAAA==.',Si='Silphi:BAAALAAECgMIAwAAAA==.Silphy:BAAALAADCggIEAAAAA==.Sindar:BAAALAAECgMIAwAAAA==.',Sk='Sky:BAAALAAECggIEgAAAA==.',Sl='Slex:BAAALAADCgUIBQABLAAECgYIDgABAAAAAA==.',Sn='Snugglepuff:BAAALAAECgMIBwAAAA==.',Sv='Svendlelynn:BAAALAAECgEIAgAAAA==.',Sw='Swirly:BAAALAADCgQIBAAAAA==.',Ta='Talion:BAAALAADCgEIAQAAAA==.',Te='Tealç:BAAALAAECgcIEQAAAA==.Teara:BAAALAAECgcIEAAAAA==.',Th='Thalaris:BAAALAAECggICwAAAA==.Thor:BAAALAAECgEIAQAAAA==.Thuraya:BAAALAAECgIIBAAAAA==.',Ty='Tyladrhas:BAAALAAECgYICgAAAA==.Tyrant:BAAALAAECgMIBQAAAA==.Tyrismaximus:BAAALAADCggICQAAAA==.',Up='Up:BAAALAAECgMICAAAAA==.',Va='Valcry:BAAALAADCgEIAQAAAA==.Vanoran:BAAALAAECgEIAQAAAA==.',Ve='Velorah:BAAALAADCggIEgAAAA==.',Vo='Voldezee:BAAALAAECgMIBgAAAA==.',Vu='Vulken:BAAALAAECgMIAwAAAA==.',Wi='Wimbly:BAAALAADCgYIBgAAAA==.',Za='Zarek:BAAALAAECgEIAQAAAA==.',Zi='Zich:BAAALAADCggICAAAAA==.Zihon:BAABLAAECoEVAAIOAAgIIxejBwAsAgAOAAgIIxejBwAsAgAAAA==.',Zo='Zodiiak:BAAALAADCgcIDAAAAA==.',Zz='Zzcatalockzz:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end