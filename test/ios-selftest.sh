#!/usr/bin/env bash
# The iOS host's multi-view self-test, on the simulator (sdk/Sources/FlutterUIKit/UIKitSelfTest.swift).
#
#   test/ios-selftest.sh            run it against the staged Office.app (.stage-ios)
#   test/ios-selftest.sh --build    build it first (build/ios-app.sh OfficeApp, ~13 min cold)
#
# Boots nothing and moves no mouse: it installs into the BOOTED simulator (or $SIM), launches with
# STARLING_SELFTEST=multiview and reads the app's stderr. Exit 0 = every step passed, 1 = a step failed,
# 2 = could not run (no booted simulator, no staged app, no result within the timeout).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
[ "${1:-}" = "--build" ] && { STARLING_IOS=1 build/ios-app.sh OfficeApp >/dev/null 2>&1 || { echo "build failed" >&2; exit 2; }; }
APP=".stage-ios/Office.app"
[ -d "$APP" ] || { echo "no $APP: run with --build" >&2; exit 2; }
SIM="${SIM:-$(xcrun simctl list devices booted | grep -Eo '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)}"
[ -n "$SIM" ] || { echo "no booted simulator" >&2; exit 2; }
LOG="$(mktemp -t ios-selftest)"
xcrun simctl terminate "$SIM" build.starling.office 2>/dev/null
xcrun simctl install "$SIM" "$APP" || exit 2
SIMCTL_CHILD_STARLING_SELFTEST=multiview xcrun simctl launch --console-pty "$SIM" build.starling.office >"$LOG" 2>&1 </dev/null &
PID=$!
for _ in $(seq 1 90); do grep -q "\[selftest\] DONE" "$LOG" && break; sleep 2; done
kill "$PID" 2>/dev/null
xcrun simctl terminate "$SIM" build.starling.office 2>/dev/null
grep "\[selftest\]" "$LOG"
if grep -q "\[selftest\] DONE pass=[0-9]* fail=0" "$LOG"; then rm -f "$LOG"; exit 0; fi
grep -q "\[selftest\] DONE" "$LOG" && { echo "log: $LOG"; exit 1; }
echo "no result within 3 minutes; log: $LOG" >&2; exit 2
