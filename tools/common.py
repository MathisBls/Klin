"""Socle commun des scripts pipeline : config, client Open Cloud, logs.

Tout appel HTTP vers Roblox passe par ici. Regles :
  - la cle API n'est jamais affichee ni loggee (voir `redact`)
  - les erreurs 409, 429 et 5xx sont retentees avec backoff, le reste remonte
  - chaque script sort avec un code != 0 en cas d'echec, pour le Makefile
"""

from __future__ import annotations

import json
import os
import random
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
API_HOST = "https://apis.roblox.com"

# Nombre de tentatives sur les erreurs transitoires (409, 429, 5xx, reseau).
MAX_RETRIES = 5
BASE_BACKOFF = 1.0


# --------------------------------------------------------------------------
# Logs (tout sur stderr, pour que stdout reste exploitable en --json)
# --------------------------------------------------------------------------

def _stderr(prefix: str, message: str) -> None:
    print(f"{prefix} {message}", file=sys.stderr, flush=True)


def info(message: str) -> None:
    _stderr("[info]", message)


def ok(message: str) -> None:
    _stderr("[ok]  ", message)


def warn(message: str) -> None:
    _stderr("[warn]", message)


def error(message: str) -> None:
    _stderr("[err] ", message)


def fail(message: str, code: int = 1) -> None:
    """Arrete le script avec un message et un code de sortie non nul."""
    error(message)
    raise SystemExit(code)


def redact(text: str, secret: str | None) -> str:
    """Remplace le secret par un masque partout ou il apparait."""
    if not secret or len(secret) < 8:
        return text
    return text.replace(secret, f"{secret[:4]}...{secret[-4:]}")


# --------------------------------------------------------------------------
# Configuration (.env)
# --------------------------------------------------------------------------

ENV_KEYS = (
    "ROBLOX_API_KEY",
    "ROBLOX_UNIVERSE_ID",
    "ROBLOX_PLACE_ID",
    "ROBLOX_CREATOR_USER_ID",
    "ROBLOX_CREATOR_GROUP_ID",
)


@dataclass(frozen=True)
class Config:
    api_key: str
    universe_id: str
    place_id: str
    creator_user_id: str = ""
    creator_group_id: str = ""

    @property
    def has_universe(self) -> bool:
        return bool(self.universe_id)

    @property
    def has_place(self) -> bool:
        return bool(self.place_id)

    def creator(self) -> dict[str, str]:
        """Bloc `creator` attendu par l'Assets API. Le groupe prime s'il existe."""
        if self.creator_group_id:
            return {"groupId": self.creator_group_id}
        if self.creator_user_id:
            return {"userId": self.creator_user_id}
        fail(
            "upload d'asset impossible : ni ROBLOX_CREATOR_USER_ID ni "
            "ROBLOX_CREATOR_GROUP_ID dans .env\n"
            "       -> mets ton userId Roblox (ou le groupId si le jeu "
            "appartient a un groupe)"
        )
        raise AssertionError("unreachable")  # pour le typage


def _parse_env_file(path: Path) -> dict[str, str]:
    """Parseur .env minimal : KEY=VALUE, # en commentaire, quotes optionnelles."""
    values: dict[str, str] = {}
    if not path.is_file():
        return values

    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export "):].strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        values[key] = value
    return values


def load_config(require: tuple[str, ...] = ("ROBLOX_API_KEY",)) -> Config:
    """Charge .env puis l'environnement (l'environnement gagne, utile en CI)."""
    values = _parse_env_file(ROOT / ".env")
    for key in ENV_KEYS:
        if os.environ.get(key):
            values[key] = os.environ[key]

    missing = [key for key in require if not values.get(key)]
    if missing:
        fail(
            "variables manquantes dans .env : "
            + ", ".join(missing)
            + "\n       -> copie .env.example en .env et remplis-les"
        )

    return Config(
        api_key=values.get("ROBLOX_API_KEY", ""),
        universe_id=values.get("ROBLOX_UNIVERSE_ID", ""),
        place_id=values.get("ROBLOX_PLACE_ID", ""),
        creator_user_id=values.get("ROBLOX_CREATOR_USER_ID", ""),
        creator_group_id=values.get("ROBLOX_CREATOR_GROUP_ID", ""),
    )


# --------------------------------------------------------------------------
# Client HTTP Open Cloud
# --------------------------------------------------------------------------

class ApiError(RuntimeError):
    """Erreur renvoyee par l'API Roblox, avec le status et le corps."""

    def __init__(self, status: int, body: str, method: str, url: str) -> None:
        self.status = status
        self.body = body
        self.method = method
        self.url = url
        super().__init__(f"{method} {url} -> HTTP {status}\n{body}")

    @property
    def is_scope_problem(self) -> bool:
        """Vrai si Roblox se plaint des permissions.

        Attention : selon l'endpoint, un scope manquant remonte en 401 *ou*
        en 403. On se fie donc au corps autant qu'au code.
        """
        lowered = self.body.lower()
        return self.status == 403 or "scope" in lowered or "insufficient" in lowered

    def explain(self) -> str:
        """Traduit les codes les plus frequents en cause probable."""
        if "unauthorized to create" in self.body:
            # Piege classique : la cle appartient au compte createur, mais
            # ROBLOX_CREATOR_USER_ID pointe vers un autre compte (celui sur
            # lequel on joue, par exemple). Roblox nomme les deux userId dans
            # son message, ce qui rend le diagnostic immediat.
            return (
                "ROBLOX_CREATOR_USER_ID ne correspond pas au compte "
                "proprietaire de la cle API.\n"
                "       -> mets l'userId du compte createur (le premier "
                "cite dans le message ci-dessus), pas celui du compte de jeu"
            )
        if self.is_scope_problem:
            return (
                "scope manquant sur la cle (ou restriction IP active) - "
                "verifie les permissions sur le Creator Dashboard"
            )
        if self.status == 400:
            return "requete refusee : corps ou parametre invalide"
        if self.status == 401:
            return "cle API invalide ou absente (header x-api-key)"
        if self.status == 403:
            return (
                "cle valide mais scope manquant, ou restriction IP active - "
                "verifie les permissions de la cle sur le Creator Dashboard"
            )
        if self.status == 404:
            return "ressource introuvable : universeId / placeId probablement faux"
        if self.status == 409:
            # Le message de Roblox ("Server is busy") est trompeur : la cause
            # la plus frequente n'est pas une surcharge mais un verrou pose
            # par une session Studio ouverte sur cette place.
            return (
                "conflit de publication. Cause la plus frequente : la place "
                "est ouverte dans Roblox Studio, qui tient un verrou "
                "d'edition.\n"
                "       -> ferme Studio, puis relance\n"
                "       -> si Studio est bien ferme, l'API est reellement "
                "surchargee : reessaie dans quelques minutes"
            )
        if self.status == 429:
            return "quota depasse, reessaie plus tard"
        return "voir le corps de la reponse ci-dessus"


class OpenCloud:
    """Client Open Cloud. Une instance par script."""

    def __init__(self, config: Config, dry_run: bool = False) -> None:
        self.config = config
        self.dry_run = dry_run

    def request(
        self,
        method: str,
        path: str,
        *,
        body: Any = None,
        raw_body: bytes | None = None,
        content_type: str | None = None,
        query: dict[str, Any] | None = None,
        expect_json: bool = True,
    ) -> Any:
        """Appel HTTP avec retry. `path` est relatif a apis.roblox.com."""
        url = path if path.startswith("http") else f"{API_HOST}{path}"
        if query:
            pairs = [
                f"{key}={urllib.parse.quote(str(value))}"
                for key, value in query.items()
                if value is not None
            ]
            if pairs:
                url += ("&" if "?" in url else "?") + "&".join(pairs)

        payload = raw_body
        headers = {
            "x-api-key": self.config.api_key,
            "Accept": "application/json",
            "User-Agent": "klin-pipeline/0.1",
        }
        if body is not None:
            payload = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if content_type:
            headers["Content-Type"] = content_type

        if self.dry_run and method.upper() not in ("GET", "HEAD"):
            info(f"[dry-run] {method.upper()} {url}")
            if body is not None:
                info(f"[dry-run] corps : {json.dumps(body, ensure_ascii=False)}")
            return {"dryRun": True}

        last_error: Exception | None = None

        for attempt in range(1, MAX_RETRIES + 1):
            request = urllib.request.Request(
                url, data=payload, headers=headers, method=method.upper()
            )
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    text = response.read().decode("utf-8", errors="replace")
                    if not expect_json or not text.strip():
                        return text
                    return json.loads(text)

            except urllib.error.HTTPError as exc:
                text = redact(
                    exc.read().decode("utf-8", errors="replace"), self.config.api_key
                )
                # 409 : "Server is busy and unable to process your upload".
                # Roblox le renvoie sur une publication quand son backend est
                # charge. C'est un "reessaie plus tard" deguise en conflit,
                # pas une erreur de notre requete.
                transient = (
                    exc.code in (409, 429)
                    or 500 <= exc.code < 600
                )
                if transient and attempt < MAX_RETRIES:
                    delay = self._retry_delay(exc, attempt)
                    warn(
                        f"HTTP {exc.code} sur {method.upper()} {url} - "
                        f"retry dans {delay:.1f}s ({attempt}/{MAX_RETRIES - 1})"
                    )
                    time.sleep(delay)
                    last_error = exc
                    continue
                raise ApiError(exc.code, text, method.upper(), url) from None

            except urllib.error.URLError as exc:
                if attempt < MAX_RETRIES:
                    delay = self._retry_delay(None, attempt)
                    warn(f"erreur reseau ({exc.reason}) - retry dans {delay:.1f}s")
                    time.sleep(delay)
                    last_error = exc
                    continue
                raise

        raise RuntimeError(f"echec apres {MAX_RETRIES} tentatives : {last_error}")

    @staticmethod
    def _retry_delay(exc: urllib.error.HTTPError | None, attempt: int) -> float:
        """Backoff exponentiel avec jitter, sauf si l'API impose Retry-After."""
        if exc is not None and exc.headers is not None:
            retry_after = exc.headers.get("Retry-After")
            if retry_after:
                try:
                    return float(retry_after)
                except ValueError:
                    pass
        # Roblox demande explicitement d'attendre "quelques minutes" sur un
        # 409 : un backoff d'une seconde ne ferait que gaspiller les essais.
        base = 15.0 if exc is not None and exc.code == 409 else BASE_BACKOFF
        return base * (2 ** (attempt - 1)) + random.uniform(0, 0.5)

    def poll_operation(
        self, operation_path: str, *, timeout: float = 180.0, interval: float = 2.0
    ) -> dict[str, Any]:
        """Attend la fin d'une operation longue Open Cloud (`done: true`)."""
        if not operation_path.startswith(("/", "http")):
            operation_path = "/" + operation_path

        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = self.request("GET", operation_path)
            if isinstance(result, dict) and result.get("done"):
                if result.get("error"):
                    raise RuntimeError(f"operation en echec : {result['error']}")
                return result
            time.sleep(interval)

        raise TimeoutError(f"operation toujours en cours apres {timeout:.0f}s")


# --------------------------------------------------------------------------
# Utilitaires partages
# --------------------------------------------------------------------------

def find_tool(name: str) -> str | None:
    """Localise un binaire de la toolchain.

    Regarde d'abord le PATH, puis le dossier ou Rokit depose ses alias.
    Rokit n'ajoute `~/.rokit/bin` au PATH que via `rokit self-install`, et
    seulement pour les terminaux ouverts ensuite. Sans ce repli, le pipeline
    echoue en "rojo introuvable" sur une machine ou tout est pourtant bien
    installe - et en CI, ou personne ne redemarre de terminal.
    """
    found = shutil.which(name)
    if found:
        return found

    for directory in (Path.home() / ".rokit" / "bin",):
        for candidate in (directory / name, directory / f"{name}.exe"):
            if candidate.is_file():
                return str(candidate)

    return None


def encode_multipart(
    fields: dict[str, str], files: dict[str, tuple[str, bytes, str]]
) -> tuple[bytes, str]:
    """Encode un corps multipart/form-data. Retourne (corps, content-type).

    `files` : nom du champ -> (nom de fichier, contenu, type MIME).
    Ecrit a la main pour garder les scripts sur la stdlib seule.
    """
    boundary = f"----klin{random.getrandbits(64):016x}"
    parts: list[bytes] = []

    for name, value in fields.items():
        parts.append(
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
            f"{value}\r\n".encode("utf-8")
        )

    for name, (filename, content, mime) in files.items():
        parts.append(
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"; '
            f'filename="{filename}"\r\n'
            f"Content-Type: {mime}\r\n\r\n".encode("utf-8")
        )
        parts.append(content)
        parts.append(b"\r\n")

    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def read_json(path: Path, default: Any = None) -> Any:
    """Lit un JSON, ou renvoie `default` si le fichier n'existe pas."""
    if not path.is_file():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    """Ecrit un JSON stable (trie, indente) pour des diffs git lisibles."""
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    # newline explicite : sinon Python ecrit du CRLF sur Windows et chaque
    # machine produit un diff git different pour un contenu identique.
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(payload)


def add_common_args(parser) -> None:
    """Arguments communs a tous les scripts du pipeline."""
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="n'effectue aucune ecriture, affiche ce qui serait envoye",
    )
    parser.add_argument(
        "--json",
        dest="as_json",
        action="store_true",
        help="sortie machine sur stdout (les logs restent sur stderr)",
    )


def emit(data: Any, as_json: bool) -> None:
    """Sortie finale sur stdout. Les logs vont sur stderr, jamais ici."""
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
