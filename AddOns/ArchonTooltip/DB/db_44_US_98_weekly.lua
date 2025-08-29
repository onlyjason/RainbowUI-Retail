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
 local lookup = {'Mage-Arcane','Unknown-Unknown','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','Paladin-Holy','Shaman-Enhancement','Hunter-Marksmanship','DemonHunter-Havoc','Paladin-Retribution','Priest-Holy',}; local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Aberdus:BAAALAAECgMIBAAAAA==.',Ac='Accalon:BAAALAADCgEIAQAAAA==.',Ad='Adubs:BAAALAAECgYIDAABLAAECggIGwABAHwkAA==.Advacus:BAAALAAECgYIDQAAAA==.',Ae='Aelerea:BAAALAADCgcIBwABLAAECgYIDQACAAAAAA==.Aethermoon:BAAALAADCgcIBwAAAA==.',Al='Aldaelon:BAAALAADCgMIAwAAAA==.Aletriss:BAAALAADCgcICgAAAA==.Alexsham:BAAALAAFFAIIAgAAAA==.',Am='Amanduh:BAAALAADCgcIBwAAAA==.Amnorpse:BAAALAADCggIFgAAAA==.',An='Analori:BAAALAADCgUICQAAAA==.Angrycodo:BAAALAADCggIFQAAAA==.Anru:BAAALAADCgYIBwAAAA==.',Ap='Apotheosys:BAAALAADCggICQAAAA==.',Ar='Arachne:BAAALAADCgYICQAAAA==.Arapaho:BAAALAADCgMIAwAAAA==.Ardent:BAEALAADCgUIBQAAAA==.Arystar:BAAALAADCgcIDQAAAA==.',As='Ashaaria:BAAALAADCgcIBwAAAA==.Ashenknight:BAAALAADCgIIAgAAAA==.Ashilyn:BAAALAAECgMIBAAAAA==.',Aw='Awnen:BAAALAAECgEIAQAAAA==.',Az='Azrad:BAAALAAECgMIBgAAAA==.',Ba='Balluh:BAAALAAECgMIBAAAAA==.',Be='Beargrylls:BAAALAADCgUIBQAAAA==.Beartest:BAABLAAECoEVAAIDAAcIWw0MJABLAQADAAcIWw0MJABLAQAAAA==.Bellmage:BAAALAAECgMIBwAAAA==.Beloc:BAAALAADCgYIBgAAAA==.Bertox:BAAALAADCgQIBAAAAA==.',Bi='Biglarge:BAAALAADCggICAAAAA==.Bigolcrities:BAAALAAECgYICQAAAA==.Bippin:BAAALAAECggIAQAAAA==.Bippot:BAAALAAECggIAwAAAA==.',Bl='Blackbride:BAAALAADCgcICgAAAA==.Blt:BAAALAAECggIAQAAAA==.',Bo='Bogorne:BAAALAAECgIIAgAAAA==.Bohvicce:BAAALAADCgcIBwAAAA==.Bonezs:BAAALAAECgYIDgAAAA==.Boomo:BAAALAADCggIDAAAAA==.Boutdatbass:BAAALAADCgcICQAAAA==.',Br='Braxxar:BAAALAAECgYIBgAAAA==.Brewmaster:BAAALAAECgUIBQAAAA==.Brutagon:BAAALAADCggIDwABLAAECgEIAgACAAAAAA==.Bryagh:BAAALAAECgMIBQAAAA==.',Bu='Bufferbug:BAAALAADCgcIBwAAAA==.Bugbear:BAAALAADCggIDwAAAA==.Bullithead:BAAALAAECgIIAgAAAA==.Buttercupz:BAAALAAECgYICQAAAA==.Buttermeupz:BAAALAAECgcIDwAAAA==.Buttsnorkle:BAAALAAECgQIBQAAAA==.',Ca='Cactuss:BAAALAAECgIIAgAAAA==.Calevan:BAAALAADCgMIAwAAAA==.',Ch='Chazboom:BAAALAAECgQICQAAAA==.Chia:BAABLAAECoElAAMEAAcIkBbiCgDvAQAEAAcIkBbiCgDvAQAFAAEIiA3tiQA0AAAAAA==.Chikkn:BAAALAADCggIEAAAAA==.Chomboslice:BAAALAADCggICAAAAA==.',Co='Convoker:BAAALAADCgMIBAAAAA==.Cornish:BAABLAAECoEWAAIGAAgIbBt0BgBeAgAGAAgIbBt0BgBeAgAAAA==.',Cr='Crazybish:BAAALAAECgEIAQAAAA==.Critsncaps:BAAALAADCggICAABLAAECggIAgACAAAAAA==.',Cu='Culdesac:BAAALAADCgQIBAAAAA==.Cutsman:BAAALAAECgcICgAAAA==.',Da='Dabbinshamin:BAAALAADCgMIAwAAAA==.Dads:BAACLAAFFIEFAAIHAAMIjxmkAgAPAQAHAAMIjxmkAgAPAQAsAAQKgRcAAgcACAgtIq0HAOACAAcACAgtIq0HAOACAAAA.Darcpaladin:BAAALAAECgIIAgABLAAECggIFgAIANcTAA==.Darcshaman:BAABLAAECoEWAAIIAAgI1xPBHwC8AQAIAAgI1xPBHwC8AQAAAA==.Darthknight:BAAALAAECgUIBQABLAAECgYICQACAAAAAA==.Darthvoid:BAAALAAECgYICQAAAA==.',De='Decynth:BAAALAAECgUIBgAAAA==.Deezebit:BAAALAADCgYIBgAAAA==.Demodorn:BAABLAAECoEWAAIJAAgIQiBMAgDNAgAJAAgIQiBMAgDNAgAAAA==.Demyst:BAAALAAECgcICgAAAA==.Devilkain:BAAALAADCgcICAAAAA==.',Di='Disruptive:BAAALAAECgMIAwAAAA==.',Dk='Dkinäbox:BAAALAADCgcIBwAAAA==.',Do='Donut:BAAALAADCgcIDQABLAAECgMIAwACAAAAAA==.Dougalleone:BAAALAAECgcIBwAAAA==.',Du='Durjin:BAAALAAECggIBAAAAA==.',Eg='Eggroll:BAAALAAECgcIDQAAAA==.',El='Elvlord:BAAALAADCgYIBgAAAA==.',Em='Emerald:BAAALAADCgUIBQAAAA==.',En='Enser:BAAALAADCggIDgAAAA==.Entrapy:BAAALAAECgUIBQAAAA==.',Er='Erisse:BAAALAADCggICAAAAA==.',Ev='Evilnapkin:BAAALAAECgMIAwAAAA==.Evion:BAAALAAECgUIBgAAAA==.Evoiga:BAAALAAFFAIIAgAAAA==.',Ez='Ezzie:BAAALAAECgMIBAAAAA==.',Fi='Fizwix:BAAALAADCgYIBgAAAA==.',Fl='Flay:BAAALAADCgIIAgAAAA==.',Fo='Fourimborniy:BAAALAADCgYIDAAAAA==.Foxbot:BAAALAAECgcIDQABLAAECgcIEgACAAAAAA==.',Fr='Frenzi:BAAALAAECgEIAQAAAA==.Frostey:BAAALAAECgEIAQAAAA==.',['Fá']='Fáelen:BAAALAAECgcIEAAAAA==.',['Fè']='Fèldweller:BAAALAAECgYICwAAAA==.',Ge='Generaname:BAAALAAECgIIAwAAAA==.',Gi='Gingrbredman:BAAALAAECgEIAQAAAA==.Gintonics:BAAALAADCgYIBgAAAA==.Girthfury:BAAALAAECgIIAgABLAAECggIFwAKAI8RAA==.',Gl='Glassçannon:BAAALAAECggIEwAAAA==.',Go='Goochlathom:BAAALAADCgEIAQABLAAECgUIBQACAAAAAA==.Goom:BAAALAAECgYICQABLAAECgcIDQACAAAAAA==.Goomi:BAAALAAECgcIDQAAAA==.Goomii:BAAALAAECgcIBwABLAAECgcIDQACAAAAAA==.Gordanramsey:BAAALAADCgUIBQAAAA==.Gorok:BAAALAADCgcICwAAAA==.',Gr='Gravykin:BAAALAAECgYICQAAAA==.Grishysham:BAAALAADCgEIAQABLAAECgMIAwACAAAAAA==.Groundbeéf:BAABLAAECoEWAAILAAgIBiZKAABkAwALAAgIBiZKAABkAwAAAA==.Grovoath:BAAALAADCgIIAgAAAA==.',Gu='Gunnysack:BAAALAADCggICwAAAA==.',Gy='Gypsyrose:BAAALAADCggIDwAAAA==.',Ha='Haitrot:BAAALAADCgEIAQAAAA==.Handofnature:BAAALAAECgQIBwAAAA==.Harie:BAAALAAECgMIAwAAAA==.',He='Healsun:BAAALAAECgcICgAAAA==.Heiny:BAAALAAECgYIDgAAAA==.',Hi='Highya:BAAALAAECgUIBgAAAA==.',Ho='Holytest:BAAALAADCggICAABLAAECgcIFQADAFsNAA==.Honeycreeper:BAAALAADCgIIAgABLAAECggIEwACAAAAAA==.Hotzshot:BAAALAAECgYIDAAAAA==.Howboudah:BAAALAADCgcIBwAAAA==.',Hu='Hugebear:BAAALAADCgMIAwAAAA==.',Ic='Iceflare:BAAALAAECgcICgAAAA==.',Id='Idotyouto:BAAALAAECgcIDAAAAA==.',Il='Illidori:BAAALAAECgcIDgAAAA==.Illidrag:BAAALAADCggIBwAAAA==.',Im='Imblind:BAAALAADCgEIAQABLAAECgcIDQACAAAAAA==.Immòrtlzed:BAAALAAECgMIAwABLAAECggIFgAIAIAmAA==.Immørtlzed:BAABLAAECoEWAAIIAAgIgCZKAABsAwAIAAgIgCZKAABsAwAAAA==.',In='Inire:BAAALAAECggIDwAAAA==.',Ir='Irent:BAAALAAECggICAAAAA==.Ironstorm:BAAALAAECgMIBAAAAA==.',Iz='Izzyumi:BAAALAAECgYICgAAAA==.',Ja='Jadelin:BAAALAAECgIIAgAAAA==.Jarlraven:BAAALAADCgEIAQAAAA==.Jaxek:BAAALAAECgcIEgAAAA==.',Je='Jetlag:BAAALAAECgQIBQAAAA==.',Jm='Jman:BAAALAAECgYICwAAAA==.',Jo='Jody:BAAALAADCgcIBwAAAA==.Johnwick:BAAALAAECgMIBgAAAA==.',Ju='Jumpndragon:BAAALAAECggIEAAAAA==.Jumpnjudge:BAAALAAECgcICgABLAAECggIEAACAAAAAA==.Jumpnshoot:BAAALAADCggICAAAAA==.Justgetme:BAAALAAECgYIDgAAAA==.',Ka='Kaariel:BAAALAAECgYIBgAAAA==.Kagger:BAAALAAECgcICAAAAA==.Kallarai:BAAALAAECgIIAwAAAA==.Kalloh:BAAALAAECgQIBwAAAA==.Kaozz:BAAALAADCgcIBwAAAA==.Kardoroth:BAAALAAECgMIBQAAAA==.Kariba:BAAALAAECgQIBwABLAAECggIFQAFAKcgAA==.Karîba:BAABLAAECoEVAAIFAAgIpyB1CQDfAgAFAAgIpyB1CQDfAgAAAA==.',Ke='Keeliori:BAAALAAECgYICQAAAA==.Kelsaz:BAABLAAECoEUAAIMAAgIXSFhBwCvAgAMAAgIXSFhBwCvAgAAAA==.Kelshift:BAAALAAECgMIAwAAAA==.Kerrìgàn:BAAALAAECgYIDAAAAA==.Kestral:BAAALAAECgYICgAAAA==.',Ki='Kickyboots:BAAALAADCgIIAgABLAAECgYIDwACAAAAAA==.Killaa:BAAALAADCgEIAQAAAA==.Kirene:BAAALAAECgYICgAAAA==.',Kn='Knoxic:BAAALAAECgEIAQAAAA==.',Ko='Kohzi:BAAALAADCgcIBwABLAAECgcIEQACAAAAAA==.Kookiie:BAABLAAECoEWAAINAAgI+yIiBwAOAwANAAgI+yIiBwAOAwAAAA==.',Kr='Kromdor:BAAALAAECggIDwAAAA==.',La='Larra:BAAALAAECgcICgAAAA==.Latherwina:BAAALAADCgMIAgAAAA==.Lavalamp:BAAALAAECgcIDQAAAA==.',Le='Leman:BAAALAAECgIIAwAAAA==.Letum:BAAALAADCgMIAwAAAA==.Levitas:BAAALAAECgUICgAAAA==.',Li='Lifebinder:BAAALAADCgYIBgABLAAECgUIBQACAAAAAA==.Limstella:BAAALAAECgYICQAAAA==.Livekyros:BAAALAADCgcICQAAAA==.',Lo='Lockxeno:BAAALAAECgYICQAAAA==.Logical:BAAALAAECggIDQAAAA==.Longsham:BAAALAADCgYIBgAAAA==.Lostmylimbs:BAAALAAECgIIAgABLAAECgYIDAACAAAAAA==.Lostmyvigor:BAAALAAFFAIIAgAAAA==.Lostvoker:BAAALAAECgUICAAAAA==.Louieballz:BAAALAAECgYICQAAAA==.',Lu='Lucarad:BAAALAAECgMIBgAAAA==.',Ly='Lyntara:BAAALAAECgUICwAAAA==.',['Lè']='Lènneth:BAAALAAECgYIDgAAAA==.',['Lì']='Lìly:BAAALAAECgMIBAABLAAECggIEwACAAAAAA==.',Ma='Macmar:BAAALAADCggIDgAAAA==.Maddelyn:BAABLAAECoEbAAIBAAgIfCT3BAAnAwABAAgIfCT3BAAnAwAAAA==.Maeve:BAAALAADCgcIBgAAAA==.Majaer:BAAALAAECggICAAAAA==.Mattshanu:BAAALAADCggICwAAAA==.Mazgruug:BAAALAADCgUIBQAAAA==.',Me='Meanssa:BAAALAAECgEIAQAAAA==.Melaan:BAAALAAECgMIAwAAAA==.',Mi='Midori:BAAALAAECgcICgAAAA==.Mindlesscon:BAAALAAECgUIBgAAAA==.Misosalty:BAAALAAECgYIDgAAAA==.',Mo='Mohbi:BAAALAAECgYICgAAAA==.Morgrave:BAAALAAECgQIBAAAAA==.Morguth:BAAALAAECggICgAAAA==.Moriartì:BAAALAADCggIDwAAAA==.Moriko:BAAALAAECgMIAwAAAA==.Morrgan:BAAALAADCgIIAgAAAA==.Mostlydead:BAAALAADCgcICwAAAA==.',Mu='Muddywater:BAAALAAECgcIBwAAAA==.Murky:BAAALAAECgMIAwAAAA==.',My='Myssa:BAEALAAECgcICgAAAA==.',Na='Nancybrew:BAAALAADCgcIBwABLAAECgYICQACAAAAAA==.Naw:BAAALAADCgQIAwAAAA==.',Ne='Neoma:BAAALAAECgYICAAAAA==.Neppie:BAAALAAECgIIAgAAAA==.Nesqwik:BAAALAADCggIFAAAAA==.',No='Noochallange:BAAALAAECgYICQAAAA==.Norex:BAAALAAECgcICgAAAA==.',Ns='Nsayne:BAAALAADCggIEAAAAA==.',Nu='Nuggie:BAAALAAECgYICwAAAA==.',Ny='Nymia:BAAALAAECgYIDwAAAA==.',['Ná']='Náð:BAAALAADCgQIBAAAAA==.',Ol='Oldmagic:BAAALAAECgMIBQAAAA==.Olizza:BAAALAADCgMIAwAAAA==.Olypsus:BAAALAADCgYIBgABLAAECggIEgACAAAAAA==.',On='Onlyhealz:BAAALAADCgIIAgAAAA==.',Oo='Ooglaboogla:BAAALAAECgYIDAAAAA==.',Ou='Ourouboros:BAAALAAECgMIAwAAAA==.',Pa='Paddlin:BAAALAAECgMIBAABLAAECgUIBQACAAAAAA==.Palibabe:BAAALAAECggICAAAAA==.Pandra:BAAALAADCgIIAgAAAA==.Panzeria:BAAALAADCgIIAQAAAA==.',Pe='Pepo:BAAALAAECgYIDAAAAA==.Pestarion:BAAALAADCgcICwABLAAECggIEAACAAAAAA==.',Ph='Phaedo:BAAALAADCgQIBAABLAAECgYIDgACAAAAAA==.Pheado:BAAALAAECgYICQABLAAECgYIDgACAAAAAA==.Phemah:BAAALAADCgIIAgAAAA==.Phortune:BAAALAADCgcIDgAAAA==.',Pi='Pinprick:BAAALAAECgYICAAAAA==.',Pl='Plank:BAAALAADCgYICgABLAAECgUIBQACAAAAAA==.',Po='Popavlad:BAAALAAECgMIBAAAAA==.Poser:BAAALAADCgYIBgAAAA==.',Py='Pyreiella:BAAALAADCggICwAAAA==.',['Pä']='Pälii:BAAALAAECgYICwAAAA==.',Qu='Quickit:BAAALAAECgEIAQAAAA==.',Ra='Ramaan:BAAALAAECgYICwAAAA==.Ramble:BAAALAADCgcIDAAAAA==.Randd:BAAALAAECgIIAQABLAAECggIEwACAAAAAA==.Ravette:BAAALAAECgMIBwAAAA==.Ravissante:BAAALAADCgMIAwAAAA==.',Re='Reesecupthis:BAAALAAECgYICAAAAA==.Reveurus:BAAALAAECgYIDwAAAA==.',Ro='Rockballs:BAAALAADCgcIBwAAAA==.Ronniemac:BAAALAAECgYICAAAAA==.Roofonfire:BAAALAAECgMIAwAAAA==.',Rs='Rsix:BAAALAADCgMIBAAAAA==.',Ry='Ryteousvigor:BAAALAAECggIAgAAAA==.',['Rõ']='Rõhk:BAAALAADCggICAAAAA==.',Sa='Safehaven:BAAALAAECgEIAgAAAA==.Samwìse:BAAALAAECggIEgAAAA==.Saveena:BAAALAADCggIFAAAAA==.',Sc='Scaes:BAAALAADCggICAAAAA==.Scarlla:BAAALAAECgQIBAAAAA==.Schiggydruid:BAAALAADCggIBwAAAA==.',Se='Sefia:BAAALAAECgcIDQAAAA==.Sereinee:BAAALAAECgMIAwAAAA==.',Sh='Shakkys:BAAALAAECgMIAwAAAA==.Shammy:BAAALAADCggIEAAAAA==.Shiryunuri:BAAALAAECgEIAQAAAA==.Shockkrock:BAAALAADCgQIBAAAAA==.Sháo:BAAALAAECgYICwAAAA==.Shämwôw:BAAALAADCgIIAgAAAA==.',Si='Silsandera:BAAALAAECgYICQAAAA==.Sinswrath:BAABLAAECoEWAAIOAAgIByRLBQAtAwAOAAgIByRLBQAtAwAAAA==.',Sk='Skarfs:BAAALAADCgYIBgABLAAECgYICAACAAAAAA==.Skarre:BAABLAAECoEWAAINAAgI6BUQGQA0AgANAAgI6BUQGQA0AgAAAA==.Skcusnor:BAAALAADCggIFgAAAA==.',Sm='Smiteheal:BAAALAADCgcIDAAAAA==.',Sn='Snaccident:BAAALAAECgcIDAAAAA==.Sneakyteeth:BAAALAAECgYICwAAAA==.',So='Songi:BAAALAAECgcIEAAAAA==.Soulwhisper:BAABLAAECoEWAAMFAAgIDiDzCwC/AgAFAAgIDiDzCwC/AgAEAAEIrwspMQA7AAAAAA==.',Sp='Spyrodruid:BAAALAAECgcIDgAAAA==.Spyromage:BAAALAAECgYIBwABLAAECgcIDgACAAAAAA==.Spyroshaman:BAAALAAECgQIAwABLAAECgcIDgACAAAAAA==.',St='Stabo:BAAALAADCgEIAQAAAA==.Steriss:BAAALAADCgcIBwABLAAECgMIAwACAAAAAA==.Straven:BAAALAAECgMIAwAAAA==.Stårrßerry:BAAALAADCgcICAAAAA==.',Su='Sugarblast:BAABLAAECoEWAAILAAgIriQZAQAWAwALAAgIriQZAQAWAwAAAA==.Suou:BAAALAAECgcICgAAAA==.',Sv='Svekke:BAAALAAECggICQAAAA==.',Sy='Sylvara:BAAALAAECgYIDAAAAA==.',['Sì']='Sìlverado:BAAALAAECgEIAQAAAA==.',Ta='Tandragosa:BAAALAADCgMIAwAAAA==.Tanthyr:BAAALAAECgYICQAAAA==.',Te='Teddy:BAAALAAECgMIBwAAAA==.',Th='Thunderhunt:BAAALAADCgQIBAABLAAECggIFQAOAA0fAA==.Thunderwings:BAABLAAECoEVAAIOAAgIDR/VDgCaAgAOAAgIDR/VDgCaAgAAAA==.',Ti='Tirent:BAAALAAECgMIBgAAAA==.',To='Tokenbeef:BAAALAADCggIEAAAAA==.Tokenshaman:BAAALAAECgMIAwAAAA==.Tombjuice:BAAALAADCgMIAwAAAA==.',Tr='Traeley:BAAALAADCgYICQABLAAECggIEgACAAAAAA==.Tranq:BAAALAADCgcIDQABLAAECgYICwACAAAAAA==.Traylay:BAAALAAECggIEgAAAA==.Tromlui:BAAALAADCgMIAwAAAA==.Trèè:BAAALAADCgYIBgAAAA==.',Tt='Ttocs:BAAALAAECgYICAAAAA==.',Tu='Tujori:BAABLAAECoEWAAIPAAgIkhNOGADmAQAPAAgIkhNOGADmAQAAAA==.',Tw='Twherk:BAABLAAECoEXAAMKAAgIjxFQDQDyAQAKAAgIjxFQDQDyAQAOAAYI5QkwSwAiAQAAAA==.Twinmoonfury:BAAALAAECgYICAAAAA==.',['Tî']='Tîtån:BAAALAADCgEIAQABLAAECgYICwACAAAAAA==.',Ug='Uglydorf:BAAALAAECgYICQAAAA==.',Un='Unsweettea:BAAALAAECgUICAAAAA==.',Va='Valstre:BAAALAAECgYICQAAAA==.',Ve='Veega:BAAALAADCgcICgAAAA==.',Vo='Volissa:BAAALAADCgIIAgAAAA==.',Wa='Waldo:BAAALAADCgcIBwABLAAECgUIBQACAAAAAA==.Warm:BAAALAAECgYICQAAAA==.Wasteofpants:BAAALAADCgYIBgAAAA==.Waterbôy:BAAALAADCgQIBAAAAA==.',We='Weepz:BAAALAADCgEIAQAAAA==.Weewoo:BAAALAADCggICgAAAA==.',Wh='Whatthefurk:BAAALAAECgUIBQAAAA==.Whistles:BAAALAAECgEIAQAAAA==.Whoasked:BAAALAAECgcIEQAAAA==.',Wo='Wolfcolas:BAAALAADCgYIBgAAAA==.Woodja:BAAALAADCggICQABLAAECgcIEAACAAAAAA==.',Xa='Xandralyn:BAAALAADCggICAAAAA==.Xanistra:BAAALAAECgcICgAAAA==.',Ya='Yahyah:BAAALAAECgMIAwAAAA==.Yamashaman:BAAALAADCgYICAAAAA==.',Yo='Yoreka:BAAALAAECgYICwAAAA==.',Za='Zariae:BAAALAADCgUIBQAAAA==.Zaszadin:BAEBLAAECoEWAAIOAAgItB8LEQB/AgAOAAgItB8LEQB/AgAAAA==.Zaxxon:BAAALAAECgYICwAAAA==.',Ze='Zerax:BAAALAAECggIDwAAAA==.',Zi='Zira:BAAALAAECgYICAAAAA==.',Zo='Zoeriku:BAAALAADCgYIDAAAAA==.Zoha:BAAALAAECgEIAQAAAA==.Zoìdberg:BAAALAAFFAIIBAAAAA==.',Zu='Zubzer:BAAALAAECgYICwAAAA==.',Zz='Zzor:BAAALAAFFAIIAgAAAA==.',['Zû']='Zûgg:BAAALAAECgUIBQAAAA==.',['Âk']='Âkroma:BAAALAAECgYICwAAAA==.',['Är']='Ärtemìs:BAAALAADCggIFAAAAA==.',['Ðo']='Ðoubtless:BAAALAADCggIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end