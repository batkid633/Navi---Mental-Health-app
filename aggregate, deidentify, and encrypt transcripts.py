import pandas as pd
import uuid
import re
import spacy
from cryptography.fernet import Fernet
from dotenv import load_dotenv

# Aggregate transcripts
all_transcripts = []
data_dir = "data/DAIC/" # fix this with DAIC WOZ path

for root, dirs, files in os.walk(data_dir):
    for file in files:
        if file.endswith("_TRANSCRIPT.csv"):
            file_path = os.path.join(root, file)
            participant_id = file.split("_")[0]
            
            df = pd.read_csv(file_path)
            df["participant_id"] = participant_id
            all_transcripts.append(df)

# Combine all transcripts into one DataFrame
df = pd.concat(all_transcripts, ignore_index=True)

# Load spaCy model for Named Entity Recognition
nlp = spacy.load("en_core_web_sm")

def deidentify_text(text):
    doc = nlp(text)
    clean = text
    for ent in doc.ents:
        if ent.label_ in ["PERSON", "GPE", "LOC", "ORG", "DATE", "TIME"]:
            clean = clean.replace(ent.text, "[REDACTED]")
    # Remove any leftover IDs or email-like strings
    clean = re.sub(r'\b\d{3,}\b', '[REDACTED]', clean)
    clean = re.sub(r'\S+@\S+', '[REDACTED]', clean)
    return clean

# Apply cleaning
df["uid"] = [uuid.uuid4().hex[:8] for _ in range(len(df))]
df["text"] = df["transcript"].apply(deidentify_text)

# Keep only safe columns
keep_cols = ["uid", "text", "PHQ9_score", "depression_label"]
df = df[keep_cols]

# Save cleaned file
df.to_csv("data/DAIC_transcripts_clean.csv", index=False)

# Encrypt cleaned file

load_dotenv()
encrypt_key = os.getenv("ecryption_KEY")
fernet = Fernet(encryption_key)
with open("data/DAIC_transcripts_clean.csv", "rb") as file:
    original = file.read()
encrypted = fernet.encrypt(original)
with open("data/cleaned_daic_data_encrypted.csv", "wb") as encrypted_file:
    encrypted_file.write(encrypted)

print("De-identified dataset saved to data")
