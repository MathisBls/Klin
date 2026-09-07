# skill: map-gen

## Rôle

Construit une map jouable à partir d'une description textuelle de la spec. Pas
de beauté : une map lisible, sans trou, où le joueur comprend où aller en moins
de dix secondes.

## Dépend de

Rien. Peut consommer [[assets]] si la spec référence des modèles.

## Contrat d'entrée

```luau
export type Zone = {
	key: string,
	displayName: string,
	-- Coin bas-gauche et taille, en studs. Grille alignee sur 4.
	origin: Vector3,
	size: Vector3,
	-- Couleur dominante, pour distinguer les zones sans texture.
	color: Color3,
	material: Enum.Material,
	-- Points d'interet poses dans la zone.
	anchors: { { key: string, offset: Vector3, kind: string } },
}

export type MapConfig = {
	-- Point d'apparition. Doit etre dans une zone.
	spawnPosition: Vector3,
	zones: { Zone },
	-- Mur invisible autour de l'ensemble. Empeche de tomber hors map.
	bounds: { center: Vector3, size: Vector3 },
	lighting: {
		ambient: Color3,
		clockTime: number,
		fogEnd: number,
	},
}
```

## Fichiers produits

| Chemin | Rôle |
|---|---|
| `src/shared/config/MapConfig.luau` | zones, spawn, limites |
| `src/workspace/Map.model.json` | géométrie statique, buildée par Rojo |
| `src/server/systems/MapAnchors.luau` | résolution des points d'intérêt |
| `tests/map-gen.spec.luau` | tests de géométrie |

La géométrie passe par un modèle JSON Rojo, pas par du code qui crée des `Part`
au démarrage : ce qui est bâti au build est vérifiable avant publication et ne
coûte rien à l'exécution.

## API serveur

```luau
MapAnchors.get(anchorKey: string): BasePart?
MapAnchors.getZone(position: Vector3): string?
```

## Règles

**Tout est ancré.** `Anchored = true` sur chaque part statique. Une seule part
non ancrée tombe et emmène le joueur avec.

**Le spawn est au-dessus du sol.** Vérifier à la génération qu'il existe une
surface sous `spawnPosition`. Un spawn dans le vide fait tomber le joueur à
l'infini dès la première seconde — le pire premier écran possible.

**Les zones ne se chevauchent pas.** Deux zones qui se recoupent donnent un
z-fighting visible et rendent `getZone` ambigu. Vérifier à la génération.

**Limites fermées.** Le volume `bounds` entoure toute la map, avec
`CanCollide = true` et `Transparency = 1`. Sans lui, le joueur sort et tombe.

**Grille de 4 studs.** Aligner origines et tailles sur 4. Des valeurs
arbitraires produisent des interstices d'un demi-stud où le joueur se coince.

**Couleurs contrastées entre zones voisines.** C'est ce qui remplace une
signalétique : le joueur doit distinguer les zones sans lire un texte.

**Budget de parts.** Rester sous 1 000 parts pour une map simple. Au-delà,
fusionner les surfaces plates plutôt que multiplier les blocs.

## Tests attendus

- une part est présente sous `spawnPosition`
- toutes les parts statiques sont `Anchored`
- aucune paire de zones ne se chevauche
- le volume `bounds` contient toutes les zones
- chaque `anchors` déclaré est retrouvable par `MapAnchors.get`
- origines et tailles sont des multiples de 4
- le nombre total de parts reste sous le budget
