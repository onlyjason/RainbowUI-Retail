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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-Marksmanship','Mage-Frost','Priest-Discipline','Shaman-Elemental','Shaman-Enhancement','Paladin-Holy','DeathKnight-Unholy','Warrior-Protection','Evoker-Devastation','Warlock-Affliction','Druid-Balance',}; local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Addilyn:BAAALAAECgEIAgAAAA==.',Ae='Aethar:BAAALAADCggICAAAAA==.',Ah='Ahminous:BAAALAAECgEIAgAAAA==.Ahroo:BAAALAAECgIIAgABLAAECgcIDQABAAAAAQ==.Ahrue:BAAALAAECgcIDQAAAQ==.',Ai='Airc:BAAALAAECgEIAQAAAA==.',Ak='Ak:BAAALAADCgIIAgABLAAECggIGgACAL4mAA==.',Al='Alfster:BAAALAAECgQIBwAAAA==.',Am='Ambulancia:BAAALAAECgIIAgAAAA==.',An='Anathemã:BAAALAADCggIBwABLAAECggIGgACAL4mAA==.',Ao='Aofmerc:BAAALAADCgQIBAAAAA==.',Ar='Arkhan:BAAALAADCgUIBQAAAA==.Arynna:BAAALAAECgIIAgAAAA==.',As='Astra:BAAALAAECgYIDQAAAA==.Asunaish:BAAALAAECgYICgAAAA==.',At='Atomicrednax:BAACLAAFFIEJAAIDAAUIdCA8AAD4AQADAAUIdCA8AAD4AQAsAAQKgRYAAgMACAhzJJMDAAoDAAMACAhzJJMDAAoDAAAA.Attroc:BAAALAADCgYIBgAAAA==.',Au='Auraria:BAAALAAECgEIAQAAAA==.',Ay='Ayahuasca:BAAALAADCgcIBwAAAA==.',Az='Azarite:BAAALAAECgMIAwAAAA==.',Ba='Babadøøk:BAAALAAECgIIAgAAAA==.Bahoodies:BAAALAAECgEIAQAAAA==.Bakhåll:BAAALAADCgYIBgAAAA==.Ballsofury:BAAALAAECgYICQAAAA==.Bananaa:BAAALAAECgMIBQAAAA==.Battousaiha:BAAALAAECgEIAgAAAA==.',Be='Beezelbubba:BAAALAADCgcIBwAAAA==.Besidedeath:BAAALAADCgQIBAAAAA==.',Bl='Blav:BAAALAADCgEIAQAAAA==.Blavpriest:BAAALAADCggICAAAAA==.',Br='Breathoflife:BAAALAAECgMIAwAAAA==.Brigandier:BAAALAADCgYICgAAAA==.',Bu='Burney:BAAALAAECgYIDgAAAA==.',['Bò']='Bònesaw:BAAALAAECgcIDwAAAA==.',Ca='Calibrium:BAAALAADCgMIAwAAAA==.Carll:BAAALAAECgcIDwAAAA==.Cathartic:BAAALAAECgQIBAAAAA==.',Ch='Cholomonga:BAAALAAECgcIDQAAAA==.',Co='Colisto:BAAALAADCgQIBAAAAA==.',Cu='Cukiesncream:BAAALAADCgQIBAAAAA==.',Da='Dabria:BAAALAAECgYICwAAAA==.Danir:BAAALAAECgIIAgAAAA==.Darig:BAAALAAECgYIBgAAAA==.',De='Decimas:BAAALAADCggICAAAAA==.Decimez:BAAALAAECgEIAgAAAA==.Decimock:BAAALAAECgEIAQAAAA==.Deschainrol:BAAALAADCgcIDAAAAA==.',Di='Dipz:BAAALAADCgYICQAAAA==.Dirtymarie:BAAALAADCgIIAgAAAA==.',Dj='Djävulsk:BAAALAAECgEIAQAAAA==.',Dr='Drain:BAAALAAECgMIBQAAAA==.Drandy:BAAALAAECgcIDQAAAA==.Draon:BAAALAADCgcIBgAAAA==.Drchow:BAAALAADCggIDwAAAA==.Drinkyds:BAAALAAECgcIDAAAAA==.',Ee='Eepic:BAAALAAECgYIDwAAAA==.',El='Eldångor:BAAALAADCggICAAAAA==.Elixir:BAAALAADCgIIAgAAAA==.Elonbust:BAAALAAECgYIAwAAAA==.',En='Enhela:BAAALAAECgYICgAAAA==.',Ep='Epinephrine:BAAALAAECgYIDAAAAA==.',Er='Erynd:BAAALAAECgQIBgAAAA==.',Es='Escorpiøn:BAAALAAECgYIBwAAAA==.',Ev='Evermore:BAAALAAECgcIBQAAAA==.',Fa='Fa:BAAALAADCggIEAABLAAECgIIBAABAAAAAA==.Falkor:BAAALAAECgYICAABLAAECgYICgABAAAAAA==.Fartinhaler:BAAALAAECgcIDQABLAAFFAUICQADAHQgAA==.Farven:BAAALAAECgYIDAABLAAECggIGgACAL4mAA==.',Fe='Felagain:BAAALAAECgEIAQAAAA==.',Fi='Fib:BAAALAAECgcIDwAAAA==.Fidgety:BAAALAAECgUICAAAAA==.Firekill:BAAALAADCgcICQAAAA==.',Fl='Flankshot:BAAALAAECgcIDwAAAA==.',Fo='Foops:BAABLAAECoEWAAIEAAgI1B+JAwDaAgAEAAgI1B+JAwDaAgAAAA==.Foopsadin:BAAALAAECgcIDQABLAAECggIFgAEANQfAA==.Footloose:BAAALAAECgEIAQAAAA==.',Fu='Functions:BAAALAADCggIEAAAAA==.',Ge='Genohbreaker:BAAALAADCgcIDQABLAADCgcIDQABAAAAAA==.Getdottedkid:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.',Gi='Giing:BAACLAAFFIEJAAICAAUIaR0iAAAOAgACAAUIaR0iAAAOAgAsAAQKgRYAAgIACAhhJv0BAGkDAAIACAhhJv0BAGkDAAAA.Giingur:BAAALAAECgcIDQABLAAFFAUICQACAGkdAA==.Gimermonty:BAAALAAECgcICwAAAA==.Ginza:BAABLAAECoEWAAIFAAgI1xsjAQCfAgAFAAgI1xsjAQCfAgAAAA==.',Gl='Gladrielle:BAAALAADCgYICAAAAA==.',Go='Gorebaby:BAAALAAECgMIBAAAAA==.Gorehands:BAAALAADCgUIBQAAAA==.',Gr='Greenline:BAAALAADCgcIDQAAAA==.Gregiously:BAABLAAECoEWAAMGAAgIzRuODACFAgAGAAgIzRuODACFAgAHAAIIehHyEgBwAAAAAA==.',['Gö']='Göttligko:BAAALAADCgYIBgAAAA==.',Ha='Hakal:BAAALAAECgQICAAAAA==.Harmony:BAAALAAECgIIAgAAAA==.',He='Hench:BAAALAADCgQIAgABLAADCggIEAABAAAAAA==.',Hi='Hipz:BAAALAAECgcIDwAAAA==.',Ho='Hotnrot:BAAALAADCgcICQAAAA==.',Hu='Hukdemon:BAAALAAECgEIAQAAAA==.',Il='Illidari:BAAALAAECgEIAQAAAA==.',In='Inviteme:BAAALAAECgQIBwAAAA==.',Ja='Jakesterwars:BAAALAADCgcICwAAAA==.',Je='Jeda:BAAALAAECgIIBAAAAA==.',Jh='Jhamin:BAAALAAECgIIBAAAAA==.',Jo='Johhnnwhickk:BAAALAADCgcIDQAAAA==.Joltasaurus:BAAALAAECgIIBAAAAA==.',Ju='Julkaal:BAAALAAECgMIAwAAAA==.',Ka='Kai:BAAALAAECgIIBAAAAA==.Karney:BAAALAAECgYIDwAAAA==.Kathenoth:BAAALAADCgIIAgAAAA==.',Ke='Kelthugan:BAAALAAECgMIAwAAAA==.Kenervate:BAAALAADCgUIBQABLAAECgIIBAABAAAAAA==.',Ki='Kitty:BAAALAAECgQIBwAAAA==.',Kl='Klickyy:BAAALAAECgQIBAABLAAECggIGgACAL4mAA==.Kliiden:BAAALAAECgYICwABLAAECggIGgACAL4mAA==.Kllcky:BAABLAAECoEaAAMCAAgIviaQAgBeAwACAAgIviaQAgBeAwAIAAEIGQy1MQA4AAAAAA==.',Ko='Koilie:BAAALAADCggIDwABLAAECgYICAABAAAAAA==.Kongo:BAAALAADCgMIAwAAAA==.Kosbow:BAAALAADCgYIBgAAAA==.',Kr='Kraoptix:BAAALAADCgcICAAAAA==.Kraun:BAAALAAECgEIAQAAAA==.Kroo:BAAALAAECgYICQAAAA==.',Ku='Kurse:BAAALAAECgEIAgAAAA==.',Kv='Kvothè:BAAALAADCggIEQAAAA==.',Ky='Kyi:BAAALAAECgcIDwAAAA==.',La='Landar:BAAALAAECgcIDwAAAA==.',Li='Lightairloka:BAAALAAECgEIAQAAAA==.Lightnin:BAAALAADCgMIAwAAAA==.',Lu='Lucién:BAAALAAECgEIAQAAAA==.',['Lí']='Líght:BAAALAAECgEIAQAAAA==.',Ma='Majèsty:BAABLAAECoEWAAICAAgIthkIFABfAgACAAgIthkIFABfAgAAAA==.Maldiva:BAAALAADCggIEAAAAA==.Mangreese:BAAALAAECgYICAAAAA==.',Mc='Mccarty:BAAALAADCggICAAAAA==.Mcgonagle:BAAALAADCggICAAAAA==.Mcstícky:BAAALAAECgYICwAAAA==.',Me='Memoo:BAAALAADCgcIBwAAAA==.',Mi='Mickdagger:BAAALAADCggICAAAAA==.',Mj='Mjolnos:BAAALAADCggICAAAAA==.',Mo='Mograinez:BAACLAAFFIEJAAIJAAUI3yEEAAAJAgAJAAUI3yEEAAAJAgAsAAQKgRYAAgkACAh/JkwAAHUDAAkACAh/JkwAAHUDAAAA.Moosebreath:BAAALAAECgIIAwAAAA==.',My='Myojin:BAAALAAECgMIAwAAAA==.',Na='Namthor:BAAALAAECgYICQAAAA==.',Nu='Numzie:BAAALAADCggIEAABLAAECgYICAABAAAAAA==.Nuovis:BAAALAADCggICwAAAA==.',['Nã']='Nãrcissus:BAAALAAECgEIAQABLAAECggIGgACAL4mAA==.',Ol='Oldshotz:BAAALAAECgYICQAAAA==.',On='Onapalehorse:BAAALAADCgQIBAAAAA==.',Os='Oscurito:BAAALAAECgMIBgAAAA==.Ose:BAAALAADCgcIBwAAAA==.',Pa='Panzerkuh:BAAALAAECgYIBwABLAAECggIFgAKAJIfAA==.Panzerwolf:BAABLAAECoEWAAIKAAgIkh/hBgBVAgAKAAgIkh/hBgBVAgAAAA==.',Pe='Pepperpots:BAAALAAECgIIBAAAAA==.',Pi='Pins:BAAALAADCgcIBwABLAAECgYICAABAAAAAA==.Pippz:BAAALAAECgIIAwAAAA==.Pizza:BAAALAADCgcIAQAAAA==.',Pr='Prugaru:BAAALAADCgcIBwAAAA==.',Pu='Punkface:BAAALAAECgEIAQAAAA==.Punkin:BAAALAADCgcICAAAAA==.Purr:BAAALAAECgIIAwAAAA==.',Qw='Qweh:BAAALAAECgcIDQAAAA==.',Ra='Rakkasei:BAAALAAECgYICQAAAA==.Razkal:BAAALAAECgcIBwAAAA==.',Re='Rellik:BAAALAAECgYICQAAAA==.',Ri='Rizzu:BAAALAAECgYIBgABLAAECgcIBwABAAAAAA==.',Rk='Rk:BAAALAADCgcIEQAAAA==.',Rn='Rngesus:BAAALAAECgYICAAAAA==.',Ro='Rockwell:BAAALAADCggICAAAAA==.',Ru='Rubysapphire:BAAALAADCgcIBwAAAA==.Ruffle:BAAALAADCgMIAwAAAA==.Rushem:BAAALAAECgEIAgAAAA==.',Ry='Ryft:BAAALAAECgMIAwAAAA==.',Sa='Sacha:BAAALAAECgcIDAAAAA==.Sansforme:BAAALAAECgQIBwAAAA==.',Se='Seita:BAAALAAECgYICAAAAA==.Seseria:BAAALAAECgcIDwAAAA==.Seshin:BAAALAADCgEIAQAAAA==.',Sh='Shadari:BAAALAADCgQIBAAAAA==.Shanic:BAAALAAECgEIAgAAAA==.Sharpshõt:BAAALAADCgYIBgAAAA==.Shiftor:BAAALAADCgQIBAAAAA==.Shiftylogic:BAAALAAECgcIDQAAAA==.Shocky:BAAALAADCggICAAAAA==.Shockzz:BAAALAAECgMIAwAAAA==.Shydow:BAAALAADCgcIBwABLAADCggIEAABAAAAAA==.',Si='Siena:BAAALAAECgYIDwAAAA==.',Sl='Slavka:BAAALAAFFAIIAgAAAA==.',Sm='Smitervane:BAAALAADCgcICQAAAA==.',Sn='Snipyvoker:BAABLAAECoEWAAILAAgIGiCyBgDHAgALAAgIGiCyBgDHAgAAAA==.Snocone:BAAALAADCgcIBwAAAA==.Snoodly:BAAALAAECgEIAgAAAA==.Snott:BAAALAAECgIIAwAAAA==.',So='Solahk:BAAALAADCgcICQAAAA==.Solarice:BAAALAAECgMIAwAAAA==.Solunais:BAAALAAECgYICAAAAA==.',Sp='Spirallidan:BAAALAAECgcIDwAAAA==.',St='Stayk:BAAALAADCgcIDAAAAA==.Stepbro:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.Stinksauce:BAAALAAFFAIIAgAAAA==.Strokntotem:BAAALAADCgYIBgAAAA==.',Su='Sunlit:BAAALAADCggIDwAAAA==.Supermann:BAAALAAECgEIAQAAAA==.Sutra:BAAALAAECgMIAwAAAA==.',Sy='Sylmarillion:BAAALAADCgYIBgAAAA==.Syx:BAAALAADCggICAAAAA==.',Ta='Tankytauren:BAAALAADCgcIDgAAAA==.Tasahof:BAABLAAECoEUAAIMAAcIZCDhAQCpAgAMAAcIZCDhAQCpAgAAAA==.Taynte:BAAALAAECgEIAQAAAA==.',Th='Thorrin:BAAALAAECgMIBAAAAA==.Thumb:BAAALAADCgEIAQAAAA==.',Ti='Timeout:BAAALAADCggICAABLAAECgcIFAAMAGQgAA==.',To='Tone:BAAALAAECgcIEAAAAA==.Totëm:BAAALAADCggICAABLAAECgcIFAAMAGQgAA==.Tough:BAAALAADCgcIBwAAAA==.',Ts='Tsayid:BAAALAAECgEIAQAAAA==.',Tv='Tvåtår:BAAALAAECgYICwAAAA==.',Ty='Typhoon:BAAALAADCggICAABLAAECgcIFAAMAGQgAA==.Tyrith:BAAALAAECgUIBgAAAA==.',Ug='Ugotgot:BAAALAADCgQIBAAAAA==.',Ul='Ulazain:BAAALAAECgYICgAAAA==.Ultrafresh:BAAALAADCgcIBwAAAA==.',Um='Umbriel:BAAALAADCgMIAgAAAA==.',Un='Unease:BAAALAAECgYIDAAAAA==.Unwell:BAAALAAECgMIAwABLAAECgMIBQABAAAAAA==.',Va='Vaas:BAAALAADCggICAAAAA==.',Vi='Viì:BAAALAAECgIIAgAAAA==.',Vo='Voidmister:BAAALAAECgMIAwAAAA==.',Wa='Wafflegarden:BAAALAADCggIFgAAAA==.Waronyou:BAAALAAECgEIAQAAAA==.Watergun:BAAALAAECgYICQAAAA==.',We='Weedie:BAAALAAECgMIBQAAAA==.',Wi='Wildcard:BAAALAADCgYIDAAAAA==.',Xe='Xenoknight:BAAALAAECgMIAwAAAA==.',Ym='Ymerehian:BAAALAADCgcIBwAAAA==.',Yo='Youllprobdie:BAAALAADCggIDwAAAA==.',Yu='Yumekö:BAAALAADCggIFQAAAA==.Yurgir:BAAALAAECgYICgAAAA==.',Zo='Zolzemex:BAAALAADCgEIAQAAAA==.',Zu='Zugmaster:BAAALAAECggICAAAAA==.',Zz='Zzephyrdruid:BAACLAAFFIEIAAINAAQIxxuKAACDAQANAAQIxxuKAACDAQAsAAQKgRYAAg0ACAhyJT4DAC0DAA0ACAhyJT4DAC0DAAAA.Zzephyrmage:BAAALAAECgcIDQABLAAFFAQICAANAMcbAA==.',['Ôä']='Ôäk:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end