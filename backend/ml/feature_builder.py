import pandas as pd
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[1] / "data"

def build_features(date_iso: str, journal_sentiment: float):
    whoop = pd.read_csv(DATA_DIR / "whoop_daily_metrics.csv")
    features = pd.read_csv(DATA_DIR / "daily_features.csv")

    whoop["date"] = pd.to_datetime(whoop["date"])
    features["date"] = pd.to_datetime(features["date"])

    row_whoop = whoop[whoop["date"] == date_iso].tail(1)
    row_feat = features[features["date"] == date_iso].tail(1)

    if row_feat.empty:
        raise ValueError("No journal features for date")

    base = row_feat.iloc[0].to_dict()
    health = row_whoop.iloc[0].to_dict() if not row_whoop.empty else {}

    base["sentiment_today"] = journal_sentiment

    # merge (WHOOP fields overwrite only if present)
    return {**base, **health}
