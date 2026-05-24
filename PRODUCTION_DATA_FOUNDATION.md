# Navi Production Data Foundation

This is the working checklist for moving Navi from a local prototype into a production-grade mental health companion app.

## Current Foundation Added

- Flutter sends the signed-in Firebase user's ID token to backend API calls.
- FastAPI verifies Firebase ID tokens on sensitive routes when `AUTH_REQUIRED=true`.
- Public backend routes are limited to `/`, `/health`, `/ready`, and `/whoop/callback`.
- CORS is controlled by `ALLOW_CORS_FROM` instead of allowing every website.
- Cloud Run docs now separate backend deploys, frontend deploys, mobile releases, and environment-only changes.
- Firestore is wired as the durable metadata store for journal and audio entries.
- Cloud Storage is wired for raw audio upload when a signed-in user saves audio.
- Hive now acts as a local/offline cache instead of the only persistence layer.
- Firebase security rules are defined for user-owned Firestore documents and Storage audio paths.
- Backend prediction, trend, prediction-log, and LLM insight-cache paths are now user-aware.
- The app can upload each signed-in user's daily sentiment feature timeline to `/ml/daily-features`.

## How The Pieces Fit Together

The Flutter app is the client. It runs on a user's phone, desktop, or browser. Because client code lives on a user's device, it cannot be trusted by itself.

Firebase Auth is the identity layer. It answers: "Who is this user?" After sign-in, Firebase gives the app an ID token.

FastAPI on Cloud Run is the private application logic layer. It receives requests from the app, verifies the Firebase ID token, runs prediction/audio/insight logic, and should decide which user data can be read or written.

The database is the durable memory layer. Local Hive storage is useful for offline mode, but production user data needs to sync to a durable cloud store.

Cloud Storage is the file layer. Audio recordings should live in a storage bucket with user-scoped paths and strict access rules, not inside the Cloud Run container.

BigQuery is the analytics and research-readiness layer. It should receive de-identified or consented exports, not become the app's primary operational database.

## Next Code Milestone

1. Choose the operational database:
   - Firestore is fastest for app-style user documents, offline-friendly sync, and simpler iteration.
   - Cloud SQL/Postgres is better for relational reporting, explicit schema, and future research-grade querying.
   - Data Connect can sit on top of Cloud SQL when you want a typed GraphQL API, but it adds setup complexity.

2. Add user-scoped cloud persistence:
   - `users/{uid}`
   - `users/{uid}/journal_entries/{entryId}`
   - `users/{uid}/audio_entries/{entryId}`
   - `users/{uid}/mood_predictions/{predictionDate}`
   - Status: journal/audio metadata are wired in the app through `DataService`.

3. Add Cloud Storage for audio:
   - bucket: `navi-audio-prod`
   - path pattern: `users/{uid}/audio/{audioEntryId}.wav`
   - store only metadata and storage URL/path in the database.
   - Status: new audio recordings upload to Storage for signed-in users when the local file/blob is available.

4. Add user data rights:
   - export my data
   - delete my account
   - delete a journal entry
   - delete an audio recording
   - consent toggles for product improvement and future research use

5. Add production observability:
   - request logs without raw journal text
   - error tracking
   - audit log for sensitive reads/writes
   - billing alerts
   - latency and error-rate alerts

## User-Based Modeling Status

The backend now checks for a per-user dataset before falling back to the global prototype dataset:

- `backend/user_runtime_data/{uid}/daily_features.csv`
- `backend/user_runtime_data/{uid}/ml_daily_dataset.csv`
- `backend/user_runtime_data/{uid}/logs/prediction_log.csv`
- `backend/user_runtime_data/{uid}/logs/llm_insights.jsonl`

This is the first personalization layer. It means each signed-in user's trends and prediction inputs can be based on their own journal-derived daily features. The current RandomForest model is still a global model artifact, so the next modeling milestone is per-user calibration or fine-tuning once each user has enough samples.

## HIPAA-Oriented Notes

Use only Google Cloud services that are eligible under the Google Cloud BAA for workloads containing PHI. Do not use Pre-GA services with PHI unless Google explicitly says that specific Pre-GA service is allowed. Avoid logging raw journal text, audio transcripts, access tokens, or biometric data.

This is product/security planning, not legal advice. A HIPAA launch also needs administrative policies, user support processes, incident response, access reviews, vendor review, and a signed BAA where required.

## Research/NIMH Readiness Later

Research use should be separated from normal product use. Build the product database first, then add a governed research export path with explicit consent, de-identification, an IRB-aware protocol, a data dictionary, and versioned mood scoring definitions.
