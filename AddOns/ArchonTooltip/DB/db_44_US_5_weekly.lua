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
 local lookup = {'Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Unknown-Unknown','DemonHunter-Havoc','Evoker-Augmentation','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Druid-Restoration','Warrior-Protection','DeathKnight-Frost','Shaman-Restoration','Evoker-Preservation','Mage-Frost','Evoker-Devastation',}; local provider = {region='US',realm='Akama',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Accost:BAAALAADCggICQAAAA==.',Ae='Aelha:BAAALAAECgMIAwAAAA==.Aeratedlol:BAACLAAFFIEGAAMBAAQIgBrnAQBdAQABAAQIeBXnAQBdAQACAAEIcySyBwBtAAAsAAQKgRcABAEACAjSJWQBAGMDAAEACAjSJWQBAGMDAAMAAwiUGVkSAA4BAAIAAwgqEF0wALIAAAAA.Aethandor:BAAALAADCgEIAQAAAA==.',Ak='Akaruku:BAAALAADCgcIBwABLAADCggIDwAEAAAAAA==.Akassa:BAAALAADCggICAAAAA==.Aknologia:BAAALAAECgUIDQABLAAECgYICAAEAAAAAA==.',Am='Amarah:BAAALAAECgQIBAAAAA==.',Ar='Arca:BAAALAADCgcIBwAAAA==.Arglock:BAAALAADCgIIAgABLAAECgcIDgAEAAAAAA==.Argrekh:BAAALAAECgUIBQABLAAECgcIDgAEAAAAAA==.Argrekm:BAAALAAECgcIDgAAAA==.Argrekt:BAAALAADCggICAABLAAECgcIDgAEAAAAAA==.Aridol:BAAALAADCgcIBwAAAA==.Arigön:BAAALAADCgcIEQAAAA==.Arshton:BAAALAADCggICAAAAA==.Arthaslk:BAAALAAECgUIBwABLAAECgcIEAAEAAAAAA==.',As='Ashx:BAAALAADCgYIBQABLAADCggICwAEAAAAAA==.Aswyn:BAAALAADCggICAAAAA==.',Av='Avade:BAAALAADCgIIAgAAAA==.',Ba='Babyjamey:BAAALAAECgYICgAAAA==.Backwater:BAAALAADCgcICAAAAA==.Baetrayer:BAACLAAFFIEFAAIFAAQI6w1yAQBYAQAFAAQI6w1yAQBYAQAsAAQKgRgAAgUACAgaJWwDAEwDAAUACAgaJWwDAEwDAAAA.Ballsofire:BAAALAAECgIIAwAAAA==.',Be='Bearmane:BAAALAAECgQIBgAAAA==.Belithel:BAAALAADCgYIAgABLAADCggICwAEAAAAAA==.Bencreepin:BAAALAAECgIIAgAAAA==.Bernoulli:BAAALAADCgcIBwAAAA==.',Bi='Bigblunts:BAAALAADCgcIDQAAAA==.',Bl='Blinkers:BAAALAAECgIIAgAAAA==.Bloodboo:BAAALAADCgMIAwAAAA==.Bloodyhpally:BAAALAAECggIEgAAAA==.Blooð:BAAALAAECgEIAQAAAA==.Blythella:BAAALAAECgUICQAAAA==.',Bo='Boadicea:BAAALAADCgIIAgAAAA==.Boombox:BAAALAAECgcIDAAAAA==.Boopsnoopems:BAAALAADCggIFQAAAA==.Bopinem:BAAALAADCgcIBwAAAA==.Borderline:BAAALAADCggIDwABLAAECgcIEAAEAAAAAA==.',Br='Braileth:BAAALAADCggIDgAAAA==.Breana:BAAALAADCgcIBwAAAA==.Breffy:BAAALAADCggICAABLAAECggIDwAEAAAAAA==.Brewjitsu:BAAALAADCgEIAQAAAA==.Brodan:BAAALAADCgQICQAAAA==.',Bu='Busy:BAAALAADCgMIAwAAAA==.',Ca='Cactuscooler:BAACLAAFFIEFAAIGAAQIqww+AABIAQAGAAQIqww+AABIAQAsAAQKgRgAAgYACAhOJGwAACMDAAYACAhOJGwAACMDAAAA.Casare:BAAALAAECgEIAQAAAA==.',Ce='Celithe:BAAALAADCggICAABLAADCggIEAAEAAAAAA==.',Cl='Clarè:BAAALAADCggICAAAAA==.Clawhalla:BAAALAAECgYIDQAAAA==.',Co='Colexn:BAAALAAECgMIAwAAAA==.Complexity:BAAALAADCggICAAAAA==.Congore:BAAALAAECgYICAAAAA==.Congr:BAAALAADCggIDgAAAA==.Conniebb:BAAALAAECgEIAQAAAA==.Cooldown:BAAALAADCgIIAgAAAA==.Cornchipz:BAAALAAECgYICAAAAA==.',Cr='Crow:BAAALAADCgcIBwAAAA==.',Cu='Cuh:BAAALAAECgcIEgAAAA==.',Da='Daelin:BAAALAADCggIEAAAAA==.Dancintotems:BAAALAADCgcIBwAAAA==.Darkacedia:BAAALAAECgcIEAAAAA==.Datbish:BAAALAADCgcIBwAAAA==.',De='Dealosed:BAAALAADCggICAAAAA==.Deathkano:BAAALAAECgEIAQAAAA==.Dekaydnkykng:BAAALAAECggIAQAAAA==.Demonlock:BAAALAADCgcIBwAAAA==.Demonscar:BAAALAADCggICwAAAA==.Devildh:BAAALAADCgcIDgAAAA==.Devildruid:BAAALAADCgMIAwAAAA==.Devilpawn:BAAALAAECgQIBgAAAA==.Devyleen:BAAALAAECgEIAQAAAA==.',Di='Disastacast:BAAALAADCggIDAAAAA==.Dive:BAAALAAECggICwAAAA==.',Dk='Dkauto:BAABLAAECoEUAAIHAAgIWR6XAwCgAgAHAAgIWR6XAwCgAgAAAA==.',Do='Doryndoran:BAAALAAECggIDQAAAA==.Dorynhashots:BAAALAADCgYIBgAAAA==.',Dr='Dracomaibois:BAAALAAECgYIDAAAAA==.Dragoneggs:BAAALAAECgMIAwAAAA==.Drippyy:BAAALAAECgYICAABLAAFFAEIAQAEAAAAAA==.Druknar:BAAALAADCggIEAAAAA==.Drunkenutz:BAAALAAECgEIAQABLAAECgcICgAEAAAAAA==.',Du='Dundo:BAAALAAECgYICgAAAA==.',['Dä']='Dälf:BAAALAAECgMIAwAAAA==.',Ed='Edirii:BAAALAADCgUIBwAAAA==.',Ei='Eissa:BAAALAADCgYICAAAAA==.',El='Elinras:BAAALAAECggICQAAAA==.Elrizon:BAAALAADCgcIDQAAAA==.',Em='Emberbane:BAAALAADCgUIBQAAAA==.Emz:BAAALAAECggIBQAAAA==.',Er='Erianda:BAAALAADCgUIBQAAAA==.Eric:BAABLAAECoEVAAMIAAgIwRuADACaAgAIAAgIrhuADACaAgAJAAQIvhN2DADGAAAAAA==.Eroninja:BAAALAADCgYICgABLAADCggICwAEAAAAAA==.',Eu='Eurong:BAAALAAFFAIIAgAAAA==.',Ev='Evangelune:BAAALAAECgEIAQAAAA==.',Ey='Eylanna:BAAALAADCgcICwAAAA==.',Ez='Ezynuff:BAAALAADCgUIBQAAAA==.',Fe='Fearoftdark:BAAALAAECggIEgAAAA==.Feltnutz:BAAALAAECgcICgAAAA==.Fendris:BAAALAADCgcICQAAAA==.',Fi='Fixware:BAAALAADCgYIBgAAAA==.',Fl='Flyjin:BAAALAAECgUIBgAAAA==.',Fo='Fortescue:BAAALAADCgYIBgABLAAECgcIEAAEAAAAAA==.',Fr='Frostybuns:BAAALAAECgYIBwAAAA==.Frostyproto:BAAALAADCggIGAAAAA==.',Fu='Fullkidney:BAAALAADCgUIBQAAAA==.Funch:BAAALAAECgYICQAAAA==.Funnel:BAAALAAFFAEIAQAAAA==.',Ga='Gabbathegoo:BAABLAAECoEUAAQCAAcIWiCIDwCMAQACAAQIXCGIDwCMAQABAAMIAx/ONQAPAQADAAIIuwgDIQB3AAAAAA==.Gainzz:BAAALAAECgMIAwAAAA==.Gandalph:BAAALAADCgcIBwAAAA==.Garl:BAAALAAECggIDwAAAA==.',Ge='Gezus:BAAALAAECggIAQAAAA==.',Gh='Ghari:BAAALAADCggICAAAAA==.',Gl='Glorwindel:BAAALAADCgUIBQAAAA==.',Gn='Gnoblin:BAAALAADCgQIBAAAAA==.',Gr='Greka:BAAALAAECgEIAQAAAA==.Grogrush:BAAALAADCgUIAgABLAAECgEIAQAEAAAAAA==.Gruhm:BAAALAADCgYIBgAAAA==.',Gy='Gyattaura:BAAALAADCgQIBAAAAA==.',Ha='Harrydötter:BAAALAAECgQIBgAAAA==.Haruaki:BAAALAADCgcICgAAAA==.',He='Hellbourne:BAAALAADCggIEAABLAADCggIGAAEAAAAAA==.Heàl:BAAALAADCggIDAAAAA==.',Ho='Holofox:BAABLAAECoEWAAIKAAgI3h1RBgCTAgAKAAgI3h1RBgCTAgAAAA==.Honored:BAAALAADCgEIAQABLAADCgYIBgAEAAAAAA==.Horman:BAAALAAECgIIAgAAAA==.',Hu='Huntalle:BAAALAAECgYICQAAAA==.',Ig='Igluu:BAAALAAECgcIDQABLAAFFAMIBQAIACgLAA==.Igotwutuneed:BAAALAADCgIIAgABLAADCgcICAAEAAAAAA==.',Ik='Ikerous:BAAALAADCgYIBgAAAA==.',Il='Ilililililli:BAAALAAECgYIEQAAAA==.',Ir='Irudium:BAAALAAECgIIAgAAAA==.',It='Itiswhatitiz:BAAALAADCgcIBwAAAA==.Itsybityshiv:BAAALAAECgEIAQAAAA==.',Iv='Ivortex:BAAALAADCgcIBwAAAA==.',Ja='Jambark:BAAALAADCggIDwAAAA==.Jaysontatum:BAAALAAECgYIBwAAAA==.',Je='Jedimomm:BAAALAADCgMIAwAAAA==.',Ji='Jimmygibbs:BAAALAAECgYIBwAAAA==.',Ju='Jundimage:BAAALAAECgYICgAAAA==.',Ka='Kamin:BAABLAAECoEUAAILAAgINhy0BgBcAgALAAgINhy0BgBcAgAAAA==.Kaykaypally:BAAALAAECgMIAwAAAA==.',Ke='Kellan:BAAALAAECgIIAgAAAA==.',Ki='Kidota:BAAALAAECgYICQAAAA==.Kilgharra:BAAALAADCgcICAAAAA==.Kilkenny:BAAALAADCggIDgAAAA==.Kinar:BAAALAAECgMIAwAAAA==.Kinara:BAAALAADCggIDgABLAAECgYICQAEAAAAAA==.Kinji:BAAALAADCgYIBAABLAADCggICwAEAAAAAA==.Kittycatmeow:BAAALAAECgcICQAAAA==.',Ko='Kouki:BAAALAADCgEIAQAAAA==.',Kr='Kreamer:BAAALAAECgQIBwAAAA==.Kristysavage:BAAALAAECgEIAgAAAA==.',Ky='Kynar:BAACLAAFFIEGAAIMAAQI1hYbAQBdAQAMAAQI1hYbAQBdAQAsAAQKgRgAAgwACAihISwLAMkCAAwACAihISwLAMkCAAAA.Kyrieirving:BAAALAADCgcIDAABLAAECgYIBwAEAAAAAA==.',La='Lambshot:BAAALAAECgMIAwAAAA==.Lambsy:BAACLAAFFIEFAAIIAAMIuRaVAgAXAQAIAAMIuRaVAgAXAQAsAAQKgRgAAggACAhUIq0HAO8CAAgACAhUIq0HAO8CAAAA.Layla:BAAALAADCgEIAQAAAA==.',Le='Lehvo:BAAALAAECgQIBAAAAA==.Lerat:BAAALAAECgYICQAAAA==.Lewpha:BAAALAAECgYICQAAAA==.',Lf='Lfhealer:BAAALAADCgUIBgAAAA==.',Li='Lightofhope:BAAALAADCggIDwAAAA==.Lisanalgaib:BAAALAADCggIEwAAAA==.Littlefoote:BAAALAADCgMIAwAAAA==.Lizzimcguire:BAAALAADCgUICAABLAADCggIDwAEAAAAAA==.',Lo='Logistic:BAAALAAECgMIAwAAAA==.',Lu='Lukadoncic:BAAALAAECgIIAgABLAAECgYIBwAEAAAAAA==.Lulubean:BAAALAADCgEIAQAAAA==.Lunchable:BAAALAAECgYIBwAAAA==.Luxmalleo:BAAALAADCgcICAAAAA==.',Ma='Magico:BAAALAADCgEIAQAAAA==.Maju:BAAALAADCgMIAwAAAA==.Makaroni:BAAALAAECgYIBgAAAA==.Mangemaqeu:BAAALAADCgMIAwAAAA==.Manticus:BAAALAADCgYICwAAAA==.Marble:BAAALAAECgEIAQAAAA==.Mari:BAAALAADCgEIAQAAAA==.Matroxx:BAAALAAECggIEQAAAA==.',Me='Melysia:BAAALAAECgYIBQAAAA==.Mepha:BAAALAAECgMIBgAAAA==.',Mi='Mika:BAAALAADCgYIAgAAAA==.Millamber:BAAALAAECgIIAgAAAA==.Minmel:BAAALAAECgYICQAAAA==.Minty:BAAALAAECgMIAwAAAA==.',Mo='Moardotsnow:BAAALAADCggICgAAAA==.Mortui:BAAALAADCgQIBAAAAA==.',Mu='Murdershow:BAAALAAECgEIAQAAAA==.',['Më']='Mëow:BAAALAAECgEIAQAAAA==.',Ni='Nightshàde:BAAALAADCggIDwAAAA==.Nirina:BAAALAADCggIFQAAAA==.Nirox:BAAALAADCgcIBwAAAA==.Nivari:BAAALAAECggIEgAAAA==.',Nn='Nnug:BAAALAADCggICAAAAA==.',No='Nohtil:BAAALAADCgcIEQAAAA==.Noraeri:BAAALAADCgcICwABLAADCggICwAEAAAAAA==.',['Nö']='Nöellen:BAAALAADCggIGAAAAA==.',Om='Omnipotent:BAAALAADCgcIBwAAAA==.',Oo='Oogieboogie:BAAALAAECgMIBAAAAA==.',Op='Oppose:BAAALAAECgYICAAAAA==.',Or='Orestes:BAAALAAECgYIBgAAAA==.Ormagöden:BAAALAAECgYICQAAAA==.',Ou='Ouchie:BAAALAADCggICAAAAA==.',Oz='Ozzpoxzo:BAAALAADCgcIDAAAAA==.',Pa='Parador:BAAALAAECgMIAwAAAA==.Pastasauce:BAAALAAECgMIAwAAAA==.',Pe='Penz:BAAALAADCgcIBwAAAA==.',Po='Pov:BAAALAADCgYIBgAAAA==.',Pr='Premonitions:BAAALAAECgMIAwAAAA==.Premune:BAAALAAECgYICQAAAA==.',Py='Pyrena:BAAALAAECgYIBwAAAA==.',Ra='Ragebait:BAAALAAECgMIBAAAAA==.Ragingfluids:BAAALAAECgQIBAAAAA==.Raime:BAAALAADCgQIBAAAAA==.Rainbowdots:BAAALAADCggICAAAAA==.Raine:BAABLAAECoEYAAINAAgInBRoGgDiAQANAAgInBRoGgDiAQAAAA==.Ralfio:BAAALAAECgMIBQAAAA==.Ramsesbaby:BAAALAAECgYIDAAAAA==.Raynith:BAAALAAECgYICgAAAA==.',Re='Readycheck:BAAALAAECgYIBwAAAA==.Reckalossi:BAAALAADCggIFAABLAAECggICQAEAAAAAA==.Relidora:BAAALAAECgYICQAAAA==.Remix:BAAALAADCgcIBwAAAA==.Revelaen:BAABLAAECoEZAAIOAAgIPBJ1BwDkAQAOAAgIPBJ1BwDkAQAAAA==.',Ri='Rick:BAAALAAECgcIDAAAAA==.',Rn='Rngeezus:BAAALAAECgcIEQAAAA==.',Ru='Rubie:BAAALAAECgQIBwAAAA==.',Sa='Sakumo:BAAALAAECgIIAgAAAA==.Sammel:BAAALAADCgMIAwAAAA==.Sanari:BAAALAADCggICwAAAA==.Sargus:BAAALAADCgIIAgAAAA==.Sathreina:BAAALAAECgYICQAAAA==.',Sc='Scaries:BAAALAAECgYICgAAAA==.Scootko:BAAALAAECgEIAQAAAA==.',Sh='Shaddik:BAAALAAECgYIDAAAAA==.Shadowisbad:BAAALAAECgYIBwAAAA==.Shaeledoran:BAAALAADCggICgAAAA==.Sheister:BAAALAAECgIIAgABLAAECggICwAEAAAAAA==.Shizuko:BAAALAADCgcIDgAAAA==.',Si='Siena:BAAALAADCgcIBwAAAA==.Silre:BAAALAADCgcIEQAAAA==.',Sl='Slappeey:BAAALAADCggIDQABLAAECgYIBwAEAAAAAA==.',So='Solanaceae:BAAALAADCggIDwAAAA==.',Sp='Spaceman:BAAALAAECgcIEAAAAA==.',Sq='Squab:BAAALAAECgYICQAAAA==.Squanchy:BAAALAAECgUIBgAAAA==.Squirtz:BAAALAADCgcICgAAAA==.',St='Storienn:BAAALAAECgIIAgAAAA==.Stormfyre:BAAALAADCggICAAAAA==.Stormyspellz:BAAALAAECgIIAgAAAA==.',Su='Sunglo:BAAALAADCgcIBwAAAA==.Sunkists:BAAALAADCgYIBgABLAAFFAQIBQAGAKsMAA==.Surefire:BAAALAAECgMIAwAAAA==.',Sw='Swaption:BAAALAAECgYIDAAAAA==.',Sy='Syrelia:BAAALAADCggIEAAAAA==.',Ta='Tacotruck:BAAALAAECgIIAgAAAA==.Takèda:BAAALAAECgMIBQAAAA==.Taoofpooh:BAAALAADCgcICAAAAA==.Tassarosea:BAAALAADCgQIBAABLAADCggIDwAEAAAAAA==.Tauloe:BAAALAADCgcIBwAAAA==.Tayna:BAAALAADCgcIBwAAAA==.',Te='Telzan:BAAALAADCgQIBAAAAA==.Terpene:BAAALAADCgcIBwAAAA==.',Th='Theuss:BAAALAAECgYICAAAAA==.Thomo:BAAALAADCggICAAAAA==.Thunk:BAAALAAECgMIAwAAAA==.',Ti='Timdawg:BAABLAAECoEUAAIPAAgI3SUhAQBMAwAPAAgI3SUhAQBMAwAAAA==.Titanite:BAAALAAECggIDwAAAA==.',To='Tomhankz:BAAALAAECgYIBwAAAA==.Tomotostein:BAAALAAECgYIDwAAAA==.Totemnutz:BAAALAAECgQIBwABLAAECgcICgAEAAAAAA==.',Tr='Tream:BAAALAADCgYIBgAAAA==.Tristîtia:BAAALAAECgYIDgAAAA==.',Tu='Tumtum:BAAALAAECgIIAwAAAA==.',Ty='Ty:BAEALAAECgYIDQAAAA==.',Ub='Ubi:BAAALAADCggIDQAAAA==.',Un='Unholyrot:BAAALAADCggIDAAAAA==.',Va='Valentin:BAAALAADCgcIBwAAAA==.Valindra:BAAALAAECgcIDgAAAA==.Vanwolfy:BAAALAAECgUIBwAAAA==.',Ve='Vedrolis:BAAALAAECggICAAAAA==.Velectran:BAAALAADCggIDgABLAADCggIEAAEAAAAAA==.',Vi='Vientolibre:BAAALAADCgUIBgAAAA==.Vish:BAAALAAECgYIBwAAAA==.',Vy='Vynle:BAAALAADCgcIBwAAAA==.',Wa='Warheimer:BAAALAADCgcIDwAAAA==.Warrgodx:BAAALAAECgcIEAAAAA==.Wartroxx:BAAALAAECgIIAgAAAA==.',We='Wengja:BAAALAADCgEIAQABLAADCgMIAwAEAAAAAA==.',Wh='Whathaveyou:BAAALAADCggICAAAAA==.',Wo='Woodkin:BAAALAAECgQIBgAAAA==.',Wr='Wrongwookie:BAAALAAECgYICQAAAA==.',Wy='Wyrmbreaker:BAAALAAECgcIDAABLAAECggIEgAEAAAAAA==.Wyrmrest:BAAALAADCgUIBQAAAA==.',Xa='Xaser:BAAALAAECgEIAQAAAA==.Xavia:BAAALAAECgYICQAAAA==.',Ya='Yapper:BAAALAAECgMIBQAAAA==.',Yo='Youtube:BAACLAAFFIEHAAIQAAQIxSTfAACxAQAQAAQIxSTfAACxAQAsAAQKgRgAAhAACAiEJBQBAGADABAACAiEJBQBAGADAAAA.',Ys='Yssabella:BAAALAADCgEIAQAAAA==.',Za='Zabada:BAAALAADCgcICQAAAA==.',Ze='Zedrakh:BAAALAAECgMIAwAAAA==.Zetta:BAAALAAECgYIDwAAAA==.',Zi='Ziplocks:BAAALAADCgQIBAAAAA==.',Zy='Zyndrael:BAAALAADCgcIBwAAAA==.',['Æn']='Ænimal:BAAALAADCgMIAwAAAA==.',['Èl']='Èlytz:BAAALAAECggICwAAAA==.',['Êl']='Êlytz:BAAALAAECgMIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end