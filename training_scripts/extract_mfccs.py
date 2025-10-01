# scripts/extract_mfccs.py
import librosa
import numpy as np
import os
import pandas as pd

SRC = "data/audio_samples"   # folder with .wav files
OUT_CSV = "data/audio_features.csv"
sr = 16000
n_mfcc = 13

rows = []
for fname in os.listdir(SRC):
    if not fname.lower().endswith(".wav"):
        continue
    path = os.path.join(SRC, fname)
    y, _ = librosa.load(path, sr=sr, mono=True)
    mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=n_mfcc)
    mfcc_mean = mfccs.mean(axis=1)
    row = {"filename": fname}
    for i, v in enumerate(mfcc_mean):
        row[f"mfcc_{i}"] = float(v)
    rows.append(row)

df = pd.DataFrame(rows)
df.to_csv(OUT_CSV, index=False)
print("Saved", OUT_CSV)
