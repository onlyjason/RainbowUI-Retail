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
 local lookup = {'Unknown-Unknown','Warlock-Demonology','Paladin-Holy','Evoker-Devastation','Shaman-Elemental','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Affliction','Monk-Windwalker','Paladin-Retribution','Monk-Brewmaster',}; local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Acupuncher:BAAALAAECgMIBQAAAA==.',Ad='Adragon:BAAALAAECgEIAQAAAA==.Adris:BAAALAAECgEIAQAAAA==.',Al='Alaeos:BAAALAAECgEIAQAAAA==.Alcha:BAAALAAECgUIBgAAAA==.Alcuh:BAAALAAECgQIBwABLAAECgUIBgABAAAAAA==.Alkuhh:BAAALAADCgYIBgABLAAECgUIBgABAAAAAA==.Alsiwolf:BAAALAAECgEIAgAAAA==.',Am='Amargado:BAAALAADCgEIAQAAAA==.Amos:BAAALAAECgYIBwAAAA==.',An='Animeniac:BAAALAAECgEIAgAAAA==.Anubis:BAAALAADCgcIBwAAAA==.',Ap='Apsalara:BAAALAAECgcICgAAAA==.',At='Atasca:BAAALAADCggIDgABLAAECgcIDwABAAAAAA==.',Av='Avdol:BAAALAAECgUIBgABLAAECggIFgACAFoiAA==.Avienndha:BAAALAAECgEIAgAAAA==.',Aw='Awake:BAAALAADCggICAAAAA==.',Az='Azzazel:BAAALAADCggICAAAAA==.',Ba='Baelsar:BAAALAADCggIGAAAAA==.',Be='Bel:BAAALAAECgEIAQAAAA==.',Bi='Bigkillajay:BAAALAAECgEIAQAAAA==.',Bl='Bloodvalor:BAAALAADCgcIDQAAAA==.',Bo='Bobbytofva:BAAALAADCgcIEAAAAA==.Boochaka:BAAALAAECgMIAwAAAA==.',Br='Brochefski:BAAALAAECgYICAAAAA==.Brung:BAAALAAECgMIAwAAAA==.Brunhel:BAAALAAECgMIAwAAAA==.',Bu='Busterposer:BAAALAAECgEIAQAAAA==.',['Bë']='Bëan:BAAALAADCgQIBAAAAA==.',Ca='Cakesandpies:BAAALAAECgIIBAAAAA==.Candor:BAAALAADCgEIAQAAAA==.',Ce='Cerberus:BAAALAADCgcICwABLAAECgYICQABAAAAAA==.',Ch='Chain:BAAALAAECgYICQAAAA==.Chompee:BAAALAAECgEIAgAAAA==.Chouko:BAAALAAECgIIAwAAAA==.Chratos:BAAALAADCgYIBwAAAA==.Chungüs:BAAALAADCgcIBwAAAA==.',Cl='Clapt:BAAALAAECgMIAwAAAA==.',Co='Coldheart:BAAALAAECgYICgAAAA==.Confined:BAAALAADCgcIEwAAAA==.',Cr='Crazyturtle:BAAALAADCggIFwABLAADCggIEQABAAAAAA==.Creeda:BAAALAADCgYIDgAAAA==.Critcomander:BAAALAADCgQIBAAAAA==.',Da='Dacrus:BAAALAAECgcIDwAAAA==.Daleenar:BAAALAADCgYIBgAAAA==.Dalsen:BAAALAAECgYICwAAAA==.Dankchop:BAAALAAECgMIAwAAAA==.Darim:BAAALAADCgcIBwAAAA==.Darkpath:BAAALAAECgcIDQAAAA==.Dawk:BAAALAADCgcIDgAAAA==.',De='Deathturtle:BAAALAADCggIEQAAAA==.Defbrews:BAEALAAECgIIAgAAAA==.Derovia:BAAALAADCgcIBwAAAA==.',Di='Diabolikal:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Dieseldane:BAAALAADCggICAAAAA==.Dieseldaynee:BAAALAADCgMIAwAAAA==.',Do='Doktrine:BAAALAADCgMIAwAAAA==.Dorkestnight:BAAALAADCgYIBgAAAA==.',Dr='Draconus:BAAALAAECgIIAgAAAA==.',Du='Durkidurk:BAAALAADCgYIBgAAAA==.',Dy='Dyabolycal:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Dyabolykal:BAAALAAECgIIAgAAAA==.',['Dë']='Dënial:BAAALAAECgYICQAAAA==.',['Dü']='Dümah:BAAALAADCgIIAgABLAAECgcIDwABAAAAAA==.',El='Ellyanna:BAAALAAECgEIAQAAAA==.Ellyore:BAAALAADCgMIBAABLAAECgEIAQABAAAAAA==.Elsh:BAAALAAECgIIAgABLAAECggIFgADADohAA==.Elsharion:BAABLAAECoEWAAIDAAgIOiHzAQDuAgADAAgIOiHzAQDuAgAAAA==.Elsharyon:BAAALAADCggICAAAAA==.',Em='Emrite:BAAALAADCgcIBwAAAA==.',Fa='Fastasheet:BAAALAAFFAMIAwAAAA==.Fatthor:BAAALAADCgYIBgAAAA==.',Fe='Felsheet:BAAALAADCgcIBwAAAA==.',Fi='Fill:BAAALAADCgcIBwABLAAECggIFgAEAOciAA==.',Fl='Flehd:BAAALAAECgIIAgAAAA==.Flehtwo:BAABLAAECoEWAAMFAAgI/hNaKwBQAQAFAAUIyxJaKwBQAQAGAAgIBQfSMgBQAQAAAA==.',Fo='Forestdunk:BAAALAADCgUIBwAAAA==.',Fr='Fragilelimbs:BAAALAAECgMIAwAAAA==.Fraglen:BAAALAAECgYICQAAAA==.Frikk:BAAALAADCgYIDAABLAADCgYIDgABAAAAAA==.',Fu='Furriosa:BAAALAADCgcIDgAAAA==.',Fy='Fyrefest:BAAALAADCggICAABLAAECgIIAwABAAAAAA==.',Ga='Garbagecan:BAAALAADCgMIAwAAAA==.',Ge='Genjyosanzo:BAAALAADCgcIDgAAAA==.Gertrude:BAAALAAECgEIAgAAAA==.',Gr='Greydrizzle:BAAALAADCgcICgAAAA==.Grimblestick:BAAALAADCgcIBwAAAA==.Grito:BAAALAADCggIFgAAAA==.Grokdepaly:BAAALAADCgcICQAAAA==.Groppum:BAAALAAECgcIDwAAAA==.',Gu='Guts:BAAALAAECgEIAQAAAA==.',Ha='Hakwaztok:BAAALAADCggIBwAAAA==.Halsina:BAAALAAECgEIAQAAAA==.',He='Healawar:BAAALAADCggIFQAAAA==.Hetairoii:BAAALAADCgcIDgAAAA==.Hexxytime:BAAALAAECgMIAwAAAA==.Heyspaghetti:BAAALAAECgYIDgABLAAECgcIDwABAAAAAA==.',Hi='Hilazy:BAAALAAECgEIAQAAAA==.',Ho='Holyfed:BAAALAADCggIEgAAAA==.Holypickles:BAAALAADCgcIDQABLAAECgIIBAABAAAAAA==.Honeydèw:BAAALAAECgEIAQAAAA==.Hoofdaddy:BAAALAAECgEIAQAAAA==.Hotdog:BAAALAAECgEIAQAAAA==.',Hy='Hypnotoad:BAAALAAECgUICAAAAA==.',Ih='Ihavenofutur:BAAALAADCgMIAwAAAA==.',Il='Illidantwo:BAABLAAECoEYAAMHAAgIRCKnBgAVAwAHAAgIPCKnBgAVAwAIAAIIISRVGQDEAAAAAA==.',Im='Implications:BAAALAAECgMIAwAAAA==.',In='Interuptus:BAAALAAECgYIDQAAAA==.Inuk:BAAALAAECgIIAwAAAA==.',Ir='Irtehmauler:BAAALAAECgMIAwAAAA==.',Is='Isalia:BAAALAADCgcIBwAAAA==.',Ja='Jahz:BAAALAAECgEIAQAAAA==.',Je='Jennaayy:BAAALAADCgQIBgAAAA==.Jenstonedart:BAAALAAECgEIAQAAAA==.Jeryeth:BAAALAAECgEIAQAAAA==.Jerymander:BAAALAAECgEIAQAAAA==.',Jm='Jmage:BAAALAADCgQIBAAAAA==.',Ju='Judidench:BAAALAAECgYICQAAAA==.',Ka='Kain:BAAALAAECgMIAwAAAA==.Kanda:BAAALAADCggICAAAAA==.',Ke='Kelkar:BAAALAAECgYICAAAAA==.',Ki='Kimbelison:BAAALAADCgcIBwAAAA==.Kiwí:BAAALAAECgYICQAAAA==.',Ko='Konen:BAAALAAECgEIAgAAAA==.Koozer:BAAALAAECgYICQAAAA==.',Kr='Krasavice:BAAALAAECgMIAwAAAA==.Krisp:BAAALAADCgcIBQABLAADCggIEgABAAAAAA==.',La='Laeda:BAAALAAECgMIBgAAAA==.Laylen:BAAALAADCgMIAwAAAA==.',Le='Leathal:BAAALAAECgMIAwAAAA==.Leathalhealz:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.',Li='Lightsmithin:BAAALAADCgQIBAAAAA==.Linkinspark:BAAALAADCgcIBwAAAA==.',Lo='Lock:BAAALAADCgcIBwAAAA==.Lohruttof:BAAALAADCgcICQAAAA==.Lokust:BAAALAAECgMIAwAAAA==.Lorthras:BAAALAADCgIIAgAAAA==.',Ly='Lycanius:BAAALAAECgYIDQAAAA==.Lyrien:BAAALAADCgcIAQAAAA==.Lysixaa:BAAALAADCgcIDAAAAA==.',Ma='Malf:BAAALAADCgQIBAAAAA==.Malëk:BAAALAAECgcIDwAAAA==.Mamus:BAAALAADCggIDwAAAA==.Manabanana:BAAALAADCgEIAQAAAA==.Mandiell:BAAALAAECgYICQAAAA==.Maximus:BAAALAAECgIIAgAAAA==.',Me='Mellowlizard:BAABLAAECoEWAAQCAAgIWiLnAgBTAgACAAcIFCHnAgBTAgAJAAMI9huuOQDxAAAKAAEIxBBoJwBPAAAAAA==.Metuss:BAAALAAECgMIAwAAAA==.Mezaa:BAAALAAECgUICAAAAA==.',Mi='Mic:BAAALAADCggIDgAAAA==.Mira:BAAALAAECgMIAwAAAA==.',Mk='Mkicon:BAAALAAECgMIAwAAAA==.Mkultra:BAAALAADCggICwAAAA==.',Mo='Mogmoog:BAAALAAECgEIAgAAAA==.Montau:BAAALAAECgMIBQAAAA==.Moonangel:BAAALAAECgEIAgAAAA==.Morbodan:BAAALAAECgQIBwAAAA==.',Mu='Mudget:BAABLAAECoEVAAQJAAgIbCKiEgAzAgAJAAYIGCGiEgAzAgACAAUI0iL3DwCHAQAKAAEIJh7wJABYAAAAAA==.Multanni:BAAALAAECgMIAwAAAA==.',My='Myonecrosis:BAAALAAECgEIAgAAAA==.',Na='Nagusame:BAAALAADCgcIBwAAAA==.',Ne='Nebrets:BAAALAADCgYIBgAAAA==.Necroboi:BAAALAADCgMIAwAAAA==.Neektwonik:BAAALAAECgEIAQAAAA==.Nethus:BAAALAADCgQIBAAAAA==.Nezal:BAAALAADCgMIBgAAAA==.',Ni='Nightelyn:BAAALAAECgEIAQAAAA==.Nimbus:BAACLAAFFIEFAAIEAAMIsxitAgAAAQAEAAMIsxitAgAAAQAsAAQKgRcAAgQACAhKJbMBAEsDAAQACAhKJbMBAEsDAAAA.',No='Nolwenn:BAAALAAECgEIAQAAAA==.Nomäd:BAAALAAECgEIAQAAAA==.',Nr='Nrlhunter:BAAALAAECgMIBAAAAA==.',Og='Ogmount:BAAALAAECgIIAgAAAA==.',Oh='Ohnomeow:BAAALAAECgYICAAAAA==.',Ok='Okasah:BAAALAAECgYIBgAAAA==.',Ou='Outofmilk:BAAALAAECgEIAQABLAAECgEIAQABAAAAAA==.',Pa='Palguard:BAAALAADCgYIBgAAAA==.',Pe='Pearbear:BAAALAADCgYICQABLAAECgYICQABAAAAAA==.Perrito:BAAALAAECgMIBgAAAA==.',Ph='Phrash:BAABLAAECoEVAAILAAgIxCRNAgAdAwALAAgIxCRNAgAdAwABLAAECggIFgAEAOciAA==.',Pi='Pippinbippin:BAAALAADCgYIBgAAAA==.',Pl='Plex:BAAALAAECgYICQAAAA==.Plexqt:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.',Po='Poocatpokop:BAAALAADCggIFQAAAA==.Poolparty:BAAALAAECgIIAwAAAA==.Poptarts:BAAALAAECgYIBgAAAA==.Porcell:BAAALAAECgIIAwAAAA==.',Pr='Premiumgank:BAAALAAECgMIAwAAAA==.',Ra='Rasttaman:BAAALAADCggICAAAAA==.',Re='Redwar:BAAALAADCgYIBwAAAA==.Rencili:BAAALAADCgcIDAAAAA==.Rengots:BAAALAADCggIDgAAAA==.Renne:BAAALAAECgYICQAAAA==.Reph:BAAALAAECgMIAwAAAA==.',Ro='Rocktober:BAAALAADCggICwAAAA==.Rokkoz:BAAALAAECgMIAwAAAA==.Rosellie:BAAALAADCgYIBgAAAA==.',['Rí']='Ríta:BAAALAADCgcICQAAAA==.',Sa='Saberosneaky:BAAALAAECgEIAgAAAA==.Saloesh:BAAALAADCgcIDwAAAA==.',Sc='Schwauszbuck:BAAALAAECgEIAQAAAA==.Scryd:BAAALAAECgIIAgAAAA==.',Sh='Shak:BAABLAAECoEWAAMMAAgI0CS4AQBvAwAMAAgI0CS4AQBvAwADAAEIHAdhMQA6AAAAAA==.Sharpshooter:BAAALAAECgEIAQAAAA==.Shirokhan:BAAALAAECggIBgAAAA==.Shleke:BAAALAADCgIIAgAAAA==.Shockysheet:BAABLAAECoEWAAIFAAgIxBiXEgAqAgAFAAgIxBiXEgAqAgAAAA==.Shruiken:BAAALAADCgYIBgAAAA==.',Si='Sidewinded:BAAALAADCgMIAwAAAA==.Sidewinderx:BAAALAADCgEIAQAAAA==.Sidewinderxi:BAAALAADCgcIBwAAAA==.',Sn='Snowbunni:BAAALAAECgEIAQAAAA==.Snowman:BAAALAADCggICAAAAA==.',St='Starvnmarvn:BAAALAAECgMIAwAAAA==.Stupidaso:BAAALAADCgYIDgAAAA==.',Su='Sugarcrits:BAAALAAECgEIAQAAAA==.Sunchipzz:BAAALAADCgUIBQAAAA==.Sundayschool:BAAALAADCgYIBgAAAA==.Sunwing:BAAALAADCgIIAQAAAA==.',Sw='Sway:BAAALAAECgMIBgAAAA==.',['Sè']='Sèrënity:BAAALAAECgYICwAAAA==.',['Só']='Sóozabimaru:BAAALAADCgQIBAAAAA==.',Ta='Tankarmor:BAAALAAECgMIAwAAAA==.Tanner:BAAALAADCgcIBwAAAA==.',Te='Teekeez:BAAALAADCggIGQAAAA==.',Th='Thela:BAAALAADCgQIBQABLAAECgcIDwABAAAAAA==.',Ti='Tiamat:BAAALAAECgYICQAAAA==.Tiffina:BAAALAAECgMIAwAAAA==.',To='Tomvokhin:BAAALAAECgMIAwAAAA==.',Tr='Traus:BAAALAADCgcIDAAAAA==.Treeberk:BAAALAADCgIIAgABLAADCgcIBwABAAAAAA==.Trolli:BAAALAAECgYIDwAAAA==.',Tw='Twixx:BAAALAAECgUICAAAAA==.Twîsted:BAAALAADCggICAABLAAECggIFgAMANAkAA==.',['Tî']='Tîtån:BAAALAADCggICAAAAA==.',Uc='Uciecha:BAAALAAECgYICAAAAA==.',Up='Up:BAABLAAECoEWAAIEAAgI5yLSAwANAwAEAAgI5yLSAwANAwAAAA==.',Va='Vaelthira:BAAALAADCgUIBQAAAA==.Valdamos:BAAALAAECgcIDwAAAA==.Valgryn:BAAALAADCgYIAgAAAA==.',Ve='Velmalthea:BAAALAAECgEIAgAAAA==.Venk:BAAALAAECgcIEAAAAA==.',Vg='Vgmking:BAAALAAECgMIAwAAAA==.',Vi='Viqqiv:BAAALAAECgcIDwAAAA==.',Vo='Vokzhen:BAAALAAECgMIBgAAAA==.Volescu:BAAALAAECgMIAwAAAA==.Voncour:BAAALAADCgYIDAAAAA==.Vonker:BAAALAAECgcIEwAAAA==.Vonkhai:BAAALAAECgMIBQAAAA==.',Vy='Vyral:BAAALAAECgMIBgAAAA==.',Wa='Wagnerhalha:BAAALAAECgYICAAAAA==.Walkerboah:BAAALAAECgMIAwAAAA==.Watergun:BAAALAAECgYIBwAAAA==.',Wh='Whycanic:BAAALAAECgEIAQAAAA==.',Wi='Willowing:BAAALAADCggICAAAAA==.',Xt='Xtoddgam:BAAALAADCgMIBgAAAA==.',Za='Zaib:BAAALAAECgcIDAAAAA==.Zarika:BAAALAAECgIIAgABLAAECggIFgALADAmAA==.Zarì:BAABLAAECoEWAAMLAAgIMCZTAAB+AwALAAgIMCZTAAB+AwANAAYIZBTuDwAxAQAAAA==.',Ze='Zebulon:BAAALAAECgYIDwAAAA==.Zenazure:BAAALAADCgcIDgAAAA==.Zenio:BAAALAADCggICAAAAA==.Zepides:BAAALAAECgYICgAAAA==.',['Él']='Élros:BAAALAAECgEIAQAAAA==.',['Ôd']='Ôdìn:BAAALAADCgcIBwAAAQ==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end