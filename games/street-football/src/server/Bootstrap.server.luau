--!strict
--[[
	Point d'entree serveur du lobby.

	Le decor est monte au demarrage, une fois pour toutes. Il n'y a pas
	encore de gameplay : cette etape ne livre que le lieu, et le football
	viendra dans une seconde passe.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local systems = ServerScriptService.Server.systems
local Decor = require(systems.Decor)
local Signs = require(systems.Signs)

local started = os.clock()

Decor.build()
Signs.build()

print(`[Klin] street-football - lobby pret en {string.format("%.1f", os.clock() - started)}s`)
