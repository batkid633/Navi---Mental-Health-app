import streamlit as st, pandas as pd, numpy as np
from datetime import datetime
from pathlib import Path
from src.io_utils import load_mood_artifacts, load_treatment_artifacts
from src.mood_infer import predict_mood
from src.treatment_infer import predict_treatment

st.set_page_config(page_title="AI Mood & Treatment", layout="centered")

DATA_DIR = Path("data/app"); DATA_DIR.mkdir(parents=True, exist_ok=True)
LOG_CSV = DATA_DIR / "mood_log.csv"

@st.cache_resource
def _load_all():
    mood_model, vectorizer, sev_classes = load_mood_artifacts()
    trt_model, scaler, trt_classes = load_treatment_artifacts()
    return mood_model, vectorizer, sev_classes, trt_model, scaler, trt_classes

mood_model, vectorizer, sev_classes, trt_model, scaler, trt_classes = _load_all()

# Init session log
if "mood_log" not in st.session_state:
    st.session_state.mood_log = pd.DataFrame(columns=[
        "entry_number","timestamp","text","severity","prob_None","prob_Mild","prob_Moderate","prob_Severe"
    ])

st.title("AI Mood & Treatment Prototype")

# ----------------- Mood Panel -----------------
st.header("📓 Daily Mood Journal")
entry = st.text_area("How are you feeling today?", height=120)

if st.button("Analyze Mood"):
    probs, labels = predict_mood([entry], mood_model, vectorizer, sev_classes)
    p = probs[0]
    sev_map = {str(sev_classes[i]): float(p[i]) for i in range(len(sev_classes))}
    pred_label = labels[0]

    st.success(f"Predicted severity: **{pred_label}**")
    st.bar_chart(pd.Series(sev_map))

    row = {
        "entry_number": len(st.session_state.mood_log)+1,
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "text": entry,
        "severity": str(pred_label),
        "prob_None": float(p[sev_classes.index(0)] if 0 in sev_classes else np.nan),
        "prob_Mild": float(p[sev_classes.index(1)] if 1 in sev_classes else np.nan),
        "prob_Moderate": float(p[sev_classes.index(2)] if 2 in sev_classes else np.nan),
        "prob_Severe": float(p[sev_classes.index(3)] if 3 in sev_classes else np.nan),
    }
    st.session_state.mood_log = pd.concat([st.session_state.mood_log, pd.DataFrame([row])], ignore_index=True)
    st.session_state.mood_log.to_csv(LOG_CSV, index=False)

if len(st.session_state.mood_log) > 0:
    st.subheader("Mood Over Time")
    df = st.session_state.mood_log.copy()
    sev_to_num = {"None":0,"Mild":1,"Moderate":2,"Severe":3}
    # Also support numeric labels if you stored 0..3
    df["sev_num"] = df["severity"].map(sev_to_num).fillna(pd.to_numeric(df["severity"], errors="coerce"))
    st.line_chart(df.set_index("entry_number")["sev_num"])

    st.download_button("Download mood log (CSV)", data=df.to_csv(index=False), file_name="mood_log.csv")

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