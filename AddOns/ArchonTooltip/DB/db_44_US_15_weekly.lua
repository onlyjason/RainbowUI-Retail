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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Rogue-Subtlety','Rogue-Assassination','Warrior-Fury','Monk-Brewmaster','Mage-Arcane','Mage-Fire','Priest-Discipline','Evoker-Preservation','Warlock-Demonology','Monk-Windwalker','Paladin-Retribution',}; local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaril:BAAALAADCgUIDQAAAA==.',Ae='Aeshal:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.',Af='Afkbot:BAAALAADCggIEQAAAA==.',Ag='Agnass:BAAALAADCgUIBwAAAA==.',Ak='Akina:BAAALAADCggICAABLAAECgYICQABAAAAAA==.',Al='Alcholic:BAAALAAECggICAAAAA==.Ald:BAAALAADCgcIEwAAAA==.Aldea:BAAALAAECgQIBAAAAA==.Alirrayia:BAAALAAECgYIBwAAAA==.Alirrayiia:BAAALAAECgcIEgAAAA==.Allystar:BAAALAADCgUICAAAAA==.',Am='Amachine:BAAALAADCgYIBgAAAA==.Ambreth:BAAALAADCggIGgAAAA==.',An='Angrylauroo:BAAALAAECgEIAQAAAA==.Anyra:BAAALAADCgMIAgAAAA==.',Ao='Aowl:BAAALAAECgIIAgAAAA==.',Ar='Artanthos:BAAALAADCgUIBQAAAA==.',As='Asgarde:BAAALAADCgcIDAAAAA==.',Az='Azurescale:BAAALAADCgcIBwAAAA==.',Ba='Bahler:BAEALAAECgEIAQAAAA==.Baji:BAAALAADCgEIAQABLAAECgQIBgABAAAAAA==.Barecast:BAAALAAECgMIBgAAAA==.Barefall:BAACLAAFFIEFAAICAAMIUiLwAAA1AQACAAMIUiLwAAA1AQAsAAQKgRYAAgIACAgIJPYEABcDAAIACAgIJPYEABcDAAAA.Barelywolf:BAAALAAECgEIAQAAAA==.Barepriest:BAAALAAECgEIAQAAAA==.Barkclaw:BAAALAADCgYICgAAAA==.Bashira:BAAALAAECgYICgAAAA==.Bast:BAAALAAECgUICQAAAA==.Baénoth:BAAALAADCgEIAQAAAA==.',Be='Berrodiah:BAAALAAECgMIBwAAAA==.Beyarago:BAAALAADCggIDwAAAA==.',Bh='Bheiroth:BAAALAAECgYIBwAAAA==.',Bi='Birds:BAAALAAECgEIAQAAAA==.',Bl='Blasphemet:BAAALAADCgEIAQAAAA==.Blodhgarm:BAAALAADCgYIBgAAAA==.Bloodflurry:BAAALAADCggIDgAAAA==.Blook:BAAALAADCgcIBwAAAA==.Bluett:BAAALAADCgMIAwAAAA==.',Bo='Bogertus:BAAALAAECgYICgAAAA==.Boomertunes:BAAALAAECgEIAQAAAA==.Boxnasty:BAAALAAECgMIAwAAAA==.',Br='Brasha:BAAALAADCgMIAwABLAADCgYIBgABAAAAAA==.Brein:BAAALAAECgMIBAAAAA==.Brewmaster:BAAALAAECgEIAQAAAA==.Bricklethumb:BAAALAADCgUIBwAAAA==.Brickred:BAAALAAECgYICQAAAA==.Browny:BAABLAAECoEVAAMDAAgIiiN+AABBAwADAAgIQiN+AABBAwAEAAUIpR9qGQC0AQAAAA==.Brunhilde:BAAALAADCgUICAAAAA==.',Bu='Bucketeer:BAAALAADCgYICQAAAA==.',Ca='Calliope:BAAALAADCggICAAAAA==.Canaprey:BAAALAADCgcIDwAAAA==.Careka:BAAALAADCgMIAwAAAA==.Catshunter:BAAALAADCggIDwAAAA==.',Ce='Celebrían:BAAALAADCgYIBgAAAA==.',Ch='Chantillary:BAAALAADCgIIAgAAAA==.Cheesy:BAAALAADCgYIBgAAAA==.Chopzullee:BAAALAADCggIDwAAAA==.',Cl='Clart:BAAALAADCggICAABLAAECgQIBgABAAAAAA==.',Co='Coljack:BAAALAAECgMIAwAAAA==.Cometodaddy:BAAALAAECgUICgAAAA==.Corali:BAAALAADCggIEQAAAA==.',Cr='Craytork:BAAALAAECgEIAQAAAA==.Crishen:BAAALAADCgEIAQAAAA==.Crocbait:BAAALAAECggIAgAAAA==.Crushma:BAAALAAECgEIAQAAAA==.',Cy='Cyngin:BAAALAADCgcIBwAAAA==.',Da='Daedelus:BAAALAADCggIEQAAAA==.Daglon:BAAALAAECgYICAAAAA==.Darris:BAAALAADCggICAAAAA==.Davidgilmor:BAAALAADCgYIBgAAAA==.',De='Deathslight:BAAALAADCgcIDQAAAA==.Dedaelia:BAAALAADCggICAAAAA==.Deeznutticus:BAABLAAECoEXAAIFAAgIcSEQBwD6AgAFAAgIcSEQBwD6AgAAAA==.Demonspud:BAAALAAECgUIBwAAAA==.Demotard:BAAALAADCgcICAAAAA==.Derdan:BAAALAAECgMIBAAAAA==.Derelict:BAAALAADCgMIAwAAAA==.Destriant:BAAALAAECgMIAwAAAA==.Devilschant:BAAALAAECgYIDAAAAA==.',Di='Dionin:BAAALAADCggIDQAAAA==.',Do='Dodoubleg:BAAALAADCgQIBQAAAA==.Donzilch:BAEALAAECgYICQAAAA==.Doosan:BAAALAADCgYIDAAAAA==.',Dr='Draeca:BAAALAADCgUIBwAAAA==.Dragondznut:BAAALAAECgYICAAAAA==.Drkladykikyo:BAAALAAECgYICAAAAA==.',Dw='Dwarfnukem:BAAALAAECgIIBAAAAA==.',['Dè']='Dègenerate:BAAALAAECgMIBgAAAA==.',Ec='Echoes:BAAALAADCgcIBwAAAA==.',Ed='Eddy:BAAALAAECgIIAgAAAA==.',Ei='Eilae:BAAALAADCggIEQAAAA==.',El='Elroyjunky:BAAALAADCgEIAQAAAA==.Elyrn:BAAALAAECgMIAwAAAA==.Elêktra:BAAALAAECgYICwAAAA==.',Em='Emmigosa:BAAALAADCgYICwAAAA==.',En='Engineers:BAAALAADCgQIBAAAAA==.',Ep='Epicnym:BAAALAADCggIDwAAAA==.',Er='Erja:BAAALAADCgYIBgAAAA==.',Es='Esdeath:BAAALAAECgYICgAAAA==.',Fe='Felsßelle:BAAALAADCggIEAAAAA==.Ferryman:BAAALAADCggIEAAAAA==.',Ff='Fflip:BAAALAADCggICAAAAA==.',Fl='Flarepulse:BAAALAADCgcIBwAAAA==.',Fo='Forphium:BAAALAAECggIEAAAAA==.',Fr='Freezoni:BAAALAADCggIDAAAAA==.Freydís:BAAALAADCgQIBAAAAA==.',Ga='Gagamer:BAAALAAECgIIAgAAAA==.Gahlina:BAAALAADCggIDwAAAA==.Galadun:BAAALAADCgMIAwABLAAECgYICgABAAAAAA==.Gancicle:BAAALAAECgIIAgAAAA==.',Ge='Geekyraventv:BAAALAADCgMIAwAAAA==.',Gi='Gilleyy:BAAALAAECgMIAwAAAA==.Giltry:BAAALAADCggICAAAAA==.Gird:BAAALAAECgYICAAAAA==.',Go='Goatmonger:BAAALAAECgIIAwAAAA==.Gordek:BAAALAAECgIIAwAAAA==.Gothitelle:BAAALAADCgcIBwAAAA==.',Gr='Grantaron:BAAALAAECgMIAwAAAA==.Gribble:BAAALAADCgUIBQAAAA==.Grntitan:BAAALAAECgEIAQAAAA==.',Gu='Guy:BAAALAADCgUIBQAAAA==.',Gw='Gwoohoori:BAAALAAECgYIDAAAAA==.',Ha='Halukari:BAAALAADCggIDgABLAAECgIIAgABAAAAAA==.Harrin:BAAALAAECgEIAQAAAA==.',He='Healingwater:BAAALAAECgEIAQAAAA==.Helya:BAAALAADCgQIBAABLAAECgcIFAAGAHchAA==.Hezrel:BAAALAADCggIDAAAAA==.',Hi='Hiddenhunts:BAAALAADCgMIAwAAAA==.',Hu='Huflungpoop:BAAALAAECgYICwAAAA==.',['Hè']='Hèalz:BAAALAADCggICAAAAA==.',Im='Imcruel:BAABLAAECoEXAAIHAAgIQiX+AgBIAwAHAAgIQiX+AgBIAwAAAA==.',In='Innerpeace:BAAALAAECgIIAwAAAA==.',Ja='Jabes:BAAALAAECgMIBwAAAA==.Jackson:BAAALAADCgUIBQAAAA==.Jatia:BAAALAAECgIIBAAAAA==.',Jo='Jorion:BAAALAAECgEIAQAAAA==.',Ju='Juacqer:BAAALAADCgUIBwAAAA==.Juniper:BAAALAAECgQIBQAAAA==.Juqi:BAACLAAFFIEKAAMHAAUIwR2dAAD3AQAHAAUIuBydAAD3AQAIAAEI8R9uAgBPAAAsAAQKgRkAAgcACAhmJcYCAEwDAAcACAhmJcYCAEwDAAAA.',Ka='Kaant:BAAALAAECgMIBAAAAA==.Kaeni:BAAALAADCgcIDQAAAA==.Kaidevyn:BAAALAAECgEIAgAAAA==.Kaleine:BAAALAADCgMIAwAAAA==.Kammalla:BAAALAAECgYICwAAAA==.Kandy:BAAALAADCgcIBwAAAA==.',Ke='Keiko:BAAALAADCggIDwAAAA==.Keiran:BAAALAAECgMIAwAAAA==.Kellistair:BAAALAADCgUIBQABLAADCgYIBgABAAAAAA==.Kelon:BAAALAAECgIIAgAAAA==.',Kh='Khalnerys:BAAALAAECggIBAAAAA==.Khoudow:BAABLAAECoEVAAIJAAgIDRYxAgBGAgAJAAgIDRYxAgBGAgAAAA==.',Ki='Kiely:BAAALAADCgcICwAAAA==.Kilgrave:BAAALAADCgYIBgAAAA==.Kimmi:BAAALAAECgEIAgAAAA==.Kimpossibull:BAAALAADCgYIBgAAAA==.',Ko='Kotayella:BAAALAAECgMIAwAAAA==.',Kr='Krellic:BAAALAADCgYIBgAAAA==.Kronore:BAAALAADCgQIBQAAAA==.Kruelshot:BAAALAADCggICwABLAAECggIFwAHAEIlAA==.Krustykrunch:BAAALAADCgYIBwAAAA==.',Kt='Kthxbye:BAAALAAECgEIAQAAAA==.',Ku='Kuraishin:BAAALAAECgYIDgAAAA==.Kutter:BAAALAADCgUIBwAAAA==.',Ky='Kylindra:BAAALAADCgcIDAABLAAECgYICQABAAAAAA==.',La='Lailyria:BAAALAAECgYICQAAAA==.Latheal:BAAALAADCgUIBwAAAA==.Lavi:BAAALAADCggICAAAAA==.',Le='Lejeune:BAAALAADCgMIBQAAAA==.Lengex:BAAALAAECgIIAgAAAA==.Leratra:BAAALAAECgMIAwAAAA==.Lero:BAABLAAECoEUAAIGAAcIdyE+BACNAgAGAAcIdyE+BACNAgAAAA==.Lexo:BAAALAAECggICAAAAA==.',Li='Liamwulf:BAAALAADCgUICAABLAADCgUIBwABAAAAAA==.Lindir:BAAALAAECgQIBAAAAA==.Liquor:BAAALAADCgUIBQABLAAECgYICgABAAAAAA==.Liquorish:BAAALAAECgYICgAAAA==.Litasfk:BAAALAAECgIIAgAAAA==.Liuni:BAAALAAECgYICQAAAA==.Liyin:BAAALAADCgMIAwAAAA==.',Lo='Lobotrigger:BAAALAAECgMIBAAAAA==.Locknutz:BAAALAADCgYIDQAAAA==.Lorantell:BAAALAADCgUIBQAAAA==.Lorelynn:BAAALAAECgMIAwAAAA==.',Lu='Luang:BAAALAADCgcIBwAAAA==.Lucìan:BAAALAAECgIIAwAAAA==.Lunaclair:BAAALAAECgUIBQABLAAECgYIDgABAAAAAA==.Lunaraeliana:BAAALAADCgQIBAAAAA==.Lunarielle:BAAALAAECgIIAwAAAA==.',Ma='Macfly:BAAALAAECgYICgAAAA==.Madlock:BAAALAAECgMIAwAAAA==.Mancath:BAAALAAECgMIBgAAAA==.Maru:BAAALAAECgQIBgAAAA==.',Me='Meeko:BAEBLAAECoEWAAIKAAgI7COCAABCAwAKAAgI7COCAABCAwAAAA==.Meow:BAAALAADCgcICgABLAAECgIIAgABAAAAAA==.Mercüry:BAAALAADCgYICQAAAA==.Mestor:BAAALAAECgEIAQAAAA==.',Mi='Midoriya:BAAALAAECgIIAwAAAA==.',Mm='Mmyessmite:BAAALAADCgMIAwAAAA==.',Mo='Monkebizness:BAAALAADCggIEQAAAA==.Morvo:BAAALAAECgYIBgAAAA==.',My='Mya:BAAALAADCggIDwABLAAECgYIDgABAAAAAA==.',Na='Nadyia:BAAALAADCgcIBwAAAA==.Naeko:BAAALAAECgUICQABLAAECgYIDgABAAAAAA==.Nazdormu:BAAALAADCggIDwAAAA==.',Ne='Neisen:BAAALAAECgMIBgAAAA==.',Ni='Nightseed:BAAALAADCgEIAQAAAA==.',No='Norisong:BAAALAADCgcICwAAAA==.',Ny='Nykolas:BAAALAADCgQIBAAAAA==.',Om='Omvfurrealz:BAAALAADCggIDAAAAA==.',On='Onslowbeach:BAAALAADCgIIAgAAAA==.',Or='Orphen:BAAALAADCgEIAQAAAA==.',Pa='Paddleball:BAAALAADCggIEQAAAA==.Papalion:BAAALAADCggIEQAAAA==.',Pd='Pda:BAAALAADCgUIBQABLAAECgYIEgABAAAAAA==.',Pi='Pickleburger:BAAALAAECgEIAQAAAA==.Pinklilydrd:BAAALAADCgUIBwAAAA==.Pizda:BAAALAAECgUICQAAAA==.',Po='Popandlock:BAAALAAECgUICQAAAA==.',Pr='Preaw:BAAALAAECgEIAQAAAA==.Prissidebow:BAAALAADCgUIBwAAAA==.',Ra='Ragbear:BAAALAAECgQIBgAAAA==.Ramblinn:BAAALAAECgYICAAAAA==.Rantis:BAAALAAECgMIBAAAAA==.Raughs:BAAALAADCggIFgAAAA==.Ravenbrook:BAAALAAECgcIEwAAAA==.Rawrr:BAAALAADCggICAAAAA==.Rawrxd:BAAALAADCggIEAAAAA==.Raxie:BAAALAAECgIIAgAAAA==.',Re='Reciprocity:BAAALAAECgMIAwAAAA==.',Ri='Ripmxi:BAAALAAECgYICAAAAA==.',Ro='Roknavar:BAAALAADCgcICwAAAA==.',Ru='Rupertgiless:BAABLAAECoEYAAILAAgI4SHTAADBAgALAAgI4SHTAADBAgAAAA==.',Sa='Sachi:BAAALAADCgcIDAAAAA==.Sacksmasher:BAAALAAECgEIAgAAAA==.Sadimir:BAAALAAECgMIAwAAAA==.Sadoh:BAAALAADCgUIBQAAAA==.Sanctos:BAAALAADCgMIAwAAAA==.Sarcastyx:BAAALAAECgMIBAAAAA==.',Sc='Scaliefox:BAAALAAECgMIBgAAAA==.Scarl:BAAALAAECgEIAQAAAA==.',Se='Seealis:BAAALAADCgcICQAAAA==.Seiphyrr:BAAALAADCgcIEAAAAA==.Senaera:BAAALAADCggICAABLAAECgYICQABAAAAAA==.',Sh='Shox:BAAALAADCgQIBAAAAA==.',Si='Silentfart:BAAALAADCggIDAABLAAECgQIBwABAAAAAA==.Sitzho:BAAALAAECgIIAgAAAA==.',Sk='Skybringer:BAAALAAECgMICQAAAA==.Skyedrin:BAAALAAECgUIAwAAAA==.Skyepally:BAAALAADCgQIBAABLAAECgUIAwABAAAAAA==.',Sl='Slambo:BAAALAAECgIIAgAAAA==.Slowburn:BAAALAADCgMIBQAAAA==.',So='Soxxy:BAAALAAECgEIAQABLAAECgYIEgABAAAAAA==.',Sp='Spoons:BAAALAAECgYICQAAAA==.Spyroh:BAAALAADCgUICAAAAA==.',St='Stabnificent:BAAALAADCggICAAAAA==.Stigger:BAAALAADCgUIBQAAAA==.Strombjorn:BAAALAAECgUIBQAAAA==.',Su='Supergobbo:BAAALAADCggICQAAAA==.Surprise:BAAALAAECgcIEgAAAA==.',Sx='Sx:BAAALAAECgYIEgAAAA==.',Sy='Sylaris:BAAALAADCgYIBgABLAAECgcIFwALAPwaAA==.Syssaelsia:BAAALAADCgYIBgAAAA==.',Ta='Tazaller:BAAALAADCgUIBQAAAA==.',Th='Thirox:BAAALAADCgEIAQAAAA==.Thotñprayers:BAAALAAECgYIBwAAAA==.Thòr:BAAALAADCgQIBAAAAA==.',To='Toranaar:BAAALAADCgcIBwAAAA==.Toya:BAAALAADCggIEAAAAA==.',Tr='Trees:BAAALAADCggIFQAAAA==.Trevain:BAAALAADCgUIBwAAAA==.Truthordare:BAAALAADCgcIBwAAAA==.Trèe:BAAALAADCgcIBwAAAA==.',Tu='Turtl:BAABLAAECoEVAAIMAAgIQCWnAABoAwAMAAgIQCWnAABoAwAAAA==.',Ty='Tydeland:BAAALAADCgYICQAAAA==.Tyryn:BAAALAAECgYICQAAAA==.',Ug='Uglydruid:BAAALAADCgcICQAAAA==.Uglymage:BAAALAADCggICwAAAA==.Uglypriest:BAAALAAECgcICwAAAA==.',Ul='Ulthadar:BAAALAADCggICQAAAA==.',Un='Unbalancéd:BAAALAADCgUICwAAAA==.',Va='Vaeadin:BAAALAADCggIDwAAAA==.Vahra:BAAALAADCgUIBwAAAA==.Valantis:BAAALAADCggIEAAAAA==.Valantor:BAAALAAECgcICgAAAA==.Valgaskav:BAAALAAECgYICwAAAA==.Vanhirksing:BAAALAAECgEIAQAAAA==.',Ve='Vegasnight:BAAALAADCggICAAAAA==.Velariel:BAAALAADCggICAAAAA==.Velisa:BAAALAAECgIIAgAAAA==.',Vo='Voidling:BAAALAAECggIBgAAAA==.Voidstruth:BAAALAADCggICAAAAA==.Voker:BAAALAAECgIIAgAAAA==.Volos:BAAALAAECgMIAwAAAA==.Volrx:BAAALAADCggIAgAAAA==.Vordaman:BAAALAAECgMIBgAAAA==.',Vy='Vyeahhgruh:BAAALAAECgYICwAAAA==.Vynír:BAABLAAECoEXAAILAAcI/BrLBwDoAQALAAcI/BrLBwDoAQAAAA==.',['Vö']='Völvå:BAAALAAECgMIAwAAAA==.',Wa='Waanpriest:BAAALAADCggIDgAAAA==.Waghoba:BAAALAAECgYICAAAAA==.Warfle:BAAALAADCgMIAwAAAA==.Warrionomous:BAAALAAECgQIBwAAAA==.Washu:BAAALAAECgQIBwAAAA==.',Wi='Wisdomheart:BAAALAADCgYIBgAAAA==.',Wo='Wonderbread:BAAALAAECgYICgAAAA==.',Wr='Wrager:BAAALAAECgIIAgAAAA==.',['Wâ']='Wârwôlf:BAAALAAECgYICQAAAA==.',Xi='Xisa:BAAALAADCggIBwAAAA==.',Xt='Xtrolldinary:BAAALAADCggIDwAAAA==.',Xu='Xunara:BAAALAAECgIIAgAAAA==.',Ya='Yawnsha:BAAALAAECgEIAQAAAA==.',Ye='Yeast:BAAALAAECgMIBgAAAA==.Yeastmode:BAAALAADCggICQAAAA==.Yercdaddy:BAAALAAECgEIAQAAAA==.Yessenia:BAAALAADCggICAAAAA==.',Yi='Yingsol:BAAALAADCgYIBgAAAA==.',Yo='Yonah:BAAALAADCgIIBAAAAA==.York:BAAALAAECgMIAwAAAA==.You:BAAALAAECgEIAQAAAA==.',Yp='Ypshay:BAAALAADCgcIDQAAAA==.',Ys='Ysondra:BAAALAADCgUIBwAAAA==.',Yv='Yvelthilios:BAAALAADCggICAAAAA==.',Za='Zademan:BAAALAADCgYIBgAAAA==.',Ze='Zeebra:BAAALAAECgYICAAAAA==.Zega:BAAALAADCgUIBQAAAA==.',Zi='Zillionbucks:BAAALAADCggICAABLAAECggIFgANAG8hAA==.Zillionbúcks:BAABLAAECoEWAAINAAgIbyEoCQDrAgANAAgIbyEoCQDrAgAAAA==.',Zu='Zulrogue:BAAALAAECgMIBQAAAA==.',['Zê']='Zêddicus:BAAALAAECgYICwAAAA==.',['Áq']='Áquafina:BAAALAAECgYIDQAAAA==.',['Ål']='Ållanon:BAAALAADCggICAAAAA==.',['Ðö']='Ðö:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end