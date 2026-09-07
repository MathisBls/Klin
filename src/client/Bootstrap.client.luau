--!strict
--[[
	Point d'entree client. Vide pour l'instant, meme role que Bootstrap.server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Version = require(ReplicatedStorage.Shared.Version)

print(`[Klin] client demarre — {Version.name} v{Version.version}`)
