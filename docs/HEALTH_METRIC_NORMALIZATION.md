# Biometric normalization 2.0.0

Implemented locally following the September 12, 2026 audit. No server was run,
queried, or deployed; no existing user data was migrated or edited. This is a
reproducibility improvement, not validation of clinical accuracy or equivalence.

## Definitions and extraction

| Field | Unit and rule |
| --- | --- |
| sleep_hours | Hours of measured primary/longest sleep; not time in bed or sleep need |
| sleep_efficiency | Provider efficiency or measured asleep / observed bed or sleep-period duration × 100; denominators remain provider-specific |
| resting_hr | bpm; provider daily RHR or Apple arithmetic mean of RHR samples from one writer |
| hrv_rmssd | ms RMSSD; WHOOP recovery RMSSD or Google's explicitly named deep-sleep RMSSD |
| hrv_sdnn | ms SDNN; Apple mean of SDNN samples, kept separate from RMSSD |
| recovery_score | WHOOP only, 0–100 |
| strain | WHOOP cycle strain only, 0–21; no workout maximum or Google proxy |
| active_zone_minutes | Google's explicit activity total, unscaled; absent/unknown total remains null |

WHOOP sleep sums all three measured light/slow-wave/REM durations, requiring all
three. Longest non-nap measured sleep per local wake date wins, with an ID tie
break. Recovery joins its sleep ID; cycle strain joins the selected sleep's cycle
ID. Missing local timezone offset or missing joins leave values unavailable
rather than assigning them to an upload/creation date. Any WHOOP API section
failure aborts the snapshot instead of replacing stored values with partial data.

Google sleep requires exact civil end date, so tomorrow's sleep cannot be reused
for today. The longest sleep wins with deterministic record ordering for ties.
Unspecified average HRV is no longer assumed to be RMSSD. Activity totals are not
summed with zone subtotals and are never converted to WHOOP strain. The live
Google response contract has not been verified: only explicit fields represented
in local code/fixtures are consumed, and other formats remain missing. The same
live-contract qualification applies to WHOOP parsing fixtures.

Apple requests read access only, including core/light, deep, REM, unspecified
asleep, in-bed, RHR, and SDNN. Manual samples are excluded. Sleep intervals are
unioned per writer to remove overlapping summaries/stages; sessions separated by
more than three hours are distinct. The longest session is assigned to its local
end date. Inconsistent or incomplete in-bed coverage yields null efficiency,
not a clamped number. This session gap is a versioned engineering rule requiring
study validation, not a clinically established sleep definition.

Apple deduplicates samples, selects a single writer per metric deterministically
by source ID, and retains alternative writer summaries and sample counts. Sleep
efficiency uses the same writer as sleep duration. No unique device IDs, raw
sample IDs, or source display names are persisted by this normalizer. It reads two
extra days locally to include overnight sessions, then filters emitted dates to
the requested window. Travel remains a limitation: historical Apple timestamps
are interpreted in the device's timezone at sync, not a stored participant IANA
study timezone. This needs resolution before multi-timezone longitudinal studies.

## Storage and source selection

`backend/biometric_normalization.py` is pure code with no I/O or cloud imports.
It validates finite numeric values against broad engineering bounds. These bounds
are rejection checks, not normative health ranges. Rejected/unreported values
stay null; an observed zero is retained where valid.

The daily dataset retains JSON `biometric_observations` (latest snapshot per
provider, including alternatives/details, units, version, and availability),
`biometric_sources` (selected provider per metric), and
`biometric_normalization_version`. This is not an immutable raw observation
archive: same-provider resync replaces its snapshot, including null values.
Different-provider alternatives remain available.

Selection is deterministic: WHOOP, then Google, then Apple for each compatible
metric. This engineering default prevents sync-order-dependent results; it does
not claim that WHOOP is scientifically superior. Study-specific source selection
and provider-stratified analyses are still needed. A new null snapshot can select
another provider or mark the metric missing. RMSSD missingness remains true when
only SDNN is available. Overall biometric missingness reflects actual valid data.

On an updated day, older unattributed values are retained under `legacy_unknown`
but excluded from normalized metric columns. Historical days are not backfilled
or retrospectively corrected. Research should filter by normalization version;
old and new measurements must not silently be pooled.

The storage schema now retains SDNN, activity minutes, and normalization metadata.
The existing trained-model feature lists are unchanged: SDNN and activity minutes
are not silently introduced into existing models. Journal daily-feature uploads
preserve stored normalized biometrics, including biometric-only days, so they do
not erase attribution. Storage writes are still the existing application paths;
no data writes were executed during this work.

## Validation and limits

Offline fixtures cover measured sleep versus time in bed, local wake-date
assignment, Google next-night exclusion, unknown HRV, zero activity, source-order
independence, missing snapshots, legacy provenance, invalid values, SDNN/RMSSD
separation, CSV persistence, journal upload preservation, staged/overlapping Apple
sleep, writer separation, and invalid efficiency coverage.

Commands (from repository root):

```sh
/opt/anaconda3/bin/python -m unittest discover -s test -p biometric_normalization_test.py
source /Users/cmdb/Documents/navi-toolchain/env.sh
flutter --suppress-analytics analyze --no-pub lib test
flutter --suppress-analytics test --no-pub
```

Python adapter and merge tests extract function definitions via AST, avoiding
application/config startup, credentials, and cloud initialization. CSV writes go
only to a synthetic temporary directory; cloud persistence is replaced by a
local list. This does not replace a future authenticated end-to-end test.

Deployment has not occurred. WHOOP/Google fixes require a separately authorized
backend release to affect the running application; a Git push alone is not proof
of deployment. An old backend may discard Apple's new fields. Do not treat these
local changes as verified live collection. Apple Health signing, native
permissions/device reads, and installation remain the next task.

Before research/venture outcome claims: verify provider contracts against
approved documentation and consented device samples; establish study timezone,
sleep rules, source preference, and reproducibility fixtures; assess measurement
agreement by provider/device; revalidate models against the corrected feature
semantics. Consent enforcement, research schema/versioning, an immutable
observation audit trail, coverage dashboards, and small-cohort privacy protections
belong to the upcoming research task. Existing research export is not thereby
certified deidentified or academically validated.
