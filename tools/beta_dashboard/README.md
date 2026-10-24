# Local owner feedback dashboard

This is the smallest owner reporting option: a Python standard-library command
generates a standalone HTML dashboard from voluntarily shared NAVI aggregate CSVs.
No server, cloud account, email integration, new dependency, or app update is needed.
It is private through local file access, **not** a deployed owner-authenticated site.

## Collect and view

1. Explain to testers that sharing is optional and that you intend to combine the
   ratings and issue counts for product improvement and presentations. Obtain their
   agreement before including their export. The app's local-save agreement alone
   is not permission to publish their responses.
2. Testers use Settings → Daily beta feedback & statistics → Copy aggregate CSV.
   They can choose a private channel to send that text to you. That channel may
   reveal their identity even though the CSV itself has no account ID or dates.
3. Save plain UTF-8 text as `beta_feedback_private/inputs/source-001.csv`, etc.
   Keep exactly **one latest snapshot per source**. Replace its existing file when
   receiving an update; never append an old and new cumulative export. Use opaque
   source labels, not names or email addresses. Sources aren't verified people.
4. From the repository root run:

   ```sh
   python3 tools/beta_dashboard/report.py --input-dir beta_feedback_private/inputs --output beta_feedback_private/dashboard.html
   ```

5. Open `beta_feedback_private/dashboard.html` in your browser. Print/save as PDF
   for a presentation after reviewing counts and obtaining appropriate permission.
   No browser server is needed. Regenerate after replacing or removing a snapshot.

The private directory is Git-ignored. Do not place real exports elsewhere in the
repository. Keep access restricted on your Mac. The generated report has owner-only
file permissions but anyone you send a copy to can read it. To honor removal, delete
the source file, regenerate, and remove older reports you retain.

## Interpretation and safeguards

- Strict schema and arithmetic checks reject malformed, extra, or incompatible data.
- Identical snapshots are rejected by default to catch duplicate imports. Different
  people can have identical results; use `--allow-identical` only after verifying
  distinct sources. Different overlapping snapshots cannot be detected reliably.
- Means use pooled rating counts, not an average of per-source means. Each metric
  shows its own denominator and missing-rating count. This is response-weighted.
- Counts describe source snapshots and response-days, not verified unique people,
  retention, clinical outcomes, or efficacy. There are no dates to graph trends.
- Reports omit source labels and do not load scripts, external fonts, or analytics.
  Small-group aggregates can still be sensitive; no automatic anonymity guarantee
  or minimum-cell suppression is claimed.
- Automatic uploads, authenticated cloud dashboards, and BigQuery remain deferred.

Tests: `python3 -m unittest discover -s test -p beta_dashboard_test.py`
