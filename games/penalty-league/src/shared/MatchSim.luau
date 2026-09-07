--!strict
--[[
	Moteur de match. Deterministe a partir de (domicile, exterieur, graine).

	DEUX PROPRIETES QUI GOUVERNENT TOUT LE FICHIER

	1. PUR ET DETERMINISTE. Meme graine, memes notes, memes reponses de
	   penalty -> meme feuille de match, evenement par evenement. C'est ce
	   qui permet a `make test` de verifier le moteur alors qu'il ne peut
	   pas demarrer le jeu. C'est aussi ce qui empeche un joueur de rejouer
	   un match perdu : la graine derive de (joueur, adversaire, journee).

	2. LE PENALTY EST UNE INTERRUPTION. Le simulateur ne decide pas du sort
	   d'un penalty : il appelle `onPenalty` et attend la reponse. En jeu,
	   ce callback fait tirer le joueur. En test, il renvoie une valeur
	   fixe, ce qui garde le tout deterministe.

	Consequence : le score final ne peut pas etre precalcule. C'est voulu -
	sans ca, le tir du joueur ne changerait rien et le critere 4 de la spec
	tomberait.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Ratings = require(ReplicatedStorage.Shared.Ratings)

export type Side = "home" | "away"

export type EventKind =
	"kickoff"
	| "chance"
	| "goal"
	| "save"
	| "penaltyAwarded"
	| "penaltyScored"
	| "penaltyMissed"
	| "fulltime"

export type MatchEvent = {
	minute: number,
	kind: EventKind,
	side: Side,
	scoreHome: number,
	scoreAway: number,
	text: string,
}

export type MatchResult = {
	scoreHome: number,
	scoreAway: number,
	events: { MatchEvent },
	-- Penalties tires par le joueur, et combien ont ete marques.
	penaltiesTaken: number,
	penaltiesScored: number,
}

--[[
	Appele quand le joueur obtient un penalty. Doit renvoyer true si le
	penalty est marque. Peut yield : en jeu, il attend le tir du joueur.
]]
export type PenaltyResolver = (minute: number) -> boolean

local MatchSim = {}

local MINUTES = 90

--[[
	Deroule le match. `onPenalty` n'est appele que pour les penalties de
	l'equipe du joueur (domicile) : ceux de l'adversaire sont resolus par
	un simple tirage, le joueur n'a pas de gardien a controler.
]]
function MatchSim.run(
	home: Ratings.TeamRatings,
	away: Ratings.TeamRatings,
	seed: number,
	onPenalty: PenaltyResolver?
): MatchResult
	local rng = Random.new(seed)
	local config = GameConfig.match

	local scoreHome, scoreAway = 0, 0
	local events: { MatchEvent } = {}
	local penaltiesTaken, penaltiesScored = 0, 0

	local function push(minute: number, kind: EventKind, side: Side, text: string)
		table.insert(events, {
			minute = minute,
			kind = kind,
			side = side,
			scoreHome = scoreHome,
			scoreAway = scoreAway,
			text = text,
		})
	end

	push(0, "kickoff", "home", "Coup d'envoi")

	for index = 1, config.eventCount do
		-- Minutes reparties regulierement, avec un peu de jitter pour que
		-- deux matchs ne se ressemblent pas au chronometre pres.
		local base = math.floor(MINUTES * index / (config.eventCount + 1))
		local minute = math.clamp(base + rng:NextInteger(-2, 2), 1, MINUTES)

		-- Qui a le ballon : tirage pondere par les milieux.
		local homeMid = home.midfield ^ config.possessionExponent
		local awayMid = away.midfield ^ config.possessionExponent
		local side: Side = if rng:NextNumber() * (homeMid + awayMid) <= homeMid
			then "home"
			else "away"

		local attack = if side == "home" then home.attack else away.attack
		local defence = if side == "home" then away.defence else home.defence

		-- Rapport A/D, pas A/(A+D) : voir le commentaire de GameConfig.
		-- Plafonne pour qu'une equipe ecrasante ne marque pas a chaque
		-- temps fort.
		local chance =
			math.min(0.95, config.chanceFactor * (attack / defence) ^ config.attackExponent)
		if rng:NextNumber() > chance then
			continue
		end

		-- Le penalty prime sur l'occasion normale : c'est le moment fort.
		if rng:NextNumber() < config.penaltyChance then
			push(minute, "penaltyAwarded", side, "Penalty !")

			local scored: boolean
			if side == "home" and onPenalty then
				penaltiesTaken += 1
				scored = onPenalty(minute)
				if scored then
					penaltiesScored += 1
				end
			else
				-- Penalty adverse, ou pas de tireur branche : tirage simple.
				scored = rng:NextNumber() < 0.75
			end

			if scored then
				if side == "home" then
					scoreHome += 1
				else
					scoreAway += 1
				end
				push(minute, "penaltyScored", side, "But sur penalty")
			else
				push(minute, "penaltyMissed", side, "Penalty manque")
			end

			continue
		end

		push(minute, "chance", side, "Occasion")

		if rng:NextNumber() < config.goalChance then
			if side == "home" then
				scoreHome += 1
			else
				scoreAway += 1
			end
			push(minute, "goal", side, "But !")
		else
			push(minute, "save", side, "Arret du gardien")
		end
	end

	push(MINUTES, "fulltime", "home", "Coup de sifflet final")

	return {
		scoreHome = scoreHome,
		scoreAway = scoreAway,
		events = events,
		penaltiesTaken = penaltiesTaken,
		penaltiesScored = penaltiesScored,
	}
end

--[[
	Graine d'un match. Deriver de (joueur, adversaire, journee) garantit
	qu'un match donne se rejoue a l'identique : un joueur qui coupe sa
	connexion sur un mauvais resultat le retrouvera tel quel.
]]
function MatchSim.seedFor(playerId: number, opponentId: string, matchday: number): number
	local hash = 0
	for index = 1, #opponentId do
		hash = (hash * 31 + string.byte(opponentId, index)) % 2147483647
	end

	return (playerId * 7919 + hash * 104729 + matchday * 15485863) % 2147483647
end

--[[ Points marques par le domicile, selon le reglement de la ligue. ]]
function MatchSim.pointsFor(scoreHome: number, scoreAway: number): number
	if scoreHome > scoreAway then
		return GameConfig.league.pointsWin
	elseif scoreHome == scoreAway then
		return GameConfig.league.pointsDraw
	end
	return 0
end

return MatchSim
