--!strict
--[[
	Cartes joueurs : generation, rarete, valeur.

	Module PUR : aucune dependance a un service Roblox, aucun effet de bord.
	C'est ce qui le rend testable par `make test`, lequel ne demarre pas le
	jeu et ne peut donc rien verifier qui dependrait d'un joueur connecte.

	Toute generation prend un `Random` en argument plutot que d'en creer un :
	l'appelant controle la graine, donc les tests sont reproductibles.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)

export type Card = {
	-- Identifiant stable, derive du nom et de la note. Deux cartes
	-- identiques partagent la meme cle : c'est ce qui permet de detecter
	-- un doublon.
	id: string,
	name: string,
	position: GameConfig.Position,
	rating: number,
	rarity: string,
}

local Cards = {}

-- Noms de fantaisie. Aucun joueur reel : utiliser de vrais noms exposerait
-- le jeu a une reclamation de droit a l'image, et Roblox retire les
-- experiences concernees sans preavis.
local FIRST_NAMES = {
	"Alvaro",
	"Bruno",
	"Cedric",
	"Dario",
	"Emil",
	"Fabio",
	"Gino",
	"Hugo",
	"Ivo",
	"Jonas",
	"Kwame",
	"Lucien",
	"Milos",
	"Nando",
	"Oscar",
	"Pavel",
	"Quim",
	"Rafa",
	"Silas",
	"Teo",
	"Ugo",
	"Vasco",
	"Wim",
	"Yannis",
}

local LAST_NAMES = {
	"Aubert",
	"Belanger",
	"Cortez",
	"Duarte",
	"Espinoza",
	"Ferrand",
	"Grimaldi",
	"Halvorsen",
	"Ibarra",
	"Jankovic",
	"Karlsen",
	"Lombardi",
	"Moreau",
	"Novak",
	"Oyelaran",
	"Petrov",
	"Quintero",
	"Rossi",
	"Sorensen",
	"Traore",
	"Ulloa",
	"Varga",
	"Weiss",
	"Zanetti",
}

local POSITIONS: { GameConfig.Position } = { "GK", "DEF", "MID", "ATT" }

local TOTAL_WEIGHT = 0
for _, rarity in GameConfig.rarities do
	TOTAL_WEIGHT += rarity.weight
end

-- Une config dont les poids somment a zero rendrait le tirage impossible.
-- Mieux vaut echouer au demarrage qu'a la premiere pochette d'un joueur.
assert(TOTAL_WEIGHT > 0, "la somme des poids de rarete doit etre > 0")

--[[ Rarete correspondant a une note, ou nil si la note est hors plages. ]]
function Cards.rarityForRating(rating: number): GameConfig.Rarity?
	for _, rarity in GameConfig.rarities do
		if rating >= rarity.minRating and rating <= rarity.maxRating then
			return rarity
		end
	end
	return nil
end

function Cards.rarityByKey(key: string): GameConfig.Rarity?
	for _, rarity in GameConfig.rarities do
		if rarity.key == key then
			return rarity
		end
	end
	return nil
end

--[[
	Tire une rarete au hasard. `floor` force un plancher : la Pochette Or
	garantit au moins cette rarete, sans jamais empecher de faire mieux.
]]
function Cards.drawRarity(rng: Random, floor: string?): GameConfig.Rarity
	local pool = GameConfig.rarities
	local total = TOTAL_WEIGHT

	if floor then
		local floorIndex: number? = nil
		for index, rarity in GameConfig.rarities do
			if rarity.key == floor then
				floorIndex = index
				break
			end
		end

		if floorIndex then
			local filtered = {}
			total = 0
			for index = floorIndex, #GameConfig.rarities do
				local rarity = GameConfig.rarities[index]
				table.insert(filtered, rarity)
				total += rarity.weight
			end
			pool = filtered
		end
	end

	local roll = rng:NextNumber() * total
	local cursor = 0

	for _, rarity in pool do
		cursor += rarity.weight
		if roll <= cursor then
			return rarity
		end
	end

	-- Filet en cas d'imprecision flottante sur le dernier intervalle.
	return pool[#pool]
end

--[[ Fabrique une carte. Deterministe pour un `rng` donne. ]]
function Cards.generate(rng: Random, rarityFloor: string?): Card
	local rarity = Cards.drawRarity(rng, rarityFloor)
	local rating = rng:NextInteger(rarity.minRating, rarity.maxRating)
	local position = POSITIONS[rng:NextInteger(1, #POSITIONS)]

	local name = `{FIRST_NAMES[rng:NextInteger(1, #FIRST_NAMES)]} {LAST_NAMES[rng:NextInteger(
		1,
		#LAST_NAMES
	)]}`

	return {
		id = `{name}#{rating}`,
		name = name,
		position = position,
		rating = rating,
		rarity = rarity.key,
	}
end

--[[
	Valeur en credits d'une carte. Croit plus vite que la note : une carte
	a 90 doit valoir nettement plus que deux cartes a 45, sinon accumuler du
	bronze serait une strategie.
]]
function Cards.value(card: Card): number
	return math.floor(10 + (card.rating / 10) ^ 3)
end

return Cards
