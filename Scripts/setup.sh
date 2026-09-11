#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in xcodegen xcodebuild node npm python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing $tool. See README.md prerequisites." >&2
    exit 1
  fi
done
if [[ ! -f Config/Local.xcconfig ]]; then
  cp Config/Local.xcconfig.example Config/Local.xcconfig
  chmod 600 Config/Local.xcconfig
fi
if [[ ! -f vercel-cookie-loader/.env.local ]]; then
  cp vercel-cookie-loader/.env.example vercel-cookie-loader/.env.local
  chmod 600 vercel-cookie-loader/.env.local
fi
npm --prefix vercel-cookie-loader ci
xcodegen generate
python3 Scripts/doctor.py
printf '\nReady. Open CookieClipDemo.xcodeproj and choose HNMessages.\n'
