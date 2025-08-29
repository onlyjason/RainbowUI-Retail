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
 local lookup = {'Unknown-Unknown','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker',}; local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abaddøn:BAAALAADCgcIBwABLAADCgcIFQABAAAAAA==.Abyssius:BAAALAAECgUIBwAAAA==.',Ac='Acalinna:BAAALAADCgcIBwAAAA==.',Ad='Adrenaleen:BAAALAAECgEIAQAAAA==.',Ae='Aeriss:BAAALAADCgMIAwAAAA==.Aezili:BAAALAADCgcIDgAAAA==.',Ag='Agnessa:BAAALAADCggIFQAAAA==.',Ak='Akafabu:BAAALAAECgMIAwABLAAECgYIDwABAAAAAA==.Akumunter:BAAALAADCgcIAwAAAA==.Akuryujin:BAAALAAECgQIBgAAAA==.',Al='Alacardias:BAAALAAECgYICQAAAA==.Alcaedra:BAAALAAECgUICAAAAA==.Aloni:BAAALAADCgEIAQAAAA==.Alphred:BAAALAAECgIIAwAAAA==.Alucarddeus:BAAALAAECgYIBwAAAA==.',Am='Amäri:BAAALAAECgYIDwAAAA==.',An='Andikin:BAAALAADCgUICQAAAA==.Andimorph:BAAALAAECgYICQAAAA==.Anymaul:BAAALAADCggICAAAAA==.',Ap='Aphrodíte:BAAALAAECgYICgAAAA==.',Aq='Aquane:BAAALAADCgcIAwAAAA==.Aquashade:BAAALAADCggICAABLAAECgYICgABAAAAAA==.Aquaterra:BAAALAAECgYICgAAAA==.',Ar='Araenis:BAAALAADCgUIBQAAAA==.Arakadia:BAAALAAECgYIDAAAAA==.Aratiri:BAAALAADCggICAAAAA==.Arkhanna:BAAALAAECgEIAQAAAA==.Arlok:BAAALAADCgYICAABLAADCgcIBwABAAAAAA==.Aruteeru:BAAALAAECgEIAQAAAA==.',As='Assumption:BAAALAADCgYIBgAAAA==.Astallivan:BAAALAADCggICAAAAA==.',Au='Auro:BAABLAAECoEVAAICAAgIfB8jCQDWAgACAAgIfB8jCQDWAgAAAA==.',Aw='Awhro:BAAALAADCggICAAAAA==.',Ax='Axará:BAAALAADCgUIBgAAAA==.',Ay='Ayala:BAAALAAECgYIBQAAAA==.',Az='Azaireos:BAAALAADCggIFQAAAA==.Azamon:BAAALAAECgIIAwAAAA==.Azark:BAAALAADCgIIAgABLAADCgcIBwABAAAAAA==.Azulpunkt:BAAALAAECggIBwAAAA==.',Ba='Baddaboomkin:BAAALAAECgMIBAAAAA==.Bake:BAAALAADCgQIBAAAAA==.Balerión:BAAALAADCgcIDgAAAA==.Bananakin:BAAALAADCgQIBAAAAA==.',Be='Bearmachine:BAAALAAECgYICgAAAA==.Beastknight:BAAALAAECgYICAAAAA==.Beastonka:BAAALAADCgQIBAABLAAECgYICAABAAAAAA==.',Bl='Blackpink:BAAALAADCgUIBQAAAA==.Blessie:BAAALAADCgcIBwAAAA==.Blitzburg:BAAALAADCgcICAAAAA==.',Bo='Boppaheks:BAAALAAECgcIDwAAAA==.',Br='Bravos:BAAALAADCggICQAAAA==.Braw:BAAALAADCggICAAAAA==.Brewsleroy:BAAALAADCgcICgAAAA==.Brewtwo:BAAALAADCgcIDgAAAA==.Briony:BAAALAADCgQIBAAAAA==.Bruute:BAAALAAECgYICgAAAA==.',Bu='Budplatinum:BAAALAADCgcIFgAAAA==.Bulletdodger:BAAALAAECgIIAgAAAA==.Bum:BAAALAADCgcIBwABLAADCgcIFQABAAAAAA==.Butchlesbian:BAAALAAECgEIAQAAAA==.',['Bá']='Bábayága:BAAALAADCgYICgAAAA==.',['Bâ']='Bâit:BAAALAADCggICAABLAAECggICAABAAAAAA==.Bâït:BAAALAAECggICAAAAA==.',['Bÿ']='Bÿ:BAAALAADCgcIBwAAAA==.',Ca='Cairo:BAAALAAECgQIBwAAAA==.Caoang:BAAALAAECgEIAQAAAA==.Cashara:BAAALAADCgcIDAAAAA==.Castayon:BAAALAADCggICAAAAA==.',Ce='Ceàrrdòrn:BAAALAAECgUIBwAAAA==.',Ch='Chillzmatic:BAABLAAECoElAAMDAAcIlBkqKADMAQADAAcIjBQqKADMAQAEAAMIESBxEwAJAQAAAA==.Chirri:BAAALAADCgcICgAAAA==.Chondriac:BAAALAADCgQIBAAAAA==.',Ci='Cinia:BAAALAAECggIEgAAAA==.',Cr='Crepitate:BAAALAADCggICAABLAAECggICAABAAAAAA==.Crunchwich:BAAALAADCgcIAwAAAA==.',Cu='Cutename:BAAALAADCgYIBgAAAA==.',Cy='Cynamyn:BAAALAADCgcIAwAAAA==.Cypress:BAAALAAECgEIAQAAAA==.',Cz='Czeskilight:BAAALAADCgYIBgAAAA==.Czheals:BAAALAAECgEIAQAAAA==.Czmage:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Da='Daane:BAAALAADCggIEgAAAA==.Dahiwon:BAAALAADCgUIBQAAAA==.Dakhran:BAAALAADCgcIBwAAAA==.Dakkä:BAAALAADCggIDQAAAA==.Darkbelt:BAAALAADCgcIBwAAAA==.Darksmîter:BAAALAAECgUIBQAAAA==.Darkstryder:BAAALAAECgMIBAAAAA==.Darkwingdot:BAAALAADCgcIDQAAAA==.Darlord:BAAALAADCgcIAwAAAA==.Datamus:BAAALAAECgYICAAAAA==.Dawncarlos:BAAALAAECgEIAQAAAA==.Daxgrol:BAAALAAECgYIDQAAAA==.Dazril:BAAALAAECgIIAwAAAA==.',De='Deandrya:BAAALAAECgMIAwAAAA==.Demonavatar:BAAALAADCgQIBAAAAA==.Demonwidow:BAAALAADCggIDwAAAA==.Demônlock:BAAALAADCgcIAwAAAA==.Desideria:BAAALAAECgIIAwAAAA==.Despondence:BAAALAADCggICAAAAA==.Desynn:BAAALAAECgYIDQAAAA==.',Di='Divinesyn:BAAALAAECgcIDgAAAA==.',Do='Dogman:BAAALAADCgYIBgAAAA==.Doormos:BAAALAADCggICAAAAA==.Dotty:BAAALAADCgcICAAAAA==.Doubtful:BAAALAAECgEIAQAAAA==.',Dr='Dracow:BAAALAAECgIIAgAAAA==.Drengorar:BAAALAAECgIIAwAAAA==.Drâcârys:BAAALAADCggIDQAAAA==.',Du='Duberrok:BAAALAAECgMIAwAAAA==.',['Dà']='Dàmeaelin:BAAALAADCggIDQAAAA==.',El='Elasper:BAAALAADCgMIAwAAAA==.',Em='Emelianas:BAAALAAECgEIAQAAAA==.',En='Entheogen:BAAALAAECgMIAwAAAA==.',Er='Eree:BAAALAADCgYIBgAAAA==.Ermoonsia:BAAALAADCgYIBgAAAA==.Erolas:BAAALAADCggIFQAAAA==.Erroon:BAAALAAECgQIBAAAAA==.',Ev='Evalilly:BAAALAADCgQIBAAAAA==.Evanessance:BAAALAAECgIIAwAAAA==.Evilice:BAAALAAECgMIAwAAAA==.Evoka:BAAALAAECgQIBAAAAA==.',Fa='Fadonis:BAAALAADCggICAAAAA==.Fahndoo:BAAALAADCgMIBAAAAA==.Fallendots:BAAALAADCgYIBgAAAA==.Fallenpally:BAAALAADCgUIBQAAAA==.Fallenvirtue:BAAALAAECgQIBgAAAA==.Fangbeary:BAAALAAECgIIAgAAAA==.Favi:BAAALAADCgcIBwAAAA==.Fayia:BAAALAADCgYICQAAAA==.Fayye:BAAALAADCgcIDgAAAA==.Faávi:BAAALAAECggICAAAAA==.',Fe='Fellin:BAAALAAECgIIAwAAAA==.Fervor:BAAALAAECgYICAAAAA==.',Fi='Fireflydh:BAAALAADCgYIAQAAAA==.Firèflyjd:BAAALAAECgEIAQAAAA==.Fizzlebrawl:BAAALAADCgMIAwAAAA==.',Fl='Floatpass:BAAALAAECgYIDAAAAA==.',Fr='Fragile:BAAALAAECgYICAAAAA==.Frizz:BAAALAADCgcIAwAAAA==.Frozenn:BAAALAAECgMIAwAAAA==.',Fu='Fuzzymonk:BAAALAADCgQIBAAAAA==.Fuzzynuttz:BAAALAAECggICAAAAA==.Fuzzytotems:BAAALAAECgcIDwAAAA==.',Fy='Fynickx:BAAALAAECgYIBgAAAA==.Fyniick:BAAALAADCgcIBwAAAA==.Fyresdal:BAAALAADCggIFgAAAA==.Fyrie:BAAALAADCgQIBAAAAA==.',['Fí']='Fíx:BAAALAADCgEIAQAAAA==.',Ga='Gallynna:BAAALAAECgUICAAAAA==.Galorfax:BAAALAAECggICAAAAA==.Galushi:BAAALAADCggIFQAAAA==.Ganicuz:BAAALAAECgIIAgAAAA==.Garlic:BAAALAADCgcIFQAAAA==.Gatok:BAAALAADCgMIBQAAAA==.',Ge='Genovese:BAAALAAECgMIBAAAAA==.',Gh='Ghundar:BAAALAADCgUIBgAAAA==.',Gi='Gilgaroth:BAAALAAECgIIAgAAAA==.Gimliy:BAAALAAECgIIAgAAAA==.',Go='Gorendish:BAAALAAECgMIAwAAAA==.',Gr='Graysonn:BAAALAADCggIEwAAAA==.Gròót:BAAALAAECgUIBwAAAA==.',Ha='Hame:BAAALAAECgEIAQAAAA==.',He='Hectic:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Heid:BAAALAADCggIEgAAAA==.Hellsong:BAAALAADCggIFAAAAA==.Henry:BAAALAADCgcIDgAAAA==.',Hi='Higanbana:BAAALAAECgYIDgAAAA==.',Ho='Holdentudix:BAAALAADCgcICwAAAA==.Hotshotzz:BAAALAADCgUIBQABLAAECgcIEwABAAAAAA==.',Hr='Hrodebert:BAAALAADCgcIBwABLAADCgcIEAABAAAAAA==.',Hu='Hubcapthief:BAAALAADCgYICwAAAA==.',['Há']='Háldrin:BAAALAAECggIEQAAAA==.',['Hö']='Höpè:BAAALAAECgYIEAAAAA==.',In='Incinerette:BAAALAAECgQIBAAAAA==.',Io='Iolite:BAAALAADCgcIAwAAAA==.',Is='Isimiel:BAAALAADCgcIDAAAAA==.Isneezed:BAAALAAECgMIBAAAAA==.',Ja='Jaberjo:BAAALAAECgYICQAAAA==.Jameson:BAAALAADCgUIBAAAAA==.',Je='Jezebel:BAAALAAECgMIBQAAAA==.',Ji='Jinxing:BAAALAAECgIIAgAAAA==.Jirto:BAAALAADCgcIFQAAAA==.',Jo='Jomadead:BAAALAAECgUIBwABLAAECggIGAAFAI4VAA==.Jomadin:BAAALAADCgcIBwABLAAECggIGAAFAI4VAA==.Jomagon:BAABLAAECoEYAAMFAAgIjhVTBgALAgAFAAgIjhVTBgALAgAGAAEItQjoMwBAAAAAAA==.',Ju='Judera:BAAALAAECggICQAAAA==.',Ka='Kaine:BAAALAAECgMIBAAAAA==.Kaing:BAAALAADCggICwAAAA==.Kainlithia:BAAALAAECgQIBAAAAA==.Kaladen:BAAALAAECgYICQAAAA==.Kaldirmi:BAAALAADCgcIBwAAAA==.Kalysti:BAAALAAECgUIBwAAAQ==.Kandee:BAAALAAECgYICwAAAA==.Karkonas:BAAALAAECgYICQAAAA==.Karvis:BAAALAAECgMIAwAAAA==.Kasdaan:BAAALAAECgUIBwAAAA==.Katostrafic:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.Kazesun:BAAALAAECgEIAQAAAA==.',Ki='Killboi:BAAALAAECgEIAQAAAA==.Killidan:BAAALAAECgcIDwAAAA==.Kimblit:BAAALAADCgcIBwAAAA==.Kimimela:BAAALAADCggIEAAAAA==.Kiridus:BAAALAAECgUIBwAAAA==.Kirklees:BAAALAADCgcIAgAAAA==.',Kn='Knackers:BAAALAADCgcIDQAAAA==.',Ko='Kookiesplz:BAAALAAECgIIAgAAAA==.',Ku='Kunpochiken:BAAALAAECgMIAwAAAA==.Kurasa:BAAALAAECgYIBgAAAA==.',Ky='Kyanna:BAAALAADCgcIAwAAAA==.',La='Lader:BAAALAADCggIEAAAAA==.Lasarian:BAAALAADCgcIBwAAAA==.Laurebeth:BAAALAAECgEIAQAAAA==.Laxinstorm:BAAALAADCggIFQAAAA==.',Le='Leaky:BAAALAADCgQIBAAAAA==.Leenei:BAAALAADCgcIAwAAAA==.Lenlaar:BAAALAADCgcIAwAAAA==.Lesserafim:BAAALAADCgMIAwAAAA==.Lethimcook:BAAALAAECgYIBwAAAA==.Levande:BAAALAAECgQICQAAAA==.',Li='Lifeblume:BAAALAAECgMIBgAAAA==.Lilsmackya:BAAALAADCgcICQAAAA==.Lilyola:BAAALAADCgcIBwAAAA==.Linamar:BAAALAADCggIDgAAAA==.Lisanda:BAAALAAECgYIDwAAAA==.',Ll='Llaira:BAAALAAECgEIAQAAAA==.',Lo='Loaq:BAAALAAECgIIAgAAAA==.Loss:BAAALAAECgMIBwAAAA==.Losti:BAAALAAECgYICAAAAA==.',Lu='Lucyfur:BAAALAADCgcIBwAAAA==.Lumafist:BAAALAAECgYIDAAAAQ==.Luxæterna:BAAALAAECgYIDQAAAA==.',Ly='Lystrasza:BAAALAAECgEIAQAAAA==.',['Lø']='Løki:BAAALAAECgYICQAAAA==.',Ma='Maeria:BAAALAADCgQICAAAAA==.Mahoragaa:BAAALAAECgIIAwAAAA==.Malefesent:BAAALAADCggICAAAAA==.Malemenas:BAAALAADCgcIBwAAAA==.Malice:BAABLAAECoEVAAIHAAcI6B2iAgB+AgAHAAcI6B2iAgB+AgAAAA==.Maraliss:BAAALAAECgEIAQAAAA==.Marjon:BAAALAADCggIEAAAAA==.',Me='Mechatwerk:BAAALAADCggIFwAAAA==.Mediocreelf:BAAALAAECgQIBwAAAA==.Melaunis:BAAALAAECgEIAQAAAA==.Melîsandre:BAAALAADCggICQAAAA==.Meora:BAAALAADCgYIBgAAAA==.Meteora:BAAALAAECgcIEgAAAA==.',Mi='Mideel:BAAALAADCgcIAwAAAA==.Migolbearcow:BAAALAAECgYICQAAAA==.Miisty:BAAALAAECgYICQAAAA==.Missrae:BAAALAADCgcIBwAAAA==.',Mo='Mombear:BAAALAAECgYIDAAAAA==.Mongocrush:BAAALAAECgEIAQAAAA==.Monyshot:BAAALAADCgcICgAAAA==.Moondizzle:BAAALAAECgEIAQAAAA==.Mooniè:BAAALAADCgYIBgAAAA==.Moosefire:BAAALAADCggIEAAAAA==.Moosenuts:BAAALAADCgcIBwAAAA==.',Mu='Muradigme:BAAALAAECgEIAQAAAA==.Murlock:BAAALAADCggICAAAAA==.',My='Myshella:BAAALAAECgUIBQAAAA==.Myvirtues:BAAALAAECgIIAgAAAA==.Myylus:BAAALAADCgcIDgAAAA==.',['Mó']='Mórrígân:BAAALAADCgEIAQAAAA==.',['Mö']='Mökes:BAAALAAECgcIDQAAAA==.',Na='Nadröj:BAAALAADCgcIDQAAAA==.Nairnmage:BAACLAAFFIEFAAIIAAMIRx/ZAgAmAQAIAAMIRx/ZAgAmAQAsAAQKgRcAAggACAg9JmABAGcDAAgACAg9JmABAGcDAAAA.Nali:BAAALAADCgMIBAAAAA==.Nariand:BAAALAADCgcIBwAAAA==.Nazzersaurus:BAAALAAECgQIBgAAAA==.',Ne='Neodin:BAAALAADCggIDgAAAA==.Nevermiss:BAAALAADCgcICAAAAA==.Nevest:BAAALAAECgEIAQAAAA==.Newhamme:BAAALAADCggICwAAAA==.',Ni='Nialli:BAAALAADCgQIBAAAAA==.Nickoftime:BAAALAADCgQIBAAAAA==.Nightglaive:BAAALAADCgUICAAAAA==.Nightjewel:BAAALAADCggIFQAAAA==.Nineero:BAAALAAECgEIAQAAAA==.',No='Noggs:BAAALAADCgcIDgAAAA==.Nokkas:BAAALAADCggICAAAAA==.',Nu='Nuali:BAAALAAECgUICAABLAAECgYIBgABAAAAAA==.',Od='Oddric:BAAALAADCgYICgAAAA==.',On='Onyxthunder:BAAALAAECgMIBAAAAA==.',Or='Orala:BAAALAAECgIIAwAAAA==.Orý:BAAALAAECgMIBAAAAA==.',Ox='Oxosorrel:BAAALAAECgMIBAAAAA==.',Pa='Palagi:BAAALAAECgEIAQAAAA==.Pamorlin:BAAALAADCgEIAQAAAA==.Pandaemonea:BAAALAAECgIIAgAAAA==.Pandame:BAAALAADCgcIDgAAAA==.Papaphobia:BAAALAAECgYICQAAAA==.Parallax:BAAALAADCgYIBgAAAA==.Parishealton:BAAALAADCggIEQAAAA==.Pastybeard:BAAALAADCggICAAAAA==.',Pi='Pinkburrito:BAAALAAECgMIAwAAAA==.Piratereeses:BAAALAAECgUICAAAAA==.',Po='Poulsbo:BAAALAADCgcIAwAAAA==.Powerlinè:BAAALAADCggICgAAAA==.',Pr='Probs:BAAALAAECgIIAgAAAA==.Prominence:BAAALAAECgMIBQAAAA==.Prozak:BAAALAAECgYICQAAAA==.',Pu='Puhlayden:BAAALAAECgcIDwAAAA==.',Py='Pyrolily:BAAALAADCggIDgAAAA==.',Qu='Quansugi:BAAALAADCggICAAAAA==.',Qy='Qylinu:BAAALAAECgUIBAAAAA==.',Ra='Rachnera:BAAALAADCgUIBgAAAA==.Rageblood:BAAALAADCgcICgAAAA==.Rakur:BAAALAAECgMIAwAAAA==.Raskela:BAAALAAECgcIDQAAAA==.',Re='Reportyrself:BAAALAAECggICAAAAA==.Rexi:BAAALAAECgIIAgAAAA==.Reyah:BAAALAAECgMIBQAAAA==.',Rh='Rhane:BAAALAADCggIFQAAAA==.Rhysen:BAAALAAECgIIAgAAAA==.',Ri='Rickcando:BAAALAADCgMIAwAAAA==.Ricshard:BAAALAAECgUIBQAAAA==.Ridjeckgron:BAAALAADCgcIDgAAAA==.Rimz:BAAALAADCgYICQAAAA==.Ringostars:BAAALAADCgMIAwAAAA==.',Ro='Rodgers:BAAALAADCggICAAAAA==.Romina:BAAALAADCgMIAwAAAA==.Romuluskin:BAAALAADCgEIAQAAAA==.Roobee:BAAALAADCggIDwAAAA==.',Ru='Rungar:BAAALAAECgEIAQAAAA==.',Ry='Rylia:BAAALAADCgcICwAAAA==.Ryukyu:BAAALAADCgUIBQAAAA==.',['Ró']='Ród:BAAALAADCgIIAgABLAAECgcIEwABAAAAAA==.',Sa='Saalira:BAAALAADCggIDwAAAA==.Sabellice:BAAALAAECgUIBwAAAA==.Saethalas:BAAALAAECgEIAQAAAA==.Sakonna:BAAALAAECgcIEwAAAA==.Salchygood:BAAALAAECgYIBgAAAA==.Samokablunt:BAAALAADCgYICQAAAA==.Sandymaw:BAAALAAECgcICwAAAA==.Sassybuns:BAAALAADCggICAAAAA==.Satyrical:BAAALAAECgIIAgAAAA==.Savin:BAAALAAECgEIAQAAAA==.',Sc='Scall:BAAALAAECgMICAAAAA==.Scrat:BAAALAADCgcIBwAAAA==.',Se='Selkamonk:BAAALAAECgYIDwAAAA==.Senissa:BAAALAADCgQIBAAAAA==.Sentrina:BAABLAAECoEaAAIFAAgIKR1JAgC5AgAFAAgIKR1JAgC5AgAAAA==.Seramon:BAAALAADCggIEAAAAA==.Seshy:BAAALAADCgcICgABLAAECgcICwABAAAAAA==.Seshymutedme:BAAALAAECgMIBQABLAAECgcICwABAAAAAA==.',Sh='Shamwû:BAAALAAECgcIEwAAAA==.Shannon:BAAALAADCgYICQABLAADCgcIDgABAAAAAA==.Shannoon:BAAALAADCgcIDgAAAA==.Shaylyne:BAAALAAECgMIBgAAAA==.Sheetal:BAAALAAECgIIAgAAAA==.Shiftlin:BAAALAAECgIIAwAAAA==.Shimmiiee:BAAALAAECgMIBQAAAA==.Shiverr:BAAALAADCgIIAgAAAA==.Shotzz:BAAALAAECgQIBgAAAA==.Showfeet:BAAALAADCgMIBAAAAA==.Shurtugal:BAAALAAECgEIAQAAAA==.Shánkyou:BAAALAADCgcICAAAAA==.',Si='Sitx:BAAALAAECgEIAQAAAA==.',Sk='Skanara:BAAALAAECgMIBAAAAA==.Skott:BAAALAADCggIDwAAAA==.Skïnnyßetch:BAAALAADCgQIBAAAAA==.',Sl='Slicedbraed:BAAALAAECgQIBAABLAAECgYIBgABAAAAAA==.Slicedbreád:BAAALAADCgMIAwABLAAECgYIBgABAAAAAA==.Slícedbread:BAAALAADCgYICwABLAAECgYIBgABAAAAAA==.',Sm='Smilyface:BAAALAADCgEIAQAAAA==.Smol:BAAALAAECgIIAgAAAA==.',So='Softhoof:BAAALAADCgMIAwAAAA==.Solignis:BAACLAAFFIEFAAICAAMIvSVAAQBVAQACAAMIvSVAAQBVAQAsAAQKgRgAAgIACAi/JhgAAJ0DAAIACAi/JhgAAJ0DAAAA.Soohots:BAAALAAECgEIAQAAAA==.Soulen:BAAALAAECgMIAwAAAA==.',Sp='Sparklehappy:BAAALAAECgQICAAAAA==.Speedwagon:BAAALAADCgcICwAAAA==.Spoghasm:BAAALAADCgcICwAAAA==.Spothoof:BAAALAAECgEIAQAAAA==.Spunkbubble:BAAALAADCgIIAgAAAA==.',Sq='Squeak:BAAALAAECgcIDAAAAA==.Sqú:BAAALAADCgQIBAAAAA==.',Ss='Ssrathi:BAAALAADCgQIBAAAAA==.',St='Star:BAAALAAECgIIAgAAAA==.Starføx:BAAALAAECgYICQAAAA==.Starshield:BAAALAADCggICAAAAA==.Stcupertino:BAAALAAECgMIAwAAAA==.Stonefury:BAAALAAECgYIDAAAAA==.Storri:BAAALAAECgEIAQAAAA==.',Su='Suehunter:BAAALAADCgcIBwAAAA==.Suoiler:BAAALAAECggIBwAAAA==.',Sw='Swoggers:BAAALAAECgcIDwAAAA==.',Sy='Syjin:BAAALAAECgYIBgAAAA==.Sylvexina:BAAALAADCgMIAgAAAA==.Syndrome:BAAALAAECgMIAwAAAA==.Synger:BAAALAADCgcICwAAAA==.Synnøve:BAAALAADCgUIBQAAAA==.Sythka:BAAALAADCggICAAAAA==.',Ta='Tabiitha:BAAALAADCgMIAwABLAAECgYIDQABAAAAAA==.Talyndis:BAABLAAECoEYAAMJAAgIoCWIAQBhAwAJAAgIoCWIAQBhAwAKAAIIkSS1MQDPAAAAAA==.Talytath:BAAALAADCgcIBwABLAAECggIGAAJAKAlAA==.Tanktonk:BAAALAAECgIIAwAAAA==.Tarlune:BAAALAAECgMIBAAAAA==.Tarzhay:BAAALAADCgMIAwAAAA==.Tawnyae:BAAALAADCgYIBgAAAA==.',Te='Terrika:BAAALAAECgEIAQAAAA==.Tetshajeh:BAAALAADCggIEAAAAA==.Teyliana:BAAALAADCgcIBQAAAA==.',Th='Thillarick:BAAALAAECgIIAwAAAA==.Thoragord:BAAALAAECgEIAQAAAA==.Thoronin:BAAALAADCgQIBAAAAA==.Thromanor:BAAALAAECgIIAgAAAA==.',Ti='Tien:BAAALAAECgIIAgAAAA==.Tiramisú:BAAALAAECgUIBwAAAA==.Tiranmyashol:BAAALAAECgYIDQAAAA==.Titanz:BAAALAADCggIFQAAAA==.',To='Todessatz:BAAALAADCgMIAwABLAAECgYIDQABAAAAAA==.Tomoya:BAAALAAECgYIDAAAAA==.Tonken:BAAALAAECgEIAQAAAA==.Toothdk:BAAALAADCgcIEQAAAA==.',Tr='Trinky:BAAALAADCgcICwAAAA==.',Ty='Tychas:BAAALAADCggIAQAAAA==.Tyrandrea:BAAALAADCgQIBgAAAA==.Tytan:BAAALAADCgcIFQAAAA==.',['Tä']='Täterdötz:BAAALAADCgcIBwAAAA==.',Ud='Udari:BAAALAAECgIIAgAAAA==.Udarii:BAAALAAECgEIAQAAAA==.',Ul='Ultraform:BAAALAADCgYIBgAAAA==.',Um='Umàdbrah:BAAALAAECgUIBwAAAA==.',Un='Unbelievable:BAAALAAECgIIAwAAAA==.',Ur='Uriaa:BAAALAADCgcIDgAAAA==.',Va='Vaegon:BAAALAADCgcIEAAAAA==.Valcyrja:BAAALAAECgQIBAAAAA==.Vani:BAAALAADCgcIDgAAAA==.Varia:BAAALAAECgYICQAAAA==.Varianstorm:BAAALAADCgUIBQAAAA==.',Ve='Veefib:BAAALAAECgYIBgAAAA==.Velvettwitch:BAAALAADCgYICAAAAA==.Vexalia:BAAALAADCgcIBwABLAAECggIEQABAAAAAA==.Vexation:BAAALAADCgcICgAAAA==.',Vi='Vidreaux:BAAALAAECgIIAwAAAA==.Vieuphoria:BAAALAAECgIIAgAAAA==.',Vo='Voidbeary:BAAALAAECggIBAAAAA==.Vokedormi:BAAALAAECgMIAwAAAA==.',Vy='Vynesra:BAAALAADCgcIBwAAAA==.',Wa='Walleroot:BAAALAAECgUIBwAAAA==.',We='Wetnurse:BAAALAADCgIIAgAAAA==.',Wh='Whirz:BAAALAAECgYICQAAAA==.',Wo='Wolfpup:BAAALAAECggIAQABLAAECggICQABAAAAAA==.',Ww='Wwalle:BAAALAADCgQIBAABLAAECgUIBwABAAAAAA==.',Xe='Xetomantias:BAAALAAECgUICAAAAA==.',Xh='Xhaelath:BAAALAADCggICAAAAA==.',Xz='Xzavier:BAAALAADCgMIAwAAAA==.',Ya='Yasutora:BAAALAADCgYIBgAAAA==.',Yf='Yfelshammy:BAAALAADCgcIAwAAAA==.',Yl='Ylvanas:BAAALAAECgUICAAAAA==.',Yo='Yogiebear:BAABLAAECoEYAAILAAgITyULAQBTAwALAAgITyULAQBTAwAAAA==.',Yr='Yrsea:BAAALAADCgcIBwAAAA==.',Yu='Yuzuna:BAAALAAECgIIAwAAAA==.',Yv='Yvonnél:BAAALAADCgQIBAAAAA==.',Za='Zanebusby:BAAALAAECgUICAAAAA==.Zannahh:BAAALAADCggICAAAAA==.Zaraa:BAAALAAECgIIAgAAAA==.Zavenia:BAAALAADCgYICAAAAA==.',Ze='Zeroshaman:BAAALAADCgcICwAAAA==.',Zi='Ziljin:BAAALAADCgQIBAAAAA==.',Zo='Zonios:BAAALAAECgMIBgAAAA==.',Zz='Zzella:BAAALAAECgcIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end