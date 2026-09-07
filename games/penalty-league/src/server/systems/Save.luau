--!strict
--[[
	Persistance via ProfileStore. Point d'ecriture unique du profil.

	Regles tenues ici :
	  - session lock : un profil ouvert par un seul serveur a la fois
	  - release au depart, sinon le joueur reste bloque plusieurs minutes
	  - echec de chargement = kick, plutot que de le laisser jouer sur un
	    profil vide qu'il perdra au prochain save
	  - migration par valeurs par defaut : une cle ajoutee au template est
	    absente des anciens profils, donc toujours lire avec un repli
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

export type ProfileData = {
	clubName: string,
	credits: number,
	-- Cartes possedees, indexees par id pour detecter un doublon en O(1).
	cards: { [string]: any },
	-- Poste -> id de carte. Une composition ne stocke que des references :
	-- dupliquer la carte entiere ferait diverger les deux copies.
	lineup: { [string]: string },
	division: number,
	matchday: number,
	seasonPoints: number,
	seasonGoalsFor: number,
	seasonGoalsAgainst: number,
	seasonWon: number,
	seasonDrawn: number,
	seasonLost: number,
	-- PurchaseId deja traites. Rend ProcessReceipt idempotent : Roblox
	-- rappelle le callback tant qu'il n'a pas recu PurchaseGranted.
	receipts: { [string]: boolean },
	penaltiesTaken: number,
	penaltiesScored: number,
	firstJoinAt: number,
}

local TEMPLATE: ProfileData = {
	clubName = "",
	credits = 0,
	cards = {},
	lineup = {},
	division = 5,
	matchday = 0,
	seasonPoints = 0,
	seasonGoalsFor = 0,
	seasonGoalsAgainst = 0,
	seasonWon = 0,
	seasonDrawn = 0,
	seasonLost = 0,
	receipts = {},
	penaltiesTaken = 0,
	penaltiesScored = 0,
	firstJoinAt = 0,
}

-- Changer ce nom repart de zero pour tous les joueurs.
local STORE_NAME = "PenaltyLeague_v1"

local Save = {}

local store = ProfileStore.New(STORE_NAME, TEMPLATE)
local profiles: { [Player]: any } = {}

--[[
	Comble les cles absentes d'un profil ancien avec celles du template.
	Sans ca, une cle ajoutee apres coup se lit en nil et fait planter le
	premier systeme qui l'utilise.
]]
local function reconcile(data: ProfileData)
	for key, value in TEMPLATE :: any do
		if (data :: any)[key] == nil then
			-- Copie des tables, sinon tous les profils partageraient la
			-- meme instance et s'ecraseraient mutuellement.
			(data :: any)[key] = if typeof(value) == "table" then table.clone(value) else value
		end
	end
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`player_{player.UserId}`, {
		Cancel = function()
			-- Le joueur est parti pendant le chargement : inutile de
			-- verrouiller un profil que personne n'utilisera.
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		player:Kick("Chargement de la sauvegarde impossible. Reessaie dans un instant.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	reconcile(profile.Data)

	if profile.Data.firstJoinAt == 0 then
		profile.Data.firstJoinAt = os.time()
		profile.Data.credits = GameConfig.currency.startingAmount
		profile.Data.division = GameConfig.league.startingDivision
	end

	-- Le club porte le pseudo du joueur : il se cree tout seul, sans
	-- formulaire, ce que le hook des dix secondes exige.
	if profile.Data.clubName == "" then
		profile.Data.clubName = `FC {player.Name}`
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Session de sauvegarde fermee. Reconnecte-toi.")
	end)

	-- Le joueur a pu partir pendant le StartSessionAsync.
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profiles[player] = profile
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession()
		profiles[player] = nil
	end
end

--[[ Profil charge, ou nil si le chargement n'est pas termine. ]]
function Save.get(player: Player): ProfileData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

--[[
	Attend le chargement. Renvoie nil si le joueur part avant, ou si le
	chargement echoue. Tout appelant doit gerer ce nil.
]]
function Save.await(player: Player, timeout: number?): ProfileData?
	local deadline = os.clock() + (timeout or 20)

	while os.clock() < deadline do
		if player.Parent ~= Players then
			return nil
		end
		local profile = profiles[player]
		if profile then
			return profile.Data
		end
		task.wait(0.1)
	end

	return nil
end

--[[
	Seul point de mutation du profil. Passer par ici plutot que d'ecrire
	directement garantit qu'un profil non charge ne provoque pas d'erreur
	et que toute ecriture est traçable a un seul endroit.

	Renvoie false si le profil n'est pas disponible.
]]
function Save.update(player: Player, mutate: (ProfileData) -> ()): boolean
	local profile = profiles[player]
	if profile == nil then
		return false
	end

	mutate(profile.Data)
	return true
end

function Save.init()
	assert(RunService:IsServer(), "Save est reserve au serveur")

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Filet de securite : sur un arret serveur, ProfileStore ferme les
	-- sessions, mais on le declenche explicitement pour ne pas dependre
	-- de l'ordre de destruction des instances.
	game:BindToClose(function()
		for player in profiles do
			onPlayerRemoving(player)
		end
	end)
end

return Save
