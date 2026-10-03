# Cloud cost maintenance

## Database retirement (2026-10-03)

The current Flutter app persists account data in Firestore and audio in Firebase
Storage. The Python backend uses Firestore; neither the updated source nor the
deployed backend connects to PostgreSQL. The `dataconnect/` directory is an unused
scaffold, not part of `firebase.json`, and references a different SQL instance.

The redundant `navi-postgresql` instance in
`project-bc878e6c-6f53-4f24-88a` was deleted with a successful final backup:

- Backup: `23e81011-36ba-41c1-a1c8-b0e1b458f934`
- Expiry: **2027-01-01 13:50:27 UTC**
- Find it in Cloud SQL > Backups, including deleted instances, or run
  `gcloud sql backups list --project=project-bc878e6c-6f53-4f24-88a`.
- Restore to a new Cloud SQL instance if needed before expiry. The backup is
  not a running database; restoration incurs database charges again.

This removes roughly $9.37/month of instance and SSD baseline charges at the
previous configuration. Backup storage is still billed until expiry. Actual
invoices, free allowances, and variable usage determine total costs.

## Wearable token retention

After a successful token write, `backend/config.py` performs best-effort cleanup
for `whoop-tokens`, `fitbit-tokens`, and `google-health-tokens` only. It preserves:

- The three newest enabled/disabled versions.
- Versions less than seven days old and versions protected by an alias.
- The newly written version and any concurrent newer version.
- Versions already scheduled for destruction.

Cleanup requires at least a seven-day `version-destroy-ttl`; otherwise it skips
deletion. Older eligible versions are disabled and scheduled for deletion after
that recovery window. Cleanup errors never undo a successfully saved token.
Disabled versions remain billable until destroyed. Cleanup runs on token writes,
not on a separate recurring scheduler.

WHOOP has this recovery window and the backend service account has
`roles/secretmanager.secretVersionManager` and `roles/secretmanager.viewer`
on **that secret only**, in addition to its existing access permissions.
Before enabling another token secret, configure the same delay and secret-scoped
permissions. Do not grant version-destruction permissions across all secrets.

## Monitoring and deployment

Health checks run every five minutes from three US regions. Failure detection can
take longer, but app requests are unaffected. This reduces monitoring requests
by 80%; it need not reduce the bill while usage is within the free allowance.

The infrastructure template now omits SQL provisioning and uses scale-to-zero
with a three-instance maximum. Use the deployment commands in GCP_QUICKSTART.md;
do not reintroduce an always-on SQL instance or warm-instance minimum without a
measured need. Keep the live environment configuration when deploying cost fixes.

The cost deployment is based on the existing production image, with only the
token-retention change patched into its configuration module. It does not deploy
all newly pulled backend changes. A broader local check found an existing failure
in `test_apple_health_sync_merges_user_biometric_daily_rows` (expected sleep hours
`7.25`, observed an empty field), reproduced with the original configuration.
Investigate that separately before deploying the entire updated backend.

Verified production revision: `navi-backend-00010-nak` (retention-only image tag
`retention-20261003`). Rollback revision: `navi-backend-00009-wmc`. Rolling back
the backend does not recreate Cloud SQL. The staged revision passed health,
readiness, and anonymous-access rejection checks before receiving traffic.

Before reinstalling the phone app, confirm that records have synced and that
account encryption/recovery access is available. Uninstalling can remove local
records that were never synced; cloud infrastructure changes do not require an
uninstall.
