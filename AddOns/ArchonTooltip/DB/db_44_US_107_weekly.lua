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
 local lookup = {'Unknown-Unknown','Paladin-Holy','Priest-Shadow','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Priest-Holy','Paladin-Retribution',}; local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=44,date='2025-08-29',data={Ac='Accusations:BAAALAAECgcIEAABLAAECggIFQABAAAAAA==.',Ae='Aeowyyn:BAAALAAECgMIAwAAAA==.Aerwynn:BAAALAAECgEIAQAAAA==.Aestra:BAAALAADCggIBwAAAA==.',Ag='Aggretsuko:BAAALAADCgYIDgAAAA==.',Ah='Ahnkhano:BAABLAAECoEUAAICAAcItxofCwATAgACAAcItxofCwATAgAAAA==.Ahnur:BAAALAADCgUIBAABLAAECgMIAwABAAAAAA==.',Ai='Ailyin:BAAALAADCgYIBgABLAAECggIEQABAAAAAA==.Aiom:BAAALAADCgUIBQAAAA==.Airiistra:BAAALAAECgEIAQAAAA==.Aiylyn:BAAALAADCgQIBAABLAAECggIEQABAAAAAA==.',Ak='Akbartheiiv:BAABLAAECoEYAAIDAAgIWCWnAQBcAwADAAgIWCWnAQBcAwAAAA==.',Al='Alexarose:BAAALAADCgEIAQAAAA==.Allistrana:BAAALAAECgcIDgAAAA==.Alyx:BAABLAAECoEeAAMEAAgIJCHtBAAXAwAEAAgIJCHtBAAXAwAFAAMIGyDrLgDmAAAAAA==.',Am='Amethos:BAAALAADCgMIAwAAAA==.Ametrine:BAAALAADCgIIAgAAAA==.',An='Anrion:BAAALAAECggIEAAAAA==.',Ar='Aristia:BAAALAADCggIDAABLAAECgYIDQABAAAAAA==.Aritus:BAAALAAECgMIAwAAAA==.Artyom:BAAALAADCgQIBAAAAA==.',Au='Auranar:BAAALAADCggIDQAAAA==.',Av='Avanicus:BAAALAADCgYICgAAAA==.',Aw='Awenari:BAAALAAECgMIAwAAAA==.',Ax='Axellent:BAAALAAECgEIAQAAAA==.Axiomlegacy:BAAALAAECgcIDgAAAA==.Axlnt:BAABLAAECoEUAAMGAAgIYh9CEQB9AgAGAAcIZyFCEQB9AgAHAAYI9RoLCgChAQAAAA==.',Az='Azeroth:BAAALAAECgEIAQAAAA==.',['Aí']='Aíylin:BAAALAADCgUIBQABLAAECggIEQABAAAAAA==.',Ba='Bajablaster:BAAALAADCgcIBwAAAA==.Bar:BAAALAAECggIDAAAAA==.Barackobamaz:BAAALAADCggICAAAAA==.',Be='Bearlyshady:BAAALAAECggIEQAAAA==.Bermy:BAAALAAECgIIBAAAAA==.Besik:BAAALAADCgYIBgAAAA==.Bewildert:BAAALAADCgYIEAAAAA==.',Bi='Bigfatmama:BAAALAAECgEIAQAAAA==.Bigjuju:BAAALAADCgUIBQAAAA==.',Bl='Bloodshadow:BAAALAAECgMIBQAAAA==.Blunderbuzz:BAAALAADCggICAABLAAECgQICAABAAAAAA==.',Bo='Bobeezu:BAAALAAECgMIAwAAAA==.Boltaire:BAAALAADCgcIBwAAAA==.Borstraz:BAAALAAECgEIAQAAAA==.',Br='Braft:BAAALAADCgYICAAAAA==.Bretcoe:BAAALAADCgMIAQAAAA==.',Ca='Caelix:BAAALAAECgMIAwAAAA==.Cale:BAAALAADCgQIBAAAAA==.Carbonight:BAAALAADCgUIBQAAAA==.Cariafel:BAAALAADCggIDwAAAA==.Carlos:BAAALAADCgUIBQAAAA==.Carneasada:BAAALAAECgIIAgAAAA==.',Ce='Celani:BAAALAAECgYIBgAAAA==.',Ch='Cheheals:BAEALAADCgMIBQABLAAECgEIAQABAAAAAA==.Chelives:BAEALAAECgEIAQAAAA==.Chillbro:BAAALAADCgEIAQAAAA==.Chromus:BAAALAAECggIEQAAAA==.',Ci='Cires:BAAALAAECgQIBQAAAA==.',Co='Cobaltwolf:BAAALAADCgcICwAAAA==.Colanasou:BAAALAADCgcIEwAAAA==.Coreth:BAAALAADCgIIAgAAAA==.Corvere:BAAALAAECggIEgAAAA==.',Cr='Cracked:BAAALAADCgcIDAAAAA==.Crow:BAAALAAECggIAgAAAQ==.',Cu='Cuddlezplz:BAAALAADCgcIDAAAAA==.',Cy='Cydric:BAAALAAECgMIAwAAAA==.',Da='Daarrkstar:BAAALAAECgIIAwAAAA==.Darirn:BAAALAADCgEIAQAAAA==.Darkkseid:BAAALAAECgYIBgAAAA==.Darkwarden:BAAALAAECgQIBAAAAA==.',De='Deanna:BAAALAADCgcIDAAAAA==.Deathkare:BAAALAAECggIEgAAAA==.Decendent:BAEALAAFFAEIAQAAAA==.Delphiia:BAAALAAECgEIAQAAAA==.Demonkare:BAAALAADCgQIBAABLAAECggIEgABAAAAAA==.Demoray:BAACLAAFFIEHAAMEAAUIjhiCAQAbAQAEAAMITxqCAQAbAQAFAAII7BXMBACoAAAsAAQKgRgAAwQACAgVJfoEABcDAAQACAirJPoEABcDAAUABggbIa0PABYCAAAA.Dethrone:BAABLAAECoEXAAMIAAgI0h2TCwCSAgAIAAgI7huTCwCSAgAJAAMIyg9NFQDfAAAAAA==.Deyjavaknadi:BAAALAADCggICQAAAA==.',Di='Dirtydragon:BAAALAAECgMIAwAAAA==.',Dk='Dkmetclaps:BAAALAADCggICAAAAA==.',Do='Dobbythaelf:BAAALAADCgcIBwAAAA==.Donoraginn:BAAALAADCgYIBwABLAADCggICQABAAAAAA==.Donos:BAAALAADCggICQAAAA==.Dorsai:BAAALAADCgQIBwAAAA==.Doughboymacc:BAAALAADCgYIBgAAAA==.',Dr='Drac:BAAALAADCggICAAAAA==.Drark:BAAALAADCgcIBwAAAA==.Drathiel:BAAALAAECgUIBgAAAA==.Draxdorei:BAAALAADCgcIDQAAAA==.Draäzz:BAAALAADCgcIDAAAAA==.Drizztknight:BAAALAADCgMIBAAAAA==.Druidicvenat:BAAALAAECgQIBwAAAA==.Drwho:BAAALAAECgcIDgAAAA==.',Ei='Eikon:BAAALAADCggIDgAAAA==.',El='Elfadwagon:BAABLAAECoEWAAIKAAgIpR2TCACZAgAKAAgIpR2TCACZAgAAAA==.Elfamon:BAAALAAECgMIAwABLAAECggIFgAKAKUdAA==.',Er='Erangar:BAAALAADCgcIEwAAAA==.Erdor:BAAALAADCgUIBQAAAA==.',Es='Esmer:BAAALAADCggIEAAAAA==.',Eu='Euronymous:BAAALAAECggIDwAAAA==.',Ex='Excuses:BAAALAAECggIFQAAAQ==.Exhumina:BAAALAAECgEIAQAAAA==.',Fa='Facestealerr:BAAALAADCggIEQAAAA==.',Fl='Flairrick:BAAALAAECgEIAQAAAA==.Flars:BAAALAADCggIDgAAAA==.',Fo='Fondaloxx:BAAALAADCgcIDAAAAA==.Forsythe:BAAALAADCgQIBAAAAA==.Foshy:BAAALAAECgEIAQAAAA==.',Fr='Freeguy:BAAALAAECgMIAwAAAA==.',Fu='Fuddop:BAAALAAECgUICAAAAA==.Fuddster:BAAALAAECgUIBwAAAA==.',Ga='Gaddess:BAAALAADCgIIAgAAAA==.Gandàlf:BAAALAAECgEIAQAAAA==.Ganymede:BAAALAAECgEIAQAAAA==.',Ge='Geilamaine:BAAALAAECgcIDAAAAA==.',Go='Gobledgook:BAAALAADCgcIBwAAAA==.Gonefishing:BAAALAAECggIEAAAAA==.',Gr='Grellior:BAAALAADCgcICwAAAA==.',Gu='Gukdu:BAAALAADCgcIBwAAAA==.Gummibear:BAAALAAECgEIAgAAAA==.Gurgul:BAAALAADCgIIAgAAAA==.',Gw='Gwiyomi:BAAALAADCgMIAwABLAAECgMIBgABAAAAAA==.',Ha='Haniku:BAAALAADCgcICQAAAA==.Harthoon:BAAALAAECggIEQAAAA==.',He='Hellsing:BAAALAAECgcIEAAAAA==.Helnova:BAAALAADCgQIBQAAAA==.Heneedmilk:BAAALAADCggICgAAAA==.Hey:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.',Hi='Hitshot:BAAALAADCgMIAwAAAA==.',Ho='Holyshmokes:BAAALAADCgIIAgAAAA==.Hotdwarf:BAAALAADCgYIBgAAAA==.',Hr='Hrumm:BAAALAADCggICAAAAA==.',Hu='Hubbabubbles:BAAALAAECgMICAAAAA==.Hullkk:BAAALAAECggIEQAAAA==.Hutchkins:BAAALAAECggIEwAAAA==.',Hy='Hydro:BAAALAAECgYIDAAAAA==.',If='Ifrita:BAAALAADCggICAAAAA==.',Il='Illaandra:BAAALAADCgYIDQABLAAECgUIBgABAAAAAA==.',Im='Imsanity:BAAALAADCgIIAgAAAA==.',In='Inseng:BAAALAAECgMIBgAAAA==.Invasion:BAAALAAECgYIBgAAAA==.',Ir='Iridescent:BAAALAADCgcIBwAAAA==.',Ja='Jahde:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Jaina:BAAALAADCgcIDgAAAA==.Jassykins:BAAALAAECgEIAQAAAA==.',Je='Jeewop:BAAALAADCgEIAQAAAA==.',Ji='Jinjerr:BAAALAAECgMIAwAAAA==.',Jo='Joanofarc:BAAALAAECgYICQAAAA==.Joloc:BAAALAAECgIIAgAAAA==.',Ju='Juancarlos:BAAALAADCgcIBwAAAA==.Jueles:BAAALAAECgMIAwAAAA==.',Ka='Kaboome:BAAALAADCgcICwAAAA==.Kalamara:BAAALAADCggIJQAAAA==.Kalrosa:BAAALAAECgQICAAAAA==.Kano:BAAALAADCgIIAgAAAA==.',Ke='Kebob:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.Kelaa:BAAALAADCgcIBwABLAADCgcICwABAAAAAA==.Keladrasong:BAAALAADCgYICAAAAA==.Kerlis:BAAALAAECgIIAgAAAA==.Kermo:BAAALAAECgMIAwAAAA==.',Kh='Khamado:BAAALAADCgEIAQAAAA==.',Ki='Kiizo:BAAALAAECgEIAQAAAA==.',Kn='Knaveztine:BAAALAADCggIGQAAAA==.',Ko='Koltaris:BAAALAAECggIEQAAAA==.Koltarix:BAAALAADCgIIAgABLAAECggIEQABAAAAAA==.Kookymonster:BAAALAAECgYIBgAAAA==.Kos:BAAALAAECggIDgAAAA==.',Ku='Kuragaru:BAAALAAECgcIDwAAAA==.',Le='Leese:BAAALAADCggIFgAAAA==.Leftraro:BAAALAAECgEIAQAAAA==.Leiyna:BAAALAAECggIEQAAAA==.Leovarde:BAAALAADCgUICAABLAAECgYICQABAAAAAA==.Leovarne:BAAALAADCgIIAgABLAAECgYICQABAAAAAA==.Lester:BAAALAAECgIIBAAAAA==.',Li='Lidrael:BAAALAAECgMIAwAAAA==.Lilihunt:BAAALAADCgQIBAAAAA==.Liliria:BAAALAAECggIEQAAAA==.',Lj='Ljadin:BAAALAAECgMIAwAAAA==.',Ll='Lloreth:BAAALAAECgMIBgAAAA==.Lloydinspace:BAAALAADCggICAAAAA==.',Lo='Lockwood:BAAALAAECgMIBgAAAA==.Lolasareena:BAAALAAECgMIAwAAAA==.Lorelei:BAAALAAECgEIAQAAAA==.Lorrellia:BAAALAADCgcIFgAAAA==.',Lu='Lucariõ:BAACLAAFFIEFAAILAAMIBxhpAgARAQALAAMIBxhpAgARAQAsAAQKgRgAAgsACAg6G04KAIUCAAsACAg6G04KAIUCAAAA.Lucenttopaz:BAAALAADCgMIBAAAAA==.Lucydream:BAAALAADCgcIBwAAAA==.Lunanova:BAAALAADCgMIAwAAAA==.',Ly='Lyllies:BAAALAAECggIEAAAAA==.',Ma='Malkir:BAAALAADCggIDgAAAA==.Marjorieb:BAAALAADCggICAAAAA==.Marunji:BAAALAAECgEIAQAAAA==.Mashir:BAAALAAECgcIEAAAAA==.Matcauthon:BAAALAADCgYIAQAAAA==.',Me='Meekogaia:BAAALAAECgcIEAAAAA==.Meleys:BAAALAADCggIDwAAAA==.',Mm='Mmbear:BAAALAADCggICAABLAAECggIFgAMAFggAA==.',Mo='Momiji:BAAALAADCgcICgAAAA==.Monarca:BAAALAADCgIIAgAAAA==.Monett:BAAALAAECgQIBQAAAA==.Montkriege:BAAALAADCgcICQAAAA==.Mookera:BAAALAADCgYIBgAAAA==.Moonwarden:BAAALAAECgEIAQAAAA==.Moxxie:BAAALAAECgEIAQAAAA==.',Mu='Murfie:BAAALAAECgIIBAAAAA==.',My='Myllah:BAAALAAECgcIDgAAAA==.Mythosrex:BAAALAADCgQIBAAAAA==.',['Mì']='Mìr:BAAALAAECggIEQAAAA==.',Na='Nagoo:BAAALAAECggIEQAAAA==.Naitho:BAAALAADCggICAAAAA==.Nashness:BAAALAAECgQIBQAAAA==.Natharion:BAAALAAECggIDwAAAA==.Natures:BAAALAADCgMIAwAAAA==.',Ne='Nezar:BAAALAAECgEIAQAAAA==.',Ni='Nitazuresh:BAAALAADCggIFAAAAA==.',Nn='Nn:BAAALAAECgEIAQAAAA==.',No='Notgoose:BAAALAAECgMIAwABLAAECggIEAABAAAAAA==.',Nu='Nuckinphutz:BAAALAADCgYIBgAAAA==.',['Nè']='Nègan:BAAALAAECgMIAwAAAA==.',['Nê']='Nêmêsîs:BAAALAADCgEIAQAAAA==.',Od='Odinrex:BAAALAAECggIAgAAAA==.',Ol='Oldpatriot:BAAALAADCggIDQAAAA==.',Os='Osirys:BAAALAADCggICQAAAA==.',Pa='Pallypaladin:BAABLAAECoEWAAIMAAgIWCBuDQCtAgAMAAgIWCBuDQCtAgAAAA==.Partywolf:BAAALAADCgcIDQAAAA==.',Pe='Pearagon:BAAALAADCgYICgAAAA==.Peelinsteel:BAAALAAECgcIEAAAAA==.',Pl='Plumper:BAAALAADCggIFQAAAA==.',Po='Polarnomad:BAAALAAECggIAgAAAA==.Popsicles:BAAALAAECgYIDQAAAA==.',Pr='Procreeper:BAAALAADCgMIAwABLAADCgUIBQABAAAAAA==.Proppant:BAAALAAECgIIBAAAAA==.',Ps='Psyop:BAAALAAECgMICQAAAA==.',Ra='Ragerrond:BAAALAADCgcICwAAAA==.Ragewing:BAAALAAECggIEQAAAA==.Rastputin:BAAALAADCgYIBwAAAA==.Razuvious:BAAALAADCgcIEQAAAA==.Razzalatath:BAAALAADCggIFAAAAA==.',Re='Retdead:BAAALAAECgEIAQAAAA==.',Rh='Rhodraco:BAAALAAECgEIAQAAAA==.',Ri='Riffraff:BAAALAADCggICAABLAAECggIEQABAAAAAA==.Riktorr:BAAALAADCgcIDgAAAA==.Riqochet:BAAALAADCgQIBgAAAA==.',Ro='Rolandrex:BAAALAADCgUIBQAAAA==.Romulusinc:BAAALAAECgEIAQAAAA==.Rosabee:BAAALAAECgQIBwAAAA==.',Ru='Rustyrose:BAAALAAECgMIAwABLAAECgMIAwABAAAAAA==.',Sa='Saint:BAAALAAECgMIAwAAAA==.Sandycheeks:BAAALAADCgcICAAAAA==.Satanica:BAAALAADCgQIBAABLAAECgYIFwAHAPkNAA==.Satoru:BAAALAADCgIIAgAAAA==.Sauce:BAAALAAECgYICgAAAA==.',Sc='Scrubz:BAAALAAECgUICAAAAA==.',Se='Selanoris:BAAALAAECgEIAQAAAA==.Senile:BAAALAAECgEIAQAAAA==.Serenitymoon:BAAALAADCgEIAQAAAA==.',Sh='Shadoweaver:BAAALAADCggICAAAAA==.Shadowshot:BAAALAADCggIDwAAAA==.Shadówglider:BAAALAADCggIFAAAAA==.Shamallaman:BAAALAAECgUIBwAAAA==.Sharana:BAAALAAECgIIBAAAAA==.Sheyoni:BAAALAADCgcIDAAAAA==.Shreck:BAAALAAECgQIBgAAAA==.Shrewmaster:BAAALAADCgQIBQAAAA==.Shroud:BAAALAAECgQIBAAAAA==.',Sk='Skinrot:BAAALAAECgcIEAAAAA==.',So='Soeki:BAAALAAECgEIAQAAAA==.Softnsquishy:BAAALAADCggICAAAAA==.Soullove:BAAALAAECgMIAwAAAA==.Soulviver:BAAALAAECgMIAwAAAA==.',Sp='Spen:BAAALAADCgcICAAAAA==.Spure:BAAALAAECgIIAgAAAA==.',Sq='Squishles:BAAALAADCggIFAAAAA==.Squishydruid:BAAALAAECggIEQAAAA==.',St='Starstreak:BAAALAADCgYICgAAAA==.Stormhammer:BAAALAADCgQIBwAAAA==.',Sw='Swiftpaws:BAAALAADCggIDAAAAA==.Swolegoose:BAAALAAECggIEAAAAA==.',Sx='Sxynun:BAAALAADCgIIAgAAAA==.',Sy='Sychoticc:BAAALAADCgMIAwAAAA==.Syncophat:BAAALAAECgMIAwAAAA==.',Ta='Talace:BAAALAADCgIIAgAAAA==.Tamsinblight:BAAALAADCggICgAAAA==.Tarrzok:BAAALAADCgcIBwABLAAECggIEQABAAAAAA==.',Te='Tellanji:BAAALAAECgMIAwAAAA==.Tempani:BAAALAAECgEIAQAAAA==.Terrorizing:BAAALAADCgcIBwABLAAECggIEQABAAAAAA==.',Th='Thrakara:BAAALAAECggIEAAAAA==.Thunderhorns:BAAALAAECgEIAQAAAA==.Thyrissa:BAAALAADCggIDgAAAA==.',To='Toaster:BAAALAAECggIEQAAAA==.Torapawz:BAAALAADCgcIBwAAAA==.',Tr='Triune:BAAALAAECgUIBwAAAA==.',Ts='Tsuo:BAAALAAECggIEQAAAA==.',Ty='Tymptriss:BAAALAAECgEIAQAAAA==.',Ul='Ulthrane:BAAALAAECgIIBAAAAA==.',Um='Umbrage:BAAALAADCggICAABLAAECggIEQABAAAAAA==.Umbren:BAAALAAECgUICQAAAA==.',Us='Usefulmelee:BAAALAADCgYIBgABLAAECggIEQABAAAAAA==.',Va='Valartha:BAAALAADCggIFAAAAA==.',Ve='Velanya:BAAALAAECgYIBgAAAA==.Velsea:BAAALAADCggICwAAAA==.Velstadt:BAAALAAECgIIBAAAAA==.Vengevhol:BAAALAAECgMIAwAAAA==.Venotu:BAAALAAECgEIAQAAAA==.Veronor:BAAALAADCggIDAABLAAECgIIBAABAAAAAA==.',Vi='Viviel:BAAALAAECgMIBQAAAQ==.',Vy='Vyctus:BAAALAADCggIDAAAAA==.',Wa='Walcoll:BAAALAADCgIIAgAAAA==.Warmongral:BAAALAADCgQIBAAAAA==.Wattheyneed:BAAALAAECgEIAQAAAA==.',Wi='Windcrow:BAAALAADCgYICgAAAA==.Wingsaber:BAAALAAECgcIDgAAAA==.Wisename:BAAALAADCggIFQAAAA==.',Wo='Woolala:BAAALAADCgMIAwABLAAECggIEAABAAAAAA==.',Wr='Wrathran:BAAALAADCggIDgAAAA==.',Xo='Xorodk:BAAALAADCgcICwAAAA==.',Ya='Yaztok:BAAALAAECgIIAgAAAA==.',Ye='Yerehmi:BAAALAADCgQIBAAAAA==.',Yv='Yvendria:BAAALAAECgIIBAAAAA==.',Za='Zacnafeen:BAAALAADCgQIBAAAAA==.Zaier:BAAALAAECggIEQAAAA==.Zarael:BAAALAADCgIIAgAAAA==.',Ze='Zealo:BAAALAADCgQIBQAAAA==.Zeovardin:BAAALAAECgYICQAAAA==.',Zh='Zhundrenga:BAAALAADCggIFAAAAA==.',Zi='Zinik:BAAALAADCggIGAAAAA==.',['Zï']='Zïggy:BAAALAAECgIIAgAAAA==.',['År']='Åres:BAAALAADCgQIBwAAAA==.',['ßä']='ßäbaracus:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end