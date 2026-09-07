# Skills de mécaniques

Une skill décrit **une mécanique réutilisable** : ce qu'elle fait, ce qu'elle
attend en configuration, les fichiers qu'elle produit, et les tests qui prouvent
qu'elle marche. `make generate` lit la spec du jeu, choisit les skills
nécessaires et les applique.

Une skill n'est pas du code. C'est un contrat. Le code est généré à partir
d'elle, pour ce jeu-là, avec cette config-là.

## Format

Chaque fichier `<nom>.md` contient, dans cet ordre :

| Section | Contenu |
|---|---|
| **Rôle** | Ce que la mécanique apporte au joueur, en deux phrases |
| **Dépend de** | Les autres skills requises, en lien wiki à double crochet |
| **Contrat d'entrée** | Le type Luau de la config que la skill consomme |
| **Fichiers produits** | Chemin exact et rôle de chaque fichier généré |
| **API serveur** | Les fonctions publiques exposées aux autres systèmes |
| **Règles** | Les invariants à ne jamais violer |
| **Tests attendus** | Ce que `make test` doit vérifier |

## Conventions communes à toutes les skills

**Arborescence.** Chaque skill écrit dans des emplacements prévisibles :

```
src/shared/config/<Nom>Config.luau    config typée, valeurs du jeu
src/shared/Remotes.luau                remotes centralisés (une seule fois)
src/server/systems/<Nom>.luau          logique serveur
src/client/ui/<Nom>.luau               interface et feedback
tests/<nom>.spec.luau                  tests de la mécanique
```

**Autorité serveur.** Le client ne calcule jamais une valeur qui compte. Il
demande, le serveur décide, le serveur réplique. Une skill qui laisse le client
décider d'un gain de monnaie est une skill fausse.

**Validation des remotes.** Tout handler serveur valide ses arguments avant de
les utiliser : type, bornes, appartenance au joueur. Un `RemoteEvent` est une
entrée publique, un joueur peut y envoyer n'importe quoi.

**Pas d'écriture DataStore directe.** Toute persistance passe par [[save]].

**Typage strict.** `--!strict` en tête de chaque fichier, StyLua et Selene
doivent passer.

**Budget serveur.** Pas de boucle par frame côté serveur. Les systèmes qui ont
besoin d'un tick utilisent un intervalle explicite et le documentent.

## Ordre de dépendance

```
save ──┬── currency ──┬── shop
       │              ├── wheel
       │              ├── daily-reward
       │              └── leaderboard
       └── inventory

map-gen   (indépendant)
assets    (indépendant, étape de pipeline)
```

Générer dans cet ordre : une skill ne peut pas être appliquée avant celles dont
elle dépend.

## Liste

- [[save]] — persistance ProfileStore, session lock
- [[currency]] — monnaies, gains, dépenses
- [[inventory]] — objets possédés, équipement
- [[shop]] — Developer Products, Game Passes, améliorations
- [[wheel]] — roue de récompenses à rareté pondérée
- [[daily-reward]] — récompense quotidienne, série
- [[leaderboard]] — classements en jeu et OrderedDataStore
- [[map-gen]] — génération de map depuis une description
- [[assets]] — résolution des assets du manifest
