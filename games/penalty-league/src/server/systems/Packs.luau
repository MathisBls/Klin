--!strict
--[[
	Ouverture de pochettes.

	Ordre impose : debiter, puis tirer, puis attribuer. Tirer avant de
	debiter permettrait de couper sa connexion sur une mauvaise pochette
	et de recuperer ses credits.

	Un seul chemin d'ouverture, que la pochette vienne des credits ou d'un
	achat en Robux : sans ca, un joueur qui paie verrait ses cartes
	arriver sans animation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Cards = require(ReplicatedStorage.Shared.Cards)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)

local systems = ServerScriptService.Server.systems
local Currency = require(systems.Currency)
local Squad = require(systems.Squad)

local Packs = {}

export type OpenResult = {
	success: boolean,
	cards: { Cards.Card }?,
	duplicateRefund: number?,
	message: string?,
}

local openCallbacks: { (Player, OpenResult) -> () } = {}

function Packs.onOpened(callback: (Player, OpenResult) -> ())
	table.insert(openCallbacks, callback)
end

--[[
	Tire et attribue une pochette. Ne debite rien : l'appelant a deja paye,
	en credits ou en Robux.
]]
function Packs.grant(player: Player, rarityFloor: string?): OpenResult
	local rng = Random.new()
	local drawn: { Cards.Card } = {}
	local refund = 0

	for index = 1, GameConfig.packs.cardsPerPack do
		-- Le plancher de rarete ne s'applique qu'a la premiere carte : une
		-- Pochette Or garantit un Or, elle ne rend pas les trois cartes Or.
		local floor = if index == 1 then rarityFloor else nil
		local card = Cards.generate(rng, floor)

		local added, credited = Squad.addCard(player, card)
		if not added then
			refund += credited
		end

		table.insert(drawn, card)
	end

	if refund > 0 then
		Currency.add(player, refund)
	end

	local result: OpenResult = {
		success = true,
		cards = drawn,
		duplicateRefund = refund,
	}

	for _, callback in openCallbacks do
		task.spawn(callback, player, result)
	end

	return result
end

--[[ Achete une pochette en credits. ]]
function Packs.buy(player: Player): OpenResult
	if not Currency.spend(player, GameConfig.packs.price) then
		return { success = false, message = "credits insuffisants" }
	end

	return Packs.grant(player)
end

return Packs
