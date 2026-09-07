# skill: leaderboard

## Rôle

Affiche qui est devant. Le classement en jeu (`leaderstats`) donne une
comparaison immédiate ; le classement global via OrderedDataStore donne un
objectif à long terme. Les deux nourrissent le temps de session.

## Dépend de

[[save]], [[currency]]

## Contrat d'entrée

```luau
export type BoardDef = {
	key: string,
	displayName: string,
	-- Source de la valeur : une monnaie de [[currency]], ou une
	-- statistique du profil.
	source: { kind: "currency", currency: string } | { kind: "stat", field: string },
	-- Classement global persistant en plus du leaderstats.
	global: boolean,
	-- Nombre d'entrees affichees sur le panneau global.
	topCount: number,
	-- Delai de rafraichissement du global, en secondes. Minimum 60 :
	-- OrderedDataStore a des quotas serres.
	refreshSeconds: number,
}

export type LeaderboardConfig = {
	boards: { BoardDef },
	-- Affiche la colonne dans le menu Roblox (leaderstats).
	showInPlayerList: boolean,
}
```

## Fichiers produits

| Chemin | Rôle |
|---|---|
| `src/shared/config/LeaderboardConfig.luau` | définition des classements |
| `src/server/systems/Leaderboard.luau` | leaderstats, OrderedDataStore |
| `src/client/ui/LeaderboardUI.luau` | panneau du top global |
| `tests/leaderboard.spec.luau` | tests de tri et de quota |

## API serveur

```luau
Leaderboard.setValue(player: Player, boardKey: string, value: number)
Leaderboard.getTop(boardKey: string): { { name: string, value: number } }
```

## Règles

**`leaderstats` est un miroir, pas une source.** La valeur vraie est dans le
profil. `leaderstats` est un `IntValue` reconstruit à partir d'elle. Lire
`leaderstats` pour décider quoi que ce soit, c'est lire une donnée qu'un
exploit peut avoir modifiée localement.

**Les quotas OrderedDataStore sont serrés.** Écrire à chaque changement de
solde épuise le budget en quelques minutes. Écrire par intervalle
(`refreshSeconds`) et au départ du joueur, pas à chaque gain.

**Refuser `refreshSeconds` sous 60.** C'est une erreur de config, pas une
préférence.

**Un seul fetch du top pour tout le serveur.** Pas un par joueur : une lecture
partagée, mise en cache, répliquée. Vingt joueurs ne doivent pas déclencher
vingt requêtes.

**`OrderedDataStore` n'accepte que des entiers positifs.** Arrondir et
plancher à zéro avant d'écrire. Une valeur négative ou décimale lève une erreur
qui casse le système entier.

**Envelopper chaque appel dans un `pcall`.** Un DataStore indisponible ne doit
pas empêcher de jouer — le classement s'affiche vide, le jeu continue.

**Ne rien écrire pour un profil non chargé.** Sinon un joueur qui part vite
inscrit un zéro à la place de son vrai score.

## Tests attendus

- `setValue` met à jour `leaderstats` du joueur
- le top global est trié par valeur décroissante
- `topCount` limite bien le nombre d'entrées
- une valeur décimale est arrondie avant écriture
- une valeur négative est ramenée à zéro
- une config avec `refreshSeconds` sous 60 est rejetée
- un échec DataStore est capturé, le jeu continue
- vingt joueurs connectés ne provoquent qu'une lecture du top par intervalle
