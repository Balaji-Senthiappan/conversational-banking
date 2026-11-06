"""Token service for the app's realtime voice (WebRTC).

The app must never hold the Azure credential. This service signs in with
DefaultAzureCredential (az login locally, Managed Identity when hosted) and mints
a short-lived realtime key for each voice session. The app then connects to Azure
directly over WebRTC with that key.

  python token_server.py            # http://127.0.0.1:8091
  POST /realtime/session  -> { "value": "ek_...", "expires_at": 1793981579,
                               "calls_url": "https://.../openai/v1/realtime/calls",
                               "model": "gpt-realtime-2.1" }
  GET  /                   -> browser test page (webrtc_test.html)

The Android emulator reaches this at http://10.0.2.2:8091.
CORS is open for local development only.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from azure.identity import DefaultAzureCredential

ENDPOINT = os.environ.get("REALTIME_ENDPOINT", "https://1000034329-fsto-dev1-resource.cognitiveservices.azure.com/").rstrip("/")
DEPLOYMENT = os.environ.get("REALTIME_DEPLOYMENT", "gpt-realtime-2.1")
VOICE = os.environ.get("REALTIME_VOICE", "marin")
PORT = int(os.environ.get("TOKEN_PORT", "8091"))
HERE = Path(__file__).parent

credential = DefaultAzureCredential()
_token = {"value": "", "expires_on": 0}


def entra_token() -> str:
    if time.time() > _token["expires_on"] - 300:
        t = credential.get_token("https://cognitiveservices.azure.com/.default")
        _token.update(value=t.token, expires_on=t.expires_on)
    return _token["value"]


def mint_key() -> dict:
    body = {"session": {"type": "realtime", "model": DEPLOYMENT,
                        "audio": {"output": {"voice": VOICE}}}}
    req = urllib.request.Request(
        f"{ENDPOINT}/openai/v1/realtime/client_secrets", data=json.dumps(body).encode(), method="POST",
        headers={"Authorization": f"Bearer {entra_token()}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.load(r)
    return {"value": data["value"], "expires_at": data.get("expires_at"),
            "calls_url": f"{ENDPOINT}/openai/v1/realtime/calls", "model": DEPLOYMENT}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body: bytes, ctype: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):  # CORS preflight
        self._send(204, b"")

    def do_GET(self):
        if self.path in ("/", "/test"):
            self._send(200, (HERE / "webrtc_test.html").read_bytes(), "text/html; charset=utf-8")
        elif self.path.startswith("/test-assets/"):
            # Recorded utterances for driving the app without a microphone (see README).
            f = (HERE / "test_assets" / Path(self.path).name)
            if f.is_file():
                self._send(200, f.read_bytes(), "audio/wav" if f.suffix == ".wav" else "application/octet-stream")
            else:
                self._send(404, b'{"error":"not found"}')
        elif self.path == "/health":
            self._send(200, json.dumps({"ok": True, "deployment": DEPLOYMENT}).encode())
        else:
            self._send(404, b'{"error":"not found"}')

    def do_POST(self):
        if self.path != "/realtime/session":
            return self._send(404, b'{"error":"not found"}')
        try:
            self._send(200, json.dumps(mint_key()).encode())
        except urllib.error.HTTPError as e:
            self._send(502, json.dumps({"error": f"Azure returned {e.code}", "detail": e.read().decode()[:400]}).encode())
        except Exception as e:  # sign-in problems, network
            self._send(502, json.dumps({"error": str(e)[:400]}).encode())

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.log_date_time_string(), fmt % args))


if __name__ == "__main__":
    print(f"Token service on http://127.0.0.1:{PORT}  ->  {ENDPOINT}  ({DEPLOYMENT})")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
