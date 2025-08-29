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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','Warrior-Protection','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Holy','Mage-Arcane',}; local provider = {region='US',realm='Cenarius',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aalen:BAAALAAECgcIDgAAAA==.',Ab='Abraham:BAAALAADCgYIBgAAAA==.',Ac='Achooah:BAAALAAECgcIEgAAAA==.Acturus:BAAALAAECgMIAwAAAA==.',Ad='Adris:BAAALAAECgEIAQAAAA==.',Ae='Aea:BAAALAAECgMIAwAAAA==.Aegisblade:BAAALAADCgQIBAAAAA==.Aelisalla:BAAALAAECgMIAwAAAA==.Aenie:BAAALAADCggIFQAAAA==.Aennielash:BAAALAADCgcIEQABLAADCggIDwABAAAAAA==.Aeralith:BAAALAADCggICAAAAA==.',Ag='Agnescat:BAAALAAECgcIDwAAAA==.Agnostos:BAAALAADCgMIAwAAAA==.',Ak='Akechi:BAAALAAECgMIBAAAAA==.Aki:BAAALAAECgEIAQAAAA==.Akrossurface:BAAALAAECgYICwAAAA==.',Al='Aladani:BAAALAAECgMIAwAAAA==.Alderax:BAAALAAECgQICQAAAA==.Alexister:BAAALAADCgcICQAAAA==.Algerzan:BAAALAADCgYIBwABLAAECgUIBgABAAAAAA==.Algerzen:BAAALAAECgUIBgAAAA==.Allizana:BAAALAAECgIIAgAAAA==.',Am='Amahir:BAAALAAECgIIAgAAAA==.Amelei:BAAALAAECggIEAAAAA==.Amethystra:BAAALAAECgUIBwAAAA==.Amp:BAAALAAECgIIAgAAAA==.Amìty:BAAALAADCggICAAAAA==.',An='Andarieal:BAAALAAECgMIAwAAAA==.Andazlin:BAAALAAECgcIDQAAAA==.Andrayuh:BAAALAADCgcIBwAAAA==.Ankesenamun:BAAALAADCgMIAwAAAA==.Ankhling:BAAALAAECgQICQAAAA==.Annamonk:BAAALAAECgcIEgAAAA==.Anyafire:BAAALAAECgEIAQAAAA==.',Ap='Apôllo:BAAALAADCggIFwAAAA==.',Ar='Aralzin:BAAALAAECggICAAAAA==.Ardy:BAAALAADCgYIBgAAAA==.Arguile:BAAALAAECgMIAwAAAA==.Armîda:BAAALAAECgMIBgAAAA==.Arouraa:BAAALAADCgcIBwAAAA==.Arvalyn:BAAALAAECgMIBAAAAA==.',As='Ashlia:BAAALAAECgYICAAAAA==.Astralflames:BAAALAAECgQICAAAAA==.',At='Atlus:BAAALAADCgIIAgABLAADCgMIBQABAAAAAA==.',Au='Auramôon:BAAALAADCgcICQAAAA==.Aurock:BAAALAAECgYIDgAAAA==.',Ax='Axazon:BAAALAAECgYIBgAAAA==.',Az='Azrriel:BAAALAADCgQIBAAAAA==.Azzerria:BAAALAAECgMIBgAAAA==.',Ba='Babestire:BAAALAADCgcICQAAAA==.Baki:BAAALAAECgYIDAAAAA==.Baldestrazza:BAAALAADCggIDAAAAA==.Bananadragon:BAAALAAECgMIBgAAAA==.Bascus:BAAALAAECgMIBAAAAA==.Bassuu:BAAALAAECgQICQAAAA==.Battle:BAAALAAECgMIAwAAAA==.Bazongås:BAAALAADCggIEAAAAA==.',Be='Beerrun:BAAALAADCgcIBwAAAA==.Belfør:BAAALAAECgEIAQAAAA==.Bellius:BAAALAAECgIIAgAAAA==.Benafleckton:BAAALAADCggIFQAAAA==.',Bi='Bigdampunch:BAAALAADCgcIBwAAAA==.Bigfisty:BAAALAAECgcIDQAAAA==.Bigtotem:BAAALAADCggIDwAAAA==.Bironin:BAAALAAECgEIAQAAAA==.',Bl='Blaqkbeard:BAAALAADCggICAAAAA==.Bledawn:BAAALAAECgEIAQAAAA==.Blindboy:BAAALAAECgEIAQAAAA==.Bloodricuted:BAAALAAECgIIAgAAAA==.Blàqk:BAAALAAECgIIAwAAAA==.',Bo='Boltsnhoes:BAAALAAECgYIDQAAAA==.Boo:BAAALAADCgMIAwAAAA==.Bootylicious:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Bophedese:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Boragarsh:BAAALAADCggIEAAAAA==.Bottom:BAAALAADCgQICAAAAA==.Bowlyne:BAAALAAECgYICAAAAA==.',Br='Brightblades:BAAALAADCgcIBwABLAADCggICQABAAAAAA==.Brumsta:BAAALAAECgYICAAAAA==.Brutalious:BAAALAADCgcICAAAAA==.',Bu='Buckaroo:BAAALAADCgcIBwABLAAECgMIBwABAAAAAA==.Buckcherry:BAAALAAECgMIBwAAAA==.Bulvaan:BAAALAAECgYICwAAAA==.',Ca='Calair:BAAALAAECgYIBgAAAQ==.Camps:BAAALAAECgMIAwAAAA==.Cantora:BAAALAAECgYICQAAAA==.Cappuchino:BAAALAAECgMIAwAAAA==.Caster:BAAALAAECgEIAQAAAA==.Catharsiz:BAAALAADCggIDQABLAAECgIIAwABAAAAAA==.Catholicism:BAAALAAECgcIDwAAAA==.Cayvie:BAAALAAECgMIAwAAAA==.Cazicthule:BAAALAAECgMIAwABLAAECgMIBQABAAAAAA==.',Cb='Cballi:BAAALAADCgYICwAAAA==.',Ce='Cedroes:BAAALAAECgMIAQAAAA==.Celandine:BAAALAAECgEIAQAAAA==.Cerror:BAAALAADCgMIAwAAAA==.',Ch='Cheezepuffs:BAAALAADCgcIDAAAAA==.Chilibean:BAAALAAECgIIAwAAAA==.Chipadip:BAAALAAECgcIEwAAAA==.Chiqaboom:BAAALAAECgIIAgAAAA==.Chrixus:BAAALAADCggIDgAAAA==.Chunlì:BAAALAAECgIIAgAAAA==.',Cl='Clayfrog:BAAALAADCggICAAAAA==.Clolarion:BAAALAAECgIIAgAAAA==.',Co='Conly:BAAALAAECgMIAwAAAA==.Contract:BAAALAAECgMIBAAAAA==.Contrakt:BAAALAAECgQIBAAAAA==.Corvalis:BAAALAAECgcIDQAAAA==.Cozy:BAAALAADCgcIBwAAAA==.',Cp='Cpuff:BAAALAADCgcIBwAAAA==.',Cr='Crowedots:BAAALAADCgYICwAAAA==.Crowedrogo:BAAALAAECgUIEAAAAA==.Crystaliria:BAAALAADCgEIAgABLAAECgUIBwABAAAAAA==.',Cu='Curiel:BAAALAAECgMIBgAAAA==.Curryoxtail:BAAALAADCgYIAQAAAA==.',Cv='Cviper:BAAALAAECgcIDQAAAA==.',Cy='Cyanos:BAAALAAECgEIAQAAAA==.',Cz='Czernabog:BAAALAAECgIIAgAAAA==.',Da='Dae:BAAALAAECgQICAAAAA==.Daggor:BAAALAADCggIDwAAAA==.Damàcles:BAAALAAECgYIDAAAAA==.Daridru:BAAALAADCgcIBwAAAA==.Darkhrt:BAAALAAECgMIBgAAAA==.Darkknightss:BAAALAAECgMIAwAAAA==.Darthrevan:BAAALAADCgcIBwAAAA==.Darylu:BAAALAAECgEIAQAAAA==.Dazedxar:BAAALAAECgMIBgAAAA==.',De='Deathdeath:BAAALAAECgQIBQAAAA==.Deathwavez:BAAALAAECgYICAAAAA==.Decadron:BAAALAAECgEIAQAAAA==.Dehmortius:BAAALAADCgcIBwAAAA==.Deiron:BAAALAAECgcIDgAAAA==.Delirium:BAAALAAECgIIAgAAAA==.Delithsong:BAAALAADCggICAABLAAECgUIBwABAAAAAA==.Dennis:BAAALAAECgcIEQAAAA==.Departéd:BAAALAAECgYICQAAAA==.Derieri:BAAALAAECgYICwAAAA==.Deselect:BAAALAADCgEIAQABLAAECgQICAABAAAAAA==.',Di='Diditagian:BAAALAADCgYIBgAAAA==.Dilaura:BAAALAADCgcICgAAAA==.Dirf:BAAALAADCggIDgAAAA==.Distotem:BAAALAAECgQIBwAAAA==.Divisioon:BAAALAADCgcIDQAAAA==.',Dk='Dkartha:BAAALAADCgMIAwAAAA==.',Do='Dobah:BAAALAADCgUIBQAAAA==.Dogness:BAAALAADCggIEQAAAA==.Dohnilt:BAAALAAECgQIBwAAAA==.Dorflundgren:BAAALAAECggIEwAAAA==.',Dr='Dracophilia:BAAALAAECgYICQAAAA==.Dracthraen:BAAALAAECgcIDQAAAA==.Draenorious:BAAALAAECgMIAwAAAA==.Drafizzy:BAAALAADCgcICQAAAA==.Dragnier:BAAALAAECggICQAAAA==.Drakenshiinx:BAAALAAECgIIAgAAAA==.',Ds='Dseed:BAAALAADCggIDgAAAA==.',Du='Dudubob:BAAALAAECgIIAgAAAA==.Dumbasmus:BAAALAAECgUICAAAAA==.',['Dè']='Dèparted:BAAALAADCgQIBAAAAA==.',Ed='Ediah:BAAALAAECggICQAAAA==.Edibleundies:BAAALAADCgYIBgAAAA==.',Ei='Eitenthees:BAAALAAECgMIBQAAAA==.',El='Elcarnal:BAAALAAECgMIAwAAAA==.Eluneadora:BAAALAADCgIIAgAAAA==.Elvishprezly:BAAALAAECgMIBgAAAA==.',Em='Em:BAAALAAECgEIAQAAAA==.Emeon:BAAALAAECgEIAQAAAA==.',En='Enailla:BAAALAADCggIDwAAAA==.Enginseer:BAAALAADCgIIAgAAAA==.Enlighten:BAAALAADCgMIAwAAAA==.Entara:BAAALAADCgMIAwAAAA==.',Er='Erazel:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',Es='Esoj:BAAALAADCgYIBgAAAA==.Esport:BAAALAAECgIIAgAAAA==.Esvanka:BAAALAAECgQIBQAAAA==.',Et='Ethereallyn:BAAALAADCggIFQAAAA==.',Eu='Euterpe:BAAALAAECgMIAwAAAA==.',Ey='Eylish:BAAALAADCggIFAAAAA==.',Ez='Ezeder:BAAALAAECggIDwAAAA==.Ezry:BAAALAAECgYICAAAAA==.',Fa='Faldomar:BAAALAAECgIIAgAAAA==.Fallen:BAAALAADCggIBgAAAA==.Fangskin:BAAALAAECgYICAAAAA==.',Fe='Felvon:BAAALAADCgIIAgAAAA==.Ferskur:BAABLAAECoEXAAICAAYIuxOBHwCnAQACAAYIuxOBHwCnAQAAAA==.',Fg='Fg:BAAALAADCgYIBgAAAA==.',Fl='Flacoo:BAAALAAECgYICAAAAA==.',Fo='Foxiehunts:BAAALAADCgQIBAAAAA==.',Fr='Fronklin:BAAALAAECgIIAwAAAA==.Frostedflake:BAAALAAECgMIAwAAAA==.Frostfox:BAAALAAECgEIAQAAAA==.',Fu='Fulmine:BAAALAADCggIDAAAAA==.Fuzybear:BAAALAADCgcIBwAAAA==.',Fy='Fyo:BAAALAAECgcIEwAAAA==.',Ga='Gaige:BAAALAADCgcIBwAAAA==.Gargon:BAAALAAECgQIBgAAAA==.Gatchagooner:BAAALAADCggIEAAAAA==.',Ge='Gehtbent:BAAALAADCggICwAAAA==.Geist:BAAALAADCgUIBQAAAA==.Gentleman:BAAALAADCgUIBgABLAAECgIIAwABAAAAAA==.Geshaan:BAAALAADCggICAAAAA==.Getchu:BAAALAADCgcIDAABLAAECgIIBAABAAAAAA==.',Gi='Girthbender:BAAALAADCgEIAQAAAA==.',Gl='Glacier:BAAALAADCgcIBwAAAA==.Glue:BAAALAAECgcIDQAAAA==.Glòo:BAAALAADCgcIBwAAAA==.',Go='Gokexu:BAAALAADCgcIDAAAAA==.Goldabyss:BAAALAADCgEIAQAAAA==.Goldenlotus:BAAALAAECgcIDwAAAA==.Golder:BAAALAAECgcIEAAAAA==.Golly:BAAALAAECgYICQAAAA==.Gorgoneion:BAEALAAECgMIBAABLAAFFAEIAQABAAAAAA==.Gortess:BAEALAAFFAEIAQAAAA==.',Gr='Graizer:BAAALAADCggIEgAAAA==.Grandaddy:BAAALAADCgQIBAAAAA==.Grapehunter:BAAALAAECgEIAQAAAA==.Grippies:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Grumley:BAAALAAECgIIAwAAAA==.Gryfalia:BAAALAAECgIIBQAAAA==.',['Gó']='Góat:BAAALAAECggIDQAAAA==.',Ha='Haart:BAAALAADCgcIAgAAAA==.Haavok:BAAALAAECgYICwAAAQ==.Halyte:BAAALAAECgQICQAAAA==.Handwelor:BAAALAADCgMIAwAAAA==.Happyfeet:BAAALAAECgcIDwAAAA==.Harak:BAAALAAECgEIAQAAAA==.Harath:BAAALAAECgEIAQAAAA==.Harf:BAAALAADCggIFQAAAA==.Havoc:BAAALAAECgMIBgAAAA==.',He='Healingtrees:BAAALAAECgEIAQAAAA==.Heckron:BAAALAADCggIDQAAAA==.Heeroqt:BAAALAAECgcIBwAAAA==.Hefaestuss:BAAALAAECgIIAgAAAA==.',Ho='Holychaos:BAAALAADCggICAAAAA==.Holyfíre:BAAALAADCgYICQAAAA==.Holygodisme:BAAALAAECgEIAQAAAA==.Holyram:BAAALAAECgMIAwAAAA==.Hound:BAAALAAECgIIAwAAAA==.',Hu='Hunt:BAAALAADCgcIDgABLAAECgYICAABAAAAAA==.',['Hà']='Hàvok:BAAALAAECgIIAgABLAAECgIIAwABAAAAAA==.',Id='Idlyby:BAAALAADCggIDAAAAA==.',Ih='Ihavefleas:BAAALAAECgMIAwAAAA==.',Il='Iledian:BAAALAAECgQICAAAAA==.Illidiet:BAAALAAECgMIAwAAAA==.',In='Infierna:BAAALAADCgcIDgAAAA==.Insomnium:BAAALAADCgYIBgAAAA==.Intruder:BAAALAADCggICAAAAA==.',Ir='Iris:BAAALAADCgQICgAAAA==.Ironfistxrio:BAAALAADCgcIBwAAAA==.',Is='Isath:BAAALAAECgMIBgAAAA==.',It='Ithuran:BAAALAADCggIDwAAAA==.',Iw='Iwillpeeonu:BAAALAAECgYICAAAAA==.',Iz='Izzydead:BAAALAADCgEIAQAAAA==.',Ja='Jainadra:BAAALAAECgIIAwAAAA==.Jalani:BAAALAAECgQICAAAAA==.Jampion:BAAALAADCggIFgAAAA==.Janedoe:BAAALAAECgQICAAAAQ==.Jassabelyda:BAAALAADCgEIAQAAAA==.Java:BAAALAAECgMIBwAAAA==.',Je='Jerg:BAAALAAECgMIBAAAAA==.Jexzyn:BAAALAAECgIIAgAAAA==.',Jo='Jond:BAAALAAECgcICQAAAA==.',Jr='Jrôxs:BAAALAAECgMIBAAAAA==.',Ju='Jubbins:BAAALAADCgIIAgAAAA==.Jubilee:BAAALAAECgIIBAAAAA==.Jubnon:BAAALAAECgYIBgAAAA==.Juriel:BAAALAAECgMIAwAAAA==.',Ka='Kaggameshi:BAAALAAECgMIAwAAAA==.Kamilla:BAAALAAECgMIAwAAAA==.Kamorita:BAAALAADCgUIBQAAAA==.Karila:BAAALAAECgMIAwAAAA==.Karilina:BAAALAADCgEIAQAAAA==.Katarina:BAAALAAECgcICAAAAA==.Kathu:BAAALAAECgQIBwAAAA==.Kayllaa:BAAALAADCgcIDgAAAA==.',Ke='Kelticrain:BAAALAAECgEIAQAAAA==.Kelvin:BAAALAADCggICgAAAA==.Keuri:BAAALAAECgQICQAAAA==.Kezielk:BAABLAAFFIEFAAIDAAMItgdzAgDBAAADAAMItgdzAgDBAAAAAA==.Kezifel:BAAALAAECgYIBgABLAAFFAMIBQADALYHAA==.Kezinik:BAAALAADCggICAABLAAFFAMIBQADALYHAA==.',Ki='Kieshara:BAAALAADCggICAAAAA==.Kitas:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.',Kl='Klegain:BAAALAAECgMIBQAAAA==.',Ko='Koradran:BAAALAADCggIFQAAAA==.Koujii:BAAALAAECgcIDQAAAA==.',Kr='Kristyana:BAAALAADCggIFQABLAAECgUIBwABAAAAAA==.',Ks='Ksenja:BAAALAAECgQICQAAAA==.',Ky='Kynyse:BAAALAADCggIDAAAAA==.Kysindra:BAAALAAECggIEgAAAA==.Kyuu:BAAALAAECgMIBgAAAA==.',['Kè']='Kètåsét:BAAALAADCgQIBAAAAA==.',La='Ladyneasa:BAAALAAECgQICAAAAA==.Lamennais:BAAALAAECgIIAgAAAA==.Lapsene:BAAALAADCggIDwAAAA==.Lavendae:BAAALAAECgMIBQAAAA==.Laxus:BAABLAAECoEVAAMEAAcIBQvrHwBjAQAEAAcIBQvrHwBjAQAFAAQI4wXWTwC7AAAAAA==.',Le='Leaorix:BAAALAADCgQIBAAAAA==.Lesath:BAAALAAECgYICwAAAA==.Leshalles:BAAALAADCgIIAgAAAA==.Leviathayne:BAAALAAECgIIAgAAAA==.',Li='Liazel:BAAALAAECgcIEwAAAA==.Lichkingjr:BAAALAADCgUIBQAAAA==.Lightboi:BAAALAAECgIIAgABLAAECgYIBgABAAAAAQ==.Lilagosa:BAAALAAECgcIEwAAAA==.Liliana:BAAALAADCgMIAwAAAA==.Lilrage:BAAALAAECgIIAgAAAA==.Lilwarcaster:BAAALAAECgMIBgAAAA==.Limen:BAAALAAECgEIAQAAAA==.',Lo='Lonelyheart:BAAALAAECgYICwAAAA==.Loopi:BAAALAAECgMIAwAAAA==.Lorechi:BAAALAAECgcICQAAAA==.',Lu='Lubesock:BAAALAAECgYIBwAAAA==.Lucyl:BAAALAADCgcIBwAAAA==.Lumpyteeth:BAAALAADCgUIBQAAAA==.Lunatick:BAAALAAECgcICwAAAA==.',Ly='Lype:BAAALAADCgEIAQABLAADCggIBgABAAAAAA==.Lyriele:BAAALAADCgcIBwAAAA==.',Ma='Maddex:BAAALAADCgUIBwAAAA==.Madfurrion:BAAALAADCggIDgAAAA==.Magdalyne:BAAALAAECgEIAQAAAA==.Magedudee:BAAALAAECgcIDQAAAA==.Magespec:BAAALAADCggICAAAAA==.Maghal:BAAALAADCgcIBwAAAA==.Maidmariann:BAAALAAECgEIAQAAAA==.Mainen:BAAALAAECgMIAwAAAA==.Maizerial:BAAALAAECgEIAQABLAADCgUIBQABAAAAAA==.Malfei:BAAALAADCggIFQAAAA==.Malignus:BAAALAAECgQICQAAAA==.Manatea:BAAALAAECgcIDAAAAA==.Mandori:BAAALAADCgcIDAAAAA==.Marceh:BAAALAADCggIDwAAAA==.Marcushorde:BAAALAAECgYICwAAAA==.Marineoracle:BAAALAAECgQICAAAAA==.Martemous:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Martypriest:BAAALAAECgMIAwAAAA==.Mashal:BAAALAADCgcIBwAAAA==.Mashdon:BAAALAADCgYICQAAAA==.Masochistic:BAAALAADCggIEAAAAA==.Mavik:BAAALAADCgEIAQAAAA==.',Me='Me:BAAALAAECgEIAQAAAA==.Meatsac:BAAALAAECgIIAwAAAA==.Mechallama:BAAALAAECgMIAwAAAA==.Mellennah:BAAALAAECgQICAAAAA==.Menrvae:BAAALAAECgMIBgAAAA==.',Mi='Miarian:BAAALAADCggIDwAAAA==.Mikdra:BAAALAADCgQIBAAAAA==.Mithara:BAAALAAECgYIDgAAAA==.',Mo='Mogwrath:BAAALAAECgYICwAAAA==.Mongsok:BAAALAAECggIDQAAAA==.Monkmonkmonk:BAAALAAECgMIBQABLAAECgQIBQABAAAAAA==.Morash:BAAALAAECgYIDQAAAA==.Morgai:BAAALAADCgIIAgAAAA==.',Mu='Mulakrup:BAAALAADCgMIAwAAAA==.Mumple:BAAALAAECgMIBAAAAA==.Mustashe:BAAALAAECgYIBgABLAAECgYICAABAAAAAA==.',My='Mynöghra:BAAALAADCgQIBAAAAA==.Myshak:BAAALAAECgMIBgAAAA==.Mystics:BAAALAADCgUIBQAAAA==.Mysticsoul:BAAALAAECgcIEwAAAA==.',['Mä']='Mäple:BAAALAAECgMIAwAAAA==.',Na='Nadizel:BAAALAADCgcIFAAAAA==.Naglfer:BAAALAADCggICAAAAA==.Nakama:BAAALAAECgYICAAAAA==.Nalestron:BAAALAAECgYICQAAAA==.Naruke:BAAALAADCgYIBgAAAA==.Narzud:BAAALAAECgEIAQAAAA==.Natália:BAAALAAECgcIEQAAAA==.Navodous:BAAALAADCgIIAgAAAA==.Nazmyr:BAAALAAECgYIDgAAAA==.',Ne='Neasa:BAAALAADCgIIAgAAAA==.Necrofeelyea:BAAALAADCgQIBAABLAAECgEIAQABAAAAAA==.Neolandar:BAAALAAECgMIBQAAAA==.Neomaiden:BAAALAADCgQIBAAAAA==.',Ni='Nickelbritt:BAAALAAECgMIBAAAAA==.Nimriel:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.',No='Nomchu:BAAALAAECgIIBAAAAA==.Notgitty:BAAALAADCgYIDQAAAA==.Notsu:BAAALAADCgcIDAAAAA==.Novidius:BAAALAAECgQICQAAAA==.',Nu='Nurga:BAAALAADCgUIBQAAAA==.',Oc='Oca:BAAALAADCgEIAQAAAA==.',Og='Ogier:BAAALAAECgEIAQAAAA==.',Ot='Otterpops:BAAALAADCgcIDQABLAAECgYICAABAAAAAA==.',Pa='Palpalpal:BAAALAADCggIFgABLAAECgQIBQABAAAAAA==.Papjekur:BAAALAADCgYIBgAAAA==.Patsy:BAAALAADCggIFgAAAA==.Patukavalar:BAAALAADCgUIBgAAAA==.Paulywag:BAAALAAECgYIDAAAAA==.Paulywog:BAAALAADCggIFQAAAA==.Paulywogg:BAAALAADCggIDgAAAA==.Paumenatin:BAAALAADCggICgAAAA==.Pawsed:BAAALAAECgYIDQAAAA==.Paûlywog:BAAALAADCgcIBwAAAA==.',Pe='Peri:BAAALAADCgMIBAAAAA==.Perleana:BAAALAAECgQICAAAAA==.Perra:BAAALAAECgYICgAAAA==.Petergriffon:BAAALAAECgIIAgAAAA==.',Ph='Philbertus:BAAALAAECggICAAAAA==.',Pi='Pickul:BAAALAADCgMIBAABLAADCgMIBQABAAAAAA==.',Po='Ponics:BAAALAADCgUICQAAAA==.',Pr='Preest:BAAALAADCgcIBwAAAA==.Profound:BAAALAADCgYIBgAAAA==.Propain:BAAALAADCgcIBwAAAA==.Protectormoo:BAAALAAECgUIBgAAAA==.',Ps='Psilocyb:BAAALAAECgMIBgAAAA==.',Pu='Puding:BAAALAAECgYIDAAAAA==.',Py='Pyixi:BAAALAAECgIIAgAAAA==.',['Pà']='Pàulywog:BAAALAADCgcICwAAAA==.',['Pá']='Páppajohn:BAAALAAECgMIAwAAAA==.',Qb='Qb:BAAALAAECgcIDQAAAA==.',Qu='Quelenna:BAAALAAECgIIAgAAAA==.Questorhunt:BAAALAAECgMIBAAAAA==.Quintus:BAAALAADCggIFQAAAA==.',Ra='Ragnariuss:BAAALAAECgQICQAAAA==.Raira:BAAALAAECgIIAgAAAA==.Ranarae:BAAALAADCgIIAgAAAA==.Raylith:BAAALAADCgQIBAAAAA==.',Re='Rebelangel:BAAALAADCgIIAgAAAA==.Reddaddy:BAAALAADCgIIAgAAAA==.Redvail:BAAALAAECgUIBgAAAA==.Rei:BAAALAADCgcIDQABLAAECgMIAwABAAAAAA==.Reivida:BAAALAAECgMIBgAAAA==.Rendokai:BAAALAAECgMIBQAAAA==.Renlaut:BAAALAADCgUIBgAAAA==.Renshaibob:BAAALAAECgcIAgAAAA==.Renzedar:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.Revohked:BAAALAADCgcIDQAAAA==.Rexius:BAAALAADCgcIEQAAAA==.Reyneza:BAAALAAECgYICQAAAA==.',Rh='Rhanale:BAAALAADCggICAAAAA==.Rhuudk:BAAALAAECgYIDAAAAA==.',Ri='Ridenpushon:BAAALAADCgcIBwABLAAECgYICAABAAAAAA==.',Ro='Rocchio:BAAALAAECgQICAAAAQ==.Rockcito:BAAALAADCgUIBQAAAA==.Rookie:BAAALAAECgYICAAAAA==.Row:BAAALAADCggICQAAAA==.Rowsi:BAAALAAECgQICAAAAA==.Roxene:BAAALAAECgIIAgAAAA==.Roykent:BAAALAAECgMIBAAAAA==.',Ru='Ruindreams:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Rumblestrut:BAAALAADCgYIBgAAAA==.',Sa='Sacrilege:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Sactostyle:BAAALAADCggIDwAAAA==.Saelron:BAAALAADCgYIBwAAAA==.Saelyraria:BAAALAAECgIIAgAAAA==.Saiti:BAAALAAECgcIDQAAAA==.Sakura:BAAALAAECgMIAwAAAA==.Sarao:BAAALAAECgYICgAAAA==.Sarathiel:BAAALAAECgMIBAAAAA==.Sarjun:BAAALAADCggIEwABLAAECgcIEQABAAAAAA==.Sarraih:BAAALAADCgUIBgAAAA==.Saruton:BAAALAADCgYIBwAAAA==.Sathandis:BAAALAADCgUIBQAAAA==.Satoru:BAAALAADCgQIBAAAAA==.',Sc='Schloadtm:BAAALAADCggICAABLAADCggIEAABAAAAAA==.Schmoogs:BAAALAAECgcICwAAAA==.Schtef:BAAALAADCgcIBwAAAA==.Schutzengel:BAAALAADCggICAAAAA==.Scoon:BAAALAAECgUIBgAAAA==.Scrotie:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Scuttlebug:BAAALAAECgYICwAAAA==.',Se='Sees:BAAALAADCggIDQAAAA==.Sekhmêt:BAAALAAECgIIAgAAAA==.Sendrais:BAAALAADCgUIBQAAAA==.Sennlilly:BAAALAADCgcIBwAAAA==.Sensistar:BAAALAAECgQIBQAAAA==.Sephen:BAAALAAECgMIAwAAAA==.Sermac:BAAALAADCgcICQAAAA==.',Sh='Shadowflay:BAAALAADCggIAgABLAAECgYICAABAAAAAA==.Shadöwlink:BAAALAADCggICAAAAA==.Shaelia:BAAALAADCgcIBwAAAA==.Shakama:BAAALAADCgUIBQAAAA==.Shallzappy:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.Shalzi:BAAALAADCggICAAAAA==.Shamcyn:BAAALAAECgQIBAAAAA==.Shamdwich:BAAALAADCgcIBwAAAA==.Shamuraijack:BAAALAAECgMIAwABLAAECgYICAABAAAAAA==.Shaokor:BAAALAADCgcICQAAAA==.Shardik:BAAALAADCgcICwAAAA==.Shepard:BAAALAAECgYICAABLAAECgYICAABAAAAAA==.Shmoogiebear:BAAALAADCggICgAAAA==.Shooth:BAAALAADCgEIAQAAAA==.Shámiko:BAAALAADCgEIAQAAAA==.',Si='Sickminded:BAAALAAECgcIDgAAAA==.Silvara:BAAALAAECgIIAgAAAA==.Silvernator:BAAALAAECgMIAwAAAA==.Simjazitime:BAABLAAECoEVAAIGAAcI0yDhCQCLAgAGAAcI0yDhCQCLAgAAAA==.',Sk='Skelaxin:BAAALAADCggIEQAAAA==.Skillhunter:BAAALAAECgYICAAAAA==.',Sl='Slippeddisc:BAAALAAECgEIAQAAAA==.',Sm='Smexyandikno:BAAALAAECgcIEwAAAA==.Smittey:BAAALAADCgQIBQAAAA==.',Sn='Sneakybora:BAAALAADCgcIEAAAAA==.Snooze:BAAALAAECgIIAgAAAA==.Snovirz:BAAALAAECgMIBgAAAA==.Snozzberry:BAAALAADCggICwAAAA==.Snykes:BAAALAAECgMIBAAAAA==.',So='Solendra:BAAALAAECgQICQAAAA==.Sookie:BAAALAAECgYICAAAAA==.',Sp='Spelltonjohn:BAAALAAECgEIAQABLAAECgQIBQABAAAAAA==.Spence:BAAALAAECgcIEwAAAA==.Spicyboyswag:BAAALAAECgMIAwABLAAECggIFQAHAHweAA==.Spikedtodeth:BAAALAADCgMIAwAAAA==.Splyce:BAAALAADCgEIAQABLAADCgMIBQABAAAAAA==.Splyne:BAAALAADCgEIAQAAAA==.Spyce:BAAALAADCgMIBQAAAA==.',St='Standinit:BAAALAAECgEIAQAAAA==.Stanlitwochi:BAAALAAECgYICwAAAA==.Starbourne:BAAALAAECgEIAQAAAA==.Starleaf:BAAALAAECgMIBgAAAA==.Starling:BAAALAAECgIIAgAAAA==.Starmie:BAAALAAECgMIBQAAAA==.Steelefang:BAAALAADCggIFQAAAA==.Stereotype:BAAALAADCgcIBwAAAA==.Sticky:BAAALAAECgQICQAAAA==.Stinkyy:BAAALAAECgEIAQAAAA==.Stonelock:BAAALAADCggICQAAAA==.Stormkitty:BAAALAAECgMIBgAAAA==.Streiter:BAAALAADCgcIDAAAAA==.',Su='Suljaer:BAAALAAECgMIBQAAAA==.Sunadrae:BAAALAADCgcIDAABLAAECgIIAwABAAAAAA==.Supersmol:BAAALAAECgcIDAAAAA==.',Sv='Svirfneblinn:BAAALAADCggICQAAAA==.',Sy='Sylas:BAAALAAECgMIAwAAAA==.Syllâbear:BAAALAAECgIIAgABLAAECgcIEQABAAAAAA==.Sylvaraea:BAAALAAECgEIAQAAAA==.Sylyndra:BAAALAAECgMIAwAAAA==.',Ta='Talastraza:BAAALAAECgMIAwAAAA==.Tanne:BAAALAADCggIEAAAAA==.Tardishunter:BAAALAAECgMIAwAAAA==.Tarrickm:BAAALAAECgQICAAAAA==.Tartarrus:BAAALAAECgYIBgAAAA==.Taterthots:BAAALAAECgcIBwAAAA==.Taulmäril:BAAALAAECgYIDQAAAA==.Tavariel:BAAALAAECgEIAQAAAA==.',Te='Teleri:BAAALAADCgMIAwAAAA==.Tellen:BAAALAAECgYIDgAAAA==.Tendisil:BAAALAADCgIIAgAAAA==.',Th='Thepurple:BAAALAADCgUIBQAAAA==.Thequae:BAAALAADCggIFQAAAA==.Thiccbranch:BAAALAAECgMIBAAAAA==.Thicsquatch:BAAALAAECgYIBgAAAA==.Thiicc:BAAALAAECgIIAgAAAA==.Thotlety:BAAALAAECgQICQAAAA==.Thrèsh:BAAALAAECgcIEAAAAA==.Thulad:BAAALAAECgUIBgAAAA==.Thymara:BAAALAAECgYICwAAAA==.',Ti='Tiamot:BAAALAADCggIEwAAAA==.Ticksndots:BAAALAAECgQIBwAAAA==.Tirinas:BAAALAAECgYIDAAAAA==.',To='Toastecute:BAAALAADCgcIBwAAAA==.Toastragosa:BAAALAADCggIDgAAAA==.Tobais:BAAALAAECgQICQAAAA==.Tombstone:BAAALAAECggIAwAAAA==.',Tr='Trafficcone:BAAALAADCgUIBQAAAA==.Treefrog:BAAALAADCgcIBwAAAA==.Trinkets:BAAALAADCggICQAAAA==.Trommash:BAAALAAECgEIAQAAAA==.Tropicalito:BAAALAADCgUIBQAAAA==.Trygrnordbru:BAAALAADCgYIBgAAAA==.Trîstan:BAAALAAECggIAwAAAA==.',Tu='Turnipssen:BAAALAAECgMIAwAAAA==.Turokuruvar:BAAALAAECgMIAwAAAA==.',Tw='Twinevil:BAAALAAECgIIAwAAAA==.',Tx='Txere:BAAALAAECgEIAQAAAA==.',Ty='Tynker:BAAALAAECgIIAgAAAA==.Tyronom:BAAALAAECgMICgAAAA==.',['Tú']='Túg:BAAALAAECgYIBgAAAA==.',Ug='Uglymugg:BAAALAADCggICAAAAA==.',Va='Valintha:BAAALAAECgQIBwAAAA==.Vanarian:BAAALAAECgcIDQAAAA==.Vandrae:BAAALAAECgEIAQAAAA==.',Ve='Velaania:BAAALAAECgMIAwAAAA==.Velrys:BAAALAAECgcIDgAAAA==.Velsaur:BAAALAADCggIDgAAAA==.Venblade:BAAALAADCgIIAgAAAA==.Vertaí:BAAALAAECgIIAgAAAA==.Veter:BAAALAAECgYICQAAAA==.Vetis:BAAALAAECgQICQAAAA==.Vexxon:BAAALAADCgMIAwAAAA==.',Vi='Vitavirent:BAAALAAECgUICAAAAA==.',Vo='Voidpera:BAAALAAECgUIBgAAAA==.',Vy='Vybzkartel:BAAALAADCgMIAwAAAA==.Vyrgaalis:BAAALAADCggIBwAAAA==.',Wa='Warkata:BAAALAAECgEIAQAAAA==.Waruned:BAAALAAECgQIBQAAAA==.Wasupnow:BAAALAAECgQICAAAAA==.',We='Wehweh:BAAALAADCgMIAwAAAA==.Wenadin:BAAALAAECgMIAwAAAA==.',Wh='Whorrifeye:BAAALAADCgcICAAAAA==.Whurstealth:BAAALAADCggICAAAAA==.',Wi='Wije:BAAALAAECgcIEAAAAA==.William:BAAALAAECgMIAwAAAA==.',Wo='Wolvedh:BAAALAADCgMIAwAAAA==.',Wr='Wraithstep:BAAALAAECgMIBAAAAA==.',Wu='Wumbology:BAAALAADCgQIBAABLAAECgYICAABAAAAAA==.',Wy='Wyrd:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.',Xh='Xhii:BAAALAAECgcIDgAAAA==.',Xu='Xuann:BAAALAAECgYIBgAAAA==.',Ye='Yendi:BAAALAAECgQIBwAAAA==.',Yn='Yngvar:BAAALAAECgYICgAAAA==.',Yo='You:BAAALAAECgIIAwAAAA==.',Yu='Yub:BAAALAAECgQICAAAAA==.Yumie:BAAALAADCgYIBgAAAA==.Yumië:BAAALAAECgEIAQAAAA==.',Za='Zallera:BAAALAADCgcIBwAAAA==.Zanetsu:BAAALAADCgUIAQAAAA==.Zarbustibal:BAAALAADCgcIBwAAAA==.Zariena:BAAALAADCgEIAQAAAA==.Zarknoth:BAAALAAECgMIAwAAAA==.Zayuh:BAAALAADCgcIEAAAAA==.Zaë:BAAALAAECgYIBgAAAA==.',Ze='Zedekiah:BAAALAADCgcIDAAAAA==.Zelmancha:BAAALAAECgQIBQAAAA==.Zenkichi:BAAALAADCgcIDAAAAA==.Zenyl:BAAALAADCgcIDQAAAA==.Zephyyra:BAAALAADCgcIBwAAAA==.Zethriel:BAAALAAECgMIAwAAAA==.',Zi='Zigby:BAAALAAECgMIAwAAAA==.Zilmage:BAAALAAECgQIBQAAAA==.',Zo='Zolidar:BAAALAAECggICAAAAA==.',Zy='Zythus:BAAALAADCgMIAwAAAA==.',['Öh']='Öhai:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end