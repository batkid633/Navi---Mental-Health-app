import argparse
import sys
import pandas as pd
import joblib
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from datetime import date
import pathlib
import json
import glob

MODELS_DIR = pathlib.Path(__file__).parent / "models"
METADATA_PATH = MODELS_DIR / "metadata.json"

MODELS_DIR.mkdir(exist_ok=True)

# CLI: allow forcing retrain
parser = argparse.ArgumentParser()
parser.add_argument("--force", action="store_true", help="Force retraining even if a model exists")
args = parser.parse_args()

# If any model (.pkl) already exists in the models dir, skip retraining unless forced
existing_models = glob.glob(str(MODELS_DIR / "*.pkl"))
if existing_models and not args.force:
    print(f"Found existing model(s) in {MODELS_DIR}. Skipping retrain (use --force to override).")
    sys.exit(0)

with open(METADATA_PATH) as f:
    metadata = json.load(f)

next_version = metadata["latest_version"] + 1
model_name = f"model_v{next_version:03d}.pkl"
model_path = MODELS_DIR / model_name

DATA_PATH = "./backend/data/ml_daily_dataset.csv"
MODEL_OUT = "./backend/ml/model.pkl"
SCHEMA_OUT = "./backend/ml/feature_schema.json"

TARGET = "Next_day_delta"
DROP_COLS = ["date", TARGET]

df = pd.read_csv(DATA_PATH)

df = df.dropna(subset=[TARGET])

X = df.drop(columns=DROP_COLS)
y = df[TARGET]

feature_names = list(X.columns)

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

model = RandomForestRegressor(
    n_estimators=200,
    max_depth=8,
    random_state=42
)

model.fit(X_train, y_train)

joblib.dump(model, model_path)

with open(SCHEMA_OUT, "w") as f:
    json.dump(feature_names, f)

metadata.update({
    "active_model": model_name,
    "latest_version": next_version,
    "last_trained": str(date.today()),
    "num_samples": len(X_train),
})

with open(METADATA_PATH, "w") as f:
    json.dump(metadata, f, indent=2)

print(f"Trained and activated {model_name}")

print(f"Features: {feature_names}")
