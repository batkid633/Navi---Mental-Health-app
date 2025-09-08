import os
import pandas as pd
import zipfile

# -------- CONFIG --------
ZIP_PATH = ""   # path to your downloaded zip
EXTRACT_DIR = "data/raw/RMHD"    # where to extract the csvs
OUTPUT_FILE = "data/processed/all_posts.csv"
# ------------------------

# 1. Extract zip if not already extracted
if not os.path.exists(EXTRACT_DIR):
    print(f"Extracting {ZIP_PATH}...")
    with zipfile.ZipFile(ZIP_PATH, "r") as zip_ref:
        zip_ref.extractall(EXTRACT_DIR)

# 2. Gather all CSV file paths
csv_files = [os.path.join(EXTRACT_DIR, f) 
             for f in os.listdir(EXTRACT_DIR) if f.endswith(".csv")]

print(f"Found {len(csv_files)} CSV files.")

# 3. Load and filter each CSV
frames = []
for f in csv_files:
    try:
        df = pd.read_csv(f, low_memory=False)
        # Adjust column names if needed:
        if "post" in df.columns:
            text_col = "post"
        elif "body" in df.columns:
            text_col = "body"
        elif "selftext" in df.columns:
            text_col = "selftext"
        else:
            raise ValueError(f"No text column found in {f}")

        # Keep only subreddit + text
        df_small = df[["subreddit", text_col]].rename(columns={text_col: "text"})
        frames.append(df_small)

    except Exception as e:
        print(f"Skipping {f} due to error: {e}")

# 4. Concatenate all dataframes
all_data = pd.concat(frames, ignore_index=True)

# 5. Drop empty rows
all_data = all_data.dropna(subset=["text"])

print(f"Combined dataset shape: {all_data.shape}")

# 6. Save to processed folder
os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
all_data.to_csv(OUTPUT_FILE, index=False)

print(f"Saved combined dataset to {OUTPUT_FILE}")
