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
 local lookup = {'Unknown-Unknown','DeathKnight-Frost','Mage-Arcane','Priest-Shadow','Mage-Frost','Shaman-Enhancement','DeathKnight-Unholy','Paladin-Retribution','Druid-Feral','Mage-Fire',}; local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aariadne:BAAALAADCggIDwABLAAECgYIDAABAAAAAA==.',Ab='Abp:BAAALAADCgIIAgAAAA==.',Ae='Aedrelyn:BAAALAAECgEIAQAAAA==.Aevumu:BAAALAAECgQIBQAAAA==.',Af='Affonasei:BAAALAAECggIAwAAAA==.',Ai='Aitvaras:BAAALAADCgUIBQAAAA==.',Ak='Akashi:BAAALAAFFAEIAQAAAA==.Akkad:BAAALAAECgIIAgAAAA==.',Al='Alacrodie:BAAALAADCgMIBQAAAA==.Alarric:BAAALAADCggICAAAAA==.Alfya:BAAALAAECgcIDgAAAA==.Alia:BAAALAAECgYIBgABLAAFFAMIBQACALoYAA==.',An='Anchronus:BAAALAAECgIIAgAAAA==.Annaborshen:BAAALAADCgYICgAAAA==.Annaiya:BAAALAADCgcIEwAAAA==.Antoccino:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Anvelor:BAAALAADCgcICAAAAA==.',Ar='Aragorno:BAAALAADCggIDwAAAA==.Archembrecht:BAAALAADCgYIBgAAAA==.Arcturen:BAAALAADCggIDwAAAA==.Ardala:BAAALAADCggIBwAAAA==.Arlos:BAAALAADCgcICwAAAA==.Arthemis:BAAALAADCggICAAAAA==.Arthor:BAAALAADCgEIAQAAAA==.',As='Ashalana:BAAALAADCgcICQAAAA==.Astäroth:BAAALAADCggICAABLAAECgQIBAABAAAAAA==.',At='Atomic:BAAALAADCggIGQAAAA==.',Aw='Awopaho:BAAALAADCgcIDgAAAA==.',Az='Azeral:BAAALAADCgEIAQAAAA==.Azylstrid:BAAALAAECgYICgAAAA==.',Ba='Babyshred:BAAALAADCgcIBwAAAA==.Bahnkari:BAAALAAECgQIBgAAAA==.Bananasloth:BAAALAAECgEIAQABLAAECgcIDQABAAAAAA==.Banokalypse:BAAALAAECgIIBAAAAA==.Banuhoh:BAAALAADCggIDwABLAAECgIIBAABAAAAAA==.Baspir:BAAALAAECgcIDwAAAA==.Bastahunter:BAAALAAECgYICQAAAA==.',Be='Belisarius:BAAALAAECgMIAwAAAA==.Belrae:BAAALAAECgMIAwAAAA==.Bethaliz:BAAALAADCgUIBQAAAA==.Bezieck:BAAALAAECgMIAwAAAA==.',Bi='Bigollock:BAAALAADCgcIBwAAAA==.',Bo='Bobb:BAAALAADCgYIBwAAAA==.',Br='Bram:BAAALAADCggIAgABLAADCggICAABAAAAAA==.Brok:BAAALAADCggIDgAAAA==.Brokegamer:BAAALAAECgYIDQABLAAFFAMIBQADAGgeAA==.Bronad:BAAALAAECgEIAQAAAA==.Broomhandle:BAAALAAECgQIBQAAAA==.Brulure:BAAALAADCgYIBgAAAA==.',Bu='Bubbletea:BAAALAAECgcIDgAAAA==.Bumbushka:BAAALAAECgMIBQAAAA==.Burinn:BAAALAAECgIIBAAAAA==.Bus:BAAALAAECgUICAAAAA==.',Ca='Caeus:BAAALAAECgQIBgAAAA==.Cantaloupe:BAAALAAECgEIAQABLAAECgYICQABAAAAAA==.Cardo:BAAALAADCgUIBQAAAA==.Carnaubaa:BAAALAAECgMIAwAAAA==.Carolinabele:BAAALAADCggIDwAAAA==.Cauud:BAAALAADCgUICAAAAA==.',Cb='Cbd:BAAALAAECgYICgAAAA==.',Ch='Chelanelf:BAAALAADCggIDwABLAAECgIIBAABAAAAAA==.Chewseph:BAAALAADCggICAAAAA==.Chizuko:BAAALAADCggICgAAAA==.Chronicler:BAAALAADCgUICgAAAA==.',Ci='Cigs:BAAALAAECgYICQABLAAFFAMIBQADAGgeAA==.Cinnabunz:BAAALAAECgIIAgAAAA==.',Cl='Clancy:BAAALAAECgMIAwAAAA==.Cleurisse:BAAALAAECgcIDAAAAA==.',Co='Conjuredeez:BAAALAAECgcIDgAAAA==.Coraf:BAAALAAECgEIAQAAAA==.',Cr='Cravix:BAAALAADCgcIEAAAAA==.Crawlercarl:BAAALAADCgQIBAAAAA==.Crowley:BAAALAAECgMIAwAAAA==.Cruoris:BAAALAAECgMIAwAAAA==.',Cu='Cuvier:BAAALAAECgEIAQAAAA==.',Da='Daemonous:BAAALAAECggIBQAAAA==.Danak:BAAALAADCgMIBQAAAA==.',De='Demisi:BAAALAAECgEIAQAAAA==.Derangedsp:BAAALAAECgcIDQAAAA==.',Di='Diasundra:BAAALAAECgYIDgAAAA==.',Do='Doomkìn:BAAALAAECgMIBQAAAA==.',Dr='Drransom:BAAALAADCgMIBAAAAA==.Druidbro:BAAALAADCggICAAAAA==.Druk:BAAALAAECgIIAgAAAA==.Dryan:BAAALAAECgMIAwAAAA==.',Du='Duo:BAAALAAECgcIDgAAAA==.Duranna:BAAALAAECgcIDgAAAA==.Durzind:BAAALAADCgMIAwAAAA==.',El='Elixir:BAAALAADCgcIBwAAAA==.Ellistrae:BAAALAAECgYICwAAAA==.',En='Endressa:BAAALAAECgMIAwAAAA==.',Ev='Evoke:BAAALAADCgYIBgAAAA==.',Ez='Ezrì:BAAALAADCgMIBQAAAA==.',Fa='Faddeyshnek:BAAALAAECgYICgAAAA==.Faerys:BAAALAAECgQIBAAAAA==.Fauntleroy:BAAALAAECgcIDgAAAA==.',Fe='Felgying:BAAALAAECgIIBAAAAA==.',Fi='Finaria:BAAALAAECgYICwAAAA==.Fireblazesix:BAAALAADCgcIBwAAAA==.Fish:BAACLAAFFIEFAAIEAAMIQSRpAQBLAQAEAAMIQSRpAQBLAQAsAAQKgRgAAgQACAjeJhMAAKEDAAQACAjeJhMAAKEDAAAA.',Fl='Fluffywuffy:BAAALAADCgYIBwAAAA==.',Fo='Footfinger:BAAALAADCgIIAgABLAAECgMIBQABAAAAAA==.Forsynth:BAAALAAECgMIAwAAAA==.',Fr='Frostynippzz:BAAALAADCgcIDgAAAA==.Frostytree:BAAALAAECgMIAwAAAA==.',Ga='Galvonic:BAAALAADCgcIDgAAAA==.',Ge='Gewitt:BAAALAAECgMIBAAAAA==.',Gi='Gimmighoul:BAAALAAECgYIDAAAAA==.',Gl='Glinda:BAAALAADCgMIAwAAAA==.',Gr='Grazienne:BAAALAADCgEIAQAAAA==.Grif:BAAALAADCggIBQAAAA==.Grimbaine:BAAALAAECgMIAwAAAA==.Gripperfu:BAAALAADCggIDQAAAA==.Grippermage:BAAALAAECgMIAwAAAA==.Gryphh:BAAALAADCgcIAwAAAA==.Gryphin:BAAALAADCgQIBAAAAA==.',Gu='Guevara:BAAALAAECgIIBAAAAA==.',Gy='Gying:BAAALAADCggIDwABLAAECgIIBAABAAAAAA==.',Ha='Hannie:BAAALAADCgMIBQAAAA==.',Ho='Holywelt:BAAALAAECgIIAgAAAA==.',Hu='Huntard:BAAALAAECgYICQAAAA==.',Ia='Ianthe:BAAALAADCggICwAAAA==.',Ib='Ibrahimovic:BAAALAAECgEIAQAAAA==.',Il='Illannä:BAAALAADCgcICgAAAA==.Ilovedesk:BAAALAAECgMIAwAAAA==.',In='Inafume:BAAALAADCgQIBAAAAA==.Injustice:BAAALAAECgcICwAAAA==.Inoxia:BAAALAADCgYIBgAAAA==.',It='Ithruyn:BAAALAADCgcIDgAAAA==.',Ja='Jamurra:BAAALAADCggIFwAAAA==.Jarnathan:BAAALAADCgQIBAAAAA==.Jasperofnym:BAAALAADCgIIAgAAAA==.Jaylinn:BAAALAAECgcIDgAAAA==.Jazzmend:BAAALAADCgUIBQAAAA==.',Ji='Jimsonweed:BAAALAAECgIIAgAAAA==.',Jo='Josie:BAAALAAECgEIAQAAAA==.',Ka='Kael:BAAALAAECgEIAQAAAA==.Kalaanri:BAAALAADCggIDwAAAA==.Kaleberry:BAAALAADCgcIBwAAAA==.Kalyandra:BAAALAADCgYIBgAAAA==.Karumie:BAAALAAECgcIDwAAAA==.Kassann:BAAALAAECgIIAwABLAAECgQIBgABAAAAAA==.Kateera:BAAALAAECgQIBAAAAA==.',Ke='Keden:BAAALAADCgMIBQAAAA==.Keljaden:BAAALAAECgIIBAAAAA==.',Ki='Kidashia:BAAALAADCggICAAAAA==.Kilro:BAAALAADCgcIBwAAAA==.Kittý:BAAALAADCggICQAAAA==.',Kn='Knotafurry:BAAALAADCggIBQAAAA==.',Ko='Koggs:BAAALAADCgYICQABLAAECgEIAQABAAAAAA==.Kohnor:BAAALAADCgMIBQAAAA==.Kopi:BAAALAAECgIIAgAAAA==.Kopiccino:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.Korlatt:BAAALAAECgEIAQAAAA==.Kowalabear:BAAALAAECgcIDAAAAA==.',Kr='Krygore:BAAALAADCgUIBQAAAA==.Krìmzar:BAAALAADCggIDwAAAA==.',Ku='Kurston:BAAALAAECgIIBAAAAA==.',Ky='Ky:BAAALAAECgcIBwAAAA==.Kymakazie:BAAALAAECgMIAwAAAA==.',La='Lathelinis:BAAALAADCggICAAAAA==.',Le='Leeven:BAAALAADCgMIAwABLAAECgMIAwABAAAAAQ==.Lexx:BAAALAADCgUICAAAAA==.',Lh='Lhia:BAAALAAECgMIAwAAAA==.',Li='Liady:BAAALAADCgYIBgAAAA==.Liirah:BAAALAADCgMIBQAAAA==.Lineda:BAAALAAECgYICgAAAA==.',Ma='Magdelyne:BAAALAAECggIAwAAAA==.Magni:BAAALAAECgMIAwAAAA==.Makgora:BAAALAADCggICAAAAA==.Makklehaney:BAAALAAECgMIAwAAAA==.Marovingian:BAAALAAECgQIBwAAAA==.',Mc='Mcsluts:BAAALAAECgIIAgAAAA==.',Me='Merciala:BAAALAAECgIIBAAAAA==.',Mo='Moddoxx:BAAALAAECgMIAwAAAA==.Moonsii:BAAALAAECgIIAgAAAA==.Mooreme:BAABLAAECoEUAAIFAAgIZSPEAQAqAwAFAAgIZSPEAQAqAwAAAA==.Mooroth:BAAALAAECgEIAQAAAA==.Morekk:BAAALAADCgcIBwAAAA==.Morozko:BAAALAAECgEIAQAAAA==.Moxxie:BAAALAADCgYICQAAAA==.',Ms='Msmana:BAAALAADCggICgAAAA==.',Mu='Muddler:BAAALAAECgEIAQAAAA==.Murciielago:BAAALAADCgcIBwAAAA==.Musclemoomy:BAAALAAECgQIBwAAAA==.',Na='Nadd:BAAALAADCggIFAAAAA==.',Ne='Negrido:BAAALAAECgcIDgAAAA==.Nei:BAAALAAECgUIBwAAAA==.',No='Nobrainer:BAAALAADCggICAAAAA==.Nomino:BAAALAADCggIDwAAAA==.Noriyuki:BAAALAADCgYICQAAAA==.',Nu='Nugatory:BAAALAADCgYICgABLAAFFAIIAwABAAAAAA==.',Og='Ogrekin:BAABLAAECoEWAAIGAAgIdh3pAgCTAgAGAAgIdh3pAgCTAgAAAA==.',Ol='Oldcrusty:BAACLAAFFIEFAAMCAAMIuhhZCACpAAACAAIIrBZZCACpAAAHAAEI1xyFBABnAAAsAAQKgRwAAwIACAitI/gEACMDAAIACAitI/gEACMDAAcABAgKJAgPAKoBAAAA.Olderon:BAAALAAECgIIAgAAAA==.Oldgraybush:BAABLAAECoEUAAIEAAYIyx+kFQD+AQAEAAYIyx+kFQD+AQABLAAFFAMIBQACALoYAA==.Olrong:BAAALAAECgMIAwAAAA==.Oluja:BAAALAADCgUIBQAAAA==.',Op='Opaalite:BAAALAADCgUIBQAAAA==.Oppressin:BAAALAAECgMIAwAAAA==.',Or='Orochimaru:BAAALAADCgIIAgAAAA==.',Ov='Overdoom:BAAALAAECgcIDgAAAA==.',Pa='Paladinjohn:BAABLAAECoEWAAIIAAgIPSXnBAAzAwAIAAgIPSXnBAAzAwAAAA==.Paladinmacie:BAAALAAECgIIAgAAAA==.Palykat:BAAALAADCggIDwAAAA==.Pandangit:BAAALAAECgUICAAAAA==.',Pe='Peacekeeper:BAAALAADCggICAAAAA==.Pennywisé:BAAALAAECgcIDgAAAA==.Percentguy:BAAALAAECgMIBQAAAA==.',Ph='Phenika:BAAALAADCggIFgAAAA==.',Pr='Priestatexam:BAAALAADCgcICAAAAA==.Progresz:BAAALAADCggIDgAAAA==.',Ps='Psycodellic:BAAALAADCggICAAAAA==.',Pu='Pugfoo:BAAALAADCgMIAwAAAA==.',Py='Pykel:BAAALAAECgcIDgAAAA==.',Qa='Qaren:BAAALAADCgUICAAAAA==.',Qp='Qpon:BAAALAADCgUICAAAAA==.',Qu='Quike:BAAALAADCgQIBAAAAA==.Quilinofnym:BAAALAADCgYICQAAAA==.',Ra='Raishun:BAAALAADCggIDAAAAA==.',Re='Redeemly:BAAALAAECgcICwAAAA==.Reeven:BAAALAAECgMIAwAAAQ==.Reika:BAAALAADCgQIBAAAAA==.Ressurectjin:BAAALAAECgUIBwAAAA==.Retrochipz:BAAALAADCgYIBgAAAA==.',Rh='Rhetegast:BAAALAAECgcIEAAAAA==.',Ri='Rike:BAEALAAECgMIAwAAAA==.Riobla:BAAALAADCgEIAQAAAA==.',Ro='Roflbackpack:BAAALAAECgYIDQAAAA==.Rokuu:BAAALAAECgQIBgAAAA==.Rolan:BAAALAADCgUIBQAAAA==.Rolandin:BAAALAAECgMIAwAAAA==.',Ru='Rumi:BAAALAADCgYIBwAAAA==.',Ry='Rylagosa:BAAALAAECgEIAQAAAA==.',['Rå']='Råion:BAAALAAECgQIBAAAAA==.',['Rê']='Rêdrum:BAAALAAECgYIDAAAAA==.',Sa='Sabithia:BAAALAADCgMIAwAAAA==.Sadoh:BAAALAADCgYICgAAAA==.Salandria:BAAALAAECgYIDAAAAA==.Salandriath:BAAALAADCgYIBgAAAA==.Sarionian:BAAALAAECgIIAgAAAA==.Sarvin:BAAALAAECgcIEAAAAA==.',Se='Sengir:BAAALAADCggIDwAAAA==.Serenitae:BAAALAAECgYIBgAAAA==.Sevsa:BAAALAAECgMIAwAAAA==.',Sh='Shambúlance:BAAALAAECgEIAQAAAA==.Shazlulu:BAAALAADCggIDwAAAA==.Shtamman:BAAALAAECgYICwAAAA==.Shuhuwua:BAAALAADCgYIBgAAAA==.Shyduex:BAAALAADCggIEwAAAA==.',Si='Singlemalt:BAAALAADCgMIAwAAAA==.',Sp='Spazzoid:BAABLAAECoEWAAIJAAgIESNYAQAbAwAJAAgIESNYAQAbAwAAAA==.Sporkulous:BAAALAADCgcIBwAAAA==.',Sq='Squiggle:BAAALAAECgEIAQAAAA==.',St='Stackd:BAAALAAECgIIAgAAAA==.Starling:BAAALAAECgcICQAAAA==.Stickybunz:BAAALAAECgUIBgABLAAECgcIEAABAAAAAA==.Stunseed:BAAALAAECgcIDgAAAA==.',Sw='Swabz:BAAALAADCgUIBQAAAA==.Sweetbunz:BAAALAAECgcIEAAAAA==.',Sy='Sydious:BAAALAADCgcICAAAAA==.Syre:BAAALAAECgcIDwAAAA==.Syver:BAAALAAECgIIAwAAAA==.',['Sì']='Sìrfuzywuzy:BAAALAADCgcIDgAAAA==.',Ta='Taniss:BAAALAAECgEIAQAAAA==.Tanner:BAAALAAECgQIBQAAAA==.Taylash:BAAALAADCgYIBgAAAA==.',Te='Tearful:BAAALAAECgYIDwAAAA==.Tedman:BAAALAAECgEIAQAAAA==.Temel:BAAALAAECgMIBgAAAA==.Tenelum:BAAALAADCgMIBQABLAAECgMIBgABAAAAAA==.Teostra:BAAALAAECgIIAgAAAA==.Testoecles:BAAALAADCgMIBAAAAA==.Teysä:BAAALAADCggICgAAAA==.',Th='Thaane:BAAALAAECgYIDAAAAA==.Thaine:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Thalonstin:BAAALAADCggIEgAAAA==.Thanevoker:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Thendezal:BAAALAAECgMIAwAAAA==.Theodrid:BAABLAAECoEaAAIIAAgIFiDqCgDQAgAIAAgIFiDqCgDQAgAAAA==.Thorislen:BAAALAADCggICAAAAA==.',Ti='Tigertigress:BAAALAAECgIIAgAAAA==.Tinkíe:BAAALAAECgcIDgAAAA==.',Tl='Tla:BAAALAADCgMIAwAAAA==.',To='Tosct:BAAALAAECgYICgAAAA==.',Tr='Trianan:BAAALAAECgEIAQAAAA==.Trippysheep:BAAALAAECgEIAQABLAAECgcIDQABAAAAAA==.Trippyshock:BAAALAADCgQIBAABLAAECgcIDQABAAAAAA==.Tristitia:BAAALAADCggICAAAAA==.',Ty='Tyche:BAAALAADCgUICAAAAA==.',Va='Vadar:BAAALAADCgcICAAAAA==.Vains:BAAALAAECgYICwAAAA==.Valrith:BAAALAADCggIFAAAAA==.',Ve='Verren:BAAALAAECgMIAwAAAA==.Veruun:BAAALAAECgMIBgAAAA==.Vesora:BAAALAAECgIIAgAAAA==.',Vy='Vyrridyl:BAAALAADCgYIBQAAAA==.',Wa='Waymond:BAAALAAECgIIAgAAAA==.',We='Weltaczar:BAAALAADCgMIAwAAAA==.Weltaholic:BAAALAADCgUIBQAAAA==.Weltazar:BAAALAAECgMIAwAAAA==.Westside:BAACLAAFFIEFAAIDAAMIaB7HAgApAQADAAMIaB7HAgApAQAsAAQKgRoAAwMACAhUJnQBAGUDAAMACAhUJnQBAGUDAAoAAQiMJQ8JAG4AAAAA.',Wh='Whodatpal:BAAALAADCgEIAQAAAA==.',Wi='Wickët:BAAALAAECgcIDgAAAA==.',Wr='Wrike:BAEALAADCgUICAABLAAECgMIAwABAAAAAA==.',Wu='Wulfengrip:BAAALAAECgIIBAAAAA==.',Xa='Xalreth:BAAALAAECgMIAwAAAA==.Xaviana:BAAALAAECgEIAQAAAQ==.',Xi='Xiangzhu:BAAALAAECgQIBgAAAA==.Xiion:BAAALAAECgYIDwAAAA==.',Ya='Yarrowsin:BAAALAADCgIIAgAAAA==.Yastypoo:BAAALAAECgYIBgAAAA==.Yata:BAAALAADCgEIAQAAAA==.',Ye='Yellinala:BAAALAADCggIGQAAAA==.',Yi='Yiff:BAAALAAECgcICgAAAA==.',Yu='Yurika:BAEALAAECgcIDAAAAA==.Yushi:BAAALAAECgcIDgAAAA==.',Ze='Zenset:BAAALAADCgMIBQAAAA==.Zenshu:BAAALAAECgYICgAAAA==.',Zh='Zhuultar:BAAALAADCgYIBgABLAADCggIFwABAAAAAA==.',Zi='Ziljen:BAAALAADCgUIBwAAAA==.Zizacast:BAAALAADCgMIAwAAAA==.',Zu='Zugzugsmash:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end