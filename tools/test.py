"""Execute la suite de tests dans un vrai serveur Roblox, via Open Cloud.

Pourquoi pas run-in-roblox : ce binaire n'a plus recu de commit depuis
juillet 2020, il ne sait plus localiser Studio, et il exige de toute facon
une machine avec Studio installe - donc inutilisable en CI.

La Luau Execution Task API fait mieux : elle execute un script Luau dans un
serveur Roblox reel, contre une version publiee de la place. Pas de Studio,
pas de GPU, et exactement le meme moteur qu'en production.

Chaine :
    publish.py (version Saved)  -> on obtient un versionId
    POST .../versions/{v}/luau-execution-session-tasks avec le script
    polling jusqu'a COMPLETE ou FAILED
    GET .../logs pour recuperer les print/warn du script

Usage :
    python tools/test.py                  # build + publish Saved + execute
    python tools/test.py --version 5      # rejoue sur une version existante
    python tools/test.py --script autre.luau
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path
from typing import Any

import common
import publish

DEFAULT_SCRIPT = common.ROOT / "tests" / "run.server.luau"

# Etats terminaux renvoyes par l'API.
DONE_STATES = {"COMPLETE", "FAILED", "CANCELLED"}


def publish_test_version(cfg: common.Config, output: Path) -> int:
    """Publie une version Saved et renvoie son numero.

    Toujours Saved : une execution de tests ne doit jamais toucher a ce que
    voient les joueurs.
    """
    api = common.OpenCloud(cfg)
    publish.run_rojo_build(output)
    response = publish.upload_version(api, cfg, output, live=False)

    version = response.get("versionNumber")
    if version is None:
        common.fail(f"publication sans versionNumber -> {response}")
    common.ok(f"version de test {version} publiee (non live)")
    return int(version)


def create_task(
    api: common.OpenCloud, cfg: common.Config, version: int, script: str
) -> str:
    """Soumet le script et renvoie le chemin de la tache a interroger."""
    path = (
        f"/cloud/v2/universes/{cfg.universe_id}/places/{cfg.place_id}"
        f"/versions/{version}/luau-execution-session-tasks"
    )
    response = api.request("POST", path, body={"script": script})

    task_path = response.get("path")
    if not task_path:
        common.fail(f"tache creee sans champ 'path' -> {response}")
    return str(task_path)


def wait_for_task(
    api: common.OpenCloud, task_path: str, timeout: float = 300.0
) -> dict[str, Any]:
    """Interroge la tache jusqu'a un etat terminal."""
    deadline = time.monotonic() + timeout
    seen_state = ""

    while time.monotonic() < deadline:
        task = api.request("GET", f"/cloud/v2/{task_path.lstrip('/')}")
        state = task.get("state", "STATE_UNSPECIFIED")

        if state != seen_state:
            common.info(f"tache : {state}")
            seen_state = state

        if state in DONE_STATES:
            return task

        time.sleep(2.0)

    common.fail(f"tache toujours en cours apres {timeout:.0f}s")
    raise AssertionError("unreachable")


def fetch_logs(api: common.OpenCloud, task_path: str) -> list[str]:
    """Recupere toutes les lignes de log de la tache, pages comprises."""
    lines: list[str] = []
    cursor: str | None = None

    while True:
        response = api.request(
            "GET",
            f"/cloud/v2/{task_path.lstrip('/')}/logs",
            query={"maxPageSize": 100, "pageToken": cursor},
        )
        for entry in response.get("luauExecutionSessionTaskLogs", []):
            lines.extend(entry.get("messages", []))

        cursor = response.get("nextPageToken") or None
        if not cursor:
            break

    return lines


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Execute tests/run.server.luau dans un serveur Roblox reel."
    )
    parser.add_argument(
        "--script",
        type=Path,
        default=DEFAULT_SCRIPT,
        help=f"script a executer (defaut : {DEFAULT_SCRIPT.name})",
    )
    parser.add_argument(
        "--version",
        type=int,
        help="rejouer sur une version deja publiee, sans rebuild ni upload",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=publish.DEFAULT_OUTPUT,
        help="chemin du .rbxl intermediaire",
    )
    common.add_common_args(parser)
    args = parser.parse_args()

    if not args.script.is_file():
        common.fail(f"script introuvable : {args.script}")

    cfg = common.load_config(
        require=("ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID")
    )

    if args.dry_run:
        common.info(f"[dry-run] executerait {args.script.name} sur une version Saved")
        common.emit({"dryRun": True}, args.as_json)
        return 0

    version = args.version or publish_test_version(cfg, args.output)

    api = common.OpenCloud(cfg)
    source = args.script.read_text(encoding="utf-8")
    common.info(f"execution de {args.script.name} sur la version {version}")

    try:
        task_path = create_task(api, cfg, version, source)
        task = wait_for_task(api, task_path)
        logs = fetch_logs(api, task_path)
    except common.ApiError as exc:
        common.error(str(exc))
        common.fail(exc.explain())
        raise AssertionError("unreachable")

    if logs:
        print("", file=sys.stderr)
        for line in logs:
            print(f"  {line}", file=sys.stderr)
        print("", file=sys.stderr)

    state = task.get("state")
    if state != "COMPLETE":
        error = task.get("error") or {}
        common.error(f"tests en echec ({state})")
        if error.get("message"):
            common.error(error["message"])
        common.emit({"state": state, "version": version, "error": error}, args.as_json)
        return 1

    common.ok(f"tests passes sur la version {version}")
    common.emit({"state": state, "version": version, "logs": logs}, args.as_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
