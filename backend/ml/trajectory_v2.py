from __future__ import annotations

import json
from datetime import date
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error
from .temporal_training import fit_temporal_model

try:
    from user_data import active_dataset_path
except ModuleNotFoundError:
    from ..user_data import active_dataset_path


BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models" / "trajectory_v2"
REGISTRY_PATH = MODELS_DIR / "registry.json"

HORIZONS = [1, 3, 7, 14]
TARGET_BASE = "sentiment_today"

FEATURE_GROUPS = {
    "journal": [
        "sentiment_today",
        "rolling_mean_7",
        "volatility_7",
        "momentum_7",
        "z_score",
        "is_anomalous",
        "day_of_week",
    ],
    "biometric": [
        "sleep_hours",
        "sleep_efficiency",
        "resting_hr",
        "hrv_rmssd",
        "recovery_score",
        "strain",
    ],
    "audio": [
        "audio_session_count",
        "audio_total_seconds",
        "audio_negative_ratio",
        "audio_positive_ratio",
        "audio_anxious_ratio",
        "audio_calm_ratio",
        "audio_training_count",
    ],
    "keyboard": [
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
        "keyboard_platform_web",
        "keyboard_platform_mobile",
        "keyboard_platform_desktop",
    ],
    "missingness": [
        "missing_journal",
        "missing_biometrics",
        "missing_audio",
        "missing_keyboard",
        "missing_sleep",
        "missing_hrv",
        "missing_recovery",
    ],
}

ABLATIONS = {
    "journal": ["journal", "missingness"],
    "journal_biometric": ["journal", "biometric", "missingness"],
    "journal_audio": ["journal", "audio", "missingness"],
    "journal_keyboard": ["journal", "keyboard", "missingness"],
    "journal_audio_keyboard": ["journal", "audio", "keyboard", "missingness"],
    "all_modalities": [
        "journal",
        "biometric",
        "audio",
        "keyboard",
        "missingness",
    ],
}


def _model_feature_names(groups: list[str]) -> list[str]:
    names: list[str] = []
    for group in groups:
        names.extend(FEATURE_GROUPS[group])
    return names


def _load_dataset(user_id: str | None = None) -> pd.DataFrame:
    path = active_dataset_path(user_id)
    if not path.exists():
        return pd.DataFrame()
    df = pd.read_csv(path)
    if "date" not in df.columns or TARGET_BASE not in df.columns:
        return pd.DataFrame()
    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df[TARGET_BASE] = pd.to_numeric(df[TARGET_BASE], errors="coerce")
    df = df.dropna(subset=["date"]).sort_values("date").reset_index(drop=True)
    return df


def _ensure_feature_columns(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    all_features = sorted({name for group in FEATURE_GROUPS.values() for name in group})
    for feature in all_features:
        if feature not in df.columns:
            df[feature] = np.nan
        df[feature] = pd.to_numeric(df[feature], errors="coerce").replace([np.inf, -np.inf], np.nan)

    df["missing_journal"] = df.get("missing_journal", df[TARGET_BASE].isna()).fillna(
        df[TARGET_BASE].isna().astype(int)
    )
    df["missing_biometrics"] = df.get("missing_biometrics", 0).fillna(
        df[FEATURE_GROUPS["biometric"]].isna().all(axis=1).astype(int)
    )
    df["missing_audio"] = df.get("missing_audio", 0).fillna(
        df[FEATURE_GROUPS["audio"]].isna().all(axis=1).astype(int)
    )
    df["missing_keyboard"] = df.get("missing_keyboard", 0).fillna(
        df[FEATURE_GROUPS["keyboard"]].isna().all(axis=1).astype(int)
    )
    df["missing_sleep"] = df.get("missing_sleep", df["sleep_hours"].isna()).fillna(
        df["sleep_hours"].isna().astype(int)
    )
    df["missing_hrv"] = df.get("missing_hrv", df["hrv_rmssd"].isna()).fillna(
        df["hrv_rmssd"].isna().astype(int)
    )
    df["missing_recovery"] = df.get("missing_recovery", df["recovery_score"].isna()).fillna(
        df["recovery_score"].isna().astype(int)
    )
    return df


def _build_horizon_frame(df: pd.DataFrame, horizon: int) -> pd.DataFrame:
    if not isinstance(horizon, int) or isinstance(horizon, bool) or horizon < 1:
        raise ValueError("Forecast horizon must be a positive number of calendar days")
    frame = _ensure_feature_columns(df)
    frame['date'] = pd.to_datetime(frame['date'], errors='coerce').dt.normalize()
    frame = frame.dropna(subset=['date']).sort_values('date').copy()
    if frame['date'].duplicated().any():
        raise ValueError("Training requires one explicitly aggregated observation per calendar date")
    frame[TARGET_BASE] = pd.to_numeric(frame[TARGET_BASE], errors='coerce')
    frame.loc[~frame[TARGET_BASE].between(-1, 1), TARGET_BASE] = np.nan
    outcomes = frame.set_index('date')[TARGET_BASE]
    frame['target_date'] = frame['date'] + pd.to_timedelta(horizon, unit='D')
    future = frame['target_date'].map(outcomes)
    frame[f"target_delta_{horizon}d"] = future - frame[TARGET_BASE]
    frame[f"target_mood_{horizon}d"] = future
    return frame.dropna(subset=[TARGET_BASE, f"target_delta_{horizon}d"]).reset_index(drop=True)


def _temporal_holdout(frame: pd.DataFrame, split: int):
    """Exclude training outcomes unavailable before the first evaluation date."""
    ordered = frame.sort_values('date').reset_index(drop=True)
    if split < 1 or split >= len(ordered):
        raise ValueError('Split must leave training and evaluation observations')
    test = ordered.iloc[split:].copy()
    train = ordered.iloc[:split].copy()
    train = train.loc[train['target_date'] < test['date'].min()].copy()
    return train, test


def _impute_features(train: pd.DataFrame, target: pd.DataFrame, features: list[str]) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, float]]:
    medians = {
        feature: float(train[feature].median()) if train[feature].notna().any() else 0.0
        for feature in features
    }
    return (
        train[features].fillna(medians),
        target[features].fillna(medians),
        medians,
    )


def _metric_dict(y_true, y_pred, baseline_pred) -> dict[str, Any]:
    model_mae = float(mean_absolute_error(y_true, y_pred))
    baseline_mae = float(mean_absolute_error(y_true, baseline_pred))
    return {
        "mae": model_mae,
        "rmse": float(mean_squared_error(y_true, y_pred) ** 0.5),
        "baseline_mae": baseline_mae,
        "baseline_rmse": float(mean_squared_error(y_true, baseline_pred) ** 0.5),
        "mae_improvement": baseline_mae - model_mae,
        "relative_mae_improvement": (
            (baseline_mae - model_mae) / baseline_mae if baseline_mae > 0 else 0.0
        ),
        "n": int(len(y_true)),
    }


def _evaluate_ablation(frame: pd.DataFrame, horizon: int, ablation_name: str, groups: list[str]) -> dict[str, Any] | None:
    if len(frame) < 8:
        return None
    split = max(5, int(len(frame) * 0.75))
    if len(frame) - split < 2:
        split = len(frame) - 2
    if split < 4:
        return None

    train, test = _temporal_holdout(frame, split)
    if len(train) < 4:
        return None
    features = _model_feature_names(groups)
    target = f"target_delta_{horizon}d"
    _, _, medians = _impute_features(train, test, features)
    # Raw missing values enter the pipeline so inner-fold imputation/scaling
    # cannot learn from the held-out inner observations.
    model = fit_temporal_model(train[features], train[target], train['date'], train['target_date'])
    pred = model.predict(test[features].replace([np.inf, -np.inf], np.nan))
    baseline = np.zeros(len(test))
    metrics = _metric_dict(test[target], pred, baseline)
    return {
        "ablation": ablation_name,
        "horizon_days": horizon,
        "features": features,
        "train_n": int(len(train)),
        "test_n": int(len(test)),
        "evaluation_protocol": "calendar_horizon_purged_holdout_v1",
        "inner_selection_protocol": model.navi_selection_protocol_,
        "inner_fold_count": model.navi_inner_fold_count_,
        "train_last_target_date": train['target_date'].max().isoformat(),
        "test_first_date": test['date'].min().isoformat(),
        "metrics": metrics,
        "feature_medians": medians,
        "model": model,
    }


def _registry() -> dict[str, Any]:
    if REGISTRY_PATH.exists():
        with open(REGISTRY_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return {
        "active_version": None,
        "latest_version": 0,
        "models": [],
    }


def _write_registry(registry: dict[str, Any]) -> None:
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    with open(REGISTRY_PATH, "w", encoding="utf-8") as f:
        json.dump(registry, f, indent=2)


def train_trajectory_v2(user_id: str | None = None, activate: bool = True) -> dict[str, Any]:
    df = _load_dataset(user_id)
    if df.empty:
        raise ValueError("No trajectory training dataset is available")

    registry = _registry()
    next_version = int(registry.get("latest_version") or 0) + 1
    version = f"trajectory_v2_{next_version:03d}"
    version_dir = MODELS_DIR / version
    version_dir.mkdir(parents=True, exist_ok=True)

    report: dict[str, Any] = {
        "version": version,
        "trained_at": date.today().isoformat(),
        "user_id": user_id,
        "row_count": int(len(df)),
        "horizons": {},
        "active_ablation_strategy": "best_time_split_mae_per_horizon",
        "target_definition": "future_journal_sentiment_minus_current_journal_sentiment",
        "horizon_definition": "calendar_days",
        "evaluation_protocol": "calendar_horizon_purged_holdout_v1",
        "metrics_role": "horizon_metrics_are_selection_only; final_test_is_untouched",
        "clinical_validation": False,
        "confidence_calibrated": False,
        "active_ablations": {},
        "final_test": {},
    }

    artifacts: dict[str, dict[str, Any]] = {}
    for horizon in HORIZONS:
        frame = _build_horizon_frame(df, horizon)
        if len(frame) < 12:
            report['horizons'][str(horizon)] = []
            report['final_test'][str(horizon)] = {'status': 'insufficient_history'}
            continue
        development, final_test = _temporal_holdout(frame, int(len(frame) * 0.8))
        if len(development) < 8 or len(final_test) < 2:
            report['horizons'][str(horizon)] = []
            report['final_test'][str(horizon)] = {'status': 'insufficient_history_after_purge'}
            continue
        horizon_report = []
        fitted_candidates = {}
        for ablation_name, groups in ABLATIONS.items():
            result = _evaluate_ablation(development, horizon, ablation_name, groups)
            if result is None:
                continue
            fitted_candidates[ablation_name] = result
            artifact_name = f"{ablation_name}_{horizon}d.pkl"
            artifact_path = version_dir / artifact_name
            joblib.dump(
                {
                    "model": result["model"],
                    "features": result["features"],
                    "feature_medians": result["feature_medians"],
                    "horizon_days": horizon,
                    "ablation": ablation_name,
                },
                artifact_path,
            )
            artifacts[f"{ablation_name}_{horizon}d"] = {
                "path": str(artifact_path.relative_to(MODELS_DIR)),
                "features": result["features"],
            }
            horizon_report.append({
                key: value
                for key, value in result.items()
                if key not in {"model", "feature_medians", "features"}
            } | {"feature_count": len(result["features"])})
        report["horizons"][str(horizon)] = horizon_report
        if horizon_report:
            best = min(
                horizon_report,
                key=lambda item: item.get("metrics", {}).get("mae", float("inf")),
            )
            report["active_ablations"][str(horizon)] = best["ablation"]
            chosen = fitted_candidates[best['ablation']]
            prediction = chosen['model'].predict(final_test[chosen['features']].replace([np.inf, -np.inf], np.nan))
            report['final_test'][str(horizon)] = {
                'status': 'evaluated_once_after_selection',
                'ablation': best['ablation'],
                'start_date': final_test['date'].min().isoformat(),
                'end_date': final_test['date'].max().isoformat(),
                'metrics': _metric_dict(final_test[f'target_delta_{horizon}d'], prediction, np.zeros(len(final_test))),
                'scope': 'single_temporal_holdout_not_clinical_validation',
            }

    if not artifacts:
        raise ValueError('Insufficient history for purged model selection and independent evaluation; no model activated')
    report["artifacts"] = artifacts
    report_path = version_dir / "report.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)

    registry["latest_version"] = next_version
    if activate:
        registry["active_version"] = version
    registry.setdefault("models", []).append({
        "version": version,
        "trained_at": report["trained_at"],
        "row_count": report["row_count"],
        "active": activate,
        "report_path": str(report_path.relative_to(MODELS_DIR)),
    })
    _write_registry(registry)
    return report


def load_active_report() -> dict[str, Any] | None:
    registry = _registry()
    active = registry.get("active_version")
    if not active:
        return None
    report_path = MODELS_DIR / active / "report.json"
    if not report_path.exists():
        return None
    with open(report_path, "r", encoding="utf-8") as f:
        return json.load(f)


def evaluate_trajectory_v2(user_id: str | None = None) -> dict[str, Any]:
    report = load_active_report()
    if report is not None:
        return report
    raise ValueError('No active evaluation report; explicit offline training is required')


def _load_artifact(report: dict[str, Any], horizon: int, ablation: str | None = None) -> dict[str, Any] | None:
    if ablation is None:
        ablation = report.get("active_ablations", {}).get(str(horizon), "all_modalities")
    key = f"{ablation}_{horizon}d"
    artifact = report.get("artifacts", {}).get(key)
    if not artifact:
        return None
    path = MODELS_DIR / artifact["path"]
    if not path.exists():
        return None
    return joblib.load(path)


def predict_trajectory_v2(feature_dict: dict[str, Any], user_id: str | None = None) -> dict[str, Any]:
    report = load_active_report()
    if report is None:
        raise ValueError('No active trajectory model; inference never trains or activates models')

    row = pd.DataFrame([feature_dict or {}])
    row = _ensure_feature_columns(row)
    baseline = float(row[TARGET_BASE].iloc[0]) if pd.notna(row[TARGET_BASE].iloc[0]) else 0.0

    forecasts = []
    for horizon in HORIZONS:
        artifact = _load_artifact(report, horizon)
        if artifact is None:
            continue
        features = artifact["features"]
        medians = artifact["feature_medians"]
        x = row[features].fillna(medians)
        delta = float(artifact["model"].predict(x)[0])
        horizon_report = report.get("horizons", {}).get(str(horizon), [])
        active_metrics = next(
            (
                item.get("metrics", {})
                for item in horizon_report
                if item.get("ablation") == artifact.get("ablation")
            ),
            {},
        )
        uncertainty = float(active_metrics.get("rmse") or active_metrics.get("baseline_rmse") or 0.35)
        baseline_mae = float(active_metrics.get("baseline_mae") or 1.0)
        model_mae = float(active_metrics.get("mae") or baseline_mae)
        confidence = float(np.clip(1.0 - (model_mae / (baseline_mae + 1e-6)) * 0.5, 0.1, 0.9))
        forecasts.append({
            "horizon_days": horizon,
            "predicted_delta": delta,
            "predicted_mood": float(np.clip(baseline + delta, -1.0, 1.0)),
            "uncertainty": uncertainty,
            "confidence": confidence,
            "ablation": artifact.get("ablation"),
        })

    next_day = forecasts[0] if forecasts else {
        "predicted_delta": 0.0,
        "confidence": 0.0,
    }
    return {
        "predicted_delta": next_day["predicted_delta"],
        "confidence": next_day["confidence"],
        "trajectory": forecasts,
        "model_version": report["version"],
        "model_family": "regularized_multimodal_trajectory_v2",
        "evaluation": report,
    }
