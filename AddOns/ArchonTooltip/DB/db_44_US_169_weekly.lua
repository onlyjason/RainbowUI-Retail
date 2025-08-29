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
 local lookup = {'Mage-Arcane','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Warrior-Arms','Warrior-Fury','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Elemental','DemonHunter-Havoc','Monk-Windwalker','DeathKnight-Frost','Druid-Balance','Priest-Holy','Druid-Guardian','Warlock-Demonology','Priest-Shadow','Priest-Discipline','Mage-Frost','Shaman-Enhancement','Monk-Brewmaster','Hunter-BeastMastery','Shaman-Restoration',}; local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aairidari:BAAALAAECgMIBAAAAA==.',Ab='Abruna:BAAALAAECgYICQABLAAECggIFQABAC8iAA==.Abruno:BAABLAAECoEVAAIBAAgILyJQBgAUAwABAAgILyJQBgAUAwAAAA==.',Ad='Adaama:BAAALAADCgcICwAAAA==.',Ae='Aeown:BAAALAADCggIFgABLAAECgcIEAACAAAAAA==.Aerdis:BAAALAADCggICAAAAA==.',Ah='Ahsoul:BAAALAADCgUIBgAAAA==.',Ak='Akamaruu:BAAALAADCgcIDQAAAA==.Akames:BAAALAAECggIDgAAAA==.Aki:BAAALAAECgMIAwAAAA==.',Al='Alahrî:BAAALAAECgcIEAAAAA==.Alandrìas:BAAALAAECgcIDAAAAA==.Alinice:BAAALAADCgEIAQAAAA==.Altera:BAAALAAECgMIBQAAAA==.Alterboy:BAAALAADCgYIBgAAAA==.',Am='Ambessa:BAAALAADCgcICgAAAA==.',An='Andere:BAAALAAECgcIDwAAAA==.Androonatorz:BAABLAAECoEVAAIDAAgIvhvTAwCrAgADAAgIvhvTAwCrAgAAAA==.Anfernay:BAAALAAECgMIBAAAAA==.Angelbearly:BAAALAADCgYIBgAAAA==.Ankylotroll:BAAALAAECgMIAwAAAA==.Annihilate:BAAALAADCgMIAwAAAA==.Anímality:BAAALAAECgMIAwAAAA==.',Ap='Apawthetic:BAEALAAECgYIBgABLAAECggIFQAEAN0gAA==.Apollõ:BAAALAADCgcIBQAAAA==.Apris:BAABLAAECoEUAAIBAAcI/R5gGwA1AgABAAcI/R5gGwA1AgAAAA==.',Ar='Arcangila:BAEALAAECgcICwAAAA==.Ardell:BAEALAADCggIDgAAAA==.Arkena:BAAALAADCgMIAwAAAA==.Arolaide:BAAALAAECgMIAwAAAA==.Arveiturace:BAAALAADCggIDwAAAA==.Arîkard:BAAALAAECgcIDQAAAA==.',As='Ashnîkko:BAAALAADCgQIBAAAAA==.Ashtar:BAAALAAECgIIAwAAAA==.Ashtomouth:BAAALAAECgMIBQAAAA==.',At='Atreia:BAAALAAECgIIAgAAAA==.',Au='Aura:BAAALAAECgUIBwAAAA==.Auronok:BAAALAADCgUIBQAAAA==.',Ba='Baconegg:BAAALAAECgMIBgAAAA==.Barma:BAAALAAECgcIEQAAAA==.Barrin:BAAALAAECgQIBgAAAA==.',Be='Beldaa:BAAALAAECgMIAwAAAA==.',Bi='Biggameanto:BAAALAADCgcICgAAAA==.Bigwill:BAAALAAECgYICAAAAA==.Bird:BAAALAAECgcIDQAAAA==.',Bl='Blargy:BAAALAAECgYIDQAAAA==.Bloodshed:BAAALAADCgcIDAAAAA==.',Bo='Bofadeez:BAAALAAECgMIBQAAAA==.Boudicah:BAAALAADCggIEQAAAA==.',Br='Brandra:BAAALAADCgMIAwAAAA==.Brewslee:BAAALAADCgQIBAAAAA==.Brokkr:BAAALAADCgMIAwAAAA==.Brookk:BAAALAADCggICAAAAA==.Bruce:BAAALAAECgcICwAAAA==.',Ca='Caliburne:BAAALAAECgcIDwAAAA==.Capz:BAACLAAFFIEIAAMFAAUI+xwTAAA4AQAGAAUIdByDAADsAQAFAAMIQyITAAA4AQAsAAQKgRgAAwUACAibJpgAABkDAAYACAhvJnsDADwDAAUABwhGJpgAABkDAAAA.',Cd='Cdlam:BAAALAADCgMIAwAAAA==.',Ce='Ceez:BAAALAADCgcIDQAAAA==.Celebrïmbor:BAAALAADCggIDwAAAA==.',Ch='Cherrycola:BAAALAADCgcICAAAAA==.Chickenstwip:BAAALAADCgcICAAAAA==.Childeater:BAAALAADCgMIAwAAAA==.Chârmy:BAAALAAECgUICAAAAA==.Chèn:BAAALAAECgQIBgAAAA==.',Ci='Cindertaro:BAAALAAECgMIAwAAAA==.',Cl='Clayre:BAAALAAECgcIDgAAAA==.Clow:BAAALAAECgIIBAAAAA==.',Co='Coolcrush:BAAALAAECgMIBQAAAA==.Cornelia:BAAALAADCgQIBgAAAA==.',Cr='Critzwar:BAAALAAFFAEIAQAAAA==.Cráite:BAAALAADCgMIAwAAAA==.',Da='Daedyxes:BAAALAAECgIIAgAAAA==.Darfretail:BAAALAADCgUIAQAAAA==.Darkmagi:BAAALAADCgcICgAAAA==.Dasherdeez:BAAALAADCgYIDgAAAA==.Dateknight:BAAALAADCgcICQAAAA==.',De='Deadlyiris:BAAALAAECgYIDQAAAA==.Deathsmalice:BAAALAADCggIDgAAAA==.Demonbulio:BAAALAAECgMIAwAAAA==.Demonisthicc:BAAALAAECgYIDgAAAA==.Demonskitten:BAAALAADCgQIBAABLAAECgYIDgACAAAAAA==.Demonslayeer:BAAALAADCgcIBwAAAA==.',Di='Diablos:BAAALAAECgMIAwAAAA==.Dirtyearl:BAAALAAECgMIBgAAAA==.Dithehealer:BAAALAAECgUICAAAAA==.Divinecandie:BAAALAADCgYIBgAAAA==.',Do='Donkeyshot:BAAALAAECgUIBQABLAAECgYIBgACAAAAAA==.Dontoro:BAAALAADCgcICQAAAA==.',Dr='Dracon:BAAALAAECgIIAgAAAA==.Draglone:BAAALAADCgcICQAAAA==.Drama:BAAALAADCgcICgAAAA==.Dranåk:BAAALAADCggICgAAAA==.Drenamai:BAAALAAECgMIBAAAAA==.Drevi:BAAALAAECgMIBQABLAAECgYIBgACAAAAAA==.Drexel:BAAALAADCgYIBgAAAA==.',Du='Dudeimhighaf:BAAALAAECgQIBgAAAA==.',Ed='Edrocz:BAEALAADCgYIBwABLAADCggIDgACAAAAAA==.',Eh='Ehmehzing:BAABLAAECoEXAAIHAAgIdyU9AgBkAwAHAAgIdyU9AgBkAwAAAA==.',El='Eliicia:BAABLAAECoEXAAQIAAgI3xlbBQDaAQAJAAcIVxV1EAAbAgAIAAcIyRVbBQDaAQAKAAMImQTGCgCXAAAAAA==.Elvwyr:BAAALAADCgcIBwAAAA==.',Em='Emizzar:BAAALAAECgYICQAAAA==.Emmetcullen:BAABLAAECoEVAAILAAgIbxyPCADOAgALAAgIbxyPCADOAgAAAA==.',En='Endo:BAAALAAECgYICQABLAAECgcIFAAMAFUkAA==.Endorush:BAABLAAECoEUAAIMAAcIVSTpCgDVAgAMAAcIVSTpCgDVAgAAAA==.',Er='Ereitherla:BAAALAAECgIIAgAAAA==.',Ev='Evergreen:BAAALAADCgMIAwABLAADCgcIDgACAAAAAA==.',Fa='Farc:BAAALAADCgMIBQAAAA==.',Fd='Fdk:BAAALAADCgQIBAAAAA==.',Fe='Feane:BAAALAADCgYICgAAAA==.Feironor:BAAALAAECgIIBAAAAA==.Feldown:BAAALAAECgEIAQAAAA==.',Fl='Floppydisc:BAAALAADCgYIBgAAAA==.',Fo='Forepray:BAAALAAECgYIBgAAAA==.Forger:BAAALAAECgIIAgAAAA==.',Fr='Freeballin:BAAALAADCgYIBgABLAADCgcIBwACAAAAAA==.Frostywaffle:BAAALAADCggICAAAAA==.',Fu='Future:BAAALAAECgUIBAABLAAECggIEAACAAAAAA==.',['Fö']='Föxtrot:BAABLAAECoEVAAINAAgIjBBaDADrAQANAAgIjBBaDADrAQAAAA==.',Ga='Galinddra:BAAALAADCggIDwAAAA==.',Gi='Givr:BAAALAADCgcIBwAAAA==.',Gl='Glone:BAAALAADCgIIAgAAAA==.',Gn='Gnatt:BAAALAADCgMIBgABLAADCgcICQACAAAAAA==.Gnomemash:BAABLAAECoEUAAIOAAcImB4CGgAuAgAOAAcImB4CGgAuAgAAAA==.',Go='Golgotterath:BAAALAAECggIEgAAAA==.Gorm:BAAALAAECgYIDAAAAA==.',Gr='Greenmeanie:BAAALAADCgYIBgAAAA==.Grimzero:BAAALAADCgcIDAAAAA==.',Ha='Hadel:BAEALAADCgYIBgABLAADCggIDgACAAAAAA==.Haldane:BAAALAAECgYICwABLAAECgYIDQACAAAAAA==.Havochunter:BAAALAADCgcIEgAAAA==.',He='Heraois:BAAALAAECgYIBgAAAA==.',Ho='Holypimp:BAAALAADCgUIBQAAAA==.Holywráth:BAAALAADCgcIBwAAAA==.',Hu='Hucklebearer:BAAALAADCgcICQAAAA==.Huney:BAAALAADCgYIBgAAAA==.Hunterdh:BAAALAAECgIIAgAAAA==.',['Hî']='Hîngbé:BAAALAADCgcIBwAAAA==.',In='Innervatez:BAACLAAFFIELAAIEAAYIFBMeAAA3AgAEAAYIFBMeAAA3AgAsAAQKgRgAAwQACAjGH/kGAIYCAAQACAjGH/kGAIYCAA8AAwifEr4xAMsAAAAA.',Iv='Ivy:BAAALAADCgcICQABLAADCggIEQACAAAAAA==.',Ja='Jakey:BAAALAAECgYIBwAAAA==.Jakie:BAAALAADCgYIBgAAAA==.Jammo:BAAALAADCgUIBgAAAA==.Jarten:BAAALAAECgMIBgAAAA==.Jaylebate:BAAALAAECgYIBgAAAA==.',Je='Jerrenn:BAAALAADCgUIBQABLAAECgIIAwACAAAAAA==.Jesseatamer:BAAALAAECgMIBwAAAA==.',Jh='Jhendrakar:BAAALAADCgMIBgAAAA==.',Ka='Kaera:BAAALAAECgYICQAAAA==.Kalenn:BAAALAADCggIDwABLAADCgMIAwACAAAAAA==.Karne:BAAALAADCgUIBQAAAA==.Kastia:BAAALAADCgcICwAAAA==.Katsumi:BAAALAADCgcIDAAAAA==.Kaunaz:BAAALAAECgEIAQAAAA==.',Ke='Keladorian:BAAALAADCgYIBgAAAA==.Kellenah:BAAALAADCgMIAwAAAA==.',Ki='Killalltoday:BAAALAAECgMIBQAAAA==.Killersmile:BAAALAADCgUIBQAAAA==.Kiren:BAAALAAECgQIBgAAAA==.Kirkk:BAAALAADCgcIDAAAAA==.Kittywaffles:BAAALAADCgcIBwAAAA==.',Kn='Knixx:BAABLAAECoEVAAIQAAgIbR8LBAD1AgAQAAgIbR8LBAD1AgAAAA==.',Ko='Koshka:BAAALAADCggIFwAAAA==.Kotastrophe:BAAALAAECgcICwAAAA==.',Kr='Krispykreme:BAAALAADCgcIFQAAAA==.',Ku='Kufoo:BAAALAAECgMIBQAAAA==.Kurao:BAAALAAECgEIAQAAAA==.Kurukai:BAAALAADCgcICAAAAA==.',Ky='Kynlerrine:BAAALAAECgMIBQAAAA==.',['Ké']='Kéndra:BAAALAADCgMIAwAAAA==.',La='Lagolas:BAAALAAECgQIBAAAAA==.Laridee:BAAALAAECgYIDAAAAA==.',Le='Leo:BAAALAAECgIIAwAAAA==.Lethe:BAAALAAECgYIBwABLAAECggIFwAIAN8ZAA==.Letsgethexy:BAAALAADCgcIDgAAAA==.',Li='Light:BAAALAAECgEIAQABLAAECggIEAACAAAAAA==.Linkover:BAAALAAECgQIBAAAAA==.Linkstar:BAAALAAECgcIDgAAAA==.',Lo='Loendrokos:BAAALAADCgQIBAAAAA==.Lohal:BAAALAAECgYIDQAAAA==.Lovekiing:BAAALAAECgMIBQAAAA==.',Lu='Luania:BAAALAADCgcICwAAAA==.Luulu:BAAALAADCgUICwABLAADCggIEQACAAAAAA==.',Ma='Mamadeezy:BAAALAADCgYIBgAAAA==.Matthyjsz:BAAALAADCgcICwAAAA==.',Mc='Mcshen:BAAALAAECgIIAgAAAA==.',Me='Megumin:BAAALAADCgcIDQABLAAECgcIEAACAAAAAA==.Merek:BAAALAAECgMIAwAAAA==.',Mi='Mistyd:BAACLAAFFIEFAAIRAAMI7wlIAADMAAARAAMI7wlIAADMAAAsAAQKgRcAAhEACAgSGSYCADYCABEACAgSGSYCADYCAAAA.',Mo='Mollyhatchet:BAAALAADCggIEAAAAA==.Moocifer:BAAALAADCgcICQAAAA==.Moonwraithe:BAAALAADCgcICgAAAA==.Morayle:BAAALAADCgMIAwAAAA==.Morgause:BAAALAAECgEIAQAAAA==.',My='Myolnir:BAAALAAECgcIDQAAAA==.',['Må']='Mångix:BAAALAAECgIIAgAAAA==.',['Mé']='Mélusine:BAAALAAECgcIEAAAAA==.',['Mï']='Mïsterlovett:BAAALAADCgYIBgABLAADCgcICgACAAAAAA==.',Na='Naksami:BAAALAADCggIFAAAAA==.',Ne='Necrotoxin:BAAALAADCgcICgAAAA==.Nenluin:BAAALAADCgMIAwAAAA==.',Ni='Nickfury:BAAALAAECgcIEAAAAA==.Nightsever:BAAALAAECggIEAAAAA==.Nilleria:BAABLAAECoETAAISAAgI9iBwAQCVAgASAAgI9iBwAQCVAgAAAA==.Nirath:BAAALAAECgMIBQAAAA==.',No='Nod:BAAALAADCgMIAwAAAA==.Nohunt:BAAALAADCgIIAgAAAA==.Nopriest:BAABLAAECoEdAAQTAAcILSOzCADBAgATAAcILSOzCADBAgAQAAUIngt7NgAEAQAUAAEIrgGoHAAgAAAAAA==.Notaboomkin:BAAALAADCggIFgAAAA==.',Oh='Ohface:BAAALAAECgMIAwAAAA==.',On='Onehotelf:BAAALAAECgEIAQAAAA==.',Oo='Oohshiny:BAAALAAECgQIBgAAAA==.Ooyagoddess:BAAALAADCgcIBwAAAA==.',['Oì']='Oìzys:BAAALAADCgEIAQAAAA==.',Pa='Pacamonk:BAAALAAECgcIDQAAAA==.Pantevon:BAAALAADCgYIBgAAAA==.Papatiny:BAAALAAECgYICQAAAA==.Pawnduh:BAAALAADCggIFwABLAAECgIIAgACAAAAAA==.Pawpatine:BAAALAAECgIIAgAAAA==.Pawthetic:BAEBLAAECoEVAAIEAAgI3SCgAgDwAgAEAAgI3SCgAgDwAgAAAA==.',Pe='Peelforheals:BAAALAAECgIIAgAAAA==.Penguindemic:BAAALAAECgYIDgAAAA==.Penguinmagi:BAAALAADCgYIBgABLAAECgYIDgACAAAAAA==.Petruccius:BAAALAAECgYIDgAAAA==.Pew:BAAALAAECgcIEAAAAA==.Pewpewbah:BAAALAADCgIIAgAAAA==.',Pi='Pinko:BAAALAAECgMIAwAAAA==.Pirate:BAAALAADCgUICAABLAAECggIEAACAAAAAA==.',Po='Poppop:BAAALAADCgMIAwAAAA==.',Pr='Prumper:BAABLAAECoEUAAIVAAgIIBZxCABIAgAVAAgIIBZxCABIAgAAAA==.',Pu='Puffinondank:BAAALAADCggICAAAAA==.Pussoflight:BAAALAAECggICAAAAA==.',Ra='Rabid:BAAALAAECgQIBAAAAA==.Ramzey:BAAALAAECgcIEAAAAA==.',Re='Regena:BAAALAAECgcIEAAAAA==.Remorse:BAAALAAFFAIIBAAAAA==.Required:BAAALAAECgEIAQAAAA==.Rethan:BAAALAADCggIDwAAAA==.Revid:BAAALAAECgIIAgABLAAECgYIBgACAAAAAA==.Revnaá:BAAALAADCgEIAQAAAA==.Reyon:BAAALAADCgEIAQAAAA==.',Ri='Riggo:BAAALAAECgYIBgAAAA==.',Ro='Rockandshock:BAAALAAFFAMIBAAAAA==.Ronfar:BAABLAAECoEUAAIWAAgIox9kAgC1AgAWAAgIox9kAgC1AgAAAA==.',Ru='Rueger:BAAALAAECgUIBwAAAA==.Rukidingme:BAAALAADCggIDQAAAA==.Rumonkingme:BAAALAADCgcIDgAAAA==.Ruttisðir:BAAALAAECgIIAgAAAA==.',Ry='Ryhorn:BAAALAAECgYICQAAAA==.Ryno:BAAALAADCgYIBwAAAA==.Ryuko:BAAALAADCgEIAQABLAAECgcIEAACAAAAAA==.',Sa='Sabnacke:BAAALAAECgcIDQAAAA==.Saitak:BAAALAADCggICAAAAA==.Sanazenet:BAAALAAECgIIAgAAAA==.Saphiras:BAAALAAECgEIAQAAAA==.Sauracerer:BAAALAADCggICgAAAA==.',Sc='Scubowsuit:BAAALAAECgMIBAAAAA==.',Se='Seliria:BAAALAADCgcIBwAAAA==.Semy:BAAALAADCgcIBwAAAA==.Senorchang:BAAALAADCggICAABLAAECggIFQALAG8cAA==.Seswatha:BAAALAAECgIIAgABLAAECggIEgACAAAAAA==.Setzero:BAAALAAECgQIBAAAAA==.',Sh='Shaltear:BAAALAADCgIIAgAAAA==.Shamandroo:BAAALAADCgIIAgABLAAECggIFQADAL4bAA==.Shamdi:BAAALAADCgcIBwAAAA==.Shmongus:BAAALAAECgMIAwAAAA==.Shortandold:BAAALAAECgYIBgAAAA==.Shìft:BAAALAAECgcIDQAAAA==.',Si='Sightofhand:BAAALAAECgMIBgAAAA==.Siki:BAAALAADCgcIBwAAAA==.Sillynanny:BAAALAADCgYICQAAAA==.Sinfulghost:BAAALAAFFAIIAgAAAA==.',Sk='Skybluhunter:BAAALAADCgIIAgAAAA==.',Sl='Slight:BAAALAADCgYIBgABLAADCggIDwACAAAAAA==.Slimydruid:BAAALAADCgYIBgAAAA==.Slow:BAAALAAECggIEAAAAA==.',Sm='Smokinontech:BAAALAADCgQIBAAAAA==.',Sn='Snape:BAAALAADCgcICQAAAA==.',So='Sonicsalt:BAAALAADCgEIAQAAAA==.Sonícberger:BAAALAAECgYICQAAAA==.Soulpatch:BAAALAADCgUIBQAAAA==.',Sq='Squee:BAAALAAECgYIDQAAAA==.',St='Stonepalm:BAAALAADCgcIBwAAAA==.Stratan:BAAALAADCggICAAAAA==.',Su='Suffer:BAAALAAECgMIAwABLAAECggIEAACAAAAAA==.Sultree:BAAALAADCggIEAAAAA==.Sunjinwoo:BAAALAADCgIIAgAAAA==.Supercat:BAAALAADCgIIAgAAAA==.Surai:BAAALAADCgYICgAAAA==.Surf:BAAALAAECgIIAwAAAA==.',Sw='Swankydranky:BAABLAAECoEVAAMNAAgIdxelCgAOAgANAAcIDBmlCgAOAgAXAAMIQgyGGQCBAAAAAA==.Swankyorcs:BAAALAAECgYICQABLAAECggIFQANAHcXAA==.Swizzydk:BAAALAAECgcICwAAAA==.',['Sà']='Sàber:BAAALAADCgcIDgAAAA==.',Ta='Tabbz:BAAALAAECgEIAQAAAA==.Taieb:BAAALAAECgMIBAAAAA==.Tallyhochick:BAAALAAECgcIDQAAAA==.Tangerine:BAAALAADCgYIBgABLAAECgcIEAACAAAAAA==.Taremian:BAAALAAECgYIBgAAAA==.Taylerswift:BAAALAADCgIIAgAAAA==.',Te='Teroch:BAAALAADCgEIAQAAAA==.',Th='Theigh:BAAALAADCgUIBQAAAA==.Theory:BAAALAADCgMIAwAAAA==.Thriller:BAAALAADCgMIAwAAAA==.',Ti='Tinyknowheal:BAAALAADCgcIBwAAAA==.Tinytamer:BAAALAAECgcIEAAAAA==.',To='Toko:BAACLAAFFIEFAAIYAAMI7x/1AAA0AQAYAAMI7x/1AAA0AQAsAAQKgRcAAhgACAiGJKYDADADABgACAiGJKYDADADAAAA.Tomblord:BAAALAAECgUIBwAAAA==.',Tr='Treeheals:BAAALAAECgcIDgAAAA==.Truthes:BAAALAADCgYIBgABLAAECgMIBgACAAAAAA==.Truthful:BAAALAAECgMIBgAAAA==.Truthx:BAAALAADCggIFQABLAAECgMIBgACAAAAAA==.',Tw='Twin:BAAALAAECgMIAwABLAAECgcIFAAOAJgeAA==.',Ty='Tylaatape:BAAALAAECgYICAAAAA==.',['Të']='Tës:BAAALAADCgcIDgAAAA==.',['Tõ']='Tõkõ:BAAALAADCggICAABLAAFFAMIBQAYAO8fAA==.',Ud='Udontsay:BAAALAADCgYICgABLAADCggIDQACAAAAAA==.',Um='Umbrae:BAAALAAECgcIDQAAAA==.',Uz='Uzala:BAAALAADCggIDQAAAA==.',Va='Va:BAAALAADCgQIBAAAAA==.Vadose:BAAALAAECgMIAwAAAA==.Valkrium:BAAALAADCgEIAQAAAA==.Valrom:BAAALAAECgIIAwAAAA==.Valyris:BAAALAAECgYICQAAAA==.Varissa:BAAALAADCgcIBwAAAA==.',Ve='Vendiy:BAAALAAECgUIBwAAAA==.Vendiyre:BAAALAADCgUIBQAAAA==.Vengefurdead:BAAALAADCggIDAAAAA==.Verdantjr:BAAALAAECgEIAQAAAA==.',Vi='Viperheals:BAAALAADCgUIBQAAAA==.',Vo='Voidbloom:BAAALAAECgYIDgAAAA==.Vonhagen:BAAALAADCgMIAwAAAA==.Vorgol:BAAALAAECgYIDgAAAA==.',Vy='Vynlenus:BAAALAADCgUIBwAAAA==.',Wa='Warkarea:BAAALAADCgcIBwABLAAECgEIAQACAAAAAA==.Warkareous:BAAALAAECgEIAQAAAA==.Warlockies:BAAALAADCgMIAwAAAA==.',We='Westerin:BAAALAAECgUICAAAAA==.',Wh='Whachagonado:BAAALAADCgcIDQAAAA==.',Wi='Widgetmaker:BAAALAADCgMIAwAAAA==.Wimateeka:BAAALAAECgYICQAAAA==.Windigo:BAAALAAECgQIBAAAAA==.Winginit:BAEALAAECgMIAwABLAAECggIFQAEAN0gAA==.',Ya='Yachak:BAAALAADCgUIBwAAAA==.',Yo='Yogí:BAABLAAECoEVAAMZAAgIwR4CBwCdAgAZAAgIwR4CBwCdAgALAAUIHg+3LgAzAQAAAA==.Yozomoto:BAAALAAECgMIAwAAAA==.',Za='Zalandria:BAAALAADCggIEgAAAA==.',Zi='Zipfizzle:BAAALAADCgYIAwAAAA==.Zipsion:BAAALAAECgQICAAAAA==.Zivver:BAAALAADCgUIBQAAAA==.',Zu='Zuoval:BAAALAAECgcIEAAAAA==.',['Zø']='Zørne:BAAALAAECgEIAQAAAA==.',['Æn']='Ænima:BAAALAADCggICwABLAAECgQIBAACAAAAAA==.',['Üt']='Üther:BAAALAAECgcIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end