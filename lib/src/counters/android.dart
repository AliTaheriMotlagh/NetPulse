import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'counters.dart';

/// Android: android.net.TrafficStats via a platform channel (see MainActivity.kt).
/// Direct /proc and netlink access is blocked for apps on Android 10+.
class AndroidSource extends CounterSource {
  static const _channel = MethodChannel('netpulse/traffic');

  @override
  String get description => 'android.net.TrafficStats';

  @override
  Future<List<IfaceCounter>> read() async {
    // [totalRx, totalTx, mobileRx, mobileTx, totalRxPk, totalTxPk, mobileRxPk, mobileTxPk]; -1 = unsupported
    final v = (await _channel.invokeMethod<Int64List>('counters'))!.map((e) => max(e, 0)).toList();
    return [
      IfaceCounter('Mobile data', IfaceKind.cellular, v[2], v[3], v[6], v[7]),
      IfaceCounter(
        'Wi-Fi & other',
        IfaceKind.lan,
        max(v[0] - v[2], 0),
        max(v[1] - v[3], 0),
        max(v[4] - v[6], 0),
        max(v[5] - v[7], 0),
      ),
    ];
  }
}
