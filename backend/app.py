import uvicorn
from fastapi import BackgroundTasks, Depends, FastAPI, Request, UploadFile, File, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from pathlib import Path
import csv
import tempfile
import os
import sys
from datetime import datetime
import json
import traceback
from dotenv import find_dotenv, load_dotenv
import pandas as pd

load_dotenv(find_dotenv(), override=False)

BACKEND_DIR = Path(__file__).resolve().parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

try:
    from auth import CurrentUser, get_current_user
    from sentiment.vader import analyze_sentiment
    from ml.predict_mood import predict_next_day
    from ml.feature_loader import load_features_for_date
    from ml.llm_insights import generate_insight, get_llm_insight, save_cached_insight
    from ml.insight_trends import load_insight_trends
    from ml.audio_mood import predict_audio_mood, analyze_audio_comprehensive, train_audio_mood_model, generate_emotional_intervention, analyze_mfcc_deep
    from ml.train_next_day_mood import train_next_day_model
    import whoop_api
    from user_data import user_daily_features_path, user_dataset_path, user_logs_dir
except ModuleNotFoundError:
    from .auth import CurrentUser, get_current_user
    from .sentiment.vader import analyze_sentiment
    from .ml.predict_mood import predict_next_day
    from .ml.feature_loader import load_features_for_date
    from .ml.llm_insights import generate_insight, get_llm_insight, save_cached_insight
    from .ml.insight_trends import load_insight_trends
    from .ml.audio_mood import predict_audio_mood, analyze_audio_comprehensive, train_audio_mood_model, generate_emotional_intervention, analyze_mfcc_deep
    from .ml.train_next_day_mood import train_next_day_model
    from . import whoop_api
    from .user_data import user_daily_features_path, user_dataset_path, user_logs_dir


app = FastAPI()

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
    text: str

@app.post("/sentiment")
def sentiment_endpoint(req: JournalRequest, current_user: CurrentUser = Depends(get_current_user)):
    try:
        return analyze_sentiment(req.text)
    except Exception as e:
        return {
            "sentiment": 0.0,
            "error": str(e)
        }
class PredictRequest(BaseModel):
    date: str
    force_reload: bool = False

class AudioTrainRequest(BaseModel):
    training_csv_path: str

class DailyFeatureRecord(BaseModel):
    date: str
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

class DailyFeaturesRequest(BaseModel):
    records: list[DailyFeatureRecord]

@app.post("/predict/tomorrow")
def predict_tomorrow(req: PredictRequest, current_user: CurrentUser = Depends(get_current_user)):
    
    features = load_features_for_date(req.date, current_user.uid)
    
    try:
        result = predict_next_day(features)
    except Exception:
        result = {
            "predicted_delta": 0.0,
            "confidence": 0.0,
            "model_version": "v1"
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
    if req.force_reload == True:
        insight = generate_insight({
            **features,
            "predicted_delta": result["predicted_delta"],
            "confidence": result["confidence"],
        })
        # Force reload bypasses the cache but still writes into the user-scoped
        # cache for future non-forced requests.
        save_cached_insight(req.date, insight, current_user.uid)
    else:
        insight = get_llm_insight(req.date, {
            **features,
            "predicted_delta": result["predicted_delta"],
            "confidence": result["confidence"],
        }, current_user.uid)

    event["insight"] = insight

    log_prediction_event(event)

    return {
        **result,
        "insight": event["insight"],
    }

@app.post("/ml/daily-features")
def save_daily_features(
    req: DailyFeaturesRequest,
    current_user: CurrentUser = Depends(get_current_user),
):
    rows = [record.dict() for record in req.records]
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

    return {
        "saved": len(df),
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
    try:
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
            content = await file.read()
            temp_file.write(content)
            temp_path = temp_file.name

        try:
            if mode == "emotional_venting":
                # Exploratory ML model for emotional venting
                mood_result = predict_audio_mood(temp_path)
                audio_analysis = analyze_audio_comprehensive(temp_path)
                
                # Add intervention suggestions based on mood
                intervention = generate_emotional_intervention(mood_result)
                
                return {
                    "filename": file.filename,
                    "mode": mode,
                    "mood_analysis": mood_result,
                    "audio_features": audio_analysis,
                    "intervention": intervention
                }
            elif mode == "deeper_analysis":
                # Deep MFCC analysis for structured assessment
                mood_result = predict_audio_mood(temp_path)
                audio_analysis = analyze_audio_comprehensive(temp_path)
                mfcc_analysis = analyze_mfcc_deep(temp_path)
                
                return {
                    "filename": file.filename,
                    "mode": mode,
                    "mood_analysis": mood_result,
                    "audio_features": audio_analysis,
                    "mfcc_analysis": mfcc_analysis
                }
            else:
                return {"error": f"Unknown analysis mode: {mode}"}
                
        finally:
            # Clean up temp file
            os.unlink(temp_path)

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Audio analysis failed: {str(e)}")

@app.post("/audio/train")
def train_audio_model(
    req: AudioTrainRequest,
    current_user: CurrentUser = Depends(get_current_user),
):
    """Train the audio mood classification model"""
    try:
        success = train_audio_mood_model(req.training_csv_path)
        if success:
            return {"message": "Audio mood model trained successfully"}
        else:
            raise HTTPException(status_code=400, detail="Training failed - check training data")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Training failed: {str(e)}")

@app.get("/")
def root():
    return {"message": "Navi Backend Running"}

@app.get("/health")
def health_check():
    return {"status": "healthy"}

@app.get("/ready")
def readiness_check():
    return {"status": "ready"}

@app.get("/whoop/connect")
def whoop_connect(
    request: Request,
    current_user: CurrentUser = Depends(get_current_user),
):
    try:
        redirect_base = str(request.base_url).rstrip('/')
        redirect_uri = whoop_api.REDIRECT_URI or f"{redirect_base}/whoop/callback"
        auth_url = whoop_api.generate_whoop_auth_url(redirect_uri)
        return {
            "auth_url": auth_url,
            "redirect_uri": redirect_uri,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/whoop/status")
def whoop_status(current_user: CurrentUser = Depends(get_current_user)):
    try:
        return whoop_api.get_whoop_status()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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

@app.get("/whoop/callback")
def whoop_callback(request: Request, code: str | None = None, state: str | None = None):
    if not code or not state:
        raise HTTPException(status_code=400, detail="Missing code or state")

    redirect_base = str(request.base_url).rstrip('/')
    redirect_uri = whoop_api.REDIRECT_URI or f"{redirect_base}/whoop/callback"

    try:
        whoop_api.handle_whoop_callback(code, state, redirect_uri)
        return HTMLResponse(
            '<html><body><h1>WHOOP connected successfully.</h1><p>You can close this tab and return to the app.</p></body></html>'
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

@app.post("/whoop/retrain")
def whoop_retrain(
    background_tasks: BackgroundTasks,
    current_user: CurrentUser = Depends(get_current_user),
):
    try:
        background_tasks.add_task(train_next_day_model, True)
        return {"message": "Retraining started"}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

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
    except Exception as e:
        return {"error": str(e)}


if __name__ == "__main__":
    uvicorn.run("app:app", host="127.0.0.1", port=8000, reload=True)
