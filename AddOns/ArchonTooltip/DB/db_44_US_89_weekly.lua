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
 local lookup = {'Unknown-Unknown','Druid-Balance','Mage-Arcane','Warlock-Destruction','Warlock-Demonology','Mage-Fire','DeathKnight-Frost',}; local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Ado:BAAALAADCgcIBwABLAAECgcIDQABAAAAAA==.',Al='Alamora:BAAALAADCgYIDQAAAA==.Alathena:BAAALAADCgMIAwAAAA==.Albinoz:BAAALAAECgcIEAAAAA==.Alerwin:BAAALAADCgIIAgAAAA==.Allem:BAAALAADCgEIAQAAAA==.',An='Anak:BAAALAAECgEIAQAAAA==.',Ar='Arathor:BAAALAAECgMIBAAAAA==.Ardor:BAAALAADCggIDAAAAA==.Arfy:BAAALAAECgIIAgAAAA==.Artemislives:BAAALAADCgIIAgAAAA==.',As='Asharia:BAAALAAECgIIAgAAAA==.Assateague:BAAALAADCgYIDQAAAA==.',At='Athlstan:BAAALAADCgcIDAAAAA==.Atrosity:BAAALAAECgYICQAAAA==.',Az='Azaleh:BAAALAAECgYICwAAAA==.',Ba='Barracksbuny:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.',Bi='Biddy:BAAALAADCggICwAAAA==.Biggdaddy:BAAALAAECgYIDQAAAA==.',Bl='Blackbeans:BAAALAAECgYIDAAAAA==.Bloodgrm:BAAALAADCgUIBQAAAA==.Bluechalk:BAAALAAECgYIBgABLAAFFAEIAQABAAAAAA==.',Bo='Bonesentinel:BAAALAAECgcIEAAAAA==.',Br='Braelysong:BAAALAADCgIIAgAAAA==.Brakhon:BAAALAADCgcIEgAAAA==.Bridela:BAAALAADCgcICgAAAA==.',Bu='Buttrock:BAAALAADCgcIBwAAAA==.Buzzdruu:BAABLAAECoEUAAICAAgILxxcCQCZAgACAAgILxxcCQCZAgAAAA==.',Ca='Caesus:BAAALAADCggIDAAAAA==.Cagedancer:BAAALAAECgMIBQAAAA==.Callio:BAAALAAECgcIDQAAAA==.Cathillex:BAAALAAECgEIAQAAAA==.Cavagos:BAAALAAECgcIDgAAAA==.Caycay:BAAALAAFFAEIAQAAAA==.',Ch='Chaosknight:BAAALAADCgUIBQAAAA==.Chestpaynes:BAAALAADCggICAAAAA==.Chillmage:BAABLAAECoEVAAIDAAgITSE8CAD7AgADAAgITSE8CAD7AgAAAA==.Churd:BAAALAAECgYICgAAAA==.Churdicus:BAAALAADCggICAAAAA==.',Cl='Cleft:BAAALAADCggICAAAAA==.Clowwnshoes:BAAALAAECgMIAwAAAA==.',Co='Cocopuff:BAAALAAECgMIAwAAAA==.Cocopuffs:BAAALAADCgcIBwAAAA==.Coldeyed:BAAALAADCggIDwAAAA==.Colostrom:BAAALAAECgcIDQAAAA==.Coramage:BAAALAAECgMIAwAAAA==.Cozi:BAAALAAECgcIDQAAAA==.',Cp='Cplusmc:BAAALAADCgcIDgAAAA==.',Cr='Crapsnakula:BAAALAADCgYIBgAAAA==.',Da='Daddychill:BAAALAAECgcIDwAAAA==.Dagithicus:BAAALAADCggICAAAAA==.Dalarayne:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Darkbeast:BAAALAAECgYICwAAAA==.Datbigguy:BAAALAADCggICQAAAA==.Daten:BAAALAAECgcICgAAAA==.Dazshauran:BAAALAADCgMIAwAAAA==.',De='Decayed:BAAALAAECgIIAgAAAA==.Delindsong:BAAALAAECgMIAwAAAA==.Denzo:BAAALAADCgcIBwAAAA==.',Di='Diagonalli:BAAALAAECgMIAwAAAA==.Digital:BAAALAADCgcIBwAAAA==.',Dj='Djpriest:BAAALAADCgYIBgAAAA==.Djshadow:BAAALAADCgYIBgAAAA==.Djshadowhunt:BAAALAADCgUIBQAAAA==.Djshadowlock:BAAALAADCgcIBwAAAA==.',Do='Doofuss:BAAALAADCgMIAwAAAA==.Doruun:BAAALAAECgYIBAAAAA==.',Dr='Drakmon:BAAALAADCggICAAAAA==.Draktând:BAAALAAECgMIBAAAAA==.Draxxanne:BAAALAAECgMIBQAAAA==.Drunkenpanda:BAAALAAECgcIDgAAAA==.',Du='Dundorn:BAAALAADCggICAAAAA==.',Ec='Echö:BAAALAAECgcIDQAAAA==.',Ei='Eightbit:BAAALAADCgYIDwABLAADCggICAABAAAAAA==.Eillwinn:BAAALAADCgYIBwAAAA==.',El='Elaine:BAAALAADCgcICwAAAA==.Elberon:BAAALAADCgYIBAAAAA==.Eleins:BAAALAADCgYIBgAAAA==.Ellspeth:BAAALAAECgMIAwAAAA==.Eluda:BAAALAADCgIIAgAAAA==.Elwyn:BAAALAAECgIIAgAAAA==.',En='Enoch:BAAALAAECgIIAgAAAA==.',Er='Erowhen:BAAALAADCgYIBgAAAA==.Errane:BAAALAAECgMIAwABLAAECggIEwABAAAAAA==.Errol:BAAALAAECgMIAwAAAA==.',Es='Estelz:BAAALAADCgcIBAABLAAECgEIAQABAAAAAA==.',Fa='Fastjack:BAAALAADCgcIFQAAAA==.',Fe='Felbelle:BAAALAADCgEIAQAAAA==.',Fi='Fiadh:BAAALAADCggICAAAAA==.Fitco:BAAALAADCggICAAAAA==.',Fo='Forgé:BAAALAADCgcICAAAAA==.',Fr='Frantecks:BAAALAADCggIBwAAAA==.Freyä:BAAALAAECgMIBAAAAA==.Froosty:BAAALAADCgYIBgAAAA==.Frëyja:BAAALAADCgYIBgAAAA==.',['Fá']='Fáde:BAAALAAECgMIBwAAAA==.',Go='Goggles:BAAALAAECgYICQAAAA==.Gowtherpunch:BAAALAAECgcIDQAAAA==.',Gr='Gravewynd:BAAALAADCgYIBwAAAA==.Grimsweeper:BAAALAAECgcIDwAAAA==.Grimsy:BAAALAAECgEIAQAAAA==.Grêg:BAAALAADCgcIDgAAAA==.',Gu='Gulnn:BAAALAAECgYICgAAAA==.',Ha='Haelena:BAAALAADCggIDwAAAA==.Halteran:BAAALAADCgUIBQAAAA==.',He='Heartsfang:BAAALAADCgYIBAAAAA==.Heelboy:BAAALAAECgMIBAAAAA==.Helna:BAAALAADCggICwAAAA==.',Ho='Holychalk:BAAALAADCgYICgABLAAFFAEIAQABAAAAAA==.Holythile:BAAALAAECgQIBgAAAA==.Hopsblossom:BAAALAAECgIIAgAAAA==.',Il='Illidead:BAABLAAECoEWAAIDAAgIvyTZBAApAwADAAgIvyTZBAApAwAAAA==.Illooj:BAAALAAECggIEwAAAA==.',In='Indexes:BAAALAADCgcIEAAAAA==.Injection:BAABLAAECoEaAAMEAAgIPiNwBAAYAwAEAAgIPiNwBAAYAwAFAAMIICHGNQCTAAAAAA==.',Is='Ischiros:BAAALAADCggICAAAAA==.',Ja='Jaalla:BAAALAADCgcIBwAAAA==.Jabbadahut:BAAALAADCggICAAAAA==.Jastrae:BAAALAAECgYICAAAAA==.Jaxxis:BAAALAADCgcIFQAAAA==.Jayruid:BAAALAADCgEIAQAAAA==.Jazyara:BAAALAADCggIDwAAAA==.',Js='Jsins:BAAALAADCgcIBwAAAA==.',Ka='Kadereith:BAAALAAECgMIAwAAAA==.Kaitryn:BAAALAADCggIDgAAAA==.Kamethyst:BAAALAADCgYIBgABLAAECgcIDgABAAAAAA==.Kamikazim:BAAALAADCggIDAABLAAECgcIDgABAAAAAA==.Kammunion:BAAALAADCggIFgABLAAECgcIDgABAAAAAA==.Kampelis:BAAALAAECgEIAQAAAA==.Kamphiyer:BAAALAAECgcIDgAAAA==.Kantheal:BAAALAAECgMIAwAAAA==.Kaulana:BAAALAAECgEIAQAAAA==.',Ke='Kellee:BAAALAADCggICgAAAA==.',Kn='Knùsê:BAAALAADCgcIBwAAAA==.',Kr='Kravex:BAAALAAECgUIBgAAAA==.Kronik:BAAALAADCgcIBwAAAA==.',Kw='Kwong:BAAALAAECgMIAwABLAAFFAEIAQABAAAAAA==.',Ky='Kylana:BAAALAADCgIIAgAAAA==.',La='Larayvia:BAAALAAECgYIDQAAAA==.Lateralis:BAAALAAECgMIBAAAAA==.Lazerpelican:BAAALAAECgYIBgAAAA==.',Le='Leesala:BAAALAAECgcIDAAAAA==.',Li='Lidoria:BAAALAADCggICgABLAAECggIGgAEAD4jAA==.Liera:BAAALAAECgEIAQAAAA==.Liliatrix:BAAALAADCgcIDQAAAA==.Lillabet:BAAALAADCgYICwAAAA==.Lilpoo:BAAALAAECgMIAwAAAA==.Lithice:BAAALAADCgMIAwAAAA==.',Lo='Loial:BAAALAAECgYICgAAAA==.',['Lí']='Límpy:BAAALAAECgIIBQAAAA==.',Ma='Magnakilro:BAAALAAECgQIBAAAAA==.Maleficus:BAAALAADCgYICAABLAADCgcIDQABAAAAAA==.Malo:BAEALAADCgcIBwABLAAECgQIBgABAAAAAA==.Markdfordeth:BAAALAADCgUIBQAAAA==.Mattingly:BAAALAADCggICwAAAA==.',Me='Meatsupreme:BAAALAAECgYICgAAAA==.Mesophistole:BAAALAADCggIEwAAAA==.',Mi='Microclick:BAAALAADCggIFQAAAA==.Mileenä:BAAALAAECgIIAgAAAA==.Minimim:BAAALAADCgYIBgAAAA==.',Mo='Modification:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Mograiné:BAAALAADCggICwAAAA==.Monkaw:BAAALAAECgQIBAAAAA==.Monkey:BAAALAADCgQIBAABLAAECgMIBQABAAAAAA==.Moong:BAAALAAECgMIBAAAAA==.Morta:BAEALAAECgQIBgAAAA==.',Mu='Mugga:BAAALAAECgcIDQAAAA==.Murderella:BAAALAADCgMIAwAAAA==.',My='Myoren:BAAALAAECgEIAQAAAA==.',['Mí']='Míasma:BAAALAADCggICgAAAA==.',['Mö']='Mörph:BAAALAADCgMIAwAAAA==.',Na='Nami:BAAALAAECgIIAgAAAA==.Narrodus:BAAALAAECgMIAwAAAA==.Nashtir:BAAALAADCggIDAAAAA==.Nashty:BAAALAADCgcICwABLAADCggIDAABAAAAAA==.Natharos:BAAALAADCgYIBgAAAA==.',Ne='Nekirikasho:BAAALAAECggIAwAAAA==.',Ni='Niasha:BAAALAADCgMIAQAAAA==.Nilah:BAAALAADCgIIAgAAAA==.Nimbus:BAAALAADCggICAAAAA==.Nimike:BAAALAAECgYIDQAAAA==.',No='Notthepope:BAAALAAECgIIAgAAAA==.',Ny='Nytenyte:BAAALAADCgcIBwAAAA==.Nytesage:BAABLAAECoEVAAIGAAgIviFpAAALAwAGAAgIviFpAAALAwAAAA==.',Od='Odyssey:BAAALAAECgMIAwAAAA==.',Ok='Okrimos:BAAALAAECgMIBQAAAA==.',Or='Orgrom:BAAALAAECggIBgAAAA==.',Ot='Otta:BAAALAAECgYIBgAAAA==.',Ox='Oxi:BAAALAAECgcIDgAAAA==.',Oz='Ozo:BAAALAADCgcIEwAAAA==.',Pa='Painavolian:BAAALAAECgYIDgAAAA==.Pariccarn:BAAALAAECgQIBgAAAA==.',Pe='Peeches:BAAALAAECgQIBgAAAA==.',Ph='Phillidan:BAAALAADCggICAAAAA==.',Pi='Pikkoga:BAAALAADCggIDwAAAA==.',Po='Poggies:BAAALAADCgIIAgAAAA==.Potatopriest:BAAALAAECgYIEAAAAA==.',Pr='Praynes:BAAALAAECgcIDQAAAA==.Proserpinae:BAAALAAECgIIAgAAAA==.',Ra='Rach:BAAALAADCgcIBgAAAA==.Raimi:BAAALAADCggIDwAAAA==.Rasz:BAAALAADCggICAAAAA==.Raszy:BAAALAADCggICAAAAA==.Razji:BAAALAAECgYICgAAAA==.',Re='Rekaas:BAAALAADCgcIBwAAAA==.Rekd:BAAALAAECgEIAQAAAA==.',Ri='Rickyclouded:BAAALAADCggICAAAAA==.Rinxi:BAAALAADCgQIBAAAAA==.',Ro='Rocknwolf:BAAALAADCgEIAQAAAA==.Rokham:BAAALAADCgEIAQAAAA==.Roscoelock:BAAALAADCgYIBgAAAA==.',Ru='Rudolfo:BAAALAADCggICAAAAA==.',['Rà']='Ràidèn:BAAALAAECgYICAAAAA==.',['Rá']='Ráyne:BAAALAADCgcIBwAAAA==.',['Rø']='Rømulus:BAAALAAECgEIAQAAAA==.',Sa='Sadeel:BAAALAAECgcIDQAAAA==.Sadewolf:BAAALAAECgYICgAAAA==.Saijin:BAAALAADCgcICgAAAA==.Samgal:BAAALAAECgMIAwAAAA==.Sansura:BAAALAADCggICAAAAA==.Sarinis:BAAALAAECgIIAgAAAA==.Sassmate:BAAALAADCggIDwAAAA==.Satyra:BAAALAAECgYICQAAAA==.Savage:BAAALAADCgcIBwAAAA==.',Sc='Schamanin:BAAALAADCggIDwAAAA==.Scipio:BAAALAADCgcIBwAAAA==.',Se='Seaniangnome:BAAALAAECgMIAwAAAQ==.Selinna:BAAALAAECgIIAgAAAA==.',Sh='Shadowstáb:BAAALAADCggIHQAAAA==.Shadybrat:BAAALAAECgIIBAABLAAECgYIBgABAAAAAA==.Shaladin:BAAALAADCggIAwAAAA==.Shamlazy:BAAALAAECgYIDQAAAA==.Shedrugsme:BAAALAAECgMIAwAAAA==.Sheev:BAAALAADCggICAABLAADCggICAABAAAAAA==.Shelby:BAAALAAECgEIAQAAAA==.Shockchalk:BAAALAAFFAEIAQAAAA==.Shulk:BAAALAAECgMIBQAAAA==.',Si='Sibbiah:BAAALAADCgcICgAAAA==.',Sk='Skaðï:BAAALAAECgcIDQAAAA==.',Sm='Smashtastic:BAAALAADCgcIBwAAAA==.Smellybeefs:BAAALAADCgYIDAABLAAECgcICgABAAAAAA==.Smellybelly:BAAALAADCgQIBAABLAAECgcICgABAAAAAA==.Smellylock:BAAALAAECgcICgAAAA==.',Sn='Sneakchalk:BAAALAADCgcIBwABLAAFFAEIAQABAAAAAA==.Snâil:BAAALAADCggIGAAAAA==.',So='Softkíss:BAAALAADCgcIBwAAAA==.',Sp='Spicycurryy:BAAALAAECgUIBgAAAA==.',St='Stainns:BAAALAAECgYICAAAAA==.Strahm:BAAALAADCgcIFQAAAA==.Størmfang:BAAALAADCgYIBgAAAA==.',Su='Summonbrick:BAAALAADCgcIEQAAAA==.Superjinn:BAAALAAECgEIAQABLAAECggIGgAEAD4jAA==.',Sy='Syine:BAAALAADCgcICgAAAA==.Syndaar:BAAALAAECgYICQAAAA==.',Ta='Talzar:BAAALAADCgcIFQAAAA==.Taynan:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.Tazdrin:BAAALAAECgcIDQAAAA==.Taztraz:BAAALAADCgcICwAAAA==.',Te='Tenamic:BAAALAAECgUICQAAAA==.Terminusado:BAAALAADCgcIDgAAAA==.Termoonusado:BAAALAAECgcIDQAAAA==.',Th='Thaeldrayne:BAAALAADCggICAAAAA==.Thillar:BAAALAADCgEIAQAAAA==.Thrallanon:BAAALAADCggICAAAAA==.',Ti='Tihj:BAAALAAECggICAAAAA==.',To='Topaze:BAAALAAECgUICwAAAA==.Totemcharger:BAAALAAECgQIBAAAAA==.',Tr='Tripshadow:BAAALAAECgMIAwAAAA==.',Tu='Turntsnaco:BAAALAAECgYICgAAAA==.Tusk:BAAALAAECgMIBAAAAA==.',Un='Unafhaen:BAAALAAECgEIAQAAAA==.Undeadjones:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.',Us='Usmccpl:BAAALAAECgMIAwAAAA==.',Uu='Uukla:BAAALAAECgYICwAAAA==.',Va='Valeigh:BAAALAAECgIIAgAAAA==.Valengarde:BAAALAAECgUIBQAAAA==.Vanissra:BAAALAADCggIDAAAAA==.Vannix:BAAALAAECgYIDAAAAA==.Vargrom:BAAALAAECgYIBgAAAA==.',Ve='Velthas:BAAALAADCgUIAQAAAA==.',Vi='Villarael:BAAALAADCggICAAAAA==.Virmethir:BAAALAADCggIDAAAAA==.',Vo='Voltaren:BAAALAAECgMIBAAAAA==.',Vx='Vxs:BAAALAAECgEIAQAAAA==.',Vy='Vyndrolan:BAABLAAECoEVAAIHAAgIJB3DDwCOAgAHAAgIJB3DDwCOAgAAAA==.',We='Weinermeat:BAAALAAECgQIBQAAAA==.',Wh='Wharv:BAAALAADCgcIDQAAAA==.',Wi='Wiwi:BAAALAAECgcIDAAAAA==.',Wo='Worglock:BAAALAAECgUIBQABLAAECgMIAwABAAAAAQ==.',Wy='Wyerforret:BAAALAAECgMIAwAAAA==.',['Xö']='Xön:BAAALAADCgcICwAAAA==.',Ya='Yalda:BAAALAADCggICAAAAA==.Yamaha:BAAALAAECgIIAgAAAA==.Yasakte:BAAALAAECgMIAwAAAA==.',Ye='Yena:BAAALAAECgEIAQAAAA==.',Yo='Yoseph:BAAALAAECgMIAwAAAA==.',Za='Zake:BAAALAAECgIIAgAAAA==.Zaringo:BAAALAAECggIAgAAAA==.Zaror:BAAALAADCgcIBwAAAA==.',Ze='Zect:BAAALAAECgIIAgAAAA==.Zerrie:BAAALAAECgEIAQAAAA==.',Zi='Ziêg:BAAALAAECgcIDAAAAA==.',Zo='Zorgas:BAAALAAECggIBgAAAA==.Zoz:BAAALAADCgYIDQAAAA==.',Zu='Zulfrik:BAAALAAECgUICQAAAA==.',['Æd']='Ædolin:BAAALAAECgEIAQAAAA==.',['Ëm']='Ëmma:BAAALAAECgYICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end