--!strict
--[[
	Abreviation des grands nombres pour l'affichage.
	1500 -> "1.5K", 2340000 -> "2.34M"

	Partage client/serveur : les deux doivent afficher la meme chaine, sinon
	le joueur voit un prix different de celui que le serveur applique.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

--[[
	Abrege un nombre au-dela de `threshold`. En dessous, renvoie l'entier
	tel quel : "847" est plus lisible que "0.85K".
]]
function Format.number(value: number, threshold: number?): string
	local limit = threshold or 1000

	if value < limit then
		return tostring(math.floor(value))
	end

	local tier = math.floor(math.log(value, 1000))
	tier = math.clamp(tier, 0, #SUFFIXES - 1)

	local scaled = value / (1000 ^ tier)
	-- Deux decimales sous 10, une seule au-dessus : "9.99K" puis "23.4K".
	-- Garde une largeur d'affichage a peu pres constante.
	local text = if scaled < 10
		then string.format("%.2f", scaled)
		else string.format("%.1f", scaled)

	-- Retire les zeros finaux : "1.50K" -> "1.5K", "2.00M" -> "2M".
	text = text:gsub("%.?0+$", "")

	return text .. SUFFIXES[tier + 1]
end

--[[
	Duree en secondes vers "3h 42m" ou "42m 10s". Utilise pour le cooldown
	de la roue.
]]
function Format.duration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	local rest = total % 60

	if hours > 0 then
		return `{hours}h {minutes}m`
	end
	if minutes > 0 then
		return `{minutes}m {rest}s`
	end
	return `{rest}s`
end

return Format
