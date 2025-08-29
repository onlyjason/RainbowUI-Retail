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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Warrior-Fury','Mage-Frost','Mage-Arcane','Monk-Windwalker','Monk-Mistweaver','Hunter-Survival','Rogue-Subtlety','Druid-Balance','Rogue-Outlaw',}; local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aariichan:BAAALAADCgYIBgAAAA==.',Ad='Adryn:BAAALAADCgYIBgABLAAECgIIBAABAAAAAA==.',Ah='Ahnafal:BAAALAAECgUICAABLAAECgEIAQABAAAAAA==.',Ak='Akaner:BAAALAADCgEIAQAAAA==.',Al='Aldavin:BAAALAAECgMIAwAAAA==.Alecto:BAABLAAECoEVAAICAAgIywmaFwCaAQACAAgIywmaFwCaAQAAAA==.Alodia:BAAALAADCgcIDgAAAA==.Alyssandra:BAAALAADCgcIDgAAAA==.',Am='Amarella:BAAALAADCggICAAAAA==.Amisha:BAAALAADCggICAAAAA==.Ammalane:BAAALAADCgMIAwAAAA==.',An='Anduinn:BAAALAADCgUIBQAAAA==.Ankelbytr:BAAALAADCgYICwAAAA==.Ansigar:BAAALAADCggICAAAAA==.',Ar='Arangarr:BAAALAAECgQICAAAAA==.Arankin:BAAALAADCgMIAwAAAA==.Areyana:BAAALAADCggIDwAAAA==.Arkandra:BAAALAADCgcIEAAAAA==.Arrietty:BAAALAAECgEIAQAAAA==.Arthues:BAAALAADCggICAAAAA==.Arumathe:BAAALAAECgYIDgAAAA==.',As='Ashisogi:BAAALAADCggICAAAAA==.',Az='Az:BAAALAAECgMIBAAAAA==.Azeriall:BAAALAAECgYICgAAAA==.',Ba='Baconhammr:BAAALAAECgMIAwAAAA==.Baddream:BAAALAADCgcICQAAAA==.Bariuster:BAAALAADCgUIBQAAAA==.',Bi='Biffnecrotic:BAAALAADCggIDwAAAA==.',Bl='Bloodnfury:BAAALAAECgMIBQAAAA==.Blucki:BAAALAAECgIIAwAAAA==.',Bo='Boules:BAAALAADCgYIBgABLAAECgEIAgABAAAAAA==.',By='Byzantium:BAAALAAECgQIBQAAAA==.',['Bô']='Bônebeard:BAAALAADCggIDwAAAA==.',['Bõ']='Bõblôd:BAAALAAECgcIDAAAAA==.',Ca='Cabledryer:BAAALAAECgYIEQAAAA==.Calamitty:BAAALAADCgcIBwAAAA==.Caliania:BAAALAADCggICAAAAA==.Calliope:BAAALAAECgQIBwAAAA==.Catastrôphic:BAAALAAECgUIBQAAAA==.Catboy:BAAALAAECgEIAQAAAA==.',Ch='Cheelo:BAAALAADCgQIBAAAAA==.Cheet:BAAALAADCgMIAwAAAA==.Chknnugget:BAAALAAECgIIAgAAAA==.Chronic:BAAALAADCggICgAAAA==.',Ci='Cindrethresh:BAAALAADCggICQAAAA==.',Co='Coffeeblak:BAAALAAECgYICAAAAA==.Collision:BAAALAADCgMIAwAAAA==.Concrete:BAAALAADCggICAAAAA==.Connjuror:BAABLAAECoEXAAIDAAgI+h1AAwBHAgADAAgI+h1AAwBHAgAAAA==.',Cr='Crazybatt:BAAALAADCgMIAwAAAA==.',Cy='Cynderleena:BAAALAADCgcIEAAAAA==.Cynyia:BAAALAAECgUICgAAAA==.',Da='Daddyelessar:BAAALAADCgcIBwAAAA==.Dagon:BAAALAADCggIDgAAAA==.Daveejones:BAAALAAECgIIAgAAAA==.',De='Deadicee:BAAALAAECgEIAgAAAA==.Deathkillar:BAAALAADCgMIAwAAAA==.Deavaos:BAAALAADCgcIBwAAAA==.Deecent:BAAALAAECgQIBQAAAA==.Demiz:BAAALAAECgQIBQAAAA==.Demondragon:BAAALAADCggIEQAAAA==.Demonicus:BAAALAAECgEIAQAAAA==.Dertka:BAAALAADCggIDgAAAA==.',Di='Discoaz:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.Dixie:BAAALAAECgMIBgAAAA==.',Do='Domw:BAAALAAECgQICAAAAA==.Donham:BAABLAAECoEWAAMEAAgIKSaZAABZAwAEAAgIKSaZAABZAwAFAAMIzRlKWgDcAAAAAA==.Doomdoomrage:BAAALAADCgcIBwAAAA==.Dorkimedes:BAAALAAECgYICQAAAA==.',Dr='Drunkenrage:BAAALAADCggIEAAAAA==.',Du='Ducan:BAAALAADCgEIAQAAAA==.Durenn:BAABLAAECoEWAAIGAAgIQCA1CADWAgAGAAgIQCA1CADWAgAAAA==.',Dw='Dwadler:BAAALAADCgYIBAAAAA==.',Dy='Dyrkazen:BAAALAADCgcIBwAAAA==.',['Dä']='Dämonjägger:BAAALAADCgcIDQAAAA==.',Ea='Earthlyskank:BAAALAADCgcIDAAAAA==.',Em='Embre:BAAALAAECgYIDAAAAA==.',Er='Eraxi:BAAALAADCgcICgAAAA==.',Eu='Euryphaessa:BAAALAADCgcIBwAAAA==.',Ev='Evlpotato:BAAALAADCgcICQAAAA==.Evojak:BAAALAAECgMIBAAAAA==.',Fa='Fader:BAAALAADCgMIAwAAAA==.Faenor:BAAALAAECgMIAwAAAA==.Fairaday:BAAALAAECgMIBQAAAA==.Faxqueenmage:BAAALAAECgMIBAAAAA==.',Fe='Feldo:BAAALAADCgYIBgAAAA==.Felthyfrank:BAAALAADCggICAAAAA==.Feorisper:BAAALAADCgMIAwAAAA==.Festering:BAAALAADCggICAAAAA==.',Fi='Fizehtotems:BAAALAADCgcIDAAAAA==.',Fl='Fluffytank:BAAALAADCggIDAAAAA==.',Fo='Foragarn:BAAALAAECgQIBAAAAA==.Foxpaws:BAAALAADCgcIBwAAAA==.',Fr='Frankkastle:BAAALAAECgQIBwAAAA==.Fridgexd:BAAALAAECgYICQAAAA==.Froggierlynx:BAABLAAECoEUAAMGAAgIBxdpEABHAgAGAAgIBxdpEABHAgAHAAUIPBLuNABFAQAAAA==.',Fu='Furtata:BAAALAADCggICAABLAADCgcICQABAAAAAA==.',Fy='Fyrestone:BAAALAADCgcIDgAAAA==.',Ga='Gabulous:BAAALAADCgcIDgAAAA==.Galencharred:BAAALAADCgcIEgAAAA==.Garagon:BAAALAAECgIIBAAAAA==.Garbinger:BAAALAAECgYICAAAAA==.Garurumon:BAAALAAECgYIBgABLAAECggIFAAIAIUgAA==.Gauss:BAAALAAECgMIAwAAAA==.Gavelle:BAAALAADCggIDwAAAA==.',Ge='Gerva:BAAALAAECgIIBAAAAA==.',Gh='Ghorfindor:BAAALAAECgEIAQAAAA==.',Gi='Gilas:BAAALAAECgQIBQAAAA==.',Gl='Globeasaure:BAAALAADCgcIBwAAAA==.',Gn='Gnik:BAAALAAECgMIBAAAAA==.',Go='Goatank:BAAALAAECgUIBgABLAAECgYIDgABAAAAAA==.Goldentorus:BAAALAADCgcIBwAAAA==.',Gr='Graahak:BAAALAAECgIIAgAAAA==.Graveborn:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.Grimsin:BAAALAADCgUIBQAAAA==.Grimstout:BAAALAADCgQIBAAAAA==.',Gu='Gutmtmon:BAAALAADCgcIDgAAAA==.',Gw='Gwenivive:BAAALAAECgMIBQAAAA==.',Ha='Hadwe:BAAALAADCgMIAwAAAA==.Hamar:BAAALAADCgEIAQAAAA==.Handofjustic:BAAALAADCggIDwAAAA==.',He='Hellda:BAEALAAECgMIAwABLAAECgQIBgABAAAAAA==.Hellzknîght:BAAALAADCgMIAwAAAA==.Hellzmonk:BAAALAAECgEIAQAAAA==.',Hi='Hikons:BAAALAADCggIDgAAAA==.',Ho='Holek:BAAALAAECgcIDwAAAA==.Holgo:BAABLAAECoEXAAIJAAgIayQ9AgBUAwAJAAgIayQ9AgBUAwAAAA==.Holyp:BAAALAADCgEIAQAAAA==.',Hr='Hraesvelger:BAAALAADCgcIBwAAAA==.',Hu='Huntresluna:BAAALAADCgcIBwAAAA==.',Ib='Iblueberryl:BAAALAADCgMIAwAAAA==.',Ic='Icia:BAAALAAECgMIBQAAAA==.',Id='Idontmiss:BAAALAAECgQICAAAAA==.',Ie='Ierestoy:BAAALAADCggIDAAAAA==.',Ig='Igneel:BAAALAAECgYIDAAAAA==.',Is='Isalia:BAAALAAECgYICQAAAA==.Iseila:BAAALAAECgYIBgAAAA==.Isevio:BAAALAAECgQIBQAAAA==.',It='Ithoran:BAAALAAECgQICQAAAA==.',Ja='Jaadd:BAAALAADCgUIBAAAAA==.Jaade:BAAALAADCgUIBQAAAA==.Jakk:BAAALAADCgEIAQABLAAECgMIBAABAAAAAA==.Jaman:BAAALAAECgMIAwABLAAECggIFgAEACkmAA==.Jamien:BAAALAAECgIIBAAAAA==.Javaka:BAAALAADCgUIBgAAAA==.',Jd='Jdeezy:BAAALAAECgIIAgAAAA==.Jdubbzy:BAAALAADCggICAAAAA==.',Je='Jessemyn:BAAALAAECgIIAgAAAA==.',Ji='Jiyeon:BAAALAAECgQIBQAAAA==.',Jp='Jproudmore:BAAALAADCgQIBQAAAA==.',Ju='Juanabolt:BAAALAAECgQIBQAAAA==.',Ka='Kaathe:BAAALAAECgUICgAAAA==.Kaidiis:BAAALAAECgMIBQAAAA==.Karbonn:BAAALAADCggIDwAAAA==.',Ke='Keelin:BAAALAAECgMIBAAAAA==.Kegbreaker:BAAALAAECgMIBQAAAA==.Keleden:BAAALAADCggICwAAAA==.Keros:BAAALAADCgcICwAAAA==.',Kh='Kharme:BAAALAAECgMIAwAAAA==.Khumi:BAAALAAECggIEQAAAA==.Khädgar:BAAALAAECgYIDgAAAA==.',Ki='Kilauea:BAAALAAECgIIAgAAAA==.Killtana:BAAALAADCgEIAQAAAA==.Kimbustible:BAAALAADCgYIBgABLAAECgYIDQABAAAAAA==.',Kn='Knockknocko:BAAALAAECgYICAAAAA==.Knocko:BAAALAADCggIDgAAAA==.',Ko='Komodostyle:BAAALAAECgEIAQAAAA==.',Kr='Kreiell:BAAALAAECgEIAQAAAA==.Kreirell:BAAALAADCgMIBAAAAA==.Krisarugala:BAAALAAECgYICQAAAA==.Krol:BAAALAAECgEIAQAAAA==.',Ku='Kunuku:BAAALAAECgMIAQAAAA==.Kurogami:BAAALAADCgIIAgAAAA==.Kurogen:BAAALAADCgEIAQAAAA==.',Ky='Kylesxmom:BAAALAAECgMIBQAAAA==.Kymal:BAAALAADCggICAAAAA==.',['Kä']='Käryff:BAAALAADCggIDwAAAA==.',['Kë']='Këy:BAAALAAECgYICQAAAA==.',['Kí']='Kíriito:BAAALAAECgMIAwAAAA==.',La='Lanlorimas:BAAALAADCgcIDgAAAA==.Latrice:BAACLAAFFIEFAAIKAAMIyx8kAABCAQAKAAMIyx8kAABCAQAsAAQKgRcAAwsACAhyIlQMAMsCAAsACAj/IVQMAMsCAAoABQigFFgbAEwBAAAA.Laviosa:BAAALAAECgcIDQAAAA==.',Le='Leevon:BAAALAADCggIDAABLAAECgMIBQABAAAAAA==.Leftyfrizz:BAAALAADCggIDgAAAA==.Leviscus:BAAALAADCggIEgAAAA==.',Li='Lightbill:BAAALAAECgMIAwAAAA==.Lijak:BAAALAAECgMIAwAAAA==.Lilblitzz:BAAALAADCgcIDAAAAA==.Lildrshadowz:BAAALAADCggIBwAAAA==.Lildruidz:BAAALAADCgUIBQAAAA==.Lilriotzz:BAAALAADCggICwAAAA==.Lilsnapz:BAAALAADCgcIBwAAAA==.Lilzriotz:BAAALAADCggICgAAAA==.Littlehand:BAAALAAECgEIAQAAAA==.Lizzliana:BAAALAADCgcIBwAAAA==.',Lo='Lovecraft:BAAALAADCgYIBgAAAA==.',Lu='Lurosh:BAAALAAECgEIAgAAAA==.',['Lï']='Lïghts:BAAALAAECgUICAAAAA==.',Ma='Mamacaster:BAAALAADCgEIAQAAAA==.Manales:BAAALAADCggICAAAAA==.Manöwar:BAAALAADCgMIBgAAAA==.Marhukai:BAAALAAECgMIBQAAAA==.Marici:BAAALAADCggICAAAAA==.Marotal:BAAALAADCggIDwAAAA==.Marsolean:BAAALAADCggIEAAAAA==.Martysparty:BAAALAAECgMIBgAAAA==.',Me='Mechaboomer:BAAALAAECgIIBAAAAA==.Megafire:BAAALAADCgcICAAAAA==.Menthol:BAAALAADCgcICQAAAA==.',Mi='Micktarogar:BAAALAAECgMIBwAAAA==.Minikloon:BAABLAAECoEaAAMMAAgIOB7/BACvAgAMAAgIOB7/BACvAgANAAIIEAOTJQBLAAAAAA==.Misstake:BAAALAADCgYICAAAAA==.Mistorri:BAAALAAECgMIBQAAAA==.Mistweaver:BAAALAAECgEIAgAAAA==.',Mo='Mollyporph:BAAALAAECggIDgAAAA==.Monoco:BAAALAADCggIDwAAAA==.Moofasa:BAAALAAECgMIAwAAAA==.Mookie:BAAALAADCggIDAAAAA==.Moonkim:BAAALAAECgYIDQAAAA==.Moradora:BAAALAADCgMIAwAAAA==.Morganah:BAAALAAECgMIAwAAAA==.Morpheus:BAAALAAECgMIAwAAAA==.Mortrum:BAAALAADCgMIAwAAAA==.',Mu='Mushaboom:BAAALAADCggIDwAAAA==.Muzzler:BAAALAAECggIEQAAAA==.',My='Mylinkah:BAAALAADCgcIBwAAAA==.Mynamefizz:BAAALAAECgQIBwAAAA==.Mythlok:BAAALAADCgcIEgAAAA==.',['Mó']='Mórtis:BAAALAADCgYIBgAAAA==.',Na='Nadis:BAAALAAECgMIAwAAAA==.Nashalle:BAAALAADCgYIDAAAAA==.Naturamirage:BAAALAADCgcIDgAAAA==.',Ni='Nightxwish:BAAALAAECgEIAQAAAA==.',No='Noctus:BAAALAAECgEIAQAAAA==.Noisemarine:BAAALAADCggIDwAAAA==.Norellia:BAAALAADCgcICwAAAA==.Northspirit:BAAALAADCgcIEgAAAA==.Novablade:BAAALAAECgUIBAAAAA==.',Ny='Nyx:BAAALAADCgYIDAABLAAECgIIBAABAAAAAA==.Nyxazara:BAAALAADCggIDgAAAA==.',Ob='Obscur:BAAALAAECgMIBQAAAA==.',Od='Oddinsstaff:BAAALAADCgEIAQAAAA==.',Oh='Ohyikers:BAAALAAFFAIIAgAAAA==.',Op='Openedfalcon:BAABLAAECoEVAAIOAAgIhx7GAADsAgAOAAgIhx7GAADsAgAAAA==.Oppey:BAAALAADCgYIBgAAAA==.',Pa='Pallek:BAAALAAECgEIAQABLAAECgcIDwABAAAAAA==.Pasta:BAAALAAECgYIDgAAAA==.',Ph='Phantomärrow:BAAALAAECggIEAAAAA==.Phude:BAAALAAECgYICgAAAA==.',Pl='Ploutòn:BAAALAAECgYICQAAAA==.',Po='Pohl:BAAALAADCgMIAwAAAA==.Poohynok:BAAALAADCggICwAAAA==.Pootieshoe:BAAALAADCgYIBwAAAA==.Potatodave:BAAALAAECgMIBAAAAA==.',Pr='Préachér:BAAALAADCgcICwABLAAECgMIAwABAAAAAA==.',Py='Pyramys:BAABLAAECoEaAAIPAAgI9iBYAQDiAgAPAAgI9iBYAQDiAgAAAA==.',Ra='Raemagne:BAAALAADCggICAAAAA==.Rainheart:BAAALAAECgYICAAAAA==.Rawhawk:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.Razgrizz:BAAALAADCgcIEAAAAA==.',Re='Retro:BAAALAADCgcIEgAAAA==.',Ri='Rialia:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Ribbonk:BAAALAADCgEIAQAAAA==.Rileyann:BAAALAAECgIIAwAAAA==.',Ro='Ronmaclean:BAAALAADCgcIBwAAAA==.Roozer:BAAALAADCgcIDQAAAA==.Rozemyne:BAAALAADCgcIBwAAAA==.',Sa='Saelyria:BAAALAAECgQIBgAAAA==.Sandiera:BAAALAADCggIDwAAAA==.Sarr:BAABLAAECoEbAAIQAAgIGB4VCQCfAgAQAAgIGB4VCQCfAgAAAA==.',Sc='Scarlett:BAAALAAECgYICwAAAA==.Scarlxrd:BAAALAAFFAIIAgAAAA==.Scoreboard:BAEBLAAECoEZAAIRAAgIjyYHAACVAwARAAgIjyYHAACVAwAAAA==.',Se='Sedric:BAAALAAECgIIAgAAAA==.Sesskaa:BAAALAAECgQIBQAAAA==.',Sh='Shamthrax:BAAALAADCgYIBgABLAAECggIEAABAAAAAA==.Shünúkh:BAAALAADCgYIBgAAAA==.',Si='Sinistergate:BAAALAAECgYICwAAAA==.Sinogad:BAAALAAECggICgAAAA==.Sinos:BAAALAADCggICAAAAA==.',Sk='Skarho:BAAALAADCgIIAgAAAA==.Skaro:BAAALAADCggIDgAAAA==.',Sl='Slopptop:BAAALAADCgUIBQAAAA==.',Sm='Smokedademon:BAAALAADCgcICQAAAA==.Smokiebear:BAAALAAECggIBgAAAA==.Smuggy:BAAALAADCggIEAABLAAECgQICAABAAAAAA==.',Sn='Snackrapp:BAAALAADCgcIBwAAAA==.Snowclaws:BAAALAADCgYIDgAAAA==.',Sp='Spanox:BAAALAAECgEIAQAAAA==.',Sq='Squallheart:BAAALAAECgMIBQAAAA==.',St='Stankbreath:BAAALAADCggIEAAAAA==.Stankness:BAAALAADCggIEAAAAA==.Stinko:BAAALAADCgcICwAAAA==.Stoopdk:BAAALAADCgYIBgAAAA==.Stooper:BAAALAAECgUIBwABLAAECgUIBwABAAAAAA==.Stoopin:BAAALAAECgUIBwAAAA==.Stoops:BAAALAAECgUIBQABLAAECgUIBwABAAAAAA==.Stoopss:BAAALAAECgUIBQABLAAECgUIBwABAAAAAA==.Stoutnholy:BAAALAADCggIDwAAAA==.Stratichnut:BAAALAAECgIIBAAAAA==.Stwampy:BAAALAAECgUIBwAAAA==.Stwiest:BAAALAADCggICAAAAA==.',Su='Subuwu:BAAALAAECgQIBAAAAA==.',Sw='Swampert:BAAALAAECgQIBQAAAA==.Swaye:BAAALAAECgEIAQAAAA==.',Sy='Syllvanas:BAAALAADCggIDgAAAA==.',Ta='Tacomistress:BAAALAADCgIIAgAAAA==.Tagath:BAAALAAECgMIBQAAAA==.Taitai:BAAALAADCgcICAAAAA==.Talibear:BAAALAADCggIDwAAAA==.Taloon:BAAALAAECgMIAQAAAA==.Taltost:BAAALAAECgEIAgAAAA==.Tarv:BAAALAADCgYIBgAAAA==.Tashamirage:BAAALAADCggIFwAAAA==.Taterthot:BAAALAAECgQICAABLAADCgcICQABAAAAAA==.',Te='Teksuo:BAAALAAECgQIBQAAAA==.Tenebra:BAAALAAECggICwAAAA==.Tenithon:BAAALAAECgYICgAAAA==.',Th='Thelora:BAAALAADCgQIBAAAAA==.Themrman:BAAALAADCgQIBAAAAA==.Thierry:BAAALAAECgMIBgAAAA==.Tholaren:BAAALAADCggIEwAAAA==.Thrissa:BAAALAADCggIDwAAAA==.Thump:BAAALAADCgQIBAAAAA==.',Ti='Ticklemaiden:BAAALAAECgMIBQAAAA==.Tinkerspell:BAAALAAECgYIDQAAAA==.Tirathon:BAAALAADCgcICwAAAA==.',To='Totemfalcon:BAAALAADCgMIBAABLAAECggIFQAOAIceAA==.',Tr='Trangon:BAAALAADCgUIBAAAAA==.Treezus:BAAALAADCgcIEQAAAA==.Triel:BAAALAADCggIDwAAAA==.Trillion:BAAALAAECgEIAQAAAA==.Trudh:BAAALAAECgYICAAAAA==.Träxx:BAAALAADCgMIAwAAAA==.',Ud='Udari:BAAALAAECgIIBAAAAA==.',Va='Vaghar:BAAALAADCgcIBwAAAA==.Vahnkar:BAAALAADCgEIAQAAAA==.Varithal:BAAALAADCggICAABLAAECgYICwABAAAAAA==.Vast:BAAALAAECgMIBAAAAA==.',Ve='Venawyn:BAAALAAECgQIBQAAAA==.Vengeancë:BAAALAADCgcIBwAAAA==.',Vi='Viral:BAAALAAECgYIDQAAAA==.Vixin:BAAALAADCgcIDgAAAA==.Vixinhunter:BAAALAADCgYIBgAAAA==.Vixinisadrag:BAAALAADCgcIDQAAAA==.',Vo='Voidsaack:BAAALAADCgcIBwAAAA==.Vortan:BAAALAAECgcIEAAAAA==.',Wh='Whatmyname:BAAALAAECgIIBAAAAA==.',Wi='Wikkd:BAAALAAECgcIDQAAAA==.Wildturtle:BAAALAAECgUIBgAAAA==.',Wo='Wolfknights:BAAALAADCgMIAwAAAA==.Wormwood:BAAALAADCggICAABLAAECgYICgABAAAAAA==.',Wy='Wytotems:BAAALAAECgQICAAAAA==.Wyvoker:BAAALAADCggICAABLAAECgQICAABAAAAAA==.',Xu='Xuny:BAAALAADCgcICgAAAA==.',Ya='Yasnah:BAAALAAECgEIAQAAAA==.',Yo='Yordi:BAAALAAECgEIAQAAAA==.',Yu='Yuzuriha:BAAALAAECgYICwAAAA==.',Za='Zamaze:BAAALAAECgQICAAAAA==.Zaras:BAAALAADCgYIBgAAAA==.Zarithria:BAAALAADCgYIBgAAAA==.',Ze='Zeekielle:BAEALAAECgQIBgAAAA==.',Zi='Zippii:BAAALAADCgcICQAAAA==.Zipy:BAAALAAECgIIAgAAAA==.',Zo='Zorathar:BAAALAADCgcIBwAAAA==.',Zy='Zyllo:BAAALAADCggIGgAAAA==.',['Ár']='Árthas:BAAALAADCgEIAQAAAA==.',['Ål']='Ålïce:BAAALAAECgcIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end