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

treatment_model_PATH = "models/treatment_model.pkl"

if os.path.exists(treatment_model_PATH):
    treatment_model = joblib.load("models/treatment_model.pkl")
else:
    st.error("No trained models found. Please run train_treatment.py first.")
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
threshold = 0.855
journal_df["threshold"] = threshold
if len(journal_df) > 0:
    st.dataframe(journal_df[["timestamp","entry","predicted_label","depression_probability"]])
    st.line_chart(journal_df.set_index("timestamp")[["depression_probability","threshold"]])

# ----------------- Treatment Panel -----------------

st.header("💊 Treatment Matching")
st.subheader("Patient Information")

age = st.slider("Age", 18, 80, 30)
anxiety_score = st.slider("Anxiety Score", 0, 10, 5)
sleep_hours = st.slider("Sleep Hours", 0, 12, 7)
exercise_hours = st.slider("Weekly Fitness Hours", 0, 15, 3)

if st.button("Predict Treatment Plan"):
    # Package inputs
    X_input = pd.DataFrame([{
        "depression_score": probs,
        "age": age,
        "anxiety_score": anxiety_score,
        "sleep_hours": sleep_hours,
        "exercise_hours": exercise_hours
    }])
    
    treatment_pred = treatment_model.predict(X_input)[0]
    st.success(f"Recommended treatment plan: **{treatment_pred}**")

# ---------- Incoming Features ------------
st.markdown("---")
st.subheader("Upcoming Features")
st.markdown("---")
st.markdown(
    """
    **Typing/Keyboard Tracker**  
    ⌨️ Analysis of typing speed, error rate, and rhythm to detect mood shifts  
    
    **Wearable Fitness Tracker Data**  
    ⌚ Integration with Apple Health, Fitbit, Garmin, etc. to monitor sleep, HRV, and activity.  
    
    **Audio Environment Tracker**  
    🎤 Analyze background noise, speech tone, and vocal energy for early depression/anxiety insights.  
    """)
