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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Mage-Frost','Mage-Arcane','Priest-Shadow','Hunter-Marksmanship','Priest-Holy','Evoker-Devastation','Hunter-BeastMastery',}; local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aassvik:BAAALAAECgMIBAAAAA==.',Ac='Achelin:BAAALAADCggIFwAAAA==.Achievless:BAAALAAECgMIBwAAAA==.Achievsome:BAAALAAECggIEgAAAA==.',Ag='Agrajag:BAAALAADCgQIBAABLAAECgYIDwABAAAAAA==.',Ai='Aither:BAAALAAECgMIBgAAAA==.',Ak='Akagrats:BAAALAADCgUICwAAAA==.Akumahunter:BAAALAADCggIBwABLAAECgMIBAABAAAAAA==.',Al='Alestar:BAAALAADCgcIBwABLAADCgcICgABAAAAAA==.Algas:BAAALAADCgcIBwAAAA==.Alixendrya:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Allimore:BAAALAAECgYIBgAAAA==.',Am='Amethestraz:BAAALAAECgcIDwAAAA==.Amzplox:BAAALAADCgEIAQAAAA==.',An='Anomander:BAAALAADCggIEAAAAA==.Anowon:BAAALAAECggIAQAAAA==.',Ar='Archtrishop:BAAALAAECgMIBAAAAA==.Arghul:BAAALAAECgYIBwAAAA==.Arishok:BAAALAADCgcIBwABLAAECgcIEgABAAAAAA==.Aristae:BAAALAADCgUIBQABLAAECgQIBQABAAAAAA==.Aristodemos:BAAALAADCgcIBwAAAA==.Arkanis:BAAALAAECgMIBgAAAA==.Arkeid:BAAALAADCgUIBgAAAA==.Arrolexancas:BAAALAAECgMIBQAAAA==.Artemissnow:BAAALAADCggIFwAAAA==.Arzuul:BAAALAAECgMIBAAAAA==.',As='Ashlynaa:BAAALAAECgYICgAAAA==.Ashmaker:BAAALAAECgIIAgAAAA==.Ashrad:BAAALAAECgUIBQAAAA==.',Av='Avinoch:BAAALAAECgIIAgAAAA==.',Ax='Axon:BAAALAADCggIEQAAAA==.',Az='Azaliene:BAAALAADCgYICwAAAA==.Azenroth:BAAALAADCggIDgAAAA==.Azules:BAAALAADCggICwAAAA==.Azureth:BAAALAADCgMIAwAAAA==.',Ba='Bakimono:BAAALAADCgQIBAAAAA==.Bastoo:BAAALAADCgcICgAAAA==.Bastoosebata:BAAALAADCgYIDwAAAA==.Bathjuice:BAAALAAECgQIBQAAAA==.Bathtub:BAAALAADCggIDgAAAA==.',Be='Beardicuss:BAAALAADCgUIBQAAAA==.Beauxjingles:BAAALAADCgYIBgAAAA==.Beezlebumon:BAAALAADCggIEwAAAA==.Beld:BAAALAADCgcICgAAAA==.Bellasaer:BAAALAAECgYIBwAAAA==.Benk:BAAALAADCgUIBQAAAA==.Bewbkin:BAAALAADCgEIAQABLAAECggIEgABAAAAAA==.',Bl='Blazingangel:BAAALAAECgIIAgAAAA==.Bliszttasheo:BAABLAAECoEXAAICAAgIfCRYCQDoAgACAAgIfCRYCQDoAgAAAA==.Blues:BAAALAADCggICAAAAA==.',Bo='Boyland:BAAALAADCgQIBAAAAA==.',Bp='Bpbreezy:BAAALAAECggIEwAAAA==.',Br='Bradunter:BAAALAAECggIDQAAAA==.Bradwarrior:BAAALAAECgIIAgAAAA==.Bray:BAAALAAECgMIAwABLAAECggIEgABAAAAAA==.Braydrel:BAAALAAECggIEgAAAA==.Breydral:BAAALAAECgIIBAAAAA==.Bronubis:BAAALAAECggIDQAAAA==.Brorighteous:BAAALAAECgEIAgAAAA==.Brutalfist:BAAALAAECgIIBAAAAA==.',Bu='Burkisure:BAAALAADCggIEQAAAA==.',Ca='Cakeplace:BAAALAAECgMIBgAAAA==.Caliypso:BAAALAADCggIDQAAAA==.Callius:BAAALAADCggICAAAAA==.Cannibal:BAAALAAECgEIAQAAAA==.Cataster:BAAALAADCgQIBAAAAA==.',Ce='Cellineth:BAAALAAECgQIBQAAAA==.Cennyo:BAAALAADCggIDwAAAA==.',Ch='Chinkiferus:BAAALAAECgMIAwAAAA==.Chrnobog:BAAALAAECgcIEQAAAA==.',Ci='Cinderlily:BAAALAAECgIIAgAAAA==.Cirali:BAAALAADCggICAABLAAECggIIAADAAgmAA==.Cisqokid:BAAALAAECgEIAgAAAA==.Citrinemeany:BAAALAADCgcIDAABLAAECgYIEAABAAAAAA==.',Cl='Classico:BAAALAADCggICAAAAA==.Cliff:BAAALAADCgMIAwAAAA==.',Co='Colty:BAAALAADCgIIAgAAAA==.Coltystabs:BAAALAADCgMIAwAAAA==.Conflagrate:BAAALAAECgcIDgAAAA==.',Cr='Crax:BAAALAADCggICgAAAA==.Crithappens:BAABLAAECoEUAAIEAAcIcBusHAAqAgAEAAcIcBusHAAqAgAAAA==.',Da='Dabbington:BAAALAADCgEIAQAAAA==.Damahees:BAAALAADCggICAAAAA==.Danzek:BAAALAADCgcICQAAAA==.',De='Deadarroyo:BAAALAADCgYIBgAAAA==.Deezmonz:BAAALAAECgMIAwABLAAECgYIDwABAAAAAA==.Delik:BAAALAAECgMIBAAAAA==.Destïny:BAAALAAECgcIBwAAAA==.Devastator:BAAALAADCgIIAgAAAA==.Dewdrop:BAAALAAECgIIAgAAAA==.',Di='Dirty:BAAALAADCgUIBQAAAA==.',Do='Docmanari:BAAALAAECgIIAgAAAA==.Dodisock:BAAALAADCgcIBwAAAA==.Doesdis:BAAALAADCgYIBgAAAA==.Doompalm:BAAALAADCgcIBwAAAA==.Doomshield:BAAALAAECgIIAgAAAA==.',Dr='Dracodeez:BAAALAAECgMIBgAAAA==.Dracô:BAAALAAECgMIBQAAAA==.Draxxadin:BAAALAADCggICAAAAA==.Druwid:BAAALAADCgMIAwAAAA==.',Dz='Dznts:BAAALAAECgMIBwAAAA==.',['Dâ']='Dârksky:BAAALAAECgMIBQAAAA==.',Ed='Eddiethered:BAAALAAECgEIAQAAAA==.',Ei='Eiseth:BAAALAAECgYICQAAAA==.',El='Electronvolt:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.Elleseven:BAAALAAECgMIAwAAAA==.',En='Enkidead:BAAALAADCgQIBAAAAA==.',Ep='Epeus:BAAALAAECgMIBAAAAA==.Epikhotti:BAAALAADCgQIBAAAAA==.',Er='Eradorn:BAAALAAECggIDAAAAA==.Erisson:BAAALAAECggIBwAAAA==.',Es='Eszran:BAAALAAECgIIAwAAAA==.',Fa='Faely:BAAALAADCggIFwAAAA==.Faevian:BAAALAAECgUIBQAAAA==.Fatherfister:BAAALAAECgcIDwAAAA==.',Fe='Ferosha:BAAALAAECgMIAwABLAAECgYIDwABAAAAAA==.',Fi='Fisch:BAAALAAECgMIBgAAAA==.Fistbill:BAAALAADCgYIDAAAAA==.',Fl='Floisa:BAAALAADCgMIAwAAAA==.Flynae:BAAALAAECgMIAwAAAA==.',Fo='Foundit:BAAALAAECgYIDwAAAA==.Foxcloud:BAAALAADCgcIBQAAAA==.Foxcloudz:BAAALAADCgQIBAAAAA==.',Fr='Franco:BAAALAAECgMIBgAAAA==.Frearyne:BAAALAAECgEIAQAAAA==.Freezebytch:BAAALAADCgcIBwABLAADCggIDAABAAAAAA==.Friedicecrea:BAAALAAECgEIAQAAAA==.Frostrayne:BAAALAADCgEIAQAAAA==.',Fu='Furrymedaddy:BAAALAADCggICAABLAAECgMIBgABAAAAAA==.',Fy='Fyxxer:BAAALAAECgQIBQABLAAECggIGwAFAA0cAA==.Fyxxie:BAABLAAECoEbAAIFAAgIDRxxDAB9AgAFAAgIDRxxDAB9AgAAAA==.',Ga='Gannikus:BAAALAAECgMIBgAAAA==.',Gi='Gialiana:BAABLAAECoEaAAIGAAgIzRxrCwBbAgAGAAgIzRxrCwBbAgAAAA==.Gibbes:BAAALAAECgQIBAAAAA==.',Gl='Gloriousfury:BAAALAADCggIDQAAAA==.',Go='Golanth:BAAALAADCgcICwAAAA==.Goldenkraken:BAAALAADCgEIAQAAAA==.',Gr='Greenpower:BAAALAADCggICQAAAA==.Greenymeany:BAAALAAECgYIEAAAAA==.Grizzlethorn:BAAALAADCgUIBQAAAA==.Grully:BAAALAAECgcIEAAAAA==.',Gu='Gubbin:BAAALAAECgYIDwAAAA==.',Ha='Haggard:BAAALAAECgMIBAAAAA==.Hailsbelle:BAAALAAECgEIAgAAAA==.Harddon:BAAALAADCggICAAAAA==.Hashtag:BAAALAADCgMIBQAAAA==.',Hb='Hbic:BAAALAAECgMIBwAAAA==.',He='Heartstabber:BAAALAAECgMIBwAAAA==.Helennia:BAAALAAECgQIBAAAAA==.Hellbane:BAAALAAECgIIAwAAAA==.Helore:BAAALAADCggICAAAAA==.',Hi='Hiryu:BAAALAADCgcICAAAAA==.',Ho='Holycolty:BAAALAAECgMIBAAAAA==.Holykrap:BAAALAAECgMIBQAAAA==.Honkhonk:BAAALAAECgIIAgAAAA==.Horchatita:BAAALAADCggIFQAAAA==.',Hu='Hungidan:BAAALAAECgMIBgAAAA==.',Ia='Iasreviad:BAAALAAECgYIDwAAAA==.',Ic='Ichab:BAAALAAECgEIAQAAAA==.',In='Indeathinite:BAAALAADCgYIBgAAAA==.Inferniö:BAABLAAECoEgAAMDAAgICCZnAAB6AwADAAgICCZnAAB6AwAEAAII4BAYYgB2AAAAAA==.Inkurushio:BAAALAAECgIIAgAAAA==.Inshoxicated:BAAALAADCgEIAgAAAA==.',Io='Iolanie:BAAALAAECgQIBgAAAA==.',Is='Ismat:BAAALAAECgYIDwAAAA==.',It='Ithys:BAAALAAECgYIDAAAAA==.',Ja='Jabahnzulash:BAAALAAECgMIAwABLAAECgcIEQABAAAAAA==.Jaeko:BAAALAAECgMIBQAAAA==.Jaekyrn:BAAALAADCggICQABLAAECgMIBQABAAAAAA==.Jaesky:BAAALAADCgMIAwABLAAECgMIBQABAAAAAA==.Jamrock:BAAALAAECggIBAAAAA==.Jarshh:BAAALAAECgMIBgAAAA==.Jastes:BAAALAADCgcICQABLAAECgYIDwABAAAAAA==.',Je='Jenako:BAAALAAECgMIAwAAAA==.Jentoo:BAAALAAECgYIDwAAAA==.',Ji='Jinn:BAAALAADCggIDQAAAA==.',Ju='Judge:BAAALAADCgcIDwABLAAECgYIDwABAAAAAA==.',['Jú']='Júel:BAAALAAECgEIAQAAAA==.',Ka='Kaelvánas:BAAALAAECgIIBAABLAAECggIEgABAAAAAA==.Kairos:BAAALAAECgMIBgAAAA==.',Ke='Keeph:BAAALAADCgcIBwAAAA==.Kelaan:BAAALAAECggIEgAAAA==.Keladriel:BAAALAAECgIIAwAAAA==.Kelsola:BAAALAAECgMIBgAAAA==.',Ki='Kilian:BAAALAAECgEIAgAAAA==.Kiril:BAAALAADCgcIDQAAAA==.Kiritos:BAAALAADCggICwAAAA==.Kiserys:BAAALAAECgMIAwAAAA==.',Ko='Korpse:BAAALAADCgQIBAAAAA==.',Kr='Krutus:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.Krysto:BAAALAAECgMIBAAAAA==.',Ku='Kungpowchick:BAAALAADCgMIAwAAAA==.',Ky='Kyr:BAAALAAECgEIAQAAAA==.',La='Lays:BAAALAADCgEIAQAAAA==.Lazerchikin:BAAALAADCgYIBgAAAA==.',Le='Lelét:BAAALAADCgcICAAAAA==.Lenin:BAAALAAECgIIAwAAAA==.Lexicology:BAAALAAECgIIBAABLAAECgMIAwABAAAAAA==.',Li='Littlestanky:BAAALAADCgYIBgAAAA==.',Ll='Llanowa:BAAALAADCgcIBwAAAA==.',Lo='Lookforlight:BAABLAAECoEaAAICAAcIzh+WGAA2AgACAAcIzh+WGAA2AgAAAA==.Lorenth:BAAALAAECgMIBgAAAA==.Lorne:BAAALAADCgEIAQAAAA==.',Ly='Lyralia:BAAALAAECgIIAgAAAA==.',Ma='Madcowburger:BAAALAADCgMIBQAAAA==.Magepalm:BAAALAAECgEIAQAAAA==.Maizen:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Malgorest:BAAALAADCgMIAwAAAA==.Malidros:BAABLAAECoEUAAIHAAgINA/YGwDHAQAHAAgINA/YGwDHAQAAAA==.Manoamano:BAAALAADCggICAAAAA==.Marhault:BAAALAAECgYIDAAAAA==.Marriage:BAAALAAECgMIBAAAAA==.Masitaka:BAAALAAECgMIAwAAAA==.Maxander:BAAALAAECggIDwAAAA==.Maximus:BAAALAAECgIIAwAAAA==.Mazah:BAAALAAECgMIAwAAAA==.',Me='Mechanix:BAAALAAECgIIAgAAAA==.Meibao:BAAALAAECgYIDwAAAA==.Menowa:BAAALAAECgMIAwAAAA==.',Mi='Millîe:BAAALAAECgMIBgAAAA==.Mistbringer:BAAALAAECgIIAgAAAA==.Mizdaddy:BAAALAAECggIAQAAAA==.',Mo='Mogxecute:BAAALAAECgYIDwAAAA==.Monorìth:BAEALAAFFAIIAgAAAA==.Moosalini:BAAALAADCgMIAwAAAA==.Moosenuckle:BAAALAADCgIIAgAAAA==.Mordaci:BAAALAADCgcIBwAAAA==.Mosaden:BAAALAAECgQIBQAAAA==.Mothghina:BAAALAADCgcICgAAAA==.',Mu='Mugetsu:BAAALAADCggICAAAAA==.Mullett:BAAALAAECgMIBAAAAA==.',My='Mymeii:BAAALAAECgEIAQAAAA==.Mythdaran:BAAALAADCggICgAAAA==.',Na='Nakiki:BAAALAAECgIIAgAAAA==.Nanzith:BAAALAADCgcIBwAAAA==.Nash:BAAALAADCgcIBwAAAA==.',Ne='Nerfornothin:BAAALAAECgIIAwAAAA==.Nethris:BAAALAAECgMIBwABLAAECggIEgABAAAAAA==.Nethshock:BAAALAAECggIEgAAAA==.Netsmear:BAAALAAECgEIAQAAAA==.Newdawn:BAAALAAECgMIBgAAAA==.',Ni='Nik:BAAALAAECgYICgAAAA==.',No='Noisyboy:BAAALAADCgUIBQAAAA==.Nosferato:BAAALAADCggICwAAAA==.Nowa:BAAALAADCgcIDQAAAA==.',['Nô']='Nôrah:BAAALAAECgMIAwAAAA==.',Ob='Obi:BAAALAAECgMIAwAAAA==.',Oh='Ohyes:BAAALAAECgMIBgAAAA==.',Ol='Oldman:BAAALAAECgEIAQAAAA==.Olfuan:BAAALAADCggICAAAAA==.Olliie:BAAALAADCggIBwAAAA==.',On='Onawani:BAAALAAECgYICwAAAA==.',Or='Oriion:BAAALAADCggIDgAAAA==.',Os='Osmont:BAAALAAECgIIAgAAAA==.',Pa='Panathan:BAAALAAECgMIBAAAAA==.Panda:BAAALAAECgIIAgAAAA==.',Pi='Pikagosa:BAABLAAECoEbAAIIAAgIQB6PBwCwAgAIAAgIQB6PBwCwAgAAAA==.',Po='Polaritee:BAAALAADCgYIBgAAAA==.',Pr='Prrine:BAAALAADCgEIAQAAAA==.',['Pæ']='Pæsta:BAAALAAECgMIBAAAAA==.',Ra='Raids:BAAALAAECgcIDwAAAA==.Rambsi:BAAALAADCggICAAAAA==.Ravel:BAAALAAECgMICQAAAA==.',Re='Redeem:BAAALAAECgUIBgAAAA==.Reios:BAAALAAECgIIAwAAAA==.',Rh='Rhadam:BAAALAAECgYICwAAAA==.Rhaz:BAAALAAECgIIAwAAAA==.Rhikre:BAAALAAECgEIAQAAAA==.',Ri='Rickyspanish:BAAALAAECgMIBAAAAA==.Rielle:BAAALAADCggIFwAAAA==.Rifter:BAAALAAECgEIAQAAAA==.Rigamortiz:BAAALAADCggIDAAAAA==.',Ro='Roupert:BAAALAADCgcIDAAAAA==.',Ru='Rubyouraw:BAAALAADCgQIBAAAAA==.Ruester:BAAALAADCgQIBAAAAA==.Ruffneck:BAAALAADCgcIBwAAAA==.Ruine:BAAALAADCgQIBAAAAA==.Rukaine:BAAALAAECgMIAwAAAA==.Rumina:BAAALAAECgIIAgAAAA==.',['Rå']='Rågnarök:BAAALAADCgIIAgAAAA==.',Sa='Sabrîna:BAAALAAECgYICQAAAA==.Saelirria:BAAALAADCgcIBwABLAAECggIGgAGAM0cAA==.Sakamota:BAAALAAECgMIBAAAAA==.Sakuadoa:BAAALAADCgIIAgAAAA==.Samo:BAAALAAECgMIBAAAAA==.Sandarr:BAAALAAECgMIAwAAAA==.Sanguinne:BAAALAAECgIIAgAAAA==.Sargemarge:BAAALAAECgIIAgAAAA==.',Se='Seabear:BAAALAADCgUIBQAAAA==.Seafoame:BAAALAAECgYICgAAAA==.Seedspreader:BAAALAADCggICAAAAA==.Seranix:BAAALAADCgMIAwAAAA==.Serbitar:BAAALAADCggIDAABLAAECgEIAQABAAAAAA==.Severus:BAAALAADCggICgAAAA==.',Sh='Shadowplay:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.Shadowwar:BAAALAADCggIEwAAAA==.Shamazing:BAAALAADCgIIAgAAAA==.Shikamáru:BAAALAADCggICAAAAA==.Shyft:BAAALAADCggICAAAAA==.',Si='Silaria:BAAALAAECgcIDQAAAA==.Silther:BAAALAAECgIIAgAAAA==.Sisterpika:BAAALAADCgcIBwAAAA==.',Sl='Slapslap:BAAALAADCggIFAAAAA==.Slavka:BAAALAADCgUIBgAAAA==.Sleepyjoee:BAAALAAECgMIBQAAAA==.Sleepypriest:BAAALAADCgQIBAAAAA==.Sleepyyjoe:BAAALAAECgQICAAAAA==.Slimothy:BAAALAADCgIIAgAAAA==.',Sm='Smaalls:BAAALAADCgQIBAAAAA==.',Sn='Snipezalot:BAAALAAECgYIBgAAAA==.Snowmage:BAAALAADCggICAAAAA==.Snâppy:BAAALAAECgMIBAAAAA==.',So='Soap:BAAALAADCgMIAwAAAA==.Societte:BAAALAAECgMIBAAAAA==.Soloron:BAAALAAECgIIAwAAAA==.Sorrowsöng:BAAALAAECgMIBgAAAA==.Southvik:BAAALAADCggIDwABLAAECgMIBAABAAAAAA==.',Sp='Spamlock:BAAALAADCggICAABLAAECggIEwABAAAAAA==.Sparke:BAAALAADCgQIBAAAAA==.Sparrhawk:BAAALAADCggIDAAAAA==.Spiced:BAAALAAECgcICgAAAA==.Spiceweasel:BAAALAADCgcIBwAAAA==.Spin:BAAALAAECgEIAQAAAA==.',Sq='Squallhammer:BAAALAADCgEIAQAAAA==.',St='Stepfister:BAAALAADCggICAAAAA==.Streea:BAAALAADCgYIBgAAAA==.Sttriker:BAAALAAECgMIBgAAAA==.',Su='Suismort:BAAALAAECggIEgAAAA==.Suisspins:BAAALAAECgMIBwAAAA==.Supernova:BAAALAADCggIDwAAAA==.',Sy='Synsairis:BAAALAAECgMIBgAAAA==.',Sz='Szekhu:BAAALAADCgUIBQAAAA==.',Ta='Tahm:BAAALAADCgQIBAAAAA==.Taiya:BAAALAADCgEIAQAAAA==.Talonknight:BAAALAAECgMIBAAAAA==.Taltruth:BAAALAADCgcIBwAAAA==.Taurrows:BAAALAAECgcIEwAAAA==.',Tb='Tbill:BAAALAAECgcICQAAAA==.',Te='Telvien:BAAALAADCgMIAwAAAA==.',Th='Thalysra:BAAALAADCgUIAwAAAA==.Theicemaker:BAAALAAECgMIBAAAAA==.Thesandwhich:BAAALAAECgMIAwAAAA==.Thornn:BAAALAADCgUIBwAAAA==.Throwdini:BAAALAAECgYICQAAAA==.',Ti='Tidewrought:BAAALAAECgEIAQAAAA==.',To='Toes:BAAALAAECgQIBwAAAA==.Totesmagoatz:BAAALAADCgQIAwAAAA==.',Tr='Trashtruck:BAAALAAECgQIBAAAAA==.Trend:BAAALAAECgMIBwAAAA==.Trotsky:BAAALAADCgcIBwAAAA==.',Tu='Tulanis:BAAALAAECgYIDwAAAA==.Turbotax:BAAALAADCgQIBAAAAA==.',Ty='Tyriem:BAAALAAECgYICgAAAA==.Tyssanton:BAAALAAECgMIBAAAAA==.',Tz='Tziganin:BAAALAAECgMIBQAAAA==.',Ut='Utaadh:BAAALAADCggIBwAAAA==.',Va='Vael:BAAALAADCgEIAQABLAAECgYIDwABAAAAAA==.Vaelthorn:BAAALAADCgEIAQABLAADCgUIBQABAAAAAA==.Vallerin:BAAALAAECgMIAwAAAA==.Valzara:BAAALAADCgYIBgAAAA==.Vanestor:BAAALAAECgEIAQABLAAECggIHAAJAIAiAA==.Vanhell:BAAALAAECgMIBAAAAA==.Vanhelsingx:BAAALAADCggIDwAAAA==.Vaticate:BAAALAAECgIIAgAAAA==.',Ve='Vegadh:BAAALAADCgMIAwAAAA==.Velaar:BAAALAADCgcICQABLAAECgYIDwABAAAAAA==.Velaán:BAAALAAECgMIAwABLAAECggIEgABAAAAAA==.Verhauzad:BAAALAADCgIIAgAAAA==.',Vi='Viiv:BAAALAAECgMIBAAAAA==.Vikthyr:BAAALAADCgIIAgABLAAECgMIBAABAAAAAA==.Villain:BAAALAAECgMIAwABLAAECgYIDAABAAAAAA==.',Vo='Vodiann:BAAALAADCgUIBQABLAAECggIHAAJAIAiAA==.Vodnar:BAABLAAECoEcAAIJAAgIgCIXBQAVAwAJAAgIgCIXBQAVAwAAAA==.Vodric:BAAALAAECgMIAwABLAAECggIHAAJAIAiAA==.Volzar:BAAALAAECgEIAQAAAA==.',Vu='Vulcos:BAAALAADCggICgAAAA==.',Vy='Vyn:BAAALAADCgEIAQAAAA==.',['Vá']='Válentine:BAAALAAECgMIBAAAAA==.',Wa='Walls:BAAALAAECgQIBQAAAA==.Waste:BAAALAAECgMIAwAAAA==.',We='Werragan:BAAALAAECgYIBgAAAA==.Werrastraza:BAAALAAECgIIBAAAAA==.Western:BAAALAAECgMIAwAAAA==.',Wh='Whispurr:BAAALAADCgYIBQAAAA==.',Wi='Willîe:BAAALAAECgIIBAAAAA==.Wilt:BAAALAADCggIEgAAAA==.',Wt='Wtfami:BAAALAADCgcICgAAAA==.',Wu='Wussycat:BAAALAADCggIEAAAAA==.',Xe='Xeirikihr:BAAALAADCgIIAgAAAA==.',Xi='Xiezhi:BAAALAAECggIBwAAAA==.',Ya='Yaffa:BAAALAADCggICAAAAA==.',Yo='Yogí:BAAALAAECgYICAAAAA==.Yokos:BAAALAADCggIFQAAAA==.',Za='Zahneel:BAAALAAECgMIBgAAAA==.Zalanar:BAAALAADCggIDwAAAA==.Zaranth:BAAALAADCgcIBwAAAA==.Zaratul:BAABLAAECoEbAAICAAgI0yHdCQDgAgACAAgI0yHdCQDgAgAAAA==.Zaroth:BAAALAAECgcIEgAAAA==.',Ze='Zelyne:BAAALAADCgcIBwAAAA==.Zentered:BAAALAADCgcICwAAAA==.Zestiriaa:BAAALAADCgUIBQAAAA==.',Zh='Zhaeer:BAAALAADCgcIBwAAAA==.Zharakp:BAAALAADCgUIBAAAAA==.',Zu='Zucarithas:BAAALAADCgcIBwAAAA==.',Zy='Zyrian:BAAALAADCgcIFQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end