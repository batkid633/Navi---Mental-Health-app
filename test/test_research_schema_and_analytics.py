import csv
import shutil
import unittest

from fastapi.testclient import TestClient

from backend import app as app_module
from backend.auth import CurrentUser
from backend.research_schema import (
    MODEL_DATASET_COLUMNS,
    RESEARCH_DAILY_FEATURE_SCHEMA_VERSION,
)
from backend.research_packets import (
    RESEARCH_PACKET_SCHEMA_NAME,
    RESEARCH_PACKET_SCHEMA_VERSION,
)
from backend.user_data import USER_DATA_DIR, user_dataset_path, user_storage_key


class _FakeAnalyticsSink:
    enabled = True

    def __init__(self):
        self.rows = []

    def insert_events(self, events):
        self.rows.extend(event.to_bigquery_row() for event in events)
        return {"enabled": True, "inserted": len(events), "errors": []}


class ResearchSchemaAndAnalyticsTest(unittest.TestCase):
    def setUp(self):
        self.user = CurrentUser(uid="schema-test-user", claims={"test": True})
        app_module.app.dependency_overrides[app_module.get_current_user] = (
            lambda: self.user
        )
        self.original_sink = app_module.analytics_sink
        self.original_persist_user_feature_records = (
            app_module.persist_user_feature_records
        )
        self.original_upload_packet_to_gcs = app_module.upload_packet_to_gcs
        self.fake_sink = _FakeAnalyticsSink()
        app_module.analytics_sink = self.fake_sink
        app_module.persist_user_feature_records = lambda _uid, _records: 0
        self.client = TestClient(app_module.app)

    def tearDown(self):
        app_module.analytics_sink = self.original_sink
        app_module.persist_user_feature_records = (
            self.original_persist_user_feature_records
        )
        app_module.upload_packet_to_gcs = self.original_upload_packet_to_gcs
        app_module.app.dependency_overrides.clear()
        shutil.rmtree(
            USER_DATA_DIR / user_storage_key(self.user.uid),
            ignore_errors=True,
        )
        shutil.rmtree(
            USER_DATA_DIR / user_storage_key("insights-user-a"),
            ignore_errors=True,
        )
        shutil.rmtree(
            USER_DATA_DIR / user_storage_key("insights-user-b"),
            ignore_errors=True,
        )

    def test_daily_features_enriches_research_records_and_keeps_model_csv_numeric(self):
        payload = {
            "records": [
                {
                    "date": "2026-06-12",
                    "schema_version": RESEARCH_DAILY_FEATURE_SCHEMA_VERSION,
                    "consent_version": "consent-test",
                    "sentiment_today": 0.25,
                    "rolling_mean_7": 0.2,
                    "volatility_7": 0.05,
                    "momentum_7": 0.01,
                    "z_score": 0.1,
                    "is_anomalous": 0,
                    "day_of_week": 4,
                    "Next_day_delta": 0.03,
                    "audio_session_count": 1,
                    "keyboard_session_count": 1,
                    "missing_journal": 0,
                    "missing_biometrics": 1,
                    "missing_audio": 0,
                    "missing_keyboard": 0,
                    "missing_sleep": 1,
                    "missing_hrv": 1,
                    "missing_recovery": 1,
                }
            ]
        }

        response = self.client.post("/ml/daily-features", json=payload)

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["saved"], 1)
        self.assertEqual(body["schema_version"], RESEARCH_DAILY_FEATURE_SCHEMA_VERSION)
        self.assertEqual(body["model_columns"], MODEL_DATASET_COLUMNS)

        dataset_path = user_dataset_path(self.user.uid)
        self.assertTrue(dataset_path.exists())
        with dataset_path.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(list(rows[0].keys()), MODEL_DATASET_COLUMNS)
        self.assertNotIn("schema_version", rows[0])
        self.assertIn("audio_session_count", rows[0])
        self.assertEqual(rows[0]["sentiment_today"], "0.25")
        self.assertEqual(rows[0]["audio_session_count"], "1.0")

    def test_analytics_events_include_schema_governance_fields_for_bigquery(self):
        response = self.client.post(
            "/analytics/events",
            json={
                "events": [
                    {
                        "event_id": "event-1",
                        "name": "Journal Saved Locally",
                        "properties": {"entry_count": 1},
                        "platform": "web",
                        "app_version": "test",
                        "schema_version": "navi_product_event_v2",
                        "session_id": "session-1",
                        "client_recorded_at": "2026-06-12T12:00:00Z",
                    }
                ]
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["inserted"], 1)
        row = self.fake_sink.rows[0]
        self.assertEqual(row["schema_version"], "navi_product_event_v2")
        self.assertEqual(row["client_schema_version"], "navi_product_event_v2")
        self.assertEqual(row["data_classification"], "privacy_safe_product_analytics")
        self.assertFalse(row["contains_health_content"])
        self.assertEqual(row["event_name"], "journal_saved_locally")

    def test_research_packet_endpoint_builds_coded_gcs_packet(self):
        captured = {}

        def fake_upload(packet):
            captured["packet"] = packet
            return {
                "uploaded": True,
                "skipped": False,
                "bucket": "test-bucket",
                "object": "research_packets/test.json",
                "packet_id": packet["packet_id"],
            }

        app_module.upload_packet_to_gcs = fake_upload

        response = self.client.post(
            "/research/packets",
            json={
                "app_version": "test-app",
                "client_generated_at": "2026-06-12T12:00:00Z",
                "records": [
                    {
                        "date": "2026-06-12",
                        "schema_version": RESEARCH_DAILY_FEATURE_SCHEMA_VERSION,
                        "sentiment_today": 0.25,
                        "rolling_mean_7": 0.2,
                        "volatility_7": 0.05,
                    }
                ],
            },
        )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertTrue(body["uploaded"])
        self.assertEqual(body["schema_name"], RESEARCH_PACKET_SCHEMA_NAME)
        self.assertEqual(body["schema_version"], RESEARCH_PACKET_SCHEMA_VERSION)
        packet = captured["packet"]
        self.assertNotEqual(packet["participant_code"], self.user.uid)
        self.assertNotIn("uid", packet)
        self.assertFalse(packet["privacy"]["raw_text_included"])
        self.assertFalse(packet["privacy"]["raw_audio_included"])
        self.assertEqual(packet["records"][0]["sentiment_today"], 0.25)

    def test_research_packet_endpoint_rejects_raw_content_fields(self):
        response = self.client.post(
            "/research/packets",
            json={
                "records": [
                    {
                        "date": "2026-06-12",
                        "sentiment_today": 0.25,
                        "raw_text_included": True,
                    }
                ],
            },
        )

        self.assertEqual(response.status_code, 422)

    def test_insight_trends_are_scoped_to_authenticated_user(self):
        self._seed_daily_features_for_user("insights-user-a", 0.10)
        self._seed_daily_features_for_user("insights-user-b", 0.80)

        self.user = CurrentUser(uid="insights-user-a", claims={"test": True})
        response_a = self.client.get("/insights/trends?days=1")
        self.assertEqual(response_a.status_code, 200)
        mood_a = response_a.json()["data"][0]["mood"]

        self.user = CurrentUser(uid="insights-user-b", claims={"test": True})
        response_b = self.client.get("/insights/trends?days=1")
        self.assertEqual(response_b.status_code, 200)
        mood_b = response_b.json()["data"][0]["mood"]

        self.assertAlmostEqual(mood_a, 0.10)
        self.assertAlmostEqual(mood_b, 0.80)

    def _seed_daily_features_for_user(self, uid, sentiment):
        original_user = self.user
        self.user = CurrentUser(uid=uid, claims={"test": True})
        records = []
        for day in range(1, 11):
            records.append(
                {
                    "date": f"2026-06-{day:02d}",
                    "sentiment_today": sentiment,
                    "rolling_mean_7": sentiment,
                    "volatility_7": 0.05,
                    "momentum_7": 0.0,
                    "z_score": 0.0,
                    "is_anomalous": 0,
                    "day_of_week": day % 7,
                    "sleep_hours": 7.0,
                    "hrv_rmssd": 50.0,
                    "missing_journal": 0,
                    "missing_biometrics": 0,
                    "missing_audio": 1,
                    "missing_keyboard": 1,
                    "missing_sleep": 0,
                    "missing_hrv": 0,
                    "missing_recovery": 1,
                }
            )

        response = self.client.post("/ml/daily-features", json={"records": records})
        self.assertEqual(response.status_code, 200)
        self.user = original_user


if __name__ == "__main__":
    unittest.main()
