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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Priest-Holy','DemonHunter-Havoc','Druid-Balance',}; local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abigail:BAAALAADCgMIBAABLAAECgYIBgABAAAAAA==.',Ad='Adorelle:BAAALAADCgMIAwAAAA==.',Ae='Aeryhnn:BAAALAADCgIIAgABLAADCgcIFQABAAAAAA==.',Ak='Akümä:BAAALAADCgcICgAAAA==.',Al='Albinodwarf:BAAALAADCggICAAAAA==.Aldêrstràsz:BAAALAAECgIIAgAAAA==.Alexandre:BAAALAAECgEIAgAAAA==.Alkaid:BAAALAADCgcIEQAAAA==.Allasia:BAAALAADCggIKQAAAA==.Alton:BAAALAADCgcICgABLAAECgEIAgABAAAAAA==.',An='Anamanahebo:BAAALAADCgMIAwAAAA==.Anaxunamoon:BAAALAADCgMIBAABLAAECgYIBgABAAAAAA==.Anduin:BAAALAADCgQIBQAAAA==.Annokan:BAAALAADCgcIBwABLAADCggIAQABAAAAAA==.',Ap='Apothecarie:BAAALAADCgcIDwABLAAECgYIBgABAAAAAA==.',Ar='Arokos:BAAALAADCgMIAwAAAA==.Arweni:BAAALAAECgYICgAAAA==.',As='Ashys:BAAALAADCgIIAgAAAA==.Asmirria:BAAALAADCggICAAAAA==.',Av='Avelios:BAAALAADCgcIEQAAAA==.',Az='Azog:BAAALAADCgUIBQAAAA==.',Ba='Babettee:BAAALAADCgcIEQAAAA==.',Be='Bearbacked:BAAALAAECgMIAwAAAA==.Beatingyews:BAAALAAECgMIBQAAAA==.Belashar:BAAALAADCgcIFQAAAA==.Beytuha:BAAALAAECgIIAgAAAA==.',Bl='Blacken:BAAALAAECgEIAQAAAA==.Blackknife:BAAALAAECgcICgAAAA==.Bladestorm:BAAALAADCgYIBgAAAA==.Blazen:BAABLAAECoEUAAICAAcI0CFnDACHAgACAAcI0CFnDACHAgAAAA==.Blinker:BAAALAAECgEIAQAAAA==.Bloodynuts:BAABLAAECoEVAAMDAAcItR6jAwAzAgADAAcIBx2jAwAzAgAEAAYI1hiFGgCoAQAAAA==.Bloodyzaz:BAEALAADCgcIBwABLAADCggIDgABAAAAAA==.Blurry:BAAALAAECgYICwAAAA==.Blütmaul:BAAALAADCgcIBwAAAA==.',Bo='Bobbidobby:BAAALAADCgUIBQABLAAECgcIFAAFADkTAA==.Bobbidyboo:BAABLAAECoEUAAIFAAcIORPKHgB1AQAFAAcIORPKHgB1AQAAAA==.Bonewing:BAAALAADCgQIBQAAAA==.Boomboompowa:BAAALAADCgcIBwAAAA==.',Br='Bristaa:BAAALAADCgMIAwAAAA==.',Bu='Buddydaelf:BAAALAAECgEIAQAAAA==.',Ca='Calion:BAAALAADCgcIBwAAAA==.Carduus:BAAALAADCgcICgABLAAECgEIAgABAAAAAA==.Cat:BAAALAAECgIIAgAAAA==.',Ch='Channese:BAAALAADCgUIBQAAAA==.Chastizer:BAAALAADCgEIAQAAAA==.Chillfang:BAABLAAECoEUAAIGAAcIaxrGCAAUAgAGAAcIaxrGCAAUAgAAAA==.Chitose:BAAALAADCggICAAAAA==.Chouji:BAAALAAECgMIBQAAAA==.',Cl='Cliff:BAAALAAECgEIAgAAAA==.',Co='Coldburn:BAAALAADCgIIAwAAAA==.',['Cê']='Cêlaçane:BAAALAADCggICQAAAA==.',Da='Dacianwolf:BAAALAADCggICAAAAA==.Dalliance:BAAALAAECgEIAgAAAA==.Daravinius:BAAALAAECgYIBgAAAA==.Darctiger:BAAALAADCgcIBwAAAA==.Dare:BAAALAAECgYIDgAAAA==.Darius:BAAALAADCgQIBAAAAA==.Darthleon:BAAALAADCgUIBQAAAA==.Daughter:BAAALAADCgMIAwAAAA==.Daveah:BAAALAADCggIEgAAAA==.Dayquil:BAAALAADCgEIAQAAAA==.Dayquîl:BAAALAADCgEIAQAAAA==.',De='Deathberry:BAAALAAECgEIAQAAAA==.Deeg:BAAALAAECgUIBQAAAA==.Delcynn:BAAALAAECgcIDQAAAA==.Demoncharge:BAAALAADCgcIEgAAAA==.Demonicablvd:BAAALAADCgcICgAAAA==.Denaeaa:BAAALAAECgEIAQAAAA==.Derecho:BAAALAAECggICAAAAA==.',Di='Discomingus:BAAALAAECgIIAgAAAA==.Dist:BAAALAADCggICAAAAA==.Divinestorm:BAAALAAECgYICQAAAA==.',Do='Dodgehoj:BAAALAADCgcIBwABLAAECgIIBAABAAAAAA==.Dodgysenpai:BAAALAAECgIIBAAAAA==.Donet:BAAALAADCggIAQAAAA==.Dotsy:BAABLAAECoEUAAMHAAcIlhULDQBsAQAIAAcIhxOyIACsAQAHAAYIUgsLDQBsAQAAAA==.',Dr='Drackarys:BAAALAADCgQIBAAAAA==.Dracon:BAAALAAECggIBwAAAA==.Dragonpower:BAAALAADCggIDwAAAA==.Dragooner:BAAALAAECgEIAgAAAA==.Drakiir:BAAALAADCgMIAwAAAA==.Drakkarnoir:BAAALAAECgIIAgABLAAECgcIEgABAAAAAA==.Dralkish:BAAALAAECgYICQAAAA==.Dramore:BAAALAADCggIDwAAAA==.Drascopes:BAAALAADCggICgAAAA==.Dravas:BAAALAAECgEIAgAAAA==.Droxx:BAAALAADCgMIAwAAAA==.Drzark:BAAALAADCgcIFAAAAA==.',Du='Duckmage:BAAALAAECgYIBgAAAA==.',['Dà']='Dàlamon:BAAALAADCgcIDQAAAA==.',Ea='Eagalis:BAAALAADCgcIBwAAAA==.',Ec='Echosmith:BAAALAADCgMIAwAAAA==.',Ed='Edaras:BAAALAAECgIIAgAAAA==.',Ef='Effrøn:BAAALAAECgUIBwAAAA==.',Ei='Eiadaa:BAAALAADCgQIBAAAAA==.Eilybellea:BAAALAADCgcIBwAAAA==.',El='Elennie:BAAALAAECgMIAwAAAA==.Elonoth:BAAALAADCggIDwAAAA==.',Em='Emelie:BAAALAADCgcIDQAAAA==.Emmi:BAAALAADCggIDwAAAA==.',Er='Erad:BAAALAADCgUIBQAAAA==.Erissa:BAAALAAECgIIAgAAAA==.',Ev='Evalani:BAAALAADCgcIEQAAAA==.Evilritê:BAAALAAECgEIAgAAAA==.Evilwhat:BAAALAADCgcIBwAAAA==.Evogos:BAAALAADCgcIBwAAAA==.',Fe='Fearmyhunter:BAAALAADCggIEAAAAA==.Felgercarb:BAAALAADCgYIDAABLAAECgYIBgABAAAAAA==.Feylen:BAAALAADCggIDwAAAA==.',Fi='Fido:BAAALAADCggICAAAAA==.Fifthelement:BAAALAAECgEIAgAAAA==.Figgy:BAAALAAECgMIAwAAAA==.',Fj='Fjalgeirr:BAAALAAECgEIAgAAAA==.',Fl='Flockling:BAAALAAECgcIDgAAAA==.',Fo='Foxymomma:BAAALAADCggIDwAAAA==.',Fr='Francine:BAAALAADCgYICAABLAAECgYIBgABAAAAAA==.Frankinsence:BAAALAAECgYIBgAAAA==.Freaksmash:BAAALAADCgYIBgAAAA==.Freydra:BAABLAAECoEUAAIJAAcI2SNBCwDLAgAJAAcI2SNBCwDLAgAAAA==.Friarfig:BAAALAADCgcIBwAAAA==.Friday:BAAALAADCgcICgAAAA==.Frierenn:BAAALAADCgcIDgAAAA==.Frßlizzard:BAAALAADCgUIBwAAAA==.',Fu='Fugazí:BAAALAADCggIEgAAAA==.',Ga='Gankak:BAAALAAECgEIAgAAAA==.',Ge='Gearsprocket:BAAALAAECgEIAgAAAA==.Geiste:BAAALAAECgcIDAAAAA==.',Gh='Ghue:BAAALAAECgMIBAAAAA==.',Gi='Gilalade:BAAALAADCggIDwAAAA==.Gilder:BAAALAADCgEIAQAAAA==.',Gn='Gnarlocks:BAAALAADCgcIEgAAAA==.Gnickabon:BAAALAADCgMIAwAAAA==.',Gr='Granny:BAAALAADCggICAAAAA==.Graywelcome:BAAALAAECgQIBAAAAA==.Grodin:BAAALAADCgcICgAAAA==.Grofiest:BAAALAAECgEIAgAAAA==.',Gw='Gwyne:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',['Gô']='Gôö:BAAALAAECgcIBwAAAA==.',Ha='Hadrian:BAAALAADCgMIAwAAAA==.Haldor:BAAALAADCggIEQAAAA==.Haohmaru:BAAALAADCggIDwAAAA==.',He='Hellhound:BAAALAADCgMIBgAAAA==.Herc:BAAALAAECgMIAwAAAA==.Hercgrim:BAAALAADCggIDQAAAA==.Hercsham:BAAALAADCgQIBAAAAA==.',Ho='Hollowknight:BAAALAADCggIDwAAAA==.Holy:BAAALAAECgQIBAAAAA==.Holydark:BAAALAAECgEIAQAAAA==.',Hu='Huneyhunter:BAAALAAECgEIAgAAAA==.',Ic='Ichigozero:BAAALAADCgIIAgAAAA==.',Il='Illimommy:BAAALAADCgIIAgAAAA==.',Im='Imagindragon:BAAALAADCgYICwAAAA==.',In='Intern:BAAALAAECgMIAwAAAA==.',Ir='Irrational:BAACLAAFFIEFAAIKAAMIHheQAgAPAQAKAAMIHheQAgAPAQAsAAQKgRwAAgoACAiOHy8HALkCAAoACAiOHy8HALkCAAAA.',Ja='Jaredius:BAAALAADCgcIDgAAAA==.Javeech:BAAALAADCggICgAAAA==.Jayse:BAAALAADCgEIAQAAAA==.',Je='Jeezus:BAAALAADCggIDgABLAAECgMIBAABAAAAAA==.Jeymi:BAAALAADCggIEAAAAA==.',Jo='Joole:BAAALAADCgUIBQABLAADCgcIFQABAAAAAA==.Joru:BAAALAAECgUICwAAAA==.Joust:BAAALAADCgQIBAAAAA==.',Jp='Jpitoo:BAAALAADCggICAAAAA==.',Ju='Junghee:BAAALAAECgcIDQAAAA==.Justìce:BAAALAADCggICAAAAA==.Juudaz:BAAALAAECgMIBAAAAA==.',Ka='Kaalorixa:BAAALAADCgcIBwAAAA==.Kabâhl:BAAALAADCgIIAgAAAA==.Kahboom:BAAALAADCggICgABLAAECgcIEgABAAAAAA==.Kahmara:BAAALAADCgYICgAAAA==.Kakahna:BAAALAADCggIDwAAAA==.Kaliista:BAAALAADCgIIAgABLAAECgEIAgABAAAAAA==.Kapkywa:BAAALAAECgQIBgAAAA==.Katsumyo:BAAALAADCgMIAwAAAA==.Katten:BAAALAADCgUIBAAAAA==.',Ke='Kellumin:BAAALAADCggICwAAAA==.',Ki='Kilra:BAAALAAECgEIAgAAAA==.Kirashiro:BAAALAADCgMIAwAAAA==.Kiyara:BAAALAAECgYIDAAAAA==.',Kl='Klungo:BAAALAAECgQIBAAAAA==.',Kn='Knotharsh:BAAALAADCgcICgAAAA==.Knowwn:BAAALAAECgEIAQAAAA==.',Ko='Korishi:BAAALAADCgcIBwAAAA==.',Kr='Krelliz:BAAALAAECgYICgAAAA==.Kroctdi:BAAALAAECgMIAwAAAA==.Kroot:BAAALAADCggICAAAAA==.Krystar:BAAALAADCgcIBwAAAA==.',Ku='Kungfuwho:BAAALAAECgcIEAAAAA==.Kutyou:BAAALAADCgIIAwAAAA==.',Ky='Kyríallé:BAAALAADCgcICgAAAA==.',La='Laysee:BAAALAAECgIIAgAAAA==.',Le='Leifreid:BAAALAAECgcIEAAAAA==.',Li='Lich:BAAALAADCggIEQAAAA==.Liesta:BAAALAADCgcICgAAAA==.Lightrawne:BAAALAADCgcIDgAAAA==.Liiege:BAAALAADCggIEgAAAA==.Linkzero:BAAALAADCggIDQAAAA==.Literedor:BAAALAADCgcIBwAAAA==.',Lo='Lobø:BAAALAAECgEIAgAAAA==.Loganx:BAAALAAECgMIAwAAAA==.Lonchaneyjr:BAAALAAECgYICQAAAA==.',Lu='Luccyy:BAAALAADCggIDwAAAA==.Lucifarlux:BAAALAADCgQIBQAAAA==.Lunatyc:BAAALAAECgUICAAAAA==.Luth:BAAALAADCgMIAwAAAA==.Luthx:BAAALAADCgcIBwAAAA==.',Ma='Maalli:BAAALAAECgIIAgAAAA==.Magestaff:BAAALAADCgcIDAABLAAECgMIAwABAAAAAA==.Magnoliá:BAAALAADCggICwAAAA==.Magnues:BAAALAADCggICAAAAA==.Magnuscaller:BAAALAADCgcIEwAAAA==.Mammal:BAAALAAECgEIAQAAAA==.Mateuszczyk:BAAALAAECgMIBgAAAA==.Mavas:BAAALAADCgcIBwAAAA==.',Mc='Mccruel:BAAALAAECgMIAwAAAA==.',Me='Megaera:BAAALAAECgcIEAAAAA==.Melar:BAAALAAECgMIBgAAAA==.Meliriir:BAAALAADCggICQAAAA==.Mentoku:BAAALAAECgYICgAAAA==.Messmer:BAAALAADCgcIDAAAAA==.',Mi='Minjae:BAAALAADCgcIEQAAAA==.',Mo='Moarwurk:BAAALAADCgcIEAABLAAECgYIBgABAAAAAA==.Moondemon:BAAALAADCgQIBAAAAA==.Mortipherus:BAAALAAECgMIBAAAAA==.Mosslillie:BAAALAADCgQIBQAAAA==.Movack:BAAALAAECgIIAwAAAA==.',Mu='Murderface:BAAALAADCggIDgAAAA==.',My='Mythirathdas:BAAALAADCgQIBAAAAA==.Mythunran:BAAALAAECgMIAwAAAA==.',['Mö']='Mörderfuchs:BAAALAADCgIIAgAAAA==.',Na='Natalina:BAAALAADCggIFAABLAAECgMIAwABAAAAAA==.Nawan:BAAALAADCggIEAAAAA==.',Ne='Nerol:BAAALAAECgYICQAAAA==.Nessalove:BAABLAAECoEUAAIKAAcISQjeKgBRAQAKAAcISQjeKgBRAQAAAA==.',Ni='Niixilaenos:BAAALAADCgQIBAAAAA==.',No='Nocte:BAAALAAECgEIAgAAAA==.Noleavesforu:BAAALAAECgMIBQAAAA==.Noone:BAAALAAECgcIDQAAAA==.Norm:BAAALAADCgMIAwAAAA==.Nostradamos:BAAALAADCgMIAwAAAA==.Noyoudidnt:BAAALAADCgEIAQAAAA==.',Nu='Numbnutts:BAAALAADCgcIDQAAAA==.',Nz='Nz:BAAALAADCgMIAwAAAA==.',Ol='Olina:BAAALAADCgcIDAAAAA==.',Or='Orajel:BAAALAADCgYIBgAAAA==.Orfantal:BAAALAAECgUICAAAAA==.Orrion:BAAALAAECgcIEgAAAA==.',Ov='Overburned:BAAALAADCgcICQAAAA==.Overshoot:BAAALAAECgEIAQAAAA==.',Ox='Oxen:BAAALAADCgEIAQAAAA==.',Pa='Paancakes:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Panterion:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.Papagayo:BAAALAADCgMIAwAAAA==.Parvarti:BAAALAADCgcIFQAAAA==.',Pe='Peachringz:BAAALAAECgMIAwAAAA==.Pennelope:BAAALAADCgcIDAABLAAECgYIBgABAAAAAA==.Penthesileia:BAAALAADCgQIBAABLAADCgcIBwABAAAAAA==.Persimmoñ:BAAALAADCggIEgAAAA==.Perveemonk:BAAALAADCggIEgAAAA==.',Ph='Phillard:BAAALAADCgQICAAAAA==.Phunbagz:BAAALAAECgIIAgAAAA==.',Po='Pokeranger:BAAALAADCgYICQAAAA==.',Pr='Prunhian:BAAALAADCgMIAwAAAA==.',Py='Pyroblast:BAAALAAECgYIBgAAAA==.',['Pá']='Pándaid:BAAALAAECgMIBAAAAA==.',['Pè']='Pèstilence:BAAALAADCggIFAAAAA==.',Ra='Rafaam:BAAALAADCgYIBgAAAA==.Rational:BAAALAAECgYIBwABLAAFFAMIBQAKAB4XAA==.',Re='Reladin:BAAALAADCggIDwAAAA==.Relanna:BAAALAADCggIDwAAAA==.Rend:BAAALAAECgEIAgAAAA==.Rendstein:BAAALAADCgcIBwAAAA==.Renzr:BAAALAAECgQIBgAAAA==.Revzxy:BAACLAAFFIELAAILAAUIBBmmAAD+AQALAAUIBBmmAAD+AQAsAAQKgRkAAgsACAjAJlQAAJQDAAsACAjAJlQAAJQDAAAA.Rexionien:BAAALAADCgcIBwAAAA==.',Rh='Rhöwdy:BAAALAADCgYIBgAAAA==.',Ri='Ridiknight:BAAALAAECgIIAgAAAA==.Rivalton:BAAALAADCgEIAQAAAA==.',Ro='Rojiee:BAAALAADCgEIAQAAAA==.',Ru='Ruddervator:BAAALAADCgUIBQAAAA==.',Ry='Ryougo:BAAALAAECgIIAQAAAA==.',Sa='Sajal:BAAALAADCggICAAAAA==.Saltdisney:BAAALAAECgMIAwAAAA==.Sansara:BAAALAADCgUIBQABLAADCgcIFQABAAAAAA==.Saristelonio:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Saristrix:BAAALAAECgMIAwAAAA==.Sarnara:BAAALAAECgEIAgABLAAECgIIAgABAAAAAA==.Sathin:BAAALAADCgIIAgAAAA==.',Sc='Scarlit:BAAALAADCggIDwAAAA==.',Se='Secord:BAAALAAECgEIAQAAAA==.Selacia:BAAALAADCgcIDQAAAA==.Selfless:BAAALAAECgcIDgAAAA==.',Sh='Shamalicous:BAAALAADCgEIAQAAAA==.Shamberries:BAAALAADCgcIEgAAAA==.Shanti:BAAALAADCgIIAgABLAADCgcIFQABAAAAAA==.Sharie:BAAALAAECgYIEgAAAA==.Shawnsetgo:BAAALAADCggIBwAAAA==.Shortwide:BAAALAADCgMIBgAAAA==.',Sk='Skolden:BAAALAADCgcIBwAAAA==.',Sl='Slumpik:BAAALAAECgQIBwAAAA==.Slÿ:BAAALAADCgQIBAAAAA==.',Sm='Smutbutt:BAAALAAECgcICgAAAA==.',Sn='Snitsky:BAAALAADCgIIAgAAAA==.',So='Soülcatcher:BAAALAADCgcIBwAAAA==.',Sp='Sparta:BAAALAADCggICAAAAA==.Spiced:BAACLAAFFIEFAAIMAAMI4h8sAQAgAQAMAAMI4h8sAQAgAQAsAAQKgRcAAgwACAjuJcMBAFMDAAwACAjuJcMBAFMDAAAA.Splort:BAAALAADCgcIBwAAAA==.',St='Steakx:BAAALAADCgcIBwAAAA==.Sthauria:BAAALAADCgcICQAAAA==.Stormfront:BAAALAAECgEIAQAAAA==.',Su='Sunshinebear:BAAALAADCgYIBgAAAA==.Suriel:BAAALAADCgcIFQAAAA==.',Sv='Svenya:BAAALAAECgEIAgAAAA==.',Sy='Sygne:BAAALAADCgcIBwAAAA==.',Sz='Szell:BAAALAADCggIEgAAAA==.',['Së']='Sëkhmët:BAAALAADCgcICgABLAAECgIIAgABAAAAAA==.',['Sï']='Sïrius:BAAALAAECgIIBAAAAA==.',Ta='Taggy:BAAALAAECgMIBAAAAA==.Tassandie:BAAALAAECgEIAgAAAA==.',Te='Terribleteri:BAAALAADCgMIAwAAAA==.',Th='Thansus:BAAALAAECgYICQAAAA==.Thiccum:BAAALAAECgMIBQAAAA==.Thrallsclàss:BAAALAADCggIDwAAAA==.Thursday:BAAALAADCgYICAAAAA==.',Ti='Tightwad:BAAALAADCgcICgABLAAECgYIBgABAAAAAA==.Tinthe:BAAALAADCgcIDQAAAA==.Tinyrawr:BAAALAADCgYIBgAAAA==.Tinytrapper:BAAALAADCggIDwAAAA==.Tionie:BAAALAAECgUIBgAAAA==.',To='Toiletnuker:BAAALAADCggIEAAAAA==.Tokyojoe:BAAALAAECgIIAgAAAA==.Torrick:BAAALAAECgUIBQAAAA==.Totemtot:BAAALAADCggIDwAAAA==.Toupee:BAAALAADCgQIBAAAAA==.',Tr='Traza:BAAALAADCgcIBwAAAA==.Trixibolt:BAAALAADCggIDwAAAA==.',Ty='Tyr:BAAALAAECgQIBAAAAA==.',Uc='Ucee:BAAALAAECgMIBAAAAA==.',Uf='Uffizzle:BAAALAADCgEIAQAAAA==.',Ul='Ulf:BAAALAAECgUIDQAAAA==.',Va='Valquirie:BAAALAAECgIIAgAAAA==.Varlamor:BAAALAAECgEIAQAAAA==.',Ve='Velanistra:BAAALAADCggIFgAAAA==.Velanthus:BAAALAADCgQIBgAAAA==.Velerestus:BAAALAADCggIFwAAAA==.Velnia:BAAALAAECgEIAQAAAA==.Vend:BAAALAADCgIIAgAAAA==.Vervane:BAAALAAECgEIAQAAAA==.Vesper:BAAALAADCggIEgABLAAECgMIBAABAAAAAA==.',Vg='Vgerr:BAAALAAECgIIAgAAAA==.',Vi='Vidarus:BAAALAADCggICAABLAAECgcIEgABAAAAAA==.',Vj='Vjango:BAAALAADCgcIBwAAAA==.',Vo='Vohu:BAAALAAECgEIAgAAAA==.Voidenai:BAAALAADCgMIAwAAAA==.',Vy='Vynesh:BAAALAAECgEIAQAAAA==.Vynos:BAAALAADCgQIBQAAAA==.',Wa='Waterlily:BAAALAAECgIIAgAAAA==.',We='Weathervein:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.',Wh='Whispie:BAAALAADCgMIAwAAAA==.',Wi='Windeyaho:BAAALAAECgMIAwAAAA==.Withcheeze:BAAALAADCgIIAgAAAA==.',Wo='Wolfman:BAAALAAECgIIAgAAAA==.',Xd='Xdrchaos:BAAALAAECgcIEQAAAA==.',Xe='Xechom:BAAALAAECgEIAQAAAA==.',Xt='Xten:BAAALAADCgcIFQAAAA==.',Yo='Yoshinox:BAAALAADCgcIBwAAAA==.',Yt='Ytee:BAAALAADCgYIBgAAAA==.',Za='Zathen:BAAALAADCggIDwAAAA==.Zazuba:BAEALAADCggIDgAAAA==.',Ze='Zelliph:BAAALAADCgcIBwAAAA==.Zenagdrina:BAAALAAECgIIAwAAAA==.Zenatra:BAAALAAECgIIAgAAAA==.Zenobiå:BAAALAADCgYIBgAAAA==.Zerodraco:BAAALAADCgYIBwAAAA==.Zeroheals:BAAALAADCggIDgAAAA==.Zeropower:BAAALAADCgMIAwAAAA==.Zerowolf:BAAALAAECggIBQAAAA==.',Zh='Zhaann:BAAALAADCgcIFQAAAA==.',['Îi']='Îi:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end