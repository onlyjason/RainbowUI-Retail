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
 local lookup = {'Unknown-Unknown','Warrior-Protection','DemonHunter-Havoc',}; local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=44,date='2025-08-29',data={Ak='Akkiba:BAAALAADCgYICQAAAA==.',Al='Alaval:BAAALAAECgMIBAAAAA==.Alendar:BAAALAADCggIEAAAAA==.Aletheïa:BAAALAADCggIEAAAAA==.Althamon:BAAALAADCgcIBwAAAA==.',Am='Amiradormi:BAAALAADCggIEQAAAA==.',An='Anori:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Antamun:BAAALAADCgYIBgAAAA==.',Ao='Aoasis:BAAALAAECgEIAQAAAA==.',Ar='Arcanight:BAAALAAECgYICwAAAA==.Arduinna:BAAALAAECgIIAgAAAA==.Arellá:BAAALAADCgMIAwABLAADCggIEAABAAAAAA==.Artemist:BAAALAADCggIDQAAAA==.',As='Asterley:BAAALAADCgYICQAAAA==.',Au='Austie:BAAALAADCgcIBwAAAA==.Austin:BAAALAADCggIDwAAAA==.',Az='Azirra:BAAALAADCgcIBwAAAA==.Azmodeus:BAAALAADCgMIAwAAAA==.Azzazel:BAAALAADCgUIBQAAAA==.',['Aí']='Aíne:BAAALAADCgIIAgAAAA==.',Ba='Bamalock:BAAALAADCggIDAAAAA==.Bankai:BAAALAAECgIIAgAAAA==.Baromir:BAAALAADCgYICQAAAA==.Bataria:BAAALAADCgIIAgAAAA==.',Be='Belinda:BAAALAADCgIIAgAAAA==.Berries:BAAALAADCgUIBAAAAA==.Betalock:BAAALAAECgYICQAAAA==.',Bi='Bigmageguy:BAAALAAECgcIBwAAAA==.Bigtriangle:BAABLAAECoEaAAICAAcIXh4uBgBtAgACAAcIXh4uBgBtAgAAAA==.',Bj='Bjoris:BAAALAAECgMIBAAAAA==.',Bl='Bloodun:BAAALAADCggIEAAAAA==.',Br='Braer:BAAALAADCgEIAQAAAA==.',Bu='Bubblegom:BAAALAAECggIEQAAAA==.Burr:BAAALAADCgcIBwAAAA==.Buubuubonk:BAAALAADCggICAAAAA==.',['Bô']='Bôjay:BAAALAADCgYIBgAAAA==.',Ca='Carvedilol:BAAALAADCgYIAQAAAA==.',Ce='Cearáa:BAAALAAECgYIBgAAAA==.Ceredolar:BAAALAAECgMIAwAAAA==.',Ch='Cherritart:BAAALAADCgcICAAAAA==.Cherritastic:BAAALAADCgUIBQAAAA==.',Ci='Cimmaraya:BAAALAAECgMIBAAAAA==.',Cl='Claemoth:BAAALAADCggIDwAAAA==.',Co='Coagulation:BAAALAAECgMIBQAAAA==.Coldri:BAAALAADCgcIDwAAAA==.Cowboyshorn:BAAALAADCggICAAAAA==.',Cu='Cubroots:BAAALAAECgMIBAAAAA==.',Cy='Cyberk:BAAALAADCgMIBgABLAADCgcIDgABAAAAAA==.Cyione:BAAALAAECgMIAwAAAA==.Cynleel:BAAALAAECgMIBAAAAA==.',Da='Dadu:BAAALAAECgEIAQAAAA==.Damackabit:BAAALAADCgMIAwABLAAECgcIBwABAAAAAA==.',De='Deathpaws:BAAALAADCggIFgAAAA==.Deathsyke:BAAALAAECgMIAwAAAA==.Deneb:BAAALAADCgYIBgAAAA==.Deviousone:BAAALAAECgMIAwAAAA==.',Do='Docdruid:BAAALAADCgcICwAAAA==.Dogon:BAAALAADCggICgAAAA==.',Dr='Drüid:BAAALAAECgEIAQAAAA==.',Ds='Dsypha:BAAALAADCggICAAAAA==.',['Dé']='Déáth:BAAALAADCgMIAwAAAA==.',Ed='Edric:BAAALAAECgEIAQAAAA==.Edyion:BAAALAAECgMIBAAAAA==.',Ef='Efreet:BAAALAAECgEIAQAAAA==.',En='Enhancethis:BAAALAADCgIIAgAAAA==.Enoth:BAAALAADCgcIBwAAAA==.',Eu='Eurae:BAAALAAECgEIAQAAAA==.',Ex='Extrodinaire:BAAALAAECgMIBAAAAA==.',Fa='Fadedhalo:BAAALAAECgMIBAAAAA==.Falstan:BAAALAADCgUIBQAAAA==.Farrahmoans:BAAALAAECgEIAQAAAA==.',Fe='Fellvarg:BAAALAAECgMIBAAAAA==.Felsgoodman:BAAALAAECgcIDQAAAA==.',Fi='Fishburne:BAAALAADCgYIAQAAAA==.',Fo='Fotiá:BAAALAADCggICAAAAA==.',Fr='Frøzen:BAAALAADCggICAAAAA==.',Fu='Fulgur:BAAALAADCgYIBgAAAA==.Fumistra:BAAALAADCggIDwAAAA==.Furßurger:BAAALAAECgMIAwAAAA==.',Ga='Gahïjï:BAAALAADCggIEgABLAAECgEIAQABAAAAAA==.Gallium:BAAALAADCgYICQAAAA==.Galmeditates:BAAALAAECgEIAQAAAA==.Galroot:BAAALAAECgEIAQAAAA==.Galsnipes:BAAALAAECgcIDQAAAA==.Galvakrond:BAAALAAECgMIBAAAAA==.',Gl='Glorp:BAAALAADCgIIAgAAAA==.',Go='Goldenhealer:BAAALAADCgcICQABLAAECgcIGgACAF4eAA==.Goldenseal:BAAALAADCggICAAAAA==.Gomletta:BAAALAAECgEIAQAAAA==.',Gr='Graace:BAAALAADCgQIBAAAAA==.Grik:BAAALAAECgMIBQAAAA==.',Gw='Gwyndora:BAAALAADCggIEAAAAA==.',Ha='Hawynlegend:BAAALAADCggICAAAAA==.',He='Healthz:BAAALAAECgMIAwAAAA==.Hellenita:BAAALAADCgcIDgAAAA==.Hellshadow:BAAALAAECgMIBAAAAA==.',Hi='Hinako:BAAALAADCgYIBgABLAADCgcICgABAAAAAA==.',Ho='Holyoshyy:BAAALAAECgQIBgAAAA==.Holyvengence:BAAALAAECgIIAgAAAA==.Honos:BAAALAADCgQIAgAAAA==.',Hu='Hukawa:BAAALAADCgcIDgAAAA==.',Ie='Iemanja:BAAALAADCggIGAAAAA==.',Im='Immakin:BAAALAAECgMIBAAAAA==.',It='Ithaka:BAAALAADCggIEAAAAA==.',Ix='Ixo:BAAALAAECgMIAwAAAA==.',Iz='Izzik:BAAALAADCgUIBQABLAADCgcIDgABAAAAAA==.',Ja='Jachyra:BAAALAAECgIIAgAAAA==.Jackmanss:BAAALAADCgQIBAAAAA==.Jalan:BAAALAADCggICAAAAA==.Jamezon:BAAALAADCggICgAAAA==.',Je='Jebby:BAAALAAECgMIBAAAAA==.',Ji='Jitlok:BAAALAAECgMIBAAAAA==.',Jo='Johnnylaw:BAAALAADCggIDgAAAA==.',Ka='Kaalaalaal:BAAALAADCgUIBQABLAAECgEIAQABAAAAAA==.Kahrul:BAAALAAECgIIAgAAAA==.Kalibontu:BAAALAADCggIDwAAAA==.Kalius:BAAALAAECgMIBAAAAA==.Kazgrom:BAAALAADCgcIBwAAAA==.Kazool:BAAALAAECgYICAAAAA==.',Ke='Kenpomage:BAAALAAECgcIDQAAAA==.',Ki='Killerheal:BAAALAAECgQIBAABLAAECgcIGgACAF4eAA==.',Kl='Klawze:BAAALAADCggIDgAAAA==.',Ky='Kyran:BAAALAADCggIDwABLAAECgMIBAABAAAAAA==.',['Kø']='Køteb:BAAALAAECgcIBwAAAA==.',Lh='Lhost:BAAALAADCggIEwAAAA==.',Li='Lightarc:BAAALAAECggICAAAAA==.Lightsz:BAAALAADCggIFQAAAA==.',['Lï']='Lïmes:BAAALAAECgEIAgAAAA==.',Ma='Maakha:BAAALAAECgMIBAAAAA==.Maehko:BAAALAADCggIDwAAAA==.Magmamuncher:BAAALAADCggIEgAAAA==.Magroot:BAAALAAECgMIBAAAAA==.Mannadina:BAAALAAECgcIDAAAAA==.Mapera:BAAALAAECgMIBAAAAA==.Marjaya:BAAALAAECgEIAQAAAA==.',Mi='Miandra:BAAALAAECgMIBAAAAA==.Michaal:BAAALAAECgIIAgAAAA==.Mirosa:BAAALAAECgMIBAAAAA==.',Mo='Moris:BAAALAAECggIEgAAAA==.Mork:BAAALAADCgEIAQAAAA==.',Mu='Murmur:BAAALAADCgYIBgAAAA==.',My='Myshaman:BAAALAADCggICAAAAA==.',Na='Nangsa:BAAALAAECgMIBAAAAA==.',Ne='Neilrodimus:BAAALAAECgYICgAAAA==.Nessva:BAAALAAECgMIBQAAAA==.Neçromonger:BAAALAAECgcIBwAAAA==.',Ni='Nikkî:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.Ninurta:BAAALAADCgcIDgAAAA==.',No='Notmyvoid:BAAALAAECgQICAAAAA==.Novuri:BAAALAAECgMIBAAAAA==.Noxz:BAAALAAECgcIDQAAAA==.',Nu='Nuada:BAAALAADCgQIBAAAAA==.',Ny='Nyiais:BAAALAAECgMIAwAAAA==.',['Nï']='Nïghtmärë:BAAALAADCggIFQAAAA==.',Ob='Obsessedwith:BAAALAAECgMIBAAAAA==.',Oh='Ohamernster:BAAALAADCgcIBwAAAA==.',Or='Orcofmeister:BAAALAADCgUIBQAAAA==.',Ot='Ottohahn:BAAALAADCgMIAwAAAA==.',Pa='Pandatude:BAAALAAECgYIBgAAAA==.',Ph='Phiasko:BAAALAAECgMIBAAAAA==.',Ps='Psyscape:BAAALAADCgMIAwAAAA==.',Pu='Purrcilla:BAAALAAECgcIDQAAAA==.',Qi='Qijdami:BAAALAADCggICAAAAA==.',Qu='Quangar:BAAALAADCgIIAgAAAA==.',Ra='Ralas:BAAALAADCgUIBQAAAA==.Razsalghul:BAAALAADCggICAAAAA==.',Re='Reeally:BAAALAAECgEIAgAAAA==.Remydondo:BAABLAAECoEVAAIDAAgImxdyFQBVAgADAAgImxdyFQBVAgAAAA==.',Ri='Rio:BAAALAADCgMIAwAAAA==.Riptheramore:BAAALAADCggIEwAAAA==.',Ro='Ronrad:BAAALAAECgMIAwAAAA==.Roulette:BAAALAADCgQIBAAAAA==.Roxo:BAAALAADCgcIBwAAAA==.Rozzinor:BAAALAAECgEIAQAAAA==.',Ru='Rukía:BAAALAADCgMIAwAAAA==.',Sa='Sacrifice:BAAALAADCggICAAAAA==.Saintos:BAAALAAECggIAQAAAA==.Santhvel:BAAALAADCgcIBwAAAA==.Savageslayer:BAAALAAECgYICQAAAA==.',Sc='Scatmantom:BAAALAADCggIEwAAAA==.',Se='Sehten:BAAALAAECgMIAwAAAA==.',Sh='Shammatude:BAAALAADCgYIDAAAAA==.Sharpie:BAAALAAECgMIBAAAAA==.Shewolf:BAAALAADCgcICAAAAA==.Shlidd:BAAALAADCgcIBwAAAA==.',Si='Simbru:BAAALAAECgMIBAAAAA==.Sinuouss:BAAALAAECgEIAQAAAA==.',Sk='Skoda:BAAALAADCgcICgAAAA==.',Sl='Slylildevil:BAAALAAECgMIBgAAAA==.',Sm='Smaaug:BAAALAADCgEIAQAAAA==.',Sp='Spenqo:BAAALAADCgMIAwAAAA==.',St='Stërns:BAAALAADCgEIAQAAAA==.',Su='Sukki:BAAALAAECgEIAQAAAA==.',Ta='Takerfan:BAAALAAECgEIAQAAAA==.Tallyblue:BAAALAADCgUIBwAAAA==.Tap:BAAALAADCgUIBQAAAA==.Taynerek:BAAALAAECgMIBAAAAA==.',Tc='Tchazzar:BAAALAADCggICQAAAA==.',Te='Tega:BAAALAADCggICAAAAA==.Temüjin:BAAALAADCggICgAAAA==.Terror:BAAALAAECgMIBQAAAA==.Testacleez:BAAALAADCggICAAAAA==.',Th='Theeonlyone:BAAALAAECgIIAwAAAA==.Thich:BAAALAAECgcIDQAAAA==.',Ti='Tiaria:BAAALAAECgEIAQAAAA==.Tinyturds:BAAALAADCgIIAgAAAA==.Titannus:BAAALAAECgMIBAAAAA==.',Tr='Tribalrage:BAAALAADCggIDwAAAA==.Troutjelly:BAAALAAECgEIAQAAAA==.',Up='Uphie:BAAALAAECgMIAwAAAA==.',Va='Vallahan:BAAALAAECgEIAQAAAA==.Vandal:BAAALAAECgMIBQAAAA==.',Ve='Vega:BAAALAAECgYICwAAAA==.',Vi='Virigil:BAAALAAECgEIAQAAAA==.',Vm='Vmax:BAAALAADCggIDwAAAA==.',Vu='Vulrita:BAAALAAECgQIDQAAAA==.',Wa='Wardral:BAAALAAECgQIBQAAAA==.',Wh='Whitehand:BAAALAADCggIFAAAAA==.',Wi='Wiind:BAAALAAECgcIDQAAAA==.',Xo='Xonz:BAAALAAECgcIDQAAAA==.',Za='Zakk:BAAALAAECgMIAwAAAA==.',Ze='Zek:BAAALAAECgIIAgABLAAECggIAQABAAAAAA==.Zeshom:BAAALAADCgcIBwAAAA==.',Zi='Zirnbie:BAAALAAECgMIBAAAAA==.',['Ða']='Ðark:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end