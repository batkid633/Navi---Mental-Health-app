from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import uuid
from datetime import datetime, timezone
from typing import Any

try:
    from config import SETTINGS, get_secret, normalize_env
except ModuleNotFoundError:
    from .config import SETTINGS, get_secret, normalize_env


RESEARCH_PACKET_SCHEMA_NAME = "navi_research_packet"
RESEARCH_PACKET_SCHEMA_VERSION = "1.0.0"
FORBIDDEN_PACKET_FIELDS = {
    "text",
    "journal_text",
    "raw_text",
    "transcript",
    "transcription",
    "raw_audio",
    "audio_bytes",
    "file_path",
    "filepath",
    "download_url",
    "email",
    "name",
    "firebase_uid",
    "uid",
    "oauth_token",
    "access_token",
    "refresh_token",
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def participant_code_for_uid(uid: str) -> str:
    salt = _research_hash_salt()
    digest = hmac.new(salt.encode("utf-8"), uid.encode("utf-8"), hashlib.sha256)
    return digest.hexdigest()[:32]


def build_research_packet(
    *,
    uid: str,
    records: list[dict[str, Any]],
    app_version: str | None = None,
    client_generated_at: str | None = None,
) -> dict[str, Any]:
    if not records:
        raise ValueError("Research packet requires at least one record")

    sanitized_records = [_sanitize_record(record) for record in records]
    date_values = sorted(
        str(record.get("date"))
        for record in sanitized_records
        if record.get("date") is not None
    )
    generated_at = utc_now_iso()
    packet_id = str(uuid.uuid4())

    return {
        "schema_name": RESEARCH_PACKET_SCHEMA_NAME,
        "schema_version": RESEARCH_PACKET_SCHEMA_VERSION,
        "packet_id": packet_id,
        "generated_at": generated_at,
        "client_generated_at": client_generated_at,
        "source_system": "navi_flutter_app",
        "app_version": app_version,
        "participant_code": participant_code_for_uid(uid),
        "record_count": len(sanitized_records),
        "date_range": {
            "start": date_values[0] if date_values else None,
            "end": date_values[-1] if date_values else None,
        },
        "privacy": {
            "data_classification": "coded_research_feature_packet",
            "identifiability": "coded",
            "raw_text_included": False,
            "raw_audio_included": False,
        },
        "quality": {
            "has_records": True,
            "empty_date_count": len(sanitized_records) - len(date_values),
        },
        "records": sanitized_records,
    }


def upload_packet_to_gcs(packet: dict[str, Any]) -> dict[str, Any]:
    bucket_name = SETTINGS.research_packet_bucket
    if not bucket_name:
        return {
            "uploaded": False,
            "skipped": True,
            "reason": "research_packet_bucket_not_configured",
        }

    try:
        from google.cloud import storage
    except ImportError as exc:
        raise RuntimeError("google-cloud-storage is not installed") from exc

    object_name = gcs_object_name(packet)
    payload = json.dumps(packet, sort_keys=True, separators=(",", ":"), default=str)
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(object_name)
    blob.metadata = {
        "schema_name": RESEARCH_PACKET_SCHEMA_NAME,
        "schema_version": RESEARCH_PACKET_SCHEMA_VERSION,
        "packet_id": str(packet["packet_id"]),
        "participant_code": str(packet["participant_code"]),
        "data_classification": "coded_research_feature_packet",
    }
    blob.upload_from_string(payload, content_type="application/json")
    return {
        "uploaded": True,
        "skipped": False,
        "bucket": bucket_name,
        "object": object_name,
        "packet_id": packet["packet_id"],
    }


def gcs_object_name(packet: dict[str, Any]) -> str:
    generated_at = str(packet.get("generated_at") or utc_now_iso())
    date_part = generated_at[:10]
    safe_date = date_part if re.match(r"^\d{4}-\d{2}-\d{2}$", date_part) else "unknown-date"
    year, month, day = safe_date.split("-") if safe_date != "unknown-date" else ("unknown", "unknown", "unknown")
    participant_code = _safe_path_part(str(packet.get("participant_code") or "unknown"))
    packet_id = _safe_path_part(str(packet.get("packet_id") or uuid.uuid4()))
    prefix = SETTINGS.research_packet_prefix.strip("/ ")
    return (
        f"{prefix}/v{RESEARCH_PACKET_SCHEMA_VERSION}/"
        f"{year}/{month}/{day}/{participant_code}/{packet_id}.json"
    )


def _sanitize_record(record: dict[str, Any]) -> dict[str, Any]:
    output: dict[str, Any] = {}
    for key, value in record.items():
        normalized_key = _normalize_key(key)
        if normalized_key in FORBIDDEN_PACKET_FIELDS:
            raise ValueError(f"Forbidden research packet field: {key}")
        output[str(key)] = _json_safe(value)

    if output.get("raw_text_included") is True:
        raise ValueError("Research packet cannot include raw text")
    if output.get("raw_audio_included") is True:
        raise ValueError("Research packet cannot include raw audio")
    return output


def _research_hash_salt() -> str:
    secret_name = normalize_env(os.getenv("RESEARCH_UID_HASH_SALT_SECRET"))
    if secret_name:
        try:
            return get_secret(secret_name)
        except Exception:
            pass
    return (
        normalize_env(os.getenv("RESEARCH_UID_HASH_SALT"))
        or normalize_env(os.getenv("ANALYTICS_UID_HASH_SALT"))
        or SETTINGS.service_name
    )


def _normalize_key(key: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "_", str(key).strip().lower()).strip("_")


def _safe_path_part(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]", "_", value).strip("._-") or "unknown"


def _json_safe(value: Any) -> Any:
    if value is None or isinstance(value, (str, bool, int, float)):
        return value
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_json_safe(item) for item in value]
    return str(value)
