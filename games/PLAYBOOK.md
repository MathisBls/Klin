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

## Leçons de production

Ces entrées ne viennent pas de métriques joueurs — `forge-clicker` n'a jamais
été publié — mais de bugs réels rencontrés en produisant. Elles sont donc
certaines, contrairement aux hypothèses de design ci-dessous.

| Leçon | D'où elle vient |
|---|---|
| Un test de câblage doit emprunter **le chemin exact du client**, pas un chemin plus permissif | `forge-clicker` : le test cherchait en récursif, le client en direct. Le clic n'a jamais marché et le test passait |
| Roblox fait pivoter un GuiObject autour de son **centre**, pas de son AnchorPoint | La roue dessinée en 186 Frames rendait un disque décalé. Une UI qui tourne doit être une image |
| Une UI générée doit être **produite depuis la config**, jamais redessinée à la main | `tools/gen_wheel.py` lit les poids dans `GameConfig.luau` : sinon l'image et le tirage divergent en silence |
| Un `409 Conflict` d'Open Cloud signifie le plus souvent **Studio ouvert sur la place** | Quinze minutes de 409 pendant que Studio tournait |
| La clé Open Cloud appartient au **compte créateur**, pas au compte de jeu | Upload d'asset refusé en 403 avec deux userId différents |
| Régler une économie **par simulation**, pas à l'estime | `penalty-league` : la première formule donnait 32 % de victoires au favori. Après réglage : 62 % |
| Un choix de gameplay n'existe que si **aucune option n'est toujours la meilleure** | `penalty-league` : le tir placé battait le tir risqué contre tous les gardiens. La visée était un faux choix |

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
