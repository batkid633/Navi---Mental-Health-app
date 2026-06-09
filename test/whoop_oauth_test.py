import importlib
import os
from pathlib import Path
import sys
import unittest
import urllib.parse

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


class WhoopOAuthTest(unittest.TestCase):
    def _load_whoop_api(self, redirect_uri=None):
        if redirect_uri is None:
            os.environ.pop("WHOOP_REDIRECT_URI", None)
        else:
            os.environ["WHOOP_REDIRECT_URI"] = redirect_uri

        from backend import whoop_api

        module = importlib.reload(whoop_api)
        module._client_id = lambda: "test-client-id"
        module._client_secret = lambda: "test-client-secret"
        return module

    def test_production_redirect_uri_is_used_in_auth_url(self):
        redirect_uri = (
            "https://navi-backend-zcp5ib6peq-uc.a.run.app/whoop/callback"
        )
        whoop_api = self._load_whoop_api(redirect_uri)

        auth_url = whoop_api.generate_whoop_auth_url()
        parsed = urllib.parse.urlparse(auth_url)
        query = urllib.parse.parse_qs(parsed.query)

        self.assertEqual(query["redirect_uri"], [redirect_uri])
        self.assertNotIn("127.0.0.1", auth_url)

    def test_signed_state_validates_after_module_reload(self):
        whoop_api = self._load_whoop_api()
        state = whoop_api.generate_whoop_state()

        # Simulates the callback being handled by a different Cloud Run worker.
        reloaded_whoop_api = importlib.reload(whoop_api)
        reloaded_whoop_api._client_secret = lambda: "test-client-secret"

        reloaded_whoop_api.validate_whoop_state(state)

        tampered_state = state[:-1] + ("A" if state[-1] != "A" else "B")
        with self.assertRaises(ValueError):
            reloaded_whoop_api.validate_whoop_state(tampered_state)


if __name__ == "__main__":
    unittest.main()
