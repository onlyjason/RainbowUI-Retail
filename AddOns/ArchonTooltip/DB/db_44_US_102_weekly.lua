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
 local lookup = {'Unknown-Unknown',}; local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aazeeroothh:BAAALAADCgQIBAAAAA==.',Ab='Abadão:BAAALAAECgUIBQAAAA==.Abigaiill:BAAALAADCgUIBQAAAA==.',Ac='Acelord:BAAALAADCgcIBwAAAA==.',Ad='Adariom:BAAALAADCgYIBwAAAA==.Adriannos:BAAALAADCgcIDwAAAA==.',Ae='Aeliana:BAAALAADCgQIAgAAAA==.',Ag='Agakii:BAAALAADCgcIBwAAAA==.',Ak='Akashhi:BAAALAADCgEIAQAAAA==.Akatisuque:BAAALAAECgEIAQAAAA==.',Al='Alaissa:BAAALAADCgcIBwAAAA==.Alcarecco:BAAALAAECgIIAgAAAA==.Aleholyn:BAAALAADCgIIAgAAAA==.Alexextreme:BAAALAADCgYIBgAAAA==.Almaimortal:BAAALAADCgQICAAAAA==.Alymswan:BAAALAADCgIIAgAAAA==.',Am='Americamg:BAAALAADCgQIBAAAAA==.Américamg:BAAALAADCgUICgAAAA==.Américaptmg:BAAALAADCgYIBgAAAA==.',An='Andrems:BAAALAADCgIIAgAAAA==.Andrit:BAAALAADCggICAAAAA==.Angelloz:BAAALAAECgYICgAAAA==.Aniell:BAAALAADCgYIAwAAAA==.Anjelvs:BAAALAADCgcIBwAAAA==.Annaoh:BAAALAAECgUICAAAAA==.Anon:BAAALAADCgcICQAAAA==.Antorea:BAAALAAECgMIAwABLAAECgYIDgABAAAAAA==.',Ar='Ardatlili:BAAALAAECgEIAQAAAA==.Artpaladin:BAAALAADCgYIBgAAAA==.',As='Ashyashiida:BAAALAADCgMIAwAAAA==.',At='Atonos:BAAALAADCgcIDQAAAA==.',Ba='Bahruk:BAAALAADCgQIBQAAAA==.Bainedemon:BAAALAADCgMIAwAAAA==.Ballatax:BAAALAAECgMIBQAAAA==.Balragouldur:BAAALAADCgQIBAAAAA==.Bandala:BAAALAADCggIEAAAAA==.',Be='Beliall:BAAALAADCgYIBwAAAA==.Bemmaith:BAAALAAECgEIAQAAAA==.Berr:BAAALAADCgEIAQAAAA==.Berthina:BAAALAADCgEIAQAAAA==.Bestwarriorr:BAAALAAECgYICgAAAA==.',Bi='Bigdmg:BAAALAADCggIBwAAAA==.',Bl='Blackteriaa:BAAALAAECgIIAwAAAA==.Bladhe:BAAALAAECgMIBQAAAA==.Blazzy:BAAALAADCgYIBgAAAA==.Blittão:BAAALAADCgEIAQAAAA==.Bloodh:BAAALAADCgQIAwAAAA==.',Bo='Boijf:BAAALAADCgYIBgAAAA==.Borisobruxo:BAAALAAECgMIAwAAAA==.',Br='Braandom:BAAALAADCgMIAgAAAA==.Braizss:BAAALAAECgQIBAAAAA==.Bridda:BAAALAAECgYICgAAAA==.',Bt='Btrader:BAAALAADCgQIBAAAAA==.',['Bé']='Béto:BAAALAAECgIIBAAAAA==.',Ca='Caridosa:BAAALAAECgQIBwAAAA==.Catalango:BAAALAAECgYICAAAAA==.Catapózão:BAAALAAECgEIAgAAAA==.',Ce='Celestine:BAAALAADCgcIDQAAAA==.',Ch='Chaya:BAAALAAECgUICAAAAA==.',Ci='Cirolet:BAAALAAECgEIAgAAAA==.',Cl='Clandestina:BAAALAADCgEIAQAAAA==.Climps:BAAALAADCggICwAAAA==.',Co='Coachmuda:BAAALAADCgYIBgAAAA==.',Cr='Creico:BAAALAADCgcIDgAAAA==.Crhomaggus:BAAALAADCgcIBwAAAA==.Criistyn:BAAALAADCgYIBgAAAA==.Crookedyoung:BAAALAADCgEIAQAAAA==.Crysdelia:BAAALAADCgUIBgAAAA==.Cröwllëy:BAAALAAECgEIAQAAAA==.',Cu='Cubatao:BAAALAADCgcICgAAAA==.Curinhas:BAAALAADCgcIBwAAAA==.',['Cä']='Cämüs:BAAALAAECgYIDwAAAA==.',Da='Daenay:BAAALAADCggIDwAAAA==.Damataa:BAAALAAECgcIDQAAAA==.Danielpve:BAAALAADCgIIAgAAAA==.',De='Deathstãr:BAAALAAECgEIAQAAAA==.Deboxe:BAAALAADCgEIAQAAAA==.Dedogrosso:BAAALAADCgcIBwAAAA==.Demonphantom:BAAALAAECgMIAwAAAA==.Derothey:BAAALAAECgMIBQAAAA==.Deuspalaa:BAAALAADCgQIBgAAAA==.',Di='Dimoniu:BAAALAAECgYIDQAAAA==.',Dn='Dnghidan:BAAALAAECgEIAQAAAA==.',Do='Dollynhø:BAAALAAECgUIBgAAAA==.Donalddrunk:BAAALAAECgYIBwAAAA==.',Dp='Dplanet:BAAALAADCgIIAgAAAA==.',Dr='Draconicsoul:BAAALAADCgMIAgAAAA==.Dravelius:BAAALAADCggICQAAAA==.Draxion:BAAALAADCgEIAQAAAA==.Drmusculos:BAAALAADCgcICgAAAA==.Drogoon:BAAALAADCgUIBQAAAA==.Druidaezeki:BAAALAAECgUIBQAAAA==.Druidnegro:BAAALAADCgQIBwAAAA==.',Du='Dultrasenegl:BAAALAADCggIDAAAAA==.Dunois:BAAALAADCgYIBgABLAAECgQIBQABAAAAAA==.',['Dë']='Dëathwing:BAAALAADCgIIAgAAAA==.',Ed='Edven:BAAALAAECgQIBQAAAA==.',Ei='Eirhys:BAAALAADCgUICQAAAA==.',El='Elbruxão:BAAALAADCgQIAQAAAA==.Elementais:BAAALAADCgQIBQAAAA==.Elfera:BAAALAAECgEIAQAAAA==.Ellanor:BAAALAAECgEIAQAAAA==.Eloaah:BAAALAADCgMIAwAAAA==.',Em='Emiteh:BAAALAADCgYIBgAAAA==.',En='Enchantrix:BAAALAADCgYICQAAAA==.',Es='Esporotricos:BAAALAADCgcICwAAAA==.Estregobor:BAAALAADCgEIAQAAAA==.',Ev='Evely:BAAALAAECgMIBAAAAA==.',Ex='Exarch:BAAALAAECgcIDwAAAA==.',Fa='Fahli:BAAALAAECgYIBgAAAA==.',Fh='Fheanor:BAAALAAECgIIAgAAAA==.',Fi='Figy:BAAALAADCgMIAwAAAA==.',Fl='Flameseek:BAAALAADCgcIBwAAAA==.',Fo='Fogareiro:BAAALAADCgIIAgAAAA==.',Fr='Freezeknight:BAAALAADCgcICwAAAA==.Friodokrl:BAAALAADCgEIAQAAAA==.',Fs='Fswefs:BAAALAADCgcIDQAAAA==.',Fu='Fubukiofhell:BAAALAAECgMICAAAAA==.Furryenjoyer:BAAALAADCgcIBwAAAA==.',['Fü']='Füba:BAAALAAECgQIBQAAAA==.',Ga='Gabrielmr:BAAALAADCgcIBwAAAA==.Gabyblack:BAAALAADCgYIBgAAAA==.Gaeldry:BAAALAADCggICQAAAA==.Gafgar:BAAALAAECgIIAgAAAA==.',Gb='Gbziinns:BAAALAAECgMIAwAAAA==.',Gi='Gintonica:BAAALAAECgEIAgAAAA==.Giradus:BAAALAADCgYICgAAAA==.Giripoca:BAAALAAECgQICAABLAAECgcIDQABAAAAAA==.',Gl='Gladsdruid:BAAALAAECgMIBAAAAA==.',Gn='Gnomagga:BAAALAADCgYIBgAAAA==.',Go='Gonb:BAAALAADCgQIBAAAAA==.Gorgadron:BAAALAADCggICAAAAA==.Gotadapinga:BAAALAADCgYIBgAAAA==.Govannon:BAAALAADCgQIBAAAAA==.',Gr='Grillnborst:BAAALAADCgcIDAAAAA==.Gromoff:BAAALAADCgIIAQAAAA==.Grømmar:BAAALAAECgYICQAAAA==.',Ha='Haakaí:BAAALAAECgIIAgAAAA==.Halera:BAAALAADCgIIAgAAAA==.Hamellin:BAAALAADCgcIBwAAAA==.Hanjaro:BAAALAADCgcIBgAAAA==.Haowie:BAAALAADCgMIAwAAAA==.Hardex:BAAALAADCggICAAAAA==.Harrypotinho:BAAALAAECgMIAwAAAA==.',He='Healgate:BAAALAAECgUIBwAAAA==.Heiwarts:BAAALAADCggICQAAAA==.Helens:BAAALAADCgMICAAAAA==.Helsiing:BAAALAAECgEIAQAAAA==.Hendgar:BAAALAAECgEIAQAAAA==.Henks:BAAALAADCgYICQAAAA==.Heróói:BAAALAADCgYIBgAAAA==.Heviia:BAAALAADCgQIBAAAAA==.',Ho='Hollydeath:BAAALAADCggICQAAAA==.Hoodcat:BAAALAADCgQIBQAAAA==.',Ht='Htapal:BAAALAADCgMIAwAAAA==.',Hu='Hunterzinhoo:BAAALAADCggIEwAAAA==.',['Hí']='Hídan:BAAALAADCggICAAAAA==.',['Hø']='Høkulani:BAAALAADCggICAAAAA==.',Ic='Icaas:BAAALAAECgYIDAAAAA==.Ichimonji:BAAALAADCgEIAQAAAA==.',Ig='Igordcz:BAAALAADCgYIBwAAAA==.Igormh:BAAALAADCgYICAAAAA==.',Il='Illidansan:BAAALAADCgMIAwABLAAECgIIAgABAAAAAA==.',In='Incarus:BAAALAADCgUIBQAAAA==.Indis:BAAALAADCgYICQAAAA==.',Ir='Iramm:BAAALAADCgcIBwAAAA==.',Is='Iscalio:BAAALAAECgMIAwAAAA==.',Ja='Jahuun:BAAALAADCgcICwAAAA==.Jaybotega:BAAALAAECgYIBwAAAA==.',Je='Jefflich:BAAALAADCggIEAAAAA==.',Ju='Jubard:BAAALAADCgYICQAAAA==.Justbones:BAAALAADCgYIBgAAAA==.',Jv='Jvrok:BAAALAADCgYIBgAAAA==.',['Jã']='Jãozen:BAAALAADCgMIBAAAAA==.',Ka='Kaguura:BAAALAADCgEIAQAAAA==.Kainele:BAAALAADCgcIBwAAAA==.Kaleuz:BAAALAAECgIIAgAAAA==.Kamasutram:BAAALAAECgIIAgAAAA==.Kaosz:BAAALAAECgYIBgAAAA==.Karynaa:BAAALAADCgcIBwAAAA==.Kavookavalaa:BAAALAADCggIFgAAAA==.Kazehiro:BAAALAADCgcICgAAAA==.Kaßßy:BAAALAADCgYICAAAAA==.',Ke='Kendør:BAAALAAECgUICQAAAA==.',Ki='Killerdek:BAAALAADCgcIBwAAAA==.Killred:BAAALAADCgEIAQAAAA==.Kinosh:BAAALAAECgYICgAAAA==.Kissmë:BAAALAAECgIIAgABLAAECgQIBQABAAAAAA==.',Ko='Koenma:BAAALAADCggIDwAAAA==.Komodordàros:BAAALAADCgEIAQAAAA==.Korav:BAAALAADCgUIBgAAAA==.',Kp='Kpiivara:BAAALAADCgcIBwAAAA==.',Kr='Kraveen:BAAALAADCgQIBwAAAA==.Krihstina:BAAALAADCggIEAAAAA==.Krix:BAAALAAECgUIBwAAAA==.Kroublin:BAAALAADCgMIAwAAAA==.',Ky='Kyleehendrix:BAAALAADCgUIBQAAAA==.Kyutaxama:BAAALAAECgQIAwAAAA==.',La='Lacerda:BAAALAADCggIDgAAAA==.Ladinoreii:BAAALAADCgQIBAAAAA==.Lanjierry:BAAALAADCgIIAwAAAA==.Lassus:BAAALAADCgcIDgAAAA==.Lauraela:BAAALAADCgEIAQAAAA==.Laurea:BAAALAAECgYIDgAAAA==.',Le='Lefthalas:BAAALAADCggICAAAAA==.Leore:BAAALAADCgEIAQAAAA==.',Lh='Lhea:BAAALAADCggIDgAAAA==.',Li='Liandariel:BAAALAAECgYIBwAAAA==.Liaras:BAAALAADCgIIAgAAAA==.Liifecomm:BAAALAAECgYIDwAAAA==.Linkertoo:BAAALAADCggICAAAAA==.',Ll='Llywelyn:BAAALAAECgIIAwAAAA==.',Lo='Lobisominhoi:BAAALAADCgcICAAAAA==.Lockart:BAAALAAECgYICAAAAA==.Lookatmylock:BAAALAADCggICQAAAA==.Lorwin:BAAALAAECgEIAQAAAA==.Lothrienn:BAAALAAECgcIEwAAAA==.',Lu='Luapelada:BAAALAADCgUIBwAAAA==.Ludas:BAAALAADCgIIAgAAAA==.Lukaslions:BAAALAAECgcIDgAAAA==.Lunnari:BAAALAADCgYIBgAAAA==.',['Lø']='Lørdsith:BAAALAAECggIDQAAAA==.Løre:BAAALAADCggIEgAAAA==.',['Lú']='Lúmine:BAAALAAECgYIBwAAAA==.',Ma='Maelsthar:BAAALAADCgMIAwAAAA==.Magoxandao:BAAALAAECgEIAQAAAA==.Maguword:BAAALAAECgEIAQAAAA==.Malandrvs:BAAALAAECgcIDAAAAA==.Malphoros:BAAALAADCgQIBgAAAA==.Mandingavudu:BAAALAADCgcIBgABLAADCggIDgABAAAAAA==.Mangaa:BAAALAADCgIIAgAAAA==.Manzagon:BAAALAADCggIDgAAAA==.Marentd:BAAALAADCgEIAQAAAA==.Marmelo:BAAALAADCgcICQAAAA==.Mazdamundi:BAAALAAECgcIBwAAAA==.',Me='Melyodasz:BAAALAADCgUIBQAAAA==.Mendingu:BAAALAAECgMIAwAAAA==.',Mh='Mhael:BAAALAADCggIFAAAAA==.Mhezz:BAAALAADCgEIAQAAAA==.',Mi='Michelmixx:BAAALAADCgYIBgAAAA==.Mikasaackerr:BAAALAADCgIIAgAAAA==.Mirall:BAAALAAECgIIAwAAAA==.Mithzor:BAAALAAECgEIAQAAAA==.',Mo='Monkyr:BAAALAADCgIIAgAAAA==.Moonluter:BAAALAADCggIDQAAAA==.Morphiszs:BAAALAADCgYICgABLAADCggIDgABAAAAAA==.Morphizs:BAAALAADCgUIBAABLAADCggIDgABAAAAAA==.Mortenegro:BAAALAADCgcIBwAAAA==.Moxx:BAAALAAECgMIBAAAAA==.',Mu='Mulungu:BAAALAADCgQIBAAAAA==.Murasakichan:BAAALAADCgcICAAAAA==.Muwhu:BAAALAADCgcICQAAAA==.',My='Mynnokyr:BAAALAAECgMIAwAAAA==.',Na='Naeryndam:BAAALAADCgMIAwAAAA==.Natally:BAAALAADCggIFQAAAA==.Navajos:BAAALAAECgMIBQAAAA==.',Ne='Necrox:BAAALAADCgQICwAAAA==.Nefasto:BAAALAADCgUIBAAAAA==.Netbrother:BAAALAAECgMIAwAAAA==.Netherbane:BAAALAADCgcICQAAAA==.',Ni='Nightmaregg:BAAALAADCgcIBwAAAA==.',No='Nosferatuxd:BAAALAAECgMICgAAAA==.Nosrede:BAAALAAECgMIBQAAAA==.',Nu='Nuccixama:BAAALAADCggICAAAAA==.',Ny='Nynfa:BAAALAADCgQIBAAAAA==.',['Në']='Nëtszs:BAAALAADCgEIAQAAAA==.',Op='Opalãoo:BAAALAAECgEIAQAAAA==.',Or='Orell:BAAALAADCgMIAwAAAA==.Orzon:BAAALAAECgYIDwAAAA==.',Ov='Overwalker:BAAALAADCgQIBgAAAA==.',Pa='Paladinokun:BAAALAAECgIIAgAAAA==.Paraguaizito:BAAALAADCggICAAAAA==.Patofus:BAAALAADCggIEwAAAA==.',Pe='Pepéti:BAAALAADCgMIAwAAAA==.Pereiro:BAAALAADCgEIAQAAAA==.Peruadavida:BAAALAADCgEIAQAAAA==.Peubolo:BAAALAADCggICAAAAA==.Peçanhaa:BAAALAADCgIIAgAAAA==.',Pi='Pisãonegro:BAAALAADCgMIAwAAAA==.Piup:BAAALAADCgcIBwAAAA==.Piupdemon:BAAALAADCgEIAQAAAA==.',Pl='Plizs:BAAALAADCgMIBAAAAA==.',Pr='Priestizila:BAAALAADCggIEwAAAA==.Prostytutah:BAAALAADCgIIAwAAAA==.',Pu='Puherito:BAAALAADCggICAAAAA==.',Qu='Quandorel:BAAALAADCgUIBQAAAA==.Quebrador:BAAALAAECgIIAgAAAA==.',Re='Reíko:BAAALAADCggIFwAAAA==.',Rh='Rhaegaar:BAAALAAECgIIAwAAAA==.Rhetrelyan:BAAALAADCgYICQAAAA==.',Ro='Roraima:BAAALAADCgcIBwAAAA==.Rovagug:BAAALAADCgQIBAAAAA==.Rozuy:BAAALAADCggICgAAAA==.',Ru='Rurdi:BAAALAADCgcIBwAAAA==.Rustzy:BAAALAADCgYIBgAAAA==.',Sa='Sanctorium:BAAALAAECgMIBAAAAA==.Sanguinus:BAAALAADCgUIBQAAAA==.Santiss:BAAALAAECgYICAAAAA==.Sapanddied:BAAALAADCggICQAAAA==.Saphis:BAAALAAECgMIBQAAAA==.Satryin:BAAALAADCgEIAQAAAA==.Satyricon:BAAALAAECgEIAQAAAA==.',Sc='Scanorr:BAAALAADCgYIBgAAAA==.Scawydwagon:BAAALAAECgMIAwAAAA==.Scwhite:BAAALAADCgYIBgAAAA==.',Se='Seralyephen:BAAALAAECgIIAgAAAA==.',Sh='Shaladrasil:BAAALAADCgQIBQAAAA==.Sherron:BAAALAADCgQIBAAAAA==.Shonin:BAAALAADCgQIBAAAAA==.Shorme:BAAALAAECgUIBwABLAAECggIEgABAAAAAA==.Shubbam:BAAALAADCgUIBQAAAA==.Shynato:BAAALAAECgEIAgAAAA==.Sháders:BAAALAADCgIIAgAAAA==.',Si='Sirgonzo:BAAALAAECgMIAwAAAA==.',Sk='Skie:BAAALAAECgMIAwAAAA==.Skilks:BAAALAADCgcICAAAAA==.',Sm='Smitharms:BAAALAADCgQIBAAAAA==.',So='Sohwarr:BAAALAADCgcIDAAAAA==.Sombara:BAAALAAECgcIDQAAAA==.Sorim:BAAALAAECgIIAgAAAA==.Soryan:BAAALAAECgIIAgAAAA==.',Sp='Spartanlofs:BAAALAADCggIEwAAAA==.',Sr='Srduid:BAAALAADCgcIBwAAAA==.',St='Starvulpix:BAAALAAECgYICgAAAA==.Statz:BAAALAAECgEIAQAAAA==.',Sw='Sweetcaress:BAAALAADCgcIBwAAAA==.Sweetl:BAAALAAECgEIAQAAAA==.',Sy='Syliria:BAAALAADCgEIAQAAAA==.',Ta='Taillys:BAAALAADCgQIDgAAAA==.Talanis:BAAALAADCggIEAABLAAECgYIDgABAAAAAA==.Taldoo:BAAALAADCggIEgAAAA==.Tarez:BAAALAAECgEIAQAAAA==.Tarfonir:BAAALAADCggIHAAAAA==.Tashian:BAAALAADCgMIAwAAAA==.Tauribel:BAAALAADCgYIBgAAAA==.Tavegrid:BAAALAAECgIIAgAAAA==.Tavius:BAAALAADCgYIBwAAAA==.',Th='Thegoliath:BAAALAAECgIIAwAAAA==.Thepickles:BAAALAADCgEIAQAAAA==.Theusmaz:BAAALAAECgEIAQAAAA==.Thirym:BAAALAADCgcIBwAAAA==.Thoryinn:BAAALAADCgYIBgAAAA==.',Ti='Tiarranho:BAAALAAECgMIAwAAAA==.Tieles:BAAALAAECgQIBQAAAA==.Tikutuku:BAAALAADCggIDwAAAA==.',To='Tokajj:BAAALAADCgQIBAAAAA==.Topon:BAAALAADCgUICQAAAA==.',Tr='Trolenciaa:BAAALAADCggICAAAAA==.Trévor:BAAALAAECgEIAQAAAA==.',Tu='Tupanã:BAAALAAECgEIAQAAAA==.Tutankamon:BAAALAAECgMIAwAAAA==.',Tw='Twoheavy:BAAALAADCggICAAAAA==.',Tx='Txinga:BAAALAADCgYIBgAAAA==.',Ty='Tyna:BAAALAADCgUIBQAAAA==.',Um='Umaguxo:BAAALAADCgMIAwAAAA==.',Ut='Uthred:BAAALAADCggIEwAAAA==.',Va='Valkorr:BAAALAADCgQIBAAAAA==.Valororo:BAAALAAECgIIAwAAAA==.',Vi='Victoriä:BAAALAADCgUIBQAAAA==.Vindicta:BAAALAADCgYIBgAAAA==.Vizaladriel:BAAALAADCggIFAAAAA==.',['Vä']='Vänhëlsing:BAAALAAECgIIAgAAAA==.',Wa='Walzý:BAAALAADCgEIAQAAAA==.',Wi='Wildgirll:BAAALAAECgYICgAAAA==.Willdemonx:BAAALAADCgMIAwAAAA==.Windragon:BAAALAADCggIEAAAAA==.Wiserys:BAAALAAECgYICAAAAA==.',Wo='Wopz:BAAALAADCgYIBwAAAA==.',Wt='Wtr:BAAALAADCggICwAAAA==.',Xd='Xdiego:BAAALAAECgMIAwAAAA==.',Xe='Xexnew:BAAALAAECgQIBQAAAA==.',Xg='Xgarugx:BAAALAADCgEIAQAAAA==.',Xi='Xinthorak:BAAALAADCgcIBwAAAA==.',Xm='Xmari:BAAALAAECgEIAQAAAA==.',Xp='Xpresuntinho:BAAALAAECgQIBAAAAA==.',Xu='Xuunn:BAAALAAECgIIAgAAAA==.',Xx='Xxarcanjoxx:BAAALAADCggICQAAAA==.Xxhadwenxx:BAAALAADCgQIBwAAAA==.',Ya='Yamada:BAAALAADCggICAAAAA==.Yaoyorozu:BAAALAAECgQIBQAAAA==.',Yo='Yogafire:BAAALAADCgUIBgAAAA==.',Yu='Yu:BAAALAADCgMIAwAAAA==.',Za='Zaaraki:BAAALAAECgMIAwAAAA==.Zahheer:BAAALAAECgIIAgAAAA==.Zayyon:BAAALAADCgIIAgAAAA==.',Ze='Zelathar:BAAALAADCggIFAAAAA==.Zenitsua:BAAALAADCgMIBQAAAA==.Zerafin:BAAALAADCgMIAwAAAA==.Zerdrax:BAAALAAECgIIAgAAAA==.',Zi='Ziirael:BAAALAADCgIIAgAAAA==.',Zk='Zkoringas:BAAALAADCgUIBwAAAA==.',Zo='Zombiepala:BAAALAADCgUIBQAAAA==.Zorgg:BAAALAADCgQIBAAAAA==.',Zz='Zzx:BAAALAADCgIIAgAAAA==.',['Zë']='Zëus:BAAALAADCgQIAQAAAA==.',['Zí']='Zíngarah:BAAALAADCgcICAAAAA==.',['Áa']='Áang:BAAALAADCgYIBwAAAA==.',['Áx']='Áxel:BAAALAADCgYIBgAAAA==.',['Ær']='Æromen:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end