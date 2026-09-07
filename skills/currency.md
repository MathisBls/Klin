# skill: currency

## Rôle

Gère les monnaies du jeu : gains, dépenses, plafonds, multiplicateurs. Tout ce
qui coûte ou rapporte passe par ici, ce qui donne un seul endroit où auditer
l'économie.

## Dépend de

[[save]]

## Contrat d'entrée

```luau
export type CurrencyDef = {
	-- Cle interne, stable. Sert de champ dans le profil.
	key: string,
	-- Nom affiche au joueur. Peut changer sans rien casser.
	displayName: string,
	-- Icone, resolue par [[assets]].
	iconAsset: string?,
	-- Montant a la premiere connexion.
	startingAmount: number,
	-- Plafond dur. nil = pas de plafond.
	maxAmount: number?,
	-- Abrege les grands nombres a l'affichage (1 500 -> 1.5K).
	abbreviate: boolean,
}

export type CurrencyConfig = {
	currencies: { CurrencyDef },
}
```

## Fichiers produits

| Chemin | Rôle |
|---|---|
| `src/shared/config/CurrencyConfig.luau` | définition des monnaies |
| `src/shared/Format.luau` | abréviation des grands nombres |
| `src/server/systems/Currency.luau` | add, spend, get, multiplicateurs |
| `src/client/ui/CurrencyDisplay.luau` | compteur, animation de gain |
| `tests/currency.spec.luau` | tests d'économie |

## API serveur

```luau
Currency.get(player: Player, key: string): number
Currency.add(player: Player, key: string, amount: number): number   -- renvoie le nouveau solde
Currency.spend(player: Player, key: string, amount: number): boolean -- false si insuffisant
Currency.setMultiplier(player: Player, key: string, source: string, value: number)
```

`setMultiplier` prend une `source` (`"gamepass2x"`, `"eventWeekend"`) plutôt
qu'un nombre global : deux bonus simultanés doivent pouvoir coexister et se
retirer indépendamment.

## Règles

**Le client n'ajoute jamais de monnaie.** Il envoie une intention (« j'ai
cliqué »), le serveur décide du gain. Un `RemoteEvent` qui transporte un montant
est une faille.

**`spend` est atomique.** Vérifier le solde et le débiter dans la même
opération. Deux achats envoyés en même temps ne doivent pas pouvoir passer tous
les deux avec un solde qui n'en couvre qu'un.

**Refuser les montants invalides.** Négatif, `NaN`, `inf`, non entier : rejeter
et logger. `add(player, key, -1000)` ne doit pas être un moyen de voler.

**Plafonner à `maxAmount`.** Silencieusement, sans erreur, mais le signaler au
client pour qu'il puisse afficher « maximum atteint ».

**Répliquer par valeur, pas par delta.** Envoyer le nouveau solde au client, pas
« +50 ». Un paquet perdu ne doit pas désynchroniser l'affichage.

## Tests attendus

- `add` puis `get` renvoie la somme attendue
- `spend` au-delà du solde renvoie `false` et ne débite rien
- `spend` du montant exact réussit et laisse le solde à zéro
- un montant négatif ou `NaN` est refusé
- `maxAmount` plafonne sans erreur
- deux multiplicateurs de sources différentes se cumulent, retirer l'un garde
  l'autre
- le solde survit à une déconnexion / reconnexion (via [[save]])
