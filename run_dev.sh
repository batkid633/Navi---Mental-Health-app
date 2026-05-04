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
PYTHONPATH="$PWD:$PYTHONPATH" python navi_ml/whoop_sync_and_merge.py

# 3. Train model
if [ -z "$RETRAIN_OPT" ]; then
	read -p "Retrain model? [y/N]: " yn
	case "$yn" in
		[Yy]*) RETRAIN_OPT="--force" ;;
		*) RETRAIN_OPT="" ;;
	esac
fi

echo "Training next-day mood model..."
PYTHONPATH="$PWD:$PYTHONPATH" python backend/ml/train_next_day_mood.py $RETRAIN_OPT

# 4. Build features
echo "Building feature schema..."
PYTHONPATH="$PWD:$PYTHONPATH" python backend/ml/feature_builder.py

# 5. Start backend (background) - listening on all interfaces for WiFi
echo "Starting backend server on 0.0.0.0:8000..."
echo ""
echo "⚠️  WiFi SETUP INSTRUCTIONS:"
echo "1. Find your computer's IP address:"
echo "   - Windows PowerShell: ipconfig | grep IPv4"
echo "   - Mac Terminal: ifconfig | grep inet"
echo "2. Open lib/config/backend_config.dart"
echo "3. Set useWiFi = true"
echo "4. Set wiFiIP = \"YOUR_IP_ADDRESS\" (e.g., 192.168.1.100)"
echo "5. Make sure iPhone is on same WiFi as this computer"
echo "6. Run app with 'flutter run'"
echo ""
cd backend
python -m uvicorn app:app --host 0.0.0.0 --port 8000 --reload &
BACKEND_PID=$!
cd ..

# Give backend time to boot
sleep 6

# 6. Start Flutter
echo "Starting Flutter app..."
flutter run

# Cleanup on exit
trap "kill $BACKEND_PID" EXIT
