"""Offline fixtures only. Adapter functions are extracted without module startup."""
import ast
import json
import math
from datetime import datetime, timedelta, timezone
from pathlib import Path
import unittest
from backend.biometric_normalization import merge_day

ROOT = Path(__file__).resolve().parents[1]


def functions(path, names, **globals_):
    tree = ast.parse((ROOT / path).read_text())
    definitions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
    scope = dict(datetime=datetime, timedelta=timedelta, timezone=timezone, math=math, json=json, **globals_)
    exec(compile(ast.Module(body=definitions, type_ignores=[]), path, 'exec'), scope)
    return scope


class NormalizationTest(unittest.TestCase):
    def row(self, source, **values):
        return dict(source=source, normalization_version='2.0.0', **values)

    def test_selection_independent_of_sync_order_and_retains_alternatives(self):
        whoop = self.row('whoop', resting_hr=55, strain=12)
        google = self.row('google_health', resting_hr=62, active_zone_minutes=0, strain=20)
        a = merge_day(merge_day({}, whoop), google)
        b = merge_day(merge_day({}, google), whoop)
        self.assertEqual(a, b)
        self.assertEqual(a['resting_hr'], 55)
        self.assertEqual(a['strain'], 12)
        self.assertEqual(a['active_zone_minutes'], 0)
        self.assertEqual(json.loads(a['biometric_observations'])['google_health']['values']['resting_hr'], 62)

    def test_null_invalidates_same_source_and_missing_flags(self):
        a = merge_day({}, self.row('whoop', hrv_rmssd=40))
        b = merge_day(a, self.row('whoop', hrv_rmssd=None))
        self.assertIsNone(b['hrv_rmssd'])
        self.assertEqual(b['missing_biometrics'], 1)
        self.assertEqual(b['missing_hrv'], 1)

    def test_sdnn_is_not_rmssd_and_invalid_numbers_are_missing(self):
        a = merge_day({}, self.row('apple_health', hrv_sdnn=42, hrv_rmssd=42,
                                  resting_hr=float('nan'), sleep_efficiency=101))
        self.assertEqual(a['hrv_sdnn'], 42)
        self.assertIsNone(a['hrv_rmssd'])
        self.assertIsNone(a['resting_hr'])
        self.assertIsNone(a['sleep_efficiency'])
        self.assertEqual(a['missing_hrv'], 1)

    def test_legacy_values_retained_but_not_claimed_normalized(self):
        a = merge_day({'sleep_hours': 9}, self.row('apple_health', resting_hr=60))
        self.assertIsNone(a['sleep_hours'])
        self.assertEqual(json.loads(a['biometric_observations'])['legacy_unknown']['values']['sleep_hours'], 9)

    def test_whoop_measured_sleep_and_local_end_date(self):
        f = functions('backend/whoop_api.py', {'_nested_num', '_sleep_hours', '_sleep_date'})
        self.assertIsNone(f['_sleep_hours']({'score': {'stage_summary': {'total_in_bed_time_milli': 36000000}}}))
        record = {'end': '2026-09-12T02:00:00Z', 'timezone_offset': '-04:00', 'score': {'stage_summary': {
            'total_light_sleep_time_milli': 4*3600000, 'total_slow_wave_sleep_time_milli': 3600000,
            'total_rem_sleep_time_milli': 2*3600000}}}
        self.assertEqual(f['_sleep_hours'](record), 7)
        self.assertEqual(f['_sleep_date'](record), '2026-09-11')
        self.assertIsNone(f['_sleep_date']({'end': record['end']}))

    def test_google_does_not_reuse_next_night(self):
        records = [{'sleep': {'interval': {'civilEndTime': {'date': {'year': 2026, 'month': 9, 'day': day}}},
                             'summary': {'minutesAsleep': mins, 'minutesInSleepPeriod': 600}}}
                   for day, mins in [(12, 420), (13, 540)]]
        f = functions('backend/fitbit_api.py', {'_sync_sleep_metrics'},
                      _reconcile_points=lambda *a: records, _to_float=lambda v: float(v) if v is not None else None)
        self.assertEqual(f['_sync_sleep_metrics']('2026-09-12'), (7, 70))

    def test_google_unknown_hrv_and_zero_activity(self):
        f = functions('backend/fitbit_api.py', {'_sync_daily_hrv', '_sync_active_zone_minutes'},
                      _list_points=lambda *a: [], _first_matching_daily=lambda *a: {'averageHeartRateVariabilityMilliseconds': 40},
                      _to_float=lambda v: float(v) if v is not None else None,
                      _daily_rollup=lambda *a: [{'activeZoneMinutes': {'activeZoneMinutesSum': 0, 'vigorousSum': 50}}])
        self.assertIsNone(f['_sync_daily_hrv']('2026-09-12'))
        self.assertEqual(f['_sync_active_zone_minutes']('2026-09-12'), 0)



class DatasetIntegrationTest(unittest.TestCase):
    def test_csv_roundtrip_preserves_sources_without_any_cloud_imports(self):
        import tempfile
        import pandas as pd
        from backend.research_schema import model_dataset_frame
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'features.csv'
            persisted = []
            f = functions('backend/app.py', {'_merge_biometric_metrics_into_user_dataset'},
                          pd=pd, BACKEND_DIR=Path(tmp), user_dataset_path=lambda _: path,
                          user_daily_features_path=lambda _: Path(tmp) / 'daily.csv',
                          BIOMETRIC_COLUMNS=list(__import__('backend.biometric_normalization', fromlist=['LIMITS']).LIMITS),
                          merge_day=merge_day, model_dataset_frame=model_dataset_frame,
                          persist_user_feature_records=lambda _, rows: persisted.extend(rows) or len(rows))
            merge = f['_merge_biometric_metrics_into_user_dataset']
            merge('fixture', [dict(date='2026-09-12', source='whoop', normalization_version='2.0.0', resting_hr=55)])
            merge('fixture', [dict(date='2026-09-12', source='apple_health', normalization_version='2.0.0', resting_hr=65, hrv_sdnn=40)])
            row = pd.read_csv(path).iloc[0]
            self.assertEqual(row['resting_hr'], 55)
            self.assertEqual(row['hrv_sdnn'], 40)
            self.assertEqual(json.loads(row['biometric_sources'])['resting_hr'], 'whoop')
            self.assertIn('apple_health', json.loads(persisted[-1]['biometric_observations']))


class PreservationTest(unittest.TestCase):
    def test_journal_upload_cannot_erase_provider_observations(self):
        from backend.biometric_normalization import preserve_biometrics
        prior = merge_day({}, dict(source='whoop', normalization_version='2.0.0', resting_hr=55))
        prior['date'] = '2026-09-12'
        rows = preserve_biometrics([dict(date='2026-09-12', resting_hr=None, sentiment_today=0.5)], [prior])
        self.assertEqual(rows[0]['resting_hr'], 55)
        self.assertEqual(rows[0]['sentiment_today'], 0.5)
        self.assertEqual(preserve_biometrics([], [prior]), [prior])


class AdapterIntegrationTest(unittest.TestCase):
    def test_whoop_joins_recovery_and_cycle_not_record_creation_date(self):
        sleep = {'id': 'sleep', 'cycle_id': 1, 'end': '2026-09-12T12:00:00Z',
                 'timezone_offset': '-04:00', 'score': {'stage_summary': {
                     'total_light_sleep_time_milli': 4*3600000,
                     'total_slow_wave_sleep_time_milli': 3600000,
                     'total_rem_sleep_time_milli': 2*3600000}}}
        payloads = {'/activity/sleep': [sleep], '/recovery': [
            {'sleep_id': 'sleep', 'created_at': '2026-09-13T12:00:00Z',
             'score': {'hrv_rmssd_milli': 50, 'resting_heart_rate': 55, 'recovery_score': 75}}],
            '/cycle': [{'id': 1, 'score': {'strain': 12}}]}
        f = functions('backend/whoop_api.py', {'_sleep_hours', '_sleep_date', '_nested_num', '_upsert_metric', 'fetch_daily_metrics'},
                      _whoop_get=lambda route, params: payloads[route])
        row = f['fetch_daily_metrics']()[0]
        self.assertEqual(row['date'], '2026-09-12')
        self.assertEqual(row['sleep_hours'], 7)
        self.assertEqual(row['hrv_rmssd'], 50)
        self.assertEqual(row['strain'], 12)
        self.assertEqual(row['source'], 'whoop')

    def test_existing_google_fixture_with_offline_adapter_functions(self):
        # Reuse the existing adapter fixture without its config/OAuth loader.
        import importlib.util
        spec = importlib.util.spec_from_file_location('offline_fitbit_fixture', ROOT / 'test/fitbit_oauth_test.py')
        fixture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixture)
        names = {'_to_float', '_date_object', '_first_matching_daily', '_sync_sleep_metrics',
                 '_sync_daily_resting_hr', '_sync_daily_hrv', '_sync_active_zone_minutes', 'sync_google_health_day'}
        scope = functions('backend/fitbit_api.py', names)
        class Adapter:
            def __getattr__(self, name):
                return scope[name]
            def __setattr__(self, name, value):
                scope[name] = value
        case = fixture.FitbitOAuthTest('test_google_health_day_sync_normalizes_biometric_columns')
        case._load_fitbit_api = lambda: Adapter()
        case.test_google_health_day_sync_normalizes_biometric_columns()


if __name__ == '__main__':
    unittest.main()
