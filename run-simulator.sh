#!/usr/bin/env bash
#
# run-simulator.sh — build InterlinedList and run it in an iOS Simulator.
#
# Usage:
#   ./run-simulator.sh                 # uses an already-booted sim, else "iPhone 16"
#   ./run-simulator.sh "iPhone 16 Pro" # boot/use a sim by name
#   SIMULATOR_NAME="iPhone SE (3rd generation)" ./run-simulator.sh
#
# Env overrides: SIMULATOR_NAME, CONFIGURATION (default Debug).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

PROJECT="InterlinedList.xcodeproj"
SCHEME="InterlinedList"
BUNDLE_ID="com.interlinedlist.app"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$ROOT/build"
DEVICE_NAME="${1:-${SIMULATOR_NAME:-iPhone 16}}"

echo "==> InterlinedList → iOS Simulator"

# --- Resolve a simulator UDID -------------------------------------------------
# Reuse an already-booted iOS simulator when there is one (fast path); otherwise
# resolve DEVICE_NAME to a concrete UDID. Pinning a UDID avoids the ambiguity of
# passing a bare device name as an xcodebuild destination.
UDID="$(xcrun simctl list devices booted -j | python3 -c '
import sys, json
data = json.load(sys.stdin)["devices"]
for runtime, devs in data.items():
    if "iOS" not in runtime:
        continue
    for d in devs:
        if d.get("state") == "Booted":
            print(d["udid"]); sys.exit(0)
' || true)"

if [ -n "${UDID:-}" ]; then
    echo "==> Using already-booted simulator: $UDID"
else
    UDID="$(xcrun simctl list devices available -j | python3 -c '
import sys, json
name = sys.argv[1]
data = json.load(sys.stdin)["devices"]
for runtime, devs in data.items():
    if "iOS" not in runtime:
        continue
    for d in devs:
        if d.get("isAvailable") and d["name"] == name:
            print(d["udid"]); sys.exit(0)
' "$DEVICE_NAME" || true)"
    if [ -z "${UDID:-}" ]; then
        echo "error: no available simulator named \"$DEVICE_NAME\"." >&2
        echo "       list options with: xcrun simctl list devices available" >&2
        exit 1
    fi
    echo "==> Booting simulator \"$DEVICE_NAME\": $UDID"
fi

# Boots if needed and blocks until the device is fully booted.
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator

# --- Build --------------------------------------------------------------------
echo "==> Building ($CONFIGURATION)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    build

# --- Locate the built .app ----------------------------------------------------
APP_PATH="$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator" \
    -maxdepth 1 -name "*.app" -type d 2>/dev/null | head -1)"
if [ -z "${APP_PATH:-}" ]; then
    echo "error: could not find built .app under $DERIVED_DATA" >&2
    exit 1
fi
echo "==> Built: $APP_PATH"

# --- Install & launch ---------------------------------------------------------
echo "==> Installing…"
xcrun simctl install "$UDID" "$APP_PATH"

echo "==> Launching $BUNDLE_ID…"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo "==> Done. (Stream logs with:  xcrun simctl spawn $UDID log stream --predicate 'process == \"$SCHEME\"' )"
