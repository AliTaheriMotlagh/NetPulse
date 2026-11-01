import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'counters.dart';

typedef _GetIfAddrs = Int32 Function(Pointer<Pointer<Uint8>>);
typedef _FreeIfAddrs = Void Function(Pointer<Uint8>);

Pointer<Uint8> _at(Pointer p, int offset) => Pointer<Uint8>.fromAddress(p.address + offset);

/// iOS and macOS: walks getifaddrs() and reads `struct if_data` from AF_LINK entries.
class DarwinSource extends CounterSource {
  static final _libc = DynamicLibrary.process();
  static final _get = _libc.lookupFunction<_GetIfAddrs, int Function(Pointer<Pointer<Uint8>>)>('getifaddrs');
  static final _free = _libc.lookupFunction<_FreeIfAddrs, void Function(Pointer<Uint8>)>('freeifaddrs');

  static const _afLink = 18, _iffUp = 0x1, _iffLoopback = 0x8, _iffRunning = 0x40;

  @override
  int get wrap => 1 << 32; // if_data byte counters are u_int32_t

  @override
  String get description => 'getifaddrs / if_data';

  @override
  Future<List<IfaceCounter>> read() async {
    final head = calloc<Pointer<Uint8>>();
    try {
      if (_get(head) != 0) throw const OSError('getifaddrs failed');
      final out = <IfaceCounter>[];
      // struct ifaddrs (LP64): next@0 name@8 flags@16 addr@24 netmask@32 dstaddr@40 data@48
      for (var p = head.value; p != nullptr; p = _at(p, 0).cast<Pointer<Uint8>>().value) {
        final addr = _at(p, 24).cast<Pointer<Uint8>>().value;
        final data = _at(p, 48).cast<Pointer<Uint8>>().value;
        final flags = _at(p, 16).cast<Uint32>().value;
        if (addr == nullptr || data == nullptr || addr[1] != _afLink || flags & _iffLoopback != 0) continue;
        final name = _at(p, 8).cast<Pointer<Utf8>>().value.toDartString();
        // struct if_data: ipackets@20 opackets@28 ibytes@40 obytes@44
        out.add(
          IfaceCounter(
            name,
            _kind(name),
            _at(data, 40).cast<Uint32>().value,
            _at(data, 44).cast<Uint32>().value,
            _at(data, 20).cast<Uint32>().value,
            _at(data, 28).cast<Uint32>().value,
            up: flags & (_iffUp | _iffRunning) == (_iffUp | _iffRunning),
          ),
        );
      }
      _free(head.value);
      return out;
    } finally {
      calloc.free(head);
    }
  }

  static IfaceKind _kind(String n) {
    if (n.startsWith('pdp_ip')) return IfaceKind.cellular;
    if (n.startsWith('utun') || n.startsWith('ipsec') || n.startsWith('ppp')) return IfaceKind.vpn;
    if (n == 'en0' && Platform.isIOS) return IfaceKind.wifi;
    if (n.startsWith('en')) return IfaceKind.lan;
    return IfaceKind.virtual; // awdl, llw, bridge, ap, anpi, gif, stf
  }
}
