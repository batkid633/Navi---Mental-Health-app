# V2 experimental primary and V1 rollback

## Contract

The initial serving mode is `v2-experimental-ridge-1`, distinct from the offline
PCA/model-selection pipeline. It estimates next-calendar-day journal sentiment,
not independently reported mood. The owner explicitly requested experimental V2
as primary despite the lack of validation. Neither V1 nor V2 is represented as
validated, and poor small-sample evaluation results have not been discarded.

The authenticated participant's own history is used; global/synthetic training
data are not substituted. Up to 180 prior valid consecutive-day pairs are used.
All training outcome dates must precede the request day. At least six pairs and
variation in journal sentiment are required. Median imputation and standardization
are fitted only on those prior pairs, then fixed-alpha Ridge is fitted. Eligible
numeric features need six historical observations, variation, and a current value.
Audio/keyboard missing flags exclude placeholder values. This is a bounded
experimental refit, not automatic validation or promotion of a better model.

A current-day journal score is required; stale history never masquerades as today's
measurement. V2 abstention returns explicitly labeled V1 fallback. Full offline
candidate evaluation retains its original minimum and held-out protocol.

V2 produces no calibrated interval or probability. `confidence: 0` is a legacy
transport placeholder with `confidence_kind: unavailable_not_calibrated`, not
measured certainty. Its explanatory text is deterministic; V2 does not call the
LLM. Existing V1 narrative behavior is unchanged when V1 is selected/fallback.

## Shadow and rollback

All three prediction routes use the shared service. Request `model: v1` for rollback
or `model: v2` (default) for the experiment. V2 responses include the same-request
V1 output as `v1_shadow`. V1 still uses its original historical/heuristic logic and
is not an independently validated control. The Today switch persists the selection
on the device. V1 shadow is not separately displayed or rated.

Model fingerprints and V2 prediction IDs distinguish training data and issued
inputs. Today feedback IDs include model version and prediction ID, and V2 feedback
uses the forecast target date. Accuracy/helpfulness remain feedback, not numerical
training labels. No automatic feedback-based fitting was introduced.

The existing per-user JSONL prediction log receives the primary/shadow snapshot.
Those logs remain on the service's existing runtime storage; durability across
instance replacement is NOT guaranteed. This is not a completed prospective
research registry. Durable consented prediction storage and reconciliation remain
separate work. No new research upload, collection or consent is enabled.

## Release boundary

The server update uses the previous exact image as its base and overlays only the
shared prediction service, experimental serving module, request schema and three
route functions. Dependencies, unrelated route bodies, environment configuration,
scaling, secrets, Firebase rules and user records are not changed. Preserve the
previous Cloud Run revision for infrastructure rollback.

Tests exercise synthetic past-only training, stale/insufficient-history abstention,
primary/shadow selection and explicit rollback. Actual route functions are tested
inside the candidate image with network disabled and storage/LLM calls mocked.
Live verification is limited to deployment metadata and `/health`, not user data.
Phone behavior and prediction-linked feedback still require owner confirmation.

## Release result — November 17, 2026

- Active revision: `navi-backend-v2exp-20261117` (100% traffic verified).
- Rollback revision retained: `navi-backend-forecast11-20261115`.
- Image digest: `sha256:c85787c2963a54e71018b5533657ae101c29d06f0db0cd9faa0c3cf2efd85187`.
- Zero-traffic revision health check passed before traffic promotion.
- Compared service template with the pre-release snapshot: only image/revision changed.
- Three synthetic serving tests passed inside the exact release image; all three
  real route functions passed primary/shadow/rollback smoke tests with mocked IO.
  Four existing prediction-contract tests passed locally. Flutter analysis of the
  changed prediction UI/service files reported no issues.
- Release iPhone build installed successfully after Xcode rebuilt the final signed
  artifact. Signature verification passed. Personal Team provisioning expires
  November 22, 2026 at 08:47:39 Eastern.
- Owner must confirm a current-day V2 forecast and feedback on-device. No actual
  production-user prediction endpoint or stored participant records were queried
  during deployment verification. No Git commit/push performed.
