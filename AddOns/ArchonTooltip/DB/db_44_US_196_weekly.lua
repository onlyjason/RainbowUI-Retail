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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Shaman-Restoration','DemonHunter-Vengeance','DeathKnight-Unholy','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Paladin-Holy','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Havoc',}; local provider = {region='US',realm='Silvermoon',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aamira:BAAALAADCgUIBQAAAA==.',Ab='Absolutnova:BAAALAAECgMIAwAAAA==.',Ad='Adamantus:BAAALAAECgMIBAAAAA==.Adinven:BAAALAADCgIIAgABLAADCgcIBwABAAAAAA==.Adoroladys:BAAALAADCggICgAAAA==.',Ae='Aedrion:BAAALAADCgQIBwAAAA==.Aeigris:BAAALAADCgMIAwAAAA==.Aelioran:BAAALAAECgMIAwAAAA==.Aeloni:BAAALAAECgcICgAAAA==.Aequitâs:BAAALAADCggICgAAAA==.Aerimes:BAAALAAECgMIBQAAAA==.Aethias:BAAALAAECgMIAwAAAA==.',Ag='Agothedh:BAAALAAECgUIBwAAAA==.',Ai='Airedhiel:BAAALAADCggIFgAAAA==.',Aj='Ajax:BAABLAAECoEWAAICAAgIgBqVFwA/AgACAAgIgBqVFwA/AgAAAA==.',Ak='Akumä:BAAALAAECgMIAwAAAA==.',Al='Alachia:BAAALAAECgcICgAAAA==.Alayssaria:BAAALAAECgIIAgAAAA==.Alcya:BAAALAADCgEIAQAAAA==.Alebreath:BAAALAADCgcIBwAAAA==.Aleymental:BAAALAADCggIDwAAAA==.Alixanya:BAAALAAECgEIAQAAAA==.Alltaken:BAAALAADCggIDwAAAA==.Alorvoke:BAAALAAECgMIBQAAAA==.Alphasoldier:BAAALAAECgYICQAAAA==.Altyair:BAAALAADCgQIBAAAAA==.Alverez:BAAALAADCgEIAQAAAA==.Alvya:BAAALAADCgcIEgAAAA==.Alymeria:BAAALAADCgIIAgAAAA==.Aláska:BAAALAADCgQIBAAAAA==.',Am='Amalina:BAAALAADCgUIBQAAAA==.Amillina:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.',An='Anaraellea:BAAALAAECgIIBAAAAA==.Angellena:BAAALAAECgIIBQAAAA==.Anian:BAAALAADCgUIBQAAAA==.Animositas:BAAALAAECgMIBAAAAA==.Anistong:BAAALAADCgMIAwAAAA==.Anowon:BAAALAAECgIIAgAAAA==.Antide:BAAALAADCgcICgAAAA==.',Ar='Arelaria:BAAALAADCgYIBgAAAA==.Arenar:BAAALAAECgcIEAAAAA==.Aresion:BAAALAADCgcIBwABLAAECgcICwABAAAAAA==.Arillian:BAAALAADCgcIBwAAAA==.Arkelium:BAAALAAECgQICAAAAA==.Armagedda:BAAALAAECgEIAQAAAA==.Aronau:BAAALAAECgEIAQAAAA==.Arthace:BAAALAADCgMIAwAAAA==.',As='Asche:BAAALAAECgYICgABLAAECgcICwABAAAAAA==.Asenath:BAAALAAECgMIAwAAAA==.Askec:BAAALAADCggIDwAAAA==.',Au='Auril:BAAALAADCgIIAgAAAA==.Ausiris:BAAALAADCgYIBgABLAADCgQIBAABAAAAAA==.',Av='Avacado:BAAALAAECgUIBQAAAA==.',Az='Azaezel:BAAALAAECgYICQAAAA==.',['Aß']='Aßomination:BAAALAADCgMIAwAAAA==.',['Aê']='Aêlin:BAAALAAECgEIAQAAAA==.',Ba='Babychewie:BAAALAAECgIIBAAAAA==.Balla:BAAALAAECgQICAAAAA==.Bambiteressa:BAAALAAECgIIBAAAAA==.',Be='Beardeman:BAAALAAECgIIBAAAAA==.Beaross:BAAALAADCgIIAgABLAAECgcIEAABAAAAAA==.Beefshock:BAAALAAECgIIBAAAAA==.Beezchurger:BAAALAAECgMIBQAAAA==.Berarrek:BAAALAADCggIFgAAAA==.Bethny:BAAALAADCgcIBwAAAA==.Betternixx:BAAALAAECggICgAAAA==.',Bi='Bigbucees:BAAALAAECgMIAwAAAA==.Bigeasy:BAAALAAECgEIAQAAAA==.Birdie:BAAALAAECgMIAwAAAA==.',Bl='Blazied:BAAALAADCgMIAwAAAA==.Blindlorcet:BAAALAADCgYIBgAAAA==.Blitzkriege:BAAALAAECgIIAwAAAA==.Blitzo:BAAALAAECgEIAgAAAA==.Blkmagic:BAAALAADCgcIDQAAAA==.Bluex:BAAALAAECgIIAgAAAA==.',Bo='Bocnore:BAAALAADCgEIAQAAAA==.Bombad:BAAALAAECgEIAQABLAAECgcIEwABAAAAAQ==.Bonelargeles:BAAALAAECggIAQAAAA==.Booyaah:BAACLAAFFIEGAAIDAAMI6hQhAgDxAAADAAMI6hQhAgDxAAAsAAQKgRcAAgMACAhcI9EBABgDAAMACAhcI9EBABgDAAAA.Borb:BAAALAAECgMIAwAAAA==.Botany:BAAALAAECgMIAwAAAA==.Bowolf:BAAALAAECgYIDAAAAA==.Boxstuffer:BAAALAAECgMIAwAAAA==.',Br='Braviel:BAAALAAECgIIAwAAAA==.Brelis:BAAALAADCgcIDAAAAA==.Brigadester:BAAALAAECggIEQAAAA==.Brighthands:BAAALAAECgYICQAAAA==.Broodin:BAAALAAECgIIAgAAAA==.Brôk:BAAALAADCggIDgAAAA==.',Bu='Bunnybringer:BAAALAADCgcICAAAAA==.Bunzasteel:BAAALAAECgMIAwAAAA==.Burritorukh:BAAALAADCggICgAAAA==.',['Bó']='Bób:BAAALAADCgYICwAAAA==.',Ca='Caladium:BAAALAAECgUICAAAAA==.Calrisa:BAAALAAECgEIAQAAAQ==.Carameldropz:BAAALAADCgYIBgAAAA==.Carthkin:BAAALAAECgIIAgAAAA==.Cassahunt:BAAALAAECgMIAwAAAA==.Cassawings:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Cathedral:BAAALAADCgUICQAAAA==.Catofwisdom:BAAALAAECgIIAgAAAA==.',Ce='Celna:BAAALAADCgcIEgAAAA==.Cerb:BAAALAAECgMIBgAAAA==.Ceris:BAAALAAECgEIAQAAAA==.Cernos:BAAALAAECgEIAQAAAA==.',Ch='Chance:BAAALAAECgcIEAAAAA==.Cheezit:BAAALAAECgEIAQAAAA==.Chilleagle:BAAALAADCggIFQAAAA==.Chillidann:BAAALAADCgEIAQABLAAECgQIDQABAAAAAA==.Chokeher:BAAALAADCgUIBQAAAA==.Chootybeeks:BAAALAAECgEIAQAAAA==.Chronobog:BAAALAAECgQICAAAAA==.',Ci='Cinderson:BAAALAAECgQIBAAAAA==.Cirílla:BAAALAADCgYIBgAAAA==.',Cl='Clockwork:BAAALAAECgcIEQAAAA==.Clömp:BAAALAAECgUIBwAAAA==.',Co='Cocoa:BAAALAADCgYIBgAAAA==.Coconuts:BAAALAADCgcIBwAAAA==.Coldfire:BAAALAADCgcICwAAAA==.Coli:BAAALAADCgMIAwAAAA==.Cosmas:BAAALAADCgIIAgAAAA==.Costanza:BAAALAADCgYIBgAAAA==.Cousìn:BAAALAADCggIBQAAAA==.Cowabungha:BAAALAADCggIEQAAAA==.Cowhide:BAAALAAECgIIAgAAAA==.',Cr='Crakki:BAAALAAECgUIBwAAAA==.Crimsonchaos:BAAALAADCgcIDQAAAA==.Cronuz:BAAALAAECgIIAwAAAA==.Crooton:BAAALAAECgMICAAAAA==.',Cy='Cyphris:BAAALAAECgUIBQAAAA==.Cyrick:BAAALAADCgMIAwAAAA==.',['Cé']='Cérnunnos:BAAALAAECgIIBAAAAA==.',Da='Daeledis:BAAALAADCgYIBgAAAA==.Daemonslayer:BAAALAAECgEIAQAAAA==.Daftknight:BAAALAAECgUIBwAAAA==.Dahamburgler:BAAALAAECgUIBQAAAA==.Daisycutter:BAAALAAECgYIBwAAAA==.Dakuta:BAAALAAECgIIAgAAAA==.Dalir:BAAALAADCgIIAgABLAAECgYIDgABAAAAAA==.Dances:BAAALAAECgMIBAAAAA==.Dangereus:BAAALAAECgMIBQAAAA==.Darach:BAAALAAECgEIAQAAAA==.Darklightt:BAAALAAECgIIAgAAAA==.Darmorg:BAAALAAECgYICQAAAA==.Daskapital:BAAALAAECgQICQAAAA==.Dawnslight:BAAALAAECgMIBAAAAA==.Daxxhoof:BAAALAADCggICAAAAA==.',De='Deadrukh:BAAALAADCggICAAAAA==.Deathreigns:BAAALAADCgcIBwAAAA==.Decayaven:BAAALAADCgIIAgAAAA==.Decymel:BAAALAAECgIIAgAAAA==.Deegoddaem:BAAALAAECgIIAwAAAA==.Deffugly:BAAALAADCgYIBwAAAA==.Delamaze:BAAALAADCgcIBwABLAAECgUICgABAAAAAA==.Delmore:BAAALAAECgQIBAABLAAECgUICgABAAAAAA==.Delmoré:BAAALAAECgUICgAAAA==.Delys:BAAALAADCgcICQAAAA==.Desetra:BAAALAADCgEIAQAAAA==.Devile:BAAALAADCgQIBAAAAA==.Devoutraven:BAAALAAECgUICQAAAA==.',Di='Dilliheal:BAAALAADCgEIAQABLAAECggIFwAEAGkiAA==.Diskrt:BAAALAAECgIIAwAAAA==.Dixonciderr:BAAALAAECgcIDwAAAA==.',Do='Dodgeram:BAAALAADCgcIEAAAAA==.Dolarito:BAAALAADCggIEQAAAA==.Donny:BAAALAAECgEIAQAAAA==.Donnybrook:BAAALAADCgEIAQAAAA==.Dootie:BAAALAADCgYIBgAAAA==.',Dr='Dragongor:BAAALAAECgMIBAAAAA==.Dravv:BAAALAADCgEIAQAAAA==.Druirhen:BAAALAAECgIIAgAAAA==.',Du='Durgal:BAAALAADCgQIBAAAAA==.',Dw='Dweedy:BAAALAADCggIFgAAAA==.',Ea='Earlgreyhot:BAAALAAECgEIAQABLAAECgcIDQABAAAAAA==.',Ec='Ecnarol:BAAALAADCggICwAAAA==.',El='Eliyana:BAAALAAECgMIAwAAAA==.Elsiñd:BAAALAAECgMIAwAAAA==.',Em='Emberdk:BAABLAAECoEXAAIFAAgIuR/XAwCjAgAFAAgIuR/XAwCjAgAAAA==.',Ep='Ephram:BAAALAADCggIEAABLAAECgcIEAABAAAAAA==.Ephysa:BAAALAADCgMIAwAAAA==.',Es='Essenne:BAAALAADCgYICAABLAAECgIIAgABAAAAAA==.',Eu='Eunos:BAAALAAECgcIEAAAAA==.',Ev='Evokepk:BAAALAADCggICwABLAAECgIIAgABAAAAAA==.',Ey='Eyeholeman:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.',Ez='Eziekeile:BAAALAADCggICQAAAA==.Ezzrra:BAAALAAECgUIBwAAAA==.',Fa='Faillock:BAAALAAECgcIEwAAAA==.Fallenshaman:BAAALAADCgUIBgAAAA==.Falora:BAAALAADCggIFgAAAA==.Fangshot:BAAALAAECgYIBgAAAA==.',Fe='Fearce:BAAALAADCgcIBwAAAA==.Feartheaxe:BAAALAAECgEIAQAAAA==.Felreaper:BAAALAADCgcIEgAAAA==.Fengbao:BAAALAAECgIIAgAAAA==.',Fh='Fhenor:BAAALAADCgcIDAABLAAECgYIDgABAAAAAA==.',Fi='Filthydegén:BAAALAAECgYICwAAAA==.Finnior:BAAALAADCgYIBgAAAA==.Firevoid:BAAALAADCgcIDAAAAA==.Fisheye:BAAALAADCgcICAAAAA==.Fishspells:BAAALAAECgEIAQAAAA==.',Fl='Flitwoot:BAAALAADCgUICAAAAA==.Fluffs:BAAALAADCgYIBgABLAAECgUIBQABAAAAAA==.',Fr='Franky:BAAALAAECgIIAgAAAA==.Frazil:BAAALAAECgYIDQAAAA==.Frogprincess:BAAALAAECgEIAQAAAA==.Frontdeboeuf:BAAALAAECgMIBAAAAA==.Fruitsalad:BAAALAAECgIIBAAAAA==.Fródo:BAAALAADCggICQAAAA==.Fröstyflakes:BAAALAADCgcIBwAAAA==.',Fu='Funneris:BAABLAAFFIEFAAIGAAMI6hbZAQARAQAGAAMI6hbZAQARAQAAAA==.Fuzzynippz:BAAALAADCggIDgAAAA==.',Fy='Fyz:BAAALAADCgQIBQAAAA==.',Ga='Gadios:BAABLAAECoEXAAIEAAgIaSJ/AQADAwAEAAgIaSJ/AQADAwAAAA==.Gaivnion:BAAALAADCggICwAAAA==.Gamba:BAAALAAECgYIDQAAAA==.Ganjcrusader:BAAALAADCgcIDAAAAA==.Gazania:BAAALAAECgEIAQAAAA==.',Ge='Geayd:BAAALAADCgMIAwAAAA==.Getlucky:BAAALAAECgEIAQAAAA==.',Gh='Ghemanis:BAAALAADCggIFgAAAA==.',Go='Goobr:BAAALAAECgMIBAAAAA==.Goover:BAAALAAECgEIAQAAAA==.Gozer:BAAALAADCgYICQAAAA==.',Gr='Gracelyn:BAAALAAECgMIAwAAAA==.Grafvitnir:BAAALAAECgEIAQAAAA==.Grenne:BAAALAAECgMIAwAAAA==.Greyman:BAAALAADCggIFgAAAA==.Grezgara:BAAALAAECgMIBAAAAA==.Grimoldone:BAAALAAECgEIAQAAAA==.Grinderrg:BAAALAAECgUIBQAAAA==.Grumbledore:BAAALAAECgcIEwAAAA==.',Gu='Gumbö:BAAALAADCgcIBwAAAA==.Gutsz:BAAALAADCgcICgAAAA==.Guttzes:BAAALAADCgQIBQAAAA==.',Gw='Gweb:BAAALAADCggICAAAAA==.',['Gü']='Gülden:BAAALAADCgIIAgAAAA==.',Ha='Hafthor:BAAALAAECgMIBQAAAA==.Haills:BAAALAADCgUIBQAAAA==.Hajpala:BAAALAADCgUIBQAAAA==.Hakzol:BAAALAAECgQIBQAAAA==.Halea:BAAALAADCgcIDgAAAA==.Hankel:BAAALAADCgcIBwAAAA==.Hardunkichud:BAAALAAECgYICQAAAA==.Harpactira:BAAALAADCggIDwAAAA==.Hautsauce:BAAALAADCgYIBgAAAA==.',He='Heartbrkr:BAAALAAECgYICQAAAA==.Heg:BAAALAADCgYIBgABLAAECgYIDwABAAAAAA==.Hegs:BAAALAAECgYIDwAAAA==.Helaku:BAAALAAECggIEAAAAA==.Heneru:BAAALAADCgQIBQAAAA==.Hentaisuccs:BAAALAADCgUIBwAAAA==.Hevharuk:BAAALAAECgMIAwAAAA==.Hewk:BAAALAAECgIIBAAAAA==.',Hi='Hideabull:BAAALAADCgQIBAABLAAECgMIBwABAAAAAA==.Hidetsugu:BAAALAADCgcIBwAAAA==.',Ho='Holdrock:BAAALAADCgUIBQAAAA==.Holylily:BAAALAADCgMIAwAAAA==.Holymoo:BAAALAAECgIIAgAAAA==.',Hu='Hudsonpally:BAAALAADCgYIBgAAAA==.Huevudo:BAAALAADCgUIAgAAAA==.Hunskaar:BAAALAAECgIIAwAAAA==.',Hy='Hybris:BAAALAADCggIEAAAAA==.',Ia='Iamapriest:BAAALAADCgcIBwAAAA==.Iamsin:BAAALAADCgcICQAAAA==.',Ic='Icul:BAAALAADCgEIAQAAAA==.',Ig='Ignorant:BAAALAAECgIIAwAAAA==.',Ih='Iheartmelee:BAAALAAECgEIAQAAAA==.Ihra:BAAALAADCgYICgAAAA==.',Il='Illidòrk:BAAALAADCgMIAwAAAA==.',Im='Impasta:BAAALAAECgIIAgAAAA==.Impmama:BAAALAAECgYIBwAAAA==.Imroflcopter:BAAALAADCggICwAAAA==.',In='Incredible:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Indil:BAAALAAECgQIBAAAAA==.Intet:BAAALAADCgUIBQAAAQ==.',Is='Isaria:BAAALAAECgMIAwAAAA==.Isindril:BAAALAAECgcIEAAAAA==.Isnacky:BAAALAAECgIIAwAAAA==.',Ja='Jackforever:BAAALAADCgQIBAAAAA==.Jadianrogue:BAAALAAECgYIDgAAAA==.Jambalaya:BAAALAAECgMIBAAAAA==.Jameswarren:BAAALAADCgcIEAAAAA==.Jannik:BAAALAAECggIEgAAAA==.',Je='Jenntly:BAAALAAECgUIBQABLAAECgUICwABAAAAAA==.',Ji='Jigi:BAAALAAECgYIDgAAAA==.Jirasia:BAAALAAECgcIEAAAAA==.Jiynx:BAAALAADCgYIBgAAAA==.',Jj='Jjmmaarrtt:BAAALAAECgMIBgAAAA==.',Jo='Joedamonk:BAAALAAECgMIAwAAAA==.Jolane:BAAALAADCgcICAAAAA==.Joystick:BAAALAAECgYIBwAAAA==.',Ka='Kaelsthus:BAAALAADCgUIBQAAAA==.Kagaiyoshi:BAAALAADCgQIBAAAAA==.Kageriyu:BAAALAAECggIEQAAAA==.Kaleiel:BAAALAADCggICAAAAA==.Kamishiro:BAAALAAECgUIBwAAAA==.Kanofel:BAAALAADCggIDgABLAAECgEIAQABAAAAAA==.Kanoslice:BAAALAADCgcIDQABLAAECgEIAQABAAAAAA==.Kanosmash:BAAALAADCgYICwABLAAECgEIAQABAAAAAA==.Kanowrath:BAAALAAECgEIAQAAAA==.Karldawgron:BAAALAADCgcIBwAAAA==.Katrianna:BAAALAADCgUIBwAAAA==.Kayla:BAAALAAECgMIBAAAAA==.',Ke='Keatøn:BAAALAAECgEIAQAAAA==.Kelethius:BAAALAAECgcIEAAAAA==.Kerelenn:BAAALAAECgIIAgAAAA==.Kesthus:BAAALAAECgYIBwAAAA==.Keystonelite:BAAALAAECgcIEAAAAA==.',Kh='Khatrina:BAAALAADCgIIAgAAAA==.',Ki='Kieser:BAAALAADCgcIBwAAAA==.Killerpally:BAAALAADCgcIEAAAAA==.Killerpkz:BAAALAADCgUIBQAAAA==.Killerzdk:BAAALAADCgcIDgABLAAECgIIAgABAAAAAA==.Kirela:BAAALAADCggIDgAAAA==.Kirkitin:BAAALAADCgMIAwAAAA==.',Kl='Klaustralus:BAAALAAECgMIBAAAAA==.',Kr='Kritneyfears:BAAALAADCgMIAwAAAA==.',Ku='Kurîgunde:BAAALAADCgcIDAAAAA==.',['Kà']='Kàylee:BAAALAAECgEIAQAAAA==.',['Ká']='Káel:BAAALAADCgUIBQAAAA==.',La='Lagaris:BAAALAAECgEIAQAAAA==.Lanararia:BAAALAAECgMIBwAAAA==.Landregorn:BAAALAAECggIBgAAAA==.Largeavian:BAAALAAECgEIAgAAAA==.Lazyestpanda:BAAALAAECgYIDgAAAA==.',Ld='Ldycathlyn:BAAALAADCgcIBwAAAA==.',Le='Leande:BAAALAADCgYIBwAAAA==.Leesy:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Leesylock:BAAALAAECgEIAQAAAA==.Legma:BAABLAAECoEVAAIHAAgIiCJXBQARAwAHAAgIiCJXBQARAwAAAA==.Lemoncitrus:BAAALAAECgYICQAAAA==.Lerbin:BAAALAAECgIIBAAAAA==.Levyan:BAAALAAECgIIBAAAAA==.',Li='Libnorathis:BAAALAAECgMIBQAAAA==.Licheternal:BAAALAAECgUICwAAAA==.Lightwolves:BAABLAAECoEWAAQIAAgI0SH3AwCgAgAIAAcIECL3AwCgAgACAAcI0xn7KQDGAQAJAAYIkBYfFQCOAQAAAA==.Lilin:BAAALAADCggIBwAAAA==.Lilynuts:BAAALAAECgYICQAAAA==.Littlebitter:BAAALAAECggIAQAAAA==.',Ll='Llirc:BAAALAADCgcIEQAAAA==.',Lo='Lockwar:BAAALAADCgUIBwAAAA==.Lonag:BAAALAADCgcICwAAAA==.Loony:BAAALAAECgIIBAAAAA==.Lovelydeäth:BAAALAAECgcIEAAAAA==.',Lu='Lunabel:BAAALAADCggICgAAAA==.',['Là']='Làmp:BAAALAAECgYIBwAAAA==.',['Lé']='Léf:BAAALAAECgMIAwAAAA==.',['Lø']='Lø:BAAALAAECgYICQAAAA==.',Ma='Madussa:BAAALAADCgYIBwAAAA==.Magelethius:BAAALAAECgUIBQAAAA==.Magestika:BAAALAAECgYICQAAAA==.Maimgor:BAAALAAECgMIBAAAAA==.Makellos:BAAALAAECgEIAQAAAA==.Malgainas:BAAALAADCgcIBwAAAA==.Mamamaya:BAAALAAECgQIBwAAAA==.Marbgar:BAAALAADCggICAAAAA==.Maricit:BAAALAAECgMIBAAAAA==.Marnard:BAAALAADCgMIAwABLAAECgMIBwABAAAAAA==.Mathirran:BAAALAAECgcIBwAAAA==.Mattedemon:BAAALAADCggICAAAAA==.Mavralara:BAAALAAECgIIBAAAAA==.Maxious:BAAALAAECgYICQAAAA==.',Mc='Mcfrown:BAAALAAECgQIDQAAAA==.',Me='Meditation:BAAALAAECgIIAgAAAA==.Mellana:BAAALAADCggIDwABLAAECgMIAwABAAAAAA==.Melvin:BAAALAADCgEIAQAAAA==.Mephestoe:BAAALAAECggIAQAAAA==.Merloc:BAAALAAECgMIBAAAAA==.Metortun:BAAALAADCgcIDgAAAA==.',Mi='Michiro:BAAALAADCgcICgAAAA==.Minglingpo:BAAALAADCgUIBQAAAA==.Mingwon:BAAALAADCgYIBgAAAA==.Minusfifty:BAAALAADCgYIBwAAAA==.Miranai:BAAALAAECgYICwAAAA==.Mirima:BAAALAAECgMIBQAAAA==.Miserablle:BAAALAADCggIEwAAAA==.Mishona:BAAALAAECgMIBAAAAA==.Missteak:BAAALAADCggICAAAAA==.Mizard:BAAALAAECgQIBQAAAA==.',Mo='Molly:BAAALAADCgcIDgAAAA==.Monkgiatzo:BAAALAADCgYIBgAAAA==.Moob:BAAALAAECgUIBwAAAA==.Moong:BAAALAAECgUICAAAAA==.Moonlitgrove:BAAALAADCgUIBQAAAA==.Morees:BAAALAAECgQICAAAAA==.Moroi:BAAALAAECgMIAwAAAA==.Mowzbyte:BAAALAADCgYIBgAAAA==.',Ms='Mstrjamus:BAAALAADCggIDwAAAA==.Mstrjonathan:BAAALAADCggIEAAAAA==.',Mu='Muffinn:BAAALAAECgEIAQAAAA==.Mustybones:BAAALAAECgYICgAAAA==.Mustärd:BAAALAAECgcICAAAAA==.',My='Myree:BAAALAAECgYICgAAAA==.Mytie:BAAALAAECgMIAwAAAA==.',['Mì']='Mìlfmänor:BAAALAADCgcIEAABLAAECgEIAQABAAAAAA==.',['Mó']='Mómo:BAAALAADCgcICQAAAA==.',Na='Nacola:BAAALAADCgIIAgAAAA==.Nahimahu:BAAALAAECgIIBAAAAA==.Naks:BAAALAAECggIDQAAAA==.Nalaria:BAAALAAECgYIBgAAAA==.Nashwa:BAAALAADCggIBAAAAA==.Nastiee:BAAALAAFFAIIAgAAAA==.',Ne='Nechrolous:BAAALAADCgMIAwAAAA==.Neonrabbit:BAAALAAECgYICQAAAA==.',Ng='Ngorongoro:BAAALAADCgcIEgAAAA==.',Ni='Niesse:BAAALAADCggIDwAAAA==.Nightæres:BAAALAAECgcICwAAAA==.Ninjakitten:BAAALAAECgMIBAAAAA==.',No='Noctisse:BAAALAAECgEIAQAAAA==.Noiscopiamo:BAAALAAECgIIAgAAAA==.Nojustice:BAAALAADCgMIAwAAAA==.Nondoctor:BAAALAAECgMIAwAAAA==.Novamage:BAAALAADCggIGAABLAAECgMIAwABAAAAAA==.',Nu='Nualpriest:BAAALAADCgQIBAABLAAECgIIAwABAAAAAA==.Nualzie:BAAALAADCggIDwABLAAECgIIAwABAAAAAA==.',Ny='Nyxrammus:BAAALAADCggIDwAAAA==.',Oa='Oashian:BAAALAAECgcIDQAAAA==.',Od='Oddmaen:BAAALAADCgcIBgAAAA==.Odonts:BAAALAAECggIBQAAAA==.',On='Onesummon:BAAALAADCgcIBwAAAA==.Onoodles:BAAALAAECgIIAgAAAA==.',Oo='Oopslock:BAAALAADCgcIBwAAAA==.',Or='Orrindan:BAAALAAECgUICAAAAA==.',Ow='Ownlyfans:BAAALAADCgQIBwAAAA==.',Ox='Oxblade:BAAALAAECgQIBAAAAA==.',Pa='Paladinæres:BAAALAADCggIDgABLAAECgcICwABAAAAAA==.Pallieguy:BAAALAAECgMIBAAAAA==.Palmoni:BAAALAAECgMIAwAAAA==.Pandà:BAAALAADCggICAAAAA==.Pathadille:BAAALAAECgUIBgAAAA==.',Pe='Peachtea:BAAALAADCgYIBgAAAA==.Penalize:BAAALAAECgcIDQAAAA==.Penalty:BAAALAADCgMIAwABLAAECgcIDQABAAAAAA==.Penetrate:BAAALAADCgcIBwABLAAECgcIDQABAAAAAQ==.Pepehands:BAAALAAECgEIAQAAAA==.Pernott:BAAALAADCggIDgAAAA==.Persëphöne:BAAALAAECggIEwAAAA==.',Ph='Phalopathy:BAAALAADCgQIBAAAAA==.Pharoahe:BAAALAADCgQIBAABLAAECgcIEAABAAAAAA==.Phett:BAAALAAECgMIBAAAAA==.Philippe:BAAALAADCggIFwAAAA==.Philo:BAAALAAECgYICQAAAA==.Phistacuffz:BAAALAAECgEIAQAAAA==.Phistonk:BAAALAADCgIIAgAAAA==.Phormere:BAAALAAECgEIAQAAAA==.',Pi='Pikkin:BAAALAAECgIIBAAAAA==.',Pl='Plaidpally:BAAALAAECgMIAwAAAA==.Platînum:BAAALAAECgUIBQAAAA==.',Po='Postmortim:BAAALAAECgIIBAAAAA==.',Ps='Psaitama:BAAALAADCgcIBwAAAA==.',Pu='Pu:BAAALAAECgIIAgAAAA==.',Py='Pyrose:BAAALAAECgEIAQAAAA==.',['Pé']='Pérséphone:BAAALAAECgEIAQAAAA==.',Qi='Qiteag:BAAALAADCggICQABLAAECgYICAABAAAAAA==.',Ql='Qlceanglóra:BAAALAAECgEIAQABLAAECgYICAABAAAAAA==.',Qu='Quintessence:BAAALAADCgcIDQABLAAECgYICAABAAAAAA==.',Qw='Qwivers:BAAALAAECgYIEgAAAA==.',Qz='Qzymandia:BAAALAAECgYICAAAAA==.Qzymandias:BAAALAADCggICAABLAAECgYICAABAAAAAA==.',Ra='Raiset:BAAALAAECgEIAgAAAA==.Raithlyn:BAAALAAECgIIBAAAAA==.Ralar:BAAALAADCgYIBgAAAA==.Ralk:BAAALAADCgYIBgAAAA==.Rambling:BAAALAAECgUICAAAAA==.Raspuutin:BAAALAADCggIEwAAAA==.Ratchét:BAAALAADCgMIAwAAAA==.Rawrm:BAAALAAECgMIBAAAAA==.Razormage:BAAALAAECgMIBAAAAA==.Razorsummit:BAAALAAECgIIAgAAAA==.',Re='Rekko:BAAALAAECgYICQAAAA==.Remidee:BAAALAADCgEIAQAAAA==.Remoria:BAAALAADCgcIBwAAAA==.Rewan:BAAALAADCgYIBgAAAA==.',Rh='Rhandato:BAAALAADCggIFgAAAA==.Rhaênys:BAAALAAECgIIAgAAAA==.Rhen:BAAALAADCggIEAAAAA==.Rhonna:BAAALAAECgMIBAAAAA==.',Ri='Riceria:BAAALAAECgIIAgAAAA==.Riduckulous:BAAALAAECgcIEAAAAA==.Rigö:BAAALAADCgMIAwAAAA==.Rizon:BAAALAAECgEIAQAAAA==.',Ro='Rocklee:BAAALAAECgMIAwAAAA==.Roguepk:BAAALAADCgcIDAABLAAECgIIAgABAAAAAA==.Rokushakubo:BAAALAADCgIIAgAAAA==.Rollis:BAAALAAECgEIAQAAAA==.Roselyne:BAAALAADCgYIBgAAAA==.',Ru='Rusâ:BAAALAAECgMIBAAAAA==.',Sa='Saandz:BAAALAADCgEIAQAAAA==.Sabyne:BAAALAAECgMIAwAAAA==.Sadala:BAAALAADCgcIBwAAAA==.Sagerae:BAAALAADCggIDQAAAA==.Salvon:BAAALAADCgIIBAAAAA==.Sandz:BAAALAAECgIIAgAAAA==.Sane:BAAALAAECgEIAQAAAA==.Sanlien:BAAALAAECgYICQAAAA==.Sarif:BAAALAADCgcIEAAAAA==.Sarra:BAAALAADCgYIBgAAAA==.Sarztra:BAAALAADCgQIBAAAAA==.Sathist:BAAALAAECgMIAwAAAA==.Satisfactree:BAAALAAECgcIDQAAAA==.Satriany:BAAALAADCggICwAAAA==.Satsa:BAAALAAECgcIDAAAAA==.Sauruman:BAAALAAECgMIBgAAAA==.Saushie:BAAALAADCgcIBwAAAA==.Savagedoodle:BAAALAAECgYIEQAAAA==.',Sb='Sbturq:BAAALAADCgcICQAAAA==.',Se='Seidhra:BAAALAAECgUICAAAAA==.Selalure:BAAALAADCgYIBgABLAAECgYIDgABAAAAAA==.Selianas:BAAALAADCggICAAAAA==.Seriola:BAAALAAECgEIAQAAAA==.Seriuspal:BAAALAADCggIDQAAAA==.Seykai:BAAALAAECgIIAgAAAA==.Seyton:BAAALAAECgIIAgAAAA==.',Sg='Sgtdoom:BAAALAAECgEIAQAAAA==.',Sh='Sh:BAAALAADCgQIBAAAAA==.Shalash:BAAALAADCgIIAgAAAA==.Shamanlfg:BAAALAADCggIEAAAAA==.Shattery:BAAALAADCgEIAQABLAAECggICgABAAAAAA==.Shedog:BAAALAADCgMIAwAAAA==.Sheldren:BAAALAAECgIIAgAAAA==.Shindra:BAAALAADCggIDwAAAA==.Shivrael:BAAALAADCgcIFQAAAA==.Shockher:BAAALAADCgcICAAAAA==.Shockrock:BAAALAAECgYIBwAAAA==.Shockteryx:BAAALAADCgcIBwAAAA==.Shootnloot:BAAALAAECgYICAAAAA==.',Si='Sicksshaman:BAAALAAECgYICQAAAA==.Siene:BAAALAADCgMIAwAAAA==.Sifusplitter:BAAALAAECgUICAAAAA==.Silliya:BAAALAADCggICAAAAA==.Silvernightz:BAAALAADCggIEwAAAA==.Sinbreaker:BAAALAAECgMIBgAAAA==.Sindreamer:BAAALAAECgIIAgAAAA==.Sisterlily:BAAALAADCggICAAAAA==.',Sk='Skinamarink:BAAALAAECgMIBAAAAA==.',Sl='Slasherous:BAAALAADCgcIBwAAAA==.Slyvek:BAAALAADCgMIAwAAAA==.',Sm='Smookin:BAAALAADCgUIBQAAAA==.',So='Sodem:BAAALAAECgMIBAAAAA==.Soepic:BAAALAAECggIEAAAAA==.Sollixx:BAAALAAECgMIBAAAAA==.Song:BAAALAADCgcIDgAAAA==.Sorthal:BAAALAADCgcIBwAAAA==.Soursops:BAAALAADCggICAAAAA==.',Sp='Spellbraker:BAAALAAECgUIBwAAAA==.Sphyxia:BAAALAAECgIIBAAAAA==.',St='Staark:BAAALAADCggICQABLAAECgYIDQABAAAAAA==.Stackss:BAAALAADCgQIBAAAAA==.Staffinabox:BAAALAAECgYICQAAAA==.Stairwell:BAAALAADCgcIBwAAAA==.Starburstz:BAAALAAECgEIAQAAAA==.Starknight:BAACLAAFFIEFAAICAAMImg5uAgD1AAACAAMImg5uAgD1AAAsAAQKgRcAAgIACAjoIZ0MALgCAAIACAjoIZ0MALgCAAAA.Stinkywinkys:BAAALAAECgIIAgAAAA==.Stiorra:BAAALAAECgMIBQAAAA==.Stonelock:BAAALAAECgMIAwAAAA==.Stonequake:BAAALAAECgIIAgAAAA==.Streamline:BAAALAAECgUIBwAAAA==.',Su='Sung:BAAALAADCgQIBAAAAA==.',Sv='Svelis:BAAALAADCgcIDgAAAA==.',Sw='Swagnasty:BAAALAAECgMIAwAAAA==.',Sy='Sylera:BAAALAADCgYIBgAAAA==.Syllvanis:BAAALAADCgEIAQAAAA==.Sylphistra:BAAALAAECgEIAQAAAA==.Sylvanasn:BAAALAAECgYIBwAAAA==.Sylvanäs:BAAALAADCggIDwAAAA==.Symsol:BAAALAAECgQIBwAAAA==.Syyn:BAAALAADCgUIBQAAAA==.Syzuurp:BAAALAADCgEIAQAAAA==.',['Sç']='Sçout:BAAALAAECgEIAQAAAA==.',Ta='Tacis:BAAALAADCgEIAQAAAA==.Tacocrusher:BAAALAADCgcIEgAAAA==.Takalion:BAAALAADCggIBgAAAA==.Taleya:BAAALAAECgYICgAAAA==.Tanarael:BAAALAADCgQIBAAAAA==.Tarryn:BAAALAADCggIFgAAAA==.Tastetest:BAAALAADCgIIAgAAAA==.',Te='Teahupoo:BAAALAADCggIFgAAAA==.Temorone:BAAALAADCggIDwAAAA==.Teross:BAAALAAECgcIEAAAAA==.Terribella:BAAALAADCgcICwABLAAECgIIAwABAAAAAA==.Terrorblades:BAAALAAECgMIAwABLAAECgcIEAABAAAAAA==.Tevye:BAAALAAECgYICQAAAA==.',Th='Thaco:BAAALAADCgMIAwAAAA==.Thard:BAAALAAECgIIAgABLAAECggIFQAHAIgiAA==.Thautama:BAAALAAECgIIAgAAAA==.Thorielan:BAAALAADCgQIBAABLAADCggIDwABAAAAAA==.Thornlox:BAAALAAECgMIBAAAAA==.Thoruulian:BAAALAADCgcIBwAAAA==.',Ti='Tikdotlock:BAAALAAECgEIAQAAAA==.Tiktik:BAAALAAECgYICgAAAA==.Tiktikmage:BAAALAADCgIIAgAAAA==.',To='Tolt:BAAALAADCgQIBAAAAA==.Tomioka:BAAALAADCgcIBwAAAA==.Tomorow:BAAALAADCgMIAwAAAA==.Torvall:BAAALAADCgUICAAAAA==.Tototl:BAAALAAECgIIAwAAAA==.',Tr='Trance:BAAALAADCgcIBwABLAADCggIFQABAAAAAA==.Trapped:BAAALAADCgEIAQABLAAECgcIEAABAAAAAA==.Treeforce:BAAALAAECgQIBgAAAA==.Trelious:BAAALAAECgYICQAAAA==.Trianorne:BAAALAAECgIIAgAAAA==.Tríxie:BAAALAADCggICAAAAA==.Tróll:BAAALAADCgYIBgAAAA==.',Tu='Turumbar:BAAALAAECgMIAwAAAA==.',Tx='Txcrazyhorse:BAAALAAECgEIAQAAAA==.',Ty='Tyrtwo:BAAALAAECgMIBAAAAA==.Tyrænde:BAAALAADCgYIBgAAAA==.',['Tå']='Tåzzie:BAAALAADCgYICwAAAA==.',['Tè']='Tèkkslàsh:BAAALAAECgIIAgAAAA==.',['Tô']='Tôny:BAAALAADCggICAAAAA==.',Un='Unholynight:BAAALAAECgEIAQAAAA==.',Va='Vacillator:BAAALAADCgcIBwAAAA==.Valagoris:BAAALAADCgIIAgABLAAECgcIEAABAAAAAA==.Valretha:BAAALAAECgEIAQABLAAECgYICAABAAAAAA==.Valval:BAAALAAECgMIAwAAAA==.Vampymammy:BAAALAAECgYICwAAAA==.Vandalizer:BAAALAADCgcICwAAAA==.Vanishingson:BAAALAAECgEIAQAAAA==.Vanmilder:BAAALAADCgcIBwAAAA==.Varci:BAAALAAECgIIAgAAAA==.Vashet:BAAALAADCgYIDwAAAA==.Vaxilldan:BAAALAAECgEIAQAAAA==.',Ve='Velell:BAAALAADCgIIAgAAAA==.Veloxia:BAAALAADCgcICwAAAA==.Venomsnake:BAAALAAECgEIAQAAAA==.Venura:BAAALAAECgYICAAAAA==.Verelidaine:BAABLAAECoEXAAMGAAgIxx5uCwCrAgAGAAgIxx5uCwCrAgAKAAIIUwK2SwA4AAAAAA==.Vesteros:BAAALAAECggIEwAAAA==.',Vi='Vintage:BAAALAADCgcIBwAAAA==.',Vo='Volatile:BAAALAADCgcIBwAAAA==.Vorvadoss:BAAALAADCggIEAAAAA==.',Wa='Wanghanglo:BAAALAADCgQIBAAAAA==.Wargumbo:BAAALAADCgEIAQAAAA==.',Wo='Woodish:BAAALAAECgYICQAAAA==.',Wy='Wyrmfang:BAAALAADCggIFgAAAA==.',Xa='Xanju:BAAALAAECgcIEAAAAA==.Xanowalker:BAAALAAECgMIAwAAAA==.',Xi='Xinkz:BAAALAAECgMIBAAAAA==.',Xp='Xpiredrat:BAAALAAECggIEQAAAA==.',Xu='Xunji:BAAALAAECgIIBAAAAA==.',Yo='Yolosphinx:BAAALAAECgcIDQAAAA==.Yorry:BAAALAADCggIDgABLAAECgYICQABAAAAAA==.Yourholyness:BAAALAADCgUIBQAAAA==.',Yu='Yuchan:BAAALAAECgMIAwAAAA==.',Za='Zakuba:BAAALAADCgcIBwAAAA==.Zalil:BAAALAAECgMIBAAAAA==.Zapdos:BAAALAAECggIEwAAAA==.Zarcyna:BAACLAAFFIEFAAMLAAMI4RcFAwC1AAALAAII4BkFAwC1AAAMAAII9RFcBwCxAAAsAAQKgRcABAsACAicJFwHAO8BAAsABggnI1wHAO8BAAwABQhRIwIaAOYBAA0ABAiYFJgPADsBAAAA.Zarik:BAAALAAECgIIAgAAAA==.Zaryk:BAAALAAECgIIAgAAAA==.Zathoron:BAAALAAECgcIEAAAAA==.',Ze='Zellven:BAAALAADCgcIBwAAAA==.Zendion:BAAALAAECgEIAgAAAA==.Zenskiv:BAAALAAECgMIBAAAAA==.Zenteryx:BAAALAAECgIIAgAAAA==.Zerphi:BAAALAAECgYICAAAAA==.',Zi='Zillian:BAAALAAECggIEQAAAA==.',Zo='Zorithane:BAAALAADCggICAAAAA==.',Zu='Zumwalathas:BAAALAAECgIIBAAAAA==.',['Zú']='Zúko:BAAALAAECgMIAwAAAA==.',['Àn']='Ànt:BAAALAAECgMIAwAAAA==.',['Àr']='Àriýa:BAAALAAECgMIAgAAAA==.',['Ëv']='Ëvan:BAAALAAECgMIBAAAAA==.',['Ïd']='Ïdril:BAABLAAFFIEGAAIOAAQIuxJYAQBsAQAOAAQIuxJYAQBsAQAAAA==.',['Ða']='Ðarrow:BAAALAADCggIDQAAAA==.',['Öu']='Öutßreak:BAAALAADCgMIAwAAAA==.',['Ûl']='Ûllr:BAAALAAECgIIAwAAAA==.',['Ûn']='Ûnwise:BAAALAAECgcIDQAAAA==.',['ßl']='ßlackplague:BAAALAAECgIIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end