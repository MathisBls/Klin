--!strict
--[[
	Remotes centralises. Un seul endroit qui cree les instances, un seul
	endroit ou lire leurs noms.

	Chaque handler serveur valide ses arguments : un RemoteEvent est une
	entree publique, un joueur peut y envoyer n'importe quoi.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cards = require(ReplicatedStorage.Shared.Cards)
local MatchSim = require(ReplicatedStorage.Shared.MatchSim)
local Penalty = require(ReplicatedStorage.Shared.Penalty)
local Ratings = require(ReplicatedStorage.Shared.Ratings)

export type StandingRow = {
	clubId: string,
	clubName: string,
	played: number,
	won: number,
	drawn: number,
	lost: number,
	goalsFor: number,
	goalsAgainst: number,
	points: number,
	isPlayer: boolean,
}

-- Etat repliqué du joueur. Toujours envoye par valeur, jamais par delta :
-- un paquet perdu ne doit pas desynchroniser l'affichage.
export type PlayerState = {
	clubName: string,
	credits: number,
	division: number,
	matchday: number,
	cards: { Cards.Card },
	lineup: { [string]: Cards.Card? },
	ratings: Ratings.TeamRatings,
	seasonPoints: number,
	hasSeasonPass: boolean,
}

export type MatchStart = {
	opponentName: string,
	opponentRatings: Ratings.TeamRatings,
	matchday: number,
}

export type MatchEnd = {
	scoreHome: number,
	scoreAway: number,
	credits: number,
	promoted: boolean,
	seasonOver: boolean,
}

export type PenaltyPrompt = {
	minute: number,
	keeperRating: number,
	deadline: number,
}

export type PenaltyOutcome = Penalty.Outcome & { scoreHome: number, scoreAway: number }

export type PackResult = {
	success: boolean,
	cards: { Cards.Card }?,
	duplicateRefund: number?,
	message: string?,
}

local FOLDER_NAME = "Remotes"

local definitions = {
	-- Client -> serveur, aucun argument : lance la journee suivante.
	PlayMatch = "RemoteFunction",
	-- Client -> serveur, argument : Penalty.Aim. Reponse : acceptee ou non.
	TakePenalty = "RemoteFunction",
	-- Client -> serveur, argument : cle de poste + id de carte.
	SetLineup = "RemoteFunction",
	-- Client -> serveur, aucun argument : achete une pochette en credits.
	OpenPack = "RemoteFunction",
	-- Client -> serveur, argument : cle de produit.
	PromptPurchase = "RemoteEvent",
	-- Client -> serveur, aucun argument. Reponse : { StandingRow }.
	GetStandings = "RemoteFunction",

	-- Serveur -> client, argument : PlayerState.
	StateChanged = "RemoteEvent",
	-- Serveur -> client, argument : MatchStart.
	MatchStarted = "RemoteEvent",
	-- Serveur -> client, argument : MatchSim.MatchEvent.
	MatchEvent = "RemoteEvent",
	-- Serveur -> client, argument : MatchEnd.
	MatchEnded = "RemoteEvent",
	-- Serveur -> client, argument : PenaltyPrompt. Le client doit repondre
	-- par TakePenalty avant `deadline`, sinon le serveur tranche seul.
	PenaltyRequested = "RemoteEvent",
	-- Serveur -> client, argument : PenaltyOutcome.
	PenaltyResolved = "RemoteEvent",
	-- Serveur -> client, argument : PackResult. Toute ouverture de pochette
	-- y passe, qu'elle vienne des credits ou d'un achat en Robux : un seul
	-- chemin d'animation, sinon un joueur qui paie ne verrait rien.
	PackOpened = "RemoteEvent",
}

local Remotes = {}

local function container(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end

		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME

		for name, className in definitions do
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end

		folder.Parent = ReplicatedStorage
		return folder
	end

	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

--[[
	Renvoie un remote par son nom. Le nom est verifie contre `definitions`
	pour qu'une faute de frappe echoue ici, avec un message clair, plutot
	qu'en produisant un WaitForChild qui ne se resout jamais.
]]
function Remotes.get(name: string): Instance
	if definitions[name] == nil then
		error(`remote inconnu : {name}`, 2)
	end

	local folder = container()
	local remote = folder:FindFirstChild(name)
	if remote == nil then
		remote = folder:WaitForChild(name, 10)
	end
	if remote == nil then
		error(`remote {name} introuvable apres 10 s`, 2)
	end

	return remote
end

function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init est reserve au serveur")
	container()
end

--[[ Expose la liste attendue, pour que les tests la verifient. ]]
function Remotes.names(): { string }
	local names = {}
	for name in definitions do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Reexport pour que le client n'ait pas a requerir MatchSim juste pour un type.
export type MatchEvent = MatchSim.MatchEvent

return Remotes
