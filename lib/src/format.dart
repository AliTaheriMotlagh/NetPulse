const _byteUnits = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
const _bitUnits = ['bps', 'Kbps', 'Mbps', 'Gbps', 'Tbps'];

String _scaled(double v, List<String> units) {
  var i = 0;
  while (v.abs() >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  final digits = i == 0 || v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(digits)} ${units[i]}';
}

/// Decimal (SI) units, matching carriers, ISPs and Apple/Android system settings.
String fmtBytes(num bytes) => _scaled(bytes.toDouble(), _byteUnits);

String fmtRate(double bytesPerSec, {required bool bits}) =>
    bits ? _scaled(bytesPerSec * 8, _bitUnits) : '${fmtBytes(bytesPerSec)}/s';

String _two(int n) => n.toString().padLeft(2, '0');

String fmtDuration(Duration d) {
  final core = '${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';
  if (d.inHours >= 24) return '${d.inDays}d ${_two(d.inHours % 24)}:$core';
  return '${_two(d.inHours)}:$core';
}

String fmtClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String fmtDate(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)} ${fmtClock(t)}';
