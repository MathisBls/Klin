# skill: assets

## Rôle

Fait le lien entre « le jeu a besoin d'une icône de pièce » et un
`rbxassetid://` utilisable. Deux voies : un ID Creator Store existant, ou un
fichier local uploadé via Open Cloud.

Cette skill n'est pas une mécanique de gameplay. C'est l'étape de pipeline que
les autres skills consomment via `Config.assets`.

## Dépend de

Rien. Toutes les autres skills dépendent d'elle pour leurs icônes.

## Contrat d'entrée

`assets/manifest.json`, à la racine du repo :

```json
{
  "version": 1,
  "assets": [
    { "key": "COIN_ICON", "assetId": 1234567 },

    { "key": "MUSIC_LOOP",
      "type": "Audio",
      "file": "assets/files/loop.mp3",
      "displayName": "Boucle d'ambiance" }
  ]
}
```

| Forme | Effet |
|---|---|
| `assetId` fourni | utilisé tel quel, aucun appel réseau |
| `file` fourni | uploadé si son SHA-256 diffère du lock |

Types acceptés : `Image`, `Audio`, `Model`, `Mesh`, `Decal`, `Video`,
`Animation`. L'extension du fichier doit correspondre au type.

## Fichiers produits

| Chemin | Rôle |
|---|---|
| `assets/assets.lock.json` | clé logique → assetId + empreinte |
| `src/shared/Config.luau` | `Config.assets.COIN_ICON` → `"rbxassetid://…"` |

Le lock est **versionné dans git**. C'est la mémoire du pipeline : sans lui,
chaque run ré-uploaderait tout et créerait des doublons sur ton compte.

## Utilisation dans les autres skills

```luau
local Config = require(ReplicatedStorage.Shared.Config)
icon.Image = Config.assets.COIN_ICON
```

Une skill référence toujours une **clé logique**, jamais un nombre. C'est ce qui
permet de remplacer un asset sans toucher au code.

## Règles

**Ne jamais inventer un ID.** Un ID d'asset est soit résolu par l'API, soit
fourni explicitement dans le manifest. Un nombre écrit au jugé pointe vers
l'asset de quelqu'un d'autre, ou vers rien.

**L'upload est asynchrone.** L'Assets API renvoie une opération, pas un ID. Il
faut la sonder jusqu'à `done: true` avant de lire `assetId`.

**Un fichier inchangé n'est pas ré-uploadé.** Comparaison par SHA-256 contre le
lock. `--force` outrepasse.

**La modération peut rejeter.** Un asset uploadé passe en revue. Une image
refusée ne sera jamais servie : le pipeline doit signaler, pas échouer
silencieusement sur un `rbxassetid://` mort.

**Les clés sont stables, les noms ne le sont pas.** `COIN_ICON` ne change
jamais ; `displayName` peut changer librement.

**Le créateur vient de `.env`.** `ROBLOX_CREATOR_USER_ID` ou
`ROBLOX_CREATOR_GROUP_ID`. Un asset uploadé sous le mauvais compte n'est pas
utilisable dans l'expérience.

## Tests attendus

- une entrée `assetId` est reprise telle quelle, sans appel réseau
- une entrée `file` inchangée réutilise l'ID du lock
- une entrée `file` modifiée déclenche un nouvel upload
- une clé dupliquée dans le manifest est rejetée
- un `type` inconnu est rejeté
- une extension incompatible avec le `type` est rejetée
- un fichier absent est signalé avec son chemin
- `Config.assets` contient une entrée par clé du manifest
