"""Teste si des assets se chargent REELLEMENT dans un serveur Roblox.

POURQUOI CETTE ETAPE EXISTE

Un asset present au Creator Store n'est pas forcement utilisable.
`InsertService:LoadAsset` ne reussit que si l'asset appartient au
proprietaire de la place, ou s'il a ete cree par Roblox.

Mesure faite sur ce repo : sur 50 modeles gratuits bien notes trouves par
la recherche, **1 seul** s'est charge. Sur 21 modeles crees par Roblox,
**21 sur 21**. Sans cette sonde, une map construite sur les resultats de
recherche serait vide en jeu, et le bug ne se verrait qu'apres publication.

La sonde recompte aussi les scripts. La recherche expose `hasScripts`, mais
on ne fait pas confiance a une metadonnee pour une question de securite : un
modele qui arrive avec un script est rejete ici aussi.

Usage :
    python tools/probe_assets.py --ids 18717544 56449188
    python tools/probe_assets.py --from-json build/candidates.json
    python tools/probe_assets.py --ids 18717544 --version 15
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import common
import test as test_runner

PROBE_TEMPLATE = """
local InsertService = game:GetService("InsertService")
local candidates = {{
{entries}
}}

local ok, failed = {{}}, {{}}

for _, entry in candidates do
	local success, result = pcall(function()
		return InsertService:LoadAsset(entry.id)
	end)

	if not success or result == nil then
		table.insert(failed, entry)
		continue
	end

	local parts, scripts = 0, 0
	for _, d in result:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
		if d:IsA("LuaSourceContainer") then
			scripts += 1
		end
	end

	local size = Vector3.zero
	local inner = result:FindFirstChildWhichIsA("Model") or result
	local okSize, extent = pcall(function()
		return inner:GetExtentsSize()
	end)
	if okSize then
		size = extent
	end

	table.insert(ok, {{
		id = entry.id,
		parts = parts,
		scripts = scripts,
		size = string.format("%.1f,%.1f,%.1f", size.X, size.Y, size.Z),
	}})
	result:Destroy()
end

print("PROBE_BEGIN")
for _, e in ok do
	print(string.format("OK %d %d %d %s", e.id, e.parts, e.scripts, e.size))
end
for _, e in failed do
	print(string.format("KO %d", e.id))
end
print("PROBE_END")
"""


def collect_ids(args) -> list[int]:
    """Rassemble les IDs a tester, depuis --ids ou un JSON de candidats."""
    ids: list[int] = []

    if args.ids:
        ids.extend(int(value) for value in args.ids)

    if args.from_json:
        path = Path(args.from_json)
        if not path.is_file():
            common.fail(f"{path} introuvable")

        data = json.loads(path.read_text(encoding="utf-8"))
        # Accepte soit une liste plate, soit un dict de listes (la sortie
        # d'une recherche groupee par requete).
        buckets = data.values() if isinstance(data, dict) else [data]
        for bucket in buckets:
            if not isinstance(bucket, list):
                continue
            for entry in bucket:
                asset_id = entry.get("id") if isinstance(entry, dict) else entry
                if asset_id:
                    ids.append(int(asset_id))

    # Dedoublonne en gardant l'ordre : tester deux fois le meme asset ne
    # dit rien de plus et coute un appel reseau.
    seen: set[int] = set()
    unique = []
    for asset_id in ids:
        if asset_id not in seen:
            seen.add(asset_id)
            unique.append(asset_id)

    return unique


def parse_output(logs: list[str]) -> tuple[list[dict], list[int]]:
    """Extrait les resultats entre les marqueurs PROBE_BEGIN et PROBE_END."""
    loaded: list[dict] = []
    failed: list[int] = []
    inside = False

    for line in logs:
        stripped = line.strip()
        if stripped == "PROBE_BEGIN":
            inside = True
            continue
        if stripped == "PROBE_END":
            break
        if not inside:
            continue

        match = re.match(r"OK (\d+) (\d+) (\d+) ([\d.,-]+)", stripped)
        if match:
            loaded.append(
                {
                    "assetId": int(match.group(1)),
                    "parts": int(match.group(2)),
                    "scripts": int(match.group(3)),
                    "size": match.group(4),
                }
            )
            continue

        match = re.match(r"KO (\d+)", stripped)
        if match:
            failed.append(int(match.group(1)))

    return loaded, failed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Teste le chargement reel d'assets dans un serveur Roblox."
    )
    parser.add_argument("--ids", nargs="*", help="IDs d'assets a tester")
    parser.add_argument("--from-json", help="fichier JSON de candidats")
    parser.add_argument(
        "--version",
        type=int,
        help="version de la place a utiliser (defaut : publie une version Saved)",
    )
    parser.add_argument("--out", type=Path, help="ecrit le resultat dans un JSON")
    common.add_game_arg(parser)
    common.add_common_args(parser)
    args = parser.parse_args()

    ids = collect_ids(args)
    if not ids:
        common.fail("aucun ID a tester (utilise --ids ou --from-json)")

    game = common.resolve_game(args.game)
    cfg = common.load_config(
        require=("ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID")
    )

    entries = "\n".join(f"\t{{ id = {asset_id} }}," for asset_id in ids)
    script = PROBE_TEMPLATE.format(entries=entries)

    common.info(f"test de chargement de {len(ids)} asset(s)")

    if args.dry_run:
        common.ok("dry-run : aucun test lance")
        common.emit({"dryRun": True, "ids": ids}, args.as_json)
        return 0

    version = args.version or test_runner.publish_test_version(
        cfg, game, common.ROOT / "build" / f"{game.name}.rbxl"
    )

    api = common.OpenCloud(cfg)
    task_path = test_runner.create_task(api, cfg, version, script)
    test_runner.wait_for_task(api, task_path, timeout=600)
    logs = test_runner.fetch_logs(api, task_path)

    loaded, failed = parse_output(logs)

    scripted = [entry for entry in loaded if entry["scripts"] > 0]
    if scripted:
        common.error(
            "REJETES : ces assets contiennent des scripts, vecteur de "
            "backdoor - " + ", ".join(str(e["assetId"]) for e in scripted)
        )
        loaded = [entry for entry in loaded if entry["scripts"] == 0]

    common.ok(f"{len(loaded)} chargeable(s) sur {len(ids)} :")
    for entry in loaded:
        common.info(
            f"  {entry['assetId']:<16} {entry['parts']:>4} parts   {entry['size']}"
        )

    if failed:
        common.warn(
            f"{len(failed)} non chargeable(s) - probablement ni possede(s) "
            f"ni cree(s) par Roblox : " + ", ".join(str(i) for i in failed[:10])
        )

    result = {"loaded": loaded, "failed": failed}

    if args.out:
        common.write_json(args.out, result)
        common.ok(f"ecrit : {args.out}")

    common.emit(result, args.as_json)
    return 0 if loaded else 1


if __name__ == "__main__":
    raise SystemExit(main())
