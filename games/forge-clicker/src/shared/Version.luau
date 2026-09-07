--!strict
--[[
	Marqueur de build. Sert de preuve que le pipeline Rojo -> Open Cloud
	fonctionne de bout en bout : si ce module est present dans la place
	publiee, c'est que le build local est bien celui qui tourne en ligne.
]]

export type BuildInfo = {
	name: string,
	version: string,
}

local Version: BuildInfo = {
	name = "Klin",
	version = "0.1.0",
}

return table.freeze(Version)
