# skill: save

## Rôle

Persiste la progression du joueur entre les sessions, sans perte ni duplication.
C'est la fondation : toute skill qui retient quelque chose passe par elle.

## Dépend de

Rien. C'est la racine de l'arbre.

## Contrat d'entrée

```luau
export type SaveConfig = {
	-- Nom du DataStore. Changer cette valeur repart de zero pour tous
	-- les joueurs : ne le faire qu'en connaissance de cause.
	storeName: string,

	-- Profil d'un joueur qui se connecte pour la premiere fois.
	-- Toute cle ajoutee ici plus tard doit avoir une valeur par defaut,
	-- sinon les anciens profils la liront en nil.
	template: { [string]: any },

	-- Intervalle d'autosave en secondes. 300 par defaut.
	autosaveInterval: number,
}
```

## Fichiers produits

| Chemin | Rôle |
|---|---|
| `src/shared/config/SaveConfig.luau` | `storeName`, template, intervalle |
| `src/shared/types/Profile.luau` | type du profil, dérivé du template |
| `src/server/systems/Save.luau` | chargement, session lock, release |
| `tests/save.spec.luau` | tests de chargement et de migration |

Dépendance Wally à ajouter : `ProfileStore`.

## API serveur

```luau
Save.get(player: Player): Profile?          -- nil si pas encore charge
Save.await(player: Player): Profile?        -- attend le chargement, nil si echec
Save.update(player: Player, fn: (Profile) -> ())  -- mutation atomique
```

`Save.update` est le seul point d'écriture. Aucun autre système ne modifie un
profil directement — sinon deux systèmes peuvent écrire en même temps et l'un
écrase l'autre.

## Règles

**Session lock obligatoire.** ProfileStore le fournit : un profil ne peut être
ouvert que par un serveur à la fois. Sans lui, un joueur qui rejoint deux
serveurs duplique ses objets.

**Release au départ.** `Players.PlayerRemoving` libère le profil. Un profil non
libéré bloque le joueur pendant plusieurs minutes à sa prochaine connexion.

**Le joueur peut partir avant la fin du chargement.** Après chaque `await`,
revérifier que le joueur est toujours là avant d'utiliser le profil.

**Échec de chargement = kick.** Si ProfileStore ne rend pas de profil, expulser
le joueur avec un message. Le laisser jouer sur un profil vide lui fait perdre
sa progression au prochain save.

**Migration par valeurs par défaut.** Une nouvelle clé du template est absente
des anciens profils. Toujours lire avec un repli, jamais supposer la présence.

## Tests attendus

- un profil neuf contient toutes les clés du template
- une clé ajoutée au template après coup est lisible sur un profil ancien
- `Save.update` appliqué deux fois de suite conserve les deux mutations
- le départ du joueur libère le profil
- un joueur qui part pendant le chargement ne provoque pas d'erreur
