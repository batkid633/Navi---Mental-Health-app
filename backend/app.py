from fastapi import FastAPI, UploadFile, File, HTTPException, Form
from pydantic import BaseModel
from sentiment.vader import analyze_sentiment
from ml.feature_builder import build_features
from ml.predict_mood import predict_next_day
from ml.feature_loader import load_features_for_date
from ml.llm_insights import generate_insight, get_llm_insight
from ml.insight_trends import load_insight_trends
from ml.audio_mood import predict_audio_mood, analyze_audio_comprehensive, train_audio_mood_model, generate_emotional_intervention, analyze_mfcc_deep
from pathlib import Path
import csv
import tempfile
import os
from datetime import datetime
import json
import traceback


app = FastAPI()

LOG_DIR = Path("./logs")
LOG_DIR.mkdir(parents=True, exist_ok=True)

PREDICTION_LOG = LOG_DIR / "prediction_log.csv"
INSIGHT_LOG = LOG_DIR / "insight_log.jsonl"

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
    csv_exists = PREDICTION_LOG.exists()

    with open(PREDICTION_LOG, "a", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "timestamp",
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
            "date": event["date"],
            "model_version": event["model_version"],
            "predicted_delta": event["predicted_delta"],
            "confidence": event["confidence"],
        })

    # ---- JSONL (full context) ----
    with open(INSIGHT_LOG, "w") as f:
        safe_event = make_json_safe(event)
        f.write(json.dumps(safe_event) + "\n")

class JournalRequest(BaseModel):
    text: str

@app.post("/sentiment")
def sentiment_endpoint(req: JournalRequest):
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

@app.post("/predict/tomorrow")
def predict_tomorrow(req: PredictRequest):
    
    features = load_features_for_date(req.date)
    
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
    else:
        insight = get_llm_insight(req.date, {
            **features,
            "predicted_delta": result["predicted_delta"],
            "confidence": result["confidence"],
        })

    event["insight"] = insight

    log_prediction_event(event)

    return {
        **result,
        "insight": event["insight"],
    }

from ml.insight_trends import load_insight_trends

# Audio Analysis Endpoints
@app.post("/audio/analyze")
async def analyze_audio(file: UploadFile = File(...), mode: str = Form("emotional_venting")):
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
def train_audio_model(training_csv_path: str):
    """Train the audio mood classification model"""
    try:
        success = train_audio_mood_model(training_csv_path)
        if success:
            return {"message": "Audio mood model trained successfully"}
        else:
            raise HTTPException(status_code=400, detail="Training failed - check training data")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Training failed: {str(e)}")

@app.get("/")
def root():
    return {"message": "Navi Backend Running"}

@app.get("/insights/trends")
def get_insight_trends(days: int = 14):
    try:
        data = load_insight_trends(days)
        return {
            "days": days,
            "data": data
        }
    except Exception as e:
        return {"error": str(e)}
