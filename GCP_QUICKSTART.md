# GCP Quickstart

This is the current Google Cloud / Firebase path for Navi beta infrastructure.

## Current Project

```text
project-bc878e6c-6f53-4f24-88a
```

Current backend URL:

```text
https://navi-backend-zcp5ib6peq-uc.a.run.app
```

## Services Used

- Firebase Auth
- Firestore
- Firebase Storage
- Firebase Hosting
- Cloud Run
- Artifact Registry
- Secret Manager
- Cloud Logging
- Cloud Monitoring

Cloud SQL and Pub/Sub are not required for the current beta path unless you intentionally add them later.

## Deploy Backend

From the repo root:

```powershell
$PROJECT_ID="project-bc878e6c-6f53-4f24-88a"
$REGION="us-central1"

gcloud.cmd config set project $PROJECT_ID

gcloud.cmd builds submit backend `
  --tag us-central1-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest

gcloud.cmd run deploy navi-backend `
  --image=us-central1-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest `
  --platform=managed `
  --region=$REGION `
  --project=$PROJECT_ID `
  --memory=2Gi `
  --cpu=1 `
  --timeout=3600 `
  --allow-unauthenticated `
  --env-vars-file=backend/cloud-run-env.yaml
```

Check deployment:

```powershell
gcloud.cmd run services describe navi-backend `
  --region=$REGION `
  --project=$PROJECT_ID `
  --format="value(status.url)"
```

## Deploy Firebase Rules

```powershell
firebase.cmd deploy --only firestore:rules,storage --project project-bc878e6c-6f53-4f24-88a
```

## Deploy Web Build

```powershell
flutter pub get

flutter build web --release `
  --dart-define=BACKEND_URL=https://navi-backend-zcp5ib6peq-uc.a.run.app

firebase.cmd deploy --only hosting --project project-bc878e6c-6f53-4f24-88a
```

## Required Production Env Values

Review `backend/cloud-run-env.yaml` before deployment.

Important values:

- `ENVIRONMENT=production`
- `AUTH_REQUIRED=true`
- `ALLOW_CORS_FROM=<firebase hosting origins>`
- `SECRET_MANAGER_PROJECT_ID=project-bc878e6c-6f53-4f24-88a`
- `OPENAI_API_KEY_SECRET=<secret-name>`
- `WHOOP_CLIENT_ID_SECRET=<secret-name>`
- `WHOOP_CLIENT_SECRET_SECRET=<secret-name>`
- `WHOOP_TOKENS_SECRET=<secret-name>`
- `WHOOP_REDIRECT_URI=https://navi-backend-zcp5ib6peq-uc.a.run.app/whoop/callback`
- `GOOGLE_HEALTH_CLIENT_ID_SECRET=<secret-name>`
- `GOOGLE_HEALTH_CLIENT_SECRET_SECRET=<secret-name>`
- `GOOGLE_HEALTH_TOKENS_SECRET=<secret-name>`
- `GOOGLE_HEALTH_REDIRECT_URI=https://navi-backend-zcp5ib6peq-uc.a.run.app/fitbit/callback`
- `ADMIN_ACCESS_UIDS=<your Firebase UID>`
- `MONITORING_ACCESS_UIDS=<your Firebase UID>`

Register the same `WHOOP_REDIRECT_URI` in the WHOOP developer dashboard for the Navi OAuth client before testing the connection flow.
Register the same `GOOGLE_HEALTH_REDIRECT_URI` in the Google Cloud OAuth client before testing Google Health/Fitbit migration auth.

The Cloud Run runtime service account must also be able to append token versions to the WHOOP token secret. For the current deployed service account, grant:

```powershell
gcloud.cmd secrets add-iam-policy-binding whoop-tokens `
  --project=project-bc878e6c-6f53-4f24-88a `
  --member=serviceAccount:712966180400-compute@developer.gserviceaccount.com `
  --role=roles/secretmanager.secretVersionAdder
```

Repeat the same grant for the Google Health token secret after creating it.

## Monitoring

1. Create a real notification channel in GCP Monitoring.
2. Copy the full notification channel resource name.
3. Run:

```powershell
.\gcp\monitoring\setup-monitoring.ps1 `
  -ProjectId "project-bc878e6c-6f53-4f24-88a" `
  -BackendHost "navi-backend-zcp5ib6peq-uc.a.run.app" `
  -NotificationChannel "projects/project-bc878e6c-6f53-4f24-88a/notificationChannels/4836870703317996015"
```

See `docs/GCP_MONITORING_SETUP.md` for details.

## Beta Checklist

- Backend `/health` returns `200`.
- Backend `/ready` returns `200`.
- WHOOP dashboard redirect URI matches the deployed backend `/whoop/callback` URL.
- Google Cloud OAuth redirect URI matches the deployed backend `/fitbit/callback` URL.
- Apple Health remains disabled until iOS HealthKit entitlements and native permissions are implemented.
- Signed-in user can save a journal entry.
- Journal entry syncs to Firestore.
- Evaluation feedback syncs to Firestore.
- Audio metadata syncs to Firestore.
- Audio file syncs to Firebase Storage.
- Data export includes local, cloud, backend, and evaluation feedback data.
- Delete account/data clears Firestore, Storage, backend runtime data, and local Hive boxes.
- Monitoring alert test reaches your notification channel.
- Budget alerts are active.
- Firebase Crashlytics is added before external mobile beta.

## Current Verification Commands

```powershell
flutter analyze
flutter test test\hive_persistence_test.dart
python -m py_compile backend\app.py backend\auth.py backend\config.py backend\user_data.py backend\whoop_api.py backend\ml\audio_mood.py backend\ml\feature_loader.py backend\ml\predict_mood.py
```

Known issue: full `flutter test` still fails until Firebase Core is mocked in `test/widget_test.dart`.
