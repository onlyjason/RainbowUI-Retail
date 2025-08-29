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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Hunter-Marksmanship','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','DemonHunter-Havoc','Priest-Holy','Paladin-Protection','Paladin-Holy','Evoker-Preservation','Warrior-Protection','Warrior-Fury','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Mage-Arcane','Evoker-Devastation','Mage-Fire','Druid-Feral','Druid-Balance','Mage-Frost','DeathKnight-Unholy','Hunter-Survival','DemonHunter-Vengeance','Shaman-Restoration','Rogue-Subtlety','Druid-Restoration','Priest-Discipline','Warrior-Arms','Hunter-BeastMastery',}; local provider = {region='US',realm='Thaurissan',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abcede:BAAALAADCggIDgABLAAECgIIAgABAAAAAA==.',Ag='Agonyawaits:BAAALAADCgcIBwAAAA==.',Ai='Aica:BAABLAAECoEUAAICAAgIlRwaBwDiAgACAAgIlRwaBwDiAgAAAA==.Aidrafox:BAABLAAECoEXAAIDAAgICSNkBAD1AgADAAgICSNkBAD1AgABLAAECggIFAAEAJYXAA==.Aims:BAAALAADCgEIAQAAAA==.Aisa:BAACLAAFFIEJAAMFAAQIAhXhAQBhAQAFAAQIFxHhAQBhAQAGAAIIPiF/AQDFAAAsAAQKgRgABAUACAhzJaABAF0DAAUACAhpJKABAF0DAAYABwjnIRYDAEsCAAcAAgiMFyEaAK4AAAAA.Aish:BAACLAAFFIEKAAIIAAUI7CAbAAAdAgAIAAUI7CAbAAAdAgAsAAQKgRcAAggACAimJsQAAIcDAAgACAimJsQAAIcDAAAA.',Al='Aleson:BAAALAADCgcIDQAAAA==.Alexgreece:BAAALAAECgMIAwABLAAFFAUICgACACUkAA==.Alirann:BAAALAAECggIDgAAAA==.Alvln:BAABLAAECoEXAAIJAAgIUR4YDwCdAgAJAAgIUR4YDwCdAgAAAA==.',Am='Ampuzzible:BAAALAAECgYIDwAAAA==.',An='Andyrios:BAAALAAECgEIAQAAAA==.Aniceguy:BAAALAADCgYICgAAAA==.',Ap='Apoplectic:BAAALAADCgcIDAAAAA==.',Aq='Aquaila:BAAALAAECgIIAgAAAA==.',Ar='Aralinya:BAABLAAECoEWAAIKAAgIAxSoFAALAgAKAAgIAxSoFAALAgAAAA==.Aralynda:BAAALAAECgcIDwAAAA==.Ardentflame:BAAALAADCgcIBwAAAA==.Arleric:BAABLAAECoEUAAMIAAgIUx7UFABXAgAIAAgIuRnUFABXAgALAAMIKCQYEQA7AQAAAA==.Arlerknight:BAAALAADCgIIAgAAAA==.',As='Asperonia:BAACLAAFFIEKAAIMAAUIBA6YAACyAQAMAAUIBA6YAACyAQAsAAQKgRgAAwgACAgUIPocABUCAAgABghPHvocABUCAAwACAj1EjcMAAMCAAAA.Astinous:BAAALAADCggIDwAAAA==.Astrid:BAABLAAECoEXAAINAAgI+R01AwCHAgANAAgI+R01AwCHAgAAAA==.Astynax:BAAALAADCggICAAAAA==.',Au='Auroborealis:BAAALAAECgIIAwAAAA==.Ausfirestorm:BAAALAAECgIIAwAAAA==.Auten:BAAALAADCgYIBgAAAA==.',Av='Avell:BAAALAAECgYIDAAAAA==.Avocardio:BAAALAADCgQIBAAAAA==.',Aw='Awesemo:BAAALAADCggICAAAAA==.Awesomatix:BAAALAAECgcIEAAAAA==.',Ax='Axiomatic:BAAALAAECgMIBgAAAA==.',Ay='Ayampenyet:BAAALAADCgcIBwAAAA==.',Az='Azazyle:BAAALAAECgYICgAAAA==.Azraelin:BAAALAADCgEIAQAAAA==.Azsharia:BAAALAAECgcIDQAAAA==.Azterixtwo:BAAALAADCgMIBQAAAA==.',Ba='Baicngcat:BAAALAADCgYIBgAAAA==.Barackobamyh:BAACLAAFFIEIAAIOAAUIcQmjAABwAQAOAAUIcQmjAABwAQAsAAQKgRgAAg4ACAiZHT4EALYCAA4ACAiZHT4EALYCAAAA.Baylan:BAAALAAECgYICAAAAA==.',Be='Beeffork:BAAALAAECgIIAwAAAA==.Beerofftap:BAAALAAECgMIBAAAAA==.Betrayr:BAABLAAECoEUAAIJAAgI1B7iDAC7AgAJAAgI1B7iDAC7AgAAAA==.Beàr:BAAALAAECgEIAQAAAA==.',Bi='Bigbadbaka:BAACLAAFFIEHAAIPAAUIihGjAADQAQAPAAUIihGjAADQAQAsAAQKgRgAAg8ACAi3JZ0AAIIDAA8ACAi3JZ0AAIIDAAAA.Bigdumpy:BAAALAADCggICAAAAA==.Biscuitpaw:BAAALAADCggIFgAAAA==.',Bl='Blackdrum:BAAALAAECgMIBQAAAA==.Blazez:BAABLAAECoEWAAIIAAgIRiWMAwBMAwAIAAgIRiWMAwBMAwAAAA==.Blazingbeard:BAAALAAECgYIDwAAAA==.Blekorc:BAAALAAECgMIAwAAAA==.Blosswyn:BAAALAADCgYICwAAAA==.',Bo='Bogart:BAAALAAECgcIEAAAAA==.Bootieeater:BAAALAADCgcIDQAAAA==.Bootiesweat:BAAALAAECgYIBgAAAA==.',Br='Brawney:BAAALAADCggIDgAAAA==.Brexan:BAAALAADCgIIAgAAAA==.',Bu='Buibuis:BAACLAAFFIEJAAIQAAUIyRaLAACnAQAQAAUIyRaLAACnAQAsAAQKgRgAAhAACAiTIEECAPsCABAACAiTIEECAPsCAAAA.Buikyah:BAABLAAECoEUAAMRAAgI5w4GCgCiAQARAAgIkQ4GCgCiAQASAAMI/BBQYQC7AAABLAAFFAUICQAQAMkWAA==.Bunnyhop:BAAALAAECgYICwAAAA==.Buysfeetpics:BAABLAAECoEWAAITAAgIuyCnCQDpAgATAAgIuyCnCQDpAgAAAA==.',['Bâ']='Bânê:BAAALAADCgcIBwAAAA==.',Ca='Calx:BAAALAAECgQIBAAAAA==.Candyman:BAAALAADCgUIBQAAAA==.Canis:BAAALAADCgEIAQAAAA==.Cannicus:BAABLAAECoEYAAITAAgIzCB9CQDrAgATAAgIzCB9CQDrAgAAAA==.Cannimix:BAAALAAECgEIAQAAAA==.Careßear:BAAALAAECgYIBgABLAAFFAUIBgAUABMHAA==.Castingcowch:BAAALAAECgEIAQAAAA==.Castrial:BAACLAAFFIEHAAITAAQIEyB3AQCWAQATAAQIEyB3AQCWAQAsAAQKgRgAAxMACAhdJd4BAF0DABMACAhdJd4BAF0DABUAAQitFpkLAEgAAAAA.Catpie:BAAALAAECgYICQAAAA==.',Ce='Celavii:BAAALAAECgcIEAAAAA==.',Ch='Chakrafool:BAAALAADCgEIAQAAAA==.Chappell:BAAALAADCggIDQAAAA==.Chargeplox:BAAALAAECgMIAwAAAA==.Chen:BAABLAAECoEUAAIEAAgI0xmACgCsAgAEAAgI0xmACgCsAgABLAAFFAQIBwATABMgAA==.Cherrybelles:BAABLAAECoEVAAIKAAgIcA6AGwDKAQAKAAgIcA6AGwDKAQAAAA==.Chiikawa:BAAALAAECgYIBgAAAA==.Chillicheese:BAAALAAECgMIBAAAAA==.Chinnohoho:BAAALAAECgYIDgAAAA==.Choppy:BAAALAAECgQIBgAAAA==.',Ci='Cigsinside:BAABLAAECoEUAAICAAgIrSGOBgDtAgACAAgIrSGOBgDtAgABLAAFFAUICgACACUkAA==.Cindermoon:BAAALAADCggICAAAAA==.',Co='Colena:BAEALAAECgcIEAAAAA==.Conzy:BAAALAAECgEIAQAAAA==.Corbulus:BAABLAAECoEVAAIIAAgIWhmpGAA1AgAIAAgIWhmpGAA1AgAAAA==.Cousindk:BAAALAAECgYIDQAAAA==.',Cr='Crispymage:BAAALAAECgYICAAAAA==.Cronus:BAAALAAECgcIDgAAAA==.Cruxes:BAAALAAECggIDgAAAA==.',Cy='Cyndi:BAAALAAECgIIAgAAAA==.Cynthia:BAAALAAECgcIAgAAAA==.',Da='Dabujamaan:BAAALAADCgYIBgAAAA==.Dannyxie:BAAALAADCgMIAwAAAA==.Darcious:BAAALAAECgIIAgABLAAECgcIEAABAAAAAA==.Darkopi:BAAALAAECgIIAgABLAAECgcIEAABAAAAAA==.Davidchoi:BAABLAAECoEUAAIKAAgI5hsNBwC7AgAKAAgI5hsNBwC7AgAAAA==.',De='Deadlly:BAAALAAECgQIBwAAAA==.Deathdrum:BAAALAAECgMIAwAAAA==.Deathrocks:BAAALAAECgMIBwAAAA==.Deejaboo:BAAALAAECgIIAQAAAA==.Delenn:BAAALAADCgcIDQAAAA==.Demondrum:BAAALAADCggIDgAAAA==.Derfderf:BAAALAADCggIDgAAAA==.Destcrypt:BAAALAAECgYICwAAAA==.',Di='Dinkwink:BAAALAADCgcIDgAAAA==.Divïne:BAAALAAECgYICAAAAA==.',Do='Dovahkiinn:BAAALAADCgcIBwAAAA==.',Dr='Draconn:BAAALAAECggIAwAAAA==.Drael:BAAALAAECggIDQAAAA==.Drethalis:BAAALAADCgcIFAAAAA==.Drewidstorm:BAAALAADCggIDgABLAAECgIIAwABAAAAAA==.Drewsoario:BAAALAADCgUIBQABLAAECgIIAwABAAAAAA==.Drewstormio:BAAALAAECgIIAwAAAA==.Drohgba:BAAALAAECgYICQAAAA==.',Ds='Dsdh:BAACLAAFFIEGAAIJAAQIsRRCAQB+AQAJAAQIsRRCAQB+AQAsAAQKgRgAAgkACAgQJYkCAFwDAAkACAgQJYkCAFwDAAAA.',Du='Dulang:BAAALAAECgYICgAAAA==.',Dy='Dyingheart:BAAALAAECgIIAwAAAA==.',['Dé']='Déáth:BAAALAAECgEIAgAAAA==.',['Dë']='Dëxy:BAAALAAECggICAAAAA==.',Ec='Ectruby:BAABLAAECoEWAAIWAAgIFhjIBABqAgAWAAgIFhjIBABqAgAAAA==.',El='Elertricsoup:BAAALAAECgIIAgAAAA==.Elunaria:BAAALAAECgQIBAABLAAECgYICAABAAAAAA==.Elwarlocko:BAAALAAECgQIBwAAAA==.Elyndre:BAACLAAFFIEGAAIUAAUIEwcQAQCDAQAUAAUIEwcQAQCDAQAsAAQKgRcAAhQACAhrJK8BAEwDABQACAhrJK8BAEwDAAAA.',Em='Emberis:BAAALAAECgIIAgAAAA==.Emopapa:BAAALAAECgYICwAAAA==.',En='Endari:BAAALAAFFAIIAgAAAA==.',Ep='Epod:BAAALAAECgYICwAAAA==.',Es='Esrei:BAAALAADCggICAAAAA==.Essdee:BAAALAAECgEIAQAAAA==.',Eu='Eugenie:BAAALAAECgEIAQAAAA==.',Fa='Faenirel:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.Faithful:BAAALAAECgEIAQAAAA==.Famine:BAAALAADCggIDgABLAAECgYICAABAAAAAA==.',Fe='Feign:BAAALAAECgYIBgABLAAFFAUICgAXAHkjAA==.Felboii:BAAALAAECgMIAwAAAA==.Feldaddy:BAAALAADCgMIAwAAAA==.Felfie:BAAALAADCgIIAgAAAA==.',Ff='Ffen:BAAALAAECgYICwAAAA==.',Fi='Filterkings:BAAALAAECgYIBgAAAA==.Fired:BAAALAADCgYICgAAAA==.',Fj='Fjordúr:BAAALAADCgcICAAAAA==.',Fr='Frankadelic:BAAALAAECgQICQAAAA==.Frankie:BAAALAADCggICAAAAA==.Freezenuts:BAAALAADCgEIAQABLAADCgEIAQABAAAAAA==.Frodolol:BAABLAAECoEXAAQTAAgI/CC4EwB3AgATAAcI5h64EwB3AgAYAAcIjxnFDQDrAQAVAAcIZhe+AgC/AQAAAA==.Frogwash:BAAALAAECgMIBAAAAA==.Frostik:BAABLAAECoEVAAIZAAgIXiGKAgDfAgAZAAgIXiGKAgDfAgAAAA==.',Fu='Fufamace:BAAALAADCgMIAwAAAA==.Furmonger:BAAALAADCgQICAAAAA==.',Fw='Fwoopie:BAAALAAECgYICwAAAA==.',Fy='Fya:BAAALAAECgMIBAAAAA==.',['Fè']='Fèárfàctóry:BAAALAAECgEIAQAAAA==.',['Fó']='Fóx:BAAALAADCggIEAAAAA==.',Ga='Gahiji:BAAALAADCgIIAgAAAA==.Gannina:BAAALAAECgcIEAAAAA==.',Ge='Genë:BAAALAADCgcICQAAAA==.',Gi='Gillemon:BAAALAADCggIEAAAAA==.Givre:BAAALAADCgIIBAAAAA==.',Gl='Glnu:BAAALAAECgYICgAAAA==.',Go='Gomron:BAAALAADCggIDgAAAA==.',Gr='Graoul:BAAALAAECgcIEgAAAA==.Greatboatsby:BAACLAAFFIEJAAINAAUI3w+BAAC+AQANAAUI3w+BAAC+AQAsAAQKgRgAAg0ACAhxItkAAB4DAA0ACAhxItkAAB4DAAAA.Greemlin:BAABLAAECoEUAAIEAAgIlhcZDQB7AgAEAAgIlhcZDQB7AgAAAA==.Grimlocke:BAAALAAECgMIAwAAAA==.Grindelwald:BAAALAAECgYIEwAAAA==.Gryffin:BAAALAAECgQICAAAAA==.',Gu='Gugudan:BAAALAAECgYICwAAAA==.Guiltyclown:BAAALAAECgQICgAAAA==.Gunnina:BAAALAAECgIIAgAAAA==.Gutt:BAAALAAECgEIAQAAAA==.Gutts:BAAALAAECgQIBAAAAA==.',Ha='Halmoni:BAAALAADCggIDwAAAA==.Haziq:BAAALAADCgUIBQAAAA==.',He='Hert:BAAALAAECgIIAgAAAA==.',Ho='Holybaicng:BAAALAADCgUIBQAAAA==.Holyshaddow:BAAALAADCgQIBAAAAA==.Hoothootsekz:BAAALAAECgYIDwAAAA==.',Hu='Hugetoes:BAAALAAECgMIBgAAAA==.',Hw='Hwhisashaman:BAAALAADCgIIAgAAAA==.',Ic='Icebreak:BAAALAAECgcICgAAAA==.',Id='Idigit:BAAALAADCgYICgAAAA==.',Im='Imsomad:BAAALAAECgEIAQAAAA==.',In='Insaneshane:BAAALAADCgYIBgAAAA==.',Is='Isee:BAAALAAECgIIAgAAAA==.Isopod:BAAALAADCggICAAAAA==.Isvelte:BAAALAAECgcICgAAAA==.',It='Itadaki:BAAALAAECgEIAQAAAA==.',Ja='Jackee:BAAALAAECgYICAAAAA==.Jarshealin:BAAALAADCgMIAwAAAA==.Jasmean:BAAALAAECgcIEAAAAA==.Jathia:BAAALAADCgUIBQAAAA==.',Je='Jennatelia:BAAALAADCgIIAwAAAA==.',Jo='Joeru:BAABLAAECoEVAAIaAAgIhRhbAQCQAgAaAAgIhRhbAQCQAgAAAA==.Johndruid:BAAALAADCgcIBwABLAAECggIDwABAAAAAA==.Johnthefury:BAAALAADCgcIBwABLAAECggIDwABAAAAAA==.Johnthemonk:BAAALAAECggIDwAAAA==.Jordoom:BAAALAADCggIDgAAAA==.Joruncity:BAAALAADCggIDgAAAA==.',Js='Jsdnfweiwwee:BAAALAAECgEIAQAAAA==.',Ju='Justmeta:BAAALAAECgcIDQAAAA==.Justrat:BAABLAAECoEYAAIDAAgIax1mBwCvAgADAAgIax1mBwCvAgAAAA==.',Jz='Jzs:BAAALAADCgIIAgABLAAECgMIBQABAAAAAA==.',Ka='Kafra:BAAALAAECgYICgAAAA==.Katalen:BAAALAAECgQIBQAAAA==.Kayalock:BAABLAAECoEVAAQFAAgI3Rp4CwCTAgAFAAgI3Rp4CwCTAgAHAAMIHgjuGQCwAAAGAAIIXQkyPQByAAAAAA==.Kazendar:BAAALAAECgEIAQAAAA==.',Ke='Kerinne:BAAALAADCggIDQAAAA==.Keriso:BAAALAAECgIIAwAAAA==.Kerìnne:BAAALAAECgUIBQAAAA==.Ketupaat:BAABLAAECoEUAAIbAAgIygswDgBcAQAbAAgIygswDgBcAQAAAA==.Kevin:BAACLAAFFIEFAAIcAAMIOyP3AAA4AQAcAAMIOyP3AAA4AQAsAAQKgRgAAhwACAiNJcwAAEYDABwACAiNJcwAAEYDAAAA.Kevp:BAAALAAECgYIEgAAAA==.',Ki='Kidevil:BAAALAAECgIIAgAAAA==.Kinbaitsuza:BAAALAADCgcICwAAAA==.',Ko='Komai:BAAALAAECgcIEAAAAA==.Kopikia:BAAALAAECgYICQAAAA==.',Kr='Krayle:BAABLAAECoEUAAIdAAgIySH3AAANAwAdAAgIySH3AAANAwAAAA==.Krucify:BAAALAAECgcIBwAAAA==.',Kt='Ktl:BAAALAAECgcICwAAAA==.Ktr:BAAALAAECgEIAQABLAAECgcICwABAAAAAA==.',Ku='Kulak:BAAALAAECgMIBwAAAA==.Kult:BAAALAADCgIIAgAAAA==.Kungfufa:BAAALAAECgQIBgAAAA==.Kunukunu:BAAALAADCgIIAgAAAA==.',Ky='Kyall:BAAALAAECgcICQAAAA==.',La='Ladiesman:BAAALAADCgUIBQAAAA==.Laissa:BAAALAAECgYIBgAAAA==.Lamerzz:BAAALAAECgUICQAAAA==.',Le='Lettuce:BAAALAAECgYIDwAAAA==.',Li='Lianglidan:BAAALAADCgYIBgAAAA==.Lightbeer:BAAALAADCgMIAgAAAA==.Likaj:BAAALAAECgYIDgAAAA==.Likguva:BAAALAAECggIAQAAAA==.Lilgrnbstd:BAAALAAECgMIBgAAAA==.Liquidsnake:BAAALAAECgYIDgAAAA==.',Lo='Lokomoko:BAAALAAECgQIBgAAAA==.Longshòt:BAAALAAECgYICAAAAA==.Loraniden:BAAALAAECgEIAQABLAAECgYIEwABAAAAAA==.Lorn:BAABLAAECoEUAAMUAAgIFiBsCQCFAgAUAAcInCJsCQCFAgANAAMImxZrEQDXAAAAAA==.',Lu='Lushinyolo:BAAALAADCgMIAwABLAAECgYIDgABAAAAAA==.',Ly='Lyndra:BAAALAAECggIDgABLAAFFAUIBgAUABMHAA==.',Ma='Maleman:BAAALAAECgYICgAAAA==.',Me='Mefiston:BAAALAAECgQICQAAAA==.Megadeath:BAAALAAECggICwAAAA==.Meku:BAAALAADCggICwAAAA==.Mentalas:BAAALAAECgYICAAAAA==.',Mi='Miaomiaomiao:BAACLAAFFIEKAAIeAAUInxpUAADaAQAeAAUInxpUAADaAQAsAAQKgRgAAx4ACAggHm4HAH8CAB4ACAggHm4HAH8CABcABAiJE+krAAwBAAAA.Miaomiaorawr:BAABLAAECoEVAAMKAAgIZx8NBAD1AgAKAAgIZx8NBAD1AgAfAAEIiBYwFwBDAAABLAAFFAUICgAeAJ8aAA==.Mightyz:BAAALAAECgQIBgAAAA==.Miikaela:BAAALAAECgMIAwAAAA==.Mikäsa:BAABLAAECoEWAAIJAAgIwBuuDQCwAgAJAAgIwBuuDQCwAgAAAA==.Minamai:BAAALAAECgIIAgAAAA==.Mistify:BAAALAAECgQIBwAAAA==.Mistlilly:BAAALAADCgUIBQAAAA==.',Mo='Moolicious:BAAALAADCgEIAQAAAA==.Moongrass:BAAALAAECgIIAwAAAA==.Mortîfer:BAAALAAECggIBQAAAA==.Mousemarâ:BAAALAAECgQICAAAAA==.',Mu='Muntsy:BAAALAADCgYICgAAAA==.Muthiaz:BAAALAAECgYIBgAAAA==.',My='Mythra:BAAALAADCgUIBQABLAAFFAIIAgABAAAAAA==.',Na='Nahaulass:BAAALAAECgIIAgAAAA==.',Ne='Necrobrew:BAAALAAECgUIBQABLAAECggIFgAOAOgcAA==.Necrowar:BAABLAAECoEWAAIOAAgI6BziBACcAgAOAAgI6BziBACcAgAAAA==.Nemovc:BAAALAAECgQIBAAAAA==.Nenepok:BAAALAADCgMIAwAAAA==.',Ng='Nginx:BAAALAAECgYICwAAAA==.',Ni='Nightíngale:BAAALAAECgQIBQAAAA==.Nigl:BAAALAADCgMIAwAAAA==.Nihilarian:BAAALAAECgMIBAAAAA==.Nishi:BAAALAADCgIIAgAAAA==.',No='Nocchii:BAAALAAECgMIBQAAAA==.Nohealsforu:BAAALAADCgIIAgABLAAECgcIEAABAAAAAA==.Nosok:BAAALAAECgEIAQAAAA==.Notwithdeath:BAAALAAECgMIBAAAAA==.Novis:BAAALAAECgYIDAAAAA==.',Nt='Nthope:BAAALAAFFAMIBgAAAQ==.Ntmonkz:BAAALAAECggIFAABLAAFFAMIBgABAAAAAQ==.',['Ní']='Níl:BAAALAAECgEIAQAAAA==.',Oj='Ojea:BAAALAAECgIIAgAAAA==.',On='Onlyhead:BAAALAAECgQIBAAAAA==.',Or='Orhgyn:BAAALAAECggIBAAAAA==.',Pa='Palabean:BAAALAADCgUIBQAAAA==.Pamie:BAAALAAECgUIBgAAAA==.Pandasoul:BAAALAADCgcIDAAAAA==.Paperplater:BAAALAADCgcIBwAAAA==.',Pe='Pepperino:BAAALAAECgYICwAAAA==.Peppy:BAAALAAECgYICgAAAA==.',Ph='Phofor:BAAALAAECgYIAQAAAA==.',Pi='Pinkrowg:BAAALAADCgYIBgABLAAECgQIBQABAAAAAA==.',Po='Pog:BAAALAAECgYIBgAAAA==.Pookymuttkao:BAAALAAECggICAAAAA==.Popini:BAAALAAECgYIDAAAAA==.Poros:BAAALAADCggICAAAAA==.Poteb:BAAALAAECgEIAgAAAA==.Powerangers:BAAALAADCgcICgAAAA==.',Pr='Prefmonk:BAAALAAECgcIDQAAAA==.Prodigal:BAAALAAFFAIIAgAAAA==.',Pu='Pumbz:BAAALAADCggIGAAAAA==.Punshockable:BAEALAAECggICAAAAA==.',Pw='Pwndis:BAAALAAECgYICwAAAA==.',Py='Pyroblst:BAAALAADCgMIAwAAAA==.Pyroorc:BAAALAAECgIIAwAAAA==.',Qe='Qeb:BAAALAAECgcIDQAAAA==.Qeliss:BAAALAAECgQIBgAAAA==.',Ra='Rainblazer:BAAALAADCgUIBQAAAA==.Ravenn:BAAALAAECgIIAwABLAAECgIIAwABAAAAAA==.',Re='Reindart:BAAALAAECgYICAAAAA==.Repertoire:BAAALAADCgcIBwAAAA==.',Ro='Ronniepaws:BAAALAAECgQIBQAAAA==.Roommatethor:BAAALAADCgcIDQAAAA==.',Ru='Rukkzh:BAAALAAECgIIAgAAAA==.Ruptured:BAAALAAECgYICQAAAA==.',Sa='Saltednuts:BAAALAAECgYIDAAAAA==.Saltysloan:BAAALAADCggIDwAAAA==.Sardonyx:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.Sarisa:BAAALAAFFAIIBAABLAAFFAQICQAgALYiAA==.Sataidelenn:BAAALAAECgYIDgAAAA==.Savagesteel:BAAALAAECgIIAgABLAAECgYICAABAAAAAA==.',Se='Senpahinata:BAAALAAECgYICwAAAA==.',Sh='Shamussy:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.Shapeshiift:BAAALAADCgQIBAAAAA==.Shardsoffury:BAAALAAECgMIBwAAAA==.Sharpess:BAAALAADCgEIAQAAAA==.Shidann:BAACLAAFFIEKAAIXAAUIeSMWAAAtAgAXAAUIeSMWAAAtAgAsAAQKgRUAAhcACAjgJiwAAJYDABcACAjgJiwAAJYDAAAA.Shintopal:BAAALAAECgQIBwAAAA==.Shiwann:BAAALAAECggIDgABLAAFFAUICgAXAHkjAA==.Shloppyh:BAACLAAFFIEKAAIEAAUIIht7AAAIAgAEAAUIIht7AAAIAgAsAAQKgRgAAgQACAjQJX0AAIcDAAQACAjQJX0AAIcDAAAA.Shocktopus:BAAALAADCggICAAAAA==.Shootrmcgavn:BAAALAAECgIIAgAAAA==.Shua:BAAALAADCgIIAgAAAA==.',Si='Sillyshammy:BAAALAAECggIBgAAAA==.Silvermaiden:BAAALAADCgUIBQAAAA==.Silvertears:BAAALAAECgMIBgABLAAECgcIBwABAAAAAA==.Sindrust:BAAALAAECgcIEAAAAA==.Singularius:BAAALAAECgIIAgAAAA==.Sinorph:BAAALAAECgQIBQABLAAECgcIEAABAAAAAA==.Sixy:BAAALAAFFAIIAgAAAA==.',Sk='Skulldrum:BAAALAAECgMIBAAAAA==.',Sl='Slappuccino:BAAALAAECgMIBgAAAA==.Slime:BAAALAADCggIAgAAAA==.Sliver:BAAALAADCgYIBgAAAA==.',Sm='Smeltzy:BAAALAADCgcIBwAAAA==.',Sn='Snacthyr:BAAALAAECgQICgAAAA==.Sneakyitch:BAAALAAECgYICQAAAA==.Sneakyorgy:BAAALAAECgcIDwAAAA==.Snowcloud:BAAALAAECgIIAgAAAA==.',So='Soil:BAABLAAECoEWAAMNAAgIlRtNAwCDAgANAAgIlRtNAwCDAgAUAAEIWhI1NAA+AAAAAA==.Solenya:BAAALAADCggIDgABLAAECgYICwABAAAAAA==.Songfíre:BAAALAAECgcIEAAAAA==.',St='Stabby:BAAALAAECgMIBgAAAA==.Stan:BAACLAAFFIEGAAMDAAQIMxPYAQAGAQADAAMIkBbYAQAGAQAhAAEIHQn0CgBXAAAsAAQKgRgAAwMACAjKI5kCACQDAAMACAjKI5kCACQDACEAAghlEYJaAIsAAAAA.Stanstan:BAABLAAECoEUAAIUAAgIsA9+EQD1AQAUAAgIsA9+EQD1AQABLAAFFAQIBgADADMTAA==.Staxks:BAAALAAECgUIBQAAAA==.Stealthunt:BAAALAAECgYIBgAAAA==.',Su='Sumdk:BAAALAAECgUIBwABLAABCgMIAwABAAAAAA==.Sutiao:BAACLAAFFIEGAAITAAQI4hTQAQBwAQATAAQI4hTQAQBwAQAsAAQKgRcABBUACAiDIIUAAPcCABUACAjfH4UAAPcCABMABwhWHtQfABECABgAAwiZGZApAMIAAAAA.',Sw='Swissarmy:BAAALAADCggICAAAAA==.Swissknife:BAAALAAECgYICAAAAA==.',Sy='Sylbananas:BAAALAADCgcIEQABLAAECgYICAABAAAAAA==.Syra:BAAALAAECgEIAQAAAA==.',['Sì']='Sìlverhunter:BAAALAAECgcIBwAAAA==.',Ta='Tallia:BAAALAAECgIIAwABLAAECgcIEwABAAAAAA==.Tancs:BAAALAAECgIIAgAAAA==.Tanknmoo:BAAALAADCgIIAgAAAA==.Taurium:BAAALAAECgcIEAAAAA==.',Te='Teezzgizzt:BAAALAADCgUICAAAAA==.Telnet:BAAALAADCgEIAQAAAA==.Tempermattal:BAAALAADCggICAAAAA==.Temsik:BAAALAAECgcIEAAAAA==.Temsikdab:BAAALAADCgcIBwAAAA==.Terrordactyl:BAAALAAECgIIAwAAAA==.',Th='Theanna:BAAALAADCggIFgAAAA==.',Ti='Tiddlyniblit:BAAALAAECgIIAgAAAA==.Tifa:BAAALAADCgUIBwAAAA==.Timei:BAAALAADCgcICAAAAA==.',Tj='Tj:BAAALAADCgcIBwAAAA==.',To='Tommyh:BAACLAAFFIEKAAICAAUIJSRWAAAuAgACAAUIJSRWAAAuAgAsAAQKgRcAAgIACAhJJpIAAIMDAAIACAhJJpIAAIMDAAAA.Tootydoots:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.Torress:BAAALAAECgMIBwAAAA==.Toufz:BAAALAAECgcIDwAAAA==.',Ty='Tyranadia:BAABLAAECoEUAAIZAAgI4yHGAQAOAwAZAAgI4yHGAQAOAwAAAA==.Tyranak:BAAALAAECgIIAgABLAAECggIFAAZAOMhAA==.Tystus:BAAALAADCgcICQAAAA==.',Tz='Tzimisce:BAAALAADCgYIBgAAAA==.',Un='Unalive:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.',Ur='Ursuula:BAAALAADCgIIAgAAAA==.',Va='Valiant:BAAALAADCggIFgAAAA==.Varnoxx:BAABLAAECoEWAAIRAAgILSDQAgDRAgARAAgILSDQAgDRAgAAAA==.',Ve='Vermillion:BAAALAAECgcIEgAAAA==.',Vn='Vnex:BAAALAAECggIDgAAAA==.',Vo='Voidleaf:BAAALAAECgYICgAAAA==.Vosegus:BAAALAADCgQIBgAAAA==.',Wa='Wahcow:BAAALAAECgMIBgAAAA==.Wardz:BAAALAAECgIIAgAAAA==.Waterman:BAAALAAECgQIBgAAAA==.Wazaldin:BAAALAADCgYIBQAAAA==.',Wi='Wiiu:BAAALAADCgMIAwAAAA==.Winnieblue:BAAALAAECgcIDAAAAA==.',Wo='Woihaziq:BAAALAADCgQIBAAAAA==.Woodro:BAAALAADCgcICwAAAA==.',Xo='Xoxoteira:BAAALAADCggICAAAAA==.',Xs='Xshamster:BAAALAADCgcIDQAAAA==.',Xt='Xtion:BAAALAAECggIDgAAAA==.',Xx='Xxiaolongnvv:BAAALAAECggICAAAAA==.',Ya='Yagnatia:BAAALAAECgMIAwAAAA==.Yayawunter:BAAALAADCggICAAAAA==.',Yo='Yongbok:BAAALAAECgIIAgAAAA==.',Yr='Yrano:BAAALAADCggIDgAAAA==.',Yu='Yurri:BAAALAADCgYIBgABLAAECgcIEwABAAAAAA==.',Za='Zaloviee:BAAALAAFFAIIAgAAAA==.Zalovii:BAAALAAECggIDgABLAAFFAIIAgABAAAAAA==.Zaraxes:BAAALAAECgcIDQAAAA==.',Ze='Zenõ:BAEALAAECgcIBwAAAA==.',Zi='Zirka:BAAALAAECgcIEwAAAA==.',Zu='Zugzs:BAAALAAECgQIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end