--!strict
--[[
	Suite de tests, executee par `make test` dans un serveur Roblox reel
	via la Luau Execution API.

	LIMITE : la session charge le DataModel mais ne demarre pas le jeu
	(`RunService:IsRunning()` vaut false), donc les scripts serveur ne
	s'executent pas d'eux-memes. On teste donc :
	  - la structure statique (mapping Rojo, stade, ancrage)
	  - le chargement de chaque module serveur, ce qui attrape les erreurs
	    de require et de syntaxe qui ne se verraient sinon qu'en production
	  - la logique pure : notes d'equipe, moteur de match, penalties,
	    raretes, economie

	C'est le principe de design de ce jeu : le moteur, l'economie et les
	cotes sont du calcul pur, donc couverts ici. Seul le ressenti du tir ne
	l'est pas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Cards = require(ReplicatedStorage.Shared.Cards)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local MatchSim = require(ReplicatedStorage.Shared.MatchSim)
local Penalty = require(ReplicatedStorage.Shared.Penalty)
local Ratings = require(ReplicatedStorage.Shared.Ratings)

type Test = { name: string, run: () -> () }

local tests: { Test } = {}

local function test(name: string, run: () -> ())
	table.insert(tests, { name = name, run = run })
end

local function assertEquals(actual: any, expected: any, what: string)
	if actual ~= expected then
		error(`{what} : attendu {tostring(expected)}, obtenu {tostring(actual)}`, 2)
	end
end

local function assertTrue(condition: boolean, what: string)
	if not condition then
		error(what, 2)
	end
end

--[[ Composition uniforme, pour isoler l'effet d'un seul parametre. ]]
local function squad(rating: number): Ratings.Lineup
	local lineup: Ratings.Lineup = {}
	for _, position in GameConfig.positions do
		lineup[position] = {
			id = `test:{position}:{rating}`,
			name = "Test",
			position = position :: any,
			rating = rating,
			rarity = "BRONZE",
		}
	end
	return lineup
end

-- --------------------------------------------------------------------------
-- Structure
-- --------------------------------------------------------------------------

test("le mapping Rojo place Shared dans ReplicatedStorage", function()
	assertTrue(ReplicatedStorage:FindFirstChild("Shared") ~= nil, "Shared absent")
end)

test("tous les modules serveur se chargent", function()
	-- Test le plus important de la structure : rien d'autre ne prouve
	-- qu'un module serveur compile, puisque les scripts ne tournent pas.
	local systems = ServerScriptService.Server.systems

	for _, name in { "Currency", "League", "Match", "Packs", "Receipts", "Save", "Squad" } do
		local ok, err = pcall(require, systems[name])
		assertTrue(ok, `module {name} ne se charge pas : {tostring(err)}`)
	end
end)

test("Remotes.init cree tous les remotes declares", function()
	local Remotes = require(ReplicatedStorage.Shared.Remotes)
	Remotes.init()

	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	assertTrue(folder ~= nil, "Remotes.init n'a cree aucun dossier")

	for _, name in Remotes.names() do
		assertTrue(folder:FindFirstChild(name) ~= nil, `remote {name} absent`)
	end
end)

test("le stade contient le ballon, le gardien, le but et un spawn", function()
	-- Le client cherche exactement ces noms en recursif. Ce test rejoue son
	-- chemin : sur le jeu precedent, un test plus permissif que le client
	-- avait laisse passer un jeu injouable.
	for _, name in { "Ball", "Keeper", "GoalCrossbar", "PenaltySpot" } do
		assertTrue(workspace:FindFirstChild(name, true) ~= nil, `{name} introuvable dans Workspace`)
	end

	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	assertTrue(spawn ~= nil, "aucun SpawnLocation")

	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { spawn }

	local hit = workspace:Raycast(spawn.Position, Vector3.new(0, -20, 0), parameters)
	assertTrue(hit ~= nil, "rien sous le SpawnLocation : le joueur tomberait")
end)

test("le spawn regarde vers le but", function()
	-- Le hook des dix secondes suppose que le joueur voie sa cible sans
	-- bouger. Le but est en Z negatif, le spawn en Z positif.
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local crossbar = workspace:FindFirstChild("GoalCrossbar", true)

	assertTrue(spawn ~= nil and crossbar ~= nil, "spawn ou but manquant")
	assertTrue(spawn.Position.Z > crossbar.Position.Z, "le spawn n'est pas du bon cote du but")

	local distance = (spawn.Position - crossbar.Position).Magnitude
	assertTrue(distance < 40, `le but est a {math.floor(distance)} studs, trop loin`)
end)

test("toutes les parts du stade sont ancrees", function()
	local floating = {}
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and not instance.Anchored then
			table.insert(floating, instance:GetFullName())
		end
	end

	assertTrue(#floating == 0, `parts non ancrees : {table.concat(floating, ", ")}`)
end)

-- --------------------------------------------------------------------------
-- Notes d'equipe
-- --------------------------------------------------------------------------

test("les notes suivent les formules de la spec", function()
	local lineup = squad(70)
	lineup.SUB = nil

	local ratings = Ratings.compute(lineup)
	assertEquals(ratings.attack, 70 * 0.7 + 70 * 0.3, "attaque")
	assertEquals(ratings.midfield, 70 * 0.7 + (70 + 70) * 0.15, "milieu")
	assertEquals(ratings.defence, 70 * 0.7 + 70 * 0.3, "defense")
end)

test("un poste vide handicape sans rendre l'equipe injouable", function()
	local full = Ratings.compute(squad(70))

	local partial = squad(70)
	partial.ATT = nil
	local weakened = Ratings.compute(partial)

	assertTrue(weakened.attack < full.attack, "retirer l'attaquant n'a rien change")
	assertTrue(weakened.attack > 0, "une equipe amputee doit rester jouable")
end)

test("le remplacant renforce le poste le plus faible", function()
	local lineup = squad(70)
	lineup.ATT = { id = "a", name = "A", position = "ATT", rating = 40, rarity = "BRONZE" }

	local without = Ratings.compute(lineup)
	lineup.SUB = { id = "s", name = "S", position = "MID", rating = 90, rarity = "ELITE" }
	local with = Ratings.compute(lineup)

	assertTrue(with.attack > without.attack, "le remplacant n'a pas aide l'attaque")
end)

-- --------------------------------------------------------------------------
-- Moteur de match
-- --------------------------------------------------------------------------

test("le moteur est deterministe pour une graine donnee", function()
	-- Sans ca, un joueur pourrait couper sa connexion et rejouer un match
	-- perdu jusqu'a obtenir un bon resultat.
	local home = Ratings.compute(squad(75))
	local away = Ratings.compute(squad(65))

	local first = MatchSim.run(home, away, 4242, function()
		return true
	end)
	local second = MatchSim.run(home, away, 4242, function()
		return true
	end)

	assertEquals(first.scoreHome, second.scoreHome, "score domicile")
	assertEquals(first.scoreAway, second.scoreAway, "score exterieur")
	assertEquals(#first.events, #second.events, "nombre d'evenements")
end)

test("la graine depend du joueur, de l'adversaire et de la journee", function()
	local a = MatchSim.seedFor(123, "bot:5:1", 1)
	assertTrue(a ~= MatchSim.seedFor(124, "bot:5:1", 1), "l'identite du joueur est ignoree")
	assertTrue(a ~= MatchSim.seedFor(123, "bot:5:2", 1), "l'adversaire est ignore")
	assertTrue(a ~= MatchSim.seedFor(123, "bot:5:1", 2), "la journee est ignoree")
end)

test("une meilleure composition gagne nettement plus souvent", function()
	-- CRITERE 4 DE LA SPEC, le seul qui compte vraiment : si la
	-- composition ne change rien de mesurable, le jeu n'est qu'un
	-- generateur de nombres deguise.
	local weak = Ratings.compute(squad(50))
	local average = Ratings.compute(squad(70))
	local strong = Ratings.compute(squad(88))

	local function winRate(home, away): number
		local wins = 0
		local runs = 600

		for seed = 1, runs do
			local result = MatchSim.run(home, away, seed)
			if result.scoreHome > result.scoreAway then
				wins += 1
			end
		end

		return wins / runs * 100
	end

	local underdog = winRate(weak, average)
	local even = winRate(average, average)
	local favourite = winRate(strong, average)

	print(
		`       outsider {math.floor(underdog)}%  ·  equilibre {math.floor(even)}%  ·  favori {math.floor(
			favourite
		)}%`
	)

	assertTrue(
		favourite > even + 15,
		`le favori ne gagne que {math.floor(favourite)}% contre {math.floor(even)}% a armes egales`
	)
	assertTrue(
		underdog < even - 10,
		`l'outsider gagne {math.floor(underdog)}%, trop proche de l'equilibre`
	)
	-- Mais l'outsider doit garder une chance : un championnat sans surprise
	-- n'a aucune tension.
	assertTrue(underdog > 3, `l'outsider ne gagne que {math.floor(underdog)}%, jamais de surprise`)
end)

test("le nombre de buts par match reste realiste", function()
	local average = Ratings.compute(squad(70))
	local total = 0
	local runs = 800

	for seed = 1, runs do
		local result = MatchSim.run(average, average, seed)
		total += result.scoreHome + result.scoreAway
	end

	local perMatch = total / runs
	print(`       {string.format("%.2f", perMatch)} buts par match`)

	assertTrue(perMatch > 1.8, `{perMatch} buts par match, trop peu`)
	assertTrue(perMatch < 4.0, `{perMatch} buts par match, trop`)
end)

test("les penalties du joueur changent le score", function()
	-- Si marquer ou rater ses penalties ne changeait rien, la seule partie
	-- jouable du jeu serait decorative.
	local home = Ratings.compute(squad(70))
	local away = Ratings.compute(squad(70))

	local scoredTotal, missedTotal = 0, 0
	local penalties = 0

	for seed = 1, 400 do
		local allIn = MatchSim.run(home, away, seed, function()
			return true
		end)
		local allOut = MatchSim.run(home, away, seed, function()
			return false
		end)

		scoredTotal += allIn.scoreHome
		missedTotal += allOut.scoreHome
		penalties += allIn.penaltiesTaken
	end

	assertTrue(penalties > 0, "aucun penalty tire sur 400 matchs")
	assertTrue(
		scoredTotal > missedTotal,
		"marquer tous ses penalties ne rapporte pas plus que tous les rater"
	)
end)

test("les points suivent le reglement", function()
	assertEquals(MatchSim.pointsFor(2, 1), GameConfig.league.pointsWin, "victoire")
	assertEquals(MatchSim.pointsFor(1, 1), GameConfig.league.pointsDraw, "nul")
	assertEquals(MatchSim.pointsFor(0, 3), 0, "defaite")
end)

-- --------------------------------------------------------------------------
-- Penalties
-- --------------------------------------------------------------------------

test("une visee invalide est rejetee", function()
	-- C'est la seule chose que le client envoie, donc la seule surface
	-- qu'un client modifie peut attaquer.
	assertTrue(Penalty.isValidAim({ x = 0.5, y = 0.5, power = 0.5 }), "visee normale refusee")

	local rejected = {
		{ x = -0.1, y = 0.5, power = 0.5 },
		{ x = 1.5, y = 0.5, power = 0.5 },
		{ x = 0.5, y = 0.5, power = 2 },
		{ x = 0 / 0, y = 0.5, power = 0.5 },
		{ x = math.huge, y = 0.5, power = 0.5 },
		{ x = "0.5", y = 0.5, power = 0.5 },
		{ x = 0.5, y = 0.5 },
	}

	for index, aim in rejected do
		assertTrue(not Penalty.isValidAim(aim), `visee invalide #{index} acceptee`)
	end

	assertTrue(not Penalty.isValidAim(nil), "nil accepte")
	assertTrue(not Penalty.isValidAim("triche"), "chaine acceptee")
end)

test("viser une lucarne est plus difficile que le centre", function()
	local centre = Penalty.difficulty({ x = 0.5, y = 0.3, power = 0.4 })
	local corner = Penalty.difficulty({ x = 0.03, y = 0.95, power = 1 })

	assertTrue(corner > centre, "la lucarne n'est pas plus difficile que le centre")
	assertTrue(centre >= 0 and corner <= 1, "difficulte hors de [0, 1]")
end)

test("un bon gardien arrete plus souvent", function()
	local aim = { x = 0.5, y = 0.4, power = 0.5 }

	local function saveRate(keeperRating: number): number
		local saves = 0
		local runs = 3000
		local rng = Random.new(7)

		for _ = 1, runs do
			if Penalty.resolve(aim, keeperRating, rng).result == "saved" then
				saves += 1
			end
		end

		return saves / runs * 100
	end

	local weak = saveRate(45)
	local elite = saveRate(95)
	print(`       gardien 45 : {math.floor(weak)}% d'arrets  ·  gardien 95 : {math.floor(elite)}%`)

	assertTrue(elite > weak + 5, "la note du gardien ne change quasiment rien")
end)

test("le meilleur tir depend du gardien en face", function()
	-- LA propriete qui rend la visee interessante. Si placer etait toujours
	-- le bon choix, le seul moment interactif du jeu se reduirait a cliquer
	-- au centre. Un reglage precedent avait exactement ce defaut.
	local placed = { x = 0.5, y = 0.25, power = 0.35 }
	local risky = { x = 0.05, y = 0.9, power = 0.95 }

	local function goalRate(aim, keeperRating: number): number
		local goals = 0
		local runs = 4000
		local rng = Random.new(4242)

		for _ = 1, runs do
			if Penalty.resolve(aim, keeperRating, rng).result == "goal" then
				goals += 1
			end
		end

		return goals / runs * 100
	end

	local weakPlaced, weakRisky = goalRate(placed, 45), goalRate(risky, 45)
	local elitePlaced, eliteRisky = goalRate(placed, 95), goalRate(risky, 95)

	print(
		`       gardien 45 : place {math.floor(weakPlaced)}% / risque {math.floor(weakRisky)}%  ·  `
			.. `gardien 95 : place {math.floor(elitePlaced)}% / risque {math.floor(eliteRisky)}%`
	)

	assertTrue(
		weakPlaced > weakRisky,
		"contre un gardien faible, le tir risque devrait etre moins bon"
	)
	assertTrue(
		eliteRisky > elitePlaced,
		"contre un gardien d'elite, prendre le risque devrait payer - sinon placer est toujours le bon choix"
	)
end)

test("un tir difficile passe plus souvent mais sort plus souvent", function()
	local function rates(aim): (number, number)
		local goals, misses = 0, 0
		local runs = 3000
		local rng = Random.new(11)

		for _ = 1, runs do
			local outcome = Penalty.resolve(aim, 70, rng)
			if outcome.result == "goal" then
				goals += 1
			elseif outcome.result == "missed" then
				misses += 1
			end
		end

		return goals / runs * 100, misses / runs * 100
	end

	local safeGoals, safeMisses = rates({ x = 0.5, y = 0.25, power = 0.35 })
	local riskyGoals, riskyMisses = rates({ x = 0.05, y = 0.9, power = 0.95 })

	print(
		`       place : {math.floor(safeGoals)}% buts / {math.floor(safeMisses)}% dehors  ·  `
			.. `risque : {math.floor(riskyGoals)}% / {math.floor(riskyMisses)}%`
	)

	assertTrue(riskyMisses > safeMisses, "le tir risque ne sort pas plus souvent")
	assertTrue(safeGoals > 40, "un tir place ne rentre presque jamais")
	-- Taux de transformation reel d'un penalty : environ 75 %. On reste
	-- dans cet ordre de grandeur, sinon le penalty perd son enjeu.
	assertTrue(safeGoals < 92, `{math.floor(safeGoals)}% de buts, le penalty est trop facile`)
end)

-- --------------------------------------------------------------------------
-- Cartes et economie
-- --------------------------------------------------------------------------

test("les poids de rarete somment a 100", function()
	local total = 0
	for _, rarity in GameConfig.rarities do
		assertTrue(rarity.weight > 0, `{rarity.key} : poids nul, jamais tire`)
		assertTrue(rarity.minRating <= rarity.maxRating, `{rarity.key} : plage de notes inversee`)
		total += rarity.weight
	end

	assertEquals(total, 100, "somme des poids")
end)

test("les plages de notes se suivent sans trou ni chevauchement", function()
	-- Un trou ferait qu'une note ne correspondrait a aucune rarete, et
	-- l'UI n'aurait pas de couleur a afficher.
	for index = 2, #GameConfig.rarities do
		local previous = GameConfig.rarities[index - 1]
		local current = GameConfig.rarities[index]
		assertEquals(
			current.minRating,
			previous.maxRating + 1,
			`trou ou chevauchement entre {previous.key} et {current.key}`
		)
	end

	for rating = 40, 99 do
		assertTrue(Cards.rarityForRating(rating) ~= nil, `la note {rating} n'a aucune rarete`)
	end
end)

test("le tirage de rarete respecte les probabilites", function()
	local rng = Random.new(2026)
	local counts: { [string]: number } = {}
	local runs = 40000

	for _ = 1, runs do
		local rarity = Cards.drawRarity(rng)
		counts[rarity.key] = (counts[rarity.key] or 0) + 1
	end

	for _, rarity in GameConfig.rarities do
		local observed = (counts[rarity.key] or 0) / runs * 100
		local drift = math.abs(observed - rarity.weight)
		assertTrue(
			drift <= 1.5,
			`{rarity.key} : {string.format("%.2f", observed)}% contre {rarity.weight}% attendu`
		)
	end
end)

test("la Pochette Or garantit au moins un Or", function()
	local rng = Random.new(99)
	local order: { [string]: number } = {}
	for index, rarity in GameConfig.rarities do
		order[rarity.key] = index
	end

	local goldIndex = order.GOLD

	for _ = 1, 2000 do
		local rarity = Cards.drawRarity(rng, "GOLD")
		assertTrue(order[rarity.key] >= goldIndex, `la Pochette Or a rendu du {rarity.key}`)
	end
end)

test("une carte generee est coherente avec sa rarete", function()
	local rng = Random.new(1234)

	for _ = 1, 3000 do
		local card = Cards.generate(rng)
		local rarity = Cards.rarityByKey(card.rarity)

		assertTrue(rarity ~= nil, `rarete inconnue : {card.rarity}`)
		assertTrue(
			card.rating >= rarity.minRating and card.rating <= rarity.maxRating,
			`{card.name} : note {card.rating} hors de la plage {card.rarity}`
		)
		assertTrue(card.id ~= "" and card.name ~= "", "carte sans identite")
	end
end)

test("une carte de meilleure note vaut strictement plus", function()
	-- Sans ca, accumuler du bronze serait une strategie de revente.
	local previous = -1
	for rating = 40, 99 do
		local value = Cards.value({
			id = "x",
			name = "x",
			position = "ATT",
			rating = rating,
			rarity = "BRONZE",
		})
		assertTrue(value > previous, `la valeur ne croit pas a la note {rating}`)
		previous = value
	end
end)

test("l'economie tient : une pochette coute quelques matchs", function()
	local perWin = GameConfig.rewards.win
	local matchesForPack = GameConfig.packs.price / perWin

	print(`       {string.format("%.1f", matchesForPack)} victoires pour une pochette`)
	assertTrue(matchesForPack >= 1.5, "une pochette est offerte a chaque match")
	assertTrue(matchesForPack <= 6, "une pochette demande trop de matchs")
end)

test("la saison a une longueur et des paliers coherents", function()
	local league = GameConfig.league
	assertTrue(league.matchdaysPerSeason >= 5, "saison trop courte")
	assertTrue(
		league.promotedCount + league.relegatedCount < league.clubsPerDivision,
		"tout le monde monte ou descend"
	)
	assertTrue(league.lowestDivision > league.highestDivision, "echelle de divisions inversee")
end)

test("chaque produit et game pass a un effet defini", function()
	for key, definition in GameConfig.products do
		assertTrue(
			definition.grantCredits ~= nil or definition.guaranteedRarity ~= nil,
			`{key} : aucun effet, l'achat ne donnerait rien`
		)
	end

	for key, definition in GameConfig.gamePasses do
		assertTrue(definition.creditMultiplier ~= nil, `{key} : aucun effet defini`)
	end
end)

-- --------------------------------------------------------------------------
-- Execution
-- --------------------------------------------------------------------------

local failed = 0

for _, entry in tests do
	local success, err = pcall(entry.run)
	if success then
		print(`[ok]   {entry.name}`)
	else
		failed += 1
		warn(`[FAIL] {entry.name}\n       {err}`)
	end
end

if failed > 0 then
	error(`{failed} test(s) en echec sur {#tests}`)
end

print(`[ok]   {#tests} test(s) passes`)
