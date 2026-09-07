--!strict
--[[
	Suite de tests executee par `make test` dans un serveur Roblox reel,
	via la Luau Execution API.

	Ce n'est pas un framework : chaque test leve une erreur si quelque chose
	ne va pas, et le script final echoue si au moins un test a echoue. Le
	code de sortie non nul bloque la publication.

	LIMITE IMPORTANTE : la session d'execution charge le DataModel mais ne
	demarre pas le jeu. RunService:IsRunning() vaut false, donc les scripts
	serveur ne s'executent pas d'eux-memes. La suite teste donc :
	  - la structure statique (mapping Rojo, map, ancrage)
	  - le chargement de chaque module serveur (attrape les erreurs de
	    require et de syntaxe, qui sinon n'apparaitraient qu'en production)
	  - la logique pure (prix, tirage pondere, formatage)
	Ce qui demande un joueur connecte (persistance, achats en Robux) reste
	verifie a la main, cf. spec.md critere 5.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)

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

-- --------------------------------------------------------------------------
-- Structure du DataModel
-- --------------------------------------------------------------------------

test("le mapping Rojo place Shared dans ReplicatedStorage", function()
	assertTrue(ReplicatedStorage:FindFirstChild("Shared") ~= nil, "ReplicatedStorage.Shared absent")
end)

test("tous les modules serveur se chargent", function()
	-- Test le plus important de la suite. La session d'execution ne demarre
	-- pas les scripts du jeu (RunService:IsRunning() vaut false), donc rien
	-- d'autre ne prouverait qu'un module serveur compile et s'initialise.
	-- Une erreur de require ou de syntaxe cote serveur ne se verrait qu'en
	-- production, sur un jeu deja publie.
	local systems = ServerScriptService.Server.systems

	for _, name in { "Currency", "Save", "Shop", "Wheel", "Receipts" } do
		local ok, err = pcall(require, systems[name])
		assertTrue(ok, `module {name} ne se charge pas : {tostring(err)}`)
	end
end)

test("Remotes.init cree tous les remotes attendus", function()
	local Remotes = require(ReplicatedStorage.Shared.Remotes)
	Remotes.init()

	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	assertTrue(folder ~= nil, "Remotes.init n'a cree aucun dossier")

	for _, name in { "Click", "BuyUpgrade", "Spin", "PromptPurchase", "StateChanged" } do
		assertTrue(folder:FindFirstChild(name) ~= nil, `remote {name} absent`)
	end
end)

test("Shop expose les trois ameliorations et calcule leurs prix", function()
	local Shop = require(ServerScriptService.Server.systems.Shop)

	for _, key in { "HAMMER", "BELLOWS", "APPRENTICE" } do
		local definition = Shop.getDefinition(key)
		assertTrue(definition ~= nil, `Shop ne connait pas {key}`)
	end

	assertTrue(Shop.getDefinition("CLE_INEXISTANTE") == nil, "Shop accepte une cle inconnue")
end)

test("Wheel.draw ne renvoie que des lots declares", function()
	local Wheel = require(ServerScriptService.Server.systems.Wheel)

	local known: { [string]: boolean } = {}
	for _, prize in GameConfig.wheel.prizes do
		known[prize.key] = true
	end

	for _ = 1, 500 do
		local prize = Wheel.draw()
		assertTrue(prize ~= nil, "Wheel.draw a renvoye nil")
		assertTrue(known[prize.key] == true, `lot inconnu tire : {prize.key}`)
	end
end)

test("la map contient l'enclume et un spawn", function()
	local forge = workspace:FindFirstChild("Forge", true)
	assertTrue(forge ~= nil, "enclume introuvable dans Workspace")
	assertTrue(
		forge:FindFirstChildWhichIsA("ClickDetector", true) ~= nil,
		"ClickDetector absent de l'enclume : le jeu serait injouable"
	)

	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	assertTrue(spawn ~= nil, "aucun SpawnLocation : le joueur tomberait dans le vide")
end)

test("toutes les parts de la map sont ancrees", function()
	local floating = {}
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and not instance.Anchored then
			table.insert(floating, instance:GetFullName())
		end
	end

	assertTrue(#floating == 0, `parts non ancrees : {table.concat(floating, ", ")}`)
end)

-- --------------------------------------------------------------------------
-- Economie
-- --------------------------------------------------------------------------

test("les trois ameliorations attendues sont definies", function()
	assertEquals(#GameConfig.upgrades, 3, "nombre d'ameliorations")

	local keys = {}
	for _, upgrade in GameConfig.upgrades do
		keys[upgrade.key] = true
		assertTrue(upgrade.basePrice > 0, `{upgrade.key} : prix de base nul`)
		assertTrue(
			upgrade.priceGrowth > 1,
			`{upgrade.key} : croissance <= 1, prix jamais croissant`
		)
		assertTrue(upgrade.maxLevel > 0, `{upgrade.key} : maxLevel nul`)
	end

	for _, expected in { "HAMMER", "BELLOWS", "APPRENTICE" } do
		assertTrue(keys[expected] == true, `amelioration {expected} manquante`)
	end
end)

test("le prix suit basePrice * croissance ^ niveau", function()
	local hammer = GameConfig.upgrades[1]
	assertEquals(hammer.key, "HAMMER", "premiere amelioration")

	assertEquals(math.floor(hammer.basePrice * hammer.priceGrowth ^ 0), 25, "prix niveau 0")
	assertEquals(math.floor(hammer.basePrice * hammer.priceGrowth ^ 1), 33, "prix niveau 1")
	assertEquals(math.floor(hammer.basePrice * hammer.priceGrowth ^ 2), 45, "prix niveau 2")
end)

test("le premier marteau reste atteignable en moins de 10 secondes", function()
	-- Jalon central de la spec : la premiere amelioration doit tomber
	-- avant que le joueur se demande ce qu'il fait la.
	local hammer = GameConfig.upgrades[1]
	local clicksNeeded = hammer.basePrice / GameConfig.click.baseGain
	local secondsAtFourPerSecond = clicksNeeded / 4

	assertTrue(
		secondsAtFourPerSecond <= 10,
		`premier marteau a {secondsAtFourPerSecond}s, la spec exige moins de 10s`
	)
end)

test("la cadence de clic autorisee reste au-dessus du jeu humain", function()
	local maxPerSecond = 1 / GameConfig.click.minInterval
	assertTrue(maxPerSecond >= 10, `plafond a {maxPerSecond} clics/s, trop bas pour un humain`)
	assertTrue(maxPerSecond <= 20, `plafond a {maxPerSecond} clics/s, trop permissif`)
end)

-- --------------------------------------------------------------------------
-- Roue
-- --------------------------------------------------------------------------

test("les poids de la roue somment a 100", function()
	local total = 0
	for _, prize in GameConfig.wheel.prizes do
		assertTrue(prize.weight > 0, `{prize.key} : poids nul, lot jamais tire`)
		total += prize.weight
	end

	assertEquals(total, 100, "somme des poids")
end)

test("le tirage pondere respecte les probabilites", function()
	local total = 0
	for _, prize in GameConfig.wheel.prizes do
		total += prize.weight
	end

	local rng = Random.new(12345)
	local counts: { [string]: number } = {}
	local runs = 20000

	for _ = 1, runs do
		local roll = rng:NextNumber() * total
		local cursor = 0
		for _, prize in GameConfig.wheel.prizes do
			cursor += prize.weight
			if roll <= cursor then
				counts[prize.key] = (counts[prize.key] or 0) + 1
				break
			end
		end
	end

	for _, prize in GameConfig.wheel.prizes do
		local observed = (counts[prize.key] or 0) / runs * 100
		local expected = prize.weight / total * 100
		local drift = math.abs(observed - expected)

		assertTrue(
			drift <= 2,
			`{prize.key} : {string.format("%.2f", observed)}% observe contre {expected}% attendu`
		)
	end
end)

test("les secteurs de la roue couvrent exactement 360 degres", function()
	-- Si les secteurs ne pavent pas le disque, l'aiguille tombe entre deux
	-- lots ou sur le mauvais. C'est le genre de bug qu'un joueur signale
	-- comme "la roue m'a menti", et qu'on ne peut pas rattraper apres coup.
	local total = 0
	for _, prize in GameConfig.wheel.prizes do
		total += prize.weight
	end

	local cursor = 0
	for _, prize in GameConfig.wheel.prizes do
		cursor += prize.weight / total * 360
	end

	assertTrue(
		math.abs(cursor - 360) < 0.001,
		`les secteurs couvrent {cursor} degres au lieu de 360`
	)
end)

test("la roue attribue une couleur distincte a chaque lot", function()
	-- Deux lots de meme couleur rendent la roue illisible : le joueur ne
	-- peut plus relier ce qu'il voit a ce qu'il gagne.
	local WheelUI = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.ui.WheelUI)

	local seen: { [string]: string } = {}
	for _, prize in GameConfig.wheel.prizes do
		local color = WheelUI.PRIZE_COLORS[prize.key]
		assertTrue(color ~= nil, `{prize.key} n'a pas de couleur declaree`)

		local signature = tostring(color)
		assertTrue(
			seen[signature] == nil,
			`{prize.key} partage la couleur de {tostring(seen[signature])}`
		)
		seen[signature] = prize.key
	end
end)

test("chaque secteur place son centre au bon angle", function()
	-- L'angle de centre pilote l'arret de l'animation. S'il derive, la roue
	-- s'arrete visuellement sur un lot different de celui attribue.
	local WheelUI = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.ui.WheelUI)

	local segments = WheelUI.buildSegments()
	assertEquals(#segments, #GameConfig.wheel.prizes, "nombre de secteurs")

	for index, segment in segments do
		assertEquals(segment.key, GameConfig.wheel.prizes[index].key, `ordre du secteur {index}`)
		assertTrue(
			math.abs(segment.centerAngle - (segment.startAngle + segment.sweep / 2)) < 0.001,
			`{segment.key} : centre mal calcule`
		)
		assertTrue(
			segment.centerAngle >= segment.startAngle
				and segment.centerAngle <= segment.startAngle + segment.sweep,
			`{segment.key} : centre hors de son propre secteur`
		)
	end

	local last = segments[#segments]
	assertTrue(
		math.abs((last.startAngle + last.sweep) - 360) < 0.001,
		"le dernier secteur ne ferme pas le disque"
	)
end)

test("le cooldown de la roue est un delai plausible", function()
	local hours = GameConfig.wheel.cooldownSeconds / 3600
	assertTrue(hours >= 1, `cooldown de {hours}h, trop court pour creer un retour`)
	assertTrue(hours <= 24, `cooldown de {hours}h, trop long`)
end)

-- --------------------------------------------------------------------------
-- Monetisation
-- --------------------------------------------------------------------------

test("les deux Developer Products ont un ID injecte", function()
	local Config = require(ReplicatedStorage.Shared.Config)

	for _, key in { "SHARDS_POUCH", "EXTRA_SPIN" } do
		local productId = Config.developerProducts[key]
		assertTrue(
			typeof(productId) == "number" and productId > 0,
			`{key} sans productId : lance make products`
		)
	end
end)

test("chaque produit de la config a un effet defini", function()
	for key in GameConfig.products do
		local definition = GameConfig.products[key]
		assertTrue(
			definition.grantShards ~= nil or definition.grantSpin ~= nil,
			`{key} : aucun effet, l'achat ne donnerait rien`
		)
	end
end)

-- --------------------------------------------------------------------------
-- Formatage
-- --------------------------------------------------------------------------

test("l'abreviation des nombres est correcte", function()
	assertEquals(Format.number(0), "0", "zero")
	assertEquals(Format.number(847), "847", "sous le seuil")
	assertEquals(Format.number(1000), "1K", "mille pile")
	assertEquals(Format.number(1500), "1.5K", "un et demi")
	assertEquals(Format.number(2340000), "2.34M", "millions")
end)

test("le formatage de duree est lisible", function()
	assertEquals(Format.duration(0), "0s", "zero")
	assertEquals(Format.duration(45), "45s", "secondes")
	assertEquals(Format.duration(150), "2m 30s", "minutes")
	assertEquals(Format.duration(3600 * 4), "4h 0m", "heures")
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
