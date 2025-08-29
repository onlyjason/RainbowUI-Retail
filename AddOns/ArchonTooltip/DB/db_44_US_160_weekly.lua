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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','DeathKnight-Blood','DemonHunter-Vengeance','Druid-Guardian','Paladin-Protection','Monk-Mistweaver','Druid-Restoration','Paladin-Holy','Rogue-Assassination',}; local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Abigor:BAAALAADCgYICAAAAA==.Abriser:BAAALAAECgYICQAAAA==.',Ac='Acttaeon:BAAALAAECgcIEQAAAA==.',Ae='Aesthetic:BAAALAAECggIEgAAAA==.',Af='Afflicting:BAAALAADCgcICAAAAA==.',Aj='Ajaxprime:BAAALAAECgcIDgAAAA==.',Al='Alerion:BAAALAADCggIEQAAAA==.Alesîa:BAAALAADCgcIBwAAAA==.Alfabika:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.',Am='Ameliia:BAAALAADCgYIBgAAAA==.Amrën:BAAALAAECgYICQABLAAECggIAQABAAAAAA==.Amyadams:BAAALAADCgQIBAAAAA==.',An='Andersand:BAAALAAECgMIAwAAAA==.Angrybow:BAAALAAECgUIBQAAAA==.Animalhouse:BAAALAAECgYICQAAAA==.Anshu:BAAALAADCggIDwAAAA==.',Ap='Ape:BAAALAADCgQIBAAAAA==.',Ar='Arcelon:BAAALAAECgEIAQAAAA==.Arcelorz:BAAALAAECgYICQAAAA==.',At='Athren:BAAALAAECgEIAQAAAA==.',Au='Autist:BAAALAADCggIDgAAAA==.',Az='Azmun:BAAALAAECgcIDQABLAAECgcIDQABAAAAAA==.Azmunn:BAAALAAECgcIDQAAAA==.Azri:BAAALAADCggIFwAAAA==.',Ba='Bannedname:BAAALAADCggICQABLAADCggIEwABAAAAAA==.Barakoshamma:BAAALAADCggICAAAAA==.Barbiee:BAAALAADCgUIBwAAAA==.',Be='Bellámuerté:BAAALAAECgYICQAAAA==.Bemmy:BAAALAADCgcIBwABLAAECgYICAABAAAAAA==.Benjie:BAAALAADCggICAAAAA==.Bergamot:BAAALAADCggICAAAAA==.Beru:BAAALAADCgEIAQAAAA==.',Bi='Biggsdk:BAAALAADCggICAAAAA==.Biggsx:BAAALAAECgYICgAAAA==.Bika:BAAALAAECgMIBQAAAA==.',Bl='Blazinbubble:BAAALAAECgMIAwAAAA==.Bloodlordzz:BAAALAAECgEIAQAAAA==.Bloodreina:BAAALAAECgYICgAAAA==.',Bo='Bootyhunting:BAAALAADCggIDwABLAAECggIEQABAAAAAA==.Bowknight:BAAALAAECgYICQAAAA==.',Br='Brdua:BAAALAAECgIIAgAAAA==.Brewhands:BAAALAAECgIIAgAAAA==.',Bu='Bulkazar:BAAALAAECgYIDgAAAA==.Burblegobble:BAAALAADCggIEQAAAA==.Burbuja:BAAALAAECgYICwAAAA==.Burninghands:BAAALAAECgIIAgAAAA==.',Bw='Bwonsamdii:BAAALAAECgQICQAAAA==.',Ca='Callabash:BAAALAAECgYIDQAAAA==.Cameltotemx:BAAALAAECggIEQAAAA==.Cazzik:BAAALAADCgUIBQAAAA==.',Ce='Celarena:BAAALAAECgMIAwAAAA==.',Ch='Cherushi:BAAALAAECgEIAQAAAA==.Chiaki:BAAALAADCgcIBwAAAA==.Chickfila:BAAALAAECgIIAgAAAA==.Chilla:BAAALAAECgQIBQAAAA==.Chomrogg:BAAALAAECgQIBAAAAA==.Choubelle:BAAALAAECgIIAgAAAA==.Chzdk:BAAALAAFFAMIBAAAAA==.Chzoldman:BAAALAAECggICAABLAAFFAMIBAABAAAAAA==.',Co='Coddler:BAAALAAECgcIDgAAAA==.Cowkitty:BAAALAAECgIIAgAAAA==.',Cr='Crabsurd:BAAALAAECgMIBAAAAA==.Crashandburn:BAAALAADCgUIBAAAAA==.Crashdots:BAAALAADCgEIAQAAAA==.Crockito:BAACLAAFFIEGAAICAAMI0yVtAQBOAQACAAMI0yVtAQBOAQAsAAQKgRgAAgIACAhtJrwAAH8DAAIACAhtJrwAAH8DAAAA.',Cy='Cymist:BAAALAAECggIEQAAAA==.Cyrusdavirus:BAAALAADCggIDwAAAA==.',Da='Danto:BAAALAADCgMIAwABLAAECgYICQABAAAAAA==.Daìsy:BAAALAAECgMIBQAAAA==.',De='Decias:BAAALAAECgcIDgAAAA==.Deemo:BAAALAADCgcIBwABLAADCgcICQABAAAAAA==.Delphyne:BAAALAADCgcIBwAAAA==.Depoprovera:BAAALAAECgcIEQAAAA==.Deqz:BAAALAAECgYICAAAAA==.Derzelas:BAAALAADCgYIBgAAAA==.Dezi:BAAALAADCggICAAAAA==.',Dh='Dhoko:BAAALAAECgYIBwAAAA==.',Di='Dilly:BAAALAAECgcIDQAAAA==.Dilox:BAAALAADCgcIBwAAAA==.Disaaya:BAAALAAECgUIBQAAAA==.Disciplina:BAAALAAECgYICQAAAA==.',Dj='Djao:BAAALAAECgIIAgAAAA==.',Dm='Dmonicknight:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.',Do='Doodlebug:BAABLAAECoEWAAIDAAgIuRy4AwCbAgADAAgIuRy4AwCbAgAAAA==.Dooshrocket:BAAALAADCgUIBQAAAA==.Dowzer:BAAALAADCgcIBwAAAA==.Doxxz:BAAALAAECgUIBwAAAA==.',Dr='Dracuujin:BAAALAAFFAIIAgAAAA==.Draeyen:BAAALAADCgcIBwAAAA==.Dreanil:BAAALAAECgMIAwAAAA==.Druidknight:BAAALAAECgEIAgAAAA==.',Du='Durbekbek:BAAALAAECgMIAwAAAA==.',Dy='Dyeuhreeuh:BAAALAAECgMIAwAAAA==.',['Dâ']='Dârn:BAAALAAECgYICQAAAA==.',Ed='Edesmor:BAAALAAECgMIBwAAAA==.',El='Elissra:BAAALAAECgYIDAAAAA==.Elpristo:BAAALAADCggICAAAAA==.',Er='Erebus:BAAALAAECgEIAgAAAA==.Erzza:BAAALAAECgYICAAAAA==.',Es='Esotericzeo:BAAALAADCgYIBgAAAA==.',Ev='Everbear:BAAALAAECgMIBQAAAA==.Evilpaladin:BAAALAADCgEIAQABLAAECgYICQABAAAAAA==.Evilpriest:BAAALAAECgYICQAAAA==.',Ex='Exconvito:BAAALAADCgQIBAAAAA==.',Fl='Flappii:BAAALAAECgUICgAAAA==.Flappyfuros:BAAALAAECgYICQAAAA==.Fluffykat:BAAALAAECgEIAQAAAA==.Flurallan:BAAALAADCgIIAgAAAA==.',Fr='Frank:BAAALAADCgIIAgAAAA==.Freezypoofs:BAAALAAECgYICQAAAA==.',Fu='Furrykane:BAEALAADCgcIBwABLAAECgYIDAABAAAAAA==.Furyhands:BAAALAAECgIIAgAAAA==.Future:BAAALAAECgcICwAAAA==.',Ga='Gazblin:BAAALAADCggIEwAAAA==.Gazbow:BAAALAADCggIDwABLAADCggIEwABAAAAAA==.Gazmo:BAAALAADCgYIBgABLAADCggIEwABAAAAAA==.',Ge='Gertielovesu:BAAALAAECgMIBAAAAA==.',Gi='Gigglefack:BAAALAAECgcIDQAAAA==.Ginshan:BAABLAAECoEUAAIEAAgI3SPgAAA7AwAEAAgI3SPgAAA7AwAAAA==.',Gn='Gnar:BAAALAAECgIIBAAAAA==.Gno:BAAALAADCggICAAAAA==.',Go='Gobbleburble:BAAALAADCgcIBwAAAA==.Gololokjek:BAAALAADCgYIBgAAAA==.Goobe:BAAALAADCggIDwABLAAECgYICAABAAAAAA==.',Gr='Gromlo:BAAALAAECgYICQAAAA==.Growho:BAABLAAFFIEFAAIFAAMI7Q09AADbAAAFAAMI7Q09AADbAAAAAA==.Grulog:BAAALAADCgcIDgAAAA==.',Gu='Guldav:BAAALAAECggIEAAAAA==.Gunny:BAAALAAECgYICQAAAA==.Guucci:BAAALAAECgEIAQAAAA==.Guuccí:BAAALAAECgEIAQAAAA==.',['Gô']='Gôthic:BAAALAAECgMIBgAAAA==.',Ho='Honortheox:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Hootree:BAAALAAECgcIDgAAAA==.Howdy:BAAALAAECgMIBAAAAA==.',Hu='Huntemall:BAAALAAECgMIBQAAAA==.Hurdis:BAAALAADCggIFAAAAA==.',Hy='Hypaxia:BAAALAAECggIAQAAAA==.',Ic='Iceshards:BAAALAAECgMIBAAAAA==.',Id='Idtrapthat:BAAALAADCgYICQAAAA==.',Il='Illidank:BAAALAAECggIEQAAAA==.Illidanknite:BAAALAADCggICAABLAAECggIEQABAAAAAA==.Illirothas:BAAALAAECgMIAwABLAAECgMIBQABAAAAAA==.',Im='Imaredflag:BAAALAAECgIIAgABLAAFFAMIBQAGAAgiAA==.Imen:BAAALAAECgYICQAAAA==.Imhealarious:BAAALAAECgYIDAAAAA==.',In='Inertia:BAABLAAECoEXAAIHAAcIaR/zEQBdAQAHAAcIaR/zEQBdAQAAAA==.Infectedbøb:BAAALAADCggICAAAAA==.Infätuation:BAAALAAECgQIBAAAAA==.',Io='Iolite:BAAALAADCggIEAAAAA==.',Is='Ispitmagic:BAAALAAECgIIAgAAAA==.',Iv='Ivalice:BAAALAAECgYIDQAAAA==.',Ja='Jafbe:BAAALAADCggIFgAAAA==.Jakethedawg:BAAALAAECgYIBwAAAA==.',Je='Jerkthedog:BAAALAAECgMIAwAAAA==.',Ji='Jinbe:BAAALAAECgYICQAAAA==.',Jo='Joslin:BAAALAADCggIEwABLAAECggIEQABAAAAAA==.',Ju='Jumbosize:BAABLAAECoEYAAIIAAgIDSIlAwDjAgAIAAgIDSIlAwDjAgAAAA==.Junrage:BAAALAAECgcIDAAAAA==.Jupîter:BAAALAAECgYICQAAAA==.Justmeldit:BAAALAADCggIEAAAAA==.',Ka='Kalastrian:BAAALAAECgYICQAAAA==.Karateshock:BAAALAAECgcICwAAAA==.Kariah:BAAALAAECgYIDAAAAA==.Karlmarks:BAAALAADCgEIAQAAAA==.Kasyllaa:BAAALAADCgEIAQABLAAECgMIBQABAAAAAA==.Katyharris:BAAALAADCgQIBAAAAA==.Kazuren:BAAALAAECgYICQAAAA==.',Ke='Kelia:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.Kelinna:BAAALAADCggIFgAAAA==.Kennidan:BAAALAAECgMIAwAAAA==.Keola:BAAALAADCgIIAgAAAA==.',Kf='Kfcchicken:BAAALAADCgYIBgAAAA==.',Ki='Kiritoo:BAAALAAECggIAQABLAAECggICAABAAAAAA==.Kirker:BAAALAAECgYICQAAAA==.',Ko='Kodabonk:BAAALAAECgYICQAAAA==.Kodanorth:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Kokoa:BAAALAADCggICAAAAA==.',Kr='Kraur:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.',Ku='Kuramaa:BAAALAADCggIFQAAAA==.',La='Lamlam:BAAALAAECgYIBwAAAA==.Lammp:BAAALAAECgIIAgAAAA==.Landar:BAAALAAECgIIAgABLAAECgYIDQABAAAAAA==.Lathsong:BAAALAADCgMIAwAAAA==.Lavadosh:BAAALAADCgcIBwAAAA==.Laws:BAAALAADCggIDwAAAA==.Layonpayens:BAAALAADCgYICgABLAAECgcIDAABAAAAAA==.',Le='Leavia:BAAALAADCggIDgAAAA==.Leshwi:BAAALAADCggIEAAAAA==.',Li='Liaeda:BAAALAAECgMIBQAAAA==.Lianshi:BAAALAADCggIDwAAAA==.Lilshizzle:BAAALAADCgcICQAAAA==.Liquify:BAAALAAECgYICAAAAA==.',Lo='Loosie:BAAALAAECgcIDgAAAA==.',Lu='Lugnuts:BAAALAADCgcICQAAAA==.Lukethenuke:BAAALAAECgUIBQAAAA==.Luketich:BAABLAAECoEXAAIJAAgIVhwbBQCFAgAJAAgIVhwbBQCFAgAAAA==.Lumiltiand:BAAALAAECggICAAAAA==.',Ly='Lydmillial:BAAALAADCgcIBwAAAA==.',Ma='Mac:BAAALAADCgMIAwAAAA==.Mad:BAAALAAECgMIAwAAAA==.Malgrendin:BAAALAAECgYICgAAAA==.Manuall:BAAALAAECgMIBQAAAA==.Maralyn:BAAALAAECgQICAAAAA==.Marcasite:BAAALAADCgUIBQAAAA==.Marevin:BAAALAADCgIIAgAAAA==.Martense:BAAALAADCgcIDQAAAA==.Marvala:BAAALAADCggIGAAAAA==.Materialist:BAAALAAECgcIEAAAAA==.Maxidh:BAAALAAECgcIEgAAAA==.Maxidk:BAAALAADCgcIBwAAAA==.',Mc='Mcbearpig:BAAALAADCggICAAAAA==.',Me='Medrunk:BAAALAAECgMIBwAAAA==.Mercknight:BAAALAADCgEIAQAAAA==.',Mi='Midgemaisel:BAAALAAECgEIAQAAAA==.Ministryy:BAAALAADCgcICQAAAA==.Mirado:BAAALAAECgYICQAAAA==.Misticknight:BAAALAAECgIIAgAAAA==.',Mo='Moochie:BAAALAAECgMIAwAAAA==.Mordrion:BAAALAADCggICgAAAA==.Morrygan:BAAALAAECgYICQAAAA==.Mortarien:BAAALAAECgEIAQAAAA==.Mortïx:BAAALAAECgcIDAAAAA==.',My='Myrtle:BAAALAAECgYICAAAAA==.',Na='Naznax:BAAALAAECgcICgAAAA==.',Ne='Necrophobic:BAAALAAECgIIAgAAAA==.Nexeoh:BAAALAAECgQIBwAAAA==.Nexflame:BAAALAAECgYICAAAAA==.',Ni='Nineinchnuts:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Niust:BAAALAADCgcIDQAAAA==.Niwatori:BAAALAAECgEIAQAAAA==.',No='Nolarz:BAACLAAFFIEHAAIKAAQIvx92AACUAQAKAAQIvx92AACUAQAsAAQKgRcAAgoACAieJL8BAEADAAoACAieJL8BAEADAAAA.Norbon:BAAALAADCggIEAAAAA==.Nosho:BAAALAAECgYICQAAAA==.',Nu='Nukthom:BAAALAAECgMIAwAAAA==.',Ny='Nyche:BAAALAADCgYIBgAAAA==.Nyneaves:BAAALAAECgYICAAAAA==.',['Në']='Nëisha:BAAALAADCgQIBAAAAA==.',Oc='Occultknight:BAAALAAFFAEIAQAAAA==.',Oh='Ohmenwah:BAAALAADCgYICAAAAA==.',Oj='Ojpyroblast:BAAALAAECgYIDwAAAA==.',Ol='Olmilkeyes:BAAALAAECgIIAgAAAA==.',Om='Omghunter:BAAALAAECgIIAgAAAA==.',On='Onisprite:BAAALAAECgIIAgAAAA==.',Oo='Oogal:BAAALAAECgMIAwAAAA==.',Or='Ordhah:BAAALAAECgYIBwAAAA==.',Ox='Oxyhottin:BAAALAAECgYICgAAAA==.',Pa='Padding:BAAALAADCgcIBwAAAA==.Padrehoof:BAAALAAECggIEgAAAA==.Pagez:BAAALAAECgEIAQAAAA==.Pakhan:BAAALAAECgUICQAAAA==.Pallo:BAAALAADCgcICQAAAA==.Paona:BAAALAAECgMIBQAAAA==.',Pe='Peraroll:BAAALAAECgcIEAAAAA==.Permafròst:BAAALAAECgYICgAAAA==.',Ph='Phenphen:BAAALAAECgYIBQAAAA==.Phuryphen:BAAALAAECgMIAwABLAAECgYIBQABAAAAAA==.Physicyan:BAAALAAECgUIBQAAAA==.',Pi='Piakchu:BAAALAADCggICwAAAA==.',Po='Pogster:BAAALAADCgYIBgAAAA==.Polaritybit:BAAALAADCgcICAAAAA==.Pookie:BAAALAADCggIDwAAAA==.Poseidôn:BAAALAAECgQIBwAAAA==.',Pr='Prïest:BAAALAAECgIIAgABLAAECgYIBwABAAAAAA==.',Ps='Psych:BAAALAADCggIDgAAAA==.',Pu='Pugnifacent:BAAALAAECggICAAAAA==.Pumaa:BAAALAAECgYIDQAAAA==.',Qu='Quelissa:BAAALAAECggICAAAAA==.',Ra='Raeyn:BAAALAAECgQIBAAAAA==.Raise:BAAALAADCggICAAAAA==.Rayssa:BAAALAAECgcICwAAAA==.',Re='Redeker:BAAALAAECgYICQAAAA==.Remorsous:BAAALAAECgMIAwAAAA==.Renardfurtif:BAAALAADCggIDgAAAA==.Rentahunter:BAAALAADCggIEAABLAAECgMIAwABAAAAAA==.Reset:BAAALAAECgEIAQABLAAECggIEgABAAAAAA==.Revax:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Revlonghorn:BAAALAAECgIIAgAAAA==.',Ri='Rimasjobas:BAAALAAECgEIAgAAAA==.Rimestar:BAAALAAECgIIAgAAAA==.Ripoodoo:BAAALAADCgcICAAAAA==.Risenhands:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.',Ro='Rockhard:BAAALAAECgMIAwAAAA==.Roguewolf:BAAALAAECgYIBwAAAA==.Rolow:BAAALAAECgcICwAAAA==.Rooni:BAAALAAECgUIBQABLAAFFAMIAwABAAAAAA==.Roony:BAAALAAFFAMIAwAAAA==.',Ru='Rush:BAAALAAECgYICQAAAA==.',Ry='Rymik:BAAALAAECgYICQAAAA==.Rysxn:BAAALAAECgYIDgAAAA==.Ryujins:BAAALAADCggICAAAAA==.Ryuujins:BAAALAAECggICwABLAAFFAIIAgABAAAAAA==.',['Rî']='Rîme:BAAALAADCgIIAgAAAA==.',Sa='Sahiri:BAAALAAECgcIDAAAAA==.',Sc='Schreckstoff:BAAALAADCgcICAAAAA==.',Se='Selinie:BAAALAADCgIIAgAAAA==.Senari:BAAALAAECgYICAAAAA==.',Sh='Shabangus:BAAALAAECgYICQAAAA==.Shadowblazer:BAAALAAECgYIDAAAAA==.Shamaloo:BAAALAADCgUIBAAAAA==.Shamansays:BAAALAAECgcICwAAAA==.Shamphen:BAAALAAECgMIAwAAAA==.Shanda:BAAALAAECggIEgAAAA==.Shanto:BAAALAAECgYICQAAAA==.Shaz:BAAALAADCgYIBgAAAA==.Sheesh:BAAALAAECgYICQAAAA==.Shiftinmojo:BAAALAAECgMIBwAAAA==.Shpongolia:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.',Si='Siee:BAAALAAECgEIAgAAAA==.',Sk='Skullbriar:BAAALAAECgIIAgAAAA==.',Sl='Sleepingtank:BAAALAAECgYIDAAAAA==.',Sn='Snkypetrah:BAAALAAECgIIAgAAAA==.',So='Somi:BAAALAADCgYIBgAAAA==.',Sp='Spittle:BAAALAADCggICAABLAAECggIFwAJAFYcAA==.',St='Stabbaran:BAAALAADCgcIBwAAAA==.Stamen:BAAALAADCgYIBgAAAA==.Stankflap:BAAALAADCggIFQAAAA==.Stavvi:BAAALAAECgIIAgAAAA==.Steviewonder:BAAALAAECgcIBwABLAAECgYIDwABAAAAAA==.Stoick:BAAALAADCgUIBQAAAA==.Stoly:BAAALAADCgUIBgAAAA==.Stonatroll:BAAALAAECgMIBQAAAA==.Stormdemon:BAAALAAECgYICwAAAA==.Stormspellz:BAAALAAECgYICQAAAA==.',Su='Supay:BAAALAAECgEIAQAAAA==.Supdaug:BAAALAAECgUIBQAAAA==.',Ta='Talos:BAAALAAECgYICAABLAAECgYICgABAAAAAA==.Tanktax:BAACLAAFFIEFAAIGAAMICCKCAAA6AQAGAAMICCKCAAA6AQAsAAQKgRgAAgYACAhhJlgAAIADAAYACAhhJlgAAIADAAAA.Taraelle:BAAALAADCgQIBAAAAA==.Taraza:BAAALAAECgYICwAAAA==.Tarkinal:BAAALAAECgMIBwAAAA==.',Te='Teildreu:BAAALAADCggIDQAAAA==.Teitterdrud:BAAALAADCgIIAgAAAA==.Telina:BAAALAAECggIAgAAAA==.Temetnosce:BAAALAAECgYICAAAAA==.Tenderhoof:BAAALAADCggIEAAAAA==.Tenebros:BAAALAAECgMIBQAAAA==.Terrorish:BAAALAAECgYICwAAAA==.Tetri:BAAALAADCgYIBgAAAA==.',Th='Thanatus:BAAALAADCgcICgAAAA==.Thearatwo:BAAALAAECggICAAAAA==.Thevinny:BAAALAADCgcIDQAAAA==.Thurm:BAAALAADCgQIBAAAAA==.',Ti='Tickz:BAAALAAECgcICwAAAA==.Tidalviz:BAAALAAECgYIBwAAAA==.Tifä:BAAALAADCgQIBAAAAA==.',To='Toebeans:BAAALAAECgMIAwABLAAECgcIEgABAAAAAA==.Toeran:BAAALAAECgYICAAAAA==.Toes:BAAALAAECgcIEgAAAA==.Toobe:BAAALAAECgIIAgAAAA==.',Tr='Tread:BAAALAAECgIIAgAAAA==.Trickee:BAAALAAECgIIAgABLAAECgIIAgABAAAAAA==.Trundell:BAAALAAECgcIEgAAAA==.',Tu='Turboswag:BAAALAAECgYICwAAAA==.',Ty='Tyindril:BAAALAADCgQIBAAAAA==.Tymertee:BAAALAADCgIIAgAAAA==.Tyria:BAAALAAECgEIAwAAAA==.',['Tÿ']='Tÿy:BAAALAAECgQIBAAAAA==.',Un='Undertõw:BAAALAADCgcIBwAAAA==.',Ur='Urabrask:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Va='Valakin:BAAALAADCgMIAwAAAA==.Varsil:BAAALAAECgMIAwAAAA==.Vashstampede:BAAALAAECgQICQAAAA==.',Ve='Velrik:BAAALAAECgIIAgAAAA==.Vezkin:BAAALAAECggIEgAAAA==.',Vg='Vghost:BAAALAADCggIDAAAAA==.',Vi='Vibzz:BAAALAADCgEIAQABLAADCgcICQABAAAAAA==.Vintictae:BAAALAADCggIDQAAAA==.Virtus:BAAALAADCgYICAAAAA==.',Vo='Voidknight:BAAALAADCgYIBgAAAA==.Vostok:BAAALAADCgEIAQAAAA==.',Wa='Wargain:BAAALAADCgUIBQAAAA==.Warlex:BAAALAADCgMIBQAAAA==.',We='Wealthyscaly:BAAALAADCgcIBwAAAA==.Werse:BAAALAAECgYICQAAAA==.Wetloginyou:BAAALAADCgIIAgAAAA==.',Wi='Willowdusk:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Willowmist:BAAALAADCgMIAwABLAAECgIIAgABAAAAAA==.Willtolive:BAAALAADCgEIAgABLAAECgMIBQABAAAAAA==.Witt:BAAALAAECgMIAwAAAA==.',Wk='Wkane:BAEALAAECgYIDAAAAA==.Wkdjôker:BAAALAADCggICAAAAA==.',Wr='Wrathofchaos:BAAALAADCgUIBQAAAA==.',Xa='Xakta:BAAALAADCgQIBAAAAA==.',Ya='Yani:BAAALAADCgcIDgAAAA==.',Ye='Yeraleth:BAAALAAECgQIBwAAAA==.',Yi='Yisiwang:BAAALAADCggICgAAAA==.',Yo='Yorkj:BAAALAAECgIIAgAAAA==.Youswanna:BAAALAADCgcIEgAAAA==.Yoyol:BAAALAAECgEIAgAAAA==.',Za='Zalthorax:BAAALAADCgYICwABLAAECgMIBQABAAAAAA==.Zatilion:BAAALAAECgYICgAAAA==.',Ze='Zeal:BAAALAAECgMIAwAAAA==.Zeh:BAAALAADCggICgAAAA==.Zekelius:BAAALAADCgIIAgAAAA==.Zenki:BAAALAADCggICwAAAA==.Zenny:BAAALAAECgMIAwAAAA==.Zenyra:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.',Zi='Ziggamoo:BAAALAADCgcICAABLAAECgYICAABAAAAAA==.Ziggashot:BAAALAAECgYICAAAAA==.Zipoo:BAAALAADCggIEAAAAA==.',Zo='Zoromaak:BAAALAAECgYIDAAAAA==.',Zu='Zukiel:BAAALAAECgUIBQAAAA==.Zurahahshá:BAAALAAECgMIAwAAAA==.Zuwin:BAAALAADCggIEgAAAA==.',['Ðr']='Ðrow:BAAALAAECgYIDAAAAA==.',['Óx']='Óxy:BAAALAADCgQIBAAAAA==.',['Ör']='Örin:BAAALAADCgcICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end