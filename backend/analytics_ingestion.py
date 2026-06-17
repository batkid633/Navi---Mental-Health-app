import hashlib
import hmac
import json
import logging
import os
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

try:
    from config import SETTINGS, get_secret, normalize_env
except ModuleNotFoundError:
    from .config import SETTINGS, get_secret, normalize_env


LOGGER = logging.getLogger("navi.analytics")

MAX_EVENT_NAME_LENGTH = 80
MAX_PROPERTY_COUNT = 40
MAX_PROPERTY_KEY_LENGTH = 60
MAX_PROPERTY_STRING_LENGTH = 240
MAX_PROPERTIES_JSON_LENGTH = 16_000
EVENT_NAME_RE = re.compile(r"[^a-z0-9_]+")
ANALYTICS_SCHEMA_VERSION = "navi_product_event_v2"


@dataclass(frozen=True)
class NormalizedAnalyticsEvent:
    event_id: str
    event_name: str
    event_timestamp: str
    received_at: str
    event_date: str
    event_source: str
    platform: str | None
    app_version: str | None
    service_name: str
    service_version: str
    environment: str
    schema_version: str
    client_schema_version: str | None
    data_classification: str
    contains_health_content: bool
    firebase_uid_hash: str
    session_id: str | None
    properties_json: str

    def to_bigquery_row(self) -> dict[str, Any]:
        return {
            "event_id": self.event_id,
            "event_name": self.event_name,
            "event_timestamp": self.event_timestamp,
            "received_at": self.received_at,
            "event_date": self.event_date,
            "event_source": self.event_source,
            "platform": self.platform,
            "app_version": self.app_version,
            "service_name": self.service_name,
            "service_version": self.service_version,
            "environment": self.environment,
            "schema_version": self.schema_version,
            "client_schema_version": self.client_schema_version,
            "data_classification": self.data_classification,
            "contains_health_content": self.contains_health_content,
            "firebase_uid_hash": self.firebase_uid_hash,
            "session_id": self.session_id,
            "properties_json": self.properties_json,
        }


def normalize_event_name(name: str | None) -> str:
    normalized = EVENT_NAME_RE.sub("_", (name or "").strip().lower())
    normalized = re.sub(r"_+", "_", normalized).strip("_")
    if not normalized:
        return "unknown_event"
    return normalized[:MAX_EVENT_NAME_LENGTH]


def normalize_property_key(key: str) -> str:
    normalized = normalize_event_name(key)
    return normalized[:MAX_PROPERTY_KEY_LENGTH]


def normalize_properties(properties: dict[str, Any] | None) -> dict[str, Any]:
    output: dict[str, Any] = {}
    for key, value in list((properties or {}).items())[:MAX_PROPERTY_COUNT]:
        safe_key = normalize_property_key(str(key))
        if value is None or isinstance(value, (bool, int, float)):
            output[safe_key] = value
        elif isinstance(value, str):
            output[safe_key] = value[:MAX_PROPERTY_STRING_LENGTH]
    return output


def properties_to_json(properties: dict[str, Any] | None) -> str:
    payload = json.dumps(
        normalize_properties(properties),
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )
    return payload[:MAX_PROPERTIES_JSON_LENGTH]


def parse_client_timestamp(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return datetime.now(timezone.utc)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _analytics_hash_salt() -> str:
    secret_name = normalize_env(os.getenv("ANALYTICS_UID_HASH_SALT_SECRET"))
    if secret_name:
        try:
            return get_secret(secret_name)
        except Exception:
            LOGGER.exception("analytics_hash_salt_secret_failed")
    return normalize_env(os.getenv("ANALYTICS_UID_HASH_SALT")) or SETTINGS.service_name


def hash_uid(uid: str) -> str:
    digest = hmac.new(
        _analytics_hash_salt().encode("utf-8"),
        uid.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return digest[:32]


def normalize_event(
    *,
    event_id: str | None,
    event_name: str | None,
    user_id: str,
    properties: dict[str, Any] | None,
    platform: str | None,
    app_version: str | None,
    client_schema_version: str | None,
    session_id: str | None,
    client_recorded_at: str | None,
    source: str,
) -> NormalizedAnalyticsEvent:
    timestamp = parse_client_timestamp(client_recorded_at)
    received_at = datetime.now(timezone.utc)
    fallback_id = hashlib.sha256(
        f"{user_id}:{event_name}:{timestamp.isoformat()}:{session_id}".encode("utf-8")
    ).hexdigest()[:32]

    return NormalizedAnalyticsEvent(
        event_id=(event_id or fallback_id)[:80],
        event_name=normalize_event_name(event_name),
        event_timestamp=timestamp.isoformat().replace("+00:00", "Z"),
        received_at=received_at.isoformat().replace("+00:00", "Z"),
        event_date=timestamp.date().isoformat(),
        event_source=normalize_event_name(source),
        platform=normalize_event_name(platform) if platform else None,
        app_version=app_version[:80] if app_version else None,
        service_name=SETTINGS.service_name,
        service_version=SETTINGS.service_version,
        environment=SETTINGS.environment,
        schema_version=ANALYTICS_SCHEMA_VERSION,
        client_schema_version=client_schema_version[:80] if client_schema_version else None,
        data_classification="privacy_safe_product_analytics",
        contains_health_content=False,
        firebase_uid_hash=hash_uid(user_id),
        session_id=session_id[:80] if session_id else None,
        properties_json=properties_to_json(properties),
    )


class BigQueryAnalyticsSink:
    def __init__(self) -> None:
        self.enabled = SETTINGS.analytics_bigquery_enabled
        self.project_id = SETTINGS.analytics_bigquery_project_id
        self.dataset = SETTINGS.analytics_bigquery_dataset
        self.table = SETTINGS.analytics_bigquery_table
        self.location = SETTINGS.analytics_bigquery_location
        self._client = None

    @property
    def table_id(self) -> str | None:
        if not (self.project_id and self.dataset and self.table):
            return None
        return f"{self.project_id}.{self.dataset}.{self.table}"

    def _get_client(self):
        if self._client is not None:
            return self._client
        try:
            from google.cloud import bigquery
        except ImportError as exc:
            raise RuntimeError("google-cloud-bigquery is not installed") from exc
        self._client = bigquery.Client(project=self.project_id, location=self.location)
        return self._client

    def insert_events(self, events: list[NormalizedAnalyticsEvent]) -> dict[str, Any]:
        table_id = self.table_id
        if not self.enabled:
            return {"enabled": False, "inserted": 0, "errors": []}
        if not table_id:
            raise RuntimeError("BigQuery analytics table is not configured")
        if not events:
            return {"enabled": True, "inserted": 0, "errors": []}

        rows = [event.to_bigquery_row() for event in events]
        errors = self._get_client().insert_rows_json(
            table_id,
            rows,
            row_ids=[event.event_id for event in events],
        )
        if errors:
            return {"enabled": True, "inserted": 0, "errors": errors}
        return {"enabled": True, "inserted": len(events), "errors": []}


analytics_sink = BigQueryAnalyticsSink()
