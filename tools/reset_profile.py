"""Remet a zero la sauvegarde d'un joueur.

Sert a retester l'onboarding : la spec vise un premier Marteau a 7 secondes,
un chiffre invérifiable une fois qu'on a 10 000 eclats en banque.

COMMENT

On n'attaque pas le DataStore directement. On execute un script Luau dans un
serveur Roblox via la Luau Execution API, et on laisse ProfileStore appeler
son propre RemoveAsync. Deux raisons :

  - pas de format de cle a deviner. ProfileStore sait ou il range ses
    profils ; nous, on ne ferait que supposer, et une supposition fausse
    supprimerait la mauvaise cle ou rien du tout.
  - le scope Open Cloud universe-datastores devient inutile : celui de la
    Luau Execution suffit, et il est deja accorde.

ATTENTION

La suppression est definitive, ProfileStore le dit explicitement : "with no
way to recover it". Le joueur ne doit pas etre connecte : une session active
tient un verrou, et il reecrirait ses anciennes donnees en partant.

Usage :
    python tools/reset_profile.py --username Asukyy
    python tools/reset_profile.py --user 1234567
    python tools/reset_profile.py --username Asukyy --dry-run
"""

from __future__ import annotations

import argparse
import json
import urllib.error
from pathlib import Path
import urllib.request

import common
import test as test_runner

# Doit rester aligne avec STORE_NAME dans src/server/systems/Save.luau.
# Si les deux divergent, ce script vide un store qui n'est pas celui du jeu
# et ne supprime donc rien - en affichant pourtant un succes.
STORE_NAME = "ForgeClicker_v1"

RESET_SCRIPT = """
local ServerScriptService = game:GetService("ServerScriptService")
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local store = ProfileStore.New("{store_name}", {{}})
local key = "player_{user_id}"

print("suppression de " .. key .. " dans {store_name}")

local removed = store:RemoveAsync(key)
if removed then
	print("[ok] profil supprime")
else
	warn("[echec] RemoveAsync a renvoye false")
	error("suppression refusee")
end
"""


def resolve_username(username: str) -> int:
    """Resout un pseudo Roblox en userId via l'API publique (sans cle)."""
    request = urllib.request.Request(
        "https://users.roblox.com/v1/usernames/users",
        data=json.dumps(
            {"usernames": [username], "excludeBannedUsers": False}
        ).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        common.fail(f"resolution du pseudo impossible : {exc}")

    matches = payload.get("data") or []
    if not matches:
        common.fail(f"aucun compte Roblox nomme '{username}'")

    found = matches[0]
    common.info(f"{found['name']} -> userId {found['id']}")
    return int(found["id"])


def verify_store_name(game: Path) -> None:
    """Compare STORE_NAME au nom reellement utilise par le jeu.

    Une divergence ferait vider un store vide en annoncant un succes, ce qui
    est pire qu'une erreur : on croirait la sauvegarde remise a zero.
    """
    source = game / "src" / "server" / "systems" / "Save.luau"
    if not source.is_file():
        common.warn("Save.luau introuvable, nom de store non verifie")
        return

    text = source.read_text(encoding="utf-8")
    marker = 'local STORE_NAME = "'
    if marker not in text:
        common.warn("STORE_NAME introuvable dans Save.luau, verification ignoree")
        return

    actual = text.split(marker, 1)[1].split('"', 1)[0]
    if actual != STORE_NAME:
        common.fail(
            f"desynchronisation : Save.luau utilise '{actual}' mais ce script "
            f"vise '{STORE_NAME}'.\n"
            f"       -> aligne STORE_NAME dans tools/reset_profile.py"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Supprime definitivement la sauvegarde d'un joueur."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--user", type=int, help="userId Roblox")
    group.add_argument("--username", help="pseudo Roblox, resolu en userId")
    parser.add_argument(
        "--version",
        type=int,
        help="version de la place a utiliser (defaut : publie une version Saved)",
    )
    common.add_game_arg(parser)
    common.add_common_args(parser)
    args = parser.parse_args()

    game = common.resolve_game(args.game)
    verify_store_name(game)

    cfg = common.load_config(
        require=("ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID")
    )

    user_id = args.user or resolve_username(args.username)

    common.warn(
        f"suppression DEFINITIVE du profil {user_id} dans '{STORE_NAME}'. "
        f"Le joueur ne doit pas etre connecte : une session active tient un "
        f"verrou et reecrirait ses anciennes donnees en partant."
    )

    if args.dry_run:
        common.ok("dry-run : rien n'a ete supprime")
        common.emit({"dryRun": True, "userId": user_id}, args.as_json)
        return 0

    script = RESET_SCRIPT.format(store_name=STORE_NAME, user_id=user_id)
    version = args.version or test_runner.publish_test_version(
        cfg, game, common.ROOT / "build" / f"{game.name}.rbxl"
    )

    api = common.OpenCloud(cfg)

    try:
        task_path = test_runner.create_task(api, cfg, version, script)
        task = test_runner.wait_for_task(api, task_path)
        logs = test_runner.fetch_logs(api, task_path)
    except common.ApiError as exc:
        common.error(str(exc))
        common.fail(exc.explain())
        raise AssertionError("unreachable")

    for line in logs:
        common.info(f"  {line}")

    if task.get("state") != "COMPLETE":
        error = task.get("error") or {}
        common.error(f"suppression en echec : {error.get('message', task.get('state'))}")
        common.emit({"ok": False, "userId": user_id}, args.as_json)
        return 1

    common.ok(f"profil {user_id} supprime - reconnecte-toi pour repartir de zero")
    common.emit({"ok": True, "userId": user_id}, args.as_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
