import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'counters.dart';

Pointer<Uint8> _at(Pointer p, int offset) => Pointer<Uint8>.fromAddress(p.address + offset);

/// Windows: GetIfTable2 from iphlpapi.dll, reading 64-bit MIB_IF_ROW2 counters.
class WindowsSource extends CounterSource {
  static final _lib = DynamicLibrary.open('iphlpapi.dll');
  static final _get = _lib
      .lookupFunction<Uint32 Function(Pointer<Pointer<Uint8>>), int Function(Pointer<Pointer<Uint8>>)>('GetIfTable2');
  static final _free = _lib.lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>(
    'FreeMibTable',
  );

  // MIB_IF_ROW2 layout (x64 and arm64), sizeof == 1352.
  static const _rowSize = 1352, _alias = 28, _type = 1128, _flags = 1152, _operStatus = 1156;
  static const _inOctets = 1208, _inUcast = 1216, _inNUcast = 1224;
  static const _outOctets = 1280, _outUcast = 1288, _outNUcast = 1296;

  @override
  String get description => 'GetIfTable2 / MIB_IF_ROW2';

  @override
  Future<List<IfaceCounter>> read() async {
    final table = calloc<Pointer<Uint8>>();
    try {
      final rc = _get(table);
      if (rc != 0) throw OSError('GetIfTable2 failed', rc);
      final t = table.value;
      final n = t.cast<Uint32>().value;
      final out = <IfaceCounter>[];
      for (var i = 0; i < n; i++) {
        final r = _at(t, 8 + i * _rowSize);
        final type = _at(r, _type).cast<Uint32>().value;
        final flags = r[_flags]; // bit0 HardwareInterface, bit1 FilterInterface
        if (type == 24 || flags & 2 != 0) continue; // loopback, filter-driver duplicates
        final kind = switch (type) {
          71 => IfaceKind.wifi,
          6 => IfaceKind.ethernet,
          243 || 244 => IfaceKind.cellular,
          23 || 53 || 131 => IfaceKind.vpn,
          _ => IfaceKind.virtual,
        };
        if (flags & 1 == 0 && kind != IfaceKind.vpn) continue; // skip Hyper-V/virtual NIC duplicates
        u64(int off) => _at(r, off).cast<Uint64>().value;
        out.add(
          IfaceCounter(
            _at(r, _alias).cast<Utf16>().toDartString(),
            kind,
            u64(_inOctets),
            u64(_outOctets),
            u64(_inUcast) + u64(_inNUcast),
            u64(_outUcast) + u64(_outNUcast),
            up: _at(r, _operStatus).cast<Uint32>().value == 1,
          ),
        );
      }
      _free(t);
      return out;
    } finally {
      calloc.free(table);
    }
  }
}
