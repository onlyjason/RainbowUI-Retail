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
 local lookup = {'Hunter-Marksmanship','Unknown-Unknown','Mage-Arcane','Mage-Frost','Warrior-Protection','DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','Druid-Restoration','Priest-Shadow','Rogue-Assassination','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Hunter-BeastMastery','Monk-Mistweaver','Rogue-Subtlety',}; local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adelphie:BAAALAAECggIDwAAAA==.Ado:BAAALAAECgYICAAAAA==.Adroc:BAAALAADCgQIBgAAAA==.',Ae='Ae:BAAALAADCgcIDgAAAA==.Aelyna:BAAALAADCgQIBAAAAA==.',Ah='Ahpuch:BAAALAAECgIIAgAAAA==.',Ai='Aidasul:BAAALAAECgIIAgAAAA==.',Al='Alkazaaro:BAAALAADCgcIBwAAAA==.Alpacalypse:BAAALAAECgYICgAAAA==.Alvar:BAAALAADCgYIBwAAAA==.',An='Antii:BAAALAADCgcIBwAAAA==.',Ap='Applejackz:BAAALAAECgMIBAAAAA==.',Ar='Araceae:BAAALAADCgUIBQAAAA==.Ariaz:BAAALAADCgcIBwAAAA==.Arkatt:BAAALAAECgcIDgAAAA==.Arrowgance:BAABLAAECoEUAAIBAAcI8RprEQD+AQABAAcI8RprEQD+AQAAAA==.Arvard:BAAALAADCggIDwAAAA==.',As='Ascrod:BAAALAAFFAEIAQABLAAECgMIAwACAAAAAA==.Ashakh:BAAALAAECggIEQAAAA==.Ashyra:BAAALAADCggICAABLAAECggIEQACAAAAAA==.',At='Atcjedi:BAAALAAECgYICAAAAA==.Atmospherelo:BAAALAAECgIIAgABLAAECggIGAADAB8lAA==.Atmospherez:BAABLAAECoEYAAMDAAgIHyWVBQAeAwADAAgI/ySVBQAeAwAEAAIIwyapJQDlAAAAAA==.',Av='Avaeya:BAAALAADCgcIBwAAAA==.',Ba='Baalsdruid:BAAALAAECgEIAQAAAA==.Badhealz:BAAALAADCgQIBAAAAA==.Banzan:BAAALAADCgUIBQAAAA==.Baubeebane:BAAALAADCgQICQAAAA==.',Bd='Bdikd:BAAALAAECgEIAQAAAA==.',Be='Beeswifty:BAAALAAECggICAAAAA==.Bekzarn:BAAALAADCggICAABLAAECgYIDQACAAAAAA==.Bellasnow:BAAALAADCgcIDgAAAA==.',Bi='Billyblunt:BAAALAADCgcIBgAAAA==.Bitta:BAAALAADCggIDgAAAA==.',Bl='Blackked:BAACLAAFFIEHAAIFAAQIPBLpAAAwAQAFAAQIPBLpAAAwAQAsAAQKgRcAAgUACAjvIHgDANcCAAUACAjvIHgDANcCAAAA.Blax:BAAALAAECgYIBgAAAA==.Blindhugs:BAAALAAECgUIBwAAAA==.Blindsky:BAAALAAECgYIBgAAAA==.Blooddh:BAAALAAECgMIBAAAAA==.Bloodypoeki:BAAALAADCgUIBQAAAA==.Bluebeetle:BAAALAADCggICAAAAA==.',Bo='Boeuf:BAAALAADCggICAABLAAECgUIBwACAAAAAA==.Boicrystian:BAAALAAECgEIAQAAAA==.Bookitty:BAAALAADCggICAAAAA==.Bowvendor:BAAALAAECgMIAwAAAA==.',Br='Brainrot:BAABLAAECoEUAAMGAAgINx8aGgAtAgAGAAcI/R0aGgAtAgAHAAMIKCViFwBBAQAAAA==.Brommix:BAAALAAECgEIAQAAAA==.',Bu='Buhbles:BAABLAAECoEYAAMIAAgI/yAhBQD9AgAIAAgI/yAhBQD9AgAJAAUIrAJIQwCGAAAAAA==.Bullshiitake:BAAALAADCggIEAAAAA==.',Ca='Caffinated:BAAALAADCgUICgAAAA==.Callum:BAAALAAECgEIAQAAAA==.Cambio:BAAALAAECgMIAwABLAAECgYICAACAAAAAA==.Capo:BAAALAADCgcIBwAAAA==.Carloshot:BAAALAAECgcICAAAAA==.Cauterize:BAAALAADCgYIBgAAAA==.Cavalaris:BAAALAADCggICAAAAA==.',Ce='Celesti:BAAALAAECgMIBQAAAA==.',Ch='Chickensalad:BAAALAAECgEIAQAAAA==.Chubsy:BAAALAAECgYIDwAAAA==.',Ci='Cileo:BAAALAAECgEIAQAAAA==.Cinamen:BAAALAAECgEIAQAAAA==.',Cl='Claugh:BAAALAAECgYICwAAAA==.Clocker:BAAALAAECgEIAgAAAA==.',Co='Coldlunch:BAAALAADCggICwAAAA==.Colton:BAAALAAECggIEgAAAA==.Combatcow:BAAALAAECggIDgAAAA==.Coorona:BAAALAADCgYIBgAAAA==.Cortizanful:BAAALAADCgcIDQAAAA==.Cowbelle:BAAALAAECgEIAQAAAA==.Cowsanetetoo:BAAALAADCggIDwAAAA==.Cozmic:BAAALAAECgYICAAAAA==.',Cq='Cq:BAAALAADCggIFAAAAA==.',Cr='Craftymidget:BAAALAAECgcIDgAAAA==.Crimsonhoof:BAAALAADCggICAAAAA==.',Cu='Cumdropcutie:BAAALAAECgYIBgAAAA==.Curandero:BAAALAAECgYICAAAAA==.',Da='Dameck:BAAALAAECgcIDgAAAA==.Daramis:BAAALAAECgcIEAAAAA==.Darkholy:BAAALAADCgcIDgAAAA==.Dasdots:BAAALAAECgEIAQAAAA==.Dawgis:BAAALAAECgcICQAAAA==.Dazzeler:BAAALAAECgMIBQAAAA==.',Dd='Ddunks:BAAALAAECgIIAgAAAA==.',De='Deathpetals:BAABLAAECoEYAAIGAAgIWiUiAgBZAwAGAAgIWiUiAgBZAwAAAA==.Deathwolf:BAAALAAECgEIAQAAAA==.Decepciona:BAAALAAECgQICQAAAA==.Deepz:BAAALAAECgQIBAAAAA==.Deniance:BAAALAADCgEIAQAAAA==.Derail:BAAALAADCgQIBAAAAA==.Despir:BAACLAAFFIEFAAIKAAQI3gu6AgAHAQAKAAQI3gu6AgAHAQAsAAQKgRgAAgoACAjfIQ8GAPgCAAoACAjfIQ8GAPgCAAAA.Devilpoing:BAAALAAECgUIBwAAAA==.',Di='Difflect:BAAALAADCgcIDgAAAA==.',Do='Doak:BAAALAAECgYICgAAAA==.Dortz:BAAALAAECgMIBgABLAAECgQIBAACAAAAAA==.Dotà:BAAALAADCggIDQAAAA==.',Dr='Draconius:BAAALAADCgcIDAAAAA==.Dragnspittle:BAAALAADCgUIBQABLAAECgcIDQACAAAAAA==.Dragonturd:BAAALAAECgEIAQAAAA==.Drazentar:BAAALAADCgMIAwAAAA==.Dreamcatcher:BAAALAAECgYIBwABLAAECggIFAALAOwcAA==.Dreathor:BAAALAAECgYICAAAAA==.',Du='Dugru:BAAALAAECgYIBwABLAAFFAQIBwAFADwSAA==.Dulgar:BAAALAAECgcIDgAAAA==.',['Dá']='Dáwgis:BAAALAAECgIIAgABLAAECgcICQACAAAAAA==.',Ed='Edenstone:BAAALAADCggIEgABLAADCgYIBgACAAAAAA==.',El='Elisha:BAAALAADCggIEwAAAA==.Elspeth:BAAALAADCggICAAAAA==.Elvyra:BAAALAADCgEIAQAAAA==.Elydra:BAAALAADCgUIBQAAAA==.Elysstaa:BAAALAAECgcIDQAAAA==.',En='Endeavor:BAAALAADCgMIAwAAAA==.Entïty:BAAALAADCgQIBAABLAAECgEIAQACAAAAAA==.',Eq='Equilibria:BAAALAAECgEIAQAAAA==.',Er='Eradrina:BAAALAADCggIDwAAAA==.',Es='Estrid:BAAALAADCgUIBQAAAA==.',Ev='Evening:BAAALAAECgUICQABLAADCgYIBgACAAAAAA==.',Ey='Eyye:BAAALAADCgcIBwABLAAECgYIAQACAAAAAA==.',Ez='Ezekiei:BAAALAAECgMIAwAAAA==.',Fa='Faminex:BAACLAAFFIEHAAIMAAQIqR8LAQCVAQAMAAQIqR8LAQCVAQAsAAQKgRgAAgwACAjWJQICAFoDAAwACAjWJQICAFoDAAAA.Farns:BAAALAAFFAEIAQAAAA==.',Fe='Fearknight:BAAALAAECgEIAQAAAA==.Felinepriest:BAAALAAECgMIAwAAAA==.Felsoaked:BAAALAADCgUICAAAAA==.',Fi='Fieryhotz:BAAALAADCgYICwAAAA==.Filligri:BAAALAAECggIEQAAAA==.Filosofem:BAAALAAECgYIDQABLAAECgYICwACAAAAAA==.Firebäne:BAAALAAECgYICQAAAA==.Firecreep:BAAALAAECgcICwAAAA==.',Fl='Flaminghawk:BAAALAAFFAIIAgAAAA==.Flob:BAAALAAECgMIAwAAAA==.',Fo='Foliage:BAAALAADCggICAAAAA==.Foxxface:BAAALAADCgIIAgAAAA==.',Fr='Frankazoid:BAAALAAECgYIEwAAAA==.Freerating:BAAALAAECggIBgAAAA==.Freightfrayn:BAAALAAECgMIAwAAAA==.Fridays:BAAALAADCgYIBgAAAA==.Fryertuck:BAAALAADCgcICwAAAA==.',Fu='Fullclangg:BAAALAAFFAQIBAAAAA==.Fullmist:BAAALAAFFAMIAwABLAAFFAQIBAACAAAAAA==.Fulltranq:BAAALAADCgYIBgABLAAFFAQIBAACAAAAAA==.',Ga='Gamesucks:BAAALAAECgMIAwAAAA==.Gaya:BAAALAADCggIGgAAAA==.',Gc='Gcozz:BAAALAAECggIDgAAAA==.',Ge='Geltherosh:BAAALAADCggIEAAAAA==.Gemiserie:BAAALAAECggIEwAAAA==.',Gi='Gigastar:BAABLAAECoEXAAIIAAgIyR0bCAC0AgAIAAgIyR0bCAC0AgAAAA==.Ginyeng:BAAALAAECgQIBAAAAA==.',Go='Goatnutts:BAAALAAECgcIEAAAAA==.Goats:BAAALAADCggICAAAAA==.Gokêe:BAAALAAECgYIBgAAAA==.Golddigger:BAAALAAECgYICAAAAA==.Goldy:BAAALAADCgcIAwAAAA==.',Gr='Greenmonsta:BAAALAAECgEIAQAAAA==.Grimknight:BAAALAAECggIEgAAAA==.Grimveil:BAAALAADCgQIBAABLAADCgYIBgACAAAAAA==.Groovi:BAAALAADCgUIBQAAAA==.Grubergeiger:BAAALAAECgUIBwAAAA==.Gruunele:BAAALAAECgEIAQAAAA==.Gruunknell:BAAALAADCgcICAAAAA==.',Gu='Gubi:BAAALAAECgQICQAAAA==.Gunzandfundz:BAAALAAECgIIAwAAAA==.',Gw='Gwår:BAAALAAECgMIBgAAAA==.Gwèn:BAAALAAECgYIDQAAAA==.',Ha='Hashbrowns:BAAALAAECgcIEQAAAA==.Haydes:BAAALAADCgcIBwAAAA==.Hayleythor:BAAALAAECgEIAgAAAA==.Hazrul:BAAALAAECgcIDQAAAA==.',He='Healzyew:BAAALAADCggIDQAAAA==.Heartlust:BAAALAAECgQIBgAAAA==.Hema:BAAALAAECgcIDAAAAA==.Herakless:BAAALAAECgIIAgAAAA==.Hexoffendar:BAAALAAECggIBgAAAA==.',Hi='Highdegrees:BAAALAADCgUIBQAAAA==.',Ho='Hoa:BAAALAAECgYICAAAAA==.Hogram:BAAALAAECgEIAQAAAA==.Hojeediver:BAAALAADCgQIBAAAAA==.Holah:BAAALAADCgcIBwABLAAFFAEIAQACAAAAAA==.Holyblowèr:BAAALAAECgEIAQAAAA==.Holyfingers:BAAALAAECgEIAQAAAA==.Hooker:BAAALAAECgIIAgAAAA==.',Hu='Hugsevoker:BAAALAADCgMIAwAAAA==.Hummingbird:BAAALAADCgcIEwAAAA==.Hungus:BAAALAAECgMIBQAAAA==.',Hy='Hybryddruid:BAAALAAECgYICQAAAA==.',Il='Illiturtle:BAAALAADCggICQAAAA==.',In='Indigolemon:BAAALAAECgcICgAAAA==.Inkconjurer:BAAALAADCgQIBAAAAA==.Inkinjector:BAAALAAECgEIAQABLAAECgQIBwACAAAAAA==.Inkworshiper:BAAALAAECgQIBwAAAA==.Inouskee:BAAALAADCggIFQAAAA==.',Ja='Jamie:BAAALAAECgYICQAAAA==.',Jd='Jdchiller:BAAALAADCgYICwAAAA==.',Ji='Jizzoner:BAAALAADCgcIBgAAAA==.',['Jø']='Jøx:BAAALAADCggICAAAAA==.',Ka='Kaaz:BAAALAADCgQIBAABLAAECgYICgACAAAAAA==.Kacho:BAAALAADCggICAAAAA==.Kaledrian:BAAALAADCggICAABLAADCggIEAACAAAAAA==.Kathen:BAAALAAECgIIAgAAAA==.Kawaiihealer:BAAALAAECgMIBgAAAA==.',Kc='Kcp:BAAALAADCggICAAAAA==.',Ke='Keddy:BAAALAADCgcIEQAAAA==.Keelovan:BAAALAADCgMIAwAAAA==.',Ki='Kievit:BAAALAAECgYICAAAAA==.Kir:BAAALAAECgEIAQAAAA==.',Kk='Kkonetica:BAAALAADCggICAAAAA==.Kkrantuq:BAAALAAECggIEgAAAA==.',Kn='Knownentity:BAAALAAECgEIAQAAAA==.',Ko='Komatos:BAAALAAECgYIDgAAAA==.Korra:BAAALAAECgIIAgAAAA==.',Kr='Krsdk:BAAALAAECgcICgAAAA==.Krystelin:BAAALAAECgEIAQAAAA==.',Ku='Kulyuk:BAAALAADCgUIBQAAAA==.',Ky='Kylar:BAAALAADCggICAABLAAECggIEgACAAAAAA==.',La='Labuff:BAAALAAECgYICQAAAA==.Lanathel:BAAALAADCgUIBQAAAA==.Lancelot:BAAALAADCgMIAwAAAA==.',Le='Leafyjoe:BAAALAAECgMIBAAAAA==.Legendarybob:BAAALAAECgYICgAAAA==.Legofortnite:BAAALAAECgYICAAAAA==.Leitbur:BAAALAAECggIAwAAAA==.',Li='Lightek:BAAALAAECgMICQAAAA==.Lilsticky:BAAALAAECgYICQAAAA==.Linaril:BAAALAADCggIFQABLAAECgcIEAACAAAAAA==.Lisp:BAAALAADCggIFQAAAA==.Lithdrage:BAAALAADCggICAABLAAECgEIAQACAAAAAA==.Livathian:BAAALAAECgYIDQAAAA==.',Lo='Logolas:BAAALAAECgMIAwAAAA==.',Lu='Lucellis:BAABLAAECoEYAAIMAAgItSW/AgBKAwAMAAgItSW/AgBKAwAAAA==.Luvabull:BAAALAADCggIDwAAAA==.Luvzue:BAAALAADCgcIBwAAAA==.Luzarious:BAAALAAECgMIAwABLAAFFAQIBwAFADwSAA==.',Ly='Lysal:BAAALAADCgcIDgAAAA==.',Ma='Maana:BAAALAAECgQIBwAAAA==.Magtharn:BAAALAAECgcICAAAAA==.Malnorr:BAAALAAECgMIAwAAAA==.Maluko:BAAALAAECgYICgAAAA==.Manbeerpig:BAAALAAECgMIBAABLAAECgUIBwACAAAAAA==.Maryadhd:BAABLAAECoEYAAMNAAgI2yOcAwBJAwANAAgI2yOcAwBJAwAOAAEIwR3DJwBHAAAAAA==.Mashedt:BAAALAAECggIEQAAAA==.',Me='Melilektra:BAAALAAECgcICwAAAA==.Meray:BAAALAADCgIIAgABLAAECgQICAACAAAAAA==.Mesmerise:BAAALAADCggIEAAAAA==.',Mi='Mikaeus:BAAALAADCggIDgAAAA==.Mikealscarn:BAAALAAECgYICQAAAA==.Mikeygee:BAAALAADCgYIBgABLAAECgcICAACAAAAAA==.Minyaw:BAAALAADCggICQABLAAECgYICgACAAAAAA==.Miraya:BAAALAAECgEIAgAAAA==.Misbehaved:BAAALAADCgcIDQAAAA==.Misticles:BAAALAAECgMIAwAAAA==.Mizoremaaka:BAAALAADCgIIAgAAAA==.',Mo='Mokari:BAEALAAECgcIDgAAAA==.Monkel:BAAALAAECgEIAQAAAA==.Moonk:BAAALAAECgYICwAAAA==.Morbidchaos:BAAALAAECgUICgAAAA==.Morglum:BAAALAAECgUICQAAAA==.Mosnar:BAAALAADCggIFAAAAA==.',My='Mytatertotes:BAAALAAECgYICgAAAA==.',['Mâ']='Mâyüri:BAAALAADCggICwABLAAECggIEwACAAAAAA==.',['Mö']='Mölly:BAAALAADCggICAAAAA==.',Na='Nadris:BAAALAADCgYIBgAAAA==.Nalrot:BAAALAADCgcIDQABLAADCggIEAACAAAAAA==.Narcine:BAAALAAECgYIBgAAAA==.Narina:BAAALAAECgIIAgAAAA==.Naruní:BAAALAAECgcIDAAAAA==.Narwhakle:BAAALAADCgUIBQAAAA==.Nayme:BAAALAADCggIBwAAAA==.',Ne='Necie:BAAALAAECgcIDgAAAA==.Nee:BAAALAAFFAIIAgAAAA==.Nelor:BAAALAADCggICwAAAA==.',No='Nongra:BAAALAADCgcIBwAAAA==.Noremac:BAAALAADCgcIDAAAAA==.',['Në']='Nëzükõ:BAAALAAECggIEwAAAA==.',Ob='Obzen:BAAALAADCgYIBgAAAA==.',Od='Odeode:BAAALAAECgcIBwAAAA==.',Of='Offensive:BAAALAAECgQIBAAAAA==.',Og='Ogre:BAABLAAECoEVAAIMAAgIrCScAwA1AwAMAAgIrCScAwA1AwAAAA==.',Ol='Oldmoldi:BAAALAAECgcIDQAAAA==.',On='On:BAAALAAECgIIBAAAAA==.',Oo='Ookkiiaatt:BAAALAADCgcIBwAAAA==.',Or='Orctoes:BAAALAAECgIIAwAAAA==.',Ox='Oxnard:BAAALAAECgIIAgAAAA==.',Pa='Palmarez:BAAALAAECgIIAgAAAA==.Pangsoongi:BAAALAAECgIIAgAAAA==.Pawcat:BAAALAAECgIIAgAAAA==.',Pe='Peewees:BAAALAADCggIEgAAAA==.Pegasus:BAAALAAECgcICwAAAA==.Peterpanda:BAAALAAECgEIAQAAAA==.Pewpewz:BAAALAAECgMIBAAAAA==.',Ph='Phaedros:BAAALAADCgcIBwABLAAECgQIBAACAAAAAA==.Phobos:BAAALAAECgEIAQAAAA==.Phogood:BAAALAAECgIIAwAAAA==.Phronesis:BAAALAADCgEIAQAAAA==.',Pi='Piles:BAAALAADCgQIBAAAAA==.',Pl='Plot:BAAALAAECgUIBQAAAA==.Plsno:BAAALAADCgEIAQAAAA==.',Po='Poekimaw:BAAALAADCgMIAwAAAA==.Polpo:BAAALAAECgUIBAAAAA==.Poppingoff:BAAALAAECgMIAwABLAAECgcIDQACAAAAAA==.Poppinin:BAAALAAECgYICAAAAA==.Potaters:BAAALAAECgQIBgAAAA==.Powerwordhug:BAAALAAECgIIAgABLAAECgUIBwACAAAAAA==.',Ps='Psychronic:BAAALAAECgUICAAAAA==.',Pu='Purrsnikitty:BAAALAADCggIFgAAAA==.',['Pà']='Pànzer:BAAALAAECgcIEwAAAA==.',Qh='Qhoneysalssa:BAAALAADCggIDQAAAA==.',Ql='Qlito:BAAALAADCggIEAABLAAECgYICgACAAAAAA==.',Qu='Quillmane:BAAALAADCggICgABLAAECgcIEAACAAAAAA==.',Ra='Raijenmango:BAAALAAECgUIBgAAAA==.Rainakamugi:BAAALAAECgcIDQAAAA==.Rakido:BAAALAAECgEIAQAAAA==.Raoh:BAAALAAECgEIAQAAAA==.Rarana:BAAALAADCgMIAwAAAA==.Rayshoots:BAAALAADCgYIDAABLAAECgQICAACAAAAAA==.Rayvoker:BAAALAAECgQICAAAAA==.Razberrykush:BAAALAADCgQIBAAAAA==.Razorbrew:BAABLAAECoEZAAIPAAgIbCQoAgAjAwAPAAgIbCQoAgAjAwAAAA==.Razorpal:BAAALAAECgMIAwABLAAECggIGQAPAGwkAA==.',Re='Reignz:BAAALAAECgcICQAAAA==.Remster:BAAALAADCgcIDAAAAA==.Rennas:BAAALAAECgYIBgAAAA==.Rezmae:BAAALAADCgUICgAAAA==.Reznàp:BAAALAADCgUIBwAAAA==.',Rh='Rhitual:BAAALAAECgYICAAAAA==.',Ri='Rift:BAAALAADCgYICQAAAA==.Rika:BAAALAADCggIEAAAAA==.Ristan:BAAALAAECgcIDgAAAA==.',Ro='Rolanlol:BAABLAAECoEUAAMBAAgIESJBCgBzAgABAAcIHCJBCgBzAgAQAAEIwyFtagBLAAAAAA==.',Ry='Ryujin:BAAALAADCggICgAAAA==.',Sa='Sachiko:BAAALAADCgYICAAAAA==.Safetyspork:BAAALAAECgYIAQAAAA==.Sagë:BAAALAAECgMIAwAAAA==.Salsa:BAAALAADCgYIBgAAAA==.Samunzo:BAAALAADCgcIBwAAAA==.Saresh:BAAALAADCggICwAAAA==.',Sc='Scalie:BAAALAADCgcICgAAAA==.Schlee:BAAALAADCgYIAQAAAA==.Scârecrow:BAAALAADCgcIDAAAAA==.',Se='Sejien:BAAALAAECgEIAQAAAA==.Senjou:BAAALAAECgMIBAAAAA==.Sermet:BAAALAADCggICQABLAAECgYICQACAAAAAA==.Serous:BAAALAAECgMIBQAAAA==.Set:BAAALAADCggIDgABLAAECgcIEAACAAAAAA==.Setal:BAAALAAECgcIEAAAAA==.',Sh='Shammycammy:BAAALAADCgcIDAAAAA==.Shimmyx:BAAALAADCggICAAAAA==.Shinydude:BAAALAAECgMIBgAAAA==.Shkanna:BAAALAAECgMIBAABLAAECgQIBAACAAAAAA==.Shovelhead:BAAALAADCgcIDgAAAA==.Shrêk:BAAALAADCggIFwAAAA==.Shwan:BAAALAAECgYIDQAAAA==.',Si='Sinavyr:BAAALAADCgcICQAAAA==.Sinergy:BAAALAADCgcIBwABLAAECgcIFAABAPEaAA==.Siomara:BAAALAADCggIGAAAAA==.Sizzlemoo:BAAALAADCgYIBwAAAA==.',Sk='Skorme:BAAALAAECgQIBAAAAA==.Skyshield:BAABLAAECoEUAAIFAAgIGRl2BgBkAgAFAAgIGRl2BgBkAgAAAA==.Skyzen:BAAALAAECgMIAwAAAA==.',Sl='Slabbhammer:BAAALAAECgYICAAAAA==.Slowmelt:BAAALAAECgIIAwAAAA==.',Sm='Smitty:BAAALAADCggICAAAAA==.Smooshednewt:BAAALAAECgcICAAAAA==.',Sn='Snckrdoodle:BAAALAADCggICAABLAAECgYICQACAAAAAA==.',So='Sohyun:BAAALAADCgMIAwABLAAECggIFAALAOwcAA==.Solis:BAAALAADCgYIBgAAAA==.',Sp='Spekk:BAAALAADCgYIBgAAAA==.Speknawz:BAAALAAECgIIAgAAAA==.Splantz:BAAALAAECgYIBgAAAA==.Spoiledangel:BAAALAADCggIFgAAAA==.Spoonman:BAAALAADCggICQAAAA==.Springz:BAAALAAECgYIDwAAAA==.Spurred:BAAALAAECgEIAQAAAA==.',St='Stereodh:BAAALAAECgIIAgAAAA==.Strange:BAAALAAECgIIAgAAAA==.Strickyrice:BAAALAADCgcICQAAAA==.Stär:BAAALAADCgcIBwAAAA==.',Su='Suffr:BAAALAADCggICAAAAA==.Sunscorn:BAAALAADCggICAAAAA==.Supanova:BAAALAAECgYIBgAAAA==.',Sw='Swingin:BAAALAAECgIIAwAAAA==.',Sy='Synapticbeez:BAAALAAECgEIAQAAAA==.',Ta='Tarram:BAAALAAECgYICgAAAA==.Tartan:BAAALAAECggIEQAAAA==.Tartin:BAAALAADCggICAAAAA==.Tavey:BAAALAADCgcIBwAAAA==.',Te='Tellura:BAAALAADCgUIBQAAAA==.',Th='Thedrink:BAAALAADCggICAAAAA==.Thesauce:BAABLAAECoEVAAIRAAgIhyNHAQAoAwARAAgIhyNHAQAoAwAAAA==.Thrikal:BAAALAAECgcIDgAAAA==.Thunderstud:BAAALAADCgMIAwAAAA==.',Ti='Timefrayne:BAAALAAECgIIAgAAAA==.',Tr='Treebark:BAAALAADCggIDAAAAA==.Trik:BAAALAADCggIBwAAAA==.',Tu='Tufluk:BAAALAAECgMIBQAAAA==.Turial:BAAALAAECgYIDQAAAA==.',Tw='Twelevepeers:BAAALAADCgMIAwAAAA==.Twntyonesav:BAAALAADCgcIEwAAAA==.',Ty='Tylanll:BAAALAADCggICAAAAA==.',Tz='Tzalman:BAAALAADCgIIBAAAAA==.',['Tì']='Tìamat:BAAALAADCgcIBwAAAA==.',Ug='Ughtismo:BAAALAADCggIFgAAAA==.',Ul='Ultarok:BAAALAAECgYICQAAAA==.',Un='Unfiltered:BAAALAADCgcIBwAAAA==.',Us='Ushii:BAAALAADCgYIBwAAAA==.',Va='Vampirevic:BAAALAADCggICAAAAA==.Varcoa:BAAALAAECgYICAAAAA==.',Ve='Velixar:BAAALAAECgEIAQAAAA==.',Vi='Vinda:BAAALAAECgcIDgAAAA==.Vivixia:BAAALAAECgMIAwAAAA==.',Vl='Vladious:BAAALAAECgYICQAAAA==.',Vo='Voidslinger:BAAALAAECgYICQAAAA==.',Vy='Vynd:BAAALAAECgYIBgAAAA==.Vynllandis:BAAALAADCgYIBgAAAA==.',Wa='Warfair:BAAALAADCgcIBwAAAA==.Washedpyro:BAAALAAECgIIAgAAAA==.Waving:BAAALAADCgQIAgAAAA==.',Wh='Whysoosalty:BAAALAADCgcIBwAAAA==.',Wi='Willywonkas:BAAALAADCggIFQAAAA==.',Wo='Woa:BAAALAADCggIFwAAAA==.Woofwoofwoof:BAAALAAECgMIBQAAAA==.',Wu='Wugu:BAAALAADCgcIEAAAAA==.',Xa='Xarite:BAAALAADCgUIBQAAAA==.',Xe='Xermet:BAAALAAECgYICQAAAA==.',Xs='Xsavage:BAAALAADCgYIBgAAAA==.',Xu='Xusukzo:BAAALAADCggIDwAAAA==.',Yo='Yoohyeon:BAABLAAECoEUAAMLAAgI7BzuCgBzAgALAAgI7BzuCgBzAgASAAIIQA2oEwBqAAAAAA==.',Yu='Yumí:BAAALAAECgUICAAAAA==.',Za='Zalath:BAAALAAECgIIAgAAAA==.Zanarkand:BAAALAAECgEIAQAAAA==.Zaunuf:BAAALAADCgcIDgAAAA==.',Ze='Zendrademonh:BAAALAADCgcIBwAAAA==.Zexexe:BAAALAAECgYICwABLAAECggIGAAGAFolAA==.',Zi='Zina:BAAALAADCgcIDAAAAA==.',Zo='Zombienolan:BAAALAAECgYICQAAAA==.',Zu='Zuzue:BAAALAADCgcIBwAAAA==.',['Âz']='Âzog:BAAALAADCgcIBwAAAA==.',['Ëy']='Ëyë:BAAALAAECgYIBwAAAA==.',['Ñi']='Ñina:BAAALAADCgcIDQAAAA==.',['ße']='ßellaa:BAAALAADCggICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end