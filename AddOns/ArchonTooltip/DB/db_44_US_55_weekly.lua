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
 local lookup = {'Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','Priest-Shadow','Priest-Discipline','Priest-Holy','Evoker-Preservation','Hunter-Marksmanship','Warrior-Fury','Evoker-Devastation','Mage-Frost','Monk-Brewmaster','Paladin-Retribution','Druid-Balance','DemonHunter-Havoc','Mage-Arcane',}; local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acheniris:BAAALAAECgIIAgAAAA==.',Ae='Aeviee:BAAALAADCgcICgAAAA==.',Ag='Agrippa:BAAALAAECgIIAgAAAA==.',Ai='Airwavez:BAAALAAECggIDAAAAA==.',Al='Aldormu:BAAALAAECgYICQAAAA==.Alessia:BAAALAAECgMIBQAAAA==.Alexxa:BAAALAAECgUICQAAAA==.Allaryia:BAAALAADCggICAAAAA==.Allura:BAAALAADCggICAAAAA==.Altra:BAAALAAECgcICwAAAA==.',Am='Amoeta:BAAALAAECgYICQAAAA==.Amzod:BAAALAADCgYIBgAAAA==.',An='Angry:BAAALAADCgUIBQAAAA==.',Ar='Arkimedes:BAAALAADCgcIBwAAAA==.',As='Ashenback:BAABLAAECoEVAAMBAAgIpBwTFQAJAgABAAcIXRsTFQAJAgACAAYIlBwGGADsAQAAAA==.Asomyrh:BAAALAAECgMIBAAAAA==.',At='Atillar:BAAALAAECgIIAgAAAA==.',Au='Aughrah:BAAALAADCgcIBwAAAA==.Aurielle:BAAALAADCgYIBgAAAA==.',Aw='Awøl:BAAALAAECgIIAgAAAA==.',Ba='Baillor:BAAALAADCggICAAAAA==.Balkanud:BAAALAAECgYICAAAAA==.Bananer:BAAALAADCgcIDAAAAA==.Banonzarath:BAAALAADCgIIAwAAAA==.Barrysoetoro:BAAALAADCgUIBQAAAA==.',Be='Beebler:BAAALAAECgIIAgAAAA==.Bekroh:BAAALAAECgYICQAAAA==.Bestt:BAAALAAECgUIBwAAAA==.',Bi='Biggestpete:BAAALAAECgEIAgAAAA==.Biggiew:BAAALAAECgYIDQAAAA==.Bigknight:BAAALAADCgMIAwAAAA==.Bigpeet:BAAALAAECgMIBAAAAA==.',Bl='Bluestars:BAAALAAECgMIBAAAAA==.',Bn='Bnahabra:BAAALAADCgYIDAAAAA==.',Bo='Bobsham:BAAALAADCgIIAwAAAA==.Bontao:BAABLAAECoEWAAIDAAgIUiBDCADdAgADAAgIUiBDCADdAgAAAA==.Borstenne:BAAALAAECgcIDQAAAA==.Bosspawz:BAAALAADCgcIBwAAAA==.',Br='Brake:BAAALAAECgUICgAAAA==.Breseshh:BAAALAAECgcIDQAAAA==.Bresew:BAAALAADCgMIAwABLAAECgcIDQAEAAAAAA==.Brickette:BAABLAAECoEWAAQFAAgIkhiaFgDzAQAFAAcIlhaaFgDzAQAGAAYI1QgYCgAOAQAHAAEIngPYWQAxAAAAAA==.Brísíngr:BAAALAADCgUIBQAAAA==.',['Bé']='Béstt:BAAALAADCgEIAQAAAA==.',Ca='Cadilak:BAAALAAECgcIDQAAAA==.Cazren:BAAALAAECggIAwAAAA==.',Ce='Ceres:BAAALAADCgEIAQAAAA==.',Ch='Charcuterie:BAAALAADCgcIDAABLAAECgcIDQAEAAAAAA==.Chocolatchan:BAAALAADCgIIAgAAAA==.Chowderhead:BAAALAAECgEIAQAAAA==.',Ci='Cileb:BAAALAAECgMIBAAAAA==.Civik:BAAALAAECgcIDwAAAA==.',Co='Condamned:BAAALAAECgYIDgAAAA==.Copperit:BAAALAAECgcIDgAAAA==.Cornburglar:BAAALAAECgMIBAAAAA==.',Cr='Crunchwrap:BAAALAADCggIFAAAAA==.Crúsader:BAAALAAECgcIDwAAAA==.',Cy='Cygon:BAAALAAECgMIAwAAAA==.',Da='Dadcolvin:BAAALAADCgMIAwAAAA==.Daddiedk:BAAALAAECgYIDgAAAA==.Damascus:BAAALAAECgIIAgAAAA==.Damncats:BAAALAAECgMIAwAAAA==.Danielsboone:BAAALAAECgMIAwAAAA==.Dantusar:BAAALAAECgUIBQAAAA==.Daraen:BAAALAADCggICgAAAA==.Darkbrigade:BAAALAADCgIIAgAAAA==.',De='Dearth:BAEALAAECgcIDAAAAA==.Deldrin:BAAALAADCgYICAAAAA==.Demilios:BAAALAADCgIIAgAAAA==.Demona:BAAALAAECgcIDQAAAA==.Demoth:BAAALAAECgIIAwAAAA==.Derptron:BAAALAADCggICAAAAA==.Desirin:BAAALAAECgMIBAAAAA==.Dethtodestny:BAAALAADCgQIBAAAAA==.Devira:BAAALAAFFAEIAQAAAA==.',Di='Dilutedret:BAAALAADCgEIAQABLAAECgYICAAEAAAAAA==.Dirtylöbster:BAAALAAECgYIDgAAAA==.Disabel:BAAALAADCgIIAwAAAA==.',Dl='Dltdjr:BAAALAAECgYICAAAAA==.',Do='Doolittle:BAAALAAECgIIBAAAAA==.Dorky:BAAALAADCgcIDAAAAA==.Dorns:BAAALAADCggIDQAAAA==.',Dr='Dralshock:BAAALAAECgMIBAAAAA==.Dranight:BAAALAAECgEIAQABLAAECgcIDwAEAAAAAA==.Drekbeef:BAAALAADCggICwAAAA==.Droo:BAAALAADCggICQABLAAECgEIAQAEAAAAAA==.Drublood:BAAALAAECgEIAQAAAA==.Drunal:BAAALAADCgcIBwABLAAECgEIAQAEAAAAAA==.',Du='Dune:BAAALAAECgMIBAAAAA==.Duwork:BAAALAAECgYICAAAAA==.Duxxi:BAAALAAECgMIBQAAAA==.',Eb='Eblouisse:BAAALAADCggIDQAAAA==.',Ec='Eckle:BAAALAAECgYIBgAAAA==.',Eh='Ehzhump:BAAALAADCgEIAQAAAA==.',El='Elladon:BAAALAADCgcICgAAAA==.',Em='Emilya:BAAALAAECgMIAwAAAA==.Emrys:BAAALAADCgMIAwAAAA==.',Fa='Faithastray:BAAALAADCgEIAQAAAA==.',Fe='Felondar:BAAALAADCggIDwAAAA==.Ferarro:BAAALAAECgEIAQAAAA==.',Fi='Firrecrotch:BAAALAADCggIFAAAAA==.Firulais:BAAALAAECgIIAwAAAA==.',Fl='Flannix:BAAALAAECgIIAgAAAA==.Flysky:BAABLAAECoEVAAIIAAgI+CUvAABxAwAIAAgI+CUvAABxAwAAAA==.',Fo='Foxsake:BAAALAADCggICAAAAA==.',Fr='Freakmeout:BAAALAADCggIFwAAAA==.Freezingrain:BAAALAADCggICAAAAA==.Frostyslams:BAAALAADCgEIAQAAAA==.',Fu='Fubear:BAAALAAECgUIBQAAAA==.Fuknar:BAAALAADCggICAAAAA==.',Ga='Galise:BAAALAADCggIDwAAAA==.Garduuk:BAAALAAECgYIDwAAAA==.Garynud:BAAALAADCggICAAAAA==.',Ge='Geel:BAAALAAECgcIDQAAAA==.Gehennas:BAAALAADCgYICAAAAA==.',Go='Gotlieb:BAAALAAECgEIAQAAAA==.',Gr='Gratefultodd:BAAALAADCgcIBwAAAA==.Gravyytrain:BAAALAAECgYIDgAAAA==.Griffini:BAAALAADCgYIBgAAAA==.Grrahtahtah:BAABLAAECoEXAAIJAAgIgiTnAgAbAwAJAAgIgiTnAgAbAwAAAA==.',Ha='Hambananna:BAAALAADCgYIAgAAAA==.Hardboyfred:BAAALAADCgMIAwAAAA==.Haylon:BAAALAADCgYIBgAAAA==.',He='Healßot:BAAALAADCgcIBwAAAA==.Heartless:BAAALAADCgYIBgAAAA==.Helhunter:BAAALAAECgcIDwAAAA==.Hellfrost:BAAALAADCgcIDQAAAA==.',Hi='Hippysmasher:BAAALAAECgYICwAAAA==.',Ho='Holyców:BAAALAAECgEIAQAAAA==.Holyhooters:BAAALAAECgQIBwAAAA==.Homebrew:BAAALAAECgQICQAAAA==.Honour:BAAALAAECgcIDwAAAA==.Hordeling:BAAALAADCgcIBwABLAAECgMIAwAEAAAAAA==.Hornstar:BAAALAAECgIIBAAAAA==.Hotshot:BAAALAADCggICgAAAA==.',Hu='Hupa:BAAALAAECgYIDgAAAA==.',Ia='Iamheyo:BAAALAAECgYICAAAAA==.',Id='Idiotbreath:BAAALAAECgYIDgAAAA==.',In='Infamouz:BAAALAAECgIIBAAAAA==.',It='Itsthewarlok:BAAALAAECgYIDgAAAA==.',Ja='Jason:BAAALAADCgcIBwAAAA==.Jasz:BAAALAAECgMIBQAAAA==.',Je='Jessislost:BAAALAADCgcICwAAAA==.',Jo='Jotaro:BAAALAADCgQICAAAAA==.',Ka='Kairei:BAAALAAECgIIAgAAAA==.Kalda:BAAALAADCgcIFwAAAA==.Kamanactali:BAAALAADCggIDgAAAA==.Katrazar:BAAALAADCgMIAwAAAA==.Kazoq:BAAALAAECgEIAQAAAA==.',Ke='Kerafyrm:BAAALAAECgEIAQABLAAECggIFQABAKQcAA==.Kernel:BAAALAAECgEIAQAAAA==.',Kh='Kham:BAABLAAECoEUAAIKAAgIqxhjDgB7AgAKAAgIqxhjDgB7AgAAAA==.Khronnos:BAAALAADCgMIAwAAAA==.',Ko='Kokeovrdose:BAAALAADCgEIAQAAAA==.',Kp='Kpop:BAAALAADCgQIBAAAAA==.',Kr='Krangis:BAAALAAECgYICwAAAA==.',Ku='Kuvare:BAAALAADCgUIBQAAAA==.',['Kå']='Kårmå:BAAALAADCggIFgAAAA==.',La='Laocoon:BAAALAADCggICAABLAAECgQIBwAEAAAAAA==.Larg:BAAALAADCggIEAAAAA==.',Le='Leadzorz:BAAALAAECgIIBAAAAA==.Leaok:BAAALAADCgcIDAAAAA==.',Li='Lissara:BAAALAADCggICAAAAA==.Littlemac:BAAALAAECgEIAQAAAA==.Lizzydh:BAAALAAECgcIDQAAAA==.',Lo='Lockdownlol:BAAALAAECgEIAQABLAAECgYICAAEAAAAAA==.Lockfred:BAAALAAECgEIAQAAAA==.',Lu='Luluh:BAAALAADCgYICQAAAA==.',Ma='Mageslayer:BAAALAAECgIIAwAAAA==.Magistaer:BAAALAAECgIIAwAAAA==.Mak:BAAALAAECgUIBQAAAA==.Malanar:BAAALAAECgMIBAAAAA==.Manamanaa:BAAALAAECgMIAwABLAAECgQICAAEAAAAAA==.Mavrik:BAAALAAECgcIDwAAAA==.',Mc='Mckay:BAAALAAECggIAQAAAA==.',Me='Meatmagic:BAAALAADCggIFQAAAA==.Megapunk:BAAALAADCgcIBwAAAA==.Meudayr:BAEALAAECgMIBAAAAA==.',Mi='Mimimochi:BAAALAADCgcIBwAAAA==.Mirari:BAAALAAECgcIDQAAAA==.',Mo='Mojorisin:BAAALAAECgMIAwAAAA==.Moodew:BAAALAADCgYIBgABLAAECgMIAwAEAAAAAA==.Moody:BAAALAAECgEIAQAAAA==.Moozee:BAAALAAECgYIDgAAAA==.Moozlock:BAAALAAECgEIAQAAAA==.Mosspaws:BAAALAAECgYIDgAAAA==.',My='Myeyes:BAAALAADCggIDQAAAA==.Mystshedevil:BAAALAADCgcIBwAAAA==.',Ni='Nicolbolas:BAAALAADCgcIBwAAAA==.',No='Nocturnos:BAAALAAECgUIDQAAAA==.Noequal:BAAALAAECgUIBQAAAA==.Nohmojo:BAAALAAECgQIBQAAAA==.Novium:BAAALAADCgIIAgAAAA==.Noxta:BAAALAAECgMIAwAAAA==.',Nu='Numonixx:BAABLAAECoEVAAILAAgIIRZ4DABIAgALAAgIIRZ4DABIAgAAAA==.',Ny='Nymage:BAAALAAECgQICAAAAA==.',['Nä']='Näd:BAAALAADCgIIAgAAAA==.',Ok='Okaerisan:BAAALAAECgEIAQAAAA==.',Ol='Olord:BAAALAADCgQIBAABLAADCggIDQAEAAAAAA==.',Op='Ophil:BAABLAAECoEUAAIMAAgI8yFvAgAGAwAMAAgI8yFvAgAGAwAAAA==.Ophilum:BAAALAADCggICAAAAA==.',Or='Orack:BAAALAAECgMIBgAAAA==.Orengar:BAAALAADCgMIAwAAAA==.',Ou='Outlast:BAAALAAECgcIDgAAAA==.',Pa='Panblind:BAAALAAFFAEIAQAAAA==.Parmigiano:BAAALAAECgcIDQAAAA==.',Pe='Peanought:BAAALAAECgMIBwAAAA==.',Pi='Pijak:BAAALAAECgIIBAAAAA==.',Po='Poah:BAACLAAFFIEIAAINAAMIRya/AABbAQANAAMIRya/AABbAQAsAAQKgRgAAg0ACAj9JgUAAK0DAA0ACAj9JgUAAK0DAAAA.Poahrogue:BAAALAAECgYIDwAAAA==.Potatoskiner:BAAALAADCgcIBwAAAA==.',Pr='Primalform:BAAALAADCgUIBQAAAA==.',Ps='Psycodk:BAAALAAECgIIAgAAAA==.',Pu='Puggernaut:BAAALAADCgUIBQAAAA==.Pumpin:BAAALAADCgUICgAAAA==.',Py='Pyjamas:BAAALAAECgYIBgAAAA==.',Ra='Raf:BAAALAADCggICAAAAA==.',Re='Reaperjoe:BAAALAAECgMIAwAAAA==.Reckoner:BAAALAADCggIDgAAAA==.Rekpriest:BAAALAADCgcIBwABLAAECggIFgAOAGMlAA==.Rektributio:BAABLAAECoEWAAIOAAgIYyVWAgBiAwAOAAgIYyVWAgBiAwAAAA==.Revalation:BAAALAAECgMIBAAAAA==.',Ro='Roarim:BAAALAAECgMIAwAAAA==.Rodfarva:BAAALAAECgYICAAAAA==.Rorymcilroy:BAAALAAECgYIDAAAAA==.',Sa='Saifrah:BAAALAADCgcIBwAAAA==.Sake:BAAALAADCggIDwAAAA==.Salmiana:BAAALAADCgEIAQAAAA==.Saucerdote:BAAALAAECgUIBQAAAA==.Saucy:BAAALAADCggIDwAAAA==.',Se='Selkie:BAAALAAECgMIAwAAAA==.Semir:BAAALAADCggICAAAAA==.',Sh='Shakakhan:BAAALAADCggICAABLAAECgYICAAEAAAAAA==.Shambeau:BAAALAADCggIEAAAAA==.Shaminbo:BAAALAADCgcICwAAAA==.Shamshielder:BAAALAAECgUIBQAAAA==.Sharick:BAAALAAECgEIAQAAAA==.Shawlee:BAAALAAECgYICQAAAA==.Shettrah:BAABLAAECoEWAAIPAAgIlx4GBwDOAgAPAAgIlx4GBwDOAgAAAA==.Shuck:BAAALAADCgMIAwAAAA==.',Si='Sigurd:BAAALAADCgQIBAAAAA==.Siickboy:BAAALAADCgcIEwAAAA==.Sijious:BAAALAAECgEIAQAAAA==.Silvin:BAAALAAECgEIAQAAAA==.Simismephis:BAAALAAECgYIDAAAAA==.',Sk='Skora:BAAALAAECgcIDAAAAA==.Skyli:BAAALAAECgEIAQABLAAECgcIDwAEAAAAAA==.',Sl='Slisce:BAAALAAECgMIAwAAAA==.',So='Somi:BAAALAAECgYIDAAAAA==.Sosuke:BAAALAAECgYIBwAAAA==.',Sp='Sp:BAAALAADCggIEAAAAA==.Spacejamdvd:BAAALAAECgMIAwABLAAECgYIDgAEAAAAAA==.',St='Stankyleg:BAABLAAECoEWAAMJAAgIrR72BwCiAgAJAAgILB72BwCiAgADAAQILRLXRgDwAAAAAA==.Starna:BAAALAADCgUIBQAAAA==.Strangemagic:BAAALAAECgMIBAAAAA==.Stuko:BAAALAADCggICQAAAA==.',Su='Supercoolzip:BAAALAADCgcICAAAAA==.',Sv='Svelea:BAEALAADCggICAAAAA==.',Sy='Sylphrena:BAAALAAECgcIDQAAAA==.Symbolism:BAAALAADCggICwAAAA==.',Ta='Talla:BAAALAAECgcIDwAAAA==.Tammey:BAAALAADCggICAAAAA==.',Te='Tewshort:BAAALAADCgUIBQAAAA==.',Th='Thorfyna:BAAALAAECgMIBAAAAA==.Threzk:BAAALAAECgYIDgAAAA==.',Ti='Ticklehunt:BAAALAAECgYIDgAAAA==.Tigerrwoods:BAAALAAECgIIAgAAAA==.',To='Tohk:BAABLAAECoEWAAIQAAgIyB7oDQCsAgAQAAgIyB7oDQCsAgAAAA==.Tollee:BAAALAADCgYIBgAAAA==.Tontiamat:BAAALAAECgYIDgAAAA==.Tontier:BAAALAAECgEIAQABLAAECgYIDgAEAAAAAA==.',Tr='Treeple:BAAALAAECgMIBAAAAA==.Treily:BAAALAAECgMIAwAAAA==.Tricket:BAAALAADCgYICQAAAA==.Trojaxx:BAAALAAECgQIBwAAAA==.Truestorm:BAAALAAECgEIAQAAAA==.Truheals:BAAALAAECgMIAwAAAA==.',Tu='Tuchi:BAAALAAFFAIIAgAAAA==.',Tw='Twingunstunn:BAAALAAECgMIAwAAAA==.',['Tà']='Tàcobelle:BAAALAAECgIIAgAAAA==.',Un='Undrverse:BAAALAADCggIDwAAAA==.',Up='Upsettingjoe:BAAALAADCgUIBQAAAA==.Uptownpimp:BAAALAAECgYICQAAAA==.',Ur='Urokk:BAAALAADCggIDQAAAA==.',Va='Vanicton:BAAALAAFFAIIAgAAAA==.Varanis:BAAALAAECgcIEwAAAA==.',Ve='Vem:BAAALAAECgMIBAAAAA==.Veriale:BAAALAAECgIIBAAAAA==.Verra:BAAALAAECgEIAQAAAA==.',Vy='Vynlaeron:BAAALAADCgcIFwAAAA==.',Wa='Wampa:BAAALAADCggIEwAAAA==.Wanderblue:BAAALAADCgcIDAAAAA==.Wangstah:BAAALAAECgMIAwAAAA==.Wargazum:BAAALAADCgUIBQAAAA==.Waytogoteam:BAAALAAECgcICQAAAA==.',We='Weeple:BAAALAADCgcIEQABLAAECgMIBAAEAAAAAA==.Weiss:BAABLAAECoEWAAIRAAgIJCPFBgAPAwARAAgIJCPFBgAPAwAAAA==.',Wo='Wonghau:BAAALAADCgYIBgAAAA==.',Wr='Wreckfest:BAAALAAECgYICQAAAA==.',Wy='Wyldspirit:BAAALAADCgcIBwAAAA==.',Ye='Yem:BAAALAAECgMIBAAAAA==.',Yu='Yuli:BAAALAADCgEIAQAAAA==.',Ze='Zedsdead:BAAALAADCgcICAAAAA==.Zepherot:BAAALAAECgMIAwAAAA==.Zet:BAAALAADCgYIBgAAAA==.Zetsu:BAAALAAECgYICgAAAA==.',Zh='Zhenya:BAAALAAECgcIDQAAAA==.',Zi='Zippit:BAAALAADCgcICwAAAA==.Zipzombie:BAAALAADCgQIBAAAAA==.',Zu='Zuga:BAAALAAECgYICQAAAA==.',['Zë']='Zët:BAAALAADCggICwAAAA==.',['Ôb']='Ôbelix:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end