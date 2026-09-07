--!strict
--[[
	Deroulement d'un match : simulation, penalties joues, recompenses.

	Le simulateur appelle `onPenalty` et attend une reponse. Ici, ce
	callback envoie une demande au client et bloque jusqu'a son tir - ou
	jusqu'au delai, apres quoi le serveur tranche seul. Sans ce delai, un
	joueur qui ferme son onglet laisserait un match ouvert pour toujours.

	Un seul match a la fois par joueur : `active` empeche qu'un second
	appel a PlayMatch lance un match parallele et double les recompenses.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local MatchSim = require(ReplicatedStorage.Shared.MatchSim)
local Penalty = require(ReplicatedStorage.Shared.Penalty)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local systems = ServerScriptService.Server.systems
local Currency = require(systems.Currency)
local League = require(systems.League)
local Save = require(systems.Save)
local Squad = require(systems.Squad)

local Match = {}

type PendingPenalty = {
	keeperRating: number,
	answer: Penalty.Outcome?,
	answered: boolean,
}

local active: { [Player]: boolean } = {}
local pending: { [Player]: PendingPenalty? } = {}

local function remote(name: string): any
	return Remotes.get(name)
end

--[[
	Enregistre le tir d'un joueur. Renvoie l'issue, ou nil si aucun penalty
	n'est en attente ou si la visee est invalide.
]]
function Match.submitPenalty(player: Player, aim: any): Penalty.Outcome?
	local slot = pending[player]
	if slot == nil or slot.answered then
		return nil
	end

	if not Penalty.isValidAim(aim) then
		return nil
	end

	local outcome = Penalty.resolve(aim, slot.keeperRating, Random.new())
	slot.answer = outcome
	slot.answered = true

	return outcome
end

--[[
	Demande un tir au joueur et attend sa reponse.

	Au-dela du delai, le serveur resout lui-meme avec une frappe centrale :
	un joueur absent ne doit ni bloquer le match ni etre recompense de son
	absence.
]]
local function requestPenalty(player: Player, minute: number, keeperRating: number): boolean
	local slot: PendingPenalty = { keeperRating = keeperRating, answer = nil, answered = false }
	pending[player] = slot

	local deadline = os.clock() + GameConfig.penalty.aimSeconds + 2
	remote("PenaltyRequested"):FireClient(player, {
		minute = minute,
		keeperRating = keeperRating,
		deadline = GameConfig.penalty.aimSeconds,
	})

	while not slot.answered and os.clock() < deadline do
		if player.Parent ~= Players then
			pending[player] = nil
			return false
		end
		task.wait(0.1)
	end

	if not slot.answered then
		-- Frappe molle au centre : le pire choix, mais pas une perte
		-- automatique. Le joueur absent garde une chance.
		slot.answer = Penalty.resolve({ x = 0.5, y = 0.3, power = 0.4 }, keeperRating, Random.new())
	end

	pending[player] = nil

	local outcome = slot.answer
	local scored = outcome ~= nil and outcome.result == "goal"

	Save.update(player, function(profile)
		profile.penaltiesTaken += 1
		if scored then
			profile.penaltiesScored += 1
		end
	end)

	if outcome then
		remote("PenaltyResolved"):FireClient(player, outcome)
	end

	return scored
end

--[[
	Joue la journee suivante. Renvoie (succes, message d'erreur).

	Le compteur de journee est incremente AVANT la simulation : si le
	serveur tombe en plein match, le joueur perd ce match mais ne peut pas
	le rejouer indefiniment pour farmer les recompenses.
]]
function Match.play(player: Player): (boolean, string?)
	if active[player] then
		return false, "un match est deja en cours"
	end

	local data = Save.get(player)
	if data == nil then
		return false, "sauvegarde pas encore chargee"
	end

	if data.matchday >= GameConfig.league.matchdaysPerSeason then
		return false, "saison terminee"
	end

	active[player] = true

	local matchday = data.matchday + 1
	Save.update(player, function(profile)
		profile.matchday = matchday
	end)

	local opponent = League.opponentFor(player, data.division, matchday)
	local mine = Squad.ratings(player)
	local keeperRating = math.floor(opponent.ratings.defence)

	remote("MatchStarted"):FireClient(player, {
		opponentName = opponent.name,
		opponentRatings = opponent.ratings,
		matchday = matchday,
	})

	local seed = MatchSim.seedFor(player.UserId, opponent.id, matchday)

	local ok, result = pcall(function()
		return MatchSim.run(mine, opponent.ratings, seed, function(minute)
			return requestPenalty(player, minute, keeperRating)
		end)
	end)

	active[player] = nil
	pending[player] = nil

	if not ok then
		warn(`[Match] simulation en echec pour {player.Name} : {result}`)
		return false, "le match n'a pas pu se jouer"
	end

	local match = result :: MatchSim.MatchResult

	-- Les evenements partent apres coup, cadences par le client : le
	-- serveur n'a pas a dormir entre deux buts.
	for _, event in match.events do
		remote("MatchEvent"):FireClient(player, event)
	end

	-- Recompenses
	local reward = GameConfig.rewards.loss
	if match.scoreHome > match.scoreAway then
		reward = GameConfig.rewards.win
	elseif match.scoreHome == match.scoreAway then
		reward = GameConfig.rewards.draw
	end
	reward += match.penaltiesScored * GameConfig.rewards.penaltyScored

	local points = MatchSim.pointsFor(match.scoreHome, match.scoreAway)

	Save.update(player, function(profile)
		profile.seasonPoints += points
		profile.seasonGoalsFor += match.scoreHome
		profile.seasonGoalsAgainst += match.scoreAway

		if match.scoreHome > match.scoreAway then
			profile.seasonWon += 1
		elseif match.scoreHome == match.scoreAway then
			profile.seasonDrawn += 1
		else
			profile.seasonLost += 1
		end
	end)

	Currency.add(player, reward)

	local seasonOver = matchday >= GameConfig.league.matchdaysPerSeason
	local promoted = false

	if seasonOver then
		local didPromote, _, _ = League.endSeason(player)
		promoted = didPromote
		if promoted then
			Currency.add(player, GameConfig.rewards.promotion)
		end
	end

	remote("MatchEnded"):FireClient(player, {
		scoreHome = match.scoreHome,
		scoreAway = match.scoreAway,
		credits = reward,
		promoted = promoted,
		seasonOver = seasonOver,
	})

	return true, nil
end

function Match.init()
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
		pending[player] = nil
	end)
end

return Match
