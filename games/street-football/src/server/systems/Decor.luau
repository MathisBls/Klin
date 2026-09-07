--!strict
--[[
	Charge le decor du lobby depuis les assets verifies, et le pose.

	TROIS REGLES QUI GOUVERNENT CE FICHIER

	1. CHARGER UNE FOIS, CLONER ENSUITE. Trente arbres identiques, c'est un
	   appel reseau, pas trente. Sans ce cache, le demarrage du serveur
	   prendrait des dizaines de secondes.

	2. REFUSER TOUT SCRIPT. Un modele du Creator Store peut contenir un
	   Script - c'est le vecteur de backdoor le plus courant sur Roblox. La
	   recherche les filtre deja, la sonde aussi, et on refuse encore ici.
	   Trois filtres pour la meme chose, parce qu'un seul suffit a echouer.

	3. UN ECHEC NE CASSE PAS LE LOBBY. Un asset retire du catalogue rend
	   `LoadAsset` faux ; on le signale et on continue. Un lobby ampute d'un
	   arbre vaut mieux qu'un lobby qui ne demarre pas.
]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Layout = require(ReplicatedStorage.Shared.config.LobbyLayout)

local Decor = {}

local cache: { [number]: Model? } = {}
local placedParts = 0

--[[
	Retire tout script d'un modele charge et signale s'il y en avait.
	On ne se fie pas a la metadonnee `hasScripts` de la recherche : pour une
	question de securite, on verifie l'objet reel.
]]
local function stripScripts(model: Instance, assetId: number): number
	local removed = 0

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
			removed += 1
		end
	end

	if removed > 0 then
		warn(
			`[Decor] asset {assetId} contenait {removed} script(s) - retires. `
				.. `A retirer du layout : un modele scripte n'a rien a faire ici.`
		)
	end

	return removed
end

--[[ Charge un asset une seule fois. Renvoie nil si le chargement echoue. ]]
local function loadAsset(assetId: number): Model?
	if cache[assetId] ~= nil then
		return cache[assetId]
	end

	local success, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)

	if not success or result == nil then
		warn(`[Decor] chargement impossible de l'asset {assetId} : {result}`)
		cache[assetId] = nil
		return nil
	end

	stripScripts(result, assetId)

	-- LoadAsset renvoie un conteneur ; le vrai modele est son enfant.
	local model = result:FindFirstChildWhichIsA("Model") or result
	model.Parent = nil
	result:Destroy()

	cache[assetId] = model
	return model
end

--[[ Compte les parts d'un modele, pour tenir le budget. ]]
local function countParts(model: Instance): number
	local total = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			total += 1
		end
	end
	return total
end

--[[
	Pose une copie. Le modele est ancre entierement : un decor non ancre
	tombe, et emmene parfois le joueur avec lui.
]]
local function place(
	template: Model,
	parent: Instance,
	position: Vector3,
	rotation: number,
	scale: number
): boolean
	local cost = countParts(template)
	if placedParts + cost > Layout.partBudget then
		return false
	end

	local clone = template:Clone()

	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			-- Le decor ne doit pas bloquer le passage : un joueur qui reste
			-- coince dans un massif de fleurs ne revient pas.
			if descendant.Size.Y < 6 then
				descendant.CanCollide = false
			end
		end
	end

	if scale ~= 1 then
		local ok = pcall(function()
			clone:ScaleTo(scale)
		end)
		if not ok then
			warn(`[Decor] mise a l'echelle impossible pour {clone.Name}`)
		end
	end

	local pivot = CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0)
	clone:PivotTo(pivot)
	clone.Parent = parent

	placedParts += cost
	return true
end

--[[ Repartit des copies le long d'un segment, des deux cotes si `offset`. ]]
local function placeLine(line: Layout.PropLine, template: Model, parent: Instance, rng: Random)
	local direction = line.to - line.from
	local length = direction.Magnitude
	if length < 1 then
		return
	end

	local unit = direction.Unit
	-- Perpendiculaire horizontale, pour border un chemin des deux cotes.
	local side = Vector3.new(-unit.Z, 0, unit.X)
	local steps = math.floor(length / line.spacing)
	local offset = line.offset or 0
	local scale = line.scale or 1

	for step = 0, steps do
		local base = line.from + unit * (step * line.spacing)
		local rotation = if line.jitterRotation then rng:NextInteger(0, 359) else 0

		if offset == 0 then
			place(template, parent, base, rotation, scale)
		else
			place(template, parent, base + side * offset, rotation, scale)
			place(template, parent, base - side * offset, rotation, scale)
		end
	end
end

--[[ Construit tout le decor. A appeler une fois au demarrage serveur. ]]
function Decor.build()
	local folder = Workspace:FindFirstChild("Decor")
	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = Workspace

	placedParts = 0
	local rng = Random.new(20260907)
	local loaded, missing = 0, 0

	local function templateFor(key: string): Model?
		local entry = Layout.assets[key]
		if entry == nil then
			warn(`[Decor] cle d'asset inconnue dans le layout : {key}`)
			return nil
		end

		local template = loadAsset(entry.id)
		if template == nil then
			missing += 1
			return nil
		end
		return template
	end

	for _, prop in Layout.props do
		local template = templateFor(prop.asset)
		if template then
			if place(template, folder, prop.position, prop.rotation or 0, prop.scale or 1) then
				loaded += 1
			end
		end
	end

	for _, line in Layout.lines do
		local template = templateFor(line.asset)
		if template then
			placeLine(line, template, folder, rng)
		end
	end

	print(
		`[Decor] {#folder:GetChildren()} objet(s) poses, {placedParts} parts, `
			.. `{missing} asset(s) indisponible(s)`
	)

	if placedParts >= Layout.partBudget then
		warn(
			`[Decor] budget de {Layout.partBudget} parts atteint - du decor a `
				.. `ete omis. Reduis le layout plutot que de lever le budget.`
		)
	end
end

--[[ Expose l'etat pour les tests. ]]
function Decor.stats(): { placedParts: number, cachedAssets: number }
	local cached = 0
	for _ in cache do
		cached += 1
	end
	return { placedParts = placedParts, cachedAssets = cached }
end

return Decor
