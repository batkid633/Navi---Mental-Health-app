# Health provider metrics audit

Local source audit: September 12, 2026. No provider APIs, production services,
accounts, or user datasets were queried. These findings describe this checkout,
not verified live provider availability or successful collection on a device.

## Conclusion

NAVI has a shared six-column biometric interface, but it does not currently
collect equivalent measurements across WHOOP, Google, and Apple. Matching
column names is insufficient for pooled comparisons or research graphs.

The UI's “Google Health (Fitbit)” integration uses Google OAuth and
`health.googleapis.com/v4` in `backend/fitbit_api.py`. This is server-side
integration code, not an implemented on-device Android Health Connect reader.
Its live API compatibility and account configuration were not checked.

## Current mappings

| NAVI column | WHOOP adapter | Google adapter | Apple adapter |
| --- | --- | --- | --- |
| `sleep_hours` | Prioritizes time in bed; falls back to total sleep, baseline sleep need, then elapsed interval | Longest qualifying sleep record's minutes asleep / 60 | Sum of `SLEEP_ASLEEP` minutes / 60 |
| `sleep_efficiency` | Efficiency percentage, with sleep performance percentage as fallback | Minutes asleep / minutes in sleep period × 100 | Asleep / in-bed minutes × 100, capped at 100 |
| `resting_hr` | Recovery record's resting heart rate | Daily resting heart rate in beats/minute | Arithmetic mean of resting-heart-rate samples per start date |
| `hrv_rmssd` | Recovery RMSSD field | Average HRV milliseconds, falling back to deep-sleep RMSSD; primary field's measurement definition needs verification | Requests RMSSD, unsupported by installed iOS plugin; plugin exposes SDNN instead |
| `recovery_score` | Recovery score | Null | Omitted |
| `strain` | Maximum of workout and cycle strain per assigned date | Active Zone Minutes / 5, capped at 21 | Omitted |

## Issues to resolve

1. **Sleep definitions differ.** WHOOP time in bed and baseline sleep need must
   not substitute for measured time asleep. Sleep performance must not silently
   substitute for sleep efficiency.
2. **Daily alignment differs.** WHOOP chooses the first available start,
   start-time, creation, update, or end date. Google accepts the requested or
   next civil end date and selects the longest record, which can misassign or
   reuse nights. Apple buckets each sample by start date. Agree on a participant
   timezone and overnight sleep attribution rule before comparing daily rows.
3. **Apple sleep is incomplete.** It requests unspecified asleep and in-bed
   samples, but not core/light, deep, or REM stages. It sums without explicit
   overlapping-interval/source reconciliation. Multiple writers and staged
   sleep require deliberate handling to avoid missing or double-counting sleep.
4. **HRV needs distinct definitions.** The installed health plugin maps iOS to
   `heartRateVariabilitySDNN`; the app requests RMSSD. Preserve a separate SDNN
   field when implementing Apple support; do not relabel it as RMSSD. Verify
   Google's primary HRV field definition before treating it as RMSSD. Even
   matching definitions need sampling-window and aggregation metadata.
5. **Google strain is an app-created proxy.** Store Active Zone Minutes
   separately, with its native unit. It is not a measured WHOOP strain score.
   WHOOP's workout/cycle maximum also needs a deliberate daily-cycle policy.
6. **Provider provenance is lost in the merged features.**
   `_merge_biometric_metrics_into_user_dataset` copies only six biometric
   columns, overwriting non-null values for each date. Google's `source` does
   not become per-metric attribution. A row can silently combine providers and
   retain older values when a later provider returns null. The generic research
   `source_system` does not resolve this.
7. **Missingness is incomplete.** The merge marks `missing_biometrics = 0` for
   every incoming dated row, even if no usable biometric arrives. Null means
   unavailable, not a measured zero or necessarily denied permission.
8. **Apple readiness remains unverified.** Usage descriptions exist, but the
   inspected Runner project has no HealthKit capability configuration. Native
   authorization, signing support, and actual reads are the next task. Its
   current sync method posts to the configured backend; it must not be invoked
   by this local-only audit.

## Proposed consistency contract (not implemented)

- Keep provider-specific observations with metric name, definition, unit,
  source/provider, originating device where available, observation window,
  timezone, aggregation method/version, and collection time.
- Use sleep hours, defined sleep efficiency, and resting heart rate as candidate
  shared metrics after correcting extraction and day alignment. Retain provider
  strata; shared units do not establish measurement equivalence.
- Keep RMSSD and SDNN separate; keep WHOOP recovery/strain and Google activity
  minutes separate. Extend schemas and model inputs explicitly before use.
- Choose an explicit preferred source per metric/day, preserving provenance and
  alternatives. Never silently blend or overwrite conflicting sources.
- Keep missing values null and record reason where known. Distinguish unsupported
  metrics, no samples, unavailable permission information, and sync failures.
- Validate parsers with small synthetic local fixtures: staged/overlapping sleep,
  midnight/timezone boundaries, duplicate sources, nulls, and HRV definitions.
  Do not import backend modules that might initialize cloud clients for an audit.

For beta/venture presentations, show consented participant counts, observed
participant-days, metric coverage, provider mix, and missingness alongside
aggregates. Keep app engagement and user feedback separate from biometric
outcomes; do not present mixed-provider changes as demonstrated clinical benefit.
Research consent and collection verification remain separate pending work.

## Local evidence

- `lib/services/health_tracker_service.dart`: provider labels and routing.
- `lib/services/apple_health_service_io.dart`: requested types and aggregation.
- `backend/whoop_api.py`: `_date_for_record`, `_sleep_hours`, `fetch_daily_metrics`.
- `backend/fitbit_api.py`: `_sync_sleep_metrics`, `_sync_daily_hrv`,
  `_sync_activity_strain_proxy`, `sync_google_health_day`.
- `backend/app.py`: `BIOMETRIC_COLUMNS`,
  `_merge_biometric_metrics_into_user_dataset`.
- `backend/research_schema.py` and
  `backend/ml/research_daily_feature_schema.json`: downstream feature contract.
- Installed local plugin: `ios/.symlinks/plugins/health/lib/src/heath_data_types.dart`
  and `ios/.symlinks/plugins/health/ios/Classes/SwiftHealthPlugin.swift`.
- `ios/Runner/Info.plist` and `ios/Runner.xcodeproj/project.pbxproj`.

Only this audit document was added. No runtime code, dependencies, signing,
production configuration, or stored metrics were changed.

## Follow-up implementation

The comparison above records the pre-fix audit. Local corrections are now
implemented; see `HEALTH_METRIC_NORMALIZATION.md` for the versioned contract,
validation results, rollout limits, and remaining scientific validation work.
