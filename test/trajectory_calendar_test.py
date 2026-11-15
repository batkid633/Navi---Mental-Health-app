"""Execute pure functions only; never import backend initialization or read datasets."""
import ast
from pathlib import Path
import unittest
import pandas as pd
import numpy as np

source = Path(__file__).resolve().parents[1] / 'backend/ml/trajectory_v2.py'
tree = ast.parse(source.read_text())
names = {'_build_horizon_frame', '_temporal_holdout'}
namespace = {'pd': pd, 'np': np, 'TARGET_BASE': 'sentiment_today',
             '_ensure_feature_columns': lambda frame: frame.copy()}
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names], type_ignores=[]), str(source), 'exec'), namespace)


class CalendarTargetTest(unittest.TestCase):
    def test_sparse_days_do_not_become_tomorrow(self):
        df = pd.DataFrame({'date': ['2026-01-01', '2026-01-03', '2026-01-04'], 'sentiment_today': [0.1, 0.3, 0.7]})
        result = namespace['_build_horizon_frame'](df, 1)
        self.assertEqual(len(result), 1)
        self.assertEqual(result.iloc[0]['date'], pd.Timestamp('2026-01-03'))
        self.assertAlmostEqual(result.iloc[0]['target_delta_1d'], 0.4)

    def test_seven_days_means_calendar_days(self):
        df = pd.DataFrame({'date': ['2026-01-08', '2026-01-01'], 'sentiment_today': [0.5, -0.2]})
        result = namespace['_build_horizon_frame'](df, 7)
        self.assertEqual(len(result), 1)
        self.assertAlmostEqual(result.iloc[0]['target_delta_7d'], 0.7)

    def test_duplicates_fail_instead_of_choosing_arbitrary_target(self):
        df = pd.DataFrame({'date': ['2026-01-01', '2026-01-01'], 'sentiment_today': [0.1, 0.2]})
        with self.assertRaises(ValueError):
            namespace['_build_horizon_frame'](df, 1)

    def test_missing_invalid_outcomes_are_not_imputed(self):
        df = pd.DataFrame({'date': pd.date_range('2026-01-01', periods=4), 'sentiment_today': [0.1, np.nan, 2, 0.4]})
        self.assertTrue(namespace['_build_horizon_frame'](df, 1).empty)

    def test_training_labels_cannot_overlap_test_period(self):
        df = pd.DataFrame({'date': pd.date_range('2026-01-01', periods=20), 'sentiment_today': np.linspace(-0.5, 0.5, 20)})
        frame = namespace['_build_horizon_frame'](df, 3)
        train, test = namespace['_temporal_holdout'](frame, 10)
        self.assertEqual(len(train), 7)
        self.assertLess(train.target_date.max(), test.date.min())


if __name__ == '__main__':
    unittest.main()
