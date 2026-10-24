# Local cleanup checkpoint — October 24, 2026

WHOOP automatic syncing and the GCP cost item are complete per Cole's confirmation.
No GCP inspection or modification was performed during this checkpoint.

Removed and staged: `clear_hive_locks.sh`, `clear_hive_locks.ps1`. Both targeted
old hard-coded data directories rather than the app's current `Hive.initFlutter()`
storage location, and deleted lock files without coordinating with a running app.
No remaining source reference was found. Byte-preserving copies are stored outside
Git in `/Users/cmdb/Documents/navi-toolchain/retired-scripts-2026-10-24/`.

Deduplicated `.vscode/tasks.json`, retaining one Web and one Windows build task.
Marked `run_dev.sh`, `run_dev.ps1`, and `retrain_model.sh` as legacy standalone
workflows, and corrected obsolete `useWiFi`/`wiFiIP` configuration instructions.
These workflows can contact WHOOP and write training data; none was executed.
The referenced WHOOP utilities, model files, datasets, cloud setup scripts, and
platform/build files were retained. They are not proven disposable.

Validation: shell syntax checked without execution, VS Code task JSON validated,
removal references checked, and Git whitespace checks passed. App code and
production configuration are unchanged by this checkpoint.

Publication remains blocked by historical WHOOP access/refresh-token fields in
commits `7b4bedf`, `a6eec08`, and `c335f66`. The local safety checker still exits
nonzero. Current cleanup does not revoke credentials or erase earlier logs/token
files. No remote inspection, history rewrite, secret rotation, commit, or push
was performed. A separately approved history rewrite and owner credential review
are still needed before declaring existing history safe to publish.

Next priorities: daily beta survey/statistics; audio analysis; journal-first
navigation and insight refresh; audit graph data coverage/sentiment; app icon;
deferred consented research/BigQuery; Gemini; Apple Health read verification.
