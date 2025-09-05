import os
import pandas as pd
from glob import glob

# Use current working directory
DATA_DIR = os.getcwd()
OUTPUT_FILE = os.path.join(DATA_DIR, "rmhd_master.csv")

# Collect all CSV files in this folder
csv_files = glob(os.path.join(DATA_DIR, "*.csv"))
print(f"Found {len(csv_files)} CSV files in {DATA_DIR}")

dfs = []

for file in csv_files:
    try:
        df = pd.read_csv(file, usecols=["subreddit", "post"])
        dfs.append(df)
        print(f"Loaded {os.path.basename(file)} ({len(df)} rows)")
    except ValueError as e:
        print(f"Skipping {os.path.basename(file)}: {e}")

# Concatenate everything
if dfs:
    master_df = pd.concat(dfs, ignore_index=True)
    print(f"Total rows combined: {len(master_df)}")

    # Save master CSV
    master_df.to_csv(OUTPUT_FILE, index=False)
    print(f"Saved master file: {OUTPUT_FILE}")
else:
    print("No valid CSVs processed.")