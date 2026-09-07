# skill: daily-reward

## Rôle

Récompense le joueur qui revient chaque jour, avec une série qui monte. C'est le
levier de rétention J1/J7 le plus direct — exactement ce que Roblox mesure pour
classer un jeu.

## Dépend de

[[save]], [[currency]], [[inventory]]

## Contrat d'entrée

```luau
export type DailyEntry = {
	day: number,               -- 1..n, position dans la serie
	displayName: string,
	iconAsset: string?,
	reward:
		{ kind: "currency", currency: string, amount: number }
		| { kind: "item", itemKey: string, count: number },
}

export type DailyRewardConfig = {
	days: { DailyEntry },
	-- Ce qui se passe apres le dernier jour :
	--   "loop"   : on repart au jour 1
	--   "repeat" : on redonne le dernier jour indefiniment
	afterLast: "loop" | "repeat",
	-- Heures d'absence tolerees avant remise a zero de la serie.
	-- 48 permet de rater une journee sans tout perdre.
	graceHours: number,
	-- Fuseau de reference pour le passage de jour. "UTC" par defaut.
	-- Un fuseau local rendrait la serie exploitable par changement d'heure.
	timezone: string,
}
```

## Fichiers produits

| Chemin | Rôle |
|---|---|
| `src/shared/config/DailyRewardConfig.luau` | série, grâce, fuseau |
| `src/server/systems/DailyReward.luau` | calcul du jour, attribution |
| `src/client/ui/DailyRewardUI.luau` | calendrier, bouton, aperçu |
| `tests/daily-reward.spec.luau` | tests de série et de bascule |

## API serveur

```luau
DailyReward.getState(player: Player): { day: number, claimable: boolean, nextAt: number }
DailyReward.claim(player: Player): (boolean, DailyEntry?, string?)
```

## Règles

**Compter en jours calendaires UTC, pas en heures écoulées.** « 24 h depuis le
dernier retrait » décale la récompense d'un peu chaque jour et finit par tomber
en pleine nuit. Comparer des numéros de jour UTC.

**Le fuseau vient de la config, pas du client.** Un client qui annonce son
fuseau peut le changer pour réclamer plusieurs fois.

**Une seule récompense par jour, garantie serveur.** Stocker le jour du dernier
retrait dans le profil et comparer avant d'accorder. Deux clics rapides ne
doivent pas donner deux récompenses.

**Écrire avant de répondre.** Marquer le jour comme réclamé, puis annoncer la
récompense. L'ordre inverse permet de récupérer deux fois en coupant la
connexion au bon moment.

**Grâce explicite.** Au-delà de `graceHours` sans connexion, la série repart à
1. En deçà, elle continue. Le joueur doit voir ce compte à rebours, sinon la
remise à zéro est vécue comme un bug.

**`afterLast` est obligatoire.** Une série sans suite définie bloque le joueur
au dernier jour sans rien lui donner.

## Tests attendus

- premier retrait donne le jour 1
- deuxième retrait le même jour UTC est refusé
- retrait le lendemain donne le jour 2
- une absence sous `graceHours` conserve la série
- une absence au-delà de `graceHours` ramène au jour 1
- `afterLast = "loop"` repart au jour 1 après le dernier
- `afterLast = "repeat"` redonne le dernier jour
- un changement d'heure locale du client ne change rien au résultat
- deux `claim` simultanés n'accordent qu'une récompense
