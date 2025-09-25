import numpy as np
import pandas as pd
import librosa
import pickle

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.metrics import classification_report

# ---------------------------
# 1. TEXT MODEL
# ---------------------------
print("Training text model...")

text_data = [
    "I feel hopeless and tired",
    "I had a wonderful day with friends",
    "Nothing makes sense anymore",
    "I'm excited about my new job",
]
labels = [1, 0, 1, 0]  # 1 = depressed, 0 = not depressed

vectorizer = TfidfVectorizer(max_features=500)
X_text = vectorizer.fit_transform(text_data)

text_model = LogisticRegression(max_iter=1000)
text_model.fit(X_text, labels)

text_probs = text_model.predict_proba(X_text)[:, 1]

# ---------------------------
# 2. AUDIO MODEL
# ---------------------------
print("Training audio model...")

# Example: simulate audio features (replace with librosa MFCCs for real data)
# For demo, we'll just use random features
X_audio = np.random.rand(len(labels), 13)  # 13 MFCCs typically - REPLACE WITH CODE ON 3 LINES BELOW
# y, sr = librosa.load("path_to_audio.wav", sr=16000)
# mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
# mfccs_mean = np.mean(mfccs, axis=1)
y_audio = labels

audio_model = RandomForestClassifier()
audio_model.fit(X_audio, y_audio)

audio_probs = audio_model.predict_proba(X_audio)[:, 1]

# ---------------------------
# 3. PHYSIO MODEL
# ---------------------------
print("Training physio model...")

# Simulated data: [heart_rate, sleep_hours, exercise_minutes]
X_physio = np.array([
    [85, 5, 0],   # likely depressed
    [70, 8, 45],  # likely healthy
    [95, 4, 10],  # likely depressed
    [65, 7, 60],  # likely healthy
])
y_physio = labels

physio_model = GradientBoostingClassifier()
physio_model.fit(X_physio, y_physio)

physio_probs = physio_model.predict_proba(X_physio)[:, 1]

# ---------------------------
# 4. LATE-FUSION MODEL
# ---------------------------
print("Training fusion model...")

# Stack all unimodal probability outputs
X_fusion = np.vstack([text_probs, audio_probs, physio_probs]).T
y_fusion = labels

fusion_model = LogisticRegression()
fusion_model.fit(X_fusion, y_fusion)

fusion_probs = fusion_model.predict_proba(X_fusion)[:, 1]
y_pred = (fusion_probs >= 0.5).astype(int)

print("\nFusion Model Report:")
print(classification_report(y_fusion, y_pred))

# ---------------------------
# 5. SAVE MODELS
# ---------------------------
print("Saving models...")

with open("models/text_vectorizer.pkl", "wb") as f:
    pickle.dump(vectorizer, f)

with open("models/text_model.pkl", "wb") as f:
    pickle.dump(text_model, f)

with open("models/audio_model.pkl", "wb") as f:
    pickle.dump(audio_model, f)

with open("models/physio_model.pkl", "wb") as f:
    pickle.dump(physio_model, f)

with open("models/fusion_model.pkl", "wb") as f:
    pickle.dump(fusion_model, f)

print("✅ All models saved to /models/")
