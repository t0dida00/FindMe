#!/usr/bin/env bash
# Builds the app for a real iPhone (Debug, signed with the team in Config/Secrets.xcconfig),
# installs it over USB/Wi-Fi with devicectl and launches it.
# Picks the first paired physical device; set DEVICE=<UDID or name> to choose another.
# Runs `xcodegen generate` first so new/removed files are picked up.
#
# Usage: bash ios/scripts/install-device.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DD="build/device"

if [[ -z "${DEVICE:-}" ]]; then
  JSON="$(mktemp)"
  xcrun devicectl list devices --json-output "$JSON" >/dev/null
  DEVICE="$(python3 - "$JSON" <<'EOF'
import json, sys
devs = json.load(open(sys.argv[1]))["result"]["devices"]
for d in devs:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("reality") == "physical" and conn.get("pairingState") == "paired" \
            and hw.get("platform") == "iOS":
        print(hw.get("udid") or d["identifier"]); break
EOF
)"
  rm -f "$JSON"
fi
if [[ -z "$DEVICE" ]]; then
  echo "No paired iPhone found. Plug it in (or join the same Wi-Fi), unlock it and trust this Mac." >&2
  exit 1
fi

xcodegen generate --quiet
echo "Building for ${DEVICE}..."
xcodebuild -project FindMe.xcodeproj -scheme FindMe -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath "$DD" -allowProvisioningUpdates build -quiet

APP="$DD/Build/Products/Debug-iphoneos/FindMe.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID" >/dev/null \
  || echo "Installed, but could not launch (is the phone locked?). Open Find Me! by hand."
echo "Installed $BUNDLE_ID on $DEVICE."
