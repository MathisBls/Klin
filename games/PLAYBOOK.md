# Playbook

Ce qui marche, ce qui échoue, **avec le chiffre qui le prouve**.

Une entrée sans chiffre n'est pas une entrée de playbook. « L'onboarding sans
texte marche bien » est une opinion ; « onboarding sans texte, rétention J1 de
31 % contre 22 % avec tutoriel » est une entrée. Les convictions non mesurées
vont dans la section Hypothèses, en bas, et y restent jusqu'à ce qu'un chiffre
les tranche.

Le playbook s'applique à chaque nouveau jeu. **On ne redébat pas d'un point
tranché par les chiffres.**

## Ce qui marche

| Élément | Chiffre qui le prouve | Jeu source | Statut |
|---|---|---|---|
| _(rien de mesuré pour l'instant)_ | | | |

Statuts : `confirmé` (vérifié sur au moins deux jeux) · `observé` (un seul jeu,
à reconfirmer).

## Ce qui a échoué

| Élément | Chiffre qui le condamne | Jeu source | Remplacé par |
|---|---|---|---|
| _(rien de mesuré pour l'instant)_ | | | |

## Base commune

Ce qui est repris tel quel dans chaque nouveau jeu, sans rediscussion. Un
élément n'entre ici qu'après être passé `confirmé` ci-dessus.

_(vide — se remplira après les premiers jeux mesurés)_

## Hypothèses non vérifiées

Convictions de départ, issues de la doc Roblox ou de l'intuition. **Elles ne
font pas autorité.** Chacune doit être confirmée ou infirmée par un chiffre,
puis déplacée dans la section correspondante.

| Hypothèse | Origine | Comment la trancher |
|---|---|---|
| Le premier écran doit donner quelque chose à faire en moins de 10 secondes | doc Roblox, `CLAUDE.md` | comparer la rétention J1 de deux jeux dont le hook diffère en délai |
| Un onboarding sans texte long retient mieux | doc Roblox, `CLAUDE.md` | idem, sur deux jeux dont l'un a un tutoriel écrit |
| Une roue quotidienne fait revenir les joueurs | intuition de design | comparer la rétention J7 avec et sans roue |
| Deux Developer Products suffisent à mesurer une conversion | intuition | regarder le taux de joueurs payants du premier jeu |

## Seuils de décision

Repères pour lire un rapport. À ajuster dès que la série donne ses propres
ordres de grandeur — ce sont des points de départ, pas des vérités.

| Métrique | Signal faible | Correct | Signal fort → itération |
|---|---|---|---|
| Rétention J1 | < 20 % | 20-30 % | > 35 % |
| Rétention J7 | < 5 % | 5-10 % | > 12 % |
| Session moyenne | < 4 min | 4-8 min | > 10 min |
| Taux de joueurs payants | < 0,5 % | 0,5-2 % | > 3 % |
