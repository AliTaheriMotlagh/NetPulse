# NetPulse

Live network usage and status for iOS, Android, macOS, Windows and Linux, from one Flutter codebase compiled to native code.

## Features

- **Zero network use of its own:** everything is read from local OS counters. The latency test runs only when you tap it, or if you turn on the continuous monitor, which is off by default.
- **Per-app traffic:** AI apps, browsers and system daemons, with live speed, session total and total since each process started. Helper processes are grouped under their app.
  - **macOS:** uses `nettop`. This needs the App Sandbox disabled, which is fine for direct or Developer ID distribution but not for the Mac App Store.
  - **Android:** uses `NetworkStatsManager`, after you grant Usage access.
  - **iOS, Windows, Linux:** not available. iOS forbids it, and Windows and Linux need admin or root.
- **Packets:** session packet totals in and out, and live packets per second.
- **Low resource use:** about 53 MB physical footprint and about 0.1% CPU on macOS. While hidden, it skips UI updates and per-app sampling and reads counters only every 30 s.

- **Live speeds:** download and upload rate with session peaks, plus a 1/5/10-minute area chart with hover and drag tooltips.
- **Status:** connection type (Wi-Fi, cellular, Ethernet, VPN), IPv4, latency, jitter and loss from a TCP probe that needs no root or ICMP access.
- **Sessions:** elapsed time, totals, average rate, and projections per hour, day and 30 days. Includes an optional data limit with a warning at 80%.
- **Checkpoints:** laps that each show time, data and average rate since the previous one. You can rename them, export them as CSV, and add one with ⌘K or Ctrl+K.
- **Reset:** archives the session to history (last 50) and starts a new one.
- **Interfaces:** live and session rate per adapter, raw OS counters, packets, every local IP (tap to copy), and an on-demand public IP lookup.
- Light and dark themes, bytes or bits, and a sampling interval from 0.5 to 5 s. The layout uses bottom navigation on phones and a navigation rail on tablets and desktops.
- Totals keep running while the app is closed. The gap is filled in from the OS counters on the next launch, unless the device restarted.

## How counters are read (no heavy plugins)

| Platform | Source |
|---|---|
| iOS / macOS | `getifaddrs()` → `struct if_data` via `dart:ffi` (32-bit wrap handled) |
| Windows | `GetIfTable2` → `MIB_IF_ROW2` via `dart:ffi` |
| Linux | `/proc/net/dev` |
| Android | `TrafficStats` via a platform channel (`MainActivity.kt`) |

Totals count physical links only. VPN and virtual adapters are shown but excluded, because their traffic would otherwise be counted twice.

## Setup

```bash
# 1. Flutter SDK (if storage.googleapis.com / pub.dev are blocked, use the official mirror):
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
#    Download flutter_macos_arm64_<version>-stable.zip from the mirror, unzip to ~/development, then:
export PATH="$HOME/development/flutter/bin:$PATH"

# 2. Generate the platform projects and apply config (permissions, entitlements, names):
./tool/setup.sh

# 3. Run
flutter run -d macos          # iOS: open the simulator first, or plug in an iPhone
flutter test
```

- **Android:** install Android Studio (SDK + emulator).
- **Windows / Linux:** build on that OS (`flutter build windows` / `flutter build linux`).
- **Release builds:** `flutter build ipa | appbundle | macos | windows | linux`.
