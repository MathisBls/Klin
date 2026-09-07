"""Cherche de vrais assets sur le Creator Store, et verifie qu'ils existent.

POURQUOI CET OUTIL EXISTE

CLAUDE.md pose une regle : "ne jamais inventer un ID d'asset : soit resolu
par l'API, soit demande". Sans cet outil, la seule facon de decorer une map
etait d'empiler des Parts primitives - ce qui donne exactement le rendu
qu'on cherche a eviter.

Ici, tout ID vient d'une recherche reelle et est reverifie avant d'entrer
dans un manifest. Un ID trouve dans un tutoriel ou devine de tete n'a rien
a faire dans le repo.

SECURITE : LES SCRIPTS DES MODELES GRATUITS

Un modele gratuit peut contenir des scripts. C'est le vecteur de backdoor le
plus courant sur Roblox : le modele est joli, et un Script planque dedans
donne un acces admin a son auteur des que le jeu tourne. La recherche ecarte
donc par defaut tout modele dont `hasScripts` est vrai. `--allow-scripts`
existe, mais il n'y a aucune bonne raison de s'en servir pour du decor.

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
    """Aplatit un resultat de recherche en ce qui sert a decider."""
    asset = entry.get("asset") or {}
    creator = entry.get("creator") or {}
    voting = entry.get("voting") or {}
    mesh = asset.get("objectMeshSummary") or {}
    counts = asset.get("instanceCounts") or {}

    return {
        "id": asset.get("id"),
        "name": asset.get("name") or "?",
        "creator": creator.get("name") or "?",
        "creatorVerified": bool(creator.get("verified")),
        # hasScripts est le champ le plus important de tout ce fichier.
        # Voir la note de securite dans l'en-tete du module.
        "hasScripts": bool(asset.get("hasScripts")) or (asset.get("scriptCount") or 0) > 0,
        "scriptCount": asset.get("scriptCount") or 0,
        "triangles": mesh.get("triangles") or 0,
        "meshParts": counts.get("meshPart") or 0,
        "upVotePercent": voting.get("upVotePercent"),
        "voteCount": voting.get("voteCount") or 0,
        "category": asset.get("categoryPath") or "",
    }


def quality_score(info: dict[str, Any]) -> float:
    """Classe les candidats : approbation, volume de votes, createur verifie.

    Un modele a 95 % d'approbation sur 8 votes est moins sur qu'un modele a
    85 % sur 900. On pondere donc l'approbation par le volume.
    """
    approval = info.get("upVotePercent")
    votes = info.get("voteCount") or 0

    if approval is None:
        return 0.0

    confidence = min(1.0, votes / 200.0)
    score = approval * confidence
    if info.get("creatorVerified"):
        score += 5
    return score


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

    rows = [describe(entry) for entry in results]

    scripted = [row for row in rows if row["hasScripts"]]
    if scripted and not args.allow_scripts:
        common.warn(
            f"{len(scripted)} modele(s) ecartes car ils contiennent des scripts "
            f"(vecteur classique de backdoor) : "
            + ", ".join(str(row["id"]) for row in scripted[:6])
        )
        rows = [row for row in rows if not row["hasScripts"]]

    if args.max_triangles:
        heavy = [row for row in rows if row["triangles"] > args.max_triangles]
        if heavy:
            common.warn(
                f"{len(heavy)} modele(s) ecartes au-dela de "
                f"{args.max_triangles} triangles"
            )
            rows = [row for row in rows if row["triangles"] <= args.max_triangles]

    rows.sort(key=quality_score, reverse=True)

    if not rows:
        common.warn("tous les resultats ont ete filtres")
        common.emit({"results": []}, args.as_json)
        return 0

    common.ok(f"{len(rows)} candidat(s) pour '{args.query}', du meilleur au moins bon :")
    common.info(f"  {'id':<18} {'nom':<40} {'tris':>8} {'appro':>7} {'votes':>7}  createur")

    for row in rows:
        approval = f"{row['upVotePercent']}%" if row["upVotePercent"] is not None else "-"
        common.info(
            f"  {str(row['id']):<18} {row['name'][:38]:<40} "
            f"{row['triangles']:>8} {approval:>7} {row['voteCount']:>7}  "
            f"{row['creator'][:18]}{' (verifie)' if row['creatorVerified'] else ''}"
        )

    common.warn(
        "aucun de ces IDs n'entre dans un manifest avant "
        "`store_search.py verify <ids>`, puis un test de chargement en jeu"
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
    finder.add_argument(
        "--allow-scripts",
        action="store_true",
        help="NE PAS UTILISER sans raison : garde les modeles contenant des "
        "scripts, principal vecteur de backdoor sur Roblox",
    )
    finder.add_argument(
        "--max-triangles",
        type=int,
        default=200000,
        help="ecarte les modeles trop lourds (defaut : 200 000)",
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
