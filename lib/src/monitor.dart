import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'counters/apps.dart';
import 'counters/counters.dart';

/// One point on the live chart: throughput in bytes per second.
class Sample {
  const Sample(this.at, this.down, this.up);
  final DateTime at;
  final double down, up;
}

/// A marked moment inside a session; [rx]/[tx] are cumulative session totals.
class Checkpoint {
  Checkpoint(this.label, this.at, this.rx, this.tx);
  String label;
  final DateTime at;
  final int rx, tx;

  Map<String, Object> toJson() => {'l': label, 'at': at.millisecondsSinceEpoch, 'rx': rx, 'tx': tx};
  factory Checkpoint.fromJson(Map<String, dynamic> j) =>
      Checkpoint(j['l'] as String, DateTime.fromMillisecondsSinceEpoch(j['at'] as int), j['rx'] as int, j['tx'] as int);
}

class Session {
  Session(this.start);
  final DateTime start;
  DateTime? end;
  int rx = 0, tx = 0, rxPk = 0, txPk = 0;
  double peakDown = 0, peakUp = 0;
  final laps = <Checkpoint>[];

  /// Per-interface and per-app session totals: key -> [rx, tx].
  final ifaces = <String, List<int>>{};
  final apps = <String, List<int>>{};

  Duration elapsed() => (end ?? DateTime.now()).difference(start);
  double get avgRate => (rx + tx) / max(1, elapsed().inMilliseconds / 1000);

  Map<String, Object?> toJson() => {
    'start': start.millisecondsSinceEpoch,
    'end': end?.millisecondsSinceEpoch,
    'rx': rx,
    'tx': tx,
    'rp': rxPk,
    'tp': txPk,
    'pd': peakDown,
    'pu': peakUp,
    'laps': [for (final c in laps) c.toJson()],
    'if': ifaces,
    'apps': apps,
  };

  static Map<String, List<int>> _totals(Object? j) => {
    for (final e in (j as Map<String, dynamic>? ?? {}).entries) e.key: List<int>.from(e.value as List),
  };

  factory Session.fromJson(Map<String, dynamic> j) {
    final end = j['end'] as int?;
    return Session(DateTime.fromMillisecondsSinceEpoch(j['start'] as int))
      ..end = end == null ? null : DateTime.fromMillisecondsSinceEpoch(end)
      ..rx = j['rx'] as int
      ..tx = j['tx'] as int
      ..rxPk = j['rp'] as int? ?? 0
      ..txPk = j['tp'] as int? ?? 0
      ..peakDown = (j['pd'] as num).toDouble()
      ..peakUp = (j['pu'] as num).toDouble()
      ..laps.addAll([for (final c in j['laps'] as List) Checkpoint.fromJson(c as Map<String, dynamic>)])
      ..ifaces.addAll(_totals(j['if']))
      ..apps.addAll(_totals(j['apps']));
  }
}

enum Health {
  excellent('Excellent'),
  good('Good'),
  fair('Fair'),
  poor('Poor'),
  offline('Offline'),
  pending('Measuring…'),
  off('Not measured');

  const Health(this.label);
  final String label;
}

class Settings extends ChangeNotifier {
  Settings._(this._prefs) {
    final j = jsonDecode(_prefs.getString('settings') ?? '{}') as Map<String, dynamic>;
    theme = ThemeMode.values[j['theme'] as int? ?? 0];
    bits = j['bits'] as bool? ?? false;
    intervalMs = j['interval'] as int? ?? 1000;
    probe = j['probe'] as bool? ?? false; // off: NetPulse itself sends nothing unless asked
    probeHost = j['host'] as String? ?? '1.1.1.1';
    limitGb = (j['limit'] as num? ?? 0).toDouble();
    trackApps = j['apps'] as bool? ?? true;
  }

  final SharedPreferences _prefs;
  late ThemeMode theme;
  late bool bits, probe, trackApps;
  late int intervalMs;
  late String probeHost;
  late double limitGb; // 0 = no limit

  void update(void Function(Settings s) change) {
    change(this);
    _prefs.setString(
      'settings',
      jsonEncode({
        'theme': theme.index,
        'bits': bits,
        'interval': intervalMs,
        'probe': probe,
        'host': probeHost,
        'limit': limitGb,
        'apps': trackApps,
      }),
    );
    notifyListeners();
  }
}

class IfaceState {
  IfaceState(this.counter);
  IfaceCounter counter;
  double down = 0, up = 0;
}

/// One app's traffic, aggregated over its processes.
class AppUsage {
  AppUsage(this.name);
  final String name;
  int rx = 0, tx = 0, procs = 0; // cumulative since each process started
  double down = 0, up = 0;
}

/// Samples OS counters, keeps live history, session totals, checkpoints and link health.
class NetMonitor extends ChangeNotifier {
  NetMonitor._(this._prefs, this.source, this.appSource) : settings = Settings._(_prefs);

  static Future<NetMonitor> create() async {
    final m = NetMonitor._(await SharedPreferences.getInstance(), CounterSource.create(), AppSource.create());
    m._restore();
    m._start();
    return m;
  }

  final SharedPreferences _prefs;
  final Settings settings;
  final CounterSource source;
  final AppSource? appSource;

  static const _historyCap = 1200, _latencyCap = 60, _pastCap = 50;
  static const probeEvery = Duration(seconds: 5);

  /// While the window is hidden, counters are read this often only so 32-bit
  /// counters can't wrap unseen; the UI and per-app sampling stop entirely.
  static const _hiddenEvery = Duration(seconds: 30);

  final history = <Sample>[];
  final ifaces = <String, IfaceState>{};
  final latency = <double?>[]; // ms; null = failed probe
  final past = <Session>[];
  Session session = Session(DateTime.now());
  List<ConnectivityResult> links = const [];
  List<NetworkInterface> addresses = const [];
  String? error, publicIp, appsError;
  double pktDown = 0, pktUp = 0; // packets per second

  /// Per-app usage, or null before the first snapshot / when access is needed.
  Map<String, AppUsage>? apps;
  bool appsNeedAccess = false;

  final _raw = <String, (int, int, int, int)>{};
  final _procs = <String, ProcBytes>{};
  DateTime? _lastAt, _procsAt;
  bool _busy = false, _visible = true, _appsLoop = false, _testing = false;
  int _intervalMs = 0;
  Timer? _sampler, _prober, _saver;
  AppLifecycleListener? _life;
  StreamSubscription<List<ConnectivityResult>>? _links;

  Sample get current => history.isEmpty ? Sample(DateTime.now(), 0, 0) : history.last;

  double? get latencyMs => latency.isEmpty ? null : latency.last;

  double? get jitter {
    final ok = latency.whereType<double>().toList();
    if (ok.length < 2) return null;
    var sum = 0.0;
    for (var i = 1; i < ok.length; i++) {
      sum += (ok[i] - ok[i - 1]).abs();
    }
    return sum / (ok.length - 1);
  }

  double get loss => latency.isEmpty ? 0 : latency.where((l) => l == null).length / latency.length;

  bool get hasLink => links.any((l) => l != ConnectivityResult.none);

  Health get health {
    if (!hasLink) return Health.offline;
    if (latency.isEmpty) return settings.probe || _testing ? Health.pending : Health.off;
    final ms = latencyMs;
    if (ms == null) return Health.offline;
    if (ms < 50) return Health.excellent;
    if (ms < 120) return Health.good;
    if (ms < 250) return Health.fair;
    return Health.poor;
  }

  int? get limitBytes => settings.limitGb > 0 ? (settings.limitGb * 1e9).round() : null;

  bool get testingLatency => _testing;

  // ---- actions -------------------------------------------------------------

  /// One-off latency test: 5 TCP handshakes (a few hundred bytes in total).
  Future<void> testLatency() async {
    if (_testing) return;
    _testing = true;
    latency.clear();
    notifyListeners();
    for (var i = 0; i < 5; i++) {
      await _probe();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    _testing = false;
    notifyListeners();
  }

  Future<void> requestAppAccess() async {
    await appSource?.requestAccess();
  }

  Checkpoint checkpoint() {
    final c = Checkpoint('Checkpoint ${session.laps.length + 1}', DateTime.now(), session.rx, session.tx);
    session.laps.add(c);
    _changed();
    return c;
  }

  void renameCheckpoint(Checkpoint c, String label) {
    c.label = label.trim().isEmpty ? c.label : label.trim();
    _changed();
  }

  /// Archives the current session (if it has data) and starts a fresh one.
  void reset() {
    if (session.rx + session.tx > 0 || session.laps.isNotEmpty) {
      session
        ..end = DateTime.now()
        ..ifaces.clear()
        ..apps.clear();
      past.insert(0, session);
      if (past.length > _pastCap) past.removeLast();
    }
    session = Session(DateTime.now());
    history.clear();
    _changed();
  }

  void deletePast(Session s) {
    past.remove(s);
    _changed();
  }

  void clearPast() {
    past.clear();
    _changed();
  }

  String exportCsv() {
    final b = StringBuffer('label,time,elapsed_s,lap_s,lap_down_bytes,lap_up_bytes,total_down_bytes,total_up_bytes\n');
    var prev = Checkpoint('start', session.start, 0, 0);
    for (final c in [...session.laps, Checkpoint('now', DateTime.now(), session.rx, session.tx)]) {
      final label = '"${c.label.replaceAll('"', '""')}"';
      b.writeln(
        [
          label,
          c.at.toIso8601String(),
          c.at.difference(session.start).inSeconds,
          c.at.difference(prev.at).inSeconds,
          c.rx - prev.rx,
          c.tx - prev.tx,
          c.rx,
          c.tx,
        ].join(','),
      );
      prev = c;
    }
    return b.toString();
  }

  Future<void> fetchPublicIp() async {
    publicIp = 'Looking up…';
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final res = await (await client.getUrl(Uri.parse('https://api.ipify.org'))).close();
      publicIp = (await res.transform(utf8.decoder).join()).trim();
    } catch (_) {
      publicIp = 'Unavailable';
    } finally {
      client.close();
    }
    notifyListeners();
  }

  Future<void> refreshAddresses() async {
    try {
      addresses = await NetworkInterface.list(includeLoopback: false);
    } catch (_) {
      addresses = const [];
    }
    notifyListeners();
  }

  // ---- engine --------------------------------------------------------------

  void _start() {
    settings.addListener(_schedule);
    _schedule();
    _saver = Timer.periodic(const Duration(seconds: 30), (_) => save());
    _life = AppLifecycleListener(
      onShow: () => _setVisible(true),
      onResume: () => _setVisible(true),
      onHide: () => _setVisible(false),
      onPause: save,
      onDetach: save,
    );
    final c = Connectivity();
    c.checkConnectivity().then(_onLinks);
    _links = c.onConnectivityChanged.listen(_onLinks);
  }

  void _setVisible(bool v) {
    if (v == _visible) return;
    _visible = v;
    if (!v) save();
    _schedule();
  }

  void _schedule() {
    final ms = _visible ? settings.intervalMs : _hiddenEvery.inMilliseconds;
    if (_intervalMs != ms) {
      _intervalMs = ms;
      _sampler?.cancel();
      _sampler = Timer.periodic(Duration(milliseconds: ms), (_) => _tick());
      _tick();
    }
    final probe = settings.probe && _visible;
    if (probe && _prober == null) {
      _prober = Timer.periodic(probeEvery, (_) => _probe());
      _probe();
    } else if (!probe && _prober != null) {
      _prober!.cancel();
      _prober = null;
    }
    if (settings.trackApps && _visible && appSource != null && !_appsLoop) _runApps();
  }

  void _onLinks(List<ConnectivityResult> r) {
    links = r;
    refreshAddresses();
    if (settings.probe) _probe();
  }

  /// Back-to-back per-app snapshots while visible and enabled; exits on its own otherwise.
  Future<void> _runApps() async {
    _appsLoop = true;
    final src = appSource!;
    while (settings.trackApps && _visible) {
      final started = DateTime.now();
      try {
        final snap = await src.read();
        appsNeedAccess = snap == null;
        if (snap != null) _applyApps(snap);
        appsError = null;
      } catch (e) {
        appsError = 'Per-app data unavailable: $e';
      }
      notifyListeners();
      final wait = src.interval - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _appsLoop = false;
  }

  void _applyApps(Map<String, ProcBytes> snap) {
    final now = DateTime.now();
    final dt = _procsAt == null ? 0.0 : now.difference(_procsAt!).inMicroseconds / 1e6;
    final first = _procsAt == null;
    final next = <String, AppUsage>{};
    snap.forEach((key, p) {
      final (name, rx, tx) = p;
      final prev = _procs[key];
      // A process first seen after the baseline started since the last snapshot,
      // so all of its bytes are new; on the very first snapshot nothing is.
      final dRx = prev == null ? (first ? 0 : rx) : max(0, rx - prev.$2);
      final dTx = prev == null ? (first ? 0 : tx) : max(0, tx - prev.$3);
      final a = next.putIfAbsent(name, () => AppUsage(name))
        ..rx += rx
        ..tx += tx
        ..procs += 1;
      if (dt > 0 && dt < 60) {
        a
          ..down += dRx / dt
          ..up += dTx / dt;
      }
      if (dRx + dTx > 0) {
        final t = session.apps.putIfAbsent(name, () => [0, 0]);
        t[0] += dRx;
        t[1] += dTx;
      }
    });
    _procs
      ..clear()
      ..addAll(snap);
    _procsAt = now;
    apps = next;
  }

  /// TCP connect time to host:443; works on every OS without ICMP privileges.
  Future<void> _probe() async {
    final sw = Stopwatch()..start();
    double? ms;
    try {
      final s = await Socket.connect(settings.probeHost, 443, timeout: const Duration(seconds: 3));
      ms = sw.elapsedMicroseconds / 1000;
      s.destroy();
    } catch (_) {
      ms = null;
    }
    latency.add(ms);
    if (latency.length > _latencyCap) latency.removeAt(0);
    notifyListeners();
  }

  static int _delta(int prev, int cur, int wrap, bool live) {
    if (cur >= prev) return cur - prev;
    // A drop while sampling live near the top of a 32-bit counter is a wrap;
    // anything else (reboot, interface reset) contributes nothing.
    if (live && wrap > 0 && prev > wrap - (1 << 30)) return cur + wrap - prev;
    return 0;
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final list = await source.read();
      final now = DateTime.now();
      final dt = _lastAt == null ? 0.0 : now.difference(_lastAt!).inMicroseconds / 1e6;
      // After a long gap (app suspended or relaunched) the delta is added to
      // totals, but not plotted as a rate.
      final live = dt > 0 && dt < 10;
      final wrapOk = dt > 0 && dt < 60;
      var down = 0, up = 0, pkDown = 0, pkUp = 0;
      final seen = <String>{};
      for (final c in list) {
        seen.add(c.id);
        final prev = _raw[c.id];
        final dRx = prev == null ? 0 : _delta(prev.$1, c.rx, source.wrap, wrapOk);
        final dTx = prev == null ? 0 : _delta(prev.$2, c.tx, source.wrap, wrapOk);
        if (prev != null && prev.$3 >= 0 && c.kind.counted) {
          pkDown += _delta(prev.$3, c.rxPackets, source.wrap, wrapOk);
          pkUp += _delta(prev.$4, c.txPackets, source.wrap, wrapOk);
        }
        _raw[c.id] = (c.rx, c.tx, c.rxPackets, c.txPackets);
        ifaces.putIfAbsent(c.id, () => IfaceState(c))
          ..counter = c
          ..down = live ? dRx / dt : 0
          ..up = live ? dTx / dt : 0;
        final t = session.ifaces.putIfAbsent(c.id, () => [0, 0]);
        t[0] += dRx;
        t[1] += dTx;
        if (c.kind.counted) {
          down += dRx;
          up += dTx;
        }
      }
      ifaces.removeWhere((id, _) => !seen.contains(id));
      session
        ..rx += down
        ..tx += up
        ..rxPk += pkDown
        ..txPk += pkUp;
      pktDown = live ? pkDown / dt : 0;
      pktUp = live ? pkUp / dt : 0;
      if (live) {
        final s = Sample(now, down / dt, up / dt);
        history.add(s);
        if (history.length > _historyCap) history.removeRange(0, history.length - _historyCap);
        session
          ..peakDown = max(session.peakDown, s.down)
          ..peakUp = max(session.peakUp, s.up);
      }
      _lastAt = now;
      error = null;
    } catch (e) {
      error = 'Could not read network counters: $e';
    } finally {
      _busy = false;
      if (_visible) notifyListeners();
    }
  }

  void _changed() {
    save();
    notifyListeners();
  }

  void save() {
    _prefs.setString(
      'state',
      jsonEncode({
        'session': session.toJson(),
        'past': [for (final s in past) s.toJson()],
        'raw': {
          for (final e in _raw.entries) e.key: [e.value.$1, e.value.$2, e.value.$3, e.value.$4],
        },
      }),
    );
  }

  /// Older saves stored only [rx, tx]; -1 marks packets as unknown so they are not counted.
  static (int, int, int, int) _rawFrom(List v) =>
      (v[0] as int, v[1] as int, v.length > 3 ? v[2] as int : -1, v.length > 3 ? v[3] as int : -1);

  void _restore() {
    final s = _prefs.getString('state');
    if (s == null) return;
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      session = Session.fromJson(j['session'] as Map<String, dynamic>);
      past.addAll([for (final p in j['past'] as List) Session.fromJson(p as Map<String, dynamic>)]);
      (j['raw'] as Map<String, dynamic>).forEach((id, v) => _raw[id] = _rawFrom(v as List));
    } catch (_) {
      // Corrupt or incompatible state: start fresh rather than crash.
      session = Session(DateTime.now());
      past.clear();
      _raw.clear();
    }
  }

  @override
  void dispose() {
    _visible = false; // stops the per-app loop
    save();
    for (final t in [_sampler, _prober, _saver]) {
      t?.cancel();
    }
    _life?.dispose();
    _links?.cancel();
    settings.removeListener(_schedule);
    super.dispose();
  }
}
