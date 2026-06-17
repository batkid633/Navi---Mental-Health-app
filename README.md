# Navi Personal

Navi Personal is a Flutter + FastAPI mental health journaling and self-insight app. It combines local-first journaling, Firebase-backed sync, sentiment analysis, audio reflection, WHOOP-informed feature pipelines, next-day mood prediction, LLM-assisted insights, and user evaluation feedback.

Navi is currently an advanced MVP / beta-candidate project. It is not a clinical device, emergency service, diagnosis tool, or treatment system.

## Current Product Surface

- `Today`: daily mood state, rolling sentiment, volatility, momentum, baseline deviation, next-day prediction, generated insight, and evaluation feedback.
- `Journal`: local-first journal entry creation, sentiment scoring, cloud sync status, retry handling, detail editing, and deletion.
- `Audio`: emotional venting and deeper-analysis recording modes, local audio metadata, cloud audio upload, backend audio analysis, and training labels.
- `Insights`: trend charts, state timeline, body/wellness metrics, backend trend loading with local fallback.
- `Settings`: consent/privacy controls, cloud sync toggle, personalized insight toggle, research/data-sharing opt-in, backend health check, WHOOP connection, data export, and account/data deletion.

## Architecture

### Flutter App

The app lives in `lib/` and targets Flutter-supported platforms. The current practical beta path is Android first and iOS once a Mac/TestFlight path is available.

Important client pieces:

- `lib/main.dart`: Firebase/Hive startup and app shell.
- `lib/widgets/auth_gate.dart`: Firebase-authenticated entry flow plus debug local mode.
- `lib/services/data_service.dart`: local-first persistence, migrations, sync retry, export/delete orchestration.
- `lib/services/cloud_persistence_service.dart`: Firestore and Storage persistence.
- `lib/services/analytics_service.dart`: privacy-safe user-scoped product analytics in Firestore.
- `lib/models/evaluation_feedback.dart`: prediction/insight evaluation records for model feedback.

### Persistence Model

Navi is intentionally local-first:

- Hive stores journal entries, audio metadata, settings, and evaluation feedback on-device.
- Firestore mirrors journal entries, audio metadata, privacy consent, product analytics, daily analytics, backend ML features, and evaluation feedback when cloud sync is enabled.
- Firebase Storage stores synced audio files under user-owned paths.
- The FastAPI backend stores per-user runtime ML files/logs and can hydrate feature data from Firestore.

Hive is not obsolete. It is the offline cache and immediate local source of truth. Firestore/Storage are the durable cloud sync layer.

### Backend

The backend lives in `backend/` and is served by FastAPI.

Core endpoints include:

- `POST /sentiment`
- `POST /predict/tomorrow`
- `POST /ml/daily-features`
- `GET /insights/trends`
- `POST /audio/analyze`
- `POST /audio/train` admin-only
- `GET /whoop/connect`
- `GET /whoop/status`
- `GET /fitbit/connect`
- `GET /fitbit/status`
- `GET /apple-health/status`
- `POST /whoop/retrain` admin-only
- `GET /data/export`
- `DELETE /data/delete`
- `GET /health`
- `GET /ready`
- `GET /monitoring/summary` admin-only
- `GET /config-check` admin-only

Production-sensitive endpoints require Firebase ID tokens when `AUTH_REQUIRED=true`.

### ML and Insights

Implemented ML/analysis components:

- VADER sentiment analysis with local fallback in the Flutter client.
- Next-day mood prediction using saved sklearn models.
- Per-user calibration when enough user feature history exists.
- LLM-generated supportive insight text with fallback.
- MFCC/audio feature extraction and exploratory audio mood classification.
- Heuristic audio fallback when no trained audio model is available.
- User evaluation feedback for prediction accuracy, helpfulness, and actual mood direction.

These features are exploratory wellness features and should be evaluated before any clinical or research claims.

## Cloud and Monitoring

Navi uses Firebase and Google Cloud:

- Firebase Auth
- Firestore
- Firebase Storage
- Firebase Hosting for web builds
- Cloud Run for the backend
- Secret Manager for production secrets
- Cloud Logging via Cloud Run stdout
- Cloud Monitoring through health checks, log-based metrics, and alert policies
- BigQuery analytics ingestion for privacy-safe product events

Monitoring docs:

- `docs/MONITORING_AND_ANALYTICS.md`
- `docs/GCP_MONITORING_SETUP.md`
- `docs/BIGQUERY_ANALYTICS.md`
- `docs/RESEARCH_DATA_SCHEMA.md`

Before beta, verify that Cloud Monitoring uptime checks, alert policies, notification channels, budget alerts, and Firebase Crashlytics are active in the actual GCP/Firebase console.

## Running Locally

Install Flutter dependencies:

```bash
flutter pub get
```

Start the backend from the project root:

```powershell
.venv\Scripts\python.exe -m uvicorn backend.app:app --host 127.0.0.1 --port 8000 --reload
```

Run the Flutter app:

```bash
flutter run -d chrome
flutter run -d windows
```

For Android emulator access to the local backend, use `http://10.0.2.2:8000`. For a physical phone on the same network, use the host computer LAN IP in Settings.

## Configuration

Local development can run with:

```bash
ENVIRONMENT=development
AUTH_REQUIRED=false
```

Production should use:

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
ADMIN_ACCESS_UIDS=<comma-separated-admin-firebase-uids>
MONITORING_ACCESS_UIDS=<comma-separated-admin-firebase-uids>
ANALYTICS_BIGQUERY_ENABLED=false
ANALYTICS_BIGQUERY_PROJECT_ID=<gcp-project-id>
ANALYTICS_BIGQUERY_DATASET=navi_analytics
ANALYTICS_BIGQUERY_TABLE=product_events
ANALYTICS_UID_HASH_SALT_SECRET=analytics-uid-hash-salt
```

The exact `WHOOP_REDIRECT_URI` must also be registered in the WHOOP developer dashboard for the Navi OAuth client.
The exact `GOOGLE_HEALTH_REDIRECT_URI` must also be registered in the Google Cloud OAuth client. NAVI keeps `/fitbit/callback` as the migration callback route, but authorization uses Google Health OAuth endpoints and Google Health scopes. Apple Health is native-device based and requires iOS HealthKit entitlements plus a Flutter HealthKit/health plugin before sync can be enabled.

See `backend/cloud-run-env.yaml`, `.env.example`, and `GCP_QUICKSTART.md`.

## Verification

Useful checks:

```bash
flutter analyze
flutter test test/hive_persistence_test.dart
python -m py_compile backend/app.py backend/auth.py backend/config.py backend/user_data.py backend/whoop_api.py backend/ml/audio_mood.py backend/ml/feature_loader.py backend/ml/predict_mood.py
```

Known current test gap:

- Full `flutter test` still fails in `test/widget_test.dart` because Firebase Core is not mocked for the test runner.
- `flutter analyze` reports existing info/warning items in `journal_detail_page.dart` and web audio utility files.

## Beta Readiness Checklist

Before external beta testing:

- Deploy current Firestore and Storage rules.
- Deploy current Cloud Run backend with `AUTH_REQUIRED=true`.
- Set real `ADMIN_ACCESS_UIDS` and `MONITORING_ACCESS_UIDS`.
- Replace placeholder CORS domains.
- Enable GCP uptime checks, log-based metrics, alert policies, and budget alerts.
- Validate Firebase Crashlytics on physical Android/iOS builds.
- Verify account/data deletion end to end.
- Verify export includes local, cloud, backend, and evaluation feedback data.
- Test cloud sync on/off behavior.
- Test audio recording, upload, analysis, and deletion on a physical phone.
- Fix Firebase widget-test setup.
- Keep model wording framed as experimental and non-diagnostic.

## Repository Layout

- `lib/`: Flutter app, models, pages, services, widgets, legal text, utilities.
- `backend/`: FastAPI backend, auth/config, user data handling, ML/audio/WHOOP modules.
- `backend/ml/models/`: saved model artifacts.
- `backend/data/`: seed/training feature CSVs.
- `navi_ml/`: standalone WHOOP sync/merge utilities.
- `docs/`: privacy, terms, HIPAA-oriented notes, security review, monitoring, incident response, access review.
- `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`: Flutter platform projects.

## Status

Current status: advanced MVP with real full-stack infrastructure and local-first cloud sync.

Primary development priorities:

1. Monitoring and crash reporting for beta.
2. Mobile physical-device testing.
3. Test cleanup and analyzer cleanup.
4. Evaluation feedback export/admin review.
5. Research data schema validation and IRB-ready study packet.
6. Model validation over longitudinal personal/beta use.
7. Legal/privacy/security review before broader use with sensitive mental health data.
