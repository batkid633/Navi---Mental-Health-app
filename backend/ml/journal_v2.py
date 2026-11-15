"""Local journal-reference v2. Never reads files, sends text, or activates models."""
import numpy as np
import pandas as pd
from .personalized_v2 import IndexContract, MetricRule, train_candidate

JOURNAL_TARGET = IndexContract('journal-sentiment-reference-v2.1', (
    MetricRule('sentiment_today', 'journal_language', -1, 1),
))
# Explicit allowlist excludes text, identifiers, feedback ratings and future labels.
PREDICTORS = ('sentiment_today', 'sleep_hours', 'sleep_efficiency', 'resting_hr',
              'hrv_rmssd', 'recovery_score', 'strain', 'audio_session_count',
              'audio_positive_ratio', 'audio_negative_ratio', 'audio_anxious_ratio',
              'audio_calm_ratio', 'keyboard_session_count', 'keyboard_correction_rate',
              'keyboard_pause_mean_ms', 'keyboard_typing_speed_cpm')


def train_journal_candidate(frame, *, participant, features):
    if not set(features).issubset(PREDICTORS):
        raise ValueError('Only approved numeric predictor names are supported')
    values = pd.to_numeric(frame['sentiment_today'], errors='coerce')
    frame = frame.copy()
    frame['sentiment_today'] = values.where(values.between(-1, 1))
    candidate = train_candidate(frame, participant=participant, contract=JOURNAL_TARGET, features=features)
    candidate.report['target'] = 'next_calendar_day_journal_sentiment'
    candidate.report['feedback_training'] = 'disabled_ratings_are_not_mood_labels'
    return candidate


def exported_journal_days(export):
    """Use numeric local entries only; preserve written calendar date, not UTC shift.

    No cloud/local merging: duplication and source conflicts require explicit review.
    Export timestamps/edits do not establish historical prediction-time availability.
    """
    if export.get('format') != 'navi-personal-data-export-v1':
        raise ValueError('Unsupported personal export')
    rows = []
    seen = set()
    for entry in export.get('local', {}).get('journalEntries', []):
        identity = entry.get('id')
        if not identity or identity in seen:
            raise ValueError('Missing/duplicate journal identity requires review')
        seen.add(identity)
        value = entry.get('sentimentScore')
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not np.isfinite(value) or not -1 <= value <= 1:
            continue
        day = pd.to_datetime(str(entry.get('date', ''))[:10], format='%Y-%m-%d', errors='coerce')
        if pd.notna(day):
            rows.append({'date': day, 'sentiment_today': value})
    if not rows:
        return pd.DataFrame(columns=['date', 'sentiment_today'])
    return pd.DataFrame(rows).groupby('date', as_index=False).sentiment_today.mean()


def journal_readiness(frame):
    scores = frame.set_index('date').sentiment_today.sort_index()
    tomorrow = scores.reindex(scores.index + pd.Timedelta(days=1)).to_numpy()
    paired = np.isfinite(tomorrow) & scores.notna().to_numpy()
    error = scores.to_numpy()[paired] - tomorrow[paired]
    return {'daily_observations': len(scores), 'consecutive_day_pairs': int(paired.sum()),
            'mean_journal_sentiment': float(scores.mean()) if len(scores) else None,
            'persistence_mae': float(np.abs(error).mean()) if len(error) else None,
            'training_ready_minimum_pairs': bool(paired.sum() >= 60),
            'comparison_status': 'not_run_requires_eligible_data_and_frozen_v1_reference',
            'interpretation': 'descriptive_journal_only_not_mood_validation'}
