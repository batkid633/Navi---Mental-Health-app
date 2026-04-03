import pandas as pd
from pathlib import Path

FEATURES_CSV = Path("data/ml_daily_dataset.csv")

def load_features_for_date(date_iso: str) -> dict:
    df = pd.read_csv(FEATURES_CSV)

    # Ensure date column is datetime
    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    target_date = pd.to_datetime(date_iso)

    # Drop rows with no date
    df = df.dropna(subset=["date"])

    # Only consider rows on or before requested date
    df = df[df["date"] <= target_date]

    if df.empty:
        return {}

    # Take the most recent available row
    row = df.sort_values("date").iloc[-1]

    # Convert NaNs → None so LLM sees them explicitly
    features = {
        k: (None if pd.isna(v) else v)
        for k, v in row.to_dict().items()
    }

    return features
