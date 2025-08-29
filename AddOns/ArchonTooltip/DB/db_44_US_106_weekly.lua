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
 local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Paladin-Holy','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Hunter-BeastMastery','Priest-Holy','DemonHunter-Havoc','Rogue-Assassination','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Druid-Feral','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Priest-Discipline','Mage-Arcane','Mage-Fire','Mage-Frost','Shaman-Enhancement','Druid-Restoration','Druid-Balance','Evoker-Devastation','Rogue-Outlaw','Hunter-Marksmanship','Rogue-Subtlety','Priest-Shadow','DeathKnight-Frost',}; local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adofian:BAAALAAECgYICwAAAA==.',Ae='Aech:BAAALAADCggICQAAAA==.Aelestus:BAAALAAECgYICQAAAA==.Aethylthryth:BAAALAAECgMIBQAAAA==.',Af='Afatfinley:BAAALAADCgcICAAAAA==.Aft:BAABLAAECoEUAAIBAAgIzA8mCQC6AQABAAgIzA8mCQC6AQAAAA==.',Ag='Aginor:BAAALAAECgMIBQAAAA==.',Ak='Akumu:BAAALAAECgQICQAAAA==.',Al='Alarkin:BAAALAADCgcICAABLAAECggIFwACAPEkAA==.Alcarde:BAAALAAECgcIDwAAAA==.Aldoan:BAAALAADCggIDAAAAA==.Alialeman:BAAALAADCgYIBwAAAA==.Alikatone:BAAALAADCgcICgAAAA==.Alistraza:BAAALAAECggIEQAAAA==.Alix:BAAALAAECgEIAQAAAA==.Allidra:BAAALAADCggIEQAAAA==.Alpal:BAABLAAECoEXAAIDAAgI4hdpCABBAgADAAgI4hdpCABBAgAAAA==.',Am='Amooki:BAAALAADCgQIBwAAAA==.',An='Andalya:BAAALAAECgEIAQAAAA==.Andrimas:BAAALAADCgIIAgAAAA==.Angelenaholy:BAAALAAECgEIAQAAAA==.Annarose:BAAALAAECgQIBAAAAA==.',Ao='Aonani:BAAALAADCgMIAQAAAA==.',Ar='Arknos:BAAALAADCgcIEAAAAA==.Arshika:BAAALAAECgMIBgAAAA==.Artèmis:BAAALAADCgcIBwABLAAECgEIAQAEAAAAAA==.Arvis:BAAALAADCgcICgAAAA==.Aryxi:BAAALAADCgIIAgAAAA==.',As='Ashowler:BAAALAAECgYICwAAAA==.Asylumm:BAAALAAECgMIAwAAAA==.',At='Atretes:BAAALAAECggIDgAAAA==.',Au='Audiopanda:BAAALAAECgIIAgAAAA==.Aukarana:BAAALAADCgcICgAAAA==.Auronhorn:BAAALAADCgMIAwAAAA==.Auroramoon:BAAALAADCggIEAAAAA==.',Av='Avo:BAAALAAECgYIDwAAAA==.',Ax='Axionar:BAAALAAECgYIDwAAAA==.',Az='Azurejay:BAAALAADCgQIBAAAAA==.Azurend:BAAALAAECgMIBQAAAA==.',Ba='Bahula:BAAALAAECgQICQAAAA==.Bainezhull:BAAALAADCggIDwAAAA==.Bastianos:BAAALAAECgMIAwAAAA==.Battlekattel:BAAALAAECgYIBgAAAA==.',Be='Bearbuttkick:BAAALAADCgIIAgAAAA==.Beastafied:BAAALAADCgMIBgAAAA==.Belron:BAAALAAECgIIAgAAAA==.Belvis:BAAALAAECgYIBgAAAA==.Bereket:BAAALAADCggICAAAAA==.',Bi='Biffler:BAAALAAECgYIDQAAAA==.Bigdumbhuntr:BAAALAAECgMIBQAAAA==.Birdmanjones:BAAALAAECgUIBwAAAA==.',Bl='Blkmagic:BAAALAAECgMIAwAAAA==.Bloodcircus:BAAALAAECgYIDAAAAA==.Bloodreign:BAAALAAECgQIBAAAAA==.Bloodworm:BAAALAADCgcIBwAAAA==.Blotto:BAABLAAECoEXAAMFAAgI/w7SEABxAQAFAAcICQ/SEABxAQAGAAEIQA3MKgA+AAAAAA==.Bluelock:BAAALAAECgIIAwAAAA==.Blåzer:BAAALAAECgIIAwAAAA==.',Bo='Bobbyray:BAAALAAECgIIAgAAAA==.Bobertbigg:BAAALAAECgcIDwAAAA==.Boominator:BAAALAAECgYICQAAAA==.Bowbuttkick:BAAALAADCgQIBAAAAA==.Boxiebrown:BAABLAAECoEXAAIHAAgIyg9uGgAJAgAHAAgIyg9uGgAJAgAAAA==.',Br='Bradymage:BAAALAAECgMIBgAAAA==.Braval:BAAALAADCggICAAAAA==.Breaya:BAAALAADCggIEQAAAA==.Brokuo:BAAALAAFFAMIAwAAAA==.Broon:BAAALAADCgcICAAAAA==.',Bu='Buzzlez:BAABLAAECoEXAAIIAAgIlQ1gHwCqAQAIAAgIlQ1gHwCqAQAAAA==.',Ca='Calboltz:BAAALAAECgUIBQAAAA==.Callmee:BAAALAADCgYIBgAAAA==.Camspally:BAAALAADCggICgAAAA==.Canaalberona:BAAALAADCggICAABLAAECgYIDQAEAAAAAA==.Carl:BAAALAADCgMIAwAAAA==.Carnage:BAAALAAECgMIBQAAAA==.',Ch='Chadgolas:BAAALAADCgcIBwAAAA==.Chanterelle:BAAALAADCggIDgAAAA==.Cheerwine:BAAALAADCggIDgAAAA==.Cheezits:BAAALAAECgcICQAAAA==.Chellevisty:BAAALAADCggICQAAAA==.Chemobog:BAAALAADCgYIBgAAAA==.',Cl='Cleavesancta:BAAALAADCgcIBwAAAA==.',Co='Cougsham:BAAALAAECgIIBAAAAA==.Cowell:BAAALAAECgIIAgAAAA==.',Cr='Crooklyn:BAAALAAECgMIAwABLAADCgEIAQAEAAAAAA==.',Cu='Cutefeet:BAAALAADCgEIAQABLAAECgcIDwAEAAAAAA==.',Cy='Cyntennial:BAAALAAECgIIAgAAAA==.',Da='Damageplan:BAAALAAECgQICQAAAA==.Danneielle:BAAALAADCggIDAAAAA==.Danìel:BAABLAAECoEXAAIJAAgIaB+6CwDLAgAJAAgIaB+6CwDLAgAAAA==.Darkanggell:BAAALAAECgEIAQAAAA==.Darkarts:BAAALAAECgMIBAAAAA==.Darkdaddy:BAAALAAECgMIAwAAAA==.Datgirl:BAAALAADCgEIAQAAAA==.',De='Decimate:BAAALAADCgEIAQAAAA==.Delecto:BAAALAAECgMIAwAAAA==.Delvorak:BAAALAADCggICAAAAA==.Dementedsage:BAAALAADCgMIBAABLAADCgcIFAAEAAAAAA==.Demondar:BAAALAADCggIEAAAAA==.Demonflog:BAAALAADCggIBQAAAA==.Dendalaus:BAABLAAECoETAAIKAAgICCRwAQBJAwAKAAgICCRwAQBJAwAAAA==.Denny:BAAALAADCgQIBAAAAA==.Devi:BAAALAAECgMIAwABLAAECgMIBAAEAAAAAA==.Dewdadew:BAAALAAECgEIAQAAAA==.',Di='Dimsumbun:BAAALAAECgMIAwAAAA==.Dinoxeye:BAAALAADCgcIBwAAAA==.',Do='Donut:BAAALAAECgMIBQAAAA==.Dotyoudead:BAAALAAECggIDQAAAA==.',Dr='Draacarys:BAAALAADCgIIAgAAAA==.Drackka:BAAALAADCggIDwAAAA==.Drackï:BAAALAADCgQIBQAAAA==.Draegon:BAAALAAECgEIAQAAAA==.Dramonk:BAABLAAECoEWAAIGAAgIIyFVBADMAgAGAAgIIyFVBADMAgAAAA==.Drewbert:BAAALAADCggICgAAAA==.Drunknmonkey:BAAALAADCggIDgAAAA==.',Dy='Dyre:BAAALAAECgYIDQAAAA==.',['Då']='Dårknéss:BAAALAAECgIIAwAAAA==.',Eh='Ehngo:BAAALAADCgcIDQAAAA==.',El='Elesia:BAAALAADCgcIFAAAAA==.Ellsnarl:BAAALAADCgUIBQAAAA==.Eltariel:BAAALAADCgIIAgAAAA==.',En='Enbolas:BAAALAADCggIDwAAAA==.Ensera:BAAALAAECgEIAQAAAA==.',Ev='Evilbang:BAAALAAECgEIAQAAAA==.',Ex='Extraho:BAAALAAECgMIAwAAAA==.',Ez='Ezani:BAAALAADCgcIBwABLAAECgQIBQAEAAAAAA==.',Fa='Fabléd:BAACLAAFFIEFAAILAAMI5SB8AgApAQALAAMI5SB8AgApAQAsAAQKgRcABAsACAhrJdkBAFcDAAsACAhrJdkBAFcDAAwAAwjRI2gPAD8BAA0AAwh1H2MkAPwAAAAA.Fatherkøi:BAAALAAECgEIAQAAAA==.',Fe='Felbreaya:BAAALAADCgYICwAAAA==.Femm:BAAALAAECgEIAQAAAA==.Fenic:BAAALAAECgEIAQAAAA==.Feyden:BAAALAADCgcIBwAAAA==.',Fi='Fiiryazell:BAAALAAECgMIAwAAAA==.Fijaswarerth:BAAALAAECgMIAwAAAA==.Fimbulvargr:BAAALAAECgMIAwAAAA==.Finiith:BAABLAAECoEXAAICAAgI8SQ5AQA7AwACAAgI8SQ5AQA7AwAAAA==.Finîth:BAAALAADCgYIBgABLAAECggIFwACAPEkAA==.',Fl='Flogdanoggin:BAAALAADCgMIAwAAAA==.Fluffly:BAAALAADCgQIBAAAAA==.Fløppydisc:BAAALAADCgEIAQAAAA==.',Fo='Foerstul:BAAALAAECgUIBwAAAA==.Forestsky:BAAALAAECgMIAwAAAA==.Foxydh:BAAALAADCgYIDAAAAA==.',Fr='Frankolden:BAAALAADCggIDwAAAA==.Frenchieguy:BAAALAAECgYICAAAAA==.Frostbitedew:BAAALAADCgcICQAAAA==.',Ga='Galdiian:BAAALAAECgEIAQAAAA==.Garnet:BAAALAAECgMIBAABLAAFFAMIBQABAKEjAA==.Gazil:BAAALAAECgYIDAAAAA==.',Gh='Ghosimoon:BAAALAAECgcIDgAAAA==.Ghyran:BAABLAAECoEXAAIOAAgIHCKHAQAPAwAOAAgIHCKHAQAPAwAAAA==.',Gn='Gnollzy:BAAALAAECgUIBQAAAA==.',Go='Gobbaghoul:BAAALAAECgMIAgAAAA==.Goldine:BAAALAADCgQIBQAAAA==.Gorius:BAAALAADCgYIBwAAAA==.',Gr='Grandmacoco:BAABLAAECoEXAAMPAAgIFhndDgBeAgAPAAgIFhndDgBeAgAQAAMIGgL3ZwBqAAAAAA==.Grazhopper:BAAALAADCgYIBgAAAA==.Groggliam:BAAALAADCgcIBwABLAAECgcICgAEAAAAAA==.',Gu='Guizee:BAAALAAECgYIDQAAAA==.Gunslinger:BAAALAAECgMIBAAAAA==.Guretta:BAAALAAECgMIAwAAAA==.',['Gø']='Gøøb:BAAALAAECgMIAwAAAA==.',Ha='Haeneros:BAAALAAECgEIAQAAAA==.Halokitty:BAAALAADCgcIBwAAAA==.Handmemytank:BAAALAADCggICAABLAAECgEIAQAEAAAAAA==.Hardscope:BAAALAADCgQIBAABLAAECgUICAAEAAAAAA==.Harumi:BAAALAAECgMIAwAAAA==.',He='Heafk:BAAALAAECgIIAgAAAA==.Healzforbeer:BAAALAAECgMIAwABLAAECgQICQAEAAAAAA==.Heavyburden:BAAALAADCgcICwAAAA==.Hedgehog:BAAALAAECgYIDwAAAA==.Heisenberf:BAAALAADCgcICwABLAAECggIFwAJAIIhAA==.Helaana:BAAALAAECgIIAwAAAA==.Hellsham:BAAALAAECgYICAAAAA==.Herlyne:BAAALAADCggIDgAAAA==.',Hi='Hirojin:BAAALAAECgEIAQAAAA==.',Ho='Holybuttkick:BAABLAAECoEXAAIRAAgI1h/+CwDCAgARAAgI1h/+CwDCAgAAAA==.Holyfield:BAAALAADCggICwAAAA==.Holyhalfdead:BAAALAADCggIEAABLAAECgEIAQAEAAAAAA==.Holysimte:BAAALAADCggICAAAAA==.Hons:BAAALAAFFAIIAgAAAA==.',['Hö']='Hönk:BAAALAADCgcIBwAAAA==.',Ib='Ibis:BAAALAADCgcIBwAAAA==.',Ic='Icefrost:BAAALAAECgcIDwAAAA==.',Ik='Ikillyoutoo:BAAALAAECgYIDAAAAA==.',Il='Ilithiphobia:BAAALAADCggICAAAAA==.Illyphia:BAAALAADCggICAAAAA==.',Im='Impressions:BAACLAAFFIEFAAISAAMIRSQEAABOAQASAAMIRSQEAABOAQAsAAQKgRcAAhIACAj9JRAAAIIDABIACAj9JRAAAIIDAAAA.',In='Inquisition:BAAALAAECgEIAQAAAA==.',Io='Ioboma:BAACLAAFFIEFAAMTAAMITRtCAwAcAQATAAMITRtCAwAcAQAUAAEIVh3cAQBcAAAsAAQKgRcABBMACAh/INAMAMQCABMACAh/INAMAMQCABQAAQiOGYMLAEkAABUAAQhJHy5AAD8AAAAA.',Ir='Ironwolf:BAAALAAECgYIDwAAAA==.',Is='Ishki:BAAALAADCggICAAAAA==.',It='Ithaela:BAAALAAECgYIBgAAAA==.Itzcoatl:BAAALAAECgEIAQAAAA==.',Iw='Iwillpownu:BAAALAADCgUIBQAAAA==.',Ja='Jabba:BAAALAADCgMIAwAAAA==.Jaden:BAAALAAECgMIAwAAAA==.Jadis:BAAALAADCgcIBAAAAA==.Jaldabaoth:BAAALAADCgYIBgAAAA==.Janoria:BAAALAAECgIIAgAAAA==.',Je='Jenova:BAAALAADCggICAAAAA==.Jerrad:BAAALAAECgUIBQAAAA==.',Jj='Jjuicyfruit:BAAALAADCgcIDgAAAA==.',Jo='Joftokal:BAAALAAECgUICQAAAA==.Jonnibravo:BAAALAADCggICgAAAA==.Jorabna:BAAALAAECgQIBQAAAA==.',Jp='Jpgalloway:BAAALAAECgUICAAAAA==.',Jw='Jwhame:BAAALAADCggIFgAAAA==.',Ka='Kalenex:BAAALAADCgYIBgAAAA==.Kalvaxis:BAAALAAECgEIAQAAAA==.Katakrima:BAAALAADCgQIBQAAAA==.Katherinne:BAAALAADCggICwAAAA==.Kattle:BAABLAAECoEWAAIWAAgImBWNAwBqAgAWAAgImBWNAwBqAgAAAA==.Kazat:BAAALAAECgcICQAAAA==.',Ke='Keinda:BAAALAADCgMIAwAAAA==.Keyasymmash:BAAALAADCggICAAAAA==.Keyrasky:BAAALAAECgIIAgAAAA==.',Kh='Khailyn:BAAALAADCgMIAwAAAA==.',Ki='Kikuu:BAAALAAECgMIBgAAAA==.Killadin:BAAALAAECgMIAwAAAA==.Killakalisi:BAAALAADCgUIBQAAAA==.Kiroa:BAAALAAECgIIBAAAAA==.Kitanya:BAAALAADCggICAABLAAECggIGgAXAJgUAA==.Kitå:BAAALAAECgQICQAAAA==.',Kn='Knocturne:BAAALAAECgMIBQAAAA==.Knoks:BAAALAAECgYIDwAAAA==.Knuckleup:BAAALAAECgMIBAAAAA==.',Ko='Koifish:BAAALAAECgcIDgAAAA==.Koivyr:BAAALAADCgcICQAAAA==.Koreshei:BAAALAADCgcICQAAAA==.Korinda:BAAALAADCggICAAAAA==.Kornytzz:BAAALAAECgIIAwAAAA==.',Kr='Krenerokos:BAAALAADCgYICQAAAA==.',Ku='Kuni:BAAALAAECgMIAwAAAQ==.Kuraokami:BAAALAAECgQICQAAAA==.',Kw='Kwille:BAAALAADCgMIAwAAAA==.',La='Ladrious:BAAALAAECgYIBgAAAA==.Lamynx:BAAALAAECgIIAwAAAA==.Larinstor:BAAALAADCgcIBwAAAA==.Larinstore:BAAALAADCgQIBQAAAA==.Lauvanya:BAAALAADCgYIAQAAAA==.Lawordan:BAAALAADCggICwAAAA==.Lazydragon:BAAALAAECgUICQAAAA==.',Le='Leaperikson:BAAALAAECgEIAQAAAA==.Leithia:BAAALAADCggICAAAAA==.',Li='Lightorzand:BAAALAADCggICAAAAA==.Lileda:BAAALAAECgIIAgAAAA==.Lilgirlblue:BAAALAAECgMIAwAAAA==.Lilwang:BAAALAADCggICQAAAA==.Lintroll:BAAALAAECgIIAwAAAA==.Lion:BAAALAAECgQIBwAAAA==.Livray:BAAALAADCgUIDAAAAA==.',Ll='Llenos:BAAALAAECgIIAgAAAA==.',Lo='Lockdnloadd:BAAALAAECgEIAQAAAA==.Loktress:BAAALAAECgUICQAAAA==.Loriella:BAABLAAECoEaAAMXAAgImBQiDgAeAgAXAAgImBQiDgAeAgAYAAYIQgsqJwA/AQAAAA==.',Lu='Lucyliu:BAAALAADCgQIBQAAAA==.Lunathra:BAAALAADCgIIAgAAAA==.',Ma='Maalk:BAAALAAECggIEQAAAA==.Mabellah:BAAALAADCgEIAQAAAA==.Macallan:BAAALAADCgIIAgAAAA==.Maellyn:BAAALAAECgMIBQAAAA==.Magusultimis:BAAALAAECgMIAwAAAA==.Malzaharr:BAAALAADCgQIBAABLAAECgYIDQAEAAAAAA==.Marbared:BAAALAAECgMIAwAAAA==.Marvolio:BAAALAADCggIDwAAAA==.Masõchist:BAAALAAECgMIAwAAAA==.Matt:BAAALAAECgYICQAAAA==.Mavin:BAAALAADCgYIBgAAAA==.Maylët:BAAALAAECggICAAAAA==.',Me='Mediarahan:BAAALAAECgIIAwAAAA==.Mercia:BAAALAAECgQIBwAAAA==.Mewlock:BAAALAADCgcIBwAAAA==.',Mi='Mikiko:BAAALAADCgcIEAAAAA==.Milamber:BAAALAAECgUICQAAAA==.Milk:BAAALAAECgYICAAAAA==.Millcreek:BAAALAAECgIIAgAAAA==.Mimiruu:BAAALAAECgYIBgAAAA==.Miraul:BAAALAAECgEIAQAAAA==.Missindragon:BAAALAAECgUICQAAAA==.Mistymoot:BAAALAAECgIIAgAAAA==.',Mo='Moduspwnens:BAAALAAECgMIBQAAAA==.Mohg:BAAALAADCgQIBAAAAA==.Mojofabulous:BAAALAAECgcIDwAAAA==.Moonabuns:BAAALAADCgYIBgAAAA==.Mormel:BAAALAAECgMIAwAAAA==.Morphius:BAAALAADCgcIBwAAAA==.',Ms='Mskenway:BAAALAADCgQIBAAAAA==.Msthea:BAAALAADCggIEAAAAA==.',Mx='Mxt:BAAALAADCgYIBgAAAA==.',['Mô']='Môô:BAAALAADCggIDQAAAA==.',['Mý']='Mýstiç:BAAALAADCgIIAgAAAA==.',Na='Naamah:BAAALAAECgEIAQAAAA==.Nagamoto:BAAALAADCgYIBgAAAA==.Nalliella:BAAALAAECgMIBQAAAA==.Narial:BAAALAADCgMIAwAAAA==.Narru:BAAALAAECggIEQAAAA==.',Ne='Nebyula:BAAALAAECgMIAwAAAA==.Necrovis:BAAALAAECgIIAQAAAA==.Nemi:BAAALAADCggIDgAAAA==.',No='Nokee:BAAALAAECgUIBwAAAA==.Norieka:BAAALAADCggIDAAAAA==.Noskillidan:BAABLAAECoEXAAIJAAgIgiEUCwDTAgAJAAgIgiEUCwDTAgAAAA==.Nozeydormu:BAABLAAECoEWAAIZAAgIkRPPDgAgAgAZAAgIkRPPDgAgAgAAAA==.',Nu='Numinous:BAAALAADCgMIAwABLAAECgcIDAAEAAAAAA==.',['Nì']='Nìdålee:BAAALAAECgUICAAAAA==.',Ob='Obmeg:BAAALAADCgcIBwAAAA==.',Od='Odell:BAAALAADCgEIAQAAAA==.Odinn:BAAALAAECgQIBwAAAA==.',On='Onyyx:BAAALAADCggICAABLAAECgEIAQAEAAAAAA==.',Oo='Oofna:BAAALAADCgcIBwAAAA==.',Or='Orionpax:BAAALAADCggIFgAAAA==.Orionsson:BAAALAADCgYIBgAAAA==.',Os='Osò:BAAALAAECgIIAgAAAA==.',Ow='Owocutedk:BAACLAAFFIEFAAIBAAMIoSOLAABHAQABAAMIoSOLAABHAQAsAAQKgRcAAgEACAhIJkUAAIkDAAEACAhIJkUAAIkDAAAA.',Oz='Ozyy:BAAALAADCgIIBQAAAA==.',Pa='Pandadad:BAAALAADCgYIBgAAAA==.Pandough:BAEALAAECgMIAwABLAAFFAMIBQAaAHscAA==.Parisher:BAAALAADCgYIDAAAAA==.Passivetréé:BAAALAADCgcICgAAAA==.Passivewaves:BAAALAADCgUIBQAAAA==.',Pe='Pelthoarder:BAAALAAECgMIBQABLAAECgYICQAEAAAAAA==.Permafrost:BAAALAAECgQIBQAAAA==.',Ph='Phrog:BAAALAADCgcIBwAAAA==.',Pi='Piescez:BAAALAADCgEIAQAAAA==.',Po='Potato:BAAALAAECgQIBwAAAA==.',Pr='Pramzel:BAAALAAECgEIAQAAAA==.Prevlaw:BAAALAAECgMIBAAAAA==.Priestfry:BAAALAADCgcIDAABLAAECgYICAAEAAAAAA==.Protagoras:BAAALAADCggICAAAAA==.',Pu='Puppet:BAAALAADCgcIBwAAAA==.',Py='Pyrophobiac:BAAALAAECgEIAQAAAA==.Pyropractor:BAAALAAECgEIAQAAAA==.',Qw='Qwayne:BAAALAAECgYIBgAAAA==.',Ra='Rafig:BAABLAAECoEXAAITAAgIiyJFCAD7AgATAAgIiyJFCAD7AgAAAA==.Rageinbattle:BAAALAAECgIIAwABLAAECgYIDQAEAAAAAA==.Ralii:BAAALAAECgcICwAAAA==.Raserisinne:BAAALAADCggIBQAAAA==.Rauko:BAAALAADCgYIBgABLAAECgEIAQAEAAAAAA==.',Re='Rewellus:BAAALAAECgcIDwAAAA==.Rexx:BAAALAAECgcIDwAAAA==.',Rh='Rhazzah:BAAALAADCgQIBAABLAAECgEIAQAEAAAAAA==.Rhino:BAAALAADCggICAAAAA==.Rhoc:BAAALAAECgMIAwAAAA==.',Ri='Ricotta:BAAALAADCgQIBAAAAA==.Rif:BAABLAAECoEXAAMbAAgIix6/CQB9AgAbAAgIix6/CQB9AgAHAAUIhxnOOQBHAQAAAA==.Rinzlér:BAAALAADCggIDwAAAA==.Riona:BAAALAAECgQIBwAAAA==.Riskyshammy:BAAALAAECgcIDQAAAA==.Riteaid:BAAALAADCggICAAAAA==.',Ro='Rodolfblanne:BAAALAAECgEIAQAAAA==.Roktor:BAAALAADCggICAAAAA==.Rolexor:BAAALAAECgIIAwAAAA==.Ronok:BAAALAAECgIIAwAAAA==.Rookaki:BAAALAAECgcIBwAAAA==.Rorthach:BAAALAADCggIDgAAAA==.Roru:BAAALAADCggICAAAAA==.Rosethebrute:BAAALAAECgcICgAAAA==.Rosetheholy:BAAALAAECgQIBQABLAAECgcICgAEAAAAAA==.',Ru='Rulk:BAAALAAECgEIAQAAAA==.Rusticdiino:BAAALAAECgUIBgAAAA==.Rutsy:BAAALAADCgYIBgAAAA==.',Ry='Ryshin:BAABLAAECoEVAAQKAAcIfAzTGgCmAQAKAAcIfAzTGgCmAQAcAAIIvwaWFABbAAAaAAII8gKpDABVAAAAAA==.',Sa='Sabeck:BAAALAAECgQIBQAAAA==.Sabyy:BAAALAADCgcIBwAAAA==.Safi:BAAALAAECgMIAwAAAA==.Saltine:BAAALAADCgMIAwABLAAECgQICQAEAAAAAA==.Sanctana:BAAALAAECgUIDAAAAA==.Sapdo:BAECLAAFFIEFAAQaAAMIexzhAACwAAAaAAIInwzhAACwAAAKAAEIICUzCABqAAAcAAEI6x83AwBdAAAsAAQKgRcABBoACAhrJUwCAFQCAAoABghzIlwLAGsCABoABwhFHkwCAFQCABwAAwjNI44KADABAAAA.Sarlek:BAAALAAECgEIAgAAAA==.Sarrath:BAAALAAECgEIAQAAAA==.Savior:BAAALAADCgUIBQAAAA==.',Sc='Scarletfuryy:BAAALAAECgUIBgAAAA==.Scaryu:BAAALAADCggICAABLAAECgMIBAAEAAAAAA==.Schaduwoef:BAAALAADCgYIBgABLAAECgMIAwAEAAAAAA==.',Se='Seanboyydrd:BAAALAADCggICAABLAAECgYICQAEAAAAAA==.Seanboyymage:BAAALAAECgYICQAAAA==.Seina:BAAALAAECgMIAwAAAA==.Selemene:BAAALAADCgMIAwAAAA==.Selohssa:BAAALAAECgMIBAAAAA==.Setanta:BAAALAADCgIIAgAAAA==.Sevella:BAAALAAECgEIAQAAAA==.',Sh='Shagara:BAAALAAECgYICAAAAA==.Shamyspoons:BAABLAAECoEVAAIPAAgILSFUBwDmAgAPAAgILSFUBwDmAgAAAA==.Shanti:BAAALAADCggICAAAAA==.Shiroompa:BAAALAAECgYIDAAAAA==.Shlippitydip:BAAALAAECgEIAQAAAA==.Shoomy:BAAALAAECgIIBAAAAA==.Shortcakes:BAAALAAECgMIAwAAAA==.Shupa:BAAALAADCgEIAQAAAA==.Shupasins:BAAALAAECgcIDwAAAA==.',Si='Simpleyfire:BAAALAAECgIIAwABLAAECgUIBgAEAAAAAA==.Sinon:BAAALAAECgYICAAAAA==.Sithkill:BAAALAAECgEIAQAAAA==.',Sk='Skiva:BAAALAAECgIIAgAAAA==.Skreebo:BAAALAADCgEIAQAAAA==.Skullanbonez:BAAALAADCgYIBgAAAA==.',Sm='Smoothbrain:BAAALAAECgcIEAAAAA==.',Sn='Snipyrcat:BAAALAAECgMIBAAAAA==.',So='Southofheavn:BAAALAADCgcIBwAAAA==.',Sp='Spanks:BAAALAAECgEIAQAAAA==.Sparlyy:BAABLAAECoEXAAIdAAgI3SVRAgBMAwAdAAgI3SVRAgBMAwAAAA==.',Ss='Sswordy:BAABLAAECoEXAAIHAAgIsCBPCQDLAgAHAAgIsCBPCQDLAgAAAA==.Sswordywaves:BAAALAADCggICgABLAAECggIFwAHALAgAA==.',St='Stephhunt:BAAALAADCgQIBAAAAA==.Steprisky:BAAALAAECgEIAQAAAA==.Stimulus:BAAALAAECgQIBgAAAA==.Stinkynuuts:BAAALAADCgYICQAAAA==.Stormcloak:BAAALAAECgMIAwAAAA==.Stormfang:BAAALAADCgcIBwAAAA==.Stormpanda:BAABLAAECoEVAAIPAAcI0RoNFAAYAgAPAAcI0RoNFAAYAgAAAA==.Straathond:BAAALAADCgYIBgABLAAECgMIAwAEAAAAAA==.',Su='Surlym:BAAALAAECgYICQAAAA==.Suzaku:BAAALAADCgYIBgAAAA==.',Sw='Switchglaive:BAAALAAECgIIAwAAAA==.',Sy='Symorolden:BAAALAADCgMIAwAAAA==.Syseloris:BAAALAAECgYICQAAAA==.Sythion:BAAALAAECgIIAgAAAA==.',['Së']='Sëphy:BAAALAADCgcIBwAAAA==.',Ta='Tanao:BAAALAADCggIEwAAAA==.Tandnda:BAAALAADCgUIBQAAAA==.Tarnea:BAAALAADCggICAAAAA==.Tavros:BAAALAAECgIIAwAAAA==.',Te='Teenieween:BAAALAADCggIDAAAAA==.Tehtallone:BAAALAAECgMIAwAAAA==.Terrastormx:BAAALAAECgUIBwAAAA==.Terravesh:BAAALAAECgMIBAAAAA==.Tessia:BAAALAAECgIIAwAAAA==.',Th='Theselin:BAAALAADCgYIBgABLAAECgMIAwAEAAAAAA==.Thopegor:BAAALAADCgIIAgAAAA==.Thornberry:BAAALAADCgMIAwAAAA==.Thundergunt:BAAALAAECgUIBQABLAAECgcIDwAEAAAAAA==.',Ti='Timestop:BAAALAAECgMIBwAAAA==.Tingletong:BAAALAAECgcIDwAAAA==.Tintaglia:BAAALAAECgMIBQAAAA==.Tinybuttkick:BAAALAAECgMIBwAAAA==.Tiramisu:BAAALAAECgIIAwAAAA==.',To='Toaster:BAAALAAECgMIAwAAAA==.Toni:BAAALAADCggIDwAAAA==.Totemem:BAAALAADCgMIAwAAAA==.',Tr='Trustnoone:BAAALAAECgUICQAAAA==.',Tu='Tunawhale:BAAALAAECgIIAwAAAA==.',Tw='Twotoepanda:BAAALAAECgIIAgABLAAECgcIFQAPANEaAA==.',Ty='Tylandra:BAAALAAECgQIBQAAAA==.',Un='Unclecheese:BAAALAADCggICAAAAA==.',Va='Vados:BAAALAADCgEIAQAAAA==.Vaeliir:BAAALAAECgUICgAAAA==.Valhart:BAAALAAECgYIBgAAAA==.Valorion:BAAALAAECgMIBgAAAA==.Vanarra:BAAALAAECgMIAwAAAA==.Vavfurion:BAAALAAECgUIBgAAAA==.',Ve='Velas:BAAALAADCggICAAAAA==.Veloura:BAAALAADCgQIBQAAAA==.Vethemia:BAAALAAECgMIBQAAAA==.',Vi='Vinsama:BAAALAADCggIDgAAAA==.Violentjudge:BAAALAAECgUICQAAAA==.Virgocelest:BAAALAAECgYIDQAAAA==.Vitamincmen:BAAALAAECgMIBAAAAA==.',Vo='Voidmommy:BAAALAADCgYIBgAAAA==.Vonmack:BAAALAADCgcIDgAAAA==.Voodoodin:BAAALAAECgIIAwAAAA==.',Vr='Vreeg:BAAALAAECgMIBQAAAA==.',['Vë']='Vësper:BAAALAAECgEIAQAAAA==.',Wa='Wackamoe:BAAALAAECgMIAwAAAA==.Watsu:BAAALAADCgYIBgAAAA==.',Wh='Wholycow:BAAALAADCggIDAAAAA==.Whoopyy:BAAALAAECgMIBQAAAA==.Whyamialive:BAABLAAECoEYAAMBAAgINyZsAAB5AwABAAgINyZsAAB5AwAeAAEIORz+gABHAAAAAA==.',Wi='Wide:BAAALAAECgcIAwAAAA==.Willowing:BAAALAAECgEIAQABLAAECggIFAAIAPkgAA==.Willowish:BAABLAAECoEUAAIIAAgI+SBvBADtAgAIAAgI+SBvBADtAgAAAA==.Willowism:BAAALAADCggIDwABLAAECggIFAAIAPkgAA==.Winterz:BAAALAAECgIIBAAAAA==.Wizerds:BAAALAAECgYICQABLAAECgYIDQAEAAAAAA==.',Wo='Woob:BAAALAAECgIIAgAAAA==.Wormwort:BAAALAAECgIIAgAAAA==.',Wy='Wytnarthom:BAAALAADCggIEAABLAAECgYICQAEAAAAAA==.Wytohne:BAAALAAECgYICQAAAA==.Wytvori:BAAALAADCgMIAwABLAAECgYICQAEAAAAAA==.',Xa='Xaree:BAAALAAECgMIBQAAAA==.',Xc='Xcat:BAABLAAECoEWAAIRAAgILiDhDAC1AgARAAgILiDhDAC1AgAAAA==.',Xo='Xorlgr:BAAALAADCggICwAAAA==.',Yv='Yvaari:BAAALAADCgcIBwABLAAECgYIBgAEAAAAAA==.Yvida:BAAALAADCggICgAAAA==.',Za='Zaffee:BAAALAAECgMIAwAAAA==.Zaffhavoc:BAAALAADCgcIBwAAAA==.Zatrekas:BAAALAAECgIIAgAAAA==.Zatrekaz:BAAALAAECgcIDAAAAA==.',Zi='Zilgala:BAAALAAECgMIBAAAAA==.Ziunepaws:BAAALAAECgQIBwAAAA==.',Zo='Zompt:BAAALAADCggIDgAAAA==.Zorionsson:BAAALAADCgcICwAAAA==.',Zu='Zugquan:BAAALAAECgMIAwAAAA==.Zumå:BAAALAADCgcIDQABLAAECgIIAwAEAAAAAA==.Zury:BAAALAAECgMIAwAAAA==.Zuu:BAAALAAECgIIAwAAAA==.',Zy='Zyasa:BAAALAAECgYICQAAAA==.Zymar:BAAALAAECgIIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end