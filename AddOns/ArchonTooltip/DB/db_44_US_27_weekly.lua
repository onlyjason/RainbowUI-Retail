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
 local lookup = {'Hunter-BeastMastery','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Frost','Mage-Frost',}; local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adoniss:BAAALAADCgcIDAAAAA==.Adrillonz:BAAALAADCgYIBgAAAA==.Adrillyn:BAAALAAECgIIAgAAAA==.',Ae='Aeirith:BAAALAAECgYIDAAAAA==.Aesohf:BAAALAAECgYICQAAAA==.',Ag='Aggroholic:BAAALAAECgUICAAAAA==.',Ai='Airius:BAAALAADCgMIBQAAAA==.',Ak='Akillerwithn:BAAALAADCgYICgAAAA==.',Al='Alayana:BAAALAADCgMIAwAAAA==.',Am='Amaliax:BAAALAADCgYIBgAAAA==.Amalthia:BAAALAAECgYIBgAAAA==.Amarasu:BAAALAAECgMIBAAAAA==.Amarlly:BAAALAADCggIEAAAAA==.',An='Anakiddo:BAAALAADCggIDQAAAA==.Andrela:BAAALAADCgMIBQAAAA==.',Ar='Archérhiro:BAABLAAECoEWAAIBAAgILiAKBgADAwABAAgILiAKBgADAwAAAA==.Arillann:BAAALAAECgYICgAAAA==.Arms:BAAALAADCgQIAwAAAA==.Arrook:BAAALAADCgYICwAAAA==.',As='Asclëpius:BAAALAAECgMIAwAAAA==.Ashymage:BAAALAAECgYIDQAAAA==.Asiram:BAAALAADCgYICQAAAA==.Askevar:BAAALAADCggIDgAAAA==.Asriél:BAAALAADCgcIBwAAAA==.',At='Atreus:BAAALAAECgMIBAAAAA==.',Av='Avolar:BAAALAADCggIDQAAAA==.',Ay='Ayyayyron:BAAALAADCgIIAgAAAA==.',Az='Azaleah:BAAALAAECgUIBgAAAA==.Azeryn:BAAALAADCgQIBAAAAA==.Azureflamez:BAAALAADCggICAABLAAECgMIAwACAAAAAA==.',Ba='Bainbridge:BAAALAADCgcIDgAAAA==.Bassanar:BAAALAAECgMIAwAAAA==.Baza:BAAALAAECgMIAwAAAA==.',Be='Beanoficate:BAAALAADCgMIBAAAAA==.Bearnormus:BAAALAADCgMIAwAAAA==.Beary:BAAALAAECgEIAgAAAA==.Beetcoyne:BAAALAADCggIDwAAAA==.Beliria:BAAALAAECgMIBgAAAA==.Benafflock:BAAALAADCggIDQAAAA==.',Bj='Bjornulfr:BAAALAADCggICAAAAA==.',Bl='Blackadder:BAAALAADCgcIEgAAAA==.Blackula:BAAALAADCgUIBQAAAA==.Blue:BAAALAAECgYICgAAAA==.',Bo='Bobthefist:BAAALAADCgMIAwAAAA==.Bogern:BAAALAADCgcIBwAAAA==.',Br='Branwynn:BAAALAADCgMIBQAAAA==.Breezydemon:BAAALAADCgcIEQAAAA==.Breezyrocks:BAAALAAECgIIAwAAAA==.Brenz:BAAALAAECgYICQAAAA==.Broke:BAAALAAECgQIBgAAAA==.',Bu='Buildthawall:BAAALAADCggIFAABLAAECgQIBwACAAAAAA==.',By='Byryja:BAAALAADCgYIBwAAAA==.',Ca='Caidinn:BAAALAAECgMIBAAAAA==.Caitlin:BAAALAADCgYIBgAAAA==.Calkey:BAAALAADCgcICwAAAA==.Camstone:BAAALAADCgQIBAAAAA==.Carmpriest:BAAALAADCgQIBAAAAA==.Carnagesim:BAAALAADCgIIAgAAAA==.Cawdor:BAAALAAECgIIAgABLAAECgMIBAACAAAAAA==.',Ce='Cereavel:BAAALAADCgQIBAAAAA==.',Ch='Channingtotm:BAAALAAECgcIEwAAAA==.Chattiehoof:BAAALAADCggIEAAAAA==.Chungis:BAAALAADCgIIAgAAAA==.Churros:BAAALAAECgEIAQABLAAECgIIAgACAAAAAA==.Chuug:BAAALAADCgYIBgAAAA==.',Cl='Closet:BAAALAADCgYIBgAAAA==.Clownfiesta:BAAALAADCgIIAgAAAA==.',Co='Coberren:BAAALAADCggIDAAAAA==.Coldbringer:BAAALAAECgMIAwAAAA==.Cordialkylie:BAAALAAECgEIAQAAAA==.',Cr='Crosslock:BAAALAADCgcIDgAAAA==.',Cu='Custom:BAAALAADCggICAAAAA==.',Cy='Cyberchic:BAAALAADCggIEwAAAA==.',['Câ']='Câp:BAAALAAECgQIBwAAAA==.',Da='Daamdem:BAAALAADCggICAAAAA==.Daeneris:BAAALAAECgQICAAAAA==.Dalaris:BAAALAADCgcIDgAAAA==.Danizmi:BAAALAAECgMIBQAAAA==.Darkkin:BAAALAADCgEIAQAAAA==.Darktress:BAAALAADCgQIBgAAAA==.Darrosh:BAAALAADCgEIAQAAAA==.Davell:BAAALAADCggIDwAAAA==.',De='Deathlorde:BAAALAAECgYIDAAAAA==.Deathmare:BAAALAADCggIDgAAAA==.Deathmojo:BAAALAAECgMIBAAAAA==.Deathty:BAAALAADCgUIBQABLAAFFAIIAgACAAAAAA==.Demitri:BAAALAADCggICAAAAA==.Demonocryl:BAABLAAECoEXAAIDAAgIKiPLBAAzAwADAAgIKiPLBAAzAwAAAA==.Demonrabbit:BAAALAAECgIIAgAAAA==.',Di='Digadigadoo:BAAALAAECgMIAwAAAA==.Diocles:BAAALAADCgcIDgAAAA==.Dirtsquirt:BAAALAADCgYIBgAAAA==.Discontent:BAAALAADCggIDQAAAA==.',Dk='Dkancelado:BAABLAAECoEXAAIEAAgIKhmtGQAwAgAEAAgIKhmtGQAwAgAAAA==.',Dm='Dmginc:BAAALAADCgMIBQAAAA==.',Do='Doeblin:BAAALAADCgcICwAAAA==.Dontyoudie:BAAALAADCgYIBwABLAADCggIDAACAAAAAA==.',Dr='Dracogabo:BAAALAADCgYICQAAAA==.Dragonflai:BAAALAAECgMIAwAAAA==.Dragonkin:BAAALAAECgIIAgAAAA==.Dragoverse:BAAALAADCgcIFQAAAA==.Draik:BAAALAAECgEIAQAAAA==.Drakkei:BAAALAAECgMICQAAAA==.Drazzixx:BAAALAAECgQIBAAAAA==.Drunkinfuzzy:BAAALAADCgcIFQAAAA==.Drylo:BAAALAAECggICgAAAA==.',Du='Dunstir:BAAALAADCggIEgAAAA==.',Dw='Dwemeor:BAAALAADCggIDQAAAA==.Dwinders:BAAALAAECgQIBAAAAA==.',Ea='Eastcoast:BAAALAAECgEIAQAAAA==.',Eg='Eggs:BAAALAADCgUIBgAAAA==.',Em='Emeralde:BAAALAAECgIIAgAAAA==.',Er='Ereada:BAAALAADCgEIAQAAAA==.',Es='Esil:BAAALAAECgMIAwAAAA==.',Et='Ethellin:BAAALAADCggIEAAAAA==.',Ex='Excalodor:BAAALAADCgYICQAAAA==.',Fe='Felraiser:BAAALAADCgUIBQAAAA==.Felwinter:BAAALAAECgYICwAAAA==.Femcelgoon:BAAALAAECgEIAQAAAA==.Fererune:BAAALAADCgYIBgAAAA==.',Fi='Firne:BAAALAADCgMIAwAAAA==.',Fo='Fourdramis:BAAALAADCgQIBAAAAA==.',Fr='Freakybtch:BAAALAADCgIIAgAAAA==.Fred:BAAALAAECgEIAQAAAA==.',Fu='Fullmage:BAAALAADCgYIBgAAAA==.Fuzzyhunter:BAAALAAECgEIAQAAAA==.',Ga='Gabel:BAAALAAECgMIAwAAAA==.Galand:BAAALAADCggIEgAAAA==.Galladin:BAAALAAECgcIDQAAAA==.Gallock:BAAALAAECgEIAQAAAA==.Gardyson:BAAALAAECgMIAwAAAA==.Garnet:BAAALAAECgMIBQAAAA==.Gastly:BAAALAAECgEIAQABLAAECgYICwACAAAAAA==.',Ge='Gesh:BAAALAADCgMIBQAAAA==.',Go='Gooblet:BAAALAADCgMIAwAAAA==.',Gr='Graveshift:BAAALAAECgYICwAAAA==.Greeds:BAAALAADCgcIBQAAAA==.Gremilien:BAAALAAECgMIBAAAAA==.Gruggrug:BAAALAADCgQIBAAAAA==.Gruglog:BAAALAADCgYICgABLAAECgMIBAACAAAAAA==.Grymtotem:BAAALAAECgEIAQAAAA==.',Gu='Guati:BAAALAAECggICAAAAA==.',Ha='Hamthesham:BAAALAAECgEIAQAAAA==.Harrod:BAAALAAECgMIBQAAAA==.',He='Hellcream:BAAALAAFFAEIAQAAAA==.Hellsspawn:BAAALAADCgYIDQAAAA==.Hellsspirit:BAAALAADCgEIAQAAAA==.Hernia:BAAALAAECgEIAQABLAAECgQIBAACAAAAAA==.',Ho='Hokàge:BAAALAAECgYIDQAAAA==.Hollyroller:BAAALAADCgEIAQAAAA==.Holyknight:BAAALAAECgMIBQAAAA==.Holymoley:BAAALAAECgMIAwAAAA==.Hoshistark:BAAALAAECgIIAgAAAA==.',Hu='Huey:BAAALAADCgQICAABLAAECgEIAQACAAAAAA==.Huntinfuzzy:BAAALAADCggICQAAAA==.',Ic='Icantblink:BAAALAAECgQIBAABLAAECggIFwAEACoZAA==.',Ig='Igothots:BAAALAAECgYICQAAAA==.',Il='Illaela:BAAALAAECgMIAwAAAA==.',In='Insanitty:BAAALAAECgYICQAAAA==.',Ip='Ipmanda:BAAALAADCgcIEgAAAA==.',Ir='Irritable:BAAALAAECgMIBAAAAA==.',Is='Isadragon:BAAALAADCgQIBAABLAAECgMIBAACAAAAAA==.',Ja='Jango:BAAALAADCgQIBAAAAA==.',Je='Jellyspinoff:BAAALAAECgUIBQAAAA==.Jellytown:BAAALAAECgYICgAAAA==.Jezelda:BAAALAADCggICQAAAA==.',Ji='Jizun:BAAALAAECgMIAwAAAA==.',Jo='Joebillybob:BAAALAAECgIIAgAAAA==.',Jp='Jpeppers:BAAALAADCgcIEQAAAA==.',Ju='Jundra:BAAALAAECgIIAgAAAA==.',['Jô']='Jôhnwick:BAAALAAECgMIBwAAAA==.',Ka='Kaidalazul:BAAALAAECgMIBgAAAA==.Kaineh:BAAALAADCggIFAAAAA==.Kaladil:BAAALAADCgcIDAAAAA==.Kaltren:BAAALAADCgUIBQAAAA==.Kamaren:BAAALAAECgMIAwAAAA==.Kannan:BAAALAAECgIIAgAAAA==.Karkana:BAAALAADCgEIAQAAAA==.Kashmirh:BAAALAADCgYIBwAAAA==.Kashmyhr:BAAALAADCgUIDAAAAA==.Kasmius:BAAALAADCgcIBwAAAA==.Kasmus:BAAALAADCgMIBAAAAA==.Kawdor:BAAALAADCgcICAABLAAECgMIBAACAAAAAA==.Kazola:BAAALAADCgcIDAAAAA==.',Ke='Kerjeet:BAAALAADCgMIAwAAAA==.',Ki='Killdar:BAAALAADCgEIAQABLAADCgcIBwACAAAAAA==.',Ko='Kollinator:BAAALAADCgIIAgAAAA==.',Kr='Kristella:BAAALAAECgEIAQABLAAECgYICwACAAAAAA==.Kroger:BAAALAADCggIEQABLAAECgIIAgACAAAAAA==.',Kv='Kvltqt:BAAALAADCgcIDgAAAA==.',Ky='Kyleena:BAAALAADCgIIAgAAAA==.',La='Lafty:BAAALAAFFAIIAgAAAA==.Larac:BAAALAAECgEIAQAAAA==.Larsfrommars:BAAALAAECgEIAQAAAA==.',Le='Leadge:BAAALAADCgYIBgAAAA==.Lenik:BAAALAAECgEIAQAAAA==.Lerios:BAAALAADCggIDQAAAA==.Leëp:BAAALAADCgcICgAAAA==.',Li='Licorice:BAAALAAECgIIAgAAAA==.Lilyfaye:BAAALAADCgcIDwAAAA==.Limits:BAAALAADCgcIDAAAAA==.Limosfire:BAAALAADCgcIDgAAAA==.',Lo='Logi:BAAALAADCgQIBAAAAA==.',Lu='Lunà:BAAALAADCggIDAAAAA==.',Ly='Lythalle:BAAALAAECgMIAwAAAA==.Lythwynn:BAAALAADCgYIBgAAAA==.',['Lý']='Lýnx:BAAALAADCggIDAAAAA==.',Ma='Maeledis:BAAALAADCgEIAQAAAA==.Magdalena:BAAALAADCgcICAAAAA==.Mageyboi:BAAALAADCgIIAgABLAAECgYIDQACAAAAAA==.Manachi:BAAALAADCgcIBwAAAA==.Manamage:BAAALAADCgcIBwAAAA==.',Mc='Mcfrothbeard:BAAALAADCgcIBwAAAA==.',Me='Meliodås:BAAALAAECgMIBQAAAA==.Merien:BAAALAAECgIIAwAAAA==.Metaphysical:BAAALAADCggIDgAAAA==.',Mi='Minilock:BAAALAAECgMIBgAAAA==.',Mm='Mmnnmmnnmnmn:BAAALAAECgMIAwAAAA==.',Mo='Mongermook:BAAALAAECgEIAQAAAA==.Monnkysham:BAAALAAECgQICAAAAA==.Mooglefur:BAAALAADCggIDQAAAA==.Morniath:BAAALAADCggICwAAAA==.Moryna:BAAALAAECgIIAgAAAA==.',Mu='Muninn:BAAALAADCgQIBAAAAA==.Muuntara:BAAALAAECgEIAQAAAA==.',My='Myaka:BAAALAADCgYIBgAAAA==.Myralam:BAAALAADCggICAAAAA==.',['Mç']='Mçgonagall:BAAALAADCgcIEgABLAADCgcIEgACAAAAAA==.',['Mì']='Mìth:BAAALAADCgQIBAABLAADCgcIDAACAAAAAA==.',Na='Naatixa:BAAALAAECgEIAQAAAA==.Nacronor:BAAALAADCgcIGwAAAA==.Nancho:BAAALAADCgcICQAAAA==.Narada:BAAALAADCggIEgAAAA==.Nasmine:BAAALAADCgQIBAAAAA==.Nasoj:BAAALAADCgQIBAABLAADCgQIBAACAAAAAA==.Nasumimonk:BAAALAADCgQIBAAAAA==.',Ne='Necrotic:BAAALAADCggICAAAAA==.Neobahamut:BAAALAAECgMIAwAAAA==.',Ni='Nicksaban:BAAALAAECgEIAQAAAA==.Nightgear:BAABLAAECoEUAAIBAAgICR+0CgC2AgABAAgICR+0CgC2AgAAAA==.Nilux:BAAALAADCggIFgAAAA==.Niteshadeth:BAAALAADCgcIDQAAAA==.Nixeava:BAAALAADCgcIDAAAAA==.',No='Nopetsneeded:BAAALAAECgMIBAABLAAECgQIBAACAAAAAA==.Norepairbill:BAAALAADCggICAABLAAECgQIBAACAAAAAA==.Nostariel:BAAALAAECgIIAgAAAA==.Notafurry:BAAALAADCgQIBAAAAA==.Noteworthy:BAAALAADCgUIBQAAAA==.',Ns='Nskanni:BAAALAADCgcIBwAAAA==.',Ny='Nyctera:BAAALAADCgMIAwAAAA==.Nysong:BAAALAAECgIIAgAAAA==.',Od='Oddangel:BAAALAADCgQIBAAAAA==.Odex:BAAALAAECgMIBAAAAA==.',Ok='Okayish:BAAALAADCgYIBgABLAADCgYIBgACAAAAAA==.',Or='Orongru:BAAALAADCgEIAgAAAA==.',Ou='Outlul:BAAALAAECgYIBgAAAA==.',Pa='Pachao:BAAALAADCgIIAgAAAA==.Pally:BAAALAAECgMIBQAAAA==.Paramedic:BAAALAADCggIDQAAAA==.Partyplumper:BAAALAAECgYICgAAAA==.',Pe='Peaches:BAAALAADCgYIBgAAAA==.Peachybelle:BAAALAADCgcICQAAAA==.Penhaligon:BAAALAADCgMIAwAAAA==.Peregríne:BAAALAADCgYIBgAAAA==.Pettybetty:BAAALAAECgMIBwAAAA==.',Pi='Pinny:BAAALAADCgMIAwAAAA==.',Po='Poppit:BAAALAADCggICAAAAA==.',Pr='Prom:BAAALAADCgcICQAAAA==.Promethèus:BAAALAAECgYICQAAAA==.Prosby:BAAALAADCggIFwAAAA==.Provor:BAAALAADCgcIDAAAAA==.',Pu='Puncharina:BAAALAADCgQIBAAAAA==.',Qu='Quanjo:BAAALAADCggIDQAAAA==.Queedle:BAAALAAECgMIBwAAAA==.',Ra='Raenyro:BAAALAADCgEIAQAAAA==.Raincestor:BAAALAAECggIEgAAAA==.Rainsvoker:BAAALAADCgUIBwAAAA==.Ramike:BAAALAADCggICAAAAA==.Ranbir:BAAALAAECgEIAQAAAA==.Randal:BAAALAADCggIDQAAAA==.Ranrawr:BAAALAADCgUIBQABLAAECgEIAQACAAAAAA==.Raqtar:BAAALAAECgIIAgAAAA==.Razihel:BAAALAADCgIIAgAAAA==.',Re='Redglerbs:BAAALAADCgIIAgAAAA==.Refrigerator:BAABLAAECoEYAAIFAAgIwCPIAQApAwAFAAgIwCPIAQApAwABLAADCggICAACAAAAAA==.Regality:BAAALAADCgcIBwAAAA==.Revasevander:BAAALAADCggICAAAAA==.Reyrá:BAAALAADCggICAAAAA==.',Ri='Rimchester:BAAALAADCgEIAQAAAA==.Rippy:BAAALAADCgcIFQAAAA==.Rithxx:BAAALAADCgEIAQAAAA==.Ritzon:BAAALAAECgYICgAAAA==.',Ro='Rockñroll:BAAALAADCggIDQAAAA==.Roguebait:BAAALAAECgYIDwAAAA==.Rottdot:BAAALAAECgIIAgAAAA==.',['Rê']='Rêyra:BAAALAAECgYICwAAAA==.',Sa='Sandokan:BAAALAADCgMIBQAAAA==.',Sc='Scubasteve:BAAALAAECgEIAQAAAA==.',Se='Sellex:BAAALAADCgcICQAAAA==.Selyn:BAAALAAECgMIAwAAAA==.Seneka:BAAALAAECgYICwAAAA==.Seniorfreaky:BAAALAADCgIIAgAAAA==.',Sh='Shadol:BAAALAADCgUIBgAAAA==.Shadowzfall:BAAALAAECgMIAwAAAA==.Shamanhack:BAAALAADCggIDQAAAA==.Shampon:BAAALAADCgYIBwAAAA==.Shmooves:BAEALAAECgEIAQAAAA==.Shobu:BAAALAADCggIDQAAAA==.',Si='Siveth:BAAALAADCggIDgAAAA==.',Sk='Skeemer:BAAALAADCgMIAwAAAA==.Skips:BAAALAAECgIIAgAAAA==.Skullace:BAAALAADCgcIDgAAAA==.Skybreaker:BAAALAADCggIEAAAAA==.',Sl='Slashndash:BAAALAAECgMIAwAAAA==.Slilith:BAAALAADCgcIBwAAAA==.',Sm='Smashurfacen:BAAALAADCgcIEAAAAA==.',Sn='Sneakysnek:BAAALAADCgEIAQAAAA==.',Sp='Spurdo:BAAALAAECgEIAQAAAA==.',Sr='Srfreaky:BAAALAADCgYICwAAAA==.',Sy='Syldi:BAAALAADCgUIBgAAAA==.Sypha:BAAALAAECgYICQAAAA==.',['Sö']='Sörren:BAAALAADCgcICAAAAA==.',Ta='Tartinari:BAAALAAECgYIDgAAAA==.',Te='Telandril:BAAALAAECgYICgAAAA==.Tenlel:BAAALAADCggIDQAAAA==.Tensuken:BAAALAADCggIDwAAAA==.Tetoncitowo:BAAALAAECgEIAQAAAA==.',Th='Thadium:BAAALAADCggIDAAAAA==.Thassian:BAAALAADCgQIBAAAAA==.Thath:BAAALAAECgYIDwAAAA==.Theremar:BAAALAADCgUIBQAAAA==.',Ti='Tiabea:BAAALAADCgYIBgAAAA==.',To='Totemik:BAAALAADCgQIBAAAAA==.',Tr='Tresg:BAAALAAECgEIAQABLAAECgQICAACAAAAAA==.Trimble:BAAALAADCgcIBgAAAA==.',Tw='Tweetz:BAAALAAECgIIAgAAAA==.Twerely:BAAALAADCgcIBwABLAADCggIDgACAAAAAA==.Twinkie:BAAALAAECgMIAwAAAA==.',Ty='Tyiedis:BAAALAAECgYICgAAAA==.Tyregar:BAAALAADCgcIEAAAAA==.Tyrànda:BAAALAADCgcICQAAAA==.',Ug='Ugotcarried:BAAALAAECgMICAAAAA==.',Uk='Ukodus:BAAALAAECgQIBQAAAA==.',Un='Unholy:BAAALAAECgMIAwAAAA==.',Ur='Urimli:BAAALAAECgMIBwAAAA==.',Va='Vadïn:BAAALAADCggICAAAAA==.Valsitril:BAAALAADCgQIBAABLAADCgcIDgACAAAAAA==.Valthaczar:BAAALAADCgUIBQAAAA==.Varadun:BAAALAADCggIFAAAAA==.Varelyna:BAAALAADCgcIBwABLAADCgcIDgACAAAAAA==.',Ve='Velsetin:BAAALAAECgcIDgAAAA==.Vendic:BAAALAADCggICQAAAA==.Verathina:BAAALAADCgEIAQAAAA==.',Vi='Vipbull:BAAALAADCggIBQAAAA==.',We='Webpage:BAAALAAECgEIAQAAAA==.',Wh='Whisperwindd:BAAALAADCgYIBgAAAA==.Whispter:BAAALAADCgYIBgAAAA==.Whitetoothe:BAAALAAECgIIAwAAAA==.',Wi='Witherhoard:BAAALAADCgMIAgAAAA==.',Wo='Wolfclawz:BAAALAADCgcICAAAAA==.',['Wé']='Wéllidan:BAAALAADCgMIAwAAAA==.',Xa='Xaniana:BAAALAAECgMIBAAAAA==.Xanthelil:BAAALAAECgMIAwAAAA==.',Xe='Xephir:BAAALAAECgUIBQAAAA==.',Xo='Xotiko:BAAALAAECgYICwAAAA==.',['Xâ']='Xâxâs:BAAALAADCgcIDAAAAA==.',Ym='Ymilla:BAAALAAECgMIBAAAAA==.',Yu='Yucci:BAAALAADCgcIBwAAAA==.Yuffië:BAAALAADCgYIBgAAAA==.Yutri:BAAALAADCgEIAQAAAA==.',Za='Zalezaar:BAAALAADCgQIBAAAAA==.Zaresa:BAAALAADCgcICAAAAA==.',Ze='Zephrylia:BAAALAADCgcIDQAAAA==.Zeraz:BAAALAAECgEIAQAAAA==.Zestusk:BAAALAADCgYIBgAAAA==.',Zh='Zhirl:BAAALAADCgcIBwAAAA==.Zhivet:BAAALAADCgMIAwAAAA==.',['Åp']='Åpexx:BAAALAADCgEIAQAAAA==.',['Îp']='Îpwñåñôöb:BAAALAADCgEIAQAAAA==.',['Ös']='Östara:BAAALAADCggIDwAAAA==.',['Ør']='Ørc:BAAALAAECgQIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end