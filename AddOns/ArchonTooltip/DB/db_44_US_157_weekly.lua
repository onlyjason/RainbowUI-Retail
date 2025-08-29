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
 local lookup = {'Unknown-Unknown','Mage-Arcane','DeathKnight-Blood','Mage-Frost','Priest-Holy','DemonHunter-Havoc','Warlock-Demonology','Druid-Feral','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Warrior-Fury','Shaman-Restoration','Mage-Fire','Evoker-Devastation','Hunter-Marksmanship','Hunter-BeastMastery',}; local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=44,date='2025-08-29',data={Aa='Aaralia:BAAALAAECgcIEAAAAA==.',Ab='Absolutezero:BAAALAAECgIIAgAAAA==.Abyssdark:BAAALAAECgMIBAAAAA==.',Am='Amerihc:BAAALAADCgcICAAAAA==.',An='Andarick:BAAALAADCgUIBQAAAA==.',Ar='Aramist:BAAALAADCgcIDQAAAA==.',As='Ashika:BAAALAAECgcIEgAAAA==.Ashikahammer:BAAALAADCgcIBwAAAA==.Ashtaroth:BAAALAADCgcICwABLAADCggIEgABAAAAAA==.',Ba='Baehyun:BAAALAAECgcIDQABLAAECggIHwACACAlAA==.',Be='Bearyjane:BAAALAAECgEIAQAAAA==.Beastalon:BAAALAADCgIIAgAAAA==.',Bi='Bigchonky:BAAALAAECgEIAQAAAA==.Bigspicyd:BAAALAADCgMIAwAAAA==.',Bl='Blegh:BAAALAAECgYIBgAAAA==.Blodkuil:BAAALAAECggIAwAAAA==.Bloodedge:BAAALAAECgQIBwAAAA==.',Bo='Bogawha:BAAALAAECgEIAQAAAA==.Bolock:BAAALAADCgcIBwAAAA==.',Br='Brentatoes:BAAALAADCgcICAAAAA==.',Bu='Bungeholio:BAAALAAECgEIAQAAAA==.Butterhoof:BAAALAADCgMIAwABLAAECgcIDwABAAAAAA==.',Ca='Cannelle:BAAALAAECgYIBgAAAA==.Carden:BAAALAAECgMIBQAAAA==.Carul:BAAALAADCggICAAAAA==.',Ch='Charlas:BAAALAAECgcIDAAAAA==.Chillywillie:BAAALAADCgUIBQAAAA==.Chosandik:BAAALAADCggICAAAAA==.',Ci='Cigam:BAAALAADCgcIBwAAAA==.',Cl='Clintbarton:BAAALAAECgQIBwAAAA==.',Co='Corvenger:BAAALAADCgMIAwAAAA==.Corvenus:BAAALAAECgEIAQAAAA==.',Ct='Cthullu:BAAALAAECgcIDwAAAA==.',Cu='Culebra:BAAALAADCggICAAAAA==.',['Cá']='Cálcár:BAAALAADCgUICQAAAA==.',['Cø']='Cøldshoulder:BAAALAAECgMIAwAAAA==.',Da='Dailyalice:BAAALAAECgMIBAAAAA==.Darcmatter:BAAALAAECgYIDAAAAA==.',De='Deathdrag:BAAALAADCgYIBgAAAA==.Deathpooden:BAABLAAFFIEFAAIDAAMI+BI/AQDwAAADAAMI+BI/AQDwAAAAAA==.Deepstate:BAAALAADCgcICwAAAA==.Demistab:BAAALAADCgcICQAAAA==.Demonäde:BAAALAAECgIIAgAAAA==.Demoña:BAAALAAECgMIBwAAAA==.Denise:BAEALAADCgYIBgAAAA==.',Di='Dima:BAAALAAECgUIBQAAAA==.Dithy:BAAALAAECgEIAQAAAA==.',Do='Donavon:BAAALAADCgcIBwAAAA==.Donutboy:BAAALAADCgcIBwAAAA==.',Dr='Drackothyr:BAAALAAECgYICQAAAA==.Draepray:BAAALAADCgMIAwAAAA==.Dragôn:BAAALAAECgIIAgAAAA==.Dravien:BAAALAAECgEIAQAAAA==.Drawshock:BAAALAAECgYICQAAAA==.Drunkpooden:BAAALAAECgEIAQAAAA==.',Du='Dugmaren:BAAALAADCgIIAgABLAAECgcIEgABAAAAAA==.',El='Elamshinae:BAAALAADCggICAAAAQ==.',Em='Emmaslight:BAAALAADCgYIBgAAAA==.',Ep='Epicdude:BAAALAAECgYIBgAAAA==.',Er='Erragorn:BAAALAAECgMIBAAAAA==.',Fa='Farity:BAAALAADCgEIAQAAAA==.',Fe='Fearzlol:BAAALAAECgcIEgAAAA==.Felbo:BAAALAAECgEIAQAAAA==.Feltank:BAAALAADCgMIBAABLAAECgcIDwABAAAAAA==.',Fi='Fisto:BAAALAADCgUIBQAAAA==.',Fl='Flanagan:BAAALAADCgcICAAAAA==.Flare:BAAALAAECgUICAAAAA==.',Fu='Fuuke:BAAALAADCggIFwAAAA==.',Ga='Gailinn:BAAALAAECgEIAQAAAA==.Ganon:BAAALAAECgMIAwAAAA==.Gayhyun:BAABLAAECoEfAAMCAAgIICUpAwBGAwACAAgIICUpAwBGAwAEAAEIFg8ORQAyAAAAAA==.',Go='Gout:BAAALAADCgYIBQAAAA==.',Gr='Greggdshami:BAAALAAECgYIBgAAAA==.Gretagobbo:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Ha='Hammburger:BAAALAADCgMIAwAAAA==.',He='Heruin:BAAALAADCgQIBAAAAA==.',Ho='Hohenhaim:BAAALAADCggICgAAAA==.Holymrp:BAAALAAECgIIAwAAAA==.Holyvarlarn:BAAALAAECgYICQABLAAFFAMIBAABAAAAAA==.Horse:BAACLAAFFIEFAAIFAAMITAHJBQC8AAAFAAMITAHJBQC8AAAsAAQKgRcAAgUACAigB+8jAIYBAAUACAigB+8jAIYBAAAA.',Hr='Hrafna:BAAALAADCgEIAQABLAAECgMIAwABAAAAAA==.',Ia='Iammyscars:BAAALAAECggIEQAAAA==.',Ih='Iheartgrass:BAAALAADCgMIAwAAAA==.',Il='Illa:BAAALAADCgIIAgAAAA==.',Ir='Ironkarkass:BAAALAADCgUIBQAAAA==.',It='Ithidang:BAAALAADCgcICgAAAA==.',Ja='Jaylas:BAAALAAECgUIBQAAAA==.Jaysashi:BAAALAAECgYICQAAAA==.',Jo='Joeexotic:BAAALAADCggICAAAAA==.Jorxx:BAAALAADCggICAAAAA==.',Ju='Judgment:BAAALAADCggIEwAAAA==.Jun:BAABLAAECoEXAAIGAAgIeia1AACGAwAGAAgIeia1AACGAwABLAAFFAMIBQAHAA8GAA==.',Ka='Kass:BAAALAAECgIIBAAAAA==.Kasumaus:BAAALAAECgUICAAAAA==.Kateri:BAAALAADCgYIBgABLAADCggIEgABAAAAAA==.',Ke='Keldra:BAAALAADCgYIBgAAAA==.Kelnis:BAAALAADCggICAAAAA==.',Kh='Khelthrael:BAAALAADCgUICQAAAA==.Khephris:BAAALAADCggIEgAAAA==.',Kn='Knivex:BAAALAAECgUIBgAAAA==.',Ku='Kubcake:BAAALAADCggICAAAAA==.Kurama:BAAALAAECgcIDQAAAA==.',Ky='Kyrise:BAAALAAECggIEAAAAA==.',Li='Lightbläster:BAAALAADCggIDAAAAA==.Lionroar:BAAALAAECgMIBAAAAA==.Lionscales:BAAALAADCgEIAQAAAA==.Littleguy:BAAALAAECgIIAgAAAA==.Liun:BAAALAADCgMIAgAAAA==.',Lo='Lokie:BAAALAADCgcIBwAAAA==.Lonee:BAAALAADCggIDwAAAA==.Lothgow:BAAALAADCgEIAQAAAA==.',Ma='Magnoline:BAAALAADCggIDwAAAA==.Malefiroar:BAAALAADCggICAAAAA==.Manbeardrac:BAAALAADCgQIBAAAAA==.Matteas:BAAALAAECgUICAAAAA==.',Mo='Mograins:BAAALAAECgUICwAAAA==.Moond:BAAALAAECgMIAwAAAA==.Morgainne:BAAALAAECgEIAQAAAA==.Mortmor:BAAALAAECgYICAAAAA==.',Mu='Muffinn:BAAALAAECgMIBQAAAA==.',My='Mym:BAAALAAECgcIDwAAAA==.',['Mâ']='Mâsterdon:BAAALAAECgEIAQAAAA==.',Ne='Needsomesun:BAAALAADCgYIBgAAAA==.Nercos:BAAALAAECgcICwAAAA==.',Ni='Niyabelle:BAAALAAECgEIAQAAAA==.',No='Noggenfloggr:BAAALAAECgEIAQAAAA==.Nomediocre:BAAALAADCgYIBgAAAA==.',Ny='Nybrax:BAAALAADCgcIBwAAAA==.',Oi='Oida:BAAALAADCgEIAQAAAA==.',Ol='Oleevia:BAAALAAECgUIBwAAAA==.',Or='Orgdynamite:BAACLAAFFIEFAAIIAAMIrhy0AAAWAQAIAAMIrhy0AAAWAQAsAAQKgRcAAggACAj+I2UBABcDAAgACAj+I2UBABcDAAAA.Oriax:BAAALAAECgMIAwAAAA==.',Pa='Paedragon:BAAALAAECgEIAQAAAA==.Papie:BAAALAADCgYIBQAAAA==.Paínkiller:BAAALAAECgUIBQABLAAECgcICwABAAAAAA==.',Pe='Pejbolt:BAACLAAFFIEFAAMHAAMIDwZyBgCYAAAHAAIIpAZyBgCYAAAJAAIIPwNLCwB5AAAsAAQKgRoABAoACAisH8QDAEwCAAoABwjsHMQDAEwCAAkABQikGOwoAG4BAAcABAgDJPobADEBAAAA.',Pi='Picklrick:BAAALAAECgMIBgAAAA==.Piezeeko:BAAALAAECgYIBgAAAA==.Pixystix:BAAALAADCggIDwAAAA==.',Po='Porksteak:BAAALAADCgYIBgAAAA==.',Pr='Priesttweety:BAAALAAECgEIAQAAAA==.',Qu='Quadzilla:BAAALAADCggICAAAAA==.',Ra='Raiden:BAAALAAECgIIAgAAAA==.Ravenkiss:BAAALAADCgEIAQAAAA==.',Re='Reignbeau:BAAALAADCggICAAAAA==.Renniel:BAAALAADCgYIBgAAAA==.Rentacat:BAAALAADCgUICwAAAA==.',Ro='Rockbìter:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.',['Rö']='Römana:BAAALAADCgYICQAAAA==.',Sa='Sathari:BAAALAADCgcIFAAAAA==.',Sc='Scoophero:BAAALAAECgcICgAAAA==.',Se='Senatia:BAAALAADCgYIBgAAAA==.Serian:BAAALAADCgYIBQAAAA==.',Sh='Shadowleague:BAAALAADCggIDAAAAA==.Shadowwroth:BAAALAAECgYICQAAAA==.Shamwowolio:BAAALAADCgEIAQABLAAECgEIAQABAAAAAA==.',Si='Sicaris:BAAALAAECgIIAgAAAA==.Sicksdeep:BAABLAAECoEjAAMLAAgIpBf3AgAxAgALAAgIpBf3AgAxAgAMAAQI9hL3MQAVAQAAAA==.',Sk='Skÿe:BAAALAAECgYICQAAAA==.',Sl='Slicedbread:BAAALAAECgYIBgAAAA==.',So='Sondirev:BAAALAAECgMIBwAAAA==.Sooshi:BAAALAADCgYIBgAAAA==.',Sp='Speoghii:BAAALAADCggICAAAAA==.Spifftreebug:BAAALAAECgUIDQAAAA==.',St='Stormrain:BAAALAADCgcIDAAAAA==.',Su='Surge:BAAALAADCggIFQAAAA==.',Ta='Taurriel:BAAALAAECgUICAAAAA==.Tazzm:BAAALAAECgYIDAAAAA==.',Te='Teio:BAAALAAECgMIBgAAAA==.Teranok:BAAALAAECgYICgAAAA==.Terozon:BAAALAADCgQIBAAAAA==.',Th='Thailog:BAAALAADCggICAAAAA==.Thalel:BAAALAADCggIEAAAAA==.Thancred:BAAALAADCgcIDQAAAA==.Thoir:BAACLAAFFIEFAAINAAMIQx0+AQAkAQANAAMIQx0+AQAkAQAsAAQKgRsAAg0ACAj5JacAAE8DAA0ACAj5JacAAE8DAAEsAAUUAwgFAAUATAEA.Thundrkeg:BAAALAADCggIDgABLAAECgcIEAABAAAAAA==.',Ti='Tipsylorcet:BAAALAAECgYICQAAAA==.',Tk='Tkfoxie:BAAALAADCgcIDAAAAA==.',Tr='Tricktìckler:BAAALAAECgEIAQAAAA==.Trinestia:BAAALAADCgQIBQAAAA==.',Tu='Turiell:BAAALAAECgEIAQAAAA==.',Ty='Tybird:BAAALAAECgMIAwAAAA==.',['Tî']='Tîlr:BAAALAAECgYICQAAAA==.',Ui='Uinta:BAAALAADCggIDwAAAA==.',Ul='Ulsull:BAAALAADCggIEgAAAA==.Ulymage:BAECLAAFFIEFAAQEAAMIWg3pAgCMAAAEAAIIYwPpAgCMAAACAAEIuiBlEQBbAAAOAAEIgwO5AgBIAAAsAAQKgRcABAIACAjiIUkQAJwCAAIACAjBIEkQAJwCAAQABwgDHE8NAPIBAA4AAgj6G8MHAJgAAAAA.',Va='Vandagylon:BAAALAADCgcIBwAAAA==.Varkhath:BAAALAADCggIEQAAAA==.',Ve='Velweaver:BAAALAAECgQIBwAAAA==.Ven:BAAALAAECgYICQAAAA==.Verac:BAAALAADCgIIAgAAAA==.',Vi='Vievie:BAAALAAECggIEQAAAA==.Viviancoggs:BAAALAADCgcIDAAAAA==.',Vy='Vynthorian:BAAALAADCggICAAAAA==.',Wa='Wankstar:BAAALAAECgIIAgAAAA==.',We='Weehunt:BAAALAAECgYICQAAAA==.',Wh='Wholegrain:BAAALAADCgcIBwAAAA==.',Wi='Wicka:BAAALAAECgUICQAAAA==.Wildriver:BAAALAAECgQICAAAAA==.Wiliam:BAAALAADCgYIAgABLAAECgcIDwABAAAAAA==.',Xa='Xandrelar:BAAALAAECgcIEAAAAA==.Xanni:BAABLAAECoEXAAINAAgItQ+tIgCpAQANAAgItQ+tIgCpAQAAAA==.Xarbyn:BAAALAADCgYIBgAAAA==.',Xe='Xelpadin:BAAALAADCggIAQAAAA==.',Ya='Yakbo:BAAALAAECgcIEAAAAA==.',Ye='Yeedle:BAAALAAECgEIAQAAAA==.',Yl='Ylwdynamite:BAAALAADCgcIDgABLAAFFAMIBQAIAK4cAA==.',Za='Zacygos:BAACLAAFFIEFAAIPAAMIVxLwAgD6AAAPAAMIVxLwAgD6AAAsAAQKgRYAAg8ACAhVJFUCADcDAA8ACAhVJFUCADcDAAAA.Zanne:BAAALAAECggIEQAAAA==.',Zl='Zlot:BAACLAAFFIEFAAMQAAMIWBTfAgDeAAAQAAMIShLfAgDeAAARAAII4QyGBwCiAAAsAAQKgRcAAxAACAhuIl0EAPYCABAACAhuIl0EAPYCABEAAggOGclXAJcAAAAA.Zlotamental:BAAALAADCgYIBgABLAAFFAMIBQAQAFgUAA==.',Zu='Zurrie:BAAALAADCgYICAAAAA==.',['Úl']='Úlfa:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end