"""Publie le build sur la place Roblox via Open Cloud.

Chaine complete :
    rojo build -o build/game.rbxl   (sauf --no-build)
    POST /universes/v1/{universeId}/places/{placeId}/versions?versionType=...

Deux types de version :
    Saved      -> la version est enregistree mais pas mise en ligne (defaut)
    Published  -> la version devient celle que jouent les joueurs

Le defaut est volontairement `Saved` : publier en live doit etre un geste
explicite (`--live`), jamais un effet de bord d'un script qui tourne.

Usage :
    python tools/publish.py                 # build + version Saved
    python tools/publish.py --live          # build + version Published
    python tools/publish.py --dry-run       # build seul, rien n'est envoye
    python tools/publish.py --no-build      # reutilise build/game.rbxl
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

import common

DEFAULT_OUTPUT = common.ROOT / "build" / "game.rbxl"
PROJECT_FILE = common.ROOT / "default.project.json"


def run_rojo_build(output: Path) -> None:
    """Construit le .rbxl. Echoue proprement si rojo n'est pas installe."""
    rojo = common.find_tool("rojo")
    if rojo is None:
        common.fail(
            "rojo introuvable, ni dans le PATH ni dans ~/.rokit/bin.\n"
            "       -> installe la toolchain : python tools/klin.py install\n"
            "       -> si rokit manque : winget install Rojo.Rokit"
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    command = [rojo, "build", str(PROJECT_FILE), "-o", str(output)]
    common.info(" ".join(command))

    result = subprocess.run(command, cwd=common.ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        common.error(result.stdout.strip())
        common.error(result.stderr.strip())
        common.fail("rojo build a echoue")

    if not output.is_file() or output.stat().st_size == 0:
        common.fail(f"rojo n'a produit aucun fichier exploitable : {output}")

    common.ok(f"build ok : {output.name} ({output.stat().st_size / 1024:.1f} Ko)")


def upload_version(
    api: common.OpenCloud, cfg: common.Config, place_file: Path, live: bool
) -> dict:
    """Envoie le .rbxl comme nouvelle version de la place."""
    version_type = "Published" if live else "Saved"
    path = f"/universes/v1/{cfg.universe_id}/places/{cfg.place_id}/versions"

    common.info(
        f"envoi de {place_file.name} vers universe {cfg.universe_id} / "
        f"place {cfg.place_id} (versionType={version_type})"
    )

    try:
        response = api.request(
            "POST",
            path,
            raw_body=place_file.read_bytes(),
            content_type="application/octet-stream",
            query={"versionType": version_type},
        )
    except common.ApiError as exc:
        common.error(str(exc))
        common.fail(exc.explain())

    return response if isinstance(response, dict) else {"raw": response}


def main() -> int:
    parser = argparse.ArgumentParser(description="Publie le build sur Roblox.")
    parser.add_argument(
        "--live",
        action="store_true",
        help="versionType=Published : la version devient celle que jouent "
        "les joueurs (defaut : Saved, non live)",
    )
    parser.add_argument(
        "--no-build",
        action="store_true",
        help="ne relance pas rojo, reutilise le fichier existant",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"chemin du .rbxl (defaut : {DEFAULT_OUTPUT.relative_to(common.ROOT)})",
    )
    common.add_common_args(parser)
    args = parser.parse_args()

    cfg = common.load_config(
        require=("ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID")
    )

    if args.no_build:
        if not args.output.is_file():
            common.fail(f"--no-build mais {args.output} n'existe pas")
        common.info(f"build ignore, reutilisation de {args.output.name}")
    else:
        run_rojo_build(args.output)

    api = common.OpenCloud(cfg, dry_run=args.dry_run)
    response = upload_version(api, cfg, args.output, args.live)

    if args.dry_run:
        common.ok("dry-run termine : build valide, rien n'a ete envoye a Roblox")
        common.emit({"dryRun": True, "file": str(args.output)}, args.as_json)
        return 0

    version = response.get("versionNumber")
    if version is None:
        common.warn(f"reponse inattendue de l'API : {response}")
    else:
        state = "EN LIGNE" if args.live else "enregistree (non live)"
        common.ok(f"version {version} {state}")
        common.info(f"https://www.roblox.com/games/{cfg.place_id}")

    common.emit(
        {
            "versionNumber": version,
            "versionType": "Published" if args.live else "Saved",
            "placeId": cfg.place_id,
            "universeId": cfg.universe_id,
        },
        args.as_json,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
