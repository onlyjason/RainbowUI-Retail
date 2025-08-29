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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','DeathKnight-Blood',}; local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aamine:BAAALAAECgIIAgAAAA==.',Ac='Acefu:BAAALAADCgQIBAAAAA==.Acornella:BAAALAAECgcIEQAAAA==.Acornilly:BAAALAADCgQIBAABLAAECgcIEQABAAAAAA==.',Ad='Adalaid:BAAALAAECgEIAQAAAA==.Adreva:BAEALAAECgMIAwAAAA==.',Ai='Ailanthus:BAAALAAECgIIAgAAAA==.',Al='Aleinadris:BAAALAAECgIIAgAAAA==.Alloisaber:BAAALAADCggIEQAAAA==.',An='Ankeseth:BAAALAADCgcIDAAAAA==.',Ao='Aodoragon:BAAALAADCggICgAAAA==.',Ar='Arkrage:BAAALAADCgYIBgAAAA==.Armarlos:BAAALAADCgYIDwAAAA==.Arthar:BAAALAADCgcIBwAAAA==.Arén:BAAALAAECgQIBgAAAA==.',As='Ashamarhaast:BAAALAAECgEIAQAAAA==.Aszun:BAAALAADCggICQABLAADCggIDwABAAAAAA==.',Av='Avadda:BAAALAAECgIIAgAAAA==.',Ba='Bahadur:BAAALAADCggIDgAAAA==.',Be='Bearzerk:BAAALAADCggIEAAAAA==.Beezlbub:BAAALAADCgcIDQAAAA==.Benathar:BAAALAAECgMIBQAAAA==.',Bi='Bigbuns:BAAALAADCgEIAQABLAAECgcIEQABAAAAAA==.Bigdumper:BAAALAAECgcIEQAAAA==.Bionico:BAAALAADCggIEgAAAA==.Birgir:BAAALAADCgcIBwAAAA==.',Bl='Blackbird:BAAALAAECgcIBwAAAA==.Blitzlichtpo:BAAALAADCgEIAQAAAA==.Bloodthorn:BAAALAAECgMIAwAAAA==.',Bo='Bortt:BAAALAADCgEIAQAAAA==.Bozscaggs:BAAALAAECgQIBAAAAA==.',Br='Brantu:BAAALAADCggIEAAAAA==.Brattishm:BAAALAAECgIIAgAAAA==.Breez:BAAALAAECgMIBAAAAA==.Brewtality:BAAALAADCgMIAwAAAA==.',Bu='Burstangel:BAAALAAECgEIAQAAAA==.',['Bå']='Båzgøre:BAAALAADCgUIBQAAAA==.',Ca='Cadenza:BAAALAADCgcIFAAAAA==.Catalyst:BAAALAADCgcIBwAAAA==.',Ce='Cerdwin:BAAALAAECgMIAwABLAAECgUIBgABAAAAAA==.',Ch='Charferad:BAAALAADCgcIFAAAAA==.Chibeard:BAAALAAECgMIBQAAAA==.Chihîro:BAAALAAECgIIAgAAAA==.Chonglin:BAAALAADCgYICAAAAA==.',Cl='Clubsdh:BAAALAAECgEIAQAAAA==.',Co='Corialis:BAAALAAECgEIAgAAAA==.',Cr='Crosis:BAAALAADCgEIAQAAAA==.',Da='Daladrius:BAAALAADCgcIFAAAAA==.Dalvy:BAAALAADCgcIBwAAAA==.Danlanis:BAAALAAECgMIAwAAAA==.Darkktotem:BAAALAAECgMIAwAAAA==.Dazanna:BAAALAAECgMIBAAAAA==.Dazre:BAAALAADCgIIAgAAAA==.',De='Deadlights:BAAALAAECgMIBQAAAA==.Deegan:BAAALAADCgcIFAAAAA==.Demunz:BAAALAADCgQIBwAAAA==.',Di='Diod:BAAALAAECgMIBQAAAA==.',Dr='Dracowolf:BAAALAADCgQIBAAAAA==.Dracvoker:BAAALAADCgUICQAAAA==.Draithis:BAAALAAECgcIEQAAAA==.Drayper:BAAALAADCgcIBwAAAA==.Druugal:BAAALAAECgUICQAAAA==.',Du='Dubs:BAAALAAECgMIBAAAAA==.Dulgrim:BAAALAADCggIDgAAAA==.Dunbarke:BAAALAAECgQICQAAAA==.Durnek:BAAALAAECgMIBQAAAA==.',Ei='Eisenstein:BAAALAADCgEIAQAAAA==.',El='Elliwynd:BAAALAAECgMIBAAAAA==.Elsi:BAAALAADCggIFQAAAA==.',Er='Erinnys:BAAALAAECgIIAgAAAA==.',Fl='Flaminfalcon:BAAALAAECgIIAgAAAA==.Flody:BAAALAAECgEIAQAAAA==.',Fo='Foorplay:BAAALAAECgMIBAAAAA==.Foxflame:BAAALAAECgUIBgAAAA==.',Fr='Freakbob:BAAALAAECgIIAgAAAA==.Froglocky:BAAALAAECgMIBQAAAA==.Frôstblade:BAAALAADCgcIBwAAAA==.',Fu='Furyaìd:BAAALAAECgIIAgAAAA==.Fusrohdah:BAAALAADCgMIAgAAAA==.',Ge='Genkithered:BAAALAAECgMIBQAAAA==.',Gh='Ghostofshaw:BAAALAADCgcIDgAAAA==.',Gl='Glyde:BAAALAAECgcIBwAAAA==.',Go='Goobs:BAAALAADCgcIAgAAAA==.',Gr='Grimhorn:BAAALAADCggIFwAAAA==.',He='Hessian:BAAALAAECgMIBgAAAA==.',Hi='Hillbroken:BAAALAAECgQIBwAAAA==.',Ho='Hojx:BAAALAAECgEIAQAAAA==.',Hu='Huntrix:BAAALAADCgYIDAAAAA==.',Hv='Hvit:BAAALAADCgcIBwAAAA==.',['Hà']='Hànks:BAAALAAECgMIBQAAAA==.',Ib='Ibíng:BAAALAADCgYIBgAAAA==.',Ic='Iceatron:BAAALAAECgEIAQAAAA==.',Im='Imo:BAAALAAECgEIAgAAAA==.',In='Inèvitable:BAAALAAECgQIBwAAAA==.',Ir='Ironphant:BAAALAADCggIDgAAAA==.',Ja='Jabujabu:BAAALAAECggICAAAAA==.',Ji='Jimsshaman:BAAALAADCgYIBgAAAA==.',Jo='Jolty:BAAALAAECgcIEQAAAA==.',['Jð']='Jð:BAAALAADCgEIAQAAAA==.',Ka='Kaiou:BAAALAADCgQIBAAAAA==.Kantor:BAAALAAECgQIBwAAAA==.Kasryna:BAAALAADCgYICAAAAA==.Kathinja:BAAALAAECgEIAQAAAA==.',Ke='Ketameanie:BAAALAAECgMIBgAAAA==.',Kh='Khadaver:BAAALAAECgEIAQAAAA==.',Ki='Killerchick:BAAALAADCgYICQAAAA==.',Km='Kmazing:BAAALAADCgUIBQAAAA==.',Ko='Konoha:BAAALAAECgMIBAAAAA==.',Ku='Kultag:BAAALAAECgEIAQAAAA==.',Ky='Kyaw:BAAALAADCggICAAAAA==.Kynzo:BAAALAAECgQIBwAAAA==.',Le='Lehann:BAAALAAECgIIAgAAAA==.',Li='Libertine:BAAALAAECgMIBQAAAA==.Lidolan:BAAALAAECgMIBAAAAA==.',Lo='Locá:BAAALAAECgQIBwAAAA==.',Lp='Lp:BAAALAADCgIIAgAAAA==.',Ma='Malgarian:BAAALAADCgcIDgAAAA==.Maplem:BAAALAAECgMIAwAAAA==.Masume:BAAALAADCggIDQAAAA==.',Me='Meowmix:BAAALAADCgQIBwAAAA==.',Mi='Michi:BAAALAAECgYICQAAAA==.Mikuki:BAAALAADCgcIBwAAAA==.',Mj='Mjölnir:BAAALAADCggIEAAAAA==.',Mo='Montita:BAAALAAECgMIAwAAAA==.',Ms='Msmaho:BAAALAADCggIEQAAAA==.',Na='Nashira:BAAALAAECgMIAwAAAA==.',Ne='Nemasus:BAAALAAECgYICgAAAA==.',Ni='Nioshei:BAAALAAECgIIAgAAAA==.Nisara:BAAALAAECgMIBAAAAA==.',No='Nochmuerta:BAAALAADCggIDwAAAA==.Nogrid:BAAALAAECgQIBwAAAA==.',Nu='Nurzle:BAAALAADCggIDgAAAA==.',Ol='Oldgreg:BAAALAADCgYIBgAAAA==.',Op='Opky:BAAALAADCggIDQAAAA==.',Or='Orneryosprey:BAAALAAECgEIAQAAAA==.',Ot='Otenshi:BAAALAADCgMIAwAAAA==.',Oz='Ozzrik:BAAALAAECgMIBAAAAA==.',Pa='Palielf:BAAALAAECgIIAgAAAA==.Pamburu:BAAALAAECgQIBwAAAA==.Papagrape:BAAALAAECgIIAgAAAA==.Parzivàl:BAAALAAECgcIEQAAAA==.Paxa:BAAALAAECgMIBQAAAA==.',Pe='Peacebox:BAAALAAECgEIAQAAAA==.Persayis:BAAALAADCgcIFAAAAA==.',Ph='Phoebel:BAAALAADCggIDwAAAA==.Phoenixbodhi:BAAALAAECgIIAgAAAA==.Phöz:BAAALAAECgcIEAAAAA==.',Po='Podnov:BAAALAAECgcIEQAAAA==.',Ra='Raithiss:BAAALAADCgEIAQABLAAECgcIEQABAAAAAA==.Ramsesb:BAAALAADCgQIBAABLAAECggIDwACABAbAA==.',Re='Redvelvet:BAAALAAECgMIAwAAAA==.Rekoner:BAAALAAECgEIAQAAAA==.',Ro='Rocks:BAAALAADCgcIBwAAAA==.',Ry='Rykria:BAAALAADCgIIAwAAAA==.',Sa='Sabbath:BAAALAAECgIIAgAAAA==.',Sc='Scrubnbubble:BAAALAADCgcIFAAAAA==.',Se='Selanda:BAAALAADCgEIAQAAAA==.',Sh='Shocknoris:BAAALAADCgEIAQAAAA==.Shoshin:BAAALAADCggIFQAAAA==.Shïvana:BAAALAADCgcIEQAAAA==.',Si='Silversaiyan:BAAALAAECgMIAwAAAA==.',Sl='Slade:BAAALAAECgMIAwAAAA==.',Sn='Snowfawn:BAAALAADCgcIDQABLAAECgMIBgABAAAAAA==.Snowieblaze:BAAALAAECgMIBgAAAA==.',So='Sofedan:BAAALAAECgQIBwAAAA==.Solaryx:BAAALAAECgEIAQAAAA==.Solinthel:BAAALAADCgUIBQAAAA==.Sorokwa:BAAALAADCggICAAAAA==.',Sq='Squids:BAAALAAECgQIBAAAAA==.',St='Stolenfate:BAAALAADCgQIBAAAAA==.',Su='Sunsword:BAAALAADCgMIAwAAAA==.',Sw='Swagidan:BAAALAAECggICAAAAA==.Sweaterloc:BAAALAADCgMIAwAAAA==.',Sy='Sylphrène:BAAALAAECgQIBwAAAA==.',['Sç']='Sçruffy:BAACLAAFFIEGAAIDAAMIkh/LAAAgAQADAAMIkh/LAAAgAQAsAAQKgRgAAgMACAgpJEsBADsDAAMACAgpJEsBADsDAAAA.',Ta='Taleth:BAAALAADCgcIDAABLAADCggIFQABAAAAAA==.Talfart:BAAALAADCggICAAAAA==.Tandrana:BAAALAADCgEIAQAAAA==.Tanwen:BAAALAAECgQIBwAAAA==.',Te='Techniqe:BAABLAAECoEPAAICAAgIEBvOCgBnAgACAAgIEBvOCgBnAgAAAA==.Teetsham:BAAALAAECggIDwAAAA==.',Th='Thulhunn:BAAALAADCgcICAAAAA==.Thuzar:BAAALAAECgMIBQAAAA==.',Ti='Ticebane:BAAALAAECggIDAAAAA==.Tidusmonk:BAAALAADCggIDgAAAA==.Tiduswar:BAAALAADCgcIBwAAAA==.Titanbeard:BAAALAADCgYIBgAAAA==.Titor:BAAALAAECgEIAgAAAA==.Tituspullo:BAAALAAECgEIAQAAAA==.',To='Tolduan:BAAALAAECgMIAwAAAA==.Totemik:BAAALAAECgEIAQAAAA==.',Tr='Tresera:BAAALAADCggIFwAAAA==.Tricarnetry:BAAALAADCggIEgAAAA==.Trogladyte:BAAALAADCgMIAwAAAA==.Trollin:BAAALAADCggIEAAAAA==.Trîela:BAAALAADCgcIBwAAAA==.',['Tô']='Tôôtsie:BAAALAAECgEIAQAAAA==.',Ve='Verakis:BAAALAAECgIIAgAAAA==.Verndarí:BAAALAAECgQIBwAAAA==.Verudora:BAAALAADCgcIFAAAAA==.Vestrayda:BAAALAAECgQIBwAAAA==.',Vo='Vortheus:BAAALAADCggIEAAAAA==.',Wa='Warning:BAAALAADCgcIBwAAAA==.',Wi='Widdy:BAAALAAECgMIAwAAAA==.Willbur:BAAALAAECgQIBwAAAA==.',Wu='Wurthwhile:BAAALAAECggICAAAAA==.',Wy='Wylaniris:BAAALAADCgYIDAAAAA==.Wyndywalker:BAAALAAECgMIBQAAAA==.',Ya='Yahman:BAAALAADCgcIEAAAAA==.',Ye='Yemozun:BAAALAAECgcIEQAAAA==.',Yo='Yoku:BAAALAAECgYICgAAAA==.',Za='Zamønk:BAAALAAECgIIBAAAAA==.Zatari:BAAALAADCgQIBAAAAA==.',Zy='Zyleeth:BAAALAADCgcIDQAAAA==.',['Äp']='Äpollymi:BAAALAADCgcIEQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end