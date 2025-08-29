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
 local lookup = {'Mage-Arcane','Unknown-Unknown','Warrior-Fury','Evoker-Devastation','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration',}; local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aeidail:BAABLAAECoEVAAIBAAgIHhvVDgCtAgABAAgIHhvVDgCtAgAAAA==.Aelmian:BAAALAADCgcIEwABLAAECgQIBQACAAAAAA==.',Af='Afkautoshot:BAAALAADCgcIBwAAAA==.',Ag='Agraceful:BAAALAAECgQIBwAAAA==.',Ai='Aios:BAAALAADCgcIDwAAAA==.',Al='Alassian:BAAALAADCgEIAQAAAA==.',An='Anklesmasher:BAAALAAECgMIAwAAAA==.Anschale:BAAALAADCgcIBwAAAA==.Antisocial:BAAALAAECgUIBQAAAA==.',Ar='Ardrith:BAAALAAECgYICgABLAAFFAUIDAADAC0XAA==.Ardrithmage:BAAALAAECgcIEAABLAAFFAUIDAADAC0XAA==.Ardrithwar:BAACLAAFFIEMAAIDAAUILReRAADfAQADAAUILReRAADfAQAsAAQKgRYAAgMACAj9IiAFAB0DAAMACAj9IiAFAB0DAAAA.Arfaz:BAAALAADCggICAABLAAECgMIBQACAAAAAA==.Arsinoë:BAAALAADCgQIBQAAAA==.Arucane:BAAALAAECgQIBQABLAAECggIFQABAB4bAA==.Arçano:BAAALAADCgcIBgAAAA==.',As='Ashom:BAAALAADCgcIDgAAAA==.',At='Atma:BAAALAAECgEIAQAAAA==.',Ba='Baerd:BAAALAAECgMIBAAAAA==.Bandek:BAAALAADCgcIEgAAAA==.Barlz:BAAALAAECgEIAQAAAA==.',Be='Bean:BAAALAADCgYIBgAAAA==.Bebby:BAAALAADCgcIEAAAAA==.Betrayer:BAAALAADCggIDAABLAAECgYIDgACAAAAAA==.Bevot:BAAALAAECgYIBgAAAA==.',Bi='Bighero:BAAALAADCgIIAgAAAA==.',Bl='Bludo:BAABLAAECoEVAAIDAAgIIhtjDwBrAgADAAgIIhtjDwBrAgAAAA==.',Bo='Bombacløt:BAAALAAECgMIBAAAAA==.',Br='Brastin:BAAALAAECgYICAAAAA==.Brenell:BAAALAAECgYIBgAAAA==.Brovaris:BAAALAADCgUIBQAAAA==.',Ca='Catassin:BAAALAADCgcIBwAAAA==.',Ch='Chriswin:BAAALAADCgUICgAAAA==.',Co='Coldncrispy:BAAALAADCggIDwAAAA==.Corious:BAAALAADCggICQAAAA==.',Cu='Cuecumba:BAAALAAECgMIBAAAAA==.',Cy='Cynderen:BAAALAADCgcIDgAAAA==.Cynthex:BAAALAADCggICAAAAA==.',Da='Daddyfatsak:BAAALAADCgQIBAABLAAECgMIAwACAAAAAA==.Dalran:BAAALAADCgcICwAAAA==.Dalren:BAABLAAECoEWAAIEAAgIoiALBwC9AgAEAAgIoiALBwC9AgAAAA==.Dartagnan:BAAALAAECgYICQAAAA==.Darthmaul:BAAALAAECgYICwAAAA==.',De='Demetrian:BAAALAAECgIIAwAAAA==.Desmidus:BAAALAAECgEIAQAAAA==.Devastation:BAAALAADCgIIAgABLAAECgYIDQACAAAAAA==.',Di='Diem:BAAALAAECgMIAwAAAA==.Disable:BAAALAAECgIIAgABLAAECgYICwACAAAAAA==.',Do='Docbane:BAAALAADCgcIBwAAAA==.Docholiday:BAAALAADCgMIAwABLAAECgMIAwACAAAAAA==.Docvader:BAAALAADCgUIBQABLAADCgcIBwACAAAAAA==.Doranar:BAAALAAECgQIBAAAAA==.Dowedoes:BAAALAAECgYICwAAAA==.',Dr='Dragonx:BAAALAAECggICAAAAA==.Dreolan:BAAALAAECgQIBQAAAA==.Driftér:BAAALAADCgMIAwAAAA==.',Dy='Dyala:BAAALAAECgYIBwAAAA==.',Dz='Dzl:BAEALAAECgYIDgAAAA==.',El='Eloise:BAAALAADCggIDgAAAA==.Elvenbane:BAAALAAECgYIDAAAAA==.',En='Enable:BAAALAAECgYICwAAAA==.',Eu='Eunliza:BAAALAADCgYICgAAAA==.',Fa='Faltree:BAAALAAECgYICgAAAA==.',Fc='Fcksean:BAAALAAECggIBgAAAA==.',Fe='Fergus:BAAALAAECgMIAwAAAA==.',Fl='Flayx:BAAALAAECgYICgAAAA==.',Fo='Foulcor:BAAALAAECgMIBAAAAA==.',Fr='Freakadeek:BAAALAAECgMIAwAAAA==.Frink:BAAALAADCgYIBgABLAAECgYICwACAAAAAA==.',Fu='Fundetected:BAAALAADCggIEAABLAADCggIFAACAAAAAA==.Furiosa:BAAALAAECgMIBAAAAA==.',['Fá']='Fállenmonkey:BAABLAAECoEUAAIFAAgIRxqoDgBYAgAFAAgIRxqoDgBYAgAAAA==.',Ga='Galadorn:BAAALAAECgMIDAAAAA==.',Ge='Gerdash:BAAALAAECgYICgAAAA==.Gerred:BAAALAAECgIIAwAAAA==.',Go='Goldenflame:BAAALAAECgYIBgAAAA==.Goldenlily:BAAALAAECgcIDwAAAA==.Goldenmunc:BAAALAAECgEIAQAAAA==.Goldenpants:BAAALAAECgEIAgAAAA==.Goldtoes:BAAALAAECgYICgAAAA==.',Gr='Grievous:BAAALAAECgYICwAAAA==.',Ha='Hailmary:BAAALAAECgYICQAAAA==.Harbinger:BAAALAAECgYIDgAAAA==.',He='Healaga:BAAALAAECgMIBQAAAA==.Hesthy:BAAALAADCgEIAQAAAA==.',Hh='Hhoonnzz:BAAALAAECgEIAQAAAA==.',Ho='Hornreaper:BAAALAAECgYICQAAAA==.',Hu='Hubbabubbajr:BAAALAADCgcIDgAAAA==.Huntai:BAAALAAECgMIAwAAAA==.',In='Infamouss:BAAALAADCgcIBwAAAA==.Interco:BAAALAADCgEIAQABLAAECgMIBAACAAAAAA==.',Ja='Jayonor:BAAALAAECgYICwAAAA==.',Je='Jek:BAAALAAECgMIBQAAAA==.',Ka='Kaeliana:BAAALAAECgUIDAAAAA==.Kagalkaya:BAAALAADCgMIAwAAAA==.',Ke='Keeper:BAAALAAECgMIBQAAAA==.Keeperodark:BAAALAADCggIEAABLAAECgMIBQACAAAAAA==.Keeperolight:BAAALAAECgIIAgABLAAECgMIBQACAAAAAA==.Kemanorel:BAAALAADCgIIAwABLAAECgYIDAACAAAAAA==.',Kh='Khaewen:BAAALAADCgcIDQABLAAECgUIDAACAAAAAA==.',Ki='Kifo:BAAALAADCgQIBAAAAA==.Killkat:BAAALAAECgMIBAAAAA==.Kilygos:BAAALAAECgQIBAAAAA==.',Ko='Kodera:BAAALAAECgEIAQAAAA==.Koojo:BAAALAADCgcICQAAAA==.Koore:BAAALAAECgUICAAAAA==.',Kr='Kraejrenosh:BAAALAADCgcIBwAAAA==.',Ku='Kurova:BAAALAADCgIIAgAAAA==.',La='Lad:BAAALAADCggICAAAAA==.Larew:BAAALAADCgYIBgAAAA==.',Lb='Lbwillkillme:BAAALAADCggICAAAAA==.',Le='Lealla:BAAALAAECgYICwAAAA==.Lechevalier:BAAALAADCggIFAAAAA==.Letholas:BAABLAAECoEUAAMGAAgIOBsKHwAMAgAGAAcIyxcKHwAMAgAHAAMIjRq0HAD6AAAAAA==.Letholäs:BAAALAADCggICAABLAAECggIFAAGADgbAA==.',Li='Lizardgang:BAAALAADCgcIDQAAAA==.',Lo='Loganshu:BAAALAAECgMIAwAAAA==.Lokan:BAAALAAECgYICgAAAA==.Lots:BAAALAAECgYIDgAAAA==.',Ly='Lyna:BAAALAAECgEIAQAAAA==.Lynaya:BAAALAAECgUIBgAAAA==.Lynndrys:BAAALAADCgYIBgAAAA==.',['Lî']='Lîghtless:BAAALAAECgcIEAAAAA==.',['Lú']='Lúckÿ:BAAALAADCgEIAQAAAA==.',Ma='Macarth:BAAALAAECgIIAgAAAA==.Makbatre:BAAALAAECgMIAwAAAA==.Malhavoc:BAAALAADCgIIAgAAAA==.Marrti:BAAALAAECgEIAQAAAA==.Matíx:BAAALAADCgcIBwAAAA==.',Mc='Mcbain:BAAALAAECgYICwAAAA==.',Me='Meatshíeld:BAAALAADCgcICAAAAA==.Melrine:BAAALAAECgMIAwAAAA==.Mesquito:BAAALAAECgMIBAAAAA==.',Mi='Minerwor:BAAALAADCgcIEgAAAA==.Minkaybo:BAAALAADCgUIBQAAAA==.',Mj='Mjolni:BAAALAADCgQIBAAAAA==.',Mm='Mmisty:BAAALAAECgMIBgAAAA==.',Mo='Monsterbee:BAAALAAECgMIBQAAAA==.',Mu='Mustypizza:BAAALAAECgMIBAAAAA==.',My='Mystery:BAAALAAECgYICwAAAA==.',Na='Nats:BAAALAAECgIIAgAAAA==.',Ne='Nekid:BAAALAADCgUIAgAAAA==.Nerdzhul:BAAALAADCgEIAQAAAA==.Neth:BAAALAAECgQIBQAAAA==.',Ni='Ninesham:BAAALAAECgEIAQAAAA==.',No='Noctum:BAAALAADCgcIDQAAAA==.Noxryl:BAAALAAECgIIAgAAAA==.',Nu='Nubrac:BAAALAADCggIEQAAAA==.',Ol='Olam:BAAALAADCgcIBwAAAA==.',Oo='Oomsca:BAAALAAECgIIAgAAAA==.',Op='Oppik:BAAALAAECgYIDAAAAA==.',Pa='Pandas:BAAALAADCgYIBgAAAA==.Pappajustify:BAAALAADCggICAAAAA==.',Pi='Pixae:BAAALAAECgYIBwAAAA==.Pixiechaos:BAAALAADCgcIEAAAAA==.',Pl='Pliable:BAAALAADCgYIBgAAAA==.',Po='Poliahu:BAAALAAECgMIAwAAAA==.Polkadottz:BAAALAADCgYICwAAAA==.Portass:BAAALAAECgEIAQAAAA==.Powerplant:BAAALAAECgcIEAAAAA==.Powerwordkek:BAAALAAECgIIAgAAAA==.',Pu='Puffington:BAAALAAECgQIBAAAAA==.Punchapuppy:BAAALAAECgEIAQAAAA==.Puremagic:BAAALAADCgMIAwAAAA==.',['Pâ']='Pârtyrocker:BAAALAAECgEIAQABLAAECgMIAwACAAAAAA==.',Ra='Ragetality:BAAALAAECggIBgAAAA==.Rahken:BAAALAAECgIIAgAAAA==.Ramaria:BAAALAADCgYIBgABLAAECgMIDAACAAAAAA==.Rath:BAAALAADCgIIAgAAAA==.',Re='Regicee:BAAALAAECgMIAwAAAA==.Retam:BAAALAADCgcIBwAAAA==.',Rh='Rhysandra:BAAALAADCgcIBwAAAA==.',Ri='Riesig:BAAALAADCgcIBwAAAA==.',Ro='Rogin:BAAALAADCgcIBwAAAA==.Rottenbean:BAAALAAECgYIDwAAAA==.',Ru='Rukkuz:BAAALAADCgYIBgAAAA==.Rundvelt:BAAALAAECgMIBAAAAA==.',Sa='Sabrinie:BAAALAADCggICAAAAA==.Salohtel:BAAALAAECgEIAQABLAAECggIFAAGADgbAA==.',Se='Serbsham:BAAALAAECgcIDgAAAA==.Serdragon:BAAALAAECgMIBAAAAA==.',Sh='Shtanky:BAAALAAECgYICgAAAA==.',Si='Sicarrii:BAAALAAECgYICQAAAA==.',Sl='Slygirl:BAAALAADCgcICgAAAA==.',So='Sofakingséxy:BAAALAADCgcIDgABLAADCggIFAACAAAAAA==.',St='Stefancorbin:BAAALAAECgQIBAAAAA==.Stormkeeper:BAAALAADCggICAABLAAECgMIBQACAAAAAA==.Styx:BAAALAADCgQIBQAAAA==.',Su='Sumetaru:BAAALAAECgMIBAAAAA==.Sunbake:BAAALAADCgcIEAAAAA==.Supremebean:BAAALAADCgIIAgAAAA==.',Sw='Sweetbbyraze:BAAALAAFFAEIAQAAAA==.Swiftzz:BAAALAAECgEIAQAAAA==.',Ta='Talipally:BAAALAAECgEIAgAAAA==.Talishammy:BAAALAADCgIIAgAAAA==.Tanisong:BAAALAADCgcICgAAAA==.Tankliden:BAAALAAECgMIAwAAAA==.',Te='Terrorism:BAAALAADCggIDQAAAA==.',Th='Thedojo:BAAALAADCggICAAAAA==.Thekingpunch:BAAALAADCgQIBQAAAA==.',Ti='Tillwar:BAAALAAECgYICwAAAA==.',To='Tobias:BAAALAAECgMIAwAAAA==.',Tr='Treibh:BAAALAAECgQIBAAAAA==.',Tu='Tubbsmcgee:BAABLAAECoEVAAIIAAgIQB0FCgBzAgAIAAgIQB0FCgBzAgAAAA==.',Tw='Twinstar:BAAALAADCgcIBwAAAA==.Twizzler:BAAALAAECgYICwAAAA==.',Ty='Tymora:BAAALAADCgcICgABLAAECgYIDAACAAAAAA==.',['Të']='Tërris:BAAALAADCgEIAQAAAA==.',Ul='Ulose:BAAALAAECgYIEwAAAA==.Ultrademon:BAAALAAECgYICAAAAA==.',Ur='Urownmother:BAAALAAECgMIAwAAAA==.',Va='Vallez:BAEALAAECgYICgAAAA==.',Ve='Velladoree:BAAALAADCgcIEAAAAA==.Veried:BAAALAADCggIDgABLAAECgQIBQACAAAAAA==.Vexira:BAAALAAECgMIBAAAAA==.',Vy='Vynlorlan:BAAALAAECgYICAAAAA==.',Wi='Wigglës:BAAALAADCgIIAgAAAA==.',Xe='Xerai:BAAALAAECgMIAwAAAA==.',Xh='Xhexana:BAAALAAECgMIAwAAAA==.',Xr='Xrayl:BAAALAAECgYIDQAAAA==.',Xz='Xzerocool:BAAALAAECgEIAQABLAAECgMIAwACAAAAAA==.',Yo='Yoshikazu:BAAALAADCgcIEAAAAA==.',Za='Zalanor:BAAALAADCggIEAAAAA==.',Zh='Zhiva:BAAALAAECgEIAQAAAA==.',Zi='Zial:BAAALAAECgIIAwAAAA==.',Zo='Zombeezle:BAAALAADCggIEAAAAA==.',Zy='Zykoz:BAAALAAECgEIAgAAAA==.',['Ÿo']='Ÿoshi:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end