"""Small-sample, retrospective diagnostic. Never activates or persists a model."""
import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler


def walk_forward_journal(frame, min_train=6, features=('sentiment_today',)):
    if min_train < 6:
        raise ValueError('At least six prior pairs required for this diagnostic')
    from .journal_v2 import PREDICTORS
    if not features or not set(features).issubset(PREDICTORS):
        raise ValueError('Numeric predictor allowlist required')
    frame = frame[list(dict.fromkeys(['date', 'sentiment_today', *features]))].copy()
    for name in features:
        frame[name] = pd.to_numeric(frame[name], errors='coerce').replace([np.inf, -np.inf], np.nan)
    frame['date'] = pd.to_datetime(frame.date, errors='raise').dt.normalize()
    if frame.date.isna().any() or frame.date.duplicated().any():
        raise ValueError('One valid observation per day required')
    frame = frame.sort_values('date')
    frame['sentiment_today'] = pd.to_numeric(frame.sentiment_today, errors='coerce')
    frame = frame.loc[frame.sentiment_today.between(-1, 1)].copy()
    scores = frame.set_index('date').sentiment_today
    frame['target_date'] = frame.date + pd.Timedelta(days=1)
    frame['target'] = frame.target_date.map(scores)
    pairs = frame.dropna(subset=['target'])
    results = []
    for _, row in pairs.iterrows():
        prior = pairs.loc[pairs.target_date < row.date]
        if len(prior) < min_train:
            continue
        model = make_pipeline(SimpleImputer(strategy='median'), StandardScaler(), Ridge(alpha=1.))
        model.fit(prior[list(features)], prior.target)
        prediction = float(np.clip(model.predict(pd.DataFrame([{name: row[name] for name in features}]))[0], -1, 1))
        results.append({'issue_date': row.date, 'target_date': row.target_date,
                        'last_training_outcome': prior.target_date.max(), 'training_pairs': len(prior),
                        'observed': row.target, 'fixed_ridge': prediction,
                        'persistence': row.sentiment_today,
                        'past_mean': float(scores.loc[scores.index <= row.date].mean())})
    return pd.DataFrame(results)
