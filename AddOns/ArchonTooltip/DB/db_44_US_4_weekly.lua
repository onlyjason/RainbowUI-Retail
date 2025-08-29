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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Frost','Hunter-Survival','Hunter-BeastMastery','Evoker-Preservation','Warrior-Fury','Priest-Holy','Shaman-Enhancement','Shaman-Restoration','Monk-Windwalker','Rogue-Assassination','Monk-Mistweaver',}; local provider = {region='US',realm='Aggramar',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aandree:BAAALAAECgMIBQAAAA==.Aantara:BAAALAAECgMIBAAAAA==.Aaubree:BAAALAAECgMIBQAAAA==.',Ab='Abïdon:BAAALAAECgYICQAAAA==.',Ac='Achkpally:BAAALAAECgQIBQAAAA==.Achkshaman:BAAALAADCgUIBQABLAAECgQIBQABAAAAAA==.',Ad='Adhd:BAAALAAECgMIBQAAAA==.Adison:BAABLAAECoEWAAICAAcIaCIPDQCyAgACAAcIaCIPDQCyAgAAAA==.Adyrt:BAAALAADCgIIAgAAAA==.',Ae='Aezir:BAAALAAECgYIDgAAAA==.',Ag='Agrepa:BAAALAADCggIDwAAAA==.',Ah='Aharuo:BAAALAADCgEIAQAAAA==.',Al='Alanil:BAAALAADCgMIAwAAAA==.Alataar:BAAALAADCgEIAQABLAAECgMIBwABAAAAAA==.Alekrynn:BAAALAADCggICwABLAAECgEIAQABAAAAAA==.Alexxa:BAAALAADCgIIAgABLAADCgQIBAABAAAAAA==.Alexyus:BAAALAAECgIIAgAAAA==.Alphahappy:BAAALAADCggIDwAAAA==.Alphashock:BAAALAADCggICAAAAA==.',Am='Amavessa:BAAALAADCggIEQAAAA==.Amiracat:BAAALAAECgEIAQAAAA==.Amorous:BAAALAADCggIEQAAAA==.',An='Angelinea:BAAALAADCgUIBQAAAA==.Anrix:BAAALAAECgEIAQAAAA==.Anumaril:BAAALAAECgMIAwABLAAECgMIBwABAAAAAA==.',Ap='Apollyion:BAAALAADCgYIBgAAAA==.Apostle:BAAALAAECgYIDAAAAA==.Applepiez:BAAALAADCgUIBgAAAA==.',Ar='Arandre:BAAALAAECgIIAgAAAA==.Arbiter:BAAALAADCggIFQABLAAECggIEQABAAAAAA==.Arcana:BAAALAAECgYICgAAAA==.Archameidus:BAAALAADCgYIBgAAAA==.Aresiea:BAAALAADCgUIBQAAAA==.Arrowzmight:BAAALAAECgYICAAAAA==.Artogand:BAAALAADCggIFgAAAA==.Arvad:BAAALAAECgYICwAAAA==.Aríà:BAAALAADCgcIDAAAAA==.',As='Asclepión:BAAALAAECgYIDAAAAA==.Askiastout:BAAALAAECggICAAAAA==.Asmodeüs:BAAALAADCgQIBAAAAA==.Asteria:BAAALAADCggIFgAAAA==.',At='Athania:BAAALAADCggICAAAAA==.Atoli:BAAALAAECgYICQAAAA==.',Av='Avemaria:BAAALAADCgEIAQAAAA==.Averlandra:BAAALAAECgYIDQAAAA==.',Aw='Awnyxxia:BAAALAAECgMIBAAAAA==.',Az='Azalth:BAABLAAECoEYAAIDAAgILya0AABxAwADAAgILya0AABxAwAAAA==.Azstastic:BAAALAAECgcIDwAAAA==.Azurehunt:BAAALAADCggICgAAAA==.Azázel:BAAALAADCgUIBQAAAA==.',Ba='Babycarrots:BAAALAAECgYICgAAAA==.Backdoorbill:BAAALAADCgUIBQAAAA==.Bacondad:BAAALAADCgcIBwAAAA==.Baldshogun:BAAALAAECgMIBQAAAA==.Balviz:BAAALAADCgcIDgAAAA==.Bandit:BAAALAADCggICwAAAA==.Barkatrusa:BAAALAAECgEIAQAAAA==.Bartokk:BAAALAAECgYICQAAAA==.Batkalklalka:BAAALAAECgcIDQAAAA==.Batmans:BAAALAADCggICAAAAA==.Baugulf:BAAALAAECgEIAgAAAA==.',Be='Beelzebuh:BAAALAADCggIFgAAAA==.Bellatrixt:BAAALAAECggIEgAAAA==.Bellilia:BAAALAADCgcIEQAAAA==.Bethmoder:BAAALAADCggICAAAAA==.',Bh='Bhewbz:BAAALAAECgcIEQAAAA==.',Bi='Bigbeardy:BAAALAAECgMIBwAAAA==.Bigchopps:BAAALAADCggIEAAAAA==.Bigshrimp:BAAALAAECgYICQAAAA==.Bilong:BAAALAADCgcIDAAAAA==.Bisquikb:BAAALAADCggIEAAAAA==.Bitnipplyout:BAAALAADCggICAAAAA==.',Bl='Blaqarrow:BAAALAADCggIDAAAAA==.Blazingdh:BAAALAADCgEIAQAAAA==.Blazingpally:BAAALAADCgIIAQAAAA==.Blessednatur:BAAALAADCgYIBgAAAA==.Blessedshot:BAAALAADCgYICgABLAADCgYIBgABAAAAAA==.Blesslock:BAAALAADCgEIAQABLAADCgYIBgABAAAAAA==.Blessvoker:BAAALAAECgcIEAABLAADCgYIBgABAAAAAA==.Bluebearie:BAAALAADCggICAABLAADCggICAABAAAAAA==.Bluemeenie:BAAALAAECgQICQAAAA==.',Bo='Boha:BAAALAADCggICQAAAA==.Boltlina:BAAALAAECgYIDgAAAA==.Bolux:BAAALAADCggIDwAAAA==.Boomerdruid:BAAALAAECgcIEgAAAA==.Booti:BAAALAAECgYICQAAAA==.Borz:BAAALAAECgMIBAAAAA==.Bountyspace:BAAALAAECgIIAgAAAA==.Bowphysicz:BAAALAADCggIEQAAAA==.',Br='Breaker:BAAALAADCgQIBAAAAA==.Brewsmash:BAAALAADCgcIBwABLAADCggIDwABAAAAAA==.Brightblaze:BAAALAAECgQIBgAAAA==.Brinefury:BAAALAAECgEIAQAAAA==.Brndo:BAAALAAECgMIBAAAAA==.Bronìx:BAAALAADCgcIEgAAAA==.Brownstars:BAAALAADCgcIBwAAAA==.Brukah:BAAALAADCggICgAAAA==.Brunoxp:BAAALAAECgYICQAAAA==.',Bu='Buritek:BAAALAAECgYICQAAAA==.',By='Bylur:BAAALAADCggICAAAAA==.',Ca='Cainhurst:BAAALAAECgIIAgAAAA==.Calaban:BAAALAAECgUIDAAAAA==.Callmedead:BAAALAAECgMIBAAAAA==.Callvar:BAAALAADCggICAAAAA==.Calyssena:BAAALAAECgIIAwAAAA==.Camalyn:BAAALAAECgUIBQAAAA==.Carcase:BAAALAAECggICwAAAA==.Carrot:BAAALAAECgYICgAAAA==.Castorice:BAAALAAECgUIBwAAAA==.Catayia:BAAALAAECgEIAQAAAA==.',Ce='Ceggss:BAAALAADCggICAAAAA==.Celesar:BAAALAADCgYICAAAAA==.Cellanthus:BAAALAADCgMIAwAAAA==.Cellasril:BAAALAAECgUICQAAAA==.Celticfrost:BAAALAAECgUICgAAAA==.Cenasmite:BAAALAADCggICAAAAA==.Cenoren:BAABLAAECoEUAAMEAAgImxruBABaAgAEAAgIJRruBABaAgAFAAEIvB5khAA+AAAAAA==.',Ch='Chaewon:BAAALAAECgEIAQAAAA==.Chaitanyanbd:BAAALAADCgcIAQAAAA==.Cheanisaurus:BAAALAADCgYIBgAAAA==.Chickenchin:BAAALAADCgQIBAAAAA==.',Ci='Cinematics:BAAALAAECgYIBwAAAA==.',Cl='Clenzo:BAAALAAECgQICAAAAA==.',Co='Cogsworthh:BAAALAADCggICAAAAA==.Conejomalo:BAAALAADCgcIBwAAAA==.Conscription:BAAALAADCgIIAgAAAA==.Coral:BAAALAADCgMIBAAAAA==.Corpserunner:BAAALAAECgMIAwAAAA==.',Cr='Cristty:BAAALAAECgEIAQAAAA==.Crocko:BAAALAADCgcICgAAAA==.Crowfoot:BAAALAADCgcIDgAAAA==.Crowshock:BAAALAAECgYIDAABLAAFFAIIAwABAAAAAA==.Crowul:BAAALAAECgQICgAAAA==.Crystallyn:BAAALAAECgYICgAAAA==.',Cu='Cubandaddy:BAAALAAECggICwAAAA==.Cutiebunnie:BAAALAADCggICAAAAA==.',Cy='Cybelliar:BAAALAADCgUIBgAAAA==.Cynthía:BAAALAAECgYIDAAAAA==.',['Câ']='Câmêllyâ:BAAALAADCgIIAgAAAA==.',['Cä']='Cärnage:BAAALAADCggICAABLAAECgcIDAABAAAAAA==.',Da='Daemlon:BAAALAAECgMIBAAAAA==.Dargonsevzer:BAAALAAECgYICQAAAA==.Darkkray:BAAALAAECgMIBwAAAA==.Darkros:BAAALAADCgEIAQAAAA==.Darkruul:BAAALAADCgUIBQAAAA==.Darkshadowq:BAAALAAECgQIBgAAAA==.Darkweaver:BAAALAAECgMIAwAAAA==.Darrio:BAAALAADCgUIBQAAAA==.Darrkstarr:BAAALAAECgEIAgAAAA==.Daspen:BAAALAAECgYIDQAAAA==.',De='Dedango:BAAALAAECgMIBAAAAA==.Delmart:BAAALAADCgEIAQAAAA==.Delonge:BAAALAADCggIFQAAAA==.Delsmonk:BAAALAAECgYICwAAAA==.Demonicshat:BAAALAAECgMIAwAAAA==.Demonkeeper:BAAALAAECgEIAQAAAA==.Deo:BAAALAAECgMIAwAAAA==.Despere:BAAALAADCgQIBAAAAA==.',Di='Diablìta:BAAALAAECgYICgAAAA==.Dilk:BAAALAAECgEIAQAAAA==.Dirt:BAAALAAECgYICwAAAA==.Diryzard:BAAALAADCgcIDgABLAAECgYICwABAAAAAA==.',Do='Doghorse:BAAALAAECgQIBgAAAA==.Domago:BAAALAAECggIDwAAAA==.Dorknight:BAAALAAECgIIAwAAAA==.Doroo:BAAALAAECgMIBgAAAA==.Dotfeardot:BAAALAAECgMIAwAAAA==.',Dp='Dpalm:BAAALAADCgYIDAABLAAECgcIDQABAAAAAA==.Dpalmlock:BAAALAADCgYICwAAAA==.',Dr='Draedia:BAAALAADCgYIBgAAAA==.Dragonarc:BAAALAADCgQIBAAAAA==.Drakros:BAAALAAECgIIAwAAAA==.Draktherias:BAAALAADCgcIBwAAAA==.Drastrasza:BAABLAAECoEUAAIDAAYIAgv/HgBHAQADAAYIAgv/HgBHAQAAAA==.Drdeathtron:BAAALAADCggIDgABLAAECgYIBwABAAAAAA==.Dreademon:BAAALAADCggICAAAAA==.Drfelshy:BAAALAAECgEIAQAAAA==.Drgonja:BAAALAAECgMIBAAAAA==.Drongk:BAAALAADCgYIBgAAAA==.Drovodian:BAAALAAECgMIBgAAAA==.Drroughneck:BAAALAADCgcIDAAAAA==.Dru:BAAALAAECgQICAAAAA==.Drunkhealer:BAAALAADCgcICAAAAA==.',Du='Dudezo:BAAALAADCggIDAAAAA==.Dulled:BAAALAADCggICgABLAADCggIFAABAAAAAA==.Dundoh:BAAALAAECgcICwAAAA==.Durm:BAAALAAECgIIAwAAAA==.Duskknight:BAAALAAECgMIBAAAAA==.',['Dá']='Dánte:BAAALAAECgQIBAAAAA==.',Ea='Earthwarden:BAAALAADCggIDwAAAA==.',Ec='Echò:BAAALAADCggIDgAAAA==.',Ei='Eillwine:BAAALAAECgEIAQAAAA==.',El='Elaeryon:BAAALAAECgMIBQAAAA==.Eleeza:BAAALAADCggIDwAAAA==.Eliel:BAAALAADCgIIAgAAAA==.Ellidiir:BAAALAADCggIFgAAAA==.Ells:BAAALAADCgcICAAAAA==.Elm:BAAALAAFFAIIAgAAAA==.Elvanshalee:BAAALAAECgUIBgAAAA==.Elylreith:BAAALAADCggIEwAAAA==.',Em='Eminjangidge:BAAALAADCgEIAQAAAA==.',Er='Eredeath:BAAALAAECgMIBwAAAA==.',Es='Esdeäth:BAAALAAECgcIEAAAAA==.Eskiestout:BAAALAAECggICAAAAA==.Estar:BAAALAAECgMIBQAAAA==.',Et='Eternity:BAAALAAECgIIAgAAAA==.',Eu='Eunomia:BAAALAAECgEIAQAAAA==.',Ev='Evokado:BAAALAADCggIDgABLAAECgYICQABAAAAAA==.Evol:BAAALAAECgMIBQAAAA==.',Ex='Exeter:BAAALAAECgIIAgAAAA==.',Fa='Faeliyn:BAAALAADCggIDwAAAA==.Faelyne:BAAALAADCgcIBwAAAA==.Falrynn:BAAALAADCggIEgAAAA==.',Fe='Fearinshatt:BAAALAAECgIIAgAAAA==.Felcrotic:BAAALAAECgYICQAAAA==.Feldrongk:BAAALAAECggIDAAAAA==.Felena:BAAALAADCgQIBAAAAA==.Felucca:BAAALAAECgYICgAAAA==.Felune:BAAALAADCgQIBAAAAA==.Fengaal:BAABLAAECoEWAAIGAAgIriYSAACNAwAGAAgIriYSAACNAwAAAA==.Fennrir:BAAALAADCgcIBwAAAA==.Feoriandis:BAEALAAECgIIAwAAAA==.',Fh='Fhalen:BAAALAAECgMIBwAAAA==.',Fi='Fiestyfluff:BAAALAADCgcIDQAAAA==.Fimbik:BAAALAAECgYICAAAAA==.Finixia:BAAALAAECgEIAQAAAA==.Fishymd:BAAALAADCgYIBgAAAA==.Fistzak:BAAALAADCggICAAAAA==.',Fl='Flaps:BAAALAADCgYIBgAAAA==.Flidaìs:BAAALAAECgUICAAAAA==.Floriaris:BAAALAADCggICAABLAAECggIFQAHAHEYAA==.',Fo='Folium:BAAALAAECgIIAgAAAA==.Foot:BAAALAADCgMIBAABLAADCgcIDgABAAAAAA==.Forestshaman:BAAALAADCgMIAwAAAA==.Forgotskillz:BAAALAADCgEIAQAAAA==.Forthelast:BAAALAADCgQIAwAAAA==.Fourarmedman:BAAALAAECgIIBAAAAA==.Foxycharsong:BAAALAAECgMIAwAAAA==.',Fr='Freezen:BAAALAADCggIDAAAAA==.Friendship:BAAALAADCgIIAQABLAAECgYIDgABAAAAAA==.Frostibtch:BAAALAADCgcIDQAAAA==.',Fu='Fullmonty:BAAALAADCgcIEQAAAA==.Furor:BAAALAAECgEIAQAAAA==.',['Fã']='Fãide:BAAALAAECgIIAgAAAA==.',Ga='Galfunkel:BAAALAAECgEIAQAAAA==.Gaobot:BAAALAAECgMIAwAAAA==.Garalagon:BAAALAADCgcIDAABLAADCggIFgABAAAAAA==.Garalon:BAAALAADCggIFgAAAA==.Gasanova:BAAALAADCgMIBAAAAA==.Gav:BAAALAADCgEIAQAAAA==.',Ge='Geauxpally:BAAALAADCggIDAAAAA==.Gelleira:BAAALAADCgEIAQAAAA==.Gendo:BAAALAAECgQIBAAAAA==.Genevieve:BAAALAADCgMIAgAAAA==.Gerisch:BAAALAAECgMIBgAAAA==.',Gi='Gigantór:BAAALAAECgYICwAAAA==.Gille:BAAALAAECgMIBwAAAA==.Gizzgnome:BAAALAADCggICAAAAA==.',Gl='Glaive:BAAALAADCgYIBgAAAA==.Glendios:BAAALAADCgcIDAAAAA==.Glumscarred:BAAALAADCggICAABLAAFFAMIBgAIAPgWAA==.Glumwing:BAACLAAFFIEGAAIIAAMI+BaZAQAMAQAIAAMI+BaZAQAMAQAsAAQKgRkAAwMACAg+Iy0DACADAAMACAg+Iy0DACADAAgABQiICSUQAPoAAAAA.Gluttony:BAAALAADCgEIAQAAAA==.',Gn='Gnometua:BAAALAADCggIDAAAAA==.',Go='Goodnights:BAAALAADCgIIAgAAAA==.',Gr='Grakhuntdur:BAAALAAECgMIBwAAAA==.Gratius:BAAALAAECgUIBQAAAA==.Grelli:BAAALAADCggICwABLAADCggIDwABAAAAAA==.',Gu='Gus:BAAALAADCggICAAAAA==.',['Gò']='Gòóse:BAAALAADCgcIBwAAAA==.',Ha='Hallertau:BAAALAADCggIDwAAAA==.Halogens:BAAALAADCggIFAAAAA==.Halon:BAAALAAECgMIBQAAAA==.Handmemychi:BAAALAAECgQIBQAAAA==.Handmemygun:BAAALAAECgEIAQABLAAECgQIBQABAAAAAA==.Hanzhul:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.Hanzumbra:BAAALAAECgcIDQAAAA==.Hard:BAAALAAECgIIAgABLAAECgcIDQABAAAAAA==.Hathemar:BAAALAAECgQIBAAAAA==.',He='Heiliger:BAAALAAECgYICQAAAA==.Hellionfire:BAAALAADCgcIBwAAAA==.Herralea:BAAALAADCgcIBwAAAA==.Herroniden:BAAALAADCgQIBAAAAA==.',Hi='Highghostixd:BAAALAAECgEIAwAAAA==.Hixx:BAAALAAECgMIAwAAAA==.',Ho='Hogan:BAAALAADCggIEQAAAA==.Holylights:BAAALAADCgIIAgABLAADCggIEQABAAAAAA==.Holytroll:BAAALAADCggICgAAAA==.Hoppus:BAAALAADCggIDgAAAA==.',Hu='Hugadin:BAAALAADCggIFAAAAA==.Hukcolo:BAAALAADCgcICgAAAA==.Huldo:BAAALAAECgMIBgAAAA==.Huntardis:BAAALAAECgIIAgAAAA==.Hunteroni:BAAALAADCgIIAgAAAA==.Huntirra:BAAALAADCgYIBgAAAA==.',Hy='Hydraulic:BAAALAAECgMIBwAAAA==.',Ia='Ialôr:BAAALAADCggIDwAAAA==.',Ib='Ibroughtazoo:BAAALAAECgIIAgAAAA==.Ibz:BAAALAAECggIEQAAAA==.',Ic='Icanhealyou:BAAALAADCgIIAgAAAA==.Iceyne:BAAALAADCgcICAAAAA==.Ichibutole:BAAALAAECgMIBAAAAA==.',Ig='Igor:BAAALAADCgMIAwAAAA==.',Il='Iloveaiart:BAAALAADCgcICAAAAA==.',Im='Impowitz:BAAALAADCggIFAAAAA==.',In='Incantata:BAAALAADCgUIBQABLAAECgMIBgABAAAAAA==.Inferiarae:BAAALAAECgMIAwAAAA==.Intera:BAAALAAECgYICgAAAA==.Invicta:BAAALAADCggICAAAAA==.',Ip='Iplaydk:BAAALAADCgYIBwAAAA==.',Ir='Ird:BAAALAAECgQIBgAAAA==.Irishfelocks:BAAALAAECgIIAwAAAA==.Ironsasquash:BAAALAAECgYICwAAAA==.',Is='Isadel:BAAALAADCggICwAAAA==.Isavedu:BAAALAAECgYIDAAAAA==.',It='Ithlord:BAAALAADCggICAABLAADCggIFAABAAAAAA==.Itoshi:BAAALAAECgIIAgAAAA==.',Iv='Ivanmage:BAAALAADCgQIAgAAAA==.Ivanstone:BAAALAADCggICgAAAA==.',Ja='Jaejunip:BAAALAADCggIBwAAAA==.Jaemetrix:BAAALAAECgEIAQAAAA==.Jaiyanaa:BAAALAAECgYIDAAAAA==.Jaydedraven:BAAALAADCgMIAwAAAA==.Jaydog:BAAALAAECgIIAgAAAA==.',Jc='Jcliff:BAAALAADCgYIBgAAAA==.',Je='Jezallyn:BAAALAADCggICQAAAA==.Jezilla:BAAALAAECgMIBAAAAA==.',Ji='Jinah:BAAALAADCgUIBQAAAA==.Jinsu:BAAALAADCggIFgAAAA==.',Jj='Jjaammaal:BAABLAAECoEVAAIJAAgI6CENDAChAgAJAAgI6CENDAChAgAAAA==.',Jo='Jomdkk:BAAALAADCgIIBAAAAA==.Jorkmahnorts:BAAALAADCgYIBgAAAA==.Josselynn:BAAALAAECgEIAQAAAA==.',Ju='Judgernaut:BAAALAADCgcIDgAAAA==.Julia:BAAALAADCgIIAgAAAA==.',Ka='Kaedran:BAAALAADCggICAAAAA==.Kaelashe:BAAALAAECgEIAQAAAA==.Kaelyndrace:BAAALAAECgMIBwAAAA==.Karaktzn:BAAALAAECgIIAgAAAA==.Karonalambnt:BAAALAADCggIDwAAAA==.Kashmeria:BAAALAADCgUIBQAAAA==.Kathell:BAAALAAECgEIAQAAAA==.Kaymyla:BAAALAADCggIEAAAAA==.',Ke='Keeris:BAAALAADCgcICQAAAA==.Keknein:BAAALAAECgYICQAAAA==.Keladia:BAAALAAECgYIBgAAAA==.Kellanthor:BAAALAADCggIEAAAAA==.Kellindor:BAAALAADCgIIAgAAAA==.Kentaris:BAAALAAECgYIDQAAAA==.Keroleaf:BAAALAAECgMIAwAAAA==.Kezrah:BAAALAAECgIIAwAAAA==.',Kh='Khadord:BAAALAADCggIDQAAAA==.Khalano:BAAALAAECgEIAQABLAAECgYIDwABAAAAAA==.Khalu:BAAALAADCgcICgAAAA==.',Ki='Kiergadran:BAAALAAECgMIAwAAAA==.Killgoré:BAAALAADCggICAAAAA==.Killimanjaro:BAAALAAECgYIDQAAAA==.Kind:BAABLAAECoEVAAIKAAgI7hMEFwDzAQAKAAgI7hMEFwDzAQAAAA==.',Kl='Klaezara:BAAALAAECgMIBQAAAA==.Klaezera:BAAALAAECgcIDQAAAA==.Klaz:BAAALAADCgQIBAAAAA==.',Kn='Knaring:BAAALAAECgMIAwAAAA==.Know:BAAALAAECgYICQAAAA==.',Ko='Kolar:BAAALAADCggIFgAAAA==.Kolby:BAAALAADCggIDgAAAA==.Koldions:BAAALAAECgcICQAAAA==.Konasana:BAAALAADCgYIBgAAAA==.Kontin:BAAALAAECgcIDAAAAA==.Kordrollas:BAAALAAECgYICAAAAA==.Kotoari:BAAALAADCgcIBwAAAA==.',Kr='Krapniknil:BAAALAADCgcIDQAAAA==.Kritzah:BAAALAAECgEIAQAAAA==.Krustycorp:BAAALAADCgQIBAAAAA==.',Ku='Kudomaru:BAAALAAECgYICQAAAA==.',Kv='Kvj:BAAALAAECgUICAAAAA==.',La='Laeghlla:BAAALAADCgYICwAAAA==.Laemora:BAAALAAECgYICgAAAA==.Lambox:BAAALAADCgQIBAAAAA==.Lancifer:BAAALAADCgcICgAAAA==.Lanelus:BAAALAAECgMIBQAAAA==.Lararrek:BAAALAAECgMIAwAAAA==.Lardios:BAAALAADCggIDwAAAA==.Lasterdal:BAAALAADCgUIBQAAAA==.Lazmuerte:BAAALAAECggIEgAAAA==.',Le='Leenana:BAAALAADCggIEAAAAA==.Lejaa:BAAALAAECgUIDAAAAA==.Leovan:BAAALAADCgcIBwAAAA==.Lewmie:BAAALAADCgIIAgAAAA==.Leìgh:BAAALAAECgYICwAAAA==.',Li='Liabilibee:BAAALAAECgEIAQAAAA==.Liddaren:BAAALAAECgIIAgAAAA==.Lifestream:BAAALAADCggIDgAAAA==.Lightstarr:BAAALAADCggICAAAAA==.Likalldapus:BAAALAADCgEIAQAAAA==.Likes:BAAALAADCgIIAgABLAADCgcIDgABAAAAAA==.Lissha:BAAALAADCgMIAwAAAA==.',Ll='Llyssa:BAAALAADCgUIBQAAAA==.',Lo='Loavien:BAAALAAECgYICgAAAA==.Loox:BAABLAAECoEVAAMHAAgIcRibDgB/AgAHAAgIcRibDgB/AgAGAAEIegswDQAzAAAAAA==.Loremaker:BAAALAADCgEIAQAAAA==.Lougii:BAABLAAECoEVAAILAAgIHQ2HBgDpAQALAAgIHQ2HBgDpAQAAAA==.',Lt='Ltcrisp:BAAALAADCgYIDQAAAA==.',Lu='Luckiee:BAAALAAECggIEwAAAA==.Luckyone:BAAALAAECgQIBgABLAAECggIEwABAAAAAA==.Ludelan:BAAALAAECgEIAQABLAAECgMIBAABAAAAAA==.',Ly='Lysendra:BAAALAADCgYICwAAAA==.Lytherella:BAAALAAECgIIAwAAAA==.',['Lô']='Lônghorn:BAAALAAECgUICAAAAA==.',Ma='Macah:BAAALAAECgMIAwAAAA==.Madpaladin:BAAALAAECgEIAQAAAA==.Magazine:BAAALAAECgMIAwABLAAECggIFAAKACMcAA==.Mahat:BAAALAADCgcIBwAAAA==.Mairina:BAAALAAECgMIBwAAAA==.Malaki:BAAALAADCgQIBAAAAA==.Malfury:BAAALAAECggICAAAAA==.Mallah:BAAALAAECgIIAwAAAA==.Manado:BAAALAADCggICAAAAA==.Manapuddin:BAAALAAECgMIBAAAAA==.Margareth:BAAALAAECgcIDAAAAA==.Mayo:BAAALAAECgMIBwAAAA==.',Me='Medenut:BAAALAAECgMIBAAAAA==.Megamar:BAAALAAECgEIAgAAAA==.Melkor:BAAALAAECgIIAgAAAA==.Mellarr:BAAALAADCgcIBwAAAA==.Mellowbee:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Methwitch:BAAALAADCgEIAQABLAAECgIIAQABAAAAAA==.',Mi='Mideer:BAAALAADCgcIBwAAAA==.Miilkmagic:BAAALAAECgYIBgAAAA==.Miilomye:BAAALAADCgQIAQAAAA==.Mik:BAAALAAECgYIDAAAAA==.Mikkjeanne:BAACLAAFFIEGAAIMAAMInQiTAwDRAAAMAAMInQiTAwDRAAAsAAQKgRgAAgwACAjcGXURACgCAAwACAjcGXURACgCAAAA.Mildredd:BAAALAAECgMIBQAAAA==.Milesprower:BAAALAAECgIIAgAAAA==.Milim:BAAALAADCgcIBwAAAA==.Mirokü:BAAALAADCgUIBQAAAA==.',Mo='Mooncrowe:BAAALAADCggIDgAAAA==.Moong:BAAALAAECgcIEAAAAA==.Moredoo:BAAALAAECgIIAgABLAAECgYIBwABAAAAAA==.Morganella:BAAALAADCgMIAwAAAA==.Morghan:BAAALAAECgYIDQAAAA==.',Mu='Mukfah:BAAALAADCgMIAwAAAA==.Murashura:BAAALAAECgEIAQAAAA==.Muzzo:BAAALAADCgcIDgAAAA==.',My='Mykulus:BAAALAADCggIFQAAAA==.Myrn:BAAALAADCgMIAwAAAA==.Mythrin:BAAALAADCggIDQAAAA==.',Na='Nadessah:BAAALAADCgEIAQAAAA==.Nahteew:BAAALAAECgMIBgAAAA==.Nardeux:BAAALAAECgEIAQAAAA==.Narozo:BAAALAADCgcICQAAAA==.',Nc='Ncyphon:BAAALAAECgIIAwAAAA==.',Ne='Necromancnt:BAAALAAECgYIDgAAAA==.Necros:BAAALAADCggIDgAAAA==.Nelyar:BAAALAAECgMICQAAAA==.Neokai:BAAALAADCggICAAAAA==.Nephiah:BAAALAAECgMIBwAAAA==.Neshi:BAAALAADCgUIBQAAAA==.',Ni='Niras:BAAALAADCgYIBgAAAA==.Nisgaa:BAAALAAECgMIBwAAAA==.Nissmo:BAAALAAECggICAAAAA==.',No='Noro:BAAALAAECggIEgAAAA==.Norotonement:BAAALAADCgIIAgABLAAECggIEgABAAAAAA==.Norotoxin:BAAALAADCgUIBQAAAA==.Noroxous:BAAALAADCggIFQABLAAECggIEgABAAAAAA==.',Nu='Numbuhone:BAAALAAECgQIBQAAAA==.',Ny='Nyxanunit:BAAALAADCggIDwAAAA==.',Ob='Obamf:BAAALAADCgEIAQAAAA==.',Od='Odarin:BAAALAADCgQIBAAAAA==.',Ol='Oldhome:BAAALAAECgYIBwAAAA==.',Om='Omau:BAAALAAECgMIAwAAAA==.Omux:BAAALAAECgMIBQAAAA==.Omìnous:BAAALAAECgMIBwAAAA==.',On='Onoitshim:BAAALAADCgUIBQAAAA==.Onsteroids:BAAALAAECgQIBQAAAA==.',Or='Orcuss:BAAALAADCgcICAAAAA==.Oruskait:BAAALAADCgcIBwAAAA==.',Ot='Otamatone:BAAALAAECggIEQAAAA==.Otsdarva:BAAALAADCgYIBAAAAA==.',Oz='Ozdragon:BAAALAAECgMIBgABLAAECgcIFAANALsgAA==.Oznah:BAABLAAECoEUAAINAAcIuyDsBQCPAgANAAcIuyDsBQCPAgAAAA==.',Pa='Pakapaka:BAAALAADCgUIBQAAAA==.Paleflow:BAAALAAECgYIBwAAAA==.Pandamoníum:BAAALAAECgYICAAAAA==.Pandemønium:BAAALAADCgYICwAAAA==.Pandorahh:BAAALAAECgIIAgAAAA==.Papasmurfh:BAEALAAECgMIBAAAAA==.Papsfear:BAAALAADCgUIBwAAAA==.Paragan:BAAALAAECgYIDAAAAA==.Paryejah:BAAALAADCgMIAwAAAA==.',Pe='Penetrate:BAAALAAECgYICQAAAA==.Perdition:BAAALAADCgcIDgAAAA==.',Ph='Phoènix:BAAALAADCggICAAAAA==.',Pm='Pmonkey:BAAALAAECgMIBwAAAA==.',Po='Poet:BAAALAADCgYIBwAAAA==.Portorobo:BAAALAAECgMIAwAAAA==.Potshaman:BAAALAAECgMIAgAAAA==.Potshogun:BAAALAAECgEIAQAAAA==.',Pr='Praxitelis:BAAALAADCgcIBwAAAA==.Promithia:BAAALAAECgYIDgAAAA==.',Ps='Psydesho:BAAALAADCgIIAgAAAA==.',Pu='Puffpuffgive:BAAALAADCgYIBgAAAA==.Putricide:BAAALAAECgMIBQAAAA==.',['Pë']='Pëëk:BAAALAAECgMIBQAAAA==.',['Pó']='Póppy:BAAALAAECgYICQAAAA==.',Ra='Raayal:BAAALAAECgQIBgAAAA==.Rachelmariet:BAAALAAECgMIAwAAAA==.Raigen:BAAALAADCggIFAAAAA==.Raiku:BAAALAAECgEIAQAAAA==.Raindròps:BAAALAADCggIDgAAAA==.Ralthor:BAAALAADCgQIBAAAAA==.Rasaja:BAAALAAECgcIDAAAAA==.Raskuall:BAAALAAECgUIBQAAAA==.Ratados:BAACLAAFFIEFAAIOAAMIJQq5AgACAQAOAAMIJQq5AgACAQAsAAQKgRgAAg4ACAi+HewGAMQCAA4ACAi+HewGAMQCAAAA.Rattleballs:BAAALAAECgIIAwAAAA==.Ravspis:BAAALAAECgcIEQAAAA==.',Re='Refnar:BAAALAAECggIEQAAAA==.Regularlegs:BAAALAAECgcIEQAAAA==.Reidknight:BAAALAADCggICAAAAA==.Reinamishima:BAAALAAECgMIBAAAAA==.Rekul:BAAALAAECgMIBAAAAA==.Renlos:BAAALAADCggICAAAAA==.Requyïm:BAAALAAECgIIAgAAAA==.Resolved:BAAALAAECgMIBwAAAA==.',Rh='Rhar:BAAALAADCgcIDAAAAA==.',Ri='Rickyxp:BAAALAADCgcICQABLAAECgYICQABAAAAAA==.Rinovath:BAAALAADCggICAAAAA==.Riproyal:BAAALAAECgYICwAAAA==.Ripwon:BAAALAADCgcIEAAAAA==.',Ro='Roaran:BAAALAADCgUICAAAAA==.Robcamacho:BAAALAADCggIFAAAAA==.Rocha:BAAALAADCgQIBAAAAA==.Rokokos:BAAALAAECgcIEAAAAA==.Ronasaur:BAAALAAECgUIDAAAAA==.Rootevil:BAAALAADCgUIBgAAAA==.Royalpain:BAAALAADCgMIAwAAAA==.',Ru='Rugersonn:BAAALAAFFAIIAgAAAA==.',Ry='Rynella:BAAALAADCgcIDgAAAA==.Ryzix:BAAALAAECgYICQAAAA==.Ryùjin:BAAALAADCgYIBgAAAA==.',['Rå']='Råth:BAAALAADCgYICQAAAA==.',['Rì']='Rìa:BAAALAAECgIIAgAAAA==.',Sa='Sadow:BAAALAADCggICgAAAA==.Sanctitea:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.Sandseyi:BAAALAADCggICAAAAA==.Sanguinos:BAAALAAECgIIAwAAAA==.Sardron:BAAALAADCgQIBAAAAA==.Sastor:BAAALAAECgMIBAAAAA==.Saveon:BAAALAADCggIDwAAAA==.',Sc='Scharhrot:BAAALAAECggIDAAAAA==.Scornhammer:BAAALAAECgYICQAAAA==.',Se='Seigarrow:BAAALAADCgQIBAAAAA==.Seiglìch:BAAALAADCgQIAwABLAAECgEIAQABAAAAAA==.Seinduke:BAAALAAECgcIEAAAAA==.Selastine:BAAALAADCgYIBgAAAA==.Sesnic:BAAALAAECgYIDAAAAA==.',Sh='Shalleth:BAAALAADCgcIDAAAAA==.Shamearthen:BAAALAADCgcIDAAAAA==.Shamrexm:BAAALAAECgIIAwAAAA==.Shande:BAAALAADCgEIAQAAAA==.Shashpal:BAAALAADCgYIBgAAAA==.Shaxet:BAAALAADCggIFQAAAA==.Sheepmeat:BAAALAADCgIIAgABLAADCggIDQABAAAAAA==.Shellpowered:BAAALAAECgEIAQABLAAECgYIDAABAAAAAA==.Shidae:BAAALAAECgYIEgAAAA==.Shintorg:BAAALAAECgYICgAAAA==.Shocksi:BAAALAAECgEIAQAAAA==.Shredzepplin:BAAALAADCgUIBQAAAA==.Shrimpkin:BAAALAAECgQIBAAAAA==.Shàdðw:BAAALAAECgYICgAAAA==.',Si='Sidon:BAAALAAECgYICQAAAA==.Sieben:BAAALAADCggICAAAAA==.Sigmardoom:BAAALAAECgMIAwAAAA==.Silviasaint:BAAALAAECgYICwAAAA==.Sinan:BAAALAAECgUIBwAAAA==.Sini:BAAALAAFFAEIAQAAAA==.Sinseekerz:BAAALAADCggIEQAAAA==.Sirivan:BAAALAADCgcIDwAAAA==.',Sk='Skrebsnop:BAAALAAECgMIBAABLAAECggIGAADAC8mAA==.Skyfel:BAAALAAECgQIAgAAAQ==.',Sl='Slapahoechef:BAAALAAECggIAgAAAA==.Slymey:BAAALAADCggIDwAAAA==.',Sm='Smoldy:BAAALAADCgIIAgAAAA==.Smúrph:BAAALAAECgQICQAAAA==.',Sn='Snaptime:BAAALAAECgMIBQAAAA==.',So='Sokha:BAAALAADCggIDQAAAA==.Sokoo:BAAALAADCggIFAAAAA==.Soliditi:BAAALAADCgMIAwAAAA==.Soteria:BAAALAAECggIDwABLAAFFAIIAgABAAAAAA==.Soulhacker:BAAALAADCgYICAAAAA==.Sovan:BAAALAADCgUIBQAAAA==.',Sp='Sparechange:BAAALAAECgYICQAAAA==.Spartorsalt:BAAALAADCgcIBwAAAA==.Specktral:BAAALAADCggICAAAAA==.Spinachio:BAAALAAECgMIBAAAAA==.',St='Stalkér:BAAALAAECgMIAwAAAA==.Starmetal:BAAALAAECgYICQAAAA==.Steeltemplar:BAAALAAECgYICQAAAA==.Stefanee:BAAALAAECgMIBwAAAA==.Stepp:BAAALAAECggIEQAAAA==.Stickynikki:BAAALAAECgMIAwAAAA==.Ston:BAAALAADCgcICgAAAA==.Stormwrath:BAAALAADCgQIBAABLAAECgcIEAABAAAAAA==.Stralos:BAAALAADCggIFgAAAA==.Strawngarm:BAAALAADCggIDwAAAA==.Stupidhunter:BAAALAAECgMIAwAAAA==.',Su='Subgôd:BAAALAAECgIIAgAAAA==.Succiboi:BAAALAAECggIDAAAAA==.Suciboi:BAAALAAECgYIBgAAAA==.Sufyan:BAAALAAECgYICwAAAA==.Sugastank:BAAALAAECgEIAQAAAA==.Sugreeva:BAAALAAECgEIAQAAAA==.Superpoopie:BAAALAAECgMIAwAAAA==.',Sw='Swagmeister:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.',Sy='Synergee:BAAALAADCgMIAwAAAA==.',['Sé']='Séverus:BAAALAAECgIIAwAAAA==.',['Sê']='Sêrenity:BAAALAADCggIFQAAAA==.',Ta='Tabatsoy:BAAALAAECgMIAwAAAA==.Taggis:BAAALAADCgYIBgAAAA==.Taggus:BAAALAADCggIDwAAAA==.Tallwar:BAAALAAECgQICgAAAA==.Talossus:BAAALAAECggIEQAAAA==.Tanid:BAAALAADCgcIBwAAAA==.Taproot:BAAALAAECgYICQAAAA==.Tarotina:BAAALAADCgUIBQAAAA==.',Te='Tealemental:BAAALAADCgQIBAABLAAECgMIBAABAAAAAA==.Teavie:BAAALAAECgMIBAAAAA==.Teisiama:BAAALAADCgYIBgAAAA==.Telriel:BAAALAAECgMIBAAAAA==.Tenbo:BAAALAAECgYIBQAAAA==.Teren:BAAALAADCgUIBQAAAA==.Terrabrew:BAAALAAECgYICQAAAA==.',Tg='Tgports:BAAALAADCggIDwAAAA==.',Th='Thaeron:BAAALAAECgUICgAAAA==.Thakar:BAAALAAECgYICQAAAA==.Theonidus:BAAALAAECgYIDAAAAA==.Thiccsteve:BAAALAAECgMIAwAAAA==.',Ti='Tigerlily:BAAALAAECgMIAwAAAA==.Tiktokthøt:BAAALAAECgYICAAAAA==.',Tl='Tlucco:BAAALAAECgMIBgAAAA==.',To='Toracina:BAAALAAECgMIBAAAAA==.Tougyu:BAAALAAECgEIAQAAAA==.',Tr='Traskel:BAAALAADCggICAAAAA==.Trav:BAAALAAECgEIAQAAAA==.Treebean:BAAALAAECgIIBAAAAA==.Trenttl:BAAALAADCgUIBwAAAA==.Treydarren:BAAALAADCgcIEgAAAA==.Trike:BAAALAAECgIIAgAAAA==.Trillix:BAAALAADCggIDgAAAA==.Trubanjo:BAAALAADCggIEQAAAA==.',Tu='Tuurok:BAAALAADCgcICgAAAA==.Tuxaloesgay:BAAALAADCgMIBAAAAA==.',Tw='Twigpig:BAAALAADCgUIBQAAAA==.',Ty='Tyrs:BAAALAADCgQIBQAAAA==.',Um='Umbriel:BAABLAAECoEVAAIPAAgI8hytAwC/AgAPAAgI8hytAwC/AgAAAA==.Umokritar:BAAALAADCgcICQAAAA==.',Un='Unthard:BAAALAAECgMIAwAAAA==.',Ur='Urazzaklek:BAAALAADCgEIAQAAAA==.Urnirus:BAAALAAECgIIAwAAAA==.',Ut='Utther:BAAALAADCggIEgAAAA==.',Va='Vaillyinz:BAAALAAECgUIBgAAAA==.Vampnor:BAAALAAECgQICAAAAA==.Vanhelzing:BAAALAADCggIDwAAAA==.Varelin:BAAALAAECgMIAwAAAA==.Varlaeus:BAAALAADCgcIBwABLAAECgMIBwABAAAAAA==.Varlais:BAAALAAECgMIBwAAAA==.',Ve='Veachkidd:BAAALAAECgMIBQAAAA==.Verell:BAAALAAECgYICgAAAA==.',Vi='Vikingstatus:BAAALAADCggIDAAAAA==.Vilma:BAAALAADCgMIAwAAAA==.Vinval:BAAALAADCgQIBAAAAA==.Viracoachdk:BAAALAADCgUIBQAAAA==.',Vo='Volacious:BAAALAADCgMIBgAAAA==.',Vt='Vtck:BAAALAADCgcIEwAAAA==.',Vu='Vulpoopa:BAAALAAECgEIAQAAAA==.Vuttplugg:BAAALAADCgYIBgAAAA==.',Vy='Vybss:BAAALAADCggICQAAAA==.',Wa='Warfe:BAAALAADCgcIDAAAAA==.Washlunk:BAAALAAECgIIAgAAAA==.Waxypad:BAAALAADCggIFgAAAA==.',Wh='Wharph:BAAALAADCgcIDgAAAA==.Whitedahlia:BAAALAAECgMIBgAAAA==.Wholey:BAAALAADCgcIDAAAAA==.',Wi='Wiltedsprout:BAAALAAECgIIAwAAAA==.Winchèster:BAABLAAECoEVAAIHAAgIbRhQDwB3AgAHAAgIbRhQDwB3AgAAAA==.',Wo='Wongo:BAAALAAECggIDwAAAA==.Woodticks:BAAALAADCggIFQAAAA==.',Wr='Wrap:BAAALAADCggICAAAAA==.',Wy='Wysh:BAAALAAECgIIAgAAAA==.',['Wì']='Wìndrush:BAAALAAECgcIEQAAAA==.',Xa='Xavaain:BAAALAAECgMIAwAAAA==.',Xe='Xeleci:BAAALAAECgMIBwAAAA==.',Xy='Xyrrath:BAAALAAECgEIAQAAAA==.',Ya='Yallos:BAAALAADCgMIAwABLAADCgcICgABAAAAAA==.Yamon:BAAALAAECgIIAwAAAA==.Yashipha:BAAALAAECgEIAQAAAA==.',Ye='Yevven:BAAALAADCgUIBQAAAA==.',Ys='Ysalia:BAAALAAECgIIAwAAAA==.Yserro:BAAALAADCgMIAwAAAA==.',Yu='Yue:BAAALAAECgcIDQAAAA==.Yulmegerth:BAAALAAECgEIAQAAAA==.Yurthong:BAAALAADCgcIBwAAAA==.',['Yô']='Yôoo:BAAALAADCgYIBgAAAA==.',['Yø']='Yørunøchi:BAAALAADCgUIBwAAAA==.',Za='Zalzaki:BAAALAADCggICAAAAA==.Zaraky:BAAALAADCgUIBgAAAA==.Zargond:BAAALAADCggIDwAAAA==.Zart:BAAALAADCggIEAAAAA==.',Ze='Zenithcia:BAAALAAECgUIBgAAAA==.Zerenitynow:BAAALAAECgMIBwAAAA==.',Zi='Zigzags:BAAALAADCggIFQAAAA==.Zilyn:BAAALAAECgMIBAAAAA==.',Zo='Zookeeper:BAAALAADCgcICQAAAA==.',Zr='Zraidn:BAAALAAECgIIAwAAAA==.Zromaverick:BAAALAAECgcIDQAAAA==.',Zy='Zyella:BAAALAADCgcIBwAAAA==.Zylara:BAAALAAECgEIAQAAAA==.Zyrenor:BAAALAAECgYIDQAAAA==.',['Àr']='Àrthäs:BAAALAADCgMIAwAAAA==.',['Ðu']='Ðungeon:BAAALAAECgMIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end