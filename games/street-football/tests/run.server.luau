--!strict
--[[
	Tests du lobby.

	La session d'execution ne demarre pas le jeu : les scripts serveur ne
	tournent pas d'eux-memes. On appelle donc Decor.build() et Signs.build()
	nous-memes, ce qui a l'avantage de tester exactement ce que fait le
	Bootstrap plutot qu'un chemin plus permissif.

	Ce que ces tests NE font pas : juger le rendu. Ca se regarde.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Layout = require(ReplicatedStorage.Shared.config.LobbyLayout)

type Test = { name: string, run: () -> () }

local tests: { Test } = {}

local function test(name: string, run: () -> ())
	table.insert(tests, { name = name, run = run })
end

local function assertTrue(condition: boolean, what: string)
	if not condition then
		error(what, 2)
	end
end

local function assertEquals(actual: any, expected: any, what: string)
	if actual ~= expected then
		error(`{what} : attendu {tostring(expected)}, obtenu {tostring(actual)}`, 2)
	end
end

-- --------------------------------------------------------------------------
-- Layout
-- --------------------------------------------------------------------------

test("chaque objet du layout reference un asset declare", function()
	-- Une cle inconnue poserait un trou silencieux dans le decor.
	for _, prop in Layout.props do
		assertTrue(Layout.assets[prop.asset] ~= nil, `prop : asset inconnu {prop.asset}`)
	end
	for _, line in Layout.lines do
		assertTrue(Layout.assets[line.asset] ~= nil, `ligne : asset inconnu {line.asset}`)
	end
end)

test("chaque asset declare a un id plausible", function()
	for key, entry in Layout.assets do
		assertTrue(typeof(entry.id) == "number" and entry.id > 0, `{key} : id invalide`)
		assertTrue(entry.parts > 0, `{key} : nombre de parts non renseigne`)
	end
end)

test("les lignes de decor ont un espacement utilisable", function()
	for _, line in Layout.lines do
		assertTrue(line.spacing > 0, `{line.asset} : espacement nul, boucle infinie`)

		local length = (line.to - line.from).Magnitude
		assertTrue(length > 0, `{line.asset} : segment de longueur nulle`)
		assertTrue(
			length / line.spacing < 200,
			`{line.asset} : {math.floor(length / line.spacing)} copies, trop`
		)
	end
end)

test("chaque panneau a un texte non vide et court", function()
	for _, sign in Layout.signs do
		assertTrue(#sign.title > 0, "panneau sans titre")
		assertTrue(#sign.subtitle > 0, `{sign.title} : pas de sous-titre`)
		-- Un panneau qu'on doit lire n'est plus un panneau.
		assertTrue(#sign.subtitle <= 60, `{sign.title} : sous-titre trop long`)
	end
end)

-- --------------------------------------------------------------------------
-- Architecture
-- --------------------------------------------------------------------------

test("le lobby fait au moins 400 studs de cote", function()
	local ground = workspace:FindFirstChild("Ground", true)
	assertTrue(ground ~= nil, "sol introuvable")
	assertTrue(
		ground.Size.X >= 400 and ground.Size.Z >= 400,
		`sol de {ground.Size.X}x{ground.Size.Z}, la spec exige 400 minimum`
	)
end)

test("les zones du plan de masse existent toutes", function()
	for _, name in { "Plaza", "PathNorth", "PathSouth", "PathEast", "PathWest" } do
		assertTrue(workspace:FindFirstChild(name, true) ~= nil, `{name} manquant`)
	end
	for _, name in { "GateBeam", "ShopRoof1", "TrainGoalBar", "Belvedere", "FountainTop" } do
		assertTrue(workspace:FindFirstChild(name, true) ~= nil, `{name} manquant`)
	end
end)

test("le spawn est pose sur du sol et regarde vers les terrains", function()
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	assertTrue(spawn ~= nil, "aucun SpawnLocation")

	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { spawn }

	local hit = workspace:Raycast(spawn.Position, Vector3.new(0, -20, 0), parameters)
	assertTrue(hit ~= nil, "rien sous le spawn : le joueur tomberait")

	-- Les terrains sont au nord (Z negatif). Le joueur doit les avoir en
	-- face sans tourner la camera : c'est le hook des dix secondes.
	local look = spawn.CFrame.LookVector
	assertTrue(look.Z < -0.5, `le spawn regarde vers {look}, pas vers les terrains`)
end)

test("toutes les parts de l'architecture sont ancrees", function()
	local floating = {}
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and not instance.Anchored then
			table.insert(floating, instance:GetFullName())
		end
	end
	assertTrue(#floating == 0, `parts non ancrees : {table.concat(floating, ", ")}`)
end)

-- --------------------------------------------------------------------------
-- Decor charge
-- --------------------------------------------------------------------------

test("le decor se construit et pose des objets", function()
	local Decor = require(ServerScriptService.Server.systems.Decor)
	Decor.build()

	local folder = workspace:FindFirstChild("Decor")
	assertTrue(folder ~= nil, "Decor.build n'a cree aucun dossier")

	local count = #folder:GetChildren()
	print(`       {count} objets de decor poses`)
	assertTrue(count >= 40, `seulement {count} objets de decor, la map sera vide`)
end)

test("aucun script tiers n'entre dans le jeu", function()
	-- LE test de securite. Un modele du Creator Store peut contenir un
	-- Script : c'est le vecteur de backdoor le plus courant sur Roblox.
	local folder = workspace:FindFirstChild("Decor")
	assertTrue(folder ~= nil, "decor absent")

	local scripts = {}
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			table.insert(scripts, descendant:GetFullName())
		end
	end

	assertEquals(#scripts, 0, `scripts tiers charges : {table.concat(scripts, ", ")}`)
end)

test("le decor tient dans son budget de parts", function()
	local Decor = require(ServerScriptService.Server.systems.Decor)
	local stats = Decor.stats()

	print(`       {stats.placedParts} parts de decor, {stats.cachedAssets} assets charges`)
	assertTrue(
		stats.placedParts <= Layout.partBudget,
		`{stats.placedParts} parts, budget {Layout.partBudget}`
	)
	-- Charger une fois et cloner : sinon le demarrage prendrait des dizaines
	-- de secondes.
	assertTrue(
		stats.cachedAssets <= 14,
		`{stats.cachedAssets} assets charges, le cache ne fonctionne pas`
	)
end)

test("tout le decor est ancre", function()
	local folder = workspace:FindFirstChild("Decor")
	assertTrue(folder ~= nil, "decor absent")

	local floating = 0
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			floating += 1
		end
	end
	assertEquals(floating, 0, `{floating} part(s) de decor non ancree(s)`)
end)

test("les panneaux se construisent avec leur texte", function()
	local Signs = require(ServerScriptService.Server.systems.Signs)
	Signs.build()

	local folder = workspace:FindFirstChild("Signs")
	assertTrue(folder ~= nil, "Signs.build n'a cree aucun dossier")
	assertEquals(#folder:GetChildren(), #Layout.signs, "nombre de panneaux")

	for _, anchor in folder:GetChildren() do
		local board = anchor:FindFirstChildWhichIsA("BillboardGui")
		assertTrue(board ~= nil, `{anchor.Name} : pas de BillboardGui`)

		local labels = 0
		for _, descendant in board:GetDescendants() do
			if descendant:IsA("TextLabel") and descendant.Text ~= "" then
				labels += 1
			end
		end
		assertTrue(labels >= 2, `{anchor.Name} : titre ou sous-titre vide`)
	end
end)

-- --------------------------------------------------------------------------
-- Eclairage
-- --------------------------------------------------------------------------

test("l'atmosphere et les effets sont en place", function()
	-- Mes deux maps precedentes n'avaient rien de tout ca, et c'est la
	-- premiere raison pour laquelle elles paraissaient mortes.
	local Lighting = game:GetService("Lighting")

	local required = {
		"Atmosphere",
		"BloomEffect",
		"SunRaysEffect",
		"ColorCorrectionEffect",
		"Sky",
	}

	for _, className in required do
		assertTrue(
			Lighting:FindFirstChildWhichIsA(className) ~= nil,
			`{className} absent de Lighting`
		)
	end

	assertTrue(Lighting.GlobalShadows, "ombres portees desactivees")
	assertTrue(Lighting.Brightness > 1, "eclairage trop faible")
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
