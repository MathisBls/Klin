--!strict
--[[
	Effectif du joueur : cartes possedees et composition.

	Le profil ne stocke que des references dans `lineup` (poste -> id de
	carte). Dupliquer la carte entiere ferait diverger les deux copies : on
	pourrait vendre une carte et la garder alignee.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Cards = require(ReplicatedStorage.Shared.Cards)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Ratings = require(ReplicatedStorage.Shared.Ratings)
local Save = require(ServerScriptService.Server.systems.Save)

local Squad = {}

local function isValidPosition(position: string): boolean
	for _, known in GameConfig.positions do
		if known == position then
			return true
		end
	end
	return false
end

--[[ Cartes possedees, triees par note decroissante pour l'affichage. ]]
function Squad.list(player: Player): { Cards.Card }
	local data = Save.get(player)
	if data == nil then
		return {}
	end

	local list: { Cards.Card } = {}
	for _, card in data.cards do
		table.insert(list, card)
	end

	table.sort(list, function(left, right)
		if left.rating == right.rating then
			return left.name < right.name
		end
		return left.rating > right.rating
	end)

	return list
end

--[[ Composition resolue en cartes reelles. ]]
function Squad.lineup(player: Player): Ratings.Lineup
	local data = Save.get(player)
	if data == nil then
		return {}
	end

	local lineup: Ratings.Lineup = {}
	for position, cardId in data.lineup do
		lineup[position] = data.cards[cardId]
	end

	return lineup
end

function Squad.ratings(player: Player): Ratings.TeamRatings
	return Ratings.compute(Squad.lineup(player))
end

--[[
	Ajoute une carte. Renvoie (ajoutee, credits rembourses).

	Un doublon n'encombre pas l'effectif : il est revendu automatiquement.
	Sans ca, une pochette sur deux ne donnerait rien de visible au joueur.
]]
function Squad.addCard(player: Player, card: Cards.Card): (boolean, number)
	local data = Save.get(player)
	if data == nil then
		return false, 0
	end

	if data.cards[card.id] ~= nil then
		local refund = math.floor(Cards.value(card) * GameConfig.packs.duplicateRefund)
		return false, refund
	end

	Save.update(player, function(profile)
		profile.cards[card.id] = card
	end)

	-- Poste vide : on aligne la carte tout de suite. Un nouveau joueur ne
	-- doit pas avoir a comprendre la composition pour jouer son premier
	-- match.
	Squad.autoFill(player)

	return true, 0
end

--[[
	Place une carte a un poste. Renvoie (succes, message d'erreur).

	Toute la validation est ici : poste connu, carte possedee, poste
	compatible. Un client modifie enverra exactement cette requete.
]]
function Squad.setPosition(player: Player, position: string, cardId: string?): (boolean, string?)
	if not isValidPosition(position) then
		return false, "poste inconnu"
	end

	local data = Save.get(player)
	if data == nil then
		return false, "sauvegarde pas encore chargee"
	end

	if cardId == nil then
		Save.update(player, function(profile)
			profile.lineup[position] = nil
		end)
		return true, nil
	end

	local card = data.cards[cardId]
	if card == nil then
		return false, "carte non possedee"
	end

	-- Le remplacant accepte n'importe quel poste ; les autres exigent le
	-- poste de la carte.
	if position ~= "SUB" and card.position ~= position then
		return false, `cette carte joue {card.position}`
	end

	Save.update(player, function(profile)
		-- Une carte deja alignee ailleurs est retiree de son ancien poste,
		-- sinon elle compterait deux fois dans les notes d'equipe.
		for slot, id in profile.lineup do
			if id == cardId then
				profile.lineup[slot] = nil
			end
		end
		profile.lineup[position] = cardId
	end)

	return true, nil
end

--[[
	Remplit les postes vides avec les meilleures cartes disponibles.
	Appele apres chaque acquisition.
]]
function Squad.autoFill(player: Player)
	local data = Save.get(player)
	if data == nil then
		return
	end

	local used: { [string]: boolean } = {}
	for _, cardId in data.lineup do
		used[cardId] = true
	end

	local owned = Squad.list(player)

	for _, position in GameConfig.positions do
		if data.lineup[position] ~= nil then
			continue
		end

		for _, card in owned do
			if used[card.id] then
				continue
			end
			if position ~= "SUB" and card.position ~= position then
				continue
			end

			used[card.id] = true
			Save.update(player, function(profile)
				profile.lineup[position] = card.id
			end)
			break
		end
	end
end

--[[
	Distribue l'effectif de depart : une carte par poste, en bronze et
	argent. Sans lui, le premier match se jouerait avec cinq postes vides.
]]
function Squad.grantStarterSquad(player: Player, rng: Random)
	local data = Save.get(player)
	if data == nil or next(data.cards) ~= nil then
		return
	end

	for _, position in GameConfig.positions do
		local card = Cards.generate(rng)
		-- On force le poste : un effectif de depart doit couvrir la
		-- composition, pas offrir quatre attaquants.
		card.position = position :: any
		card.id = `{card.name}#{card.rating}#{position}`

		Save.update(player, function(profile)
			profile.cards[card.id] = card
			profile.lineup[position] = card.id
		end)
	end
end

return Squad
