import streamlit as st, pandas as pd, numpy as np
from datetime import datetime
import os
import joblib
import pickle

#------------------ Load trained model --------------
CLASSIFIER_PATH = "models/mood_classifier.pkl"
VECTORIZER_PATH = "models/mood_vectorizer.pkl"

if os.path.exists(CLASSIFIER_PATH) and os.path.exists(VECTORIZER_PATH):
    with open(CLASSIFIER_PATH, "rb") as f:
        classifier = pickle.load(f)
    with open(VECTORIZER_PATH, "rb") as f:
        vectorizer = pickle.load(f)
else:
    st.error("No trained models found. Please run train_mood.py first.")
    st.stop()

#----- Set up local storage for journal entries ----
LOG_FILE = "data/journal_log.csv"
os.makedirs("data", exist_ok=True)

if os.path.exists(LOG_FILE):
    journal_df = pd.read_csv(LOG_FILE)
else:
    journal_df = pd.DataFrame(columns=["timestamp","entry","predicted_label","depression_probability"])

#---------------- Sreamlit UI -----------------
st.header("Mood Journal")
st.write("Log your daily jounral entry and track mood predictions over time")

entry = st.text_area("Write your journal entry here:",height=150)
if st.button("Analyze mood"):
    if entry.strip():
        #Vectorize and predict
        X = vectorizer.transform([entry])
        # Get probability for "depressed" (class 1)
        probs = classifier.predict_proba(X)[0][1]
        # Apply custom threshold
        threshold = 0.855 # based on train_mood graph in data/processed
        label = 1 if probs >= threshold else 0
        if label == 0:
            label_str = "this text does not suggest depression"
        else:
            label_str = "this text suggests depression"
        label_proba = classifier.predict_proba(X)[0]

        #save entry
        new_row={
            "timestamp":datetime.now().strftime("%Y-%m-%d %H:%M"),
            "entry": entry,
            "predicted_label": label,
            "depression_probability" : probs
        }
        journal_df = pd.concat([journal_df, pd.DataFrame([new_row])],ignore_index=True)
        journal_df.to_csv(LOG_FILE,index=False)

        #display result
        st.subheader("Mood Prediction")
        st.write(f"Predicted mood: *{label_str}")
        st.write("Confidence:")
        for i, prob in enumerate(label_proba):
            st.write(f"- Class {i}: {prob:.2f}")
    else:
        st.warning("Please type something before analyzing.")

# ------------- Show Past entries -------------------
st.subheader("Mood history")
if len(journal_df) > 0:
    st.dataframe(journal_df[["timestamp","entry","predicted_label","depression_probability"]])
    st.line_chart(journal_df.set_index("timestamp")["depression_probability"].astype("category").cat.codes)

# ----------------- Treatment Panel -----------------
st.header("💊 Treatment Matching")
col1,col2 = st.columns(2)
with col1:
    age = st.slider("Age", 18, 80, 35)
    severity_1to9 = st.slider("Baseline severity (1–9)", 1, 9, 5)
with col2:
    sleep_issues = st.selectbox("Sleep Issues", [0,1], index=0)
    anxiety = st.selectbox("Anxiety Comorbidity", [0,1], index=0)

if st.button("Suggest Treatment"):
    probs, labels = predict_treatment([[age, severity_1to9, sleep_issues, anxiety]], trt_model, scaler, trt_classes)
    p = probs[0]
    result = pd.Series({trt_classes[i]: float(p[i]) for i in range(len(trt_classes))}).sort_values(ascending=False)
    st.success(f"Top recommendation: **{labels[0]}**")
    st.bar_chart(result)
