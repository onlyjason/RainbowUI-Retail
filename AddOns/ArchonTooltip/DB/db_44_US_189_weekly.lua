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
 local lookup = {'Unknown-Unknown','Warlock-Destruction',}; local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Ablestract:BAAALAADCgcIDgAAAA==.',Ad='Adreane:BAAALAADCggIDQAAAA==.',Ai='Airana:BAAALAAECgcIDQAAAA==.Airrent:BAAALAAECgYIDAAAAA==.',Ak='Akamma:BAAALAADCggIFQAAAA==.',Al='Algeriono:BAAALAADCgcIBwAAAA==.',Am='Ameliae:BAAALAAECgMIBgAAAA==.',An='Angrykillah:BAAALAADCgcIBwAAAA==.Angrytanker:BAAALAADCggIBwAAAA==.',As='Asukasoryu:BAAALAADCgIIAgAAAA==.',Ax='Axèl:BAAALAAECgMIBQAAAA==.',Az='Azimondius:BAAALAAECgYICAAAAA==.',Ba='Balefire:BAAALAADCggICAAAAA==.Bandorn:BAAALAADCgMIAwAAAA==.Barbieq:BAAALAADCgcIBwAAAA==.Bareeds:BAAALAADCggICAAAAA==.',Be='Bepallylol:BAAALAAECgMIAwAAAA==.',Bi='Bistroboy:BAAALAAECgEIAQAAAA==.',Bo='Bogun:BAAALAAECgYICQAAAA==.Bowinkle:BAAALAADCgUIBQABLAADCggICAABAAAAAA==.',Br='Brightheal:BAAALAAECgEIAQAAAA==.Bronsoon:BAAALAADCgcICgAAAA==.Brunka:BAAALAADCgIIAgAAAA==.',Bu='Bulgestomper:BAAALAAECgMIBAAAAA==.Burbuja:BAAALAAECgEIAQAAAA==.Burneynador:BAAALAAECgIIBgAAAA==.',Ca='Castrato:BAAALAADCgQIBgAAAA==.Catleesi:BAAALAAECgYICAAAAA==.',Ce='Celibrimbor:BAAALAAECgYIDwAAAA==.',Ch='Chariizard:BAAALAADCgMIAwAAAA==.Chewÿ:BAAALAAECggIDQAAAA==.Chicntrl:BAAALAAECgYICwAAAA==.Chlamy:BAAALAADCggIDQAAAA==.',Co='Cojarr:BAAALAAECgYIBwAAAA==.Corbina:BAAALAAECggICQAAAA==.Cowadin:BAAALAADCggIEAAAAA==.',Cr='Cru:BAAALAAECgQIBwAAAA==.',Da='Daamodi:BAAALAADCgQIBAAAAA==.Dabswfel:BAAALAADCgYIBAAAAA==.Daemonwing:BAAALAADCggIDgAAAA==.Damis:BAAALAADCggIDwAAAA==.Darazer:BAAALAADCgYIBgAAAA==.',De='Demontrix:BAAALAADCgYIBgAAAA==.Destruction:BAAALAAECgMIBQAAAA==.Dethwing:BAAALAAECgYIBwAAAA==.Devo:BAAALAAECgYICgAAAA==.',Di='Dingers:BAAALAADCgcIBwAAAA==.Divinespark:BAAALAAECgMIBQAAAA==.Diáo:BAAALAAECgMIBQAAAA==.',Dr='Drakewing:BAAALAADCgcICQAAAA==.Drunkdriver:BAAALAADCgUIBQAAAA==.Drylogic:BAAALAAECgQIBAAAAA==.',Du='Dubya:BAAALAADCgYIBgAAAA==.',Ea='Eap:BAAALAADCggIDwAAAA==.Eazye:BAAALAAECgYIDgAAAA==.',Ec='Eclipsed:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.',El='Elementrix:BAAALAAECgMIBQAAAA==.Elentiya:BAAALAADCggICAAAAA==.Elphzz:BAAALAAECgYICAAAAA==.Eltaquito:BAAALAADCggIEAAAAA==.',Em='Emoose:BAAALAAECgcIDgAAAA==.',En='Engel:BAAALAADCgcICQAAAA==.Enmma:BAABLAAECoEYAAICAAgItRtwCwCUAgACAAgItRtwCwCUAgAAAA==.',Er='Eriius:BAAALAAECgEIAQAAAA==.',Fe='Felorc:BAAALAAECgIIBAAAAA==.Feluri:BAAALAADCggICAAAAA==.',Fi='Fistofbacon:BAAALAADCgYIBgAAAA==.',Fr='Free:BAAALAAECgIIBAAAAA==.',Fu='Fuegodotz:BAAALAADCgYIBgAAAA==.',Ga='Gabby:BAAALAADCgIIAgAAAA==.Ganjåfarian:BAAALAAECgMIAwAAAA==.',Ge='Gelektrael:BAAALAAECgMIBQAAAA==.Getchya:BAAALAADCgcIDAAAAA==.',Go='Gobbrik:BAAALAAECgEIAQAAAA==.Goppy:BAAALAADCgcIBwAAAA==.Govegan:BAAALAADCggICwAAAA==.',Gr='Greengoliath:BAAALAAECgYIBwAAAA==.Greyhairs:BAAALAADCggIFwAAAA==.',Gw='Gwynnbleidd:BAAALAADCgUIBQAAAA==.',Ha='Haschel:BAAALAAECgYICQAAAA==.',He='Hexwater:BAAALAADCgQIBAAAAA==.Heypal:BAAALAAECgEIAQAAAA==.',Hi='Hillaryduff:BAAALAAECgUIBwABLAAECgYICAABAAAAAA==.',Hy='Hycisan:BAAALAAECgMIBQAAAA==.',Ic='Icydoodad:BAAALAAECgQIBgAAAA==.',Jb='Jbirdlol:BAAALAADCgcIBwAAAA==.',Je='Jeatrie:BAAALAAECggIAgAAAA==.Jetmage:BAAALAAECgYICgAAAA==.',Ju='Juliecat:BAAALAAECgYIBwAAAA==.Jux:BAAALAADCggIFwAAAA==.',Jw='Jwarr:BAAALAADCgcIBwAAAA==.',Ka='Kamkamm:BAAALAADCgYIDAAAAA==.Kasiaus:BAAALAADCgcICAAAAA==.Kasitwo:BAAALAADCgIIAgAAAA==.Katelynne:BAAALAADCggIFwAAAA==.Kaylib:BAAALAAECgMIBAAAAA==.',Kd='Kdawarrior:BAAALAAECgQIBQAAAA==.',Ke='Kerze:BAAALAADCgcIBwAAAA==.',Kh='Khazador:BAAALAAECgMIBAAAAA==.Khie:BAAALAADCggICAAAAA==.',Ki='Kickgodx:BAAALAAECgYIBgAAAA==.Kittykatt:BAAALAADCggICAAAAA==.',Kr='Kraggo:BAAALAAECgYICQAAAA==.Krucifire:BAAALAADCggIEAAAAA==.Krysiss:BAAALAADCgUIBQAAAA==.',Ku='Kumala:BAAALAAECgMIAwAAAA==.',La='Lamia:BAAALAAECgMIBAAAAA==.Landoh:BAAALAAECgMIBQAAAA==.Larsen:BAAALAAECgMIBQAAAA==.Lastshot:BAAALAADCgcIBwAAAA==.Laudanum:BAAALAADCggIDQAAAA==.',Li='Lianfei:BAAALAADCgcICAAAAA==.Lightstyle:BAAALAAECgMIAwAAAA==.Lilcocoxoxo:BAAALAADCggICQAAAA==.',Lo='Lockesol:BAAALAAECgIIAgAAAA==.Lozak:BAAALAADCgEIAQAAAA==.',Ly='Lyrana:BAAALAADCgUIBQAAAA==.',Ma='Magisterium:BAAALAADCggIDwAAAA==.Malt:BAAALAAECgMIBQAAAA==.Marex:BAAALAADCggICAAAAA==.Mario:BAAALAAECgIIAgAAAA==.',Mb='Mbrosmites:BAAALAAECgYICgAAAA==.',Mi='Mightyguzz:BAAALAAECgQICQAAAA==.Miyako:BAAALAAECgYICQAAAA==.',Mu='Muffnmeister:BAAALAAECgMIAwAAAA==.Muroxas:BAAALAADCgEIAQAAAA==.',['Mô']='Môses:BAAALAAECgMIAwAAAA==.',Na='Natë:BAAALAAECggIEgAAAA==.',Ne='Necrotalon:BAAALAADCggIFwAAAA==.Neonomega:BAAALAAECgYIDgAAAA==.',Nh='Nharuna:BAAALAAECgMIBgAAAA==.',Ni='Niykee:BAAALAAECgMIAwAAAA==.',No='Nocarrots:BAAALAAECgIIAgAAAA==.Noztra:BAAALAAECgYIDQAAAA==.',Ob='Obliteration:BAAALAADCggICQABLAAECgMIBQABAAAAAA==.',Oh='Ohshifty:BAAALAADCggIEAAAAA==.',Or='Orbsicles:BAAALAAECgEIAQAAAA==.',Ox='Oxycleanbro:BAAALAADCgEIAQAAAA==.',Pa='Paedrig:BAAALAAECgMIBAAAAA==.Papadynamite:BAAALAAECgMIAwAAAA==.',Pe='Pestilent:BAAALAADCgcIBwAAAA==.',Ph='Phaesphoros:BAAALAAECgIIAgAAAA==.',Po='Pookiebear:BAAALAAECgYICwAAAA==.',Pr='Primévil:BAAALAADCgQIBAABLAADCgUIBQABAAAAAA==.',Ps='Psychosis:BAAALAAECgcIBwAAAA==.',Ra='Rahnster:BAAALAAECgIIAgAAAA==.Rahuud:BAAALAAECgIIAQAAAA==.Raiiz:BAAALAAECgcIEQAAAA==.Rainhoof:BAAALAAECgMIBQAAAA==.Ralneth:BAAALAAFFAIIAgAAAA==.Randomtask:BAAALAADCgcIBwAAAA==.Rapala:BAAALAAECgIIAgAAAA==.Raspútin:BAAALAADCggICAAAAA==.',Re='Resonance:BAAALAADCgQIBgAAAA==.',Rj='Rjolz:BAAALAAECgYICwAAAA==.',Ro='Rocks:BAAALAAECgYICQAAAA==.Rootzi:BAAALAAECgMIAwAAAA==.Roshaka:BAAALAADCgIIAgAAAA==.',Ru='Rucks:BAAALAAECgMIBQAAAA==.',Sa='Sandalfon:BAAALAADCgcIBwAAAA==.',Sc='Scarab:BAAALAAECgEIAgAAAA==.',Se='Seg:BAAALAAECgQIBAAAAA==.Serbob:BAAALAAECgMIAwAAAA==.',Sh='Shadowscar:BAAALAADCggICAAAAA==.Shamertin:BAAALAADCggICAAAAA==.Shawkti:BAAALAAECgMIBAAAAA==.Shennong:BAAALAADCgcIDgAAAA==.Shifta:BAAALAAECgMIBQAAAA==.Shockohôlic:BAAALAADCgUIBQAAAA==.',Sk='Skullkìng:BAAALAAECgYICgAAAA==.',Sn='Snappy:BAAALAAECgYICQAAAA==.',So='Softtaco:BAAALAADCgcIBwAAAA==.',St='Staho:BAAALAADCgcICAAAAA==.Stoopiddk:BAAALAADCgMIAwAAAA==.Stoopidrood:BAAALAADCgcIBwAAAA==.Stoopidwarur:BAAALAADCgUIBQAAAA==.Stormclaw:BAAALAAECgMIBQAAAA==.',Su='Sufiya:BAAALAAECgIIAgAAAA==.Suhwoo:BAAALAAECgMIAwAAAA==.',Sw='Sweetone:BAAALAAECgIIAwAAAA==.',Sy='Syphon:BAAALAAECgMIBAAAAA==.',['Sú']='Súzúmebachi:BAAALAAECgQICQAAAA==.',Ta='Tandarilada:BAAALAAECgEIAQAAAA==.',Te='Testiew:BAAALAADCgcIDQAAAA==.',Th='Thrasius:BAAALAADCgQIBQAAAA==.Threebuttons:BAAALAADCgcIBwABLAAECggIBQABAAAAAA==.',Ti='Tirran:BAAALAADCgMIAwAAAA==.Tisle:BAAALAADCgYIBgAAAA==.Titanic:BAAALAADCgYIBgAAAA==.',To='Totemator:BAAALAADCggIFQAAAA==.',Tr='Traphouse:BAAALAADCgEIAQAAAA==.Treeiage:BAAALAAECgMIBQAAAA==.',['Tê']='Têzeret:BAAALAAECgIIAgAAAA==.',['Tö']='Töshiro:BAAALAAECgMIBQAAAA==.',Un='Unschmit:BAAALAADCgYIBgAAAA==.',Ve='Velirayvia:BAAALAAECgIIAwAAAA==.Vexxdr:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Vexxs:BAAALAAECgYICQAAAA==.',We='Weebeez:BAAALAAECgEIAQAAAA==.Wenden:BAAALAAECgMIBgAAAA==.',Wi='Windzari:BAAALAADCggICAAAAA==.Windzilitrix:BAAALAAECgIIAgAAAA==.',Wu='Wulffric:BAAALAAECgEIAQAAAA==.',Xa='Xazio:BAAALAADCgcICgAAAA==.',Yi='Yiang:BAAALAAECgYICgAAAA==.Yilandrin:BAAALAADCgYIDAABLAADCgcIBwABAAAAAA==.',Yl='Ylndrysa:BAAALAAECgcIEAAAAA==.',Yo='Yonie:BAAALAAECgcIDgAAAA==.Yoohyeon:BAAALAADCggIDwAAAA==.',Ze='Zedrock:BAAALAAECggIEQAAAA==.Zekodian:BAAALAAECgQICQAAAA==.',Zh='Zhas:BAAALAADCggIFwAAAA==.',Zu='Zuro:BAAALAAECgMIBQAAAA==.',['Ÿí']='Ÿílandrin:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end