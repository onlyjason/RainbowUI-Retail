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
 local lookup = {'Unknown-Unknown','Shaman-Restoration','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction',}; local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Accett:BAAALAAECgQIBgAAAA==.',Ak='Akkane:BAAALAAECgMIAwAAAA==.',Al='Albertwesker:BAAALAADCgcICgAAAA==.Alethrix:BAAALAAECgEIAQAAAA==.Alexi:BAAALAADCgUICAAAAA==.Allitha:BAAALAAECgMIAwAAAA==.Alynas:BAAALAADCgcIBwAAAA==.',Am='Amorias:BAAALAADCggIDAAAAA==.',Ap='Apophìs:BAAALAADCgcIDQAAAA==.',Ar='Areto:BAAALAAECgIIAgAAAA==.Arold:BAAALAADCggIDgAAAA==.Artemysia:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.',As='Asylia:BAABLAAECoEVAAICAAgIgh8dBADZAgACAAgIgh8dBADZAgAAAA==.',At='Atlantus:BAAALAADCggICAABLAAECgIIAwABAAAAAA==.',Au='Aug:BAACLAAFFIEKAAIDAAUITCF2AAAKAgADAAUITCF2AAAKAgAsAAQKgRYAAgMACAigJikAAJMDAAMACAigJikAAJMDAAAA.',Av='Avesiren:BAAALAADCggIDwAAAA==.',Ay='Ayidá:BAAALAADCgYICgAAAA==.',Ba='Babalunious:BAAALAAECgIIAwAAAA==.Babymamaa:BAAALAADCgcIDQAAAA==.Babymuffins:BAAALAAECgIIAgAAAA==.',Be='Belligeranta:BAAALAADCgYIBgAAAA==.',Bi='Bigbabybustx:BAAALAAECgcIDQAAAA==.',Bl='Blackmill:BAAALAAECgIIAgAAAA==.Blathmac:BAAALAADCgcIBwAAAA==.',Bo='Bootzee:BAAALAADCggIEQAAAA==.Bordamot:BAAALAAECgMIAwAAAA==.',Br='Britishchick:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Brotatochips:BAAALAADCgcIDQAAAA==.Brunhilian:BAAALAADCgcIEQAAAA==.',Ca='Cadun:BAAALAAECgIIAgAAAA==.Calada:BAAALAADCggIDwAAAA==.Callypso:BAAALAAECgIIAwAAAA==.Cathrogue:BAAALAAECgQIBAAAAA==.',Ce='Cedarnia:BAAALAADCgIIAgAAAA==.',Ch='Charot:BAAALAADCgUIBQAAAA==.',Ci='Citchelas:BAAALAAECgQIBQAAAA==.',Cr='Craftykit:BAAALAADCggIFgAAAA==.Cribbage:BAAALAADCgYIBgAAAA==.',Cy='Cytrondark:BAAALAADCgcIDQAAAA==.',Da='Danlor:BAAALAAECgEIAQAAAA==.Darkheaven:BAAALAAECgMIAwAAAA==.Dazarek:BAAALAAECgIIAwAAAA==.',De='Debbie:BAAALAAECgYIDQAAAA==.Demglavesdoe:BAAALAADCgYIBgAAAA==.Devinetoro:BAAALAAECgMIBQAAAA==.Devour:BAAALAAECgYICgAAAA==.',Di='Diaga:BAAALAAECgMIBQAAAA==.',Do='Doree:BAAALAADCgUIBQAAAA==.',Dr='Dragal:BAAALAADCgIIAgAAAA==.Drathlagar:BAAALAADCgYIBwAAAA==.Drboberella:BAAALAADCggIBQAAAA==.',Ea='Eatêr:BAAALAADCgIIAgAAAA==.',El='Elusive:BAAALAADCggICAAAAA==.',Em='Emune:BAAALAAECgIIAgAAAA==.',En='Enoira:BAAALAAECgEIAQAAAA==.Enver:BAAALAADCggICAAAAA==.',Ep='Epistle:BAAALAADCggIDwAAAA==.',Et='Eternaldoom:BAAALAADCgYICgAAAA==.',Fa='Faffard:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Fartalot:BAAALAAECgIIAwAAAA==.',Fe='Feleaf:BAAALAADCgIIAgAAAA==.Fennerick:BAAALAAECgYICgAAAA==.Feyndra:BAAALAADCggICwAAAA==.',Fr='Frick:BAAALAADCgcIDgAAAA==.',Fu='Fuglydude:BAAALAADCgcICgAAAA==.',Fy='Fystie:BAAALAADCggIDwABLAAECgEIAQABAAAAAA==.',Ge='Gebra:BAAALAADCgMIAwABLAAECgMIBQABAAAAAA==.',Gh='Ghugorend:BAAALAADCgIIAgAAAA==.',Gi='Giavanna:BAAALAADCggICgAAAA==.',Go='Goose:BAAALAADCgYIAwAAAA==.',Gr='Grashen:BAAALAADCgcICgAAAA==.',Gs='Gsm:BAAALAAECgMIBQAAAA==.',Gu='Gurlyman:BAAALAADCgcIDQAAAA==.',Ha='Hanako:BAAALAAECggIEgAAAQ==.Hante:BAAALAADCgQIBwAAAA==.',He='Heelsya:BAAALAAECgMIAwAAAA==.',Hi='Hi:BAAALAAECgEIAQAAAA==.Hipsterjestr:BAAALAADCgMIAwAAAA==.',Ho='Hoomnooba:BAAALAADCgcIDQAAAA==.Hotspur:BAAALAAECgIIAgAAAA==.',Hu='Hukmunk:BAAALAADCggIEwAAAA==.',Ja='Jacspally:BAAALAAECgIIAwAAAA==.Janora:BAAALAAECgMIAwAAAA==.Jarlath:BAAALAADCgQIBAAAAA==.',Je='Jebra:BAAALAAECgMIBQAAAA==.Jellexy:BAAALAADCggIDwAAAA==.Jellibean:BAAALAAECgEIAQAAAA==.',Jo='Johnnybone:BAAALAADCggIDwAAAA==.Jonnyfive:BAAALAADCgcIDQAAAA==.Josephyn:BAAALAADCgcICgABLAAECgcIEAABAAAAAA==.',Ka='Kayzon:BAACLAAFFIEGAAIEAAMI9hlAAQAnAQAEAAMI9hlAAQAnAQAsAAQKgR4AAwQACAidI9IDAC0DAAQACAidI9IDAC0DAAUAAQgMBj1QAC0AAAAA.',Ke='Kenshiro:BAAALAADCgcIDQAAAA==.',Kh='Khandragho:BAAALAADCgUIBQAAAA==.Khorne:BAAALAADCgcICQAAAA==.',Ki='Kij:BAAALAAECgIIAgAAAA==.',Kl='Klavine:BAAALAAECggIDgAAAA==.',Ko='Korben:BAAALAAECgYICgAAAA==.',Kr='Kragh:BAAALAADCggIDwAAAA==.Krazybish:BAAALAADCggIFQAAAA==.Kronn:BAAALAADCgcIDQAAAA==.Kryptonicboy:BAAALAADCgUIBQAAAA==.',Ku='Kublakhan:BAAALAAECgIIBAAAAA==.',La='Lakhi:BAAALAAECgUICAAAAA==.Laureli:BAAALAADCggIDwAAAA==.',Le='Leeta:BAAALAAECgIIAgAAAA==.Lemooski:BAAALAAECgYIDAAAAA==.Leorra:BAAALAAECgMIAwAAAA==.Letholdus:BAAALAAECgEIAQAAAA==.',Li='Lightningg:BAAALAAECgMIAwAAAA==.',Lo='Lokralaila:BAAALAADCgcICgAAAA==.Loraley:BAAALAADCgYIBgAAAA==.Losoz:BAAALAAECgEIAgAAAA==.',Lu='Lucifera:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.',Ly='Lynk:BAAALAADCgcIBwAAAA==.',Ma='Madouke:BAAALAAECgYICAAAAA==.Maegwin:BAAALAAECgEIAQAAAA==.Magusbilly:BAAALAADCgEIAQAAAA==.Malarch:BAAALAAECgYIBgAAAA==.Mandi:BAAALAAECgIIAgAAAA==.Matchstíck:BAAALAAECgEIAQAAAA==.Maxxpowerz:BAAALAADCgcICAAAAA==.',Me='Mellaise:BAAALAADCggIFgAAAA==.',Mi='Mikonawa:BAAALAADCgcIDwAAAA==.Mildrik:BAAALAAECgMIAwAAAA==.Minsc:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Mirkdrak:BAAALAADCgcIDgAAAA==.Misfed:BAAALAAFFAEIAQAAAA==.Mishach:BAAALAADCgUIBgABLAADCgYIBgABAAAAAA==.Missus:BAAALAADCggIDgAAAA==.Mizzen:BAAALAAECgEIAQAAAA==.Miång:BAAALAADCgcICgAAAA==.',Mo='Mohdaddy:BAAALAAECgMIAwAAAA==.Mommydearest:BAAALAAECgEIAQAAAA==.Morganná:BAAALAAECgYICAAAAA==.Motz:BAAALAAECgMIBAAAAA==.Motzart:BAAALAADCgEIAQAAAA==.',Mu='Munkìe:BAAALAADCgQIBAABLAAECgMIBQABAAAAAA==.',['Mí']='Míku:BAAALAAECgYIBgAAAA==.',Na='Narddog:BAAALAADCgMIAwAAAA==.',Ne='Negate:BAAALAAECggIDwAAAA==.',No='Nosine:BAAALAADCgMIAwAAAA==.',['Në']='Nëptune:BAAALAAECgcIEAAAAA==.',Om='Omnidacc:BAAALAADCggICAAAAA==.',Or='Oroko:BAAALAAECgEIAQAAAA==.Oroku:BAAALAAECgEIAgAAAA==.Oruko:BAAALAADCgcIBwAAAA==.',Ot='Otwin:BAAALAADCgcIDQAAAA==.',Pa='Pahuum:BAAALAADCgcIDQAAAA==.Palewhiteman:BAAALAADCgcIBwAAAA==.Palleigh:BAAALAAECgIIAwAAAA==.',Pe='Pepélepewpew:BAAALAADCgcIBwAAAA==.',Po='Polat:BAAALAADCgcICgAAAA==.Poodleparty:BAAALAAECgIIBgAAAA==.',Qu='Quanta:BAAALAADCggIEgAAAA==.',Ra='Raptorling:BAAALAADCgQIBAAAAA==.',Re='Renaus:BAAALAADCgcIBwAAAA==.',Ri='Rinsê:BAAALAADCgMIAwABLAADCgMIAwABAAAAAA==.Ripptyde:BAAALAADCggIDwAAAA==.',Ro='Rocthoeb:BAAALAAECggIEgAAAA==.Rorq:BAAALAAECgMIAwAAAA==.',Ru='Run:BAAALAAECgEIAQAAAA==.Russbuss:BAAALAADCgMIAwAAAA==.',Ry='Ry:BAAALAAECgEIAgAAAA==.',Sa='Saelsia:BAAALAADCgUIBQAAAA==.Saintfoxtrot:BAEALAADCggIDQAAAA==.Sativva:BAAALAADCgcIBwAAAA==.',Sc='Scrybe:BAAALAADCgcIDAAAAA==.',Se='Setsena:BAAALAAECgMIAwAAAA==.',Sh='Shinstabber:BAAALAAECgMIAwAAAA==.Shockedballs:BAAALAADCgMIAwAAAA==.',Si='Siphondark:BAAALAAECgMIAwAAAA==.Sitak:BAAALAADCgIIAgAAAA==.',Sl='Slapnutz:BAAALAAECgYIDwAAAA==.Slashcry:BAAALAADCgcIDQAAAA==.Slaylorswift:BAAALAADCgUIBQABLAAECgMIBQABAAAAAA==.',So='Sofedor:BAAALAADCgcIBwAAAA==.',St='Starcaller:BAAALAAECgYICgAAAA==.Stmonster:BAAALAADCgcICAAAAA==.Stratacaster:BAAALAADCgMIAwAAAA==.Stuckinwell:BAACLAAFFIEFAAMGAAMIsRZIAwCzAAAGAAII1RdIAwCzAAAHAAEIaBT0DABbAAAsAAQKgRQABAYACAg0IqMGAPoBAAYABgilH6MGAPoBAAcABAg7Ib4qAGEBAAgAAgjBCTAeAI4AAAAA.',Sw='Swike:BAAALAADCgQIBAAAAA==.',Ta='Tach:BAAALAADCgcIBwAAAA==.Taenir:BAAALAADCggIFgAAAA==.Taílorswift:BAAALAAECgMIBQAAAA==.',Te='Temna:BAAALAAECgMIBQAAAA==.Terepal:BAAALAADCggICQAAAA==.',Th='Theel:BAAALAADCggIDAAAAA==.',Ti='Tikitoki:BAAALAADCgEIAQAAAA==.Tinbasher:BAAALAAECgYICQAAAA==.Tinlock:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Tiriön:BAAALAAECgIIBAAAAA==.',Tj='Tjshoots:BAAALAADCgYIBgAAAA==.Tjugofyra:BAAALAADCgQIBAAAAA==.',To='Totemistic:BAAALAADCgcIDAAAAA==.',Tr='Treebilly:BAAALAADCgMIAwAAAA==.Triviousox:BAAALAADCgcICgAAAA==.',Tw='Twilightjade:BAAALAADCgcIDgAAAA==.',Un='Unbanme:BAAALAAECgcIEwAAAA==.Unglued:BAAALAAECgMIAwAAAA==.',Ut='Uttrsdeek:BAAALAADCgUIBQAAAA==.Uttrspriest:BAAALAAECgYIDQAAAA==.',Va='Valaesha:BAAALAAECggICAAAAA==.Valkknaifu:BAAALAAECgMIBQAAAA==.Valkrie:BAAALAADCggIFwAAAA==.Valleya:BAAALAAECgYICAAAAA==.',Ve='Vessna:BAAALAADCgQIBAAAAA==.',Vi='Vivîán:BAAALAADCggIDwAAAA==.',Vo='Vonsnuffles:BAAALAADCggICwAAAA==.Voras:BAAALAADCgUIBQAAAA==.Voxidead:BAAALAAECgMIAwAAAA==.Voximonk:BAAALAAECgYIBgAAAA==.',['Và']='Vàli:BAAALAADCgYIBgAAAA==.',Wh='Whiskeyrick:BAAALAADCgcIBwAAAA==.',Wi='Wier:BAAALAAECgIIAgAAAA==.',Wo='Worthy:BAAALAADCgIIAwAAAA==.',Ze='Zemillion:BAAALAADCggIEQAAAA==.Zeynah:BAAALAADCggIDwAAAA==.',Zo='Zoedan:BAAALAADCggIGAAAAA==.Zophier:BAAALAADCgUIBAAAAA==.Zoéy:BAAALAAECgcIDgAAAA==.',Zu='Zube:BAAALAAECgQICQAAAA==.',Zy='Zydee:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end