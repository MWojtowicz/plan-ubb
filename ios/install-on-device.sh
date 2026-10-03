#!/bin/zsh
# Builds Plan UBB, signs it with your Apple team and installs it on a USB-connected iPhone.
#
#   ./install-on-device.sh            # Release build, first connected iPhone
#   CONFIGURATION=Debug ./install-on-device.sh
#   DEVICE_ID=<udid> TEAM_ID=<team> ./install-on-device.sh
#
# Without TEAM_ID it uses the team of the Apple ID signed into Xcode (Settings → Accounts),
# preferring the free personal team when there are several.
# Free-team apps expire after 7 days: run this again to re-sign and reinstall.
set -euo pipefail

cd "${0:A:h}"

if [[ -z "${TEAM_ID:-}" ]]; then
  # Xcode keeps the teams of every signed-in Apple ID here, keyed by account.
  TEAM_ID="$(defaults export com.apple.dt.Xcode - 2>/dev/null \
    | plutil -extract IDEProvisioningTeamByIdentifier json -o - - 2>/dev/null \
    | python3 -c '
import json, sys
try:
    accounts = json.load(sys.stdin)
except ValueError:
    accounts = {}
teams = list({t["teamID"]: t for account in accounts.values() for t in account}.values())
personal = [t for t in teams if t.get("isFreeProvisioningTeam")]
if not teams:
    sys.exit("No Apple ID in Xcode. Sign in under Xcode → Settings → Accounts, or set TEAM_ID.")
chosen = teams if len(teams) == 1 else personal
if len(chosen) != 1:
    sys.exit("Several teams in Xcode. Pick one with TEAM_ID=<id>:\n"
             + "\n".join("  " + t["teamID"] + "  " + t.get("teamName", "") for t in teams))
print(chosen[0]["teamID"])
')"
fi
CONFIGURATION="${CONFIGURATION:-Release}"
BUNDLE_ID="it.mwojtowicz.PlanUbb"
DERIVED_DATA="build/device"

if [[ -z "${DEVICE_ID:-}" ]]; then
  devices_json="$(mktemp)"
  trap 'rm -f "$devices_json"' EXIT
  xcrun devicectl list devices --quiet --json-output "$devices_json" >/dev/null
  DEVICE_ID="$(python3 - "$devices_json" <<'EOF'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
for d in devices:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if (hw.get("reality") == "physical" and hw.get("platform") == "iOS"
            and conn.get("transportType") == "wired" and conn.get("pairingState") == "paired"):
        print(hw["udid"])
        break
EOF
)"
  if [[ -z "$DEVICE_ID" ]]; then
    echo "No paired iPhone connected over USB. Plug it in, unlock it and tap Trust." >&2
    exit 1
  fi
fi
echo "==> Device: $DEVICE_ID, team: $TEAM_ID, configuration: $CONFIGURATION"

if command -v xcodegen >/dev/null; then
  echo "==> Generating Xcode project"
  xcodegen generate --quiet
fi

echo "==> Building and signing"
xcodebuild \
  -project PlanUbb.xcodeproj \
  -scheme PlanUbb \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -quiet \
  build

APP="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/PlanUbb.app"

echo "==> Installing $APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "==> Launching"
if ! xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID"; then
  echo "Installed, but couldn't launch it. If iOS says the developer isn't trusted, go to" >&2
  echo "Settings → General → VPN & Device Management and trust your Apple ID, then open the app." >&2
fi
