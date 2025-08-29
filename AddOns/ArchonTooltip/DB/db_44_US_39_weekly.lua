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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Mage-Arcane','Paladin-Protection','Shaman-Elemental','Shaman-Enhancement','Paladin-Retribution',}; local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aarronn:BAAALAADCgcIDQAAAA==.',Ak='Aksuna:BAAALAADCggIEAAAAA==.',Al='Alexie:BAAALAAECgUIBQAAAA==.Alleriand:BAAALAAECgQIBQAAAA==.Alndinda:BAAALAADCgcIBwAAAA==.',Am='Amboo:BAAALAADCgcIBwAAAA==.Ambulenz:BAAALAAECgEIAQAAAA==.Amuze:BAAALAADCggIBwAAAA==.',An='Andersdame:BAAALAAECgYICAAAAA==.',Ar='Arktyh:BAAALAAECgYICAAAAA==.Arkveld:BAAALAAECgEIAQAAAA==.Arkwin:BAAALAADCgYIBgAAAA==.',As='Asherah:BAAALAADCggICAABLAAECgYICwABAAAAAA==.Astkoozaa:BAAALAAECgIIAgAAAA==.Astártus:BAAALAAECgEIAQAAAA==.',At='Attincy:BAAALAADCggIEwAAAA==.',Au='Auphenix:BAAALAAECgEIAQAAAA==.Autumnwind:BAAALAAECgMICAAAAA==.',Av='Avianda:BAAALAADCgYIBgAAAA==.',Ay='Ayah:BAAALAADCggIDwAAAA==.Ayayrohn:BAAALAADCggICAAAAA==.Ayunathena:BAAALAAECgEIAQAAAA==.',Az='Azensetra:BAAALAADCggICAAAAA==.',Ba='Badger:BAAALAAECgEIAQAAAA==.Banchi:BAAALAAECgcICAAAAA==.Barbarus:BAAALAADCgQIBQAAAA==.Barnbek:BAAALAADCggIEgAAAA==.',Be='Beccky:BAAALAADCgcICgAAAA==.Beginners:BAAALAAECgMIAwAAAA==.Bevicia:BAAALAAECgMIAwAAAA==.',Bi='Bigdom:BAAALAAECgYICgAAAA==.Bitsotig:BAAALAADCgcICwAAAA==.Bituin:BAAALAADCgcIBwAAAA==.',Bl='Blaschko:BAAALAADCggIEQAAAA==.Bluelicht:BAAALAAECgMIBQABLAAECgYICgABAAAAAA==.Bluphantom:BAAALAAECgMIBQAAAA==.',Bo='Bodiddly:BAAALAADCgcICwAAAA==.Bonestorm:BAAALAADCggIFwAAAA==.Boodiica:BAAALAAECgYIBgAAAA==.',Br='Brazadin:BAAALAADCggIDAABLAAECgcIDgABAAAAAA==.Brazzclapz:BAAALAAECgcIDgAAAA==.',Bu='Bullybane:BAAALAADCgcIEwAAAA==.Bustie:BAAALAADCgYIBQAAAA==.',['Bû']='Bûbbles:BAAALAADCggICwAAAA==.',Ca='Calahunts:BAEBLAAECoEYAAICAAgI5h8CCADhAgACAAgI5h8CCADhAgAAAA==.Carwood:BAAALAADCgYIBgAAAA==.Catgirl:BAAALAAECgYICwAAAA==.Catßenatar:BAAALAAECgcIDgAAAA==.',Cd='Cdude:BAAALAADCgQIBAAAAA==.',Ch='Chadfrey:BAAALAADCgcIBwAAAA==.Chenna:BAAALAADCgIIAwAAAA==.Choppychoppy:BAAALAADCgUIBQAAAA==.Chrysostom:BAAALAAECgcIEAAAAA==.',Ci='Cindesera:BAAALAADCgcIBwAAAA==.',Cl='Clayne:BAAALAADCgIIAgAAAA==.Cloggy:BAACLAAFFIEFAAMDAAMICxlpAwARAQADAAMICxlpAwARAQAEAAEIgQO8DABIAAAsAAQKgR4ABAMACAgBJDkGAPICAAMACAjyITkGAPICAAUABQj+G1wJALUBAAQAAgiHJXksAMcAAAAA.',Co='Coeus:BAAALAADCgQIBAAAAA==.Colcupcake:BAAALAADCgMIAwAAAA==.',Cr='Crath:BAAALAAECgIIAgAAAA==.Crazyxgf:BAAALAADCgQIBAAAAA==.Crixo:BAAALAAECgYICQAAAA==.Crownlock:BAAALAAECgEIAQAAAA==.Crownpal:BAAALAADCgcIBwAAAA==.Crownwarrior:BAAALAAECgYIDQAAAA==.Cryptoid:BAAALAAECgIIAgAAAA==.',Da='Dairyairy:BAAALAAECgMIBQAAAA==.Dal:BAAALAAECgEIAQAAAA==.Dalinius:BAAALAAECgEIAQAAAA==.Datfourloko:BAAALAAECgQIBwAAAA==.Dazing:BAAALAAECgEIAgAAAA==.',Dd='Ddx:BAAALAAECgUIBgAAAA==.',De='Deadmeats:BAAALAADCgcIDQAAAA==.Deamontsuki:BAAALAADCggICAAAAA==.Deathpack:BAAALAAFFAIIAgAAAA==.Deedzy:BAAALAADCgYICAAAAA==.Denaian:BAAALAADCgQIBAAAAA==.Denerran:BAAALAADCgEIAQAAAA==.Despodia:BAAALAADCgcIDQAAAA==.Detazendezin:BAAALAADCgcIDQAAAA==.Detralan:BAAALAADCggICAAAAA==.',Do='Dotheal:BAAALAAECggIAQAAAA==.',Dr='Dragonduude:BAAALAADCggIDAAAAA==.Dragre:BAAALAADCgEIAQAAAA==.Draklord:BAAALAADCgEIAQAAAA==.Dromonid:BAAALAAECgYICgAAAA==.Droodar:BAAALAADCgcIBwAAAA==.Druaryaka:BAAALAAECgcICgAAAA==.',Du='Duckei:BAAALAAECgEIAQAAAA==.Duckywg:BAAALAAECgYICwAAAA==.Duplara:BAAALAADCggIEAAAAA==.',Ea='Earthman:BAAALAADCgEIAQAAAA==.',Ec='Eclipsea:BAAALAADCggIDgAAAA==.',El='Elorll:BAAALAADCgEIAQAAAA==.Elowensa:BAAALAADCgcICQAAAA==.',Er='Erzäscärlet:BAAALAADCggIBQAAAA==.',Ex='Exploits:BAAALAADCgcIDAAAAA==.',Fa='Faitalis:BAAALAADCgcIDAAAAA==.Fatboyheals:BAAALAADCgUIBQAAAA==.Faylith:BAAALAADCgIIAgAAAA==.',Fe='Feast:BAAALAADCgcIDAAAAA==.Fenster:BAAALAADCgQIBAABLAADCgYIBgABAAAAAA==.',Fi='Fichael:BAAALAADCgYIBgAAAA==.Fidodido:BAAALAADCgQIBAAAAA==.',Fl='Flandergoan:BAAALAADCgIIAgABLAADCgYIBgABAAAAAA==.Floofball:BAEALAADCgcIBwABLAAECggIGAACAOYfAA==.',Fo='Focaex:BAAALAADCggICAAAAA==.',Fr='Frostmageice:BAAALAADCggIDgAAAA==.Frosttdk:BAAALAAECgEIAQAAAA==.',Gi='Gilliam:BAAALAADCgUIBQAAAA==.Girthlock:BAAALAADCgMIAwABLAADCgcIDgABAAAAAA==.',Go='Goatfera:BAAALAADCgQIBQAAAA==.Gobbyfin:BAAALAAECgEIAgABLAAECgMIBQABAAAAAA==.Goofybot:BAAALAAECgUIDAAAAA==.Goofysensei:BAAALAADCgQIBAAAAA==.',Gr='Granbrigitte:BAAALAAECgEIAQAAAA==.Greenmonk:BAAALAAECgIIAgAAAA==.Gripreaper:BAAALAADCgYIDgABLAAECggIFwAGADsiAA==.',Gu='Guldandan:BAAALAADCgUIBQABLAADCgUICQABAAAAAA==.Gulugg:BAAALAADCgMIAwAAAA==.Gulycow:BAAALAAECgIIAgAAAA==.',['Gü']='Gümby:BAAALAADCgIIAgAAAA==.',Ha='Haddixbros:BAAALAAECgIIAgAAAA==.Hadean:BAAALAAECgEIAQAAAA==.Handieman:BAAALAADCgcIBwAAAA==.Hatheielion:BAAALAAECgEIAQAAAA==.Havocthree:BAAALAADCgcIDAAAAA==.Haztur:BAAALAADCggIDgAAAA==.',He='Headcheff:BAAALAADCggIEwAAAA==.Hearah:BAAALAAECgcIDQAAAA==.Hellz:BAAALAAECgcICgAAAA==.Hesum:BAAALAADCgYICwAAAA==.Hexeda:BAAALAADCgEIAQAAAA==.Hexkwondo:BAAALAADCggIDwAAAA==.',Hi='Hikari:BAAALAADCgcIDgAAAA==.Hiskitten:BAAALAADCggIEwAAAA==.',Ho='Holyfangs:BAAALAAECgIIAgAAAA==.Hondò:BAEBLAAECoEVAAIHAAgIYBqUFQBmAgAHAAgIYBqUFQBmAgAAAA==.Hondó:BAEALAAECgUIBgABLAAECggIFQAHAGAaAA==.Hondô:BAEALAAECgIIAgABLAAECggIFQAHAGAaAA==.',Hu='Hukmo:BAAALAADCgcICQAAAA==.Hunterzalt:BAAALAAECgYICwAAAA==.Huntrdvetmac:BAAALAADCgMIAwAAAA==.',Hy='Hybridmage:BAAALAADCggIFAAAAA==.',['Hô']='Hôndo:BAEALAADCgUIBQABLAAECggIFQAHAGAaAA==.',Il='Illidaria:BAAALAADCgUIBgAAAA==.',In='Incendio:BAAALAADCgcIDAAAAA==.Incision:BAAALAAECgEIAQAAAA==.',Is='Isellbodybag:BAAALAADCgcIBwAAAA==.',It='Ithrail:BAAALAAECgYIDAAAAA==.',Ja='Jaark:BAAALAADCgYIBgAAAA==.Jaldabaoth:BAAALAADCgIIAgAAAA==.Jarkevon:BAAALAAECgQIBAAAAA==.Jaywheezy:BAAALAADCgIIAgAAAA==.',Jd='Jdew:BAAALAAECgQIBQAAAA==.',Je='Jebidiáh:BAAALAADCgUIBQABLAADCggIDwABAAAAAA==.Jehon:BAAALAADCggICAAAAA==.',Jo='Jockster:BAAALAAECgIIAgAAAA==.Jonnywane:BAAALAADCgUIBQAAAA==.',Ju='Juann:BAAALAADCgcIBwAAAA==.Judgeandrson:BAAALAAECgMIAwAAAA==.Judinous:BAAALAAECgUICAAAAA==.Juggernåut:BAAALAADCgUIBQAAAA==.Julydie:BAAALAAECgIIAgAAAA==.Justfarmin:BAAALAADCgYIBgAAAA==.',Ka='Kaboria:BAAALAAECgYIBgAAAA==.Kaelthuss:BAAALAADCgUICQAAAA==.Kalross:BAAALAADCgQIBAAAAA==.Kalyia:BAAALAAECgEIAQAAAA==.Kataclyst:BAAALAAECgEIAQAAAA==.Kaîah:BAAALAAECgEIAQAAAA==.',Ke='Kekul:BAAALAADCggIFgAAAA==.Kelathia:BAAALAAECgEIAQABLAAFFAMIBQADAAsZAA==.Keukenhof:BAAALAAECgIIAgABLAAECgMIBQABAAAAAA==.Keygra:BAAALAAECgEIAQABLAAECgYICwABAAAAAA==.',Ki='Kicktell:BAAALAAECgMIAwAAAA==.Kilgust:BAAALAADCgQIBAAAAA==.Killnaenae:BAAALAAECggICAAAAA==.Kiyohimee:BAAALAADCggIEwAAAA==.',Ko='Kokobinks:BAEALAAECgYICAAAAA==.Konstentine:BAAALAAECgEIAQAAAA==.Korabakoki:BAAALAAECgMIBAAAAA==.Korik:BAAALAADCgYIDgAAAA==.Koryk:BAAALAADCgcICAAAAA==.',Kr='Krazazzle:BAAALAADCggIDgAAAA==.',Ky='Kylefasel:BAAALAADCgUIBQAAAA==.',['Ká']='Kátniss:BAAALAADCgIIAgAAAA==.',Le='Leafhound:BAAALAADCgcICQAAAA==.Legendrìser:BAAALAAECgYICwAAAA==.Leginge:BAAALAAECgYICQAAAA==.',Li='Lightfemboy:BAABLAAECoEXAAIIAAgIAScDAACwAwAIAAgIAScDAACwAwAAAA==.Lineofdeath:BAAALAADCggICAAAAA==.Lissandra:BAAALAADCgcIBwAAAA==.',Lo='Lobotomite:BAABLAAECoEXAAIGAAgIOyJ9BAAqAwAGAAgIOyJ9BAAqAwAAAA==.',Lu='Lucilight:BAAALAADCgYICwAAAA==.Lunza:BAAALAADCggICAAAAA==.',Ma='Magnusvll:BAAALAAECgIIAgAAAA==.Mandrei:BAAALAAECgEIAQAAAA==.Manøn:BAAALAAECgMIBAAAAA==.Masinverter:BAAALAAECgQICAAAAA==.Mastalys:BAEALAADCggIFgAAAQ==.Maudsham:BAABLAAECoEYAAMJAAgIfReAEABHAgAJAAgIeBWAEABHAgAKAAYIRBWoCQCIAQAAAA==.Maulerhylife:BAAALAADCgQIBAAAAA==.Mavet:BAAALAAECgYICwAAAA==.Mavina:BAAALAAECgcIDgAAAA==.Mazez:BAAALAAECgEIAQAAAA==.Mazrana:BAAALAADCggICAAAAA==.',Me='Meanju:BAAALAADCggICwAAAA==.Meatshieldz:BAAALAADCgcIDgAAAA==.Megalock:BAAALAAECgMIBQAAAA==.Meketek:BAAALAAECgYICgAAAA==.Melido:BAAALAADCgUIBgAAAA==.Meliretiera:BAAALAADCggIEAAAAA==.Mercymain:BAAALAADCgMIAwAAAA==.Mew:BAAALAADCgEIAQAAAA==.Mewow:BAAALAADCgcIBwAAAA==.',Mi='Mightylux:BAAALAAECgEIAQAAAA==.Mildo:BAAALAAECgMIBQAAAA==.Mindraka:BAAALAAECgQIBgAAAA==.Minervá:BAAALAAECgYICwAAAA==.Minotàurus:BAAALAAECgIIAgAAAA==.Mistis:BAAALAADCgcIBwAAAA==.',Mo='Moash:BAAALAADCggICAAAAA==.Mokama:BAAALAAECgUIBgAAAA==.Monstershi:BAAALAADCgcIBwAAAA==.Montbard:BAAALAADCgcIBwAAAA==.Moonlaser:BAAALAADCgcIBwAAAA==.Moopiehead:BAAALAADCgcIDgAAAA==.Mooserocka:BAAALAAECgEIAQAAAA==.Mooshroom:BAAALAADCgIIAgAAAA==.',My='Myrokorian:BAAALAAECgMIBAAAAA==.',['Mö']='Möngo:BAAALAADCgIIAgAAAA==.',Na='Narcissist:BAAALAAECgIIAgAAAA==.',Ne='Neaprogue:BAAALAAECggICAAAAA==.',Ni='Nightwind:BAAALAADCgcIBwAAAA==.',No='Notascalie:BAAALAADCgcIDQABLAAECggIFwAGADsiAA==.Notozxgnome:BAAALAADCgYICAAAAA==.Novavanna:BAAALAADCggIDAAAAA==.',Nu='Nubzy:BAAALAADCgEIAQAAAA==.',['Nò']='Nòte:BAAALAAECgEIAQAAAA==.',['Nø']='Nørb:BAAALAADCggIGAAAAA==.',Og='Oggon:BAAALAADCgEIAQAAAA==.',Ol='Olgalina:BAAALAADCggICAAAAA==.',On='Onlypi:BAAALAADCggIDwAAAA==.',Op='Opirix:BAAALAAECgQIBgAAAA==.Oppenheim:BAAALAAECgYIAwAAAA==.',Ou='Ouidufromage:BAAALAADCgYICAAAAA==.',Pa='Paddfoot:BAAALAADCgEIAQAAAA==.',Pe='Pepperss:BAAALAADCggIEAAAAA==.',Pi='Pinkbar:BAAALAADCgcIBwAAAA==.Piru:BAAALAADCgcIDAAAAA==.',Pj='Pjayylmao:BAAALAADCggIDwAAAA==.',Pl='Plus:BAAALAADCgcICwAAAA==.',Po='Popedk:BAAALAADCggICAAAAA==.',Pr='Presvyr:BAAALAADCgIIAgAAAA==.',Py='Pyrophobia:BAAALAAECgMIBAAAAA==.Pyytthonn:BAAALAAECgIIAgAAAA==.',Qi='Qincheng:BAAALAAECgEIAQAAAA==.',Qu='Quakedk:BAAALAAFFAIIAgAAAA==.Quiggins:BAAALAAECgMIBgAAAA==.',Ra='Raezor:BAAALAADCgYIBgAAAA==.Ragingfemboy:BAAALAADCggIDwAAAA==.Rainami:BAAALAADCggIEAABLAAECgQIBwABAAAAAA==.Rainiy:BAAALAAECgMIAwAAAA==.Rainyi:BAAALAADCgEIAQAAAA==.Razurel:BAAALAADCgEIAQAAAA==.',Re='Realmage:BAAALAADCgcIEwABLAAFFAIIAgABAAAAAA==.Reginald:BAAALAADCggIDAAAAA==.',Ri='Rizzlér:BAAALAADCggIDwAAAA==.',Ro='Rokyman:BAAALAAECgMIBAAAAA==.',Ry='Ryoko:BAAALAAECgYICAAAAA==.',Sa='Saelaida:BAAALAADCgEIAQAAAA==.Sagerin:BAAALAADCgcIBwAAAA==.Sageslife:BAAALAAECgEIAQAAAA==.Saintofthetp:BAAALAAECgYICQAAAA==.Sarifa:BAAALAAECgYICwAAAA==.',Sc='Scorz:BAAALAADCgYIBgAAAA==.Screamweaver:BAAALAAECgEIAQAAAA==.',Se='Selenecontes:BAAALAAECgYICwAAAA==.Selvina:BAAALAADCggIFAAAAA==.Serencio:BAAALAADCggICAAAAA==.',Sg='Sgæyl:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.',Sh='Shaboomboom:BAAALAAECgcIDQAAAA==.Shaemuss:BAAALAADCggIDwAAAA==.Shalai:BAAALAAECgYIBgAAAA==.Shaldonna:BAAALAADCggICAAAAA==.Shannii:BAAALAAECgYIBgAAAA==.Shew:BAAALAAECgEIAQAAAA==.Shewadin:BAAALAAECgEIAQAAAA==.Shewcifer:BAAALAADCgMIAwAAAA==.Shortcake:BAAALAADCgUIBQAAAA==.Shortstack:BAAALAADCgMIAwAAAA==.Shíkari:BAAALAAECgIIAgAAAA==.',Sk='Skanok:BAAALAAECgMIAwAAAA==.Skoria:BAAALAAECgIIAgAAAA==.Skybreaker:BAAALAADCgQIBAAAAA==.Skybri:BAAALAADCgcIDgAAAA==.',Sm='Smitten:BAAALAAECgQIBAAAAA==.',So='Soapydish:BAAALAAECgUICQAAAA==.Solrin:BAAALAADCgcICgAAAA==.Sookiez:BAAALAADCgMIAwAAAA==.',Sp='Splits:BAAALAADCggICAAAAA==.',St='Starfury:BAAALAAECgMIBAAAAA==.Starrscream:BAAALAAECggIBAAAAA==.Stazlol:BAAALAADCgMIAwAAAA==.Stazxd:BAAALAADCggIGwAAAA==.Stomach:BAAALAAECgMIAwAAAA==.Stormshade:BAAALAAECgIIAgAAAA==.Strikers:BAAALAADCggIDgAAAA==.Stunllub:BAAALAADCggIDAAAAA==.',Su='Suggs:BAAALAAECgcICQAAAA==.',Sy='Sydahlille:BAAALAADCgYICwAAAA==.Sydne:BAAALAADCggICwAAAA==.Sylvànis:BAAALAAECgYICAAAAA==.Synergistic:BAAALAADCggIDwAAAA==.Syoxx:BAAALAADCgQIBQAAAA==.',['Sø']='Sølara:BAAALAAECgEIAQAAAA==.',['Sú']='Súcubo:BAAALAAECgIIAgAAAA==.',Ta='Tabina:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Tairneañach:BAAALAAECgMIBAAAAA==.Tauriko:BAAALAAECgEIAQAAAA==.',Th='Theler:BAAALAADCggIEAABLAAFFAMIBQADAAsZAA==.Theradestria:BAAALAAECgEIAQAAAA==.',Ti='Tigerpaulm:BAAALAAECgYIBgAAAA==.Timmyjam:BAAALAAECgEIAQAAAA==.',Tr='Treeperson:BAAALAADCggICAAAAA==.Triquetra:BAAALAAECgIIAgAAAA==.Trokken:BAAALAAECgMIBQAAAA==.',Ud='Udderless:BAAALAAECgMIBgAAAA==.',Un='Understorm:BAAALAADCggIDgABLAADCggIFwABAAAAAA==.',Ur='Urgehal:BAAALAADCgUIBQAAAA==.',Va='Valdora:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.Vampyric:BAAALAADCggIFQAAAA==.Vampyrica:BAAALAADCgYIBgAAAA==.',Ve='Velro:BAABLAAECoEXAAICAAgIvSMrAgBPAwACAAgIvSMrAgBPAwAAAA==.Vexira:BAAALAADCggIFAAAAA==.',Vi='Vianir:BAAALAADCgcIDgAAAA==.Viroxar:BAAALAAECgEIAQAAAA==.Vivisheep:BAAALAADCgcIBwAAAA==.',Vl='Vlndeca:BAAALAADCgYICgAAAA==.',['Vê']='Vêxor:BAAALAAECgcIDAAAAA==.',Wa='Warryaka:BAAALAADCggIDAAAAA==.',We='Wels:BAAALAAECgMIBQAAAA==.',Wh='Whichwitch:BAAALAADCgQIBAAAAA==.Whisperlia:BAAALAAECgMIAwAAAA==.Whitejr:BAAALAAECgYIBgAAAA==.',Wi='Wigglypuffsr:BAAALAAECgYICgAAAA==.Wiggsmashedu:BAAALAADCgYIDAABLAAECgYICgABAAAAAA==.Wiikkid:BAAALAADCgcICgAAAA==.Winkbind:BAAALAADCggICAAAAA==.',Wl='Wll:BAAALAADCgQIBAAAAA==.',Wo='Wondrwoman:BAEALAADCggIEAAAAA==.',Xa='Xaclov:BAAALAAECgUIBQAAAA==.Xaeva:BAAALAADCgcIBwAAAA==.Xalcor:BAEALAAECgUIDQAAAA==.Xandea:BAAALAAECgIIAgAAAA==.',Xk='Xkatarina:BAAALAADCgIIAgAAAA==.',Xy='Xyform:BAAALAADCggIDwAAAA==.Xylotus:BAAALAAECgIIAgAAAA==.',Ya='Yahtzeé:BAAALAAECgcIEAAAAA==.',Yo='Yoshisune:BAAALAADCggIGAAAAA==.',Yu='Yujirø:BAAALAADCgYIDAABLAAFFAIIAgABAAAAAA==.Yuro:BAAALAADCgIIAgAAAA==.',Za='Zaffira:BAAALAAECgYICQAAAA==.Zanewindigar:BAAALAADCgIIAgAAAA==.Zatay:BAAALAAECgIIBAAAAA==.',Ze='Zedawg:BAAALAADCgMIAwAAAA==.Zeeluz:BAAALAADCgYIBgAAAA==.Zerrin:BAAALAADCgEIAQAAAA==.',Zi='Ziweix:BAAALAADCggICAAAAA==.',Zo='Zombae:BAAALAADCggICAAAAA==.Zonanta:BAAALAADCggIEQAAAA==.',Zu='Zukaris:BAAALAADCggIDwAAAA==.Zuulis:BAAALAADCgYIBgAAAA==.',Zy='Zyj:BAAALAADCggIFAAAAA==.',['Ås']='Åsher:BAAALAADCgEIAQABLAAECgcIFAALABAlAA==.',['Çé']='Çélädor:BAABLAAECoEUAAILAAcIECXACQDiAgALAAcIECXACQDiAgAAAA==.',['Ör']='Örin:BAAALAAECgQIBAAAAA==.',['ße']='ßeef:BAAALAADCgcIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end