import streamlit as st
import pandas as pd
import numpy as np
from datetime import datetime
import os
import requests
from dotenv import load_dotenv

# Local log storage
LOG_FILE = "data/journal_log.csv"
os.makedirs("data", exist_ok=True)

if os.path.exists(LOG_FILE):
    journal_df = pd.read_csv(LOG_FILE)
else:
    journal_df = pd.DataFrame(columns=[
        "timestamp", "entry",
        "text_score", "audio_score", "physio_score", "final_score"
    ])

# Streamlit UI
st.header("Mood Journal")
st.write("Log your daily journal entry and track mood predictions over time")

# Journal entry
entry = st.text_area("Write your journal entry here:", height=150)

# Physiological data inputs
st.subheader("Physiological Data (Demo)")
age = st.slider("Age", 18, 80, 30)
sleep_hours = st.slider("Sleep Hours", 0, 12, 7)
avg_heart_rate = st.slider("Average Resting Heart Rate (bpm)", 40, 120, 80)
steps = st.slider("Steps (per day)", 0, 20000, 5000)
anxiety_score = st.slider("Anxiety Score", 0, 10, 5)

# Submit button
if st.button("Analyze Mood"):
    if entry.strip():
        # Load API key / URL
        load_dotenv()
        API_URL = os.getenv("API_KEY")

        payload = {
            "journal_entry": entry,
            "age": age,
            "sleep_hours": sleep_hours,
            "avg_heart_rate": avg_heart_rate,
            "steps": steps,
            "anxiety_score": anxiety_score
        }

        response = requests.post(API_URL, json=payload)

        if response.status_code == 200:
            result = response.json()

            # Display scores
            st.subheader("Model Scores")
            st.write(f"**Text Score:** {result['text_score']:.2f}")
            st.write(f"**Physio Score:** {result['physio_score']:.2f}")
            st.write(f"**Audio Score:** {result['audio_score']:.2f}")
            st.write(f"**Final Depression Score:** {result['final_score']:.2f}")

            # Interpretation
            if result["final_score"] > 0.5:
                st.error("Elevated depression risk predicted")
            else:
                st.success("Low depression risk predicted")

            # Save log entry
            new_row = {
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M"),
                "entry": entry,
                "text_score": result["text_score"],
                "audio_score": result["audio_score"],
                "physio_score": result["physio_score"],
                "final_score": result["final_score"],
            }
            journal_df = pd.concat([journal_df, pd.DataFrame([new_row])], ignore_index=True)
            journal_df.to_csv(LOG_FILE, index=False)

        else:
            st.error(f"API error: {response.status_code}")
    else:
        st.warning("Please type something before analyzing.")

# Show Past entries
st.subheader("Mood History")
if len(journal_df) > 0:
    st.dataframe(journal_df[["timestamp", "entry", "final_score"]])
    st.line_chart(journal_df.set_index("timestamp")[["final_score"]])

# Treatment Panel

st.header("Treatment Matching")
st.subheader("Patient Information")

probs = st.session_state.get("probability", 0.0)
age = st.slider("Age", 18, 80, 30)
anxiety_score = st.slider("Anxiety Score", 0, 10, 5)
sleep_hours = st.slider("Sleep Hours", 0, 12, 7)
exercise_hours = st.slider("Weekly Fitness Hours", 0, 15, 3)

if st.button("Predict Treatment Plan"):
    # Package inputs
    X_input = pd.DataFrame([{
        "depression_score": probs,
        "anxiety_score": anxiety_score,
        "sleep_hours": sleep_hours,
        "exercise_hours": exercise_hours,
        "age": age,
    }])
    
    treatment_pred = treatment_model.predict(X_input)[0]
    st.success(f"Recommended treatment plan: **{treatment_pred}**")

# Incoming Features
st.markdown("---")
st.subheader("Upcoming Features")
st.markdown("---")
st.markdown(
    """
    **Typing/Keyboard Tracker**  
    Analysis of typing speed, error rate, and rhythm to detect mood shifts  
    
    **Wearable Fitness Tracker Data**  
    Integration with Apple Health, Fitbit, Garmin, etc. to monitor sleep, HRV, and activity.  
    
    **Audio Environment Tracker**  
    Analyze background noise, speech tone, and vocal energy for early depression/anxiety insights.  

    **LLM Therapy Chat Bot**
    Therapy chat bot that would serve as a stand-in for a therapist and help orchestrate therapy appointments
    """)
