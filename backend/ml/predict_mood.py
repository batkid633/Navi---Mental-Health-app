import json
import joblib
import numpy as np
import pathlib

BASE_DIR = pathlib.Path(__file__).parent
MODELS_DIR = BASE_DIR / "models"
with open(MODELS_DIR / "metadata.json") as f:
    metadata = json.load(f)

MODEL_PATH = MODELS_DIR / metadata["active_model"]
SCHEMA_PATH = BASE_DIR / "feature_schema.json"

model = joblib.load(MODEL_PATH)

with open(SCHEMA_PATH) as f:
    FEATURES = json.load(f)

def predict_next_day(feature_dict: dict):
    x = [feature_dict.get(f, 0.0) for f in FEATURES]
    delta = model.predict([x])[0]

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
    "confidence": float(min(1.0, abs(delta) * 2)),  # simple heuristic
    "model_version": metadata["active_model"]
}
