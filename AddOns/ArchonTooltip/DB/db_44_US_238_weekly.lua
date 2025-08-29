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
 local lookup = {'Shaman-Elemental','Unknown-Unknown','DeathKnight-Frost','Priest-Shadow','Rogue-Assassination','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy',}; local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aayrawn:BAAALAAECgIIAgAAAA==.',Ac='Aceofplagues:BAAALAAECgYICAAAAA==.',Al='Alextros:BAAALAAECgYIDQAAAA==.',Am='Amaranthe:BAAALAADCgUIBQAAAA==.Amrax:BAAALAAECgQIBwAAAA==.',An='Antijastran:BAAALAAECgMIBAAAAA==.',Aq='Aquabat:BAAALAAECgYICQAAAA==.',Az='Azgaroth:BAAALAADCgcIBwAAAA==.Azråel:BAAALAADCgIIAgAAAA==.',['Aí']='Aí:BAAALAADCggICAAAAA==.',Ba='Bartab:BAAALAAECgUICAAAAA==.Bastadi:BAABLAAECoEXAAIBAAgI4yT7AwAtAwABAAgI4yT7AwAtAwAAAA==.',Be='Bearemy:BAAALAAECgIIAgAAAA==.',Bi='Bike:BAAALAADCgQIBAAAAA==.',Bl='Blueeyesdrag:BAAALAAECgEIAQAAAA==.',Bo='Boxes:BAAALAAECgEIAQABLAAECgcIDAACAAAAAA==.',Br='Brando:BAAALAAECgMIBwAAAA==.Braully:BAAALAADCggICAAAAA==.Brewzlee:BAAALAADCgcIBwAAAA==.Brëtski:BAAALAAECgIIAgAAAA==.',Bu='Burnah:BAAALAAECgIIAgAAAA==.Burph:BAAALAADCggICAAAAA==.Buttonsmash:BAAALAAECggIEwAAAA==.Buzzkill:BAAALAAECgEIAQAAAA==.',Ca='Cancerousqt:BAAALAADCgUIBQAAAA==.Carmius:BAAALAADCgYIBgAAAA==.',Cc='Ccane:BAAALAAECgMIAwAAAA==.',Ce='Celinn:BAAALAAECgMICAAAAA==.',Ch='Chawshaft:BAAALAAECgUICQAAAA==.Childish:BAAALAAECgMIAwAAAA==.Chiling:BAAALAADCgQIAwAAAA==.Chimalma:BAAALAAECgQIBAAAAA==.Chrishanson:BAABLAAECoEWAAIDAAgIVCIMCAD0AgADAAgIVCIMCAD0AgAAAA==.',Ci='Cilantra:BAAALAAECgEIAQAAAA==.',Co='Cobi:BAAALAAECgQIBwAAAA==.Combo:BAAALAAECggIEwAAAA==.',Cr='Crates:BAAALAAECgcIDAAAAA==.',Cu='Curonconagua:BAAALAAECgIIAgAAAA==.',Cy='Cypherrellik:BAAALAAECgYICQAAAA==.',Da='Daigle:BAAALAAECgMIBQAAAA==.Damues:BAAALAAECgIIAgAAAA==.Darkepic:BAAALAADCgcIBwAAAA==.Darkling:BAAALAAECgIIAgAAAA==.',De='Deeznutsdead:BAAALAAECgQIBAAAAA==.Demonicz:BAAALAAECgcIDQABLAAECggIDgACAAAAAA==.Denaric:BAAALAAECgYICwAAAA==.Derty:BAAALAAECgcIEQAAAA==.Dethsoul:BAAALAAECgYIDQAAAA==.',Di='Dixonmybut:BAAALAADCgIIAgAAAA==.',Dr='Dragonborn:BAAALAADCgEIAQAAAA==.Dragondznuts:BAAALAAECgMIBAABLAAECggIEwACAAAAAA==.Draxtar:BAAALAADCgcIBwAAAA==.Dreamblast:BAAALAADCggICAAAAA==.Druzizzle:BAAALAADCgcIBwAAAA==.',Du='Duckling:BAAALAADCgcIDQABLAADCggICAACAAAAAA==.',Ea='Earwego:BAAALAAECgYICQAAAA==.',Ei='Eisla:BAAALAAECgYIDQAAAA==.',El='Elkshamen:BAAALAAECgIIAgABLAAECgYICQACAAAAAA==.Elodi:BAAALAAECgcIDAAAAA==.',Em='Emylia:BAAALAAECggIDQAAAA==.',Er='Eresdelor:BAAALAAECgQIBwAAAA==.Errepal:BAAALAAECgYICQAAAA==.',Es='Espionage:BAAALAAECgYICQAAAA==.',Ev='Evoktor:BAAALAADCgcIDQAAAA==.',Fa='Faccasdeath:BAAALAADCgcIDQAAAA==.Faerless:BAAALAAECgEIAgAAAA==.',Fi='Fizzypop:BAAALAAECgQIBAAAAA==.',Fl='Flap:BAAALAADCggICAAAAA==.',Fo='Foxu:BAAALAADCgcIBwAAAA==.Fozzi:BAAALAAECgcIDAAAAA==.',Fr='Frostyburn:BAAALAADCgcIBwAAAA==.',Ga='Garrosh:BAAALAAECgYICQAAAA==.',Ge='Geörge:BAABLAAECoEaAAIEAAgI8RsHDACEAgAEAAgI8RsHDACEAgAAAA==.',Go='Goja:BAAALAAECgMIBAAAAA==.Goosey:BAAALAAECgcIDQAAAA==.',Gr='Grotlek:BAAALAAECgMIBgAAAA==.',Ha='Haedrath:BAAALAAECgYICgAAAA==.Halcozaraki:BAAALAAECgIIAgAAAA==.Hark:BAAALAAECgMIBgAAAA==.Hatred:BAAALAAECgYICQAAAA==.Hawgbawl:BAAALAADCggICAAAAA==.',He='Hellequin:BAABLAAECoEXAAIFAAgIUCFzAwAQAwAFAAgIUCFzAwAQAwAAAA==.Heyitsmegoku:BAAALAADCggIFQAAAA==.',Hi='Hidenseekpro:BAAALAAECgMIAwAAAA==.',Ho='Hollypriest:BAAALAADCggIBwAAAA==.',In='Infoxticated:BAAALAAECgEIAQABLAAECgMIAwACAAAAAA==.',Ir='Irely:BAAALAAECgQIBgAAAA==.',Jo='Joanoforc:BAAALAAECgQIBwAAAA==.Joshallen:BAAALAADCgcICwAAAA==.',Ka='Kano:BAAALAAECgQIBgAAAA==.Kawada:BAAALAAECgEIAgAAAA==.',Ki='Kiro:BAAALAADCggICAAAAA==.',Kr='Kreishi:BAAALAADCgYIBgAAAA==.Krisanthemum:BAAALAAECgUIBgAAAA==.',Ku='Kustaa:BAAALAAECgQIBwAAAA==.',La='Laissen:BAAALAADCgQIBQAAAA==.Lattemocha:BAAALAAECgQIBwAAAA==.',Le='Letum:BAAALAADCgcIBwAAAA==.Levar:BAAALAADCgYIBgAAAA==.',Li='Limbbutcher:BAAALAAECgIIAgAAAA==.',Lo='Locket:BAAALAADCggIDwAAAA==.Lockofwar:BAAALAAECgEIAQAAAA==.',Lu='Lunastra:BAEALAADCgIIBAABLAAECgYIEAACAAAAAA==.Lurinoraylda:BAAALAADCgYIBwAAAA==.',Ly='Lyiann:BAAALAADCggICAAAAA==.',Ma='Mafi:BAAALAAECgIIAgAAAA==.Magron:BAAALAADCgIIAgAAAA==.Magsdk:BAABLAAECoEUAAIDAAgI/BtiDAC5AgADAAgI/BtiDAC5AgAAAA==.Mantussy:BAAALAAECgYIDwAAAA==.',Me='Meddicus:BAAALAAECgcIDQAAAA==.Mediocrates:BAAALAAECgYICQAAAA==.Mehoul:BAAALAADCgMIAwAAAA==.Mewtwô:BAAALAAECgMIAwAAAA==.',Mi='Millionaire:BAAALAADCggIEwAAAA==.Mindrocker:BAAALAADCgMIAwAAAA==.',Mo='Mojomittens:BAAALAADCggIDgAAAA==.Monkontilt:BAAALAAECgQIBAAAAA==.Monstermime:BAAALAAECgIIAgAAAA==.Monstrosity:BAAALAADCgYIAQAAAA==.Moonmittens:BAAALAAECgYICQAAAA==.Moosetracks:BAAALAAECgYICQAAAA==.',My='Mywarrior:BAAALAAECgQIBAAAAA==.',Na='Napkuntt:BAAALAAECgEIAQAAAA==.Nardil:BAAALAADCgIIAwABLAAECgMIBQACAAAAAA==.Nathanael:BAAALAAECggIDAAAAA==.Nazara:BAEALAAECgYIEAAAAA==.',Ni='Nikodemos:BAAALAAFFAIIBAAAAQ==.',Ny='Nyssa:BAAALAAECgEIAQAAAA==.Nyxana:BAAALAADCggIDwAAAA==.',Ol='Olestankyleg:BAAALAAECgQIBAAAAA==.',Ox='Oxheart:BAAALAAECgYICwAAAA==.',Oz='Ozzmosis:BAAALAADCgcIBwAAAA==.',Pa='Packages:BAAALAADCggIDwABLAAECgcIDAACAAAAAA==.Pandaari:BAAALAADCgYIBgAAAA==.',Pe='Penguinadin:BAAALAADCggICAABLAADCggIDgACAAAAAA==.',Ph='Philip:BAAALAAECgcIDgAAAA==.',Pi='Picklemån:BAAALAAECgEIAQAAAA==.',Pr='Prepaid:BAAALAADCgQIBAAAAA==.',Py='Pyrrah:BAAALAAECgYICQAAAA==.Pyrria:BAAALAADCgMIAwABLAAECgYICQACAAAAAA==.',Ra='Ract:BAAALAAECgQIBAAAAA==.Rajamana:BAAALAAECgMIBgAAAA==.Raymoondoe:BAAALAAECgUIBgAAAA==.',Re='Reginrune:BAAALAADCggIEAAAAA==.Reknob:BAAALAADCgYIBgABLAAECgQIBwACAAAAAA==.',Sa='Sahomi:BAAALAAECgYIBwAAAA==.Satrina:BAAALAAECgUIBQAAAA==.Savvy:BAAALAAECgIIAgAAAA==.',Sc='Schlavens:BAAALAADCgYIBgABLAAECggIEwACAAAAAA==.',Sh='Shamander:BAAALAAECggIEQAAAA==.Shandrisa:BAAALAAECgcIEAAAAA==.',Sl='Slapahoe:BAAALAAECgcICwAAAA==.',So='Somazugzug:BAAALAAECgYICQAAAA==.',St='Starfleet:BAAALAADCggIDgAAAA==.Stormydamsel:BAAALAAECgMIAwAAAA==.Stormzyy:BAAALAAECgIIAgABLAAECgYIDQACAAAAAA==.Stupidmage:BAAALAAECgYICQAAAA==.',Sy='Syrillia:BAAALAAECgEIAQAAAA==.',Ta='Taintbubble:BAAALAAECgYIBgAAAA==.Taliã:BAAALAADCgIIAgAAAA==.Tankadins:BAAALAAECgcIDwABLAAECggIDgACAAAAAA==.Tarnished:BAAALAADCggICwAAAA==.Tarquitus:BAABLAAECoEUAAMGAAcIMR5aCQDJAQAHAAcIhRpvIQD1AQAGAAYIAxxaCQDJAQAAAA==.Taurenhunter:BAAALAADCgUIBQAAAA==.',Te='Teamwrkx:BAAALAADCggICAAAAA==.',Th='Thajuan:BAAALAAECgIIAwAAAA==.Thedegz:BAAALAADCggICgAAAA==.Thoni:BAAALAAECgQIBgAAAA==.',Ti='Tissue:BAAALAAECgEIAQAAAA==.',Tr='Treeadin:BAAALAAECgQIBwAAAA==.Trollcula:BAAALAAECgYICQAAAA==.Truthwithin:BAAALAADCgYICwAAAA==.',Ts='Tsarrubus:BAAALAAECgYICQAAAA==.',Tw='Twingert:BAAALAAECgYICQAAAA==.',Ul='Ulghar:BAAALAAECggIEgAAAA==.',Un='Unfauithful:BAAALAAECggIAgABLAAECggIEwACAAAAAA==.',Va='Vangpao:BAAALAAECgYICQAAAA==.Varmyr:BAAALAADCgMIAwAAAA==.',Ve='Vengefulcry:BAAALAADCggIEAAAAA==.Vengefulfury:BAAALAADCggIEwAAAA==.Vengefül:BAAALAAECgEIAQAAAA==.',Vo='Voidsong:BAAALAADCggICgAAAA==.',Vy='Vykare:BAAALAADCgcIBwAAAA==.',Wa='Warkinn:BAAALAADCgcIBwAAAA==.Waterblaster:BAAALAAECgQICAAAAA==.',Wh='Whyamiapalli:BAAALAAECgMIBAAAAA==.',Wi='Wiqui:BAAALAAECgQICQAAAA==.',Wo='Wolfadin:BAAALAAECgMIBQAAAA==.',Wr='Wrathwaltz:BAAALAAECgIIAgAAAA==.',Wu='Wuhshake:BAAALAAECgQIBwAAAA==.',Xe='Xenophics:BAABLAAECoEZAAMIAAcIFRQGMACkAQAIAAcIFRQGMACkAQAJAAMIwAcVKQCQAAAAAA==.',Yu='Yudri:BAAALAADCggICAAAAA==.',Za='Zacktos:BAAALAADCgcICAABLAAECgYIDQACAAAAAA==.Zapetio:BAAALAADCgYIBgAAAA==.Zarranora:BAAALAAECgEIAQAAAA==.Zarrin:BAAALAADCgQIBAAAAA==.',Ze='Zenshin:BAAALAAECgEIAQAAAA==.Zentaur:BAAALAAECgIIAgAAAA==.',Zi='Zitfrlt:BAAALAAECgYIDQAAAA==.',['Øz']='Øzzÿ:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end