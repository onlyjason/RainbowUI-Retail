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
 local lookup = {'Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warrior-Protection',}; local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adrador:BAAALAAECgMIBQAAAA==.Adrenaline:BAAALAAECggIEwAAAA==.',Al='Alayssa:BAAALAAECgMIBQAAAA==.Alca:BAAALAAECgUICAAAAA==.Alda:BAAALAADCgQIBAAAAA==.Alnima:BAAALAAECgUICQAAAA==.Alo:BAAALAADCgMIAwABLAAECgYIDwABAAAAAA==.',Am='Amoondai:BAAALAAECgEIAQAAAA==.Amoondrin:BAAALAAECgYIDwAAAA==.',An='Angau:BAAALAADCggIDAAAAA==.Anistanza:BAAALAADCggICAAAAA==.Anthios:BAAALAADCgMIAwAAAA==.Antisnow:BAAALAAECgYICwAAAA==.',Ar='Arvidpally:BAAALAAECgEIAQAAAA==.',As='Astrotar:BAAALAADCgcIBwAAAA==.',At='Attima:BAAALAAECgUICQAAAA==.',Au='Auram:BAAALAADCgcICgAAAA==.Auratier:BAAALAAECgMIAwAAAA==.Aurorà:BAAALAADCgcIBwAAAA==.Auspex:BAAALAAECgMIAwAAAA==.Autumnmist:BAAALAADCgUIBQAAAA==.',Av='Avaryn:BAAALAAECggIEgAAAA==.Averagegoob:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.',Ba='Babavoss:BAAALAAECggIBQAAAA==.Badaracka:BAAALAAECgEIAQAAAA==.Badash:BAAALAAECgMIBgAAAA==.Bahamuth:BAAALAAECgUICQAAAA==.Barnacles:BAAALAADCggICAAAAA==.Bats:BAAALAADCgEIAQAAAA==.',Bd='Bdyrk:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.',Be='Bexley:BAAALAAECgUICAAAAA==.',Bi='Biggerbunny:BAAALAAECgYICAAAAA==.Bingspin:BAAALAADCgYIBgAAAA==.',Bl='Blargle:BAAALAADCggICwAAAA==.Bloodrake:BAAALAAECgYIDgAAAA==.',Bo='Bosshoss:BAAALAAECgYICwAAAA==.Boûlar:BAAALAAECgMIAwAAAA==.',Br='Braneour:BAAALAAECgMIBQAAAA==.Broswen:BAAALAAECgMIAwABLAAECgUIBQABAAAAAA==.Bruen:BAAALAADCgcIEAAAAA==.',Bu='Buldir:BAAALAADCgcIDgAAAA==.',['Bõ']='Bõss:BAAALAAECgEIAQAAAA==.',Ca='Calibre:BAAALAAECgYIBwAAAA==.Calyptus:BAAALAAECgMIBAAAAA==.Cassandrah:BAAALAADCggIDgABLAAECgYIDwABAAAAAA==.Cassandral:BAAALAAECgYIDwAAAA==.',Ce='Celìa:BAAALAAECgMIAwAAAA==.',Ch='Chantinelle:BAAALAADCggIEAAAAA==.Chema:BAAALAAECgYIEAAAAA==.Chfbigtoe:BAAALAADCgIIAgAAAA==.Chfgaribaldi:BAAALAAECgEIAQAAAA==.Chosen:BAAALAADCggIDgABLAAECgcICAABAAAAAA==.Christy:BAAALAADCgYICgAAAA==.Chugg:BAAALAAECgMIAwAAAA==.',Co='Coffeedemon:BAAALAADCgYICwAAAA==.Coldslappins:BAAALAAECgQIBAAAAA==.Corsina:BAAALAAECgUIBgAAAA==.',Cp='Cptdarklight:BAAALAAECgYICQAAAA==.',Cr='Crazybladês:BAAALAADCgQIBAAAAA==.Creepi:BAAALAADCgcICgAAAA==.Crimsonshado:BAAALAAECgUIBQAAAA==.',Cu='Cubcake:BAAALAAECgEIAQAAAA==.Cujoo:BAAALAADCgIIAgAAAA==.Curtastrophe:BAAALAAECgYIDwAAAA==.Curticus:BAAALAADCgQIBwAAAA==.Curtimal:BAAALAADCggICAAAAA==.',Cy='Cynsia:BAAALAAECgYIBgAAAA==.',Da='Daelanos:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.Dafuq:BAAALAAECgYICwAAAA==.Dajitsune:BAAALAAECgQICAAAAA==.',Dd='Dds:BAAALAAECgYIDAAAAA==.',De='Deathdemon:BAAALAADCgcICgAAAA==.Decimated:BAAALAADCggICgABLAAECgcICAABAAAAAA==.Demonilla:BAAALAAECgEIAgAAAA==.Dempkiston:BAAALAADCgcIDgAAAA==.Denable:BAAALAADCgcIDgAAAA==.Desun:BAAALAADCgcIDwAAAA==.Deàths:BAAALAAECgIIAgAAAA==.',Di='Digiorno:BAAALAAECgUICQAAAA==.Dilaudyd:BAAALAADCgYICQAAAA==.',Do='Donori:BAAALAAECgMIAwAAAA==.Dorcath:BAAALAAECgYIDAAAAA==.Dorin:BAAALAADCgcIBwAAAA==.',Dr='Dragan:BAAALAADCgYICgAAAA==.Dragonias:BAAALAAECgEIAQAAAA==.Drinny:BAAALAAECgUICQAAAA==.Drqueenisin:BAAALAAECgMIAwAAAA==.',Du='Duerek:BAAALAADCggIDwAAAA==.',Ea='Earthangel:BAAALAADCgcIDgAAAA==.',Ed='Eddric:BAAALAADCgcIDwAAAA==.Edlarel:BAAALAADCgcIDAABLAAECgQIBAABAAAAAA==.',Eg='Ego:BAAALAADCgcIBwAAAA==.',Ei='Einar:BAAALAADCgYIBgAAAA==.',El='Eldergreen:BAAALAADCgcICwABLAAECgEIAQABAAAAAA==.Elfwine:BAAALAADCgcICAAAAA==.Eli:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.Elindria:BAAALAAECgYIDwAAAA==.Ellaven:BAAALAADCgQICAAAAA==.Elminstir:BAAALAADCggIEQAAAA==.Elyissia:BAAALAADCgYIBgAAAA==.',Eo='Eotêch:BAAALAADCgYIBgAAAA==.',Er='Eraelystiria:BAAALAADCgcIDgAAAA==.',Ev='Eviae:BAAALAADCgcIDgAAAA==.Evillure:BAAALAADCggICAAAAA==.',Fa='Fairy:BAAALAADCgEIAQAAAA==.Falan:BAAALAADCggIFQAAAA==.Fallwabryn:BAAALAADCgcICwAAAA==.Fangelu:BAAALAAECgYIDAAAAA==.Fangerra:BAAALAADCgMIAwAAAA==.',Fe='Feår:BAAALAAECgMIBAAAAA==.',Fi='Fiesel:BAAALAADCgcIBwAAAA==.Filledejoie:BAAALAAECgUICQAAAA==.',Fl='Flexdruid:BAAALAADCgYICwAAAA==.Flourish:BAAALAADCgEIAQAAAA==.',Fr='Fragil:BAAALAAECgEIAQAAAA==.',Ga='Galena:BAAALAAECgEIAQAAAA==.',Ge='Geshtal:BAAALAAECgMIBgAAAA==.',Gi='Girion:BAAALAADCgcIDgAAAA==.',Gl='Gladyse:BAAALAADCgMIAwAAAA==.Glaiven:BAAALAAECggIEgAAAA==.Glyr:BAAALAAECgYIDwAAAA==.',Go='Gorgrin:BAAALAAECgEIAQAAAA==.',Gr='Greenback:BAAALAADCgUIBQAAAA==.Groudon:BAAALAADCggICAAAAA==.',Gu='Guthix:BAAALAAECgIIAwAAAA==.',Ha='Hailmaker:BAAALAAECgUICQAAAA==.Halnan:BAAALAAECgEIAQAAAA==.Harkanum:BAAALAAECgMIBQABLAAECgYIDAABAAAAAA==.Harkdeadly:BAAALAAECgYIDAAAAA==.Harkdheadly:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Hazbeen:BAAALAADCgcIBwAAAA==.',He='Hector:BAAALAAECgMIBgAAAA==.',Hi='Hidethetotem:BAAALAAECgIIBQAAAA==.Hikari:BAAALAAECgcIDwAAAA==.',Ho='Homerr:BAAALAAECgEIAQAAAA==.Honiahaka:BAAALAAECgUICQAAAA==.Hornbrah:BAAALAAECggICAAAAA==.',Hu='Humanoidead:BAAALAAECgYICwAAAA==.Humanoidsham:BAAALAAECgMIAwABLAAECgYICwABAAAAAA==.',Hy='Hydrah:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.',['Hö']='Hölyçow:BAAALAADCgMIAwAAAA==.',Id='Idunasil:BAAALAADCgcIDQAAAA==.',Ja='Jandrisel:BAAALAADCggIFgAAAA==.Jayjay:BAAALAADCgMIAwAAAA==.Jazastraza:BAAALAADCggIFQAAAA==.',Je='Jequalsjosh:BAAALAAECgMIBQAAAA==.Jesper:BAAALAAECgYIDwAAAA==.',Ji='Jilara:BAAALAAECgIIAgAAAA==.Jimmyjim:BAAALAAECgEIAQAAAA==.Jimmyjimmy:BAAALAADCgYICQAAAA==.',Jo='Jokker:BAAALAAECggIEgAAAA==.',Jr='Jrose:BAAALAADCggICAAAAA==.',Ka='Kaasa:BAAALAADCgUIBQAAAA==.Kaiatra:BAAALAAECgEIAQAAAA==.Kaibane:BAAALAADCgEIAQAAAA==.Kainaki:BAAALAADCgUIBQAAAA==.Kalastraza:BAAALAADCgYIBQAAAA==.Kataski:BAAALAADCgQIBAABLAAECgEIAQABAAAAAA==.Kaìju:BAAALAAECgIIAgAAAA==.',Ke='Kellytgt:BAAALAADCgcICgAAAA==.Kelovan:BAAALAAECgMIAwAAAA==.',Kn='Knowing:BAAALAADCgYICAAAAA==.',Ko='Korhina:BAAALAAECgYIDwAAAA==.',Ku='Kungfoogle:BAAALAAECgEIAQAAAA==.Kuroyukihime:BAAALAAECgYICgAAAA==.',La='Larradra:BAAALAADCgYIBgAAAA==.Lashela:BAAALAADCggIFgAAAA==.Laughter:BAAALAAECgEIAQAAAA==.Laylla:BAAALAADCgIIAgAAAA==.Lazhro:BAAALAADCgYIBgAAAA==.Lazulie:BAAALAADCgYIBgAAAA==.',Le='Lefnedrav:BAAALAADCgcIBwAAAA==.',Li='Ligea:BAAALAADCgUICAAAAA==.Lightmessiah:BAAALAAECgQICAAAAA==.Lightone:BAAALAADCgUIBQAAAA==.Lillianaxe:BAAALAADCggIEAAAAA==.Lilyvain:BAAALAADCgYIBwAAAA==.Liquidbread:BAAALAADCgcICAAAAA==.Listerine:BAAALAAECgQIBAAAAA==.Livnod:BAAALAADCgYICQAAAA==.',Lo='Locutusborg:BAAALAAECgMICAAAAA==.Loonstalker:BAAALAADCgcIBwAAAA==.Loosescrew:BAAALAADCgIIAQAAAA==.Lorine:BAAALAAECgYICQAAAA==.Loveroleaves:BAAALAADCgcIBwAAAA==.',Ma='Madge:BAAALAADCgMIAwAAAA==.Manmade:BAAALAAECgMIAwAAAA==.Marqu:BAAALAADCgcIDQAAAA==.Mastakillah:BAAALAAECgcIEgAAAA==.Maxino:BAAALAAECgEIAQAAAA==.',Me='Mejijhon:BAAALAADCggICAAAAA==.',Mi='Michello:BAAALAAECgEIAQAAAA==.Micsharpens:BAAALAAECgYICwAAAA==.',Mo='Mogdor:BAAALAADCggIEAAAAA==.Moondark:BAAALAADCgYICQAAAA==.Moonhunt:BAAALAAECgMIAwAAAA==.Mordican:BAAALAADCgMIAwAAAA==.',My='Myxie:BAAALAADCggICAAAAA==.',['Mí']='Mísfìt:BAAALAAECgYIDwAAAA==.',Na='Nakaito:BAAALAAECgEIAQAAAA==.Narcoleptic:BAAALAAECgYICQAAAA==.Naturaljuice:BAAALAAECgYIBgAAAA==.',Ne='Nerflife:BAAALAAECggICAAAAA==.',Ni='Nicoa:BAAALAADCggICgAAAA==.Nightsawdy:BAAALAAECgMIBQAAAA==.Niightstorm:BAAALAADCgcIDgAAAA==.Nikwillig:BAAALAADCggIFQAAAA==.Nilvalor:BAAALAAECgUICAAAAA==.Nitefire:BAAALAADCgYICgAAAA==.',Nt='Ntadadarknes:BAAALAAECgEIAQAAAA==.',Ny='Nyméria:BAAALAADCgUIBQAAAA==.',Of='Offspring:BAAALAADCgYIBgAAAA==.',Op='Ophinium:BAAALAADCggIDwAAAA==.',Pa='Pandaskinner:BAAALAADCggIEAAAAA==.Parsivval:BAAALAADCgYICgAAAA==.',Ph='Phelo:BAAALAADCgcIBwAAAA==.Phrael:BAAALAAECgUIBgAAAA==.',Pr='Praecantrix:BAAALAADCgEIAQAAAA==.Pray:BAAALAAECgUICQAAAA==.Principium:BAAALAAECgEIAQAAAA==.Principiumx:BAAALAADCgEIAQAAAA==.Prodarkangel:BAAALAAECgUICQAAAA==.Proyapper:BAAALAADCgcIDAAAAA==.',Pu='Pubis:BAAALAAECgQIBwAAAA==.Puckllane:BAAALAAECgYICQAAAA==.Punkin:BAAALAADCgYICQAAAA==.',Py='Pyre:BAAALAADCgYIBgABLAAECgYIDwABAAAAAA==.',Qu='Quefstank:BAAALAAECgYICQAAAA==.Quivver:BAAALAADCgYIBgAAAA==.',Ra='Rabmaxx:BAAALAADCggIEAAAAA==.Raistlin:BAAALAADCgMIAwAAAA==.Ravenlight:BAAALAAECgcIEQAAAA==.Ravenwynnd:BAAALAAECgYIDwAAAA==.Rawllss:BAAALAAECgEIAQAAAA==.Razix:BAAALAAECgYIDAAAAA==.',Re='Reightchael:BAAALAADCgcIBwABLAAECgUICAABAAAAAA==.Reija:BAAALAADCggICAAAAA==.Revernon:BAAALAADCggICAAAAA==.',Rh='Rhyzer:BAAALAADCgcIDgAAAA==.',Ru='Rubmytotem:BAAALAAECgEIAQAAAA==.',Sa='Sabazia:BAAALAAECgYICQAAAA==.Salios:BAABLAAECoEcAAMCAAgI0x/pBQD3AgACAAgIuB/pBQD3AgADAAUIPxqbHQAnAQAAAA==.Sallydisco:BAAALAADCgEIAQABLAADCgcIBwABAAAAAA==.Sanara:BAAALAADCgcIDgAAAA==.Saphirá:BAAALAAECgUIBQAAAA==.Satreshan:BAAALAAECgQIBwAAAA==.',Sc='Scrept:BAAALAAECgEIAQAAAA==.Scÿph:BAEALAAECgYICgAAAA==.',Se='Sedaline:BAAALAADCgEIAQAAAA==.Seithe:BAAALAADCggICAAAAA==.Sephie:BAAALAADCgcIDgAAAQ==.Serenisham:BAAALAADCgMIAwAAAA==.Serenity:BAAALAAECggIDwAAAA==.Serviance:BAAALAADCggICAAAAA==.',Sh='Shabzyt:BAAALAAECgUIBgAAAA==.Shamancheese:BAAALAADCgYIAgABLAAECgYIDwABAAAAAA==.Shamrockshak:BAAALAAECgEIAgAAAA==.Shenuton:BAAALAADCggIFwAAAA==.Shockthêràpy:BAAALAAECggIDwAAAA==.Shoes:BAAALAAECgYICQAAAA==.Shtmage:BAAALAAECgMIAwAAAA==.Shyanni:BAAALAAECgIIAgAAAA==.',Si='Simi:BAAALAAECgYICQAAAA==.Sinvius:BAAALAADCggIDwAAAA==.',Sl='Slurpington:BAAALAADCggIDgAAAA==.',Sm='Smokesçreen:BAAALAAECgYICAAAAA==.',Sn='Snugglebomb:BAAALAAECgYICQAAAA==.',So='Soonerpride:BAAALAADCggIDwAAAA==.',Sp='Sparkfist:BAAALAADCggICAAAAA==.Spellumgud:BAAALAADCggICAAAAA==.',Sq='Squiby:BAAALAAECgYIDQAAAA==.Squibyrogue:BAAALAADCggICAAAAA==.',St='Starweaver:BAAALAAECgEIAQAAAA==.Stirlingskat:BAAALAAECgMIBQAAAA==.Stoya:BAAALAAECgMIAwAAAA==.Stuef:BAAALAAECgUICAAAAA==.Stäirs:BAAALAAECgUICQAAAA==.',Sv='Sveika:BAAALAADCgYICgABLAAECgEIAQABAAAAAA==.',Sy='Sylaria:BAAALAADCgYICQAAAA==.',['Sï']='Sïn:BAAALAAECgIIAgAAAA==.',Ta='Tadnippy:BAAALAADCgUIBQAAAA==.Tailbandit:BAAALAAECgMICAAAAA==.Taurne:BAAALAAECgUIBQAAAA==.',Te='Teknoman:BAAALAAECgYICQAAAA==.',Th='Thalan:BAAALAADCgYICQAAAA==.Thalfi:BAAALAADCgMIAwAAAA==.Tharain:BAAALAADCgYICgAAAA==.Thecurt:BAAALAAECgUICQAAAA==.Thorno:BAAALAADCgYIBgAAAA==.Thorsamie:BAAALAAECgEIAQAAAA==.',Ti='Timaeus:BAAALAADCggIDwAAAA==.Titanlock:BAAALAADCgYICQAAAA==.',Tk='Tkdfath:BAAALAAECgEIAQAAAA==.',To='Tokoyami:BAAALAAECgUICAAAAA==.Toralina:BAAALAAECgMIBgAAAA==.Torvia:BAAALAADCgYICQAAAA==.',Tr='Tralsoni:BAAALAAECgYIDwAAAA==.Tratren:BAAALAADCgQIBwAAAA==.Trikie:BAAALAADCggIDAABLAAECgMIAwABAAAAAA==.Trikkie:BAAALAAECgMIAwAAAA==.Trisinz:BAAALAAECgUICAAAAA==.',Tu='Tuerto:BAAALAAECgEIAQAAAA==.Turk:BAAALAAECgYIDwAAAA==.Turkish:BAAALAAECgUIBwAAAA==.Turtledisco:BAAALAADCgcIBwAAAA==.',Ty='Tychaa:BAAALAADCgYIBgAAAA==.Tylat:BAAALAADCgYIAwABLAADCgYIBgABAAAAAA==.Tyranay:BAAALAAECgcIEQAAAA==.',Ul='Ullyr:BAAALAAECgUICQAAAA==.',Un='Unsung:BAAALAAECgYIDwAAAA==.',Us='Us:BAAALAAECgMIAwAAAA==.',Va='Vadose:BAAALAADCggICgABLAAECgYICQABAAAAAA==.Vanshrill:BAAALAADCgcICQAAAA==.',Ve='Veiksla:BAAALAAECgEIAQAAAA==.',Vi='Vitur:BAAALAAECgYIDwAAAA==.',Vo='Volaine:BAAALAADCgcIDgAAAA==.Volt:BAAALAAECgUICQAAAA==.Vonransom:BAAALAADCggIDQAAAA==.',['Vô']='Vôx:BAAALAAECgIIAgAAAA==.',Wa='Warbeard:BAAALAAECgYICwAAAA==.',Wo='Worldlight:BAAALAAECgcIDwAAAA==.',Xa='Xanthad:BAAALAADCgIIAgAAAA==.',Ya='Yaan:BAAALAAECgMIBAAAAA==.Yashä:BAAALAADCggICAAAAA==.',Ye='Yesbeatme:BAAALAADCggIDwAAAA==.',Yu='Yurface:BAAALAADCgIIAgAAAA==.',Za='Zain:BAAALAAECgYIDwAAAA==.Zandibar:BAAALAADCgcIDgAAAA==.Zaptoasted:BAAALAADCgcIBgAAAA==.Zariea:BAAALAAECggICgAAAA==.',Ze='Zenty:BAAALAADCggICwAAAA==.',Zi='Zibb:BAAALAADCggIFAAAAA==.',Zu='Zuggie:BAAALAAECgEIAQAAAA==.Zurtrinik:BAABLAAECoEWAAIEAAgIRiGpBACkAgAEAAgIRiGpBACkAgAAAA==.',Zy='Zylith:BAAALAAECgMIAwABLAAECgUICQABAAAAAA==.',Zz='Zzonked:BAAALAAECgYIDAAAAA==.',['Zé']='Zénith:BAAALAADCgcIBwAAAA==.',['Zø']='Zøømies:BAAALAAECgMIAwAAAA==.',['Àr']='Àrròw:BAAALAADCggIDgAAAA==.',['Äs']='Äshnärd:BAAALAAECgYICQAAAA==.',['Ðo']='Ðoogle:BAAALAADCgYICgABLAAECgEIAQABAAAAAA==.',['Ðr']='Ðruidess:BAAALAAECgMIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end