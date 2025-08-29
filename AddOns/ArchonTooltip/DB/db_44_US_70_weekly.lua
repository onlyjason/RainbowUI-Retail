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
 local lookup = {'Unknown-Unknown','Druid-Balance',}; local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Aderoth:BAAALAADCgcIBwAAAA==.Adovada:BAAALAAECgYIDAAAAA==.',Ae='Aesthelian:BAAALAAECgEIAQAAAA==.Aesthelyan:BAAALAAECgIIAwAAAA==.',Ag='Agnia:BAAALAAECgEIAQAAAA==.',Ah='Ahnerfays:BAAALAADCgYICwABLAADCggIFAABAAAAAA==.',Ai='Aintnorest:BAAALAAECgEIAQAAAA==.Aitra:BAAALAAECgMIBQAAAA==.',Al='Aldo:BAAALAAECggICAAAAA==.Alerothon:BAAALAAECgcIDwAAAA==.Alestiana:BAAALAAECgQIBQAAAA==.Aletalayllia:BAAALAADCgIIAgABLAADCgYICAABAAAAAA==.Alumidragon:BAAALAADCgIIBAAAAA==.Alumiedgy:BAAALAAECggIBAAAAA==.Alumina:BAAALAADCgQIBQAAAA==.Alveia:BAAALAAECgMIAwABLAAECgUIBgABAAAAAA==.Alycya:BAAALAADCgYIBgAAAA==.',Am='Amathios:BAAALAADCgcICgAAAA==.',An='Annati:BAAALAAECgYIDgAAAA==.',Ao='Aoba:BAAALAAECgYIBwAAAA==.',Ap='Apila:BAAALAAECgMIAwABLAAECgMIAwABAAAAAQ==.Apochryfel:BAAALAAECgMIBQAAAA==.Apox:BAAALAAECgMIBQAAAA==.',Ar='Arasha:BAAALAAECgMICAAAAA==.Arcaneisbad:BAAALAADCggIFAAAAA==.Areaman:BAAALAADCgYIBgAAAA==.Arlyn:BAAALAAECgUIBgAAAA==.Arrok:BAAALAAECgQIBwAAAA==.Artagan:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.Artemisixion:BAAALAAECgIIAgAAAA==.Artemisrolls:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Arthillius:BAAALAADCggIDAAAAA==.',As='Asheyari:BAAALAAECgIIAgAAAA==.Asmodias:BAAALAAECgEIAQAAAA==.',Au='Aurica:BAAALAAECgEIAQAAAA==.',Ba='Baalút:BAAALAADCggICAAAAA==.Ballasor:BAAALAADCggICAAAAA==.Ballinwar:BAAALAAECgcICwAAAA==.Basement:BAAALAADCggIDAAAAA==.Bashanu:BAAALAAECgQIBwABLAAECgEIAQABAAAAAA==.',Be='Beefñcheddar:BAAALAAECgcIDgAAAA==.Beernuts:BAAALAAECgEIAQAAAA==.Bestdpsspec:BAAALAADCgcICwABLAADCggIFAABAAAAAA==.',Bh='Bhalimar:BAAALAADCggIFQAAAA==.',Bi='Bigradish:BAAALAADCgcIBQAAAA==.Billywham:BAAALAADCggIDwAAAA==.Bip:BAAALAAECgcIDAAAAA==.',Bl='Blazingfist:BAAALAADCgMIAgAAAA==.Blehpaladin:BAAALAADCgUIBQAAAA==.',Bo='Boomchickenz:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.',Br='Bramick:BAAALAAECgEIAQAAAA==.Brianstorm:BAAALAAECgUIBgAAAA==.Bristleblowi:BAAALAAECgIIAgAAAA==.Bronkowitz:BAAALAAECgEIAQAAAA==.Brrk:BAAALAADCggICAAAAA==.',Bu='Burnie:BAAALAAECgEIAQAAAA==.',Ca='Caeke:BAAALAADCggICAAAAA==.Canarri:BAAALAADCgYIBgAAAA==.Carion:BAAALAAECgYICQAAAA==.',Ce='Ceirah:BAAALAAECgEIAQAAAA==.Celaris:BAAALAADCgUIAQAAAA==.Celestiné:BAAALAADCgcIBwAAAA==.',Ch='Chaingun:BAAALAAECgIIAgAAAA==.Chilblain:BAAALAAECgEIAQAAAA==.Chillbane:BAAALAAECgEIAQAAAA==.Choicecut:BAAALAAECgYICQABLAAECgcIDwABAAAAAA==.',Ci='Cibochevski:BAAALAADCggIDQABLAAECgEIAQABAAAAAA==.',Cl='Clonezero:BAAALAADCgQIBAAAAA==.Cloudx:BAAALAAECgMIBQAAAA==.',Co='Corrum:BAAALAAECgMIBQAAAA==.Corya:BAAALAADCggIDwAAAA==.Covennant:BAAALAADCggIDAAAAA==.Cowboi:BAAALAADCgcIBwAAAA==.',Cr='Crystalle:BAAALAADCgcIDQAAAA==.',Cu='Cutterman:BAAALAADCggIDgAAAA==.',Cz='Czernobog:BAAALAADCgIIAgAAAA==.',Da='Daeshan:BAAALAAECgYIBgAAAA==.Dairyaki:BAAALAAECgEIAQAAAA==.Daldolarette:BAAALAAECgcIDgAAAA==.Darcnight:BAAALAADCgcIDQAAAA==.Dasecondone:BAAALAAECgYICQAAAA==.Davebra:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.Dawg:BAAALAAECgYIBgAAAA==.Days:BAAALAAECgYIDAAAAA==.',De='Deadrra:BAAALAADCggICAAAAA==.Deathkam:BAAALAADCggICAAAAA==.Deathlange:BAAALAADCgcIBwAAAA==.Deathroy:BAAALAAECgEIAQAAAA==.Decapa:BAAALAADCgQIBAABLAAECgUIBwABAAAAAA==.Demoneda:BAAALAAECgEIAQAAAA==.Destros:BAAALAAECgMIAwAAAA==.Deáth:BAAALAADCgMIAwAAAA==.',Di='Dispriests:BAAALAADCgcICwAAAA==.',Do='Donchapper:BAAALAADCggICAAAAA==.',Dr='Dragontales:BAAALAADCggIDgAAAA==.Drusti:BAAALAADCgUIAwAAAA==.Dryageribeye:BAAALAAECgUIBwAAAA==.',Du='Dudebra:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Dunchief:BAAALAAECgEIAQAAAA==.Duskthrasher:BAAALAAECgMIBQAAAA==.',Dw='Dwuid:BAAALAADCggIDAAAAA==.',Ec='Ech:BAAALAAECgYIBwAAAA==.Echo:BAAALAADCggICAAAAA==.',Ei='Eiraveta:BAAALAAECgEIAQAAAA==.',El='Elandin:BAAALAAECgYICgAAAA==.Elclapador:BAAALAADCgUIBQAAAA==.Elronn:BAAALAAECgMIBQAAAA==.',Er='Ereess:BAAALAADCgcIBwAAAA==.Eringobragh:BAAALAADCggIDQAAAA==.',Ev='Evonis:BAAALAADCgYIBQABLAAECgYIDAABAAAAAA==.',Ex='Extinct:BAAALAAECgYICwAAAA==.',Fa='Falesalla:BAAALAADCgcIDQAAAA==.Fancyee:BAAALAADCggIDAAAAA==.Fantasma:BAAALAAECgMIAwAAAA==.',Fi='Firebolt:BAAALAADCggIFwAAAA==.Fixin:BAAALAAECgQICgAAAA==.',Fl='Fluffyðvol:BAAALAAECgIIAwAAAA==.',Fo='Foxydaisy:BAAALAADCgEIAQAAAA==.Foxytotems:BAAALAAECgEIAQAAAA==.',Fr='Fraeulein:BAAALAADCgcIBwAAAA==.Fricorith:BAAALAAECgIIAgAAAA==.',Fu='Fuuz:BAAALAADCgcIBwAAAA==.',Fy='Fyr:BAAALAAECgEIAQAAAA==.',['Fù']='Fùzz:BAAALAAECgQIBwAAAA==.',Ga='Galenos:BAAALAADCgcIBwAAAA==.Garekk:BAAALAAECgEIAgAAAA==.Garsodin:BAAALAADCgYIBgABLAAECgEIAgABAAAAAA==.',Ge='Geofford:BAAALAADCgMIAwAAAA==.',Gh='Ghostee:BAAALAADCggIDwAAAA==.Ghostue:BAAALAADCgYIBgAAAA==.Ghundom:BAAALAAECgUIBgAAAA==.',Gi='Gilmore:BAAALAADCggIDQAAAA==.',Gl='Globshaper:BAAALAADCgEIAQAAAA==.',Go='Goblock:BAAALAADCggICwAAAA==.Goneville:BAAALAAECgcIDgAAAA==.Gouken:BAAALAAECgMIAwAAAA==.',Gr='Grakata:BAAALAADCggIDwABLAAECgUIBgABAAAAAA==.Grebyss:BAAALAADCggIDQAAAA==.Grenpoli:BAAALAADCgcIBwAAAA==.Gretoriks:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.Gretorix:BAAALAADCggIEAAAAA==.Greylocke:BAAALAAECgEIAQAAAA==.Gruts:BAAALAADCgUIBQAAAA==.',Gt='Gtxx:BAAALAAECgMIAwAAAA==.',Gu='Gutworthy:BAAALAAECgIIAgAAAA==.Guulgund:BAAALAAECgYIDAAAAA==.',Ha='Haldevarik:BAAALAAECgYIDAAAAA==.Hallzofdeath:BAAALAAECgYICAAAAA==.Hammerjane:BAAALAADCggICAAAAA==.',He='Healmerelic:BAAALAADCggICAAAAA==.Heavywinner:BAAALAAECgcIDgAAAA==.Hellsfury:BAAALAAECgMIBAAAAA==.',Ho='Hornluz:BAAALAADCgMIAwAAAA==.Howittzer:BAAALAAECgUIBgAAAA==.',Ht='Htr:BAAALAADCggICAAAAA==.',Hu='Hubbabubbá:BAAALAADCgYIBgAAAA==.Hughmann:BAAALAAECgEIAQAAAA==.',Hy='Hyperionyx:BAAALAADCggIEAAAAA==.',['Hâ']='Hârlot:BAAALAAECgEIAQAAAA==.',['Hõ']='Hõgi:BAAALAADCggICAAAAA==.',Ig='Igotopless:BAAALAADCgUIBQAAAA==.',Il='Illegitimate:BAAALAADCgMIBgAAAA==.Illidemon:BAAALAAECgYIDAAAAA==.',Im='Imacritter:BAAALAADCgcICAABLAADCggIFAABAAAAAA==.',In='Inariux:BAAALAADCggICAAAAA==.Indrasama:BAAALAADCggIDQAAAA==.',Ja='Jadeth:BAAALAAECgIIBAAAAA==.Jakolantern:BAAALAAECgIIAgAAAA==.Jammymg:BAAALAADCgcIEAABLAADCggIDAABAAAAAA==.Jaratri:BAAALAAECgcICwAAAA==.',Je='Jeka:BAAALAADCgcIBwAAAA==.',Jo='Jobopali:BAAALAAECgMIAwAAAA==.',Ju='Jularyn:BAAALAAECgYICQAAAA==.',Jy='Jynxter:BAAALAAECgUICwAAAA==.',Ka='Kaatu:BAAALAAECgEIAQAAAA==.Kamthesham:BAAALAAECgUIBgAAAA==.Kargorath:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Kargorok:BAAALAAECgIIAgAAAA==.Karmai:BAAALAAECgYIDAAAAA==.Karynah:BAAALAADCgcIBwAAAA==.Kathine:BAAALAAECgQIBQAAAA==.Kaysha:BAAALAADCggIBwAAAA==.',Ke='Kelwynd:BAAALAADCggIDwAAAA==.Kenda:BAAALAAECgIIAwAAAA==.Kermadec:BAAALAADCgUIBQAAAA==.',Kh='Khellendros:BAAALAADCgcIBwAAAA==.',Ki='Killmehitme:BAAALAADCgMIAwAAAA==.Kirean:BAAALAAECgYIBwAAAA==.',Kn='Knives:BAAALAAECgUIBgAAAA==.',Ko='Kobesama:BAAALAAECgYIBgAAAA==.Korrtanna:BAAALAAECgMIBAAAAA==.',Kr='Kranark:BAAALAADCgcIBwAAAA==.Krazz:BAAALAAECgEIAQABLAAECgQIBwABAAAAAA==.Kree:BAAALAADCggICwAAAA==.Krix:BAAALAAECgEIAQAAAA==.Kryssie:BAAALAAECgQIBgAAAA==.',Ky='Kylala:BAAALAADCgUIBQAAAA==.',['Kö']='Köra:BAAALAADCggICAAAAA==.',La='Ladydark:BAAALAAECgQIBwAAAA==.Lanaya:BAAALAAECgEIAQAAAA==.Laserheadten:BAAALAAECgQICgAAAA==.Laulon:BAAALAAECgEIAQABLAAECgMIAwABAAAAAQ==.',Le='Lenian:BAAALAAECgEIAQAAAA==.Lerrick:BAAALAADCgUIBQAAAA==.',Li='Lizardwizard:BAAALAADCgMIAwAAAA==.',Ll='Llando:BAAALAAECgYIDAAAAA==.',Lo='Loracelan:BAAALAADCggICwAAAA==.Loreck:BAAALAAECgQIBQAAAA==.Loredaryn:BAAALAADCggIDwAAAA==.Lorlea:BAAALAADCgMIBAAAAA==.',Lu='Luckystars:BAAALAAECgMIBAAAAA==.Lugia:BAAALAADCgcIBwAAAA==.Lunariel:BAAALAAECgMIBQAAAA==.',Lv='Lvrdrow:BAAALAAECgcICQAAAA==.',Ly='Lyraae:BAAALAAECgEIAQAAAA==.',['Lå']='Låudånum:BAAALAADCggIDgAAAA==.',Ma='Madlet:BAAALAAECgEIAQAAAA==.Maiganoss:BAAALAADCggIDgAAAA==.Manson:BAAALAADCgcIBwAAAA==.Marovek:BAAALAADCgYIBgAAAA==.',Mc='Mcpunch:BAAALAAECggIAgAAAA==.',Me='Mecho:BAAALAADCgEIAQAAAA==.Megid:BAAALAAECgEIAQAAAA==.',Mi='Midgete:BAAALAADCgcICwAAAA==.Mikewilliams:BAAALAADCgQIBAAAAA==.Milosham:BAAALAAECgQIBgAAAA==.Miradil:BAAALAADCgUIBQAAAA==.Mithesis:BAAALAAECgMIAwAAAA==.Mizblumkin:BAAALAAECgEIAQAAAA==.',Mo='Morbidcorpse:BAAALAADCgQIBAAAAA==.Moretea:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.Moriar:BAAALAAECgYIBgAAAA==.',Mu='Muradil:BAAALAADCgYIBgAAAA==.',['Mä']='Mäxïmüs:BAAALAAECgIIAgAAAA==.',['Mû']='Mûffin:BAAALAADCggIFgAAAA==.',Na='Narrondiian:BAAALAADCgcIBwABLAAECgMIAwABAAAAAQ==.Nautprepared:BAAALAADCgUIBQAAAA==.',Ne='Nerik:BAAALAADCggICwAAAA==.Nexair:BAAALAADCgMIAwAAAA==.',No='Nomari:BAAALAAECggIBgAAAA==.Noran:BAAALAAECgQIBgAAAA==.Noritide:BAAALAAECgMIAwABLAADCgYICAABAAAAAA==.',Ny='Nyctos:BAAALAADCgcIEAAAAA==.',['Nì']='Nìanna:BAAALAAECgEIAQAAAA==.',Ok='Okira:BAAALAADCgYIBgAAAA==.',Ol='Olessa:BAAALAADCggIDwAAAA==.',Or='Orcrest:BAAALAADCggIDAAAAA==.',Pa='Painette:BAAALAADCgQIBAAAAA==.Palajack:BAAALAAECgIIBQAAAA==.Paryah:BAAALAAECgEIAQAAAA==.Pauken:BAAALAADCggIDwABLAAECgUIBwABAAAAAA==.',Ph='Pharixia:BAAALAADCgcIBwAAAA==.Pheart:BAAALAADCgIIAgAAAA==.Phindra:BAAALAADCggICAAAAA==.Phréek:BAAALAADCggICAAAAA==.',Pi='Pinkdeath:BAAALAADCgUIBQAAAA==.',Pk='Pkfire:BAAALAADCgIIAgAAAA==.',Pl='Plethknight:BAAALAAECgUIBgAAAA==.',Po='Poseidoñ:BAAALAADCgMIAgAAAA==.',Pr='Praze:BAAALAADCggIDAAAAA==.Protego:BAAALAADCggIFAAAAA==.',Py='Pyriah:BAAALAAECgEIAgAAAA==.',Qr='Qrebel:BAAALAAECgEIAQAAAA==.',Ra='Ragnix:BAAALAADCgEIAQAAAA==.Rahis:BAAALAAECgQIBgAAAA==.Rahjas:BAAALAAECgEIAQAAAA==.Raiu:BAAALAAECgEIAQAAAA==.Raliek:BAAALAAECgMIBQAAAA==.Ramsis:BAAALAAECgQIBwAAAA==.Randir:BAAALAAECgUIBgAAAA==.Rath:BAAALAAECgEIAQAAAA==.Razathi:BAAALAADCggIDAAAAA==.',Re='Red:BAAALAADCgcIEAAAAA==.Rekashlaba:BAAALAADCgQIBAAAAA==.Remedivhs:BAAALAAECgMIAwAAAQ==.Renthios:BAAALAADCggIEgAAAA==.Rexkramer:BAAALAAECgQIBwAAAA==.',Rh='Rhiannonage:BAAALAADCgUIBwAAAA==.',Ri='Rizzlin:BAAALAAECgIIAgAAAA==.',Ro='Robinhoodx:BAAALAAECgYIBwAAAA==.Rockel:BAAALAAECgEIAQAAAA==.Romokhar:BAAALAAECgEIAgAAAA==.Rooflsmcrofl:BAAALAADCgYICAAAAA==.',Ru='Rudef:BAAALAAECgYICQAAAA==.',Rz='Rzzini:BAAALAADCggICAAAAA==.',Sa='Sakurá:BAAALAADCgUIBQAAAA==.Samloomis:BAAALAADCgQIBAAAAA==.Sarris:BAAALAADCggIDQAAAA==.Satsumaia:BAAALAADCggICgAAAA==.Saucyologist:BAAALAAECgEIAQAAAA==.',Se='Seablue:BAAALAADCgUIBQAAAA==.Seiba:BAAALAAECgYIDAAAAA==.Seret:BAAALAAECgQIBAAAAA==.',Sg='Sgtfriday:BAAALAAECgcICwAAAA==.',Sh='Shadexar:BAAALAAECgMIAwAAAA==.Shael:BAAALAAECgEIAQAAAA==.Shakenscotch:BAAALAADCgcICAAAAA==.Shallez:BAAALAADCggIDwAAAA==.Shamanstein:BAAALAADCgQIBAABLAADCggIDwABAAAAAA==.Shammbo:BAAALAADCgcIDgAAAA==.Shazra:BAAALAAECgYIBwAAAA==.Shelbee:BAAALAADCgMIAwAAAA==.Shikkaka:BAAALAAECgEIAQAAAA==.Shivana:BAAALAAECgMIBAAAAA==.Shrimps:BAAALAADCggIDQAAAA==.Shrykh:BAAALAADCggIDQAAAA==.Shupala:BAAALAADCgUIBwAAAA==.',Si='Sicnus:BAAALAADCgcIDQAAAA==.Sinadin:BAAALAAECgQIBQAAAA==.',Sj='Sjardi:BAAALAADCgYICAAAAA==.',Sk='Skippers:BAAALAADCgEIAQAAAA==.Skywalkr:BAAALAADCgcICAAAAA==.',Sm='Smâlls:BAAALAAECgMIBQAAAA==.',Sn='Snowshottib:BAAALAAECgEIAQAAAA==.',So='Sonnenblume:BAAALAADCgcIBwAAAA==.Sourpoppin:BAAALAAECgUIBQAAAA==.Southsound:BAAALAAECgIIAgAAAA==.',Sp='Spiceballs:BAAALAADCgQIBAAAAA==.',St='Steppinrazor:BAAALAAECggIBgAAAA==.Sturma:BAAALAAECgYICAAAAA==.',Su='Sunhi:BAAALAADCgEIAQAAAA==.Superrad:BAAALAADCggIFAAAAA==.',Sv='Svetlyna:BAAALAAECgMIAwAAAA==.',Sy='Sybil:BAABLAAECoEUAAICAAcI+hevEgAFAgACAAcI+hevEgAFAgAAAA==.Synovia:BAAALAAECgUIBQAAAA==.',['Sá']='Sálus:BAAALAADCgcIBQAAAA==.',Ta='Tahfyn:BAAALAADCggIFgAAAA==.Tahtiania:BAAALAADCggIDQAAAA==.Talkurandis:BAAALAAECgIIAwABLAAECgMIAwABAAAAAQ==.Tangi:BAAALAADCgYIBgAAAA==.',Te='Tenma:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.Teo:BAAALAAECgEIAQAAAA==.',Th='Thereispally:BAAALAADCggICAAAAA==.Thermook:BAAALAADCggICAAAAA==.Thunderrfury:BAAALAADCggIAgAAAA==.Thunderthyes:BAAALAADCggICAAAAA==.Thundertwig:BAAALAAECgIIAgAAAA==.',Ti='Timoris:BAAALAAECgUIBwAAAA==.',To='Toggo:BAAALAADCggIDgAAAA==.',Tr='Treehaus:BAAALAAECgEIAgAAAA==.Trildjr:BAAALAAECgMIAwAAAA==.Trillina:BAAALAADCgIIAQAAAA==.Truelover:BAAALAADCgYIBgAAAA==.',Tu='Tuldag:BAAALAAECgQIBwAAAA==.',Ty='Tyranny:BAAALAADCgYICAAAAA==.Tyrishawk:BAAALAAECgEIAQAAAA==.Tyrse:BAAALAAECgQIBQAAAA==.',Tz='Tzeke:BAAALAADCgQIBAAAAA==.Tzerina:BAAALAAECgIIAgAAAA==.',Ur='Urilas:BAAALAAECgMIBQAAAA==.',Va='Vaethan:BAAALAADCgUIBQABLAAECgYIDAABAAAAAA==.Valatath:BAAALAAECgIIAwAAAA==.Valereesa:BAAALAADCgIIAgAAAA==.Valford:BAAALAADCgUIBgAAAA==.Validan:BAAALAADCggIEAAAAA==.Valrah:BAAALAADCgcIBwAAAA==.Valssharess:BAAALAAECgMIBQAAAA==.Valth:BAAALAADCggIDAAAAA==.Valynxia:BAAALAAECgIIAgAAAA==.Varaella:BAAALAADCgcICwAAAA==.Vaîne:BAAALAADCgcICQAAAA==.',Ve='Vecna:BAAALAAECgMIBAAAAA==.Velenkes:BAAALAADCggIDAAAAA==.Veleria:BAAALAAECgEIAQAAAA==.Velysonna:BAAALAADCggIDQAAAA==.Verelyse:BAAALAADCggIDwAAAA==.Verio:BAAALAADCgcICwAAAA==.Versatina:BAAALAADCggIDAAAAA==.',Vi='Vicity:BAAALAAECgMIAwAAAA==.Vidris:BAAALAAECgEIAQAAAA==.Viko:BAAALAAECgIIAwAAAA==.Vinaya:BAAALAADCggIDAAAAA==.Viriyn:BAAALAADCgcIBwAAAA==.Vizhu:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.',Vo='Volthemar:BAAALAAECgQIBwAAAA==.Vortigen:BAAALAADCggIDAAAAA==.',Vu='Vulpy:BAAALAAECgUIBgAAAA==.',Wa='Watsuki:BAAALAADCggIDQAAAA==.',We='Werrick:BAAALAAECgMIBQAAAA==.',Wi='Wisegurl:BAAALAAECgUIBwAAAA==.',Wo='Wombsplitter:BAAALAADCgMIAwAAAA==.',Wu='Wushing:BAAALAAECgMIAwAAAA==.',Ww='Wwmage:BAAALAADCgMIAwAAAA==.',Wy='Wylecsham:BAAALAADCgcICQAAAA==.Wylectra:BAAALAAECgYIBwAAAA==.',['Wì']='Wìse:BAAALAADCgYICAAAAA==.',Xe='Xeròmercy:BAAALAADCggIBQAAAA==.',Ye='Yeetuis:BAAALAAECgMIAwAAAA==.',Za='Zagasham:BAAALAAECgQIBgAAAA==.Zahvaria:BAAALAADCggIFwAAAA==.Zahvia:BAAALAADCgYIBgABLAADCggIFwABAAAAAA==.Zalson:BAAALAAECgQIBAAAAA==.Zaphiell:BAAALAAECgMIAwAAAA==.Zaraylia:BAAALAAECgMIBQAAAA==.',Ze='Zekrom:BAAALAADCgcIBwAAAA==.Zev:BAAALAADCggIDAAAAA==.',Zi='Zilleey:BAAALAAECgYIDAAAAA==.',Zu='Zulwax:BAAALAAECgIIAgAAAA==.',Zy='Zykie:BAAALAAECgMIBQAAAA==.',['Äc']='Ächmed:BAAALAAECgQIBwAAAA==.',['Är']='Ärgo:BAAALAAECgEIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end