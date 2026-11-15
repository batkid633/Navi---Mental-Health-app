"""Local-only experimental daily-index forecasting. No IO, training on import or activation.

Inputs must be consented, numeric, end-of-local-day aggregates for ONE participant.
Scoring anchors/directions are an explicit research contract, not learned mood truth.
"""
from dataclasses import dataclass
import hashlib
import json
import math

import numpy as np
import pandas as pd
import sklearn

from .temporal_training import fit_temporal_model


VERSION = 'personalized-index-v2.0-experimental'


@dataclass(frozen=True)
class MetricRule:
    name: str
    domain: str
    low: float
    high: float
    direction: int = 1


@dataclass(frozen=True)
class IndexContract:
    version: str
    rules: tuple

    def __post_init__(self):
        if not self.version or not self.rules:
            raise ValueError('A named, nonempty scoring contract is required')
        names = [r.name for r in self.rules]
        if len(set(names)) != len(names) or 'date' in names:
            raise ValueError('Metric names must be unique and cannot be date')
        for r in self.rules:
            if (not r.name or not r.domain or r.direction not in (-1, 1)
                    or not np.isfinite([r.low, r.high]).all() or r.low >= r.high):
                raise ValueError('Each metric requires finite ordered anchors and a direction')

    @property
    def fingerprint(self):
        payload = {'version': self.version, 'rules': [vars(r) for r in self.rules]}
        return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def _daily(frame):
    frame = frame.copy()
    dates = pd.to_datetime(frame['date'], errors='raise')
    if dates.isna().any() or dates.dt.tz is not None or not dates.eq(dates.dt.normalize()).all():
        raise ValueError('Use explicit timezone-free local calendar dates, one row per day')
    if dates.duplicated().any():
        raise ValueError('Duplicate daily observations require upstream aggregation')
    frame['date'] = dates
    return frame.sort_values('date').reset_index(drop=True)


def score_days(frame, contract):
    """Equal domain weighting, equal metric weighting within domains.

    Anchors map monotonically to [-1,1] with clipping. All contracted metrics must
    be observed for a comparable index. Missing coverage yields no target, not a
    reweighted score. All other available numeric metrics may still be predictors.
    """
    frame = _daily(frame)
    scaled = pd.DataFrame(index=frame.index)
    for rule in contract.rules:
        raw = pd.to_numeric(frame.get(rule.name, pd.Series(np.nan, index=frame.index)), errors='coerce')
        raw = raw.replace([np.inf, -np.inf], np.nan)
        scaled[rule.name] = (2 * (raw - rule.low) / (rule.high - rule.low) - 1).clip(-1, 1) * rule.direction
    domains = sorted({r.domain for r in contract.rules})
    components = pd.DataFrame({d: scaled[[r.name for r in contract.rules if r.domain == d]].mean(axis=1)
                               for d in domains})
    result = pd.DataFrame({'date': frame.date, 'index': components.mean(axis=1),
                           'coverage': scaled.notna().mean(axis=1)})
    result.loc[scaled.isna().any(axis=1), 'index'] = np.nan
    result['contract_hash'] = contract.fingerprint
    return result


def _numeric(frame, features):
    # Only explicitly selected numeric columns enter fitting; never journal text.
    return frame.reindex(columns=features).apply(pd.to_numeric, errors='coerce').replace([np.inf, -np.inf], np.nan)


def _metrics(actual, predicted):
    error = np.asarray(predicted) - np.asarray(actual)
    return {'n': len(error), 'mae': float(np.abs(error).mean()),
            'rmse': float(np.sqrt(np.square(error).mean()))}


@dataclass
class Candidate:
    participant: str
    contract: IndexContract
    features: tuple
    model: object
    radius: float
    evaluated_through: pd.Timestamp
    report: dict

    def forecast(self, *, participant, frame):
        if participant != self.participant:
            raise ValueError('This candidate belongs to a different participant')
        frame = _daily(frame)
        if len(frame) != 1 or frame.date.iloc[0] <= self.evaluated_through:
            raise ValueError('Forecast requires one day later than all evaluated outcomes')
        x = _numeric(frame, self.features)
        if not x.notna().any(axis=1).iloc[0]:
            raise ValueError('No observed predictor measurements')
        point = float(np.clip(self.model.predict(x)[0], -1, 1))
        return {'issued_day': str(frame.date.iloc[0].date()),
                'target_day': str((frame.date.iloc[0] + pd.Timedelta(days=1)).date()),
                'prediction': point, 'interval_low': max(-1., point - self.radius),
                'interval_high': min(1., point + self.radius),
                'observed_features': x.columns[x.notna().iloc[0]].tolist(),
                'contract_hash': self.contract.fingerprint, 'model_version': VERSION,
                'candidate_id': self.report['candidate_id'],
                'target_definition': self.report['target'],
                'uncertainty_kind': 'temporal_residual_interval_no_coverage_guarantee',
                'clinical_validation': False}


def train_candidate(frame, *, participant, contract, features, alpha=0.1):
    """Return an isolated candidate; never write artifacts or change serving routes.

    Chronological 60/20/20 train/calibration/test. Purge overlapping outcome dates.
    Inner temporal CV compares regularization and optional PCA on training only.
    The untouched test measures baselines and empirical interval coverage; it does
    not choose or automatically activate models. Thresholds are engineering gates,
    not sample-size/power claims. The caller must supply one participant only.
    """
    if not participant or not 0 < alpha < 1:
        raise ValueError('Participant key and alpha in (0,1) required')
    features = tuple(features)
    if not features or len(set(features)) != len(features) or 'date' in features:
        raise ValueError('Select unique numeric predictor columns explicitly')
    for identity in ('participant_id', 'user_id'):
        if identity in frame and not frame[identity].eq(participant).all():
            raise ValueError('Mixed or mismatched participant identifiers')
    frame = _daily(frame)
    x = _numeric(frame, features)
    if any(x[c].notna().sum() == 0 for c in features):
        raise ValueError('Exclude entirely missing/non-numeric predictor columns explicitly')
    scores = score_days(frame, contract).set_index('date')['index']
    rows = pd.DataFrame({'date': frame.date})
    rows['target_date'] = rows.date + pd.Timedelta(days=1)
    rows['target'] = rows.target_date.map(scores)
    rows['current'] = rows.date.map(scores)
    rows['trailing'] = rows.date.map(scores.rolling('7D', min_periods=1).mean())
    # Same eligible days for model and baselines; never impute outcome labels.
    rows = rows.loc[rows[['target', 'current']].notna().all(axis=1) & x.notna().any(axis=1)]
    if len(rows) < 60:
        raise ValueError('Insufficient complete daily pairs: require at least 60; no activation')
    n = len(rows)
    train, calibration, test = rows.iloc[:int(n*.6)], rows.iloc[int(n*.6):int(n*.8)], rows.iloc[int(n*.8):]
    train = train.loc[train.target_date < calibration.date.min()]
    calibration = calibration.loc[calibration.target_date < test.date.min()]
    if len(train) < 24 or len(calibration) < 10 or len(test) < 10:
        raise ValueError('Insufficient purged training/calibration/test observations')
    # Feature eligibility cannot be rescued by observing held-out values.
    if x.loc[train.index].notna().sum().eq(0).any():
        raise ValueError('A predictor is entirely missing in training')
    model = fit_temporal_model(x.loc[train.index], train.target, train.date,
                               train.target_date, compare_pca=True)
    cal_pred = np.clip(model.predict(x.loc[calibration.index]), -1, 1)
    residuals = np.sort(np.abs(calibration.target.to_numpy() - cal_pred))
    rank = math.ceil((len(residuals) + 1) * (1 - alpha))
    if rank > len(residuals):
        raise ValueError('Insufficient calibration observations for requested interval level')
    radius = float(residuals[rank - 1])
    pred = np.clip(model.predict(x.loc[test.index]), -1, 1)
    low, high = np.maximum(-1, pred-radius), np.minimum(1, pred+radius)
    candidate_metrics = _metrics(test.target, pred)
    baselines = {'persistence': _metrics(test.target, test.current),
                 'trailing_7_calendar_days': _metrics(test.target, test.trailing)}
    provenance = hashlib.sha256()
    provenance.update(contract.fingerprint.encode())
    provenance.update(json.dumps({'features': features, 'alpha': alpha, 'version': VERSION,
                                  'sklearn': sklearn.__version__}, sort_keys=True).encode())
    provenance.update(pd.util.hash_pandas_object(pd.concat([rows, x.loc[rows.index]], axis=1), index=False).values.tobytes())
    report = {'candidate_id': provenance.hexdigest(),
              'runtime': {'numpy': np.__version__, 'pandas': pd.__version__, 'sklearn': sklearn.__version__},
              'version': VERSION, 'target': 'experimental_multimodal_daily_index',
              'contract_hash': contract.fingerprint, 'features': list(features),
              'split_counts': {'train': len(train), 'calibration': len(calibration), 'test': len(test)},
              'selection': model.navi_selection_protocol_,
              'pca_selected': model.named_steps.get('reduce', 'passthrough') != 'passthrough',
              'test': candidate_metrics, 'baselines': baselines,
              'beats_baselines_mae': all(candidate_metrics['mae'] < b['mae'] for b in baselines.values()),
              'interval': {'nominal_coverage': 1-alpha, 'radius': radius,
                           'test_coverage': float(((test.target >= low) & (test.target <= high)).mean()),
                           'test_mean_width': float((high-low).mean()),
                           'coverage_guaranteed': False,
                           'kind': 'temporal_residual_interval'},
              'clinical_validation': False, 'promotion': 'manual_review_required',
              'score_coverage': float(scores.notna().mean()),
              'split_dates': {name: {'first_issue': str(part.date.min().date()),
                                    'last_outcome': str(part.target_date.max().date())}
                              for name, part in [('train', train), ('calibration', calibration), ('test', test)]}}
    return Candidate(participant, contract, features, model, radius, test.target_date.max(), report)
