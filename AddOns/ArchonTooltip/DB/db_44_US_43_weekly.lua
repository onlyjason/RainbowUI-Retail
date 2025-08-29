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
 local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Priest-Shadow','Mage-Fire','Mage-Arcane',}; local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adrastea:BAAALAAECgYICQAAAA==.',Ai='Aiellee:BAAALAADCggIDAAAAA==.',Ak='Ak:BAAALAAECgQIBgAAAA==.Akantha:BAAALAADCggIEgAAAA==.',Al='Alcomyst:BAAALAAECgEIAQAAAA==.',Am='Amare:BAAALAAECgEIAQAAAA==.America:BAAALAAECggICAAAAA==.',Ar='Arroyo:BAAALAAECgUICAAAAA==.',As='Askadar:BAAALAAECgMIAwAAAA==.',Az='Azazél:BAAALAAECgUICwAAAA==.Azti:BAABLAAECoEUAAQBAAgIbRySCADcAQABAAcIZh2SCADcAQACAAIINRYPSwCEAAADAAEICwHLMAAqAAAAAA==.',Ba='Bauer:BAAALAAECgEIAQAAAA==.',Be='Beckinsale:BAAALAADCgcIBwAAAA==.',Bi='Bigtotempole:BAAALAADCggIDwAAAA==.',Bl='Blackkheartt:BAAALAADCgIIAgAAAA==.Bland:BAAALAAECgYIBQAAAA==.Blappin:BAAALAADCgQIBAAAAA==.Bloodgrog:BAAALAADCgYIBgAAAA==.Bloodmyst:BAAALAAECgUICQAAAA==.Blooshield:BAAALAADCggIEwAAAA==.',Bo='Boatsandho:BAAALAAECgEIAQAAAA==.Boneman:BAAALAAECgEIAQAAAA==.Bookwyrm:BAAALAADCgcIDQAAAA==.',By='Byssrak:BAAALAADCggICAAAAA==.',Ca='Cailan:BAAALAADCggIDwAAAA==.Caladiir:BAAALAAECgcIEwAAAA==.Casandera:BAAALAAECgEIAQABLAAECgUICQAEAAAAAA==.',Ce='Cerealmilk:BAAALAADCggIDQABLAAECgIIAgAEAAAAAA==.',Ch='Chopshop:BAAALAADCgMIAwAAAA==.Christopher:BAAALAAECgcIDAAAAA==.Chí:BAAALAADCgYIBgAAAA==.',Co='Cocofluff:BAAALAAECgcIEQAAAA==.Cowmandment:BAAALAADCgcIDQAAAA==.',Cr='Creepydemise:BAAALAAECgMIBgAAAA==.Creepydrunk:BAAALAADCgQIBAABLAAECgMIBgAEAAAAAA==.',Da='Daedra:BAAALAADCgUIBQAAAA==.Daggett:BAAALAAECgMIBAAAAA==.Dannydael:BAAALAADCgcIBwAAAA==.Darkcross:BAAALAADCggIEgAAAA==.Darthorak:BAAALAAECgEIAQAAAA==.Davennial:BAAALAAECgIIAgAAAA==.Dawnn:BAAALAAECgEIAQAAAA==.',De='Deanbearowl:BAAALAAECgEIAQAAAA==.Deatnshadow:BAAALAADCggICgAAAA==.Demorolizer:BAAALAADCgcICgABLAAECgUICwAEAAAAAA==.Denden:BAAALAADCgUIBQAAAA==.Denounce:BAAALAAECgEIAQAAAA==.Derogatory:BAAALAADCggICAAAAA==.',Di='Dinden:BAAALAADCgcIBwAAAA==.Divineice:BAAALAAECggIBAAAAA==.',Dm='Dmncgdss:BAAALAAECgEIAQAAAA==.',Do='Dolgrim:BAAALAADCggICwAAAA==.Doregoran:BAAALAADCgUIBQAAAA==.',Dr='Dracopeet:BAAALAAECgQICAAAAA==.Dragondeez:BAAALAADCggICAAAAA==.Dragonstew:BAAALAADCgYIBgAAAA==.Drausella:BAAALAADCgUIBgAAAA==.Dregato:BAAALAAECgEIAQAAAA==.Drinknpull:BAAALAADCgcIBwAAAA==.',Du='Dubs:BAAALAADCggICAAAAA==.',Dw='Dwarkino:BAAALAADCggIDwAAAA==.',['Dõ']='Dõndon:BAAALAADCgcIDQAAAA==.',Eo='Eona:BAAALAAECgMIAwAAAA==.',Er='Ericcdraven:BAAALAAECgMIAwAAAA==.Erodoria:BAAALAAECgEIAQAAAA==.',Fa='Falkor:BAAALAAECgYICQAAAA==.Fayway:BAAALAAECgYIDAAAAA==.',Fe='Felostheros:BAAALAADCgEIAQAAAA==.Felrus:BAAALAADCgcIBwAAAA==.Femsurboy:BAAALAAECgIIAgAAAA==.Ferretus:BAAALAAECgEIAQAAAA==.',Fi='Firepower:BAAALAAECgMIBQAAAA==.',Fl='Flame:BAAALAADCgMIAwAAAA==.',Fr='Freshyx:BAAALAADCgcIBwAAAA==.Frostypeaks:BAAALAADCggIDwAAAA==.',Fu='Funnypiggy:BAAALAADCgYIBgAAAA==.',Fy='Fyrael:BAAALAAECgQIBAAAAA==.',['Fö']='Föreststump:BAAALAADCgcIDAAAAA==.',Ga='Galdir:BAAALAAECgYICAAAAA==.Gallielynne:BAAALAADCggICgAAAA==.Ganache:BAAALAAECgEIAQAAAA==.Gantos:BAAALAADCgcIEQAAAA==.',Gi='Giggles:BAAALAADCggIDgAAAA==.',Gl='Glennspyder:BAAALAADCgcIDgABLAAECgEIAQAEAAAAAA==.Glomp:BAAALAADCgUIBQAAAA==.',Gr='Groddles:BAAALAADCggICgAAAA==.Grodlee:BAAALAADCgUIBQAAAA==.Grook:BAAALAADCgEIAQABLAAECgcIBwAEAAAAAA==.',Ha='Hailstorm:BAAALAAECgIIAgAAAA==.Hanjo:BAAALAAECgQICAAAAA==.',Ig='Igrisa:BAAALAAECgEIAQAAAA==.',Ja='Jackiblue:BAAALAAECgEIAQAAAA==.',Je='Jellybreak:BAAALAAECgUIBwAAAA==.',Ji='Jimmybones:BAAALAADCgIIAgAAAA==.',Jj='Jjam:BAAALAADCgYIBgAAAA==.',Ju='Juicycrop:BAAALAAECgMIBAAAAA==.Julius:BAAALAAECgcICgAAAA==.',Jy='Jyrian:BAAALAAECgQIBwAAAA==.',Ka='Kaanâ:BAAALAAECgQICAAAAA==.Kaelei:BAAALAADCgcICAAAAA==.Kateblue:BAAALAAECgQICAAAAA==.',Ke='Keeble:BAAALAADCggIEAAAAA==.Kelser:BAAALAAECgMIAwAAAA==.',Ki='Killtia:BAAALAADCggIDgAAAA==.Kir:BAAALAADCgcIBwAAAA==.',Kr='Kreepywife:BAAALAADCgQIBAAAAA==.Krowley:BAAALAAECgEIAQAAAA==.',Le='Leahu:BAAALAAECgUIBwAAAA==.Lediaa:BAAALAAECgEIAQAAAA==.Lexijen:BAAALAADCgcIBAAAAA==.',Li='Lifehunter:BAAALAADCgEIAQABLAAECgUIBgAEAAAAAA==.Likenoudder:BAAALAADCggIEwAAAA==.Littlespyone:BAAALAAECgEIAQAAAA==.',Lo='Locholovis:BAAALAAECgMIAwAAAA==.Lockdrop:BAAALAAECgcICAAAAA==.Longhorse:BAAALAAECgIIAgAAAA==.',Lu='Luminouss:BAAALAAECgUICQAAAA==.Lumpia:BAAALAAECgcIDwAAAA==.',Ma='Maggus:BAAALAADCgcICQAAAA==.Majin:BAAALAAECgIIAgAAAA==.Malvorak:BAAALAAECgEIAQAAAA==.Mameka:BAAALAAECggICAAAAA==.',Me='Melissandra:BAAALAAECgQICAAAAA==.Merab:BAAALAADCgcICgAAAA==.Mercas:BAAALAAECgMIBQAAAA==.Mericadk:BAAALAAECggIDAAAAA==.Mezi:BAAALAAECgUIBwAAAA==.',Mh='Mhonster:BAAALAAECgUIBgAAAA==.',Mi='Milkable:BAAALAADCgYIBgAAAA==.',Mo='Mortalion:BAAALAAECgYIBgAAAA==.',Ms='Msvelvet:BAAALAADCgEIAQABLAADCgUIBQAEAAAAAA==.',Mu='Mullen:BAAALAAECgEIAQABLAAECgIIAgAEAAAAAA==.Mulron:BAAALAAECgEIAQAAAA==.',My='Mysolidsnake:BAAALAAECgEIAQAAAA==.',Na='Nalordron:BAAALAADCgMIAwAAAA==.Nardenan:BAAALAADCggICAAAAA==.',Ni='Nightsky:BAAALAADCgQIBAAAAA==.',No='Noraeliice:BAAALAADCgcIBwAAAA==.Noreda:BAAALAAECgcIBwAAAA==.Notdaimler:BAAALAAECgIIAgAAAA==.',Ny='Nystria:BAAALAADCggICAAAAA==.',Ok='Okwøn:BAAALAADCggICAAAAA==.',Oo='Oozwoz:BAAALAADCggIBAAAAA==.',Pe='Pewpewtazarz:BAAALAADCgYIBgAAAA==.',Ph='Phrock:BAAALAAECgEIAQAAAA==.',Pl='Plagueblade:BAAALAAECgQICAAAAA==.Plaguee:BAAALAADCgYIBgAAAA==.',Po='Poppy:BAAALAAECgQIBwAAAA==.',Pr='Prescription:BAAALAADCggICQAAAA==.',Pu='Puff:BAAALAADCgMIBAAAAA==.Puntardo:BAAALAAECgMIBgAAAA==.Puppeteer:BAAALAADCgcIDgAAAA==.',Ra='Ragingrain:BAAALAAECgMIAwAAAA==.Rainthefire:BAAALAAECgcIDwAAAA==.Rawktuah:BAAALAAECgYICgAAAA==.',Re='Redcross:BAAALAADCgQIBAAAAA==.Redoxx:BAAALAAECgMIAwAAAA==.Restofarian:BAAALAAECgYICQAAAA==.Retino:BAAALAADCgMIAwAAAA==.Revie:BAAALAADCgcIBwAAAA==.',Rh='Rhagnor:BAAALAADCggICwAAAA==.',Ri='Righteous:BAAALAAECgMIAwAAAA==.',Ro='Roahnollins:BAAALAAECgIIAgAAAA==.Roray:BAAALAAECgEIAQAAAA==.Rotinshot:BAAALAAECgYIBgAAAA==.',Sa='Sahrotaar:BAAALAAECgEIAQAAAA==.',Se='Seagrams:BAAALAAECgUIBQAAAA==.Seizon:BAAALAAECgMIBAAAAA==.Serom:BAAALAAECgEIAQAAAA==.Sesshomaaru:BAAALAADCgcIBwAAAA==.',Sh='Shaazrah:BAAALAAECgIIAwABLAAECgcIEwAEAAAAAA==.Shadowbaby:BAAALAADCgcIBwAAAA==.Shameeps:BAAALAAECgIIAgAAAA==.Sharkie:BAAALAAECgYIDAAAAA==.Sharkyng:BAAALAAECgYIDgAAAA==.Sharpshôôter:BAAALAADCggICQAAAA==.Sherunn:BAAALAAECgEIAQAAAA==.Shimakaze:BAAALAAECgUIBwAAAA==.Shymistress:BAAALAAECgYICQAAAA==.Shåmmy:BAAALAAECgUICQAAAA==.',Si='Sins:BAAALAAECgQIBgAAAA==.',Sk='Skiá:BAAALAAECgUICAAAAA==.Sko:BAAALAAECgEIAQAAAA==.Skrinkles:BAAALAAECgEIAQAAAA==.',Sl='Slayerr:BAAALAADCgIIAwAAAA==.',Sp='Spiceymcmak:BAAALAADCgEIAQAAAA==.Sploosh:BAAALAADCggICAAAAA==.Splàsh:BAAALAAECgMIBwAAAA==.',Sq='Squattin:BAAALAAECgcIBwAAAA==.',St='Stoneboot:BAAALAAECgQIBAAAAA==.',Su='Sumaria:BAAALAAECgEIAQAAAA==.',Sw='Swain:BAAALAADCggICAAAAA==.Sweetvixen:BAAALAADCgUIBQAAAA==.',Ta='Takeda:BAAALAAECgEIAQAAAA==.Talisya:BAAALAAECgYIBgAAAA==.Tandria:BAAALAADCgcICgAAAA==.',Te='Teakaachu:BAAALAADCggIDwAAAA==.Terdanator:BAAALAAECgMIAwAAAA==.Terewinf:BAAALAAECgIIAgAAAA==.Terhali:BAAALAADCgYICgAAAA==.',Th='Thaeras:BAAALAADCggIEAAAAA==.Thanatus:BAAALAAECgYIDAAAAA==.Thendroz:BAAALAADCgcIBwAAAA==.',To='Tosar:BAAALAAECgcICwAAAA==.',Tr='Treats:BAAALAADCggIDQAAAA==.Tridius:BAAALAAECgYICAAAAA==.Trumped:BAAALAADCgMIBAAAAA==.',Tw='Twittle:BAAALAADCgEIAQAAAA==.',Ty='Tyloo:BAAALAAECgYICQAAAA==.Tyrmin:BAAALAAECgMIBgAAAA==.Tyton:BAAALAADCgQIBAAAAA==.',Ur='Uraenus:BAAALAAECgQIBwAAAA==.Uriah:BAAALAADCgcIDgAAAA==.Uryu:BAAALAADCggIFQAAAA==.Urïah:BAAALAADCgYICQABLAADCgcIDgAEAAAAAA==.',Ut='Utherr:BAAALAADCggICgAAAA==.',Va='Vaeirn:BAAALAADCggICAAAAA==.Vashirr:BAAALAAECgEIAQAAAA==.',Ve='Velarina:BAAALAADCgQIBAAAAA==.Velkan:BAAALAAECgEIAQAAAA==.Vengbladez:BAAALAADCggICQAAAA==.Vergus:BAAALAAECgYICgAAAA==.Vesaelia:BAAALAAECgIIAwAAAA==.',Vi='Violamax:BAABLAAFFIEGAAIFAAQIhRJRAQBXAQAFAAQIhRJRAQBXAQAAAA==.Violinmax:BAABLAAECoEWAAMGAAgIqRoRAQCOAgAGAAgIqRoRAQCOAgAHAAYI8QsmSQATAQABLAAFFAQIBgAFAIUSAA==.Viral:BAAALAAECggICAAAAA==.',Vo='Vonnie:BAAALAAECgEIAQAAAA==.',Wa='Wardwhelp:BAAALAADCgMIAwABLAAECgIIAgAEAAAAAA==.',Wi='Wifehaver:BAAALAAECgYICQAAAA==.Winniedehpoo:BAAALAAECgMIAwAAAA==.Winniejahpoo:BAAALAAECgYIBgAAAA==.',Wo='Wooloo:BAABLAAECoEXAAQCAAgIUyRiAwAvAwACAAgIUyRiAwAvAwADAAQIChRPDwBAAQABAAIIuBJ0PQBxAAAAAA==.',Wr='Wrathirnesta:BAAALAAECgEIAQAAAA==.',Wy='Wynona:BAAALAAECgEIAQAAAA==.',Xa='Xanagore:BAAALAAECgQIBQAAAA==.',Xo='Xorroth:BAAALAADCgYIBgAAAA==.',Xu='Xunie:BAAALAAECgIIAgAAAA==.',Xx='Xxie:BAAALAAECggIBAAAAA==.',Yi='Yisselda:BAAALAADCgMIAwAAAA==.',Za='Zana:BAAALAAECgUIBwAAAA==.',Zb='Zbrute:BAAALAAECgEIAQAAAA==.',Ze='Zenny:BAAALAAECgYIBgAAAA==.',['Øk']='Økwøn:BAABLAAECoETAAIHAAgIxB5YCQDsAgAHAAgIxB5YCQDsAgAAAA==.',['ße']='ßeorn:BAAALAADCgQIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end