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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Shaman-Restoration','DemonHunter-Havoc',}; local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acesup:BAAALAADCgQIBAAAAA==.Ackre:BAAALAADCggIDwAAAA==.',Ad='Aderian:BAAALAAECgYICQAAAA==.',Ag='Agarramelo:BAAALAADCgYIBgAAAA==.',Al='Alasha:BAAALAADCgYIBgAAAA==.Aldith:BAAALAAECgYIBgAAAA==.Alex:BAAALAAECgcIEAAAAA==.Allypally:BAAALAAECgQIBQAAAA==.Alunai:BAAALAADCgQIBAAAAA==.Alystrasza:BAAALAADCgcIBwAAAA==.',Am='Amgrod:BAAALAADCggIDwAAAA==.',An='Ankén:BAAALAAECgUICAAAAA==.',Ar='Aradwar:BAAALAAECgMIBAAAAA==.Aremis:BAAALAADCgYICAAAAA==.Arfas:BAAALAADCgIIAgAAAA==.Argronak:BAAALAADCgIIAgAAAA==.Arkhetype:BAAALAAECgMIBgAAAA==.',Au='Auracorusca:BAAALAAECgEIAQAAAA==.',Ba='Bajr:BAAALAAECgYICgAAAA==.Bamboozle:BAAALAADCgcICgAAAA==.Banker:BAAALAAECgIIAgAAAA==.Bassianus:BAAALAADCgYIBgAAAA==.',Be='Berko:BAAALAAECgUICgAAAA==.Bethil:BAAALAADCgYIBgAAAA==.',Bi='Bienestarina:BAAALAADCgcICgAAAA==.',Bj='Bjebo:BAAALAAECgMIBQAAAA==.',Bl='Blackout:BAAALAAECgIIBAAAAA==.Bluffz:BAAALAAFFAMIAwAAAA==.Bluffztwo:BAAALAAECgIIAgABLAAFFAMIAwABAAAAAA==.',Br='Brothermango:BAAALAADCgQIBQAAAA==.Brynjalf:BAAALAAECgIIAgAAAA==.',Bu='Buffshot:BAAALAAECgYICQAAAA==.Butterscotch:BAAALAAECgMIBAAAAA==.',['Bï']='Bïcho:BAAALAAECggIDgAAAA==.',Ca='Calambar:BAAALAADCgcIBwAAAA==.Calkurn:BAAALAADCgcICgAAAA==.Catch:BAAALAADCgYIBgAAAA==.',Ce='Ceilcya:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Celenight:BAAALAADCgcIDAAAAA==.',Ch='Chillidari:BAAALAADCgYIBgAAAA==.',Cl='Clavam:BAAALAADCggICAAAAA==.',Co='Coffeeshot:BAAALAADCgQIBAAAAA==.Conith:BAAALAADCgcIBwAAAA==.',Cr='Crashcake:BAAALAAECgYIBgAAAA==.',Da='Danvorian:BAAALAADCgIIAgAAAA==.Darmil:BAAALAAECgYICQAAAA==.',De='Deadlyalba:BAAALAADCggIFAAAAA==.Deathbezos:BAAALAADCgcIBwAAAA==.Demonblades:BAAALAAECgYICgAAAA==.Denarten:BAAALAAECgcIEAAAAA==.Destroass:BAAALAADCgcICAAAAA==.',Di='Disrupt:BAAALAADCgIIAgAAAA==.',Do='Dockevorkian:BAAALAAECgcIEAAAAA==.Dojo:BAAALAADCggIDwAAAA==.Dougclap:BAAALAADCggICAAAAA==.Dougdk:BAAALAADCgIIAgAAAA==.',Dr='Dracoczar:BAAALAADCgEIAQAAAA==.Drakej:BAAALAADCggICAAAAA==.Drdookie:BAAALAADCgEIAQAAAA==.Drinnokan:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Drinntellect:BAAALAADCggIGgABLAAECgcIEAABAAAAAA==.Dritolus:BAAALAAECgYIDAAAAA==.Drodanerf:BAAALAADCgcICgAAAA==.',Dx='Dxanatos:BAAALAAECgMIBQAAAA==.',Dy='Dysrupt:BAAALAAECgIIBAAAAA==.',Eg='Egodraconis:BAAALAAECgEIAQAAAA==.',El='Elbako:BAAALAADCgcIBwAAAA==.Elenara:BAAALAADCgcIBwAAAA==.Elilla:BAAALAAECgMIBgAAAA==.',Er='Erotes:BAAALAADCgUICAAAAA==.',Ez='Ezindetal:BAAALAADCgMIAwAAAA==.',Fa='Faing:BAAALAADCgQIBAAAAA==.Faithfulness:BAAALAAECgMIBgAAAA==.Farlack:BAAALAAECgMIAwAAAA==.',Fe='Felnollid:BAAALAAECgcIEAAAAA==.',Fh='Fheyd:BAAALAADCgUIBQAAAA==.',Fi='Fistandcider:BAAALAADCgcIDAAAAA==.',Fl='Floralcarer:BAAALAAECgEIAQAAAA==.',Fo='Follet:BAAALAADCgYIBgAAAA==.Forgivenn:BAAALAADCggICQAAAA==.Foxpalm:BAAALAAECgYICQAAAA==.Foxyalba:BAAALAADCgYIBgAAAA==.',Fr='Fromage:BAAALAADCgYICAABLAADCggIDAABAAAAAA==.Frostdflake:BAAALAAECgYIDQAAAA==.Fruitpunch:BAAALAADCgcIBwAAAA==.',Fu='Fubina:BAAALAAECgYICAAAAA==.Fulgurithm:BAAALAAECgYICgAAAA==.',Ga='Gardevóir:BAAALAADCgcIBwABLAAECgIIAwABAAAAAA==.Gatuw:BAAALAAECgIIAgAAAA==.',Gi='Gilgämesh:BAAALAAECgcIEwAAAA==.',Gl='Glomah:BAAALAAECgYIBgAAAA==.',Gr='Grandhomme:BAAALAAECgEIAQAAAA==.Grantul:BAAALAAECgMIBQAAAA==.Greasmon:BAAALAAECgcIDQAAAA==.Grimthore:BAABLAAECoEUAAICAAcIdxo+EABCAgACAAcIdxo+EABCAgAAAA==.Growlings:BAAALAAECgMIBAAAAA==.',Ha='Haanzo:BAEALAAECggIBAAAAA==.Hawktwo:BAAALAADCgYIBgABLAADCggIDAABAAAAAA==.',Hu='Hubirt:BAAALAAECgYICgAAAA==.Huntorox:BAAALAADCggIDwAAAA==.Hushpupi:BAAALAAECgYIDAAAAA==.',Ia='Ianthel:BAAALAADCgMIAwABLAADCgYICAABAAAAAA==.',Ic='Icesloth:BAAALAAECgEIAQAAAA==.',Id='Idamae:BAAALAADCggIDwAAAA==.Iduun:BAAALAADCgYIBgAAAA==.',Il='Ildar:BAAALAADCggICAAAAA==.',In='Incoherent:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.',Ja='Jafud:BAAALAAECgYICQAAAA==.Jamaican:BAAALAAECgIIAgAAAA==.Jarfjarfmix:BAAALAADCggICAAAAA==.Jaste:BAAALAAECgUIBgAAAA==.',Je='Jeromiah:BAAALAADCgcIBwAAAA==.Jessalba:BAAALAADCgcIBwAAAA==.',Ji='Jitan:BAAALAADCgcIBwAAAA==.',Ju='Juju:BAABLAAECoEYAAIDAAgIah1PBwCYAgADAAgIah1PBwCYAgAAAA==.Justice:BAAALAADCgcICQAAAA==.',Ka='Kalentina:BAAALAAECgQIBwAAAA==.Kambria:BAAALAADCgcIBwAAAA==.Kaminair:BAAALAADCgQIBAAAAA==.Kandra:BAAALAADCgcIBwAAAA==.Kaunuzoth:BAAALAADCgcIGQABLAAECgYIDAABAAAAAA==.',Kh='Khalia:BAAALAADCgcICwAAAA==.',Ki='Killbotx:BAAALAAECgMIAwAAAA==.Killt:BAAALAAECgMIBAAAAA==.Kimora:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Kioshii:BAAALAADCgIIAgABLAAECgYIDAABAAAAAA==.',Ko='Koalaharris:BAAALAAECgIIAgAAAA==.Koojoé:BAAALAADCgcICAAAAA==.',Ku='Kungfutiger:BAAALAAECgQIBwAAAA==.Kushiina:BAAALAAECgIIAwAAAA==.',La='Laghles:BAAALAAECgcIEQAAAA==.Laroes:BAAALAAECgMIBAABLAAECgYIBgABAAAAAA==.Laughles:BAAALAADCggICQABLAAECgcIEQABAAAAAA==.',Le='Lemanjá:BAAALAAECgYICgAAAA==.',Li='Liadrin:BAAALAAECgIIAwAAAA==.Liann:BAAALAADCgMIAwAAAA==.Lickenss:BAAALAAECgYIDAAAAA==.Liliane:BAAALAAECgQICAAAAA==.Limbless:BAAALAADCgYIBgABLAADCggIDAABAAAAAA==.',Lo='Lockstar:BAAALAAECgYICwAAAA==.Logistiprime:BAAALAADCgcIBwAAAA==.Logistiçs:BAAALAADCgQIBAAAAA==.Lookatme:BAAALAADCgQIBAAAAA==.',Lu='Lucerin:BAAALAADCgMIAwAAAA==.Lurak:BAAALAADCgUICQAAAA==.Luthais:BAAALAADCggIFQAAAA==.Luzifer:BAAALAADCggIDgAAAA==.',['Lê']='Lêng:BAAALAAECgMIAwAAAA==.',Ma='Mageyoulook:BAAALAAECgEIAQAAAA==.Malera:BAAALAADCgYIBgAAAA==.Malyce:BAAALAAECgMIBQAAAA==.Manasolid:BAAALAAECgYICgAAAA==.Mankow:BAAALAADCgcICQAAAA==.Margo:BAAALAAECgYICwAAAA==.Maruug:BAAALAADCggICwAAAA==.',Me='Meatcurtin:BAAALAADCgIIAgAAAA==.Meraleona:BAAALAAECgMIAwAAAA==.Methslinger:BAAALAAECgcIEAAAAA==.',Mi='Micaëla:BAAALAAECgYICQAAAA==.Micoo:BAAALAADCggICAAAAA==.',Mo='Mochee:BAAALAADCgcIDQABLAAECgYIDAABAAAAAA==.Moosh:BAAALAADCgYIBgAAAA==.Moris:BAAALAAECgMIBAAAAA==.Mortmuzi:BAAALAADCgcIBwAAAA==.',Mu='Muldah:BAAALAAECgcIDgAAAA==.Murdersquab:BAAALAADCgIIAgAAAA==.',My='Mynte:BAAALAAECgEIAQAAAA==.',Na='Naenamia:BAAALAADCgcIBwABLAAECgMIBwABAAAAAA==.Nas:BAAALAAECgIIAgAAAA==.Natreseth:BAAALAADCgIIAgAAAA==.Navie:BAAALAADCggICwAAAA==.Nawperwoman:BAAALAAECgQIBwAAAA==.',Ne='Necroz:BAAALAADCgcIBwAAAA==.Nezitalanot:BAAALAADCgUIBQAAAA==.Nezzek:BAAALAAECgUICwAAAA==.',Ni='Nicebud:BAABLAAECoEUAAIEAAgIfBchGAA9AgAEAAgIfBchGAA9AgAAAA==.Nightsfury:BAAALAADCgQIBAAAAA==.Nikawa:BAAALAAECgEIAQAAAA==.',No='Nozel:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.',Ny='Nymerias:BAAALAADCgQIBQAAAA==.',Ob='Obitó:BAAALAAECgIIAgAAAA==.',Om='Omaticaya:BAAALAAECgYICQAAAA==.',Or='Ordained:BAAALAADCggIDAAAAA==.Orlak:BAAALAADCgEIAQAAAA==.',Os='Oshot:BAAALAAECgEIAQAAAA==.',Ou='Oua:BAAALAADCggICAAAAA==.Ourania:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',Pa='Paean:BAAALAADCgcIEQAAAA==.Pakuriso:BAAALAADCgEIAQAAAA==.Pallyboi:BAAALAADCgYIBgAAAA==.Pandycake:BAAALAADCgcICgAAAA==.',Pe='Pelure:BAAALAADCgcIBwAAAA==.',Pi='Pillowfluff:BAAALAADCggICAAAAA==.Pillowpuhmpa:BAAALAADCgUIBQAAAA==.',Pk='Pkalygos:BAAALAAECgMIBQAAAA==.',Po='Powerstrokee:BAAALAADCggIEgAAAA==.',Pr='Prierin:BAAALAAECgMIBQAAAA==.',Ps='Psilocybin:BAAALAAECgYIDgAAAA==.Psychelone:BAAALAADCggIFQAAAA==.',Pu='Pupichow:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.Purification:BAAALAADCgcIBwAAAA==.',Ra='Raine:BAAALAADCgcIBwAAAA==.Rainer:BAAALAADCgcIBwAAAA==.',Re='Rexion:BAAALAAECgIIAgAAAA==.',Ri='Ripre:BAAALAADCgMIAwAAAA==.',Ru='Runeclad:BAAALAAECgMIBQAAAA==.',Ry='Ryla:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.',Sa='Saladron:BAAALAAECgIIBAAAAA==.Salitheion:BAAALAAECgMIAwAAAA==.Sapper:BAAALAAECgMIAwAAAA==.Sauroraa:BAAALAADCggICAAAAA==.Sayuri:BAAALAAECgEIAQAAAA==.',Sc='Scope:BAAALAADCgEIAQAAAA==.',Se='Serenn:BAAALAAECgMIAwAAAA==.',Sh='Shakafaka:BAAALAAECgYIBgAAAA==.Shalthen:BAAALAAECgYICQAAAA==.Sherot:BAAALAAECgMIAwAAAA==.Shladoran:BAAALAAECgYICAAAAA==.Shos:BAAALAAECgYICwAAAA==.Shotsshots:BAAALAAECgMIAwAAAA==.',Si='Siberianwolf:BAAALAADCggIFAAAAA==.Sinnister:BAAALAAECgUIBQAAAA==.',Sk='Skully:BAAALAADCgIIAgABLAAECgcIDQABAAAAAA==.Sky:BAAALAADCggICQABLAAECgMIBQABAAAAAA==.',Sn='Sneakyhammer:BAAALAAECgYICAAAAA==.Snorina:BAAALAAECgMIBwAAAA==.',So='Sosozen:BAAALAADCggIDwAAAA==.',St='Starkiller:BAAALAADCgEIAQAAAA==.Strange:BAAALAADCggICQAAAA==.',Su='Sullyheals:BAAALAAECgYIBgAAAA==.',Sw='Swytch:BAAALAAECgMIBQAAAA==.',Sy='Sylvii:BAAALAAECgIIAwAAAA==.',Ta='Tabor:BAAALAADCgcIDQAAAA==.Tammyfaye:BAAALAADCggIDAAAAA==.Tanzanite:BAAALAADCgYIBgAAAA==.Tarahcee:BAAALAADCgcIBwAAAA==.',Te='Telath:BAAALAADCgcIAQAAAA==.Teostra:BAAALAAECgEIAQAAAA==.',Th='Themoosifer:BAAALAAECgYICwAAAA==.Thicctomemz:BAAALAADCgcIBwAAAA==.Thyck:BAAALAAECgUIBQAAAA==.Thydis:BAAALAADCgYIBgAAAA==.',Ti='Tibbs:BAAALAAECgMIBgAAAA==.',Tk='Tk:BAAALAAECgMIAwAAAA==.',To='Tonar:BAAALAADCggIDQAAAA==.Toomuchjuice:BAAALAADCggIFgAAAA==.Torluis:BAAALAADCgIIAgAAAA==.',Tr='Trollydave:BAAALAADCgUIBQAAAA==.Trumalice:BAAALAADCgUIBQAAAA==.',Tu='Tuckr:BAAALAADCgcICwAAAA==.',Ty='Tybberss:BAAALAAECgEIAQAAAA==.Tyranick:BAAALAAECgYICgAAAA==.',Uk='Ukkie:BAAALAAFFAIIAgAAAA==.Uknowcuhbud:BAAALAAECgYICgAAAA==.',Un='Uncorrupted:BAAALAAECggIAQAAAA==.',Ur='Urforgiven:BAAALAAECgEIAQAAAA==.',Va='Vainqueur:BAAALAADCgIIAgAAAA==.Valkilik:BAAALAAECgMIBQAAAA==.Valuryan:BAAALAADCggIFQAAAA==.Vasdepherens:BAAALAAECgMIBgAAAA==.',Ve='Vell:BAAALAADCgYIBgAAAA==.Verox:BAAALAADCgcIEwAAAA==.',Vi='Villkiz:BAAALAADCggICAAAAA==.Vizzi:BAAALAADCggIEQAAAA==.',Vl='Vladomar:BAAALAADCgIIAgAAAA==.',Vs='Vspice:BAAALAADCggIDwAAAA==.',Wa='Wackz:BAAALAADCgYIBgAAAA==.Warshank:BAAALAADCgcIBwAAAA==.Wawa:BAAALAAECgYICgAAAA==.',Wh='Whissk:BAAALAADCggICAAAAA==.',Wo='Wovvo:BAAALAADCggIDgAAAA==.',Xh='Xhöry:BAAALAAECgYIAgAAAA==.',Yo='Yoruchi:BAAALAAECgYICgAAAA==.',Yu='Yurigami:BAAALAADCggIDAAAAA==.',Za='Zakuren:BAAALAAECgcIEAAAAA==.Zandie:BAAALAADCgEIAQAAAA==.',Zi='Zigormu:BAAALAAECgEIAQAAAA==.',Zo='Zoë:BAAALAADCgcIBwAAAA==.',['Ñî']='Ñîx:BAAALAAECgMIBQAAAA==.',['Ôj']='Ôjarg:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end