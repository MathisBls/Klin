--!strict
--[[
	Panneaux flottants du lobby.

	Deux lignes au maximum par panneau : un panneau qu'on doit lire n'est
	plus un panneau. La couleur porte autant d'information que le texte, et
	c'est elle qu'on percoit de loin.

	`AlwaysOnTop` est volontairement faux : un panneau qui traverse les
	murs detruit la lecture de l'espace. On accepte qu'il soit masque quand
	on n'est pas en vue directe - c'est justement ce qui donne le sentiment
	d'un lieu plutot que d'un menu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Layout = require(ReplicatedStorage.Shared.config.LobbyLayout)

local Signs = {}

local function buildSign(sign: Layout.Sign, parent: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = `Sign_{sign.title}`
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(sign.position)
	anchor.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Board"
	billboard.Size = UDim2.fromOffset(420, 130)
	billboard.StudsOffset = Vector3.new(0, 0, 0)
	-- Visible de loin, mais il finit par disparaitre : un panneau lisible
	-- depuis l'autre bout de la map encombre l'ecran.
	billboard.MaxDistance = 320
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = sign.color
	stroke.Thickness = 4
	stroke.Parent = frame

	-- Barre de couleur : c'est ce qu'on distingue en premier, avant tout
	-- texte, et ce qui differencie les zones d'un coup d'oeil.
	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(1, 0, 0, 8)
	accent.Position = UDim2.fromScale(0, 0)
	accent.BackgroundColor3 = sign.color
	accent.BorderSizePixel = 0
	accent.Parent = frame

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 14)
	accentCorner.Parent = accent

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 54)
	title.Position = UDim2.fromOffset(12, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = sign.color
	title.Text = sign.title
	title.Parent = frame

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -24, 0, 40)
	subtitle.Position = UDim2.fromOffset(12, 76)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(228, 232, 238)
	subtitle.Text = sign.subtitle
	subtitle.Parent = frame

	return anchor
end

--[[ Construit tous les panneaux. A appeler une fois au demarrage. ]]
function Signs.build()
	local existing = Workspace:FindFirstChild("Signs")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Signs"
	folder.Parent = Workspace

	for _, sign in Layout.signs do
		buildSign(sign, folder)
	end

	print(`[Signs] {#Layout.signs} panneau(x) poses`)
end

return Signs
