import importlib
import os
from pathlib import Path
import sys
import unittest
import urllib.parse

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


class FitbitOAuthTest(unittest.TestCase):
    def _load_fitbit_api(self, redirect_uri=None):
        if redirect_uri is None:
            os.environ.pop("GOOGLE_HEALTH_REDIRECT_URI", None)
            os.environ.pop("FITBIT_REDIRECT_URI", None)
        else:
            os.environ["GOOGLE_HEALTH_REDIRECT_URI"] = redirect_uri

        from backend import fitbit_api

        module = importlib.reload(fitbit_api)
        module._client_id = lambda: "test-fitbit-client-id"
        module._client_secret = lambda: "test-fitbit-client-secret"
        return module

    def test_production_redirect_uri_is_used_in_auth_url(self):
        redirect_uri = (
            "https://navi-backend-zcp5ib6peq-uc.a.run.app/fitbit/callback"
        )
        fitbit_api = self._load_fitbit_api(redirect_uri)

        auth_url = fitbit_api.generate_fitbit_auth_url()
        parsed = urllib.parse.urlparse(auth_url)
        query = urllib.parse.parse_qs(parsed.query)

        self.assertEqual(query["redirect_uri"], [redirect_uri])
        self.assertIn(
            "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
            query["scope"][0],
        )
        self.assertIn(
            "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
            query["scope"][0],
        )
        self.assertIn("access_type", query)
        self.assertEqual(query["access_type"], ["offline"])
        self.assertNotIn("127.0.0.1", auth_url)

    def test_signed_state_validates_after_module_reload(self):
        fitbit_api = self._load_fitbit_api()
        state = fitbit_api.generate_fitbit_state()

        reloaded_fitbit_api = importlib.reload(fitbit_api)
        reloaded_fitbit_api._client_secret = lambda: "test-fitbit-client-secret"

        reloaded_fitbit_api.validate_fitbit_state(state)

        tampered_state = state[:-1] + ("A" if state[-1] != "A" else "B")
        with self.assertRaises(ValueError):
            reloaded_fitbit_api.validate_fitbit_state(tampered_state)

    def test_google_health_day_sync_normalizes_biometric_columns(self):
        fitbit_api = self._load_fitbit_api()

        fitbit_api._reconcile_points = lambda data_type, filter_value=None: [
            {
                "sleep": {
                    "interval": {
                        "civilEndTime": {
                            "date": {"year": 2026, "month": 6, "day": 4}
                        }
                    },
                    "summary": {
                        "minutesAsleep": 420,
                        "minutesInSleepPeriod": 450,
                    },
                }
            }
        ]
        fitbit_api._list_points = lambda data_type, filter_value=None: {
            "daily-resting-heart-rate": [
                {
                    "dailyRestingHeartRate": {
                        "date": {"year": 2026, "month": 6, "day": 4},
                        "beatsPerMinute": 52,
                    }
                }
            ],
            "daily-heart-rate-variability": [
                {
                    "dailyHeartRateVariability": {
                        "date": {"year": 2026, "month": 6, "day": 4},
                        "averageHeartRateVariabilityMilliseconds": 67,
                    }
                }
            ],
        }[data_type]
        fitbit_api._daily_rollup = lambda data_type, day_iso: [
            {
                "activeZoneMinutes": {
                    "fatBurnSum": 20,
                    "cardioSum": 30,
                }
            }
        ]

        row = fitbit_api.sync_google_health_day("2026-06-04")

        self.assertEqual(row["date"], "2026-06-04")
        self.assertEqual(row["sleep_hours"], 7)
        self.assertAlmostEqual(row["sleep_efficiency"], 93.333333, places=5)
        self.assertEqual(row["resting_hr"], 52)
        self.assertEqual(row["hrv_rmssd"], 67)
        self.assertIsNone(row["recovery_score"])
        self.assertEqual(row["strain"], 10)
        self.assertEqual(row["source"], "google_health")


if __name__ == "__main__":
    unittest.main()
