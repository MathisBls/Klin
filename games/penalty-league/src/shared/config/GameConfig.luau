--!strict
--[[
	Toutes les valeurs chiffrees du jeu, au meme endroit.
	Reference : games/penalty-league/spec.md

	Aucun ID Roblox ici : ils vivent dans Config.luau, genere par
	`make assets` et `make products`.
]]

export type Position = "GK" | "DEF" | "MID" | "ATT" | "SUB"

export type Rarity = {
	key: string,
	displayName: string,
	minRating: number,
	maxRating: number,
	-- Poids relatif. La somme fait 100 pour se lire en pourcentage direct.
	weight: number,
	color: Color3,
}

local GameConfig = {
	slug = "penalty-league",

	currency = {
		key = "credits",
		displayName = "Credits",
		startingAmount = 500,
		abbreviateAbove = 10000,
	},

	-- Les cinq emplacements de la composition. L'ordre est celui de l'UI.
	positions = { "GK", "DEF", "MID", "ATT", "SUB" } :: { Position },

	positionNames = {
		GK = "Gardien",
		DEF = "Defense",
		MID = "Milieu",
		ATT = "Attaque",
		SUB = "Remplacant",
	} :: { [string]: string },

	rewards = {
		win = 120,
		draw = 60,
		loss = 30,
		penaltyScored = 15,
		perPlaceGained = 50,
		promotion = 500,
	},

	packs = {
		price = 250,
		cardsPerPack = 3,
		-- Une carte deja possedee est revendue a cette fraction de sa
		-- valeur : aucune ouverture ne doit etre vide de sens.
		duplicateRefund = 0.40,
	},

	rarities = {
		{
			key = "BRONZE",
			displayName = "Bronze",
			minRating = 40,
			maxRating = 59,
			weight = 55,
			color = Color3.fromRGB(150, 106, 68),
		},
		{
			key = "SILVER",
			displayName = "Argent",
			minRating = 60,
			maxRating = 74,
			weight = 28,
			color = Color3.fromRGB(178, 184, 196),
		},
		{
			key = "GOLD",
			displayName = "Or",
			minRating = 75,
			maxRating = 86,
			weight = 13,
			color = Color3.fromRGB(226, 182, 68),
		},
		{
			key = "ELITE",
			displayName = "Elite",
			minRating = 87,
			maxRating = 94,
			weight = 3.5,
			color = Color3.fromRGB(120, 96, 214),
		},
		{
			key = "LEGEND",
			displayName = "Legende",
			minRating = 95,
			maxRating = 99,
			weight = 0.5,
			color = Color3.fromRGB(232, 96, 64),
		},
	} :: { Rarity },

	match = {
		-- Douze temps forts sur 90 minutes : assez pour raconter un match,
		-- assez peu pour que la feuille se lise en une minute.
		eventCount = 12,
		-- Occasion : p = chanceFactor * (Attaque / Defense) ^ attackExponent.
		--
		-- Le rapport A/D et non A/(A+D) : la seconde forme est trop plate,
		-- elle ne creusait que 11 % d'ecart entre une equipe a 88 et une a
		-- 70, si bien que la composition ne changeait presque rien.
		--
		-- Ces quatre nombres ont ete regles par simulation (8 000 matchs
		-- par jeu de parametres) pour viser des chiffres de vrai football :
		--   outsider 50 contre 70 : 12 % de victoires
		--   equilibre  70 contre 70 : 37 %
		--   favori     88 contre 70 : 60 %
		--   matchs nuls : 25 %, buts par match : 2,6
		-- Les toucher sans refaire tourner la simulation casse l'equilibre.
		chanceFactor = 0.44,
		attackExponent = 1.0,
		-- Une occasion sur deux finit au fond.
		goalChance = 0.50,
		-- Exposant de la possession. A 1, l'ecart de milieu se traduit
		-- lineairement ; au-dela, les gros milieux ecrasent tout.
		possessionExponent = 1.0,
		-- Probabilite qu'une occasion devienne un penalty.
		penaltyChance = 0.08,
		-- Duree d'affichage d'un evenement cote client, en secondes.
		eventDelay = 0.55,
	},

	penalty = {
		-- Le tireur dispose de ce delai pour valider visee puis puissance.
		aimSeconds = 5,
		-- Arret : base + bonus de note du gardien - bonus de difficulte.
		--
		-- Ces quatre nombres creent LE choix du jeu. Regles pour que le
		-- meilleur tir depende du gardien en face :
		--   gardien 45 : place 84 % de buts, risque 74 %  -> placer
		--   gardien 70 : place 75 %, risque 74 %          -> a peu pres egal
		--   gardien 95 : place 66 %, risque 74 %          -> prendre le risque
		--
		-- Un reglage precedent rendait le tir place meilleur contre tous les
		-- gardiens : la visee et la puissance n'etaient alors qu'un faux
		-- choix. Ne pas y toucher sans refaire tourner la comparaison.
		saveBase = 0.28,
		savePerRatingPoint = 0.004,
		saveDifficultyBonus = 0.44,
		-- Hors cadre : croit avec le carre de la difficulte.
		missBase = 0.05,
		missDifficultyFactor = 0.22,
	},

	league = {
		-- Division 5 est le point d'entree, 1 le sommet.
		lowestDivision = 5,
		highestDivision = 1,
		startingDivision = 5,
		matchdaysPerSeason = 10,
		clubsPerDivision = 12,
		promotedCount = 3,
		relegatedCount = 3,
		pointsWin = 3,
		pointsDraw = 1,
	},

	products = {
		PACK_GOLD = { displayName = "Pochette Or", guaranteedRarity = "GOLD" },
		CREDITS_LARGE = { displayName = "3 000 credits", grantCredits = 3000 },
	},

	gamePasses = {
		-- Multiplicateur applique a tous les gains de credits.
		SEASON_PASS = { displayName = "Pass Saison", creditMultiplier = 1.5 },
	},

	autosaveIntervalSeconds = 300,
}

return table.freeze(GameConfig)
