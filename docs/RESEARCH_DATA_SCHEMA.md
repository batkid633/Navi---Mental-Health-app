# Navi Research Data Schema

Navi's research data contract is a coded, daily-level feature schema designed
for consented research export. It is separate from product operation, raw app
storage, and product analytics.

Canonical machine-readable schema:

```text
backend/ml/research_daily_feature_schema.json
```

Current schema:

```text
navi_research_daily_features v1.0.0
```

## Scope

This schema contains daily summaries and derived features only. It excludes raw
journal text, raw audio files, transcripts, names, emails, OAuth tokens, raw
Firebase UIDs, and free-text user notes.

The primary research unit is one participant-day:

```text
participant_code + date + schema_version
```

`participant_code` is backend-added from a non-reversible hash prefix. It is a
coded participant identifier, not a raw account id.

## Provenance and Consent Fields

Every research daily feature record should include:

- `schema_name`: stable schema family name.
- `schema_version`: semantic schema version.
- `generated_at`: UTC generation/enrichment time.
- `record_type`: currently `daily_feature_summary`.
- `source_system`: usually `navi_flutter_app`.
- `participant_code`: backend-added coded participant id.
- `consent_scope`: currently `optional_research_sharing`.
- `consent_version`, `privacy_policy_version`, `terms_version`: text versions
  accepted by the participant when available.
- `data_classification`: currently `coded_research_feature`.
- `identifiability`: currently `coded`.
- `raw_text_included`: must be `false`.
- `raw_audio_included`: must be `false`.
- `research_use_allowed`: true only when optional research sharing is enabled.

## Feature Groups

Journal language features:

- `sentiment_today`
- `rolling_mean_7`
- `volatility_7`
- `momentum_7`
- `z_score`
- `is_anomalous`
- `day_of_week`

Biometric features:

- `sleep_hours`
- `sleep_efficiency`
- `resting_hr`
- `hrv_rmssd`
- `recovery_score`
- `strain`

Audio-derived features:

- `audio_session_count`
- `audio_total_seconds`
- `audio_negative_ratio`
- `audio_positive_ratio`
- `audio_anxious_ratio`
- `audio_calm_ratio`
- `audio_training_count`

Typing-rhythm aggregate features:

- `keyboard_session_count`
- `keyboard_event_count`
- `keyboard_chars_estimated`
- `keyboard_backspace_count`
- `keyboard_correction_rate`
- `keyboard_pause_mean_ms`
- `keyboard_pause_std_ms`
- `keyboard_burst_count`
- `keyboard_typing_speed_cpm`
- `keyboard_late_night_ratio`
- `keyboard_platform_web`
- `keyboard_platform_mobile`
- `keyboard_platform_desktop`

Missingness flags:

- `missing_journal`
- `missing_biometrics`
- `missing_audio`
- `missing_keyboard`
- `missing_sleep`
- `missing_hrv`
- `missing_recovery`

Retrospective training target:

- `Next_day_delta`

## Operational Separation

The backend accepts enriched research records at `POST /ml/daily-features`.
Full enriched records are persisted to the durable feature store when available.
The local ML CSV remains numeric/model-safe. It keeps date, derived numeric
features, missingness flags, and retrospective training targets, but excludes
governance/provenance strings and booleans such as `schema_version`,
`consent_version`, `data_classification`, `raw_text_included`, and
`research_use_allowed`.

This prevents consent/provenance metadata from being accidentally used as model
features while preserving numeric multimodal inputs for trajectory modeling and
research exports.

## Product Analytics

Product analytics use a separate schema:

```text
gcp/bigquery/analytics_events_schema.json
```

Those rows are classified as `privacy_safe_product_analytics` and include
`contains_health_content=false`. They may count feature usage, errors, and
workflow events, but they must not contain raw mental health content or biometric
values.

## Research Governance Notes

This schema is research-ready infrastructure, not IRB approval by itself.
Before collecting or analyzing user data for human-subjects research, Navi still
needs a protocol, approved consent language, withdrawal process, data retention
plan, collaborator data-use terms, and IRB approval or written non-research
determination where applicable.
