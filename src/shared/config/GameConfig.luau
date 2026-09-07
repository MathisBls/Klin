--!strict
--[[
	Toutes les valeurs chiffrees du jeu, au meme endroit.
	Reference : games/forge-clicker/spec.md

	Aucun ID Roblox ici : ils vivent dans Config.luau, genere par
	`make assets` et `make products`.
]]

export type UpgradeKey = "HAMMER" | "BELLOWS" | "APPRENTICE"

export type Upgrade = {
	key: UpgradeKey,
	displayName: string,
	description: string,
	basePrice: number,
	-- Prix du niveau n = basePrice * priceGrowth ^ n
	priceGrowth: number,
	maxLevel: number,
}

export type PrizeReward =
	{ kind: "shards", amount: number }
	| { kind: "multiplier", value: number, duration: number }

export type Prize = {
	key: string,
	displayName: string,
	-- Poids relatif. La somme fait 100 pour se lire en pourcentage direct.
	weight: number,
	reward: PrizeReward,
}

local GameConfig = {
	slug = "forge-clicker",

	currency = {
		key = "shards",
		displayName = "Eclats",
		startingAmount = 0,
		-- Abrege au-dela de 1000 : 1.5K, 2.3M.
		abbreviateAbove = 1000,
	},

	click = {
		-- Gain de base avant toute amelioration.
		baseGain = 1,
		-- Anti-spam : le serveur refuse les clics plus rapproches que ca.
		-- 12 clics/s est au-dessus de ce qu'un humain fait (~8 en pointe),
		-- donc ne gene aucun joueur legitime tout en plafonnant un autoclicker.
		minInterval = 1 / 12,
	},

	upgrades = {
		{
			key = "HAMMER" :: UpgradeKey,
			displayName = "Marteau",
			description = "+1 eclat par coup",
			basePrice = 25,
			priceGrowth = 1.35,
			maxLevel = 25,
		},
		{
			key = "BELLOWS" :: UpgradeKey,
			displayName = "Soufflet",
			description = "+10% de gain",
			basePrice = 100,
			priceGrowth = 1.50,
			maxLevel = 15,
		},
		{
			key = "APPRENTICE" :: UpgradeKey,
			displayName = "Apprenti",
			description = "+1 eclat par seconde",
			basePrice = 250,
			priceGrowth = 1.60,
			maxLevel = 20,
		},
	} :: { Upgrade },

	wheel = {
		-- 4 heures. La roue est le pari de retention de ce jeu.
		cooldownSeconds = 4 * 60 * 60,
		spinDuration = 3.5,
		prizes = {
			{
				key = "HANDFUL",
				displayName = "Poignee d'eclats",
				weight = 40,
				reward = { kind = "shards", amount = 50 },
			},
			{
				key = "PURSE",
				displayName = "Bourse",
				weight = 25,
				reward = { kind = "shards", amount = 150 },
			},
			{
				key = "CHEST",
				displayName = "Coffre",
				weight = 15,
				reward = { kind = "shards", amount = 500 },
			},
			{
				key = "HEAVY_CHEST",
				displayName = "Coffre lourd",
				weight = 10,
				reward = { kind = "shards", amount = 2000 },
			},
			{
				key = "EMBER",
				displayName = "Braise ardente",
				weight = 8,
				reward = { kind = "multiplier", value = 2, duration = 300 },
			},
			{
				key = "FORGE_HEART",
				displayName = "Coeur de forge",
				weight = 2,
				reward = { kind = "shards", amount = 10000 },
			},
		} :: { Prize },
	},

	products = {
		-- Cles logiques. Les productId reels sont dans Config.developerProducts,
		-- ecrits par `make products`.
		SHARDS_POUCH = { displayName = "Bourse d'eclats", grantShards = 10000 },
		EXTRA_SPIN = { displayName = "Tour supplementaire", grantSpin = true },
	},

	autosaveIntervalSeconds = 300,
	-- Tick de la production automatique. 1 s : assez fin pour etre lisible,
	-- assez large pour ne pas peser sur le serveur.
	apprenticeTickSeconds = 1,
}

return table.freeze(GameConfig)
