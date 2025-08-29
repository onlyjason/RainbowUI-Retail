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
 local lookup = {'Unknown-Unknown','Warrior-Fury',}; local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aanne:BAAALAAECgYICgAAAA==.',Ab='Abacadaver:BAAALAADCgMIAwAAAA==.',Ac='Aceshot:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.',Ae='Aeani:BAAALAADCgcIDQAAAA==.Aethwyn:BAAALAADCgUICAAAAA==.',Ah='Ahantasha:BAAALAADCgIIAgAAAA==.Ahnkala:BAAALAAECgEIAQAAAA==.',Ai='Ailiia:BAAALAADCgcIBwAAAA==.',Ak='Akamagnum:BAAALAADCgMIAwAAAA==.',Al='Aleinjochas:BAAALAAECgUIDAAAAA==.Allupcreepy:BAAALAAECgQIBAAAAA==.',Am='Ambewlance:BAAALAAECgEIAQAAAA==.Amethystra:BAAALAAECgQIBwAAAA==.',An='Ansem:BAAALAADCgMIAwAAAA==.Antediluvian:BAAALAAECgUIBQAAAA==.Anthesis:BAAALAAECgYICAAAAA==.',Ap='Apep:BAAALAADCggIEAAAAA==.',Ar='Arcanea:BAAALAADCgcIDAAAAA==.Arcanys:BAAALAAECgEIAQABLAAECgYIDgABAAAAAA==.Armypartay:BAAALAAECgEIAQAAAA==.Artemys:BAAALAAECggIEgAAAA==.',As='Ashowyn:BAAALAAECgUIDAAAAA==.Asketill:BAAALAAECgYICQAAAA==.Asmodee:BAAALAADCggICAAAAA==.Assyriän:BAAALAAECgMIBQAAAA==.',Av='Avly:BAAALAADCggIFQAAAA==.',Az='Azbiné:BAAALAADCggICAAAAA==.Azimortem:BAAALAADCgUICQAAAA==.',Ba='Baatou:BAAALAAECgIIAgAAAA==.Batharel:BAAALAAECgMIBAAAAA==.Baulrock:BAAALAAECgMIBAAAAA==.',Be='Bearen:BAAALAAECgUIDAAAAA==.Beckett:BAAALAAECgMIBAAAAA==.Beertrain:BAAALAAECgUIDAAAAA==.Beesechurger:BAAALAAECgMIBQAAAA==.Bellezza:BAAALAAECgYICgAAAA==.Beornir:BAAALAAECgEIAQAAAA==.',Bh='Bhikku:BAAALAADCgcIBwABLAAECgIIBAABAAAAAA==.Bhilly:BAAALAADCgMIAwAAAA==.',Bj='Bjornn:BAAALAAECgMIBQAAAA==.',Bl='Blarpsniff:BAAALAADCgMIAwAAAA==.Blight:BAAALAADCgcIBgAAAA==.Bloodeagle:BAAALAAECgYIBgAAAA==.Bloodstream:BAAALAADCggICAABLAADCggIEQABAAAAAA==.Bludgen:BAAALAADCggIEQAAAA==.',Bo='Bobitt:BAAALAAECgEIAQAAAA==.Boddyknocker:BAAALAAECgQIBwAAAA==.Bofadeezhelz:BAAALAAECgUICAAAAA==.Boinkusan:BAAALAAECgUICgAAAA==.Bolthar:BAAALAAECgMIAwAAAA==.Bombpopp:BAAALAADCgEIAQAAAA==.Bonkler:BAAALAAECgMIBQAAAA==.Boomtoon:BAAALAADCgYIBgAAAA==.Boonerichard:BAAALAADCggIDwAAAA==.Boyardees:BAAALAAECgMIBAAAAA==.',Br='Branwin:BAAALAADCgMIAwAAAA==.Braver:BAAALAAECgYIEQAAAA==.Braverwar:BAAALAADCgcIBwAAAA==.Brayedine:BAAALAAECgEIAgAAAA==.Breekachu:BAAALAAECgIIAwAAAA==.Brostep:BAAALAADCgMIAwAAAA==.Brutimus:BAAALAADCgQIBAAAAA==.',Bu='Bugfog:BAAALAADCgcIBQAAAA==.',Ca='Camandah:BAAALAADCgcIEwAAAA==.Canman:BAAALAADCgYIBgAAAA==.Caranina:BAAALAADCgMIAwAAAA==.Cardeller:BAAALAADCgcICwAAAA==.Cassean:BAAALAADCggICQAAAA==.Cassei:BAAALAAECgcICwAAAA==.Cassiell:BAAALAADCgMIAwAAAA==.',Ce='Celenia:BAAALAADCggIDwAAAA==.',Ch='Charmless:BAAALAADCgcIBAABLAAECgYICgABAAAAAA==.Charzilla:BAAALAADCgcIBwAAAA==.Chavirst:BAAALAADCgIIAgAAAA==.Cheetopaly:BAAALAAECgMIBgAAAA==.Chinchulín:BAAALAADCgEIAQAAAA==.Chìgusa:BAAALAAECgUIDAAAAA==.',Cl='Clumonk:BAAALAAECgMIBQAAAA==.',Co='Codiakmage:BAAALAAECgQIBQAAAA==.Codiakmonk:BAAALAADCggICAAAAA==.Constanna:BAAALAAECgIIAwAAAA==.Corellon:BAAALAAECgQIBwAAAA==.Corvincorvae:BAAALAAECgQIBQAAAA==.',Cr='Cratoz:BAAALAAECgIIAgAAAA==.Crixhs:BAAALAADCggIEQAAAA==.Cronatick:BAAALAADCgIIAgAAAA==.',Cu='Curse:BAAALAADCgYIBwAAAA==.',Cy='Cyndrine:BAAALAAECgcIDAAAAA==.Cynex:BAAALAAECggICAAAAA==.',Da='Dadipps:BAAALAAECgMIAwAAAA==.Dagnei:BAAALAAECgEIAQAAAA==.Daltina:BAAALAAECgMIBQAAAA==.Dareael:BAAALAADCggIEAAAAA==.Daros:BAAALAADCgcIBwAAAA==.',De='Deadnite:BAAALAAECgMIBQAAAA==.Deathpuma:BAAALAAECgYICgAAAA==.Deathrowe:BAAALAAECgMIBAAAAA==.Dekaied:BAAALAAECgMIAwAAAA==.Demothemo:BAAALAADCggIEQAAAA==.Demítrá:BAAALAAECgcIDQAAAA==.Denorek:BAAALAAECgEIAQAAAA==.Derca:BAAALAADCgcICgAAAA==.Dercadin:BAAALAADCgEIAQAAAA==.Devain:BAAALAADCggICAAAAA==.Devbear:BAAALAADCgYIBgAAAA==.Deveren:BAAALAADCgEIAQAAAA==.Devthor:BAAALAADCgcICgAAAA==.',Di='Diazz:BAAALAADCggIDgAAAA==.Diminish:BAAALAAECgMIBAAAAA==.Dirus:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Disease:BAAALAAECgQIBQAAAA==.',Do='Docksaints:BAAALAADCgUIBQAAAA==.Donlazul:BAAALAAECgMIAwAAAA==.Dotdotdeath:BAAALAADCgcIBwAAAA==.',Dr='Draconoth:BAAALAAECgMIBAAAAA==.Draczhul:BAAALAAECgMIBQAAAA==.Draka:BAAALAAECgYIBgAAAA==.Dranddrand:BAAALAAECgcIDAAAAA==.Drowa:BAAALAAECgQIBgAAAA==.',Du='Dungard:BAAALAAECgYICgAAAA==.',Dy='Dyami:BAAALAAECgEIAQAAAA==.',['Dè']='Dèadèyè:BAAALAADCgEIAQAAAA==.',['Dé']='Délight:BAAALAAECgMIBQAAAA==.',Ea='Eatmorechkn:BAAALAAECgUICgAAAA==.',Ed='Edgli:BAAALAAECgEIAQAAAA==.',Ee='Eellonwy:BAAALAAECgEIAQAAAA==.Eemerald:BAAALAADCggIDwAAAA==.',Eg='Egna:BAAALAAECgQIBQAAAA==.',El='Eldiablo:BAAALAADCgcIBwAAAA==.Elizaa:BAAALAAECgYICAAAAA==.Elvirardrake:BAAALAADCgcIBwAAAA==.',En='Enidd:BAAALAADCgYIBgAAAA==.',Ep='Epsteinlist:BAAALAAECgQICQAAAA==.',Ev='Evildean:BAAALAAECgYICQAAAA==.Evnstar:BAAALAADCgcIBwAAAA==.',Ey='Eyllian:BAAALAAECgMIBQAAAA==.',Fa='Falkór:BAAALAAECgEIAQAAAA==.',Fe='Feebleheart:BAAALAADCgcICAAAAA==.Feelinbetter:BAAALAADCgYIBgAAAA==.Fenrigaar:BAAALAAECgIIAgAAAA==.Feymagic:BAAALAADCgcIBwAAAA==.',Fi='Fi:BAAALAADCggIDgAAAA==.Fillin:BAAALAADCgYIBgAAAA==.',Fo='Formula:BAAALAAECgUIBQAAAA==.Forsakenly:BAAALAAECgMIBQAAAA==.',Fr='Freshstart:BAAALAAECgIIAwAAAA==.Frostmage:BAAALAAECgQIBwAAAA==.',Fu='Fulgure:BAAALAAECgUIDAAAAA==.Furbucket:BAAALAADCggICAAAAA==.Futon:BAAALAAECgYICgAAAA==.',Fy='Fylerz:BAAALAADCgcIBwAAAA==.',Ga='Gagoogamesh:BAAALAAECgYIBgAAAA==.Galebb:BAAALAADCgcICgAAAA==.',Go='Gothik:BAAALAAECgYICQAAAA==.Goyahokasinj:BAAALAADCgYICAAAAA==.',Gr='Grayshock:BAAALAADCgcIBwAAAA==.Graysun:BAAALAADCgEIAQAAAA==.Griannee:BAAALAAECgMIBQAAAA==.Griselda:BAAALAADCgYIBgABLAAECgMIBAABAAAAAA==.Grismistea:BAAALAAECgMIBAAAAA==.',Gu='Guidance:BAAALAADCgIIAgAAAA==.Guldannielle:BAAALAAECgMIBQAAAA==.Gusmo:BAAALAADCgIIAgAAAA==.',['Gâ']='Gânk:BAAALAAECgUICgAAAA==.',Ha='Happytissue:BAAALAADCggICQABLAAECgUICwABAAAAAA==.Hardrin:BAAALAAECgYIBgAAAA==.',He='Heavensbliss:BAAALAADCgQIBwABLAAECgQIBwABAAAAAA==.Heriel:BAAALAAECgIIAgABLAAECgIIBAABAAAAAA==.',Hi='Hinatachan:BAAALAADCgcIBwAAAA==.',Ho='Horge:BAAALAAECgUIBQAAAA==.Hoûdini:BAAALAAECgUIBQAAAA==.',Hu='Hughhoofner:BAAALAAECgUICwAAAA==.Humphrees:BAAALAAECgQIBwAAAA==.Huntmnk:BAAALAAECgIIAwAAAA==.',Hy='Hydros:BAAALAAECgEIAQAAAA==.Hyuyo:BAAALAADCgQIBAAAAA==.',['Hà']='Hàtos:BAAALAAECgcICAAAAA==.',Ic='Icesus:BAAALAADCgYIBgAAAA==.',Id='Idot:BAAALAADCgIIAgAAAA==.',Ig='Iguana:BAAALAAECgMIBAAAAA==.',Il='Iliane:BAAALAAECgEIAQAAAA==.',Im='Imatsu:BAAALAADCgcIBwAAAA==.',In='Invissibill:BAAALAAECgQIBgAAAA==.',Io='Iohma:BAAALAADCgMIAwAAAA==.',It='Itsbillymays:BAAALAADCgEIAQAAAA==.',Iv='Ivanã:BAAALAAECgQIBwAAAA==.',Ja='Jadestone:BAAALAADCggIDwAAAA==.Jamestown:BAAALAADCggIEQAAAA==.',Je='Jezaabelle:BAAALAADCgcIBwAAAA==.',Jo='Jojokiller:BAAALAADCgcIBwAAAA==.',Ju='Jupitus:BAAALAAECgMIBQAAAA==.Justicecomes:BAAALAAECgYIBgAAAA==.',Ka='Kadangsu:BAAALAAECgUIDAAAAA==.Kalla:BAAALAADCgMIAwAAAA==.Katalania:BAAALAAECgQIBAAAAA==.Kazo:BAAALAADCgUIBQAAAA==.',Ke='Keiwainara:BAAALAAECgMIBQAAAA==.Kenthel:BAAALAAECgMIBQAAAA==.Kenthels:BAAALAAECgEIAQABLAAECgMIBQABAAAAAA==.Kezt:BAAALAADCgcICQAAAA==.',Kh='Khumdahn:BAAALAAECgYICAAAAA==.',Ki='Kikimmn:BAAALAADCgcIEQAAAA==.Killerchop:BAAALAAECgUIBwAAAA==.Kimen:BAAALAAECgMIBAAAAA==.',Ko='Korry:BAAALAADCggIDwAAAA==.Kortinas:BAAALAADCgYIBgAAAA==.Kouhai:BAAALAADCggIDwAAAA==.',Kr='Kreiestar:BAAALAAECgMIBAAAAA==.Krelanllan:BAAALAADCggICAAAAA==.Krilliz:BAAALAADCgcIDQAAAA==.',Ku='Kukui:BAAALAAECggICAAAAA==.',Le='Leche:BAAALAADCgcICAAAAA==.Leenaa:BAAALAAECgYICAAAAA==.Leselda:BAAALAADCgYIBwAAAA==.',Li='Lie:BAAALAAECgUIBQAAAA==.Lihan:BAAALAAECgQIBAAAAA==.Lively:BAAALAADCgMIAQAAAA==.Lizze:BAAALAAECgUICgAAAA==.',Ll='Llihon:BAAALAAECgIIAgAAAA==.',Lo='Lockedtoit:BAAALAADCgcIBwAAAA==.Loverocket:BAAALAAECgQIBwAAAA==.Lowhp:BAAALAADCgEIAQAAAA==.',Lu='Lumna:BAAALAAECgMIBQAAAA==.Luna:BAAALAAECgEIAQAAAA==.',Ly='Lysh:BAAALAAECgYIBgAAAA==.',['Ló']='Lóng:BAAALAAECgIIAgAAAA==.',Ma='Maddawg:BAAALAAECgQIBAAAAA==.Magdaanii:BAAALAADCggICAAAAA==.Magedown:BAAALAAECgUIDAAAAA==.Mageyôulook:BAAALAAECggIEwAAAA==.Manapali:BAAALAADCgQIBAAAAA==.Mangerhotie:BAAALAAECgcIEAAAAA==.Manpumper:BAAALAAECgEIAQAAAA==.Mattdemon:BAAALAAECgYICgAAAA==.Maxadus:BAAALAADCgUIBgAAAA==.Maxvoltage:BAAALAADCgUIBQAAAA==.',Me='Meliowar:BAAALAAECgcIEgAAAA==.Meowlevolent:BAAALAAECgYICgAAAA==.Merrciless:BAAALAAECgMIBAAAAA==.Meru:BAAALAADCgcIDgAAAA==.',Mi='Miradele:BAAALAAECgQIBAAAAA==.Misscleö:BAAALAAECgYICAAAAA==.Mistyvan:BAAALAAECgQIBwAAAA==.',Mo='Moosakka:BAAALAAECgMIBAAAAA==.Moozan:BAAALAADCgQIBAAAAA==.Mopar:BAAALAAECgMIBQAAAA==.',My='Mydin:BAAALAAECgYICQAAAA==.Mystìque:BAAALAADCggICgAAAA==.',Na='Naarias:BAAALAAECgIIAgAAAA==.Nastijiggle:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.',Ne='Newklear:BAAALAADCgYIBgAAAA==.Nexxa:BAAALAAECgMIBQAAAA==.',Ni='Nightshadow:BAAALAAECgQIBgAAAA==.Niqkle:BAAALAAECgYIBgAAAA==.',No='Nohurtscooby:BAAALAADCgYIBgAAAA==.Notmeanzy:BAAALAAECgQIBwAAAA==.',Ns='Nstagatr:BAAALAAECgMIAwAAAA==.',Ny='Nyara:BAAALAAECgYICQAAAA==.Nyralim:BAAALAAECgMIBQAAAA==.Nyxi:BAAALAADCgcIBwAAAA==.',Ob='Obliteration:BAAALAAECgEIAQAAAA==.',Oc='Ocus:BAAALAADCgcIDQAAAA==.',Ok='Okkotsu:BAAALAADCgQIBAAAAA==.',Ol='Olehanna:BAAALAAECgMIBQAAAA==.',On='Onyxtear:BAAALAADCgcIBwAAAA==.Onyxwild:BAAALAADCgcIBwAAAA==.',Op='Opsec:BAAALAAECgYICAAAAA==.',Ou='Out:BAAALAAECgIIAgAAAA==.',Pe='Peachslime:BAEALAAFFAIIBAAAAA==.Peachykeen:BAAALAADCgMIBQAAAA==.Perfectpal:BAAALAAECgUIDAAAAA==.Peri:BAAALAADCgcIDgAAAA==.',Ph='Phasmatis:BAAALAADCgMIAwAAAA==.',Pl='Plágué:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Po='Pork:BAAALAADCgcIBwAAAA==.Pozzi:BAAALAAECgIIAwAAAA==.',Ps='Psuedolus:BAAALAAECgMIBQAAAA==.',Pu='Pulshadow:BAAALAAFFAIIAgAAAA==.Pumah:BAAALAADCgYIBgAAAA==.Putricia:BAAALAAECgEIAQAAAA==.',Py='Pythagoras:BAAALAAECgYICAAAAA==.',Qu='Quiff:BAAALAADCggICAAAAA==.',Ra='Raahhzi:BAAALAAECgMIBQAAAA==.Raamen:BAAALAADCgYIBgAAAA==.Rabano:BAAALAADCgMIAwAAAA==.Raellia:BAAALAAECgQIBwAAAA==.Rajia:BAAALAAECgMIAgAAAA==.Rammalen:BAAALAAECgYIBgAAAA==.Ranes:BAAALAAECgQIBwAAAA==.',Re='Redxelementz:BAAALAAECgUIBwAAAA==.Refreshed:BAAALAADCgMIAwAAAA==.Renasen:BAAALAAECgMIBQAAAA==.Renjin:BAAALAADCgQIAwAAAA==.Reno:BAAALAAECgMIBAAAAA==.Resiretha:BAAALAAECgMIAwAAAA==.Revelynn:BAAALAAECgUICwAAAA==.Revémyna:BAAALAADCgMIBAAAAA==.',Rh='Rhengoku:BAAALAADCgIIAQAAAA==.Rhyssen:BAAALAADCgYIBgAAAA==.',Ri='Riolu:BAAALAADCgQIBAAAAA==.Riz:BAAALAADCgYIBgAAAA==.',Ro='Rotawna:BAAALAADCgcIDgAAAA==.Roxxydh:BAAALAAECgYIBwAAAA==.Roxxye:BAAALAADCggICAAAAA==.',Ru='Ruumis:BAAALAAECgUIDAAAAA==.',Ry='Ryezn:BAAALAADCggICwAAAA==.Rynoh:BAAALAAECgYICQAAAA==.',Sa='Sanguinè:BAAALAAECgIIAgAAAA==.',Sc='Scaleorva:BAAALAAECgMIBAAAAA==.Schnappz:BAAALAAECgMIBAAAAA==.',Se='Seraphìm:BAAALAADCgcICgAAAA==.',Sh='Shadezilla:BAAALAAECgQIBgAAAA==.Shamabahama:BAAALAADCgIIAgAAAA==.Shamagorn:BAAALAAECgIIAgAAAA==.Shamysosa:BAAALAAECgMIBwAAAA==.Shamzulu:BAAALAADCgMIAwAAAA==.Shapeshift:BAAALAADCgYIEAAAAA==.Shhimhiding:BAAALAADCgYIBgAAAA==.Shiftyouup:BAAALAAECgMIAwAAAA==.Shiven:BAAALAADCgYICgAAAA==.Shivin:BAAALAADCgcIDgAAAA==.Shreddem:BAAALAADCggICAAAAA==.Shwillbur:BAAALAAECgQIBwAAAA==.Shádôws:BAAALAAECgMIAwAAAA==.',Si='Sikes:BAAALAAECgMIBAAAAA==.Silverstring:BAAALAADCggIEAAAAA==.Sinergee:BAAALAAECgQIBwAAAA==.Sinona:BAAALAADCgcIBwAAAA==.',Sk='Skinzzey:BAAALAADCgYIBgAAAA==.Skycrush:BAAALAADCgQIBAAAAA==.',Sl='Slingerz:BAAALAAECgYICgAAAA==.Slowmeaux:BAAALAADCgMIAwAAAA==.',Sm='Smiggles:BAAALAAECgEIAQAAAA==.Smoky:BAAALAAECgYIDgAAAA==.',Sn='Snaperhead:BAAALAAECgQIBwAAAA==.Sneekey:BAAALAAECgMIAwAAAA==.',So='Solkar:BAAALAAECgMIAwAAAA==.Sonastii:BAAALAAECgMIAwAAAA==.Soullesslock:BAAALAAECgQIBAAAAA==.',Sp='Spazzchel:BAAALAADCgQIBAAAAA==.Speedyicy:BAAALAAFFAEIAQAAAA==.',St='Stabymcstab:BAAALAADCgMIAwAAAA==.Stahlman:BAAALAAECgQIBwAAAA==.Stalpho:BAAALAAECgUIDAAAAA==.Starkind:BAAALAAECgQIBwAAAA==.Starliner:BAAALAAECgYICgAAAA==.Stompz:BAAALAAECgcIDgAAAA==.Stoutmist:BAAALAADCggICwAAAA==.Stratogos:BAAALAADCgYIBgAAAA==.Sturr:BAAALAADCgIIAgAAAA==.Styrke:BAAALAADCgIIAgAAAA==.',Su='Suurik:BAAALAAECgUIDAAAAA==.Suwah:BAAALAADCggICAAAAA==.',Sy='Sydsween:BAAALAADCggIDQAAAA==.',['Sâ']='Sârgäsm:BAAALAAECggIEgAAAA==.',Ta='Taras:BAABLAAECoEYAAICAAgI4SIHBQAfAwACAAgI4SIHBQAfAwAAAA==.Taraxist:BAAALAAECgYICAAAAA==.Tarcanisdk:BAAALAAECgYIDgAAAA==.Tazergun:BAAALAAECgQIBwAAAA==.',Tc='Tchala:BAAALAAECgIIBAAAAA==.',Te='Teksalor:BAAALAAECgYICAAAAA==.Teth:BAAALAAECgMIBQAAAA==.',Th='Thaine:BAAALAAECgYICgAAAA==.Tharci:BAAALAAECgcIEAAAAA==.Theelvira:BAAALAAECgYIDwAAAA==.Thessali:BAAALAAECgUIDAAAAA==.Theundeadone:BAAALAAECgYIBgAAAA==.Thndrwzrd:BAAALAADCggIDwAAAA==.Thundertaurd:BAAALAADCgQIBAAAAA==.',Ti='Tidepoddk:BAAALAADCggIDgAAAA==.Tidepood:BAAALAADCgMIAwAAAA==.Tinypain:BAAALAAECgEIAQAAAA==.',Tr='Trkhsk:BAAALAADCgIIAgAAAA==.Trujal:BAAALAAECgUICgAAAA==.',Ud='Udderlyquiff:BAAALAAECgQIBQAAAA==.Udderlyslow:BAAALAAECgYIDwAAAA==.',Uv='Uvetus:BAAALAAECgEIAQABLAADCgMIAwABAAAAAA==.',Va='Vaku:BAAALAADCgcICAAAAA==.Valhallarama:BAAALAAECgYICgAAAA==.Vampy:BAAALAAECgIIAgAAAA==.Vannida:BAAALAADCgYICQABLAADCgcIEwABAAAAAA==.',Ve='Velocinips:BAAALAAECgMIBgAAAA==.',Vo='Volde:BAAALAAECgYICAAAAA==.Voodoo:BAAALAADCgMIAwAAAA==.',Vv='Vvander:BAAALAADCgMIAwAAAA==.',Wa='Waffemann:BAAALAAECgMIBQAAAA==.Wangwang:BAAALAAECgEIAQAAAA==.Warlakaflaka:BAAALAADCgcICQAAAA==.Wavemaster:BAAALAADCgcIBgAAAA==.',Wh='Whale:BAAALAAECgEIAQAAAA==.Whalecrab:BAAALAADCgcIDgAAAA==.Whodinisux:BAAALAADCgcIBwAAAA==.',Wi='Wicked:BAAALAADCgcIDgABLAAECgMIBAABAAAAAA==.Winston:BAAALAADCgUIBgAAAA==.',Wy='Wylestrean:BAAALAAECgYICAAAAA==.',Yo='Yollodinn:BAAALAAECgEIAQAAAA==.Yoolind:BAAALAADCggICAAAAA==.',Yu='Yujology:BAAALAAECgMIBQAAAA==.Yulind:BAAALAAECgYICQAAAA==.',Za='Zachknight:BAAALAADCgIIAwAAAA==.Zaniti:BAAALAADCggICAAAAA==.',Ze='Zel:BAAALAADCggIDAAAAA==.Zeme:BAAALAADCgcIBwAAAA==.Zentradei:BAAALAAECgEIAQAAAA==.Zephariel:BAAALAADCgYICAAAAA==.',Zi='Zieganfuss:BAAALAAECgYICgAAAA==.',Zo='Zoho:BAAALAAECgEIAQAAAA==.Zoombinis:BAAALAAECgMIAwAAAA==.Zottie:BAAALAAECgEIAQAAAA==.',['Ðr']='Ðracula:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end