# GCP Monitoring Setup

This repo now includes starter Cloud Monitoring assets under `gcp/monitoring/`.

These assets are intentionally small and beta-focused. They cover the core things you need to know quickly:

- Is the backend reachable?
- Are 5xx errors happening?
- Are requests getting slow?
- Are requests timing out?
- Are product events being logged?

## Required Inputs

Before applying monitoring, collect:

- GCP project ID
- Cloud Run backend URL
- notification channel ID for your email/SMS/Slack/PagerDuty channel
- admin Firebase UID for `/monitoring/summary`

Current likely values:

- Project: `project-bc878e6c-6f53-4f24-88a`
- Backend: `https://navi-backend-zcp5ib6peq-uc.a.run.app`

Verify these before running setup.

## Console Setup Checklist

1. Open Google Cloud Console.
2. Select the Firebase/GCP project used by Navi.
3. Go to Monitoring.
4. Create a notification channel with your real email.
5. Copy the notification channel resource name.
6. Confirm Cloud Run logs are visible in Logs Explorer.
7. Confirm `/health` returns `200`.
8. Confirm `/ready` returns `200`.
9. Set `ADMIN_ACCESS_UIDS` and `MONITORING_ACCESS_UIDS` in Cloud Run.

## Apply With PowerShell

From the repo root:

```powershell
.\gcp\monitoring\setup-monitoring.ps1 `
  -ProjectId "project-bc878e6c-6f53-4f24-88a" `
  -BackendHost "navi-backend-zcp5ib6peq-uc.a.run.app" `
  -NotificationChannel "projects/project-bc878e6c-6f53-4f24-88a/notificationChannels/4836870703317996015"
```

The script uses `gcloud monitoring uptime create`, `gcloud monitoring policies create`, and `gcloud logging metrics create`.

If your installed `gcloud` does not support one of those commands, use the JSON files as the source of truth and create the equivalent resources in the GCP Console.

## Included Policies

- `uptime-health.json`: uptime check against `/health`.
- `alert-cloud-run-5xx.json`: alert when Cloud Run 5xx responses exceed threshold.
- `alert-cloud-run-latency.json`: alert when request latency is elevated.
- `alert-cloud-run-timeouts.json`: alert when timeout responses occur.
- `metric-product-events.json`: log-based metric for backend `product_event` logs.
- `metric-backend-errors.json`: log-based metric for backend 5xx completions.

## Budget Monitoring

Set budget alerts manually in Billing:

- 50 percent of monthly budget
- 80 percent of monthly budget
- 100 percent of monthly budget
- 120 percent of monthly budget

For beta, include Firebase/Firestore/Storage, Cloud Run, Artifact Registry, Secret Manager, Cloud Logging, and any paid AI API usage in the cost review.

## Firebase Monitoring

Before mobile beta, add Firebase Crashlytics. This repo does not yet include Crashlytics dependencies.

Recommended beta signals:

- crash-free users
- app startup crashes
- auth flow failures
- journal save failures
- audio recording failures
- audio upload failures
- backend prediction failures
- evaluation feedback saves

## Admin Runtime Check

After setting admin UIDs, call:

```powershell
Invoke-RestMethod -Uri "https://navi-backend-zcp5ib6peq-uc.a.run.app/monitoring/summary" -Headers @{ Authorization = "Bearer <firebase-id-token>" }
```

This should return aggregate request counters and product event counters without exposing journal text or audio content.
