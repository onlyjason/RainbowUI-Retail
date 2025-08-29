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
 local lookup = {'Unknown-Unknown',}; local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abadonn:BAAALAADCgYICQAAAA==.Abberleigh:BAAALAADCgcICgAAAA==.Abrikandilu:BAAALAADCggICgAAAA==.',Ad='Adran:BAAALAADCgUICwAAAA==.',Ae='Aewynn:BAAALAADCgIIAgAAAA==.',Ai='Aisling:BAAALAADCgcIDAAAAA==.',Ak='Akari:BAAALAAECgYIDAAAAA==.',Al='Alaepo:BAAALAADCgcIBgAAAA==.Alaraa:BAAALAADCggIEAABLAAECgYIDgABAAAAAA==.Alathar:BAAALAADCggICQAAAA==.Algonq:BAAALAADCgMICQABLAAECgMIAwABAAAAAA==.Alkamaz:BAAALAAECgMIAwAAAA==.Allandris:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Allsack:BAAALAADCgcIBwAAAA==.Alnethir:BAAALAADCgYIBgAAAA==.Alsar:BAAALAAECgYICQAAAA==.',Am='Amathushhg:BAAALAAECgMIBwAAAA==.',An='Andarial:BAAALAADCggIDgAAAA==.Andella:BAAALAAECgYIDgAAAA==.Andreth:BAAALAADCgcICgAAAA==.Andridertime:BAAALAADCgQIBAAAAA==.Antivalor:BAAALAADCggIFAABLAAECggIEQABAAAAAA==.Anytime:BAAALAADCgcIBwAAAA==.',Ar='Ardahh:BAAALAAECgMIAwAAAA==.Arntdorn:BAAALAADCgcICAAAAA==.',As='Ashrial:BAAALAADCgIIAgAAAA==.',Ba='Baconsdemon:BAAALAADCggICgAAAA==.Bacontotem:BAAALAAECgMIAwAAAA==.Baelhal:BAAALAAECggIEQAAAA==.Barenjager:BAAALAAECgIIAgAAAA==.',Bi='Bigtex:BAAALAAECgMIAwAAAA==.Biped:BAAALAAECgIIBAAAAA==.',Bl='Blackberry:BAAALAAECgYICAAAAA==.Blackbooks:BAAALAAECgMIBQAAAA==.Blackdeath:BAAALAAECgYIDgAAAA==.Blou:BAAALAAECgMICgAAAA==.Bluemonster:BAAALAADCgcIDgAAAA==.',Bo='Bonekrusher:BAAALAAECgEIAQAAAA==.Boomstique:BAAALAAECgMIAwAAAA==.',Br='Brainfart:BAAALAADCgIIAgAAAA==.Brokkr:BAAALAAECgIIAgAAAA==.Brunnoker:BAAALAAECgYIBgAAAA==.Brutalís:BAAALAAECgIIAwABLAAECgQICQABAAAAAA==.',Bt='Btrain:BAAALAAECgEIAQAAAA==.',Bu='Budlightyear:BAAALAAECgMIBgAAAA==.Bujeg:BAAALAAECgMIAwAAAA==.',Ca='Capbap:BAAALAAECgMIAwAAAA==.',Ce='Cenobité:BAAALAAECgMIAwAAAA==.',Ch='Chamber:BAAALAADCgEIAQABLAADCggIFAABAAAAAA==.Chaosmaster:BAAALAADCgEIAQAAAA==.Chiff:BAAALAADCgcICwAAAA==.',Ci='Cirax:BAAALAAECgIIAgAAAA==.',Cl='Clenton:BAAALAAECgYIDAAAAA==.',Co='Cordae:BAAALAADCgcICQAAAA==.',Cr='Cronnan:BAAALAADCggIEwAAAA==.Crowford:BAAALAAECgIIAwAAAA==.',Da='Daemonfaust:BAAALAAECgMIAwAAAA==.Darkartist:BAAALAADCgMIAwAAAA==.Darkdream:BAAALAAECgEIAQAAAA==.Darkmedic:BAAALAADCgcIBwAAAA==.',De='Deathral:BAAALAAECgEIAQAAAA==.Deathrall:BAAALAADCggICAAAAA==.Deedees:BAAALAADCgQIBAAAAA==.',Dh='Dhrizia:BAAALAADCgUIBQAAAA==.',Di='Diddyshank:BAAALAAECgUIBQAAAA==.Dirtnåp:BAAALAADCgMIAwAAAA==.',Dr='Dragontoast:BAAALAADCgcICgAAAA==.Drazluzkal:BAAALAADCgcICgAAAA==.Dredre:BAAALAAECgIIAgAAAA==.Druidïan:BAAALAAECgUIBQAAAA==.',['Dø']='Døwnrîteheål:BAEALAAECggIEQAAAA==.',Eb='Ebbola:BAAALAADCgMIBwAAAA==.',El='Elaric:BAAALAADCggIDwAAAA==.Elementium:BAAALAADCgcIBwAAAA==.Elgatõ:BAAALAADCgcIDQAAAA==.',En='Engi:BAAALAADCgEIAQAAAA==.',Ep='Epikrate:BAAALAAECgMIBQAAAA==.',Es='Escaper:BAAALAAECgMIAwAAAA==.',Fa='Faewynn:BAAALAADCgcIBwAAAA==.Fallenash:BAAALAADCggIDgABLAAECggIEQABAAAAAA==.Fallenembers:BAAALAAECggIEQAAAA==.Farius:BAAALAADCgYIBwABLAADCgcIBgABAAAAAA==.',Fh='Fhait:BAAALAADCgMIBgABLAAECgMIAwABAAAAAA==.Fhaust:BAAALAADCgMIAwAAAA==.',Fo='Force:BAAALAADCgIIAgAAAA==.Foxfu:BAAALAAECgMIBwAAAA==.',Fr='Frenchtoast:BAAALAAECgMIBAAAAA==.Frozenmojo:BAAALAADCgQIBQAAAA==.',Fu='Funkytown:BAAALAADCgEIAQAAAA==.Futurama:BAAALAADCggIFQABLAAECggIEQABAAAAAA==.',['Fê']='Fêyrê:BAAALAAECgQIBwAAAA==.',Ga='Gamurash:BAAALAAECgMIBAAAAA==.',Ge='Gendin:BAAALAADCgcICAABLAAECgMIBAABAAAAAA==.',Gh='Ghosty:BAAALAAECgMIBgAAAA==.Ghozt:BAAALAADCggIFAAAAA==.',Gl='Glassvortex:BAAALAADCgQIBAABLAADCgMIAwABAAAAAA==.',Go='Gostann:BAAALAAECgEIAQABLAADCggIDwABAAAAAA==.',Gr='Grezbek:BAAALAAECgUICQAAAA==.Gryphone:BAAALAADCgUIBQAAAA==.',Gu='Gustwin:BAAALAADCggIEAAAAA==.',['Gí']='Gímmick:BAAALAADCgYIBgAAAA==.',He='Healingtree:BAAALAADCggIDwAAAA==.Hellfar:BAAALAADCggIDwAAAA==.Helrix:BAAALAAECgYIBgAAAA==.',Ho='Hondojoe:BAAALAAECggIEAAAAA==.Honeydrake:BAAALAAECgQICAAAAA==.Honovi:BAAALAADCgcIDQAAAA==.Hopewell:BAAALAAECgMIAwAAAA==.',Hu='Huginn:BAAALAAECgYICQAAAA==.Hugnsnuggle:BAAALAAECgMIAwABLAAECgMIAwABAAAAAA==.Huhu:BAAALAAECgMIAwAAAA==.',['Hä']='Hännibal:BAAALAADCggICgAAAA==.',Ib='Ibage:BAAALAAECgMIAwABLAAECgQIBAABAAAAAA==.Ibn:BAAALAAECgIIBAAAAA==.',Ic='Icecreem:BAAALAADCgUIBQAAAA==.Icon:BAAALAAECgQIBgAAAA==.',Ir='Irielle:BAAALAADCggIGgAAAA==.',Iv='Ivylyn:BAAALAADCgIIAgAAAA==.',Ix='Ixì:BAAALAAECgQIBgAAAA==.',Ja='Jakota:BAAALAADCgMIBwAAAA==.Jamazion:BAAALAADCgYIDQAAAA==.Japan:BAAALAADCgMIBAAAAA==.',Jh='Jhae:BAAALAAECgYIBwAAAA==.',Jo='Joemacho:BAAALAADCgYIBgABLAAECggIEAABAAAAAA==.',Ju='Judax:BAAALAAECgYIBgAAAA==.Junrui:BAAALAADCgcICgAAAA==.Justagirl:BAAALAAECgMIAwAAAA==.Juti:BAAALAADCgIIAgAAAA==.',Ka='Kadooka:BAAALAAECgMIBgAAAA==.Kaldaran:BAAALAAECgIIBAAAAA==.Kalithorn:BAAALAADCggIEAAAAA==.Kallan:BAAALAAECgMIAwAAAA==.Karen:BAAALAADCgMICQAAAA==.Katira:BAAALAADCgMIBAAAAA==.Kazarath:BAAALAADCggIDwAAAA==.',Ke='Keelay:BAAALAAECgUIBwAAAA==.Keégan:BAAALAAECgIIAwAAAA==.',Ko='Koffcdragon:BAAALAADCgIIAgAAAA==.Koffcmorbius:BAAALAADCgMIBwAAAA==.',Kr='Kraken:BAAALAAECgQIBgAAAA==.Krønic:BAAALAADCgUIBQAAAA==.',Ku='Kubb:BAAALAAECgMIAwAAAA==.',Kw='Kweh:BAAALAAECgYIBgAAAA==.',La='Lardrel:BAAALAADCggICAAAAA==.Laurlynn:BAAALAAECgMIAwAAAA==.Lavina:BAAALAADCgcICQABLAADCggICAABAAAAAA==.',Lc='Lchaim:BAAALAADCgcICQAAAA==.',Le='Lenwe:BAAALAADCggIFAAAAA==.Leona:BAAALAADCgIIAgAAAA==.',Li='Lianolaura:BAAALAADCggIDwAAAA==.',Lo='Loquetis:BAAALAADCgQIBAAAAA==.Loxia:BAAALAADCgcIDgAAAA==.',Lu='Lumi:BAAALAADCgcICAAAAA==.',['Lá']='Láyla:BAAALAADCgUIBgAAAA==.',Ma='Maavarra:BAAALAAECgUICQAAAA==.Machera:BAAALAADCggIEQAAAA==.Maera:BAAALAAECgMIBgAAAA==.Magicnips:BAAALAADCggIEgABLAAECggIEQABAAAAAA==.Maki:BAAALAAECgIIAgAAAA==.Manss:BAAALAAECgIIAgAAAA==.Maxxum:BAAALAAECgYIBgAAAA==.Mayhew:BAAALAAECgQIBwAAAA==.',Me='Melysindria:BAAALAADCggICAAAAA==.Merixa:BAAALAAECgEIAQAAAA==.Metatron:BAAALAADCgIIAgAAAA==.',Mi='Misericorde:BAAALAAECgcIDAAAAA==.Mizwiz:BAAALAAECgMIBQAAAA==.',Mo='Momentomori:BAAALAADCgYIBwAAAA==.Moneygetter:BAAALAAECgIIAgAAAA==.Morthis:BAAALAAECgUICQAAAA==.',My='Mydarling:BAAALAADCggIEAAAAA==.Mymoon:BAAALAAECgYICQAAAA==.Myris:BAAALAAECgIIAgAAAA==.',Na='Naturalchi:BAAALAAECgMIBwAAAA==.',Ne='Nefilion:BAAALAADCgcIBwAAAA==.Nelson:BAAALAADCgcIBwAAAA==.',Ni='Nikodemus:BAAALAAECgcIEAAAAA==.',No='Nomik:BAAALAADCggICAABLAADCggIFAABAAAAAA==.Nonah:BAAALAADCgIIAgAAAA==.',Nu='Nullspace:BAAALAAECgUICAAAAA==.',['Ní']='Níghtwing:BAAALAAECgMIBQAAAA==.',Or='Orcalicious:BAAALAADCggIEgAAAA==.Orym:BAAALAAECgMIAwAAAA==.',Pa='Pallythetank:BAAALAAECgMIBAAAAA==.Pappabeary:BAAALAADCgYIDAAAAA==.',Pe='Pescoço:BAAALAADCgcIBwAAAA==.',Pr='Preachêr:BAAALAADCgMIBgABLAAECgMIAwABAAAAAA==.Primeatheist:BAAALAAECgMIBQAAAA==.Primê:BAAALAADCgEIAQABLAAECgMIAwABAAAAAA==.',Pu='Pulsebas:BAAALAAECgcIDAAAAA==.Puuhceew:BAAALAAECgMIBQAAAA==.',Qu='Quarantine:BAAALAADCgUIBQAAAA==.',['Qù']='Qùell:BAAALAADCggICAAAAA==.',Ra='Raifu:BAAALAADCgEIAQAAAA==.Rainera:BAAALAAECgQIBAAAAA==.Ramanas:BAAALAADCggIDwAAAA==.',Re='Realmizeria:BAAALAAECgcIEAAAAA==.Redeye:BAAALAAECgEIAQAAAA==.',Rh='Rhambivoid:BAAALAAECgYICQAAAA==.',Ri='Riordan:BAAALAAECgQICAAAAA==.',Ro='Rojeton:BAAALAADCgIIAgAAAA==.Rolemartyrx:BAAALAAECgUIBwAAAA==.Rothema:BAAALAADCgYIBgAAAA==.',Ru='Rude:BAAALAAECgMIAwABLAAECgMIBwABAAAAAA==.',Rw='Rwlmaster:BAAALAADCgYICQAAAA==.',Ry='Rynzia:BAAALAAECggIEQAAAA==.Ryoko:BAAALAADCggICAAAAA==.',Sa='Samatet:BAAALAADCgEIAQAAAA==.Saripriest:BAAALAADCgYIBgAAAA==.',Sc='Scerra:BAAALAAECgIIBAAAAA==.',Se='Sephiros:BAAALAADCgMIBwAAAA==.Seru:BAAALAADCgcICgAAAA==.Seviren:BAAALAAECgcIEAAAAA==.',Sh='Sharriavolf:BAAALAAECgUICQAAAA==.Shato:BAAALAAECgEIAQAAAA==.Shotzys:BAAALAADCgcIDQAAAA==.',Sl='Slavedaddy:BAAALAADCgYIBgAAAA==.Slickback:BAAALAAECgMIBQAAAA==.',Sn='Sneakysoul:BAAALAAECggIEQAAAA==.',Sp='Spanxya:BAAALAAECgQIBgAAAA==.Spartaaxd:BAAALAAECgMIBgAAAA==.Spxxgy:BAAALAAECgEIAQAAAA==.',St='Stinkyfrog:BAAALAADCggICQAAAA==.Stubmcbean:BAAALAADCgMICQABLAAECgMIAwABAAAAAA==.Studdmuffin:BAAALAAECgMIBgAAAA==.',Su='Sugary:BAAALAAECgcIDQAAAA==.Suka:BAAALAADCgMIBwAAAA==.Suramna:BAAALAAECgMIAwAAAA==.',Sw='Swiftleaf:BAAALAADCggIDwAAAA==.',Sy='Sylentcurse:BAAALAAECgQICQAAAA==.',['Sì']='Sìnfulìcìous:BAAALAADCgcIDQAAAA==.',Ta='Tagalorc:BAAALAADCggIFwAAAA==.Takamaki:BAAALAADCggIDwAAAA==.Tanksbacon:BAAALAADCgMIAgAAAA==.',Te='Teana:BAAALAADCgQIBAAAAA==.',Th='Thelegendáry:BAAALAAECgYICgAAAA==.Therosewood:BAAALAADCgEIAQAAAA==.Thraine:BAAALAAECgMIBQAAAA==.',Ti='Tianden:BAAALAAECgEIAQAAAA==.Tione:BAAALAAECgEIAgAAAA==.',To='Toto:BAAALAADCgYICwAAAA==.',Tr='Treebear:BAAALAADCgcIDgAAAA==.Treeboi:BAAALAADCgQIBQAAAA==.Trisstan:BAAALAAECgMIAwAAAA==.',Ty='Tymur:BAAALAAECgQIBgAAAA==.',Um='Umbrax:BAAALAADCgUIBQAAAA==.',Un='Uncledots:BAAALAADCggICAAAAA==.',Uz='Uzukune:BAAALAAECgMIBAAAAA==.',Va='Vandalism:BAAALAAECgEIAQAAAA==.Vandenar:BAAALAAECgEIAQAAAA==.Vasilli:BAAALAADCgMIAwAAAA==.',Ve='Vellii:BAAALAAECgYICQAAAA==.Vellora:BAAALAADCgQIBAAAAA==.Veloth:BAAALAAECgcIEAAAAA==.',Vl='Vll:BAAALAAECgUIBwAAAA==.',Vo='Voidemort:BAAALAADCggICAAAAA==.',Vy='Vynlerian:BAAALAAECgEIAQAAAA==.',Wa='Wanawa:BAAALAAECgEIAQABLAAECgQIBgABAAAAAA==.Wardran:BAAALAADCggICAAAAA==.Warhorne:BAAALAADCgMIAwABLAAECgQIBgABAAAAAA==.',We='Wearhóuse:BAAALAAECgYICgAAAA==.',Wi='Wilshaman:BAAALAADCgMIBwAAAA==.Wisemoney:BAAALAADCgMIAwAAAA==.',Wy='Wylian:BAAALAADCgcICgAAAA==.',Xa='Xandercruise:BAAALAADCggIDwAAAA==.Xanthong:BAAALAAECgUICAAAAA==.Xanweeb:BAAALAADCggICAAAAA==.',Xi='Xilanthis:BAAALAAECgMIAwAAAA==.',Xu='Xuchilbara:BAAALAAECgQIBAAAAA==.',Ya='Yamato:BAAALAAECgMIBQAAAA==.',Yu='Yumchurros:BAAALAAECgMIBAAAAA==.',Za='Zaledron:BAAALAAECgQIBwAAAA==.',Zd='Zdivinity:BAAALAAECgcIEAABLAADCgMIAwABAAAAAA==.',Ze='Zendeth:BAAALAAECgMIAwAAAA==.Zenno:BAAALAADCgQIBQAAAA==.Zethic:BAAALAAECgEIAQAAAA==.',Zh='Zhades:BAAALAAECgIIAgABLAADCgMIAwABAAAAAA==.Zhort:BAAALAAECgIIAwAAAA==.',Zi='Zircon:BAAALAADCggIDwAAAA==.',Zj='Zjaffacakes:BAAALAADCgMIAwAAAA==.',Zo='Zodi:BAAALAADCgcIEAAAAA==.',Zu='Zultan:BAAALAAECgYIDAAAAA==.Zurrik:BAAALAAECgcIEAAAAA==.',['Är']='Ärtísãñwû:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end