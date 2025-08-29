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
 local lookup = {'Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Mage-Arcane','Mage-Frost','Mage-Fire','Rogue-Assassination','Warrior-Protection','Paladin-Holy',}; local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aantoc:BAAALAADCgEIAQAAAA==.',Ad='Admin:BAAALAAECgUICQAAAA==.',Ai='Airist:BAAALAAECgIIAgAAAA==.',Al='Alathir:BAAALAAECgcIDAAAAA==.Alluri:BAAALAAECgIIAgAAAA==.Alone:BAAALAAECgIIAgAAAA==.Alrossan:BAAALAAFFAIIAgAAAA==.Althemia:BAAALAADCgMIAwAAAA==.Alunamora:BAAALAAECgMIBgAAAA==.Alwind:BAAALAAECgMIBAAAAA==.',Am='Ametheus:BAAALAADCggIDQAAAA==.Ammaris:BAAALAAECgEIAQAAAA==.',An='Ancksunamun:BAAALAADCgIIAgAAAA==.Andia:BAAALAAECgIIAwAAAA==.Angerr:BAAALAAECgYIBgAAAA==.',Ap='Apøllø:BAAALAAECgIIAgAAAA==.',Aq='Aquamann:BAAALAADCgMIAwAAAA==.',Ar='Arcamancer:BAAALAADCggICwAAAA==.Argarth:BAAALAAECgIIAgAAAA==.Arinthal:BAAALAADCgcIBwAAAA==.Arontheplmbr:BAAALAAECgIIAgAAAA==.Arril:BAAALAAECgIIAgAAAA==.',As='Ashed:BAAALAAECggIDgAAAA==.Ashlieghee:BAAALAAECgMIAwAAAA==.Asterie:BAAALAADCgUIBQAAAA==.Astien:BAAALAADCgcIBwAAAA==.Astra:BAAALAAECgEIAQAAAA==.Aszunie:BAAALAAECgIIAgAAAA==.',Au='Auralyth:BAAALAADCggIDQAAAA==.Aurien:BAAALAAECgIIBAAAAA==.',Av='Averlen:BAAALAAECgMIAgAAAA==.Avha:BAAALAAECgIIAgAAAA==.',Ay='Ayrene:BAAALAAECgIIAgAAAA==.',Ba='Bailas:BAAALAADCggIFwAAAA==.Banana:BAABLAAECoEVAAMBAAgI9iJ8BACiAgABAAcIkiJ8BACiAgACAAMIMxRSHgDIAAAAAA==.Barbiesresto:BAAALAAECgYIBwAAAA==.Basharn:BAAALAADCgYIBgAAAA==.Bashou:BAAALAADCgIIAgAAAA==.Bastet:BAAALAAECgYICQAAAA==.',Be='Beleynn:BAAALAAECgUIBQAAAA==.Benjofamin:BAAALAADCgcIBwAAAA==.',Bi='Bigdps:BAAALAADCggIFAAAAA==.Bigpuffer:BAAALAADCgcICAAAAA==.Bitesize:BAEALAAECggIEQAAAA==.',Bl='Bladesky:BAAALAADCgcIBwAAAA==.Blashster:BAAALAADCggICAAAAA==.Bledingrage:BAAALAAECgIIAgAAAA==.Blightsize:BAEALAADCggICAABLAAECggIEQADAAAAAA==.Blinkstorm:BAAALAAECgIIAgAAAA==.Bloodyauel:BAAALAADCggIFwAAAA==.',Bo='Boaw:BAAALAADCgYIBwAAAA==.Booppinbubb:BAAALAAECgEIAQAAAA==.Boraichoo:BAAALAAECgMIAwAAAA==.Bouchardy:BAAALAAECgYIDAAAAA==.',Br='Brackz:BAAALAADCggIDQAAAA==.Brannwynn:BAAALAADCgQIBAAAAA==.Brighter:BAAALAAECgcIEAAAAA==.',Bu='Bunnkost:BAAALAAECgIIAgAAAA==.Bunnyparade:BAAALAADCgEIAQAAAA==.',By='Bynnevanna:BAAALAADCggIFgAAAA==.',Ca='Caiden:BAAALAAECgMIBAAAAA==.Cainen:BAAALAAECgMIAwAAAA==.Calrissa:BAAALAADCgQIBQAAAA==.Casterrata:BAAALAADCgcICgAAAA==.',Ce='Celbrooke:BAAALAAECgIIAwAAAA==.Cethin:BAAALAADCgcIBwAAAA==.',Ch='Chamina:BAAALAADCgMIAwAAAA==.Chaosshot:BAAALAAECgYICQAAAA==.Cheedardrood:BAABLAAECoEUAAIEAAcISxk4EAAFAgAEAAcISxk4EAAFAgAAAA==.',Cl='Claytotems:BAAALAADCggIDgAAAA==.Claytraps:BAAALAADCggICAAAAA==.Clayvicar:BAAALAAECgcIEAAAAA==.Clulnglunk:BAAALAADCggICQAAAA==.',Co='Coridane:BAAALAAECgQIBQAAAA==.Corwinfiron:BAAALAAECgMIAwAAAA==.Cotraye:BAABLAAECoEVAAMFAAgIWSLCCADpAgAFAAgIWSLCCADpAgAGAAUIoQtjEgDsAAAAAA==.',Cr='Cruller:BAAALAADCggIDwAAAA==.Cryteck:BAAALAADCgcICwAAAA==.',Cu='Curkage:BAAALAADCgcIBwAAAA==.Curseblood:BAAALAAECgIIBAAAAA==.',Cy='Cybexia:BAAALAADCgcIBwAAAA==.',['Cá']='Cámus:BAAALAAECgIIAgAAAA==.',Da='Daementor:BAAALAAECggIEAAAAA==.Dakvelis:BAAALAAECgcIEAAAAA==.Danduin:BAAALAAECgMIAgAAAA==.Daphine:BAAALAADCggIFQAAAA==.Darkplazzma:BAAALAAECgMIAwAAAA==.Darkwhispers:BAAALAADCggIEAABLAAECggIDwADAAAAAA==.Darmin:BAAALAAECgMIBQAAAA==.Dav:BAAALAADCgIIAgAAAA==.Dazcon:BAAALAADCgIIAgAAAA==.',De='Deathmask:BAAALAADCgcIBwAAAA==.Deipriest:BAAALAADCggIDgAAAA==.Demontacos:BAAALAAECgMIAwAAAA==.Derodd:BAAALAAECgYIBwAAAA==.Dewkiez:BAAALAADCggIDAABLAAECggIEQADAAAAAA==.',Di='Diabolicarl:BAAALAAECgYICQAAAA==.Diri:BAAALAAECggIDgAAAA==.Disgrace:BAAALAAECgMIBAAAAA==.',Do='Dojacat:BAAALAADCgYICAAAAA==.Dominith:BAAALAAECgIIAgAAAA==.Dookiez:BAAALAADCggICAABLAAECggIEQADAAAAAA==.Doubledragin:BAAALAAECgYIDwAAAA==.',Dr='Draag:BAAALAADCgYIBgAAAA==.Draeneiamin:BAAALAADCgIIAgABLAADCgcIBwADAAAAAA==.Dragfan:BAAALAAECgIIAgAAAA==.Druidgirls:BAAALAAECggIEQAAAA==.Druist:BAAALAADCgIIAgAAAA==.',Du='Duess:BAAALAADCgMIAwAAAA==.Dullex:BAAALAAECgIIAgAAAA==.Dumptruck:BAAALAADCgcICAAAAA==.Durogdem:BAAALAAECgIIAwAAAA==.Duskfire:BAAALAADCgcIEwAAAA==.',['Dà']='Dàrkness:BAAALAAECgMIAwAAAA==.',Ef='Efrideet:BAAALAADCggIGwAAAA==.',El='Elaelta:BAAALAADCgEIAQAAAA==.Elenora:BAAALAAECgYIBgAAAA==.Elhunthunt:BAAALAADCgQIBAAAAA==.Ellea:BAAALAAECgMIAgAAAA==.Ellim:BAAALAAECgYIBgAAAA==.Eluneatic:BAAALAAECgEIAQAAAA==.',Em='Emer:BAAALAAECgcIEAAAAA==.Emmy:BAAALAADCggICgABLAAECgcIEAADAAAAAA==.',En='Encore:BAAALAAECgMIAwAAAA==.Endellion:BAAALAADCgYIBgAAAA==.',Eo='Eousphorus:BAAALAAECggIEAAAAA==.',Er='Eros:BAAALAADCgMIAwAAAA==.',Es='Esplan:BAAALAADCggICAABLAAECggIDgADAAAAAA==.',Et='Etile:BAAALAAECgMIBAAAAA==.',Ev='Evelleion:BAAALAAECgQIBQAAAA==.Everfrost:BAAALAADCgQIBAAAAA==.',Ex='Exoticlord:BAAALAAECgIIAgAAAA==.',Ez='Ezek:BAAALAAECgEIAQAAAA==.',Fe='Feid:BAAALAAECgMIBwAAAA==.Felicity:BAAALAADCgcIBwAAAA==.Fellynn:BAAALAAECgcIEAAAAA==.Fertilized:BAAALAADCgUICgAAAA==.',Fi='Firburger:BAAALAADCgQIBAAAAA==.Fishfoot:BAAALAADCgEIAQAAAA==.',Fj='Fjorf:BAAALAAECggICAAAAA==.',Fl='Flashblood:BAAALAAECgMIAwAAAA==.Flirtywombat:BAAALAADCggIFwAAAA==.',Fo='Foah:BAAALAADCggICgAAAA==.Foxtrót:BAAALAADCgIIAgABLAAECgYIDQADAAAAAA==.',Fr='Friskifingaz:BAAALAADCgcIDgAAAA==.',Fu='Fucsa:BAAALAADCgMIBQAAAA==.Fumanchu:BAAALAAECgYIDQAAAA==.',Ga='Gaamora:BAAALAADCgcICgAAAA==.Gamegg:BAAALAAECgMIAgAAAA==.Gankster:BAAALAAECgEIAQAAAA==.Garagos:BAAALAAECgcIEAAAAA==.',Gc='Gcj:BAAALAAECgUIBgAAAA==.',Ge='Gebuss:BAAALAADCggIEAABLAAECggIEQADAAAAAA==.',Gi='Gilford:BAAALAAECgIIAgAAAA==.Gimlinn:BAAALAAECgQIBgAAAA==.',Gl='Glock:BAAALAADCggICAAAAA==.',Gn='Gnesii:BAAALAADCgMIAwAAAA==.',Go='Gorf:BAAALAADCggICAABLAAECggICAADAAAAAA==.',Gr='Greymist:BAAALAADCggIEAAAAA==.Grezhul:BAAALAADCggICAAAAA==.Grimtuk:BAAALAADCggICgAAAA==.Grizzlock:BAAALAAECgEIAgAAAA==.Grochen:BAAALAADCggIEAAAAA==.Grïpnrïp:BAAALAADCgQIBAAAAA==.',Gu='Guldam:BAAALAAECgQIBQAAAA==.Gunnerrata:BAAALAAECgQIBgAAAA==.',Ha='Halifaxx:BAAALAAECgEIAQAAAA==.Halitwo:BAAALAADCgMIAwAAAA==.Hamburgar:BAAALAADCgEIAQAAAA==.Hammeredfupa:BAAALAAECgIIAgAAAA==.Hapiagin:BAAALAAECgMIAgAAAA==.Havan:BAAALAADCgcIBwAAAA==.Hawknor:BAAALAAECgIIAgAAAA==.',He='Herm:BAAALAAECgcIEAAAAA==.Heydave:BAAALAAECggIBgAAAA==.',Ho='Holymidget:BAAALAADCggIDQAAAA==.Hotmamama:BAAALAAECgEIAQAAAA==.Hotsndots:BAAALAAECgcIDAAAAA==.',Hu='Huzzy:BAAALAADCgMIBQAAAA==.',Hy='Hyperia:BAAALAADCggICAABLAAECggIEQADAAAAAA==.Hysteria:BAAALAADCgEIAQAAAA==.',Ia='Iamcrazydk:BAAALAADCggIEwAAAA==.Iamcrazydrui:BAAALAADCgIIAgAAAA==.',Ig='Ignored:BAAALAAECgMIAwAAAA==.',Il='Ilidra:BAAALAADCgYIBgAAAA==.Illidæn:BAAALAAECgIIAgAAAA==.',Im='Imgonaruneya:BAAALAAECgEIAQAAAA==.Imgød:BAAALAADCgUIBQAAAA==.Immoralhate:BAAALAADCggICAAAAA==.Imoxi:BAAALAADCgYIBwAAAA==.Impuratus:BAAALAAECgYICQAAAA==.',In='Inq:BAAALAAECgUICAAAAA==.Intervals:BAAALAAECgEIAQAAAA==.',Io='Io:BAAALAADCggIDgAAAA==.',Ir='Iridaceaë:BAAALAADCgYIBgAAAA==.',Is='Isedeath:BAAALAAECgcIEAAAAA==.',Ja='Jafarius:BAAALAADCgEIAQAAAA==.Janton:BAAALAAECgMIBQAAAA==.',Je='Jenaveive:BAAALAAECgMIBAAAAA==.',Jn='Jnex:BAAALAAECgYIDgAAAA==.',Jo='Jookiez:BAAALAAECggIEQAAAA==.Joubers:BAAALAAECgEIAQAAAA==.',Ju='Juicer:BAAALAADCggIDQAAAA==.Justine:BAAALAAECgMIAgAAAA==.',['Jä']='Jävel:BAAALAAECgIIAgAAAA==.',Ka='Kaelysong:BAAALAADCgMIAwAAAA==.Kaepora:BAAALAAECgIIAgAAAA==.Kagebolt:BAAALAAECgMIAgAAAA==.Kairah:BAAALAADCgcIBwAAAA==.Kairiandel:BAAALAAECgYICQAAAA==.Kalï:BAAALAADCgcIDgAAAA==.Karnakula:BAAALAADCgYICgAAAA==.Karnapong:BAAALAADCgIIAgAAAA==.Karnathula:BAAALAAECgcIEAAAAA==.',Ke='Kelleon:BAAALAAECgEIAQAAAA==.Kennel:BAAALAAECgIIAgAAAA==.Keylleth:BAAALAADCgcIDgAAAA==.',Kh='Khalania:BAAALAAECgEIAQAAAA==.Khamari:BAAALAAECgMIAwAAAA==.Khlamps:BAAALAADCgIIAgAAAA==.',Ki='Kilaia:BAAALAAECgEIAgAAAA==.Kilda:BAAALAAECgMIAwAAAA==.Kirru:BAAALAAECgIIAgAAAA==.Kirsty:BAAALAADCggIDwAAAA==.Kixle:BAAALAAECgEIAQAAAA==.',Kn='Kniveschou:BAAALAAECgMIBAAAAA==.',Ko='Kokushibô:BAAALAADCgMIAwAAAA==.Kolobos:BAAALAADCgYIBgAAAA==.',Kr='Kreaton:BAAALAADCggIDwAAAA==.',Kw='Kwag:BAAALAAECggIAgAAAA==.',['Kû']='Kûchiki:BAAALAAECgYICAAAAA==.',La='Laethorne:BAAALAADCggIDwAAAA==.Lanludar:BAAALAAECgYICQAAAA==.Lantern:BAAALAADCggICAAAAA==.Laserfingies:BAAALAADCgYICgAAAA==.Lastsun:BAAALAADCgYIBgAAAA==.Lavacakes:BAAALAAECgcIEAAAAA==.',Le='Leggewïe:BAAALAADCgQIBAAAAA==.Lelantoz:BAAALAAECgIIAgAAAA==.Lenailla:BAAALAADCgYIBgAAAA==.Leqoofus:BAAALAADCgUIBQABLAADCgYICgADAAAAAA==.',Li='Lidan:BAAALAADCgcIDAAAAA==.Lii:BAAALAAECgEIAQAAAA==.Linaeni:BAAALAADCgQIBAAAAA==.',Lo='Logyn:BAAALAADCgMIAwAAAA==.Lorwalker:BAAALAADCgEIAQAAAA==.',Lu='Lunarluvgood:BAAALAADCggICAABLAAECggIDgADAAAAAA==.Luta:BAAALAADCgcIBwAAAA==.',Ly='Lyssiarose:BAAALAAECgIIAgAAAA==.',Ma='Mackina:BAAALAADCggICwAAAA==.Madmagi:BAAALAAECgIIAgAAAA==.Mado:BAAALAAECgYICQAAAA==.Magicky:BAAALAAECgEIAQAAAA==.Maido:BAAALAADCgEIAQAAAA==.Maikego:BAAALAAECgMIAwAAAA==.Malfhunter:BAAALAAECggIEQAAAA==.Manic:BAAALAADCgIIAgAAAA==.Manofwood:BAAALAAECgcIDQAAAA==.Mantodea:BAAALAADCgcICAAAAA==.Maribel:BAAALAADCgMIAwAAAA==.Marmin:BAAALAAECgIIAgAAAA==.Masumi:BAAALAADCgcIBwAAAA==.',Me='Meat:BAAALAAECgMIBQAAAA==.Mehrartz:BAAALAADCgYIBgAAAA==.Melillia:BAAALAAECgMIAwAAAA==.Merdocki:BAAALAAECgcIEAAAAA==.Merdre:BAABLAAECoEUAAMHAAcIzBm4EwAVAgAHAAcIzBm4EwAVAgAIAAYI9wHAOwCcAAAAAA==.Meriell:BAAALAAECgIIAgAAAA==.Metasavage:BAAALAADCggICwAAAA==.',Mi='Miccah:BAAALAADCgEIAQAAAA==.Michealhunt:BAAALAADCgYICQAAAA==.Midory:BAAALAADCggICAAAAA==.Milkshakess:BAAALAADCgIIAgAAAA==.Milkymocha:BAAALAAECgIIAgAAAA==.Minus:BAAALAAECgMIAwAAAA==.',Mo='Moistweaver:BAAALAAECgEIAQAAAA==.Moontower:BAAALAADCgYIBgAAAA==.Morcant:BAAALAAECgIIAgAAAA==.Morlu:BAAALAAECgYICgAAAA==.Moron:BAAALAAECgMIAwAAAA==.Mortaríon:BAAALAADCggICAAAAA==.Mortimer:BAAALAADCgcIBwAAAA==.Mourne:BAABLAAECoEdAAMFAAgIAyZ1AQBoAwAFAAgIAyZ1AQBoAwAJAAQImCIzEgB/AQAAAA==.',['Mä']='Mäck:BAAALAAECgEIAgAAAA==.',Na='Nadirya:BAEALAADCggICAABLAAECggIEQADAAAAAA==.Narallia:BAAALAAECgEIAQAAAA==.Natureshogun:BAAALAAECgMIAgAAAA==.',Ne='Needle:BAAALAAECgMIAwAAAA==.Neoshaman:BAAALAADCgcIFAAAAA==.Nephala:BAAALAADCgcIBwAAAA==.',Ni='Nightmehr:BAAALAAECggIDgAAAA==.Ninewizerd:BAAALAADCgcIBwAAAA==.',No='Noblearthur:BAAALAAECgMIBAAAAA==.Nodiddy:BAAALAADCggICAAAAA==.Noobscoob:BAAALAAECgEIAQAAAA==.',Nu='Nutlust:BAAALAAECgEIAQAAAA==.',['Nì']='Nìdalee:BAAALAADCgYIBgAAAA==.',Of='Ofilia:BAAALAADCgcICgAAAA==.',Oh='Ohnobro:BAAALAAECggICgAAAA==.',Om='Omalmalha:BAAALAAECgMIAwAAAA==.',On='Onedruidtion:BAAALAADCggICQAAAA==.Onlyjuans:BAAALAADCggIGAAAAA==.',Op='Ophekins:BAAALAADCgcIDgAAAA==.',Or='Orlos:BAAALAAECgIIAgAAAA==.Oräkk:BAAALAAECgYIDwAAAA==.',Ot='Ottis:BAAALAADCgMIAwAAAA==.',Pa='Padrin:BAAALAAECgIIAgAAAA==.Pandapaws:BAAALAAECgMIBAAAAA==.Pandulce:BAAALAAECgEIAQAAAA==.Papawaas:BAAALAADCgcIBwAAAA==.Partyhardly:BAAALAAECgMIAwAAAA==.Pavetta:BAAALAAECgMIAQAAAA==.',Pd='Pdiddi:BAAALAAECggICQAAAA==.',Ph='Phaedriel:BAAALAADCgcIBwAAAA==.Phanacéa:BAAALAAECgEIAQAAAA==.Phatman:BAAALAAECgIIAgAAAA==.Phrostir:BAAALAAECggIAQAAAA==.',Pi='Pierre:BAAALAAFFAEIAQAAAA==.Pillgrimm:BAAALAAECgMIBAAAAA==.Pingburger:BAAALAADCgcIBwAAAA==.Pirotic:BAAALAADCggIDgAAAA==.',Pl='Platerrata:BAAALAADCggIDwAAAA==.',Po='Pockoator:BAAALAADCgIIAgAAAA==.Pokomo:BAAALAADCggIEQABLAAECgMIBQADAAAAAA==.Pooqh:BAAALAAECgcICQAAAA==.',Pr='Praesidiel:BAAALAAECgMIAwAAAA==.Prepennies:BAAALAADCgcIEwABLAADCggIDQADAAAAAA==.Presxia:BAAALAADCgcIBwAAAA==.Prophylactic:BAAALAAECgIIAgAAAA==.Providence:BAAALAAECggIEQAAAA==.',Pu='Pudgypaws:BAAALAAECgcIDwAAAA==.',Py='Pyrogasm:BAAALAADCgcIDgABLAAECggIHQAFAAMmAA==.',Qu='Quickmend:BAAALAAECggIEQAAAA==.Quicknok:BAAALAADCggIEAAAAA==.',Qz='Qzeal:BAAALAADCgYIBwAAAA==.',Ra='Raccoons:BAABLAAECoEVAAMKAAgIaCWDAQBhAwAKAAgIaCWDAQBhAwALAAEIUhZpSgA9AAAAAA==.Raencryx:BAAALAADCggICAAAAA==.Raengii:BAAALAADCgcIBwABLAADCggICAADAAAAAA==.Ragged:BAAALAAECgYICQAAAA==.Rainsinger:BAAALAADCgcIBgAAAA==.Randomchar:BAAALAADCggIEAAAAA==.Rankor:BAAALAAECgcIDwAAAA==.Rastann:BAAALAAECggIDwAAAA==.Raycharles:BAAALAAECggICAAAAA==.Raztak:BAAALAADCgYIBgABLAAECgMIBQADAAAAAA==.',Re='Reapertoo:BAABLAAECoEYAAIFAAgI4yQ0AwBEAwAFAAgI4yQ0AwBEAwAAAA==.Redbaron:BAAALAAECgYIDAAAAA==.Reganf:BAAALAADCgYIEwAAAA==.Remily:BAAALAAECgcIEAAAAA==.Repyns:BAAALAAECggIDgAAAA==.',Rh='Rhollor:BAAALAAECgMIBAAAAA==.Rhyiah:BAAALAADCgMIAwAAAA==.Rhânko:BAAALAADCgYIBgABLAAECgIIAwADAAAAAA==.',Ri='Riderofblack:BAAALAAECgMIBAAAAA==.Rimeblade:BAAALAADCgcIBwAAAA==.Rincewind:BAAALAAECgMIAwABLAAECggIDgADAAAAAA==.Risi:BAAALAADCgcIDQAAAA==.',Ro='Rodned:BAAALAADCggIEAAAAA==.Rolas:BAAALAAECgEIAQABLAAECgIIAgADAAAAAA==.Rollingpain:BAAALAADCgcIBwABLAAECgYICQADAAAAAA==.Rozalin:BAAALAAECgcIEAAAAA==.',Rr='Rrankor:BAAALAAECgMIAwABLAAECgcIDwADAAAAAA==.',Ru='Ruffprophet:BAAALAADCgYIDAAAAA==.Rumi:BAAALAAECgIIAgAAAA==.',Ry='Ryoshi:BAAALAADCggICAAAAA==.',Sa='Sacredstorms:BAAALAADCgUIBQAAAA==.Sacredswords:BAAALAAECgcIDwAAAA==.Saintcosmo:BAABLAAECoEbAAIMAAcIWAxpMwBNAQAMAAcIWAxpMwBNAQAAAA==.Sandscale:BAAALAAECgMIBQAAAA==.Savagesin:BAABLAAECoEWAAQNAAgIvhZRIgD/AQANAAgI+xFRIgD/AQAOAAMIlyDXHwAhAQAPAAEIVQABEAANAAAAAA==.',Sc='Scharpling:BAAALAADCggIEAABLAAECggIDgADAAAAAA==.',Se='Serènity:BAAALAADCgYIBgABLAADCgcIBwADAAAAAA==.',Sh='Shadelira:BAAALAAECgIIAgAAAA==.Shamwoo:BAAALAADCgYICQABLAADCgcIBwADAAAAAA==.Shaundakul:BAAALAADCggIDgAAAA==.Shibe:BAAALAADCggIDQAAAA==.Shiddydeps:BAAALAADCggIBAAAAA==.Shockakhan:BAAALAAECgIIAgAAAA==.Shortnstack:BAAALAADCgcIBwAAAA==.Shyloh:BAAALAADCggIDwAAAA==.Shãwarma:BAAALAADCgcIDAAAAA==.',Si='Sideffectz:BAAALAAECgQIBAAAAA==.Signet:BAAALAADCgcIBwAAAA==.Silanah:BAAALAAECgcIEAAAAA==.Sindrel:BAAALAADCggICAAAAA==.',Sk='Skadï:BAAALAAECgYICwAAAA==.Skawalker:BAAALAAECggIEAAAAA==.',Sl='Slaynne:BAAALAAECgcIDwAAAA==.',Sm='Smellis:BAAALAADCgcIBwAAAA==.Smäug:BAAALAAFFAIIAwAAAA==.',Sn='Sneakytaco:BAAALAAECgEIAQAAAA==.',So='Sockz:BAABLAAECoEVAAIQAAgIBBUdDQBOAgAQAAgIBBUdDQBOAgAAAA==.Solea:BAAALAADCgQICAAAAA==.Solroasted:BAAALAADCgYICQABLAAECgYIDAADAAAAAA==.Solrosenburg:BAAALAAECgYIDAAAAA==.Sondreman:BAAALAAECgIIAgAAAA==.Sophies:BAAALAAECgMIBwAAAA==.Sorg:BAAALAAECgcICAAAAA==.',Sp='Spiritual:BAAALAAECgEIAQAAAA==.',Sq='Squirreltag:BAAALAAECgcIDgAAAA==.',Sr='Srmorphsalot:BAAALAAECgIIAgABLAAFFAEIAQADAAAAAA==.',Ss='Sstiny:BAAALAADCgEIAQAAAA==.',St='Statyrea:BAAALAADCgcICAAAAA==.Stemmon:BAAALAAECgcICgAAAA==.Styx:BAABLAAECoEXAAIRAAgIzyM5AQBNAwARAAgIzyM5AQBNAwAAAA==.',Su='Sukfóót:BAAALAAECgQIBgAAAA==.Sulk:BAAALAAECgMIBQAAAA==.Sumbatadh:BAAALAAECgIIAwAAAA==.Supermancer:BAAALAAECgIIAgAAAA==.',Sw='Swaggajax:BAAALAADCggICAABLAAECgcIEAADAAAAAA==.',Sy='Sybexia:BAAALAAECgIIAgAAAA==.Sylastin:BAAALAAECgMIBQAAAA==.Sylvestris:BAAALAAECgQIBAAAAA==.',Ta='Tacos:BAAALAADCggICQAAAA==.Tailyan:BAAALAADCgQIBQAAAA==.Tankjob:BAAALAADCgYICwAAAA==.Tanklorswift:BAAALAADCgQIBAAAAA==.Tanukis:BAAALAAECgIIAgAAAA==.Tatsuyâ:BAAALAAECgIIAwAAAA==.',Te='Teapot:BAAALAAECgMIAgAAAA==.Tedoseirum:BAAALAAECgYIDAAAAA==.Terani:BAAALAADCgcIBwAAAA==.Texasbilly:BAAALAADCgIIAgAAAA==.',Th='Thalch:BAAALAADCggIDgAAAA==.Thedtwo:BAAALAAECgMIBQAAAA==.Theprayer:BAAALAAECgIIAgAAAA==.Thereaping:BAAALAAECgMIAwAAAA==.Thorgarrus:BAAALAAECggIEQAAAA==.Thundernips:BAAALAADCgMIAwABLAAECgEIAQADAAAAAA==.',Ti='Tigerwoodz:BAAALAAECggIDQAAAA==.Timemend:BAAALAADCgMIAwAAAA==.Timithicus:BAAALAADCgMIAwAAAA==.Tinada:BAAALAADCggICAABLAAECggIFQALAP0cAA==.',To='Toddie:BAAALAAECgYICQAAAA==.Tolkarnyx:BAAALAAECgYIBgAAAA==.Tolkein:BAAALAADCggICAAAAA==.Tormod:BAAALAAECgMIBAAAAA==.Tormodd:BAAALAADCggIDwAAAA==.',Tr='Trashypanda:BAAALAAECgMIAwABLAAFFAIIAgADAAAAAA==.Treeleaves:BAAALAADCgYIBgABLAAECgMIBQADAAAAAA==.Treniity:BAAALAAECgMIAgAAAA==.Tristanyia:BAAALAADCgcIDQAAAA==.Trogdorr:BAAALAADCggIDgABLAAECgcIDwADAAAAAA==.Trutert:BAAALAADCggIDQAAAA==.Tryana:BAAALAAECgIIAwAAAA==.Trüe:BAAALAADCgcIBwAAAA==.',Tu='Tust:BAAALAAECgYIBgAAAA==.',Tw='Twentynine:BAAALAAECgYICQAAAA==.Twistedkilla:BAAALAADCggIDQAAAA==.',Ty='Tylla:BAAALAADCggIDgABLAAECgcIFAAHAMwZAA==.Tyr:BAAALAAECgcIEQAAAA==.Tyrnova:BAAALAADCggIDgAAAA==.',Uk='Ukog:BAAALAAECgIIAgAAAA==.',Ul='Ultrear:BAAALAADCgcIBwAAAA==.',Um='Umbravolt:BAAALAAECggIEQAAAA==.Umpreaker:BAAALAADCgYIBgAAAA==.',Un='Unmoose:BAAALAADCggICgAAAA==.',Ur='Uruchi:BAAALAADCggIEAAAAA==.',Uu='Uutimage:BAAALAADCgcIBwAAAA==.',Va='Vakero:BAAALAAECgIIAwAAAA==.Valinorah:BAAALAAECgYIDAAAAA==.Valthrax:BAAALAAECggICQAAAA==.Vanitas:BAAALAADCgQIBAAAAA==.Varada:BAAALAADCggIDgABLAAECgcIEAADAAAAAA==.Varï:BAAALAADCgYIBgAAAA==.',Ve='Velordis:BAAALAAFFAEIAQAAAA==.',Vi='Victaria:BAAALAAECgcICwAAAA==.Viridesa:BAAALAADCgcICAAAAA==.Vitalism:BAAALAADCgYIBgAAAA==.Vivianvande:BAAALAAECgMIBQAAAA==.Vixine:BAAALAAECgMIAgAAAA==.',Vo='Voidbacon:BAAALAADCggICAAAAA==.Voidoftaco:BAAALAAECgIIAgAAAA==.Vortex:BAAALAAECgMIBAAAAA==.',Wa='Warfarmer:BAAALAAECgIIAgAAAA==.Warhawke:BAAALAADCgMIAwAAAA==.',Wc='Wcmocha:BAAALAADCgUIBQABLAAECgIIAgADAAAAAA==.',We='Weak:BAAALAAECgEIAQAAAA==.',Wh='Wheresdparty:BAAALAADCgcICQABLAADCggICAADAAAAAA==.Whis:BAAALAAECgIIAgAAAA==.Whò:BAAALAAECgEIAQABLAAECgYICgADAAAAAA==.',Wi='Wiimage:BAAALAAECgYICgABLAAECggIFgASAFwbAA==.Wiivinelight:BAABLAAECoEWAAISAAgIXBvCBACNAgASAAgIXBvCBACNAgAAAA==.Willymshatna:BAAALAADCgMIAwAAAA==.',Wo='Wondersk:BAAALAADCgMIAwAAAA==.',Wy='Wyrmweaver:BAAALAADCgcIBwAAAA==.',['Wå']='Wåffle:BAAALAAECggIEQAAAA==.',Xa='Xandari:BAAALAAECgMIAwAAAA==.Xannafer:BAAALAADCgcIBwAAAA==.Xannah:BAABLAAECoEUAAIHAAgIrCOzAQA6AwAHAAgIrCOzAQA6AwAAAA==.Xannefer:BAAALAADCgMIAwAAAA==.Xanpo:BAAALAAECgYIBgAAAA==.Xantrys:BAAALAAECgIIBAAAAA==.',Yc='Yce:BAAALAAECgIIAgAAAA==.',Ye='Yeâh:BAAALAAECgYICgAAAA==.',Yo='Yoker:BAAALAAECgUIBQAAAA==.',Yu='Yucan:BAAALAADCggICAAAAA==.',Za='Zaelagos:BAAALAADCgcIBwAAAA==.Zalorea:BAAALAADCggIGgAAAA==.Zamrog:BAAALAAECggIEQAAAA==.Zamthyr:BAAALAADCggIEAABLAAECggIEQADAAAAAA==.Zanya:BAAALAADCgcIBwAAAA==.',Ze='Zenez:BAAALAADCgQIBAAAAA==.Zestychip:BAAALAADCgYICgAAAA==.Zethia:BAAALAADCgQIBAAAAA==.Zexor:BAAALAADCgEIAQAAAA==.',Zh='Zhaoyun:BAAALAAECgIIAgAAAA==.',Zi='Zilkir:BAAALAAECgcIEAAAAA==.Zimdrovic:BAAALAADCggIBwAAAA==.Zivadhim:BAAALAADCgcICAAAAA==.',Zl='Zlyth:BAAALAADCggIDgAAAA==.',Zo='Zould:BAAALAAECgYIEAAAAA==.',Zu='Zugger:BAAALAADCgcIBwAAAA==.Zuzuheals:BAAALAAECgYIBgAAAA==.Zuzzlin:BAAALAADCgMIAwAAAA==.',['Åi']='Åitrix:BAAALAADCggIFAAAAA==.',['Ðe']='Ðestro:BAAALAADCgQIBAAAAA==.',['Ðr']='Ðr:BAAALAAECgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end