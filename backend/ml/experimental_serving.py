"""Explicit opt-in experimental serving; bounded fixed Ridge, no registry activation.

Runtime training uses only the authenticated participant's past numeric rows.
This small-data mode is distinct from the evaluated PCA candidate pipeline.
"""
import hashlib
import json
import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

VERSION = 'v2-experimental-ridge-multihorizon-1'
HORIZONS = (1, 3, 7, 14)
FEATURES = ('sentiment_today', 'sleep_hours', 'sleep_efficiency', 'resting_hr',
            'hrv_rmssd', 'recovery_score', 'strain', 'audio_positive_ratio',
            'audio_negative_ratio', 'audio_anxious_ratio', 'audio_calm_ratio',
            'keyboard_correction_rate', 'keyboard_pause_mean_ms', 'keyboard_typing_speed_cpm')

class InsufficientEvidence(ValueError):
    pass


def _predict_horizon(features, history, issue_date, horizon):
    day = pd.Timestamp(issue_date).normalize()
    if pd.isna(day) or day.tz is not None:
        raise InsufficientEvidence('invalid_issue_date')
    if pd.Timestamp(features.get('date')).normalize() != day:
        raise InsufficientEvidence('journal_required_for_requested_day')
    current = pd.to_numeric(pd.Series([features.get('sentiment_today')]), errors='coerce').iloc[0]
    if not np.isfinite(current) or not -1 <= current <= 1:
        raise InsufficientEvidence('current_journal_score_missing')
    if not {'date', 'sentiment_today'}.issubset(history.columns):
        raise InsufficientEvidence('history_missing')
    h = history.copy()
    h['date'] = pd.to_datetime(h.date, errors='coerce').dt.normalize()
    h = h.loc[h.date < day].sort_values('date')
    if h.date.duplicated().any():
        raise InsufficientEvidence('duplicate_dates')
    y = pd.to_numeric(h.sentiment_today, errors='coerce')
    h['sentiment_today'] = y.where(y.between(-1, 1))
    scores = h.set_index('date').sentiment_today
    h['target_date'] = h.date + pd.Timedelta(days=horizon)
    h['target'] = h.target_date.map(scores)
    h = h.loc[h.target_date < day].dropna(subset=['sentiment_today', 'target']).tail(180)
    if len(h) < 6:
        raise InsufficientEvidence('fewer_than_six_prior_calendar_pairs')
    x = h.reindex(columns=FEATURES).apply(pd.to_numeric, errors='coerce').replace([np.inf, -np.inf], np.nan)
    now = pd.DataFrame([features]).reindex(columns=FEATURES).apply(pd.to_numeric, errors='coerce').replace([np.inf, -np.inf], np.nan)
    # Historical availability only; avoid treating zero missing placeholders as data.
    for prefix, flag in [('audio_', 'missing_audio'), ('keyboard_', 'missing_keyboard')]:
        cols = [c for c in FEATURES if c.startswith(prefix)]
        if flag in h:
            x.loc[pd.to_numeric(h[flag], errors='coerce') == 1, cols] = np.nan
        if features.get(flag) == 1:
            now[cols] = np.nan
    cols = [c for c in FEATURES if x[c].notna().sum() >= 6 and x[c].nunique() > 1 and now[c].notna().iloc[0]]
    if 'sentiment_today' not in cols:
        raise InsufficientEvidence('insufficient_journal_variation')
    model = make_pipeline(SimpleImputer(strategy='median'), StandardScaler(), Ridge(alpha=1.))
    model.fit(x[cols], h.target)
    prediction = float(np.clip(model.predict(now[cols])[0], -1, 1))
    fingerprint = hashlib.sha256(pd.util.hash_pandas_object(
        pd.concat([h[['date', 'target']], x[cols]], axis=1), index=False).values.tobytes()).hexdigest()[:16]
    version = f'{VERSION}-h{horizon}-{fingerprint}'
    available = ['journal']
    if any(c in cols for c in FEATURES[1:7]): available.append('biometric')
    if any(c.startswith('audio_') for c in cols): available.append('audio')
    if any(c.startswith('keyboard_') for c in cols): available.append('keyboard')
    prediction_id = hashlib.sha256(json.dumps({'model': version, 'day': str(day.date()), 'features': now[cols].iloc[0].to_dict()}, sort_keys=True).encode()).hexdigest()
    return {'prediction_id': prediction_id, 'predicted_delta': prediction-float(current), 'predicted_mood': prediction,
            'confidence': 0.0, 'confidence_kind': 'unavailable_not_calibrated',
            'uncertainty_kind': 'unavailable', 'trajectory': [], 'horizon_days': horizon,
            'model_version': version, 'model_family': VERSION,
            'primary_model': 'v2', 'experimental': True,
            'target_definition': 'next_calendar_day_journal_sentiment',
            'issue_date': str(day.date()), 'target_date': str((day+pd.Timedelta(days=horizon)).date()),
            'training_pairs': len(h), 'used_features': cols,
            'modality_coverage': {'available_modalities': available, 'coverage_ratio': len(available)/4},
            'validation': {'sample_count': len(h), 'validation_ready': False},
            'insight': f'Experimental {horizon}-day journal sentiment: {prediction:.2f} on a −1 to +1 scale. Based on {len(h)} prior daily pairs. This is not a validated mood assessment; uncertainty is not calibrated.'}


def predict_experimental(features, history, issue_date):
    # Keep the existing primary next-day contract. Longer horizons never borrow
    # the next-day fit or fabricate a forecast when their own pairs are absent.
    primary = _predict_horizon(features, history, issue_date, 1)
    points = []
    for horizon in HORIZONS:
        try:
            result = primary if horizon == 1 else _predict_horizon(features, history, issue_date, horizon)
            points.append({key: result[key] for key in (
                'horizon_days', 'target_date', 'predicted_mood', 'predicted_delta',
                'prediction_id', 'model_version', 'training_pairs', 'used_features',
                'modality_coverage')})
            points[-1].update(status='available', confidence=None, uncertainty=None,
                              uncertainty_kind='unavailable')
        except InsufficientEvidence as exc:
            points.append({'horizon_days': horizon, 'status': 'unavailable',
                           'target_date': str((pd.Timestamp(issue_date).normalize()+pd.Timedelta(days=horizon)).date()),
                           'reason': str(exc), 'predicted_mood': None,
                           'predicted_delta': None, 'confidence': None, 'uncertainty': None})
    primary['trajectory'] = points
    primary['trajectory_target_definition'] = 'journal_sentiment_on_exact_future_calendar_day'
    return primary


def load_personal_history(user_id):
    if not user_id:
        raise InsufficientEvidence('authenticated_user_required')
    try:
        from user_data import user_dataset_path, hydrate_user_dataset_from_firestore
    except ModuleNotFoundError:
        from ..user_data import user_dataset_path, hydrate_user_dataset_from_firestore
    path = user_dataset_path(user_id)
    if not path.exists():
        hydrate_user_dataset_from_firestore(user_id)
    return pd.read_csv(path) if path.exists() else pd.DataFrame()
