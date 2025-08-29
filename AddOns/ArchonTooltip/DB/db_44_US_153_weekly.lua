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
 local lookup = {'Unknown-Unknown','Monk-Windwalker','Evoker-Preservation','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy',}; local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acalyn:BAAALAADCgcIBwAAAA==.Acaric:BAAALAAECgMIBAAAAA==.',Al='Alchemist:BAAALAADCgYICQAAAA==.Alegar:BAAALAADCgcICgAAAA==.Allixis:BAAALAADCgcIBwAAAA==.Alluriel:BAAALAADCgcIEwAAAA==.Altharoth:BAAALAAECgYICgAAAA==.Alypia:BAAALAADCgcIDQAAAA==.',Am='Amira:BAAALAAFFAEIAQAAAA==.',Ap='Applepies:BAAALAADCgcIBwAAAA==.',Ar='Arauial:BAAALAADCgYICgAAAA==.Areez:BAAALAADCgcIBwAAAA==.Aribella:BAAALAAECgYICQAAAA==.Arizann:BAAALAAECgMIAwAAAA==.Arobotdr:BAAALAADCgcIBwAAAA==.',As='Asapglocky:BAAALAADCgQIBAAAAA==.',Au='Aurolina:BAAALAAECgYICgAAAA==.',Ba='Baelrog:BAAALAADCgcIEQAAAA==.Baiene:BAAALAAECgMIBQAAAA==.Bandalar:BAAALAAECgcICwAAAA==.Barfbutt:BAAALAAECgMIAwAAAA==.Bashems:BAAALAADCgcIBAAAAA==.',Be='Beachnaga:BAAALAADCgMIAwAAAA==.Beastette:BAAALAAECgMIAwAAAA==.Beefstums:BAAALAAECgMIAwAAAA==.Bento:BAAALAADCgcIEQAAAA==.',Bl='Bleak:BAAALAADCgUIBQAAAA==.Blessedtotem:BAAALAAECgEIAQAAAA==.Blueeyearch:BAAALAAECgEIAQAAAA==.',Bo='Bo:BAAALAAECgYICQAAAA==.Bobb:BAAALAAECgMIBQAAAA==.Bolgan:BAAALAAECgYIDwAAAA==.Boosh:BAAALAAECgMIAwAAAA==.Bowknee:BAAALAAECgYICQAAAA==.Bowsho:BAAALAAECgQICQAAAA==.',Br='Brassybella:BAAALAADCgcICwAAAA==.Breezybone:BAAALAADCggICQAAAA==.Briollias:BAAALAADCgcIBwAAAA==.',Bu='Bumbokan:BAAALAAECgEIAgAAAA==.Bunnytitan:BAAALAADCgcIBwAAAA==.Bunsnekbun:BAAALAADCggICAAAAA==.Butterbunz:BAAALAAECgIIAgAAAA==.',Bw='Bwangifer:BAAALAAECgMIAwAAAA==.',Ca='Cacunningham:BAAALAADCgcIBwAAAA==.Caitriona:BAAALAAECgMIAwAAAA==.Canalyn:BAAALAAECgIIAgAAAA==.Cargae:BAAALAADCgYICQAAAA==.',Ce='Celenis:BAAALAAECgEIAQAAAA==.Cellysa:BAAALAAECgQIBwAAAA==.Cellysia:BAAALAADCgIIAgAAAA==.Ceramyth:BAAALAAECgMIAwAAAA==.Ceres:BAAALAAECgMIAwAAAA==.Cesara:BAAALAAECgMIBQAAAA==.Ceseria:BAAALAAECgIIAgAAAA==.Cesiline:BAAALAADCgYICQAAAA==.',Ch='Chaahck:BAAALAAECgMIBwAAAA==.Chaliss:BAAALAAECgIIAgAAAA==.Chbribs:BAAALAADCgcIEwAAAA==.',Cl='Claus:BAAALAAECgEIAQAAAA==.',Co='Comma:BAAALAAECgYICQAAAA==.Corn:BAAALAADCggIFQAAAA==.',Cy='Cyphragon:BAAALAAECgMIAwAAAA==.Cyrinx:BAAALAADCgcIEAAAAA==.',Da='Dakz:BAAALAADCgcIBwAAAA==.Dalend:BAAALAAECgMIBQAAAA==.Damerot:BAAALAAECgEIAQAAAA==.Dawnsingers:BAAALAADCgcIBAAAAA==.',De='Deadbeard:BAAALAAECgEIAQAAAA==.Deadlocs:BAAALAADCggIEAAAAA==.Deathmethods:BAAALAAECgMIBwAAAA==.Deepwater:BAAALAAECgMIBAAAAA==.Deesnucks:BAAALAADCgcIDAAAAA==.Dellydd:BAAALAAECgMIBQAAAA==.Delphina:BAAALAADCggICwAAAA==.Demini:BAAALAADCggIFQAAAA==.Demisê:BAAALAAECgMIBgAAAA==.Demonrick:BAAALAADCgcIEgAAAA==.Derithon:BAAALAAECgQIBgAAAA==.',Di='Dillinger:BAAALAADCggIDwAAAA==.Dingodgaf:BAAALAADCgMIAwAAAA==.',Do='Doomstir:BAAALAADCgcICQAAAA==.',Dr='Dranius:BAAALAAECgYICQAAAA==.Drendar:BAAALAADCgcIBgAAAA==.Driztette:BAAALAAECgEIAQAAAA==.Drnewport:BAAALAADCggICQAAAA==.Drunkfuq:BAAALAADCgQIBAABLAADCgUIBQABAAAAAA==.Drystine:BAAALAAECgMIBAAAAA==.',Du='Dubbtown:BAAALAADCgYIBgAAAA==.Dugtig:BAAALAADCggICAAAAA==.',Ee='Eedeeweewee:BAAALAADCgYIBgAAAA==.',El='Electroshokk:BAAALAAECgEIAQAAAA==.Eleios:BAAALAAECgIIAgAAAA==.Elipsis:BAAALAAECgYIDAAAAA==.Elm:BAAALAAECgMIBAAAAA==.Elmus:BAAALAADCgUIBQAAAA==.Elybella:BAAALAAECgYICQAAAA==.Elysirath:BAAALAAECgMIBgAAAA==.',Em='Emanon:BAAALAAECgIIAgAAAA==.',Er='Erkor:BAAALAADCgcIDwAAAA==.Erythorbic:BAAALAAECgMIBQAAAA==.',Es='Estralage:BAAALAADCgcIDwAAAA==.',Ev='Evictor:BAAALAADCgUIBQABLAAECgMIBgABAAAAAA==.Evoshatter:BAAALAADCggICQAAAA==.',Ex='Exileelfsam:BAAALAAECgMIAwAAAA==.',Fa='Faranth:BAAALAADCgcICgAAAA==.Faîle:BAAALAAECgQIBQAAAA==.',Fe='Feltigress:BAAALAADCgYIBgAAAA==.',Ff='Ffugme:BAAALAAECgIIAgAAAA==.Ffugoff:BAAALAAECgEIAQAAAA==.',Fi='Finnian:BAAALAAECgMIAwAAAA==.Fio:BAAALAAECgYICQAAAA==.Firiona:BAAALAADCgIIAQAAAA==.Fistfuloftok:BAAALAADCgcIBwAAAA==.',Fl='Flood:BAAALAAECggIBAAAAA==.Fläva:BAAALAAECgMIBgAAAA==.',Fr='Fresca:BAAALAADCgcICAAAAA==.Frosht:BAAALAADCgYIBgAAAA==.Frostmage:BAAALAAECgEIAgAAAA==.',['Fà']='Fàrmer:BAAALAADCgIIAgAAAA==.',['Fö']='Föx:BAAALAADCggIEAAAAA==.',Ga='Gafocalypse:BAAALAADCgcICwAAAA==.Gatsuji:BAABLAAECoEVAAICAAgIfRfVBwBQAgACAAgIfRfVBwBQAgAAAA==.',Gi='Gigowatt:BAAALAAECgEIAgAAAA==.',Gl='Glaciaah:BAAALAADCgYIBwAAAA==.Glifberg:BAAALAAECgEIAQAAAA==.',Go='Goovs:BAAALAADCgMIBQAAAA==.',Gr='Greed:BAAALAADCgUIBQAAAA==.Griselbrand:BAAALAAECgYICwAAAA==.Grotok:BAAALAAECgIIAwAAAA==.',Gu='Gub:BAAALAAECgEIAgAAAA==.Gumer:BAAALAADCgcICwAAAA==.Guri:BAAALAADCggICQAAAA==.',Gy='Gywnevere:BAAALAADCgcIBwAAAA==.',['Gü']='Günter:BAAALAAECgEIAgAAAA==.',Ha='Halraku:BAAALAADCgcIBwAAAA==.Halygos:BAAALAADCgcIBwAAAA==.Hammeredchic:BAAALAADCgcIBwAAAA==.',He='Herpecluster:BAAALAADCgcIBwAAAA==.',Hi='Hister:BAAALAAECgUIBgAAAA==.',Hu='Hugulin:BAAALAAECgIIAgAAAA==.',Ib='Ibuprophen:BAAALAADCgIIAgAAAA==.',Ic='Iceblocklulz:BAAALAADCgQIBAAAAA==.Icing:BAAALAADCggICAAAAA==.',Ig='Iggey:BAAALAADCggICgAAAA==.Iggles:BAAALAADCgcIBAAAAA==.',Il='Ilandras:BAAALAAECgMIBAAAAA==.Ililith:BAAALAADCgEIAQAAAA==.Illidanstörm:BAAALAADCggICAAAAA==.Illvillidan:BAAALAADCgcICgAAAA==.',It='Itachii:BAAALAADCgQIBQAAAA==.Itsredbelow:BAAALAADCgMIAwAAAA==.',Ja='Jackblãck:BAAALAADCgQIBAAAAA==.Jaisu:BAAALAADCgMIAwAAAA==.',Ji='Jibberlock:BAAALAAECggIBwABLAAECgMIAwABAAAAAA==.Jibbydude:BAAALAADCgYICQAAAA==.',Ju='Justen:BAAALAADCgMIAwAAAA==.',Ka='Kalila:BAAALAAECgYICAAAAA==.Katsuko:BAAALAAECgMIBgAAAA==.Kattnirra:BAAALAAECgQIBwAAAA==.Katze:BAAALAADCggIDwAAAA==.',Ke='Keannor:BAAALAAECgMIAwAAAA==.Keepper:BAAALAAECgYIDQAAAA==.Keiraa:BAAALAADCgIIAgAAAA==.Kenj:BAAALAAECgYICgAAAA==.Kenjurr:BAABLAAECoEXAAIDAAYI4yVLBABcAgADAAYI4yVLBABcAgABLAAECgYICgABAAAAAA==.Kennahirn:BAAALAAECgMIBAAAAA==.',Ki='Kickashes:BAAALAADCgEIAQAAAA==.Killahaseo:BAAALAAECgMIBAAAAA==.Killmoedee:BAAALAAECgQICQAAAA==.Kiscandra:BAAALAAECgIIAgAAAA==.Kiss:BAAALAADCgEIAQAAAA==.',Ko='Koopa:BAAALAADCgQIAgABLAAECgYICwABAAAAAA==.Korvithraz:BAAALAAECgMIBQAAAA==.Kozzmo:BAAALAADCgYIBgAAAA==.',Kr='Kryptic:BAAALAADCggICAAAAA==.',Ku='Kuari:BAAALAADCgcIBwAAAA==.Kui:BAAALAAECgMIAwAAAA==.Kupua:BAAALAADCgIIAgAAAA==.',La='Laerla:BAAALAADCgcIBwAAAA==.Laetri:BAAALAAECgYICgAAAA==.Laylene:BAAALAAECgEIAgAAAA==.Lazloo:BAAALAAECgEIAQAAAA==.Lazymidget:BAAALAAECggICAAAAA==.',Le='Legindkiller:BAAALAADCgcIEAAAAA==.',Li='Lightsward:BAAALAADCgYICQAAAA==.',Lo='Lockatock:BAAALAADCgUIBQAAAA==.Lockrah:BAAALAADCgcIBgAAAA==.Loun:BAAALAAECgMIAwAAAA==.',Lu='Luciellia:BAAALAADCgYICwAAAA==.Lumianis:BAAALAADCgQIBAAAAA==.Luminae:BAAALAAECgIIAwAAAA==.',Ly='Lyn:BAAALAAECgcICgAAAA==.',Ma='Mackenziiee:BAAALAAECgMIBQAAAA==.Magenside:BAAALAADCgQIBAAAAA==.Magicwater:BAAALAAECgQIBwAAAA==.Magyar:BAAALAAECgMIBAAAAA==.Mainline:BAAALAADCgYIBwAAAA==.Maizepriest:BAAALAAECgMIBAAAAA==.Malz:BAAALAADCgYICgABLAAECgIIAgABAAAAAA==.Mannysaf:BAAALAAECgIIAgAAAA==.Marröw:BAAALAAECgIIAgAAAA==.Masfima:BAAALAAECgIIAgAAAA==.Maxz:BAAALAAECgMIAwAAAA==.',Me='Melinesc:BAAALAADCgcIDAAAAA==.Mellowlink:BAAALAAECgEIAgAAAA==.Melvier:BAAALAADCgYIBgAAAA==.',Mi='Mickeyy:BAAALAADCgcIBwAAAA==.Mimi:BAACLAAFFIELAAMEAAYIoSFSAADiAQAEAAUIlyBSAADiAQAFAAEI1yYfCQB3AAAsAAQKgRYAAwQACAiMJSADABQDAAQACAiGJSADABQDAAUAAgg5IRBQALoAAAAA.Mirlanda:BAAALAAECgEIAQAAAA==.',Mo='Mordrassil:BAAALAADCgcIBwAAAA==.Mortenous:BAAALAADCgcICwAAAA==.Mowte:BAAALAADCgYICQAAAA==.',My='Mystáke:BAAALAAECgMIBQAAAA==.',['Mê']='Mêrcy:BAAALAADCgUIBQAAAA==.',Na='Narcissus:BAAALAADCgYICQAAAA==.Nautrium:BAAALAADCgQIBQAAAA==.',Ne='Nessanova:BAAALAAECggIDAAAAA==.Neyt:BAAALAADCgMIAwAAAA==.Neytdrake:BAAALAADCggIDQAAAA==.Neytfury:BAAALAAECgYICwAAAA==.Neytshock:BAAALAADCggICAAAAA==.Neytwa:BAAALAAECgMIAwAAAA==.',Ni='Nikkikynz:BAAALAADCgcIDAAAAA==.Nitalan:BAAALAADCgYICQAAAA==.',No='Nopet:BAAALAAECgQIBAAAAA==.Noras:BAAALAAECgMIBgAAAA==.Nordicslayer:BAAALAAECgIIAgAAAA==.Notagnoblin:BAAALAAECgYIEwAAAA==.',Nu='Nuffsaid:BAAALAADCgIIAgAAAA==.',Ny='Nyvee:BAAALAADCgYIBgAAAA==.',Ob='Obnyxion:BAAALAAECgcIDAAAAA==.',Og='Ogrelurd:BAAALAADCgcIBwAAAA==.',Om='Omstrong:BAAALAAECgEIAQAAAA==.',Op='Ophelia:BAAALAAECgUICQAAAA==.',Or='Orakwa:BAAALAAECgEIAQAAAA==.',Pa='Packdh:BAAALAAECgYICgAAAA==.Pakingshet:BAAALAAECgQICgAAAA==.Pallinda:BAAALAAECgIIAgAAAA==.Panz:BAAALAAECgMIAwAAAA==.Pappyoblu:BAAALAADCgcIBAAAAA==.',Pe='Pendulumlaw:BAAALAAECgYICQAAAA==.Pennypacker:BAAALAADCggICQAAAA==.Petmycat:BAAALAAECgEIAQAAAA==.Petsmart:BAAALAADCggIAgAAAA==.',Ph='Phoel:BAAALAADCgYIBgAAAA==.',Pi='Pinkbuns:BAAALAAECgMIAwAAAA==.',Pn='Pneuma:BAAALAAECgEIAQAAAA==.',Po='Pofella:BAAALAADCggICAAAAA==.Portalkombat:BAAALAAECgYICQAAAA==.',Pr='Prenton:BAAALAAECgMIBQAAAA==.Pristin:BAAALAADCgcIBwAAAA==.Profundity:BAAALAADCgMIBAAAAA==.Prometheus:BAAALAAECgEIAQAAAA==.',Pu='Putangina:BAAALAAECgEIAgABLAAECgQICgABAAAAAA==.Puzzykat:BAAALAADCggICAAAAA==.',['Pä']='Päg:BAAALAADCggICQABLAAECgIIAgABAAAAAA==.',Qe='Qeini:BAAALAAECgMIBgAAAA==.',Ra='Raelashe:BAAALAAECgcIDwAAAA==.Rafoff:BAAALAADCgcIEQAAAA==.Ragnarax:BAAALAADCgcIBwAAAA==.Rahtoth:BAAALAADCgIIAgAAAA==.Rancoramble:BAAALAAECgMIBQAAAA==.Ranekk:BAAALAADCgEIAQAAAA==.Ranga:BAAALAADCggICAAAAA==.Razblood:BAAALAAECgQIBgAAAA==.',Re='Remmaryn:BAAALAAECgMIAwAAAA==.Rengår:BAAALAADCgEIAgAAAA==.Reticent:BAAALAADCgcIBgAAAA==.Reyth:BAAALAADCgcIEAAAAA==.',Rh='Rhuby:BAAALAAECgMIBAAAAA==.',Ri='Ricewalker:BAAALAAECgEIAgAAAA==.Rikenji:BAAALAADCgMIAwAAAA==.Rionya:BAAALAAECgMIAwAAAA==.Riptîde:BAAALAAECgQICAAAAA==.',Ro='Robodwarf:BAAALAAECgQICQAAAA==.Rochelle:BAAALAADCgQIBAAAAA==.Rousimar:BAAALAADCggIDQAAAA==.',Ru='Rubbmytotems:BAAALAADCgcIBAAAAA==.Ruleti:BAAALAAECgYICQAAAA==.Russell:BAAALAADCgYICQAAAA==.',Sa='Sabado:BAAALAADCgcIEwAAAA==.Santrious:BAAALAADCgYIBgAAAA==.Saralanna:BAAALAAECgMIBAAAAA==.Sarefina:BAAALAAECgIIAgAAAA==.Saths:BAAALAAECgcIEQAAAA==.',Sc='Scoban:BAABLAAECoEWAAIGAAgILBfnCQAoAgAGAAgILBfnCQAoAgAAAA==.',Se='Sentaspell:BAAALAADCgUIBQAAAA==.',Sh='Shadowmander:BAAALAADCggICAAAAA==.Shammieodd:BAAALAADCggICAAAAA==.Shamthorn:BAAALAADCggIFQAAAA==.Shaqfu:BAAALAADCgMIBgAAAA==.Shnow:BAAALAADCggICQAAAA==.Shugz:BAAALAADCgYICQAAAA==.Shumai:BAAALAADCgIIAgAAAA==.',Si='Sikxrevenge:BAAALAAECgUICQAAAA==.Siliconista:BAAALAAECgYIDAAAAA==.Silverbolt:BAAALAADCgQIBAAAAA==.Sinderone:BAAALAADCggICAAAAA==.',Sl='Slaidan:BAAALAAECgMIBAAAAA==.Sllew:BAAALAAECgIIAgAAAA==.Slopehho:BAAALAADCggICAAAAA==.',Sm='Smoulder:BAAALAADCggICQAAAA==.',Sn='Snigles:BAAALAADCgcICwAAAA==.',So='Socretz:BAAALAADCgcIBwAAAA==.Soules:BAAALAAECgIIAgAAAA==.Soulumin:BAAALAADCgMIAwAAAA==.',Sp='Sposi:BAAALAAECgMIBAAAAA==.',Ss='Sselionn:BAAALAADCggIBwAAAA==.',St='Stomps:BAAALAAECgQIBgAAAA==.Stonefoot:BAAALAADCgcICwAAAA==.',Su='Susann:BAAALAAECgIIAgAAAA==.Sutomi:BAAALAADCggICAABLAAECgcICgABAAAAAA==.',Sy='Syravia:BAAALAAECgMIBAAAAA==.',['Sé']='Séraphyne:BAAALAADCgcIEwAAAA==.',Ta='Talarin:BAAALAAECgEIAQAAAA==.Tavinrayn:BAAALAADCgQIBAAAAA==.Tayder:BAAALAAECgMIBAAAAA==.',Te='Tekesh:BAAALAAECgMIAwAAAA==.Tenebris:BAAALAAECgYIBgAAAA==.Tensen:BAAALAADCgcICwAAAA==.Teshara:BAAALAADCgcIBwAAAA==.',Th='Theladyboy:BAAALAAECgEIAQAAAA==.Throhk:BAAALAADCgUIAgAAAA==.',Ti='Tibblespri:BAAALAAECgYIEgAAAA==.Tigerliley:BAAALAAECgEIAQABLAAECgQIBwABAAAAAA==.',To='Toordiin:BAAALAADCgcIBAAAAA==.Torstai:BAAALAADCgcIEwAAAA==.',Ts='Tserendolgor:BAAALAADCgcIDAAAAA==.',Tw='Twinight:BAAALAADCgcIBwABLAAECgQIBwABAAAAAA==.Twinsha:BAAALAAECgQIBwAAAA==.Twyla:BAAALAAECgMIBAAAAA==.',Ty='Tylanis:BAAALAADCgcIBwAAAA==.Tyresious:BAAALAADCgcIBwAAAA==.',Ul='Ultimon:BAAALAAECgEIAQAAAA==.',Un='Unauma:BAAALAAECgYICQAAAA==.Unsainted:BAAALAADCgQIBAAAAA==.',Va='Vahaghn:BAAALAADCggICAAAAA==.Valedus:BAAALAAECgYICgAAAA==.',Ve='Veroya:BAAALAAECgYICwAAAA==.Vespra:BAAALAAECgQICQAAAA==.Vetinari:BAAALAADCgYICQAAAQ==.',Vi='Vine:BAAALAADCgUIBQABLAAECgMIBAABAAAAAA==.',Vo='Volcker:BAAALAAECgMIBQAAAA==.Voldamar:BAAALAAECgMIBgAAAA==.Voltuk:BAAALAAECgUIBwAAAA==.',Vy='Vyria:BAAALAAECgEIAQABLAAECgYIBgABAAAAAA==.',Wa='Wadoralock:BAAALAAECgYIDAAAAA==.Waeylith:BAAALAAECgMIBAAAAA==.Wahnsinn:BAAALAAECgEIAQAAAA==.Waoconñaw:BAAALAADCgQIBAAAAA==.Warrock:BAAALAADCggIFwAAAA==.Warwarb:BAAALAADCggIDQAAAA==.Waterliliy:BAAALAAECgQIBwAAAA==.',We='Weepingångel:BAAALAAECgMIBwAAAA==.Weroroakiji:BAAALAAECgEIAgAAAA==.',Wi='Wildcarde:BAAALAADCgEIAQAAAA==.Wingnaprayer:BAAALAADCgcICwAAAA==.',Wo='Wongidan:BAAALAAECgEIAQAAAA==.Woofee:BAAALAADCgMIBAAAAA==.',Wr='Wrath:BAAALAADCgMIAwAAAA==.Wrot:BAAALAADCggIDwAAAA==.',['Wý']='Wýler:BAAALAAECgQIBAAAAA==.',Xa='Xanderella:BAAALAAECgEIAQAAAA==.',Xe='Xedus:BAAALAADCgIIAgAAAA==.Xeltal:BAAALAAECgMIBAABLAAECgYICwABAAAAAA==.',Xi='Xilla:BAAALAAECgEIAgAAAA==.',Yi='Yitian:BAAALAAECgQIBgAAAA==.',Yo='Yorllik:BAAALAADCgMIAwAAAA==.',Za='Zaraelil:BAAALAADCgMIAwAAAA==.Zarrx:BAAALAADCgcIBwAAAA==.',Ze='Zetsuî:BAAALAADCgUIBQAAAA==.',Zh='Zhorvan:BAAALAAECgIIAgAAAA==.',Zo='Zoboomafoo:BAAALAAECgQICQAAAA==.',['Äc']='Äcid:BAAALAAECgMIBQAAAA==.',['Åp']='Åpollo:BAAALAAECgMIAwAAAA==.',['Ðe']='Ðeja:BAAALAADCgMIAwAAAA==.',['Òm']='Òmgitsbwòng:BAAALAAECgQIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end