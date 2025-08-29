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
 local lookup = {'Unknown-Unknown',}; local provider = {region='US',realm='Llane',name='US',type='weekly',zone=44,date='2025-08-29',data={Ae='Aelador:BAAALAADCgUIBQAAAA==.',Ah='Ahondappleti:BAAALAAECgIIAgAAAA==.',Al='Aliadra:BAAALAAECgEIAQAAAA==.Alistus:BAAALAAECgYIDQAAAA==.Alonestarr:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.Aloney:BAAALAADCgQIBAAAAA==.Aluríanna:BAAALAAECgIIAgAAAA==.',Am='Amoriandis:BAAALAADCgcIBwAAAA==.',An='Angorim:BAAALAADCgcIDAAAAA==.Angua:BAAALAADCggIEAAAAA==.',Ap='Apspally:BAAALAAECgMIAwAAAA==.',Ar='Arielisa:BAAALAADCggIBgAAAA==.',Au='Aurius:BAAALAADCgYIBgAAAA==.',Az='Azzog:BAAALAADCggIFQAAAA==.',Ba='Baindyn:BAAALAAECgEIAQAAAA==.Barky:BAAALAADCgYIBgAAAA==.',Be='Beanboozled:BAAALAADCgQIBQAAAA==.Beaum:BAAALAAECgcIEAAAAA==.Beoff:BAAALAADCgcIBwAAAA==.Bessarion:BAAALAADCgUIBQAAAA==.Betdruid:BAAALAADCgYIDAAAAA==.',Bi='Bitsie:BAAALAAECgEIAQAAAA==.',Bl='Blaggut:BAAALAADCgQIBQAAAA==.Blessurhart:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Blksunshine:BAAALAADCgQIBAAAAA==.',Bo='Bolash:BAAALAADCgYIBwAAAA==.Boyslave:BAAALAAECgcIEQAAAA==.',Br='Bradthomas:BAAALAADCgIIAgAAAA==.Briiezee:BAAALAAECgMIAwAAAA==.Bruscha:BAAALAAECgEIAQAAAA==.',Bu='Bulvhine:BAAALAADCggIFAAAAA==.',['Bù']='Bùmblebee:BAAALAAECgMIAwAAAA==.',Ca='Cactusteeth:BAAALAAECgIIAgAAAA==.Camford:BAAALAAECgIIAgAAAA==.Catou:BAAALAADCgcIBwAAAA==.',Ce='Ceenaya:BAAALAADCggIDwAAAA==.',Ch='Chewydeath:BAAALAAECgcIDQAAAA==.Chillmend:BAAALAAECgMIBQAAAA==.Chimerax:BAAALAAECgYIDAAAAA==.Chocoláte:BAAALAAECgIIAwABLAAECgMIAwABAAAAAA==.Chully:BAAALAAECgYICQAAAA==.',Cl='Click:BAAALAAECgMIBQAAAA==.Cloutfarmer:BAAALAAECgcIEAAAAA==.',Co='Comadore:BAAALAAECgUIBwAAAA==.',Cr='Crimes:BAAALAADCgUIBQAAAA==.',Cy='Cylithina:BAAALAAECgEIAQAAAA==.',Da='Daegal:BAAALAADCgQIBAAAAA==.Dapope:BAAALAADCgQIBAAAAA==.Dartheior:BAAALAADCgMIAwAAAA==.Dawggbiscuit:BAAALAAECgMIAwAAAA==.Daygu:BAAALAAECgQIBwAAAA==.',De='Deadseksi:BAAALAADCgEIAQAAAA==.Decrepe:BAAALAAECgcIEAAAAA==.Delph:BAAALAAECgcIEAAAAA==.Demon:BAAALAAECgEIAgAAAA==.',Di='Diarmada:BAAALAADCgcIDAAAAA==.Dietmtndew:BAAALAADCggIEAAAAA==.Distill:BAAALAADCgQIBAAAAA==.',Do='Dominicm:BAAALAAECgcIEAAAAA==.Doola:BAAALAADCgIIAgAAAA==.Downloading:BAAALAAECgYIEAAAAA==.',Dr='Draegadin:BAAALAADCgQIBQAAAA==.Draq:BAAALAADCgQIBQAAAA==.',Du='Dublinn:BAAALAADCggIFQAAAA==.',Eb='Ebonhorn:BAAALAAECgEIAQAAAA==.',Ei='Einark:BAAALAAECgIIAgAAAA==.Einen:BAAALAADCgcIDQAAAA==.',El='Eldrond:BAAALAADCgQIBwABLAAECgIIAgABAAAAAA==.Elinis:BAAALAAECgMIAwAAAA==.Elrîc:BAAALAADCgMIAwAAAA==.',Er='Eridor:BAAALAADCgEIAQAAAA==.',Ex='Exek:BAAALAAECgEIAQAAAA==.',Fa='Fabaztard:BAAALAAECgEIAQAAAA==.Faline:BAAALAAECgQIBAAAAA==.',Fe='Ferlane:BAAALAADCggIEAAAAA==.Feywynn:BAAALAADCgYIBwAAAA==.',Fi='Fights:BAAALAAECgQIBgAAAA==.Fiigment:BAAALAADCggICAAAAA==.',Fo='Forky:BAAALAAECgIIBAAAAA==.Foxknight:BAAALAAECgEIAQAAAA==.',Fr='Franksnbeans:BAAALAAECgQIBAAAAA==.',Ga='Gaction:BAAALAADCgMIBAAAAA==.Gadrielle:BAAALAADCggIDAAAAA==.Gameslayer:BAAALAADCggICAAAAA==.',Gh='Ghalumvhar:BAAALAADCggIFAAAAA==.Ghostybb:BAAALAADCggIEgAAAA==.',Gi='Gila:BAAALAADCggIDAAAAA==.Gilamon:BAAALAADCggICQAAAA==.Gingasorrow:BAAALAAECgEIAQAAAA==.Gizzle:BAAALAAECgYICQAAAA==.',Gl='Glomdrul:BAAALAADCgcICgAAAA==.',Gr='Gruljak:BAAALAADCggICAAAAA==.Grÿmm:BAAALAAECgMIBQAAAA==.',Ha='Hanjha:BAAALAAECgMIBQAAAA==.Haryma:BAAALAADCgIIAgABLAAECgcIEQABAAAAAA==.Hatz:BAAALAADCgcICQAAAA==.',He='Heavyxj:BAAALAAECgIIAgAAAA==.Heyblinken:BAAALAADCggIDgAAAA==.',Hm='Hm:BAAALAADCgcIAQAAAA==.',Ho='Hoff:BAAALAADCggICAAAAA==.Holyjouk:BAAALAADCggIEAAAAA==.',Hu='Hugzy:BAAALAADCgYIBgAAAA==.Huueguard:BAAALAAECgYICAAAAA==.',Hw='Hwore:BAAALAAECgIIAgAAAA==.',Hy='Hypnocide:BAEALAAECgIIAgAAAA==.',Ic='Icxdin:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',Il='Illandren:BAAALAAECgcIDQAAAA==.Illusiveeyes:BAAALAADCgcIBwAAAA==.Illuvatar:BAAALAAECggICAAAAA==.Ilona:BAAALAAECgMIAwAAAA==.',Im='Imoogi:BAAALAADCgYIBgAAAA==.Impsane:BAAALAAECgIIAgAAAA==.',Jo='Joesph:BAAALAADCgcIBwAAAA==.',Ju='Judis:BAAALAAECgMIBAAAAA==.',Ka='Kairì:BAAALAADCggIFQAAAA==.Kalifist:BAAALAAECgYICwAAAA==.Kalipain:BAAALAADCgQIBAAAAA==.Kanajotoma:BAAALAAECgEIAQAAAA==.',Ke='Keleena:BAEALAAECgIIAgAAAA==.',Ki='Kinst:BAAALAAECgIIAgAAAA==.Kitanyia:BAAALAAECgQIBQAAAA==.',Ky='Kyakuna:BAAALAADCgEIAQAAAA==.Kyrah:BAAALAAECgIIAgAAAA==.',Le='Lenthalis:BAAALAADCggIDwAAAA==.',Li='Libearty:BAAALAAECgMIBQAAAA==.Lilbro:BAAALAADCgQIBQAAAA==.Lilithh:BAAALAADCggIDQAAAA==.Lingula:BAAALAAECgEIAQAAAA==.',Lo='Loaganic:BAAALAAECgcIEAAAAA==.Lockjáw:BAAALAADCgMIAwAAAA==.',Ly='Lytol:BAAALAAECgMIBQAAAA==.',Ma='Magikin:BAAALAAECggIEwAAAA==.',Me='Mechagnome:BAAALAAECgcICgAAAA==.Meezee:BAAALAADCgcICgAAAA==.Megamedes:BAAALAAECgMIBQAAAA==.Meizhi:BAAALAADCggICwAAAA==.',Mi='Missmaam:BAAALAADCggIFQAAAA==.Mithras:BAEALAADCggIDwABLAAECgMIAwABAAAAAA==.',Mu='Mushuwoonter:BAAALAAECgQIBgAAAA==.',['Mô']='Mônkii:BAAALAAECgcIEQAAAA==.',Na='Naenia:BAAALAADCggIDQAAAA==.',Ne='Nepe:BAAALAADCgQIBAAAAA==.',No='Nocainus:BAAALAAECgMIBQAAAA==.Noogarg:BAAALAADCggIDwAAAA==.',Ny='Nyasu:BAAALAADCgQIBAAAAA==.',['Nà']='Nàl:BAAALAADCgMIAwAAAA==.',['Nø']='Nøtsure:BAAALAADCggIDgAAAA==.',Ob='Obsidia:BAAALAAECgIIAgAAAA==.',Om='Omelette:BAAALAADCgcIBwAAAA==.',On='Onik:BAAALAAECgIIAgAAAA==.',Op='Ophiris:BAAALAAECgMIAwAAAA==.Opochtli:BAAALAADCggIAgAAAA==.',Or='Orinoheal:BAAALAAECgEIAQAAAA==.',Os='Oskar:BAAALAADCggICAAAAA==.',Pa='Pallydude:BAAALAADCgQIBQAAAA==.',Pe='Perilous:BAAALAADCgQIBAAAAA==.',Ph='Phat:BAAALAADCgQIBQAAAA==.Phuumyn:BAAALAAECgMIBQAAAA==.',Pi='Piccoblast:BAAALAAFFAIIAgAAAA==.Picklesoup:BAAALAAECgEIAQAAAA==.Piickles:BAAALAAFFAIIAgAAAA==.',Pl='Plutø:BAAALAAECgIIAwAAAA==.',Pr='Praeastra:BAEALAAECgMIAwAAAA==.Proctôr:BAAALAAECgQIBAAAAA==.',Qu='Quilian:BAAALAAECgYIBgAAAA==.',Ra='Radian:BAAALAAECgMIBQAAAA==.Raelynn:BAAALAAECgMIBQAAAA==.Raevenhart:BAAALAAECgYICQAAAA==.Raptorx:BAAALAADCgcIEgAAAA==.Rawls:BAAALAADCgYIBgAAAA==.',Re='Redvex:BAAALAAECgcIEAAAAA==.Redwing:BAAALAAECgEIAQAAAA==.Rei:BAAALAAECgYIDAAAAA==.Rencraw:BAAALAAECgMIAwAAAA==.Restoris:BAAALAADCgEIAQAAAA==.Rewrew:BAAALAAECgQIBAAAAA==.',Ri='Rilbreena:BAAALAADCgQIBQAAAA==.Rinahvoid:BAAALAAECgcIDQAAAA==.',Ro='Rosanna:BAAALAADCgcIBwAAAA==.',Ru='Ruana:BAEALAAECgEIAQAAAA==.Rubyrazor:BAAALAADCgQIBAAAAA==.',Sc='Schiggymonk:BAAALAADCgcIAgAAAA==.Scubbs:BAAALAAECgYICQAAAA==.Scubbsboo:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.',Se='Seras:BAAALAADCgYICwAAAA==.Servantes:BAAALAAECgMIBQAAAA==.Seviora:BAAALAADCgMIAwAAAA==.',Sh='Shadokin:BAAALAADCggICAAAAA==.Shootsz:BAAALAAECggICwAAAA==.Shotya:BAAALAAECgMIBQAAAA==.',Si='Singe:BAAALAADCgEIAQAAAA==.Sixthknight:BAAALAADCgcIBwAAAA==.',Sl='Slambow:BAAALAADCgYICgAAAA==.',Sn='Snarkypony:BAAALAADCgQIBAAAAA==.',So='Sorsere:BAAALAAECgIIAgAAAA==.',Sp='Spoilsport:BAAALAAECgEIAQAAAA==.',St='Starcaller:BAAALAADCggIDwAAAA==.',Su='Sulph:BAAALAAECggIBQAAAA==.',Ta='Taarrt:BAAALAADCgYIBgAAAA==.Taart:BAAALAAECgQIBAAAAA==.Talshekar:BAAALAAECgMIBQAAAA==.Tarsis:BAAALAAECgMIBQAAAA==.Tauruman:BAAALAADCgcICQAAAA==.',Te='Terya:BAAALAADCggIAQAAAA==.Tezlyn:BAAALAADCggIEAAAAA==.',Th='Thaevin:BAAALAAECgIIAgAAAA==.Thatbirch:BAAALAADCgcIBwAAAA==.Thingwan:BAAALAAECgYICQAAAA==.',To='Toiletpooper:BAAALAADCgcIBQAAAA==.',Tr='Treewisp:BAEALAADCgEIAQABLAAECgIIAgABAAAAAA==.Troy:BAAALAAECgQIBAAAAA==.Trylly:BAAALAAECgEIAQAAAA==.',Ty='Typh:BAAALAAECgcIEAAAAA==.',Uf='Uffish:BAAALAADCgQIBQAAAQ==.',Un='Undeaddemon:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.Undeadscaly:BAAALAAECgYIDAAAAA==.Undeadshaman:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Undignified:BAAALAAECgIIAgAAAA==.',Ve='Verasia:BAAALAAECgEIAQAAAA==.',Vi='Vidikan:BAAALAAECgEIAQAAAA==.',Vo='Volbourn:BAAALAADCgQIBAAAAA==.',Vv='Vvumpscut:BAAALAAECgcIEAAAAA==.',Wi='Wildsoul:BAAALAAECgMIBQAAAA==.Witt:BAAALAAECgYICQAAAA==.',Wr='Wreked:BAAALAAECgMIAwAAAA==.',Xa='Xaneva:BAAALAAECgcICgAAAA==.',Xe='Xerôxgravity:BAAALAAECgIIAgAAAA==.',Xi='Xilo:BAAALAADCgcICwAAAA==.Xilphira:BAAALAAECgEIAQAAAA==.',Xl='Xlithz:BAAALAAECgQIBAAAAA==.',Ya='Yarohd:BAAALAADCgcIBwAAAA==.',Za='Zapheara:BAAALAADCggICAAAAA==.Zarelleria:BAAALAADCgEIAQAAAA==.',Ze='Zente:BAAALAAECgYICQAAAA==.Zequill:BAAALAAECgQIBgAAAA==.Zevsticles:BAAALAAECgcIDQAAAA==.',Zo='Zooj:BAAALAAECgMIBQAAAA==.',Zt='Ztacez:BAAALAADCgIIBAAAAA==.',Zy='Zylofeather:BAAALAADCgcICgAAAA==.',['Áz']='Ázeroth:BAAALAADCgcIBwAAAA==.',['ßa']='ßaddie:BAAALAAECgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end