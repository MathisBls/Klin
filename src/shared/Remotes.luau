--!strict
--[[
	Remotes centralises. Un seul endroit qui cree les instances, un seul
	endroit ou lire leurs noms.

	Le serveur cree les instances au demarrage ; le client les attend.
	Chaque handler serveur valide ses arguments : un RemoteEvent est une
	entree publique, un joueur peut y envoyer n'importe quoi.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Etat repliqué du joueur, envoye par le serveur apres chaque changement.
-- Toujours par valeur, jamais par delta : un paquet perdu ne doit pas
-- desynchroniser l'affichage.
export type PlayerState = {
	shards: number,
	upgrades: { [string]: number },
	clickGain: number,
	perSecond: number,
	multiplier: number,
	spinAvailableAt: number,
	ownedProducts: number,
}

export type SpinResult = {
	success: boolean,
	prizeKey: string?,
	displayName: string?,
	message: string?,
}

local FOLDER_NAME = "Remotes"

local definitions = {
	-- Client -> serveur. Aucun argument : le serveur decide du gain.
	Click = "RemoteEvent",
	-- Client -> serveur, argument : cle d'amelioration (string).
	BuyUpgrade = "RemoteFunction",
	-- Client -> serveur, aucun argument.
	Spin = "RemoteFunction",
	-- Client -> serveur, argument : cle de produit (string).
	PromptPurchase = "RemoteEvent",
	-- Serveur -> client, argument : PlayerState.
	StateChanged = "RemoteEvent",
	-- Serveur -> client, argument : { amount: number } pour le feedback visuel.
	ClickFeedback = "RemoteEvent",
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

--[[
	Cree les instances. A appeler une fois au demarrage serveur, avant que
	le premier client ne tente de les attendre.
]]
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init est reserve au serveur")
	container()
end

return Remotes
