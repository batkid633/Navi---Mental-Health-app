import uvicorn
from fastapi import BackgroundTasks, Depends, FastAPI, Request, UploadFile, File, HTTPException, Form, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field
from pathlib import Path
import asyncio
import csv
from collections import defaultdict, deque
import hashlib
import tempfile
import os
import sys
from datetime import datetime, timedelta
import json
import logging
import traceback
import time
import uuid
from dotenv import find_dotenv, load_dotenv
import pandas as pd

load_dotenv(find_dotenv(), override=False)

BACKEND_DIR = Path(__file__).resolve().parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

try:
    from config import BACKEND_DIR, SETTINGS, config_check
    from auth import CurrentUser, get_current_user, require_admin
    from sentiment.vader import analyze_sentiment
    from ml.predict_mood import predict_next_day
    from ml.trajectory_model import predict_trajectory
    from ml.validation_report import build_validation_report
    from ml.trajectory_v2 import (
        evaluate_trajectory_v2,
        predict_trajectory_v2,
        train_trajectory_v2,
    )
    from ml.feature_loader import load_features_for_date
    from ml.llm_insights import generate_insight, get_llm_insight, save_cached_insight
    from ml.insight_trends import load_insight_trends
    from ml.audio_mood import predict_audio_mood, analyze_audio_comprehensive, train_audio_mood_model, generate_emotional_intervention, analyze_mfcc_deep
    from ml.train_next_day_mood import train_next_day_model
    import fitbit_api
    import whoop_api
    from user_data import (
        delete_user_runtime_data,
        export_user_runtime_data,
        persist_user_feature_records,
        user_daily_features_path,
        user_dataset_path,
        user_logs_dir,
    )
except ModuleNotFoundError:
    from .config import BACKEND_DIR, SETTINGS, config_check
    from .auth import CurrentUser, get_current_user, require_admin
    from .sentiment.vader import analyze_sentiment
    from .ml.predict_mood import predict_next_day
    from .ml.trajectory_model import predict_trajectory
    from .ml.validation_report import build_validation_report
    from .ml.trajectory_v2 import (
        evaluate_trajectory_v2,
        predict_trajectory_v2,
        train_trajectory_v2,
    )
    from .ml.feature_loader import load_features_for_date
    from .ml.llm_insights import generate_insight, get_llm_insight, save_cached_insight
    from .ml.insight_trends import load_insight_trends
    from .ml.audio_mood import predict_audio_mood, analyze_audio_comprehensive, train_audio_mood_model, generate_emotional_intervention, analyze_mfcc_deep
    from .ml.train_next_day_mood import train_next_day_model
    from . import fitbit_api
    from . import whoop_api
    from .user_data import (
        delete_user_runtime_data,
        export_user_runtime_data,
        persist_user_feature_records,
        user_daily_features_path,
        user_dataset_path,
        user_logs_dir,
    )

STARTED_AT = time.time()
MONITORING_STATE = {
    "requests_total": 0,
    "requests_by_path": defaultdict(int),
    "requests_by_status": defaultdict(int),
    "product_events": defaultdict(int),
    "last_request_at": None,
}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service": SETTINGS.service_name,
            "version": SETTINGS.service_version,
        }
        for key in (
            "request_id",
            "method",
            "path",
            "status_code",
            "duration_ms",
            "client",
            "sample_count",
            "event_name",
            "user_hash",
            "metadata",
        ):
            value = getattr(record, key, None)
            if value is not None:
                payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging() -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())


configure_logging()
logger = logging.getLogger("navi.api")

app = FastAPI(title="Navi Backend", version=SETTINGS.service_version)

_rate_limit_windows: dict[str, deque[float]] = defaultdict(deque)
MAX_DAILY_FEATURE_RECORDS = 400
MAX_AUDIO_UPLOAD_BYTES = int(os.getenv("MAX_AUDIO_UPLOAD_BYTES", str(25 * 1024 * 1024)))
ALLOWED_AUDIO_MODES = {"emotional_venting", "deeper_analysis"}
ALLOWED_AUDIO_CONTENT_TYPES = {
    "audio/wav",
    "audio/x-wav",
    "audio/mpeg",
    "audio/mp4",
    "audio/aac",
    "audio/ogg",
    "audio/webm",
    "application/octet-stream",
}


def _parse_iso_date(value: str, field_name: str = "date") -> str:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError) as exc:
        raise HTTPException(status_code=422, detail=f"Invalid {field_name}") from exc
    return parsed.date().isoformat()


def _safe_upload_name(filename: str | None) -> str:
    name = Path(filename or "audio.wav").name
    return name[:120] or "audio.wav"


def _resolve_training_csv_path(path_value: str) -> Path:
    requested = Path(path_value).expanduser()
    if not requested.is_absolute():
        requested = BACKEND_DIR / requested
    resolved = requested.resolve()
    allowed_roots = [
        (BACKEND_DIR / "data").resolve(),
        (BACKEND_DIR / "user_runtime_data").resolve(),
    ]
    if not any(resolved == root or root in resolved.parents for root in allowed_roots):
        raise HTTPException(status_code=400, detail="Training CSV path is outside allowed data directories")
    if resolved.suffix.lower() != ".csv":
        raise HTTPException(status_code=400, detail="Training data must be a CSV file")
    return resolved

def _cors_origins() -> list[str]:
    configured = os.getenv("ALLOW_CORS_FROM", "")
    origins = [origin.strip() for origin in configured.split(",") if origin.strip()]
    if origins:
        return origins
    if os.getenv("ENVIRONMENT", "development").lower() == "production":
        return []
    return [
        "http://127.0.0.1:8000",
        "http://localhost:8000",
        "http://127.0.0.1:8080",
        "http://localhost:8080",
        "http://127.0.0.1:5000",
        "http://localhost:5000",
    ]

def _cors_origin_regex() -> str | None:
    if os.getenv("ENVIRONMENT", "development").lower() == "production":
        return None
    return r"https?://(localhost|127\.0\.0\.1)(:\d+)?"

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins(),
    allow_origin_regex=_cors_origin_regex(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _client_ip(request: Request) -> str:
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        return forwarded_for.split(",", 1)[0].strip()
    if request.client:
        return request.client.host
    return "unknown"


def _rate_limit_key(request: Request) -> str:
    authorization = request.headers.get("authorization")
    if authorization:
        return hashlib.sha256(authorization.encode("utf-8")).hexdigest()
    return _client_ip(request)


def _user_hash(user_id: str) -> str:
    return hashlib.sha256(user_id.encode("utf-8")).hexdigest()[:12]


def log_product_event(
    event_name: str,
    current_user: CurrentUser,
    metadata: dict | None = None,
) -> None:
    safe_metadata = {}
    for key, value in (metadata or {}).items():
        if value is None or isinstance(value, (str, int, float, bool)):
            safe_metadata[str(key)] = value
    MONITORING_STATE["product_events"][event_name] += 1
    logger.info(
        "product_event",
        extra={
            "event_name": event_name,
            "user_hash": _user_hash(current_user.uid),
            "metadata": safe_metadata,
        },
    )


def _is_rate_limited(request: Request) -> bool:
    if SETTINGS.rate_limit_per_minute <= 0:
        return False
    if request.url.path in {"/health", "/live", "/ready"}:
        return False

    now = time.monotonic()
    window = _rate_limit_windows[_rate_limit_key(request)]
    while window and now - window[0] > 60:
        window.popleft()
    if len(window) >= SETTINGS.rate_limit_per_minute:
        return True
    window.append(now)
    return False


@app.middleware("http")
async def production_guardrails(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    started = time.perf_counter()
    status_code = 500

    if _is_rate_limited(request):
        status_code = 429
        response = JSONResponse(
            status_code=status_code,
            content={"detail": "Rate limit exceeded"},
            headers={"x-request-id": request_id},
        )
    else:
        try:
            response = await asyncio.wait_for(
                call_next(request),
                timeout=SETTINGS.request_timeout_seconds,
            )
            status_code = response.status_code
            response.headers["x-request-id"] = request_id
        except asyncio.TimeoutError:
            status_code = 504
            response = JSONResponse(
                status_code=status_code,
                content={"detail": "Request timed out"},
                headers={"x-request-id": request_id},
            )
        except Exception:
            logger.exception(
                "request_failed",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "client": _client_ip(request),
                },
            )
            status_code = 500
            response = JSONResponse(
                status_code=status_code,
                content={"detail": "Internal server error"},
                headers={"x-request-id": request_id},
            )

    duration_ms = round((time.perf_counter() - started) * 1000, 2)
    MONITORING_STATE["requests_total"] += 1
    MONITORING_STATE["requests_by_path"][request.url.path] += 1
    MONITORING_STATE["requests_by_status"][str(status_code)] += 1
    MONITORING_STATE["last_request_at"] = datetime.utcnow().isoformat() + "Z"
    logger.info(
        "request_complete",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "status_code": status_code,
            "duration_ms": duration_ms,
            "client": _client_ip(request),
        },
    )
    return response

LOG_DIR = BACKEND_DIR / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)

PREDICTION_LOG = LOG_DIR / "prediction_log.csv"
INSIGHT_LOG = LOG_DIR / "insight_log.jsonl"

def _prediction_log_for(user_id: str) -> Path:
    return user_logs_dir(user_id) / "prediction_log.csv"

def _insight_log_for(user_id: str) -> Path:
    return user_logs_dir(user_id) / "insight_log.jsonl"

def make_json_safe(obj):
    if isinstance(obj, dict):
        return {k: make_json_safe(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [make_json_safe(v) for v in obj]
    if hasattr(obj, "isoformat"):
        return obj.isoformat()
    return obj

def log_prediction_event(event: dict):
    """
    Writes:
    - numeric fields → CSV (for ML analysis)
    - full event → JSONL (for traceability)
    """

    # ---- CSV (ML-friendly) ----
    prediction_log = _prediction_log_for(event["user_id"])
    insight_log = _insight_log_for(event["user_id"])
    csv_exists = prediction_log.exists()

    with open(prediction_log, "a", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "timestamp",
                "user_id",
                "date",
                "model_version",
                "predicted_delta",
                "confidence",
            ],
        )

        if not csv_exists:
            writer.writeheader()

        writer.writerow({
            "timestamp": event["timestamp"],
            "user_id": event["user_id"],
            "date": event["date"],
            "model_version": event["model_version"],
            "predicted_delta": event["predicted_delta"],
            "confidence": event["confidence"],
        })

    # ---- JSONL (full context) ----
    with open(insight_log, "a") as f:
        safe_event = make_json_safe(event)
        f.write(json.dumps(safe_event) + "\n")

class JournalRequest(BaseModel):
    text: str = Field(min_length=1, max_length=20000)

@app.post("/sentiment")
def sentiment_endpoint(req: JournalRequest, current_user: CurrentUser = Depends(get_current_user)):
    try:
        log_product_event("sentiment_requested", current_user)
        return analyze_sentiment(req.text)
    except Exception:
        logger.exception("sentiment_analysis_failed")
        log_product_event("sentiment_failed", current_user)
        return {
            "sentiment": 0.0,
            "error": "sentiment_analysis_failed"
        }
class PredictRequest(BaseModel):
    date: str = Field(min_length=8, max_length=40)
    force_reload: bool = False

class TrajectoryTrainRequest(BaseModel):
    activate: bool = True

class AudioTrainRequest(BaseModel):
    training_csv_path: str = Field(min_length=1, max_length=500)

class DailyFeatureRecord(BaseModel):
    date: str = Field(min_length=8, max_length=40)
    sentiment_today: float
    rolling_mean_7: float | None = None
    volatility_7: float | None = None
    momentum_7: float | None = None
    z_score: float | None = None
    is_anomalous: int | None = None
    day_of_week: int | None = None
    Next_day_delta: float | None = None
    sleep_hours: float | None = None
    sleep_efficiency: float | None = None
    resting_hr: float | None = None
    hrv_rmssd: float | None = None
    recovery_score: float | None = None
    strain: float | None = None
    audio_session_count: float | None = None
    audio_total_seconds: float | None = None
    audio_negative_ratio: float | None = None
    audio_positive_ratio: float | None = None
    audio_anxious_ratio: float | None = None
    audio_calm_ratio: float | None = None
    audio_training_count: float | None = None
    keyboard_session_count: float | None = None
    keyboard_active_seconds: float | None = None
    keyboard_event_count: float | None = None
    keyboard_chars_estimated: float | None = None
    keyboard_backspace_count: float | None = None
    keyboard_correction_rate: float | None = None
    keyboard_pause_mean_ms: float | None = None
    keyboard_pause_std_ms: float | None = None
    keyboard_burst_count: float | None = None
    keyboard_typing_speed_cpm: float | None = None
    keyboard_late_night_ratio: float | None = None
    keyboard_platform_web: float | None = None
    keyboard_platform_mobile: float | None = None
    keyboard_platform_desktop: float | None = None
    missing_journal: int | None = None
    missing_biometrics: int | None = None
    missing_audio: int | None = None
    missing_keyboard: int | None = None
    missing_sleep: int | None = None
    missing_hrv: int | None = None
    missing_recovery: int | None = None

class DailyFeaturesRequest(BaseModel):
    records: list[DailyFeatureRecord] = Field(default_factory=list, max_length=MAX_DAILY_FEATURE_RECORDS)

class CheckInDispatchRequest(BaseModel):
    dry_run: bool = True
    due_only: bool = True
    limit: int = Field(default=500, ge=1, le=5000)
    title: str = Field(default="Navi check-in", min_length=1, max_length=80)
    body: str = Field(default="Time for your Navi check-in.", min_length=1, max_length=180)

def _firebase_admin_clients():
    try:
        import firebase_admin
        from firebase_admin import firestore, messaging
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Firebase Admin is not available") from exc

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    return firestore.client(), firestore, messaging

def _require_notification_dispatcher(
    authorization: str | None = Header(default=None),
    x_navi_scheduler_secret: str | None = Header(default=None),
) -> CurrentUser:
    scheduler_secret = os.getenv("NOTIFICATION_DISPATCH_SECRET", "").strip()
    if scheduler_secret and x_navi_scheduler_secret == scheduler_secret:
        return CurrentUser(uid="scheduler", claims={"scheduler": True})

    current_user = get_current_user(authorization)
    return require_admin(current_user)

def _notification_device_is_due(device: dict, now_utc: datetime) -> tuple[bool, str]:
    try:
        offset_minutes = int(device.get("timezoneOffsetMinutes") or 0)
    except (TypeError, ValueError):
        offset_minutes = 0
    try:
        check_in_minutes = int(device.get("checkInTimeMinutes") or 20 * 60)
    except (TypeError, ValueError):
        check_in_minutes = 20 * 60

    local_now = now_utc + timedelta(minutes=offset_minutes)
    local_date = local_now.date().isoformat()
    if device.get("lastCheckInPromptLocalDate") == local_date:
        return False, "already_sent_today"

    current_minutes = local_now.hour * 60 + local_now.minute
    if current_minutes < check_in_minutes:
        return False, "not_due_yet"

    return True, local_date

@app.post("/notifications/check-in/dispatch")
def dispatch_check_in_notifications(
    req: CheckInDispatchRequest,
    current_user: CurrentUser = Depends(_require_notification_dispatcher),
):
    db, firestore, messaging = _firebase_admin_clients()
    now_utc = datetime.utcnow()
    query = (
        db.collection_group("notification_devices")
        .where("checkInEnabled", "==", True)
        .limit(req.limit)
    )
    scanned = sent = skipped = failed = 0
    errors: list[dict] = []

    for doc in query.stream():
        scanned += 1
        device = doc.to_dict() or {}
        token = str(device.get("token") or "").strip()
        if not token:
            skipped += 1
            continue

        due, reason_or_date = _notification_device_is_due(device, now_utc)
        if req.due_only and not due:
            skipped += 1
            continue

        local_date = reason_or_date if due else now_utc.date().isoformat()
        if not req.dry_run:
            try:
                messaging.send(
                    messaging.Message(
                        token=token,
                        notification=messaging.Notification(
                            title=req.title,
                            body=req.body,
                        ),
                        data={
                            "type": "check_in_prompt",
                            "route": "journal",
                            "local_date": local_date,
                        },
                    )
                )
                doc.reference.update(
                    {
                        "lastCheckInPromptLocalDate": local_date,
                        "lastCheckInPromptSentAt": firestore.SERVER_TIMESTAMP,
                    }
                )
            except Exception as exc:
                failed += 1
                errors.append({"device": doc.reference.path, "error": str(exc)[:160]})
                continue

        sent += 1

    log_product_event(
        "check_in_notifications_dispatched",
        current_user,
        {
            "dry_run": req.dry_run,
            "due_only": req.due_only,
            "scanned": scanned,
            "sent": sent,
            "skipped": skipped,
            "failed": failed,
        },
    )
    return {
        "dry_run": req.dry_run,
        "due_only": req.due_only,
        "scanned": scanned,
        "sent": sent,
        "skipped": skipped,
        "failed": failed,
        "errors": errors[:20],
    }

@app.get("/data/export")
def export_my_backend_data(current_user: CurrentUser = Depends(get_current_user)):
    return {
        "user_id": current_user.uid,
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "backend": export_user_runtime_data(current_user.uid),
    }

@app.delete("/data/delete")
def delete_my_backend_data(current_user: CurrentUser = Depends(get_current_user)):
    result = delete_user_runtime_data(current_user.uid)
    return {
        "user_id": current_user.uid,
        "deleted_at": datetime.utcnow().isoformat() + "Z",
        **result,
    }

@app.post("/predict/tomorrow")
def predict_tomorrow(req: PredictRequest, current_user: CurrentUser = Depends(get_current_user)):
    req.date = _parse_iso_date(req.date)
    
    features = load_features_for_date(req.date, current_user.uid)
    
    try:
        legacy_result = predict_next_day(features, current_user.uid)
        trajectory_result = predict_trajectory(
            features,
            current_user.uid,
            legacy_next_day=legacy_result,
        )
        result = {
            **legacy_result,
            **trajectory_result,
            "raw_next_day_model": legacy_result,
            "model_version": f"{legacy_result.get('model_version', 'unknown')}+trajectory_v1",
        }
    except Exception:
        result = {
            "predicted_delta": 0.0,
            "confidence": 0.0,
            "model_version": "v1",
            "trajectory": [],
            "trajectory_summary": {
                "direction": "unknown",
                "model_family": "unavailable",
            },
            "modality_coverage": {
                "modalities": {
                    "journal": False,
                    "biometric": False,
                    "audio": False,
                    "keyboard": False,
                },
                "available_modalities": [],
                "coverage_ratio": 0.0,
            },
            "validation": {"validation_ready": False, "reason": "prediction_failed"},
        }

    event = {
        "timestamp": datetime.utcnow().isoformat(),
        "user_id": current_user.uid,
        "date": req.date,
        "model_version": result.get("model_version", "v1"),
        "predicted_delta": result["predicted_delta"],
        "confidence": result["confidence"],
        "features": features,
    }
    insight_context = {
        **features,
        "predicted_delta": result["predicted_delta"],
        "confidence": result["confidence"],
        "trajectory": result.get("trajectory", []),
        "trajectory_summary": result.get("trajectory_summary", {}),
        "modality_coverage": result.get("modality_coverage", {}),
        "validation": result.get("validation", {}),
    }
    if req.force_reload == True:
        insight = generate_insight(insight_context)
        # Force reload bypasses the cache but still writes into the user-scoped
        # cache for future non-forced requests.
        save_cached_insight(req.date, insight, current_user.uid)
    else:
        insight = get_llm_insight(req.date, insight_context, current_user.uid)

    event["insight"] = insight

    log_prediction_event(event)
    log_product_event(
        "tomorrow_prediction_generated",
        current_user,
        {
            "force_reload": req.force_reload,
            "confidence": result.get("confidence"),
            "model_version": result.get("model_version"),
            "calibrated": result.get("calibration", {}).get("applied")
            if isinstance(result.get("calibration"), dict)
            else None,
        },
    )

    return {
        **result,
        "insight": event["insight"],
    }

@app.post("/predict/trajectory")
def predict_mood_trajectory(
    req: PredictRequest,
    current_user: CurrentUser = Depends(get_current_user),
):
    req.date = _parse_iso_date(req.date)
    features = load_features_for_date(req.date, current_user.uid)
    try:
        legacy_result = predict_next_day(features, current_user.uid)
        trajectory_result = predict_trajectory(
            features,
            current_user.uid,
            legacy_next_day=legacy_result,
        )
        result = {
            **trajectory_result,
            "raw_next_day_model": legacy_result,
            "model_version": f"{legacy_result.get('model_version', 'unknown')}+trajectory_v1",
        }
    except Exception:
        logger.exception("trajectory_prediction_failed")
        raise HTTPException(status_code=500, detail="Trajectory prediction failed")

    log_product_event(
        "trajectory_prediction_generated",
        current_user,
        {
            "confidence": result.get("confidence"),
            "model_version": result.get("model_version"),
            "coverage_ratio": result.get("modality_coverage", {}).get("coverage_ratio")
            if isinstance(result.get("modality_coverage"), dict)
            else None,
        },
    )
    return result

@app.post("/predict/trajectory-v2")
def predict_mood_trajectory_v2(
    req: PredictRequest,
    current_user: CurrentUser = Depends(get_current_user),
):
    req.date = _parse_iso_date(req.date)
    features = load_features_for_date(req.date, current_user.uid)
    try:
        result = predict_trajectory_v2(features, current_user.uid)
        log_product_event(
            "trajectory_v2_prediction_generated",
            current_user,
            {
                "confidence": result.get("confidence"),
                "model_version": result.get("model_version"),
            },
        )
        return result
    except Exception:
        logger.exception("trajectory_v2_prediction_failed")
        raise HTTPException(status_code=500, detail="Trajectory v2 prediction failed")

@app.post("/ml/daily-features")
def save_daily_features(
    req: DailyFeaturesRequest,
    current_user: CurrentUser = Depends(get_current_user),
):
    if len(req.records) > MAX_DAILY_FEATURE_RECORDS:
        raise HTTPException(status_code=413, detail="Too many daily feature records")
    if current_user.claims and current_user.claims.get("auth_disabled"):
        return {
            "saved": 0,
            "skipped": True,
            "reason": "auth_disabled_local_dev",
        }

    rows = [record.dict() for record in req.records]
    for row in rows:
        row["date"] = _parse_iso_date(str(row.get("date") or ""))
    if not rows:
        return {"saved": 0}

    df = pd.DataFrame(rows)
    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df = df.dropna(subset=["date"])
    df = df.sort_values("date")

    feature_path = user_daily_features_path(current_user.uid)
    dataset_path = user_dataset_path(current_user.uid)
    df.to_csv(feature_path, index=False)
    df.to_csv(dataset_path, index=False)
    durable_saved = persist_user_feature_records(current_user.uid, rows)
    log_product_event(
        "daily_features_saved",
        current_user,
        {"saved": len(df), "durable_saved": durable_saved},
    )

    return {
        "saved": len(df),
        "durable_saved": durable_saved,
        "feature_path": str(feature_path),
        "dataset_path": str(dataset_path),
    }

from ml.insight_trends import load_insight_trends

# Audio Analysis Endpoints
@app.post("/audio/analyze")
async def analyze_audio(
    file: UploadFile = File(...),
    mode: str = Form("emotional_venting"),
    current_user: CurrentUser = Depends(get_current_user),
):
    """Analyze uploaded audio file for mood detection"""
    if mode not in ALLOWED_AUDIO_MODES:
        raise HTTPException(status_code=400, detail="Unknown analysis mode")
    if file.content_type and file.content_type not in ALLOWED_AUDIO_CONTENT_TYPES:
        raise HTTPException(status_code=415, detail="Unsupported audio content type")
    content = await file.read()
    if len(content) > MAX_AUDIO_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Audio upload too large")

    try:
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
            temp_path = temp_file.name
            temp_file.write(content)

        try:
            if mode == "emotional_venting":
                # Exploratory ML model for emotional venting
                mood_result = predict_audio_mood(temp_path, current_user.uid)
                audio_analysis = analyze_audio_comprehensive(temp_path)
                
                # Add intervention suggestions based on mood
                intervention = generate_emotional_intervention(mood_result)
                log_product_event(
                    "audio_analyzed",
                    current_user,
                    {
                        "mode": mode,
                        "model_status": mood_result.get("model_status")
                        if isinstance(mood_result, dict)
                        else None,
                        "personalized": mood_result.get("personalized")
                        if isinstance(mood_result, dict)
                        else None,
                    },
                )
                
                return {
                    "filename": _safe_upload_name(file.filename),
                    "mode": mode,
                    "mood_analysis": mood_result,
                    "audio_features": audio_analysis,
                    "intervention": intervention
                }
            elif mode == "deeper_analysis":
                # Deep MFCC analysis for structured assessment
                mood_result = predict_audio_mood(temp_path, current_user.uid)
                audio_analysis = analyze_audio_comprehensive(temp_path)
                mfcc_analysis = analyze_mfcc_deep(temp_path)
                log_product_event(
                    "audio_analyzed",
                    current_user,
                    {
                        "mode": mode,
                        "model_status": mood_result.get("model_status")
                        if isinstance(mood_result, dict)
                        else None,
                        "personalized": mood_result.get("personalized")
                        if isinstance(mood_result, dict)
                        else None,
                    },
                )
                
                return {
                    "filename": _safe_upload_name(file.filename),
                    "mode": mode,
                    "mood_analysis": mood_result,
                    "audio_features": audio_analysis,
                    "mfcc_analysis": mfcc_analysis
                }
                
        finally:
            # Clean up temp file
            os.unlink(temp_path)

    except HTTPException:
        raise
    except Exception:
        logger.exception("audio_analysis_failed")
        log_product_event("audio_analysis_failed", current_user, {"mode": mode})
        raise HTTPException(status_code=500, detail="Audio analysis failed")

@app.post("/audio/train")
def train_audio_model(
    req: AudioTrainRequest,
    current_user: CurrentUser = Depends(require_admin),
):
    """Train the audio mood classification model"""
    try:
        training_csv_path = _resolve_training_csv_path(req.training_csv_path)
        success = train_audio_mood_model(str(training_csv_path), current_user.uid)
        if success:
            log_product_event("audio_model_trained", current_user)
            return {"message": "Audio mood model trained successfully"}
        raise HTTPException(status_code=400, detail="Training failed - check training data")
    except HTTPException:
        raise
    except Exception:
        logger.exception("audio_training_failed")
        raise HTTPException(status_code=500, detail="Training failed")

def _service_info() -> dict:
    return {
        "service": SETTINGS.service_name,
        "version": SETTINGS.service_version,
        "environment": SETTINGS.environment,
    }

def _check_writable(path: Path) -> dict:
    try:
        path.mkdir(parents=True, exist_ok=True)
        probe = path / ".healthcheck"
        probe.write_text(datetime.utcnow().isoformat(), encoding="utf-8")
        probe.unlink(missing_ok=True)
        return {"ok": True}
    except Exception as exc:
        return {"ok": False, "error": exc.__class__.__name__}

@app.get("/")
def root():
    return {"message": "Navi Backend Running", **_service_info()}

@app.get("/version")
def version():
    return _service_info()

@app.get("/config-check")
def get_config_check(current_user: CurrentUser = Depends(require_admin)):
    return config_check()

@app.get("/live")
def liveness_check():
    return {"status": "live", **_service_info()}

@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "uptime_seconds": round(time.time() - STARTED_AT, 2),
        **_service_info(),
    }

@app.get("/monitoring/summary")
def monitoring_summary(current_user: CurrentUser = Depends(require_admin)):
    return {
        "uptime_seconds": round(time.time() - STARTED_AT, 2),
        "requests_total": MONITORING_STATE["requests_total"],
        "requests_by_path": dict(MONITORING_STATE["requests_by_path"]),
        "requests_by_status": dict(MONITORING_STATE["requests_by_status"]),
        "product_events": dict(MONITORING_STATE["product_events"]),
        "last_request_at": MONITORING_STATE["last_request_at"],
        **_service_info(),
    }

@app.get("/ready")
def readiness_check():
    checks = {
        "logs_writable": _check_writable(LOG_DIR),
        "user_runtime_writable": _check_writable(BACKEND_DIR / "user_runtime_data"),
        "config": config_check(),
    }
    ready = checks["logs_writable"]["ok"] and checks["user_runtime_writable"]["ok"]
    if SETTINGS.environment == "production":
        ready = ready and checks["config"]["ok"]
    return JSONResponse(
        status_code=200 if ready else 503,
        content={"status": "ready" if ready else "not_ready", "checks": checks, **_service_info()},
    )

@app.get("/whoop/connect")
def whoop_connect(
    request: Request,
    current_user: CurrentUser = Depends(get_current_user),
):
    try:
        redirect_base = str(request.base_url).rstrip('/')
        redirect_uri = whoop_api.resolve_whoop_redirect_uri(redirect_base)
        auth_url = whoop_api.generate_whoop_auth_url(redirect_uri)
        return {
            "auth_url": auth_url,
            "redirect_uri": redirect_uri,
        }
    except Exception:
        logger.exception("whoop_connect_failed")
        raise HTTPException(status_code=500, detail="WHOOP connect failed")

@app.get("/whoop/status")
def whoop_status(current_user: CurrentUser = Depends(get_current_user)):
    try:
        return whoop_api.get_whoop_status()
    except Exception:
        logger.exception("whoop_status_failed")
        raise HTTPException(status_code=500, detail="WHOOP status failed")

@app.get("/fitbit/connect")
def fitbit_connect(
    request: Request,
    current_user: CurrentUser = Depends(get_current_user),
):
    try:
        redirect_base = str(request.base_url).rstrip('/')
        redirect_uri = fitbit_api.resolve_fitbit_redirect_uri(redirect_base)
        auth_url = fitbit_api.generate_fitbit_auth_url(redirect_uri)
        return {
            "auth_url": auth_url,
            "redirect_uri": redirect_uri,
        }
    except RuntimeError as exc:
        if "credentials are not configured" in str(exc):
            raise HTTPException(status_code=503, detail=str(exc))
        logger.exception("fitbit_connect_failed")
        raise HTTPException(status_code=500, detail="Fitbit connect failed")
    except Exception:
        logger.exception("fitbit_connect_failed")
        raise HTTPException(status_code=500, detail="Fitbit connect failed")

@app.get("/fitbit/status")
def fitbit_status(current_user: CurrentUser = Depends(get_current_user)):
    try:
        return fitbit_api.get_fitbit_status()
    except Exception:
        logger.exception("fitbit_status_failed")
        raise HTTPException(status_code=500, detail="Fitbit status failed")

@app.get("/apple-health/status")
def apple_health_status(current_user: CurrentUser = Depends(get_current_user)):
    return {
        "connected": False,
        "configured": False,
        "setup_required": True,
        "platform_native": True,
        "message": (
            "Apple Health uses native HealthKit permissions in the iOS app. "
            "Add HealthKit entitlements and the Flutter health integration before enabling sync."
        ),
    }

@app.get("/journal/history")
def journal_history(current_user: CurrentUser = Depends(get_current_user)):
    history_path = BACKEND_DIR / "data" / "daily_features.csv"
    if not history_path.exists():
        return {"data": []}

    entries = []
    with open(history_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            date_value = row.get("date")
            sentiment_value = row.get("sentiment_today")
            if not date_value or sentiment_value in (None, ""):
                continue
            try:
                sentiment_score = float(sentiment_value)
            except ValueError:
                continue

            entries.append({
                "id": f"historical-{date_value}",
                "date": date_value,
                "text": (
                    "Historical mood sample imported from local training data. "
                    "Original journal text is not available in the current repo."
                ),
                "sentimentScore": sentiment_score,
                "sentimentLabel": _sentiment_label(sentiment_score),
            })

    return {"data": entries}

def _sentiment_label(score: float) -> str:
    if score > 0.05:
        return "positive"
    if score < -0.05:
        return "negative"
    return "neutral"

BIOMETRIC_COLUMNS = [
    "sleep_hours",
    "sleep_efficiency",
    "resting_hr",
    "hrv_rmssd",
    "recovery_score",
    "strain",
]


def _merge_biometric_metrics_into_user_dataset(
    user_id: str,
    metric_rows: list[dict],
) -> dict:
    dataset_path = user_dataset_path(user_id)
    if dataset_path.exists():
        df = pd.read_csv(dataset_path)
    else:
        global_dataset = BACKEND_DIR / "data" / "ml_daily_dataset.csv"
        if user_id == "local-dev" and global_dataset.exists():
            df = pd.read_csv(global_dataset)
        else:
            df = pd.DataFrame(columns=["date"])

    if (
        user_id == "local-dev"
        and "sentiment_today" not in df.columns
        or (
            user_id == "local-dev"
            and "sentiment_today" in df.columns
            and df["sentiment_today"].notna().sum() == 0
        )
    ):
        global_dataset = BACKEND_DIR / "data" / "ml_daily_dataset.csv"
        if global_dataset.exists():
            base = pd.read_csv(global_dataset)
            df = pd.concat([base, df], ignore_index=True)
            df = df.drop_duplicates(subset=["date"], keep="last")

    if "date" not in df.columns:
        df["date"] = None
    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df = df.dropna(subset=["date"])

    incoming = pd.DataFrame(metric_rows)
    if incoming.empty or "date" not in incoming.columns:
        return {"saved": 0, "dataset_path": str(dataset_path)}

    incoming["date"] = pd.to_datetime(incoming["date"], errors="coerce")
    incoming = incoming.dropna(subset=["date"]).sort_values("date")
    if incoming.empty:
        return {"saved": 0, "dataset_path": str(dataset_path)}

    for column in BIOMETRIC_COLUMNS:
        if column not in incoming.columns:
            incoming[column] = None
        if column not in df.columns:
            df[column] = None

    if "missing_biometrics" not in df.columns:
        df["missing_biometrics"] = 1
    for column in ("missing_sleep", "missing_hrv", "missing_recovery"):
        if column not in df.columns:
            df[column] = 1
    if "missing_journal" not in df.columns:
        df["missing_journal"] = df.get("sentiment_today", pd.Series([None] * len(df))).isna().astype(int)
    if "missing_audio" not in df.columns:
        df["missing_audio"] = 1
    if "missing_keyboard" not in df.columns:
        df["missing_keyboard"] = 1

    df = df.set_index("date", drop=False)
    for _, row in incoming.iterrows():
        date_value = row["date"]
        if date_value not in df.index:
            df.loc[date_value, "date"] = date_value
            df.loc[date_value, "missing_journal"] = 1
            df.loc[date_value, "missing_audio"] = 1
            df.loc[date_value, "missing_keyboard"] = 1
        for column in BIOMETRIC_COLUMNS:
            value = row.get(column)
            if pd.notna(value):
                df.loc[date_value, column] = value

        df.loc[date_value, "missing_biometrics"] = 0
        df.loc[date_value, "missing_sleep"] = 0 if pd.notna(df.loc[date_value].get("sleep_hours")) else 1
        df.loc[date_value, "missing_hrv"] = 0 if pd.notna(df.loc[date_value].get("hrv_rmssd")) else 1
        df.loc[date_value, "missing_recovery"] = 0 if pd.notna(df.loc[date_value].get("recovery_score")) else 1

    df = df.reset_index(drop=True).sort_values("date")
    df["date"] = pd.to_datetime(df["date"], errors="coerce").dt.date.astype(str)
    dataset_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(dataset_path, index=False)
    df.to_csv(user_daily_features_path(user_id), index=False)

    records = df[df["date"].isin(incoming["date"].dt.date.astype(str))].to_dict("records")
    durable_saved = persist_user_feature_records(user_id, records)
    return {
        "saved": len(records),
        "durable_saved": durable_saved,
        "dataset_path": str(dataset_path),
        "date_start": incoming["date"].min().date().isoformat(),
        "date_end": incoming["date"].max().date().isoformat(),
    }

@app.get("/whoop/callback")
def whoop_callback(request: Request, code: str | None = None, state: str | None = None):
    if not code or not state:
        raise HTTPException(status_code=400, detail="Missing code or state")

    redirect_base = str(request.base_url).rstrip('/')
    redirect_uri = whoop_api.resolve_whoop_redirect_uri(redirect_base)

    try:
        whoop_api.handle_whoop_callback(code, state, redirect_uri)
        return HTMLResponse(
            '<html><body><h1>WHOOP connected successfully.</h1><p>You can close this tab and return to the app.</p></body></html>'
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception:
        logger.exception("whoop_callback_failed")
        raise HTTPException(status_code=500, detail="WHOOP callback failed")

@app.post("/whoop/sync")
def whoop_sync_daily_metrics(
    days: int = 30,
    current_user: CurrentUser = Depends(get_current_user),
):
    try:
        metric_rows = whoop_api.fetch_daily_metrics(days)
        result = _merge_biometric_metrics_into_user_dataset(
            current_user.uid,
            metric_rows,
        )
        log_product_event(
            "whoop_daily_metrics_synced",
            current_user,
            {
                "requested_days": days,
                "fetched": len(metric_rows),
                "saved": result.get("saved"),
            },
        )
        return {
            "requested_days": days,
            "fetched": len(metric_rows),
            **result,
        }
    except FileNotFoundError:
        return {
            "requested_days": days,
            "fetched": 0,
            "saved": 0,
            "connected": False,
            "detail": "WHOOP is not connected.",
        }
    except Exception:
        logger.exception("whoop_sync_failed")
        raise HTTPException(status_code=500, detail="WHOOP sync failed")

@app.post("/fitbit/sync")
@app.post("/google-health/sync")
def google_health_sync_daily_metrics(
    days: int = 30,
    current_user: CurrentUser = Depends(get_current_user),
):
    days = max(1, min(days, 90))
    today = datetime.utcnow().date()
    day_values = [
        (today - timedelta(days=offset)).isoformat()
        for offset in range(days - 1, -1, -1)
    ]

    try:
        metric_rows = [
            fitbit_api.sync_google_health_day(day_value)
            for day_value in day_values
        ]
        metric_rows = [
            row for row in metric_rows
            if any(pd.notna(row.get(column)) for column in BIOMETRIC_COLUMNS)
        ]
        result = _merge_biometric_metrics_into_user_dataset(
            current_user.uid,
            metric_rows,
        )
        log_product_event(
            "google_health_daily_metrics_synced",
            current_user,
            {
                "requested_days": days,
                "fetched": len(metric_rows),
                "saved": result.get("saved"),
            },
        )
        return {
            "provider": "google_health",
            "requested_days": days,
            "fetched": len(metric_rows),
            **result,
        }
    except FileNotFoundError:
        return {
            "provider": "google_health",
            "requested_days": days,
            "fetched": 0,
            "saved": 0,
            "connected": False,
            "detail": "Google Health is not connected.",
        }
    except Exception:
        logger.exception("google_health_sync_failed")
        raise HTTPException(status_code=500, detail="Google Health sync failed")

@app.get("/fitbit/callback")
def fitbit_callback(request: Request, code: str | None = None, state: str | None = None):
    if not code or not state:
        raise HTTPException(status_code=400, detail="Missing code or state")

    redirect_base = str(request.base_url).rstrip('/')
    redirect_uri = fitbit_api.resolve_fitbit_redirect_uri(redirect_base)

    try:
        fitbit_api.handle_fitbit_callback(code, state, redirect_uri)
        return HTMLResponse(
            '<html><body><h1>Fitbit connected successfully.</h1><p>You can close this tab and return to the app.</p></body></html>'
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception:
        logger.exception("fitbit_callback_failed")
        raise HTTPException(status_code=500, detail="Fitbit callback failed")

@app.post("/whoop/retrain")
def whoop_retrain(
    background_tasks: BackgroundTasks,
    current_user: CurrentUser = Depends(require_admin),
):
    try:
        background_tasks.add_task(train_next_day_model, True)
        return {"message": "Retraining started"}
    except Exception:
        logger.exception("whoop_retrain_failed")
        raise HTTPException(status_code=500, detail="Retraining failed")

@app.get("/insights/trends")
def get_insight_trends(
    days: int = 14,
    current_user: CurrentUser = Depends(get_current_user),
):
    try:
        data = load_insight_trends(days, current_user.uid)
        return {
            "days": days,
            "data": data
        }
    except Exception:
        logger.exception("insight_trends_failed")
        raise HTTPException(status_code=500, detail="Insight trends failed")

@app.get("/model/validation-report")
def get_model_validation_report(
    current_user: CurrentUser = Depends(get_current_user),
):
    try:
        report = build_validation_report(current_user.uid)
        log_product_event(
            "model_validation_report_loaded",
            current_user,
            {
                "row_count": report.get("row_count"),
                "study_ready": report.get("readiness", {}).get("study_ready")
                if isinstance(report.get("readiness"), dict)
                else None,
            },
        )
        return report
    except Exception:
        logger.exception("model_validation_report_failed")
        raise HTTPException(status_code=500, detail="Validation report failed")

@app.post("/model/trajectory-v2/train")
def train_trajectory_v2_endpoint(
    req: TrajectoryTrainRequest,
    current_user: CurrentUser = Depends(require_admin),
):
    try:
        report = train_trajectory_v2(current_user.uid, activate=req.activate)
        log_product_event(
            "trajectory_v2_model_trained",
            current_user,
            {
                "version": report.get("version"),
                "row_count": report.get("row_count"),
                "activate": req.activate,
            },
        )
        return report
    except Exception:
        logger.exception("trajectory_v2_training_failed")
        raise HTTPException(status_code=500, detail="Trajectory v2 training failed")

@app.get("/model/trajectory-v2/evaluate")
def evaluate_trajectory_v2_endpoint(
    current_user: CurrentUser = Depends(require_admin),
):
    try:
        report = evaluate_trajectory_v2(current_user.uid)
        log_product_event(
            "trajectory_v2_model_evaluated",
            current_user,
            {
                "version": report.get("version"),
                "row_count": report.get("row_count"),
            },
        )
        return report
    except Exception:
        logger.exception("trajectory_v2_evaluation_failed")
        raise HTTPException(status_code=500, detail="Trajectory v2 evaluation failed")


if __name__ == "__main__":
    uvicorn.run("app:app", host="127.0.0.1", port=8000, reload=True)
