from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression

try:
    from user_data import active_dataset_path
except ModuleNotFoundError:
    from ..user_data import active_dataset_path


HORIZONS = [1, 3, 7, 14]
SENTIMENT = "sentiment_today"
TARGET = "Next_day_delta"

JOURNAL_FEATURES = [
    "sentiment_today",
    "rolling_mean_7",
    "volatility_7",
    "momentum_7",
    "z_score",
    "is_anomalous",
]

BIOMETRIC_FEATURES = [
    "sleep_hours",
    "sleep_efficiency",
    "resting_hr",
    "hrv_rmssd",
    "recovery_score",
    "strain",
]

AUDIO_FEATURES = [
    "audio_session_count",
    "audio_total_seconds",
    "audio_negative_ratio",
    "audio_positive_ratio",
    "audio_anxious_ratio",
    "audio_calm_ratio",
]

KEYBOARD_FEATURES = [
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

MISSINGNESS_FEATURES = [
    "missing_journal",
    "missing_biometrics",
    "missing_audio",
    "missing_keyboard",
    "missing_sleep",
    "missing_hrv",
    "missing_recovery",
]


@dataclass
class TrajectoryComponents:
    baseline: float
    trend_per_day: float
    volatility: float
    biometric_adjustment: float
    audio_adjustment: float
    keyboard_adjustment: float
    residual_std: float


def _num(value: Any, default: float = 0.0) -> float:
    if value is None:
        return default
    try:
        if pd.isna(value):
            return default
    except TypeError:
        pass
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _clip_sentiment(value: float) -> float:
    return float(np.clip(value, -1.0, 1.0))


def _safe_std(values: pd.Series | np.ndarray, default: float = 0.15) -> float:
    clean = pd.Series(values).dropna()
    if len(clean) < 2:
        return default
    std = float(clean.std())
    if math.isnan(std) or std <= 0:
        return default
    return std


def _load_history(user_id: str | None) -> pd.DataFrame:
    path = active_dataset_path(user_id)
    if not Path(path).exists():
        return pd.DataFrame()
    df = pd.read_csv(path)
    if "date" not in df.columns or SENTIMENT not in df.columns:
        return pd.DataFrame()
    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df[SENTIMENT] = pd.to_numeric(df[SENTIMENT], errors="coerce")
    df = df.dropna(subset=["date", SENTIMENT]).sort_values("date")
    return df


def _modality_coverage(row: dict[str, Any], history: pd.DataFrame) -> dict[str, Any]:
    def present(features: list[str]) -> list[str]:
        available = []
        for feature in features:
            value = row.get(feature)
            if value is None and feature in history.columns and len(history) > 0:
                value = history.iloc[-1].get(feature)
            if value is not None and not pd.isna(value):
                available.append(feature)
        return available

    journal = present(JOURNAL_FEATURES)
    biometric = present(BIOMETRIC_FEATURES)
    audio = present(AUDIO_FEATURES)
    keyboard = present(KEYBOARD_FEATURES)
    missingness = present(MISSINGNESS_FEATURES)
    modalities = {
        "journal": len(journal) > 0,
        "biometric": len(biometric) > 0,
        "audio": len(audio) > 0,
        "keyboard": len(keyboard) > 0,
    }
    available_modalities = [name for name, ok in modalities.items() if ok]
    return {
        "modalities": modalities,
        "available_modalities": available_modalities,
        "available_feature_count": len(journal)
        + len(biometric)
        + len(audio)
        + len(keyboard)
        + len(missingness),
        "expected_feature_count": len(JOURNAL_FEATURES)
        + len(BIOMETRIC_FEATURES)
        + len(AUDIO_FEATURES)
        + len(KEYBOARD_FEATURES)
        + len(MISSINGNESS_FEATURES),
        "coverage_ratio": (len(available_modalities) / 4.0),
        "missingness": {
            "journal": bool(_num(row.get("missing_journal"), 0.0)),
            "biometrics": bool(_num(row.get("missing_biometrics"), 0.0)),
            "audio": bool(_num(row.get("missing_audio"), 0.0)),
            "keyboard": bool(_num(row.get("missing_keyboard"), 0.0)),
            "sleep": bool(_num(row.get("missing_sleep"), 0.0)),
            "hrv": bool(_num(row.get("missing_hrv"), 0.0)),
            "recovery": bool(_num(row.get("missing_recovery"), 0.0)),
        },
    }


def _recent_trend(history: pd.DataFrame, row: dict[str, Any]) -> tuple[float, float]:
    if len(history) >= 3:
        recent = history.tail(min(14, len(history)))
        x = np.arange(len(recent)).reshape(-1, 1)
        y = recent[SENTIMENT].to_numpy()
        model = LinearRegression().fit(x, y)
        fitted = model.predict(x)
        residual_std = _safe_std(y - fitted)
        return float(np.clip(model.coef_[0], -0.18, 0.18)), residual_std

    return float(np.clip(_num(row.get("momentum_7")), -0.18, 0.18)), 0.2


def _z_against_history(feature: str, row: dict[str, Any], history: pd.DataFrame) -> float:
    value = row.get(feature)
    if value is None or pd.isna(value):
        return 0.0
    if feature not in history.columns:
        return 0.0
    series = pd.to_numeric(history[feature], errors="coerce").dropna()
    if len(series) < 4:
        return 0.0
    std = float(series.std())
    if std <= 0 or math.isnan(std):
        return 0.0
    return float(np.clip((_num(value) - float(series.mean())) / std, -2.0, 2.0))


def _biometric_adjustment(row: dict[str, Any], history: pd.DataFrame) -> float:
    sleep = _z_against_history("sleep_hours", row, history)
    efficiency = _z_against_history("sleep_efficiency", row, history)
    hrv = _z_against_history("hrv_rmssd", row, history)
    recovery = _z_against_history("recovery_score", row, history)
    resting_hr = _z_against_history("resting_hr", row, history)
    strain = _z_against_history("strain", row, history)
    adjustment = (
        0.025 * sleep
        + 0.015 * efficiency
        + 0.025 * hrv
        + 0.020 * recovery
        - 0.020 * resting_hr
        - 0.015 * strain
    )
    return float(np.clip(adjustment, -0.16, 0.16))


def _audio_adjustment(row: dict[str, Any]) -> float:
    sessions = _num(row.get("audio_session_count"))
    if sessions <= 0:
        return 0.0
    negative = _num(row.get("audio_negative_ratio"))
    anxious = _num(row.get("audio_anxious_ratio"))
    positive = _num(row.get("audio_positive_ratio"))
    calm = _num(row.get("audio_calm_ratio"))
    adjustment = 0.07 * (positive + calm) - 0.08 * (negative + anxious)
    return float(np.clip(adjustment, -0.14, 0.14))


def _keyboard_adjustment(row: dict[str, Any], history: pd.DataFrame) -> float:
    sessions = _num(row.get("keyboard_session_count"))
    if sessions <= 0:
        return 0.0
    correction = _z_against_history("keyboard_correction_rate", row, history)
    pause = _z_against_history("keyboard_pause_mean_ms", row, history)
    late = _z_against_history("keyboard_late_night_ratio", row, history)
    speed = _z_against_history("keyboard_typing_speed_cpm", row, history)
    adjustment = 0.012 * speed - 0.018 * correction - 0.014 * pause - 0.014 * late
    return float(np.clip(adjustment, -0.08, 0.08))


def _components(row: dict[str, Any], history: pd.DataFrame) -> TrajectoryComponents:
    baseline = _num(row.get(SENTIMENT))
    if baseline == 0.0 and len(history) > 0:
        baseline = _num(history.iloc[-1].get(SENTIMENT))

    trend, residual_std = _recent_trend(history, row)
    volatility = _num(row.get("volatility_7"), _safe_std(history[SENTIMENT]) if len(history) else 0.2)
    volatility = float(np.clip(volatility, 0.05, 0.9))
    residual_std = max(residual_std, volatility * 0.65, 0.08)
    return TrajectoryComponents(
        baseline=_clip_sentiment(baseline),
        trend_per_day=trend,
        volatility=volatility,
        biometric_adjustment=_biometric_adjustment(row, history),
        audio_adjustment=_audio_adjustment(row),
        keyboard_adjustment=_keyboard_adjustment(row, history),
        residual_std=float(np.clip(residual_std, 0.08, 0.9)),
    )


def _validation_diagnostics(history: pd.DataFrame) -> dict[str, Any]:
    if len(history) < 5:
        return {
            "sample_count": int(len(history)),
            "validation_ready": False,
            "reason": "fewer_than_5_daily_rows",
        }

    rows = history.copy()
    rows["previous"] = rows[SENTIMENT].shift(1)
    rows = rows.dropna(subset=["previous"])
    if rows.empty:
        return {
            "sample_count": int(len(history)),
            "validation_ready": False,
            "reason": "no_lagged_rows",
        }
    persistence_mae = float(np.mean(np.abs(rows[SENTIMENT] - rows["previous"])))
    return {
        "sample_count": int(len(history)),
        "validation_ready": len(history) >= 30,
        "reason": "ok" if len(history) >= 30 else "needs_at_least_30_daily_rows_for_study_validation",
        "persistence_baseline_mae": persistence_mae,
        "target_rows": int(history[TARGET].notna().sum()) if TARGET in history.columns else 0,
    }


def predict_trajectory(
    feature_dict: dict[str, Any],
    user_id: str | None = None,
    horizons: list[int] | None = None,
    legacy_next_day: dict[str, Any] | None = None,
) -> dict[str, Any]:
    horizons = horizons or HORIZONS
    history = _load_history(user_id)
    row = dict(feature_dict or {})
    if not row and len(history) > 0:
        row = history.iloc[-1].to_dict()

    coverage = _modality_coverage(row, history)
    parts = _components(row, history)
    coverage_ratio = float(coverage["coverage_ratio"])
    sample_count = int(len(history))
    sample_factor = min(1.0, sample_count / 30.0)
    coverage_factor = 0.45 + (0.55 * coverage_ratio)
    confidence_floor = 0.12 if sample_count < 10 else 0.18

    forecasts = []
    for horizon in horizons:
        decay = 1.0 / math.sqrt(max(1, horizon))
        expected_delta = (
            parts.trend_per_day * horizon
            + (
                parts.biometric_adjustment
                + parts.audio_adjustment
                + parts.keyboard_adjustment
            )
            * decay
        )
        expected_mood = _clip_sentiment(parts.baseline + expected_delta)
        uncertainty = float(
            np.clip(
                parts.residual_std * math.sqrt(max(1, horizon)) * (1.25 - 0.35 * sample_factor),
                0.08,
                1.25,
            )
        )
        confidence = float(
            np.clip(
                (1.0 / (1.0 + uncertainty)) * coverage_factor * (0.55 + 0.45 * sample_factor),
                confidence_floor,
                0.92,
            )
        )
        forecasts.append(
            {
                "horizon_days": int(horizon),
                "predicted_mood": expected_mood,
                "predicted_delta": float(np.clip(expected_mood - parts.baseline, -2.0, 2.0)),
                "uncertainty": uncertainty,
                "confidence": confidence,
            }
        )

    next_day = forecasts[0]
    if legacy_next_day and sample_count < 30:
        legacy_delta = _num(legacy_next_day.get("predicted_delta"))
        blended_delta = (0.65 * next_day["predicted_delta"]) + (0.35 * legacy_delta)
        next_day["predicted_delta"] = float(np.clip(blended_delta, -2.0, 2.0))
        next_day["predicted_mood"] = _clip_sentiment(parts.baseline + blended_delta)

    direction = "stable"
    if forecasts[-1]["predicted_delta"] > 0.15:
        direction = "improving"
    elif forecasts[-1]["predicted_delta"] < -0.15:
        direction = "declining"
    elif parts.volatility > 0.35:
        direction = "variable"

    return {
        "predicted_delta": next_day["predicted_delta"],
        "confidence": next_day["confidence"],
        "trajectory": forecasts,
        "trajectory_summary": {
            "direction": direction,
            "baseline_mood": parts.baseline,
            "trend_per_day": parts.trend_per_day,
            "volatility": parts.volatility,
            "biometric_adjustment": parts.biometric_adjustment,
            "audio_adjustment": parts.audio_adjustment,
            "keyboard_adjustment": parts.keyboard_adjustment,
            "model_family": "longitudinal_multimodal_trajectory_v1",
        },
        "modality_coverage": coverage,
        "validation": _validation_diagnostics(history),
    }
