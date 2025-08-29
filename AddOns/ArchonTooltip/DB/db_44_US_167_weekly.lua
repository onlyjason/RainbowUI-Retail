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
 local lookup = {'Unknown-Unknown','Priest-Discipline','Shaman-Elemental','Warlock-Demonology','Monk-Windwalker','Hunter-BeastMastery','Druid-Balance','Warlock-Destruction','DeathKnight-Blood','Warrior-Protection','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Affliction','Shaman-Restoration','Paladin-Protection','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Mage-Arcane','Mage-Fire','Druid-Feral','Mage-Frost',}; local provider = {region='US',realm="Ner'zhul",name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adastea:BAAALAAECgYICQAAAA==.',Ae='Aethos:BAAALAAECggICAAAAA==.',Al='Alaanz:BAAALAADCggIDwAAAA==.Alexàndros:BAAALAAECgMIAwAAAA==.Alpharatz:BAAALAAECgYICQAAAA==.',Am='Amunwrath:BAAALAAECgQIBwAAAA==.',An='Andromëda:BAAALAAECgUICAAAAA==.Anelace:BAAALAAECgcIDgAAAA==.Anyana:BAAALAAECgYIBgAAAA==.',Ao='Aozeraa:BAAALAAECgYICwAAAA==.',Ar='Arazarke:BAAALAAECgEIAQAAAA==.Arcae:BAAALAAECgYICgAAAA==.Arnáiz:BAAALAAECgYICgAAAA==.Arthaas:BAAALAADCgYIBgAAAA==.Arthás:BAAALAAECgIIAgAAAA==.',As='Asaki:BAAALAAECgMIBAAAAA==.Ashtongue:BAAALAAECggICQAAAA==.Asurafresh:BAAALAAECgMIAwAAAA==.',Av='Avein:BAAALAADCgcIDAAAAA==.',Aw='Awakarih:BAAALAADCgEIAQAAAA==.',Ay='Aytumarido:BAAALAADCgQIBAAAAA==.Ayvero:BAAALAAECgMIAwAAAA==.',Az='Azgrumaul:BAAALAADCgYIBgAAAA==.Azin:BAAALAAECgEIAgAAAA==.Azurepriest:BAAALAADCgcICwAAAA==.Azuresham:BAAALAAECgQICQAAAA==.Azuric:BAAALAAECgMIAwAAAA==.',Ba='Baabels:BAAALAAECgYICgAAAA==.Balenciaga:BAAALAAECgEIAQAAAA==.Bamuth:BAAALAAECgcIEgAAAA==.Barkskinlol:BAAALAADCggIDAABLAAECgcIEgABAAAAAA==.Bawmbucha:BAAALAAECggIBwAAAA==.',Bb='Bbundo:BAAALAAECgIIAwAAAA==.',Be='Beartom:BAAALAADCggIDwAAAA==.Bedd:BAAALAADCgYIBgAAAA==.',Bg='Bgneedwork:BAAALAAECgYICQAAAA==.',Bi='Bigbud:BAAALAAECgIIAgAAAA==.Bignbad:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.Bigramy:BAAALAADCggICAAAAA==.Billidari:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.Bixby:BAAALAAECgMIBwAAAA==.',Bl='Blazedin:BAAALAAECgEIAQAAAA==.Blitinblade:BAAALAADCgcICAAAAA==.Bloodcore:BAAALAAECgMIAwAAAA==.',Bo='Bobelsted:BAAALAAECgMIAwAAAA==.Boeds:BAAALAAECgIIAwAAAA==.',Br='Breadman:BAAALAAECgMIAwAAAA==.Brotar:BAAALAADCggIBwAAAA==.Bryxie:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.',Bu='Bubbes:BAAALAAECgMIAwAAAA==.Bubbleguts:BAAALAAECgYIBgAAAA==.Bubblemourn:BAAALAAECgUIBgAAAA==.Buggasm:BAAALAADCgcIDAAAAA==.',['Bæ']='Bæn:BAAALAAECgMIBQAAAA==.',Ca='Calcub:BAAALAAECgMIBwAAAA==.Caly:BAEALAAECggIAQAAAQ==.Calykay:BAAALAADCgYICgAAAA==.Calym:BAEALAAECgMIAwABLAAECggIAQABAAAAAA==.Calystalyn:BAEBLAAECoEVAAICAAgIaxwKAQCuAgACAAgIaxwKAQCuAgABLAAECggIAQABAAAAAA==.Catheria:BAAALAADCgYIAgAAAA==.Catheriana:BAAALAAECgMIAwAAAA==.',Ch='Chach:BAAALAAECgUIBQAAAA==.Chanthony:BAAALAAECggIEgAAAA==.Chatz:BAAALAADCgQIBAAAAA==.Chawkdruid:BAAALAAECgYICAAAAA==.Cheesebag:BAAALAADCgcIBwAAAA==.Chupfury:BAAALAAFFAIIAgAAAA==.Chuppohh:BAAALAAECgcIDQAAAA==.',Ci='Cincy:BAAALAADCggICgAAAA==.Cindragosa:BAAALAAECgYIDAAAAA==.',Co='Colauris:BAAALAAECgYICQAAAA==.Coldholes:BAAALAAECgEIAQAAAA==.Cowtoes:BAAALAADCgcIBwAAAA==.Cozycat:BAAALAAECgYIDAAAAA==.',Cr='Crak:BAAALAADCgEIAQABLAAECgMIBAABAAAAAA==.Craydaughter:BAAALAADCgEIAQABLAAECgYICwABAAAAAA==.Crayson:BAAALAAECgYICwAAAA==.Crazroz:BAAALAADCggICAABLAAECgcIEgABAAAAAQ==.Crossbreeze:BAAALAAECgYIBwAAAA==.Crossover:BAAALAADCgUIBQAAAA==.',Da='Daddy:BAAALAAECgIIAgABLAAFFAMIBQADAI8ZAA==.Daddytotems:BAAALAAECgYIDQAAAA==.Dagwall:BAAALAAECgMIAwAAAA==.Dannamoth:BAAALAAECgMIAwAAAA==.Darkail:BAAALAADCggIDwAAAA==.Dathrustae:BAAALAADCgQIBAAAAA==.',Dc='Dctrdoom:BAAALAAECgMIBQAAAA==.',De='Deals:BAAALAADCgYIBgABLAAECggIFQAEAAojAA==.Deatherselfs:BAAALAAECgYIBwAAAA==.Deathex:BAAALAAECgEIAQAAAA==.Debrickashaw:BAAALAADCgcICQABLAAECgYICgABAAAAAA==.Delamone:BAAALAADCggIDgAAAA==.Delläk:BAAALAAECgMIBQAAAA==.Dementd:BAAALAAECgcIEQAAAA==.Demwun:BAAALAADCggICgAAAA==.Derekvinyard:BAAALAAECgEIAQAAAA==.Dezalan:BAAALAADCgEIAQAAAA==.',Di='Diavolina:BAAALAADCggICAAAAA==.Dig:BAAALAADCggICQAAAA==.Dillusion:BAAALAADCggICAAAAA==.Dinkdonk:BAAALAAECgYIDAAAAA==.Dinkdonkin:BAAALAAECgMIAwAAAA==.Diodoesdmg:BAAALAAECgcIDgAAAA==.',Dm='Dmuerte:BAAALAAECgEIAQAAAA==.',Do='Dolguldur:BAAALAADCggIDgAAAA==.Domochevsky:BAABLAAECoEUAAIFAAgIIRyJBgB6AgAFAAgIIRyJBgB6AgAAAA==.Domoshamsky:BAAALAAECgMIAwABLAAECggIFAAFACEcAA==.',Dr='Drakelm:BAAALAAECggIEgAAAA==.Drastïk:BAAALAAECgIIAgAAAA==.Drayolgen:BAAALAADCgcIBwAAAA==.Dreamweeder:BAAALAADCggIDAAAAA==.Droggö:BAAALAADCgUIBQABLAAECgYIDgABAAAAAA==.Drrdead:BAAALAAECgIIAgAAAA==.Drtotem:BAAALAADCggIFAAAAA==.Druuls:BAAALAADCggIDgAAAA==.Drwigglesz:BAAALAAECgEIAQAAAA==.',Du='Duckpond:BAAALAAECggIDwAAAA==.Dumbdragon:BAAALAADCgcIBwAAAA==.Durrtybao:BAAALAAECgEIAQAAAA==.Duskmane:BAAALAAECgEIAQAAAA==.',Ec='Eckco:BAAALAAECgQIBgAAAA==.Ecksman:BAAALAAECgYICQAAAA==.Ectheliön:BAAALAADCgYIBgABLAAECgYIDgABAAAAAA==.Ecthyma:BAAALAADCggICAAAAA==.',Ed='Ederic:BAAALAAECgEIAQAAAA==.Edgarthepale:BAAALAAECgMIBQAAAA==.',Ei='Eildor:BAAALAADCgYIBQAAAA==.Eillonwy:BAAALAAECgMIBwAAAA==.',Ek='Ekccko:BAAALAADCgYIBgABLAAECgQIBgABAAAAAA==.',Em='Ember:BAABLAAECoEVAAIGAAgILCMfBQAUAwAGAAgILCMfBQAUAwAAAA==.Emberz:BAAALAADCgYIBgAAAA==.Embraze:BAAALAAECgYICwAAAA==.',En='Engels:BAAALAAECgQIBQAAAA==.Enyaspace:BAAALAADCgcIBwAAAA==.',Er='Eradicated:BAAALAAECgYIBgAAAA==.Eremes:BAAALAAECgUIBQAAAA==.Eru:BAAALAAECgYICgAAAA==.',Es='Escaflowne:BAAALAADCgQIBAAAAA==.Esperranza:BAAALAAECgMIAwAAAA==.',Ev='Evodny:BAAALAADCggICAAAAA==.Evylet:BAAALAAECgYIDAAAAA==.',Fa='Fact:BAAALAAECgEIAQAAAA==.Faeris:BAAALAAECgMIBgAAAA==.',Fe='Feacialiale:BAAALAADCggIGwAAAA==.Felbladekid:BAAALAAECgYICAAAAA==.Fellspawn:BAAALAADCggIDwABLAAECgYIDgABAAAAAA==.Fenella:BAAALAAECgMIAwAAAA==.',Fi='Fikkle:BAAALAAECgMIBwAAAA==.Finnar:BAAALAADCgcIBwAAAA==.Fisttoface:BAAALAADCggIDwAAAA==.',Fl='Flapflapbust:BAAALAAECggICgABLAAECggIFgAHAO0kAA==.Flappytwinky:BAAALAADCgQIBAAAAA==.',Fo='Forestwayngr:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Fortysouls:BAAALAADCgQIBAABLAADCggIAQABAAAAAA==.Forvalhalla:BAAALAADCgUIBQAAAA==.Foxhunt:BAAALAAECgMIAwAAAA==.',Fr='Friarpuck:BAAALAAECgEIAgAAAA==.Frozensalt:BAAALAAECgcICwAAAA==.Fryssa:BAAALAADCgYIBgAAAA==.',Fu='Furrsparta:BAAALAADCggICQAAAA==.Fuzhun:BAAALAADCgcIDAAAAA==.',Ga='Gaebrill:BAAALAAECgMIAwAAAA==.Galiphe:BAAALAAECgYICwAAAA==.Garidan:BAAALAAECgMIBAAAAA==.',Ge='Geeyanni:BAAALAAECgYICwAAAA==.Geopetal:BAAALAAECggIDwAAAA==.',Gh='Ghavilax:BAAALAADCggICAAAAA==.',Gi='Gibbes:BAAALAAECgQIBwAAAA==.Gigahorn:BAAALAADCgcIBwABLAAECggIEwABAAAAAA==.Gigga:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Gingy:BAAALAAECgcICwAAAA==.',Gj='Gjoll:BAAALAAECgYICwAAAA==.',Gl='Gladefresh:BAAALAAECgIIAgAAAA==.Glocked:BAAALAAECgYICAAAAA==.',Go='Goldenice:BAAALAAECgQIBgAAAA==.Golokhan:BAAALAAECgIIAgAAAA==.Gorannak:BAAALAADCgYICgAAAA==.Gorgô:BAAALAADCgcIBwAAAA==.Gornur:BAAALAADCgYIBgAAAA==.',Gr='Gromix:BAAALAADCgcIDQAAAA==.',Gu='Guiles:BAAALAADCgQIBAAAAA==.',['Gä']='Gähl:BAAALAAECgMIAwAAAA==.',Ha='Hafwyn:BAAALAAECgYIDgAAAA==.Hammy:BAAALAADCgEIAQAAAA==.Hanor:BAAALAADCggIDQAAAA==.Harakiri:BAAALAAECgYICQAAAA==.Harrizune:BAAALAAECgEIAQAAAA==.Haunteddrank:BAAALAAECgEIAQAAAA==.Hayley:BAAALAADCggICAAAAA==.',He='Headquarters:BAAALAADCgIIAgABLAADCggIAQABAAAAAA==.Healador:BAAALAADCgEIAQAAAA==.Healingtime:BAAALAAECgIIAgAAAA==.Heka:BAAALAADCgUICQAAAA==.Hellballz:BAAALAADCggICAAAAA==.',Ho='Holyholyholy:BAAALAAECgYICAAAAA==.Holymeow:BAAALAADCgMIAwABLAADCggIDwABAAAAAA==.Holysmiter:BAAALAAECgMIBQAAAA==.Hoodfabulous:BAAALAAECgYIDwAAAA==.Hordebob:BAAALAAECgUICAAAAA==.Hots:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.Hoverboots:BAAALAADCgIIAgAAAA==.',Hu='Huberto:BAAALAADCgcIEgAAAA==.Hungryhuskar:BAAALAADCggICAAAAA==.Huntforblood:BAAALAADCgcIEgAAAA==.Hupyaptelyot:BAAALAAECgMIBwAAAA==.',Hy='Hytierea:BAAALAAECgYIDAAAAA==.',Ic='Icebox:BAAALAADCgcIBwAAAA==.',Id='Idra:BAAALAADCgEIAQABLAAECgYIDAABAAAAAA==.',Im='Imawayne:BAAALAAECgMIAwAAAA==.Impulsé:BAAALAADCggIDAAAAA==.',In='Incubus:BAAALAAECgYICwAAAA==.Inward:BAAALAAECgIIAgAAAA==.',Ir='Iriemon:BAAALAAECgMIBgAAAA==.Ironstomp:BAAALAAECggICAAAAA==.',Is='Ishamaêl:BAAALAADCgMIAwAAAA==.Issowimonk:BAAALAADCgUIBQABLAAECgYIBwABAAAAAA==.Issowishaman:BAAALAAECgYIBwAAAA==.',It='Italiaa:BAAALAADCggIDAAAAA==.',Ix='Ixtel:BAAALAAECgMIBwAAAA==.',Ja='Jaidy:BAAALAAECgMIBQAAAA==.Janfebmarch:BAAALAAECggIEwAAAA==.Jasperb:BAAALAADCgYIDAABLAADCggIDwABAAAAAA==.Jayshieldin:BAAALAADCgQIBAAAAA==.',Je='Jerzzarn:BAAALAAECgMIBAAAAA==.',Ji='Jinzx:BAAALAAECgQIBgABLAAECgYIEQABAAAAAA==.Jinzzx:BAAALAAECgYIEQAAAA==.',Jm='Jmaman:BAAALAAECgEIAQAAAA==.',Jo='Jojo:BAAALAAECgYIDgAAAA==.Jolannar:BAAALAADCgYIBgAAAA==.',Ju='Judgedranz:BAAALAAECgEIAQAAAA==.Judoso:BAAALAAECgMIBAAAAA==.Jujubear:BAAALAAECgEIAQAAAA==.Junnarma:BAAALAAECgQIBwAAAA==.',['Já']='Járnviðr:BAAALAAECgYIDgAAAA==.',['Jé']='Jérrex:BAAALAADCgUIBQAAAA==.',Ka='Kabrax:BAAALAADCggICAAAAA==.Kadrath:BAAALAAFFAIIAgAAAA==.Kaelmythe:BAAALAAECgMIBgAAAA==.Kaiula:BAAALAAECgcIEwAAAA==.Kajione:BAAALAAECgUIBQAAAA==.Kakegurui:BAAALAADCgMIAwAAAA==.Kalabar:BAAALAAECgEIAQAAAA==.Kalnath:BAAALAAECgcIDgAAAA==.Kalynnah:BAAALAAECgYICQAAAA==.Kamalsutra:BAAALAADCgcICgAAAA==.Kanatoo:BAAALAAECgYIDwAAAA==.Kanekisenpai:BAABLAAECoEWAAMEAAgIyx2/BAAgAgAEAAgIrxu/BAAgAgAIAAcIThk8FAAfAgAAAA==.Kanjam:BAAALAAECgMIBgAAAA==.Kardiiac:BAAALAADCgcICwAAAA==.Kazrar:BAAALAADCggIDgAAAA==.',Ke='Kelai:BAABLAAECoEUAAIJAAgI1yAiAwC9AgAJAAgI1yAiAwC9AgAAAA==.',Ki='Kilmall:BAAALAADCggICAAAAA==.Kilusuka:BAAALAADCggICwAAAA==.Kitsa:BAAALAAECgEIAgAAAA==.Kittypride:BAAALAAECgIIAgAAAA==.',Kn='Kneenja:BAAALAAECgYICwAAAA==.',Ko='Kobarr:BAAALAAECgYICgAAAA==.Konfucius:BAAALAAECgYICwAAAA==.Kordhel:BAAALAADCggICAAAAA==.',Kr='Krump:BAAALAAECgYIDgAAAA==.',Ku='Kultek:BAAALAAECgMIAwABLAAECggIFAAJANcgAA==.Kuramá:BAAALAAECgEIAQAAAA==.Kurina:BAABLAAECoEWAAIKAAgITxKPDQC9AQAKAAgITxKPDQC9AQAAAA==.Kuyà:BAAALAAECgcIDgAAAA==.Kuzé:BAAALAAECgMIBQAAAA==.',Kw='Kwyjibo:BAABLAAECoEWAAMLAAgI/Rg+FQBWAgALAAgI/Rg+FQBWAgAMAAMI9hM0IgC5AAAAAA==.',Ky='Kyuubi:BAAALAAECgYICwAAAA==.',La='Lanrythe:BAAALAAECgEIAQAAAA==.Lase:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Latronin:BAAALAADCgYIBgAAAA==.',Le='Leglocker:BAAALAAECgMIBQAAAA==.Let:BAAALAADCgYIBgAAAA==.Levace:BAAALAAECgYIBgAAAA==.',Li='Liamneesngos:BAAALAADCgUIBwAAAA==.Lightisdead:BAAALAADCgcIBwAAAA==.Lightningki:BAAALAAECgMIBwAAAA==.Lindariel:BAAALAAECgYICgAAAA==.Lindir:BAAALAAECgYICQAAAA==.Lirina:BAAALAADCgcIBwAAAA==.',Lo='Lockedupfoo:BAABLAAECoEVAAQIAAgIMyQoEABQAgAIAAYIiyMoEABQAgAEAAUIOR/dEgBvAQANAAEIkxH2JgBRAAAAAA==.Lodi:BAAALAADCgMIBgABLAAECgYICwABAAAAAA==.Lolmindflay:BAAALAAECgEIAQAAAA==.Lorchah:BAAALAAECgEIAQAAAA==.Lorkon:BAAALAADCgQIBAAAAA==.Lostevoker:BAAALAAECgMIAwAAAA==.',Lu='Lugugugu:BAAALAAECgEIAQAAAA==.Lunarfrff:BAAALAADCgEIAQAAAA==.Luporain:BAAALAAECgEIAQAAAA==.Luppoo:BAAALAAECgQIBAAAAA==.Lussty:BAAALAADCggIDQAAAA==.',Ly='Lyfeline:BAAALAADCgcIDAAAAA==.',['Lá']='Láise:BAAALAADCgQIBAABLAAECgYIBgABAAAAAA==.',Ma='Machahunt:BAAALAAECgQIBgAAAA==.Machico:BAAALAAECgMIBgAAAA==.Maelstrom:BAAALAADCgEIAQABLAADCggICQABAAAAAA==.Magicdeadly:BAAALAAECgEIAQAAAA==.Magosika:BAAALAAECgEIAgAAAA==.Mailen:BAAALAADCgEIAQAAAA==.Maledizione:BAAALAAECgYIBwAAAA==.Manasplainer:BAAALAAECgIIAgABLAAECggICQABAAAAAA==.Maxbadly:BAAALAAECgMIBgAAAA==.Maxplanck:BAAALAADCgcIBwAAAA==.Maybebi:BAAALAADCgYIBgAAAA==.Mazkrot:BAAALAADCgcIEgAAAA==.',Me='Meadow:BAAALAADCggIDgAAAA==.Medea:BAAALAAECgMIAwAAAA==.Medeus:BAAALAADCgcIDwAAAA==.Medívh:BAAALAADCgYICAABLAADCgcIBwABAAAAAA==.Megahorn:BAAALAAECggIEwAAAA==.Megapod:BAAALAADCggICAAAAA==.Memon:BAAALAADCgMIAwAAAA==.Menily:BAAALAADCggICAAAAA==.Merpp:BAAALAAECgMIBAAAAA==.Metalwarrior:BAAALAAECgYICQAAAA==.',Mi='Midniyt:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Mikki:BAAALAADCggIFAAAAA==.Mikkilina:BAAALAAECgMIBgAAAA==.Mild:BAAALAAECgEIAQAAAA==.Minarax:BAAALAAECgIIAgAAAA==.Minipog:BAAALAAECgMIBAAAAA==.Minishadow:BAAALAAECgMIBQAAAA==.Mitric:BAAALAAECgIIAgAAAA==.',Mm='Mmeow:BAAALAADCggIDwAAAA==.',Mo='Monachus:BAAALAAECgIIAwAAAA==.Mongokjunior:BAAALAADCgEIAQAAAA==.Monkpera:BAAALAADCggICAAAAA==.Mooph:BAAALAADCgMIAwAAAA==.Moowarrior:BAAALAAECgQIBgAAAA==.Morgothic:BAAALAADCgYIBgAAAA==.',Ms='Msixty:BAAALAADCgcIBwAAAA==.',Mu='Murmaiderr:BAAALAAECgUICAAAAA==.Murman:BAAALAADCggIGgAAAA==.',My='Mykaela:BAAALAADCgcIBwAAAA==.Mykee:BAAALAAECgMIBAAAAA==.Mystic:BAAALAAECgMIBgAAAA==.Mysticdemon:BAAALAADCgEIAQAAAA==.Mysticladin:BAAALAADCggICAAAAA==.',['Mö']='Möthug:BAAALAAECgIIAgAAAA==.',Na='Nalla:BAAALAADCgMIAwAAAA==.Naoz:BAAALAADCggIFAAAAA==.Naravian:BAAALAAECgMIAwAAAA==.Narunì:BAAALAADCgUIBwAAAA==.Nater:BAAALAAECgMIAwAAAA==.',Ne='Nekrron:BAAALAAECgYICAAAAA==.',Ni='Nickthehick:BAAALAADCggICAAAAA==.Nightlord:BAAALAAECgUIBQAAAA==.Nikaku:BAAALAAECgMIBAAAAA==.Nitakip:BAAALAADCgEIAgAAAA==.',No='Nohozkohkoh:BAAALAADCggICAAAAA==.Norko:BAAALAADCggICAAAAA==.',Ny='Nyrell:BAAALAAECgIIAgAAAA==.',Of='Offweight:BAAALAAECgMIBAAAAA==.',Ok='Okishama:BAABLAAECoEVAAMDAAgIIxuQDQByAgADAAgIIxuQDQByAgAOAAIIvghdbwBVAAAAAA==.',Ol='Olkoth:BAAALAADCgcIBwAAAA==.',On='Oneinchash:BAAALAADCggICAAAAA==.Onytzia:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.',Op='Ophelastra:BAAALAADCggIDgAAAA==.',Or='Orlon:BAAALAADCgMIAwAAAA==.',Oz='Ozrick:BAAALAADCggIDAAAAA==.',Pa='Palamaine:BAABLAAECoEUAAIPAAgIkSATAwDPAgAPAAgIkSATAwDPAgAAAA==.Paleail:BAAALAADCggIDQABLAADCggIDwABAAAAAA==.Partytime:BAAALAADCgUIBQAAAA==.',Pe='Pestey:BAAALAADCgEIAQABLAAECggIEAABAAAAAA==.Pesty:BAAALAAECggIEAAAAA==.Pettax:BAAALAADCggICAAAAA==.',Ph='Phate:BAAALAAECgIIBQAAAA==.',Pi='Pikkle:BAAALAADCggIEgAAAA==.',Pk='Pkflash:BAAALAAECgMIAwAAAA==.',Pl='Pleabs:BAAALAAECgYICwAAAA==.Plikka:BAAALAADCgcIDgABLAAECgYICQABAAAAAA==.',Po='Powerburn:BAAALAADCgcIBwAAAA==.',Pr='Praesolus:BAAALAAECgMIBAAAAA==.Praysop:BAAALAAECgEIAQAAAA==.Preech:BAAALAADCgcIBwAAAA==.Prepared:BAAALAADCgUIBQAAAA==.Probstoned:BAAALAAECgEIAQAAAA==.Promocode:BAAALAADCggIEwABLAAECggIFQAEAAojAA==.',Ps='Pssybreath:BAAALAAECgMIBwAAAA==.',Pu='Puddl:BAAALAAECgEIAQAAAA==.Punnisher:BAAALAAECgEIAQAAAA==.',Qf='Qf:BAAALAAECggICAABLAAECgMIAwABAAAAAA==.',Qt='Qtpre:BAAALAAECgMIAwAAAA==.',Qu='Quidamtyra:BAAALAAECgMIAwAAAA==.',Ra='Raawful:BAAALAAECgYICwAAAA==.Rabbifrost:BAAALAAECgYICwAAAA==.Radiana:BAAALAAECgMIBAAAAA==.Rageon:BAAALAADCggIDwAAAA==.Raphic:BAAALAADCggIFAAAAA==.Rathvyr:BAABLAAECoEXAAIQAAgILCP/BAAfAwAQAAgILCP/BAAfAwAAAA==.',Re='Readyaft:BAAALAAECgMIBwAAAA==.Rebeakah:BAAALAAECgMIBgAAAA==.Redbash:BAAALAAECgcIEQAAAA==.Reflex:BAAALAAECgMIAwAAAA==.Reggs:BAAALAAECgYIBwAAAQ==.Reminara:BAAALAAECgMIBgAAAA==.Renko:BAAALAAECgYICwAAAA==.',Rh='Rhaynera:BAAALAADCggIFAAAAA==.',Ri='Riggins:BAAALAADCgYICQAAAA==.Rigginss:BAAALAADCgQIBAAAAA==.Rightkick:BAAALAADCgIIAgAAAA==.Rilakuma:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Rillandis:BAAALAADCgcIBwAAAA==.',Ro='Roddaric:BAAALAADCgcIDAAAAA==.Roguspanish:BAAALAADCgcICwAAAA==.Rolling:BAAALAAECgMIAwAAAA==.Roserage:BAAALAAECgMIBQAAAA==.Rozewyn:BAAALAAECgYICwAAAA==.',Ru='Ruijerd:BAAALAADCgYIBgAAAA==.Russianlove:BAAALAAECgIIBAAAAA==.',Ry='Ryawhitefang:BAAALAAECgYICQAAAA==.',Sa='Sadgoblin:BAAALAAECgIIAwAAAA==.Salael:BAAALAAECgcIEAAAAA==.Sangwyn:BAAALAADCggIDwAAAA==.Saphirin:BAAALAAECgYIBgAAAA==.Sater:BAAALAAECgQIBgAAAA==.Saya:BAAALAADCggIDAAAAA==.',Sc='Schitris:BAAALAADCggIDgABLAABCgEIAQABAAAAAA==.Schutzengel:BAAALAAECgUIBgAAAA==.Scribbl:BAAALAAECggICwAAAA==.',Se='Serkand:BAAALAAECgEIAQAAAA==.',Sh='Shadowshot:BAAALAAECgcIEAAAAA==.Shallowgrave:BAAALAAECgQIBgAAAA==.Shamaroo:BAAALAAECgQIBwAAAA==.Shammyhaggar:BAAALAADCggIDwAAAA==.Shamuraijack:BAABLAAECoEWAAIDAAgIUh/FCgCmAgADAAgIUh/FCgCmAgAAAA==.Shamywamy:BAAALAAECgMIAgAAAA==.Sharkhunter:BAAALAADCgYIAgABLAABCgEIAQABAAAAAA==.Shayn:BAAALAADCgcIDAAAAA==.Shaz:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.Shazbot:BAAALAAECgYICQABLAAECgMIAwABAAAAAA==.Shiffty:BAAALAAECgMIBQAAAA==.Shortroundd:BAAALAADCggICAAAAA==.Shrivel:BAAALAADCgIIAgAAAA==.Shwingg:BAAALAADCggICwAAAA==.Shyza:BAAALAAECgEIAQAAAA==.Shäde:BAAALAAFFAEIAQAAAA==.',Si='Siek:BAAALAADCgYIBgAAAA==.',Sk='Skabby:BAAALAAECgMIAwABLAAECgMIBgABAAAAAA==.Skeletondk:BAAALAADCgQIBAAAAA==.Skiethx:BAABLAAECoEWAAMRAAgIzSTzAABbAwARAAgIuyTzAABbAwASAAEIHyZGEwBvAAAAAA==.Skinfeast:BAAALAAECgIIAgAAAA==.Skra:BAAALAAECgcIEgAAAQ==.Skullderz:BAAALAAECgYIDQAAAA==.Skullderzii:BAAALAAECgYIDQABLAAECgYIDQABAAAAAA==.Skullderzvi:BAAALAAECgMIAwABLAAECgYIDQABAAAAAA==.',Sl='Slambonie:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.Slute:BAAALAAECgIIAgAAAA==.',Sm='Smashyz:BAAALAADCgIIAgABLAAECggIDwABAAAAAA==.Smitherz:BAAALAADCgcIBwABLAADCggIFgABAAAAAA==.',Sn='Snotrocket:BAAALAADCggICAAAAA==.',So='Somaria:BAAALAADCgcICQAAAA==.Soopavillain:BAAALAAECgMIBAAAAA==.Sovietu:BAAALAADCggICAAAAA==.Soyahuasca:BAAALAADCgUIAwAAAA==.',Sp='Spacedusts:BAAALAAECgYICQAAAA==.Sparykz:BAAALAAECgMIBQAAAA==.Spazie:BAAALAAECgQIBgAAAA==.Spnkynvrsoft:BAAALAAECgcIEgAAAA==.',Sq='Squeakers:BAAALAADCgcIBwAAAA==.Squee:BAAALAAECgEIAgAAAA==.Squirts:BAAALAAECgIIAgAAAA==.',Sr='Srmonkey:BAAALAAECgYIBgAAAA==.',St='Stabachacha:BAABLAAECoEWAAMRAAgIlSF5AwAPAwARAAgIlSF5AwAPAwATAAEIFAZtDgAyAAAAAA==.Stealthanie:BAAALAAECgQIBgAAAA==.Steamicyhott:BAAALAADCggIDwAAAA==.Sth:BAAALAAECgMIAwAAAA==.Stinkie:BAAALAAFFAIIAgAAAA==.Stonebeard:BAAALAADCggIFgAAAA==.Stormblessed:BAAALAAECgQIBgAAAA==.Stormscream:BAAALAAECgMIBgAAAA==.Stríx:BAAALAAECgcIDgAAAA==.',Su='Subliminal:BAAALAAECgQIBAAAAA==.Suhl:BAAALAADCgUIBQAAAA==.Supaslappa:BAAALAAECgEIAQAAAA==.Super:BAABLAAECoEUAAMUAAgI4x9VDgCzAgAUAAgICR9VDgCzAgAVAAEIFSLmCQBfAAAAAA==.Surgate:BAAALAAECgcIDgAAAA==.Suriell:BAAALAAECgEIAQAAAA==.Surit:BAAALAADCgYIBgAAAA==.Surthi:BAAALAAECgEIAQAAAA==.Suspencer:BAAALAAECgYIBgAAAA==.',Sw='Swampybutt:BAAALAAECgEIAQAAAA==.Swane:BAAALAADCggICAAAAA==.',Sy='Sylverarrow:BAAALAAECgYICQAAAA==.Symph:BAAALAAECgIIBAAAAA==.Syndel:BAAALAAECgEIAQAAAA==.Syzyx:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Ta='Tadorcha:BAAALAAECgIIAgAAAA==.Tankhealsdps:BAAALAAECggICAAAAA==.Tarnfair:BAAALAADCggIDAAAAA==.Taven:BAAALAADCgcIBwAAAA==.',Te='Tekka:BAAALAAECgQIBgAAAA==.Telvor:BAAALAAECgMIBQAAAA==.Teminar:BAAALAADCggIEgAAAA==.Teralynn:BAAALAADCggICAAAAA==.Terrukk:BAAALAAECgIIAgAAAA==.Teufelsnudel:BAAALAAECgYICwAAAA==.',Th='Thekizbe:BAAALAADCgcIBwAAAA==.Thelippy:BAAALAADCgQIBAAAAA==.Therran:BAAALAAECgYICQAAAA==.Theuss:BAAALAAECgMIAwAAAA==.Thexxa:BAAALAADCgcIBwAAAA==.Thorraden:BAAALAADCgcIBwAAAA==.Thranduill:BAAALAAECgYICAAAAA==.',Ti='Tigerclaw:BAAALAADCgcICgAAAA==.Tilley:BAAALAAECgMIBQAAAA==.Tingaling:BAAALAAECgMIAwAAAA==.Tinyt:BAAALAAECgYICgAAAA==.',Tl='Tlock:BAAALAAECgMIBwAAAA==.',To='Todokoro:BAAALAADCgcIBwAAAA==.Toothlss:BAAALAAECgMIBAAAAA==.Torrero:BAABLAAECoEWAAIWAAgISBYcBgA2AgAWAAgISBYcBgA2AgAAAA==.Toyletwahtah:BAAALAADCgcICgAAAA==.',Tr='Tralth:BAAALAADCgUIBQAAAA==.Tribalz:BAAALAAECgYICwAAAA==.Triples:BAABLAAECoEVAAIUAAgIWxiTFQBmAgAUAAgIWxiTFQBmAgAAAA==.Tripsitter:BAAALAADCgUIBQAAAA==.Trunddle:BAAALAAECgEIAQAAAA==.',Ty='Tygrelilly:BAAALAAECgMIBgAAAA==.Tyrfyre:BAAALAADCgMIBQAAAA==.',['Té']='Témptations:BAAALAADCgYIBwAAAA==.',Un='Undeadpriest:BAAALAADCgcIDAAAAA==.',Va='Valandrian:BAAALAAECgMIBQAAAA==.Valkirion:BAAALAAECgMIBgAAAA==.Valmont:BAAALAAECgIIAgAAAA==.',Ve='Veevx:BAAALAADCgYIBwAAAA==.Vekz:BAAALAAECgYICwAAAA==.Vervdk:BAAALAAECgEIAQAAAA==.Vervlock:BAAALAAECggIDQAAAA==.Vexander:BAAALAAECgIIAgAAAA==.',Vo='Vongimiz:BAAALAADCgcICAAAAA==.Vork:BAAALAAECgMIBwAAAA==.Voucher:BAABLAAECoEVAAMEAAgICiOEBgD8AQAEAAYI1yOEBgD8AQAIAAUIUx88IACvAQAAAA==.',Vy='Vysérå:BAAALAAECgYICQAAAA==.',['Vé']='Vénkman:BAAALAAECgYIBwAAAA==.',Wa='Warglaíve:BAAALAAECgMIAwAAAA==.Waterlilly:BAAALAADCgcIBwAAAA==.',We='Welanin:BAAALAADCggIDwAAAA==.',Wh='Whizdum:BAAALAADCggICQAAAA==.',Wi='Wil:BAAALAAECgYICQAAAA==.Wildbillee:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Wildbilly:BAAALAAECgMIAwAAAA==.Wind:BAAALAADCggICAAAAA==.Witchblade:BAAALAADCggICQABLAAECgMIBgABAAAAAA==.Wizzlewozzle:BAAALAAECgMIAwAAAA==.',Wo='Wolvslayer:BAAALAAECgMIAwABLAAFFAEIAQABAAAAAA==.Worldwaker:BAAALAAECgcICwAAAA==.',Wu='Wukard:BAAALAAECgMIBAAAAA==.',Wy='Wyldbill:BAABLAAECoEUAAQNAAgIdhv5BgDuAQANAAYIKhf5BgDuAQAEAAUIKxdjHAAuAQAIAAEIhg/3XAA8AAAAAA==.',Xa='Xarxzez:BAAALAAECgMIBAAAAA==.',Xc='Xcarnage:BAAALAADCgIIAgAAAA==.',Xg='Xgambit:BAAALAADCggIDQAAAA==.',Xp='Xprtwarrior:BAAALAAECgYICwAAAA==.',Ya='Yamadin:BAAALAAECgMIAwAAAA==.Yatzhee:BAAALAADCgcICgAAAA==.',Yi='Yishi:BAAALAAECgMIBwAAAA==.',Yo='Yokoyama:BAAALAAECgYICgAAAA==.Yolei:BAAALAADCgQIBAAAAA==.',Yu='Yuckmouth:BAABLAAECoEUAAIXAAgI3Rd/CQAzAgAXAAgI3Rd/CQAzAgAAAA==.Yuli:BAAALAAFFAIIAgAAAA==.',Za='Zaborg:BAAALAAECgIIAgAAAA==.Zadaen:BAAALAAECgMIBQAAAA==.Zalasande:BAAALAAECgIIAgABLAAECggIFgARAJUhAA==.Zandashaman:BAAALAADCgcIBgAAAA==.Zank:BAAALAAECgMIBQAAAA==.Zantai:BAAALAAECgcIDgAAAA==.Zaraeicelis:BAAALAAECgIIAgAAAA==.Zardax:BAAALAADCgQIBgAAAA==.',Ze='Zeita:BAAALAAECgQIBgAAAA==.Zeuce:BAAALAADCggICAAAAA==.',Zh='Zheron:BAAALAAECgIIAgAAAA==.',Zi='Zivie:BAAALAAECgYIBgAAAA==.',Zo='Zorkky:BAAALAADCgQIBwAAAA==.',Zs='Zsuzsa:BAAALAADCggIEAAAAA==.',Zu='Zuule:BAAALAADCggICQAAAA==.',Zy='Zylowe:BAAALAADCgcIEQAAAA==.',['Ác']='Áchu:BAAALAAECgYICQAAAA==.',['Ça']='Çarm:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end