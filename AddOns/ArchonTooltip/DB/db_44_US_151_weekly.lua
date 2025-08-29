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
 local lookup = {'Unknown-Unknown','Warrior-Protection','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Druid-Feral','Priest-Holy','Priest-Shadow','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Devastation','Evoker-Augmentation','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction',}; local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaluah:BAAALAADCgEIAQAAAA==.',Ac='Acmis:BAAALAAECgMIBAAAAA==.',Ae='Aelous:BAAALAADCgQIBQAAAA==.',Ai='Airazor:BAAALAADCgMIAwAAAA==.Airrose:BAAALAAECgYIDAAAAA==.',Ak='Aku:BAAALAAECgMIAwAAAA==.',Al='Alarred:BAAALAADCgUICAAAAA==.Aldrauna:BAAALAADCgYIBAAAAA==.Alexan:BAAALAADCgIIAgAAAA==.Allise:BAAALAAECgIIAgAAAA==.Alucardus:BAAALAADCgcIBwAAAA==.Aléthia:BAAALAAECgEIAQAAAA==.',An='Anathemá:BAAALAADCgMIAwAAAA==.',Ap='Apawagos:BAAALAAECgQICQAAAA==.',Ar='Ardeyn:BAAALAADCggICAAAAA==.Arelyssa:BAAALAADCgEIAQAAAA==.Arianndda:BAAALAADCggICAAAAA==.Arin:BAAALAAECgQIBgAAAA==.Armageddon:BAAALAADCgMIAwAAAA==.Arraeroda:BAAALAADCggIDAAAAA==.Arrence:BAAALAAECgYIDgAAAA==.',As='Askor:BAAALAAECgMIAwAAAA==.Asperan:BAAALAADCgYIBgAAAA==.Astela:BAAALAAECgMIBAAAAA==.',Au='Autolock:BAAALAAECgYIDQAAAA==.',Av='Avatan:BAAALAAECgMIBwAAAA==.Ave:BAAALAAECgEIAQAAAA==.Avecrusade:BAAALAAECgMIBQAAAA==.Averlis:BAAALAAECgYIDgAAAA==.Averliss:BAAALAADCggIDgAAAA==.',Az='Azkaleth:BAAALAADCggIDAAAAA==.',Ba='Backpack:BAAALAADCgYIBgAAAA==.Badderdragon:BAAALAAFFAIIAgAAAA==.Badfish:BAAALAADCggICAAAAA==.Badmrmittens:BAAALAAECgMIBAAAAA==.Badmuffin:BAAALAAECgMIBAAAAA==.Balamuth:BAAALAAECgEIAQAAAA==.Bandrui:BAAALAADCgcIBwAAAA==.Baragahor:BAAALAADCgMIAwAAAA==.Bareyee:BAAALAAECgMIBQAAAA==.Baxtur:BAAALAAECgUIBgAAAA==.',Be='Bearlygrillz:BAAALAAECgIIAgAAAA==.Bearontoe:BAAALAADCgEIAQAAAA==.Beepbeep:BAAALAAECgYIDgAAAA==.Begachan:BAAALAADCgcICgAAAA==.Berkstein:BAAALAAECgMIAwAAAA==.Berrysnake:BAAALAADCggIEgAAAA==.',Bi='Biggimac:BAAALAAECgYIDAAAAA==.Bimbom:BAAALAAECgQIBAAAAA==.Biochemist:BAAALAAECgQIBQAAAA==.Bioengineer:BAAALAAECgIIBAABLAAECgQIBQABAAAAAA==.Biosphere:BAAALAADCgMIAwABLAAECgQIBQABAAAAAA==.Biotoxin:BAAALAAECgIIAwABLAAECgQIBQABAAAAAA==.',Bl='Blackdoom:BAAALAADCgMIBAAAAA==.Blitzbeast:BAAALAADCgQIBAAAAA==.Bloodleak:BAAALAAECgEIAQAAAA==.Bloodrayen:BAAALAADCgIIAgAAAA==.Bluefish:BAAALAAECgIIAwAAAA==.',Bn='Bnuggiest:BAAALAADCgcIAgAAAA==.',Bo='Bootyhandler:BAAALAADCgQIBQAAAA==.Borucmonk:BAAALAAECgMIBQAAAA==.Borucwar:BAAALAADCggIDgABLAAECgMIBQABAAAAAA==.Bouletcannon:BAAALAAECgYIBgAAAA==.',Br='Brassticus:BAAALAAECgcIEAAAAA==.Breez:BAAALAADCgEIAQABLAAFFAIIAgABAAAAAA==.Broguecode:BAAALAADCgEIAQAAAA==.Broodiie:BAAALAADCggIEAAAAA==.Brucewee:BAAALAADCgQIBAAAAA==.',Bu='Buddhi:BAAALAAECgcIDgAAAA==.Burrhas:BAAALAAECgMIAwAAAA==.',Bw='Bwahablast:BAAALAAECgYIBgAAAA==.',By='Byorklock:BAAALAADCggICwAAAA==.',['Bø']='Bøøberry:BAAALAAECgIIAQAAAA==.',Ca='Calkestis:BAAALAADCgIIAgAAAA==.Cancermancer:BAAALAADCgUIBwAAAA==.Cardora:BAAALAADCggIFwAAAA==.Caròl:BAAALAAECgQIBQAAAA==.',Ch='Chay:BAAALAAECgcIDAAAAA==.Cheezecake:BAAALAAECgUICAAAAA==.Chennoa:BAAALAADCgMIAwAAAA==.Chivo:BAAALAAECgMIBAAAAA==.Chopu:BAAALAAECgEIAQAAAA==.Chubbers:BAAALAAECgIIAQAAAA==.Chyna:BAAALAADCggICAAAAA==.',Ci='Cibø:BAAALAADCgcICwAAAA==.Cirdae:BAAALAAECgYIDgAAAA==.',Cl='Clarsh:BAAALAAFFAIIAgAAAA==.Clayzerk:BAAALAAECgUIBwAAAA==.Cleric:BAAALAAECgYIDAABLAAECgEIAQABAAAAAA==.',Co='Colrobinson:BAAALAADCgMIAwAAAA==.Contagious:BAAALAADCgIIAgAAAA==.Corber:BAAALAAECgMIBgAAAA==.',Cp='Cptsaveahoe:BAAALAAECgUIBgAAAA==.',Cr='Crazynip:BAAALAAECgUICAAAAA==.Crickit:BAAALAAECgEIAQABLAADCgYIDwABAAAAAA==.Crickét:BAAALAADCgcICAABLAADCgYIDwABAAAAAA==.Crickêt:BAAALAADCgYIDAABLAADCgYIDwABAAAAAA==.Crickët:BAAALAADCggIFAABLAADCgYIDwABAAAAAA==.Crikit:BAAALAADCgYIDwAAAA==.Crikkit:BAAALAADCgcICAABLAADCgYIDwABAAAAAA==.Crrioth:BAAALAAECgQIBwAAAA==.',Ct='Ctrlshftheal:BAAALAADCgMIAwAAAA==.',Cu='Cuddlehugs:BAAALAAECgcIEgAAAA==.Cujo:BAAALAADCgcIEAAAAA==.Curiousgeorg:BAAALAADCggICAAAAA==.',Cy='Cybre:BAAALAAECgIIAgAAAA==.Cyndil:BAAALAADCgcIBwAAAA==.Cysbrew:BAAALAADCgUIBQABLAAECgMIBgABAAAAAA==.Cysero:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.Cysien:BAAALAAECgMIBgAAAA==.Cysraka:BAAALAADCgcICgABLAAECgMIBgABAAAAAA==.',['Cä']='Cästiel:BAAALAAECgMIBAAAAA==.',Da='Dadpriest:BAAALAADCgcIBwAAAA==.Dakkaglyndur:BAAALAADCgcIEwAAAA==.Daleus:BAAALAAECgYIDAAAAA==.Darathon:BAABLAAECoEaAAICAAgI5RCbDQC8AQACAAgI5RCbDQC8AQAAAA==.Darcane:BAAALAAFFAIIAgAAAA==.Darctanian:BAAALAAECgEIAQAAAA==.Dareth:BAAALAAECgMIAwAAAA==.Darkvayne:BAAALAAECggIAQAAAA==.Dashh:BAAALAADCggICAAAAA==.Dayanita:BAAALAADCggIDwAAAA==.Dayenu:BAAALAADCgcIBwAAAA==.',De='Deathpig:BAAALAAECgMIBgAAAA==.Deceiver:BAAALAAECgQICQAAAA==.Deleitlama:BAAALAADCggIEgAAAA==.Delisius:BAAALAADCggIDwAAAA==.Demonnova:BAACLAAFFIEFAAIDAAMI4A4RBAD9AAADAAMI4A4RBAD9AAAsAAQKgRcAAgMACAhGHlwPAJkCAAMACAhGHlwPAJkCAAAA.Demonrayen:BAAALAADCgQIBAAAAA==.Denleader:BAAALAADCggICAAAAA==.Dessertname:BAAALAAECgMIAwAAAA==.Devinity:BAAALAADCgYICgAAAA==.Dezsp:BAAALAAECgcIEgAAAA==.',Dg='Dghunter:BAAALAAECgYIDAAAAA==.',Di='Diarana:BAAALAAECgEIAQAAAA==.Dino:BAAALAAECgIIAgAAAA==.Dinotime:BAAALAADCgMIAwAAAA==.Dippÿ:BAAALAADCggIFQAAAA==.',Dn='Dnite:BAAALAADCgYIBgAAAA==.',Do='Dokholliday:BAAALAADCgcIBwAAAA==.Dorrinael:BAAALAADCgEIAQAAAA==.',Dr='Dragn:BAAALAAECgMIBAAAAA==.Dragnas:BAAALAAECgcIEAAAAA==.Dragniperake:BAAALAADCggIDgAAAA==.Draykose:BAAALAAECgYICQAAAA==.Dreadnaunt:BAAALAAECgEIAQAAAA==.Drewed:BAAALAAECgcIEAAAAA==.Drugral:BAAALAAFFAIIAgAAAA==.Druileti:BAACLAAFFIEFAAIEAAMIAyMAAQA4AQAEAAMIAyMAAQA4AQAsAAQKgRgABAQACAjXHyEMADkCAAQABwj2HiEMADkCAAUAAghXG8g2AKAAAAYAAgiIDeMXAHsAAAAA.Dryad:BAAALAAECgYIDAAAAA==.Drzoidberg:BAAALAAECgYIEAAAAA==.Drúzy:BAAALAADCgEIAQABLAAECgcIEAABAAAAAA==.',Du='Dugronn:BAAALAAECgYICQAAAA==.',Dw='Dwarfvadar:BAAALAAECgMIBAAAAA==.',['Dê']='Dênnisp:BAAALAAECgEIAQAAAA==.',El='Elanthemage:BAAALAAECgMIAwAAAA==.Eleison:BAACLAAFFIEFAAIHAAMIUyX6AABQAQAHAAMIUyX6AABQAQAsAAQKgR4AAwgACAgSJdQBAFcDAAgACAgSJdQBAFcDAAcACAhxIOwGAL4CAAAA.Elldren:BAAALAAECgMIBQAAAA==.Ellesperis:BAAALAAECgMIBQAAAA==.Ellumon:BAAALAAECgYIDAAAAA==.Elspat:BAAALAADCgcIBwAAAA==.',Em='Emergnc:BAAALAADCgUIBQAAAA==.',Ep='Epyon:BAAALAADCggIFQAAAA==.',Er='Eragôn:BAAALAAECgYICQAAAA==.Erinyes:BAAALAAECgYIDgAAAA==.Ersatzcheese:BAAALAAECgIIAwABLAAECgYIDAABAAAAAA==.',Es='Estee:BAAALAAECgMIBAAAAA==.',Ev='Evoquer:BAAALAADCgUIBQABLAAECgYIDwABAAAAAA==.',Ex='Executioner:BAAALAAECgYICwAAAA==.',Fa='Fatfish:BAAALAADCggICAAAAA==.Fatty:BAAALAAECgYIDgAAAA==.',Fe='Felkuro:BAAALAAECgMIAwAAAA==.Feul:BAAALAAECgcIDgAAAA==.',Fi='Fiasko:BAAALAAECgYIDAAAAA==.Finarfin:BAAALAADCgYICAAAAA==.',Fl='Flippÿ:BAAALAAECgYIDAAAAA==.Flotila:BAAALAAECggIAQAAAA==.Fluffythecup:BAAALAAECgMIBAAAAA==.',Fo='Formidonis:BAAALAAECgYIDAAAAA==.Foxfirestrot:BAAALAAECgEIAQAAAA==.',Fr='Fraudcheese:BAAALAAECgYIDAAAAA==.Freyjaa:BAAALAADCggIEAAAAA==.Frostfyre:BAAALAAECgEIAQAAAA==.',Fu='Fulgur:BAAALAADCgcIBwAAAA==.Funshine:BAAALAAECgUIBQAAAA==.',Ga='Galhar:BAAALAADCgEIAQAAAA==.Garygabagool:BAAALAAFFAIIAgAAAA==.Gawdspet:BAAALAAECgIIAgAAAA==.',Ge='Gengarr:BAAALAADCggIEwAAAA==.',Gh='Ghostraptor:BAAALAAECgYICgAAAA==.',Gi='Gizammo:BAAALAADCgIIAQAAAA==.',Gl='Glaivegetter:BAAALAADCgcICwAAAA==.Glendor:BAAALAADCgQIBAAAAA==.Glizzymcquir:BAAALAAECgEIAQAAAA==.Gloomycyan:BAAALAAECgEIAQAAAA==.Glupshiddo:BAAALAADCggICAABLAAECggIFgADABwhAA==.Glyn:BAAALAAECgMIBAAAAA==.',Gn='Gnawrly:BAAALAAECgMIBQAAAA==.',Go='Gogurt:BAAALAADCgYIBgAAAA==.Gonturan:BAAALAAECgMIAwAAAA==.Govblast:BAAALAADCggICAAAAA==.',Gr='Gratsby:BAAALAAECgMIBgAAAA==.Greenstone:BAAALAADCgYIDQAAAA==.Grish:BAAALAADCgEIAQAAAA==.Grïm:BAAALAAECgQICQAAAA==.',Gu='Guldont:BAAALAADCggICAAAAA==.Gummiebearz:BAAALAAECgEIAQAAAA==.',Ha='Hankering:BAAALAAECgYIDAAAAA==.Haptics:BAAALAAECgcIDwAAAA==.Haruot:BAAALAADCggICAAAAA==.',He='Hecateis:BAAALAAECgEIAQAAAA==.Heenan:BAAALAADCggIDwAAAA==.Hexkey:BAAALAAECgIIAgAAAA==.',Hi='Higanbana:BAAALAADCggIEAAAAA==.Hintze:BAAALAADCggICAAAAA==.',Ho='Holyhandgrnd:BAAALAADCggIDgAAAA==.Holyslanger:BAAALAADCgYIBgAAAA==.Holywaddles:BAAALAAECgMIBAAAAA==.Honeygirl:BAAALAADCgQIBAAAAA==.Horfin:BAAALAAECgMIAwAAAA==.Hotfix:BAAALAADCgYIBgAAAA==.Hothnar:BAAALAADCggIEAAAAA==.',Ht='Htownshawdo:BAAALAAECgEIAQAAAA==.',Hu='Huevocutter:BAAALAADCgUIBQAAAA==.',['Hä']='Hänkofer:BAAALAAECgEIAQABLAAECgYIDAABAAAAAA==.',Ia='Iamhim:BAAALAADCgYIBgAAAA==.',Ih='Ihatepriests:BAAALAADCgUIBQAAAA==.',Ik='Ikarí:BAAALAAECgYIBgAAAA==.',Il='Ills:BAAALAADCggICAAAAA==.',In='Inara:BAAALAADCgcIBwAAAA==.Inuyasha:BAAALAAECgIIAgAAAA==.Invincible:BAAALAAECgIIAgAAAA==.',Io='Ioraa:BAAALAAECgMIBAAAAA==.',Ir='Irishhammer:BAAALAAECgMIAwAAAA==.',Is='Ispreadstds:BAAALAADCgIIAgAAAA==.',It='Itchynips:BAAALAAECgEIAQAAAA==.',['Iá']='Ián:BAAALAAECgYIDAAAAA==.',Ja='Jakkimothy:BAAALAAECgIIBAABLAAECgMIAwABAAAAAA==.Janq:BAAALAAECgYIDAAAAA==.',Je='Jellyfish:BAAALAAECgEIAQAAAA==.Jeniko:BAAALAADCggIDwAAAA==.Jerrodsmage:BAAALAADCgEIAQAAAA==.',Ji='Jit:BAAALAAECgEIAQAAAA==.',Jm='Jmc:BAAALAAECgMIBgAAAA==.',Jp='Jpglaive:BAAALAADCgcIBwAAAA==.Jpmagi:BAAALAADCgYICQABLAADCgcIBwABAAAAAA==.',Ju='Juggernaunt:BAAALAAECgEIAQAAAA==.Jullene:BAAALAADCggIDAAAAA==.Justania:BAAALAAECgcIEAAAAA==.',['Já']='Jáque:BAAALAAECgMIBAAAAA==.',Ka='Kaeloth:BAAALAAECgYICwAAAA==.Kagayoshi:BAAALAAECgIIAwAAAA==.Kaiman:BAAALAADCggICAAAAA==.Kainen:BAAALAADCgEIAQAAAA==.Kalebpal:BAAALAAECgYICwAAAA==.Kaotic:BAAALAAECgYIDgAAAA==.Kaoticc:BAAALAADCgYIBgAAAA==.Kaotics:BAAALAAECgMIAwAAAA==.Kardia:BAAALAAECgIIAwAAAA==.Kayaane:BAAALAADCggICAAAAA==.Kayaanu:BAAALAAECgYICwAAAA==.',Ke='Kellholy:BAAALAAFFAIIAgAAAA==.Kelork:BAAALAADCgcIEAAAAA==.',Kh='Khadrodox:BAAALAAECgEIAQAAAA==.Khazryl:BAAALAAECgMIBQAAAA==.',Ki='Kirke:BAAALAAECgIIAgAAAA==.Kirriana:BAAALAADCgcIBwAAAA==.',Kl='Kletas:BAAALAADCgUIBQAAAA==.',Kn='Knottyflow:BAAALAADCgMIAwAAAA==.Knull:BAAALAAECgMIAwAAAA==.',Ko='Kojee:BAAALAAECgIIAgAAAA==.Korvash:BAAALAAECgIIAgAAAA==.Kowerd:BAAALAAECgYIDAAAAA==.',Kr='Krapon:BAAALAAECgYICQAAAA==.Kromgol:BAABLAAECoEWAAMJAAgI5xiZEQA2AgAJAAcI0xuZEQA2AgAKAAEIUAtCeAAyAAAAAA==.Krupp:BAAALAADCggIEAAAAA==.',Ku='Kushov:BAAALAADCgMIAwAAAA==.',Kw='Kwende:BAAALAAECgYICQAAAA==.',Ky='Kyela:BAAALAAECgMIBAAAAA==.',['Kø']='Kørupted:BAAALAAECgMIBAAAAA==.',La='Lacrian:BAAALAAECgEIAgAAAA==.Lafertdaniel:BAAALAAECgYICwAAAA==.Lamiisa:BAAALAAECgIIAwAAAA==.Largepenance:BAAALAAECgYIDQAAAA==.Lará:BAAALAADCggIEAAAAA==.Laurala:BAAALAAECgEIAQAAAA==.Laved:BAAALAAECgMIBwAAAA==.',Lc='Lcee:BAAALAADCgcICwAAAA==.',Ld='Ldkills:BAAALAADCgcICQAAAA==.',Le='Leegandhi:BAAALAADCggICAAAAA==.Leshy:BAAALAADCgcIDQAAAA==.',Li='Lilya:BAAALAADCgEIAQAAAA==.Lisoo:BAAALAADCgUIBQAAAA==.Litedragon:BAAALAAECgEIAQAAAA==.Lixialitixa:BAAALAAECgEIAQAAAA==.',Lo='Lockedûp:BAAALAADCgEIAQAAAA==.Locktorious:BAAALAADCgYIBwABLAAECgMIBgABAAAAAA==.Loji:BAAALAAECgcIEAAAAA==.Lolha:BAAALAADCgUIBQABLAAECgUICAABAAAAAA==.Lonemage:BAAALAADCggICAAAAA==.',Lu='Lucidonis:BAAALAAECgYICQAAAA==.',Ly='Lystia:BAAALAAECgIIBAAAAA==.',Ma='Madriel:BAAALAAECgMIBAAAAA==.Magento:BAAALAAECgYIDAAAAA==.Maladie:BAAALAAECgQIBQAAAA==.Malira:BAAALAADCggICAAAAA==.Manmonk:BAAALAAECgQIBQAAAA==.Mastaquick:BAAALAADCggICAAAAA==.Mayge:BAAALAADCgQIBAABLAAECgYIDwABAAAAAA==.',Mc='Mcfknkfc:BAAALAAECgcIEAAAAA==.',Me='Meatydk:BAAALAADCgcIBwAAAA==.Mechabling:BAAALAADCgMIAwAAAA==.Medari:BAAALAADCgEIAQABLAAECgMIBAABAAAAAA==.Meds:BAAALAADCgcICAAAAA==.Meeyo:BAAALAAECgcIEAAAAA==.Mehrunedagon:BAAALAADCgUIBQAAAA==.Mekaoppai:BAAALAAECgYICAAAAA==.Menrva:BAAALAAECgEIAQAAAA==.Meowmy:BAAALAADCgYIBwAAAA==.',Mi='Micti:BAAALAAECgYICgAAAA==.Micycle:BAAALAAECgEIAQAAAA==.Miltonberle:BAAALAADCgcIBwAAAA==.Miniion:BAAALAAECgEIAQAAAA==.Minirhon:BAAALAADCggIDwAAAA==.Minyon:BAAALAAECgYIDAAAAA==.Miso:BAAALAADCgUIBQAAAA==.Missodette:BAAALAAECgEIAQAAAA==.Mistajones:BAAALAAECgIIAQAAAA==.',Mo='Moneyshock:BAAALAAECgQIBwAAAA==.Monkybrewstr:BAAALAADCgIIAgAAAA==.Monsterpal:BAAALAAECgYICgAAAA==.Moosteak:BAAALAAECgQIBAAAAA==.Morke:BAAALAAECgMIBAAAAA==.Moser:BAAALAADCgUICQAAAA==.Mouseyy:BAAALAADCgEIAQAAAA==.',Mu='Mugron:BAAALAAECgQIBAAAAA==.Muhsheckles:BAAALAADCgcIBwAAAA==.',My='Mythrandia:BAAALAAECgYICwAAAA==.',['Mý']='Mýbad:BAAALAAECgIIAwAAAA==.',Na='Naki:BAAALAADCgYIBgAAAA==.Narìko:BAAALAADCgUIBQABLAADCggIEAABAAAAAA==.',Ne='Necroswrath:BAAALAAECgYICgAAAA==.Neebstrasza:BAAALAADCggIDAAAAA==.Nephthÿs:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.Nexeus:BAAALAADCgEIAQAAAA==.',Nh='Nhaeli:BAAALAADCgcIBwAAAA==.',Ni='Nicodkemus:BAAALAAECgYIDAAAAA==.Nightwrath:BAAALAADCgcIBwAAAA==.Nikfu:BAAALAAECgEIAQABLAAECgYIDAABAAAAAA==.Ningenn:BAAALAAECgYIDAAAAA==.Nixis:BAAALAAECgQIBQAAAA==.',No='Noctilus:BAAALAAECgYICQAAAA==.Norav:BAAALAAECgYICAAAAA==.Nordrydm:BAABLAAECoEVAAMLAAgIph3SAwC6AgALAAgIph3SAwC6AgAMAAQIaxKUGwD5AAAAAA==.Nordrydwl:BAAALAADCgYIBgABLAAECggIFQALAKYdAA==.Notoes:BAAALAADCggICAAAAA==.',['Ní']='Níghtmäre:BAAALAAECgEIAQAAAA==.',Oa='Oakstone:BAAALAAECgMIAwAAAA==.',Ol='Olscratch:BAAALAADCgcIBwAAAA==.',Op='Ophealiac:BAAALAAECgUICAAAAA==.',Os='Oshugun:BAAALAAECgUICAAAAA==.',Ov='Ovary:BAAALAADCggIFQAAAA==.',Ow='Owoker:BAAALAADCggICAAAAA==.',Pa='Pandybearz:BAAALAAECgMIBgAAAA==.',Pe='Pekkie:BAAALAAECgEIAQAAAA==.Penpineapple:BAAALAADCgEIAQAAAA==.Pestcontrol:BAAALAADCgIIAgAAAA==.Petcoo:BAAALAADCgEIAQAAAA==.',Pi='Pidi:BAAALAAECgYIDgAAAA==.Pioree:BAABLAAECoEUAAMNAAcIZiIGCwBjAgANAAcIOSAGCwBjAgAOAAYIyhjIAgDBAQAAAA==.Pixieberry:BAAALAAECgMIBgAAAA==.',Pl='PlayerPPXMXC:BAAALAAECgUIAQAAAA==.',Po='Polaroid:BAAALAADCgQIBAAAAA==.Pookiebear:BAAALAADCgUIBwAAAA==.',Pr='Prandal:BAAALAADCggIDgAAAA==.Program:BAAALAADCgcICQAAAA==.Projecthorde:BAAALAADCgcIBwAAAA==.',Pu='Purfoa:BAAALAADCggICAAAAA==.',Py='Pyrophobeac:BAABLAAECoEXAAMNAAgI/h4dBwC8AgANAAgI/h4dBwC8AgAOAAEIWAjmBwBBAAAAAA==.',Qu='Qu:BAAALAAECgIIAgAAAA==.Quizhik:BAAALAADCgQIAgAAAA==.',Ra='Ranulkath:BAAALAADCgMIAwAAAA==.Rayshia:BAAALAADCgcIBwAAAA==.',Re='Regnis:BAAALAADCgEIAQAAAA==.Regressive:BAAALAADCgcICAAAAA==.Reilyton:BAAALAAECgEIAQAAAA==.Resperea:BAAALAADCgIIAgAAAA==.Respwar:BAAALAADCggIDwAAAA==.Retharic:BAAALAADCgcIBwAAAA==.Rezzed:BAAALAADCgcICgAAAA==.',Ri='Ricassou:BAAALAAECgcIDgAAAA==.Rindor:BAAALAAECgEIAQAAAA==.Rivendell:BAAALAAECgEIAQAAAA==.',Ru='Rucy:BAAALAAECgYICwAAAA==.',['Ré']='Réfléx:BAAALAADCgcIBwAAAA==.Rélisha:BAAALAADCggIDQAAAA==.',['Rê']='Rêvelations:BAAALAADCggIDwAAAA==.',Sa='Saeyasan:BAAALAAECgMIBAAAAA==.Saitouhajime:BAAALAADCgcIBwAAAA==.Sakurai:BAAALAAECgMIBAAAAA==.Sammi:BAAALAADCggIEgAAAA==.Sarande:BAAALAAECgEIAQAAAA==.Sariline:BAAALAADCggICAAAAA==.Saristia:BAAALAADCggICwABLAAECgMIBAABAAAAAA==.',Sc='Scalathria:BAAALAADCgYIBgAAAA==.',Se='Seinn:BAAALAAECgYICQAAAA==.Selevis:BAAALAADCgcIDQAAAA==.Selindia:BAAALAAECgMIBAAAAA==.Selyra:BAAALAADCgcICgAAAA==.Seraphion:BAAALAADCgYIBgAAAA==.',Sh='Shadowcyde:BAAALAADCgcIBwAAAA==.Shaeya:BAAALAADCgUIBQAAAA==.Shallon:BAAALAAECgIIAwAAAA==.Shamcheese:BAAALAADCggIDgABLAAECgYIDAABAAAAAA==.Shamman:BAAALAAECgYIDwAAAA==.Shattered:BAAALAADCggIEAAAAA==.Sheeple:BAAALAADCgYIBgAAAA==.Shelina:BAAALAADCgEIAQAAAA==.Shen:BAAALAAECgYIBwAAAA==.Shermie:BAAALAADCgYIBgAAAA==.Shibito:BAAALAAECgcIEAAAAA==.Shift:BAAALAAECgcICgAAAA==.Shilihu:BAAALAAECgEIAQAAAA==.Shorzy:BAAALAAECgMIBQAAAA==.Shreddeez:BAAALAAECgYIDgAAAA==.',Si='Sidhedroia:BAAALAAECgMIBAAAAA==.Sienar:BAAALAAECgYICAAAAA==.Sigmasmite:BAAALAADCgYIBwAAAA==.Silentsword:BAAALAADCgYIBgAAAA==.Silvi:BAAALAADCgIIAgAAAA==.',Sk='Skeptá:BAAALAAECgcIEQAAAA==.',Sl='Sleepfrostvv:BAAALAAECgcIDAAAAA==.Slicee:BAAALAAECgIIAgAAAA==.Slimpikkinz:BAAALAADCgYIBgAAAA==.',Sn='Snizza:BAAALAADCgcICgAAAA==.Snugglebunne:BAAALAADCgEIAQAAAA==.',So='Soldek:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.Solnar:BAAALAAECgMIAwAAAA==.Somno:BAAALAAECgYIDgAAAA==.Sorabel:BAAALAADCgIIAgAAAA==.Soulfly:BAAALAAECgMIBQAAAA==.Soulsabi:BAAALAAECgYICwAAAA==.',Sp='Spatule:BAAALAAECgYIBwAAAA==.Sperk:BAAALAAECgYICwAAAA==.Spookyninja:BAABLAAECoEWAAIPAAgI2iHdAAAZAwAPAAgI2iHdAAAZAwAAAA==.Spoonman:BAAALAAECgEIAQAAAA==.Spâwn:BAAALAADCggIGAAAAA==.',St='Stardrift:BAAALAADCggIEgAAAA==.Stere:BAAALAAECgIIAwAAAA==.Steve:BAAALAADCgcICgAAAA==.Stifftotem:BAAALAADCggICwAAAA==.Stonecheeks:BAAALAADCgcIBwAAAA==.Stonedborn:BAAALAADCgYIBgAAAA==.Stream:BAAALAAECgMIBQAAAA==.Stärkiller:BAAALAAECgEIAQAAAA==.',Su='Suenami:BAAALAAECgcICwAAAA==.Supershenron:BAAALAAECgUICAAAAA==.Surprisë:BAAALAADCggICAAAAA==.',Sv='Svelesstiá:BAAALAADCgcIDgAAAA==.',Sw='Swamprhino:BAAALAADCgEIAQABLAAECgYIDwABAAAAAA==.Swan:BAAALAAECgMIBQAAAA==.Swoled:BAAALAAECgUIBQAAAA==.',Sy='Sybrand:BAAALAAECgYIDgAAAA==.Syrelliia:BAAALAAECgcIEQAAAA==.',['Sæ']='Sævage:BAAALAAECgMIBQAAAA==.',['Sø']='Sørta:BAAALAAECgMIBAAAAA==.',Ta='Tables:BAAALAAECgIIAgAAAA==.Tachi:BAAALAADCggIEwAAAA==.Tardovski:BAAALAADCgcIBwAAAA==.Tatertots:BAAALAAECgEIAQAAAA==.Tazorface:BAAALAAECgYIDwAAAA==.',Th='Tharkash:BAAALAAECgcIEAAAAA==.Thedockwho:BAAALAAECgEIAQAAAA==.Thedoctorwho:BAAALAADCggICAAAAA==.Theliarcy:BAAALAAECgYIDAAAAA==.Theodusjasbo:BAAALAADCgIIAgAAAA==.Thetorghuide:BAAALAAECgUICAAAAA==.Thiccbae:BAAALAAECggIAQAAAA==.Thirdeye:BAABLAAECoEWAAIEAAgIDx72BQCZAgAEAAgIDx72BQCZAgAAAA==.Thundastruck:BAAALAAECggIAQAAAA==.Thådius:BAAALAAECgYIDAAAAA==.',Ti='Tifalockhorn:BAAALAADCgQIBAAAAA==.Timidity:BAAALAAECgYICwAAAA==.Tirranoth:BAAALAADCgMIAwABLAADCggICAABAAAAAA==.',Tn='Tnarg:BAAALAADCgIIAgAAAA==.',To='Tommiee:BAAALAADCgIIAgAAAA==.Toolip:BAAALAAECgMIBQAAAA==.Tornwraith:BAAALAADCggIFgAAAA==.Touchingtoes:BAAALAADCggICQAAAA==.Tovash:BAAALAAECgMIAwAAAA==.',Tr='Trashfish:BAAALAADCggICAAAAA==.Triso:BAAALAAECgEIAQAAAA==.Tronus:BAAALAAECgEIAQAAAA==.Troodonus:BAAALAAECgMIBgAAAA==.',Ts='Tsukaar:BAAALAAECgYIBgAAAA==.',Tu='Turadactyl:BAAALAADCgIIAwAAAA==.',Ua='Uafool:BAAALAADCgUIBQAAAA==.',Ug='Ugathor:BAAALAAECgMIAwAAAA==.Ugway:BAAALAAECgcIDwAAAA==.',Un='Unforgyven:BAAALAADCggIGAAAAA==.',Ur='Ursoulismine:BAAALAADCgcICQAAAA==.',Uw='Uwuks:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.',Va='Valgaar:BAAALAAECgMIAwAAAA==.Valshear:BAAALAADCgcIBwAAAA==.Vaneste:BAABLAAECoEXAAMQAAgI6CKKAgBfAgAQAAcIPiOKAgBfAgARAAEIlCBBJABcAAAAAA==.Varessa:BAAALAADCggIDgAAAA==.Vartrino:BAAALAAECgYIDgAAAA==.Vasher:BAAALAAECggIBQAAAA==.Vaxxine:BAAALAADCgUIBQAAAA==.',Ve='Veganator:BAAALAAECgcIDwAAAA==.Velynda:BAAALAADCgcIDgABLAAECgMIBAABAAAAAA==.Venatris:BAAALAADCgYIDAAAAA==.Vendoralia:BAAALAAECgIIAgAAAA==.Veralynn:BAAALAAECgEIAQAAAA==.Verinastra:BAAALAADCgQIBAAAAA==.Verlant:BAAALAAECgEIAQAAAA==.Vermwing:BAAALAAECgYIDgAAAA==.',Vi='Viraya:BAAALAADCggIDwAAAA==.Virikae:BAAALAADCgUIBQAAAA==.Vixxeen:BAAALAADCgUICAAAAA==.',Vy='Vyniran:BAAALAAECgEIAQAAAA==.',Wa='Wallock:BAAALAADCgcIDQAAAA==.Warfury:BAAALAAECgMIBgAAAA==.Warpedpriest:BAAALAADCggIFAAAAA==.Watchnu:BAAALAADCgYIBgAAAA==.',Wh='Whammo:BAAALAAECgMIBAAAAA==.Whiterayne:BAAALAADCgcICAAAAA==.',Wi='Wildeholy:BAAALAAECggICAAAAA==.Willhelmina:BAAALAADCggIDQABLAAECgMIBQABAAAAAA==.Willowhite:BAAALAADCggIDwAAAA==.Wimberly:BAAALAAECgIIAgAAAA==.',Wl='Wlockholmes:BAAALAAECgMIBQAAAA==.',Wo='Wockyslush:BAAALAAECgMIBAAAAA==.Wolfrin:BAAALAADCggIEAAAAA==.',Wr='Wraithion:BAAALAAECgMIBgAAAA==.',Wu='Wubwub:BAAALAADCgcIBwAAAA==.Wulfjin:BAAALAAECgIIAgAAAA==.',Ya='Yabusame:BAAALAADCggIDQAAAA==.Yakisoba:BAAALAAECgUIBQAAAA==.',Yi='Yieqz:BAAALAADCggIDAABLAAECgIIAgABAAAAAA==.',Yo='Yokel:BAAALAAECgMIAwAAAA==.Yoze:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.',Za='Zah:BAAALAAECgQIBQAAAA==.Zalkrys:BAAALAAECgIIAgAAAA==.Zaln:BAAALAADCgUIBQAAAA==.Zandrim:BAAALAAECgUICwAAAA==.Zaremis:BAAALAAECgYIDAAAAA==.Zathore:BAAALAAECgIIAgAAAA==.Zayehuo:BAAALAADCggIEAAAAA==.',Ze='Zelphie:BAAALAAECgYIDgAAAA==.Zencrow:BAAALAAECgYIDwAAAA==.Zengadormu:BAAALAADCgYIBgAAAA==.Zent:BAAALAADCgcICwAAAA==.Zerttrak:BAAALAAECgcIBwAAAA==.Zeus:BAAALAAECgIIAgAAAA==.',Zi='Zirondella:BAAALAADCgcIBwABLAADCgYIDwABAAAAAA==.Zirondelle:BAAALAADCgYIBgABLAADCgYIDwABAAAAAA==.Zitawitch:BAAALAAECgEIAQAAAA==.',Zn='Zna:BAAALAAECgIIAgAAAA==.',['Æd']='Ædion:BAAALAAECgIIAgAAAA==.',['Ër']='Ërâgnõr:BAAALAAECgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end