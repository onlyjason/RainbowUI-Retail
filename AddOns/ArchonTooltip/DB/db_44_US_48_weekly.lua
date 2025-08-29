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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Priest-Shadow','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','DeathKnight-Frost','DeathKnight-Blood','Priest-Holy','Mage-Arcane','Warrior-Protection','Monk-Windwalker','Druid-Feral','Druid-Balance','DeathKnight-Unholy',}; local provider = {region='US',realm='Caelestrasz',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaurus:BAAALAADCggIDQAAAA==.',Ab='Abdull:BAAALAADCgUIBgAAAA==.',Ac='Acailas:BAAALAAECgMIBgAAAA==.Acca:BAAALAADCggICAAAAA==.Ackrenezoth:BAAALAADCggICgAAAA==.Ackryd:BAAALAADCgMIBQAAAA==.',Ad='Adorion:BAAALAAECgMIBAAAAA==.',Ae='Aesku:BAAALAADCggICAAAAA==.Aethariale:BAAALAADCgIIAgAAAA==.',Ag='Agree:BAAALAADCgcIAwAAAA==.',Ai='Aidend:BAAALAADCgYIBgAAAA==.Aiydarkbane:BAAALAADCgEIAQAAAA==.',Ak='Akizza:BAAALAADCgcIDgAAAA==.',Al='Alayethun:BAAALAAECgIIAwAAAA==.Albaz:BAAALAADCgQIBQAAAA==.Alfah:BAAALAADCggIDgAAAA==.Alicia:BAAALAADCggICAAAAA==.Alixafxv:BAAALAADCgcIDAAAAA==.Allmightheal:BAAALAAECgMIAwAAAA==.Allorpally:BAAALAAECgMIBQAAAA==.Alltherage:BAAALAAECgMIBgABLAADCggICQABAAAAAA==.Altriaàlter:BAAALAADCgcIBwAAAA==.Alyxpants:BAAALAAECgQICAAAAA==.',Am='Amarayllia:BAAALAADCgcIBgAAAA==.Amishall:BAAALAAECgMIAwAAAA==.Amystake:BAAALAADCgEIAQAAAA==.',An='Anguskhan:BAAALAAECgIIAgAAAA==.Angæl:BAAALAAECgIIAwAAAA==.',Ar='Arcyandor:BAAALAAECgMIBQAAAA==.Aristomenis:BAAALAAECgMIAwAAAA==.Arity:BAAALAAECgYIDAAAAA==.Arkarna:BAAALAAECgIIAgAAAA==.Arlarna:BAAALAAECgYICwAAAA==.Arndul:BAAALAAECgYICwAAAA==.Artemmiss:BAAALAAECgMIAgABLAAECgMIBAABAAAAAA==.Arthilas:BAAALAADCgcIDAAAAA==.Artémïs:BAAALAADCgUIBQAAAA==.Arìes:BAAALAADCgMIAwAAAA==.',As='Ashairic:BAAALAAECgMIAwAAAA==.Ashammylady:BAAALAADCgMIAwAAAA==.Ashmear:BAAALAADCggIDwAAAA==.Ashtism:BAAALAAECgYICQAAAA==.Ashê:BAAALAADCgQIBAABLAAECgMIBAABAAAAAA==.',Au='Aurelia:BAAALAAECgYIDQAAAA==.Auryon:BAACLAAFFIEFAAICAAMImCK/AABDAQACAAMImCK/AABDAQAsAAQKgRgAAgIACAiZJUMCAE4DAAIACAiZJUMCAE4DAAAA.',Av='Avelane:BAAALAAECgYIBwAAAA==.',Ay='Ayahuasca:BAAALAAECgIIAgAAAA==.',Az='Azaman:BAAALAADCgcIDgAAAA==.Azdreamfyre:BAAALAAECgEIAQAAAA==.Azii:BAAALAADCgYICQAAAA==.Azoker:BAAALAAECgEIAgAAAA==.',Ba='Babulu:BAAALAADCggIEAAAAA==.Babuyang:BAAALAAECgYIBgAAAA==.Balan:BAAALAAECgQIBwAAAA==.Balerion:BAAALAAECgMIBAAAAA==.Barbossa:BAAALAAECgEIAQAAAA==.Barethor:BAAALAAECgIIAgAAAA==.Barimran:BAAALAADCggIDQAAAA==.Batos:BAAALAAECgYICgAAAA==.Battleaxe:BAAALAAECgMIBAAAAA==.',Be='Beeisme:BAAALAADCggIDAAAAA==.Bekstar:BAAALAADCggIFgAAAA==.Belarii:BAAALAAECgIIBAAAAA==.Belsam:BAAALAADCggIDwAAAA==.Benington:BAAALAAECgYIDQAAAA==.Beregond:BAAALAAECgMIBAAAAA==.',Bi='Biggobbo:BAABLAAECoEYAAIDAAgIYCOYAwAtAwADAAgIYCOYAwAtAwAAAA==.Bigstagger:BAAALAADCggICAAAAA==.Binbin:BAAALAADCgIIAgAAAA==.Binchooken:BAAALAAECgYICQAAAA==.Biyu:BAAALAADCgcIDgAAAA==.',Bj='Bjartastrasz:BAAALAAECgEIAQAAAA==.',Bl='Blankbeatle:BAAALAADCgcICAAAAA==.Blayke:BAAALAADCgIIAgAAAA==.Blazesoul:BAAALAADCgIIAgAAAA==.Blazine:BAAALAAECggIAgAAAA==.Blingblong:BAAALAADCgQIBQAAAA==.Bliss:BAAALAAECgIIAgAAAA==.Blueberry:BAAALAAECgYIDAAAAA==.Blueshott:BAAALAAECgIIAwAAAA==.Blòodrayne:BAAALAAECgQIBAAAAA==.',Bo='Bonadmer:BAAALAAECgEIAQAAAA==.Boneblocka:BAAALAAECgMIBgAAAA==.Boyaka:BAAALAADCgQIBAABLAAECgMIBAABAAAAAA==.',Br='Bracken:BAAALAADCgcIDQAAAA==.Braelaria:BAAALAADCgIIAgAAAA==.Breakernz:BAAALAAECgMIAwABLAAECggIEgABAAAAAA==.Breakersan:BAAALAAECgIIAgABLAAECggIEgABAAAAAA==.Briskett:BAAALAADCgIIAgAAAA==.Broxley:BAAALAAECgEIAgAAAA==.Bru:BAAALAAECgMIAwAAAA==.',Bu='Budgie:BAAALAAECgIIAgAAAA==.Budgy:BAAALAAECgIIAwAAAA==.Burdhammer:BAAALAADCgcIBwABLAAECgQIBwABAAAAAA==.Burdia:BAAALAADCgcIDAABLAAECgQIBwABAAAAAA==.Bussie:BAAALAAECgEIAgAAAA==.Buttabull:BAAALAADCggICAAAAA==.',['Bå']='Båst:BAAALAAECgEIAQAAAA==.',['Bë']='Bëllädonna:BAAALAADCgEIAQAAAA==.',Ca='Caffeínated:BAAALAAFFAIIAgAAAA==.Calenmirïel:BAAALAAECgIIAwAAAA==.Callipygian:BAAALAADCgcICAAAAA==.Captinfluff:BAAALAAECgQIBQAAAA==.Cardoney:BAAALAAECgMIBwAAAA==.Cariah:BAAALAAECgYICQAAAA==.Casteyl:BAAALAADCggIEwAAAA==.Catashax:BAAALAADCgUIBQAAAA==.Caylais:BAAALAAECgYICQAAAA==.Cayldin:BAAALAAECgMIAwAAAA==.',Cd='Cdkit:BAAALAAECgYIDQAAAA==.',Ce='Cersien:BAAALAAECgMIBgAAAA==.Cethe:BAAALAAECgIIAwAAAA==.',Ch='Chaosdemonn:BAAALAADCggIEAAAAA==.Charmedbee:BAAALAADCgYIBgAAAA==.Chasstise:BAAALAADCggIDwAAAA==.Cheazdad:BAAALAADCgYIBgAAAA==.Cheekz:BAAALAAECgQIBwAAAA==.Cheggery:BAAALAADCgUIBgAAAA==.Chirpe:BAAALAADCggIDwABLAAECgEIAQABAAAAAA==.Chronos:BAAALAADCggIDgAAAA==.Chubbo:BAAALAAECgMIBAAAAA==.Chubbypope:BAAALAADCggIEAABLAAECgMIAwABAAAAAA==.Chubshammy:BAAALAADCgYIDAAAAA==.',Ci='Cind:BAAALAAECgYICwAAAA==.Cinestrá:BAAALAAECgIIAwAAAA==.Citywok:BAAALAAECgYICQAAAA==.',Cl='Cleevi:BAAALAADCgYICwAAAA==.Clessan:BAAALAAECgIIAwAAAA==.Clissia:BAAALAADCgcIDAAAAA==.Cloudmonk:BAAALAAECgUIBwAAAA==.',Co='Coffêê:BAAALAAECgYIDwAAAA==.Corastrasza:BAAALAAECgIIAgAAAA==.',Cr='Crankez:BAAALAAECgQIBwAAAA==.Cresentmoon:BAAALAAECgEIAQAAAA==.Crimsonmage:BAAALAAECgMIAwAAAA==.Cristyl:BAAALAADCgcIDQAAAA==.',Cu='Cursednerd:BAAALAADCgYIBgAAAA==.',Cy='Cynnal:BAAALAAECgUIAwAAAA==.',Da='Dahj:BAAALAAECgEIAQAAAA==.Dalanar:BAAALAAECgMIBgAAAA==.Daltharan:BAAALAADCgcIAQAAAA==.Damnrisky:BAAALAAECgIIAgAAAA==.Danard:BAAALAADCgcIBwAAAA==.Danjanah:BAAALAADCgIIAgAAAA==.Dantragg:BAAALAAECgMIBwAAAA==.Daprity:BAAALAAFFAIIAgAAAA==.Darkspelz:BAAALAADCgcIBwABLAAECgYIBwABAAAAAA==.Davè:BAAALAAECgYIDQAAAA==.Daywalkër:BAAALAAECgMIAwAAAA==.',Dc='Dclyne:BAAALAADCggIEAAAAA==.',De='Deadkween:BAAALAADCgYIBgAAAA==.Deadlymoe:BAAALAAECgEIAQAAAA==.Debris:BAAALAAECgQIBwAAAA==.Decdum:BAAALAAECgEIAQAAAA==.Delililéi:BAAALAAECgEIAQAAAA==.Delây:BAAALAADCgcIDAAAAA==.Demnight:BAAALAADCgcIBwAAAA==.Demonpoison:BAAALAAECgYICQAAAA==.Denasar:BAAALAADCgYIBgAAAA==.Dengar:BAAALAAECgcIDgAAAA==.Desyphium:BAAALAAECgcIEgAAAA==.Devorra:BAAALAAECgEIAQAAAA==.Deyalane:BAAALAADCggIDQAAAA==.',Di='Diriisharks:BAAALAADCgYIBgABLAAECggIFQAEAIMjAA==.Dirtydeeds:BAAALAADCgIIAgAAAA==.Dirtykittie:BAAALAAECgcIEwAAAA==.',Do='Doinku:BAAALAADCgIIAgAAAA==.Doovezr:BAAALAADCgcIBwAAAA==.Dotshot:BAAALAADCgcIBwAAAA==.',Dr='Draemon:BAAALAAECgMIBQAAAA==.Dragonhead:BAACLAAFFIEFAAIFAAMIox15AgAgAQAFAAMIox15AgAgAQAsAAQKgRgAAgUACAhUJm8AAI8DAAUACAhUJm8AAI8DAAAA.Drahn:BAAALAADCgcIDQABLAAECgIIAwABAAAAAA==.Drakkuss:BAAALAADCgIIAgAAAA==.Drasston:BAAALAAECgQIBAAAAA==.Dreamer:BAAALAADCggIDwAAAA==.Drhoho:BAAALAAECgMIBgAAAA==.Drizztdemon:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Drsarixz:BAAALAAECgQICAAAAA==.',Du='Duty:BAAALAADCgcIBQAAAA==.',Dy='Dynam:BAAALAAECgYICQAAAA==.',['Dá']='Dáve:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.',Ea='Eahhgoth:BAAALAADCgcIEwAAAA==.',Ec='Eclipsè:BAAALAADCggICAAAAA==.',Ee='Eevaa:BAAALAADCggIBQAAAA==.Eevà:BAAALAADCgQIBAAAAA==.',Ef='Efink:BAAALAAECgcIEAAAAA==.',Eg='Eggboy:BAAALAADCgYIBgAAAA==.',Ei='Eirikafemk:BAABLAAECoEVAAIGAAgI3g8QDADQAQAGAAgI3g8QDADQAQAAAA==.Eirikafepa:BAAALAADCggICAABLAAECggIFQAGAN4PAA==.Eirikafesh:BAAALAADCggIEAABLAAECggIFQAGAN4PAA==.',Ek='Ektrical:BAAALAADCgIIAgAAAA==.',El='Elenoire:BAAALAAECgcIBwAAAA==.Elfhelm:BAAALAAECgIIAwAAAA==.Elipsis:BAAALAADCggICgAAAA==.Ellisinor:BAAALAADCggIFwAAAA==.Elnalle:BAAALAADCgQIBAAAAA==.Elröhir:BAAALAADCgEIAQABLAAECgcIDgABAAAAAA==.Elured:BAAALAAECgIIAwAAAA==.Elysean:BAAALAADCgcIAwAAAA==.',Em='Embermist:BAAALAAECgIIAwAAAA==.Emerelf:BAAALAADCgcIDAABLAAECgIIAwABAAAAAA==.Emliy:BAAALAAECgIIAgAAAA==.',Eq='Equinoxus:BAAALAAECgcIEwAAAA==.',Er='Ero:BAAALAADCggICQABLAAECgQICgABAAAAAA==.Erodan:BAAALAAECgQICgAAAA==.Eryuna:BAAALAADCgcIBwAAAA==.',Es='Estarae:BAAALAAECgMIAwAAAA==.',Ev='Everhealer:BAAALAAECgMIBAAAAA==.Evilhàg:BAAALAADCggICAAAAA==.Evilloaf:BAAALAADCgMIAwAAAA==.Evoo:BAAALAADCgYIBgAAAA==.',Ex='Exiledemon:BAAALAADCgEIAQAAAA==.',Fa='Faera:BAAALAAECgEIAgAAAA==.Fal:BAAALAAECgMIAwAAAA==.Falconova:BAAALAADCggICAAAAA==.Faneragare:BAABLAAECoEYAAMHAAgIeySRBAAqAwAHAAgIeySRBAAqAwAIAAMIFQ9cFgCbAAAAAA==.Fanface:BAAALAAECgIIAgAAAA==.Fated:BAAALAAECgcIEwAAAA==.',Fe='Feldylocks:BAAALAAECgMIBQAAAA==.Felfuryerza:BAAALAADCgcIBwAAAA==.Felstaber:BAAALAADCgcIBwAAAA==.Feromas:BAAALAADCgcIEQABLAAECgYICgABAAAAAA==.Feyfoxe:BAAALAADCgYICAAAAA==.',Fi='Fiarilina:BAAALAADCggICAABLAADCggICAABAAAAAA==.Fingersword:BAAALAAECgYIDwAAAA==.Firnén:BAAALAAECgIIAgAAAA==.Fishing:BAABLAAECoEVAAIEAAgIgyM3AwA/AwAEAAgIgyM3AwA/AwAAAA==.Fistor:BAAALAAECgEIAQAAAA==.',Fl='Flangelina:BAAALAADCgcIDAAAAA==.Flapsalot:BAAALAAECgIIAwAAAA==.Flaviousqt:BAAALAAECgMIAwAAAA==.Fleety:BAAALAAECgYIBgAAAA==.Flekzakzak:BAAALAAECgYIDgAAAA==.Flekzugzug:BAAALAADCgcICwAAAA==.Fleshmender:BAAALAAECgMIBgAAAA==.Floppyauntie:BAAALAAECgQICgAAAA==.Florota:BAAALAADCgcIDAAAAA==.Fluffpriest:BAABLAAECoEUAAIJAAgInhl2DQBcAgAJAAgInhl2DQBcAgAAAA==.',Fo='Foxes:BAAALAADCgUIBQAAAA==.',Fr='Frair:BAAALAAECgYIDgAAAA==.Franjipanni:BAAALAADCgcIDAAAAA==.Fresco:BAAALAADCgcIDQAAAA==.Freshprotein:BAAALAADCgcIBwAAAA==.Freshy:BAAALAAECgYICAAAAA==.Frostmagee:BAAALAADCggIEAAAAA==.',Fu='Fugandardy:BAAALAADCgYIDAAAAA==.Fupanchoo:BAAALAAECgMIBgAAAA==.Furryjessus:BAAALAAECgQIBAAAAA==.',Ga='Galah:BAAALAAECgMIBAAAAA==.Galell:BAAALAADCggICAAAAA==.Garmr:BAAALAADCgcIBwAAAA==.Garthurn:BAAALAADCgcICgAAAA==.',Ge='Gemli:BAAALAADCggICQAAAA==.Gentle:BAAALAAECgcIDAAAAA==.',Gh='Ghostsaber:BAAALAAECgQICQAAAA==.',Gi='Gibaz:BAAALAADCgQIBAAAAA==.Gistel:BAAALAAECgYIDgAAAA==.',Gn='Gnof:BAACLAAFFIEFAAIKAAMIEBj/AwAMAQAKAAMIEBj/AwAMAQAsAAQKgRgAAgoACAh7JMUEACoDAAoACAh7JMUEACoDAAAA.',Go='Goatvier:BAAALAAECgcIEgAAAA==.Gobbles:BAAALAADCgYIBgAAAA==.Goodenia:BAAALAADCggIEAAAAA==.Gooseyboy:BAAALAAECgIIAgABLAAECgQIBAABAAAAAA==.Gorhowl:BAAALAAECgYIDQAAAA==.Gorli:BAAALAAECgIIAwAAAA==.Goshie:BAAALAAECgYICQAAAA==.Gottolurveit:BAAALAADCgYIBgAAAA==.',Gr='Grabmeabeer:BAAALAADCggICAAAAA==.Gracela:BAAALAAECgMIBAAAAA==.Grantuss:BAAALAAECgMIBgAAAA==.Gravdh:BAAALAAECgcIEAAAAA==.Grimdeath:BAAALAAECgEIAQAAAA==.',Gu='Gutzee:BAAALAADCgcICQAAAA==.',['Gü']='Gürgän:BAAALAADCggICAAAAA==.',Ha='Hadestubby:BAAALAAECgcIEgAAAA==.Hamsta:BAAALAADCggIFAAAAA==.Hartcake:BAAALAADCgcIBwAAAA==.Haulalapa:BAAALAADCgcIAQAAAA==.',He='Headloc:BAAALAAECgIIAwAAAA==.Hellshunter:BAAALAAECgYIBwAAAA==.Hevifear:BAAALAAECgIIBAAAAA==.Hezaq:BAAALAAECgIIAwAAAA==.',Ho='Hollowcene:BAAALAADCgcIBwAAAA==.Hollowvoice:BAAALAAECgYICQAAAA==.Holocene:BAAALAAECgEIAQAAAA==.Holyspookies:BAAALAADCgcIEAABLAAECgEIAgABAAAAAA==.Holyviixen:BAAALAAECgQIBwAAAA==.Honoriah:BAAALAAECgMIBgAAAA==.Horacio:BAAALAADCggIFQAAAA==.Hormotional:BAAALAADCggICAAAAA==.Hotfridge:BAAALAAECgMIAwAAAA==.Houof:BAAALAADCgcIBwAAAA==.',Hr='Hrokgar:BAAALAAECgEIAQABLAAECggIGAAHAHskAA==.',Hu='Huahua:BAAALAADCggIDwAAAA==.Hubux:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.Huevodmuerte:BAAALAAECgYIEQAAAA==.Huntér:BAAALAAECgcIEwAAAA==.Huoyan:BAAALAADCgcIAwAAAA==.',Ia='Iamhots:BAAALAAECgcIEQAAAA==.',Ic='Icdedpple:BAAALAAECgQIBAAAAA==.Icepyro:BAAALAAECgcIDAAAAA==.Iceslurry:BAAALAAECgMIAwAAAA==.',Id='Idkwhattodo:BAAALAAECgMIAwAAAA==.',Ig='Igotcha:BAAALAADCgcIBwAAAA==.',Il='Illidirii:BAAALAADCgMIAwABLAAECggIFQAEAIMjAA==.',Im='Imabiteyou:BAAALAAECgMIAwAAAA==.Imanzder:BAAALAADCgcICQAAAA==.Impa:BAAALAADCgcIBwAAAA==.Imprison:BAAALAAECgYIDgAAAA==.',In='Inarius:BAAALAAECgMIBwAAAA==.Inflictor:BAAALAAECgYICQAAAA==.Inoe:BAAALAADCgcIDgAAAA==.',Is='Ishtara:BAAALAADCggICgAAAA==.Isterra:BAAALAADCgcIEwAAAA==.',Iz='Izuli:BAAALAADCgIIAgAAAA==.Izulia:BAAALAAECgQIBwAAAA==.Izulidor:BAAALAADCggICQAAAA==.Izzul:BAAALAADCggIEAABLAAECgQIBwABAAAAAA==.',Ja='Jab:BAAALAAECgMIAwABLAAECggIFQALALkhAA==.Jackiexx:BAAALAAECgcIDAAAAA==.Jadesong:BAAALAADCgIIAgAAAA==.Jaellylah:BAAALAADCgcIDgAAAA==.Jakestanater:BAAALAAECgUICAAAAA==.Jassel:BAAALAAECgQIBwAAAA==.Jazmeine:BAAALAAECgMIAwAAAA==.Jaýrider:BAAALAADCgcICQAAAA==.',Ji='Jickspirrow:BAAALAADCgEIAQAAAA==.Jimjam:BAAALAAECgIIAgAAAA==.',Jj='Jjsön:BAAALAAECgcIDQAAAA==.Jjthejester:BAAALAADCgUIBQAAAA==.',Jl='Jlaby:BAAALAAECgYICQAAAA==.',Jp='Jpxdk:BAAALAAECgYICQAAAA==.',Jr='Jrael:BAAALAADCgYIBgABLAAECgIIAwABAAAAAA==.',Ju='Juicei:BAAALAAECgEIAQAAAA==.',['Jë']='Jëster:BAAALAADCgIIAgABLAADCgUIBQABAAAAAA==.',Ka='Kaffie:BAAALAAECgMIBwAAAA==.Kagéslammer:BAAALAADCggICAAAAA==.Kalimaluaa:BAAALAADCgMIAgAAAA==.Kanundrum:BAAALAAECgEIAQAAAA==.Karll:BAAALAADCgEIAQABLAAECgMIBAABAAAAAA==.Kazayel:BAAALAAECgMIBAAAAA==.',Ke='Keli:BAAALAADCggICAAAAA==.Kestrel:BAAALAAECgIIAgAAAA==.Kevinfridge:BAAALAAECgMIAwAAAA==.Kevinoeleven:BAAALAADCgcIBQAAAA==.',Kh='Khasey:BAAALAAECgIIAwAAAA==.Khrøne:BAAALAADCgYIBgAAAA==.',Ki='Killionaire:BAAALAAECgcICgABLAAECgMIBAABAAAAAA==.Kinko:BAAALAADCggIFwAAAA==.',Ko='Koltx:BAAALAAECgYICQAAAA==.Konoko:BAAALAADCgIIAgAAAA==.Kosmage:BAAALAAECgcIDwAAAA==.',Kr='Krackd:BAAALAAECgYICAAAAA==.Kraii:BAAALAADCgQIBAAAAA==.Krasnyvolk:BAAALAAECgQIBQAAAA==.Kreuzschlitz:BAAALAADCgMIBgAAAA==.Krinksroozu:BAAALAADCgcIBwAAAA==.Krizkin:BAAALAADCggIDwAAAA==.Krugg:BAAALAAECgIIAgAAAA==.Kruzandir:BAAALAAECgMIAwAAAA==.',Ku='Kuck:BAAALAAECgEIAQAAAA==.Kusei:BAAALAAECgcIDAAAAA==.',Ky='Kybeth:BAAALAADCgIIAwAAAA==.Kyjra:BAAALAAECgYICQAAAA==.Kynhark:BAAALAADCgcIHAAAAA==.Kyoudo:BAAALAAECgIIAgAAAA==.',['Kâ']='Kâtàrä:BAAALAADCgYICQAAAA==.',['Kå']='Kåílañì:BAAALAADCgcICAAAAA==.',['Kæ']='Kælthas:BAAALAADCgcIBwAAAA==.',La='Lambda:BAAALAAECgYICQAAAA==.Lasergator:BAAALAAECgYIBgAAAA==.Layonpaws:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.Lazybeatle:BAAALAADCgcIDAAAAA==.',Le='Lease:BAAALAADCggIDwABLAADCggIFAABAAAAAA==.Legs:BAABLAAECoEVAAILAAgIuSFNAwDeAgALAAgIuSFNAwDeAgAAAA==.Leighandra:BAAALAAECgEIAQAAAA==.Lemonstrong:BAAALAADCgcIBwAAAA==.Lemures:BAAALAAECgcICQAAAA==.Lexoni:BAAALAADCggICAAAAA==.',Li='Lilfist:BAAALAAECgMIBgAAAA==.Linarisa:BAAALAAECgUIBQAAAA==.Linasong:BAAALAADCgcIAQABLAAECgUIBQABAAAAAA==.Liquidate:BAAALAAECgYICwAAAA==.Lissii:BAAALAADCgUIBQAAAA==.Litori:BAAALAADCgcIDgAAAA==.Littessa:BAAALAADCggICAAAAA==.Littlebob:BAAALAAECgEIAQAAAA==.Littlepaly:BAAALAAECgcIEQAAAA==.Littlepilot:BAAALAADCgcIBwAAAA==.',Lo='Lochana:BAAALAAECgcIDgAAAA==.Lockenstock:BAAALAADCgMIAwAAAA==.Lockiesdad:BAAALAADCggICAAAAA==.Lookatmoi:BAAALAAECgcIEAAAAA==.Lorethemar:BAAALAADCgYIBgAAAA==.Loryn:BAAALAAECgYIDgAAAA==.Loseyourself:BAAALAAECgMIAwAAAA==.',Lu='Lumbajack:BAAALAAECgMIBAAAAA==.Lunaera:BAAALAAECgMIAwAAAA==.Lunatepesh:BAAALAADCgMIAwAAAA==.',Ly='Lyth:BAAALAADCgYICwAAAA==.',['Lì']='Lìzârd:BAAALAADCgUIBQAAAA==.',['Lù']='Lùo:BAABLAAECoEVAAIMAAgI9BdtBwBcAgAMAAgI9BdtBwBcAgAAAA==.',Ma='Macflurry:BAAALAADCgYIBgAAAA==.Maedhros:BAAALAADCggICgAAAA==.Magicsnake:BAAALAAECgMIAwAAAA==.Magnerius:BAAALAADCggIFAAAAA==.Mags:BAAALAAECgcIEQAAAA==.Mahrkis:BAAALAAECgQIBwAAAA==.Maht:BAAALAAECgYICAAAAA==.Majinbuu:BAAALAAECgQICAAAAA==.Maldreds:BAAALAAECgQIBQAAAA==.Malfestio:BAAALAAECgYICQABLAAECgYICgABAAAAAA==.Mantuitor:BAAALAAECgMIAwAAAA==.Marielle:BAAALAAECgEIAQAAAA==.Mariku:BAAALAADCgcICwAAAA==.Marinthe:BAAALAADCgcIDAAAAA==.Marsie:BAAALAAECgMIAwAAAA==.Marvin:BAAALAAECgIIAwAAAA==.Mashex:BAAALAAECgQICQAAAA==.',Me='Mediyah:BAAALAADCgcIDAAAAA==.Medshocks:BAAALAAECgIIAwAAAA==.Melande:BAAALAAECgIIAwAAAA==.Mellowbee:BAAALAAECgcIDAAAAA==.Menzel:BAAALAADCggIFAAAAA==.Mercior:BAAALAAECgEIAQAAAA==.Mergabien:BAAALAAECgYIBwAAAA==.Merry:BAAALAADCgQIBAAAAA==.Merrytear:BAAALAADCggIDwAAAA==.',Mi='Miaque:BAAALAAECgMIBAAAAA==.Mikarika:BAAALAADCgcICwAAAA==.Mikecharo:BAAALAAECgQIBAAAAA==.Milksalve:BAAALAAECgYICQAAAA==.Milzey:BAAALAAECgYICQAAAA==.Minicrits:BAAALAADCgcICQAAAA==.Miraak:BAAALAADCgYIBwAAAA==.Miradin:BAAALAADCgcIBwAAAA==.Misshapp:BAAALAAECgIIAgAAAA==.Mistakoji:BAAALAAECgQIBAAAAA==.',Mo='Mogwii:BAAALAAECggICAAAAA==.Mojìto:BAAALAAECgEIAQAAAA==.Moltenelf:BAAALAADCgYIBgAAAA==.Moltenghost:BAAALAAECgUICgABLAADCgYIBgABAAAAAA==.Mondieu:BAAALAAECgcICAAAAA==.Monkel:BAAALAAECgMIBAAAAA==.Monkowski:BAAALAAECgQICgAAAA==.Mooh:BAAALAADCgYIBgAAAA==.Moonflora:BAAALAAECgIIBAAAAA==.Morderith:BAAALAADCggICAAAAA==.Morveth:BAAALAADCgcICwAAAA==.Moñk:BAAALAADCggICgAAAA==.',Ms='Msspells:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Mstrgizmo:BAAALAAECgIIAgAAAA==.',Mt='Mt:BAAALAADCgQIBAAAAA==.',Mu='Muted:BAAALAAECgQICAAAAA==.Muzc:BAAALAAECggIAQAAAA==.',My='Mythbriyon:BAABLAAECoEXAAINAAgIoSGhAQAIAwANAAgIoSGhAQAIAwAAAA==.Mythrerus:BAAALAADCgQIBQAAAA==.',['Mö']='Mörock:BAAALAADCgUIBQAAAA==.',Na='Naalaxii:BAAALAAECgQICAAAAA==.Nainaa:BAAALAADCggIDgAAAA==.Natrstorm:BAAALAAECgMIAwAAAA==.Naturised:BAAALAAECgIIAwAAAA==.Naursalla:BAAALAAECgcIEwAAAA==.Nawe:BAAALAAECgIIBAAAAA==.Nazghoul:BAAALAAECgYICgAAAA==.',Ne='Necratia:BAAALAAECgIIAgAAAA==.Necroptic:BAAALAAECgIIAgAAAA==.Neellixx:BAAALAADCggIEgAAAA==.Neflyn:BAAALAAECgMIBAAAAA==.Nekrofeelya:BAAALAAECgEIAQAAAA==.Nessaandra:BAAALAAECgMIAwAAAA==.Nessey:BAAALAAECgQICQAAAA==.Nestle:BAAALAAECgMIBgAAAA==.Nezarec:BAAALAADCgQIBAAAAA==.',Ni='Nightessence:BAAALAADCgUIBQAAAA==.Nimirie:BAAALAAECgQICQAAAA==.Nimuè:BAAALAAECgIIAwAAAA==.Ninja:BAAALAAECgQIBAAAAA==.',No='Noimen:BAAALAADCgcIBwAAAA==.Nokshaman:BAAALAAECgYICwAAAA==.Norflock:BAAALAADCgEIAQAAAA==.Noverra:BAAALAAECgcIDgAAAA==.',Ny='Nyarlathötep:BAAALAADCgIIAgAAAA==.Nynaevê:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.',Ob='Obrim:BAAALAAECgYICAAAAA==.',Od='Odefira:BAAALAADCgYIBgAAAA==.Odemii:BAAALAAECgMIBAAAAA==.Odessus:BAAALAADCgcIBwAAAA==.',Oh='Ohsheit:BAAALAADCgcICAAAAA==.',Ol='Oldspicè:BAAALAADCggICAAAAA==.',On='Onejobbeatle:BAAALAADCgUIBQAAAA==.Onnisan:BAAALAAECggIEgAAAA==.',Op='Oppressor:BAAALAAECgYIBgAAAA==.',Or='Orisi:BAAALAAECgMIAwAAAA==.Ormal:BAAALAADCggICwAAAA==.',Os='Osmess:BAAALAAECgMIAwAAAA==.',Ox='Oxtonguerice:BAAALAADCgcIBwAAAA==.',Oz='Ozzietree:BAABLAAECoEUAAIOAAcIjCVfBgDfAgAOAAcIjCVfBgDfAgAAAA==.',Pa='Pakerious:BAAALAADCggIDwAAAA==.Pallyaceman:BAAALAAECgYIDQAAAA==.Pallydion:BAAALAADCgQIAwAAAA==.Pandarella:BAAALAAECgMIBwAAAA==.Pandayu:BAAALAAECgYICAABLAAECggIFQAMAPQXAA==.Pandur:BAAALAAECgIIAgAAAA==.Parallaxia:BAAALAAECgcICwAAAA==.Pawmo:BAAALAAECgMIAwAAAA==.',Pe='Peako:BAAALAAECgcIDQAAAA==.Perollold:BAAALAAECgYICgAAAA==.',Ph='Pharmacie:BAAALAAECgQIBwAAAA==.',Pi='Picklé:BAAALAAECgQICAAAAA==.Pinkrock:BAAALAADCgMIAwABLAAECgQICgABAAAAAA==.Pinnk:BAAALAADCggICAAAAA==.Pirate:BAAALAAECgQICQAAAA==.',Pl='Plopperoo:BAAALAAECgMIBAAAAA==.',Po='Pocaface:BAAALAAECgMIBgAAAA==.Podabear:BAABLAAECoEVAAINAAgIUSLaAQD8AgANAAgIUSLaAQD8AgAAAA==.Podablood:BAAALAADCggIEAABLAAECggIFQANAFEiAA==.Podawoo:BAAALAADCggICAABLAAECggIFQANAFEiAA==.Pogmourne:BAAALAADCgcICgAAAA==.Poria:BAAALAADCgcIDAAAAA==.',Pr='Preserved:BAAALAAECgMIBQAAAA==.',Pu='Pubee:BAAALAAECgMIBgAAAA==.Puru:BAAALAAECgMIBAAAAA==.',Pw='Pwningyou:BAAALAAECgMIBgAAAA==.',['Pâ']='Pâkerious:BAAALAADCgYIDAAAAA==.',Qu='Quetzalcoatl:BAAALAADCgcIBwAAAA==.',Ra='Raenys:BAAALAAECgEIAQAAAA==.Rafemonk:BAAALAADCgcIBwABLAAECgQICgABAAAAAA==.Rafepally:BAAALAAECgQICgAAAA==.Ragner:BAAALAADCgcIAwAAAA==.Raiburd:BAAALAADCgUIBQABLAAECgQIBwABAAAAAA==.Raiigun:BAAALAAECgQICAAAAA==.Rakdos:BAAALAAECgIIAgAAAA==.Rakutina:BAAALAAECgMIBAAAAA==.Rastianklin:BAAALAAECgEIAQAAAA==.Rastillin:BAAALAADCgcIDAAAAA==.Rawrbewbs:BAAALAADCgUIBQABLAAECgcIEQABAAAAAA==.Rawrbewbz:BAAALAAECgcIEQAAAA==.Rawrbutt:BAAALAADCgMIAwABLAAECgcIEQABAAAAAA==.Rawrnewbz:BAAALAAECgIIAQABLAAECgcIEQABAAAAAA==.Rawrnoob:BAAALAAECgEIAQABLAAECgcIEQABAAAAAA==.Rayburd:BAAALAAECgQIBwAAAA==.Raziiel:BAAALAAECgMIBgAAAA==.',Rb='Rbeastmaster:BAAALAAECgEIAQAAAA==.',Re='Rebuked:BAAALAAECgMIAwAAAA==.Recharge:BAAALAADCggIDQAAAA==.Redrock:BAAALAAECgQICgAAAA==.Rekberries:BAAALAAECgMIBAAAAA==.Relinna:BAAALAADCggIEAAAAA==.',Rh='Rhiarrow:BAAALAADCgYIBgAAAA==.Rhodie:BAAALAAECgcIEQAAAA==.Rhyfelglod:BAAALAAECgcIEwAAAA==.Rhyzand:BAAALAADCggICAAAAA==.',Ri='Ricmnk:BAAALAAECgIIAwAAAA==.Rico:BAAALAADCgcIBwAAAA==.Rideshift:BAAALAAECgMIBQAAAA==.Rifkin:BAAALAAECgEIAQAAAA==.',Ro='Ronrot:BAAALAAECgcICAAAAA==.Roots:BAAALAAECgcIEQAAAA==.',['Rá']='Rágnar:BAAALAAECgIIAgAAAA==.',['Rö']='Rögue:BAAALAADCgQIBAAAAA==.',Sa='Safy:BAAALAAECgIIAwAAAA==.Saladin:BAAALAAECgMIBgAAAA==.Salfrom:BAAALAADCgQICAAAAA==.Samzuid:BAAALAAECgEIAQAAAA==.Sanamun:BAAALAAECggIAQAAAA==.Sanguiniüs:BAAALAAECgYIBgAAAA==.Sareàth:BAAALAADCgcIBwAAAA==.',Sc='Schwarzkopf:BAAALAADCgcIDAAAAA==.Scrubturkey:BAAALAAECgMIBgAAAA==.Scumvoker:BAAALAAECgMIBQAAAA==.',Se='Sebastien:BAAALAADCggICAAAAA==.Seidhkona:BAAALAAECgMIBgAAAA==.Senshi:BAAALAADCggICAAAAA==.Seraph:BAAALAADCgcIBwAAAA==.Seratus:BAAALAADCgYIBgAAAA==.Seravael:BAAALAAECgQICAAAAA==.Sevexy:BAAALAAECgYICwAAAA==.',Sh='Shadown:BAAALAADCgcIBwAAAA==.Shammydelic:BAAALAAECgEIAQAAAA==.Shield:BAAALAAECgYIDwAAAA==.Shikarii:BAAALAADCggIGAAAAA==.Shimmyt:BAAALAAECgIIAwAAAA==.Shions:BAAALAADCgUIBQAAAA==.',Si='Siceralc:BAAALAAECgMIAwAAAA==.Siilvermoose:BAAALAADCgcIEwAAAA==.Silandrea:BAAALAADCggIDwABLAADCggICQABAAAAAA==.Silversham:BAAALAADCgEIAQAAAA==.Silverstaria:BAAALAADCggIDwAAAA==.Sinamor:BAAALAAECgcIDAAAAA==.Sinless:BAAALAADCgIIAgAAAA==.',Sk='Skermish:BAAALAADCggICwABLAAECgYIDgABAAAAAA==.Skwamptumpus:BAAALAADCgcIAQAAAA==.',Sl='Slashfire:BAAALAAECgYICQAAAA==.Slysham:BAAALAADCggICAAAAA==.Släps:BAAALAADCgcICwAAAA==.',Sm='Smooks:BAAALAAECgYIDwAAAA==.',Sn='Snax:BAAALAAECgQICAAAAA==.Sneeds:BAAALAAECgcIDQAAAA==.Snowhail:BAAALAAECgIIAwAAAA==.',So='Soal:BAAALAAECgMIBAAAAA==.Soaringsky:BAAALAAECgcIEQAAAA==.Sogekingx:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Solacium:BAAALAAECggIDgAAAA==.Soopershot:BAAALAADCggIDwAAAA==.Sopheeaa:BAAALAAECgMIBAAAAA==.Sozin:BAAALAADCgIIAgAAAA==.',Sp='Spacepawz:BAAALAADCgcIDAAAAA==.Spangledorf:BAAALAAECgYICQAAAA==.Sparrów:BAAALAAECgYICQAAAA==.Spawnoflieb:BAAALAADCgMIAwAAAA==.Spaztik:BAAALAADCggICgAAAA==.Spectrefive:BAAALAAECgIIAgAAAA==.Spectressa:BAAALAAECgIIAgAAAA==.Spicychimken:BAAALAADCggIFwAAAA==.Spookies:BAAALAAECgEIAgAAAA==.Spâcegoat:BAAALAAECgQIBwAAAA==.',Sq='Squishybelly:BAAALAADCgUIBQAAAA==.',St='Starielle:BAAALAAECgEIAgAAAA==.Stellarus:BAAALAAECgYICgAAAA==.Stormblessed:BAAALAAECgEIAQAAAA==.Stormyshadow:BAAALAADCggIEwAAAA==.',Su='Sunhi:BAAALAADCgcICQAAAA==.Surashock:BAAALAAECgIIAgAAAA==.Suunshine:BAAALAAECgMIBAAAAA==.',Sw='Swampyhunt:BAAALAAECgYICQAAAA==.Sworden:BAAALAADCgcIDgAAAA==.',Sy='Sylvianna:BAAALAADCgcIDQAAAA==.Sylvianne:BAAALAADCgUIBQAAAA==.Synfal:BAAALAADCggICAAAAA==.Syrezz:BAAALAADCgcIBwAAAA==.',['Sè']='Sèraph:BAAALAADCgQIBQAAAA==.',Ta='Tainter:BAAALAAECgYIDQAAAA==.Taity:BAAALAADCgYIBgABLAAECgQICQABAAAAAA==.Tangodruid:BAAALAAECgMIBgAAAA==.Tarynz:BAAALAADCggICwAAAA==.',Te='Tegglez:BAABLAAECoEWAAMPAAgIpx4sCAAhAgAPAAYIQx8sCAAhAgAHAAMIoho+WgDdAAAAAA==.Tellan:BAAALAADCgMIAwABLAADCgcIBwABAAAAAA==.',Th='Thalaera:BAAALAADCgEIAQABLAAECgYIBwABAAAAAA==.Thallan:BAAALAADCgcIDgABLAADCggICwABAAAAAA==.Thanatoss:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.Thatdamdruid:BAAALAAECgIIAwAAAA==.Thekrelltoss:BAAALAAECgYIDwAAAA==.Thânâtos:BAAALAAECgIIAgAAAA==.',Ti='Tiffaknee:BAAALAADCgEIAQAAAA==.',To='Torale:BAAALAADCgMIAwAAAA==.Toriyama:BAAALAAECgYIDQAAAA==.Tormentar:BAAALAADCgYIBgAAAA==.Totembeatle:BAAALAAECgYIDwAAAA==.Totemsforaid:BAAALAAECgMIBgAAAA==.Toteshadow:BAAALAAECgIIAgAAAA==.Totesto:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Tototoro:BAAALAADCgUICAABLAAECgIIAgABAAAAAA==.Tovuk:BAAALAAECgMIBgAAAA==.',Tr='Treecoleos:BAAALAAECgUICAAAAA==.Triplesix:BAAALAADCgYICgAAAA==.Trippedbee:BAAALAADCggIDwAAAA==.Trollolol:BAAALAADCggICQAAAA==.',Ts='Tsireyahbm:BAAALAAECgUIBwAAAA==.',Tu='Tussle:BAAALAADCggICAAAAA==.',Tw='Twîsted:BAAALAAECgMIBQAAAA==.',Ty='Tynfoyl:BAAALAAECgIIAgAAAA==.Tyraná:BAAALAAECgMIAwAAAA==.Tyrionmutt:BAAALAADCgcIBwABLAAECgQICQABAAAAAA==.Tyrolean:BAAALAADCggIEQAAAA==.',['Tà']='Tàe:BAAALAADCgcIDQAAAA==.',['Tò']='Tònk:BAAALAADCgQIBAAAAA==.',Ud='Udown:BAAALAADCgQIAgAAAA==.',Up='Upsilon:BAAALAADCgcIBwAAAA==.Uptime:BAAALAADCggIDgAAAA==.',Va='Vaardzz:BAAALAAECgMIAwAAAA==.Valatuuk:BAAALAAECgMIAwAAAA==.Valipali:BAAALAADCggIDwAAAA==.',Ve='Veanir:BAAALAAECgIIAgAAAA==.Veletta:BAAALAADCggICAAAAA==.Vellarya:BAAALAAECgIIAwAAAA==.Velphian:BAAALAAECgYICQAAAA==.',Vi='Vials:BAAALAADCggIDwABLAAECggIEgABAAAAAA==.Vintagewine:BAAALAADCgIIAgAAAA==.Vividèlity:BAAALAAECgIIAwAAAA==.',Vo='Vozie:BAAALAAECgQICAAAAA==.',Vr='Vraielshaman:BAAALAAECgYIBgAAAA==.Vraielsneak:BAAALAAECgYIDQAAAA==.Vrchat:BAAALAAECgMIAwAAAA==.Vrogoth:BAAALAAECgQICQAAAA==.',Vy='Vyke:BAAALAAECgMIBwAAAA==.Vyndrasylia:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Vyxenn:BAAALAAECgcIEQAAAA==.',['Vê']='Vêlmarah:BAAALAAECgEIAQAAAA==.',Wa='Warriortolof:BAAALAADCgIIAgAAAA==.Watchmyfur:BAAALAAECgMIBAAAAA==.Watchy:BAAALAADCgcIBwAAAA==.',We='Weebix:BAAALAADCgEIAQAAAA==.',Wh='Whyningurl:BAAALAAECgQIBgAAAA==.',Wi='Wiiman:BAAALAAECgcICwAAAA==.Willbert:BAAALAAECgMIAwAAAA==.Willowwood:BAAALAADCgcIBwAAAA==.',Wo='Wot:BAAALAAECgIIAwAAAA==.',Xe='Xeenah:BAAALAAECgYIDQAAAA==.Xenobi:BAAALAAECgYIBgAAAA==.Xerolife:BAAALAAECgYICQAAAA==.',Xf='Xforce:BAAALAAECgcICwAAAA==.',Xi='Xilef:BAAALAAECgMIAgAAAA==.',Ya='Yaboi:BAAALAADCgMIAwAAAA==.',Yo='Yoy:BAAALAADCggICAAAAA==.',Yu='Yukes:BAAALAAECgYIDQAAAA==.',Yw='Ywerd:BAAALAADCggICAAAAA==.',['Yí']='Yíkes:BAAALAAECgMIAwAAAA==.',Za='Zaarock:BAAALAADCggICAAAAA==.Zanduill:BAAALAAECgcIEAAAAA==.Zantrollawen:BAAALAADCggIDwAAAA==.Zaräck:BAAALAAECgMIBgAAAA==.Zayva:BAAALAADCggIDwAAAA==.',Ze='Zeally:BAAALAAECgQIBAAAAA==.Zeeva:BAAALAADCggIDgABLAADCggIDwABAAAAAA==.Zeflashtrash:BAAALAADCggICgAAAA==.Zeht:BAAALAADCgEIAQAAAA==.',Zi='Zillchi:BAAALAAECgEIAgAAAA==.Zincberg:BAAALAADCggIEwAAAA==.Zindroz:BAAALAAECgcICwAAAA==.',Zo='Zorbax:BAAALAAECgEIAgAAAA==.Zorgoth:BAAALAAECgIIAwAAAA==.',Zu='Zunny:BAAALAADCggIDwAAAA==.',Zy='Zykaei:BAAALAAECgcIEQAAAA==.',Zz='Zzeldris:BAAALAAECgMIBQAAAA==.',['Zá']='Záräck:BAAALAADCgEIAQABLAAECgMIBgABAAAAAA==.',['Zä']='Zäräck:BAAALAAECgMIBgABLAAECgMIBgABAAAAAA==.',['Áy']='Áylamao:BAAALAAECgUIBQAAAA==.',['Âs']='Âssâssin:BAAALAAECgYICAAAAA==.',['Äz']='Äzi:BAAALAAECggIDAAAAA==.',['Æc']='Æclipsè:BAAALAADCgEIAQAAAA==.',['Ço']='Çomplexity:BAAALAAECgYICAAAAA==.',['Ðe']='Ðeez:BAAALAADCgcIBwABLAAECgQIBwABAAAAAA==.Ðeeztard:BAAALAAECgQIBwAAAA==.',['Ði']='Ðiesel:BAAALAADCggIFgABLAAECgQIBwABAAAAAA==.',['Ðr']='Ðroppd:BAAALAAECgIIAgAAAA==.',['Øb']='Øbiwan:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end