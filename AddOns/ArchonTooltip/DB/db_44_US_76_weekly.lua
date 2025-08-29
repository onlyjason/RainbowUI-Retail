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
 local lookup = {'Unknown-Unknown','Paladin-Protection','Mage-Frost','Priest-Shadow','Shaman-Restoration','Monk-Mistweaver','Warrior-Fury','Paladin-Retribution','DeathKnight-Unholy','Shaman-Enhancement','Shaman-Elemental',}; local provider = {region='US',realm='Draka',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Aberaht:BAAALAAECgYICQAAAA==.Absolution:BAAALAAECgMIBAAAAA==.',Ae='Aenastian:BAAALAADCggICAABLAAECgQICwABAAAAAA==.',Ah='Ahnubas:BAAALAAECgIIAgAAAA==.',Ak='Akaa:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',Al='Aleannia:BAAALAADCggIEwAAAA==.Alestria:BAAALAADCgcICQAAAA==.Alysae:BAAALAAECggIEgAAAA==.Alysaie:BAAALAAECgIIBAAAAA==.',An='Animusvox:BAAALAAECgUIBQAAAA==.Anniebot:BAAALAADCgYIDQAAAA==.',Ap='Apollodruid:BAAALAADCgcIBwAAAA==.Apythia:BAAALAAECgIIAgAAAA==.',Ar='Arbyss:BAAALAADCgYICwAAAA==.Arcan:BAAALAAECgEIAQAAAA==.Arthanau:BAAALAAECgMIAwAAAA==.',As='Asherox:BAAALAAECgMIAwAAAA==.Astraeä:BAAALAAECgMIBAAAAA==.Astrocakes:BAAALAAECgIIAgABLAAECgMIBAABAAAAAA==.Astríd:BAAALAADCgcICgAAAA==.Asuma:BAAALAADCgYIAQAAAA==.',At='Athenä:BAABLAAECoEdAAICAAgIiA3ODQB8AQACAAgIiA3ODQB8AQAAAA==.',Az='Azazelx:BAAALAADCgMIAwAAAA==.',Ba='Baridion:BAAALAAECgMIAwAAAA==.Basanda:BAAALAADCggIDwABLAAECgYIDAABAAAAAA==.',Be='Bearlydrag:BAAALAADCgEIAQAAAA==.Benjinana:BAAALAADCggIGAAAAA==.Berahla:BAAALAADCgcIDgAAAA==.Betterthanu:BAAALAADCgcICwAAAA==.',Bk='Bkrispy:BAAALAAECgMIBAAAAA==.Bkunstopabl:BAAALAAECgYIDwAAAA==.Bkunstoppabl:BAAALAADCgYIBgAAAA==.',Bl='Blackhebrew:BAAALAADCgEIAQAAAA==.',Bo='Bohde:BAAALAAECgIIAgAAAA==.Bombjovi:BAAALAAECgMIBQAAAA==.Bonny:BAAALAADCgMIAwAAAA==.Boomjob:BAAALAAECgUIDwAAAA==.',Bt='Btrflyprncss:BAAALAADCggICAAAAA==.',Bu='Budde:BAAALAADCgYIDAAAAA==.Buddie:BAAALAADCgYICQAAAA==.Buffaloseven:BAAALAAECgEIAQABLAAECggIGwADAHYgAA==.',['Bë']='Bëlha:BAAALAADCggICQAAAA==.',Ca='Carm:BAAALAADCgYIEgAAAA==.Carslyle:BAAALAAECgMIBAAAAA==.',Ce='Cellifalas:BAAALAAECgMIAwAAAA==.',Ch='Chardaney:BAAALAADCgYIBgAAAA==.Cherryontop:BAAALAAECgEIAQAAAA==.Chronics:BAAALAAECgYIDwAAAA==.',Cl='Clydde:BAAALAADCgcIBwAAAA==.',Co='Coladraco:BAAALAADCggIEAAAAA==.Colandros:BAAALAADCgcIBwAAAA==.Colaux:BAAALAADCgYIBgAAAA==.Coldspace:BAAALAAECgYIDwAAAA==.',Cr='Crestfallen:BAAALAAECgMIBAAAAA==.Crimes:BAAALAADCgMIAwAAAA==.',Da='Dankzor:BAAALAADCggICAAAAA==.Darthrevan:BAAALAAECgMIAwAAAA==.Dasharnkal:BAAALAAECgMIBgAAAA==.',De='Deadlocke:BAAALAADCgcIBwAAAA==.Deadpump:BAAALAAECgUICAAAAA==.Demon:BAAALAADCgMIAwAAAA==.Demonforged:BAAALAADCggIBwAAAA==.Denzvicc:BAAALAADCgcIDAAAAA==.Dergigg:BAAALAAECgQIBwAAAA==.Devilah:BAAALAADCgYICgAAAA==.',Di='Diascia:BAAALAADCgYIBwAAAA==.Digifoxx:BAAALAADCgUIBQABLAADCgcIBwABAAAAAA==.Disciplined:BAAALAAECgIIAgAAAA==.Dispérsion:BAABLAAECoEWAAIEAAgICyQ9BQAJAwAEAAgICyQ9BQAJAwAAAA==.',Do='Doirla:BAAALAAECgYICQAAAA==.',Dr='Dragdrake:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.Dragnas:BAAALAAECgEIAgAAAA==.Dramakiller:BAAALAADCgYICwAAAA==.Drcornbread:BAAALAADCggIGAAAAA==.Drdreggs:BAAALAAECgEIAQAAAA==.',Du='Dumptruckk:BAAALAAECgQIBQAAAA==.',Ed='Edvardo:BAAALAADCgEIAQAAAA==.',El='Elastar:BAAALAAECgYICQAAAA==.Elizaveto:BAAALAADCggICQAAAA==.Ellimist:BAEBLAAECoEWAAIFAAgIFiQwAQA0AwAFAAgIFiQwAQA0AwAAAA==.Elsan:BAAALAADCggICAAAAA==.Elí:BAAALAAECgMIAwAAAA==.',En='Enoeht:BAAALAAECgEIAQAAAA==.',Er='Erazar:BAAALAAECgQIBQAAAA==.Erickk:BAAALAAECgYIDQAAAA==.',Es='Essense:BAAALAAECgYIBgAAAA==.',Ex='Exodari:BAAALAAECgYICQAAAA==.',Fe='Fel:BAAALAAECgYIDwAAAA==.',Fi='Fiddich:BAAALAADCgcIBwAAAA==.Fillthy:BAABLAAECoEcAAIGAAgIICMaAgD/AgAGAAgIICMaAgD/AgAAAA==.Fiora:BAAALAAECgMIAwAAAA==.Fizban:BAAALAAECgMIBgAAAA==.',Fl='Flacitaone:BAAALAADCgMIAwAAAA==.Flappybird:BAAALAAECgMIBAAAAA==.Fleshanblood:BAAALAADCgUIBQAAAA==.',Ga='Gadogear:BAAALAAECgEIAgAAAA==.Gameoverx:BAAALAAECgIIAwAAAA==.',Ge='Gelen:BAAALAAFFAEIAQAAAA==.Genicide:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.',Gf='Gfr:BAAALAADCgcIDgAAAA==.',Go='Goatcheeze:BAAALAAECgQIBQAAAA==.Goatylocks:BAAALAAECgMIBQAAAA==.Goldenchild:BAAALAADCgMIAwABLAAECgMIBAABAAAAAA==.',Gr='Grampa:BAAALAAECgMIBgAAAA==.Greentrooper:BAAALAADCgcIBwABLAADCggIDQABAAAAAA==.',Gu='Gulen:BAAALAADCggIDwAAAA==.',['Gí']='Gíga:BAAALAADCgYIBgAAAA==.',Ha='Hanhaine:BAAALAAECgQIBgAAAA==.Harryballsak:BAAALAAECggIBwAAAA==.Havanerita:BAAALAADCgEIAQAAAA==.Hayward:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',He='Hellenkeller:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Heloisa:BAAALAAECgMIBgAAAA==.Henshin:BAAALAAECgYIDwAAAA==.',Hi='Hilikussy:BAAALAADCggICAAAAA==.',Ho='Holymolle:BAAALAAECgMIBwAAAA==.',Hu='Hukleberry:BAAALAADCgUIBQAAAA==.',Ic='Icyowneege:BAAALAAECgQIBQABLAAECggIGwAHAOMhAA==.',Il='Illie:BAAALAAECgYICQAAAA==.',Im='Imasmallmage:BAAALAADCggICAAAAA==.Imyourpapi:BAAALAADCgYIBgAAAA==.',In='Infection:BAAALAADCgcIBwAAAA==.Intoodragons:BAAALAAECgYIDwAAAA==.Intubate:BAAALAADCggIFwAAAA==.',Io='Ionzz:BAAALAAECgYICwAAAA==.',Ir='Iroann:BAAALAAECgYICwAAAA==.',Is='Isaded:BAAALAAECgYIDwAAAA==.Isawarriorr:BAAALAADCggICQAAAA==.Ish:BAAALAAECgMIBQAAAA==.Ishmael:BAAALAAECggIEgAAAA==.',Ja='Jaicu:BAAALAAECgQIBAAAAA==.Jasher:BAAALAAECgIIAwAAAA==.',Jc='Jckie:BAAALAADCgUIBQAAAA==.',Je='Jet:BAAALAAECgYICQAAAA==.',Jh='Jhet:BAAALAADCgcIDAAAAA==.',Ju='Julthaenia:BAAALAADCgcIDQABLAAECgQICwABAAAAAA==.',Ka='Kaeldon:BAAALAADCgcICAAAAA==.Kagebushin:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Kalindari:BAAALAAECgIIBAAAAA==.Karynos:BAAALAAECgYICQAAAA==.',Ke='Kejin:BAAALAAECgIIAgAAAA==.',Ki='Kilie:BAAALAADCgYIBgAAAA==.Kimshi:BAAALAADCgcIBwAAAA==.Kirintore:BAAALAADCggIDgAAAA==.',Ko='Konspiracy:BAAALAAECgMIAwAAAA==.Konvict:BAAALAADCggICAABLAAECgQIBAABAAAAAA==.',Kr='Kryph:BAAALAAECgMIAwAAAA==.',['Kä']='Kämpfer:BAAALAADCgMIBQABLAAECgMIBAABAAAAAA==.',La='Lafiel:BAAALAAECgYICQAAAA==.Lampent:BAAALAAECgMIAwAAAA==.Lazeras:BAAALAAECgMIBgAAAA==.',Le='Lefay:BAAALAADCgcIEgAAAA==.Letsgetwet:BAAALAADCggICQAAAA==.',Li='Lilcita:BAAALAAECgEIAQAAAA==.Liquorsnake:BAAALAADCgcIBwAAAA==.Lirralina:BAAALAADCgEIAQAAAA==.Liscyra:BAAALAADCgcIBwAAAA==.Lithiana:BAAALAAECgMIAwAAAA==.Littleslay:BAAALAADCgcIBwAAAA==.',Lo='Lockaflockå:BAAALAADCgMIAwAAAA==.Locke:BAAALAADCgUIBQAAAA==.Lookylooky:BAAALAADCgEIAQAAAA==.Lozmoji:BAAALAADCggICwABLAAECgQIBgABAAAAAA==.',Lu='Lune:BAAALAADCgMIBQAAAA==.Luxtyrannica:BAAALAAECgQIBAAAAA==.',Ly='Lysandria:BAAALAAECgYIDAAAAA==.',Ma='Marluxia:BAAALAAECggIEgAAAA==.Mayu:BAAALAADCgYIBgAAAA==.',Me='Medion:BAAALAAECgYIDAAAAA==.Meglana:BAAALAADCggIDwAAAA==.Mehpisto:BAAALAADCgUIBQAAAA==.Meristem:BAAALAAECgMIAwAAAA==.Meryle:BAAALAAECgYIDAAAAA==.',Mi='Mikemelrose:BAAALAAECgUICAAAAA==.',Mo='Moegu:BAAALAAECgIIAgAAAA==.Mondgrille:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.Moonbounds:BAABLAAECoEXAAIFAAgI0h9SBADUAgAFAAgI0h9SBADUAgAAAA==.Moonlights:BAAALAAECgMIBwABLAAECggIFwAFANIfAA==.Mooseolini:BAAALAADCggICAAAAA==.Mousechief:BAAALAAECgIIAgAAAA==.Moxxzi:BAAALAADCgMIAwAAAA==.',Mu='Muhfookinbak:BAAALAAECgMIBQAAAA==.',Na='Naksu:BAAALAADCggICAAAAA==.Navaljuices:BAAALAAECgMIAwAAAA==.',Ne='Neao:BAAALAAECgUIBQAAAA==.Neifeb:BAAALAAECgMIBAAAAA==.',Ni='Ninh:BAAALAAECgYIDwAAAA==.',No='Noblehand:BAAALAADCggICQAAAA==.Notsodemon:BAAALAAECgUIBQAAAA==.Notsoshaman:BAAALAAECgcIDwAAAA==.',Ny='Nythrakor:BAAALAADCgMIAwAAAA==.Nyyia:BAAALAAECgMIAwAAAA==.',['Nó']='Nóoble:BAAALAADCggICAAAAA==.',Ob='Obvinotagirl:BAAALAAECgYIEAAAAA==.',Od='Odinheåthen:BAAALAAECgIIAgAAAA==.',Ok='Okathra:BAAALAADCgcIBwABLAAECgQICAABAAAAAA==.',Om='Ommaar:BAAALAAECgYIDQAAAA==.',On='Onebadmutha:BAAALAAECgMIBQAAAA==.Ontop:BAAALAAECgYIDwAAAA==.',Or='Orasa:BAAALAADCggICAAAAA==.',Ow='Owneege:BAABLAAECoEbAAIHAAgI4yHDBQAQAwAHAAgI4yHDBQAQAwAAAA==.',Pa='Paapaa:BAAALAADCgYIBgAAAA==.Pallinar:BAAALAAECgIIAgAAAA==.Pallypump:BAAALAADCgcIDgABLAAECgUICAABAAAAAA==.Pasquale:BAAALAADCgYIDgAAAA==.',Pe='Pebbles:BAABLAAECoEbAAIIAAgI1RScHAAYAgAIAAgI1RScHAAYAgAAAA==.Pesty:BAAALAAECgMIBAAAAA==.',Ph='Phodeath:BAAALAADCgcIBwAAAA==.',Pi='Pickletts:BAAALAAECgYICwAAAA==.',Pl='Plaguerott:BAAALAAECgEIAQAAAA==.',Po='Polydh:BAAALAAECgYIDAAAAA==.Poobah:BAAALAAECgMIBAAAAA==.Popscotch:BAAALAAECgYIDAAAAA==.Pottra:BAAALAADCgUICQAAAA==.Pouffant:BAAALAAECgQIBQAAAA==.',Pr='Preperationh:BAAALAAECgEIAQAAAA==.Priestdeaus:BAAALAAECgMIBgAAAA==.Probemycrit:BAAALAADCgUIBQAAAA==.',Pu='Putinfree:BAAALAADCggICAAAAA==.',Pw='Pwnjitsu:BAAALAAECgYICwAAAA==.',Py='Pyrothermia:BAABLAAECoEbAAIDAAgIdiAiBADCAgADAAgIdiAiBADCAgAAAA==.',Qu='Quinlekpr:BAAALAAECgMIBQAAAA==.',Ra='Ragnaros:BAAALAADCgUIBQABLAAECggIGwAJAGAmAA==.Rakugan:BAAALAADCgYICwAAAA==.Rawhoof:BAAALAAECgYIDwAAAA==.Razak:BAAALAAECgQICAAAAA==.',Re='Redtiger:BAAALAADCgcIBwAAAA==.Renisa:BAAALAAECgYICQAAAA==.Retman:BAAALAAECgYICAAAAA==.Retspoon:BAAALAADCggICAAAAA==.Revculter:BAAALAADCggICAAAAA==.Rexoro:BAAALAAECgUIBgAAAA==.Reyne:BAAALAADCggICAABLAAECggIEgABAAAAAA==.',Ro='Roccot:BAAALAAECgYICAAAAA==.Rocknstone:BAAALAAECgQIBAAAAA==.Rotjaw:BAAALAADCggICwAAAA==.',['Rè']='Rèjuva:BAAALAAECgYICwAAAA==.',['Rô']='Rônnin:BAAALAADCgcIBwAAAA==.',Sa='San:BAAALAAECgYIDwAAAA==.Sanyakulak:BAABLAAECoEVAAMCAAgIcBW1CADyAQACAAgIcBW1CADyAQAIAAMI8AXUaACWAAAAAA==.Sarneth:BAAALAADCggIDwAAAA==.',Sc='Scalycat:BAAALAAECgYIDQAAAA==.Scarybear:BAAALAADCgcIDQABLAAECgIIAwABAAAAAA==.',Se='Selvagem:BAAALAADCgMIAwAAAA==.Senate:BAAALAAECgEIAQAAAA==.',Sh='Shabambalam:BAAALAAECgMIAwAAAA==.Shablaam:BAAALAAECgQIBQAAAA==.Shadowbear:BAAALAAECgIIAwAAAA==.Shamiepower:BAAALAADCgQIBAAAAA==.Shiftfaced:BAAALAADCgcIBwAAAA==.Shiuye:BAAALAADCgMIAwAAAA==.Shocklocke:BAAALAADCgQIBAAAAA==.',Si='Silverocean:BAAALAAECgYICQAAAA==.',Sk='Skelli:BAEALAAECgEIAQABLAAECggIFgAFABYkAA==.Skindred:BAAALAADCgQIBAAAAA==.Skittlez:BAAALAAECgYIDAAAAA==.Skulldog:BAAALAADCggIDQAAAA==.',Sm='Smallz:BAAALAADCgUIBQABLAAECgMIBgABAAAAAA==.',Sn='Snooptrogg:BAAALAAECgMIBAAAAA==.',So='Soldiah:BAAALAAECgMIAwAAAA==.Souljax:BAAALAADCggIDwAAAA==.Soulsquisher:BAAALAADCgcIBwAAAA==.',Sp='Spacelaser:BAAALAADCgYIDAAAAA==.Spiriel:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.Splyff:BAAALAADCgcIBwAAAA==.',Sq='Sqwurl:BAAALAAECgUICgAAAA==.',St='Stabbydragon:BAAALAAECgMIAwAAAA==.Stormfist:BAAALAAECgIIAgAAAA==.Stormhaven:BAAALAADCgcIDQAAAA==.Stormone:BAAALAADCgYIBgAAAA==.Stormriders:BAAALAAECgEIAQAAAA==.Stouty:BAAALAADCgQIBAAAAA==.',Sw='Sweetscass:BAAALAADCgQICAAAAA==.Swisscheese:BAAALAADCggIDAABLAAECgMIBQABAAAAAA==.Swmeoekde:BAAALAAECgIIAgAAAA==.',Ta='Talithiya:BAAALAAECgQIBQAAAA==.',Te='Terragosa:BAAALAAECgMIAwAAAA==.Tetchybono:BAAALAADCgcIBwAAAA==.',Th='Thade:BAAALAAECgYICAAAAA==.Thaeleon:BAAALAAECgMIAwABLAAECggIEgABAAAAAA==.Theory:BAAALAADCggIDgAAAA==.Thirinis:BAAALAAECgIIAgAAAA==.Thornbeast:BAAALAAECgIIAgAAAA==.Throwspurple:BAAALAAECgYIDwAAAA==.Thundergirl:BAAALAADCggICwAAAA==.',Ti='Tictacc:BAAALAADCgQIBwAAAA==.Tigani:BAAALAADCgYICgAAAA==.Timster:BAAALAAECgYIDgAAAA==.Tinkelf:BAAALAADCgcIDAAAAA==.Tinstey:BAAALAADCggIBgAAAA==.',To='Toetums:BAAALAADCgQICAAAAA==.Tosstheboys:BAAALAAECgMIBAAAAA==.',Tr='Traesdyne:BAAALAADCgcICgAAAA==.Tricon:BAAALAADCgcIBwAAAA==.Trr:BAAALAAECggIEwAAAA==.',Ty='Tyrlidd:BAAALAAECgMIAwAAAA==.',Un='Undeadalus:BAAALAADCgIIAwAAAA==.',Ur='Uricash:BAAALAADCgYIBgAAAA==.Urrax:BAAALAAECgMIAwAAAA==.Urzual:BAAALAAECgMIBAAAAA==.',Uu='Uuna:BAAALAADCggICAABLAAECgMIBgABAAAAAA==.',Va='Valerin:BAAALAADCgUIAwAAAA==.Vandreynna:BAAALAAECgQICwAAAA==.',Ve='Velaris:BAAALAADCggIEgAAAA==.Velasha:BAAALAADCggICQAAAA==.Verbrennen:BAAALAAECgMIBAAAAA==.Veritâ:BAAALAAECgQIBQAAAA==.',Vi='Viviann:BAAALAAECgYICQAAAA==.',Vr='Vrakal:BAAALAAECgMIAwAAAA==.',['Vé']='Vénus:BAAALAADCgEIAQAAAA==.',Wa='Warlo:BAAALAADCggICAABLAAECgcIDwABAAAAAA==.Warraxe:BAAALAADCgcIEwAAAA==.Warriorballz:BAAALAAECgMIBAAAAA==.',We='Weilyn:BAAALAADCgYICwAAAA==.Wellgreck:BAAALAAECgYIDAAAAA==.',Wi='Wickathy:BAAALAAECgYICgAAAA==.Withering:BAAALAADCggIDQAAAA==.',Wo='Worstdps:BAAALAADCgcIBwAAAA==.',Wu='Wuldorr:BAAALAAECgcIDgAAAA==.',Xa='Xaos:BAAALAAECgMICAAAAA==.',Xt='Xtrafel:BAAALAADCggICAAAAA==.',Xy='Xype:BAAALAAECggIAwAAAA==.',Yn='Ynlib:BAAALAAECgYICQABLAAFFAIIAgABAAAAAA==.',Yv='Yvvee:BAAALAAECgIIBAAAAA==.',Za='Zapdôs:BAAALAADCggIDgAAAA==.',Ze='Zephyris:BAABLAAECoEYAAMKAAgI+iKxAAA3AwAKAAgI+iKxAAA3AwALAAEIHBUkTQBFAAAAAA==.',Zr='Zryda:BAAALAADCgcIBwAAAA==.',Zw='Zweimal:BAAALAAECgYICQAAAA==.',['Äz']='Äzrael:BAAALAAECgMIBQAAAA==.',['Çr']='Çréwüsæðèr:BAAALAADCgcIBwAAAA==.',['Ðo']='Ðollz:BAAALAAECgQIBQAAAA==.',['Ðî']='Ðîgîfox:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end