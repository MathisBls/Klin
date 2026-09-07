--!strict
--[[
	Roue de recompenses a rarete ponderee.

	Le tirage est serveur. Le client anime une roue qui s'arrete sur un
	resultat deja decide - jamais l'inverse.

	Le cooldown est stocke en horodatage absolu, pas en compteur : un
	compteur decremente se remettrait a zero a chaque deconnexion.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Currency = require(ServerScriptService.Server.systems.Currency)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Save = require(ServerScriptService.Server.systems.Save)

local Wheel = {}

local TOTAL_WEIGHT = 0
for _, prize in GameConfig.wheel.prizes do
	TOTAL_WEIGHT += prize.weight
end

-- Une config dont les poids somment a zero rendrait le tirage impossible.
-- Mieux vaut echouer au demarrage qu'au premier tour d'un joueur.
assert(TOTAL_WEIGHT > 0, "la somme des poids de la roue doit etre > 0")

-- Une source d'alea par serveur, jamais math.random global : deux joueurs
-- ne doivent pas pouvoir tirer la meme sequence.
local rng = Random.new()

--[[ Secondes restantes avant le prochain tour gratuit, 0 si disponible. ]]
function Wheel.getCooldown(player: Player): number
	local data = Save.get(player)
	if data == nil then
		return math.huge
	end
	return math.max(0, data.spinAvailableAt - os.time())
end

function Wheel.canSpin(player: Player): boolean
	return Wheel.getCooldown(player) <= 0
end

--[[ Tirage pondere. Isole pour etre testable sans joueur. ]]
function Wheel.draw(): GameConfig.Prize
	local roll = rng:NextNumber() * TOTAL_WEIGHT
	local cursor = 0

	for _, prize in GameConfig.wheel.prizes do
		cursor += prize.weight
		if roll <= cursor then
			return prize
		end
	end

	-- Filet en cas d'imprecision flottante sur le dernier intervalle.
	return GameConfig.wheel.prizes[#GameConfig.wheel.prizes]
end

local function grant(player: Player, prize: GameConfig.Prize)
	if prize.reward.kind == "shards" then
		Currency.add(player, prize.reward.amount)
	elseif prize.reward.kind == "multiplier" then
		Currency.setMultiplier(player, "wheel", prize.reward.value, prize.reward.duration)
	end
end

--[[
	Tourne la roue. `ignoreCooldown` sert au tour achete en Robux.

	Ordre impose : verifier le cooldown, le poser, tirer, attribuer. Poser
	le cooldown avant le tirage empeche deux appels simultanes de passer
	tous les deux.
]]
function Wheel.spin(player: Player, ignoreCooldown: boolean?): (boolean, GameConfig.Prize?, string?)
	local data = Save.get(player)
	if data == nil then
		return false, nil, "sauvegarde pas encore chargee"
	end

	if not ignoreCooldown and not Wheel.canSpin(player) then
		return false, nil, "roue pas encore disponible"
	end

	if not ignoreCooldown then
		Save.update(player, function(profile)
			profile.spinAvailableAt = os.time() + GameConfig.wheel.cooldownSeconds
		end)
	end

	local prize = Wheel.draw()
	grant(player, prize)

	return true, prize, nil
end

return Wheel
