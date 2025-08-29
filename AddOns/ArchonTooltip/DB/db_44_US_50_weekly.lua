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
 local lookup = {'Mage-Arcane','Unknown-Unknown','Priest-Shadow','Paladin-Protection','Warrior-Protection','Druid-Balance','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','DeathKnight-Frost','DemonHunter-Havoc',}; local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Achelis:BAAALAAECgMIBQAAAA==.',Ad='Adelonda:BAAALAADCgcIDwAAAA==.Adros:BAAALAAECgMIBQAAAA==.Adrrel:BAABLAAECoEWAAIBAAgIRxwJFwBZAgABAAgIRxwJFwBZAgAAAA==.',Ae='Aedrèl:BAAALAADCgYIBgABLAAECggIFgABAEccAA==.Aelon:BAAALAAECgIIAgAAAA==.Aevouros:BAAALAADCggIEAAAAA==.',Ag='Agammemnon:BAAALAADCgUIBQAAAA==.',Ak='Akarg:BAAALAAECggIBgAAAA==.Akariliselle:BAAALAAECgYICQAAAA==.Aknologia:BAAALAAECgEIAQAAAA==.',Al='Albita:BAAALAAECgMIBAAAAA==.Alexander:BAAALAAECgYICAAAAA==.Alpacalypse:BAAALAAECgEIAQAAAA==.Alyssandre:BAAALAAECgUICAAAAA==.Alzheimerz:BAAALAAECgYIBwAAAA==.',Am='Amaribo:BAAALAAECgYICQAAAA==.',An='Anaraleth:BAAALAADCggIFAAAAA==.Anaralyth:BAAALAADCgEIAQABLAADCggIFAACAAAAAA==.Andaya:BAAALAAECgYICQAAAA==.',Ar='Arandis:BAAALAAECgMIBQAAAA==.Arch:BAAALAAECgEIAQAAAA==.Arcianna:BAAALAAECgMIAwAAAA==.Arjurn:BAAALAAECgMIBQAAAA==.Armpitbutter:BAAALAAECgMIBQAAAA==.Artymiss:BAAALAADCgYIBgAAAA==.',As='Ashireita:BAAALAAECgMIBAAAAA==.Ashtarion:BAAALAAECgMIBAAAAA==.',At='Atos:BAAALAAECgMIBgAAAA==.Atrayupryde:BAAALAADCggICAAAAA==.',Au='Aurturious:BAAALAADCggIDwAAAA==.',Av='Avelina:BAAALAAECgEIAQAAAA==.Aviendhà:BAAALAADCggICAAAAA==.Avocat:BAAALAADCggIDAAAAA==.',Az='Azeria:BAAALAAFFAIIAgAAAA==.',Ba='Baekr:BAAALAADCgYIBgAAAA==.Balgar:BAAALAAECgMIBAAAAA==.Balgrys:BAAALAAECgYICAAAAA==.Bartholomeus:BAAALAADCggIDQAAAA==.Baumstrum:BAAALAAECgMIBAAAAA==.',Be='Bekiddo:BAAALAAECgMIAwAAAA==.Bernadea:BAAALAADCggIDQAAAA==.',Bl='Blitzed:BAAALAAECgIIAgAAAA==.Bloodrayvn:BAAALAAECgEIAQAAAA==.',Bo='Boomchick:BAAALAADCgUIBQAAAA==.Bosta:BAAALAADCgYICQAAAA==.',Br='Brenri:BAAALAADCggIDQAAAA==.Brew:BAAALAADCgMIAwAAAA==.',Bu='Bubbleoseven:BAAALAAECgMIBQAAAA==.Burgaroth:BAAALAAECgIIBQAAAA==.Buuron:BAAALAADCgUIBQAAAA==.',Ca='Caneste:BAABLAAECoEWAAIDAAgIcCKZCADDAgADAAgIcCKZCADDAgAAAA==.',Ce='Celestyl:BAAALAAECgEIAQAAAA==.Cerwynnea:BAAALAADCgQIBAAAAA==.',Ch='Chamaëleon:BAAALAAECgMIBQAAAA==.Cheapbeer:BAAALAAECgQIBgAAAA==.Cherry:BAAALAADCggIDAAAAA==.Chiforged:BAAALAADCggIDwAAAA==.Chill:BAAALAADCgIIAgAAAA==.Chromstrasza:BAAALAAECgIIAgAAAA==.',Cl='Claric:BAAALAADCggICAAAAA==.',Co='Comitus:BAAALAAECgMIBgAAAA==.Conjarr:BAAALAAECgYIDQAAAA==.Cougarsixsix:BAAALAADCgcIDgAAAA==.',Cr='Crazydrake:BAAALAADCgUIBQAAAA==.Crimos:BAAALAAECgIIBAAAAA==.Cryptyx:BAAALAADCgYICQAAAA==.',Da='Daerthor:BAAALAAECgMIBAAAAA==.Dakaru:BAAALAADCgIIAgABLAADCgIIAgACAAAAAA==.Dalind:BAAALAADCggIDwAAAA==.Damaclies:BAAALAAECgcIDgAAAA==.Darthbane:BAAALAADCgcICgAAAA==.Darthstroyer:BAAALAAECgYICgAAAA==.Dasta:BAAALAADCgcIBwAAAA==.',De='Demonpixy:BAAALAADCggIDwAAAA==.',Di='Diabal:BAAALAADCgcIDQAAAA==.Diend:BAAALAAECgMIBgAAAA==.Discord:BAAALAADCgcIBwABLAAECgMIAwACAAAAAA==.Distiffany:BAAALAAECgQIBAAAAA==.',Dj='Djthedruid:BAAALAADCgcIBwABLAAECgEIAQACAAAAAA==.Djthelock:BAAALAAECgEIAQAAAA==.',Do='Dovuh:BAAALAADCgcICgAAAA==.',Dr='Dravenpryde:BAAALAAECgEIAQAAAA==.Draziu:BAAALAADCgIIAgAAAA==.Druen:BAAALAAECgMIAwAAAA==.Drunkenpo:BAAALAAECgMIBgAAAA==.Drïzl:BAAALAAECgYIDQAAAA==.',Du='Duckchow:BAAALAADCgYIBgAAAA==.',Dw='Dwarfoo:BAAALAADCggIDwAAAA==.Dweñde:BAAALAAECgMIAwAAAA==.',Ed='Eddrick:BAAALAAECgEIAQAAAA==.Edoran:BAAALAAECgYICwAAAA==.Edoren:BAAALAAECgQIBQAAAA==.',Ei='Eilethen:BAAALAAECgUICAAAAA==.',El='Elweyrin:BAAALAADCggIDwAAAA==.Elzbeth:BAAALAADCgQIBAAAAA==.',En='Engo:BAAALAAECgYICAAAAA==.',Er='Eradrá:BAAALAAECgIIAgAAAA==.Eragon:BAAALAADCgEIAQAAAA==.Erinaenna:BAAALAADCgIIAgAAAA==.',Eu='Eureka:BAAALAADCggICAAAAA==.',Ev='Evaiñe:BAAALAADCgcIFQAAAA==.Evandra:BAAALAAECgMIBAAAAA==.Evanorah:BAAALAAECgMIAwAAAA==.',Ez='Ezarke:BAAALAADCggIEwAAAA==.',Fa='Facelessman:BAAALAAECgMIAwAAAA==.Faedeyeda:BAAALAADCggIDAAAAA==.Farqtoo:BAAALAAECgMIBgAAAA==.Fatalerrorr:BAAALAAECgIIAgAAAA==.',Fe='Ferhold:BAAALAADCgcICQAAAA==.Ferrovax:BAAALAADCgcIBwABLAAECgIIAgACAAAAAA==.',Fo='Forkwrath:BAAALAADCgYIBgABLAAECggIFgADAHAiAA==.',Fr='Frojio:BAAALAAECgMIAwAAAA==.Frosten:BAAALAADCgcICwAAAA==.',Fu='Fuegonuggz:BAAALAAECgQICgABLAAECgIIAgACAAAAAA==.',Fy='Fyyre:BAAALAADCgYIBgAAAA==.',Ga='Gaeralf:BAAALAADCgYIBgAAAA==.Gaff:BAAALAAECgEIAQAAAA==.Galedari:BAAALAAECgMIAwAAAA==.Gariland:BAAALAAECgMIAwAAAA==.',Gh='Ghostie:BAAALAADCgcIDQABLAAECgMIBQACAAAAAA==.',Gr='Greenbeen:BAAALAADCgQIBwAAAA==.Grido:BAAALAADCgQICAAAAA==.Grimbrindral:BAABLAAECoEWAAIEAAgIuhbJCQDYAQAEAAgIuhbJCQDYAQAAAA==.Grubbluster:BAAALAAECgEIAgAAAA==.Gruzaxx:BAAALAADCgcIDgAAAA==.',Gu='Guilhermebr:BAAALAADCgUIBQAAAA==.',Ha='Hadin:BAAALAAECgMIBQAAAA==.Haozhao:BAAALAAECgMIBgAAAA==.Harsaiah:BAAALAAECgEIAQAAAA==.Hatchet:BAAALAADCgcICAAAAA==.',He='Healspammer:BAAALAADCggICAAAAA==.Heckboy:BAAALAAECgEIAQAAAA==.Hephaistian:BAAALAADCggIFgAAAA==.Heretictus:BAAALAADCgcIDAAAAA==.Hespera:BAAALAAECgYICQAAAA==.',Hi='Hirnatou:BAAALAAECgYIDwAAAA==.',Ho='Horsebananas:BAAALAAECgYICgAAAA==.Hosferatu:BAAALAADCgYIBgAAAA==.',Hu='Hulud:BAAALAAECgMIBgAAAA==.',Hy='Hydrangea:BAAALAADCggIDwAAAA==.Hysgar:BAAALAAECgcIEAAAAA==.Hysteria:BAAALAAECgEIAQAAAA==.',Ic='Icetiger:BAAALAADCggIDwAAAA==.',Il='Illidaz:BAAALAAECgEIAgAAAA==.Illiduke:BAAALAADCgYIBgABLAAFFAIIAgACAAAAAA==.Ilthunran:BAAALAADCgcIDgAAAA==.',Im='Immortál:BAAALAAECgMIBQAAAA==.Implication:BAAALAADCggIDwAAAA==.',In='Inc:BAAALAADCggIFgAAAA==.Infinìte:BAAALAAECgMIAwAAAA==.',Ja='Jamjars:BAAALAADCggIDgAAAA==.Jaybaz:BAAALAADCgcIDgAAAA==.',Je='Jemythra:BAAALAADCgUIBQAAAA==.',Ji='Jindrac:BAAALAADCgYIBgAAAA==.Jindwakuna:BAAALAAECgMIAwAAAA==.',Ka='Kalarae:BAAALAAECgMIAwAAAA==.Kaltharion:BAAALAAECgYIDAAAAA==.Kantong:BAAALAAECgQIBwAAAA==.Karabar:BAAALAAECgMIBQAAAA==.Kars:BAAALAADCgIIAgAAAA==.',Ke='Kelli:BAAALAADCgcIBwAAAA==.',Kh='Khadi:BAAALAAECgIIAwAAAA==.Khamaracy:BAAALAADCggIDwAAAA==.Khrooze:BAAALAADCgYIBgABLAAECgYICgACAAAAAA==.',Ki='Kiljana:BAAALAADCggIDQAAAA==.',Ku='Kurick:BAAALAADCggIFQAAAA==.',La='Latte:BAAALAAECgIIAgAAAA==.',Le='Lenity:BAAALAAECgIIBQAAAA==.Letty:BAAALAAECgMIAwAAAA==.',Li='Lightlink:BAAALAAECgQIBQAAAA==.Lildragon:BAAALAADCgQIBQAAAA==.Lilstrasza:BAAALAADCgcIBwAAAA==.Limu:BAAALAADCgYIBgAAAA==.',Lo='Lokinah:BAAALAADCggICgAAAA==.',Lu='Lucoryphus:BAAALAAECgMIAwAAAA==.Lukeduke:BAABLAAECoEYAAIFAAgIhyDHAwDLAgAFAAgIhyDHAwDLAgABLAAFFAIIAgACAAAAAA==.',Ly='Lydia:BAAALAAECgYICQAAAA==.',['Lô']='Lôckrocks:BAAALAAECgEIAQAAAA==.',['Lý']='Lýsendra:BAAALAADCgQIBAAAAA==.',Ma='Malifel:BAAALAAECgMIAwAAAA==.Mandarin:BAAALAAECgEIAQAAAA==.',Me='Mercia:BAAALAAECgMIAwAAAA==.Merekoma:BAAALAAECgIIAgAAAA==.Metalfutbol:BAAALAADCgMIAwAAAA==.',Mi='Milarra:BAAALAADCggIDwAAAA==.Milker:BAABLAAECoEVAAMGAAgIACF3BAAMAwAGAAgIACF3BAAMAwAHAAQIxRJJNgDQAAAAAA==.Minalan:BAAALAAECgYICgAAAA==.Mingonashoba:BAAALAAECgEIAQAAAA==.Misschris:BAAALAAECgMIBAAAAA==.Mizu:BAAALAADCggIDwAAAA==.',Mt='Mtdewmon:BAAALAADCgMIAwAAAA==.',Mu='Muttskî:BAAALAADCgMIBAAAAA==.',My='Myrrh:BAAALAAECgEIAQAAAA==.Mysklef:BAAALAADCgYIBgAAAA==.Mystaria:BAAALAADCgMIAwAAAA==.Mythris:BAAALAADCgcIBwAAAA==.Mythìx:BAAALAAECgMIBgAAAA==.',Na='Nakia:BAAALAAECgMIBAAAAA==.Natah:BAAALAADCgcIBwABLAAECgYIBwACAAAAAA==.',Ne='Nekro:BAAALAAECgEIAQAAAA==.Nelandra:BAAALAADCgcIDgAAAA==.Neongrasp:BAAALAAECgcIEwAAAA==.',Ni='Nickatnight:BAAALAAECgMIAwAAAA==.Nickbreed:BAAALAADCggICAAAAA==.Nilrem:BAAALAADCgcIEwAAAA==.',No='Nofríends:BAAALAADCggICAAAAA==.Nomahuata:BAAALAAECgYIDAAAAA==.Nordre:BAAALAAECgYICgAAAA==.Notaninja:BAAALAADCgYIBgAAAA==.',Ny='Nyeli:BAAALAADCggIDwAAAA==.Nylaera:BAAALAADCggICAAAAA==.Nyxi:BAAALAAECgIIAgAAAA==.',['Né']='Néo:BAAALAADCggIFwAAAA==.',On='Onefiftyone:BAAALAAECgMIBgAAAA==.Onlybeans:BAAALAAECgEIAQAAAA==.Onyxx:BAAALAADCggIFwAAAA==.',Pa='Paranitis:BAAALAADCggIFAAAAA==.Paraparaboom:BAAALAAECggIDgAAAA==.',Pl='Plunka:BAAALAAECgMIBQAAAA==.',Po='Potshot:BAAALAAECgcIEgAAAA==.',Pu='Punchline:BAAALAAECgIIAgABLAAECgMIAwACAAAAAA==.',Ra='Ragingdh:BAAALAAECgcIEAAAAA==.Raivel:BAAALAADCgYIBgAAAA==.Rakhak:BAAALAAECgEIAgAAAA==.Randalthor:BAAALAADCgcIDgAAAA==.Raneyth:BAAALAADCgcIFQAAAA==.Ravagèr:BAAALAAECgQIBAAAAA==.',Re='Redemus:BAAALAADCgYIBgAAAA==.Redwinetoast:BAAALAAECgMIBAAAAA==.Reeva:BAAALAADCgcIBwABLAADCggIDAACAAAAAA==.Reposess:BAAALAADCgIIAgAAAA==.Reshyk:BAAALAAECgMIBAAAAA==.',Rh='Rhobes:BAAALAADCgcIBwAAAA==.',Ri='Rictus:BAAALAAECgYICAAAAA==.Rikuto:BAAALAADCggIDwAAAA==.Rivermire:BAAALAADCgMIAwAAAA==.Rix:BAAALAAECgMIBAABLAAECgMIBAACAAAAAA==.Rizheng:BAAALAAECgMIAwAAAA==.',Ro='Roanza:BAAALAADCggIEAAAAA==.Rohgar:BAAALAADCgYIBgABLAAECgYICgACAAAAAA==.',Ru='Rumor:BAAALAADCggICwAAAA==.Rurry:BAABLAAECoEaAAMIAAgIDCSJAAA/AwAIAAgIDCSJAAA/AwAJAAEIzAv/MwA/AAAAAA==.',Ry='Ryuki:BAAALAAECgcIDgAAAA==.',Sa='Salocar:BAAALAADCggICAAAAA==.Sand:BAAALAAECgMIBgAAAA==.Sauceypanda:BAAALAADCgYIBgAAAA==.Savior:BAAALAADCgUIBQAAAA==.Savonah:BAAALAADCggIDAAAAA==.',Sc='Scalespawn:BAAALAADCgQIBAABLAAECggIFwAKADEiAA==.Scaryl:BAAALAADCggIFwAAAA==.Scourgespawn:BAABLAAECoEXAAIKAAgIMSKJBgAKAwAKAAgIMSKJBgAKAwAAAA==.',Se='Seikyo:BAAALAAECgMIBQAAAA==.Sephuz:BAAALAADCgQIBAAAAA==.Serbiscuit:BAAALAAECgMIAwAAAA==.Serenval:BAAALAAECgcIDQAAAA==.Seyrah:BAAALAADCgMIAwABLAADCgQIBAACAAAAAA==.',Sh='Shadewarden:BAAALAADCgcICwAAAA==.Shadyaf:BAAALAAECgMIBAAAAA==.Shalis:BAAALAAECgMIBAAAAA==.Sharallaron:BAAALAAECgQIBwAAAA==.Sharko:BAAALAAECgIIAgAAAA==.Sharvalee:BAAALAAECgMIBAAAAA==.Shibui:BAAALAAECgMIBgAAAA==.Shönuff:BAAALAAECgEIAQAAAA==.',Si='Simbagrovex:BAAALAAECgEIAgAAAA==.',Sk='Skoduh:BAAALAAECgEIAQAAAA==.',Sl='Slaanesh:BAAALAAECgQIBAAAAA==.Sluggo:BAAALAAFFAIIBAAAAA==.',So='Solfist:BAAALAAECgMIAwAAAA==.Soraka:BAAALAADCgcIDgAAAA==.',Sp='Spiralmist:BAAALAAECgUIBgAAAA==.Spiritföx:BAAALAADCgIIAgAAAA==.Spiritzugzug:BAAALAADCgQIBAAAAA==.',St='Stonedalways:BAAALAAECgIIAgAAAA==.',Su='Surrak:BAAALAADCgcIDgAAAA==.Sus:BAABLAAECoEVAAILAAgINRjyFgBIAgALAAgINRjyFgBIAgAAAA==.',Sv='Sveta:BAAALAADCggICgABLAAECgcIDgACAAAAAA==.',Sy='Sylvíadne:BAAALAADCggIDgAAAA==.',['Sá']='Sábel:BAAALAADCgYIBgABLAAECgMIAwACAAAAAA==.',Ta='Tachima:BAAALAADCgEIAQABLAAECgcIDgACAAAAAA==.Tarathor:BAAALAADCggIDwAAAA==.',Te='Tea:BAAALAAECgMIBgAAAA==.Teknofarious:BAAALAADCgYICAAAAA==.Teá:BAAALAADCgYIBgABLAADCggICwACAAAAAA==.',Th='Thallizarr:BAAALAADCgUICAAAAA==.Thialia:BAAALAAECgMIBQAAAA==.Thranduil:BAAALAADCgMIAwAAAA==.',Ti='Tinkabella:BAAALAAECgMIBQAAAA==.Tizl:BAAALAAECgMIBQAAAA==.',To='Tobiblindpaw:BAAALAAECgIIAgAAAA==.Tombstone:BAAALAAECgMIBAAAAA==.Topgap:BAAALAADCgcICAABLAAECggIGgAIAAwkAA==.Toronus:BAAALAADCggIQgAAAA==.',Tr='Treechow:BAAALAADCgYIBgAAAA==.Trix:BAAALAAECgMIBQAAAA==.',Tu='Tullrine:BAAALAAECgMIAwAAAA==.Tulsi:BAAALAAECgMIBgAAAA==.',Um='Umm:BAAALAADCgYIBgAAAA==.',Va='Vas:BAAALAADCgYIFQAAAA==.',Ve='Veklanxx:BAAALAADCggICgAAAA==.Vend:BAAALAAECgEIAQAAAA==.Vere:BAAALAADCgcIBwAAAA==.Vethir:BAAALAADCggIDwAAAA==.Vevicenth:BAAALAADCggICAABLAAECgMIAwACAAAAAA==.',Vi='Victorynuggz:BAAALAAECgIIAgAAAA==.Vizzax:BAAALAAECgIIAgAAAA==.',Wa='Warenio:BAAALAADCgYIBgAAAA==.Warpsbulge:BAAALAADCggIDQABLAAECggIFQAGAAAhAA==.',Wh='Whakan:BAAALAADCggIEQABLAAECgMIAwACAAAAAA==.',Wi='Williamgoat:BAAALAADCggICAABLAAECgYIBwACAAAAAA==.',Wu='Wuukong:BAAALAAECgEIAQAAAA==.',Xa='Xakeko:BAAALAADCggIDwAAAA==.Xalatos:BAAALAADCgcICQAAAA==.Xaleria:BAAALAADCgcIBwAAAA==.Xalfein:BAAALAADCgYICQAAAA==.',Xe='Xería:BAAALAADCggIDgAAAA==.',Xi='Xiaolang:BAAALAADCgUIBQAAAA==.',Ya='Yanakana:BAAALAADCgcIFQAAAA==.',Yv='Yveltal:BAAALAAECgUICAAAAA==.',Za='Zatriani:BAAALAADCgcIDQAAAA==.',Ze='Zednotzee:BAAALAADCgYIBgAAAA==.',Zi='Zidaya:BAAALAADCgUIBQABLAADCggIDAACAAAAAA==.Zinu:BAAALAAECgMIBgAAAA==.',Zu='Zulfionn:BAAALAAECgEIAQAAAA==.',Zy='Zylae:BAAALAAECgEIAQAAAA==.Zylah:BAAALAADCgcIDQAAAA==.',['Áy']='Áyrá:BAAALAAECgMIBAAAAA==.',['Âk']='Âkula:BAAALAADCgcIBwAAAA==.',['Åp']='Åpollyon:BAAALAAECgIIAgAAAA==.',['Øu']='Øuroboros:BAAALAADCgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end