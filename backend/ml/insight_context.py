"""Strict numeric/enum boundary for LLM input; never admit journal prose."""
import math
import hashlib
import json
from numbers import Real

FIELDS = ('predicted_delta', 'confidence', 'rolling_mean_7', 'volatility_7',
          'sleep_hours', 'hrv_rmssd', 'strain', 'audio_session_count',
          'audio_negative_ratio', 'audio_anxious_ratio')


def number(value):
    return float(value) if isinstance(value, Real) and not isinstance(value, bool) and math.isfinite(value) else None


def safe_insight_context(context):
    safe = {key: number(context.get(key)) for key in FIELDS}
    points = context.get('trajectory')
    safe['trajectory'] = [{key: number(point.get(key)) for key in
                          ('horizon_days', 'predicted_mood', 'predicted_delta', 'uncertainty')}
                         for point in (points[:4] if isinstance(points, list) else []) if isinstance(point, dict)]
    coverage = context.get('modality_coverage')
    available = coverage.get('available_modalities', []) if isinstance(coverage, dict) else []
    safe['modality_coverage'] = {'available_modalities': [key for key in ('journal', 'biometric', 'audio', 'keyboard')
                                                        if isinstance(available, list) and key in available]}
    summary = context.get('trajectory_summary')
    direction = summary.get('direction') if isinstance(summary, dict) else None
    safe['trajectory_summary'] = {'direction': direction if direction in ('improving', 'declining', 'variable', 'stable') else 'unknown'}
    return safe


def insight_cache_key(context):
    payload = {'metrics': safe_insight_context(context), 'model_version': context.get('model_version'),
               'prompt_contract': 'numeric_only_1'}
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
