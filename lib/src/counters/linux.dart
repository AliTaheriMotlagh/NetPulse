import 'dart:io';

import 'counters.dart';

/// Linux: parses /proc/net/dev (64-bit counters) and /sys/class/net/*/operstate.
class LinuxSource extends CounterSource {
  @override
  String get description => '/proc/net/dev';

  @override
  Future<List<IfaceCounter>> read() async {
    final lines = await File('/proc/net/dev').readAsLines();
    final out = <IfaceCounter>[];
    for (final line in lines.skip(2)) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final name = line.substring(0, colon).trim();
      if (name == 'lo') continue;
      final f = line.substring(colon + 1).trim().split(RegExp(r'\s+')).map(int.parse).toList();
      String? state;
      try {
        state = File('/sys/class/net/$name/operstate').readAsStringSync().trim();
      } on FileSystemException {
        state = null;
      }
      // rx: bytes packets errs drop fifo frame compressed multicast | tx: bytes packets ...
      out.add(IfaceCounter(name, _kind(name), f[0], f[8], f[1], f[9], up: state == null ? null : state == 'up'));
    }
    return out;
  }

  static IfaceKind _kind(String n) {
    if (n.startsWith('wl')) return IfaceKind.wifi;
    if (n.startsWith('en') || n.startsWith('eth')) return IfaceKind.ethernet;
    if (n.startsWith('ww') || n.startsWith('rmnet')) return IfaceKind.cellular;
    if (RegExp(r'^(tun|tap|wg|ppp|tailscale|zt)').hasMatch(n)) return IfaceKind.vpn;
    return IfaceKind.virtual; // docker, veth, br, virbr ...
  }
}
