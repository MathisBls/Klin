"""Equivalent du Makefile, sans dependance a make. Pour Windows.

    python tools/klin.py            # liste les cibles
    python tools/klin.py doctor
    python tools/klin.py publish -- --live

Tout ce qui suit `--` est passe tel quel au script sous-jacent.
Les deux entrees (make et klin.py) doivent rester synchronisees : si tu
ajoutes une cible au Makefile, ajoute-la ici.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import common

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "game.rbxl"
PY = [sys.executable]

# cible -> (description, liste de commandes)
TARGETS: dict[str, tuple[str, list[list[str]]]] = {
    "install": (
        "Installe la toolchain (rokit) et les dependances (wally)",
        [["rokit", "install"], ["wally", "install"]],
    ),
    "doctor": (
        "Verifie la cle Open Cloud et ses scopes (lecture seule)",
        [PY + ["tools/doctor.py"]],
    ),
    "fmt": ("Formate le Luau avec StyLua", [["stylua", "games"]]),
    "fmt-check": (
        "Echoue si le formatage n'est pas a jour",
        [["stylua", "--check", "games"]],
    ),
    "lint": (
        "StyLua + Selene",
        [["stylua", "--check", "games"], ["selene", "games"]],
    ),
    "build": (
        "Construit build/<slug>.rbxl",
        [PY + ["tools/publish.py", "--dry-run"]],
    ),
    "wheel": (
        "Regenere l'image de la roue depuis GameConfig",
        [PY + ["tools/gen_wheel.py"]],
    ),
    "test": (
        "Publie une version Saved et y execute la suite de tests",
        [PY + ["tools/test.py"]],
    ),
    "assets": (
        "Resout assets/manifest.json et injecte les IDs",
        [PY + ["tools/assets.py"]],
    ),
    "products": (
        "Cree/met a jour les Developer Products et Game Passes",
        [PY + ["tools/products.py"]],
    ),
    "publish": (
        "Envoie une version Saved (non live) sur la place",
        [PY + ["tools/publish.py"]],
    ),
    "publish-live": (
        "Envoie une version Published (visible par les joueurs)",
        [PY + ["tools/publish.py", "--live"]],
    ),
    "reset": (
        "Supprime une sauvegarde (klin.py reset -- --username X). DEFINITIF",
        [PY + ["tools/reset_profile.py"]],
    ),
    "analytics": (
        "Ecrit un rapport dans reports/ (klin.py analytics -- --slug <slug>)",
        [PY + ["tools/analytics.py"]],
    ),
    "clean": ("Supprime les artefacts de build", []),
}


def show_help() -> int:
    print("Usage : python tools/klin.py <cible> [-- args...]\n")
    print("Cibles :")
    for name, (description, _) in TARGETS.items():
        print(f"  {name:<14} {description}")
    return 0


def run(command: list[str]) -> int:
    """Execute une commande, avec un message clair si l'outil manque."""
    if command[0] != sys.executable:
        # find_tool retombe sur ~/.rokit/bin, que Rokit n'ajoute au PATH
        # qu'apres `rokit self-install`, et seulement pour les terminaux
        # ouverts ensuite. Sans ce repli, le pipeline echoue en "rojo
        # introuvable" sur une machine ou tout est pourtant installe.
        resolved = common.find_tool(command[0])
        if resolved is None:
            print(
                f"[err]  '{command[0]}' introuvable, ni dans le PATH ni dans "
                f"~/.rokit/bin.\n"
                f"       -> lance d'abord : python tools/klin.py install",
                file=sys.stderr,
            )
            return 127
        command = [resolved] + command[1:]

    print(f"[run]  {' '.join(command)}", file=sys.stderr, flush=True)
    return subprocess.run(command, cwd=ROOT).returncode


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help", "help"):
        return show_help()

    target = argv[0]
    extra = argv[argv.index("--") + 1:] if "--" in argv else []

    if target not in TARGETS:
        print(f"[err]  cible inconnue : {target}\n", file=sys.stderr)
        return show_help() or 2

    if target == "clean":
        shutil.rmtree(ROOT / "build", ignore_errors=True)
        (ROOT / "sourcemap.json").unlink(missing_ok=True)
        print("[ok]   build/ et sourcemap.json supprimes", file=sys.stderr)
        return 0

    _, commands = TARGETS[target]
    for index, command in enumerate(commands):
        # Les arguments supplementaires vont a la derniere commande de la cible.
        full = command + extra if index == len(commands) - 1 else command
        if target == "build":
            BUILD.parent.mkdir(parents=True, exist_ok=True)
        code = run(full)
        if code != 0:
            return code

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
