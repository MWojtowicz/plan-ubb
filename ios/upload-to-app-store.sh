#!/bin/zsh
# Builds Plan UBB for the App Store and uploads it to App Store Connect (TestFlight, then review).
#
#   ./upload-to-app-store.sh
#   TEAM_ID=<team> ./upload-to-app-store.sh
#
# The App Store Connect API key is read from the login Keychain. The item's name comes from
# signing.local.env at the repo root (gitignored, see SIGNING.local.md); ASC_KEYCHAIN_SERVICE overrides it.
# The key is written to a private temporary file only while xcodebuild runs.
# Raise CURRENT_PROJECT_VERSION in project.yml before each upload (and MARKETING_VERSION for a new version).
set -euo pipefail

cd "${0:A:h}"

[[ -f ../signing.local.env ]] && source ../signing.local.env
KEYCHAIN_SERVICE="${ASC_KEYCHAIN_SERVICE:?Set it in signing.local.env (see SIGNING.local.md)}"
item="$(security find-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null)" || {
  echo "No App Store Connect API key in the Keychain. See SIGNING.local.md." >&2
  exit 1
}
KEY_ID="$(print -r -- "$item" | sed -n 's/.*"acct"<blob>="\(.*\)"/\1/p')"
ISSUER_ID="$(print -r -- "$item" | sed -n 's/.*"icmt"<blob>="issuer=\(.*\)"/\1/p')"
[[ -n "$KEY_ID" && -n "$ISSUER_ID" ]] || { echo "The Keychain item needs a key ID (account) and issuer=<id> (comment)." >&2; exit 1; }

if [[ -z "${TEAM_ID:-}" ]]; then
  # Same source as install-on-device.sh, but the App Store needs a paid team.
  TEAM_ID="$(defaults export com.apple.dt.Xcode - 2>/dev/null \
    | plutil -extract IDEProvisioningTeamByIdentifier json -o - - 2>/dev/null \
    | python3 -c '
import json, sys
try:
    accounts = json.load(sys.stdin)
except ValueError:
    accounts = {}
teams = list({t["teamID"]: t for account in accounts.values() for t in account}.values())
paid = [t for t in teams if not t.get("isFreeProvisioningTeam")]
if len(paid) != 1:
    sys.exit("Pick the paid Apple Developer team with TEAM_ID=<id>:\n"
             + "\n".join("  " + t["teamID"] + "  " + t.get("teamName", "") for t in teams))
print(paid[0]["teamID"])
')"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEY_ID" -w | base64 -d > "$tmp/AuthKey.p8"
auth=(-allowProvisioningUpdates -authenticationKeyPath "$tmp/AuthKey.p8"
      -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")

cat > "$tmp/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF

echo "==> Generating the Xcode project"
xcodegen generate --quiet

echo "==> Archiving (team $TEAM_ID)"
xcodebuild archive -scheme PlanUbb -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/PlanUbb.xcarchive DEVELOPMENT_TEAM="$TEAM_ID" "${auth[@]}" -quiet

echo "==> Uploading to App Store Connect (key $KEY_ID)"
xcodebuild -exportArchive -archivePath build/PlanUbb.xcarchive -exportOptionsPlist "$tmp/ExportOptions.plist" \
  -exportPath build/export "${auth[@]}"

echo "==> Uploaded. The build shows up in TestFlight after Apple finishes processing it (usually 5–30 minutes)."
