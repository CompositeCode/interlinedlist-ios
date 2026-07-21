#!/usr/bin/env bash
#
# run-iphone.sh — build InterlinedList and run it on a connected iPhone.
#
# Requires:
#   * An iPhone connected via USB (or paired over the network), unlocked and
#     trusting this Mac, with Developer Mode enabled (Settings → Privacy &
#     Security → Developer Mode).
#   * Signing configured for the InterlinedList target in Xcode (a Team with a
#     provisioning profile). This script passes -allowProvisioningUpdates so
#     Xcode can create/refresh a development profile automatically.
#
# Usage:
#   ./run-iphone.sh              # first connected iOS device
#   ./run-iphone.sh "My iPhone"  # pick a device by name
#   DEVICE_NAME="My iPhone" ./run-iphone.sh
#
# Env overrides: DEVICE_NAME, CONFIGURATION (default Debug),
#                DEVELOPMENT_TEAM (optional; overrides the project's team).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

PROJECT="InterlinedList.xcodeproj"
SCHEME="InterlinedList"
BUNDLE_ID="com.interlinedlist.app"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$ROOT/build"
WANT_NAME="${1:-${DEVICE_NAME:-}}"

echo "==> InterlinedList → connected iPhone"

# --- Resolve the device -------------------------------------------------------
DEV_JSON="$(mktemp -t ildevices).json"
trap 'rm -f "$DEV_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEV_JSON" >/dev/null

read -r DEV_UDID DEV_ID DEV_LABEL < <(python3 - "$DEV_JSON" "$WANT_NAME" <<'PY'
import sys, json
path, want = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
devices = json.load(open(path)).get("result", {}).get("devices", [])

def is_ios(d):
    return d.get("hardwareProperties", {}).get("platform", "") == "iOS"

def connected(d):
    return d.get("connectionProperties", {}).get("tunnelState", "") == "connected"

cands = [d for d in devices if is_ios(d)]
if want:
    cands = [d for d in cands if d.get("deviceProperties", {}).get("name", "") == want]

# Prefer a connected device, then fall back to the first match.
pick = next((d for d in cands if connected(d)), cands[0] if cands else None)
if not pick:
    sys.exit(0)

udid = pick.get("hardwareProperties", {}).get("udid", "")
ident = pick.get("identifier", "")
name = pick.get("deviceProperties", {}).get("name", "device")
print(udid, ident, name.replace(" ", "_"))
PY
)

if [ -z "${DEV_UDID:-}" ] || [ -z "${DEV_ID:-}" ]; then
    echo "error: no connected iOS device found${WANT_NAME:+ named \"$WANT_NAME\"}." >&2
    echo "       check: xcrun devicectl list devices" >&2
    exit 1
fi
echo "==> Device: ${DEV_LABEL//_/ } (udid $DEV_UDID)"

# --- Build (device, signed) ---------------------------------------------------
TEAM_ARGS=()
if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    TEAM_ARGS=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi

echo "==> Building ($CONFIGURATION, signed)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=iOS,id=$DEV_UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    "${TEAM_ARGS[@]}" \
    build

# --- Locate the built .app ----------------------------------------------------
APP_PATH="$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos" \
    -maxdepth 1 -name "*.app" -type d 2>/dev/null | head -1)"
if [ -z "${APP_PATH:-}" ]; then
    echo "error: could not find built .app under $DERIVED_DATA" >&2
    exit 1
fi
echo "==> Built: $APP_PATH"

# --- Install & launch ---------------------------------------------------------
echo "==> Installing to device…"
xcrun devicectl device install app --device "$DEV_ID" "$APP_PATH"

echo "==> Launching $BUNDLE_ID…"
xcrun devicectl device process launch --device "$DEV_ID" "$BUNDLE_ID"

echo "==> Done."
