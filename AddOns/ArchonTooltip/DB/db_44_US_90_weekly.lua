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
 local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Monk-Windwalker','Paladin-Holy','Warrior-Protection','Hunter-BeastMastery','DeathKnight-Blood',}; local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abacus:BAAALAADCggICAAAAA==.',Ad='Adam:BAACLAAFFIEGAAMBAAMIvBtwAgC5AAABAAIIpx5wAgC5AAACAAII1hpfBgC5AAAsAAQKgRgABAIACAhNJSgCAEwDAAIACAi1JCgCAEwDAAMABAhHFOoPADQBAAEABAhaJLofABoBAAAA.Adomie:BAAALAAECgIIAgAAAA==.Adragon:BAAALAAECgMIAwAAAA==.',Al='Alatia:BAAALAADCggIEgAAAA==.Allsmiles:BAAALAAECgQIBAAAAA==.Allura:BAAALAADCgYIBwAAAA==.Alttharius:BAEALAADCggICAABLAAECgYIDAAEAAAAAA==.Alyysha:BAAALAAECgUICgAAAA==.',Am='Amoon:BAAALAAECgIIAgAAAA==.',Ar='Archymedes:BAAALAAECgMIAwAAAA==.Arckady:BAAALAADCgYIBwAAAA==.Artharius:BAEALAAECgYIDAAAAA==.',As='Astrální:BAAALAADCgYICAAAAA==.',At='Atlas:BAAALAAECgMIAwAAAA==.',Az='Aztharot:BAAALAADCgUIBQAAAA==.Azula:BAAALAAECgIIAgAAAA==.',Ba='Badchoices:BAAALAADCgUIBQAAAA==.Badkittie:BAAALAADCgMIAwAAAA==.Balraun:BAAALAADCgcIBwAAAA==.',Be='Beefsnake:BAAALAAECgcIEAAAAA==.Beefytips:BAAALAADCgYIBgAAAA==.Berserko:BAAALAADCgEIAQAAAA==.',Bi='Bigunsforu:BAAALAADCggIDQAAAA==.',Bl='Bladesmcgee:BAAALAAECgYICQAAAA==.Blóódlust:BAAALAADCgYIBgAAAA==.',Bo='Bofahdeez:BAAALAAECgYICQAAAA==.',Br='Brawlr:BAAALAADCgMIAwAAAA==.Brenarion:BAAALAADCgMIAwAAAA==.Brendoh:BAAALAADCgMIAwAAAA==.Brolic:BAAALAAECgMIAwAAAA==.',Bu='Burritojinjr:BAAALAADCggICAAAAA==.',Ca='Cagen:BAAALAAECgMIAwAAAA==.Cail:BAAALAADCgYICAAAAA==.Calisa:BAAALAAECgIIAwAAAA==.Calmwaters:BAAALAADCgcICgAAAA==.Capncaveman:BAAALAADCgQIBAAAAA==.',Ch='Chigutotems:BAAALAAECgQIBAAAAA==.Chozen:BAAALAAECgEIAQAAAA==.',Ck='Ckntndrsub:BAAALAAECgMIBAAAAA==.',Co='Coffee:BAAALAADCgcIBwAAAA==.Colinferral:BAAALAAECgMIAwAAAA==.',Cr='Cronicpain:BAAALAAECggICAAAAA==.',Cu='Cursedwaters:BAAALAADCgcICAAAAA==.',['Câ']='Cânt:BAAALAAECggIEQAAAA==.',Da='Daks:BAAALAAECgcICwAAAA==.Darklucrezia:BAAALAAECgcICAAAAA==.',De='Deetsy:BAAALAAECgMIAwAAAA==.Deffy:BAAALAAECgIIAwAAAA==.',Di='Discount:BAAALAADCgcIBwAAAA==.Dispelldaddy:BAAALAADCggIFAABLAAECgYICQAEAAAAAA==.Dizzed:BAAALAADCgUIBQABLAADCgYICAAEAAAAAA==.',Do='Docholiday:BAAALAAECggIEAAAAA==.',Dr='Dracarius:BAAALAADCgQIBgAAAA==.Dragondex:BAAALAADCgYICAAAAA==.Drargun:BAAALAADCggICAAAAA==.Drezdan:BAAALAAECgcIDQAAAA==.Dryad:BAAALAADCgYIBwAAAA==.',Du='Durkk:BAAALAAECgIIAwAAAA==.',El='Elanthae:BAAALAADCgMIBQAAAA==.',Es='Estara:BAAALAAECgIIAwAAAA==.',Et='Etali:BAAALAAECgIIAwAAAA==.',Eu='Eudora:BAAALAAECgEIAQAAAA==.',Ev='Evanel:BAAALAADCgcIBgAAAA==.',Fa='Fanis:BAAALAAECgIIAgAAAA==.Faynor:BAAALAADCgcIBwAAAA==.',Fl='Florago:BAAALAADCgYIBAAAAA==.',Fo='Forgiven:BAABLAAECoEWAAIFAAgIAiZ0AAB1AwAFAAgIAiZ0AAB1AwAAAA==.',Fr='Frakir:BAAALAAECgIIAwAAAA==.Francis:BAAALAADCgcIDQAAAA==.Fritz:BAAALAAECgYICQAAAA==.',Fu='Fujinn:BAAALAADCgcIBwAAAA==.',Fw='Fwapp:BAABLAAECoEXAAIGAAgIsCLsAAAlAwAGAAgIsCLsAAAlAwAAAA==.',Ga='Galvanize:BAAALAADCgcIBwAAAA==.Gatsby:BAAALAAECgQIBwAAAA==.',Gi='Gijaick:BAAALAADCggIEwAAAA==.',Go='Goldhawk:BAAALAADCgQIBAAAAA==.Gotrik:BAAALAADCgUIBQABLAAECgMIAwAEAAAAAA==.Gotwiped:BAAALAAECgUIBgAAAA==.',Ha='Hantaz:BAAALAAECgcIDwAAAA==.Hanzi:BAAALAADCgMIAwAAAA==.Hatemagic:BAAALAADCgEIAQAAAA==.',He='Helexis:BAAALAADCgMIAwAAAA==.',Hi='Hi:BAAALAADCgcICwABLAAECgQIBwAEAAAAAA==.Hills:BAAALAAECgUIBAAAAA==.',Ho='Holydarkness:BAAALAADCggICgAAAA==.',['Hø']='Hølly:BAAALAADCgUIBwAAAA==.',Ig='Igram:BAAALAAECgUICgAAAA==.',Il='Illidamngirl:BAAALAAECgYIDgAAAA==.',Im='Imperius:BAAALAAECgcIDQAAAA==.',In='Ines:BAAALAAECgcIDwAAAA==.Insomiax:BAAALAAECgIIAgAAAA==.Inuyashä:BAAALAADCgcIDAABLAAECgQIBwAEAAAAAA==.',Iv='Ivork:BAAALAADCggICAAAAA==.',Ja='Jankadish:BAAALAAECgUIBgAAAA==.Jarre:BAAALAAECgYIBgAAAA==.Jarrin:BAAALAADCgMIBQAAAA==.',Jb='Jbaconcheese:BAAALAADCgEIAQAAAA==.',Ji='Jinsei:BAAALAADCggICAAAAA==.',Ju='Juicy:BAAALAAECgYICgAAAA==.Juicyblossom:BAAALAAECgEIAQABLAAECgYICgAEAAAAAA==.Junkmonk:BAAALAAECgcIEAAAAA==.',Ka='Kalia:BAAALAAECgYICQABLAABCgMIAwAEAAAAAA==.',Ke='Keratin:BAAALAAECgEIAQAAAA==.',Ki='Kiinran:BAAALAADCgcIBwAAAA==.Kil:BAAALAADCggIFQAAAA==.Kinan:BAAALAAECgIIAwAAAA==.Kita:BAAALAAECgEIAQAAAA==.',Kr='Kreloenis:BAAALAADCgYIBAAAAA==.Kritneyfears:BAAALAADCggIEAAAAA==.',Ky='Kynra:BAAALAAECgIIAwAAAA==.Kyonko:BAAALAAECgIIAwAAAA==.',La='Lachrymarum:BAAALAADCgcICgAAAA==.Lanssolo:BAAALAAECgMIAwAAAA==.',Li='Livid:BAAALAADCgcIDwAAAA==.',Lo='Lomponic:BAAALAAECgYIDgAAAA==.Lonelyone:BAAALAADCggIDQAAAA==.Loomadin:BAAALAADCgcIDQAAAA==.',Ma='Machikori:BAAALAADCgYIBgAAAA==.Maera:BAAALAADCgYIBgAAAA==.Manawar:BAABLAAECoEXAAIHAAgICxaJCgD7AQAHAAgICxaJCgD7AQAAAA==.',Mc='Mcribz:BAAALAAECgYIDAABLAAECggIFgAIACUfAA==.',Mi='Mikoto:BAAALAADCgcIBwAAAA==.Miorine:BAAALAADCggICAAAAA==.Mistqt:BAACLAAFFIEIAAIJAAMICRsCAQAKAQAJAAMICRsCAQAKAQAsAAQKgRgAAgkACAiOI6gBACQDAAkACAiOI6gBACQDAAAA.Mitra:BAAALAAECgMIBQAAAA==.',Mo='Monktup:BAAALAADCgMIAwABLAADCgYICAAEAAAAAA==.Monnehbaggs:BAAALAAECgYIDQAAAA==.Mooinator:BAAALAADCgIIAgAAAA==.Mortalidad:BAAALAAECgEIAQAAAA==.',My='Myraghor:BAAALAAECgYICQAAAA==.',Nb='Nbs:BAAALAAECgEIAQAAAA==.',Ne='Nebody:BAAALAADCggIEAAAAA==.Necriss:BAAALAAECgEIAQAAAA==.',Ni='Nike:BAAALAAECggICAAAAA==.Nixvulpe:BAAALAADCgcIBwAAAA==.',No='Noshards:BAAALAAECgMIBQAAAA==.',Pa='Papachance:BAAALAADCggICwAAAA==.Papafrank:BAAALAADCgYIBgAAAA==.Papapump:BAAALAAECgYIDAAAAA==.Payload:BAAALAADCggIEAAAAA==.',Pe='Peach:BAAALAAECgQIBAAAAA==.',Ph='Phuzzi:BAAALAADCgcIBQAAAA==.',Pi='Pinga:BAAALAAECgMIBQAAAA==.',Po='Potatojuice:BAAALAAECgEIAQABLAAECggIEAAEAAAAAA==.Potroastjr:BAAALAADCggICAAAAA==.',Pr='Praying:BAAALAADCgUIBQAAAA==.Preposition:BAAALAAECgIIAgAAAA==.Proctology:BAAALAAECgEIAQAAAA==.',Py='Pyrinis:BAAALAADCgMIAwABLAAECgQICQAEAAAAAA==.Pyroblaster:BAAALAAECgcICgAAAA==.Pythonissa:BAAALAADCggICAAAAA==.',Qu='Quarrel:BAAALAADCgUIBQAAAA==.',Ra='Raenon:BAAALAADCgcIBwAAAA==.Raggnar:BAAALAAECgYIBwAAAA==.Ragingwaters:BAAALAADCgUIBQAAAA==.Rakin:BAAALAAECgQICQAAAA==.Raun:BAAALAAECgIIAwAAAA==.',Re='Relaire:BAAALAAECgEIAQAAAA==.',Ri='Riku:BAAALAAECgIIAwAAAA==.',Ro='Ronse:BAAALAAECggICgAAAA==.Roots:BAAALAADCgcICgAAAA==.',Ry='Ryveri:BAAALAAECgYICQAAAA==.',Sh='Shiggs:BAAALAADCgcIBwAAAA==.Shortsighted:BAABLAAECoEWAAIIAAgIJR/yBwDiAgAIAAgIJR/yBwDiAgAAAA==.Shui:BAAALAADCggIDQAAAA==.',Si='Silverwolf:BAAALAAECgQICAAAAA==.Simplyunlock:BAAALAAECgQIBwAAAA==.Simplyvoid:BAAALAADCgcIBwABLAAECgQIBwAEAAAAAA==.Sinon:BAAALAAECgYIDQAAAA==.Sizzlechop:BAAALAAECgQIBwAAAA==.',So='Soheii:BAAALAADCgYIBgAAAA==.Songs:BAAALAAECgQIBwAAAA==.Sorbak:BAAALAAECgYIBwAAAA==.Sosuke:BAAALAADCgUIBQAAAA==.',Sp='Spicysausage:BAAALAADCggICAAAAA==.',St='Stalath:BAAALAADCgUIBgAAAA==.Stormwing:BAAALAADCggIDgAAAA==.Strecagosa:BAAALAAECgIIAwAAAA==.',Su='Sumarr:BAAALAADCgUIBQAAAA==.',Sv='Svenn:BAAALAAECgQIBAAAAA==.',Sw='Swiftstrike:BAAALAADCgQIBAAAAA==.',['Së']='Sëvatar:BAAALAAECggIBwAAAA==.',Ta='Talron:BAAALAADCgMIAgAAAA==.',Te='Tea:BAAALAAECgMIAwAAAA==.Tenebrarum:BAAALAAECgMIAwAAAA==.',Th='Thehalesta:BAAALAADCgcIDQAAAA==.Therag:BAAALAAECgMIAwAAAA==.',Ti='Timb:BAAALAAECgIIAgAAAA==.Tirna:BAAALAAECgIIAwAAAA==.',Tu='Tullen:BAEALAAECgIIAwAAAA==.Turanos:BAAALAADCgYIBwAAAA==.',Ul='Ultrachad:BAAALAADCggICAAAAA==.',Un='Unggoy:BAACLAAFFIEFAAIIAAMIZR5UAQAjAQAIAAMIZR5UAQAjAQAsAAQKgRgAAggACAh7JHMCAEoDAAgACAh7JHMCAEoDAAAA.',Ur='Urianna:BAAALAADCggIEgAAAA==.',Va='Vahidamus:BAAALAADCggIEAAAAA==.Vaurix:BAAALAADCggICwAAAA==.',Ve='Vedacia:BAAALAAECgIIAgAAAA==.Vegetation:BAAALAAECgQIBgAAAA==.Venatrix:BAAALAADCgYICgAAAA==.',['Vë']='Vëx:BAAALAADCgcIBwABLAADCggIEAAEAAAAAA==.',Wa='Wafuzz:BAAALAAECgIIAgAAAA==.Warpig:BAAALAAECgIIAgAAAA==.Waters:BAAALAADCgEIAQAAAA==.Watersafari:BAAALAADCgEIAQAAAA==.',Wi='Wildeyed:BAAALAADCgUIBQABLAAECgMIAwAEAAAAAA==.Winds:BAAALAADCgIIAgABLAAECgQIBwAEAAAAAA==.',Wo='Wombaa:BAAALAAECgcIEQABLAADCgMIAwAEAAAAAA==.',Xy='Xyr:BAAALAAECgYICQAAAA==.',Ya='Yawelcome:BAAALAAECgIIAgAAAA==.',Za='Zandalia:BAAALAADCgYIDAAAAA==.',Zo='Zolton:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end