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
 local lookup = {'Shaman-Elemental','Unknown-Unknown','Hunter-Marksmanship','Druid-Restoration','DeathKnight-Frost','Evoker-Devastation','Monk-Mistweaver','Monk-Brewmaster','Hunter-BeastMastery','Druid-Balance','DemonHunter-Vengeance','Mage-Frost','Warlock-Destruction','Mage-Arcane','Rogue-Assassination',}; local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aarkan:BAAALAADCgcIBwAAAA==.',Ae='Aeironok:BAAALAAECgQICQAAAA==.Aetheriel:BAAALAAECgMIAwAAAA==.',Ag='Agdall:BAAALAAECgIIAgAAAA==.Aggronok:BAABLAAECoEYAAIBAAgIMSO1BQAKAwABAAgIMSO1BQAKAwAAAA==.Agorron:BAAALAADCgcIBwAAAA==.',Ak='Akasha:BAAALAADCgcIBwAAAA==.Akatala:BAAALAAECgYIDgAAAA==.Akilah:BAAALAADCgMIAwABLAAECgMICAACAAAAAA==.Akunda:BAAALAAECgYICwAAAA==.',Al='Aladori:BAAALAADCgIIAgAAAA==.Allania:BAAALAADCggICAAAAA==.',Am='Amancitta:BAAALAADCgEIAQAAAA==.',An='Androse:BAAALAAECgMIBQAAAA==.',Ap='Apollon:BAABLAAECoEVAAIDAAgINBEiGgCZAQADAAgINBEiGgCZAQAAAA==.',Ar='Archaldroth:BAAALAADCgcIDgAAAA==.Aridhol:BAAALAAECgMIDQAAAA==.Arixen:BAAALAADCgcICwABLAADCggIDgACAAAAAA==.Arkayik:BAAALAAECgYICwAAAA==.Arnix:BAAALAAECgIIAgAAAA==.Aruj:BAAALAADCggIDQAAAA==.',As='Ashleyblue:BAAALAADCgcIBwAAAA==.Ashragoza:BAAALAADCgIIAgAAAA==.',Au='Aurelìa:BAAALAADCgQIBAAAAA==.',Av='Averah:BAAALAADCgcIBwABLAAECgMIAwACAAAAAA==.Avolokden:BAABLAAECoEXAAIEAAgIpx6vBQCeAgAEAAgIpx6vBQCeAgAAAA==.Avort:BAAALAADCgEIAQABLAAECgYICgACAAAAAA==.',Az='Azargos:BAAALAAECgEIAQAAAA==.Azmyth:BAAALAADCggICAABLAAFFAMIBQAFAGYkAA==.Azmythdk:BAACLAAFFIEFAAIFAAMIZiRDAQBJAQAFAAMIZiRDAQBJAQAsAAQKgRcAAgUACAhdJmUAAIgDAAUACAhdJmUAAIgDAAAA.',Ba='Babòón:BAABLAAECoEUAAIGAAgIKCC7BgDHAgAGAAgIKCC7BgDHAgAAAA==.Baconwrap:BAAALAADCgYIBgAAAA==.Badthots:BAAALAAECgQIBwAAAA==.Baelthas:BAAALAAECgMIBAABLAAECgMIBwACAAAAAA==.Baolin:BAAALAADCgYIBgAAAA==.Baxtercham:BAAALAADCggIDwAAAA==.',Be='Bearys:BAAALAAECgMICAAAAA==.Beet:BAAALAAECgcIDwAAAA==.Belindra:BAAALAAECgMIBAAAAA==.',Bi='Bigkahunas:BAAALAAECgMIBQAAAA==.Bigolblood:BAAALAADCgcIBwABLAAFFAEIAQACAAAAAA==.Bigzacky:BAAALAAECgYIDgAAAA==.Bindottin:BAAALAAECgQIBQAAAA==.Binkiebear:BAAALAADCgMIAwAAAA==.Binsters:BAAALAADCgEIAQAAAA==.Bitshifter:BAAALAAECggIBAAAAA==.',Bl='Bladlast:BAAALAAECgYICwAAAA==.Blankee:BAAALAAFFAIIAgABLAAFFAMIAwACAAAAAA==.Blastr:BAAALAAECgMIBAAAAA==.Blessediron:BAAALAADCgcIDQAAAA==.Bloodraven:BAAALAAECgQICQAAAA==.Bloomthetank:BAAALAAECgIIAgAAAA==.Bludclot:BAAALAAFFAEIAQAAAA==.',Bo='Boglim:BAAALAADCggIEQAAAA==.Boomins:BAAALAAECgYICgAAAA==.Booze:BAABLAAECoEUAAIHAAgIUh2OBACgAgAHAAgIUh2OBACgAgABLAAFFAEIAQACAAAAAA==.Bophades:BAAALAAECgIIBAAAAA==.Bossee:BAAALAAFFAMIAwAAAA==.Bowfdeez:BAAALAADCgEIAQAAAA==.',Br='Bradadin:BAAALAADCggIDgAAAA==.Brainlagg:BAAALAAECgQICQAAAA==.Brewmato:BAAALAADCgEIAQABLAAECgQIBwACAAAAAA==.Brewsly:BAABLAAECoEZAAIIAAgIihGMCgCxAQAIAAgIihGMCgCxAQAAAA==.Brusque:BAAALAADCgcIDgAAAA==.',Bu='Bugbug:BAAALAAECgMIAwAAAA==.Bullfire:BAAALAADCgQIBAAAAA==.Buu:BAAALAADCgcICAAAAA==.',['Bö']='Böbdakimi:BAABLAAECoEXAAMJAAgIZSHqCADSAgAJAAgIZSHqCADSAgADAAEI/QeZTgAxAAAAAA==.',Ca='Caedence:BAAALAADCgcIBwAAAA==.Cairith:BAAALAAECgIIAgAAAA==.Calahir:BAAALAADCgUIBQAAAA==.Calphon:BAAALAADCgUIBQAAAA==.Captcosmo:BAAALAADCggIDwAAAA==.Carthtotems:BAAALAAECgcIDwAAAA==.Cataevok:BAAALAADCgcIBwAAAA==.',Ce='Centu:BAAALAADCgYIBwAAAA==.',Ch='Chaosblood:BAAALAAECgEIAgAAAA==.Cheekstick:BAAALAADCgcICQAAAA==.Chillbrah:BAAALAAECgYIBgABLAAECgYIDQACAAAAAA==.Chithris:BAAALAADCgcIBwAAAA==.Chodoge:BAAALAAECgcIEAAAAA==.Choopi:BAAALAAECgYIBgABLAAFFAEIAQACAAAAAA==.Chopsouië:BAAALAADCgcIBwAAAA==.',Ci='Ciimagi:BAAALAAECgQIBQAAAA==.Cirno:BAAALAAECgQICQAAAA==.',Co='Constantinee:BAAALAADCgcIBwAAAA==.Contagion:BAAALAADCgcIBwAAAA==.Contours:BAAALAADCggICAAAAA==.Copenfel:BAAALAAECgYICgABLAAECggIBwACAAAAAA==.Copevoker:BAAALAAECggIBwAAAA==.Cowtion:BAAALAAECgYIDQAAAA==.',Cr='Cravensworth:BAAALAADCgcICQAAAA==.Creamcheese:BAAALAADCggICAAAAA==.Creators:BAAALAAECgMIAgAAAA==.Crossblêssêr:BAAALAAECgEIAQABLAAFFAIIAgACAAAAAA==.Cryptics:BAAALAADCgIIAgAAAA==.Cryxiss:BAAALAADCgcIDgAAAA==.',Da='Daddylock:BAAALAADCgYIBgAAAA==.Daim:BAAALAAECgEIAQAAAA==.Damevil:BAAALAADCgEIAQAAAA==.Dangelo:BAAALAAECgYICgAAAA==.Dasani:BAAALAADCggIDQABLAADCggIDgACAAAAAA==.Davinia:BAAALAAECgIIAgAAAA==.Dawnshade:BAAALAADCgQIBAAAAA==.',De='Dehoffrynn:BAAALAAECgMIBAAAAA==.Demonicbry:BAAALAADCgUIBAABLAAECgIIBAACAAAAAA==.Depravity:BAAALAAECgQICgAAAA==.Deúz:BAAALAAECgcIDgAAAA==.',Di='Diela:BAAALAAECgMIAwAAAA==.Diesel:BAAALAAECgMIBgAAAA==.Divine:BAAALAAECgIIAgABLAAECgQICQACAAAAAA==.',Dk='Dkandy:BAAALAAECgcIDQAAAA==.',Do='Dogstar:BAAALAADCgcICgAAAA==.Donnyn:BAAALAADCgMIAwAAAA==.Dotsrus:BAAALAAECgYIBgAAAA==.Dovin:BAAALAAECgIIAgAAAA==.Downfawl:BAAALAAECgQIBAABLAAECgcIEAACAAAAAA==.',Dr='Draaenor:BAAALAADCgUIBQAAAA==.Drackon:BAAALAADCgMIAwAAAA==.Draconblaze:BAAALAAECgIIBAAAAA==.Drak:BAAALAADCgMIAwAAAA==.Draxus:BAAALAAECgYICQAAAA==.Drelbekk:BAAALAAECgMIBQAAAA==.Drocthyr:BAAALAAECgQICQAAAA==.Drotation:BAAALAADCgcIBwAAAA==.',Du='Dumabucactao:BAAALAADCgUICQAAAA==.Durbinn:BAAALAAECgcICQAAAA==.Durf:BAAALAADCgQIBAAAAA==.Duska:BAAALAADCgcIFAAAAA==.',['Dé']='Décay:BAAALAADCgUIBQAAAA==.',['Dì']='Dìstürbed:BAAALAAECgYICwAAAA==.',Ea='Eamoon:BAAALAADCggIDwAAAA==.',Ed='Edah:BAAALAADCgEIAQAAAA==.',Ee='Eevah:BAAALAAECgMIBwAAAA==.',Eg='Eggsonrice:BAAALAAECgYIBwAAAA==.',El='Eldeayer:BAAALAADCgEIAQAAAA==.Elementsmash:BAAALAAECgQIBAAAAA==.Eleventeen:BAAALAAECgcIDwAAAA==.Elfnightt:BAAALAAECgMIAwAAAA==.Elithiri:BAAALAAECgEIAwAAAA==.Ellipsisfear:BAAALAADCgYIDAAAAA==.Elosai:BAAALAADCggIDwAAAA==.Elsenorcheto:BAAALAADCgcIDgAAAA==.',En='Envy:BAAALAADCgcIBwABLAADCggIDAACAAAAAA==.',Ep='Epiphany:BAAALAADCggICgAAAA==.',Es='Eseri:BAAALAAECggIDgAAAA==.',Ex='Exarch:BAAALAADCgYIBgAAAA==.Exentrick:BAAALAADCgYIBgAAAA==.',Fa='Fangaxe:BAAALAAFFAEIAQAAAA==.Fartknocker:BAAALAADCgMIAwAAAA==.Fatails:BAAALAADCgcIDAAAAA==.',Fi='Fiatko:BAAALAAECggICAAAAA==.',Fl='Floshotmoo:BAAALAAECgUIBwAAAA==.Fly:BAAALAADCgUIBQAAAA==.',Fr='Fragmental:BAAALAADCggICAABLAAECgMIBgACAAAAAA==.Fragon:BAAALAAECgMIBgAAAA==.Franzen:BAAALAAECgMIAwAAAA==.',Fu='Furypalm:BAAALAAECgcIDgAAAA==.',Ga='Galansus:BAAALAAECgQIBQAAAA==.Gannon:BAAALAADCgYIBgAAAA==.Garfulgur:BAAALAAECgIIAwAAAA==.Garhanu:BAAALAADCgIIAgABLAAECgIIAwACAAAAAA==.Garroxx:BAAALAADCgcIBwABLAAECgIIAwACAAAAAA==.Gaypoc:BAABLAAECoEWAAMKAAgInxKWGgCyAQAKAAcIoBKWGgCyAQAEAAgIhg1lGwCRAQAAAA==.Gazember:BAAALAADCgcIBwAAAA==.',Ge='Gehenna:BAAALAADCgcIDAAAAA==.Gezebel:BAAALAAECgYIBgAAAA==.',Gh='Ghðst:BAAALAAECgUIBwAAAA==.',Gi='Gigabob:BAAALAAECgMIBQABLAAECggIFwAJAGUhAA==.Giganaught:BAAALAAECgMIAwAAAA==.Gilroy:BAABLAAECoEXAAIFAAgI+B+tCgDPAgAFAAgI+B+tCgDPAgAAAA==.',Gl='Glarghal:BAAALAAECgYICQAAAA==.',Go='Goku:BAAALAADCgYICAAAAA==.Goosily:BAAALAADCggIDAAAAA==.',Gr='Grapebevrage:BAAALAAECgYICQAAAA==.Greenleaf:BAAALAADCgQIBAAAAA==.Greentouch:BAAALAADCgcIBwAAAA==.Grevv:BAAALAADCgEIAQAAAA==.Grewt:BAAALAAECgcIEAAAAA==.',Ha='Haliifax:BAAALAADCggIDwAAAA==.Harps:BAABLAAECoEWAAILAAgI0iDxAQDiAgALAAgI0iDxAQDiAgAAAA==.Harrymason:BAAALAADCggICAABLAAECgMIBAACAAAAAA==.Harver:BAAALAAECgYIDQAAAA==.Hashuut:BAAALAAECgMIBgAAAA==.Hate:BAAALAAECgIIAgAAAA==.Hathaw:BAAALAADCgcIDgAAAA==.Hawkeyez:BAAALAADCgYIBwAAAA==.',He='Healarious:BAAALAADCgEIAQAAAA==.Helliod:BAAALAAECgYIDAAAAA==.Herja:BAAALAAECgIIAwAAAA==.',Hi='Hidebound:BAAALAAECgQICQAAAA==.Hitower:BAAALAAECgMIAwAAAA==.',Ho='Hobgoblinn:BAAALAAFFAIIAgAAAA==.Holybel:BAAALAADCggIDgAAAA==.Holydiver:BAAALAAECgYIDAAAAA==.Honeybees:BAAALAADCggIDQAAAA==.Honeydutchtv:BAAALAAECggIEwAAAA==.Hopezherbz:BAAALAAECgYICAAAAA==.',Hu='Hugedonut:BAAALAAECgIIAgAAAA==.Hughmungus:BAAALAAECgYIBwABLAAECgYIDAACAAAAAA==.',['Hë']='Hëcatë:BAAALAADCgIIAgAAAA==.',Ia='Iamshatner:BAAALAAECgEIAQAAAA==.',Il='Ilikeurmoves:BAAALAAECgMIBAAAAA==.Illidew:BAAALAAECgYIDAAAAA==.',Im='Imheated:BAAALAAECgYIDAAAAA==.Iminthegame:BAAALAADCgIIAgAAAA==.',In='Inakha:BAAALAAECgIIAwAAAA==.Iniel:BAAALAADCgYIBgAAAA==.Inuet:BAAALAADCgQIBAAAAA==.',Ir='Ironskin:BAAALAADCgcIBwAAAA==.',It='Itadori:BAAALAADCggIDgAAAA==.Itheron:BAAALAADCgQIBAAAAA==.',Ja='Jackiepandas:BAAALAADCggICAABLAAECggIEQACAAAAAA==.Jafar:BAAALAAECgIIAgAAAA==.Jammylock:BAAALAADCgcIBwAAAA==.Jardin:BAAALAADCgcICQAAAA==.',Jb='Jbsham:BAAALAADCgcICwAAAA==.',Je='Jessbae:BAAALAAECgUICgAAAA==.',Ji='Jimmypage:BAAALAAECgQIBgAAAA==.',Jo='Joe:BAAALAAECgUIBgAAAA==.Johnnybgood:BAAALAAECgQIBAAAAA==.',Jt='Jtrain:BAAALAAECgYIDgAAAA==.',Ju='Juicedmoose:BAAALAAECgYICwAAAA==.Junundu:BAAALAAECggIAQAAAA==.Justahhtank:BAAALAADCgcIDgAAAA==.',Ka='Kaelisse:BAAALAADCggIDQAAAA==.Kaelstrada:BAAALAAECgMIBwAAAA==.Kaennä:BAAALAAECgYIDQAAAA==.Kaldorlon:BAAALAADCgcIBwAAAA==.Kamisria:BAAALAAECgcIEQAAAA==.Kari:BAAALAAECgQICQAAAA==.Kattah:BAAALAADCggIDQAAAA==.Kavikk:BAAALAAECggIAwAAAA==.',Ke='Keldelan:BAAALAADCggIDAAAAA==.Kellbells:BAAALAADCggICAAAAA==.',Kn='Knoctürnal:BAAALAAECggIEQAAAA==.',Ko='Korvold:BAAALAADCggICAAAAA==.Kozzy:BAAALAADCggICAAAAA==.',Kr='Kravsham:BAAALAADCgUIBQAAAA==.',Ky='Kylisse:BAAALAADCggIEwAAAA==.',['Kä']='Känakä:BAAALAADCgcIBwAAAA==.',La='Lakab:BAAALAAECgQIBwAAAA==.Lasagna:BAAALAAECgYICwAAAA==.Lash:BAAALAADCgcIBwAAAA==.Lastina:BAAALAADCgIIAgAAAA==.Laufeyenjoy:BAAALAAECggICAAAAA==.',Le='Leassar:BAAALAAECgYICQAAAA==.Leecy:BAAALAADCgQIBQAAAA==.Leget:BAAALAADCggICAAAAA==.Lexxe:BAAALAAECgcICwAAAA==.',Li='Liamneesons:BAAALAAECgQICQAAAA==.Liluana:BAAALAAECgcIDgAAAA==.Linzalina:BAAALAAECgcIDAAAAA==.',Lo='Lockrian:BAAALAAECgYIDQAAAA==.Lolrush:BAACLAAFFIEFAAILAAMIyAnlAADEAAALAAMIyAnlAADEAAAsAAQKgRcAAgsACAgoHaIEAFkCAAsACAgoHaIEAFkCAAAA.Lovetea:BAAALAAECgMIBAAAAA==.',Lu='Luminni:BAAALAAECgMIBQAAAA==.Luxdae:BAAALAADCgYIBgAAAA==.',Ly='Lyall:BAAALAAECgYICQAAAA==.Lyrnn:BAAALAAECgEIAQAAAA==.',['Lø']='Løveshøck:BAAALAADCgEIAQABLAAECgMIBAACAAAAAA==.',Ma='Maddpriest:BAAALAADCgcIDAAAAA==.Mainmoon:BAAALAAECgcIDgAAAA==.Mangoism:BAAALAAECgIIAgAAAA==.Manyax:BAAALAAECgYIBgAAAA==.Marygolden:BAAALAAECgEIAQABLAAECgMICAACAAAAAA==.Masadeushi:BAAALAAECgUICAAAAA==.Masstta:BAAALAADCgQIAwAAAA==.Mavesa:BAAALAAECgEIAQAAAA==.',Me='Melsea:BAAALAADCggIEwAAAA==.Metharian:BAAALAADCggIDgAAAA==.Meyrl:BAAALAADCgUIBQAAAA==.',Mi='Missclickies:BAAALAAECgYIDAAAAA==.Misspeled:BAAALAADCgQIBAABLAAECgYIDAACAAAAAA==.',Mo='Moistbimbo:BAAALAAECgMIBAAAAA==.Mokoto:BAAALAAECgYIDQAAAA==.Mona:BAAALAAECgMIAwAAAA==.Monkheals:BAAALAAECgIIAgAAAA==.Moontzu:BAAALAADCggIBwABLAAECgMIAwACAAAAAA==.Morik:BAAALAADCgcIBwAAAA==.Morphs:BAAALAADCgcIDgAAAA==.',My='Mylittlepwny:BAAALAADCgIIAgAAAA==.Myneria:BAAALAADCggIEQAAAA==.',['Mä']='Märin:BAAALAADCgcIDAAAAA==.',Na='Nate:BAABLAAECoEXAAIMAAgIKR9KAwDjAgAMAAgIKR9KAwDjAgAAAA==.Natinal:BAAALAAECgcIDgAAAA==.',Ne='Necromanced:BAAALAAECgcIEAAAAA==.Neff:BAAALAADCgYIBgAAAA==.Nessie:BAAALAADCggIEAABLAAECggIFAANAHQbAA==.Nexkaa:BAAALAAECgQICAAAAA==.',Ni='Nikoll:BAAALAADCgcIFQAAAA==.Nimbles:BAAALAADCgIIAgAAAA==.Nimi:BAAALAAECgQICQAAAA==.',No='Nonhealer:BAAALAAECgUIBgAAAA==.Nonordon:BAAALAADCggICAABLAAECgYICwACAAAAAA==.',Og='Ogier:BAAALAAECgQIBQAAAA==.',Oh='Ohbbes:BAAALAADCgUIBgAAAA==.',On='Onlydans:BAAALAAECgQICQAAAA==.',Or='Orinj:BAAALAAECgYIDAAAAA==.Orm:BAAALAAECgQICQAAAA==.',Pa='Packer:BAAALAADCgYIBAAAAA==.Pallymurph:BAAALAAECgIIAgAAAA==.Pannfried:BAAALAADCgEIAQAAAA==.Paopao:BAAALAAECgUIBQAAAA==.Pauladeen:BAAALAAECgYIBgABLAAECgYIDAACAAAAAA==.',Pd='Pdpaul:BAAALAADCggIDAAAAA==.',Pe='Pearlzinha:BAAALAAECgIIAgAAAA==.Pekka:BAAALAAECgcIDgABLAAECgcIDgACAAAAAA==.',Ph='Philo:BAAALAADCgUIAwAAAA==.Phin:BAAALAAECgYIDgAAAA==.Phuga:BAAALAADCggICAAAAA==.',Pi='Pig:BAAALAADCgEIAQAAAA==.Pitchblack:BAAALAAECgIIAgABLAAECgYIDgACAAAAAA==.',Pl='Plush:BAAALAAECggIEwAAAA==.',Pr='Prathos:BAAALAADCgcIBwAAAA==.Prayer:BAAALAADCgcIBwAAAA==.Prettyfrosty:BAAALAAECgYICgAAAA==.Primals:BAAALAADCgcIBwAAAA==.Primestock:BAAALAAECgYIDQAAAA==.',Pu='Puffsummons:BAAALAAECgYICwAAAA==.Purify:BAAALAAECgQICQAAAA==.',Py='Pyrannor:BAAALAADCggIFQAAAA==.Pythonpat:BAAALAAECgMIBAAAAA==.',Qu='Quadinel:BAAALAADCggIJAAAAA==.Quinie:BAAALAADCgEIAQAAAA==.Quinifer:BAAALAAECgYICgAAAA==.',Ra='Rabid:BAAALAADCgcICwAAAA==.Radamantys:BAAALAAECgIIBgAAAA==.Raendis:BAAALAADCggICAABLAAECgIIAgACAAAAAA==.Ralandrov:BAAALAADCgYIBgAAAA==.Raygedemon:BAAALAAECgEIAwAAAA==.Razdurin:BAAALAADCgYIBgAAAA==.',Re='Redspally:BAAALAAECgUICAAAAA==.Regenerate:BAAALAAECgYIBgAAAA==.Revenge:BAAALAAECgYIDwAAAA==.Rezear:BAAALAAECgMIBAAAAA==.',Ri='Rikez:BAAALAADCggIDgAAAA==.',Ro='Rose:BAAALAADCgcIBwAAAA==.Rowsdower:BAAALAAECgYICgAAAA==.',Ru='Rubez:BAAALAAECgQIBAAAAA==.',['Rí']='Rínzler:BAAALAADCggIBgABLAAECgUICAACAAAAAA==.',Sa='Sampink:BAAALAAECgcICwAAAA==.Sanquites:BAAALAAECgYIBwAAAA==.Sasudkbowser:BAAALAAECgMIAwAAAA==.Sasuke:BAAALAAECgYIDAAAAA==.Satoru:BAAALAADCgYIBgAAAA==.',Sc='Scalebait:BAAALAAECgQIBgAAAA==.Scotygrippen:BAAALAAECgIIAgAAAA==.',Se='Seifer:BAAALAAECgUICAAAAA==.Selistras:BAAALAAECgcIEQAAAA==.Sembra:BAAALAAECgcIDwAAAA==.',Sh='Shadowdeity:BAAALAADCgcIBwAAAA==.Shallock:BAAALAAECgQIBQAAAA==.Shammÿ:BAAALAAECggIAgAAAA==.Shampåyne:BAAALAADCggIDgAAAA==.Shamwowz:BAAALAAECgMIBwAAAA==.Shaxy:BAAALAAECgcICgAAAA==.Shayhaycook:BAAALAAECgQIBwAAAA==.Sheylafare:BAAALAAECgEIAQABLAAECgUICAACAAAAAA==.Shindra:BAAALAAECgIIAgAAAA==.Shlice:BAAALAAECgIIAgAAAA==.Shunt:BAAALAADCgQIBAAAAA==.Shuraina:BAAALAADCgcICQAAAA==.Shylachase:BAAALAADCgcIDgAAAA==.Shylasloan:BAAALAADCggIEAAAAA==.',Si='Sindelkrocks:BAAALAADCgcICgAAAA==.Sinisterion:BAAALAAECgYICQABLAAECggIEQACAAAAAA==.Sixshotwilly:BAAALAADCgYICQAAAA==.',Sk='Skron:BAAALAADCgcIBwABLAAECgMICAACAAAAAA==.Skuna:BAAALAAECgEIAQAAAA==.Skylane:BAAALAADCggIDQAAAA==.',Sl='Slor:BAAALAADCgEIAQAAAA==.Slugbug:BAAALAAECgEIAgAAAA==.',Sm='Smirkyimp:BAAALAADCggIDwAAAA==.',Sn='Snanth:BAABLAAECoENAAIMAAYIvxpTDQDxAQAMAAYIvxpTDQDxAQAAAA==.Snooze:BAAALAAFFAEIAQAAAA==.Snuudle:BAAALAADCgYIBgAAAA==.',So='Solteris:BAAALAAECgYIBgAAAA==.',Sp='Spalling:BAAALAAECgIIAgAAAA==.Spauunn:BAAALAAECgMIBwAAAA==.Speculative:BAAALAAECggIEAAAAA==.Spelleria:BAAALAADCgMIAwAAAA==.Spitfire:BAAALAAECggIEgAAAA==.Sploof:BAAALAADCggICAAAAA==.Spulby:BAAALAAECgcIDgAAAA==.Spyroh:BAAALAADCgIIAwABLAADCgYIBgACAAAAAA==.',Sq='Squee:BAABLAAECoEUAAMOAAYIDhfaMACmAQAOAAYIDhfaMACmAQAMAAIIfwQAPABTAAAAAA==.',St='Stoopadin:BAAALAADCggICAABLAAECgYICAACAAAAAA==.Stoopedholy:BAAALAAECgYICAAAAA==.Stubbs:BAAALAADCgcICAAAAA==.',Su='Sumato:BAAALAAECgQIBwAAAA==.Sunalae:BAAALAAECgIIAgAAAA==.Suo:BAAALAADCgIIAgAAAA==.',Sw='Sweetbee:BAAALAADCggIDQAAAA==.',Sy='Syllata:BAAALAAECgQIBwAAAA==.Sylvae:BAAALAADCgMIAwAAAA==.Sylvianna:BAAALAAECgYIEAAAAA==.',Ta='Taichee:BAAALAADCgMIAwAAAA==.Taoist:BAAALAAECgMIAwAAAA==.',Te='Temuhealer:BAAALAADCgcIEgAAAA==.Teppic:BAAALAAECgcIDwAAAA==.Terabow:BAAALAAECgQICQAAAA==.Ternu:BAAALAAFFAEIAQAAAA==.Terraxia:BAAALAAECgIIAgAAAA==.',Th='Thedie:BAAALAAECgEIAQAAAA==.Therla:BAAALAAECgIIAgAAAA==.Thicklatina:BAAALAAECgEIAQAAAA==.Thoughtless:BAAALAAECggICAAAAA==.',Ti='Tim:BAAALAADCggIDQAAAA==.Tiny:BAAALAAECgQICQAAAA==.Titantelli:BAABLAAECoEYAAIPAAgIphZSCwBtAgAPAAgIphZSCwBtAgAAAA==.Titin:BAAALAAECgIIAgABLAAFFAEIAQACAAAAAA==.',To='Totem:BAAALAAECgYIBgAAAA==.Totenschein:BAAALAADCggIDwAAAA==.',Tr='Trixibell:BAAALAADCggIDgAAAA==.Troiika:BAAALAAECgMIAwAAAA==.',Tu='Tumultus:BAAALAADCggIDQAAAA==.Turdlingus:BAAALAADCgcIBwAAAA==.',Tw='Twerknwrk:BAAALAADCgYIBgAAAA==.',Ty='Tylennidar:BAAALAAFFAEIAQAAAA==.Tylethian:BAAALAADCgcICgAAAA==.Tyniel:BAAALAADCggIEAAAAA==.Tyroth:BAAALAADCgYIBgAAAA==.',Un='Unhallowed:BAAALAAECgcIEAAAAA==.',Up='Upchuck:BAAALAADCgcIDgAAAA==.',Ur='Urexwife:BAAALAADCgYICAAAAA==.Urumagus:BAAALAADCgcIBwABLAADCgcIDgACAAAAAA==.Urusmash:BAAALAADCgcIDgAAAA==.',Va='Valael:BAAALAADCgIIAgAAAA==.Valdris:BAAALAAECgMIAwAAAA==.Valistrasza:BAAALAAECgMIBAABLAAECgMIBwACAAAAAA==.Vanic:BAAALAAECgEIAQAAAA==.Vanillite:BAAALAAECgQIBgAAAA==.',Ve='Velragon:BAAALAAECgYIDAAAAA==.Vexinnhexin:BAAALAADCgYICgAAAA==.',Vh='Vhx:BAAALAADCggIDwAAAA==.',Vi='Vikander:BAAALAADCgUICAABLAAECggIAQACAAAAAA==.Vixelle:BAAALAADCgcIDgAAAA==.',Vl='Vladdracule:BAAALAADCgEIAQAAAA==.',Vo='Voker:BAAALAADCgIIAgAAAA==.Vort:BAAALAAECgYICgAAAA==.',Vr='Vrykin:BAAALAADCgEIAQAAAA==.',['Vï']='Vïxenô:BAAALAAECgcIDwAAAA==.',Wa='Warcook:BAAALAADCgcIDgABLAAECgQIBwACAAAAAA==.Warturtle:BAAALAADCgcIBwAAAA==.Warvessel:BAAALAAECgcIDQAAAA==.Warxiez:BAAALAADCggIDgAAAA==.',Wh='Whirt:BAAALAAECgQICQAAAA==.Why:BAAALAAECgMIAwAAAA==.',Wi='Widowmaker:BAAALAAECgYIDgAAAA==.Windowmaker:BAAALAADCgUIBQAAAA==.Wishes:BAAALAADCgYIBgAAAA==.',Wo='Wobblanks:BAAALAADCgMIAwABLAADCggIEAACAAAAAA==.',Xa='Xavilic:BAAALAAECgMIBwAAAA==.',Xe='Xentric:BAAALAADCgYIBgAAAA==.',Xu='Xulio:BAAALAADCgcIDQAAAA==.',Xy='Xylorkian:BAAALAAECgQIBAAAAA==.',Yo='Younban:BAAALAADCggIEAAAAA==.',Za='Zafguy:BAAALAADCgcIBwAAAA==.Zahlxr:BAAALAAECgMIBwAAAA==.Zahlzr:BAAALAAECgMIAwABLAAECgMIBwACAAAAAA==.Zapraz:BAAALAAECgIIAgABLAAECggIAwACAAAAAA==.',Ze='Zephyrus:BAAALAADCggICAAAAA==.Zepoly:BAAALAADCgcIDgAAAA==.Zeraphole:BAAALAADCggICAAAAA==.Zerie:BAAALAADCggIFQAAAA==.Zerrynthia:BAAALAADCgYIBgAAAA==.',Zo='Zoidbergmd:BAAALAAECgcIDgAAAA==.Zomat:BAAALAADCggIDQAAAA==.Zomßie:BAAALAADCgQIBAAAAA==.Zookk:BAAALAAECgYICAABLAAECgYIDgACAAAAAA==.Zorbrix:BAAALAAECgQICQAAAA==.',Zu='Zulgenam:BAAALAADCgMIBgAAAA==.Zulgeteb:BAAALAAECgIIAwAAAA==.Zuura:BAAALAAECgQICQAAAA==.',Zy='Zyrig:BAAALAAECggIEAAAAA==.',Zz='Zztank:BAAALAAECgYICwAAAA==.',['Êy']='Êynar:BAAALAADCgcIEQAAAA==.',['Ðe']='Ðelagro:BAABLAAECoEbAAMKAAgIsCPxAwAaAwAKAAgIsCPxAwAaAwAEAAEIjQkuWQAqAAAAAA==.',['ßå']='ßårzíñí:BAAALAADCggIFwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end