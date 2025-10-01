# training/test_pipeline.py

import pickle
import numpy as np

# --------------------------
# 1. Load Saved Models
# --------------------------
def load_model(path):
    with open(path, "rb") as f:
        return pickle.load(f)

print("Loading models...")
vectorizer = load_model("models/text_vectorizer.pkl")
text_model = load_model("models/text_model.pkl")
audio_model = load_model("models/audio_model.pkl")
physio_model = load_model("models/physio_model.pkl")
fusion_model = load_model("models/fusion_model.pkl")

# --------------------------
# 2. Fake Input Data
# --------------------------
# Example journal entry
sample_text = "I feel very tired and unmotivated today."

# Example audio (13 MFCCs) – for now, just random numbers
sample_audio = np.random.rand(13).reshape(1, -1)

# Example physio [heart_rate, sleep_hours, exercise_minutes]
sample_physio = np.array([[90, 5, 0]])

# --------------------------
# 3. Get Predictions
# --------------------------
# Text → TF-IDF → prob
X_text = vectorizer.transform([sample_text])
text_prob = text_model.predict_proba(X_text)[:, 1][0]

# Audio → prob
audio_prob = audio_model.predict_proba(sample_audio)[:, 1][0]

# Physio → prob
physio_prob = physio_model.predict_proba(sample_physio)[:, 1][0]

# --------------------------
# 4. Late Fusion
# --------------------------
X_fusion = np.array([[text_prob, audio_prob, physio_prob]])
final_prob = fusion_model.predict_proba(X_fusion)[:, 1][0]

# --------------------------
# 5. Output
# --------------------------
print("\n--- Test Pipeline Results ---")
print(f"Text Score:     {text_prob:.3f}")
print(f"Audio Score:    {audio_prob:.3f}")
print(f"Physio Score:   {physio_prob:.3f}")
print(f"Final Fused:    {final_prob:.3f}")
