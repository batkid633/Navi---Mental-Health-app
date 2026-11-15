# Insights coverage audit — October 31, 2026

Local source-code audit only. No production records, journals, accounts, or APIs
were queried. Audio operation is now confirmed by the user on their iPhone.

## What the metrics actually use

| Output | Input in current source | Limitation |
| --- | --- | --- |
| Journal sentiment / its delta | Journal text sentiment averaged by day | Not a fused mental-health score; wearable/audio data must not be mixed into this scale |
| Volatility / trend slope | Journal sentiment history | Backend uses rolling rows, not necessarily consecutive calendar days |
| HRV series | Backend rolling mean of hrv_rmssd | Seven observations; no source/freshness metadata in the trends response |
| Sleep variability | Backend rolling standard deviation of sleep_hours | Hours, not sleep duration and not mathematical variance despite field name sleep_var |
| Local fallback | Local journal history only | No wearable coverage; fallback is now labeled |
| LLM narrative | Predicted delta, confidence, trajectory, modality list, journal mean/volatility, sleep, HRV, strain, audio counts/ratios | No journal prose, transcript, or semantic interpretation of recorded words |

WHOOP/Google can contribute through existing synchronized backend features. This
audit cannot certify current provider completeness or freshness without data access.
Apple Health remains a local preview pending sample-read verification and wider
pipeline integration; do not describe it as contributing to every insight.

## High sentiment: what can and cannot be concluded

The normal text scorer is NLTK VADER. The Dart offline fallback is a simple word
count and does not understand negation/context (for example, negating a positive
word does not invert it). Different scorers are currently pooled in the graphs.
High sentiment therefore reflects scored wording, not evidence of high well-being.
No personal entries were inspected, so the user's particular high scores are not
explained or validated by this audit. No scores were recalibrated or overwritten.

## Corrections made locally

- Rename mood chart/chips to journal sentiment and explain its modality/scale.
- Preserve missing, non-finite, and out-of-range sentiment as missing, not zero.
- Draw gaps for missing samples; use straight lines to avoid curve overshoot.
- Show returned HRV and sleep-variability series separately with units. The prior
  screen did not render them; an unused older combined chart mixed unlike units.
- Distinguish backend summaries from local journal fallback.
- Clarify that time windows count recorded observations, not guaranteed calendar days.

## Remaining issues before broader beta

- Window unlocks are row-count based; backend and local volatility conventions
  differ. Standardize calendar windows, missingness and standard-deviation rules.
- Backend longitudinal_state maps arbitrary KMeans cluster IDs to labels such as
  Recovering/Declining and writes a shared model file during reads. These are not
  validated interpretations; repair locally and review before any backend deploy.
- UI signal strength is a heuristic based on observation count, body availability
  and low volatility, not statistical confidence or predictive accuracy.
- Add provider timestamps, provenance, missingness and scorer coverage to the API.
- LLM prompt requires a fixed direction/label and limited summary fields, which
  constrains specificity. A separate prompt revision should distinguish observed
  data from forecasts and uncertainty, without uploading private journal prose.

No backend code was deployed or modified. These chart changes require an updated
iPhone build and on-device verification. Local Flutter suite: 54 tests passed;
analysis: four pre-existing style notices. The SDK attempted an automatic version
lookup during the first check; it failed without reaching GitHub. Subsequent checks
used --no-version-check and --no-pub to avoid version/dependency network access.
