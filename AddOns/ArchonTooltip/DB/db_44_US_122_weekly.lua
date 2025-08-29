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
 local lookup = {'Unknown-Unknown','Shaman-Enhancement','Shaman-Elemental','Hunter-BeastMastery','Druid-Feral','Druid-Balance','Shaman-Restoration','Priest-Holy','Priest-Discipline','DeathKnight-Frost','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Unholy','Evoker-Preservation','Hunter-Marksmanship','Warrior-Fury','Paladin-Protection','DemonHunter-Havoc','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Warrior-Protection','Monk-Brewmaster','DeathKnight-Blood','Priest-Shadow','Paladin-Holy','Mage-Arcane','Mage-Frost','Monk-Mistweaver','Mage-Fire',}; local provider = {region='US',realm='Icecrown',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aarrare:BAAALAADCggIEAAAAA==.',Ad='Adendel:BAAALAADCgYIBgAAAA==.Adobi:BAAALAAECgYICgAAAA==.',Ae='Aeryx:BAAALAAECgYICQAAAA==.',Ah='Ahsôka:BAAALAADCggIFQAAAA==.',Ai='Airie:BAAALAAECgMIBAAAAA==.',Ak='Akatash:BAAALAADCgcIDwAAAA==.Akisa:BAAALAAECgMIAwAAAA==.',Al='Alardressra:BAAALAAECgIIAwAAAA==.Aldoran:BAAALAAECgEIAQAAAA==.Alediran:BAAALAAECgMIBAAAAA==.Alf:BAAALAADCggIFQAAAA==.Algowithagun:BAAALAAECgUIBgAAAA==.Alisterr:BAAALAAECgUICwAAAA==.Allada:BAAALAADCgMIAwAAAA==.Altrys:BAAALAAECgMIBgAAAA==.Always:BAAALAAECgQIBwAAAA==.Alyndras:BAAALAAECgEIAQAAAA==.',Am='Amafrey:BAAALAAECgYICgAAAA==.Amethin:BAAALAADCgQIBAAAAA==.Amo:BAAALAAECgYICwAAAQ==.',An='Andalock:BAAALAAECgcICgAAAA==.Andelle:BAAALAAECgEIAQAAAA==.Andraka:BAAALAADCggIFgAAAA==.Annihilape:BAAALAADCgYIBgAAAA==.Anzi:BAAALAADCggICAABLAAECgYICwABAAAAAA==.',Ap='Apheara:BAAALAAECgEIAQAAAA==.',Aq='Aquariusa:BAAALAADCgcICQAAAA==.',Ar='Arabelle:BAAALAAECgMIAwAAAA==.Arisaris:BAABLAAECoEVAAMCAAcIXRI2BwDSAQACAAcIXRI2BwDSAQADAAEIsAGAVgAeAAAAAA==.Arisl:BAAALAAECggIAQAAAA==.Arlaeya:BAAALAAECgMIAwAAAA==.Artemislux:BAAALAAECgEIAQAAAA==.Artery:BAAALAADCgMIAwAAAA==.Arthassina:BAAALAAECgMIAwAAAA==.Arthes:BAAALAADCggICAAAAA==.Aryastark:BAAALAADCgcIBwAAAA==.',As='Aseeltare:BAAALAAECgcIEQAAAA==.Ashuma:BAAALAADCgcIBwAAAA==.Asline:BAAALAADCggIDwAAAA==.Aslumos:BAAALAADCggICAAAAA==.Astelle:BAAALAAECgcICQAAAA==.',At='Atherial:BAAALAADCgcIBwAAAA==.',Au='Audious:BAAALAADCggIDwAAAA==.Aurawa:BAAALAADCggIFQAAAA==.Autumnn:BAAALAAECgYICgAAAA==.',Av='Avaren:BAAALAAECgIIAgABLAAECgYIFgAEAKMkAA==.Avarenh:BAABLAAECoEWAAIEAAYIoyR+EABqAgAEAAYIoyR+EABqAgAAAA==.Avareno:BAAALAADCgcICAABLAAECgYIFgAEAKMkAA==.Avarens:BAAALAAECgMIAwABLAAECgYIFgAEAKMkAA==.',Aw='Awake:BAAALAADCggIGAABLAAECgYICQABAAAAAA==.Awhbeans:BAEALAAECgMIBgAAAA==.',Ba='Baggins:BAAALAAECgYICQAAAA==.Baineblood:BAAALAADCggIDAABLAAECgIIAgABAAAAAA==.Bainejr:BAAALAAECgIIAgAAAA==.Bandaidhealz:BAAALAAECgMIAwAAAA==.Baylife:BAAALAAECgMIBgAAAA==.',Be='Beasthunter:BAAALAADCgcIEwAAAA==.Bellanor:BAAALAADCgcIBAAAAA==.Bellonà:BAAALAADCggICAAAAA==.Benafflick:BAAALAAECgMIBgAAAA==.Beru:BAAALAADCgIIAgAAAA==.Bevmo:BAAALAADCgcIBwAAAA==.',Bh='Bheorn:BAAALAAECgEIAQAAAA==.',Bi='Bighawktuah:BAAALAADCgYIBgAAAA==.Bigjoe:BAAALAAECgcICgAAAA==.Bigjustice:BAAALAAECgcIEAAAAA==.',Bj='Bjorne:BAAALAAECgUIBgAAAA==.',Bl='Blackcat:BAAALAADCgMIAwAAAA==.Blammo:BAAALAAECgYIBwAAAA==.Blastoise:BAAALAAECggIAwAAAA==.Blinkdh:BAAALAAFFAIIAgAAAA==.Blinklol:BAAALAADCgcIBwABLAAECgcICgABAAAAAA==.Blueyes:BAAALAADCggICAAAAA==.Blïght:BAAALAADCggIFQAAAA==.Blùe:BAAALAAECgUIBgAAAA==.',Bo='Bouquet:BAAALAAECgMIBgAAAA==.',Br='Braavos:BAAALAADCgcIDgAAAA==.Breve:BAAALAADCgMIBgAAAA==.Brewnicorn:BAAALAAECgQIBgAAAA==.Brisenado:BAAALAADCggICAAAAA==.Brokenhymn:BAAALAADCgQIBgAAAA==.',Bu='Bubagump:BAAALAADCggICAAAAA==.Buffdumpster:BAAALAAECgMIBAAAAA==.Bullithead:BAAALAAECgUICAAAAA==.Bumpydin:BAAALAADCgUICAAAAA==.Bunzy:BAAALAADCgcIBAAAAA==.Burleb:BAAALAAECgcIEAAAAA==.Burndrozal:BAAALAAECgMIBQAAAA==.Burph:BAAALAAECgYIBgAAAA==.Busterz:BAAALAADCggIFQAAAA==.',By='Bye:BAAALAAECgIIAgAAAA==.',['Bæ']='Bær:BAAALAADCgMIAwABLAAECgYICwABAAAAAA==.',Ca='Calador:BAAALAADCgEIAQAAAA==.Calorenn:BAAALAADCggIEAABLAAECgQIBgABAAAAAA==.Calorèn:BAAALAADCgYIBgABLAAECgQIBgABAAAAAA==.Calorên:BAAALAAECgQIBgAAAA==.Canuxontop:BAAALAADCgYIBgAAAA==.Capy:BAAALAAECgMIAwAAAA==.Carabetta:BAAALAADCgEIAQAAAA==.Carlitos:BAAALAAECgIIAgAAAA==.Catfood:BAAALAAECgcIEQAAAA==.',Ce='Celebrok:BAAALAADCgYIBgAAAA==.Celebrox:BAAALAAECgIIAwAAAA==.Celedhring:BAAALAAECgUIBgAAAA==.Celestriâ:BAAALAADCggIBwAAAA==.',Ch='Chals:BAAALAAECgcIDwAAAA==.Chanra:BAAALAADCgcIBwAAAA==.Charcoal:BAAALAADCggIDgAAAA==.Charìzard:BAAALAADCggICAAAAA==.Chedyshredy:BAAALAADCgcIBwAAAA==.Chickenism:BAECLAAFFIENAAIFAAUIwyEXAAADAgAFAAUIwyEXAAADAgAsAAQKgSEAAwUACAjTJi8BACcDAAUABwicJi8BACcDAAYACAhHJY8DACQDAAAA.Chowtime:BAAALAAECgYICgAAAA==.Chromium:BAAALAAECgYICgAAAA==.',Ci='Citronia:BAAALAADCgEIAQABLAADCgYIBgABAAAAAA==.',Cl='Claine:BAAALAAECgQICQAAAA==.Clamps:BAABLAAFFIEGAAIHAAIIQyEYBADEAAAHAAIIQyEYBADEAAAAAA==.Clandon:BAACLAAFFIENAAIIAAUIJBo4AADuAQAIAAUIJBo4AADuAQAsAAQKgSEAAwkACAjLHcgDAOwBAAgACAjBGjsNAF8CAAkABgjhGsgDAOwBAAAA.Claxton:BAAALAADCgIIAgAAAA==.Clóckwórk:BAAALAADCgcIBwAAAA==.',Co='Coffeebean:BAAALAAECgEIAQAAAA==.Conformity:BAAALAAECgYICQAAAA==.Coolers:BAAALAAECgEIAgAAAA==.Cosmogos:BAAALAADCgcICgAAAA==.',Cr='Cremia:BAAALAADCgYIBgABLAAECgQICAABAAAAAA==.Croissant:BAAALAADCgcIBwAAAA==.Cron:BAAALAAECgEIAQAAAA==.Cross:BAAALAAECgYICwAAAA==.Cruentus:BAAALAADCgUIBQABLAAECgYIDQABAAAAAA==.Crushem:BAAALAADCggIFgAAAA==.Cryptstory:BAAALAAECgMIAwAAAA==.',Ct='Ctyxia:BAAALAAECggICQAAAA==.',Cu='Curl:BAAALAAECgMIBAAAAA==.',Cy='Cytanous:BAAALAADCgYIBgAAAA==.',Da='Daax:BAAALAADCgcIBwAAAA==.Daddydeath:BAAALAAECgUIBwAAAA==.Dagonfive:BAAALAAECgYIBwAAAA==.Daisyann:BAAALAAECgYIDAAAAA==.Dancouga:BAAALAAECgUIBgAAAA==.Danedrik:BAAALAADCgcICwAAAA==.Danelor:BAAALAADCgMIAwAAAA==.Dantallon:BAEALAADCggIEAAAAA==.Darastrìx:BAAALAADCgcIBwAAAA==.Darkilk:BAAALAADCgQIBAAAAA==.Darkslinger:BAAALAADCggICAAAAA==.Darroon:BAAALAAECgYIDgAAAA==.Darroonx:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Dawnchatters:BAAALAAECgQIBgAAAA==.Dawntodusk:BAAALAADCggIEAAAAA==.Daymann:BAABLAAECoEWAAIKAAgIUCFKBwD9AgAKAAgIUCFKBwD9AgAAAA==.Daymia:BAAALAAECgMIBgAAAA==.Dayquill:BAAALAAECgIIAgAAAA==.Dazknight:BAAALAAECgUICQAAAA==.',De='Deaddemon:BAAALAADCgYIBgABLAAECgYIDQABAAAAAQ==.Deadion:BAAALAAECgYIDQAAAQ==.Deadknot:BAAALAADCgcICQAAAA==.Deadpally:BAAALAAECgQIBgAAAA==.Deadspriest:BAAALAADCgYIDAABLAAECgYIDQABAAAAAQ==.Deathkobus:BAAALAAECgQIBQAAAA==.Decormei:BAAALAAECgMIAwAAAA==.Deltatoast:BAAALAADCgMIAwAAAA==.Destheleye:BAAALAADCggIFgAAAA==.Destiva:BAAALAAECgQIBgAAAA==.Dewdles:BAAALAAECgIIAgAAAA==.Dewdrop:BAAALAAECgYICAAAAA==.',Di='Diamf:BAAALAAECgYIDAAAAA==.Diapermode:BAAALAAECgMIAwABLAAFFAEIAQABAAAAAA==.Dilbis:BAAALAADCgYIBgAAAA==.Dimm:BAAALAAECgMIBgAAAA==.Discordmod:BAAALAADCgcIBwAAAA==.Disneyworld:BAAALAADCgEIAQAAAA==.Dithia:BAAALAAECgYICgAAAA==.Diuxtros:BAAALAAECgYICwAAAA==.Divided:BAAALAAECgYICQAAAA==.',Dj='Djdad:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Djpanther:BAAALAAECgMIAwAAAA==.Djslice:BAAALAAECgIIAwAAAA==.',Dn='Dnk:BAAALAAECgMIBgAAAA==.',Do='Docbushh:BAAALAAECgMIAwABLAAECgcIDQABAAAAAA==.Doohoo:BAAALAAECgIIAwAAAA==.Doomhammerz:BAAALAADCgUIBQAAAA==.Dordrel:BAAALAAECgIIAgAAAA==.Dosilly:BAAALAADCgYIBgABLAAECgQIBQABAAAAAA==.Dotbush:BAAALAAECgcIDQAAAA==.',Dr='Draevon:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Dragondrop:BAAALAADCggIFgAAAA==.Dragoness:BAAALAADCgIIAgAAAA==.Dragonflight:BAAALAAECgMIBgAAAA==.Dragonie:BAAALAADCgQIBAAAAA==.Dragonlyfans:BAAALAADCggIFgAAAA==.Dragonside:BAAALAAECgQIBwAAAA==.Drakloak:BAACLAAFFIEHAAILAAUIDhfAAADNAQALAAUIDhfAAADNAQAsAAQKgRgAAwsACAhJJjABAFsDAAsACAjpJDABAFsDAAwABgjFJbIBADsCAAAA.Drench:BAAALAAECgMIBQAAAA==.Druzhnakova:BAAALAADCgUIBgAAAA==.',Du='Duckdodger:BAAALAADCgIIAgAAAA==.Durota:BAAALAAECgEIAQAAAA==.Dusktodawn:BAAALAADCggICwAAAA==.',Dv='Dv:BAAALAADCggIDAAAAA==.',Dz='Dzzy:BAABLAAECoEhAAIEAAgI9CX+AABxAwAEAAgI9CX+AABxAwAAAA==.Dzzyp:BAAALAAECgMIAwABLAAECggIIQAEAPQlAA==.',['Dà']='Dàmnàtion:BAAALAADCgMIAwAAAA==.Dàmàn:BAAALAADCgMIAwAAAA==.',['Dä']='Däemarcus:BAAALAAECgQIBgAAAA==.',Ec='Ectoz:BAAALAADCgQIBAABLAAFFAIIAgABAAAAAA==.Ectyxx:BAAALAAFFAIIAgAAAA==.',Ek='Ekkothegreat:BAAALAAECggIAQAAAA==.',El='Elberan:BAAALAAECgMIBAAAAA==.Electuzz:BAAALAAECgEIAQAAAA==.Elesar:BAAALAADCgYIBwAAAA==.Elidellx:BAAALAAECgUIBgAAAA==.Elite:BAAALAADCgUIBQAAAA==.Ellantaliia:BAAALAAECgEIAQABLAAECgQIBQABAAAAAA==.Elsmasher:BAAALAADCgcIBwAAAA==.Elwynn:BAAALAAECgcICgAAAQ==.',En='Enkharna:BAAALAAECgEIAQAAAA==.Enklebiter:BAAALAADCggICAAAAA==.',Er='Eraevia:BAAALAAECgIIAgAAAA==.Erolina:BAAALAADCgcIBwAAAA==.Erotaph:BAAALAADCggIFgAAAA==.Errá:BAAALAADCggICQAAAA==.',Es='Esoteric:BAAALAAECgYIBgAAAA==.',Ev='Evilshorty:BAAALAADCgYIBgAAAA==.',Ez='Ezrean:BAAALAADCgIIAgAAAA==.',Fa='Facex:BAAALAADCggICwAAAA==.Faet:BAAALAAECgcICgAAAA==.Faeyt:BAAALAAECgQIBwAAAA==.Farsighted:BAAALAAECgEIAQAAAA==.',Fe='Fecaldumplin:BAAALAADCgEIAQAAAA==.Feedtheiron:BAAALAAECgYIBgAAAA==.Felqath:BAAALAAECggICQAAAA==.',Fi='Fidgetspinna:BAAALAADCgMIBQAAAA==.Finesthour:BAACLAAFFIENAAINAAUIpCMCAAAuAgANAAUIpCMCAAAuAgAsAAQKgSEAAg0ACAj7JgEAALMDAA0ACAj7JgEAALMDAAAA.Finnaburnya:BAAALAADCgMIAwAAAA==.Finnacreep:BAAALAADCggIDgAAAA==.Fisti:BAAALAADCgcIBwAAAA==.',Fl='Flaiaris:BAAALAADCgcIBwAAAA==.Flayon:BAAALAAECgMIBgAAAA==.Flogrinder:BAAALAADCgcIEAAAAA==.Floragoreya:BAAALAAECgEIAQAAAA==.Flùffy:BAAALAAECgYICwAAAA==.',Fo='Foibles:BAAALAADCgMIAwAAAA==.Fouriqclass:BAAALAADCggIFwAAAA==.Foxicious:BAAALAADCgcIBwAAAA==.Foxjaw:BAAALAADCggIDQAAAA==.Foxpaw:BAAALAAECgUIBgAAAA==.',Fr='Fraggle:BAEALAAECgYICwAAAA==.Freathas:BAAALAADCgQIBAAAAA==.Fredsham:BAAALAAECgIIAgAAAA==.Freshtomatoe:BAAALAAECgQICAAAAA==.Frightening:BAAALAADCgYIDAAAAA==.',Fu='Furritoo:BAAALAAECgMIBQAAAA==.Furrivoid:BAAALAADCgcIDQAAAA==.Furyshotz:BAAALAAECgMIBQAAAA==.Fuzzie:BAAALAAECgYIBwAAAA==.',Ga='Galkrana:BAAALAADCgYIBgABLAAECgQICgABAAAAAA==.Galkthyr:BAAALAAECgQICgAAAA==.Gamergoo:BAAALAAECgcICgAAAA==.Gampshwago:BAACLAAFFIELAAMLAAUIwCJlAAAaAgALAAUIwCJlAAAaAgAMAAEIDw1SAQBdAAAsAAQKgSQAAwsACAjfJgYAAKcDAAsACAjfJgYAAKcDAA4AAgiwHF0TAKcAAAAA.Gardrail:BAAALAAECgIIAgAAAA==.Garkk:BAAALAAECgYICQAAAA==.Garronan:BAACLAAFFIENAAMPAAUISSJbAQAiAQAPAAMI8yFbAQAiAQAEAAIIyiL0AgDYAAAsAAQKgSEAAw8ACAhZJXUDAAwDAA8ACAiJJHUDAAwDAAQAAwjEI+w8ADMBAAAA.',Ge='Geoffrogue:BAAALAADCggIFwAAAA==.Geveesa:BAAALAAECgMIBgAAAA==.',Gh='Ghakajin:BAAALAAECgcIDwAAAA==.Ghoststory:BAAALAAECgYICQAAAA==.',Gi='Gibletss:BAAALAAECgcICgAAAA==.Gigatwon:BAAALAADCgcIBwAAAA==.Gitaeki:BAAALAAECgUIBgAAAA==.',Gn='Gnomegirl:BAAALAADCgYIBgAAAA==.',Go='Goldielocks:BAAALAADCgcICAAAAA==.',Gr='Gravemssteak:BAAALAAECgMIBAAAAA==.Graviplana:BAAALAADCgcIDgAAAA==.Grayfoxx:BAAALAADCgcIDAAAAA==.Grindder:BAAALAAECgEIAQAAAA==.Grodahn:BAAALAADCggIDwAAAA==.Groshnok:BAABLAAECoEUAAIQAAcI2CLICgC4AgAQAAcI2CLICgC4AgAAAA==.Grunky:BAACLAAFFIEHAAIHAAQIihQPAQAwAQAHAAQIihQPAQAwAQAsAAQKgRgAAgcACAizJiEAAIEDAAcACAizJiEAAIEDAAAA.',Gs='Gstink:BAAALAADCgYIBgAAAA==.',Gu='Guannifer:BAAALAADCggIDgAAAA==.Gustoshot:BAAALAAECggIBAAAAA==.',['Gá']='Gárd:BAAALAAECgMIBgAAAA==.',Ha='Habebe:BAAALAADCgIIAgAAAA==.Halashim:BAAALAADCgIIAgAAAA==.Halyax:BAAALAAECgIIAgAAAA==.Hamoron:BAAALAAECgYICAAAAA==.Harambae:BAAALAADCgUIBQAAAA==.Harambear:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.Hastad:BAAALAADCgIIAgAAAA==.Hawkingbird:BAAALAAECgMIBwABLAAECgYIDAABAAAAAA==.',He='Healzawrs:BAAALAAECgMIBAAAAA==.Hellsing:BAAALAADCgUIBgAAAA==.Herido:BAAALAAECgYICwAAAA==.Herm:BAAALAAECgMIAwAAAA==.',Hi='Hihowareya:BAAALAAECgIIAgAAAA==.Hildegar:BAAALAAECgMIBQAAAA==.',Ho='Holilope:BAAALAADCgUIBQAAAA==.Holysmaug:BAAALAADCggICAAAAA==.Holysyn:BAAALAADCgIIAgAAAA==.Holyzerph:BAAALAADCgcICAAAAA==.Hornyfoo:BAAALAADCggIFAAAAA==.Hoso:BAAALAAECgcIDgAAAA==.',Hs='Hsolo:BAAALAAECgMIBgAAAA==.',Hy='Hyourin:BAAALAAECgMIAwAAAA==.Hypothermix:BAAALAADCgEIAQAAAA==.',['Hâ']='Hâzél:BAAALAAECgQIBgAAAA==.',['Hä']='Häc:BAAALAAECgMIBAAAAA==.',['Hë']='Hëllräisër:BAAALAAECgMIBAAAAA==.',['Hô']='Hôlystôrm:BAAALAAECgMIBQAAAA==.',Ic='Ichigonyne:BAAALAADCggIFgAAAA==.Ickárus:BAAALAADCgUIBQAAAA==.',Id='Idiscu:BAAALAADCggIDwAAAA==.',Im='Imamoose:BAAALAADCgUIBQAAAA==.Immortal:BAACLAAFFIEMAAIQAAUI0CIfAAAyAgAQAAUI0CIfAAAyAgAsAAQKgSEAAhAACAhvJn8BAGYDABAACAhvJn8BAGYDAAAA.',In='Ineedhelp:BAAALAADCgcIDQAAAA==.Invisinual:BAAALAADCggIEAABLAAECgQIBQABAAAAAA==.',Ir='Irisw:BAAALAADCgYIEQAAAA==.',Is='Isam:BAAALAAECgUICQAAAA==.',Ja='Jackietran:BAAALAADCgIIAgAAAA==.Jadepyre:BAAALAAECgcICgAAAA==.Jaedemon:BAAALAAECgYIDAAAAA==.Jaesan:BAAALAADCgcIBwAAAA==.Jawbreaker:BAAALAADCgYICgAAAA==.Jazaden:BAAALAADCggIEAAAAA==.',Je='Jediyuh:BAAALAAECgMIBAAAAA==.Jellybeanjar:BAAALAAECgQIBgAAAA==.Jerlion:BAAALAAECgcICgAAAA==.',Jl='Jlhu:BAAALAADCgQIBAAAAA==.',Jo='Johnjenkins:BAAALAADCgEIAQAAAA==.Jorji:BAAALAADCgcIBwAAAA==.Jorkin:BAAALAAECgYIBgAAAA==.',Jt='Jtvikiing:BAAALAADCgYIBgAAAA==.',Ju='Jumpies:BAAALAADCggIFgAAAA==.Juunbroh:BAAALAAECgUIBQAAAA==.',Ka='Kaana:BAAALAAECgUICQAAAA==.Kaiyla:BAAALAADCgcIDAAAAA==.Kalid:BAAALAAFFAIIAgABLAAFFAQIBwAHAIoUAA==.Kalpanda:BAAALAADCgYIBgAAAA==.Kamyndra:BAAALAAECgMIBAAAAA==.Karma:BAAALAAECgEIAQAAAA==.Kaunjin:BAAALAAECgMIBQAAAA==.Kaèltho:BAAALAAECgIIAwAAAA==.',Ke='Kedrak:BAAALAADCgIIAgAAAA==.Keell:BAAALAADCgIIAgAAAA==.Kegcrash:BAAALAADCgIIAgAAAA==.Kegroll:BAAALAADCgcICQABLAADCggIDQABAAAAAA==.Keillea:BAAALAAECgcICQAAAA==.Keir:BAAALAAECgMIBgAAAA==.',Kh='Khaeltharion:BAAALAAECgcIDwAAAA==.',Ki='Kickrocks:BAAALAAECgIIAgAAAA==.Killauwrlock:BAAALAADCggIEQAAAA==.Kilmanov:BAAALAAECggIAQAAAA==.Kinkies:BAAALAAECgEIAQAAAA==.Kitmeup:BAAALAAECggIDgAAAA==.',Kl='Klemm:BAAALAADCggIDwAAAA==.',Kn='Knighella:BAAALAADCggIEAAAAA==.',Ko='Koal:BAEALAADCggIFgABLAAECgYICwABAAAAAA==.Kodu:BAAALAADCggICAAAAA==.Kommit:BAACLAAFFIEIAAIRAAUIGRxFAACWAQARAAUIGRxFAACWAQAsAAQKgRcAAhEACAh3IvsEAG4CABEACAh3IvsEAG4CAAAA.Kortotem:BAAALAADCgMIAwAAAA==.Koyn:BAAALAADCgYIBQABLAAECgEIAQABAAAAAA==.Kozzyy:BAAALAADCggICQAAAA==.',Kr='Krymsy:BAAALAADCggIDAAAAA==.',Kw='Kwikkicks:BAAALAAECgcICgAAAA==.',Ky='Kyder:BAAALAADCgIIAgABLAAECgQICgABAAAAAA==.Kymiro:BAACLAAFFIENAAISAAUIKByRAAAKAgASAAUIKByRAAAKAgAsAAQKgSEAAhIACAgzJroBAG4DABIACAgzJroBAG4DAAAA.Kynir:BAAALAAFFAEIAQAAAA==.',['Kä']='Käthryn:BAAALAADCgMIAwAAAA==.',La='Labzy:BAAALAADCgYIBgAAAA==.Laloria:BAAALAAECgMIAwAAAA==.',Le='Lebomba:BAAALAAECggICwAAAA==.Lenamore:BAAALAADCgUIBQAAAA==.Leobardo:BAAALAAECgYIDQAAAA==.',Li='Lighterrup:BAAALAAECgMIAwABLAAECgYICwABAAAAAA==.Lilpeewee:BAAALAAECgMIAwAAAA==.Linting:BAAALAAECgcICQAAAA==.Lithsong:BAAALAADCgUIBQAAAA==.Littlemorsel:BAAALAADCgYIBgAAAA==.Livindedgurl:BAAALAADCggICwAAAA==.',Lo='Lohele:BAAALAAECgcIDwAAAA==.Lohtou:BAAALAADCgcIBwAAAA==.Lonie:BAAALAAECgYICwAAAA==.Lotion:BAAALAAECgYIDQAAAA==.',Lu='Lucyfury:BAAALAADCgIIAgAAAA==.Luedragosa:BAAALAAECgEIAQAAAA==.Lumie:BAAALAADCggIFgAAAA==.Lummox:BAAALAAECgEIAQAAAA==.Luthern:BAAALAADCgcIBwAAAA==.Luxy:BAAALAAECgYICAAAAA==.',Ly='Lysunder:BAAALAAECgMIBgAAAA==.Lythronax:BAAALAADCgcIDgAAAA==.',['Lö']='Löwen:BAAALAAECgYICwAAAA==.',Ma='Mackzsh:BAAALAAECggIEgAAAA==.Madblackjack:BAAALAAECgIIAgAAAA==.Madlark:BAAALAADCgIIAgABLAAECgQICAABAAAAAA==.Madlarkin:BAAALAAECgQICAAAAA==.Maeverune:BAAALAAECgEIAQAAAA==.Magie:BAAALAAECgYICwAAAA==.Mahanar:BAAALAAECgIIAgAAAA==.Malchiel:BAAALAAECgEIAQAAAA==.Malisenta:BAAALAADCgIIAgABLAAECgQIBgABAAAAAA==.Manahoe:BAAALAADCgUIAwAAAA==.Manech:BAAALAAECgQIBgAAAA==.Markoramius:BAAALAAECgQIBAAAAA==.Marshmallows:BAAALAADCgUIBwAAAA==.Marthan:BAAALAAECgMIBAAAAA==.Masonqt:BAAALAADCgYICwAAAA==.',Mc='Mcscales:BAAALAAECgcIEQAAAA==.',Me='Mechadeeps:BAAALAADCgcIBwAAAA==.Mechajoni:BAAALAADCggIDgAAAA==.Meen:BAAALAAECgQIBwAAAA==.Meganpriest:BAAALAAFFAIIBAAAAA==.Mekhasingh:BAAALAAECgIIAgAAAA==.Melindhra:BAABLAAECoEVAAIEAAgIBiCkBQALAwAEAAgIBiCkBQALAwAAAA==.Merandelle:BAAALAAFFAIIAgAAAA==.Mercaanary:BAAALAADCgYICQAAAA==.Mercilous:BAAALAADCgcIBwAAAA==.Merlins:BAAALAAECgUIBgAAAA==.Meruem:BAAALAADCgEIAQAAAA==.Metarage:BAAALAADCgcIBwAAAA==.',Mi='Miamiganster:BAAALAAFFAIIBAAAAA==.Mindbullets:BAAALAADCgYIBgAAAA==.Minerz:BAAALAADCgYIBgAAAA==.Mirah:BAAALAAECggIDgAAAA==.Misclick:BAAALAAECgIIAgAAAA==.Mithrandir:BAAALAADCggICQAAAA==.',Mo='Mogriya:BAAALAAECgUIBwAAAA==.Mokt:BAAALAAECgQIBQAAAA==.Mollywhop:BAAALAAECgMIAwAAAA==.Molyneaux:BAAALAAECgMIBgAAAA==.Mondommond:BAAALAAECgEIAQAAAA==.Monkie:BAAALAAECgYIDgAAAA==.Montee:BAAALAAECgIIBAAAAA==.Moonlite:BAAALAADCgYIBgAAAA==.Moozi:BAAALAAECgUICQAAAA==.Morags:BAAALAADCgQIBgAAAA==.Mortisima:BAAALAAECggIBwAAAA==.Motgus:BAAALAADCgEIAQAAAA==.',Ms='Mskittie:BAAALAAECgIIAwAAAA==.',Mu='Munnydk:BAEALAAECgYIEgAAAA==.Murph:BAAALAAECgYICwAAAA==.Mutilatee:BAACLAAFFIELAAMTAAUIOx3zAABAAQATAAMIQx3zAABAAQAUAAIILR06AQDBAAAsAAQKgSEABBMACAjxJa4BAEIDABMACAjoI64BAEIDABQABAgGJXcGAK0BABUAAggzJD4JANIAAAAA.',My='Myeesa:BAAALAAECgMIBAAAAA==.Myeyeonu:BAAALAAECgIIBQAAAA==.Mystshots:BAAALAAECgEIAQAAAA==.',['Mé']='Méruem:BAAALAAECgQIBQAAAA==.',['Mí']='Míra:BAAALAAECgUIBgAAAA==.',Na='Nachtengel:BAAALAAECgQIBAAAAA==.Nagda:BAAALAADCgcIBwAAAA==.Naismine:BAAALAAECgMIBQAAAA==.Nakita:BAAALAADCggICAAAAA==.Nate:BAAALAAECgMIBAAAAA==.Natzely:BAAALAAECgIIAgAAAA==.Natzriel:BAAALAADCgcIBwAAAA==.Naustaire:BAAALAADCgYIBgAAAA==.',Ne='Nebulous:BAAALAAECgcICgAAAA==.Necromantic:BAAALAAECgMIAwAAAA==.Neila:BAAALAAFFAIIAgAAAA==.Nerfdtodeath:BAAALAAECgcICAAAAA==.Nerfed:BAAALAAECgcICgAAAA==.Nesaru:BAAALAAECgQIBwAAAA==.',Ni='Niav:BAAALAAECgEIAQAAAA==.Nightcowtoo:BAAALAADCggICAAAAA==.Nimueh:BAAALAADCgcIBwAAAA==.Nines:BAAALAAECgYIBgAAAA==.Nisaloth:BAAALAAECgQIBQAAAA==.',No='No:BAAALAADCggICAAAAA==.Nobumori:BAAALAADCgcIBwAAAA==.Nonaz:BAAALAAECgYICAAAAA==.Nontoxic:BAAALAAECgcICQAAAQ==.Noop:BAAALAADCggIFgAAAA==.Norot:BAAALAADCggIFgAAAA==.Noxvalens:BAAALAADCgMIAwAAAA==.',Nu='Nual:BAAALAAECgQIBQAAAA==.Nubtorious:BAAALAADCgIIAgAAAA==.Nudag:BAAALAAECgMIBAAAAA==.',Ol='Older:BAAALAAECgUIBgAAAA==.Olk:BAAALAAECgYICAAAAA==.',Om='Omari:BAAALAAECgcIDAAAAA==.Omita:BAAALAAECgIIAwAAAA==.',On='Onerustyboi:BAAALAADCggIDwAAAA==.',Oo='Oohgabooga:BAAALAADCggICAAAAA==.',Or='Oreganom:BAAALAAECgYIBgABLAAFFAUIDAAWAFwaAA==.Oreganosh:BAAALAAFFAIIAgABLAAFFAUIDAAWAFwaAA==.Oreganow:BAACLAAFFIEMAAMWAAUIXBrhAADsAQAWAAUIXBrhAADsAQAXAAEIrgSfDABJAAAsAAQKgSEABBYACAh7JsYAAHcDABYACAh6JsYAAHcDABgABghoJMoCAHUCABcAAQipHIhEAE8AAAAA.Orenghar:BAAALAAECgMIBAAAAA==.Oribelle:BAAALAADCgUIBQAAAA==.',Ov='Overbite:BAAALAADCgcIBwAAAA==.Overcast:BAAALAADCgcIEwAAAA==.',Pa='Pallyisbad:BAAALAADCgcIBwAAAA==.Papadôc:BAAALAADCgcICQAAAA==.Papi:BAAALAADCggIBAAAAA==.Pavlov:BAAALAAECgIIAgAAAA==.',Pe='Pedometer:BAAALAADCgcIDAAAAA==.Penrhyn:BAAALAADCgEIAQAAAA==.Pesmerga:BAAALAADCgQIBgAAAA==.Petuski:BAAALAAECgYICQAAAA==.Pewpewism:BAEALAAFFAIIAgABLAAFFAUIDQAFAMMhAA==.',Ph='Phaithe:BAAALAADCgMIBAAAAA==.Phalynn:BAAALAAECgIIAgAAAA==.Phatrips:BAAALAADCgQIBAABLAAECgYICwABAAAAAA==.Phriaa:BAAALAADCggIDwABLAAECgMIBQABAAAAAA==.',Pi='Picante:BAAALAAECgMIAwAAAA==.Pingu:BAABLAAECoEWAAIHAAgIDCQ8AQAxAwAHAAgIDCQ8AQAxAwAAAA==.Pintsized:BAAALAADCgYIBgABLAAECgYICwABAAAAAA==.',Pk='Pkfiend:BAAALAADCgcIBwAAAA==.Pkspyro:BAAALAAECgMIBAAAAA==.',Pl='Planckshock:BAAALAADCggIGAAAAA==.',Po='Popicus:BAAALAADCggIFwAAAA==.Potf:BAAALAADCgcIBwAAAA==.',Pr='Pratz:BAAALAADCgUICAAAAA==.Primatepete:BAABLAAECoEhAAIZAAgIHh7QDgCaAgAZAAgIHh7QDgCaAgAAAA==.Protpalli:BAAALAAECgYICQAAAA==.Prudk:BAAALAAECgYIBgAAAA==.Prumage:BAAALAAECgYIBgAAAA==.Prupru:BAABLAAECoEYAAMWAAgIICNfAgBHAwAWAAgIICNfAgBHAwAXAAEIvxrARwBHAAAAAA==.',Pu='Pumpa:BAAALAAFFAEIAQAAAA==.Punchfist:BAAALAAECgEIAgAAAA==.Punchymchit:BAAALAAECgQICQAAAA==.',Qu='Quickchicken:BAAALAADCgYIBwAAAA==.',Ra='Racecar:BAAALAAECgYICQAAAA==.Radala:BAABLAAFFIEHAAIaAAMIJh9UAQAEAQAaAAMIJh9UAQAEAQABLAAFFAUICgAbAPwbAA==.Raddru:BAAALAAECgYIBgABLAAFFAUICgAbAPwbAA==.Radel:BAABLAAECoEYAAIcAAgIFQBbIQAMAAAcAAgIFQBbIQAMAAABLAAFFAUICgAbAPwbAA==.Radmonk:BAACLAAFFIEKAAIbAAUI/BtrAADQAQAbAAUI/BtrAADQAQAsAAQKgRgAAhsACAgLJd0AAFgDABsACAgLJd0AAFgDAAAA.Radpal:BAAALAAECgYIBgABLAAFFAUICgAbAPwbAA==.Raesham:BAAALAAECgEIAgAAAA==.Ragemaster:BAAALAADCgUIBQAAAA==.Ragnaar:BAAALAADCgUIBQAAAA==.Rakour:BAAALAADCggICAAAAA==.Ralah:BAAALAAECgYICwAAAA==.Ranolas:BAAALAADCgcICgAAAA==.Raydoth:BAAALAAECgMIAwAAAA==.Razeus:BAAALAADCgcIEAAAAA==.',Re='Reallyclever:BAAALAAECgYIDQAAAA==.Redorai:BAAALAADCgcIDAAAAA==.Reinys:BAAALAAECgMIAwAAAA==.Relzira:BAAALAAECgMIBAAAAA==.Revokor:BAAALAAFFAIIAgAAAA==.Rezispacqt:BAAALAAECgMIBgAAAA==.',Ri='Risto:BAAALAAFFAEIAQAAAA==.Rizzed:BAAALAADCgMIBQAAAA==.',Ro='Rockgoblin:BAAALAADCggIDQAAAA==.Rocknlock:BAAALAAECgMIAwAAAA==.Rossin:BAAALAAECgMIBAAAAA==.',Ry='Ryddlesr:BAAALAAECgcIDgAAAA==.Ryeshot:BAACLAAFFIEMAAIdAAUIwiNkAAAcAgAdAAUIwiNkAAAcAgAsAAQKgSEAAh0ACAhsJosAAIQDAB0ACAhsJosAAIQDAAAA.Rylin:BAAALAADCggIEAAAAA==.',['Rü']='Rüwüdë:BAAALAADCggIDAAAAA==.',Sa='Saikotik:BAAALAADCggIFgAAAA==.Salakazam:BAAALAAECgIIAgAAAA==.Sallich:BAAALAADCggIFwAAAA==.Santacruzfc:BAAALAAECgIIBAAAAA==.Sarcii:BAAALAAECgUIBgAAAA==.Sarri:BAAALAADCgYIEgABLAAECgYICwABAAAAAA==.Sarthuul:BAAALAADCggIDwAAAA==.Sarusham:BAAALAAECggIDgAAAA==.Saruu:BAAALAAECgYIDAAAAA==.Satanika:BAAALAAECggIBQAAAA==.Sauronn:BAAALAAECgEIAQAAAA==.Sayleen:BAAALAADCgcIBwAAAA==.',Sc='Scarlah:BAAALAAECgEIAQAAAA==.Scarrotem:BAAALAAECgcICgAAAA==.Scrabbles:BAAALAAECgYIDgAAAA==.',Se='Sedimental:BAAALAADCggIDwAAAA==.Senara:BAAALAAECgQICgAAAA==.Serenityñow:BAAALAADCgYICwAAAA==.Severas:BAAALAAECgYIBwAAAA==.',Sh='Shadorash:BAAALAADCggICQAAAA==.Shadowcross:BAAALAADCggIDwAAAA==.Shadowfactor:BAAALAADCggIFgAAAA==.Shadownej:BAAALAADCggIFgAAAA==.Shadowqeini:BAAALAAECgMIBgAAAA==.Shakakill:BAAALAADCgcIBwAAAA==.Shamonlee:BAAALAADCggIEQAAAA==.Shan:BAAALAAECgYIDQAAAA==.Shapaladin:BAAALAAECgMIBAAAAA==.Shockacon:BAAALAADCggICAAAAA==.Shockpaw:BAAALAADCgYICgAAAA==.Shocolate:BAAALAAECgEIAQAAAA==.Shogun:BAAALAAECgYICwAAAA==.Shtinkus:BAAALAAECgMIBAAAAA==.',Si='Sidereus:BAAALAAECgYICgABLAADCgUIBQABAAAAAQ==.Sidewayz:BAAALAADCgUIBQAAAA==.Silibriti:BAAALAAECgQIBgAAAA==.Silladin:BAACLAAFFIEJAAIeAAQIjQQeAQA4AQAeAAQIjQQeAQA4AQAsAAQKgSEAAh4ACAheFTAIAEUCAB4ACAheFTAIAEUCAAAA.Silys:BAAALAAECgMIBQAAAA==.Simille:BAAALAADCggIDwAAAA==.Sinknight:BAACLAAFFIEKAAMKAAQILh6TAAClAQAKAAQILh6TAAClAQANAAEIAgNGBQBeAAAsAAQKgSEAAgoACAhqJp8AAIADAAoACAhqJp8AAIADAAAA.Sipthyr:BAAALAADCgMIAwAAAA==.Sixxnine:BAAALAADCgUIBQAAAA==.',Sk='Skagodin:BAAALAAECgEIAQAAAA==.Skagodk:BAAALAADCgMIAwAAAA==.Skagowa:BAAALAADCggICAAAAA==.Skeebadae:BAAALAAECgUICAAAAA==.Skelestar:BAAALAAECgcICgAAAA==.',Sl='Slayabunny:BAAALAAFFAIIAgAAAA==.Slepslep:BAAALAADCggIEAABLAAECgQIBgABAAAAAA==.Slepybaer:BAAALAAECgQIBgAAAA==.',Sm='Smaugvoker:BAAALAAECgYICQAAAA==.Smoosh:BAAALAAECgEIAQAAAA==.',Sn='Sneakyrage:BAAALAADCgUIBQAAAA==.Snowolf:BAAALAADCgQIBAAAAA==.',So='Sororitas:BAAALAAECgMIBgAAAA==.Southpau:BAAALAADCgQIBAABLAAECggIFQAHABkhAA==.Southpauxx:BAABLAAECoEVAAIHAAgIGSEiBADZAgAHAAgIGSEiBADZAgAAAA==.Souupded:BAAALAADCgYIBgABLAAECgIIAwABAAAAAA==.Souupfu:BAAALAADCgcIBwABLAAECgIIAwABAAAAAA==.Souupgonwild:BAAALAAECgIIAwAAAA==.',Sp='Spee:BAAALAADCgUIBgAAAA==.Spunkyshroom:BAAALAADCgcICgAAAA==.',Ss='Ssdende:BAAALAAECgUIBQAAAA==.Ssjorion:BAAALAADCgYIDAAAAA==.',St='Stacydabes:BAAALAAECggIDwAAAA==.Stainer:BAABLAAECoEhAAIfAAgIeRyvDgCvAgAfAAgIeRyvDgCvAgAAAA==.Stellalluna:BAAALAAECgMIAwAAAA==.Stormstone:BAAALAADCgIIAgAAAA==.Strepsis:BAAALAAFFAIIAgAAAA==.',Su='Suspenders:BAAALAAECgMIBAAAAA==.',Sy='Sydarla:BAAALAADCggIDwAAAA==.Sylvak:BAAALAAECgcIEAAAAA==.Sylvanassimp:BAAALAAECgIIAgAAAA==.Symorn:BAAALAAECgMIBAAAAA==.',['Sã']='Sãphirã:BAAALAAECggIAwAAAA==.',['Sä']='Säm:BAAALAADCgYIBwABLAAECgYICwABAAAAAA==.',Ta='Taelil:BAAALAAECgMIBAAAAA==.Tageretta:BAAALAAECgQIBAAAAA==.Tagerhumon:BAAALAADCgMIAwAAAA==.Tagerloc:BAAALAAECgEIAQAAAA==.Tagmage:BAAALAADCgIIAwAAAA==.Talenath:BAAALAAECgYICwAAAA==.Tanalock:BAAALAAECgMIBAAAAA==.Tatertot:BAAALAAECgYICgAAAA==.Taynka:BAAALAAECgEIAQAAAA==.',Te='Terayesa:BAAALAADCgYIBgAAAA==.Teriza:BAAALAAECgYIBgAAAA==.',Th='Thallya:BAABLAAECoEUAAIgAAcIqiDHBQCJAgAgAAcIqiDHBQCJAgAAAA==.Theannoyance:BAAALAADCggIDgAAAA==.Theevil:BAAALAAECgMIAwAAAA==.Theliberal:BAAALAADCgMIBAAAAA==.Thelonnius:BAAALAAECgMICgAAAA==.Therealsb:BAAALAAECgYIBwABLAAFFAIIAgABAAAAAA==.Thornstaad:BAAALAAECgIIAwAAAA==.Thortanous:BAAALAADCggIEAAAAA==.Throckmortus:BAAALAAECgEIAQAAAA==.Thunderboom:BAAALAADCgYIBgAAAA==.Thundercles:BAAALAAECgMIBAAAAA==.Thundir:BAAALAADCgYIBgAAAA==.Thymé:BAAALAADCgYICwAAAA==.Thór:BAAALAADCggICAAAAA==.',Ti='Tiacapan:BAAALAADCgcIEAAAAA==.Tideradra:BAACLAAFFIEJAAIDAAQIfhsgAQCIAQADAAQIfhsgAQCIAQAsAAQKgSEAAgMACAhQJoUAAIYDAAMACAhQJoUAAIYDAAAA.Tieranos:BAAALAAECgMIBQAAAA==.Tigerdrop:BAAALAADCggIFgAAAA==.Tigerich:BAAALAADCgEIAQAAAA==.Ting:BAAALAAECgcIEwAAAA==.Tinydecay:BAAALAADCgIIAgAAAA==.Tinypally:BAAALAADCggICgAAAA==.Tirays:BAAALAADCggIEQAAAA==.Tivv:BAAALAADCgQIBAAAAA==.Tivøn:BAABLAAECoEYAAMHAAgInBKvHwC9AQAHAAgInBKvHwC9AQADAAYI7AxeJwBtAQAAAA==.',Tk='Tkfreeze:BAAALAADCgEIAQAAAA==.',To='Toixic:BAACLAAFFIEHAAIhAAMI3xAfAgD1AAAhAAMI3xAfAgD1AAAsAAQKgSEAAiEACAiZG1AGAGICACEACAiZG1AGAGICAAAA.Tonyrigatoni:BAAALAADCggIDgAAAA==.Tootihunt:BAAALAAECgcIEwAAAA==.Tootilock:BAAALAADCgQIBAABLAAECgcIEwABAAAAAA==.Totesmkge:BAAALAAECgUIBgAAAA==.Totmdispenzr:BAAALAADCggIFgAAAA==.',Tr='Travaxian:BAAALAAECgYICwAAAA==.Trogburn:BAAALAAECgIIAgAAAA==.Trogfour:BAAALAADCgcIBwAAAA==.Trunks:BAAALAADCgQIBAAAAA==.',Ts='Tsellie:BAAALAAECgYIDAAAAA==.Tsukoyomi:BAAALAADCggICAAAAA==.',Tu='Tummylover:BAAALAADCgEIAQAAAA==.Tumtumm:BAAALAAECgQIBgAAAA==.Turboknight:BAAALAADCgcIDAAAAA==.Turbotdemon:BAAALAAECgYICwAAAA==.Turkleton:BAAALAAECgcIEAAAAA==.',Tw='Twelvebtw:BAACLAAFFIELAAMWAAUILRK1AQB3AQAWAAQIFha1AQB3AQAXAAIIIg1TBgCaAAAsAAQKgSEABBYACAivJeEAAHQDABYACAivJeEAAHQDABgABwghGUwEAD0CABcAAwhUHl0hABABAAAA.Twelvyyh:BAAALAAECgYIBgABLAAFFAUICwAWAC0SAA==.Twístedteå:BAAALAADCggIFwAAAA==.',Ty='Tylos:BAAALAADCgcIDQAAAA==.Tyraxous:BAAALAAECgQIBgAAAA==.Tyrinnà:BAAALAAECgIIBAAAAA==.',['Tà']='Tàiko:BAAALAAECgUIBgAAAA==.',Ug='Ugrestul:BAAALAADCggIEwAAAA==.',Ul='Ulah:BAAALAADCgcIFAAAAA==.',Un='Unfixed:BAAALAADCgMIBQAAAA==.Unknownz:BAAALAAECgYIAQAAAA==.Unstopawble:BAAALAAECgUIBgAAAA==.Unstopubble:BAAALAADCgcICQAAAA==.',Va='Vaariks:BAAALAAECgYICwAAAA==.Vaera:BAAALAAECgMIBAAAAA==.Valianthe:BAAALAAECgMIAwAAAA==.Vasiliy:BAAALAADCgUIBQAAAA==.Vaylen:BAAALAADCgcIDQAAAA==.',Ve='Velaryon:BAAALAADCgcIBwAAAA==.Vet:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.',Vi='Viddik:BAAALAAECggIBAAAAA==.Vikingdrood:BAAALAAECgYIEAAAAA==.Vikingdroodd:BAAALAAECgUIBwABLAAECgYIEAABAAAAAA==.Vikingjoe:BAAALAAECgYICAABLAAECgYIEAABAAAAAA==.Vikinglockk:BAAALAADCgEIAQABLAAECgYIEAABAAAAAA==.Vinnyfr:BAAALAAECgYIDQAAAA==.Viwi:BAAALAAECgMIBgAAAA==.Vixxyy:BAAALAAECgIIAgAAAA==.',Vo='Vokerism:BAEALAAECgYIDAABLAAFFAUIDQAFAMMhAA==.Vokerjor:BAAALAADCggIFwAAAA==.Vorden:BAAALAADCggICQAAAA==.',Vu='Vulair:BAAALAADCgcIDQAAAA==.',['Vî']='Vîta:BAAALAADCggIDwAAAA==.',Wa='Wagic:BAAALAADCgcIBwAAAA==.',Wi='Wisdom:BAAALAAECgcIEQAAAA==.',Wl='Wlfxy:BAAALAAECgMIAwAAAA==.',Wo='Wonrey:BAAALAAECgMIBgAAAA==.',Wy='Wynndiego:BAAALAAECgYICwAAAA==.Wyrmslayer:BAAALAAECgcIDQAAAA==.',Xa='Xaidra:BAACLAAFFIENAAIOAAUIEx9PAAACAgAOAAUIEx9PAAACAgAsAAQKgSEAAg4ACAjmITwBAPoCAA4ACAjmITwBAPoCAAAA.Xalatathfeet:BAAALAAECgcICwAAAA==.Xanatu:BAAALAAECgUIBQAAAA==.Xandyr:BAAALAADCgcIBwAAAA==.',Xe='Xecron:BAAALAAFFAEIAQAAAA==.Xedk:BAAALAAECgUIBgAAAA==.Xepherite:BAAALAAFFAEIAQAAAA==.',Xi='Xiaojian:BAAALAAECgcIDgAAAA==.',Xp='Xpectrum:BAAALAAECgMIAwAAAA==.',Ye='Yex:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.',Yo='Yonaton:BAAALAAECgEIAQAAAA==.',Za='Zalea:BAACLAAFFIEMAAIfAAUIXSNRAAATAgAfAAUIXSNRAAATAgAsAAQKgSEAAx8ACAiIJroAAHoDAB8ACAiIJroAAHoDACIAAQghJcoJAGEAAAAA.Zaleera:BAAALAAFFAIIAgABLAAFFAUIDAAfAF0jAA==.Zana:BAAALAAECgMIBwABLAAECgYICgABAAAAAA==.Zaries:BAAALAAECgYIDwAAAA==.Zarrion:BAAALAAECgYIDwAAAA==.Zazarri:BAAALAADCgcIBwAAAA==.',Ze='Zendroza:BAAALAADCgYICQAAAA==.Zenfuzz:BAAALAADCgYIBgAAAA==.Zephyrlock:BAAALAADCgMIBgAAAA==.Zerkin:BAAALAADCgYICwAAAA==.',Zi='Zingers:BAAALAADCgcIBwAAAA==.',Zo='Zonovar:BAAALAADCgYICgAAAA==.',Zu='Zugzuglife:BAAALAADCggIEAAAAA==.',Zy='Zyxx:BAAALAAECgEIAQAAAA==.',['Zà']='Zàddy:BAAALAADCgEIAQAAAA==.',['Ås']='Åshborn:BAAALAADCggICAAAAA==.',['Év']='Év:BAAALAAECgEIAgAAAA==.',['Ði']='Ðixiewrecked:BAAALAAECgYIBgAAAA==.',['Ðr']='Ðragoòn:BAAALAADCgIIAgAAAA==.',['Ðu']='Ðuckii:BAAALAAECgMIAwAAAA==.',['Ôw']='Ôwô:BAAALAADCgYICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end