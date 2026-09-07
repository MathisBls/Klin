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
		EXTRA_SPIN = 3711754780,
		SHARDS_POUCH = 3711754781,
	},
	-- cle logique -> gamePassId
	gamePasses = {},
}

return table.freeze(Config)
