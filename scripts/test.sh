#!/bin/bash
# Run the TapDetector tests (no Xcode / XCTest required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)/podpointer-tests"
swiftc -swift-version 5 "$ROOT/Tests/main.swift" "$ROOT/Sources/TapDetector.swift" -o "$OUT"
"$OUT"
