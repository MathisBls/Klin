--!strict
--[[
	Tir au but : visee puis puissance, en deux clics.

	CE QUE CE MODULE NE FAIT PAS

	Il ne decide rien. Il collecte trois nombres dans [0, 1] et les envoie.
	Le serveur tranche, puis renvoie l'issue, que l'on met en scene. La
	trajectoire du ballon est un tween : le ballon n'est jamais un objet
	physique, ce qui supprime toute question de propriete reseau et rend
	la triche impossible.

	DEROULE

	1. Un reticule balaie la largeur du but. Un clic fixe X et Y.
	2. Une jauge monte et descend. Un clic fixe la puissance.
	3. Envoi, attente, animation du resultat.

	Le balayage est volontairement rapide : la decision doit se prendre en
	trois secondes, sinon le tir devient un simple bouton.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PenaltyUI = {}
PenaltyUI.__index = PenaltyUI

local PANEL = Color3.fromRGB(18, 20, 26)
local TEXT = Color3.fromRGB(240, 244, 248)
local ACCENT = Color3.fromRGB(64, 200, 120)
local DANGER = Color3.fromRGB(226, 82, 66)

-- Vitesses de balayage, en aller-retour par seconde.
local AIM_SPEED = 0.75
local POWER_SPEED = 1.1

local function corner(instance: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = instance
end

function PenaltyUI.new(parentGui: ScreenGui)
	local self = setmetatable({}, PenaltyUI)

	self.phase = "idle" :: "idle" | "aim" | "power" | "waiting"
	self.aimX = 0.5
	self.aimY = 0.5
	self.power = 0.5
	self.onShoot = nil :: ((number, number, number) -> ())?

	local overlay = Instance.new("Frame")
	overlay.Name = "PenaltyOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.ZIndex = 20
	overlay.Parent = parentGui
	self.overlay = overlay

	-- Cadre du but, en coordonnees ecran. Le reticule s'y deplace, ce qui
	-- rend la visee lisible sans avoir a projeter la geometrie 3D.
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(520, 240)
	frame.Position = UDim2.fromScale(0.5, 0.32)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.92
	frame.BorderSizePixel = 0
	frame.ZIndex = 20
	frame.Parent = overlay
	self.frame = frame

	local border = Instance.new("UIStroke")
	border.Color = Color3.fromRGB(255, 255, 255)
	border.Thickness = 3
	border.Transparency = 0.4
	border.Parent = frame

	local reticle = Instance.new("Frame")
	reticle.Size = UDim2.fromOffset(34, 34)
	reticle.AnchorPoint = Vector2.new(0.5, 0.5)
	reticle.BackgroundColor3 = ACCENT
	reticle.BackgroundTransparency = 0.25
	reticle.BorderSizePixel = 0
	reticle.ZIndex = 21
	reticle.Parent = frame
	corner(reticle, 17)
	self.reticle = reticle

	local reticleStroke = Instance.new("UIStroke")
	reticleStroke.Color = Color3.new(1, 1, 1)
	reticleStroke.Thickness = 2
	reticleStroke.Parent = reticle

	-- Jauge de puissance, sous le cadre.
	local gauge = Instance.new("Frame")
	gauge.Size = UDim2.fromOffset(520, 26)
	gauge.Position = UDim2.new(0.5, 0, 0.32, 148)
	gauge.AnchorPoint = Vector2.new(0.5, 0)
	gauge.BackgroundColor3 = PANEL
	gauge.BorderSizePixel = 0
	gauge.Visible = false
	gauge.ZIndex = 20
	gauge.Parent = overlay
	corner(gauge, 6)
	self.gauge = gauge

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.ZIndex = 21
	fill.Parent = gauge
	corner(fill, 6)
	self.fill = fill

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromOffset(520, 30)
	hint.Position = UDim2.new(0.5, 0, 0.32, 190)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 18
	hint.TextColor3 = TEXT
	hint.TextStrokeTransparency = 0.5
	hint.Text = ""
	hint.ZIndex = 20
	hint.Parent = overlay
	self.hint = hint

	local result = Instance.new("TextLabel")
	result.Size = UDim2.fromOffset(600, 60)
	result.Position = UDim2.fromScale(0.5, 0.62)
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.GothamBold
	result.TextSize = 42
	result.TextColor3 = TEXT
	result.TextStrokeTransparency = 0.4
	result.Text = ""
	result.ZIndex = 22
	result.Parent = overlay
	self.result = result

	self.connection = RunService.RenderStepped:Connect(function(delta)
		self:step(delta)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not overlay.Visible then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space
		then
			self:advance()
		end
	end)

	return self
end

--[[ Balayage du reticule puis de la jauge. Un aller-retour, pas un cycle. ]]
function PenaltyUI:step(delta: number)
	if self.phase == "aim" then
		self.sweep = (self.sweep or 0) + delta * AIM_SPEED
		-- Triangle : 0 -> 1 -> 0, plus lisible qu'une sinusoide pour viser.
		local t = math.abs(((self.sweep * 2) % 2) - 1)
		self.aimX = t
		-- La hauteur suit un second balayage plus lent : viser une lucarne
		-- demande de reussir les deux, ce qui justifie sa difficulte.
		self.aimY = math.abs(((self.sweep * 1.3) % 2) - 1)

		self.reticle.Position = UDim2.fromScale(self.aimX, 1 - self.aimY)
	elseif self.phase == "power" then
		self.powerSweep = (self.powerSweep or 0) + delta * POWER_SPEED
		self.power = math.abs(((self.powerSweep * 2) % 2) - 1)

		self.fill.Size = UDim2.fromScale(self.power, 1)
		-- La jauge vire au rouge dans le haut : la puissance maximale est
		-- un choix risque, l'UI doit le dire sans texte.
		self.fill.BackgroundColor3 = if self.power > 0.8 then DANGER else ACCENT
	end
end

--[[ Un clic fait avancer d'une phase. ]]
function PenaltyUI:advance()
	if self.phase == "aim" then
		self.phase = "power"
		self.gauge.Visible = true
		self.powerSweep = 0
		self.hint.Text = "Clique pour doser la frappe"
	elseif self.phase == "power" then
		self.phase = "waiting"
		self.hint.Text = ""
		if self.onShoot then
			self.onShoot(self.aimX, self.aimY, self.power)
		end
	end
end

--[[ Ouvre la phase de visee. `onShoot` recoit (x, y, puissance). ]]
function PenaltyUI:prompt(onShoot: (number, number, number) -> ())
	self.onShoot = onShoot
	self.phase = "aim"
	self.sweep = 0
	self.gauge.Visible = false
	self.result.Text = ""
	self.hint.Text = "Clique pour viser"
	self.overlay.Visible = true
end

--[[
	Met en scene l'issue decidee par le serveur. Le ballon suit un tween
	vers le point vise : c'est une illustration, pas une simulation.
]]
function PenaltyUI:showOutcome(outcome: any)
	self.phase = "idle"
	self.gauge.Visible = false

	local ball = Workspace:FindFirstChild("Ball", true)
	local keeper = Workspace:FindFirstChild("Keeper", true)

	if ball and ball:IsA("BasePart") then
		local origin = ball.CFrame
		-- Le but s'etend de -12 a +12 en X, de 0 a 16 en Y, a Z = -14.
		local targetX = (self.aimX - 0.5) * 22
		local targetY = 1 + self.aimY * 13

		if outcome.result == "missed" then
			-- Un tir manque sort du cadre : on exagere l'ecart pour que
			-- le joueur voie pourquoi.
			targetX = targetX * 1.6
			targetY = targetY + 4
		end

		local flight = TweenService:Create(
			ball,
			TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(targetX, targetY, -15) }
		)
		flight:Play()

		task.delay(1.6, function()
			TweenService:Create(ball, TweenInfo.new(0.3), { CFrame = origin }):Play()
		end)
	end

	if keeper and keeper:IsA("BasePart") then
		local origin = keeper.CFrame
		local offset = if outcome.keeperDive == "left"
			then -7
			elseif outcome.keeperDive == "right" then 7
			else 0

		TweenService:Create(
			keeper,
			TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = origin * CFrame.new(offset, 0, 0) }
		):Play()

		task.delay(1.6, function()
			TweenService:Create(keeper, TweenInfo.new(0.3), { CFrame = origin }):Play()
		end)
	end

	if outcome.result == "goal" then
		self.result.Text = "BUT !"
		self.result.TextColor3 = ACCENT
	elseif outcome.result == "saved" then
		self.result.Text = "ARRET DU GARDIEN"
		self.result.TextColor3 = DANGER
	else
		self.result.Text = "A COTE"
		self.result.TextColor3 = DANGER
	end

	task.delay(2.2, function()
		if self.phase == "idle" then
			self.overlay.Visible = false
			self.result.Text = ""
		end
	end)
end

function PenaltyUI:isActive(): boolean
	return self.overlay.Visible
end

return PenaltyUI
