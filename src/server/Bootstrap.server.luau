--!strict
--[[
	Point d'entree serveur. Vide pour l'instant : le generateur de jeu
	remplira ce fichier. Il existe pour que `make test` ait quelque chose
	a verifier (le jeu demarre sans erreur).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Version = require(ReplicatedStorage.Shared.Version)

print(`[Klin] serveur demarre — {Version.name} v{Version.version}`)
