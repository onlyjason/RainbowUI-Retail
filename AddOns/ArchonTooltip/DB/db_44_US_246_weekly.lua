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
 local lookup = {'Unknown-Unknown','Druid-Restoration','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Paladin-Retribution','DeathKnight-Blood','DeathKnight-Frost','Shaman-Enhancement',}; local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaronfreeze:BAAALAAECgYICgAAAA==.',Ac='Actaeøn:BAAALAAECgUICAAAAA==.',Aj='Ajaxz:BAAALAADCgIIAgAAAA==.',Al='Albedô:BAAALAAECgQICgABLAAECgcIDwABAAAAAA==.Aliren:BAAALAAECgEIAQAAAA==.Allformarc:BAAALAADCgcIBwAAAA==.Allmaick:BAAALAAECgIIAgAAAA==.Alystrasza:BAAALAAECgMIBgAAAA==.',An='Antimovsky:BAAALAAECgMIBgAAAA==.',Ar='Arlare:BAABLAAECoEXAAICAAgIfiI9AgD9AgACAAgIfiI9AgD9AgAAAA==.Arzavaen:BAAALAADCgQIBAAAAA==.',Au='Aullyura:BAAALAADCgcIBwAAAA==.',Be='Bertringer:BAAALAAECgIIAgAAAA==.',Bi='Bigbodybenzz:BAAALAAECgcIDgAAAA==.Bigdipper:BAAALAAECgEIAQAAAA==.Birthcontrol:BAAALAADCgIIAgAAAA==.Bisha:BAAALAADCgYIBgAAAA==.Bizcocho:BAAALAADCgcIBwAAAA==.',Bl='Blackscales:BAAALAADCggIDwAAAA==.Blickblop:BAAALAAECgUIBQAAAA==.',Bo='Boomkingobrr:BAAALAADCgEIAQAAAA==.Boopnoot:BAAALAADCggIDgAAAA==.Boosted:BAAALAADCgMIAwABLAAFFAMIBgADAIoYAA==.Boss:BAAALAADCgcIFQAAAA==.Bouttreefidy:BAAALAADCgcIDQABLAAFFAMIBgADAIoYAA==.',Bu='Bubbleballs:BAAALAADCggICwAAAA==.Buckits:BAAALAADCgYIBwAAAA==.Buratino:BAAALAADCgQIBAAAAA==.Burnsx:BAAALAAECgMIAwABLAAFFAMIBgADAIoYAA==.Burrucey:BAAALAAECgMIAwAAAA==.',Bw='Bwoar:BAAALAAECgMIBgAAAA==.',By='Bye:BAAALAADCgEIAQAAAA==.',Ca='Calaheals:BAAALAADCggIDwABLAAECgEIAQABAAAAAA==.',Ce='Cernnunnos:BAAALAADCggIFwABLAAECgYICQABAAAAAA==.',Ch='Cherga:BAAALAADCgcICwAAAA==.Choice:BAAALAADCggIFwAAAA==.Chudlife:BAAALAADCggICAAAAA==.',Ci='Cindere:BAAALAADCgcIDQAAAA==.',Cl='Clarion:BAAALAADCgcIBwAAAA==.Cliint:BAAALAAECgIIAgAAAA==.',Co='Coldfrio:BAAALAADCggICAAAAA==.',Cy='Cydar:BAAALAADCgQIBAAAAA==.',Da='Dankins:BAABLAAECoEfAAMEAAgIvCV/AABbAwAEAAgIvCV/AABbAwAFAAUIbQdjMgAPAQAAAA==.',De='Deathtraper:BAAALAADCgEIAQAAAA==.Debur:BAAALAADCgIIAgAAAA==.Demunhuner:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.Dette:BAAALAAECgEIAQAAAA==.Devilchaser:BAAALAAECgMIBgAAAA==.',Di='Dilix:BAAALAADCgYIBgAAAA==.Divinity:BAAALAAECgIIAgAAAA==.',Do='Doctrdoom:BAAALAADCgUIBQABLAAECgQIBQABAAAAAA==.Donotfear:BAAALAADCgIIAgAAAA==.Doyueventank:BAAALAADCggICAAAAA==.',Dr='Droopnoot:BAAALAADCgYIBgAAAA==.Drstabington:BAAALAADCggIDwAAAA==.Drunkard:BAAALAAECgQIBgAAAA==.',Du='Duxlock:BAAALAAECgEIAQAAAA==.',Dy='Dycra:BAAALAAECgIIAgAAAA==.Dypew:BAAALAAECggIDQAAAA==.',Ed='Edarix:BAAALAADCgEIAQABLAAECgYICQABAAAAAA==.',Ek='Ekmek:BAAALAADCgEIAQAAAA==.',El='Elabernathy:BAAALAAECgEIAgAAAA==.Elenay:BAAALAAECgMIBgAAAA==.',Em='Emulsdeath:BAAALAAECgMIAwABLAAECgcIEAABAAAAAA==.Emulsifier:BAAALAAECgcIEAAAAA==.',Er='Erusgizmo:BAAALAAECgcIDgAAAA==.',Ez='Ezurael:BAAALAAECgEIAQAAAA==.',Fa='Fairbear:BAAALAAECgMIBQAAAA==.',Fe='Fearna:BAAALAADCgIIAgAAAA==.',Fi='Finester:BAAALAAECgcIEAAAAA==.Fisticuff:BAAALAADCgMIAwABLAAECgYIEAABAAAAAA==.',Fl='Flatline:BAAALAADCggIDgAAAA==.Flerken:BAAALAADCgcIBwAAAA==.Flickbean:BAAALAADCgEIAQAAAA==.',Fr='Fruitgrinder:BAAALAADCgUIBQAAAA==.',Ga='Gabi:BAAALAADCgYIBgAAAA==.Garin:BAAALAAECgEIAQAAAA==.Gaschags:BAAALAAECgEIAgAAAA==.',Gi='Gitrektt:BAAALAAECgIIAgAAAA==.',Gl='Glizzybreath:BAAALAAECgQIBAAAAA==.',Go='Gorska:BAAALAAECgMIBgAAAA==.',Gr='Graardor:BAAALAAECgEIAQAAAA==.Greenjeans:BAAALAADCgcIDQAAAA==.Grit:BAAALAADCgcIDAABLAAECgQIBQABAAAAAA==.',Ha='Hanni:BAAALAAECgcIDwAAAA==.Haveaburitto:BAAALAAECgYICQAAAA==.Hawktoetem:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.',He='Hedemon:BAAALAADCgcICgAAAA==.Hellshand:BAAALAADCggICAAAAA==.',Ho='Holycøw:BAAALAADCgYICgAAAA==.Hommon:BAAALAAECgcIDAAAAA==.',Hq='Hqerny:BAAALAAECggIBgAAAA==.',Hu='Hughjass:BAAALAAECgMIBgAAAA==.',['Hü']='Hümpndümp:BAAALAADCgEIAQAAAA==.',Ih='Ihureciv:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.',Il='Illior:BAAALAAECgMIBAAAAA==.Illivori:BAAALAADCggICAAAAA==.',Im='Impimpimpimp:BAAALAADCgcIDQABLAAFFAMIBgADAIoYAA==.',In='Inkdancer:BAAALAADCggICwAAAA==.',Ip='Ipopkidneys:BAABLAAECoEXAAMGAAgI4iM2AgAvAwAGAAgI4iM2AgAvAwAHAAEIYR4NFQBSAAAAAA==.',Ir='Iridia:BAAALAAECgEIAQAAAA==.Iroi:BAAALAADCggIEAAAAA==.',Iy='Iyanne:BAAALAADCgYIBgAAAA==.',Ja='Jametrok:BAAALAAECggIAwAAAA==.',Je='Jeriçho:BAAALAAECgEIAQAAAA==.',Ji='Jiraîya:BAAALAAECgUIBQAAAA==.',Ju='Jugo:BAAALAADCgcIBwAAAA==.',Kd='Kdash:BAAALAADCgcICwAAAA==.',Kh='Khthonios:BAAALAAECgMIAwAAAA==.',Ko='Koisy:BAAALAADCggIBAAAAA==.Koopapal:BAAALAAECgMIBAAAAA==.',La='Largemann:BAAALAAECgIIAgABLAAECgcIDwABAAAAAA==.',Le='Leloo:BAAALAADCgcICAAAAA==.',Li='Lilliana:BAAALAAECgEIAQAAAA==.Lillianna:BAAALAAECgMIBgAAAA==.Lilwilli:BAAALAADCgcIDgAAAA==.Lisbeth:BAAALAADCgIIAgAAAA==.',Lo='Loenhart:BAAALAADCggIDQAAAA==.Lolkurtone:BAAALAAECgIIAgAAAA==.Loopnoot:BAAALAAECgEIAQAAAA==.',Lu='Luciaan:BAAALAADCggIDwAAAA==.Lunabloom:BAAALAADCggICAAAAA==.Lunastorm:BAAALAAECgcIDgAAAA==.Lune:BAAALAADCggICwAAAA==.Luponero:BAAALAAECgYIDAAAAA==.',Ma='Madzcows:BAAALAADCgMIAwAAAA==.Mamaheals:BAAALAADCggICAAAAA==.Mandos:BAAALAAECgYICQAAAA==.Manzoman:BAAALAADCgUIBwAAAA==.Maralayia:BAAALAAECggICAAAAA==.',Mc='Mcfistypoo:BAAALAADCgUIBQAAAA==.',Me='Megumixo:BAAALAADCggICAAAAA==.Merlini:BAAALAAECgMIAwAAAA==.Meshflowin:BAAALAADCggIFwAAAA==.',Mi='Mitzis:BAAALAAECgYICgAAAA==.',Mo='Mommymilker:BAAALAADCgcIBwAAAA==.Moondo:BAAALAADCggICAAAAA==.Morbisity:BAAALAAECgEIAQAAAA==.',['Mè']='Mètis:BAAALAADCggICAAAAA==.',['Mó']='Mórgoth:BAAALAAECgcIDgABLAAECgYICQABAAAAAA==.',Ni='Nickvoker:BAAALAADCgYIBgAAAA==.',Nu='Nurmally:BAAALAAECgEIAQAAAA==.',Of='Offspeck:BAAALAAECgQIBQAAAA==.',Ou='Outbreak:BAAALAAECggICAAAAA==.',Oz='Ozwald:BAAALAAECgcIEAAAAA==.',Pa='Paff:BAAALAAECgQIBQAAAA==.',Pe='Peachaid:BAEALAAFFAEIAQAAAA==.Peachie:BAAALAAECgIIAwAAAA==.Peetree:BAAALAADCggIBgAAAA==.Pentennison:BAAALAADCgQIBAAAAA==.Petures:BAAALAAECgUICwAAAA==.',Ph='Phosphorus:BAAALAAECgcIEQAAAA==.',Pi='Piddydiddy:BAAALAADCggICQAAAA==.',Pl='Plagüë:BAAALAAECgcIEAAAAA==.Plexx:BAAALAADCggICAAAAA==.Pluckedchkn:BAAALAADCggICAAAAA==.',Po='Poofighter:BAAALAAECgEIAQABLAAECgcIDwABAAAAAA==.Pooncandy:BAAALAAECgEIAQAAAA==.',Pr='Precious:BAAALAADCggIDwAAAA==.',Qs='Qsrqasda:BAAALAADCgYIBgAAAA==.',Qt='Qtmenopaws:BAAALAADCggIEwAAAA==.Qtptt:BAAALAAFFAIIAgAAAA==.',Qu='Quillana:BAAALAADCgcIBwAAAA==.',Ra='Radiantsloth:BAAALAADCgEIAQABLAAECgEIAQABAAAAAA==.Raelynne:BAAALAAECgIIAgAAAA==.Ragemage:BAAALAADCgEIAQABLAAECgcICgABAAAAAA==.Ragemonk:BAAALAAECgcICgAAAA==.Ragerogue:BAAALAAECgEIAQABLAAECgcICgABAAAAAA==.Rakeurface:BAAALAADCgIIAgAAAA==.Raptorchrist:BAAALAAECgMIAwAAAA==.Rasmong:BAAALAAECgEIAQAAAA==.Ravinnytesky:BAAALAAECgIIAgAAAA==.',Re='Retaliator:BAAALAAECgYICQAAAA==.',Rh='Rhae:BAABLAAECoEUAAIIAAcIug8ICwB9AQAIAAcIug8ICwB9AQABLAAECgYICQABAAAAAA==.',Ro='Rosè:BAAALAAECgMIAwABLAAECgYICQABAAAAAA==.',Ry='Ryguycombust:BAAALAADCgYIBgAAAA==.Ryguyro:BAAALAADCgYIBgAAAA==.',Sa='Sacerbelator:BAAALAAECgIIAgAAAA==.Sanexa:BAAALAADCgcICwAAAA==.Satsu:BAAALAADCgIIAgAAAA==.',Sc='Scaja:BAAALAADCgUIBQAAAA==.Scrumpvincet:BAAALAADCgMIBgAAAA==.',Se='Sedda:BAABLAAECoEVAAIJAAgIxSXcAgBYAwAJAAgIxSXcAgBYAwAAAA==.Selune:BAAALAADCgcIBwAAAA==.Senbonsenbon:BAAALAAECgEIAQAAAA==.Sensual:BAAALAAECgYIDAAAAA==.Sesshomaru:BAAALAAECgcIDwAAAA==.',Sh='Sharamooke:BAAALAADCgQIBAABLAAECgQIBAABAAAAAA==.Shirona:BAAALAADCgcIBwAAAA==.Shub:BAAALAADCgcIEwAAAA==.',Si='Siare:BAAALAAECgIIAgAAAA==.Sixfootsix:BAAALAAECgUICAAAAA==.',Sk='Skadî:BAAALAADCggICAAAAA==.Skechers:BAAALAAECgMIBQAAAA==.Skeeter:BAAALAAECgMIBQAAAA==.',Sn='Sneekee:BAAALAADCgMIAwABLAAECgQIBAABAAAAAA==.Sneetch:BAAALAAECgMIBwAAAA==.',So='Solstice:BAAALAADCgYIBgAAAA==.Sonichoos:BAAALAADCgcIDQAAAA==.Soulforged:BAAALAADCgYICQABLAAECgcICwABAAAAAA==.Soulscale:BAAALAADCggIEAABLAAECgcICwABAAAAAQ==.Soulseer:BAAALAAECgcICwAAAA==.',Sp='Spookz:BAAALAADCgQIBAAAAA==.',Su='Subs:BAAALAADCgcIBwAAAA==.',['Sâ']='Sâtoru:BAAALAAECgcIDwAAAA==.',Ta='Tanaelle:BAAALAAECgMIAwAAAA==.Tannia:BAAALAADCgYIBgAAAA==.Taxgirly:BAAALAAECgcIDwAAAA==.',Th='Thats:BAAALAADCgMIBAAAAA==.Thizzles:BAABLAAECoEQAAMKAAgIiBJTDQBRAQAKAAYISg9TDQBRAQALAAUIyA6ESgAwAQAAAA==.',Ti='Tiarisaril:BAAALAAECgYICQAAAA==.',To='Toe:BAAALAAECgIIAgAAAA==.Topenga:BAAALAAECgcIDQAAAA==.',Tw='Twicelife:BAAALAAECgQIBAABLAAECgcIEQABAAAAAA==.',['Tü']='Türök:BAAALAAECgIIAwAAAA==.',Uh='Uhtred:BAAALAAECgUIBgAAAA==.',Un='Undread:BAAALAAECgYIEAAAAA==.Uneedsummilk:BAAALAADCggIDgAAAA==.',Uq='Uqt:BAAALAAECgQICAAAAA==.',Va='Valoria:BAAALAAECgEIAQAAAA==.',Vi='Viceruhl:BAAALAAECgcIEAAAAA==.Viserion:BAAALAAECgIIAgAAAA==.',Vo='Vondage:BAAALAAECgIIAwAAAA==.',Vu='Vue:BAAALAAECgcIDgAAAA==.',Wa='Wakasham:BAABLAAECoEVAAIMAAgIQiVyAABPAwAMAAgIQiVyAABPAwAAAA==.Waypaw:BAAALAAECgMIAwAAAA==.',We='Weewee:BAAALAADCggIBQAAAA==.',Wi='Willpower:BAAALAADCgcIBwAAAA==.',Wo='Wolfzbåin:BAAALAAECgYICQAAAA==.',Wu='Wunderlust:BAAALAAECgcIDgAAAA==.',Xa='Xanedina:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.',Xm='Xmatick:BAAALAAECggIBQAAAA==.',Ye='Yellowshaman:BAAALAAECgcIEAAAAA==.',Yu='Yuruse:BAAALAAECgMIAgABLAAECgQIBAABAAAAAA==.',Zu='Zuriznikov:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.',['Ån']='Ångie:BAAALAADCggICAAAAA==.',['Úz']='Úzui:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end