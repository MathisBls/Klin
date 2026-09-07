--!strict
--[[
	Placement du decor du lobby. DE LA DONNEE, PAS DU CODE : deplacer un
	arbre ne doit pas demander de toucher a une fonction.

	LES IDS D'ASSETS ONT ETE VERIFIES, PAS DEVINES

	Chacun est passe par trois filtres, dans cet ordre :
	  1. recherche sur le Creator Store, gratuits seulement
	  2. rejet automatique de tout modele contenant un script - c'est le
	     vecteur de backdoor le plus courant sur Roblox
	  3. `tools/probe_assets.py` : chargement REEL via InsertService dans un
	     serveur Roblox, qui a confirme les 21 references ci-dessous

	Cette troisieme etape n'est pas du zele. Sur 50 modeles gratuits bien
	notes trouves par la recherche, un seul se chargeait : LoadAsset exige
	que l'asset appartienne au proprietaire de la place ou ait ete cree par
	Roblox. Tous les modeles retenus ici sont crees par Roblox.

	Les tailles indiquees sont celles mesurees par la sonde, pas des
	estimations - c'est ce qui permet de poser les objets sans qu'ils
	s'interpenetrent.
]]

export type Prop = {
	asset: string,
	position: Vector3,
	-- Rotation autour de l'axe vertical, en degres.
	rotation: number?,
	scale: number?,
}

export type PropLine = {
	asset: string,
	from: Vector3,
	to: Vector3,
	-- Espacement en studs entre deux exemplaires.
	spacing: number,
	-- Decalage lateral. Une valeur et son opposee bordent un chemin.
	offset: number?,
	scale: number?,
	-- Variation aleatoire de rotation, pour eviter l'alignement mecanique.
	jitterRotation: boolean?,
}

local Layout = {}

--[[
	Catalogue verifie. `parts` sert de budget : l'Oak Tree pese 437 parts,
	on ne le clone donc que deux fois, alors que Tree - Large en pese 16.
]]
Layout.assets = {
	OAK_TREE = { id = 18717544, parts = 437, size = Vector3.new(40, 39, 45) },
	TREE_LARGE = { id = 56449188, parts = 16, size = Vector3.new(12, 16, 12) },
	TREE_MEDIUM = { id = 56449156, parts = 10, size = Vector3.new(4, 16, 4) },
	TREE_SMALL = { id = 56449132, parts = 6, size = Vector3.new(4, 8, 4) },
	TREE_AUTUMN = { id = 56449099, parts = 16, size = Vector3.new(12, 16, 12) },
	PARK_BENCH = { id = 23153972, parts = 14, size = Vector3.new(4, 5, 9) },
	CONCRETE_BENCH = { id = 23153979, parts = 5, size = Vector3.new(2, 1, 7) },
	FLOWERS = { id = 56448980, parts = 2, size = Vector3.new(4, 4, 4) },
	FENCE = { id = 56449052, parts = 6, size = Vector3.new(8, 4, 4) },
	ARCH = { id = 56448235, parts = 19, size = Vector3.new(8, 8, 12) },
	ARCH_RAILING = { id = 56448208, parts = 22, size = Vector3.new(8, 8, 12) },
	FLAG_RED = { id = 82351, parts = 2, size = Vector3.new(5, 6, 5) },
	FLAG_BLUE = { id = 82352, parts = 2, size = Vector3.new(5, 6, 5) },
	STREETLIGHT = { id = 56449028, parts = 6, size = Vector3.new(4, 16, 9) },
}

-- Budget total de parts clonees. Au-dela, le lobby rame sur une machine
-- modeste, et un lobby qui rame ne donne envie de rester nulle part.
Layout.partBudget = 4000

--[[
	Objets places un par un. Les positions viennent du plan de masse de la
	spec : place centrale a l'origine, quatre bras vers N/S/E/O.
]]
Layout.props = {
	-- Les deux grands chenes encadrent la place, en fond de perspective.
	{ asset = "OAK_TREE", position = Vector3.new(-96, 0, -96) },
	{ asset = "OAK_TREE", position = Vector3.new(96, 0, -96) },

	-- Bancs autour de la fontaine, tournes vers elle.
	{ asset = "PARK_BENCH", position = Vector3.new(0, 0, 34), rotation = 0 },
	{ asset = "PARK_BENCH", position = Vector3.new(0, 0, -34), rotation = 180 },
	{ asset = "PARK_BENCH", position = Vector3.new(34, 0, 0), rotation = 90 },
	{ asset = "PARK_BENCH", position = Vector3.new(-34, 0, 0), rotation = 270 },

	-- Arches du portail nord, de part et d'autre du chemin.
	{ asset = "ARCH_RAILING", position = Vector3.new(-14, 0, -120), rotation = 90 },
	{ asset = "ARCH_RAILING", position = Vector3.new(14, 0, -120), rotation = 90 },

	-- Drapeaux d'equipe a l'entree des terrains.
	{ asset = "FLAG_RED", position = Vector3.new(-24, 0, -132) },
	{ asset = "FLAG_BLUE", position = Vector3.new(24, 0, -132) },
	{ asset = "FLAG_RED", position = Vector3.new(-24, 0, -168) },
	{ asset = "FLAG_BLUE", position = Vector3.new(24, 0, -168) },

	-- Massifs fleuris aux angles de la place.
	{ asset = "FLOWERS", position = Vector3.new(-46, 0, -46) },
	{ asset = "FLOWERS", position = Vector3.new(46, 0, -46) },
	{ asset = "FLOWERS", position = Vector3.new(-46, 0, 46) },
	{ asset = "FLOWERS", position = Vector3.new(46, 0, 46) },

	-- Verdure du belvedere sud.
	{ asset = "TREE_AUTUMN", position = Vector3.new(-40, 24, 190) },
	{ asset = "TREE_AUTUMN", position = Vector3.new(40, 24, 190) },
	{ asset = "TREE_LARGE", position = Vector3.new(-24, 24, 214) },
	{ asset = "TREE_LARGE", position = Vector3.new(24, 24, 214) },
} :: { Prop }

--[[
	Lignes d'objets. Un chemin borde d'arbres et de lampadaires se lit
	comme un chemin ; le meme chemin nu ressemble a une dalle oubliee.
]]
Layout.lines = {
	-- Lampadaires le long des quatre bras.
	{
		asset = "STREETLIGHT",
		from = Vector3.new(0, 0, -70),
		to = Vector3.new(0, 0, -180),
		spacing = 36,
		offset = 16,
	},
	{
		asset = "STREETLIGHT",
		from = Vector3.new(0, 0, 70),
		to = Vector3.new(0, 0, 170),
		spacing = 36,
		offset = 16,
	},
	{
		asset = "STREETLIGHT",
		from = Vector3.new(70, 0, 0),
		to = Vector3.new(180, 0, 0),
		spacing = 36,
		offset = 16,
	},
	{
		asset = "STREETLIGHT",
		from = Vector3.new(-70, 0, 0),
		to = Vector3.new(-180, 0, 0),
		spacing = 36,
		offset = 16,
	},

	-- Arbres en second rideau, plus loin que les lampadaires pour creer
	-- de la profondeur plutot qu'un couloir.
	{
		asset = "TREE_LARGE",
		from = Vector3.new(0, 0, -80),
		to = Vector3.new(0, 0, -190),
		spacing = 40,
		offset = 40,
		jitterRotation = true,
	},
	{
		asset = "TREE_MEDIUM",
		from = Vector3.new(0, 0, 80),
		to = Vector3.new(0, 0, 160),
		spacing = 34,
		offset = 40,
		jitterRotation = true,
	},
	{
		asset = "TREE_LARGE",
		from = Vector3.new(80, 0, 0),
		to = Vector3.new(190, 0, 0),
		spacing = 40,
		offset = 40,
		jitterRotation = true,
	},
	{
		asset = "TREE_MEDIUM",
		from = Vector3.new(-80, 0, 0),
		to = Vector3.new(-190, 0, 0),
		spacing = 34,
		offset = 44,
		jitterRotation = true,
	},

	-- Petits arbres dans les quadrants, pour que le regard ne bute pas
	-- sur une pelouse vide entre deux bras.
	{
		asset = "TREE_SMALL",
		from = Vector3.new(-80, 0, -80),
		to = Vector3.new(-200, 0, -200),
		spacing = 34,
		offset = 26,
		jitterRotation = true,
	},
	{
		asset = "TREE_SMALL",
		from = Vector3.new(80, 0, -80),
		to = Vector3.new(200, 0, -200),
		spacing = 34,
		offset = 26,
		jitterRotation = true,
	},
	{
		asset = "TREE_SMALL",
		from = Vector3.new(-80, 0, 80),
		to = Vector3.new(-200, 0, 200),
		spacing = 34,
		offset = 26,
		jitterRotation = true,
	},

	-- Barrieres qui bordent l'aire d'entrainement, a l'est.
	{
		asset = "FENCE",
		from = Vector3.new(140, 0, -48),
		to = Vector3.new(210, 0, -48),
		spacing = 8,
	},
	{
		asset = "FENCE",
		from = Vector3.new(140, 0, 48),
		to = Vector3.new(210, 0, 48),
		spacing = 8,
	},
} :: { PropLine }

--[[
	Panneaux flottants. Deux lignes au maximum : un panneau qu'on doit
	lire n'est plus un panneau.
]]
export type Sign = {
	position: Vector3,
	title: string,
	subtitle: string,
	color: Color3,
}

Layout.signs = {
	{
		position = Vector3.new(0, 26, -120),
		title = "TERRAINS",
		subtitle = "Entre pour jouer un match",
		color = Color3.fromRGB(72, 200, 110),
	},
	{
		position = Vector3.new(-52, 18, -120),
		title = "REGLES",
		subtitle = "3 contre 3  ·  5 minutes  ·  premier a 3 buts",
		color = Color3.fromRGB(240, 200, 80),
	},
	{
		position = Vector3.new(-150, 24, 0),
		title = "BOUTIQUES",
		subtitle = "Maillots, ballons, celebrations",
		color = Color3.fromRGB(120, 170, 255),
	},
	{
		position = Vector3.new(150, 24, 0),
		title = "ENTRAINEMENT",
		subtitle = "Tire au but, sans enjeu",
		color = Color3.fromRGB(255, 150, 70),
	},
	{
		position = Vector3.new(0, 42, 200),
		title = "BELVEDERE",
		subtitle = "Vue sur tout le lobby",
		color = Color3.fromRGB(200, 160, 255),
	},
} :: { Sign }

return table.freeze(Layout)
