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
 local lookup = {'Unknown-Unknown','DeathKnight-Blood',}; local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adara:BAAALAAECggIDwAAAA==.Adgame:BAAALAADCgQIBAAAAA==.',Ae='Aeserix:BAAALAAECgEIAQAAAA==.',Af='Aftershocks:BAAALAAECgYIDAAAAA==.',Ag='Agarmon:BAAALAAECgcIDAAAAA==.Agarne:BAAALAAECgIIAwAAAA==.Agman:BAAALAADCgYIBgAAAA==.',Ai='Aimster:BAAALAADCgEIAQAAAA==.',Al='Allaris:BAAALAAECgMIBQAAAA==.Altryn:BAAALAADCgEIAQAAAA==.Alundrablaze:BAAALAAECgYICAAAAA==.',Am='Amarixa:BAAALAADCgMIAwAAAA==.',An='Anrraakk:BAAALAADCgcIEgAAAA==.',Ar='Aranthino:BAAALAAECgIIAwAAAA==.Aryabhatta:BAAALAAECgMIAwAAAA==.',As='Asmodeaus:BAAALAADCgcICQAAAA==.',Au='Audwald:BAAALAADCgMIAgAAAA==.',Av='Avalys:BAAALAADCgIIAgAAAA==.',Az='Azshanne:BAAALAADCgUIBQAAAA==.',Ba='Barryallen:BAAALAAECgMIBwAAAA==.',Be='Beansination:BAAALAAECgYICwAAAA==.Beefsupriem:BAAALAADCggICAAAAA==.Beelzerrbub:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Belari:BAAALAADCgMIAwAAAA==.Bettywhyte:BAAALAADCgQIBAAAAA==.Beêfyboi:BAAALAADCgMIAwAAAA==.',Bi='Bigcheese:BAAALAADCggIDwAAAA==.Bigdogdad:BAAALAADCgYICgAAAA==.Biohazard:BAAALAAECgcICQAAAA==.',Bl='Blackfuse:BAAALAADCgcIBwAAAA==.Blacksalamí:BAAALAADCgIIAgAAAA==.Blightpaw:BAAALAAECggIDwAAAA==.',Bo='Bonemayka:BAAALAAECgEIAQAAAA==.',Br='Bracelet:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Brewsandboos:BAAALAAECgMIAwAAAA==.',Ch='Chronokite:BAAALAAECgMIAwAAAA==.',Ci='Cincrat:BAAALAADCgQIBAAAAA==.',Cl='Clayman:BAAALAADCgUIBQAAAA==.',Co='Coey:BAAALAADCgYIBgAAAA==.Cosmosfocker:BAAALAADCggIBwAAAA==.',Da='Dankshot:BAAALAAECgEIAgAAAA==.Darafragen:BAAALAAECgYICgAAAA==.Darkterrors:BAAALAAECgMIAwAAAA==.',De='Deader:BAAALAAECgMIAwAAAA==.Deddwarf:BAAALAAECgMIAwAAAA==.Delithel:BAAALAADCgMIAwAAAA==.Delomnas:BAAALAADCgMIAwABLAAECgIIAgABAAAAAA==.',Di='Displace:BAAALAAECgIIAgAAAA==.Divish:BAAALAAECgQIBgAAAA==.',Do='Dodge:BAAALAAECgMIAwAAAA==.Dommymommy:BAAALAADCgcIBQAAAA==.',Dr='Dragonbourne:BAAALAADCggICwAAAA==.Drillanne:BAAALAAECgMIAwAAAA==.Druecc:BAAALAAECgMIBQAAAA==.Druidlord:BAAALAAECgIIAgAAAA==.',Du='Duckyfur:BAAALAAECgcIDAAAAA==.',Ed='Edwin:BAAALAAECgQIBgAAAA==.',Ei='Eirwind:BAAALAAECgEIAQAAAA==.',El='Ellennia:BAAALAADCgUICAAAAA==.',Em='Emdeef:BAAALAADCgMIAwAAAA==.Emeraldlight:BAAALAADCggICAAAAA==.',Er='Eraagon:BAAALAAECgMIAwAAAA==.',Es='Esh:BAABLAAECoEYAAICAAgIGyPGAQAbAwACAAgIGyPGAQAbAwAAAA==.Essence:BAAALAADCgUIBQAAAA==.',Ev='Evosaber:BAAALAADCgYICAAAAA==.',Fa='Faedina:BAAALAADCgcIBwAAAA==.Fanara:BAAALAADCggICwAAAA==.',Fe='Feardotfear:BAAALAADCgMIAwAAAA==.',Ff='Ffej:BAAALAAECgMIAwAAAA==.',Fi='Fitua:BAAALAAECgEIAQAAAA==.',Fo='Fordemocracy:BAAALAADCgEIAQAAAA==.Foutre:BAAALAADCggIDwAAAA==.',Fr='Fryas:BAAALAAECgEIAQAAAA==.',Fu='Fuzzytotems:BAAALAADCgMIAwAAAA==.',Fy='Fynnick:BAAALAAECgUIBgAAAA==.',['Få']='Fång:BAAALAAECgEIAQAAAA==.',Ge='Getlnmyvan:BAAALAAECgcIDQAAAA==.',Gi='Gile:BAAALAADCggICAAAAA==.',Gn='Gnomesaiyan:BAAALAADCgYIBgAAAA==.',Go='Goinsolo:BAAALAAECgcIDQAAAA==.Gorvax:BAAALAAECgMIBQAAAA==.',Gr='Greed:BAAALAAECgcIDQAAAA==.',Gw='Gwenledyr:BAAALAAECgYIDQAAAA==.',He='Hellenkeller:BAAALAAECgMIBQAAAA==.',Hu='Hurken:BAAALAADCggICAAAAA==.',Ic='Icelynn:BAAALAADCggICwAAAA==.',Il='Ilivedead:BAAALAADCgEIAQAAAA==.',In='Iniquitous:BAAALAAECgMIAwAAAA==.',Ir='Irwarrioryo:BAAALAAECgMIBgAAAA==.',Ja='Jamby:BAAALAADCgEIAQAAAA==.Jast:BAAALAADCggIDwAAAA==.',Jb='Jblaze:BAAALAADCgcIDQAAAA==.',Je='Jerix:BAAALAAECgQIBAAAAA==.',Ju='Jupiter:BAAALAAECgEIAQAAAA==.Juzomido:BAAALAADCgcIBwAAAA==.',Ka='Kades:BAAALAAECgEIAQAAAA==.Karai:BAAALAAECgEIAQABLAAECgcICQABAAAAAA==.Karupted:BAAALAADCggIFQAAAA==.Katianna:BAAALAAECgYIDQAAAA==.',Ke='Kelanath:BAAALAADCggIFgAAAA==.',Kh='Khalli:BAAALAAECgMIAwAAAA==.',Ki='Kirchhoff:BAAALAADCgUIBQAAAA==.',Kn='Knahs:BAAALAADCgYIBgAAAA==.',Ko='Kohemoth:BAAALAADCgcIBwAAAA==.',Kr='Kronoz:BAAALAADCggIGAAAAA==.',Ku='Kulrig:BAAALAAFFAEIAQAAAA==.',Ky='Kynzi:BAAALAADCgcICgAAAA==.',['Kï']='Kïnkerbell:BAAALAADCgIIAgABLAAECgMIBAABAAAAAA==.',La='Lastmark:BAAALAADCggICQAAAA==.',Lo='Lovetaco:BAAALAADCggIDQAAAA==.',Lu='Lunaari:BAAALAAECgIIAgAAAA==.Lunalei:BAAALAADCggIEQAAAA==.Lunastarvale:BAAALAAECgcICwAAAA==.',Ma='Maesunrays:BAAALAADCgEIAQAAAA==.Malganon:BAAALAAECgMIBwAAAA==.Marigosa:BAAALAADCgUIBQAAAA==.Martheiran:BAAALAAECgMIBQAAAA==.Mathelmana:BAAALAAECgMIBQAAAA==.',Me='Melarorah:BAAALAAECgYICgAAAA==.',Mi='Mikeknahs:BAAALAADCgMIBQAAAA==.Miro:BAAALAADCgMIAwAAAA==.Miseral:BAAALAADCggICAAAAA==.',Mo='Monklee:BAAALAAECgQIBgAAAA==.Mordakka:BAAALAAECgEIAQABLAAFFAEIAQABAAAAAA==.Morghella:BAAALAAECgcIDAAAAA==.Morphism:BAAALAAECgIIAwAAAA==.Morphvenzerr:BAAALAAECgMIAwAAAA==.Mouthbreathr:BAAALAADCggICAAAAA==.',My='Mynamejeff:BAAALAADCgMIAwAAAA==.',Na='Nacazul:BAAALAAECgYIDwAAAA==.Nasman:BAAALAADCgQIBAAAAA==.',Ne='Nesmae:BAAALAAECgMIAwABLAAECgYICgABAAAAAA==.',Ni='Nickromancer:BAAALAADCgcICgAAAA==.',No='Noirra:BAAALAAECgYICgAAAA==.',Nu='Nutty:BAAALAAECgUIBQAAAA==.',['Nü']='Nürselandrei:BAAALAAECgMIBQAAAA==.',Ol='Oleyinka:BAAALAADCgUIBQAAAA==.',Or='Orcnicky:BAAALAAECgIIAgAAAA==.',Ov='Overfrosty:BAAALAAECgMIBQAAAA==.',Pa='Packrabit:BAAALAADCgIIAgAAAA==.Paladino:BAAALAADCggIGAAAAA==.Pawwz:BAAALAAECgMIAwAAAA==.',Pe='Peng:BAAALAAECgMIAwAAAA==.',Pk='Pkay:BAAALAADCgIIAgAAAA==.',Po='Polarsmash:BAAALAADCgUIBQAAAA==.Popedope:BAAALAADCgEIAQABLAAECgcICQABAAAAAA==.',Pr='Prodigy:BAAALAAECgEIAQAAAA==.Prìde:BAAALAAECgMIBAAAAA==.',Pu='Purgedfire:BAAALAADCggIDQAAAA==.',Ra='Raal:BAAALAAECgMIAwAAAA==.Rampancy:BAAALAADCgEIAQABLAAECgcICQABAAAAAA==.Ransus:BAAALAADCgQIBAAAAA==.Ravon:BAAALAAECgQIBwAAAA==.Rayda:BAAALAAECgMIBAAAAA==.',Re='Renka:BAAALAAECgYICAAAAA==.Reuss:BAAALAADCgYIBwAAAA==.',Ri='Rianne:BAAALAAECgEIAQAAAA==.',Ro='Rowanbow:BAAALAADCgcIDQAAAA==.',Ru='Rubik:BAAALAADCggIDwAAAA==.',['Ré']='Rédd:BAAALAAECgMIBQAAAA==.',Sa='Saberhawk:BAAALAADCggIEAAAAA==.Sakurazuka:BAAALAAECgIIAgAAAA==.Sancey:BAAALAADCgEIAQAAAA==.Sandbag:BAAALAAECgEIAQAAAA==.Sandseyi:BAAALAADCgYICgAAAA==.Sarelyn:BAAALAAECgEIAQAAAA==.',Sc='Scoobyxdooby:BAAALAAECgMIAwAAAA==.Scottcooney:BAAALAAECgMIBQAAAA==.Scycon:BAAALAADCgQIBAAAAA==.',Se='Sealedkyubi:BAAALAADCggIEAAAAA==.Selinicus:BAAALAADCgUIDAAAAA==.Servilia:BAAALAADCggIDQAAAA==.',Sh='Sharindlar:BAAALAADCggIFgAAAA==.Shlopers:BAAALAADCgUIBQAAAA==.Shmastus:BAAALAADCgcIDgAAAA==.Shokanu:BAAALAAECgcICwAAAA==.Shoun:BAAALAADCggICAAAAA==.',Si='Sib:BAAALAAECgMIBQAAAA==.Silverlight:BAAALAADCgIIAgABLAAFFAEIAQABAAAAAA==.',Sk='Skeets:BAAALAADCggIDwAAAA==.',Sm='Smölder:BAAALAAECgMIBQAAAA==.',Sn='Snakie:BAAALAAECgEIAQAAAA==.',So='Sofieeus:BAAALAAECgMIBwAAAA==.Sofshammy:BAAALAADCgUICgAAAA==.Sokorag:BAAALAAECgQIBAAAAA==.Sonofgods:BAAALAAECgIIAwAAAA==.',Sp='Sparklefárts:BAAALAAECgEIAQAAAA==.',St='Stall:BAAALAADCgUIBAABLAADCgYIBgABAAAAAA==.Starrbuck:BAAALAAECgMIBQAAAA==.Stephii:BAAALAAECgIIAgAAAA==.Stormblåst:BAAALAAECgIIBAAAAA==.Stridor:BAAALAAECgMIAwAAAA==.Stryke:BAAALAAECgMIAwAAAA==.',Su='Suterareta:BAAALAAECgIIAgAAAA==.',Ta='Taksun:BAAALAAECgMIBwAAAA==.Talianka:BAAALAAECgMIAwAAAA==.Tav:BAAALAADCgcICQAAAA==.',Te='Tennesseejed:BAAALAADCgUIAwAAAA==.',Th='Thaia:BAAALAAECgMIBAAAAA==.Thaladrin:BAAALAAECgMIAwAAAA==.Thalagar:BAAALAADCgMIAwAAAA==.Thannatos:BAAALAADCgIIAgAAAA==.Throwinbolts:BAAALAADCgUIBQAAAA==.',Ti='Tianara:BAAALAADCgQIBAABLAAECgcICQABAAAAAA==.Titania:BAAALAADCgMIBgAAAA==.',Tj='Tjismyname:BAAALAADCggIDwAAAA==.',Tr='Tritium:BAAALAAECgIIAgAAAA==.Tromglok:BAAALAADCgYIBgAAAA==.Trurala:BAAALAAECgMIBgAAAA==.',Tu='Tubby:BAAALAAECgYIDAAAAA==.',Ty='Tyleinthrel:BAAALAADCgMIAwAAAA==.',Ue='Uelfaen:BAAALAADCgUIBQAAAA==.',Ug='Uggo:BAAALAAECgcIEAAAAA==.',Ul='Ulyssès:BAAALAADCgYIBgAAAA==.',Ur='Urgott:BAAALAAECgQIBgAAAA==.Ursalaisis:BAAALAADCgYICgAAAA==.',Va='Valentyn:BAAALAAECgEIAQAAAA==.',Ve='Vesperial:BAAALAADCggIDwAAAA==.',Vi='Victus:BAAALAADCgYIBgAAAA==.',Vu='Vuskar:BAAALAAECgQIBQAAAA==.',We='Wespally:BAAALAADCggIAgAAAA==.',Wh='Whitefangx:BAAALAAECggIBAAAAA==.',Xi='Xinther:BAAALAADCgcICQAAAA==.',Xx='Xxluminati:BAAALAADCgUIBQAAAA==.',Ya='Yakushimaru:BAAALAAECgMIBwAAAA==.',Za='Zarella:BAAALAADCgEIAQABLAAECgEIAQABAAAAAA==.Zarifia:BAAALAAECgEIAQAAAA==.',Ze='Zeb:BAAALAADCgcIBwAAAA==.Zefren:BAAALAAECgYIBgAAAA==.Zeith:BAAALAAECgQIBgAAAA==.Zeta:BAAALAAECgQIBgAAAA==.',Zi='Zildon:BAAALAADCgMIAwAAAA==.',Zu='Zugzüg:BAAALAADCgYICgAAAA==.',['Åm']='Åmerica:BAAALAADCggICQABLAAECgMIBwABAAAAAA==.',['Ül']='Ülysses:BAAALAADCgYICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end