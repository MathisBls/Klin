# street-football — étape 1 : le lobby

**Statut** : spec — en attente de validation
**Univers** : Kiln Test (`6934111218`)

Ce document ne couvre que **le lobby**. Le football lui-même (conduite,
frappe, matchs) fera l'objet d'une seconde spec, une fois le lobby validé en
jeu.

## Leçons des jeux précédents

Ni `forge-clicker` ni `penalty-league` n'ont été publiés pour de vrai, donc
aucune métrique joueur. Mais deux leçons de production commandent ce document.

**Les maps précédentes étaient moches, et pas par manque de goût.** Je n'avais
aucun outil pour résoudre un ID d'asset, et `CLAUDE.md` interdit d'en inventer
un. Il ne restait que l'empilement de `Part` primitives. `tools/store_search.py`
lève ce blocage : tout modèle vient d'une recherche réelle, est filtré, vérifié,
puis **testé en chargement dans un vrai serveur**.

**Une map ne devient pas vivante en ajoutant des modèles.** Mes deux maps
n'avaient ni `Atmosphere`, ni `Bloom`, ni `SunRays`, ni `ColorCorrection`,
ni ombres portées. Une grande part de ce qui rend une map Roblox « épique »
tient à l'éclairage, pas à la géométrie. C'est traité ici au même rang que le
décor.

## Ce que le lobby doit être

Un lieu où l'on a envie de rester deux minutes avant de jouer. Pas un menu
déguisé en salle d'attente.

| Exigence | Traduction concrète |
|---|---|
| **Grand** | 500 × 500 studs, plusieurs minutes pour en faire le tour |
| **Vivant** | végétation, éclairage, eau, mouvement, profondeur verticale |
| **Lisible** | on comprend où aller en dix secondes, sans lire |
| **Des chemins** | on suit un tracé, on ne traverse pas une plaine vide |
| **Des coins jeu** | des zones distinctes, pas un plateau uniforme |
| **Des boutiques** | de vrais bâtiments dans lesquels on entre |
| **Des panneaux** | flottants, avec texte : jouer, règles, boutique |

## Plan de masse

Une place centrale, quatre directions qui en partent. Le joueur apparaît au
centre et voit ses options sans bouger.

```
                    TERRAINS (nord)
                    portails de match
                          |
                     [ arche ]
                          |
  BOUTIQUES  ---- PLACE CENTRALE ----  ENTRAINEMENT
    (ouest)         fontaine              (est)
                    spawn                cible de tir
                          |
                     [ escalier ]
                          |
                     BELVEDERE (sud)
                  surplomb, vue sur tout
```

| Zone | Contenu | Rôle |
|---|---|---|
| **Place centrale** | fontaine, pavage, bancs, arbres, lampadaires | point de repère, spawn |
| **Nord — Terrains** | arche monumentale, trois portails, panneau de règles | là où on va jouer |
| **Ouest — Boutiques** | trois bâtiments avec devanture, étals, banderoles | monétisation, cosmétiques |
| **Est — Entraînement** | but, ballons, cible de tir | on essaie la mécanique sans enjeu |
| **Sud — Belvédère** | escalier, plateforme haute, arbres | verticalité, point de vue |

La verticalité n'est pas décorative : une map plate paraît petite quelle que
soit sa taille.

## Panneaux flottants

`BillboardGui` ancrés, lisibles de loin, avec une icône et deux lignes de
texte maximum.

| Panneau | Emplacement | Texte |
|---|---|---|
| Terrains | au-dessus de l'arche nord | « TERRAINS — entre pour jouer un match » |
| Règles | à côté de l'arche | « RÈGLES — 3v3, 5 minutes, premier à 3 buts » |
| Boutiques | au-dessus de la rue ouest | « BOUTIQUES » |
| Entraînement | au-dessus du but est | « ENTRAÎNEMENT — libre » |
| Chaque portail | au-dessus | nom du terrain, joueurs présents |

Deux lignes maximum : un panneau qu'on doit lire n'est plus un panneau.

## Assets

Aucun ID n'entre dans ce jeu sans avoir passé trois filtres :

1. **Recherche** sur le Creator Store, gratuits seulement
2. **Filtre automatique** : modèles contenant des scripts écartés — c'est le
   vecteur de backdoor le plus courant sur Roblox — et budget de triangles
3. **Test de chargement réel** : `InsertService:LoadAsset` exécuté dans un
   serveur Roblox. Un asset présent au catalogue n'est pas forcément chargeable

Les modèles retenus sont chargés **une fois** au démarrage puis clonés :
charger le même arbre trente fois coûterait trente appels réseau.

## Architecture technique

| Élément | Où |
|---|---|
| Sol, chemins, bâtiments, escaliers | `src/workspace/Lobby.model.json`, bâti par Rojo |
| Placement du décor | `src/shared/config/LobbyLayout.luau`, une liste de données |
| Chargement et clonage | `src/server/systems/Decor.luau` |
| Panneaux | `src/server/systems/Signs.luau` |
| Éclairage et atmosphère | propriétés Rojo dans `default.project.json` |

Le placement est **de la donnée, pas du code** : déplacer un arbre ne demande
pas de toucher à une fonction.

## Ce que `make test` pourra vérifier

- chaque asset du layout se charge réellement
- aucun modèle chargé ne contient de script
- le spawn a du sol sous lui
- les quatre zones existent et sont atteignables à pied
- chaque panneau a un texte non vide
- budget de parts et de triangles respecté

Le rendu, lui, ne se teste pas. Il se regarde.

## Critères de réussite

1. Le lobby fait au moins 400 × 400 studs praticables
2. Depuis le spawn, on voit les quatre directions sans bouger la caméra
3. On rejoint chaque zone par un chemin, jamais à travers du vide
4. Aucun script tiers n'est chargé dans le jeu
5. Le tout tient sous 60 FPS sur une machine moyenne
6. **Ça donne envie de rester** — seul critère non mesurable, et le plus important
