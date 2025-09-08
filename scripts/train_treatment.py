import json, joblib, pandas as pd, numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler, LabelEncoder
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import Dense, Dropout
from tensorflow.keras.utils import to_categorical
from pathlib import Path

ART = Path("artifacts"); ART.mkdir(exist_ok=True, parents=True)

# 1) LOAD DATA (swap in STAR*D later)
# columns example: age, severity_1to9, sleep_issues, anxiety, treatment_label
df = pd.read_csv("data/raw/treatment_demo.csv")

X = df[["age","severity_1to9","sleep_issues","anxiety"]].values.astype(float)
y_raw = df["treatment_label"].astype(str)

scaler = StandardScaler()
X = scaler.fit_transform(X)

le = LabelEncoder()
y = le.fit_transform(y_raw)
y_cat = to_categorical(y)

Xtr, Xte, ytr, yte = train_test_split(X, y_cat, test_size=0.2, random_state=42, stratify=y_cat)

model = Sequential([
    Dense(64, activation='relu', input_shape=(X.shape[1],)),
    Dropout(0.2),
    Dense(32, activation='relu'),
    Dense(y_cat.shape[1], activation='softmax')
])
model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
model.fit(Xtr, ytr, epochs=15, batch_size=32, validation_data=(Xte, yte))

model.save(ART / "treatment_model.h5")
joblib.dump(scaler, ART / "scaler.joblib")
with open(ART / "treatment_classes.json", "w") as f:
    json.dump(le.classes_.tolist(), f)