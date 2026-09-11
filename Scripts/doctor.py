#!/usr/bin/env python3
"""Check developer prerequisites without printing secrets or calling live services."""
import platform
from pathlib import Path
import re
import shutil
import subprocess


def main():
    root = Path(__file__).resolve().parent.parent
    missing = False
    for name in ('xcodebuild', 'xcodegen', 'swiftc', 'node', 'npm', 'python3'):
        found = shutil.which(name) is not None
        print(f'{"OK" if found else "MISSING"}  {name}')
        missing |= not found
    if platform.system() != 'Darwin':
        print('NOTE  Native builds require macOS. Backend and Python checks also run on Linux.')
    if shutil.which('node'):
        version = subprocess.check_output(['node', '--version'], text=True).strip()
        print(f'NOTE  Node {version}; Node 22 is the pinned backend runtime (.nvmrc).')
    if shutil.which('xcodebuild'):
        result = subprocess.run(['xcodebuild', '-version'], capture_output=True, text=True)
        if result.returncode:
            print('MISSING  Full Xcode; select it with xcode-select and finish first-launch setup.')
            missing = True
    local = root / 'Config/Local.xcconfig'
    if not local.exists():
        print('NOTE  No local config. Simulator builds use portable defaults; run make setup for device setup.')
    else:
        text = local.read_text()
        if 'YOURTEAMID' in text or 'your-project' in text or 'com.yourcompany' in text:
            print('TODO  Fill in Config/Local.xcconfig before device installation or live transfers.')
        if re.search(r'^COOKIE_TRANSFER_CLIENT_SECRET\s*=\s*\S+', text, re.M):
            print('NOTE  Private Debug preparation is configured; Release builds omit this credential.')
    env = root / 'vercel-cookie-loader/.env.local'
    print('OK  Local backend env exists (values not checked).' if env.exists()
          else 'NOTE  Copy vercel-cookie-loader/.env.example to .env.local to configure a backend.')
    return int(missing)


if __name__ == '__main__':
    raise SystemExit(main())
