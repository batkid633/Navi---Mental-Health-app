import pandas as pd
import numpy as np
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
from pathlib import Path
import joblib

MODEL_PATH = Path(__file__).parent / "models" / "longitudinal_state.pkl"

STATE_LABELS = {
    0: "Stable",
    1: "Volatile",
    2: "Recovering",
    3: "Declining"
}

FEATURES = [
    "rolling_std_7",
    "trend_slope_7",
    "sleep_var_7",
    "hrv_avg_7"
]


def train_state_model(df):

    clean = df.dropna(subset=FEATURES).copy()

    if len(clean) < 8:
        return df, None

    scaler = StandardScaler()
    X = scaler.fit_transform(clean[FEATURES])

    # Handle inf/nan from scaling
    X = np.nan_to_num(X, nan=0.0, posinf=0.0, neginf=0.0)

    model = KMeans(n_clusters=4, random_state=42)
    states = model.fit_predict(X)

    clean["state_id"] = states
    clean["state"] = clean["state_id"].map(STATE_LABELS)

    joblib.dump((model, scaler), MODEL_PATH)

    df = df.merge(clean[["date", "state"]], on="date", how="left")

    return df, model


def load_state_model():
    if MODEL_PATH.exists():
        return joblib.load(MODEL_PATH)
    return None