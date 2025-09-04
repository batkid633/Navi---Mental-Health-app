from pathlib import Path
import json, joblib
from tensorflow.keras.models import load_model

ART = Path("artifacts")

def load_mood_artifacts():
    model = load_model(ART / "mood_model.h5")
    vectorizer = joblib.load(ART / "vectorizer.joblib")
    classes = json.load(open(ART / "severity_classes.json"))
    return model, vectorizer, classes

def load_treatment_artifacts():
    model = load_model(ART / "treatment_model.h5")
    scaler = joblib.load(ART / "scaler.joblib")
    classes = json.load(open(ART / "treatment_classes.json"))
    return model, scaler, classes