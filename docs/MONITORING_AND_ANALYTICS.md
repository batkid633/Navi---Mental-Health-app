# Monitoring and Analytics

Navi uses two lightweight production signals:

1. GCP operational monitoring for backend health.
2. Firebase user-scoped product analytics for app behavior.
3. Optional BigQuery ingestion for admin product analytics.

## Backend Monitoring

The FastAPI backend emits structured JSON logs to stdout. On Cloud Run, these
logs automatically appear in Google Cloud Logging.

Logged backend fields include:

- request ID
- HTTP method
- route path
- status code
- duration in milliseconds
- service name and version
- privacy-safe product events

The backend also exposes:

- `/health` for uptime checks
- `/ready` for dependency readiness
- `/monitoring/summary` for aggregate runtime counters

In production, `/monitoring/summary` requires the signed-in Firebase user ID to
be listed in `MONITORING_ACCESS_UIDS`.

Recommended GCP setup:

- Create Cloud Monitoring uptime checks against `/health`.
- Create log-based metrics for `status_code >= 500`.
- Create log-based metrics for `message="product_event"`.
- Add alerts for elevated 5xx errors, high latency, and repeated timeouts.
- Add budget alerts for beta cloud spend.
- Validate Firebase Crashlytics before physical-device beta testing.

Starter monitoring assets now live in `gcp/monitoring/`, with setup notes in
`docs/GCP_MONITORING_SETUP.md`.

## Frontend Product Analytics

The Flutter app writes privacy-safe analytics under each user's Firestore record:

- `users/{uid}/analytics_events`
- `users/{uid}/daily_analytics`

Events intentionally do not include journal text, audio files, transcripts,
raw notes, or personally identifying metadata beyond the authenticated user
document they already belong to.

Tracked examples:

- sign-in attempted/succeeded/failed
- journal loaded/saved/synced
- audio recording saved/analyzed
- insights loaded from backend or local fallback
- settings saved
- data export/delete requested
- backend health checked

## Grant-Useful Metrics

The most useful early product metrics are:

- successful sign-ins
- journal saves per active user
- cloud sync success/failure rate
- audio recordings saved
- audio analysis success/failure rate
- insight page load success/fallback rate
- backend health latency
- 4xx/5xx API error rates

These metrics show whether the product is usable and reliable without turning
sensitive mental health content into analytics data.

## BigQuery Warehouse

For aggregate admin analysis, the Flutter app also sends the same privacy-safe
events to `POST /analytics/events`. When `ANALYTICS_BIGQUERY_ENABLED=true`, the
backend writes normalized rows to BigQuery. See `docs/BIGQUERY_ANALYTICS.md` for
the schema, setup script, event catalog, and starter queries.
