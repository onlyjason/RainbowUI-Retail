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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Druid-Restoration','Monk-Mistweaver','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Druid-Feral','DemonHunter-Vengeance','DeathKnight-Unholy','DeathKnight-Frost',}; local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Aberendh:BAAALAAECggIBQAAAA==.Aberenmonk:BAAALAADCggICgAAAA==.',Ac='Acidemon:BAAALAAECgUIBAAAAA==.',Ad='Adalaide:BAAALAAECgYIDwAAAA==.Adine:BAAALAADCggIFwAAAA==.',Ae='Aedran:BAAALAADCgcIBwABLAAECgcICQABAAAAAA==.',Ah='Ahkna:BAAALAADCggIEwAAAA==.',Ai='Aizlyn:BAAALAADCggIFwAAAA==.',Al='Aliraeda:BAAALAAECgYICQAAAA==.Alisara:BAAALAAECgcIEAAAAA==.Alitrullbrat:BAAALAAECgIIAgAAAA==.Allexx:BAAALAAECgYICQAAAA==.Altarisjr:BAAALAADCgMIAwAAAA==.',Am='Amasu:BAABLAAECoEVAAICAAgISB/WCQCrAgACAAgISB/WCQCrAgAAAA==.Amoresh:BAAALAAECgYIDAAAAA==.',An='Anastriana:BAAALAADCggIFwAAAA==.Angeal:BAAALAAECgEIAQAAAA==.Animus:BAAALAAECgIIBAAAAA==.Anzew:BAAALAADCggIEAAAAA==.',Ar='Arazalor:BAAALAAECgQIBAAAAA==.Arcangel:BAABLAAECoEVAAIDAAgIQSKpAwDUAgADAAgIQSKpAwDUAgAAAA==.Arcbane:BAAALAADCgEIAQAAAA==.Argand:BAAALAAECgIIBAAAAA==.Ariannah:BAAALAAECgIIAgAAAA==.Arimlinn:BAAALAAECgIIAgAAAA==.Arkantös:BAAALAAECgEIAgAAAA==.Arthelton:BAAALAADCgcIBwAAAA==.Arthurdent:BAAALAAECgIIBAAAAA==.',As='Asham:BAAALAAECgIIAgAAAA==.Ashenrain:BAAALAADCggICAAAAA==.',At='Atheren:BAAALAAECgQIBAAAAA==.Athmei:BAAALAADCgMIAwAAAA==.',Au='Augmented:BAAALAADCgcIDQAAAA==.Auntiemimi:BAAALAAECgEIAgAAAA==.',Av='Avaleandia:BAAALAADCggIEwABLAAECgYICQABAAAAAA==.Avannar:BAAALAADCggIDwAAAA==.Aveìl:BAAALAADCgcICAAAAA==.Aviae:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.',Ay='Ayani:BAAALAAECgMIBgAAAA==.Aydie:BAAALAADCgYICwAAAA==.Ayrelle:BAAALAADCgQIBAAAAA==.',Ba='Bacongrease:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Baconsizzle:BAAALAAECgMIAwAAAA==.Baddhabit:BAAALAADCgUIBQAAAA==.Baddkharma:BAAALAAECgIIAgAAAA==.Bagelz:BAABLAAECoEVAAIEAAgILiWgAABQAwAEAAgILiWgAABQAwAAAA==.Balagref:BAAALAADCggICQAAAA==.Baldsack:BAAALAADCgIIAgABLAAECgcIDwABAAAAAA==.Balgan:BAAALAAECgYICAAAAA==.Baraqel:BAAALAADCggIFwAAAA==.Bathomula:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.Bathool:BAAALAAECgEIAQAAAA==.Bayblade:BAAALAADCgEIAQABLAAFFAMIBQAFAJsVAA==.Bayla:BAAALAAECgIIAgABLAAFFAMIBQAFAJsVAA==.Bazza:BAAALAAECgIIAgAAAA==.',Be='Beararms:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Bearicade:BAAALAADCgcIDQAAAA==.Bec:BAAALAAECggICQAAAA==.Beefcat:BAAALAAECgcICQAAAA==.Benedictus:BAAALAAECgMIBwAAAA==.Benteen:BAAALAADCgIIAwAAAA==.Beric:BAAALAAECgQIDgAAAA==.Betadine:BAAALAADCggIEgAAAA==.',Bi='Biron:BAAALAAECgMIBAAAAA==.Bitofhoney:BAAALAADCgIIAgAAAA==.',Bl='Blayse:BAAALAADCggIEgAAAA==.',Bo='Bodom:BAAALAAECgMIAwAAAA==.Boo:BAAALAADCggICAAAAA==.Boogersugar:BAAALAADCgYIBgAAAA==.Boohaha:BAAALAAECgEIAQAAAA==.Boompunch:BAAALAAECggICAAAAA==.Borris:BAAALAAECgYIDAAAAA==.',Br='Breakthrough:BAAALAAECgUIBAAAAA==.Brightwing:BAABLAAECoEeAAIGAAcIWiNdAgCzAgAGAAcIWiNdAgCzAgAAAA==.Brigorshama:BAAALAADCggIEAAAAA==.Brogrash:BAAALAAECgYIDQAAAA==.Brushlite:BAAALAADCgcICQAAAA==.Brynth:BAAALAAECgEIAQAAAA==.',Bu='Bullshivek:BAAALAAECgUIBAAAAA==.',['Bé']='Bénihime:BAAALAADCgYICQAAAA==.',['Bú']='Bú:BAAALAAECgMIAwAAAA==.',Ca='Caale:BAAALAAECgMIBAAAAA==.Cajùn:BAAALAAECgEIAQAAAA==.Callsaul:BAAALAADCgMIAwAAAA==.Caylissa:BAAALAAECgEIAgAAAA==.',Ce='Cendo:BAAALAAECgYIAwABLAAECgYIBgABAAAAAA==.Cenvoked:BAAALAAECgYIBgAAAA==.Cetlfeng:BAAALAAECgMIAwAAAA==.',Ch='Charlicious:BAAALAAECgIIBAAAAA==.Chedwilunar:BAAALAADCgEIAQAAAA==.Chimster:BAAALAADCgQIBAAAAA==.Chknlttl:BAAALAAECgUIBAAAAA==.Chocomochi:BAAALAADCggICQAAAA==.Chompsky:BAAALAADCgMIAwAAAA==.Chopleaf:BAAALAADCgcICAAAAA==.Chrønic:BAAALAADCgcICQAAAA==.Chyluakin:BAAALAAECgIIAgAAAA==.Chyna:BAAALAADCgMIAwAAAA==.',Ci='Cieara:BAAALAADCggICAAAAA==.Cinnaminty:BAAALAADCgMIAwAAAA==.',Cl='Clout:BAAALAAECgEIAQAAAA==.',Co='Conflag:BAAALAAECgMIAwAAAA==.Constantine:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.',Cr='Craeus:BAAALAAECgMIBgAAAA==.Crauley:BAAALAADCgQICAAAAA==.Crine:BAAALAADCgMIAwABLAAECgMIBAABAAAAAA==.Criptik:BAAALAADCgcIDgAAAA==.Criztal:BAAALAADCgcIDQABLAADCggIEAABAAAAAA==.',Cu='Cuppiecakes:BAAALAADCggICAAAAA==.Cursedmayo:BAAALAAECgcIDwAAAA==.Cut:BAAALAADCggICgABLAAFFAIIAgABAAAAAA==.',Cy='Cynadora:BAAALAAECgYICQAAAA==.Cyonarah:BAAALAADCggIDgAAAA==.',Da='Daimonduke:BAAALAADCgcIBwAAAA==.Daimondukee:BAAALAAECgMIBQAAAA==.Darem:BAAALAADCgMIAwAAAA==.Darll:BAAALAAECgQIBAAAAA==.',De='Deathmaster:BAAALAAECgQIBwAAAA==.Deidra:BAAALAADCggIDQAAAA==.Delryth:BAAALAADCgcICAAAAA==.Demonchimy:BAAALAADCggIEAAAAA==.Demondani:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.Demonsitter:BAAALAADCgYIBgAAAA==.Demontan:BAAALAADCggICAAAAA==.Dersdomkie:BAAALAADCgcIBwAAAA==.Devahs:BAAALAAECgMIBAAAAA==.',Di='Diggi:BAAALAAECgEIAQAAAA==.Diosa:BAAALAAECgMIBgAAAA==.',Dj='Djflazzin:BAAALAADCgcIFAAAAA==.',Do='Docfeelgood:BAAALAADCgcICAAAAA==.Doeylock:BAAALAADCgQIBAAAAA==.Dogmom:BAAALAADCggICAAAAA==.',Dr='Dragaan:BAAALAAECgMIBAAAAA==.Dragondude:BAAALAADCggICQAAAA==.Dragonoodles:BAAALAAECgIIAgAAAA==.Dragonzbane:BAAALAAECgEIAQAAAA==.Drdoom:BAAALAAECgIIAgAAAA==.Dreamawake:BAAALAADCgcIBwAAAA==.Drek:BAAALAADCggICgAAAA==.',Du='Dummiethicc:BAAALAADCgcICgAAAA==.Dummithick:BAAALAAECgcIDwAAAA==.',Dw='Dwarfsham:BAAALAADCggIEAAAAA==.',Dy='Dyriana:BAAALAADCgcIBwAAAA==.',['Dä']='Dänzig:BAAALAADCgEIAQAAAA==.',Ea='Eatsorcs:BAAALAAECgYICgAAAA==.',Eb='Ebit:BAAALAAECgMIBgAAAA==.',Ec='Eclipz:BAAALAADCgEIAQAAAA==.',Ei='Eirodlez:BAAALAAECgIIAQAAAA==.',El='Elektraka:BAAALAADCgQIBAAAAA==.Elijá:BAAALAADCgUIBQAAAA==.Ellasian:BAAALAAECgIIAgAAAA==.Eloise:BAAALAADCgcICAAAAA==.Eltria:BAABLAAECoEVAAIHAAgIISPMBwABAwAHAAgIISPMBwABAwAAAA==.',Ep='Ephel:BAAALAAECgEIAQAAAA==.',Es='Eskanor:BAAALAADCggICQAAAA==.Essential:BAAALAAFFAEIAQAAAA==.',Et='Ethop:BAAALAADCgcICwABLAAECgcICQABAAAAAA==.',Ez='Ezalth:BAAALAADCggIDwAAAA==.',Fa='Falafelguy:BAAALAAECgMIBQAAAA==.',Fe='Fedange:BAAALAAECgMIAwAAAA==.Felician:BAAALAADCgcIBwAAAA==.Felii:BAAALAAECgQIBAAAAA==.Fey:BAAALAAECgYICwAAAA==.',Fi='Finiarel:BAAALAADCgQIBAABLAAECgQIBAABAAAAAA==.Fireslingin:BAAALAADCgMIAwAAAA==.Fireyfox:BAAALAADCgcIBwABLAAECgUIBAABAAAAAA==.',Fj='Fjc:BAAALAAECgEIAQAAAA==.',Fl='Flannel:BAAALAADCgMIAwAAAA==.Flazzin:BAAALAADCggICAAAAA==.Flubber:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.',Fo='Forestspirit:BAAALAAECgYICQAAAA==.Foxxee:BAAALAADCgYIBQAAAA==.Fozzey:BAAALAAECgMIAwAAAA==.',Fr='Freyjawion:BAAALAAECgIIAgAAAA==.Frodostabbns:BAAALAAECgUICAAAAA==.',Ga='Galadryel:BAABLAAECoEVAAICAAgIdhMVFQAFAgACAAgIdhMVFQAFAgAAAA==.Gargosa:BAAALAAECgcICgAAAA==.Garybusey:BAAALAADCgIIAgAAAA==.',Ge='Geist:BAABLAAECoEVAAMIAAgIbCA9CgDaAgAIAAgIbCA9CgDaAgAJAAEIaQxMMQA6AAAAAA==.Gekni:BAAALAAECgMIBAAAAA==.Geraith:BAAALAAFFAEIAQAAAA==.Gerios:BAAALAAECgQIBAAAAA==.',Gh='Gheroth:BAAALAADCgcICAAAAA==.Ghostflair:BAAALAADCgYIBgAAAA==.Ghostflare:BAAALAADCgEIAQAAAA==.',Gl='Glendra:BAAALAAECgYICQAAAA==.Gloomfx:BAAALAAECgMIBAAAAA==.Glorranna:BAAALAADCgUICAAAAA==.Glowfish:BAAALAAECgEIAQAAAA==.',Gn='Gnomemage:BAAALAADCgQIBAAAAA==.',Gr='Gregoriusz:BAAALAAFFAEIAQAAAA==.Greygull:BAAALAADCggIEgAAAA==.Gripe:BAAALAADCgcIBwAAAA==.Grr:BAAALAAECgYIBQAAAA==.Grunin:BAAALAADCggIDgAAAA==.',Gu='Guntank:BAAALAAECgMIBgAAAA==.Guntenk:BAAALAADCgcIBwAAAA==.',Ha='Havenfell:BAAALAAECgYIBwAAAA==.Hawkfist:BAAALAAECgQIBwAAAA==.',He='Heinzz:BAAALAAECgIIBAAAAA==.',Hi='Hierodoulos:BAAALAAECgMIBgAAAA==.',Hk='Hkfortyseven:BAAALAADCgcICAAAAA==.',Ho='Homedepot:BAAALAAECgMIAwAAAA==.Honeygold:BAAALAADCggIDgABLAAFFAEIAQABAAAAAA==.Hordehunters:BAAALAAECgMIBAAAAA==.',Hr='Hrothgar:BAAALAAECgYICgAAAA==.',Hu='Hummni:BAAALAAECgMIAwAAAA==.Hunthard:BAAALAAECgYICwAAAA==.',Hy='Hypoluxo:BAAALAADCggIEAAAAA==.',Ic='Icenea:BAAALAADCggIDgABLAAECgcIEAABAAAAAA==.',If='Ifearu:BAAALAADCggIDQAAAA==.',Ik='Ikthus:BAABLAAECoEVAAIKAAgI/RnWAQCqAgAKAAgI/RnWAQCqAgAAAA==.',Il='Illeiria:BAAALAAECgYICgAAAA==.Illtud:BAAALAADCggICQAAAA==.',Im='Imbaked:BAAALAAECgUICQAAAA==.',In='Inola:BAAALAAECgIIAwAAAA==.',Ir='Irisha:BAAALAADCggIDgAAAA==.Ironpipes:BAAALAADCgUIBAAAAA==.',Is='Iskrå:BAAALAADCggIEAAAAA==.',Ja='Jacynth:BAAALAAECgEIAgAAAA==.Jadian:BAAALAADCgcIDgAAAA==.Jaesyn:BAAALAAECgEIAQAAAA==.Jaimers:BAAALAAECgMIAwAAAA==.Jarik:BAAALAAECgMIBgAAAA==.Javlos:BAAALAAECgIIAgAAAA==.Jaxen:BAAALAADCgQIAwAAAA==.Jaywilde:BAAALAAECgcIDwAAAA==.Jaína:BAAALAADCgYIBwAAAA==.',Je='Jedzia:BAAALAADCgcICAAAAA==.Jeep:BAAALAAECgEIAQABLAAECgQIAwABAAAAAA==.Jellystalker:BAABLAAECoEXAAMLAAgIDiDqBwDiAgALAAgIDiDqBwDiAgAMAAQI/Q83MgDKAAAAAA==.Jerusalaem:BAAALAADCgEIAQAAAA==.',Ju='Jujiji:BAAALAADCggIDgAAAA==.Julls:BAAALAADCgQIBAAAAA==.Justboltit:BAAALAADCgcIDQABLAAECgQIBwABAAAAAA==.Juuiicce:BAAALAADCgcIBwAAAA==.',['Jö']='Jörð:BAAALAADCgcIBwAAAA==.',Ka='Kaisel:BAAALAAECgIIAQAAAA==.Kalestrazsaa:BAAALAADCggIEwAAAA==.Kalilah:BAAALAADCgYIBgAAAA==.Karnamoo:BAAALAAECgMIAwAAAA==.Karotten:BAAALAAECgQIBAAAAA==.Karrah:BAAALAADCgcIDgAAAA==.Karthair:BAAALAAECgUIBAAAAA==.Kashofy:BAAALAADCgEIAQAAAA==.Kaylessa:BAAALAAECgMIBAAAAA==.Kaz:BAAALAAECgUIAgAAAA==.',Ke='Keello:BAAALAAECgIIAgAAAA==.Keliatan:BAAALAAECgQIBwAAAA==.',Ki='Kileena:BAAALAADCgEIAQABLAAECgYICgABAAAAAA==.Killgore:BAAALAADCggIDQAAAA==.Kintsugi:BAAALAADCggICQAAAA==.Kisatchie:BAAALAAECgMIBAAAAA==.',Kl='Klepto:BAABLAAECoEWAAINAAgIGSDhCwDJAgANAAgIGSDhCwDJAgAAAA==.',Kr='Kreatos:BAAALAAECgYIBwABLAAFFAIIAgABAAAAAA==.Kromulok:BAAALAADCgIIAgABLAAECgYIBwABAAAAAA==.Kryne:BAAALAAECgMIBAAAAA==.Kröm:BAAALAAECgYIBwAAAA==.',Ku='Kumoji:BAAALAAECgYIBwAAAA==.Kurandor:BAAALAADCggIDwAAAA==.',Ky='Kylira:BAAALAADCgMIAwAAAA==.Kymerah:BAAALAADCgYIBwAAAA==.Kyrhios:BAAALAAECgEIAQAAAA==.Kyrøs:BAAALAADCgYIDwAAAA==.',La='Lannisters:BAAALAADCgcIDQAAAA==.Lanor:BAAALAAECgYICgAAAA==.Laquavious:BAAALAAECgMIBQAAAA==.Laquisham:BAAALAADCgMIAwABLAAECgMIBQABAAAAAA==.Lark:BAAALAAECgIIAgAAAA==.Larthas:BAAALAADCgcIDAAAAA==.Latrel:BAAALAAECggICAAAAA==.Lausia:BAAALAAECgMIAwAAAA==.',Le='Lealia:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.Leiha:BAAALAADCggIDAAAAA==.Lemen:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Li='Liams:BAAALAADCggIDwAAAA==.Lidori:BAAALAADCgMIAwAAAA==.Lightsent:BAAALAADCgcIDQAAAA==.Linux:BAAALAAECgUIBAAAAA==.',Ll='Llama:BAAALAAECgUIBAAAAA==.',Lo='Lokzilla:BAAALAAECgQIBAAAAA==.Loliita:BAAALAADCgcIBwAAAA==.Los:BAAALAAECgEIAQAAAA==.Lothurin:BAAALAAECgIIAQAAAA==.',Lr='Lrrp:BAAALAADCgMIAwAAAA==.',Lu='Luminianna:BAAALAAECgIIBAAAAA==.',Ly='Lytol:BAAALAADCggIDwAAAA==.',Ma='Maedae:BAAALAAECgIIBAAAAA==.Maegi:BAAALAADCggIDQAAAA==.Magicdam:BAAALAAECggICQAAAA==.Magmyr:BAAALAAECgQICQAAAA==.Manathas:BAAALAAECgIIAgAAAA==.Mandrith:BAAALAADCgcIBwAAAA==.Massacre:BAAALAAFFAIIAgAAAA==.Maxieflames:BAAALAADCgcICwAAAA==.Maxxed:BAABLAAECoEXAAMOAAgIXxvuGQDlAQAOAAYIMx3uGQDlAQAPAAYIXBj+GwDGAQAAAA==.',Me='Melanyx:BAAALAAECgMIBwAAAA==.Melielila:BAAALAADCgYIBgAAAA==.Menopawsal:BAAALAADCgEIAQAAAA==.Meoshi:BAAALAAECgIIAwAAAA==.Mesuryte:BAAALAAECgUICAAAAA==.',Mi='Mibs:BAAALAAECgMIAwAAAA==.Mickal:BAAALAAECgQIBAAAAA==.Miera:BAAALAADCggICAAAAA==.Mindchuck:BAAALAADCggICAAAAA==.Minorin:BAAALAADCgUIBwABLAAECgYIDwABAAAAAA==.Misoalive:BAAALAADCgYIBwAAAA==.',Mm='Mmoo:BAAALAAECgIIAgAAAA==.',Mn='Mnrogar:BAAALAADCgcIBwAAAA==.',Mo='Modara:BAAALAAECgIIAgAAAA==.Mohegon:BAAALAAECgIIAgAAAA==.Mohini:BAAALAAECgMIAwAAAA==.Mojhohammers:BAAALAADCggIDQAAAA==.Moonren:BAAALAAECgUIBAAAAA==.Morganlfaye:BAAALAAECgMIBAAAAA==.Morgianna:BAAALAAECgMIBAAAAA==.Mortincarne:BAAALAAECgMIBAAAAA==.',Mu='Munchwizard:BAAALAAECgIIAgAAAA==.',My='Mystravyn:BAAALAADCgcIBwAAAA==.',['Mé']='Méntos:BAAALAAECgIIBAAAAA==.',Na='Narfox:BAAALAAECgUIBAAAAA==.Narila:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Ne='Neameto:BAAALAAECgYICAAAAA==.Nefarox:BAAALAAECgEIAgAAAA==.Nek:BAAALAAECgYICwAAAA==.Nerve:BAAALAADCggICAABLAAECggIFQAIAGwgAA==.Ness:BAAALAAECgYIDgAAAA==.',Ni='Nico:BAAALAAECggIBgAAAA==.Niftyninja:BAAALAAECgcIDwAAAA==.Nightriderr:BAAALAADCgQIBAAAAA==.Nightstealer:BAAALAADCggIEAAAAA==.Nikkikayama:BAABLAAECoEVAAILAAgICRoTDwB5AgALAAgICRoTDwB5AgAAAA==.Ninigi:BAAALAAECgUIBAAAAA==.',No='Nonextinct:BAAALAADCgcICwAAAA==.Nonsequitur:BAAALAADCggICAAAAA==.Noobalot:BAAALAADCggICAAAAA==.Noran:BAAALAAECgQIBQAAAA==.Norikof:BAAALAAECgMIAwABLAAECgYICwABAAAAAA==.Norikoff:BAAALAAECgYICwAAAA==.',Nu='Nubzz:BAAALAAECgYIBwAAAA==.',Ny='Nyalla:BAAALAADCgcICAAAAA==.Nynox:BAAALAAECgIIBAAAAA==.',['Nê']='Nêin:BAAALAAECgMIBAAAAA==.',['Nü']='Nügg:BAAALAADCgcICgAAAA==.',Od='Odenpanda:BAAALAADCgUIBQAAAA==.',Oh='Ohgodspiders:BAAALAAECgMIBgAAAA==.',On='Onedge:BAAALAADCgcIBwAAAA==.Onlyvlprfans:BAABLAAECoEWAAIPAAgIjh4zCADWAgAPAAgIjh4zCADWAgAAAA==.',Oo='Oojoc:BAAALAADCgUIBQAAAA==.Oojocadin:BAAALAADCgIIAgAAAA==.Oojockin:BAAALAADCgcIBwAAAA==.Oojocninja:BAAALAADCgcIFAAAAA==.',Op='Ophina:BAAALAAECgEIAgAAAA==.',Or='Orah:BAAALAAECgIIAgAAAA==.Orangejello:BAAALAAECgMIBAAAAA==.Orkin:BAAALAAECgQIBAAAAA==.Ormis:BAAALAAECgYICQAAAA==.Orodruin:BAAALAADCgcIDQAAAA==.',Ox='Oxensham:BAAALAAECgcICwAAAA==.',Oy='Oyesdaddi:BAAALAADCgIIAgAAAA==.',Pa='Pallywall:BAAALAADCggICAAAAA==.Pana:BAAALAADCgcIBwAAAA==.Panamonktana:BAAALAAECgIIAgAAAA==.Pandy:BAAALAAECgEIAQAAAA==.Pannifer:BAAALAAECgMIBAAAAA==.Paolon:BAAALAADCggIDAAAAA==.Parillax:BAAALAADCgUIBQAAAA==.Pastalavista:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.',Pe='Peeperoni:BAAALAAECgMIAwAAAA==.Pesterfield:BAAALAADCgEIAQAAAA==.',Ph='Philkulson:BAAALAAECgQIBAABLAAFFAEIAQABAAAAAA==.',Pi='Picker:BAAALAADCgcIBwAAAA==.Pinecones:BAAALAAECgMIBAAAAA==.',Po='Pointer:BAAALAADCgcICgAAAA==.Poledra:BAAALAADCgcICAAAAA==.Poros:BAAALAADCgcICAAAAA==.Porterah:BAAALAAECgQIBAAAAA==.Poutyne:BAAALAAFFAIIAgAAAA==.',Pr='Preph:BAAALAADCgcICwAAAA==.Priestatute:BAEALAADCgMIAwAAAA==.',Pu='Pumadam:BAAALAADCggIEAAAAA==.Punkvc:BAAALAAECgQIBAAAAA==.',Py='Pyren:BAAALAADCgcICQAAAA==.',['Pá']='Párts:BAAALAAECgEIAQAAAA==.',Qi='Qinari:BAAALAAECgMIBAAAAA==.',Qu='Quaeras:BAAALAAECgMIBgAAAA==.',Ra='Ragé:BAAALAAECgQIBwAAAA==.Raytow:BAAALAADCggIDQAAAA==.Razelle:BAAALAAECgUIBAAAAA==.',Re='Reden:BAAALAAECggIAgAAAA==.Redrummurder:BAAALAAECgcICwAAAA==.Regarr:BAAALAAECgEIAQAAAA==.Rellu:BAAALAAECgYIEQAAAA==.Remus:BAAALAADCggIEAAAAA==.Ressix:BAAALAAECgQIBAAAAA==.',Ri='Rickybobby:BAAALAADCgYIAgAAAA==.Rigormortits:BAAALAADCggICAAAAA==.Risenone:BAAALAAECgcIDgAAAA==.',Ro='Romie:BAAALAAECggICAAAAA==.Ronborules:BAAALAAECgIIAgAAAA==.',Ru='Rumlock:BAAALAAECgUIBAAAAA==.Runkor:BAAALAADCgIIAgABLAAECgYIBwABAAAAAA==.',Sa='Sabai:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Salivan:BAAALAAECgEIAgAAAA==.',Sc='Scar:BAABLAAECoEWAAIQAAgIvhpMAwCuAgAQAAgIvhpMAwCuAgAAAA==.Scarecro:BAAALAAECgQIBAAAAA==.',Se='Sedo:BAAALAADCgUIBQAAAA==.Seiya:BAAALAAECgQIBwAAAA==.Selira:BAAALAAECgUIBAAAAA==.Senji:BAAALAADCgMIAwAAAA==.Sensi:BAAALAAECgMIBAAAAA==.Serkawne:BAAALAADCgIIAgAAAA==.',Sh='Shakiraa:BAAALAADCgMIAwAAAA==.Shakkirah:BAAALAAECgYICQAAAA==.Shamdood:BAAALAAECgMIAwAAAA==.Shamhuntzu:BAEBLAAECoEVAAMNAAgIyxaDFwBCAgANAAgIyxaDFwBCAgARAAUI8QUPGwCyAAAAAA==.Shampaign:BAAALAAECgYICgAAAA==.Shaoevoker:BAAALAADCggIEAAAAA==.Sharnara:BAAALAAECgEIAQAAAA==.Shawarma:BAAALAAECgMIBQAAAA==.Shazera:BAAALAADCggICAABLAADCggIEAABAAAAAA==.Shazira:BAAALAADCggIEAAAAA==.Shpeegs:BAAALAAECgMIAwAAAA==.',Si='Silentwounds:BAAALAAECgIIAgAAAA==.Silvercircle:BAAALAAECgMIBwAAAA==.Silverlord:BAAALAAECgEIAQAAAA==.Sineste:BAAALAADCggICAAAAA==.Siv:BAAALAAECgIIAgAAAA==.',Sl='Sliggeryjig:BAAALAAECgYIDQAAAA==.',Sn='Sneakydeath:BAAALAAECgYICQAAAA==.Snorg:BAAALAAECgIIAQAAAA==.',So='Solarnova:BAAALAAECgEIAQAAAA==.Solorn:BAAALAAECgQICAAAAA==.Soojoc:BAAALAADCgYIBgAAAA==.Southlondon:BAAALAADCgcIDAAAAA==.',Sp='Sploadin:BAAALAAECgIIBAAAAA==.Spygon:BAAALAAECgMIAwAAAA==.',Sq='Squadwiz:BAAALAAECgMIBAAAAA==.',St='Starstrike:BAAALAADCggICAAAAA==.Stoxolox:BAAALAAECgYICgAAAA==.Strobila:BAAALAAECgIIBAAAAA==.Studdmuffin:BAABLAAECoEUAAMSAAgIsh7VAwCkAgASAAgIlxvVAwCkAgATAAcInxwGJQDmAQAAAA==.',Su='Superholycow:BAAALAADCgYIBgAAAA==.Suzé:BAAALAAECgQIBAAAAA==.',Sw='Sweetta:BAAALAAECgEIAQAAAA==.',Sy='Sylvië:BAAALAADCgcIDAAAAA==.Synful:BAAALAADCgcIBwAAAA==.Syrioforel:BAAALAAECgMIBwAAAA==.',Ta='Takada:BAAALAAECgUIBgAAAA==.Tatanna:BAAALAADCgcICAAAAA==.Tazaan:BAAALAADCggIEAAAAA==.',Te='Telzindrov:BAAALAAECgMIBgAAAA==.Terockk:BAAALAADCgYIBgAAAA==.',Th='Thalgar:BAAALAADCggICAAAAA==.Thanoslykev:BAAALAADCggIDQAAAA==.Thisea:BAAALAADCgQIBAAAAA==.Threads:BAAALAAECgMIBAAAAA==.Thunderbot:BAAALAADCggIEAAAAA==.Thunderkak:BAAALAADCgQICAAAAA==.Thunderkat:BAAALAADCggIDQAAAA==.Théière:BAAALAAECgMIAwAAAA==.',Ti='Titoxs:BAAALAAECgMIAwAAAA==.',To='Tomathon:BAAALAADCggICAAAAA==.Toomuchrum:BAAALAADCgcIBwAAAA==.Topher:BAAALAADCgcIDQAAAA==.Totemlycool:BAAALAADCggICwABLAAECgEIAQABAAAAAA==.',Tr='Trac:BAAALAADCgcIBwAAAA==.Truelies:BAAALAADCgUIBQAAAA==.Tróuble:BAAALAADCgYICAAAAA==.',Ts='Tsukiki:BAAALAADCggIEAAAAA==.',Tu='Tuc:BAAALAAECgIIAgAAAA==.',Ty='Tyndareos:BAAALAADCgQIBAAAAA==.Typhoontravv:BAAALAAECgYIBgAAAA==.',Uf='Ufearme:BAAALAADCgYICwAAAA==.',Ug='Ugabooga:BAAALAAFFAIIAgAAAA==.Uggon:BAAALAAECgEIAgAAAA==.',Um='Umorvus:BAAALAAECgYICAAAAA==.',Ut='Uthur:BAAALAAECgMIBAAAAA==.Utterchaos:BAAALAAFFAEIAQAAAA==.',Va='Vaea:BAAALAAECgMIAwAAAA==.Vahsik:BAAALAADCgcICAAAAA==.Valizor:BAAALAAECgEIAQAAAA==.Varathal:BAAALAADCggICAAAAA==.Varty:BAAALAAECgcICQAAAA==.Vasila:BAAALAAECgMIAwAAAA==.Vayle:BAAALAAECgMIBgAAAA==.',Vc='Vc:BAAALAADCgcIDQAAAA==.',Ve='Veelanna:BAAALAADCgEIAQAAAA==.Vegapath:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.Velinasonara:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Vetta:BAAALAAFFAEIAQAAAA==.',Vg='Vger:BAAALAADCgcIBwAAAA==.',Vi='Vii:BAAALAADCgEIAQAAAA==.',Vo='Voideffects:BAAALAAECgMIBgAAAA==.Volgagrad:BAAALAAECgMIBQAAAA==.',Vs='Vshow:BAAALAADCggICAAAAA==.',Vu='Vulpïx:BAAALAADCgEIAQAAAA==.',Vy='Vyralith:BAAALAADCgEIAQAAAA==.',Wa='Walshera:BAAALAAFFAEIAQAAAA==.Warrchief:BAAALAADCgYIBgAAAA==.Wazul:BAAALAADCgcICAAAAA==.',Wh='Whisp:BAAALAADCggIDwAAAA==.Whisperz:BAAALAAECgQIAwAAAA==.',Wi='Wick:BAAALAADCgQIBAAAAA==.Winchesters:BAAALAADCgcIBwAAAA==.Windstone:BAAALAAECggIDwAAAA==.',Wo='Wolfsbanne:BAAALAADCgQIBAAAAA==.Woxof:BAAALAADCggICAAAAA==.',Wu='Wuoshi:BAAALAADCgQIBAAAAA==.Wuwii:BAAALAAECgMIBgAAAA==.',Wy='Wylddemon:BAAALAADCggIEAAAAA==.',Xa='Xara:BAAALAAECgQIBAAAAA==.',Xe='Xeroxoxo:BAAALAAECgcIDwAAAA==.',Xi='Xieren:BAAALAAECggIDgABLAAFFAIIAgABAAAAAA==.',Ym='Ymedruid:BAABLAAECoETAAIQAAgIth4YAwC5AgAQAAgIth4YAwC5AgAAAA==.',Yo='Yoroichi:BAAALAAECgMIBAAAAA==.',Yu='Yuck:BAAALAAECgIIAgAAAA==.Yueyue:BAAALAAECgMIBAAAAA==.',['Yá']='Yáng:BAAALAAECgQIBwAAAA==.',Za='Zandaloog:BAAALAADCggICAAAAA==.Zanris:BAAALAAECgEIAgAAAA==.Zaptor:BAAALAADCgcICAAAAA==.Zaridi:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Zarrgos:BAAALAADCgcIBwAAAA==.Zayala:BAAALAADCgMIAwABLAAECgMIBgABAAAAAA==.',Ze='Zeldorie:BAAALAAECgIIAQAAAA==.Zeniel:BAAALAADCggICAAAAA==.Zennder:BAAALAAECgMIBAAAAA==.Zenum:BAAALAADCgcICQAAAA==.Zethic:BAAALAAECgMIAwAAAA==.',Zi='Ziral:BAAALAADCgcIDQAAAA==.',Zo='Zoobee:BAAALAAECgIIBAAAAA==.Zoog:BAABLAAECoEVAAIJAAgIfho0BwBYAgAJAAgIfho0BwBYAgAAAA==.',Zy='Zyphera:BAAALAAECgMIBgAAAA==.Zyvara:BAAALAAECgEIAQAAAA==.',['Às']='Àsdread:BAAALAAECgUIBgAAAA==.',['Áp']='Ápollo:BAAALAAECgIIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end