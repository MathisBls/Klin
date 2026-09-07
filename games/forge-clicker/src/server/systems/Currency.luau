--!strict
--[[
	Monnaie du jeu : lecture, gain, depense, multiplicateurs temporaires.
	Tout ce qui coute ou rapporte passe par ici, ce qui donne un seul
	endroit ou auditer l'economie.

	Le client n'ajoute jamais de monnaie : il envoie une intention, le
	serveur decide du montant.
]]

local Players = game:GetService("Players")

local ServerScriptService = game:GetService("ServerScriptService")
local Save = require(ServerScriptService.Server.systems.Save)

export type Multiplier = {
	value: number,
	-- Horodatage unix d'expiration. 0 = permanent.
	expiresAt: number,
}

local Currency = {}

-- Multiplicateurs en memoire, par joueur puis par source. Non persistes :
-- un bonus de 5 minutes n'a pas de sens apres une deconnexion.
local multipliers: { [Player]: { [string]: Multiplier } } = {}

local changedCallbacks: { (Player) -> () } = {}

local function notify(player: Player)
	for _, callback in changedCallbacks do
		task.spawn(callback, player)
	end
end

--[[ Enregistre un observateur appele a chaque changement de solde. ]]
function Currency.onChanged(callback: (Player) -> ())
	table.insert(changedCallbacks, callback)
end

--[[
	Un montant valide est un entier fini positif. Rejeter ici plutot que
	dans chaque appelant : `add(player, -1000)` ne doit pas etre un moyen
	de vider le compte de quelqu'un.
]]
local function isValidAmount(amount: number): boolean
	return typeof(amount) == "number"
		and amount == amount -- ecarte NaN
		and amount ~= math.huge
		and amount >= 0
		and amount == math.floor(amount)
end

function Currency.get(player: Player): number
	local data = Save.get(player)
	return if data then data.shards else 0
end

--[[
	Ajoute des eclats. Renvoie le nouveau solde, ou nil si le profil n'est
	pas charge (l'appelant doit alors renoncer, pas reessayer en boucle).
]]
function Currency.add(player: Player, amount: number): number?
	if not isValidAmount(amount) or amount == 0 then
		return Currency.get(player)
	end

	local newTotal: number? = nil
	local ok = Save.update(player, function(data)
		data.shards += amount
		newTotal = data.shards
	end)

	if not ok then
		return nil
	end

	notify(player)
	return newTotal
end

--[[
	Debite si le solde suffit. Verification et debit dans la meme
	operation : deux achats simultanes ne doivent pas passer tous les deux
	avec un solde qui n'en couvre qu'un.
]]
function Currency.spend(player: Player, amount: number): boolean
	if not isValidAmount(amount) then
		return false
	end

	local success = false
	Save.update(player, function(data)
		if data.shards >= amount then
			data.shards -= amount
			success = true
		end
	end)

	if success then
		notify(player)
	end
	return success
end

--[[
	Pose un multiplicateur identifie par sa source. Deux bonus simultanes
	de sources differentes se cumulent et se retirent independamment.
	`duration` a 0 rend le bonus permanent.
]]
function Currency.setMultiplier(player: Player, source: string, value: number, duration: number)
	if not multipliers[player] then
		multipliers[player] = {}
	end

	multipliers[player][source] = {
		value = value,
		expiresAt = if duration > 0 then os.time() + duration else 0,
	}

	notify(player)
end

--[[
	Produit des multiplicateurs actifs. Les expires sont nettoyes au
	passage : pas besoin d'une boucle de maintenance separee.
]]
function Currency.getMultiplier(player: Player): number
	local sources = multipliers[player]
	if sources == nil then
		return 1
	end

	local now = os.time()
	local total = 1

	for source, entry in sources do
		if entry.expiresAt ~= 0 and entry.expiresAt <= now then
			sources[source] = nil
		else
			total *= entry.value
		end
	end

	return total
end

function Currency.init()
	Players.PlayerRemoving:Connect(function(player)
		multipliers[player] = nil
	end)
end

return Currency
