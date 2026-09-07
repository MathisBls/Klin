--!strict
--[[
	Point d'entree client : HUD, boutique, roue, feedback de clic.

	Le client n'est qu'un affichage et une source d'intentions. Il ne
	calcule aucune valeur qui compte : les chiffres viennent tous de
	StateChanged.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WheelUI = require(script.Parent.ui.WheelUI)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local clickRemote = Remotes.get("Click") :: RemoteEvent
local buyRemote = Remotes.get("BuyUpgrade") :: RemoteFunction
local spinRemote = Remotes.get("Spin") :: RemoteFunction
local promptRemote = Remotes.get("PromptPurchase") :: RemoteEvent
local stateRemote = Remotes.get("StateChanged") :: RemoteEvent
local feedbackRemote = Remotes.get("ClickFeedback") :: RemoteEvent
local spinPlayedRemote = Remotes.get("SpinPlayed") :: RemoteEvent

local ACCENT = Color3.fromRGB(255, 122, 26)
local PANEL = Color3.fromRGB(22, 20, 24)
local TEXT = Color3.fromRGB(240, 236, 230)

local state: Remotes.PlayerState? = nil

-- --------------------------------------------------------------------------
-- Construction de l'interface
-- --------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "ForgeHUD"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local function corner(parent: Instance, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function makeButton(name: string, text: string, position: UDim2, anchor: Vector2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(150, 44)
	button.Position = position
	button.AnchorPoint = anchor
	button.BackgroundColor3 = PANEL
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = TEXT
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = screen
	corner(button, 8)
	return button
end

-- Compteur principal. En haut, jamais au centre : le centre appartient a
-- l'enclume.
local counter = Instance.new("TextLabel")
counter.Name = "Counter"
counter.Size = UDim2.fromOffset(320, 64)
counter.Position = UDim2.new(0.5, 0, 0, 16)
counter.AnchorPoint = Vector2.new(0.5, 0)
counter.BackgroundColor3 = PANEL
counter.BackgroundTransparency = 0.15
counter.BorderSizePixel = 0
counter.Font = Enum.Font.GothamBold
counter.TextSize = 30
counter.TextColor3 = ACCENT
counter.Text = "0"
counter.Parent = screen
corner(counter, 10)

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.fromOffset(320, 20)
subtitle.Position = UDim2.new(0.5, 0, 0, 82)
subtitle.AnchorPoint = Vector2.new(0.5, 0)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 14
subtitle.TextColor3 = TEXT
subtitle.TextTransparency = 0.3
subtitle.Text = "Eclats"
subtitle.Parent = screen

local shopButton = makeButton("ShopButton", "Atelier", UDim2.new(0, 16, 1, -16), Vector2.new(0, 1))
local wheelButton = makeButton("WheelButton", "Roue", UDim2.new(1, -16, 1, -16), Vector2.new(1, 1))

-- Raccourci d'achat, au-dessus du bouton Atelier. Visible sans etre
-- impose : la spec ne veut pas d'un jeu qui pousse a payer.
local pouchButton =
	makeButton("PouchButton", "Bourse d'eclats", UDim2.new(0, 16, 1, -70), Vector2.new(0, 1))
pouchButton.Size = UDim2.fromOffset(150, 36)
pouchButton.TextSize = 13

-- --------------------------------------------------------------------------
-- Panneau boutique
-- --------------------------------------------------------------------------

local shopPanel = Instance.new("Frame")
shopPanel.Name = "ShopPanel"
shopPanel.Size = UDim2.fromOffset(340, 300)
shopPanel.Position = UDim2.new(0, 16, 1, -76)
shopPanel.AnchorPoint = Vector2.new(0, 1)
shopPanel.BackgroundColor3 = PANEL
shopPanel.BackgroundTransparency = 0.05
shopPanel.BorderSizePixel = 0
shopPanel.Visible = false
shopPanel.Parent = screen
corner(shopPanel, 10)

local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 8)
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = shopPanel

local shopPadding = Instance.new("UIPadding")
shopPadding.PaddingTop = UDim.new(0, 10)
shopPadding.PaddingLeft = UDim.new(0, 10)
shopPadding.PaddingRight = UDim.new(0, 10)
shopPadding.Parent = shopPanel

local upgradeRows: { [string]: { button: TextButton, label: TextLabel } } = {}

local function addUpgradeRow(upgrade: GameConfig.Upgrade, order: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = shopPanel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -110, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextColor3 = TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = upgrade.displayName
	label.Parent = row

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(100, 40)
	button.Position = UDim2.fromScale(1, 0.5)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.BackgroundColor3 = ACCENT
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = Color3.new(0, 0, 0)
	button.Text = "..."
	button.Parent = row
	corner(button, 6)

	button.Activated:Connect(function()
		local result = buyRemote:InvokeServer(upgrade.key)
		if not result.success and result.message then
			button.Text = result.message
			task.delay(1.2, function()
				-- La prochaine mise a jour d'etat reecrira le vrai prix.
				button.Text = "..."
			end)
		end
	end)

	upgradeRows[upgrade.key] = { button = button, label = label }
end

for index, upgrade in GameConfig.upgrades do
	addUpgradeRow(upgrade, index)
end

local wheel = WheelUI.new(screen)

-- --------------------------------------------------------------------------
-- Feedback de clic
-- --------------------------------------------------------------------------

--[[
	Chiffre flottant au-dessus de l'enclume. C'est le hook des premieres
	secondes : le joueur doit voir immediatement que son clic a produit
	quelque chose.
]]
local function showFloatingGain(amount: number)
	local anvil = Workspace:FindFirstChild("Forge", true)
	if anvil == nil or not anvil:IsA("BasePart") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 40)
	billboard.StudsOffset = Vector3.new(math.random(-15, 15) / 10, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = anvil
	billboard.Parent = anvil

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 26
	label.TextColor3 = ACCENT
	label.TextStrokeTransparency = 0.4
	label.Text = `+{Format.number(amount)}`
	label.Parent = billboard

	local tween = TweenService:Create(
		billboard,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = billboard.StudsOffset + Vector3.new(0, 3, 0) }
	)
	tween:Play()

	TweenService
		:Create(label, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 })
		:Play()

	task.delay(0.85, function()
		billboard:Destroy()
	end)
end

-- --------------------------------------------------------------------------
-- Mise a jour de l'affichage
-- --------------------------------------------------------------------------

local function refresh()
	local current = state
	if current == nil then
		return
	end

	counter.Text = Format.number(current.shards, GameConfig.currency.abbreviateAbove)

	local parts = { `+{Format.number(current.clickGain)} par coup` }
	if current.perSecond > 0 then
		table.insert(parts, `{Format.number(current.perSecond)}/s`)
	end
	if current.multiplier > 1 then
		table.insert(parts, `x{current.multiplier}`)
	end
	subtitle.Text = table.concat(parts, "   ")

	for _, upgrade in GameConfig.upgrades do
		local row = upgradeRows[upgrade.key]
		if row then
			local level = current.upgrades[upgrade.key] or 0
			row.label.Text =
				`{upgrade.displayName}  ({level}/{upgrade.maxLevel})\n{upgrade.description}`

			if level >= upgrade.maxLevel then
				row.button.Text = "Max"
				row.button.BackgroundColor3 = Color3.fromRGB(60, 56, 64)
			else
				local price = math.floor(upgrade.basePrice * upgrade.priceGrowth ^ level)
				row.button.Text = Format.number(price, GameConfig.currency.abbreviateAbove)
				row.button.BackgroundColor3 = if current.shards >= price
					then ACCENT
					else Color3.fromRGB(80, 60, 44)
			end
		end
	end

	local remaining = current.spinAvailableAt - os.time()
	wheel:setCooldown(remaining, `Prochain tour dans {Format.duration(remaining)}`)

	-- Pastille sur le bouton quand un tour est disponible : le joueur ne
	-- doit pas avoir a ouvrir le panneau pour savoir qu'il peut jouer.
	wheelButton.Text = if remaining <= 0 then "Roue  ●" else "Roue"
	wheelButton.TextColor3 = if remaining <= 0 then ACCENT else TEXT
end

stateRemote.OnClientEvent:Connect(function(newState: Remotes.PlayerState)
	state = newState
	refresh()
end)

feedbackRemote.OnClientEvent:Connect(showFloatingGain)

-- --------------------------------------------------------------------------
-- Entrees
-- --------------------------------------------------------------------------

local function connectAnvil()
	local anvil = Workspace:WaitForChild("Forge", 20)
	if anvil == nil then
		warn("[Klin] enclume introuvable dans Workspace")
		return
	end

	local detector = anvil:FindFirstChildWhichIsA("ClickDetector", true)
	if detector == nil then
		warn("[Klin] ClickDetector absent de l'enclume")
		return
	end

	detector.MouseClick:Connect(function()
		clickRemote:FireServer()
	end)
end

task.spawn(connectAnvil)

shopButton.Activated:Connect(function()
	shopPanel.Visible = not shopPanel.Visible
	wheel:setOpen(false)
end)

wheelButton.Activated:Connect(function()
	wheel:setOpen(not wheel:isOpen())
	shopPanel.Visible = false
end)

wheel.closeButton.Activated:Connect(function()
	wheel:setOpen(false)
end)

wheel.spinButton.Activated:Connect(function()
	-- On ne se sert du retour que pour les refus. Un tour reussi arrive par
	-- SpinPlayed, comme un tour achete en Robux : un seul chemin d'animation
	-- pour les deux origines.
	local result = spinRemote:InvokeServer()
	if not result.success and result.message then
		wheel:setStatus(result.message)
	end
end)

wheel.buyButton.Activated:Connect(function()
	promptRemote:FireServer("EXTRA_SPIN")
end)

spinPlayedRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.prizeKey) ~= "string" then
		return
	end

	-- Un tour achete peut arriver alors que le panneau est ferme : on
	-- l'ouvre, sinon le joueur paie et ne voit rien.
	wheel:setOpen(true)
	wheel:setStatus("")

	wheel:playSpin(payload.prizeKey, function(segment)
		if segment then
			wheel:setStatus(`Tu as obtenu : {segment.displayName}`)
		end
	end)
end)

pouchButton.Activated:Connect(function()
	promptRemote:FireServer("SHARDS_POUCH")
end)

-- Rafraichit le compte a rebours de la roue sans solliciter le serveur.
task.spawn(function()
	while true do
		task.wait(1)
		if state then
			refresh()
		end
	end
end)

print(`[Klin] {GameConfig.slug} - client pret`)
