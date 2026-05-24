import pandas as pd
from pathlib import Path
try:
    from user_data import active_dataset_path
except ModuleNotFoundError:
    from ..user_data import active_dataset_path

FEATURES_CSV = Path(__file__).parent.parent / "data" / "ml_daily_dataset.csv"

def load_features_for_date(date_iso: str, user_id: str | None = None) -> dict:
    dataset_path = active_dataset_path(user_id) if user_id else FEATURES_CSV
    df = pd.read_csv(dataset_path)

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
