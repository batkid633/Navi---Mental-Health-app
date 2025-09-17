import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import joblib
import seaborn as sns
import matplotlib.pyplot as plt

# ---- 1. Create a fake dataset ----
print("Creating fake dataset to simulate the STAR*D dataset")

np.random.seed(42)
n_samples = 1000

data = {
    "depression_score": np.random.rand(n_samples),
    "anxiety_score": np.random.randint(1, 10, n_samples),
    "sleep_hours": np.random.normal(7, 1.5, n_samples).clip(3, 10),
    "exercise_hours": np.random.normal(3, 1.0, n_samples).clip(0, 10),
    "age": np.random.randint(18, 70, n_samples),
}

df = pd.DataFrame(data)

# ---- 2. Fake treatment label (simple rules for demo) ----
conditions = []
for i, row in df.iterrows():
    if row["depression_score"] > 0.7 and row["anxiety_score"] > 6:
        conditions.append("medication")
    elif row["depression_score"] > 0.5:
        conditions.append("therapy")
    elif row["sleep_hours"] < 5:
        conditions.append("lifestyle")
    else:
        conditions.append("Medication and Therapy")

df["treatment"] = conditions

# ---- 3. Train Random Forest ----
"Training Random Forest classifier..." 

X = df.drop("treatment", axis=1)
y = df["treatment"]

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

clf = RandomForestClassifier(n_estimators=100, random_state=42)
clf.fit(X_train, y_train)

# ---- 4. Evaluate ----
y_pred = clf.predict(X_test)
print(classification_report(y_test, y_pred))

# Plot feature importance
importances = clf.feature_importances_
feature_names = X.columns
feat_imp = pd.DataFrame({"feature": feature_names, "importance": importances})
feat_imp = feat_imp.sort_values("importance", ascending=False)

plt.figure(figsize=(8,5))
sns.barplot(x="importance", y="feature", data=feat_imp)
plt.title("Feature Importance in Treatment Prediction")
plt.show()

# ---- 5. Save model ----
joblib.dump(clf, "models/treatment_model.pkl")
print("Treatment model saved to models/treatment_model.pkl")
