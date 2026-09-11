#!/usr/bin/env python3
"""Send a fresh, session-scoped App Clip test without logging its token."""
import argparse
import getpass
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from prepare_card import https_origin


LINQ_BASE = "https://api.linqapp.com/api/partner"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chat", required=True, type=uuid.UUID)
    parser.add_argument("--base-url", type=https_origin, default=os.environ.get("PUBLIC_BASE_URL"))
    parser.add_argument("--local", action="store_true", help="Send a text URL for an iPhone Local Experience")
    args = parser.parse_args()
    if not args.base_url:
        parser.error("set PUBLIC_BASE_URL or pass --base-url")
    transfer_secret = os.environ.get("APP_TRANSFER_SECRET")
    if not transfer_secret:
        transfer_secret = getpass.getpass("Backend test credential: ")
    linq_key = os.environ.get("LINQ_API_KEY") or getpass.getpass("Linq API key: ")
    opener = urllib.request.build_opener(NoRedirect)

    def request(base, path, key, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(base + path, data=data,
            headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        try:
            with opener.open(req, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Request failed (HTTP {error.code}); check configuration and permissions.") from None

    prepared = request(args.base_url, "/api/transfers/prepare", transfer_secret, {})
    if prepared.get("ok") is not True:
        raise RuntimeError("Backend did not prepare a transfer")
    url = args.base_url + "/open?" + urllib.parse.urlencode({
        "view": "web", "target": "https://news.ycombinator.com/login",
        "bbSession": prepared["sessionId"], "bbToken": prepared["token"],
        "test": "appclip-" + uuid.uuid4().hex[:12],
    })
    part = {"type": "text", "value": url} if args.local else {
        "type": "app_clip", "value": url, "caption": "Connect your Hacker News demo session",
    }
    path = f"/v3/chats/{args.chat}/messages"
    sent = request(LINQ_BASE, path, linq_key, {"message": {
        "preferred_service": "iMessage", "idempotency_key": "appclip-" + uuid.uuid4().hex,
        "parts": [part],
    }})
    message = sent["message"]
    summary = {"messageID": message["id"], "sessionID": prepared["sessionId"],
               "tokenExpiresAt": prepared["tokenExpiresAt"], "mode": "local-experience" if args.local else "app-clip-card"}
    print(json.dumps(summary), flush=True)
    for _ in range(5):
        time.sleep(2)
        status = request(LINQ_BASE, f"/v3/messages/{message['id']}", linq_key)
        delivery = status.get("delivery_status")
        if delivery in {"delivered", "read", "failed"}:
            print(json.dumps({"deliveryStatus": delivery}), flush=True)
            return
    print(json.dumps({"deliveryStatus": delivery}), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        raise SystemExit(str(error)) from None
