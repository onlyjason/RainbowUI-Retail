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
 local lookup = {'Unknown-Unknown','Rogue-Subtlety','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','DeathKnight-Frost','Paladin-Retribution','Warrior-Arms',}; local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adonas:BAAALAADCgcIBwAAAA==.',Ae='Aera:BAAALAADCgcIBwAAAA==.Aeyther:BAAALAAECgUICAAAAA==.',Ag='Agave:BAAALAAECgYICwAAAA==.Aglaivmistak:BAAALAAECgYIBwAAAA==.Agromant:BAAALAADCggICAAAAA==.',Ah='Ahluethedrud:BAAALAADCgYICwAAAA==.',Al='Alexios:BAAALAAECgQIBAAAAA==.Allstate:BAAALAAECgMIBAAAAA==.Alluin:BAAALAAECgIIAwAAAA==.Almidas:BAAALAAECgYICAAAAA==.Alukarrd:BAAALAADCggIDgAAAA==.Alybeth:BAAALAADCgMIAwAAAA==.Alyriss:BAAALAAECgIIAgAAAA==.',An='Angelle:BAAALAAECgEIAgAAAA==.Annakin:BAAALAAECgYIBgAAAA==.Anora:BAAALAAECgcIDQAAAA==.',Ao='Aoitodo:BAAALAADCggIEAAAAA==.',Ap='Apostata:BAAALAAECgYIBgAAAA==.Apricitie:BAAALAADCgQIBgAAAA==.',Ar='Arcturi:BAAALAADCgQIBAAAAA==.Arelà:BAAALAAECgMIBAAAAA==.Arlynaa:BAAALAADCgIIAgAAAA==.',Au='Aunumator:BAAALAADCgcIDAAAAA==.',Av='Avocadorable:BAAALAADCggIEAAAAA==.Avâtre:BAAALAAECgYIDAAAAA==.',Az='Azamoth:BAAALAAECgIIAgAAAA==.',Ba='Bajingobomb:BAAALAAECgYICQAAAA==.Bajisil:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.Barkwoven:BAAALAAECgIIAgAAAA==.Bayonetta:BAEALAADCgYIBgABLAAECgYICQABAAAAAA==.',Be='Be:BAAALAAECgYICQAAAA==.Beerticus:BAAALAAECgYICQAAAA==.Bezos:BAAALAAECgYIBgAAAA==.',Bi='Bigdingus:BAAALAAECgUIBQAAAA==.Binggles:BAAALAAECgYICwAAAA==.Bingglesdru:BAAALAAECgEIAQAAAA==.',Bl='Blanque:BAAALAAECggIEwAAAA==.Blooddrain:BAAALAADCgcICwAAAA==.',Bo='Bobette:BAAALAAECgYICgAAAA==.Bodyspray:BAAALAAECgUIBQAAAA==.Bonnz:BAAALAADCgQIBAAAAA==.Boomboomboom:BAAALAAECgYICwAAAA==.Bootypoppinn:BAAALAAECgEIAQAAAA==.Booyay:BAAALAAECgYIDQAAAA==.Bosmina:BAAALAAECgcIEAAAAA==.Bouffalant:BAAALAAECgEIAQAAAA==.Boulder:BAAALAADCgMIAwABLAAECgYIBgABAAAAAA==.',Br='Brickme:BAAALAAECgMIAwAAAA==.Brielle:BAAALAADCgcICwABLAAECgEIAQABAAAAAA==.Brophyssor:BAAALAADCgEIAQABLAAECgMIBAABAAAAAA==.Bruucey:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.',Bu='Butchers:BAAALAAECgEIAQAAAA==.',Ca='Cadillactica:BAAALAADCgYIBgAAAA==.Cancel:BAAALAADCgYIBgAAAA==.Carademuerta:BAAALAAECgQIBAAAAA==.',Ce='Cernsarn:BAAALAAECgQICQAAAA==.',Ch='Chaklok:BAAALAADCgIIAgAAAA==.Chimkin:BAAALAAECggIEgAAAA==.Chiri:BAEALAAECgYICQAAAA==.Chvngus:BAAALAADCgEIAQAAAA==.',Ci='Cight:BAAALAADCggIDwAAAA==.Citizencain:BAAALAAECgMIAwAAAA==.',Cl='Clarabelle:BAAALAAECgEIAQAAAA==.',Co='Conmammoth:BAAALAAECgMIAwAAAA==.Coohwhip:BAAALAAECgYIBwAAAA==.Corky:BAAALAADCgMIAwAAAA==.Correction:BAAALAADCgcIBwAAAA==.',Cr='Crazybows:BAAALAADCgMIAwAAAA==.Cristobal:BAAALAAECgYIDQAAAA==.Cronùs:BAAALAADCgYIBgAAAA==.',Cu='Curaga:BAAALAAECgYICwAAAA==.',Cy='Cyrails:BAAALAAECgYIBgAAAA==.',Da='Dagwar:BAAALAAECgIIAgAAAA==.Dahlster:BAAALAADCgEIAQAAAA==.Dajogaqui:BAAALAADCgcIDAAAAA==.Dannytanaris:BAAALAADCgEIAQAAAA==.Darkmajìk:BAAALAADCgIIAgAAAA==.Dawknee:BAAALAADCgYIDAAAAA==.',De='Deathbejaman:BAAALAADCggICAAAAA==.Deathclock:BAAALAAECgQICAAAAA==.Degey:BAAALAAECgYICQAAAA==.Deign:BAAALAAECgcIEAAAAA==.Demordh:BAAALAAECgcICgAAAA==.Deriso:BAAALAAECgYIDQAAAA==.Derivate:BAAALAAECgYICQAAAA==.Deyanoriel:BAAALAAECgMIAwAAAA==.',Di='Diagonpally:BAAALAAECgcIDQAAAA==.Divah:BAAALAAECgMIAwAAAA==.',Dr='Dracovish:BAAALAAECgcICwAAAA==.Drakbek:BAAALAADCggIDQAAAA==.Dreco:BAAALAADCgUIBQAAAA==.Drelik:BAAALAADCgUIBgAAAA==.Dronebot:BAAALAAECgcIEAAAAA==.Drucifer:BAAALAAECgEIAQAAAA==.Drungle:BAAALAADCgQIBAAAAA==.Drúcifer:BAAALAADCgYICAAAAA==.',Du='Duelfiend:BAAALAADCgcIBwAAAA==.Durumi:BAAALAAECgMIBQAAAA==.Dustyshotz:BAAALAAECgIIAgAAAA==.',Dw='Dwall:BAAALAAECgMIAwAAAA==.',Dy='Dys:BAAALAAECgMIBgAAAA==.',Dz='Dzieux:BAAALAADCggIDwAAAA==.Dznutz:BAAALAADCggICAAAAA==.',El='Elavyn:BAAALAAECggIEgAAAA==.Elyor:BAAALAADCgcIDAAAAA==.',Er='Ervish:BAAALAAECgcIDQAAAA==.',Es='Eshesofalar:BAAALAADCgYIBgAAAA==.Estraya:BAAALAADCgcICAAAAA==.',Eu='Euphoricxx:BAAALAAECgcIEgAAAA==.',Fa='Faithles:BAAALAAECgMIAwAAAA==.Falgur:BAAALAAECgcIEAAAAA==.Fantasma:BAAALAADCggIFQAAAA==.',Fe='Fergalis:BAAALAADCggICAABLAAECgYICwABAAAAAA==.',Fi='Findal:BAAALAAECgQIBwAAAA==.Finley:BAAALAADCggIBAAAAA==.Fivemagics:BAAALAAECgYIDgAAAA==.',Fl='Floorhammer:BAAALAAECgUIBQAAAA==.',Fo='Fotation:BAAALAAECgEIAQAAAA==.Foxlock:BAAALAAECgEIAQAAAA==.',Fr='Fraas:BAAALAAECgcIEwAAAA==.Frankyice:BAAALAAECgYICQAAAA==.Frostytugg:BAAALAADCgYIBgAAAA==.',Fy='Fyaball:BAAALAAFFAIIBAAAAA==.',Ga='Gambitt:BAAALAAECgIIAwAAAA==.Gamer:BAAALAAECgYICgAAAA==.Gammaray:BAAALAAECggIEwAAAA==.Garbandis:BAAALAAECgQIBwAAAA==.Gash:BAACLAAFFIEFAAICAAMIsBaxAAAHAQACAAMIsBaxAAAHAQAsAAQKgRYAAgIACAiSHScCAJwCAAIACAiSHScCAJwCAAAA.Gawdric:BAAALAAECggIEgAAAA==.',Ge='Generosity:BAAALAAECgcIEwAAAA==.',Gi='Gibsmedats:BAAALAAECgYICQAAAA==.',Gl='Glaiven:BAAALAAECgMIAwAAAA==.Glenfiddich:BAAALAAECgYICQAAAA==.',Gn='Gnartusk:BAAALAAECgMIBQAAAA==.',Go='Gonch:BAAALAAECgYICgAAAA==.Gorrgra:BAAALAADCgMIAwAAAA==.',Gr='Grandmapunch:BAAALAADCgYIBgABLAAECgQIBAABAAAAAA==.Gravepalm:BAAALAAECgYICAAAAA==.Greko:BAAALAAECgIIAgAAAA==.Grumpylock:BAAALAADCggIDwAAAA==.',Gs='Gsus:BAAALAAECgQIBwAAAA==.',Gu='Gueritestje:BAAALAAECgQIBAAAAA==.Guzzlord:BAAALAAECgUIBQAAAA==.',He='Healynn:BAAALAADCgYIBgAAAA==.',Hi='Hitoshura:BAAALAAECgYICwAAAA==.',Hl='Hllzones:BAAALAADCgIIAgAAAA==.',Ho='Hobbesworth:BAAALAAECgMIAwAAAA==.Hoboman:BAAALAAECgQIBAAAAA==.Holygail:BAAALAAECggIEQAAAA==.Holyginger:BAAALAADCgIIAgAAAA==.Hotjohn:BAAALAAECggIDwAAAA==.Howitzerx:BAAALAADCgcIBwAAAA==.',Hu='Hunghog:BAAALAADCggIAwAAAA==.Hustus:BAAALAAECgYIBwAAAA==.',Hy='Hydrate:BAAALAADCgUIAQABLAAECgYICwABAAAAAA==.',Id='Ididntknow:BAAALAADCgYICwAAAA==.Idlehand:BAAALAADCggIDQABLAAECgYICAABAAAAAA==.',In='Indrani:BAAALAAECgYICQAAAA==.Infidel:BAABLAAECoEXAAIDAAgIbyNiBAAPAwADAAgIbyNiBAAPAwAAAA==.Innogen:BAAALAAECgcIEAAAAA==.Invert:BAAALAAECgcIEQAAAA==.',Io='Iorlas:BAAALAAECgYICQAAAA==.',Ip='Ippiekiyaymf:BAAALAAECgEIAQAAAA==.Ippy:BAAALAADCggIDAAAAA==.',Ir='Irishillidan:BAAALAAECgEIAQAAAA==.Irishman:BAAALAADCgYICgAAAA==.',Is='Isometrics:BAAALAADCgYICwAAAA==.',Ja='Jadebrulee:BAAALAADCgIIAgAAAA==.Jalter:BAAALAADCgMIAwABLAAECgcIEwABAAAAAA==.Jaltok:BAAALAAECgYIBgAAAA==.Jarjárßlinks:BAAALAADCggICAAAAA==.Jawnclawgodx:BAAALAADCgUIBQABLAAECggIDwABAAAAAA==.',Je='Jenga:BAAALAAECggIBwAAAA==.',Jf='Jf:BAAALAAECgcIEQAAAA==.',Ji='Jinrokh:BAAALAAECgYIDQAAAA==.Jitzakkal:BAACLAAFFIEFAAMEAAMIcx+2AgAiAQAEAAMIQhu2AgAiAQAFAAIIvhwbAgC9AAAsAAQKgRcAAwQACAhzJIsJALMCAAQABwiwI4sJALMCAAUABQheH88PAIkBAAAA.',Jo='Johnleekgodx:BAAALAAECgIIAgAAAA==.Johnnycool:BAAALAADCgIIAwABLAAECgEIAQABAAAAAA==.Johnpaladin:BAAALAAECgcIBwAAAA==.',Ju='Juliant:BAAALAADCgYICQAAAA==.',Ka='Kait:BAAALAADCggICAAAAA==.Kajaan:BAAALAADCgYIBgAAAA==.Kalgard:BAAALAAECgYICQAAAA==.Karax:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Karpathous:BAAALAAECggICAAAAA==.Kasey:BAAALAAECgEIAQAAAA==.',Kc='Kcebrëps:BAAALAAECgYIBgAAAA==.',Ke='Keladorn:BAAALAAECgEIAQAAAA==.',Kh='Khanyiso:BAAALAAECgYICwAAAA==.',Ki='Kickme:BAAALAADCggICAAAAA==.Kieran:BAAALAAECgYICwAAAA==.Kikimora:BAAALAADCgcIBwAAAA==.Killsaurus:BAABLAAECoEUAAIGAAcIuiFRCQC0AgAGAAcIuiFRCQC0AgAAAA==.',Kn='Kneehunt:BAAALAADCggICAAAAA==.',Kr='Krixus:BAAALAADCgYIBgAAAA==.',Ku='Kunetakinte:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.',Kw='Kwaz:BAAALAAECgYIBgABLAAECgYIBwABAAAAAA==.Kwazard:BAAALAAECgYIBwAAAA==.',Ky='Kysa:BAAALAAECggIEQAAAA==.Kysoti:BAAALAADCgcIBwAAAA==.',La='Lamer:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Lancebass:BAAALAAECgQIBAAAAA==.Lankyntanky:BAAALAAECggIEwAAAA==.Largepetr:BAAALAAECgEIAQAAAA==.Laternerd:BAAALAADCgEIAQAAAA==.',Le='Lenarius:BAAALAADCggICAABLAAECggIFQAHAH4cAA==.Lepale:BAAALAAECgYIBQAAAA==.Lesthar:BAAALAADCgYICAAAAA==.',Li='Liliel:BAAALAAECgEIAQAAAA==.Lindi:BAAALAADCgcICAAAAA==.Littlecid:BAAALAAECgIIAgABLAAECgQIBwABAAAAAA==.Littlerat:BAAALAADCgIIAwAAAA==.',Lo='Lockmog:BAAALAAECgYIBgAAAA==.Lokrom:BAAALAAECgIIAwAAAA==.',Ly='Lynvala:BAAALAADCgQIBAAAAA==.Lysergicburn:BAAALAAECgYICAAAAA==.',['Lô']='Lôx:BAAALAADCgMIAgAAAA==.',Ma='Magturri:BAAALAAECgYICQAAAA==.Maiwaife:BAAALAAECgUICgAAAA==.Majinjohn:BAAALAAECggIEwAAAA==.Manolo:BAABLAAECoHHAAIIAAgI4yZHAACaAwAIAAgI4yZHAACaAwAAAA==.Marcusdapimp:BAAALAAECggIEgAAAA==.Mashimo:BAAALAADCggIFwAAAA==.Matattal:BAAALAADCgcIBwAAAA==.Maxfirepower:BAAALAADCgUIBQAAAA==.Maxfrogpower:BAAALAADCgcIBwAAAA==.Maxsunward:BAAALAADCgcIDQAAAA==.',Me='Meatballmike:BAAALAADCgUIBQAAAA==.Meepasaurus:BAAALAAECgcIDgAAAA==.Meliiodas:BAAALAAECgMIAwAAAA==.Mellky:BAAALAAECgcIEQAAAA==.Metanoia:BAAALAAECgcIEwAAAA==.',Mi='Mibb:BAAALAAECggIEQAAAA==.Midnitetrvlr:BAAALAADCgMIAwAAAA==.Mirren:BAAALAAECgUICAAAAA==.Misdiagnosis:BAAALAADCggICAAAAA==.Misfit:BAAALAAECgYIDgAAAA==.Missmoans:BAAALAADCgEIAQABLAAECgMIBAABAAAAAA==.',Mo='Mommyrose:BAAALAAECgYIBgAAAA==.Momojojo:BAAALAAECgYIEAAAAA==.Moonflame:BAAALAAECgYICQAAAA==.Moonmoonmoon:BAAALAAECgYICwAAAA==.Morphyne:BAAALAAECgcIEgAAAA==.Mosdeath:BAAALAADCgQIBAAAAA==.Moselli:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Moserr:BAAALAADCggICAAAAA==.',My='Mykrin:BAAALAAECgMIAwAAAA==.Mynchus:BAAALAADCgUIBgAAAA==.Mystictomato:BAAALAAECgYICgAAAA==.',['Mà']='Màlachi:BAAALAAECgMIBgAAAA==.',['Má']='Máxine:BAAALAADCggIDwAAAA==.',Na='Narrator:BAAALAAECgYIBgAAAA==.Natasa:BAAALAAECgUICAAAAA==.Natedog:BAAALAAECgcIEQAAAA==.Navanni:BAAALAADCgcIDgAAAA==.',Ne='Neamheaglach:BAABLAAECoEVAAIHAAgIfhz1EQB3AgAHAAgIfhz1EQB3AgAAAA==.Neotahr:BAAALAAECgcIEAAAAA==.Neu:BAAALAAECgMIAwAAAA==.',Ni='Nihl:BAAALAAECgEIAQAAAA==.',Nu='Nubchi:BAAALAAECgIIAgAAAA==.Nuggies:BAAALAAECgUIBQAAAA==.Nuug:BAAALAADCggIDQAAAA==.',['Nô']='Nôva:BAAALAAECgUIBgAAAA==.',['Nö']='Növacaïn:BAAALAADCgYIBgAAAA==.',Oi='Oistos:BAAALAAECggIEAAAAA==.',Om='Omicron:BAAALAAECgQIBAAAAA==.Omnii:BAAALAADCgIIAgAAAA==.',On='Ono:BAAALAAECgYICQAAAA==.Onslaught:BAAALAAECgYIBwAAAA==.',Oo='Oohso:BAAALAAECgQIBQAAAA==.Oomfie:BAAALAADCggIFQAAAA==.',Or='Oreum:BAAALAAECgMIAwAAAA==.',Os='Osirìs:BAAALAADCgQIBAAAAA==.',Pa='Pallyana:BAAALAADCggICQAAAA==.Parch:BAAALAAECgYICwAAAA==.Parsleyposh:BAAALAADCgQIBAAAAA==.Paåyne:BAAALAADCgcIBwAAAA==.',Pe='Perituvir:BAAALAAECgMIAwAAAA==.Pesto:BAAALAAECgMIAwAAAA==.',Ph='Phteve:BAAALAADCgIIAgAAAA==.',Pi='Pixieluv:BAAALAAECggIEgAAAA==.',Pl='Plastic:BAAALAADCgMIAwAAAA==.',Po='Pom:BAAALAAECgMIAwAAAA==.',Pr='Prabishar:BAAALAADCgcIBwAAAA==.Praystatiøn:BAAALAADCgQIBAAAAA==.',Ps='Psyop:BAAALAAECgMIBgAAAA==.',Pu='Punked:BAAALAADCgYIBgAAAA==.',['Pä']='Päntera:BAAALAAECgUIDgAAAA==.',Qc='Qcumber:BAAALAADCgcIBwAAAA==.',Qu='Quiver:BAAALAAECgcIEgAAAA==.',Qy='Qyill:BAAALAAECgYIBgAAAA==.',Ra='Raensong:BAAALAADCgcIBgAAAA==.Raisa:BAAALAAECgYIDwAAAA==.Rakardos:BAAALAADCgEIAQAAAA==.Rasar:BAAALAAECgYICQAAAA==.Rawdric:BAAALAAECgUIBQAAAA==.Raymora:BAAALAAECgYIBgAAAA==.',Re='Rebeccablack:BAAALAAECgYICwAAAA==.Resolute:BAAALAADCggICAAAAA==.Restó:BAAALAADCgYIBgAAAA==.Ret:BAABLAAECoEUAAIJAAgIyB1xAQCxAgAJAAgIyB1xAQCxAgAAAA==.Rett:BAAALAADCgcIBwABLAAECggIFAAJAMgdAA==.Rexxy:BAAALAAECgcIEQAAAA==.',Ri='Riddlez:BAAALAAECgMIBAAAAA==.Riott:BAAALAADCgUIBQAAAA==.',Ro='Romoko:BAAALAAECgYICAAAAA==.Rorshk:BAAALAAECgUIBQAAAA==.Roydruid:BAAALAADCgYIDAAAAA==.Roysham:BAAALAAECgMIAwAAAA==.Roywar:BAAALAADCgcIDQAAAA==.',Ry='Rycicle:BAAALAAECgEIAQAAAA==.',Sa='Sanbi:BAAALAADCggICwAAAA==.Sathe:BAAALAAECgMIBQAAAA==.Saverance:BAAALAADCggICQABLAAECgcIEgABAAAAAA==.Savernity:BAAALAAECgcIEgAAAA==.Savingrace:BAAALAAECgMIAwABLAAECgcIEgABAAAAAA==.Savotage:BAAALAADCggICgABLAAECgcIEgABAAAAAA==.Savrynn:BAAALAAECgYIDwABLAAECgcIEgABAAAAAA==.',Sc='Scalelord:BAAALAADCgcICAAAAA==.',Se='Selbi:BAAALAAECgYIBgAAAA==.Selsk:BAAALAAECgUICAAAAA==.Senjougahara:BAAALAAFFAIIAgAAAA==.Seriyah:BAAALAAECgcIEQAAAA==.',Sg='Sgtmav:BAAALAAECgEIAQAAAA==.',Sh='Shabane:BAAALAAECgMIBQAAAA==.Shaggy:BAAALAADCgYIBgAAAA==.Shanbubu:BAAALAADCgcIBwAAAA==.Shento:BAAALAADCgEIAQAAAA==.Shidayah:BAAALAADCgcIDgAAAA==.Shiminy:BAAALAADCgEIAQAAAA==.Shinobi:BAAALAAECgYICQAAAA==.Shirls:BAAALAAECgQIBwAAAA==.Shivaetwo:BAAALAAECgcIEAAAAA==.Shivanie:BAAALAADCgcIBwAAAA==.Shubie:BAAALAAECgMIAwAAAA==.',Si='Silvergodx:BAAALAAECggIEQAAAA==.',Sk='Skragg:BAAALAAECgUICAAAAA==.Skullkin:BAAALAAECgMIAwAAAA==.Skylinex:BAAALAAECggICQAAAA==.Skïttles:BAAALAAECgMIBAAAAA==.',Sl='Slardar:BAAALAADCgcIBwAAAA==.Sleezball:BAAALAAECgQIBwAAAA==.',Sn='Sneakybae:BAAALAADCgIIAgAAAA==.',So='Sobek:BAAALAAECgMIBgAAAA==.Soksabai:BAAALAAECgYIDAAAAA==.Sonata:BAAALAAECgYIBgAAAA==.Songraven:BAAALAADCggICAAAAA==.Sonicdeath:BAAALAAECgYICQAAAA==.Sonictide:BAAALAAECgEIAQAAAA==.Southie:BAAALAAECgcIEAAAAA==.',Sp='Spicytacoo:BAAALAADCggIDgAAAA==.',St='Stacy:BAAALAADCggICAAAAA==.Stepdag:BAAALAAECgcIDgAAAA==.Stonebro:BAAALAAECgIIAgAAAA==.Strey:BAAALAAECgIIAgAAAA==.Stryve:BAAALAADCggIDgAAAA==.',Sw='Swiftyninja:BAAALAAECgcIEAAAAA==.',Sy='Synder:BAAALAAECgYICwAAAA==.',['Sà']='Sàvîor:BAAALAADCgIIAgAAAA==.',Ta='Taaienberg:BAAALAAECgIIAgAAAA==.Tabata:BAAALAAECgYIBgAAAA==.Taco:BAAALAAECgUICAAAAA==.Tailwind:BAAALAAECgYICwAAAA==.Tainin:BAAALAAECgMIBQAAAA==.Talogos:BAAALAAECgQIBQAAAA==.Targus:BAAALAAECgMIBQAAAA==.Tarynna:BAAALAAECgMIAwAAAA==.',Te='Teilande:BAAALAAECgIIAwAAAA==.Telrissan:BAAALAAECgYICQAAAA==.Tenyroldemon:BAAALAAECgYICQAAAA==.',Th='Thald:BAAALAAECgYICgAAAA==.Thaznotmilk:BAAALAADCgEIAQAAAA==.Thebatmon:BAAALAAECgMIAwAAAA==.Thendera:BAAALAAECgMIBQAAAA==.Thirst:BAAALAAECgMIBAABLAAECgYICAABAAAAAA==.Thrintknight:BAAALAADCggIDgAAAA==.',Ti='Tikaywhoa:BAAALAAECgMIAwAAAA==.Tisakna:BAAALAAECgcIEAAAAA==.',To='Torquee:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.Totempetr:BAAALAADCgYIBgAAAA==.Touchmitotem:BAAALAADCgYIDAAAAA==.',Tr='Trask:BAAALAAECgUICAAAAA==.Treefort:BAAALAADCgUIBQAAAA==.',Tu='Tuggthedruid:BAAALAAECgYIDgAAAA==.Turbowar:BAAALAAECgEIAQAAAA==.',Us='Usedgoods:BAAALAAECggICAAAAA==.',Va='Vanderuid:BAAALAAECgYIDwAAAA==.',Vi='Vidrus:BAAALAADCgEIAQAAAA==.',Vj='Vjay:BAAALAADCggIHQAAAA==.',Vl='Vlana:BAAALAADCggICQAAAA==.',Vo='Voodoowhodo:BAAALAAECgMIBgAAAA==.',['Vä']='Välmet:BAAALAAECgcIEgAAAA==.',['Vê']='Vêngênce:BAAALAADCgcIDwAAAA==.',Wa='Waddledoo:BAAALAAECgUICAAAAA==.',We='Wethands:BAAALAADCggICAAAAA==.',Wi='Wishez:BAAALAADCgEIAQAAAA==.',Xe='Xenomortis:BAAALAAECgIIAgAAAA==.',Xi='Xiangorne:BAAALAAECgYICQAAAA==.Xindormi:BAAALAAECgYIDQAAAA==.',Xm='Xmanish:BAAALAADCgcIBwAAAA==.',Xo='Xoro:BAAALAADCgQIBAAAAA==.',Xr='Xrxyz:BAAALAAECgYICAAAAA==.',Ye='Yertgodx:BAAALAADCggIDAAAAA==.Yewna:BAAALAAECgUICQABLAAECgcIDQABAAAAAA==.',Yu='Yurnero:BAAALAADCgcIDwAAAA==.',Za='Zachdrac:BAAALAADCgcIDQAAAA==.Zachsham:BAAALAADCgcICAAAAA==.Zahrah:BAAALAAECgMIAwAAAA==.Zambeezi:BAAALAADCgcICwABLAAECgMIAwABAAAAAA==.Zanyp:BAAALAAECgUICAAAAA==.Zau:BAAALAAECgUICAAAAA==.',Zy='Zyke:BAAALAADCggIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end