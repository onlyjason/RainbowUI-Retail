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
 local lookup = {'Rogue-Assassination','Unknown-Unknown','Warlock-Demonology','Paladin-Retribution','Rogue-Outlaw','Rogue-Subtlety','Druid-Balance','Druid-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Protection','Priest-Holy','Druid-Feral',}; local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adorean:BAAALAAECgYIEAAAAA==.',Ae='Aeginau:BAAALAADCgUIBgAAAA==.',Ag='Age:BAAALAAECgMIAwAAAA==.',Ai='Aimnskin:BAAALAADCgcIEwAAAA==.Aionios:BAAALAADCggIDwAAAA==.',Ak='Akaril:BAAALAAECgIIBAAAAA==.Akki:BAAALAADCggICgAAAA==.',Al='Albertus:BAAALAADCggICAAAAA==.Alexstraxsa:BAAALAADCggICAAAAA==.Alihandro:BAAALAAECgUICQAAAA==.Alphabeast:BAAALAAECgYIDAABLAAECggIFQABAEgiAA==.',Am='Ameiisaa:BAAALAAECgMIAwAAAA==.Amyeryn:BAAALAADCgMIAQAAAA==.Amytiel:BAAALAAECgYICgAAAA==.',An='Anabella:BAAALAADCgcIBwAAAA==.Andorelia:BAAALAADCggIDQAAAA==.Andronae:BAAALAAECgQIBgAAAA==.Anxie:BAAALAADCgMIAwAAAA==.',Ap='Apprentice:BAAALAADCggIDAAAAA==.',Ar='Aramos:BAAALAADCggIFgAAAA==.Aranassa:BAAALAAECgEIAQAAAA==.Archpalidan:BAAALAADCgcIBwABLAAECgIIBAACAAAAAA==.Arigidpeen:BAAALAADCggIFgAAAA==.Arta:BAAALAADCggIFgAAAA==.',As='Ashhealz:BAAALAAECgQIBgAAAA==.',Ax='Axlegrease:BAAALAADCgQICQAAAA==.',Az='Azazuul:BAAALAADCggICgAAAA==.Azhar:BAAALAADCgYIBgAAAA==.',Ba='Babeal:BAAALAADCgcIDQAAAA==.Bach:BAAALAAECgcIDAAAAA==.Badsnapple:BAAALAADCgYIBgABLAADCgcIEwACAAAAAA==.Baethic:BAAALAAECgYICAAAAA==.',Be='Beaker:BAAALAAECgYIEwAAAA==.Beastmode:BAAALAAECgcICwAAAA==.Bet:BAAALAAECgYIBgAAAA==.',Bl='Blackpanthxr:BAAALAAECgYICQAAAA==.Blackup:BAAALAADCgIIAgAAAA==.Blueboost:BAAALAADCggIDwAAAA==.',Bo='Bookofzeref:BAAALAAECgYIEgAAAA==.',Br='Bralline:BAAALAADCgIIAgAAAA==.Brayend:BAAALAAECgMIBQAAAA==.Brimscythe:BAAALAAECgUIAwAAAA==.Bruisedknee:BAAALAADCgcIEwAAAA==.Bruttaneus:BAAALAADCgUIBgAAAA==.',Bu='Bubblepriest:BAAALAADCgcICwAAAA==.Buttexplode:BAAALAADCgcIDgAAAA==.',Ca='Caddleprot:BAAALAAECgMIBAAAAA==.Caedelous:BAAALAAECgMIAwAAAA==.Caliandis:BAAALAADCggICAAAAA==.Candrass:BAAALAADCgcIBwAAAA==.Carclias:BAAALAAECgYICwAAAA==.Carthrix:BAAALAAECgEIAQAAAA==.Cattlerage:BAAALAADCgcICAAAAA==.',Ce='Cedo:BAAALAAECgEIAQAAAA==.Celery:BAAALAAECgYIBwAAAA==.',Ch='Chaoscookies:BAAALAAECgEIAQAAAA==.Charizàrd:BAAALAAFFAEIAgAAAA==.',Ck='Ckay:BAAALAADCgcIBwAAAA==.',Co='Come:BAAALAADCggICAAAAA==.Comlock:BAAALAAECgEIAQAAAA==.Complacent:BAAALAADCggIDQAAAA==.Coomgeta:BAAALAADCgYIDAAAAA==.Coomtheory:BAAALAAECgUIBgAAAA==.',Cr='Cruetzfeldt:BAAALAADCgcICwAAAA==.Cryptobling:BAAALAADCgYIBwAAAA==.',Cu='Cursedchild:BAAALAADCggIDgAAAA==.',Cy='Cyclonic:BAAALAADCgcICAAAAA==.Cyonicus:BAAALAAECgYIEAAAAA==.Cyska:BAAALAAECgQIBgAAAA==.',Da='Daciana:BAAALAADCggIFQAAAA==.Dagaroonie:BAAALAAECgQIBAAAAA==.Dagevas:BAAALAAECgIIAgAAAA==.Dannÿ:BAAALAADCgcIBwABLAAECgYICAACAAAAAA==.Darkeznite:BAAALAAECgEIAQAAAA==.Darth:BAAALAADCgcIBwAAAA==.Dartoy:BAAALAAECgMIBQAAAA==.Daruud:BAAALAADCgMIAwAAAA==.Dax:BAAALAADCggIDwAAAA==.',De='Deeppurple:BAAALAADCgcIEgAAAA==.Deezmons:BAAALAAECgMIBwAAAA==.Del:BAAALAAECgYIEwAAAA==.Delinda:BAAALAADCgYIBgABLAADCgcIDwACAAAAAA==.Despot:BAAALAADCgUIBQAAAA==.',Dh='Dhargal:BAAALAAECgYIEwAAAA==.',Di='Dial:BAAALAADCgcICQAAAA==.Dichotomy:BAAALAADCggICAAAAA==.Diesontrash:BAAALAADCgMIAwAAAA==.Divitiacus:BAAALAADCgcIEwAAAA==.Dixee:BAAALAADCgcIBwAAAA==.',Do='Dontmeswitme:BAABLAAECoEVAAIBAAgISCLLAgAfAwABAAgISCLLAgAfAwAAAA==.Dothedru:BAAALAADCgYIBwAAAA==.',Dr='Drinkme:BAAALAADCgEIAQAAAA==.Droki:BAAALAAECggIEwAAAA==.Drokigos:BAAALAAECggICAABLAAECggIEwACAAAAAA==.',Du='Dullbrain:BAAALAADCgYIBgABLAAECgIIAgACAAAAAA==.Dum:BAAALAADCggICwAAAA==.Durples:BAAALAAECgMIAwABLAAECgMIBAACAAAAAA==.',Dy='Dyorra:BAAALAADCggICAAAAA==.',['Dã']='Dãnny:BAAALAAECgYICAAAAA==.',['Dä']='Därryl:BAAALAADCgEIAQAAAA==.',Eb='Ebonshade:BAAALAADCgcICgAAAA==.',Ed='Edgardapoe:BAAALAADCggIDwAAAA==.Edge:BAAALAADCgcIBwAAAA==.',Eh='Ehmill:BAAALAADCgcIBwAAAA==.',Ei='Einvoid:BAAALAADCgcIBwAAAA==.',El='Elosien:BAAALAADCgIIBAABLAADCggICAACAAAAAA==.Elventhing:BAAALAAECgYICAAAAA==.Elwing:BAAALAADCgcIEwAAAA==.',Em='Emmå:BAAALAAECgIIAgAAAA==.',En='Enel:BAAALAADCgcICQAAAA==.',Es='Eskers:BAAALAAECgYICAAAAA==.Estralla:BAAALAADCggICAAAAA==.',Et='Ethereon:BAAALAADCgUIBQABLAAECgYIEwACAAAAAA==.',Ev='Evilkarma:BAAALAADCgcIDQAAAA==.Evocatis:BAAALAAECggIEQAAAA==.',Fa='Faasht:BAAALAADCgcIEAAAAA==.Faion:BAAALAAECgYIBgAAAA==.Falco:BAAALAADCggIBwAAAA==.Faolan:BAAALAADCgEIAQAAAA==.Faros:BAAALAADCggICAABLAAECgYIDQACAAAAAA==.Fatigue:BAAALAADCgcIDAAAAA==.',Fe='Feaster:BAAALAADCgUIBQABLAAECgIIBAACAAAAAA==.Feebs:BAAALAAECgEIAQAAAA==.Felzbirt:BAAALAADCggICgAAAA==.',Fi='Firebirdz:BAAALAAECggIEQAAAA==.Firebirdzx:BAAALAADCggICAABLAAECggIEQACAAAAAA==.Fizyx:BAAALAADCggICAAAAA==.',Fl='Flygon:BAAALAAECgYIDQAAAA==.',Fo='Forginn:BAAALAAECgYIDAAAAA==.',Fr='Frequentine:BAAALAAECgUIBgAAAA==.Friargark:BAAALAADCgYIBgAAAA==.',Fu='Fuzzybut:BAAALAADCggIDwAAAA==.',Ga='Gark:BAAALAADCgcIEQAAAA==.Gazzi:BAAALAAECgYICAAAAA==.',Ge='Genocyde:BAAALAADCgQICAAAAA==.',Go='Gokussjthree:BAAALAADCgcIEQAAAA==.Gonger:BAAALAAECgIIAgAAAA==.Goodjuju:BAAALAADCggIBwAAAA==.Gooseneck:BAAALAAECgIIBAAAAA==.',Gr='Granmista:BAAALAAECgMIBAAAAA==.',Gu='Guldantheimp:BAAALAADCgcIBwAAAA==.Guroo:BAAALAAECgYIBwAAAA==.',Ha='Hackle:BAAALAAECgIIAgAAAA==.Hagarn:BAAALAAECgcIDgAAAA==.Halastrasz:BAAALAAECgMIAwAAAA==.Hanyar:BAAALAAECgYIEwAAAA==.Harpers:BAAALAADCgMIAwAAAA==.Hazan:BAAALAAECggICAABLAAECggIEwACAAAAAA==.',He='Heffs:BAAALAADCgMIBAABLAAECgEIAQACAAAAAA==.Heffy:BAAALAAECgEIAQAAAA==.Hellswarden:BAAALAADCggIDgAAAA==.Hexmachine:BAAALAAECggIBAAAAA==.',Ho='Holmstein:BAAALAADCgcICgAAAA==.Holyray:BAAALAADCgUIBQAAAA==.Hoolignrazor:BAAALAAECgMIAwAAAA==.',['Hë']='Hëllsoldier:BAAALAADCgIIAgAAAA==.',Ia='Iamahriman:BAAALAAECgMIAwAAAA==.Iamarawn:BAAALAADCgYIAgAAAA==.Iamthanatos:BAAALAADCgMIAwABLAADCgYIAgACAAAAAA==.',Ic='Icyfreeze:BAAALAAECgMIAwAAAA==.',Id='Idblastdat:BAAALAAECgYICgAAAA==.Idie:BAAALAADCgcIEQAAAA==.',Il='Illestria:BAAALAAECgYIBwAAAA==.Illumiscotty:BAAALAAECgQIBgAAAA==.',Im='Immshorty:BAAALAADCggICAAAAA==.Immórtál:BAAALAAECgIIAgAAAA==.',Iv='Ivankatrump:BAAALAADCgYIBgAAAA==.',Iz='Izara:BAAALAADCgcIDQAAAA==.',Ja='Jangfu:BAAALAADCgYIBgAAAA==.Jasindra:BAAALAADCggIDwABLAAECgYICAACAAAAAA==.',Je='Jenk:BAAALAADCgYIBgABLAAECgYIDQACAAAAAA==.',Jg='Jg:BAAALAADCggICAAAAA==.',Jo='Jolinascrubs:BAAALAAECgEIAQAAAA==.Jonjee:BAAALAAECgYICgAAAA==.',Ju='Junichi:BAAALAADCgcICAAAAA==.Jurkee:BAAALAAECgQIDAAAAA==.',Ka='Kaala:BAAALAAECgYICwAAAA==.Kain:BAAALAADCgEIAQAAAA==.Kalivath:BAAALAAECgQIBgAAAA==.Katio:BAAALAAECgYICwAAAA==.Kavaria:BAAALAAECgMIBQAAAA==.',Ke='Kekadin:BAAALAADCgIIAgAAAA==.Kelira:BAAALAADCgcIDAAAAA==.Kessandra:BAABLAAECoEVAAIDAAgIXB9aAQCaAgADAAgIXB9aAQCaAgAAAA==.Kessanova:BAAALAADCggIDwAAAA==.',Kh='Khurri:BAAALAAECgYICAAAAA==.',Ki='Kielthazad:BAAALAADCgUIBQAAAA==.Kirr:BAAALAAECgUICAAAAA==.Kirridan:BAAALAADCggICAAAAA==.Kisor:BAAALAADCgcIBwAAAA==.Kitchenstink:BAAALAAECgIIAgAAAA==.',Ko='Komosky:BAEBLAAECoEXAAIEAAgIqyE/CAD4AgAEAAgIqyE/CAD4AgAAAA==.',Kr='Kratoskyrie:BAAALAAECgMIBAAAAA==.Krelen:BAAALAADCgcIBwAAAA==.Kru:BAAALAADCggIFAAAAA==.',Ku='Kurnea:BAAALAADCggIFQAAAA==.',La='Lachlann:BAAALAADCgUICgAAAA==.Lakartó:BAAALAAFFAEIAQAAAA==.Layson:BAAALAADCgUIBQAAAA==.Lazzareto:BAAALAADCgEIAQAAAA==.',Ld='Ldritch:BAABLAAECoEYAAQFAAgIJCMKAgBtAgAFAAYIfSQKAgBtAgAGAAMITh0EDQDvAAABAAIIzSRXNQCcAAAAAA==.',Le='Leonedis:BAAALAAECgEIAgAAAA==.Letgomyego:BAAALAADCgcIBwAAAA==.Lethea:BAAALAADCggICwAAAA==.',Li='Littlethor:BAAALAADCgYIBQAAAA==.',Lo='Lohin:BAAALAAECgMIBAAAAA==.Lore:BAAALAAECgYICAAAAQ==.Lorune:BAAALAADCgYIBgABLAADCggIEAACAAAAAA==.Lovely:BAAALAAECgYIBwAAAA==.',Lu='Luminate:BAAALAAECgYIEwAAAA==.Luxurious:BAAALAADCgYICwAAAA==.Luxyloves:BAAALAADCgQIBAAAAA==.',Ly='Lyannastark:BAAALAAFFAEIAQAAAA==.',Ma='Maaca:BAAALAADCgYIAgAAAA==.Magiskdragon:BAAALAAECgIIAgAAAA==.Malachor:BAAALAADCggICAAAAA==.Maligned:BAAALAAECgYIEgAAAA==.Mathac:BAAALAAECgUIBQAAAA==.Mazes:BAAALAAECgYIDAAAAA==.',Mc='Mccholock:BAAALAADCggIDwAAAA==.Mcmach:BAAALAADCggIEAAAAA==.',Me='Memelle:BAAALAADCggICAAAAA==.Menoah:BAAALAADCggICAAAAA==.Meredith:BAAALAADCggICAAAAA==.Mesilana:BAAALAADCggICAAAAA==.',Mi='Mirenna:BAAALAADCggICAAAAA==.Misseymiss:BAAALAADCgcIBwAAAA==.',Mo='Moja:BAAALAAECgMIAwAAAA==.Monichan:BAAALAADCgcICAAAAA==.Monkfu:BAAALAADCgYIBgAAAA==.Moosecheeks:BAAALAADCgYIBgAAAA==.Mooseknuckle:BAAALAADCggIDgAAAA==.Moriainthan:BAAALAAECgEIAQAAAA==.Moriim:BAAALAAECgYICAAAAA==.Morior:BAAALAADCggICAAAAA==.Motorcade:BAAALAADCggICwAAAA==.',Mu='Muddermarrow:BAAALAADCgMIAwAAAA==.Murazor:BAAALAADCgYIBgAAAA==.Murples:BAAALAAECgMIBAAAAA==.',My='Mystie:BAAALAAECgEIAQAAAA==.Mythicle:BAAALAAECgIIAgAAAA==.',Na='Natzukamu:BAABLAAECoEUAAMHAAgIcSAWCQCfAgAHAAcIZiMWCQCfAgAIAAIIdQn7VAA2AAAAAA==.Natzuxion:BAAALAADCgcIBwAAAA==.',Ne='Neather:BAAALAAECgEIAQAAAA==.Neels:BAAALAADCggICAAAAA==.Neron:BAAALAADCgYIBgAAAA==.Nexeon:BAAALAAECgYIEwAAAA==.',Ni='Nira:BAAALAAECgYIEgAAAA==.',No='Nockturne:BAAALAAECgEIAQAAAA==.Nonetoo:BAAALAADCgYIBgAAAA==.Notdeadyet:BAAALAADCggICAAAAA==.',Nu='Nuthar:BAAALAAECgMICAAAAA==.',Ny='Nyceria:BAAALAAECgYICAAAAA==.',Og='Ogden:BAAALAAECgMIBwAAAA==.',On='Onetoughson:BAAALAAECgYIBwAAAA==.Ontherun:BAAALAADCggIEwAAAA==.',Op='Oprawinfury:BAAALAADCgcIDwAAAA==.',Or='Orphani:BAAALAADCggIDQAAAA==.',Os='Oscarguydude:BAAALAAECgQIBAAAAA==.',Ow='Owlpha:BAAALAADCggICAAAAA==.Owltruist:BAAALAADCgcICwAAAA==.',Pa='Palmpyro:BAAALAADCgcIBwAAAA==.Pantherlily:BAAALAADCgQIBAAAAA==.Paulo:BAAALAADCgcICgAAAA==.',Pe='Peenance:BAAALAADCgcIDQAAAA==.Pele:BAAALAADCgcIEwAAAA==.Pellito:BAAALAADCggIEgAAAA==.Perpetrator:BAAALAADCgcIDQAAAA==.',Ph='Phyre:BAAALAADCggIDAAAAA==.',Po='Poepwn:BAAALAAECgYIDAAAAA==.',Pu='Puffypanda:BAAALAADCgcICgAAAA==.',Qu='Quelmanar:BAAALAAECgQIBAAAAA==.Quìnn:BAAALAADCgYIAgAAAA==.',Ra='Raeris:BAAALAADCgcIBwABLAADCggIEAACAAAAAA==.Rakawa:BAAALAADCgcICgAAAA==.Rannick:BAAALAADCggICAAAAA==.Ratio:BAAALAAECgIIAgAAAA==.Raynnie:BAAALAAECgMIAwAAAA==.',Rc='Rcane:BAAALAADCgIIAgAAAA==.',Re='Redshift:BAAALAAECgYICAAAAA==.Regarded:BAABLAAECoEUAAMJAAgIQyJ3CQCEAgAJAAgIph93CQCEAgAKAAIISiHZTwC7AAAAAA==.',Ri='Riftwalker:BAAALAADCgQIBAAAAA==.Ripdvanwinkl:BAAALAADCggIFgAAAA==.',Ru='Rucool:BAAALAADCgYICgAAAA==.Runtimes:BAAALAADCggICAABLAAECggIEwACAAAAAA==.Ruxl:BAAALAADCggIDwABLAAECggIFQABAEgiAA==.',Sa='Salacake:BAAALAADCggICAAAAA==.Salacakei:BAAALAAECgEIAQAAAA==.Salin:BAAALAADCgUIBwAAAA==.Sarthiy:BAAALAADCggIFgABLAAECggIFQALAAUkAA==.Sarthy:BAABLAAECoEVAAILAAgIBST4AQAXAwALAAgIBST4AQAXAwAAAA==.Sassaphras:BAABLAAECoEXAAIMAAgI5hNEEgAkAgAMAAgI5hNEEgAkAgAAAA==.',Sc='Scoobydo:BAAALAADCgcIEwABLAAECgIIAgACAAAAAA==.Scrandy:BAAALAAECgQIBAAAAA==.Scrubs:BAABLAAECoEVAAIKAAgItRflEQBZAgAKAAgItRflEQBZAgAAAA==.',Se='Selv:BAAALAADCgYIBwAAAA==.',Sh='Shadius:BAAALAAECgYIDQAAAA==.Shambino:BAAALAADCggIDAAAAA==.Shandralore:BAAALAADCggICAAAAA==.Sharpclawz:BAAALAADCgEIAQAAAA==.Shiel:BAAALAADCggIDwAAAA==.Shockböx:BAAALAADCgMIAwAAAA==.Shockdoctor:BAAALAAECgEIAQAAAA==.Shockzillah:BAAALAAECgcIDgAAAA==.Shoveldruid:BAABLAAECoEWAAINAAgIOx8/AgDmAgANAAgIOx8/AgDmAgAAAA==.Shroomdoom:BAAALAADCgMIAwAAAA==.Shuenli:BAAALAADCgcIEQAAAA==.',Si='Sicarion:BAAALAADCggIJAAAAA==.Sidarin:BAAALAADCgcIBgAAAA==.Sipowitz:BAAALAADCgcIBwAAAA==.Sithil:BAAALAAECgUIBgAAAA==.',Sl='Sleepyy:BAAALAADCggICQAAAA==.Sleples:BAAALAAECgIIAgAAAA==.Sleyalias:BAAALAADCgcIEQAAAA==.Slyxxii:BAAALAAECgYIBwAAAA==.Slyyxxi:BAAALAADCgcIBwAAAA==.',Sm='Smolder:BAAALAADCgcICQAAAA==.',Sn='Snarkyloc:BAAALAADCggIFgAAAA==.Sneakeh:BAAALAADCgYIBgAAAA==.',So='Solorion:BAAALAADCgcIDgAAAA==.Sorovar:BAAALAAECgYICAAAAA==.Soulbreakër:BAAALAADCgYIBgAAAA==.',Sp='Spony:BAAALAADCggIDwAAAA==.',St='Starbrow:BAAALAAECgYIDQAAAA==.Stonecoldcat:BAAALAADCgcIBwAAAA==.Stormlight:BAAALAADCggIFQAAAA==.Strength:BAAALAADCgYIBgABLAAECgMIBAACAAAAAA==.Strippah:BAAALAADCgYICAAAAA==.',Su='Sulevin:BAAALAAECgMIAwAAAA==.Sushistryke:BAAALAADCgMIAwAAAA==.',Sy='Syland:BAAALAADCggIDwAAAA==.',Ta='Taker:BAAALAADCgcIBwAAAA==.Talanah:BAAALAADCggICAAAAA==.Tanaesta:BAAALAADCgcIDwABLAAECgYICAACAAAAAA==.Targis:BAAALAADCgcIBwAAAA==.Tarvariks:BAAALAADCggIDQAAAA==.Tazanaz:BAAALAADCgcICwABLAAECgYICAACAAAAAA==.',Te='Teafa:BAAALAADCgcICwAAAA==.Tendai:BAAALAADCgYIBgAAAA==.Teynk:BAAALAAECgMIBAAAAA==.',Th='Thassa:BAAALAADCgcIDAAAAA==.Thatwhtcsaid:BAAALAADCgIIAwAAAA==.Thefavorite:BAAALAADCggICAAAAA==.Thegreatkhal:BAAALAAECgEIAQAAAA==.Thilea:BAAALAADCggICQAAAA==.Thorlas:BAAALAAECgQIBgAAAA==.',Ti='Tinkerella:BAAALAAECgEIAQAAAA==.',To='Tomma:BAAALAAECgYIDQAAAA==.Torolock:BAAALAADCgcIBwAAAA==.Totem:BAAALAADCgcICgAAAA==.Totembi:BAAALAAECgMIAwAAAA==.',Tr='Trailerpark:BAAALAADCgEIAQAAAA==.Trevally:BAAALAAECgMIBAAAAA==.Trupeti:BAAALAADCggIFgAAAA==.',Ty='Tytaniium:BAAALAAECgIIAgAAAA==.',Ul='Ulanmonk:BAAALAAECgEIAQAAAA==.Ulanybelle:BAAALAADCgUIBQAAAA==.Ulridan:BAAALAADCgMIAwABLAAECgYIEwACAAAAAA==.',Un='Uniad:BAAALAAECgQIBQAAAA==.',Up='Upvote:BAAALAAECgMIAwAAAA==.',Va='Valendera:BAAALAAECgYICAAAAA==.Valifadin:BAAALAADCggICAAAAA==.Valkenstein:BAAALAAECgMIAwAAAA==.Valndrevy:BAAALAADCgYIBgAAAA==.Valyrain:BAAALAAECgIIAgAAAA==.Vamire:BAAALAADCggICAAAAA==.Vanpèlt:BAAALAADCgcIEAAAAA==.Vansan:BAAALAAECgYICAAAAA==.',Ve='Venngennce:BAAALAAECgYICAAAAA==.',Vi='Vinntage:BAAALAAECgYIEwAAAA==.',Vo='Voided:BAAALAAECgcIDwAAAA==.Vorkath:BAAALAAECgYIEwAAAA==.',Vt='Vtae:BAAALAAECgEIAQAAAA==.',Wa='Warangel:BAAALAADCgcIBwAAAA==.Warrgoddess:BAAALAADCgIIAgAAAA==.Warubozu:BAAALAADCgMIAwAAAA==.',We='Werehamster:BAAALAADCggIEAAAAA==.',Wh='Whispala:BAAALAADCgcICQAAAA==.',Wi='Wickedwon:BAAALAADCgYIBwAAAA==.Widdershins:BAAALAAECgYICAAAAA==.',Wo='Woxmojo:BAAALAADCggICAAAAA==.Woxvala:BAAALAAECgYICQAAAA==.',Wu='Wubblebubble:BAAALAAECgEIAQAAAA==.',Xa='Xaelin:BAAALAADCggIDwAAAA==.Xanistus:BAAALAAECgYICQAAAA==.',Ya='Yamoro:BAAALAADCggICAAAAA==.',Yi='Yiforyif:BAAALAAECgYICAABLAAECggIGAAFACQjAA==.',Yl='Ylvis:BAAALAAECgYIDQAAAA==.',Yo='Yoshymi:BAAALAAECgMIAgAAAQ==.',Yr='Yrkoon:BAAALAADCgMIAwAAAA==.',Za='Zarion:BAAALAADCggIDwAAAA==.',Ze='Zeirl:BAAALAAECgQIBAAAAA==.Zeroz:BAAALAAECgIIAwAAAA==.',Zi='Ziltchy:BAAALAAECgIIAgAAAA==.',Zo='Zocorro:BAAALAADCgcIEgAAAA==.Zocorrus:BAAALAADCgYIBgAAAA==.',Zu='Zuelmst:BAAALAADCgIIAgAAAA==.',['Ân']='Ângel:BAAALAADCgYICAAAAA==.',['ße']='ßeerßunny:BAAALAAECgEIAQAAAA==.',['ßl']='ßloodbag:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end