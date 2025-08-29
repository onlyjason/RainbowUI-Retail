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
 local lookup = {'Unknown-Unknown','Monk-Mistweaver',}; local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aartje:BAAALAADCggIDQAAAA==.',Ab='Abduo:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',Ad='Aduin:BAAALAADCgEIAQAAAA==.',Ae='Aelita:BAAALAADCgcICwAAAA==.Aellita:BAAALAADCgcIDQAAAA==.Aellori:BAAALAADCggIDgAAAA==.',Af='Afkinlife:BAAALAADCgIIAgAAAA==.',Ak='Akir:BAAALAADCgcIBwAAAA==.Aksafiya:BAAALAAECgMIAwAAAA==.',Al='Alandras:BAAALAAECgMIBAAAAA==.Alaras:BAAALAADCgcIDgAAAA==.Allrianne:BAAALAAECgEIAQAAAA==.Allyriae:BAAALAAECgIIBAAAAA==.Alphá:BAAALAADCgUIBQAAAA==.Althor:BAAALAAECgMIBAAAAA==.Altraxious:BAAALAADCgMIAwAAAA==.',An='Andoros:BAAALAAECgMIBQAAAA==.',Ap='Apheron:BAAALAAECgMIBAAAAA==.Apollimy:BAAALAAECggICAAAAA==.Applebow:BAAALAAECgMIBAAAAA==.',Ar='Archaiden:BAAALAADCgYIBgAAAA==.Archee:BAAALAAECgEIAQAAAA==.Arenothor:BAAALAADCgYICAAAAA==.Arioch:BAAALAADCgcIBwAAAA==.Arknova:BAAALAADCgcICgAAAA==.Armas:BAAALAAECgEIAQAAAA==.Arylin:BAAALAAECgMIBAAAAA==.',As='Asheram:BAAALAADCgcIBwAAAA==.Asnabel:BAAALAADCggIFAAAAA==.Aspirate:BAAALAAECgEIAQAAAA==.',Ay='Ayambe:BAAALAADCgIIAwAAAA==.',Ba='Babygirll:BAAALAAECgMIBAAAAA==.Balinh:BAAALAADCggIEAAAAA==.Bandiama:BAAALAADCgIIAgAAAA==.Bazibaz:BAAALAADCgQIBAAAAA==.',Be='Beffytreehug:BAAALAADCgEIAQABLAAECgcIEgABAAAAAA==.Belixe:BAAALAADCgEIAQAAAA==.Bendeye:BAAALAADCgIIAgAAAA==.Betanya:BAAALAADCggICAABLAAECggICAABAAAAAA==.',Bl='Blee:BAAALAADCggIFQAAAA==.',Bo='Boomhauer:BAAALAAECgMIBAAAAA==.',Br='Braelia:BAAALAAECgMIAwAAAA==.Brannigan:BAAALAAECgEIAQAAAA==.Brucecambull:BAAALAADCggIDgAAAA==.',Bu='Bubblepopper:BAAALAAECgYICgAAAA==.Bunky:BAAALAADCggIDwAAAA==.',Ca='Calenbraga:BAAALAADCggIMQAAAA==.Calisim:BAAALAADCggIFQAAAA==.Cassamaria:BAAALAADCggIEgAAAA==.Cataryn:BAAALAADCggIEAAAAA==.Catt:BAAALAADCggIEAAAAA==.',Ce='Cellebur:BAAALAADCggIFQAAAA==.Ceta:BAAALAAECgMIBAAAAA==.',Ch='Cheww:BAAALAADCgIIAgAAAA==.',Co='Corgï:BAAALAAECgUICAAAAA==.Corswain:BAAALAADCgYIBgAAAA==.',Cr='Crusatyr:BAAALAADCgUIBQABLAADCggIFgABAAAAAA==.Cruxx:BAAALAAECgMIAwAAAA==.',Cy='Cyanheart:BAAALAAECgMIAwAAAA==.Cyroka:BAAALAADCggIFAAAAA==.Cyrr:BAAALAADCgcICgAAAA==.Cytroncutoff:BAAALAADCgcIEgAAAA==.',Da='Dalastish:BAAALAAECgEIAQAAAA==.Dalizar:BAAALAADCgYICwAAAA==.Damia:BAAALAAECgMIBAAAAA==.Danzig:BAAALAAECgMIAwAAAA==.Darsithis:BAAALAAECgMIBAAAAA==.',De='Delvarrieth:BAAALAADCggIFwAAAA==.Demonicblade:BAAALAADCggIFAAAAA==.Demonicbolt:BAAALAADCgYICwAAAA==.Demzy:BAAALAAECgIIAwAAAA==.Denathis:BAAALAADCgMIAwAAAA==.Deneba:BAAALAADCgEIAgAAAA==.Dercuur:BAAALAADCggIDgAAAA==.Desala:BAAALAADCgcIBwAAAA==.',Dh='Dhari:BAAALAADCgcICwAAAA==.',Do='Doddie:BAAALAADCggICgAAAA==.Doomhunter:BAAALAADCgEIAQAAAA==.Dotur:BAAALAADCggIFQAAAA==.',Dr='Dracspriggs:BAAALAADCgIIAgAAAA==.Drainmee:BAAALAADCgYICAAAAA==.Dregoth:BAAALAAECgMIAwAAAA==.Drzaya:BAAALAADCgcIBwAAAA==.',Ea='Eathur:BAAALAADCgYIBgAAAA==.',Ed='Edomrawad:BAAALAADCgQIBAAAAA==.',El='Elddib:BAAALAADCgEIAQAAAA==.Elynth:BAAALAADCggIEAAAAA==.',Fa='Falunaria:BAAALAADCgIIAgAAAA==.Falunia:BAAALAAECgEIAgAAAA==.Fangren:BAAALAADCgYICAAAAA==.Faragorn:BAAALAAECgMIBAAAAA==.Farrseer:BAAALAADCggIDgAAAA==.',Fe='Felscythe:BAAALAADCggIFAAAAA==.Feorana:BAAALAADCgcIDQAAAA==.Feres:BAAALAADCggIFgAAAA==.Feresdenn:BAAALAADCggICAAAAA==.',Fi='Fialova:BAAALAAECgMIAwAAAA==.Fidickittie:BAAALAADCgcIBwAAAA==.Fierrastar:BAAALAAECgMIAwAAAA==.Finshao:BAAALAADCggIFQAAAA==.',Fl='Flemish:BAAALAADCgcIDAAAAA==.Flipalicious:BAAALAAECgQIBwAAAA==.',Fr='Freyalise:BAAALAADCggIDgAAAA==.Frostycarbon:BAAALAAECgMIBAAAAA==.Frostyrufio:BAEALAADCggIJgAAAA==.',Fu='Furywalk:BAAALAADCggICwAAAA==.',['Få']='Fåtthor:BAAALAADCggIEwAAAA==.',Ga='Gaia:BAAALAADCggIEQAAAA==.',Gi='Gianavel:BAAALAADCggIFAAAAA==.Gibzz:BAAALAADCgYIBgAAAA==.Ginomage:BAAALAAECgMIAwAAAA==.',Gr='Granosh:BAAALAADCgcIDgAAAA==.Grazok:BAAALAADCggIEAAAAA==.Grimslaide:BAAALAADCgcIEQAAAA==.Grubetsell:BAAALAADCgYIBgABLAAECgcIDQABAAAAAA==.Grubetsella:BAAALAAECgcIDQAAAA==.Grugachur:BAAALAADCggIFwAAAA==.Grumper:BAAALAAECgMIAwAAAA==.Grumpÿ:BAAALAAECgEIAQAAAA==.',Gu='Guenhywvar:BAAALAADCggIEAAAAA==.',Ha='Hanoumatoi:BAAALAAECgEIAQAAAA==.Haralambos:BAAALAADCggIFQAAAA==.Haralogain:BAAALAADCgYIBgABLAADCggIFQABAAAAAA==.Harel:BAAALAADCggIDgAAAA==.',He='Helbrede:BAAALAADCgQIBAAAAA==.Heledosia:BAAALAADCggIDgAAAA==.Hestiamajere:BAAALAADCgcIDQAAAA==.Heyokagi:BAAALAAECgMIBAAAAA==.',Hi='Himothyjones:BAAALAAECgMIBAAAAA==.',Ho='Hordkilla:BAAALAADCggIFgAAAA==.Hownowbrncw:BAAALAAECgMIAwAAAA==.',Hu='Hukkari:BAAALAADCgcIBwAAAA==.',Hy='Hyce:BAAALAAECgMIBAAAAA==.',Ic='Ichaival:BAAALAADCgcICwAAAA==.',Ih='Ihavenoname:BAAALAADCgQIBAAAAA==.',Im='Imabirdhaww:BAAALAADCggICAABLAAECgMIBAABAAAAAQ==.Imathdal:BAAALAAECgMIAwAAAA==.',In='Inow:BAAALAAECgIIAgAAAA==.',Is='Iselian:BAAALAAECgMIAwAAAA==.',Jb='Jbprimero:BAAALAAECgEIAQAAAA==.Jbshami:BAAALAADCggIEAAAAA==.',Je='Jeb:BAAALAADCggIDwAAAA==.Jeffurry:BAAALAADCggIDwAAAA==.Jenzak:BAAALAAECgMIBAAAAA==.Jetfires:BAAALAAECgYICAAAAA==.',Ji='Jinger:BAAALAADCggIDQAAAA==.',Jo='Joeroguin:BAAALAAECgEIAQAAAA==.Jordun:BAAALAAECgEIAQAAAA==.',Ka='Kaedren:BAAALAADCgIIAwAAAA==.Kaelorien:BAAALAAECgMIBAAAAA==.Kaetta:BAAALAADCggIEAAAAA==.Kaguyå:BAAALAAECgMIBAAAAA==.Kalypsa:BAAALAADCgYICAAAAA==.Kardanis:BAAALAADCggIEAAAAA==.Kashe:BAAALAADCggIFQAAAA==.Kasume:BAAALAADCggIFgAAAA==.Katavia:BAAALAADCggIEAAAAA==.Katrazath:BAAALAADCgMIAwAAAA==.Kaydencia:BAAALAADCgEIAQAAAA==.Kayonia:BAAALAADCgEIAQAAAA==.',Ke='Kevshaman:BAAALAADCgcIDAAAAA==.',Ki='Kikona:BAAALAADCgcIBwAAAA==.Killserenity:BAAALAAECgcIEgAAAA==.Kivrin:BAAALAADCgEIAQAAAA==.',Kr='Krimsyn:BAAALAAECgEIAQAAAA==.Kringlë:BAAALAAECgMIBAAAAA==.Kritish:BAABLAAECoEXAAICAAgIlg+eDADEAQACAAgIlg+eDADEAQAAAA==.',Ku='Kuunko:BAAALAADCgUIBQAAAA==.',Ky='Kymma:BAAALAAECgMIBAAAAA==.',La='Lagoriatsua:BAAALAADCggIEAAAAA==.Launchpad:BAAALAADCgcIDgAAAA==.',Le='Leafamealone:BAAALAAECgYICQAAAA==.Leilau:BAAALAAECgMIBAAAAA==.Leinikki:BAAALAADCggIDwAAAA==.Leiris:BAAALAAECgMIBAAAAA==.Lestal:BAAALAADCggIFQAAAA==.Letifer:BAAALAADCgIIAgAAAA==.Leve:BAAALAADCgEIAQAAAA==.',Li='Lightbeard:BAAALAADCggIFQAAAA==.Lightforge:BAAALAAECgMIAwAAAA==.Lightsgrasp:BAAALAADCgQIBAAAAA==.Lightwalker:BAAALAADCggIDgAAAA==.',Lo='Lorion:BAAALAADCgUIBQAAAA==.Lorredain:BAAALAADCgIIAwAAAA==.',Lu='Lunamaris:BAAALAADCgYICgAAAA==.Lutze:BAAALAADCggIDgAAAA==.',Ly='Lyshai:BAAALAAECgcIDwAAAA==.',Ma='Magamon:BAAALAADCggIEAAAAA==.Malfuriia:BAAALAADCggIFwAAAA==.Mamboke:BAAALAADCgcIDQAAAA==.Margerdria:BAAALAADCgcIFAAAAA==.Marien:BAAALAADCggIFQAAAA==.Maxowen:BAAALAADCggIFwAAAA==.',Me='Mearadan:BAAALAAECgMIAwAAAA==.Meatsweats:BAAALAADCggIDgAAAA==.Megashira:BAAALAADCgcIDQAAAA==.Mekh:BAAALAADCggIFwABLAAECgcIDwABAAAAAA==.Melanara:BAAALAADCggIDgAAAA==.',Mi='Milligan:BAAALAADCggIEAAAAA==.',Mj='Mjsage:BAAALAADCggIEAAAAA==.',Mm='Mmeow:BAAALAADCgYICAAAAA==.',Mo='Moirine:BAAALAADCggIFwAAAA==.Monstertruck:BAAALAADCggIDwAAAA==.Moonflowers:BAAALAAFFAIIAgAAAA==.',Mu='Mustikka:BAAALAADCggIEgAAAA==.',My='Myuriyanka:BAAALAAECgIIAgAAAA==.Myzrian:BAAALAAECgEIAQAAAA==.',Na='Nadron:BAAALAADCgcIDQAAAA==.Nagualli:BAAALAADCggIEAAAAA==.Naiacin:BAAALAAECgYIDAAAAA==.Naieve:BAAALAAECgMIBAABLAAECgYIDAABAAAAAA==.Naturesmitch:BAAALAAECgEIAQAAAA==.',Ne='Negargra:BAAALAADCgUIBQAAAA==.Nephandus:BAAALAADCggIDgAAAA==.',Ni='Nikooli:BAAALAADCgcIDQAAAA==.',No='Noopsie:BAAALAADCggIGwAAAA==.Nooters:BAAALAAECgUIBwAAAA==.',Ob='Oberonny:BAAALAADCgcIDgAAAA==.',Od='Oderica:BAAALAADCggIDgAAAA==.',Ol='Olinar:BAAALAADCgIIAgAAAA==.',Or='Orongosh:BAAALAADCgQIBAAAAA==.',Os='Oscarmikey:BAAALAAECgcIEgAAAA==.',Ot='Ottoshot:BAAALAADCggIFwAAAA==.',Pa='Pandeism:BAAALAADCggIFgAAAA==.Parkenis:BAAALAAECgMIAwAAAA==.',Pe='Peanutbritle:BAAALAADCggIEAAAAA==.',Ph='Phranknbeans:BAAALAAECgUICwAAAA==.',Pi='Pixiey:BAAALAADCggIDgAAAA==.',Pr='Prism:BAAALAADCgYIBgAAAA==.',Qu='Quorin:BAAALAADCggICAAAAA==.',Ra='Raen:BAAALAADCgEIAQAAAA==.Raez:BAAALAADCggIDQAAAA==.Rageaholik:BAAALAAECgEIAQAAAA==.Ramshiv:BAEALAAECgEIAQAAAA==.Rashona:BAAALAADCgYIBgAAAA==.',Re='Rezmage:BAAALAAECgUICAAAAA==.',Rh='Rhage:BAAALAAECgEIAQAAAA==.',Ri='Riahana:BAAALAAECgIIAgAAAA==.Riggin:BAAALAAECgMIAwAAAA==.Rionach:BAAALAAECgMIAwAAAA==.',Ro='Rooroo:BAAALAADCgYIBgAAAA==.Rowani:BAAALAAECgMIBAAAAA==.',Ru='Runningelk:BAAALAAECgMIAwAAAA==.Runscapemain:BAAALAADCggIEAAAAA==.',Ry='Ryeti:BAAALAADCgYICwAAAA==.Rysonal:BAAALAADCggICAABLAADCggICAABAAAAAA==.',Sa='Saintulrick:BAAALAAECgIIAgAAAA==.Sanitas:BAAALAAECgMIBgAAAA==.',Se='Seeyen:BAAALAAECgcIEAAAAA==.Seraphi:BAAALAAECgMIAwAAAA==.',Sh='Shadowhunder:BAAALAAECgEIAQAAAA==.Shammy:BAAALAADCgcIAwAAAA==.Shankalot:BAAALAADCgEIAQAAAA==.Shiftingsand:BAAALAADCggICAAAAA==.Shihoru:BAAALAADCgcIBwAAAA==.Ships:BAAALAAECgYICgAAAA==.',Si='Sinthoras:BAAALAAECgIIAgAAAA==.',Sj='Sjðfn:BAAALAADCggIBwABLAAECggICAABAAAAAA==.',Sk='Skibbie:BAAALAAECgcIEgAAAA==.',Sl='Slayvanas:BAAALAADCggIDwAAAA==.Slumbers:BAAALAAECgIIAgAAAA==.',So='Solinius:BAAALAAECgMIAwAAAA==.Sooyoung:BAAALAADCggICwAAAA==.Sorvina:BAAALAAECgIIAwAAAA==.Soulflame:BAAALAAECgIIAgAAAA==.',Sp='Spottedcoat:BAAALAADCggIEAAAAA==.',St='Starpath:BAAALAAECgMIAwAAAA==.Stregnor:BAAALAAECgMIAwAAAA==.Styggi:BAAALAADCgUIBQAAAA==.Stygy:BAAALAADCggICwAAAA==.',Su='Sumyunguy:BAAALAAECgYICgAAAA==.',Sv='Sveñ:BAAALAADCggICgAAAA==.',Sy='Syllenne:BAAALAAECgcIDwAAAA==.Sylv:BAAALAADCggIFQAAAA==.',Ta='Tachie:BAAALAADCggIEwAAAA==.Taele:BAAALAAECgMIAwAAAA==.Taiche:BAAALAAECgMIBAAAAA==.Taiuru:BAAALAAECgUICAAAAA==.Tamalpais:BAAALAADCgcIDQAAAA==.Tareyn:BAAALAADCgYIBgAAAA==.Tarvah:BAAALAADCgMIAwAAAA==.Taza:BAAALAADCgUIBQAAAA==.',Te='Teak:BAAALAADCgYIBgAAAA==.Tenderlion:BAAALAADCggICAAAAA==.Tevian:BAAALAAECgcIDwAAAA==.Tezzerae:BAAALAADCggIEwAAAA==.',Th='Thaesan:BAAALAAECgMIBwAAAA==.Theistica:BAAALAAECgIIAgAAAA==.Therin:BAAALAAECgMIBAAAAA==.',Ti='Tikitavi:BAAALAADCggIDwAAAA==.Tinyclaw:BAAALAADCgcIBwAAAA==.Tizara:BAAALAADCgEIAQAAAA==.',To='Tonas:BAAALAADCgEIAQAAAA==.Toofast:BAAALAAECgEIAQAAAA==.',Tr='Trydora:BAAALAADCggIEgAAAA==.',Un='Unsure:BAAALAADCgYIBgAAAA==.',Ut='Utheli:BAAALAAECgYIBgAAAA==.',Va='Vaildora:BAAALAADCgcIDQABLAADCggIEwABAAAAAA==.Valdra:BAAALAAECgMIBAAAAA==.',Ve='Velidraena:BAAALAADCgEIAQAAAA==.',Vi='Viralwhammy:BAAALAAECgEIAQAAAA==.',Vl='Vlonet:BAAALAAECgYICQAAAA==.',Vn='Vnasty:BAAALAAECggIEgAAAA==.',['Vì']='Vì:BAAALAAECgUIBwAAAA==.',Wa='Watsworth:BAAALAADCgYIBgAAAA==.',Wh='Whelp:BAAALAAECgMIAwAAAA==.Whiriin:BAAALAADCgEIAQAAAA==.',Wi='Wilken:BAAALAAECgEIAQAAAA==.Wink:BAAALAADCggIDgAAAA==.',Wr='Wreckoner:BAAALAADCggIEAAAAA==.',Xa='Xannah:BAAALAADCgIIAwAAAA==.',Xi='Xinthos:BAAALAADCgUIBQAAAA==.',Yk='Yknub:BAAALAAECgEIAQAAAA==.',Za='Zamael:BAAALAADCgYIBgAAAA==.Zanagor:BAAALAAECgMIAwAAAA==.Zarathan:BAEALAADCgQIBAAAAA==.Zarathoszan:BAAALAAECgIIAgAAAA==.Zareena:BAAALAADCggICAAAAA==.Zayaadh:BAAALAAECgcICAAAAA==.',Ze='Zelgaddis:BAAALAAECgMIAwAAAA==.Zenbird:BAAALAAECgMIBAAAAQ==.Zenfish:BAAALAAECgcICQAAAA==.',Zu='Zulinn:BAAALAADCgcIBwAAAA==.Zurgen:BAAALAAECgMIBAAAAA==.',Zz='Zzyzzxi:BAAALAADCgcIBwAAAA==.',['Êc']='Êclipse:BAAALAADCggIFgAAAA==.',['Øm']='Ømëgá:BAAALAADCgcIDQAAAA==.',['Ýu']='Ýui:BAAALAADCgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end