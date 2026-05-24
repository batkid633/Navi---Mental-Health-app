# Navi Personal Backend

FastAPI-based backend for the Navi Personal mood tracking application. Provides endpoints for mood prediction, LLM-powered insights, and audio analysis.

## Setup

### Prerequisites
- Python 3.10+
- Pip or Poetry

### Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure environment variables:
```bash
cp .env.example .env
# Edit .env with your credentials:
# - OPENAI_API_KEY: Get from https://platform.openai.com/api-keys
# - WHOOP_CLIENT_ID/SECRET: Register at https://developer.whoop.com/
# Make sure values are not wrapped in extra quotes in .env.
```

3. Start the backend server locally.

From the project root, use the project virtual environment:
```powershell
.venv\Scripts\python.exe -m uvicorn backend.app:app --host 127.0.0.1 --port 8000 --reload
```

Or from the `backend` folder:
```powershell
cd backend
..\.venv\Scripts\python.exe -m uvicorn app:app --host 127.0.0.1 --port 8000 --reload
```

If you prefer to run directly from the backend package, you can also use:
```powershell
cd backend
python app.py
```

The backend will start on `http://127.0.0.1:8000`

### Authentication behavior

Production should run with:

```bash
ENVIRONMENT=production
AUTH_REQUIRED=true
ALLOW_CORS_FROM=https://app.yourdomain.com,https://www.yourdomain.com
```

When `AUTH_REQUIRED=true`, sensitive endpoints require a Firebase ID token in the `Authorization: Bearer <token>` header. The Flutter app now adds that token automatically for signed-in users. Local development can keep `AUTH_REQUIRED=false` so you can test backend behavior before wiring Firebase credentials into your shell.

For local runs, edit `.env` or set shell environment variables before starting Uvicorn. `.env.production` is a deployment template and is not automatically used by `flutter run` or the local backend.

> Important: Make sure `WHOOP_REDIRECT_URI` is set to the backend callback URL and matches the redirect configured in your Whoop developer app.
> If you run the backend from a different machine or your phone is on another device, use your computer’s LAN IP instead of `127.0.0.1`.
> Example: `http://192.168.1.100:8000/whoop/callback`
>
> For Android emulators, use `http://10.0.2.2:8000/whoop/callback` when running the backend on your host machine.
> For iOS simulators, `http://127.0.0.1:8000/whoop/callback` should work when the backend runs on the same computer.
>
> When running `flutter run -d chrome`, the backend must also allow cross-origin requests from the browser. The backend now includes CORS support for local development.

---

## API Endpoints

### Mood Prediction

#### `POST /predict/tomorrow`
Predict next-day mood change based on current features and health metrics.

**Request:**
```json
{
  "date": "2026-04-18",
  "force_reload": false
}
```

**Response:**
```json
{
  "predicted_delta": 0.42,
  "confidence": 0.87,
  "model_version": "v56",
  "insight": "Based on recent patterns, you may feel noticeably better tomorrow..."
}
```

---

### Insights

#### `GET /insights/trends`
Get historical insight trends for charting and analysis.

**Query Parameters:**
- `days` (int, default=30): Number of days of history to retrieve

**Response:**
```json
[
  {
    "date": "2026-04-17",
    "sentiment_mean": 0.65,
    "volatility": 0.34,
    "state": "Stable",
    "insight": "..."
  },
  ...
]
```

#### `POST /insights/generate`
Generate LLM-powered insight for a given date and features.

**Request:**
```json
{
  "date": "2026-04-18",
  "features": {
    "sentiment_today": 0.72,
    "rolling_mean_7": 0.55,
    "volatility_7": 0.40,
    "sleep_hours": 7.5,
    "hrv_rmssd": 120.5,
    "strain": 6.2
  }
}
```

---

### Audio Analysis

#### `POST /audio/analyze`
Analyze uploaded WAV audio and predict mood from audio features.

**Request (multipart/form-data):**
- `file`: WAV audio file
- `mode` (optional): "venting" or "analysis" (default: "venting")

**Response:**
```json
{
  "predicted_mood": "positive",
  "confidence": 0.82,
  "audio_features": {
    "duration_seconds": 45.2,
    "spectral_centroid": 3250,
    "mfcc_mean": [12.5, -8.3, 3.1, ...],
    "rms_energy": 0.156
  }
}
```

#### `POST /audio/train`
Train the audio mood classification model from labeled training data.

**Request:**
```json
{
  "training_data_csv": "path/to/labeled_audio.csv"
}
```

Expected CSV format:
```csv
audio_path,mood_label
/path/to/happy1.wav,happy
/path/to/sad1.wav,sad
```

---

## File Structure

```
backend/
├── app.py                 # FastAPI application entry point
├── requirements.txt       # Python dependencies
├── .env.example          # Environment variables template
├── ml/
│   ├── train_next_day_mood.py    # Model training pipeline
│   ├── predict_mood.py           # Mood prediction utilities
│   ├── feature_builder.py        # Feature engineering
│   ├── feature_loader.py         # Feature loading helpers
│   ├── audio_mood.py             # Audio analysis module
│   ├── llm_insights.py           # LLM insight generation
│   ├── insight_trends.py         # Trend analysis
│   ├── longitudinal_features.py  # Multi-day feature engineering
│   ├── longitudinal_model.py     # State classification model
│   ├── feature_schema.json       # Feature definitions
│   └── models/                   # Trained model files
│       ├── model_v056.pkl       # Current mood prediction model
│       ├── longitudinal_state.pkl # State classification model
│       └── audio_mood_model.pkl  # Audio mood classifier (if trained)
├── sentiment/
│   ├── __init__.py
│   └── vader.py          # VADER sentiment analysis
├── data/
│   ├── daily_features.csv        # Computed daily features
│   ├── whoop_daily_metrics.csv   # Health metrics from WHOOP API
│   └── ml_daily_dataset.csv      # Merged dataset for training
└── logs/
    ├── insight_log.jsonl         # Historical insights
    ├── llm_insights.jsonl        # LLM-generated insights cache
    └── prediction_log.csv        # Prediction history
```

---

## Development Workflow

### Running the Development Server

```bash
# From project root
./run_dev.sh
```

This script:
1. Syncs WHOOP health data
2. (Optionally) retrains the mood prediction model
3. Builds feature schema
4. Starts the FastAPI server

### Manual Model Training

```bash
cd backend
python ml/train_next_day_mood.py --force
```

### Testing Endpoints

```bash
# Predict tomorrow's mood
curl -X POST http://localhost:8000/predict/tomorrow \
  -H "Content-Type: application/json" \
  -d '{"date": "2026-04-18", "force_reload": false}'

# Get trends
curl http://localhost:8000/insights/trends?days=30

# Upload audio for analysis
curl -X POST http://localhost:8000/audio/analyze \
  -F "file=@audio_sample.wav" \
  -F "mode=venting"
```

---

## Data Pipeline

1. **WHOOP Sync** → Fetch latest health metrics from WHOOP API
2. **Feature Building** → Compute rolling averages, volatility, momentum from journal entries
3. **Merging** → Combine journal features with health metrics
4. **Model Training** → Train RandomForest model on historical data
5. **Prediction** → Generate predictions for next-day mood change
6. **LLM Insight** → Generate contextual narrative insights using OpenAI

---

## Environment Variables

See `.env.example` for all required variables:

- `OPENAI_API_KEY`: OpenAI API key for LLM insights
- `WHOOP_CLIENT_ID`: WHOOP API client ID
- `WHOOP_CLIENT_SECRET`: WHOOP API client secret
- `WHOOP_REDIRECT_URI`: OAuth callback URI (default: http://localhost:8080/callback)

---

## Troubleshooting

**Import errors when running the backend?**
- Ensure all dependencies are installed: `pip install -r requirements.txt`
- Check that `.env` file exists with required credentials

**WHOOP sync fails?**
- Verify `navi_ml/tokens/whoop_tokens.json` exists or run authentication first
- Check that WHOOP credentials are correct in `.env`

**Audio analysis not working?**
- Train the audio model first: `python ml/train_next_day_mood.py`
- Ensure `librosa` is installed for audio processing

---

## License

Navi Personal - Private use
