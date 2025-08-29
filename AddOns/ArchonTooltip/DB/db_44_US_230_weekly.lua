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
 local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Warrior-Fury','Monk-Brewmaster','Priest-Shadow','Hunter-BeastMastery','Rogue-Assassination','DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction',}; local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=44,date='2025-08-29',data={Ai='Aigis:BAAALAADCggIEAAAAA==.',Al='Aldric:BAAALAAFFAIIBAAAAA==.Alpyne:BAAALAAECgMIBgAAAA==.',Am='Amnoon:BAAALAAECgIIBAAAAA==.Amri:BAAALAAECgcIEgAAAA==.',An='Andaro:BAAALAAECgUICAAAAA==.',Aq='Aquas:BAAALAADCgcIBwAAAA==.',Ar='Ardbert:BAAALAADCgEIAQAAAA==.Ardrhys:BAAALAADCgcIBwAAAA==.Artikin:BAAALAADCgIIAgAAAA==.',Au='Automagic:BAAALAADCggICAAAAA==.',Av='Avondwella:BAAALAAECgYICgAAAA==.',Az='Azgo:BAAALAADCgcIBwAAAA==.',Ba='Balm:BAAALAAECgYICwAAAA==.',Be='Beastcloud:BAAALAAECgIIAwAAAA==.Berzerker:BAAALAAECgYICwAAAA==.',Bi='Bigsquee:BAAALAADCgYIBgAAAA==.',Bl='Blob:BAAALAAECggICAAAAA==.',Bo='Bonedstew:BAAALAAECgIIBAAAAA==.Bonestorm:BAAALAADCgUIBQAAAA==.Boondiggles:BAAALAAECgcICgAAAA==.Boucouyoucou:BAAALAAECgcIDQAAAA==.',Br='Bratton:BAAALAAECgEIAQAAAA==.Breaddeqs:BAAALAADCggICAAAAA==.Bremiton:BAAALAADCgUIBQABLAAECgYICwABAAAAAA==.Brickhousee:BAAALAADCggICwAAAA==.Brud:BAAALAADCgYIBgAAAA==.Brunstan:BAAALAAECgcIEAAAAA==.',Bu='Burningish:BAAALAAECgMIBgAAAA==.',By='Byakugan:BAAALAAECgIIAgAAAA==.',['Bé']='Béley:BAAALAADCggICAABLAAECgcIEgABAAAAAA==.',['Bø']='Bønitalèè:BAAALAAECgEIAQAAAA==.',Ca='Caleco:BAAALAADCgYIDgAAAA==.Calvisilocks:BAAALAAECgIIBAAAAA==.Calvisniper:BAAALAADCgcIAwAAAA==.',Ce='Cenobia:BAAALAADCggIDwAAAA==.',Co='Cosmicspark:BAAALAADCggIEQAAAA==.Cosmyc:BAAALAADCgQIBAAAAA==.',Cr='Creation:BAAALAADCgIIAgAAAA==.Crentist:BAAALAAECgEIAQAAAA==.Critoliz:BAAALAAECgQIAQAAAA==.',Cw='Cwds:BAAALAADCggIEAAAAA==.',Da='Daddyhunt:BAAALAADCgUIBAAAAA==.Daddyissue:BAAALAADCgYIBgAAAA==.Daggo:BAAALAADCgQICAAAAA==.Darkreaper:BAAALAADCgcIAwAAAA==.Davros:BAAALAADCgcIDQAAAA==.',De='Deadeyezz:BAAALAADCgUIBQAAAA==.Dellandre:BAAALAADCgcIAwABLAAECgIIBAABAAAAAA==.',Dh='Dhampyre:BAAALAAECgMIBgAAAA==.',Di='Diabolist:BAAALAAECgIIAgAAAA==.Dianafyre:BAAALAAECgIIAgAAAA==.Diosed:BAAALAADCggICAAAAA==.Divineflavor:BAAALAAECgYICwAAAA==.',Do='Doclock:BAAALAADCgUICAAAAA==.Doktaga:BAAALAAECgMIAwAAAA==.',Dr='Dragonlily:BAAALAADCgEIAQAAAA==.Drarken:BAAALAAECgcIEgAAAA==.Druidy:BAAALAAECggIDQAAAA==.',Ed='Edging:BAAALAAECgMIAwAAAA==.',El='Eldarr:BAAALAADCgcIDgABLAAECgYICwABAAAAAA==.Eldrist:BAAALAAECgYICwAAAA==.',En='Enazen:BAAALAAECgIIAwAAAA==.Endlol:BAAALAAECgMIBQAAAA==.',Er='Eredaria:BAAALAADCgcIBwAAAA==.Ergo:BAABLAAECoEWAAMCAAgIFSJMAgAMAwACAAgIFSJMAgAMAwADAAEI0hkUbwA8AAAAAA==.',Fa='Fadedheartt:BAAALAADCgcIDAAAAA==.Fadednight:BAAALAAECgYICwAAAA==.Fakedeath:BAAALAADCgUIBQAAAA==.Falkun:BAAALAADCgQIBAAAAA==.',Fe='Felwhisper:BAAALAADCgEIAQAAAA==.',Fl='Floptropican:BAAALAAECgcIEAAAAA==.',Fo='Forexis:BAAALAADCgcIBwAAAA==.Foxykrikka:BAAALAADCgQIBAAAAA==.',Fr='Frostybreath:BAAALAAECgMIBQAAAA==.Frostybrews:BAAALAAECgIIAgABLAAECgMIBQABAAAAAA==.Frostychan:BAAALAADCgQIBAABLAAECgMIBQABAAAAAA==.Fróstblight:BAAALAADCggIEAAAAA==.',Ga='Gadjit:BAAALAADCgQIBAAAAA==.',Ge='Geida:BAAALAADCgcIBwAAAA==.',Gl='Glendanzig:BAAALAADCgYICQAAAA==.Glendanzigs:BAAALAAECgMIAwAAAA==.Glendanzigz:BAAALAADCgQIBAAAAA==.',Gr='Grimlee:BAAALAADCgYIBwAAAA==.Gromuul:BAAALAAECgIIAgAAAA==.',Ha='Halitosiss:BAAALAADCggICAABLAAECgMIBgABAAAAAA==.Hathaway:BAAALAAECgEIAgAAAA==.',He='Hellenkiller:BAAALAAECgIIAgAAAA==.',Hi='Highly:BAAALAADCggICAAAAA==.',Ho='Hollowheart:BAAALAAECgIIAgAAAA==.Holybell:BAAALAADCgUIBQAAAA==.Holyshyyt:BAAALAADCggICQAAAA==.',Hu='Huntism:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.',Hy='Hylanna:BAAALAADCggIDwAAAA==.',['Hó']='Hónor:BAAALAAECgYICwAAAA==.',Ic='Ici:BAAALAAECgYICQAAAA==.',Ik='Ikyaria:BAAALAAECgYIDQAAAA==.',Im='Imlerith:BAAALAADCgUIBQAAAA==.',In='Incharge:BAAALAADCgEIAQAAAA==.Intensifies:BAAALAAECgMIBgAAAA==.',Is='Iskothar:BAAALAADCggIDwAAAA==.',Iv='Ivarboneless:BAAALAADCggIDgAAAA==.',Ja='Jackz:BAAALAAECgYIBgAAAA==.Jackzlock:BAAALAADCggICAAAAA==.Jailer:BAAALAADCgQIBAAAAA==.',Ka='Kaelcyde:BAAALAADCgYICQAAAA==.Kakipriest:BAAALAAECgIIAgAAAA==.Karone:BAAALAADCggICAAAAA==.Katara:BAAALAADCgcIBwAAAA==.',Ki='Kiliko:BAAALAAECgEIAQAAAA==.',Ko='Kodera:BAAALAADCgYIEQAAAA==.',Ku='Kuru:BAAALAADCgQIBAAAAA==.',Ky='Kyronix:BAAALAAECgMIAwAAAA==.',['Kó']='Kóth:BAAALAADCgUIBQAAAA==.',La='Langarde:BAAALAAECgIIAwAAAA==.Lastdragon:BAAALAADCggIBwAAAA==.',Le='Leonxanimus:BAAALAADCggICAAAAA==.Leonz:BAABLAAECoEWAAIEAAgIJyWbAQBjAwAEAAgIJyWbAQBjAwAAAA==.Letharanos:BAEALAAECgUICgAAAA==.Lethasham:BAEALAADCgYIBgABLAAECgUICgABAAAAAA==.',Li='Liraffemyn:BAAALAAECgcIDwAAAA==.Lithvia:BAAALAADCggICAAAAA==.',Lu='Lustiri:BAAALAADCggICAAAAA==.',Ma='Madarauchiha:BAAALAAECgIIAgAAAA==.Madeatt:BAAALAAECgYICQAAAA==.Maitai:BAAALAAECggIEAABLAADCggICAABAAAAAA==.Maldran:BAAALAAECgIIBAAAAA==.Malianona:BAAALAADCgEIAQAAAA==.Marien:BAAALAAECgIIAwAAAA==.',Me='Meastoso:BAAALAAECgYIDQAAAA==.Mechanizedtv:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Megarai:BAAALAAECgEIAQAAAA==.Mehuman:BAAALAADCggIEQAAAA==.Mehumanhuntr:BAAALAADCgUIBQAAAA==.Mehumanlock:BAAALAAECgYICwAAAA==.Mepandawife:BAAALAADCggIEAAAAA==.Metaphorical:BAAALAAECgIIAgAAAA==.Meworgendk:BAAALAADCgcIBwAAAA==.',Mi='Midgarr:BAAALAADCgQIBAAAAA==.',Mo='Mogh:BAAALAADCgQIBAAAAA==.Moobubbles:BAAALAADCgQIBAAAAA==.Moonscale:BAAALAADCggIDgAAAA==.Mordai:BAAALAADCgQIBgAAAA==.',Na='Nailia:BAAALAADCggIDwAAAA==.Nailz:BAAALAAECgMIBgAAAA==.Narsissa:BAAALAADCgUIBgAAAA==.Nazzle:BAAALAADCggIDwAAAA==.',Ni='Nightshield:BAAALAADCggIEQAAAA==.Niptuck:BAAALAADCgQIBAAAAA==.Niral:BAAALAADCgIIAgAAAA==.',No='Noahcalc:BAAALAAFFAIIAgAAAA==.Notbacon:BAAALAADCgQIBAAAAA==.',Oh='Ohmylanta:BAAALAAECgcIDgAAAA==.Ohmylantâ:BAAALAADCgYIDAAAAA==.',Oo='Oopzinbootz:BAAALAAECgIIAgAAAA==.',Or='Oriax:BAAALAAECgIIAgAAAA==.',Ow='Owhowhh:BAAALAADCgIIAgAAAA==.',['Oâ']='Oâth:BAAALAAECgQIBwAAAA==.',Pa='Paldozer:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Pallywacker:BAAALAAECgIIAwAAAA==.Panzerkan:BAAALAADCgcIBwAAAA==.Panzerkìn:BAAALAADCgQIBgAAAA==.Parsegodx:BAABLAAECoEWAAIFAAgIoSGwAgDdAgAFAAgIoSGwAgDdAgAAAA==.',Ph='Phantomturk:BAAALAADCggIEAAAAA==.Phininik:BAAALAAECgMIAwAAAA==.',Pi='Pigish:BAAALAADCggIEQAAAA==.Pigishdog:BAAALAAECgMIBgAAAA==.',Po='Pojuro:BAAALAAECgUIBQAAAA==.Posh:BAAALAAECgUIBQAAAA==.',Pr='Priestsk:BAABLAAECoEWAAIGAAgIRSWqAQBcAwAGAAgIRSWqAQBcAwAAAA==.Prismara:BAAALAADCgcICwAAAA==.',Py='Pyke:BAAALAADCgQIBAAAAA==.',Qu='Quadnodteddy:BAAALAADCggIEgAAAA==.',Ra='Rakarg:BAAALAAECgQIBQAAAA==.Rantsuu:BAAALAAECgUIBQABLAAECgcIEAABAAAAAA==.',Re='Redthing:BAAALAADCgYICQAAAA==.Remitus:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.',Ri='Rickÿ:BAAALAAECgIIAgAAAA==.Ripndip:BAAALAAECgQIAQAAAA==.',Ro='Rooter:BAAALAAECggIEgAAAA==.',Sa='Salmanius:BAAALAAECgMIBgAAAA==.',Se='Seongwar:BAAALAAECgIIAgAAAA==.',Sh='Shadowlight:BAAALAAECgMIBgAAAA==.Shadówhealz:BAAALAADCgEIAQAAAA==.Sharpshotjak:BAAALAADCggIAQAAAA==.Shekadreu:BAAALAADCggICAAAAA==.Shimera:BAAALAAECgIIBAAAAA==.Shockawar:BAABLAAECoEWAAIEAAgIzR0RCgDEAgAEAAgIzR0RCgDEAgAAAA==.Shootrmcgavn:BAABLAAECoEVAAIHAAgIRySqAQBdAwAHAAgIRySqAQBdAwAAAA==.Shrive:BAAALAAECgIIBAAAAA==.',Si='Silverblood:BAAALAADCggIDwAAAA==.',So='Solthiel:BAAALAADCgQIBAAAAA==.Somerled:BAAALAAECgMIBAAAAA==.',Sq='Squirtina:BAAALAAECgYIDAAAAA==.',St='Starrdazze:BAAALAADCgcIDAAAAA==.Stump:BAAALAADCgEIAQAAAA==.',Su='Sukdatboi:BAAALAADCggICQAAAA==.Sunstrike:BAAALAADCgEIAQAAAA==.',Ta='Talden:BAAALAAECgMIBgAAAA==.Talkamar:BAAALAAECgYICgAAAA==.Taylorswift:BAAALAAECgIIBAAAAA==.',Te='Tessio:BAAALAADCggIFAAAAA==.',Th='Thekourge:BAAALAAECgIIBAAAAA==.Thenard:BAAALAAECgMIAwAAAA==.Therealcafna:BAAALAADCgYIBwAAAA==.Thukunaenhan:BAAALAAECgMICgAAAA==.',Ti='Tirra:BAAALAAECgMIBgABLAAECgcIEgABAAAAAA==.',To='Tomuchmakeup:BAAALAAECgEIAQAAAA==.Touritos:BAAALAAECgEIAQAAAA==.',Tu='Tulirenpo:BAAALAADCgQIBAAAAA==.',Tw='Twogora:BAAALAAECgIIAgAAAA==.Twotoeundoer:BAAALAAECgYIEQAAAA==.',Ty='Tydemonhorde:BAAALAADCgYIBQAAAA==.Tydes:BAAALAAECgMIAwAAAA==.Tyler:BAAALAADCggIEAAAAA==.',Ur='Uritao:BAAALAADCgEIAQAAAA==.',Va='Valissar:BAAALAADCgQIBAAAAA==.Vanan:BAAALAAECgIIAgAAAA==.Vancliffe:BAAALAADCggICAAAAA==.',Ve='Veldyn:BAAALAADCgQIBAAAAA==.Veramond:BAAALAADCgIIAgAAAA==.',Vi='Vibes:BAAALAADCgQIBAAAAA==.Vitira:BAAALAAECgMIAwAAAA==.',Vo='Volk:BAABLAAECoEWAAIIAAgIeyWpAABqAwAIAAgIeyWpAABqAwAAAA==.Volkana:BAAALAAECgIIAgABLAAECggIFgAIAHslAA==.',Vs='Vse:BAAALAADCggIBQABLAAECggIAwABAAAAAA==.Vsesosorry:BAAALAAECggIAwAAAA==.',Vy='Vyne:BAAALAADCgYICQAAAA==.',['Vä']='Väna:BAAALAAECgMIBgAAAA==.',Wa='Wardozer:BAAALAADCggICAAAAA==.',Wo='Worgenkrantz:BAAALAAECgIIAgAAAA==.',Wr='Wrenlyn:BAABLAAECoEUAAIJAAcIBSDSEgBwAgAJAAcIBSDSEgBwAgAAAA==.',Wt='Wtdatmouthdo:BAAALAAECggIDgAAAA==.',Xa='Xaedilis:BAAALAADCgcIDQAAAA==.',Xi='Xiaohi:BAAALAADCgcIBwAAAA==.',Xo='Xolòtl:BAAALAAECgYICgAAAA==.',Xy='Xymos:BAABLAAECoEWAAMKAAgI4yTuAQBVAwAKAAgI2CTuAQBVAwALAAQIECElCwCPAQAAAA==.',Ya='Yakjar:BAAALAADCgMIAwAAAA==.Yakul:BAAALAADCgcIBwAAAA==.',Ys='Yserra:BAAALAAECgMIAwAAAA==.',Za='Zaes:BAAALAADCgcIBwAAAA==.Zalyia:BAAALAADCgcIDAAAAA==.Zangief:BAAALAADCgQIBwAAAA==.Zarthas:BAAALAAECgQIBAAAAA==.',Ze='Zelydah:BAEALAADCgQIBAABLAAECgYICQABAAAAAA==.Zexpert:BAAALAAECgMIBgAAAA==.',['Zô']='Zôrt:BAAALAADCggIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end