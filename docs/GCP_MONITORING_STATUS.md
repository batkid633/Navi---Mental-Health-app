# GCP Monitoring Status

Last updated: 2026-06-10

Project:

```text
project-bc878e6c-6f53-4f24-88a
```

## Created

Uptime check:

```text
Navi backend health uptime
projects/project-bc878e6c-6f53-4f24-88a/uptimeCheckConfigs/navi-backend-health-uptime-Z7zfdCY-t88
```

Stale duplicate uptime checks that targeted
`navi-backend-712966180400.us-central1.run.app` were removed on 2026-06-10.
The active check targets `navi-backend-zcp5ib6peq-uc.a.run.app`.

Log-based metrics:

```text
product_events
backend_5xx_completions
```

BigQuery analytics:

```text
Dataset: project-bc878e6c-6f53-4f24-88a.navi_analytics
Table: project-bc878e6c-6f53-4f24-88a.navi_analytics.product_events
View: project-bc878e6c-6f53-4f24-88a.navi_analytics.daily_engagement
Partitioning: event_date
Clustering: event_name, platform, event_source
UID hash salt secret: analytics-uid-hash-salt
Cloud Run writer IAM: roles/bigquery.dataEditor, roles/bigquery.jobUser
```

Alert policies:

```text
Navi backend 5xx responses
projects/project-bc878e6c-6f53-4f24-88a/alertPolicies/847524637432767747

Navi backend high latency
projects/project-bc878e6c-6f53-4f24-88a/alertPolicies/7864277754063555801

Navi backend timeout responses
projects/project-bc878e6c-6f53-4f24-88a/alertPolicies/4498222688753677323
```

Notification channel:

```text
cole_email
projects/project-bc878e6c-6f53-4f24-88a/notificationChannels/4836870703317996015
```

Runtime checks:

```text
Backend URL: https://navi-backend-zcp5ib6peq-uc.a.run.app
/health: healthy
/ready: ready
ADMIN_ACCESS_UIDS: PA1G8J3v4Fdy0CxrUxXHgSjzLfi1
MONITORING_ACCESS_UIDS: PA1G8J3v4Fdy0CxrUxXHgSjzLfi1
```

WHOOP/secret setup:

```text
Secret Manager API: enabled
Secrets created: whoop-client-id, whoop-client-secret, whoop-tokens, openai-api-key
Cloud Run service account: 712966180400-compute@developer.gserviceaccount.com
Secret accessor role: granted
```

## Still Needed

- Add GCP Billing budget alerts.
- Finish Firebase Crashlytics validation on physical Android/iOS beta builds.
- Test the WHOOP OAuth flow from the hosted app after the Firebase Hosting redeploy.
