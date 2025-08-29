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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc',}; local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Absens:BAAALAAECgYICgAAAA==.',Ad='Adorian:BAAALAADCggICAABLAAECgYICwABAAAAAA==.',Ae='Aether:BAAALAAECgMIBAAAAA==.',Af='Aforceofone:BAAALAADCggIDAAAAA==.',Al='Alazar:BAAALAADCggIEgAAAA==.Allysia:BAAALAAECgMIBAAAAA==.',Am='Amerlinn:BAAALAADCggIDwAAAA==.',An='Andoral:BAAALAADCggIBwAAAA==.Anjan:BAAALAADCgUIAQAAAA==.Annaday:BAAALAAECgIIAwAAAA==.Antiock:BAAALAAECgYICwAAAA==.Anyaesthesia:BAAALAAECgMIBAAAAA==.',Ar='Artto:BAAALAADCgcICAAAAA==.',As='Ashbrínger:BAAALAAECgQICAAAAA==.Asterius:BAAALAADCgYIDAAAAA==.Astrum:BAAALAAECgQIBQAAAA==.',Av='Aveilas:BAAALAADCggICAAAAA==.',Ay='Aybara:BAAALAADCggIDQAAAA==.Aylakaye:BAAALAADCgcIDQAAAA==.',Az='Azrei:BAAALAAECgMIBgAAAA==.Azzathoth:BAAALAAECgUIBQAAAA==.Azzlee:BAAALAADCgMIAwAAAA==.',Ba='Baldur:BAAALAADCggIDgAAAA==.Baylohn:BAAALAADCggIDgAAAA==.',Be='Beast:BAAALAAFFAEIAQAAAA==.Beatríx:BAAALAAECgMIAwAAAA==.Beligar:BAAALAADCgUIBQABLAADCggIDwABAAAAAA==.Beärshare:BAAALAADCgQIBgAAAA==.',Bh='Bhalthazar:BAAALAADCgcIDgAAAA==.',Bi='Bigrig:BAAALAADCgEIAQAAAA==.Binato:BAAALAADCgIIAgAAAA==.Bitterman:BAAALAAECgIIAwAAAA==.',Bl='Bladed:BAAALAAECgMIBAAAAA==.Blastin:BAAALAADCgMIAwAAAA==.',Bo='Bohikeog:BAAALAADCgMIBQAAAA==.Bommbur:BAAALAAECgYIEgAAAA==.',Br='Brandeath:BAAALAAECgEIAgAAAA==.Brandrage:BAAALAADCgcIBwAAAA==.Bromagi:BAAALAAECgMIBgAAAA==.Brîttany:BAAALAAECgIIAgAAAA==.',Bu='Buildthawall:BAAALAAECgQIBQAAAA==.',Ca='Carstanan:BAAALAADCgIIAgAAAA==.Catamynyia:BAAALAAECgEIAQAAAA==.Cazsca:BAAALAADCgcIDAAAAA==.',Ce='Celaborn:BAAALAAECgcICAAAAA==.Cellestite:BAAALAAECgEIAQAAAA==.',Ch='Chazsquatch:BAAALAAECgUIBwAAAA==.Chie:BAAALAAECgMIAwAAAA==.',Cl='Clearance:BAAALAADCggIDwAAAA==.',Co='Compliance:BAAALAAECgIIAgAAAA==.Conduction:BAAALAAECgIIAwAAAA==.',Cu='Cullyeskie:BAAALAAECgEIAQAAAA==.Curveball:BAAALAADCggIAgABLAAECgIIAwABAAAAAA==.',Cy='Cyndyr:BAAALAADCgQIBAAAAA==.Cyniar:BAAALAAECgIIAgAAAA==.',Da='Damerlin:BAAALAADCgcICQAAAA==.Darkbane:BAAALAADCgYIBgAAAA==.Darkstär:BAAALAAECgMIBwAAAA==.',De='Deacon:BAAALAAECgMIBAAAAA==.Deepfriar:BAAALAAECgMIBwAAAA==.Deestro:BAAALAADCgEIAQAAAA==.Demonicjoe:BAAALAAECgEIAQABLAAECggIDgABAAAAAA==.Demonicveil:BAAALAADCgYICQABLAAECgMIAwABAAAAAA==.Derailed:BAAALAAECgMIBQAAAA==.Deydraeroeda:BAACLAAFFIEFAAICAAQISAahAQBBAQACAAQISAahAQBBAQAsAAQKgRgAAgIACAiCIp8GABUDAAIACAiCIp8GABUDAAAA.',Di='Dingô:BAAALAADCgIIAgAAAA==.Dirtman:BAAALAAECgMIBQAAAA==.Discarded:BAAALAAECgIIAgAAAA==.',Do='Doodyshamala:BAAALAADCgcICwAAAA==.',Dr='Dracthyrgeek:BAAALAADCgYIDAAAAA==.Drewdog:BAAALAADCggIFAAAAA==.',Du='Dubes:BAAALAAECgMIBwAAAA==.',Ei='Eirotari:BAAALAAECgIIAgAAAA==.Eirote:BAAALAAECgMIBwAAAA==.',El='Eldari:BAAALAADCggIFgAAAA==.Elem:BAAALAAECggIDgAAAA==.',Em='Emortal:BAAALAADCgMIAwAAAA==.Emperessfang:BAAALAAECgYICAAAAA==.',Ey='Eye:BAAALAAECgYICQAAAA==.',Fa='Faloril:BAAALAADCgcIDQAAAA==.',Fe='Felorion:BAAALAAECgEIAQAAAA==.Felynne:BAAALAADCggIEAAAAA==.Ferkme:BAAALAADCgcICgAAAA==.Ferolynch:BAAALAADCggIBQAAAA==.',Fi='Fionnan:BAAALAAECgIIAgABLAAECgMIBwABAAAAAA==.',Fr='Frosch:BAAALAADCgYICgABLAAECgMIAwABAAAAAA==.Frxst:BAAALAADCggIBQAAAA==.Fryeguy:BAAALAADCgcIDAAAAA==.',Fu='Fudo:BAAALAAECgEIAQAAAA==.Furtoes:BAAALAADCgYIDAAAAA==.',Ga='Gazerbeam:BAAALAADCgUIBQAAAA==.',Ge='Gesht:BAAALAAECgEIAQAAAA==.Getthatore:BAAALAAECgMIBAAAAA==.',Go='Goof:BAAALAAECgYICgAAAA==.Goontaa:BAAALAADCgcICgAAAA==.',Gr='Griz:BAAALAAECgMIBAAAAA==.Grizzly:BAAALAAECgEIAQABLAAECgMIBAABAAAAAA==.Gròws:BAAALAADCgcIEwAAAA==.',['Gì']='Gìmli:BAAALAADCgcIBwAAAA==.',Ha='Haddor:BAAALAADCgcIFAAAAA==.Haelor:BAAALAAECggICAAAAA==.Hammer:BAAALAADCggIFgAAAA==.Hanastuus:BAAALAADCggIDQAAAA==.Hankerin:BAAALAADCgQIBAAAAA==.Hare:BAAALAAECgcIDQAAAA==.Hatrid:BAAALAAECgUICAAAAQ==.Haunter:BAAALAAECgMIBgAAAA==.Havòk:BAAALAAECgMIAwAAAA==.',He='Healingshaft:BAAALAADCgEIAgAAAA==.Heimdall:BAAALAAECgQIBgAAAA==.Hexorcism:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.',Hi='Hilitemonk:BAAALAADCggIDwAAAA==.',Ho='Holific:BAAALAAECgMIBAAAAA==.Holymommy:BAAALAAECgMIAwAAAA==.Holysmu:BAAALAAECgMIAwAAAA==.Hotrodranger:BAAALAAECgMIBgAAAA==.Hottub:BAAALAAECgMIAwAAAA==.',Hu='Huntrezz:BAAALAAECgEIAQAAAA==.',Hv='Hvac:BAAALAAECgEIAQAAAA==.',Ja='Jacquichan:BAAALAADCgEIAgABLAAECgMIBgABAAAAAA==.Jankh:BAAALAAECgMIAwAAAA==.',Ka='Kakàrot:BAAALAADCgcIBwABLAAECgYIBwABAAAAAA==.Kalanllan:BAAALAAECgYIBwAAAA==.Kallikan:BAAALAAECgEIAQAAAA==.Kaniehtiio:BAAALAADCgcIBwAAAA==.Kasteen:BAAALAADCgEIAQAAAA==.Kaøs:BAAALAADCgYIBgAAAA==.',Ke='Kelthelon:BAAALAADCgcICgAAAA==.Kesha:BAAALAAECgMIBgAAAA==.',Kh='Khaz:BAAALAADCggICAAAAA==.',Ki='Kikariko:BAAALAAECgEIAQAAAA==.Kilaaz:BAAALAAECgQIBgAAAA==.',Kl='Klejnot:BAAALAADCgUIAwAAAA==.',Kr='Krusin:BAAALAADCggICAAAAA==.',La='Lagren:BAAALAADCgcICgAAAA==.Lazur:BAAALAADCgcIDQAAAA==.',Le='Lealoo:BAAALAADCgcIDgABLAAECgIIAgABAAAAAA==.Legolard:BAAALAAECgIIAgAAAA==.Lehi:BAAALAADCgEIAQAAAA==.Lever:BAAALAADCgIIAgAAAA==.',Li='Liath:BAAALAADCgcIDAAAAA==.',Lo='Loena:BAAALAAECgYICQAAAA==.Loko:BAAALAADCgYIBgAAAA==.Longboi:BAAALAAECgMIBgAAAA==.',Ly='Lyadra:BAAALAAECgIIAgAAAA==.',Ma='Madan:BAAALAADCggIFwAAAA==.Magey:BAAALAAECgYICQAAAA==.Majikku:BAAALAADCgcICAAAAA==.Malehorelock:BAAALAAECgMIBgAAAA==.Malkariss:BAAALAAECgMIBAAAAA==.Mammadruid:BAAALAAECgEIAQAAAA==.Mauldis:BAAALAAECgMIBAAAAA==.',Me='Meowkitty:BAAALAADCgcIBwAAAA==.Meyci:BAAALAADCgcIEQAAAA==.Mezden:BAAALAADCgYIBgAAAA==.',Mi='Miaka:BAAALAAECgMIBwAAAA==.Midanna:BAAALAAECgYIBgAAAA==.Mini:BAAALAAECgMIBgAAAA==.Minigoonta:BAAALAADCgIIAgAAAA==.Mito:BAAALAADCgcIEwAAAA==.',Mo='Moghroth:BAAALAAECgMIBgAAAA==.Mowiewowie:BAAALAADCgYIBgAAAA==.',Mu='Mundinn:BAAALAAECgMIBQAAAA==.',['Má']='Mátador:BAAALAADCgMIAwAAAA==.',Na='Nahhar:BAAALAAECgIIAgABLAAECgcICwABAAAAAA==.Nashandrelle:BAAALAADCgQIBAAAAA==.',Ne='Nekzus:BAAALAAECgEIAQAAAA==.Nella:BAAALAAECgYICQABLAAECgMIBgABAAAAAA==.',Ni='Nineva:BAAALAAECgEIAQAAAA==.',No='Nobas:BAAALAAECgMIBgAAAA==.Notoriety:BAAALAADCgUIBQAAAA==.',Ny='Nyahgsathoth:BAAALAAECgMIAwAAAA==.',Oc='Octavien:BAAALAADCgQIBAAAAA==.',On='Onlyhealz:BAAALAADCgMIAwAAAA==.',Os='Ossiiris:BAAALAADCggICAAAAA==.Osteovine:BAAALAAECgQIBAAAAA==.',Ou='Ouron:BAAALAADCgcICwAAAA==.',Pa='Paiya:BAAALAAECgMIBAAAAA==.Pandamonn:BAAALAAECgMIBwAAAA==.Paug:BAAALAAECgYIBgAAAA==.',Ph='Phoomp:BAAALAAECgMIAwAAAA==.',Pl='Plaguestingr:BAAALAAECgMIBQAAAA==.',Po='Pojoevokest:BAAALAAECgMIBAAAAA==.Pontifex:BAAALAAECgMIBgAAAA==.Portandmorph:BAAALAAECgIIAgAAAA==.',Pr='Prone:BAAALAAECgMIBwAAAA==.',Pu='Pumpiest:BAAALAADCgcIDAAAAA==.',['Pè']='Pèppèr:BAAALAAECgEIAQAAAA==.',Qr='Qròw:BAAALAADCgUICQAAAA==.',Qu='Quinnifred:BAAALAADCgcICwAAAA==.',Ra='Raakotah:BAAALAAECgcIDwAAAA==.Raasclaat:BAAALAADCgYIBgAAAA==.Raelo:BAAALAAECgMIAwAAAA==.Rahvinn:BAAALAADCggICAAAAA==.Railan:BAAALAADCgUIBQAAAA==.Rakash:BAAALAAECgYICQAAAA==.Rarg:BAAALAAECgIIAgAAAA==.Ravia:BAAALAAECgMIAwAAAA==.Razuki:BAAALAAECgMIBQAAAA==.',Re='Reddale:BAAALAADCggIDwAAAA==.Resco:BAAALAAECgMICQAAAA==.',Rh='Rhedd:BAAALAADCgQIBAAAAA==.',Rk='Rkun:BAAALAADCgcICwAAAA==.',Ro='Robopopo:BAAALAAECgYIBgAAAA==.Rook:BAAALAAECgcICwAAAA==.Rosepiercer:BAAALAAECgEIAQAAAA==.Rosyhead:BAAALAADCgcIBwAAAA==.',Sa='Samandean:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Sammich:BAAALAADCgcIBwAAAA==.Sarasvati:BAAALAADCgcIDAAAAA==.',Sc='Schmuppet:BAAALAADCggIFgAAAA==.',Se='Sellena:BAAALAAECgIIAgAAAA==.Sephir:BAAALAAECgEIAQAAAA==.Seralth:BAAALAADCgcIDQAAAA==.',Sh='Shadowmyst:BAAALAADCgcIDQAAAA==.Sheislegend:BAAALAAECgEIAQAAAA==.Shmoon:BAEALAADCgUIBQAAAA==.Shocolatte:BAAALAAECgMIBAAAAA==.Sháken:BAAALAAECgEIAQAAAA==.',Si='Siccinok:BAAALAAECgEIAQAAAA==.Sindo:BAAALAADCgYIBgABLAAECgMIBgABAAAAAA==.Sindorian:BAAALAAECgIIAgABLAAECgMIBgABAAAAAA==.Singto:BAAALAADCggICAAAAA==.Sink:BAAALAADCgYICwAAAA==.',Sk='Skullah:BAAALAADCggIDwAAAA==.',So='Sobewan:BAAALAAECgMIAwAAAA==.Solastra:BAAALAAECgMIBAAAAA==.Sommer:BAAALAAECgMIAwABLAAECgMIBAABAAAAAA==.',Sp='Spartdragon:BAAALAAECgEIAQAAAA==.',Sq='Squeakyboots:BAAALAADCgcIDAAAAA==.',St='Staryxia:BAAALAAECgMIBgAAAA==.Stephie:BAAALAADCggIFwAAAA==.Stonetotem:BAAALAAECgQIBAAAAA==.',Su='Sublimation:BAAALAADCggIDQABLAAECgIIAwABAAAAAA==.Subuwu:BAAALAAECgYICQAAAA==.Sulwen:BAAALAAECgYIEgAAAA==.Sumerset:BAAALAAECgMIAwAAAA==.Supaflytnt:BAAALAAECgIIAgAAAA==.Sustia:BAAALAADCgUIDAAAAA==.',Sw='Swolteamsix:BAAALAAECgYICAAAAA==.',['Sé']='Séphy:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.',Ta='Taera:BAAALAAECgMIBgAAAA==.Tanklndunkil:BAAALAADCggICAAAAA==.',Te='Teetaw:BAAALAADCgEIAQAAAA==.Tempus:BAAALAAECgMIBQAAAA==.Teriko:BAAALAAECgMIBQAAAA==.',Th='Thequixote:BAAALAADCgcIEgAAAA==.',Ti='Tinytotems:BAAALAADCggIDwAAAA==.',Tr='Trayice:BAAALAADCgMIAwAAAA==.',Tu='Tunky:BAAALAADCggICAABLAAECgcICwABAAAAAA==.',Un='Unta:BAAALAAECgYICgAAAA==.',Va='Vaeladric:BAAALAAECgIIAwAAAA==.Valenora:BAAALAADCgcIDgAAAA==.Valise:BAAALAADCggIEAAAAA==.Varuz:BAAALAAECgMIBgAAAA==.Varyz:BAAALAADCgMIAwABLAAECgMIBgABAAAAAA==.',Ve='Velanise:BAAALAADCgIIAgAAAA==.Veldora:BAAALAADCgIIAgAAAA==.Veloon:BAAALAADCgUIBgAAAA==.Veloras:BAAALAADCgYIBgAAAA==.Vesmina:BAAALAAECgMIBgAAAA==.',Vi='Viewer:BAAALAAECgMIAwAAAA==.Virridian:BAAALAAECgIIAgAAAA==.',Vy='Vyno:BAAALAADCgYIBgAAAA==.',Wa='Wallofshame:BAAALAAECggIAwAAAA==.Wartooth:BAAALAAECgMIBAAAAA==.Wassergott:BAAALAAECgEIAQAAAA==.',We='Weblight:BAAALAADCgcIDgAAAA==.Weeabooz:BAAALAADCgIIAgAAAA==.Wesiepooh:BAAALAADCgcIEgAAAA==.',Wh='Whistles:BAAALAAECgcIDwAAAA==.Whøratøry:BAAALAADCggIFAAAAA==.',Wi='Winona:BAAALAAECgYICQAAAA==.',Wo='Wooden:BAAALAADCgIIAgAAAA==.',Xa='Xaphy:BAAALAAECgMIBgAAAA==.Xardots:BAAALAAECgIIBAABLAAECgMIBQABAAAAAA==.',Xi='Xiareth:BAAALAADCggIFwAAAA==.',Xy='Xyleiah:BAAALAAECgMIBwAAAA==.Xyra:BAAALAAECgEIAQAAAA==.',['Xá']='Xároth:BAAALAAECgMIBQAAAQ==.',Ya='Yaddi:BAAALAADCgMIAwAAAA==.Yanci:BAAALAAECgMIBAAAAA==.',Za='Zackor:BAAALAAECgIIAgAAAA==.Zaylis:BAAALAAECgYICgAAAA==.',Ze='Zeebo:BAAALAAECgMIAwAAAA==.',Zy='Zyk:BAAALAAECgYICQAAAA==.',['Zê']='Zêphyr:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.',['Äg']='Ägramon:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end