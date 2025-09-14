# train_mood.py

import pandas as pd
import numpy as np
import pickle
import matplotlib.pyplot as plt

from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report

import nltk
from nltk.sentiment import SentimentIntensityAnalyzer

# --- Step 1: Load data ---
print("Loading data...")
df = pd.read_csv("data/raw/rmhd_master.csv")  # update path if needed

# --- Step 2: Create proxy labels ---
depression_subs = ["depression", "SuicideWatch", "offmychest", "Anxiety", "bipolarreddit","alcoholism"]
df["label"] = df["subreddit"].apply(lambda x: 1 if x.lower() in depression_subs else 0)
print(df["label"].value_counts())

X_text = df["post"].astype(str)
y = df["label"].astype(int)

# --- Step 3: Train classifier ---
print("Training classifier...")
X_train, X_test, y_train, y_test = train_test_split(X_text, y, test_size=0.2, random_state=42)

vectorizer = TfidfVectorizer(max_features=10000)
X_train_vec = vectorizer.fit_transform(X_train)
X_test_vec = vectorizer.transform(X_test)

clf = LogisticRegression(class_weight="balanced",max_iter=1000)
clf.fit(X_train_vec, y_train)

# Evaluate
y_pred = clf.predict(X_test_vec)
print("\nClassification Report:")
print(classification_report(y_test, y_pred))

# Depression probability scores
probs = clf.predict_proba(X_test_vec)[:, 1]


##TEST SECTION
import matplotlib.pyplot as plt
from sklearn.metrics import roc_curve, roc_auc_score, precision_recall_curve, auc

# --- ROC Curve ---
fpr, tpr, roc_thresholds = roc_curve(y_test, probs)
roc_auc = roc_auc_score(y_test, probs)

plt.figure(figsize=(7, 5))
plt.plot(fpr, tpr, label=f"ROC curve (AUC = {roc_auc:.2f})")
plt.plot([0, 1], [0, 1], linestyle="--", color="gray")
plt.xlabel("False Positive Rate")
plt.ylabel("True Positive Rate (Recall)")
plt.title("ROC Curve")
plt.legend()
plt.show()

# --- Precision-Recall Curve ---
prec, rec, pr_thresholds = precision_recall_curve(y_test, probs)
pr_auc = auc(rec, prec)

plt.figure(figsize=(7, 5))
plt.plot(rec, prec, label=f"PR curve (AUC = {pr_auc:.2f})")
plt.xlabel("Recall")
plt.ylabel("Precision")
plt.title("Precision-Recall Curve")
plt.legend()
plt.show()

##END TEST SECTION

# --- Step 4: Sentiment analysis ---
print("Adding sentiment scores...")
nltk.download("vader_lexicon")
sia = SentimentIntensityAnalyzer()

sentiment_scores = X_test.apply(lambda x: sia.polarity_scores(x)["compound"])
sent_norm = (sentiment_scores - sentiment_scores.min()) / (sentiment_scores.max() - sentiment_scores.min())

# --- Step 5: Combine into mood score ---
mood_score = 0.5 * probs + 0.5 * (1 - sent_norm)

# --- Step 6: Save results + plot ---
df_results = pd.DataFrame({
    "text": X_test,
    "true_label": y_test,
    "depression_prob": probs,
    "sentiment": sentiment_scores,
    "mood_score": mood_score
})

df_results = df_results.reset_index(drop=True)
df_results["entry_number"] = df_results.index  # simulate timeline

# Plot mood score trajectory
plt.plot(df_results["entry_number"], df_results["mood_score"], marker="o")
plt.xlabel("Entry number")
plt.ylabel("Mood score (0=positive, 1=depressed)")
plt.title("Mood trajectory over time (Hybrid Score)")
plt.savefig("data/processed/mood_trajectory.png")
plt.show()

# --- Step 7: Save model + vectorizer for later use ---
print("Saving model and vectorizer...")
with open("models/mood_classifier.pkl", "wb") as f:
    pickle.dump(clf, f)

with open("models/mood_vectorizer.pkl", "wb") as f:
    pickle.dump(vectorizer, f)

print("✅ Training complete. Model, vectorizer, and plot saved.")
