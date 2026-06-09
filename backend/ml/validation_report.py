from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

try:
    from user_data import active_dataset_path
except ModuleNotFoundError:
    from ..user_data import active_dataset_path


JOURNAL_COLUMNS = [
    "sentiment_today",
    "rolling_mean_7",
    "volatility_7",
    "momentum_7",
    "z_score",
]
BIOMETRIC_COLUMNS = [
    "sleep_hours",
    "sleep_efficiency",
    "resting_hr",
    "hrv_rmssd",
    "recovery_score",
    "strain",
]
AUDIO_COLUMNS = [
    "audio_session_count",
    "audio_total_seconds",
    "audio_negative_ratio",
    "audio_positive_ratio",
    "audio_anxious_ratio",
    "audio_calm_ratio",
]
KEYBOARD_COLUMNS = [
    "keyboard_session_count",
    "keyboard_active_seconds",
    "keyboard_event_count",
    "keyboard_chars_estimated",
    "keyboard_backspace_count",
    "keyboard_correction_rate",
    "keyboard_pause_mean_ms",
    "keyboard_pause_std_ms",
    "keyboard_burst_count",
    "keyboard_typing_speed_cpm",
    "keyboard_late_night_ratio",
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
HORIZONS = [1, 3, 7, 14]


def _load_dataset(user_id: str | None = None) -> pd.DataFrame:
    path = active_dataset_path(user_id)
    if not Path(path).exists():
        return pd.DataFrame()
    df = pd.read_csv(path)
    if "date" in df.columns:
        df["date"] = pd.to_datetime(df["date"], errors="coerce")
        df = df.dropna(subset=["date"]).sort_values("date")
    return df


def _has_any(df: pd.DataFrame, columns: list[str]) -> pd.Series:
    available = [col for col in columns if col in df.columns]
    if not available:
        return pd.Series([False] * len(df), index=df.index)
    return df[available].notna().any(axis=1)


def _missing_rate(df: pd.DataFrame, column: str) -> float | None:
    if column not in df.columns or len(df) == 0:
        return None
    return float(df[column].isna().mean())


def _coverage(df: pd.DataFrame) -> dict[str, Any]:
    if len(df) == 0:
        return {
            "journal_days": 0,
            "biometric_days": 0,
            "audio_days": 0,
            "keyboard_days": 0,
            "fully_multimodal_days": 0,
            "journal_ratio": 0.0,
            "biometric_ratio": 0.0,
            "audio_ratio": 0.0,
            "keyboard_ratio": 0.0,
            "fully_multimodal_ratio": 0.0,
        }

    journal = _has_any(df, JOURNAL_COLUMNS)
    biometric = _has_any(df, BIOMETRIC_COLUMNS)
    audio = _has_any(df, AUDIO_COLUMNS)
    keyboard = _has_any(df, KEYBOARD_COLUMNS)
    full = journal & biometric & audio & keyboard
    total = len(df)
    return {
        "journal_days": int(journal.sum()),
        "biometric_days": int(biometric.sum()),
        "audio_days": int(audio.sum()),
        "keyboard_days": int(keyboard.sum()),
        "fully_multimodal_days": int(full.sum()),
        "journal_ratio": float(journal.mean()),
        "biometric_ratio": float(biometric.mean()),
        "audio_ratio": float(audio.mean()),
        "keyboard_ratio": float(keyboard.mean()),
        "fully_multimodal_ratio": float(full.mean()),
    }


def _horizon_metrics(df: pd.DataFrame) -> list[dict[str, Any]]:
    if "sentiment_today" not in df.columns or len(df) < 2:
        return []

    rows = []
    values = pd.to_numeric(df["sentiment_today"], errors="coerce")
    for horizon in HORIZONS:
        actual_delta = values.shift(-horizon) - values
        persistence_error = actual_delta.abs().dropna()
        rows.append(
            {
                "horizon_days": horizon,
                "target_count": int(actual_delta.notna().sum()),
                "persistence_baseline_mae": (
                    float(persistence_error.mean())
                    if len(persistence_error) > 0
                    else None
                ),
            }
        )
    return rows


def _readiness(df: pd.DataFrame, coverage: dict[str, Any]) -> dict[str, Any]:
    daily_rows = len(df)
    target_rows = int(df["Next_day_delta"].notna().sum()) if "Next_day_delta" in df.columns else 0
    blockers = []
    if daily_rows < 30:
        blockers.append("Collect at least 30 daily rows for early validation.")
    if daily_rows < 100:
        blockers.append("Collect 100+ daily rows per user for stronger personal trajectory modeling.")
    if coverage["audio_days"] < 10:
        blockers.append("Analyze and sync at least 10 audio-supported days.")
    if coverage["biometric_days"] < 10:
        blockers.append("Ingest at least 10 biometric-supported days.")
    if coverage["keyboard_days"] < 10:
        blockers.append("Collect at least 10 in-app typing rhythm-supported days.")
    if target_rows < 20:
        blockers.append("Collect at least 20 next-day outcome rows.")

    return {
        "daily_rows": daily_rows,
        "target_rows": target_rows,
        "early_validation_ready": daily_rows >= 30 and target_rows >= 20,
        "multimodal_validation_ready": (
            daily_rows >= 30
            and target_rows >= 20
            and coverage["audio_days"] >= 10
            and coverage["biometric_days"] >= 10
            and coverage["keyboard_days"] >= 10
        ),
        "study_ready": (
            daily_rows >= 100
            and target_rows >= 80
            and coverage["audio_days"] >= 30
            and coverage["biometric_days"] >= 30
            and coverage["keyboard_days"] >= 30
        ),
        "blockers": blockers,
    }


def build_validation_report(user_id: str | None = None) -> dict[str, Any]:
    df = _load_dataset(user_id)
    coverage = _coverage(df)
    missingness = {
        column: _missing_rate(df, column)
        for column in JOURNAL_COLUMNS
        + BIOMETRIC_COLUMNS
        + AUDIO_COLUMNS
        + KEYBOARD_COLUMNS
        + MISSINGNESS_COLUMNS
    }
    return {
        "row_count": int(len(df)),
        "date_range": {
            "start": df["date"].min().date().isoformat()
            if "date" in df.columns and len(df) > 0
            else None,
            "end": df["date"].max().date().isoformat()
            if "date" in df.columns and len(df) > 0
            else None,
        },
        "coverage": coverage,
        "missingness": missingness,
        "horizon_metrics": _horizon_metrics(df),
        "readiness": _readiness(df, coverage),
        "recommended_validation": [
            "Compare trajectory predictions against persistence and rolling-average baselines.",
            "Run ablations: journal-only, journal+audio, journal+biometric, journal+keyboard, and all modalities.",
            "Report metrics by horizon: 1, 3, 7, and 14 days.",
            "Separate calibration data from held-out validation users during the study.",
        ],
    }
