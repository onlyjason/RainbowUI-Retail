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
 local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship',}; local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abrakadabruh:BAAALAADCgYIBgAAAA==.',Ad='Adaric:BAAALAADCggICAAAAA==.',Ae='Aeons:BAAALAADCgEIAQAAAA==.Aes:BAAALAAECgMIAwAAAA==.',Af='Afoshadow:BAAALAADCggICAAAAA==.',Ai='Aileron:BAAALAADCgcICAAAAA==.',Am='Aminall:BAAALAADCgYIBwAAAA==.',An='Andar:BAAALAADCgMIAwAAAA==.Andore:BAAALAADCggIDwAAAA==.Anisha:BAAALAAECgMIAwAAAA==.',Ar='Arak:BAAALAAECgEIAQAAAA==.Arkhan:BAAALAAECgEIAgAAAA==.',As='Assbar:BAAALAADCgYIBgAAAA==.Astalar:BAAALAADCgYIBgABLAAECggICgABAAAAAA==.',At='Atreana:BAAALAAECgYICQAAAA==.',Av='Avalerion:BAAALAAECgEIAQAAAA==.Avij:BAAALAADCgUIBQABLAADCgcICgABAAAAAA==.',Ay='Ayoreo:BAAALAAECgIIAgAAAA==.',['Añ']='Añathema:BAAALAAECgEIAQAAAA==.',Bi='Bigpoppapump:BAAALAADCgcIDQAAAA==.',Bl='Blazed:BAAALAADCgMIBQAAAA==.Bloodbeard:BAAALAAECgMIBAAAAA==.Bloomer:BAAALAAECggICAAAAA==.Bluecoral:BAAALAADCgUIBQAAAA==.Blushtime:BAAALAAECgYICQAAAA==.Bluwhale:BAAALAAECggIEwAAAA==.',Bo='Bodanky:BAAALAAECgYICQAAAA==.Boradorson:BAAALAADCgYIDAAAAA==.',Br='Bruno:BAAALAAECgMIBQAAAA==.',Bu='Bunnynuggetz:BAAALAADCgYIBgAAAA==.Burland:BAAALAAECgMIBQAAAA==.',Ca='Callistos:BAAALAAECgMIBQAAAA==.Camelshammy:BAAALAADCggICQAAAA==.Caradyn:BAAALAADCgQIBAAAAA==.Castianna:BAAALAADCgcIEAAAAA==.',Ce='Ceadirec:BAAALAAECgMIAwAAAA==.Celoria:BAAALAADCgQIBQAAAA==.Century:BAAALAAECgQIBQAAAA==.Cerenis:BAAALAAECgcIDwAAAA==.',Ch='Chug:BAAALAAECgYICgAAAA==.',Ci='Circà:BAAALAAECgMIAwAAAA==.Cithrel:BAAALAAECgMIAwAAAA==.',Cl='Cloudninelol:BAAALAAECgYICAAAAA==.',Co='Coconutz:BAAALAADCggICAAAAA==.',Cr='Creolix:BAAALAAECgIIAgAAAA==.',Da='Damnatio:BAAALAAECgYICgAAAA==.Darkclement:BAAALAAECgMIAwAAAA==.Dastro:BAAALAAFFAEIAQAAAA==.Date:BAAALAADCggICAAAAA==.',De='Demetrius:BAAALAADCgMIAwAAAA==.Demonofwar:BAAALAADCggICgAAAA==.',Di='Divinehog:BAAALAAECgYICgAAAA==.',Dm='Dmaan:BAAALAADCggICAAAAA==.',Do='Docsyde:BAAALAAECgEIAQAAAA==.',Dr='Dragonpebble:BAAALAAECgYICAAAAA==.Drahalah:BAABLAAECoEeAAMCAAgIIiMWDAC9AgACAAgIViIWDAC9AgADAAMIdSUMFwBFAQAAAA==.Drahmage:BAAALAAECgUIBgAAAA==.Drezind:BAAALAAECgIIAgAAAA==.Drugar:BAABLAAECoEVAAICAAgIfhwJEgB2AgACAAgIfhwJEgB2AgAAAA==.',Ds='Dskilly:BAAALAADCgcIBgAAAA==.',Dw='Dwaegan:BAAALAADCgMIAwABLAAECgMIBQABAAAAAA==.Dwálin:BAAALAADCgcIBwAAAA==.',Ea='Earthvoodoo:BAAALAADCgQIBAABLAAECgYICgABAAAAAA==.',Eh='Ehunter:BAAALAAECgEIAQAAAA==.',El='Elaenius:BAAALAAECgEIAQAAAA==.Elevated:BAAALAAECgcIEAAAAA==.Elezel:BAAALAADCggICwAAAA==.Ellianneth:BAAALAADCgQIBAAAAA==.Eluneslight:BAAALAADCggIDQAAAA==.',En='Ender:BAAALAADCgIIAgAAAA==.',Ep='Epi:BAAALAAECgYICwAAAA==.Epistasia:BAAALAADCgIIAgAAAA==.',Er='Erniethecow:BAAALAADCggICAAAAA==.Erniethemonk:BAAALAAECgcIDAAAAA==.',Ez='Ezbutton:BAAALAAECgIIAgAAAA==.Ezfix:BAAALAAECgUICQAAAA==.',Fa='Farrago:BAAALAADCgIIAgAAAA==.',Fo='Fourth:BAAALAADCgMIAwAAAA==.',Ga='Garaylo:BAAALAAECgYIEgAAAA==.',Gh='Ghosst:BAAALAAECgYICAAAAA==.',Gi='Giannis:BAAALAADCggIEgAAAA==.Gimlithekind:BAAALAADCggIEQAAAA==.',Gn='Gnonepiece:BAAALAAECgQICAAAAA==.',Gu='Guerrero:BAAALAADCgUIBQAAAA==.',Gw='Gwaan:BAAALAAECgIIAgAAAA==.',Ha='Hammering:BAAALAADCgcIDAABLAAECggIFQACAH4cAA==.',He='Heliòs:BAAALAADCgIIAgAAAA==.',Ho='Hogshock:BAAALAADCggIEQAAAA==.Holygrailz:BAAALAADCgQIBAAAAA==.Holyzel:BAAALAAECgUIBgAAAA==.',Hs='Hsimingjung:BAAALAAECgYIBgAAAA==.',Hy='Hylie:BAAALAADCgMIAwAAAA==.',Ig='Ignatius:BAAALAADCgYIBgAAAA==.',In='Inte:BAAALAADCgcICwAAAA==.',Ip='Ipullpeople:BAAALAADCgcIDAAAAA==.',Ja='Jade:BAAALAADCgMIAwAAAA==.Jaiarix:BAAALAAECgMIAwAAAA==.Jaime:BAAALAAECgMICQAAAA==.Jalani:BAAALAADCgcICQAAAA==.Jalet:BAAALAAECgEIAQAAAA==.Jaydee:BAAALAAECgMIBAAAAA==.',Jc='Jckl:BAAALAADCgMIAwAAAA==.',Jr='Jrjunior:BAAALAADCgMIAwAAAA==.',Ju='Jugsy:BAAALAAECgYICAAAAA==.',Ka='Kayn:BAAALAADCggIEgAAAA==.',Ke='Kebsy:BAAALAAECgUICAAAAA==.Kevonjuravis:BAAALAAECgIIBAAAAA==.',Kh='Khalyl:BAAALAADCggIFgAAAA==.',Ki='Kitcat:BAAALAADCgcIBwAAAA==.',Ko='Koqmo:BAAALAAECgYICAAAAA==.Korez:BAAALAAECgMIAwAAAA==.',La='Labienus:BAAALAADCggIDgAAAA==.Larroy:BAAALAADCgMIBAAAAA==.',Le='Lena:BAAALAADCgEIAgAAAA==.Levanthius:BAAALAADCgIIAgAAAA==.',Li='Lirizeon:BAAALAADCggIDgAAAA==.Lizzybordan:BAAALAADCgEIAgABLAADCggIDwABAAAAAA==.',Lo='Loadine:BAAALAAECgQICgAAAA==.Lokitia:BAAALAADCgcIBwAAAA==.',Lu='Lucinick:BAAALAAECgMIAwAAAA==.Lunathir:BAAALAADCggICAABLAAECggICgABAAAAAA==.',Ma='Macdaduelist:BAAALAADCggIGAAAAA==.Madmartegan:BAAALAADCgMIAwAAAA==.Mantislokout:BAAALAADCgUIBwAAAA==.Marcx:BAAALAAECgYIEgAAAA==.Mariskama:BAAALAAECgMIAwAAAA==.',Me='Meatster:BAAALAADCgQIBAAAAA==.Meowimabear:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Meucci:BAAALAAECgQIBwAAAA==.Mewmaster:BAAALAAECgIIAgAAAA==.',Mh='Mhelora:BAAALAADCggICAAAAA==.',Mi='Mikkais:BAAALAADCgcIBwAAAA==.Milfeater:BAAALAADCggIDgAAAA==.Minimini:BAAALAAECgcIDgAAAA==.',Mo='Moneygk:BAAALAAECggIDgAAAA==.Moolin:BAAALAAECgMIBQAAAA==.Moranthe:BAAALAADCgcIBwABLAAECgYIDgABAAAAAA==.Morneris:BAAALAAECgcIEAAAAA==.',Mu='Muggypew:BAAALAAECggICAAAAA==.Muzik:BAAALAADCgMIBQAAAA==.',My='Mythuneran:BAAALAAECgMIBgAAAA==.',Na='Naheka:BAAALAADCgMIAwAAAA==.',Ne='Neeza:BAAALAAECgMIAwAAAA==.Nena:BAAALAADCggIFgAAAA==.Neria:BAAALAADCgQIBAAAAA==.Neya:BAAALAADCgcIDAAAAA==.',Ni='Ninjainred:BAAALAADCgYIBgAAAA==.Ninjamage:BAAALAADCgcIBwAAAA==.Niteangel:BAAALAADCgMIAwAAAA==.Nithendroz:BAAALAAECgMIAwAAAA==.Nity:BAAALAAECgMIBQAAAA==.',No='Nolameme:BAEALAADCggICAABLAAECgUIBwABAAAAAA==.Noot:BAAALAADCgQIBAAAAA==.',['Nê']='Nêwfie:BAAALAADCggIDAAAAA==.',Oc='Oceans:BAAALAADCgUIBQAAAA==.',Ol='Olgreeneyes:BAAALAAECgMIAwAAAA==.',Or='Orilm:BAAALAAECgYIDAAAAA==.',Pa='Painspongie:BAAALAAECgEIAgAAAA==.Patriza:BAAALAADCggIDwAAAA==.Pavo:BAAALAADCggIDgAAAA==.',Pe='Peejean:BAAALAAECgEIAgAAAA==.Pey:BAAALAAECgYICAABLAAECgYIEAABAAAAAA==.Peyblade:BAAALAADCgIIAgABLAAECgYIEAABAAAAAA==.Peycicle:BAAALAAECgYIEAAAAA==.Peysanity:BAAALAADCgcIBwABLAAECgYIEAABAAAAAA==.Peystruction:BAAALAADCgcICgABLAAECgYIEAABAAAAAA==.Peytan:BAAALAADCgUIBgABLAAECgYIEAABAAAAAA==.',Ph='Phlosidon:BAAALAAECgEIAQAAAA==.',Pi='Pickles:BAAALAAECgIIAgAAAA==.Pippå:BAAALAAECgMIAwAAAA==.',Po='Pokeyruler:BAAALAADCggIFQAAAA==.Powdrpufgirl:BAAALAADCggIDQAAAA==.',Pr='Protect:BAAALAADCgcIBwAAAA==.',['Qì']='Qìlen:BAAALAADCggIFwAAAA==.',Ra='Raein:BAAALAAECgMIAwAAAA==.Rainn:BAAALAAECgUIBwAAAA==.Rainnspow:BAAALAADCggICAAAAA==.Ralofurius:BAAALAADCgcICgAAAA==.Rasril:BAAALAAECgQIBwAAAA==.',Rh='Rhaast:BAAALAADCgYIBgAAAA==.',Ri='Rikeji:BAAALAAECgMIBAAAAA==.Rivenxi:BAAALAAECgcIBwAAAA==.',Ro='Roskolnikov:BAAALAAECgEIAQAAAA==.',Ru='Ruele:BAAALAAECgYIDgAAAA==.Ruenan:BAAALAAECgUICAAAAA==.',Ry='Ryain:BAAALAAECgQIBwAAAA==.',Sa='Sapthat:BAAALAAECgYIDQAAAA==.Sarahlina:BAABLAAECoEaAAIEAAcIjiFwCACZAgAEAAcIjiFwCACZAgAAAA==.Sarapheena:BAAALAADCgUICAAAAA==.Savepebble:BAAALAADCgcIBwABLAAECgYICAABAAAAAA==.',Se='Seather:BAAALAAECgIIAwAAAA==.Seldiane:BAAALAADCgUIBgAAAA==.Selendaa:BAAALAAECgEIAQAAAA==.Senadarra:BAAALAADCggIDgAAAA==.',Sh='Shawperson:BAAALAAECgMIAwAAAA==.Sheri:BAAALAADCgQIBQAAAA==.Shizzi:BAAALAAECgIIAgAAAA==.Shmammy:BAAALAAECgYICgAAAA==.',Si='Sinadara:BAAALAAECgcIEAAAAA==.',Sk='Skalar:BAAALAADCggIDgAAAA==.Skyfall:BAAALAADCgEIAQAAAA==.',Sl='Slight:BAAALAADCggICAAAAA==.',Sm='Smackman:BAAALAAECgYICwAAAA==.',So='Sock:BAAALAAECgQICgAAAA==.Sonny:BAAALAAECgIIAgAAAA==.Sonámbula:BAAALAADCgEIAQAAAA==.Sorrenda:BAAALAADCgcIBwAAAA==.',Sp='Spincycle:BAAALAAECgEIAQAAAA==.Spinetarak:BAAALAADCgEIAQAAAA==.',Sv='Sventhebrave:BAAALAAECgEIAQAAAA==.',Sy='Sykill:BAAALAADCgEIAQAAAA==.Sylira:BAAALAAFFAIIAwAAAA==.',Ta='Tadz:BAAALAADCgUIBgAAAA==.',Te='Teemo:BAAALAAECgYIDQAAAA==.Temanen:BAAALAADCgcIBwAAAA==.',Th='Throdio:BAAALAAECgYICQAAAA==.',Ti='Tigerwang:BAAALAAECgMIBAAAAA==.Timaeus:BAAALAADCggIDgAAAA==.Tinder:BAAALAADCgYICgAAAA==.',To='Todoroki:BAAALAADCgcIDQAAAA==.Tonymontoni:BAAALAADCgYIBwAAAA==.',Tr='Trifflinhoes:BAAALAAECgYIBgAAAA==.',Tu='Turtlë:BAAALAAECgQICgAAAA==.',Tw='Twohoof:BAAALAADCggICAAAAA==.',['Tá']='Tátánká:BAAALAADCgUIBQAAAA==.',['Tä']='Tänithðurden:BAAALAADCgcIBwAAAA==.',['Tû']='Tûrtle:BAAALAAECgMIBAAAAA==.',Um='Umbrabelle:BAAALAADCgIIAgAAAA==.',Un='Unoboom:BAAALAADCgYIBgAAAA==.Unoboxo:BAAALAAECgcIEAAAAA==.',Va='Valorash:BAAALAAECgMIBQAAAA==.Variola:BAAALAAECgIIAgAAAA==.',Ve='Veilofmaya:BAAALAAECgYICAAAAA==.Velarius:BAAALAADCggIDgAAAA==.Veraltah:BAAALAADCgYIDAAAAA==.',Vi='Vibian:BAAALAADCgIIAgAAAA==.Vipermage:BAAALAADCgcICgAAAA==.',Vo='Vodahmin:BAAALAAECggIBQAAAA==.Vonderick:BAAALAADCggIDQAAAA==.Voodoodog:BAAALAAECgYICgAAAA==.',Vr='Vraxxas:BAAALAADCgcIEQAAAA==.',Vu='Vulf:BAAALAAECgEIAQAAAA==.Vulgrimm:BAAALAAECgMIAwAAAA==.',Vy='Vysa:BAAALAADCgYIBgAAAA==.Vyéra:BAAALAADCggIFgAAAA==.',Wa='Wargasm:BAAALAADCgUIBQABLAADCggIDwABAAAAAA==.Watongo:BAAALAAECgMIAwAAAA==.',Wh='Whacky:BAAALAADCgEIAQAAAA==.',['Wø']='Wøeify:BAAALAAECgMIBAAAAA==.',Ya='Yaldabaoth:BAAALAAECgcICAAAAA==.',Yu='Yuji:BAAALAAECgEIAQAAAA==.',Za='Zag:BAAALAAECgIIAgAAAA==.Zazakai:BAAALAADCggIDwAAAA==.',Ze='Zelthauria:BAAALAADCggIDgAAAA==.',Zo='Zoreniil:BAAALAADCgMIAwAAAA==.',Zu='Zugluck:BAAALAADCgcIDgAAAA==.',['Ål']='Ålloria:BAAALAAECgIIAgAAAA==.',['Ör']='Örcfist:BAAALAAECggICgAAAA==.',['ßl']='ßlackßetty:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end