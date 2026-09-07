--!strict
--[[
	Championnat : adversaires, classement, fin de saison.

	CHOIX STRUCTURANT : LA LIGUE EST ASYNCHRONE

	On affronte la PHOTO de l'equipe d'un autre joueur, jamais le joueur en
	direct. Pas de matchmaking, pas de serveur partage, pas de replication
	temps reel - et le jeu fonctionne avec un seul joueur connecte.

	Le pool d'adversaires est complete par des clubs generes quand il est
	trop mince. Un classement vide decourage plus qu'il ne motive, et un
	jeu qui n'a pas encore de joueurs doit quand meme etre jouable.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Ratings = require(ReplicatedStorage.Shared.Ratings)
local Save = require(ServerScriptService.Server.systems.Save)
local Squad = require(ServerScriptService.Server.systems.Squad)

export type Club = {
	id: string,
	name: string,
	ratings: Ratings.TeamRatings,
	-- true pour un club genere, false pour la photo d'un joueur reel.
	generated: boolean,
}

local League = {}

local POOL_STORE = "PenaltyLeague_Pool_v1"
local pool = DataStoreService:GetDataStore(POOL_STORE)

-- Cache par division, rafraichi periodiquement. Une lecture partagee pour
-- tout le serveur : vingt joueurs ne doivent pas declencher vingt requetes
-- DataStore.
local cache: { [number]: { clubs: { Club }, fetchedAt: number } } = {}
local CACHE_SECONDS = 120

--[[
	Note cible d'une division. La division 5 tourne autour de 55, la 1
	autour de 91 : la progression doit se sentir sans devenir infranchissable.
]]
function League.targetRating(division: number): number
	local lowest = GameConfig.league.lowestDivision
	local highest = GameConfig.league.highestDivision
	local span = math.max(1, lowest - highest)
	local position = (lowest - division) / span

	return 55 + position * 36
end

local GENERATED_NAMES = {
	"AC Verdon",
	"Real Solene",
	"FC Marbre",
	"Union Kastel",
	"SC Havane",
	"Olympique Tarn",
	"FC Lumen",
	"Sporting Ombre",
	"AS Cendre",
	"Racing Bruyere",
	"FC Zephyr",
	"CD Ferro",
	"Athletic Novo",
	"FC Ardoise",
	"Inter Brume",
}

--[[ Fabrique un club genere, reproductible a partir de son index. ]]
local function generateClub(division: number, index: number): Club
	local rng = Random.new(division * 1000 + index)
	local target = League.targetRating(division)
	local lineup = Ratings.generateLineup(rng, math.floor(target))

	return {
		id = `bot:{division}:{index}`,
		name = GENERATED_NAMES[(index - 1) % #GENERATED_NAMES + 1],
		ratings = Ratings.compute(lineup),
		generated = true,
	}
end

--[[
	Clubs d'une division : joueurs reels d'abord, completes par des clubs
	generes. Toute lecture DataStore est enveloppee dans un pcall : un
	DataStore indisponible ne doit pas empecher de jouer.
]]
function League.clubs(division: number): { Club }
	local cached = cache[division]
	if cached and os.clock() - cached.fetchedAt < CACHE_SECONDS then
		return cached.clubs
	end

	local clubs: { Club } = {}

	local ok, stored = pcall(function()
		return pool:GetAsync(`division_{division}`)
	end)

	if ok and typeof(stored) == "table" then
		for _, entry in stored do
			if typeof(entry) == "table" and entry.id and entry.ratings then
				table.insert(clubs, {
					id = entry.id,
					name = entry.name or "Club",
					ratings = entry.ratings,
					generated = false,
				})
			end
		end
	elseif not ok then
		warn(`[League] lecture du pool impossible : {stored}`)
	end

	local index = 1
	while #clubs < GameConfig.league.clubsPerDivision do
		table.insert(clubs, generateClub(division, index))
		index += 1
	end

	cache[division] = { clubs = clubs, fetchedAt = os.clock() }
	return clubs
end

--[[
	Adversaire d'une journee. Deterministe : la meme journee renvoie
	toujours le meme adversaire, sinon un joueur pourrait relancer jusqu'a
	tomber sur un club faible.
]]
function League.opponentFor(player: Player, division: number, matchday: number): Club
	local clubs = League.clubs(division)
	local mine = `player:{player.UserId}`

	local candidates: { Club } = {}
	for _, club in clubs do
		if club.id ~= mine then
			table.insert(candidates, club)
		end
	end

	if #candidates == 0 then
		return generateClub(division, matchday)
	end

	local index = (matchday - 1) % #candidates + 1
	return candidates[index]
end

--[[
	Publie la photo de l'equipe du joueur dans le pool de sa division.
	Appele apres chaque changement de composition.

	UpdateAsync et non SetAsync : deux serveurs peuvent publier en meme
	temps, et un SetAsync ecraserait l'entree de l'autre.
]]
function League.publish(player: Player)
	local data = Save.get(player)
	if data == nil then
		return
	end

	local entry = {
		id = `player:{player.UserId}`,
		name = data.clubName,
		ratings = Squad.ratings(player),
	}

	local division = data.division

	task.spawn(function()
		local ok, err = pcall(function()
			pool:UpdateAsync(`division_{division}`, function(current)
				local list = if typeof(current) == "table" then current else {}

				for index, existing in list do
					if typeof(existing) == "table" and existing.id == entry.id then
						list[index] = entry
						return list
					end
				end

				table.insert(list, entry)

				-- Le pool est borne : un DataStore a une limite de taille
				-- par cle, et une liste sans plafond finirait par la
				-- depasser et faire echouer toutes les ecritures.
				while #list > GameConfig.league.clubsPerDivision * 4 do
					table.remove(list, 1)
				end

				return list
			end)
		end)

		if not ok then
			warn(`[League] publication dans le pool impossible : {err}`)
		end
	end)
end

--[[
	Classement de la division du joueur. Les clubs generes recoivent des
	points deterministes derives de leur note : sans ca, le tableau serait
	vide et n'apprendrait rien au joueur.
]]
function League.standings(player: Player): { any }
	local data = Save.get(player)
	if data == nil then
		return {}
	end

	local rows = {}
	local clubs = League.clubs(data.division)
	local mine = `player:{player.UserId}`

	for _, club in clubs do
		if club.id == mine then
			continue
		end

		-- Points plausibles pour la force du club et le nombre de journees
		-- ecoulees, stables d'un affichage a l'autre.
		local rng = Random.new(club.id:len() * 31 + math.floor(club.ratings.overall))
		local strength = math.clamp((club.ratings.overall - 40) / 60, 0, 1)
		local won, drawn = 0, 0

		for _ = 1, data.matchday do
			local roll = rng:NextNumber()
			if roll < 0.25 + strength * 0.4 then
				won += 1
			elseif roll < 0.5 + strength * 0.3 then
				drawn += 1
			end
		end

		local lost = data.matchday - won - drawn
		table.insert(rows, {
			clubId = club.id,
			clubName = club.name,
			played = data.matchday,
			won = won,
			drawn = drawn,
			lost = lost,
			goalsFor = won * 2 + drawn,
			goalsAgainst = lost * 2 + drawn,
			points = won * GameConfig.league.pointsWin + drawn * GameConfig.league.pointsDraw,
			isPlayer = false,
		})
	end

	table.insert(rows, {
		clubId = mine,
		clubName = data.clubName,
		played = data.matchday,
		won = data.seasonWon,
		drawn = data.seasonDrawn,
		lost = data.seasonLost,
		goalsFor = data.seasonGoalsFor,
		goalsAgainst = data.seasonGoalsAgainst,
		points = data.seasonPoints,
		isPlayer = true,
	})

	table.sort(rows, function(left, right)
		if left.points ~= right.points then
			return left.points > right.points
		end
		local leftDiff = left.goalsFor - left.goalsAgainst
		local rightDiff = right.goalsFor - right.goalsAgainst
		if leftDiff ~= rightDiff then
			return leftDiff > rightDiff
		end
		return left.clubName < right.clubName
	end)

	return rows
end

--[[ Position du joueur dans son classement, 1 pour le premier. ]]
function League.playerRank(player: Player): number
	local mine = `player:{player.UserId}`
	for index, row in League.standings(player) do
		if row.clubId == mine then
			return index
		end
	end
	return GameConfig.league.clubsPerDivision
end

--[[
	Cloture la saison. Renvoie (montee, descente, nouvelle division).

	La division est bornee : monter depuis la division 1 ou descendre
	depuis la derniere ne fait rien plutot que de sortir de l'echelle.
]]
function League.endSeason(player: Player): (boolean, boolean, number)
	local data = Save.get(player)
	if data == nil then
		return false, false, GameConfig.league.startingDivision
	end

	local rank = League.playerRank(player)
	local config = GameConfig.league
	local division = data.division

	local promoted = rank <= config.promotedCount and division > config.highestDivision
	local relegated = rank > config.clubsPerDivision - config.relegatedCount
		and division < config.lowestDivision

	if promoted then
		division -= 1
	elseif relegated then
		division += 1
	end

	Save.update(player, function(profile)
		profile.division = division
		profile.matchday = 0
		profile.seasonPoints = 0
		profile.seasonWon = 0
		profile.seasonDrawn = 0
		profile.seasonLost = 0
		profile.seasonGoalsFor = 0
		profile.seasonGoalsAgainst = 0
	end)

	return promoted, relegated, division
end

return League
