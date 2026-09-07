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


def render_markdown(
    cfg: common.Config, start: str, end: str, results: dict[str, Any]
) -> str:
    """Construit le rapport Markdown."""
    lines = [
        "# Rapport analytics",
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

    lines += [
        "",
        "## Lecture",
        "",
        "Les trois chiffres qui pilotent le classement Roblox : duree de session,",
        "retention J1 et J7, revenus par joueur. Une retention J1 sous 25 % veut",
        "dire que le premier ecran ne donne pas assez a faire dans les 10",
        "premieres secondes.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Ecrit un rapport analytics.")
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

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d_%H%M")
    REPORTS.mkdir(parents=True, exist_ok=True)

    markdown_path = REPORTS / f"analytics_{stamp}.md"
    markdown_path.write_text(render_markdown(cfg, start, end, results), encoding="utf-8")

    json_path = REPORTS / f"analytics_{stamp}.json"
    common.write_json(
        json_path,
        {
            "universeId": cfg.universe_id,
            "startTime": start,
            "endTime": end,
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
