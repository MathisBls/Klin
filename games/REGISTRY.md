# Registre des jeux

Un jeu par ligne. **À consulter avant d'écrire toute nouvelle spec** : si la
mécanique ou le hook envisagé figure déjà ici, changer d'idée avant d'écrire.

Un nouveau jeu doit différer sur les trois axes à la fois — mécanique, thème,
hook. Deux sur trois ne suffit pas.

| Slug | Mécanique principale | Thème | Hook des 10 premières secondes | Sortie | État |
|---|---|---|---|---|---|
| `forge-clicker` | cliquer (enclume) | atelier de forge | enclume à 6 studs du spawn, pulsante ; le premier clic fait jaillir un `+1` | — | archivé |
| `penalty-league` | tirer au but (visée + puissance) | football de club, stade en nocturne | apparition **sur le point de penalty**, ballon posé, gardien en face — aucun menu | 2026-09-07 | en cours |

## États possibles

| État | Sens |
|---|---|
| `en cours` | spec écrite, pas encore publié |
| `publié` | en ligne, chiffres pas encore lisibles (moins de 7 jours) |
| `mesuré` | chiffres disponibles, rapport dans `reports/<slug>.md` |
| **`itération`** | signal fort — on améliore celui-là au lieu d'en créer un autre |
| `archivé` | abandonné ou jamais publié ; ses leçons sont dans `PLAYBOOK.md` |

## Mécaniques déjà utilisées

Liste à plat, pour vérifier d'un coup d'œil ce qui est pris. Une mécanique
présente ici est interdite pour un nouveau jeu, sauf en mode `itération` sur le
jeu qui la porte.

- **cliquer un objet du décor** — `forge-clicker`
- **viser un point et doser une puissance sous contrainte de temps** — `penalty-league`

## Hooks déjà utilisés

- **objet interactif à portée immédiate du spawn, sans menu ni texte** — `forge-clicker`
- **action à enjeu immédiat dès l'apparition, avant tout menu** — `penalty-league`
