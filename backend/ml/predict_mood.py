import json
import joblib
import numpy as np
import pandas as pd
import pathlib

try:
    from user_data import active_dataset_path
except ModuleNotFoundError:
    from ..user_data import active_dataset_path

BASE_DIR = pathlib.Path(__file__).parent
MODELS_DIR = BASE_DIR / "models"
with open(MODELS_DIR / "metadata.json") as f:
    metadata = json.load(f)

MODEL_PATH = MODELS_DIR / metadata["active_model"]
SCHEMA_PATH = BASE_DIR / "feature_schema.json"

model = joblib.load(MODEL_PATH)

with open(SCHEMA_PATH) as f:
    FEATURES = json.load(f)

TARGET = "Next_day_delta"

def _feature_vector(feature_dict: dict):
    return [feature_dict.get(f, 0.0) or 0.0 for f in FEATURES]

def _user_calibration(user_id: str | None):
    if not user_id:
        return {
            "applied": False,
            "sample_count": 0,
            "mean_residual": 0.0,
            "reason": "no_user",
        }

    dataset_path = active_dataset_path(user_id)
    if not dataset_path.exists():
        return {
            "applied": False,
            "sample_count": 0,
            "mean_residual": 0.0,
            "reason": "no_user_dataset",
        }

    df = pd.read_csv(dataset_path)
    if TARGET not in df.columns:
        return {
            "applied": False,
            "sample_count": 0,
            "mean_residual": 0.0,
            "reason": "missing_target",
        }

    df = df.dropna(subset=[TARGET])
    if len(df) < 5:
        return {
            "applied": False,
            "sample_count": int(len(df)),
            "mean_residual": 0.0,
            "reason": "not_enough_samples",
        }

    rows = []
    for _, row in df.iterrows():
        rows.append(_feature_vector(row.to_dict()))

    raw_predictions = model.predict(rows)
    residuals = df[TARGET].to_numpy() - raw_predictions
    mean_residual = float(np.clip(np.mean(residuals), -0.3, 0.3))

    return {
        "applied": True,
        "sample_count": int(len(df)),
        "mean_residual": mean_residual,
        "reason": "ok",
    }

def predict_next_day(feature_dict: dict, user_id: str | None = None):
    x = _feature_vector(feature_dict)
    raw_delta = float(model.predict([x])[0])
    calibration = _user_calibration(user_id)
    delta = raw_delta + calibration["mean_residual"]

    if delta > 0.1:
        label = "Positive"
        color = "green"
    elif delta < -0.1:
        label = "Negative"
        color = "red"
    else:
        label = "Neutral"
        color = "grey"

    return {
        "predicted_delta": float(delta),
        "raw_predicted_delta": raw_delta,
        "confidence": float(min(1.0, abs(delta) * 2)),
        "model_version": metadata["active_model"],
        "calibration": calibration,
    }
