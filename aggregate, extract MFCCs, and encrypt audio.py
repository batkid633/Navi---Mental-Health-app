import os
import numpy as np
import pandas as pd
import librosa
from cryptography.fernet import Fernet
from dotenv import load_dotenv

# ---------- 1. Setup ----------
load_dotenv()
encryption_key = os.getenv("encryption_KEY")  # 44-character Fernet key base64-encoded
if not encryption_key:
    # You can generate one if needed:
    from cryptography.fernet import Fernet
    encryption_key = Fernet.generate_key().decode()
    print("No key found — generated new key. Save this securely in .env as encryption_KEY=")
    print(encryption_key)

fernet = Fernet(encryption_key.encode())

daic_audio_path = "data/DAIC_WOZ/Audio/"
labels_path = "data/DAIC_WOZ/labels.csv"
output_path = "data/daic_audio_features_encrypted.bin"

# ---------- 2. Load participant labels ----------
labels_df = pd.read_csv(labels_path)  # expects participant_id, depression

# ---------- 3. Feature extraction function ----------
def extract_mfcc_features(audio_path, n_mfcc=13, sr=16000):
    try:
        y, sr = librosa.load(audio_path, sr=sr)
        mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=n_mfcc)
        return np.mean(mfccs, axis=1)
    except Exception as e:
        print(f"Error reading {audio_path}: {e}")
        return np.zeros(n_mfcc)

# ---------- 4. Aggregate per participant ----------
audio_data = []

for _, row in labels_df.iterrows():
    pid = str(row["participant_id"])
    label = row["depression"]

    participant_files = [
        f for f in os.listdir(daic_audio_path)
        if pid in f and f.endswith(".wav")
    ]
    if not participant_files:
        continue

    mfccs_all = []
    for f in participant_files:
        mfcc_feat = extract_mfcc_features(os.path.join(daic_audio_path, f))
        mfccs_all.append(mfcc_feat)

    # Average across sessions
    participant_vector = np.mean(mfccs_all, axis=0)
    entry = {"participant_id": pid, "label": label}
    for i, val in enumerate(participant_vector):
        entry[f"mfcc_{i+1}"] = val
    audio_data.append(entry)

audio_df = pd.DataFrame(audio_data)
print(f"Extracted MFCCs for {len(audio_df)} participants")

# ---------- 5. Encrypt and save ----------
csv_bytes = audio_df.to_csv(index=False).encode()
encrypted_bytes = fernet.encrypt(csv_bytes)

with open(output_path, "wb") as f:
    f.write(encrypted_bytes)

print(f"Encrypted MFCC features saved to {output_path}")
