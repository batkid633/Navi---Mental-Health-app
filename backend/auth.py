from dataclasses import dataclass
import os

import firebase_admin
from fastapi import Depends, Header, HTTPException
from firebase_admin import auth as firebase_auth

try:
    from config import SETTINGS
except ModuleNotFoundError:
    from .config import SETTINGS


ENVIRONMENT = SETTINGS.environment
AUTH_REQUIRED = SETTINGS.auth_required


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


def _configured_admin_uids() -> set[str]:
    values = [
        os.getenv("ADMIN_ACCESS_UIDS", ""),
        os.getenv("MONITORING_ACCESS_UIDS", ""),
    ]
    return {
        uid.strip()
        for value in values
        for uid in value.split(",")
        if uid.strip()
    }


def is_admin_user(current_user: CurrentUser) -> bool:
    claims = current_user.claims or {}
    return bool(
        claims.get("admin") is True
        or claims.get("navi_admin") is True
        or current_user.uid in _configured_admin_uids()
    )


def require_admin(
    current_user: CurrentUser = Depends(get_current_user),
) -> CurrentUser:
    if not is_admin_user(current_user):
        raise HTTPException(status_code=403, detail="Admin access required")
    return current_user
