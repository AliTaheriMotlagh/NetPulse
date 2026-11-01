import 'dart:io';

import 'package:flutter/material.dart';

import 'android.dart';
import 'darwin.dart';
import 'linux.dart';
import 'windows.dart';

enum IfaceKind {
  wifi('Wi-Fi', Icons.wifi_rounded, true),
  ethernet('Ethernet', Icons.settings_ethernet_rounded, true),
  lan('Wi-Fi / Ethernet', Icons.router_outlined, true),
  cellular('Cellular', Icons.signal_cellular_alt_rounded, true),
  vpn('VPN / tunnel', Icons.vpn_lock_outlined, false),
  virtual('Virtual', Icons.device_hub_rounded, false);

  const IfaceKind(this.label, this.icon, this.counted);
  final String label;
  final IconData icon;

  /// Whether this interface contributes to totals. Tunnels and virtual
  /// adapters are excluded because their bytes also cross a physical link.
  final bool counted;
}

/// A raw snapshot of one interface's OS byte/packet counters.
class IfaceCounter {
  const IfaceCounter(this.id, this.kind, this.rx, this.tx, this.rxPackets, this.txPackets, {this.up});
  final String id;
  final IfaceKind kind;
  final int rx, tx, rxPackets, txPackets;

  /// Link state, or null when the platform does not expose it.
  final bool? up;
}

abstract class CounterSource {
  /// Counter modulus for platforms with 32-bit counters (0 = 64-bit).
  int get wrap => 0;
  String get description;
  Future<List<IfaceCounter>> read();

  static CounterSource create() {
    if (Platform.isAndroid) return AndroidSource();
    if (Platform.isWindows) return WindowsSource();
    if (Platform.isLinux) return LinuxSource();
    return DarwinSource();
  }
}
