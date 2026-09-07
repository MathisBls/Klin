# skill: shop

## Rôle

Boutique du jeu : améliorations payées en monnaie interne, Developer Products
payés en Robux (consommables), Game Passes payés en Robux (permanents). C'est la
skill qui touche à l'argent réel, donc celle où une erreur coûte cher.

## Dépend de

[[save]], [[currency]]

## Contrat d'entrée

```luau
export type Upgrade = {
	key: string,
	displayName: string,
	description: string,
	iconAsset: string?,
	currency: string,          -- cle d'une monnaie de [[currency]]
	basePrice: number,
	-- Prix du niveau n = basePrice * (priceGrowth ^ n). 1.0 = prix fixe.
	priceGrowth: number,
	maxLevel: number?,         -- nil = illimite
	-- Effet applique par niveau. Interprete par le systeme concerne.
	effect: { kind: string, valuePerLevel: number },
}

export type DevProduct = {
	key: string,               -- cle dans Config.developerProducts
	displayName: string,
	description: string,
	priceRobux: number,
	grants: { { currency: string, amount: number } },
}

export type GamePass = {
	key: string,               -- cle dans Config.gamePasses
	displayName: string,
	description: string,
	priceRobux: number,
	effect: { kind: string, value: number },
}

export type ShopConfig = {
	upgrades: { Upgrade },
	developerProducts: { DevProduct },
	gamePasses: { GamePass },
}
```

Les IDs Roblox ne figurent pas ici. Ils vivent dans `Config.developerProducts`
et `Config.gamePasses`, générés par `make products`. La skill référence des clés
logiques, jamais des nombres.

## Fichiers produits

| Chemin | Rôle |
|---|---|
| `src/shared/config/ShopConfig.luau` | catalogue, prix, effets |
| `src/server/systems/Shop.luau` | achats en monnaie interne |
| `src/server/systems/Receipts.luau` | `ProcessReceipt`, Game Passes |
| `src/client/ui/ShopUI.luau` | panneau boutique, prompts d'achat |
| `tests/shop.spec.luau` | tests d'achat et d'idempotence |

Ce catalogue alimente aussi `assets/products.json`, consommé par
`make products`.

## API serveur

```luau
Shop.getLevel(player: Player, upgradeKey: string): number
Shop.getPrice(player: Player, upgradeKey: string): number
Shop.buyUpgrade(player: Player, upgradeKey: string): (boolean, string?)
Shop.ownsPass(player: Player, passKey: string): boolean
```

## Règles

**`ProcessReceipt` doit être idempotent.** Roblox rappelle le callback tant
qu'il n'a pas reçu `PurchaseGranted`. Stocker chaque `PurchaseId` traité dans le
profil et renvoyer `PurchaseGranted` immédiatement si l'ID est déjà connu. Sans
ça, un joueur reçoit sa récompense plusieurs fois.

**Accorder avant de confirmer.** Écrire la récompense dans le profil **et
attendre que le save soit passé** avant de renvoyer `PurchaseGranted`. Confirmer
d'abord, c'est risquer un crash serveur entre les deux : le joueur a payé et n'a
rien.

**Un seul `ProcessReceipt` dans tout le jeu.** C'est un callback unique sur
`MarketplaceService`. Deux systèmes qui l'assignent, et le second écrase le
premier silencieusement.

**Renvoyer `NotProcessedYet` en cas de doute.** Si le profil n'est pas chargé ou
qu'une écriture échoue, ne pas accorder. Roblox rappellera.

**Le prix est calculé serveur.** Le client affiche un prix, le serveur le
recalcule au moment de l'achat. Un client modifié ne doit pas pouvoir acheter au
prix du niveau 1 une amélioration niveau 20.

**Vérifier `maxLevel` avant de débiter,** pas après.

**Les Game Passes se vérifient au join et à l'achat.**
`UserOwnsGamePassAsync` peut échouer réseau : envelopper dans un `pcall` et
réessayer, ne pas conclure que le joueur ne possède rien.

## Tests attendus

- acheter une amélioration débite le prix exact et incrémente le niveau
- acheter sans les fonds échoue et ne débite rien
- le prix suit `basePrice * priceGrowth ^ niveau`
- `maxLevel` bloque l'achat suivant
- **le même `PurchaseId` traité deux fois n'accorde la récompense qu'une fois**
- un `ProcessReceipt` sur un profil non chargé renvoie `NotProcessedYet`
- un Game Pass possédé est détecté après reconnexion
- le niveau des améliorations survit à une reconnexion
