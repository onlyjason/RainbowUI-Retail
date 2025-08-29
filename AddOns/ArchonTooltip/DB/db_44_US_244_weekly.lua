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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Druid-Restoration','Druid-Balance','Rogue-Subtlety','Rogue-Assassination',}; local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abracadaver:BAAALAADCgcICgAAAA==.Abÿss:BAAALAAECgEIAQAAAA==.',Ad='Adachï:BAAALAADCgMIAwABLAAECgYICAABAAAAAA==.Adolinn:BAAALAADCgQIBAAAAA==.',Ae='Aedar:BAAALAAECgYICwAAAA==.Aeturnas:BAAALAAECgUICgAAAA==.',Ag='Aggregate:BAAALAADCggIDwAAAA==.Aggros:BAAALAADCggIDgAAAA==.',Al='Alanima:BAAALAAECgEIAQAAAA==.Alanssra:BAAALAADCggIDQAAAA==.Aldry:BAAALAADCgcIBwAAAA==.Alinthe:BAAALAAECgIIAgAAAA==.Allypally:BAAALAAECgEIAQAAAA==.Aloriz:BAAALAAECgQIAwAAAA==.Alros:BAAALAAECgMIBgAAAA==.Alvaah:BAAALAADCgMIAwAAAA==.',Am='Ambrek:BAAALAADCgMIAwAAAA==.Amorianthos:BAAALAADCgYIBgAAAA==.',An='Angiosarcoma:BAAALAAECgIIAgAAAA==.Anguskhän:BAAALAAECgEIAQAAAA==.Antäres:BAAALAADCgQIBAABLAAECgYICAABAAAAAA==.',Ar='Arctica:BAAALAADCgQIBwAAAA==.Arkades:BAAALAAECgQIBAAAAA==.Arram:BAAALAADCgYIBgAAAA==.',Au='Auriell:BAAALAAECgMIAwAAAA==.',Av='Averynicole:BAAALAADCggIDwAAAA==.',Aw='Awasjr:BAAALAAECgUICAAAAA==.',Az='Azmodon:BAAALAAECgIIAwAAAA==.',Ba='Balerions:BAAALAAECgUIBQAAAA==.Barbedweihr:BAAALAADCgEIAQAAAA==.Bark:BAAALAAECgcICAAAAA==.',Be='Beanvoker:BAAALAAECgYIBwAAAA==.Bearhug:BAAALAAECgEIAQAAAA==.Beasty:BAAALAAECgIIAgAAAA==.Beefjerky:BAAALAAECgMIAwAAAA==.Belardor:BAAALAAECggICAAAAA==.Beliara:BAAALAADCggIDwAAAA==.Belladonia:BAAALAADCggICAAAAA==.Berrymage:BAAALAADCgUIBQAAAA==.Beë:BAAALAAECgUIBwAAAA==.',Bi='Bicboi:BAAALAAECgYIBwAAAA==.Bionarra:BAAALAAECgYIDgAAAA==.Bip:BAAALAADCgEIAQAAAA==.Bishopwr:BAAALAAECgQIBgAAAA==.',Bo='Boethiah:BAAALAAECgcIBwAAAA==.',Br='Brakug:BAAALAAECgYICAAAAA==.Brecc:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.Breck:BAAALAADCgIIAgABLAADCgYIBgABAAAAAA==.Brekk:BAAALAAECgYIBgAAAA==.Brem:BAAALAAECgYICQAAAA==.Bretagnesse:BAAALAAECgMIAwAAAA==.Briara:BAAALAAECgEIAQAAAA==.Bristlelich:BAAALAADCggIDwAAAA==.Broníx:BAAALAADCgcIDQAAAA==.',Bu='Burritobolts:BAAALAADCgYIBQAAAA==.',By='Bynx:BAAALAADCgIIAgABLAAECgUIBQABAAAAAA==.',['Bè']='Bèrtim:BAAALAADCgUIBQAAAA==.',Ca='Candisc:BAAALAADCgQIBAAAAA==.Canyouzapit:BAAALAAECgIIAgAAAA==.Carartha:BAAALAAECgIIBAAAAA==.Carnitine:BAAALAAECgMIAwAAAA==.Carrots:BAAALAAECgIIAgAAAA==.Cartman:BAAALAAECgYIBgABLAAECgcIDgABAAAAAA==.Cashmachine:BAAALAAECgUICQAAAA==.Catfight:BAAALAAECgIIAgAAAA==.',Ch='Cheesecake:BAAALAAECgIIAgAAAA==.Choks:BAAALAAECgIIAgAAAA==.Chéfboyrlee:BAAALAAECgMICgAAAA==.',Ci='Cindiyoohoo:BAAALAAECgIIAgAAAA==.',Co='Colbru:BAAALAADCgEIAQABLAAECgMIBgABAAAAAA==.Comandante:BAAALAAECgMIAwAAAA==.Cownado:BAAALAAECgIIAgAAAA==.Coyotedruid:BAAALAADCggIDwAAAA==.',Cy='Cynleel:BAAALAADCggIDwAAAA==.',Da='Daimon:BAAALAADCggICAAAAA==.Dallyp:BAAALAADCggIDAAAAA==.Dalmarr:BAAALAAECgEIAQAAAA==.Dandistyle:BAAALAAECgcIDAAAAA==.',De='Deeviant:BAAALAADCgIIAgAAAA==.Defend:BAAALAAECgcIDgAAAA==.Delragedh:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Delrager:BAAALAAECgIIAgAAAA==.Demónícz:BAAALAADCgcIBwAAAA==.',Di='Dicén:BAAALAAECgEIAQAAAA==.Diosa:BAAALAADCgIIAwAAAA==.Divix:BAAALAAECgUICQAAAA==.',Dj='Djderpysoaky:BAAALAADCgQIBAAAAA==.Djehrtey:BAAALAAECgEIAQAAAA==.Djhunter:BAAALAAECgQIBAAAAA==.Djin:BAAALAADCggIDwABLAAECgEIAgABAAAAAA==.Djinni:BAAALAAECgEIAgAAAA==.',Do='Doodle:BAAALAADCgYIBgAAAA==.',Dr='Dracnahr:BAAALAAECgUICAAAAA==.Dragunn:BAAALAAECgYIBgAAAA==.Drakula:BAAALAADCgQIBAAAAA==.Drassdimples:BAAALAADCgcIBwAAAA==.Draul:BAAALAAECgUICAAAAA==.Dreadshammy:BAAALAADCggICAAAAA==.Drenleah:BAAALAAECgUICQAAAA==.Drifabell:BAAALAAECgYIBgAAAA==.Dromokafrapp:BAAALAAECgYICAAAAA==.Drunkwinry:BAAALAAECgUICAAAAA==.Dryian:BAAALAADCgIIAwAAAA==.',Du='Duarcan:BAAALAADCggIFAAAAA==.Dumblegear:BAAALAAECgMIBgAAAA==.',Dy='Dyadin:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Dysdayne:BAAALAADCggIEAAAAA==.',['Dë']='Dëathx:BAAALAAECgIIAgAAAA==.',Ec='Ecclesia:BAAALAADCgcICwAAAA==.',Ei='Eihr:BAAALAADCgUIBwAAAA==.Eihria:BAAALAAECgcIEAAAAA==.',Ek='Ekatrina:BAAALAAECgYIBwAAAA==.',El='Elara:BAAALAAECggICAAAAA==.Ellariia:BAAALAAECgYIDwAAAA==.Ellemystic:BAAALAADCgcICgAAAA==.',Em='Emeralda:BAAALAADCggIDwAAAA==.Emerelda:BAAALAADCgMIAwAAAA==.Emokilla:BAAALAADCggICQAAAA==.',En='Engalí:BAAALAADCgIIAwAAAA==.',Es='Esha:BAAALAAECgYIBwAAAA==.',Ez='Ezekial:BAAALAAECgQIBgAAAA==.',Fa='Faubito:BAAALAAECgIIAgAAAA==.',Fe='Fearlesfreep:BAAALAAECgUICQAAAA==.Fearsona:BAAALAADCggIDQAAAA==.Fedan:BAAALAAECggICAAAAA==.Felfüry:BAAALAAECgUIBQAAAA==.Felkroz:BAAALAAECgYICwAAAA==.Fenixshaw:BAAALAADCggIFwAAAA==.Feyd:BAAALAAECgIIAgAAAA==.',Fi='Finella:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Fireandice:BAAALAADCgMIAgABLAAECgcIGAACAAQmAA==.',Fl='Fleahotel:BAAALAAECgIIAgAAAA==.Fluffy:BAAALAADCgcIBwAAAA==.',Fo='Fogage:BAAALAAECgIIAgAAAA==.Fogdemon:BAAALAAECgYIDAAAAA==.',Fr='Freinkenbaby:BAAALAADCgMIAwAAAA==.Fröstmöurne:BAAALAADCggIDwAAAA==.',Fu='Furbes:BAAALAADCgcIBwAAAA==.Furts:BAAALAADCgMIAwAAAA==.Futuo:BAAALAADCgcICgAAAA==.',Ga='Garrex:BAABLAAECoEYAAICAAcIBCZqCQDJAgACAAcIBCZqCQDJAgAAAA==.',Ge='Geret:BAAALAADCgcIDgAAAA==.Getmerkd:BAAALAADCgEIAQAAAA==.Gezabelle:BAAALAADCgcIBwAAAA==.',Gl='Glitchy:BAAALAAECgYICAAAAA==.',Gn='Gnomage:BAAALAADCggICAAAAA==.',Go='Goingtogetu:BAAALAAECgYIBgAAAA==.Goldshots:BAAALAADCggIDQAAAA==.Goldsplash:BAAALAAECgUICAAAAA==.Gorefiend:BAAALAAECgYIBwAAAA==.',Gr='Greatthomas:BAAALAADCggICAAAAA==.Greeley:BAAALAAECgIIAgAAAA==.Gregdapro:BAAALAAECgQIBQABLAAECgUICAABAAAAAA==.Gregnstone:BAAALAAECgUICAAAAA==.',Gu='Guacamole:BAAALAADCggICAAAAA==.Guderian:BAAALAAECgIIAgAAAA==.Gunnhunter:BAAALAAECgMIAwABLAAFFAEIAQABAAAAAQ==.Gunnyal:BAAALAAECgIIAgAAAA==.',Ha='Hagunn:BAAALAAFFAEIAQAAAQ==.Hagunnagain:BAAALAAECgYIBwABLAAFFAEIAQABAAAAAQ==.Hazel:BAAALAADCgYIBgAAAA==.',He='Heatfrezze:BAAALAAECgYICQAAAA==.',Ho='Howlinplague:BAAALAAECgQIBQAAAA==.',Hu='Hulkhogan:BAAALAAECgMIBgAAAA==.',Hy='Hykoo:BAAALAAECgYIBwAAAA==.',Ig='Igohego:BAAALAAECgMIBgAAAA==.',In='Incindia:BAAALAAECgIIAgAAAA==.',Ir='Ironhidez:BAAALAAECgUICAAAAA==.',Is='Ismellgood:BAAALAADCgIIAgAAAA==.',It='Itsyaboidy:BAAALAAECgMIAwAAAA==.',Ja='Jarzhuntz:BAAALAAECgIIAgAAAA==.Jasmini:BAAALAADCggIDwAAAA==.',Je='Jezter:BAAALAADCgYIBgAAAA==.',Jh='Jharlin:BAAALAAECgQIBwAAAA==.',Jo='Joehex:BAAALAAECgUICAAAAA==.Jolee:BAAALAADCggIDwAAAA==.',Ju='Juankaeltass:BAAALAADCgcICAAAAA==.Juankaeltha:BAAALAADCgcIBwAAAA==.Juankaelthas:BAAALAADCgYIBgAAAA==.Jungiann:BAAALAADCgUIBQAAAA==.Juánkaeltas:BAAALAADCgcIDAAAAA==.',['Já']='Jáybe:BAAALAAECgcIDQAAAA==.',Ka='Kaeleesh:BAAALAAECgMIBQAAAA==.Kahekili:BAAALAAECgIIAgAAAA==.Kaidou:BAAALAAECgQIBQAAAA==.Kaleesh:BAAALAAECgYIDAAAAA==.Kananga:BAAALAAECgIIAgAAAA==.Kanus:BAAALAADCggICAAAAA==.Karavira:BAAALAADCgcIDgAAAA==.Kaybar:BAAALAAECgIIAgAAAA==.Kazeem:BAAALAAECgMIAwAAAA==.Kaziu:BAAALAAECggICAAAAA==.',Ke='Kelindina:BAAALAAECgcIDQAAAA==.Kelindinas:BAAALAAECgIIBAAAAA==.Kelindis:BAAALAADCggIDAABLAAECgcIDQABAAAAAA==.Keoeu:BAAALAAECgMIBgAAAA==.Kerah:BAAALAAECgMIAwAAAA==.',Kh='Khaliden:BAAALAADCgUIBQAAAA==.Khalli:BAAALAADCgMIAwAAAA==.',Ki='Kiermaxim:BAAALAAECgQICAAAAA==.Kindred:BAAALAADCgMIAwAAAA==.Kiriku:BAAALAAECgYICQAAAA==.',Ko='Kotok:BAAALAAECgIIAgAAAA==.',Kr='Kroon:BAAALAADCggICQAAAA==.',Ky='Kyrit:BAAALAADCgIIAQAAAA==.',['Kø']='Køraei:BAAALAAECgIIAgAAAA==.',La='Latios:BAAALAADCgYIBgAAAA==.',Ld='Ldyelphaba:BAAALAAECgMIBQAAAA==.',Le='Letummilitis:BAAALAADCgcICAAAAA==.Levin:BAAALAAECgYIDwAAAA==.',Ll='Llght:BAAALAAECgYIDAAAAA==.',Lo='Logankord:BAAALAAECgUICAAAAA==.Lokeirah:BAAALAADCgcIBwAAAA==.Lono:BAAALAAECgUICAAAAA==.Loonnah:BAAALAADCgcICgAAAA==.Lorath:BAAALAAECgMIAwAAAA==.',Lu='Lucory:BAAALAADCgEIAQAAAA==.Lucyfurr:BAAALAADCgIIAQAAAA==.',Ly='Lyara:BAAALAAECggIDwAAAA==.Lynngunn:BAAALAAECgYIBwAAAA==.Lythos:BAAALAAECgUIBgAAAA==.',Ma='Machomans:BAAALAAECgMIBgAAAA==.Magicmeat:BAAALAADCgMIAwAAAA==.Malifae:BAAALAAECgUICAAAAA==.Manoroth:BAAALAAECgYIBgAAAA==.Mansa:BAAALAAECgUICAAAAA==.Mastamojo:BAAALAAECgQIBgAAAA==.Matri:BAAALAAECgEIAQAAAA==.Maylae:BAAALAAECgEIAQAAAA==.',Mc='Mcmurphy:BAAALAADCgMIAwAAAA==.Mctanky:BAAALAAECgYIBwAAAA==.',Me='Meissen:BAAALAAECgEIAQAAAA==.Melendaren:BAAALAADCgcICgAAAA==.Meltara:BAAALAADCgMIAwAAAA==.Meow:BAAALAAECgcIDAAAAA==.Mercei:BAAALAAECgMIBgAAAA==.Mercifulfate:BAAALAADCgEIAQAAAA==.Messìah:BAAALAADCggIDgAAAA==.Meãny:BAABLAAECoEVAAMCAAgI1SWLBgD6AgACAAcIMCaLBgD6AgADAAgI6yLNBADqAgAAAA==.',Mh='Mhozarr:BAAALAADCgcIBwAAAA==.',Mi='Miaelva:BAAALAADCgEIAQAAAA==.Miniav:BAAALAADCgcICgAAAA==.',Mj='Mjollnir:BAAALAADCgYIBgAAAA==.',Ml='Mladjo:BAAALAAECgYICwAAAA==.',Mo='Mogulous:BAAALAAECgMIAwAAAA==.Moneie:BAAALAADCgYIBgAAAA==.Monkeyballs:BAAALAADCggIDwAAAA==.Moog:BAAALAADCgcICwAAAA==.Mozaic:BAAALAAECgUICQAAAA==.',Mu='Mugrüíth:BAAALAADCgcICgAAAA==.Muur:BAAALAADCgcIBAAAAA==.',My='Myselia:BAAALAAECgMIAwAAAA==.Mysterius:BAAALAAECgUICQAAAA==.',Na='Nad:BAAALAADCgcIDAAAAA==.Naek:BAAALAADCgcICgAAAA==.',Ne='Nekrasami:BAAALAAECgUIBwAAAA==.',Ni='Nikoichi:BAAALAADCgcICAAAAA==.Nilyaf:BAABLAAECoEUAAIEAAcI4Bf9GwAdAgAEAAcI4Bf9GwAdAgAAAA==.Nimrods:BAAALAADCgIIAgAAAA==.',Nu='Numb:BAAALAADCgMIAwAAAA==.',On='Onetwocowpow:BAAALAAECgYICAAAAA==.Onostoolan:BAAALAAECgIIAgAAAA==.',Oo='Ooshiny:BAAALAADCgYIBgAAAA==.',Or='Orclard:BAAALAAECgEIAQABLAAECgYICwABAAAAAA==.Ordanith:BAAALAAECgcIDAAAAA==.Orionn:BAABLAAECoEZAAICAAgIbSFSBgD+AgACAAgIbSFSBgD+AgAAAA==.',Os='Osø:BAAALAADCggIDgAAAA==.',Ov='Oven:BAAALAAECgUIBQAAAA==.',Ow='Owoh:BAAALAADCgQIBAAAAA==.',Pa='Palilard:BAAALAAECgYICwAAAA==.',Pe='Peacebreaker:BAAALAADCgUIBQAAAA==.',Ph='Phreakshow:BAAALAADCgUIBQAAAA==.',Pi='Piratepally:BAAALAADCgMIAwAAAA==.',Pr='Prettyheels:BAAALAAECgEIAQAAAA==.Protus:BAAALAADCgcIBwAAAA==.',Pu='Puddermeow:BAAALAADCggICAAAAA==.',['Pï']='Pïnkbäbybëef:BAAALAADCggICAAAAA==.',Ra='Raelone:BAAALAAECgIIBAAAAA==.Rageofmommy:BAAALAADCgUIBQAAAA==.Raknslash:BAAALAAECgYIBgAAAA==.Rameumptom:BAAALAADCgEIAQAAAA==.Rangérz:BAAALAAECgYIDgAAAA==.Rasa:BAAALAAECgQIBwAAAA==.',Re='Reo:BAACLAAFFIEFAAIFAAMIXRIjAgD4AAAFAAMIXRIjAgD4AAAsAAQKgRYAAwUACAj2IPADAMsCAAUACAj2IPADAMsCAAYAAQgOG1tEAE0AAAAA.Restore:BAAALAAECgMIAwAAAA==.Reàper:BAAALAADCgEIAQAAAA==.',Rh='Rhamnousia:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.Rhielle:BAAALAAECgYIDAAAAA==.',Ri='Rinche:BAAALAAECgYICAAAAA==.Rine:BAAALAADCgYICgAAAA==.',Ro='Rolland:BAAALAADCggICAAAAA==.',Ru='Ruikmas:BAAALAAECgIIBAAAAA==.Ruytoo:BAAALAADCggIDAAAAA==.',['Rö']='Röse:BAAALAADCggIBwAAAA==.',['Rý']='Rýegar:BAAALAADCgcIBwAAAA==.',Sa='Sadrobot:BAAALAADCgUIBgABLAAECgcIDQABAAAAAA==.Safety:BAAALAAECgMIAwAAAA==.Sahbe:BAAALAAECgUICQAAAA==.Sammael:BAAALAAECgIIAgAAAA==.Samoajoe:BAAALAAECgEIAQAAAA==.Samovar:BAAALAAECgMIBwAAAA==.Sandrisa:BAAALAADCgYIBgAAAA==.Sandwiches:BAAALAAECgMIBwAAAA==.Sarraloesh:BAAALAADCgYIBgAAAA==.',Sc='Scalebagz:BAAALAADCgcIBwAAAA==.Schism:BAAALAAECgYIBwAAAA==.Scythren:BAAALAADCgYIBgAAAA==.',Se='Sentren:BAAALAADCgcICQAAAA==.Seo:BAAALAADCgMIAwAAAA==.Setresh:BAAALAAECgcICwAAAA==.',Sh='Shadowexarch:BAAALAAECgMIAwAAAA==.Shadöwsöng:BAAALAADCggIDgAAAA==.Shamalan:BAAALAAECgIIAgAAAA==.Shamwowhex:BAAALAAECgMIAwAAAA==.Sharatira:BAAALAADCgcICgAAAA==.Shawarma:BAAALAAECgYICgAAAA==.Shinnobi:BAAALAADCggICAAAAA==.Shirui:BAAALAAECgYIDAAAAA==.Shivyn:BAAALAAECgMIAwAAAA==.Shocknyall:BAAALAAECgEIAQAAAA==.Shockyoubad:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.Shoota:BAAALAAECgYICAAAAA==.Shosho:BAAALAAECgYIDgAAAA==.Shulin:BAAALAAECgEIAQAAAA==.',Si='Siegnos:BAAALAADCggIDwAAAA==.Silvershine:BAAALAAECgEIAgAAAA==.Silverwolf:BAAALAADCgEIAQAAAA==.',Sl='Slayerjay:BAAALAADCgUIBQAAAA==.',Sm='Smashdiggity:BAAALAAECgYIBwAAAA==.Smoothvelvet:BAAALAAECggICQAAAA==.',Sp='Spinach:BAAALAADCgIIAgAAAA==.Spookasem:BAAALAADCgUIBgAAAA==.Sprinkle:BAAALAAECgEIAQAAAA==.',Ss='Ssraeshza:BAAALAAECgMIAwAAAA==.',St='Staretra:BAAALAAECgYICAAAAA==.Sterarcher:BAAALAADCgcIDgAAAA==.Stezdashaman:BAAALAADCgcICgAAAA==.Stfholy:BAAALAAECgMIBwAAAA==.Stockade:BAAALAAECgIIAgAAAA==.Stormbrínger:BAAALAAECgIIAgAAAA==.',Su='Supernovda:BAAALAADCgUIBQAAAA==.',['Sè']='Sèan:BAAALAAECgYIBwAAAA==.',['Sì']='Sìlvertìger:BAAALAAECgEIAgAAAA==.',['Sö']='Sörceress:BAAALAADCggICwAAAA==.',Ta='Taadra:BAAALAAECgUICQAAAA==.Talfuki:BAAALAAECgEIAQAAAA==.Talona:BAACLAAFFIEFAAMHAAMIyxucAAAQAQAHAAMI9hqcAAAQAQAIAAIIFRuVBAC6AAAsAAQKgR8AAwcACAjOIV8BAN8CAAgACAgzIfQEAPACAAcACAhNH18BAN8CAAAA.Tan:BAAALAADCgUIBgAAAA==.Tanjent:BAAALAAECgEIAQAAAA==.Tatsumå:BAAALAAECgEIAQABLAAECgIIAwABAAAAAA==.Tavis:BAAALAADCgcIBwAAAA==.Tavvi:BAAALAAECgYICQAAAA==.',Te='Teachmane:BAAALAAECgUIBwAAAA==.Terp:BAAALAAECgMIAwAAAA==.Terrix:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.',Th='Thalrissa:BAAALAAECgIIAgAAAA==.Thasmortan:BAAALAADCgUICQAAAA==.Thuglifé:BAAALAAECgMIAgAAAA==.',Ti='Tidemaiden:BAAALAAECgMIBAAAAA==.Tipsymancer:BAAALAAECgYICAAAAA==.',To='Totemdaddy:BAAALAAECgMIBQAAAA==.',Tr='Treesus:BAAALAAECgIIAgAAAA==.Triane:BAAALAAECgYIBwAAAA==.Trinket:BAAALAADCggICAABLAAECgUIBQABAAAAAA==.Trollroom:BAAALAAECgIIAgAAAA==.',Ts='Tsu:BAAALAAECgEIAQAAAA==.',Tu='Tundéth:BAAALAADCgYIBgABLAAECgMIBgABAAAAAA==.',Ty='Tyso:BAAALAAECgcIEQAAAA==.',Uw='Uwuowosenpai:BAAALAAECgEIAQAAAA==.',Va='Vancro:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Variable:BAAALAAECgUIBgAAAA==.Vashdin:BAAALAAECgIIAgAAAA==.',Ve='Velashis:BAAALAAECgMIBAAAAA==.Velmoon:BAAALAADCgYIBgAAAA==.Venenum:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Verdiance:BAAALAADCgYICQAAAA==.Verexar:BAAALAADCggIEAAAAA==.Veringetorix:BAAALAADCggIDgABLAAECgMIAwABAAAAAA==.Vermin:BAAALAAECgUIBgAAAA==.Vett:BAAALAAECgIIAgAAAA==.',Vi='Vicvega:BAAALAAECgMIAwABLAAECgUIBQABAAAAAA==.',Vo='Void:BAAALAAECgEIAQAAAA==.Volgatha:BAAALAAECgMIBgAAAA==.',Vr='Vresim:BAAALAAECgYIDgAAAA==.',Vu='Vugnus:BAAALAAECgIIAgAAAA==.',['Vå']='Vånkro:BAAALAAECgMIAwAAAA==.',Wa='Wartorn:BAAALAADCgMIAwABLAAECgYIBgABAAAAAA==.Wayofthesnix:BAAALAAECgEIAQAAAA==.',We='Westrin:BAAALAAECgYICAAAAA==.',Wh='Whype:BAAALAAECgMIBAAAAA==.',Wi='Wiegraf:BAAALAAECgYICAAAAA==.Wiffen:BAAALAAECgUICQAAAA==.',Wo='Worgendork:BAAALAADCggICAAAAA==.',Wy='Wyndeline:BAAALAADCggIFgAAAA==.',['Wà']='Wàr:BAAALAADCgYIBgAAAA==.',Xa='Xarrie:BAAALAADCgYICQAAAA==.',Ya='Yaecob:BAAALAAECgQIBQAAAA==.',Ye='Yeamon:BAAALAADCggICAAAAA==.',Yg='Yggrasdil:BAAALAADCggICwABLAAECgYICAABAAAAAA==.',Ym='Ymir:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.',Za='Zaft:BAAALAAECgYICAAAAA==.Zaha:BAAALAAECgYIDQAAAA==.Zappsz:BAAALAADCggIFQAAAA==.Zars:BAAALAADCgYIDQAAAA==.Zath:BAAALAAECgYIDwAAAA==.',Ze='Zem:BAAALAADCgcIBwAAAA==.Zennish:BAAALAADCgcIBwAAAA==.Zephyr:BAABLAAECoEUAAIGAAYIaSF8DwAxAgAGAAYIaSF8DwAxAgAAAA==.Zeusdh:BAAALAADCgcIBwAAAA==.',Zi='Zimblesnerd:BAAALAAECgEIAQAAAA==.Zithenex:BAAALAAECgIIAgAAAA==.',Zu='Zumanîty:BAAALAADCggIDgAAAA==.',Zw='Zwar:BAAALAADCggIDwAAAA==.',['Zü']='Zümänity:BAAALAADCggIDwAAAA==.',['Ál']='Álister:BAAALAADCgQIBAAAAA==.',['Ér']='Éragon:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end