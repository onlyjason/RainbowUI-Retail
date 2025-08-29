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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','Mage-Arcane','Monk-Mistweaver','Priest-Holy',}; local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Ablivien:BAAALAAFFAIIAgAAAA==.',Ad='Adinne:BAAALAADCgcICQAAAA==.Adroiel:BAAALAADCgcIBwAAAA==.',Ah='Ahron:BAAALAAECgYICwAAAA==.',Ai='Aica:BAAALAADCgQIBAAAAA==.Ainjel:BAAALAADCgcIBwAAAA==.',Al='Aleuseche:BAAALAAECgUICQAAAA==.Alexdh:BAAALAADCggICQAAAA==.Alohomora:BAAALAADCggICAAAAA==.',An='Antarès:BAAALAAECgcIDwAAAA==.Antifight:BAAALAAECgQICAAAAA==.Antàrès:BAAALAAECgEIAQABLAAECgcIDwABAAAAAA==.',Aq='Aquílés:BAAALAADCgQIBwAAAA==.',Ar='Arazensetal:BAAALAAECgIIAwAAAA==.Arcanizzon:BAAALAADCggIEQAAAA==.Arctre:BAAALAAECgIIAgAAAA==.Ardênt:BAAALAAECgEIAgAAAA==.Arrowheart:BAAALAADCggICAAAAA==.',At='Ation:BAAALAADCgYICQAAAA==.',Au='Aukatsang:BAAALAAFFAIIAgAAAA==.Aury:BAAALAAECgcIDwAAAA==.',Av='Avalonsgf:BAAALAADCggICQAAAA==.Aviator:BAAALAAECgMIBQAAAA==.',Az='Azymor:BAAALAAECgMIBgAAAA==.',Ba='Baladeva:BAAALAAECgIIAwAAAA==.Bandmage:BAAALAAECgEIAQAAAA==.Bau:BAAALAADCggICQAAAA==.Bay:BAACLAAFFIEFAAICAAMImxXUAgD9AAACAAMImxXUAgD9AAAsAAQKgRcAAgIACAgnI0gEAAEDAAIACAgnI0gEAAEDAAAA.',Be='Bearomir:BAAALAAECgYIDAAAAA==.Beekrazy:BAAALAADCgIIAgAAAA==.Beersnob:BAAALAAECgMIBwAAAA==.Benjam:BAAALAAECgEIAQAAAA==.',Bi='Bigdawg:BAAALAADCggIDQAAAA==.Bigsteve:BAAALAAECgIIAwAAAA==.Bitcoined:BAAALAAECgcIDQAAAA==.',Bl='Blanket:BAAALAAECgYIBwAAAA==.Blitzo:BAAALAADCgcIBwAAAA==.Blóódyfrost:BAAALAADCggIBwAAAA==.',Bo='Bottomdps:BAAALAAECgMIBQAAAA==.',Br='Brewthos:BAAALAAECgMIBQAAAA==.',Bu='Buttonmashèr:BAAALAAECgIIAgAAAA==.',['Bè']='Bèyork:BAAALAADCgcIDgAAAA==.',Ca='Camacho:BAAALAADCgEIAQAAAA==.Canowhoopass:BAAALAAECgMIBAAAAA==.Carelyn:BAAALAADCgQIBAAAAA==.',Ce='Celaneo:BAAALAAECgIIAgAAAA==.Celegrimbor:BAAALAAECgMIAwAAAA==.Cereas:BAAALAADCggIFgAAAA==.',Cl='Cliftonx:BAAALAAECgMIBwAAAA==.Clukdogg:BAAALAAFFAIIAgAAAA==.',Co='Combination:BAAALAAECgIIAwAAAA==.Copaan:BAAALAADCgQIBAAAAA==.Corvenall:BAAALAADCggIDwAAAA==.',Cr='Crossbow:BAAALAADCggIEAAAAA==.',Cy='Cystalis:BAAALAADCgcICAAAAA==.',Da='Daddyavocado:BAAALAAECgYICQAAAA==.Darkbaret:BAAALAADCgYIBgAAAA==.Darknesmonk:BAAALAAECgEIAQAAAA==.Darknesworg:BAAALAAECgcICgAAAA==.Datia:BAAALAAECgUIBwABLAAECgcIDgABAAAAAA==.Davand:BAAALAAECgYIBgAAAA==.Davinah:BAAALAAECgQIBAAAAA==.',De='Deana:BAAALAADCggICAAAAA==.Deondre:BAAALAADCgUICQAAAA==.Destrothos:BAAALAAECgMIBgAAAA==.Devilsrain:BAAALAAECgIIAwAAAA==.Devoutheart:BAAALAAECgEIAQABLAAECgMIBAABAAAAAA==.',Di='Diehappy:BAAALAADCgcICQAAAA==.Divina:BAAALAADCgYIBgAAAA==.',Do='Dotaantimage:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Dp='Dpsvendor:BAAALAAECgEIAQAAAA==.',Dr='Draenyra:BAAALAADCgMIBQAAAA==.Dragonshark:BAAALAADCgQIBAAAAA==.Drasek:BAAALAAECgMIAwAAAA==.Dreamq:BAABLAAECoEYAAIDAAgI8SKbBQAeAwADAAgI8SKbBQAeAwAAAA==.Druiela:BAAALAADCgUICQAAAA==.Drylie:BAAALAAFFAIIAgAAAA==.Drô:BAAALAADCgcIBwAAAA==.',Dt='Dtinnel:BAAALAAECgMIBAABLAAECgYICQABAAAAAA==.',Du='Duck:BAAALAADCggIEQAAAA==.',['Dò']='Dòt:BAAALAADCgQIBAAAAA==.',Ea='Eaglemas:BAAALAADCgcIBwAAAA==.',El='Elandra:BAAALAAECgcICwAAAA==.Elinaar:BAAALAADCggIAgAAAA==.',Em='Emela:BAAALAADCggICQAAAA==.Emmone:BAAALAADCggIFQAAAA==.',En='Energydrink:BAAALAAECgcICwAAAA==.',Ev='Evilrook:BAAALAADCgcIBQAAAA==.',Fa='Fairyfire:BAAALAADCgMIAwAAAA==.Faunna:BAAALAAECgUICwAAAA==.',Fe='Felicopter:BAAALAAECgMIBwAAAA==.Felrysa:BAAALAADCgIIAgAAAA==.Felyeah:BAAALAADCgYIBgAAAA==.',Fi='Fiyona:BAAALAADCgUIBgAAAA==.',Fr='Frathi:BAAALAADCgcIBwAAAA==.Fresnutt:BAAALAAECgMIAwAAAA==.Frrank:BAAALAAFFAIIAgAAAA==.',Ga='Galcain:BAAALAAECgYIBgAAAA==.Gantz:BAAALAAECgEIAgAAAA==.',Gh='Ghostmain:BAAALAAECgIIAgAAAA==.',Go='Gorizarev:BAAALAAECgEIAQAAAA==.',Gr='Grumandel:BAAALAAECgIIAwAAAA==.',Gu='Gudetama:BAAALAAECgEIAQAAAA==.',Gw='Gwydion:BAAALAAECgUICAAAAA==.',Gy='Gywen:BAAALAAECgEIAQAAAA==.',Ha='Hankhill:BAAALAAECgIIAwAAAA==.Hanma:BAAALAADCggIDAAAAA==.Harribel:BAAALAAECgEIAQAAAA==.Harunohana:BAAALAADCgEIAQAAAA==.',He='Healjamin:BAAALAADCggIDwABLAAECgEIAQABAAAAAA==.Heartblade:BAAALAAECgMIAwAAAA==.',Hi='Hiroki:BAAALAAECgQIBgAAAA==.',Ho='Holybjoly:BAAALAAECgUIBwAAAA==.',Hu='Huxter:BAAALAAECgIIAgAAAA==.',Hy='Hycenoth:BAAALAAECgQIBQAAAA==.Hypnø:BAAALAADCgUIBQAAAA==.Hyun:BAAALAADCggICAAAAA==.',Je='Jehannum:BAAALAAECgIIAgAAAA==.Jesibellica:BAAALAAECgEIAQAAAA==.Jezebet:BAAALAADCgIIAgAAAA==.',Ji='Jiglebelly:BAAALAAECgEIAgABLAAECggIHQAEAJsjAA==.',Jo='Jonahheal:BAAALAADCggICAAAAA==.',Jz='Jz:BAAALAADCgYICwAAAA==.',Ka='Kaotic:BAAALAADCgYIBwAAAA==.Katarena:BAAALAAECgMIBwAAAA==.Kazule:BAAALAAECgEIAQAAAA==.Kazzaroth:BAAALAADCgUIBQAAAA==.',Ke='Keeller:BAAALAAECgMIAwAAAA==.',Kh='Khasket:BAAALAADCgcIDAAAAA==.',Ki='Kinký:BAAALAAECgUICAABLAAECgEIAQABAAAAAA==.',Ko='Kodekai:BAAALAADCggIDwAAAA==.Korvoh:BAAALAAECgIIAwAAAA==.',Kr='Krinchi:BAAALAAECgIIAwAAAA==.',Ku='Kumahu:BAAALAADCggIFQAAAA==.',Ky='Kyloris:BAAALAAECgIIAQAAAA==.',['Kä']='Kämik:BAAALAAECgIIAwAAAA==.',['Kø']='Kørrgøth:BAAALAADCgYICAAAAA==.',La='Lampion:BAAALAAECgUICgAAAA==.Lasstchance:BAAALAADCgcICQAAAA==.Latinamaddog:BAAALAAECgMIBAAAAA==.Lawolf:BAAALAADCgcIDQAAAA==.',Le='Lemuria:BAAALAADCgYIBQAAAA==.Leröth:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.',Li='Lilwagyu:BAAALAADCgYIBgAAAA==.Lilzai:BAAALAAECgMIBwAAAA==.Linds:BAAALAAECgIIAgAAAA==.',Lt='Ltdanslegs:BAAALAAECgEIAQAAAA==.',Lu='Luxu:BAAALAAECgIIAgAAAA==.',Ly='Lysandraa:BAAALAAECgIIAgAAAA==.',['Lä']='Lähär:BAAALAAECgUICAAAAA==.',Ma='Maged:BAAALAAECgMIBwAAAA==.Makimae:BAAALAADCgcIBwAAAA==.Maldrik:BAAALAAECgMIBwAAAA==.Manabun:BAAALAAECgIIAwAAAA==.Manbearcat:BAAALAAECgMIAwAAAA==.Maybebeef:BAAALAAECgYIBwAAAA==.',Me='Mebeatwife:BAAALAADCgYIBgAAAA==.Medkit:BAAALAADCggIDwAAAA==.Melancholic:BAAALAAECgEIAQAAAA==.Mera:BAAALAADCgEIAQAAAA==.Merisuda:BAAALAADCggICgAAAA==.Merle:BAAALAAECgYICgAAAA==.Metobo:BAAALAAECgIIAgAAAA==.',Mi='Mikethegray:BAAALAAECgIIAwAAAA==.Mistris:BAAALAADCgcICQAAAA==.',Mo='Momoku:BAAALAAECgIIAwAAAA==.Mookie:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Moolimbo:BAAALAAECgIIAwAAAA==.Mooseboy:BAAALAAECgMIBwAAAA==.Mootalstrike:BAAALAAECgUIBgAAAA==.Mord:BAAALAAECgYICgAAAA==.Mortyjr:BAAALAAECgEIAgAAAA==.Moshworm:BAAALAAECgMIBAAAAA==.',Mv='Mvp:BAAALAADCgQIBAAAAA==.',Na='Natsumi:BAAALAAECgMICAAAAA==.',Ne='Nehima:BAAALAAECgMIBwAAAA==.Nelaphim:BAAALAAECgUIBwAAAA==.Nessanië:BAAALAADCgEIAQAAAA==.',Ni='Nico:BAAALAAECgMIAwAAAA==.Nitro:BAAALAAECgYIDAAAAA==.',No='Noxxidari:BAAALAAECgYIDwAAAA==.Noxxus:BAAALAADCggIEQAAAA==.',Nu='Nushi:BAAALAADCgEIAQAAAA==.',Ny='Nymphis:BAAALAADCgMIAwAAAA==.',Ob='Oblivia:BAAALAADCgcIBwAAAA==.',Or='Orbs:BAAALAADCgQIBAAAAA==.Orchist:BAAALAAECgMIAwAAAA==.',Pa='Paynes:BAAALAADCgcIEAAAAA==.',Pe='Pepperona:BAAALAAECgYICAAAAA==.',Pi='Piketricfoot:BAAALAADCgcIBwAAAA==.Pitchblende:BAAALAAECgMIBwAAAA==.',Pl='Plumbis:BAAALAADCgcIEwAAAA==.',Po='Polymorph:BAAALAADCgYICAAAAA==.Portalheart:BAAALAAECgMIBAAAAA==.',Pr='Protagoras:BAAALAADCggIBgAAAA==.',Pu='Purejoy:BAAALAADCgcICAAAAA==.',Qi='Qillaris:BAAALAADCgcIBwAAAA==.Qillratha:BAAALAADCggICAAAAA==.',Qu='Questron:BAAALAADCgcIEQAAAA==.Quillz:BAAALAAECgMIAwAAAA==.',Qx='Qxxui:BAAALAADCggIDQAAAA==.',Ra='Raani:BAAALAADCgcIEQAAAA==.Raiffee:BAAALAADCgcICQAAAA==.Raszageth:BAAALAAECgYIBgAAAA==.Rathiclap:BAAALAAFFAIIAgAAAA==.',Re='Redine:BAAALAADCgIIAgAAAA==.Rendis:BAAALAADCgcIBwAAAA==.',Ri='Rinya:BAAALAAECgIIAgAAAA==.',Rm='Rmilberr:BAAALAADCgcIBwAAAA==.',Ro='Rosalynne:BAAALAAFFAIIAgAAAA==.',Ru='Ruukia:BAAALAAECgYICQAAAA==.',Ry='Ryddyk:BAAALAAECgYIDgAAAA==.',['Ré']='Réaperknight:BAAALAADCggIEwAAAA==.',Sa='Saelylria:BAAALAADCgEIAQAAAA==.Sandernel:BAAALAADCggIEAAAAA==.Sannish:BAABLAAECoEXAAIFAAcIGA5WJACCAQAFAAcIGA5WJACCAQAAAA==.Sapientia:BAAALAADCgUIBQAAAA==.Saragon:BAAALAADCggICAAAAA==.',Sc='Scar:BAAALAADCggICAAAAA==.',Sh='Shaeen:BAAALAAECgQIBwAAAA==.Sharksaw:BAAALAAECgYICAAAAA==.Sharroz:BAAALAAECgUIBgAAAA==.Shennu:BAAALAAECgEIAQAAAA==.Shxttyhshman:BAAALAAECgMIBgAAAA==.',Si='Sineth:BAAALAADCgcIDQAAAA==.',Sk='Skoftyia:BAAALAADCgIIAgABLAADCgYIBgABAAAAAA==.Skyhigh:BAAALAAECgMIBwAAAA==.Skyknight:BAAALAADCgcIEQAAAA==.',Sl='Slapadwarf:BAAALAAECgcICwAAAA==.',Sm='Smackitdòwn:BAAALAADCgQIBAAAAA==.',Sn='Snowin:BAAALAAECgEIAQAAAA==.',So='Solcon:BAAALAAECgIIAwAAAA==.',Sp='Spaazz:BAAALAADCggICgAAAA==.Spellsteal:BAAALAADCgcIDgAAAA==.',St='Stepsister:BAAALAADCgQIBAAAAA==.Stormtempest:BAAALAADCgMIAwAAAA==.Störmrender:BAAALAAECgMIBgAAAA==.',Sw='Swan:BAAALAAECgQIBAAAAA==.Swishswish:BAAALAAECgMIBgAAAA==.',Sy='Sybelybrook:BAAALAADCggIFQAAAA==.Syde:BAAALAAECgUIBwAAAA==.',Ta='Tabithaa:BAAALAAECgEIAQAAAA==.Taloriesh:BAAALAAECgIIAwAAAA==.Tanazir:BAAALAADCggIDwAAAA==.Tarivel:BAAALAADCgcIBwAAAA==.Tarondria:BAAALAAECgEIAQAAAA==.',Te='Techytechy:BAAALAAECgEIAQAAAA==.Teito:BAAALAAECgYICQAAAA==.Telkard:BAAALAADCgYIBgAAAA==.',Th='Theily:BAAALAADCggIDwAAAA==.Thewife:BAAALAAECgEIAQABLAAECgMIBQABAAAAAA==.Thora:BAAALAAECgEIAQAAAA==.Thundrtheigs:BAAALAAECgIIAgAAAA==.',Ti='Tigermaster:BAAALAAECgIIAgAAAA==.Tilamano:BAAALAAECgUIBwAAAA==.Tilthulhu:BAAALAADCggIBgABLAAECgUIBwABAAAAAA==.',To='Tohrnamental:BAAALAAECgUIBwAAAA==.Tonycheeks:BAAALAADCgYIBgAAAA==.Toomey:BAAALAADCgcICgAAAA==.Toopie:BAAALAADCggICAAAAA==.Torrthious:BAAALAADCggICAABLAAECggIDwABAAAAAA==.',Tr='Trenve:BAAALAAECgMIBAAAAA==.',Tu='Tuzzyfits:BAAALAAECgIIAgAAAA==.',['Té']='Téchymoon:BAAALAAFFAIIAgAAAA==.',Ug='Ugo:BAAALAAECgUICgAAAA==.',Um='Umbron:BAAALAAECgMIBAAAAA==.',Un='Ungrounded:BAAALAADCggIFQAAAA==.',Us='Useche:BAAALAAECgQIAwABLAAECgUICQABAAAAAA==.',Va='Valak:BAAALAADCgcIDQAAAA==.Valakyre:BAAALAADCgcIBwAAAA==.Valcristo:BAAALAAECgUIBwAAAA==.Valk:BAAALAADCgcIBwAAAA==.Valros:BAAALAADCggIDwAAAA==.Vanity:BAAALAADCgQIBAAAAA==.',Ve='Vegean:BAAALAADCgYIBwAAAA==.Velthana:BAAALAAECgIIBAAAAA==.Venous:BAAALAAECgUIBQAAAA==.Vest:BAAALAAECgIIAwAAAA==.',Vi='Vicariana:BAAALAAFFAIIAgAAAA==.Vidette:BAAALAADCgYIBgAAAA==.Viduus:BAAALAAECgMIBAAAAA==.Vieliessar:BAAALAADCgYICgAAAA==.',Vo='Vodmor:BAAALAAECgIIAgAAAA==.Voidlight:BAAALAADCgUIBQAAAA==.',Wa='Waffl:BAAALAAECgYIBgAAAA==.Warrendeath:BAAALAAFFAIIAgAAAA==.',We='Wetfingers:BAAALAADCggICAAAAA==.',Wh='Whoflungpoo:BAAALAAECgIIAgAAAA==.',Wi='Widerichard:BAAALAAECgIIAwAAAA==.Widowshifts:BAAALAADCggICAAAAA==.',Wo='Wogar:BAAALAADCgUIBgAAAA==.Wowbelly:BAABLAAECoEdAAIEAAgImyOGAQAZAwAEAAgImyOGAQAZAwAAAA==.',Xd='Xdream:BAAALAAECgEIAQABLAAECggIGAADAPEiAA==.',Xo='Xonk:BAAALAAFFAIIAgAAAA==.',Yu='Yuji:BAAALAAECgYICQAAAA==.',Za='Zach:BAAALAADCgMIAwAAAA==.Zanatos:BAAALAAECgIIAgAAAA==.',Ze='Zenreto:BAAALAAECgIIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end