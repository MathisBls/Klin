# forge-clicker

**Statut** : publié en live le 2026-09-07 (version 7)
**Univers** : Kiln Test (`6934111218`)

## Leçons des jeux précédents

Premier jeu de la série. `games/REGISTRY.md` est vide, `games/PLAYBOOK.md` ne
contient aucune entrée prouvée. Il n'y a donc rien à conserver ni à abandonner.

**Ce que ce jeu sert à faire** : prouver que le pipeline sort un jeu jouable et
publié en une passe. Ce n'est pas un jeu qui cherche une audience, c'est un jeu
qui cherche à valider une chaîne de production.

**Hypothèses du playbook que ce jeu met à l'épreuve** :

| Hypothèse | Comment ce jeu la teste |
|---|---|
| Donner à faire en moins de 10 s retient mieux | l'enclume est à 6 studs du spawn, cliquable immédiatement, sans menu |
| Onboarding sans texte long | zéro tutoriel écrit, seulement un `+1` flottant au premier clic |
| Une roue quotidienne fait revenir | cooldown de 4 h, visible en permanence |
| Deux Developer Products suffisent à mesurer une conversion | un pack de monnaie, un tour de roue |

Ces quatre points passeront dans `PLAYBOOK.md` **avec leurs chiffres** après
`make analytics --slug forge-clicker`, pas avant.

## Identité

| Axe | Valeur |
|---|---|
| **Mécanique principale** | cliquer — frapper une enclume pour produire de la monnaie |
| **Thème** | atelier de forge, pierre sombre et métal chaud |
| **Hook des 10 premières secondes** | le joueur apparaît face à une enclume qui pulse en orange ; le premier clic fait jaillir un éclat et affiche `+1` ; le compteur en haut monte tout de suite |
| **Genre** | simulator / incremental |

## Boucle de jeu

### 30 secondes

Le joueur clique. Chaque clic donne des **Éclats**. Au bout d'environ 7
secondes il a de quoi acheter son premier Marteau, ce qui double son gain. Le
saut est immédiat et visible : le `+1` devient `+2`.

Objectif : que la première amélioration tombe avant que le joueur ait le temps
de se demander ce qu'il fait là.

### 5 minutes

Trois leviers se sont ouverts :

- **Marteau** — plus d'éclats par clic, achat fréquent, gratification courte
- **Soufflet** — multiplicateur, achat plus rare, gratification moyenne
- **Apprenti** — production automatique, le jeu commence à tourner sans clic

L'Apprenti est le moment charnière : le joueur voit son compteur monter alors
qu'il ne touche à rien. C'est ce qui transforme une session de curiosité en
session de progression.

La roue est disponible dès le premier jour, avec un cooldown de 4 h.

### 1 heure

Le rythme de clic ne suffit plus, la production automatique domine. Le joueur
arbitre entre acheter un niveau d'Apprenti de plus ou attendre la roue. Les
deux Developer Products deviennent visibles comme raccourcis, sans être
imposés.

Le coût des améliorations croît géométriquement, donc l'attente s'allonge
naturellement. C'est le point où le jeu doit soit donner une raison de revenir
demain (la roue), soit perdre le joueur. C'est exactement ce que la rétention
J1 mesurera.

## Économie chiffrée

**Monnaie unique** : Éclats (`SHARDS`), départ à 0, pas de plafond, affichage
abrégé au-delà de 1 000.

### Gain par clic

```
gain = (1 + niveauMarteau) * (1 + 0.10 * niveauSoufflet) * multiplicateurs
```

### Améliorations

| Clé | Nom | Effet par niveau | Prix de base | Croissance | Niveau max |
|---|---|---|---|---|---|
| `HAMMER` | Marteau | +1 éclat par clic | 25 | ×1.35 | 25 |
| `BELLOWS` | Soufflet | +10 % de gain | 100 | ×1.50 | 15 |
| `APPRENTICE` | Apprenti | +1 éclat / seconde | 250 | ×1.60 | 20 |

Prix du niveau *n* = `basePrice * croissance^n`, arrondi à l'entier.

### Jalons de progression

Base de calcul : 4 clics par seconde, joueur actif sans interruption.

| Temps | Éclats cumulés | Ce que le joueur a |
|---|---|---|
| 7 s | ~28 | Marteau 1 — le gain double |
| 30 s | ~200 | Marteau 3 |
| 2 min | ~1 400 | Marteau 5, Soufflet 1 |
| 5 min | ~4 500 | Soufflet 2, **Apprenti 1** — la production auto démarre |
| 20 min | ~30 000 | Apprenti 4, Marteau 10 |
| 1 h | ~150 000 | Apprenti 7, Soufflet 5 |

L'Apprenti à 5 minutes est le chiffre le plus important de cette table. Trop
tôt, le clic n'a pas eu le temps d'exister ; trop tard, le joueur part avant.

### Roue

Cooldown **4 heures**. Poids sur un total de 100, donc lisibles en pourcentage.

| Lot | Récompense | Poids | Probabilité |
|---|---|---|---|
| Poignée d'éclats | 50 éclats | 40 | 40 % |
| Bourse | 150 éclats | 25 | 25 % |
| Coffre | 500 éclats | 15 | 15 % |
| Coffre lourd | 2 000 éclats | 10 | 10 % |
| Braise ardente | ×2 pendant 5 min | 8 | 8 % |
| Cœur de forge | 10 000 éclats | 2 | 2 % |

Le lot à 2 % vaut environ 20 minutes de jeu à mi-parcours : assez pour
provoquer une réaction, pas assez pour casser la courbe.

## Monétisation

| Clé | Type | Nom | Prix | Contenu |
|---|---|---|---|---|
| `SHARDS_POUCH` | Developer Product | Bourse d'éclats | 25 R$ | 10 000 éclats |
| `EXTRA_SPIN` | Developer Product | Tour supplémentaire | 15 R$ | un tour de roue immédiat, ignore le cooldown |

Pas de Game Pass sur ce jeu. Un Game Pass est un achat permanent : le proposer
sur un jeu dont on ne sait pas encore s'il retient qui que ce soit, c'est
vendre quelque chose qu'on n'a pas prouvé.

Les 10 000 éclats de la bourse valent environ 20 minutes de jeu à mi-parcours.
Ce n'est pas un raccourci qui saute la progression, c'est une avance.

## Map

Une seule pièce, pas de déplacement nécessaire.

| Élément | Position | Rôle |
|---|---|---|
| Sol | 60 × 60 studs, pierre sombre | l'atelier |
| Spawn | à 6 studs de l'enclume, orienté vers elle | le joueur voit sa cible sans bouger |
| Enclume | centre, métal, halo orange pulsant | la cible du clic |
| Forge | derrière l'enclume, émission chaude | source de lumière et d'ambiance |
| Murs | 4 murs de 20 studs | ferment la pièce |
| Limites | volume invisible englobant | empêche de sortir |

Budget : moins de 100 parts. Tout est ancré.

## Ambiance

Pierre sombre, métal chaud, une seule source de lumière orange venant de la
forge. `ClockTime` à 2 (nuit), brouillard à 120 studs pour resserrer l'espace
sur l'enclume.

L'UI est en bas et en haut, jamais au centre : le centre appartient à
l'enclume.

Pas de musique dans cette version. Un asset audio impose un upload et un
passage en modération, ce qui ajoute un point de rupture à une passe qui doit
d'abord prouver le pipeline.

## Skills utilisées

| Skill | Rôle ici |
|---|---|
| [[save]] | profil : éclats, niveaux, roue, reçus |
| [[currency]] | Éclats, gains, multiplicateurs temporaires |
| [[shop]] | 3 améliorations, 2 Developer Products, `ProcessReceipt` |
| [[wheel]] | 6 lots, cooldown 4 h, tour payant en Robux |
| [[map-gen]] | l'atelier |

Non utilisées : `inventory` (aucun objet), `leaderboard` (à ajouter seulement si
le jeu retient — un classement vide décourage plus qu'il ne motive),
`daily-reward` (la roue joue déjà ce rôle, en ajouter un second diluerait la
mesure de son effet).

## Critères de réussite de la passe

Ce jeu est réussi si, sans intervention manuelle :

1. `make build` produit un `.rbxl`
2. `make test` passe dans un serveur Roblox réel
3. `make products` crée les 2 Developer Products et écrit leurs IDs
4. `make publish-live` met le jeu en ligne sur Kiln Test
5. un joueur peut cliquer, acheter les 3 améliorations, tourner la roue, se
   déconnecter et retrouver sa progression

Le critère 5 est le seul qui compte vraiment. Les quatre autres sont des
préalables.
