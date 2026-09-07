--!strict
--[[
	Point d'entree client : HUD, effectif, classement, feuille de match.

	Le client n'est qu'un affichage et une source d'intentions. Il ne
	calcule aucune valeur qui compte : les chiffres viennent tous de
	StateChanged.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local PenaltyUI = require(script.Parent.ui.PenaltyUI)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local playRemote = Remotes.get("PlayMatch") :: RemoteFunction
local penaltyRemote = Remotes.get("TakePenalty") :: RemoteFunction
local lineupRemote = Remotes.get("SetLineup") :: RemoteFunction
local packRemote = Remotes.get("OpenPack") :: RemoteFunction
local promptRemote = Remotes.get("PromptPurchase") :: RemoteEvent
local standingsRemote = Remotes.get("GetStandings") :: RemoteFunction
local stateRemote = Remotes.get("StateChanged") :: RemoteEvent
local matchStartedRemote = Remotes.get("MatchStarted") :: RemoteEvent
local matchEventRemote = Remotes.get("MatchEvent") :: RemoteEvent
local matchEndedRemote = Remotes.get("MatchEnded") :: RemoteEvent
local penaltyRequestedRemote = Remotes.get("PenaltyRequested") :: RemoteEvent
local penaltyResolvedRemote = Remotes.get("PenaltyResolved") :: RemoteEvent
local packOpenedRemote = Remotes.get("PackOpened") :: RemoteEvent

local PANEL = Color3.fromRGB(18, 20, 26)
local TEXT = Color3.fromRGB(240, 244, 248)
local ACCENT = Color3.fromRGB(64, 200, 120)
local MUTED = Color3.fromRGB(120, 128, 140)

local state: Remotes.PlayerState? = nil
local matchRunning = false

local screen = Instance.new("ScreenGui")
screen.Name = "LeagueHUD"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local penalty = PenaltyUI.new(screen)

local function corner(instance: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = instance
end

local function makeButton(text: string, position: UDim2, anchor: Vector2, width: number): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(width, 42)
	button.Position = position
	button.AnchorPoint = anchor
	button.BackgroundColor3 = PANEL
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = TEXT
	button.Text = text
	button.Parent = screen
	corner(button, 8)
	return button
end

-- --------------------------------------------------------------------------
-- Bandeau du haut : club, credits, division
-- --------------------------------------------------------------------------

local header = Instance.new("Frame")
header.Size = UDim2.fromOffset(420, 62)
header.Position = UDim2.new(0.5, 0, 0, 12)
header.AnchorPoint = Vector2.new(0.5, 0)
header.BackgroundColor3 = PANEL
header.BackgroundTransparency = 0.1
header.BorderSizePixel = 0
header.Parent = screen
corner(header, 10)

local clubLabel = Instance.new("TextLabel")
clubLabel.Size = UDim2.new(1, -20, 0, 26)
clubLabel.Position = UDim2.fromOffset(10, 8)
clubLabel.BackgroundTransparency = 1
clubLabel.Font = Enum.Font.GothamBold
clubLabel.TextSize = 18
clubLabel.TextColor3 = TEXT
clubLabel.TextXAlignment = Enum.TextXAlignment.Left
clubLabel.Text = "..."
clubLabel.Parent = header

local statsLabel = Instance.new("TextLabel")
statsLabel.Size = UDim2.new(1, -20, 0, 20)
statsLabel.Position = UDim2.fromOffset(10, 34)
statsLabel.BackgroundTransparency = 1
statsLabel.Font = Enum.Font.Gotham
statsLabel.TextSize = 13
statsLabel.TextColor3 = MUTED
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.Text = ""
statsLabel.Parent = header

-- --------------------------------------------------------------------------
-- Feuille de match
-- --------------------------------------------------------------------------

local feed = Instance.new("Frame")
feed.Size = UDim2.fromOffset(360, 280)
feed.Position = UDim2.new(1, -16, 0.5, 0)
feed.AnchorPoint = Vector2.new(1, 0.5)
feed.BackgroundColor3 = PANEL
feed.BackgroundTransparency = 0.08
feed.BorderSizePixel = 0
feed.Visible = false
feed.Parent = screen
corner(feed, 10)

local feedTitle = Instance.new("TextLabel")
feedTitle.Size = UDim2.new(1, -20, 0, 34)
feedTitle.Position = UDim2.fromOffset(10, 8)
feedTitle.BackgroundTransparency = 1
feedTitle.Font = Enum.Font.GothamBold
feedTitle.TextSize = 20
feedTitle.TextColor3 = TEXT
feedTitle.Text = ""
feedTitle.Parent = feed

local feedList = Instance.new("ScrollingFrame")
feedList.Size = UDim2.new(1, -20, 1, -54)
feedList.Position = UDim2.fromOffset(10, 46)
feedList.BackgroundTransparency = 1
feedList.BorderSizePixel = 0
feedList.ScrollBarThickness = 3
feedList.CanvasSize = UDim2.new()
feedList.AutomaticCanvasSize = Enum.AutomaticSize.Y
feedList.Parent = feed

local feedLayout = Instance.new("UIListLayout")
feedLayout.Padding = UDim.new(0, 3)
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Parent = feedList

local feedOrder = 0

local function pushFeed(text: string, colour: Color3?)
	feedOrder += 1
	local line = Instance.new("TextLabel")
	line.Size = UDim2.new(1, 0, 0, 20)
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.Gotham
	line.TextSize = 13
	line.TextColor3 = colour or TEXT
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.Text = text
	line.LayoutOrder = feedOrder
	line.Parent = feedList
	feedList.CanvasPosition = Vector2.new(0, feedLayout.AbsoluteContentSize.Y)
end

-- --------------------------------------------------------------------------
-- Panneaux effectif et classement
-- --------------------------------------------------------------------------

local function makePanel(width: number, height: number): Frame
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(width, height)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 15
	panel.Parent = screen
	corner(panel, 12)
	return panel
end

local squadPanel = makePanel(520, 400)
local squadList = Instance.new("ScrollingFrame")
squadList.Size = UDim2.new(1, -24, 1, -70)
squadList.Position = UDim2.fromOffset(12, 46)
squadList.BackgroundTransparency = 1
squadList.BorderSizePixel = 0
squadList.ScrollBarThickness = 4
squadList.CanvasSize = UDim2.new()
squadList.AutomaticCanvasSize = Enum.AutomaticSize.Y
squadList.ZIndex = 15
squadList.Parent = squadPanel

local squadLayout = Instance.new("UIListLayout")
squadLayout.Padding = UDim.new(0, 5)
squadLayout.Parent = squadList

local squadTitle = Instance.new("TextLabel")
squadTitle.Size = UDim2.new(1, -24, 0, 32)
squadTitle.Position = UDim2.fromOffset(12, 10)
squadTitle.BackgroundTransparency = 1
squadTitle.Font = Enum.Font.GothamBold
squadTitle.TextSize = 19
squadTitle.TextColor3 = TEXT
squadTitle.TextXAlignment = Enum.TextXAlignment.Left
squadTitle.Text = "Effectif"
squadTitle.ZIndex = 15
squadTitle.Parent = squadPanel

local leaguePanel = makePanel(560, 420)
local leagueList = Instance.new("ScrollingFrame")
leagueList.Size = UDim2.new(1, -24, 1, -70)
leagueList.Position = UDim2.fromOffset(12, 46)
leagueList.BackgroundTransparency = 1
leagueList.BorderSizePixel = 0
leagueList.ScrollBarThickness = 4
leagueList.CanvasSize = UDim2.new()
leagueList.AutomaticCanvasSize = Enum.AutomaticSize.Y
leagueList.ZIndex = 15
leagueList.Parent = leaguePanel

local leagueLayout = Instance.new("UIListLayout")
leagueLayout.Padding = UDim.new(0, 3)
leagueLayout.Parent = leagueList

local leagueTitle = Instance.new("TextLabel")
leagueTitle.Size = UDim2.new(1, -24, 0, 32)
leagueTitle.Position = UDim2.fromOffset(12, 10)
leagueTitle.BackgroundTransparency = 1
leagueTitle.Font = Enum.Font.GothamBold
leagueTitle.TextSize = 19
leagueTitle.TextColor3 = TEXT
leagueTitle.TextXAlignment = Enum.TextXAlignment.Left
leagueTitle.Text = "Classement"
leagueTitle.ZIndex = 15
leagueTitle.Parent = leaguePanel

-- --------------------------------------------------------------------------
-- Boutons
-- --------------------------------------------------------------------------

local playButton =
	makeButton("Jouer la journee", UDim2.new(0.5, 0, 1, -16), Vector2.new(0.5, 1), 200)
playButton.BackgroundColor3 = ACCENT
playButton.TextColor3 = Color3.new(0, 0, 0)

local squadButton = makeButton("Effectif", UDim2.new(0, 16, 1, -16), Vector2.new(0, 1), 130)
local leagueButton = makeButton("Classement", UDim2.new(0, 154, 1, -16), Vector2.new(0, 1), 130)
local packButton = makeButton("Pochette  250", UDim2.new(1, -16, 1, -16), Vector2.new(1, 1), 150)
local shopButton = makeButton("Boutique Robux", UDim2.new(1, -174, 1, -16), Vector2.new(1, 1), 150)

local closeButton = makeButton("Fermer", UDim2.new(0.5, 0, 0.5, 205), Vector2.new(0.5, 0.5), 120)
closeButton.Visible = false
closeButton.ZIndex = 16

-- --------------------------------------------------------------------------
-- Rendu
-- --------------------------------------------------------------------------

local function rarityColor(key: string): Color3
	for _, rarity in GameConfig.rarities do
		if rarity.key == key then
			return rarity.color
		end
	end
	return MUTED
end

local function refreshHeader()
	local current = state
	if current == nil then
		return
	end

	clubLabel.Text = current.clubName
	statsLabel.Text = string.format(
		"D%d  ·  J%d/%d  ·  %d pts  ·  %s credits  ·  ATT %d  MIL %d  DEF %d",
		current.division,
		current.matchday,
		GameConfig.league.matchdaysPerSeason,
		current.seasonPoints,
		Format.number(current.credits, GameConfig.currency.abbreviateAbove),
		math.floor(current.ratings.attack),
		math.floor(current.ratings.midfield),
		math.floor(current.ratings.defence)
	)

	packButton.Text = `Pochette  {GameConfig.packs.price}`
	packButton.BackgroundColor3 = if current.credits >= GameConfig.packs.price
		then ACCENT
		else PANEL
	packButton.TextColor3 = if current.credits >= GameConfig.packs.price
		then Color3.new(0, 0, 0)
		else MUTED
end

local function refreshSquad()
	local current = state
	if current == nil then
		return
	end

	for _, child in squadList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Composition d'abord : c'est ce que le joueur vient regler.
	local order = 0
	for _, position in GameConfig.positions do
		order += 1
		local card = current.lineup[position]

		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundColor3 = Color3.fromRGB(28, 31, 38)
		row.BorderSizePixel = 0
		row.Font = Enum.Font.Gotham
		row.TextSize = 14
		row.TextColor3 = TEXT
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = order
		row.ZIndex = 15
		row.Text = if card
			then `  {GameConfig.positionNames[position]}   {card.name}   {card.rating}`
			else `  {GameConfig.positionNames[position]}   — vide —`
		row.Parent = squadList
		corner(row, 6)

		if card then
			local badge = Instance.new("Frame")
			badge.Size = UDim2.fromOffset(6, 40)
			badge.BackgroundColor3 = rarityColor(card.rarity)
			badge.BorderSizePixel = 0
			badge.ZIndex = 16
			badge.Parent = row
		end
	end

	local separator = Instance.new("TextLabel")
	separator.Size = UDim2.new(1, 0, 0, 28)
	separator.BackgroundTransparency = 1
	separator.Font = Enum.Font.GothamBold
	separator.TextSize = 13
	separator.TextColor3 = MUTED
	separator.TextXAlignment = Enum.TextXAlignment.Left
	separator.Text = "Cartes — clique pour aligner"
	separator.LayoutOrder = 100
	separator.ZIndex = 15
	separator.Parent = squadList

	for index, card in current.cards do
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundColor3 = Color3.fromRGB(24, 27, 33)
		row.BorderSizePixel = 0
		row.Font = Enum.Font.Gotham
		row.TextSize = 13
		row.TextColor3 = TEXT
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = 100 + index
		row.ZIndex = 15
		row.Text = `  {card.position}   {card.name}   {card.rating}`
		row.Parent = squadList
		corner(row, 5)

		local badge = Instance.new("Frame")
		badge.Size = UDim2.fromOffset(5, 34)
		badge.BackgroundColor3 = rarityColor(card.rarity)
		badge.BorderSizePixel = 0
		badge.ZIndex = 16
		badge.Parent = row

		row.Activated:Connect(function()
			local result = lineupRemote:InvokeServer(card.position, card.id)
			if not result.success and result.message then
				squadTitle.Text = `Effectif — {result.message}`
				task.delay(1.5, function()
					squadTitle.Text = "Effectif"
				end)
			end
		end)
	end
end

local function refreshLeague()
	for _, child in leagueList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local rows = standingsRemote:InvokeServer()
	if typeof(rows) ~= "table" then
		return
	end

	for index, row in rows do
		local line = Instance.new("TextLabel")
		line.Size = UDim2.new(1, 0, 0, 26)
		line.BackgroundColor3 = Color3.fromRGB(28, 31, 38)
		line.BackgroundTransparency = if row.isPlayer then 0 else 0.6
		line.BorderSizePixel = 0
		line.Font = if row.isPlayer then Enum.Font.GothamBold else Enum.Font.Gotham
		line.TextSize = 13
		line.TextColor3 = if row.isPlayer then ACCENT else TEXT
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.LayoutOrder = index
		line.ZIndex = 15
		line.Text = string.format(
			"  %2d.  %-20s  %2d j   %2d pts   %+d",
			index,
			row.clubName,
			row.played,
			row.points,
			row.goalsFor - row.goalsAgainst
		)
		line.Parent = leagueList
		corner(line, 4)
	end
end

local function closePanels()
	squadPanel.Visible = false
	leaguePanel.Visible = false
	closeButton.Visible = false
end

-- --------------------------------------------------------------------------
-- Evenements serveur
-- --------------------------------------------------------------------------

stateRemote.OnClientEvent:Connect(function(newState: Remotes.PlayerState)
	state = newState
	refreshHeader()
	if squadPanel.Visible then
		refreshSquad()
	end
end)

matchStartedRemote.OnClientEvent:Connect(function(payload)
	matchRunning = true
	closePanels()
	feed.Visible = true
	feedOrder = 0

	for _, child in feedList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local current = state
	feedTitle.Text =
		`J{payload.matchday}  ·  {if current then current.clubName else "?"} — {payload.opponentName}`
	playButton.Text = "Match en cours"
	playButton.BackgroundColor3 = MUTED
end)

matchEventRemote.OnClientEvent:Connect(function(event)
	local colour = TEXT
	if event.kind == "goal" or event.kind == "penaltyScored" then
		colour = ACCENT
	elseif event.kind == "penaltyAwarded" then
		colour = Color3.fromRGB(240, 200, 80)
	elseif event.kind == "save" or event.kind == "penaltyMissed" then
		colour = MUTED
	end

	pushFeed(
		string.format(
			"%2d'  %s   %d-%d",
			event.minute,
			event.text,
			event.scoreHome,
			event.scoreAway
		),
		colour
	)
end)

matchEndedRemote.OnClientEvent:Connect(function(payload)
	matchRunning = false
	playButton.Text = "Jouer la journee"
	playButton.BackgroundColor3 = ACCENT

	pushFeed(`Fin du match — {payload.scoreHome}-{payload.scoreAway}`, ACCENT)
	pushFeed(`+{payload.credits} credits`, TEXT)

	if payload.promoted then
		pushFeed("MONTEE EN DIVISION SUPERIEURE", ACCENT)
	elseif payload.seasonOver then
		pushFeed("Saison terminee", MUTED)
	end
end)

penaltyRequestedRemote.OnClientEvent:Connect(function(payload)
	pushFeed(`{payload.minute}'  Penalty pour toi !`, Color3.fromRGB(240, 200, 80))

	penalty:prompt(function(x, y, power)
		penaltyRemote:InvokeServer({ x = x, y = y, power = power })
	end)
end)

penaltyResolvedRemote.OnClientEvent:Connect(function(outcome)
	penalty:showOutcome(outcome)
end)

packOpenedRemote.OnClientEvent:Connect(function(result)
	if not result.success then
		return
	end

	squadPanel.Visible = true
	closeButton.Visible = true
	refreshSquad()

	for _, card in result.cards or {} do
		squadTitle.Text = `Nouvelle carte : {card.name} ({card.rating})`
	end

	if (result.duplicateRefund or 0) > 0 then
		squadTitle.Text = `{squadTitle.Text}  ·  +{result.duplicateRefund} credits de doublons`
	end
end)

-- --------------------------------------------------------------------------
-- Entrees
-- --------------------------------------------------------------------------

playButton.Activated:Connect(function()
	if matchRunning then
		return
	end
	local result = playRemote:InvokeServer()
	if not result.success and result.message then
		feed.Visible = true
		pushFeed(result.message, MUTED)
	end
end)

squadButton.Activated:Connect(function()
	leaguePanel.Visible = false
	squadPanel.Visible = not squadPanel.Visible
	closeButton.Visible = squadPanel.Visible
	if squadPanel.Visible then
		refreshSquad()
	end
end)

leagueButton.Activated:Connect(function()
	squadPanel.Visible = false
	leaguePanel.Visible = not leaguePanel.Visible
	closeButton.Visible = leaguePanel.Visible
	if leaguePanel.Visible then
		refreshLeague()
	end
end)

closeButton.Activated:Connect(closePanels)

packButton.Activated:Connect(function()
	local result = packRemote:InvokeServer()
	if not result.success and result.message then
		squadTitle.Text = `Effectif — {result.message}`
		squadPanel.Visible = true
		closeButton.Visible = true
		refreshSquad()
	end
end)

shopButton.Activated:Connect(function()
	-- Deux produits seulement : on alterne plutot que d'ouvrir un panneau
	-- de plus pour une v1.
	promptRemote:FireServer("PACK_GOLD")
end)

-- Le stade doit exister avant que le premier penalty n'arrive : sans lui,
-- l'animation du ballon n'aurait rien a bouger.
task.spawn(function()
	if Workspace:FindFirstChild("Ball", true) == nil then
		warn("[Klin] ballon introuvable dans Workspace - l'animation sera muette")
	end
end)

print(`[Klin] {GameConfig.slug} - client pret`)
