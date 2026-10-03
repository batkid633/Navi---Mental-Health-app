import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

from google.cloud import secretmanager

from backend import config


class SecretRetentionTest(unittest.TestCase):
    def setUp(self):
        self.parent = "projects/123/secrets/whoop-tokens"
        self.client = Mock()
        self.client.get_secret.return_value = secretmanager.Secret(
            name=self.parent, version_destroy_ttl=timedelta(days=7),
            version_aliases={"rollback": 2},
        )

    def version(self, number, age=30, state=1, scheduled=False):
        fields = dict(name=f"{self.parent}/versions/{number}", state=state,
                      create_time=datetime.now(timezone.utc) - timedelta(days=age),
                      etag=f"etag-{number}")
        if scheduled:
            fields["scheduled_destroy_time"] = datetime.now(timezone.utc) + timedelta(days=7)
        return secretmanager.SecretVersion(**fields)

    def test_preserves_latest_three_alias_recent_and_scheduled_versions(self):
        self.client.list_secret_versions.return_value = [
            self.version(1), self.version(2), self.version(3, scheduled=True),
            self.version(4, age=1), self.version(5, state=2), self.version(6),
            self.version(7), self.version(8), self.version(9, state=3),
        ]
        config._prune_token_versions(self.client, self.parent, f"{self.parent}/versions/8")
        self.assertEqual(
            self.client.destroy_secret_version.call_args_list,
            [unittest.mock.call(request={"name": f"{self.parent}/versions/5", "etag": "etag-5"}),
             unittest.mock.call(request={"name": f"{self.parent}/versions/1", "etag": "etag-1"})],
        )

    def test_no_cleanup_without_delayed_destruction(self):
        self.client.get_secret.return_value = secretmanager.Secret(name=self.parent)
        config._prune_token_versions(self.client, self.parent, f"{self.parent}/versions/8")
        self.client.list_secret_versions.assert_not_called()

    def test_other_secrets_are_never_pruned(self):
        config._prune_token_versions(self.client, "projects/123/secrets/openai-api-key", "unused")
        self.client.get_secret.assert_not_called()

    def test_concurrent_newer_versions_are_not_deleted(self):
        self.client.list_secret_versions.return_value = [self.version(i) for i in range(1, 10)]
        config._prune_token_versions(self.client, self.parent, f"{self.parent}/versions/3")
        self.assertEqual(self.client.destroy_secret_version.call_count, 1)
        self.assertEqual(self.client.destroy_secret_version.call_args.kwargs["request"]["name"],
                         f"{self.parent}/versions/1")

    def test_cleanup_failure_does_not_fail_successful_token_save(self):
        self.client.add_secret_version.return_value.name = f"{self.parent}/versions/8"
        self.client.get_secret.side_effect = PermissionError("cleanup denied")
        with patch.object(secretmanager, "SecretManagerServiceClient", return_value=self.client):
            with self.assertLogs("navi.config", level="WARNING"):
                config.add_secret_version(self.parent, "test-token")
        self.client.add_secret_version.assert_called_once()


if __name__ == "__main__":
    unittest.main()
