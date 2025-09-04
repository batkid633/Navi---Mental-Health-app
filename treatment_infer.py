import numpy as np

def predict_treatment(patient_rows, model, scaler, classes):
    # patient_rows: list of [age, severity_1to9, sleep_issues, anxiety]
    X = scaler.transform(patient_rows)
    probs = model.predict(X, verbose=0)
    top_idx = probs.argmax(axis=1)
    labels = [classes[i] for i in top_idx]
    return probs, labels