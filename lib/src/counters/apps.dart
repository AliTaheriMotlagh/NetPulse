import 'dart:io';

import 'package:flutter/services.dart';

/// Cumulative bytes for one process (or Android UID): (app name, rx, tx).
typedef ProcBytes = (String, int, int);

/// Per-app traffic. Only macOS and Android expose it to unprivileged apps:
/// iOS forbids it, and Windows/Linux need admin/root (ETW / eBPF).
abstract class AppSource {
  String get description;

  /// Minimum time between snapshots.
  Duration get interval;

  /// Snapshot keyed by process/UID, or null when the user must grant access first.
  Future<Map<String, ProcBytes>?> read();

  Future<void> requestAccess() async {}

  static AppSource? create() {
    if (Platform.isMacOS) return MacAppSource();
    if (Platform.isAndroid) return AndroidAppSource();
    return null;
  }

  static String get unsupportedReason {
    if (Platform.isIOS) return 'iOS does not let apps see other apps’ traffic.';
    if (Platform.isWindows) {
      return 'Per-app traffic on Windows needs administrator rights (ETW), which NetPulse does not request.';
    }
    return 'Per-app traffic on Linux needs root (eBPF), which NetPulse does not request.';
  }
}

/// macOS: `nettop` snapshot (works without root, outside the App Sandbox),
/// with full app names resolved from `ps` so helper processes group under their app.
class MacAppSource extends AppSource {
  final _names = <int, String>{};

  @override
  String get description => 'nettop';

  @override
  Duration get interval => const Duration(seconds: 5); // nettop -L 1 itself takes ~5 s

  @override
  Future<Map<String, ProcBytes>?> read() async {
    final r = await Process.run('/usr/bin/nettop', ['-P', '-L', '1', '-x', '-J', 'bytes_in,bytes_out']);
    final rows = <(int, String, int, int)>[];
    for (final line in (r.stdout as String).split('\n')) {
      final f = line.split(',');
      if (f.length < 3) continue;
      final dot = f[0].lastIndexOf('.');
      final pid = int.tryParse(f[0].substring(dot + 1)), rx = int.tryParse(f[1]), tx = int.tryParse(f[2]);
      if (dot <= 0 || pid == null || rx == null || tx == null) continue;
      rows.add((pid, f[0].substring(0, dot), rx, tx));
    }
    if (rows.any((p) => !_names.containsKey(p.$1))) await _refreshNames();
    final live = {for (final p in rows) p.$1};
    _names.removeWhere((pid, _) => !live.contains(pid));
    return {for (final (pid, short, rx, tx) in rows) '$pid': (_names[pid] ?? short, rx, tx)};
  }

  Future<void> _refreshNames() async {
    final r = await Process.run('/bin/ps', ['-axo', 'pid=,comm=']);
    for (final line in (r.stdout as String).split('\n')) {
      final t = line.trim();
      final sp = t.indexOf(' ');
      final pid = sp > 0 ? int.tryParse(t.substring(0, sp)) : null;
      if (pid != null) _names[pid] = _appName(t.substring(sp + 1).trim());
    }
  }

  /// "/Applications/Google Chrome.app/Contents/Frameworks/…Helper" -> "Google Chrome".
  static String _appName(String path) {
    final i = path.indexOf('.app/');
    if (i >= 0) return path.substring(path.lastIndexOf('/', i) + 1, i);
    return path.substring(path.lastIndexOf('/') + 1);
  }
}

/// Android: NetworkStatsManager per-UID totals since boot (needs Usage access).
class AndroidAppSource extends AppSource {
  static const _channel = MethodChannel('netpulse/traffic');

  @override
  String get description => 'NetworkStatsManager';

  @override
  Duration get interval => const Duration(seconds: 10);

  @override
  Future<Map<String, ProcBytes>?> read() async {
    final list = await _channel.invokeListMethod<List<Object?>>('apps');
    if (list == null) return null;
    return {for (final a in list) '${a[0]}': (a[1] as String, a[2] as int, a[3] as int)};
  }

  @override
  Future<void> requestAccess() => _channel.invokeMethod('openUsageAccess');
}
