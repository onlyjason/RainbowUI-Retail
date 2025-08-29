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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','DemonHunter-Havoc','Hunter-Survival','Shaman-Elemental','Monk-Windwalker','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Outlaw','Rogue-Assassination','Priest-Holy','Priest-Shadow','Mage-Arcane','Shaman-Restoration','Druid-Balance','DemonHunter-Vengeance','Paladin-Holy',}; local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acalirra:BAAALAADCggICAAAAA==.',Ad='Admaris:BAAALAADCggICAAAAA==.',Ag='Agni:BAAALAAFFAIIAgAAAA==.',Ah='Ahes:BAAALAADCgQIBAAAAA==.',Aj='Ajoblanco:BAAALAAECgMIBQAAAA==.',Ak='Akkadian:BAAALAAECgQIBAAAAA==.Ako:BAAALAADCgEIAQAAAA==.',Al='Alexá:BAAALAADCggICAABLAAECgIIBAABAAAAAA==.',Am='Amarillos:BAAALAAECgQIAgAAAA==.Amarillys:BAAALAAECggICAAAAA==.Ambrotos:BAAALAAECgIIAgAAAA==.Amnesty:BAAALAAECgYIBwAAAA==.Amo:BAAALAAECgEIAQAAAA==.',An='Anahlia:BAAALAAECgUIBwABLAAFFAMIBQACAGMSAA==.Androotate:BAAALAAECgYICAAAAA==.Angermeier:BAAALAAECgYIDAAAAA==.',Aq='Aquilia:BAAALAAECgMIAwAAAA==.',Ar='Archituethis:BAAALAADCggIDAAAAA==.Arowin:BAAALAAECgEIAQAAAA==.',As='Asclepieus:BAAALAAECgcIDgAAAA==.Assarah:BAAALAAECgYIDgAAAA==.Asystoli:BAAALAAECgYIDgAAAA==.',Au='Audry:BAAALAADCgYIBgAAAA==.Aulrelle:BAAALAADCgYIDwAAAA==.',Aw='Aw:BAACLAAFFIEFAAIDAAMIexrnAgAXAQADAAMIexrnAgAXAQAsAAQKgRYAAgMACAgoJGAFACoDAAMACAgoJGAFACoDAAAA.',Ax='Ax:BAEALAAFFAIIAgAAAA==.',Az='Azala:BAAALAAECgQIBAAAAA==.Azallea:BAAALAADCgcIBwAAAA==.Azjaqir:BAAALAADCgMIAwAAAA==.Azuro:BAABLAAECoEXAAIDAAgIQSBZCwDPAgADAAgIQSBZCwDPAgAAAA==.',Ba='Badpenný:BAAALAAECgMIAwAAAA==.Bakeon:BAAALAADCggICgAAAA==.Baldozhi:BAAALAAECgEIAQAAAA==.Banë:BAAALAAECgMIAwAAAA==.Barnacles:BAAALAAECgIIAgAAAA==.Batareva:BAAALAADCgEIAQAAAA==.Battlepug:BAAALAADCggIDwAAAA==.',Be='Beledros:BAAALAAECgcIEQAAAA==.Benson:BAAALAAECgMIAwAAAA==.',Bi='Bigslicknick:BAAALAADCgYICAAAAA==.Birblock:BAEALAAECgYIBgABLAAFFAUICQAEABYmAA==.',Bl='Blitzzen:BAAALAADCgUIBgAAAA==.Bloodscourge:BAAALAADCgUIBQAAAA==.Blyngblong:BAAALAAECgMIBgAAAA==.',Bo='Bobbo:BAAALAADCggIDwAAAA==.Boon:BAAALAAECgQIBwAAAA==.',Br='Braass:BAAALAADCgYIEQAAAA==.Brek:BAAALAADCggICAAAAA==.Brodobaggins:BAAALAAECggIDQAAAA==.Brutebuffalo:BAAALAAECgYICAAAAA==.Brïsingr:BAAALAADCgUIBQAAAA==.',Bu='Bubbleboi:BAAALAADCggIDgAAAA==.Bubblewrapp:BAAALAAECgcIDgAAAA==.Burgerguy:BAAALAAECgYICAAAAA==.Buublebutt:BAAALAADCgIIAgAAAA==.',['Bâ']='Bâra:BAAALAAECgQIBgAAAA==.',Ca='Captworgen:BAAALAADCgYIBgAAAA==.Carnal:BAAALAAECgIIAwAAAA==.Casini:BAAALAADCgEIAQAAAA==.Castro:BAAALAAECgMIBQAAAA==.',Ch='Chalix:BAAALAADCggIDQAAAA==.Chaosnipple:BAAALAAECgYIDAAAAA==.Cheapchi:BAAALAAECgYIDgAAAA==.Cheburashka:BAACLAAFFIEFAAIFAAMIySD5AQAiAQAFAAMIySD5AQAiAQAsAAQKgRcAAgUACAhRJaYBAGIDAAUACAhRJaYBAGIDAAAA.Chewymentos:BAAALAAECgQIBAAAAA==.Chonwang:BAAALAAECgIIAgAAAA==.Chunkymonkey:BAABLAAECoEXAAIGAAgINiFYBADLAgAGAAgINiFYBADLAgAAAA==.',Ci='Cidren:BAAALAAECgcIDwAAAA==.',Cl='Claudefrollo:BAAALAAECgMIBQAAAA==.',Co='Cod:BAAALAAECgcIDQAAAA==.Convict:BAAALAAECgYICAAAAA==.Cory:BAAALAAECgIIBAAAAA==.',Cr='Crimsa:BAAALAAECgYICAAAAA==.Cronwar:BAAALAADCgMIAwAAAA==.Cryogen:BAAALAAECgUICgAAAA==.',Cu='Cucaramanga:BAAALAAECgEIAQAAAA==.',Da='Daemon:BAAALAAECgYIEwAAAA==.Damocus:BAAALAAECgIIAgAAAA==.Darkessos:BAAALAAECgMIAwAAAA==.Darksouls:BAAALAADCggIDwAAAA==.',Db='Dblane:BAAALAADCgEIAQAAAA==.',De='Deelahn:BAAALAAECgMIAwAAAA==.Demonicchoas:BAABLAAECoEUAAQHAAgI+R52CQC0AgAHAAgI+R52CQC0AgAIAAIImwvpHQCQAAAJAAMIIxeCOACGAAAAAA==.Demontaters:BAAALAADCggICAABLAAECgcIDwABAAAAAA==.Denagorn:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.Devdaddy:BAAALAADCggICAAAAA==.Deyssana:BAAALAADCgYIBgAAAA==.',Dm='Dmcsparda:BAAALAADCgQIBAAAAA==.',Do='Dotorg:BAAALAADCggICQAAAA==.Dottorg:BAABLAAECoEdAAMHAAgIJR9xCwCUAgAHAAgIJR9xCwCUAgAIAAcIfgerDQBgAQAAAA==.',Dp='Dpssos:BAAALAADCgEIAQABLAAECgMIAwABAAAAAA==.',Dr='Dragon:BAAALAAECgQIBgAAAA==.Draiko:BAAALAADCggICAAAAA==.Druidgale:BAAALAAECgMIAwAAAA==.Druidless:BAAALAAECggIEgAAAA==.Drygth:BAAALAADCgcIBwAAAA==.',Du='Dubblebubble:BAAALAAECgIIAgAAAA==.Dubdub:BAAALAAECgcICgAAAA==.Durdle:BAAALAADCgYIBgAAAA==.',Dw='Dwarfmage:BAAALAADCgcIBwAAAA==.',Ei='Eisador:BAAALAADCgcICQAAAA==.',Eq='Equilibrio:BAAALAAECgYICQAAAA==.',Er='Erwinnd:BAAALAADCggIFQAAAA==.',Ez='Ezailas:BAAALAAECgIIBAAAAA==.Ezpzndaheezy:BAAALAAECgYIDAAAAA==.',Fa='Faelthas:BAAALAADCggICAAAAA==.Fallapart:BAAALAADCggICAAAAA==.Fangroot:BAAALAADCggICgAAAA==.',Fe='Felanxiety:BAAALAAECgMIAwAAAA==.Felawful:BAAALAAECgMIAwAAAA==.Felstrider:BAAALAAECgYICgAAAA==.Ferador:BAABLAAECoEXAAMKAAgIZx+8BwDmAgAKAAgIZx+8BwDmAgALAAIIJAmpSABHAAAAAA==.',Fi='Fistsphoyou:BAAALAADCgcIBwAAAA==.',Fr='Frigid:BAAALAADCgYIBgAAAA==.Froskur:BAAALAAECgQIBwAAAA==.Froze:BAAALAAECgQIBgAAAA==.',Fu='Furiossa:BAAALAADCgQIBAAAAA==.',Ga='Gabrian:BAAALAAECgMICAAAAA==.Gaerry:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Garpo:BAAALAAECgYICQAAAA==.Gateway:BAAALAADCggICAAAAA==.',Gh='Ghazi:BAAALAAECgEIAQAAAA==.Ghexan:BAAALAAECgMIBAAAAA==.Ghidorah:BAAALAAECgEIAQAAAA==.',Go='Goredrinker:BAABLAAECoEXAAIMAAgIoyXbAABZAwAMAAgIoyXbAABZAwAAAA==.',Gr='Grimreaper:BAABLAAECoEWAAINAAgIsR07AQDKAgANAAgIsR07AQDKAgAAAA==.Groag:BAAALAAECgQIBgAAAA==.',Gu='Gurion:BAAALAADCgQIBAAAAA==.Gurth:BAAALAADCgcICgABLAAECgUICgABAAAAAA==.',Ha='Haarp:BAAALAADCggIEAAAAA==.Hakü:BAAALAADCgEIAQAAAA==.Hammered:BAAALAADCgUIBQAAAA==.',He='Healbot:BAAALAAECgYICAAAAA==.Heydk:BAAALAAECgcIEwAAAA==.',Ho='Hoid:BAAALAAECgMIBAAAAA==.',Hu='Hugodog:BAAALAADCgMIAwAAAA==.Hushrage:BAAALAAECgcIEgAAAA==.',Ib='Iblisshaytan:BAAALAAECgYIDgABLAAECggIFgAOAPUYAA==.',Ig='Ignacious:BAAALAAECgYIDAAAAA==.',Il='Ilfirin:BAAALAAECgIIAgAAAA==.',Is='Ischia:BAABLAAECoEXAAMPAAgIyxLcFwDqAQAPAAgIyxLcFwDqAQAQAAEIdxEwTQA2AAAAAA==.Ishbaal:BAAALAAECgMIBQAAAA==.',Jc='Jch:BAACLAAFFIEFAAIKAAMIMxIwAgAGAQAKAAMIMxIwAgAGAQAsAAQKgRgAAgoACAiwItkFAAcDAAoACAiwItkFAAcDAAAA.',Je='Jenova:BAAALAAECgIIAgAAAA==.Jepwar:BAAALAADCggICAAAAA==.Jerpic:BAAALAAECgYIBwAAAA==.',Ji='Jinwoo:BAAALAAECggICAAAAA==.',Jo='Jollydk:BAAALAADCggICAAAAA==.Jolyne:BAAALAADCggIDgAAAA==.',Jr='Jrdn:BAAALAADCgcIDQAAAA==.',Ju='Jukkrit:BAAALAADCggICAAAAA==.Juniperz:BAAALAADCgMIAwAAAA==.',['Jü']='Jülles:BAAALAAECgMIAwAAAA==.',Ka='Kaelstro:BAAALAADCggIDQAAAA==.Kalmya:BAAALAAECgYICQAAAA==.Kazumah:BAAALAADCggIEAAAAA==.',Kh='Khronos:BAAALAADCggICAAAAA==.',Kl='Klunder:BAAALAAECgYICgAAAA==.',Kn='Kneeco:BAAALAAECgEIAQAAAA==.',Ko='Kostik:BAAALAAECgQIBQAAAA==.',Kr='Kridillis:BAAALAAECgcIEAAAAA==.',Kt='Ktang:BAAALAAECgUIBwAAAA==.',La='Laennaya:BAAALAAECgMIBwAAAA==.Lawls:BAAALAAECgQIBAAAAA==.Laylor:BAABLAAECoEWAAIRAAgIGCGsCgDdAgARAAgIGCGsCgDdAgAAAA==.',Li='Linaria:BAAALAADCgMIAwAAAA==.',Lo='Logañ:BAACLAAFFIEFAAISAAMIFx9DAQAiAQASAAMIFx9DAQAiAQAsAAQKgRcAAxIACAh4HtcIAIMCABIACAh4HtcIAIMCAAUABwjwFKMZANwBAAAA.Loko:BAABLAAECoEbAAITAAgISSDjBQDrAgATAAgISSDjBQDrAgAAAA==.',Lu='Luminise:BAAALAAECgEIAQAAAA==.Luxxus:BAAALAAECgcIEAAAAA==.',Ma='Maghul:BAAALAADCggICAABLAAECgYICgABAAAAAA==.Magrmage:BAAALAAECgIIAgAAAA==.Mantakore:BAAALAAECgUIBQAAAA==.Mappa:BAAALAADCggICgAAAA==.',Mc='Mcpoke:BAAALAADCgIIAQAAAA==.',Me='Mert:BAAALAADCgcIDQAAAA==.Mertric:BAAALAAECgcIDQAAAA==.',Mi='Mikayy:BAAALAAECgcIEAAAAA==.Milenko:BAAALAAECgYICwAAAA==.Mimonk:BAAALAADCgMIAwAAAA==.Minix:BAAALAAECgcICAAAAA==.Mintmentos:BAAALAADCgYIBgAAAA==.Misbehavin:BAAALAADCgQIBAAAAA==.Mishká:BAAALAADCgcIBwAAAA==.',Mo='Monkybusinez:BAAALAADCgEIAQABLAADCggIDgABAAAAAA==.Monstrous:BAAALAAFFAMIBAAAAA==.Moosebehavin:BAAALAADCgcIBwAAAA==.Mordecaii:BAAALAADCgQIBAAAAA==.Moyana:BAAALAADCgYIBgAAAA==.',Mt='Mthafknfreez:BAAALAAECgYIDQABLAAECggIFgAOAPUYAA==.',['Mè']='Mèatsweats:BAAALAAECgMIBAAAAA==.',Na='Narukami:BAAALAADCgIIAgAAAA==.',Ne='Negaduck:BAAALAADCggICAAAAA==.',No='Noku:BAAALAADCggIFgAAAA==.',Nu='Nusyl:BAAALAAECgYIBwAAAA==.',Ny='Nymeriã:BAAALAADCgcIDgAAAA==.',Ob='Obz:BAAALAAECgMIAwAAAA==.',Oh='Ohimesama:BAAALAAECgcIDwAAAA==.',Ok='Okamy:BAAALAAECgMIAwABLAAECgIIBAABAAAAAA==.',Ol='Oldmanyuu:BAAALAAECgYICgAAAA==.',Or='Orroth:BAAALAADCgcIBwAAAA==.',Oz='Ozelea:BAAALAADCggICQAAAA==.',Pe='Pedro:BAAALAADCgcICQAAAA==.Perphaleen:BAAALAAECgMIAwAAAA==.',Ph='Phdndamage:BAAALAAECgUIBQAAAA==.Phoinix:BAABLAAECoEXAAIPAAgIOhXvEwATAgAPAAgIOhXvEwATAgAAAA==.Phyllis:BAAALAAECgIIBAAAAA==.',Pi='Pickel:BAAALAAECggIDgABLAAECggIDgABAAAAAA==.Picklerik:BAAALAAECgcIEAAAAA==.',Pl='Ploxis:BAACLAAFFIEFAAIUAAMIIxV+AADvAAAUAAMIIxV+AADvAAAsAAQKgRcAAhQACAgtJOgAADgDABQACAgtJOgAADgDAAAA.',Po='Poptart:BAAALAAECgMIAwAAAA==.Porthub:BAAALAAECgIIAwAAAA==.Power:BAAALAADCgMIAwAAAA==.',Pr='Premiumferal:BAABLAAECoEXAAIOAAgIVhzHCQCLAgAOAAgIVhzHCQCLAgAAAA==.Prevoker:BAAALAADCgQIBAAAAA==.Primecarry:BAACLAAFFIEFAAIVAAMIXh84AQAuAQAVAAMIXh84AQAuAQAsAAQKgRcAAhUACAjSIwYBAB0DABUACAjSIwYBAB0DAAAA.Primemonster:BAAALAAECgUIBwABLAAFFAMIBQAVAF4fAA==.',Pu='Puripuri:BAAALAADCggIDgAAAA==.Putmeincoach:BAAALAADCgcIDAAAAA==.',['Pô']='Pôkesmot:BAAALAAECgYICwAAAA==.',Ra='Ragark:BAAALAADCgEIAQAAAA==.Randioh:BAAALAAECgMIAwAAAA==.Rassputen:BAABLAAECoEUAAIMAAgIgxlcBgAcAgAMAAgIgxlcBgAcAgAAAA==.Rayvic:BAAALAADCgcIBwAAAA==.',Re='Rebounding:BAAALAAECgQICQAAAA==.Redjive:BAAALAAECgMIAwAAAA==.Regi:BAAALAAECgYIDAAAAA==.Reliri:BAAALAADCgcICgAAAA==.Remeowii:BAAALAAECgEIAQAAAA==.',Ri='Rider:BAAALAAECgYIBgAAAA==.',Ro='Robby:BAAALAADCgIIAgAAAA==.Roguen:BAABLAAECoEWAAIOAAgI9RiYCgB6AgAOAAgI9RiYCgB6AgAAAA==.Romirin:BAAALAAECgMIBwAAAA==.Ronin:BAAALAAECgYICgAAAA==.Rootbeam:BAAALAAECgMIAwAAAA==.Rotan:BAAALAAECgIIAgAAAA==.Roulduke:BAAALAAECgIIBAAAAA==.Rowgoku:BAAALAADCgQIBAAAAA==.',Sa='Sacredmentos:BAAALAADCgcIBwAAAA==.Sammybeans:BAAALAAECgMIAwAAAA==.Sammybich:BAAALAADCgcICwAAAA==.Sanai:BAAALAADCgcICwAAAA==.Saymaro:BAAALAAECgEIAQAAAA==.',Sc='Scruffmcgruf:BAAALAAECgMIAwAAAA==.',Se='Sean:BAAALAADCgIIAgAAAA==.Secrtservice:BAAALAAECgYIEAAAAA==.Selrahc:BAAALAAECgUICgAAAA==.Seongwa:BAAALAADCgQIBQAAAA==.Sephie:BAAALAAECgEIAQAAAA==.Sephyrin:BAAALAADCgcIBwAAAA==.',Sg='Sgtslappy:BAAALAAECgMIBAAAAA==.',Sh='Shadyhunter:BAAALAADCggIEAAAAA==.Shasa:BAAALAAECggIEgAAAA==.Shatteredsky:BAAALAAECgQIBgAAAA==.Sheroko:BAAALAADCgcIBwAAAA==.Shøcktherapy:BAAALAADCgUIBQAAAA==.',Si='Silzo:BAAALAAECgMIAwAAAA==.Sindorella:BAAALAAECgcIDgAAAA==.Sisterwife:BAAALAAECgIIBAAAAA==.',Sk='Skizx:BAAALAADCgEIAQAAAA==.Skullpacker:BAAALAADCgYIBgAAAA==.Skunkpaw:BAAALAAECgEIAQAAAA==.Skysong:BAACLAAFFIEFAAICAAMIYxIcAwD1AAACAAMIYxIcAwD1AAAsAAQKgRcAAgIACAiHIXgFAOICAAIACAiHIXgFAOICAAAA.',Sl='Slashedeye:BAAALAAECgYIDQAAAA==.',Sn='Snowynn:BAAALAADCgIIAgAAAA==.Snuper:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.Snurglesnop:BAAALAADCgcIDQAAAA==.',So='Sofii:BAAALAAECgMIAwAAAA==.Solheim:BAAALAAECgMIAwAAAA==.Souffle:BAAALAADCgYIBgAAAA==.',Sp='Spookypink:BAAALAAECgQIBgAAAA==.',Sq='Squeaak:BAAALAAECgIIAgAAAA==.',Sr='Srirachajane:BAAALAAECgMIAwAAAA==.',St='Stormcoast:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Strathin:BAAALAAECgYIDgAAAA==.Strathz:BAAALAADCggICAAAAA==.',Su='Suggadeath:BAAALAAECgcIEAAAAA==.Superdonkey:BAAALAAECgMIBQABLAAECggIFwAGADYhAA==.Sushi:BAAALAADCggIDgAAAA==.',Sy='Sylatis:BAECLAAFFIEJAAIEAAUIFiYEAAAvAgAEAAUIFiYEAAAvAgAsAAQKgRkAAgQACAixJg8AAJIDAAQACAixJg8AAJIDAAAA.Synvert:BAAALAAECgIIAgAAAA==.',['Sø']='Sølidus:BAAALAAECgQIBwABLAAFFAMIBQARAOoNAA==.',Ta='Tanothos:BAAALAADCgYICAAAAA==.Tayylor:BAAALAAECgEIAQAAAA==.',Th='Thabk:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.Thelenin:BAAALAADCgEIAQAAAA==.Theshortbuss:BAAALAAECgIIAgAAAA==.Thormond:BAAALAADCggIEwAAAA==.Thurmund:BAAALAADCggIDQAAAA==.',Ti='Tiddybear:BAAALAADCgIIAgAAAA==.',To='Toastay:BAAALAADCgcIDgAAAA==.Toastz:BAAALAAECgIIAgAAAA==.Toilet:BAAALAAECggICQAAAA==.Toolthirdeye:BAAALAADCgcIBwAAAA==.',Tr='Treecoast:BAAALAAECgYIDAAAAA==.Treediddy:BAAALAAECggIDgAAAA==.Trojen:BAAALAAECgYIDwAAAA==.',Um='Umadh:BAACLAAFFIEFAAIDAAMIviSVAQBIAQADAAMIviSVAQBIAQAsAAQKgRgAAgMACAhNJiQBAHsDAAMACAhNJiQBAHsDAAAA.',Un='Unphallusble:BAAALAAECgIIAgAAAA==.',Va='Vantress:BAAALAAECgQIBgAAAA==.Vashtí:BAAALAADCgYIBgAAAA==.',Ve='Vengened:BAAALAAECgcIEAAAAA==.Vergessen:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Vi='Vid:BAAALAADCggICwAAAA==.Vilous:BAAALAAECgIIAgAAAA==.',Vo='Volaris:BAAALAADCgcIDAABLAAECgEIAQABAAAAAA==.Voltecjr:BAAALAADCggIEQAAAA==.',Vr='Vraax:BAABLAAECoEWAAMLAAgIhRP7EwDeAQALAAgIhRP7EwDeAQAKAAQIiwf6TADJAAAAAA==.',Vy='Vyandonys:BAAALAAECgMIBAAAAA==.',Wa='Warriors:BAAALAADCgUIBQAAAA==.Wasling:BAAALAAECggIDwAAAA==.',We='Wesjin:BAAALAAECgQIBgAAAA==.',Wi='Wildarms:BAAALAAECggIEQAAAA==.',Wo='Wobbles:BAAALAADCggIFgAAAA==.Wobblez:BAAALAAECgcIEQAAAA==.Wobzster:BAAALAAECgEIAQAAAA==.Wooglone:BAAALAAECgYIBgAAAA==.',Wu='Wurzagnipple:BAAALAADCgcIDgAAAA==.',Wy='Wyndia:BAAALAAECgIIAgAAAA==.',Xe='Xenophontes:BAACLAAFFIEFAAIRAAMI6g0TBgDcAAARAAMI6g0TBgDcAAAsAAQKgRcAAhEACAiVHtgOAK0CABEACAiVHtgOAK0CAAAA.',Xi='Xihuang:BAAALAAECgYIDgABLAAECggIFgAOAPUYAA==.Xiia:BAAALAAECgMIBQAAAA==.',Xo='Xouo:BAAALAAFFAIIBAAAAA==.Xouu:BAAALAAECggICwABLAAFFAIIBAABAAAAAA==.',Xx='Xxuu:BAAALAAECggIAgABLAAFFAIIBAABAAAAAA==.',Xz='Xzanen:BAAALAAECgcIDAAAAA==.',Ya='Yaoguai:BAAALAAECgMIAwAAAA==.Yasei:BAAALAAECgYICQAAAA==.',Za='Zammboomafoo:BAAALAAECgQICgAAAA==.Zanian:BAAALAADCgcICQAAAA==.Zarthei:BAAALAADCgcICwAAAA==.Zarthie:BAAALAAECgIIAgAAAA==.',Ze='Zephon:BAAALAADCgYIBgAAAA==.',Zo='Zotiel:BAAALAADCgIIAgABLAAECgQIBAABAAAAAA==.Zoêy:BAAALAADCggICAAAAA==.',Zu='Zukster:BAAALAAECgMIBAAAAA==.Zuphinne:BAAALAAECgEIAQAAAA==.',Zy='Zynatra:BAAALAAECgcICQAAAA==.Zyncoolmint:BAAALAADCggICgABLAAECgMIAwABAAAAAA==.Zynisch:BAAALAAECgEIAQAAAA==.',['Ða']='Ðarkspartan:BAAALAADCgcIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end