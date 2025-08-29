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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','Shaman-Elemental','Mage-Arcane','Paladin-Retribution','Hunter-BeastMastery','Priest-Holy','Shaman-Restoration','Priest-Shadow',}; local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aadrise:BAAALAADCgcIFQAAAA==.Aaramis:BAAALAAECgYICQAAAA==.',Ab='Abandyn:BAAALAAECgIIBAAAAA==.',Ac='Aceallia:BAAALAAECgEIAQAAAA==.Acidevil:BAAALAADCgcIBwAAAA==.',Ad='Adrisehunt:BAAALAADCgEIAgAAAA==.',Ae='Aerynxa:BAAALAADCggIDAAAAA==.',Al='Aldoladre:BAAALAAECgEIAQAAAA==.Alluraxis:BAAALAADCgcIBwAAAA==.',Am='Amadayus:BAAALAAECgQIBAAAAA==.Amaging:BAAALAAECgIIAwAAAA==.Amagingdoom:BAAALAAECgQIBAAAAA==.Amarïe:BAAALAADCggICAAAAA==.',An='Angolii:BAAALAADCgEIAQAAAA==.Angrybox:BAAALAADCgIIAgAAAA==.',Ar='Aranyssa:BAAALAAECgEIAQAAAA==.Arkaÿne:BAAALAADCgcIBwAAAA==.Arki:BAAALAADCggIDgAAAA==.Arkork:BAAALAADCggIDwAAAA==.',As='Ashenbloom:BAAALAADCgcICgAAAA==.Ashurandal:BAAALAADCgcIDgABLAADCggIEgABAAAAAA==.Asiago:BAAALAAECgEIAQABLAAECgYICgABAAAAAA==.Aspect:BAAALAADCggIDQAAAA==.Astralnaut:BAAALAADCgcIBwAAAA==.',At='Atiesh:BAAALAAECggIBQAAAA==.',Au='Aulora:BAAALAAECgMIAwAAAA==.',Ay='Aylasha:BAAALAADCgQIBAAAAA==.',Az='Azenet:BAAALAADCggIEAABLAAECggIGAACAAsaAA==.Azogthorror:BAAALAADCggIDwAAAA==.',Ba='Banecroft:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Barackoshama:BAAALAAECgcIDgAAAA==.Barfdrinker:BAAALAADCgQIBQAAAA==.Batrastard:BAAALAAECgYICgAAAA==.Battlescars:BAAALAAECgYIBwAAAA==.Baw:BAAALAAECgcICQAAAA==.',Bd='Bdelp:BAAALAADCggICQAAAA==.',Be='Belfiyajr:BAAALAAECggIAgAAAA==.Bellátrix:BAAALAADCgMIAwAAAA==.Bernham:BAAALAADCgEIAQAAAA==.',Bi='Bigskyrogue:BAAALAAECgMIBAAAAA==.',Bl='Blackstaar:BAAALAAECgEIAQAAAA==.Blackwÿn:BAAALAADCgYIBgAAAA==.Bladedozzer:BAAALAADCgcIBwAAAA==.Blindinglite:BAAALAADCggICQAAAA==.Blindtoast:BAAALAAECgIIAgAAAA==.Bloodx:BAAALAADCggICgAAAA==.Bloodypala:BAAALAADCggICAAAAA==.Blorp:BAAALAADCggIDQAAAA==.Bluehair:BAAALAADCgEIAQAAAA==.',Bo='Bobertz:BAAALAADCggIFwAAAA==.Bombil:BAAALAADCgYIBwAAAA==.Bowmcshooty:BAAALAAECgYICwAAAA==.',Br='Brawlbuff:BAAALAADCgYIBwAAAA==.Brieter:BAAALAAECgYICgAAAA==.Bringo:BAAALAADCgMIAwAAAA==.Briss:BAAALAADCgQIBAAAAA==.Brohmz:BAAALAADCggICAAAAA==.Brotheldog:BAAALAAECgMIAwAAAA==.',Bu='Bumpski:BAAALAAECgIIAwAAAA==.',Ca='Calabane:BAAALAADCgcIBwAAAA==.Calagon:BAAALAADCggICAAAAA==.Calculated:BAAALAAECgMIBQABLAAECgYICwABAAAAAA==.Camipriest:BAAALAAECgUICwAAAA==.Canabliss:BAAALAADCgYIBgAAAA==.Carnage:BAAALAAECgMIBwAAAA==.Cassiann:BAAALAADCgEIAQAAAA==.',Ce='Ceredor:BAAALAADCggICAABLAAECgYICAABAAAAAA==.',Ch='Chairon:BAAALAAECgEIAgAAAA==.Cheesus:BAAALAAECgYICAABLAAECgYICgABAAAAAA==.Chiani:BAAALAADCgMIAwABLAADCgQIBAABAAAAAA==.Chilepeludo:BAAALAADCgIIAgAAAA==.Chipsnsalsa:BAAALAAECgYICwAAAA==.Chocoriffic:BAAALAAECgYICQABLAAECgYICwABAAAAAA==.',Ci='Cindeth:BAAALAADCggIDAABLAADCggIEAABAAAAAA==.',Co='Coko:BAAALAAECgQICgABLAAECgYICAABAAAAAA==.Condemned:BAAALAADCgYIBgAAAA==.',Cp='Cptsnorlax:BAAALAADCgIIAgAAAA==.',Cr='Crackjones:BAAALAADCggICgAAAA==.Creatine:BAAALAADCgMIAwAAAA==.Crinessandra:BAAALAAECgEIAQAAAA==.Crisgmt:BAAALAAECgcIDgAAAA==.Crul:BAAALAADCggIEAAAAA==.Cryptìc:BAAALAAECgIIAgABLAAECggIDgABAAAAAA==.Cryptîc:BAAALAAECggIDgAAAQ==.Crâckjones:BAAALAADCgMIAwAAAA==.',Cu='Cujak:BAAALAAECgcICwAAAA==.',Cy='Cynesdeyn:BAAALAADCggICQAAAA==.',Da='Daekoo:BAABLAAECoEXAAIDAAgINh23CQC5AgADAAgINh23CQC5AgAAAA==.Dalranirn:BAAALAAECgUICAAAAA==.Dancelock:BAAALAADCgIIAgAAAA==.Dandingledon:BAAALAADCgcIBwAAAA==.Darkleche:BAAALAADCgcIBwAAAA==.Dartingeagle:BAAALAAECgYIBwAAAA==.Dasmos:BAAALAAECgIIAwAAAA==.Davett:BAAALAAECgcIEAAAAA==.Dawn:BAAALAADCgMIAwAAAA==.',De='Deathballz:BAAALAAECgYICwAAAA==.Deathclawx:BAAALAADCgYICwAAAA==.Deathmaster:BAAALAAECgYIBwAAAA==.Dekustick:BAAALAAECgcIDQAAAA==.Delthrus:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Demonclawx:BAAALAADCgYIBwAAAA==.Dervish:BAAALAADCgIIAgABLAAECggIGAACAAsaAA==.Devatt:BAAALAADCggIDgAAAA==.',Di='Diogenist:BAAALAADCggIFwAAAA==.',Do='Dolire:BAAALAAECgMIAwAAAA==.Doodydood:BAAALAADCgYIDAAAAA==.Dotlover:BAAALAAECgMIBwAAAA==.',Dr='Draconnie:BAAALAADCgcIDAAAAA==.Dragonjade:BAAALAADCggIEwAAAA==.Drakowswitch:BAAALAADCgEIAQAAAA==.Drakyre:BAAALAAECgIIAgAAAA==.Drdrea:BAAALAADCgIIAgAAAA==.Dreadlockqts:BAAALAAECgQIBQAAAA==.Drexybear:BAAALAAECgMIBQAAAA==.Droodballz:BAAALAAECgEIAQABLAAECgYICwABAAAAAA==.Drywall:BAAALAADCgYIBwAAAA==.Drêato:BAAALAADCgcIBwAAAA==.',Du='Dunbarth:BAAALAAECgYIDQAAAA==.Durzaka:BAAALAAECgYIDgAAAA==.',Dv='Dvdcheezemen:BAAALAADCgMIAwAAAA==.',Dw='Dwarfzilla:BAAALAADCgUICAAAAA==.',['Dé']='Dévílyñ:BAAALAADCgQIBgAAAA==.',Ea='Earthdozzer:BAAALAADCgMIAwAAAA==.',Ec='Echofin:BAAALAADCggIEAAAAA==.Echohavo:BAAALAADCggIDAAAAA==.',El='Electricfrst:BAAALAAECgEIAQAAAA==.Elkanàh:BAAALAAECgMIAwAAAA==.Elylla:BAAALAADCggIHgAAAA==.Elyysian:BAAALAAECgQIBgAAAA==.',En='Enter:BAAALAAECgcICgAAAA==.Enñui:BAAALAADCgQIBAAAAA==.',Er='Erhito:BAAALAAECgEIAQAAAA==.Erian:BAAALAADCgMIAwAAAA==.',Es='Essekk:BAABLAAECoEbAAIEAAgI/h3aEACWAgAEAAgI/h3aEACWAgAAAA==.',Eu='Euliana:BAAALAADCggIDwAAAA==.Eulianas:BAAALAADCgcIBwAAAA==.',Ev='Event:BAAALAADCggIFgAAAA==.',Fa='Faithdith:BAAALAADCgQIAwAAAA==.Fatpo:BAAALAADCgQIBAABLAAECgEIAQABAAAAAA==.',Fe='Feartherapto:BAAALAADCgYICAAAAA==.Feyllidan:BAAALAAECgMIBwAAAA==.',Fl='Flashinpan:BAAALAADCgUIBQAAAA==.Flavio:BAAALAADCgMIAgAAAA==.',Fo='Foô:BAAALAAECgcIEgAAAA==.',Fy='Fyafya:BAAALAAECgIIAgAAAA==.Fyah:BAAALAAECgUICAAAAA==.',['Fé']='Féytey:BAAALAAECgcIEAAAAA==.',Ga='Garliforbard:BAAALAAECgYIDQAAAA==.',Ge='Genesis:BAAALAAECggIAgAAAA==.Geobloom:BAAALAADCggICAAAAA==.Gerbic:BAAALAADCgIIAwAAAA==.Gerttie:BAAALAADCgEIAQAAAA==.',Gi='Gimmedapets:BAAALAADCgcIBwAAAA==.',Go='Gomdagarm:BAAALAADCggIDwAAAA==.Gopwal:BAAALAAECgQIBgAAAA==.Gorto:BAAALAAECgEIAQAAAA==.',Gr='Grek:BAAALAAECgEIAQAAAA==.Grippi:BAAALAAECgYIDAAAAA==.',Gu='Guy:BAAALAAECgMIAwAAAA==.',Ha='Harper:BAAALAAECgMIBAAAAA==.Hazyboi:BAAALAADCgEIAQAAAA==.',He='Healabae:BAAALAADCgQIBwAAAA==.Heavenly:BAAALAADCggICAAAAA==.Hemoheals:BAAALAAECgIIBAABLAAECggIGQAFAGIgAA==.Hemostasis:BAABLAAECoEZAAIFAAgIYiD7CQDeAgAFAAgIYiD7CQDeAgAAAA==.Herjä:BAAALAADCggICAAAAA==.Hexem:BAAALAADCgcIBwAAAA==.',Ho='Holygingers:BAAALAADCgYIBgAAAA==.Horeded:BAAALAADCgcIBwABLAAECgYIDQABAAAAAA==.Hotsfired:BAAALAADCgMIAwAAAA==.Howtoheal:BAAALAADCgYIBgAAAA==.',Hu='Huun:BAAALAAECgYIBgAAAA==.',Ia='Iamnsfw:BAAALAAFFAEIAQAAAA==.',Ik='Ikash:BAAALAAECgYIBgAAAA==.',Il='Illmannered:BAAALAADCgcIBwAAAA==.',Im='Imhere:BAAALAADCgEIAQAAAA==.',In='Indigø:BAAALAADCgYIBwAAAA==.Infortunii:BAAALAADCgcICgABLAAECgYIEAABAAAAAA==.Intheclawset:BAAALAAECgQIBwAAAA==.',Ir='Ironhide:BAAALAADCggIEwAAAA==.Irrenadro:BAAALAAECgYICAAAAA==.',Is='Ishalivan:BAAALAADCggICAAAAA==.',It='Itsp:BAAALAAECgMIAwAAAA==.',Ja='Jabaru:BAAALAADCggIEAAAAA==.Jaderabbit:BAAALAADCgUIBwAAAA==.Jahearys:BAAALAADCgcIBwAAAA==.',Ji='Jinanne:BAAALAADCgYIBgAAAA==.Jingleparts:BAAALAAECgMIAwABLAAECgYICwABAAAAAA==.',Jo='Jonesy:BAAALAADCgYIBgAAAA==.Jongnome:BAAALAAECgYICAAAAA==.',Jx='Jxe:BAAALAAECgcICwAAAA==.',Ka='Kaeldin:BAAALAADCgEIAQAAAA==.Kaianne:BAAALAADCggIEAAAAA==.Kaidan:BAAALAAECgYIDQAAAA==.Kalamorian:BAAALAADCgcIBwAAAA==.Kalyke:BAAALAADCgQIBAAAAA==.Kazeyuki:BAAALAADCggICgAAAA==.',Ke='Keetra:BAAALAAECgcIEgAAAA==.Keiriline:BAAALAAECgIIAgAAAA==.Kelalais:BAAALAADCgcIBwAAAA==.',Ki='Kianna:BAAALAADCgcIBwAAAA==.Kikkomon:BAAALAADCggIDwAAAA==.Kilbourne:BAAALAAECgEIAQAAAA==.Killbreed:BAAALAAECgQICAAAAA==.Kinkster:BAAALAADCgEIAQAAAA==.',Kn='Knifeprty:BAAALAAECgMIBAAAAA==.Knuggz:BAAALAAECgEIAQAAAA==.',Ku='Kushzilla:BAAALAADCgUIBwAAAA==.',Ky='Kyleroach:BAAALAAECgYICgAAAA==.Kyletotems:BAAALAADCggICAAAAA==.Kynthelyina:BAAALAADCgUIBQAAAA==.',La='Lambeáu:BAABLAAECoEUAAIGAAcIMByiEQBcAgAGAAcIMByiEQBcAgAAAA==.Laraviana:BAAALAADCgcICAAAAA==.Larzosh:BAAALAAECgYIDQAAAA==.Latth:BAAALAAECgMIBwAAAA==.Lawdheals:BAAALAAECgIIAgAAAA==.',Le='Lee:BAAALAADCgMIAwAAAA==.Lenardo:BAAALAADCgQIBwAAAA==.Lethargy:BAAALAADCgEIAQAAAA==.Letitgo:BAAALAADCgcIBwAAAA==.Lexiras:BAAALAAECgQIDAAAAA==.',Li='Lilwiz:BAAALAADCgcICAAAAA==.Limitedshade:BAAALAADCgcIBwAAAA==.Linnxs:BAAALAADCgcIBgAAAA==.',Lo='Loceng:BAAALAADCggIDAAAAA==.Lokeysan:BAAALAADCgcIBwAAAA==.',Lu='Ludwig:BAAALAAECgYICgAAAA==.Lustnbeiber:BAAALAADCggICAAAAA==.Luyoun:BAAALAADCggIEgAAAA==.',Ly='Lyncha:BAAALAAECgEIAQABLAAECgQIBQABAAAAAA==.Lynchà:BAAALAAECgQIBQAAAA==.Lynchä:BAAALAADCgcIBwABLAAECgQIBQABAAAAAA==.',Ma='Maakun:BAAALAAECgYIBgAAAA==.Madard:BAAALAAECgEIAQABLAAECggIGQAHADUdAA==.Madette:BAAALAAECgMIBgABLAAECggIGQAHADUdAA==.Madwing:BAAALAADCggIDgAAAA==.Mahzad:BAABLAAECoEYAAMIAAgIchUjGADyAQAIAAgIchUjGADyAQADAAYI7RKbIgCRAQAAAA==.Majesteit:BAAALAADCgQIAQAAAA==.Malfrun:BAAALAAECgYICAAAAA==.Mantooth:BAAALAAECgEIAQAAAA==.Marijuan:BAAALAAECgYIDQAAAA==.Mathrim:BAAALAAECgcIEgAAAA==.Matooka:BAAALAAECgMIBAAAAA==.Maynji:BAAALAADCgcIBwAAAA==.',Me='Mebforu:BAAALAADCgMIAwAAAA==.Mechrevo:BAAALAADCgcIBwAAAA==.Meencurry:BAAALAAECgQIBAAAAA==.Metaphase:BAAALAAECgYIDQAAAA==.',Mh='Mhaelsstrom:BAAALAAECgcIEAAAAA==.',Mi='Mikaì:BAAALAAECgYIDQAAAA==.Milkjug:BAAALAADCgUIBQABLAAECgQIBgABAAAAAA==.Millerlitè:BAAALAADCgIIAgAAAA==.Mindmaster:BAAALAAECgIIAwAAAA==.Minot:BAAALAADCggIFgAAAA==.Mistt:BAAALAAECgYICQAAAA==.',Mo='Mojoshammy:BAAALAADCgYIBgAAAA==.Molodwar:BAAALAADCggIEAAAAA==.Monkgroom:BAAALAAECgcIDQAAAA==.Montra:BAAALAAECgYIDwAAAA==.Moolificent:BAAALAADCggIDwAAAA==.Moonsinn:BAAALAAECgYICAAAAA==.Mozbahb:BAAALAAECgMIBwABLAAECggIGAAIAHIVAA==.',Mu='Muddbane:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Mugen:BAAALAADCgcICwAAAA==.Muiry:BAAALAADCgUIBgABLAADCggIEgABAAAAAA==.',['Mû']='Mûdd:BAAALAAECgcIEAAAAA==.',Na='Naazra:BAAALAAECgYIDQAAAA==.Nachopally:BAAALAAECgEIAQAAAA==.Narf:BAAALAADCgcIBwAAAA==.Nayelii:BAAALAADCggICAAAAA==.',Ne='Nestaah:BAAALAADCgcIBwAAAA==.Netalzinxz:BAAALAADCgIIAgAAAA==.',Ni='Niaru:BAAALAAECggIBwAAAA==.Nicetomeatyu:BAAALAADCggIDAAAAA==.Nightwïsh:BAAALAAECgYIDQAAAA==.',No='Nobainer:BAAALAADCgUIBQAAAA==.Nohkano:BAAALAAECgEIAQAAAA==.',On='Onebutton:BAAALAADCgcIBwABLAAECgYICAABAAAAAA==.Oneofmany:BAAALAADCgQIBAAAAA==.Oneshothel:BAAALAADCgMIAwAAAA==.',Oo='Oomkin:BAAALAADCggICQAAAA==.',Or='Ortillious:BAAALAAECgQIBQAAAA==.Oryndern:BAAALAADCgIIAgAAAA==.',Ov='Ovenmitts:BAAALAADCggICQABLAAECgYICwABAAAAAA==.Overblood:BAAALAADCgIIAgAAAA==.',Pa='Paladeez:BAAALAADCggIDwABLAAECggIGQAFAGIgAA==.Paladindanse:BAAALAAECgEIAQAAAA==.Pantheons:BAAALAADCgYIBgAAAA==.Paradon:BAAALAADCgcIBwAAAA==.Pardon:BAAALAADCgUIBAABLAADCggIEAABAAAAAA==.Parsi:BAAALAADCgYIBgAAAA==.',Pe='Peachorange:BAAALAAECggICAAAAA==.Perci:BAAALAADCgQIBgAAAA==.',Ph='Phialkit:BAAALAADCgQIBAABLAAECgcIEAABAAAAAA==.Phialseer:BAAALAAECgcIEAAAAA==.Philip:BAAALAAECgMIBQAAAA==.Phylon:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.',Pi='Pizzaparty:BAAALAAECgMIAwABLAAECgYICwABAAAAAA==.',Pj='Pjeshka:BAAALAADCgUICgAAAA==.',Pl='Planetklaus:BAAALAADCgcIBwAAAA==.',Po='Polargirl:BAAALAADCgcIBgAAAA==.Polis:BAAALAADCggICAAAAA==.Pougadina:BAAALAAECgEIAQAAAA==.Powderpaq:BAAALAADCgYIBgAAAA==.',Pr='Pritee:BAAALAAECgcIEAAAAA==.',Pu='Pursepony:BAAALAADCgcIBwAAAA==.',['Pò']='Pò:BAAALAAECgMIBAAAAA==.',Qi='Qizzle:BAAALAADCgYICgAAAA==.',Qu='Quencha:BAAALAADCgEIAQAAAA==.Quez:BAAALAAECgIIAgAAAA==.Quietmoo:BAAALAADCgcICQABLAAECgYICAABAAAAAA==.',Ra='Rabite:BAAALAAECgYICgAAAA==.Ragaboom:BAAALAADCgcIDgAAAA==.Ramshunter:BAAALAAECgIIAgAAAA==.Ratnob:BAAALAAECgMIAwAAAA==.Rawker:BAAALAAECgMICgAAAA==.',Re='Reddemon:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.Relda:BAAALAAECgYICQAAAA==.Renae:BAAALAAECggICAAAAA==.Rennshi:BAAALAAECgYIDwAAAA==.Reqiumiv:BAAALAADCgcIEwAAAA==.Retpally:BAAALAAECgcIBwAAAA==.Retstafari:BAAALAADCgUIBQAAAA==.Revelations:BAAALAADCgcIBwAAAA==.',Ri='Righteousnes:BAAALAADCgMIAwAAAA==.',Ro='Rolanthas:BAAALAAECgYIDQAAAA==.Ronkarr:BAAALAADCgMIBQAAAA==.Rootsie:BAAALAADCgYIBgAAAA==.Rosario:BAAALAAECgYIBgAAAA==.',Ru='Rukhana:BAAALAADCgMIAwAAAA==.',Ry='Rythmatic:BAAALAAECgQIBAAAAA==.',['Ré']='Rénae:BAAALAADCggICAABLAAECggICAABAAAAAA==.',Sa='Sakieri:BAAALAAECgYIDgAAAA==.Salinia:BAAALAADCgYIBgAAAA==.Salto:BAAALAADCggIDAAAAA==.Samwisegam:BAAALAAECgYIDgAAAA==.Sarina:BAAALAAECgMIAwAAAA==.Savant:BAAALAAECgIIBAAAAA==.',Sc='Scye:BAAALAADCggIDAAAAA==.',Se='Seanoevil:BAAALAAECgYIEAAAAA==.Selaris:BAAALAADCggICwAAAA==.Selluuraeus:BAAALAADCgUIBQAAAA==.Selyndrea:BAAALAADCgUIBQAAAA==.Serahealer:BAAALAAECgcIDwAAAA==.Serazal:BAABLAAECoEYAAICAAgICxpuCACcAgACAAgICxpuCACcAgAAAA==.',Sh='Shamshamz:BAAALAAECgMIAwAAAA==.Shocksfired:BAAALAADCgQIBAAAAA==.Shortbejo:BAAALAADCgcICQAAAA==.',Si='Siegesentinl:BAAALAADCgYIDgAAAA==.Sikozu:BAAALAADCgIIAgAAAA==.',Sk='Skeezer:BAAALAADCggIEAAAAA==.',Sl='Slycendyce:BAAALAADCgcIDQAAAA==.',Sm='Smallkeg:BAAALAADCgcICQAAAA==.',So='Soonan:BAAALAADCgMIAwAAAA==.',Sq='Squishe:BAAALAAECggICwAAAA==.',St='Steppedon:BAAALAAECgIIAgAAAA==.Stingerai:BAAALAAECgYICAAAAA==.Stormbless:BAAALAAECgYICAAAAA==.Stormjovaa:BAAALAAECgMIBAAAAA==.Stygianna:BAAALAADCgIIAgAAAA==.',Su='Sukunaa:BAAALAADCgcIDgAAAA==.Sunaena:BAAALAAECgIIAgAAAA==.Supermight:BAAALAADCgYICgAAAA==.',Sy='Sylarage:BAAALAADCgUIBQAAAA==.Syzmic:BAAALAADCgcIBwAAAA==.',Ta='Tamb:BAAALAADCgcIDwAAAA==.Tandrissa:BAAALAADCgUIBQABLAAECgYICAABAAAAAA==.Tartanian:BAAALAADCgIIAgAAAA==.Tasket:BAAALAAECgEIAQAAAA==.Tauro:BAAALAADCggIFgAAAA==.Tazzbrez:BAAALAAECgYICAAAAA==.',Te='Teehuntee:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.Teemond:BAAALAADCggIEAABLAAECgcIEAABAAAAAA==.Tekraa:BAAALAAECgcIEAAAAA==.Tempist:BAAALAADCggIFgAAAA==.Teribullduce:BAAALAAECgUIBwAAAA==.',Th='Thaelia:BAAALAADCgYIBgAAAA==.Thebadtouch:BAAALAADCgMIAwAAAA==.Therion:BAAALAADCggIBwAAAA==.Thog:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.Thormor:BAABLAAECoEZAAMHAAgINR2gBwCwAgAHAAgINR2gBwCwAgAJAAIIew/eQQB0AAAAAA==.Thuggerjr:BAAALAADCgcIFQAAAA==.Thænes:BAAALAADCgMIBAAAAA==.',Ti='Ticktactotem:BAAALAADCgMIAwAAAA==.Tinyandcute:BAAALAADCggICgABLAAECgYICwABAAAAAA==.Tisket:BAAALAAECgYICwAAAA==.Tithecollect:BAAALAAECgQIBgAAAA==.',To='Toefungys:BAAALAADCgcIBwAAAA==.Tottemdrop:BAAALAAECgUIBQAAAA==.',Tr='Troglodyte:BAAALAADCgcIBwAAAA==.',Tu='Turbulent:BAAALAADCgcICgAAAA==.',['Tá']='Táti:BAAALAAECgYICwAAAA==.',Un='Unfocused:BAAALAAECgcIDgAAAA==.',Va='Valkiryn:BAAALAADCgcIBwABLAADCggIDwABAAAAAA==.Vaush:BAAALAADCgIIAgAAAA==.',Ve='Veratas:BAAALAADCgcIDgAAAA==.Verian:BAAALAADCgcIDgAAAA==.',Vi='Vitiate:BAAALAADCgUIBQAAAA==.',Vy='Vyrexiona:BAAALAAECgcIDwAAAA==.',Wa='Wafflefart:BAAALAADCggIDwAAAA==.',Wh='Whammybammy:BAAALAADCggIEgAAAA==.',Wi='Wildxwarrior:BAAALAADCgYIBgAAAA==.Willdun:BAAALAADCgYIBgAAAA==.Winchells:BAAALAADCggIEgAAAA==.Winrodan:BAAALAAECgYICAAAAA==.Wizy:BAAALAAECgEIAQAAAA==.',Wo='Wouldd:BAAALAADCgYIBgAAAA==.',Xa='Xarttoplek:BAAALAADCggIEAABLAAECgYICAABAAAAAA==.',Xu='Xufoxpikmin:BAAALAADCgUIBQAAAA==.',Ya='Yagamii:BAAALAADCgEIAQAAAA==.',Ye='Yehvendale:BAAALAAECggIAQAAAA==.Yeosephsoc:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Yo='Yoohoomoo:BAAALAAECgMIAwAAAA==.Yourboymoi:BAAALAAECgYICQAAAA==.',Yu='Yunnie:BAAALAADCggIEQAAAA==.Yutch:BAAALAAECggIDgAAAA==.',Za='Zacalkan:BAAALAADCgcIBgAAAA==.Zagreo:BAAALAADCggIDwAAAA==.Zarathan:BAAALAADCgIIAQAAAA==.',Zo='Zolanna:BAAALAADCggIFAAAAA==.',Zu='Zugforlife:BAAALAAECgYIBgABLAAECgYIEAABAAAAAA==.Zulugangrene:BAAALAAECgIIBAAAAA==.Zun:BAAALAAECgEIAQAAAA==.',['Zä']='Zäkurä:BAAALAADCgIIAgAAAA==.',['Æg']='Ægir:BAAALAADCggICAAAAA==.',['Ôx']='Ôx:BAAALAADCgYIBgAAAA==.',['Öh']='Öhyshi:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end