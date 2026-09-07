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

def assets_lock(game: Path) -> Path:
    return game / "assets" / "assets.lock.json"


def products_lock(game: Path) -> Path:
    return game / "assets" / "products.lock.json"


def config_file(game: Path) -> Path:
    return game / "src" / "shared" / "Config.luau"

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


def generate(game: Path) -> Path:
    """Reconstruit Config.luau. Retourne le chemin ecrit."""
    locks = common.read_json(assets_lock(game), default={}) or {}
    products = common.read_json(products_lock(game), default={}) or {}

    # Les assets sont exposes comme des chaines rbxassetid:// directement
    # utilisables (Image, Sound.SoundId...), pas comme des nombres nus.
    assets = {
        key: f'"rbxassetid://{entry["assetId"]}"'
        for key, entry in sorted(locks.items())
        if entry.get("assetId")
    }

    # Les produits sont des nombres : MarketplaceService les veut ainsi.
    product_ids = {
        key: str(entry["productId"])
        for key, entry in sorted(products.get("developerProducts", {}).items())
        if entry.get("productId")
    }
    passes = {
        key: str(entry["gamePassId"])
        for key, entry in sorted(products.get("gamePasses", {}).items())
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
        + _render_table("developerProducts", product_ids, "cle logique -> productId")
        + _render_table("gamePasses", passes, "cle logique -> gamePassId")
        + "}\n\nreturn table.freeze(Config)\n"
    )

    target = config_file(game)
    target.parent.mkdir(parents=True, exist_ok=True)
    # newline explicite : sur Windows, Python traduirait les sauts de ligne
    # en CRLF, que stylua.toml (line_endings = "Unix") rejette au make lint.
    with target.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(body)

    common.ok(
        f"Config.luau regenere : {len(assets)} asset(s), "
        f"{len(product_ids)} produit(s), {len(passes)} game pass(es)"
    )
    return target


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Regenere Config.luau.")
    common.add_game_arg(parser)
    generate(common.resolve_game(parser.parse_args().game))
