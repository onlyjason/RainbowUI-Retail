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
 local lookup = {'Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Monk-Windwalker','Unknown-Unknown','Druid-Feral','Paladin-Protection','Mage-Arcane','Mage-Frost','Priest-Holy','Shaman-Enhancement','Hunter-BeastMastery','DeathKnight-Blood','Paladin-Retribution','Mage-Fire','Evoker-Devastation','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Preservation','DemonHunter-Havoc','Shaman-Elemental','Paladin-Holy','Hunter-Marksmanship',}; local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aamix:BAABLAAECoEWAAQBAAgIPhehGwDYAQABAAcIqhShGwDYAQACAAUIWRcfHgAkAQADAAEIIAReKwBDAAAAAA==.Aarom:BAABLAAECoEXAAIEAAgIGhh5CABAAgAEAAgIGhh5CABAAgAAAA==.Aashia:BAAALAADCgQIBAAAAA==.',Ab='Abhark:BAAALAAECgYICAAAAA==.Abrakastaba:BAAALAADCgcIBwABLAAECggIEgAFAAAAAA==.',Ac='Achifee:BAAALAADCgIIAgAAAA==.',Ae='Aerius:BAAALAAECgEIAQAAAA==.',Ag='Agimlin:BAAALAADCggICAAAAA==.',Ak='Akasori:BAABLAAECoEVAAIGAAYImhc0CgC5AQAGAAYImhc0CgC5AQAAAA==.Akeir:BAAALAAECgMIBQAAAA==.Akîra:BAAALAADCgMIAwABLAAECggIEgAFAAAAAA==.',Al='Aldarus:BAAALAAECgYICAAAAA==.Alstre:BAAALAAECgYIBwAAAA==.Alîsonshammy:BAAALAAECggIEgAAAA==.',Am='Ambersulfr:BAAALAAECgIIAgAAAA==.Amishostrich:BAAALAADCgcIBwAAAA==.Amrazz:BAAALAAECgcIDAAAAA==.Amrazzfox:BAAALAADCggICAABLAAECgcIDAAFAAAAAA==.Amrazzshammy:BAAALAADCggICQABLAAECgcIDAAFAAAAAA==.Amzey:BAEALAAECgUICAAAAA==.',An='Anahata:BAAALAADCgMIAwAAAA==.Andromeda:BAAALAAECgcIEAAAAA==.Anexilea:BAAALAADCgcIBgAAAA==.Anomander:BAAALAADCggIGQAAAA==.',Ar='Arakis:BAAALAAECgQIBwABLAAECgYIDgAFAAAAAA==.Armazoo:BAAALAAECgcIEAAAAA==.',As='Ashardalon:BAAALAADCggICAAAAA==.Ashylarry:BAAALAADCggICgAAAA==.Asiiago:BAAALAADCgMIAwAAAA==.Astralus:BAAALAAECgcIEAAAAA==.Astramis:BAAALAAECgMIBAAAAA==.',At='Athos:BAAALAAECgIIAgAAAA==.Atomicbarbie:BAAALAADCgcIBwABLAAECggIEgAFAAAAAA==.',Ba='Babybuu:BAAALAAECgIIAgAAAA==.Bam:BAAALAAECgYIBgAAAA==.Barthold:BAAALAADCggIGAAAAA==.',Be='Beleaf:BAAALAAECgMIAwAAAA==.Beorrn:BAAALAADCgcIBwAAAA==.Bexton:BAAALAAECgIIAgABLAAECggIEAAFAAAAAA==.',Bl='Bledsmasher:BAAALAADCggIEAAAAA==.Blouses:BAAALAAFFAEIAQAAAA==.',Bo='Bobowild:BAAALAAECgMIBAAAAA==.Bonbons:BAAALAADCgMIAwAAAA==.Boned:BAAALAAECgMIBQAAAA==.Bonemair:BAAALAAECgMIAwABLAAECggIFwAHAJQjAA==.Bowser:BAAALAADCggICAAAAA==.',Br='Braelie:BAAALAADCgYIBgAAAA==.Brewcelee:BAAALAADCgcIBwAAAA==.',Bu='Bulwark:BAAALAADCgcIBwAAAA==.Bup:BAAALAAECgYICAAAAA==.Bups:BAAALAADCgYIBwAAAA==.Buttjuggles:BAAALAADCgcICQAAAA==.',Ca='Caldec:BAACLAAFFIEFAAIIAAMI/wfbBQDlAAAIAAMI/wfbBQDlAAAsAAQKgRcAAwgACAiwH7IOAK8CAAgACAiwH7IOAK8CAAkAAwgIF/IrALEAAAAA.Caldeç:BAAALAAECgMIAwAAAA==.Camina:BAAALAAECgMIAgAAAA==.Catwater:BAAALAADCgQIBAAAAA==.',Ch='Chainmagus:BAAALAADCggICAABLAAECggIGAAKACEiAA==.Chainsmite:BAABLAAECoEYAAIKAAgIISIpAwAMAwAKAAgIISIpAwAMAwAAAA==.Cheeno:BAAALAAECgYIDAAAAA==.',Cl='Clunk:BAAALAAECgMIBAAAAA==.',Co='Cogltzach:BAAALAADCggICAABLAAECgIIAgAFAAAAAA==.Coorslight:BAAALAAECgMIAwABLAAECgYICgAFAAAAAA==.Cors:BAAALAADCgcIBwAAAA==.',Cr='Crantor:BAAALAAECgYICAAAAA==.Crelam:BAACLAAFFIEFAAILAAMI1wTCAADcAAALAAMI1wTCAADcAAAsAAQKgRcAAgsACAi+GqECAKcCAAsACAi+GqECAKcCAAAA.Cronatherus:BAAALAADCgEIAQAAAA==.Cruentis:BAAALAAECgYICgAAAA==.Crysus:BAAALAAECgQIBAAAAA==.',Da='Daemoon:BAAALAAECgYIDQAAAA==.Damarisalynn:BAAALAAECgUICAAAAA==.Damös:BAAALAAECgMIBAAAAA==.Dangus:BAAALAADCgcIBwAAAA==.Danifarian:BAAALAAECggIEgAAAA==.Danoth:BAAALAADCggIEAAAAA==.Darwin:BAAALAAECgIIAwAAAA==.Dasmoodhayn:BAAALAADCgIIAgAAAA==.Davalanch:BAAALAAECggIDQAAAA==.',De='Deathdowla:BAAALAAECggIBAAAAA==.Demondot:BAAALAAECgMIBwAAAA==.Denart:BAAALAAECggIEAAAAA==.Dethkløk:BAAALAAECgIIAwAAAA==.Deylera:BAAALAAECgYIDgAAAA==.',Di='Dillbert:BAAALAADCgMIAwAAAA==.Dimensius:BAAALAAECgIIAQAAAA==.Dirus:BAAALAADCgYIBgABLAAECgYICQAFAAAAAA==.',Do='Dogfight:BAAALAAECgcIBwAAAA==.Doloros:BAAALAAECgYICgAAAA==.Dootie:BAAALAADCggICAAAAA==.Dorá:BAAALAADCgUIBQABLAAECgUICQAFAAAAAA==.',Dr='Dragonhide:BAAALAAECgEIAQAAAA==.Dragown:BAAALAAECgIIAgAAAA==.Drakedav:BAAALAAECgIIAgABLAAECggIDQAFAAAAAA==.Dreadbone:BAAALAADCgcIBwABLAAECgEIAQAFAAAAAA==.Dresel:BAACLAAFFIEFAAIMAAMIIxE/AgADAQAMAAMIIxE/AgADAQAsAAQKgRcAAgwACAg/IFMGAP4CAAwACAg/IFMGAP4CAAAA.Drewpeebahlz:BAAALAADCgcICAAAAA==.Drezell:BAAALAAECgMIBAABLAAFFAMIBQAMACMRAA==.',Du='Duchaillu:BAAALAAECgQIBAAAAA==.',Dy='Dyami:BAAALAAECgYIDAAAAA==.Dying:BAAALAADCggICAABLAAECggIEgAFAAAAAA==.Dynas:BAAALAAECgEIAQAAAA==.',Ea='Earthcake:BAAALAAECgcIEgAAAA==.',Ed='Eddielich:BAABLAAFFIEFAAINAAMI5RzzAAAQAQANAAMI5RzzAAAQAQAAAA==.Eddiepope:BAAALAAECgMIAwABLAAFFAMIBQANAOUcAA==.Eddiewar:BAAALAAECgcIBwAAAA==.',El='Elfpen:BAAALAADCgQIBAAAAA==.Ellan:BAAALAAECgYICgAAAA==.Elmatonn:BAAALAAECgIIAgAAAA==.',Em='Embaw:BAAALAAECgYIDQAAAA==.',En='Enlargeshamy:BAAALAAECgYIBwAAAA==.',Es='Escanõr:BAAALAADCgYIBgAAAA==.',Fa='Fatevoker:BAAALAADCgQIBAAAAA==.',Fe='Fexli:BAAALAADCgQIBAAAAA==.',Fo='Folklore:BAAALAAECgMIBQAAAA==.Fordrius:BAAALAADCgQIAgAAAA==.Forklift:BAAALAADCggICAABLAAECgYICQAFAAAAAA==.',Fr='Frankmomma:BAAALAADCgcIBwAAAA==.Frossttee:BAAALAADCgcIDQABLAAECgcIEwAFAAAAAA==.Frostbrownie:BAAALAADCgEIAQAAAA==.Frostyfoxy:BAAALAAECgQIBQAAAA==.Frothtie:BAAALAAECggIBQAAAA==.Fruits:BAAALAAECgEIAgABLAAECgcIFAAOAAskAA==.',Fu='Fusebawx:BAAALAADCgQIBAAAAA==.',Ga='Galram:BAAALAAECgMIAwABLAAFFAMIBQALANcEAA==.Garlicbred:BAAALAAECgQIBQAAAA==.Gastro:BAAALAADCgIIAgAAAA==.',Gi='Gimpwithmilk:BAAALAAECgQIBAAAAA==.Gip:BAAALAADCgcIDQAAAA==.',Gl='Glavenüs:BAAALAADCgcIBwAAAA==.Glimmair:BAABLAAECoEXAAIHAAgIlCOxAQAoAwAHAAgIlCOxAQAoAwAAAA==.Glimmer:BAAALAADCgQIBAAAAA==.Glo:BAAALAADCgcIAQAAAA==.',Gr='Greshum:BAAALAADCgUIBQAAAA==.Greyanna:BAAALAAECgEIAQAAAA==.Gromthrall:BAAALAADCgQIBAAAAA==.Grumpydik:BAAALAADCgcIBwAAAA==.',Gu='Gumdrops:BAAALAADCgMIAwAAAA==.Gurthrot:BAAALAADCgcIBwAAAA==.Guunarak:BAAALAADCgEIAQAAAA==.',Gy='Gymluigi:BAAALAAECgMIAwAAAA==.',['Gò']='Gòd:BAAALAAECgIIAgAAAA==.',Ha='Hailin:BAAALAADCgcIDAAAAA==.Hammerramma:BAAALAAECgMIAwAAAA==.Hapgido:BAAALAADCgQIBAAAAA==.',Hb='Hbheathenm:BAACLAAFFIEFAAMIAAMIOQXjCAC2AAAIAAMIaATjCAC2AAAPAAEIIgMDAwA2AAAsAAQKgSQAAwgACAgIIAQJAPECAAgACAgIIAQJAPECAA8AAgjxEMkJAGEAAAAA.',He='Hellhore:BAAALAADCgcIDwAAAA==.',Hi='Highego:BAAALAADCgYIBgAAAA==.Hitta:BAAALAADCggICwAAAA==.',Ho='Holdenc:BAAALAADCggIDwABLAAECgMIAwAFAAAAAA==.Hoodz:BAAALAAECgYICQAAAA==.Horyshizz:BAAALAADCgIIAgAAAA==.Hotzalot:BAEALAADCgYIBgAAAA==.',Ib='Ibearprofen:BAAALAAECgUIBQAAAA==.Iblees:BAAALAAECgcIEwAAAA==.',Ic='Icywang:BAAALAADCgcIDgAAAA==.',Im='Imagined:BAAALAAECgMIAwAAAA==.',In='Indihunter:BAAALAADCgcIDgAAAA==.Infernis:BAAALAADCgMIAwAAAA==.Infidelity:BAAALAADCgcIGgAAAA==.Inque:BAAALAAECgYICwAAAA==.',Ir='Ironinfidel:BAAALAADCgUIBQAAAA==.',Iv='Ivank:BAAALAAECgIIAgAAAA==.Ivannalot:BAAALAADCgcICgAAAA==.',Ja='Jage:BAAALAADCggIEAAAAA==.Jakkul:BAAALAAECgcIEAAAAA==.Jarsham:BAAALAADCggIFgAAAA==.',Je='Jetstingray:BAAALAADCgMIAwABLAAECgYICQAFAAAAAA==.',Jo='Joran:BAAALAADCgcIDQAAAA==.',Jw='Jwrs:BAAALAAECgUIBQAAAA==.',Ka='Kaelana:BAAALAAECgMIAwAAAA==.Kahlua:BAAALAAECgUICQAAAA==.Kailan:BAAALAADCggIDgABLAAECgYICgAFAAAAAA==.Kailani:BAAALAAECgUIBgAAAA==.Kaldro:BAAALAADCggIDgAAAA==.Kariana:BAAALAAECgYICgAAAA==.Kasarka:BAAALAAECgYICAAAAA==.Kathry:BAAALAADCgcICgAAAA==.',Kc='Kcid:BAAALAAECgMIBAAAAA==.',Ke='Kedibaba:BAAALAAECggIBQAAAA==.Keepdreaming:BAAALAAECgYICgAAAA==.Kelom:BAAALAADCggIEAAAAA==.',Ki='Kianti:BAAALAADCgcICQAAAA==.Killeh:BAAALAADCgcIDQAAAA==.Killhando:BAAALAADCgcIBwAAAA==.Kindaka:BAAALAADCgMIAwAAAA==.Kios:BAAALAADCggIDwAAAA==.Kipdog:BAAALAAECgYICQAAAA==.',Ko='Korda:BAAALAADCgQIBAAAAA==.Korothela:BAAALAADCggICQAAAA==.Kosh:BAAALAADCgQIBAAAAA==.Koyra:BAACLAAFFIEFAAIQAAMI9iAEAgAaAQAQAAMI9iAEAgAaAQAsAAQKgRcAAhAACAiiJXMBAFQDABAACAiiJXMBAFQDAAAA.',Kr='Krayvok:BAAALAADCggICAAAAA==.Krump:BAAALAADCgcICgAAAA==.',Ku='Kubidari:BAAALAADCggICAAAAA==.Kugeki:BAAALAADCgEIAQAAAA==.Kungfuul:BAAALAADCggICAAAAA==.Kuraladin:BAAALAADCgYIBgABLAAECggIFgARAIYgAA==.Kurral:BAABLAAECoEWAAIRAAgIhiANBwDOAgARAAgIhiANBwDOAgAAAA==.Kurstina:BAAALAAECgIIAwAAAA==.',Ky='Kynkjr:BAAALAAECgYICQAAAA==.Kyramus:BAAALAAECgMIBAAAAA==.',La='Laconia:BAAALAAECgYIDgAAAA==.Larox:BAAALAADCgQIBQAAAA==.Lashstorm:BAAALAAECgIIAgAAAA==.Lattsatnar:BAAALAADCgcIBwAAAA==.',Le='Learn:BAAALAADCggICAAAAA==.Legendary:BAAALAAECgYIDAAAAA==.Leviiathan:BAAALAAECggICAAAAA==.',Li='Liesel:BAAALAADCgcIBwAAAA==.Lifebloom:BAAALAADCgYICgAAAA==.Lilah:BAAALAAECgYICgAAAA==.Lilyillidari:BAAALAADCgcIBwAAAA==.',Lo='Lokk:BAAALAADCgYIBgAAAA==.Loktardogard:BAAALAAECgIIAwAAAA==.Lowdps:BAAALAADCggICAAAAA==.',Lu='Luminus:BAAALAADCgEIAQAAAA==.Lunafalia:BAAALAAECgYICQAAAA==.Lurosa:BAABLAAECoEZAAMSAAgIkiI/BADCAgASAAgIkiI/BADCAgARAAEItBQkSAA6AAAAAA==.Luxeria:BAAALAAECgMIAwAAAA==.',Ly='Lyrae:BAAALAAECgMIAwAAAA==.',['Lï']='Lïchkinged:BAAALAAECggICgAAAA==.',Ma='Macready:BAAALAAECgUICQAAAA==.Magenin:BAAALAADCgcIBwAAAA==.Magusdemon:BAAALAAECgYICQAAAA==.Mairicade:BAAALAADCggICAABLAAECggIFwAHAJQjAA==.Malifexia:BAAALAADCgQIBAAAAA==.Maltessa:BAAALAADCgUIBQABLAAECgYICgAFAAAAAA==.Manøn:BAAALAAECgQICAAAAA==.Marllowe:BAABLAAECoEWAAIEAAgIuBaYCAA9AgAEAAgIuBaYCAA9AgAAAA==.Mathy:BAAALAAECgYIBgAAAA==.',Mc='Mc:BAAALAADCgIIAgAAAA==.',Me='Mej:BAAALAAECgIIAgAAAA==.Melreu:BAAALAADCgYIBgAAAA==.Menymage:BAAALAAECgEIAgAAAA==.Mephísto:BAAALAADCggICAABLAAECgcIEwAFAAAAAA==.',Mi='Midletons:BAAALAADCgEIAQAAAA==.Midran:BAAALAAECgYICAAAAA==.Mischief:BAAALAADCgUIBQAAAA==.',Mo='Mojó:BAAALAAECgEIAQAAAA==.Monkfox:BAAALAAECgEIAQABLAAECgIIAgAFAAAAAA==.Moovoker:BAAALAAECgYICgAAAA==.Morb:BAAALAAECggICAAAAA==.',Mt='Mtdew:BAAALAADCgcIBwAAAA==.',Mu='Muggy:BAABLAAECoEZAAMTAAgImiSwHgAPAgATAAUI3SSwHgAPAgAUAAQISyJwEQCIAQAAAA==.Muggyrolls:BAAALAAECgIIAgABLAAECggIGQATAJokAA==.',My='Mystics:BAAALAAECgcIEAAAAA==.Mysts:BAAALAAECgMIAwABLAAFFAMIBQAVAIcmAA==.',['Mê']='Mêatsweats:BAAALAADCgUIBQAAAA==.',Na='Narama:BAABLAAECoEXAAMBAAgIdBPQGwDWAQABAAcIdRPQGwDWAQACAAIIYxHwNQCSAAAAAA==.',Ne='Nep:BAAALAAECgcIEgAAAA==.Nerisha:BAAALAADCggIEAAAAA==.',Ni='Ninæ:BAAALAADCggICAABLAAECggIFgASAOgiAA==.Nitewïng:BAAALAAECgYIBwAAAA==.',No='Nootao:BAAALAAFFAIIAgAAAA==.Nootau:BAAALAAECgMIAwABLAAFFAIIAgAFAAAAAA==.',Ny='Nyoz:BAAALAADCgUIBwAAAA==.Nyxare:BAAALAAECgMIBAAAAA==.',Om='Omegabane:BAAALAAECgYICQAAAA==.',On='Onne:BAAALAADCgUIBQAAAA==.',Or='Oraculus:BAACLAAFFIEFAAISAAMIShb2AQAAAQASAAMIShb2AQAAAQAsAAQKgRcAAhIACAgzIbICAO4CABIACAgzIbICAO4CAAAA.',Ow='Owlbeartree:BAAALAADCgYIBwAAAA==.Ownweaver:BAAALAADCggIDQAAAA==.',Pa='Pakaru:BAAALAAECgYICwAAAA==.Pam:BAABLAAECoEWAAIWAAgINiHcCQDlAgAWAAgINiHcCQDlAgAAAA==.Paragon:BAAALAAECgMIAwAAAA==.',Pe='Peech:BAAALAAECgUIBwAAAA==.Peka:BAAALAADCgcIBwAAAA==.Peremo:BAAALAAECgcIEQAAAA==.Perfectdark:BAACLAAFFIEFAAIWAAMIsRn1AgAWAQAWAAMIsRn1AgAWAQAsAAQKgRcAAhYACAikIogGABcDABYACAikIogGABcDAAAA.',Pi='Pickles:BAAALAAECgYICAAAAA==.Pieper:BAAALAADCgMIAwAAAA==.Pipa:BAAALAAECgcIEAAAAA==.',Pl='Plaguexrat:BAAALAADCgYIBgAAAA==.',Po='Poacher:BAAALAAECgEIAQAAAA==.Poombah:BAAALAADCgQIBAAAAA==.Porack:BAAALAAECgIIAgAAAA==.',Pr='Prayerform:BAAALAAECggIDgAAAA==.Provence:BAAALAADCgcIBwAAAA==.',Pu='Pugna:BAAALAAECgUIBQAAAA==.Pumptydumpty:BAAALAAECgYICAAAAA==.',Py='Pyreynna:BAAALAAECgIIAgAAAA==.',Qu='Quahzai:BAAALAAECgYICQAAAA==.Queso:BAAALAAECgEIAQABLAAECgYIDAAFAAAAAA==.Quicky:BAAALAAECgcIDQAAAA==.Quickyclap:BAAALAAECgYICAAAAA==.Quinmora:BAAALAAECgEIAQAAAA==.',Ra='Rainhunter:BAAALAAECgcIEAAAAA==.Ralnorin:BAAALAADCgIIAgAAAA==.Randomcream:BAAALAADCgcIBwAAAA==.Raux:BAAALAADCggIDAAAAA==.',Re='Realfrojd:BAAALAAECgcIDwAAAA==.Redrick:BAAALAAECgEIAQAAAA==.Refract:BAAALAADCgYIBgAAAA==.Regginunchuk:BAAALAAECgYICgAAAA==.Reisza:BAAALAAECgUIBQAAAA==.Releronastus:BAAALAADCgYICAAAAA==.Relief:BAAALAADCggICAABLAAECgYICQAFAAAAAA==.Resolution:BAAALAADCggICAAAAA==.Retricution:BAAALAAECgMIBQAAAA==.Reyson:BAAALAAECgUICQAAAA==.',Ri='Riastlen:BAAALAADCgcIDQAAAA==.Rille:BAAALAADCggICAAAAA==.Rinfen:BAAALAADCgcICgAAAA==.Rinslaughter:BAAALAADCgMIAwAAAA==.Rinthia:BAAALAAECgYICgAAAA==.Ripyeet:BAAALAAECgMIAwAAAA==.',Ro='Robinhood:BAAALAAECggIAgAAAA==.Roots:BAAALAAECgMIBAAAAA==.',Ru='Rukaji:BAAALAADCggIFgAAAA==.',['Rå']='Råge:BAAALAADCgQIBQAAAA==.',['Rö']='Röland:BAAALAADCgIIAgABLAAECgIIAgAFAAAAAA==.',Sa='Saetheline:BAAALAAECgYICgAAAA==.Saren:BAAALAADCgEIAQAAAA==.Sargosa:BAAALAADCgMIAwABLAADCgQIBAAFAAAAAA==.Sarkang:BAAALAADCgcIBwAAAA==.Sathelil:BAAALAADCgcICwAAAA==.Savvy:BAAALAAECgYIDwAAAA==.',Sc='Schutze:BAAALAAFFAEIAQAAAA==.',Sd='Sdadfeg:BAAALAAECgYICQAAAA==.',Se='Sethena:BAAALAADCgcIBwAAAA==.Señorpanda:BAAALAADCgcIBwAAAA==.',Sh='Shabobado:BAAALAAECgMIAwAAAA==.Shamangobrr:BAAALAAECgEIAQAAAA==.Shandralox:BAAALAAECgMIBAAAAA==.Shirochi:BAAALAADCggIEAAAAA==.Shockenawe:BAAALAADCgcIBwAAAA==.Shxdow:BAAALAADCgcIBwAAAA==.',Si='Sibble:BAAALAADCgYIBgAAAA==.Simplejakk:BAABLAAECoEWAAIXAAgIHCReBAAnAwAXAAgIHCReBAAnAwAAAA==.Sinterklaas:BAAALAAECgMIBgAAAA==.',Sk='Skullchick:BAAALAADCgMIAwAAAA==.',Sl='Slawth:BAAALAADCgQIBAAAAA==.Sleepel:BAAALAADCgUIAQAAAA==.',Sm='Smexydeath:BAAALAAECgMIAwAAAA==.Smeyplus:BAACLAAFFIEFAAIOAAMI2BQTAgD/AAAOAAMI2BQTAgD/AAAsAAQKgRYAAg4ACAgQJYAEADoDAA4ACAgQJYAEADoDAAAA.',Sn='Snickeris:BAAALAADCgcIGgAAAA==.Snofawl:BAAALAAECgcIEgAAAA==.',So='Sorisa:BAAALAADCgcIBwAAAA==.Soulstriver:BAAALAADCgIIAgAAAA==.Sovereign:BAABLAAECoEXAAIQAAgIKR+XCACYAgAQAAgIKR+XCACYAgAAAA==.',Sq='Squidd:BAAALAAECgEIAQAAAA==.',St='Stars:BAAALAAECgYICgAAAA==.Steelcow:BAAALAADCgYICQAAAA==.Stinkiepete:BAAALAADCgcIDAAAAA==.Stylepoints:BAAALAAECgMIBgAAAA==.',Su='Sucramonkey:BAAALAADCggIGAAAAA==.Sureno:BAAALAAECgMIAwAAAA==.Sutrii:BAAALAAECgYICgAAAA==.',Sw='Swagpresence:BAAALAAECgcIEAAAAA==.Sweetpickles:BAAALAADCggICAAAAA==.',Sy='Symbiote:BAAALAADCgYICwAAAA==.Syruko:BAAALAADCgEIAQAAAA==.',Sz='Szyphon:BAAALAADCggIDgAAAA==.',Th='Theillest:BAAALAADCgEIAQAAAA==.Thejorlane:BAAALAAECgIIAQAAAA==.Thiccrootz:BAAALAAECgUICwAAAA==.Thiccshields:BAAALAAECgQICQAAAA==.Thicctotemz:BAAALAAECgMICQAAAA==.Thorndot:BAAALAAECgYICQAAAA==.Thornmist:BAAALAADCgYIBgAAAA==.',Ti='Tiama:BAAALAAECgMIAwAAAA==.',To='Toonerfu:BAAALAAECgMIBAAAAA==.Topah:BAAALAADCgcIDQAAAA==.',Tr='Trick:BAAALAAECgYICQAAAA==.Trixietails:BAAALAADCggICAAAAA==.Trox:BAAALAADCgUIBwAAAA==.',Tu='Tuyghy:BAAALAADCggICAAAAA==.',Tw='Twentyone:BAAALAAECgQICAAAAA==.Twiggz:BAAALAAECgUICAAAAA==.',Ty='Tyralen:BAAALAAECgUIBwABLAAECgYICgAFAAAAAA==.Tyrandras:BAAALAAECgYICgAAAA==.Tyrec:BAAALAAECgIIAgAAAA==.',Ul='Uldrag:BAAALAAECgEIAQAAAA==.',Un='Undeadpreist:BAAALAADCgUIBQAAAA==.Undying:BAAALAAECggIEgAAAA==.Unicörn:BAABLAAECoEUAAMOAAcICyRvEQB7AgAOAAcICyRvEQB7AgAYAAcIohJODwDYAQAAAA==.Unlyfe:BAAALAADCggIEAABLAAECgIIAgAFAAAAAA==.',Ur='Urri:BAEALAAECgMIAwABLAAECgMIBAAFAAAAAA==.',Va='Valdreya:BAAALAADCgcIDAABLAAECgYICgAFAAAAAA==.Vauromoth:BAAALAADCgYIBgAAAA==.',Ve='Velyssa:BAAALAAECgMIBAAAAA==.Ventris:BAAALAAECgIIAgAAAA==.Vesaris:BAAALAADCgEIAQAAAA==.',Vi='Vineeshewah:BAAALAAECgMIBAAAAA==.Violen:BAAALAADCgcIDAAAAA==.Vizu:BAAALAAECggIEgAAAA==.',Vo='Volaric:BAAALAADCgcIBwAAAA==.',Vu='Vulsted:BAAALAADCgMIAQAAAA==.',Wa='Wantedd:BAAALAAECgMIAwAAAA==.Warren:BAAALAADCgcIBwAAAA==.',Wi='Wilbo:BAAALAAECgMIBgAAAA==.Wily:BAAALAAECgIIAgAAAA==.Wisperwing:BAAALAADCggICAAAAA==.',Wo='Wolffed:BAAALAADCgcIBwAAAA==.Wormszer:BAAALAADCggIFAAAAA==.Woth:BAAALAADCgYIEQAAAA==.',Wy='Wylds:BAAALAADCggICAABLAAFFAMIBQAVAIcmAA==.Wynds:BAABLAAFFIEFAAIVAAMIhybOAABgAQAVAAMIhybOAABgAQAAAA==.',Xi='Xiaozhi:BAEALAAECgMIBAAAAA==.',Xo='Xologrim:BAAALAADCggICAABLAAECgIIAgAFAAAAAA==.',Xz='Xzariana:BAAALAAECgIIAgAAAA==.',Ya='Yakub:BAABLAAECoEVAAIZAAgI/iTDAwAGAwAZAAgI/iTDAwAGAwAAAA==.',Ye='Yennefer:BAAALAADCgYICQAAAA==.',Yo='Yoirr:BAAALAAECgMIBAAAAA==.',Yt='Ythia:BAAALAAECgIIAgAAAA==.',Yy='Yy:BAAALAAECgYICgAAAA==.',['Yë']='Yëëter:BAAALAADCgcICgAAAA==.',Za='Zach:BAAALAAECgIIAgAAAA==.',Ze='Zeana:BAAALAADCgIIAgABLAAECgMIBAAFAAAAAA==.Zellyne:BAABLAAECoEWAAISAAgI6CJqAgD2AgASAAgI6CJqAgD2AgAAAA==.Zelse:BAAALAAECgMIAwAAAA==.Zeop:BAAALAAECgMIBAAAAA==.Zestt:BAAALAADCgMIAwAAAA==.',Zo='Zorrid:BAAALAADCgIIAgAAAA==.Zorriya:BAACLAAFFIEFAAIMAAMIEwfQAwDDAAAMAAMIEwfQAwDDAAAsAAQKgRUAAgwACAglHiQKAL8CAAwACAglHiQKAL8CAAAA.',['Ây']='Âyepa:BAAALAAECgMIBAAAAA==.',['Ëd']='Ëdison:BAAALAAECgYICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end