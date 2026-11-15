"""Pure source functions with synthetic fixtures; no datasets, model I/O or cloud."""
import ast
import math
from pathlib import Path
from types import SimpleNamespace
from typing import Any
import unittest
import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression

ROOT = Path(__file__).resolve().parents[1]

def functions(path, names, namespace):
    tree = ast.parse(path.read_text())
    nodes = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(path), 'exec'), namespace)
    return namespace

ctx = functions(ROOT / 'backend/ml/trajectory_model.py',
    {'_num', '_clip_sentiment', '_safe_std', '_recent_trend', '_components', '_validation_diagnostics'},
    {'math': math, 'np': np, 'pd': pd, 'Any': Any, 'LinearRegression': LinearRegression,
     'SENTIMENT': 'sentiment_today', 'TARGET': 'Next_day_delta', 'TrajectoryComponents': SimpleNamespace,
     '_biometric_adjustment': lambda *a: 0, '_audio_adjustment': lambda *a: 0,
     '_keyboard_adjustment': lambda *a: 0})

class InferenceSafetyTest(unittest.TestCase):
    def test_neutral_is_not_replaced_by_positive_history(self):
        history = pd.DataFrame({'date': pd.date_range('2026-01-01', periods=4), 'sentiment_today': [0.8]*4})
        result = ctx['_components']({'sentiment_today': 0.0}, history)
        self.assertEqual(result.baseline, 0.0)

    def test_missing_baseline_and_history_abstains(self):
        with self.assertRaises(ValueError):
            ctx['_components']({}, pd.DataFrame())

    def test_trend_is_per_calendar_day_not_per_observation(self):
        history = pd.DataFrame({'date': pd.to_datetime(['2026-01-01', '2026-01-11', '2026-01-21']), 'sentiment_today': [0.0, 0.1, 0.2]})
        slope, _ = ctx['_recent_trend'](history, {})
        self.assertAlmostEqual(slope, 0.01)

    def test_thirty_rows_do_not_claim_validation(self):
        history = pd.DataFrame({'date': pd.date_range('2026-01-01', periods=35), 'sentiment_today': [0.2]*35})
        result = ctx['_validation_diagnostics'](history)
        self.assertFalse(result['validation_ready'])
        self.assertEqual(result['paired_day_count'], 34)

    def test_gaps_are_not_next_day_baseline_pairs(self):
        history = pd.DataFrame({'date': pd.date_range('2026-01-01', periods=6, freq='3D'), 'sentiment_today': [0.2]*6})
        result = ctx['_validation_diagnostics'](history)
        self.assertFalse(result['validation_ready'])
        self.assertNotIn('persistence_baseline_mae', result)

    def test_v2_reads_never_train_when_artifacts_are_absent(self):
        local = functions(ROOT / 'backend/ml/trajectory_v2.py', {'predict_trajectory_v2', 'evaluate_trajectory_v2'},
            {'Any': Any, 'load_active_report': lambda: None,
             'train_trajectory_v2': lambda **kw: self.fail('Read attempted training')})
        with self.assertRaises(ValueError):
            local['predict_trajectory_v2']({})
        with self.assertRaises(ValueError):
            local['evaluate_trajectory_v2']()

if __name__ == '__main__':
    unittest.main()
