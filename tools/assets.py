"""Resout assets/manifest.json : upload les fichiers locaux, garde les IDs.

Le manifest declare des assets par cle logique. Deux formes :

    { "key": "COIN_ICON", "assetId": 1234567 }
        -> asset deja sur Roblox (Creator Store ou upload precedent),
           on l'utilise tel quel, aucun appel reseau.

    { "key": "COIN_ICON", "type": "Image", "file": "assets/files/coin.png",
      "displayName": "Coin" }
        -> fichier local, uploade via l'Assets API si pas deja dans le lock.

Le lock (assets/assets.lock.json) evite de re-uploader a chaque run : on
compare l'empreinte SHA-256 du fichier. Fichier inchange -> on reutilise l'ID.

Usage :
    python tools/assets.py
    python tools/assets.py --dry-run
    python tools/assets.py --force      # re-uploade meme si inchange
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import common
import config_gen

MANIFEST = common.ROOT / "assets" / "manifest.json"
LOCK = config_gen.ASSETS_LOCK

# assetType Roblox -> extensions acceptees et type MIME a envoyer.
ASSET_TYPES: dict[str, tuple[tuple[str, ...], str]] = {
    "Image": ((".png", ".jpg", ".jpeg", ".bmp", ".tga"), "image/png"),
    "Audio": ((".mp3", ".ogg"), "audio/mpeg"),
    "Model": ((".fbx",), "model/fbx"),
    "Mesh": ((".fbx",), "model/fbx"),
    "Decal": ((".png", ".jpg", ".jpeg"), "image/png"),
    "Video": ((".mp4", ".mov"), "video/mp4"),
    "Animation": ((".fbx",), "model/fbx"),
}


def file_digest(path: Path) -> str:
    """SHA-256 du fichier, pour savoir s'il a change depuis le dernier upload."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_manifest() -> list[dict[str, Any]]:
    """Lit et valide le manifest. Echoue tot sur une entree mal formee."""
    data = common.read_json(MANIFEST)
    if data is None:
        common.fail(f"{MANIFEST.relative_to(common.ROOT)} introuvable")

    entries = data.get("assets", [])
    if not isinstance(entries, list):
        common.fail("le champ 'assets' du manifest doit etre une liste")

    seen: set[str] = set()
    for index, entry in enumerate(entries):
        key = entry.get("key")
        if not key:
            common.fail(f"asset #{index} : champ 'key' manquant")
        if key in seen:
            common.fail(f"cle dupliquee dans le manifest : {key}")
        seen.add(key)

        if not entry.get("assetId") and not entry.get("file"):
            common.fail(f"asset '{key}' : il faut soit 'assetId', soit 'file'")

        if entry.get("file"):
            asset_type = entry.get("type")
            if asset_type not in ASSET_TYPES:
                common.fail(
                    f"asset '{key}' : type '{asset_type}' inconnu. "
                    f"Valeurs acceptees : {', '.join(sorted(ASSET_TYPES))}"
                )
            path = common.ROOT / entry["file"]
            if not path.is_file():
                common.fail(f"asset '{key}' : fichier introuvable -> {entry['file']}")
            extensions, _ = ASSET_TYPES[asset_type]
            if path.suffix.lower() not in extensions:
                common.fail(
                    f"asset '{key}' : extension {path.suffix} incompatible avec "
                    f"le type {asset_type} ({', '.join(extensions)})"
                )

    return entries


def upload(
    api: common.OpenCloud, cfg: common.Config, entry: dict[str, Any]
) -> int | None:
    """Uploade un fichier et attend l'ID final. None en dry-run."""
    key = entry["key"]
    path = common.ROOT / entry["file"]
    asset_type = entry["type"]
    _, mime = ASSET_TYPES[asset_type]

    request = {
        "assetType": asset_type,
        "displayName": entry.get("displayName", key),
        "description": entry.get("description", f"Genere par le pipeline Klin ({key})"),
        "creationContext": {"creator": cfg.creator()},
    }

    body, content_type = common.encode_multipart(
        fields={"request": json.dumps(request)},
        files={"fileContent": (path.name, path.read_bytes(), mime)},
    )

    common.info(f"upload {key} ({asset_type}, {path.stat().st_size / 1024:.0f} Ko)")
    response = api.request(
        "POST", "/assets/v1/assets", raw_body=body, content_type=content_type
    )

    if api.dry_run:
        return None

    operation = response.get("path") or response.get("operationId")
    if not operation:
        common.fail(f"asset '{key}' : reponse sans operation -> {response}")

    # L'API renvoie "operations/{id}" ; l'endpoint de suivi est sous /assets/v1/.
    if not operation.startswith("operations/"):
        operation = f"operations/{operation}"
    result = api.poll_operation(f"/assets/v1/{operation}")

    asset_id = (result.get("response") or {}).get("assetId")
    if not asset_id:
        common.fail(f"asset '{key}' : operation terminee sans assetId -> {result}")

    common.ok(f"{key} -> {asset_id}")
    return int(asset_id)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Resout le manifest d'assets et regenere Config.luau."
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="re-uploade meme si le fichier n'a pas change",
    )
    common.add_common_args(parser)
    args = parser.parse_args()

    entries = load_manifest()
    lock: dict[str, dict[str, Any]] = common.read_json(LOCK, default={}) or {}

    if not entries:
        common.info("manifest vide, rien a resoudre")
        config_gen.generate()
        common.emit({"resolved": 0, "uploaded": 0}, args.as_json)
        return 0

    cfg = common.load_config(require=("ROBLOX_API_KEY",))
    api = common.OpenCloud(cfg, dry_run=args.dry_run)

    uploaded = 0
    resolved: dict[str, dict[str, Any]] = {}

    for entry in entries:
        key = entry["key"]

        # Cas 1 : ID fourni en dur, rien a faire.
        if entry.get("assetId"):
            resolved[key] = {"assetId": int(entry["assetId"]), "source": "manifest"}
            common.info(f"{key} -> {entry['assetId']} (ID fourni)")
            continue

        # Cas 2 : fichier local. On compare l'empreinte avec le lock.
        path = common.ROOT / entry["file"]
        digest = file_digest(path)
        previous = lock.get(key, {})

        if (
            not args.force
            and previous.get("sha256") == digest
            and previous.get("assetId")
        ):
            resolved[key] = previous
            common.info(f"{key} -> {previous['assetId']} (inchange, upload evite)")
            continue

        asset_id = upload(api, cfg, entry)
        if asset_id is None:  # dry-run
            resolved[key] = previous or {"assetId": 0, "sha256": digest}
            continue

        resolved[key] = {
            "assetId": asset_id,
            "sha256": digest,
            "file": entry["file"],
            "type": entry["type"],
        }
        uploaded += 1

    if args.dry_run:
        common.ok(f"dry-run : {len(resolved)} asset(s), rien n'a ete envoye")
        common.emit({"dryRun": True, "resolved": len(resolved)}, args.as_json)
        return 0

    common.write_json(LOCK, resolved)
    config_gen.generate()

    common.ok(f"{len(resolved)} asset(s) resolu(s), dont {uploaded} uploade(s)")
    common.emit(
        {"resolved": len(resolved), "uploaded": uploaded, "assets": resolved},
        args.as_json,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
