import os
import secrets
import urllib.parse
import json
import requests
from datetime import datetime, timezone
from flask import Flask, request
from dotenv import load_dotenv

load_dotenv()

CLIENT_ID = os.getenv("WHOOP_CLIENT_ID")
CLIENT_SECRET = os.getenv("WHOOP_CLIENT_SECRET")
REDIRECT_URI = os.getenv("WHOOP_REDIRECT_URI")

AUTH_URL = "https://api.prod.whoop.com/oauth/oauth2/auth"
TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"

STATE = secrets.token_hex(4)  # 8 characters

app = Flask(__name__)


@app.route("/")
def login():
    params = {
        "response_type": "code",
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "scope": "read:sleep read:recovery read:workout offline",
        "state": STATE,
    }

    url = f"{AUTH_URL}?{urllib.parse.urlencode(params)}"
    return f'<a href="{url}">Login with WHOOP</a>'


@app.route("/callback")
def callback():
    code = request.args.get("code")
    state = request.args.get("state")

    if state != STATE:
        return "Invalid state parameter", 400

    token_resp = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "code": code,
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "redirect_uri": REDIRECT_URI,
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    if token_resp.status_code != 200:
        return token_resp.text, token_resp.status_code

    tokens = token_resp.json()
    # Token response contains:
    # - access_token
    # - refresh_token
    # - expires_in (seconds)
    # - token_type
    # - scope

    expires_in = tokens.get("expires_in")
    if expires_in is not None:
        tokens["expires_at"] = int(datetime.now(timezone.utc).timestamp() + int(expires_in))

    # Keep strict JSON formatting for machine parse
    with open("navi_ml/tokens/whoop_tokens.json", "w") as f:
        f.write(json.dumps(tokens, indent=2))

    return "WHOOP connected successfully. You can close this tab."


if __name__ == "__main__":
    app.run(port=8080, debug=False, use_reloader=False)
