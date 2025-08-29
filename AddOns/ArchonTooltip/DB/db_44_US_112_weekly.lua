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
 local lookup = {'Unknown-Unknown','Warrior-Fury',}; local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adilia:BAAALAAECgEIAQAAAA==.',Af='Afox:BAAALAAECgMIAwAAAA==.',Ak='Akaidia:BAAALAAECggICAAAAA==.',Al='Alektophobia:BAAALAAECgIIAgAAAA==.Altysa:BAAALAAECgEIAQAAAA==.',Am='Amorina:BAAALAAECgIIAgAAAA==.Amz:BAAALAAECgcIDwAAAA==.',An='Anamnesis:BAAALAAECgMIBAAAAA==.Anda:BAAALAADCggICAAAAA==.Andracca:BAAALAADCgcIBwAAAA==.Aner:BAAALAADCgMIAwAAAA==.Angered:BAAALAAFFAIIBAAAAA==.Angrygnome:BAAALAAECgMIBQAAAA==.Angélique:BAAALAAECgYICgAAAA==.Antonement:BAAALAAECgYICAAAAA==.',Ao='Aoiakuma:BAAALAADCgMIAwAAAA==.',Ar='Arcadi:BAAALAADCgMIAwABLAADCgQIBAABAAAAAA==.Arcamoon:BAAALAADCgQIBAAAAA==.Arcashi:BAAALAADCgMIAwABLAADCgQIBAABAAAAAA==.Armistice:BAAALAADCgQIBAAAAA==.Arrokoth:BAAALAADCggIDAAAAA==.',Au='Autodrive:BAAALAAECgMIBAAAAA==.',Az='Azenthal:BAAALAAECgcIDQAAAA==.',['Aç']='Açhilles:BAAALAADCgMIAwABLAAECgIIAgABAAAAAA==.',Ba='Baemon:BAAALAADCgYICQAAAA==.Banannana:BAAALAAECgUIBQAAAA==.Banshee:BAAALAAECgMIBQAAAA==.Banzen:BAAALAADCggIDwAAAA==.Battle:BAEALAADCgYIBgAAAA==.',Be='Beldorin:BAAALAADCgYICwAAAA==.Belgran:BAAALAAECgMIBAAAAA==.Berric:BAAALAADCggIDwAAAA==.',Bi='Biackstone:BAAALAAECgIIAgAAAA==.Bigdaddynik:BAAALAADCgYIBgABLAADCggIEQABAAAAAA==.Bileshots:BAAALAAECgIIAgAAAA==.Birdhunter:BAAALAAECgEIAQAAAA==.Birdmån:BAAALAAECgMIAwAAAA==.',Bj='Bjoren:BAAALAAECgMIBAAAAA==.',Bl='Bluraspberry:BAAALAAECgQIBQAAAA==.',Bo='Boombat:BAAALAAECgIIAgAAAA==.Boomdorf:BAAALAADCggICQAAAA==.Bootiebang:BAAALAAECgEIAQAAAA==.Bootycall:BAAALAAECgEIAQAAAA==.',Br='Brandu:BAAALAADCgIIAgAAAA==.',Bu='Buckaroo:BAAALAADCggICAAAAA==.',Ca='Captoom:BAAALAADCgYICQABLAADCggIFgABAAAAAA==.Carbox:BAAALAADCgYICQAAAA==.Caring:BAAALAAECgEIAQAAAA==.',Ce='Cesàrè:BAAALAADCggICAAAAA==.',Ch='Chahra:BAAALAADCgcIBwAAAA==.Cheesecaké:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Chucklesless:BAAALAAECgEIAQAAAA==.',Cl='Clangedin:BAAALAAECgEIAQAAAA==.',Co='Coreytaylors:BAAALAADCgIIAgAAAA==.Cosaga:BAAALAADCgMIAwAAAA==.',Cr='Crownshunter:BAAALAADCgEIAQAAAA==.',Cu='Cucktank:BAAALAADCgYIBgAAAA==.',Da='Dakon:BAAALAAECgYIDQAAAA==.Daneaus:BAAALAAECgQIBQAAAA==.Daredevil:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.Darnuus:BAAALAAECgMIAwAAAA==.',De='Deathbydruid:BAAALAAECgMIBAAAAA==.Deathnelf:BAAALAADCgcIBwAAAA==.Decimator:BAAALAADCgcIBwAAAA==.Devildognutz:BAAALAADCgcICQAAAA==.',Di='Diminuendo:BAAALAADCgUIBwAAAA==.',Do='Dolfuu:BAAALAAECggICAAAAA==.Dorozh:BAAALAAECgIIAgAAAA==.',Dr='Dragonstorm:BAAALAAECgIIAgAAAA==.Drala:BAAALAAECgIIAgAAAA==.Drathheals:BAAALAAECgMIBAAAAA==.Dripjaw:BAAALAADCggIFQAAAA==.Druidía:BAAALAAECgcICAAAAA==.Dryconias:BAAALAADCgcIBwAAAA==.',Du='Dunkelzhan:BAAALAAECgMIAwAAAA==.',Dy='Dyana:BAAALAAECgEIAQAAAA==.',Dz='Dz:BAAALAAECgUIBgAAAA==.',['Dà']='Dàrito:BAAALAADCgYICwAAAA==.',Ec='Ecobessie:BAAALAADCgYICQAAAA==.',Ed='Edlund:BAAALAAECgQIBQAAAA==.',Ei='Eilinaria:BAAALAAECgIIAgAAAA==.Eindri:BAAALAADCgQIBAABLAADCggICAABAAAAAA==.',El='Elbiee:BAAALAAECgYICQAAAA==.Electricfun:BAAALAADCgEIAQAAAA==.Elemenabeech:BAAALAADCgcIEQAAAA==.Elvy:BAAALAAECgQIBAAAAA==.',Em='Emrýs:BAAALAAECgMIBQAAAA==.',Fa='Fabulousness:BAAALAAECgYICAAAAA==.Falak:BAAALAADCgQIBQAAAA==.Falsetto:BAAALAADCggICAAAAA==.',Fi='Fineshyt:BAAALAAECgYIDAAAAA==.',Fl='Flitred:BAAALAADCgYIBgAAAA==.Flurpldenken:BAAALAADCgQIBAAAAA==.',Fu='Furryriver:BAAALAADCggIFQAAAA==.',Ga='Galbi:BAAALAAECgMIAwAAAA==.Galianna:BAAALAAECgIIAgAAAA==.',Ge='Geogre:BAAALAAECgcIDQAAAA==.Gevul:BAAALAAECgMIBQAAAA==.',Gl='Glazul:BAAALAADCgMIAwAAAA==.Glodelyth:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.',Gr='Gremionis:BAAALAAECgMIBgAAAA==.Grozny:BAAALAADCgIIAgAAAA==.',Gu='Guccidruid:BAAALAAECgMIAwAAAA==.',['Gâ']='Gârin:BAAALAADCgcICAAAAA==.',Ha='Happydabs:BAAALAADCgcIBwAAAA==.Hark:BAAALAADCgMIAwAAAA==.Haveabubble:BAAALAAECgQIBQAAAA==.Havvoc:BAAALAAECgIIAgAAAA==.',He='Helena:BAAALAAECgYIDgAAAA==.Heliarc:BAAALAADCgYICQAAAA==.Hermès:BAAALAADCggIDQABLAAECgYICgABAAAAAA==.',Ho='Hoink:BAAALAAECgMIAwAAAA==.Holyale:BAAALAAECgEIAQAAAA==.Hoopla:BAAALAAECgEIAQAAAA==.',Hu='Huutou:BAAALAAECgIIAgAAAA==.',['Hí']='Hísoka:BAAALAAECgQIAQAAAA==.',Il='Illidonis:BAAALAADCgcIBwAAAA==.Illustriâ:BAAALAADCgYICwAAAA==.',Ir='Irs:BAAALAADCgMIAwAAAA==.',Is='Istabthings:BAAALAAECgEIAQAAAA==.',It='Itchydh:BAAALAAECgcIEAAAAA==.',Ja='Jarlude:BAAALAADCggIDwAAAA==.Jaydu:BAAALAAECgIIAgAAAA==.',Je='Jedaz:BAAALAADCgcIDgAAAA==.Jefferie:BAAALAADCgQIBAAAAA==.Jenøvha:BAAALAADCgcIEQAAAA==.',Ji='Jigs:BAAALAAECgEIAQAAAA==.Jiyong:BAAALAAECgMIBQAAAA==.',Jo='Jobei:BAAALAADCggIFQAAAA==.',Ju='Jujutanketh:BAAALAADCgcICgAAAA==.',Ka='Kabøchi:BAAALAAECgMIBQAAAA==.Kaloras:BAAALAADCgIIAgAAAA==.Kanaloa:BAAALAADCgcIBwAAAA==.Kayler:BAAALAADCgUIBQABLAAECggICAABAAAAAA==.',Ke='Keirin:BAAALAAECgIIAgAAAA==.Keldica:BAAALAADCgcIDAAAAA==.Kenshan:BAAALAAECgEIAQAAAA==.Kevinbox:BAAALAAECgUICAAAAA==.',Ki='Kiryie:BAAALAADCgcIBwAAAA==.',Kn='Knifecap:BAAALAADCggIFgAAAA==.',Ko='Koneta:BAAALAADCgcIBwAAAA==.Kotar:BAAALAADCgcIAQAAAA==.',Kr='Kraigen:BAAALAAECgYICAAAAA==.Krawmanon:BAAALAAECgQIBQAAAA==.Krod:BAAALAAFFAEIAQAAAA==.',Kt='Ktulu:BAAALAADCgYIBgAAAA==.',Ku='Kulrhex:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.',La='Lavenderloot:BAAALAAECgMIAwAAAA==.',Le='Legzala:BAAALAADCggIEAAAAA==.',Li='Lightdecay:BAAALAAECgYIDAAAAA==.Lightningfox:BAAALAAECgMIBQAAAA==.Lightsfallen:BAAALAADCggIEQAAAA==.Lilpeople:BAAALAAECgEIAQAAAA==.Lilredindie:BAAALAADCgcIBwAAAA==.Lisperlina:BAAALAADCgUIBwAAAA==.Lithia:BAAALAADCgcIBwAAAA==.Lithiris:BAAALAADCgQIBAAAAA==.Littlemo:BAAALAADCggIFQAAAA==.',Lu='Lucielbaal:BAAALAAECgQIBAAAAA==.Luciene:BAAALAAECgYICAAAAA==.Luciferus:BAAALAAECgMIBgAAAA==.Luckystop:BAAALAADCgcICwAAAA==.',Ly='Lyrska:BAAALAAECgEIAQAAAA==.Lytearrow:BAAALAAECgEIAQAAAA==.',['Lè']='Lèonidas:BAAALAADCgMIAwABLAAECgMIBQABAAAAAA==.',['Lé']='Léaf:BAAALAADCgcIDgAAAA==.',Ma='Maimprowler:BAAALAADCgEIAQAAAA==.Makdorei:BAAALAAECgQIBQAAAA==.Manbearpally:BAAALAADCgMIAwAAAA==.Manikfury:BAAALAAECgYICAAAAA==.Maniksmage:BAAALAADCgMIBQABLAAECgYICAABAAAAAA==.Mannypack:BAAALAAECgEIAQAAAA==.',Mc='Mcdawg:BAAALAADCgYIBgAAAA==.Mcleary:BAAALAAECgMIAwAAAA==.',Me='Melinashala:BAAALAAECgMIBAAAAA==.Mephizto:BAAALAAECgYIDwAAAA==.Methylpheni:BAAALAADCgcIDQABLAAECgEIAQABAAAAAA==.',Mi='Mikø:BAAALAADCgcIBwAAAA==.Miler:BAAALAAECgIIAwAAAA==.Misfire:BAAALAAECgMIAwAAAA==.Missprayer:BAAALAADCggIEgAAAA==.',Mo='Moemo:BAAALAAECgIIAgAAAA==.Mohodh:BAAALAAECgYICAAAAA==.Mongowrath:BAAALAADCgcIBwAAAA==.Monksterz:BAAALAAECgMIBAAAAA==.Monoxidê:BAAALAAECgIIAgAAAA==.Moonwarriorx:BAAALAAECgMIBAAAAA==.Morrigyn:BAAALAADCggICQAAAA==.Morsecode:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.',Mu='Muchuchu:BAAALAAECgQIBAAAAA==.Mulitia:BAAALAADCgUIBQAAAA==.Mustachekick:BAAALAADCgMIAwAAAA==.',My='Mystez:BAAALAAECgEIAQAAAA==.',['Mí']='Místwalker:BAAALAAECgEIAQAAAA==.',Na='Nackthyr:BAAALAAECgcIDQAAAA==.Naelyn:BAAALAAECgQIAwAAAA==.Narlin:BAAALAADCgcIBwAAAA==.',Ne='Nedairon:BAAALAAECgIIAgAAAA==.Neonlight:BAEALAADCgYICQAAAA==.',Ni='Nikkota:BAAALAADCggIDwAAAA==.Ninjypunch:BAAALAADCgUIBQAAAA==.',No='Norla:BAAALAAECgEIAQAAAA==.Norst:BAAALAAECgIIAgAAAA==.',Oa='Oath:BAAALAAECgYICAAAAA==.Oatmeals:BAAALAADCgcICQAAAA==.',Od='Oddsham:BAAALAADCgMIAwAAAA==.',Og='Oghamm:BAAALAAECgMIBQAAAA==.',Ol='Olmek:BAABLAAECoEXAAICAAgI0R/1BwDqAgACAAgI0R/1BwDqAgAAAA==.',Op='Oprahwndfury:BAAALAAECgIIAgAAAA==.',Or='Orzanis:BAAALAADCggICAAAAA==.',Pa='Palasades:BAAALAADCgcIDAAAAA==.Pasorin:BAAALAAECgIIAgAAAA==.',Pe='Peacemakër:BAAALAAECgMIBAAAAA==.Pelly:BAAALAAECgYICAAAAA==.',Ph='Pharaa:BAAALAAECgMIBQAAAA==.Phasze:BAAALAADCgQIBAAAAA==.',Pi='Picoso:BAAALAAECgYICAAAAA==.Piianna:BAAALAADCggIGAAAAA==.Pinzel:BAAALAAECgIIAgAAAA==.',Pj='Pjrogue:BAAALAAECgcIDQAAAA==.',Po='Poltrgeist:BAAALAAECgIIAgAAAA==.Popeweaseliv:BAAALAADCggIEwABLAAECgIIAgABAAAAAA==.',Qi='Qikkaw:BAAALAAECgMIBQAAAA==.',Qu='Quantos:BAAALAAECgMIBAAAAA==.',Ra='Raganar:BAAALAAECgMIBQAAAA==.Raikuowo:BAAALAAECgcIDwAAAA==.Rakeret:BAAALAADCgYICAAAAA==.Rasz:BAAALAAECgMIBQAAAA==.Rayjean:BAAALAADCgYICQAAAA==.',Re='Relmax:BAAALAAECgIIAgAAAA==.',Rh='Rhaenýs:BAAALAAECgMIBAAAAA==.Rhonwynn:BAAALAAECgMIBQAAAA==.',Ri='Rikershipdwn:BAAALAAECgIIAgAAAA==.Riptorn:BAAALAADCgcIDAAAAA==.Rivik:BAAALAAECgIIAgAAAA==.',Ro='Robertkenway:BAAALAAECgMIBAABLAAECgMIBgABAAAAAA==.Rod:BAAALAAECgMIBAAAAA==.Rokte:BAAALAADCgcIBwAAAA==.',Ru='Rudepoodle:BAAALAAECgUICQAAAA==.',['Rä']='Räum:BAAALAAECgMIBAAAAA==.',Sa='Saammiee:BAAALAAECgEIAQAAAA==.Saetrin:BAAALAADCgQIBAAAAA==.Samartyr:BAAALAADCggIFQAAAA==.Samison:BAAALAADCgcIDgAAAA==.Sangwynaris:BAAALAADCgYICwAAAA==.Sangwynova:BAAALAADCgMIAwAAAA==.Sarrael:BAAALAAECgMIBQAAAA==.',Sc='Scorpmage:BAAALAAECgMIBQAAAA==.',Se='Sedrick:BAAALAAECgMIBAAAAA==.Sekhmett:BAAALAADCgcIBwAAAA==.Sepulveda:BAAALAADCggIFAABLAAECgIIAgABAAAAAA==.',Sh='Shamallama:BAAALAAECgEIAQAAAA==.Shazool:BAAALAAECgcIDgAAAA==.Sheep:BAAALAAECgIIAgAAAA==.Shenanigan:BAAALAAECgMIBQAAAA==.Shifterz:BAAALAADCggIFQAAAA==.',Si='Sierramist:BAAALAAECgUICAAAAA==.Sindella:BAAALAAECgMIBQAAAA==.',Sm='Smitemight:BAAALAAECgEIAQAAAA==.',Sn='Sneakydvldog:BAAALAADCggIFAAAAA==.',St='Starboi:BAAALAADCgcICAAAAA==.Starfìre:BAAALAADCggIDgAAAA==.Starrbuk:BAAALAADCggIDgAAAA==.',Su='Sunareas:BAAALAADCggIDQAAAA==.Sunlightbro:BAAALAADCggIFgAAAA==.',Sy='Synthetic:BAAALAAECgMIAwAAAA==.Syv:BAAALAADCggIEwAAAA==.',['Sä']='Säbertooth:BAAALAADCgcIBwAAAA==.',['Sö']='Sööshi:BAAALAAECgIIAgAAAA==.',Te='Tecs:BAAALAAECgYICAAAAA==.Tekis:BAAALAADCgIIAgAAAA==.',Th='Thalira:BAAALAAECgIIAgAAAA==.',Ti='Tizlle:BAAALAAECgMIAwAAAA==.',To='Toaster:BAAALAADCgUIBQAAAA==.Toiletpooper:BAAALAAECgYICQAAAA==.Torridwells:BAAALAADCgcIBwAAAA==.Totemcap:BAAALAADCggICgABLAADCggIFgABAAAAAA==.',Tr='Trell:BAAALAAECgEIAgAAAA==.Trixiebear:BAAALAADCgUIBAABLAAECgYIDAABAAAAAA==.Troag:BAAALAAECgMIAwAAAA==.Troagstar:BAAALAAECgMIAwAAAA==.',Tw='Twoten:BAAALAAECgMIBQAAAQ==.',Ty='Tylerz:BAAALAADCgcIBwAAAA==.',Us='Ushas:BAAALAAECgUIBwAAAA==.',Va='Valindrea:BAAALAADCggIFQAAAA==.Vandalism:BAAALAAECgcIEAAAAA==.Vasrannah:BAAALAAECgYIBgAAAA==.Vavriel:BAAALAAECgYICAAAAA==.',Ve='Venomstick:BAAALAAECgQIBAAAAA==.',Vi='Violetheals:BAAALAAECgYICAAAAA==.Vithper:BAAALAADCggIEAAAAA==.',Vn='Vnia:BAAALAAECgIIAwAAAA==.',Vo='Volttron:BAAALAADCgQIBAAAAA==.',Vy='Vyrahildard:BAAALAAECgQIBQAAAA==.',Wa='Wasteland:BAAALAAECgUICAAAAA==.',We='Weaselhunter:BAAALAAECgIIAgAAAA==.Weasellock:BAAALAADCggIDAABLAAECgIIAgABAAAAAA==.Weaselmage:BAAALAADCggICQABLAAECgIIAgABAAAAAA==.Welor:BAAALAADCgYICAAAAA==.',Wi='Willbarr:BAAALAAECgMIBAAAAA==.',Wo='Wooffee:BAAALAADCgMIAwAAAA==.',Xa='Xalatathussy:BAAALAADCgUIBQAAAA==.Xaquillis:BAAALAAECgYIDQAAAA==.',Xe='Xeck:BAAALAADCgUIBQAAAA==.Xentrie:BAAALAADCgcIFQAAAA==.Xeyvara:BAAALAAECgQIBQAAAA==.',Xi='Xicute:BAAALAAECgIIAgAAAA==.',Za='Zarzt:BAAALAAECgMIBQAAAA==.Zatannah:BAAALAADCgQIBAAAAA==.',Ze='Zerkerpally:BAAALAADCgYICAAAAA==.Zestdruid:BAAALAAECgYICAAAAA==.',Zi='Zinojae:BAAALAADCggIDwAAAA==.',Zo='Zooaphile:BAAALAAECgEIAQAAAA==.Zorc:BAAALAAECgcIDQAAAA==.Zordòn:BAAALAADCggICAAAAA==.',Zy='Zyate:BAAALAAECgcICwAAAA==.Zyyra:BAAALAAECgQIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end