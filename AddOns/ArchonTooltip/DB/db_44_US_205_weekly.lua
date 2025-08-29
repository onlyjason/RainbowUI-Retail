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
 local lookup = {'Warrior-Fury','Unknown-Unknown','Priest-Shadow','DeathKnight-Frost','Druid-Restoration','Monk-Brewmaster','Paladin-Holy','Rogue-Subtlety','DemonHunter-Vengeance','Evoker-Preservation','Priest-Holy','Paladin-Retribution','Shaman-Elemental','Mage-Frost','Mage-Arcane','Mage-Fire','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Rogue-Assassination','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction',}; local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abaddon:BAAALAADCgIIAgAAAA==.',Ah='Ahrianna:BAABLAAFFIEFAAIBAAMITQ9dAwADAQABAAMITQ9dAwADAQAAAA==.',Al='Alacia:BAAALAAECgIIAgABLAAECgMIBwACAAAAAA==.Alirah:BAAALAAECgIIAgAAAA==.Altairre:BAAALAADCgYIBwAAAA==.Alundre:BAAALAAECgcIEAAAAA==.Alyaa:BAAALAADCgYIBgAAAA==.',An='Ante:BAABLAAFFIEHAAIDAAMIBBa2AgAHAQADAAMIBBa2AgAHAQAAAA==.Antpony:BAAALAADCgYIBgABLAAECgYICQACAAAAAA==.',Ar='Arania:BAAALAADCgMIAwAAAA==.',Aw='Awoozehl:BAACLAAFFIEHAAIEAAMIByJ2AQA4AQAEAAMIByJ2AQA4AQAsAAQKgRgAAgQACAiGJscAAHsDAAQACAiGJscAAHsDAAAA.',Az='Azgrodon:BAAALAAECgQICAAAAA==.',Ba='Baconette:BAEALAADCgIIAgABLAAFFAMIBwAFAGcKAA==.Banatok:BAAALAADCggICAAAAA==.Bathrezz:BAAALAAECgIIAgAAAA==.',Be='Beleaves:BAABLAAFFIEGAAIGAAMImworAgDMAAAGAAMImworAgDMAAAAAA==.Beverlylynn:BAAALAADCgIIAgAAAA==.',Bi='Bifurious:BAAALAADCgcIBwABLAAECgYICQACAAAAAA==.Bigbepsi:BAAALAAECgYIBgAAAA==.Bigstick:BAAALAADCgEIAgABLAAECgQICAACAAAAAA==.',Bl='Bladebearer:BAAALAAECgYICgAAAA==.',Bo='Boofassist:BAACLAAFFIEGAAIHAAIIWSPsAgDUAAAHAAIIWSPsAgDUAAAsAAQKgRwAAgcACAg5Il4BAAoDAAcACAg5Il4BAAoDAAAA.Boomsonic:BAAALAAECgYICQAAAA==.Boptur:BAAALAADCgIIAgAAAA==.Boraga:BAAALAADCgcIBwAAAA==.',Br='Brawlers:BAAALAADCgQIBAAAAA==.Brewtalizer:BAAALAADCgYIBgAAAA==.Broccoliz:BAECLAAFFIEHAAIFAAMIZwqiAgDgAAAFAAMIZwqiAgDgAAAsAAQKgRgAAgUACAicFvgUAM8BAAUACAicFvgUAM8BAAAA.',Bu='Bukhaki:BAAALAAECgMIBgABLAAECgYIDQACAAAAAA==.',Bw='Bwonshamdi:BAAALAAECgIIAgAAAA==.',Ca='Cafca:BAAALAAECgYICQAAAA==.Camv:BAAALAADCgcICQAAAA==.Catastrophe:BAAALAADCgEIAQAAAA==.',Ce='Cekestina:BAAALAADCgcIDAAAAA==.',Ch='Changying:BAAALAAECgEIAQAAAA==.Choedankal:BAAALAADCgcIBwAAAA==.Chukie:BAAALAAECgMIAwAAAA==.',Ci='Cialis:BAAALAAECgMIBQAAAA==.Cinnamoroll:BAAALAAECgMIBQAAAA==.',Cl='Clèrick:BAAALAAECgIIAgAAAA==.',Co='Combination:BAAALAAECgcIEAAAAA==.Conscienze:BAAALAADCgYICgAAAA==.',Cr='Crista:BAAALAADCgIIAwAAAA==.',Da='Dabbyshatner:BAAALAAECggIDgAAAA==.Dallzbeep:BAAALAAECgYICgAAAA==.Dancehall:BAAALAAECgEIAQAAAA==.Darthdiddyus:BAABLAAECoEWAAIIAAgIUiLrAAASAwAIAAgIUiLrAAASAwAAAA==.Datshammy:BAAALAAECgcIDAAAAA==.',De='Deaththreat:BAAALAAECgIIAgAAAA==.Destructer:BAAALAADCggIEgAAAA==.',Di='Dirtydinker:BAAALAAECgIIAgAAAA==.Dixsard:BAAALAAECgYIDQAAAA==.',Do='Doomsday:BAAALAADCgEIAQAAAA==.Dottprepared:BAABLAAFFIEHAAIJAAMISQ6jAADdAAAJAAMISQ6jAADdAAAAAA==.',Dr='Dradow:BAAALAADCgYIBgAAAA==.Drokar:BAAALAAECgMIBAAAAA==.',Du='Dudette:BAAALAAECgMIAwAAAA==.',Eg='Eggfooyung:BAAALAAECgYIDgABLAAFFAIIBgAHAFkjAA==.',El='Elendsear:BAAALAADCggICAAAAA==.',En='Endcredits:BAAALAAECgIIAgAAAA==.',Ev='Evoulker:BAACLAAFFIEHAAIKAAMIABahAQAKAQAKAAMIABahAQAKAQAsAAQKgRgAAgoACAiNGo8EAE8CAAoACAiNGo8EAE8CAAAA.',Ey='Eyyosmite:BAAALAADCggICAAAAA==.',Fa='Fairytale:BAABLAAECoEYAAILAAgIlRPfFAAJAgALAAgIlRPfFAAJAgAAAA==.',Fe='Fellitha:BAAALAAECgIIAwAAAA==.Fengxu:BAAALAADCggICAAAAA==.',Fi='Fists:BAAALAADCgcIBwAAAA==.',Fr='Frierenotter:BAAALAADCggIDQAAAA==.',Ga='Gabagoon:BAAALAAECgMIBgAAAA==.Gargarbinks:BAAALAADCgUIBQAAAA==.Gawain:BAAALAADCggICAAAAA==.',Ge='Georg:BAABLAAECoEYAAIMAAgI2CNsBgAYAwAMAAgI2CNsBgAYAwAAAA==.',Gh='Ghazzie:BAAALAADCgYIBgAAAA==.',Gl='Glaiver:BAAALAAECgIIAgAAAA==.Glassjaw:BAAALAADCggICAAAAA==.',Gu='Gulgrimmar:BAACLAAFFIEHAAINAAMISBwsAgAdAQANAAMISBwsAgAdAQAsAAQKgRgAAg0ACAhwJcEBAF8DAA0ACAhwJcEBAF8DAAAA.Guwudanielle:BAAALAAECgYIBgABLAAECgYIBgACAAAAAA==.',['Gò']='Gòdcômplex:BAAALAADCgQIBAAAAA==.',Ha='Harkness:BAAALAAECgMIAwAAAA==.',He='Hextech:BAAALAAECgIIAgAAAA==.Heyfren:BAAALAADCggICAAAAA==.',Ho='Hobosapian:BAAALAAECgMIBgABLAAECgYICQACAAAAAA==.Hodann:BAAALAADCgcIDgAAAA==.Holybread:BAABLAAECoEXAAIMAAgI0SI4BgAcAwAMAAgI0SI4BgAcAwAAAA==.Holydawn:BAAALAADCgYIBgAAAA==.',Hu='Hughue:BAAALAAECgQIBAAAAA==.',Ij='Ijustankedu:BAAALAADCgcIDQAAAA==.',Il='Ilgrim:BAAALAAECgcICQAAAA==.Illadaron:BAAALAAECgUICAAAAA==.Ilravenll:BAAALAAECgcIBwABLAAECgcICQACAAAAAA==.Ilweaver:BAAALAAECgEIAQABLAAECgcICQACAAAAAA==.Ilyana:BAACLAAFFIEGAAIOAAMI4RZvAAANAQAOAAMI4RZvAAANAQAsAAQKgRgABA4ACAh1IoMFAJECAA4ABwhNIIMFAJECAA8ABQg6H4kxAKIBABAAAQiTDoENADsAAAAA.',Is='Isabella:BAAALAAECgYIBgAAAA==.Ishtann:BAAALAADCggICAAAAA==.',Ja='Jayc:BAAALAAECgQIBgAAAA==.',Je='Jereico:BAACLAAFFIEGAAIRAAMIIB01AgARAQARAAMIIB01AgARAQAsAAQKgRgAAxIACAj6I70AAN4CABIABwipJL0AAN4CABEACAhuH9oJAHwCAAAA.Jeryhn:BAACLAAFFIEHAAIHAAMIuBIHAgAJAQAHAAMIuBIHAgAJAQAsAAQKgRgAAgcACAgKG7IGAGICAAcACAgKG7IGAGICAAAA.',Jo='Joeynodz:BAAALAADCggIDwAAAA==.',Ju='Juand:BAAALAAECgIIAwAAAA==.Juggalo:BAAALAAECggIEQAAAA==.June:BAACLAAFFIEFAAITAAMIkQlgAgDpAAATAAMIkQlgAgDpAAAsAAQKgRgAAhMACAgvHiIEALACABMACAgvHiIEALACAAAA.',Ka='Kaelyn:BAAALAAECgEIAQABLAAECgMIBgACAAAAAA==.Kaldriss:BAAALAADCggIDwAAAA==.Kallidos:BAAALAADCgUIBQAAAA==.Kanoe:BAAALAADCggICAAAAA==.',Ke='Kervina:BAAALAAECgMIBAAAAA==.',Kh='Khraboom:BAAALAAECgYICwAAAA==.',Ko='Koddin:BAAALAAECgUICQAAAA==.Koreth:BAACLAAFFIEGAAIUAAMInBbiAQAeAQAUAAMInBbiAQAeAQAsAAQKgRgAAxQACAiDIi0EAAADABQACAhhIi0EAAADAAgABAiaHWAJAFYBAAAA.Kornholyo:BAAALAAECgQIBQAAAA==.',Kr='Krymz:BAAALAADCgcIBwAAAA==.',Ku='Kutuzov:BAAALAAECgEIAQAAAA==.',La='Lamemoosaur:BAAALAAECgYICQAAAA==.Laríca:BAAALAAECgcIEAAAAA==.Lateralus:BAAALAAECgMIBAAAAA==.Lavabursting:BAAALAADCggICAAAAA==.Laydoutyota:BAAALAAECgYICwAAAA==.',Li='Lickmytoes:BAAALAAECgMIAwAAAA==.Lilea:BAAALAAECgMIBwAAAA==.Lionsmane:BAAALAAECgMIBQAAAA==.',Lo='Looshi:BAAALAADCgQIBAAAAA==.Lortherian:BAAALAADCggICwAAAA==.',['Lä']='Läwlbringer:BAAALAADCggICgAAAA==.',Ma='Madamofdeath:BAAALAADCgcIBwAAAA==.Malachite:BAAALAAECgIIAgAAAA==.Mania:BAAALAADCggIDQABLAAECgYICQACAAAAAA==.Mayalee:BAAALAADCgEIAQAAAA==.',Mc='Mcpwn:BAAALAADCgcIBwAAAA==.',Me='Meatier:BAAALAAECgYIBgABLAAECgYICQACAAAAAA==.Melanie:BAAALAADCgYIBgABLAAECgYIBgACAAAAAA==.',Mo='Monkch:BAAALAADCgcIBwAAAA==.Monsterskill:BAAALAAECgYICgAAAA==.Moonerva:BAAALAAECgIIAgAAAA==.',Mv='Mvqchx:BAAALAAECgcIDAAAAA==.',Na='Narib:BAAALAAECgMIBAAAAA==.',Ni='Nightfangs:BAAALAADCgcIBwAAAA==.Nisel:BAAALAADCgEIAQAAAA==.',No='Nobacon:BAAALAAECgEIAQAAAA==.Notmychair:BAAALAAECgMIAwAAAA==.',['Në']='Nëmu:BAAALAAECgUICQAAAA==.',['Ní']='Nír:BAAALAAECgIIAgAAAA==.',Ob='Oben:BAAALAAECgMIBQAAAA==.',Om='Omnious:BAAALAADCgQIBAAAAA==.',Or='Orelin:BAAALAADCgEIAQAAAA==.',Pa='Palaoben:BAAALAADCgUIBQAAAA==.Passionate:BAAALAAECgcIDQAAAA==.',Ph='Phatmidas:BAAALAAECgIIAgAAAA==.',Pi='Pion:BAAALAADCggICAABLAAECgcIEAACAAAAAA==.',Pl='Plutonyus:BAAALAAECgYICwAAAA==.',Po='Potatopotato:BAAALAAECgYIDgAAAA==.Pounces:BAAALAAECgcICgAAAA==.',Ps='Psychomidget:BAAALAAECgEIAQAAAA==.',Pu='Puetrid:BAAALAAECgUICgAAAA==.',Ra='Ragnarök:BAAALAAECgEIAQAAAA==.Randomly:BAAALAADCgcIEQAAAA==.Rautha:BAAALAADCgEIAQAAAA==.',Ro='Robopacman:BAAALAAECggIEgAAAA==.Rodstewart:BAAALAAECggIEAAAAA==.',Ry='Ryuiya:BAAALAAECgMIAwAAAA==.',Sa='Saintjiub:BAAALAADCggICQAAAA==.Savv:BAACLAAFFIEHAAIVAAMIAR70AQAvAQAVAAMIAR70AQAvAQAsAAQKgRgAAhUACAjYJOsDAEUDABUACAjYJOsDAEUDAAAA.Savvtwo:BAAALAADCgEIAQABLAAFFAMIBwAVAAEeAA==.',Sc='Scarlex:BAAALAAECgMIBQAAAA==.Schloopee:BAAALAAECgUIBQAAAA==.Scriptkiddie:BAAALAADCgYIDAAAAA==.',Sh='Shifuu:BAAALAAECgYICgAAAA==.Shinanigans:BAAALAADCggIDgAAAA==.Shinygut:BAAALAADCgcIDAAAAA==.Shinyknight:BAAALAADCgMIAwAAAA==.Shinynight:BAAALAAECgMIBAAAAA==.Shplooze:BAAALAAECgEIAQAAAA==.Shweet:BAAALAAECgcIBwAAAA==.',Si='Siarderis:BAAALAADCgMIAwAAAA==.Silverblades:BAAALAAECgIIAwAAAA==.Silverossos:BAAALAADCgUIBQAAAA==.',Sk='Skitty:BAAALAAECgEIAQAAAA==.',Sl='Slashhide:BAAALAADCggICAAAAA==.',Sm='Smokehause:BAAALAADCgUIBQAAAA==.',Sn='Snots:BAAALAAECggIDgAAAA==.Snozzberries:BAAALAADCggIDgABLAAECgIIAgACAAAAAA==.',So='Soaker:BAAALAAECgQIBwAAAA==.Solidsilver:BAAALAAECgMIAwAAAA==.',Sp='Spfzero:BAAALAAECgMIBQAAAA==.Spitter:BAAALAADCggIDwABLAAECgYIDQACAAAAAA==.',Sq='Squibble:BAAALAADCggIEwAAAA==.',St='Staggered:BAAALAAECgMIAwAAAA==.Starzburstz:BAAALAADCgcIBwAAAA==.Stratusphere:BAAALAADCgUIBQAAAA==.Stârlèss:BAAALAADCgcIBwAAAA==.',Su='Subtox:BAAALAAECgYIDAAAAA==.',['Sê']='Sêp:BAAALAAECgEIAQAAAA==.',Te='Tenzu:BAAALAAECgYICgAAAA==.',Th='Thiaf:BAAALAADCgMIAwAAAA==.',Ti='Tiewaz:BAAALAAECgMIBgAAAA==.',To='Tolun:BAABLAAECoEWAAIOAAgI5xq9BQCLAgAOAAgI5xq9BQCLAgAAAA==.Tosan:BAAALAAECgQIBgAAAA==.',Tr='Troubily:BAAALAAECgEIAQABLAAECggIFQAHAOUFAA==.Troubly:BAABLAAECoEVAAIHAAgI5QW4FQCHAQAHAAgI5QW4FQCHAQAAAA==.',Tu='Turn:BAACLAAFFIEGAAMWAAMIpBgNBAABAQAWAAMIqRMNBAABAQAXAAIIXg5UBQClAAAsAAQKgRgABBYACAjzH/sJAKoCABYACAjeH/sJAKoCABgABgiHFaMIAMYBABcAAwgCHLcjAAABAAAA.Turtleduck:BAAALAADCgYIBgAAAA==.',Va='Valhkyr:BAAALAADCggIBwAAAA==.',Ve='Venratzi:BAAALAADCgQIBAAAAA==.',Wa='Warraaxx:BAAALAADCgYIBgAAAA==.',Wi='Wintersnite:BAAALAADCggIFQAAAA==.Wizzyy:BAAALAADCgcIBwAAAA==.',Wy='Wyleic:BAAALAADCggIDgAAAA==.',Ye='Yenaldlooshi:BAAALAADCgEIAQABLAADCgQIBAACAAAAAA==.Yenchmeister:BAABLAAECoEYAAIBAAgImSQOBgALAwABAAgImSQOBgALAwAAAA==.',Yo='Yoduh:BAAALAAECgYICwAAAA==.Youngbusta:BAAALAADCggICAABLAAECgcIDAACAAAAAA==.',Yu='Yuri:BAAALAADCggICAAAAA==.Yuta:BAAALAAECgEIAQABLAAECgMIBAACAAAAAA==.',Za='Zarian:BAAALAAECgcIDwAAAA==.',Zo='Zourlight:BAAALAADCgEIAQAAAA==.Zourlock:BAAALAADCgYIBgAAAA==.Zourstorm:BAAALAAECgYIBgAAAA==.',Zy='Zynjamin:BAABLAAECoEVAAIRAAcIySN6BgDMAgARAAcIySN6BgDMAgAAAA==.',['Ðr']='Ðrèamless:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end