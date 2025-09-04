import json, joblib, pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import LabelEncoder
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Dense, Dropout
from tensorflow.keras.utils import to_categorical
from pathlib import Path

ART = Path("artifacts"); ART.mkdir(exist_ok=True, parents=True)

# 1) LOAD YOUR DATA (replace with CLPsych/DAIC-WOZ once ready)
df = pd.read_csv("data/raw/mood_demo.csv")  # columns: text, label (0..3)
X_text = df["text"].astype(str)
y = df["label"].astype(int)

# 2) VECTORIZER + LABELS
vectorizer = TfidfVectorizer(max_features=5000, ngram_range=(1,2))
X = vectorizer.fit_transform(X_text)
le = LabelEncoder()
y_enc = le.fit_transform(y)
y_cat = to_categorical(y_enc)

Xtr, Xte, ytr, yte = train_test_split(X, y_cat, test_size=0.2, random_state=42, stratify=y_cat)

# 3) MODEL
model = Sequential([
    Dense(256, activation='relu', input_shape=(X.shape[1],)),
    Dropout(0.3),
    Dense(128, activation='relu'),
    Dropout(0.2),
    Dense(y_cat.shape[1], activation='softmax')
])
model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
model.fit(Xtr.toarray(), ytr, epochs=8, batch_size=32, validation_data=(Xte.toarray(), yte))

# 4) SAVE ARTIFACTS
model.save(ART / "mood_model.h5")
joblib.dump(vectorizer, ART / "vectorizer.joblib")
with open(ART / "severity_classes.json", "w") as f:
    json.dump(le.classes_.tolist(), f)