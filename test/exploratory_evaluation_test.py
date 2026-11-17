import unittest
import numpy as np
import pandas as pd
from backend.ml.exploratory_evaluation import walk_forward_journal

class ExploratoryTest(unittest.TestCase):
    def test_no_future_outcomes_and_future_changes_do_not_change_earlier_predictions(self):
        f = pd.DataFrame({'date': pd.date_range('2026-01-01', periods=25), 'sentiment_today': np.sin(np.arange(25))})
        a = walk_forward_journal(f)
        self.assertTrue((a.last_training_outcome < a.issue_date).all())
        f.loc[20:, 'sentiment_today'] = .99
        b = walk_forward_journal(f)
        np.testing.assert_allclose(a.fixed_ridge.iloc[:10], b.fixed_ridge.iloc[:10])

    def test_sparse_days_do_not_become_next_day_pairs(self):
        f = pd.DataFrame({'date': pd.date_range('2026-01-01', periods=25, freq='3D'), 'sentiment_today': 0.2})
        self.assertTrue(walk_forward_journal(f).empty)
