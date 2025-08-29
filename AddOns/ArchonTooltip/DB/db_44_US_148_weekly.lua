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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost','Priest-Shadow','Warrior-Fury','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','Hunter-BeastMastery','Monk-Mistweaver','Shaman-Elemental','Druid-Restoration','DemonHunter-Vengeance','Shaman-Enhancement','Shaman-Restoration','Druid-Balance','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Monk-Windwalker',}; local provider = {region='US',realm='Magtheridon',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Addelina:BAAALAADCgUIBQAAAA==.',Ak='Akulagos:BAAALAADCgMIAwAAAA==.Akunzed:BAAALAADCgMIAwAAAA==.',Al='Alii:BAAALAADCggIDwAAAA==.Allen:BAAALAADCggIFAAAAA==.Allnutnosup:BAAALAADCggICAAAAA==.Alondra:BAAALAADCgcIDgAAAA==.',Am='Amythistle:BAAALAAECgIIAgAAAA==.',An='Andrü:BAAALAAECgYICQAAAA==.',Ap='Applefritter:BAAALAADCggICAAAAA==.',Ar='Archimainos:BAAALAAECgYIBQAAAA==.Arnblass:BAAALAAECgYICgAAAA==.',As='Asclepiùs:BAAALAADCgcIDQAAAA==.Ashellestana:BAAALAAECgYICwAAAA==.Ashgarn:BAAALAADCgcIBwAAAA==.Asiago:BAAALAAECgYICQAAAA==.',Au='Augthyr:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.Aurius:BAAALAAECgEIAQAAAA==.',Av='Avalen:BAAALAAECgUIDQAAAA==.Aviee:BAAALAAECgYIDAAAAA==.Avishun:BAAALAADCgYIBwAAAA==.Avreel:BAAALAAECgIIAgAAAA==.',Az='Azazi:BAABLAAECoEWAAICAAgIvCWnAgBNAwACAAgIvCWnAgBNAwAAAA==.Azgul:BAAALAADCgMIAwAAAA==.Azoozu:BAAALAAECgIIBAAAAA==.',['Aå']='Aåaåaåaåaåaå:BAAALAADCgUIBwAAAA==.',Ba='Baced:BAAALAAECgYICgAAAA==.Baendron:BAAALAAECgYICQAAAA==.Bahnna:BAAALAAECgIIAwAAAA==.Bakaris:BAAALAAECgMIAwAAAA==.Balavan:BAEALAAECgYICQAAAA==.Barbarik:BAAALAAECgYICAABLAAECggIEAABAAAAAA==.Baretwallace:BAAALAAECgMIAwAAAA==.Bayesian:BAAALAADCgEIAQAAAA==.',Be='Beefwildfire:BAAALAADCgYIBgAAAA==.Belle:BAAALAADCgYIBgAAAA==.',Bi='Bigdady:BAAALAAECgMIAwAAAA==.',Bl='Blackbolt:BAAALAAFFAIIAwAAAA==.Blindeye:BAAALAADCgQIBAAAAA==.Blorgin:BAABLAAECoEYAAMDAAgIPiE4CgCCAgADAAcIfx84CgCCAgAEAAII8hyTEACeAAAAAA==.Blínk:BAAALAADCggICAAAAA==.',Bo='Bobsalami:BAABLAAECoETAAIFAAcIWx5uFABeAgAFAAcIWx5uFABeAgAAAA==.Boofing:BAAALAADCgQIBAAAAA==.Bookers:BAAALAAECgYIBgAAAA==.Boulangerie:BAABLAAECoEXAAIGAAgIISbAAQBZAwAGAAgIISbAAQBZAwAAAA==.Boulezen:BAAALAAECgMIBAAAAA==.Boyd:BAABLAAECoEWAAIHAAgIlBwwDACfAgAHAAgIlBwwDACfAgAAAA==.',Br='Brodir:BAAALAAECgYICAAAAA==.',Bu='Bu:BAAALAADCgYIBgAAAA==.Bundunshammy:BAAALAAECgUIBQAAAA==.',Bw='Bwansamdi:BAAALAAECgYICQAAAA==.',Ca='Cactpus:BAAALAADCgcICgAAAA==.Cainpain:BAABLAAECoEYAAIIAAgI6iBcBAD2AgAIAAgI6iBcBAD2AgAAAA==.Canadatrash:BAAALAADCggICgABLAAECgMIAwABAAAAAA==.',Ce='Ceasarsalad:BAABLAAECoEWAAIJAAgIYxlqDwBZAgAJAAgIYxlqDwBZAgAAAA==.Ceazitt:BAAALAAECgYICgAAAA==.Celestriå:BAAALAAECgIIAwAAAA==.',Ch='Chadlockb:BAACLAAFFIEFAAMKAAMIEBnqAQDAAAAKAAII9h3qAQDAAAAJAAEIQg+ODQBYAAAsAAQKgRgABAoACAgtJqgDADwCAAoABgiaJqgDADwCAAsABQjMFzkKAKMBAAkAAwjBI9AyACUBAAAA.Cheesee:BAAALAAECgYICgAAAA==.Chewbarka:BAAALAAECgEIAQAAAA==.Chithor:BAAALAADCgYICgAAAA==.Cholo:BAAALAAECgEIAQAAAA==.Chronite:BAAALAAECgMIBAAAAA==.Chuffy:BAAALAAECgIIBAAAAA==.',Ci='Cindr:BAABLAAFFIEFAAIMAAMIRBkdAgAWAQAMAAMIRBkdAgAWAQAAAA==.',Co='Codys:BAABLAAECoEXAAMNAAgIsCMxAgASAwANAAgIsCMxAgASAwACAAIILwZ7cAA5AAAAAA==.Colddblooded:BAAALAADCgcICwAAAA==.Cololol:BAABLAAECoEbAAIOAAgI/yWHAQByAwAOAAgI/yWHAQByAwAAAA==.Compcomp:BAAALAAECgIIAgAAAA==.Compensating:BAAALAAECgEIAQAAAA==.Cooper:BAAALAAECgYICQAAAA==.Coronaplague:BAAALAADCgcIDgAAAA==.Cosmos:BAAALAAECgYICQAAAA==.Courodyne:BAAALAADCggICwAAAA==.',Cr='Crispylol:BAAALAADCggICAAAAA==.Crucious:BAAALAAECgEIAQAAAA==.',Cu='Cucokai:BAAALAAECgUICgAAAA==.Cuddlekaren:BAAALAAECgYIBgABLAAFFAMIBQAIAGwJAA==.Cuddlestomp:BAACLAAFFIEFAAIIAAMIbAmRAwDBAAAIAAMIbAmRAwDBAAAsAAQKgRcAAwgACAiXIj8FAN8CAAgACAg4Ij8FAN8CAA8AAgjNEP5aAIkAAAAA.',Cy='Cyndor:BAABLAAECoEWAAIMAAgIwhyqBwCuAgAMAAgIwhyqBwCuAgAAAA==.',['Cä']='Cämulos:BAAALAADCggIEAAAAA==.',['Cø']='Cøsmos:BAAALAADCggIEAAAAA==.',Da='Daemivn:BAAALAAECgEIAQAAAA==.Daki:BAAALAADCgcIBwAAAA==.Damntehdy:BAAALAADCggIEAABLAAECggIFAAGAL8MAA==.Dandie:BAAALAAECgEIAQAAAA==.Dantalian:BAAALAADCggIEAABLAAECggIFAANAEgdAA==.Darthmerlin:BAAALAAECgQIBQAAAA==.Darthpanda:BAAALAADCgUIBQABLAAECgQIBQABAAAAAA==.Dasmango:BAAALAADCggIEAABLAAECggIFAAQALgRAA==.Dasmonko:BAABLAAECoEUAAIQAAgIuBFrCwDeAQAQAAgIuBFrCwDeAQAAAA==.',Db='Dbowzerz:BAAALAADCggIEQAAAA==.',De='Deblacksheep:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.Deladeus:BAAALAADCggICAABLAAECggIFgAMAMIcAA==.Deming:BAAALAADCgYIBgAAAA==.Demonlock:BAAALAADCgcIBwAAAA==.Demontim:BAAALAAECgEIAQAAAA==.Descend:BAAALAADCggIEAAAAA==.Destroyifier:BAAALAADCgIIAgAAAA==.',Dh='Dhsil:BAAALAAECggIAQAAAA==.',Dj='Djavol:BAABLAAECoEUAAIOAAgImhdcGQAyAgAOAAgImhdcGQAyAgAAAA==.',Dn='Dnok:BAAALAAECgIIAQAAAA==.',Do='Doomfury:BAAALAAECgMIAwAAAA==.Dotsfired:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.',Dr='Dragonlord:BAAALAAECgYICQAAAA==.Drankincup:BAABLAAECoEcAAIRAAgIKCThAgBGAwARAAgIKCThAgBGAwAAAA==.Dredd:BAAALAADCgcICgAAAA==.Dreyahh:BAAALAAECgYICgAAAA==.Drinkinmycup:BAAALAAECgYIBgABLAAECggIHAARACgkAA==.Dropchannel:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.Drstagger:BAEALAAECgYICAAAAA==.',Du='Dumping:BAAALAAECgMIBAAAAA==.Duskflower:BAABLAAECoEWAAISAAgIlRotCgBVAgASAAgIlRotCgBVAgAAAA==.Duzahl:BAAALAADCgMIAgAAAA==.',El='Elementors:BAAALAAECgQIBQAAAA==.Elfarmer:BAAALAADCgIIAgAAAA==.Elleri:BAAALAADCgcICAAAAA==.',Ep='Epnodk:BAAALAAECgYIBgABLAAFFAIIAwABAAAAAA==.Epnopal:BAAALAAFFAIIAwAAAA==.',Er='Error:BAAALAADCggIFQAAAA==.',Es='Esp:BAAALAADCgcIBwAAAA==.',Ev='Evarielle:BAAALAADCggICAABLAAECggIFgAMAMIcAA==.Evictally:BAAALAADCgcICQABLAAECgUIBQABAAAAAA==.',Fa='Falaya:BAABLAAECoEWAAIJAAgI6SQQAwA3AwAJAAgI6SQQAwA3AwAAAA==.Faldain:BAABLAAECoEUAAIHAAcIOCTECADcAgAHAAcIOCTECADcAgAAAA==.Falst:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.',Fe='Fenntard:BAAALAADCgQIBAAAAA==.Fersos:BAAALAADCgYICQAAAA==.',Fi='Fie:BAAALAAECgYICAAAAA==.Fis:BAABLAAECoEUAAIFAAgI7iPnAwA2AwAFAAgI7iPnAwA2AwAAAA==.',Fl='Fluffed:BAEALAAECgYICgABLAAFFAMIBQATAEEQAA==.Flyntflosy:BAABLAAECoEWAAIRAAgIDxuBDgBkAgARAAgIDxuBDgBkAgAAAA==.',Fr='Fragment:BAAALAAECgMIAwAAAA==.Frozoevoko:BAAALAAECgYICQAAAA==.',Fu='Furyess:BAAALAADCgMIAwAAAA==.',Ga='Garolok:BAAALAAECgYICQAAAA==.Gazeraelia:BAAALAADCggIDgABLAAECgcIEAABAAAAAA==.Gazerakhan:BAAALAADCgcICAABLAAECgcIEAABAAAAAA==.Gazerielle:BAAALAAECgcIEAAAAA==.',Gh='Ghaanfel:BAAALAADCgcIBwAAAA==.Ghaanplague:BAAALAAECgYICgAAAA==.',Gi='Gingerbelly:BAAALAADCgYICwAAAA==.Ginthril:BAAALAADCggIDAABLAAECgYIBgABAAAAAA==.',Gl='Glizzydizzy:BAAALAADCggIEAAAAA==.Glizzylizzy:BAABLAAECoEUAAIUAAgI+xzTAQDdAgAUAAgI+xzTAQDdAgAAAA==.',Go='Goldilockes:BAAALAADCggIDwAAAA==.Goodluck:BAAALAAECgIIAgABLAAECggIFgAVANIiAA==.Gotrek:BAAALAADCgQICAAAAA==.Gouttoes:BAAALAADCgUIBQAAAA==.Gowownage:BAABLAAECoEUAAISAAgI5CH6AQAGAwASAAgI5CH6AQAGAwAAAA==.',Gr='Gradius:BAAALAAFFAIIAgAAAA==.Graedeus:BAAALAAECgMIBAABLAAFFAIIAgABAAAAAA==.Graydius:BAAALAAECgYIBgAAAA==.Greenchips:BAAALAAECgEIAQAAAA==.Greenhoof:BAAALAAECgIIAwAAAA==.Greenmango:BAABLAAECoEUAAIWAAgIsBW2DgA9AgAWAAgIsBW2DgA9AgAAAA==.Grel:BAAALAADCgIIAgAAAA==.Groovy:BAAALAAECgEIAQAAAA==.',Gu='Gulltherizul:BAAALAADCgMIBgAAAA==.',['Gø']='Gøøn:BAAALAAECgMICQAAAA==.',Ha='Hadris:BAAALAADCgcIBwAAAA==.Halestorm:BAAALAADCggIFgAAAA==.Halk:BAABLAAECoEXAAIHAAgIPhnRDwBkAgAHAAgIPhnRDwBkAgAAAA==.Havefun:BAABLAAECoEWAAIVAAgI0iIdAwDwAgAVAAgI0iIdAwDwAgAAAA==.',He='Hecachire:BAAALAAFFAIIBAAAAA==.Hellafyre:BAAALAAECgEIAQAAAA==.Hellquack:BAAALAAECgMIBAAAAA==.',Hi='Hijikata:BAAALAAECgIIAgAAAA==.Hinoka:BAAALAADCgIIAgAAAA==.',Ho='Holyblake:BAAALAAECgMIBAAAAA==.Holydoyle:BAAALAAECgIIBAAAAA==.Hotpøcket:BAABLAAECoEWAAMSAAgIsR1aBwCAAgASAAgIsR1aBwCAAgAWAAEI9g44RwA+AAAAAA==.Howdyhoe:BAAALAADCgUIBQABLAADCgYIBgABAAAAAA==.',Hu='Hueymagoo:BAAALAADCgcICQAAAA==.Hugecheeks:BAAALAAECgUIBwAAAA==.',Hy='Hyperìen:BAABLAAECoEXAAIXAAgIMiU1AgBlAwAXAAgIMiU1AgBlAwAAAA==.',Ia='Iampro:BAABLAAECoEUAAMGAAgIex8vBwDgAgAGAAgIex8vBwDgAgAYAAIIzyANQQCyAAAAAA==.Iax:BAAALAADCgYIBwAAAA==.',Ig='Ignia:BAAALAAECgcIDQAAAA==.',Im='Immortalmage:BAAALAADCgEIAQAAAA==.',In='Indeed:BAAALAADCgEIAQABLAADCggIDQABAAAAAA==.Inferna:BAAALAAECgEIAQAAAA==.Inferno:BAAALAAECgMIAwAAAA==.Invisibul:BAAALAADCggICAAAAA==.',Ir='Irbaboon:BAAALAAECgYICwABLAAECgYIEgABAAAAAA==.',It='Itsevokernow:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.Itsovernow:BAAALAAECgIIAgAAAA==.',Iv='Ivermectin:BAAALAADCgQIBAAAAA==.',Ja='Jacosta:BAAALAAECgQICgAAAA==.Jal:BAABLAAECoEXAAIGAAgIlx62CQCtAgAGAAgIlx62CQCtAgAAAA==.Jamgirl:BAAALAAECgYIBgAAAA==.Jampu:BAAALAADCgcIBwAAAA==.Jangokin:BAABLAAECoEXAAIWAAgIRyKiBQDyAgAWAAgIRyKiBQDyAgAAAA==.',Je='Jebkúsh:BAAALAADCgIIAgAAAA==.Jellybely:BAAALAAECgMIAwAAAA==.',Ji='Jill:BAAALAADCgcIEAAAAA==.Jinks:BAAALAAECgEIAQAAAA==.',Jo='Joelrobuchon:BAAALAAECgIIAgAAAA==.Jormungandr:BAAALAAECgIIBAAAAA==.',Ju='Juffpiggly:BAAALAAECgIIAgAAAA==.',['Jí']='Jím:BAAALAAECgYICQAAAA==.',Ka='Kaeris:BAAALAAECgcIDgAAAA==.Kaige:BAAALAAECgMIAwAAAA==.Kalerõn:BAAALAAECgEIAQAAAA==.Kaltuk:BAAALAADCggIDQAAAA==.Katastrophik:BAAALAAECgcICgAAAA==.Kathery:BAAALAADCgcIBwAAAA==.Kazhunter:BAAALAADCgYIBwAAAA==.',Ke='Kellandron:BAAALAADCgQIBAABLAADCgYIBgABAAAAAA==.Kellwildfire:BAAALAAECgYICAAAAA==.',Kh='Khamael:BAABLAAECoEUAAINAAgISB1OBgB5AgANAAgISB1OBgB5AgAAAA==.Kharazumi:BAAALAADCggIEgAAAA==.Kheiron:BAAALAAECgYIEgAAAA==.',Ki='Killbot:BAAALAADCgQIBAAAAA==.Killbotmad:BAAALAADCgIIAgAAAA==.Kinu:BAAALAAECgcIDAAAAA==.Kitane:BAAALAAECgMIAwAAAA==.Kitcat:BAAALAADCgcIBwAAAA==.Kitsunibi:BAAALAAECgYIBgAAAA==.Kittyneko:BAAALAAECgIIBAAAAA==.',Kr='Krammuel:BAAALAADCgYIBgAAAA==.Krotus:BAAALAAECgIIBAAAAA==.Krìeg:BAAALAADCgQIBAAAAA==.',Ku='Kurohail:BAAALAAECgcIEAAAAA==.Kurolion:BAAALAAECgIIAgAAAA==.Kurosong:BAAALAAECgIIAgABLAAECgcIEAABAAAAAA==.Kusheed:BAAALAADCgQIBAAAAA==.',Kw='Kwanrwava:BAAALAAECgIIAgAAAA==.',Ky='Kyblade:BAAALAAECgYICQAAAA==.',['Kö']='Köhda:BAAALAADCgMIBAAAAA==.',['Kù']='Kùrupt:BAAALAAECggICAAAAA==.',La='Ladrogue:BAAALAAECgMIBQAAAA==.Larpfenn:BAAALAADCgcIBwAAAA==.',Le='Leosbryn:BAAALAAECgYICQAAAA==.Lerrielin:BAAALAAECgYIDAAAAA==.Lexide:BAAALAAECgMIBQAAAA==.',Lh='Lhaxorp:BAAALAAECgMIAwABLAAECggIDwABAAAAAA==.',Li='Ligmadeebliz:BAAALAAECgUIBgABLAAECgUIBwABAAAAAA==.Liilliith:BAAALAAECgIIAgAAAA==.',Lu='Lucero:BAAALAAECgMIBQAAAA==.Luethrin:BAAALAADCgEIAQAAAA==.',['Lê']='Lêona:BAAALAAECgQIBwAAAA==.',Ma='Mageblprows:BAAALAADCgcIEAAAAA==.Magikbeef:BAAALAADCggIDwAAAA==.Majackula:BAAALAADCggICAAAAA==.Maltreated:BAEBLAAECoEWAAMIAAgITCMoAwATAwAIAAgITCMoAwATAwAPAAEIQxJObgBBAAAAAA==.Mangothemage:BAABLAAECoEVAAICAAgI3yOuAgBNAwACAAgI3yOuAgBNAwAAAA==.Martidemon:BAAALAADCgEIAQAAAA==.Martiknight:BAAALAAECgUIBQAAAA==.Martrane:BAAALAADCgQIBAAAAA==.Matikz:BAABLAAECoEWAAMDAAgI/RsyCgCCAgADAAgI/RsyCgCCAgAEAAYIxQpBCgA6AQAAAA==.Maylla:BAAALAAECgEIAgAAAA==.',Me='Medali:BAAALAADCgIIAgAAAA==.Meddle:BAABLAAECoEXAAIYAAgI5CWGAABxAwAYAAgI5CWGAABxAwAAAA==.Meddlemorph:BAAALAAECgYIBgAAAA==.Meekcrob:BAAALAADCggICAAAAA==.Melìcta:BAAALAAECgEIAQAAAA==.Merthulion:BAAALAADCggICQAAAA==.Metaspec:BAAALAAECgYIDQAAAA==.Meyea:BAABLAAECoEXAAIFAAgIxyP6BAAjAwAFAAgIxyP6BAAjAwAAAA==.',Mi='Mikuji:BAAALAADCggIDgAAAA==.Miller:BAAALAADCgcIEAAAAA==.Miru:BAAALAAECgIIAgAAAA==.Mizadra:BAAALAAECgUIBwAAAA==.',Mo='Moghedian:BAAALAADCggIDwAAAA==.Monning:BAAALAAECgMIAwAAAA==.Moofenn:BAAALAADCgcIBwAAAA==.Moonzer:BAAALAAECgYICQABLAAECggIDwABAAAAAA==.Moraraa:BAAALAAECgIIAgAAAA==.',Mu='Munsen:BAAALAADCgcIBwAAAA==.',My='Myronorris:BAAALAADCgcIEwABLAAECgYICQABAAAAAA==.Mystìa:BAAALAADCggICAAAAA==.',['Mé']='Mércy:BAAALAAECgYIDAAAAA==.',['Mí']='Místerfister:BAAALAADCgcIBwAAAA==.',Na='Nakbu:BAAALAAECgIIAgAAAA==.Nazenezin:BAAALAAECgMIAwAAAA==.',Ne='Neblin:BAAALAADCgUIBQAAAA==.Necksus:BAAALAAECgMIAwAAAA==.Neralya:BAAALAADCggICAAAAA==.Nerfwarlocks:BAAALAAECgYIBgABLAAECggIFwAGACEmAA==.Neroth:BAAALAADCgEIAQAAAA==.',Ni='Niall:BAAALAADCggIDAAAAA==.Nivix:BAAALAAECgMIAwAAAA==.',No='Nombre:BAABLAAECoEWAAIUAAgIZRwtAwB/AgAUAAgIZRwtAwB/AgAAAA==.Notpetya:BAAALAADCgUIBQAAAA==.Notprepared:BAAALAAECgUIBQAAAA==.',Nu='Nuggi:BAAALAADCgEIAQAAAA==.',Nw='Nwt:BAAALAADCgcIBwABLAAECgQIBQABAAAAAA==.',Ny='Nylaehh:BAAALAADCgIIAgAAAA==.Nyvix:BAAALAADCgQIBAAAAA==.',On='Onewing:BAAALAADCgYIBgABLAAECgQIBwABAAAAAA==.Onorna:BAAALAADCggICAABLAAECggIFgAVAA0eAA==.Onornu:BAABLAAECoEWAAMVAAgIDR7DBwCSAgAVAAgIDR7DBwCSAgARAAcImxp2EgArAgAAAA==.Onornun:BAAALAAECgMIAwABLAAECggIFgAVAA0eAA==.',Or='Orcmagge:BAAALAADCgMIBAAAAA==.Orlidan:BAAALAAECgYICQAAAA==.',Ot='Ottilak:BAAALAAECgcIDwAAAA==.',Ox='Oxrow:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.Oxyshots:BAAALAAECgYIDwAAAA==.',Pa='Paolameda:BAAALAADCgYICAAAAA==.Paris:BAAALAADCgcIBwAAAA==.Paveway:BAAALAADCgQIAwAAAA==.',Pe='Pediatre:BAAALAAECgUIBQAAAA==.Peka:BAABLAAECoEXAAMRAAgI4x0LEABLAgARAAcInx4LEABLAgAVAAgImROfHQDLAQAAAA==.Pekakek:BAAALAAECgYIBgAAAA==.Pepsiraz:BAABLAAECoEUAAITAAgIYhgNBQBLAgATAAgIYhgNBQBLAgAAAA==.',Ph='Philoso:BAAALAAECgMIAwAAAA==.Phobius:BAABLAAECoEUAAIZAAgI9xr0AwCfAgAZAAgI9xr0AwCfAgAAAA==.',Pi='Pileofschitt:BAAALAAECgYICAAAAA==.Pippapjappin:BAAALAAECgMIAwAAAA==.Pireyne:BAAALAADCgYIBgAAAA==.Pistachioz:BAAALAAECgYICQAAAA==.',Pl='Playfultouch:BAAALAADCggICQAAAA==.',Po='Poonanypie:BAAALAADCgYIBgAAAA==.Poonzer:BAAALAAECggIDwAAAA==.Porosity:BAAALAADCgMIBAAAAA==.Powerpigeon:BAAALAADCggICAABLAAECggIHAARACgkAA==.',Qe='Qetesh:BAAALAAECgMIAwAAAA==.',Ra='Raehon:BAAALAADCggICAAAAA==.Rahel:BAAALAADCgcIBAAAAA==.Rain:BAAALAAECgMIAwAAAA==.Randalthorr:BAAALAADCgYIBgAAAA==.Rawwr:BAAALAAECgcICQAAAA==.',Re='Rekasa:BAAALAAECgYIBgAAAA==.Relentless:BAAALAAECgIIAgAAAA==.Reportable:BAAALAADCgQIAgAAAA==.',Rh='Rhowa:BAECLAAFFIEFAAITAAMIQRCdAADfAAATAAMIQRCdAADfAAAsAAQKgRcAAhMACAjOHu0CAKICABMACAjOHu0CAKICAAAA.',Ri='Riftraft:BAAALAADCgIIAgAAAA==.Ripjw:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.',Rk='Rkoo:BAAALAAECgUIBQAAAA==.',Ro='Rokmaat:BAAALAADCgcIBgAAAA==.Roxx:BAAALAADCggICAAAAA==.Roxzor:BAAALAAECgYIEgAAAA==.Royok:BAAALAAECgQIBwAAAA==.',Ry='Rynne:BAAALAAECggIEgAAAA==.',Sa='Sabroen:BAAALAADCgYIBgAAAA==.Saenys:BAAALAADCgYIBgAAAA==.Sakardi:BAAALAAECgIIBAAAAA==.Sartak:BAAALAADCgEIAQAAAA==.Sawedoff:BAAALAAECgEIAQAAAA==.Sazeon:BAAALAADCgEIAQAAAA==.',Sc='Scalybunz:BAAALAAECgEIAQAAAA==.Scamall:BAECLAAFFIEFAAISAAMIyyaqAABgAQASAAMIyyaqAABgAQAsAAQKgRkAAhIACAjyJg0AAJYDABIACAjyJg0AAJYDAAAA.Schokowitz:BAAALAAECgIIBAAAAA==.Screwdizzle:BAAALAAECgIIAgAAAA==.',Se='Seacrit:BAAALAAECgEIAQAAAA==.Secsysalad:BAAALAADCggICAABLAAECggIFgAJAGMZAA==.Senazeal:BAAALAAECgYIBgAAAA==.Severussnipe:BAAALAADCggICAAAAA==.',Sh='Shabxi:BAAALAADCgcIBwAAAA==.Shade:BAABLAAECoEUAAIDAAgIYgxfEgAAAgADAAgIYgxfEgAAAgAAAA==.Shageron:BAAALAAECggIDwAAAA==.Shallaman:BAAALAADCggICAAAAA==.Shampóóp:BAAALAADCggIDwAAAA==.Shankspec:BAABLAAECoEUAAIDAAcIoyJ6BwC5AgADAAcIoyJ6BwC5AgAAAA==.Shawns:BAAALAADCgcIBwAAAA==.Shayu:BAAALAADCgcICgAAAA==.Shivana:BAAALAAECgYIBgAAAA==.Shockdh:BAAALAADCgYIBgAAAA==.Shocksock:BAAALAAFFAIIAwAAAA==.Shoeboo:BAACLAAFFIEFAAIRAAMIdyACAgAhAQARAAMIdyACAgAhAQAsAAQKgRkAAhEACAiFJuwAAHgDABEACAiFJuwAAHgDAAAA.Shämash:BAAALAAECgMIBgAAAA==.Shìvä:BAAALAAECgEIAQAAAA==.Shízz:BAAALAADCgcIBwAAAA==.Shöck:BAAALAADCggIDwAAAA==.',Si='Sicc:BAAALAADCgcIBwAAAA==.Siccness:BAAALAAECgYICgAAAA==.Sieben:BAAALAAECgcIDQAAAA==.Siic:BAAALAADCgYIBgAAAA==.',Sk='Skoody:BAAALAAECgIIAgAAAA==.Skwerl:BAAALAADCgYIBgAAAA==.Skywalkêr:BAAALAAECgEIAQAAAA==.',Sl='Sliceroni:BAAALAADCgcICAAAAA==.Slumdawg:BAAALAAECgIIAgAAAA==.Slurmage:BAAALAAECgcICQAAAA==.',Sm='Smittywerben:BAAALAAECgYIBgAAAA==.Smokfun:BAAALAADCgYICgABLAAECggIFgAVANIiAA==.',So='Solidjen:BAAALAAECggIEAAAAA==.Sovera:BAAALAADCgcIBwAAAA==.',Sp='Sparkles:BAAALAADCgIIAgAAAA==.Springmango:BAAALAADCggIEAAAAA==.',St='Stabbydabby:BAAALAADCgcIBwAAAA==.Stansdck:BAAALAAECgYIBgAAAA==.Stanshield:BAAALAADCgUIBQAAAA==.Stevensiegal:BAAALAADCggICAAAAA==.Stiq:BAAALAADCggIDQAAAA==.Stojk:BAAALAADCgIIAgAAAA==.Stojkette:BAAALAAECgMIAwAAAA==.Stormbless:BAAALAAECgYICwAAAA==.Stormfallz:BAAALAAECgYICgAAAA==.Stronghands:BAAALAADCggIEAAAAA==.',Su='Surehoof:BAAALAAECgEIAgAAAA==.',Sw='Sweegie:BAAALAAECgYIEAAAAA==.Sweegs:BAAALAADCgMIAwAAAA==.',Sy='Syndrea:BAAALAADCgcIEwAAAA==.Sytryana:BAAALAAECgIIAgAAAA==.',['Sí']='Sílk:BAAALAADCggIEwAAAA==.',Ta='Taara:BAAALAAECgcIDwAAAA==.Tanjiro:BAAALAAECgMIBQABLAAECgMICQABAAAAAA==.Tarka:BAAALAADCggICAAAAA==.',Te='Teemo:BAAALAADCgIIAgAAAA==.Tehdymortis:BAABLAAECoEUAAIGAAgIvwzOGADaAQAGAAgIvwzOGADaAQAAAA==.Terk:BAABLAAECoEYAAIUAAgIYiZ8AABMAwAUAAgIYiZ8AABMAwAAAA==.Tewdee:BAAALAAECgMIAwAAAA==.',Th='Thacinis:BAAALAADCgUIBQAAAA==.Thalrymere:BAAALAAECgYICQAAAA==.Theepally:BAAALAADCgcIBwAAAA==.Thundin:BAAALAADCgcICQAAAA==.',Ti='Tidejitsu:BAABLAAECoEXAAMaAAgI5hTiDQDNAQAaAAcI0xTiDQDNAQAQAAgICwgqEQBrAQAAAA==.Tideshifts:BAAALAADCgcIBwAAAA==.Tikz:BAAALAAECgYIDAAAAA==.',To='Tock:BAAALAAECgYICgAAAA==.Tockella:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Toe:BAAALAAECgIIAgAAAA==.Tohil:BAAALAAECgEIAQAAAA==.Tokenwarrior:BAAALAAECgMIBAAAAA==.Topa:BAAALAAECgUIBwAAAA==.Torvï:BAAALAADCggIDwAAAA==.',Tr='Trapstâr:BAAALAAECgYIEgAAAA==.Tricky:BAAALAAECgYICQAAAA==.Trivalence:BAAALAAECgIIBAAAAA==.Trollboy:BAAALAADCggIDwAAAA==.Trolltrain:BAAALAAECgIIAgAAAA==.Trunky:BAAALAAECgUICAABLAAECgYICQABAAAAAA==.',Uk='Ukko:BAAALAADCggIDAAAAA==.',Un='Unholyreáper:BAAALAAECgYIDQAAAA==.Unholyrëaper:BAAALAAECgYICQAAAA==.Unkledeath:BAAALAAECgIIAQAAAA==.',Va='Vaughn:BAAALAAFFAIIAwAAAA==.',Ve='Vedekur:BAAALAADCggIDQAAAA==.Vegetate:BAAALAAECgYICQAAAA==.Veggieboi:BAAALAAECgYICAAAAA==.',Vi='Vigilo:BAAALAAECgcIDwAAAA==.Viki:BAAALAAECgUIBQAAAA==.Viruzdk:BAAALAAECgYIEAAAAA==.',Vo='Vonick:BAAALAADCgEIAQAAAA==.Vordrak:BAAALAAECgIIAgAAAA==.',Wa='Warwonka:BAABLAAECoEUAAIIAAgIohSHEgDxAQAIAAgIohSHEgDxAQAAAA==.Watchurbeard:BAAALAAECgYICQAAAA==.',We='Weatherdwarf:BAAALAAECgYICQAAAA==.Wetnoodle:BAAALAADCggIDwAAAA==.',Wh='Whamass:BAAALAAECgYIBgAAAA==.Whammer:BAAALAADCgUIBQAAAA==.Whiiplash:BAAALAAECggIDgAAAA==.',Wi='Willsmith:BAAALAAECgQIBgAAAA==.Windfûrry:BAAALAADCggICgABLAAECgMIAwABAAAAAA==.Winnydafoo:BAAALAADCgcIDgAAAA==.Winrie:BAAALAAECgEIAQAAAA==.',Wr='Wrapfire:BAAALAAECgIIBAAAAA==.',Xe='Xedria:BAAALAADCgIIAgAAAA==.',Xy='Xylali:BAAALAAECgEIAQAAAA==.Xyra:BAAALAAECggIBwAAAA==.',Ya='Yacob:BAABLAAECoEXAAICAAgIFibTAAB2AwACAAgIFibTAAB2AwAAAA==.Yamarahj:BAAALAAECggIEAAAAA==.',Yo='Yo:BAAALAAECggIDgAAAA==.Yorikk:BAAALAAECgMIBAAAAA==.Youngterps:BAAALAAECgQIBQAAAA==.',Yu='Yukika:BAAALAADCggICAAAAA==.',Za='Zanse:BAAALAADCggIDwAAAA==.Zaratul:BAAALAADCggIBwAAAA==.Zarkaz:BAAALAAECgMIBQAAAA==.Zarmaku:BAAALAAECgMIBwAAAA==.Zaubear:BAAALAAECgYICAABLAAFFAMIBQAKAM0fAA==.Zauber:BAACLAAFFIEFAAQKAAMIzR97AQDFAAAKAAII2x57AQDFAAAJAAIILRRKBwCxAAALAAEIniLpAABmAAAsAAQKgRQABAkACAiRJmYAAIoDAAkACAhjJmYAAIoDAAsABAgWIXMLAIoBAAoAAghUIt4yAKIAAAAA.Zavarian:BAAALAADCgUIBQABLAAECgMIBAABAAAAAA==.Zazu:BAAALAADCgMIAwAAAA==.',Ze='Zeetti:BAAALAADCggIDwAAAA==.Zensei:BAAALAAECgYIBgAAAA==.',Zi='Zirraj:BAABLAAECoEXAAIHAAgIuSTKAgBJAwAHAAgIuSTKAgBJAwAAAA==.Zivvy:BAAALAADCgQIBAAAAA==.',Zn='Zn:BAAALAADCgcIDAAAAA==.',Zu='Zurk:BAAALAADCggIDgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end