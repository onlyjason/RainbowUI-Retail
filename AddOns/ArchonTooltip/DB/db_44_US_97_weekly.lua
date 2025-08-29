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
 local lookup = {'Warrior-Fury','Unknown-Unknown','Mage-Frost','Mage-Arcane','Paladin-Retribution','Warlock-Demonology','Shaman-Restoration','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Holy',}; local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Ackren:BAAALAADCgMIAwAAAA==.Acky:BAAALAAECgMIAwAAAA==.',Ak='Akittymeow:BAAALAAECgMIBgAAAA==.',Al='Althunter:BAAALAAECgcIBwAAAA==.',Am='Amaranthe:BAAALAADCgIIAgAAAA==.Amelina:BAAALAADCgUIBQAAAA==.Amorir:BAAALAAECgYICQAAAA==.',An='Anastala:BAAALAAECgMIAwAAAA==.Annesta:BAAALAAECgMIAwAAAA==.Anyaneeze:BAAALAADCggICQAAAA==.',Ap='Applephone:BAAALAAECgYICQAAAA==.',Ar='Archontas:BAAALAAECgYICQAAAA==.Arioprx:BAAALAADCggICAAAAA==.Aritus:BAABLAAECoEUAAIBAAgIWCLTBgD+AgABAAgIWCLTBgD+AgAAAA==.Arkaline:BAAALAADCgYIBgAAAA==.Artuarry:BAAALAAECgcIEAAAAA==.',As='Ashaweshk:BAAALAADCgcIDQAAAA==.',At='Athenà:BAAALAAECgEIAQAAAA==.',Av='Avocado:BAAALAAECgUIBwAAAA==.',Ax='Axelaw:BAAALAADCggIFAAAAA==.',Ba='Badragon:BAAALAADCggICQAAAA==.Banthr:BAAALAADCggIDwAAAA==.Battleworm:BAAALAAECgIIAwABLAADCggICQACAAAAAA==.',Be='Beefytacos:BAAALAADCggIDQAAAA==.Bellurdan:BAAALAAECgEIAwAAAA==.',Bl='Bloods:BAAALAADCgUIBQAAAA==.Bluejuly:BAAALAAECgEIAQAAAA==.',Bo='Boflex:BAAALAADCgYICQAAAA==.Bonebolt:BAAALAADCgcIDgAAAA==.Bonetotem:BAAALAAECgMIAwAAAA==.Boofy:BAAALAADCggICgABLAAECgMIBgACAAAAAA==.Borica:BAAALAADCgMIAwAAAA==.',Br='Bronzor:BAAALAADCgEIAgAAAA==.Bronzé:BAAALAAECgMIBQAAAA==.Brunedric:BAAALAADCggIDgAAAA==.',Bu='Bulan:BAAALAAECgYIDwAAAA==.',Ca='Caistan:BAAALAADCgMIAwAAAA==.Caleisme:BAAALAADCgUIBQAAAA==.Candypants:BAAALAAECgYICgAAAA==.Cappilon:BAAALAADCggIDwAAAA==.Carkevelin:BAAALAADCgQIBQAAAA==.Cayssaris:BAAALAADCggIFAAAAA==.',Ce='Ceeti:BAAALAAECgYICgAAAA==.',Ch='Cheezytaco:BAAALAADCggICQABLAAECgMIBgACAAAAAA==.Chelthud:BAAALAADCggICAAAAA==.Chihirosan:BAAALAADCgcIBwAAAA==.Chikila:BAAALAAECgIIAgAAAA==.Chilliflakez:BAAALAADCggIFAAAAA==.',Cl='Cleansing:BAAALAADCggIFQABLAAECgYICQACAAAAAA==.Cleyi:BAAALAAECgcIDgAAAA==.',Co='Coldroled:BAABLAAECoEYAAMDAAgI5iOfAwDXAgADAAgIuh+fAwDXAgAEAAUIsR/VMgCbAQAAAA==.Cosairi:BAAALAAECgMIAwAAAA==.Cougztroll:BAAALAAECgYICQAAAA==.',['Cì']='Cìryatan:BAAALAAECgEIAgAAAA==.',Da='Dalamarr:BAAALAAECgUIDAAAAA==.Daranne:BAABLAAECoEVAAIFAAgIMx51DwCRAgAFAAgIMx51DwCRAgAAAA==.Darrow:BAAALAADCgcIDAABLAAECggIFQAGACwhAA==.',De='Deebows:BAAALAAECgEIAQAAAA==.Der:BAAALAADCgcIBwABLAAECgcIEAACAAAAAA==.',Di='Dienomtye:BAAALAAECgYICAAAAA==.Diqon:BAAALAAECgYICgAAAA==.Disturbedtwo:BAAALAAECgYICgAAAA==.Dixinu:BAAALAAECgYICQAAAA==.',Do='Dolphinz:BAAALAAECggICAAAAA==.',Dr='Dragoose:BAAALAAECgcIEAAAAA==.Draukka:BAAALAADCggIBAAAAA==.Dread:BAAALAAECgIIAgAAAA==.Druish:BAAALAAECgcIDQAAAA==.Drykkr:BAAALAAECgUIDAAAAA==.',['Dà']='Dàsh:BAAALAAECgIIAgAAAA==.',Ec='Ectrein:BAAALAAECgEIAQAAAA==.',Ed='Edwardtwosev:BAAALAADCgcIBwABLAAECgEIAQACAAAAAA==.',Ei='Eielore:BAAALAAECgEIAQAAAA==.Eina:BAAALAAECgIIAgAAAA==.',El='Ellataa:BAAALAADCgYIBgABLAAECgMIBQACAAAAAA==.',Em='Emmyanta:BAAALAADCgYIBgAAAA==.',En='Ennayóx:BAAALAADCgUIBQAAAA==.',Ep='Ephelia:BAABLAAECoEVAAIHAAgIdxmxDwA3AgAHAAgIdxmxDwA3AgAAAA==.',Ev='Everlight:BAAALAAECgUIDAAAAA==.',Fa='Falstaff:BAAALAAECgYICgAAAA==.Fane:BAAALAADCggIFwAAAA==.Fatterblunt:BAAALAAECgcIEAAAAA==.',Fe='Feldar:BAAALAAECgYIBwAAAA==.',Fi='Fizzlelock:BAAALAAECgQIBQAAAA==.Fizzooka:BAAALAADCggIFQAAAA==.',Fl='Flirbert:BAAALAADCggIDgAAAA==.Flordros:BAAALAAECgUIBQAAAA==.',Fo='Fool:BAAALAADCgcIBwABLAADCggICQACAAAAAA==.Fourdy:BAAALAAECgYIDAAAAA==.',Fr='Fredwin:BAAALAADCgcIBwAAAA==.Frenn:BAAALAADCgQIBAAAAA==.Froost:BAAALAAFFAEIAQAAAA==.',Fu='Furvert:BAAALAAECgcIEAAAAA==.Fushi:BAAALAADCgcIBwAAAA==.',Ga='Gapper:BAAALAAECgUICAAAAA==.',Gh='Ghostgoboo:BAAALAADCgUICQAAAA==.',Gi='Gimby:BAAALAADCgEIAQAAAA==.',Gl='Glestaar:BAAALAAECgYICwAAAA==.Glyr:BAAALAAECgUIDAAAAA==.',Go='Goonkin:BAAALAADCgcICQABLAAECgUICAACAAAAAA==.Gothelf:BAAALAAECgIIAgABLAAECgYIDQACAAAAAA==.Gothri:BAAALAAECgEIAQAAAA==.',Gr='Greedy:BAAALAADCggICAAAAA==.Grict:BAAALAADCggIDwAAAA==.Grooknash:BAAALAADCgEIAQAAAA==.Growth:BAAALAADCgQIBAAAAA==.',Ha='Hairi:BAABLAAECoEWAAMIAAgIQx/cBADkAgAIAAgIQx/cBADkAgAJAAcIySMJCwCWAgAAAA==.Harnel:BAAALAAECgMIBAAAAA==.Hattorihanzo:BAAALAADCggIFAAAAA==.',He='Healmart:BAAALAADCgcICgAAAA==.Heylock:BAAALAADCggICAAAAA==.',Ho='Holyenjoyer:BAAALAADCggICAAAAA==.Hoyer:BAAALAAECgMIAwAAAA==.',Hu='Huge:BAAALAAECgQIBwAAAA==.',Il='Illeda:BAAALAAECgEIAQAAAA==.',In='Inblood:BAAALAAECgYICQAAAA==.',Ja='Jack:BAAALAADCgMIBAAAAA==.Jackula:BAAALAADCgQIBAABLAADCggICQACAAAAAA==.Jakub:BAAALAAECgYIDAAAAA==.',Je='Jesituis:BAAALAADCgIIAgAAAA==.',Jo='Joellegucci:BAAALAAECgcIDQAAAA==.',Ka='Kalfier:BAAALAAECgQIBQAAAA==.Kamarra:BAAALAAECgMIAwAAAA==.Kankles:BAAALAAECgcIEQAAAA==.',Ke='Kentukee:BAAALAAECgMIAwAAAA==.Kernelpanic:BAAALAAECgcIEAAAAA==.',Ki='Kimberbo:BAAALAAECgEIAQAAAA==.Kirkle:BAAALAAECgUICAAAAA==.',Ko='Korgosh:BAAALAADCggIDwAAAA==.',Ky='Kynsia:BAAALAADCgYICQAAAA==.',La='Laisperis:BAAALAADCggIEAAAAA==.Lavasaurus:BAAALAAECgYICQAAAA==.Laydeboi:BAAALAAECgYICgABLAAECgYICwACAAAAAA==.',Le='Leafstorm:BAAALAAECgMIBQAAAA==.Lektar:BAAALAAECgMIBQAAAA==.Lesclaypool:BAAALAADCgcICgAAAA==.Leuser:BAABLAAECoEZAAIKAAYIzBwyHgALAgAKAAYIzBwyHgALAgAAAA==.',Li='Lifebloomz:BAAALAAECgMIBAAAAA==.Linaínverse:BAAALAAECggIEgAAAA==.Littlemån:BAAALAADCgEIAQAAAA==.',Lo='Lockroute:BAAALAADCgYIBgAAAA==.Loddi:BAAALAADCgcICAABLAAECgcIEAACAAAAAA==.Lorblor:BAAALAADCgIIAgAAAA==.Lothandra:BAAALAADCgQIBAAAAA==.Lowang:BAAALAAECgMIBgAAAA==.Loxus:BAAALAADCgUIBQAAAA==.',Lu='Lumie:BAAALAADCggIDwAAAA==.Lunafox:BAAALAAECgEIAQAAAA==.Lunamae:BAAALAAECgMIBAAAAA==.Luvvyaa:BAAALAAECgYICwAAAA==.',Ly='Lythomancer:BAAALAAECgYICQAAAA==.',Ma='Maddeena:BAAALAADCggIFQAAAA==.Mascal:BAAALAAECgMIAwAAAA==.Mavraylrela:BAAALAAECgQIBQAAAA==.Maxohlx:BAABLAAECoEVAAIGAAgILCFSAQCdAgAGAAgILCFSAQCdAgAAAA==.',Me='Mechacooter:BAAALAADCggICQAAAA==.Meilia:BAAALAAECgEIAgAAAA==.Mekari:BAAALAAECgYICgAAAA==.Melaii:BAAALAADCgIIAgAAAA==.Melynne:BAAALAAECgYICQAAAA==.',Mi='Milopede:BAAALAAECgYICQAAAA==.Mizukaze:BAAALAADCgUIBQAAAA==.',Mo='Moistori:BAAALAAECgEIAQAAAA==.Mormegil:BAAALAAECgYICQAAAA==.Moshimoshi:BAAALAAECgQIBAAAAA==.',Ms='Mssheph:BAAALAADCgcIDQAAAA==.',Mu='Munkeefase:BAAALAAECgMIBgAAAA==.Munkeetrance:BAAALAADCgEIAQAAAA==.Munted:BAAALAAECgYICQAAAA==.',Na='Narathax:BAAALAAECgQIBAAAAA==.Nareyne:BAAALAAECgYIDQAAAA==.Nazend:BAAALAADCggIDwABLAAECgYICQACAAAAAA==.',Nb='Nbg:BAABLAAECoEUAAILAAcIZg7LDgBQAQALAAcIZg7LDgBQAQABLAADCggICQACAAAAAA==.',Ne='Necrofeelya:BAAALAAECgUIBQAAAA==.Necrox:BAAALAAECgMIBQAAAA==.Nessará:BAAALAADCggIDwAAAA==.',Ni='Nineline:BAAALAAECgUICAAAAA==.',No='Nobgoblin:BAAALAADCgcIBwABLAADCggICAACAAAAAA==.Noein:BAAALAADCgYIBgAAAA==.',Nu='Nuraga:BAAALAAECgMICAAAAA==.',Ny='Nyte:BAAALAAECgMIAwAAAA==.',Oh='Ohnoh:BAAALAADCgcIBwAAAA==.',On='Onahue:BAAALAAECgUICgAAAA==.',Ou='Ouija:BAAALAADCggICAAAAA==.Ousini:BAAALAAECgIIAgAAAA==.',Pa='Paldaka:BAAALAAECgUIDAAAAA==.Pandaemonia:BAAALAAFFAEIAQAAAA==.Papafritas:BAAALAAECgYIDAAAAA==.Patchmen:BAAALAADCgMIAwAAAA==.Pattilicious:BAAALAAECgUICgAAAA==.',Pi='Pieglaive:BAAALAAECgUIDAAAAA==.Pierres:BAAALAADCggICAAAAA==.',Pl='Plantman:BAAALAADCggIDwAAAA==.',Pu='Puffytaco:BAAALAADCgcIBgABLAAECgMIBgACAAAAAA==.Putanginamo:BAAALAADCgUIBgAAAA==.',Qu='Quelak:BAAALAAECgYICQAAAA==.Quilue:BAAALAAECgYICQAAAA==.',Ra='Rakka:BAAALAAECgYIBgAAAA==.Ranktwo:BAAALAADCgIIAgABLAAECgcIEQACAAAAAA==.Rannmagnison:BAAALAAECgYICQAAAA==.Raquoon:BAAALAADCggIFAAAAA==.Rasonia:BAAALAADCgIIAgABLAAECgYIDAACAAAAAA==.Razumi:BAAALAAECgEIAQAAAA==.',Rh='Rhyannen:BAAALAADCggICAABLAADCggIFgACAAAAAA==.',Ri='Rinorik:BAAALAAECgYICgAAAA==.Rizzdor:BAAALAADCgMIAwABLAAECgMIBQACAAAAAA==.',Ro='Rockbiter:BAAALAADCggICwAAAA==.Rockhhard:BAAALAAECgEIAQAAAA==.Rollingman:BAAALAADCgcIBwAAAA==.',Ry='Rygaard:BAAALAAECgYICgAAAA==.Ryutiz:BAAALAAECgMIBQAAAA==.',Sa='Sanerya:BAAALAADCgYIBgAAAA==.Sapharina:BAAALAAECgYIDAAAAA==.',Sc='Scrapple:BAAALAADCgYIBgAAAA==.',Se='Searfang:BAAALAAECgYICAAAAA==.Seid:BAAALAAECgcIBwAAAA==.Selitos:BAAALAADCgUIBQAAAA==.',Sh='Shadowmidget:BAAALAAECgMIBgAAAA==.Shamarune:BAAALAADCgUIBQAAAA==.Shiho:BAAALAADCgUIBQAAAA==.Shloopnado:BAAALAADCgQIBAAAAA==.Showtime:BAAALAAECgMIAwAAAA==.',Si='Silaslunark:BAAALAAECgEIAQAAAA==.',Sk='Skarigar:BAAALAADCgcIBwAAAA==.',Sl='Slampoof:BAAALAADCgcIEQAAAA==.Slimesmile:BAAALAAECgIIAgAAAA==.',Sn='Snowscayia:BAAALAAECggIEgAAAA==.',So='Solatium:BAAALAAECgcIDQAAAA==.Solmina:BAAALAAECgYICgAAAA==.Soraya:BAAALAADCgcIBwABLAADCggIFgACAAAAAA==.Soulciopath:BAAALAADCgcIBwAAAA==.',Sp='Spartan:BAAALAAECgMIAwAAAA==.Spartanñ:BAAALAAECgIIAgAAAA==.Spicytaco:BAAALAADCggIDQABLAAECgMIBgACAAAAAA==.Spokkette:BAAALAADCgQIBAAAAA==.',Sq='Squadie:BAAALAAECgYIBwAAAA==.Squanchs:BAAALAAECgYIDAAAAA==.Squanchy:BAAALAADCgcIBwABLAAECgYIDAACAAAAAA==.',Sr='Srry:BAAALAAFFAEIAQAAAA==.',St='Sternenfall:BAAALAAECgQIBgAAAA==.Strollfuhce:BAAALAADCgYIBwAAAA==.',Su='Subjectsigma:BAAALAAECgMIBAAAAA==.Sundance:BAAALAADCggIFgAAAA==.Sunwraith:BAAALAADCggIFwAAAA==.Supersting:BAAALAADCgYIBwAAAA==.Surmise:BAAALAAECgYICQAAAA==.',Sw='Swayzeetrain:BAABLAAECoEUAAIMAAcInBnMDAD6AQAMAAcInBnMDAD6AQAAAA==.',Sy='Syrain:BAAALAADCgcIEQAAAA==.',Ta='Tabius:BAAALAAECgUIDAAAAA==.Talkingtaco:BAAALAAECgMIBgAAAA==.Taznik:BAAALAAECgEIAQAAAA==.',Te='Teeny:BAAALAADCgYIBgABLAAECgQIBwACAAAAAA==.Tempestx:BAAALAADCgcICwAAAA==.Tessek:BAAALAADCgUIBQAAAA==.',Th='Thuranin:BAAALAADCgcICAABLAAECggIFQAGACwhAA==.',To='Tore:BAAALAADCggIFAAAAA==.Totemangge:BAAALAAECgIIAgAAAA==.',Tr='Tremendous:BAAALAADCgEIAQABLAAECgQIBwACAAAAAA==.Trena:BAAALAADCgcIDgAAAA==.Tridragon:BAAALAAECgYICQAAAA==.Triggs:BAAALAADCgQIBAAAAA==.Trinadel:BAAALAAECgcIDQAAAA==.Träitors:BAAALAADCgQIBAABLAAECgYICQACAAAAAA==.',Ts='Tsarevich:BAAALAADCggIFAAAAA==.',Tu='Tuna:BAAALAAECgYICwAAAA==.',Tw='Twileaf:BAAALAAECgIIAgAAAA==.Twoinchisbig:BAAALAAECgMIBgAAAA==.',['Té']='Térror:BAAALAAECgcICgAAAA==.',Um='Umbored:BAAALAAECgUIBQABLAAECgYICwACAAAAAA==.',Un='Unsure:BAAALAADCgMIAwAAAA==.',Va='Valdoo:BAAALAADCgUIBQAAAA==.Varaxaugment:BAAALAADCgEIAQAAAA==.Varaxe:BAAALAADCgcIBwAAAA==.Varrik:BAAALAAECgYIDAAAAA==.',Ve='Velora:BAAALAADCggICwAAAA==.',Vi='Violent:BAAALAADCgMIAwAAAA==.',Vo='Vodkaxyon:BAAALAADCgcICgAAAA==.Volieu:BAAALAAECgIIAgAAAA==.Volklin:BAAALAAECgIIBAAAAA==.Volsa:BAAALAADCgcIBwAAAA==.',Wa='Walchert:BAAALAAECgEIAQAAAA==.',We='Wegl:BAAALAADCgcIDAAAAA==.Wesleypipes:BAAALAAECgMIBAAAAA==.',Wi='Winota:BAAALAADCgcIBwAAAA==.',Wo='Wolfgang:BAAALAADCggICQAAAA==.',Xa='Xandi:BAAALAAECgEIAQAAAA==.',Xe='Xelienn:BAAALAAECgMIBwAAAA==.Xelojr:BAAALAADCgcIFgAAAA==.',Xi='Xia:BAAALAAECgYICQAAAA==.',Xo='Xoilkick:BAAALAAECgMIAwAAAA==.Xoilstelth:BAAALAADCgEIAQABLAADCgcIDQACAAAAAA==.',['Xê']='Xêna:BAAALAAECgMIBAAAAA==.',Ye='Yellowsnøw:BAAALAAECgIIAgAAAA==.Yenadin:BAAALAADCgEIAQAAAA==.',Yu='Yumeshade:BAAALAAECgcIEAAAAA==.',Za='Zamari:BAAALAAECgIIAgAAAA==.Zanzabar:BAAALAAECgMIBAAAAA==.Zarraa:BAAALAADCgEIAQAAAA==.',Zo='Zoerina:BAAALAAECgYICQAAAA==.Zoobilong:BAAALAAECgYIDAAAAA==.Zorbadin:BAAALAADCggIEAAAAA==.',Zx='Zxak:BAAALAAECgYICQAAAA==.',Zy='Zyahk:BAAALAADCgQIBQAAAA==.',['Ðâ']='Ðâshy:BAAALAADCggICAABLAAECgIIAgACAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end