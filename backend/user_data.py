import hashlib
import math
import numbers
import re
import shutil
from datetime import date, datetime
from pathlib import Path
from typing import Any

import pandas as pd

try:
    from research_schema import model_dataset_frame
except ModuleNotFoundError:
    from .research_schema import model_dataset_frame


BACKEND_DIR = Path(__file__).resolve().parent
USER_DATA_DIR = BACKEND_DIR / "user_runtime_data"
GLOBAL_DATA_DIR = BACKEND_DIR / "data"


def _ensure_firebase_app() -> bool:
    try:
        import firebase_admin
    except ImportError:
        return False

    try:
        if not firebase_admin._apps:
            firebase_admin.initialize_app()
        return True
    except Exception:
        return False


def safe_user_id(user_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]", "_", user_id or "unknown")


def user_storage_key(user_id: str) -> str:
    digest = hashlib.sha256((user_id or "unknown").encode("utf-8")).hexdigest()[:24]
    label = safe_user_id(user_id)[:40].strip("._-") or "user"
    return f"{digest}_{label}"


def user_dir(user_id: str) -> Path:
    path = USER_DATA_DIR / user_storage_key(user_id)
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


def _feature_collection(user_id: str):
    if not _ensure_firebase_app():
        return None

    try:
        from firebase_admin import firestore
    except ImportError:
        return None

    return (
        firestore.client()
        .collection("users")
        .document(user_storage_key(user_id))
        .collection("backend_ml_features")
    )


def persist_user_feature_records(user_id: str, records: list[dict[str, Any]]) -> int:
    collection = _feature_collection(user_id)
    if collection is None:
        return 0

    saved = 0
    try:
        for record in records:
            date_value = str(record.get("date") or "").strip()
            if not date_value:
                continue
            doc_id = re.sub(r"[^0-9A-Za-z_.-]", "_", date_value)
            collection.document(doc_id).set(record, merge=True)
            saved += 1
    except Exception:
        return 0
    return saved


def hydrate_user_dataset_from_firestore(user_id: str) -> bool:
    collection = _feature_collection(user_id)
    if collection is None:
        return False

    try:
        docs = list(collection.stream())
    except Exception:
        return False
    if not docs:
        return False

    rows = [doc.to_dict() for doc in docs if doc.to_dict()]
    if not rows:
        return False

    df = model_dataset_frame(rows)
    if "date" not in df.columns:
        return False

    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df = df.dropna(subset=["date"]).sort_values("date")
    if df.empty:
        return False

    dataset_path = user_dataset_path(user_id)
    daily_features_path = user_daily_features_path(user_id)
    df.to_csv(dataset_path, index=False)
    df.to_csv(daily_features_path, index=False)
    return True


def _json_safe(value: Any) -> Any:
    if value is None or isinstance(value, (str, bool)):
        return value
    if isinstance(value, numbers.Integral):
        return int(value)
    if isinstance(value, numbers.Real):
        number = float(value)
        return number if math.isfinite(number) else None
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_json_safe(item) for item in value]
    try:
        if pd.isna(value):
            return None
    except (TypeError, ValueError):
        pass
    return value


def export_user_runtime_data(user_id: str) -> dict[str, Any]:
    runtime_dir = user_dir(user_id)
    files = {}
    for path in runtime_dir.rglob("*"):
        if path.is_file():
            files[str(path.relative_to(runtime_dir)).replace("\\", "/")] = path.read_text(
                encoding="utf-8",
                errors="replace",
            )

    firestore_features: dict[str, Any] = {}
    collection = _feature_collection(user_id)
    if collection is not None:
        try:
            for doc in collection.stream():
                firestore_features[doc.id] = _json_safe(doc.to_dict())
        except Exception:
            firestore_features = {}

    return {
        "runtime_files": files,
        "firestore_backend_ml_features": firestore_features,
    }


def delete_user_runtime_data(user_id: str) -> dict[str, Any]:
    runtime_dir = USER_DATA_DIR / user_storage_key(user_id)
    resolved_runtime_dir = runtime_dir.resolve()
    resolved_user_data_dir = USER_DATA_DIR.resolve()
    if resolved_user_data_dir not in resolved_runtime_dir.parents:
        raise RuntimeError("Refusing to delete path outside user runtime data")
    deleted_runtime_dir = runtime_dir.exists()
    if runtime_dir.exists():
        shutil.rmtree(runtime_dir)

    deleted_feature_docs = 0
    collection = _feature_collection(user_id)
    if collection is not None:
        try:
            for doc in collection.stream():
                doc.reference.delete()
                deleted_feature_docs += 1
        except Exception:
            deleted_feature_docs = 0

    return {
        "deleted_runtime_dir": deleted_runtime_dir,
        "deleted_feature_docs": deleted_feature_docs,
    }


def active_dataset_path(user_id: str | None = None) -> Path:
    if user_id:
        user_path = user_dataset_path(user_id)
        if user_path.exists():
            return user_path
        if user_id == "local-dev":
            return GLOBAL_DATA_DIR / "ml_daily_dataset.csv"
        hydrate_user_dataset_from_firestore(user_id)
        if user_path.exists():
            return user_path
    return GLOBAL_DATA_DIR / "ml_daily_dataset.csv"
