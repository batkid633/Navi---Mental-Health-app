# backend.py
from fastapi import FastAPI
from pydantic import BaseModel
import random
import joblib

app = FastAPI()

# Define what data the API will expect
class TextPhysioInput(BaseModel):
    journal_entry: str
    age: int
    sleep_hours: float
    avg_heart_rate: int
    steps: int
    anxiety_score: int  # slider 1–10

@app.get("/")
def root():
    return {"message": "Backend API is running!"}

@app.post("/predict_text_physio")
def predict_text_physio(data: TextPhysioInput):
    # For MVP demo, generate a dummy score
    # Later → plug in trained model
    
    dummy_score = round(random.uniform(0, 1), 3)

    return {
        "depression_probability": dummy_score,
        "interpretation": "Depressed" if dummy_score > 0.5 else "Not Depressed"
    }

@app.post("/upload_aduio")
def upload_audio(data: audio_files)

