#!/usr/bin/env bash
# Generates the native platform projects and applies NetPulse's platform config.
# Safe to re-run: `flutter create .` only adds missing files, and each patch checks first.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --project-name netpulse --org com.alitaheri --platforms ios,android,macos,windows,linux .
flutter pub get

# Android: internet + network-state permissions for the latency probe and connectivity.
m=android/app/src/main/AndroidManifest.xml
grep -q ACCESS_NETWORK_STATE "$m" || perl -0pi -e 's|(<manifest[^>]*>)|$1\n    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>|' "$m"
perl -pi -e 's|android:label="netpulse"|android:label="NetPulse"|' "$m"

# macOS: outgoing network for the optional latency test; no App Sandbox so per-app traffic (nettop) works.
for e in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  grep -q network.client "$e" || perl -0pi -e 's|</dict>|\t<key>com.apple.security.network.client</key>\n\t<true/>\n</dict>|' "$e"
  perl -0pi -e 's|(<key>com.apple.security.app-sandbox</key>\s*)<true/>|$1<false/>|' "$e"
done
perl -pi -e 's|^PRODUCT_NAME = .*|PRODUCT_NAME = NetPulse|' macos/Runner/Configs/AppInfo.xcconfig

# Display names on iOS, Windows and Linux.
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName NetPulse' ios/Runner/Info.plist 2>/dev/null || true
perl -pi -e 's|L"netpulse"|L"NetPulse"|' windows/runner/main.cpp
perl -pi -e 's|"netpulse"|"NetPulse"|g' linux/runner/my_application.cc 2>/dev/null || perl -pi -e 's|"netpulse"|"NetPulse"|g' linux/my_application.cc

flutter analyze
echo "Done. Run: flutter run -d macos   (or ios / android / windows / linux)"
