# Mood-model audit and validation protocol — October 31, 2026

## Scope and owner's decision

Source-code audit and synthetic local unit tests only. No production data access,
training runs, model activation, artifact replacement or deployment. The owner
prefers existing feedback over adding daily self-ratings for now. Journal text
must remain excluded from LLM input; this audit does not change that boundary.

The current target is **future journal sentiment**, not independently measured
mood. Multiple input categories can predict that target, but do not turn it into
a validated holistic mental-health score. The existing code uses regression and
heuristic paths, not Bayesian fusion. Model complexity is not a validity criterion.

## Findings and implemented corrections

| Finding | Action/status |
| --- | --- |
| Forecast horizons used row offsets, mislabeling sparse data as calendar days | Changed v2 target construction to exact date matching; absent outcomes are excluded, never imputed |
| Training labels extended into evaluation dates | Purge training rows whose target date is on/after the evaluation start |
| Duplicate daily dates ambiguously define outcomes | Fail explicitly; require deliberate upstream daily aggregation |
| Missing/out-of-range target values | Exclude rather than silently treating them as neutral |
| Selection results could be mistaken for final validation | New report metadata identifies target, calendar horizon, selection-only metrics and lack of clinical/calibrated validation |

These changes apply to future training with this local source. Existing deployed
artifacts retain their old target construction/evaluation and are not revalidated.
Five synthetic tests cover sparse dates, calendar horizons, duplicate dates,
invalid outcomes, and exclusion of overlapping training-label dates.

## Existing feedback: appropriate uses

EvaluationFeedback stores targetType, targetDate (sometimes an entry ID rather
than a calendar date), journalEntryId, predictedDelta, confidence, modelVersion,
accuracyRating, helpfulnessRating, actualMoodDirection, notes and timestamps.
The visible shared feedback card collects accuracy/helpfulness judgments; field
existence alone does not prove actualMoodDirection is consistently populated.

| Feedback | Appropriate role | Do not do |
| --- | --- | --- |
| Accurate / partly / inaccurate | User-perceived agreement, separated by target type and model version | Convert directly into a −1 to +1 mood label |
| Helpful / neutral / unhelpful | Product usefulness and narrative evaluation | Treat usefulness as forecast correctness or well-being |
| Actual mood direction, if explicitly collected after the forecast outcome | Separate directional evaluation after validating target date/horizon | Treat direction as an absolute mood magnitude |
| Free-text note / journal text | Keep private; outside numeric LLM features | Send to LLM or silently use as training labels |

Feedback is optional and influenced by seeing the prediction. Report response
counts and missingness; do not treat nonresponse as neutral or positive. Store
immutable forecast issue-time snapshots before introducing learning from feedback.
An edited response must not retroactively become an earlier training observation.
No automatic feedback training or reinterpretation of existing responses was added.

## Required evaluation design before model promotion

1. Freeze outcome, horizon, prediction issue time, available-input cutoff, eligible
   records, and exclusion rules before comparing models. Keep synthetic fixtures
   separate from real participant evaluation.
2. Construct one calendar-day row per person with units, provider source, collection
   timestamps, missingness and scorer version. Never backfill future measurements.
3. Use chronological expanding-window outer evaluation. Within each outer training
   period, use purged chronological folds for model/feature selection. Fit imputation,
   scaling and tuning separately inside every fold. Reserve a final untouched period.
4. Compare against persistence (zero change), trailing historical mean and journal-only
   baselines. Evaluate added value of audio, health and keyboard via prespecified
   ablations; do not require uninformative modalities just to claim full integration.
5. Report MAE/RMSE with n per horizon/person and error distributions. Quantify uncertainty
   using temporal blocks rather than independent-row resampling. Do not claim generality
   from one owner or treat multiple days as independent participants.
6. Evaluate interval coverage/width on held-out periods before displaying intervals as
   calibrated. Existing RMSE and MAE-derived confidence are not posterior probabilities.
7. Shadow-evaluate frozen candidates prospectively; activate only after documented
   baseline improvement, coverage, stability, and review. Retain rollback artifacts.

## Unresolved blockers to strong scientific claims

- Addressed locally in the subsequent training update: Ridge/ElasticNet selection
  now uses purged expanding-window inner folds, with imputation/scaling inside each
  fold. Insufficient folds use fixed Ridge regularization, not shuffled tuning.
- Addressed locally: the final chronological 20% is reserved before ablation
  selection. Development outcomes overlapping that period are removed. The selected
  candidate is evaluated once on that period, separately under `final_test`.
  Existing artifact reports still contain the old optimistic selection estimates.
- Registries/model files are shared paths rather than clearly isolated personal vs
  cohort artifacts; inference can trigger training/activation when artifacts are absent.
- Median-filled missing modalities, especially all-missing feature groups, can produce
  predictions without evidence that those modalities informed them.
- Confidence is an ad hoc MAE transformation; uncertainty uses RMSE, not a validated
  individual prediction interval. Clipping to −1..1 does not establish calibration.
- VADER and lexical fallback sentiment are pooled despite different error behavior.
- Acoustic fallback mood is heuristic; keyboard measurements can reflect device,
  language and typing context. They are candidate correlates, not mood ground truth.
- Arbitrary KMeans cluster IDs receive clinical-sounding direction/state labels.
- No independent mood criterion has been selected. Current claims must remain about
  journal-sentiment forecasts and user-rated utility, not clinical mood classification.

## Graph specification

Keep observed journal sentiment and forecasts visually distinct on calendar dates.
Plot a forecast at its issue date plus its exact horizon; retain issue time, model
version and available modalities. Do not connect absent observations as measured
values, manufacture an overall mood label, or render RMSE as a Bayesian credible
interval. A historical forecast-vs-observation graph requires immutable predictions;
recomputing today's model on old dates is not historical prospective performance.

The next implementation stage is explicit forecast/feedback alignment, temporal
uncertainty calibration and prospective validation. No new daily mood survey is
required by this plan.

## Local training update

The code now separates inner tuning, ablation selection on development data, and
the reserved final period. The saved selected model remains fitted only to its
development training segment; final observations never update it. A repeated run
that is adapted after viewing final results would compromise that holdout; a future
prospective period is needed for subsequent decisions.

No production or existing personal model was retrained or replaced. Synthetic tests
exercise temporal purging, small-sample fallback, fold-specific preprocessing and
serialized-model inference compatibility. Local tests used scikit-learn 1.9.0;
backend requirements remain pinned to 1.7.2 and were not upgraded. Validation in the
exact deployment environment remains required before release.

## November 14 follow-up: serving path and inference safeguards

Today calls `/predict/tomorrow`, which blends the legacy next-day estimator with
trajectory v1. V2 is a separate endpoint; its training changes do not automatically
replace Today's model. No serving-path migration has been performed.

Local v1 fixes preserve a measured zero sentiment baseline instead of substituting
the latest historical score, calculate trend per elapsed calendar day, and restrict
persistence comparisons to consecutive calendar dates. Thirty rows no longer cause
`validation_ready: true`: that calculation is descriptive baseline evaluation only.
Missing baselines with no usable historical fallback raise an error rather than
fabricating neutral sentiment. An existing valid historical fallback remains.

V1 adds explicit metadata labeling its confidence and uncertainty as uncalibrated
heuristic quantities. The Today trajectory strip displays a model score instead of
a percentage and explains it is not probability of correctness. This is not a new
calibration method, and other legacy confidence consumers still require review.

V2 prediction/evaluation reads now raise a clear missing-artifact error rather than
training or activating a model as a side effect. Explicit training remains separate;
registry isolation and activation policy still need improvement.

Six additional synthetic tests cover neutral baseline preservation, missing-baseline
abstention, calendar slope, non-validation from row counts, gaps in persistence
pairs, and no training from v2 reads. No existing datasets, artifacts or production
services were accessed. These backend edits require later deployment before affecting
the phone's server-generated predictions; UI installation is also pending.
