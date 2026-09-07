"""Genere assets/files/wheel.png depuis GameConfig.luau.

POURQUOI CE SCRIPT EXISTE

L'image de la roue et les poids du tirage doivent decrire la meme chose. Si
on redessine l'image a la main apres avoir change un poids, l'aiguille finit
par s'arreter sur un secteur qui n'est pas celui attribue - un bug que le
joueur vit comme "la roue m'a menti" et qu'aucun test de logique n'attrape.

Ce script lit donc les poids directement dans src/shared/config/GameConfig.luau.
Changer un poids et relancer `make wheel` suffit ; il n'y a rien a
synchroniser a la main.

Sortie PNG ecrite avec la seule stdlib (zlib + struct), pour ne pas imposer
Pillow au repo ni a la CI.

Usage :
    python tools/gen_wheel.py
    python tools/gen_wheel.py --size 1024
"""

from __future__ import annotations

import argparse
import math
import re
import struct
import zlib
from pathlib import Path

import common

# Chemins resolus par jeu.

# Cle de lot -> couleur du secteur. Doit rester identique a PRIZE_COLORS dans
# src/client/ui/WheelUI.luau, qui colore la legende : deux palettes
# divergentes rendraient la legende inutilisable.
COLORS: dict[str, tuple[int, int, int]] = {
    "HANDFUL": (78, 74, 84),
    "PURSE": (96, 116, 140),
    "CHEST": (88, 140, 104),
    "HEAVY_CHEST": (140, 108, 180),
    "EMBER": (214, 96, 40),
    "FORGE_HEART": (240, 190, 60),
}

FALLBACK = (90, 86, 96)
RIM_COLOR = (26, 24, 30)
SEPARATOR_COLOR = (18, 17, 21)

SEPARATOR_DEGREES = 0.9
RIM_RATIO = 0.032
SUPERSAMPLE = 3


def read_prizes(config: Path) -> list[tuple[str, float]]:
    """Extrait (cle, poids) de GameConfig.luau, dans l'ordre de declaration.

    On parse le Luau plutot que de dupliquer les valeurs ici : une copie
    finirait par diverger, et c'est precisement ce que ce script evite.
    """
    if not config.is_file():
        common.fail(f"{config.relative_to(common.ROOT)} introuvable")

    text = config.read_text(encoding="utf-8")

    start = text.find("prizes = {")
    if start == -1:
        common.fail("bloc 'prizes' introuvable dans GameConfig.luau")

    block = text[start:]
    prizes: list[tuple[str, float]] = []

    for match in re.finditer(
        r'key\s*=\s*"([A-Z_]+)"\s*,\s*displayName\s*=\s*"[^"]*"\s*,\s*weight\s*=\s*([\d.]+)',
        block,
    ):
        prizes.append((match.group(1), float(match.group(2))))

    if not prizes:
        common.fail("aucun lot lu dans GameConfig.luau - le format a-t-il change ?")

    return prizes


def build_sectors(prizes: list[tuple[str, float]]) -> list[dict]:
    """Convertit les poids en bornes angulaires, sens horaire, zero en haut."""
    total = sum(weight for _, weight in prizes)
    if total <= 0:
        common.fail("la somme des poids vaut zero")

    sectors: list[dict] = []
    cursor = 0.0

    for key, weight in prizes:
        sweep = weight / total * 360.0
        sectors.append(
            {
                "key": key,
                "start": cursor,
                "end": cursor + sweep,
                "color": COLORS.get(key, FALLBACK),
            }
        )
        cursor += sweep

    return sectors


def write_png(path: Path, size: int, pixels: bytearray) -> None:
    """Ecrit un PNG RGBA. Stdlib seule : pas de dependance a Pillow."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    # Chaque ligne est prefixee d'un octet de filtre (0 = aucun).
    raw = bytearray()
    stride = size * 4
    for y in range(size):
        raw.append(0)
        raw += pixels[y * stride : (y + 1) * stride]

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def render(sectors: list[dict], size: int) -> bytearray:
    """Rasterise le disque, avec supersampling pour lisser les bords."""
    center = size / 2.0
    radius = center - 2
    rim = radius * RIM_RATIO
    pixels = bytearray(size * size * 4)

    boundaries = [sector["start"] for sector in sectors]

    def sector_at(angle: float) -> dict:
        for sector in sectors:
            if sector["start"] <= angle < sector["end"]:
                return sector
        return sectors[-1]

    def near_boundary(angle: float) -> bool:
        for bound in boundaries:
            if abs(((angle - bound + 180.0) % 360.0) - 180.0) < SEPARATOR_DEGREES:
                return True
        return False

    step = 1.0 / SUPERSAMPLE
    samples = SUPERSAMPLE * SUPERSAMPLE

    for y in range(size):
        row = y * size * 4
        for x in range(size):
            red = green = blue = alpha = 0

            for sy in range(SUPERSAMPLE):
                for sx in range(SUPERSAMPLE):
                    dx = x + (sx + 0.5) * step - center
                    dy = y + (sy + 0.5) * step - center
                    distance = math.hypot(dx, dy)

                    if distance > radius:
                        continue

                    # atan2(dx, -dy) : zero vers le haut, croissant dans le
                    # sens horaire - la meme convention que l'aiguille.
                    angle = math.degrees(math.atan2(dx, -dy)) % 360.0

                    if distance > radius - rim:
                        colour = RIM_COLOR
                    elif near_boundary(angle):
                        colour = SEPARATOR_COLOR
                    else:
                        base = sector_at(angle)["color"]
                        # Degrade radial : le centre plus sombre donne du
                        # volume sans texture.
                        shade = 0.72 + 0.28 * (distance / radius)
                        colour = tuple(int(channel * shade) for channel in base)

                    red += colour[0]
                    green += colour[1]
                    blue += colour[2]
                    alpha += 255

            if alpha == 0:
                continue

            covered = alpha / 255
            offset = row + x * 4
            pixels[offset] = int(red / covered)
            pixels[offset + 1] = int(green / covered)
            pixels[offset + 2] = int(blue / covered)
            pixels[offset + 3] = int(alpha / samples)

    return pixels


def main() -> int:
    parser = argparse.ArgumentParser(description="Genere l'image de la roue.")
    parser.add_argument(
        "--size", type=int, default=512, help="cote de l'image (defaut : 512)"
    )
    parser.add_argument("--output", type=Path)
    common.add_game_arg(parser)
    common.add_common_args(parser)
    args = parser.parse_args()

    game = common.resolve_game(args.game)
    args.output = args.output or game / "assets" / "files" / "wheel.png"

    prizes = read_prizes(game / "src" / "shared" / "config" / "GameConfig.luau")
    sectors = build_sectors(prizes)

    common.info(f"{len(sectors)} secteurs lus dans GameConfig.luau :")
    for sector in sectors:
        common.info(
            f"  {sector['key']:<12} {sector['start']:6.1f} -> {sector['end']:6.1f} deg"
        )

    if args.dry_run:
        common.ok("dry-run : image non generee")
        common.emit({"dryRun": True, "sectors": len(sectors)}, args.as_json)
        return 0

    pixels = render(sectors, args.size)
    write_png(args.output, args.size, pixels)

    size_kb = args.output.stat().st_size / 1024
    common.ok(f"{args.output.relative_to(common.ROOT)} ecrit ({size_kb:.1f} Ko)")
    common.warn("pense a relancer `make assets` pour uploader la nouvelle image")

    common.emit(
        {"output": str(args.output), "sectors": len(sectors)}, args.as_json
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
