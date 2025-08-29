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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Priest-Holy',}; local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adow:BAAALAAECgMIBAAAAA==.',Ae='Aered:BAAALAADCggICwAAAA==.',Ai='Aig:BAAALAAECgEIAQAAAA==.',Ak='Akuria:BAAALAAECgMIBwAAAA==.',Al='Alacía:BAAALAAECgQIBAAAAA==.Alahna:BAAALAADCggIFQAAAA==.Aleahrose:BAAALAAECgYICwAAAA==.Alena:BAAALAADCggIBwAAAA==.Alsta:BAAALAAECgMIAwABLAAECgQIAwABAAAAAA==.',An='Anies:BAAALAAECgQICAAAAA==.Animûs:BAAALAADCggICAAAAA==.',Aq='Aquarian:BAAALAAECgYICwAAAA==.',Ar='Aralight:BAAALAADCgEIAQAAAA==.Ardcore:BAAALAAECgUICwAAAA==.Arys:BAAALAADCgcICwAAAA==.',As='Asusan:BAAALAADCgcICQAAAA==.',Av='Avãrice:BAAALAAECgEIAQAAAA==.',Az='Azuré:BAAALAAECgQIBAAAAA==.',Ba='Backkstabber:BAAALAADCggICAAAAA==.Batmuhn:BAAALAAECgEIAQAAAA==.',Be='Belserion:BAAALAAECgMICQAAAA==.Berol:BAAALAAECgQIAwAAAA==.Beroldin:BAAALAADCgEIAQABLAAECgQIAwABAAAAAA==.',Bi='Biggiebrewz:BAAALAAECgYICAAAAA==.Biggiesmallz:BAAALAAECgMIAwAAAA==.Bigsuggardad:BAAALAAECgIIAgAAAA==.Bikerbabe:BAAALAADCgcIDgAAAA==.',Bj='Bjøørn:BAAALAADCggICAAAAA==.',Bl='Blindmafaka:BAAALAAECgQICQAAAA==.Blkrend:BAAALAAECgcIDQAAAA==.',Br='Bradycam:BAAALAAECgUICgAAAA==.Bricktitty:BAAALAADCggICQAAAA==.Bride:BAAALAADCgMIAwAAAA==.Bruyneelka:BAAALAAECgMIAwAAAA==.',Bu='Bullozer:BAAALAADCggIDQAAAA==.Bungles:BAAALAAECgUIAQAAAA==.Burritobill:BAAALAAECgYICgAAAA==.',Ca='Carebeär:BAAALAAECgMIBQAAAA==.Casella:BAAALAAECgYIDgAAAA==.',Ch='Chubbyshamy:BAAALAADCgYICQAAAA==.',Cl='Cleth:BAAALAAECgMIBwAAAA==.Clouzot:BAAALAADCgMIAwAAAA==.',Co='Corax:BAAALAAECgMIBwAAAA==.',['Cö']='Cösmic:BAAALAAECgIIAgAAAA==.',Da='Danskan:BAAALAADCgcICQAAAA==.Darmorae:BAAALAADCggICAAAAA==.',De='Deadstimpy:BAAALAAECgIIAwAAAA==.Deathris:BAAALAAECgYICwAAAA==.Desadeness:BAAALAADCgcIDQAAAA==.',Dr='Dracdemonica:BAAALAAECgcIDQAAAA==.Draclou:BAAALAADCgYIBgAAAA==.Dracslock:BAAALAAECgMICAAAAA==.Dracthyrios:BAAALAADCggIDwAAAA==.Drelserion:BAAALAADCggIEwABLAAECgMICQABAAAAAA==.Drestla:BAAALAAECgYIDgAAAA==.Drowgon:BAAALAAECgcIBwAAAA==.',['Dø']='Døømlørd:BAAALAAECgEIAQABLAAECgMIBQABAAAAAA==.',['Dú']='Dúbs:BAAALAADCgMIAwAAAA==.',Ea='Earthhammerz:BAAALAADCgcIBwAAAA==.',El='Electricks:BAAALAAECgYICwAAAA==.Elizardbuff:BAAALAADCgMIAwAAAA==.Elrande:BAAALAADCggICAAAAA==.',Em='Emolock:BAAALAAECgMIAwAAAA==.',En='Endir:BAAALAADCgMIAwAAAA==.',Ep='Epiphaný:BAAALAAECggICAAAAA==.',Ev='Evadne:BAAALAAECgEIAQAAAA==.',Fa='Farthin:BAAALAADCgQIBAAAAA==.',Fe='Fenn:BAAALAAECgYICwAAAA==.',Fl='Fleew:BAAALAAECgIIAgAAAA==.',Fr='Freak:BAAALAAECgMIBAAAAA==.Freakpeachh:BAAALAAECgYICQAAAA==.',Fu='Furylight:BAAALAADCgEIAQAAAA==.',Ga='Galam:BAAALAADCgQIBAAAAA==.Ganjtastik:BAAALAADCgYIBgAAAA==.',Ge='Gettemchump:BAAALAADCgYIBgAAAA==.',Go='Goredk:BAAALAAECgIIAgAAAA==.',Gr='Gr:BAAALAAECgUIBwAAAA==.Gregord:BAAALAADCgcICgAAAA==.Gromiir:BAAALAAECgYICwAAAA==.',['Gä']='Gärrus:BAAALAADCggICAAAAA==.',['Gó']='Gójira:BAAALAAECgMIAwAAAA==.',Ha='Hartis:BAAALAAECgIIAgAAAA==.',He='Hellsonlyboo:BAAALAADCgEIAQAAAA==.Hemotep:BAAALAAECgEIAQAAAA==.',Ho='Holeefok:BAAALAAECgcIEgAAAA==.Holiblade:BAAALAAECgMIBgAAAA==.Holitank:BAAALAADCgQIBAAAAA==.Holykilla:BAAALAAECgYICwAAAA==.Hooligun:BAAALAAECgEIAQAAAA==.',Hr='Hruno:BAAALAADCggICAABLAAECgMIBgABAAAAAA==.',Hy='Hypérian:BAAALAADCggICwAAAA==.',Ia='Ianes:BAAALAAECgEIAQAAAA==.',Ic='Icyprotoss:BAAALAADCggIDgAAAA==.',Ig='Igneel:BAAALAADCggICwAAAA==.',Ij='Ijustshotyou:BAAALAADCgcIDgAAAA==.',In='Insomniaxe:BAAALAAECgMIAwAAAA==.Invidious:BAAALAADCggICwAAAA==.',Ir='Irvyn:BAAALAADCgEIAQAAAA==.',Is='Isohden:BAAALAADCgUICAAAAA==.',Je='Jehbodia:BAAALAADCggIFQAAAA==.',Jn='Jnymango:BAAALAADCgYIDAABLAAECgYICwABAAAAAA==.',Jo='Johnnymango:BAAALAAECgYICwAAAA==.Jollakeratu:BAAALAAECgMIBwAAAA==.',Ju='Juut:BAAALAADCggIDgAAAA==.',['Jø']='Jønty:BAAALAADCgMIAwAAAA==.',Ka='Kaitn:BAAALAAECgMIAQAAAA==.Kazathule:BAAALAAECgYICwAAAA==.',Kb='Kbetty:BAAALAAECgYICwAAAA==.',Ke='Keelhorn:BAAALAAECgYIDAAAAA==.',Ki='Kibon:BAAALAADCggIFQAAAA==.Kinkyhawt:BAAALAAECgUIBQAAAA==.Kirio:BAAALAAECgYIDAAAAA==.Kitsunenohi:BAAALAAECgMIBwAAAA==.',Ko='Kozilek:BAAALAADCgYIBgAAAA==.',Kw='Kwazii:BAAALAAECggIBQAAAA==.',Ky='Kyogre:BAAALAAECgMIAwAAAA==.',La='Laefnia:BAAALAAECgUICAAAAA==.Larebeast:BAAALAADCgMIAwAAAA==.Laresistance:BAAALAAECgMIBAAAAA==.',Le='Leomist:BAAALAAECgEIAQAAAA==.',Li='Lightrunner:BAAALAADCgcICAAAAA==.Lildarleena:BAAALAADCgcICgAAAA==.Lilis:BAAALAADCgcIDQAAAA==.Lilithe:BAAALAAECgMIBQAAAA==.Lillíth:BAAALAADCggICAAAAA==.',Lo='Logonman:BAAALAADCgQIBAAAAA==.Longshankss:BAAALAADCgcIBwAAAA==.',Ma='Machine:BAAALAADCgUIBQAAAA==.Madbeech:BAAALAADCgMIAwAAAA==.Mangezlâge:BAAALAADCgMIAwAAAA==.Marby:BAAALAADCgcIBwAAAA==.Marjories:BAAALAADCgMIAwAAAA==.',Mc='Mcclure:BAAALAADCgcIDQAAAA==.',Me='Meleyss:BAAALAADCgIIAgAAAA==.Mereidith:BAABLAAECoEhAAICAAcIxh91FABwAgACAAcIxh91FABwAgAAAA==.Mesoholy:BAAALAADCgcIBwAAAA==.',Mi='Mir:BAAALAAECgcIBwAAAA==.',Mk='Mkalf:BAAALAADCgMIAwAAAA==.',Mo='Moobáca:BAAALAAECggIAwAAAA==.Morcilla:BAAALAADCgcICQAAAA==.',My='Myssdirect:BAAALAADCgMIAwAAAA==.Mythrandiir:BAAALAAECgIIAgAAAA==.Mythredor:BAAALAADCgcIDgAAAA==.',Na='Naughtynurse:BAAALAAECgYICQAAAA==.',Ne='Newthrall:BAAALAADCgQIBAAAAA==.',Ni='Nicoa:BAAALAAECgYICQAAAA==.Nighthawque:BAAALAADCgMIAwAAAA==.Ninnyggums:BAAALAADCgUIBQAAAA==.',Ob='Obiejuan:BAAALAAECgcIDQAAAA==.',Od='Oddball:BAAALAAECgQIBwAAAA==.',Ol='Oldirtbag:BAAALAADCgQIBAAAAA==.Olgam:BAAALAAECgUICgAAAA==.',Or='Orthiaa:BAAALAADCgcIBwAAAA==.',Pa='Pabdru:BAAALAADCgMIAwAAAA==.Palpinaintez:BAAALAAECggIEwAAAA==.',Ph='Phatheals:BAAALAADCgcIBwAAAA==.',Po='Poseidon:BAAALAADCggICAAAAA==.',Ps='Psiren:BAAALAADCgcIBwAAAA==.',['Pä']='Päw:BAAALAAECgIIAgAAAA==.',Ra='Raathe:BAAALAADCgMIAwAAAA==.Radge:BAAALAAECgcICgAAAA==.Rainnous:BAAALAADCggICQAAAA==.Rakso:BAAALAADCgMIAwAAAA==.Raljah:BAAALAAECgMIBgAAAA==.Rallmar:BAAALAADCgEIAQAAAA==.Raxxer:BAAALAADCgQIBAAAAA==.',Ri='Richpplwater:BAAALAADCgQIAQAAAA==.',Ro='Romanath:BAAALAADCgEIAQAAAA==.Royalnewb:BAAALAADCgcIBwAAAA==.',Ry='Ryptyde:BAAALAAECgcIDwAAAA==.',Sa='Saldar:BAAALAAECgUIBwAAAA==.Saox:BAAALAAECgIIAgAAAA==.Sapandslap:BAAALAAECgYICQAAAA==.',Se='Serri:BAAALAADCgMIAwAAAA==.',Sh='Shak:BAAALAADCgUIBQAAAA==.Shalai:BAAALAAECgYIBgAAAA==.Shellingtun:BAAALAAECggIEAAAAA==.Shiverray:BAAALAAECgYICQAAAA==.Shylor:BAAALAADCgMIAwAAAA==.',Sk='Skitch:BAAALAADCgcICAAAAA==.Sksteve:BAAALAADCgMIAwAAAA==.Skychades:BAAALAAECgIIAgAAAA==.',Sp='Sparklenne:BAAALAADCggICwAAAA==.Spookydeath:BAAALAAECgcIEAAAAA==.Spýro:BAAALAADCggICAAAAA==.',Sq='Squeaky:BAAALAADCggICwAAAA==.',St='Stoneydragon:BAAALAAECgMIBQAAAA==.Sturnguard:BAAALAADCggICwAAAA==.',Su='Sunchipz:BAAALAADCgYIBgAAAA==.Supervicious:BAAALAADCggIDgAAAA==.',Sy='Sylenne:BAAALAAECgIIAgAAAA==.Sylur:BAAALAAECgMIBQAAAA==.Syrinora:BAAALAADCgIIAgAAAA==.',['Sü']='Sümtíñgwoñg:BAAALAAECgEIAQAAAA==.',Ta='Tah:BAAALAADCgYICwABLAAECgcIGAADAPkYAA==.Tahran:BAAALAADCgcIDQABLAAECgcIGAADAPkYAA==.Tahren:BAABLAAECoEYAAIDAAcI+RisFAALAgADAAcI+RisFAALAgAAAA==.Tahshock:BAAALAAECgIIAgABLAAECgcIGAADAPkYAA==.Talerion:BAAALAAECgIIAgAAAA==.Tanidia:BAAALAADCgEIAQAAAA==.',Tc='Tcdots:BAAALAADCgcIBwAAAA==.',Te='Temperament:BAAALAADCgMIAwAAAA==.Temporalize:BAAALAADCgcIBwAAAA==.',Th='Tharic:BAAALAADCggICQAAAA==.Thelionheart:BAAALAADCgIIAgAAAA==.Thistelbear:BAAALAAECgMIBwAAAA==.',Ti='Titszilla:BAAALAAECggICAAAAA==.',Tr='Trankoz:BAAALAAECgQIAwAAAA==.Trippy:BAAALAAECgMIBgAAAA==.',Tt='Ttsprinkles:BAAALAADCgYIBgAAAA==.',Tw='Tweis:BAAALAADCgMIAwAAAA==.',Va='Valaa:BAAALAAECgYICgAAAA==.Vassandra:BAAALAADCgUIBQAAAA==.',Ve='Veda:BAAALAADCgUIBQAAAA==.',Vi='Viaro:BAAALAADCggICwAAAA==.Viddysouls:BAAALAAECgMIBwAAAA==.Viscerai:BAAALAAECgMICAAAAA==.Vission:BAAALAADCgYIBwAAAA==.',Vo='Vonmiller:BAAALAAECgYIBwAAAA==.',We='Weird:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.',Xe='Xennessa:BAAALAADCgEIAQAAAA==.',Yu='Yugen:BAAALAAECgYIDQAAAA==.Yurie:BAAALAAECgMIAwAAAA==.',Ze='Zenhawk:BAAALAADCgEIAQAAAA==.',Zy='Zyxtryne:BAAALAAECgMIAwAAAA==.',['Çà']='Çàîn:BAAALAAECgMIAwAAAA==.',['Ñö']='Ñövä:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end