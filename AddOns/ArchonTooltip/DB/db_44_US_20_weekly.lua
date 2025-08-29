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
 local lookup = {'Shaman-Elemental','Mage-Arcane','Mage-Frost','Rogue-Assassination','Unknown-Unknown','Priest-Shadow','Monk-Mistweaver','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Priest-Holy','Evoker-Devastation','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Protection','Druid-Balance','Warrior-Fury','DeathKnight-Frost','Paladin-Holy','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Havoc','DeathKnight-Blood','Monk-Brewmaster',}; local provider = {region='US',realm='Arthas',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abacas:BAABLAAECoEXAAIBAAgIrx58CgCsAgABAAgIrx58CgCsAgAAAA==.Abominant:BAAALAAECgQIBwAAAA==.Abrohms:BAAALAAECgYIDQAAAA==.',Ac='Ackrenoth:BAAALAADCgEIAQAAAA==.',Ad='Adua:BAAALAADCggICAAAAA==.',Ae='Aelare:BAAALAADCgcICQAAAA==.Aerovix:BAAALAADCgUICAAAAA==.Aethryn:BAAALAADCgYIBgAAAA==.Aevist:BAAALAAECgcICgAAAA==.',Ai='Airfryer:BAABLAAECoEWAAMCAAgI9SGpDwCjAgACAAgIOSGpDwCjAgADAAIIviFzMACTAAAAAA==.Ais:BAAALAAECgYICAAAAA==.Aitsu:BAABLAAECoEXAAIEAAgIKyMABAAFAwAEAAgIKyMABAAFAwAAAA==.Aivy:BAAALAAECgcIEAAAAA==.',Ak='Akkula:BAAALAAECgMIBgAAAA==.Akrios:BAAALAADCggIFgAAAA==.',Al='Alfadelle:BAAALAADCgMIAwAAAA==.Allinah:BAAALAAECgIIAgAAAA==.Alloran:BAAALAADCgcIAQAAAA==.Alujin:BAAALAAECgMIAwAAAA==.Alwaysgrumpy:BAAALAADCgIIAgAAAA==.',Am='Amaraku:BAAALAADCgEIAQAAAA==.',An='Anathor:BAAALAAECgUICgAAAA==.Ancstrlbower:BAAALAAECgMIBAAAAA==.Anetra:BAAALAADCgcIFAAAAA==.Animosiity:BAAALAAECgYIBgABLAAECgYIDgAFAAAAAA==.Anot:BAAALAADCgYIBgAAAA==.',Ao='Aonyx:BAAALAADCgcIBwAAAA==.',Aq='Aqi:BAAALAAECgYIBwAAAA==.',Ar='Araessa:BAAALAADCggICwAAAA==.Arcanewitch:BAAALAADCgQIBgAAAA==.Arcueid:BAAALAADCgYIBgAAAA==.Ariannia:BAAALAADCgcIBwAAAA==.Aridaios:BAAALAADCgcIDQAAAA==.Arkemesis:BAAALAADCgQIBAAAAA==.Arkys:BAAALAADCgYIBwAAAA==.Armillaria:BAAALAADCgYIBgAAAA==.Arrowyn:BAAALAADCggIFgAAAA==.Artaith:BAAALAAECgYICQAAAA==.Artzshock:BAAALAAECgEIAQAAAA==.',As='Ashtoka:BAAALAADCgcIDgAAAA==.Assanet:BAAALAAECgYIBgAAAA==.Astra:BAAALAAECgMIAwAAAA==.',At='Attimonk:BAAALAAECggIEQAAAA==.',Au='Auralystra:BAAALAADCgcIDQAAAA==.Auspicious:BAAALAADCgUIBwAAAA==.',Av='Avadin:BAAALAAECgcIDwAAAA==.Aversa:BAAALAAECgYIDAAAAA==.',Ay='Ayoubsnzy:BAAALAADCggIBwAAAA==.',Az='Azeran:BAAALAAECgUIBgAAAA==.Azeroth:BAAALAAECgYICAAAAA==.Azrielius:BAAALAAECgIIAgAAAA==.Aztoa:BAAALAADCgcIBwAAAA==.Aztoka:BAAALAADCggICQAAAA==.',Ba='Baelor:BAAALAADCgcIBwAAAA==.Bai:BAAALAAECgIIAgAAAA==.Baldelomar:BAAALAADCgYIDAAAAA==.Bapped:BAAALAADCggIEQABLAAECgQIBAAFAAAAAA==.Barkside:BAAALAADCgIIAQAAAA==.Bastock:BAAALAAECgYICgAAAA==.',Be='Beeanzz:BAAALAADCgMIAwAAAA==.Belavik:BAAALAAECgcIEwAAAA==.Bellamere:BAAALAAECgQIBgAAAA==.Bennyblancoo:BAAALAADCgYIBgAAAA==.Berako:BAAALAAECgEIAQAAAA==.Beuller:BAAALAADCgcIBgAAAA==.',Bi='Bibidibobidi:BAAALAAECgEIAQAAAA==.Bigholycrits:BAAALAADCggICAAAAA==.Bigpainpal:BAAALAAECgMIBgAAAA==.Bigshlappy:BAAALAAECgMIAwAAAA==.Bigshloppy:BAAALAAECgIIAgAAAA==.Bigsloopy:BAAALAADCgUIBQAAAA==.Bigslopper:BAAALAADCgUIBQAAAA==.Bigzap:BAAALAADCgUIBQAAAA==.Billysblade:BAAALAAECggIEQAAAA==.Binker:BAAALAAECgEIAQAAAA==.',Bl='Bladelord:BAAALAADCgUIBQAAAA==.Blightful:BAAALAAECgEIAQAAAA==.Blitzbuster:BAAALAAECgUIBwAAAA==.Blladee:BAAALAADCggICAABLAAECgUIBgAFAAAAAA==.Bloogai:BAAALAADCgYIDAAAAA==.Bluëberry:BAAALAAECgYIBgAAAA==.',Bo='Bonomage:BAAALAAECgMIAwAAAA==.Boombayah:BAAALAAECgYIBgAAAA==.Boomkins:BAAALAAECgUIBgAAAA==.Bootypi:BAABLAAECoEXAAIGAAgIPiHlBgDlAgAGAAgIPiHlBgDlAgAAAA==.Bostoncreme:BAAALAAECgcIBwABLAAECgcIEAAFAAAAAA==.',Br='Branifus:BAAALAAECgYICAAAAA==.Brilline:BAAALAADCggICwAAAA==.Brity:BAAALAADCgYIBgAAAA==.Brockly:BAAALAAECgYICgAAAA==.Brotorious:BAAALAAECgYIDQAAAA==.Brucetree:BAAALAADCgYICwAAAA==.',Bs='Bschwizzle:BAAALAAECgUIBwAAAA==.',Bu='Bueford:BAAALAADCgcIBwAAAA==.Bumii:BAAALAADCggIDgAAAA==.Bungie:BAAALAADCggICAAAAA==.Burkmon:BAAALAAECgMIBQAAAA==.Butseven:BAAALAAECgUIBQAAAA==.Butterbubble:BAAALAAECgIIAwAAAA==.',Bw='Bwirdy:BAAALAAECgUIBQAAAA==.',['Bâ']='Bârt:BAAALAADCgUIBQAAAA==.',['Bê']='Bêärdlover:BAAALAAECggICAAAAA==.',['Bø']='Bøøk:BAAALAADCggICQAAAA==.',['Bü']='Büzz:BAAALAADCgUIBwAAAA==.',Ca='Cadriel:BAAALAADCgYICQAAAA==.Cadu:BAAALAAECgMIBgAAAA==.Cailleách:BAAALAADCggIDwAAAA==.Calthron:BAAALAAECgMIAwAAAA==.Calumen:BAAALAAECgcICwAAAA==.Cannaorganix:BAAALAADCgUICAAAAA==.Cantmilktho:BAAALAAECgMIAwAAAA==.Capoo:BAAALAAECgEIAQABLAAECgMIAwAFAAAAAA==.Captbojack:BAAALAADCgYICwAAAA==.Carban:BAAALAADCgcICgAAAA==.Cardiacattck:BAAALAADCgYIEQAAAA==.Caribou:BAAALAAECgMIBAAAAA==.Carint:BAAALAADCgYIBgAAAA==.Carnages:BAAALAADCgYIBgABLAAECgUIBwAFAAAAAA==.Castíel:BAAALAAECgIIAgAAAA==.Catjam:BAAALAADCgEIAQAAAA==.Catta:BAAALAAECgYIDAAAAA==.Cazzame:BAAALAADCgUIBQAAAA==.',Ce='Ceren:BAAALAAECgEIAQAAAA==.Cerilio:BAAALAAECgMIAwAAAA==.',Ch='Chacheroni:BAAALAADCgYIBgAAAA==.Chitbricks:BAAALAADCgYICQAAAA==.Chivyn:BAABLAAECoEVAAIHAAgI6h7OAwC7AgAHAAgI6h7OAwC7AgAAAA==.Chloe:BAAALAAECgEIAgAAAA==.Chogak:BAAALAADCgcICwAAAA==.Chrizard:BAAALAAECgMIAwAAAA==.Chylan:BAAALAAECgcICwAAAA==.',Ci='Cian:BAAALAADCggIDAAAAA==.Cincolobos:BAAALAAECgYICgAAAA==.Cinnaminsaph:BAAALAADCgcICQAAAA==.Cityweaves:BAABLAAECoEXAAIHAAgIzCSZAABRAwAHAAgIzCSZAABRAwAAAA==.',Cl='Clarkswife:BAAALAAECgYICgAAAA==.',Co='Coldkneez:BAAALAAECgEIAQAAAA==.Conri:BAAALAAECgMIBAAAAA==.Cornelius:BAAALAADCggIEwAAAA==.',Cp='Cptthunder:BAAALAAECgUICwAAAA==.',Cr='Crajor:BAAALAADCgcICAAAAA==.Critaurus:BAAALAAFFAEIAQAAAA==.Cronstione:BAAALAAECgUIBgAAAA==.Crushinater:BAAALAAECgYIDAAAAA==.',Cu='Cutekiller:BAAALAAECgcICwAAAA==.Cutgrass:BAAALAADCgcIBwAAAA==.',['Cô']='Côrack:BAAALAAFFAIIAgAAAA==.Côôkiemonstr:BAAALAADCggICAABLAAECggIEgAFAAAAAA==.',Da='Daddydeath:BAAALAAECgcICwAAAA==.Daedríc:BAAALAAECgcIDgAAAA==.Daeemon:BAAALAAECgMIBQAAAA==.Daktzen:BAAALAAECgcIDgAAAA==.Dalraeda:BAAALAAECgYIBgABLAAECgYICQAFAAAAAA==.Darkseer:BAAALAAECgUIBgAAAA==.Darreck:BAAALAAECgMIBAAAAA==.Darvus:BAAALAADCgYICQAAAA==.Davinity:BAAALAAECgMIBAAAAA==.Dazbezzaraz:BAAALAAECggIEQAAAA==.',Dd='Ddrizztt:BAAALAAECgYIDQAAAA==.',De='Deadnilly:BAAALAADCggIBQABLAADCggIBgAFAAAAAA==.Deathloky:BAAALAAECgYIBwAAAA==.Debussy:BAAALAADCggICgAAAA==.Deedlít:BAAALAADCgIIAgAAAA==.Deeroy:BAAALAADCgYIBgAAAA==.Dehmonia:BAABLAAECoEbAAQIAAgInB0MCwCaAgAIAAgIzxwMCwCaAgAJAAMI+AuXMgCkAAAKAAEIaAhSKQBJAAAAAA==.Dela:BAAALAAECgUIBwAAAA==.Delandèr:BAAALAADCgYIBwABLAAECgUIBwAFAAAAAA==.Delerino:BAAALAADCgYIBgABLAAECgUIBwAFAAAAAA==.Dementus:BAAALAADCgQIBAAAAA==.Demincy:BAAALAAECgYIDQAAAA==.Demoreon:BAAALAADCgQIBAAAAA==.Demïos:BAAALAAECgQIBQAAAA==.Denothar:BAAALAAECgIIAgAAAA==.Deset:BAAALAAECgYICgAAAA==.Despiration:BAAALAAFFAIIAwAAAA==.Devotion:BAAALAADCgMIAwAAAA==.Deylia:BAAALAAECgUIBgAAAA==.',Dh='Dhalthron:BAAALAADCgQIBAAAAA==.',Di='Dingùs:BAAALAAECgMIAwAAAA==.Dirkadeux:BAAALAAECggIEQAAAA==.Dirt:BAAALAAECgUIBQAAAA==.Dirtyûndys:BAAALAAECgIIAgABLAAECgIIAgAFAAAAAA==.Divine:BAAALAADCgYIBgAAAA==.Divinepath:BAAALAADCgQIBAAAAA==.',Dn='Dnp:BAAALAADCgIIAgAAAA==.',Do='Doesnttank:BAAALAAECgYIBwAAAA==.Dohnut:BAAALAAECgcIEAAAAA==.Dollkill:BAAALAADCgUIBQAAAA==.Donaldhump:BAAALAADCgYIBgABLAAECggIFAALAMUcAA==.Donk:BAAALAADCggIEwAAAA==.Doofensmrtz:BAAALAADCggIDgAAAA==.Doresain:BAAALAADCggIDwAAAA==.Dorit:BAAALAADCggIEAAAAA==.Doslobos:BAAALAADCggICAABLAAECgYICgAFAAAAAA==.Doughmaker:BAABLAAECoEXAAIMAAgIkiPJAQA2AwAMAAgIkiPJAQA2AwAAAA==.',Dr='Dragonraithe:BAAALAAECgMIAwAAAA==.Drainbabwe:BAAALAADCggICwAAAA==.Drakira:BAAALAADCgYIBgAAAA==.Draktaroth:BAAALAADCggIDAAAAA==.Drangoo:BAAALAAECgIIAQAAAA==.Dreambender:BAAALAADCggIFQAAAA==.Dreignos:BAAALAAECggIEQAAAA==.Drezzartwat:BAAALAAECgIIAgAAAA==.Drillbit:BAAALAADCggICAAAAA==.Drizztski:BAAALAADCgcIFQABLAAECgYIDQAFAAAAAA==.Drmcbandaid:BAAALAADCgEIAQAAAA==.Drowninkitty:BAAALAADCgUIBQAAAA==.Drunkpo:BAAALAADCgcICAAAAA==.',Ds='Dsylxeia:BAAALAAECgcIDQAAAA==.',Dy='Dykewondo:BAAALAADCgcICAAAAA==.Dyonarian:BAAALAADCgQIBAAAAA==.',['Dì']='Dìrtyundys:BAAALAADCgUICAABLAAECgIIAgAFAAAAAA==.',Ea='Earthlyrage:BAAALAAECgUIBwAAAA==.',Eb='Eberson:BAAALAAECgMIAwAAAA==.',Ec='Ecker:BAAALAAECgUIBQAAAA==.',Ed='Ednata:BAAALAAECgYIDAAAAA==.',Ee='Eepy:BAAALAAECgcIDAAAAA==.',Eg='Egg:BAAALAAECgYICwAAAA==.',Ei='Eidora:BAAALAAECgYIBwAAAA==.',Ek='Ekistraza:BAAALAADCggICAAAAA==.',El='Elarise:BAAALAADCgcIBwAAAA==.Elem:BAAALAAECgYIDQAAAA==.Elevonday:BAAALAAECgIIAgAAAA==.Elizaa:BAAALAADCgYIBgAAAA==.Ellanoteama:BAAALAAECgYICAAAAA==.Ellayri:BAAALAAECgMIBQAAAA==.Eloraa:BAAALAADCgYIBgAAAA==.',Em='Emo:BAAALAADCggIDgAAAA==.Emollama:BAAALAAECgYIDwAAAA==.',En='Endoblades:BAAALAAFFAEIAQAAAA==.Endobleeds:BAAALAADCgQIBAABLAAFFAEIAQAFAAAAAA==.Endorsi:BAAALAADCgEIAQAAAA==.Enforcers:BAAALAAECgMIBgAAAA==.Enmancement:BAAALAADCgcIBwAAAA==.',Er='Eradagon:BAAALAAECgMIBAAAAA==.Erzai:BAAALAAECgQIBAAAAA==.',Es='Eshtera:BAAALAAECgYIEAAAAA==.',Et='Etherious:BAAALAADCgcICwAAAA==.',Ev='Evisuration:BAAALAAECgMIBQAAAA==.Evokedu:BAAALAAECgcICwAAAA==.Evokemode:BAAALAAECgUIBgAAAA==.Evokhim:BAAALAADCgYIBQAAAA==.',Ex='Explosivoh:BAAALAAECgMIBgAAAA==.',Fa='Fady:BAAALAAECgcIDAAAAA==.Falkv:BAAALAAECgQIBQAAAA==.Famousqtx:BAAALAAECgMIBwAAAA==.Fanda:BAAALAADCgMIAwAAAA==.Fasminer:BAAALAADCgcIBwAAAA==.',Fe='Fearòshima:BAAALAAECgIIAgAAAA==.Feetpics:BAAALAAECgcICwAAAA==.Feldrak:BAAALAAECgcIDQAAAA==.Feldriu:BAAALAADCgcIFAAAAA==.Felkrimson:BAAALAADCgYIBwABLAAECgUICAAFAAAAAA==.Fellwaz:BAAALAADCgUIBQAAAA==.Feyth:BAAALAAECgEIAQAAAA==.',Fi='Fiarin:BAAALAAECgYIBgAAAA==.Fingerd:BAAALAADCgMIAwAAAA==.Fireshock:BAAALAAECgMIBAAAAA==.',Fl='Flapped:BAAALAAECgQIBAAAAA==.Flexious:BAAALAAECgUIBQAAAA==.Flexlight:BAAALAAECgEIAQAAAA==.',Fo='Folandra:BAAALAAECgMIAQAAAA==.Forceomega:BAAALAADCgQIBAAAAA==.Fotosynthsis:BAAALAADCgcIDgAAAA==.Foxyladeh:BAAALAADCgYIBgAAAA==.',Fr='Fraw:BAAALAAECgYIEQAAAA==.Frerejacques:BAAALAAECgQIBQAAAA==.Friskies:BAAALAADCgcIBwAAAA==.Frogussy:BAAALAADCgYICAAAAA==.Frostkissed:BAAALAADCgcIDQAAAA==.Frostytongue:BAAALAADCggIDgAAAA==.Frozenboner:BAAALAADCggIDwABLAAECgUIBwAFAAAAAA==.Fròstitute:BAAALAADCgUIBQAAAA==.',Fu='Fuzedstera:BAABLAAECoEXAAQJAAgIlSLQBQAJAgAJAAYIryTQBQAJAgAIAAQIBx/LKgBhAQAKAAIIGQohHQCWAAABLAAFFAIIAgAFAAAAAA==.',Ga='Gadrok:BAAALAADCgcIBwAAAA==.Gainz:BAAALAAECgUIBgAAAA==.Galadriella:BAAALAADCggIDgAAAA==.Galva:BAAALAAECgMIBAAAAA==.Garyness:BAABLAAECoEXAAINAAgIqBbRDQAvAgANAAgIqBbRDQAvAgAAAA==.',Ge='Gekiretsu:BAAALAAECgcIDgAAAA==.Gerbil:BAAALAAECgYICwAAAA==.',Gh='Ghostdabs:BAAALAAECgMIBAAAAA==.',Gi='Gilwood:BAABLAAECoEXAAMOAAgIfh5xCwBbAgAOAAgIHxtxCwBbAgAPAAEIXyIbZgBfAAAAAA==.Gingyr:BAAALAADCggIFgAAAA==.Girthyquake:BAAALAADCggICAAAAA==.',Gl='Gloinn:BAABLAAECoEXAAICAAgIWhs4FABzAgACAAgIWhs4FABzAgAAAA==.',Go='Goaskyomama:BAAALAAECgMIAwAAAA==.Goblinesmie:BAAALAAECgMIBAAAAA==.Goliâth:BAAALAADCgcIDQAAAA==.Gombie:BAAALAAECgMIAwAAAA==.Gozuryu:BAAALAADCggIDQAAAA==.',Gr='Graetx:BAAALAAECgcICwAAAA==.Gravan:BAAALAADCgcIBwAAAA==.Grawd:BAAALAAECgMIBAAAAA==.Greatscoob:BAAALAADCgIIAgAAAA==.Grezzdorn:BAAALAAECgEIAQAAAA==.Grimpterror:BAAALAADCgUIBQABLAAECggIFAAJAEAiAA==.Grimwar:BAABLAAECoEUAAMJAAgIQCLdBAAeAgAJAAcIUyDdBAAeAgAKAAII+SSsFQDbAAAAAA==.Gripthis:BAAALAAECgEIAQAAAA==.Grokironhide:BAAALAADCgIIAgAAAA==.Grotaour:BAAALAADCgMIAwAAAA==.',Gu='Guesswholoky:BAAALAADCgYIBgAAAA==.Gulmatt:BAAALAAECgIIAgAAAA==.Guxue:BAAALAADCgUIBQAAAA==.',['Gë']='Gëtshwiftÿ:BAAALAADCgUIBQAAAA==.',['Gí']='Gílgamore:BAAALAAECggIEwAAAA==.',Ha='Hakaska:BAAALAADCgEIAQAAAA==.Hakâi:BAAALAADCggIFgAAAA==.Hanswolo:BAAALAADCgQIBAAAAA==.Hardtack:BAAALAAECgMIBAAAAA==.Hargrim:BAAALAADCggIEgAAAA==.',He='Hellbrringer:BAAALAAECgcIBwAAAA==.Helliod:BAAALAADCgYIBQAAAA==.Hellõ:BAAALAAECgMIBgAAAA==.Heycreative:BAAALAAECggICgAAAA==.',Hi='Hibred:BAAALAAECggICwAAAA==.Highlock:BAAALAAECggIDAAAAA==.Hitchbotnee:BAAALAAECgYIBwAAAA==.',Ho='Hoffit:BAAALAADCggIDwAAAA==.Holidei:BAAALAADCggIFwAAAA==.Holopa:BAABLAAECoEVAAIQAAgIBSDYAgDeAgAQAAgIBSDYAgDeAgAAAA==.Holycowbaby:BAAALAADCgYIBQAAAA==.Holymood:BAAALAADCggIBwAAAA==.Holysam:BAAALAADCggIDQAAAA==.Hooflepuff:BAAALAAFFAIIAgAAAA==.Hornguy:BAAALAAECgEIAQAAAA==.Hozakis:BAAALAAECgMIBAAAAA==.',Hs='Hsr:BAAALAAECgQIBgAAAA==.',Hu='Huataurga:BAAALAAECgYICgAAAA==.Huff:BAAALAAECgcIDQABLAAFFAIIAgAFAAAAAA==.Hugsy:BAAALAADCgcICAAAAA==.Hukmentation:BAAALAADCgYIBgABLAAECgUIBQAFAAAAAA==.Hunternin:BAAALAAECgMIBQAAAA==.Hunterzirn:BAAALAAECggICAAAAA==.Hurgan:BAAALAAECgMIBQAAAA==.Hussyhunt:BAAALAADCgMIAwAAAA==.Hussypal:BAAALAADCgUIBQAAAA==.Hussypriest:BAAALAADCggIFgAAAA==.',Hy='Hykari:BAAALAADCgcIBwAAAA==.',['Hà']='Hàchi:BAABLAAECoEXAAIRAAgIMiZPAQBiAwARAAgIMiZPAQBiAwAAAA==.',['Hä']='Hämwallet:BAAALAAECgcIBwAAAA==.',['Hê']='Hêmophiliac:BAAALAAECggICAABLAAECggIEgAFAAAAAA==.',['Hì']='Hìtt:BAAALAADCggIEgAAAA==.',Ib='Ibnlaahad:BAAALAADCgcIBwABLAADCggIFQAFAAAAAA==.',Id='Idontmind:BAAALAADCgIIAgAAAA==.',Ig='Igómoo:BAAALAADCgcIBwAAAA==.',Il='Ilovemydrake:BAAALAADCggIDQAAAA==.Iluvgothgrls:BAAALAADCgcICAABLAADCggICwAFAAAAAA==.Ilûminati:BAAALAADCggIDQAAAA==.',Im='Imlagging:BAAALAADCgYIBgAAAA==.',In='Infernalmasa:BAABLAAECoEWAAMJAAgILxpwCQDOAQAJAAcIUhpwCQDOAQAIAAUIOBl0JgB/AQAAAA==.Inkubator:BAAALAAECgcIEQAAAQ==.Innai:BAAALAAECgQIBAABLAAECggIFwASAPYfAA==.Innerpeace:BAAALAAECgEIAQAAAA==.Inos:BAAALAAECgMIAwAAAA==.',Io='Iocktart:BAAALAADCgIIAgAAAA==.',Ir='Iratedreamer:BAAALAAECgMIAwAAAA==.Irronhidee:BAAALAAECgUIBgAAAA==.',Is='Isnotadragon:BAAALAAECgUICwAAAA==.',It='Itsthebaby:BAAALAAECgMIAwAAAA==.',Iv='Iveth:BAAALAADCgcIBwAAAA==.',Iy='Iyamdemon:BAAALAADCgEIAQAAAA==.Iyamwarlock:BAAALAADCggICAAAAA==.',Iz='Izanagi:BAAALAADCggIDwAAAA==.',Ja='Jaco:BAAALAADCggIDgAAAA==.Jakareo:BAAALAAECgYIBwAAAA==.Jalwyze:BAAALAAECgUIBQAAAA==.Janeene:BAAALAADCgYIBwAAAA==.Jasyndar:BAAALAADCggIEAAAAA==.',Je='Jeffington:BAAALAAECgEIAQAAAA==.',Ji='Jirehn:BAAALAAECggICQAAAA==.',Ka='Kaeyle:BAABLAAECoEWAAILAAgI7x2yDAC4AgALAAgI7x2yDAC4AgAAAA==.Kafka:BAAALAAECggIDgAAAA==.Kainnan:BAAALAADCgcIBAAAAA==.Kaladan:BAAALAAECggICAAAAA==.Kanra:BAAALAADCgcICAAAAA==.Kansurm:BAAALAADCgYIBgAAAA==.Katfury:BAAALAAECggIEQAAAA==.Katyr:BAAALAAECggIAQAAAA==.Kaylai:BAAALAADCgcIDQAAAA==.',Ke='Kehradriël:BAAALAADCgQIBAAAAA==.Keiralightly:BAAALAADCggICAAAAA==.Kem:BAAALAADCgcIBwAAAA==.',Kg='Kgee:BAAALAADCgQIBAAAAA==.',Kh='Khealz:BAAALAAECgMIBQAAAA==.',Ki='Killablessed:BAAALAADCggICAAAAA==.Kindraki:BAABLAAECoEVAAITAAgIuxibEgBwAgATAAgIuxibEgBwAgAAAA==.Kirbÿ:BAAALAADCggIFgAAAA==.',Kl='Kleinenstein:BAAALAADCgMIAwAAAA==.Klurlax:BAAALAADCgcIDQAAAA==.',Kn='Knowone:BAAALAAECgUICQAAAA==.',Ko='Kodita:BAAALAADCgIIAgAAAA==.Kohdå:BAAALAADCgMIAwAAAA==.Komosky:BAEALAADCggIAgAAAA==.Kongfumaster:BAAALAAECgcIBwAAAA==.Kordathi:BAAALAADCgcIDgABLAAECgYIDQAFAAAAAA==.Kordelea:BAAALAAECgYIDQAAAA==.Korgran:BAAALAADCgUIBQAAAA==.Kovenant:BAAALAADCgQIBAAAAA==.',Kr='Krakair:BAAALAADCggICAAAAA==.Krendalor:BAAALAADCgQIBAAAAA==.Krimsonmage:BAAALAAECgMIAwABLAAECgUICAAFAAAAAA==.Kryptic:BAAALAAECgUIBgAAAA==.',Ku='Kushmasta:BAAALAADCgcIBwAAAA==.',Ky='Kylea:BAAALAAECgMIBQAAAA==.Kysira:BAAALAAECgMIBAAAAA==.',La='Lacouturiere:BAAALAAECgEIAgAAAA==.Lahmastu:BAAALAAECgEIAQAAAA==.Laidtorest:BAAALAADCgMIAwAAAA==.Lainarning:BAAALAADCgMIAwAAAA==.Lairyn:BAAALAADCgcICAAAAA==.Lasinth:BAAALAAECgcICwAAAA==.Lastparagon:BAAALAADCggIDgAAAA==.Latana:BAAALAAECgMIAwAAAA==.Lathries:BAAALAAECgEIAgAAAA==.',Ld='Ldytncty:BAAALAADCgcIBwAAAA==.',Le='Leafå:BAAALAADCgcIBwAAAA==.Lefthian:BAAALAAFFAEIAQAAAA==.Letoka:BAAALAADCggICAAAAA==.',Li='Liath:BAAALAADCgcICgAAAA==.Lichqueenfel:BAAALAADCgYIBwAAAA==.Lifewells:BAAALAADCgQIBAAAAA==.Ligma:BAAALAAECgMIBQAAAA==.Lilikill:BAAALAAECgYIDAAAAA==.Lililina:BAAALAADCgcIDgAAAA==.Lilithfel:BAAALAADCgYICAAAAA==.Lillyth:BAAALAAECgUIBgAAAA==.Lilpurp:BAAALAAECgEIAQAAAA==.Limgrave:BAAALAAECgIIAgAAAA==.Linael:BAABLAAECoEWAAIGAAgIeBhfDgBdAgAGAAgIeBhfDgBdAgAAAA==.Liserrys:BAAALAADCggIDwAAAA==.Littlefoxie:BAAALAAECgYIEAAAAA==.Livedehtmai:BAAALAAECgIIAgAAAA==.',Ll='Lleyla:BAEALAAFFAEIAQAAAA==.Llumi:BAAALAAECgUICQAAAA==.',Lm='Lmacorns:BAAALAAECgUIBgAAAA==.',Lo='Lockyboi:BAAALAAECgEIAQABLAAECgYIBwAFAAAAAA==.Lohlari:BAAALAADCgUIBQAAAA==.Lohre:BAAALAAECgYIDAAAAA==.Loonbell:BAAALAAECgIIAwAAAA==.',Lu='Luckÿ:BAAALAADCgUIBQAAAA==.Luminarie:BAABLAAECoEXAAIUAAgIDSP/AAAfAwAUAAgIDSP/AAAfAwAAAA==.Lunabow:BAAALAAECgEIAQABLAAECgcIEAAFAAAAAA==.Lunadream:BAAALAAECgcIEAAAAA==.Lunalar:BAAALAADCgcIDwAAAA==.Lurtz:BAAALAADCgYICgABLAAECgUIBwAFAAAAAA==.Luthostus:BAAALAADCgYIBgAAAA==.Luvalot:BAAALAAECgMIBQAAAA==.Luvoratory:BAAALAAECgYIEgAAAA==.Luxaria:BAAALAAECgIIBAAAAA==.',Ly='Lybelle:BAAALAADCggICAAAAA==.',Ma='Mackantosh:BAAALAAECgYICgAAAA==.Madamkrimson:BAAALAAECgUICAAAAA==.Madtrollz:BAAALAADCgcIFQAAAA==.Mageops:BAAALAADCgIIAgAAAA==.Magered:BAAALAAECgYIDQAAAA==.Magoroxx:BAAALAAECgMIBgAAAA==.Maiyathicc:BAAALAAECgEIAQABLAAECgMIAQAFAAAAAA==.Makesammich:BAAALAAECgcIDwAAAA==.Malekbane:BAAALAAECgQIBAAAAA==.Malikya:BAAALAADCgYIBwAAAA==.Malkon:BAAALAAECgcICwAAAA==.Malvora:BAABLAAECoEXAAQIAAgI2xxqEgA2AgAIAAcIfB1qEgA2AgAJAAQIExL0IQAMAQAKAAIIQwnvHwCBAAAAAA==.Mamanurse:BAAALAADCgcIBwAAAA==.Mancezilla:BAAALAAECgYIDAAAAA==.Maplepriest:BAAALAAECgUIBQAAAA==.Masstercard:BAAALAAECgYICQAAAA==.Mattfu:BAAALAAECgQIBAABLAAFFAUIBwAMANUSAA==.Maxeras:BAAALAAECgEIAQAAAA==.Maximus:BAAALAAECgYIDAAAAA==.Mayoi:BAAALAAECgYIBwAAAA==.Mazapán:BAAALAAECgQIBwAAAA==.',Mb='Mbuku:BAAALAAECgUICgAAAA==.',Mc='Mcboogrballs:BAAALAADCgQIBAAAAA==.Mcroguez:BAAALAAFFAIIAwAAAA==.',Me='Mechpunch:BAAALAADCggICAAAAA==.Mechshift:BAAALAAECgMIBgAAAA==.Meeche:BAAALAAECgQIBAAAAA==.Meekz:BAAALAAECgMIBAAAAA==.Meesho:BAAALAADCggIEwAAAA==.Megacarry:BAABLAAECoEXAAIOAAgItB4vBwCzAgAOAAgItB4vBwCzAgAAAA==.Melfpally:BAAALAAECgEIAQAAAA==.Menagerie:BAAALAAECgYIDgAAAA==.Mericandream:BAAALAAECgUIBgAAAA==.Merling:BAAALAAECgEIAQAAAA==.Mestopholies:BAAALAAECgYICgAAAA==.Metatron:BAAALAAECgMIAwAAAA==.Mewzy:BAAALAAECggIEQAAAA==.',Mi='Michelangêlo:BAAALAADCgcIBwAAAA==.Microchips:BAAALAAECgYIEQAAAA==.Midnay:BAAALAADCggIEAAAAA==.Midra:BAAALAADCgcICwAAAA==.Midu:BAAALAADCgcICwABLAADCgcIDgAFAAAAAA==.Mihd:BAAALAAECgUIBgAAAA==.Mikassa:BAAALAADCgcIBwAAAA==.Mileana:BAAALAADCggICgAAAA==.Milkfan:BAAALAAECgYIDQAAAA==.Millamaxwell:BAABLAAECoEWAAMBAAgI1CBEBgD+AgABAAgI1CBEBgD+AgAVAAcIhQ+ULgBkAQAAAA==.Millim:BAAALAAECgUIBgAAAA==.Minato:BAAALAAECgYIBgAAAA==.Minimus:BAAALAADCgcIDgAAAA==.Mitur:BAAALAAECgQIBAAAAA==.',Mo='Module:BAAALAADCggIEgAAAA==.Moistbiscuit:BAABLAAECoEWAAMBAAgIxRkWDQB8AgABAAgIxRkWDQB8AgAVAAcI/QTvQwADAQAAAA==.Moistform:BAAALAAECgUIBQAAAA==.Monkfrank:BAAALAADCgcIBwAAAA==.Monstressed:BAAALAADCgcIBwAAAA==.Monte:BAAALAADCggIHgAAAA==.Moobees:BAAALAAECgMIBAAAAA==.Moogue:BAEALAAECgUIBwAAAA==.Mooky:BAEALAADCgYICgABLAAECgUIBwAFAAAAAA==.Moollycyrus:BAAALAADCgcICgAAAA==.Moraxus:BAABLAAECoEXAAISAAgI9h+bDACYAgASAAgI9h+bDACYAgAAAA==.Morthose:BAAALAAECgYIDgAAAA==.Mortuous:BAAALAADCgYIBwAAAA==.Motìon:BAAALAAECgcIDQAAAA==.Mouneski:BAAALAAECgMIBQAAAA==.',Mu='Mubu:BAAALAADCggIEwAAAA==.Mudpriest:BAAALAAECggIEQAAAA==.Muffdiiva:BAAALAAECgUIBgAAAA==.Mulletman:BAAALAADCggICgAAAA==.Munknee:BAAALAADCgcIBwAAAA==.Murphlord:BAAALAAECgYICAAAAA==.Muskybolt:BAAALAAECgYIDQAAAA==.',My='Mybuddie:BAAALAAECgEIAQAAAA==.Myrion:BAAALAADCgIIAgAAAA==.Mystrix:BAAALAAECgYICQAAAA==.Mythans:BAAALAADCgYIBgAAAA==.Myzary:BAAALAADCgYICwAAAA==.',['Mã']='Mãoru:BAAALAADCgYICwAAAA==.',['Më']='Mërc:BAAALAADCgUIBQAAAA==.Mërcy:BAAALAADCggIFgAAAA==.',['Mò']='Mòmô:BAAALAADCgcIBwAAAA==.',['Mô']='Mômô:BAAALAADCgUIBQAAAA==.',['Mö']='Mömò:BAAALAAECgMIBQAAAA==.',Na='Nadroj:BAAALAAECggIDgAAAA==.Nahiri:BAAALAADCggIDwAAAA==.Nardhaa:BAAALAAECgIIAgAAAQ==.Narianstus:BAAALAADCgMIAwAAAA==.Narrius:BAAALAAECgYIDQAAAA==.Nassandia:BAAALAAECgMIBgAAAA==.Naturallyop:BAAALAADCgcIBwAAAA==.',Ne='Necrötica:BAAALAADCgEIAQAAAA==.Nemafex:BAAALAAECgUIBgAAAA==.Nesonis:BAAALAAECgUIBQAAAA==.Nexxen:BAAALAAECgMIBAAAAA==.Nezindrov:BAAALAAECgYICQAAAA==.',Ni='Niavy:BAAALAAECgQIBwAAAA==.Niccel:BAAALAAECgQIBAAAAA==.Nightclaw:BAAALAAECgEIAQAAAA==.Nightwreck:BAAALAADCgcICwAAAA==.Nimchip:BAABLAAECoEWAAISAAgI+hg8DgB+AgASAAgI+hg8DgB+AgAAAA==.',No='Noriel:BAAALAADCgYIBgAAAA==.Notfisher:BAAALAADCggICAABLAAECgcIBwAFAAAAAA==.Notmyforte:BAAALAADCgYIBgAAAA==.',['Ná']='Náthe:BAAALAAECgEIAQAAAA==.',Oa='Oakzz:BAAALAAECgMIBQAAAA==.',Oc='Ocêangrown:BAAALAADCggIBwAAAA==.',Od='Odhran:BAABLAAECoEXAAIMAAgIZyRdAQBGAwAMAAgIZyRdAQBGAwAAAA==.Odrik:BAAALAAECgYICgAAAA==.',Og='Og:BAAALAAECgMIAwAAAA==.',Oh='Ohden:BAAALAADCggICQAAAA==.Ohgodbees:BAAALAAECgMIBQAAAA==.',On='Onuris:BAAALAADCggIFAAAAA==.Onís:BAAALAAECgcIDQAAAA==.',Op='Oprahwndfury:BAAALAADCggIFQAAAA==.',Or='Orastal:BAAALAADCgcIDgABLAADCggIDwAFAAAAAA==.Oravoker:BAAALAADCggIDwAAAA==.Oreodumpling:BAAALAADCggIDAAAAA==.',Os='Osawa:BAAALAAECgMIBQAAAA==.',Ou='Outches:BAAALAAECgUIBgAAAA==.',Oz='Ozshock:BAAALAAECgYICwAAAA==.Ozz:BAAALAADCgMIAwAAAA==.',Pa='Pags:BAAALAAECgMIBQAAAA==.Palavadin:BAAALAADCgQIBAABLAAECgcIDwAFAAAAAA==.Palthron:BAAALAAECgUIBwAAAA==.Palychick:BAAALAADCggIDQABLAAECgQIBgAFAAAAAA==.Pamplemòóse:BAAALAADCggICAABLAAFFAIIAgAFAAAAAA==.Pandatotem:BAAALAADCgcIDgAAAA==.Paniicsenpai:BAAALAADCgYIBgABLAAECgYIDgAFAAAAAA==.Paramedic:BAABLAAECoEWAAMLAAgI0SZzAACRAwALAAgI0SZzAACRAwAUAAEIbRsQLwBQAAAAAA==.Pawlblart:BAAALAADCgMIAwAAAA==.Pawsowa:BAAALAADCggIEgAAAA==.',Pe='Peekàboo:BAAALAADCgcIBwAAAA==.Pelikanesis:BAAALAAECgUIBQAAAA==.Peppercornz:BAAALAADCgUIBQAAAA==.Pestilance:BAAALAAECgMIBAAAAA==.Pestus:BAAALAADCggICQAAAA==.',Ph='Phèdre:BAAALAADCgMIAwAAAA==.',Pi='Piff:BAAALAADCggICAAAAA==.Pimlock:BAAALAAECgYIBwAAAA==.Pinkfuzi:BAAALAAECgMIAwAAAA==.',Pl='Plasmik:BAABLAAECoEUAAMDAAgIwRwTCQA8AgADAAgIwRwTCQA8AgACAAQIyQ+bSwABAQAAAA==.Plastiki:BAAALAAECgYIEgAAAA==.Plastor:BAAALAAECgMIAwAAAA==.',Po='Poisonousx:BAAALAADCgYIBgABLAADCgcIFQAFAAAAAA==.Poka:BAAALAAECgUIBQAAAA==.Pokatoo:BAAALAAECgEIAQAAAA==.Pomarcpyro:BAAALAAECgYICgAAAA==.Pookudooku:BAAALAAECgIIAQAAAA==.Popcyrn:BAAALAADCgMIAwABLAADCggIFgAFAAAAAA==.Porkkchopp:BAAALAAECgMIBQAAAA==.Porkuba:BAAALAADCgcIDAAAAA==.Porkwah:BAAALAAECgEIAQAAAA==.',Pp='Ppfungus:BAAALAADCggICAABLAADCggICwAFAAAAAA==.',Pr='Prayermonger:BAAALAAFFAIIAwAAAQ==.Preist:BAAALAAECgIIAgAAAA==.Pretorianz:BAAALAADCggIDQAAAA==.',Pu='Puckhead:BAAALAADCgYIBgABLAAECgIIAgAFAAAAAQ==.Pufftreez:BAAALAAECgYICwAAAA==.Purebeaf:BAAALAAECgcICwAAAA==.Purplatath:BAAALAADCggIDgAAAA==.Purpledrink:BAAALAAECgYIDAAAAA==.Purplewar:BAAALAADCgYIBgAAAA==.Purpplelady:BAAALAADCgYIBgAAAA==.',Py='Pynki:BAAALAAECgQIBQAAAA==.Pyrofreak:BAAALAAECgMIAwAAAA==.Pyrìz:BAAALAAECgIIAgAAAA==.',['Pê']='Pêwpew:BAAALAADCgEIAQAAAA==.',Qi='Qik:BAAALAAECgcIDAAAAQ==.',Qu='Quadratic:BAAALAADCggIDQAAAA==.',Qw='Qweefur:BAAALAAECgMIBAAAAA==.',Ra='Rabidwombat:BAAALAAFFAIIAgAAAA==.Raidenx:BAAALAADCgcICQAAAA==.Raindin:BAAALAAECgMIBAAAAA==.Raisers:BAAALAAECgYIDwAAAA==.Rangoo:BAAALAAECgYICgAAAA==.Ravels:BAAALAAECgMIBgAAAA==.Ravenmane:BAAALAAECgYIBgAAAA==.Ravenous:BAAALAADCgYIBgAAAA==.Ravenouss:BAAALAADCgYIBgAAAA==.Razenot:BAAALAADCgEIAQAAAA==.Razziz:BAAALAAECgMIAwAAAA==.',Re='Realistic:BAAALAAECgcICAAAAA==.Rednight:BAAALAADCgIIAgAAAA==.Regolas:BAAALAAECgMIBAAAAA==.Reinhàrd:BAAALAADCggICAAAAA==.Relzzad:BAAALAADCggIHgAAAA==.Remylord:BAAALAAECgcICwAAAA==.Rendalin:BAAALAAECgMIAwAAAA==.Rentámonk:BAAALAAECgMIBAAAAA==.Rentápally:BAAALAAECgMIAwAAAA==.Retch:BAAALAADCgYIBgAAAA==.Retfin:BAAALAADCgEIAQAAAA==.',Rh='Rhoadez:BAAALAAECgYIDAAAAA==.Rhoadzilla:BAAALAADCgUIBgAAAA==.',Ri='Rikaya:BAAALAAECgMIBQAAAA==.Riot:BAAALAADCgIIAgABLAAECgMIBQAFAAAAAA==.Riversöng:BAAALAAECgUICAAAAA==.Rizlok:BAAALAADCggIDwABLAAECgcIEAAFAAAAAA==.Rizoynius:BAAALAADCggIBwAAAA==.',Ro='Rogmayor:BAAALAAECgQICAAAAA==.Roguepink:BAAALAAECgYIBwAAAA==.Rolypo:BAAALAAECgMIBwAAAA==.Ronalde:BAAALAAECgEIAQAAAA==.Rosalinde:BAAALAAECgYIDgAAAA==.Rougesera:BAAALAADCgcIBwABLAAECgYICQAFAAAAAA==.Rousera:BAAALAAECgYICQAAAA==.',Ru='Runtzz:BAAALAADCgcICgAAAA==.',Ry='Rynnzler:BAAALAAECgMIBAAAAA==.Ryuji:BAAALAAECgcICwAAAA==.Ryushinizi:BAAALAAECgUIBwAAAA==.',['Ré']='Rédemptíon:BAAALAADCggICAAAAA==.',Sa='Saejin:BAAALAADCgYICgABLAAECgUIBwAFAAAAAA==.Sageth:BAABLAAECoEWAAIRAAgIXSOtBgDXAgARAAgIXSOtBgDXAgAAAA==.Saintsaints:BAABLAAECoEXAAIGAAgI0hoiDgBiAgAGAAgI0hoiDgBiAgAAAA==.Samlock:BAAALAADCgQIBAAAAA==.Sanalin:BAAALAADCgQIBAAAAA==.Sandyrivers:BAAALAADCgcIBwAAAA==.Sanlerøs:BAAALAAECgMIBAAAAA==.Saraelys:BAAALAADCgcIBwABLAAECgMIBQAFAAAAAA==.Saral:BAAALAAECgIIAgAAAA==.Sarandots:BAAALAADCgEIAQABLAAECgYICwAFAAAAAA==.Sarantakos:BAAALAAECgYICwAAAA==.Sargarus:BAAALAADCgYIBgAAAA==.Sarviez:BAABLAAECoEVAAIWAAgIbRojAwCCAgAWAAgIbRojAwCCAgAAAA==.Sass:BAAALAAECgEIAQAAAA==.Savelah:BAAALAAECgcICwAAAA==.',Sc='Schifo:BAAALAAECgUIBQABLAAECggIFgABANQgAA==.Scolio:BAAALAAECgIIAgAAAA==.Scourgeguy:BAAALAAECgMIBwAAAA==.',Se='Seasyns:BAAALAADCgUIBQABLAADCggIFgAFAAAAAA==.Serialquillr:BAAALAAECggIEgAAAA==.Seyen:BAAALAADCggICAABLAAECgYIDQAFAAAAAA==.',Sh='Shadosham:BAAALAAECgUIBgAAAA==.Shadovved:BAAALAAECggICAABLAAECggIEgAFAAAAAA==.Shamanlove:BAAALAADCgIIAgAAAA==.Shamdel:BAAALAADCgMIAwABLAAECgUIBwAFAAAAAA==.Shamiatwain:BAAALAAECgYICQAAAA==.Shamvelah:BAAALAAECgYIBgAAAA==.Shearchip:BAAALAAECgYIDgABLAAECggIFgASAPoYAA==.Sheetrock:BAAALAADCgQIBAAAAA==.Sheleighly:BAAALAADCgYIBgAAAA==.Shizuchan:BAAALAAECggIBgAAAA==.Shizzkin:BAAALAAECgEIAQAAAA==.Shocktoke:BAAALAAECgMIBQAAAA==.Shockwave:BAAALAAECgEIAQAAAA==.Shotsadin:BAABLAAECoEUAAILAAgIxRzTDQCoAgALAAgIxRzTDQCoAgAAAA==.Shriv:BAAALAADCggIEgAAAA==.Shãmanic:BAAALAAECgMIBQAAAA==.',Si='Silencedfish:BAAALAADCgYIBgAAAA==.Silentespada:BAAALAAECgMIBgAAAA==.Silverage:BAAALAADCgcICwAAAA==.Sixminuteabs:BAAALAAECgcICgAAAA==.Sizasome:BAAALAADCgQIBAAAAA==.',Sk='Skims:BAAALAAECgMIAwAAAA==.Sknag:BAAALAADCgcIBwAAAA==.Skornn:BAAALAADCgYIBgAAAA==.Skovar:BAAALAADCgMIAwAAAA==.Skullmagedon:BAAALAAECgIIAgAAAA==.Skweaek:BAAALAADCgUIBQAAAA==.Skylaa:BAAALAADCgcICAAAAA==.',Sl='Slag:BAAALAADCgYIBgAAAA==.Slappypaws:BAAALAAECgcICwAAAA==.Sleeptoken:BAAALAADCgEIAQAAAA==.Slizaro:BAAALAAECgMIAwAAAA==.',Sm='Smeagull:BAAALAADCgcIDQAAAA==.Smlck:BAAALAADCgUIBQAAAA==.',Sn='Snackism:BAAALAADCggIDQAAAA==.Snackumz:BAAALAAECgUIBgAAAA==.Snakeyess:BAAALAADCgYICQAAAA==.Snauseberry:BAAALAAECgYIBQAAAA==.Snowborn:BAAALAADCgMIAwAAAA==.Snowman:BAAALAADCgQIBAAAAA==.',So='Socceroogoat:BAAALAADCgUICAAAAA==.Softboi:BAAALAAECgcIBwAAAA==.Soldmysoul:BAAALAAECgQIBAAAAA==.Sonkris:BAAALAAECgYICgAAAA==.Sopheri:BAABLAAECoEUAAIMAAcIcCHGCQCNAgAMAAcIcCHGCQCNAgAAAA==.Sorcerous:BAAALAADCggIEgAAAA==.Soulamander:BAAALAAECgYICQAAAA==.Southsidë:BAAALAAECggICAAAAA==.Soül:BAACLAAFFIEFAAIHAAMIgAeCAgDiAAAHAAMIgAeCAgDiAAAsAAQKgRYAAgcACAjfG2kFAIMCAAcACAjfG2kFAIMCAAAA.',Sp='Spd:BAAALAAECgIIBAAAAA==.Spigoosh:BAAALAADCggICAAAAA==.Splic:BAABLAAECoEXAAIEAAgIRhvPCACdAgAEAAgIRhvPCACdAgAAAA==.Spoons:BAAALAADCgcIBwAAAA==.Sprewell:BAAALAAECgUIBgAAAA==.Sproxs:BAAALAADCgcIBwABLAADCggIDgAFAAAAAA==.Sproxx:BAAALAADCggIDgAAAA==.',St='Starfish:BAAALAAECgMIAwAAAA==.Stoofy:BAAALAAFFAIIAgAAAA==.Stormfather:BAAALAAECgYIEAABLAAECggIHgASAKQcAA==.Stormstår:BAAALAADCgIIAgAAAA==.Straightgru:BAAALAADCgcIBwAAAA==.Strykax:BAAALAADCgMIAwAAAA==.Strype:BAAALAAECgUIBgAAAA==.',Su='Sunbourne:BAAALAAECgMIAwAAAA==.Superfunn:BAAALAAECgYIBwAAAA==.Superplague:BAAALAAECgMIAwAAAA==.Surfnturf:BAABLAAECoEWAAIRAAgIyBi/CwBuAgARAAgIyBi/CwBuAgAAAA==.',Sw='Sweetbud:BAAALAADCgYIBgAAAA==.Swiftheartt:BAAALAAECgMIBAAAAA==.',Sy='Sydarei:BAAALAAECgYICQAAAA==.Sylri:BAAALAADCgYIBgAAAA==.Sylvaneth:BAAALAADCgcICgAAAA==.Sylvio:BAAALAADCgYIBgAAAA==.',['Sö']='Söul:BAAALAADCgcIBwAAAA==.',['Sú']='Súcellus:BAAALAADCgMIAwAAAA==.',Ta='Takari:BAAALAADCggIEAAAAA==.Taldk:BAAALAADCgcIBwAAAA==.Tangomango:BAAALAAECgcICgAAAA==.Taranis:BAAALAADCggIDgAAAA==.Tatyl:BAAALAADCgcIBwAAAA==.Tauntface:BAAALAADCgEIAQAAAA==.Tazana:BAAALAADCgUIDQAAAA==.Tazzorface:BAAALAADCgIIAgAAAA==.',Te='Tegorman:BAAALAADCgcICwAAAA==.Terodactyl:BAAALAAECgUICAAAAA==.Teto:BAAALAADCgcICgABLAAECgYIDAAFAAAAAA==.Tezzeret:BAAALAADCggIEAAAAA==.',Th='Thatsiso:BAAALAAECggIBwAAAA==.Theirashes:BAEALAADCgMIAwABLAAECggIFQAXAOMkAA==.Theothehero:BAABLAAECoEUAAIJAAgIUSCUAwA+AgAJAAgIUSCUAwA+AgAAAA==.Thermostat:BAAALAADCgcIBwAAAA==.Thickenuggie:BAAALAADCgcIBwAAAA==.Thormoon:BAAALAAECggIEQAAAA==.Thunger:BAAALAADCgMIBAAAAA==.',Ti='Tiahdoe:BAAALAADCgcICAAAAA==.Tinygloves:BAAALAADCgYIBgAAAA==.Tiowel:BAABLAAECoEUAAIVAAgI8x17BQC5AgAVAAgI8x17BQC5AgAAAA==.Tizz:BAAALAADCgcICgAAAA==.',To='Tolnoc:BAAALAAECgMIBAAAAA==.Tonraq:BAAALAAECgQIBgAAAA==.Tornelos:BAAALAAECgIIAgAAAA==.',Tr='Trancexo:BAABLAAECoEVAAIRAAgIyB7sBwC3AgARAAgIyB7sBwC3AgAAAA==.Tricia:BAAALAADCgYIDAAAAA==.Trightz:BAAALAAECgEIAQAAAA==.Trillian:BAAALAAECgQIBAAAAA==.',Ts='Tsc:BAAALAADCgcICgAAAA==.',Tt='Ttottz:BAAALAAECgUIBgAAAA==.',Tu='Tuggy:BAAALAAECgMIBQAAAA==.',Tw='Twinkdeath:BAAALAAECgYIBgAAAA==.Twinkerdink:BAAALAAECgYIBgAAAA==.Twinkload:BAAALAAECgMIBAAAAA==.Twïgyy:BAAALAADCggICAAAAA==.',Ty='Tyrnrir:BAAALAADCgEIAQAAAA==.',Um='Umbráe:BAABLAAECoEXAAIYAAgINCHDAgDVAgAYAAgINCHDAgDVAgAAAA==.',Un='Undeady:BAAALAADCggICAAAAA==.Unholyrob:BAAALAADCggICAAAAA==.Unnknnownn:BAAALAADCgcICgAAAA==.',Us='Usui:BAAALAAECgYICQAAAA==.',Va='Valara:BAAALAADCgQIBAABLAAECgUIBwAFAAAAAA==.Valekh:BAAALAADCgcIDAAAAA==.Valewalker:BAAALAAFFAIIAwAAAA==.Valhalla:BAAALAAECgUIBwAAAA==.Valina:BAAALAADCgYIBgAAAA==.Vashezzo:BAAALAAFFAMIBAAAAA==.',Ve='Velilanna:BAAALAADCgQIAgAAAA==.Velinessa:BAAALAADCggICAAAAA==.Veliselynna:BAAALAAECggIEAAAAA==.Velyria:BAAALAADCgEIAQAAAA==.Vengenilly:BAAALAADCggIBgAAAA==.Verbseer:BAAALAADCggICAAAAA==.Verdent:BAAALAADCgcIBwAAAA==.Verthica:BAAALAAECgMIAwAAAA==.Veyllor:BAAALAAECgEIAQAAAA==.',Vi='Vicedro:BAAALAAECgIIAgAAAA==.',Vo='Volac:BAAALAADCgcIBwAAAA==.Volteer:BAAALAADCggIEAABLAAECggIFgABANQgAA==.Voxian:BAAALAAECgIIAgAAAA==.',Vy='Vyaus:BAAALAAECgMIAwAAAA==.Vyecodin:BAAALAAFFAIIAgAAAA==.Vyndrestus:BAAALAADCgYIBgAAAA==.Vytorin:BAAALAAECgQIBgAAAA==.',['Vä']='Väryn:BAAALAAECgYIDQAAAA==.',Wa='Wally:BAABLAAFFIEFAAIZAAMIwRS4AQDnAAAZAAMIwRS4AQDnAAAAAA==.Warchief:BAABLAAECoEMAAISAAcIGBYxHgDDAQASAAcIGBYxHgDDAQAAAA==.Watoto:BAAALAADCgYIBgAAAA==.Wats:BAAALAADCgYIBgAAAA==.Waystrong:BAAALAADCggICAABLAADCggIHgAFAAAAAA==.',Wh='Whatthehorse:BAAALAADCgMIAwAAAA==.',Wi='Witall:BAAALAAECgYICwAAAA==.',Wn='Wnrtotems:BAAALAADCgYIBgAAAA==.',Wo='Worack:BAAALAADCggICAABLAAFFAIIAgAFAAAAAA==.Wowcer:BAAALAADCgYIBgAAAA==.',Wr='Wrastekahn:BAAALAADCggICAAAAA==.Wrathgate:BAAALAAECggIEgAAAA==.Wraug:BAAALAAECgYIDQAAAA==.Wreckedem:BAAALAAECgEIAQAAAA==.',Xa='Xaevis:BAAALAADCgYIBgABLAAECgUIBwAFAAAAAA==.Xaeviz:BAAALAAECgUIBwAAAA==.Xalatasha:BAAALAAECgMIBgAAAA==.Xayy:BAAALAAFFAIIAgAAAA==.',Xe='Xenojiva:BAAALAAECgIIAgAAAA==.Xevorian:BAAALAAECgUIBwAAAA==.Xexxi:BAAALAAECgYIDwAAAA==.',Xz='Xzina:BAAALAAECgMIBgAAAA==.',Ya='Yaoming:BAAALAAECgMIBQAAAA==.Yaraltaire:BAAALAADCgEIAQAAAA==.',Ye='Yedranna:BAAALAADCgcIDAAAAA==.',['Yà']='Yàkana:BAAALAADCgcIDQAAAA==.',Za='Zanpakutou:BAABLAAECoEXAAIQAAgIniQBAgAWAwAQAAgIniQBAgAWAwAAAA==.Zarenthil:BAAALAADCgQIBAAAAA==.Zarine:BAAALAADCgUIBgAAAA==.Zavana:BAAALAADCgMIAwAAAA==.',Ze='Zerluz:BAAALAADCgcIDAAAAA==.',Zi='Ziino:BAAALAADCggICAAAAA==.',Zo='Zoriki:BAAALAADCggIEgAAAA==.',Zu='Zultra:BAAALAADCgMIBAAAAA==.',['Zø']='Zørghén:BAABLAAECoEVAAICAAcI0hCPKwDGAQACAAcI0hCPKwDGAQAAAA==.',['Äb']='Äbruptness:BAAALAADCgcIBwAAAA==.',['Æl']='Ælvis:BAAALAADCggIFgAAAA==.',['Ïs']='Ïshtãr:BAAALAAECgYIDQAAAA==.',['Ði']='Ðinraal:BAAALAAECgQIBQAAAA==.',['ßï']='ßïll:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end