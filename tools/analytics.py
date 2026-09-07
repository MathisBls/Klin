"""Lit les metriques de l'experience et ecrit un rapport dans reports/.

Interroge l'Analytics Query API pour les indicateurs qui comptent d'apres le
CLAUDE.md : temps de session, retention J1/J7, monetisation. Un rapport
Markdown horodate est ecrit dans reports/, plus un JSON brut a cote pour
pouvoir comparer deux runs sans reparser du texte.

Une metrique absente n'est pas une erreur : un jeu qui vient d'etre publie
n'a pas encore de retention J7. On l'affiche comme indisponible et on
continue.

Usage :
    python tools/analytics.py                # 28 derniers jours
    python tools/analytics.py --days 7
    python tools/analytics.py --metric DailyActiveUsers --metric DailyRevenue
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
from typing import Any

import common

REPORTS = common.ROOT / "reports"
ENDPOINT = "/analytics-query-api/v1/universes/{universe}/metrics"

# Metrique -> (libelle, unite). L'ordre est celui du rapport.
#
# Ces noms ont ete valides un par un contre l'API : elle repond
# "The metric with name X was not found" (code 2001) sur un nom inconnu.
# Ne pas en inventer un sans l'avoir teste - la doc publique est incomplete.
METRICS: dict[str, tuple[str, str]] = {
    "DailyActiveUsers": ("Joueurs actifs par jour", "joueurs"),
    "MonthlyActiveUsers": ("Joueurs actifs par mois", "joueurs"),
    "Visits": ("Visites", "visites"),
    "AverageSessionLengthMinutes": ("Duree de session moyenne", "minutes"),
    "D1Retention": ("Retention J1", "%"),
    "D7Retention": ("Retention J7", "%"),
    "D30Retention": ("Retention J30", "%"),
    "DailyRevenue": ("Revenus", "R$"),
    "AverageRevenuePerUser": ("Revenu par joueur", "R$"),
    "AverageRevenuePerPayingUser": ("Revenu par joueur payant", "R$"),
    "PayingUsersCVR": ("Taux de joueurs payants", "%"),
}


def _error_message(exc: common.ApiError) -> str:
    """Extrait le message lisible d'une erreur analytics, sinon le corps brut."""
    try:
        payload = json.loads(exc.body)
    except Exception:
        return exc.body[:120]

    error = payload.get("error")
    if isinstance(error, dict) and error.get("message"):
        return str(error["message"])
    return exc.body[:120]


def query(
    api: common.OpenCloud, cfg: common.Config, metric: str, start: str, end: str
) -> dict[str, Any]:
    """Interroge une metrique. Renvoie un dict avec 'values' ou 'error'."""
    try:
        response = api.request(
            "POST",
            ENDPOINT.format(universe=cfg.universe_id),
            body={
                "metric": metric,
                "granularity": "OneDay",
                "startTime": start,
                "endTime": end,
            },
        )
    except common.ApiError as exc:
        # Une metrique inconnue ou indisponible remonte en 400 avec un
        # message parlant. Ce n'est pas une raison d'interrompre le rapport.
        if exc.status == 400:
            return {"error": _error_message(exc)}
        raise

    return {"raw": response, "values": extract_values(response)}


def extract_values(response: Any) -> list[float]:
    """Extrait la serie numerique, quelle que soit la forme exacte du JSON.

    L'API a change de forme plusieurs fois (operation/values/dataPoints).
    Plutot que de parier sur une seule, on descend chercher les nombres.
    """
    values: list[float] = []

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("value", "metricValue") and isinstance(value, (int, float)):
                    values.append(float(value))
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(response)
    return values


def summarise(values: list[float]) -> dict[str, float | None]:
    """Total, moyenne et derniere valeur d'une serie."""
    if not values:
        return {"total": None, "average": None, "latest": None}
    return {
        "total": round(sum(values), 2),
        "average": round(sum(values) / len(values), 2),
        "latest": round(values[-1], 2),
    }


def replay_rate(results: dict[str, Any]) -> float | None:
    """Taux de rejeu, derive de Visits / DailyActiveUsers.

    Roblox n'expose aucune metrique de rejeu. On la calcule : un joueur unique
    qui genere 2,4 visites par jour est revenu 1,4 fois. C'est un indicateur
    derive, pas une mesure - le rapport doit le dire.
    """
    visits = (results.get("Visits") or {}).get("summary") or {}
    users = (results.get("DailyActiveUsers") or {}).get("summary") or {}

    total_visits, total_users = visits.get("total"), users.get("total")
    if not total_visits or not total_users:
        return None
    return round(total_visits / total_users, 2)


def render_markdown(
    cfg: common.Config,
    start: str,
    end: str,
    results: dict[str, Any],
    slug: str | None = None,
) -> str:
    """Construit le rapport Markdown."""
    title = f"# Rapport analytics - {slug}" if slug else "# Rapport analytics"
    lines = [
        title,
        "",
        f"- Univers : `{cfg.universe_id}`",
        f"- Periode : {start[:10]} -> {end[:10]}",
        f"- Genere le : {dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%d %H:%M')} UTC",
        "",
        "| Metrique | Derniere valeur | Moyenne | Total | Unite |",
        "|---|---:|---:|---:|---|",
    ]

    for metric, payload in results.items():
        label, unit = METRICS.get(metric, (metric, ""))
        if payload.get("error"):
            lines.append(f"| {label} | - | - | - | {payload['error']} |")
            continue

        stats = payload["summary"]
        if stats["latest"] is None:
            lines.append(f"| {label} | - | - | - | pas encore de donnees |")
            continue

        lines.append(
            f"| {label} | {stats['latest']} | {stats['average']} | "
            f"{stats['total']} | {unit} |"
        )

    rate = replay_rate(results)
    lines += [
        "",
        "## Taux de rejeu",
        "",
        "Roblox n'expose aucune metrique de rejeu. Celle-ci est **derivee** de",
        "`Visits / DailyActiveUsers` : c'est le nombre moyen de sessions par",
        "joueur unique sur la periode. A lire comme un indicateur, pas comme",
        "une mesure officielle.",
        "",
        f"**{rate} session(s) par joueur**" if rate else "_Pas encore de donnees._",
        "",
        "## Lecons a reporter",
        "",
        "A recopier dans `games/PLAYBOOK.md` avec le chiffre qui les prouve, et",
        "dans la section \"Lecons des jeux precedents\" de la spec suivante.",
        "",
        "- Ce qui est conserve :",
        "- Ce qui est abandonne :",
        "- Ce que le jeu suivant fait differemment :",
        "",
        "Reperes (voir `games/PLAYBOOK.md` pour les seuils a jour) : retention J1",
        "sous 20 % = signal faible, au-dessus de 35 % = signal fort, le jeu passe",
        "en mode iteration au lieu d'en creer un nouveau.",
        "",
        "Un jeu de moins de 7 jours n'a pas de retention J7 lisible : ne pas en",
        "tirer de conclusion.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Ecrit un rapport analytics.")
    parser.add_argument(
        "--slug",
        help="slug du jeu : ecrit reports/<slug>.md, nom stable, ecrase a chaque "
        "run. C'est le fichier que cite la spec du jeu suivant.",
    )
    parser.add_argument(
        "--days", type=int, default=28, help="profondeur de la periode (defaut : 28)"
    )
    parser.add_argument(
        "--metric",
        action="append",
        choices=sorted(METRICS),
        help="limiter a certaines metriques (repetable)",
    )
    common.add_common_args(parser)
    args = parser.parse_args()

    if args.days < 1:
        common.fail("--days doit valoir au moins 1")

    cfg = common.load_config(require=("ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID"))
    api = common.OpenCloud(cfg)  # lecture seule, --dry-run sans objet ici

    end_date = dt.datetime.now(dt.timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    start_date = end_date - dt.timedelta(days=args.days)
    start = start_date.strftime("%Y-%m-%dT%H:%M:%SZ")
    end = end_date.strftime("%Y-%m-%dT%H:%M:%SZ")

    wanted = args.metric or list(METRICS)
    common.info(f"periode {start[:10]} -> {end[:10]}, {len(wanted)} metrique(s)")

    results: dict[str, Any] = {}
    for metric in wanted:
        try:
            payload = query(api, cfg, metric, start, end)
        except common.ApiError as exc:
            common.error(str(exc))
            common.fail(exc.explain())

        if payload.get("error"):
            common.warn(f"{metric} : {payload['error']}")
        else:
            payload["summary"] = summarise(payload["values"])
            count = len(payload["values"])
            common.info(f"{metric} : {count} point(s)")
        results[metric] = payload

    REPORTS.mkdir(parents=True, exist_ok=True)

    # Avec --slug, le rapport porte un nom stable et est ecrase a chaque run :
    # c'est le fichier que la spec suivante doit citer. Sans slug, on horodate
    # pour ne pas ecraser un rapport de jeu.
    if args.slug:
        stem = args.slug
    else:
        stem = "analytics_" + dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d_%H%M")

    markdown_path = REPORTS / f"{stem}.md"
    with markdown_path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(render_markdown(cfg, start, end, results, args.slug))

    json_path = REPORTS / f"{stem}.json"
    common.write_json(
        json_path,
        {
            "slug": args.slug,
            "universeId": cfg.universe_id,
            "startTime": start,
            "endTime": end,
            "replayRate": replay_rate(results),
            "metrics": {
                metric: payload.get("summary") or {"error": payload.get("error")}
                for metric, payload in results.items()
            },
        },
    )

    common.ok(f"rapport ecrit : {markdown_path.relative_to(common.ROOT)}")
    common.emit({"report": str(markdown_path), "data": str(json_path)}, args.as_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
