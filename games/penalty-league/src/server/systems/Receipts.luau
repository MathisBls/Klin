--!strict
--[[
	Achats en Robux. C'est le fichier ou une erreur coute de l'argent reel
	a quelqu'un, donc celui ou les invariants sont les plus stricts.

	Trois regles qui gouvernent tout :

	1. IDEMPOTENCE. Roblox rappelle ProcessReceipt tant qu'il n'a pas recu
	   PurchaseGranted. Sans memoire des PurchaseId, un joueur recoit sa
	   recompense plusieurs fois pour un seul paiement.

	2. ACCORDER AVANT DE CONFIRMER. On ecrit la recompense dans le profil,
	   on marque le recu, et seulement ensuite on renvoie PurchaseGranted.
	   L'ordre inverse laisse le joueur ayant paye sans rien si le serveur
	   tombe entre les deux.

	3. EN CAS DE DOUTE, NotProcessedYet. Profil non charge, ecriture
	   echouee : ne rien accorder. Roblox rappellera.

	Un seul ProcessReceipt existe dans tout le jeu : c'est un callback
	unique sur MarketplaceService, deux assignations et la seconde ecrase
	la premiere en silence.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Currency = require(ServerScriptService.Server.systems.Currency)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Packs = require(ServerScriptService.Server.systems.Packs)
local Save = require(ServerScriptService.Server.systems.Save)

local Receipts = {}

-- productId Roblox -> cle logique. Construit depuis Config.developerProducts,
-- genere par `make products`. Un produit absent de la config ne sera pas
-- reconnu : on refuse plutot que de deviner.
local productIdToKey: { [number]: string } = {}

local grantCallbacks: { (Player) -> () } = {}

function Receipts.onGranted(callback: (Player) -> ())
	table.insert(grantCallbacks, callback)
end

--[[
	Applique la recompense d'un produit. Renvoie true si tout est ecrit.
	Ne touche pas au registre des recus : c'est l'appelant qui l'ecrit,
	dans la meme passe.
]]
local function applyReward(player: Player, productKey: string): boolean
	if productKey == "CREDITS_LARGE" then
		local amount = GameConfig.products.CREDITS_LARGE.grantCredits
		return Currency.add(player, amount) ~= nil
	end

	if productKey == "PACK_GOLD" then
		-- Le plancher de rarete est precisement ce que le joueur a paye.
		local floor = GameConfig.products.PACK_GOLD.guaranteedRarity
		return Packs.grant(player, floor).success
	end

	warn(`[Receipts] produit sans effet defini : {productKey}`)
	return false
end

--[[
	Multiplicateur de credits du Pass Saison, pose a la connexion.

	UserOwnsGamePassAsync peut echouer reseau : on enveloppe dans un pcall
	et on conclut a l'absence seulement si l'appel a reussi. Conclure sur
	une erreur reseau priverait un joueur de ce qu'il a paye.
]]
function Receipts.applyGamePasses(player: Player)
	local passId = Config.gamePasses.SEASON_PASS
	if passId == nil then
		return
	end

	local ok, owned = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)

	if not ok then
		warn(`[Receipts] verification du Pass Saison impossible pour {player.Name}`)
		return
	end

	if owned then
		Currency.setMultiplier(
			player,
			"seasonPass",
			GameConfig.gamePasses.SEASON_PASS.creditMultiplier,
			0
		)
	end
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if player == nil then
		-- Le joueur est parti. Roblox rappellera a sa prochaine connexion,
		-- sur ce serveur ou un autre.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local data = Save.get(player)
	if data == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptKey = tostring(info.PurchaseId)

	-- Deja traite : confirmer immediatement, sans re-accorder.
	if data.receipts[receiptKey] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey = productIdToKey[info.ProductId]
	if productKey == nil then
		warn(`[Receipts] productId inconnu : {info.ProductId} - achat non traite`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(applyReward, player, productKey)
	if not ok or not granted then
		warn(`[Receipts] echec d'attribution de {productKey} a {player.Name}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- La recompense est ecrite : on marque le recu dans la meme passe,
	-- avant de confirmer.
	local marked = Save.update(player, function(profile)
		profile.receipts[receiptKey] = true
	end)

	if not marked then
		-- La recompense est donnee mais le recu n'est pas marque. Confirmer
		-- serait pire : au prochain rappel on redonnerait. On laisse Roblox
		-- rappeler, et l'idempotence jouera au tour suivant.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	for _, callback in grantCallbacks do
		task.spawn(callback, player)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--[[ Ouvre le prompt d'achat pour une cle logique. ]]
function Receipts.prompt(player: Player, productKey: string): boolean
	local productId = Config.developerProducts[productKey]
	if productId == nil then
		warn(`[Receipts] pas de productId pour {productKey} - lance make products`)
		return false
	end

	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	return ok
end

function Receipts.init()
	for key, productId in Config.developerProducts do
		productIdToKey[productId] = key
	end

	if next(productIdToKey) == nil then
		warn("[Receipts] aucun Developer Product configure - lance make products")
	end

	MarketplaceService.ProcessReceipt = processReceipt
end

return Receipts
