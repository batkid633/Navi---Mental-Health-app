import numpy as np
import pandas as pd
import librosa
import pickle

from cryptography.fernet import Fernet

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.metrics import classification_report

# 1. TEXT MODEL
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

# Fetch Reddit posts
def fetch_posts(subs, label, limit=300):
    data = []
    for sub in subs:
        for post in reddit.subreddit(sub).hot(limit=limit):
            data.append({
                "text": f"{post.title} {post.selftext}",
                "label": label
            })
    return pd.DataFrame(data)

df_depressed = fetch_posts(depressed_subs, 1)
df_control = fetch_posts(control_subs, 0)

reddit_df = pd.concat([df_depressed, df_control], ignore_index=True)
reddit_df = reddit_df.dropna().sample(frac=1).reset_index(drop=True)
reddit_df.to_csv("data/reddit_text.csv", index=False)
print("Saved Reddit data with shape:", reddit_df.shape)

# Decrypt and load DAIC data
load_dotenv()

encryption_key = os.getenv("encryption_KEY") 
fernet = Fernet(encryption_key)

encrypted_path = "data/cleaned_daic_data_encrypted.csv"
with open(encrypted_path, "rb") as file:
    encrypted_file = file.read()

# Decrypt file contents
decrypted_bytes = fernet.decrypt(encrypted_file)
decoded_str = decrypted_bytes.decode("utf-8")

# Convert decrypted CSV text back into DataFrame
from io import StringIO
daic_df = pd.read_csv(StringIO(decoded_str))
print("Loaded DAIC data with shape:", daic_df.shape)

# Match with labels
# If you have a separate labels file for participants (e.g., depression severity) make sure participant_id is consistent between datasets
try:
    labels_path = "data/DAIC_WOZ/labels.csv"
    daic_labels = pd.read_csv(labels_path)
    if "participant_id" in daic_df.columns:
        daic_df = daic_df.merge(
            daic_labels[["participant_id", "depression"]],
            on="participant_id",
            how="left"
        )
        daic_df = daic_df.rename(columns={"depression": "label"})
except FileNotFoundError:
    print("Warning: labels.csv not found — using existing labels if present")

# Combine Reddit + DAIC
text_df = pd.concat([reddit_df, daic_df], ignore_index=True)
text_df = text_df.dropna(subset=["text", "label"])
print("Combined text dataset shape:", text_df.shape)

X_text = text_df["text"]
y_text = text_df["label"]

# Train vectorizer and model
vectorizer = TfidfVectorizer(
    max_features=5000,
    stop_words="english",
    ngram_range=(1, 2)
)
X_vec = vectorizer.fit_transform(X_text)

text_model = LogisticRegression(max_iter=1000)
text_model.fit(X_vec, y_text)

text_probs = text_model.predict_proba(X_vec)[:, 1]
print("Text model trained successfully.")

# 2. AUDIO MODEL

# Load and decrypt
load_dotenv()
encryption_key = os.getenv("encryption_KEY")
fernet = Fernet(encryption_key.encode())

with open("data/daic_audio_features_encrypted.bin", "rb") as f:
    encrypted_data = f.read()

decrypted_csv = fernet.decrypt(encrypted_data).decode()
audio_df = pd.read_csv(pd.io.common.StringIO(decrypted_csv))

print("Decrypted MFCC features:", audio_df.shape)

# Prepare data
X_audio = audio_df.filter(regex="mfcc_").values
y_audio = audio_df["label"].values

# Train model
audio_model = RandomForestClassifier(n_estimators=100, random_state=42)
audio_model.fit(X_audio, y_audio)

audio_probs = audio_model.predict_proba(X_audio)[:, 1]
print("Audio model trained on decrypted MFCCs")

# 3. PHYSIO MODEL
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

# 4. LATE-FUSION MODEL
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

# 5. SAVE MODELS
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
