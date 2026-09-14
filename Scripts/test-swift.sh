#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/cookieclip-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc Shared/WebViewMessageLink.swift Tests/WebViewMessageLinkTests.swift -o "$test_dir/links"
"$test_dir/links"
swiftc Shared/HackerNewsCookieCapture.swift Tests/HackerNewsCookieCaptureTests.swift -o "$test_dir/cookies"
"$test_dir/cookies"
swiftc Shared/HackerNewsCookieCapture.swift MessagesExtension/MessagesCookieTransfer.swift Tests/MessagesCookieTransferTests.swift -o "$test_dir/messages"
"$test_dir/messages"
swiftc Shared/WebViewMessageLink.swift Shared/SignInCard.swift Tests/SignInCardTests.swift -o "$test_dir/cards"
"$test_dir/cards"
