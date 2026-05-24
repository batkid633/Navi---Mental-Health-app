import pandas as pd
import numpy as np
from pathlib import Path
from sklearn.linear_model import LinearRegression
try:
    from user_data import active_dataset_path
except ModuleNotFoundError:
    from ..user_data import active_dataset_path

DATA_DIR = Path(__file__).resolve().parents[1] / "data"

def compute_slope(series):
    y = series.values
    
    if len(y) < 3 or np.isnan(y).any():
        return 0
    
    x = np.arange(len(y)).reshape(-1,1)
    
    model = LinearRegression().fit(x,y)
    return model.coef_[0]


def build_longitudinal_features(user_id: str | None = None):

    path = active_dataset_path(user_id)
    
    if not path.exists():
        return None

    df = pd.read_csv(path)
    df["date"] = pd.to_datetime(df["date"], errors='coerce')
    df = df.dropna(subset=['date'])
    df = df.sort_values("date")

    # rolling volatility
    df["rolling_std_7"] = df["sentiment_today"].rolling(7).std()

    # trend slope
    df["trend_slope_7"] = (
        df["sentiment_today"]
        .rolling(7)
        .apply(compute_slope, raw=False)
    )

    # sleep averages
    df["sleep_avg_7"] = df["sleep_hours"].rolling(7).mean()

    df["sleep_var_7"] = df["sleep_hours"].rolling(7).std()

    # HRV average
    df["hrv_avg_7"] = df["hrv_rmssd"].rolling(7).mean()

    # recovery lag (simple proxy)
    df["recovery_lag"] = df["z_score"].rolling(5).apply(
        lambda x: (x < -1).sum()
    )

    # dip frequency
    df["dip_freq_14"] = df["z_score"].rolling(14).apply(
        lambda x: (x < -0.5).sum()
    )

    return df
