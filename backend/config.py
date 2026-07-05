import json
import logging
import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

from dotenv import find_dotenv, load_dotenv


load_dotenv(find_dotenv(), override=False)

LOGGER = logging.getLogger("navi.config")
BACKEND_DIR = Path(__file__).resolve().parent


def env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def normalize_env(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
    if value.startswith("'") and value.endswith("'"):
        value = value[1:-1]
    return value.strip() or None


ENVIRONMENT = normalize_env(os.getenv("ENVIRONMENT")) or "development"
ENVIRONMENT = ENVIRONMENT.lower()
IS_PRODUCTION = ENVIRONMENT == "production"
SERVICE_NAME = normalize_env(os.getenv("SERVICE_NAME")) or "navi-backend"
SERVICE_VERSION = (
    normalize_env(os.getenv("SERVICE_VERSION"))
    or normalize_env(os.getenv("K_REVISION"))
    or normalize_env(os.getenv("GIT_SHA"))
    or "dev"
)


@dataclass(frozen=True)
class RuntimeSettings:
    environment: str = ENVIRONMENT
    service_name: str = SERVICE_NAME
    service_version: str = SERVICE_VERSION
    auth_required: bool = env_bool("AUTH_REQUIRED", IS_PRODUCTION)
    request_timeout_seconds: int = env_int("REQUEST_TIMEOUT_SECONDS", 60)
    rate_limit_per_minute: int = env_int("RATE_LIMIT_PER_MINUTE", 120)
    outbound_timeout_seconds: int = env_int("OUTBOUND_TIMEOUT_SECONDS", 15)
    secret_manager_project_id: str | None = normalize_env(
        os.getenv("SECRET_MANAGER_PROJECT_ID")
        or os.getenv("GOOGLE_CLOUD_PROJECT")
        or os.getenv("GCP_PROJECT")
    )
    analytics_bigquery_enabled: bool = env_bool("ANALYTICS_BIGQUERY_ENABLED", False)
    analytics_bigquery_project_id: str | None = normalize_env(
        os.getenv("ANALYTICS_BIGQUERY_PROJECT_ID")
        or os.getenv("GOOGLE_CLOUD_PROJECT")
        or os.getenv("GCP_PROJECT")
        or os.getenv("SECRET_MANAGER_PROJECT_ID")
    )
    analytics_bigquery_dataset: str = (
        normalize_env(os.getenv("ANALYTICS_BIGQUERY_DATASET")) or "navi_analytics"
    )
    analytics_bigquery_table: str = (
        normalize_env(os.getenv("ANALYTICS_BIGQUERY_TABLE")) or "product_events"
    )
    analytics_bigquery_location: str = (
        normalize_env(os.getenv("ANALYTICS_BIGQUERY_LOCATION")) or "US"
    )
    research_packet_bucket: str | None = normalize_env(
        os.getenv("RESEARCH_PACKET_BUCKET")
    )
    research_packet_prefix: str = (
        normalize_env(os.getenv("RESEARCH_PACKET_PREFIX")) or "research_packets"
    )


SETTINGS = RuntimeSettings()


class SecretConfigError(RuntimeError):
    pass


def _secret_resource(secret_name: str, project_id: str) -> str:
    if secret_name.startswith("projects/"):
        if "/versions/" in secret_name:
            return secret_name
        return f"{secret_name}/versions/latest"
    return f"projects/{project_id}/secrets/{secret_name}/versions/latest"


@lru_cache(maxsize=64)
def get_secret(secret_name: str) -> str:
    project_id = SETTINGS.secret_manager_project_id
    if not project_id and not secret_name.startswith("projects/"):
        raise SecretConfigError("SECRET_MANAGER_PROJECT_ID is required for Secret Manager lookups")

    try:
        from google.cloud import secretmanager
    except ImportError as exc:
        raise SecretConfigError("google-cloud-secret-manager is not installed") from exc

    client = secretmanager.SecretManagerServiceClient()
    response = client.access_secret_version(
        request={"name": _secret_resource(secret_name, project_id or "")}
    )
    return response.payload.data.decode("utf-8")


def add_secret_version(secret_name: str, value: str) -> None:
    project_id = SETTINGS.secret_manager_project_id
    if not project_id and not secret_name.startswith("projects/"):
        raise SecretConfigError("SECRET_MANAGER_PROJECT_ID is required for Secret Manager writes")

    try:
        from google.cloud import secretmanager
    except ImportError as exc:
        raise SecretConfigError("google-cloud-secret-manager is not installed") from exc

    parent = secret_name
    if secret_name.startswith("projects/") and "/versions/" in secret_name:
        parent = secret_name.rsplit("/versions/", 1)[0]
    elif not secret_name.startswith("projects/"):
        parent = f"projects/{project_id}/secrets/{secret_name}"

    client = secretmanager.SecretManagerServiceClient()
    client.add_secret_version(
        request={"parent": parent, "payload": {"data": value.encode("utf-8")}}
    )
    get_secret.cache_clear()


def secret_value(
    setting_env: str,
    legacy_envs: list[str] | None = None,
    required: bool = False,
) -> str | None:
    secret_name = normalize_env(os.getenv(setting_env))
    if secret_name:
        return normalize_env(get_secret(secret_name))

    for env_name in legacy_envs or []:
        value = normalize_env(os.getenv(env_name))
        if value:
            if SETTINGS.environment == "production":
                raise SecretConfigError(
                    f"{env_name} must be stored in Secret Manager and referenced by {setting_env}"
                )
            return value

    if required:
        raise SecretConfigError(f"{setting_env} is required")
    return None


def secret_json(setting_env: str) -> dict[str, Any] | None:
    value = secret_value(setting_env)
    if not value:
        return None
    return json.loads(value)


def config_check() -> dict[str, Any]:
    secret_bindings = {
        "OPENAI_API_KEY": "OPENAI_API_KEY_SECRET",
        "WHOOP_CLIENT_ID": "WHOOP_CLIENT_ID_SECRET",
        "WHOOP_CLIENT_SECRET": "WHOOP_CLIENT_SECRET_SECRET",
        "WHOOP_TOKENS": "WHOOP_TOKENS_SECRET",
        "FITBIT_CLIENT_ID": "FITBIT_CLIENT_ID_SECRET",
        "FITBIT_CLIENT_SECRET": "FITBIT_CLIENT_SECRET_SECRET",
        "FITBIT_TOKENS": "FITBIT_TOKENS_SECRET",
        "GOOGLE_HEALTH_CLIENT_ID": "GOOGLE_HEALTH_CLIENT_ID_SECRET",
        "GOOGLE_HEALTH_CLIENT_SECRET": "GOOGLE_HEALTH_CLIENT_SECRET_SECRET",
        "GOOGLE_HEALTH_TOKENS": "GOOGLE_HEALTH_TOKENS_SECRET",
    }
    direct_secret_envs = {
        "OPENAI_API_KEY",
        "WHOOP_CLIENT_ID",
        "WHOOP_Client_ID",
        "WHOOP_CLIENT_SECRET",
        "WHOOP_Client_Secret",
        "FITBIT_CLIENT_ID",
        "Fitbit_Client_ID",
        "FITBIT_CLIENT_SECRET",
        "Fitbit_Client_Secret",
        "GOOGLE_HEALTH_CLIENT_ID",
        "GOOGLE_HEALTH_CLIENT_SECRET",
    }

    checks: dict[str, Any] = {
        "environment": SETTINGS.environment,
        "service_version": SETTINGS.service_version,
        "auth_required": SETTINGS.auth_required,
        "secret_manager_project_configured": bool(SETTINGS.secret_manager_project_id),
        "whoop_redirect_uri_configured": bool(
            normalize_env(os.getenv("WHOOP_REDIRECT_URI"))
            or normalize_env(os.getenv("WHOOP_Redirect_URI"))
        ),
        "fitbit_redirect_uri_configured": bool(
            normalize_env(os.getenv("GOOGLE_HEALTH_REDIRECT_URI"))
            or normalize_env(os.getenv("FITBIT_REDIRECT_URI"))
            or normalize_env(os.getenv("Fitbit_Redirect_URI"))
        ),
        "secrets": {},
        "analytics": {
            "bigquery_enabled": SETTINGS.analytics_bigquery_enabled,
            "bigquery_project_configured": bool(SETTINGS.analytics_bigquery_project_id),
            "bigquery_dataset": SETTINGS.analytics_bigquery_dataset,
            "bigquery_table": SETTINGS.analytics_bigquery_table,
            "uid_hash_salt_secret_configured": bool(
                normalize_env(os.getenv("ANALYTICS_UID_HASH_SALT_SECRET"))
            ),
        },
        "research_packets": {
            "bucket_configured": bool(SETTINGS.research_packet_bucket),
            "prefix": SETTINGS.research_packet_prefix,
            "uid_hash_salt_secret_configured": bool(
                normalize_env(os.getenv("RESEARCH_UID_HASH_SALT_SECRET"))
            ),
        },
        "warnings": [],
        "ok": True,
    }

    for label, env_name in secret_bindings.items():
        checks["secrets"][label] = {
            "secret_ref_configured": bool(normalize_env(os.getenv(env_name))),
        }

    if SETTINGS.environment == "production":
        required_secret_labels = {
            "OPENAI_API_KEY",
            "WHOOP_CLIENT_ID",
            "WHOOP_CLIENT_SECRET",
            "WHOOP_TOKENS",
        }
        missing_refs = [
            label
            for label, env_name in secret_bindings.items()
            if label in required_secret_labels and not normalize_env(os.getenv(env_name))
        ]
        missing_optional_refs = [
            label
            for label, env_name in secret_bindings.items()
            if label not in required_secret_labels and not normalize_env(os.getenv(env_name))
        ]
        direct_envs = [name for name in direct_secret_envs if normalize_env(os.getenv(name))]
        if missing_refs:
            checks["warnings"].append(
                f"Missing Secret Manager references for: {', '.join(missing_refs)}"
            )
        if missing_optional_refs:
            checks["warnings"].append(
                f"Optional integrations not configured: {', '.join(missing_optional_refs)}"
            )
        if direct_envs:
            checks["warnings"].append(
                f"Direct secret environment variables are set in production: {', '.join(sorted(direct_envs))}"
            )
        if SETTINGS.analytics_bigquery_enabled and not SETTINGS.analytics_bigquery_project_id:
            checks["warnings"].append("ANALYTICS_BIGQUERY_PROJECT_ID is not configured")
        if SETTINGS.analytics_bigquery_enabled and not normalize_env(
            os.getenv("ANALYTICS_UID_HASH_SALT_SECRET")
        ):
            checks["warnings"].append(
                "ANALYTICS_UID_HASH_SALT_SECRET is recommended before production analytics export"
            )
        if not SETTINGS.research_packet_bucket:
            checks["warnings"].append(
                "RESEARCH_PACKET_BUCKET is not configured; research packet upload will be skipped"
            )
        if SETTINGS.research_packet_bucket and not normalize_env(
            os.getenv("RESEARCH_UID_HASH_SALT_SECRET")
        ):
            checks["warnings"].append(
                "RESEARCH_UID_HASH_SALT_SECRET is recommended before production research packet export"
            )
        if not checks["whoop_redirect_uri_configured"]:
            checks["warnings"].append("WHOOP_REDIRECT_URI is not configured")
        checks["ok"] = (
            not missing_refs
            and not direct_envs
            and SETTINGS.auth_required
            and checks["whoop_redirect_uri_configured"]
        )

    return checks
