--!strict
--[[
	Point d'entree serveur : cable les systemes, valide les remotes,
	replique l'etat.

	Tout handler de remote valide ses arguments avant de les utiliser.
	Un joueur peut envoyer n'importe quoi sur un RemoteEvent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local systems = ServerScriptService.Server.systems
local Currency = require(systems.Currency)
local League = require(systems.League)
local Match = require(systems.Match)
local Packs = require(systems.Packs)
local Receipts = require(systems.Receipts)
local Save = require(systems.Save)
local Squad = require(systems.Squad)

Remotes.init()
Save.init()
Currency.init()
Match.init()
Receipts.init()

local playRemote = Remotes.get("PlayMatch") :: RemoteFunction
local penaltyRemote = Remotes.get("TakePenalty") :: RemoteFunction
local lineupRemote = Remotes.get("SetLineup") :: RemoteFunction
local packRemote = Remotes.get("OpenPack") :: RemoteFunction
local promptRemote = Remotes.get("PromptPurchase") :: RemoteEvent
local standingsRemote = Remotes.get("GetStandings") :: RemoteFunction
local stateRemote = Remotes.get("StateChanged") :: RemoteEvent
local packOpenedRemote = Remotes.get("PackOpened") :: RemoteEvent

--[[ Assemble l'etat repliqué. Envoye par valeur, jamais par delta. ]]
local function buildState(player: Player): Remotes.PlayerState?
	local data = Save.get(player)
	if data == nil then
		return nil
	end

	-- Copie : envoyer la table de Squad telle quelle exposerait une
	-- reference que le client ne doit pas pouvoir influencer.
	local lineup = table.clone(Squad.lineup(player))

	return {
		clubName = data.clubName,
		credits = data.credits,
		division = data.division,
		matchday = data.matchday,
		cards = Squad.list(player),
		lineup = lineup,
		ratings = Squad.ratings(player),
		seasonPoints = data.seasonPoints,
		hasSeasonPass = Currency.getMultiplier(player) > 1,
	}
end

local function pushState(player: Player)
	local state = buildState(player)
	if state then
		stateRemote:FireClient(player, state)
	end
end

Currency.onChanged(pushState)
Receipts.onGranted(pushState)

-- Toute ouverture de pochette est annoncee, qu'elle vienne des credits ou
-- d'un achat en Robux. Un seul chemin d'animation cote client.
Packs.onOpened(function(player, result)
	packOpenedRemote:FireClient(player, result)
	pushState(player)
end)

-- --------------------------------------------------------------------------
-- Handlers
-- --------------------------------------------------------------------------

playRemote.OnServerInvoke = function(player: Player)
	local success, message = Match.play(player)
	pushState(player)
	return { success = success, message = message }
end

penaltyRemote.OnServerInvoke = function(player: Player, aim: any)
	-- La validation complete est dans Penalty.isValidAim, appelee par
	-- Match.submitPenalty : un seul endroit ou borner les entrees.
	local outcome = Match.submitPenalty(player, aim)
	if outcome == nil then
		return { success = false, message = "aucun penalty en attente" }
	end
	return { success = true, outcome = outcome }
end

lineupRemote.OnServerInvoke = function(player: Player, position: any, cardId: any)
	if typeof(position) ~= "string" then
		return { success = false, message = "requete invalide" }
	end
	if cardId ~= nil and typeof(cardId) ~= "string" then
		return { success = false, message = "requete invalide" }
	end

	local success, message = Squad.setPosition(player, position, cardId)
	if success then
		League.publish(player)
		pushState(player)
	end

	return { success = success, message = message }
end

packRemote.OnServerInvoke = function(player: Player)
	local result = Packs.buy(player)
	pushState(player)
	return result
end

standingsRemote.OnServerInvoke = function(player: Player)
	return League.standings(player)
end

promptRemote.OnServerEvent:Connect(function(player: Player, key: any)
	if typeof(key) ~= "string" then
		return
	end
	if GameConfig.products[key] == nil then
		return
	end

	Receipts.prompt(player, key)
end)

-- --------------------------------------------------------------------------
-- Connexion
-- --------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		if Save.await(player) == nil then
			return
		end

		-- L'effectif de depart doit exister avant le premier match, sinon
		-- le joueur jouerait avec cinq postes vides.
		Squad.grantStarterSquad(player, Random.new(player.UserId))
		Squad.autoFill(player)

		Receipts.applyGamePasses(player)
		League.publish(player)

		pushState(player)
	end)
end)

print(`[Klin] {GameConfig.slug} - serveur pret`)
