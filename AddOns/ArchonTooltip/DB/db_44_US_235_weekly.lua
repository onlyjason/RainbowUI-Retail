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
 local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Hunter-Survival','Priest-Shadow','DemonHunter-Havoc','Druid-Restoration','Rogue-Assassination','Druid-Feral','Druid-Balance',}; local provider = {region='US',realm='Velen',name='US',type='weekly',zone=44,date='2025-08-29',data={Ai='Aidendawn:BAAALAADCgYIBgAAAA==.',Ak='Akilan:BAAALAADCgQIBwAAAA==.',Al='Alamar:BAAALAADCggIEQAAAA==.',Am='Amastus:BAAALAADCgcICwAAAA==.',An='Anaru:BAAALAAECgMIAwAAAA==.Anoobornot:BAAALAAECgMIAwAAAA==.',Ar='Arcfury:BAAALAADCgcICgAAAA==.Arwyne:BAAALAADCgYIBgAAAA==.',As='Asturoth:BAAALAAECgYICAAAAA==.',At='Atar:BAAALAADCgcIBwAAAA==.Atlassdver:BAAALAAECgUIBQAAAA==.Atzi:BAAALAAECgMIBAABLAAECgYICgABAAAAAA==.Atzie:BAAALAAECgYICgAAAA==.',Au='Aust:BAAALAAECgYICgAAAA==.',Av='Averlis:BAAALAADCgUIBQAAAA==.',Az='Azmithrilim:BAAALAADCggICQAAAA==.',Ba='Bahnwa:BAAALAAECgYIBQAAAA==.Bandadi:BAEBLAAECoEUAAMCAAgIsiHCAADJAgACAAgIsiHCAADJAgADAAEIrwc2KgBGAAAAAA==.Barathne:BAAALAADCggIDAAAAA==.',Be='Beargruk:BAAALAADCggIDwAAAA==.Belii:BAAALAADCggIEgAAAA==.Bended:BAAALAAECgMIBQAAAA==.',Bi='Bicketybam:BAAALAADCgYIBgAAAA==.',Bl='Blaknight:BAAALAADCgMIAwAAAA==.Blitzed:BAAALAAECgYIBgAAAA==.Bluedrake:BAAALAADCgIIAwAAAA==.Blueparrot:BAAALAADCgcIFgAAAA==.',Bo='Bombfaucet:BAAALAADCgUIBQAAAA==.Boogley:BAAALAAECgYICQAAAA==.',Br='Brimmstone:BAAALAADCgcIBwAAAA==.Bringinlight:BAAALAADCgcIDQAAAA==.',Bu='Bubbleicious:BAAALAADCgYIBgAAAA==.Bulletz:BAAALAAECgMIBQAAAA==.Bunnyhop:BAAALAADCgYICgAAAA==.',['Bì']='Bìgbang:BAAALAADCgYIBgAAAA==.',Ca='Cassandria:BAAALAAECgMIBQAAAA==.',Ce='Cerex:BAAALAADCgcIBwAAAA==.',Ch='Charmeleon:BAAALAADCgcIEwAAAA==.Chathlia:BAAALAAECgEIAQAAAA==.Chixie:BAAALAADCgIIAgAAAA==.Chogric:BAAALAAECgcIEAAAAA==.',Cl='Clark:BAAALAADCgIIAgAAAA==.Clunkin:BAAALAADCggIDwAAAA==.',Co='Cochar:BAAALAAECgcICwAAAA==.Cogsprocket:BAAALAADCgYICgAAAA==.Corebox:BAAALAADCgYIBgAAAA==.',Cr='Crawl:BAAALAADCgQIBAAAAA==.Crona:BAAALAAECgYIBgAAAA==.Crzy:BAAALAAECgcIDQAAAA==.Crzylock:BAAALAADCgcIBwAAAA==.Crzzy:BAAALAADCgMIAQABLAAECgcIDQABAAAAAA==.',Cu='Culúrien:BAAALAADCgQIBAAAAA==.Cumintogitya:BAAALAADCgYIBgABLAADCgcIDQABAAAAAA==.',Cy='Cyhyraethia:BAAALAAECgQIBwAAAA==.',Da='Daish:BAAALAAECgEIAQAAAA==.Danda:BAAALAADCggICAAAAA==.Danica:BAAALAADCgcIBwAAAA==.Dantès:BAAALAAECgYICwAAAA==.Daphne:BAAALAADCgEIAQAAAA==.Daricepicker:BAAALAAECgcIEAAAAA==.Darkbeef:BAAALAADCggIEAAAAA==.Darkyn:BAAALAAECgMIBQAAAA==.Daywoo:BAAALAADCgQIBAAAAA==.',De='Deadpool:BAAALAAECgYICQAAAA==.Deadscar:BAAALAADCggIDgAAAA==.Deathmasterj:BAAALAADCggIEAAAAA==.Decessus:BAAALAADCgQIBQAAAA==.Decímus:BAAALAADCggIAQAAAA==.Deealin:BAAALAADCgEIAQABLAAECgcIEAABAAAAAA==.',Dh='Dhoong:BAAALAADCgYIBgAAAA==.',Di='Disloyal:BAAALAADCgYIBwAAAA==.Dithariaa:BAAALAADCgYIBgAAAA==.',Do='Docryktor:BAAALAAECgUICQAAAA==.Doomgears:BAAALAADCgYIBgAAAA==.',Dr='Dragonair:BAAALAADCgcIEgAAAA==.Dragonoide:BAAALAADCgQIBAAAAA==.Draxe:BAAALAADCgQIBAAAAA==.Drhoe:BAAALAADCgQIBAAAAA==.Drhurtouch:BAAALAAECgYIBgAAAA==.Drryktor:BAAALAADCgUIBgAAAA==.Druithh:BAAALAAECgMIBAAAAA==.Drussila:BAAALAAECgMIAwAAAA==.Druu:BAAALAAECgIIAgAAAA==.',['Dè']='Dèathknight:BAAALAAECgYIBgAAAA==.',Eb='Ebonwings:BAAALAADCggIEAAAAA==.',Ed='Ediana:BAAALAAECgUICQAAAA==.',El='Eleiel:BAAALAADCgQIBAAAAA==.',En='Enkiel:BAAALAADCggIEwAAAA==.',Ep='Epipally:BAAALAADCgUIBQAAAA==.',Es='Estameling:BAAALAAECgMIBQAAAA==.',Ev='Evokthis:BAAALAAECgEIAQAAAA==.',Ex='Exash:BAAALAAECgMIAwAAAA==.',['Eç']='Eçhø:BAAALAAECgEIAQAAAA==.',Fa='Fathertim:BAAALAADCgYIBgAAAA==.',Fe='Felanas:BAAALAADCggIDwAAAA==.',Fi='Fidelcashflõ:BAAALAADCgQIBAABLAAECgYICwABAAAAAA==.Finella:BAAALAADCgYIAQAAAA==.Finnick:BAAALAADCgMIAwAAAA==.Fitchner:BAAALAADCgQIBAAAAA==.',Fr='Froobsglaive:BAAALAADCgcIFQAAAA==.Frostii:BAAALAAECgYIBwAAAA==.',Fu='Fudestamp:BAAALAADCgEIAgAAAA==.Fufight:BAAALAAECgMIAwAAAA==.',Fy='Fyrebug:BAAALAADCggIEwAAAA==.',Ga='Galandor:BAAALAADCgYIDQAAAA==.Garviel:BAAALAAECgQIBAAAAA==.Gaya:BAAALAAECgUIBQAAAA==.Gaïa:BAAALAADCgEIAQAAAA==.',Ge='Getouttafire:BAAALAADCgYIBgABLAADCgcIDQABAAAAAA==.',Gi='Gityadruid:BAAALAADCgQIBAABLAADCgcIDQABAAAAAA==.Gityahunter:BAAALAADCgcIDQABLAADCgcIDQABAAAAAA==.',Go='Gobanks:BAAALAADCggICAAAAA==.',Gr='Grayson:BAAALAADCgMIAwAAAA==.Graysurv:BAABLAAECoEUAAIEAAgI6yUqAAB3AwAEAAgI6yUqAAB3AwAAAA==.Graysurvjr:BAAALAAECgIIBAAAAA==.Greenarrow:BAAALAADCggIFAAAAA==.Griimp:BAAALAAECgQIBgAAAA==.Grimaterial:BAAALAADCgEIAQAAAA==.Grimwali:BAAALAADCgEIAQAAAA==.Grimzido:BAAALAADCggICAAAAA==.Gromlin:BAAALAADCgcIDAAAAA==.',Ha='Halcrenian:BAAALAADCgcIBwAAAA==.Hamremmi:BAAALAAECgYIBgABLAAECggIFwAFAG8gAA==.Hamsteak:BAAALAADCgMIBgAAAA==.Happymad:BAAALAADCgMIAwAAAA==.Hasalia:BAAALAADCgcIDAAAAA==.',He='Healsforu:BAAALAAECgMIBQAAAA==.Hellservent:BAAALAADCgQIBAABLAADCgcIDwABAAAAAA==.Heretanky:BAAALAAECggIBgAAAA==.',Hi='Hif:BAAALAAECgMIAwAAAA==.',Il='Illyy:BAAALAAECgMIBQAAAA==.',In='Indawhole:BAABLAAECoEXAAIGAAgIpyXMAgBYAwAGAAgIpyXMAgBYAwAAAA==.',Iz='Izumiwitabow:BAAALAADCgYIDQAAAA==.',Ja='Jasmean:BAAALAADCggIEAAAAA==.Javaluminous:BAAALAADCggIEAAAAA==.Jaytsukitori:BAAALAAECgYIDQAAAA==.',Je='Jenn:BAAALAADCgYICQAAAA==.',Jh='Jhaeriao:BAAALAADCgYIBgAAAA==.Jhantherox:BAAALAADCgEIAQAAAA==.',Ji='Jiani:BAAALAADCgMIAwABLAADCgcICwABAAAAAA==.',Jo='Joesepi:BAAALAAECggIDwAAAA==.',Ju='Judgeswag:BAAALAAECgYICgAAAA==.',Jy='Jyve:BAAALAAECgEIAQAAAA==.',Ka='Kaleris:BAAALAAECgMIAwABLAAECgQIBwABAAAAAA==.Kallian:BAAALAADCgEIAQAAAA==.Kathana:BAAALAADCgEIAQAAAA==.',Kh='Khonshu:BAAALAAECgIIAgAAAA==.',Ki='Kij:BAEALAAECgIIAgABLAAECggIFAACALIhAA==.Kilrah:BAAALAAECgYICQAAAA==.Kissmycrits:BAAALAADCgUIBwAAAA==.Kissmywrath:BAAALAADCgIIAgAAAA==.Kiyoine:BAAALAAECgMIBQAAAA==.',Kn='Knocksteady:BAAALAAECgYICwAAAA==.Knoxform:BAAALAADCggICQAAAA==.Knoxrages:BAAALAAECgMIBQABLAADCggICQABAAAAAA==.',Kr='Krisanthemus:BAAALAADCggICAAAAA==.Krogg:BAAALAADCggIDAAAAA==.Krzzy:BAAALAAECgEIAQABLAAECgcIDQABAAAAAA==.',Ky='Kynbrookera:BAAALAAECgYICgAAAA==.',['Kì']='Kìnky:BAAALAAECgEIAQAAAA==.',La='Lavan:BAAALAAECgEIAQAAAA==.',Le='Legendary:BAAALAAECgMIBQAAAA==.Letrissia:BAAALAAECgMIBQAAAA==.',Li='Lilchargey:BAAALAADCggIDgAAAA==.Lilyheart:BAAALAADCgcIBwAAAA==.Lit:BAAALAADCggICAAAAA==.Littledog:BAAALAAECgYIDAAAAA==.',Lo='Lorthamar:BAAALAAECgQIBQAAAA==.Lotten:BAAALAAECgEIAgAAAA==.',Lu='Luckevin:BAAALAADCgUIBQAAAA==.Lunitari:BAAALAADCgYIBgAAAA==.Lurashtai:BAAALAADCgMIBAAAAA==.Luthorx:BAAALAADCggICAAAAA==.Luthran:BAAALAAECgIIAgABLAAECggIFQAHAFUYAA==.',Ma='Madbanger:BAAALAADCgcIBwAAAA==.Magmash:BAAALAADCggICAAAAA==.Malafang:BAAALAADCgcICQAAAA==.Malanah:BAAALAADCgYICwAAAA==.Matchez:BAAALAADCgEIAQAAAA==.Maverick:BAABLAAECoEUAAIIAAcIQyAxCQCVAgAIAAcIQyAxCQCVAgAAAA==.',Me='Meltedcheese:BAAALAADCgYICgAAAA==.',Mi='Michaella:BAAALAADCgcIDQAAAA==.Miramanie:BAAALAADCgUIBQAAAA==.',Mo='Mogar:BAAALAAECggIDAAAAA==.Mojitocurse:BAAALAADCggIFwAAAA==.Moonzhine:BAAALAAECgMIBQAAAA==.Moosejaw:BAAALAADCgUIBQAAAA==.Mordread:BAAALAADCgYIBwAAAA==.Mossyp:BAAALAADCggIDAAAAA==.',Na='Nai:BAAALAADCgQIBAAAAA==.',Ne='Nearly:BAAALAAECgYICgAAAA==.Nectar:BAAALAADCggIGQAAAA==.Netherward:BAAALAAECgMIAwABLAAECggIFwAFAG8gAA==.',Ni='Nidhögg:BAAALAADCgcIEgAAAA==.Niinia:BAAALAAECgIIAgAAAA==.Nivmizzet:BAAALAAECgYICQAAAA==.',No='Nokken:BAAALAADCgYIBgAAAA==.Nolakai:BAAALAADCgcIDQAAAA==.Novalea:BAAALAAECgYIDAAAAA==.Noxe:BAAALAAECgMIBQAAAA==.Noxiia:BAAALAADCggICAAAAA==.',['Nä']='Nädroj:BAAALAADCgMIAwAAAA==.',['Nø']='Nøstalgic:BAAALAAECgMIAwAAAA==.',Od='Odogaren:BAAALAAFFAEIAQAAAA==.',Og='Ogsleepy:BAAALAADCgcIBwAAAA==.',Om='Omnipunch:BAAALAAECgcIDAAAAA==.',Ox='Oxxo:BAAALAADCgYIBgAAAA==.',Pa='Paladdin:BAAALAAECgIIAgAAAA==.Paraggonn:BAAALAADCggIDwAAAA==.Parraggonn:BAAALAADCgIIAgAAAA==.',Pe='Perlonis:BAAALAAECgMIAwAAAA==.',Ph='Phury:BAAALAAECgYICgAAAA==.',Pi='Pinkfloydian:BAAALAAECgcIEAAAAA==.Pinpusmaxmus:BAAALAADCgYICgAAAA==.Pizza:BAAALAADCgYIBgAAAA==.',Po='Pomomies:BAAALAADCgMIAwAAAA==.Pooseunpoose:BAAALAADCgcICQAAAA==.',Ra='Raveneyes:BAEALAAECgMIBQAAAA==.Raynesong:BAAALAADCggIDwAAAA==.',Re='Reddemon:BAAALAAECgEIAgAAAA==.Restorott:BAAALAADCgMIAwAAAA==.',Rh='Rhaenfyre:BAAALAAECgMIBwAAAA==.Rhya:BAAALAADCgcIBwAAAA==.',Ri='Ricola:BAAALAAECgYIDAAAAA==.Rivenel:BAAALAADCggIDgAAAA==.',Ro='Rocksann:BAAALAADCgcIBwAAAA==.Roperklax:BAAALAADCggICAAAAA==.',Ru='Runawäy:BAAALAAECgMIBAAAAA==.Rundas:BAAALAAECgEIAQAAAA==.',Ry='Ryukira:BAAALAADCgIIAgAAAA==.',['Rá']='Rándymársh:BAAALAADCgYIBgABLAADCgcIDQABAAAAAA==.',Sa='Sadorry:BAAALAAECgMIBQAAAA==.Salic:BAAALAAECgIIAgAAAA==.Sanaroth:BAAALAADCgUIBQAAAA==.Sape:BAAALAAECgMIBAAAAA==.Sarasvati:BAAALAADCgcIBwAAAA==.Sassafrazz:BAAALAADCggIDwAAAA==.Savagebeauty:BAAALAADCgMIBgAAAA==.Savvy:BAAALAADCgUIBAAAAA==.',Sc='Scrumbles:BAAALAAECgMIAwAAAA==.',Se='Segador:BAAALAAECgEIAQAAAA==.',Sh='Shadazar:BAAALAADCggICAAAAA==.Shamanizim:BAAALAAECgMIBAAAAA==.Shampoon:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.Shedog:BAAALAADCgYIBgAAAA==.Sheeanna:BAAALAADCgYIBgAAAA==.Shenzii:BAAALAAECgIIAgAAAA==.Shinotenshi:BAAALAAECgEIAQAAAA==.Shugarae:BAAALAAECgIIAgAAAA==.Shédim:BAAALAAECgEIAQAAAA==.Shórtstalk:BAAALAADCgIIAgAAAA==.',Sl='Slayter:BAAALAAECgMICAAAAA==.Slithiss:BAAALAADCgUIBgAAAA==.',So='Soju:BAAALAADCggIDgABLAAECgcIEAABAAAAAA==.',St='Stolen:BAAALAAECgMIAgABLAAECgcIEQABAAAAAA==.',Su='Suli:BAAALAADCgYIBgAAAA==.Sunrise:BAAALAAECgIIBAAAAA==.Suzsette:BAAALAADCgMIAwAAAA==.',Sw='Sweaty:BAAALAAECgcIDQAAAA==.',Sy='Syljhana:BAAALAADCgcIBwAAAA==.Sylris:BAAALAAECgEIAQAAAA==.Sylvanthis:BAAALAADCgcICQAAAA==.Synnimon:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.Synnov:BAAALAAECgMIAwAAAA==.Syrrellia:BAAALAADCgcIBAAAAA==.Syzzle:BAAALAAECgEIAQABLAAECgMIBQABAAAAAA==.',['Sç']='Sçoxx:BAAALAAECgEIAQAAAA==.',Ta='Tanorial:BAAALAAECgYIDAAAAA==.',Te='Teneturadvas:BAAALAADCggICAABLAADCggIEAABAAAAAA==.Terrorblades:BAAALAAECgIIAgAAAA==.',Th='Thelastvirg:BAAALAAECgcIDQAAAA==.Thundrus:BAAALAAECgIIAgAAAA==.Thunsar:BAAALAADCgQIBwAAAA==.',Ti='Tine:BAAALAADCggIDwABLAAECgMIAwABAAAAAA==.',To='Toxicposion:BAAALAADCgcIDwAAAA==.',Tr='Tragedeigh:BAAALAAECgMIAwAAAA==.Trávpac:BAAALAAECgYIBgAAAA==.',Tt='Ttjpll:BAAALAADCgYICQAAAA==.',Tu='Tuckncloak:BAAALAADCgMIAwAAAA==.',Ty='Tyræll:BAAALAAECgIIAgABLAAFFAEIAQABAAAAAA==.',Ug='Ugrup:BAAALAADCggIDAAAAA==.',Ul='Ulumonk:BAAALAADCgQIBAABLAAECggIFQAHAFUYAA==.Ulurak:BAABLAAECoEVAAQHAAgIVRjHCgBMAgAHAAgIVRjHCgBMAgAJAAQIqgYVFADBAAAKAAMIrQwgOQCQAAAAAA==.',Un='Uncleskip:BAAALAADCggICAAAAA==.',Ur='Urza:BAAALAAECgYIBwAAAA==.',Va='Valhondria:BAAALAAECgYIDAAAAA==.Valhondrias:BAAALAADCggICAAAAA==.Vallorien:BAAALAADCgYIDQAAAA==.Varnier:BAAALAAECgYICQAAAA==.',Ve='Vengeânce:BAAALAADCgcICwAAAA==.Venïce:BAAALAADCggIDgAAAA==.Vespyr:BAAALAADCgUIBgAAAA==.',Vi='Villarae:BAAALAADCgcIBwAAAA==.',Vo='Voidspear:BAAALAADCggICAAAAA==.',Vu='Vulpe:BAAALAADCggIDgABLAADCggIEAABAAAAAA==.',Vy='Vynl:BAAALAADCgYIDAAAAA==.',Wa='Waili:BAAALAAECgEIAQAAAA==.Waritosz:BAAALAADCggICgAAAA==.',Wh='Wholy:BAAALAAECgUIBwAAAA==.',Wo='Woodryktor:BAAALAADCggIDwAAAA==.Worm:BAAALAADCgMIAwAAAA==.',Xa='Xaanii:BAAALAAECgEIAQAAAA==.Xalatathh:BAAALAAECgUIBwAAAA==.',Xu='Xuefeiyan:BAAALAAECgYICwAAAA==.',Xy='Xyligosa:BAAALAADCggICAAAAA==.',Za='Zaralina:BAAALAAECgMIAwAAAA==.Zaza:BAAALAADCgcIFAAAAA==.Zazasr:BAAALAADCgMIAwAAAA==.',Zh='Zharfrost:BAAALAADCggIDAAAAA==.',Zo='Zombiehunter:BAAALAAECgUIBwAAAA==.Zornqueff:BAAALAAECgMIBQAAAA==.',['Zö']='Zörtax:BAAALAAECgEIAQAAAA==.',['Åt']='Åthena:BAAALAAECgcIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end