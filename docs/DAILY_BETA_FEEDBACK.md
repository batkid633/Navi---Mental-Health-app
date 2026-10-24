# Daily beta feedback

NAVI offers an optional survey on first home-screen use or resume each local
calendar day. Saving or skipping suppresses further prompts that day. Settings →
Daily beta feedback & statistics allows editing today's answer, disabling prompts,
deleting responses, and copying aggregate CSV for charts.

Responses use an account-specific encrypted Hive box on this device. This feature
does not upload responses, query production, or feed the research/BigQuery pipeline.
Survey prompts default on; answers are saved only when the user selects Save locally.
Skipping stores a local day marker. There is no free-text collection.

Version `beta-feedback-1` records ease of use and perceived helpfulness (1–5 or
Not used), plus one issue category. Editing replaces that day's response. Rating
averages exclude Not used and display their own sample counts. Days without a
survey interaction are not counted as skipped days or usage days.

Statistics describe responses from this account/device, not unique participants,
retention, clinical improvement, or efficacy. Aggregate CSV includes schema version,
counts, means and rating distributions, without dates or account identifiers.
Copying to the clipboard is an explicit export; review before sharing. Cohort-wide
statistics and consented uploads remain future work.

Offline tests cover daily prompting, edits, missing ratings, validation, encrypted
persistence, deletion and aggregate export. Device acceptance still requires opening
the updated app, saving a response, checking Settings statistics, reopening the app
the same day, and verifying the disable toggle.
