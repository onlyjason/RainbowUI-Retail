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
 local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Hunter-BeastMastery','Druid-Restoration',}; local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adynn:BAAALAAECgYICQAAAA==.',Ae='Aenywyn:BAAALAAECgYICQAAAA==.',Af='Afridium:BAAALAADCggIFAAAAA==.Afterimage:BAAALAADCggICAABLAAECgMIBgABAAAAAA==.',Al='Alderath:BAAALAADCgcIBwAAAA==.Alibaba:BAAALAADCgcIBwAAAA==.Alista:BAAALAAECgYICQAAAA==.',Am='Amoraith:BAAALAADCggIDgAAAA==.Amrya:BAAALAADCgcIBwAAAA==.',An='Anll:BAAALAADCgMIAwAAAA==.',Ao='Aonar:BAAALAADCggIEwAAAA==.',Ar='Arayvia:BAAALAADCgYIBgAAAA==.Arazak:BAAALAAECgEIAQABLAAECgYIDAABAAAAAA==.Arcann:BAAALAADCgEIAQAAAA==.Archenteron:BAAALAADCgIIAgAAAA==.Arctat:BAAALAADCgcIBwAAAA==.Ariannaass:BAAALAADCggIFQAAAA==.Arkaan:BAAALAAECgEIAQAAAA==.Aryah:BAAALAADCgIIAgAAAA==.',As='Asbjorne:BAAALAAECgMIAwAAAA==.Aseopp:BAAALAADCgcIDwAAAA==.',Au='Aunalea:BAAALAADCgUIBQAAAA==.Aurianne:BAAALAAECgIIAgAAAA==.Auroroth:BAAALAAECgYIBgAAAA==.Autumnmoon:BAAALAAECgEIAQAAAA==.',Av='Avelos:BAAALAAECgcIDwAAAA==.',Ay='Ayzmyth:BAAALAAECgMICAAAAA==.',Ba='Babygirldemi:BAAALAAECgYIBgAAAA==.Bafa:BAAALAADCgUIBQAAAA==.Bakedbean:BAAALAADCgcIFAAAAA==.Banthapooduu:BAAALAADCgYIBgAAAA==.Bashra:BAAALAADCgcIBwAAAA==.',Be='Beasic:BAAALAAECgMIBgAAAA==.Beetlejuicë:BAAALAADCgIIAgAAAA==.Beletili:BAAALAAECgYICAAAAA==.Bellissimo:BAAALAAECgMIAwAAAA==.',Bh='Bhooth:BAAALAADCgcICgAAAA==.',Bi='Birb:BAAALAAECgYIBwAAAA==.Birdmage:BAAALAAECgEIAQABLAAECgYICgABAAAAAA==.Birdman:BAAALAAECgYICgAAAA==.Birdwarrior:BAAALAADCggICAABLAAECgYICgABAAAAAA==.',Bl='Blackcoffee:BAAALAADCgYICgAAAA==.Blackraven:BAAALAAECgIIAgAAAA==.Blatendrg:BAAALAAECgMIBAAAAA==.Blindcloud:BAAALAAECgEIAQAAAA==.',Bo='Boot:BAAALAADCggIEwAAAA==.',Br='Bread:BAAALAAECgMIAwAAAA==.Breae:BAAALAAECgMIBgAAAA==.',By='Bytchwind:BAAALAADCgIIAgAAAA==.',Ca='Caistin:BAAALAADCgYICAAAAA==.Calla:BAAALAADCggICAAAAA==.Caluu:BAAALAADCgQIBAAAAA==.Castironslam:BAAALAAECgYICQAAAA==.Catsclaw:BAAALAADCggIDwAAAA==.',Ce='Ceneda:BAAALAADCgcIDAAAAA==.',Ch='Chaba:BAAALAAECgMIBgAAAA==.Chasangwon:BAAALAAECggIBgAAAA==.Chathvia:BAAALAADCgQIBAAAAA==.Chiot:BAAALAAECgMIBQAAAA==.',Ci='Cinderhorn:BAAALAADCgcIDwAAAA==.',Co='Corax:BAAALAAECgQIBAAAAA==.Corisana:BAAALAADCggIDgAAAA==.Corlada:BAAALAADCggICwAAAA==.Corleth:BAAALAADCgMIAwAAAA==.Corlink:BAAALAADCggICwAAAA==.Corlock:BAAALAADCgYIBwAAAA==.Cormech:BAAALAADCggIDwAAAA==.Cornite:BAAALAADCggIDAAAAA==.Cottonpandy:BAAALAAECgMIBQAAAA==.',Cr='Crizzo:BAAALAAECgIIAgAAAA==.',Da='Dakra:BAEALAAECgMIBgAAAA==.Dalandis:BAAALAAECgIIAgAAAA==.Dalyeth:BAAALAAECgEIAQAAAA==.Dann:BAAALAADCgYIBwAAAA==.Darce:BAAALAADCgcIBwAAAA==.Darkwingorc:BAAALAAECgYIDgAAAA==.Darkwulf:BAAALAADCgcIBwAAAA==.Daunt:BAAALAADCgcIDAABLAADCggIFgABAAAAAA==.',De='Deandra:BAAALAADCggICAAAAA==.Deara:BAAALAADCgcIDQAAAA==.Deebz:BAAALAAECgMIBgAAAA==.Deliverance:BAAALAAECgMIAwAAAA==.Demolicious:BAAALAADCgcIDAAAAA==.Denuma:BAAALAADCgMIAwAAAA==.Devilina:BAAALAAECgEIAQAAAA==.Dewsong:BAAALAAECgMIBgAAAA==.',Dh='Dheri:BAAALAAECgUIBgAAAA==.',Di='Diegho:BAAALAADCggIEwAAAA==.Diluvian:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',Dn='Dnegelpal:BAAALAAECgUIBgAAAA==.',Do='Dodgecharger:BAAALAADCgcIDQAAAA==.Doskya:BAABLAAECoEWAAMCAAgItBsEBAAzAgACAAgI7xoEBAAzAgADAAMIthSqQAC9AAAAAA==.Dotss:BAAALAADCgcIBwAAAA==.',Dr='Drakilu:BAAALAAECgMIBgAAAA==.Drasic:BAAALAAECgcIDwAAAA==.Draug:BAAALAAECgMIBAAAAA==.Drunken:BAAALAAECgYICQAAAA==.Drunkndonuts:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.',Du='Durward:BAAALAAECgMIAwAAAA==.Duskø:BAAALAAECgQIBQAAAA==.Duvo:BAAALAAECgEIAQAAAA==.',['Dé']='Détank:BAAALAAECgYICQAAAA==.',Ea='Easyname:BAABLAAECoEYAAIEAAcICBydGQAtAgAEAAcICBydGQAtAgAAAA==.',Ei='Eiene:BAAALAADCgYIBgAAAA==.',El='Elarra:BAAALAADCggICAAAAA==.Ellbereth:BAAALAADCgYIBQAAAA==.Elloseth:BAAALAAECgEIAQAAAA==.Elmorin:BAAALAADCgcIBQAAAA==.',Em='Emeraldshdw:BAABLAAECoEVAAIFAAgIwhecFgApAgAFAAgIwhecFgApAgAAAA==.',Eo='Eolon:BAAALAADCgUICAAAAA==.',Ep='Epica:BAAALAAECgMIBgAAAA==.',Er='Eragonhawk:BAAALAADCggIDwAAAA==.Eroldan:BAAALAAECgMIAwAAAA==.Erovianoria:BAAALAAECgYIDgAAAA==.',Es='Escalus:BAAALAAECgYIBgAAAA==.Essun:BAAALAADCggIDwAAAA==.',Fa='Fatalfury:BAAALAAECgYIBwAAAA==.Fauxpal:BAAALAADCggIDwAAAA==.',Fe='Feleon:BAAALAADCgcIBwABLAAECggIFwAGANQgAA==.',Fi='Finngan:BAAALAADCgcICwAAAA==.',Fl='Flintbeard:BAAALAADCgcIBwAAAA==.Fluffs:BAAALAAECgIIAgAAAA==.',Fo='Fol:BAAALAAECgUIBwAAAA==.Forestkin:BAAALAADCgcIDQABLAAECgEIAQABAAAAAA==.Foxtails:BAAALAADCgcIBwAAAA==.',Fr='Frelli:BAAALAAECgYICAABLAAFFAIIAgABAAAAAA==.Frostreaper:BAAALAADCgcIDAAAAA==.Frozenthunda:BAAALAADCgcIDAAAAA==.Frumunda:BAAALAAECgYICgAAAA==.Frys:BAAALAADCggIDAAAAA==.',Fu='Furina:BAAALAAECgcIDgAAAA==.Furna:BAAALAAECgEIAQAAAA==.Furries:BAAALAADCgQIBAAAAA==.',Ga='Gabrael:BAAALAAECgcIEAAAAA==.Galstan:BAAALAADCgcIBwAAAA==.',Ge='Geloe:BAAALAADCggIFgAAAA==.',Gh='Ghorienge:BAAALAADCggIDwAAAA==.',Gi='Gidimin:BAAALAADCgcIDAAAAA==.Gilox:BAAALAADCgcICAAAAA==.Ginrickey:BAAALAADCgcIDgAAAA==.',Go='Gorgoth:BAAALAAECgMIBAAAAA==.Gothgirldemi:BAAALAAFFAIIAgAAAA==.',Gr='Graymon:BAAALAADCggIFAAAAA==.Greebo:BAAALAADCgcIDAAAAA==.',Gu='Guilherme:BAAALAAECgIIAgAAAA==.',Gw='Gwenyver:BAAALAADCgcIEAAAAA==.',Ha='Hafaken:BAAALAADCgcIBwAAAA==.Hammerfall:BAAALAAECgYIBwAAAA==.Hamord:BAAALAAECgMIAwAAAA==.Hansdelbruk:BAAALAADCgYIEAAAAA==.Hapablahp:BAAALAAECgIIAgAAAA==.Harlock:BAAALAAECgMIAwAAAA==.Hazelnuts:BAAALAADCgUIAgAAAA==.',He='Healusive:BAAALAADCgMIAwAAAA==.Hellcrazed:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.Helleye:BAAALAADCgcICQAAAA==.',Hi='Hiten:BAAALAAECgMIAwAAAA==.',Ho='Hoshida:BAAALAADCgMIAwAAAA==.',Hu='Huntertattoo:BAAALAAECgMIBgAAAA==.',['Hê']='Hêlleye:BAAALAADCgYIDwABLAAECgUIBwABAAAAAA==.',['Hí']='Hírra:BAAALAAECgcIDwAAAA==.',Id='Idkanymore:BAAALAADCgUIBQAAAA==.',Ie='Iepa:BAAALAADCggIFQAAAA==.',If='Ifryz:BAAALAAECgIIAgAAAA==.',Ig='Ignisluage:BAAALAADCgcIBwAAAA==.',Il='Illianarra:BAAALAADCggIEwAAAA==.Illidorable:BAAALAAECgEIAQABLAAFFAIIAgABAAAAAA==.Iloveparrots:BAAALAADCgcIBwAAAA==.Ilthad:BAAALAADCggIEAAAAA==.',Im='Imperio:BAAALAADCgcICwAAAA==.Impåbuser:BAAALAADCgQIBAABLAADCgYICAABAAAAAA==.Imshalar:BAAALAADCgEIAQAAAA==.',In='Infurryating:BAAALAAECgEIAQAAAA==.Insainter:BAAALAADCggIDwAAAA==.',Ir='Iroar:BAAALAADCgQIBAAAAA==.',It='Itsirk:BAAALAADCgcIBQAAAA==.',Iz='Izyebelle:BAAALAAECgMIAwAAAA==.',Ja='Jadynara:BAAALAAECgcIDQAAAA==.Jandreline:BAAALAADCgcIBwAAAA==.',Je='Jennyfer:BAAALAADCgMIAwAAAA==.',Jh='Jhainzaar:BAAALAAECgMIBAAAAA==.',Ji='Jiayou:BAAALAAECgIIAgAAAA==.Jimmydin:BAAALAAECgcIEAAAAA==.',Ju='Julkan:BAAALAAECgMIAwAAAA==.Junhoong:BAAALAAECgYICQAAAA==.',Ka='Kai:BAAALAAECgMIAwAAAA==.Kairoll:BAAALAAECgYICQAAAA==.Karaa:BAAALAAECgEIAQAAAA==.Kariena:BAAALAADCgcICAAAAA==.Kassidy:BAAALAADCgUIAgABLAADCggIFAABAAAAAA==.Katesluage:BAAALAAECgEIAQAAAA==.',Ke='Kelina:BAAALAADCgcIDwAAAA==.Kernasas:BAAALAAECgMIAwAAAA==.Kezan:BAEALAAECgIIAwAAAA==.',Kh='Khupo:BAAALAAECgYICQAAAA==.',Ki='Kit:BAAALAADCgQIBAAAAA==.Kitalidie:BAAALAADCgUIBwABLAADCgcICAABAAAAAA==.Kizaraan:BAAALAAECgMIAwAAAA==.',Kl='Kleyntamar:BAAALAADCggIDQAAAA==.',Ko='Koans:BAAALAAECgQIBwAAAA==.',Kr='Kritt:BAAALAADCgcIDQAAAA==.Krshna:BAAALAADCgcICgAAAA==.',Ku='Kupmage:BAAALAAECgMIAwAAAA==.',Ky='Kynnigos:BAAALAAECgEIAQAAAA==.Kystorm:BAAALAADCgQIBAAAAA==.Kyüss:BAAALAAECgIIAgAAAA==.',La='Larachel:BAAALAADCgcIBwAAAA==.Laur:BAAALAAECgYIDgAAAA==.',Le='Leathergimp:BAAALAAECgcIEQAAAA==.Leiney:BAAALAADCgEIAQAAAA==.Levia:BAAALAADCgcIBwAAAA==.',Li='Liartes:BAAALAADCggIFAAAAA==.Lilipo:BAAALAADCgcIEgAAAA==.Liltara:BAAALAADCggIFAAAAA==.Liskurja:BAAALAADCgUIBQAAAA==.',Lo='Logoth:BAAALAAECgYIDgAAAA==.Loula:BAAALAAECgMIBAAAAA==.',Lu='Luli:BAAALAAECggIDgAAAA==.Lunaellana:BAAALAADCgQIBAAAAA==.Lunhibault:BAAALAAECgEIAQAAAA==.Lus:BAAALAAECgYIDAAAAA==.',Ly='Lyneena:BAAALAAECgYICQAAAA==.Lyonidas:BAAALAADCgMIAwAAAA==.',Ma='Makado:BAAALAAECgIIAwAAAA==.Makoroth:BAAALAAECgEIAQAAAA==.Maycee:BAAALAADCgMIBgAAAA==.',Mc='Mcabre:BAAALAADCgUIAgABLAADCggIFAABAAAAAA==.Mcat:BAAALAADCgcIDgAAAA==.Mcnaugh:BAAALAADCgQIBAAAAA==.',Me='Meatplow:BAAALAADCgYIBgAAAA==.Mefistofeliz:BAAALAADCggICAAAAA==.Menaras:BAAALAAECgYIDgAAAA==.',Mi='Miyu:BAAALAAECgYICQAAAA==.',Mo='Mod:BAAALAAECgYICQAAAA==.Moelly:BAAALAAECgYICQAAAA==.Mogtham:BAAALAAECgMIBQAAAA==.Moisticklez:BAAALAAECggIAgAAAA==.Momastery:BAAALAAECgYICQAAAA==.Moofor:BAAALAADCgUIBQABLAADCggIDwABAAAAAA==.Moonpig:BAAALAADCgMIAwAAAA==.Morellea:BAAALAADCgcIBwAAAA==.Morighann:BAAALAAECgYICQAAAA==.Morphalot:BAAALAAECgEIAQAAAA==.Mortality:BAAALAADCgcICgABLAAECgMIAwABAAAAAA==.',My='Mynameisjeff:BAAALAAECgEIAQAAAA==.Mynkx:BAAALAADCgcIDQAAAA==.',Na='Nahaman:BAAALAADCgMIBgAAAA==.Nalo:BAAALAADCggIDgAAAA==.Nazan:BAAALAADCggIEwAAAA==.Nazrethess:BAAALAADCggIFAAAAA==.',Ne='Nechahira:BAABLAAECoEXAAIGAAgI1CB7BAC7AgAGAAgI1CB7BAC7AgAAAA==.Nethim:BAAALAADCgcICgAAAA==.',Ni='Nimirawr:BAAALAAECgYICQAAAA==.',Ny='Nyia:BAAALAADCgYIBgAAAA==.Nyke:BAAALAADCgcICgAAAA==.Nyxta:BAAALAADCgYIBgAAAA==.',Oh='Ohwellz:BAAALAAECgcIDQAAAA==.',Op='Ophin:BAAALAADCgcICgAAAA==.',Or='Orejon:BAAALAADCgYIBgAAAA==.Orhail:BAAALAADCgUIBQAAAA==.Orhel:BAAALAADCgEIAQAAAA==.Ornathius:BAAALAADCgcIDgAAAA==.',Ou='Outofmana:BAAALAAECgQIBwAAAA==.',Pa='Padhu:BAAALAADCggIDwAAAA==.Palox:BAAALAADCgUIBQAAAA==.Panamared:BAAALAAECgMIBgAAAA==.Pantheriea:BAAALAAECgMIAwAAAA==.Parmes:BAAALAADCgUIAgAAAA==.',Pc='Pc:BAAALAADCgMIAwAAAA==.',Pe='Pennyfeather:BAAALAAECgMIBgAAAA==.Pezza:BAAALAADCggIDwAAAA==.',Ph='Phaze:BAAALAAECgYICQAAAA==.Phia:BAAALAAECgcIEAAAAA==.',Pl='Pluralbutter:BAAALAAECgEIAQAAAA==.',Pr='Prattlemonk:BAAALAAECgYICQAAAA==.Primu:BAAALAAECgMIAwAAAA==.Protherus:BAAALAAECgYICQAAAA==.',Ps='Psylix:BAAALAAECgMIBgAAAA==.',Pu='Puncheon:BAAALAADCggICAABLAAECggIFwAGANQgAA==.',Qi='Qinzhe:BAAALAADCggIFwAAAA==.',Qt='Qtkat:BAAALAADCgUIAgABLAADCggIEgABAAAAAA==.',Ra='Raevennlumis:BAAALAADCgIIAgAAAA==.Rahb:BAAALAAECgEIAQAAAA==.Ransha:BAAALAADCggIBgABLAAECgYICgABAAAAAA==.Raymos:BAAALAADCgUIBQAAAA==.',Re='Rebirth:BAAALAADCgIIAgAAAA==.Renwic:BAAALAADCggIFAAAAA==.',Rh='Rhintalle:BAAALAADCgUIAgAAAA==.',Ro='Roostorm:BAAALAADCgcIBwAAAA==.Roryh:BAAALAADCgYICQAAAA==.',Sa='Sagehawk:BAAALAAECgMIAwAAAA==.Sanguinous:BAAALAADCgcICQAAAA==.Satori:BAAALAADCggIEwAAAA==.',Se='Selfu:BAAALAAECgMIBAAAAA==.Sellidor:BAAALAAECgYICQAAAA==.Senzadel:BAAALAADCgcIBwAAAA==.Seriniyaa:BAAALAAECgEIAQAAAA==.',Sh='Shadowfar:BAAALAADCgQIBAAAAA==.Shadowseeker:BAAALAADCgUIAgAAAA==.Shaiey:BAAALAADCgQIBAAAAA==.Shaim:BAAALAAECgcIEAAAAA==.Shamanthá:BAAALAAECgUIBwAAAA==.Shikabane:BAAALAADCgMIAwAAAA==.Shiningangel:BAAALAADCgYIBgAAAA==.Shinjiro:BAAALAAECgMIBgAAAA==.Shirito:BAAALAAFFAIIAgAAAA==.Shirogos:BAAALAAECgYICAAAAA==.Shortnstout:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.',Si='Sienje:BAAALAAECgQIBAAAAA==.Sifern:BAAALAADCggIEwAAAA==.Sigma:BAAALAAECgMIBgAAAA==.Simpleson:BAAALAAECgYICAAAAA==.',Sk='Skornne:BAAALAAECgYICwAAAA==.',Sl='Slaete:BAAALAADCgcIBwAAAA==.Slappyfeet:BAAALAADCgMIAwABLAAECgYICQABAAAAAA==.',Sn='Snievan:BAAALAAECgIIAgAAAA==.',So='Solemn:BAAALAAECgIIAgAAAA==.Solrana:BAAALAADCgcIBwAAAA==.Songmistress:BAAALAADCgcIDAAAAA==.Soriona:BAAALAAECgEIAQAAAA==.Sorren:BAAALAADCgcIDgAAAA==.Sorrows:BAAALAAECgEIAQAAAA==.Sosukesagara:BAAALAADCgcIBwAAAA==.Sozin:BAAALAAECgEIAQAAAA==.',St='Strom:BAAALAAECgEIAQAAAA==.',Su='Sunasha:BAAALAAECgEIAQAAAA==.Superbautumn:BAAALAAECgEIAgAAAA==.',Sw='Swullypants:BAAALAAECgYIBgAAAA==.',Sy='Sylester:BAAALAADCgUIAQAAAA==.',['Sé']='Sélune:BAAALAAECgEIAQAAAA==.',Ta='Tali:BAAALAAECgMIAwAAAA==.Talumil:BAAALAAECgYICgAAAA==.Tangle:BAAALAAECgEIAQAAAA==.Tanka:BAAALAAECgMIBgAAAA==.Tashlaraz:BAAALAADCggIEgAAAA==.Taurus:BAAALAAECgIIAgAAAA==.Taveleron:BAAALAADCgYIBwAAAA==.Tavia:BAAALAAECgMIAwAAAQ==.',Te='Temporantus:BAAALAADCggIFwAAAA==.Terrasque:BAAALAAECgMIAwAAAA==.',Th='Thaddeus:BAAALAAECgMIBAAAAA==.Therm:BAAALAAECgcIEAAAAA==.Thoramier:BAAALAAECgIIAgAAAA==.Thorgrune:BAAALAADCgUIDQAAAA==.Thunderthys:BAAALAADCgcIDQAAAA==.',Ti='Tibble:BAAALAAECgMIBAAAAA==.',To='Tonatuih:BAAALAAECgYICQAAAA==.',Tr='Travia:BAAALAADCgcIDwAAAA==.Trezzia:BAAALAAECgMIBAAAAA==.Triipod:BAAALAADCgIIAgAAAA==.Trinkat:BAAALAADCggIEgAAAA==.Troggdor:BAAALAADCgcIBwAAAA==.',Ty='Tylean:BAAALAADCggICAAAAA==.',Um='Umbreon:BAAALAAECgUICAABLAAECggIFwAGANQgAA==.',Un='Unethical:BAAALAAECgMIAwAAAA==.',Ur='Ursamajoris:BAAALAAECgEIAQAAAA==.Urzahd:BAAALAADCggIEwAAAA==.',Va='Vaddix:BAAALAADCggIDAAAAA==.Vareyn:BAAALAAECgUIBwAAAA==.',Ve='Vermin:BAAALAADCgQIBAAAAA==.',Vi='Vienge:BAAALAADCgcIBwAAAA==.',Vl='Vladriel:BAAALAADCgUIAgAAAA==.',Vo='Vonon:BAAALAAECgYIBgAAAA==.Vorth:BAAALAAECgYICQAAAA==.',Wa='Waldir:BAAALAAECgMIBQAAAA==.Walrox:BAAALAADCgEIAQAAAA==.Watz:BAAALAAECgUICAAAAA==.',Wi='Wintersnow:BAAALAAECgEIAQAAAA==.',Wr='Wrack:BAAALAADCggIFwAAAA==.',Wy='Wyldecat:BAAALAADCggIDQAAAA==.',Xa='Xandralynn:BAAALAADCgMIAgAAAA==.',Xe='Xessala:BAAALAADCgUIBQAAAA==.',Xh='Xheero:BAAALAAECgcIDQAAAA==.',Ya='Yagiashi:BAAALAAECgcIDwAAAA==.',Yo='Yodaddy:BAAALAADCggICAAAAA==.',Yu='Yulica:BAAALAADCggIFAAAAA==.',Za='Zaffy:BAAALAADCgcICQAAAA==.Zandra:BAAALAADCgMIAwAAAA==.Zano:BAAALAADCggIEgAAAA==.Zaruba:BAAALAADCggIFgAAAA==.',Ze='Zekos:BAAALAADCgcIEQAAAA==.',Zi='Zillver:BAAALAAFFAIIAgAAAA==.Zimdalar:BAAALAADCggIEwAAAA==.Ziy:BAAALAADCgYIBgAAAA==.',Zu='Zulre:BAAALAADCgUIBQAAAA==.',['Äk']='Äkräs:BAAALAADCgUIAgAAAA==.',['Üb']='Übique:BAAALAAECgcIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end