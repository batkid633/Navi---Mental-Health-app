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

import praw
import pandas as pd
from dotenv import load_dotenv

load_dotenv()
praw_id = os.getenv("PRAW_ID")
praw_secret = os.getenv("PRAW_secret")

reddit = praw.Reddit(
    client_id=str(praw_id),
    client_secret=str(praw_secret),
    user_agent="depression text classifier using Reddit posts by u/Slow-Bit-155"
)

# Define subreddits to use
depressed_subs = ["depression", "offmychest", "mentalhealth"]
control_subs = ["happy", "CasualConversation", "GetMotivated"]

def fetch_posts(subs, label, limit=300):
    data = []
    for sub in subs:
        for post in reddit.subreddit(sub).hot(limit=limit):
            data.append({"text": post.title + " " + post.selftext, "label": label})
    return pd.DataFrame(data)

df_depressed = fetch_posts(depressed_subs, 1)
df_control = fetch_posts(control_subs, 0)

reddit_df = pd.concat([df_depressed, df_control], ignore_index=True)
reddit_df = reddit_df.dropna().sample(frac=1).reset_index(drop=True)
reddit_df.to_csv("data/reddit_text.csv", index=False)
print("✅ Saved Reddit data with shape:", reddit_df.shape)

daic_path = "data/DAIC_WOZ/transcripts/"
texts, labels = [], []

for file in os.listdir(daic_path):
    if file.endswith(".txt"):
        with open(os.path.join(daic_path, file), "r", encoding="utf-8") as f:
            texts.append(f.read())
            # Example: label based on PHQ-8 score in metadata CSV
            # Let's assume you have daic_labels.csv with participant_id and depression label
daic_labels = pd.read_csv("data/DAIC_WOZ/labels.csv")
daic_df = pd.DataFrame({"text": texts, "label": daic_labels["depression"]})

# Combine Reddit + DAIC
text_df = pd.concat([reddit_df, daic_df], ignore_index=True)
X_text = text_df["text"]
y_text = text_df["label"]

vectorizer = TfidfVectorizer(max_features=5000,
    stop_words="english",
    ngram_range=(1,2)
)
X_vec = vectorizer.fit_transform(X_text)

text_model = LogisticRegression(max_iter=1000)
text_model.fit(X_vec, labels)

text_probs = text_model.predict_proba(X_vec)[:, 1]

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

print("All models saved to /models/")
