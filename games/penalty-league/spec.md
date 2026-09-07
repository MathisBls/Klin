# penalty-league

**Statut** : spec — en attente de validation
**Univers** : Kiln Test (`6934111218`), en remplacement de `forge-clicker`

## Leçons des jeux précédents

`forge-clicker` n'a pas été publié : il a servi à prouver la chaîne de
production, pas à trouver une audience. `games/PLAYBOOK.md` ne contient donc
aucune entrée chiffrée, et il n'y a rien à conserver ni à abandonner sur la
base de métriques.

**Ce qu'il a quand même appris**, et qui vaut pour ce jeu :

| Constat | Conséquence ici |
|---|---|
| Le test cherchait en récursif là où le client cherchait en direct : le clic n'a jamais marché | Tout test de câblage rejoue **le chemin exact du client** |
| Roblox fait pivoter un GuiObject autour de son centre, pas de son AnchorPoint | Toute UI qui tourne passe par une image, pas par des Frames assemblées |
| `make test` ne démarre pas le jeu (`RunService:IsRunning()` vaut `false`) | **Ce jeu est conçu pour que le maximum de logique soit du calcul pur, donc testable** |

Ce dernier point n'est pas une contrainte subie : c'est le principe de design
du jeu. Voir « Pourquoi ce périmètre » plus bas.

## Identité

| Axe | Valeur |
|---|---|
| **Mécanique principale** | tirer au but — viser un coin, doser la puissance, contre un gardien |
| **Thème** | football de club, ambiance stade en nocturne |
| **Hook des 10 premières secondes** | le joueur apparaît **sur le point de penalty**, ballon posé, gardien en face. Aucun menu. Il tire avant d'avoir lu quoi que ce soit |
| **Genre** | sports / manager asynchrone |

Différenciation contre le registre : `forge-clicker` utilisait « cliquer un
objet du décor » avec pour hook « objet interactif près du spawn ». Ici la
mécanique est une visée dosée sous contrainte de temps, et le hook est une
action à enjeu immédiat. Les trois axes diffèrent.

## Pourquoi ce périmètre, et pas un vrai match

Un 11v11 jouable sur Roblox bute sur trois murs :

1. **La propriété réseau du ballon.** Une part est simulée par celui qui en a
   la propriété. Ballon serveur → le tireur subit sa propre latence. Ballon
   client → il peut tricher et les autres voient le ballon téléporter. Les
   gros jeux de foot Roblox ont mis des mois là-dessus.
2. **Les animations.** Frappe, course, tacle, plongeon. Ça s'auteur à la main
   dans Studio. Impossible à générer correctement par script.
3. **Le remplissage.** 11v11 avec 4 joueurs connectés exige des bots avec
   pathfinding et décisions tactiques.

**Ce jeu contourne les trois en faisant du ballon une décoration.** Le client
envoie `(coin visé, puissance)`. Le serveur décide du résultat par un tirage
pondéré. La trajectoire affichée n'est qu'un tween qui illustre une décision
déjà prise. Aucune propriété réseau, aucune triche possible, aucune
désynchronisation.

Et **la ligue est asynchrone** : on affronte la sauvegarde d'un autre joueur,
pas le joueur lui-même. Pas de matchmaking, pas de serveur partagé, pas de
réplication temps réel. Le jeu fonctionne avec un seul joueur connecté.

Conséquence directe : le moteur de match, l'économie, les cotes des packs et le
classement sont **du calcul pur**, donc couverts par `make test`. Seul le
ressenti du tir ne l'est pas.

## Boucle de jeu

### 30 secondes

Le joueur apparaît sur le point de penalty. Une jauge de puissance oscille, un
réticule se déplace le long de la ligne de but. Un clic fixe la visée, un
second la puissance. Le gardien plonge. But ou arrêt.

Après le premier tir : « Tu viens de rejoindre le **FC \<pseudo\>**. Division 5. »
Le club se matérialise depuis l'action, pas depuis un formulaire.

### 5 minutes

Le joueur a joué ses deux ou trois premières journées de championnat. Chaque
match affiche une feuille de match qui se déroule (minute par minute, accéléré),
et s'interrompt sur **les penalties, qu'il tire lui-même**. Ces tirs changent
le résultat pour de vrai.

Il a ouvert sa première pochette et découvert le système de cartes : chaque
joueur a une note et un poste. Il comprend que sa composition change les
probabilités de la simulation.

### 1 heure

La saison avance. Le classement de la division est visible, peuplé des clubs
d'autres joueurs réels. Le joueur arbitre entre garder ses crédits pour une
pochette rare ou renforcer un poste faible.

L'enjeu de fin de saison est la **montée** : passer de Division 5 à Division 4.
C'est la raison de revenir demain — bien plus qu'un cooldown.

## Économie chiffrée

**Monnaie unique** : Crédits (`CREDITS`), départ à 500.

### Gains

| Source | Crédits |
|---|---|
| Victoire | 120 |
| Match nul | 60 |
| Défaite | 30 |
| Penalty marqué | 15 |
| Fin de saison, par place gagnée au classement | 50 |
| Montée de division | 500 |

Un match dure ~90 s montre en main. À trois matchs, le joueur a de quoi ouvrir
sa première pochette (250). Le premier palier tombe donc dans les cinq
premières minutes — le jalon que `forge-clicker` plaçait à sept secondes est ici
la première pochette.

### Cartes joueurs

Cinq postes : `GK`, `DEF`, `MID`, `ATT`, plus un `SUB` remplaçant. Chaque carte
a une note de 40 à 99.

| Rareté | Plage de note | Poids | Probabilité |
|---|---|---|---|
| Bronze | 40-59 | 55 | 55 % |
| Argent | 60-74 | 28 | 28 % |
| Or | 75-86 | 13 | 13 % |
| Élite | 87-94 | 3.5 | 3,5 % |
| Légende | 95-99 | 0.5 | 0,5 % |

Poids sur 100, donc lisibles en pourcentage direct — comme la roue de
`forge-clicker`, et pour la même raison.

**Pochette** : 250 crédits, 3 cartes. Une carte doublon se revend
automatiquement à 40 % de sa valeur, pour qu'aucune ouverture ne soit vide de
sens.

### Notes d'équipe

```
Attaque  = ATT.note * 0.7 + MID.note * 0.3
Milieu   = MID.note * 0.7 + (ATT.note + DEF.note) * 0.15
Défense  = DEF.note * 0.7 + GK.note * 0.3
```

Le remplaçant `SUB` ajoute 5 % de sa note au poste le plus faible : il a une
valeur sans compliquer la formule.

### Moteur de match

Déterministe à partir de `(équipeA, équipeB, graine)`. Douze événements, chacun :

1. **Possession** : tirage pondéré par `MilieuA` contre `MilieuB`
2. **Occasion** : `p = 0.30 * AttaqueA / (AttaqueA + DéfenseB)`
3. Si occasion, **but** avec `p = 0.42`, sinon arrêt
4. **Penalty** : 8 % par occasion créée. Le match se met en pause, le joueur
   tire.

Une graine dérivée de `(idJoueur, idAdversaire, numéroDeJournée)` rend le match
rejouable à l'identique — indispensable pour qu'un test puisse vérifier le
moteur, et pour qu'un joueur ne puisse pas relancer un match perdu.

### Tir au but

Le client envoie `(coinX, coinY, puissance)`, tous trois bornés `[0, 1]`. Le
serveur :

1. rejette toute valeur hors bornes, `NaN` ou infinie
2. calcule la difficulté : viser une lucarne est plus risqué que le centre
3. tire l'arrêt : `pArrêt = 0.28 + 0.004 * (noteGK - 60) - 0.20 * difficulté`
4. tire le tir manqué (cadre) : `pDehors = 0.05 + 0.25 * difficulté²`

Un tir mou au centre est presque toujours arrêté. Une lucarne pleine puissance
passe souvent, mais sort une fois sur cinq. Le joueur a une vraie décision.

## Ligue

- **Cinq divisions**, de 5 (départ) à 1
- **Saison = 10 journées**, jouées au rythme du joueur
- Victoire 3 pts, nul 1 pt
- Fin de saison : les **3 premiers montent**, les **3 derniers descendent**
- Adversaires : squads d'autres joueurs réels, tirés d'un pool persistant.
  Complétés par des clubs générés quand le pool est trop mince — un classement
  vide décourage plus qu'il ne motive

Le squad de chaque joueur est publié dans le pool à chaque changement de
composition. On affronte une **photo** de son équipe, jamais le joueur en
direct.

## Monétisation

| Clé | Type | Nom | Prix | Contenu |
|---|---|---|---|---|
| `PACK_GOLD` | Developer Product | Pochette Or | 49 R$ | 3 cartes, Or garanti |
| `CREDITS_LARGE` | Developer Product | 3 000 crédits | 79 R$ | ~12 pochettes |
| `SEASON_PASS` | Game Pass | Pass Saison | 199 R$ | +50 % de crédits sur tous les gains |

Un Game Pass est justifié ici, contrairement à `forge-clicker` : il porte sur
une boucle longue, pas sur un jeu dont on ignore s'il retient.

**Aucun achat ne donne de carte Légende garantie.** Vendre le sommet de la
progression tue la progression.

## Map

Un stade, une seule zone jouable. Pas de déplacement nécessaire.

| Élément | Rôle |
|---|---|
| Pelouse et lignes | terrain, surface de réparation visible |
| But + filet | la cible |
| Point de penalty | le spawn, face au but |
| Gardien | mannequin animé par tween, pas de physique |
| Tribunes | volume simple, ambiance nocturne |
| Panneau LED | affiche le score du match en cours |

Ambiance nocturne, projecteurs. Budget sous 300 parts.

## Skills utilisées

| Skill | Rôle ici |
|---|---|
| [[save]] | profil : club, squad, cartes, saison, classement, reçus |
| [[currency]] | crédits, gains de match |
| [[inventory]] | cartes joueurs possédées, composition |
| [[shop]] | pochettes, produits Robux, `ProcessReceipt` |
| [[wheel]] | réutilisée pour l'ouverture de pochette (tirage pondéré) |
| [[leaderboard]] | classement de division |
| [[map-gen]] | le stade |

Nouvelle skill à écrire : **`match-sim`** — moteur de match déterministe,
pur, rejouable à partir d'une graine.

## Périmètre v1, et ce qui est reporté

**Dans la v1** : tir au but, moteur de match, cartes et pochettes, composition
à 5 postes, une saison de 10 journées, deux divisions actives (5 et 4),
classement, monétisation complète.

**Reporté explicitement** : le marché des transferts entre joueurs, les
tactiques, les blessures, les compétitions à élimination directe, les cinq
divisions complètes, et toute animation de joueur autre que le gardien.

Ce report n'est pas de la paresse : chacun de ces éléments ajoute une surface
de bug que `make test` ne couvre pas, et la v1 doit d'abord prouver que la
boucle tient.

## Critères de réussite

1. `make test` passe, dont le moteur de match sur graine fixe
2. Un joueur tire un penalty dans les 10 secondes suivant son arrivée
3. Une journée de championnat se joue de bout en bout, penalties compris
4. La composition modifie mesurablement les résultats simulés
5. Progression, cartes et classement survivent à une déconnexion
6. Un achat Robux crédite exactement une fois, `PurchaseId` à l'appui

Le critère 4 est le cœur : si changer sa composition ne change rien de visible,
le jeu n'est qu'un générateur de nombres aléatoires déguisé.
