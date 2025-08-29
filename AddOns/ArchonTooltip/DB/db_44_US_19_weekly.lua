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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Druid-Balance','DeathKnight-Frost',}; local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abractus:BAAALAADCgMIAwAAAA==.',Ac='Ackresetaz:BAAALAADCgcICAAAAA==.',Ad='Adriana:BAAALAAECgIIAgAAAA==.Adrianix:BAAALAADCgYIDAAAAA==.Adru:BAAALAAECgEIAQAAAA==.',Ae='Aeglos:BAAALAAECgcIEwAAAA==.Aentharion:BAAALAAECgIIAwAAAA==.',Ag='Agheera:BAAALAADCgcIEgAAAA==.',Ai='Aileen:BAAALAAECgUIBwAAAA==.',Al='Alahn:BAAALAADCggICwABLAADCggIDwABAAAAAA==.Alcotor:BAAALAADCgQIBAAAAA==.Alindri:BAAALAADCggICQAAAA==.Allexilock:BAAALAAECgMIBwAAAA==.Alorren:BAAALAAECgIIAgAAAA==.',Am='Amon:BAAALAADCgcICgAAAA==.Amynrar:BAAALAADCgUIBQAAAA==.',An='Anarorenna:BAAALAAECggICAAAAA==.Andiril:BAAALAADCgcIBwAAAA==.Anguis:BAAALAAECgEIAgAAAA==.Ansem:BAAALAADCgcICgAAAA==.',Ap='Aphantasia:BAAALAADCgIIAgAAAA==.Apiix:BAAALAAECgcIEAAAAA==.Apothegary:BAAALAADCggIEAAAAA==.',Aq='Aquagoat:BAAALAAECgYICQAAAA==.',Ar='Arcticsnow:BAAALAADCggIDwAAAA==.Arkose:BAAALAAECgMIAwAAAA==.Artanos:BAAALAAECgEIAgAAAA==.',As='Aschen:BAAALAADCgIIAgAAAA==.Ashlynne:BAAALAAECgMIBAAAAA==.Aspensong:BAAALAAECgIIAwAAAA==.Astoreth:BAAALAAECgQIBQAAAA==.Astracious:BAAALAADCgIIAgAAAA==.',At='Atax:BAAALAAECgIIAwAAAA==.Atlàs:BAAALAAECgIIAgAAAA==.',Av='Avestara:BAAALAAECgEIAQAAAA==.Avrice:BAAALAADCggIDwAAAA==.',Aw='Awakè:BAAALAADCgIIAgAAAA==.',Ay='Ayaku:BAAALAAECgIIAgAAAA==.',Az='Azelior:BAAALAAECgIIAwAAAA==.',Ba='Badconduct:BAAALAADCggIDgAAAA==.Badshot:BAAALAAECgYICgAAAA==.Balwun:BAAALAADCgUIBAAAAA==.Bariggs:BAAALAAECgYIDQAAAA==.',Bb='Bbaioff:BAAALAADCggICAABLAAECgYICQABAAAAAA==.',Be='Behomet:BAAALAADCggIDgAAAA==.Ben:BAAALAAECgYIDgAAAA==.Berestan:BAAALAADCgcIFQAAAA==.Beriadan:BAAALAAECgYICQAAAA==.Bevee:BAAALAAECgcIDwAAAA==.',Bl='Blackenedice:BAAALAADCgIIAgAAAA==.Blackrøse:BAAALAAECgMIAwAAAA==.Bleddwen:BAAALAAECgEIAgAAAQ==.Bloodbeerd:BAAALAAECgMIAwAAAA==.Blrsama:BAAALAADCgcICwAAAA==.',Bo='Bovines:BAAALAADCgYIDAAAAA==.Boüh:BAAALAAECgEIAQAAAA==.',Br='Brekht:BAAALAAECgEIAQAAAA==.',Bu='Burmeister:BAAALAAECgEIAQAAAA==.Burnadine:BAAALAAECgEIAgAAAA==.Burnswhnpee:BAAALAAECgIIAwAAAA==.',Ca='Caliie:BAAALAAECgIIAwAAAA==.Callektra:BAAALAADCggIEAAAAA==.Candle:BAAALAADCggIDQAAAA==.Captclamslam:BAAALAAECgEIAQAAAA==.Cassity:BAAALAADCgYIBgAAAA==.Cayamoon:BAAALAADCggICAAAAA==.Cayde:BAAALAADCggICQABLAAECgEIAQABAAAAAA==.',Ce='Celestina:BAAALAADCggICAAAAA==.',Ch='Chintakari:BAAALAAECgMIAwAAAA==.',Co='Confusious:BAAALAADCggIDwAAAA==.Coree:BAAALAAECgMIBwAAAA==.Cornflower:BAAALAADCggICgAAAA==.',Cr='Crazyhorse:BAAALAADCggICAAAAA==.Creamy:BAAALAAECgIIAgAAAA==.Crisolah:BAAALAADCggIDwAAAA==.Cryostatic:BAAALAADCgcIEgABLAADCggICAABAAAAAA==.',Cu='Cultel:BAAALAAECgcIEAAAAA==.',Cy='Cyendia:BAAALAAECgIIAgAAAA==.',Da='Daemondark:BAAALAADCgIIAgAAAA==.Dagapriest:BAAALAAECgMIAwAAAA==.Dakan:BAAALAADCgYIBwAAAA==.Daphcelyn:BAAALAADCgcIEQAAAA==.Dariusz:BAAALAAECgIIAgAAAA==.Darkalen:BAAALAAECgUIBwAAAA==.Darklodus:BAAALAADCggIDwAAAA==.Davìd:BAAALAADCggICAAAAA==.Davîd:BAAALAAECgMIAwAAAA==.',De='Deathb:BAAALAADCggIBQAAAA==.Deathjingle:BAAALAAECggIDQAAAA==.Decklyn:BAAALAAECgUIBwAAAA==.Deecayed:BAAALAADCggIDwAAAA==.Deecoy:BAAALAAECgIIAgAAAA==.Deemonic:BAAALAAECgIIAgAAAA==.Deetermined:BAAALAAECgYIDgAAAA==.Deeviant:BAAALAADCggIDwAAAA==.Denchy:BAAALAADCgcIEQAAAA==.Densie:BAAALAADCgEIAQAAAA==.Desetraz:BAAALAAECgYIDAAAAQ==.Deviistate:BAAALAAECgMIBQAAAA==.Deyndine:BAAALAADCgcICAAAAA==.Deélicious:BAAALAAECgMIAwAAAA==.',Di='Dicicastrado:BAAALAAECgQICAABLAADCgcIBwABAAAAAA==.',Do='Dorden:BAAALAAECgUICAAAAA==.Dorilax:BAAALAAECgQIBgAAAA==.Doublelife:BAAALAAECgYIDAAAAA==.',Dr='Draemora:BAAALAAECgEIAQAAAA==.Drewsham:BAAALAAECgMIAwAAAA==.Drogath:BAAALAAECgEIAQAAAA==.Drothmyr:BAAALAADCgcIDQAAAA==.Druntress:BAAALAAECgYIBgAAAA==.',Du='Duarraag:BAAALAADCgQIBQAAAA==.Duncan:BAAALAAECggICAAAAA==.Dunkible:BAAALAAECgEIAQAAAA==.',['Dê']='Dêcibel:BAAALAADCgUIBgAAAA==.',['Dë']='Dëërez:BAAALAAECgEIAQAAAA==.',El='Elayna:BAAALAAECgEIAgAAAA==.Elfname:BAAALAADCgEIAgAAAA==.Elishaunt:BAAALAADCgcIBwAAAA==.Elivan:BAAALAAECgEIAQAAAA==.Elleizah:BAAALAAECgUIBgAAAA==.',En='Envi:BAAALAAECgMIBAAAAA==.',Ep='Epoxous:BAAALAAECgIIAgAAAA==.',Er='Erixi:BAAALAAECgEIAgAAAA==.Erodoreal:BAAALAAECgEIAQAAAA==.Errya:BAAALAADCgEIAQAAAA==.Erudition:BAAALAADCgMIAwAAAA==.',Et='Ethérn:BAAALAADCgMIAwAAAA==.',Ev='Everchanging:BAAALAADCggIDwAAAA==.',Ex='Excelidin:BAAALAADCgUIBwAAAA==.',Ez='Ezikial:BAAALAADCgcICQAAAA==.',Fa='Falcdruiid:BAAALAAECgEIAQAAAA==.Falcwarrior:BAAALAADCgQIBAAAAA==.Falryus:BAAALAADCggICgAAAA==.Fayemoon:BAAALAADCggIDwAAAA==.',Fe='Felwit:BAAALAAECgIIAwAAAA==.Felwraith:BAAALAADCgIIAgABLAAECgIIAwABAAAAAA==.Fentanilo:BAAALAADCgYIBgAAAA==.',Fi='Fitzooth:BAAALAAECgMIBAAAAA==.',Fl='Flamos:BAAALAADCgcIDAAAAA==.Floofles:BAAALAADCggIDwAAAA==.Florabelle:BAAALAADCgcICgABLAADCggICgABAAAAAA==.',Fo='Forkarl:BAAALAAECgEIAQAAAA==.Foshomomo:BAAALAAECgIIAwAAAA==.Fozzle:BAAALAAECgUIBwAAAA==.',Fr='Francus:BAEALAADCgYIDAABLAAECggIFQACAAgkAA==.Freck:BAAALAADCgcIDgAAAA==.Frenndi:BAAALAADCgcIEAAAAA==.Frostbites:BAAALAAECgEIAQAAAA==.',Fy='Fynedge:BAAALAAECgIIAgAAAA==.Fynnyntyss:BAAALAAECgUICAAAAA==.Fyrè:BAAALAAECgUICAAAAA==.',Ga='Gaeila:BAAALAAECgIIAwAAAA==.Gafgarion:BAAALAAECggIBgAAAA==.',Ge='Gerlock:BAAALAAECgEIAQAAAA==.Getschwiftyy:BAAALAADCgUIBwAAAA==.',Gh='Ghandahlf:BAAALAAECgEIAQAAAA==.',Gi='Giulietta:BAAALAAECgEIAgAAAA==.',Gn='Gnazzadin:BAAALAADCggIDwAAAA==.',Go='Golmac:BAAALAAECgIIAwAAAA==.',Gr='Grimreaver:BAAALAADCgYIBgAAAA==.Grimwharf:BAAALAAECgEIAQAAAA==.Grumpus:BAAALAADCgcIDQAAAA==.Grunaelyn:BAAALAAECgMIAwAAAA==.',Ha='Haelynn:BAAALAAECgMIBwAAAA==.Harmonize:BAAALAAECgEIAQAAAA==.Haunt:BAAALAADCggICgAAAA==.Hawna:BAAALAAECgIIAgAAAA==.',Ho='Honordin:BAAALAAECgQIBwAAAA==.',Hu='Hucha:BAAALAADCgYIBwAAAA==.Hundren:BAAALAADCgYIBgAAAA==.Hundrood:BAAALAADCgMIAwAAAA==.',Hw='Hweilan:BAAALAADCgcIDgAAAA==.',Ia='Iamearl:BAAALAAECgEIAQAAAA==.',Ic='Icyhotness:BAAALAAECgMIAwAAAA==.',Il='Illador:BAAALAADCgQIAgAAAA==.',Im='Imthekey:BAAALAADCgMIAwAAAA==.',In='Inania:BAAALAAECgYIDAAAAA==.Inconell:BAAALAADCggIEAAAAA==.Invisibiitch:BAAALAAECgYIBgAAAA==.',Io='Iorolan:BAAALAAECgEIAQAAAA==.',Is='Ismira:BAAALAAECgMIBgAAAA==.',Iz='Izaer:BAAALAAECgMIBQAAAA==.',Ja='Jadestorm:BAAALAAECgMIAwAAAA==.Jahirah:BAAALAAECgMIAwABLAAECgMIAwABAAAAAA==.Jamesons:BAAALAADCgcIDQAAAA==.Janaian:BAAALAAECgQIBAAAAA==.Jarius:BAAALAAECgIIAwAAAA==.',Je='Jeez:BAAALAAECgYICQAAAA==.Jeri:BAABLAAECoEXAAIDAAgIiiPjAwArAwADAAgIiiPjAwArAwAAAA==.',Jo='Jonyy:BAAALAADCgcIBwAAAA==.Joona:BAAALAAECgUIBwAAAA==.Jorianna:BAAALAADCgcIBwAAAA==.Joru:BAACLAAFFIEKAAIEAAUIYx0PAADaAQAEAAUIYx0PAADaAQAsAAQKgRcAAgQACAjeJTcAAGwDAAQACAjeJTcAAGwDAAAA.',Ka='Kabir:BAAALAADCggIFwAAAA==.Kadria:BAAALAAECgEIAgAAAA==.Kailanii:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.Kaiyne:BAAALAAECgYIDgAAAA==.Kalaman:BAAALAAECgMIBAAAAA==.Kalian:BAAALAAECgIIAwAAAA==.Kallivar:BAAALAADCggIEQAAAA==.Kalry:BAAALAADCgcIBwAAAA==.Karalee:BAAALAADCgcIDQAAAA==.Karonis:BAAALAAECgMIAwAAAA==.Katieey:BAACLAAFFIEOAAIFAAYIGB8RAABOAgAFAAYIGB8RAABOAgAsAAQKgRgAAwUACAibIKsFALUCAAUACAibIKsFALUCAAYABQgNHQIgAKMBAAAA.Kayde:BAAALAAECgEIAQAAAA==.Kaye:BAAALAADCggIDgAAAA==.Kayil:BAAALAADCggIDgAAAA==.Kayl:BAAALAAECgcIEAAAAA==.',Ke='Kedalin:BAAALAADCgcIEAAAAA==.Kendalara:BAAALAADCggIDQAAAA==.Kennyloggy:BAACLAAFFIEFAAIHAAQIZBaXAABqAQAHAAQIZBaXAABqAQAsAAQKgRkAAgcACAh0JnAAAIYDAAcACAh0JnAAAIYDAAAA.Kenxts:BAAALAAECgYIBwAAAA==.Keravnyx:BAAALAAECggIAgAAAA==.Kerensky:BAAALAAECgQIBgAAAA==.Kevris:BAAALAAECgMIAwAAAA==.Keydan:BAAALAAECgEIAgAAAA==.',Kh='Khyn:BAAALAADCggIDgAAAA==.',Ki='Killmaim:BAAALAADCggICAAAAA==.',Kl='Klassy:BAAALAAECgcIEAAAAA==.',Ko='Koppi:BAAALAADCgUIBwAAAA==.Korehecate:BAAALAAECgEIAQAAAA==.Korru:BAAALAAECgMIBAAAAA==.Kotie:BAAALAAECgYICQAAAA==.',Kr='Krylee:BAAALAAECgMIBAAAAA==.',Ku='Kuiboom:BAAALAADCgMIAwAAAA==.',Ky='Kyoroog:BAAALAADCggICAAAAA==.Kyoshino:BAAALAAECgIIAgAAAA==.Kyouya:BAAALAAECgQIBgAAAA==.Kyrgune:BAAALAADCgYIBwAAAA==.',['Kà']='Kàhlan:BAAALAADCgYIBgAAAA==.',La='Lacerne:BAAALAADCgEIAQABLAAECgYICQABAAAAAA==.Laoftey:BAAALAAECgcIEAAAAA==.Laradea:BAAALAAECgIIAwAAAA==.',Le='Leam:BAAALAADCgYIBgAAAA==.Leewoo:BAAALAADCgcIBwAAAA==.Leglock:BAAALAAECgEIAQAAAA==.',Li='Lierenn:BAAALAAECgEIAQAAAA==.Lillshooter:BAAALAAECgMIAwAAAA==.Livicecia:BAAALAAECgQIBwAAAA==.',Lo='Loona:BAAALAADCgEIAQAAAA==.Lotlizard:BAAALAADCgcIDAAAAA==.',Lu='Lucariah:BAAALAADCgcIBwAAAA==.Lucielinna:BAAALAAECgEIAQAAAA==.Luckiiem:BAAALAAECgcIDgAAAA==.Luckyðate:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.Lumpiakween:BAAALAADCggIDwAAAA==.Lunarkin:BAAALAADCgYIBwAAAA==.Luoma:BAAALAADCggIDwAAAA==.Lurik:BAAALAAECgUIBwAAAA==.Luthane:BAAALAAECgEIAQAAAA==.',Ma='Magikar:BAAALAADCgcIBwAAAA==.Makishi:BAAALAAECgEIAQAAAA==.Malferious:BAAALAADCgcIDwAAAA==.Malfura:BAAALAADCggICgAAAA==.Malário:BAAALAADCgUIBQAAAA==.Mascdomtop:BAAALAAECgcIDQAAAA==.Massbringer:BAAALAADCgcICAABLAADCggIDgABAAAAAA==.Matalin:BAAALAADCggIDgAAAA==.Mazzarzul:BAAALAADCgIIAgABLAAECgMIBQABAAAAAA==.',Me='Meatbølls:BAAALAAECgIIAgAAAA==.Meebles:BAAALAAECgUICAAAAA==.Mekanism:BAAALAADCggIDgABLAAECgcIEAABAAAAAA==.Melasmus:BAAALAAECgIIAgAAAA==.Mes:BAAALAAECgQIBgAAAA==.',Mi='Micker:BAAALAAECgEIAQAAAA==.Micklaa:BAAALAAECgEIAQAAAA==.Millenium:BAAALAAECgQIBQAAAA==.Mingtai:BAAALAADCgYIBwAAAA==.Mizzakien:BAAALAAECgMIBAAAAA==.',Mo='Molgrano:BAAALAADCgcIBwAAAA==.Monell:BAAALAADCggIDwAAAA==.Moonsinde:BAAALAADCggICAAAAA==.Morgrem:BAAALAADCgYIBgAAAA==.Morwin:BAAALAAECgQIBgAAAA==.Mossum:BAAALAAECgUICQAAAA==.',Mu='Muncher:BAAALAADCggIDgAAAA==.',My='Mykellcat:BAAALAAECgEIAgAAAA==.',Na='Naeni:BAAALAAECgMIAwAAAA==.Nafaari:BAAALAAECgcIDgAAAA==.Narima:BAAALAADCggIDwAAAA==.Navirose:BAAALAADCgcIBwAAAA==.',Ne='Necromos:BAAALAADCggICAAAAA==.',Nh='Nhala:BAAALAADCggIDwAAAA==.',Ni='Nickspally:BAAALAAECgQIBgAAAA==.Nikodem:BAAALAAECgUIBQAAAA==.Nil:BAAALAAECgEIAgAAAA==.',No='Nore:BAAALAADCggIFwAAAA==.',Nu='Nullanar:BAAALAAECgIIAQAAAA==.',Ob='Oblivions:BAAALAAECgcIEAAAAA==.',Og='Ogion:BAAALAAECgUICAAAAA==.',On='Onewaystreet:BAAALAAECgQIBQAAAA==.',Or='Orckus:BAAALAADCgUIBwAAAA==.Oriann:BAAALAAECgQIBgAAAA==.',Oy='Oyaman:BAAALAADCgMIAwAAAA==.',Oz='Ozeroh:BAAALAADCgcIDgAAAA==.',Pa='Palimoon:BAAALAADCgcIBwAAAA==.Pandaburn:BAAALAAECgEIAQAAAA==.Paranne:BAAALAAECgUICAAAAA==.Patapouf:BAAALAAECgEIAQAAAA==.',Pe='Peanût:BAAALAAECgcIDgAAAA==.Pesante:BAAALAAECgQIBQAAAA==.',Ph='Philippy:BAAALAAECgMIBAAAAA==.Phyrr:BAAALAAECggICAAAAA==.',Pi='Pippá:BAAALAADCgcIBwAAAA==.',Po='Polonius:BAAALAADCggIEwAAAA==.Potato:BAAALAADCggICAAAAA==.',Py='Pythe:BAAALAAECgUICAAAAA==.',Qa='Qap:BAAALAAECgEIAgAAAA==.',Qu='Qualnorr:BAAALAADCgcIDQAAAA==.Quelletois:BAAALAADCgcIBwAAAA==.Quffles:BAAALAADCgcIBwAAAA==.Quixediah:BAAALAADCgIIAgAAAA==.Quixhea:BAAALAAECgIIAgAAAA==.',Ra='Rachiel:BAAALAADCggICAAAAA==.Radalas:BAAALAAECgEIAQAAAA==.Radreliris:BAAALAAECgIIAwAAAA==.Rainchêck:BAAALAADCggIDwAAAA==.Raineir:BAAALAADCgIIAgAAAA==.Ramcco:BAEALAAECgEIAQAAAA==.Ranelle:BAAALAAECgUICAAAAA==.Ravnyr:BAAALAAECgEIAQAAAA==.Razelik:BAAALAAECgMIAwAAAA==.',Re='Reedem:BAAALAAECgYICgAAAA==.Reen:BAAALAAECggIDwAAAA==.Regilock:BAAALAAECgcIDQAAAA==.Revín:BAAALAAECgUICAAAAA==.',Rh='Rhaenyraa:BAAALAAECgEIAQAAAA==.Rhallin:BAAALAADCgcICwAAAA==.Rhasalgul:BAAALAADCgcICwAAAA==.Rhegar:BAAALAADCgcIBwAAAA==.',Ri='Riparium:BAAALAAECgYIBgAAAA==.',Ro='Rolhen:BAAALAADCggICAAAAA==.Roquen:BAAALAAECgUICAAAAA==.Roquén:BAAALAADCgcIDgAAAA==.Rowain:BAAALAAECgIIAwAAAA==.Rozilan:BAAALAAECgUIBQAAAA==.',Ry='Ryanarri:BAAALAADCggIDgAAAA==.Rylacus:BAAALAAECgEIAgAAAA==.Rylii:BAAALAADCgUIBgAAAA==.',Sa='Salibaron:BAAALAADCgcICwAAAA==.Sarby:BAAALAADCgYIBgAAAA==.Sarlef:BAAALAAECgIIAgAAAA==.',Se='Sellidra:BAAALAAECgEIAQAAAA==.Seo:BAAALAAECgYIDwAAAA==.Seyana:BAAALAADCggIDwAAAA==.',Sh='Shaffer:BAAALAADCgYICAAAAA==.Shakensteak:BAAALAAECgUIBwAAAA==.Shellshocker:BAAALAAECgcIEAAAAA==.Sheyta:BAAALAAECgIIAgAAAA==.Shikï:BAAALAAECgYIDwAAAA==.Shockadelica:BAAALAADCgcIBAABLAADCggIDwABAAAAAA==.',Si='Sigesar:BAAALAAECgIIAwAAAA==.Sink:BAAALAADCgEIAQAAAA==.',Sk='Skyluna:BAAALAADCgcICwABLAAECgMIAwABAAAAAA==.Skywatcher:BAAALAAECgEIAQAAAA==.',Sn='Snicky:BAAALAADCgcIEQAAAA==.',So='Solare:BAAALAADCggICAAAAA==.',Sp='Spazfrazzle:BAAALAADCgYIBgABLAADCggIDwABAAAAAA==.Speeds:BAAALAAECgUIBQAAAA==.',Sq='Squeletor:BAAALAADCgcIBwAAAA==.',St='Steelpen:BAAALAADCgEIAQAAAA==.Stenston:BAAALAAECgMIAwAAAA==.Sterede:BAAALAADCgcIEAAAAA==.Stonehenge:BAAALAAECgEIAQAAAA==.Stormagetton:BAAALAADCgEIAQAAAA==.Stormwolves:BAAALAADCgQIBAAAAA==.',Su='Sumana:BAAALAADCgMIAwAAAA==.',Sv='Sverdrup:BAAALAAECgEIAgABLAAECgYIBgABAAAAAA==.',Sy='Syel:BAABLAAECoERAAIIAAcIdSQUCwDKAgAIAAcIdSQUCwDKAgAAAA==.Sylphrená:BAAALAADCggICAAAAA==.Sylvanase:BAAALAAECgcIDwAAAA==.',Ta='Tallari:BAAALAADCggIDgABLAAECgcIEAABAAAAAA==.Tallic:BAAALAAECgcIEAAAAA==.Tamili:BAAALAAECgEIAQAAAA==.Tarsi:BAAALAADCggIDwAAAA==.Tashoonne:BAAALAADCgMIAwAAAA==.',Te='Tearinurside:BAAALAADCgMIAwAAAA==.Techmetal:BAAALAADCggIDwAAAA==.Telidrel:BAAALAADCgIIAgAAAA==.',Th='Thaddeaus:BAAALAAECgQIBgAAAA==.Thaddeus:BAAALAAECgIIAwAAAA==.Thebeefyone:BAAALAAECgMIBwAAAA==.Thoriant:BAEBLAAECoEVAAICAAgICCS7BQAlAwACAAgICCS7BQAlAwAAAA==.Thumpette:BAAALAAECgMIBQAAAA==.Thurtus:BAAALAAECgQIBgABLAAECgUICAABAAAAAA==.Thuviel:BAAALAADCgcICQAAAA==.',Ti='Tizaria:BAAALAAECgEIAQAAAA==.',To='Tominaetor:BAAALAAECgMIBQAAAA==.Tosoto:BAAALAAECgUICAAAAA==.',Ts='Tsukuyomï:BAAALAAECgMIAwAAAA==.Tsuky:BAAALAADCggIDgAAAA==.',Ty='Tym:BAAALAAECgEIAQAAAA==.Tyrael:BAAALAAECgEIAQAAAA==.Tyreanna:BAAALAADCgUIBQAAAA==.Tyrioz:BAAALAAECgMIAwAAAA==.',Ul='Ultratin:BAAALAAECgMIAwAAAA==.',Ut='Utadia:BAAALAADCgcIBwABLAAECgcIDwABAAAAAA==.',Va='Valius:BAAALAAECgIIAgAAAA==.Vallarium:BAAALAADCggICQAAAA==.Valornor:BAAALAAECgIIAwAAAA==.Vanderwat:BAAALAAECgEIAQAAAA==.Vandill:BAAALAAECgMIBQAAAA==.Vandél:BAAALAAECgUICAAAAA==.',Ve='Veasnacool:BAAALAAECgMIAwAAAA==.Velaryssa:BAAALAAECgQIBQABLAAECgMIBwABAAAAAA==.',Vi='Victorn:BAAALAADCggIEgAAAA==.',Vo='Voden:BAAALAADCgcIDgAAAA==.Voidwarrior:BAAALAADCgUIBgAAAA==.Volrun:BAAALAADCgUICAAAAA==.Vontote:BAAALAAECgIIAgAAAA==.',Wa='Wandorf:BAEALAAECgIIAwAAAA==.Warwolfe:BAAALAAECgYIDQAAAA==.',Wi='Willshammy:BAAALAAECgUIBQAAAA==.',Wo='Wolferunner:BAAALAAECgEIAQAAAA==.',Wr='Wratholy:BAAALAAECgMIAwAAAA==.',['Wí']='Wíllöw:BAAALAAECgIIAgAAAA==.',Xa='Xaldora:BAAALAADCgYIBgAAAA==.Xandaius:BAAALAADCgYICAABLAAECgUICAABAAAAAA==.Xandrake:BAAALAAECgcIEAABLAAECggIEgABAAAAAA==.',Xd='Xdxvuu:BAAALAADCggIFQAAAA==.',Xe='Xerimok:BAAALAAECgEIAgAAAA==.',Xi='Xinya:BAAALAADCgYICwAAAA==.Xipa:BAAALAADCgYIBgABLAAECgcIEAABAAAAAA==.',Xs='Xsavier:BAAALAAECgMIAwAAAA==.Xshando:BAAALAAECgIIAwAAAA==.',Ya='Yamato:BAAALAAECgUICAAAAA==.',Ye='Yesmín:BAAALAADCgcIBwAAAA==.',Yh='Yhall:BAAALAADCggIEAAAAA==.',Yn='Yn:BAAALAADCgEIAQAAAA==.',Yo='Youwas:BAAALAAECgQIBgAAAA==.',Yu='Yukmouf:BAAALAAECgQIBQAAAA==.',Za='Zacharaius:BAAALAADCggICAAAAA==.Zakaris:BAAALAADCgYIBgAAAA==.Zarael:BAAALAAECgIIAgABLAAECgYIDAABAAAAAQ==.Zarrov:BAAALAADCggIDgAAAA==.Zarrove:BAAALAAECgcIEAAAAA==.',Ze='Zedael:BAAALAAECgMIAwAAAA==.Zefara:BAAALAAECgYICQAAAA==.Zerref:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Zh='Zhöe:BAAALAAECgMIBQAAAA==.',Zo='Zoldor:BAAALAAECgEIAQAAAA==.Zoobooks:BAAALAADCggIDQAAAA==.',Zu='Zuggeraut:BAAALAADCgEIAQAAAA==.Zurasai:BAAALAADCgcIBwAAAA==.',Zy='Zycorr:BAAALAADCggICwAAAA==.Zyheal:BAAALAAECgcICgAAAA==.Zymor:BAAALAADCgUICAAAAA==.Zytrex:BAAALAADCgcIDgAAAA==.',['Äm']='Ämaterasu:BAAALAADCggIDgABLAAECgMIAwABAAAAAA==.',['Ða']='Ðaniel:BAAALAAECgcIDwAAAA==.',['Ñÿ']='Ñÿx:BAAALAAECgEIAQAAAA==.',['ßl']='ßlueshield:BAAALAADCggIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end