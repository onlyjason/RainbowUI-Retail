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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Evoker-Devastation',}; local provider = {region='US',realm='Nemesis',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abitu:BAAALAAECgYIDAAAAA==.Absolutus:BAAALAADCgcIBwAAAA==.',Ac='Acnaya:BAAALAADCgcIBwAAAA==.',Ae='Aerlath:BAAALAAECgcIDwAAAA==.',Ag='Agathaelunna:BAAALAADCgcIEAAAAA==.Ageudh:BAAALAADCgIIAgAAAA==.Ageudk:BAAALAADCgcICQAAAA==.Agrïås:BAAALAAECgMIAwAAAA==.',Ai='Ainora:BAAALAAECgIIAgAAAA==.',Ak='Akahi:BAAALAADCgEIAQAAAA==.Akasta:BAAALAAECgQIBQAAAA==.',Al='Albicha:BAAALAADCgYIBgAAAA==.Aldrathion:BAAALAAECgEIAQAAAA==.Aledk:BAAALAADCggIEQAAAA==.Alendos:BAAALAAECgEIAQAAAA==.Alessan:BAAALAADCgEIAQAAAA==.Alikate:BAAALAADCgEIAQAAAA==.Allanaels:BAAALAADCgQIBAAAAA==.Allarium:BAAALAADCgUIBQAAAA==.Allerick:BAAALAADCgQIAwAAAA==.Alluap:BAAALAADCgEIAQAAAA==.Allÿhanna:BAAALAADCgEIAQAAAA==.Almalexia:BAAALAADCggIDAAAAA==.Altreir:BAAALAADCggICAAAAA==.Aluxxious:BAAALAAECgMIBQAAAA==.',Am='Amalahk:BAAALAADCggIEAAAAA==.Amberbeardy:BAAALAAECgYIBgABLAAECgYIEAABAAAAAA==.',An='Anadirtei:BAABLAAECoEUAAICAAgIeyM6BQAtAwACAAgIeyM6BQAtAwAAAA==.Anarky:BAAALAADCgUIBQAAAA==.Andärilho:BAAALAAECgEIAQAAAA==.Anestesista:BAAALAADCgcIBwAAAA==.Anirbas:BAAALAADCgEIAQAAAA==.Ankawos:BAAALAAECgQIBgAAAA==.Anmarbor:BAAALAADCgMIAwAAAA==.Anubisdamage:BAAALAADCgMIAwAAAA==.',Ap='Apellon:BAAALAADCgcICgAAAA==.Apocalipse:BAAALAAECgcIEgAAAA==.Apofisdruida:BAAALAAECggIAQAAAA==.',Aq='Aquillez:BAAALAAECgQICQAAAA==.',Ar='Arathanis:BAAALAADCggICAAAAA==.Archontus:BAAALAAECgYIBgAAAA==.Argosaxxr:BAAALAADCgEIAQAAAA==.Arinn:BAAALAAECgcICgAAAA==.Arriden:BAAALAADCggICQAAAA==.Artaxarrow:BAAALAAECgEIAQAAAA==.Arthur:BAAALAAECgQIBQAAAA==.',As='Asaquebrada:BAAALAAECgEIAQAAAA==.Asgarim:BAAALAADCgIIAgAAAA==.Ashabellanar:BAAALAAECgEIAQAAAA==.Asheedra:BAAALAAECgMIAwAAAA==.Asinhaazul:BAAALAAECgYICQAAAA==.Aslatiel:BAAALAAECgYIDQAAAA==.Astanael:BAAALAADCggICgAAAA==.Astegon:BAAALAAECgMIBAAAAA==.Astergilda:BAAALAAECgcIDwAAAA==.',At='Atlanthås:BAAALAADCgcIBwAAAA==.',Av='Avanthara:BAAALAADCgUIBQAAAA==.',Ba='Babuskha:BAAALAAECgMIAwAAAA==.Bakushiterra:BAAALAAECgcICgAAAA==.Balzhemir:BAAALAAECgMIAwAAAA==.Barks:BAAALAAECgYIDQAAAA==.Barrig:BAAALAAECgEIAQAAAA==.Bashii:BAAALAADCgEIAQAAAA==.Baskervile:BAAALAADCgEIAQAAAA==.',Be='Be:BAAALAADCggICQAAAA==.Bebotodas:BAAALAADCggICAAAAA==.Behind:BAAALAADCgcIEgAAAA==.Bellwolff:BAAALAADCgYICAAAAA==.',Bi='Bilpaxton:BAAALAADCgcIBwAAAA==.Binar:BAAALAADCgIIAgAAAA==.Birxbox:BAAALAADCgMIAwAAAA==.Biscoktu:BAAALAADCggICAAAAA==.',Bl='Blackberry:BAAALAAECgYICQAAAA==.Blackwatch:BAAALAADCgcICgAAAA==.Blackzinho:BAAALAADCgUIBQAAAA==.Blecktold:BAAALAAECgMIAwAAAA==.Blenksmage:BAAALAADCggIFwABLAAECgYICQABAAAAAA==.Bllenks:BAAALAAECgYICQAAAA==.Bloodkael:BAAALAADCgQIBAAAAA==.Bloodyclaw:BAAALAADCggIGAAAAA==.',Bo='Boizinn:BAAALAADCggICgAAAA==.Boldonaro:BAAALAAECgYICgAAAA==.Boomgoesyou:BAAALAAECgcIEAAAAA==.Bowjobby:BAAALAADCgUICAAAAA==.',Br='Bradokk:BAAALAADCgcIBwAAAA==.Bradvï:BAAALAADCgQIBAAAAA==.Brakury:BAAALAADCgYIBgAAAA==.Brazukmaiden:BAAALAADCgIIAgAAAA==.Breeda:BAAALAAECgIIAgAAAA==.Brisawave:BAAALAAECgcIEgAAAA==.Broke:BAAALAAECgYICgAAAA==.Broogon:BAAALAAECgEIAQAAAA==.Broxikor:BAAALAADCgcIDAAAAA==.Brujjah:BAAALAADCgYIBgAAAA==.',Bu='Bugadson:BAAALAADCgcIBwAAAA==.Bullzin:BAAALAAECgQIBQAAAA==.Burlesque:BAAALAADCgMIAwAAAA==.',By='Byzüca:BAAALAADCgQIBAAAAA==.',['Bä']='Bäbäyaga:BAAALAADCgIIAgAAAA==.Bäbì:BAAALAADCgEIAQAAAA==.',['Bé']='Béssi:BAAALAADCgEIAQAAAA==.',Ca='Cabracega:BAAALAAECgMIBQAAAA==.Caiquebmq:BAAALAAECgIIAgAAAA==.Calong:BAAALAADCgcIBwAAAA==.Canards:BAAALAADCgYIBgABLAAECgcICwABAAAAAA==.Capdez:BAAALAAECgMIAwAAAA==.Carlodruid:BAAALAADCggIDgABLAAECgcIDQABAAAAAA==.Carlopala:BAAALAAECgcIDQAAAA==.Carqueiro:BAAALAAECgYIDAAAAA==.Carronte:BAAALAAECgEIAgAAAA==.Cassisus:BAAALAADCgYIBQAAAA==.Cathise:BAAALAAECgYIDQAAAA==.Caxola:BAAALAADCgIIAgAAAA==.',Ce='Ceerbere:BAAALAADCgYIBwAAAA==.Ceifadoro:BAAALAADCgYIBgAAAA==.Ceifhador:BAAALAAECgMIBAAAAA==.Celea:BAAALAAECgIIAgAAAA==.Cenarioss:BAAALAAECgIIAgAAAA==.',Ch='Charr:BAAALAADCggIDAAAAA==.Checkmarlin:BAAALAAECgEIAQAAAA==.Chichura:BAAALAADCgcIBwAAAA==.Chiclas:BAAALAADCgYIBgAAAA==.Chimia:BAAALAADCggICAABLAAECgYICwABAAAAAA==.Chisana:BAAALAADCgMIAwAAAA==.Chopz:BAABLAAECoEVAAMDAAgIMx5zAgA1AgAEAAgIZBluDABoAgADAAYIvCBzAgA1AgAAAA==.Chromell:BAAALAAECgMIAwAAAA==.Chucknòórris:BAAALAADCgMIAwAAAA==.',Cl='Clane:BAAALAADCgUIAwABLAAECgYICwABAAAAAA==.Clastus:BAAALAAECgMIBwAAAA==.Clessalvein:BAAALAADCgIIAgAAAA==.Clunck:BAAALAAECggIEAAAAA==.Clurf:BAAALAADCggIDQAAAA==.',Co='Coiovoker:BAAALAADCgcIDQABLAAECgYIDQABAAAAAA==.Coitadinho:BAAALAAECgIIAgAAAA==.Coldaknight:BAAALAADCgIIAgAAAA==.Coolcaine:BAAALAADCgYIBgAAAA==.Corin:BAAALAADCgEIAQAAAA==.Corlayn:BAAALAAECgYIDgAAAA==.',Cr='Craazy:BAAALAADCggICgAAAA==.Crazy:BAAALAADCgQIBQAAAA==.Cristonea:BAAALAADCgcICgAAAA==.Cronosxdxd:BAAALAAECgQICAAAAA==.Crownlley:BAAALAADCgMIAwAAAA==.Crucyatus:BAAALAAECgUIBwAAAA==.',Ct='Ctrlaltfrost:BAAALAAECgEIAQABLAAECgUIBQABAAAAAA==.',Cu='Curativø:BAAALAADCggIDwAAAA==.Curriel:BAAALAAECgIIAgAAAA==.',['Cá']='Cássia:BAAALAADCgcIBwAAAA==.',['Cä']='Cätrina:BAAALAADCggIFwAAAA==.',['Cü']='Cürintia:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',['Cÿ']='Cÿgnus:BAAALAADCgQIBAAAAA==.',Da='Daddybear:BAAALAADCggICAAAAA==.Daeneryß:BAAALAADCgcICAAAAA==.Daffodil:BAAALAAECgMIBQAAAA==.Daflora:BAAALAADCgcIBwAAAA==.Daitokumyo:BAAALAADCggIBwAAAA==.Dalshar:BAAALAAECgQIBgAAAA==.Darggor:BAAALAADCgEIAQAAAA==.Darkasto:BAAALAADCgEIAQAAAA==.Darkdweller:BAAALAAECgQIBwAAAA==.Darkhold:BAAALAADCgYIBgAAAA==.Darkplate:BAAALAADCgUIBQAAAA==.Darkrangerr:BAAALAAECgQIBAAAAA==.Darksheen:BAAALAAECgIIAgAAAA==.Darukia:BAAALAADCgQIBAAAAA==.Dashblinding:BAAALAAECgIIAgAAAA==.Dayeron:BAAALAADCgUIAgAAAA==.',De='Deadaim:BAAALAADCgMIAwAAAA==.Deadcaster:BAAALAAECgcIEQAAAA==.Deftones:BAAALAADCgEIAQAAAA==.Deina:BAAALAAECgEIAgAAAA==.Delarÿn:BAAALAADCggIFgAAAA==.Demonatrix:BAAALAAECgEIAgAAAA==.Deratron:BAAALAADCgcIBwAAAA==.Derleyc:BAAALAADCgcIBwAAAA==.Devilshand:BAAALAADCgYIBgAAAA==.',Dh='Dhanyr:BAAALAADCgQIBAAAAA==.Dhargo:BAAALAADCgcIBwAAAA==.Dhmora:BAAALAAECgQIBgAAAA==.Dhuntr:BAAALAADCgUIBQAAAA==.',Di='Diamath:BAAALAADCggIEQAAAA==.Dijank:BAAALAADCgYICgABLAADCgcIDQABAAAAAA==.Dijunk:BAAALAADCgYIDAABLAADCgcIDQABAAAAAA==.Dine:BAAALAAECgUIBQAAAA==.Distürbed:BAAALAADCgMIBQAAAA==.',Dn='Dnt:BAAALAAECgYIDQAAAA==.',Do='Dogger:BAAALAADCgcICQAAAA==.Dokaeby:BAAALAAECgcIEAAAAA==.Dominyum:BAAALAAECgEIAQAAAA==.Donperez:BAAALAAECgIIAgAAAA==.Doper:BAAALAAECgMIBAAAAA==.Doraggumir:BAAALAAECgMIBQAAAA==.Dorbäs:BAAALAADCgYIBgAAAA==.Dornaa:BAAALAAECgIIAgAAAA==.Dosmagos:BAAALAADCggIEAAAAA==.',Dp='Dpvat:BAAALAAECgEIAQAAAA==.',Dr='Dracomalføy:BAAALAAECgYIDAAAAA==.Dracurintia:BAAALAADCggICAAAAA==.Draeneide:BAAALAADCgUIBQAAAA==.Dragonslayex:BAAALAADCgQIAQAAAA==.Dragpeta:BAAALAADCggIBgAAAA==.Dragãobr:BAAALAAECgMIBQAAAA==.Drainsoul:BAAALAAECgYIBAAAAA==.Drakhamm:BAAALAADCggIDQAAAA==.Drakiza:BAABLAAECoEeAAMFAAcITwqWDABSAQAFAAcITwqWDABSAQAGAAMIMQdQBgCFAAAAAA==.Dranacs:BAAALAAECgcICwAAAA==.Dregam:BAAALAADCgQIBQAAAA==.Drts:BAAALAAECgcIEQAAAA==.Druideero:BAAALAADCgYICQABLAAECgMIBgABAAAAAA==.Druidelicios:BAAALAADCgYIBgAAAA==.',Du='Dubakim:BAAALAADCgEIAQAAAA==.Dublin:BAAALAAECgEIAQAAAA==.Dudupokas:BAAALAADCggIDAAAAA==.Dulley:BAAALAADCgMIAwAAAA==.Dumar:BAAALAADCgUIBQAAAA==.Dumat:BAAALAAECgcIDgAAAA==.',Ec='Ecchishiouze:BAAALAADCggIFQAAAA==.',Ei='Eithan:BAAALAAECgYICQAAAA==.',El='Elaei:BAAALAADCgYIBgAAAA==.Elbang:BAAALAADCgcIFQAAAA==.Elbow:BAAALAADCgcIBwAAAA==.Elfafias:BAAALAADCgUICAAAAA==.Elfyss:BAAALAAECgYICQAAAA==.Elleria:BAAALAAECgMIAwAAAA==.Elwampas:BAAALAAECgEIAQAAAA==.',Em='Emgion:BAAALAADCgUIBQAAAA==.',En='Encanis:BAAALAAECgYIDQAAAA==.',Ep='Epsan:BAAALAADCggIDwAAAA==.',Er='Erowiin:BAAALAADCgcICwAAAA==.',Es='Estrelar:BAAALAAECgEIAQAAAA==.',Et='Ethergring:BAAALAADCgUIBQAAAA==.Ethidium:BAAALAADCgIIAgAAAA==.',Ex='Excelsios:BAAALAADCgcIDAAAAA==.Exo:BAAALAAECgMIBAAAAA==.Exorciseur:BAAALAADCggIFgAAAA==.',Fa='Fabiocaos:BAAALAADCgYICgAAAA==.Falsh:BAAALAADCgMIAwAAAA==.Fauna:BAAALAADCgMIAwAAAA==.',Fe='Feanori:BAAALAAECgYICQAAAA==.Felifeels:BAAALAADCgYICQAAAA==.Fellyx:BAAALAADCgQIBAAAAA==.Fenixrudder:BAAALAAECgcIDgAAAA==.Fenty:BAAALAAECgMIBgAAAA==.Feralius:BAAALAAECgIIAwAAAA==.Ferolleza:BAAALAADCgcIBwAAAA==.Feron:BAAALAADCgEIAQAAAA==.Festrati:BAAALAADCgUIBQAAAA==.Fezesney:BAAALAADCgcIBwAAAA==.',Fi='Finbor:BAAALAAECgYICQAAAA==.Fiänis:BAAALAADCggICAAAAA==.',Fl='Flenyr:BAAALAADCgcIEgAAAA==.Flexanatesta:BAAALAADCgYIBgAAAA==.Fluaba:BAABLAAECoEUAAIHAAcINBeZCgAcAgAHAAcINBeZCgAcAgAAAA==.Flufyneon:BAAALAADCgcICQAAAA==.',Fr='Fretus:BAAALAADCgEIAQAAAA==.Frostpower:BAAALAAECgMIBwAAAA==.',Fu='Fumarfazbem:BAAALAAECgYIDQAAAA==.',Ga='Gaazharagoth:BAAALAAECgcIDAAAAA==.Gabridh:BAAALAAECgYICgAAAA==.Gabronius:BAAALAADCgcICgAAAA==.Galakrar:BAAALAADCgYIBgAAAA==.Ganor:BAAALAADCgQIBQAAAA==.Garfall:BAAALAAECgYIDgAAAA==.Garlak:BAAALAADCgcIDAAAAA==.',Ge='Gentileza:BAAALAAECgIIAgAAAA==.',Gh='Ghago:BAAALAADCgQIBAAAAA==.Ghinnbo:BAAALAADCggIFgAAAA==.',Gi='Gilbertovíl:BAAALAADCgcICAAAAA==.Gittana:BAAALAADCgEIAQAAAA==.Giu:BAAALAAECgcIEAAAAA==.',Gl='Glacyale:BAAALAADCgEIAQAAAA==.Glisa:BAAALAAECgIIBAAAAA==.',Go='Gomesdk:BAAALAADCgUIBQAAAA==.Gommamon:BAAALAAECggIEwAAAA==.',Gr='Grekorio:BAAALAADCgEIAQAAAA==.Greylord:BAAALAADCgYIBgABLAAECggIFQAIACEZAA==.Greylordp:BAAALAADCgEIAQABLAAECggIFQAIACEZAA==.Greylordx:BAABLAAECoEVAAIIAAgIIRkGEAA0AgAIAAgIIRkGEAA0AgAAAA==.Grilhon:BAAALAADCgcIBQAAAA==.Grimm:BAAALAAECgEIAQAAAA==.Gromakra:BAAALAADCgEIAQAAAA==.Gromitak:BAAALAAECgQICAAAAA==.',Gu='Guanwei:BAAALAAECgEIAQAAAA==.Guspe:BAAALAAECgEIAQAAAA==.Guvops:BAAALAADCgUIBQAAAA==.',Ha='Haiume:BAAALAAECgQIBQAAAA==.Hajiro:BAAALAAECgIIAgAAAA==.Haldrius:BAAALAADCgEIAQAAAA==.Hancalimon:BAAALAADCggIFQAAAA==.Haredrai:BAAALAADCgMIAwAAAA==.Harko:BAAALAAECgMIBAAAAA==.Hastterix:BAAALAADCgQIBAAAAA==.',He='Healsi:BAAALAADCgIIAgAAAA==.Healsubmisso:BAAALAAECgMIBAAAAA==.Helenawood:BAAALAADCgIIAwAAAA==.Henbwar:BAAALAAECgIIAQAAAA==.',Hi='Highbuzz:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.Hiime:BAAALAADCgYIBgAAAA==.Hilota:BAAALAAECgQIBAAAAA==.Hitkins:BAAALAADCgIIAwAAAA==.',Ho='Hoffmahh:BAAALAADCgcIEQAAAA==.Hofkari:BAAALAAECgYICAAAAA==.Holycel:BAAALAAECgEIAQAAAA==.Honeymoon:BAAALAAECgMIBAAAAA==.Honoriodruid:BAAALAADCgYIBgAAAA==.Hordhunter:BAAALAAECgIIAgABLAAECgMIBQABAAAAAA==.Hosein:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.',Hu='Huansheila:BAAALAADCgQIBAAAAA==.Hunterpica:BAAALAAECgIIAQAAAA==.Huntmon:BAAALAAECgUICQAAAA==.Hupert:BAAALAAECgMIBgAAAA==.Huriah:BAAALAADCggIDwAAAA==.',Hy='Hybrido:BAAALAADCgQIBAAAAA==.Hypnøs:BAAALAADCgEIAQAAAA==.',['Hë']='Hëllz:BAAALAADCgUIBQAAAA==.Hëster:BAAALAADCggICwAAAA==.',['Hø']='Hørdeon:BAAALAADCgQIBAAAAA==.',Ib='Ibizadruid:BAAALAAECgYIDAAAAA==.',Ic='Icedark:BAAALAADCgMIAwAAAA==.Ichø:BAAALAADCgQIBAAAAA==.',Il='Ilidarilariê:BAAALAAECgYIBgAAAA==.Ilimitavel:BAAALAADCgMICAAAAA==.Illithyia:BAAALAAECgcIDgAAAA==.',In='Incógnito:BAAALAADCgcIDAAAAA==.',Io='Iolann:BAAALAADCgYIBwAAAA==.',Ir='Iradethor:BAAALAADCggICAAAAA==.Iradocaçador:BAAALAAECgcICgAAAA==.Irenikus:BAAALAAECgMIBAABLAAECgQIBQABAAAAAA==.',Is='Isilda:BAAALAADCggICAAAAA==.',It='Italodpz:BAAALAAECgUIBgAAAA==.',Iu='Iuri:BAAALAAECgQICAAAAA==.',Iz='Izanagidk:BAAALAADCgcICAAAAA==.Izanna:BAAALAADCgcIDgAAAA==.Izzhar:BAAALAADCggICgAAAA==.',Ja='Jaguncio:BAAALAAECgQIBAAAAA==.Jalfrunis:BAAALAADCgQIBAAAAA==.Jasoncrazy:BAAALAADCgMIAwAAAA==.',Je='Jeevas:BAAALAAECgcICgAAAA==.Jeu:BAAALAADCgcIBwAAAA==.',Jh='Jhoric:BAAALAADCgYICQAAAA==.Jhowlina:BAAALAADCgcIBwAAAA==.',Jl='Jlk:BAAALAADCgcIBwAAAA==.',Jo='Jodie:BAAALAAECgYIDAAAAA==.Johnez:BAAALAADCggICAAAAA==.Johnluc:BAAALAAECgMIBAAAAA==.Jolino:BAAALAADCggICgAAAA==.Jotavê:BAAALAADCgMIBQABLAADCgcIDQABAAAAAA==.',Jp='Jpleuk:BAAALAAECgYIDQAAAA==.',Jr='Jrxamã:BAAALAADCggIDgAAAA==.',Ju='Jubbileu:BAAALAADCgUIBQAAAA==.Judyalvarez:BAABLAAECoEWAAQJAAgI2h7iAgBUAgAJAAgI2h7iAgBUAgAKAAMInBCURACmAAALAAIIvgS9IgBpAAAAAA==.Jujubete:BAAALAAECgEIAQAAAA==.Julianelps:BAAALAADCgcICwAAAA==.Junipe:BAAALAADCgIIAgAAAA==.',['Já']='Jámes:BAAALAADCgcIDQAAAA==.',['Jü']='Jürema:BAAALAADCgcIBwAAAA==.',Ka='Kaali:BAAALAADCgEIAQAAAA==.Kairottyy:BAAALAAECgUIBQAAAA==.Kaju:BAAALAAECgYIBgAAAA==.Kaladrÿel:BAAALAADCggICAAAAQ==.Karadoc:BAAALAAECgYICgAAAA==.Karandaar:BAAALAAECgYIDAAAAA==.Katona:BAAALAAECgQICAAAAA==.Kayapo:BAAALAAECgYIDAAAAA==.',Ke='Keinyan:BAAALAAECgYIDQAAAA==.Keior:BAAALAAECgYIDQAAAA==.Kelito:BAAALAADCgEIAQAAAA==.Kenai:BAAALAAECgIIAgAAAA==.Kewan:BAAALAAECgMIAwABLAAECgUIBQABAAAAAA==.Kezdan:BAAALAADCgUIBQAAAA==.',Kh='Khasin:BAAALAADCggIEQAAAA==.',Ki='Kiedro:BAAALAADCgcIEgAAAA==.Kiha:BAAALAAECgMIAwAAAA==.Kiliel:BAAALAADCgcIBwAAAA==.Kiregeth:BAAALAAECgEIAQAAAA==.Kitrel:BAAALAAECgEIAgAAAA==.',Kj='Kjörd:BAAALAADCgYIBgAAAA==.',Kl='Kllauzz:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Kllauzzmage:BAAALAADCgcIFQABLAAECgMIAwABAAAAAA==.Kllauzzpalla:BAAALAAECgMIAwAAAA==.',Kn='Knut:BAAALAADCgUIBQAAAA==.',Ko='Koltiras:BAAALAAECgIIBAAAAA==.Kolyn:BAABLAAECoEVAAIMAAgISRuzDwBzAgAMAAgISRuzDwBzAgAAAA==.Komamurasou:BAAALAADCgEIAQAAAA==.Komebotiko:BAAALAAECgYICgAAAA==.Konar:BAAALAAECgEIAQAAAA==.Koopa:BAAALAADCgYIBgAAAA==.Koridels:BAAALAAECgMIBAAAAA==.Korite:BAAALAAECgIIAgAAAA==.Koziell:BAAALAADCgEIAQAAAA==.',Kr='Krastian:BAAALAAECgQIBgAAAA==.Kratosg:BAAALAADCgYIAwAAAA==.Kreegh:BAAALAADCggIDwAAAA==.Kroszarynn:BAAALAAECgMIBQAAAA==.Krupper:BAAALAAECgUIBQAAAA==.Kryptus:BAAALAADCgQIBAAAAA==.',Ky='Kyary:BAAALAAECgMIBQAAAA==.Kyndin:BAAALAADCgUIBQAAAA==.',['Kä']='Käläsh:BAAALAAECgYICwAAAA==.Käyros:BAAALAAECgMIBQAAAA==.',['Kö']='Köndmänö:BAAALAAECgYIDAAAAA==.',La='Lakras:BAAALAADCgUIBQAAAA==.Lamont:BAAALAAECgIIAgAAAA==.Langratixa:BAAALAAECgYIDAAAAA==.Lanmandragor:BAAALAADCgEIAgAAAA==.Lawphos:BAAALAADCgcICAAAAA==.Lazzaro:BAAALAADCgIIAgAAAA==.',Le='Leafeon:BAAALAAECgIIAgAAAA==.Leaflady:BAAALAADCgYIBgAAAA==.Lebelisco:BAAALAAECgIIAgAAAA==.Legnarxama:BAAALAADCgYIBgAAAA==.Leitemurphy:BAAALAADCgYIBgAAAA==.Lennard:BAAALAADCgQIBAAAAA==.Lennorien:BAAALAAECgMIAwAAAA==.Leruy:BAAALAADCgIIAgAAAA==.Levihiro:BAAALAADCgUIBQAAAA==.Leyr:BAAALAADCgYIBgAAAA==.Leøncio:BAAALAADCgYIBQAAAA==.',Lh='Lhyunl:BAAALAADCggICQAAAA==.',Li='Liarah:BAAALAADCgYIBgAAAA==.Lichgebre:BAAALAADCgQIBAAAAA==.Liftshertail:BAAALAAECgYIDgAAAA==.Linaeny:BAAALAAECgMIAwAAAA==.Linestrasza:BAAALAADCgYICAAAAA==.Linguinha:BAAALAADCgEIAQAAAA==.Linso:BAAALAADCgcIBwAAAA==.Lisøng:BAAALAADCgUIBQAAAA==.Littleshelby:BAAALAADCgYICAAAAA==.Lixxclone:BAAALAAECgYIDAAAAA==.Lixxpersion:BAAALAAECgIIAgAAAA==.',Lo='Loffs:BAAALAADCgcICAAAAA==.Lorsaser:BAAALAAECgMIBAAAAA==.Lorthaeron:BAAALAAECgEIAgAAAA==.Lorthras:BAAALAAECgMIAwAAAQ==.Lorës:BAAALAADCggICQAAAA==.Lotharayn:BAAALAAECgUIBgAAAA==.',Lp='Lp:BAAALAADCgYIBgAAAA==.',Lu='Lucasbr:BAAALAAECgYIBwAAAA==.Lucasyeah:BAAALAAECgMIBAAAAA==.Luisgrilo:BAAALAADCgYICQAAAA==.Lukanelas:BAAALAADCgIIAgAAAA==.Lumiel:BAAALAADCgUIBQAAAA==.Luna:BAAALAAECgYIBgAAAA==.Lunæly:BAAALAADCgMIAwAAAA==.Luzdacelesc:BAAALAAECgYICQAAAA==.',Ly='Lydruid:BAAALAADCgcICgAAAA==.Lyssi:BAAALAADCgMIBgAAAA==.',['Lá']='Lápide:BAAALAAECgEIAQAAAA==.',['Lä']='Läädÿpröfäñ:BAAALAADCgQIAwAAAA==.',['Lë']='Lënori:BAAALAADCggIDwAAAA==.',['Lø']='Løthariel:BAAALAAECgIIAgAAAA==.',['Lú']='Lúaprata:BAAALAAECgYICQAAAA==.',Ma='Macho:BAAALAAECgcICwAAAA==.Madefromhell:BAAALAADCggIBAAAAA==.Maezinha:BAAALAADCgEIAQAAAA==.Mageli:BAAALAAECgMIBAAAAA==.Magodanilo:BAAALAAECgIIAgAAAA==.Magrim:BAAALAADCgUIBQAAAA==.Makenai:BAAALAAECgUIBQAAAA==.Malidalador:BAAALAAECgUIBQAAAA==.Malmorttius:BAAALAADCgYICQAAAA==.Maltaess:BAAALAAECgEIAQAAAA==.Maltozo:BAAALAAECgYICwAAAA==.Manalysa:BAAALAADCgcIBwAAAA==.Mandrakson:BAAALAAECgMIBQAAAA==.Mangai:BAAALAAECgEIAQAAAA==.Mariiamil:BAAALAAECgIIAgAAAA==.Marrky:BAAALAAECgYICgAAAA==.Marycristiny:BAAALAAECgMIBAAAAA==.Matamato:BAAALAADCgcIBwAAAA==.Mayef:BAAALAADCgYIBgAAAA==.Mazaky:BAAALAAECgMIAwAAAA==.',Me='Medparental:BAAALAADCgUIBQAAAA==.Melyodas:BAAALAADCgcIDQAAAA==.Menorxidil:BAAALAAECgcIDgAAAA==.Menp:BAAALAAECgEIAgAAAA==.Mereen:BAAALAAECgEIAQAAAA==.Mew:BAAALAADCgEIAQAAAA==.Mewtwo:BAAALAADCgUIBQAAAA==.',Mh='Mhalkar:BAAALAAECgQICAAAAA==.',Mi='Midnights:BAAALAAECgMIBAAAAA==.Miniipriest:BAAALAADCgQIBAAAAA==.Minipura:BAAALAAECgYIBgAAAA==.Minort:BAAALAADCgcICgAAAA==.Miralokka:BAAALAADCggICAAAAA==.Mistkiller:BAAALAAECgYIBwAAAA==.Misto:BAAALAADCgcIBwAAAA==.Mithrim:BAAALAADCggICAAAAA==.Miucel:BAAALAAECgUICAAAAA==.',Mn='Mnëmosine:BAAALAADCggIHgAAAA==.',Mo='Mogan:BAAALAAECgYIBgAAAA==.Momocchi:BAAALAAECgYICgAAAA==.Momohime:BAAALAADCggICAABLAAECggIFwANAE4kAA==.Monabell:BAAALAADCggIEAAAAA==.Monkill:BAAALAADCggICgABLAAECgQIBAABAAAAAA==.Montej:BAAALAADCgEIAQAAAA==.Moondormu:BAAALAAECgEIAQAAAA==.Moondragoon:BAAALAAECgEIAQAAAA==.Morainesedai:BAAALAADCgEIAgAAAA==.Mortya:BAAALAAECgMIAwAAAA==.Mourumecha:BAAALAAECgYIEgABLAAECggIDgABAAAAAA==.Moyrá:BAAALAADCgYIBAAAAA==.Moçadireita:BAAALAADCggICAAAAA==.',Mu='Mugidinhaa:BAAALAADCgYICgAAAA==.Murilion:BAAALAAECgYICQAAAA==.Musleira:BAAALAAECgYICAAAAA==.',My='Mystpanda:BAAALAADCgcIDAAAAA==.Mytologiaa:BAAALAAECgMIBQAAAA==.',['Mä']='Mällü:BAAALAADCgcIBwAAAA==.Mälthazar:BAAALAAECgYICAAAAA==.',['Må']='Mågus:BAAALAAECgYICwAAAA==.',Na='Naastros:BAAALAAECgIIAwAAAA==.Naero:BAAALAADCgQIBQAAAA==.Naghar:BAAALAAECgYICwAAAA==.Namisan:BAAALAADCggIDwAAAA==.Naomiy:BAAALAADCggIDwAAAA==.Narjes:BAAALAAECgYIEQAAAA==.Narthromir:BAAALAADCgEIAQAAAA==.Nayah:BAAALAADCgYICAAAAA==.',Ne='Necromantus:BAAALAAECgMIBgAAAA==.Negodin:BAAALAAECgMIBQAAAA==.Neosoro:BAAALAAECgEIAQAAAA==.Nerlock:BAAALAADCgcIDAAAAA==.Netchenha:BAAALAAECgIIAgAAAA==.Netwaris:BAAALAADCgEIAQAAAA==.Neunschwänzi:BAAALAADCggICAAAAA==.',Nh='Nhenb:BAAALAADCgEIAQAAAA==.',Ni='Nickez:BAAALAAECgEIAgAAAA==.Niennia:BAAALAADCgcIBwAAAA==.Niin:BAAALAADCgUIBgAAAA==.Nijød:BAAALAAECgIIAgAAAA==.Nikity:BAAALAADCgYICQAAAA==.Ninalysii:BAAALAADCggIEAAAAA==.Nitrofera:BAAALAAECgMIAwAAAA==.Nixus:BAAALAAECgEIAQAAAA==.',No='Noctis:BAAALAAECgEIAQAAAA==.Noitescura:BAAALAADCgEIAQAAAA==.Nokur:BAAALAADCgYIBgAAAA==.Noodlesoup:BAAALAADCgQIBAABLAAECgEIAQABAAAAAA==.Norary:BAAALAAECgMIAwAAAA==.Nortênho:BAAALAAECgQICAAAAA==.Notz:BAAALAADCggIDgAAAA==.',Nu='Nunhöly:BAAALAADCggIEAAAAA==.Nusty:BAAALAADCgQIBAAAAA==.',['Nö']='Nöturnö:BAAALAADCgMIBQAAAA==.',Ob='Obsidien:BAAALAAECgMIAwAAAA==.',Od='Odysseus:BAAALAAECgQICAAAAA==.',Ok='Okasaki:BAAALAAECgYIDAAAAA==.',Ol='Oliele:BAAALAAECgUIBwAAAA==.',On='Onbonguinha:BAAALAAECgMIAwAAAA==.Oneiri:BAAALAAECgYIEAAAAA==.',Op='Ophellis:BAAALAADCgYIBgAAAA==.',Or='Organya:BAAALAAECgcIDwAAAA==.',Ot='Otherside:BAAALAADCggIFAAAAA==.',Ow='Ownadormg:BAAALAADCgcICAAAAA==.Ownedborn:BAAALAADCgcIBwAAAA==.',Oz='Ozyi:BAAALAAECgYIBwAAAA==.Ozzgen:BAAALAADCggICAAAAA==.',Pa='Pachenko:BAAALAADCgcIBwABLAAFFAIIAgABAAAAAA==.Pains:BAAALAADCgcICQAAAA==.Pajeh:BAAALAAECgMIBQAAAA==.Palacktrum:BAAALAAECgYICQAAAA==.Palah:BAAALAAECgUIBQAAAA==.Panða:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Paquinhoh:BAAALAAECgMIAgAAAA==.Parafinared:BAAALAAECgEIAQAAAA==.Pauladinho:BAAALAAECgIIAwAAAA==.',Pe='Pedroaço:BAAALAADCgEIAQABLAAECgYICgABAAAAAA==.Penelopedark:BAAALAADCgMIAwAAAA==.Pepito:BAAALAAECgYIDQAAAA==.Perseidas:BAAALAADCgMIAwAAAA==.Pesaa:BAAALAAECgYIBgAAAA==.',Ph='Phantoz:BAAALAAECgUIBQAAAA==.Philii:BAAALAAECgIIAgAAAA==.Phyrexius:BAAALAADCgcICwAAAA==.',Pi='Picklerick:BAAALAADCggICAAAAA==.Pirangueiroo:BAAALAADCgYIBgAAAA==.Pirikitinhah:BAAALAADCgcIBwAAAA==.Pirizin:BAAALAAECgUICQAAAA==.Piroquilidan:BAAALAADCgUICQABLAAECgEIAQABAAAAAA==.Pirus:BAAALAADCgcIBwAAAA==.',Po='Pohmei:BAAALAADCgYIBgAAAA==.Popopeka:BAAALAADCggICQAAAA==.Porthosrox:BAAALAAECgEIAQAAAA==.',Pr='Presiddent:BAAALAADCgcIEAAAAA==.Priapista:BAAALAAECgMIAwAAAA==.Priestiputa:BAAALAAECgQIBAAAAA==.Pristini:BAAALAADCgYIBwAAAA==.Priyla:BAAALAAECgIIAgAAAA==.Pryanka:BAAALAAECgYIDAAAAA==.',Ps='Psilodruidus:BAAALAADCgYIBwAAAA==.',['På']='Påndä:BAAALAAECgEIAQAAAA==.',Qu='Queliy:BAAALAADCgYICAAAAA==.Quixaba:BAAALAADCgcIDQAAAA==.',Ra='Radork:BAAALAAECgYICgAAAA==.Raduque:BAAALAAECgEIAQAAAA==.Rafaelgame:BAAALAAECggIBAAAAA==.Ragmage:BAAALAADCgcIDwAAAA==.Ragnaryos:BAAALAAECgYIEAAAAA==.Rairone:BAAALAAECgYICQAAAA==.Randël:BAAALAAECgMIAwAAAA==.Rapunxel:BAAALAADCggIFgAAAA==.Rarámuri:BAAALAADCgEIAQAAAA==.Rasha:BAAALAADCgMIAwAAAA==.Ravaella:BAAALAAECgEIAQAAAA==.Razorcrusher:BAAALAAECgMIAwAAAA==.Razortank:BAAALAAECgMIBgAAAA==.',Rb='Rbchama:BAAALAADCggIDwAAAA==.',Re='Recebas:BAAALAADCgQIBQAAAA==.Reverend:BAAALAAECgIIAwAAAA==.Revoltevoker:BAABLAAECoEVAAINAAgIkx4nBwC7AgANAAgIkx4nBwC7AgAAAA==.',Rh='Rhegium:BAAALAADCgcICgAAAA==.Rhenb:BAAALAADCgIIAgAAAA==.Rhoghar:BAAALAAECgcIDQAAAA==.',Ri='Risver:BAAALAADCgcIBwAAAA==.',Ro='Rolekss:BAAALAADCgcIDwAAAA==.Ropivacaine:BAAALAAECgMIBAAAAA==.Rosh:BAAALAAECggIEQAAAA==.Roverandom:BAAALAADCgMIAwAAAA==.Rowen:BAAALAADCgYIBgAAAA==.Roy:BAAALAAECgYICwAAAA==.Roöf:BAAALAAECgcIDwAAAA==.',Ru='Rubrø:BAAALAADCgYIBgAAAA==.Rubya:BAAALAAECgQICAAAAA==.Rudder:BAAALAADCgUIBQAAAA==.Rusbe:BAAALAADCgUIBQAAAA==.',Ry='Ryøkø:BAAALAAECgYICgAAAA==.',['Rä']='Räidela:BAAALAAECgYIDQAAAA==.',['Ró']='Rótulo:BAAALAADCgIIAgAAAA==.',['Rö']='Rööh:BAAALAAECgYICQAAAA==.',Sa='Saariaaho:BAAALAADCgcIDQAAAA==.Sabïnne:BAAALAAECgEIAQAAAA==.Sacha:BAAALAAECgcICAAAAA==.Saelwynd:BAAALAADCgcICQAAAA==.Saluton:BAAALAAECgIIAgAAAA==.Samiarcane:BAAALAADCgcIEQAAAA==.Samidemon:BAAALAADCgcIDQABLAADCgcIEQABAAAAAA==.Sanderoveio:BAAALAAECgMIBAAAAA==.Sarashi:BAAALAADCgUIBQAAAA==.Sarttz:BAAALAAECgYIDwAAAA==.Sarttzzd:BAAALAADCgQIBAABLAAECgYIDwABAAAAAA==.Sartzz:BAAALAADCgMIAwAAAA==.Saskuatera:BAAALAAECgMIAwAAAA==.',Sc='Schroeder:BAAALAAECgQIBgAAAA==.Schwi:BAAALAAECgEIAQAAAA==.',Se='Seelyvorey:BAAALAAECgYIDAAAAA==.Selph:BAAALAAECgMIBQAAAA==.Semasa:BAAALAADCgIIAgAAAA==.Sens:BAAALAADCgcIBwAAAA==.Sereni:BAAALAAECgIIAgAAAA==.Serlkin:BAAALAADCgcIBwAAAA==.Seufurico:BAAALAADCggICAAAAA==.',Sh='Sha:BAAALAAECgIIAgAAAA==.Shadowvoker:BAAALAADCggIDQAAAA==.Shadowwlock:BAAALAAECgMIBAAAAA==.Shalivanëfox:BAAALAAECgcICQAAAA==.Shamante:BAAALAADCgYIBgAAAA==.Shanpoo:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Shaolink:BAAALAAECgMIBAABLAAECgUIBQABAAAAAA==.Sharckaron:BAAALAAECgIIAwAAAA==.Shawcram:BAAALAADCgIIAgAAAA==.Shiburudina:BAAALAADCgQIBAAAAA==.Shigami:BAAALAAECgYIEQAAAA==.Shiroesan:BAAALAADCggICAAAAA==.Shortsham:BAAALAAECgIIAgAAAA==.Shädøw:BAAALAADCgYIBgABLAADCgYICQABAAAAAA==.Shíroé:BAAALAAECgEIAQAAAA==.Shîvas:BAAALAAECgYICQAAAA==.Shïnön:BAAALAAECgMIBAAAAA==.',Si='Sianus:BAAALAAECgYICwAAAA==.Sibilith:BAAALAADCgEIAQAAAA==.Sicariuz:BAAALAADCgUIBQAAAA==.Silverhand:BAAALAADCggICAAAAA==.Sinliss:BAAALAADCggIEQAAAA==.',Sk='Skorge:BAAALAAECgEIAQAAAA==.Skál:BAAALAADCgIIAwAAAA==.Skäuz:BAAALAADCgQIBAAAAA==.',Sl='Slashield:BAAALAAECgYICAABLAAECggIEAABAAAAAA==.',Sm='Smaragdina:BAAALAAECggIDwAAAA==.',Sn='Snipinho:BAAALAADCgIIAgAAAA==.Snowhand:BAAALAAECgIIAwAAAA==.Snullër:BAAALAAECgEIAQAAAA==.Snøkill:BAAALAADCgYIBgAAAA==.',So='Solaryel:BAAALAADCgcICQAAAA==.Sonameh:BAAALAAECgEIAQAAAA==.Soneca:BAAALAADCgYIBgAAAA==.Soneka:BAAALAADCggIDQAAAA==.Sorceleur:BAAALAADCggIFAABLAADCggIFgABAAAAAA==.Soriak:BAAALAADCgIIAgAAAA==.Sorrateiro:BAAALAADCgQIBQAAAA==.Sougigante:BAAALAAECgIIAwAAAA==.',Sp='Spellshadown:BAAALAADCggIDAAAAA==.Splotch:BAAALAAECgQICQAAAA==.Spratch:BAAALAADCggICAABLAAECgQICQABAAAAAA==.',St='Stagnate:BAAALAAECgMIAwAAAA==.Stanyz:BAAALAADCgcIBwAAAA==.Starkn:BAAALAAECgMIBQAAAA==.Stoly:BAAALAAECgIIAgAAAA==.Strahr:BAAALAADCgcICAAAAA==.Strexx:BAAALAADCggIDgAAAA==.Strongher:BAAALAAECgIIAgAAAA==.Stronoffgard:BAAALAAECgYICwAAAA==.',Su='Suellidan:BAAALAADCgQIBAAAAA==.Sulfur:BAAALAAECgMIAwAAAA==.Sunkeeper:BAAALAADCgIIAQAAAA==.Superelfo:BAAALAADCgUIBgAAAA==.',Sy='Sylanore:BAAALAADCgQIBAAAAA==.Synka:BAAALAADCgUIBQAAAA==.',Sz='Szaan:BAAALAAECgcIDgAAAA==.',Ta='Tacticianx:BAAALAAECgIIAgAAAA==.Taloco:BAAALAAECgYIBgAAAA==.Tankeda:BAAALAAECgQIBAAAAA==.Tariia:BAAALAADCgEIAQAAAA==.Tasleen:BAAALAADCgMIAwAAAA==.Taywiz:BAAALAADCggICgAAAA==.',Tc='Tchukinha:BAAALAADCggIDQAAAA==.',Td='Tdarklord:BAAALAAECgEIAQAAAA==.',Te='Tempestar:BAAALAADCggICAAAAA==.Tenóry:BAAALAADCgcICQAAAA==.Teppes:BAAALAADCggIBwAAAA==.Terpa:BAAALAAECgYICwAAAA==.Tezerret:BAAALAAECgUIBQAAAA==.',Th='Thalgrim:BAAALAAECgUIBQAAAA==.Thamyssa:BAAALAADCgEIAQAAAA==.Tharinthor:BAAALAADCggICAAAAA==.Tharizdum:BAAALAADCgUIBgABLAAECgcIDAABAAAAAA==.Thefatherz:BAAALAADCgUIBwAAAA==.Thespitit:BAAALAAECgQICAAAAA==.Thorbjorne:BAAALAADCgcIBwAAAA==.Thordul:BAAALAADCggICAAAAA==.Thundara:BAAALAADCgYIBwAAAA==.',Ti='Ticomia:BAAALAAECgMIBwAAAA==.Tindera:BAAALAAECgEIAQAAAA==.Tiãomonstrin:BAAALAADCgYICAAAAA==.',To='Toni:BAAALAAECgIIAgAAAA==.Tonsodh:BAAALAADCggICwAAAA==.',Tr='Trinitys:BAAALAAECgIIAgAAAA==.Trombas:BAAALAAECgIIAgAAAA==.',Ts='Tsuki:BAAALAAECgYIDQAAAA==.',Tu='Turandil:BAAALAADCgYIBgAAAA==.Turles:BAAALAAECgYICQAAAA==.',Tx='Txanga:BAAALAADCggIEgAAAA==.',Ty='Tyco:BAAALAADCgYIBgAAAA==.Tyde:BAAALAAECgIIBAAAAA==.Typol:BAAALAAECgIIAgAAAA==.Tyrelle:BAAALAADCgEIAQAAAA==.',['Tá']='Táila:BAAALAAECgMIBAAAAA==.',['Tó']='Tógádó:BAAALAAECgMIAwAAAA==.',['Tü']='Türier:BAAALAADCgIIAgAAAA==.',Ul='Ulduan:BAAALAADCgYIBgAAAA==.',Um='Umburana:BAAALAADCgYICgABLAADCgcIDQABAAAAAA==.Umehara:BAAALAAECgMIAwAAAA==.Umtrutaai:BAAALAADCggIEgAAAA==.',Un='Unclearnaldo:BAAALAAECgIIAgAAAA==.Undeadbear:BAAALAADCggIFgAAAA==.',Ur='Urgath:BAAALAAECgMIAwAAAA==.Uron:BAAALAADCggIDAAAAA==.',Va='Vaalla:BAAALAAECgUIBgAAAA==.Vahaka:BAAALAADCgEIAQAAAA==.Vallyri:BAAALAAECgUIBwAAAA==.Vandeerr:BAAALAADCgcIBwAAAA==.Varuna:BAAALAADCgEIAQAAAA==.Vastor:BAAALAAECgYIDQAAAA==.Vatrushkia:BAAALAAECgIIAgAAAA==.Vatruska:BAAALAADCgUIBQAAAA==.',Ve='Vecsa:BAAALAADCgYIBgAAAA==.Veellkan:BAAALAAECgMIAwAAAA==.Vellami:BAAALAAECgMIBAAAAA==.Velocífero:BAAALAADCgIIAgAAAA==.Venator:BAAALAAECgcICgAAAA==.Verind:BAAALAADCgIIAgAAAA==.Vertizine:BAAALAADCgcIBwAAAA==.',Vi='Viciadø:BAAALAAECggIBAAAAA==.Viiolenta:BAAALAAECgYICAAAAA==.Vikat:BAAALAAECgQICgAAAA==.Vits:BAAALAAECgEIAgAAAA==.',Vn='Vnk:BAAALAADCgcIBwAAAA==.',Vo='Voidwar:BAAALAADCgcICgAAAA==.Volkarok:BAAALAADCgQIBAAAAA==.Vouexporela:BAAALAAECgcIDgAAAA==.Vougam:BAAALAADCgYICQAAAA==.',Vu='Vultures:BAAALAADCgEIAQAAAA==.',Vy='Vyana:BAAALAADCggICQAAAA==.',['Vø']='Vøidelicious:BAAALAAECgMIBgAAAA==.Vøxen:BAAALAADCgYICwAAAA==.',['Vÿ']='Vÿk:BAAALAADCgcIBwAAAA==.',Wa='Warlockdoido:BAAALAAECgYICQAAAA==.Wazrak:BAAALAADCgUICAAAAA==.',We='Weedivh:BAAALAAECgEIAQAAAA==.Weiserbud:BAAALAADCgcIBwAAAA==.Wennies:BAAALAAECgMIBQAAAA==.Wesa:BAAALAAECgMIBAAAAA==.',Wh='Whisu:BAAALAADCgcIBwAAAA==.',Wi='Wifehunt:BAAALAAECgIIAgAAAA==.Willvictory:BAAALAAECgUICQAAAA==.Winnettou:BAAALAADCgcIDgAAAA==.',Wu='Wuan:BAAALAAECgUIBwAAAA==.',['Wä']='Wälls:BAAALAADCgcICAAAAA==.',['Wï']='Wïndfury:BAAALAAECgEIAQAAAA==.',Xa='Xamaprocrime:BAAALAAECgUIBgABLAADCggICAABAAAAAA==.Xamatruivo:BAAALAAECgQIBwAAAA==.Xamyjr:BAAALAADCgcIBgAAAA==.Xamâbulança:BAAALAADCgUIBQAAAA==.Xamãfofo:BAAALAAECgcIBwAAAA==.Xanasmanas:BAAALAAFFAIIAgAAAA==.',Xe='Xerthas:BAAALAAECgMIAwAAAA==.',Xu='Xubrao:BAAALAADCggICAAAAA==.Xuratøø:BAAALAAECgQIBwAAAA==.',Xy='Xymor:BAABLAAECoEXAAMNAAgITiSmAwASAwANAAgITiSmAwASAwAGAAEIziPoBgBlAAAAAA==.Xyuwan:BAAALAADCgcICgAAAA==.',Ya='Yamirshi:BAAALAADCgYIBgAAAA==.',Yd='Ydoom:BAAALAADCgMIAwAAAA==.',Ye='Yenniferxd:BAAALAADCgQIBAAAAA==.',Yi='Yiba:BAAALAAECgIIAgAAAA==.',Yo='Yoriko:BAAALAAECgQIBAABLAAECggIFwANAE4kAA==.Yorios:BAAALAAECgQICwAAAA==.',Ys='Yshiny:BAAALAADCgQIBAABLAAECgYIEQABAAAAAA==.',Za='Zamii:BAAALAAECgYIDwAAAA==.Zanncor:BAAALAADCgYIBgAAAA==.Zapnoodle:BAAALAAECggICAAAAA==.Zaynab:BAAALAAECgIIAgAAAA==.',Ze='Zegotinhamm:BAAALAADCgMIAwAAAA==.Zelyx:BAAALAADCgcIBwAAAA==.Zenked:BAAALAAECgYIEAAAAA==.Zenkedy:BAAALAADCggIDwAAAA==.Zerohealing:BAAALAADCgcIDQAAAA==.Zerty:BAAALAADCgcIBwAAAA==.Zethart:BAAALAAECgYICQAAAA==.',Zh='Zharock:BAAALAAECgYIDAAAAA==.',Zi='Zigart:BAAALAADCgYIBgAAAA==.',Zo='Zones:BAAALAAECgYIDQAAAA==.',Zu='Zugflinstons:BAAALAAECgIIAgAAAA==.',['Ág']='Ágioskypria:BAAALAADCgYIBgAAAA==.',['Ák']='Ákima:BAAALAADCggICAAAAA==.',['Än']='Ängron:BAAALAADCgcICwAAAA==.',['Ét']='Étel:BAAALAAECgIIAgAAAA==.',['Ïx']='Ïxdxdx:BAAALAAECgMIAwAAAA==.',['Ðo']='Ðougs:BAAALAADCgcIDAAAAA==.',['Ðâ']='Ðântë:BAAALAADCggICwAAAA==.',['Ôc']='Ôcto:BAAALAAECgYIBgAAAA==.',['Øm']='Ømegazerø:BAAALAADCgcIBwAAAA==.',['ßr']='ßrenndøn:BAAALAADCggICwAAAA==.ßrì:BAAALAADCgYIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end