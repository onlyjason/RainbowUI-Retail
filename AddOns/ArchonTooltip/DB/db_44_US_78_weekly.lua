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
 local lookup = {'Rogue-Assassination','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Mage-Arcane','Rogue-Subtlety','DeathKnight-Frost','DemonHunter-Havoc','Warrior-Protection','Rogue-Outlaw','Priest-Holy','Priest-Discipline',}; local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aedaris:BAAALAAECgYIDAAAAA==.Ael:BAAALAAECgIIAgAAAA==.',Ag='Agiel:BAAALAADCggICQAAAA==.',Al='Alithial:BAAALAADCgUIBQAAAA==.Allisa:BAAALAAECgIIAgAAAA==.',An='Anlaky:BAAALAAECgYIEAABLAAFFAQICAABAJEaAA==.Anvious:BAAALAAECgMIBQAAAA==.Anxious:BAAALAADCgUIBQAAAA==.',Ap='Applecrusher:BAAALAAECgMIAwAAAA==.',Aq='Aquilea:BAAALAAECgEIAQAAAA==.',Ar='Artzlayer:BAAALAAECgYIDAAAAA==.Aríes:BAAALAAECgYIDQAAAA==.',As='Asami:BAAALAADCgcIBwAAAA==.Ashveil:BAAALAAECgMIBQAAAA==.',At='Athelloren:BAAALAADCgMIBQAAAA==.',Av='Avakyn:BAAALAAECgYIDwAAAA==.',Aw='Awuuga:BAAALAADCgEIAQAAAA==.',Az='Az:BAAALAAECgYIBgAAAA==.Azamalaza:BAAALAAECgMICAAAAA==.Azmo:BAAALAAECgIIAgAAAA==.',Ba='Badb:BAAALAAECgIIAgAAAA==.Balanceme:BAAALAADCgYIBgAAAA==.Barad:BAAALAADCgYIBgAAAA==.',Be='Beelphegor:BAAALAADCgYIBgABLAADCgcIAgACAAAAAA==.Belphine:BAAALAADCgcIBwAAAA==.',Bi='Bicksmage:BAAALAAECgEIAQAAAA==.Bigdaddylock:BAABLAAECoEVAAQDAAgI+SBiBQABAwADAAgI+SBiBQABAwAEAAQIQh4vJQD2AAAFAAEIhx7/IwBfAAAAAA==.Bingle:BAAALAAECgIIAgAAAA==.',Bk='Bkk:BAAALAADCgIIAwAAAA==.',Bl='Bladeterror:BAAALAADCggICwAAAA==.Blighteÿe:BAAALAADCggIDQAAAA==.Blightèye:BAAALAAECgMIBgAAAA==.Blur:BAAALAAECgQIBQAAAA==.',Bo='Bohica:BAAALAADCgcIBwAAAA==.Bombdiggity:BAAALAAECgIIAgAAAA==.Bonnierotted:BAABLAAECoEXAAIGAAgI5iHKBQD9AgAGAAgI5iHKBQD9AgAAAA==.Boynaja:BAAALAAECgMIAwAAAA==.',Br='Brickwall:BAAALAADCgMIBAABLAAECgMIBgACAAAAAA==.',Ca='Cakebringer:BAAALAAECgIIAgAAAA==.Caroshi:BAAALAAECgUIBQAAAA==.',Ce='Ceramic:BAAALAADCgEIAQAAAA==.',Ch='Chickensalt:BAAALAADCgcIBwAAAA==.Choney:BAAALAADCggICAAAAA==.Chud:BAAALAAECgYIDgAAAA==.Chulla:BAAALAAECgIIAgAAAA==.',Co='Colcutro:BAAALAADCgcIBwAAAA==.Comillhoe:BAAALAAECgMIAwAAAA==.Comillpeace:BAAALAAECgYIBgAAAA==.',Cr='Critter:BAAALAADCgIIAgAAAA==.Crozier:BAAALAADCgYIBgAAAA==.',Cu='Curb:BAAALAAECgYIDQAAAA==.Curby:BAAALAAECgIIAgAAAA==.Cursedfennec:BAAALAAECgMIBQAAAA==.Curseofòwó:BAAALAAECgIIAgAAAA==.',Da='Damnnyou:BAAALAADCggICAABLAAECgYIDwACAAAAAA==.',De='Deloraine:BAABLAAECoEWAAIGAAgIcR8SCADOAgAGAAgIcR8SCADOAgAAAA==.Demonicfaith:BAAALAAECgYICQAAAA==.Dexxi:BAAALAADCgMIAwAAAA==.',Di='Dirtyfux:BAAALAAECggIAQAAAA==.Dirtyneedles:BAAALAAECgYIDAAAAA==.Divinechill:BAAALAADCgYIBgAAAA==.',Dk='Dkuy:BAAALAAECgYICwAAAA==.',Dr='Dracaena:BAAALAAECgYIDwAAAA==.Draining:BAAALAAECggIBAAAAA==.Drekavach:BAAALAAECgIIAgAAAA==.Driden:BAAALAADCgYIBgAAAA==.',Eh='Ehee:BAAALAADCggICAABLAAECgYICwACAAAAAA==.',El='Elexann:BAAALAAECgMIAwAAAA==.Elleen:BAAALAADCgYIBwAAAA==.',Em='Emoduh:BAAALAADCggICAAAAA==.Emopapa:BAAALAADCggIDwAAAA==.',En='Endlessdh:BAAALAAECgYIDwAAAA==.Engi:BAABLAAECoELAAIHAAYISxLmNwB+AQAHAAYISxLmNwB+AQAAAA==.',Er='Erayice:BAAALAAECgEIAQAAAA==.Erissaria:BAAALAAECgIIAwAAAA==.',Ev='Evilbanana:BAAALAADCgMIAwAAAA==.',Ex='Exilecross:BAAALAAECgYIDAAAAA==.',Fa='Fayyra:BAAALAAECggIDwAAAA==.',Fe='Fed:BAAALAAECgMIBwAAAA==.Ferndru:BAAALAADCgUIBQAAAA==.',Fi='Fiaadh:BAAALAADCgMIAwAAAA==.Firstdegree:BAAALAAECgYICQAAAA==.',Fl='Flameshock:BAAALAAECgMIBgAAAA==.',Fu='Funkymajik:BAAALAAECgEIAQAAAA==.Furrywarrior:BAAALAAECgMIAwAAAA==.',Ga='Garfield:BAAALAAECgIIAgABLAAFFAIIAgACAAAAAA==.Garugala:BAAALAAECgYIDQAAAA==.',Gi='Gigas:BAAALAADCgEIAQABLAADCgYIBgACAAAAAA==.',Gl='Glyphe:BAAALAAECgMIAwAAAA==.',Gr='Greatapoc:BAAALAADCgcICwAAAA==.',Gu='Gunkle:BAAALAADCgIIAgAAAA==.Guårdian:BAAALAAECgMIBAAAAA==.',Ha='Habitat:BAAALAADCgcIDAAAAA==.Handofillidn:BAAALAAECgIIAgAAAA==.',He='Heartlessa:BAAALAAECgEIAQAAAA==.Herrion:BAABLAAECoEVAAQEAAgIByRRCgDCAQAEAAUIIiZRCgDCAQADAAMIhCCSMwAgAQAFAAMIWQs1GQC2AAAAAA==.',Ho='Holyberry:BAAALAAECgQIBwAAAA==.How:BAAALAAECgEIAQAAAA==.',Hu='Huntenei:BAAALAAECgYIDwAAAA==.Huzz:BAAALAADCgQIBwAAAA==.',Hw='Hwanjeab:BAAALAADCgYIBgAAAA==.',In='Incredihulk:BAAALAADCgUIBAABLAAECgYIDAACAAAAAA==.Iniquity:BAAALAADCgUIBQAAAA==.',Ja='Jassine:BAAALAAECgYIBQAAAA==.',Jd='Jday:BAAALAAECgMIBAAAAA==.',Je='Jef:BAABLAAECoEUAAMIAAgI8x1IAgCQAgAIAAcIXxxIAgCQAgABAAQIPh11JQBIAQABLAAFFAQICAABAJEaAA==.',Ji='Jinkazamaz:BAABLAAECoEUAAIJAAcIyB9+EACGAgAJAAcIyB9+EACGAgAAAA==.',Jk='Jkfury:BAAALAAECgQICAAAAA==.',Js='Js:BAAALAAECgYICQAAAA==.',Ju='Jubei:BAAALAADCgMIAwABLAAECgYICwAHAEsSAA==.',Ka='Kaaru:BAAALAAECgEIAQAAAA==.Kaihavocz:BAAALAAECgIIAgAAAA==.Kalavea:BAAALAAECgIIAgAAAA==.Kamei:BAAALAAECgIIAwAAAA==.Kania:BAAALAAECgYIDwAAAA==.',Ke='Keeze:BAAALAADCgcIBwAAAA==.',Ki='Kiwichaos:BAABLAAECoEWAAIKAAgI9B2iDQCxAgAKAAgI9B2iDQCxAgAAAA==.',Kr='Krazzul:BAAALAADCgUIBwAAAA==.',Ky='Kycetesar:BAAALAADCgcIBwAAAA==.Kynra:BAAALAAECgMIAwAAAA==.Kynralol:BAAALAAECgcIDAAAAA==.',La='Laomoo:BAAALAAECgMIAwAAAA==.',Le='Legolazz:BAAALAAECgYIDgAAAA==.',Li='Lightbeef:BAAALAAECgMIAwAAAA==.Littleriver:BAAALAAECgYICQAAAA==.',Lp='Lpayn:BAAALAAECgIIAgAAAA==.',Lu='Lugroth:BAAALAAECgYIBgABLAAECggIFQAEAAckAA==.',Ma='Maize:BAAALAAECgYICQAAAA==.Marcy:BAAALAADCgcIBwAAAA==.',Me='Megs:BAAALAAECgYICQAAAA==.',Mi='Micn:BAAALAAECgMIBgAAAA==.Miri:BAAALAAECgYIDgAAAA==.',Mo='Moistpole:BAAALAADCgcIEQAAAA==.Mongk:BAAALAADCgMIAwABLAAECgYICwACAAAAAA==.Morphio:BAAALAAECgQICAAAAA==.',My='Mysterio:BAAALAAECgYIDAAAAA==.',Na='Nahaza:BAAALAADCggIDgAAAA==.',Ni='Nikola:BAAALAAECgYICwAAAA==.Nimro:BAABLAAECoEWAAILAAgILxRyCwDlAQALAAgILxRyCwDlAQAAAA==.',No='Noirebringer:BAAALAAECgYIDAAAAA==.Noirexd:BAAALAADCggIEAAAAA==.',Nu='Nuferax:BAAALAAECgEIAQAAAA==.',Or='Orangecat:BAAALAADCggIDwAAAA==.Orinocco:BAAALAADCgYIBgAAAA==.',Pa='Painfire:BAAALAADCggIDwAAAA==.Palliative:BAAALAAECgIIAgAAAA==.',Po='Porpus:BAAALAAECgEIAQAAAA==.',Ps='Psalms:BAAALAAECgYIBwAAAA==.',Pu='Purplecat:BAAALAAECgYICQAAAA==.',Py='Pyrusdk:BAAALAAECggIAwAAAA==.',Qu='Quesarah:BAAALAADCggIAQAAAA==.',Qw='Qweffor:BAAALAAECgcIDgAAAA==.',Re='Readydeady:BAAALAAECgcIDQAAAA==.Resurrect:BAAALAAECgEIAQAAAA==.',Ri='Ripdis:BAAALAADCgcIDAAAAA==.',Ro='Rodger:BAAALAAECgYICwAAAA==.Ronfirestorm:BAAALAADCggIDgABLAAECgYICQACAAAAAA==.Ronhunts:BAAALAAECgMIAwABLAAECgYICQACAAAAAA==.Ronlock:BAAALAADCgQIBAABLAAECgYICQACAAAAAA==.',Ry='Rythcard:BAAALAADCggIDgAAAA==.',['Rô']='Rôlayne:BAAALAADCggIDwAAAA==.',Sa='Salvare:BAABLAAECoEVAAIMAAgI7hjaAQB/AgAMAAgI7hjaAQB/AgAAAA==.Sanea:BAAALAADCggIEAAAAA==.Sardrindon:BAAALAADCgIIAgAAAA==.Savage:BAAALAADCgIIAgAAAA==.',Sc='Scrungorshus:BAAALAAECgMIAwAAAA==.',Se='Sedge:BAACLAAFFIEIAAMBAAQIkRr1AQAcAQABAAMI/hf1AQAcAQAIAAIIlB4vAQDEAAAsAAQKgRgAAwgACAgvJj8BAO8CAAgABwiNJD8BAO8CAAEABAi5JEQbAKIBAAAA.',Sg='Sgthavok:BAAALAAECgYICQAAAA==.',Sh='Shadowind:BAAALAAECggICAAAAA==.Shakor:BAAALAAECgIIAgAAAA==.Shammalxs:BAAALAADCggICAAAAA==.Shampooing:BAAALAAECgUIBQAAAA==.Sharpknife:BAAALAAECgIIAQAAAA==.Shonk:BAAALAAECgcIEAAAAA==.',Si='Sicckbrew:BAAALAADCgcICAAAAA==.',Sj='Sjsj:BAAALAADCgcIBwAAAA==.',Sk='Skizzyy:BAAALAAECgYIBgAAAA==.',Sl='Släyêr:BAAALAADCgMIAwAAAA==.',Sn='Snottite:BAAALAAECgEIAQAAAA==.',Sp='Spiral:BAAALAADCgcIBwAAAA==.Spliice:BAAALAADCgYIBgAAAA==.Sportsfan:BAAALAAECgYIDQAAAA==.',Sq='Squiish:BAAALAAFFAIIAgAAAA==.',St='Stickypriest:BAAALAAECgYIDQAAAA==.Strawmagic:BAABLAAECoEYAAIHAAgIKCXNAQBeAwAHAAgIKCXNAQBeAwAAAA==.Streamliner:BAAALAAECgYIDAAAAA==.',Su='Sustangelia:BAAALAAECgYIDQAAAA==.',Sw='Swordkiller:BAAALAADCggIBQAAAA==.',Ta='Talletalanot:BAAALAAECgYIDgAAAA==.Tazocin:BAAALAADCgUIBQAAAA==.',Th='Thrugg:BAAALAADCggIEQAAAA==.',Ti='Tiberian:BAAALAAECgIIAgAAAA==.Tiltbear:BAAALAADCgcICwAAAA==.',To='Totems:BAAALAAECgYICwAAAA==.',Tr='Trapboi:BAAALAADCgcIAgAAAA==.Trass:BAAALAAECgYIDQAAAA==.',Tu='Tuzz:BAAALAAECgMIAwAAAA==.',Ty='Tyloriesh:BAAALAADCgUIBQAAAA==.',['Tö']='Töraque:BAAALAADCggIDwAAAA==.',Va='Vanor:BAAALAADCgIIAgAAAA==.Varg:BAAALAADCgUIBQAAAA==.',Ve='Velandria:BAAALAAECgQIBwAAAA==.Velyssel:BAAALAADCgMIAwAAAA==.Vermeil:BAAALAADCgcIBwAAAA==.Vermythrax:BAAALAAECgEIAQAAAA==.',Vo='Voltashan:BAAALAAECgMIAwAAAA==.',Wa='Warlboy:BAAALAAECgMIAwABLAAECgQIBAACAAAAAA==.Warth:BAAALAAECgIIAgAAAA==.',Wc='Wchin:BAAALAAECgYIDQAAAA==.',We='Wedlock:BAAALAADCgMIAQAAAA==.Wendyy:BAAALAAECgYIEgAAAA==.',Wh='Whakaraua:BAAALAADCggIEQAAAA==.Whio:BAAALAAECgQICQAAAA==.',Wi='Widdy:BAAALAAECgUICQAAAA==.Wildginger:BAAALAAECgQICAAAAA==.',Wo='Worgenenergy:BAAALAADCgUIBQAAAA==.',Xe='Xedd:BAABLAAECoEXAAMNAAgIFxiDDwBCAgANAAgIFxiDDwBCAgAOAAEI0R2dFQBWAAAAAA==.Xerxexy:BAAALAAECgYICAAAAA==.',Xi='Xiera:BAAALAAECgEIAQAAAA==.',Ya='Yaminosaishi:BAAALAAECgYIDwAAAA==.Yamiprays:BAAALAADCgcIEgAAAA==.',Za='Zani:BAAALAAECgYIDwAAAA==.',Zx='Zxtole:BAAALAADCggIDgAAAA==.',['Ôx']='Ôx:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end