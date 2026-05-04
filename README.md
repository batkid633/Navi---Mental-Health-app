# Navi Personal

Navi Personal is a hybrid Flutter + Python app for self-tracking, mood journaling, insights, and audio-based emotional analysis.

## What this project includes today

- **Flutter mobile/desktop app** with four main tabs:
  - `Today`: daily mood summary, volatility, momentum, and baseline deviation
  - `Journal`: entry creation with sentiment scoring and live Hive-backed storage
  - `Audio`: dual-mode audio capture for emotional venting and deeper MFCC-based analysis
  - `Insights`: trend charts, state timeline, and historical insight patterns

- **Backend API server** built with FastAPI:
  - `/insights/trends`: returns longitudinal insight trend data
  - `/audio/analyze`: accepts WAV audio uploads and returns mood predictions + audio features
  - `/audio/train`: trains the audio mood classification model from labeled training data

- **Machine learning services** including:
  - next-day mood prediction
  - LLM-powered insights generation
  - MFCC-based audio mood analysis
  - deep audio feature extraction for structured evaluation

- **Local data storage** using Hive for:
  - journal entries
  - audio recordings and metadata

## Current architecture

### Flutter app (`lib/`)

- Uses `Hive` for offline persistence.
- Provides a modern multi-tab UI with data-driven cards and charts.
- Supports audio capture and upload to the backend for analysis.
- Uses `backend_config.dart` to switch between localhost and WiFi backend access.

### Backend (`backend/`)

- FastAPI backend serving prediction and analysis endpoints.
- `ml/` contains the Python model logic, audio feature extraction, and training utilities.
- Data pipeline includes WHOOP sync, feature generation, and model training.

## How to run the project

### Start development pipeline

Use the provided dev script from the repo root:

```bash
./run_dev.sh
```

This script currently:

1. syncs WHOOP data and merges it into the dataset
2. optionally retrains the next-day mood model
3. builds the feature schema
4. starts the backend server

### Run the Flutter app

Once the backend is running, open a second terminal and run:

```bash
flutter run
```

If targeting a device over WiFi, set `lib/config/backend_config.dart`:

```dart
static const bool useWiFi = true;
static const String wiFiIP = "YOUR_IP_ADDRESS";
```

### Backend training / audio model

To enable audio mood prediction, you must supply labeled training data and train the model.

The audio training data is expected as a CSV with two columns:

```csv
audio_path,mood_label
C:/path/to/audio/happy1.wav,happy
C:/path/to/audio/sad1.wav,sad
```

Then train the model via the backend API or Python helper.

## What the audio analysis supports now

- `emotional venting` mode: free-form recording with supportive intervention suggestions
- `deeper analysis` mode: calibration sentence + guided speech + deep MFCC feature extraction
- The backend can return:
  - predicted mood + confidence
  - audio metrics like duration, tempo, spectral centroid, and RMS energy
  - mood-based intervention suggestions

## Important notes

- The audio mood prediction model only works after a trained model is available.
- Existing journal and audio data are stored locally with Hive.
- If Hive lock errors occur on Windows, the app has logic to clear stale `.lock` files and retry.

## File structure overview

- `lib/`: Flutter UI, pages, services, widgets, and models
- `backend/`: FastAPI backend server and ML code
- `backend/ml/`: audio model, feature builder, insight trends, and prediction modules
- `backend/data/`: generated CSV feature files and analytics datasets
- `navi_ml/`: WHOOP sync and merge tools

## Status

This project is currently a functional prototype with:

- journal sentiment capture
- local analytics and daily mood metrics
- backend-supported audio analysis
- a working insights pipeline

Future improvements may include better model training automation, stronger data validation, broader audio mood labels, and more polished UI feedback.
