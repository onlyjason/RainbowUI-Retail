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
 local lookup = {'Unknown-Unknown',}; local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acezinha:BAAALAADCgYIBwAAAA==.Acezinho:BAAALAAECgQICAAAAA==.',Al='Alessaxd:BAAALAAECgUICAAAAA==.Alfajhor:BAAALAAECggIDwAAAA==.Alfinety:BAAALAADCgcIBwABLAAECggIEQABAAAAAA==.Alkarin:BAAALAAECgEIAQAAAA==.Alleriane:BAAALAAECgYICgAAAA==.Allïce:BAAALAADCgcIDAAAAA==.Alruna:BAAALAAECgQIAwAAAA==.Altaelli:BAAALAADCgYIBwAAAA==.',Am='Amazom:BAAALAAECgYIEQAAAA==.Ametnys:BAAALAAECgYIDQAAAA==.Amylta:BAAALAAECgcICQAAAA==.',An='Andaliz:BAAALAAECgYICAAAAA==.Andaril:BAAALAADCggIDgAAAA==.Ansião:BAAALAADCggIFgAAAA==.Anub:BAAALAADCgYIBgAAAA==.',Ar='Arattorn:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.Artronis:BAAALAAECgYIDQAAAA==.',As='Ashbörn:BAAALAAECgUICQAAAA==.Asteron:BAAALAAECgYICAAAAA==.Astropologo:BAAALAADCgYICQAAAA==.',At='Atriuz:BAAALAAECgYICwAAAA==.Attuk:BAAALAADCgcIBwAAAA==.',Au='Aurín:BAAALAADCgcICQAAAA==.',Ay='Aykho:BAAALAADCgcIBwAAAA==.',['Aú']='Aúromn:BAAALAADCgcIBwAAAA==.',Ba='Badloki:BAAALAADCgcICAAAAA==.Barbabruto:BAAALAAECgUIBgAAAA==.',Be='Bergrj:BAAALAADCggICQAAAA==.',Bi='Bigbag:BAAALAADCgYIBgAAAA==.',Bl='Bloke:BAAALAADCgcIBwAAAA==.',Bo='Boboi:BAAALAAECgMIBAAAAA==.Borgnåkke:BAAALAAECgYICAAAAA==.',Br='Brahman:BAAALAADCggIEQAAAA==.Brlyon:BAAALAADCgUICQAAAA==.Broquel:BAAALAADCgMIAwAAAA==.Brylux:BAAALAAECgEIAQAAAA==.',['Bë']='Bëard:BAAALAADCgcIDQABLAADCggICwABAAAAAA==.',Ca='Cangacëiro:BAAALAAECgEIAQAAAA==.Caralh:BAAALAAECgEIAQAAAA==.Cathe:BAAALAADCggIDgAAAA==.Caça:BAAALAAECgIIAgAAAA==.',Ce='Cearárinha:BAAALAAECggIEQAAAA==.',Ch='Champdude:BAAALAAECgQIBwAAAA==.Chico:BAAALAADCgUIBQAAAA==.',Cr='Cria:BAAALAADCgcIDQAAAA==.Cristcalad:BAAALAAECgMIAwAAAA==.Cronnak:BAAALAADCgEIAQAAAA==.',Cu='Cupnoodles:BAAALAAECgYICAAAAA==.Cutia:BAAALAADCgUIBQAAAA==.',Da='Daibodan:BAAALAAECgMIBQAAAA==.Dankambr:BAAALAADCgcIDgAAAA==.Danoprox:BAAALAAECgcICQAAAA==.Darkest:BAAALAADCgIIAgAAAA==.Darklara:BAAALAAECgMIBAAAAA==.Darkove:BAAALAAECgUIBQAAAA==.Darrow:BAAALAAECgYIDQAAAA==.',De='Deathfly:BAAALAADCggICAAAAA==.Deathinhu:BAAALAAECgYICAAAAA==.Deathnacht:BAAALAADCgYIBwAAAA==.Delset:BAAALAAECgUICwAAAA==.',Di='Dimeros:BAAALAADCggIDgAAAA==.Dishy:BAAALAADCgcIBwAAAA==.Divaloka:BAAALAADCgcICgAAAA==.',Dk='Dktropa:BAAALAAECgEIAQAAAA==.',Do='Donora:BAAALAAECgIIAgAAAA==.',Dr='Drackmontana:BAAALAAECgYIDQAAAA==.Dragaum:BAAALAAECgMIAwAAAA==.Dragony:BAAALAADCggIEwAAAA==.Drajeel:BAAALAADCgYICQAAAA==.Dramerk:BAAALAADCgcIBwAAAA==.Dratzako:BAAALAADCgEIAQAAAA==.Druidblack:BAAALAADCgYICAAAAA==.Dryter:BAAALAADCggICAAAAA==.',Du='Dubhe:BAAALAADCgUIBQAAAA==.',Dz='Dzon:BAAALAADCgEIAQAAAA==.',El='Eluuria:BAAALAADCgUIBQAAAA==.',Er='Ernest:BAAALAAECgQIBAAAAA==.',Es='Estagiario:BAAALAADCgcIBwAAAA==.',Fa='Faeldar:BAAALAADCgMIAwAAAA==.Fandrall:BAAALAADCggIBwAAAA==.Faölin:BAAALAADCggIFgAAAA==.',Fe='Feldonn:BAAALAADCggIFQAAAA==.Ferael:BAAALAAECgYICAAAAA==.',Fi='Filhododurók:BAAALAADCgcIBQAAAA==.',Fl='Flavors:BAAALAAECgQIBwAAAA==.Florbela:BAAALAADCgcIBwAAAA==.Floxy:BAAALAADCgMIAwAAAA==.',Fr='Fredericc:BAAALAAECgMIAwAAAA==.Freyá:BAAALAAECgQIBgAAAA==.',['Fö']='Föx:BAAALAADCggICAAAAA==.',Ga='Galatrixx:BAAALAAECgMIAwAAAA==.Galettz:BAAALAADCggICQAAAA==.Galfur:BAAALAADCgUIBQAAAA==.Gamori:BAAALAADCgYIBgAAAA==.Gandwelf:BAAALAADCgQIBAAAAA==.',Gd='Gdkpala:BAAALAADCgEIAQAAAA==.',Ge='Gegel:BAAALAAECgMIAwABLAAECgYIEQABAAAAAA==.',Gi='Giafar:BAAALAADCgMIAwAAAA==.',Go='Gouken:BAAALAADCgcICgAAAA==.',Gr='Grilado:BAAALAADCgcIBwAAAA==.Grumax:BAAALAAECgMIAwAAAA==.',Gu='Guasuty:BAAALAAECgQIBAAAAA==.Guitianki:BAAALAADCgYIAwAAAA==.Gusgislon:BAAALAAECgQIBwAAAA==.',['Gæ']='Gænnicus:BAAALAADCggICgAAAA==.',['Gø']='Gøvers:BAAALAADCgQIBAAAAA==.',Ha='Haaknosh:BAAALAAECggIDAAAAA==.Halord:BAAALAADCgcIBwAAAA==.Harchus:BAAALAADCgQICAAAAA==.',He='Heareezan:BAAALAADCgEIAQAAAA==.Hendrikison:BAAALAADCgQIBAAAAA==.',Hi='Hipot:BAAALAAECgMIAwAAAA==.',Hu='Hunfox:BAAALAAECggIEQAAAA==.',['Hö']='Hölycrüsh:BAAALAAECgYIDQAAAA==.',Ic='Icecurse:BAAALAADCggIDwAAAA==.',Il='Ilyna:BAAALAADCgMIAwAAAA==.',In='Indarion:BAAALAADCgQIBQAAAA==.Intbuf:BAAALAAECgUICAABLAADCgQIBgABAAAAAA==.Invisiblelol:BAAALAAECgYIDQAAAA==.',Iv='Ivina:BAAALAAECggIDgAAAA==.',Ja='Jadentrues:BAAALAADCggICAAAAA==.Jaymee:BAAALAADCgcIBwAAAA==.',Jc='Jcmdk:BAAALAAECgQIBwAAAA==.',Ju='Judapriest:BAAALAADCgMIAwAAAA==.Judithi:BAAALAADCgYIBgAAAA==.Jullianxd:BAAALAAECgIIAwAAAA==.',Jv='Jvkilerr:BAAALAADCgIIAgAAAA==.',Ka='Kaallew:BAAALAAECgMIAwAAAA==.Kaelonidas:BAAALAAECgYIDQAAAA==.Kalazshar:BAAALAAECgYICwAAAA==.Kalelzinho:BAAALAADCgYIBgAAAA==.Kangaxx:BAAALAAECgIIAgAAAA==.Kantaa:BAAALAADCggIEQAAAA==.Katucha:BAAALAADCgMIBQAAAA==.Kavartu:BAAALAAECgQIBwAAAA==.Kazul:BAAALAAECgMIAwAAAA==.',Ke='Keldorian:BAAALAADCgMIBQAAAA==.Kelliar:BAAALAADCggIDwAAAA==.',Kh='Khaliq:BAAALAAECgQIBgAAAA==.Khaos:BAAALAADCgYIBwAAAA==.Khisto:BAAALAAECgQIBQAAAA==.',Ki='Killerbiie:BAAALAAECgMIAwAAAA==.Kitamor:BAAALAAECgMIBQAAAA==.',Ko='Koriakin:BAAALAAECgMIAwAAAA==.Korläsh:BAAALAADCgcIFAAAAA==.Kosmo:BAAALAAECgYIBgAAAA==.Kotalkhan:BAAALAADCgcIDQAAAA==.',Kr='Kraniuso:BAAALAAECgMIAwAAAA==.Kronkthar:BAAALAADCgcIDAAAAA==.',Ku='Kuthila:BAAALAADCgIIAgAAAA==.',['Kí']='Kíty:BAAALAADCggICwAAAA==.',['Kÿ']='Kÿdou:BAAALAAECgYIDwAAAA==.',La='Laetus:BAAALAADCgYIBgAAAA==.Laiander:BAAALAAECgIIAgAAAA==.Laiany:BAAALAAECgYICAAAAA==.Lancer:BAAALAAECgMIAwAAAA==.Lastly:BAAALAADCgIIAgAAAA==.',Le='Lelinhæ:BAAALAADCgcIBwAAAA==.Leric:BAAALAADCgQICAAAAA==.Leyshen:BAAALAAECgMIBAAAAA==.',Lh='Lhama:BAAALAAECgQIBwAAAA==.Lhwei:BAAALAAECgIIAwAAAA==.',Li='Lipezeira:BAAALAADCgIIAQAAAA==.Lislfox:BAAALAAECgMIBQAAAA==.',Lk='Lkinho:BAAALAAECgEIAgAAAA==.',Lo='Logósh:BAAALAAECgIIAgAAAA==.Lokuhzmarcus:BAAALAAECgYICQAAAA==.Lortheron:BAAALAAECgMIBQAAAA==.Loupgarrou:BAAALAAECgMIBgAAAA==.',Lu='Lucileia:BAAALAAECgEIAgAAAA==.Lucyfary:BAAALAAECgUIBQAAAA==.Lupusmater:BAAALAADCgEIAQAAAA==.Luthiemnm:BAAALAAECgEIAQAAAA==.',Ly='Lylka:BAAALAAECgQIBwAAAA==.',['Lë']='Lëstat:BAAALAADCgcICAAAAA==.',['Lö']='Lör:BAAALAADCggICAAAAA==.',Ma='Maeghann:BAAALAADCggIFAAAAA==.Magashuave:BAAALAADCgcICAAAAA==.Magetity:BAAALAADCgMIBAAAAA==.Magraver:BAAALAADCgYIBgAAAA==.Mahalloo:BAAALAADCgcIBwAAAA==.Maholir:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.Makani:BAAALAADCgcICwAAAA==.Malphass:BAAALAADCgUIBQAAAA==.Malévolatity:BAAALAADCggICgAAAA==.Manaweaver:BAAALAADCgcIBwAAAA==.Mandarraio:BAAALAAECgMIAwAAAA==.Maple:BAAALAADCggIDwAAAA==.Massafera:BAAALAAECgQIBwAAAA==.Mathfacii:BAAALAAECgMIAwAAAA==.Matinhoverde:BAAALAADCgMIAwAAAA==.Maxinë:BAAALAADCgcIBwAAAA==.Mayanyy:BAAALAADCgcICAAAAA==.',Md='Mdrdark:BAAALAAECggIEgAAAA==.',Me='Medz:BAAALAAECgQIBwAAAA==.Megalokki:BAAALAAECgMIAwAAAA==.Meka:BAAALAAECgIIAgAAAA==.Melianya:BAAALAADCgcIBwAAAA==.Mercurios:BAAALAADCggIEwAAAA==.Merellien:BAAALAADCgMIAwAAAA==.Metamorful:BAAALAAECgMIAwAAAA==.',Mh='Mhorgann:BAAALAADCgIIAgAAAA==.',Mi='Mindysith:BAAALAAECgMIAwAAAA==.Mirvy:BAAALAAECgcIEwAAAA==.',Mo='Mohanninha:BAAALAADCgcIBwAAAA==.Mohotok:BAAALAAECgMIAwAAAA==.Morgh:BAAALAADCgIIAgAAAA==.Morkhar:BAAALAAECgYICwAAAA==.Morsíronn:BAAALAADCgcIBwAAAA==.Morthalys:BAAALAAECgYIDQAAAA==.',Mu='Murano:BAAALAAECgQIBQAAAA==.',['Má']='Máia:BAAALAAECgMIBAAAAA==.',['Mä']='Mändosz:BAAALAADCggIDgAAAA==.',['Mé']='Ménace:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',Na='Nadvorny:BAAALAAECgYICAAAAA==.Narkeiden:BAAALAADCgcIBwAAAA==.',Ne='Necronx:BAAALAADCgcIBwAAAA==.Nefas:BAAALAADCggIDwAAAA==.Nelaette:BAAALAADCgYIBgAAAA==.Nelf:BAAALAAECgIIAwAAAA==.Nelsonedi:BAAALAADCggIDwAAAA==.Nemmëviu:BAAALAADCgUIBQAAAA==.Nepthunus:BAAALAAECgQIBwAAAA==.Neuvosor:BAAALAADCgcIBAAAAA==.',Nh='Nhajla:BAAALAADCgUIBQAAAA==.',No='Nobitsura:BAAALAAECgYICAAAAA==.Noctiel:BAAALAADCggICAAAAA==.Noctred:BAAALAAECgYICAAAAA==.Novkov:BAAALAAECgMIAwAAAA==.',Ny='Nylthaly:BAAALAADCggICAAAAA==.',['Në']='Nëytiiri:BAAALAADCggIDAAAAA==.',Ol='Oldram:BAAALAADCgQIBAAAAA==.',On='Onistisu:BAAALAADCgcIBwAAAA==.',Or='Orillan:BAAALAAECgYIBwAAAA==.Orukam:BAAALAAECgMIAwAAAA==.Orulord:BAAALAADCgEIAQAAAA==.',Pa='Paix:BAAALAAECgYICwAAAA==.Palahammër:BAAALAAECgEIAQAAAA==.Pandalokodj:BAAALAAECgYIBgAAAA==.Pandong:BAAALAAECgMIBQAAAA==.Pangedrey:BAAALAAECgYICAAAAA==.Parcival:BAAALAAECgYICAAAAA==.Parký:BAAALAAECgMIBQAAAA==.Pastorclovis:BAAALAADCgcIBwAAAA==.Pauladinu:BAAALAADCgYIBwAAAA==.',Pe='Penseur:BAAALAAECgYICAAAAA==.Perçeu:BAAALAADCgcIBwAAAA==.',Pi='Pierro:BAAALAADCgYICgABLAAECgIIAgABAAAAAA==.Pitchula:BAAALAADCgcIBwAAAA==.',Pl='Plankh:BAAALAADCgcIBgAAAA==.',Po='Poltergeiste:BAAALAADCgYIBgAAAA==.',Pr='Pratrios:BAAALAAECgMIAwAAAA==.Predathor:BAAALAADCgcIDAAAAA==.Priestiti:BAAALAADCgMIAwAAAA==.',Ps='Psaaiiquer:BAAALAADCgEIAQAAAA==.',Py='Pyxis:BAAALAAECgMIBgAAAA==.',['Pä']='Pändero:BAAALAAECgIIAgAAAA==.',Ra='Radunz:BAAALAAECgQIBwAAAA==.Rafamatatudo:BAAALAADCggIEQAAAA==.Ragweiller:BAAALAAECgMIBQAAAA==.Raio:BAAALAAECgMIAwAAAA==.Rajh:BAAALAADCgEIAQAAAA==.Ralfwur:BAAALAADCgcIEAAAAA==.Razelcry:BAAALAADCggIFQAAAA==.',Re='Renam:BAAALAADCgYICQAAAA==.',Rh='Rhaizen:BAAALAADCggICAAAAA==.Rhaumarhu:BAAALAADCgYIBgAAAA==.Rhyzon:BAAALAADCgcIBwAAAA==.',Ri='Riptides:BAAALAAECgMIAwAAAA==.Riva:BAAALAAECgYICgAAAA==.',Ro='Rosafuriosa:BAAALAAECgIIAgABLAAECgYIEQABAAAAAA==.',Ru='Rustovick:BAAALAADCgcIBgAAAA==.',Ry='Ryler:BAAALAAECgcIDgAAAA==.',Sa='Saimòn:BAAALAADCgQIBgAAAA==.Salatzar:BAAALAADCggIBQAAAA==.Samejin:BAAALAAECgEIAgAAAA==.Sanahh:BAAALAADCgcIDwAAAA==.Santoru:BAAALAADCgMIAwAAAA==.Sapekinhä:BAAALAAECgYICQAAAA==.Saphirah:BAAALAAECgEIAQAAAA==.Satanvitória:BAAALAADCgQIBgAAAA==.Saturio:BAAALAADCgQIBAAAAA==.',Sc='Sciel:BAAALAADCgUIBgAAAA==.',Se='Sereiaa:BAAALAAECgIIAgAAAA==.Sethhell:BAAALAADCgYIBgAAAA==.',Sh='Shadowmore:BAAALAAECgYIBwAAAA==.Shadowraging:BAAALAAECgIIAgAAAA==.Shalthan:BAAALAADCgUIBQAAAA==.Shanoa:BAAALAAECgEIAQAAAA==.Shedo:BAAALAAECgcIEAAAAA==.Sheevane:BAAALAAECgQIBwAAAA==.Shodayme:BAAALAADCgcIDQAAAA==.Shonja:BAAALAADCgcICAAAAA==.Shula:BAAALAADCggIDQAAAA==.Shuruleyas:BAAALAADCgEIAQAAAA==.',Si='Siclop:BAAALAADCgIIAgAAAA==.',Sm='Smidget:BAAALAAECgMIAwAAAA==.',So='Solsunna:BAAALAADCgcIBwAAAA==.Sombrea:BAAALAADCgcIFAAAAA==.Soulwise:BAAALAADCggICAAAAA==.',Sr='Srtelúrio:BAAALAAECgQIBwAAAA==.',St='Stampede:BAAALAAECgEIAQAAAA==.Stëlla:BAAALAAECgMIAwAAAA==.',Su='Superweaver:BAAALAAECgYICAAAAA==.Surt:BAAALAAECgMIAwAAAA==.',Sw='Swaglordjock:BAAALAADCgIIAgAAAA==.Swarlock:BAAALAAECgMIAwAAAA==.',Sy='Syrelys:BAAALAADCgQIBAAAAA==.',Ta='Taal:BAAALAADCggICAAAAA==.Takomort:BAAALAAECgMIAwAAAA==.Talandar:BAAALAAECgYICAAAAA==.Tamuríl:BAAALAADCgIIAgAAAA==.Tanthallas:BAAALAADCgUIBwAAAA==.Taskan:BAAALAADCgMIAwAAAA==.Tavindh:BAAALAADCgcICQAAAA==.',Te='Teldro:BAAALAADCgcIDAAAAA==.Tempestt:BAAALAADCgIIAgAAAA==.Tensopala:BAAALAADCggICAAAAA==.',Th='Thabitah:BAAALAAECgQIBwAAAA==.Thaldir:BAAALAADCgIIAgAAAA==.Tharros:BAAALAAECgIIBAAAAA==.Theresa:BAAALAAECgQIBwAAAA==.Tholmund:BAAALAADCgEIAQAAAA==.Thorian:BAAALAAECgEIAQAAAA==.Thormentor:BAAALAADCgcIDQAAAA==.Thotamon:BAAALAADCgMIBgAAAA==.Thráain:BAAALAAECgEIAQAAAA==.Thundersword:BAAALAADCgcIBwAAAA==.Thuralionn:BAAALAADCgYIBgAAAA==.Théus:BAAALAAECgMIAwAAAA==.Thëo:BAAALAADCgIIAgAAAA==.Thünderfck:BAAALAADCggIDwAAAA==.',Ti='Tidim:BAAALAADCgUIBQAAAA==.Tihiro:BAAALAADCgYIBwAAAA==.',To='Tormael:BAAALAADCggIDQAAAA==.',Tr='Trynwan:BAAALAADCgcIDQAAAA==.',Ul='Ulquiórra:BAAALAADCgcIDwAAAA==.',Us='Usfull:BAAALAAECgMIBQAAAA==.',Va='Valky:BAAALAAECgQIBAAAAA==.',Vi='Vincimus:BAAALAADCgMIAwAAAA==.Vintekilo:BAAALAAECgMIBAAAAA==.Vishnatrix:BAAALAADCgcIBwAAAA==.',Vy='Vygh:BAAALAAECgUIBwAAAA==.',Wa='Wabafett:BAAALAADCgMIAwAAAA==.Walligator:BAAALAAECgMIBAAAAA==.Warlaka:BAAALAADCgMIAwAAAA==.Warpiel:BAAALAADCggICAABLAADCggICAABAAAAAA==.',Wi='Wikthor:BAAALAADCgYIBgAAAA==.Windrunners:BAAALAADCgIIAgAAAA==.',Xa='Xamalandrö:BAAALAADCggICgAAAA==.Xameme:BAAALAADCgcIBwAAAA==.Xanis:BAAALAAECgQIBQAAAA==.',Xe='Xeha:BAAALAADCggICAAAAA==.',Ya='Yamii:BAAALAAECgYIDAAAAA==.',Ze='Zeytona:BAAALAAECgQIBwAAAA==.',Zo='Zobo:BAAALAAECgQIBgAAAA==.',Zu='Zulkia:BAAALAADCgYIBgABLAAECgYICwABAAAAAA==.',['Ár']='Árÿä:BAAALAAECgQIBwAAAA==.',['Áy']='Áy:BAAALAADCgYIDAAAAA==.',['Är']='Äraxy:BAAALAAECgQIBwAAAA==.',['Øv']='Øvesso:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end