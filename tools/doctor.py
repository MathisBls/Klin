"""Diagnostic de la cle Open Cloud : quels scopes sont presents, lesquels manquent.

Tout est en lecture seule - ce script n'ecrit jamais rien sur Roblox.
Pour chaque etape du pipeline, on tape l'endpoint le moins couteux du meme
domaine de permission et on interprete le code HTTP :

    200/404 -> le scope est present (404 = scope ok, ressource inexistante)
    401     -> la cle elle-meme est invalide
    403     -> le scope manque, ou une restriction IP bloque la cle

Usage :
    python tools/doctor.py
    python tools/doctor.py --json
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from typing import Any, Callable

import common


@dataclass
class Check:
    """Un scope a verifier, et comment le verifier."""

    key: str
    label: str
    scope: str
    needed_by: str
    probe: Callable[[common.OpenCloud, common.Config], Any]
    requires: tuple[str, ...] = ()

    # Message affiche quand la sonde passe. Une sonde en lecture ne prouve
    # jamais que le scope :write est accorde - il faut le dire.
    on_success: str = "scope accorde"

    # Rempli a l'execution
    status: str = field(default="", init=False)
    detail: str = field(default="", init=False)


# --------------------------------------------------------------------------
# Sondes (toutes en GET/POST de lecture)
# --------------------------------------------------------------------------

def _probe_universe(api: common.OpenCloud, cfg: common.Config) -> Any:
    return api.request("GET", f"/cloud/v2/universes/{cfg.universe_id}")


def _probe_place(api: common.OpenCloud, cfg: common.Config) -> Any:
    return api.request(
        "GET", f"/cloud/v2/universes/{cfg.universe_id}/places/{cfg.place_id}"
    )


def _probe_assets(api: common.OpenCloud, _cfg: common.Config) -> Any:
    # On lit un asset qui n'existe pas : 404 prouve que le scope passe,
    # 403 prouve qu'il manque. Aucun asset reel n'est touche.
    return api.request("GET", "/assets/v1/assets/1")


def _probe_luau_execution(api: common.OpenCloud, cfg: common.Config) -> Any:
    # Meme un GET sur une tache inexistante exige le scope :write. C'est donc
    # la seule sonde du lot qui valide reellement une permission d'ecriture,
    # sans rien executer.
    return api.request(
        "GET",
        f"/cloud/v2/universes/{cfg.universe_id}/places/{cfg.place_id}"
        f"/versions/1/luau-execution-sessions/none/tasks/none",
    )


def _probe_products(api: common.OpenCloud, cfg: common.Config) -> Any:
    return api.request(
        "GET",
        f"/developer-products/v2/universes/{cfg.universe_id}/developer-products/creator",
        query={"maxPageSize": 1},
    )


def _probe_analytics(api: common.OpenCloud, cfg: common.Config) -> Any:
    return api.request(
        "POST",
        f"/analytics-query-api/v1/universes/{cfg.universe_id}/metrics",
        body={
            "metric": "DailyActiveUsers",
            "granularity": "OneDay",
            "startTime": "2026-01-01T00:00:00Z",
            "endTime": "2026-01-02T00:00:00Z",
        },
    )


CHECKS: list[Check] = [
    Check(
        key="universe",
        label="Univers lisible",
        scope="universe:read",
        needed_by="toutes les etapes",
        probe=_probe_universe,
        requires=("ROBLOX_UNIVERSE_ID",),
    ),
    Check(
        key="place",
        label="Place (lecture)",
        scope="universe-places:read",
        needed_by="make publish",
        probe=_probe_place,
        requires=("ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID"),
        on_success="lecture OK - :write non verifiable sans publier",
    ),
    Check(
        key="assets",
        label="Assets (lecture)",
        scope="asset:read",
        needed_by="make assets",
        probe=_probe_assets,
        on_success="lecture OK - :write non verifiable sans uploader",
    ),
    Check(
        key="luau-execution",
        label="Luau Execution",
        scope="universe.place.luau-execution-session:write",
        needed_by="make test",
        probe=_probe_luau_execution,
        requires=("ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID"),
        on_success="ecriture OK (seul scope :write verifiable a vide)",
    ),
    Check(
        key="products",
        label="Developer Products",
        scope="universe.developer-product:read / :write",
        needed_by="make products",
        probe=_probe_products,
        requires=("ROBLOX_UNIVERSE_ID",),
    ),
    Check(
        key="analytics",
        label="Analytics",
        scope="universe-analytics:read",
        needed_by="make analytics",
        probe=_probe_analytics,
        requires=("ROBLOX_UNIVERSE_ID",),
    ),
]


# --------------------------------------------------------------------------

STATUS_LABEL = {
    "ok": "OK      ",
    "missing": "MANQUANT",
    "invalid": "CLE KO  ",
    "skipped": "IGNORE  ",
    "unknown": "?       ",
}


ENV_TO_FIELD = {
    "ROBLOX_UNIVERSE_ID": "universe_id",
    "ROBLOX_PLACE_ID": "place_id",
}


def run_check(check: Check, api: common.OpenCloud, cfg: common.Config) -> None:
    """Execute une sonde et classe le resultat."""
    absent = [
        name for name in check.requires if not getattr(cfg, ENV_TO_FIELD[name], "")
    ]
    if absent:
        check.status = "skipped"
        check.detail = "manque dans .env : " + ", ".join(absent)
        return

    try:
        check.probe(api, cfg)
        check.status = "ok"
        check.detail = check.on_success
    except common.ApiError as exc:
        if exc.is_scope_problem:
            check.status = "missing"
            check.detail = exc.explain()
        elif exc.status == 401:
            check.status = "invalid"
            check.detail = exc.explain()
        elif exc.status == 404:
            # Le scope a laisse passer la requete ; la ressource n'existe pas.
            check.status = "ok"
            check.detail = "scope accorde (ressource sonde inexistante, normal)"
        elif exc.status == 400:
            # Requete refusee sur le fond, donc l'autorisation est passee.
            check.status = "ok"
            check.detail = "scope accorde (parametres de sonde refuses, normal)"
        else:
            check.status = "unknown"
            check.detail = f"HTTP {exc.status} - {exc.explain()}"
    except Exception as exc:  # reseau, timeout...
        check.status = "unknown"
        check.detail = str(exc)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verifie la cle Open Cloud et ses scopes (lecture seule)."
    )
    common.add_common_args(parser)
    args = parser.parse_args()

    cfg = common.load_config(require=("ROBLOX_API_KEY",))
    api = common.OpenCloud(cfg)  # jamais dry_run : tout est deja en lecture

    common.info("verification de la cle Open Cloud (aucune ecriture)")
    for name, value in (
        ("ROBLOX_UNIVERSE_ID", cfg.universe_id),
        ("ROBLOX_PLACE_ID", cfg.place_id),
    ):
        if not value:
            common.warn(f"{name} vide - les tests qui en dependent seront ignores")

    for check in CHECKS:
        run_check(check, api, cfg)

    print("", file=sys.stderr)
    for check in CHECKS:
        line = (
            f"  {STATUS_LABEL[check.status]}  {check.label:<22} "
            f"{check.scope:<40} {check.detail}"
        )
        print(line, file=sys.stderr)
    print("", file=sys.stderr)

    blocked = [c for c in CHECKS if c.status in ("missing", "invalid")]
    if any(c.status == "invalid" for c in CHECKS):
        common.error(
            "la cle API est rejetee (401). Regenere-la sur "
            "https://create.roblox.com/dashboard/credentials"
        )
    elif blocked:
        common.error("scopes manquants - a ajouter sur la cle :")
        for check in blocked:
            common.error(f"    {check.scope}  (bloque : {check.needed_by})")
        common.error(
            "  Creator Dashboard > Open Cloud > API Keys > ta cle > "
            "ajoute l'univers et coche les permissions ci-dessus."
        )
    else:
        common.ok("tous les scopes testables en lecture sont accordes")
        common.warn(
            "les scopes :write (universe-places:write, asset:write, "
            "developer-product:write) ne peuvent pas etre verifies sans "
            "ecrire sur Roblox - coche-les aussi, sinon `make publish` "
            "echouera en 401 'insufficient scopes'"
        )

    common.emit(
        {
            "ok": not blocked,
            "checks": [
                {
                    "key": c.key,
                    "scope": c.scope,
                    "status": c.status,
                    "detail": c.detail,
                    "neededBy": c.needed_by,
                }
                for c in CHECKS
            ],
        },
        args.as_json,
    )

    return 1 if blocked else 0


if __name__ == "__main__":
    raise SystemExit(main())
