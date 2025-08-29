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
 local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Arcane','Paladin-Holy','Mage-Frost','Priest-Holy','Shaman-Elemental',}; local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abinitio:BAAALAADCggIEAAAAA==.Abintol:BAAALAADCgIIAgABLAAECgUIBQABAAAAAA==.',Ac='Acharon:BAAALAAECgQIBgAAAA==.Ackee:BAAALAADCggICQAAAA==.',Ad='Ad:BAAALAAECgMIAwAAAA==.Addelaide:BAAALAAECgYICQAAAA==.',Ae='Aeslin:BAAALAAECgEIAQAAAA==.',Ai='Airbaxhdh:BAAALAADCgcIDQAAAA==.',Ak='Akaya:BAAALAAECgMIAwABLAAFFAIIAgABAAAAAA==.',Al='Alarashinu:BAAALAAECgYICQAAAA==.Alawaeh:BAAALAAECgQICAAAAA==.',An='An:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.Anahit:BAAALAADCgYIBgAAAA==.',Ar='Ar:BAACLAAFFIEFAAICAAMIVg04AwDRAAACAAMIVg04AwDRAAAsAAQKgRgAAgIACAj6IyQdAH4BAAIACAj6IyQdAH4BAAEsAAQKAwgDAAEAAAAA.Archimetes:BAAALAADCgcIBQAAAA==.Aretas:BAAALAAECgMIBAABLAAECgMIBwABAAAAAA==.Arkøn:BAAALAADCgIIAgAAAA==.',As='Ashikaga:BAAALAAECgMIBAAAAA==.Asifa:BAAALAADCggIFgAAAA==.',At='Atherion:BAAALAAECgQIBAAAAA==.Attackroot:BAAALAAECgIIAgAAAA==.',Av='Aveticus:BAAALAADCggICAAAAA==.Avranarada:BAAALAAECgUICAAAAA==.',Ax='Axmann:BAAALAADCggICQAAAA==.',Az='Azarondel:BAAALAADCgcIBwAAAA==.Azbjorn:BAAALAADCggICAAAAA==.Azralia:BAAALAAECgYICgAAAA==.Azung:BAAALAADCgYICQAAAA==.',['Aú']='Aústin:BAAALAADCgUIBQAAAA==.',Ba='Baalial:BAAALAADCgYIBgAAAA==.Babaisyaga:BAABLAAECoEVAAIDAAgIwCDHDQCKAgADAAgIwCDHDQCKAgAAAA==.Baka:BAAALAAECgMIBgAAAA==.Balinse:BAAALAAECgIIAwAAAA==.Banua:BAAALAADCggIFAAAAA==.Barb:BAAALAADCgEIAQAAAA==.Barrelrollin:BAAALAAECgMIBgAAAA==.Batrito:BAAALAAECgMIAwABLAAECgYIDgABAAAAAA==.',Be='Bealzebubbà:BAAALAAECgIIAgAAAA==.Beastfodays:BAAALAADCgEIAQAAAA==.Beaumont:BAAALAADCgcIBwAAAA==.Bebitte:BAAALAADCggICAAAAA==.Becina:BAAALAAECgIIBAABLAAECgcIEwABAAAAAA==.Beyorn:BAAALAADCggIEQAAAA==.',Bi='Bigbeans:BAAALAADCgcIDQAAAA==.Billcosbrew:BAAALAADCgYICgABLAAECgcIDwABAAAAAA==.',Bj='Bjorinn:BAAALAAECggICAAAAA==.',Bl='Blessphemous:BAAALAADCgcIBwAAAA==.Blizzcon:BAAALAAECgMIBQAAAA==.',Bo='Boone:BAAALAAECgMIAwAAAA==.Borrgar:BAAALAAECgMIBgAAAA==.',Br='Bracori:BAAALAAFFAEIAQAAAA==.Brago:BAAALAADCgcIBwAAAA==.Brandywynne:BAAALAAECgYICQAAAA==.Brick:BAAALAAECgYICQAAAA==.Brightfame:BAAALAAECgYICQAAAA==.Bronny:BAAALAAECgIIAwAAAA==.Brownpepperz:BAAALAAECgMIBwAAAA==.',Bu='Buffshagwell:BAAALAADCgQIBAAAAA==.',Ca='Calypsio:BAAALAAECgMIBgAAAA==.Candyballs:BAAALAADCgcICAABLAAECgIIAwABAAAAAA==.Captinboomie:BAAALAADCgMIAwAAAA==.Caretakerz:BAAALAADCggICAAAAA==.Carrey:BAAALAADCgYICQAAAA==.',Ce='Cedre:BAAALAADCgUIBgAAAA==.',Ch='Cheesepuff:BAAALAAECgMIAwAAAA==.Cheeto:BAAALAADCgcIDQABLAAECgIIAwABAAAAAA==.Chellevil:BAAALAAECgMIAwAAAA==.',Ci='Cindera:BAAALAAECgIIAgABLAAECgcIFAAEAHYjAA==.Cirï:BAAALAAECgMIAwAAAA==.',Cn='Cntendr:BAAALAAECgMIBAAAAA==.',Co='Codenike:BAAALAAECgIIAgAAAA==.Corelheals:BAAALAADCgUIAQAAAA==.Covertyqt:BAAALAAECgUICAAAAA==.Coyote:BAAALAAECgEIAQAAAA==.',Cp='Cptnhuman:BAAALAAECgUICAAAAA==.',Cr='Cromie:BAAALAAECgEIAQAAAA==.Crunk:BAAALAAECgcIDAAAAA==.Cryptis:BAAALAAECggIAgAAAA==.',Cu='Cursedbear:BAAALAAECgYICgAAAA==.Curvos:BAAALAAECgYIBgAAAA==.',Cy='Cyndal:BAAALAADCgYIBgAAAA==.',Da='Daboof:BAAALAADCgcIEQAAAA==.Daggere:BAAALAADCggIEwAAAA==.Darkenmicky:BAAALAAECgIIBAAAAA==.Darkmickyz:BAAALAADCggIEgAAAA==.Darthbobula:BAAALAAFFAEIAQAAAA==.Dashing:BAAALAAECgYIBgAAAA==.Dashwilder:BAAALAADCgcIBwAAAA==.Dayloc:BAAALAAECgUICAAAAA==.Daédalús:BAAALAADCgYIBgAAAA==.',Db='Dbdabeast:BAAALAADCggIDgAAAA==.',De='Deawin:BAAALAADCgYIBgABLAAECgMIBgABAAAAAA==.Delitta:BAAALAADCggIFwAAAA==.Demontyk:BAAALAAECgIIAwAAAA==.',Dh='Dhunter:BAAALAAFFAEIAQAAAA==.',Di='Diablõ:BAAALAAECgUICAAAAA==.',Dl='Dl:BAAALAAECgYICQAAAA==.',Do='Donkeylove:BAAALAAECgIIBAAAAA==.Doomsdayy:BAAALAADCggIDwAAAA==.Dotdotgoose:BAAALAADCggICgAAAA==.',Dr='Draccarys:BAAALAAECgQIBAAAAA==.Drakkarr:BAAALAADCgYIBgAAAA==.Drogthief:BAAALAADCgcIBwAAAA==.Droowin:BAAALAADCgYIBgABLAAECgMIBgABAAAAAA==.',Dw='Dworg:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.',['Dò']='Dòóm:BAAALAADCgcIBgAAAA==.',Ea='Earlgrey:BAAALAADCgUIBQAAAA==.',Eb='Ebullition:BAAALAAECgEIAQAAAA==.',Ed='Edgypriest:BAAALAAECgUIBQAAAA==.',Ei='Eigi:BAAALAADCggIDAAAAA==.',Ek='Ekthelion:BAAALAAECgIIBAAAAA==.',El='Eldanon:BAAALAAECgYICwAAAA==.Elela:BAAALAADCggICQAAAA==.Elistann:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.Elwe:BAAALAAECgIIAwAAAA==.',En='Enkidu:BAAALAAECgMIBgAAAA==.Enseth:BAAALAAECgMIBAAAAA==.',Er='Erazen:BAAALAADCggICAAAAA==.',Es='Esme:BAAALAAECgYICQAAAA==.',Et='Ethir:BAAALAAECggICwAAAA==.',Eu='Euryleia:BAAALAADCggIDwAAAA==.',Fa='Faeriefox:BAAALAADCggIEwAAAA==.Fairious:BAAALAAECgQIBQAAAA==.Fallenstar:BAAALAAECgMIBQAAAA==.Fangrell:BAAALAADCgYIAgABLAAECgMIAwABAAAAAA==.Faror:BAAALAADCggICQAAAA==.',Fe='Felcon:BAAALAADCgcIDQAAAA==.Fennec:BAAALAADCggIFwAAAA==.Fenrirr:BAAALAADCgMIAwABLAAECgMIBgABAAAAAA==.Fet:BAAALAAFFAIIAgAAAA==.Feyu:BAAALAADCgcIDQABLAAECgQIBQABAAAAAA==.',Fl='Flashfiré:BAAALAADCgYICgAAAA==.Floss:BAAALAADCggIDAABLAAECgEIAQABAAAAAA==.Flöti:BAAALAAECgQIBQAAAA==.',Fn='Fngusamungus:BAAALAAECgIIBAAAAA==.',Fo='Forsehtti:BAAALAADCgQIBAAAAA==.',Fr='Frysky:BAAALAADCgUIBQAAAA==.',Fu='Futz:BAAALAAECgYICQAAAA==.',Fy='Fyrr:BAAALAADCgcIDwAAAA==.',Ga='Gahnzul:BAAALAADCgcICAAAAA==.Gajeèl:BAAALAADCggIEAABLAAECggIEAABAAAAAA==.Gajitbek:BAAALAADCgcIBwAAAA==.Galadriell:BAAALAAECgEIAQAAAA==.',Go='Gooberz:BAAALAAECgIIAgAAAA==.',Gr='Grabbygranny:BAAALAAECgYIDgAAAA==.Gravewin:BAAALAADCgYIDAABLAAECgMIBgABAAAAAA==.Graveytrain:BAAALAAECgcIEwAAAA==.Grendelheim:BAAALAADCgcIEQAAAA==.Groedari:BAAALAADCggIFQAAAA==.',Gu='Gula:BAAALAADCgcIBwAAAA==.Gurg:BAAALAAECgEIAQAAAA==.',Ha='Halfpanda:BAAALAAECgMIAwAAAA==.Harborseal:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Hathaendron:BAAALAADCgMIAwAAAA==.Havikuugamik:BAAALAAECggICwAAAA==.',Ho='Holyyballs:BAAALAAECgIIAwAAAA==.Hotrodbob:BAAALAADCgcICAAAAA==.',['Há']='Hálfpint:BAAALAADCggIEAAAAA==.',['Hì']='Hìroko:BAAALAADCggIEAAAAA==.',Ia='Iaaryn:BAAALAADCgYIBgAAAA==.',Ib='Iblees:BAAALAAECgYICQAAAA==.',Id='Idkmyname:BAAALAADCgIIAgAAAA==.',In='Infinitie:BAAALAADCgMIAwAAAA==.',Ir='Iroh:BAAALAAECgIIAwAAAA==.',Is='Ishewtyou:BAAALAADCgYICAABLAADCggIDQABAAAAAA==.',Ja='Jacii:BAAALAAECgUICAAAAA==.Jargathan:BAAALAADCggIDgAAAA==.Jarinduva:BAAALAADCgUIBgAAAA==.Jawnson:BAAALAAECgMIBgAAAA==.',Je='Jenefer:BAAALAAFFAEIAQAAAA==.',Jo='Jonav:BAAALAADCgcICwAAAA==.Jondooss:BAAALAADCgMIAwAAAA==.Josefina:BAAALAADCggICAAAAA==.',Ju='Jubelum:BAAALAADCgUIBgAAAA==.',Ka='Kailback:BAAALAAECgMIBgAAAA==.Kailiana:BAAALAADCgIIAgAAAA==.Kalcifur:BAABLAAECoEUAAIFAAgI7RdCDgDmAQAFAAgI7RdCDgDmAQAAAA==.Kastiel:BAAALAADCgEIAQABLAAECgIIAwABAAAAAA==.Kathtel:BAAALAADCgcIBwAAAA==.Katleara:BAAALAADCgcIDgAAAA==.Katstrider:BAAALAAECgMIBQAAAA==.',Ke='Keldean:BAAALAAECgUICgAAAA==.Keryka:BAAALAAECggIDQAAAA==.',Kh='Khall:BAAALAAECggIEgAAAA==.',Ki='Kifkroker:BAAALAADCggIFwAAAA==.Kileedragone:BAAALAADCgQIAwAAAA==.Kirøs:BAAALAAECggICAAAAA==.Kiterisa:BAAALAAECgUICAAAAA==.Kiti:BAAALAAECgMIAwABLAAECgMIBgABAAAAAA==.',Ko='Kohn:BAAALAAECgMIAwAAAA==.Kona:BAAALAADCgEIAgABLAAECgUICAABAAAAAA==.',Ky='Kylyra:BAAALAAECgYICwABLAAFFAEIAQABAAAAAA==.',['Ká']='Kákashí:BAAALAADCgIIAgABLAADCggIFwABAAAAAA==.',La='Ladýfinger:BAAALAAECgEIAQABLAAFFAEIAQABAAAAAA==.Laisidhiel:BAAALAADCggIFwAAAA==.Lani:BAAALAADCgcIBwAAAA==.Lariel:BAAALAADCggIDwAAAA==.Laruna:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.Lawz:BAAALAAECgEIAQAAAA==.',Le='Lelianna:BAAALAADCgcIEQAAAA==.Leshafrierne:BAAALAAECgMIAwAAAA==.Lexia:BAAALAAECgIIBAAAAA==.',Li='Lilani:BAAALAADCgMIAwAAAA==.Lilturtz:BAAALAAECgEIAQAAAA==.',Ll='Llorien:BAAALAADCgcIBwAAAA==.',Lo='Locksative:BAAALAADCgcIDwABLAADCggIDQABAAAAAA==.Longhorn:BAAALAADCggIEQAAAA==.Loni:BAAALAADCggICAAAAA==.Lorriena:BAAALAADCgYIBgAAAA==.Lortpegsalot:BAAALAAECggIEAAAAA==.',Lu='Lucina:BAAALAAECgMIBgAAAA==.Luluz:BAAALAADCgYIEAAAAA==.',Ma='Madamkluck:BAAALAAECgIIAgAAAA==.Maglubiyet:BAAALAAECgIIAgAAAA==.Manhole:BAAALAAECgIIAwAAAA==.Markyb:BAAALAAECgUICAAAAA==.Masamura:BAAALAAFFAEIAQAAAA==.Masaria:BAAALAADCggICQABLAADCggIDAABAAAAAA==.Maureanna:BAAALAAECgcIEwAAAA==.',Me='Meapstor:BAAALAAECgYICQAAAA==.Medanii:BAAALAADCggIBwAAAA==.Meno:BAAALAAECgMIBwAAAA==.Meriana:BAAALAADCgcIDgAAAA==.',Mi='Milnova:BAAALAADCggICwAAAA==.Mireille:BAAALAADCgcIDQAAAA==.Mitzuky:BAAALAAECgEIAQAAAA==.',Mo='Mogsmage:BAAALAADCgcICAAAAA==.Monkeypeach:BAAALAADCgYICwAAAA==.Monstertruck:BAAALAADCgcICwAAAA==.Moocifer:BAAALAADCgQIBAAAAA==.Morganlefay:BAAALAADCggIDAAAAA==.Morlyn:BAAALAAECgIIAwAAAA==.Morregan:BAAALAAECgEIAQAAAA==.Mousemist:BAAALAAECgMIBQAAAA==.',My='Mystìc:BAAALAAECgIIAwAAAA==.',['Má']='Májorrobot:BAAALAADCggIDQAAAA==.',Na='Nadi:BAAALAAECgUICAAAAA==.Namesgambit:BAAALAAECgcIDwAAAA==.Navia:BAAALAADCggIEwAAAA==.',Ne='Nedtusk:BAAALAAECgQIBQAAAA==.Nedyan:BAAALAADCgcIBwABLAAECgQIBQABAAAAAA==.Nemein:BAAALAADCgEIAQAAAA==.Nenji:BAAALAAECgIIAgABLAAECgEIAQABAAAAAA==.Nessà:BAAALAADCgYIBwABLAADCgcIBwABAAAAAA==.Neveenn:BAAALAAECgUICAAAAA==.Neverbakdown:BAAALAADCgMIAwAAAA==.',Ni='Ninithepooh:BAAALAAECgYIBgAAAA==.Nirith:BAAALAADCgYIBgAAAA==.Niteskye:BAAALAADCgEIAQABLAADCgUIBQABAAAAAA==.',No='Notoom:BAAALAADCggIDQAAAA==.',Ny='Nyaria:BAAALAADCggIDAAAAA==.Nyxara:BAAALAADCgcICgAAAA==.',['Nè']='Nèzukõ:BAAALAAECgIIAwAAAA==.',Ob='Oba:BAAALAADCgcIBwAAAA==.Obata:BAAALAAECgYIDgAAAA==.',Oj='Ojore:BAEALAAECgIIAgAAAA==.Ojoverde:BAAALAAFFAEIAQAAAA==.',Op='Ophillã:BAAALAADCgYICwABLAADCgcIBwABAAAAAA==.',Or='Ordenn:BAAALAAFFAEIAQABLAAFFAIIAgABAAAAAA==.Orengo:BAAALAAECgEIAQAAAA==.',Ov='Overflare:BAAALAADCgcICgAAAA==.',Pa='Pashnir:BAAALAADCgcICQAAAA==.',Pe='Peachey:BAAALAAECgEIAQAAAA==.Peakra:BAAALAADCgEIAQAAAA==.Persephonnie:BAAALAADCgMIBQAAAA==.Petty:BAAALAADCgcIBwAAAA==.',Ph='Phrantic:BAAALAAECggICwAAAA==.',Pi='Pigas:BAAALAAECgMIBwAAAA==.',Pl='Platinïum:BAAALAAECgIIAgAAAA==.',Po='Poseidon:BAAALAAECgIIAwAAAA==.',Pr='Prestbyter:BAAALAADCgQIBAAAAA==.Prestoresto:BAAALAAECgMIBQAAAA==.Priestling:BAAALAADCggICAAAAA==.Prophetic:BAAALAADCgMIAwAAAA==.',Ps='Psi:BAAALAAECgMIBgAAAA==.Psychros:BAAALAAECgEIAQAAAA==.',['Pé']='Pésto:BAAALAADCggICAAAAA==.',Qu='Quijon:BAAALAADCgUIBQAAAA==.Quinberos:BAAALAAECgEIAQABLAAECgUIBQABAAAAAA==.Quårantine:BAAALAADCggICAAAAA==.',Ra='Radhoc:BAAALAAECgIIAgAAAA==.Ramdel:BAAALAAECgMIBQAAAA==.Ramstryder:BAAALAADCggIDwABLAAECgMIBQABAAAAAA==.Rayycharles:BAAALAADCggIDwABLAAECgcIDwABAAAAAA==.Rayziel:BAAALAAECgMIAwAAAA==.Razorlore:BAAALAAECgEIAQAAAA==.',Re='Rengell:BAAALAAECgMIAwAAAA==.Replink:BAAALAAECgYICAAAAA==.',Rh='Rheagnar:BAABLAAECoEUAAIDAAgICCFqBwDrAgADAAgICCFqBwDrAgAAAA==.',Ri='Rizemage:BAAALAAECgIIAgAAAA==.',Ro='Robobob:BAAALAAECgEIAQAAAA==.Rosana:BAAALAADCgQIBAABLAADCggIDAABAAAAAA==.Rowynna:BAAALAAECgUIBQAAAA==.',Ry='Ryzedbear:BAAALAAECgIIAgAAAA==.',['Rý']='Rýoko:BAAALAADCgUIBQAAAA==.',Sa='Safaria:BAAALAAECgMIBQAAAA==.Saloenus:BAAALAADCgEIAQAAAA==.Sauceyho:BAAALAADCgMIAwAAAA==.Saucymac:BAAALAAFFAEIAQAAAA==.',Sc='Scandal:BAAALAADCgUIBgAAAA==.',Se='Serak:BAAALAAECgMIBgAAAA==.',Sh='Shadowflame:BAAALAADCggICAAAAA==.Shallator:BAAALAAECgIIAwAAAA==.Shamanigans:BAAALAAECgYIBgAAAA==.Shammygoat:BAAALAAECgIIAgAAAA==.Shaqattack:BAAALAAECgYIDQAAAA==.Shaqattaq:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.Sharkadin:BAAALAAECgMIBQAAAA==.Shawnella:BAAALAAECgUIBQAAAA==.Shawntelle:BAAALAAECgMIAwAAAA==.Sheephappens:BAAALAADCgYIBgAAAA==.Shifflegnome:BAAALAAECgYIDAAAAA==.Shinaie:BAAALAAECgIIBAAAAA==.',Si='Sigrunn:BAAALAAECgYICwAAAA==.Sigzil:BAAALAAECgIIAgAAAA==.Silth:BAAALAADCgcICgAAAA==.',Sk='Skox:BAAALAADCgcIBwAAAA==.',Sm='Smmoke:BAAALAAECgUICAAAAA==.',Sn='Sneekypally:BAAALAADCgcIDgAAAA==.Sniperart:BAAALAAECgMIBwAAAA==.',So='Soap:BAAALAADCgYIBgAAAA==.Solrithia:BAAALAADCgcIBwAAAA==.Sordid:BAAALAAECgIIAgAAAA==.Soull:BAAALAAECgMIBwAAAA==.',Sp='Spacemilkman:BAAALAAECgIIBAAAAA==.Spliffinator:BAAALAADCggIDwAAAA==.',St='Starface:BAAALAAFFAEIAQAAAA==.Stellaria:BAAALAAECgMIBgAAAA==.Steverogers:BAAALAADCgYIBgABLAAECgcIDwABAAAAAA==.Strongbad:BAAALAADCggICwAAAA==.Sturmx:BAAALAAECgUICAAAAA==.',Su='Supergenius:BAAALAADCgcIBwAAAA==.Superkingchi:BAAALAADCgQIBgAAAA==.',Ta='Talila:BAAALAAECgMIBwAAAA==.Tankbear:BAAALAAECgQIBQAAAA==.Tasselhof:BAAALAADCgIIAgAAAA==.Tazend:BAAALAADCgQIBAAAAA==.',Te='Teryail:BAAALAADCgcIBwAAAA==.',Th='Thailong:BAAALAADCgcIBwAAAA==.Thaqknight:BAAALAAECgMIBwAAAA==.Thedemon:BAAALAADCgYIAQAAAA==.Thorran:BAAALAADCggIDAAAAA==.',Ti='Tickle:BAAALAAECgIIBAAAAA==.Tidiboom:BAAALAADCgcIDAAAAA==.',To='Tockell:BAAALAADCgMIAwAAAA==.Torbin:BAAALAAECgIIAwAAAA==.',Tp='Tpaartoz:BAAALAADCgMIAwAAAA==.',Tr='Trasi:BAAALAAECgMIAwAAAA==.Trichinella:BAAALAADCgcIBwABLAAECgMIBwABAAAAAA==.Trollishways:BAAALAAECgMIAwAAAA==.Tryjincks:BAAALAAECgQIBQAAAA==.',Ts='Tsukibearr:BAAALAAECgMIAwAAAA==.',Tu='Tusky:BAAALAADCgEIAQAAAA==.',Ty='Tykahndrius:BAAALAADCgcIDAAAAA==.',['Tú']='Túsk:BAAALAAECgMIBAAAAA==.',['Tý']='Týlius:BAAALAAECgQIBQAAAA==.',Ul='Ultima:BAAALAADCgUIBQAAAA==.',Un='Unspokenword:BAAALAADCgUIBQAAAA==.',Ut='Uthilon:BAAALAAECgUICAAAAA==.',Uw='Uwudan:BAAALAAECgMIAwAAAA==.',Va='Valdare:BAAALAAECgMIBgAAAA==.Validorn:BAAALAADCgYICgAAAA==.Vampgodxx:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Varrielim:BAAALAADCgcIBwAAAA==.',Ve='Vedillian:BAAALAADCggIDwAAAA==.Velskor:BAAALAAECgYIDAAAAA==.Venomcarnage:BAAALAADCgMIBQAAAA==.',Vi='Victorr:BAAALAAECgYICAAAAA==.Vierna:BAAALAADCggIDwAAAA==.Vite:BAAALAADCgUIBgAAAA==.',Vo='Voladon:BAAALAAECgYICQAAAA==.Voyana:BAAALAAECgMIBQABLAAECgMIBQABAAAAAA==.',Vy='Vydragon:BAAALAADCgcIBwAAAA==.Vymage:BAABLAAECoEUAAMEAAcIdiPZEQCMAgAEAAcIdiPZEQCMAgAGAAEISBLNQwA2AAAAAA==.Vyrubur:BAAALAADCggIBgABLAAECgcIFAAEAHYjAA==.',['Vá']='Válidüs:BAABLAAECoEZAAIHAAgIDRkpDQBgAgAHAAgIDRkpDQBgAgAAAA==.',['Vã']='Vãsh:BAAALAADCggIFQAAAA==.',Wa='Warlockey:BAAALAAECgMIBAAAAA==.Warninja:BAAALAAECgIIAgAAAA==.Waterloo:BAAALAADCgcIEAAAAA==.',Wi='Widger:BAAALAADCggIDwAAAA==.Wildboom:BAAALAAECgIIAgAAAA==.',Wo='Worfern:BAAALAADCgUIBgAAAA==.',Wr='Wrathomatic:BAAALAADCgUIBQAAAA==.',Ye='Yerty:BAAALAAECgUICQAAAA==.',Za='Zashawa:BAAALAADCgQIBAAAAA==.Zashen:BAAALAADCggICAAAAA==.',Ze='Zenithgrey:BAAALAAECgYIBgAAAA==.',Zl='Zluck:BAAALAADCgYIBgABLAAECggIFwAIAJYjAA==.Zluco:BAABLAAECoEXAAIIAAgIliNrBQAQAwAIAAgIliNrBQAQAwAAAA==.',Zy='Zyzzler:BAAALAAECgUICQAAAA==.',['Zà']='Zàp:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end