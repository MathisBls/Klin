--!strict
--[[
	Suite de tests executee par `run-in-roblox` sur build/game.rbxl.

	Ce n'est pas un framework : chaque test est une fonction qui leve une
	erreur si quelque chose ne va pas. run-in-roblox remonte le code de
	sortie, ce qui suffit pour bloquer un `make publish` casse.

	A mesure que le generateur produira du code, ajouter ici les tests
	prevus par les skills (achat simule, sauvegarde, economie).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Test = {
	name: string,
	run: () -> (),
}

local tests: { Test } = {}

local function test(name: string, run: () -> ())
	table.insert(tests, { name = name, run = run })
end

local function assertEquals<T>(actual: T, expected: T, what: string)
	if actual ~= expected then
		error(`{what} : attendu {tostring(expected)}, obtenu {tostring(actual)}`, 2)
	end
end

-- --------------------------------------------------------------------------
-- Tests
-- --------------------------------------------------------------------------

test("le dossier Shared est replique", function()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if shared == nil then
		error("ReplicatedStorage.Shared absent : le mapping Rojo est casse")
	end
end)

test("Version se charge et est gele", function()
	local Version = require(ReplicatedStorage.Shared.Version)
	assertEquals(Version.name, "Klin", "Version.name")

	if not table.isfrozen(Version :: any) then
		error("Version devrait etre gele (table.freeze)")
	end
end)

test("Config existe des que le pipeline a tourne", function()
	-- Config.luau est genere par `make assets` / `make products`.
	-- Avant le premier run il n'existe pas : ce n'est pas une erreur.
	local config = ReplicatedStorage.Shared:FindFirstChild("Config")
	if config == nil then
		print("[skip] Config.luau pas encore genere")
		return
	end

	local Config = require(config)
	for _, field in { "assets", "developerProducts", "gamePasses" } do
		if typeof((Config :: any)[field]) ~= "table" then
			error(`Config.{field} devrait etre une table`)
		end
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
