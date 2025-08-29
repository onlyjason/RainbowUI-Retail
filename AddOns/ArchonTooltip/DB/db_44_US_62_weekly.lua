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
 local lookup = {'Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Mage-Arcane','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection','Warrior-Fury','Rogue-Assassination','Priest-Shadow','Shaman-Restoration','Paladin-Holy','Hunter-Marksmanship',}; local provider = {region='US',realm="Dath'Remar",name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abyssal:BAAALAAECgMIAwAAAA==.',Ac='Ace:BAAALAAECgYIBgAAAA==.',Ad='Ade:BAAALAAECgYICgAAAA==.Adezardre:BAAALAAECgEIAQAAAA==.Adhûi:BAAALAADCggICAAAAA==.Adrollan:BAAALAAECgMIBQAAAA==.Advosary:BAAALAAECgIIAgAAAA==.',Ae='Aeron:BAAALAADCgcIBwAAAA==.',Af='Afterburn:BAAALAADCgcIBwAAAA==.',Ag='Agaluga:BAAALAAECgMIAwAAAA==.',Ai='Aigilas:BAAALAAECgYIDgAAAA==.',Ak='Akiriya:BAAALAAECgYICgAAAA==.Akiros:BAAALAAECgMIBgAAAA==.',Al='Alariev:BAAALAADCgYICwAAAA==.Alci:BAAALAADCgcIBwAAAA==.Aletech:BAAALAAECgYICgAAAA==.Aliesá:BAAALAAECgQIBAAAAA==.Alilea:BAAALAAECgQIBQAAAA==.Alisandrah:BAACLAAFFIEGAAMBAAMIUSAuAgA5AQABAAMIUSAuAgA5AQACAAIIGhd7AwCxAAAsAAQKgRgAAwEACAhpJuIAAHQDAAEACAi7JeIAAHQDAAIABwjgJXwCAGICAAAA.Allegedly:BAAALAAECgQIBgAAAA==.Allforsaken:BAAALAAECgMIBAAAAA==.Alucarð:BAAALAAECgEIAQAAAA==.',Am='Amber:BAAALAAECgIIAgAAAA==.Amberlicious:BAAALAADCggICAABLAAECgIIAgADAAAAAA==.Amberlilly:BAAALAADCgcIBwABLAAECgIIAgADAAAAAA==.Amilandris:BAAALAAECgYIDAAAAA==.',An='Analalea:BAAALAADCgUICAAAAA==.Angrypanda:BAAALAAECgIIAQAAAA==.',Ap='Apoloc:BAAALAAECgIIAgAAAA==.Appolo:BAAALAAECgQIBwAAAA==.Apregio:BAAALAAECgYICgAAAA==.',Ar='Arazuren:BAAALAAECgUICgAAAA==.Archaedius:BAAALAAECgYICgAAAA==.Archslayer:BAAALAAECgIIAgAAAA==.Arcnuby:BAAALAADCgMIAwAAAA==.Arcshammy:BAAALAAECgMIBAAAAA==.Arlo:BAAALAAECgEIAgAAAA==.Arneus:BAAALAADCggIDwAAAA==.Artaq:BAAALAADCggIDwAAAA==.Arvanon:BAAALAAECgMIBQAAAA==.',As='Asann:BAAALAADCgcICAAAAA==.Asculapius:BAAALAAECgUICAAAAA==.Ashanar:BAAALAAECgEIAgAAAA==.Ashbringa:BAAALAAECgIIAgAAAA==.Ashmend:BAAALAAECgEIAQAAAA==.Ashtarm:BAAALAAECgIIAwABLAAECgcIDwADAAAAAA==.Assatur:BAAALAADCgQIBAAAAA==.Astarna:BAAALAADCggIDgAAAA==.',At='Athelass:BAAALAADCgcIBwAAAA==.Atriel:BAAALAADCggIEgAAAA==.',Au='Auvvyqt:BAAALAADCggIEAAAAA==.',Av='Avelinna:BAAALAAECgIIAgAAAA==.',Az='Aztrayel:BAAALAAECgMIBQAAAA==.Azurâ:BAAALAADCggIDwAAAA==.',Ba='Baalial:BAAALAAECgMIBAAAAA==.Babychino:BAAALAAECgEIAgAAAA==.Baelig:BAAALAADCgcIBwAAAA==.Bangbangbro:BAAALAADCgIIAgAAAA==.Barium:BAAALAADCgMIAwAAAA==.Barkfeather:BAAALAADCgYIBgAAAA==.Bastem:BAAALAAECgEIAQAAAA==.Batgirl:BAAALAAECgIIAgAAAA==.',Be='Beachcubes:BAAALAAECgIIAwAAAA==.Beadow:BAAALAAECgEIAQAAAA==.Beamac:BAAALAADCgMIAwAAAA==.Bearchested:BAAALAADCggICAAAAA==.Behrendorff:BAAALAAECgEIAQAAAA==.Belnewid:BAAALAAECgEIAQAAAA==.Belthsdruid:BAAALAADCgcIDgAAAA==.',Bi='Bigboomba:BAAALAAECgQIBgAAAA==.Bigdoomba:BAAALAADCggICAAAAA==.Billbee:BAAALAADCggIDwAAAA==.Biphh:BAAALAAECgcIDwAAAA==.',Bl='Blackvelvet:BAAALAAECgYIDgABLAAECgYIDgADAAAAAA==.Blazingness:BAAALAAECgIIAgAAAA==.Blessmedaddy:BAAALAADCgMIBQAAAA==.Blinkgoat:BAAALAADCgcIDAAAAA==.Bloodleater:BAAALAAECgYIDgAAAA==.Blowsbubbles:BAAALAADCggIFgAAAA==.',Bo='Bodom:BAAALAADCggIDwAAAA==.Boneyjam:BAAALAADCggIFwAAAA==.Boosti:BAAALAADCgcIBwAAAA==.Bowgan:BAAALAADCgcIDQABLAAECggICAADAAAAAA==.Bowjob:BAAALAAECgYICgAAAA==.',Br='Brewboy:BAAALAAECgUIAwAAAA==.Brok:BAAALAAECgUIAgAAAA==.Brunnhylde:BAAALAADCgcIEAABLAAECgEIAQADAAAAAA==.Brutalight:BAAALAAECgMIBAAAAA==.Brutus:BAAALAAECgYIDgAAAA==.',Bu='Budgìe:BAAALAAECgMIBAAAAA==.Buggzz:BAAALAAECgcIEQAAAA==.Burningblood:BAAALAADCgQIBAAAAA==.Burntpotatoe:BAAALAADCgEIAQAAAA==.',Bw='Bwonswamdi:BAAALAADCggIDAAAAA==.',By='Bynn:BAAALAADCgYIBgAAAA==.',['Bä']='Bärebäck:BAAALAADCgEIAQAAAA==.',Ca='Cactusnight:BAAALAAECgIIAgAAAA==.Cadyheron:BAAALAAECgYIDAAAAA==.Cahtbl:BAAALAADCgcIBwAAAA==.Calaveran:BAAALAADCgUIBQAAAA==.Callin:BAAALAAECgQIBgAAAA==.Calyx:BAAALAADCgYIBgAAAA==.Cancer:BAAALAADCggIHQAAAA==.Caoimhe:BAAALAAECgMIBAAAAA==.Caramord:BAAALAAECgEIAQAAAA==.Castalight:BAAALAADCggIDgABLAAECgIIAgADAAAAAA==.Castershot:BAAALAAECgIIAgAAAA==.Cavalier:BAAALAADCgcIEAAAAA==.Cayssae:BAAALAADCgIIAgAAAA==.',Ce='Celana:BAAALAAECgUICwAAAA==.Cemtar:BAAALAAECgYICQAAAA==.',Ch='Cheekyazz:BAAALAAECgIIAgAAAA==.Chimeria:BAAALAAECgEIAQAAAA==.Chirran:BAAALAAECgYICQAAAA==.Chookin:BAAALAAECgIIAgAAAA==.Chrillis:BAAALAADCgcIDQAAAA==.',Ci='Cindell:BAAALAAECgcICwAAAA==.Cinderstraza:BAAALAADCgcIBwAAAA==.Cinnamonbuns:BAAALAADCggIDwABLAAECgIIAgADAAAAAA==.',Co='Cola:BAAALAADCgMIAwAAAA==.Conroy:BAAALAAECgMIBgAAAA==.Corldrin:BAAALAADCgcIBwAAAA==.Coronis:BAAALAAECgEIAQAAAA==.Corriana:BAAALAADCggIDwABLAAECgIIAgADAAAAAA==.',Cr='Crazee:BAABLAAECoEWAAIEAAgI9SISBQAlAwAEAAgI9SISBQAlAwAAAA==.Cryos:BAAALAAECgQIBwAAAA==.',Ct='Ctshammy:BAAALAAECgMIBQAAAA==.',Cu='Curian:BAAALAADCgcIBwAAAA==.Cursedyou:BAAALAADCggIFwAAAA==.Curserot:BAAALAAECgQIBQAAAA==.',Cy='Cylinne:BAAALAADCggICAAAAA==.Cynal:BAAALAAECgYIDAAAAA==.',['Cö']='Cöwgirl:BAAALAADCgcICQAAAA==.',['Cÿ']='Cÿrie:BAAALAADCgQIBAAAAA==.',Da='Daddyy:BAAALAADCggICAABLAAECggIFgAEAPUiAA==.Dallado:BAABLAAECoEUAAMFAAYIbBnbCgChAQAFAAYIbBnbCgChAQAGAAYIWQe+SAAeAQAAAA==.Dammo:BAAALAADCggIDgAAAA==.Damous:BAAALAAECgMIAwAAAA==.Daring:BAAALAAECgQIBQAAAA==.Dashbringer:BAAALAADCggIDwAAAA==.',Db='Dbigboss:BAAALAAECgEIAQAAAA==.',De='Deadlynewbz:BAAALAAFFAEIAQAAAA==.Deadstars:BAAALAADCgcIBwAAAA==.Deathbyshoe:BAAALAAECgEIAgAAAA==.Decypha:BAAALAAECgYIDgAAAA==.Delgar:BAAALAADCggIEAAAAA==.Demonboyz:BAAALAADCgcIEAAAAA==.Demonicnight:BAAALAAECgcIDQAAAA==.Demtara:BAAALAAECgcICAAAAA==.Denja:BAAALAADCggICAAAAA==.Derryth:BAAALAAECgYICAAAAA==.Dethro:BAAALAAECgYIEAAAAA==.Dethtickles:BAAALAADCgMIAwAAAA==.Dezit:BAAALAAECgYIEAAAAA==.Deådcow:BAAALAAECgQIBAAAAA==.',Di='Diabolicus:BAAALAADCgcIBwAAAA==.Dirtyret:BAAALAADCgYIBgAAAA==.Distruction:BAAALAADCgcICwAAAA==.Divinegirly:BAAALAAECgIIAgAAAA==.',Dn='Dniwsanavlys:BAAALAADCgcIBwAAAA==.',Do='Doom:BAAALAAECggIEQAAAA==.',Dr='Dracnock:BAAALAADCggIFgAAAA==.Drapary:BAAALAAECgMIBQAAAA==.Drark:BAAALAADCgQIBAABLAAECgUIAwADAAAAAA==.Drathdevar:BAAALAADCggIDgAAAA==.Dreamy:BAAALAADCggIDAAAAA==.Drinian:BAAALAAECgEIAgAAAA==.Druidicflows:BAAALAADCgQIBAAAAA==.',Du='Duskclaw:BAAALAAECgMIAwAAAA==.',Dy='Dyl:BAAALAAECgYIDgAAAA==.Dylexd:BAAALAAECgMIBAAAAA==.',['Dï']='Dïscpriest:BAAALAAECgEIAQAAAA==.',Ea='Eamis:BAAALAAECgQIBQAAAA==.',Ec='Eccentricity:BAAALAADCgIIAgAAAA==.Echomender:BAAALAADCgQIBAAAAA==.Eclipseqt:BAAALAADCggICAAAAA==.',Ei='Eivorr:BAAALAAECgMICAAAAA==.',El='Elenadanvers:BAAALAAECgIIAgAAAA==.Elesiass:BAAALAADCgUIBQAAAA==.Elmaco:BAAALAAECgYIDAAAAA==.Elseapi:BAAALAAECgEIAgAAAA==.Elys:BAAALAAECgYIDAAAAA==.',Em='Empra:BAAALAADCggIEwABLAAECgQIBwADAAAAAA==.',En='Endorpha:BAAALAADCgEIAQAAAA==.Ent:BAAALAAECgEIAgAAAA==.',Es='Esmaralda:BAAALAADCggIFwAAAA==.',Et='Etnie:BAAALAADCgUIBQAAAA==.',Ev='Everleaf:BAAALAADCggIFwAAAA==.',Fa='Faildave:BAAALAAECgMIAwAAAA==.Fallendivine:BAAALAAECgYIBgAAAA==.',Fe='Felraxis:BAAALAADCgMIAwABLAAECgMIBQADAAAAAA==.Fensmage:BAAALAAECgYIDAAAAA==.',Fi='Fistdk:BAAALAADCggICAAAAA==.',Fl='Flashinlight:BAAALAAECgIIAgAAAA==.Flintlck:BAAALAAECgIIAgAAAA==.Flooki:BAAALAADCgcIBwAAAA==.Flooky:BAAALAAECgIIAgAAAA==.',Fo='Folost:BAAALAADCggICgAAAA==.Fomor:BAAALAAECgIIAgAAAA==.Forbs:BAAALAADCgUIBQAAAA==.Foreignerr:BAAALAAECgEIAQAAAA==.',Fr='Frostyball:BAAALAAECgEIAQAAAA==.',Fu='Fubaar:BAAALAADCgMIAwAAAA==.Fumorian:BAAALAADCgcIDQAAAA==.Furrious:BAAALAAECgIIAgAAAA==.',Ga='Gallene:BAABLAAECoEXAAMHAAgITiUuAwDjAgAHAAgITiUuAwDjAgAIAAcIOByeHgC+AQAAAA==.Gandallf:BAAALAADCgYIBgAAAA==.Garakarak:BAAALAAECgIIAgAAAA==.Garrysanchez:BAAALAAECggIAQAAAA==.',Ge='Genimaculata:BAAALAAECgYIDgAAAA==.Gerince:BAAALAADCggIDgAAAA==.Geîsha:BAAALAADCgUIBgAAAA==.',Gh='Ghostarrow:BAAALAAECgMIBQABLAAECgUICQADAAAAAA==.Ghostxd:BAAALAADCgYIBwAAAA==.',Gi='Gingerbits:BAAALAAECggIAQAAAA==.',Gl='Gladios:BAAALAAECgEIAQAAAA==.Glarry:BAAALAADCggIDgAAAA==.Glidelicator:BAAALAAECgYIDwAAAA==.',Gn='Gnolan:BAAALAAECgIIAgAAAA==.',Go='Going:BAAALAAECgcIEAAAAA==.Goshin:BAAALAADCggIDgAAAA==.',Gr='Grandarcher:BAAALAAECgMIBQAAAA==.Grashk:BAAALAAECgMIBAAAAA==.Grimbel:BAAALAAECgMIBAAAAA==.Grimcritical:BAAALAADCgEIAQAAAA==.Grukal:BAAALAADCgQIBAAAAA==.Grux:BAAALAADCgQIAQABLAAECggICAADAAAAAA==.',Ha='Hadessham:BAAALAAECgQIBQAAAA==.Hagas:BAAALAADCggIFwAAAA==.Handydh:BAAALAAECgYICwAAAA==.Hanke:BAAALAADCggIFQAAAA==.Harleybear:BAAALAAECgMIAwAAAA==.',He='Healback:BAAALAAECgMIBAAAAA==.Hecatè:BAAALAADCgcIBwAAAA==.Heedgert:BAAALAADCgIIAgAAAA==.Heughligan:BAAALAAECgYIDAAAAA==.',Hi='Hirokey:BAAALAAECgcIEAAAAA==.',Ho='Holyhorn:BAAALAAECgEIAQAAAA==.Holylightt:BAAALAADCggIFAAAAA==.Hoshinomapo:BAAALAADCgQIBAAAAA==.',Hu='Hueningk:BAAALAADCggICgABLAADCggIFgADAAAAAA==.Humble:BAAALAAECgcIDwAAAA==.',Hy='Hydromender:BAAALAAECgMIAwAAAA==.Hyperactiv:BAAALAAECgIIAgABLAAECgUIAwADAAAAAA==.',Ic='Iciclex:BAAALAAECgQIBAAAAA==.Icymilky:BAAALAAECgQICAAAAA==.',Ig='Igneel:BAAALAAECgYIDgAAAA==.Igolin:BAAALAAECgcIEAAAAA==.',Il='Illfightyou:BAAALAAECgUICwAAAA==.Illumine:BAAALAADCgQIBQAAAA==.',Im='Imadragon:BAAALAAECgEIAQAAAA==.Imperials:BAAALAAECgYIDAAAAA==.Impsgosplat:BAAALAAECgEIAQAAAA==.',In='Inaminute:BAAALAAECgMIAwAAAA==.Inosolan:BAAALAAECgIIAgAAAA==.',Ir='Irritable:BAAALAAECgIIAgAAAA==.Irvinebrown:BAAALAAECgYIBgAAAA==.Irvinica:BAAALAAECgYIBgABLAAECgYIBgADAAAAAA==.',Is='Ishibo:BAAALAADCgcIBwAAAA==.Issii:BAAALAAECgIIAgAAAA==.Istenn:BAAALAAECgcIDQAAAA==.',It='Itchmay:BAAALAADCggIBAAAAA==.Ithyl:BAAALAAECgQIBgAAAA==.Itzslappy:BAAALAAECgYIDAAAAA==.',Iv='Ivenate:BAAALAADCgEIAQAAAA==.',Ja='Jadedoriana:BAAALAAECgYIDwAAAA==.Jammer:BAAALAADCggICAAAAA==.Janinda:BAAALAAECgYIDgAAAA==.Janine:BAAALAAFFAIIAwAAAA==.Jastina:BAAALAADCggIFgAAAA==.Jaszz:BAAALAAECgcIDwAAAA==.',Jb='Jb:BAAALAAECgYICAAAAA==.',Je='Jereaux:BAAALAAECgYIDwAAAA==.Jesto:BAAALAAECgQIBwAAAA==.',Ji='Jindy:BAAALAAECgQIBAAAAA==.',Jn='Jnockoff:BAAALAAECgMIAwAAAA==.',Jo='Joefist:BAAALAAECgMIAwAAAA==.Jorakotaluji:BAAALAADCggIDwAAAA==.Joshst:BAAALAADCgcICgAAAA==.Josta:BAAALAAECgIIAgAAAA==.Josto:BAAALAAECgMICgAAAA==.Jovyll:BAAALAAECgIIAgAAAA==.',Ju='Justmightee:BAAALAADCgEIAQAAAA==.',Ka='Kaelinth:BAAALAADCgIIAgAAAA==.Kaelyth:BAAALAAECgEIAgAAAA==.Kalsarikänit:BAAALAADCgEIAQAAAA==.Kamakazie:BAAALAAECgMIAwAAAA==.Kameiccillo:BAAALAADCgcIDgABLAAECgQIBAADAAAAAA==.Kamelle:BAAALAADCggIFQAAAA==.Karenstrasza:BAAALAAECgMIBQAAAA==.Kareya:BAAALAADCgcIBwAAAA==.Karynai:BAAALAADCgcIEAAAAA==.Kathundra:BAAALAADCgcIEQAAAA==.Kazoøie:BAAALAAECggICAAAAA==.',Kc='Kcar:BAAALAADCggIEQAAAA==.',Ke='Keikeivon:BAAALAAECgYIDAAAAA==.Kelandris:BAAALAAECgIIAgAAAA==.Kellanis:BAAALAAECggIAQAAAA==.Kelsern:BAAALAAECgYIDgAAAA==.Kevinstrasza:BAAALAAECgMIBQAAAA==.',Kh='Khaloran:BAAALAADCggIFgAAAA==.',Ki='Kiaaraa:BAAALAADCgYIBgAAAA==.Killshotbob:BAAALAADCgIIAgAAAA==.Kimjongheal:BAAALAAECgMIBAAAAA==.Kinnigit:BAAALAAECgYIDwAAAA==.Kinstalz:BAAALAAECgIIAgAAAA==.Kiphine:BAAALAADCggIDwAAAA==.Kipp:BAAALAAECgQIBQAAAA==.Kirky:BAAALAADCgcIBwAAAA==.Kismis:BAAALAADCgQIBAAAAA==.Kitanishi:BAAALAADCgcIEAAAAA==.Kithrah:BAAALAAECgcIEAAAAA==.Kithrâh:BAAALAADCggIDwABLAAECgcIEAADAAAAAA==.Kitsuneko:BAAALAAECgQIBwAAAA==.',Ko='Kolugar:BAAALAAECgcIDwAAAA==.Konkar:BAAALAAECgIIBAAAAA==.Korrín:BAAALAADCgUIBQABLAAECgYIDQADAAAAAA==.Korzz:BAAALAADCggIDwAAAA==.',Kr='Krokasa:BAAALAAECgQICgAAAA==.',['Kà']='Kàrmá:BAAALAADCgcIDQAAAA==.',['Ká']='Káyléth:BAAALAADCgIIAgAAAA==.',La='Laiceeshay:BAAALAADCgcIBwAAAA==.Laindre:BAAALAADCggICAAAAA==.Lallado:BAAALAAECgYIBgABLAAECgYIFAAFAGwZAA==.Large:BAAALAAECgQICgAAAA==.Lars:BAAALAAECgQIBwAAAA==.Larxe:BAAALAADCggIDgAAAA==.Lavagoat:BAAALAAECgMIAwAAAA==.',Le='Leicamf:BAAALAAECgEIAQAAAA==.Leiila:BAAALAADCgcIDQAAAA==.Lethanâ:BAAALAAECgYIDgAAAA==.Letmedie:BAAALAAECgIIAgAAAA==.Lez:BAAALAAECgcIDwAAAA==.',Li='Liaravara:BAAALAADCgUIBQAAAA==.Lieef:BAAALAAECgYIDAAAAA==.Lightmare:BAAALAADCgEIAQAAAA==.Lightmender:BAAALAADCgUICQAAAA==.Lilind:BAAALAAECgIIAgAAAA==.Lillypad:BAAALAADCggICAAAAA==.Linas:BAAALAADCgYIBgAAAA==.Liteon:BAAALAADCgQIBAAAAA==.Lizzo:BAAALAAECgQIBQAAAA==.',Lo='Lockedenload:BAAALAADCgcIDAAAAA==.Loewrelei:BAAALAADCgcIBwAAAA==.Logoze:BAAALAADCggIFwAAAA==.Lonedecay:BAAALAAECgEIAQAAAA==.Lorieyxo:BAAALAAECgIIAgAAAA==.Lorrim:BAAALAAECgMIBAAAAA==.',Lu='Lucifear:BAAALAADCggIBwAAAA==.Lupissolo:BAAALAADCggIDwAAAA==.Lute:BAAALAAECgMIBAAAAA==.',Ly='Lycain:BAAALAADCggIFQAAAA==.Lyssan:BAAALAADCgIIAgAAAA==.Lyth:BAAALAADCgcIAQAAAA==.Lythium:BAAALAADCgMIAwAAAA==.',['Lá']='Láiken:BAAALAADCggIFgAAAA==.',Ma='Madcalve:BAAALAAECgQIBQAAAA==.Madelinë:BAAALAADCgEIAQAAAA==.Madmoxxie:BAAALAAECgEIAQAAAA==.Mahgo:BAAALAADCggIGAAAAA==.Mahonanida:BAAALAAECgEIAQAAAA==.Maikara:BAAALAADCgcIBwAAAA==.Majinoodle:BAAALAAECgQIBAAAAA==.Malfalcator:BAAALAAECgMIBAAAAA==.Marieh:BAAALAADCgMIAwAAAA==.Maryberry:BAAALAAECgQIBAAAAA==.Maximuslee:BAAALAADCgEIAQAAAA==.Mazhun:BAAALAAECgIIAwAAAA==.Maëve:BAAALAAECgIIAgAAAA==.',Mc='Mcneill:BAAALAADCggICAAAAA==.',Me='Mekky:BAAALAAECgIIAgAAAA==.Meltharion:BAAALAADCggIDgAAAA==.Meowmeowmeow:BAAALAAECgUIBQAAAA==.Mercerful:BAAALAAECgMIAwAAAA==.Mereaux:BAAALAADCggIDwAAAA==.Merlinsbeard:BAAALAADCgcIBwAAAA==.Methox:BAAALAAECgUICQAAAA==.Meuseonekey:BAAALAAECgcICwAAAA==.Mezzosh:BAAALAADCggICAAAAA==.',Mi='Minnielock:BAAALAADCgMIAwAAAA==.Minotauren:BAAALAAECgMIAwAAAA==.Mirya:BAAALAAECgQIBgAAAA==.Mirä:BAAALAADCgYIBgABLAAECgYIDQADAAAAAA==.Missoni:BAAALAADCgQIBAAAAA==.Misstyheals:BAAALAAECgMIBAAAAA==.Mistyfisty:BAAALAADCggICAAAAA==.',Mo='Mochalatte:BAAALAAECgYICAAAAA==.Monanarr:BAAALAAECgEIAgAAAA==.Monsterunner:BAAALAADCgEIAQAAAA==.Moondive:BAAALAADCgMIAwAAAA==.Moopsy:BAAALAADCggIFgAAAA==.Moppsey:BAAALAADCggIEQAAAA==.Mops:BAAALAAECgEIAgAAAA==.Mordakai:BAAALAAECggIEgAAAA==.Mordane:BAAALAADCggICAAAAA==.Mordgrum:BAAALAADCggICAABLAAECggIEgADAAAAAA==.Mordrael:BAAALAADCggICAABLAAECggIEgADAAAAAA==.Morgraine:BAAALAADCggICAAAAA==.Mortel:BAAALAADCgcIDgAAAA==.Mouni:BAAALAAECgEIAQAAAA==.Moxej:BAAALAAECgQICAAAAA==.',Mu='Mummaolilith:BAAALAADCggIDgAAAA==.Mur:BAAALAAECgMIBAAAAA==.',My='Mycotoxin:BAAALAADCggIDwAAAA==.Mysteerie:BAAALAAECgEIAgAAAA==.Mysterie:BAAALAAECgIIAwAAAA==.Mythlik:BAAALAADCgcIBwAAAA==.Mythlogic:BAAALAADCggIFwAAAA==.',['Mè']='Mèrciless:BAAALAADCgYIBgAAAA==.',['Mò']='Mòrwenna:BAAALAADCgYIAwAAAA==.',['Mù']='Mùshu:BAAALAAECgQIBQAAAA==.',Na='Naakk:BAAALAAECgUIAgAAAA==.',Ne='Necrobunny:BAAALAAECgQIBQAAAA==.Needcoffee:BAAALAADCgcIDQAAAA==.Neondh:BAAALAAECgIIAgAAAA==.Nettia:BAAALAADCggICAAAAA==.Nev:BAAALAAECgQICAAAAA==.Nevven:BAAALAADCgcIBwAAAA==.',Ni='Nicksdeath:BAAALAADCgYIBgAAAA==.Nickshunter:BAAALAADCgcIBwAAAA==.Nickslock:BAAALAADCgYIBgAAAA==.Nicksmage:BAAALAAECgUICAAAAA==.Nicksshaman:BAAALAADCgQIBgAAAA==.Nightwissh:BAAALAAECgEIAQAAAA==.Nikarius:BAAALAAECgIIAwAAAA==.Nionn:BAAALAADCggIFwAAAA==.Nirazelle:BAAALAAECgMIBQAAAA==.Nitevoker:BAAALAAECgIIAgAAAA==.',No='Nohezi:BAAALAADCgcICgAAAA==.Nokkxd:BAAALAADCggICAAAAA==.Nordalea:BAAALAAECgYIDAAAAA==.Nospheratu:BAAALAADCgcIBwAAAA==.',Nu='Nufhead:BAAALAAECgIIAgAAAA==.Nufhëad:BAAALAADCgMIBAAAAA==.Nufknights:BAAALAADCgIIAgAAAA==.',Ny='Nycemonk:BAAALAAECgIIAgAAAA==.Nyxanna:BAAALAAECgMIBAAAAA==.',['Nû']='Nûfhead:BAAALAADCgMIAgAAAA==.',['Nü']='Nümnüts:BAAALAAECgEIAQAAAA==.',Om='Omegapepega:BAAALAADCgMIAwAAAA==.Omnath:BAAALAADCggIDwAAAA==.',On='Ondwarfi:BAAALAAECgYIDgAAAA==.Onigarou:BAAALAADCgcIDQAAAA==.',Oo='Oospider:BAAALAADCggIFgAAAA==.',Op='Ophearia:BAAALAADCgcICgAAAA==.',Or='Orsbáqra:BAAALAADCggIFgAAAA==.Orthanu:BAAALAAECgIIAgAAAA==.',Ou='Outage:BAAALAAECgEIAQAAAA==.',Oz='Ozzywarlock:BAAALAAECgMIAwAAAA==.',Pa='Paieth:BAAALAAECgMIBQAAAA==.Palewhitekid:BAAALAADCgcICAABLAAECgUIAwADAAAAAA==.Pallado:BAAALAAECgEIAQABLAAECgYIFAAFAGwZAA==.Pallobi:BAAALAADCgUICQAAAA==.Pallycaust:BAAALAADCggIEwABLAAECgYIDAADAAAAAA==.Pallymcbeav:BAAALAAECgYICwAAAA==.Paltriks:BAAALAAECgMIBQAAAA==.Pandi:BAAALAAECgUIBQAAAA==.Panduken:BAAALAADCggIDAAAAA==.',Pe='Pelga:BAAALAADCgUIBQAAAA==.Perameles:BAAALAAECgYIDAAAAA==.',Ph='Phenergen:BAAALAAECgIIAgAAAA==.Phillord:BAAALAAECgEIAQAAAA==.',Pi='Pinchei:BAAALAADCggIEAAAAA==.Pinchiy:BAAALAADCggIBwAAAA==.Pinkclass:BAAALAADCgYIBQAAAA==.',Pr='Predakìng:BAAALAAECgIIAgAAAA==.Predz:BAAALAAECgMIBQAAAA==.Predztor:BAAALAAECgEIAQAAAA==.Prophet:BAAALAADCgcIBwAAAA==.Prophetgenie:BAAALAAECgMIBAAAAA==.',Ps='Psyreq:BAAALAAECgUIAgAAAA==.',Pu='Punkey:BAAALAADCggIEAAAAA==.',Py='Pyrra:BAAALAADCggICAAAAA==.',Qu='Quartquartma:BAAALAAECgIIAgAAAA==.',Ra='Raelana:BAAALAAECgQIBwAAAA==.Raeni:BAAALAAECgUIBwAAAA==.Raque:BAAALAADCgYIBgAAAA==.Ravic:BAAALAAECgIIAQAAAA==.Razeld:BAAALAAECgIIAgAAAA==.Razhun:BAAALAAECgEIAgAAAA==.Razia:BAAALAADCggIFgAAAA==.Razzax:BAAALAADCgYIBgAAAA==.Razzmata:BAAALAAECgYICAAAAA==.',Re='Reapsouls:BAAALAAECgIIAgAAAA==.Reddas:BAAALAADCgYICQAAAA==.Rellianna:BAAALAADCgcIDAAAAA==.Relock:BAAALAAECgMIBQAAAA==.Remaxlynna:BAAALAADCggICAAAAA==.Reportthis:BAAALAAECgMIBAAAAA==.Restik:BAAALAADCgYIBgAAAA==.Rexy:BAAALAAECgYICAAAAA==.Rezïstive:BAAALAAECgEIAQAAAA==.',Ri='Rimara:BAAALAADCggIDAAAAA==.Rinasuzuki:BAAALAAECgYIDgAAAA==.Rishari:BAAALAAECgQIBgAAAA==.Rithrian:BAAALAAECgIIAgAAAA==.',Rj='Rjaý:BAAALAADCggICAAAAA==.Rjstabby:BAABLAAECoEXAAIJAAgIyxqUCQCOAgAJAAgIyxqUCQCOAgAAAA==.',Ro='Roboisk:BAAALAAECgIIAgAAAA==.Rodador:BAAALAADCggICwAAAA==.Rolstein:BAAALAADCgQIBAAAAA==.Rottlee:BAAALAADCgYIDgAAAA==.Rozabella:BAAALAAECgYIDgAAAA==.',Ry='Ryklan:BAAALAADCgcIEAAAAA==.',['Rë']='Rëdylivë:BAAALAADCggIEAAAAA==.',['Rï']='Rïkku:BAAALAADCggICAABLAAECgYICgADAAAAAA==.',Sa='Sadge:BAAALAAECgQIBAAAAA==.Sakuragosa:BAAALAAECgQIBAAAAA==.Sakuraharuno:BAAALAAECgcIEAAAAA==.Sakuranee:BAAALAAECgEIAQAAAA==.Sakuura:BAAALAAECgYICwAAAA==.Saltburn:BAAALAAECgYIDgAAAA==.Sareena:BAAALAADCggIFgAAAA==.Sargash:BAAALAAECggIEgAAAA==.Sarkness:BAAALAAECgUIBwAAAA==.Sataiel:BAAALAADCggICAAAAA==.Savageness:BAAALAAECgYIDQAAAA==.',Sc='Scarbi:BAAALAAECgQIBQAAAA==.Scooty:BAAALAAECgEIAQAAAA==.',Se='Seoho:BAAALAADCgYIBgABLAADCggIFgADAAAAAA==.Sergiowarlok:BAAALAADCgYIBgAAAA==.',Sh='Shadowkain:BAAALAAECgIIAgAAAA==.Shallios:BAAALAAECgQIBgAAAA==.Shamanfruit:BAAALAAECgEIAQAAAA==.Shamannigans:BAAALAAECgIIAgAAAA==.Shambiguous:BAAALAADCgMIAwAAAA==.Shambulance:BAAALAADCggICAAAAA==.Shammble:BAAALAADCggIDgAAAA==.Shawing:BAAALAADCgMIAwAAAA==.Shaydana:BAAALAADCgYIBgABLAADCgcIBwADAAAAAA==.Shaymin:BAAALAAECgEIAQAAAA==.Shaytan:BAAALAAECgEIAgAAAA==.Shazamwombat:BAAALAADCgYIBgAAAA==.Sheogorath:BAAALAAECgYIDwAAAA==.Shibarí:BAAALAADCgcIEAAAAA==.Shiphra:BAAALAAECgIIAgAAAA==.Shnox:BAAALAADCggICAAAAA==.Shocksocks:BAAALAAECgQIBQAAAA==.Shocktopus:BAAALAADCggICAAAAA==.Shouku:BAAALAADCggICQAAAA==.Shouldershot:BAAALAAECgYIDAAAAA==.Shyaiel:BAAALAAECggIEwAAAA==.',Si='Sianien:BAAALAAECgMIBQAAAA==.Sielbi:BAAALAADCggICAAAAA==.Siinatra:BAAALAAECgYIDQAAAA==.Siinatress:BAAALAADCgYICAABLAAECgYIDQADAAAAAA==.Silvanas:BAAALAAECgUIBQAAAA==.Silverstarr:BAAALAAECgEIAQAAAA==.Silverti:BAAALAAECgYICAAAAA==.Sindorth:BAAALAADCggICQAAAA==.Sinnafein:BAAALAADCgcIDQAAAA==.Siohban:BAAALAAECgMIBAABLAAECgMIBAADAAAAAA==.',Sk='Skaalfyre:BAAALAAECgcIDgAAAA==.Skylarsdk:BAAALAADCgYICAAAAA==.',Sl='Slothination:BAAALAAECgYICwAAAA==.',Sn='Snowsnow:BAABLAAECoEWAAIGAAgICh8cCgDhAgAGAAgICh8cCgDhAgAAAA==.',So='Socnirr:BAAALAAECgYICgAAAA==.Soiboii:BAAALAAECgMIBgAAAA==.Sokraxx:BAAALAAECggIEgAAAA==.Sonogal:BAAALAAECgYICQAAAA==.Sonyc:BAAALAAECgYICgAAAA==.Soothhunt:BAAALAADCgcIBwAAAA==.',Sp='Spassvogel:BAAALAAECgEIAQAAAA==.Spinandwin:BAAALAAECgQIBQAAAA==.Sprievodca:BAAALAADCggIFgAAAA==.Spêwt:BAAALAAECggICAAAAA==.',Sq='Squishys:BAAALAADCgcIDgAAAA==.',Ss='Sstormmy:BAAALAAECgYICgAAAA==.',St='Stae:BAAALAAECgMIBwAAAA==.Steelbull:BAAALAAECgQIBQAAAA==.Steelmyth:BAAALAAECgYICQAAAA==.Steeltngri:BAAALAAECgcICgAAAA==.Stringybeef:BAAALAADCggIFAAAAA==.',Sy='Sy:BAAALAAECgcICwAAAA==.Syannas:BAAALAADCggIGAAAAA==.Sycamore:BAAALAAECgYIDgAAAA==.Sydor:BAAALAADCggIGAAAAA==.Sylanthe:BAAALAADCggIFQAAAA==.Syleanta:BAAALAAECgEIAQAAAA==.Sylennia:BAAALAAECgEIAgAAAA==.Sylvaknight:BAAALAAECgEIAQAAAA==.Syperial:BAAALAAECgEIAQABLAAECgYIDAADAAAAAA==.',Sz='Szarni:BAAALAAECgEIAgAAAA==.',['Sê']='Sênsêi:BAAALAADCgYIBwAAAA==.',Ta='Tabbi:BAAALAAECgYICgAAAA==.Tabitrisao:BAAALAAECgYIBwAAAA==.Taehyun:BAAALAADCggIFgAAAA==.Takahashi:BAAALAADCgYIBgAAAA==.Takfu:BAAALAAECgUIBgAAAA==.Tanlequìn:BAAALAAECgMIBgAAAA==.Taridalas:BAAALAAECgIIAwAAAA==.Taroth:BAAALAADCgYICAAAAA==.Taucetid:BAAALAADCggIEAAAAA==.',Te='Tehmonk:BAAALAAECgUICgAAAA==.Teledór:BAAALAADCggIFwAAAA==.Telraena:BAAALAAECgIIAgAAAA==.Tep:BAAALAAECgMIAwAAAA==.Terh:BAAALAADCggIEAAAAA==.Terokkar:BAAALAAECgEIAgAAAA==.Tetsukage:BAAALAADCggIEAAAAA==.',Th='Thecrocodile:BAAALAADCgcIDAAAAA==.Thiea:BAAALAAECgYIDAAAAA==.Thunderpog:BAABLAAECoEXAAIKAAgI7iUEAgBSAwAKAAgI7iUEAgBSAwAAAA==.Thàlia:BAAALAAECgYIDQAAAA==.',Ti='Timepriest:BAAALAADCgEIAQABLAADCgYIBgADAAAAAA==.Tinypi:BAAALAAECgIIAwAAAA==.Tivara:BAAALAADCggIDwAAAA==.',To='Tomthumb:BAAALAADCgcIBwAAAA==.Topshot:BAAALAAECgYICAAAAA==.Torr:BAAALAAECgMIBQAAAA==.Tory:BAAALAADCgcIDgAAAA==.',Tr='Trazer:BAAALAADCgUIBQAAAA==.Treefidy:BAAALAADCgIIAgAAAA==.Treesource:BAAALAAECgEIAQAAAA==.Tribble:BAAALAADCgMIAwAAAA==.Tripdre:BAAALAADCggIDwAAAA==.',Tw='Twentyfour:BAAALAADCggICAAAAA==.Twing:BAAALAADCggICAAAAA==.',Uk='Ukarnus:BAAALAADCgIIAgAAAA==.',Ul='Ulrike:BAAALAAECgYIDgAAAA==.',Un='Unc:BAAALAADCgcIDgAAAA==.Unchained:BAAALAADCggICQAAAA==.Unitofshapes:BAAALAAECgYICgAAAA==.Unitofvision:BAAALAAECgEIAQABLAAECgYICgADAAAAAA==.',Up='Upndown:BAAALAAECgYICAAAAA==.Upngoo:BAAALAADCggICAAAAA==.',Ur='Urog:BAAALAADCggIDQAAAA==.',Va='Valestra:BAAALAADCgYIBgAAAA==.Valestraz:BAAALAADCggICgAAAA==.Vallon:BAAALAAECgcICwAAAA==.Valody:BAAALAADCggICAABLAAFFAIIAwADAAAAAA==.Vanel:BAAALAAECgQIBQAAAA==.Varthele:BAAALAAECgIIAgAAAA==.Varthwind:BAAALAADCggIDAAAAA==.',Ve='Velise:BAAALAAECgIIAwAAAA==.Velvetcure:BAAALAADCggIFgABLAAECgYIDgADAAAAAA==.Vernossiel:BAAALAADCggICAAAAA==.Vexahlia:BAAALAAECgIIBAAAAA==.',Vh='Vhagar:BAAALAAFFAIIAgAAAA==.',Vi='Vilithianna:BAAALAADCgUIBQAAAA==.Vio:BAABLAAECoEXAAILAAgI+SS9AABIAwALAAgI+SS9AABIAwAAAA==.Violicia:BAAALAADCgUIBQAAAA==.Viserys:BAAALAAECgMIBAAAAA==.',Vo='Vodmodmon:BAAALAADCgYIEQAAAA==.Voidblade:BAAALAAECgIIAgAAAA==.',Vu='Vudumon:BAAALAAECgUIBQAAAA==.',Vy='Vylathrius:BAAALAADCggIFQAAAA==.Vyperz:BAAALAADCgYICwAAAA==.Vyprz:BAAALAAECgcIEAAAAA==.',Wa='Wabisabi:BAAALAAECgcICgAAAA==.Wabssjnr:BAABLAAECoEYAAIMAAgIGhrtBQByAgAMAAgIGhrtBQByAgAAAA==.Wabssp:BAAALAAECgYIDAABLAAECggIGAAMABoaAA==.Warllado:BAAALAAECgMIAwABLAAECgYIFAAFAGwZAA==.Warwitch:BAAALAADCgcIBwAAAA==.',We='Weeten:BAAALAADCgcIDgAAAA==.Weiland:BAAALAAECgEIAQAAAA==.',Wh='Whoopsie:BAAALAADCggICAAAAA==.',Wi='Wifetown:BAABLAAECoEXAAINAAcIBg3PIABbAQANAAcIBg3PIABbAQAAAA==.Williwaw:BAAALAADCgQIBAAAAA==.Wiz:BAAALAAECgIIAgAAAA==.',Wo='Wolfflash:BAAALAAECgUIBQAAAA==.Wolfsguard:BAAALAAECggIAgAAAA==.Wolvaren:BAAALAAECgEIAQAAAA==.',Wy='Wytchwyld:BAAALAADCgcIDwAAAA==.',Xa='Xalyndra:BAAALAAECgMIBQAAAA==.Xanastiri:BAAALAADCgEIAQAAAA==.Xanthir:BAAALAADCggIDgAAAA==.Xasra:BAAALAAECgEIAQAAAA==.',Xe='Xelbie:BAAALAAFFAEIAQAAAA==.',Xi='Xintar:BAAALAAECggIBQAAAA==.',Ya='Yannu:BAAALAADCgUIBQAAAA==.',Ye='Yebanned:BAABLAAFFIEFAAIHAAMIoBdwAQD9AAAHAAMIoBdwAQD9AAAAAA==.Yeetcannon:BAAALAAECgcICwAAAA==.Yellowajah:BAAALAADCgcICgAAAA==.',Yi='Yidaki:BAAALAADCgYIBgAAAA==.',Yo='Yogan:BAAALAADCgQIBwAAAA==.',Yt='Ythandor:BAAALAADCgEIAQAAAA==.',Za='Zaabra:BAAALAADCggIFgAAAA==.Zaion:BAAALAADCgYIDwAAAA==.Zaralis:BAAALAADCgcICAAAAA==.Zarino:BAAALAADCgEIAQAAAA==.',Ze='Zealatha:BAAALAAECgYICQAAAA==.Zealis:BAAALAAECgMIBQAAAA==.Zeederp:BAAALAAECgYICgAAAA==.Zeemano:BAAALAAECgEIAgAAAA==.Zeira:BAAALAAECgYICAAAAA==.Zentresh:BAAALAAECgIIAgAAAA==.',Zi='Zippers:BAAALAADCggIDgAAAA==.',Zo='Zoicey:BAAALAAECgYIDgAAAA==.Zolce:BAAALAAECgEIAQABLAAECgYIDgADAAAAAA==.Zonkley:BAAALAAECgEIAQAAAA==.Zorkra:BAAALAADCgcICAAAAA==.',Zu='Zularaik:BAAALAAECgMIBAAAAA==.',Zw='Zwirbel:BAAALAADCgIIAgABLAAECgYIDgADAAAAAA==.',Zy='Zybaxos:BAAALAAECgYIDwAAAA==.',Zz='Zzro:BAAALAADCgcIEgAAAA==.',['Îs']='Îssy:BAAALAAECgMIAwAAAA==.',['Ðø']='Ðøóm:BAAALAADCgIIAwAAAA==.',['Øm']='Ømegoss:BAAALAADCggICAAAAA==.',['Ül']='Ülric:BAAALAADCgQIBAABLAAECgIIAgADAAAAAA==.',['ßr']='ßrum:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end