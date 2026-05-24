import re
from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parent
USER_DATA_DIR = BACKEND_DIR / "user_runtime_data"
GLOBAL_DATA_DIR = BACKEND_DIR / "data"


def safe_user_id(user_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]", "_", user_id or "unknown")


def user_dir(user_id: str) -> Path:
    path = USER_DATA_DIR / safe_user_id(user_id)
    path.mkdir(parents=True, exist_ok=True)
    return path


def user_logs_dir(user_id: str) -> Path:
    path = user_dir(user_id) / "logs"
    path.mkdir(parents=True, exist_ok=True)
    return path


def user_dataset_path(user_id: str) -> Path:
    return user_dir(user_id) / "ml_daily_dataset.csv"


def user_daily_features_path(user_id: str) -> Path:
    return user_dir(user_id) / "daily_features.csv"


def active_dataset_path(user_id: str | None = None) -> Path:
    if user_id:
        user_path = user_dataset_path(user_id)
        if user_path.exists():
            return user_path
    return GLOBAL_DATA_DIR / "ml_daily_dataset.csv"
