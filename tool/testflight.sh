#!/usr/bin/env bash
# Builds an optimized, signed iOS release and uploads it to App Store Connect / TestFlight.
#
# One-time prerequisites (Apple account required, cannot be scripted):
#   1. Apple Developer Program membership.
#   2. Xcode > Settings > Accounts: sign in with that Apple ID.
#   3. App Store Connect > Apps > "+": create an app with bundle ID com.alitaheri.netpulse.
#
# Usage: TEAM_ID=ABCDE12345 ./tool/testflight.sh
#   TEAM_ID is the 10-character ID on developer.apple.com > Membership.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID (developer.apple.com > Membership)}"
printf 'DEVELOPMENT_TEAM = %s\nCODE_SIGN_STYLE = Automatic\n' "$TEAM_ID" > ios/Flutter/Team.xcconfig

flutter analyze
flutter test

# --obfuscate/--split-debug-info: smaller binary; symbols stay local for crash decoding.
# Xcode exports with ios/ExportOptions.plist, which uploads straight to App Store Connect
# and lets Apple assign the next build number.
flutter build ipa --release \
  --obfuscate --split-debug-info=build/debug-info/ios \
  --export-options-plist=ios/ExportOptions.plist

echo "Uploaded. It appears in App Store Connect > TestFlight after processing (usually 5-15 min)."
echo "Add yourself as an internal tester there, then install via the TestFlight app on your iPhone."
