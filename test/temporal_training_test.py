"""Synthetic training only; no backend initialization, datasets or artifact writes."""
import importlib.util
from pathlib import Path
import unittest
import io
import joblib
import numpy as np
import pandas as pd
from sklearn.base import clone

path = Path(__file__).resolve().parents[1] / 'backend/ml/temporal_training.py'
spec = importlib.util.spec_from_file_location('temporal_training', path)
training = importlib.util.module_from_spec(spec)
spec.loader.exec_module(training)


class TemporalTrainingTest(unittest.TestCase):
    def test_every_fold_excludes_overlapping_future_labels(self):
        dates = pd.date_range('2026-01-01', periods=80)
        folds = training.purged_folds(dates, dates + pd.Timedelta(days=7))
        self.assertGreaterEqual(len(folds), 2)
        for train, validation in folds:
            self.assertLess((dates[train] + pd.Timedelta(days=7)).max(), dates[validation].min())
            self.assertFalse(set(train) & set(validation))

    def test_short_history_uses_fixed_regularization(self):
        dates = pd.date_range('2026-01-01', periods=6)
        model = training.fit_temporal_model(pd.DataFrame({'x': [0, 1, np.nan, 3, 4, 5]}), np.arange(6), dates, dates + pd.Timedelta(days=1))
        self.assertEqual(model.navi_selection_protocol_, 'fixed_ridge_insufficient_temporal_folds')
        self.assertTrue(np.isfinite(model.predict(pd.DataFrame({'x': [np.nan]}))).all())

    def test_imputation_and_scaling_stay_inside_cloneable_pipeline(self):
        dates = pd.date_range('2026-01-01', periods=24)
        x = pd.DataFrame({'x': np.arange(24, dtype=float), 'absent': np.nan})
        model = training.fit_temporal_model(x, np.sin(np.arange(24)), dates, dates + pd.Timedelta(days=1))
        self.assertEqual(list(model.named_steps), ['impute', 'scale', 'model'])
        fold = clone(model).fit(x.iloc[:8], np.sin(np.arange(8)))
        self.assertEqual(fold.named_steps['impute'].statistics_[0], 3.5)
        self.assertEqual(fold.named_steps['scale'].mean_[0], 3.5)
        self.assertEqual(fold.predict(x.iloc[-2:]).shape, (2,))
        self.assertEqual(model.navi_selection_protocol_, 'purged_expanding_window_inner_cv_v1')

    def test_unsorted_or_invalid_dates_are_rejected(self):
        dates = pd.to_datetime(['2026-01-02', '2026-01-01'])
        with self.assertRaises(ValueError):
            training.purged_folds(dates, dates + pd.Timedelta(days=1))

    def test_saved_pipeline_accepts_legacy_prefilled_inference(self):
        dates = pd.date_range('2026-01-01', periods=6)
        x = pd.DataFrame({'x': [1., 2., np.nan, 4., 5., 6.], 'missing': np.nan})
        model = training.fit_temporal_model(x, np.arange(6) / 10, dates, dates + pd.Timedelta(days=1))
        buffer = io.BytesIO()
        joblib.dump(model, buffer)
        buffer.seek(0)
        restored = joblib.load(buffer)
        raw = pd.DataFrame({'x': [np.nan], 'missing': [np.nan]})
        prefilled = raw.fillna({'x': 4., 'missing': 0.})
        np.testing.assert_allclose(restored.predict(raw), restored.predict(prefilled))


if __name__ == '__main__':
    unittest.main()
