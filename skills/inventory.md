# skill: inventory

## Rôle

Retient ce que le joueur possède : objets, quantités, équipement actif. Sert de
socle aux skills qui distribuent des récompenses ([[wheel]], [[daily-reward]])
et à celles qui les consomment.

## Dépend de

[[save]]

## Contrat d'entrée

```luau
export type ItemDef = {
	key: string,
	displayName: string,
	description: string,
	iconAsset: string?,
	-- Purement cosmetique cote UI, n'influence aucune logique.
	rarity: "common" | "uncommon" | "rare" | "epic" | "legendary",
	-- Empilable : une ligne d'inventaire avec un compteur.
	-- Non empilable : une ligne par exemplaire.
	stackable: boolean,
	maxStack: number?,
	-- Emplacement d'equipement. nil = objet non equipable.
	slot: string?,
	-- Effet applique quand l'objet est equipe.
	effect: { kind: string, value: number }?,
}

export type InventoryConfig = {
	items: { ItemDef },
	-- Nombre de lignes distinctes. nil = illimite.
	maxSlots: number?,
	-- Emplacements d'equipement disponibles, ex: { "hat", "tool" }.
	equipSlots: { string },
}
```

## Fichiers produits

| Chemin | Rôle |
|---|---|
| `src/shared/config/InventoryConfig.luau` | catalogue des objets |
| `src/server/systems/Inventory.luau` | add, remove, equip |
| `src/client/ui/InventoryUI.luau` | grille, détail, équipement |
| `tests/inventory.spec.luau` | tests de possession |

## API serveur

```luau
Inventory.add(player: Player, itemKey: string, count: number): boolean
Inventory.remove(player: Player, itemKey: string, count: number): boolean
Inventory.count(player: Player, itemKey: string): number
Inventory.equip(player: Player, itemKey: string): (boolean, string?)
Inventory.unequip(player: Player, slot: string): boolean
```

`add` renvoie `false` si l'inventaire est plein. L'appelant doit gérer ce cas :
une récompense de roue perdue parce que l'inventaire était plein sans que
personne ne le vérifie, c'est un ticket de support.

## Règles

**Une clé inconnue est refusée.** `add(player, "cle_inexistante", 1)` échoue et
logge. Sans ça, une faute de frappe dans une skill crée un objet fantôme que
l'UI ne sait pas afficher.

**Vérifier la place avant d'ajouter.** Contrôler `maxSlots` et `maxStack`
d'abord, écrire ensuite. Un ajout partiel (3 sur 5) doit être explicite dans la
valeur de retour, jamais silencieux.

**`remove` ne descend jamais sous zéro.** Retirer plus que possédé échoue en
bloc, sans retrait partiel.

**Un slot d'équipement contient au plus un objet.** Équiper sur un slot occupé
déséquipe l'ancien dans la même opération.

**L'équipement est validé à la possession.** Équiper un objet absent de
l'inventaire est refusé — un client modifié enverra cette requête.

**Le client n'écrit rien.** Il demande `equip`, le serveur vérifie et réplique.

## Tests attendus

- `add` puis `count` renvoie la quantité attendue
- un objet empilable dépasse `maxStack` en créant une seconde pile, ou échoue
  si `maxSlots` est atteint
- `add` sur un inventaire plein renvoie `false` sans rien modifier
- `remove` au-delà du possédé échoue et ne retire rien
- une clé inconnue est refusée
- équiper sur un slot occupé déséquipe le précédent
- équiper un objet non possédé est refusé
- l'inventaire et l'équipement survivent à une reconnexion
