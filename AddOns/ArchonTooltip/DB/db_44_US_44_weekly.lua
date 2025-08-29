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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Shaman-Enhancement','Mage-Arcane','Druid-Balance',}; local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=44,date='2025-08-29',data={Ad='Adventureux:BAAALAAECgYIDQAAAA==.',Ag='Aglæca:BAAALAADCgEIAQABLAAECgQIBAABAAAAAA==.Agnos:BAAALAAECgcIDQAAAA==.Aguaholic:BAAALAADCggIDwAAAA==.',Al='Alacuma:BAAALAAECggIEQAAAA==.Alludes:BAAALAAECgEIAQAAAA==.Almosteasy:BAAALAAECgcIDgAAAA==.Alunagryn:BAAALAAECgYICwAAAA==.Alvera:BAAALAADCgcICgAAAA==.',An='Ananas:BAAALAAECgQIBgAAAA==.Ancestor:BAAALAAECgEIAQAAAA==.Anchorpaddle:BAAALAADCgUIBQAAAA==.Anduin:BAAALAAECgMIBQAAAA==.Angrysham:BAAALAADCgEIAQAAAA==.Anxiouspally:BAAALAAECgIIAwAAAA==.',Ar='Arkwinn:BAAALAAECgMIAwAAAA==.Armee:BAAALAAECgYIBgAAAA==.Arrowedice:BAABLAAECoEUAAICAAgIohcYEABuAgACAAgIohcYEABuAgAAAA==.',As='Asmilwelme:BAAALAADCgcIBwAAAA==.Aszea:BAAALAADCgcIDQAAAA==.',Ay='Ayen:BAAALAAECgMICQAAAA==.',Ba='Baalrogg:BAAALAADCgQIBAABLAADCgYIBgABAAAAAA==.Babagooney:BAAALAAECgMIBAAAAA==.Baconlettuce:BAAALAADCgQIBAAAAA==.Badderdragon:BAAALAADCggICAAAAA==.Bahra:BAAALAADCgcIDgAAAA==.Bailmorek:BAAALAAECgMIBgAAAA==.Bangungot:BAAALAAECgUIBQABLAAFFAUICAADAHsYAA==.Bangvoker:BAACLAAFFIEIAAIDAAUIexiuAADaAQADAAUIexiuAADaAQAsAAQKgRcAAwMACAgGJbUCAC0DAAMACAgGJbUCAC0DAAQAAQjiJqIGAHQAAAAA.Barrin:BAAALAADCgcIDQAAAA==.',Be='Beastallday:BAAALAADCggIDwAAAA==.Beeski:BAAALAAECgEIAQAAAA==.Beeto:BAAALAAECgcIBwAAAA==.Best:BAAALAADCgIIAgAAAA==.',Bi='Bigbktowtr:BAEALAADCggICAABLAAECggIGQAFAM8gAA==.Bigolbkt:BAEALAAECgIIAgABLAAECggIGQAFAM8gAA==.',Bl='Bladés:BAAALAADCgcICwABLAAECgMIBAABAAAAAA==.Blâze:BAAALAAECgIIAgAAAA==.',Bo='Boberton:BAABLAAECoEVAAQGAAgIAiapAAB8AwAGAAgIAiapAAB8AwAHAAIITh+vFwDGAAAIAAMIoiJXMwCgAAAAAA==.Bolognese:BAAALAAECggIEgAAAA==.',Br='Brickeddown:BAAALAADCggIEAAAAA==.Brsp:BAAALAAECgIIAgABLAAECgMIBQABAAAAAA==.',Bu='Bucketresto:BAEALAADCgUIBQABLAAECggIGQAFAM8gAA==.Budamnk:BAAALAAECgIIAgAAAA==.Bure:BAAALAAECgcIDgAAAA==.Buzzbuzz:BAAALAAECgMIAwAAAA==.',Ca='Cadroyd:BAAALAAECgYICwAAAA==.Caelin:BAAALAAECgYICwAAAA==.Caishana:BAAALAAECgcIDwAAAA==.Calypsea:BAAALAAECgEIAQAAAA==.Cauterize:BAAALAAECgQIBQAAAA==.',Ch='Cheekswitano:BAAALAAECgMIAwAAAA==.Chopadk:BAAALAADCggICAAAAA==.Chumle:BAAALAADCgcIBwAAAA==.Chumlëy:BAAALAADCgcIBwAAAA==.Churbeast:BAAALAAECgMIBAAAAA==.',Ci='Cinderblast:BAAALAADCgIIAgAAAA==.',Co='Colomel:BAAALAADCggIEwAAAA==.Costaz:BAAALAAECgYICQAAAA==.',Cr='Craakala:BAAALAADCgcIBAAAAA==.Crimmi:BAAALAAECgIIAgAAAA==.',Cy='Cyndle:BAAALAAECgMIAwAAAA==.Cyphus:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.',Da='Daddythicc:BAAALAAECgYICgAAAA==.Dahuey:BAAALAADCggICAAAAA==.Dancetakill:BAAALAADCggICQAAAA==.Dankpal:BAAALAAECgEIAQABLAABCgMIAwABAAAAAA==.Davinki:BAAALAAECgMIAwAAAA==.',Db='Dbltap:BAAALAAECgcIDwAAAA==.',De='Deadbuz:BAAALAAECgQIBAAAAA==.Demonchocc:BAAALAADCgEIAQABLAADCgQIBAABAAAAAA==.Demondaddy:BAAALAADCgYIBgAAAA==.Deputy:BAAALAAECgMIBQAAAA==.Detritus:BAAALAAECgMIAwAAAA==.Devi:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.',Di='Dicepal:BAAALAAECgIIAgABLAAECggIFAACAKIXAA==.Dirtmonkgirt:BAAALAAECgMIBAAAAA==.Dirtnasty:BAAALAADCgcIBwAAAA==.Dirtyfish:BAAALAADCgcIDgAAAA==.Dirtysham:BAAALAAECgYIEAAAAA==.Divination:BAAALAADCggIDQAAAA==.Divinia:BAAALAADCgcICwAAAA==.',Do='Doodle:BAAALAAECgYIBgAAAA==.Doom:BAAALAADCgQIBAAAAA==.Doompockets:BAAALAAECgYICQAAAA==.Dorts:BAAALAADCgYIBgAAAA==.Downbad:BAAALAAECgcIEQAAAA==.',Dr='Dracara:BAAALAADCggIDQABLAAECgQICQABAAAAAA==.Drahseer:BAAALAAECgEIAQAAAA==.Dreadz:BAAALAAECgEIAQAAAA==.Drkdestro:BAAALAAECgcIDwAAAA==.',Du='Duadhe:BAAALAADCgMIAwAAAA==.Dusan:BAAALAAECgMIBQAAAA==.',['Dï']='Dïvinity:BAAALAADCgcIDAAAAA==.',Ea='Earthdaddy:BAAALAADCggIBgAAAA==.',Ed='Edonsian:BAAALAAECgcIDwAAAA==.',Eg='Egmont:BAAALAADCgMIAwAAAA==.',El='Elliekins:BAAALAADCgMIAwAAAA==.Elpapii:BAAALAADCgUIBgAAAA==.',En='Enoka:BAAALAAECgYIDAAAAA==.',Es='Estelá:BAAALAADCgcIBwAAAA==.',Et='Etikwa:BAAALAAECgMIAwAAAA==.',Ev='Eviline:BAAALAADCgcICAABLAAECgMIBgABAAAAAA==.Evillad:BAAALAADCgMIAwAAAA==.',Ew='Ewaboyz:BAAALAADCgMIAwAAAA==.',Fa='Fariebubbles:BAAALAADCggIFQAAAA==.Fastandis:BAAALAADCgcIBwAAAA==.',Fe='Felene:BAAALAAECgUIBwAAAA==.Fenixstraza:BAAALAAECgYIDAAAAA==.Feuvelours:BAAALAAECgcIEAAAAA==.',Fi='Fireblade:BAAALAADCgcIBwAAAA==.Firitako:BAAALAAECgEIAQAAAA==.Fistfest:BAAALAAECgMIBQAAAA==.',Fo='Fookyue:BAAALAADCgQIBAABLAADCggICAABAAAAAA==.Fourfiftysix:BAAALAAECgMIBQAAAA==.',Fr='Frankiejr:BAAALAADCgcIEAABLAAECgMIAwABAAAAAA==.Frapilicious:BAAALAAECgEIAQAAAA==.Frapss:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Frostpoptart:BAAALAAECgYICQAAAA==.',Fu='Fudruckus:BAAALAAECgYIBgAAAA==.Furball:BAAALAAECgMIAwAAAA==.',Ga='Garabashi:BAAALAAECgMIAwAAAA==.Garogog:BAAALAADCgcICQAAAA==.Gazze:BAAALAADCggIEAAAAA==.',Ge='Gertog:BAAALAAECgQIBAAAAA==.',Gi='Giggléz:BAAALAADCggIDwAAAA==.',Go='Goosehunter:BAAALAADCgEIAQAAAA==.Gooze:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Gorshot:BAAALAADCgYIBgAAAA==.',Gr='Greatvibes:BAAALAADCgYIBgAAAA==.Grid:BAAALAADCgYIBgABLAAECgYIEwABAAAAAA==.Grimmjob:BAAALAAECgMIAwAAAA==.',Gu='Guess:BAAALAAECgYICgAAAA==.',Gy='Gyat:BAAALAADCgMIAwAAAA==.',Ha='Halfagar:BAABLAAECoEVAAIJAAcIUyT8BgC9AgAJAAcIUyT8BgC9AgAAAA==.Hanyuu:BAAALAAECgYIDgAAAA==.',He='Hellbound:BAAALAAECgMICQAAAA==.Hexiann:BAAALAADCggICAAAAA==.',Hi='Hikaria:BAAALAADCgUIBQAAAA==.',Ho='Holyshirts:BAAALAADCgUIBQAAAA==.Hoofadin:BAAALAADCgYIBgAAAA==.Hotsandots:BAAALAADCgcIDQAAAA==.',Hu='Hustlenflow:BAAALAAECgEIAgAAAA==.Huñted:BAAALAADCggICAAAAA==.',Ic='Icuris:BAAALAAECgIIAgAAAA==.',Il='Ilesh:BAAALAAECgQIBAAAAA==.Ilithiya:BAAALAAECgYIBwAAAA==.Illidakkin:BAAALAADCgYIBgAAAA==.Illidrac:BAAALAAECgQICQAAAA==.',Im='Imageine:BAAALAADCgYICQAAAA==.',Is='Isaidnoice:BAAALAAECgMIBgAAAA==.Ishton:BAAALAAECgYICwAAAA==.',Iv='Ivshadow:BAAALAAECgUICQAAAA==.',Ja='Jalkayd:BAAALAADCgYIBgAAAA==.',Je='Jecka:BAAALAAECgMIAwABLAAECgMIBAABAAAAAA==.Jecthyr:BAAALAAECgMIBAAAAA==.Jenka:BAAALAAECgYIDQAAAA==.',Ji='Jinnasaiquoi:BAAALAADCggICwAAAA==.Jinncubus:BAAALAADCggICgAAAA==.',Jm='Jmoney:BAAALAADCggIFQAAAA==.',Jo='Jonrock:BAAALAADCggIGAAAAA==.Jordana:BAAALAAECgMIBAAAAA==.Jornnathan:BAAALAAECgYICgAAAA==.',Ka='Kainöa:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.Kalrathen:BAAALAAECgYICQAAAA==.Kanan:BAAALAAECgMIBAAAAA==.Karmatotem:BAAALAAECgEIAQAAAA==.Karsh:BAAALAADCggIEgAAAA==.',Kd='Kdb:BAAALAAFFAEIAQAAAA==.',Ke='Kerr:BAAALAAECgcIDwAAAA==.Keuaakepo:BAAALAAECgIIAgAAAA==.',Ki='Kickback:BAAALAAECgYIDAAAAA==.Kienne:BAAALAAECgYICQAAAA==.Kinnison:BAAALAAECggICQAAAA==.Kinomi:BAAALAADCggIBwAAAA==.Kitava:BAAALAADCgQIBAAAAA==.Kiwikitten:BAAALAADCggICAAAAA==.',Kl='Klee:BAAALAAECgQIBAAAAA==.',Kr='Kreamyumyums:BAAALAADCgYIBgAAAA==.Krethunt:BAAALAADCgcIBwAAAA==.Kryptika:BAAALAAECgYIDAAAAA==.',La='Lace:BAAALAAECgYIEwAAAA==.Lanzen:BAAALAADCggICgABLAAECgMIAwABAAAAAA==.Lanzier:BAAALAADCgMIAwABLAAECgMIAwABAAAAAA==.Larrfena:BAAALAADCgcIBwAAAA==.Lasha:BAAALAADCggICAAAAA==.',Le='Lefufu:BAAALAADCgYICwAAAA==.Lementz:BAABLAAECoEYAAIKAAgIbSG0AQDpAgAKAAgIbSG0AQDpAgAAAA==.',Li='Lillia:BAAALAAECgMIBQAAAA==.Lilyrose:BAAALAADCgEIAQAAAA==.',Lo='Locbolt:BAAALAADCggIEwAAAA==.',Lu='Luhon:BAAALAADCggIFQAAAA==.Lunaru:BAAALAAECgMIAwAAAA==.',['Lë']='Lëeloo:BAAALAADCggICAABLAAECgcIDwABAAAAAA==.',Ma='Mackjay:BAAALAAECgUIBQAAAA==.Maey:BAAALAAECgYIDAAAAA==.Magumba:BAAALAAECgMIAwAAAA==.Maktah:BAAALAAECgEIAQAAAA==.Marshboa:BAAALAADCgYIBgAAAA==.Matiks:BAAALAADCgYIDQAAAA==.Matrix:BAAALAADCgUIBQAAAA==.',Mc='Mclovinit:BAABLAAECoEdAAILAAgIbSKMBwAFAwALAAgIbSKMBwAFAwAAAA==.',Me='Megalixir:BAAALAADCgcIBwAAAA==.Mentos:BAAALAAECgQICQAAAA==.',Mi='Miikaro:BAAALAADCgYICQAAAA==.Minideath:BAAALAADCgEIAQAAAA==.Mionn:BAAALAADCggICAAAAA==.Misfire:BAAALAAECgYICAAAAA==.Mishakal:BAAALAADCgUIBQAAAA==.',Ml='Mlleena:BAAALAAECgYIDQAAAA==.',Mo='Moonkas:BAAALAADCggICAAAAA==.Moonshinenz:BAAALAADCgEIAQAAAA==.Mordythia:BAAALAADCgIIAgAAAA==.Mossfire:BAAALAAECgYICwAAAA==.',['Mà']='Màlák:BAAALAADCggICAAAAA==.',['Mø']='Møøfi:BAAALAADCgUIBQAAAA==.',['Mü']='Münir:BAAALAAECgEIAQAAAA==.',Na='Nalithor:BAAALAAECgMIBQAAAA==.Nameless:BAAALAAECgYIDAAAAA==.Narc:BAAALAADCggIDQAAAA==.Narcosis:BAAALAADCgcIBwAAAA==.Nasfurratu:BAAALAAECgYIDgAAAA==.',Ne='Neeraj:BAAALAAECgMIAwAAAA==.Nelthdracion:BAAALAADCggICAABLAAECgQICQABAAAAAA==.',Ni='Nicadema:BAAALAADCgQIBAAAAA==.',No='Norn:BAAALAAECgMIBQAAAA==.',Nu='Nunu:BAAALAAECgcICgAAAA==.',Ob='Obliverat:BAAALAADCgcIBwAAAA==.',Og='Oger:BAAALAADCggICAABLAAECggIFQAGAAImAA==.',On='Onetonnegun:BAAALAADCggIDwAAAA==.',Oz='Ozymandias:BAAALAAECgYICQAAAA==.',Pa='Pandaminium:BAAALAAECgEIAQAAAA==.Partimed:BAAALAAECgcIBwAAAA==.Partypizza:BAAALAAECgMIBgAAAA==.Pawful:BAAALAADCgcIBwAAAA==.',Pe='Pecksniffian:BAAALAADCgQIBAAAAA==.',Ph='Phoenixphyre:BAAALAADCgcIEAAAAA==.Phoennix:BAAALAAECgIIAgAAAA==.',Pi='Pisjar:BAAALAADCgcIBwAAAA==.Pivnert:BAAALAAECgMIBAAAAA==.Pixxysticks:BAAALAADCgMIAwAAAA==.',Pr='Protwheels:BAAALAAECgQIBQABLAAECgYIBgABAAAAAA==.',Pu='Purushartha:BAAALAADCgYIBgAAAA==.',['Pü']='Pünish:BAAALAADCgYIBgAAAA==.',Ra='Raeleus:BAAALAAECgIIAgAAAA==.Raevan:BAAALAAECgEIAQAAAA==.Railmoose:BAAALAADCgIIAgAAAA==.Rallek:BAAALAAECgMIBgAAAA==.Rarn:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.',Re='Reigningfury:BAAALAAECgEIAQAAAA==.Reinel:BAAALAADCgEIAQAAAA==.Remeras:BAAALAAECgEIAQAAAA==.Restoshaman:BAAALAADCgcIBwABLAAECgcIFQAJAFMkAA==.',Ri='Riken:BAAALAAECgYIBgAAAA==.',Ro='Roadi:BAAALAAECgcIDwAAAA==.Robert:BAAALAADCgcIBwAAAA==.Roshkar:BAAALAADCgYIBgAAAA==.',Ru='Rubyrod:BAAALAADCgYIBgABLAAECgcIDwABAAAAAA==.',Ry='Ryoko:BAAALAADCgcICQAAAA==.Ryvv:BAAALAAECgMIAwAAAA==.',Sa='Sabôteur:BAAALAAECgIIAgAAAA==.Sadistikshot:BAAALAAECgUICQAAAA==.Saphirá:BAAALAADCgcIBwABLAAECgcIDwABAAAAAA==.Sazoren:BAAALAADCgIIAgAAAA==.',Sh='Shadegrove:BAAALAAECgMIBwAAAA==.Shammwoww:BAAALAAECgYIDQAAAA==.Shanegillis:BAAALAADCgEIAQAAAA==.Shiftinbuz:BAAALAADCggIDQAAAA==.Shirairyu:BAAALAAECgMIAwAAAA==.Shmoopy:BAAALAADCggICAAAAA==.Shockbrokerr:BAAALAADCgcIBwAAAA==.Shyphter:BAAALAADCgcIBwAAAA==.Shàbbarankz:BAAALAAECgYICAAAAA==.Shâdôw:BAAALAADCgQIBAAAAA==.',Si='Sier:BAAALAAECgMIBAAAAA==.Sindradori:BAAALAADCgYIBgAAAA==.Sinnerman:BAAALAAECgYIDAAAAA==.Sitnspin:BAAALAADCgcIDAAAAA==.Sizzle:BAAALAADCgcICgABLAAECgMIAwABAAAAAA==.',Sl='Slamburger:BAAALAAECgYICgAAAA==.',Sm='Smokindots:BAAALAADCgcIBwABLAAECggICAABAAAAAA==.Smokintotem:BAAALAAECggICAAAAA==.Smokinvoid:BAAALAAECgYICAABLAAECggICAABAAAAAA==.Smøke:BAAALAADCgYIBgAAAA==.',Sn='Sneakyslime:BAAALAADCgcIDAAAAA==.Snowberry:BAAALAADCgcIBAAAAA==.',Sp='Spaghet:BAEBLAAECoEZAAIFAAgIzyDLBwDeAgAFAAgIzyDLBwDeAgAAAA==.',St='Stompino:BAAALAAECgQIBwAAAA==.Stormz:BAAALAAECgMIBQAAAA==.',Su='Sunblade:BAAALAAECgQIBAABLAAECgYIDAABAAAAAA==.',Sw='Swabby:BAAALAADCgcIBwAAAA==.Swift:BAAALAAECgMIAwAAAA==.Swiftdragon:BAAALAAECgUICgAAAA==.Swizzle:BAAALAAECgYIDQAAAA==.',['Sá']='Sár:BAAALAADCgcIBwAAAA==.',Ta='Tappfer:BAAALAADCgYICQABLAAECgYIDAABAAAAAA==.Tassidar:BAAALAADCgYIBwAAAA==.Taxii:BAAALAAECgYICgAAAA==.',Te='Teapots:BAAALAAECgYIDQAAAA==.',Th='Thalerys:BAAALAADCgcIBwAAAA==.Thatwarlock:BAAALAAECgYICAAAAA==.Thayelith:BAABLAAECoEVAAIMAAgIVR+UBwDAAgAMAAgIVR+UBwDAAgAAAA==.Thayer:BAAALAADCgcIBwAAAA==.Thedeus:BAAALAAECgcIEAAAAA==.Thefifth:BAAALAADCggICAAAAA==.Thelisia:BAAALAADCggIDgAAAA==.Theralendris:BAAALAAECgEIAQAAAA==.Thickarm:BAAALAAECgIIAwAAAA==.Threebeans:BAAALAAECgcIDwAAAA==.',Ti='Tiddyweaver:BAAALAADCgYICgAAAA==.',Tj='Tj:BAAALAAECgMIBQAAAA==.',Tr='Tri:BAAALAAECgMIAwAAAA==.Tristam:BAAALAAECgMIAwAAAA==.',Tu='Tuggle:BAAALAADCggIFQAAAA==.Tuneleitor:BAAALAADCgYIBgAAAA==.',Ty='Ty:BAAALAAECgYIBgAAAA==.Tyllan:BAAALAAECgcIEQAAAA==.',Un='Unholycanibl:BAAALAADCgQIBAAAAA==.',Va='Vaculao:BAAALAADCgYICAAAAA==.Vaeld:BAAALAAECgEIAQABLAAECgMICgABAAAAAA==.Valagor:BAAALAADCggICAAAAA==.Vanzen:BAAALAAECgMIAwAAAA==.Vanzer:BAAALAAECgMIAwAAAA==.Varukia:BAAALAADCgQIBAAAAA==.Vaxis:BAAALAAECgYICgAAAA==.',Vh='Vhoq:BAAALAADCgcICAAAAA==.',Vo='Voidillusion:BAAALAADCggICAAAAA==.',Wa='Warchant:BAAALAAECgYIDAAAAA==.Wazers:BAAALAADCggICAAAAA==.',We='Weave:BAAALAADCgcICAABLAAECgYIEwABAAAAAA==.Wernov:BAAALAADCggICAAAAA==.',Wh='Whodoitaunt:BAAALAAECgYIDAAAAA==.',Wi='Wichan:BAAALAAECgMIBgAAAA==.Windhashira:BAAALAAECgMIAwAAAA==.',Wo='Wondercop:BAAALAAECgMIBAAAAA==.Woodrow:BAAALAADCgMIAwAAAA==.',Xa='Xanddlock:BAAALAADCggIDwAAAA==.Xanjay:BAAALAAECgYIBgAAAA==.Xanorea:BAAALAADCgUIBQABLAAECgQIBAABAAAAAA==.',Xe='Xenocyst:BAAALAAECgMIBAAAAA==.Xeranari:BAAALAADCgcIDQAAAA==.',Xf='Xfaith:BAAALAAECgMIBAAAAA==.',Xt='Xtreme:BAAALAAECgMIAwAAAA==.',Ya='Yaoden:BAAALAAECgMICgAAAA==.Yaodin:BAAALAADCggICAABLAAECgMICgABAAAAAA==.',Ye='Yeadude:BAAALAADCggIDgAAAA==.Yes:BAAALAAECgEIAQAAAA==.',Yi='Yisoonshin:BAAALAADCgIIAgAAAA==.',Yo='Yolotli:BAAALAADCgcIBwAAAA==.',Yu='Yunsky:BAAALAADCggIDwAAAA==.',Za='Zaka:BAAALAAECgcIEQAAAA==.Zanosuke:BAAALAAECgMIAwAAAA==.Zaria:BAAALAAECgMIBQAAAA==.Zartushk:BAAALAADCgEIAQAAAA==.',Ze='Zepsh:BAAALAADCggIDQAAAA==.Zerika:BAAALAAECgEIAQAAAA==.',Zi='Zigzwag:BAAALAAECgIIAgAAAA==.',Zo='Zomgqq:BAAALAAECgYICgAAAA==.',Zy='Zync:BAAALAADCgYIBgAAAA==.',['Èe']='Èepy:BAAALAADCgYIDwAAAA==.',['És']='Éstéla:BAAALAADCgYIBwAAAA==.',['Êe']='Êepy:BAAALAAECgMIAwAAAA==.',['ßl']='ßlackøut:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end