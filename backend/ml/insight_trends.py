import pandas as pd
import numpy as np
from ml.longitudinal_features import build_longitudinal_features
from ml.longitudinal_model import train_state_model

def load_insight_trends(days=30, user_id: str | None = None):

    df = build_longitudinal_features(user_id)

    if df is None or len(df) == 0:
        return []

    df, _ = train_state_model(df)

    df = df.tail(days)

    trends = []

    for _, row in df.iterrows():
        def clean_value(key):
            val = row.get(key)
            if pd.notna(val) and not np.isinf(val):
                return val
            return None

        trends.append({
            "date": row["date"].strftime("%Y-%m-%d"),
            "mood": clean_value("sentiment_today"),
            "volatility": clean_value("rolling_std_7"),
            "trend_slope": clean_value("trend_slope_7"),
            "sleep_avg": clean_value("sleep_avg_7"),
            "sleep_var": clean_value("sleep_var_7"),
            "hrv": clean_value("hrv_avg_7"),
            "state": row.get("state") if pd.notna(row.get("state")) else "Unknown"
        })

    return trends
