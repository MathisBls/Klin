"""Genere src/shared/Config.luau a partir des fichiers lock.

Pourquoi passer par des locks plutot que d'editer Config.luau directement :
`assets.py` et `products.py` ecrivent chacun leur partie, a des moments
differents. S'ils patchaient le meme fichier Luau, le second effacerait le
premier. Chacun ecrit donc son lock JSON, et ce module reconstruit Config.luau
entierement a partir des deux. L'ordre d'execution n'a plus d'importance.

Les locks sont versionnes dans git : ils sont la memoire du pipeline (quel ID
Roblox correspond a quelle cle logique), sans quoi chaque run recreerait des
produits en double.
"""

from __future__ import annotations

from pathlib import Path

import common

ASSETS_LOCK = common.ROOT / "assets" / "assets.lock.json"
PRODUCTS_LOCK = common.ROOT / "assets" / "products.lock.json"
CONFIG_FILE = common.ROOT / "src" / "shared" / "Config.luau"

HEADER = """--!strict
--[[
	FICHIER GENERE - ne pas editer a la main.
	Regenere par `make assets` et `make products` depuis :
	  assets/assets.lock.json
	  assets/products.lock.json
]]
"""


def _luau_key(key: str) -> str:
    """Rend une cle utilisable comme identifiant Luau, sinon la met en crochets."""
    if key.isidentifier() and not key[0].isdigit():
        return key
    escaped = key.replace("\\", "\\\\").replace('"', '\\"')
    return f'["{escaped}"]'


def _render_table(name: str, entries: dict[str, str], comment: str) -> str:
    """Rend une sous-table Luau triee, ou une table vide commentee."""
    if not entries:
        return f"\t-- {comment}\n\t{name} = {{}},\n"

    lines = [f"\t-- {comment}", f"\t{name} = {{"]
    for key in sorted(entries):
        lines.append(f"\t\t{_luau_key(key)} = {entries[key]},")
    lines.append("\t},")
    return "\n".join(lines) + "\n"


def generate() -> Path:
    """Reconstruit Config.luau. Retourne le chemin ecrit."""
    assets_lock: dict = common.read_json(ASSETS_LOCK, default={}) or {}
    products_lock: dict = common.read_json(PRODUCTS_LOCK, default={}) or {}

    # Les assets sont exposes comme des chaines rbxassetid:// directement
    # utilisables (Image, Sound.SoundId...), pas comme des nombres nus.
    assets = {
        key: f'"rbxassetid://{entry["assetId"]}"'
        for key, entry in sorted(assets_lock.items())
        if entry.get("assetId")
    }

    # Les produits sont des nombres : MarketplaceService les veut ainsi.
    products = {
        key: str(entry["productId"])
        for key, entry in sorted(products_lock.get("developerProducts", {}).items())
        if entry.get("productId")
    }
    passes = {
        key: str(entry["gamePassId"])
        for key, entry in sorted(products_lock.get("gamePasses", {}).items())
        if entry.get("gamePassId")
    }

    body = (
        HEADER
        + "\nexport type Config = {\n"
        "\tassets: { [string]: string },\n"
        "\tdeveloperProducts: { [string]: number },\n"
        "\tgamePasses: { [string]: number },\n"
        "}\n\n"
        "local Config: Config = {\n"
        + _render_table("assets", assets, "cle logique -> rbxassetid://")
        + _render_table("developerProducts", products, "cle logique -> productId")
        + _render_table("gamePasses", passes, "cle logique -> gamePassId")
        + "}\n\nreturn table.freeze(Config)\n"
    )

    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(body, encoding="utf-8")

    common.ok(
        f"Config.luau regenere : {len(assets)} asset(s), "
        f"{len(products)} produit(s), {len(passes)} game pass(es)"
    )
    return CONFIG_FILE


if __name__ == "__main__":
    generate()
