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
local Receipts = require(systems.Receipts)
local Save = require(systems.Save)
local Shop = require(systems.Shop)
local Wheel = require(systems.Wheel)

Remotes.init()
Save.init()
Currency.init()
Receipts.init()

local clickRemote = Remotes.get("Click") :: RemoteEvent
local buyRemote = Remotes.get("BuyUpgrade") :: RemoteFunction
local spinRemote = Remotes.get("Spin") :: RemoteFunction
local promptRemote = Remotes.get("PromptPurchase") :: RemoteEvent
local stateRemote = Remotes.get("StateChanged") :: RemoteEvent
local feedbackRemote = Remotes.get("ClickFeedback") :: RemoteEvent
local spinPlayedRemote = Remotes.get("SpinPlayed") :: RemoteEvent

-- Dernier clic accepte par joueur, pour le plafond anti-autoclicker.
local lastClickAt: { [Player]: number } = {}

--[[
	Assemble l'etat repliqué. Envoye par valeur : un paquet perdu ne doit
	pas desynchroniser l'affichage.
]]
local function buildState(player: Player): Remotes.PlayerState?
	local data = Save.get(player)
	if data == nil then
		return nil
	end

	return {
		shards = data.shards,
		upgrades = table.clone(data.upgrades),
		clickGain = Shop.getClickGain(player),
		perSecond = Shop.getPerSecond(player),
		multiplier = Currency.getMultiplier(player),
		spinAvailableAt = data.spinAvailableAt,
		ownedProducts = 0,
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

-- Toute rotation de roue est annoncee au joueur, qu'elle vienne de son
-- bouton ou d'un achat traite dans ProcessReceipt. Le client n'a alors
-- qu'un seul chemin d'animation a gerer.
Wheel.onSpin(function(player, prize)
	spinPlayedRemote:FireClient(player, {
		prizeKey = prize.key,
		displayName = prize.displayName,
	})
end)

-- --------------------------------------------------------------------------
-- Handlers
-- --------------------------------------------------------------------------

clickRemote.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	local previous = lastClickAt[player]

	-- Plafond de cadence. Ne bloque pas un humain (12 clics/s est au-dessus
	-- de la pointe humaine) mais borne ce qu'un autoclicker peut extraire.
	if previous and now - previous < GameConfig.click.minInterval then
		return
	end
	lastClickAt[player] = now

	local gain = Shop.getClickGain(player)
	if Currency.add(player, gain) == nil then
		return
	end

	Save.update(player, function(data)
		data.totalClicks += 1
	end)

	feedbackRemote:FireClient(player, gain)
end)

buyRemote.OnServerInvoke = function(player: Player, key: any)
	if typeof(key) ~= "string" then
		return { success = false, message = "requete invalide" }
	end

	local success, message = Shop.buyUpgrade(player, key)
	if success then
		pushState(player)
	end

	return { success = success, message = message }
end

spinRemote.OnServerInvoke = function(player: Player)
	local success, _prize, message = Wheel.spin(player)
	if not success then
		return { success = false, message = message }
	end

	-- Le detail du lot part par SpinPlayed, pas ici : l'animation doit
	-- suivre le meme chemin qu'un tour achete en Robux.
	pushState(player)
	return { success = true }
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
-- Boucles
-- --------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	-- Attendre le profil avant le premier envoi, sinon le client affiche
	-- zero puis saute a la vraie valeur.
	task.spawn(function()
		if Save.await(player) then
			pushState(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastClickAt[player] = nil
end)

-- Production automatique. Un seul timer pour tous les joueurs, pas une
-- boucle par joueur ni une boucle par frame.
task.spawn(function()
	while true do
		task.wait(GameConfig.apprenticeTickSeconds)

		for _, player in Players:GetPlayers() do
			local perSecond = Shop.getPerSecond(player)
			if perSecond > 0 then
				Currency.add(player, perSecond * GameConfig.apprenticeTickSeconds)
			end
		end
	end
end)

print(`[Klin] {GameConfig.slug} - serveur pret`)
