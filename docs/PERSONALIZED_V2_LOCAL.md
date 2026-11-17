# Personalized v2: local experimental candidate

Status: implemented as an opt-in Python library, NOT connected to app serving,
NOT trained on personal data, NOT deployed. The existing serving contract remains
unchanged. `backend/ml/personalized_v2.py` is separate from the older
journal-sentiment `trajectory_v2.py` to avoid silently replacing its target.

## What is implemented

- Explicit `IndexContract` and `MetricRule` with version and content fingerprint.
  Each metric has fixed low/high anchors and a direction. Values map linearly to
  [-1,1] with clipping. Equal weights within each domain, then equal domain weights,
  prevent a domain dominating merely because it has more columns. These are
  experimental design choices, not empirically validated mood weights.
- Strict complete-contract coverage for the outcome. Missing metrics yield an
  absent index, never neutral values or silent reweighting. Coverage is returned.
  This may sharply reduce usable days; report that attrition before adopting a
  contract. Missingness can be informative and complete cases may be biased.
- Explicit numeric predictor selection can include context metrics that have no
  defensible positive/negative direction in the index. Raw journal text is not a
  predictor. Unknown columns are not automatically included.
- Per-participant next-calendar-day index forecasting. No imputed outcome labels.
  Explicit participant identities, when present, must match the requested user.
- Train-only median imputation and standardized personal feature scales inside
  chronological purged folds. Ridge/ElasticNet candidates and optional PCA+Ridge;
  PCA is selected only through inner validation. No polynomial feature expansion.
- Chronological 60/20/20 train/calibration/test periods, with overlapping outcome
  dates purged. At least 60 complete daily pairs and split-specific minimums.
  These are engineering thresholds, not evidence of statistical power.
- Absolute calibration residual order statistic for bounded prediction intervals.
  The report includes nominal level, held-out coverage, width and sample counts.
  Temporal dependence and drift mean exchangeability cannot be assumed: NO coverage
  guarantee, Bayesian interpretation or probability-of-correctness claim is made.
- Persistence and trailing-seven-calendar-day baselines on the same test dates.
  Test performance does not automatically activate a candidate.
- Contract fingerprint, candidate/data fingerprint, package versions, split dates
  and feature names for reproducibility. Save configuration and the original
  private input separately; fingerprints cannot reconstruct data.
- Forecast calls reject other participants, historical dates within evaluation,
  and entirely missing predictor rows. They return coverage, target date, index
  version and candidate identity with the forecast.

## Local usage

From the repository root, with the backend Python dependencies installed:

```python
from backend.ml.personalized_v2 import IndexContract, MetricRule, train_candidate

# `daily` is an explicitly prepared, consented, SINGLE-person numeric DataFrame.
# Do not use these arbitrary fixture anchors as real health/mood definitions.
contract = IndexContract('synthetic-demo-only', (
    MetricRule('synthetic_affect', 'affect', -1, 1),
    MetricRule('synthetic_recovery', 'recovery', 0, 100),
))
candidate = train_candidate(
    daily, participant='local-participant', contract=contract,
    features=['synthetic_affect', 'synthetic_recovery'],
)
report = candidate.report
# A later single-day DataFrame, after all evaluation outcomes:
forecast = candidate.forecast(participant='local-participant', frame=later_day)
```

There is no implicit dataset read, network access, registry activation, model
persistence or retraining on import. Keep private exports in an ignored folder
such as `local_research_exports/`; do not commit reports containing personal data.

## Input contract and remaining decisions

Rows must be finalized end-of-local-calendar-day aggregates, sorted by explicit
local date with one row per date. Upstream preparation must enforce units,
provider comparability, consent, measurement availability cutoff and provenance.
Do not insert retrospectively available measurements into historical forecasts.
The library cannot infer these facts from numeric values alone.

Before personal-data training, approve actual domain membership, anchors,
directions, valid physiological ranges and the handling of redundant measures.
In particular, sleep is not necessarily monotonically beneficial, HRV methods
are not interchangeable, and keyboard speed has no established mood direction.
No production scoring formula is invented here. All domains can be considered
as predictors without pretending all metrics have known mood meanings.

Personal scaling and regression weights adapt forecasting, not the target's
meaning. Optional PCA describes feature variation, not causal importance.
Scoring rules remain frozen across model comparisons; changing them requires a
new contract and evaluation. No independent mood criterion is supplied.

Repeat training explicitly with newly available consented observations. Review
candidates on new prospective periods, with stable contracts and rollback, rather
than repeatedly tuning against the same final test. Automatic scheduled learning,
artifact storage, app charts, cloud serving, and model promotion are not included.
An owner export alone supports single-person development, not population claims.

## Validation

Synthetic tests only:

```
python -m unittest discover -s test -p 'personalized_v2_test.py'
python -m unittest discover -s test -p 'temporal_training_test.py'
```

Tests cover scoring/missingness, invalid contracts/dates, insufficient data, text
rejection, temporal split isolation, participant scope, future-only forecasts and
invariance of fitted models/calibration to final-test value changes. Validate
again against deployment-pinned dependencies before any future server release.

## Journal-reference decision (November 15)

The initial participant-facing target is now **next-calendar-day journal
sentiment**, with all eligible observed numeric modalities available as predictors.
Use `backend.ml.journal_v2.train_journal_candidate`, not an invented composite.
The generic index library remains available for explicit future experiments;
there is no approved multi-domain target formula and no automatic serving change.

`JOURNAL_TARGET` fixes the existing [-1,1] scale. The wrapper rejects out-of-range
sentiment rather than clipping it into a valid training label, and allowlists
predictor names to exclude retrospective targets, text and feedback ratings.
Specify the eligible feature subset before evaluation; absent modalities cannot
be presented as having informed the model. Health units/provenance must already
have been verified in upstream preparation. This wrapper does not certify them.

`exported_journal_days` reads only local numeric journal scores and calendar dates
from an already loaded personal export; it does not read text or use cloud logs
as training examples. Same-day scores are averaged; ambiguous duplicate IDs fail.
Dates retain the calendar date written in the export. UTC/local-day equivalence
and edits/availability must be reviewed before treating a retrospective run as
prospective validation. The adapter does not merge cloud duplicates or infer
absent health/audio/keyboard measurements.

Feedback remains separate: helpfulness measures utility, accuracy ratings measure
perceived agreement. Neither is silently mapped to a numerical mood target.
Explicit later mood corrections would require their own target contract, timestamp
alignment, consent and evaluation before training against them.

Private descriptive readiness reports belong under ignored
`local_research_exports/`. A fair v1–v2 comparison requires sufficient eligible
pairs, the frozen v1 artifact and past-only calibration on the same held-out dates.
No v1 winner/loser claim is made from sparse data or existing prediction logs.

## Sparse-history diagnostic

`exploratory_evaluation.walk_forward_journal` permits a separate retrospective
fixed-Ridge diagnostic after six prior eligible pairs. This does NOT lower the
60-pair production candidate gate. Each forecast uses only training outcomes
strictly before its issue day. Compare persistence and past-only mean on exactly
the same dates. Predictor subsets are explicit and allowlisted; all imputation
and scaling is fitted to prior pairs. No PCA selection, calibrated intervals,
automatic activation or deployed-v1 equivalence is claimed. Examining several
variants on these same few dates is exploratory, not independent model selection.
Personal results and figures are kept in ignored `local_research_exports/`.
