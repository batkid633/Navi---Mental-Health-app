import base64
import hashlib
import hmac
import json
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
TOKEN_PATH = ROOT / "navi_ml" / "tokens" / "fitbit_tokens.json"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
HEALTH_API_BASE = "https://health.googleapis.com/v4"

REDIRECT_URI = normalize_env(
    os.getenv("GOOGLE_HEALTH_REDIRECT_URI")
    or os.getenv("FITBIT_REDIRECT_URI")
    or os.getenv("Fitbit_Redirect_URI")
)
if REDIRECT_URI is not None:
    REDIRECT_URI = REDIRECT_URI.rstrip("/")
LOCAL_REDIRECT_URI = "http://127.0.0.1:8000/fitbit/callback"
TOKEN_REFRESH_MARGIN = 60
STATE_MAX_AGE_SECONDS = 600
DEFAULT_SCOPES = " ".join(
    [
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
        "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
        "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
        "https://www.googleapis.com/auth/googlehealth.profile.readonly",
    ]
)


def _client_id() -> str | None:
    return secret_value(
        "GOOGLE_HEALTH_CLIENT_ID_SECRET",
        ["FITBIT_CLIENT_ID", "Fitbit_Client_ID"],
    ) or secret_value(
        "FITBIT_CLIENT_ID_SECRET",
        ["FITBIT_CLIENT_ID", "Fitbit_Client_ID"],
    )


def _client_secret() -> str | None:
    return secret_value(
        "GOOGLE_HEALTH_CLIENT_SECRET_SECRET",
        ["FITBIT_CLIENT_SECRET", "Fitbit_Client_Secret"],
    ) or secret_value(
        "FITBIT_CLIENT_SECRET_SECRET",
        ["FITBIT_CLIENT_SECRET", "Fitbit_Client_Secret"],
    )


def _configured() -> bool:
    return bool(_client_id() and _client_secret())


def _ensure_token_dir():
    TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)


def _load_token_data():
    secret_tokens = secret_json("GOOGLE_HEALTH_TOKENS_SECRET")
    if secret_tokens is None:
        secret_tokens = secret_json("FITBIT_TOKENS_SECRET")
    if secret_tokens is not None:
        return secret_tokens
    if SETTINGS.environment == "production":
        raise SecretConfigError(
            "GOOGLE_HEALTH_TOKENS_SECRET or FITBIT_TOKENS_SECRET must be configured in production"
        )
    if not TOKEN_PATH.exists():
        raise FileNotFoundError("Token file not found")
    with open(TOKEN_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def _save_token_data(token_data: dict):
    token_secret = normalize_env(
        os.getenv("GOOGLE_HEALTH_TOKENS_SECRET") or os.getenv("FITBIT_TOKENS_SECRET")
    )
    if token_secret:
        add_secret_version(token_secret, json.dumps(token_data))
        return
    if SETTINGS.environment == "production":
        raise SecretConfigError(
            "GOOGLE_HEALTH_TOKENS_SECRET or FITBIT_TOKENS_SECRET must be configured in production"
        )
    _ensure_token_dir()
    with open(TOKEN_PATH, "w", encoding="utf-8") as f:
        json.dump(token_data, f, indent=2)


def _validate_fitbit_config() -> None:
    if not _configured():
        raise RuntimeError("Google Health client credentials are not configured.")


def resolve_fitbit_redirect_uri(request_base_url: str | None = None) -> str:
    if REDIRECT_URI:
        return REDIRECT_URI

    if request_base_url:
        return f"{request_base_url.rstrip('/')}/fitbit/callback"

    return LOCAL_REDIRECT_URI


def _state_signing_key() -> str:
    key = _client_secret()
    if not key:
        raise RuntimeError("Google Health client credentials are not configured.")
    return key


def _sign_state_payload(payload: str) -> str:
    digest = hmac.new(
        _state_signing_key().encode("utf-8"),
        payload.encode("utf-8"),
        hashlib.sha256,
    ).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def generate_fitbit_state() -> str:
    issued_at = int(datetime.now(timezone.utc).timestamp())
    nonce = secrets.token_urlsafe(16)
    payload = f"{issued_at}.{nonce}"
    return f"{payload}.{_sign_state_payload(payload)}"


def validate_fitbit_state(state: str) -> None:
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


def _token_is_expired(token_data: dict) -> bool:
    expires_at = token_data.get("expires_at")
    if expires_at is None:
        return True
    return datetime.now(timezone.utc).timestamp() > (expires_at - TOKEN_REFRESH_MARGIN)


def _to_float(value):
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _date_object(day_iso: str) -> dict:
    parsed = datetime.fromisoformat(day_iso).date()
    return {"year": parsed.year, "month": parsed.month, "day": parsed.day}


def _next_day_iso(day_iso: str) -> str:
    parsed = datetime.fromisoformat(day_iso).date()
    return (parsed + timedelta(days=1)).isoformat()


def _stamp_expiration(tokens: dict) -> dict:
    expires_in = tokens.get("expires_in")
    if expires_in is not None:
        tokens["expires_at"] = int(
            datetime.now(timezone.utc).timestamp() + int(expires_in)
        )
    return tokens


def _refresh_fitbit_token(token_data: dict) -> dict:
    refresh_token = token_data.get("refresh_token")
    if not refresh_token:
        raise RuntimeError("No refresh_token available in stored token data")

    _validate_fitbit_config()

    resp = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": _client_id(),
            "client_secret": _client_secret(),
        },
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
        },
        timeout=SETTINGS.outbound_timeout_seconds,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"Fitbit refresh token failed with status {resp.status_code}")

    new_tokens = _stamp_expiration(resp.json())
    if "refresh_token" not in new_tokens:
        new_tokens["refresh_token"] = refresh_token

    _save_token_data(new_tokens)
    return new_tokens


def _get_access_token() -> str:
    token_data = _load_token_data()
    if _token_is_expired(token_data):
        token_data = _refresh_fitbit_token(token_data)

    access_token = token_data.get("access_token")
    if not access_token:
        raise RuntimeError("No access_token in Google Health token data")
    return access_token


def _health_request(
    method: str,
    path: str,
    params: dict | None = None,
    json_body: dict | None = None,
) -> dict:
    access_token = _get_access_token()
    url = f"{HEALTH_API_BASE}/{path.lstrip('/')}"
    resp = requests.request(
        method,
        url,
        params=params,
        json=json_body,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
        },
        timeout=SETTINGS.outbound_timeout_seconds,
    )
    if resp.status_code == 401:
        token_data = _refresh_fitbit_token(_load_token_data())
        resp = requests.request(
            method,
            url,
            params=params,
            json=json_body,
            headers={
                "Authorization": f"Bearer {token_data.get('access_token')}",
                "Accept": "application/json",
            },
            timeout=SETTINGS.outbound_timeout_seconds,
        )
    if resp.status_code == 404:
        return {}
    resp.raise_for_status()
    return resp.json() if resp.text else {}


def _list_points(data_type: str, filter_value: str | None = None) -> list[dict]:
    params = {"pageSize": 100}
    if filter_value:
        params["filter"] = filter_value
    records = []
    while True:
        data = _health_request(
            "GET",
            f"users/me/dataTypes/{data_type}/dataPoints",
            params=params,
        )
        records.extend(data.get("dataPoints", []))
        page_token = data.get("nextPageToken")
        if not page_token:
            break
        params["pageToken"] = page_token
    return records


def _reconcile_points(data_type: str, filter_value: str | None = None) -> list[dict]:
    params = {"pageSize": 100}
    if filter_value:
        params["filter"] = filter_value
    records = []
    while True:
        data = _health_request(
            "GET",
            f"users/me/dataTypes/{data_type}/dataPoints:reconcile",
            params=params,
        )
        records.extend(data.get("dataPoints", []))
        page_token = data.get("nextPageToken")
        if not page_token:
            break
        params["pageToken"] = page_token
    return records


def _daily_rollup(data_type: str, day_iso: str) -> list[dict]:
    day = _date_object(day_iso)
    body = {
        "range": {
            "start": {
                "date": day,
                "time": {"hours": 0, "minutes": 0, "seconds": 0, "nanos": 0},
            },
            "end": {
                "date": day,
                "time": {"hours": 23, "minutes": 59, "seconds": 59, "nanos": 0},
            },
        },
        "windowSizeDays": 1,
    }
    data = _health_request(
        "POST",
        f"users/me/dataTypes/{data_type}/dataPoints:dailyRollUp",
        json_body=body,
    )
    return data.get("rollupDataPoints", [])


def _first_matching_daily(records: list[dict], key: str, day_iso: str) -> dict | None:
    target = _date_object(day_iso)
    for record in records:
        payload = record.get(key) or {}
        date_value = payload.get("date") or {}
        if (
            int(date_value.get("year", 0)) == target["year"]
            and int(date_value.get("month", 0)) == target["month"]
            and int(date_value.get("day", 0)) == target["day"]
        ):
            return payload
    return None


def _sync_sleep_metrics(day_iso: str) -> tuple[float | None, float | None]:
    # Sleep records often end the morning after they start, so query by civil end date.
    next_day = _next_day_iso(day_iso)
    records = _reconcile_points(
        "sleep",
        f'sleep.interval.civil_end_time >= "{day_iso}"',
    )
    best_sleep = None
    best_minutes = 0.0
    for record in records:
        sleep = record.get("sleep") or {}
        summary = sleep.get("summary") or {}
        interval = sleep.get("interval") or {}
        end_time = interval.get("endTime") or ""
        civil_end = interval.get("civilEndTime", {}).get("date") or {}
        civil_end_iso = None
        if civil_end:
            civil_end_iso = (
                f"{int(civil_end.get('year', 0)):04d}-"
                f"{int(civil_end.get('month', 0)):02d}-"
                f"{int(civil_end.get('day', 0)):02d}"
            )
        if civil_end_iso not in {day_iso, next_day} and not end_time.startswith(day_iso):
            continue
        minutes_asleep = _to_float(summary.get("minutesAsleep"))
        minutes_period = _to_float(summary.get("minutesInSleepPeriod"))
        if minutes_asleep is not None and minutes_asleep > best_minutes:
            best_sleep = summary
            best_minutes = minutes_asleep

    if not best_sleep:
        return None, None

    minutes_asleep = _to_float(best_sleep.get("minutesAsleep"))
    minutes_period = _to_float(best_sleep.get("minutesInSleepPeriod"))
    sleep_hours = minutes_asleep / 60 if minutes_asleep is not None else None
    sleep_efficiency = None
    if minutes_asleep is not None and minutes_period:
        sleep_efficiency = (minutes_asleep / minutes_period) * 100
    return sleep_hours, sleep_efficiency


def _sync_daily_resting_hr(day_iso: str) -> float | None:
    records = _list_points(
        "daily-resting-heart-rate",
        f'daily_resting_heart_rate.date >= "{day_iso}"',
    )
    payload = _first_matching_daily(records, "dailyRestingHeartRate", day_iso)
    return _to_float((payload or {}).get("beatsPerMinute"))


def _sync_daily_hrv(day_iso: str) -> float | None:
    records = _list_points(
        "daily-heart-rate-variability",
        f'daily_heart_rate_variability.date >= "{day_iso}"',
    )
    payload = _first_matching_daily(records, "dailyHeartRateVariability", day_iso)
    return (
        _to_float((payload or {}).get("averageHeartRateVariabilityMilliseconds"))
        or _to_float(
            (payload or {}).get(
                "deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds"
            )
        )
    )


def _sync_activity_strain_proxy(day_iso: str) -> float | None:
    # Google Health does not expose WHOOP strain. Active Zone Minutes is mapped
    # to the same NAVI feature slot as a conservative activity-load proxy.
    points = _daily_rollup("active-zone-minutes", day_iso)
    total_minutes = 0.0
    for point in points:
        active_zone = point.get("activeZoneMinutes") or {}
        for key, value in active_zone.items():
            if key.endswith("Sum") or key in {"activeZoneMinutes", "activeZoneMinutesSum"}:
                total_minutes += _to_float(value) or 0.0
    if total_minutes <= 0:
        return None
    return min(21.0, round(total_minutes / 5.0, 3))


def sync_google_health_day(day_iso: str) -> dict:
    sleep_hours, sleep_efficiency = _sync_sleep_metrics(day_iso)
    return {
        "date": day_iso,
        "sleep_hours": sleep_hours,
        "sleep_efficiency": sleep_efficiency,
        "resting_hr": _sync_daily_resting_hr(day_iso),
        "hrv_rmssd": _sync_daily_hrv(day_iso),
        # Google Health does not provide a direct WHOOP recovery score.
        "recovery_score": None,
        "strain": _sync_activity_strain_proxy(day_iso),
        "source": "google_health",
    }


def generate_fitbit_auth_url(redirect_uri: str | None = None) -> str:
    _validate_fitbit_config()

    state = generate_fitbit_state()
    if redirect_uri is None:
        redirect_uri = resolve_fitbit_redirect_uri()
    else:
        redirect_uri = redirect_uri.rstrip("/")

    params = {
        "response_type": "code",
        "client_id": _client_id(),
        "redirect_uri": redirect_uri,
        "scope": normalize_env(os.getenv("GOOGLE_HEALTH_SCOPES"))
        or normalize_env(os.getenv("FITBIT_SCOPES"))
        or DEFAULT_SCOPES,
        "state": state,
        "access_type": "offline",
        "prompt": "consent",
        "include_granted_scopes": "true",
    }
    return f"{AUTH_URL}?{urllib.parse.urlencode(params)}"


def handle_fitbit_callback(code: str, state: str, redirect_uri: str | None = None) -> dict:
    validate_fitbit_state(state)

    if redirect_uri is None:
        redirect_uri = resolve_fitbit_redirect_uri()
    else:
        redirect_uri = redirect_uri.rstrip("/")

    _validate_fitbit_config()

    token_resp = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect_uri,
            "client_id": _client_id(),
            "client_secret": _client_secret(),
        },
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
        },
        timeout=SETTINGS.outbound_timeout_seconds,
    )

    if token_resp.status_code != 200:
        raise RuntimeError(f"Fitbit token exchange failed with status {token_resp.status_code}")

    tokens = _stamp_expiration(token_resp.json())
    _save_token_data(tokens)
    return tokens


def get_fitbit_status() -> dict:
    configured = _configured()
    if not configured:
        return {
            "connected": False,
            "configured": False,
            "setup_required": True,
            "message": "Google Health developer credentials are not configured yet.",
        }

    try:
        token_data = _load_token_data()
    except FileNotFoundError:
        return {"connected": False, "configured": True}

    connected = bool(token_data.get("refresh_token"))
    expires_at = token_data.get("expires_at")
    expires_at_iso = None
    if expires_at is not None:
        expires_at_iso = datetime.fromtimestamp(int(expires_at), timezone.utc).isoformat()

    if connected and expires_at is not None and _token_is_expired(token_data):
        try:
            token_data = _refresh_fitbit_token(token_data)
            expires_at = token_data.get("expires_at")
            expires_at_iso = datetime.fromtimestamp(int(expires_at), timezone.utc).isoformat()
        except Exception:
            pass

    return {
        "connected": connected,
        "configured": True,
        "expires_at": expires_at_iso,
    }
