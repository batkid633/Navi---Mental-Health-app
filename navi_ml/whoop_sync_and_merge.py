import json
import requests
import pandas as pd
from datetime import date, timedelta, datetime, timezone
import os
from dotenv import load_dotenv

load_dotenv()  # Load environment variables from .env file
API_BASE = "https://api.prod.whoop.com/developer/v2"
TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"
TOKEN_FILE = "navi_ml/tokens/whoop_tokens.json"

# refresh safety margin (seconds)
TOKEN_REFRESH_MARGIN = 60

WHOOP_CSV = "backend/data/whoop_daily_metrics.csv"
FEATURES_CSV = "backend/data/daily_features.csv"
MERGED_CSV = "backend/data/ml_daily_dataset.csv"


# --------------------
# Auth
# --------------------

def load_token_data():
    if not os.path.exists(TOKEN_FILE):
        raise FileNotFoundError(f"Token file not found: {TOKEN_FILE}. Run whoop_auth first.")
    with open(TOKEN_FILE) as f:
        return json.load(f)


def save_token_data(token_data: dict):
    with open(TOKEN_FILE, "w") as f:
        json.dump(token_data, f, indent=2)


def token_is_expired(token_data: dict) -> bool:
    expires_at = token_data.get("expires_at")
    if expires_at is None:
        return True
    return datetime.now(timezone.utc).timestamp() > (expires_at - TOKEN_REFRESH_MARGIN)


def refresh_whoop_token(token_data: dict) -> dict:
    refresh_token = token_data.get("refresh_token")
    if not refresh_token:
        raise RuntimeError("No refresh_token available in stored token data")

    data = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": os.getenv("WHOOP_CLIENT_ID"),
        "client_secret": os.getenv("WHOOP_CLIENT_SECRET"),
    }

    resp = requests.post(TOKEN_URL, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
    if resp.status_code != 200:
        raise RuntimeError(f"WHOOP refresh token failed: {resp.status_code} {resp.text}")

    new_tokens = resp.json()

    # Keep refresh token if provider doesn't return one
    if "refresh_token" not in new_tokens:
        new_tokens["refresh_token"] = refresh_token

    expires_in = new_tokens.get("expires_in")
    if expires_in is not None:
        new_tokens["expires_at"] = int(datetime.now(timezone.utc).timestamp() + int(expires_in))

    save_token_data(new_tokens)
    return new_tokens


def get_access_token():
    token_data = load_token_data()

    if token_is_expired(token_data):
        token_data = refresh_whoop_token(token_data)

    access_token = token_data.get("access_token")
    if not access_token:
        raise RuntimeError("No access_token in token file")

    return access_token


def fetch(endpoint: str):
    token = get_access_token()
    resp = requests.get(
        f"{API_BASE}/{endpoint}",
        headers={"Authorization": f"Bearer {token}"}
    )

    if resp.status_code == 401:
        token_data = refresh_whoop_token(load_token_data())
        resp = requests.get(
            f"{API_BASE}/{endpoint}",
            headers={"Authorization": f"Bearer {token_data.get('access_token')}"}
        )

    if resp.status_code == 404:
        raise RuntimeError(f"WHOOP endpoint not found: {endpoint}")

    resp.raise_for_status()
    return resp.json()


# --------------------
# Helpers
# --------------------
def safe_first(records):
    return records[0] if records else None


# --------------------
# WHOOP extraction (v2)
# --------------------
def sync_day(day_iso: str):
    sleep = fetch(f"activity/sleep?start_date={day_iso}&end_date={day_iso}")
    recovery = fetch(f"recovery?start_date={day_iso}&end_date={day_iso}")
    workout = fetch(f"activity/workout?start_date={day_iso}&end_date={day_iso}")

    sleep_rec = safe_first(sleep.get("records", []))
    rec_rec = safe_first(recovery.get("records", []))
    work_rec = safe_first(workout.get("records", []))

    return {
        "date": day_iso,

        # Sleep
      "sleep_hours": (
            sleep_rec["score"]["stage_summary"]["total_in_bed_time_milli"] / (1000 * 60 * 60)
            if sleep_rec
            and sleep_rec.get("score")
            and sleep_rec["score"].get("stage_summary")
            else None
        ),
        
        "sleep_efficiency": (
            sleep_rec["score"].get("sleep_efficiency_percentage")
            if sleep_rec else None
        ),

        # Recovery
        "resting_hr": (
            rec_rec["score"].get("resting_heart_rate")
            if rec_rec else None
        ),
        "hrv_rmssd": (
            rec_rec["score"].get("hrv_rmssd_milli")
            if rec_rec else None
        ),
        "recovery_score": (
            rec_rec["score"].get("recovery_score")
            if rec_rec else None
        ),

        # Training
        "strain": (
            work_rec["score"].get("strain")
            if work_rec else 0
        ),
    }


def append_whoop_row(row: dict):
    df = pd.DataFrame([row])
    df.to_csv(
        WHOOP_CSV,
        mode="a",
        index=False,
        header=not os.path.exists(WHOOP_CSV)
    )

# --------------------
# Merge for ML
# --------------------
def merge_with_features():
    if not os.path.exists(FEATURES_CSV):
        raise FileNotFoundError("daily_features.csv not found")

    whoop_df = pd.read_csv(WHOOP_CSV)
    whoop_df = (
        whoop_df
        .sort_values("date")
        .drop_duplicates(subset="date", keep="last")
    )
    features_df = pd.read_csv(FEATURES_CSV)
    whoop_df["date"] = pd.to_datetime(whoop_df["date"])
    features_df["date"] = pd.to_datetime(features_df["date"])

    merged = pd.merge(
        features_df,
        whoop_df,
        on="date",
        how="left"
    )

    merged.to_csv(MERGED_CSV, index=False)


# --------------------
# Entry point
# --------------------
if __name__ == "__main__":
    features_df = pd.read_csv(FEATURES_CSV)
    day = features_df["date"].max()

    row = sync_day(day)

    append_whoop_row(row)
    merge_with_features()

    print("WHOOP v2 sync + ML merge complete.")
