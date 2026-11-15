"""Pure training helpers: no dataset reads, artifact writes, or network access."""
import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.linear_model import ElasticNet, Ridge
from sklearn.model_selection import GridSearchCV, TimeSeriesSplit
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


def purged_folds(dates, target_dates):
    dates = pd.Series(pd.to_datetime(dates)).reset_index(drop=True)
    targets = pd.Series(pd.to_datetime(target_dates)).reset_index(drop=True)
    if len(dates) != len(targets) or dates.isna().any() or targets.isna().any():
        raise ValueError('Valid issue and outcome dates are required')
    if not dates.is_monotonic_increasing or dates.duplicated().any() or (targets <= dates).any():
        raise ValueError('Unique chronological issue dates and future outcomes are required')
    if len(dates) < 8:
        return []
    folds = []
    for train, validation in TimeSeriesSplit(n_splits=3).split(dates):
        train = train[(targets.iloc[train] < dates.iloc[validation[0]]).to_numpy()]
        if len(train) >= 4 and len(validation) >= 2:
            folds.append((train, validation))
    return folds


def fit_temporal_model(train_x, train_y, dates, target_dates):
    if len(train_x) != len(train_y) or len(train_x) != len(dates):
        raise ValueError('Features, labels and dates must align')
    x = train_x.replace([np.inf, -np.inf], np.nan)
    folds = purged_folds(dates, target_dates)
    pipeline = Pipeline([
        ('impute', SimpleImputer(strategy='median', keep_empty_features=True)),
        ('scale', StandardScaler()),
        ('model', Ridge(alpha=1.0)),
    ])
    # With insufficient temporal evidence, use a fixed regularized baseline;
    # do not substitute shuffled or leave-one-out tuning.
    if len(folds) < 2:
        pipeline.fit(x, train_y)
        pipeline.navi_selection_protocol_ = 'fixed_ridge_insufficient_temporal_folds'
        pipeline.navi_inner_fold_count_ = len(folds)
        return pipeline
    candidates = [{'model': [Ridge()], 'model__alpha': [0.1, 1.0, 10.0, 100.0]}]
    if len(x) >= 30:
        candidates.append({'model': [ElasticNet(max_iter=20000, random_state=42)],
                           'model__alpha': [0.01, 0.1, 1.0],
                           'model__l1_ratio': [0.1, 0.5, 0.9]})
    search = GridSearchCV(pipeline, candidates, cv=folds,
                          scoring='neg_mean_absolute_error', refit=True,
                          n_jobs=1, error_score='raise')
    search.fit(x, train_y)
    model = search.best_estimator_
    model.navi_selection_protocol_ = 'purged_expanding_window_inner_cv_v1'
    model.navi_inner_fold_count_ = len(folds)
    return model
