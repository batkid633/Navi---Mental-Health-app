import os
from dataclasses import dataclass

import firebase_admin
from fastapi import Header, HTTPException
from firebase_admin import auth as firebase_auth
from dotenv import find_dotenv, load_dotenv


load_dotenv(find_dotenv(), override=False)


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


ENVIRONMENT = os.getenv("ENVIRONMENT", "development").strip().lower()
AUTH_REQUIRED = _env_bool("AUTH_REQUIRED", ENVIRONMENT == "production")


@dataclass(frozen=True)
class CurrentUser:
    uid: str
    email: str | None = None
    claims: dict | None = None


def _ensure_firebase_app() -> None:
    if firebase_admin._apps:
        return

    # In Cloud Run, Application Default Credentials are preferred. For local
    # development, GOOGLE_APPLICATION_CREDENTIALS can point at a service account
    # JSON file if AUTH_REQUIRED=true.
    firebase_admin.initialize_app()


def get_current_user(
    authorization: str | None = Header(default=None),
) -> CurrentUser:
    if not authorization:
        if AUTH_REQUIRED:
            raise HTTPException(status_code=401, detail="Missing Authorization header")
        return CurrentUser(uid="local-dev", claims={"auth_disabled": True})

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Invalid Authorization header")

    try:
        _ensure_firebase_app()
        decoded_token = firebase_auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid Firebase token") from exc

    return CurrentUser(
        uid=decoded_token["uid"],
        email=decoded_token.get("email"),
        claims=decoded_token,
    )
