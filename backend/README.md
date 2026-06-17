# Navi Backend

FastAPI backend for Navi Personal. It provides sentiment scoring, prediction, insights, audio analysis, WHOOP connection helpers, data export/delete, runtime monitoring, and admin-only operational endpoints.

## Run Locally

From the repo root:

```powershell
.venv\Scripts\python.exe -m uvicorn backend.app:app --host 127.0.0.1 --port 8000 --reload
```

For unauthenticated local testing:

```powershell
$env:ENVIRONMENT="development"
$env:AUTH_REQUIRED="false"
.venv\Scripts\python.exe -m uvicorn backend.app:app --host 127.0.0.1 --port 8000 --reload
```

Production should run with:

```bash
ENVIRONMENT=production
AUTH_REQUIRED=true
SECRET_MANAGER_PROJECT_ID=<gcp-project-id>
OPENAI_API_KEY_SECRET=<secret-name>
WHOOP_CLIENT_ID_SECRET=<secret-name>
WHOOP_CLIENT_SECRET_SECRET=<secret-name>
WHOOP_TOKENS_SECRET=<secret-name>
WHOOP_REDIRECT_URI=https://navi-backend-zcp5ib6peq-uc.a.run.app/whoop/callback
GOOGLE_HEALTH_CLIENT_ID_SECRET=<secret-name>
GOOGLE_HEALTH_CLIENT_SECRET_SECRET=<secret-name>
GOOGLE_HEALTH_TOKENS_SECRET=<secret-name>
GOOGLE_HEALTH_REDIRECT_URI=https://navi-backend-zcp5ib6peq-uc.a.run.app/fitbit/callback
ALLOW_CORS_FROM=<firebase-hosting-origin-or-app-domain>
ADMIN_ACCESS_UIDS=<comma-separated-admin-uids>
MONITORING_ACCESS_UIDS=<comma-separated-admin-uids>
ANALYTICS_BIGQUERY_ENABLED=false
ANALYTICS_BIGQUERY_PROJECT_ID=<gcp-project-id>
ANALYTICS_BIGQUERY_DATASET=navi_analytics
ANALYTICS_BIGQUERY_TABLE=product_events
ANALYTICS_UID_HASH_SALT_SECRET=analytics-uid-hash-salt
```

The same `WHOOP_REDIRECT_URI` must be registered in the WHOOP developer dashboard for the Navi OAuth client. `/whoop/connect` uses it when building the WHOOP authorization URL, and `/whoop/callback` uses the same value during code exchange.

The Cloud Run runtime service account also needs `roles/secretmanager.secretVersionAdder` on the `whoop-tokens` secret so successful OAuth callbacks can persist refreshed access and refresh tokens.

Google Health uses the same backend browser OAuth pattern. Register `GOOGLE_HEALTH_REDIRECT_URI` in the Google Cloud OAuth client and grant the runtime service account `roles/secretmanager.secretVersionAdder` on the Google Health token secret before enabling the integration. NAVI keeps `/fitbit/callback` as the migration callback route. Apple Health uses native iOS HealthKit permissions rather than backend OAuth.

## Auth

Sensitive endpoints use `get_current_user`, which validates Firebase ID tokens when `AUTH_REQUIRED=true`.

Admin endpoints use `require_admin`. A user is admin if:

- Firebase token claim `admin=true`
- Firebase token claim `navi_admin=true`
- UID appears in `ADMIN_ACCESS_UIDS` or `MONITORING_ACCESS_UIDS`

## Endpoints

Public health/runtime:

- `GET /`
- `GET /version`
- `GET /live`
- `GET /health`
- `GET /ready`
- `GET /whoop/callback`
- `GET /fitbit/callback`

Authenticated user endpoints:

- `POST /sentiment`
- `POST /analytics/events`
- `POST /predict/tomorrow`
- `POST /ml/daily-features`
- `GET /insights/trends`
- `POST /audio/analyze`
- `GET /whoop/connect`
- `GET /whoop/status`
- `GET /fitbit/connect`
- `GET /fitbit/status`
- `GET /apple-health/status`
- `GET /journal/history`
- `GET /data/export`
- `DELETE /data/delete`

Admin-only endpoints:

- `GET /config-check`
- `GET /monitoring/summary`
- `POST /audio/train`
- `POST /whoop/retrain`

## Data Paths

- Global seed/training data: `backend/data/`
- Per-user runtime data: `backend/user_runtime_data/`
- Per-user prediction logs: `backend/user_runtime_data/<hashed-user>/logs/`
- Model artifacts: `backend/ml/models/`

Runtime user data is ignored by git.

## ML Behavior

- Next-day prediction uses the active model listed in `backend/ml/models/metadata.json`.
- Per-user calibration is used when enough user feature rows are available.
- LLM insights use OpenAI when configured and fall back to local supportive text otherwise.
- Audio analysis extracts acoustic/MFCC features and uses a trained model when available.
- If no audio model is available, Navi returns a transparent heuristic fallback.

## Monitoring

The backend emits structured JSON logs to stdout. Cloud Run sends these to Cloud Logging.
When enabled, `POST /analytics/events` also writes privacy-safe product events
to BigQuery.

Useful endpoints:

- `/health`: uptime checks
- `/ready`: dependency/config readiness
- `/monitoring/summary`: admin-only aggregate counters

Monitoring assets live in `gcp/monitoring/`; setup notes live in `docs/GCP_MONITORING_SETUP.md`.

## Verification

```powershell
python -m py_compile backend\app.py backend\auth.py backend\config.py backend\user_data.py backend\whoop_api.py backend\ml\audio_mood.py backend\ml\feature_loader.py backend\ml\predict_mood.py
```
