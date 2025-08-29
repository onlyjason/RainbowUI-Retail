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
 local lookup = {'Unknown-Unknown','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Druid-Guardian','DeathKnight-Frost','Druid-Restoration',}; local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aeliena:BAAALAADCgUIDQAAAA==.Aenstar:BAAALAAECgEIAQAAAA==.',Ag='Aggrothiss:BAAALAADCgIIAgAAAA==.',Ak='Akuugar:BAAALAAECgYICgAAAA==.',Al='Aldenton:BAAALAADCgIIAgAAAA==.',Am='Amaneeda:BAAALAADCggIFwAAAA==.Amazonia:BAAALAADCgcIDAAAAA==.Amphloo:BAAALAADCggICwAAAA==.',An='Andúril:BAAALAADCgcIBwAAAA==.Anotherdh:BAAALAAECgIIAgAAAA==.Antagonis:BAAALAADCggIEgAAAA==.Antihandsome:BAAALAAECgEIAQAAAA==.',Ap='Aphrodlte:BAAALAADCgIIAwAAAA==.',Ar='Aragorñ:BAAALAADCgcICwAAAA==.Arashe:BAAALAADCggIDwAAAA==.Arganos:BAAALAAECgUIBwAAAA==.Arkhorn:BAAALAADCggIFAAAAA==.',As='Asa:BAAALAADCgYIBgAAAA==.Ashaktalos:BAAALAADCgUIBQAAAA==.Aspyn:BAAALAADCgcIBwAAAA==.',At='Atenea:BAAALAADCgYIBgAAAA==.Atheïst:BAAALAAECgYICgAAAA==.',Au='Aurite:BAAALAAFFAMIBQAAAQ==.Aurorapup:BAAALAADCgcIBwAAAA==.',Av='Aventon:BAAALAADCggICAABLAAECgUIBwABAAAAAA==.',Ba='Baconlittle:BAAALAAECgIIAgAAAA==.Baleste:BAAALAADCgUIBQAAAA==.Bammbamm:BAAALAAECgIIAgAAAA==.Banewreak:BAAALAAECgEIAQAAAA==.Baradin:BAAALAADCgUIBQAAAA==.Barind:BAAALAAECgcIEAAAAA==.Bashelar:BAAALAADCggIDQAAAA==.',Bd='Bdawg:BAAALAADCgcICAAAAA==.',Be='Beerjitsu:BAAALAADCggIEAAAAA==.Bena:BAAALAADCgIIAgAAAA==.Betrayer:BAAALAAECgIIBAAAAA==.',Bi='Bietony:BAAALAADCgcIDAAAAA==.Bigak:BAAALAADCgQIBAAAAA==.Bigdisc:BAAALAADCgYIBgAAAA==.',Bo='Bossdwarf:BAAALAADCgQIBAAAAA==.Bovinebishop:BAAALAADCgcICQAAAA==.',Br='Briana:BAAALAADCgcIBwAAAA==.Brotherjason:BAEBLAAECoEbAAICAAgIjCF0AAAWAwACAAgIjCF0AAAWAwAAAA==.Brothervoker:BAAALAAECgMIAwAAAA==.',Bu='Bubba:BAAALAAECgEIAQAAAA==.Buttersworth:BAAALAAECgcIDQAAAA==.',Ca='Caatia:BAAALAAECgIIAgABLAAECgQIBgABAAAAAA==.Carryharder:BAAALAAECgMIAgAAAA==.Carthel:BAAALAAECgQIBAAAAA==.Catalla:BAAALAADCgYIDAAAAA==.',Ch='Chase:BAAALAADCggICAAAAA==.Chasseresse:BAAALAADCgcICgAAAA==.',Cr='Crackmonkèy:BAAALAADCgIIAgAAAA==.Cranknspank:BAAALAADCgUIBQAAAA==.Crittykat:BAAALAADCgcICgAAAA==.Cronoz:BAAALAADCggIDwAAAA==.',['Có']='Cózmik:BAAALAADCgcICAAAAA==.',Da='Dace:BAAALAADCgcICwAAAA==.Daddyalfredd:BAAALAAECgYIDwAAAA==.Daestra:BAAALAADCggICQAAAA==.Dahlie:BAAALAAECgMIBQAAAA==.Daliela:BAAALAAECggICgAAAA==.Dalya:BAAALAADCgcIDAAAAA==.Dartog:BAAALAADCgQIBAAAAA==.Dayel:BAAALAADCgcIEgAAAA==.',De='Deathratell:BAAALAADCgUIBQAAAA==.Dedfred:BAAALAADCggIGwAAAA==.Dekard:BAAALAADCggIBwAAAA==.Deklock:BAAALAADCgcIBwABLAADCggIBwABAAAAAA==.Dekunarreia:BAAALAADCggIEgAAAA==.Deltee:BAAALAADCgcIFAAAAA==.Demoiselle:BAAALAADCggIDwAAAA==.Demonkila:BAAALAADCggIFwAAAA==.Demonyx:BAAALAADCgMIAwAAAA==.Destinÿ:BAAALAAECgMIBAAAAA==.Devildonnix:BAAALAADCgIIAgAAAA==.',Dh='Dhaiul:BAAALAADCgcICwAAAA==.',Di='Dispel:BAAALAAECgEIAQAAAA==.Dist:BAAALAADCggIBwAAAA==.',Do='Domminatryx:BAAALAAECgYICAAAAA==.',Dr='Dragoncheese:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Dragunov:BAAALAAECgIIAgAAAA==.Drakentales:BAAALAADCggIEAAAAA==.Dreathhammer:BAAALAAECgcIEAAAAA==.',Du='Dunadin:BAAALAADCgQIBAABLAAECgMIBgABAAAAAA==.Dundyrn:BAAALAAECgMIBgAAAA==.Durzarn:BAAALAADCgUIBQAAAA==.',Ed='Edmunin:BAEALAADCgYICwAAAA==.',El='Elememetal:BAAALAADCggIDwAAAA==.',Fa='Fangora:BAAALAADCgIIAgAAAA==.Fanmir:BAAALAADCgMIBQAAAA==.Fatpao:BAAALAADCgUIBQAAAA==.',Fe='Felscar:BAAALAADCgcICwAAAA==.',Fi='Fignewt:BAAALAADCggIEgAAAA==.Filitov:BAAALAADCggIDAAAAA==.',Fo='Foxtrot:BAAALAADCgMIBAABLAADCgcICQABAAAAAA==.',Ga='Gamblex:BAAALAADCggIDwAAAA==.Gampy:BAAALAADCgYIBgABLAAECgMIBwABAAAAAA==.',Gh='Ghlaircan:BAAALAADCggIFQAAAA==.',Gi='Gimleia:BAAALAADCggIFwAAAA==.',Gl='Glanth:BAAALAAECggIDQAAAA==.',Go='Goontar:BAAALAADCgIIAgAAAA==.Gormundy:BAAALAADCgYIBgAAAA==.',Gr='Grumpygannon:BAAALAAECgUICQAAAA==.',Hi='Hideman:BAAALAAECgEIAQAAAA==.',Ho='Holyrocker:BAAALAADCgcIDAAAAA==.Honah:BAAALAAECgMIBQAAAA==.Honeybutter:BAAALAADCgcIBwABLAAECgMIAgABAAAAAA==.',['Hà']='Hàdéz:BAAALAAECgQIBgAAAA==.',Ih='Ihealzufool:BAAALAADCggIEgAAAA==.',Il='Illidannyboy:BAAALAADCgEIAgAAAA==.',Im='Im:BAAALAAECgcIEQAAAA==.Imded:BAAALAADCggIEAAAAA==.',In='Inglorious:BAAALAADCggIDgAAAA==.',Ir='Irohman:BAAALAADCgMIAwAAAA==.',Iz='Izanagi:BAAALAADCgcIBwAAAA==.Izzam:BAAALAADCgYIBgAAAA==.',Ja='Jaredsboy:BAAALAADCggICgAAAA==.Jarlych:BAAALAAECgIIAgAAAA==.Javieraa:BAAALAAECgYICQAAAA==.',Jo='Jocecilla:BAAALAADCgYIBgABLAAECgQIBgABAAAAAA==.',Ju='Jutsu:BAAALAAECgMIAwAAAA==.',Ka='Kaiv:BAABLAAECoEVAAQDAAgIMCJyAgBiAgADAAcIASRyAgBiAgAEAAMIKhooOQD1AAAFAAIIZxQHHACeAAAAAA==.Kaokorra:BAAALAADCggIDwAAAA==.',Kh='Khanen:BAAALAAECgMIBQABLAAFFAIIBAABAAAAAA==.Khymaera:BAAALAADCgcICwAAAA==.',Ki='Kielann:BAAALAAECgIIAgAAAA==.Kimmi:BAAALAADCgUICAAAAA==.Kiven:BAAALAADCgIIAgAAAA==.',Ko='Konnonn:BAAALAAFFAIIBAAAAA==.',Kw='Kw:BAAALAAECgIIAgAAAA==.',['Ká']='Káïv:BAAALAAECgYICAAAAA==.',La='Larolod:BAAALAADCgYICwAAAA==.Lasadin:BAAALAADCgMIAwAAAA==.',Le='Lebaidan:BAAALAADCggIEgAAAA==.Lechwe:BAAALAAECgYICQAAAA==.Leeon:BAAALAADCgIIAgAAAA==.',Li='Lindaren:BAAALAADCgIIAgAAAA==.',Lo='Loepesci:BAAALAAECgYICgAAAA==.Loepeshi:BAAALAAECgMIBAAAAA==.Lopus:BAAALAADCggIFwAAAA==.Lovepet:BAAALAAECgMIBwAAAA==.',Lu='Lubù:BAAALAADCgUIBQAAAA==.Lunal:BAAALAAECgYICgAAAA==.',Ly='Lyda:BAAALAAECgIIAgAAAA==.',['Lû']='Lûnitari:BAAALAADCggIFwAAAA==.',Ma='Madbaddie:BAAALAAECgMIBAAAAA==.Maite:BAAALAADCgEIAQAAAA==.Majör:BAAALAAECgYIDgAAAA==.Malibubarbie:BAAALAAECgIIAgAAAA==.Materesa:BAAALAAECgMIBQAAAA==.Maus:BAAALAAECgYICgAAAA==.',Mc='Mcdoom:BAAALAADCgcIBwAAAA==.',Me='Menapaws:BAABLAAECoEVAAMGAAgIhxpPBACAAgAGAAgIhxpPBACAAgAHAAEIuxS8EQA5AAAAAA==.Meriel:BAAALAAECgEIAQAAAA==.',Mi='Mictan:BAAALAADCgcICwAAAA==.Milk:BAAALAADCggIDgAAAA==.Miloo:BAAALAADCgMIAgAAAA==.Mizkilla:BAAALAADCgcICwAAAA==.',Mo='Monlee:BAAALAADCgMIAwAAAA==.Moonbayne:BAAALAAECgMIAwAAAA==.Mortalkombat:BAAALAADCgQIBAAAAA==.',My='Mythology:BAAALAAECgcIEQAAAA==.',['Mà']='Màc:BAAALAAECgIIAgAAAA==.',Na='Nazam:BAAALAADCgIIAgAAAA==.',Ne='Nepharim:BAAALAADCggICAAAAA==.Nephlim:BAABLAAECoETAAIIAAgIqSB4BQAaAwAIAAgIqSB4BQAaAwAAAA==.',Ni='Nightskÿ:BAAALAAECgUIBwAAAA==.',No='Noobsmaycry:BAAALAADCgMIAwAAAA==.',Oo='Oorlian:BAAALAADCggIDwAAAA==.',Op='Opheleia:BAAALAADCggICAAAAA==.',Ov='Overwhelming:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.',Pa='Pangaeaa:BAAALAADCggIAgAAAA==.Pawsitive:BAEALAADCggICAABLAAECggIFQAJAN0gAA==.',Ph='Phenitz:BAAALAAFFAIIAwAAAA==.',Po='Pookie:BAAALAAECgEIAQAAAA==.',Ps='Psiberian:BAAALAADCgcIDgAAAA==.Psychopuppy:BAAALAADCgMIAwAAAA==.',Ra='Rastapopulos:BAAALAADCggICwAAAA==.',Re='Reptilectric:BAAALAADCggIFwAAAA==.',Ri='Rikaku:BAAALAADCggIDwAAAA==.Rina:BAAALAADCgcICQAAAA==.Ririkari:BAAALAADCgEIAQAAAA==.',Ro='Romuleus:BAAALAADCgcICgAAAA==.Rosemery:BAAALAAECgEIAQAAAA==.',['Râ']='Râpôdâc:BAAALAAECgIIBAAAAA==.Râpödac:BAAALAAECgYICQAAAA==.',Sa='Sabriel:BAAALAADCgQIBAABLAADCgYIBgABAAAAAA==.Sagaba:BAAALAADCgcIBwAAAA==.Sairo:BAAALAADCgcICwAAAA==.Sapheroh:BAAALAADCggIDwAAAA==.Sause:BAAALAADCgcIDwAAAA==.',Sc='Schizo:BAAALAAECgQIAwAAAA==.',Se='Searena:BAAALAADCggIFwAAAA==.Semdorii:BAAALAAECgMIBQAAAA==.Sephywrath:BAAALAAECgUIBwAAAA==.Serahal:BAAALAADCgQIBAAAAA==.Seranight:BAAALAAECgUICAAAAA==.Sevenpaws:BAAALAAECgEIAQABLAAECgYICgABAAAAAA==.',Sh='Shadöw:BAAALAADCgUIBQAAAA==.Shaidon:BAAALAADCgYIBgAAAQ==.Shirohige:BAAALAADCggIDwAAAA==.Shockakhan:BAAALAADCgIIAgAAAA==.Shådowed:BAAALAADCgcIEgAAAA==.',Si='Sidelich:BAAALAAECgIIAgAAAA==.Silvanoshi:BAAALAADCgcIEgAAAA==.',So='Soularis:BAAALAAECgIIAgAAAA==.',Sp='Spaxtic:BAAALAADCgYIBgAAAA==.Spybro:BAAALAADCggICwAAAA==.',St='Stormcrows:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Stormtalon:BAAALAADCgMIAwAAAA==.',Su='Sudri:BAAALAADCgMIAwAAAA==.Supersport:BAAALAADCggIFwAAAA==.',Sy='Synistir:BAAALAADCgMIBQAAAA==.Syrø:BAAALAADCgMIBAAAAA==.',Ta='Tahr:BAAALAADCggIDgAAAA==.Talebras:BAAALAADCgcICgAAAA==.Tamatoa:BAAALAADCgYIBgAAAA==.Tanith:BAAALAADCgYIBgABLAADCggIFwABAAAAAA==.Tansora:BAAALAADCggICwAAAA==.',Te='Tempést:BAAALAADCgYIBgAAAA==.',Th='Thehound:BAAALAADCggICAAAAA==.Therea:BAAALAAECgIIAgAAAA==.Thetinman:BAAALAADCgcIDAABLAAECgMIBQABAAAAAA==.Thorash:BAAALAADCgMIAwAAAA==.',Ti='Tiarcis:BAAALAAECgUICAAAAA==.Tigg:BAAALAAECgIIAgAAAA==.Tiri:BAAALAADCggICAAAAA==.Tivadar:BAAALAADCgcICAAAAA==.',Tr='Tradden:BAAALAADCgIIAgAAAA==.Treesummoner:BAAALAAECgUIBwAAAA==.Troolyes:BAAALAADCgYIDAAAAA==.',Ub='Ubext:BAAALAAECgMIAwAAAA==.',Va='Vali:BAAALAADCgcIBwAAAA==.Valiente:BAAALAADCggIFAAAAA==.Vallo:BAAALAADCggICwAAAA==.Vasilia:BAAALAAECgIIAgAAAA==.',Ve='Veliat:BAAALAAECgYICQAAAA==.Velliria:BAAALAADCgYIBgAAAA==.Vestri:BAAALAADCgMIAwAAAA==.',Vi='Viradi:BAAALAADCggIDwAAAA==.',Vo='Voiddonnix:BAAALAADCgcIBwAAAA==.',Wa='Warfrog:BAAALAAECgMIBgAAAA==.',We='Wetpaperbag:BAAALAADCgYIBgABLAAECgMIAgABAAAAAA==.',Wo='Wotwind:BAAALAAECgcIDAAAAA==.',Wu='Wuwindtang:BAAALAAECgMIAwAAAA==.',Xe='Xeniuz:BAAALAADCgQIBAAAAA==.',Yt='Ythiria:BAAALAADCgMIAwAAAA==.',Za='Zanthe:BAAALAADCggIDwAAAA==.Zapanese:BAAALAAECgMIBAAAAA==.Zappletree:BAAALAADCgUIBQAAAA==.Zaptism:BAAALAADCgYIBgAAAA==.',Zi='Zipit:BAAALAAECgcIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end