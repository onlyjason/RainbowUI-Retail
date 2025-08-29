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
 local lookup = {'Unknown-Unknown','Shaman-Restoration','Monk-Windwalker','Paladin-Retribution','Druid-Guardian','Paladin-Holy','Warlock-Demonology','Hunter-BeastMastery','DemonHunter-Havoc','Shaman-Elemental',}; local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Aciddrop:BAAALAADCgQIBAAAAA==.Acinas:BAAALAAECgMIBAAAAA==.Acolyne:BAAALAADCggIDwAAAA==.',Ad='Adonijah:BAAALAAECgIIAgAAAA==.',Ae='Aelaravia:BAAALAADCgEIAQAAAA==.',Ag='Agathair:BAAALAADCggIDAAAAA==.',Ah='Ahkt:BAAALAADCgIIAgAAAA==.',Ai='Airundies:BAAALAAECgcIDwAAAA==.',Ak='Akoris:BAAALAADCgUIBQAAAA==.Akorlos:BAAALAADCgYIBgAAAA==.Akorys:BAAALAAECgYIDAAAAA==.',Al='Alandrodil:BAAALAAECgEIAQABLAAECgcIEQABAAAAAA==.Allauria:BAAALAAECgYIBgAAAA==.Allystra:BAAALAAECgMIBQABLAAECgYICQABAAAAAA==.Almansur:BAAALAADCgIIAgAAAA==.Altnumberten:BAAALAAECgMIAwAAAA==.',An='Anwir:BAAALAAECgMIAwAAAA==.',Ap='Apollyon:BAAALAAFFAEIAQAAAA==.',Aq='Aquua:BAAALAAECgYIDgAAAA==.',Ar='Archangel:BAAALAAECgEIAQAAAA==.Arcticdps:BAAALAAECgIIAgAAAA==.Ardirn:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Ariell:BAAALAAECgQIBAAAAA==.Ariiel:BAAALAADCggIDgABLAAECgQIBAABAAAAAA==.Arinath:BAAALAAECgcIEQAAAA==.Arlind:BAAALAAECgYIBgAAAA==.Arlotrec:BAAALAADCgUIBQAAAA==.Arnid:BAAALAADCgcICQAAAA==.Arotilles:BAAALAADCggICAAAAA==.Arthuritucus:BAAALAADCgcIDQAAAA==.',As='Ashlose:BAAALAADCgcICwAAAA==.Ashuryn:BAAALAAECggIBQAAAA==.Aspenoa:BAAALAADCgcICgAAAA==.',Au='Augmen:BAAALAADCgYIBwAAAA==.Augmet:BAAALAADCgIIAgAAAA==.Augmeth:BAAALAADCgQIBAAAAA==.',Av='Avex:BAAALAAECgQIBgAAAA==.',Aw='Awengaa:BAAALAADCgMIAwAAAA==.',Ax='Axemage:BAAALAAECgYIDQAAAA==.',Az='Azzrael:BAAALAAECggIEgAAAA==.',Ba='Baelfang:BAAALAADCgYIBgAAAA==.Baelfeng:BAAALAADCgcIDAAAAA==.Bahgeye:BAAALAADCgUIBQAAAA==.Bajaladin:BAAALAADCgQIBwAAAA==.Balikbayan:BAAALAAECgMIAwAAAA==.Ballonknot:BAAALAADCgIIAwABLAAECgYIBwABAAAAAA==.Bancko:BAAALAADCgEIAQAAAA==.Barryallen:BAAALAAECgMIBgAAAA==.Bast:BAAALAADCgUIBQABLAAECgYICQABAAAAAA==.',Be='Belithdora:BAAALAADCgcICwAAAA==.Belladin:BAAALAADCggIDgAAAA==.Benwins:BAAALAADCggIDwAAAA==.Besus:BAAALAADCgcICgAAAA==.',Bi='Bigoltotems:BAAALAAECgYICQAAAA==.Billblowbagg:BAAALAAECgEIAgAAAA==.Billiams:BAAALAADCgMIAgAAAA==.Bis:BAAALAADCgIIAgABLAADCgcICgABAAAAAA==.Bisholoyd:BAAALAAECgMIBQAAAA==.',Bl='Blastoise:BAAALAAECgYIDQAAAA==.Blazakin:BAAALAADCgUICAAAAA==.Bllur:BAABLAAECoEVAAICAAgIgh1iCACJAgACAAgIgh1iCACJAgAAAA==.Bloodwitness:BAAALAADCgMIAwABLAADCggIEAABAAAAAA==.Bloodwrath:BAAALAADCggIDgAAAA==.Blunocturne:BAAALAADCgcICwAAAA==.',Bo='Booktok:BAAALAADCggICwAAAA==.Boomhauerr:BAAALAAECgYICQAAAA==.',Br='Bracydaboss:BAAALAADCgcIBwAAAA==.Brelm:BAAALAADCgMIAwAAAA==.Brenbreathe:BAAALAAECgYIBgAAAA==.Brickinkeys:BAAALAAECgIIBAAAAA==.',['Bà']='Bàne:BAAALAADCggIEAAAAA==.',Ca='Caenarigos:BAAALAAECgYICQAAAA==.Caenarius:BAAALAADCgUIBgABLAAECgYICQABAAAAAA==.Calenashbury:BAAALAADCgcIBwAAAA==.Candez:BAAALAAECgYIBwAAAA==.Card:BAAALAADCggIDAABLAAECgYIBgABAAAAAA==.Cariene:BAAALAADCgQIBAAAAA==.Carnyy:BAAALAAECgcIEAAAAA==.Catalope:BAAALAAECggIBAAAAA==.',Ce='Celestara:BAAALAAECgIIAgAAAA==.Celornis:BAAALAAECgEIAQAAAA==.',Ch='Chameleos:BAAALAADCggIGAAAAA==.Chimubai:BAAALAAECgEIAQAAAA==.',Ci='Circeshadows:BAAALAADCgYICgAAAA==.Circusfreak:BAAALAAECgIIAwAAAA==.',Cl='Cloacajones:BAAALAAECgYIDgAAAA==.Clohhe:BAAALAADCgcIEAAAAA==.Clwnshoenrgy:BAAALAADCggICAAAAA==.',Co='Consecrated:BAAALAADCggICAAAAA==.Constatine:BAAALAADCgcICgAAAA==.',Cr='Cremesodax:BAAALAAECgEIAwAAAA==.Critnyspears:BAAALAAECgMIBwAAAA==.Crownnova:BAAALAADCggICAAAAA==.Cryomortis:BAAALAADCggIBAAAAA==.',Cu='Custodeus:BAAALAADCggICwAAAA==.',Cy='Cynsia:BAAALAADCgcIEwAAAA==.',Da='Daemonpope:BAAALAADCggIFgAAAA==.Dallthyrian:BAABLAAECoEVAAIDAAcIqxxjCQApAgADAAcIqxxjCQApAgAAAA==.Damsey:BAAALAADCgEIAQAAAA==.Dargonbref:BAAALAADCggIEAAAAA==.Darkkhaos:BAAALAAECgYICQAAAA==.Darkklion:BAAALAADCgcIBwAAAA==.Darkndspooky:BAAALAADCgIIAgAAAA==.Darkselenite:BAAALAAECgIIBAAAAA==.Darkshock:BAAALAADCgMIAwAAAA==.Darlough:BAAALAAECgMIBQAAAA==.Dasblur:BAAALAADCggIDQAAAA==.Dathingz:BAAALAADCgcICwAAAA==.',De='Deathly:BAAALAAECgIIAgAAAA==.Deathstone:BAAALAAECgYICQABLAAECgcIFQAEAMAhAA==.Deathtress:BAAALAADCggIFgAAAA==.Decado:BAAALAAECgYICQAAAA==.Degen:BAAALAADCgMIAwAAAA==.Demish:BAAALAAECgYICAAAAA==.Demonae:BAAALAAECgYIDQAAAA==.Demoncas:BAAALAADCgIIAgAAAA==.Demondrodil:BAAALAAECgcIEQAAAA==.Demontime:BAAALAAECgQIBQAAAA==.Denimbeard:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.Denimdan:BAAALAAECgYICQAAAA==.Derferk:BAAALAADCgcIDQAAAA==.Dergie:BAAALAADCgQIBAAAAA==.Dergiesmalls:BAAALAADCgcIBwAAAA==.',Di='Dirtyflewids:BAAALAAECgcIEQAAAA==.Discer:BAAALAADCggIBwAAAA==.Discibren:BAAALAAECgEIAQAAAA==.Disdain:BAAALAADCgcICQAAAA==.',Dj='Djkin:BAAALAADCgcIDQAAAA==.',Dk='Dkalliru:BAAALAAECgYIDgAAAA==.',Do='Docdolittle:BAAALAAECgQIBgAAAA==.Docfreez:BAAALAAECgYICQAAAA==.Docrighteous:BAAALAADCgcIBwABLAAECgQIBgABAAAAAA==.Doomhamer:BAAALAAECgYIDgAAAA==.Dorissia:BAAALAAECgEIAQAAAA==.Doublepull:BAAALAAECgUICAAAAA==.Doufeellucky:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.',Dr='Dracthrus:BAAALAADCgIIAgAAAA==.Drbaobuns:BAAALAAECgMIBgABLAAECgYIDAABAAAAAA==.Drfishtacos:BAAALAAECgQIBAABLAAECgYIDAABAAAAAA==.Drgatorwine:BAAALAADCgEIAQABLAAECgYIDAABAAAAAA==.Drjvck:BAAALAADCgQICgAAAA==.Drkimchirice:BAAALAAECgYICQABLAAECgYIDAABAAAAAA==.Drlocktapus:BAAALAAECgYICgAAAA==.Drmacncheese:BAAALAAECgMIBQABLAAECgYIDAABAAAAAA==.Drpumpkinpie:BAAALAADCgQIBAABLAAECgYIDAABAAAAAA==.Drtatersalad:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Druidussy:BAAALAADCggICAAAAA==.Drwontonsoup:BAAALAAECgYIDAAAAA==.',Du='Duiunit:BAAALAADCgcICAAAAA==.Dumblìedore:BAAALAADCggIDAAAAA==.Dumpstur:BAAALAADCgMIAwAAAA==.Dune:BAAALAADCgIIBwAAAA==.',['Dä']='Därkseid:BAAALAADCgcICAAAAA==.',Ea='Easyy:BAAALAAECgYICgAAAA==.',Eb='Ebolabeef:BAAALAADCgUIBQABLAAECgUIBQABAAAAAA==.',Ei='Eighteen:BAAALAADCgcIDQAAAA==.',Ek='Eksi:BAAALAAECgYIBgAAAA==.',El='Elementalone:BAAALAAECgUIBAAAAA==.Elftastic:BAAALAAECgYICQAAAA==.Elidron:BAAALAADCgMIAwABLAADCgYIBgABAAAAAA==.Eljonny:BAAALAADCgcIBwAAAA==.Eloreyalan:BAAALAADCgMIAwAAAA==.',Em='Embedded:BAAALAADCggICwABLAADCggIEAABAAAAAA==.',En='Envyschunk:BAAALAADCggIHAAAAA==.',Er='Erevora:BAAALAADCggIDAAAAA==.',Es='Escoez:BAAALAADCgMIAwAAAA==.',Et='Etherwing:BAAALAAECgUIBQAAAA==.',Ex='Excruciator:BAAALAAECgcIDQAAAA==.',Ez='Ezfran:BAEALAADCgIIAgAAAA==.',Fa='Fallandor:BAAALAADCgMIAwABLAADCgUIBQABAAAAAA==.Falloutz:BAAALAADCggIFwAAAA==.Farrock:BAAALAAECgQICQAAAA==.Fawxette:BAAALAAECgYICQAAAA==.',Fe='Febriss:BAAALAADCgUIBQAAAA==.Felonnius:BAAALAADCgcIDAAAAA==.Ferallock:BAAALAAECgQIBAAAAA==.',Fi='Filledegel:BAAALAAECgEIAQAAAA==.Finowscath:BAAALAAECggICwAAAA==.Fistdoc:BAAALAAECgMIBAAAAA==.Fizzlesaurus:BAAALAAECgEIAQAAAA==.',Fl='Flasky:BAAALAAECgYIDAAAAA==.',Fo='Foomonchue:BAAALAADCgcIBwAAAA==.',Fr='Freezide:BAAALAAECgIIAgAAAA==.',Fu='Fullerir:BAAALAADCggIEgAAAA==.Fuzzycoochy:BAAALAAECgYICQAAAA==.Fuzzylock:BAAALAADCgUIBQAAAA==.',Fy='Fynslane:BAAALAAECgMIBAAAAA==.',Ga='Galahadsend:BAAALAAECgMIAwAAAA==.Garrin:BAAALAADCgQIBQAAAA==.',Ge='Getbehindhim:BAAALAAECgQICgAAAA==.',Gh='Ghostreveri:BAAALAAECgYIDAAAAA==.',Gi='Gigah:BAAALAAECgYIBwAAAA==.Gildin:BAAALAAECgcIDgAAAA==.Giox:BAAALAADCgYIBgAAAA==.',Gl='Glía:BAAALAAECgYICAAAAA==.',Gn='Gnomedguerre:BAAALAADCgQIBAAAAA==.',Go='Goatstatik:BAAALAADCggIDgAAAA==.Goom:BAAALAADCgQIBAAAAA==.Goosejaw:BAAALAADCgUIBQAAAA==.Gordopelotas:BAAALAADCgIIAQAAAA==.Gorelockk:BAAALAADCgcIDAAAAA==.Gorgamish:BAAALAADCggIBwAAAA==.',Gr='Grahka:BAAALAADCgMIBQAAAA==.Grayseer:BAAALAAECgcIEQAAAA==.Greeningout:BAAALAADCgQIBAAAAA==.Greybeast:BAAALAADCgQIBwABLAADCggIFwABAAAAAA==.Grimwizard:BAAALAAECggIEAAAAA==.Grizmak:BAAALAADCgYIBgAAAA==.Grizzink:BAAALAADCggICAAAAA==.Grumpstraza:BAAALAAECgIIAgAAAA==.Grumpydemon:BAAALAAECgYICgAAAA==.',Gu='Gula:BAAALAADCgcIBwAAAA==.Guldurax:BAAALAADCggIBwAAAA==.',Gw='Gwonk:BAAALAADCggIDAAAAA==.',Ha='Hakkai:BAAALAAECgYIBgAAAA==.Halvorse:BAAALAADCggIDQAAAA==.Harryhoudini:BAAALAAECgIIAgAAAA==.Hashaa:BAAALAAECgEIAgAAAA==.',He='Headdie:BAAALAADCggIDQAAAA==.Healingyou:BAAALAADCgcIBwABLAAECgYIFQAFADMgAA==.Healsgobrr:BAABLAAECoEUAAIGAAgIDBFxCwAOAgAGAAgIDBFxCwAOAgAAAA==.Healsorus:BAAALAADCgQIBAABLAAECggIDwABAAAAAA==.Helldealer:BAAALAADCgcIDQAAAA==.Heraclez:BAAALAAECggIBgAAAA==.Hercumore:BAAALAADCgMIAwAAAA==.Hesha:BAAALAAECgMIBAAAAA==.Hexlexxia:BAAALAADCgMIAwABLAAECgIIBAABAAAAAA==.',Hi='Histaint:BAABLAAECoESAAIHAAgIkho8AwBHAgAHAAgIkho8AwBHAgAAAA==.',Ho='Holysock:BAAALAADCggIDwAAAA==.Hornhunter:BAAALAADCgYIBgAAAA==.',Hu='Huch:BAAALAADCggIEAAAAA==.Hugoman:BAAALAAECgYICQAAAA==.Huni:BAAALAAECgcIDQAAAA==.',Hy='Hydealyn:BAAALAAECgYIBgAAAA==.',Ib='Ibufen:BAAALAADCgcIBwAAAA==.',Ic='Iceburnes:BAAALAADCgUIBwAAAA==.',Il='Ilineda:BAAALAAECgIIBAAAAA==.Illsmiteu:BAAALAADCggICAAAAA==.',Im='Imdragginazz:BAAALAADCgMIAwAAAA==.Imelectric:BAAALAADCgcIDAAAAA==.Imunchies:BAAALAADCggIDQAAAA==.Imwithstupid:BAAALAADCggIBwAAAA==.',In='Inthrel:BAAALAADCgUIBQAAAA==.',Ir='Irinashidou:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.Iriolarthas:BAAALAAECgMIAwAAAA==.Irodina:BAAALAADCggIEQAAAA==.',It='Itsmechillyp:BAAALAADCgMIAwAAAA==.',Je='Jediobiwon:BAAALAADCgQIBQAAAA==.Jeffrèy:BAAALAADCgUIBQAAAA==.Jettchi:BAAALAADCgUIBQABLAAECgYICgABAAAAAA==.',Ji='Jinox:BAAALAADCggIEAAAAA==.',Jl='Jlmanlg:BAAALAAECggICAAAAA==.',Jo='Jonesey:BAABLAAECoEVAAIFAAYIMyCnAgAPAgAFAAYIMyCnAgAPAgAAAA==.Joneseyy:BAAALAAECgYIBgABLAAECgYIFQAFADMgAA==.Joreion:BAAALAAECgcIDgAAAA==.',Jr='Jracó:BAAALAAECggIBQAAAA==.',Ju='Juliettestar:BAAALAADCgYIAQAAAA==.Junglemoon:BAAALAADCgQIBgAAAA==.Justiz:BAAALAADCgcICgAAAA==.Juststitch:BAAALAADCggICAAAAA==.',Ka='Kalliie:BAAALAAECgMIAwAAAA==.Kalrendion:BAAALAADCgcIDAABLAADCggIDwABAAAAAA==.Kalru:BAAALAAECgIIAgAAAA==.Karasu:BAAALAADCggIGAAAAA==.Kartazain:BAAALAAECgMIAwAAAA==.Kath:BAAALAADCgEIAQAAAA==.Kaylith:BAAALAADCgcIDQAAAA==.',Ke='Keyaiedis:BAAALAAECgEIAQAAAA==.',Kh='Khaosstormz:BAAALAADCgcICAABLAAECgYICQABAAAAAA==.Khorrin:BAAALAADCgEIAQAAAA==.',Ki='Killians:BAAALAADCgcIBwAAAA==.Kiritical:BAAALAADCgMIAwAAAA==.Kitak:BAAALAADCggIDwAAAA==.Kitchenbôund:BAAALAAECgEIAQAAAA==.',Ko='Koragh:BAAALAADCggIDwAAAA==.Korris:BAAALAAECgEIAQAAAA==.Korvin:BAAALAADCgYIDAAAAA==.Koudelka:BAAALAAECgYICQAAAA==.Kozyrov:BAAALAAECgIIAgAAAA==.',Kr='Krianan:BAAALAAECgYIDAAAAA==.Krisana:BAAALAADCgUIBQAAAA==.Krustym:BAAALAADCgUIBQAAAA==.',Kw='Kwothe:BAAALAAECgIIBAAAAA==.',Ky='Kynlass:BAAALAADCgcIBwAAAA==.',['Kö']='Körris:BAAALAADCgcIBwAAAA==.',La='Ladron:BAAALAADCgcICgAAAA==.Laeina:BAAALAAECgYIDgAAAA==.Lakshmi:BAAALAADCgcIBwABLAAECgIIBAABAAAAAA==.Lassaris:BAAALAADCgMIBQAAAA==.',Le='Lelou:BAAALAAFFAIIAgAAAA==.',Lf='Lfrith:BAAALAAECgQIBwAAAA==.',Li='Lilathiaa:BAAALAAECgMIBQAAAA==.Liondori:BAAALAAFFAIIAgAAAA==.Lirisa:BAAALAADCgcIBwAAAA==.',Lm='Lmj:BAAALAAECgIIAgAAAA==.',Lo='Lockngood:BAAALAADCgcIDAAAAA==.Lockstarz:BAAALAAECgMIAwAAAA==.Loikclaws:BAAALAAECgEIAQAAAA==.',Lu='Luckyliandra:BAAALAADCgQIBAAAAA==.Lukrid:BAAALAADCgcIBwAAAA==.Luroria:BAAALAADCgIIAgAAAA==.Luteilnarn:BAAALAAECgIIAgAAAA==.',Ma='Maelmael:BAAALAAECgMIBQAAAA==.Magoombie:BAAALAADCgcIEgAAAA==.Malthoryn:BAAALAAECggIAwAAAA==.Mamamercy:BAAALAAECgEIAQAAAA==.Mamisiopao:BAAALAADCgYIBgAAAA==.Manaflare:BAAALAADCggIFgAAAA==.Mantle:BAAALAADCgUIBQAAAA==.Maraverly:BAAALAAECgYIBwAAAA==.Maudib:BAAALAADCgQIBgAAAA==.',Me='Meenister:BAAALAAECgEIAQAAAA==.Mellomei:BAAALAAECgIIAgABLAAECgYIEAABAAAAAA==.Mellomeii:BAAALAAECgYIEAAAAA==.Mellomeimei:BAAALAADCggICgABLAAECgYIEAABAAAAAA==.Meowmeowhit:BAAALAADCgEIAQAAAA==.Merope:BAAALAADCggICAAAAA==.Merxi:BAAALAADCgYIBgAAAA==.Metaslave:BAAALAADCggICgAAAA==.',Mh='Mheow:BAAALAADCggIDgAAAA==.',Mi='Midnightsham:BAAALAADCgcIBwAAAA==.Midnightsun:BAAALAADCgYIBgAAAA==.Mitufu:BAAALAAECgEIAQAAAA==.',Mo='Moffix:BAAALAADCgYIBgAAAA==.Mogg:BAAALAAECgUIBQAAAA==.Mojorisin:BAAALAADCgYIBgAAAA==.Mom:BAAALAAECgYICwAAAA==.Momie:BAAALAADCgcIBwAAAA==.Monkeyddrago:BAAALAAECgcIDwAAAA==.Moonrunes:BAAALAADCgcIBwAAAA==.Morcruach:BAAALAADCgcIEgAAAA==.Morgañya:BAAALAAECgUICAABLAAECgYICQABAAAAAA==.',Mu='Mufassa:BAAALAADCggICAAAAA==.',Na='Naliste:BAAALAADCgMIAwAAAA==.Nautprepared:BAAALAAECgIIAgAAAA==.',Ne='Needhealz:BAAALAAECggIDwAAAA==.Nephey:BAAALAADCgcIBwAAAA==.Nerfmonks:BAAALAAECgMIBQAAAA==.Neruse:BAAALAAECggIBwAAAA==.',Ni='Nietherme:BAAALAAECgMIBAAAAA==.Nightmun:BAAALAADCgMIAwAAAA==.Niraerk:BAAALAADCggIDwAAAA==.',Nj='Njamani:BAAALAAECgcIEAAAAA==.',No='Noblefiend:BAAALAAECgMIAwAAAA==.Nofoamlatte:BAAALAADCgcIDgABLAAECgYICQABAAAAAA==.',Nu='Nugget:BAAALAAECgcICgAAAA==.Nurspepper:BAAALAADCgcIDQAAAA==.',Ny='Nyagosa:BAAALAAECgMIAwAAAA==.Nyalore:BAAALAAECgYIDgAAAA==.',Ol='Olia:BAAALAADCgcICQAAAA==.',On='Onlyclams:BAAALAADCgYICwAAAA==.Onlyheåls:BAAALAADCgIIAgAAAA==.',Oo='Oopah:BAAALAADCgcIBgABLAAECgcIDwABAAAAAA==.',Oq='Oquaellii:BAAALAADCgcIBwAAAA==.',Or='Oralen:BAAALAAECgcIEAAAAA==.',Ov='Overloader:BAAALAAECgYIDAAAAA==.',Ow='Ownin:BAAALAAECgEIAQAAAA==.',Ox='Oxreign:BAAALAADCgEIAQAAAA==.',Pa='Paladinchan:BAAALAADCgUIBQABLAAECgYICQABAAAAAA==.Pallygank:BAAALAAECgUIBgAAAA==.Panxita:BAAALAAECgMIBQAAAA==.Parvatii:BAAALAADCgUIBQAAAA==.',Pe='Peruano:BAAALAAECgYICgAAAA==.',Ph='Phewphew:BAAALAAECgIIAwAAAA==.',Pi='Pietastegood:BAAALAAECgYIDwAAAA==.Pinkpwnage:BAAALAAECgQIBQAAAA==.Pitchblack:BAAALAADCggIDQAAAA==.',Pl='Plobs:BAAALAAECgcICQAAAA==.',Po='Poordemon:BAAALAADCgQIBAAAAA==.Popelin:BAAALAAECgEIAQAAAA==.',Pr='Privo:BAAALAAECgcIBwAAAA==.',Ps='Psickem:BAAALAADCgYIBgAAAA==.Psilycube:BAAALAAECgEIAQAAAA==.',Pu='Puffthemagic:BAAALAADCgUIBQABLAAECgYIDQABAAAAAA==.Pukguksong:BAAALAADCgcICgAAAA==.',Py='Pyreliice:BAAALAADCgUIBQAAAA==.',Ra='Raendarth:BAAALAADCggIEAAAAA==.Rageclaw:BAEALAAECgMIBAAAAA==.Ragecypher:BAAALAADCgYIBwAAAA==.Rakath:BAAALAAECgMIAwAAAA==.Rakrak:BAAALAADCgcICAABLAAECgcIEQABAAAAAA==.Ramchi:BAAALAAECgIIAgAAAA==.Ramknight:BAAALAADCggIDwAAAA==.',Re='Reck:BAAALAAECgYIDQAAAA==.Redericc:BAAALAADCgYIBgAAAA==.Redharvest:BAAALAAECgYICAAAAA==.Redrangerzz:BAAALAADCgcIBwAAAA==.Redrocket:BAAALAADCgYIBgAAAA==.Redwolf:BAAALAADCggICAAAAA==.Rejuve:BAAALAADCgYIBgAAAA==.Renwick:BAAALAADCggIEAAAAA==.Retàsa:BAAALAAECgEIAQAAAA==.Reverie:BAAALAAECgQIBQAAAA==.Revvy:BAAALAAECgIIAgAAAA==.',Rh='Rhabarberbar:BAAALAAECgEIAQABLAAECgYIDwABAAAAAA==.',Ri='Riasg:BAAALAAECgcIDQAAAA==.Rikoe:BAAALAAECgQIBQAAAA==.',Ro='Rohirpriest:BAAALAADCgMIAwAAAA==.Rosannas:BAAALAAECgcIEAAAAA==.Rosepoiso:BAAALAAECgEIAQAAAA==.Royål:BAAALAADCggICAAAAA==.',Ru='Ruibash:BAAALAAECgIIBgAAAA==.Runè:BAAALAADCgMIAwAAAA==.',['Rí']='Ríce:BAAALAADCggICAAAAA==.',Sa='Sagittarrix:BAAALAADCggIEAAAAA==.Sandenis:BAAALAADCggIDwAAAA==.Sanothen:BAAALAADCgcIBwAAAA==.',Sc='Scaledoc:BAAALAAECgIIBAABLAAECgMIBAABAAAAAA==.Scallywagg:BAAALAAECgMIBQAAAA==.Schmedium:BAAALAADCggICQAAAA==.Scrimz:BAAALAADCggICAAAAA==.',Se='Searcomic:BAAALAADCgIIAwAAAA==.Seasalt:BAAALAADCgcIBwAAAA==.Seldav:BAAALAAECgMIAwABLAAECggIFAAGAAwRAA==.Selm:BAAALAAECgYICQAAAA==.Sendorin:BAAALAADCggICAAAAA==.Session:BAAALAADCggICwAAAA==.',Sh='Shadowrelive:BAAALAADCgQIBAAAAA==.Shaluesta:BAAALAADCgcIDAAAAA==.Sharco:BAAALAAECgMIBAAAAA==.Sherrizzahh:BAAALAADCgYIDAAAAA==.Shieldyaass:BAAALAADCggICAAAAA==.Shinobin:BAAALAADCggICAAAAA==.Shinshots:BAAALAADCggIEAAAAA==.Shion:BAAALAADCggIDAAAAA==.Shizdin:BAAALAADCggICAAAAA==.Shooshmael:BAAALAAECgIIAgABLAAECgMIBQABAAAAAA==.Shujaa:BAAALAAECgMIAwAAAA==.Shush:BAAALAADCggICAAAAA==.Shékinah:BAAALAAECgEIAQAAAA==.',Si='Sigrdrífa:BAAALAADCgQIBAABLAAECgEIAQABAAAAAA==.Silentia:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Sinaer:BAAALAADCggICAAAAA==.Sindrea:BAAALAADCggIDgAAAA==.Sinthein:BAAALAADCgUIBQAAAA==.Sipala:BAAALAADCgEIAQAAAA==.',Sk='Skadhen:BAAALAAECgYIBwAAAA==.Skeleten:BAAALAAECgcIDwAAAA==.Skillstormin:BAAALAADCgcIDAAAAA==.Skolgi:BAAALAADCgIIAgAAAA==.',Sl='Sloppyspikes:BAAALAADCggIDwAAAA==.',Sm='Smidgenn:BAAALAADCgMIAwAAAA==.',Sn='Snailtrailin:BAAALAAECgEIAQAAAA==.',So='Sokar:BAAALAADCgYIBgAAAA==.Solstara:BAAALAAECgEIAQAAAA==.Sotan:BAAALAAECgYICgAAAA==.Soulforge:BAAALAADCggICAAAAA==.',Sp='Sparowprince:BAABLAAECoEVAAIEAAcIwCGVEACEAgAEAAcIwCGVEACEAgAAAA==.Spilled:BAAALAAECgYIBgAAAA==.Splashu:BAAALAADCgQIBgAAAA==.',St='Stabfaces:BAAALAADCgcIBwAAAA==.Steakprime:BAAALAADCggICAAAAA==.Steelreserve:BAAALAADCgMIAwAAAA==.Steezya:BAAALAAECgEIAQAAAA==.Stiern:BAAALAADCgcIBwAAAA==.Stinkerfart:BAAALAAECgcIDQAAAA==.Stonestrasz:BAAALAADCgYIBgABLAAECgcIFQAEAMAhAA==.Stormykitty:BAAALAAECgEIAQAAAA==.Stormyriver:BAAALAAECgMIBQAAAA==.Sturtza:BAAALAAECggIEgAAAA==.',Ta='Talarrus:BAAALAADCgUIBQAAAA==.Taleigha:BAAALAAECgMIBwAAAA==.Talisaie:BAAALAAECgYIDwAAAA==.Taron:BAAALAADCggIEAAAAA==.',Te='Tenshichan:BAAALAADCgUIBgABLAAECgYICQABAAAAAA==.',Th='Thehandaxe:BAAALAAECgEIAQAAAA==.Thehumanatee:BAAALAAECgUIBgAAAA==.Thingytoo:BAAALAADCgcICgAAAA==.Threes:BAAALAADCgcICgAAAA==.Thryn:BAAALAADCggIDQAAAA==.',Ti='Tilted:BAAALAAECgMIBgAAAA==.',To='Topp:BAAALAADCggIDgAAAA==.Totemstitch:BAAALAAECgYIDAAAAA==.',Tr='Treadria:BAAALAADCggICAAAAA==.Treemage:BAAALAAECgcICAAAAA==.Treloot:BAAALAADCggIDAAAAA==.',Tu='Tums:BAAALAAECgYIDAAAAA==.Tumsdimorte:BAAALAADCggICgABLAAECgYIDAABAAAAAA==.Turkatron:BAAALAAECgEIAQAAAA==.',Tw='Twixy:BAAALAAECgUIBgAAAA==.',Ty='Tylenill:BAAALAAECgUICQAAAA==.',['Tì']='Tìlted:BAABLAAECoEZAAIIAAgIzCMrAwA8AwAIAAgIzCMrAwA8AwAAAA==.',Un='Untoro:BAAALAAECgUIEAAAAA==.',Ur='Ursoman:BAAALAAECgMIAwAAAA==.',Uz='Uzainbolt:BAAALAADCggICQAAAA==.',Va='Valkyrin:BAAALAADCgYIBQAAAA==.Valvalon:BAAALAAECgYICAAAAA==.Valëria:BAAALAAECgMIAwAAAA==.Vannin:BAAALAADCggIEwAAAA==.Vartik:BAAALAADCggIEAAAAA==.',Ve='Veelaria:BAAALAAECgIIAwAAAA==.Veldez:BAAALAAECgEIAQAAAA==.Veledaa:BAAALAADCgUIBQABLAAECgIIBAABAAAAAA==.Velinddrel:BAAALAADCgYIBgAAAA==.Velocity:BAAALAADCggICAAAAA==.Veravulp:BAAALAADCgcIFQAAAA==.Verisa:BAAALAADCgcIDgAAAA==.',Vi='Vicalaus:BAAALAAECgUIDAAAAA==.View:BAAALAADCggIDgAAAA==.Viito:BAAALAADCgEIAQAAAA==.Vikki:BAAALAADCggICAAAAA==.Vivne:BAAALAADCggICAABLAADCggICAABAAAAAA==.',Vo='Vogmudet:BAAALAADCgQIBQAAAA==.Voidwitch:BAAALAAECgIIBAAAAA==.Volcanicx:BAAALAADCggIDAAAAA==.Volstagg:BAAALAAECgEIAQAAAA==.',Vu='Vulra:BAAALAADCggIDgAAAA==.',Wa='Wahmyshammy:BAAALAADCgcIBwAAAA==.',We='Webbfury:BAAALAAECgYIBwAAAA==.Weirdjulian:BAAALAADCgYIBgAAAA==.Wetpug:BAAALAADCgcIBwAAAA==.',Wh='Whompwhomp:BAAALAADCgIIAgAAAA==.Whupitup:BAAALAADCgcIBwAAAA==.',Wi='Wickedcream:BAAALAADCggICAAAAA==.Wiidge:BAAALAAECgQIBgAAAA==.Wiinkk:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.Wikd:BAAALAADCgIIAgAAAA==.Wildretnuh:BAABLAAECoEXAAIJAAgIyBujDwCVAgAJAAgIyBujDwCVAgAAAA==.Windiwithani:BAAALAAECgMIAwAAAA==.Winifred:BAAALAADCgcIBwAAAA==.',Wo='Worgath:BAAALAADCggIFgAAAA==.Worldcrafter:BAAALAAECggIDAAAAA==.Worldender:BAAALAADCggICAAAAA==.',Ww='Wwiink:BAAALAADCgcIBwAAAA==.',Xa='Xantry:BAABLAAECoEZAAIEAAgIVCWqAgBcAwAEAAgIVCWqAgBcAwAAAA==.',Xy='Xylean:BAAALAADCgIIAgAAAA==.',['Xê']='Xênä:BAAALAAECgcIEgABLAAECgYIDQABAAAAAA==.',Yo='Yossarian:BAAALAADCggIEQAAAA==.',Ys='Ysalune:BAAALAADCgIIAgAAAA==.',Za='Zaneth:BAAALAADCgcICAAAAA==.Zarayl:BAAALAADCgUIBQAAAA==.Zarrah:BAAALAAECgEIAQAAAA==.Zaryalin:BAAALAADCgYIBgAAAA==.',Ze='Zeddicuss:BAAALAADCggIDAAAAA==.Zendalis:BAAALAAECgMIAwAAAA==.Zenithpowerr:BAAALAADCgIIAwAAAA==.Zenjay:BAAALAADCgcIBwAAAA==.Zerrikan:BAAALAAECgIIAgAAAA==.',Zi='Zilphah:BAAALAADCgcICQAAAA==.Zimms:BAAALAAECgMIAwAAAA==.Zinoga:BAAALAAECgEIAQAAAA==.Zizzka:BAAALAADCgMIAwAAAA==.',Zu='Zubkarra:BAABLAAECoEVAAIKAAgIFh+TCADOAgAKAAgIFh+TCADOAgAAAA==.Zukcha:BAAALAADCgMIAwAAAA==.',['Zö']='Zöñster:BAAALAADCgYIBgAAAA==.',['Zø']='Zøhan:BAAALAADCgQIBAAAAA==.',['Äl']='Älcatraz:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end