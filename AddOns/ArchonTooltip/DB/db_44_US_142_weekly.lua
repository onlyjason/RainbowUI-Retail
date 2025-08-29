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
 local lookup = {'Unknown-Unknown','DeathKnight-Frost','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Mage-Frost','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Mage-Arcane','Mage-Fire','Shaman-Elemental','Priest-Shadow',}; local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=44,date='2025-08-29',data={Aj='Ajunlucky:BAAALAAECgcIEAAAAA==.',Ak='Aknologia:BAAALAAECgMIBAAAAA==.',Al='Alanazurend:BAAALAADCgUIBQAAAA==.Alexari:BAAALAAECgEIAQAAAA==.Allcoholic:BAAALAADCgUIBQAAAA==.Alody:BAAALAAECgEIAQAAAA==.',An='Andrea:BAAALAAECgEIAQAAAA==.Andybernard:BAAALAADCgYIBgAAAA==.',Ar='Aramala:BAAALAAECgMIAwAAAA==.Argentzephyr:BAAALAAECgEIAgAAAA==.Armados:BAAALAADCggIDwAAAA==.',As='Astalos:BAAALAADCggIDwAAAA==.',Av='Avatorque:BAAALAADCgQIBAAAAA==.',Ay='Aylinn:BAAALAAECgYICwAAAA==.Aymonzo:BAAALAAECgYICQAAAA==.Ayumi:BAAALAADCggICAAAAA==.',Az='Azem:BAAALAADCgcIBwAAAA==.Azulean:BAAALAADCgQIBAAAAA==.',Ba='Badlóck:BAAALAAECggIAQABLAAECggIEgABAAAAAA==.Baisedarbre:BAAALAADCgcIBQAAAA==.Ballidur:BAAALAADCgYICwAAAA==.Bamz:BAAALAAECgMIAwAAAA==.',Be='Bearalas:BAAALAAECgcICAAAAA==.Beastreality:BAAALAAECgQIBwAAAA==.Beatia:BAAALAADCggICAAAAA==.Becky:BAABLAAECoEVAAICAAgIeh2EDwCRAgACAAgIeh2EDwCRAgAAAA==.Betelgeuse:BAAALAAECgcIEAAAAA==.',Bi='Bigoysters:BAAALAAECgEIAQAAAA==.Binnyi:BAAALAAECgYICAAAAA==.',Bl='Blackfoot:BAAALAAECgMIBQAAAA==.Bladivile:BAAALAAECgYICAAAAA==.Blistur:BAAALAADCgcICQAAAA==.Bluegoblin:BAAALAAECgMIAwAAAA==.',Bo='Bouberry:BAAALAAECgYICgAAAA==.Bovinedor:BAAALAAECgYIDwAAAA==.Bowzer:BAAALAAECgEIAQAAAA==.',Br='Brabiant:BAAALAAECgEIAQABLAAECgMIBAABAAAAAA==.',Bu='Bubbleaddict:BAAALAAECgEIAQAAAA==.Bunsu:BAAALAAECgQIBAAAAA==.Butcrack:BAAALAAECgEIAQAAAA==.',Ca='Cabael:BAAALAAECgQIBAAAAA==.Cakeshake:BAAALAAECgEIAQAAAA==.Calistos:BAAALAADCggIDwAAAA==.Camelnuckle:BAAALAAECgYIDQAAAA==.Candor:BAAALAAECgYICgAAAA==.Cattle:BAAALAAECgYIBgAAAA==.',Ch='Chaostorms:BAAALAAECgYIEAAAAA==.Chardinator:BAAALAADCggICAAAAA==.Chess:BAAALAADCgcIBwAAAA==.Chikenhydra:BAAALAAECgQICAAAAA==.Chowdo:BAAALAADCggICAAAAA==.',Ci='Cihuacoatl:BAAALAAECggICAAAAA==.',Cl='Clawsofpeace:BAAALAAECgYICwAAAA==.',Co='Congelati:BAAALAADCgYICQAAAA==.Corcid:BAAALAADCgMIAwAAAA==.',Cp='Cptmorgan:BAAALAAECgYICAAAAA==.',Cr='Cryodk:BAAALAAECggIBQAAAA==.Cryosham:BAAALAAECggIBQAAAA==.Crypteque:BAAALAADCgUIBQAAAA==.',Da='Daddiestouch:BAAALAAECgMIAwAAAA==.Dampundies:BAAALAAECgQICAAAAA==.Dangerdoom:BAAALAAECgYICAAAAA==.Darkàn:BAAALAAECgYICAAAAA==.Davislk:BAAALAAECgMIAwAAAA==.',De='Deadvikingg:BAAALAAECgEIAQAAAA==.Deadwix:BAAALAADCgcIBwAAAA==.Deathadoom:BAAALAAECgYICgAAAA==.Deathtaker:BAAALAAECgEIAgAAAA==.Dekel:BAAALAAECggIAQAAAA==.Dekomori:BAAALAAECgQIBQAAAA==.Demonata:BAAALAAECgMIAwAAAA==.Derpmonk:BAAALAAECgIIAgAAAA==.Destrada:BAAALAADCgYIBgAAAA==.Destrah:BAAALAADCggIFQAAAA==.Devbusswife:BAABLAAECoEUAAIDAAcIfiMABAC0AgADAAcIfiMABAC0AgAAAA==.Deviiarrc:BAAALAAECgQIBgAAAA==.',Di='Diamondhands:BAAALAAECgEIAQAAAA==.Dibi:BAAALAAECgYIBgAAAA==.',Dl='Dlamb:BAAALAAECgQIBgAAAA==.',Do='Doroga:BAAALAADCgIIAgAAAA==.',Dr='Drainlife:BAAALAAECgcICQAAAA==.Dreyvina:BAAALAAECgIIAgAAAA==.Drmmrhunter:BAAALAAECgYICwAAAA==.Dronox:BAAALAADCgYIBgAAAA==.Drtism:BAAALAADCgUIBgAAAA==.',Dw='Dwippietiggs:BAAALAAECgQIBAAAAA==.',Ea='Earthlocked:BAAALAADCgcIDgAAAA==.',Ek='Ekitten:BAAALAAECgYIBgAAAA==.',El='Electrodè:BAAALAADCgEIAQAAAA==.Elements:BAAALAAECgEIAQAAAA==.',Em='Emberstone:BAAALAADCggIDgAAAA==.Emoux:BAAALAADCgYIBgAAAA==.',Ep='Epicdragon:BAAALAADCgUIBwAAAA==.',Er='Eralia:BAAALAAECgYICgAAAA==.Eralt:BAAALAAECgYICAAAAA==.',Ev='Evo:BAAALAAECgYICgAAAA==.',Fa='Faithshand:BAAALAAECgYICAAAAA==.Fallenbow:BAAALAADCgIIAgAAAA==.Fallengrace:BAAALAADCgMIAwAAAA==.Faythé:BAAALAADCgEIAQAAAA==.',Fe='Fellumir:BAAALAAECgQICQAAAA==.Femmeabarbe:BAAALAADCgMIBAAAAA==.Feorana:BAAALAAECgYICAAAAA==.Fergie:BAAALAADCgMIAwAAAA==.Fergilicious:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Fetti:BAAALAADCgcICwAAAA==.',Fi='Finkenator:BAAALAAFFAIIAgAAAA==.Finkler:BAAALAAFFAIIAgABLAAFFAIIAgABAAAAAA==.',Fl='Flameshock:BAAALAAECgYICgABLAAECgYICgABAAAAAA==.Florsynthia:BAAALAAECgYIDgAAAA==.Flylikebug:BAAALAAECgUIBwAAAA==.',Fr='Fragility:BAAALAAECgcIDwAAAA==.Frewdye:BAAALAADCgMIAwAAAA==.Frostborn:BAAALAADCgYIBgAAAA==.Frozeny:BAAALAADCgcIDwAAAA==.Frïgïdbïch:BAAALAAECgYIBgAAAA==.',Ga='Galiria:BAAALAAECgcIBwAAAA==.Gamthor:BAAALAAECgUIBQAAAA==.',Gh='Ghale:BAAALAADCgcIBwAAAA==.',Gl='Gleebo:BAEALAADCgYIBgAAAA==.Glengoyne:BAAALAAECgMIBAAAAA==.Globalwarmin:BAAALAADCggICAAAAA==.Globoe:BAACLAAFFIEQAAMEAAYIxSQQAACHAgAEAAYIzSMQAACHAgAFAAII7iKAAADdAAAsAAQKgSgAAwUACAi7JhEAAIADAAUACAghJhEAAIADAAQACAipJlgBAFYDAAAA.Gloreb:BAAALAADCgYIBgAAAA==.',Gr='Grahz:BAAALAAECgQIBAAAAA==.Grizzlebee:BAAALAADCgUIBQAAAA==.',Gw='Gwolambi:BAAALAADCgcIBwAAAA==.',Gy='Gypsyjinx:BAAALAAECgEIAQAAAA==.',['Gé']='Gérald:BAAALAAECgEIAQAAAA==.',Ha='Haakon:BAAALAADCgMIBgAAAA==.Hairybearie:BAAALAAECgQIBAAAAA==.Hairypawter:BAAALAADCgMIAwAAAA==.Harrowing:BAABLAAECoEYAAIGAAgI6xzlAwCnAgAGAAgI6xzlAwCnAgAAAA==.Haurt:BAAALAAECgYIDQAAAA==.',He='Healnbot:BAAALAAECgMIBAAAAA==.',Hi='Highground:BAAALAADCgcIDwAAAA==.Hischier:BAAALAADCgcIBwAAAA==.Hixyn:BAAALAAFFAMIBQAAAQ==.',Ho='Holyschiz:BAAALAADCggIDQAAAA==.Homelander:BAAALAAECgUIBQAAAA==.',Hu='Huge:BAAALAAECgUIBQAAAA==.Humanpriest:BAAALAADCgcIEgABLAAECgEIAQABAAAAAA==.Hurg:BAAALAADCgcIBwAAAA==.',Ih='Ihateyoudude:BAAALAAECgEIAQAAAA==.',Il='Illindis:BAAALAAECgMIAwAAAA==.Illona:BAAALAAECgIIAgAAAA==.',Im='Impguy:BAAALAADCggIDQABLAAECggIBgABAAAAAA==.',In='Indibvisible:BAAALAAECggICAAAAA==.Insañe:BAAALAAECggIEgAAAA==.Invisibulls:BAAALAADCggIDQABLAAECgYIBgABAAAAAA==.',Ir='Iron:BAABLAAECoEXAAIHAAgILSXiAwA1AwAHAAgILSXiAwA1AwAAAA==.',Is='Isinister:BAAALAADCgcICAAAAA==.',Iu='Iustus:BAAALAAECgQIBQAAAA==.',Ja='Jayylols:BAAALAAECgIIAgAAAA==.',Ka='Katasha:BAAALAAECgMIAwAAAA==.Kazraghand:BAAALAAECgYICwAAAA==.',Ke='Kei:BAAALAADCggICAAAAA==.Kelsio:BAAALAAECgMIAwAAAA==.Kenkonga:BAAALAADCgYIBwAAAA==.Kerble:BAAALAADCgcIBwAAAA==.Keres:BAAALAADCgQIBAABLAAECgYIBgABAAAAAA==.',Kh='Kharos:BAAALAAECgcIEwAAAA==.',Ki='Kikeo:BAAALAAECgcIEwAAAA==.Kinks:BAAALAAECgYICgAAAA==.',Kl='Klemedor:BAAALAADCggICAABLAAECgYICgABAAAAAA==.',Ko='Kogori:BAAALAAECgMIBAAAAA==.Konsus:BAAALAADCgUIBgAAAA==.Kowthulu:BAAALAAECgIIAgABLAAECggIEQABAAAAAA==.',Kr='Krelsh:BAAALAAECggIBgAAAA==.',Ku='Kumquat:BAAALAADCgcIBwAAAA==.Kungfudegru:BAAALAAECgYICQAAAA==.',Ky='Kyleenä:BAAALAADCgIIAgAAAA==.Kyradin:BAAALAADCgEIAQAAAA==.',['Kí']='Kítkat:BAAALAAECgMIBQAAAA==.',La='Ladonra:BAAALAADCggIDwAAAA==.',Le='Ledge:BAAALAAECgQIBQAAAA==.Leibowitzy:BAAALAAECgEIAgAAAA==.',Lh='Lhehitman:BAABLAAECoEUAAIIAAcIZRu/CgAaAgAIAAcIZRu/CgAaAgAAAA==.',Li='Lidela:BAAALAADCgcICwAAAA==.Lightbuff:BAAALAADCgcICwAAAA==.',Lo='Lofi:BAAALAADCgYIBwAAAA==.Login:BAAALAAECgcIEAAAAA==.Lomur:BAAALAADCggICAAAAA==.Lorellion:BAAALAADCgMIAwAAAA==.',Lu='Ludey:BAAALAAECgcIEAAAAA==.Lutray:BAAALAAECgYICAAAAA==.',Ly='Lysandri:BAAALAAECgYICgAAAA==.Lythronax:BAAALAADCgEIAQAAAA==.',Ma='Macartwheez:BAAALAADCgIIAgAAAA==.Makembleed:BAAALAAECgEIAQAAAA==.Marodd:BAAALAAECgYICAAAAA==.Matylin:BAAALAADCgcIDQAAAA==.',Me='Mealgak:BAAALAADCgQIBAAAAA==.Meatbawl:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.Meatwangs:BAAALAAECgYIDQAAAA==.Meklena:BAAALAAECgYICAAAAA==.',Mi='Mikey:BAAALAADCgIIAgAAAA==.Milize:BAAALAAECgcIDQAAAA==.',Mk='Mkachen:BAAALAADCgEIAQAAAA==.',Mo='Mondergryn:BAAALAADCgUIBQAAAA==.Monkintrunk:BAAALAADCgcIBAABLAAECgMIBAABAAAAAA==.Moonslayer:BAAALAAECgYICAAAAA==.Morega:BAAALAADCgMIAwABLAAECgYICAABAAAAAA==.Mosag:BAAALAADCgcIBwAAAA==.',Mu='Mudgeon:BAAALAAECgYICAAAAA==.',Na='Nacal:BAAALAADCggIEwAAAA==.Nagarafan:BAAALAAECgEIAQAAAA==.',Ne='Nefeli:BAAALAAECgcIEAAAAA==.Nestia:BAAALAAECgEIAgAAAA==.Never:BAABLAAECoEVAAQJAAgICRy1DwBVAgAJAAgITxi1DwBVAgAKAAYIhRigBwDeAQALAAMI6BnoJgDrAAAAAA==.',Ni='Niccolò:BAAALAADCgcICAAAAA==.Nightbird:BAAALAADCggICQAAAA==.Nightshade:BAAALAAECgYICgAAAA==.Nikno:BAAALAAECgYICQAAAA==.Nirmahs:BAAALAADCgQIBAAAAA==.Nitren:BAAALAADCgMIAwABLAAECgYICAABAAAAAA==.Nitron:BAAALAAECgYICAAAAA==.',No='Nohzak:BAAALAAECgEIAQAAAA==.',Ob='Oblaan:BAAALAAECgYICAAAAA==.',Oc='Ocllo:BAAALAADCggICAAAAA==.',Of='Offwhite:BAAALAADCgYIBgAAAA==.',Oj='Ojo:BAAALAAECgYIBwAAAA==.',Ol='Olane:BAAALAAECgUIBQAAAA==.',On='Oneilldh:BAAALAADCgIIAgAAAA==.Oniana:BAAALAADCggIFgAAAQ==.',Or='Orlyra:BAAALAADCgcIBwAAAA==.',Ot='Ottoz:BAAALAAECgEIAQAAAA==.Otum:BAAALAAECgEIAQAAAA==.',Pa='Painbringer:BAAALAAFFAMIAwAAAA==.Palwix:BAAALAADCgYIBwAAAA==.Panter:BAAALAAECgEIAQABLAAECgEIAQABAAAAAA==.',Pe='Peacemaster:BAAALAAECgEIAQABLAAECgYICwABAAAAAA==.',Ph='Pharaoh:BAAALAAECgQICAAAAA==.Phodoe:BAAALAAECgYICAAAAA==.',Pi='Piers:BAAALAADCgMIAwAAAA==.',Pl='Playne:BAAALAAECgYIBgAAAA==.',Po='Pokeureyeout:BAAALAAECgEIAQAAAA==.Porkfeet:BAAALAADCgEIAQAAAA==.',Pr='Priestluvboy:BAAALAAECgcICQAAAA==.Prodyne:BAAALAAECgcIEAAAAA==.',Pu='Pumpkinpuff:BAAALAAECgYICQAAAA==.Purplppleatr:BAAALAADCgcIDQABLAADCggIDwABAAAAAA==.',Qd='Qd:BAAALAAECgQIBAAAAA==.',Qu='Quiettreader:BAAALAAECgEIAgAAAA==.',Ra='Raidboss:BAAALAAECgYICgAAAA==.Rayvennes:BAAALAAECgYICQAAAA==.',Re='Redeath:BAAALAADCggIDwAAAA==.Redonculous:BAAALAAECgYICwAAAA==.Regdod:BAAALAAECgIIAgAAAA==.Reinault:BAAALAAECgYIBgAAAA==.Rekkagh:BAAALAADCgcIBwAAAA==.Relina:BAAALAADCgcIBwAAAA==.Renalla:BAAALAADCggICAAAAA==.',Ri='Riona:BAAALAADCgYIBgAAAA==.',Ro='Rob:BAAALAAECgIIAgAAAA==.Roruk:BAAALAADCgcIBwAAAA==.Rorym:BAAALAADCgMIAwAAAA==.Roxxiloxxi:BAAALAAECgYIDQAAAA==.',Ru='Rubick:BAAALAADCggICwAAAA==.',['Rè']='Rèy:BAAALAADCgIIAgAAAA==.',Sa='Sabria:BAAALAAECgcIEAAAAA==.Sahria:BAAALAADCgcIDAAAAA==.Samlosco:BAAALAAECgcIEAAAAA==.Sark:BAAALAADCgUIBQAAAA==.Saturax:BAAALAADCgQIBAAAAA==.',Sc='Scalpelheals:BAACLAAFFIEOAAIMAAUI+hdFAADfAQAMAAUI+hdFAADfAQAsAAQKgSEAAgwACAguIawGAMICAAwACAguIawGAMICAAAA.Sceledrus:BAAALAAECgIIAgAAAA==.',Se='Sebekuul:BAAALAAECgUICgAAAQ==.Selbur:BAAALAAECgIIAgAAAA==.Sephurik:BAACLAAFFIEFAAMNAAMIuAXnDAChAAANAAIIfAXnDAChAAAOAAEILwYVAgBWAAAsAAQKgSAAAw0ACAhlHAwWAGECAA0ACAi2GQwWAGECAA4ABAgaGa8FAPYAAAAA.Serovin:BAAALAAECgQIBAAAAA==.',Sh='Shamaneez:BAAALAAECgYICQAAAA==.Shawker:BAAALAADCgYICwAAAA==.Showtek:BAAALAAECgYIEQAAAA==.Shrukina:BAAALAAECggIAwAAAA==.Shyft:BAAALAAECgEIAQAAAA==.',Si='Siddharthá:BAAALAAECgYICAAAAA==.Sikanda:BAAALAAECgYICQAAAA==.Simonds:BAAALAAECgIIAgAAAA==.Sinara:BAAALAAECggIEAAAAA==.Sion:BAAALAAECgYICwAAAA==.',Sk='Skoal:BAAALAAECgcIEAAAAA==.Sky:BAAALAAECgQIBAAAAA==.Skyelf:BAAALAAECgMIBAAAAA==.',Sl='Slatt:BAAALAAECgcIDQAAAA==.Sluggerr:BAAALAAECgcICQAAAA==.',Sn='Snape:BAAALAADCggIEgAAAA==.',So='Socratez:BAAALAAECgIIAgAAAA==.Sosaebum:BAAALAAECgYICwAAAA==.',Sp='Sparkd:BAAALAADCggIFAAAAA==.Spectrecles:BAAALAAECggIBQAAAA==.Spectrecless:BAAALAADCgMIAwABLAAECggIBQABAAAAAA==.Spookieturbo:BAAALAAECgUICgAAAA==.',St='Stablehand:BAAALAAECgMIAwAAAA==.Steve:BAACLAAFFIEFAAIPAAMIGQgdBADaAAAPAAMIGQgdBADaAAAsAAQKgSAAAg8ACAitI7ADADMDAA8ACAitI7ADADMDAAAA.Steâlth:BAAALAAECgMIAwAAAA==.Stonedfel:BAAALAAECgYICwAAAA==.Stor:BAAALAADCgMIAwAAAA==.',Su='Sullymonster:BAAALAADCgYIBgAAAA==.Sunweaver:BAAALAADCgQIBAAAAA==.',Sv='Svartr:BAAALAADCgcIBwAAAA==.',Sw='Sweetpotato:BAAALAADCgIIAgAAAA==.',Sy='Syx:BAAALAADCgcIBwAAAA==.',['Sø']='Sørrow:BAAALAAECgYICgAAAA==.',Ta='Tabi:BAAALAAECgYICAAAAA==.Taiyn:BAAALAADCggICAAAAA==.Tannarra:BAAALAADCgMIBAAAAA==.Tarryne:BAAALAAECgMIAwAAAA==.',Te='Teenytank:BAAALAADCgcICwAAAA==.Tenaciouzd:BAAALAADCgcICAAAAA==.',Th='Thechikening:BAAALAADCgMIAwABLAAECgQICAABAAAAAA==.Thedayman:BAAALAAECgUIBQAAAA==.Thedoginme:BAAALAADCgcIBwAAAA==.Theliono:BAAALAAECgMIBAAAAA==.Therwinn:BAAALAAECgYICQAAAA==.Thetaint:BAAALAAECgMIAwAAAA==.Thraxion:BAAALAAECgYIBgAAAA==.Thunderkow:BAAALAAECggIEQAAAA==.',Ti='Tigg:BAAALAADCgYIBwAAAA==.',To='Tomahawkchow:BAAALAAECgQIBQAAAA==.Totemofpeace:BAAALAADCgQIBQABLAAECgYICwABAAAAAA==.Totumly:BAAALAAECgMIAwAAAA==.Touchelement:BAAALAADCgcICAAAAA==.',Tr='Trentvoker:BAAALAAECgcIEwAAAA==.',Ts='Tsu:BAAALAAECgEIAQAAAA==.',Tt='Ttiyu:BAAALAAECgYICgAAAA==.',Tw='Twisty:BAAALAADCgQIBAAAAA==.Twîgg:BAAALAAECgYIBgAAAA==.',Uz='Uzi:BAAALAADCgMIAwAAAA==.',Va='Varei:BAAALAADCggIDwAAAA==.',Ve='Vedil:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.',Vi='Via:BAAALAADCggICAAAAA==.Victra:BAAALAADCgcIBwAAAA==.Vil:BAACLAAFFIEQAAIQAAYIAho4AABkAgAQAAYIAho4AABkAgAsAAQKgSAAAhAACAiCJpsAAIEDABAACAiCJpsAAIEDAAAA.',Vo='Voizu:BAAALAADCgYIBgAAAA==.',Wa='Warchicken:BAAALAADCggIDwABLAAECgQICAABAAAAAA==.',Wi='Wikeid:BAAALAADCgMIAwAAAA==.Willrut:BAAALAADCggIDwAAAA==.Withengar:BAAALAAECgYICwAAAA==.',Wo='Wonetime:BAAALAAECgIIAgAAAA==.',Wu='Wuuzzyy:BAAALAAECgUICAAAAA==.',Xa='Xaliko:BAAALAAECgYICAAAAA==.Xanbaran:BAAALAAECgcIEAAAAA==.Xandian:BAAALAAECgIIAgAAAA==.',Xe='Xen:BAAALAADCgcIDQAAAA==.Xenn:BAAALAADCgYIBAAAAA==.',Ya='Yami:BAAALAAECgEIAQAAAA==.',Yu='Yuki:BAAALAAECggIAwAAAA==.Yukki:BAAALAAECgIIAgAAAA==.',Za='Zaradinna:BAAALAAECgQIBAAAAA==.Zartenton:BAAALAADCgYIBgAAAA==.Zaylas:BAAALAAECgMIAwAAAA==.',Ze='Zerikai:BAAALAAECggIAgAAAA==.Zerivryn:BAAALAAECgYICgAAAA==.Zerkhaine:BAAALAAECgYICwAAAA==.',Zh='Zhevius:BAAALAADCggIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end