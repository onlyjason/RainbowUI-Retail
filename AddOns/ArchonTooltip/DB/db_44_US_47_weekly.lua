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
 local lookup = {'Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Monk-Brewmaster','Warrior-Protection','DemonHunter-Havoc','Shaman-Restoration','Paladin-Retribution','Paladin-Protection','Druid-Feral','Druid-Restoration','Druid-Balance','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Mage-Frost','Warlock-Demonology','Priest-Holy','Monk-Windwalker','Druid-Guardian','DeathKnight-Blood',}; local provider = {region='US',realm='BurningLegion',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aalfie:BAAALAAECgUICAABLAAECgcIDwABAAAAAA==.',Ad='Aderren:BAAALAAECgIIAgAAAA==.',Ae='Aethras:BAAALAADCggIDwAAAA==.Aevella:BAABLAAECoEUAAMCAAcI3CPeAQCzAgACAAcIPSPeAQCzAgADAAUIjx4OGgCuAQAAAA==.',Ag='Aghanaar:BAAALAAECgEIAgAAAA==.Agidan:BAAALAAECgQIBAAAAA==.',Al='Alcøholism:BAAALAADCggICAAAAA==.Alijah:BAAALAAECgYICwAAAA==.Alleriá:BAAALAAECgQIBgAAAA==.Almora:BAAALAADCgEIAQAAAA==.Altöra:BAAALAAFFAIIAgAAAA==.',Am='Amatsubu:BAAALAAECgIIAgABLAAFFAQIBwAEALAeAA==.',An='Ancalime:BAABLAAECoEWAAIFAAgIviFvAAA9AwAFAAgIviFvAAA9AwAAAA==.Andrial:BAAALAADCgQIAQAAAA==.Angelmoon:BAAALAADCgcIDwAAAA==.Anklehumper:BAAALAAECgYIDgAAAA==.Anthreaz:BAAALAAECgYICQAAAA==.',Ap='Aphic:BAAALAADCgYIBgAAAA==.Applepie:BAAALAAECgQIBQAAAA==.',Ar='Arcell:BAAALAAECgMIBQAAAA==.Arczy:BAAALAADCggICAAAAA==.Areye:BAAALAADCgUIBwAAAA==.Armous:BAAALAAECgYICQAAAA==.Arzuros:BAAALAAECgYICgAAAA==.',As='Aspenetta:BAAALAADCgcICgAAAA==.Asrian:BAAALAAECgcIDgAAAA==.Astrel:BAAALAAECgcIDgAAAA==.',At='Atmaweapn:BAAALAADCggICAABLAADCggICgABAAAAAA==.',Au='Aurorias:BAAALAAECgMIBAAAAA==.',Ay='Ayumí:BAAALAADCgcIDQAAAA==.',Az='Azzulaa:BAAALAADCgYIBgAAAA==.',Ba='Baconarrow:BAAALAAECgMIAwAAAA==.Baconcakes:BAAALAADCggIDAAAAA==.Badsquatch:BAAALAADCgcIBwAAAA==.Balkasha:BAAALAAECgQIBAAAAA==.Bartholomew:BAAALAADCggIFAAAAA==.Basil:BAAALAADCgIIAgAAAA==.',Be='Bearoldramis:BAAALAADCgcIBwAAAA==.Belladonna:BAAALAAECgYIDQABLAAECggIFgAGAJEhAA==.Besthunter:BAAALAADCgQIBAAAAA==.',Bi='Bigdragun:BAAALAADCgIIAgAAAA==.',Bl='Blackorc:BAAALAAECgYIDgAAAA==.Blast:BAAALAAECgcIDwAAAA==.Blastphemy:BAABLAAECoEUAAIHAAcI+w0EIACWAQAHAAcI+w0EIACWAQAAAA==.Blaçkout:BAAALAAECgQICAAAAA==.Bleedlife:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.Blinksoncd:BAAALAAFFAIIAwAAAA==.Bloodbott:BAAALAAECgcIDgAAAA==.Bloodrainer:BAAALAADCgcIBwAAAA==.Blutregen:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.Blutzappel:BAAALAADCgcICAABLAAECgYIDAABAAAAAA==.',Bo='Bobfriskit:BAAALAAECgcIEAAAAA==.Boboro:BAAALAADCgIIAgAAAA==.Bonezy:BAAALAADCgMIAwAAAA==.Bookko:BAAALAAECgMIAwAAAA==.Boot:BAAALAAECgcIEgAAAA==.Borborygmus:BAAALAADCgQIBAAAAA==.',Br='Bradshoona:BAAALAAECgYIBgAAAA==.Braedron:BAAALAADCgYIBgABLAAECgYIEAABAAAAAA==.',Bu='Bubbleandrun:BAAALAADCggIDAABLAAECgYICgABAAAAAA==.Bullyray:BAAALAADCgEIAQAAAA==.Buroode:BAAALAAECgYIDAAAAA==.Busselton:BAAALAADCggICAAAAA==.',['Bé']='Béât:BAABLAAECoEUAAIIAAgIcySaAQAgAwAIAAgIcySaAQAgAwAAAA==.',Ca='Caperucita:BAAALAAECgYICgAAAA==.Carpe:BAAALAADCgEIAQAAAA==.Carrots:BAAALAADCggICAAAAA==.Caveira:BAAALAADCgYIDAAAAA==.',Ce='Cellwynn:BAAALAADCgUIBQAAAA==.Cevyl:BAAALAAECgMIAwAAAA==.',Ch='Champdp:BAABLAAECoEVAAIJAAgI1CGaAgD9AgAJAAgI1CGaAgD9AgAAAA==.Chaucher:BAAALAADCgIIAgAAAA==.Chauchi:BAAALAAECgQIBQAAAA==.Chazberry:BAAALAAFFAIIAgAAAA==.Chimeranaug:BAAALAAECgEIAgAAAA==.Chunksuave:BAAALAAECgYICQAAAA==.',Ci='Cillocybin:BAAALAAECgYICQAAAA==.',Cj='Cjs:BAAALAAECgIIAgAAAA==.',Cl='Cleavensegal:BAAALAADCgIIAgAAAA==.Clöüdÿ:BAAALAAECgYICgAAAA==.',Co='Cobbs:BAAALAADCgcICAAAAA==.Cocoraptor:BAAALAAECgYICgAAAA==.Colodelfuego:BAAALAADCggICAAAAA==.Cologa:BAABLAAECoEVAAIHAAgI2Rp5CwCNAgAHAAgI2Rp5CwCNAgAAAA==.Columbus:BAAALAAECgIIAwAAAA==.Confess:BAAALAAECgcIDwAAAA==.Congruentz:BAAALAADCgYIBgAAAA==.Coola:BAAALAAECgYICgAAAA==.Cooyon:BAAALAAECggIAgAAAA==.Copperbeard:BAAALAADCggICAABLAADCggIDgABAAAAAA==.Cornelius:BAAALAADCgUIBQAAAA==.Cosines:BAAALAAECgYIEAAAAA==.Cowsrule:BAAALAAECgQICQAAAA==.',Da='Daeio:BAAALAAECgIIAgAAAA==.Daggrim:BAAALAAECgYICgAAAA==.Dahyku:BAAALAAECgYIDQAAAA==.Damuro:BAAALAADCgcICwAAAA==.Darkaunnas:BAAALAAECgUIBQAAAA==.Darkmedian:BAEALAADCggICAABLAAECgcIDwABAAAAAA==.Darksorrow:BAAALAADCgYIBwAAAA==.',De='Deacon:BAAALAADCgEIAQAAAA==.Dedrick:BAAALAADCggIDwAAAA==.Deepzforya:BAAALAAECgMIBAAAAA==.Deified:BAAALAADCgcICQAAAA==.Deldor:BAAALAAECgEIAQAAAA==.Demonetizer:BAABLAAECoEWAAIKAAgIcyLoCQDkAgAKAAgIcyLoCQDkAgAAAA==.Demonicart:BAAALAADCgcIDgAAAA==.Denniecrane:BAEBLAAECoEVAAILAAgIrBcIFAARAgALAAgIrBcIFAARAgAAAA==.Devildrivèr:BAAALAADCgcICQAAAA==.',Di='Dimand:BAAALAADCgcIBwAAAA==.Diplol:BAAALAADCgcIBwAAAA==.',Do='Donttrustme:BAAALAAECgYICgAAAA==.Donttryit:BAAALAADCggICAAAAA==.Doominique:BAAALAADCggIAQAAAA==.Dozo:BAAALAAECgcIDQAAAA==.',Dr='Drama:BAAALAADCgcIBwAAAA==.Driptide:BAAALAADCggICAAAAA==.',Du='Dualipa:BAAALAAECgMIAwAAAA==.Dumbleklitz:BAAALAAECgQIBAABLAAECgYICwABAAAAAA==.Durids:BAAALAADCggICwAAAA==.Durían:BAAALAAECgMIAwABLAAECgYIDwABAAAAAA==.Dustÿ:BAAALAADCggICAAAAA==.Duub:BAAALAAECgMIBQAAAA==.',['Dü']='Dürn:BAAALAADCgcIDQABLAAECgYICQABAAAAAA==.',Ei='Eilesa:BAAALAADCgcIEgAAAA==.Einhardt:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.',El='Elila:BAAALAADCggIDgAAAA==.Elintha:BAAALAAECgYICgAAAA==.Ellja:BAAALAAECgYICgAAAA==.Ellwine:BAAALAADCgcIBwAAAA==.Eluned:BAAALAADCgcIBwAAAA==.',Em='Emmahotson:BAAALAAECgUIBQAAAA==.Emojake:BAAALAADCgQIAgAAAA==.Emrys:BAAALAAECgcIBwAAAA==.',Er='Erza:BAAALAAFFAIIAgAAAA==.',Es='Escaflowne:BAABLAAECoEWAAMMAAgIBCTHBAA2AwAMAAgIiyPHBAA2AwANAAEIaSVJIgBeAAAAAA==.Escanor:BAAALAAECgcIDQAAAA==.',Et='Ethorin:BAAALAADCggICQAAAA==.',Ev='Evelinada:BAAALAADCgMIAwABLAAECgYIDAABAAAAAA==.',Ex='Exception:BAAALAADCggICAABLAAECgQIBAABAAAAAA==.Exit:BAAALAAECgQIBAAAAA==.',Fa='Farmette:BAAALAAECgQIBQAAAA==.',Fe='Feardotdrop:BAAALAADCgQIBAAAAA==.Felbeard:BAABLAAECoEWAAIGAAgIkSHZBAAOAwAGAAgIkSHZBAAOAwAAAA==.Ferreday:BAAALAAECgIIAwAAAA==.',Fi='Fingoflin:BAAALAAECgMIAwAAAA==.',Fl='Flandi:BAAALAADCgYIAwAAAA==.Fleakertwo:BAABLAAECoEWAAIDAAgIzxH8DgAwAgADAAgIzxH8DgAwAgAAAA==.Flocko:BAAALAADCgYICAAAAA==.Floopchi:BAAALAAECgQICQAAAA==.Flói:BAAALAAECgYICwAAAA==.',Fo='Foddercannon:BAAALAAECgcIDgAAAA==.Forandya:BAAALAADCgcICQAAAA==.Foxycottin:BAAALAADCgUICQAAAA==.',Fr='Freezepop:BAAALAAECgYICQAAAA==.Friedrib:BAABLAAECoEVAAQOAAgIHiAFAwC7AgAOAAgIHiAFAwC7AgAPAAEI/wj3VQAyAAAQAAEI5gffTQAnAAAAAA==.Friskycow:BAEALAADCggICAABLAAECgcIFAAJAH8lAA==.Froostshok:BAAALAADCgUIBwAAAA==.Frostybuds:BAAALAAECgEIAQAAAA==.Frozal:BAAALAADCgYIBgAAAA==.',Fu='Fursona:BAAALAADCgcIBwAAAA==.Futralize:BAAALAAECgYICQAAAA==.',Ga='Galfuran:BAAALAAECgYICgAAAA==.Galise:BAAALAAECgMIAwAAAA==.Gangstapaly:BAAALAAECgYIBAAAAA==.Gangstaparty:BAAALAAECgEIAQABLAAECgYIBAABAAAAAA==.Gannarae:BAAALAADCgUIBQAAAA==.Garak:BAAALAADCgYIBgAAAA==.Garur:BAAALAAECgEIAQAAAA==.',Ge='Geicogecko:BAAALAAECgcIEAAAAA==.Genaveive:BAAALAAECgcIBwAAAA==.Getloke:BAAALAADCgcICgAAAA==.Getstitched:BAAALAADCgMIAwAAAA==.',Gi='Gimmix:BAAALAAECgMIBQAAAA==.',Gn='Gnomered:BAAALAADCggICAAAAA==.Gnottagnelf:BAAALAADCgcIDAAAAA==.',Go='Gobbylynn:BAAALAADCggIFQABLAAECgcIFAACANwjAA==.',Gr='Grimlo:BAAALAADCgcICgAAAA==.Grusomestab:BAAALAADCggIDQAAAA==.Gryzzle:BAAALAADCgYIBgAAAA==.',Gu='Gusterson:BAAALAAECgMIBAAAAA==.',Gw='Gwisztaxman:BAAALAAECgMIBgAAAA==.',Ha='Haint:BAAALAAECgYIDgAAAA==.Hairybumbum:BAAALAAECgYIDAAAAA==.Haldan:BAAALAADCggICAAAAA==.Hastra:BAAALAAECgQIBQAAAA==.Hatenine:BAAALAAECgQIBQAAAA==.',He='Healah:BAAALAAECgYIBgAAAA==.Healwheaton:BAAALAADCggIBgABLAAECgcIDwABAAAAAA==.Hegotthedrip:BAAALAAFFAIIAgAAAA==.Hellhowl:BAAALAADCgMIAwABLAAECgYIDQABAAAAAA==.',Hi='Hijackx:BAAALAAECgYIEAAAAA==.',Ho='Holdne:BAAALAADCgcIBwABLAAECgIIAwABAAAAAA==.Holiloa:BAAALAAECgYICQAAAA==.Holyburoode:BAAALAADCgYIBwABLAAECgYIDAABAAAAAA==.Holycampa:BAAALAAECgEIAgAAAA==.Holypoker:BAAALAAECgEIAgAAAA==.Hoodini:BAAALAAECgEIAQAAAA==.',Hu='Hukwa:BAAALAADCgcIBwAAAA==.Huntsweet:BAAALAADCgEIAQAAAA==.',['Hû']='Hûlkk:BAAALAAECgMIBgAAAA==.',Ic='Iced:BAABLAAECoEWAAMRAAgIdCAWCACjAgARAAcIGiEWCACjAgASAAUIrwn8DwD/AAAAAA==.',If='Ifeelnothing:BAAALAADCgQIBAABLAAECgMIBgABAAAAAA==.',Ig='Ignatowski:BAAALAAECgEIAQAAAA==.',Ii='Iindulgelag:BAAALAADCggIDwAAAA==.',Il='Ilinarae:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.Illnea:BAAALAAECgEIAQAAAA==.',Im='Imphasedup:BAABLAAECoEWAAMTAAgIZRdfIgD/AQATAAcICBdfIgD/AQAUAAIIbxMGNAB8AAAAAA==.',In='Inebrious:BAAALAAECgMIAwAAAA==.Inndra:BAAALAAECgIIAgAAAA==.',Is='Iseldir:BAAALAADCgUIBQAAAA==.Ishi:BAAALAADCggICAAAAA==.',It='Itsmäam:BAAALAAFFAIIAgAAAA==.',Iv='Ivale:BAAALAAECgYIDgAAAA==.',Ja='Jabamental:BAABLAAECoEUAAILAAcIPRyJEwAVAgALAAcIPRyJEwAVAgAAAA==.Jaded:BAAALAADCgcIDQAAAA==.Jamx:BAABLAAECoEUAAQGAAcIgRoYJACQAQAGAAUIbRoYJACQAQAVAAQIFxlYKQDbAAAFAAIIcwTxIwBfAAAAAA==.Jamzs:BAAALAADCgcIDgABLAAECgcIFAAGAIEaAA==.Janos:BAAALAADCgcIFAAAAA==.Java:BAAALAAECgYIEgAAAA==.',Je='Jerm:BAAALAADCggIEwAAAA==.Jessia:BAAALAAECgQICQAAAA==.',Jm='Jmy:BAAALAADCggICAABLAAECgcIFAAGAIEaAA==.',Jo='Jongi:BAAALAADCgcIBwAAAA==.Jorrethoi:BAAALAAECgQIBQAAAA==.',Ju='Jurble:BAAALAAECgYIEAAAAA==.Justborn:BAAALAADCgYIBwAAAA==.',['Jå']='Jåmmy:BAAALAADCggICAABLAAECgcIFAAGAIEaAA==.',Ka='Kabbu:BAAALAAECgMIBAAAAA==.Kaelord:BAAALAAECgMIBAAAAA==.Kaizer:BAABLAAECoEXAAIKAAgIGyM7BgAcAwAKAAgIGyM7BgAcAwAAAA==.Kalrakin:BAAALAADCgcIBwABLAAECgcIDwABAAAAAA==.Kaminari:BAAALAADCggICQABLAAECgYICQABAAAAAA==.Kardrig:BAAALAAECgIIAgAAAA==.Katarin:BAAALAADCgEIAQAAAA==.Katwoman:BAAALAAECgcIDwAAAA==.Kaylana:BAAALAADCggIDwABLAADCggIEgABAAAAAA==.Kaylanuh:BAAALAADCggIEgAAAA==.',Ke='Keleseth:BAAALAADCgYIBwAAAA==.Kelthal:BAAALAADCggIDgAAAA==.Kelthard:BAAALAAECgEIAQAAAA==.Kero:BAAALAADCgcICAAAAA==.',Ki='Kiingvvizard:BAAALAAECgMIBAAAAA==.Killercold:BAAALAADCggIDgAAAA==.Killzworkz:BAAALAADCgcICgAAAA==.Kissagarita:BAAALAAECgYICAABLAAFFAUICQAWAKwVAA==.Kissalicious:BAAALAAECgcIEAABLAAFFAUICQAWAKwVAA==.Kissception:BAACLAAFFIEJAAIWAAUIrBVVAADRAQAWAAUIrBVVAADRAQAsAAQKgRYAAxYACAiwHtILAHACABYABwiFINILAHACAAcABggeGVkbAMEBAAAA.Kisstrosity:BAAALAAECgYICQABLAAFFAUICQAWAKwVAA==.Kissubblegum:BAAALAADCgYIBgABLAAFFAUICQAWAKwVAA==.',Kl='Klítzhunter:BAAALAAECgYICwAAAA==.',Kn='Knotmyfault:BAAALAADCgcIBwAAAA==.',Ko='Kodoseeker:BAAALAAECgcIEAAAAA==.',Kr='Krean:BAAALAADCggIEgAAAA==.Krisali:BAABLAAECoEXAAIUAAgIFR4qBQCbAgAUAAgIFR4qBQCbAgAAAA==.Krisalii:BAAALAAECgMIAwABLAAECggIFwAUABUeAA==.',Ku='Kudrel:BAAALAAECgEIAQAAAA==.Kunar:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.Kunarr:BAAALAAECgYICgAAAA==.',Kv='Kviera:BAAALAAECgMIAwAAAA==.',['Kí']='Kíki:BAAALAAECgMIAwAAAA==.',Le='Legumes:BAAALAAFFAIIAgAAAA==.Leidiavolo:BAAALAADCgEIAQAAAA==.Lemage:BAABLAAECoEYAAMTAAgIRR/qDwCgAgATAAgIRR/qDwCgAgAUAAIIBQhkOABlAAAAAA==.Lennore:BAAALAAECgQICQAAAA==.',Li='Linchknight:BAAALAAECgUICAAAAA==.Linda:BAAALAAECgQICQAAAA==.Lioness:BAAALAADCgEIAQAAAA==.',Lk='Lkjfodsdirwo:BAAALAADCgEIAQAAAA==.',Lo='Loktad:BAAALAAECgYIEAAAAA==.Lonelytuna:BAAALAAECgMIAwAAAA==.Lousee:BAAALAAECgIIAgAAAA==.Lovable:BAAALAADCggIDAAAAA==.Loves:BAAALAAECgUICAAAAA==.',Lu='Lumindrenia:BAAALAADCggIEAAAAA==.Lunarfel:BAAALAAECgcIEAAAAA==.',Ly='Lyvola:BAABLAAECoEYAAIMAAgIXyC3DQCpAgAMAAgIXyC3DQCpAgAAAA==.',['Lä']='Lätêx:BAABLAAECoEUAAIMAAcIOiWUCQDkAgAMAAcIOiWUCQDkAgAAAA==.',Ma='Macktown:BAAALAAECgYIBgAAAA==.Madsquatch:BAAALAAECgcICgAAAA==.Maeghynne:BAAALAADCgUIBQAAAA==.Magello:BAAALAADCgUIBQAAAA==.Magicmeatxxl:BAAALAAECgcIDwAAAA==.Magusgobrr:BAAALAAECgYIEAAAAA==.Mahawker:BAAALAADCggIDgAAAA==.Makaveli:BAAALAADCgMIAwAAAA==.Malkoroth:BAAALAADCggICAAAAA==.Manafist:BAAALAADCgYIEgAAAA==.Margarito:BAAALAADCgQIBAAAAA==.Marth:BAAALAADCggIDQAAAA==.Maxvertrappn:BAAALAAECgYIBgAAAA==.Maxxypads:BAAALAADCggIDwAAAA==.',Mc='Mctrenbolone:BAAALAAFFAIIAgAAAA==.',Me='Median:BAEALAAECgcIDwAAAA==.Memebait:BAAALAAECgMIBAAAAA==.',Mi='Michael:BAAALAAECgUICAAAAA==.Milkedmoose:BAAALAAECgQICQAAAA==.Mistaclean:BAAALAADCgYIBgABLAAFFAQIBQALABkRAA==.',Mo='Moona:BAAALAAECgYIDQAAAA==.Moonberry:BAABLAAECoEVAAIRAAgIrRb/CwBRAgARAAgIrRb/CwBRAgAAAA==.Moonfireya:BAAALAADCgYICAAAAA==.Moonlock:BAAALAADCgcIEgAAAA==.Moowhere:BAAALAAECgcIDwAAAA==.Morbin:BAAALAAECgcICgAAAA==.Motomotoo:BAAALAADCgYIBgAAAA==.',Mt='Mtak:BAAALAAECggIEgAAAA==.',Mu='Mufflebutt:BAAALAADCgMIAwAAAA==.Muni:BAAALAADCggICQAAAA==.Munitionz:BAAALAADCgQIBAAAAA==.Murphdh:BAAALAAECgMIAwAAAA==.',My='Myriad:BAACLAAFFIEHAAIEAAQIsB5wAACOAQAEAAQIsB5wAACOAQAsAAQKgRwAAgQACAicJEgBACgDAAQACAicJEgBACgDAAAA.',['Má']='Máru:BAAALAADCgIIAgAAAA==.Máverik:BAAALAAECgEIAQAAAA==.',Na='Nannerpuss:BAAALAADCggIDAAAAA==.Naraynne:BAABLAAECoEWAAIWAAgIIRfGDwA/AgAWAAgIIRfGDwA/AgAAAA==.',Ne='Neechie:BAAALAADCggICAAAAA==.',Ni='Nidos:BAAALAAECgYIDgAAAA==.Nighthaven:BAAALAADCgcIEAAAAA==.Nightshade:BAAALAAECgYIDgAAAA==.',No='Nomerci:BAAALAADCggICAAAAA==.Novapal:BAAALAAECgcIEAAAAA==.',Ob='Obrahma:BAAALAADCggIDgAAAA==.',Oc='Ochnauq:BAAALAADCgcIBwAAAA==.',Od='Odehla:BAAALAADCgQIBAAAAA==.',On='Oniyume:BAAALAAECgYICgAAAA==.',Or='Orcall:BAAALAAFFAIIAgAAAA==.Orufus:BAAALAAECgEIAQAAAA==.',Os='Oserza:BAAALAADCggICgAAAA==.Osferth:BAAALAAECgEIAQAAAA==.',Pa='Pakku:BAABLAAECoEWAAIXAAgIRyAdAwD7AgAXAAgIRyAdAwD7AgAAAA==.Paladaine:BAAALAAECgYIBgAAAA==.Pallypocket:BAAALAADCgQIAgAAAA==.Panddora:BAAALAADCgIIAgAAAA==.Pandicus:BAAALAAECgYIDAAAAA==.Panny:BAAALAADCgcICwAAAA==.Paoot:BAAALAADCgYIBgABLAAECgcIDwABAAAAAA==.Papal:BAAALAADCgQIBAAAAA==.Paramyrddin:BAAALAAECgYIBgABLAAECgcIBwABAAAAAA==.',Pe='Peachmangos:BAAALAADCgcIDAAAAA==.Petty:BAAALAAECgIIAgAAAA==.',Ph='Phatsword:BAAALAAECgQIAwAAAA==.Phigon:BAAALAAECgYICgAAAA==.',Po='Potatodruid:BAAALAAECgYICQAAAA==.',Pr='Preem:BAAALAAECgEIAgAAAA==.Prÿss:BAAALAADCgMICAAAAA==.',Pu='Punchanaga:BAAALAADCgcIBgAAAA==.Pure:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.',Py='Pyrael:BAAALAADCgYICAAAAA==.Pyroblast:BAAALAAECgQIBwAAAA==.',Qu='Quancho:BAABLAAECoEUAAIYAAcIHxkyAwDqAQAYAAcIHxkyAwDqAQAAAA==.',Qw='Qwade:BAAALAAECgcIDwAAAA==.',Ra='Radishes:BAAALAAECgYIDwAAAA==.Rahlen:BAAALAAECgcICwAAAA==.Rakaman:BAAALAAECgMIAwAAAA==.Raká:BAAALAAECgEIAQAAAA==.Ramza:BAABLAAFFIEFAAIMAAMIIxquAQALAQAMAAMIIxquAQALAQAAAA==.Ranbou:BAAALAAFFAIIAgAAAA==.Rappidan:BAAALAAECgQICQAAAA==.Ratheron:BAAALAADCggIFAAAAA==.',Re='Reboot:BAAALAADCggICAABLAAECgcIEgABAAAAAA==.Redeemer:BAAALAADCggICAAAAA==.Relm:BAAALAADCggICgAAAA==.Repens:BAAALAAECgQIBAAAAA==.Restosterone:BAAALAAECgQIAwAAAA==.Retful:BAAALAAECgIIAgABLAAECggIFgAKAHMiAA==.Reverent:BAAALAAECgEIAgAAAA==.Revo:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.',Rh='Rhordrick:BAAALAAECgUICAAAAA==.',Ri='Rivën:BAAALAAECgYICQAAAA==.Rizefi:BAAALAADCgUIBQAAAA==.',Ro='Roquefort:BAAALAADCgcIEgAAAA==.Roz:BAAALAADCgEIAQAAAA==.',Ru='Runawaynow:BAACLAAFFIEFAAILAAQIGREZAQAuAQALAAQIGREZAQAuAQAsAAQKgRYAAgsACAitIlEBACwDAAsACAitIlEBACwDAAAA.Runelife:BAAALAAECgMIBgAAAA==.Runstrosity:BAAALAAECgcICgAAAA==.Runurrito:BAAALAAECgYIBwABLAAFFAQIBQALABkRAA==.',['Râ']='Râve:BAAALAADCgQIBAABLAADCggIDgABAAAAAA==.',Sa='Sadori:BAAALAADCgcIBwAAAA==.Sakarialana:BAAALAAECgIIAwAAAA==.Salani:BAAALAADCgcICgAAAA==.Samdeathfoot:BAAALAAECgQIBAAAAA==.Sankeman:BAAALAAECgYICQAAAA==.Sanq:BAAALAAECgYICgAAAA==.Saresil:BAAALAAECgUIBQAAAA==.Sashay:BAAALAAECgEIAQAAAA==.Sathmulrax:BAAALAADCgcIEwAAAA==.',Sc='Scape:BAAALAAECgYICQAAAA==.',Se='Seney:BAAALAADCggIEAAAAA==.Seyuri:BAAALAAECgMIBQAAAA==.Seán:BAAALAAECgQIBAAAAA==.',Sh='Shadowar:BAAALAAECgUICAAAAA==.Shadowbell:BAAALAAECgQICQAAAA==.Shadowgale:BAAALAADCgcIEgAAAA==.Shadowkatz:BAAALAAECgMIAwAAAA==.Shallwe:BAAALAADCggICAABLAAECgYICgABAAAAAA==.Shamonyou:BAAALAADCgYIBgAAAA==.Shantari:BAAALAADCgcICQAAAA==.Shayrpd:BAAALAADCggIDQAAAA==.Shelbster:BAAALAADCgcIBwAAAA==.Shimo:BAAALAAECgMIBAAAAA==.Shrektwondvd:BAAALAADCgcICgAAAA==.Shämeltoe:BAAALAAECgMIAwAAAA==.Shøckybalboa:BAAALAADCggICgABLAAECgYIBAABAAAAAA==.',Si='Sidekickz:BAAALAADCgcICwABLAAECgYIDgABAAAAAA==.Sigsbee:BAAALAAECgQIBQAAAA==.Sistervera:BAAALAADCgEIAQAAAA==.',Sk='Skarlett:BAAALAADCggIFQAAAA==.Skhorn:BAAALAAECgQICQAAAA==.Skinnybenis:BAAALAADCggIEQAAAA==.Skrüffy:BAAALAAECgEIAQAAAA==.',Sm='Smokedrib:BAAALAAECgIIAgABLAAECggIFQAOAB4gAA==.',Sn='Snoochie:BAAALAADCgYIBgAAAA==.Snoozgar:BAAALAAECgIIAgAAAA==.',So='Sodori:BAAALAADCggIEAAAAA==.Solariss:BAAALAADCgYICQABLAADCgYIEgABAAAAAA==.Solstice:BAAALAADCggICAAAAA==.',Sq='Squirmish:BAAALAADCgQIBAAAAA==.',St='Staar:BAAALAADCgcICwAAAA==.Stlshock:BAAALAAECgMIBQAAAA==.Stormscar:BAAALAAECgEIAQABLAAECggIGAATAEUfAA==.Strongdroid:BAAALAAECgEIAQAAAA==.Stéllabélla:BAAALAAECggIEwAAAA==.',Su='Substrate:BAAALAAECgQIBAAAAA==.Sudip:BAAALAADCgIIAwAAAA==.Sugarteets:BAAALAAECgMIAwAAAA==.Susie:BAAALAADCgIIAgAAAA==.',Sv='Svaval:BAABLAAECoEVAAIZAAgI8h8aAwC+AgAZAAgI8h8aAwC+AgAAAA==.',Sx='Sxypwnsmith:BAAALAADCgcICAAAAA==.',Sy='Sylilith:BAAALAADCgcIBwAAAA==.Synder:BAAALAAECgYIDQAAAA==.',['Sõ']='Sõren:BAAALAAECgYICgAAAA==.',Ta='Tacodelfuego:BAAALAADCgQIBAAAAA==.Tamedurmom:BAAALAAECgQIBwAAAA==.Tankinpánda:BAAALAAECgUICAAAAA==.Tanksalott:BAAALAADCgEIAQAAAA==.Tarekk:BAAALAAECgMIBgAAAA==.Tark:BAAALAADCggICAAAAA==.Taybrah:BAAALAAECgEIAQAAAA==.',Tb='Tbacon:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',Tc='Tchornobog:BAAALAADCgYIBgAAAA==.',Te='Tearssoul:BAAALAAECgEIAQAAAA==.Tehcountar:BAAALAAECgYIEAAAAA==.Terps:BAAALAAECgYIEAAAAA==.',Th='Thebeerwiz:BAAALAAECgYIDgAAAA==.Thelianne:BAAALAAECgMIBAAAAA==.Thorenis:BAAALAADCgUIBQAAAA==.Thorps:BAAALAAECgYIEAAAAA==.Thotitoldyou:BAAALAAECgYICQAAAA==.Thrusty:BAABLAAECoEVAAMMAAgIXiQcBgAeAwAMAAgIXiQcBgAeAwANAAEIAh+hJQBCAAAAAA==.Thugoneous:BAAALAAECgYICQAAAA==.Thvelios:BAAALAAECgQIBQAAAA==.',Ti='Tigerhug:BAAALAAECgIIAgAAAA==.Tigerpalm:BAAALAADCgYIBgAAAA==.Tilexer:BAAALAAFFAEIAQAAAA==.Timzion:BAAALAAECgcIEAAAAA==.',To='Tomerarenai:BAAALAAECgcIDQAAAA==.Touchedd:BAAALAAECgUIBQAAAA==.',Tr='Trapshotumad:BAAALAADCgMIAwAAAA==.Tredbarta:BAAALAADCgYIBgAAAA==.Trugi:BAAALAAECgYIDAAAAA==.Trîzzle:BAAALAAECggIEwAAAA==.',Tu='Tumi:BAAALAADCgUIBQAAAA==.Turag:BAAALAAECgQIBAAAAA==.Tuzza:BAAALAAECgEIAQAAAA==.',Tw='Twox:BAAALAAECgIIAgAAAA==.',Ty='Tymbyr:BAAALAAECgQICQAAAA==.Tyoka:BAAALAAECgIIAwAAAA==.Tyokå:BAAALAADCgMIAwAAAA==.',Un='Unole:BAAALAADCgQIBAAAAA==.',Us='Uskthaniel:BAAALAADCgUIBQAAAA==.',Va='Vaalkad:BAAALAAECgIIAgAAAA==.Vadiem:BAAALAADCgMIAwAAAA==.Vaelgrym:BAAALAADCggICAAAAA==.Vaelyss:BAAALAADCggIDgAAAA==.Vafanopoli:BAAALAADCggICAAAAA==.Valvadin:BAAALAADCgcIBwAAAA==.Valvazug:BAAALAAECgEIAQAAAA==.Vanished:BAAALAAECgYICgAAAA==.Varinth:BAAALAAECgQIBQAAAA==.',Ve='Vecidus:BAAALAADCgcIBwAAAA==.Velassi:BAAALAAECgcIDwAAAA==.Verii:BAAALAAECgYICQAAAA==.',Vi='Vintari:BAAALAAECgQIBQAAAA==.',Vo='Voidswish:BAAALAAECgUICAAAAA==.Volkai:BAAALAADCgcIBwAAAA==.',Vr='Vriks:BAAALAADCggICAAAAA==.',Wa='Waddles:BAAALAADCgcICQAAAA==.Watsuki:BAAALAAECgYIBgAAAA==.Wazerk:BAAALAADCgYIBgAAAA==.',Wh='Whely:BAEBLAAECoEUAAIJAAcIfyWtAgD5AgAJAAcIfyWtAgD5AgAAAA==.Whitegoodman:BAAALAAECgIIAgAAAA==.Whitewolfs:BAAALAADCgMIAwAAAA==.',Wi='Wilcoxx:BAAALAADCgMIAwABLAADCggICAABAAAAAA==.Wilcozz:BAAALAADCggICAAAAA==.Wildclefairy:BAAALAAECgYICwAAAA==.Willen:BAAALAADCgcICgAAAA==.Wiremaiden:BAAALAAECgQIBQAAAA==.Wizhold:BAAALAAECgIIAwAAAA==.',['Wí']='Wíx:BAAALAADCggICAAAAA==.',['Wî']='Wîxx:BAAALAAFFAIIAgAAAA==.',Xa='Xantizzle:BAAALAAECgYICAAAAA==.',Xi='Xitsilab:BAAALAAECgEIAQAAAA==.',Xy='Xylna:BAAALAADCgcIEgAAAA==.',Ya='Yacuto:BAAALAAFFAIIAgAAAA==.Yanasampanno:BAAALAAECgYICQAAAA==.',Yo='Yopaat:BAAALAADCggIFgABLAAECgUIBQABAAAAAA==.',Za='Zacheeus:BAAALAAFFAIIAgAAAA==.Zamarion:BAAALAADCgIIAgAAAA==.Zambaataa:BAAALAADCgEIAQAAAA==.Zardragon:BAAALAAFFAIIAgAAAA==.Zariina:BAAALAAECgEIAgAAAA==.',Ze='Zelethor:BAAALAAFFAIIAgAAAA==.Zemfister:BAAALAAECgcICgABLAAECggICAABAAAAAA==.Zenji:BAAALAAECgIIAgAAAA==.Zephiatan:BAAALAAECgEIAQAAAA==.',Zi='Ziluwa:BAABLAAECoEVAAMTAAgIRhv4EgB/AgATAAgIRhv4EgB/AgAUAAEIywUKSAAlAAAAAA==.',Zo='Zod:BAAALAAECgEIAQAAAA==.Zoosh:BAAALAADCgYIBgAAAA==.Zooshbringer:BAAALAAECgEIAQAAAA==.Zooshcicle:BAAALAADCgEIAQAAAA==.',Zu='Zulgrin:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end