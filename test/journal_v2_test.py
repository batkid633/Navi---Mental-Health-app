import unittest
from backend.ml.journal_v2 import exported_journal_days, journal_readiness, train_journal_candidate

class JournalV2Test(unittest.TestCase):
    def test_daily_aggregation_invalid_values_and_calendar_gaps(self):
        records = [{'id': str(i), 'date': day, 'sentimentScore': value, 'text': 'must not leave adapter'}
                   for i, (day, value) in enumerate([('2026-01-01', 0), ('2026-01-01', 1), ('2026-01-02', .2), ('2026-01-04', .3), ('2026-01-05', 9)])]
        frame = exported_journal_days({'format': 'navi-personal-data-export-v1', 'local': {'journalEntries': records}})
        self.assertEqual(list(frame.columns), ['date', 'sentiment_today'])
        report = journal_readiness(frame)
        self.assertEqual(report['consecutive_day_pairs'], 1)
        self.assertAlmostEqual(report['persistence_mae'], .3)
        self.assertFalse(report['training_ready_minimum_pairs'])
        with self.assertRaises(ValueError):
            train_journal_candidate(frame, participant='fixture', features=['Next_day_delta'])

    def test_candidate_uses_journal_target_and_rejects_invalid_labels(self):
        import numpy as np
        import pandas as pd
        frame = pd.DataFrame({'date': pd.date_range('2025-01-01', periods=120),
                              'sentiment_today': np.sin(np.arange(120)/9),
                              'sleep_hours': 7 + np.sin(np.arange(120)/12)})
        candidate = train_journal_candidate(frame, participant='synthetic',
                                            features=['sentiment_today', 'sleep_hours'])
        self.assertEqual(candidate.report['target'], 'next_calendar_day_journal_sentiment')
        future = frame.iloc[-1:].copy()
        future['date'] += pd.Timedelta(days=1)
        self.assertEqual(candidate.forecast(participant='synthetic', frame=future)['target_definition'],
                         'next_calendar_day_journal_sentiment')
        frame['sentiment_today'] = 5
        with self.assertRaises(ValueError):
            train_journal_candidate(frame, participant='synthetic', features=['sentiment_today'])
