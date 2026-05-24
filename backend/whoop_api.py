import json
import os
import secrets
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv())

ROOT = Path(__file__).resolve().parent.parent
TOKEN_PATH = ROOT / "navi_ml" / "tokens" / "whoop_tokens.json"
AUTH_URL = "https://api.prod.whoop.com/oauth/oauth2/auth"
TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"


def _normalize_env(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
    if value.startswith("'") and value.endswith("'"):
        value = value[1:-1]
    return value.strip()

CLIENT_ID = _normalize_env(os.getenv("WHOOP_CLIENT_ID") or os.getenv("WHOOP_Client_ID"))
CLIENT_SECRET = _normalize_env(os.getenv("WHOOP_CLIENT_SECRET") or os.getenv("WHOOP_Client_Secret"))
REDIRECT_URI = _normalize_env(
    os.getenv("WHOOP_REDIRECT_URI") or os.getenv("WHOOP_Redirect_URI")
) or "http://127.0.0.1:8000/whoop/callback"
if REDIRECT_URI is not None:
    REDIRECT_URI = REDIRECT_URI.rstrip('/')
STATE_STORE = set()
TOKEN_REFRESH_MARGIN = 60


def _ensure_token_dir():
    TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)


def _load_token_data():
    if not TOKEN_PATH.exists():
        raise FileNotFoundError("Token file not found")
    with open(TOKEN_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def _save_token_data(token_data: dict):
    _ensure_token_dir()
    with open(TOKEN_PATH, "w", encoding="utf-8") as f:
        json.dump(token_data, f, indent=2)


def _token_is_expired(token_data: dict) -> bool:
    expires_at = token_data.get("expires_at")
    if expires_at is None:
        return True
    return datetime.now(timezone.utc).timestamp() > (expires_at - TOKEN_REFRESH_MARGIN)


def _validate_whoop_config() -> None:
    if CLIENT_ID is None or CLIENT_SECRET is None:
        raise RuntimeError(
            "WHOOP_CLIENT_ID and WHOOP_CLIENT_SECRET must be present in the .env file. "
            "Also check that values are not wrapped in extra quotes."
        )


def _refresh_whoop_token(token_data: dict) -> dict:
    refresh_token = token_data.get("refresh_token")
    if not refresh_token:
        raise RuntimeError("No refresh_token available in stored token data")

    _validate_whoop_config()

    data = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    }

    resp = requests.post(TOKEN_URL, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
    if resp.status_code != 200:
        raise RuntimeError(f"WHOOP refresh token failed: {resp.status_code} {resp.text}")

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

    state = secrets.token_hex(8)
    STATE_STORE.add(state)

    if redirect_uri is None:
        redirect_uri = REDIRECT_URI
    else:
        redirect_uri = redirect_uri.rstrip('/')

    params = {
        "response_type": "code",
        "client_id": CLIENT_ID,
        "redirect_uri": redirect_uri,
        "scope": "read:sleep read:recovery read:workout offline",
        "state": state,
    }

    return f"{AUTH_URL}?{urllib.parse.urlencode(params)}"


def handle_whoop_callback(code: str, state: str, redirect_uri: str | None = None) -> dict:
    if state not in STATE_STORE:
        raise ValueError("Invalid state parameter")
    STATE_STORE.remove(state)

    if redirect_uri is None:
        redirect_uri = REDIRECT_URI
    else:
        redirect_uri = redirect_uri.rstrip('/')

    _validate_whoop_config()

    token_resp = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "code": code,
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "redirect_uri": redirect_uri,
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    if token_resp.status_code != 200:
        raise RuntimeError(token_resp.text)

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
