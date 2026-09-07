--!strict
--[[
	Boutique : les trois ameliorations payees en eclats.

	Le prix est toujours recalcule serveur au moment de l'achat. Le client
	affiche un prix de confort ; un client modifie ne doit pas pouvoir
	acheter au prix du niveau 1 une amelioration de niveau 20.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Currency = require(ServerScriptService.Server.systems.Currency)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Save = require(ServerScriptService.Server.systems.Save)

local Shop = {}

local byKey: { [string]: GameConfig.Upgrade } = {}
for _, upgrade in GameConfig.upgrades do
	byKey[upgrade.key] = upgrade
end

function Shop.getDefinition(key: string): GameConfig.Upgrade?
	return byKey[key]
end

function Shop.getLevel(player: Player, key: string): number
	local data = Save.get(player)
	if data == nil then
		return 0
	end
	return data.upgrades[key] or 0
end

--[[
	Prix du prochain niveau. Renvoie nil si l'amelioration est au maximum :
	un nil se distingue d'un prix de 0, qui serait achetable.
]]
function Shop.getPrice(player: Player, key: string): number?
	local definition = byKey[key]
	if definition == nil then
		return nil
	end

	local level = Shop.getLevel(player, key)
	if level >= definition.maxLevel then
		return nil
	end

	return math.floor(definition.basePrice * definition.priceGrowth ^ level)
end

--[[ Gain par clic, ameliorations et multiplicateurs compris. ]]
function Shop.getClickGain(player: Player): number
	local hammer = Shop.getLevel(player, "HAMMER")
	local bellows = Shop.getLevel(player, "BELLOWS")

	local base = GameConfig.click.baseGain + hammer
	local bonus = 1 + 0.10 * bellows

	return math.max(1, math.floor(base * bonus * Currency.getMultiplier(player)))
end

--[[ Production automatique par seconde, multiplicateurs compris. ]]
function Shop.getPerSecond(player: Player): number
	local apprentice = Shop.getLevel(player, "APPRENTICE")
	if apprentice == 0 then
		return 0
	end

	return math.floor(apprentice * Currency.getMultiplier(player))
end

--[[
	Achete un niveau. Renvoie (succes, message d'erreur).

	Ordre impose : verifier la definition, verifier le niveau max, debiter,
	puis seulement incrementer. Incrementer avant de debiter laisserait un
	niveau gratuit si la depense echoue.
]]
function Shop.buyUpgrade(player: Player, key: string): (boolean, string?)
	local definition = byKey[key]
	if definition == nil then
		return false, "amelioration inconnue"
	end

	local data = Save.get(player)
	if data == nil then
		return false, "sauvegarde pas encore chargee"
	end

	local level = data.upgrades[key] or 0
	if level >= definition.maxLevel then
		return false, "niveau maximum atteint"
	end

	local price = math.floor(definition.basePrice * definition.priceGrowth ^ level)
	if not Currency.spend(player, price) then
		return false, "eclats insuffisants"
	end

	Save.update(player, function(profile)
		profile.upgrades[key] = (profile.upgrades[key] or 0) + 1
	end)

	return true, nil
end

return Shop
