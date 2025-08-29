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
 local lookup = {'Unknown-Unknown','Rogue-Subtlety','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery',}; local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Advisor:BAAALAAFFAEIAQAAAA==.',Ae='Aerius:BAAALAADCgcIBwAAAA==.',Ah='Ahnkho:BAAALAADCgcICwAAAA==.',Ai='Ainon:BAAALAADCgcIBwAAAA==.',Ak='Akarm:BAAALAADCgcIBwAAAA==.',Am='Amandakk:BAAALAADCgcIDgAAAA==.Aminime:BAAALAAECgEIAQAAAA==.',An='Ananix:BAAALAADCgUIBQAAAA==.Anavailable:BAAALAADCgIIAgAAAA==.Andy:BAAALAADCggICAAAAA==.Angelicuss:BAAALAADCgYIBgABLAAECgUICAABAAAAAA==.',Aq='Aqulissa:BAAALAADCgUIBQAAAA==.',Ar='Arolder:BAAALAAECgMIBQAAAA==.Artlerath:BAAALAADCgUIBQAAAA==.',As='Ashkraft:BAAALAAECgMIAwAAAA==.',Az='Azcowboy:BAAALAADCgcICAAAAA==.Azshuna:BAAALAADCggICAAAAA==.',Ba='Bananie:BAAALAAECgIIAgAAAA==.Bankus:BAAALAAECgEIAgAAAA==.Barakka:BAAALAAECgIIAgAAAA==.Barelor:BAAALAADCgcICwAAAA==.Barir:BAAALAADCgcICQAAAA==.Barraka:BAAALAADCgcIBwAAAA==.Batmân:BAAALAADCgcIFAAAAA==.',Bb='Bbite:BAAALAAECgYIBgAAAA==.',Be='Beezy:BAAALAAECgMIBQAAAA==.',Bi='Bigjon:BAAALAAECgEIAQAAAA==.',Bl='Blessa:BAAALAAECgMIBQAAAA==.Bloomzy:BAAALAADCggIEgAAAA==.',Bo='Boombástic:BAAALAAECgYICQAAAA==.Boomco:BAAALAAECgMIAwAAAA==.Bootes:BAAALAAECgMIBAAAAA==.',Br='Brawny:BAAALAAECgMIAwAAAA==.Breeti:BAAALAAECgIIBAAAAA==.Briana:BAAALAADCgcICQAAAA==.Broadside:BAAALAAECgUIBQAAAA==.Broin:BAAALAADCgcIBwAAAA==.Broshots:BAAALAADCgQIBwAAAA==.Bryda:BAAALAADCgcIBwAAAA==.',Bu='Bubukityfuc:BAAALAADCggIDgABLAAECgYICgABAAAAAA==.Bundy:BAAALAADCggICQAAAA==.',Ca='Cajbo:BAAALAAECgMIBQAAAA==.Calyssa:BAAALAAECgUIBgAAAA==.Carpe:BAAALAADCgMIAwABLAADCgcIBwABAAAAAA==.Cartan:BAAALAAECgMIAwAAAA==.Cat:BAAALAAECgYIBgAAAA==.Cayeth:BAAALAADCggICAAAAA==.',Ch='Cheetos:BAAALAADCgcIDgAAAA==.Chunlee:BAAALAAECgMIBgAAAA==.',Cl='Cloudseeker:BAAALAADCgcIBwAAAA==.Clu:BAAALAADCgcIBwAAAA==.',Cr='Creepnroll:BAAALAAECgIIAgAAAA==.Creslan:BAAALAADCgcIBwABLAAECgUICAABAAAAAA==.',Ct='Ctrlaltdk:BAAALAAECgYICAAAAA==.',Cu='Cuttie:BAAALAADCgYIBgAAAA==.',Cy='Cyrax:BAAALAAECggIDQAAAA==.Cyser:BAAALAAECgEIAQAAAA==.',Da='Dahgrimza:BAAALAAECgQIBgAAAA==.Dalna:BAAALAAECgMIBAAAAA==.Daranoth:BAAALAADCgcICQAAAA==.Darklürker:BAAALAADCggIDgAAAA==.Dasthodan:BAAALAADCgIIAgAAAA==.',Dc='Dctrpepper:BAAALAADCgcIFQAAAA==.',De='Deadpool:BAAALAAECgMIAwAAAA==.Deilliann:BAAALAAECgMIBQAAAA==.Demonica:BAAALAAECgMIAwAAAA==.Demonky:BAAALAADCgEIAQABLAADCgMIAwABAAAAAA==.Devick:BAAALAADCggICAAAAA==.',Di='Dinta:BAAALAAECgYICwAAAA==.Discostu:BAAALAADCgcIBwAAAA==.',Do='Dominoes:BAAALAAECgEIAQAAAA==.Domìnion:BAAALAADCggIEAAAAA==.Donara:BAAALAADCgcIDAAAAA==.Dovahhun:BAAALAADCgYIBgAAAA==.',Dr='Drainny:BAAALAADCggICAAAAA==.Drakth:BAAALAADCgcIEwAAAA==.Dreadedmurph:BAAALAADCgQIBAAAAA==.Dreadhex:BAAALAAECgQIBgAAAA==.Drekava:BAAALAADCgUIBQAAAA==.Drktoon:BAAALAAECgIIAgAAAA==.',Du='Duffmyster:BAAALAAECgMIAwAAAA==.Dumbocity:BAAALAAECgMIBgAAAA==.',Dy='Dyss:BAAALAADCgcIBwAAAA==.Dystotez:BAAALAAECgMIBQAAAA==.',Ea='Earthshield:BAAALAADCggICAAAAA==.',Ed='Edinth:BAAALAAECgYICgAAAA==.',El='Ellaana:BAAALAAECgMIAwAAAA==.Elotarra:BAAALAADCgMIAwAAAA==.',Er='Eriko:BAAALAAECgYIBwAAAA==.',Fa='Faeonia:BAAALAAECgQIBgAAAA==.Farwolf:BAAALAADCggIFAAAAA==.',Fe='Felicitas:BAAALAADCggICAAAAA==.',Fi='Fiannigon:BAAALAAECgYICwAAAA==.Filthy:BAAALAAECgEIAQABLAAECgQIBAABAAAAAA==.',Fl='Flath:BAAALAADCgYIBgAAAA==.Fluidd:BAAALAAECggIDwAAAA==.Flungpu:BAAALAADCggIDwABLAAECgQIBQABAAAAAA==.',Fr='Frehyer:BAAALAADCgQIBAABLAADCgcIBwABAAAAAA==.Freyen:BAAALAADCgcIBwAAAA==.',Fu='Fuselit:BAAALAADCgcICwAAAA==.',Ga='Galfure:BAAALAAECgIIAgAAAA==.Garruk:BAAALAADCgcICgAAAA==.Garwynn:BAAALAAECgUICgAAAA==.',Gh='Ghostkev:BAAALAAECgEIAQAAAA==.',Gl='Glen:BAAALAAECgMIAwAAAA==.',Go='Goldenbot:BAAALAADCgYIBgAAAA==.Gormlaîth:BAAALAADCgMIAwAAAA==.Gorpriest:BAAALAAECgEIAQAAAA==.Gouki:BAAALAADCggIFAABLAAECgMIBgABAAAAAA==.',Gr='Grunbeld:BAEALAADCggICAAAAA==.',Gu='Guthyler:BAAALAADCggIEgAAAA==.',['Gæ']='Gætherr:BAAALAAECgEIAQAAAA==.',Ha='Habbypallie:BAAALAADCgIIAgAAAA==.Handlebardoc:BAAALAAFFAIIBAAAAA==.Hatorade:BAAALAADCgQIBAAAAA==.',He='Heyei:BAAALAAECgMIBQAAAA==.',Hi='Him:BAAALAAECgYIBwAAAA==.Hitmonchamp:BAAALAADCgQIBAAAAA==.',Ho='Holyleader:BAAALAAECgMIBQAAAA==.Hongshian:BAAALAADCgYIBAAAAA==.',Hy='Hydrocodone:BAAALAADCgcICgAAAA==.',Ig='Ignisloth:BAAALAAECgYICAAAAA==.',Ij='Ijillien:BAAALAADCgcIBwAAAA==.',Il='Illidadysgrl:BAAALAADCggIDgAAAA==.',Im='Imonster:BAAALAAECgMIBQAAAA==.Imooforu:BAAALAADCgcIBwAAAA==.',Is='Isuktoo:BAAALAADCggICAAAAA==.',It='Itsgotime:BAAALAAECgYICgAAAA==.',Ja='Jaedelle:BAAALAAECgUICAAAAA==.Jamus:BAAALAAECgQIBAAAAA==.Jarray:BAAALAADCgYIEAAAAA==.',Je='Jestic:BAABLAAECoEeAAICAAgIsh3mAQCyAgACAAgIsh3mAQCyAgAAAA==.',Ji='Jiangshi:BAAALAADCgcIDgAAAA==.',Ka='Kaazel:BAAALAAECgQIBQAAAA==.Kaimana:BAAALAADCgcIBwAAAA==.Kamarin:BAAALAADCggICAAAAA==.Kangis:BAAALAADCgcIBwAAAA==.Karite:BAAALAAECgMIBQAAAA==.Karlov:BAAALAADCggICAAAAA==.',Ke='Kellarus:BAAALAADCggICAAAAA==.Kellement:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Keloria:BAAALAADCggIDwAAAA==.Kelorn:BAAALAADCgYICgAAAA==.Kennychaoss:BAAALAAECgUICAAAAA==.',Kh='Khrisbkreme:BAAALAADCgYIBgABLAAECgYICAABAAAAAA==.',Ki='Killi:BAAALAAECgEIAQAAAA==.',Ko='Kosseluna:BAAALAAECgMIBAAAAA==.Kostazu:BAAALAAECgUICAAAAA==.Kozanat:BAAALAADCgEIAQAAAA==.',Kp='Kpai:BAABLAAECoEVAAIDAAgIbSMAAwBDAwADAAgIbSMAAwBDAwAAAA==.',Ku='Kulwren:BAAALAAECgYICgAAAA==.Kumogakure:BAAALAAECgQIBgAAAA==.',Ky='Kynvana:BAAALAADCggIDgAAAA==.',La='Laity:BAAALAADCgcIDgAAAA==.Lavthyr:BAAALAADCgcIBwAAAA==.Lazkal:BAAALAADCgcIBwAAAA==.',Le='Lebesgue:BAAALAADCggICAAAAA==.Lebigmu:BAAALAAECgMIBQAAAA==.Leeanna:BAAALAADCggICAAAAA==.Leshwi:BAAALAAECgMIAwAAAA==.',Li='Lieff:BAAALAAECgEIAQAAAA==.Lisettar:BAAALAAECgYICwAAAA==.',Lu='Lunariss:BAAALAADCgcICwAAAA==.',Ly='Lycanbyte:BAAALAADCgcIFQAAAA==.Lylith:BAAALAAECgMIBAAAAA==.Lyndria:BAAALAADCggIFgAAAA==.',['Lé']='Léxý:BAAALAADCggIDgAAAA==.',Ma='Macmillie:BAAALAAECgMIAwAAAA==.Maddicollins:BAAALAADCggICgAAAA==.Magnólia:BAAALAAECgMIAwAAAA==.Mahan:BAAALAADCggICAAAAA==.Majesticalaf:BAAALAADCgcIDgABLAAECgYICgABAAAAAA==.Marathon:BAAALAAECgMIBAAAAA==.Maribelle:BAAALAADCggIFgABLAAECgUICAABAAAAAA==.',Me='Melonsquezer:BAAALAAECgMIBQAAAA==.Menmei:BAAALAAECgEIAQAAAA==.Meygen:BAAALAADCggIDQAAAA==.',Mi='Minien:BAAALAAECgMIBQAAAA==.Minko:BAAALAAECgMIAwAAAA==.Mistres:BAAALAAECgEIAQAAAA==.',Mo='Monstrosity:BAAALAADCgMIBAAAAA==.Moonshot:BAAALAAECgUICAAAAA==.Morillic:BAAALAAECgMIBQAAAA==.Morscornu:BAAALAAECgQIBAAAAA==.Mothis:BAAALAADCgcIBwAAAA==.Mouchii:BAAALAAECgIIAgAAAA==.',Ms='Mstrcrowly:BAAALAADCggIGAAAAA==.',Mu='Mustachjones:BAAALAADCgYICgAAAA==.',My='Myra:BAAALAAECggIEwAAAA==.Myros:BAAALAAECgMIBQAAAA==.',Na='Narestor:BAAALAADCgQIBAAAAA==.Navras:BAAALAAECgQIBAAAAA==.',Ne='Nero:BAAALAAECgYICgAAAA==.Newhealer:BAAALAAECgEIAQAAAA==.',Ni='Nimuerose:BAAALAAECgMIAwAAAA==.',No='Nortree:BAAALAADCggIFAAAAA==.',Nu='Nulwyrm:BAAALAAECgMIAwAAAA==.',Ny='Nyyrivik:BAAALAADCgQIBAAAAA==.',Oc='Octapie:BAAALAAECgMIBQAAAA==.',Og='Ogbuoku:BAAALAADCgcIBwAAAA==.',Oh='Ohitsadragon:BAAALAAECgYICAAAAA==.',Or='Oranur:BAAALAADCgcIBwAAAA==.Oreoscruunit:BAAALAAECgQIBAABLAAECgYICAABAAAAAA==.',Pa='Palmalaharis:BAAALAAECgIIAgAAAA==.Palädin:BAAALAADCgYIBwAAAA==.Parmesan:BAAALAADCgcIBwAAAA==.Pashene:BAAALAAECgEIAQAAAA==.Paw:BAAALAADCgcIBwAAAA==.Pawedone:BAAALAADCgYIBwABLAADCgcIBwABAAAAAA==.',Pe='Periwinkle:BAAALAAECgUIBgAAAA==.Pettacular:BAAALAAECgEIAQAAAA==.',Ph='Phidra:BAAALAAECgMIBQAAAA==.',Pl='Plushy:BAAALAAECgQIBAAAAA==.',Po='Pokecheck:BAAALAADCgMIBQAAAA==.',Pr='Predatorc:BAAALAAECgYIBwAAAA==.Primatesix:BAAALAADCgMIAwAAAA==.Primevl:BAAALAAECgUICAAAAA==.Primèvil:BAAALAADCgcIBwAAAA==.',Pu='Puma:BAAALAADCggIDwAAAA==.Puny:BAAALAADCgcIBwABLAAECgQIBAABAAAAAA==.',['Pö']='Pölly:BAAALAADCgMIAwAAAA==.',Ra='Raediant:BAAALAADCggIDgAAAA==.Rahvinwulf:BAAALAAECgMIBQAAAA==.Rairen:BAAALAAECgQIBQAAAA==.Rangikuu:BAAALAADCggIBwAAAA==.Raquel:BAAALAAECgYIBwAAAA==.Raxtian:BAAALAADCgQIBAABLAADCgcIBwABAAAAAA==.Raínbowdash:BAAALAAECgYICgAAAA==.',Re='Rede:BAAALAADCgcICwAAAA==.Redrum:BAAALAADCgYIBgAAAA==.Redwood:BAAALAAECgMIBQAAAA==.Relieff:BAAALAADCgcIBwAAAA==.Revalz:BAAALAAECgIIAgAAAA==.',Rh='Rhyzamel:BAAALAADCgcIEQAAAA==.',Ri='Rio:BAAALAAECgUICAAAAA==.Ris:BAAALAAECgYIDQAAAA==.Ritami:BAAALAAECgYIDAAAAA==.',Ro='Roknathar:BAAALAAECgYICQAAAA==.Rosin:BAAALAAECgIIAgAAAA==.',Ru='Rukya:BAAALAADCgYIBgAAAA==.',Sa='Sater:BAAALAADCgMIAwAAAA==.',Se='Sedo:BAAALAADCgYIBgAAAA==.Selenia:BAAALAADCgMIAwAAAA==.Semfidel:BAAALAADCggICAAAAA==.',Sh='Shadygrove:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.Shammymax:BAAALAADCgMIAwAAAA==.Shaomai:BAAALAAECgYIBwAAAA==.Shi:BAAALAADCgMIAwAAAA==.Shâde:BAAALAAECgcIDAAAAA==.',Si='Silencekilla:BAAALAADCgMIBgAAAA==.Silverwin:BAAALAAECgEIAQAAAA==.',Sk='Skädi:BAAALAAECgUICAAAAA==.',Sl='Slayerian:BAAALAADCgcIBwAAAA==.Slimjd:BAAALAAECgYICwAAAA==.',Sm='Smiteignite:BAAALAAECgQIBAAAAA==.Smitted:BAAALAADCgcIBwAAAA==.',So='Sonddra:BAAALAAECgIIAgAAAA==.Sorn:BAAALAAECgMIAwAAAA==.',Sp='Splittail:BAAALAAECgMIAwAAAA==.',St='Steinhauld:BAAALAADCgUIBQAAAA==.Stormstout:BAAALAADCgcIBwAAAA==.',Su='Sunrise:BAAALAADCgQIBAAAAA==.Suppabad:BAAALAAECgMIBQAAAA==.',Sw='Swordgobonk:BAAALAADCggICAAAAA==.',Ta='Taara:BAAALAADCgcIBwABLAAECgUICAABAAAAAA==.Tadriel:BAAALAADCgYIBAAAAA==.Tarysha:BAAALAAECgMIAwAAAA==.Taylee:BAAALAAECgIIAgAAAA==.Tazara:BAAALAADCgMIBAAAAA==.',Te='Tehnegev:BAAALAADCgcIBwAAAA==.Tevia:BAAALAAECgYICwAAAA==.',Th='Thalip:BAAALAADCgcIBwAAAA==.Tharas:BAAALAAECgMIAwAAAA==.Thata:BAAALAADCgcIBwABLAADCggIDgABAAAAAA==.Theøden:BAAALAAECgUICQAAAA==.Thokmay:BAAALAAECgUICAAAAA==.',Ti='Tiandrinna:BAAALAAECgMIAwAAAA==.Timmyjudge:BAAALAADCgcIBwAAAA==.Timmymayhem:BAAALAADCgcIBwAAAA==.Tinyspoon:BAAALAADCggIFwAAAA==.',Tm='Tmagnet:BAAALAAECgEIAQAAAA==.',To='Toenail:BAAALAADCgMIAwAAAA==.Toilet:BAAALAAECgMIAwAAAA==.Totemology:BAAALAAECgIIAgAAAA==.Totirdtotank:BAAALAADCgcICgAAAA==.',Tr='Trixterwolf:BAAALAADCgUICAAAAA==.',Ts='Tserendolgor:BAAALAADCgcIDgAAAA==.',Ul='Ulqiuorra:BAAALAAECgEIAQAAAA==.',Un='Undbex:BAAALAADCgMIAwAAAA==.Unávoidable:BAAALAADCgIIAgAAAA==.',Ur='Uranyr:BAAALAAECgQICQAAAA==.',Va='Valdor:BAAALAADCgcIFQAAAA==.Valeeras:BAAALAADCgUIBgAAAA==.Valeron:BAAALAAECgEIAQAAAA==.Valicous:BAAALAADCgcIFQAAAA==.Valord:BAAALAADCggICAAAAA==.Vandalie:BAAALAADCggICwAAAA==.',Ve='Velocity:BAAALAAECgMIAwABLAAFFAIIBAABAAAAAA==.Verianna:BAAALAAECgMIBQAAAA==.',Vo='Vodkâshots:BAAALAAECggIAQAAAA==.',Wa='Warvegas:BAAALAADCggIDQAAAA==.',Wi='Willowy:BAAALAAECgUICAAAAA==.',['Wâ']='Wâlmi:BAAALAAECggIBQAAAA==.',Xa='Xaerius:BAAALAAECgMIBQAAAA==.Xann:BAAALAADCgcICAAAAA==.Xantyr:BAAALAADCgcIFQAAAA==.',Xe='Xerseus:BAAALAAECgEIAgAAAA==.',Ya='Yarman:BAAALAAECgEIAQAAAA==.',Yi='Yiirito:BAAALAADCgIIAgAAAA==.',Yo='Yogsarah:BAAALAAECgYICQAAAA==.Yojimbro:BAAALAADCgcIBwAAAA==.',Ze='Zechte:BAAALAADCgUICQAAAA==.',Zi='Zipzip:BAAALAAECgMIAwAAAA==.Zirl:BAAALAAECgYICQAAAA==.Zirou:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Zivy:BAAALAAECgMIBAABLAAECgYICQABAAAAAA==.',Zu='Zuir:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.Zur:BAABLAAECoEUAAMEAAcIAR8gEQACAgAEAAcIABggEQACAgAFAAYITBxyIwDIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end