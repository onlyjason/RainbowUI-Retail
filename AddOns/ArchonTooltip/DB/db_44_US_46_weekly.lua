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
 local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Rogue-Assassination','Unknown-Unknown','Shaman-Enhancement','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Druid-Restoration','Evoker-Devastation','DemonHunter-Havoc','Shaman-Elemental','Warrior-Fury','Mage-Arcane','Mage-Fire','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','Monk-Mistweaver','Evoker-Preservation','Monk-Brewmaster','Druid-Feral','Rogue-Subtlety','DeathKnight-Blood','Warrior-Protection','Paladin-Retribution',}; local provider = {region='US',realm='BurningBlade',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aatto:BAABLAAECoEWAAQBAAgINRmbBgD7AQABAAgIChmbBgD7AQACAAQIkBczEAAwAQADAAMIow7MRwCUAAAAAA==.',Ab='Abyssial:BAAALAADCgIIAgAAAA==.',Ac='Acerhelper:BAAALAAECgYIBwAAAA==.Acertrick:BAACLAAFFIELAAMEAAYI4hgDAABVAgAEAAYI4hgDAABVAgAFAAEIOQNPCgBXAAAsAAQKgRgAAgQACAjNJS0AAGMDAAQACAjNJS0AAGMDAAAA.',Ad='Adria:BAAALAAECgEIAQAAAA==.Adumb:BAAALAADCgQIBAAAAA==.Ady:BAAALAAECgcICwAAAA==.Adyv:BAAALAADCggICAABLAAECgcICwAGAAAAAA==.',Ae='Aelwyd:BAACLAAFFIEFAAIDAAMI5AK3BADkAAADAAMI5AK3BADkAAAsAAQKgSAAAwMACAgyHBcMAIoCAAMACAgyHBcMAIoCAAIABwheDRYHAOwBAAAA.Aery:BAAALAAECgcIEwAAAA==.Aessara:BAAALAAECgMIBgAAAA==.',Ag='Aggron:BAABLAAECoEXAAIHAAgIZSGVAQDwAgAHAAgIZSGVAQDwAgAAAA==.Aggrøh:BAAALAAECggIEQAAAA==.',Ah='Ahdumb:BAAALAAECgcIDQAAAA==.',Ai='Ailurun:BAAALAADCgQIBAAAAA==.',Al='Alexassassin:BAABLAAECoEYAAIEAAgIYBr+AQBxAgAEAAgIYBr+AQBxAgAAAA==.Aloriannis:BAAALAADCggICQABLAAECgMIAwAGAAAAAA==.Alphaeryn:BAAALAAECgIIAgAAAA==.Altonoon:BAAALAAECgYIDgAAAA==.',Am='Amarace:BAAALAADCgcIDgABLAADCgEIAQAGAAAAAA==.Amaraceshift:BAAALAADCgEIAQAAAA==.Amaymon:BAAALAADCgcIEQAAAA==.Amazing:BAAALAAECgYICQAAAA==.Amowbrose:BAAALAAECgMIBgAAAA==.Amowdemoon:BAAALAADCggIDwABLAAECgMIBgAGAAAAAA==.',An='Anatall:BAAALAAECgcIBQAAAA==.Anitá:BAAALAADCggIDwAAAA==.',Ap='Applejack:BAAALAADCgYIBgAAAA==.',Ar='Araeriiscise:BAAALAAECgEIAgABLAAFFAMIBQAIAJMhAA==.Araeriispi:BAACLAAFFIEFAAIIAAMIkyGBAQBBAQAIAAMIkyGBAQBBAQAsAAQKgRsAAwgACAhZJskAAHoDAAgACAhZJskAAHoDAAkAAwhvJBgvADUBAAAA.Arcaneette:BAAALAADCgYIBgAAAA==.Arcturous:BAAALAAECgIIAgAAAA==.Argosa:BAAALAAECgEIAQABLAAECgYIBgAGAAAAAA==.Ari:BAAALAAECgYIDAAAAA==.Ariehh:BAAALAADCgYIBgABLAAECgYIDAAGAAAAAA==.Arihog:BAAALAADCggIEAAAAA==.Arisol:BAAALAADCgYIBgABLAAECgYIDAAGAAAAAA==.Arkilyte:BAAALAAECgYIBgABLAAFFAYICgAKANYiAA==.Arkilytë:BAACLAAFFIEKAAMKAAYI1iJBAADyAQAKAAUIUSJBAADyAQALAAEIbCU1CQBxAAAsAAQKgRgAAgoACAhVJUEBAEwDAAoACAhVJUEBAEwDAAAA.Arkîlyte:BAAALAADCggICAAAAA==.Arothira:BAAALAAECgMIAwAAAA==.Aryä:BAAALAAECgIIAgAAAA==.',As='Ascend:BAECLAAFFIEMAAIMAAYIfg5AAAAUAgAMAAYIfg5AAAAUAgAsAAQKgRgAAgwACAgPG8kEAIwCAAwACAgPG8kEAIwCAAAA.Ascendant:BAEALAAECgYIBgABLAAFFAYIDAAMAH4OAA==.Ashona:BAAALAADCgcIEQAAAA==.',At='Atomed:BAAALAADCgIIAgAAAA==.Atulho:BAAALAADCgMIAwAAAA==.',Au='Auroch:BAAALAAECgYIDAAAAA==.Auxilary:BAAALAAECgcIEwAAAA==.',Av='Avarcis:BAAALAAECgcICgAAAA==.Aveloree:BAAALAAECgEIAgAAAA==.Avigdor:BAAALAADCgYIBgAAAA==.',Aw='Awful:BAAALAADCggIDQABLAAECgYICAAGAAAAAA==.',Az='Aznu:BAAALAADCggICAAAAA==.Azuggo:BAAALAAECgMIBAAAAA==.',Ba='Baalian:BAAALAADCggIEAAAAA==.Ballidur:BAAALAAECgUIBQAAAA==.Banick:BAAALAADCggIDwAAAA==.Bankaî:BAAALAAECgEIAQAAAA==.Bare:BAAALAADCgMIAwAAAA==.Barrey:BAAALAAECgUIBQABLAAFFAMIBQANAFIaAA==.Bartszdruid:BAAALAAECgYIDAAAAA==.Bartszgreen:BAAALAADCgEIAQABLAAECgYIDAAGAAAAAA==.Bartszsimpsn:BAAALAAECgYIDAABLAAECgYIDAAGAAAAAA==.Baylan:BAAALAADCgcIBwAAAA==.',Be='Beastbeard:BAAALAADCggIBwAAAA==.Beastbme:BAAALAADCgMIBAAAAA==.Beefbroroni:BAABLAAECoEVAAIOAAgI4RHLEAAAAgAOAAgI4RHLEAAAAgAAAA==.Bendie:BAAALAADCggIDAAAAA==.Beret:BAAALAAECgcIEwAAAA==.Bewmbat:BAEALAAECgYICQAAAQ==.',Bi='Biggybones:BAAALAAECgEIAQAAAA==.Bimbo:BAAALAAECgYICQAAAA==.Birdinii:BAAALAAECgYIBgAAAA==.Bithindel:BAAALAAECgQIBgAAAA==.',Bl='Blargdrake:BAAALAAECggIEgAAAA==.Blessurheart:BAAALAAECgIIAgAAAA==.',Bo='Bonkie:BAAALAADCgcICAAAAA==.Boots:BAAALAADCgMIAwAAAA==.Bowslash:BAAALAAECgYICgAAAA==.Boötesvoid:BAAALAADCggICAAAAA==.',Br='Brexxdh:BAACLAAFFIEQAAIPAAYIbxJZAAA6AgAPAAYIbxJZAAA6AgAsAAQKgSAAAg8ACAgVJtIBAGwDAA8ACAgVJtIBAGwDAAAA.Brisnger:BAAALAADCgcIBwAAAA==.Brockwell:BAAALAAECgEIAQAAAA==.Brojojojojo:BAAALAAECgYICwAAAA==.Bryandelios:BAAALAAECgMIAwAAAA==.',Bu='Bubb:BAAALAAECgEIAQAAAA==.Bubkiss:BAEALAAECgYIBwABLAAECgYICQAGAAAAAQ==.Buffalo:BAAALAAECgcIEwAAAA==.Buffs:BAAALAAECgQIBgAAAA==.Burgerpriest:BAAALAAECgYIEQAAAA==.',Ca='Cain:BAAALAADCggICQAAAA==.Cakes:BAAALAAECgYIDwAAAA==.Caldrick:BAAALAADCgcIDAAAAA==.Callie:BAACLAAFFIEKAAIJAAUIjQ1uAAC4AQAJAAUIjQ1uAAC4AQAsAAQKgRgAAgkACAh1FXkSACICAAkACAh1FXkSACICAAAA.Carerra:BAAALAADCgIIAgAAAA==.Catwink:BAAALAADCgYIBgAAAA==.Caulkgoblinz:BAAALAAECgMIBgAAAA==.',Ce='Celine:BAAALAAECgQIBwAAAA==.',Ch='Chaddbrochil:BAAALAADCggICAAAAA==.Chaosblade:BAAALAAECgMIBwAAAA==.Chickengawdz:BAAALAAECgcIDgAAAA==.Chizzlefronk:BAAALAAECgIIAwAAAA==.Chocobomb:BAABLAAECoEXAAIQAAgIzxa+DwBQAgAQAAgIzxa+DwBQAgAAAA==.Chunkis:BAAALAADCgcIBwAAAA==.Chuulimta:BAAALAADCgEIAQAAAA==.',Ci='Cicatrizesp:BAAALAAECgYIEQAAAA==.Cive:BAAALAAECgQIBgAAAA==.',Cl='Clëric:BAAALAAECgYIDAAAAA==.',Co='Cocytuss:BAAALAADCgEIAQABLAAECgYICgAGAAAAAA==.Coldhurted:BAAALAAECgcIEwAAAA==.Corvo:BAAALAADCgQIBAABLAAECgYICgAGAAAAAA==.Cosmere:BAAALAAECgIIAgAAAA==.',Cr='Crimsondusk:BAAALAAECgcIEQAAAA==.Cringefuk:BAAALAAECgYIBgAAAA==.Crêate:BAAALAADCgcIEQAAAA==.',Cy='Cyela:BAAALAADCgYIBgAAAA==.Cyelana:BAAALAADCggICAAAAA==.Cygníus:BAAALAAECgMIAwAAAA==.Cygs:BAAALAAECgQIBAAAAA==.Cyne:BAAALAADCgUIBQAAAA==.',Da='Dagather:BAAALAAECgMIBQAAAA==.Dahnza:BAABLAAECoEYAAIRAAYIJw1pKABtAQARAAYIJw1pKABtAQAAAA==.Dalagone:BAAALAADCgIIAgAAAA==.Dalelador:BAAALAAECgEIAQAAAA==.Dampfur:BAAALAAECgYICwAAAA==.Danendena:BAAALAAECgMIAwAAAA==.Dapope:BAAALAAECgYIBgAAAA==.Darkcorn:BAABLAAECoEYAAIRAAYIfh2dGQDvAQARAAYIfh2dGQDvAQAAAA==.Darkflash:BAAALAADCgEIAQAAAA==.Darkhogtech:BAAALAADCgQICAAAAA==.Darkslaier:BAAALAADCgIIAgAAAA==.Darminna:BAAALAAECgcIEwAAAA==.Darminno:BAAALAADCggICAAAAA==.Daziize:BAAALAAECgcIDwAAAA==.',De='Deathlywind:BAAALAAECgcIDQABLAAECggIFQALAIQfAA==.Deathspark:BAAALAADCggIEAAAAA==.Debo:BAAALAADCgcICAAAAA==.Dee:BAAALAAECgMIAwAAAA==.Demongems:BAAALAADCgcICwAAAA==.Demoslem:BAAALAADCggIDQAAAA==.Dereksama:BAAALAAECgYICgAAAA==.Derrickwhite:BAAALAAECgYIBgAAAA==.Destivine:BAAALAADCgMIAwAAAA==.Destrorin:BAAALAADCgUIBQAAAA==.Deucedeuce:BAAALAAECgEIAQAAAA==.Devowizard:BAACLAAFFIEQAAMSAAYIfiI0AAAjAgASAAUIRSU0AAAjAgATAAEIlxSwAQBhAAAsAAQKgSgAAxIACAi7JkcAAI0DABIACAi7JkcAAI0DABMAAQiXJs8IAHIAAAAA.',Di='Dibib:BAACLAAFFIELAAMDAAYI9RW0AQB3AQADAAQILxS0AQB3AQABAAIIgxkaAwC0AAAsAAQKgRgABAEACAjmI4QPAIwBAAMABQheIj8aAOQBAAEABQj0IoQPAIwBAAIAAgiYFSQbAKUAAAAA.Dingleling:BAAALAAECgQICAABLAAECgUIBQAGAAAAAA==.Dirtybirdz:BAAALAAECgEIAQAAAA==.Discofusion:BAAALAAECggICAAAAA==.Discohunts:BAAALAADCgcIBwAAAA==.',Dk='Dkitty:BAAALAAECgcICgAAAA==.',Do='Doridanx:BAAALAAECgMIBQAAAA==.Dorttok:BAAALAAECgYIBgAAAA==.Dota:BAAALAAECgEIAgAAAA==.',Dr='Dracke:BAAALAADCggICAAAAA==.Drphìl:BAAALAADCgcIBwAAAA==.Drucifer:BAAALAAECgYIBgAAAA==.Drukqs:BAAALAADCgYICAAAAA==.',Du='Ducksicker:BAAALAAECgUIBgAAAA==.Dumbeh:BAAALAAECgEIAQAAAA==.Dumpsterbaby:BAAALAAECgYICAAAAA==.Dungen:BAAALAAFFAEIAQAAAA==.Durath:BAAALAADCgMIBAAAAA==.',Dy='Dyr:BAAALAADCgYIDAAAAA==.',['Dë']='Dëku:BAAALAADCggIFwAAAA==.',Ek='Ekim:BAAALAAECgMIBAAAAA==.',El='Ellínore:BAAALAADCggIDwAAAA==.Elspeth:BAAALAAECgYICQAAAA==.',Em='Emailed:BAECLAAFFIEOAAMQAAUIDBZaAQBbAQAQAAQIUxJaAQBbAQAUAAEIXACrDQA7AAAsAAQKgRQAAhAACAg+I1sHAOYCABAACAg+I1sHAOYCAAAA.Emberus:BAAALAAECgYIDAAAAA==.Embraces:BAEALAAECgYIDAABLAAFFAUIDgAQAAwWAA==.Emmeline:BAAALAADCggIDwAAAA==.',En='Ensaladatoss:BAAALAAECgcIDwAAAA==.Envy:BAAALAAECgIIBQAAAA==.',Er='Ervine:BAAALAAECgQIBQAAAA==.',Eu='Eupatorus:BAAALAAECgMIBQAAAA==.',Fa='Fatboybob:BAAALAADCgcIEQAAAA==.Fatfreddy:BAAALAADCgYICgAAAA==.Favi:BAAALAAECgYIBgAAAA==.',Fe='Festermight:BAACLAAFFIEMAAMVAAQI0xmHAQAzAQAVAAMIBCGHAQAzAQAWAAEIQgQLBQBgAAAsAAQKgSAAAhUACAgQJqcBAGMDABUACAgQJqcBAGMDAAAA.',Fi='Finnhammers:BAAALAADCgEIAQAAAA==.Finnhunter:BAAALAADCgMIAwAAAA==.Firenze:BAAALAADCgUIBQAAAA==.Fistingfirst:BAAALAADCgUIBQAAAA==.',Fl='Flippmode:BAAALAAECgIIAgAAAA==.Floorpov:BAAALAAECgYIBAAAAA==.',Fo='Fourth:BAAALAADCgUIBgAAAA==.Foxtrotwhisk:BAAALAADCggIDwAAAA==.',Fr='Fredrock:BAAALAAECgYICgAAAA==.Frostbane:BAAALAADCggIBwAAAA==.',Fu='Furyhots:BAAALAAECgMIAwAAAA==.Futiledeath:BAAALAADCgYIBgAAAA==.Fuzziewuzzie:BAAALAADCgQIBAAAAA==.Fuzzynuts:BAAALAADCgcIBwAAAA==.',Ga='Gaibe:BAAALAAECgYIDwAAAA==.Garahn:BAAALAADCgMIAwAAAA==.',Ge='Gelrous:BAAALAADCgcIBwAAAA==.Georgeknight:BAACLAAFFIEGAAMVAAMIPBLQAwDdAAAVAAMI1wjQAwDdAAAWAAEIYSPIBABjAAAsAAQKgRgAAxYACAi4JAQDAMkCABYABwhiJQQDAMkCABUACAjRF7kfAAcCAAAA.Georgemx:BAAALAAECgUIBQABLAAFFAMIBgAVADwSAA==.Gewch:BAAALAAECgQICgAAAA==.',Gi='Gingergiant:BAAALAAECgMIBAAAAA==.Girl:BAAALAADCggICAAAAA==.Gizzwizard:BAAALAADCgcIDAAAAA==.',Go='Goblindur:BAAALAADCgEIAQABLAAECgUIBQAGAAAAAA==.Gogeta:BAAALAAECgYIDAAAAA==.Gosaran:BAAALAAECgQIBAAAAA==.Gottraps:BAAALAAECgQIBQAAAA==.',Gr='Gradris:BAAALAAECgcIEwAAAA==.Greener:BAAALAAECgcIDwAAAA==.Grimtar:BAAALAAECgMIBgAAAA==.Grizpix:BAAALAAECgIIAQAAAA==.Groden:BAAALAADCgYIBgAAAA==.',Gu='Guillandrius:BAAALAADCggIBAAAAA==.Gunoil:BAAALAAECgMIBQABLAAECgYICgAGAAAAAA==.Guzzlord:BAAALAAECgYIBgAAAA==.',Ha='Haibeam:BAAALAAECgMIAwAAAA==.Hatake:BAAALAAECgEIAQAAAA==.Hazkalzlek:BAAALAADCgcIDgAAAA==.',He='Heil:BAAALAAECgEIAQABLAAECgUICQAGAAAAAA==.Heqqr:BAAALAAECgYIBgAAAA==.Herrimonk:BAAALAAECgQICAAAAA==.Hexual:BAAALAADCgIIAwAAAA==.',Hi='Himnick:BAACLAAFFIEQAAMDAAYIkR3EAAD5AQADAAUInB3EAAD5AQABAAIIfxvXAgC2AAAsAAQKgSAABAMACAg5JggFAAoDAAMABwgBJggFAAoDAAIAAggMJXkVAN0AAAEAAQgaJu89AG8AAAAA.',Ho='Hog:BAAALAADCgEIAQAAAA==.Hokoto:BAAALAADCgcICgAAAA==.Hollowsoul:BAAALAADCgIIAgAAAA==.Holmadic:BAAALAAECggIAwAAAA==.Holygems:BAAALAADCgMIAwAAAA==.Holyshocker:BAAALAADCggICAAAAA==.Honoree:BAAALAAECgIIAgAAAA==.Hope:BAAALAAECgYICwAAAA==.Hornzie:BAAALAAECgMIAwAAAA==.',Hu='Huntarino:BAAALAAECgYICQAAAA==.',['Hò']='Hòrnz:BAAALAADCgIIAgAAAA==.',Ia='Iamanevoker:BAAALAAECgYIBgAAAA==.',Ic='Ickly:BAAALAAECgYICgAAAA==.',Ie='Ieagle:BAAALAAECgEIAQAAAA==.',Il='Illuunni:BAAALAAECgUICgAAAA==.',Is='Ishelin:BAAALAAECgYIDgAAAA==.Ishin:BAAALAAECgEIAQAAAA==.',Iv='Ivlyth:BAAALAADCgUIBQAAAA==.',Iw='Iwasgard:BAAALAAECgMIBAAAAA==.',Ja='Jaraxxus:BAAALAAECgYICwAAAA==.',Jc='Jclaw:BAAALAADCgYIBgAAAA==.',Je='Jeddak:BAAALAAECgYICwAAAA==.Jelrous:BAAALAAECgMIAwAAAA==.Jennaortega:BAAALAAECgIIAgAAAA==.Jennzen:BAAALAADCggIDwAAAA==.Jeof:BAAALAAECgEIAQAAAA==.',Jl='Jlimremix:BAABLAAECoEUAAIXAAcIZCYoBQD8AgAXAAcIZCYoBQD8AgAAAA==.',Jo='Jojodk:BAAALAAECgUIBgAAAA==.',Ju='Juicester:BAAALAAECgYICQAAAA==.',Jx='Jx:BAAALAADCggICAAAAA==.',Jz='Jzimm:BAAALAAECgIIAgAAAA==.',Ka='Kaeorisera:BAECLAAFFIEMAAMWAAUIpBOwAAAfAQAWAAMIdxewAAAfAQAVAAMI9Qx+AwDvAAAsAAQKgSAAAxYACAhVI/oBAAADABYACAgGI/oBAAADABUACAgrGH0ZADICAAAA.Kairowarrior:BAAALAADCggIFAAAAA==.Kanatash:BAAALAAECgcIEAAAAA==.Kariden:BAAALAAECgEIAQAAAA==.Karnesia:BAAALAADCggIFgAAAA==.Karra:BAAALAAECgQIBQAAAA==.Kathqt:BAABLAAECoEUAAIOAAcIyCKaBwCvAgAOAAcIyCKaBwCvAgAAAA==.Kayliezra:BAAALAADCgcIBgABLAADCggIDwAGAAAAAA==.Kayssa:BAAALAAECggIDgAAAA==.',Ke='Keegan:BAAALAAECgcIEwAAAA==.Keiiyast:BAAALAADCgYIBgAAAA==.',Ki='Kiko:BAAALAADCggICQAAAA==.Kindatipsy:BAAALAAECgEIAgAAAA==.Kirasti:BAAALAAECgEIAQAAAA==.Kirkadh:BAAALAAECgMIAwABLAAFFAMIBQANAFIaAA==.Kisspr:BAAALAAECgYICwAAAA==.Kitkatt:BAAALAAECgMIBQAAAA==.Kitrix:BAAALAADCgQIBAAAAA==.Kizant:BAAALAADCggICAAAAA==.',Kl='Klizz:BAAALAAECgEIAQAAAA==.Klod:BAAALAADCgMIAwAAAA==.',Kn='Knobjob:BAAALAAECgYICgAAAA==.',Ko='Kogarasu:BAAALAAECgEIAQAAAA==.Korvold:BAAALAAECgIIAgAAAA==.',Kr='Kragarsf:BAAALAADCggIDwAAAA==.',Ku='Kupona:BAAALAAECgIIAgAAAA==.',La='Lall:BAAALAADCgcIEQAAAA==.Lamsauce:BAAALAADCgcICAAAAA==.Lastrang:BAAALAADCgIIAgABLAAECgUIBQAGAAAAAA==.Lateralusei:BAAALAADCgYIBgAAAA==.',Le='Left:BAAALAADCgUIBQABLAAECgEIAgAGAAAAAA==.Lenala:BAAALAAECgIIAgAAAA==.Leplynn:BAAALAADCgcICQAAAA==.Lesham:BAAALAAECgIIAgAAAA==.',Li='Liar:BAAALAADCgMIAwAAAA==.Lickwid:BAAALAADCggICAAAAA==.Life:BAAALAADCgcIBwABLAAECgMIAwAGAAAAAA==.Lightdeity:BAAALAAECgEIAQAAAA==.Limp:BAAALAAECgYICwAAAA==.Liquorbox:BAAALAADCggICAAAAA==.Littlelion:BAAALAAECggICgAAAA==.Littleteapot:BAAALAAECgIIAgAAAA==.Littlewig:BAAALAADCgcICAAAAA==.',Lo='Locknut:BAAALAADCgcIBwAAAA==.Lockzar:BAAALAAECgYIDAAAAA==.Lohrian:BAAALAAECgUIBQAAAA==.Lowiq:BAAALAAECgcICgAAAA==.',Lu='Lucentil:BAAALAADCgcIBgABLAADCggICQAGAAAAAA==.Luckycharmz:BAAALAAECgEIAQAAAA==.Lukayu:BAAALAAECgEIAQAAAA==.Luzrul:BAAALAAECgIIAgAAAA==.',Lv='Lv:BAAALAAECgcIEwAAAA==.',Ly='Lyka:BAAALAAECgMIBAAAAA==.',Ma='Madeinheaven:BAAALAAECgYICwAAAA==.Madorie:BAACLAAFFIEHAAIDAAMI8BSbAwAMAQADAAMI8BSbAwAMAQAsAAQKgSAAAgMACAghJJcCAEIDAAMACAghJJcCAEIDAAAA.Magden:BAAALAAECgQICAAAAA==.Magealb:BAAALAADCgcIBwAAAA==.Magecraftsp:BAAALAADCgYIBgABLAAECgcIBwAGAAAAAA==.Magefert:BAAALAAECgIIAgAAAA==.Magehunts:BAAALAAECgcIBwAAAA==.Magicshooter:BAAALAADCgQIBAAAAA==.Magistus:BAACLAAFFIEQAAIYAAYIfhcaAAA0AgAYAAYIfhcaAAA0AgAsAAQKgSAAAhgACAhCGHcJAAsCABgACAhCGHcJAAsCAAAA.Maisiffa:BAAALAADCgYIBgAAAA==.Makeout:BAAALAAECgMIAwAAAA==.Malevenn:BAAALAAECgcIDQAAAA==.Malicide:BAAALAADCgYIBgAAAA==.Mamisalami:BAAALAADCgcIEQAAAA==.Marmalady:BAACLAAFFIEQAAIZAAYIXhYlAABDAgAZAAYIXhYlAABDAgAsAAQKgSAAAhkACAghIwQBAA8DABkACAghIwQBAA8DAAAA.Masachi:BAAALAAECgYIBgABLAAFFAYIDAANAJEZAA==.Masakins:BAACLAAFFIEMAAINAAYIkRkZAAA+AgANAAYIkRkZAAA+AgAsAAQKgRgAAg0ACAgeI4MDANgCAA0ACAgeI4MDANgCAAAA.Matrebobe:BAAALAAECgcICQAAAA==.Maulo:BAAALAAFFAIIAwABLAAFFAYIDQAaAE8SAA==.Mauly:BAABLAAFFIENAAIaAAYITxJWAADtAQAaAAYITxJWAADtAQAAAA==.Maxum:BAAALAAECgEIAQAAAA==.Maynabloom:BAAALAAECgcIBwABLAAFFAUICQAXAKEKAA==.Maynamajo:BAAALAAECgEIAQABLAAFFAUICQAXAKEKAA==.Maynaminty:BAAALAAECgYIBgABLAAFFAUICQAXAKEKAA==.Maynaowl:BAACLAAFFIEJAAMXAAUIoQo8AQAdAQAXAAQILws8AQAdAQAbAAMIqgkfAQDxAAAsAAQKgRgAAxcACAhcI8IEAAUDABcACAhcI8IEAAUDABsACAg1GA0EAIsCAAAA.Maynayogurt:BAAALAADCgIIAgABLAAFFAUICQAXAKEKAA==.Mazzoraku:BAAALAADCgQIBAAAAA==.',Mc='Mclovin:BAAALAADCgcIDgAAAA==.',Me='Medspriest:BAAALAADCggICAAAAA==.Meltazor:BAAALAADCgcIBwAAAA==.',Mi='Midgert:BAACLAAFFIEGAAISAAUIuQfaAQBtAQASAAUIuQfaAQBtAQAsAAQKgRgAAhIACAhWHoERAI8CABIACAhWHoERAI8CAAAA.Mimint:BAAALAAFFAIIBAAAAA==.Mishima:BAAALAAECgQIBQAAAA==.Mistfit:BAAALAAECgIIAgAAAA==.Mizs:BAAALAADCgUIBQAAAA==.',Mo='Moadebe:BAAALAAECgMIBgAAAA==.Moghsothoth:BAAALAADCgcIBwAAAA==.Mojojojö:BAAALAADCgcIBwABLAADCggIDwAGAAAAAA==.Moktal:BAAALAAECgIIAgAAAA==.Moloki:BAAALAAECgQIBgAAAA==.Moogabooga:BAAALAAECgcIDwAAAA==.Moogster:BAAALAADCgcIBwABLAAECgcIDwAGAAAAAA==.Moogysupreme:BAAALAADCgIIAgAAAA==.',My='Myfursona:BAAALAADCggIFwAAAA==.Mynamegard:BAAALAAECgMIBAAAAA==.',['Mø']='Møuntie:BAAALAADCggIEAABLAAECgEIAQAGAAAAAA==.',['Mý']='Mýr:BAAALAAECgYIBgAAAA==.',Na='Naelyni:BAAALAADCgQIBAAAAA==.Naturalgas:BAAALAADCgQIBAAAAA==.Nazarick:BAAALAAECgMIBQAAAA==.',Ne='Negrumps:BAAALAADCgcIDgAAAA==.Nekthros:BAAALAAECgYIBwAAAA==.Neoheals:BAAALAAECgMIAwAAAA==.Nephair:BAAALAAECgUIBQAAAA==.Nestel:BAAALAADCgcIBwAAAA==.Nez:BAAALAADCggICAAAAA==.Nezdh:BAACLAAFFIEMAAIPAAYIfRlOAABTAgAPAAYIfRlOAABTAgAsAAQKgRgAAg8ACAgdJPADAEQDAA8ACAgdJPADAEQDAAAA.',Ni='Niamella:BAAALAADCgYIBgABLAADCggICQAGAAAAAA==.Nicholascage:BAAALAAECgcIEwAAAA==.Niers:BAAALAADCggICgAAAA==.',No='Noranthia:BAAALAADCggICAAAAA==.Norastria:BAAALAAECgEIAQAAAA==.',Ny='Nyllalock:BAAALAAECggIDQAAAA==.Nylmagicman:BAAALAAECgcIDAABLAAECggIDQAGAAAAAA==.',['Nÿ']='Nÿx:BAAALAADCgcIEAAAAA==.',Ob='Oberron:BAAALAADCggIDgABLAAECgcIBQAGAAAAAA==.',Ok='Okixs:BAAALAAECgcICQAAAA==.',On='Oneria:BAAALAADCggICAAAAA==.',Os='Oshamma:BAAALAAECgEIAgAAAA==.',Ot='Otterclaw:BAAALAADCggICAAAAA==.',Oz='Ozcane:BAAALAADCggICAABLAAECgEIAgAGAAAAAA==.Ozpal:BAAALAADCgYIBgABLAAECgEIAgAGAAAAAA==.Oztide:BAAALAAECgEIAgAAAA==.',Pa='Para:BAAALAAECgMIBgAAAA==.Pastorb:BAAALAAECgMIAwAAAA==.',Pe='Penelopi:BAAALAAECgIIAgAAAA==.Penguinia:BAAALAADCggICAAAAA==.Pensman:BAAALAAECgYICQAAAA==.Pew:BAAALAADCggIFwAAAA==.Pewpewlessqq:BAAALAADCggIFgAAAA==.',Ph='Phazer:BAAALAADCggIEAAAAA==.Phishfude:BAAALAADCgcIEQAAAA==.Phukitol:BAAALAADCgIIAgAAAA==.',Pi='Pigeonkick:BAAALAAECgIIBAAAAA==.Piratealex:BAAALAAECgYIBgABLAAECggIGAAEAGAaAA==.',Pl='Plexadin:BAAALAAECgIIAwAAAA==.',Po='Podakk:BAAALAAECgMIAwAAAA==.Poex:BAAALAAECgYICQAAAA==.Posternutbag:BAAALAADCgUICQAAAA==.',Pr='Praetormalus:BAAALAAECgMIAwAAAA==.Prepotenté:BAAALAADCggICAAAAA==.',Ps='Psymon:BAAALAAECgIIAgAAAA==.',Pt='Ptheve:BAACLAAFFIEPAAIRAAUI3yAxAAAdAgARAAUI3yAxAAAdAgAsAAQKgSAAAhEACAiVJpsAAIIDABEACAiVJpsAAIIDAAAA.',Pu='Pundemic:BAABLAAECoEUAAMBAAgI9xgBEQB9AQADAAgIzRAwHwC4AQABAAYIVRQBEQB9AQAAAA==.',Pw='Pwiestman:BAAALAADCggICAAAAA==.',Qu='Quantrank:BAAALAAECgQIBwAAAA==.',Ra='Raei:BAABLAAECoEgAAIUAAgIhQRhPAAjAQAUAAgIhQRhPAAjAQAAAA==.Raewyn:BAAALAAECgQICgAAAA==.Ragestrasz:BAAALAAECgQIBgAAAA==.Raladead:BAAALAAECgYIDQAAAA==.Ramchi:BAAALAAECgYIDAAAAA==.Ramhorn:BAAALAAECgIIAgAAAA==.Raythe:BAAALAAECgEIAQAAAA==.',Re='Reckless:BAAALAAECgEIAgAAAA==.Rediixx:BAAALAAECgEIAQAAAA==.Reformedbtw:BAAALAAECgcIDAAAAA==.Reikochet:BAAALAAECgIIAgAAAA==.Relgeiz:BAAALAADCgUIBQAAAA==.Remain:BAABLAAECoEXAAIKAAgIuh5ECACdAgAKAAgIuh5ECACdAgAAAA==.Render:BAAALAAECgEIAQAAAA==.Restorement:BAAALAADCggICAAAAA==.',Ri='Ricê:BAAALAADCgYIBgABLAAECgYIDQAGAAAAAA==.Ride:BAAALAAECgIIAgAAAA==.Riizzo:BAAALAAECgYIBwAAAA==.Rimz:BAAALAADCgIIAgAAAA==.Riotous:BAAALAADCgQIBAABLAAECgEIAgAGAAAAAA==.Rixi:BAAALAAECgMIBQAAAA==.',Ro='Roadkillz:BAAALAAECgYICgAAAA==.Robinsouls:BAAALAADCggIDwAAAA==.Roelly:BAAALAAECgEIAQAAAA==.Roguh:BAAALAADCgcIBwAAAA==.Rokhunt:BAACLAAFFIEJAAILAAUI+iMNAAAuAgALAAUI+iMNAAAuAgAsAAQKgRgAAgsACAhNJsUAAHoDAAsACAhNJsUAAHoDAAAA.Rothkar:BAAALAADCgcICgAAAA==.Rothmagus:BAAALAADCgQIBAAAAA==.Rothmarak:BAAALAADCgcIDAAAAA==.Rougarou:BAAALAADCgYIBgAAAA==.Rougetard:BAAALAAECgYIDAAAAA==.Roweana:BAAALAAECgEIAQAAAA==.',Ru='Ruinous:BAAALAADCgcIBwABLAAECgEIAgAGAAAAAA==.Rumdumb:BAAALAAECgYICgAAAA==.',['Rî']='Rîcê:BAAALAAECgYIDQAAAA==.',Sa='Sabelorn:BAAALAAECgcICgAAAA==.Saltarius:BAAALAADCggICAAAAA==.Sanaroth:BAAALAADCgcIDgAAAA==.Sanctusmalus:BAAALAADCggIDgAAAA==.Satanicsally:BAAALAADCgYIBgAAAA==.Savycat:BAABLAAECoEQAAMLAAgI8h+NDwB0AgALAAcIECGNDwB0AgAKAAQI2R6mIABcAQAAAA==.',Sc='Scene:BAAALAADCggIDgAAAA==.Scorchedsand:BAAALAADCgYIBgAAAA==.Scrambls:BAAALAADCgEIAQAAAA==.Screwheals:BAAALAAECgUIBQAAAA==.',Se='Seandawn:BAAALAADCgcIBwAAAA==.Secondwind:BAABLAAECoEVAAILAAgIhB9FBwDtAgALAAgIhB9FBwDtAgAAAA==.Secretions:BAEALAAECgQIBwAAAA==.Selathiel:BAAALAADCggICAAAAA==.Sellene:BAABLAAFFIEFAAINAAMIUhpcAQAcAQANAAMIUhpcAQAcAQAAAA==.Sellina:BAAALAADCgUIBQABLAAFFAMIBQANAFIaAA==.Senorbang:BAAALAAECgQIBQAAAA==.Sensei:BAAALAAECgYICAAAAA==.Sep:BAAALAAECgcIDAAAAA==.',Sh='Shadowflare:BAAALAADCggIGgAAAA==.Shadowtwist:BAAALAADCggIDwABLAAECgMIBQAGAAAAAA==.Shakirra:BAAALAADCgMIBQAAAA==.Shalveris:BAAALAADCggICAAAAA==.Shamantrufy:BAAALAAECgEIAQAAAA==.Shamchu:BAAALAADCggICAAAAA==.Shaolinhunk:BAAALAAECgcICgAAAA==.Shelandria:BAACLAAFFIEMAAMFAAUIkxC3AAB7AQAFAAQIPRS3AAB7AQAcAAIIJgEQAgCgAAAsAAQKgR4AAwUACAjXI7sDAAoDAAUACAjXI7sDAAoDABwACAitDCkGALgBAAAA.Shiftykrates:BAAALAAECgcICgAAAA==.Shiko:BAEALAAECgcIDwAAAA==.Shmevlin:BAAALAAECgYIDQAAAA==.Shockrates:BAAALAAECgYIBgAAAA==.Shreker:BAAALAAECgcIEwAAAA==.Shrig:BAAALAAECgYICAAAAA==.',Si='Sidebo:BAAALAAECgEIAgAAAA==.Siler:BAAALAADCgYICAAAAA==.Sirn:BAAALAAECgEIAQAAAA==.',Sk='Skeeto:BAAALAAECgMIBAAAAA==.',Sl='Slimes:BAAALAADCgQIBwAAAA==.Slimxx:BAAALAAECgYICwAAAA==.Slxve:BAAALAADCggIDwAAAA==.Slytherin:BAAALAAECgQIBAAAAA==.',Sn='Snaven:BAAALAADCgYICQAAAA==.Sneggs:BAAALAADCgYIDgAAAA==.Snickers:BAAALAADCgMIAwABLAAECgMIAwAGAAAAAA==.Snipermonkey:BAAALAAECgcICgAAAA==.',So='Soriko:BAAALAAECgQIBwAAAA==.Sorynna:BAAALAADCgIIAgAAAA==.Soul:BAAALAAECgcIEwAAAA==.',Sp='Sparkleheals:BAAALAADCgMIBgAAAA==.Spin:BAAALAAECgMIAwAAAA==.',St='Stedk:BAAALAAECgYIBgAAAA==.Stinknugget:BAAALAAECgYICgAAAA==.Straightjork:BAAALAAECgIIAgAAAA==.Stygwyggyr:BAAALAAECgcIBwAAAA==.',Su='Sugarzcoat:BAAALAAECgMIAwAAAA==.Sulphurous:BAAALAAECgYICwAAAA==.Supernovi:BAEALAAFFAIIAgAAAA==.',Sw='Swampdonkyy:BAAALAADCgYIBgAAAA==.Swole:BAAALAADCgUIBwAAAA==.Swsandy:BAACLAAFFIELAAIIAAUIex6IAAD4AQAIAAUIex6IAAD4AQAsAAQKgRgAAggACAh/JvQAAHMDAAgACAh/JvQAAHMDAAAA.',Sy='Sydur:BAAALAADCgIIAgABLAAECgcIDgAGAAAAAA==.Syenite:BAAALAADCgIIAgAAAA==.Sylarr:BAAALAAECgEIAQAAAA==.Sylbris:BAAALAADCgcIBwAAAA==.Syler:BAAALAAECgcIDgAAAA==.Synxy:BAAALAAECggIBQAAAA==.Syrixil:BAAALAADCgcIBwABLAAECgQIBQAGAAAAAA==.',Ta='Takkar:BAAALAADCgMIAwAAAA==.Talfie:BAAALAAECgYICgAAAA==.Talphy:BAAALAADCgUIBQAAAA==.Talren:BAAALAAECgYIEAAAAA==.Tanavast:BAAALAAECgEIAQAAAA==.Tasari:BAACLAAFFIEMAAIaAAYIHiUKAACgAgAaAAYIHiUKAACgAgAsAAQKgRgAAhoACAiKJigAAJADABoACAiKJigAAJADAAAA.',Te='Teekhunt:BAAALAAECgIIAgAAAA==.Tekain:BAAALAAECgQIBQAAAA==.Terkeei:BAAALAADCgYIBgAAAA==.',Th='Thedeadlypug:BAAALAAECgMIBQAAAA==.Thiccbolts:BAAALAAFFAIIAgAAAA==.Thots:BAAALAADCgUIBQAAAA==.Thrallblade:BAAALAAECgIIBAAAAA==.',Ti='Tich:BAAALAADCgcICwAAAA==.Tichu:BAAALAADCggIEQAAAA==.Tifelia:BAAALAADCggIFQAAAA==.Tikí:BAACLAAFFIEMAAMOAAYIkRPWAAC9AQAOAAUInxDWAAC9AQAZAAIIbgkpBAChAAAsAAQKgRgAAw4ACAhKIxUOACsCAA4ABggbIhUOACsCABkACAjiEbQHANsBAAAA.Tiniqueeni:BAAALAAECgMIBQABLAAECggIGwAdAFkYAA==.',Tk='Tkdtwo:BAAALAAECgUIBQAAAA==.',To='Tohká:BAAALAAECgYIBgAAAA==.Tonyz:BAAALAAECgIIAgAAAA==.Torrential:BAAALAADCggIDwAAAA==.Torthie:BAACLAAFFIEMAAMSAAYIBRyiAAD2AQASAAUIaCCiAAD2AQATAAEIFAYXAgBWAAAsAAQKgRgAAxIACAhJJH4HAAYDABIACAhJJH4HAAYDABMAAQiiFQ4MAEUAAAAA.Tothblocks:BAACLAAFFIEQAAIeAAYIXRY6AAAkAgAeAAYIXRY6AAAkAgAsAAQKgSAAAh4ACAgIJJABADkDAB4ACAgIJJABADkDAAAA.Toxaaris:BAAALAAECgEIAQAAAA==.',Tr='Tripp:BAAALAAECgMIBQAAAA==.Trollerella:BAAALAAECgYIEQAAAA==.Trolljaboy:BAAALAADCggICAABLAAECgYIEQAGAAAAAA==.Tronxx:BAAALAADCgEIAQAAAA==.Troxigar:BAAALAAECgYICwAAAA==.Tru:BAAALAADCgIIAgAAAA==.',Tu='Tulips:BAEALAAECgYIBgABLAAFFAIIAgAGAAAAAA==.',Tv='Tverdymonk:BAAALAAECgQIBwAAAA==.Tverdypally:BAAALAAECgMIAwABLAAECgQIBwAGAAAAAA==.Tverdywar:BAAALAADCgUICAABLAAECgQIBwAGAAAAAA==.',Tw='Twistkun:BAAALAAECgMIBQAAAA==.',Ty='Tyko:BAAALAAECgYIDQAAAA==.Tym:BAAALAADCgYIBgAAAA==.Tymara:BAAALAAECgEIAQAAAA==.Tyrdrop:BAAALAADCgcIDAAAAA==.Tyrelsa:BAAALAAECgIIBAAAAA==.',['Tå']='Tånner:BAAALAAECgYICAAAAA==.',['Tó']='Tóxìc:BAAALAAECgMIBwAAAA==.',Un='Unclerod:BAAALAAECgYICQAAAA==.Unfixable:BAAALAAFFAEIAQAAAQ==.Unholyshart:BAAALAADCgYIBgABLAADCggIDwAGAAAAAA==.Unholystuff:BAAALAADCgUIBQAAAA==.',Ur='Urshac:BAAALAAECgMIAwAAAA==.',Uu='Uunfar:BAAALAAECgcIDwAAAA==.',Uw='Uwushock:BAAALAADCggIDwAAAA==.',Va='Vadavaka:BAAALAADCgcIBgAAAA==.Valmortis:BAAALAAECgIIAgAAAA==.Valtara:BAAALAAECgYIBgAAAA==.Vanthari:BAAALAAECgYIDQAAAA==.Vato:BAAALAADCgYICQAAAA==.',Ve='Veida:BAAALAADCgMIAwAAAA==.',Vi='Viiv:BAAALAADCgIIAgAAAA==.Viper:BAAALAAECgcIEgAAAA==.',Vl='Vlad:BAAALAAECgYIBgAAAA==.',Vo='Vosslar:BAAALAAECgUICQAAAA==.',['Vî']='Vîper:BAAALAADCggIDQAAAA==.',Wa='Waarrlockk:BAACLAAFFIEMAAMDAAYIxxlbAABOAgADAAYIxxlbAABOAgABAAIIZRzDAgC3AAAsAAQKgRgABAMACAgaJhYBAG0DAAMACAjHJRYBAG0DAAEABgjKJIQHAO0BAAIAAggvGg8aAK4AAAAA.Walrusrider:BAAALAADCgcIBwAAAA==.Wanred:BAAALAADCggICAAAAA==.Wassy:BAAALAAECgYICgAAAA==.Wazzabi:BAAALAAECgQIBAAAAA==.',We='Wealdstone:BAAALAAECgQIBgAAAA==.Wemgobyama:BAAALAAECgUIBgAAAQ==.',Wh='Whepdemon:BAAALAAECgEIAQAAAA==.',Wi='Wildtotem:BAAALAADCggIDgAAAA==.Wizartrees:BAAALAADCgcIBwAAAA==.Wizsera:BAABLAAECoEYAAIOAAYIHCMzDABMAgAOAAYIHCMzDABMAgAAAA==.',Wo='Womboree:BAAALAAECgYICQAAAA==.',Wr='Wrathion:BAAALAAECgQIBQAAAA==.',Xa='Xalthazar:BAAALAADCgYIBgAAAA==.',Ya='Yakaroni:BAAALAADCgMIAwAAAA==.',Ye='Yellowheal:BAAALAADCgcIDAAAAA==.Yeofdh:BAAALAADCgcIBwAAAA==.',Yk='Yki:BAAALAAECgMIBQAAAA==.Ykim:BAAALAADCgQIBAAAAA==.',Yl='Ylvä:BAAALAADCgEIAQABLAADCgYIBgAGAAAAAA==.',Yu='Yukarna:BAAALAAECgQIBQAAAA==.',Za='Zaafkiel:BAAALAAECgIIAgAAAA==.Zainbrain:BAEALAADCgcIBwAAAA==.Zaraphym:BAAALAAECgIIAgAAAA==.',Ze='Zeats:BAAALAAECgYIBgABLAAECggIGAAfAPolAA==.Zedrea:BAAALAADCggICwAAAA==.Zeiya:BAAALAADCgYIBgAAAA==.Zelgadis:BAAALAADCgMIBgAAAA==.Zephyrine:BAAALAAECgYICAAAAA==.Zerfallen:BAAALAADCgUIBQABLAAECgMIAwAGAAAAAA==.',Zh='Zhuzhu:BAAALAADCggIDgAAAA==.',Zi='Zigy:BAAALAAECgcIDwAAAA==.Zippydoo:BAAALAAECgYIEgAAAA==.',Zu='Zukko:BAAALAAECgYICQAAAA==.Zulkaris:BAAALAADCgcIBwAAAA==.Zuroxxar:BAAALAADCgYICQABLAAECgIIAgAGAAAAAA==.',Zy='Zynny:BAAALAADCgcIDAAAAA==.',['Åm']='Åmaranth:BAAALAADCgEIAQAAAA==.',['Ìl']='Ìl:BAABLAAECoEYAAIfAAgI+iVqAQB1AwAfAAgI+iVqAQB1AwAAAA==.',['Ïn']='Ïnno:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end