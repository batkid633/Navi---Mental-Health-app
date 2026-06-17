from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import pandas as pd


RESEARCH_DAILY_FEATURE_SCHEMA_NAME = "navi_research_daily_features"
RESEARCH_DAILY_FEATURE_SCHEMA_VERSION = "1.0.0"

MODEL_FEATURE_COLUMNS = [
    "sentiment_today",
    "rolling_mean_7",
    "volatility_7",
    "momentum_7",
    "z_score",
    "is_anomalous",
    "day_of_week",
    "sleep_hours",
    "sleep_efficiency",
    "resting_hr",
    "hrv_rmssd",
    "recovery_score",
    "strain",
    "beacon_sample_count",
    "beacon_hr_avg",
    "beacon_hr_min",
    "beacon_hr_max",
    "beacon_temp_c_avg",
    "beacon_lux_avg",
    "beacon_motion_avg",
    "beacon_battery_avg",
    "beacon_activity_still_ratio",
    "beacon_activity_walking_ratio",
    "beacon_activity_running_ratio",
    "beacon_activity_restless_ratio",
]

RESEARCH_FEATURE_COLUMNS = [
    "audio_session_count",
    "audio_total_seconds",
    "audio_negative_ratio",
    "audio_positive_ratio",
    "audio_anxious_ratio",
    "audio_calm_ratio",
    "audio_training_count",
    "keyboard_session_count",
    "keyboard_event_count",
    "keyboard_chars_estimated",
    "keyboard_backspace_count",
    "keyboard_correction_rate",
    "keyboard_pause_mean_ms",
    "keyboard_pause_std_ms",
    "keyboard_burst_count",
    "keyboard_typing_speed_cpm",
    "keyboard_late_night_ratio",
    "keyboard_platform_web",
    "keyboard_platform_mobile",
    "keyboard_platform_desktop",
]

MISSINGNESS_COLUMNS = [
    "missing_journal",
    "missing_biometrics",
    "missing_audio",
    "missing_keyboard",
    "missing_sleep",
    "missing_hrv",
    "missing_recovery",
]

TARGET_COLUMNS = ["Next_day_delta"]
IDENTIFIER_COLUMNS = ["date"]
MODEL_DATASET_COLUMNS = (
    IDENTIFIER_COLUMNS
    + MODEL_FEATURE_COLUMNS
    + RESEARCH_FEATURE_COLUMNS
    + MISSINGNESS_COLUMNS
    + TARGET_COLUMNS
)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def enrich_research_record(record: dict[str, Any], user_id_hash: str | None = None) -> dict[str, Any]:
    output = dict(record)
    defaults = {
        "schema_name": RESEARCH_DAILY_FEATURE_SCHEMA_NAME,
        "schema_version": RESEARCH_DAILY_FEATURE_SCHEMA_VERSION,
        "generated_at": utc_now_iso(),
        "record_type": "daily_feature_summary",
        "data_classification": "coded_research_feature",
        "identifiability": "coded",
        "raw_text_included": False,
        "raw_audio_included": False,
        "source_system": "navi_flutter_app",
        "consent_scope": "optional_research_sharing",
        "research_use_allowed": True,
    }
    for key, value in defaults.items():
        if output.get(key) is None:
            output[key] = value
    if user_id_hash:
        if output.get("participant_code") is None:
            output["participant_code"] = user_id_hash
    return output


def model_dataset_frame(rows: list[dict[str, Any]]) -> pd.DataFrame:
    df = pd.DataFrame(rows)
    for column in MODEL_DATASET_COLUMNS:
        if column not in df.columns:
            df[column] = None
    return df[MODEL_DATASET_COLUMNS]
