# Générateur de jeux Roblox

## Objectif
Pipeline 100 % automatisé : un prompt décrit un jeu, le repo produit un projet Roblox complet (Luau + assets + monétisation), le builde, le teste et le publie via Open Cloud. Aucune étape manuelle dans Studio en régime normal ; Studio sert uniquement au debug visuel.

## Stack imposée
- Rokit pour la toolchain (`rokit.toml`) : rojo, wally, stylua, selene, run-in-roblox
- Rojo : `default.project.json` mappe `src/` vers le DataModel
- Wally pour les dépendances (Promise, Knit ou équivalent léger, ProfileStore pour les sauvegardes)
- Scripts pipeline en Python 3 dans `tools/` (build, upload assets, créer developer products, publier, lire analytics)
- Secrets uniquement via `.env` (`ROBLOX_API_KEY`, `ROBLOX_UNIVERSE_ID`, `ROBLOX_PLACE_ID`). Jamais dans le code ni les commits.

## Arborescence
```
src/
  server/      ServerScriptService (systèmes serveur)
  client/      StarterPlayerScripts (UI, inputs, feedback)
  shared/      ReplicatedStorage (config, types, remotes, données de jeu)
  workspace/   map générée
assets/        manifest.json : assets locaux à uploader + IDs Creator Store à insérer
games/<slug>/  spec.md du jeu (boucle, économie, map, monétisation) + brief visuel
tools/         scripts pipeline Open Cloud
skills/        une skill par mécanique réutilisable
```

## Règles Luau
- Strict typing (`--!strict`) partout, StyLua + Selene doivent passer
- Toute logique d'économie, d'achat et de sauvegarde est côté serveur. Le client ne fait que demander.
- Remotes typés et centralisés dans `shared/Remotes.luau`, validation systématique des arguments côté serveur
- Sauvegardes via ProfileStore, session lock, jamais d'écriture DataStore directe
- Achats : `MarketplaceService.ProcessReceipt` idempotent, ID de reçu stocké dans le profil
- Aucun `wait()` legacy, pas de `while true do` sans budget, pas de boucle par frame côté serveur

## Skills de mécaniques (à créer dans `skills/`, une par fichier)
Chaque skill = description, contrat d'entrée (config), fichiers produits, tests attendus.
Premières skills : `shop` (Developer Products + Game Passes), `wheel` (roue de récompenses avec rareté pondérée), `inventory`, `save` (ProfileStore), `currency`, `daily-reward`, `leaderboard`, `map-gen` (map simple depuis une description), `assets` (recherche Creator Store ou upload local).

## Pipeline (chaque commande doit exister dans `Makefile` ou `justfile`)
1. `spec` : à partir du prompt, écrire `games/<slug>/spec.md` (genre, boucle 30 s / 5 min / 1 h, économie chiffrée, monétisation, map, ambiance). Me le montrer avant de générer.
2. `generate` : produire le code depuis la spec en appelant les skills
3. `assets` : résoudre le manifest (insertion par ID ou upload via Open Cloud Assets API), injecter les IDs dans `shared/Config.luau`
4. `products` : créer ou mettre à jour les Developer Products et Game Passes via Open Cloud, stocker leurs IDs dans la config
5. `build` : `rojo build -o build/game.rbxl`
6. `test` : lint + `run-in-roblox` sur une suite de tests (jeu démarre sans erreur, achats simulés, sauvegarde ok)
7. `publish` : POST Open Cloud `universes/{universeId}/places/{placeId}/versions?versionType=Published`
8. `analytics` : lire rétention, sessions, revenus et écrire un rapport dans `reports/`

## Ce que Roblox mesure (à garder en tête dans chaque design)
Temps de session, rétention J1/J7, taux de rejeu, monétisation par joueur. Le premier écran doit donner quelque chose à faire en moins de 10 secondes. Onboarding sans texte long.

## Façon de travailler
- Commencer par un plan court, le valider avec moi, puis exécuter
- Commits petits et atomiques, messages clairs
- Quand un endpoint Open Cloud est incertain, aller lire la doc officielle (create.roblox.com/docs/cloud) plutôt que deviner
- Ne jamais inventer un ID d'asset : soit résolu par l'API, soit demandé
- Répondre en français, sans emojis

## Stratégie multi-jeux

Le repo ne produit pas un jeu, il produit une série de jeux. Deux forces s'y
opposent et doivent être tenues ensemble : **varier assez pour apprendre
quelque chose de neuf**, et **garder assez pour ne pas réapprendre ce qu'on
sait déjà**.

### 1. Chaque jeu est une vraie variation

Un nouveau jeu doit différer des précédents sur les trois axes suivants :

- **Mécanique principale** : le verbe que le joueur répète. Cliquer, empiler,
  esquiver, fusionner, courir, deviner, construire.
- **Thème** : l'univers et sa lecture visuelle immédiate.
- **Hook des 10 premières secondes** : ce qui se passe à l'écran avant que le
  joueur ait décidé de rester.

Reprendre la même boucle avec un skin différent est interdit. Un simulateur de
clic renommé en simulateur de minage n'est pas un nouveau jeu : c'est le même
jeu, et il n'apprend rien de plus que le précédent.

`games/REGISTRY.md` liste chaque jeu sorti avec sa mécanique, son thème, son
hook et sa date de sortie. **Le consulter est obligatoire avant d'écrire une
spec.** Si la mécanique ou le hook envisagé y figure déjà, changer d'idée avant
d'écrire, pas après.

### 2. Varier ne veut pas dire repartir de zéro

Ce qui a fait ses preuves est conservé et réutilisé tel quel :

- une skill dont le code généré n'a produit aucun bug
- un onboarding qui a donné une bonne rétention J1
- un shop qui a converti
- une roue qui a fait revenir les joueurs

Ces éléments forment la **base commune**. Le jeu suivant hérite de tout ça sans
discussion, et ne diffère que sur la mécanique, le thème et le hook.

`games/PLAYBOOK.md` tient deux listes : ce qui marche et ce qui a échoué.
Chaque entrée porte **le chiffre qui la prouve**. « L'onboarding sans texte
marche bien » n'est pas une entrée de playbook ; « onboarding sans texte,
rétention J1 de 31 % contre 22 % avec tutoriel » en est une. Une conviction
sans chiffre reste une hypothèse et se note comme telle.

Le playbook s'applique à chaque nouveau jeu. On ne redébat pas d'un point
tranché par les chiffres.

### 3. Le rapport analytics alimente la spec suivante

Après publication, `make analytics --slug <slug>` écrit `reports/<slug>.md` :
rétention J1 et J7, temps de session moyen, taux de rejeu, revenus.

Ce rapport est une **entrée obligatoire** de la spec du jeu suivant. Chaque
`spec.md` contient une section « Leçons des jeux précédents » qui dit
explicitement :

- **ce qui est conservé**, et le chiffre qui le justifie
- **ce qui est abandonné**, et le chiffre qui le condamne
- **ce que ce jeu fait différemment en conséquence**

Une spec sans cette section est incomplète. Un jeu lancé sans avoir lu le
rapport du précédent répète ses erreurs.

Tant qu'un jeu a moins de 7 jours, ses chiffres de rétention J7 ne sont pas
lisibles : le noter dans la section plutôt que d'inventer une conclusion.

### 4. Un signal fort déclenche l'itération

Si un jeu montre une rétention J1 nettement au-dessus des autres, il passe en
**mode itération** : on améliore celui-là au lieu d'en créer un nouveau.

Créer un jeu de plus quand on en tient un qui marche, c'est abandonner le seul
actif qui a de la valeur. La série existe pour trouver ce signal, pas pour
faire du volume.

En mode itération, `REGISTRY.md` marque le jeu comme actif et les entrées de
`PLAYBOOK.md` issues de ses versions successives priment sur les autres.

## Premier jeu de validation
Mini simulator : cliquer pour gagner une monnaie, boutique avec 3 améliorations et 2 Developer Products, roue quotidienne, sauvegarde. Objectif : sortir en un seul prompt, jouable et publié. Pas de joli tant que le pipeline n'est pas prouvé.