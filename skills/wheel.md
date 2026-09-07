# skill: wheel

## Rôle

Roue de récompenses à rareté pondérée. Donne au joueur une raison de revenir et
un moment de tension gratuit. C'est aussi le point d'entrée naturel d'un
Developer Product « tour supplémentaire ».

## Dépend de

[[save]], [[currency]], [[inventory]]

## Contrat d'entrée

```luau
export type Prize = {
	key: string,
	displayName: string,
	iconAsset: string?,
	-- Poids relatif, pas un pourcentage. Un poids de 10 sur un total de
	-- 200 donne 5 %. Ajouter un lot ne demande donc pas de rebalancer
	-- les autres.
	weight: number,
	reward:
		{ kind: "currency", currency: string, amount: number }
		| { kind: "item", itemKey: string, count: number }
		| { kind: "multiplier", currency: string, value: number, duration: number },
}

export type WheelConfig = {
	prizes: { Prize },
	-- Delai entre deux tours gratuits, en secondes.
	cooldownSeconds: number,
	-- Tour payant en monnaie interne. nil = pas de tour payant.
	paidSpin: { currency: string, price: number }?,
	-- Cle de Developer Product pour un tour immediat. nil = desactive.
	productKey: string?,
	-- Duree de l'animation cote client, en secondes.
	spinDuration: number,
}
```

## Fichiers produits

| Chemin | Rôle |
|---|---|
| `src/shared/config/WheelConfig.luau` | lots, poids, cooldown |
| `src/server/systems/Wheel.luau` | tirage, cooldown, attribution |
| `src/client/ui/WheelUI.luau` | roue, rotation, révélation |
| `tests/wheel.spec.luau` | tests de tirage et de cooldown |

## API serveur

```luau
Wheel.canSpin(player: Player): (boolean, number)   -- false + secondes restantes
Wheel.spin(player: Player, paid: boolean): (boolean, Prize?, string?)
```

## Règles

**Le tirage est serveur.** Le client anime une roue qui s'arrête sur un résultat
**déjà décidé**. Jamais l'inverse. Un client qui choisit son lot et l'annonce au
serveur, c'est une roue qui donne toujours le légendaire.

**Le cooldown est absolu, pas relatif.** Stocker l'horodatage du prochain tour
(`os.time() + cooldown`), pas un compteur décrémenté. Un compteur se remet à
zéro quand le joueur se déconnecte.

**Le cooldown est vérifié serveur à chaque tour.** Le client affiche un timer de
confort ; il ne fait pas autorité.

**Débiter avant de tirer.** Pour un tour payant : vérifier les fonds, débiter,
puis tirer. Tirer d'abord permettrait de rejouer un mauvais résultat en coupant
la connexion.

**Attribuer avant d'annoncer.** Écrire la récompense, puis envoyer le résultat
au client. Si l'attribution échoue (inventaire plein), le joueur doit le savoir
avant l'animation, pas après.

**Somme des poids > 0.** Une config où tous les poids valent zéro doit échouer
à la génération, pas à l'exécution.

**Un tirage, une source d'aléa serveur.** `Random.new()` par appel, jamais
`math.random` global partagé entre joueurs.

## Tests attendus

- sur 10 000 tirages, la fréquence de chaque lot est à ±2 % de son poids
  relatif
- un tour hors cooldown est refusé et ne donne rien
- le cooldown survit à une déconnexion / reconnexion
- un tour payant sans les fonds est refusé et ne débite rien
- un tour payant avec les fonds débite exactement une fois
- une récompense `item` sur un inventaire plein échoue proprement, avec un
  message, sans consommer le tour
- une config dont les poids somment à zéro est rejetée
