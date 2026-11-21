import unittest
import numpy as np
import pandas as pd
from backend.ml.experimental_serving import predict_experimental, InsufficientEvidence
from backend.ml.prediction_service import predict_current

class ExperimentalServingTest(unittest.TestCase):
    def setUp(self):
        self.h = pd.DataFrame({'date': pd.date_range('2026-01-01', periods=30), 'sentiment_today': np.sin(np.arange(30)/4)})
        self.f = {'date': '2026-01-30', 'sentiment_today': .2}

    def test_future_rows_and_current_outcome_cannot_affect_training(self):
        a = predict_experimental(self.f, self.h, '2026-01-30')
        changed = self.h.copy(); changed.loc[29, 'sentiment_today'] = -.99
        b = predict_experimental(self.f, changed, '2026-01-30')
        self.assertEqual(a['predicted_mood'], b['predicted_mood'])
        self.assertEqual(a['model_version'], b['model_version'])
        self.assertEqual(a['target_date'], '2026-01-31')
        self.assertEqual(a['used_features'], ['sentiment_today'])

    def test_stale_or_short_history_abstains(self):
        with self.assertRaises(InsufficientEvidence): predict_experimental(self.f, self.h, '2026-02-01')
        with self.assertRaises(InsufficientEvidence): predict_experimental(self.f, self.h.iloc[:5], '2026-01-30')

    def test_primary_shadow_and_rollback(self):
        kwargs = dict(legacy_predict=lambda f,u: {'model_version':'fixture', 'predicted_delta':.1, 'confidence':.2}, trajectory_predict=lambda f,u,**kw: {})
        result = predict_current(self.f, 'fixture', history_loader=lambda u:self.h, **kwargs)
        self.assertEqual(result['primary_model'], 'v2')
        self.assertEqual(result['v1_shadow']['predicted_delta'], .1)
        old = predict_current(self.f, 'fixture', primary='v1', **kwargs)
        self.assertEqual(old['primary_model'], 'v1')
        fallback = predict_current(self.f, 'fixture', history_loader=lambda u:self.h.iloc[:2], **kwargs)
        self.assertEqual(fallback['selection_reason'], 'v2_unavailable')

    def test_independent_calendar_horizons_have_distinct_pair_counts_and_ids(self):
        result = predict_experimental(self.f, self.h, '2026-01-30')
        points = result['trajectory']
        self.assertEqual([p['horizon_days'] for p in points], [1, 3, 7, 14])
        self.assertEqual([p['training_pairs'] for p in points], [28, 26, 22, 15])
        self.assertEqual(len({p['model_version'] for p in points}), 4)
        for point in points:
            self.assertEqual(pd.Timestamp(point['target_date']), pd.Timestamp('2026-01-30') + pd.Timedelta(days=point['horizon_days']))
            self.assertIsNone(point['uncertainty'])
            self.assertIsNone(point['confidence'])

    def test_short_history_only_withholds_unsupported_horizons(self):
        result = predict_experimental({'date':'2026-01-10', 'sentiment_today':.2}, self.h, '2026-01-10')
        self.assertEqual([p['status'] for p in result['trajectory']], ['available', 'available', 'unavailable', 'unavailable'])
        for point in result['trajectory'][2:]:
            self.assertIsNone(point['predicted_mood'])

    def test_future_values_cannot_change_any_horizon(self):
        original = predict_experimental(self.f, self.h, '2026-01-30')['trajectory']
        altered = self.h.copy()
        altered.loc[29, 'sentiment_today'] = -.99
        self.assertEqual(original, predict_experimental(self.f, altered, '2026-01-30')['trajectory'])

    def test_gaps_do_not_count_as_elapsed_rows(self):
        history = self.h.copy()
        history['date'] = pd.date_range('2026-01-01', periods=30, freq='3D')
        with self.assertRaises(InsufficientEvidence):
            predict_experimental({'date':'2026-04-01', 'sentiment_today':.2}, history, '2026-04-01')
