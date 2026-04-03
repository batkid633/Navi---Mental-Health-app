#!/bin/bash
set -e  # stop on error

echo "=== Navi Dev Pipeline Starting ==="

# Allow non-interactive control via --retrain flag. If not provided,
# prompt the user to confirm retraining.
RETRAIN_OPT=""
for arg in "$@"; do
	case "$arg" in
		--retrain) RETRAIN_OPT="--force" ;;
	esac
done

# 1. Sync + merge WHOOP data (tokens auto-refresh)
echo "Syncing WHOOP data..."
python navi_ml/whoop_sync_and_merge.py

# 3. Train model
if [ -z "$RETRAIN_OPT" ]; then
	read -p "Retrain model? [y/N]: " yn
	case "$yn" in
		[Yy]*) RETRAIN_OPT="--force" ;;
		*) RETRAIN_OPT="" ;;
	esac
fi

echo "Training next-day mood model..."
python backend/ml/train_next_day_mood.py $RETRAIN_OPT

# 4. Build features
echo "Building feature schema..."
python backend/ml/feature_builder.py

# 5. Start backend (background)
echo "Starting backend server..."
cd backend
uvicorn app:app --reload &
BACKEND_PID=$!
cd ..

# Give backend time to boot
sleep 6

# 6. Start Flutter
echo "Starting Flutter app..."
flutter run

# Cleanup on exit
trap "kill $BACKEND_PID" EXIT
