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
 local lookup = {'Unknown-Unknown','Paladin-Retribution',}; local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Accursed:BAAALAAECgUICAAAAA==.',Ad='Adol:BAAALAAECgUIBwAAAA==.',Ai='Airpod:BAAALAADCgQIBAABLAAECgEIAQABAAAAAA==.',Ak='Akharthor:BAAALAADCggICAAAAA==.',Al='Alacair:BAAALAADCgcIBwAAAA==.Aleighta:BAAALAADCgcIBwAAAA==.',Am='Amiren:BAAALAADCggICwAAAA==.',An='Anero:BAAALAAECgMIBAAAAA==.',As='Ashtuck:BAAALAADCgcIDgAAAA==.Asmodius:BAAALAADCgUIBgAAAA==.',At='Atlantis:BAAALAADCggIEAAAAA==.',Az='Azagor:BAAALAADCggIDgAAAA==.',Ba='Backshots:BAAALAAECgYICQAAAA==.Baja:BAAALAAECgMIBAAAAA==.Bananâs:BAAALAAECgEIAQAAAA==.',Be='Bearlyatank:BAAALAAECgIIAgAAAA==.Belan:BAAALAAECgUICAAAAA==.Belfegor:BAAALAAECgIIAgAAAA==.Belladin:BAAALAAECgYIDwAAAA==.',Bi='Bigsmashbash:BAAALAADCgIIAgAAAA==.Bishdrood:BAAALAAECggIEQAAAA==.',Bl='Blamecheese:BAAALAADCggIDgAAAA==.Blamezuko:BAAALAADCgYIBgAAAA==.Blite:BAAALAADCgcIEQAAAA==.Bloom:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.',Bo='Bobiejo:BAAALAAECgUIBwAAAA==.Bomburst:BAAALAAECgMIBAAAAA==.Bonelespizza:BAAALAAECgYIEgAAAA==.Bongrippa:BAAALAADCgYIBwAAAA==.',Br='Brandywyne:BAAALAADCgcICgAAAA==.Brendand:BAAALAADCggIDAAAAA==.Bruel:BAAALAADCgMIAwAAAA==.',Bu='Bullschmidt:BAAALAAECgYICgAAAA==.',Ca='Cachinnare:BAAALAADCgUIBQABLAADCgYICwABAAAAAA==.Calabretta:BAAALAAECgYICQAAAA==.Camermike:BAAALAADCggIFQAAAA==.Canuhduhh:BAAALAAECgQIBwAAAA==.Captnjack:BAAALAADCggIDwAAAA==.',Ch='Chaece:BAAALAAECgUICAAAAA==.Chaindemon:BAAALAADCgMIBAAAAA==.Charysmaa:BAAALAADCgcIEQAAAA==.Cheoekar:BAAALAADCgYIDAAAAA==.Chevygurl:BAAALAADCggIDwAAAA==.',Co='Coca:BAAALAAECgMIBwAAAA==.Coldrick:BAAALAADCgIIAgAAAA==.Corgi:BAAALAAECgMIBgAAAA==.Cosmicjay:BAAALAAECgEIAQAAAA==.',Cr='Crow:BAAALAAECgYIBgAAAQ==.',Cy='Cyndline:BAAALAADCgMIAwAAAA==.',Da='Daffodil:BAAALAAECgEIAQAAAA==.Dannyshoot:BAAALAADCgEIAQAAAA==.Dantaeres:BAAALAADCgYIBgAAAA==.Dantreess:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Dantruis:BAAALAAECgYICQAAAA==.Darkshiver:BAAALAADCgMIAwAAAA==.',De='Dec:BAAALAADCgEIAQAAAA==.Demonwolfss:BAAALAAECgQIBAABLAAFFAMIAwABAAAAAA==.',Di='Diabla:BAAALAAECgcICgAAAA==.Diothorn:BAAALAAECgEIAQAAAA==.',Du='Dudrank:BAAALAAECgIIAwAAAA==.Duskowl:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.',Dy='Dymondsmashr:BAAALAAECgIIAgAAAA==.',['Dæ']='Dænerys:BAAALAAECgYIBwAAAA==.',Eb='Ebben:BAAALAADCgYIBgAAAA==.',Eg='Egirlslayer:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.',Em='Emberrose:BAAALAAECgEIAQAAAA==.',En='Envymytalent:BAAALAAECgIIAgAAAA==.',Fa='Fakedruid:BAAALAAECgYICQAAAA==.',Fr='Frostfires:BAAALAAECggICAAAAA==.Fryerchris:BAAALAADCggIEwAAAA==.Fryylock:BAAALAADCgYIBgABLAADCggIEwABAAAAAA==.',Fu='Fusky:BAAALAAECgEIAQAAAA==.',Fy='Fynn:BAAALAAECgcIDwAAAA==.',Ga='Galadria:BAAALAAECgYIDQAAAA==.',Go='Goldenlock:BAAALAADCggICAAAAA==.Golfmo:BAAALAAECgYICwAAAA==.',Gr='Gre:BAAALAADCggIDAAAAA==.Greenleaves:BAAALAAECgIIAgAAAA==.',Gu='Guay:BAAALAAECgEIAQAAAA==.',Ha='Hailin:BAAALAAECgYICQAAAA==.Harlsley:BAAALAADCgcIBwAAAA==.',Hi='Hightroller:BAAALAAECgMIBgAAAA==.',Ho='Holyjenkins:BAAALAADCgEIAQAAAA==.Homulily:BAAALAADCgUIBgAAAA==.Howlingdeath:BAAALAADCggICAAAAA==.',Ja='Jankismith:BAAALAAECgMIBgAAAA==.Jayy:BAAALAAECgIIAgAAAA==.',Ka='Kamerth:BAAALAAECgIIAgAAAA==.Kapow:BAAALAAECgMIAwAAAA==.Karluron:BAAALAAECgUIBgAAAA==.Katbaka:BAAALAADCgYIBgABLAADCggIDgABAAAAAA==.Katmoreahh:BAAALAADCggIDgAAAA==.Kazure:BAAALAAECgYIDQAAAA==.',Kh='Khaôtic:BAAALAAECgEIAQAAAA==.',Ki='Kidgrif:BAAALAADCgIIAgAAAA==.Kidneyspears:BAAALAADCggICQAAAA==.Kienzy:BAAALAADCgEIAQAAAA==.',Ko='Konekokat:BAEALAADCggIFAAAAA==.',Kr='Krakkin:BAAALAADCgYIBwAAAA==.Kravenovv:BAAALAADCggICgAAAA==.Krenil:BAAALAADCgYIEQAAAA==.Kryypt:BAAALAADCggICAAAAA==.',Ku='Kuzenzalo:BAAALAADCgcIDQAAAA==.',['Kî']='Kîkyo:BAAALAAECgYIBgAAAA==.',La='Laaksy:BAAALAAECgcIDwAAAA==.Landock:BAAALAADCgYICQAAAA==.Landrothus:BAAALAADCgMIAwAAAA==.Lavaca:BAAALAAECgYICgAAAA==.Laylla:BAAALAAECgMIBAAAAA==.',Le='Leotart:BAAALAAECgUIBQAAAA==.',Li='Lindiin:BAAALAADCgYIBwAAAA==.',Ll='Llewxam:BAAALAADCgQIBAAAAA==.',Lo='Lortnok:BAAALAAECgMIBQAAAA==.Lothlórien:BAAALAAECgQICAAAAA==.',Lu='Lukadoncic:BAAALAADCggIDgABLAAECgYIBwABAAAAAA==.Luwwin:BAAALAAECgMIAwAAAA==.',['Lö']='Lögäñ:BAAALAAECgMIAwAAAA==.',Ma='Magiclaire:BAAALAADCgUIBQAAAA==.Magon:BAAALAADCgMIAwAAAA==.Mari:BAAALAADCgcIDgAAAA==.Marist:BAAALAADCggIDwAAAA==.Maspada:BAAALAAECgYICgAAAA==.',Me='Mewfrostian:BAAALAADCgcIBwAAAA==.',Mi='Mianceden:BAAALAAECgEIAQAAAA==.Miku:BAAALAADCgUIBQAAAA==.Milent:BAAALAAECgUICAAAAA==.',Mo='Moarteas:BAAALAADCgIIAwAAAA==.Mon:BAAALAAECgMIAwAAAA==.',Ms='Msspelled:BAAALAADCgcIDgAAAA==.',Mu='Muhahahahaa:BAAALAADCgQIBAABLAADCggIEwABAAAAAA==.Munkeynuts:BAAALAADCgYIBgAAAA==.',Mx='Mximus:BAAALAAECggIDwAAAA==.',My='Mystí:BAAALAAECgYIDgAAAA==.',Na='Nabstar:BAAALAADCggICAABLAAECgUICAABAAAAAA==.Nabstarr:BAAALAAECgUICAAAAA==.Nasroth:BAAALAAECgQICQAAAA==.Nast:BAAALAAECgQIBAAAAA==.',Ni='Niibyter:BAAALAAECgIIAgAAAA==.Niveous:BAAALAADCgcIEQAAAA==.Niveus:BAAALAADCgcIBwAAAA==.',Ol='Oldgreyone:BAAALAADCggIGAAAAA==.',On='One:BAAALAADCgcICAAAAA==.Onlylocks:BAAALAAECgMIAwAAAA==.',Or='Oreeli:BAAALAAECgYICQAAAA==.Orlis:BAAALAADCgcICgAAAA==.',Pa='Pallydan:BAAALAAECgYIDAAAAA==.',Ph='Philanthropy:BAAALAAECgYIDQAAAA==.',Pi='Pitchdemise:BAAALAAECgEIAQAAAA==.',Pl='Pläze:BAAALAAECgEIAQAAAA==.',Po='Poppy:BAAALAAFFAIIAgAAAA==.Porunga:BAAALAADCgEIAQAAAA==.',Pu='Pust:BAAALAADCggIDwAAAA==.',Py='Pyronorish:BAAALAADCgMIAwAAAA==.Pytthia:BAAALAAECgYICAAAAA==.',Qu='Quinntus:BAAALAADCgUIBQAAAA==.',Ra='Ramitos:BAAALAADCgYIBgAAAA==.Raptalia:BAAALAADCgEIBAAAAA==.Ratfingers:BAAALAADCgUIBQABLAADCgYICwABAAAAAA==.Rathands:BAAALAADCgYICwAAAA==.',Re='Rebs:BAAALAADCgIIAwAAAA==.Reganox:BAAALAADCgYICQAAAA==.Rethonaevyr:BAAALAADCgQIBAAAAA==.',Ri='Rickjamesbia:BAAALAADCgEIAQAAAA==.Rikiriki:BAAALAAECgEIAQAAAA==.Rizhir:BAAALAADCgEIAQAAAA==.',Ro='Ronkey:BAAALAADCgYICQAAAA==.Ronktea:BAAALAADCgcICgAAAA==.Ronkzar:BAAALAADCgcICgAAAA==.',['Rô']='Rôflstômp:BAAALAAECgEIAQAAAA==.',Sa='Saekura:BAAALAADCgYICgAAAA==.Salanis:BAAALAADCggICAABLAAECgIIAwABAAAAAA==.Saltydog:BAAALAADCgIIAgAAAA==.Sashayleft:BAAALAAECgYICgAAAA==.',Sc='Scampi:BAAALAAECgMIBgAAAA==.',Se='Sebasmatiu:BAAALAADCgYIBgAAAA==.Selfesteem:BAAALAADCgcIDAAAAA==.Setal:BAAALAAECgMIBAAAAA==.',Sh='Shaft:BAAALAAECgUIBQABLAAECgYICQABAAAAAA==.Shamurloc:BAAALAAECgcIDwAAAA==.Sheenatonic:BAAALAAECgYICQAAAA==.Shionn:BAAALAADCggICAAAAA==.Shoukan:BAAALAAECgYICAAAAA==.',Si='Silentpaw:BAAALAAECgUICAAAAA==.Siska:BAAALAADCgcIDAAAAA==.',Sl='Slak:BAAALAAECgQIBAAAAA==.',Sm='Smallchaos:BAAALAAECgMIBwAAAA==.Smelt:BAAALAADCgUIBQAAAA==.',So='Sokáar:BAAALAADCgcIBwAAAA==.',Sr='Srmixmurloc:BAAALAADCgEIAQAAAA==.',St='Stabbytrout:BAAALAAECgYIEQAAAA==.Starrise:BAAALAAECggIAwAAAA==.Stickyjr:BAAALAADCgEIAQAAAA==.',Su='Sunetra:BAAALAADCgQIBAAAAA==.',['Sà']='Sàlanis:BAAALAAECgIIAwAAAA==.',Ta='Taloki:BAAALAADCgYIBwAAAA==.Tatsuhisa:BAAALAADCgYIBQAAAA==.Tayshren:BAAALAADCgcIAgABLAADCggIDwABAAAAAA==.Tazdingo:BAAALAADCgYIBgAAAA==.',Th='Thallyn:BAAALAADCggIDgAAAA==.Thyung:BAAALAADCgcIBwAAAA==.',Ti='Tikkari:BAAALAADCgMIAwAAAA==.Tinny:BAAALAADCgQIBAAAAA==.',Tk='Tkd:BAAALAAECgYICQAAAA==.',To='Toph:BAAALAAECgYIDgAAAA==.',Tr='Trollwarlock:BAAALAADCgcIBwAAAA==.Trolosarushx:BAEALAAECgEIAQABLAAECggIGAACANoeAA==.Trondur:BAAALAADCgIIAgAAAA==.Trydel:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.',Ts='Tsukihana:BAAALAADCgcIBwAAAA==.',Tw='Twinkiee:BAAALAADCgcIDgAAAA==.',['Tá']='Tálonstorm:BAAALAAECgMIBgAAAA==.',Ul='Ultra:BAAALAAECgIIAgAAAA==.',Ur='Ursidae:BAAALAADCgcIBwAAAA==.',Va='Vaeek:BAAALAAECgEIAQAAAA==.Vaestar:BAAALAAECgIIAgAAAA==.Valnoressa:BAAALAADCggIDgAAAA==.',Ve='Vendetta:BAAALAADCgcIBwAAAA==.',Vi='Vidofnir:BAAALAADCgcIBwAAAA==.Vilthrax:BAAALAADCgMIAwAAAA==.Viperdude:BAAALAAECgIIAgABLAAECgYICwABAAAAAA==.',Vl='Vladvladvlad:BAAALAADCgcIBwAAAA==.',Vo='Vormav:BAAALAADCggIDgABLAAECgUIBwABAAAAAA==.',['Ví']='Ví:BAAALAADCggIDQAAAA==.',Wa='Watermelon:BAAALAAECgEIAQAAAA==.Wayofthefox:BAAALAAECgYICQAAAA==.',Wh='Whalaski:BAAALAAECgUICgAAAA==.',Wi='Wickedsin:BAAALAADCgMIAwAAAA==.Wildren:BAAALAADCgcIDgAAAA==.',Wo='Woolybülly:BAAALAADCgcIBwAAAA==.',Wr='Wreckitman:BAAALAADCgcICAAAAA==.',Wy='Wynnie:BAAALAADCgYICwAAAA==.',Xa='Xaalath:BAAALAADCgcIDgAAAA==.',Ya='Yaacotu:BAAALAADCgcIDgAAAA==.Yaperbitally:BAAALAAECgIIAgAAAA==.',Yo='Yozomi:BAAALAADCgYIDQAAAA==.',Ze='Zellzii:BAAALAAECgIIAgAAAA==.Zerø:BAAALAAECgEIAgAAAA==.',Zi='Zillâ:BAAALAAECgIIAgAAAA==.',Zo='Zorlon:BAAALAADCggIEAABLAADCggIFQABAAAAAA==.',['Äu']='Äustin:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end