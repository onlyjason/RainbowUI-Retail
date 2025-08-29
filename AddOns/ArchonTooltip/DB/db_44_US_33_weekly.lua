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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Priest-Holy','Druid-Guardian','Shaman-Restoration','DemonHunter-Vengeance','Mage-Arcane','Druid-Balance','Monk-Mistweaver','Mage-Fire','Paladin-Holy','Paladin-Retribution','Evoker-Devastation','DemonHunter-Havoc','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction',}; local provider = {region='US',realm='Blackrock',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aarôn:BAAALAAECgYIBwAAAA==.',Ab='Absolution:BAAALAADCgQIBAABLAAECgYICAABAAAAAA==.',Ac='Acaliri:BAAALAADCggIBwAAAA==.Acos:BAAALAADCgMIAwAAAA==.Acousticmind:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.',Ad='Adamantorc:BAAALAAFFAEIAQAAAA==.Adampal:BAAALAADCgYIBwABLAAFFAEIAQABAAAAAA==.Adebisi:BAAALAAECgIIBAAAAA==.Adlez:BAAALAADCgcIDAAAAA==.',Ae='Aeromir:BAAALAAECgMIAwAAAA==.Aethylas:BAAALAAECgMIBAAAAA==.',Ai='Aizzen:BAAALAADCgYIBgAAAA==.',Ak='Akhouel:BAAALAAECgYIDgAAAA==.',Al='Alanoth:BAAALAAECgUIBwAAAA==.Albur:BAAALAADCgMIBAAAAA==.Aldrusan:BAAALAADCgQIBAAAAA==.Aletrion:BAAALAAECgYICQAAAA==.Alexstraszza:BAAALAADCgYIDgAAAA==.Alfalfaflow:BAAALAADCggIDAAAAA==.Alienfreakdt:BAAALAAECggIDgAAAA==.Almuh:BAAALAADCgUICQAAAA==.Alysun:BAAALAADCgQIBwAAAA==.Alysyn:BAAALAAECgMIAwAAAA==.',Am='Amathel:BAAALAAECgYIBwAAAA==.Amberlyn:BAAALAADCgcIBwAAAA==.Amorillas:BAAALAAECgMIBAAAAA==.Amzel:BAACLAAFFIEFAAICAAMIJRBJAgABAQACAAMIJRBJAgABAQAsAAQKgRwAAwIACAitIk0FABEDAAIACAitIk0FABEDAAMAAQheDndPAC8AAAAA.',An='Angelsfìst:BAAALAAECgMIAwAAAA==.Angelus:BAAALAADCgcICAAAAA==.Animaloss:BAAALAAECgcIDwAAAA==.',Ar='Aradora:BAAALAADCggIDgAAAA==.Archive:BAAALAADCgYICgAAAA==.Arkayla:BAAALAAECgYICgAAAA==.Arken:BAAALAADCggIDgABLAAECgYICgABAAAAAA==.Arkyos:BAABLAAECoEUAAIEAAgIjSKFAwDsAgAEAAgIjSKFAwDsAgAAAA==.Artemyss:BAAALAAECgQIBgAAAA==.Arthanos:BAAALAAECggIEAAAAA==.Aryã:BAAALAAECgMIAwAAAA==.',As='Asirili:BAAALAAECgIIAgAAAA==.Asterean:BAAALAAECgYIDAAAAA==.Asterion:BAAALAADCgcICAAAAA==.',Av='Avazen:BAAALAADCgcIEwAAAA==.',Ay='Ayrah:BAAALAAECgIIAgAAAA==.',Ba='Babyde:BAAALAAECgIIAgAAAA==.Babygirlx:BAAALAAECgQICAAAAA==.Baelcoz:BAAALAAECgMIAwAAAA==.Baelon:BAAALAAECgMIAwAAAA==.Baragan:BAAALAADCggICAAAAA==.Barknshift:BAAALAAECgYICAAAAA==.Barkskin:BAAALAAECgYICQAAAA==.Basijis:BAAALAAECgQIBAAAAA==.Battlesister:BAAALAADCgUIBQAAAA==.Bazonga:BAAALAADCggICgAAAA==.',Be='Bearin:BAAALAADCgMIAwAAAA==.Beastialmath:BAAALAAECgMIAwAAAA==.Beazle:BAAALAADCggIEAAAAA==.Beburos:BAAALAAECgEIAQAAAA==.Bellarke:BAAALAAECgIIAQAAAA==.Belldelphine:BAAALAAECgcIEAAAAA==.',Bg='Bgmcsqueezy:BAAALAADCgUICQAAAA==.',Bi='Bigback:BAAALAADCgMIAwAAAA==.Bigdamjudge:BAAALAADCggICAAAAA==.Bigdoofus:BAAALAADCgQIBAAAAA==.Bigdrink:BAAALAADCgcICAAAAA==.Biggestgobo:BAAALAADCgYICAAAAA==.Bithea:BAAALAAECgQIBAAAAA==.',Bj='Bjorneiron:BAAALAAECgIIAgABLAAECgcIFAAFAGAfAA==.',Bl='Blackømen:BAAALAADCggIAQAAAA==.Blangtron:BAAALAAECgEIAQAAAA==.Blazeuwu:BAABLAAECoEUAAIGAAgIqh3rBQDPAgAGAAgIqh3rBQDPAgAAAA==.Bleak:BAAALAAECgMIBgAAAA==.Bloodkane:BAAALAADCggICAAAAA==.Blueaggy:BAAALAADCgYIBgAAAA==.Bläir:BAAALAAECgMIBAAAAA==.Blödhgárm:BAABLAAECoEUAAIHAAgIPRnVAQBQAgAHAAgIPRnVAQBQAgAAAA==.',Bo='Boboko:BAAALAAECgYIBgAAAA==.Bodyshots:BAAALAAECgYICAAAAA==.Bokar:BAAALAAECgMIAwAAAA==.Boofoo:BAAALAAECgEIAQAAAA==.Bortie:BAAALAAECggICwAAAA==.Bortikuz:BAAALAADCgYICwABLAAECggICwABAAAAAA==.Bosch:BAAALAADCggICAABLAAECggIEAABAAAAAA==.Boschoa:BAAALAAECggIEAAAAA==.',Br='Brightboom:BAAALAADCgcIBwAAAA==.Brisk:BAAALAADCgcIDQAAAA==.Broccoliched:BAAALAADCggIDQAAAA==.Bruceling:BAAALAAECgYIEQAAAA==.',Bu='Busenitz:BAAALAADCggICAAAAA==.Butterzz:BAAALAADCggICAAAAA==.',Bw='Bwonsomchi:BAAALAADCggIEwAAAA==.',['Bü']='Bünbün:BAAALAAECgQIBwAAAA==.',Ca='Cainos:BAAALAADCgMIAwAAAA==.Calandra:BAAALAAECgYICwAAAA==.Cardidus:BAAALAAECgMIAwAAAA==.Carditis:BAABLAAECoEUAAIIAAcImyC4CACEAgAIAAcImyC4CACEAgAAAA==.Cauzality:BAAALAADCgUIBQAAAA==.Caytr:BAAALAAECgYIDwAAAA==.',Ce='Cedren:BAAALAAECgUIBgAAAA==.Celeríty:BAAALAAECgIIAgAAAA==.Celynn:BAAALAADCgMIBgAAAA==.Cev:BAABLAAECoEZAAIJAAgIayKqAQD4AgAJAAgIayKqAQD4AgAAAA==.Cevren:BAAALAADCgIIAQABLAAECggIGQAJAGsiAA==.',Cf='Cfred:BAAALAAECgYICwAAAA==.',Ch='Chaintail:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Chaosdevx:BAAALAAECgIIAgAAAA==.Chaoselite:BAAALAAECgcIEQABLAAECgIIAgABAAAAAA==.Chaotïc:BAAALAAECgMIAwABLAAECgUIBQABAAAAAA==.Charmie:BAAALAAECgYIBwAAAA==.Cheddarnig:BAAALAAECgMIBAAAAA==.Cheekz:BAAALAADCgIIAgAAAA==.Chemao:BAAALAAECgcIEQAAAA==.Chenymonk:BAAALAADCgcIBwAAAA==.Chickenbeef:BAAALAAECgEIAQAAAA==.Chickennuggi:BAAALAAECgMIAwAAAA==.Chiliverde:BAAALAADCgYIBQAAAA==.Chubbycurser:BAAALAADCggIDgAAAA==.Chuibacca:BAAALAAECggIEAAAAA==.',Ci='Cimitilko:BAAALAAECgEIAQAAAA==.',Cl='Clanx:BAAALAADCgYIBgAAAA==.Clickclack:BAAALAAECggIDQAAAA==.',Co='Cobrakilla:BAAALAAECgYICAAAAA==.Cobrakiller:BAAALAAECgIIAgABLAAECgYICAABAAAAAA==.Coded:BAAALAADCggIDgAAAA==.Coraquil:BAAALAAECgIIAgAAAA==.Corbun:BAAALAADCgcICQAAAA==.Corpsemage:BAAALAAECgEIAQAAAA==.Cosmicgate:BAAALAAECgYIBwAAAA==.Cowlawladin:BAAALAAECgYIDgAAAA==.Cowmcvoker:BAAALAAECgYIBgAAAA==.',Cr='Crazyspells:BAAALAAECgIIAgAAAA==.Critcritz:BAAALAAECgMIBQAAAA==.Critical:BAABLAAECoEUAAIKAAgImxlmGABMAgAKAAgImxlmGABMAgAAAA==.Crockett:BAAALAADCgYIBwAAAA==.Crolin:BAAALAADCgQIBAAAAA==.',Cy='Cyaxares:BAAALAAECgYIBwAAAA==.Cyndi:BAAALAADCgcIDAAAAA==.Cyrce:BAAALAADCgMIAgAAAA==.',['Cä']='Cätalyst:BAAALAAECgUIBQAAAA==.',['Cö']='Cönquest:BAAALAAECggIEgAAAA==.',Da='Daddysauce:BAAALAADCgYIBwAAAA==.Dadimscared:BAAALAADCggIDgAAAA==.Dadspancakes:BAAALAAECggIAQAAAA==.Dadumpy:BAAALAADCgYIBgAAAA==.Daeltha:BAAALAAECgcIEQAAAA==.Daneglesack:BAAALAAECgYIDwAAAA==.Danoslul:BAAALAAECgIIAgABLAAECggIDgABAAAAAA==.Daragnos:BAAALAAECgcIBwAAAA==.Darkhært:BAAALAAECgIIAwAAAA==.Darkkai:BAAALAAECgYICQAAAA==.Darthmuffin:BAAALAAECgYIBgAAAA==.Daryl:BAABLAAECoEXAAILAAgIDx6sBwC8AgALAAgIDx6sBwC8AgAAAA==.Dasprime:BAAALAAECgYIBgAAAA==.',De='Deadgrizz:BAAALAADCgEIAQABLAADCgUIBwABAAAAAA==.Deadhitmann:BAAALAAECgEIAQAAAA==.Deathdealer:BAAALAADCgYICQAAAA==.Deathisys:BAAALAAECgIIAgAAAA==.Decall:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.Decmonke:BAAALAADCggIDgAAAA==.Degraded:BAAALAAECggIBwAAAA==.Demeteros:BAAALAAECgEIAQAAAA==.Demonkoopa:BAAALAADCgcIBwAAAA==.Ders:BAAALAAECgMIAwAAAA==.Dethstra:BAAALAADCggIFQABLAAECgIIAgABAAAAAA==.Dezrook:BAAALAADCgcIBwAAAA==.',Di='Dionotus:BAAALAADCgYIBgAAAA==.Dippindotz:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Dist:BAAALAADCggIDAAAAA==.Diäblo:BAAALAADCgYIBgAAAA==.',Dk='Dkayla:BAAALAADCggICAAAAA==.',Do='Domenex:BAAALAAECgcIDAAAAA==.Doryani:BAAALAAECgYIDQAAAA==.Dothotter:BAAALAADCgUICQABLAAECgYIBwABAAAAAA==.',Dr='Dracburton:BAAALAADCgcIDgAAAA==.Drachen:BAAALAADCggICAABLAAECggIEAABAAAAAA==.Dragynbeast:BAAALAAECgEIAQAAAA==.Dratnosfan:BAAALAAECggIDgAAAA==.Dreamlike:BAAALAAECggIEgAAAA==.Dredlysnipes:BAAALAADCgYIBgAAAA==.Dresden:BAAALAADCgcIBwAAAA==.Drezco:BAAALAAECgMIBgABLAAECggIGQAJAGsiAA==.Drowsy:BAAALAADCgEIAQAAAA==.Drrokso:BAAALAAECgUIBwAAAA==.Drshockk:BAAALAADCggIDwAAAA==.Drudru:BAAALAADCgEIAQAAAA==.Drueed:BAAALAADCgQIBAABLAAFFAEIAQABAAAAAA==.Drujur:BAAALAAECgYIBgABLAAECgYICgABAAAAAA==.Drukkan:BAAALAADCgYIBgAAAA==.Drymeathole:BAAALAADCgEIAQAAAA==.',Du='Dumbcookie:BAAALAADCgMIAwAAAA==.Dunkndonuts:BAAALAAECgEIAQAAAA==.',Ea='Earthencore:BAAALAAECgMIBQAAAA==.Earthenmoky:BAAALAAECgYICQAAAA==.Easycompany:BAAALAADCgcIEwAAAA==.',Ec='Echidna:BAAALAAECgYIBgAAAA==.',Eg='Eggmilk:BAAALAADCgcIDQAAAA==.',Eh='Ehass:BAAALAADCgMIAwAAAA==.',Ek='Ekosønic:BAAALAAECgMIBAAAAA==.Ekò:BAAALAADCggIFQAAAA==.Ekó:BAAALAADCggIEgAAAA==.Ekõ:BAAALAADCgcIDgAAAA==.Ekø:BAAALAADCgcICwAAAA==.',El='Elasticheart:BAAALAAECgEIAQAAAA==.Elaxa:BAAALAAECgYIDAAAAA==.Eldsinsalis:BAAALAAECggIBAAAAA==.Electrolytes:BAAALAADCggICQAAAA==.Elunedragon:BAAALAADCgcIBwAAAA==.Elunè:BAAALAAECgUICAAAAA==.',Em='Emoky:BAAALAADCggIBQAAAA==.',En='Enhshamnas:BAAALAAECgMIBAAAAA==.',Er='Ertbrez:BAAALAADCgQIBQAAAA==.',Es='Escanõr:BAAALAADCgIIAgAAAA==.',Eu='Eugio:BAAALAADCggIDgAAAA==.',Ev='Evanora:BAAALAADCgYICgAAAA==.Evialleanna:BAAALAAECggIBAAAAA==.Evilbearman:BAAALAADCgcIBwABLAAECggIAwABAAAAAA==.Evillinx:BAAALAAECgcIDQAAAA==.Evilmaru:BAAALAAECgQIBgAAAA==.',Ex='Exi:BAAALAAECgEIAQAAAA==.',Fa='Faespalmn:BAAALAAECgYICgABLAAECgcICgABAAAAAA==.Faesplant:BAAALAAECgcICgAAAA==.Faesroln:BAAALAAECgYIBgABLAAECgcICgABAAAAAA==.Falstar:BAAALAAECggIBwAAAA==.Fatshaman:BAAALAAECgEIAQAAAA==.',Fe='Feralfeelin:BAAALAAECgMIAwAAAA==.Fermango:BAAALAADCgYIBwAAAA==.',Fi='Fidel:BAAALAAECgYICAAAAA==.Fil:BAAALAAECgMIAwAAAA==.Fildo:BAAALAADCgQIBwABLAAECgMIAwABAAAAAA==.Fintann:BAAALAADCggICwAAAA==.Firstloser:BAAALAADCgMIBgAAAA==.',Fl='Flexglaive:BAAALAAECgUICAAAAA==.Flextime:BAAALAADCgQIBAAAAA==.Flexvoid:BAAALAADCgQIBAAAAA==.Flywireé:BAAALAADCgcICAAAAA==.',Fo='Folis:BAAALAAECgEIAQAAAA==.Fortyourself:BAAALAADCggICAAAAA==.Foxfyre:BAAALAAECgIIAgAAAA==.',Fr='Freezeorburn:BAAALAADCgYIBgABLAAECgYIDgABAAAAAA==.Friggitte:BAAALAAECgEIAQAAAA==.Friholy:BAAALAAECgYICwAAAA==.Frizyphus:BAAALAADCgcICAAAAA==.Frostdaddy:BAAALAAECgIIAgAAAA==.',Fu='Fuldar:BAAALAADCgMIAwAAAA==.Funkytree:BAAALAAECgEIAQAAAA==.Furgoblin:BAAALAAECgMIBAABLAAECgYIDgABAAAAAA==.',['Fâ']='Fâdêd:BAAALAADCgcIDQABLAAECgMIBQABAAAAAA==.',['Fä']='Fädëd:BAAALAADCgcIDAABLAAECgMIBQABAAAAAA==.',Ga='Gabi:BAAALAADCgcICgAAAA==.Gacrux:BAAALAADCggIFwAAAA==.Galadrìel:BAAALAAECgYIDAAAAA==.Galadrìèl:BAAALAADCgUIBQAAAA==.Galén:BAAALAADCgcIBwABLAADCggIDwABAAAAAA==.Gamamaru:BAAALAADCgcICAAAAA==.Gasrok:BAAALAADCgcIBwABLAAFFAEIAQABAAAAAA==.Gateor:BAAALAADCgcIBwAAAA==.Gatka:BAAALAADCgEIAQAAAA==.Gawdlike:BAAALAAECgIIAgAAAA==.',Ge='Geraci:BAAALAAECgMIBAAAAA==.',Gh='Ghorn:BAAALAAECgMIBgAAAA==.',Gi='Ginnar:BAAALAADCgcIBwAAAA==.',Gl='Glareaforsor:BAAALAADCgcIBwABLAADCgcICQABAAAAAA==.Glimpse:BAAALAAECgMIBgAAAA==.',Go='Gochurass:BAAALAAECgUICgAAAA==.Gortooth:BAAALAADCgQIBAABLAADCgYIBgABAAAAAA==.',Gr='Graptharr:BAAALAAECgMIAwAAAA==.Greyarrow:BAAALAAECgMIAwAAAA==.Greæd:BAAALAAECgYICQAAAA==.Gringiito:BAAALAAECgYIDAAAAA==.Grizzard:BAAALAAECgQIBgAAAA==.Grizzarmored:BAAALAADCgUIBwAAAA==.Gromjutar:BAAALAAECgMIAwAAAA==.Gruckek:BAAALAAECgQIBgAAAA==.Grunbeld:BAAALAADCgUIBQABLAAECgcIFAAFAGAfAA==.Gròót:BAAALAAECgUIBwAAAA==.',Gu='Guillo:BAAALAAECgEIAQAAAA==.',Gw='Gwendlyne:BAAALAAECgIIAwAAAA==.',['Gó']='Góddess:BAAALAAECgYICAAAAA==.',Ha='Hairychubby:BAAALAADCgYIBgAAAA==.Hawtchili:BAAALAADCgcICQAAAA==.',He='Healoshima:BAAALAAECgUIBwAAAA==.Heligg:BAAALAAECgYIBwAAAA==.Heliophobic:BAAALAAECgIIAwAAAA==.Hellig:BAAALAADCgcIBwAAAA==.Hellofriday:BAAALAAECgMIAwAAAA==.Heurassein:BAAALAADCgIIAgABLAADCggIFQABAAAAAA==.Heywood:BAAALAADCggIKQAAAA==.',Hi='Hideyerweed:BAAALAAECgQIBQABLAAECgYIBwABAAAAAA==.Highscore:BAAALAADCgcICgAAAA==.Hisa:BAAALAADCgcIBwAAAA==.',Ho='Holistic:BAAALAAECgQIBgAAAA==.Holyshok:BAAALAADCgcIBwAAAA==.Holyv:BAAALAAECgQIBgAAAA==.Hornei:BAAALAADCgYIBgAAAA==.Hotchocmilk:BAAALAAECgYIBwAAAA==.Hozzash:BAAALAADCgEIAQAAAA==.',Hr='Hr:BAAALAAECgYIDgAAAA==.',Hu='Hukelan:BAAALAAECgIIAgAAAA==.Huntaa:BAAALAAECgYICAAAAA==.Huråji:BAABLAAECoEUAAMEAAgI6BDUEQCNAQAEAAYIhxTUEQCNAQAMAAgIdgjBEAByAQAAAA==.',['Hä']='Hännibal:BAAALAADCgYIBgAAAA==.',Ia='Iampal:BAAALAADCgcICQAAAA==.',Il='Ilima:BAAALAADCggICAAAAA==.Illidarn:BAAALAADCgMIAwAAAA==.',Im='Imryl:BAAALAAECgcIDAAAAA==.',In='Inzo:BAAALAAECgUIBwAAAA==.',Ir='Ironpaws:BAAALAAECgIIAgABLAAECgYIDgABAAAAAA==.',Is='Isa:BAABLAAECoEZAAMKAAgIUh9QEwB8AgAKAAgIUh9QEwB8AgANAAMIEBzkBQDmAAAAAA==.',It='Itsen:BAAALAADCgUIBQABLAAFFAEIAQABAAAAAA==.Itâchi:BAAALAAECgQIBAABLAAECgUICAABAAAAAA==.',Ja='Jabberwolky:BAAALAADCgMIAwAAAA==.Jademoggins:BAAALAAECgEIAQAAAA==.Jaggons:BAAALAAECgEIAQAAAA==.Janeshoots:BAAALAADCgQIBAAAAA==.Jatish:BAAALAADCgQIBAAAAA==.Javøs:BAAALAAECggIEwAAAA==.Jaxon:BAAALAAECgEIAQAAAA==.',Jd='Jdub:BAAALAAECgYIEAAAAA==.',Je='Jebdh:BAAALAADCggIEAABLAAFFAEIAQABAAAAAA==.Jebx:BAAALAADCgUIBQABLAAFFAEIAQABAAAAAA==.Jebydk:BAAALAAFFAEIAQAAAA==.Jebyy:BAAALAADCgEIAQABLAAFFAEIAQABAAAAAA==.Jeffyshadows:BAAALAAECggIEAAAAA==.Jelsy:BAAALAAECgMIAwAAAA==.Jem:BAAALAAECgYICAAAAA==.Jepx:BAAALAADCgYIBgAAAA==.Jerìk:BAABLAAECoEUAAMOAAgIlyLBAAAwAwAOAAgIlyLBAAAwAwAPAAEIMhLpggBAAAAAAA==.Jesly:BAAALAADCgQIBwAAAA==.',Ji='Jimmyhoofa:BAAALAAECgEIAQAAAA==.Jinei:BAAALAADCggIEAABLAAECggIEAABAAAAAA==.Jinniumma:BAAALAADCgcIBwAAAA==.',Jo='Joeywheeler:BAAALAAECggIEAAAAA==.Johvah:BAAALAADCgcIBwAAAA==.Jones:BAAALAADCgQIBAAAAA==.',Js='Jsteelflexx:BAAALAADCgEIAQAAAA==.',Ju='Juryn:BAAALAAECgYICgAAAA==.Justabutcher:BAAALAAECgEIAQAAAA==.',Ka='Kadaan:BAAALAADCgcIBwAAAA==.Kafur:BAAALAAECgUICAAAAA==.Kaisèr:BAAALAAECgUIBwAAAA==.Kalpo:BAAALAADCgYIBwAAAA==.Karynaku:BAAALAAECgIIAgAAAA==.Kathseras:BAAALAAECgIIBAAAAA==.',Ke='Kelendor:BAABLAAECoEUAAICAAgIbRVeFQA0AgACAAgIbRVeFQA0AgAAAA==.Kelendora:BAAALAADCggIFQAAAA==.Kelindron:BAAALAADCgYIBgAAAA==.Kemmlerok:BAAALAADCgEIAQAAAA==.Kenno:BAAALAADCgcIBwABLAAFFAEIAQABAAAAAA==.Kevani:BAAALAADCgcIBwAAAA==.Kevis:BAAALAADCgMIAwAAAA==.Kevius:BAAALAADCggIEgAAAA==.Kevphan:BAAALAADCgMIBgAAAA==.Kevrath:BAAALAADCgYIBgAAAA==.Kevzin:BAAALAADCgUIBQAAAA==.',Kh='Khautic:BAAALAADCgMIAwAAAA==.Khlampzight:BAAALAADCggICAABLAAECggIEAABAAAAAA==.Khlampzoker:BAAALAAECggIEAAAAA==.',Ki='Kikurface:BAAALAADCgcICgAAAA==.Kirvala:BAAALAAECgYIBwAAAA==.Kiyoseten:BAAALAADCggICwAAAA==.',Kl='Kluya:BAAALAADCggICgAAAA==.',Ko='Kooriaisu:BAAALAADCgcIBwAAAA==.Koradd:BAAALAADCggIDgAAAA==.Korban:BAAALAADCgYIBgAAAA==.Kozakx:BAAALAAECgEIAQAAAA==.',Kr='Krankykronk:BAAALAAECgMIBAAAAA==.',Ku='Kukan:BAAALAAECgYICQAAAA==.Kuko:BAAALAADCgEIAQAAAA==.Kulider:BAAALAADCggICgAAAA==.',Kv='Kvitko:BAAALAAECgcIDQAAAA==.',Kw='Kwangpow:BAAALAAECgYIDAAAAA==.',['Kà']='Kàkàshi:BAAALAAECgUICAAAAA==.',La='Laise:BAAALAADCgcICgABLAAECggIEgABAAAAAA==.Laylbrise:BAAALAAECgEIAQAAAA==.Laz:BAAALAADCgYIBgAAAA==.Lazyrage:BAAALAAECgMIAwAAAA==.Lazythunder:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Le='Lebronto:BAAALAADCgQIBAAAAA==.Lefturn:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Lepsid:BAEALAAECggICAABLAADCgcIBwABAAAAAA==.Lesses:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.Lessisless:BAAALAAECgMIBAAAAA==.',Li='Lichnaught:BAAALAADCgQIBwABLAAECgMIAwABAAAAAA==.Lienee:BAAALAADCgQIBAABLAADCgYIBgABAAAAAA==.Lifegrizz:BAAALAADCgIIAgABLAADCgUIBwABAAAAAA==.Lindra:BAAALAADCgMIAwAAAA==.',Lo='Loaded:BAAALAAECgYIDwAAAA==.Lonzzo:BAAALAADCggICAAAAA==.Lovecats:BAAALAADCggICQAAAA==.',Ls='Lstormfuryl:BAAALAADCgcICAAAAA==.',Lu='Lucasz:BAAALAADCgQIBAAAAA==.Lucíén:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.Lunarrya:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.',['Là']='Làdygaga:BAAALAADCggIFgAAAA==.',Ma='Madarchoth:BAAALAAECgQIBAAAAA==.Maddalynn:BAAALAADCggIEAAAAA==.Magharat:BAAALAADCggIDgABLAAFFAEIAQABAAAAAA==.Magicpewpew:BAAALAAECgIIAgAAAA==.Mahmage:BAEALAADCgcIBwAAAA==.Maki:BAAALAADCggICAAAAA==.Makilros:BAAALAAECgIIAgAAAA==.Malacanthet:BAAALAAECgYIDAAAAA==.Manamama:BAAALAADCgcIDQAAAA==.Manangtroll:BAAALAAECgMIAwAAAA==.Mandelstam:BAAALAAECggIDAAAAA==.Mangoloidman:BAAALAADCgcICQAAAA==.',Mc='Mcflurry:BAAALAADCgcICQABLAAECggIBAABAAAAAA==.Mctilly:BAAALAADCgcIBwAAAA==.',Me='Mediev:BAAALAAECgEIAQABLAAECgcICQABAAAAAA==.Meekers:BAEALAAFFAMIBAAAAA==.Megadd:BAAALAADCggICAAAAA==.Melindris:BAAALAAECgIIAgAAAA==.Meridah:BAAALAADCggIFQAAAA==.',Mi='Michaelvarr:BAAALAAECgQIBAAAAA==.Midorii:BAAALAADCggIDgAAAA==.Mightbeheals:BAAALAADCgMIAwAAAA==.Miiniishammy:BAAALAADCgcIDQAAAA==.Minar:BAAALAAECgIIBAABLAAECggIEgABAAAAAA==.Mintyhunt:BAAALAADCggICAAAAA==.Mirîa:BAAALAAECggICAAAAA==.Misarua:BAAALAAECgYIBgAAAA==.Miscreant:BAAALAADCggICAAAAA==.Mistamiyagi:BAAALAAECgMIAwAAAA==.',Mk='Mkultra:BAAALAAECgEIAQAAAA==.',Mo='Moneyshaught:BAAALAADCggICAABLAAECggIEAABAAAAAA==.Monipouch:BAAALAAECgYICwAAAA==.Moonchicken:BAAALAAECgEIAQAAAA==.Moondaisy:BAAALAAECgEIAQAAAA==.Moosesloth:BAAALAAECgUICAAAAA==.Morff:BAAALAADCgIIAgAAAA==.',Mu='Muffblaster:BAAALAAECgcICQAAAA==.Murphet:BAAALAAECgYIDgAAAA==.Muttonchops:BAAALAADCgcIAQAAAA==.',Na='Nacronissa:BAAALAADCgUIBQAAAA==.Narthvador:BAAALAADCgYIBgABLAAECgIIBAABAAAAAA==.Narthvoker:BAAALAADCgYICwABLAAECgIIBAABAAAAAA==.Nathenatra:BAABLAAECoEUAAIQAAgIgxg9CgB0AgAQAAgIgxg9CgB0AgAAAA==.Naturetacos:BAAALAAECgcIEAAAAA==.',Ne='Neb:BAAALAAECgUIBwAAAA==.Neeko:BAAALAAECgcIDwAAAA==.Nefertári:BAAALAAECgEIAgAAAA==.Nerzhûla:BAAALAAECgIIAgAAAA==.Nessä:BAAALAAECgMIAwAAAA==.Nezath:BAAALAADCgcIBwAAAA==.',Ni='Nickotine:BAAALAAECgcIDwAAAA==.Nikiku:BAAALAAECgMIAwAAAA==.',No='Nochu:BAAALAAECgYICQAAAA==.Nofsh:BAAALAADCgcIBwAAAA==.Nofshay:BAAALAADCgIIAgABLAAECggICwABAAAAAA==.Noktyx:BAAALAAECgIIBAAAAA==.Nosferåtu:BAAALAAECgQICwAAAA==.Nosolis:BAAALAAECgQIBgAAAA==.Nostick:BAABLAAECoEWAAIRAAgIyB7aDgCgAgARAAgIyB7aDgCgAgAAAA==.Novacrono:BAAALAAECgcIDwAAAA==.',Nu='Nuluwene:BAAALAADCggIDgAAAA==.',['Nà']='Nàwty:BAAALAAECgIIAgAAAA==.',['Nô']='Nôôk:BAAALAAECgMIAwAAAA==.',Oa='Oathbreaker:BAAALAADCgMIAwAAAA==.',Oc='Ocean:BAAALAAECgYIDAAAAA==.',Od='Odderpop:BAAALAADCgEIAQAAAA==.Odeinn:BAAALAADCgQIBAAAAA==.',Oh='Ohmydog:BAAALAADCgcIBwAAAA==.',Om='Omakinteh:BAAALAADCggICQAAAA==.',On='Onýx:BAAALAAECggIEAAAAA==.',Ot='Otherlebowsk:BAAALAAECgUICwAAAA==.',Oz='Ozoidi:BAAALAADCgcIDQAAAA==.',Pa='Paandorra:BAAALAADCgcIDAAAAA==.Pal:BAAALAADCggIEAAAAA==.Palxa:BAABLAAECoEVAAIPAAgIByTgBAA0AwAPAAgIByTgBAA0AwAAAA==.Pangittroll:BAAALAADCggICgAAAA==.Papatotems:BAAALAAECgQIBgAAAA==.Pastorpat:BAAALAADCgYIBgAAAA==.Pawluh:BAAALAADCgcICQAAAA==.',Pe='Peat:BAAALAADCgYIBgABLAAECgcIFAAFAGAfAA==.Perhaps:BAAALAAECgUICAAAAA==.Pern:BAAALAADCgMIAwABLAAECgYIDAABAAAAAA==.Petrichora:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.',Ph='Phatform:BAAALAADCggIEgAAAA==.',Pi='Pickwaton:BAAALAAECgQIBgAAAA==.Pikapowas:BAAALAAECgEIAQAAAA==.Pillie:BAAALAADCgQIBAAAAA==.Pils:BAAALAADCggICAAAAA==.',Pl='Plaguejr:BAAALAAECggICAAAAA==.Pld:BAAALAADCgcIDQAAAA==.',Po='Pokapanda:BAAALAADCgcIBwAAAA==.Ponyoo:BAAALAADCggIDgAAAA==.Poppzadin:BAAALAADCgcIBwAAAA==.Poppzbabe:BAAALAADCgMIAwAAAA==.Poppzy:BAAALAAECgIIAgAAAA==.Poptartkilla:BAAALAADCggIBAAAAA==.Porpol:BAAALAADCggIFwAAAA==.',Pr='Praize:BAABLAAECoEUAAQSAAgITh7tAQCnAgASAAcIkCDtAQCnAgATAAEIfg4ORwBIAAAUAAEIJRCIWwA+AAAAAA==.Protectmeh:BAAALAAECgQIBAAAAA==.Proteine:BAAALAADCgcIBwAAAA==.',Ps='Psychologyy:BAAALAAECgIIAgAAAA==.Psykopathik:BAAALAADCggIEAAAAA==.Psyvoker:BAAALAADCgMIAwAAAA==.',Pu='Puccii:BAAALAAECgYIDgABLAAECggIGQAKAFIfAA==.Pulp:BAAALAADCgYIBgAAAA==.',Pw='Pworddumbo:BAAALAAECgYICQAAAA==.',Py='Pyrosternia:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.',Qh='Qhaoz:BAAALAAECgYIDQAAAA==.',Qi='Qirl:BAAALAADCggICwAAAA==.',Qt='Qti:BAAALAADCgYIBwAAAA==.',Qu='Quadnines:BAAALAAECgMIAwAAAA==.Quesly:BAAALAAECgUIBwAAAA==.Quinnlenn:BAAALAAECgQICgAAAA==.',Ra='Raeliy:BAAALAADCggICAAAAA==.Rageona:BAAALAADCggIBwAAAA==.Rajnikaant:BAAALAAECgQIBQAAAA==.Rajuk:BAAALAADCgEIAQAAAA==.Rakash:BAAALAADCggIFwAAAA==.Ramthura:BAAALAAECgUIBQAAAA==.Rangen:BAAALAADCgUIBwAAAA==.Ratarga:BAAALAAFFAEIAQAAAA==.Ratlok:BAAALAAFFAMIBAAAAA==.Ratnasty:BAAALAADCgIIAgAAAA==.Rattalia:BAAALAAECgQIBQAAAA==.Rattroll:BAAALAADCgcIBwABLAAFFAEIAQABAAAAAA==.Ravenaa:BAAALAAECgMIBgAAAA==.',Re='Realmwalker:BAAALAAECggIAwAAAA==.Recurves:BAAALAAECgMIAwAAAA==.Reet:BAAALAADCgcIBwAAAA==.Relweave:BAAALAAECgYICAAAAA==.Remessa:BAAALAAECgYICQAAAA==.Renzer:BAAALAAECgMIBQAAAA==.Restasis:BAAALAADCgcIBwAAAA==.Reveluv:BAAALAAECgUIBQAAAA==.',Rh='Rhaellia:BAAALAAECgIIAgAAAA==.Rhaenyratar:BAAALAAECgYICQAAAA==.',Ri='Riasgremory:BAAALAADCgEIAQAAAA==.Righturn:BAAALAADCggICgABLAAECgYIDAABAAAAAA==.Rigormorty:BAAALAAECgYICwAAAA==.Rinaera:BAAALAAECgMIAwAAAA==.Rix:BAAALAAECgcICgAAAA==.',Ro='Robinschwan:BAAALAAECgQIBgAAAA==.Rohna:BAAALAAECgIIAgABLAAECgQIBAABAAAAAA==.Rollindirty:BAABLAAECoEUAAIFAAcIYB9zBQBZAgAFAAcIYB9zBQBZAgAAAA==.Rollinhammer:BAAALAADCgMIAwAAAA==.Romanoff:BAAALAADCgMIBgAAAA==.Rotted:BAAALAAECgYIBgAAAA==.Rougeapy:BAAALAADCgMIAwAAAA==.',Rr='Rrazzo:BAAALAADCggIEAABLAAECgIIBAABAAAAAA==.',Ru='Rufio:BAAALAAECgYICAAAAA==.Rufiz:BAAALAADCgcIBgAAAA==.Runewulun:BAAALAADCggIDgAAAA==.',['Ró']='Róbbin:BAAALAADCgYICwAAAA==.Róbin:BAAALAADCgIIAgAAAA==.',Sa='Sabryel:BAAALAAECgYICgAAAA==.Saizead:BAAALAAECgEIAQAAAA==.Sandsniper:BAAALAAECgMIBQAAAA==.Sanghelli:BAAALAAECgcIEwAAAA==.Sangosu:BAAALAAECgMIAwAAAA==.Sapling:BAAALAAECgYICAAAAA==.Savus:BAAALAAECgMIAwAAAA==.',Sc='Scatzug:BAAALAAECgEIAQAAAA==.Sclubsvn:BAAALAAECgUICgAAAA==.Scootsymalon:BAAALAAECgEIAQAAAA==.',Se='Seanthepries:BAAALAAECgYIEwAAAA==.Secretaznman:BAAALAAECgYIDAAAAA==.Selianari:BAAALAADCgYIBgAAAA==.Serialheal:BAAALAAECgYIDgAAAA==.Sevalynn:BAAALAAECggIEAAAAA==.Señorveliat:BAAALAADCggIBwAAAA==.',Sh='Shadowlilith:BAAALAADCgcIDAAAAA==.Shamanfresh:BAAALAADCgMIAwAAAA==.Shaokahn:BAAALAADCgYICgAAAA==.Shaunmonk:BAAALAADCggICAAAAA==.Shaydsters:BAAALAAECgIIAgAAAA==.Sheetboxhntr:BAAALAAECgYICgAAAA==.Shinso:BAAALAAECgcIDQABLAAECggIFwALAA8eAA==.Shiwang:BAAALAAECggIEAAAAA==.Shockazulu:BAAALAAECgYIBgABLAAECgYICwABAAAAAA==.Shockfizts:BAAALAADCgYICQAAAA==.Shocktherapy:BAAALAAECgQIBQAAAA==.Shockzilla:BAAALAADCgcIDQAAAA==.Shogunhanzo:BAAALAADCgcICAAAAA==.Shwoop:BAAALAAECgEIAQABLAAECgYICwABAAAAAA==.',Si='Sigurrose:BAAALAADCggIFQAAAA==.Sista:BAAALAAECgQICAAAAA==.',Sk='Skheals:BAAALAAECgYICgAAAA==.',Sl='Slùgmuffìn:BAAALAAECggIDQAAAA==.',Sm='Smetrios:BAAALAADCggICAABLAAECggIEAABAAAAAA==.Smoka:BAAALAAECgYIDQAAAA==.Smokedh:BAAALAAECgQIBgABLAAECgYIBwABAAAAAA==.Smokezug:BAAALAAECgUICAABLAAECgYIBwABAAAAAA==.Smolfox:BAAALAADCgUIBQAAAA==.Smãllpãckage:BAAALAADCgcIBwAAAA==.Smökëÿ:BAAALAAECgIIAwAAAA==.',Sn='Sn:BAAALAAECgcIDgAAAA==.Snorter:BAAALAAECgcIEAAAAA==.Snowfury:BAABLAAECoEUAAICAAgIsiFOBgD+AgACAAgIsiFOBgD+AgAAAA==.Snuffaluffa:BAAALAADCgYIBgABLAAECgYIEQABAAAAAA==.',So='Solamina:BAAALAAECgYIBgAAAA==.Sonaela:BAAALAAECgMIBAAAAA==.Sourdeath:BAAALAAECgMIAwAAAA==.',Sp='Spacemarine:BAAALAADCgUIBQAAAA==.Spageti:BAAALAADCgYIBgAAAA==.Spartachan:BAAALAAECgEIAQAAAA==.Spiritfingrz:BAAALAAECgMIAwAAAA==.Spit:BAAALAAECgYIBgAAAA==.Splendipulos:BAAALAAECgYIBgAAAA==.',Ss='Ssnoosnoo:BAAALAAECgMIAwAAAA==.',St='Stanchion:BAAALAADCgMIAwAAAA==.Statíc:BAAALAADCgcIBwAAAA==.Stiffe:BAAALAAECgMIBQAAAA==.Stolen:BAAALAAECgYIBgABLAAECgcIEQABAAAAAA==.Stromshield:BAABLAAECoEYAAIPAAgISBxrEACGAgAPAAgISBxrEACGAgAAAA==.',Su='Suicideblond:BAAALAADCggIPQAAAA==.Sunnyz:BAAALAAECgUIBQAAAA==.Supaflash:BAABLAAECoEUAAMOAAgIJiAtAwC/AgAOAAgIJiAtAwC/AgAPAAQI8g9CUQAAAQAAAA==.Surfnturf:BAAALAAECgYICAAAAA==.Surprisê:BAAALAAECgcIEQAAAA==.',Sy='Syladstrasza:BAAALAADCggIFQAAAA==.Sylvaticus:BAAALAAECgEIAQAAAA==.Sylwyn:BAAALAAECgUICQAAAA==.Syross:BAAALAAFFAEIAQAAAA==.',Sz='Szeto:BAAALAAECgQIBgABLAAECggIGQAKAFIfAA==.',Ta='Tacobreth:BAAALAAECgQIBAAAAA==.Tah:BAAALAADCggICAAAAA==.Talonarayan:BAAALAAECgEIAQAAAA==.Talrock:BAAALAAECgMIAwAAAA==.Tamran:BAAALAAECgMIAwAAAA==.',Te='Teldrus:BAAALAADCgIIBAAAAA==.Tenderfel:BAAALAAECgEIAgAAAA==.Terraconis:BAAALAADCgYIBgAAAA==.Tewasha:BAAALAAECgYIDAAAAA==.',Th='Thalryn:BAAALAAECgMIBAAAAA==.Thanös:BAAALAADCgYIBgAAAA==.Themainzest:BAAALAAECgMIAwAAAA==.Theodore:BAAALAADCgMIAwAAAA==.Thesinner:BAAALAAECggIEQAAAA==.Thiccmage:BAAALAAECgMIBQABLAAECgYIBwABAAAAAA==.Thobos:BAAALAAECggIDQAAAA==.Thorlok:BAAALAAECgMIAwAAAA==.Throth:BAAALAADCgcICQAAAA==.Thul:BAAALAAECggIEgAAAA==.Thunderstry:BAAALAAECgQIBgAAAA==.Thuringwethl:BAAALAADCgYIDQAAAA==.',Ti='Tiggars:BAABLAAECoEUAAIGAAcI0RT+GwDGAQAGAAcI0RT+GwDGAQAAAA==.Tinydigger:BAAALAADCgcIDQAAAA==.Tinyfist:BAAALAAECggIAQAAAA==.Tiyy:BAAALAAECgIIAgAAAA==.',Tl='Tlacate:BAAALAADCgQIBAAAAA==.',Tn='Tnastyy:BAAALAADCgEIAQAAAA==.',To='Tongosami:BAAALAADCgcIDQABLAAECgMIBAABAAAAAA==.Tonight:BAAALAAECgQIBAAAAA==.Toraa:BAAALAADCgUIBgAAAA==.Totertotz:BAAALAAECggIDgAAAA==.',Tr='Tramana:BAAALAAECgUIDAAAAA==.Trauk:BAAALAAECgMIAwAAAA==.Trecks:BAAALAAECgIIAgAAAA==.Troggy:BAAALAADCgQIBAABLAADCgcIDAABAAAAAA==.Trollcopter:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Trollwíthbow:BAAALAAFFAEIAQAAAA==.Tropheus:BAAALAADCggICAAAAA==.',Tw='Tweedledumb:BAAALAAECggIEAAAAA==.Twochains:BAAALAAECgQIBgAAAA==.',Ty='Tyfirna:BAAALAADCgcIBwAAAA==.',Ul='Uly:BAAALAAECgUICQAAAA==.Ulyy:BAAALAADCggIDgAAAA==.',Um='Umakai:BAAALAAECgIIAgAAAA==.',Un='Uneartth:BAAALAADCgIIAgAAAA==.Unnerfable:BAAALAADCgEIAQAAAA==.Unstayble:BAAALAADCgYIBgAAAA==.',Ur='Urawizrdhary:BAAALAADCggICAAAAA==.Urouge:BAAALAAECgYIDwABLAAECggIGQAKAFIfAA==.',Va='Vacula:BAAALAAECgYICQAAAA==.Vailiq:BAAALAAECgYIBwABLAAECgYICgABAAAAAA==.Valreaux:BAAALAAECgYIBwAAAA==.',Ve='Velacour:BAAALAADCgIIAgAAAA==.Veneration:BAAALAADCggIDgAAAA==.Venâtor:BAAALAADCgcIBwAAAA==.Vetting:BAAALAAECgMIAgAAAA==.Vex:BAAALAAECgYIDAAAAA==.',Vh='Vhx:BAAALAADCgYIBgABLAAECgcIEQABAAAAAA==.',Vi='Vianthe:BAAALAADCgMIAwAAAA==.Vikktoria:BAAALAADCgIIAgAAAA==.Viseryss:BAAALAADCggIFAAAAA==.',Vl='Vladdamir:BAAALAADCgEIAQAAAA==.',Vo='Voidance:BAAALAADCgcICgAAAA==.Voidheart:BAAALAADCgYIBgAAAA==.Voidling:BAAALAADCgYICQAAAA==.Volarke:BAAALAADCgcIBwAAAA==.Vortexis:BAAALAAECgUIBwAAAA==.Voìdborn:BAAALAAECgYIBwAAAA==.',Vy='Vyndk:BAAALAAECgcIDQAAAA==.',Wa='Walkinghealz:BAAALAADCggIFQABLAAECgYIDgABAAAAAA==.Wanderrerr:BAAALAADCgcIBwAAAA==.',Wh='Whatthemage:BAAALAAECgcIDQABLAAFFAEIAQABAAAAAA==.',Wi='Wijin:BAAALAAECgYIBwAAAA==.Willyouchill:BAAALAADCggICAAAAA==.Windfrey:BAAALAADCgQICAAAAA==.Windsong:BAAALAADCgcIBwAAAA==.Winterfáll:BAAALAADCgMIAwAAAA==.',Wo='Wobs:BAAALAAECgcICAAAAA==.Woopoles:BAAALAADCggICAAAAA==.',['Wå']='Wårlordårés:BAAALAADCgMIAwAAAA==.',Xa='Xalazoth:BAAALAADCggICAAAAA==.Xavierdh:BAAALAAECgMIAwAAAA==.',Ya='Yabadabadoo:BAAALAAECgMIAwAAAA==.Yahboibangz:BAAALAAECgYICgAAAA==.Yamikaneki:BAAALAADCggICAABLAAECgcIFAAFAGAfAA==.Yanci:BAAALAADCgcIDQAAAA==.',Yc='Ycetz:BAAALAAECgYIDAAAAA==.',Ye='Yearn:BAAALAADCgcIBwAAAA==.Yehdigg:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.',Za='Zalaraxe:BAAALAADCggIDwAAAA==.Zarra:BAAALAADCgcIBwAAAA==.Zathora:BAAALAADCgUIBQAAAA==.',Ze='Zenkic:BAAALAADCgcIDgAAAA==.Zenlock:BAAALAADCgYIBgAAAA==.Zephyræ:BAAALAADCgYIBgAAAA==.',Zm='Zmjjkk:BAAALAAECggIDgAAAA==.',Zo='Zonstab:BAAALAADCgYIBgAAAA==.Zontarr:BAAALAAECgEIAQAAAA==.',['Èm']='Èmily:BAAALAADCggIDgAAAA==.',['Ét']='Éthos:BAAALAAECgUIBwAAAA==.',['Ön']='Önonta:BAAALAADCgMIAwAAAA==.Önotoes:BAAALAAECgMIAwAAAA==.',['ßr']='ßrightskull:BAAALAAECgQIBwAAAA==.',['ßu']='ßug:BAAALAADCgEIAQABLAAECgQIBAABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end