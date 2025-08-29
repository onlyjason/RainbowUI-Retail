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
 local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Shaman-Enhancement','Mage-Arcane','Mage-Fire','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Devastation','Druid-Restoration','Priest-Shadow','Evoker-Augmentation','Rogue-Assassination','Monk-Windwalker',}; local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abor:BAAALAAECgYICQAAAA==.Abracadaniel:BAAALAADCgcIBwAAAA==.',Ad='Adampembe:BAAALAADCgYIBgAAAA==.Adamwarlock:BAAALAADCggIDgAAAA==.',Ae='Aegrus:BAAALAADCggICAAAAA==.',Al='Alcmenegems:BAAALAAECgYICQAAAA==.Alcmeneinen:BAAALAAECgcIEAAAAA==.Althelea:BAAALAADCgMIAwAAAA==.',Am='Ambernora:BAAALAADCgEIAQAAAA==.Amerha:BAAALAADCggICwAAAA==.',An='Anasterion:BAAALAAECgcIEgAAAA==.Angelshare:BAAALAADCggICgAAAA==.Annaeia:BAAALAADCgQIBAAAAA==.Ansley:BAAALAADCgMIAwAAAA==.',Ar='Arukubar:BAAALAADCgQIBAAAAA==.',As='Ashs:BAAALAAECgMIAwAAAA==.Ashárya:BAAALAAECgYIDwAAAA==.Asrok:BAAALAAECgUIBgAAAA==.',At='Atlasdark:BAAALAAECgMIAwABLAADCgcIBwABAAAAAA==.Atlasfallen:BAAALAADCgcIBwAAAA==.',Av='Avraszun:BAAALAADCgYICgAAAA==.',Ba='Balthromaw:BAAALAAECgYICwAAAA==.Barron:BAAALAAECgYICQAAAA==.Batarix:BAAALAAECgMIAwAAAA==.Battlecát:BAAALAADCgEIAQAAAA==.Bawonlakwa:BAAALAADCggICAAAAA==.',Be='Beardwaffle:BAAALAAECgEIAQABLAAECgMIAgABAAAAAA==.Beastrage:BAAALAAECgcIBwAAAA==.Beliel:BAAALAADCgIIAgAAAA==.Belsath:BAAALAAECggIEgAAAA==.',Bi='Billy:BAAALAAECgYIDwAAAA==.Biophage:BAAALAAECgMIBQAAAA==.',Bl='Blackmane:BAAALAADCgYIBgAAAA==.Bladesplicer:BAAALAADCggIFgAAAA==.Blax:BAAALAADCggIDwAAAA==.Bloodhoundss:BAAALAAECgMIBwAAAA==.Bloodricuted:BAAALAAECgYICQAAAA==.Blynks:BAAALAADCgEIAQAAAA==.Blössöm:BAAALAADCggICAAAAA==.',Bo='Bobfx:BAACLAAFFIEFAAMCAAMIxheLAwCxAAACAAIIxBaLAwCxAAADAAIItBASCQCmAAAsAAQKgRcAAwIACAgFIb4BAIICAAIACAgFIb4BAIICAAMAAginE19KAIcAAAAA.',Br='Braydren:BAAALAADCgEIAQAAAA==.Brewhouse:BAAALAADCgYIBgAAAA==.',Bu='Buffmeister:BAAALAADCggICQAAAA==.Bullydi:BAAALAADCgQIAwAAAA==.Buttertar:BAAALAADCgcICQAAAA==.',['Bö']='Böbbyboucher:BAAALAAECgMIAwAAAA==.',['Bü']='Bütterz:BAAALAAECgYICgAAAA==.',Ca='Cadh:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.Cadl:BAAALAAECgIIAgAAAA==.Candy:BAAALAADCgMIAwAAAA==.',Ce='Celeira:BAAALAADCggICQABLAADCggIDAABAAAAAA==.Celestiaroxy:BAAALAAECgYICgAAAA==.',Ch='Chaosmaster:BAAALAADCgMIAwAAAA==.Chucknourish:BAAALAAECgcIBwAAAA==.',Cl='Clarebear:BAAALAADCgQIBAAAAA==.Clearwater:BAAALAADCgcIBwAAAA==.Cluedartsn:BAAALAAECgQIBAAAAA==.',Co='Cocolila:BAAALAADCgQIAwAAAA==.Coeurdeleon:BAAALAAECgcIEAAAAA==.Condemnation:BAAALAAECgcIEAAAAA==.Conspiracy:BAAALAAECgMIAwAAAA==.Convoke:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Coral:BAAALAADCgMIAwAAAA==.Corban:BAAALAADCgQIBAAAAA==.Corebahn:BAAALAADCgQIBAABLAADCgQIBAABAAAAAA==.',Cr='Crayak:BAAALAAECgcICwAAAA==.Criminology:BAAALAADCgMIAwAAAA==.Crossctrl:BAAALAAECgEIAQAAAA==.Crux:BAAALAAECgMIBAAAAA==.',Da='Darkvizzy:BAAALAAECgEIAQABLAAECgYICAABAAAAAA==.Dave:BAAALAADCggICAAAAA==.',De='Deadbones:BAAALAAECgMIAwAAAA==.Deathlando:BAAALAAECgIIAgABLAAECgYICgABAAAAAA==.Demidru:BAAALAADCggIDwAAAA==.Demiplo:BAAALAAECgEIAQAAAA==.Demonbeard:BAAALAAECgMIAgAAAA==.Deralict:BAAALAADCgYIBAAAAA==.Derpah:BAAALAAECgMIAwAAAA==.Deselle:BAAALAAECgIIBAAAAA==.',Di='Diakaze:BAAALAAECgEIAQAAAA==.Discipline:BAAALAAECgYICwAAAA==.',Do='Donatelloh:BAAALAAECgIIAwAAAA==.',Dr='Dracondz:BAAALAAECgMIAwAAAA==.Dragonforce:BAAALAAECgIIBAAAAA==.Dratr:BAAALAAECgUICAAAAA==.Drogbar:BAAALAAECgQIBgAAAA==.Dropshotta:BAAALAAECgUIBQAAAA==.Drstranger:BAAALAADCgYIBgAAAA==.',Du='Dunhamster:BAAALAAECgMIAwAAAA==.Duo:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.Dusksprinter:BAAALAADCgMIAwAAAA==.',Ed='Ediw:BAAALAADCgEIAQAAAA==.',Ek='Ekri:BAAALAADCgYIDAAAAA==.',El='Eladra:BAAALAADCggIDAAAAA==.Eleidon:BAAALAADCgMIAwAAAA==.Elonmeda:BAAALAADCggICwAAAA==.Elowynn:BAAALAAECgYIDwAAAA==.Elèctra:BAAALAADCggIDgAAAA==.',En='Enrit:BAAALAAECgcIDQAAAA==.Entropy:BAAALAAECgMIAwAAAA==.',Eq='Equation:BAAALAAECgIIAgABLAAFFAMIBQAEAJcWAA==.',Er='Eradicator:BAAALAADCgYICgAAAA==.',Es='Esther:BAAALAADCgEIAQAAAA==.',Eu='Euripides:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.',Ev='Evelise:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.Evilham:BAAALAAECgQIBgABLAAECgUIDAABAAAAAA==.Evoklando:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.',Ex='Exorcism:BAAALAAECgEIAQAAAA==.Expectpriest:BAAALAADCggICAAAAA==.',Ez='Ezith:BAAALAADCggICAABLAAECgYICQABAAAAAA==.',Fe='Felzugger:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Fenka:BAACLAAFFIEFAAIFAAQIqQopAABQAQAFAAQIqQopAABQAQAsAAQKgRcAAgUACAhnIfsAACADAAUACAhnIfsAACADAAAA.',Fh='Fhalanx:BAAALAADCggIDgAAAA==.',Fi='Fib:BAAALAAECgYIBwAAAA==.Filthythang:BAAALAADCgEIAQAAAA==.',Fl='Flowdinjudge:BAAALAADCggICAAAAA==.Flreball:BAAALAADCggIDQAAAA==.',Fo='Fourtweenty:BAAALAADCgcIBwAAAA==.',Fr='Framistina:BAAALAAECgMIAwAAAA==.Frostflame:BAAALAAECgYICQAAAA==.',Fu='Furrbidden:BAAALAAECgYICQAAAA==.',Ga='Garrosh:BAAALAAECgMIAwAAAA==.Gastøn:BAAALAADCgYIBgAAAA==.Gazløwe:BAAALAADCgYICgAAAA==.',Ge='Geraniho:BAAALAAECgYIDQAAAA==.',Gh='Ghouse:BAAALAADCggIEAAAAA==.',Gi='Giganteus:BAAALAADCgYIBwAAAA==.',Go='Goblinmyrock:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.Gotfleas:BAEALAAFFAEIAQAAAA==.',Gr='Greyoak:BAAALAAECggIAwAAAA==.Grimthork:BAAALAADCgcIBwAAAA==.Grommkar:BAAALAAECgYIDAAAAA==.Grumpig:BAAALAAECgQIBwAAAA==.Grynth:BAAALAAECgcIEAABLAABCgQIBAABAAAAAA==.',Gu='Gummyxbear:BAAALAAECgcIDQAAAA==.',Ha='Hamachi:BAAALAADCgYIBgABLAAECgUIDAABAAAAAA==.Hanaka:BAAALAADCgUIBQAAAA==.',He='Heal:BAAALAAECgIIAgAAAA==.Healcannon:BAAALAAECgYIDgAAAA==.Hexenmeister:BAAALAAECgMIAwAAAA==.',Hi='Highlordzed:BAAALAADCgMIAwAAAA==.Hintolisu:BAAALAAECgcIDQAAAA==.Hitsme:BAAALAADCgcIBwAAAA==.',Ho='Holybaloney:BAAALAAECgUICgAAAA==.Holysmite:BAAALAAECgQIBAAAAA==.Hopeidontsuc:BAAALAADCgQIBAAAAA==.',Hu='Hulkamaniac:BAAALAADCggICAAAAA==.',Ic='Iceblossom:BAAALAAECgIIAgAAAA==.',Il='Illidarian:BAAALAADCgMIAwAAAA==.Illprepared:BAAALAAECggIBwAAAA==.',Im='Immunè:BAAALAADCgMIAgAAAA==.Imrah:BAAALAAECgMIAwAAAA==.',In='Inflamary:BAAALAAECgYIAwAAAA==.',Is='Isisankh:BAAALAADCgQIAwAAAA==.',Ja='Jaybowski:BAAALAAECgYICQAAAA==.',Je='Jen:BAAALAAECgcIDQAAAA==.',Jo='Jo:BAAALAAECgQIBwAAAA==.Joraan:BAAALAAECgIIAgAAAA==.',Ka='Kamð:BAAALAADCgcIBwAAAA==.Kanami:BAAALAAECgEIAQAAAA==.Kaori:BAAALAAECgMIAwAAAA==.Karamazov:BAAALAAECgMIBgAAAA==.Katzé:BAAALAADCgQIAgAAAA==.Kaynyx:BAAALAAECgYICgAAAA==.',Ke='Kedrik:BAAALAADCggIDwAAAA==.Kelpshake:BAAALAAECgcICwAAAA==.Kenzie:BAAALAADCgQIBAAAAA==.Kerb:BAAALAAECgMIBAAAAA==.Kethulan:BAAALAADCgYICgAAAA==.',Ki='Kissyboots:BAAALAAECgQIBwAAAA==.',Kn='Knockdown:BAAALAADCggICAABLAAECgYICgABAAAAAA==.',Ko='Koinpurse:BAAALAAECgMIAwAAAA==.Kommon:BAAALAADCgcIBwAAAA==.Konjur:BAACLAAFFIEFAAQEAAMIlxauAwBaAAAGAAEIthk6EQBfAAAEAAEIOh6uAwBaAAAHAAEI1QszAgBUAAAsAAQKgRcABAQACAhxJU8GAHkCAAQABghPJU8GAHkCAAYABAgQI7U4AHoBAAcAAQgdC6kNADkAAAAA.',Kr='Krelock:BAAALAAECgUIBwAAAA==.Krymzendeath:BAAALAADCgcIDgAAAA==.Krísztina:BAAALAAECggIAQAAAA==.',Ku='Kueny:BAAALAADCgIIAgABLAAFFAIIAgABAAAAAA==.',['Ké']='Kérrígan:BAAALAADCgcICgAAAA==.',La='Lakey:BAAALAADCggICgABLAAECgcIEAABAAAAAA==.Lakeyy:BAAALAAECgcIEAAAAA==.Lakeyys:BAAALAADCgcICgABLAAECgcIEAABAAAAAA==.Laklin:BAAALAAECgEIAQAAAA==.Lambeal:BAAALAADCgcICwAAAA==.Lazytotems:BAAALAAECgYICwAAAA==.',Le='Legolassy:BAAALAADCggICAAAAA==.Leidaraion:BAAALAAECgUICgAAAA==.Lewless:BAAALAADCgEIAQAAAA==.',Li='Libskwhy:BAAALAAECgMIAwAAAA==.Lisex:BAACLAAFFIEGAAIIAAMIHSKTAQAxAQAIAAMIHSKTAQAxAQAsAAQKgSgAAwgACAiVJTwBAG0DAAgACAiVJTwBAG0DAAkAAQhoHzgvAEQAAAAA.Lithe:BAAALAAECgEIAQAAAA==.',Lo='Locklear:BAAALAAECgYICQAAAA==.Locknrock:BAAALAAECgUICQAAAA==.Loco:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Logic:BAABLAAECoEYAAIGAAgIvSK0CgDcAgAGAAgIvSK0CgDcAgAAAA==.Lorianthe:BAAALAADCgMIAwAAAA==.Lovemyrolls:BAAALAADCggICAAAAA==.Loxy:BAAALAADCggICAAAAA==.',Lu='Luchenta:BAAALAADCgQIAwAAAA==.Lugrax:BAAALAAECgQIBwAAAA==.',Ly='Lynaperez:BAAALAAECggIAgAAAA==.',Ma='Maani:BAAALAAECgUICAAAAA==.Macediin:BAAALAADCgYIBgAAAA==.Macktruk:BAAALAAECgUIBgAAAA==.Macthyr:BAAALAADCggIDAAAAA==.Magicmate:BAAALAAECgYICwAAAA==.Magnet:BAAALAADCgYIBgAAAA==.Makiel:BAAALAADCggICAAAAA==.Malmort:BAAALAADCgEIAQAAAA==.Malricfrost:BAAALAADCggIEwAAAA==.Mamageek:BAAALAAECgUICAAAAA==.Maples:BAAALAADCgcIBwAAAA==.Margella:BAAALAADCggIEQAAAA==.Marksterique:BAAALAAECgQICAAAAA==.',Mc='Mclock:BAAALAAECgMIAwAAAA==.Mcmuffin:BAAALAADCgMIAwAAAA==.',Me='Metalbound:BAAALAADCgcICQAAAA==.Metalvoker:BAAALAADCggICAAAAA==.Meteorman:BAAALAAECgMIBAAAAA==.Meyndflay:BAAALAAECgMIAwAAAA==.',Mi='Milfncookes:BAAALAADCggICwAAAA==.Minata:BAAALAAFFAIIAgAAAA==.Mistapoop:BAAALAADCgUIBQAAAA==.',Mo='Moistgravy:BAAALAAECgQIBwAAAA==.Mokoko:BAABLAAECoEWAAIKAAgIfRulCQCBAgAKAAgIfRulCQCBAgAAAA==.Monaotoro:BAAALAAECgMIBwAAAA==.Monnik:BAAALAADCgcIBwAAAA==.Moomoo:BAAALAAECgQICAAAAA==.Moomoowho:BAAALAADCgYIBgAAAA==.Moothai:BAAALAAECgYICwAAAA==.',Mu='Murloc:BAAALAADCgMIAwAAAA==.',Na='Nagi:BAAALAAECgQIBwAAAA==.Nalah:BAAALAAECgUIBQAAAA==.Narkotik:BAAALAAECgYICAAAAA==.Narly:BAAALAADCgEIAQAAAA==.Natalyne:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.Nazan:BAAALAAECgMIAwAAAA==.Nazer:BAAALAADCgMIAwAAAA==.',Ne='Nellie:BAAALAAECgYIDgAAAA==.Neuron:BAABLAAFFIEFAAILAAMIjyTWAABGAQALAAMIjyTWAABGAQAAAA==.Nevermourn:BAAALAADCgYIBwAAAA==.Nezereth:BAAALAADCgYIBgAAAA==.',Ni='Nickademon:BAAALAAECgIIAgAAAA==.Nigdruu:BAAALAAECgYICQAAAA==.Ninjavc:BAAALAAECgMIAwAAAA==.',No='Noora:BAAALAADCgUIBQAAAA==.',On='Onitenshi:BAAALAADCggIFAAAAA==.',Oo='Oortt:BAAALAAECgYICQAAAA==.',Op='Opracereroll:BAAALAADCgcICQAAAA==.',Or='Oralys:BAAALAADCggICAAAAA==.',Ot='Otheal:BAAALAADCggIDwAAAA==.Otsutsuki:BAAALAAECggICAAAAA==.',Ov='Overdose:BAAALAAECgcIEAAAAA==.',Pa='Padle:BAAALAAECgEIAQAAAA==.Paladín:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Palazar:BAAALAAECgIIAgAAAA==.Palicoco:BAAALAAECgIIAgAAAA==.Pallyivar:BAAALAAECgYICgAAAA==.',Pe='Penguinthief:BAAALAADCgcIBwAAAA==.',Ph='Philconnors:BAAALAADCgYIBgAAAA==.Phobias:BAAALAADCgYIBwAAAA==.',Pi='Piglittle:BAABLAAECoEUAAIMAAgIyhLGFgDxAQAMAAgIyhLGFgDxAQAAAA==.Pillowfight:BAAALAAECgMIAwAAAA==.Pipesong:BAAALAAECgIIAgAAAA==.',Po='Polymer:BAAALAADCgIIBQAAAA==.Polyrhythm:BAAALAAECgUIAgAAAA==.Postmaelone:BAAALAADCggICAAAAA==.Powainfusion:BAAALAADCgMIAwAAAA==.',Pr='Priesticles:BAAALAADCgMIAwAAAA==.Priestoe:BAAALAADCgcIBwAAAA==.Proshvam:BAAALAAECgIIAgAAAA==.',Pu='Puffthemagik:BAAALAADCgYIBgAAAA==.',Ra='Raidarye:BAAALAADCgcIBwAAAA==.Raventer:BAAALAADCggIDwAAAA==.Razàgul:BAAALAAECgIIAgAAAA==.',Re='Reagann:BAAALAAECgQIBAAAAA==.Reale:BAAALAADCgQIBQAAAA==.Reenom:BAAALAADCgcIBwAAAA==.Reginageørge:BAAALAADCgIIAgAAAA==.Rekka:BAAALAADCgYIDAABLAAECgUIDAABAAAAAA==.Restroman:BAAALAADCgMIAwAAAA==.',Rh='Rhainge:BAAALAAECgMIAwAAAA==.',Ro='Robodadyjuan:BAAALAAECgYICQAAAA==.Rogermortis:BAAALAAECgMIAwAAAA==.Ronara:BAAALAADCggIEQAAAA==.Ronpaw:BAAALAADCgEIAQAAAA==.',Ru='Ruptur:BAAALAAECgYICQABLAAFFAMIBQAEAJcWAA==.',Rw='Rwk:BAAALAAECgIIAwAAAA==.',Ry='Ryujinsimp:BAACLAAFFIEFAAMKAAMI1iTbAQAhAQAKAAMI0BrbAQAhAQANAAIIEyKfAADCAAAsAAQKgRgAAwoACAh7JmAAAIYDAAoACAhlJmAAAIYDAA0ABwjoIsUBADUCAAAA.',['Ré']='Récke:BAAALAADCgMIAwAAAA==.',Sa='Salvester:BAAALAAECgMIAwABLAAECggIFAAMAMoSAA==.Samtarkras:BAAALAAECgQICAAAAA==.Saràh:BAAALAADCgcIBwAAAA==.',Se='Selket:BAAALAADCggICAAAAA==.Serivel:BAAALAADCggIEAAAAA==.',Sh='Shadowfrin:BAAALAADCgIIAgAAAA==.Sharkguy:BAAALAADCgYIDAABLAAECgcIDQABAAAAAA==.Shialabeef:BAAALAAECgQICQAAAA==.Shiivera:BAAALAAECgYICgAAAA==.Shuyan:BAAALAADCggIBwAAAA==.Shøcktherapy:BAAALAAECgEIAQAAAA==.',Si='Sindrina:BAAALAAECgYIDgAAAA==.',So='Solvaring:BAAALAADCgcIBwAAAA==.Soulfang:BAAALAAECgQIBgAAAA==.Soulréaver:BAAALAADCgEIAQAAAA==.',St='Starfail:BAAALAAECgYIDQAAAA==.Staxstabs:BAABLAAECoEUAAIOAAgIVh1iBQDmAgAOAAgIVh1iBQDmAgAAAA==.Staxstax:BAAALAAECgYIEgABLAAECggIFAAOAFYdAA==.Stealthdeath:BAAALAAECgYIDwAAAA==.Steelrend:BAAALAAECgIIAgAAAA==.Stefine:BAAALAADCgQIBAAAAA==.Steven:BAACLAAFFIEFAAIPAAMIEA+IAQD2AAAPAAMIEA+IAQD2AAAsAAQKgRcAAg8ACAhnHp0FAJgCAA8ACAhnHp0FAJgCAAAA.Stevenlock:BAAALAADCgcIEgABLAAECgUIBQABAAAAAA==.Stickyfeet:BAAALAAECgMIAwAAAA==.',Su='Suddenshield:BAAALAADCgQIBAABLAAECgYICAABAAAAAA==.Suddentide:BAAALAAECgYICAAAAA==.Superpowers:BAAALAADCggICAAAAA==.Surtur:BAAALAAECgYICwAAAA==.',Sv='Svarit:BAAALAADCggIDAAAAA==.',Sy='Sygismund:BAAALAAECgMIBAAAAA==.Syreyn:BAAALAADCgYIBgAAAA==.Sysecond:BAAALAAECgcIDQAAAA==.',['Së']='Sëlene:BAAALAADCgEIAQAAAA==.',['Sì']='Sìlence:BAAALAADCgcIDgAAAA==.',['Sï']='Sïlence:BAAALAADCgYIBgAAAA==.',Ta='Tagbone:BAAALAAECgcICQAAAA==.Talade:BAAALAADCgIIAgAAAA==.Taotien:BAAALAAECgYICAAAAA==.Taydar:BAAALAADCgYIBgAAAA==.',Tc='Tchaik:BAAALAAECgQIBAAAAA==.',Th='Thaynes:BAAALAAECgYICQAAAA==.',Ti='Tigerugly:BAAALAAECgYIDgAAAA==.Tinytea:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.',To='Togepi:BAAALAADCggIDgAAAA==.',Tr='Traveler:BAAALAADCgYIBgAAAA==.Treepal:BAAALAAECgUIBQAAAA==.Trusinner:BAAALAAECgMIAwAAAA==.',Ts='Tsunt:BAAALAAECgYICQAAAA==.',Tu='Tuba:BAAALAAECgMIAwAAAA==.Turkeyleg:BAAALAAECgIIAgAAAA==.',Ty='Tyriam:BAAALAAECgQIBAAAAA==.Tyriel:BAAALAADCgcIBwAAAA==.',Un='Unholybigsby:BAAALAADCgUIBwAAAA==.Uninstall:BAAALAAECgMIBwAAAA==.',Va='Valyndis:BAAALAADCgYIBgAAAA==.Vandy:BAAALAAECgMIAwAAAA==.Vanion:BAAALAAECgIIAgAAAA==.Varo:BAAALAAECgcIDQAAAA==.',Ve='Vendicia:BAAALAADCggIFQAAAA==.Veronique:BAAALAAECgcIEAAAAA==.Verryxx:BAAALAADCggIDwAAAA==.',Vi='Vihtal:BAAALAAECgMIAwAAAA==.Vikalpha:BAAALAAECgIIAgAAAA==.Vizzeek:BAAALAAECgYICAAAAA==.',Vv='Vvastenfall:BAAALAADCgUIBQAAAA==.',Vy='Vynirian:BAAALAAECgcIDAAAAA==.',Wa='Walterlight:BAAALAADCggICAAAAA==.Warham:BAAALAAECgUIDAAAAA==.',We='Weiningman:BAAALAAECgUIBQAAAA==.Wemetanye:BAAALAADCgcIDQABLAAECgMIAwABAAAAAA==.',Wi='Wiiska:BAAALAAECgMIBgAAAA==.Windoelicker:BAAALAAECgIIBAAAAA==.',Wo='Worgya:BAAALAAECgMIAwAAAA==.',Wu='Wugambino:BAAALAADCgYIBgAAAA==.Wuggles:BAAALAADCgQIBAAAAA==.Wulong:BAAALAAECgYIBgAAAA==.',Xa='Xalatoes:BAAALAAECgMIAwAAAA==.',Xb='Xbalanque:BAAALAAECgMIBAAAAA==.',Xe='Xesa:BAAALAADCgYIBgAAAA==.Xesdrah:BAAALAADCgMIAwAAAA==.',Ye='Yetil:BAAALAAECgMIAwAAAA==.Yey:BAAALAAECgUIBgAAAA==.',Za='Zabazay:BAAALAAECgQICAAAAA==.Zaneth:BAAALAADCggICAAAAA==.Zaughlin:BAAALAADCgMIAwAAAA==.Zaycursed:BAAALAADCggICAABLAAFFAEIAQABAAAAAA==.Zaydream:BAAALAAFFAEIAQAAAA==.Zaydämon:BAAALAAECgEIAQABLAAFFAEIAQABAAAAAA==.',Ze='Zelthrix:BAAALAADCggIDwAAAA==.',Zi='Zieva:BAAALAAECgMIAwAAAA==.Ziggybeast:BAAALAAECgYICwAAAA==.',Zo='Zomboyy:BAAALAAECgUIBwAAAA==.Zophar:BAAALAAECgEIAQAAAA==.',['Ås']='Åstríd:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end