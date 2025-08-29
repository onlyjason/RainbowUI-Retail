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
 local lookup = {'Druid-Restoration','Unknown-Unknown','Hunter-BeastMastery','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety',}; local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=44,date='2025-08-29',data={Al='Alium:BAAALAAECgYICAAAAA==.',Am='Amamage:BAAALAAECgYICQAAAA==.Amaterasuu:BAAALAAECgQIBQAAAA==.',An='Ankheloios:BAAALAAECgQIBgAAAA==.',Ar='Aredhela:BAAALAAECgEIAQAAAA==.Ariadné:BAAALAAECggIAwAAAA==.Arinth:BAAALAADCgcIDAAAAA==.',As='Asmodeius:BAAALAAECgEIAQAAAA==.Astroprof:BAAALAADCgYIDAAAAA==.',At='Athrea:BAAALAAECgQIBgAAAA==.',Av='Avasharm:BAAALAADCgIIAgAAAA==.Avendros:BAAALAAECgIIAgAAAA==.',Ba='Badmoon:BAAALAAECgEIAQAAAA==.',Be='Beegchungus:BAAALAADCgcIBwAAAA==.',Bi='Bigcowguy:BAAALAADCgcIFAAAAA==.Bighorn:BAAALAAECgcIDQAAAA==.Binke:BAAALAADCggIFgAAAA==.Bittywyvern:BAAALAAECgIIAwAAAA==.',Bl='Blayze:BAAALAAECgEIAQAAAA==.Blessurheart:BAAALAAECgEIAQAAAA==.Bloodyedge:BAAALAADCggIFQAAAA==.',Bo='Bobheals:BAAALAAECgYIBgAAAA==.Bolo:BAAALAAECgcIBwAAAA==.Boostedww:BAAALAAECgIIAgAAAA==.Bowlby:BAAALAADCggIFwAAAA==.',Br='Bramacky:BAAALAADCgEIAQAAAA==.Brayker:BAAALAAECgcIEAAAAA==.Breadoneal:BAAALAAECgMIBQAAAA==.Brokenmask:BAABLAAECoEXAAIBAAgIhQ8XGwCUAQABAAgIhQ8XGwCUAQAAAA==.Brynjamin:BAAALAAECgEIAQAAAA==.',Ca='Caedwyn:BAAALAAECgMIBwAAAA==.Caitrakk:BAAALAAECgQIBAAAAA==.Camdaglam:BAAALAAECgMIBwAAAA==.Camlon:BAAALAADCggIDgAAAA==.Carebêar:BAAALAADCgcIBwABLAAECgYICAACAAAAAA==.Careradin:BAAALAAECgYICAAAAA==.Cartilage:BAAALAAECgMIAwAAAA==.Cashdown:BAAALAADCgYIBgABLAAECgcIFAADAC0bAA==.Cashketchum:BAAALAADCgIIAgABLAAECgcIFAADAC0bAA==.Cashsclay:BAABLAAECoEUAAIDAAcILRumFAA7AgADAAcILRumFAA7AgAAAA==.',Ce='Celadon:BAAALAADCggICAAAAA==.Cerus:BAAALAADCgYIBgAAAA==.',Ch='Chandra:BAAALAAECgYIDwAAAA==.',Co='Coorslight:BAAALAADCgQIBAAAAA==.Cowbustion:BAAALAAECgYICAAAAA==.',Cr='Croarik:BAAALAAECgIIAgAAAA==.Cromak:BAAALAAECgYICgAAAA==.Crunchychibi:BAAALAAECgMIBwAAAA==.',Da='Daemoten:BAAALAAECgIIAgAAAA==.Darch:BAAALAAECgcIDwAAAA==.Dartin:BAAALAAECgEIAQAAAA==.',De='Dethbysnusnu:BAAALAAECgYICgAAAA==.',Di='Dico:BAAALAAECgMIAwABLAAECgYIBgACAAAAAA==.Dipshift:BAAALAAECgYIDAAAAA==.Divinator:BAAALAADCgUIBQAAAA==.',Do='Dohan:BAAALAADCgYIBgAAAA==.Dove:BAAALAADCggICAAAAA==.',Dr='Dragonborne:BAAALAADCgQIBAAAAA==.',Du='Duerger:BAAALAAECgMIBwAAAA==.Duney:BAAALAADCggIDwAAAA==.Dustyrusty:BAAALAADCggICAABLAAECgMIBwACAAAAAA==.',Ea='Easykills:BAAALAADCgQIBAAAAA==.',Ec='Eckoe:BAAALAADCggICAAAAA==.',Ej='Ejavuday:BAAALAAECgIIAgAAAA==.',En='Englishfrie:BAAALAAECgEIAwAAAA==.',Et='Ether:BAAALAAECgMICAAAAA==.',Ev='Evera:BAAALAAECgQIBQAAAA==.',Fe='Feihao:BAAALAADCgYICAAAAA==.Feile:BAAALAAECgcICgAAAA==.',Fi='Fieris:BAAALAADCgQIBgAAAA==.',Fo='Foolezz:BAAALAAECgUIBgAAAA==.',Fr='Fredthedh:BAAALAAECgMIBwAAAA==.',Fu='Furble:BAAALAAECgEIAQAAAA==.',Ga='Galrak:BAAALAADCggICQAAAA==.Gammilite:BAAALAADCgcIDAAAAA==.Ganandor:BAAALAAECgYIDAAAAA==.Gator:BAAALAAECgYIDAAAAA==.Gaulish:BAAALAADCgIIAgAAAA==.',Ge='Getagrip:BAAALAAECgMIBQABLAAECgYIBgACAAAAAA==.',Gi='Gilhond:BAAALAAECgYICQAAAA==.',Go='Gottverdammt:BAAALAAECgcIBwAAAA==.Goturpaswrd:BAAALAADCgQIBAAAAA==.',Gr='Grizzabella:BAAALAAECgYICAAAAA==.',He='Headersz:BAAALAAECgEIAQAAAA==.Healufast:BAAALAADCgcIBwAAAA==.',Hl='Hlife:BAAALAADCggICAAAAA==.',Ho='Hogrider:BAAALAADCgEIAQAAAA==.',Hu='Huchar:BAAALAAECgYICAAAAA==.Huntar:BAAALAAECgYICAAAAA==.',Ic='Iceblade:BAAALAAECgcIDgAAAA==.',Il='Illidaniella:BAAALAADCgUIBwAAAA==.Illsmurfuup:BAAALAAECgYIDAAAAA==.',Io='Iove:BAAALAADCgQIBAAAAA==.',Ir='Irisa:BAAALAAECgYICAAAAA==.',Ja='Jackymoon:BAAALAADCggICAAAAA==.Jadzi:BAAALAADCgUIBQAAAA==.Janaru:BAAALAAECgIIAgAAAA==.',Je='Jessaiyan:BAAALAAECgcICAAAAA==.',Ji='Jisoo:BAAALAAECgcIEAAAAA==.',Jt='Jtb:BAAALAAECgMIBQAAAA==.',Ju='Jubokko:BAAALAAECgEIAQAAAA==.Julaudette:BAAALAADCgYIBgAAAA==.Julzaria:BAAALAADCggIDwAAAA==.Jurny:BAAALAAECgEIAQAAAA==.',Ka='Kadookieii:BAAALAADCggIDwAAAA==.Kahlandra:BAAALAAECgcICgAAAA==.Kathormac:BAAALAAECgMIBAAAAA==.Kawolski:BAAALAAECgYIDwAAAA==.',Ke='Keepz:BAAALAADCgIIAgAAAA==.Keerasera:BAAALAADCggICAAAAA==.',Kh='Khrama:BAAALAAECgYICAAAAA==.',Ki='Kirachi:BAAALAAECgMIBwAAAA==.',Kr='Kritterbug:BAAALAAECgYIBgAAAA==.',Ku='Kungcarefu:BAAALAADCgUIBwABLAAECgYICAACAAAAAA==.Kungfuwingz:BAAALAADCggICAAAAA==.',La='Lacio:BAAALAAECgcIDgAAAA==.Lateeda:BAAALAADCggIEwAAAA==.Lathena:BAAALAAECgYICQAAAA==.',Le='Lemonstorm:BAAALAAECgYIDAAAAA==.',Li='Lifenight:BAAALAAECgMIAwAAAA==.Ligger:BAAALAADCgcICwAAAA==.Lilstinker:BAAALAAECgYICgAAAA==.',Ln='Lninedkhack:BAAALAADCgYIBgAAAA==.',Lo='Loviatar:BAAALAAECgMIBAAAAA==.',Lu='Lunala:BAAALAADCgYICQABLAAECgQIBAACAAAAAA==.Lurman:BAAALAAECgIIAgAAAA==.Lustiel:BAAALAAECgMIAwAAAA==.',Ma='Maraysonys:BAAALAADCgMIAwAAAA==.Marryg:BAAALAAECgcIEAAAAA==.Maxdeath:BAAALAADCgcIDgAAAA==.',Me='Megtallica:BAAALAADCgQIBAAAAA==.Mensrea:BAAALAADCgcIBwAAAA==.Merrygored:BAAALAAECgEIAQABLAAECgcIEAACAAAAAA==.',Mi='Miniaa:BAAALAAECgIIAgAAAA==.Missoxx:BAAALAADCgUIBQABLAAECgMICAACAAAAAA==.',Mo='Moarpewpew:BAAALAADCgcICgABLAAECgQIBQACAAAAAA==.Mochimage:BAAALAAECgIIBAAAAA==.Mojoe:BAAALAAECgYICQAAAA==.Moopster:BAAALAAECgYICQAAAA==.',My='Mythoclast:BAAALAADCggIDgAAAA==.',Na='Nalmoc:BAAALAADCgYIBgAAAA==.Nalt:BAAALAADCggICAAAAA==.Narella:BAAALAAECgYIBgAAAA==.Narelle:BAAALAAECgYICQABLAAECgYIBgACAAAAAA==.Nathand:BAAALAADCgUIBQAAAA==.Nautika:BAAALAAECgMIBAAAAA==.',Ne='Nephilim:BAAALAADCggIBwAAAA==.Newp:BAAALAAECgcIBwAAAA==.',Nh='Nhoj:BAAALAAECgYIBgAAAA==.',Ni='Nillchill:BAAALAAECgIIAgAAAA==.Nimrose:BAAALAAECgEIAQAAAA==.Niquid:BAAALAAECgIIAgAAAA==.',Oc='Occult:BAAALAADCgEIAQAAAA==.',Os='Oshaku:BAAALAAECggIAQAAAQ==.',Ou='Outdpsacokie:BAAALAADCgYIDAAAAA==.',Pa='Palleeplz:BAAALAADCgcIBwAAAA==.Pancakezebra:BAAALAAECgcIEAAAAA==.',Pe='Penelo:BAAALAADCgcIBwAAAA==.Perturabo:BAAALAAECgMIAwAAAA==.',Ph='Phoenix:BAAALAAECgUICAAAAA==.Phrenikk:BAAALAADCgcIBwAAAA==.',Po='Pocketchange:BAAALAAECgcICgAAAA==.',Pr='Pressence:BAAALAAECgYICAAAAA==.',Pu='Puptart:BAAALAAECgQIBwAAAA==.',Qr='Qrz:BAAALAADCggICAAAAA==.',Ra='Ragadin:BAAALAADCgMIAwAAAA==.Randybobandy:BAAALAAECgMIAwAAAA==.',Re='Reeth:BAAALAADCggICAAAAA==.Renothidan:BAAALAAECgYICAAAAA==.Revrynth:BAAALAAECgMICAAAAA==.',Ri='Rithcice:BAEBLAAECoEWAAIEAAgIySXFAAB8AwAEAAgIySXFAAB8AwAAAA==.Rituals:BAAALAADCgcICwAAAA==.',Ro='Ronburgondy:BAAALAADCgcIBgAAAA==.',['Ró']='Róshi:BAAALAADCgMIAwAAAA==.',Sa='Sacdulait:BAAALAADCgEIAQAAAA==.Sarinx:BAAALAADCgIIAgAAAA==.',Sc='Scatterpaws:BAAALAAECgMIBAAAAA==.Scorns:BAAALAAECggICAAAAA==.',Sd='Sdh:BAAALAADCgYICQAAAA==.',Se='Sedici:BAAALAAECgQIBAAAAA==.',Sh='Shamman:BAAALAADCggIDwAAAA==.Shamwowz:BAAALAAECgMIBQAAAA==.Shani:BAAALAAECgEIAQAAAA==.Sherson:BAAALAAECgUICQAAAA==.Shlea:BAAALAAECgYIDQAAAA==.Shnabzy:BAAALAADCgcIDAAAAA==.',Si='Silvanna:BAAALAADCgYICQAAAA==.Sivi:BAAALAADCgIIAgAAAA==.',Sl='Slimboyjoe:BAAALAADCgIIAgAAAA==.Slimmjim:BAAALAAECgIIAgAAAA==.Slinkstir:BAAALAADCggIDAAAAA==.',So='Sourpets:BAAALAADCggICAAAAA==.Sourpetz:BAAALAAECgMIBgAAAA==.Sozolek:BAAALAADCggICgABLAAECgMIAwACAAAAAA==.',Sr='Srwars:BAAALAADCgMIAwAAAA==.',St='Standarshh:BAAALAAECgYIBgAAAA==.Steben:BAAALAAECgcIDAAAAA==.Stormrise:BAAALAADCggIDgAAAA==.',Su='Subtle:BAAALAAECgYIBgAAAA==.Sugarbabi:BAAALAAECgYICQAAAA==.Sugarcube:BAAALAADCgcIDgAAAA==.',Sw='Swann:BAAALAAECgEIAQAAAA==.',Sy='Sylrianah:BAAALAAECgcIEAAAAA==.Sylveste:BAAALAAECgIIAgAAAA==.Sylvfelster:BAAALAAECgIIAwAAAA==.',Ta='Talis:BAAALAADCgYIBwAAAA==.Tankhiskhan:BAAALAAECgYICgAAAA==.Tarlis:BAAALAADCgEIAQAAAA==.',Te='Teale:BAAALAADCgMIAwAAAA==.',Th='Thanil:BAAALAAECgIIBAAAAA==.',Ti='Tirala:BAAALAAECgMIBwAAAA==.Tiridormi:BAAALAADCgYIBgAAAA==.Titano:BAAALAADCgcICAAAAA==.',Tr='Traum:BAAALAADCgYIBgAAAA==.Traumzi:BAAALAAECgMIAwAAAA==.Travvy:BAACLAAFFIEHAAMFAAMIDR7qAQAdAQAFAAMI0xnqAQAdAQAGAAEI/hNUBABQAAAsAAQKgRgAAwYACAjbJZAAADoDAAYACAj4I5AAADoDAAUACAioJDgCAC8DAAAA.Trevmo:BAAALAAECgcIEAAAAA==.Trixxix:BAAALAAECgYICgAAAA==.',Ty='Tymora:BAAALAAECgIIAgAAAA==.Tyrving:BAAALAAECgYIBwAAAA==.',Ud='Uddershock:BAAALAADCgEIAQAAAA==.',Ur='Uraisa:BAAALAADCggICAAAAA==.',Ve='Vellissa:BAAALAAECgIIAgAAAA==.',Vi='Viral:BAAALAAECgYICQAAAA==.',Vo='Voy:BAAALAAECgcIEAAAAA==.',Vy='Vyel:BAAALAADCgcIBwAAAA==.',We='Weasy:BAAALAAECgcIDgAAAA==.',Wi='Wickedtron:BAAALAAECgcICgAAAA==.Wingzard:BAAALAAECgMIBAAAAA==.',Xf='Xfusion:BAAALAADCgcIEgAAAA==.',Xl='Xl:BAAALAAECggIEgAAAA==.',Ya='Yao:BAAALAADCgMIAwABLAAECgEIAQACAAAAAA==.Yasrena:BAAALAAECgIIAgAAAA==.',Yo='Yogurtpants:BAAALAAECgMIBAAAAA==.',Za='Zakaraki:BAAALAAECgcIEAAAAA==.Zaki:BAAALAAECgIIAgAAAA==.Zanked:BAAALAADCggICAAAAA==.',Ze='Zeleria:BAAALAAECgQIBAAAAA==.Zeno:BAAALAADCgUIBQAAAA==.',Zo='Zoflow:BAAALAADCgcIBQAAAA==.Zorb:BAAALAAECgcIEAAAAA==.Zoshow:BAAALAADCgcIBwAAAA==.',Zr='Zrakton:BAAALAAECgYICgAAAA==.',['Zõ']='Zõshow:BAAALAAECgMIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end