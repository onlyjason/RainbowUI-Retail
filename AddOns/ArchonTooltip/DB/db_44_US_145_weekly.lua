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
 local lookup = {'Rogue-Assassination','Rogue-Outlaw','DeathKnight-Frost','Unknown-Unknown','Monk-Windwalker','Warlock-Affliction','Hunter-Marksmanship','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Mage-Arcane','Evoker-Devastation','DemonHunter-Havoc','Evoker-Preservation','Rogue-Subtlety','Druid-Feral','Shaman-Enhancement','Paladin-Retribution','Priest-Discipline','Shaman-Elemental','Paladin-Holy','DemonHunter-Vengeance','Hunter-BeastMastery','Mage-Frost','Warrior-Protection',}; local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aahrya:BAAALAAECgUICAAAAA==.Aanassu:BAAALAADCgUICAAAAA==.',Ad='Adan:BAABLAAECoEWAAMBAAgI4RtmCACmAgABAAgI4RtmCACmAgACAAEIuAZBDgA1AAABLAAFFAYICQADAGQjAA==.',Ae='Aeonnax:BAAALAADCgYICAAAAA==.Aevisea:BAAALAADCggICgABLAADCggICwAEAAAAAA==.',Ag='Agnodike:BAAALAADCgcIBwAAAA==.',Ai='Aidan:BAABLAAECoEWAAIFAAgIBiWjAQA6AwAFAAgIBiWjAQA6AwABLAAFFAYICQADAGQjAA==.Aileron:BAAALAAECgYIDQAAAA==.',Ak='Akari:BAAALAADCgIIAgAAAA==.Akshana:BAAALAAECgIIAgAAAA==.',Al='Alcore:BAAALAAECgEIAQAAAA==.Aldoron:BAAALAAECggICQAAAA==.Aldrigor:BAAALAADCggIDwAAAA==.Alett:BAAALAAECgMIBAAAAA==.Alivathus:BAAALAAECgcIDQAAAA==.',An='Anachron:BAAALAAECgEIAQAAAA==.Angriff:BAAALAAECgMIAwAAAA==.',Ar='Araina:BAAALAADCgcIDQAAAA==.Arbarkm:BAAALAAECggIBgAAAA==.Arcelf:BAAALAADCggIDgAAAA==.Archie:BAAALAADCgIIAgAAAA==.Artemix:BAAALAADCgMIAgAAAA==.',As='Ashenclaw:BAAALAAECgMIBAAAAA==.Aspinks:BAAALAADCgcIBwABLAAECgcIEAAEAAAAAA==.Aspirincess:BAAALAADCgQIBgAAAA==.Asra:BAABLAAECoEXAAIGAAgIUB41AQDeAgAGAAgIUB41AQDeAgAAAA==.Astragalus:BAAALAADCgcIDwAAAA==.',Au='Auxmage:BAAALAAECgQIBAAAAA==.',Av='Availl:BAAALAAECgMIBQAAAA==.Avinôx:BAABLAAECoEVAAIHAAgIKx07BwCyAgAHAAgIKx07BwCyAgAAAA==.',Ay='Aydan:BAACLAAFFIEJAAIDAAYIZCMLAACNAgADAAYIZCMLAACNAgAsAAQKgRgAAgMACAiKJmQAAIkDAAMACAiKJmQAAIkDAAAA.Aylan:BAAALAADCgcIEQAAAA==.',Az='Aziera:BAAALAADCggICwAAAA==.Azumaa:BAAALAAECgEIAQAAAA==.Azureth:BAAALAADCggIFwAAAA==.Azzinoth:BAAALAAECgUICAAAAA==.',Ba='Baalzack:BAAALAADCgcIEQAAAA==.Bacnmac:BAAALAAECggIEQAAAA==.Baiwushi:BAAALAAECgYICAAAAA==.Balbit:BAABLAAECoEXAAIGAAgINyJfAABIAwAGAAgINyJfAABIAwAAAA==.Ballock:BAAALAAECgYICwAAAA==.',Be='Bearagorn:BAAALAADCggICAAAAA==.Beep:BAAALAADCgYIBgAAAA==.Beherit:BAAALAADCgcICAAAAA==.Belaghal:BAAALAADCggIDQAAAA==.',Bi='Bifwelington:BAAALAAECgEIAQAAAA==.Biggles:BAECLAAFFIEFAAIIAAMI+xktAQApAQAIAAMI+xktAQApAQAsAAQKgR4AAggACAhqIZkCAPECAAgACAhqIZkCAPECAAAA.',Bl='Blademedaddy:BAAALAADCgEIAQAAAA==.Blaithe:BAAALAADCgUICAAAAA==.Blobney:BAACLAAFFIEGAAIJAAMI3iUFAgBKAQAJAAMI3iUFAgBKAQAsAAQKgRgABAkACAjSJhYAAKEDAAkACAjSJhYAAKEDAAYABAgCIKYMAHMBAAoAAggRI98uALoAAAAA.Blueblazes:BAAALAAECgIIAgAAAA==.Bluechip:BAAALAADCggICAABLAAECgIIAgAEAAAAAA==.Blueeagle:BAAALAAECgEIAQAAAA==.',Bo='Boldalgaz:BAEBLAAECoEVAAILAAgIyhyNDACZAgALAAgIyhyNDACZAgAAAA==.',Br='Braum:BAAALAAECgUIBwAAAA==.Brazlor:BAAALAAECgIIBAAAAA==.Brendel:BAAALAAECgIIAgAAAA==.Brikz:BAAALAAECgQICAAAAA==.Brohaha:BAAALAADCggICAAAAA==.',Bu='Bubort:BAAALAADCggICAAAAA==.Bucknado:BAABLAAECoEaAAIMAAcIdxb4HgAYAgAMAAcIdxb4HgAYAgAAAA==.Burakurue:BAAALAADCgYIBgAAAA==.Butterflyy:BAAALAAECgEIAQAAAA==.',Ca='Caleis:BAAALAADCgYICQAAAA==.Casaric:BAAALAADCggIDwAAAA==.',Ce='Celestial:BAAALAAECgUICgAAAA==.',Ch='Charger:BAAALAADCgIIAgAAAA==.Charlok:BAAALAAECgIIAgAAAA==.Chcknmcnuget:BAAALAAECgMIAwAAAA==.Cheen:BAAALAADCgcICAAAAA==.Chifarm:BAAALAAECgMIAwAAAA==.Christobol:BAAALAAECgQICwAAAA==.Chupacabra:BAAALAAECgIIAgAAAA==.Chuyz:BAAALAADCggIEwAAAA==.Chuyzz:BAAALAAECgEIAQAAAA==.',Ci='Cilelienea:BAAALAADCgYIBgAAAA==.',Cl='Clickchi:BAAALAADCgcIEQAAAA==.',Co='Constara:BAAALAADCgcIDAAAAA==.Cordeliaa:BAAALAAECgYIBgAAAA==.Corkster:BAAALAAECgEIAQAAAA==.',Cr='Crimm:BAAALAAFFAIIAgABLAAFFAYIDQANAOkgAA==.Crista:BAAALAADCgMIAwAAAA==.Crunch:BAAALAAECgcIDwAAAA==.Crystaz:BAAALAAECgYIDgAAAA==.',Cs='Cshaugh:BAAALAAECgYIBgAAAA==.',Cy='Cynthor:BAAALAAECgQIBgAAAA==.',Da='Dabz:BAAALAAECgEIAQAAAA==.Daddymech:BAAALAADCgcIDAAAAA==.Daenys:BAAALAADCgEIAgAAAA==.Dahyun:BAAALAAECgMIAwAAAA==.Dalelor:BAAALAAECgIIAgAAAA==.Damnatíon:BAAALAAECggIAgAAAA==.Darala:BAAALAADCggICAAAAA==.Darcie:BAAALAAECgYIBwAAAA==.Dargeth:BAAALAAECgMIBAAAAA==.Darthflamed:BAAALAADCggICAABLAAECgYICwAEAAAAAA==.Davinah:BAAALAADCgEIAQAAAA==.Davybopit:BAAALAADCgYIDAAAAA==.Daylia:BAAALAADCggICAAAAA==.',De='Deathcows:BAAALAADCgYIBgAAAA==.Delmus:BAAALAADCgUICAABLAADCgcICQAEAAAAAA==.Delphinae:BAAALAAECgIIAgAAAA==.Derpalaherp:BAAALAADCgUICAAAAA==.Devia:BAAALAADCggIDQAAAA==.Deyvaen:BAAALAADCgQIBAAAAA==.',Dh='Dhae:BAAALAAECgEIAQAAAA==.',Di='Dirtyfighter:BAAALAAECgMIAwAAAA==.Dirtylock:BAAALAADCgcICwABLAAECgMIAwAEAAAAAA==.Discosticks:BAAALAADCgcIBwAAAA==.',Dj='Djfunky:BAAALAAECgMIAwAAAA==.',Do='Doodman:BAEALAAECgMIBwAAAA==.Doodmang:BAEALAADCgIIAgABLAAECgMIBwAEAAAAAA==.Dorron:BAAALAADCgYIBAAAAA==.',Dr='Dragontorpdo:BAAALAADCgEIAQAAAA==.Dragonviper:BAAALAADCgMIAwAAAA==.Drslay:BAAALAADCgcIBwAAAA==.',Du='Dumbclass:BAAALAADCgcIDQABLAAECggIHgAJAM0hAA==.',Dw='Dwelknarr:BAAALAAECgIIAgAAAA==.',Dy='Dyore:BAAALAAECgEIAgAAAA==.',['Dä']='Dämonjägger:BAAALAADCgUICQAAAA==.',['Dø']='Døpamine:BAAALAADCgcIAwAAAA==.',Ea='Eadric:BAAALAAECgIIAgAAAA==.Earendur:BAAALAADCgcICAAAAA==.',Ed='Edallen:BAAALAADCggICAAAAA==.',El='Elaise:BAAALAAECgMIAwAAAA==.Elbrujo:BAAALAAECgMIBQAAAA==.Elden:BAAALAADCgUIBQAAAA==.Ellipsis:BAAALAAECgYICwAAAA==.Elñeco:BAAALAADCgcIBwAAAA==.',Em='Emaytete:BAAALAADCggICgAAAA==.Emayteteheww:BAAALAADCgUIBQAAAA==.Empirial:BAAALAAECgEIAQAAAA==.',Et='Ethaerielle:BAAALAADCgcICAAAAA==.',Fe='Feargasma:BAAALAADCggICAAAAA==.Felflamel:BAAALAAECgYICwAAAA==.Felfook:BAAALAAECgMIBAAAAA==.Felystmagi:BAAALAADCggICAAAAA==.Feralized:BAAALAAECgIIAwAAAA==.',Fk='Fkincarebear:BAAALAADCgQIBgAAAA==.',Fl='Flax:BAAALAADCgIIAgAAAA==.Flores:BAAALAAECgIIAgAAAA==.Flurryfarm:BAAALAADCgIIAgAAAA==.',Fr='Franks:BAAALAADCgUIBQAAAA==.Fronks:BAAALAADCgcIBwAAAA==.Frozenhawk:BAAALAADCgcIBwAAAA==.',Ga='Galaesa:BAAALAADCgcIDQAAAA==.Gallarlyn:BAAALAAECgEIAQAAAA==.Gamelia:BAAALAADCgcICQAAAA==.Gary:BAAALAAECgMIAwAAAA==.Gashed:BAAALAADCggIEAAAAA==.',Ge='Geewilkr:BAAALAAECgIIBAAAAA==.Gerhart:BAAALAAECgIIAgAAAA==.',Gh='Ghostsham:BAAALAAECgYICQABLAAECggIHgAJAHQlAA==.',Gl='Glamizon:BAAALAADCggICAAAAA==.Glass:BAAALAADCgYIBgABLAAECggIFwAGADciAA==.',Gn='Gnarfarm:BAAALAAECgMIAwAAAA==.',Go='Go:BAAALAAECgIIAgABLAAECggIEwAEAAAAAA==.Goniff:BAAALAAECgYICwAAAA==.Goransk:BAAALAADCgcICQAAAA==.Gormash:BAAALAAECgEIAQABLAAECgEIAQAEAAAAAA==.Gorsk:BAAALAADCgUIBQABLAADCgcICQAEAAAAAA==.',Gr='Graemyste:BAAALAADCgMIAwAAAA==.Graevoak:BAAALAADCgUIBQABLAAECgEIAQAEAAAAAA==.Grubber:BAAALAAECgMIAwAAAA==.Grüb:BAAALAADCgMIAwABLAAECgMIAwAEAAAAAA==.',Gu='Guntran:BAAALAAECgEIAQAAAA==.',Gw='Gwenixx:BAAALAADCgcIEQAAAA==.Gwouncegeebl:BAAALAADCggICAABLAAFFAUICwANAMAiAA==.',Ha='Haghlan:BAAALAADCggICAAAAA==.Halios:BAAALAAECgEIAgAAAA==.Hamorina:BAAALAAECgYICwAAAA==.Hardtohurt:BAAALAADCgcIBwAAAA==.Hawke:BAAALAADCggICAAAAA==.',He='Heckfire:BAAALAAECgMIBQAAAA==.Hellifiknow:BAAALAADCggIDQABLAAECgMIBAAEAAAAAA==.',Hi='Hiruzèn:BAAALAAECgMIAwAAAA==.',Ho='Holypwr:BAAALAAECgQICQAAAA==.Hondar:BAAALAADCgcICAAAAA==.Hondarr:BAAALAADCgYIBgAAAA==.Honkinhammer:BAAALAAECgIIAgAAAA==.Horris:BAAALAAECgQICgAAAA==.Hotdumpling:BAAALAAECgIIAgAAAA==.',Hu='Huegarak:BAAALAAECgIIAgAAAA==.Hummockdwell:BAAALAAECgcICwAAAA==.Huntrium:BAAALAAECgIIAgAAAA==.Hurl:BAAALAADCgUIBQAAAA==.',Hy='Hyle:BAAALAADCggIEAAAAA==.',Ib='Ibuprofen:BAAALAAECgQIBwAAAA==.',Il='Illidad:BAABLAAECoEXAAIOAAgIpyEeCQDvAgAOAAgIpyEeCQDvAgAAAA==.Illuminator:BAAALAAECgIIAgAAAA==.',In='Inspectadeck:BAABLAAECoEXAAIJAAgIjBlJEABOAgAJAAgIjBlJEABOAgAAAA==.',Is='Istariel:BAABLAAECoEeAAQJAAgIdCWrBgDoAgAJAAcIQSWrBgDoAgAKAAUIWSMBEACHAQAGAAIIkR5RGAC+AAAAAA==.',Ja='Jasmines:BAAALAADCggIDgAAAA==.Jazu:BAAALAAECgcIDAAAAA==.',Je='Jerks:BAAALAAECgQICQAAAA==.',Jo='Jofu:BAAALAAECgYIBAAAAA==.Jolann:BAAALAADCgUICAAAAA==.Jorrell:BAAALAAECgMIBQAAAA==.Joval:BAAALAADCgcIDgAAAA==.Jozeph:BAAALAAECgYIBAAAAA==.',Ju='Juantoof:BAAALAAECgQICAAAAA==.Junknuts:BAAALAADCgUICAAAAA==.',Ka='Kaalar:BAAALAAECgQIBwAAAA==.Kaestirael:BAAALAADCgcIBwAAAA==.Kambala:BAAALAADCgMIAwAAAA==.Kamoura:BAAALAAECgMIBQAAAA==.Karmen:BAACLAAFFIEFAAIPAAMI6CHvAAA/AQAPAAMI6CHvAAA/AQAsAAQKgR4AAg8ACAhJIO8BAM8CAA8ACAhJIO8BAM8CAAAA.Karnara:BAAALAADCggIDQAAAA==.Karnatron:BAAALAADCgcIEQABLAADCggIDQAEAAAAAA==.Karnillidan:BAAALAADCgMIAwABLAADCggIDQAEAAAAAA==.Karnvoid:BAAALAADCgYIBgABLAADCggIDQAEAAAAAA==.Kaylea:BAAALAAFFAIIAgAAAA==.',Ke='Keattzxd:BAACLAAFFIEFAAMBAAMI/B0kAwDXAAABAAIIkiEkAwDXAAAQAAEIzxYiBABSAAAsAAQKgR4AAxAACAiDJWkAAEsDABAACAjfJGkAAEsDAAEACAj5Iv0DAAYDAAAA.Kennagi:BAAALAADCgcIDAAAAA==.Kenshunterl:BAAALAAECgIIAgAAAA==.Ketch:BAAALAADCgcIBwAAAA==.',Kh='Khovastis:BAACLAAFFIEFAAIRAAMITBjQAAAOAQARAAMITBjQAAAOAQAsAAQKgR4AAhEACAgzI24BABYDABEACAgzI24BABYDAAAA.',Ki='Kianll:BAAALAAECggICAAAAA==.Kitchntabls:BAACLAAFFIEFAAIOAAMIWA4IBAD+AAAOAAMIWA4IBAD+AAAsAAQKgRwAAg4ACAj/IJ4IAPYCAA4ACAj/IJ4IAPYCAAAA.',Kn='Knîghtmârê:BAAALAADCggICAAAAA==.',Ko='Koenji:BAABLAAECoEcAAISAAgINyClAQDtAgASAAgINyClAQDtAgAAAA==.Korenn:BAAALAADCgUIBQAAAA==.',['Kä']='Käne:BAAALAADCggIEAAAAA==.',La='Lannor:BAAALAADCgcIEQAAAA==.Lap:BAAALAADCgYIBgAAAA==.',Le='Legimp:BAAALAAECgIIAgAAAA==.Lerann:BAAALAADCggIEQAAAA==.Lewdcifer:BAAALAADCgcIBwAAAA==.Leyeston:BAAALAADCgcIBwAAAA==.',Li='Lightandfit:BAAALAAECgEIAQAAAA==.Lillea:BAAALAAECgMIBQAAAA==.',Lo='Lockcookies:BAAALAADCgYIBgAAAA==.Loktalaan:BAABLAAECoEWAAISAAgImhaTAwBoAgASAAgImhaTAwBoAgAAAA==.Lookinglimbo:BAAALAADCgIIAgAAAA==.Lothartar:BAAALAAECgIIAgAAAA==.',Lp='Lpz:BAAALAADCgQIBAAAAA==.',Lu='Lucien:BAAALAAECgUICwAAAA==.Lumenati:BAEALAADCgcIDgAAAA==.',Ly='Lyfeguard:BAAALAADCggIEAAAAA==.',Ma='Maddeath:BAAALAAECgMIBQAAAA==.Magrztorpedo:BAAALAADCgQIBAAAAA==.Mahito:BAAALAAECgYIDwAAAA==.Malianas:BAAALAAECgUIBQAAAA==.Malivath:BAAALAAECgIIAgAAAA==.Mallenroh:BAAALAADCggIDwAAAA==.Manawarrx:BAAALAADCgEIAQABLAAECggIFQATADolAA==.Marascelle:BAAALAADCgYIBgAAAA==.Marderer:BAAALAAECgMIAwAAAA==.Mariuss:BAABLAAECoEeAAIUAAgImRwbAQClAgAUAAgImRwbAQClAgAAAA==.Marmalade:BAAALAAECgIIAgAAAA==.Masakari:BAAALAAECgMIBQAAAA==.Mattðaemon:BAAALAADCgUIBwAAAA==.Maulfarm:BAAALAAFFAMIBAAAAA==.Mazzlock:BAAALAAECgYIDQAAAA==.',Me='Megameow:BAAALAAECgEIAQAAAA==.Melunia:BAAALAADCgEIAQAAAA==.Mercuria:BAAALAADCgcIEQAAAA==.Meriel:BAAALAAECgYIBwAAAA==.Metaclass:BAAALAAECgIIAgABLAAECgMIBQAEAAAAAA==.',Mi='Mistybeaver:BAAALAAECgEIAQAAAA==.Miztie:BAAALAADCggICAAAAA==.',Mo='Mobius:BAAALAAECgMIAwAAAA==.Monkpowa:BAAALAADCggICAAAAA==.Moondrius:BAAALAAECgQICgAAAA==.Mooseknukle:BAAALAADCgEIAQAAAA==.Moosk:BAAALAADCgIIAgAAAA==.Mort:BAAALAAECgIIAgAAAA==.Moziaki:BAAALAADCgEIAQAAAA==.',Ms='Msds:BAAALAAECgIIAgAAAA==.',Mu='Mulch:BAAALAAECgYICwAAAA==.Muscles:BAAALAADCgMIAwAAAA==.',My='Mybelle:BAAALAADCggIDwAAAA==.Mysticle:BAAALAADCgcIEQAAAA==.Mythaltis:BAAALAAECgMIBQAAAA==.',Na='Namielle:BAAALAADCgEIAQAAAA==.Narache:BAAALAAECgEIAQAAAA==.Narr:BAAALAADCgcIBwAAAA==.',Ne='Necrodyn:BAAALAADCgEIAQABLAAECgYICQAEAAAAAA==.Necrokai:BAAALAAECgYICQAAAA==.Necromyst:BAAALAADCgcIBwABLAAECgYICQAEAAAAAA==.Netherwolf:BAAALAAECgIIAgAAAA==.',Ni='Niddemos:BAAALAAECgEIAQAAAA==.',No='No:BAABLAAECoEWAAITAAgIQSDYFABXAgATAAgIQSDYFABXAgAAAA==.Noctix:BAAALAAECgQIBQAAAA==.Noctula:BAAALAAECgMIAwABLAAECgYICQAEAAAAAA==.Nooblette:BAAALAADCggIFgAAAA==.Nozok:BAAALAADCgcIEQAAAA==.',Ny='Nytkiller:BAAALAADCgYICAAAAA==.Nyzul:BAAALAADCgcICQAAAA==.',['Nî']='Nînjázömbáé:BAAALAADCggICAAAAA==.',Oa='Oakenheim:BAAALAADCggICAAAAA==.',Of='Offtank:BAAALAADCgEIAQAAAA==.',On='Onebuttonman:BAAALAADCgQIBAAAAA==.',Op='Opallea:BAAALAADCgcICQABLAADCgcICQAEAAAAAA==.Oppa:BAAALAADCgUIBgABLAADCgcICQAEAAAAAA==.',Or='Orch:BAAALAADCggIEAAAAQ==.',Ov='Overclocked:BAAALAAECgcIEAAAAA==.',Pa='Panchov:BAAALAADCgUIBgAAAA==.',Pe='Pendojo:BAAALAAECgcIDQAAAA==.Pendovoker:BAAALAADCggICAAAAA==.',Ph='Phandros:BAAALAAECgMIBgAAAA==.Phoebz:BAAALAADCgcIBwAAAA==.',Pi='Pip:BAACLAAFFIEFAAIVAAMIqx3hAQAoAQAVAAMIqx3hAQAoAQAsAAQKgR4AAhUACAirJaoBAGIDABUACAirJaoBAGIDAAAA.Pixie:BAAALAAECgcIDAAAAA==.',Po='Pookiemonstr:BAAALAADCggIDwAAAA==.',Pr='Prizrak:BAAALAADCggICAABLAAECggIHgAJAHQlAA==.Project:BAAALAADCgEIAQAAAA==.',Pu='Purplepete:BAAALAAECgMIAwAAAA==.',Qu='Quilbetrez:BAAALAADCgcIBwAAAA==.',Ra='Raegar:BAAALAADCgEIAQAAAA==.Raikai:BAAALAADCgYIBgABLAADCggIEQAEAAAAAA==.Rakury:BAAALAAECgIIAgAAAA==.Randinestine:BAAALAAECgIIAgAAAA==.Rasa:BAABLAAECoEYAAIWAAgI5hfpCAA3AgAWAAgI5hfpCAA3AgAAAA==.Ratdh:BAAALAAECgEIAQAAAA==.Raulothim:BAAALAAECgUIBQAAAA==.',Re='Reanlor:BAAALAAECgEIAQAAAA==.Reveus:BAAALAADCggIEAAAAA==.',Rh='Rhaenes:BAAALAADCgYIBgAAAA==.Rhicc:BAAALAAECgQIBwAAAA==.',Ri='Ricemachinex:BAABLAAECoEeAAQJAAgIzSFOCgCnAgAJAAgIzSBOCgCnAgAKAAUI1h6yFQBaAQAGAAEIkAVTKgBGAAAAAA==.Rizhky:BAAALAAECgMIBQAAAA==.Rizrilarex:BAAALAADCgUIBQAAAA==.',Ro='Robinwho:BAAALAADCgcIBwABLAAECgMIBQAEAAAAAA==.Roflclap:BAAALAADCggICAAAAA==.Rokthul:BAAALAADCgYIBgAAAA==.',Sa='Sanguinus:BAAALAADCgcIBwAAAA==.Saruh:BAAALAADCgcIBwAAAA==.Sassparilluh:BAAALAADCgcIEAAAAA==.',Sc='Scholoman:BAAALAAECgYIBgAAAA==.Scoron:BAAALAADCgUIAQAAAA==.Scruffmcbuff:BAAALAADCggIBAABLAAECgUICAAEAAAAAA==.',Se='Seerjonn:BAAALAAECgYIAwAAAA==.Severusevans:BAAALAAECgUICgAAAA==.Sevmage:BAAALAADCgYIBgABLAAECgUICgAEAAAAAA==.',Sh='Shackleßolt:BAAALAAECgUIBwAAAA==.Shadowplay:BAAALAADCgIIAgAAAA==.Shadowsspawn:BAAALAADCgEIAQAAAA==.Shamallow:BAAALAADCgUICAAAAA==.Shammish:BAAALAADCgcIBwAAAA==.Shammunition:BAAALAAECgYIDAAAAA==.Shartz:BAAALAAECgMIBQAAAA==.Shaysa:BAAALAAECgYIBgAAAA==.Shootyrob:BAAALAAECgQIBAAAAA==.Shroom:BAAALAADCggIEAAAAA==.',Si='Simpleebarky:BAABLAAECoEVAAITAAgIOiUEAgBoAwATAAgIOiUEAgBoAwAAAA==.Sistafista:BAAALAADCgYIBgAAAA==.',Sk='Skarlotta:BAAALAADCgMIAwAAAA==.Skuid:BAAALAADCgMIAwAAAA==.',Sl='Sladex:BAAALAAECgIIAgAAAA==.Sleeptoken:BAAALAADCgUIBwAAAA==.Sleezy:BAAALAAECgcIDgAAAA==.',Sn='Sneaki:BAABLAAECoEVAAQBAAgIZx1xDABZAgABAAcIvx5xDABZAgAQAAcIsBKYBQDQAQACAAQIERNGCAAJAQAAAA==.',So='Soarseas:BAAALAADCgYIBgAAAA==.Solaras:BAAALAADCggICAAAAA==.Sommin:BAAALAADCgIIAgAAAA==.Sookie:BAAALAADCgIIAgABLAADCgcICQAEAAAAAA==.Sorn:BAAALAADCgYIBgAAAA==.',Sp='Spankmyflank:BAAALAADCgcICQAAAA==.Sprinklez:BAAALAADCggICAAAAA==.Spurb:BAAALAADCgcIFQAAAA==.Spywodwaggin:BAAALAADCgEIAQAAAA==.',St='Stabbyfinch:BAAALAADCggIFwAAAA==.Steplok:BAAALAAECgUICAAAAA==.Stonestriker:BAAALAAECgIIAgAAAA==.Stooben:BAAALAAFFAEIAQAAAA==.Sturge:BAAALAAECgQIBAAAAA==.',Su='Sulfurica:BAAALAADCgUICAABLAADCgcICQAEAAAAAA==.Sunsetyellow:BAAALAADCgcIBwABLAAECggIFwAOAKchAA==.',Sw='Sweetbee:BAAALAAECgMIBAAAAA==.Sweetivy:BAAALAAECgIIAgAAAA==.',Sx='Sxlhrassment:BAAALAAECgMIBQAAAA==.',Sy='Syanalody:BAAALAADCgcICwAAAA==.',['Så']='Såmhåin:BAAALAADCgEIAQAAAA==.',Ta='Tactics:BAAALAADCgcIBwAAAA==.Taeron:BAAALAADCgQIBAAAAA==.Tanstaafl:BAAALAADCgcIBwAAAA==.Taralom:BAAALAAECgIIAgAAAA==.Taryon:BAAALAAECgEIAQAAAA==.Taz:BAEBLAAECoEVAAMXAAgIhRi8BgAQAgAXAAYIih68BgAQAgAOAAgIrRC1IwDnAQAAAA==.Tazroc:BAAALAADCgEIAQAAAA==.',Te='Tenevoy:BAAALAADCgYIBgABLAAECggIHgAJAHQlAA==.Teuton:BAAALAAECgMIAwAAAA==.',Th='Thadex:BAAALAADCgcIDQAAAA==.Thaldrin:BAABLAAECoETAAIDAAgIVyRsBAAsAwADAAgIVyRsBAAsAwAAAA==.Thatoneguy:BAAALAADCggIEAAAAA==.Thecreator:BAAALAADCggICAAAAA==.Thefunk:BAAALAADCgcIBwAAAA==.Theholytank:BAAALAADCgQIAwAAAA==.Thorseas:BAAALAAECgMIBgAAAA==.Threeiron:BAAALAAECgYIBgAAAA==.Thundastruck:BAAALAAECgMIAwAAAA==.',To='Tooyoo:BAABLAAECoEZAAILAAgIeR6oCgC6AgALAAgIeR6oCgC6AgAAAA==.Toron:BAAALAADCgUIBQAAAA==.Tozzy:BAAALAADCggICAAAAA==.',Tp='Tpala:BAAALAADCgYIDgAAAA==.',Tr='Transparêncy:BAAALAADCggICAAAAA==.Transwights:BAAALAAECgYIBgAAAA==.Trashpixie:BAAALAAECgYICQAAAA==.',Tu='Turthunt:BAACLAAFFIEFAAMYAAMIQx5+AQAcAQAYAAMIyR1+AQAcAQAHAAIIaxt1BACtAAAsAAQKgRgAAxgACAjHJU8EACIDABgACAgPJU8EACIDAAcABghUJdoJAHsCAAAA.Turtlock:BAAALAADCgcIBQABLAAFFAMIBQAYAEMeAA==.',Ty='Tyndriel:BAAALAADCgcIBwAAAA==.',Un='Uncletank:BAAALAAECgIIAgAAAA==.',Ur='Urka:BAAALAADCgcIDgAAAA==.',Va='Valakar:BAAALAADCgUICAAAAA==.Valhardt:BAAALAADCggIDgAAAA==.Valoth:BAAALAADCgcIDAAAAA==.Vanelura:BAAALAADCgYIBgAAAA==.Vashnir:BAAALAADCggICAABLAAECgYIDgAEAAAAAA==.',Vi='Vistray:BAAALAADCgQIBAAAAA==.',['Vá']='Vánagandr:BAAALAAECgIIAgAAAA==.',Wa='Wahstella:BAACLAAFFIEFAAMZAAMICgl1AgCeAAAZAAIIYw11AgCeAAAMAAEIVwDaFAAhAAAsAAQKgSQAAhkACAhSJHkBADcDABkACAhSJHkBADcDAAAA.Waraich:BAAALAAECgYIEgABLAAFFAYIDQAaAKEgAA==.Wararrior:BAACLAAFFIENAAIaAAYIoSAQAACGAgAaAAYIoSAQAACGAgAsAAQKgRgAAhoACAgEJoAAAHcDABoACAgEJoAAAHcDAAAA.Waterdroplet:BAAALAADCgQIBwAAAA==.',Wh='Whelp:BAAALAADCgIIBAABLAAECgcIDAAEAAAAAA==.Whispy:BAAALAADCggICQABLAAECgcIDAAEAAAAAA==.Whitelady:BAAALAAECggIDAAAAA==.Whiterobot:BAAALAADCgIIAwAAAA==.Whittle:BAAALAADCggIDwAAAA==.Whodofthunk:BAAALAAECgMIBAAAAA==.Wholemilk:BAAALAAECgIIBAAAAA==.',Wi='Wifekicker:BAAALAADCgYIBwAAAA==.Wilhelm:BAAALAADCgYIBgAAAA==.',Wo='Woozi:BAAALAAFFAEIAQAAAA==.',Wr='Wrekker:BAAALAADCgcIBwAAAA==.',Wu='Wulgarr:BAABLAAECoEUAAIaAAgIexotBwBLAgAaAAgIexotBwBLAgAAAA==.',Xa='Xavierson:BAAALAAECgIIAwAAAA==.',Xi='Xilone:BAAALAAECgMIBgAAAA==.',Ye='Yenool:BAAALAADCggICQAAAA==.',Yi='Yi:BAAALAAECggIEwAAAA==.',Yo='Yokai:BAAALAAECgIIAwAAAA==.',Za='Zaaga:BAAALAAECgEIAgAAAA==.Zamon:BAAALAADCgcIBwAAAA==.Zamyk:BAAALAAECgEIAQAAAA==.Zantar:BAAALAADCggIDwAAAA==.Zappyböi:BAAALAAECgYIDgAAAA==.Zaqor:BAAALAADCgYIBgAAAA==.Zarf:BAAALAAECgYIDgAAAA==.Zariq:BAAALAADCggIBgAAAA==.Zartis:BAAALAADCgEIAQAAAA==.Zatal:BAAALAADCggICAAAAA==.Zayer:BAAALAADCggICAAAAA==.',Ze='Zeld:BAAALAAECgYIBAAAAA==.Zelgius:BAAALAAECgUIBwAAAA==.Zenhunter:BAAALAADCggIEAAAAA==.',Zh='Zhulee:BAAALAAECgYIBAAAAA==.',Zi='Zinu:BAAALAADCggIFgAAAA==.Zir:BAAALAAECgUICwAAAA==.Zirda:BAAALAAECgIIAgAAAA==.Ziviana:BAACLAAFFIEGAAIIAAMIgQ6bAgDhAAAIAAMIgQ6bAgDhAAAsAAQKgRgAAggACAhDIxsBADEDAAgACAhDIxsBADEDAAAA.Zizjat:BAAALAAECgQIBAAAAA==.',Zu='Zuuf:BAAALAAECgYIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end