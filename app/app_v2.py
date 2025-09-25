import streamlit as st, pandas as pd, numpy as np
from datetime import datetime
import os
import joblib
import pickle
import requests
from dotenv import load_dotenv

#----- Set up local storage for journal entries ----
LOG_FILE = "data/journal_log.csv"
os.makedirs("data", exist_ok=True)

if os.path.exists(LOG_FILE):
    journal_df = pd.read_csv(LOG_FILE)
else:
    journal_df = pd.DataFrame(columns=["timestamp","entry","text_prediction","audio_prediction","physio_prediction","final_prediction"])

#---------------- Sreamlit UI ----------------- 
st.header("Mood Journal")
st.write("Log your daily jounral entry and track mood predictions over time")

entry = st.text_area("Write your journal entry here:",height=150)
if st.button("Analyze mood"):
    if entry.strip():

        #save entry
        new_row={
            "timestamp":datetime.now().strftime("%Y-%m-%d %H:%M"),
            "entry": entry,
            "text_prediction" : text_score
        }
        journal_df = pd.concat([journal_df, pd.DataFrame([new_row])],ignore_index=True)
        journal_df.to_csv(LOG_FILE,index=False)

  # Send data to FastAPI backend
        load_dotenv()
        API_KEY = os.getenv("API_KEY")

        payload = {
            "journal_entry": journal_entry,
            "age": age,
            "sleep_hours": sleep_hours,
            "avg_heart_rate": avg_heart_rate,
            "steps": steps,
            "anxiety_score": anxiety_score
        }
        response = requests.post(API_KEY, json=payload)

        if response.status_code == 200:
            result = response.json()
            st.subheader("Model Scores")
            st.write(f"**Text Score:** {result['text_score']:.2f}")
            st.write(f"**Physio Score:** {result['physio_score']:.2f}")
            st.write(f"**Audio Score:** {result['audio_score']:.2f}")
            st.write(f"**Final Depression Score:** {result['final_score']:.2f}")

            # Add a little interpretation
            if result["final_score"] > 0.5:
                st.error("This entry suggests elevated depression risk")
            else:
                st.success("This entry suggests low depression risk")
        else:
            st.error(f"API error: {response.status_code}")
    else:
        st.warning("Please type something before analyzing.")

# ------------- Show Past entries -------------------
st.subheader("Mood history")
threshold = 0.5
journal_df["threshold"] = threshold
if len(journal_df) > 0:
    st.dataframe(journal_df[["timestamp","entry","final_score"]])
    st.line_chart(journal_df.set_index("timestamp")[["final_score","threshold"]])

# ----------------- Treatment Panel -----------------

st.header("💊 Treatment Matching")
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

    **LLM Therapy Chat Bot**
    🤖 Therapy chat bot that would serve as a stand-in for a therapist and help orchestrate therapy appointments
    """)
