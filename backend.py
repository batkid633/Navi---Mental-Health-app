# # filename: main.py
from fastapi import FastAPI, File, UploadFile, Form
from pydantic import BaseModel
import pickle
import numpy as np
import uvicorn

app = FastAPI()

# Load models/vectorizers once
with open("text_vectorizer.pkl", "rb") as f:
    text_vectorizer = pickle.load(f)

with open("text_model.pkl", "rb") as f:
    text_model = pickle.load(f)

with open("audio_model.pkl", "rb") as f:
    audio_model = pickle.load(f)

with open("physio_model.pkl", "rb") as f:
    physio_model = pickle.load(f)
    
with open("fusion_model.pkl", "rb") as f:
    fusion_model = pickle.load(f)

@app.post("/predict/")
async def predict(
    journal_entry: str = Form(...),
    heart_rate: float = Form(...),
    sleep_hours: float = Form(...),
    audio_file: UploadFile = File(None)
):
    # 1. Text preprocessing
    text_features = text_vectorizer.transform([journal_entry])
    text_pred = text_model.predict_proba(text_features)[0][1]

    # 2. Physio features
    physio_features = np.array([[heart_rate, sleep_hours]])
    physio_pred = physio_model.predict_proba(physio_features)[0][1]

    # 3. Audio features (placeholder for now)
    audio_pred = 0.0
    if audio_file is not None:
        contents = await audio_file.read()
        # TODO: preprocess into MFCC or embeddings
        # audio_features = preprocess_audio(contents)
        # audio_pred = audio_model.predict_proba(audio_features)[0][1]
        audio_pred = 0.5  # dummy for now

    # 4. Late fusion
    
    X_fusion = np.vstack([text_probs, audio_probs, physio_probs]).T
    y_fusion = labels

    fusion_model = LogisticRegression()
    fusion_model.fit(X_fusion, y_fusion)
    
    fusion_probs = fusion_model.predict_proba(X_fusion)[:, 1]
    y_pred = (fusion_probs >= 0.5).astype(int)
    
    final_score = []
    final_score.append(y_fusion, y_pred)

    return {
        "text_score": float(text_pred),
        "physio_score": float(physio_pred),
        "audio_score": float(audio_pred),
        "final_score": float(final_score)
    }

if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)backend.py
