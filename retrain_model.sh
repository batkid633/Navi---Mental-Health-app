#!/bin/bash
set -e

echo "🔄 Syncing WHOOP data..."
python navi_ml/whoop_sync_and_merge.py

echo "🧠 Training model..."
python backend/ml/train_next_day_mood.py

echo "🧩 Rebuilding features..."
python backend/ml/feature_builder.py

echo "✅ Retraining complete"
