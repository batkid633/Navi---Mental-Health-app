"""Synthetic, in-memory examples only; no cloud, private data or model registry."""
import unittest
import numpy as np
import pandas as pd
from backend.ml.personalized_v2 import IndexContract, MetricRule, score_days, train_candidate


class PersonalizedV2Test(unittest.TestCase):
    def setUp(self):
        # Arbitrary test anchors are NOT proposed clinical/production weights.
        self.contract = IndexContract('fixture-only', (
            MetricRule('a', 'journal', -1, 1), MetricRule('b', 'health', 0, 100)))
        t = np.arange(120)
        self.frame = pd.DataFrame({'date': pd.date_range('2025-01-01', periods=120),
                                   'a': np.sin(t/8), 'b': 50+20*np.cos(t/12)})

    def test_domains_balanced_and_missing_never_imputed(self):
        f = pd.DataFrame({'date': pd.date_range('2025-01-01', periods=3),
                          'a': [1, -1, np.nan], 'b': [0, 100, 50]})
        scored = score_days(f, self.contract)
        self.assertEqual(scored['index'].iloc[0], 0)
        self.assertEqual(scored['index'].iloc[1], 0)
        self.assertTrue(np.isnan(scored['index'].iloc[2]))
        self.assertEqual(scored.coverage.iloc[2], .5)

    def test_contract_and_dates_fail_closed(self):
        with self.assertRaises(ValueError):
            IndexContract('bad', (MetricRule('x', 'health', 1, 1),))
        with self.assertRaises(ValueError):
            score_days(pd.concat([self.frame, self.frame]), self.contract)
        changed = IndexContract('fixture-only', (MetricRule('a', 'journal', -2, 1),))
        self.assertNotEqual(changed.fingerprint, self.contract.fingerprint)

    def test_small_data_and_text_predictors_rejected(self):
        with self.assertRaises(ValueError):
            train_candidate(self.frame.iloc[:20], participant='fixture', contract=self.contract, features=['a'])
        self.frame['journal_text'] = 'private words'
        with self.assertRaises(ValueError):
            train_candidate(self.frame, participant='fixture', contract=self.contract, features=['journal_text'])

    def test_temporal_evaluation_and_personal_scope(self):
        c = train_candidate(self.frame, participant='fixture', contract=self.contract, features=['a', 'b'])
        self.assertFalse(c.report['interval']['coverage_guaranteed'])
        self.assertEqual(c.report['promotion'], 'manual_review_required')
        splits = c.report['split_dates']
        self.assertLess(splits['train']['last_outcome'], splits['calibration']['first_issue'])
        self.assertLess(splits['calibration']['last_outcome'], splits['test']['first_issue'])
        future = self.frame.iloc[-1:].copy()
        future['date'] += pd.Timedelta(days=1)
        with self.assertRaises(ValueError):
            c.forecast(participant='other', frame=future)
        with self.assertRaises(ValueError):
            c.forecast(participant='fixture', frame=self.frame.iloc[-1:])
        p = c.forecast(participant='fixture', frame=future)
        self.assertLessEqual(p['interval_low'], p['prediction'])
        self.assertGreaterEqual(p['interval_high'], p['prediction'])
        self.assertEqual(p['contract_hash'], self.contract.fingerprint)

    def test_final_values_cannot_change_fitted_model_or_calibration(self):
        first = train_candidate(self.frame, participant='fixture', contract=self.contract, features=['a', 'b'])
        changed = self.frame.copy()
        changed.loc[105:, ['a', 'b']] = [0.9, 95]
        second = train_candidate(changed, participant='fixture', contract=self.contract, features=['a', 'b'])
        np.testing.assert_allclose(first.model.predict(self.frame[['a', 'b']]), second.model.predict(self.frame[['a', 'b']]))
        self.assertEqual(first.radius, second.radius)


if __name__ == '__main__':
    unittest.main()
