# BigQuery Analytics Ingestion

Navi exports privacy-safe product analytics to BigQuery through the FastAPI
backend. The app still writes user-scoped analytics to Firestore for export,
delete, and troubleshooting, but BigQuery is the admin analytics warehouse.

## Current Pipeline

1. Flutter calls `AnalyticsService.track(...)`.
2. The event is normalized and written to:
   - `users/{uid}/analytics_events`
   - `users/{uid}/daily_analytics`
3. The same safe event is sent to `POST /analytics/events` with the Firebase ID
   token.
4. The backend validates auth, normalizes fields again, hashes the Firebase UID,
   and inserts rows into BigQuery when `ANALYTICS_BIGQUERY_ENABLED=true`.

No journal text, audio files, transcripts, raw notes, emails, names, or raw
Firebase UIDs are exported to BigQuery.

## BigQuery Table

Default table:

```text
project-bc878e6c-6f53-4f24-88a.navi_analytics.product_events
```

Schema source:

```text
gcp/bigquery/analytics_events_schema.json
```

Current row schema version:

```text
navi_product_event_v2
```

Product analytics rows include governance fields:

- `schema_version`
- `client_schema_version`
- `data_classification`
- `contains_health_content`

Partitioning:

- Daily partition on `event_date`.

Clustering:

- `event_name`
- `platform`
- `event_source`

## Setup

From the repo root:

```powershell
.\gcp\bigquery\setup-bigquery-analytics.ps1 `
  -ProjectId "project-bc878e6c-6f53-4f24-88a" `
  -Dataset "navi_analytics" `
  -Table "product_events" `
  -Location "US" `
  -CloudRunServiceAccount "712966180400-compute@developer.gserviceaccount.com"
```

Create the UID hash salt secret before enabling production export:

```powershell
gcloud.cmd secrets create analytics-uid-hash-salt `
  --project=project-bc878e6c-6f53-4f24-88a `
  --replication-policy=automatic

gcloud.cmd secrets versions add analytics-uid-hash-salt `
  --project=project-bc878e6c-6f53-4f24-88a `
  --data-file=<path-to-random-salt-file>
```

Then set these Cloud Run env vars:

```text
ANALYTICS_BIGQUERY_ENABLED=true
ANALYTICS_BIGQUERY_PROJECT_ID=project-bc878e6c-6f53-4f24-88a
ANALYTICS_BIGQUERY_DATASET=navi_analytics
ANALYTICS_BIGQUERY_TABLE=product_events
ANALYTICS_BIGQUERY_LOCATION=US
ANALYTICS_UID_HASH_SALT_SECRET=analytics-uid-hash-salt
```

## Event Catalog

Current exported frontend event families:

- App/session: `app_started`, `tab_viewed`, `local_test_mode_started`
- Auth: `sign_in_attempted`, `sign_in_succeeded`, `sign_in_failed`,
  `email_sign_in_form_toggled`
- Journal: `journal_loaded`, `journal_load_failed`,
  `journal_save_attempted`, `journal_saved_locally`, `journal_save_failed`,
  `journal_cloud_sync_finished`, `journal_cloud_sync_timeout`,
  `journal_sync_retry_finished`, `journal_features_sync_finished`,
  `journal_features_sync_failed`
- Audio: `audio_loaded`, `audio_load_failed`, `audio_recording_started`,
  `audio_permission_denied`, `audio_recording_start_failed`,
  `audio_saved_locally`, `audio_cloud_sync_finished`,
  `audio_recording_empty`, `audio_recording_save_failed`,
  `audio_sync_retry_finished`, `audio_analysis_started`,
  `audio_analysis_succeeded`, `audio_analysis_failed`, `audio_deleted`
- Insights/today: `insights_loaded`, `insights_backend_failed`,
  `evaluation_feedback_saved`
- Settings and data rights: `settings_saved`, `settings_save_failed`,
  `backend_health_checked`, `data_export_requested`,
  `data_export_succeeded`, `data_export_failed`,
  `account_delete_confirmed`, `account_delete_cancelled`,
  `account_delete_started`, `account_delete_failed`
- Encryption recovery: `encryption_recovery_exported`,
  `encryption_recovery_export_failed`, `encryption_recovery_imported`,
  `encryption_recovery_import_failed`
- Health integrations: `health_tracker_connect_attempted`,
  `health_tracker_connect_url_opened`, `health_tracker_connect_failed`,
  `health_tracker_sync_attempted`, `health_tracker_sync_completed`,
  `health_tracker_sync_failed`
- Notifications: `notification_received_foreground`,
  `notification_opened`, `notification_opened_cold_start`

Backend product events continue to appear in Cloud Logging and are also written
to the same BigQuery table when `ANALYTICS_BIGQUERY_ENABLED=true`.

## Admin Queries

Daily engagement view source:

```text
gcp/bigquery/daily_engagement.sql
```

Useful first checks:

```sql
SELECT event_date, platform, active_users, journal_saves, audio_saves
FROM `project-bc878e6c-6f53-4f24-88a.navi_analytics.daily_engagement`
ORDER BY event_date DESC, platform;
```

```sql
SELECT event_name, COUNT(*) AS events, COUNT(DISTINCT firebase_uid_hash) AS users
FROM `project-bc878e6c-6f53-4f24-88a.navi_analytics.product_events`
WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY event_name
ORDER BY events DESC;
```

```sql
SELECT
  event_date,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'audio_analysis_succeeded'),
    COUNTIF(event_name IN ('audio_analysis_succeeded', 'audio_analysis_failed'))
  ) AS audio_analysis_success_rate
FROM `project-bc878e6c-6f53-4f24-88a.navi_analytics.product_events`
GROUP BY event_date
ORDER BY event_date DESC;
```

## Admin Rules

- Do not add raw journal text, audio paths, transcripts, email addresses, names,
  OAuth tokens, or raw Firebase UIDs to event properties.
- Do not add raw biometric values to product analytics. Use the research feature
  schema and explicit research consent for health-derived data.
- Keep property values primitive: string, number, boolean, or null.
- Keep event names action-oriented and stable.
- Use BigQuery IAM for admin analytics access; do not grant broad project owner
  roles for dashboard users.
- Set table expiration or dataset retention once beta analytics needs are known.
