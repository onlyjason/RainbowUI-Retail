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
 local lookup = {'Monk-Windwalker','Evoker-Devastation','Unknown-Unknown','Hunter-Marksmanship','Paladin-Retribution','Rogue-Outlaw','Shaman-Enhancement','Warlock-Destruction','Hunter-BeastMastery','Warlock-Demonology','Evoker-Augmentation','Druid-Balance','Druid-Restoration','Druid-Feral','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','DemonHunter-Vengeance','Warlock-Affliction','Mage-Frost','Warrior-Fury','Warrior-Protection','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost',}; local provider = {region='US',realm='Stormreaver',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaragonchi:BAAALAAECgcIEwAAAA==.Aaragondelta:BAAALAADCgcICwAAAA==.Aaragondeus:BAAALAADCgcICAAAAA==.Aaragonium:BAAALAAECgIIAwABLAAFFAUIBgABAOoPAA==.Aaragonius:BAAALAADCggIDgAAAA==.Aaragonneo:BAACLAAFFIEGAAIBAAUI6g9KAACoAQABAAUI6g9KAACoAQAsAAQKgRgAAgEACAi+JWYAAHgDAAEACAi+JWYAAHgDAAAA.Aaragontheta:BAAALAADCgUIAwABLAAFFAUIBgABAOoPAA==.Aaragonxeta:BAAALAADCggICAAAAA==.',Ac='Ackreseth:BAABLAAECoEUAAICAAgINRcwDQA6AgACAAgINRcwDQA6AgAAAA==.Acrimony:BAAALAAECgYICQAAAA==.',Ad='Adannis:BAAALAAECgMIBAAAAA==.Adeal:BAAALAADCggICwAAAA==.Adornusm:BAAALAAECgYIDAAAAA==.Adrelia:BAAALAAECgYICgAAAA==.',Ae='Aeradeth:BAAALAAECgcIEAAAAA==.',Ai='Aiee:BAAALAADCgcIBwAAAA==.',Al='Alariele:BAAALAAECgIIAgAAAA==.Alcrenz:BAAALAAECgYICgAAAA==.Aleystra:BAAALAAECgMIAwAAAA==.Alisari:BAAALAAECggIEgAAAA==.',Am='Amethystmoon:BAAALAADCgcICgABLAADCgcICgADAAAAAA==.Amourn:BAAALAADCggIEQAAAA==.',An='Analrek:BAAALAAECgcIDQAAAA==.',Ap='Apoluss:BAAALAAECgEIAgAAAA==.Applesnapple:BAAALAADCggIFgAAAA==.',Ar='Arc:BAAALAAECgMIAwAAAA==.Arculus:BAAALAAECgMIBAAAAA==.Ardalin:BAAALAAECgEIAQAAAA==.Arelais:BAAALAAECgMIBQAAAA==.Arghast:BAAALAADCgcIBwABLAAECgUICAADAAAAAA==.Arkhan:BAAALAAECgcICwAAAA==.Arock:BAAALAADCgEIAQAAAA==.Arrithion:BAAALAAECgMIBgAAAA==.Arrowdaone:BAAALAAECgEIAQAAAA==.Arthaz:BAAALAAECgcIEwABLAAECggIGAACAAckAA==.',As='Asgorath:BAAALAADCgMIAwAAAA==.Astheric:BAAALAADCgcIBwAAAA==.Asyela:BAAALAADCgQIBwABLAAECgMIAwADAAAAAA==.',At='Atexnogaraa:BAAALAADCggIEAABLAAFFAUIBgABAOoPAA==.',Av='Averelles:BAAALAAECgUIBgAAAA==.',Ax='Axtin:BAAALAAFFAIIAgAAAA==.',Az='Azsharaa:BAAALAAECgMIBAAAAA==.',Ba='Baethoven:BAAALAAECgMIAwAAAA==.Baldo:BAAALAAECgEIAQAAAA==.Ballzout:BAAALAAECgIIAgABLAAECgcIDAADAAAAAA==.Bandages:BAAALAADCgcICwAAAA==.Bashm:BAAALAAECgMIAwABLAAECgcIDwADAAAAAA==.Baths:BAAALAADCgIIAgAAAA==.',Be='Beens:BAABLAAECoEUAAIEAAgI3SRxAQBGAwAEAAgI3SRxAQBGAwAAAA==.Beers:BAAALAADCgQIBgABLAAECgUICAADAAAAAA==.Beewitched:BAAALAADCgcICgAAAA==.Bellator:BAAALAAECgUIBgAAAA==.Belowzerolol:BAACLAAFFIEJAAIFAAYIQiMEAACJAgAFAAYIQiMEAACJAgAsAAQKgRYAAgUACAjoJigAAKMDAAUACAjoJigAAKMDAAAA.Bengrimm:BAAALAAECgYIBgAAAA==.Benysdeath:BAAALAAECgYIDAAAAA==.Beornn:BAAALAADCgQIBAAAAA==.Bertha:BAAALAAECgUICAAAAA==.',Bh='Bhabayaga:BAAALAAECgcIEwAAAA==.',Bi='Billbigtotem:BAAALAAECgQICAAAAA==.Billofrights:BAAALAADCggIDgAAAA==.',Bl='Blademaw:BAAALAADCggICAAAAA==.',Bm='Bmj:BAAALAAECgMIAwAAAA==.',Bo='Boomboompow:BAAALAADCgQIBAAAAA==.Boopin:BAAALAADCgQIBAAAAA==.Bovinestorm:BAAALAAECgMIAwAAAA==.',Br='Brewcognetus:BAAALAAECgYICQAAAA==.Bribird:BAAALAAECgYIDAAAAA==.Brocc:BAAALAAECgMIAwABLAAFFAYICQAFAEIjAA==.Bronsoni:BAAALAADCgEIAQAAAA==.Brunax:BAAALAADCgYIBgAAAA==.',Bu='Buckets:BAAALAADCgQIBAAAAA==.Buffoutlaw:BAAALAAECgcIEwABLAAFFAYICQAGAMcQAA==.Bulaklak:BAAALAADCgYIBwAAAA==.Bulliath:BAAALAADCgUIBQAAAA==.Bullshiv:BAAALAADCggICAAAAA==.Bully:BAAALAADCgcIBwAAAA==.Bullzzeye:BAAALAAECgcIEAAAAA==.',By='Byshop:BAAALAAECgMIBAAAAA==.',['Bë']='Bëar:BAAALAAECgIIAgABLAAECggIHAAHADAhAA==.',Ca='Cabe:BAAALAAECgYICgAAAA==.Caddywaumpus:BAAALAADCggICAAAAA==.Caddywhompus:BAAALAADCgMIAwAAAA==.Calkoon:BAAALAADCgMIAwAAAA==.Canwin:BAAALAAECgcIEwABLAAFFAYICQAIAIAYAA==.Carnageev:BAAALAAECgMIAwAAAA==.Caylalle:BAAALAAECgUIBgABLAAFFAIIAgADAAAAAA==.',Ce='Celthrinor:BAAALAADCgEIAQAAAA==.Cerevistra:BAAALAAECgMIAwAAAA==.',Ch='Chalybs:BAAALAADCgMIAwAAAA==.Charlitos:BAAALAAECgMIBAAAAA==.Chilex:BAAALAADCgYIBwABLAAECgIIAgADAAAAAA==.Chokyo:BAAALAADCggIDwAAAA==.Chulain:BAAALAADCggIDwAAAA==.Chunk:BAAALAAECgcIEgAAAA==.',Ci='Cifer:BAAALAAECgYICgAAAA==.',Cl='Claritinclr:BAAALAAECgYIDgAAAA==.',Co='Comatoast:BAAALAAECgYICgAAAA==.Cornh:BAABLAAECoEWAAMEAAgIPSKUCACWAgAEAAcIJyGUCACWAgAJAAgIqhmaEwBGAgAAAA==.Corns:BAAALAAECgcIEwAAAA==.Covenants:BAAALAAECgEIAQAAAA==.',Cr='Craptastic:BAAALAAECgMIAwAAAA==.Cripolious:BAAALAADCggICAAAAA==.Crut:BAAALAADCggIDgAAAA==.',Da='Dameosh:BAAALAAECgYIDAAAAA==.Damonic:BAAALAAECgQIBAABLAAECgcIDAADAAAAAA==.Danas:BAAALAADCgYICwAAAA==.Davicurn:BAAALAADCggIEwAAAA==.Daymión:BAAALAAECgIIAgAAAA==.',De='Deadywaumpus:BAAALAAECgcIEAAAAA==.Deathkong:BAAALAADCgIIAgAAAA==.Deebstatus:BAAALAADCggIEQAAAA==.Deidre:BAAALAAECgMIAwAAAA==.Demonicpeon:BAAALAAECgMIAwAAAA==.Demonkillua:BAAALAADCggIHwAAAA==.Demonnzo:BAAALAADCgYICQAAAA==.Deyalos:BAAALAAECgEIAQAAAA==.Deylicious:BAAALAADCggIDwABLAAFFAYICQAJAE8bAA==.Dezoka:BAAALAADCgUIBQAAAA==.',Dh='Dhani:BAAALAAECgMIAwAAAA==.',Di='Dietdrpibb:BAAALAADCgYIDgABLAADCgYIEAADAAAAAA==.Dijoe:BAAALAAECgMIAwAAAA==.Diminuere:BAAALAAECgMIAwAAAA==.Dippndotz:BAABLAAECoEWAAMIAAgI8xYfEwAtAgAIAAgIGRUfEwAtAgAKAAcIDQ65FABhAQAAAA==.Discern:BAAALAADCgYICQAAAA==.Dissection:BAAALAADCgYIBgABLAAECgUICAADAAAAAA==.',Do='Dogwalterll:BAAALAAECgQIBQAAAA==.Dohvahkiin:BAAALAADCgcIEQAAAA==.Doinkerz:BAAALAAECgYIBgAAAA==.Dontlosmë:BAAALAADCgYIBgAAAA==.Dotsafrenic:BAAALAAECgcIDwAAAA==.Doublebubble:BAAALAAECgMIAwAAAA==.',Dr='Draaragon:BAAALAADCggIEAABLAAFFAUIBgABAOoPAA==.Dragnbofades:BAAALAADCggIDwAAAA==.Dragondyz:BAABLAAECoEYAAMCAAgIByTiBADxAgACAAgIxSHiBADxAgALAAMIZSXlAwBRAQAAAA==.Dragonlyfans:BAAALAAECgcIEwABLAAFFAYICQAMAPoRAA==.Draltolkal:BAAALAADCgQIBAAAAA==.Drazi:BAAALAAECgMIAwAAAA==.Dreadlocksz:BAAALAADCgcIBwAAAA==.Dreteraktwo:BAAALAAECggIEwAAAA==.Drive:BAAALAAECgEIAQAAAA==.',Du='Dubby:BAAALAAECgYIDwAAAA==.',Ea='Eardi:BAAALAAECgYICwAAAA==.Earthpounder:BAAALAAECgEIAQAAAA==.',Ee='Eebo:BAAALAAECgEIAgAAAA==.',El='Elphabah:BAAALAAECgYIDwAAAA==.',Em='Emilil:BAAALAADCgcICgAAAA==.Emp:BAAALAAECgEIAQAAAA==.',En='Enlight:BAAALAADCgUIBwAAAA==.',Er='Eralynea:BAAALAADCgcICAAAAA==.',Es='Escapades:BAAALAAECgMIAwAAAA==.',Ex='Exias:BAAALAADCggIFwAAAA==.',Ey='Eyejuice:BAAALAADCgMIAwAAAA==.',Fa='Farming:BAAALAAECgIIAgAAAA==.Fartman:BAAALAADCgYIBgAAAA==.Faunuis:BAACLAAFFIEJAAQMAAYI+hEFAQAoAQAMAAMI4x0FAQAoAQANAAMIWxufAQAOAQAOAAEIpAxvAwBZAAAsAAQKgRgAAw4ACAiUJHQCANsCAA4ABwjdInQCANsCAAwACAh7ITsIALACAAAA.',Fe='Fearthebeef:BAAALAAECgYICgAAAA==.Featherbrain:BAAALAAECgIIAgAAAA==.Felmo:BAAALAADCggIDQAAAA==.Femboyxd:BAAALAAECgYIEgAAAA==.Ferdubs:BAAALAAECgUICAAAAA==.Ferenyet:BAAALAADCgcIBwAAAA==.',Fi='Fiercetits:BAAALAADCgcIEAAAAA==.Fizzybubbles:BAAALAAECgYICgAAAA==.Fizzydevil:BAAALAADCgcIBwAAAA==.',Fl='Flamehunter:BAAALAAECgYIDQAAAA==.Flapple:BAAALAAECgYICwAAAA==.Flûffy:BAAALAADCgcIBwAAAA==.',Fr='Freebowjöb:BAAALAADCggICAABLAAECgIIAwADAAAAAA==.',Fu='Fuacata:BAAALAAECgEIAQAAAA==.Funklock:BAAALAADCggICAAAAA==.',['Fð']='Fðxxy:BAAALAADCggICwAAAA==.',Ga='Gandàlin:BAAALAADCggIGAAAAA==.Gardasil:BAAALAADCgcIBwAAAA==.Garrand:BAAALAAECgMIBwAAAA==.Gatabtraluz:BAAALAADCgMIAwAAAA==.',Ge='Gelloa:BAAALAAECgYICwAAAA==.',Gg='Ggator:BAAALAAECgUIBQAAAA==.',Gl='Glimmer:BAAALAAECgYICQAAAA==.Glopanx:BAAALAAECgYICgAAAA==.',Go='Goldenapples:BAAALAADCggIDQAAAA==.Goresnot:BAAALAAECgIIAgAAAA==.',Gr='Grievur:BAAALAADCggIDAAAAA==.Grimphenix:BAAALAAECgMIAwAAAA==.Grizzn:BAAALAAECgYIBgAAAA==.Gryff:BAAALAAECgMIAwAAAA==.',Gu='Guap:BAACLAAFFIEJAAMPAAYIyBoFAQDYAQAPAAUIIhkFAQDYAQAQAAEICCNdAQBrAAAsAAQKgRkAAw8ACAj4JdMCAEsDAA8ACAgwJdMCAEsDABAAAQgEJtsIAHEAAAAA.Guapshot:BAAALAAECgEIAQAAAA==.Guile:BAAALAAECgMIAwAAAA==.Guillome:BAAALAAECgYIBgAAAA==.',Gw='Gwap:BAAALAAECgcIEwABLAAFFAYICQAPAMgaAA==.',Gy='Gypsysky:BAAALAADCgcIEgAAAA==.Gyrik:BAAALAADCggICAAAAA==.',['Gí']='Gífted:BAAALAAECgcICwAAAA==.',Ha='Haleybeary:BAAALAAECgMIAwAAAA==.Hallowborne:BAAALAADCgQIBAAAAA==.Hardlikepine:BAAALAADCgcIBwAAAA==.Hauntu:BAAALAAECgYIDAAAAA==.',He='Healfu:BAAALAADCggIEgAAAA==.Helligos:BAAALAADCgMIBAAAAA==.Hestia:BAAALAADCgcIBwAAAA==.Heydzood:BAAALAAECgYIDgAAAA==.',Hi='Hidendeath:BAAALAAECgEIAQAAAA==.Hidendeathh:BAAALAAECgYICwAAAA==.Highland:BAAALAAECgYICgAAAA==.Hippocratic:BAAALAADCggICAAAAA==.Hitaman:BAAALAAECgMIBQAAAA==.',Ho='Hogslammer:BAAALAAECgMIBwAAAA==.Hollowborne:BAAALAADCgQIBAAAAA==.Horan:BAAALAAECgcIEAAAAA==.Hotdemongel:BAAALAADCggIEQAAAA==.',Hr='Hriste:BAAALAAECgYICgAAAA==.',Hu='Hugakitty:BAAALAADCggICAABLAAECgYIDgADAAAAAA==.Hugétotem:BAAALAAECgMIBQAAAA==.Huumdinger:BAEALAAECgUIBQAAAA==.',Hw='Hwalthher:BAAALAAECgMICQAAAA==.',Ia='Ian:BAAALAAECggIBwAAAA==.',Ik='Ikedah:BAAALAAECgMIBgAAAA==.',Im='Imasan:BAAALAAECgUIBwAAAA==.Imbadbrah:BAAALAAECgYIDAAAAA==.Imgonnalust:BAAALAADCgIIAgAAAA==.Immadbrah:BAAALAAECgUIBQAAAA==.Imminentdoom:BAAALAAECgYICQAAAA==.Impmafia:BAAALAAECgYIDAAAAA==.Impslap:BAAALAAECgMIAwAAAA==.',In='Incog:BAAALAAECgcIEwAAAQ==.Insurrection:BAAALAADCgUIBQABLAADCggICAADAAAAAA==.Invayne:BAAALAAECgUICAAAAA==.',Io='Iolmop:BAAALAAECgEIAQAAAA==.',Ir='Iriya:BAAALAADCgcIBgAAAA==.Ironorc:BAAALAADCggICAAAAA==.',Ix='Ixen:BAAALAAECgQIBAAAAA==.',Ja='Jaesedar:BAAALAAFFAIIAgAAAA==.Jaestoes:BAAALAADCgcIBwAAAA==.Jamesharden:BAAALAADCgcICQAAAA==.Jandaraia:BAAALAADCgcIDQAAAA==.Jarlbrez:BAAALAADCgYIBgAAAA==.',Je='Jekylmayhyde:BAAALAADCggIDgAAAA==.Jellythug:BAAALAADCggIDgAAAA==.Jengosa:BAAALAAECgEIAQAAAA==.Jessrabbit:BAAALAADCgQIBAAAAA==.Jethon:BAAALAAECgUIBwAAAA==.Jexro:BAABLAAECoEWAAIRAAgIAibwAACBAwARAAgIAibwAACBAwAAAA==.',Jo='Johncennaa:BAAALAAECgYIDwAAAA==.',Ju='Jusstice:BAAALAAECgMIAwAAAA==.',Ka='Kad:BAAALAAECgMIAwAAAA==.Kairok:BAAALAAECgYIBgAAAA==.Kaleesi:BAAALAAECgEIAQAAAA==.Kasheira:BAAALAAECgMIAwAAAA==.Katti:BAAALAAECgIIAgAAAA==.Katà:BAAALAAECgYICAAAAA==.',Kb='Kblastis:BAAALAAECgcIEAAAAA==.Kblastissimo:BAAALAADCggICAAAAA==.',Kh='Kheirma:BAEALAADCggIFgAAAA==.Khronus:BAAALAAECgcIEAAAAA==.',Ki='Ki:BAAALAADCgcIBwAAAA==.Killerfròst:BAAALAADCgUIBQAAAA==.Kishok:BAAALAAECgMIBQAAAA==.',Kl='Klopklep:BAAALAADCgQIBAAAAA==.',Kn='Knøvå:BAAALAAECgYIDAAAAA==.',Ko='Koality:BAACLAAFFIEJAAISAAYIUBFVAAAuAgASAAYIUBFVAAAuAgAsAAQKgRgAAxIACAiZJhoAAJ0DABIACAiZJhoAAJ0DABMAAQhBBURYADYAAAAA.Koalitytime:BAAALAAECgUIAwAAAA==.Kojohunter:BAAALAADCgYIBgAAAA==.Kolgar:BAAALAAECgUIBgAAAA==.',Kr='Krähen:BAAALAADCggICAAAAA==.',Ku='Kulax:BAAALAADCgcIDgAAAA==.',Ky='Kyrohi:BAAALAADCgcIBwAAAA==.',['Kô']='Kôvu:BAAALAADCgYICwAAAA==.',La='Lazerchicken:BAAALAADCgMIAwAAAA==.',Lc='Lcboss:BAAALAAECgcIDQAAAA==.',Ld='Ldâwg:BAAALAAECgIIAgAAAA==.',Le='Leafshot:BAAALAADCgcIBwAAAA==.Lelu:BAAALAADCgUIBQAAAA==.Leucetios:BAAALAAECgMIAwAAAA==.',Li='Lilbilf:BAAALAAECgIIAgAAAA==.Liliuma:BAAALAADCgYIBgAAAA==.Linkddha:BAAALAADCggIDgAAAA==.Lithelissena:BAAALAADCgcIBwABLAAECggIDwADAAAAAA==.',Lo='Lockfocks:BAAALAADCgIIAgAAAA==.Locomana:BAAALAADCgYIBgAAAA==.Locoscar:BAAALAAECgYIEwAAAA==.Loktark:BAACLAAFFIEJAAIGAAYIxxACAABgAgAGAAYIxxACAABgAgAsAAQKgRcAAgYACAhxJgEAAKEDAAYACAhxJgEAAKEDAAAA.Longrichard:BAAALAAECgYICwAAAA==.Lootchi:BAACLAAFFIEJAAIUAAYIuxIeAAArAgAUAAYIuxIeAAArAgAsAAQKgRYAAhQACAhxJWsAAGMDABQACAhxJWsAAGMDAAAA.Lootee:BAAALAAECgEIAQABLAAFFAYICQAUALsSAA==.Lootin:BAABLAAECoEVAAIVAAgI9SKYAAA6AwAVAAgI9SKYAAA6AwABLAAFFAYICQAUALsSAA==.Loren:BAAALAADCgYIDAABLAAECgYIDAADAAAAAA==.Losstknight:BAAALAADCgUIBwAAAA==.',Lu='Lustíé:BAAALAADCgYIDAAAAA==.Luthianne:BAAALAAECgUICQAAAA==.',Ly='Lynfel:BAAALAAECgcIEwABLAAFFAYICQAWADUmAA==.Lyraessel:BAAALAAECgIIAgAAAA==.Lyreth:BAAALAAECgYICQAAAA==.',Ma='Maelstrom:BAAALAAECgEIAQAAAA==.Magedood:BAAALAAECgMIBwAAAA==.Magev:BAAALAAECgEIAQAAAA==.Maggerz:BAAALAAECgMIAwAAAA==.Maleficent:BAAALAADCggIDwAAAA==.Malefik:BAAALAAECgYIDAAAAA==.Mallence:BAAALAADCgQIBAAAAA==.Mambomarty:BAACLAAFFIEJAAMIAAYIgBhtAAA9AgAIAAYIfRhtAAA9AgAKAAEIGSV+CABdAAAsAAQKgRgABAgACAjzJggAAKoDAAgACAjrJggAAKoDABcAAwiGJOsOAEcBAAoABAiYJeYgABIBAAAA.Manather:BAACLAAFFIEJAAMYAAYIvSIJAAD6AQAYAAUI3yYJAAD6AQAQAAEIDw65AQBgAAAsAAQKgRgABBgACAidJmABAD4DABgACAhIJWABAD4DAA8ABQiGJkwaAD0CABAAAQj/Jd0IAHEAAAAA.Manginah:BAAALAAECgcIDAAAAA==.Martechroot:BAEALAADCgcIBwABLAAFFAIIAgADAAAAAA==.Mary:BAAALAADCgQIBAAAAA==.Mavanthis:BAAALAAECgYICgAAAA==.Maxdizaster:BAAALAAECgMIAwAAAA==.',Mc='Mcbonk:BAABLAAECoEWAAIZAAgIpSIuBQAcAwAZAAgIpSIuBQAcAwAAAA==.Mcgeethal:BAAALAAECgMIBAAAAA==.Mcmap:BAAALAADCggICAAAAA==.',Me='Merlenoir:BAAALAADCgcIDAAAAA==.Messybedhead:BAAALAAECgEIAQAAAA==.',Mi='Michaelboltn:BAAALAADCgcICAAAAA==.Michelsdru:BAAALAAECgIIAgAAAA==.Milesprower:BAAALAADCgEIAQAAAA==.Milfurion:BAAALAADCggICAAAAA==.Mindgamez:BAAALAADCgEIAQAAAA==.Mintwiskers:BAAALAAECgIIAgAAAA==.Misawa:BAAALAADCgYICgABLAAECgUICAADAAAAAA==.Mivix:BAAALAAECgcIEwABLAAFFAUIBwATAMkSAA==.',Mo='Moatboat:BAAALAAECgUIBQAAAA==.Moktarn:BAAALAADCgEIAQAAAA==.Mom:BAAALAAECgcIEAAAAA==.Monkco:BAAALAADCgMIAwAAAA==.Monkzu:BAAALAAECgYIDAAAAA==.Moosé:BAAALAAECgYIBgAAAA==.',Mu='Muffslam:BAAALAAECgEIAQAAAA==.Mugged:BAAALAAECggIDQAAAA==.Muinogaraa:BAAALAADCgUIBQABLAAFFAUIBgABAOoPAA==.Mushmouth:BAAALAAECgcIDgAAAA==.',My='Myiish:BAAALAADCgQIBAAAAA==.',['Mì']='Mìchael:BAAALAAECgIIAgAAAA==.',['Mú']='Músu:BAAALAAECgEIAQAAAA==.',Na='Nabruun:BAAALAADCgIIAgAAAA==.Nagosho:BAAALAADCgMIAwAAAA==.Naixdk:BAAALAAFFAIIAgAAAA==.Naixz:BAAALAAECggIDgABLAAFFAIIAgADAAAAAA==.Naixzz:BAAALAAECgYIBgAAAA==.Namaste:BAAALAAECgYICAAAAA==.Naril:BAAALAAECgYICgAAAA==.Narvana:BAAALAADCgYIBgAAAA==.Nautical:BAAALAADCgIIAgABLAAECgcIFAANAN8mAA==.Nayalla:BAAALAAECgMIAwAAAA==.',Ne='Neopolitan:BAAALAADCgcIDQAAAA==.Nephthysx:BAAALAADCgYICAAAAA==.Neredron:BAAALAADCggICAAAAA==.Neu:BAAALAAECgMIBAAAAA==.',Ng='Ngelofdeath:BAAALAAECgUIBQAAAA==.',Nh='Nhystel:BAAALAAECgYICQAAAA==.',Ni='Nilhilion:BAAALAADCgcIBwABLAADCggICgADAAAAAA==.Nimmit:BAAALAAECgcIDgAAAA==.Ningning:BAAALAAECggIDwAAAA==.',Nn='Nnk:BAAALAAECgUIBQAAAA==.',No='Nogaraa:BAAALAAECgIIAgABLAAFFAUIBgABAOoPAA==.Norina:BAABLAAECoEVAAMZAAgIURPVEwAuAgAZAAgIURPVEwAuAgAaAAYIIwY0HADnAAAAAA==.Novaku:BAAALAADCgMIAwAAAA==.Novath:BAACLAAFFIEJAAIbAAYIuh0MAAB4AgAbAAYIuh0MAAB4AgAsAAQKgRgAAxsACAihJhIAAIcDABsACAihJhIAAIcDAAUABggRAAAAAAAAAAAA.',Ny='Nyssarissa:BAAALAAECgcIDwAAAA==.',Oa='Oak:BAAALAADCggICAAAAA==.Oakenstream:BAAALAAECgcIEAAAAA==.',Oe='Oennogaraa:BAAALAADCggICAABLAAFFAUIBgABAOoPAA==.',On='Onereborn:BAAALAAECgIIAwAAAA==.Onetime:BAAALAADCgcIBwAAAA==.',Op='Ophélia:BAAALAAECgMIBwAAAA==.',Or='Oryk:BAAALAADCgcICgAAAA==.Oryx:BAAALAADCggIDAAAAA==.',Ow='Owlcapwn:BAAALAADCgIIAgAAAA==.',Ox='Oxito:BAAALAAECgUIBgAAAA==.',Oz='Ozzy:BAAALAADCgcIDQAAAA==.',Pa='Paalaz:BAABLAAECoEVAAIRAAgI8h2HEACLAgARAAgI8h2HEACLAgAAAA==.Paarthurnax:BAAALAADCggIDgAAAA==.Palmface:BAAALAAECgYICgAAAA==.',Pe='Peakes:BAAALAADCgUIBQAAAA==.Pedrocerrano:BAAALAAECgYICwAAAA==.Penos:BAAALAADCgEIAQAAAA==.Peteypab:BAAALAADCggIDwAAAA==.Petraen:BAAALAADCggIFwAAAA==.Pettaunt:BAAALAADCgMIAwAAAA==.',Ph='Phirefly:BAAALAADCggIEQAAAA==.Phoebrooke:BAAALAADCgMIAwAAAA==.Phoebë:BAAALAADCggIDwAAAA==.',Pi='Pickledin:BAAALAAECgIIAgAAAA==.Pinecones:BAAALAAECgcIEwABLAAECggIGAAZAI0kAA==.Pipila:BAAALAADCggIEwAAAA==.',Pk='Pkmntrainer:BAAALAADCgYIEAAAAA==.',Pl='Please:BAACLAAFFIEJAAIcAAYIYwZhAACtAQAcAAYIYwZhAACtAQAsAAQKgRgAAhwACAhaHYUHAJYCABwACAhaHYUHAJYCAAAA.Pleasethree:BAAALAADCggICAAAAA==.Pleasetwo:BAAALAAECgcIEwABLAAFFAYICQAcAGMGAA==.',Po='Poochootrain:BAAALAAECgMIBQAAAA==.Poofzimatree:BAAALAAECgEIAQAAAA==.Pook:BAAALAAECgcIDwAAAA==.',Pr='Pranayama:BAAALAAECgEIAQABLAAECgcIDQADAAAAAA==.Prezbyter:BAAALAAECgQIBQAAAA==.Properwanken:BAAALAAECgEIAQAAAA==.',Pu='Pullo:BAAALAAECgYIDgAAAA==.Pummeler:BAAALAAECgYICQAAAA==.Puresalt:BAAALAAECgMIAwAAAA==.Purple:BAAALAAECgEIAwAAAA==.',Py='Pyrê:BAAALAAECgEIAQAAAA==.',Qu='Queltrax:BAAALAADCgEIAQAAAA==.Quorsam:BAAALAADCggIDwAAAA==.',Qw='Qwadsfwfgads:BAABLAAECoEUAAINAAcI3yZ/AQAcAwANAAcI3yZ/AQAcAwAAAA==.',Ra='Rahkhza:BAAALAADCgIIAgAAAA==.Rakatashe:BAAALAAECgcIDQAAAA==.Ranko:BAAALAADCgUIBQAAAA==.Raszahk:BAAALAAECggIDgABLAAECgIIAwADAAAAAA==.Rawhide:BAAALAADCgcICwAAAA==.Rayden:BAAALAADCgcICQAAAA==.Razir:BAAALAAECgIIAgAAAA==.Razularu:BAAALAAECgMIAwAAAA==.',Re='Reavêr:BAAALAAECgYIDwAAAA==.Regidruid:BAAALAADCggICAABLAAECggIDQADAAAAAA==.Regilock:BAAALAAECggIDQAAAA==.Reinhart:BAAALAAECgIIAgABLAAECgYIBgADAAAAAA==.Rekoalafied:BAAALAAECgcIEwAAAA==.Retlec:BAAALAAECgYICgAAAA==.Reye:BAAALAADCggICAAAAA==.Reysalami:BAAALAADCgcIBwAAAA==.',Rh='Rhaethyn:BAAALAAECgEIAQAAAA==.Rheahtman:BAAALAADCggIDwAAAA==.',Ri='Rickaz:BAAALAAECgUIBQAAAA==.Riddck:BAAALAAECgYICQAAAA==.Rifràf:BAAALAAECgMIBQAAAA==.Rilana:BAAALAAECgcICAAAAA==.Ripto:BAAALAAECgUIBgAAAA==.Rithmatist:BAAALAAECgIIAgAAAA==.',Ro='Robles:BAAALAAECgEIAQAAAA==.Roshana:BAAALAAECgYICgAAAA==.Roshin:BAAALAADCggICgAAAA==.',Ru='Ruzzart:BAAALAADCggICAAAAA==.',Ry='Ryuulion:BAAALAAECgMIBgAAAA==.',['Rã']='Rãgë:BAAALAAECgEIAQAAAA==.',['Rä']='Räge:BAAALAADCgEIAQABLAAECgEIAQADAAAAAA==.',Sa='Sabat:BAAALAADCggICAAAAA==.Safiyah:BAAALAAECgMIAwAAAA==.Sal:BAAALAADCgQIBAAAAA==.Saltyevoker:BAAALAADCgMIAwAAAA==.Same:BAAALAAECgcIEwABLAAFFAYICQAbALodAA==.Samophlangy:BAAALAADCgIIAgAAAA==.Sandorstus:BAAALAADCgMIAwAAAA==.Sapphyre:BAAALAADCgcIBwAAAA==.Sappuccino:BAAALAAECgYIBgAAAA==.Saïnt:BAAALAAECgEIAQAAAA==.',Sc='Schmeged:BAAALAADCgIIAgAAAA==.Schtoove:BAAALAAECgIIAgAAAA==.Scope:BAAALAAECgEIAQAAAA==.Scottwarren:BAAALAAECgcIEAAAAA==.',Se='Sefirot:BAAALAAECgMIAwAAAA==.Selinddra:BAAALAAECgMIAwAAAA==.Sentry:BAAALAADCgUIBQAAAA==.Serfsup:BAAALAAECgQIBQAAAA==.Sevpriest:BAAALAADCgEIAwAAAA==.Seymoul:BAAALAADCgIIAgAAAA==.Seysana:BAAALAAECgMIBAAAAA==.',Sh='Shadowscale:BAAALAADCgcICAAAAA==.Shadowtism:BAAALAAECgIIAgAAAA==.Shamanfox:BAAALAAECgYIDgAAAA==.Shamanism:BAAALAADCgcIBwAAAA==.Shamdaddy:BAAALAAECgMIAwAAAA==.Shamezee:BAAALAADCggIFgAAAA==.Shiiko:BAAALAAECgMIAwAAAA==.Shintrospect:BAAALAAECgMIAwAAAA==.Shocklesnar:BAABLAAECoEXAAIdAAgI8SMOBQAYAwAdAAgI8SMOBQAYAwAAAA==.Shockntarts:BAAALAADCgYICgAAAA==.Shockrates:BAAALAADCgYIDAABLAADCgcIDAADAAAAAA==.',Si='Sicilianhero:BAAALAADCgUIBQAAAA==.Silento:BAAALAAECgQIBAAAAA==.Silveracid:BAAALAADCgYIBgABLAADCggICAADAAAAAA==.Silverwen:BAABLAAECoEZAAMEAAgIsiKQAgAlAwAEAAgIliKQAgAlAwAJAAYIURRtMAB7AQAAAA==.Simplytoxic:BAAALAADCgcICgAAAA==.Sindrz:BAAALAAECgIIAgAAAA==.Sinistratus:BAAALAAECgYICgAAAA==.Sinowbeat:BAAALAAECgcIEwABLAAFFAYICQAFAEIjAA==.Sinox:BAAALAAECgQIBwAAAA==.',Sk='Skidmo:BAAALAAECgYIEAAAAA==.Skipcawk:BAACLAAFFIEJAAMJAAYITxsJAABAAgAJAAYIPxgJAABAAgAEAAIIWB20BQCaAAAsAAQKgRcAAwQACAi3JYoAAGYDAAQACAi3JYoAAGYDAAkAAQjLHL5sAEQAAAAA.Skipco:BAAALAAECgcIEwABLAAFFAYICQAJAE8bAA==.Skroxx:BAAALAAECgQIBAAAAA==.',Sl='Slaying:BAAALAAECgYIDQAAAA==.',Sm='Smokesha:BAAALAADCgEIAQAAAA==.Smokietoke:BAAALAADCgMIAwAAAA==.',Sn='Snowleopard:BAAALAAECgIIAgABLAAECgQIBAADAAAAAA==.Snuffey:BAAALAAECgMIAwAAAA==.',So='Solfire:BAAALAAECgYICgAAAA==.Solstice:BAAALAAECgMIAwABLAAECgYICQADAAAAAA==.',Sp='Spardot:BAAALAADCgEIAQAAAA==.Sphalerite:BAAALAAECgMIAwAAAA==.Spite:BAAALAADCgcIBwAAAA==.',St='Starrynight:BAAALAADCgEIAQAAAA==.Starsaber:BAAALAADCggICAAAAA==.Stevewise:BAAALAAECgMIAwAAAA==.Stoc:BAAALAAECgMIBAAAAA==.Stormfall:BAAALAADCgcICgAAAA==.Stykah:BAAALAAECgMIAwAAAA==.',Su='Suinogaraa:BAAALAADCgcICAAAAA==.Sunderwhere:BAAALAAECgIIAwAAAA==.Sunjosh:BAAALAADCggIDQAAAA==.',Sw='Sweetbella:BAAALAADCgcIBwAAAA==.',Sy='Syf:BAAALAAECgMIAwAAAA==.Syllenda:BAAALAAECgIIAgAAAA==.Synched:BAAALAAECgMIBQAAAA==.',Ta='Taedas:BAAALAAECgYICgAAAA==.Tankatron:BAAALAADCgUIBQAAAA==.Tankyoumuch:BAAALAADCgcICgAAAA==.Tasis:BAAALAADCgYICQAAAA==.Taznia:BAAALAAECgMIAwAAAA==.',Te='Teddywaumpus:BAAALAADCggICAAAAA==.Tehax:BAAALAAECgYICgAAAA==.Tehaxe:BAAALAAECgIIAgAAAA==.Temir:BAAALAADCgMIAwAAAA==.Tenebrion:BAAALAADCgcIDgAAAA==.Tentotem:BAAALAAECgMIAwAAAA==.Teslacoil:BAAALAAECgYIDAAAAA==.',Th='Thabidness:BAAALAADCggIFgAAAA==.Thanquiol:BAACLAAFFIEJAAIWAAYINSYCAAB4AgAWAAYINSYCAAB4AgAsAAQKgRgAAhYACAjtJg8AAJ4DABYACAjtJg8AAJ4DAAAA.Thatchori:BAAALAADCgEIAQAAAA==.Thebaraj:BAAALAAECgYICQAAAA==.Thebarncat:BAAALAADCgcIBwAAAA==.Thedasboott:BAABLAAECoEUAAIbAAcIMQx2FgB+AQAbAAcIMQx2FgB+AQAAAA==.Thefel:BAAALAADCgEIAQAAAA==.Thegoat:BAAALAADCggICAAAAA==.Thehuntsman:BAAALAADCggIDgAAAA==.Theogflin:BAAALAADCgYIBgAAAA==.Thorenn:BAAALAADCgIIAgAAAA==.',Ti='Tigerlile:BAAALAADCggICAAAAA==.Tike:BAAALAADCggIEAABLAAECgcIDwADAAAAAA==.Timouthy:BAAALAADCgIIAgAAAA==.',To='Tomtrocity:BAAALAADCgcICAAAAA==.',Tr='Trillm:BAAALAAECgMIAwAAAA==.',Ts='Tsipayeoc:BAAALAADCgMIAwAAAA==.',Tw='Twerktooth:BAAALAAECgQIBgAAAA==.Twistedhavoc:BAAALAAECgMIBQAAAA==.Twk:BAAALAADCgMIBAAAAA==.Twïzz:BAAALAAECgYIDAAAAA==.',Um='Umalinn:BAAALAAECgYICgAAAA==.Umbragoth:BAAALAAECgEIAQAAAA==.',Un='Unicornblood:BAAALAADCggIDQAAAA==.Unrivaled:BAAALAAECgEIAQAAAA==.',Va='Vacca:BAAALAAECgYICAAAAA==.Vaelyra:BAAALAADCggIDgAAAA==.Vandagar:BAAALAAECgMIBAAAAA==.Vapor:BAABLAAECoEbAAIGAAcIZiI+AQDIAgAGAAcIZiI+AQDIAgAAAA==.Varista:BAAALAAECgYICgAAAA==.Varsity:BAABLAAECoEYAAIZAAgIjSQ0AgBVAwAZAAgIjSQ0AgBVAwAAAA==.Vasmonk:BAAALAAECgMIAwAAAA==.',Ve='Veleanna:BAAALAADCgYIBgAAAA==.Velyndina:BAAALAAECgYICAAAAA==.',Vi='Victor:BAAALAAECgEIAQAAAA==.Vidro:BAAALAAECgcIDwAAAA==.Viniette:BAAALAAECgcIDQAAAA==.Violinn:BAAALAAECgMIBQAAAA==.',Vo='Voodoobeast:BAAALAAECgMIAwAAAA==.',Vu='Vurjin:BAAALAADCggIDgAAAA==.',Wa='Wackytobaccy:BAAALAADCgIIAgAAAA==.',Wh='Whyme:BAABLAAECoEUAAMeAAgILiISBwDBAgAeAAcICiISBwDBAgAfAAMIIhjvDQDWAAAAAA==.',Wi='Wickle:BAAALAAECgMIAwAAAA==.Windwalkers:BAAALAADCgUIBQAAAA==.Wizliz:BAAALAADCggIDAAAAA==.',Wo='Woodbury:BAAALAAECgYIDAAAAA==.',Wr='Wreckkoning:BAAALAADCggIDgAAAA==.',Ws='Wsciekly:BAAALAAECgYICQAAAA==.',Xa='Xaliph:BAAALAAECgMIBAAAAA==.Xandela:BAAALAADCgMIAwAAAA==.Xas:BAAALAADCgcIDQAAAA==.',Xh='Xhamarific:BAAALAADCgYIBgAAAA==.',Xi='Xivei:BAACLAAFFIEHAAITAAUIyRJsAAC7AQATAAUIyRJsAAC7AQAsAAQKgRgAAhMACAiNJZIAAG0DABMACAiNJZIAAG0DAAAA.',Xo='Xoroth:BAAALAADCgcIDQAAAA==.',Xu='Xuedo:BAAALAADCggIDwAAAA==.',Yi='Yiffalicious:BAAALAADCgMIAwAAAA==.Yinlou:BAAALAAECgEIAQAAAA==.',Yv='Yvanehtnioj:BAAALAAECgMIBgAAAA==.',Za='Zachx:BAACLAAFFIEHAAMIAAYIsxbvAADjAQAIAAUIYRjvAADjAQAKAAEITg40CwBSAAAsAAQKgRgAAwgACAgRJsEBAFoDAAgACAjeJcEBAFoDABcABwhOJfUAAPUCAAAA.Zachxtweme:BAAALAAECgcIEwABLAAFFAYIBwAIALMWAA==.Zargar:BAAALAAECgYICwAAAA==.Zarmakai:BAABLAAECoEVAAIgAAgITiLHAwA4AwAgAAgITiLHAwA4AwAAAA==.',Zd='Zd:BAAALAAECgMIAwAAAA==.',Ze='Zelin:BAAALAAECgIIAgAAAA==.Zenxo:BAAALAADCgcIBwAAAA==.',Zi='Zillidan:BAAALAADCgYIBgABLAAFFAMIAwADAAAAAA==.',Zu='Zurg:BAAALAAECgYICQAAAA==.',Zy='Zygon:BAAALAAECgMIAwAAAA==.Zylos:BAAALAAECgcICwAAAA==.',Zz='Zzuh:BAAALAAECgYIDgAAAA==.',['Ök']='Ökko:BAAALAAECgMIBAAAAA==.',['Öw']='Öwly:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end