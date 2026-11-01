import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netpulse/src/format.dart';
import 'package:netpulse/src/monitor.dart';

void main() {
  test('formats SI bytes, rates and durations', () {
    expect(fmtBytes(999), '999 B');
    expect(fmtBytes(1500), '1.50 KB');
    expect(fmtBytes(25300000), '25.3 MB');
    expect(fmtRate(125000, bits: true), '1.00 Mbps');
    expect(fmtRate(125000, bits: false), '125 KB/s');
    expect(fmtDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
    expect(fmtDuration(const Duration(days: 2, hours: 3)), '2d 03:00:00');
  });

  test('session survives a JSON round trip', () {
    final s = Session(DateTime(2026, 1, 1))
      ..rx = 1000
      ..tx = 200
      ..peakDown = 12.5
      ..laps.add(Checkpoint('A', DateTime(2026, 1, 1, 0, 5), 600, 100))
      ..ifaces['en0'] = [1000, 200];
    final r = Session.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(
      [r.start, r.rx, r.tx, r.peakDown, r.laps.single.label, r.laps.single.rx, r.ifaces['en0']],
      [
        s.start,
        1000,
        200,
        12.5,
        'A',
        600,
        [1000, 200],
      ],
    );
  });
}
