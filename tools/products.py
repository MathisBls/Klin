"""Cree et met a jour les Developer Products et Game Passes via Open Cloud.

Source de verite : assets/products.json (versionne, ecrit a la main ou par le
generateur de jeu). Ce script le rapproche de l'etat reel sur Roblox et ecrit
les IDs obtenus dans assets/products.lock.json, puis regenere Config.luau.

Regle qui gouverne tout le fichier : on ne cree jamais deux fois le meme
produit. Un produit deja dans le lock est mis a jour (PATCH), pas recree.
Un produit absent du lock mais deja present sur Roblox sous le meme nom est
adopte plutot que duplique - sans quoi chaque run gonflerait la boutique.

Les deux APIs attendent du multipart/form-data, pas du JSON.

Usage :
    python tools/products.py
    python tools/products.py --dry-run
"""

from __future__ import annotations

import argparse
from typing import Any

import common
import config_gen

CATALOG = common.ROOT / "assets" / "products.json"
LOCK = config_gen.PRODUCTS_LOCK

# Les deux familles ne different que par leurs chemins et le nom de leur ID.
FAMILIES: dict[str, dict[str, str]] = {
    "developerProducts": {
        "label": "developer product",
        "collection": "/developer-products/v2/universes/{universe}/developer-products",
        "list": "/developer-products/v2/universes/{universe}/developer-products/creator",
        "item": "/developer-products/v2/universes/{universe}"
        "/developer-products/{id}",
        "id_field": "productId",
    },
    "gamePasses": {
        "label": "game pass",
        "collection": "/game-passes/v1/universes/{universe}/game-passes",
        "list": "/game-passes/v1/universes/{universe}/game-passes/creator",
        "item": "/game-passes/v1/universes/{universe}/game-passes/{id}",
        "id_field": "gamePassId",
    },
}


def load_catalog() -> dict[str, dict[str, Any]]:
    """Lit et valide assets/products.json."""
    data = common.read_json(CATALOG, default={"developerProducts": {}, "gamePasses": {}})

    for family in FAMILIES:
        entries = data.get(family, {})
        if not isinstance(entries, dict):
            common.fail(f"'{family}' doit etre un objet {{ cle: definition }}")

        for key, entry in entries.items():
            if not entry.get("name"):
                common.fail(f"{family}.{key} : champ 'name' obligatoire")
            price = entry.get("price")
            if price is not None and (not isinstance(price, int) or price < 0):
                common.fail(
                    f"{family}.{key} : 'price' doit etre un entier de Robux >= 0"
                )

    return data


def to_form(entry: dict[str, Any]) -> dict[str, str]:
    """Traduit une entree du catalogue en champs multipart.

    Les booleens partent en 'true'/'false' : un formulaire ne transporte
    que du texte, et Roblox refuse 'True' avec une majuscule.
    """
    form: dict[str, str] = {"name": entry["name"]}

    if entry.get("description"):
        form["description"] = entry["description"]
    if entry.get("price") is not None:
        form["price"] = str(entry["price"])

    # Un produit sans prix explicite ne doit pas se retrouver en vente a 0 R$.
    for_sale = entry.get("isForSale", entry.get("price") is not None)
    form["isForSale"] = "true" if for_sale else "false"

    if entry.get("isRegionalPricingEnabled") is not None:
        form["isRegionalPricingEnabled"] = (
            "true" if entry["isRegionalPricingEnabled"] else "false"
        )

    return form


def list_existing(
    api: common.OpenCloud, cfg: common.Config, family: str
) -> dict[str, int]:
    """Renvoie {nom: id} de ce qui existe deja sur Roblox, pour ne pas dupliquer."""
    spec = FAMILIES[family]
    id_field = spec["id_field"]
    found: dict[str, int] = {}
    cursor: str | None = None

    while True:
        response = api.request(
            "GET",
            spec["list"].format(universe=cfg.universe_id),
            query={"maxPageSize": 100, "pageToken": cursor},
        )
        if not isinstance(response, dict):
            break

        # Le nom du tableau varie selon la famille : on prend le premier
        # champ qui est une liste plutot que de coder son nom en dur.
        items: list[dict[str, Any]] = next(
            (value for value in response.values() if isinstance(value, list)), []
        )
        for item in items:
            if item.get("name") and item.get(id_field):
                found[item["name"]] = int(item[id_field])

        cursor = response.get("nextPageToken") or None
        if not cursor:
            break

    return found


def create(
    api: common.OpenCloud, cfg: common.Config, family: str, entry: dict[str, Any]
) -> int | None:
    """Cree le produit. Renvoie son ID, ou None en dry-run."""
    spec = FAMILIES[family]
    body, content_type = common.encode_multipart(to_form(entry), files={})

    response = api.request(
        "POST",
        spec["collection"].format(universe=cfg.universe_id),
        raw_body=body,
        content_type=content_type,
    )
    if api.dry_run:
        return None

    product_id = response.get(spec["id_field"])
    if not product_id:
        common.fail(f"creation sans {spec['id_field']} -> {response}")
    return int(product_id)


def update(
    api: common.OpenCloud,
    cfg: common.Config,
    family: str,
    product_id: int,
    entry: dict[str, Any],
) -> None:
    """Met a jour un produit existant. L'API repond 204, sans corps."""
    spec = FAMILIES[family]
    body, content_type = common.encode_multipart(to_form(entry), files={})

    api.request(
        "PATCH",
        spec["item"].format(universe=cfg.universe_id, id=product_id),
        raw_body=body,
        content_type=content_type,
        expect_json=False,
    )


def sync_family(
    api: common.OpenCloud,
    cfg: common.Config,
    family: str,
    catalog: dict[str, Any],
    lock: dict[str, Any],
) -> tuple[dict[str, Any], int, int]:
    """Rapproche une famille du catalogue. Renvoie (lock, crees, mis a jour)."""
    spec = FAMILIES[family]
    entries = catalog.get(family, {})
    previous = lock.get(family, {})
    resolved: dict[str, Any] = {}
    created = updated = 0

    if not entries:
        return resolved, 0, 0

    # Une seule liste pour toute la famille, pour ne pas payer un appel par cle.
    existing = {} if api.dry_run else list_existing(api, cfg, family)

    for key, entry in sorted(entries.items()):
        known_id = previous.get(key, {}).get(spec["id_field"])

        # Deja sur Roblox sous ce nom mais absent du lock : on l'adopte.
        if not known_id and entry["name"] in existing:
            known_id = existing[entry["name"]]
            common.warn(
                f"{family}.{key} : {spec['label']} '{entry['name']}' existait "
                f"deja sur Roblox (id {known_id}) - adopte au lieu d'etre recree"
            )

        if known_id:
            common.info(f"{family}.{key} -> maj de {spec['label']} {known_id}")
            if not api.dry_run:
                update(api, cfg, family, int(known_id), entry)
            updated += 1
            product_id = int(known_id)
        else:
            common.info(f"{family}.{key} -> creation de {spec['label']}")
            new_id = create(api, cfg, family, entry)
            if new_id is None:  # dry-run
                continue
            common.ok(f"{family}.{key} -> {new_id}")
            created += 1
            product_id = new_id

        resolved[key] = {
            spec["id_field"]: product_id,
            "name": entry["name"],
            "price": entry.get("price"),
        }

    # Une cle retiree du catalogue laisse un produit vivant sur Roblox :
    # l'API ne sait pas supprimer un produit, donc on se contente d'alerter.
    for key in previous:
        if key not in entries:
            common.warn(
                f"{family}.{key} n'est plus dans products.json mais existe "
                f"toujours sur Roblox (id {previous[key].get(spec['id_field'])}) - "
                f"a desactiver a la main depuis le Creator Dashboard"
            )

    return resolved, created, updated


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Synchronise les Developer Products et Game Passes."
    )
    common.add_common_args(parser)
    args = parser.parse_args()

    catalog = load_catalog()
    if not any(catalog.get(family) for family in FAMILIES):
        common.info("aucun produit declare dans assets/products.json")
        config_gen.generate()
        common.emit({"created": 0, "updated": 0}, args.as_json)
        return 0

    cfg = common.load_config(require=("ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID"))
    api = common.OpenCloud(cfg, dry_run=args.dry_run)
    lock: dict[str, Any] = common.read_json(LOCK, default={}) or {}

    result: dict[str, Any] = {}
    total_created = total_updated = 0

    try:
        for family in FAMILIES:
            resolved, created, updated = sync_family(api, cfg, family, catalog, lock)
            result[family] = resolved
            total_created += created
            total_updated += updated
    except common.ApiError as exc:
        common.error(str(exc))
        common.fail(exc.explain())

    if args.dry_run:
        common.ok("dry-run termine, rien n'a ete cree ni modifie")
        common.emit({"dryRun": True}, args.as_json)
        return 0

    common.write_json(LOCK, result)
    config_gen.generate()

    common.ok(f"{total_created} cree(s), {total_updated} mis a jour")
    common.emit(
        {"created": total_created, "updated": total_updated, **result}, args.as_json
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
