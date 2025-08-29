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
 local lookup = {'Shaman-Enhancement','Shaman-Elemental','Unknown-Unknown','Mage-Arcane','Evoker-Devastation','Hunter-BeastMastery','Shaman-Restoration','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Priest-Holy',}; local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aanira:BAAALAAECgYICQAAAA==.Aaronsmyname:BAAALAAECgYIDAAAAA==.',Ab='Abigor:BAAALAADCgMIAwAAAA==.',Ad='Admore:BAAALAAECgMIBQAAAA==.Adämwest:BAAALAAECgUICAAAAA==.',Ae='Aeriith:BAAALAAECgYIDQAAAA==.',Ag='Agameden:BAAALAADCggIGAAAAA==.Agi:BAAALAAECgEIAQAAAA==.',Ai='Aileron:BAAALAADCgcICgAAAA==.',Ak='Akaya:BAAALAADCggICAAAAA==.Akevitt:BAAALAAECgMIAwAAAA==.',Al='Alissha:BAAALAADCgcICgAAAA==.Allestra:BAAALAAECgMIBwAAAA==.Altert:BAAALAAECgIIAQAAAA==.Alymere:BAAALAADCggIEQAAAA==.',Am='Amage:BAAALAAECgYICQAAAA==.Amalphia:BAAALAAECgEIAQAAAA==.Amoxil:BAAALAADCgEIAQAAAA==.',An='Anasztaizia:BAAALAADCgcIDQAAAA==.Angarock:BAAALAADCgUIBQAAAA==.Anobun:BAABLAAECoEcAAMBAAgIMCFTAQAEAwABAAgIMCFTAQAEAwACAAEI3BzFTABIAAAAAA==.Anorah:BAAALAADCgcIDQAAAA==.',Ar='Aranyssa:BAAALAAECgYIBwAAAA==.Arath:BAAALAAECgYIBwAAAA==.Arcona:BAAALAAECgEIAQAAAA==.Areocyle:BAAALAADCgcIBwAAAA==.Artiemesia:BAAALAADCggICAAAAA==.',As='Asar:BAAALAAECgIIAgAAAA==.Assumi:BAAALAAECgYICQAAAA==.Astora:BAAALAAECgYIBgAAAA==.',At='Athuzad:BAAALAAECgMIBAAAAA==.',Au='Auquroe:BAAALAADCggIDgAAAA==.Auroraalysia:BAAALAAECgMIBAAAAA==.Autumnmoon:BAAALAADCgYIBgAAAA==.',Ay='Ayeroh:BAAALAAECgEIAgAAAA==.Ayvangeline:BAAALAAECgEIAQAAAA==.',['Aí']='Aída:BAAALAADCgQIBAABLAADCggIDwADAAAAAA==.',Ba='Baggedmilk:BAABLAAECoEVAAIEAAgI3BYGGABQAgAEAAgI3BYGGABQAgAAAA==.Bakasaura:BAABLAAECoEVAAIFAAYIyCBTDQA4AgAFAAYIyCBTDQA4AgAAAA==.Balorous:BAAALAAECgMIBgAAAA==.Bansheetrack:BAAALAAECgYICwAAAA==.Banthis:BAAALAAECgEIAQAAAA==.Barkcamon:BAAALAADCggICAAAAA==.Barthelo:BAAALAAECgYICQAAAA==.Bathsheba:BAAALAAECgMIAwAAAA==.',Be='Bearnkdlady:BAAALAADCggIDQAAAA==.Beastboy:BAAALAADCgcIBwAAAA==.Bekahsama:BAAALAADCgcIDgAAAA==.Beldaran:BAAALAADCgcIDQAAAA==.Belladawna:BAAALAAECgYICQAAAA==.Belldândy:BAAALAADCgcIDAAAAA==.Bernal:BAAALAAECgEIAQAAAA==.',Bi='Bicepswar:BAAALAAECgUICAAAAA==.Bigëmu:BAAALAAECgEIAQAAAA==.Billyloomis:BAAALAADCgcIBwAAAA==.Bingbangpów:BAAALAAECgEIAQABLAAECgUICAADAAAAAA==.',Bl='Blarus:BAAALAAECgQIBwAAAA==.',Bo='Boherwin:BAAALAAECgQIBgAAAA==.Bonebreaker:BAAALAAECgYIBgAAAA==.Bontarest:BAAALAAECgYICQAAAA==.',Br='Brantus:BAAALAADCgUIAgAAAA==.Brillina:BAAALAAECgYICgAAAA==.Brisaea:BAAALAADCggICAAAAA==.Brugg:BAAALAAECgcIDwAAAA==.',Bu='Buddy:BAAALAADCgQIBQAAAA==.Bunnylajoya:BAAALAAECgUICgAAAA==.Busjacker:BAAALAAECgYIDAAAAA==.',['Bä']='Bäldur:BAAALAAECgYICQAAAA==.',Ca='Cainan:BAAALAADCgMIAwAAAA==.Calliah:BAAALAAECgIIAgAAAA==.Carmelita:BAAALAAECgMIBAAAAA==.Caroweaven:BAAALAADCggICgAAAA==.',Ce='Cecìl:BAAALAAECgQIBAAAAA==.Cecíl:BAAALAAECgEIAQAAAA==.Cedaver:BAAALAAECgUICAAAAA==.Cellphoneguy:BAAALAAECgYICQAAAA==.Celtigar:BAAALAADCggIFwAAAA==.',Ch='Chaan:BAAALAAECgIIAgAAAA==.Chamcham:BAAALAADCggIEAAAAA==.Cheddar:BAAALAADCggIDQAAAA==.Cheshire:BAAALAAECgQICQAAAA==.Chickenhunt:BAAALAAECgMIBAAAAA==.Chlorin:BAAALAAECgYIDAAAAA==.Chocolate:BAAALAAECgYIDwAAAA==.',Ci='Cindrozarke:BAAALAAECgYIBgAAAA==.Cirilla:BAAALAADCggICQAAAA==.',Cl='Clickbait:BAAALAADCggIFwAAAA==.Cloakthis:BAAALAADCgUIBQAAAA==.Cloudcrasher:BAAALAAECgYIDAAAAA==.Cloudspeaker:BAAALAADCgYIDAAAAA==.',Co='Coldsdeath:BAAALAADCgcIBwAAAA==.Coldslayer:BAAALAAECgYICQAAAA==.Coldsteeldx:BAAALAADCggICAAAAA==.Coradane:BAAALAAECgMIBAAAAA==.',Cr='Crackzap:BAAALAAECgYIDQAAAA==.Crakatowa:BAAALAADCggICQAAAA==.Crazyrd:BAAALAAECgYICwAAAA==.Crotgustus:BAAALAADCgIIAgABLAAECgIIAwADAAAAAA==.Crumblebump:BAAALAAECgEIAQAAAA==.Crummbly:BAAALAADCggIDgAAAA==.',Ct='Ctrlc:BAAALAAECgMIAwAAAA==.',Cy='Cybergax:BAAALAADCgcIDQAAAA==.Cyntaria:BAAALAAECgMIBAAAAA==.',['Cü']='Cüpcake:BAAALAAECgYICQAAAA==.',Da='Daienne:BAAALAAECgYICgAAAA==.Dalari:BAAALAADCgcIBwAAAA==.Danamor:BAAALAAECgYIBgAAAA==.Danoasis:BAAALAADCgcICwAAAA==.Daqueenn:BAAALAAECgYIBgAAAA==.Darkblooded:BAAALAADCgQIBAAAAA==.Darnel:BAAALAAECgYICQAAAA==.Darnokk:BAAALAAECgEIAQAAAA==.Darro:BAAALAADCgMIAwAAAA==.Darthdarkco:BAAALAADCgEIAQAAAA==.Darthvenom:BAAALAADCggIHgAAAA==.Dax:BAAALAAECggIAwAAAA==.',De='Deathbymagic:BAAALAAECgUIBQAAAA==.Deathgouki:BAAALAAECgMIBwAAAA==.Deathstrokee:BAAALAADCgcIBwAAAA==.Deathylad:BAAALAAECgQIBAAAAA==.Demogirl:BAAALAADCgcIEAAAAA==.Demongotha:BAAALAADCgcIBwAAAA==.Demonico:BAAALAADCgUIBgAAAA==.Demonstryker:BAAALAADCgcIBwAAAA==.Deschain:BAAALAAECgMIBAAAAA==.Destartè:BAAALAADCggIBAAAAA==.Dewert:BAAALAADCggIEAAAAA==.Dexerson:BAAALAADCgcICgAAAA==.',Di='Diin:BAAALAAECgMIAwAAAA==.',Dr='Dracorex:BAAALAAECgEIAQAAAA==.Dracoul:BAAALAADCggIDgAAAA==.Dredd:BAAALAAECgEIAgAAAA==.Drougoss:BAAALAADCgcIBwAAAA==.Drunk:BAAALAAECgIIAgABLAAECgUICQADAAAAAA==.',Ds='Dsypha:BAAALAAECgIIAgAAAA==.',Du='Dude:BAAALAADCgYIBgAAAA==.',Ec='Eckshin:BAAALAADCgcIBwAAAA==.',Eg='Eggnorant:BAAALAAECgYICgAAAA==.',Ek='Ekkaia:BAAALAAECgYICwAAAA==.',El='Elephant:BAAALAAECggIDAABLAAFFAMIAwADAAAAAA==.Elluuna:BAAALAADCgcIBwAAAA==.Elpeluca:BAAALAADCgEIAQAAAA==.Elryn:BAAALAAECgMIBAAAAA==.',En='Encana:BAAALAAECgQICQAAAA==.Ender:BAAALAAECgMIBAAAAA==.',Er='Erada:BAAALAAECgEIAQAAAA==.Ericgb:BAAALAAECgYICQAAAA==.Errowz:BAAALAADCggIDwAAAA==.Errzza:BAAALAAECgEIAQAAAA==.Erutreya:BAAALAAECgIIAgAAAA==.',Ev='Evokesoul:BAAALAADCggICAAAAA==.',Ex='Execrate:BAAALAADCgcIDQAAAA==.Expron:BAAALAAECgIIAgAAAA==.Exqui:BAAALAAECgYICgAAAA==.Exøz:BAAALAAECgMIAwAAAA==.',Ez='Ezmerelda:BAAALAAECgMIBAAAAA==.Ezral:BAAALAADCggIDwABLAAECgYIBgADAAAAAA==.Ezrascarlets:BAAALAAECgIIAgAAAA==.Ezzra:BAAALAADCgcIBwAAAA==.',Fa='Fadedhope:BAAALAADCgcIDAABLAAECgMIBAADAAAAAA==.Fafnar:BAAALAADCgcIBwABLAAECgYICQADAAAAAA==.Fafnie:BAAALAAECgYICQAAAA==.',Fe='Felath:BAAALAAECgMIBwAAAA==.Feldspar:BAAALAAECgMIBwAAAA==.Ferallos:BAAALAADCggICwAAAA==.',Fi='Fil:BAAALAAECgMIBAAAAA==.Filcandy:BAAALAADCgQIBAAAAA==.Finalhealing:BAAALAAECgIIAgAAAA==.Finalkill:BAAALAAECgMIBAAAAA==.Firalas:BAAALAADCgcIBwAAAA==.Fireblood:BAAALAAECgMIBAAAAA==.Firelungs:BAAALAADCgcIBwAAAA==.Fishswife:BAAALAAECgEIAQAAAA==.Fistoflurry:BAAALAADCggIDQAAAA==.',Fj='Fjedaykin:BAAALAADCgcICwAAAA==.',Fl='Flemel:BAAALAAECgMIBAAAAA==.Flyingrat:BAAALAAECgEIAgAAAA==.',Fo='Footoo:BAAALAAECgEIAQAAAA==.Forestsong:BAAALAADCgQIBAABLAADCggIFwADAAAAAA==.',Fr='Franksuba:BAAALAAECgUICQAAAA==.Fringilla:BAAALAADCgYICwAAAA==.Frostmove:BAAALAADCgYIDgAAAA==.',Ga='Galiophobia:BAAALAAECgMIBAAAAA==.Gaman:BAAALAADCgQIBAAAAA==.Gawleywood:BAAALAAECgEIAQAAAA==.',Ge='Geethatlock:BAAALAADCgcIBwAAAA==.Gellidus:BAAALAAECgYICgAAAA==.Genatren:BAAALAADCgMIAwAAAA==.',Gh='Ghosteagle:BAAALAADCgcIBwAAAA==.',Gl='Glasse:BAAALAAECgMIAwAAAA==.',Gn='Gnomejodas:BAAALAAECgMIBAAAAA==.',Go='Gobfather:BAAALAAECgEIAQAAAA==.Goodfaith:BAAALAADCggIFAAAAA==.',Gr='Grenelli:BAAALAADCgUIBQAAAA==.Grimlocke:BAAALAAECgIIAgABLAAECgMIAwADAAAAAA==.Grimsolo:BAAALAAECgMIAwAAAA==.Grimtale:BAAALAADCgcIBwABLAAECgMIAwADAAAAAA==.',Gu='Gullibull:BAAALAAECgQIBwAAAA==.',Gw='Gwynne:BAAALAAECgUIBgAAAA==.',Ha='Hadoxx:BAAALAADCgcICwAAAA==.Halanad:BAAALAADCgcIDQAAAA==.Haldrada:BAAALAADCgcICQAAAA==.Halfsumo:BAAALAAECgMIBQAAAA==.Hamer:BAAALAAECgIIAgAAAA==.Haraad:BAAALAADCgQIBAAAAA==.Hassindiir:BAAALAAECgYIDAAAAA==.Hawmahcide:BAAALAADCgcIBwAAAA==.Hayles:BAAALAAECgEIAQAAAA==.',He='Hecklerkoch:BAAALAAECgYICQAAAA==.Heinrych:BAAALAADCgcIBwAAAA==.Herbalife:BAAALAAECgYICAAAAA==.Herevoker:BAABLAAECoEVAAIFAAgIeRsyCQCKAgAFAAgIeRsyCQCKAgAAAA==.Herhunter:BAAALAAECgUIBgABLAAECggIFQAFAHkbAA==.',Hi='Hildia:BAAALAADCgQIBAAAAA==.Hippochi:BAAALAADCgcIBwAAAA==.Hishunter:BAABLAAECoEWAAIGAAgIJx+aCQDHAgAGAAgIJx+aCQDHAgAAAA==.Hiswarrior:BAAALAADCggIDwABLAAECggIFgAGACcfAA==.',Ho='Holyhawg:BAAALAAECgMIAwAAAA==.Hotcakes:BAAALAAECgIIAwAAAA==.',Hr='Hräfn:BAAALAAECgQICQAAAA==.',Hu='Humansnipr:BAAALAAECgEIAgAAAA==.Huntarr:BAAALAAECgYICwAAAA==.Hunterdamon:BAAALAAECgYICwAAAA==.',['Hà']='Hàou:BAAALAADCgcIBwAAAA==.',Ia='Iamafish:BAAALAAECgMIBwAAAA==.Iandis:BAAALAADCgEIAQAAAA==.',Ic='Iceez:BAAALAADCggIFwAAAA==.',Ig='Igotyoubro:BAAALAADCggIDgAAAA==.',Il='Ilidanick:BAAALAAECgIIAgAAAA==.',Im='Imahunter:BAAALAAECgMIBAAAAA==.Imayhealumab:BAAALAAECgEIAQAAAA==.',In='Insidae:BAAALAAECgQICQAAAA==.',Ir='Ironfist:BAAALAAECgMIAwAAAA==.',Is='Isakoa:BAAALAAECgEIAQAAAA==.Iscreamloud:BAAALAAECgEIAgAAAA==.Ismirea:BAAALAADCggIFAAAAA==.Isïldur:BAAALAAECgEIAQABLAAECggIGAAHAEIlAA==.',It='Itsaju:BAAALAADCgQIBgAAAA==.',Ja='Jalencarter:BAAALAAECgcIEgAAAA==.Jam:BAAALAADCgcIBwAAAA==.Jamez:BAAALAADCggICAAAAA==.Jantasir:BAAALAAECgEIAQAAAA==.Jarvian:BAAALAADCgcIDgAAAA==.Jasemage:BAAALAAECgEIAQAAAA==.Jashnah:BAAALAAECgEIAQAAAA==.Javalyn:BAAALAAECgEIAQAAAA==.Jayse:BAAALAADCggIFwAAAA==.',Je='Jerbo:BAAALAADCggIFQAAAA==.Jerr:BAAALAAECgMIBQAAAA==.',Ji='Jirachi:BAAALAAFFAIIAgABLAAFFAMIBwAIADsOAA==.',Jo='Jobi:BAAALAAECgYICQAAAA==.Johallas:BAAALAAECgYICwAAAA==.Jonnsnow:BAAALAADCgMIBgAAAA==.',Ju='Juf:BAAALAAECgYICQAAAA==.Julio:BAAALAADCgYIBQAAAA==.',Ka='Kaho:BAAALAAECgYIBgAAAA==.Kalda:BAAALAAECgcICAAAAA==.Kallisto:BAAALAAECgMIBQAAAA==.Karraklazic:BAAALAADCggICQABLAAECgYIDQADAAAAAA==.Kayce:BAAALAAECgYICwAAAA==.Kazu:BAAALAAECgEIAQAAAA==.Kazuhiro:BAAALAADCggIFQAAAA==.',Ke='Keagan:BAAALAADCggIFwAAAA==.Keevah:BAAALAAECgQIBgAAAA==.Kenania:BAAALAAECgIIAgAAAA==.',Kh='Khaluha:BAAALAADCggIDwAAAA==.',Kr='Krisphobos:BAAALAAECgEIAQAAAA==.',Kt='Ktrevious:BAAALAAECgEIAQAAAA==.',Ku='Kubael:BAAALAAECgYIBgAAAA==.Kulgutbuster:BAAALAAECgYICwAAAA==.Kungpow:BAAALAAECgYICgAAAA==.Kuromatsu:BAAALAAECgYICQAAAA==.Kurtrus:BAAALAADCgMIAwAAAA==.',Kw='Kwonshukilla:BAAALAADCgcIBwAAAA==.',['Kì']='Kìngpin:BAAALAAECgMIBQAAAA==.',['Kÿ']='Kÿt:BAAALAAECgMIBAAAAA==.',La='Labarta:BAAALAADCgIIAgAAAA==.Labubu:BAAALAAECgEIAQAAAA==.Lacedon:BAAALAAECgIIAgAAAA==.Lanolin:BAAALAADCggIDgAAAA==.Larfleeze:BAAALAADCgYIBgAAAA==.Laultar:BAAALAADCgEIAQABLAAECgIIAwADAAAAAA==.Lauressa:BAAALAAECgQIBAAAAA==.Lauriena:BAAALAAECgYICAAAAA==.',Le='Lethaldx:BAAALAADCgcICQAAAA==.',Li='Lightaverice:BAAALAADCgcIDgAAAA==.Lightforge:BAAALAADCgcIBwAAAA==.Lilitha:BAAALAADCgYIBgAAAA==.Lilliean:BAAALAAECgMIAwABLAAECgYIBgADAAAAAA==.Linedaleiris:BAAALAADCgcIBwAAAA==.Lishan:BAAALAAECgYIDQAAAA==.Lizora:BAAALAAECgcIEAAAAA==.',Lo='Lock:BAAALAADCggIDAAAAA==.Lohuu:BAAALAADCggIDgAAAA==.Lowalwala:BAAALAAECgQIBgAAAA==.',Lu='Lucìd:BAAALAAECgMIBgAAAA==.Lucíd:BAAALAADCgIIAgAAAA==.Luforia:BAAALAAECgIIAgAAAA==.Lunareia:BAAALAAECgYIBgAAAA==.Lunhzae:BAAALAAECgcIDwAAAA==.',Ma='Mack:BAAALAAECggICgAAAA==.Madrina:BAAALAADCgcIDgAAAA==.Magdar:BAAALAADCgcICgAAAA==.Maggor:BAAALAAECgMIAwAAAA==.Magicwithin:BAAALAAECgYIBgAAAQ==.Magut:BAAALAADCgMIAwAAAA==.Maim:BAAALAADCgcICgAAAA==.Malevolens:BAAALAAECgMIBAAAAA==.Malkinish:BAAALAADCgcIBwABLAAECgYICwADAAAAAA==.Mancant:BAAALAADCggIDAAAAA==.Mandilyn:BAAALAADCgcICgAAAA==.Maraella:BAAALAADCgEIAQAAAA==.Marche:BAAALAAECgYICwAAAA==.Mavanahlia:BAAALAADCgcIBwAAAA==.Mavar:BAAALAAECgYIBgAAAA==.',Me='Megladoon:BAAALAADCgcICAAAAA==.Meno:BAAALAADCgcIBwAAAA==.Menoscales:BAAALAAECgIIAgAAAA==.Meowzors:BAAALAADCggICAAAAA==.Mephïsto:BAAALAAECgUICAAAAA==.Merenil:BAAALAAECgUICAAAAA==.Messdupllama:BAAALAAECgYICwAAAA==.',Mi='Microburst:BAAALAADCgYIBgABLAAECgYICQADAAAAAA==.Microcharge:BAAALAAECgYICQAAAA==.Millene:BAAALAADCgcICAAAAA==.Mincarius:BAAALAAECgYICwAAAA==.Minerdari:BAAALAADCgcIBwAAAA==.Misosoup:BAAALAAECgMIAwAAAA==.',Mo='Mongargiss:BAAALAAECgEIAgAAAA==.Monkingold:BAAALAADCggICgAAAA==.Monolath:BAAALAADCgcICwAAAA==.Monoslam:BAAALAADCggIFwAAAA==.Montaro:BAAALAAECgEIAQAAAA==.Mooncrash:BAAALAAECgMIBAAAAA==.Morbidi:BAAALAAECgEIAgAAAA==.Morrigun:BAAALAADCgcIBwAAAA==.',Mu='Munnsta:BAAALAADCgIIAgAAAA==.Muskan:BAAALAAECgMIBAAAAA==.',My='Mysticah:BAAALAAECgEIAQAAAA==.Mytharissa:BAAALAADCggICAAAAA==.',Na='Naffer:BAABLAAECoEYAAMJAAgIoR6ECACjAgAJAAgIVB6ECACjAgAKAAYInRV2BwCNAQAAAA==.Nanr:BAAALAAECgYICgAAAA==.Nathi:BAAALAADCgcIDQAAAA==.Nazeera:BAAALAADCgcICgABLAADCgcIDQADAAAAAA==.',Ne='Necrokinesis:BAAALAADCgQIBAAAAA==.Nee:BAAALAADCgcIBwAAAA==.Neshalel:BAAALAADCggIEgAAAA==.Nezax:BAAALAADCggIDgAAAA==.',Ni='Nikash:BAAALAADCgUIBQAAAA==.Nillawaffer:BAAALAADCgcIBwABLAAECgYICwADAAAAAA==.',No='Noheroclass:BAAALAADCggICAAAAA==.Novacat:BAAALAAFFAEIAQAAAA==.November:BAAALAAECgIIAgAAAA==.',Nu='Nubriss:BAAALAAECgMIBwAAAA==.Nuitsguard:BAAALAAECgMIBwAAAA==.Nukeithard:BAAALAADCgcIBwAAAA==.',Ny='Nyssavia:BAAALAADCgYIBgAAAA==.',['Nè']='Nèaner:BAAALAAECgYIDAAAAA==.',['Nê']='Nêbelim:BAAALAADCgMIAwAAAA==.',['Nø']='Nøwa:BAAALAADCgEIAQAAAA==.',Oi='Oiheg:BAAALAAECgYICwAAAA==.',Or='Orjchi:BAAALAADCgcIBwAAAA==.Oronin:BAAALAADCggICAABLAAECggIHgALAP4jAA==.Orynn:BAAALAADCgcIDgAAAA==.',Os='Osmodeus:BAAALAADCgIIAgAAAA==.',Ov='Ovrcompnsate:BAAALAADCgEIAQAAAA==.',Ow='Owt:BAAALAAECgIIAgAAAA==.',Pa='Paneer:BAAALAAECgMIAwAAAA==.',Pe='Percent:BAAALAAECgYIDAAAAA==.',Ph='Phobe:BAAALAAECgEIAQABLAAECgMIBgADAAAAAA==.Photos:BAAALAAECgYICQAAAA==.',Pi='Pigums:BAAALAAECgYICwAAAA==.Pils:BAAALAADCggICAABLAAECgIIAgADAAAAAA==.Pinknbubbly:BAAALAADCgcICwAAAA==.',Po='Poceidon:BAAALAADCgEIAQAAAA==.Potaje:BAAALAADCgQIBAAAAA==.',Pr='Proatheris:BAAALAAECgYIDAAAAA==.Procellaria:BAAALAAECgYIBwABLAAECgYIDAADAAAAAA==.Proioxis:BAAALAAECgYICAABLAAECgYIDAADAAAAAA==.Proteales:BAAALAADCgcIBgABLAAECgYIDAADAAAAAA==.Prîde:BAAALAADCgcIDAAAAA==.',Ps='Psysmash:BAAALAADCgcIDgABLAAECgYICQADAAAAAA==.',Pu='Puddingfarts:BAAALAADCggIEwAAAA==.Purrpally:BAAALAADCggIEAAAAA==.',Py='Pyroclàstic:BAAALAADCgIIAgABLAAECgMIBAADAAAAAA==.Pywacket:BAAALAAECgIIAgAAAA==.',Qu='Quende:BAABLAAECoEYAAIHAAgIQiXFAABGAwAHAAgIQiXFAABGAwAAAA==.Quendia:BAAALAAECgIIAgABLAAECggIGAAHAEIlAA==.Quick:BAAALAADCggIDQAAAA==.',Ra='Racingdude:BAAALAADCggIDAAAAA==.Rahye:BAAALAADCggICAAAAA==.Ratava:BAAALAADCgcIFQAAAA==.Rathaan:BAAALAAECgYICwAAAA==.',Re='Refil:BAAALAAECgMIAwAAAA==.Rekien:BAAALAADCggICAAAAA==.Relador:BAAALAAECgcIDAAAAA==.Relena:BAAALAADCggIEwABLAADCgUIBQADAAAAAA==.Renshi:BAAALAADCgcIBwAAAA==.Rettyruxpin:BAAALAAECgIIAgAAAA==.Revo:BAAALAAECgMIBQAAAA==.Revolution:BAAALAADCgcIBwAAAA==.',Ri='Rikaza:BAAALAAECgMIBQAAAA==.Riot:BAAALAAECgMIBgAAAA==.',Ro='Rognar:BAAALAAECgMIAwAAAA==.Rosefang:BAAALAADCgcIBwAAAA==.Roupert:BAAALAAECgMIAwAAAA==.Rozzluz:BAAALAAECgIIAgAAAA==.',Ru='Rutira:BAAALAAECgYICwAAAA==.',Ry='Ryasha:BAAALAADCgcIBwAAAA==.Ryân:BAAALAAECgYIBgAAAA==.',Sa='Saladhealer:BAAALAAECgEIAQABLAAECgMIAwADAAAAAA==.Sanin:BAAALAAECgQIBgAAAA==.Sardaukar:BAAALAADCggIEwAAAA==.Saula:BAAALAAECgMIBAABLAAECgYIDQADAAAAAA==.',Sc='Scarleth:BAAALAADCgEIAQAAAA==.',Se='Seacow:BAAALAADCgIIAgAAAA==.Searilus:BAAALAAECgEIAQAAAA==.Seifus:BAAALAADCgcICgAAAA==.Selinnaria:BAAALAADCgEIAQAAAA==.',Sh='Shamak:BAAALAADCggICwAAAA==.Shamdaddy:BAAALAAECgYIDwAAAA==.Shammoos:BAAALAADCggICAAAAA==.Shamæn:BAAALAAECgEIAQAAAA==.Shieldon:BAAALAADCgUIBQABLAAECgYICQADAAAAAA==.Shikamarú:BAAALAADCggICAAAAA==.Shinhealer:BAAALAADCggICgAAAA==.Shåmpon:BAAALAAECgcIEwAAAA==.',Si='Sillyduck:BAAALAAECgMIAwAAAA==.Silvernleaf:BAAALAAECgMIBAAAAA==.Simarie:BAAALAADCggIDAAAAA==.Simbaa:BAAALAAECgMIAwAAAA==.Sinai:BAAALAAECgUICAAAAA==.Sion:BAAALAADCggIDwAAAA==.Sirlancer:BAAALAAECgQICAAAAA==.',Sk='Skua:BAAALAADCgQIBAAAAA==.',Sl='Slashertursh:BAAALAADCgYIBgAAAA==.Slayurprayer:BAAALAADCgUICQAAAA==.Sleêp:BAAALAADCgcIDQAAAA==.Slosh:BAAALAAECgIIAgAAAA==.',Sm='Smerffy:BAAALAAECgMIBAAAAA==.',Sn='Snaptrap:BAAALAAECgYICwAAAA==.',So='Solder:BAAALAADCgcIBwAAAA==.Solthera:BAAALAADCgcIBwAAAA==.Sonny:BAAALAAECgUIBwAAAA==.Sorena:BAAALAAECgIIAgAAAA==.Sorstraza:BAAALAADCgcIBwAAAA==.Soulhorror:BAAALAAECgUICQAAAA==.',Sp='Spicytuna:BAAALAAECgIIAwAAAA==.Spriggs:BAAALAAECgMIBgAAAA==.',Sq='Squareruut:BAAALAADCggICAAAAA==.Squirt:BAAALAAECgMIAwAAAA==.',St='Stenney:BAAALAADCgUIBQAAAA==.Stonedread:BAAALAAECgMIBAAAAA==.',Su='Subvert:BAAALAAECgIIAgAAAA==.Sullyboy:BAAALAAECgEIAQABLAAECgYIDwADAAAAAA==.Sumobush:BAAALAAECgYIDAAAAA==.Sunaerilitha:BAAALAAECgYIDQAAAA==.Sunarii:BAAALAAECgIIAgAAAA==.Sungmi:BAAALAAECgYICQAAAA==.',Sw='Swizle:BAAALAAECgMIBAAAAA==.',Sy='Syber:BAAALAAECgYICAAAAA==.Syllara:BAAALAADCgcIDgABLAAECgYICQADAAAAAA==.Symphonica:BAAALAAECgMIBQAAAA==.Synclaer:BAAALAADCgYIBgABLAADCggIFwADAAAAAA==.Synthesize:BAAALAADCgQIBAAAAA==.',['Sæ']='Sæc:BAAALAADCgEIAQAAAA==.',Ta='Tacticalshot:BAAALAAECgcIBwAAAA==.Taravangian:BAAALAAECgIIAgAAAA==.Tarò:BAAALAAECgYIDAAAAA==.',Te='Technomancer:BAAALAADCgcIDQAAAA==.Tehtree:BAAALAADCggIDgAAAA==.Teldon:BAAALAAECgMIBQAAAA==.Telvissra:BAAALAADCggIEAAAAA==.',Th='Thecure:BAAALAADCggICAAAAA==.Themonks:BAAALAAECgcIDAAAAA==.Thetamoon:BAAALAAECgYICQAAAA==.Thewitcher:BAAALAADCgYIBgAAAA==.Thorggon:BAAALAAECgMIBwAAAA==.Thornmane:BAAALAAECgMIAwAAAA==.Thrybz:BAAALAADCgcIBwAAAA==.',Ti='Tiki:BAAALAADCgYIBgAAAA==.Tiktikboom:BAAALAADCgUICQAAAA==.',To='Toxique:BAAALAAECgMIBAAAAA==.',Tr='Travelocitee:BAAALAADCgcIDgAAAA==.Tresor:BAAALAADCgYIBwAAAA==.Trollintreat:BAAALAAECgUICQAAAA==.Trustissues:BAAALAAECgIIAwAAAA==.Try:BAACLAAFFIEFAAICAAQIAhNbAQBbAQACAAQIAhNbAQBbAQAsAAQKgRgAAwIACAhMJYQCAE4DAAIACAhMJYQCAE4DAAEACAiGH8IEAC8CAAAA.Trybu:BAAALAAECgcICwAAAA==.Tryiss:BAAALAAECgMIAwAAAA==.',Tt='Ttryss:BAAALAADCgUIBQAAAA==.',Tu='Turtlelord:BAAALAAECgUIBQAAAA==.Turukmakto:BAAALAADCgEIAQAAAA==.',Ty='Tylendal:BAAALAAECgEIAQAAAA==.Tyrlizard:BAAALAAECgYICgAAAA==.',Ub='Ubeillin:BAAALAAECgEIAgAAAA==.',Um='Umaga:BAAALAADCggICAAAAA==.',Un='Unfleshed:BAAALAAECgYICgAAAA==.Unfàthømable:BAAALAAECgMIBAAAAA==.',Va='Vallith:BAAALAADCgcIBwAAAA==.Valtaran:BAAALAADCggIFwAAAA==.Valtarr:BAAALAAECgYICQAAAA==.Vanadis:BAAALAADCgMIAgAAAA==.Vannes:BAAALAADCgQIAwAAAA==.Varcius:BAAALAAECgEIAgAAAA==.Vardä:BAAALAAECgQIBAAAAA==.Vaylri:BAAALAAECgYIBgAAAA==.',Ve='Vehemently:BAAALAAECgcIBwAAAA==.Veloril:BAAALAADCgcIBwAAAA==.Velynn:BAAALAADCgcIDQAAAA==.Vespidae:BAAALAADCggICgAAAA==.Vexka:BAAALAADCgcIBwAAAA==.',Vi='Vidu:BAAALAAECgYICQAAAA==.Vivienna:BAAALAADCgQIBAAAAA==.Vivitrix:BAAALAADCgYIBgAAAA==.Vivitryxia:BAAALAADCggIFwAAAA==.',Vo='Vokan:BAAALAADCgcIBwAAAA==.',Vu='Vulchan:BAAALAADCgYIBgABLAAECgMIBQADAAAAAA==.Vulchpanson:BAAALAAECgMIBQAAAA==.',Vv='Vv:BAAALAAECgMIBQAAAA==.',Wa='Wargisao:BAAALAAECgYIDAAAAA==.Warkraft:BAAALAAECgIIAgAAAA==.',We='Weavile:BAACLAAFFIEHAAIIAAMIOw4pAgDyAAAIAAMIOw4pAgDyAAAsAAQKgRoAAggACAjkGyEEALACAAgACAjkGyEEALACAAAA.Wef:BAAALAADCggIFgAAAA==.Weirdtotem:BAAALAAECgMIAwAAAA==.Wenwin:BAAALAAECgEIAQAAAA==.Westylad:BAAALAAECgIIAgAAAA==.',Wh='Whartonius:BAAALAAECgIIAwAAAA==.Whatthefunk:BAAALAADCgYIBgAAAA==.',Wi='Willemdabow:BAAALAADCggIFwAAAA==.Wimbodk:BAAALAADCggIFwAAAA==.Wimboheotii:BAAALAADCgQIBAABLAADCggIFwADAAAAAA==.Wimbowar:BAAALAADCgYIBgABLAADCggIFwADAAAAAA==.Windlle:BAAALAAECgMIBAAAAA==.',Wo='Wolfylad:BAAALAADCggICAAAAA==.',Wy='Wyomarus:BAAALAADCgcIBwAAAA==.',Xa='Xalatari:BAAALAADCgcIBwABLAAECgYICwADAAAAAA==.',Ya='Yahima:BAAALAAECgMIBQAAAA==.',Yu='Yuma:BAAALAADCgcIBwAAAA==.',['Yë']='Yëët:BAAALAAECgcIDQAAAA==.',Za='Zachisdead:BAAALAADCggICAAAAA==.Zachspitfire:BAAALAADCgIIAgABLAADCggICAADAAAAAA==.Zakma:BAABLAAECoEeAAILAAgI/iN3AgAgAwALAAgI/iN3AgAgAwAAAA==.Zalee:BAAALAAECgMIAwAAAA==.Zalen:BAAALAAECgYICwAAAA==.Zaxx:BAAALAADCgYIBgAAAA==.',Zh='Zhihao:BAAALAAECgEIAQAAAA==.',Zo='Zonkmachine:BAAALAADCgMIAwAAAA==.Zonksdruid:BAAALAADCgIIAgAAAA==.Zonksmoose:BAAALAAECgMIAwAAAA==.Zonkspaladin:BAAALAAECgYIBwAAAA==.Zonkspriest:BAAALAADCggICAAAAA==.',Zp='Zpyder:BAAALAADCgcIBwAAAA==.',Zy='Zynskie:BAAALAAECgEIAQAAAA==.',['ße']='ßerlain:BAAALAADCgcIDQAAAA==.',['ßr']='ßris:BAAALAAECgQICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end