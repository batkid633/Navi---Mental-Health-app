# Local GitHub readiness audit — September 13, 2026

Status: not cleared for public sharing. Local inspection only; no remote/GitHub
access, push, history rewrite, credential rotation, server command, or production
data mutation was performed. License choice has been supplied and implemented in `LICENSE.txt`.

## Findings

1. Historical `navi_ml/tokens/whoop_tokens.json` contains access-token and
   refresh-token fields in local commits `7b4bedf`, `a6eec08`, and `c335f66`.
   Values were not printed. Validity and remote exposure are unknown. Deleting
   the current file or adding an ignore rule does not remove these blobs from
   history. Owner-led credential review and a separately authorized history
   cleanup plan are needed before public release. Do not rewrite history or
   rotate credentials automatically.
2. `.env` appears in local history (`894e728`). The limited assignment-pattern
   scan did not find the selected credential patterns there; this is not proof
   that the historical contents are safe.
3. Tracked runtime logs include `backend/logs/insight_log.jsonl`,
   `backend/logs/llm_insights.jsonl`, and `backend/logs/prediction_log.csv`.
   Existing ignore rules do not untrack them. Treat as sensitive until provenance
   is confirmed. No log contents were printed or removed.
4. Tracked datasets include `backend/data/{daily_features,ml_daily_dataset,
   whoop_daily_metrics}.csv`, `navi_ml/data/daily_features.csv`, and
   `backend/ml/sample_training_data.csv`. Cole Rivell confirmed the tracked CSV datasets are entirely synthetic test
   data. This is owner-reported provenance, not an independent reconstruction. Existing trained `.pkl` artifacts also need
   training-data provenance review; they were not deserialized or executed.
5. Firebase client API-key patterns appear in Android/iOS client configuration
   and `lib/firebase_options.dart`. These are client configuration rather than
   evidence of a leaked service-account private key. Production configuration
   was preserved. No selected private-key/OpenAI/GitHub/AWS token patterns were
   detected in the bounded current-file scan; this is not an exhaustive secret
   audit or validation of Firebase security rules.
6. Added the custom NAVI Personal Noncommercial License at Cole Rivell's
   direction: attributed personal reuse/modification, with commercial use and
   other uses outside the personal grant requiring written permission. It is not
   MIT. Third-party dependency/model/data terms are not overridden.
7. `build/`, Pods, and `.dart_tool/` are not tracked. The open IDE file under
   `build/ios/SourcePackages/` is generated dependency content, not NAVI source.
8. The existing iOS workflow runs on pushes to main and pull requests. It uses a
   floating Flutter selection and a hosted Mac runner. No workflow was run or
   changed during this audit. A manual Git push may trigger this preexisting CI;
   pushing source alone does not verify backend deployment or BigQuery ingestion.
9. Local research edits are unfinished. Static analysis passes, but collection
   tests and device validation remain deferred. They were preserved when the user deferred research work.
   Do not label this working tree a completed research-collection release.

## Changes in this audit

Added ignore rules for local signing keys/profiles and explicit local research
export directories. These rules prevent accidental new additions; they do not
remove already tracked files or history. Added this audit document, `LICENSE.txt`, and a README license notice. No files were
staged, deleted, committed, or pushed.

## Review limits and next decisions

The scan covered tracked and nonignored working files, selected secret patterns,
selected historical paths, tracked generated/data/model paths, and the existing
CI workflow. It did not inspect shared servers or GitHub visibility, scan every
historical blob, execute model files, or verify credential validity. Confirm the
license and data provenance, then prepare a concrete cleanup plan preserving any
needed local data before changing tracking/history. Deleting local research
copies must not delete original journals or production data.

## Validation

Local Flutter static analysis passed for `lib` and `test`. `git diff --check`
passed. No tests were run for the license/documentation-only changes. The working
tree still contains the preserved HealthKit and deferred research implementation
edits; this audit does not certify those unfinished changes for release.

## Cleanup follow-up — September 13, 2026

This section supersedes current-tracking findings above:

- Removed the three `backend/logs/` runtime files from the Git index with
  `git rm --cached`. Their deletions are staged; their local copies remain
  byte-for-byte unchanged (SHA-256 checked) and ignored. Runtime code creates
  missing log directories/files and tolerates absent insight caches. These are
  generated private artifacts, not required source assets. Historical copies
  remain in Git until a separately approved history cleanup.
- Preserved synthetic CSV fixtures, all model artifacts, platform files, lockfiles,
  and Firebase client configuration. References to data/model files were found;
  absence of an obvious import is not evidence that an artifact can be deleted.
  No ignored build caches or local user files were deleted.
- Added missing Dockerfile copies for `biometric_normalization.py`,
  `research_schema.py`, and `research_packets.py`. A static check confirms the
  Dockerfile now includes direct local Python imports of `app.py`. No image was
  built and no container/server was started, so container integration remains
  unverified.
- Expanded backend Docker ignore rules for environment variants, runtime logs,
  user data, credentials, signing files, and research exports. Synthetic `data/`
  fixtures and model assets remain included.
- Removed an explicit Firebase UID/account-scoped filename from a journal debug
  message. Existing functional storage paths and Firebase settings were retained.
- Added `scripts/check_repository_safety.py`, an offline bounded scan that prints
  paths/categories only. It intentionally exits nonzero while known historical
  WHOOP access/refresh-token fields remain. It does not test token validity or
  claim exhaustive history/dependency vulnerability coverage.
- Added five local research privacy regression tests using only synthetic inputs
  and encrypted temporary storage. Research device verification, health-provider
  collection, and BigQuery remain deferred; passing these tests does not complete
  those features.

Validation: 24 existing Flutter tests plus five new privacy tests passed; 11
Python normalization tests passed; Flutter static analysis, Python syntax,
Dockerfile direct-import coverage, and Git whitespace checks passed. No live
provider/API checks, remote security scans, dependency upgrades, new native
build, or installation were performed for this cleanup.

### Remaining publication gate

Current-file cleanup does not revoke historically committed credentials or erase
older private logs. Before publishing existing history, the owner must resolve
credential exposure and approve a history-cleanup approach. No token values were
printed, credentials changed, branches rewritten, commits created, or pushes
performed. Remote visibility and previously distributed copies are unknown.

A concrete potential history-cleanup scope is `.env`,
`navi_ml/tokens/whoop_tokens.json`, and the three runtime-log paths above, across
all intended published refs. Such a rewrite changes commit IDs and may require
coordination/force-pushing by the owner; it needs explicit approval and a local
backup plan before execution. A rewrite alone does not invalidate leaked tokens.
