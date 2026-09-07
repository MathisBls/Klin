--!strict
--[[
	Resolution d'un tir au but. Module PUR.

	LE PRINCIPE QUI EVITE TOUS LES PROBLEMES RESEAU

	Le ballon n'est pas un objet physique. Le client envoie trois nombres -
	coin vise et puissance - le serveur decide du resultat par tirage
	pondere, et la trajectoire affichee n'est qu'un tween qui illustre une
	decision deja prise.

	Aucune propriete reseau a arbitrer, aucune desynchronisation possible,
	aucune triche : un client modifie ne peut envoyer que des nombres, qui
	sont bornes et valides ici.

	DIFFICULTE

	Viser une lucarne est plus dur que le centre, et plus la frappe est
	puissante moins elle est precise. La difficulte combine les deux, ce
	qui donne au joueur une vraie decision plutot qu'un bouton a presser.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)

export type Aim = {
	-- Position visee dans le but, normalisee. x : 0 poteau gauche,
	-- 1 poteau droit. y : 0 au sol, 1 sous la barre.
	x: number,
	y: number,
	-- 0 frappe placee, 1 frappe maximale.
	power: number,
}

export type Outcome = {
	result: "goal" | "saved" | "missed",
	-- Cote choisi par le gardien, pour l'animation.
	keeperDive: "left" | "center" | "right",
	difficulty: number,
}

local Penalty = {}

--[[
	Une visee valide est faite de trois nombres finis dans [0, 1]. Tout le
	reste est rejete : c'est la seule chose que le client envoie, donc la
	seule surface qu'un client modifie peut attaquer.
]]
function Penalty.isValidAim(aim: any): boolean
	if typeof(aim) ~= "table" then
		return false
	end

	for _, key in { "x", "y", "power" } do
		local value = aim[key]
		if typeof(value) ~= "number" then
			return false
		end
		-- Ecarte NaN (qui n'est egal a rien, pas meme a lui-meme) et les
		-- infinis, que les comparaisons de bornes laisseraient passer.
		if value ~= value or value == math.huge or value == -math.huge then
			return false
		end
		if value < 0 or value > 1 then
			return false
		end
	end

	return true
end

--[[
	Difficulte d'un tir, dans [0, 1].

	Un tir au ras du poteau en haut est le plus dur ; le centre a mi-hauteur
	le plus facile. La puissance ajoute sa part : elle augmente les chances
	de battre le gardien mais degrade la precision.
]]
function Penalty.difficulty(aim: Aim): number
	-- Distance au centre sur chaque axe, ramenee dans [0, 1].
	local lateral = math.abs(aim.x - 0.5) * 2
	local height = aim.y

	local placement = (lateral * 0.6 + height * 0.4)
	return math.clamp(placement * 0.75 + aim.power * 0.25, 0, 1)
end

--[[
	Resout le tir. `rng` vient de l'appelant pour que les tests soient
	reproductibles ; en jeu, le serveur en cree un par tir.
]]
function Penalty.resolve(aim: Aim, keeperRating: number, rng: Random): Outcome
	local config = GameConfig.penalty
	local difficulty = Penalty.difficulty(aim)

	-- Le gardien plonge du cote vise deux fois sur trois. Le tiers restant
	-- laisse au joueur le sentiment d'avoir trompe le gardien plutot que
	-- d'avoir gagne a la loterie.
	local dive: "left" | "center" | "right"
	if rng:NextNumber() < 0.66 then
		dive = if aim.x < 0.4 then "left" elseif aim.x > 0.6 then "right" else "center"
	else
		local roll = rng:NextInteger(1, 3)
		dive = if roll == 1 then "left" elseif roll == 2 then "center" else "right"
	end

	-- Hors cadre d'abord : un tir rate n'atteint jamais le gardien.
	local missChance = config.missBase + config.missDifficultyFactor * difficulty ^ 2
	if rng:NextNumber() < missChance then
		return { result = "missed", keeperDive = dive, difficulty = difficulty }
	end

	local saveChance = config.saveBase
		+ config.savePerRatingPoint * (keeperRating - 60)
		- config.saveDifficultyBonus * difficulty
	saveChance = math.clamp(saveChance, 0.02, 0.90)

	if rng:NextNumber() < saveChance then
		return { result = "saved", keeperDive = dive, difficulty = difficulty }
	end

	return { result = "goal", keeperDive = dive, difficulty = difficulty }
end

return Penalty
