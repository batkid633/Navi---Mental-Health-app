# Forecast-serving update — November 15, 2026

## Deployment result

Cloud Run project `project-bc878e6c-6f53-4f24-88a`, region `us-central1`, service
`navi-backend` now routes 100% of traffic to `navi-backend-forecast11-20261115`.

Image digest:
`sha256:9632f07ab459b057668c90487bfa9e7f98bb3a62817c1515133ea584a17c54ff`

All runtime template settings were compared with the saved pre-deployment service
and remained identical except the image and revision name. The temporary test tag
was removed when traffic moved. IAM, secrets, environment, networking, scaling,
Firebase configuration and user records were not changed.

## Serving contract

`/predict/tomorrow`, `/predict/trajectory`, and the compatibility route
`/predict/trajectory-v2` call `ml.prediction_service.predict_current`.
The v2 URL is now a compatibility alias, **not** an experimental-v2 model selector.
All return `prediction_contract_version: navi-forecast-1.1` and an artifact-aware
`model_version` ending in `+navi-forecast-1.1`. Tomorrow additionally returns the
LLM narrative. Descriptive journal/body trend charts remain descriptive, not
alternate prediction models.

The retained serving family is the existing next-day estimator plus audited
multimodal trajectory v1. Experimental v2 training remains separate and does not
automatically become the serving model. No model was retrained or activated here.

Included fixes: neutral baseline preservation, calendar-time slope, non-validation
from row count alone, explicit heuristic confidence metadata, and removal of v2
training side effects from prediction/evaluation reads. Tomorrow now reports an
unavailable forecast on prediction failure rather than fabricating a neutral score.

LLM context passes a strict numeric/enum allowlist. Journal prose, transcripts,
feedback notes, and strings substituted into numeric fields are excluded. Cached
insights are keyed by the numeric context and model version; legacy unkeyed cached
narratives are not reused. This is not a migration to Gemini or a new mood target.

## Narrow release packaging

Production's base image was older than the repository and lacked several local
research/biometric-normalization changes. To avoid deploying unrelated work, this
release preserved that image and dependencies, replaced only the three prediction
route functions in its app.py, and overlaid the audited model/LLM helper modules.
All unrelated deployed functions/classes were compared structurally and preserved.

**A full deployment from the repository Dockerfile is NOT equivalent to this
release.** It would also publish unrelated local features. Audit that separately.

Base digest:
`sha256:c52c075947dd59098085b7fcb842391dafecd9377df86c2242315bf6185eb402`

Exact overlay source, build context, source baseline, deployment operation records,
health result and before/after service snapshots are retained locally under
`/Users/cmdb/Documents/navi-toolchain/backend-release-20261114/`. Service snapshots
may contain configuration references and should not be copied into Git.

## Validation and boundaries

- 20 synthetic Python model/contract tests passed inside the exact release image.
- The release image imported the application successfully with networking disabled.
- All three actual route functions returned identical prediction contract fields
  using synthetic predictions and mocked I/O inside the network-isolated image.
- A zero-percent candidate URL returned healthy from `/health` before promotion.
- Deployment metadata confirmed 100% traffic and unchanged runtime configuration.
- No production prediction, journal, audio or research-data endpoints were queried.

The deployed source supports Firestore restoration of per-user feature datasets;
actual persisted records were not read or verified. Revision-local caches/logs
are ephemeral, as they were before this update.

## Scientific limitations and next work

This is a corrective engineering release, not clinical validation or a proven
accuracy improvement. Its target remains journal sentiment, not independently
measured mood. Heuristic adjustments, confidence, residual calibration and model
registry isolation still need work. The existing LLM wording can still overstate
confidence; the added metadata does not itself rewrite every legacy consumer.

Prioritize immutable issue-time forecasts, feedback-to-outcome alignment,
prospective temporal evaluation, calibrated uncertainty and comparisons against
simple baselines before promoting experimental models or claiming holistic mood
validity. No journal text needs to be sent to an LLM for that work.

## Rollback

Previous revision: `navi-backend-00010-nak`. It was retained. A rollback should route
100% traffic back to that revision after checking for subsequent deployment changes;
do not overwrite unrelated runtime configuration. This does not delete user data.
The image and local pre-deployment service snapshot are retained for review.
