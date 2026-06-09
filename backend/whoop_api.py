import json
import base64
import hmac
import hashlib
import os
import secrets
import urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

try:
    from config import (
        SETTINGS,
        SecretConfigError,
        add_secret_version,
        normalize_env,
        secret_json,
        secret_value,
    )
except ModuleNotFoundError:
    from .config import (
        SETTINGS,
        SecretConfigError,
        add_secret_version,
        normalize_env,
        secret_json,
        secret_value,
    )

ROOT = Path(__file__).resolve().parent.parent
TOKEN_PATH = ROOT / "navi_ml" / "tokens" / "whoop_tokens.json"
AUTH_URL = "https://api.prod.whoop.com/oauth/oauth2/auth"
TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"
API_BASE_URL = "https://api.prod.whoop.com/developer/v2"


REDIRECT_URI = normalize_env(
    os.getenv("WHOOP_REDIRECT_URI") or os.getenv("WHOOP_Redirect_URI")
)
if REDIRECT_URI is not None:
    REDIRECT_URI = REDIRECT_URI.rstrip('/')
LOCAL_REDIRECT_URI = "http://127.0.0.1:8000/whoop/callback"
TOKEN_REFRESH_MARGIN = 60
STATE_MAX_AGE_SECONDS = 600


def _client_id() -> str | None:
    return secret_value("WHOOP_CLIENT_ID_SECRET", ["WHOOP_CLIENT_ID", "WHOOP_Client_ID"])


def _client_secret() -> str | None:
    return secret_value(
        "WHOOP_CLIENT_SECRET_SECRET", ["WHOOP_CLIENT_SECRET", "WHOOP_Client_Secret"]
    )


def _ensure_token_dir():
    TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)


def _load_token_data():
    secret_tokens = secret_json("WHOOP_TOKENS_SECRET")
    if secret_tokens is not None:
        return secret_tokens
    if SETTINGS.environment == "production":
        raise SecretConfigError("WHOOP_TOKENS_SECRET must be configured in production")
    if not TOKEN_PATH.exists():
        raise FileNotFoundError("Token file not found")
    with open(TOKEN_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def _save_token_data(token_data: dict):
    token_secret = normalize_env(os.getenv("WHOOP_TOKENS_SECRET"))
    if token_secret:
        add_secret_version(token_secret, json.dumps(token_data))
        return
    if SETTINGS.environment == "production":
        raise SecretConfigError("WHOOP_TOKENS_SECRET must be configured in production")
    _ensure_token_dir()
    with open(TOKEN_PATH, "w", encoding="utf-8") as f:
        json.dump(token_data, f, indent=2)


def _token_is_expired(token_data: dict) -> bool:
    expires_at = token_data.get("expires_at")
    if expires_at is None:
        return True
    return datetime.now(timezone.utc).timestamp() > (expires_at - TOKEN_REFRESH_MARGIN)


def _active_token_data() -> dict:
    token_data = _load_token_data()
    if _token_is_expired(token_data):
        token_data = _refresh_whoop_token(token_data)
    return token_data


def _validate_whoop_config() -> None:
    if _client_id() is None or _client_secret() is None:
        raise RuntimeError(
            "WHOOP client credentials are not configured."
        )


def resolve_whoop_redirect_uri(request_base_url: str | None = None) -> str:
    if REDIRECT_URI:
        return REDIRECT_URI

    if request_base_url:
        return f"{request_base_url.rstrip('/')}/whoop/callback"

    return LOCAL_REDIRECT_URI


def _state_signing_key() -> str:
    key = _client_secret()
    if not key:
        raise RuntimeError("WHOOP client credentials are not configured.")
    return key


def _sign_state_payload(payload: str) -> str:
    digest = hmac.new(
        _state_signing_key().encode("utf-8"),
        payload.encode("utf-8"),
        hashlib.sha256,
    ).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def generate_whoop_state() -> str:
    issued_at = int(datetime.now(timezone.utc).timestamp())
    nonce = secrets.token_urlsafe(16)
    payload = f"{issued_at}.{nonce}"
    return f"{payload}.{_sign_state_payload(payload)}"


def validate_whoop_state(state: str) -> None:
    parts = state.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid state parameter")

    issued_at_raw, nonce, signature = parts
    if not issued_at_raw or not nonce or not signature:
        raise ValueError("Invalid state parameter")

    try:
        issued_at = int(issued_at_raw)
    except ValueError as exc:
        raise ValueError("Invalid state parameter") from exc

    now = int(datetime.now(timezone.utc).timestamp())
    if issued_at > now + 60 or now - issued_at > STATE_MAX_AGE_SECONDS:
        raise ValueError("Expired state parameter")

    expected_signature = _sign_state_payload(f"{issued_at_raw}.{nonce}")
    if not hmac.compare_digest(signature, expected_signature):
        raise ValueError("Invalid state parameter")


def _refresh_whoop_token(token_data: dict) -> dict:
    refresh_token = token_data.get("refresh_token")
    if not refresh_token:
        raise RuntimeError("No refresh_token available in stored token data")

    _validate_whoop_config()

    data = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": _client_id(),
        "client_secret": _client_secret(),
    }

    resp = requests.post(
        TOKEN_URL,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=SETTINGS.outbound_timeout_seconds,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"WHOOP refresh token failed with status {resp.status_code}")

    new_tokens = resp.json()
    if "refresh_token" not in new_tokens:
        new_tokens["refresh_token"] = refresh_token

    expires_in = new_tokens.get("expires_in")
    if expires_in is not None:
        new_tokens["expires_at"] = int(datetime.now(timezone.utc).timestamp() + int(expires_in))

    _save_token_data(new_tokens)
    return new_tokens


def generate_whoop_auth_url(redirect_uri: str | None = None) -> str:
    _validate_whoop_config()

    state = generate_whoop_state()

    if redirect_uri is None:
        redirect_uri = resolve_whoop_redirect_uri()
    else:
        redirect_uri = redirect_uri.rstrip('/')

    params = {
        "response_type": "code",
        "client_id": _client_id(),
        "redirect_uri": redirect_uri,
        "scope": "read:sleep read:recovery read:workout read:cycles offline",
        "state": state,
    }

    return f"{AUTH_URL}?{urllib.parse.urlencode(params)}"


def handle_whoop_callback(code: str, state: str, redirect_uri: str | None = None) -> dict:
    validate_whoop_state(state)

    if redirect_uri is None:
        redirect_uri = resolve_whoop_redirect_uri()
    else:
        redirect_uri = redirect_uri.rstrip('/')

    _validate_whoop_config()

    token_resp = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "code": code,
            "client_id": _client_id(),
            "client_secret": _client_secret(),
            "redirect_uri": redirect_uri,
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=SETTINGS.outbound_timeout_seconds,
    )

    if token_resp.status_code != 200:
        raise RuntimeError(f"WHOOP token exchange failed with status {token_resp.status_code}")

    tokens = token_resp.json()
    expires_in = tokens.get("expires_in")
    if expires_in is not None:
        tokens["expires_at"] = int(datetime.now(timezone.utc).timestamp() + int(expires_in))

    _save_token_data(tokens)
    return tokens


def get_whoop_status() -> dict:
    try:
        token_data = _load_token_data()
    except FileNotFoundError:
        return {"connected": False}

    connected = bool(token_data.get("refresh_token"))
    expires_at = token_data.get("expires_at")
    expires_at_iso = None
    if expires_at is not None:
        expires_at_iso = datetime.fromtimestamp(int(expires_at), timezone.utc).isoformat()

    if connected and expires_at is not None and _token_is_expired(token_data):
        try:
            token_data = _refresh_whoop_token(token_data)
            expires_at = token_data.get("expires_at")
            expires_at_iso = datetime.fromtimestamp(int(expires_at), timezone.utc).isoformat()
        except Exception:
            pass

    return {
        "connected": connected,
        "expires_at": expires_at_iso,
    }


def _auth_headers() -> dict[str, str]:
    token_data = _active_token_data()
    access_token = token_data.get("access_token")
    if not access_token:
        raise RuntimeError("WHOOP access token is not available")
    return {"Authorization": f"Bearer {access_token}"}


def _whoop_get(path: str, params: dict | None = None) -> list[dict]:
    records: list[dict] = []
    next_token = None
    for _ in range(10):
        query = dict(params or {})
        if next_token:
            query["nextToken"] = next_token
        resp = requests.get(
            f"{API_BASE_URL}{path}",
            headers=_auth_headers(),
            params=query,
            timeout=SETTINGS.outbound_timeout_seconds,
        )
        if resp.status_code != 200:
            raise RuntimeError(f"WHOOP API {path} failed with status {resp.status_code}")
        payload = resp.json()
        batch = payload.get("records")
        if isinstance(batch, list):
            records.extend([item for item in batch if isinstance(item, dict)])
        elif isinstance(payload, list):
            records.extend([item for item in payload if isinstance(item, dict)])
            break
        next_token = payload.get("next_token") or payload.get("nextToken")
        if not next_token:
            break
    return records


def _parse_date(value) -> str | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).date().isoformat()
    except ValueError:
        return None


def _date_for_record(record: dict) -> str | None:
    for key in ("start", "start_time", "created_at", "updated_at", "end"):
        parsed = _parse_date(record.get(key))
        if parsed:
            return parsed
    return None


def _nested_num(record: dict, paths: list[tuple[str, ...]]) -> float | None:
    for path in paths:
        current = record
        for key in path:
            if not isinstance(current, dict) or key not in current:
                current = None
                break
            current = current[key]
        if current is None:
            continue
        try:
            return float(current)
        except (TypeError, ValueError):
            continue
    return None


def _sleep_hours(record: dict) -> float | None:
    millis = _nested_num(
        record,
        [
            ("score", "stage_summary", "total_in_bed_time_milli"),
            ("score", "stage_summary", "total_sleep_time_milli"),
            ("score", "sleep_needed", "baseline_milli"),
        ],
    )
    if millis is not None:
        return millis / (1000 * 60 * 60)

    start = record.get("start")
    end = record.get("end")
    if start and end:
        try:
            start_dt = datetime.fromisoformat(str(start).replace("Z", "+00:00"))
            end_dt = datetime.fromisoformat(str(end).replace("Z", "+00:00"))
            return max(0.0, (end_dt - start_dt).total_seconds() / 3600)
        except ValueError:
            return None
    return None


def _upsert_metric(metrics: dict[str, dict], date_key: str | None, values: dict) -> None:
    if not date_key:
        return
    day = metrics.setdefault(date_key, {"date": date_key})
    for key, value in values.items():
        if value is not None:
            day[key] = value


def fetch_daily_metrics(days: int = 30) -> list[dict]:
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=max(1, min(days, 120)))
    params = {
        "start": start.isoformat().replace("+00:00", "Z"),
        "end": end.isoformat().replace("+00:00", "Z"),
        "limit": 25,
    }
    metrics: dict[str, dict] = {}
    errors: list[str] = []

    try:
        sleep_records = _whoop_get("/activity/sleep", params)
    except Exception as exc:
        sleep_records = []
        errors.append(f"sleep:{exc}")
    for sleep in sleep_records:
        date_key = _date_for_record(sleep)
        _upsert_metric(
            metrics,
            date_key,
            {
                "sleep_hours": _sleep_hours(sleep),
                "sleep_efficiency": _nested_num(
                    sleep,
                    [
                        ("score", "sleep_efficiency_percentage"),
                        ("score", "sleep_performance_percentage"),
                    ],
                ),
            },
        )

    try:
        recovery_records = _whoop_get("/recovery", params)
    except Exception as exc:
        recovery_records = []
        errors.append(f"recovery:{exc}")
    for recovery in recovery_records:
        date_key = _date_for_record(recovery)
        _upsert_metric(
            metrics,
            date_key,
            {
                "resting_hr": _nested_num(
                    recovery,
                    [("score", "resting_heart_rate"), ("score", "resting_hr")],
                ),
                "hrv_rmssd": _nested_num(
                    recovery,
                    [("score", "hrv_rmssd_milli"), ("score", "hrv_rmssd")],
                ),
                "recovery_score": _nested_num(
                    recovery,
                    [("score", "recovery_score")],
                ),
            },
        )

    try:
        workout_records = _whoop_get("/activity/workout", params)
    except Exception as exc:
        workout_records = []
        errors.append(f"workout:{exc}")
    for workout in workout_records:
        date_key = _date_for_record(workout)
        strain = _nested_num(workout, [("score", "strain")])
        if date_key and strain is not None:
            day = metrics.setdefault(date_key, {"date": date_key})
            day["strain"] = max(float(day.get("strain") or 0.0), strain)

    try:
        cycle_records = _whoop_get("/cycle", params)
    except Exception as exc:
        cycle_records = []
        errors.append(f"cycle:{exc}")
    for cycle in cycle_records:
        date_key = _date_for_record(cycle)
        strain = _nested_num(cycle, [("score", "strain")])
        if date_key and strain is not None:
            day = metrics.setdefault(date_key, {"date": date_key})
            day["strain"] = max(float(day.get("strain") or 0.0), strain)

    if not metrics and errors:
        raise RuntimeError("; ".join(errors))

    return sorted(metrics.values(), key=lambda row: row["date"])
