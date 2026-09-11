#!/usr/bin/env python3
"""Prepare a short-lived sign-in card. Creates a Browserbase session; sends no message."""
import argparse
import getpass
import json
import os
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def https_origin(value):
    url = urllib.parse.urlsplit(value)
    if (url.scheme != 'https' or not url.hostname or url.username or url.password
            or url.port not in (None, 443) or url.path not in ('', '/') or url.query or url.fragment):
        raise argparse.ArgumentTypeError('Use an HTTPS origin, for example https://your-project.vercel.app')
    return value.rstrip('/')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', type=https_origin, default=os.environ.get('PUBLIC_BASE_URL'))
    parser.add_argument('--output', type=Path, default=Path('.local/sign-in-card.txt'))
    args = parser.parse_args()
    if not args.base_url:
        parser.error('set PUBLIC_BASE_URL or pass --base-url')
    if args.output.exists():
        parser.error('output already exists; choose a new --output path for a new card')
    secret = os.environ.get('APP_TRANSFER_SECRET') or getpass.getpass('Backend preparation secret: ')
    if len(secret) < 32:
        parser.error('the preparation secret must contain at least 32 characters')
    request = urllib.request.Request(args.base_url + '/api/transfers/prepare', data=b'{}', headers={
        'Authorization': 'Bearer ' + secret, 'Content-Type': 'application/json',
    })
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            prepared = json.load(response)
    except urllib.error.HTTPError as error:
        raise SystemExit(f'Preparation failed (HTTP {error.code}); check backend configuration.') from None
    if prepared.get('ok') is not True or not prepared.get('sessionId') or not prepared.get('token'):
        raise SystemExit('The backend did not return a valid sign-in card.')
    url = args.base_url + '/open?' + urllib.parse.urlencode({
        'view': 'web', 'target': 'https://news.ycombinator.com/login',
        'bbSession': prepared['sessionId'], 'bbToken': prepared['token'],
    })
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        output.write(url + '\n')
    print(f'Card saved to {args.output}. Keep this URL private; it contains a short-lived grant.')
    print(f"Session: {prepared['sessionId']}; expires: {prepared.get('tokenExpiresAt', 'in 10 minutes')}")


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(f'Could not prepare card: {type(error).__name__}. Check your configuration and connection.') from None
