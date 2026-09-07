"""Cherche de vrais assets sur le Creator Store, et verifie qu'ils existent.

POURQUOI CET OUTIL EXISTE

CLAUDE.md pose une regle : "ne jamais inventer un ID d'asset : soit resolu
par l'API, soit demande". Sans cet outil, la seule facon de decorer une map
etait d'empiler des Parts primitives - ce qui donne exactement le rendu
qu'on cherche a eviter.

Ici, tout ID vient d'une recherche reelle et est reverifie avant d'entrer
dans un manifest. Un ID trouve dans un tutoriel ou devine de tete n'a rien
a faire dans le repo.

DEUX ETAPES, JAMAIS UNE SEULE

  1. `search`  : interroge le Creator Store et affiche les candidats
  2. `verify`  : relit chaque ID retenu et confirme son type et son createur

La deuxieme etape n'est pas une formalite. Un ID peut disparaitre, passer
en payant, ou etre d'un type incompatible - un Model la ou on attend une
Mesh. Le decouvrir au build vaut mieux qu'en jeu.

Usage :
    python tools/store_search.py search --query "stadium" --type Model
    python tools/store_search.py search --query "tree" --free-only --limit 20
    python tools/store_search.py verify 1234567 7654321
"""

from __future__ import annotations

import argparse
import json
from typing import Any

import common

SEARCH_PATH = "/toolbox-service/v2/assets:search"

# searchCategoryType accepte par l'API. Restreint volontairement a ce qui
# sert a decorer une map : demander un type inconnu remonte un 400 opaque.
CATEGORIES = ("Model", "Mesh", "Image", "Audio", "Video", "Font", "Plugin")


def search(
    api: common.OpenCloud,
    query: str,
    category: str,
    limit: int,
    free_only: bool,
    verified_only: bool,
) -> list[dict[str, Any]]:
    """Interroge le Creator Store. Renvoie la liste brute des resultats."""
    body: dict[str, Any] = {
        "searchCategoryType": category,
        "query": query,
        "maxPageSize": min(limit, 100),
    }

    if free_only:
        # Un asset gratuit coute zero centime. Filtrer ici plutot qu'apres
        # coup evite de proposer des modeles qu'on ne peut pas utiliser.
        body["maxPriceCents"] = 0

    if verified_only:
        body["includeOnlyVerifiedCreators"] = True

    try:
        response = api.request("POST", SEARCH_PATH, body=body)
    except common.ApiError as exc:
        if exc.is_scope_problem:
            common.error(str(exc))
            common.fail(
                "le scope creator-store-product:read manque sur la cle.\n"
                "       -> Creator Dashboard > Open Cloud > API Keys > ta cle\n"
                "       -> ajoute le systeme 'creator-store-product', puis "
                "ouvre 'Select Operations to Add' et coche :read"
            )
        raise

    if not isinstance(response, dict):
        common.fail(f"reponse inattendue : {response}")

    # Le nom du tableau a change entre versions de l'API : on prend le
    # premier champ qui est une liste plutot que de coder son nom en dur.
    results = next(
        (value for value in response.values() if isinstance(value, list)), []
    )
    return results


def describe(entry: dict[str, Any]) -> dict[str, Any]:
    """Extrait les champs utiles, quelle que soit la forme exacte du JSON."""

    def dig(*names: str) -> Any:
        for name in names:
            if name in entry and entry[name] not in (None, ""):
                return entry[name]
        # Certaines versions imbriquent tout sous 'asset' ou 'product'.
        for container in ("asset", "product", "creator"):
            nested = entry.get(container)
            if isinstance(nested, dict):
                for name in names:
                    if nested.get(name) not in (None, ""):
                        return nested[name]
        return None

    return {
        "id": dig("assetId", "id"),
        "name": dig("name", "displayName"),
        "type": dig("assetType", "type"),
        "creator": dig("creatorName", "name") if entry.get("creator") else None,
        "priceCents": dig("priceCents", "price"),
    }


def verify(api: common.OpenCloud, asset_id: str) -> dict[str, Any] | None:
    """Relit un asset. Renvoie ses metadonnees, ou None s'il est inaccessible."""
    try:
        return api.request("GET", f"/assets/v1/assets/{asset_id}")
    except common.ApiError as exc:
        common.warn(f"{asset_id} : HTTP {exc.status} - {exc.explain()}")
        return None


def cmd_search(args, api: common.OpenCloud) -> int:
    results = search(
        api, args.query, args.type, args.limit, args.free_only, args.verified_only
    )

    if not results:
        common.warn(f"aucun resultat pour '{args.query}' en {args.type}")
        common.emit({"results": []}, args.as_json)
        return 0

    common.ok(f"{len(results)} resultat(s) pour '{args.query}' :")
    rows = []

    for entry in results:
        info = describe(entry)
        rows.append(info)
        price = info["priceCents"]
        label = "gratuit" if price in (0, None) else f"{price} cents"
        common.info(
            f"  {str(info['id']):<18} {str(info['name'])[:44]:<46} "
            f"{str(info['type'] or '?'):<8} {label}"
        )

    common.warn(
        "aucun de ces IDs n'entre dans un manifest avant "
        "`store_search.py verify <ids>`"
    )
    common.emit({"results": rows}, args.as_json)
    return 0


def cmd_verify(args, api: common.OpenCloud) -> int:
    verified, failed = [], []

    for asset_id in args.ids:
        metadata = verify(api, asset_id)
        if metadata is None:
            failed.append(asset_id)
            continue

        name = metadata.get("displayName") or "?"
        kind = metadata.get("assetType") or "?"
        common.ok(f"  {asset_id:<18} {name[:44]:<46} {kind}")
        verified.append({"assetId": asset_id, "displayName": name, "assetType": kind})

    if failed:
        common.error(f"{len(failed)} ID(s) inaccessibles : {', '.join(failed)}")

    common.emit({"verified": verified, "failed": failed}, args.as_json)
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Cherche et verifie des assets du Creator Store."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    finder = sub.add_parser("search", help="cherche des assets")
    finder.add_argument("--query", required=True, help="termes de recherche")
    finder.add_argument(
        "--type", default="Model", choices=CATEGORIES, help="type d'asset"
    )
    finder.add_argument("--limit", type=int, default=15)
    finder.add_argument(
        "--free-only", action="store_true", help="uniquement les assets gratuits"
    )
    finder.add_argument(
        "--verified-only",
        action="store_true",
        help="uniquement les createurs verifies",
    )
    common.add_common_args(finder)

    checker = sub.add_parser("verify", help="verifie que des IDs existent")
    checker.add_argument("ids", nargs="+", help="IDs d'assets a verifier")
    common.add_common_args(checker)

    args = parser.parse_args()

    cfg = common.load_config(require=("ROBLOX_API_KEY",))
    api = common.OpenCloud(cfg)

    if args.command == "search":
        return cmd_search(args, api)
    return cmd_verify(args, api)


if __name__ == "__main__":
    raise SystemExit(main())
