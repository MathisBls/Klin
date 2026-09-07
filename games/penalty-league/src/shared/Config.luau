--!strict
--[[
	FICHIER GENERE - ne pas editer a la main.
	Regenere par `make assets` et `make products` depuis :
	  assets/assets.lock.json
	  assets/products.lock.json
]]

export type Config = {
	assets: { [string]: string },
	developerProducts: { [string]: number },
	gamePasses: { [string]: number },
}

local Config: Config = {
	-- cle logique -> rbxassetid://
	assets = {},
	-- cle logique -> productId
	developerProducts = {
		CREDITS_LARGE = 3711762200,
		PACK_GOLD = 3711762203,
	},
	-- cle logique -> gamePassId
	gamePasses = {
		SEASON_PASS = 1969755436,
	},
}

return table.freeze(Config)
