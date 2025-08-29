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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Paladin-Holy',}; local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=44,date='2025-08-29',data={Ab='Absylus:BAAALAAECgIIAgAAAA==.Abuse:BAAALAAECgYICwAAAA==.',Ac='Accoli:BAAALAAECgYICAAAAA==.Actionman:BAAALAAECggICAAAAA==.',Ak='Akéno:BAAALAADCggIDQAAAA==.',Al='Alfrank:BAAALAADCgMIAwAAAA==.',An='Andreanne:BAAALAADCgIIAgAAAA==.',Ar='Ariaddne:BAAALAAECgYICgAAAA==.Arthur:BAAALAADCgEIAQAAAA==.',Au='Augonly:BAAALAAECgcIEAAAAA==.',Az='Azalea:BAAALAAECggIHwAAAQ==.Azazèl:BAAALAADCggICAAAAA==.',Ba='Barryberry:BAAALAADCggICwAAAA==.',Bb='Bbldrizzy:BAAALAAECgYICAAAAA==.',Be='Bearlybaked:BAAALAAECgEIAQAAAA==.Beastlieduke:BAAALAADCggIEAAAAA==.Beastlierduk:BAAALAAECgEIAQAAAA==.Bellaruhbz:BAAALAAECgUIBQAAAA==.Bellybutton:BAAALAAECgEIAQAAAA==.',Bi='Bigfletch:BAAALAADCgcICgAAAA==.Bigtac:BAAALAAECgMIBQAAAA==.Binggus:BAAALAAECgYIBwAAAA==.',Bl='Blabbybootze:BAAALAAECgMIAwAAAA==.Bladelight:BAAALAADCgEIAQAAAA==.Blaisefenely:BAAALAADCgcIDQAAAA==.Blighte:BAAALAAECgYIEAAAAA==.Blondiepeblz:BAAALAAECgEIAgAAAA==.Bloodluna:BAAALAADCgEIAQAAAA==.',Bo='Bofine:BAAALAAECgIIAgAAAA==.',Br='Braicelina:BAAALAADCgQIBwAAAA==.Brubru:BAAALAADCgYIBgAAAA==.',Bu='Bubbatron:BAAALAAECgIIAgAAAA==.Bubblebuns:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Bubbáa:BAAALAADCgYIBgAAAA==.',Ca='Caani:BAAALAADCgQIBAAAAA==.Captnmeow:BAAALAAECgEIAgAAAA==.Capuccina:BAAALAADCgMIBAAAAA==.Carareith:BAAALAADCgMIAwAAAA==.Cares:BAAALAADCgcIBwAAAA==.',Ci='Cinderfalls:BAAALAAECgIIAgAAAA==.',Co='Coa:BAAALAADCgcIBwAAAA==.Colveraar:BAAALAADCgcIBwAAAA==.Corita:BAAALAAECgIIAgAAAA==.',Cu='Curseword:BAAALAAECgIIAgAAAA==.',Cw='Cwilson:BAAALAAECggIBgAAAA==.',Da='Dadune:BAAALAADCggIDgABLAADCggIEAABAAAAAA==.Dariaa:BAAALAADCggIDgAAAA==.Darkcrusader:BAAALAADCgIIAgAAAA==.Darkmoo:BAAALAAECgEIAQAAAA==.Darkrage:BAAALAADCgYIBgAAAA==.Darkyiff:BAAALAADCgUIBgAAAA==.Darthownage:BAAALAADCgQIBAAAAA==.',De='Deadaf:BAAALAAECgIIAgAAAA==.Deadergriff:BAAALAADCgcIDAAAAA==.Deadhippyxix:BAAALAADCgUICAAAAA==.Deadicated:BAAALAAECgEIAwAAAA==.Deathmark:BAAALAAECgYIDgAAAA==.Deathproof:BAAALAAECgIIAgAAAA==.Denallia:BAAALAADCggIDwAAAA==.Desunaito:BAAALAAFFAEIAQAAAA==.Deviious:BAAALAAECgYICAAAAA==.',Do='Doresh:BAAALAADCggICQAAAA==.Dorki:BAAALAAECggICAAAAA==.',Dr='Dracnogard:BAAALAADCggIEwAAAA==.Dracowulf:BAAALAAECgMIBQAAAA==.Dragonx:BAAALAAECgMIBQAAAA==.Drakowolf:BAAALAAECgIIAgAAAA==.Drewceratops:BAAALAAECgcIEAAAAA==.Drimchi:BAAALAAECgYICwAAAA==.Dromkyr:BAAALAAECgIIAgAAAA==.Drossiechan:BAAALAADCgYIBgAAAA==.',Du='Duellipa:BAAALAAECgMIBgAAAA==.Dundi:BAAALAADCgQIBAABLAAECgUIBwABAAAAAA==.Duroganosh:BAAALAADCgcICQAAAA==.',Dy='Dyandis:BAAALAADCgYIBgAAAA==.',['Dæ']='Dæmonique:BAAALAAECgQIBwAAAA==.',Ea='Eaturbrainz:BAAALAADCgUIBgAAAA==.',Eb='Ebijonalord:BAAALAADCggIFgAAAA==.',Ed='Edgin:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',El='Elayssaen:BAAALAADCgQIBAAAAA==.Elegia:BAAALAAECgUIBgAAAA==.Ellesande:BAAALAADCgYIDQAAAA==.Elunie:BAAALAADCggICAAAAA==.Elvenviper:BAAALAAECgIIAwAAAA==.Elvenwow:BAAALAADCgYICQABLAAECgIIAwABAAAAAA==.',Em='Emadiropilo:BAAALAADCgQIBAAAAA==.',En='Endless:BAAALAADCgUIBQAAAA==.Enlighten:BAAALAADCggIDQAAAA==.',Er='Erismorn:BAABLAAECoEWAAICAAgI/CQJBABCAwACAAgI/CQJBABCAwAAAA==.',Eu='Eugalien:BAAALAADCgQIBAAAAA==.Eugallen:BAAALAADCggIDwAAAA==.',Fa='Faezaria:BAAALAAECgEIAQAAAA==.Fallen:BAABLAAECoEUAAMDAAgIVxgjFABhAgADAAgIVxgjFABhAgAEAAYIkAu+FQBUAQAAAA==.Fathermoo:BAAALAADCgEIAQAAAA==.',Fe='Felt:BAAALAADCgMIAwABLAAECgIIAQABAAAAAA==.Ferozz:BAAALAADCgQIBAAAAA==.',Fi='Finatar:BAAALAAECgMIBgAAAA==.',Fl='Flexatronic:BAAALAAECgMIBgAAAA==.',Fr='Frankdatank:BAAALAADCgQIBAAAAA==.Frankzzorz:BAAALAAECgMIBgAAAA==.Fremder:BAAALAAECgUIBgAAAA==.Froggy:BAAALAADCggIEwAAAA==.',Fu='Funeral:BAACLAAFFIEGAAIFAAQIkBmdAQCAAQAFAAQIkBmdAQCAAQAsAAQKgRcAAwUACAgDJRsCAE8DAAUACAgDJRsCAE8DAAYABghHGGoHAOQBAAAA.',Fy='Fyjhrt:BAAALAAECgMIBgAAAA==.',Ga='Galdiir:BAAALAADCggICAAAAA==.Gazzthi:BAAALAADCgcIDgAAAA==.',Gd='Gdkman:BAAALAADCgYICgAAAA==.Gdkmonk:BAAALAADCggIBwAAAA==.',Gi='Gimmedatmouf:BAAALAAECgYICQAAAA==.Gimmedatneck:BAAALAAECgQIBwAAAA==.Ginga:BAAALAADCgEIAQAAAA==.Giratina:BAAALAAECgMIBAAAAA==.',Gl='Gloryhollow:BAAALAAECgIIAgAAAA==.',Go='Goatsunemiku:BAAALAADCgMIAwABLAADCgcIBwABAAAAAA==.Gooseandmav:BAAALAAECgQIAgAAAA==.Goreflinger:BAAALAADCgEIAQAAAA==.',Gr='Grandmoo:BAAALAAECgEIAgAAAA==.Grastim:BAAALAADCggIEAAAAA==.',Gw='Gwenindoubt:BAAALAAECgYICgAAAA==.Gwima:BAAALAADCggICAAAAA==.',Ha='Haraldsson:BAAALAAECgYICQAAAA==.Hasaro:BAAALAAECgcIDQAAAA==.Havokvacano:BAAALAAECgMIAwAAAA==.',He='Hellbrringer:BAAALAAECgYIDAAAAA==.',Hi='Highwarlord:BAAALAAECgEIAQAAAA==.',Ho='Hoj:BAABLAAECoEVAAIHAAgI2iYDAACeAwAHAAgI2iYDAACeAwAAAA==.Hotbheals:BAAALAADCgcIBwAAAA==.',Hu='Humanform:BAAALAADCggICAAAAA==.',Ik='Ikemetic:BAAALAADCgYIBgAAAA==.',In='Inflames:BAAALAADCgYICAAAAA==.',It='Itssofluffy:BAAALAAECgIIAgAAAA==.',Ja='Jacee:BAAALAADCgcIBwAAAA==.Jahumcsha:BAAALAADCgQIBgAAAA==.',Ji='Jinxxd:BAAALAAECgIIAgAAAA==.',Jo='Jojoflex:BAAALAADCgYICQABLAAECgUIBwABAAAAAA==.Jonsweetfox:BAAALAADCgYIBgAAAA==.Jorgedaddy:BAAALAAECgUIBwAAAA==.Jorgemonk:BAAALAAECgEIAQAAAA==.',Ka='Kaitokit:BAAALAADCgcIBwAAAA==.Kakadoody:BAAALAADCgcICQAAAA==.Kathriena:BAAALAADCggICAAAAA==.Kayllina:BAAALAADCggIEAAAAA==.Kayotic:BAAALAADCggIDQAAAA==.',Ke='Kelethei:BAAALAAECgIIAwAAAA==.Kelmorphic:BAAALAAECgIIAgAAAA==.',Kh='Khalua:BAAALAADCgcIBwAAAA==.',Ki='Kikiana:BAAALAAECgMIBAAAAA==.Kimolina:BAAALAADCggIFgAAAA==.',Ko='Kodera:BAAALAADCgYIBgAAAA==.',Kr='Kramerica:BAAALAADCggIDgAAAA==.',La='Lackluster:BAAALAAECgcIDQAAAA==.',Li='Lightshields:BAAALAADCgIIAgAAAA==.Lilbits:BAAALAADCggICAAAAA==.Lilithamy:BAAALAADCgYICQAAAA==.Lillivale:BAAALAADCgYICwABLAADCgYIDQABAAAAAA==.Lilsofa:BAAALAADCgcIBwAAAA==.Linissa:BAAALAADCggICwAAAA==.Littledude:BAAALAADCgcIBwAAAA==.',Lo='Locknloaded:BAAALAADCggICgAAAA==.',Lu='Lucían:BAAALAADCgIIAwABLAADCgYIDAABAAAAAA==.Luncennick:BAAALAADCgUIBQAAAA==.',Ly='Lykaios:BAAALAADCgQIBQAAAA==.',Ma='Makio:BAAALAADCggICAAAAA==.Manard:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Mangomiike:BAAALAADCgQIBQAAAA==.Margalgan:BAAALAADCgMIBQAAAA==.Marvalildra:BAAALAADCgEIAQAAAA==.Maylinfenora:BAAALAADCgcIBwAAAA==.',Me='Metalhedface:BAAALAAECgcIEQAAAA==.',Mi='Miakalifa:BAAALAAECgMIBQAAAA==.Mikecoxwall:BAAALAAECgYIDAAAAA==.Mikuchan:BAAALAADCggICgAAAA==.Mirazha:BAAALAAECgYIDgAAAA==.Mirikh:BAAALAAECgIIAgAAAA==.Mistytits:BAAALAADCgQIBAABLAADCggICAABAAAAAA==.Miyukix:BAAALAAECgIIAwAAAA==.',Mo='Monkeli:BAAALAAECgIIAwAAAA==.Monsterblur:BAAALAAECgUIBwAAAA==.Moonrecluse:BAAALAAECgYICgAAAA==.Morbidon:BAAALAAECgYICwAAAA==.Mortakii:BAAALAADCgYIBgAAAA==.Motgus:BAAALAADCgcIBwAAAA==.',My='Myamoamo:BAAALAADCggIEgAAAA==.',Na='Nanoxenixz:BAAALAAECgIIAwAAAA==.Nattiel:BAAALAADCgcICQAAAA==.',Ne='Nebucana:BAAALAADCgEIAQAAAA==.Nellaa:BAAALAADCgQIBQAAAA==.Neru:BAAALAADCgcIBwAAAA==.Nesuko:BAAALAADCgcICQAAAA==.Nevarc:BAAALAADCgcIFwAAAA==.',Ni='Nighwing:BAAALAADCgMIAwAAAA==.Nipgripple:BAAALAAECgMIAwAAAA==.',No='Notsoul:BAAALAADCgcICwAAAA==.',Nu='Nufal:BAAALAADCgcICwAAAA==.Nuseka:BAAALAAECgIIBAAAAA==.',Ny='Nyst:BAAALAADCgEIAQAAAA==.',Ob='Oborax:BAEALAAECgMIBgAAAA==.',Ok='Okoru:BAAALAADCgUIBwAAAA==.',Ol='Oliskyes:BAAALAADCggIDgAAAA==.Oliviabenson:BAAALAAECgYIBgAAAA==.Oluun:BAAALAADCgMIAwAAAA==.',Oo='Oof:BAAALAADCggICQAAAA==.',Or='Ordis:BAAALAADCgQIBAAAAA==.',Ow='Owlkapwn:BAAALAADCgMIBAAAAA==.',Pa='Palalalalala:BAAALAADCgEIAQAAAA==.Paradoxsoul:BAAALAAECgIIAgAAAA==.Paulius:BAAALAADCgEIAQAAAA==.',Pe='Pemdas:BAAALAAECggIDQAAAA==.',Pi='Pitto:BAAALAADCgcICAAAAA==.',Po='Polani:BAAALAAECgEIAQAAAA==.Pomonk:BAAALAAECgUIBQAAAA==.Poupouchasse:BAAALAAECgEIAQAAAA==.',Pp='Ppc:BAAALAAECgEIAQABLAAECggIFQAHANomAA==.',Pr='Procyonx:BAAALAADCgcIBwAAAA==.Prynnfire:BAAALAADCgcIDwAAAA==.',Pv='Pvc:BAAALAAECgYICQABLAAECggIFQAHANomAA==.',Py='Pyronna:BAAALAADCgEIAQAAAA==.',Ra='Raenisaria:BAAALAADCgMIAwAAAA==.Raevelina:BAAALAADCggIFgAAAA==.Rafik:BAAALAADCgQIBAAAAA==.Rakunan:BAAALAADCggIDQAAAA==.Rancord:BAAALAADCggIBgAAAA==.Ravensblood:BAAALAAECgMIBAAAAA==.',Re='Redria:BAAALAADCgIIAgAAAA==.Reexxarroni:BAAALAAECgMIBgAAAA==.Regarde:BAAALAAECgMIAwAAAA==.Renoitukax:BAAALAAECgIIAgAAAA==.',Ro='Rochana:BAAALAADCggICAAAAA==.Rogueaio:BAAALAADCgcIBwAAAA==.',Ry='Ryzen:BAAALAAECgYIDwAAAA==.',Sa='Sarnka:BAAALAADCgYICQAAAA==.',Sc='Schmuckateli:BAAALAAECggIBQAAAA==.Scruffiesdh:BAAALAADCgEIAQAAAA==.Scruffz:BAAALAADCggICAAAAA==.',Se='Seabull:BAAALAAECgMIAwAAAA==.Sean:BAAALAADCggIDAAAAA==.Seanm:BAAALAADCgYIBwAAAA==.Sendakonx:BAAALAADCgYIBgAAAA==.Serys:BAAALAADCgcIBwAAAA==.',Sh='Shaboing:BAAALAAECgEIAgAAAA==.Shadendark:BAAALAAECgIIAgAAAA==.Shadowkock:BAAALAADCgMIAwAAAA==.Shamans:BAAALAAECgIIAgAAAA==.Shamncheese:BAAALAAECgIIAwABLAADCgYIDAABAAAAAA==.Shampe:BAAALAADCgcICgAAAA==.Shasta:BAAALAAECgcIEgAAAA==.Sheepydeep:BAAALAADCgEIAQAAAA==.Shisuiuchiha:BAAALAADCggIEgAAAA==.',Si='Siilas:BAAALAAECgcIDAAAAA==.Sil:BAAALAAECgMIBgAAAA==.Simbaa:BAAALAADCgUIBQAAAA==.Sithremnant:BAAALAADCgIIAgAAAA==.',Sj='Sjdruid:BAAALAAECgIIAwAAAA==.',Sk='Skay:BAAALAADCgYICQAAAA==.Skxar:BAAALAAECgYIBwAAAA==.Skxarlly:BAAALAADCgQIBAAAAA==.',Sl='Slammydooker:BAAALAAECgIIAgAAAA==.Slightstab:BAAALAAECgcIAgAAAA==.',Sm='Smokeshots:BAAALAAECgEIAQAAAA==.',Sn='Sneakygingy:BAAALAADCgQIBAAAAA==.',So='Soki:BAAALAADCgEIAQAAAA==.Soulja:BAAALAAECgQIBgAAAA==.',Sp='Spicytrinket:BAAALAAECgIIAgAAAA==.Spitondagrav:BAAALAADCgIIAgAAAA==.',St='Statik:BAAALAAECgEIAQAAAA==.Stepuncle:BAAALAADCgYIDAAAAA==.Steveesham:BAAALAADCgIIAgABLAAECgUIBQABAAAAAA==.Stonetusk:BAAALAAECgEIAQAAAA==.Strobe:BAAALAADCgYIBgAAAA==.',Su='Sumnèr:BAAALAAECgQIBAAAAA==.',Sy='Syberis:BAAALAADCggICwAAAA==.Systemofivy:BAAALAAECgMIAwAAAA==.',Ta='Talatin:BAAALAADCgEIAQAAAA==.Tandrae:BAAALAADCgEIAQAAAA==.Tansmith:BAAALAADCgcICAAAAA==.Tapered:BAAALAAECgIIAQAAAA==.Tapurd:BAAALAADCgcIBwABLAAECgIIAQABAAAAAA==.Tardo:BAAALAADCgIIAgAAAA==.Tarrful:BAAALAADCgcIBwAAAA==.Taupo:BAAALAAECgUIBgAAAA==.',Te='Techevo:BAAALAADCgUIBgAAAA==.Tengeodnesse:BAAALAADCgQIBAAAAA==.Terrortick:BAAALAADCggIDAAAAA==.Texie:BAAALAADCgcIDwAAAA==.',Th='Thasch:BAAALAADCgUIBwAAAA==.Thicktotem:BAAALAAECgEIAQAAAA==.Thorïn:BAAALAADCgIIAgAAAA==.Thorýn:BAAALAAECgYICAAAAA==.',Ti='Tipsy:BAAALAAECgIIAgAAAA==.Titanite:BAAALAAECgMIAwAAAA==.',Tk='Tkv:BAAALAADCgcIBwAAAA==.',Tr='Tralleth:BAAALAADCggIDwAAAA==.Tranq:BAAALAADCgUICAAAAA==.Treetime:BAAALAAECgYICwAAAA==.Trismegistus:BAAALAAECgMIBQAAAA==.Troxa:BAAALAADCggICAAAAA==.',Tw='Twinklord:BAAALAADCggICgAAAA==.',Ty='Tylopally:BAAALAADCgEIAQAAAA==.Tyloprot:BAAALAAECgUIBgAAAA==.Tylovath:BAAALAAECgIIAgAAAA==.',Uj='Ujc:BAAALAADCggICAABLAADCggICQABAAAAAA==.',Un='Uncookedham:BAAALAAECgIIAgAAAA==.',Ur='Urgh:BAAALAAECgMIBgAAAA==.',Va='Vaeh:BAAALAAECgYICQAAAA==.Valphraen:BAAALAADCgcIBwAAAA==.Vanillaface:BAAALAAECgMIBQAAAA==.',Ve='Velarael:BAAALAADCgcIBwAAAA==.Veldar:BAAALAADCgIIAgAAAA==.Veynxthral:BAAALAADCgEIAQAAAA==.',Vh='Vheckxus:BAAALAADCggICgAAAA==.Vholyduck:BAAALAADCgIIAgAAAA==.',Vi='Vilia:BAAALAADCggICwAAAA==.Vincyn:BAAALAADCggICAAAAA==.',Vk='Vkt:BAAALAAECgUIDAAAAA==.',Vy='Vynivon:BAAALAADCgYIBgAAAA==.',Wa='Wachonaso:BAAALAAECgMIBQAAAA==.',Wh='Wheresmyjaw:BAAALAAECgcIEQAAAA==.',Wi='Wildthree:BAAALAAECgEIAQAAAA==.Wilkiesdh:BAAALAAECgMIBwAAAA==.',Wo='Wookys:BAAALAADCggICAAAAA==.',['Wä']='Wärlöck:BAAALAAECggICAAAAA==.',Xt='Xtk:BAAALAADCgcIBwAAAA==.',Ya='Yahro:BAAALAAECgMIBAAAAA==.Yakhekiri:BAAALAAECgMIBAAAAA==.Yaromane:BAAALAADCgUIBQABLAAECgMIBAABAAAAAA==.Yashiroexe:BAAALAAECgUIBwAAAA==.',Yn='Ynaguinid:BAAALAADCgEIAQAAAA==.',Yo='Yohoko:BAAALAADCgQIBAAAAA==.Yotoymuerto:BAAALAADCgEIAQAAAA==.',['Yü']='Yümmydönuts:BAAALAADCggIDgAAAA==.',Za='Zainar:BAAALAADCgcIBwABLAADCgYIDAABAAAAAA==.Zasso:BAAALAAECgMIAwAAAA==.Zathenoth:BAAALAADCgYIBgAAAA==.Zaydan:BAAALAADCgcIBwAAAA==.',Ze='Zelgor:BAAALAADCgQIBAAAAA==.',['Çl']='Çloud:BAAALAAECgEIAQABLAAECgUIBQABAAAAAA==.',['Ør']='Ørsted:BAAALAADCgYIBgABLAAECgUIBgABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end