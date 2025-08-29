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
 local lookup = {'Unknown-Unknown','DeathKnight-Blood','Priest-Holy','Priest-Discipline',}; local provider = {region='US',realm='Uther',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acalla:BAAALAADCgMIAwAAAA==.',Ad='Addiction:BAAALAAECgEIAQAAAA==.',Ag='Ages:BAAALAADCgMIAwAAAA==.',Al='Alcidde:BAAALAADCgIIAgAAAA==.Aliancia:BAAALAAECgIIAgAAAA==.Alobar:BAAALAADCgcIBwAAAA==.Aloriel:BAAALAADCgMIAwAAAA==.',An='Ankelbyter:BAAALAAECgYICAAAAA==.Annelynne:BAAALAAECgMIAwAAAA==.Annora:BAAALAAECgQIBQAAAA==.Anthraxx:BAAALAAECgYIBgAAAA==.',As='Assclapiuss:BAAALAAECgMIAwAAAA==.Asterchades:BAAALAAECgMIBAAAAA==.Asterius:BAAALAAECgMIAwAAAA==.Astlin:BAAALAAECgcICgAAAA==.',At='Athennah:BAAALAAECgMIBAAAAA==.Atrophe:BAAALAAECgMIBAAAAA==.Attikus:BAAALAAECgEIAQAAAA==.',Au='Auralass:BAAALAADCggIFQAAAA==.Aurene:BAAALAAECgYICAAAAQ==.',Av='Avatard:BAAALAAECgYICwAAAA==.',Ba='Babashaba:BAAALAADCggICQAAAA==.Babbles:BAAALAADCggICAAAAA==.Bandaidkit:BAAALAAECggIEwAAAA==.',Be='Beep:BAAALAAECgMIAwAAAA==.Beezer:BAAALAAECgEIAQAAAA==.Behemothe:BAAALAAECgMIBAAAAA==.Beryllos:BAAALAADCgYIBgAAAA==.',Bi='Bigdmg:BAAALAAECgMIBAAAAA==.Bigjustice:BAAALAADCgEIAQAAAA==.Bigspoon:BAAALAAECgIIBAAAAA==.',Bl='Bledana:BAAALAAECgMIBQAAAA==.Bleué:BAAALAADCgcIBwAAAA==.Bloodmourne:BAAALAAECgMIBAAAAA==.',Bo='Boggz:BAAALAADCggIEgAAAA==.Borthyr:BAAALAAECgYICAAAAA==.Bowowner:BAAALAAECgEIAQAAAA==.',Ca='Catastrophic:BAAALAAECgMIAwAAAA==.Catmaan:BAAALAAECgMIBQAAAA==.',Ch='Chamelean:BAAALAAECgYIDgAAAA==.Chaosburns:BAAALAAECgMIAwAAAA==.Chimpnzthat:BAAALAADCggIFQAAAA==.Chookicookie:BAAALAAECgMIBAAAAA==.Chrome:BAAALAAECgMIBAAAAA==.',Ci='Cinderwisp:BAAALAADCgUIBQAAAA==.Cindyy:BAAALAAECgUICAAAAA==.',Cl='Cluterbuck:BAAALAADCgIIAgAAAA==.',Co='Coldbeans:BAAALAAECgIIBAAAAA==.Coresh:BAAALAADCgUIBQAAAA==.Cornpuff:BAAALAAECgEIAQAAAA==.',Cr='Creedd:BAAALAAECgMIBgAAAA==.',Da='Damessiah:BAAALAAECgIIAgAAAA==.Dark:BAAALAAECgMIBAAAAA==.Darkphyre:BAAALAAECgEIAQAAAA==.Darthtree:BAAALAADCgUIBQAAAA==.Davee:BAAALAAECgYICAAAAA==.',De='Deadmandan:BAAALAADCgMIBAAAAA==.Demondred:BAAALAAECgEIAQAAAA==.Demonhugger:BAAALAADCgcIBwAAAA==.Deqlyn:BAAALAAECgMIBAAAAA==.Deschutes:BAAALAAECgMIAwAAAA==.Desmus:BAAALAADCggIDgAAAA==.Dethglaive:BAAALAADCgQIBAAAAA==.',Di='Diddyy:BAAALAADCgUIBQAAAA==.',Do='Dompally:BAAALAAECgQIBgAAAA==.Doomdooms:BAAALAAECgMIAwAAAA==.',Dr='Dragoncross:BAAALAADCgcICAAAAA==.Drakaina:BAAALAADCgUIBQAAAA==.Draknaroc:BAAALAADCggIFQAAAA==.Drpatan:BAAALAADCgQIBAAAAA==.Druni:BAAALAAECgEIAQAAAA==.',Ec='Echowalker:BAAALAADCgMIAwABLAADCggIFQABAAAAAA==.Eclipsse:BAAALAAECgEIAQAAAA==.',Ee='Eecho:BAAALAADCgQIBAABLAADCgUIBQABAAAAAA==.',Ek='Ekkroo:BAAALAADCgcIBwAAAA==.',Em='Emokillaz:BAAALAADCggIFAAAAA==.',En='Endor:BAAALAADCggIDwAAAA==.',Ep='Epictaxes:BAAALAADCgUIBQAAAA==.Epsilón:BAAALAAECgMIBAAAAA==.',Eu='Euphrate:BAAALAADCgYIBgAAAA==.',Ex='Exaduss:BAAALAAECgIIBAAAAA==.',Fa='Failbear:BAAALAAECgEIAQAAAA==.Faxon:BAAALAAECgIIBAAAAA==.Faylan:BAAALAAECgEIAQAAAA==.',Fi='Fibot:BAAALAAECgEIAQAAAA==.Fireboürne:BAAALAAECgcIEAAAAA==.',Fo='Forscythia:BAAALAADCgcIDAAAAA==.Foxyxaya:BAAALAAECgYICwAAAA==.',Fr='Fraeyah:BAAALAAECgEIAQAAAA==.Frogurt:BAAALAADCgUIBQAAAA==.',Ga='Gaborex:BAAALAAECgQIBgAAAA==.',Gh='Ghomertin:BAAALAADCgcIEwAAAA==.',Gi='Gipsydanger:BAAALAAECgUIBQAAAA==.Girthquake:BAAALAADCggICAAAAA==.',Gl='Gladiatrix:BAAALAADCgMIAwAAAA==.Glasnificent:BAAALAAECgMIAwAAAA==.Glassyå:BAAALAADCgMIBAAAAA==.',Go='Gonnjass:BAAALAADCgEIAgAAAA==.',Gr='Grakonys:BAAALAAECgMIBAAAAA==.Greensun:BAAALAADCgUIBQAAAA==.Grimmbot:BAAALAADCgMIBgAAAA==.Grunnck:BAAALAADCgMICAAAAA==.',Gw='Gwenfrewi:BAAALAADCgUIBQAAAA==.Gwydìon:BAAALAAECgYICAAAAA==.',Gy='Gypsyhunter:BAAALAAECgMIAwAAAA==.',Ha='Harron:BAAALAADCggIDgAAAA==.Hawtbooty:BAAALAADCggIFgAAAA==.Haziel:BAAALAADCgcIBwAAAA==.',He='Heartsbane:BAAALAADCggICAAAAA==.Helixrage:BAAALAAECgMIAwAAAA==.Hellreines:BAAALAAECgEIAQAAAA==.',Hi='Hildi:BAAALAADCggIFQAAAA==.',Ho='Holy:BAAALAAECgYICgAAAA==.',Hu='Hulkcrush:BAAALAADCgMIBAAAAA==.Humanítÿ:BAAALAADCgYIBgAAAA==.',Il='Illidab:BAAALAAECgMIBQAAAA==.',In='Incredibread:BAAALAAECgYICAAAAA==.Indub:BAAALAAECgEIAQAAAA==.',Is='Ishura:BAAALAADCgcIBwAAAA==.',It='Itsmejo:BAAALAAECgMIBAAAAA==.',Iv='Ivvy:BAAALAAECgEIAQAAAA==.',Iz='Izanami:BAAALAADCggIDgAAAA==.',Ja='Jadenzar:BAAALAAECgIIAgAAAA==.Jantra:BAAALAAECgIIAgABLAAECgQIBAABAAAAAA==.',Je='Jebby:BAAALAAECgcICwAAAA==.Jeebz:BAAALAADCggICQABLAAECgcICwABAAAAAA==.Jemmâ:BAAALAAECgYIDgAAAA==.',Jo='Joshc:BAAALAAECgMIBAAAAA==.',Ka='Kaaris:BAAALAAECgIIBAAAAA==.Kaiarie:BAAALAADCggIFQAAAA==.Kaippe:BAAALAAECgEIAQAAAA==.Kalordis:BAAALAADCgUIBQAAAA==.Kanzak:BAAALAADCggIDQAAAA==.Karkea:BAAALAAECgcICQAAAA==.',Ke='Kebin:BAAALAAECgMIAwAAAA==.Kelfhammer:BAAALAAECgYICQAAAA==.',Ki='Kibil:BAAALAAECgIIBAAAAA==.',Ko='Korax:BAAALAADCggIDwAAAA==.Kotek:BAAALAADCgMIAwAAAA==.',Ku='Kujiera:BAAALAAECgYIBgAAAA==.Kuroro:BAAALAAECgYICAAAAA==.Kurrents:BAAALAAECgIIBAAAAA==.',['Kâ']='Kârgorr:BAAALAADCggIGAAAAA==.',La='Lad:BAAALAAECgYICAAAAA==.Larryfish:BAAALAAECgIIBAAAAA==.Lavos:BAAALAAECgYICAAAAA==.',Le='Legionn:BAAALAAECgMIBAAAAA==.Leopan:BAAALAAECgEIAQAAAA==.Levitikus:BAAALAAECgMIAwAAAA==.Levìtikus:BAAALAADCgUIBQAAAA==.',Li='Lifereaver:BAAALAAECgQIBQAAAA==.Linxoln:BAAALAADCggIFgAAAA==.Liru:BAAALAAECgMIAwAAAA==.Lisster:BAAALAAECgMIBAAAAA==.',Lo='Loafe:BAAALAAECgYICwAAAA==.Lothric:BAAALAADCgUIBQAAAA==.',Lu='Lumeria:BAAALAAECgEIAQAAAA==.Lunaignis:BAAALAADCggICAAAAA==.Luthais:BAAALAAECgEIAQAAAA==.Luxury:BAAALAADCggIDgAAAA==.',Ly='Lysanthir:BAAALAAECgMIAwAAAA==.',Ma='Malevian:BAAALAAECgYICwAAAA==.Malfuridan:BAAALAADCgcIBwAAAA==.Mariasha:BAAALAADCgcIBwAAAA==.Mattx:BAAALAAECgIIAwAAAA==.Mazy:BAAALAAECgMIAwAAAA==.',Mc='Mckinnon:BAAALAADCgMIAwAAAA==.',Me='Megaterium:BAAALAADCggIFgAAAA==.',Mi='Miggytron:BAAALAAECgEIAQAAAA==.Missmisery:BAAALAAECgIIBAAAAA==.Mithdraug:BAAALAAECgEIAQAAAA==.',Mo='Mongalf:BAAALAADCgIIAgAAAA==.Moozenic:BAAALAAECgcIDQAAAA==.Mopsus:BAAALAAECgMIAwAAAA==.Mortarîon:BAAALAAECgYICAAAAA==.',My='Mystiqwolf:BAAALAADCggICAAAAA==.',Mz='Mztique:BAAALAAECggIBgAAAA==.',Ne='Nephcult:BAAALAAECgIIAgAAAA==.',Ni='Nishgrail:BAAALAAECgYICAAAAA==.',No='Nohkal:BAAALAADCgYICQAAAA==.Noreh:BAAALAADCggIDwAAAA==.',Nu='Nukusmaximus:BAAALAADCggIDgAAAA==.',Ny='Nyiah:BAAALAAECgIIBAAAAA==.Nyletak:BAAALAADCggICAAAAA==.',['Nâ']='Nâl:BAAALAAECgIIAgAAAA==.',Ok='Oktharun:BAABLAAECoEWAAICAAgIsSJPAQA5AwACAAgIsSJPAQA5AwAAAA==.',Ol='Oldbull:BAAALAADCgUIBQAAAA==.',On='Onex:BAAALAAECgEIAQAAAA==.Onfleek:BAAALAAECgMIAwAAAA==.',Op='Opalielle:BAAALAAECgIIAgAAAA==.',Or='Orgrím:BAAALAAECgYIBgAAAA==.',Pa='Palii:BAAALAADCgYIBwAAAA==.Pangørian:BAAALAADCgcIBwAAAA==.',Pe='Persefini:BAAALAAECgEIAQAAAA==.Petrokull:BAAALAADCgYICAAAAA==.Petronius:BAAALAADCgEIAQAAAA==.',Ph='Phaeder:BAAALAADCggICAAAAA==.',Pl='Plugugly:BAAALAAECgMIAwAAAA==.',Po='Polinemarois:BAAALAADCggIEAAAAA==.Porkque:BAAALAAECgMIAgAAAA==.Porthios:BAAALAADCgcIDQAAAA==.Possible:BAAALAADCgYIBgAAAA==.Potatobear:BAAALAAECgYICAAAAA==.',Pr='Prifduwies:BAAALAAECgMIAwAAAA==.',Qu='Quicktime:BAAALAAECgcICwAAAA==.',Ra='Ragedh:BAAALAAFFAIIAgAAAA==.Randyll:BAAALAAECgYICAAAAA==.Ranillan:BAAALAADCggIDgAAAA==.',Re='Reeses:BAAALAADCggICAABLAADCgcIBwABAAAAAA==.Retnuhnomeed:BAAALAADCggIEgAAAA==.Revara:BAAALAADCggIDgAAAA==.',Rh='Rhilik:BAAALAADCgMIBAAAAA==.',Ro='Robnsparkles:BAAALAAECgYICQAAAA==.Rockmoninov:BAAALAADCgQIBAAAAA==.Roglof:BAAALAAECggICwAAAA==.Rowlah:BAAALAADCgcIBwAAAA==.Rozy:BAAALAAECgUICAAAAA==.',Ru='Ruiizu:BAAALAAECgMIBAAAAA==.',['Rä']='Räwdäwg:BAAALAADCgYICgAAAA==.',Sa='Saghira:BAAALAAECgMIAwAAAA==.Sairicck:BAAALAAECgMIBAAAAA==.Sallymander:BAAALAADCggIFAAAAA==.Samaal:BAAALAADCggICAABLAAECgQIBAABAAAAAA==.Sanaleana:BAAALAADCgYIBgAAAA==.Saoiche:BAAALAAECgMIAwAAAA==.Sarcasticus:BAAALAAECgEIAQAAAA==.Sarlaina:BAAALAADCgcIBwAAAA==.Saul:BAAALAAECgMIBAAAAA==.',Se='Seananigans:BAAALAADCgYIBgAAAA==.Sekkuar:BAAALAAECgIIAgAAAA==.Selenar:BAAALAAECgMIAwAAAA==.Selinora:BAAALAAECgYICAAAAA==.',Sh='Shaolinsnake:BAAALAAECgEIAQAAAA==.Shivwork:BAAALAAECgMIAwAAAA==.Shocklesnar:BAAALAAECgEIAQABLAAECgIIBAABAAAAAA==.',Si='Sick:BAAALAADCgQIBQAAAA==.Sigil:BAAALAAECgMIAwAAAA==.',Sn='Snax:BAAALAADCgIIAgAAAA==.Sneakymanh:BAAALAAECgEIAQAAAA==.',So='Solsti:BAAALAAECgYICAAAAA==.',Sp='Spears:BAAALAADCggICAAAAA==.',Sq='Squidge:BAAALAAECgIIAwAAAA==.',St='Stormfeather:BAAALAAECgMIAwAAAA==.Strikerv:BAAALAAECgQIBgAAAA==.Strozzapreti:BAAALAAECgMIBgAAAA==.Stàrwalker:BAAALAADCggIFQAAAA==.',Su='Suguru:BAAALAAECgQIBAAAAA==.Sunman:BAAALAAECgMIBAAAAA==.Sushi:BAAALAAECgIIBAAAAA==.',Sv='Sven:BAAALAAECgEIAQAAAA==.',Sw='Swifty:BAAALAAECgMIBAAAAA==.',Sy='Sylinsor:BAAALAADCgYICQAAAA==.Symor:BAAALAADCgYIBgAAAA==.',Ta='Talin:BAAALAAECgMIBwAAAA==.Tanarel:BAAALAADCgYIBwAAAA==.Taryen:BAAALAAECgMIAwAAAA==.',Te='Telaari:BAAALAADCgcIDgABLAAECgMIAwABAAAAAA==.',Th='Thalenia:BAAALAAECgYICwAAAA==.Thekingdom:BAAALAAECgUIBQAAAA==.',Ti='Tikeidari:BAAALAAECgMIBAAAAA==.',To='Torogrande:BAAALAADCgYICQAAAA==.Toutii:BAAALAADCggICAAAAA==.',Tr='Trappythirst:BAAALAAECgIIAgAAAA==.Trolkin:BAAALAADCgcIBwAAAA==.Truximus:BAAALAADCgYIBgAAAA==.',Ty='Tyranis:BAAALAADCggIEAAAAA==.',Um='Umbrael:BAAALAADCgYICQAAAA==.',Va='Valeira:BAABLAAECoEVAAMDAAgILR77BwCqAgADAAgILR77BwCqAgAEAAII3AwnEwBvAAAAAA==.Varek:BAAALAADCgMIAwABLAADCgYIBgABAAAAAA==.Varleara:BAAALAADCggICgAAAA==.',Vd='Vdüb:BAAALAAECgIIAgAAAA==.',Ve='Ventana:BAAALAAECgEIAQAAAA==.Verdilac:BAAALAAECgMIAwAAAA==.',Vi='Vinceglortho:BAAALAADCgIIBAAAAA==.',Vu='Vuhdoo:BAAALAADCgIIAgAAAA==.Vulfryia:BAAALAADCgMIBQAAAA==.',Vy='Vyranoth:BAAALAAECgYICwAAAA==.Vyronika:BAAALAAECgQIBAAAAA==.',Wa='Wanji:BAAALAAECgEIAQAAAA==.',Wi='Widdle:BAAALAAECgIIAgAAAA==.Wigsplitter:BAAALAAECgMIBAAAAA==.Windborne:BAAALAAECgMIAwAAAA==.Wintyr:BAAALAADCgYICQAAAA==.',Wr='Wraithbane:BAAALAADCggICAAAAA==.',Wy='Wytewytch:BAAALAADCgYIBgAAAA==.',Xa='Xalsfootmat:BAAALAAECgMIBQAAAA==.',Xe='Xeranon:BAAALAADCggIFAAAAA==.',Xi='Xifan:BAAALAADCggICQAAAA==.Xiva:BAAALAADCggIEgAAAA==.',Xt='Xtayse:BAAALAAECgIIBAAAAA==.',Yo='Yoruechi:BAAALAAECgYICwAAAA==.',['Yú']='Yúmyúm:BAAALAADCgYIBgAAAA==.',Za='Zahel:BAAALAAECgYIBwAAAA==.',Ze='Zelli:BAAALAADCgUIBQAAAA==.Zeneri:BAAALAAECgYICAAAAA==.Zenpaws:BAAALAADCgMIAwAAAA==.',Zi='Zimster:BAAALAADCgUIBQAAAA==.',Zo='Zobi:BAAALAADCgYICQAAAA==.Zomboo:BAAALAAECgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end