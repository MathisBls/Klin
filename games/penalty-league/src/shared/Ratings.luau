--!strict
--[[
	Traduit une composition en trois notes d'equipe.

	Module PUR. C'est le maillon qui doit rendre le critere 4 de la spec
	verifiable : si changer sa composition ne change pas mesurablement les
	notes, le jeu n'est qu'un generateur de nombres deguise.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cards = require(ReplicatedStorage.Shared.Cards)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)

export type Lineup = { [string]: Cards.Card? }

export type TeamRatings = {
	attack: number,
	midfield: number,
	defence: number,
	overall: number,
}

local Ratings = {}

-- Note d'un poste vide. Pas zero : un poste vide doit handicaper sans
-- rendre l'equipe injouable, sinon un joueur qui perd une carte ne peut
-- plus rien faire.
local EMPTY_RATING = 30

local function ratingOf(lineup: Lineup, position: string): number
	local card = lineup[position]
	return if card then card.rating else EMPTY_RATING
end

--[[
	Calcule les notes. Formules de la spec :

		Attaque  = ATT * 0.7 + MID * 0.3
		Milieu   = MID * 0.7 + (ATT + DEF) * 0.15
		Defense  = DEF * 0.7 + GK  * 0.3

	Le remplacant ajoute 5 % de sa note au poste le plus faible : il a une
	valeur reelle sans compliquer la lecture.
]]
function Ratings.compute(lineup: Lineup): TeamRatings
	local gk = ratingOf(lineup, "GK")
	local def = ratingOf(lineup, "DEF")
	local mid = ratingOf(lineup, "MID")
	local att = ratingOf(lineup, "ATT")

	local attack = att * 0.7 + mid * 0.3
	local midfield = mid * 0.7 + (att + def) * 0.15
	local defence = def * 0.7 + gk * 0.3

	local sub = lineup.SUB
	if sub then
		local bonus = sub.rating * 0.05
		local lowest = math.min(attack, midfield, defence)

		if lowest == attack then
			attack += bonus
		elseif lowest == midfield then
			midfield += bonus
		else
			defence += bonus
		end
	end

	return {
		attack = attack,
		midfield = midfield,
		defence = defence,
		overall = (attack + midfield + defence) / 3,
	}
end

--[[ Note du gardien, utilisee par la resolution des penalties. ]]
function Ratings.keeperRating(lineup: Lineup): number
	return ratingOf(lineup, "GK")
end

--[[
	Compose une equipe generee pour un club adverse d'un niveau donne.
	Sert a peupler une division quand le pool de joueurs reels est trop
	mince : un classement vide decourage plus qu'il ne motive.
]]
function Ratings.generateLineup(rng: Random, targetRating: number): Lineup
	local lineup: Lineup = {}

	for _, position in GameConfig.positions do
		-- Plus ou moins 8 points autour de la cible : les clubs generes
		-- ont des forces et des faiblesses, comme ceux des joueurs.
		local rating = math.clamp(targetRating + rng:NextInteger(-8, 8), 40, 99)
		local rarity = Cards.rarityForRating(rating)

		lineup[position] = {
			id = `bot:{position}:{rating}`,
			name = `Joueur {position}`,
			position = position :: any,
			rating = rating,
			rarity = if rarity then rarity.key else "BRONZE",
		}
	end

	return lineup
end

return Ratings
