--!strict
--[[
	Roue de recompenses : vrai disque a secteurs, qui tourne et s'arrete sur
	le lot annonce par le serveur.

	DEUX PARTIS PRIS

	1. Les secteurs sont PROPORTIONNELS AU POIDS, pas de taille egale. Un lot
	   a 2 % occupe 7,2 degres. Le joueur voit donc la rarete au lieu de la
	   deviner. Une roue a six parts egales dont l'une donne 2 % du temps est
	   un mensonge visuel.

	2. Le client n'a AUCUNE part dans le tirage. Le serveur renvoie une cle,
	   on calcule l'angle qui met ce secteur sous l'aiguille, et on anime
	   jusque-la. La roue est une mise en scene d'un resultat deja acquis.

	DESSIN SANS ASSET

	Roblox ne sait pas dessiner un secteur circulaire nativement, et uploader
	une image imposerait un passage en moderation. Chaque secteur est donc
	rempli de fines lames rectangulaires partant du centre, posees tous les
	deux degres. Au bord du disque, deux degres font environ 5 pixels : une
	lame de 8 pixels de large couvre l'intervalle sans laisser de trou.
]]

local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)

local WheelUI = {}
WheelUI.__index = WheelUI

local RADIUS = 150
local BLADE_STEP = 2
local BLADE_WIDTH = 8
local FULL_TURNS = 5

local PANEL = Color3.fromRGB(22, 20, 24)
local TEXT = Color3.fromRGB(240, 236, 230)
local ACCENT = Color3.fromRGB(255, 122, 26)

-- Couleur par lot, du plus commun au plus rare. L'oeil doit pouvoir classer
-- les secteurs sans lire une seule etiquette.
local PRIZE_COLORS: { [string]: Color3 } = {
	HANDFUL = Color3.fromRGB(78, 74, 84),
	PURSE = Color3.fromRGB(96, 116, 140),
	CHEST = Color3.fromRGB(88, 140, 104),
	HEAVY_CHEST = Color3.fromRGB(140, 108, 180),
	EMBER = Color3.fromRGB(214, 96, 40),
	FORGE_HEART = Color3.fromRGB(240, 190, 60),
}

local FALLBACK_COLOR = Color3.fromRGB(90, 86, 96)

export type Segment = {
	key: string,
	displayName: string,
	weight: number,
	startAngle: number,
	sweep: number,
	centerAngle: number,
	color: Color3,
}

--[[
	Decoupe le disque. Les angles sont en degres, sens horaire, zero en haut
	(midi) : c'est la ou pointe l'aiguille.
]]
local function buildSegments(): { Segment }
	local total = 0
	for _, prize in GameConfig.wheel.prizes do
		total += prize.weight
	end

	local segments: { Segment } = {}
	local cursor = 0

	for _, prize in GameConfig.wheel.prizes do
		local sweep = prize.weight / total * 360

		table.insert(
			segments,
			{
				key = prize.key,
				displayName = prize.displayName,
				weight = prize.weight,
				startAngle = cursor,
				sweep = sweep,
				centerAngle = cursor + sweep / 2,
				color = PRIZE_COLORS[prize.key] or FALLBACK_COLOR,
				percent = prize.weight / total * 100,
			} :: any
		)

		cursor += sweep
	end

	return segments
end

local function corner(instance: Instance, radius: UDim)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = radius
	uiCorner.Parent = instance
end

--[[
	Une lame : rectangle ancre par son bord bas au centre du disque, tourne
	de `angle`. A rotation nulle il pointe vers le haut.
]]
local function makeBlade(parent: Instance, angle: number, color: Color3)
	local blade = Instance.new("Frame")
	blade.Size = UDim2.fromOffset(BLADE_WIDTH, RADIUS)
	blade.Position = UDim2.fromScale(0.5, 0.5)
	blade.AnchorPoint = Vector2.new(0.5, 1)
	blade.Rotation = angle
	blade.BackgroundColor3 = color
	blade.BorderSizePixel = 0
	blade.Parent = parent
end

function WheelUI.new(parentGui: ScreenGui)
	local self = setmetatable({}, WheelUI)

	self.segments = buildSegments()
	self.spinning = false

	-- Voile sombre : la roue est un moment, elle merite le plein ecran.
	local overlay = Instance.new("Frame")
	overlay.Name = "WheelOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = parentGui
	self.overlay = overlay

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(560, 420)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	panel.ZIndex = 11
	panel.Parent = overlay
	corner(panel, UDim.new(0, 14))

	-- Zone du disque, a gauche.
	local stage = Instance.new("Frame")
	stage.Size = UDim2.fromOffset(RADIUS * 2 + 40, RADIUS * 2 + 40)
	stage.Position = UDim2.fromOffset(20, 20)
	stage.BackgroundTransparency = 1
	stage.ZIndex = 11
	stage.Parent = panel

	-- Le disque tournant. Tout ce qui est dedans tourne avec lui.
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.Size = UDim2.fromOffset(RADIUS * 2, RADIUS * 2)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.BackgroundColor3 = Color3.fromRGB(14, 13, 16)
	disc.BorderSizePixel = 0
	disc.ClipsDescendants = true
	disc.ZIndex = 11
	disc.Parent = stage
	corner(disc, UDim.new(0.5, 0))
	self.disc = disc

	for _, segment in self.segments do
		local angle = segment.startAngle
		-- On depasse legerement la fin du secteur pour que deux secteurs
		-- voisins se touchent sans laisser de liseré de fond.
		while angle < segment.startAngle + segment.sweep do
			makeBlade(disc, angle, segment.color)
			angle += BLADE_STEP
		end
		makeBlade(disc, segment.startAngle + segment.sweep, segment.color)
	end

	-- Etiquettes : seulement sur les secteurs assez larges pour les porter.
	-- Sur un secteur a 2 %, un texte serait illisible ; la legende s'en
	-- charge.
	for _, segment in self.segments do
		if segment.sweep >= 30 then
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromOffset(90, 20)
			label.AnchorPoint = Vector2.new(0.5, 0.5)

			local radians = math.rad(segment.centerAngle - 90)
			local distance = RADIUS * 0.62
			label.Position =
				UDim2.new(0.5, math.cos(radians) * distance, 0.5, math.sin(radians) * distance)

			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBold
			label.TextSize = 12
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.5
			label.Text = `{math.floor(segment.weight)}%`
			label.Rotation = segment.centerAngle
			label.ZIndex = 12
			label.Parent = disc
		end
	end

	-- Moyeu, pour cacher la convergence des lames au centre.
	local hub = Instance.new("Frame")
	hub.Size = UDim2.fromOffset(56, 56)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.BackgroundColor3 = PANEL
	hub.BorderSizePixel = 0
	hub.ZIndex = 13
	hub.Parent = stage
	corner(hub, UDim.new(0.5, 0))

	-- Aiguille, a midi. Fixe : c'est le disque qui tourne.
	local pointer = Instance.new("TextLabel")
	pointer.Size = UDim2.fromOffset(40, 40)
	pointer.Position = UDim2.new(0.5, 0, 0, -6)
	pointer.AnchorPoint = Vector2.new(0.5, 0)
	pointer.BackgroundTransparency = 1
	pointer.Font = Enum.Font.GothamBold
	pointer.TextSize = 34
	pointer.TextColor3 = ACCENT
	pointer.TextStrokeTransparency = 0.3
	pointer.Text = "▼"
	pointer.ZIndex = 14
	pointer.Parent = stage

	-- Colonne de droite : legende, resultat, boutons.
	local side = Instance.new("Frame")
	side.Size = UDim2.fromOffset(200, 380)
	side.Position = UDim2.fromOffset(RADIUS * 2 + 70, 20)
	side.BackgroundTransparency = 1
	side.ZIndex = 11
	side.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextColor3 = TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Roue de la forge"
	title.ZIndex = 11
	title.Parent = side

	local legend = Instance.new("Frame")
	legend.Size = UDim2.new(1, 0, 0, 150)
	legend.Position = UDim2.fromOffset(0, 32)
	legend.BackgroundTransparency = 1
	legend.ZIndex = 11
	legend.Parent = side

	local legendLayout = Instance.new("UIListLayout")
	legendLayout.Padding = UDim.new(0, 4)
	legendLayout.SortOrder = Enum.SortOrder.LayoutOrder
	legendLayout.Parent = legend

	for index, segment in self.segments do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 20)
		row.BackgroundTransparency = 1
		row.LayoutOrder = index
		row.ZIndex = 11
		row.Parent = legend

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(12, 12)
		swatch.Position = UDim2.fromScale(0, 0.5)
		swatch.AnchorPoint = Vector2.new(0, 0.5)
		swatch.BackgroundColor3 = segment.color
		swatch.BorderSizePixel = 0
		swatch.ZIndex = 11
		swatch.Parent = row
		corner(swatch, UDim.new(0, 3))

		local text = Instance.new("TextLabel")
		text.Size = UDim2.new(1, -20, 1, 0)
		text.Position = UDim2.fromOffset(20, 0)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Gotham
		text.TextSize = 12
		text.TextColor3 = TEXT
		text.TextTransparency = 0.15
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.Text = `{segment.displayName}  ·  {math.floor(segment.weight)}%`
		text.ZIndex = 11
		text.Parent = row
	end

	local status = Instance.new("TextLabel")
	status.Size = UDim2.new(1, 0, 0, 44)
	status.Position = UDim2.fromOffset(0, 190)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.TextSize = 14
	status.TextColor3 = TEXT
	status.TextWrapped = true
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = ""
	status.ZIndex = 11
	status.Parent = side
	self.status = status

	local function makeSideButton(text: string, y: number, height: number, color: Color3)
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, height)
		button.Position = UDim2.fromOffset(0, y)
		button.BackgroundColor3 = color
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.TextColor3 = if color == ACCENT then Color3.new(0, 0, 0) else TEXT
		button.Text = text
		button.ZIndex = 11
		button.Parent = side
		corner(button, UDim.new(0, 8))
		return button
	end

	self.spinButton = makeSideButton("Tourner", 244, 46, ACCENT)
	self.buyButton =
		makeSideButton("Tour supplementaire (Robux)", 298, 38, Color3.fromRGB(46, 42, 50))
	self.buyButton.TextSize = 13
	self.closeButton = makeSideButton("Fermer", 344, 34, Color3.fromRGB(36, 33, 40))
	self.closeButton.TextSize = 13

	return self
end

function WheelUI:isOpen(): boolean
	return self.overlay.Visible
end

function WheelUI:setOpen(open: boolean)
	self.overlay.Visible = open
end

--[[ Etat du bouton principal selon le cooldown restant. ]]
function WheelUI:setCooldown(remaining: number, formatted: string)
	if self.spinning then
		return
	end

	if remaining <= 0 then
		self.spinButton.Text = "Tourner"
		self.spinButton.BackgroundColor3 = ACCENT
		self.spinButton.TextColor3 = Color3.new(0, 0, 0)
		if self.status.Text == "" then
			self.status.Text = "La roue est prete."
		end
	else
		self.spinButton.Text = formatted
		self.spinButton.BackgroundColor3 = Color3.fromRGB(60, 56, 64)
		self.spinButton.TextColor3 = TEXT
	end
end

function WheelUI:setStatus(text: string)
	self.status.Text = text
end

--[[
	Anime le disque jusqu'au lot donne, puis appelle `onDone`.

	Le calcul central : un secteur dessine a l'angle A apparait a A + R une
	fois le disque tourne de R. Pour amener le centre du secteur gagnant
	sous l'aiguille (angle 0), il faut R = -centerAngle, modulo 360. On y
	ajoute cinq tours pour que le mouvement se voie.
]]
function WheelUI:playSpin(prizeKey: string, onDone: (Segment?) -> ())
	if self.spinning then
		return
	end

	local target: Segment? = nil
	for _, segment in self.segments do
		if segment.key == prizeKey then
			target = segment
			break
		end
	end

	if target == nil then
		-- Cle inconnue : ne pas inventer un secteur, ne pas animer au
		-- hasard. Le joueur a deja recu sa recompense cote serveur.
		warn(`[WheelUI] lot inconnu renvoye par le serveur : {prizeKey}`)
		onDone(nil)
		return
	end

	self.spinning = true
	self.spinButton.Text = "..."
	self.spinButton.BackgroundColor3 = Color3.fromRGB(60, 56, 64)
	self.status.Text = ""

	local current = self.disc.Rotation
	local base = current - (current % 360)
	local landing = (360 - target.centerAngle) % 360
	local final = base + FULL_TURNS * 360 + landing
	if final <= current then
		final += 360
	end

	local tween = TweenService:Create(
		self.disc,
		TweenInfo.new(
			GameConfig.wheel.spinDuration,
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		),
		{ Rotation = final }
	)

	tween.Completed:Connect(function()
		self.spinning = false
		onDone(target)
	end)

	tween:Play()
end

-- Exposes pour les tests : la geometrie et la palette sont la partie de
-- ce module qui peut se tromper en silence, donc la partie qui doit etre
-- verifiable sans construire d'interface.
WheelUI.buildSegments = buildSegments
WheelUI.PRIZE_COLORS = PRIZE_COLORS

return WheelUI
