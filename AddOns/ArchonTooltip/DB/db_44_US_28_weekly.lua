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
 local lookup = {'Hunter-BeastMastery','Monk-Brewmaster','Priest-Holy','Unknown-Unknown','Monk-Windwalker','Hunter-Marksmanship',}; local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acidrain:BAAALAAECgMIBQAAAA==.',Ad='Adar:BAAALAAECgEIAQAAAA==.',Ah='Ahrmanhamma:BAAALAAECgYIEwAAAA==.Ahu:BAABLAAECoEYAAIBAAgIjxbIEwBEAgABAAgIjxbIEwBEAgAAAA==.',Ak='Akatala:BAAALAADCgcIDQAAAA==.',Am='Amagidyne:BAAALAADCgUIBQABLAAECggIFwACAEUmAA==.Amaging:BAAALAAECgcICwAAAA==.Amoondai:BAABLAAECoEXAAIDAAgI0wqzHwCoAQADAAgI0wqzHwCoAQAAAA==.',An='Animäs:BAAALAAECgMIBAAAAA==.',Ap='Apolyon:BAAALAAECgcIDwAAAA==.',Ar='Arisblood:BAAALAADCgIIAgAAAA==.',Az='Azuree:BAAALAAECgcICwAAAA==.',Ba='Bacstabath:BAAALAAECgcIEAAAAA==.Banden:BAAALAADCgEIAQAAAA==.Banshee:BAAALAAECgMIAwAAAA==.',Be='Bear:BAAALAAECgEIAQAAAA==.Benislul:BAAALAADCgUIBgABLAAECgYICgAEAAAAAA==.',Bi='Billysunday:BAAALAAECgcIDQAAAA==.',Bl='Bloodios:BAAALAAECgcICwAAAA==.Blínd:BAAALAADCgYIBgAAAA==.',Bo='Bobarett:BAAALAADCggICAAAAA==.Bobinblood:BAAALAAECgEIAQAAAA==.Bocrusher:BAAALAADCgQIBAAAAA==.Bombadil:BAAALAAECgMIBQAAAA==.',Br='Bribage:BAAALAAECgcICwAAAA==.Brighter:BAAALAAECgIIAwAAAA==.Bringit:BAAALAADCggICQAAAA==.Brisote:BAAALAAECgQIBAAAAA==.Brolaf:BAAALAAECgYIBgAAAA==.Bruu:BAAALAAECgMIAwAAAA==.',Bu='Bunkir:BAAALAAECgcICwAAAA==.',['Bâ']='Bâvmôrrda:BAAALAAECgEIAQAAAA==.',Ca='Carada:BAAALAADCgcIBwAAAA==.',Cd='Cduh:BAAALAADCgEIAQAAAA==.',Ce='Cerric:BAAALAADCggIDAAAAA==.',Ch='Chickenwìngs:BAAALAADCggICAAAAA==.Chikñ:BAAALAAECgMIBAAAAA==.Chilis:BAAALAADCgEIAQAAAA==.',Ci='Cindresh:BAAALAAECgEIAQAAAA==.',Co='Cocoredbull:BAAALAADCggICAAAAA==.Correin:BAAALAAECgYICQAAAA==.Corruption:BAAALAAECggIAwAAAA==.',Cr='Craszhin:BAAALAAECgMIBQAAAA==.',Cu='Cuddled:BAAALAAECgEIAQAAAA==.Cuilbronadui:BAAALAADCggICwAAAA==.',Da='Darkdelight:BAAALAAECgcIDgAAAA==.',De='Deets:BAAALAAECgMIBQAAAA==.Demona:BAAALAAECgMIBQAAAA==.Derfurry:BAAALAAECgEIAQAAAA==.Descalabrada:BAAALAADCgYIBgAAAA==.',Dr='Drpep:BAAALAAECgYIBgAAAA==.Drpeppers:BAAALAAECgMIBQAAAA==.',['Dé']='Déathsavage:BAAALAAECgMIAwAAAA==.',Ec='Eclair:BAAALAAECgMIBQAAAA==.',Ei='Eilistraee:BAAALAADCggICAAAAA==.',El='Elchonk:BAAALAAECgMIAwAAAA==.Elhayn:BAAALAAECgMIBQAAAA==.Elmore:BAAALAAECgcIDgAAAA==.',Es='Escalla:BAAALAADCgMIAwAAAA==.',Ev='Evilmonkeydr:BAAALAAECgUIBgAAAA==.Evilmonkeymg:BAAALAADCgcIBwABLAAECgUIBgAEAAAAAA==.',Fa='Fanereaver:BAAALAADCgUIBQAAAA==.Fasana:BAAALAADCggIDwAAAA==.',Fe='Felreaper:BAAALAAECgIIAgAAAA==.Fennec:BAAALAADCgcIBwAAAA==.Fenrisulfr:BAAALAADCgYIBgAAAA==.',Fh='Fherrys:BAAALAAECgEIAQAAAA==.',Fi='Firefox:BAAALAAECgMIBQAAAA==.',Fl='Flooreagha:BAAALAAECgcIDAAAAA==.Flypig:BAAALAAECgIIAgAAAA==.',Fr='Frostymonk:BAAALAAECgEIAQAAAA==.Frostyred:BAAALAAECgQIBwAAAA==.',Ga='Gallaxie:BAAALAADCgYIBgABLAAECgYICQAEAAAAAA==.Gawyn:BAAALAAECgMIBQAAAA==.',Gh='Ghostryterz:BAAALAADCgcIDgAAAA==.',Gi='Gigaswole:BAAALAADCgYIBgAAAA==.Gigem:BAAALAADCggICQAAAA==.',Go='Goldarrow:BAAALAAECgMIBQAAAA==.Goldenhour:BAAALAAECgIIAgAAAA==.',Gr='Gradrina:BAAALAAECggICAAAAA==.Gredan:BAAALAAECgEIAQAAAA==.Grob:BAAALAAECgIIAgAAAA==.',Ha='Hasbullascat:BAAALAADCgcIBwABLAAECgYICgAEAAAAAA==.Hayzel:BAAALAAECgEIAQAAAA==.',He='Hellen:BAAALAAECgEIAQAAAA==.',Ho='Holy:BAAALAAECgMIAwAAAA==.Holymolii:BAAALAADCgcIBwAAAA==.Horrlock:BAAALAADCgIIAgAAAA==.Hotcoffee:BAAALAAECgQIBwAAAA==.',Ih='Ihatehealers:BAAALAADCggIHAAAAA==.',In='Inali:BAAALAADCgcIBwAAAA==.Incredabull:BAAALAADCggIFgAAAA==.',Is='Istayblunted:BAAALAAECgIIBAAAAA==.',Iu='Iuuki:BAAALAAECgIIAwAAAA==.',Ja='Jacqualyn:BAAALAADCggIBwAAAA==.Jal:BAABLAAECoEYAAIFAAgIgBwvBgCFAgAFAAgIgBwvBgCFAgAAAA==.Jaraxxus:BAAALAAECggIAQAAAA==.',Ji='Jiayerah:BAAALAADCggIDQABLAAECgEIAQAEAAAAAA==.Jinkuzo:BAAALAAECgMIBQAAAA==.Jinmu:BAAALAAECgMIBAAAAA==.',Jo='Joandarc:BAAALAADCgYIBgAAAA==.Joogie:BAAALAAECgMIAwAAAA==.',Ju='Juggie:BAAALAAECgQIBQAAAA==.Julienned:BAAALAAECgcICwAAAA==.',['Jø']='Jønes:BAAALAADCgcIDQAAAA==.',Ka='Kagluus:BAAALAAECgYICgAAAA==.',Ke='Keroppi:BAAALAAECgIIAgAAAA==.',Ki='Kilyan:BAAALAAECgYICwAAAA==.Kilyanev:BAAALAADCgcIDQAAAA==.',Kv='Kvothe:BAAALAAECgcICgAAAA==.',La='Lamont:BAAALAADCgUIBQAAAA==.',Le='Leanahtan:BAAALAAECgIIAgAAAA==.Leothandraa:BAAALAAECgMIAwAAAA==.',Li='Liese:BAAALAADCgIIAgAAAA==.',Lo='Loka:BAAALAAECgIIAgAAAA==.Lokiewoo:BAAALAADCgcIBwAAAA==.',Lu='Lumiyer:BAAALAADCgcIDQAAAA==.',Ly='Lygor:BAAALAAECgMIBQAAAA==.Lykana:BAAALAADCgYIDAAAAA==.',Ma='Majellan:BAAALAAECgQICAAAAA==.Marrius:BAAALAADCgQIBAAAAA==.Marsawn:BAAALAAECgQIBwAAAA==.',Mc='Mcpeepants:BAAALAAECgMIBQABLAAECgYIEwAEAAAAAA==.',Me='Memebeam:BAAALAAECgQIBAAAAA==.',Mi='Miko:BAAALAADCggICwAAAA==.Mikàsa:BAAALAAECgIIAwAAAA==.Mindlessness:BAAALAAECgcICwAAAA==.Mineralelf:BAAALAAECgcICgAAAA==.Mittensqt:BAAALAAECgIIAgABLAAECgYIBgAEAAAAAA==.',Mo='Mortshan:BAAALAAECgIIAgAAAA==.',Mu='Mugsimus:BAAALAAECgcIDgAAAA==.',My='Mylas:BAAALAADCgYICwAAAA==.Mysticalfox:BAAALAADCgYIBgAAAA==.',Ni='Nihlus:BAAALAADCgUIBQAAAA==.',No='Notos:BAAALAADCgYIBQAAAA==.',Nu='Nurzul:BAAALAADCgUIBQAAAA==.',Ny='Nyrvana:BAAALAAECgMIBQAAAA==.',Or='Orceo:BAAALAAECgMIBgAAAA==.Oreosbunny:BAAALAADCgcIBgAAAA==.',Pi='Pindapinda:BAAALAAECgcIDwAAAA==.Pizzaboy:BAAALAADCgYIBgABLAAECgYIEwAEAAAAAA==.',Po='Pompompower:BAAALAAECgUIBwAAAA==.Potential:BAAALAADCgcIBwAAAA==.',Pr='Praebae:BAAALAAECgMIAwAAAA==.',Pu='Pubstar:BAAALAADCgIIAgAAAA==.Purpul:BAAALAAECgEIAQAAAA==.',Qa='Qaccy:BAAALAAECgMIBgAAAA==.',Qu='Quietmind:BAAALAAECgQICgAAAA==.',['Qê']='Qêxê:BAAALAAECgQIBwAAAA==.',Ra='Rando:BAAALAADCggICAAAAA==.Randomfergus:BAAALAAECgMIBQAAAA==.',Re='Rebelle:BAAALAADCgIIAgAAAA==.Redone:BAAALAAECgcICgAAAA==.Reishirome:BAAALAAECgMIAwAAAA==.Rektum:BAAALAADCgEIAQAAAA==.Rezwho:BAAALAAECgEIAQAAAA==.',Rh='Rhavaniel:BAABLAAECoEYAAIGAAgICyRbAgAqAwAGAAgICyRbAgAqAwAAAA==.',Ro='Rona:BAAALAADCgUIBQAAAA==.',Ru='Rumincoke:BAAALAADCggICAAAAA==.',Sa='Sansa:BAAALAAECgEIAQAAAA==.Savrille:BAAALAAECgMIBwAAAA==.',Se='Serutan:BAAALAAECgMIBQAAAA==.',Sh='Shadowo:BAAALAADCgIIAgAAAA==.Shamannexus:BAAALAAECgQIBwAAAA==.Shammyin:BAAALAADCggICAAAAA==.',Sm='Smogcheck:BAAALAAECgMIBAAAAA==.',Sn='Snackcake:BAAALAAECgIIAwAAAA==.Snowws:BAAALAAECgcICQAAAA==.',So='Sortis:BAAALAAECgcIDgAAAA==.',St='Steck:BAAALAAECgEIAQAAAA==.Strigo:BAAALAAECgcIEAAAAA==.Strigoii:BAAALAADCgIIAgABLAAECgcIEAAEAAAAAA==.Strigöi:BAAALAAECgEIAQABLAAECgcIEAAEAAAAAA==.',Su='Sumswho:BAAALAADCgYICAAAAA==.',Ta='Talas:BAAALAAECgcIDgAAAA==.Tallia:BAAALAADCgUIBQAAAA==.',Th='Thaelink:BAAALAAECgIIAgAAAA==.',Ti='Tirium:BAAALAADCgcIBwAAAA==.',Tr='Treantreznor:BAAALAADCgMIAwAAAA==.Trillbrill:BAAALAAECgQIBgAAAA==.Trinitum:BAAALAADCggICQAAAA==.',Un='Unduril:BAAALAAECgQIBAAAAA==.',Ur='Ursae:BAAALAAECgMIBAAAAA==.',Va='Vaadboolin:BAAALAAECgYICgAAAA==.Vaadmar:BAAALAADCgcICAABLAAECgYICgAEAAAAAA==.',Vo='Voidjuices:BAAALAAECgYICgAAAA==.',Vy='Vyxenn:BAAALAAECgcICwAAAA==.',Wa='Wanders:BAAALAAECgcICgAAAA==.',Wi='Wiggley:BAAALAAECgMIAwAAAA==.',Xe='Xeròmercy:BAAALAADCgcIBwAAAA==.',Za='Zacattack:BAAALAADCgcIBwAAAA==.Zage:BAAALAAECgYIDQAAAA==.Zazreal:BAAALAAECgMIBQAAAA==.',Zi='Zick:BAEALAAECgIIAwABLAAECgcIDQAEAAAAAA==.Zillyanna:BAAALAADCgMIAwAAAA==.',Zy='Zywol:BAAALAAECgcICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end