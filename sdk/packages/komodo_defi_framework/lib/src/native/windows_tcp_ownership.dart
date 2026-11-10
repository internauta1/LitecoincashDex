import 'dart:ffi';
import 'package:ffi/ffi.dart';

typedef WindowsTcpTableQuery =
    int Function(Pointer<Void>, Pointer<Uint32>, int, int, int, int);

/// Read one bounded IPv4 snapshot. No RPC credentials are used by this reader.
Set<int> readWindowsTcpOwners({
  required WindowsTcpTableQuery query,
  required int rpcPort,
  int? clientPort,
}) {
  // Ask Windows for the relevant class directly. The aggregate table can
  // briefly omit a live listener under connection churn.
  const ownerPidListener = 3;
  const ownerPidConnections = 4;
  final tableClass = clientPort == null
      ? ownerPidListener
      : ownerPidConnections;
  final size = calloc<Uint32>();
  try {
    const insufficient = 122;
    if (query(nullptr, size, 0, 2, tableClass, 0) != insufficient) {
      throw StateError('TCP ownership unavailable');
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      // Windows reports an estimate; connections can grow between the sizing
      // call and this snapshot. Reserve bounded slack before every attempt.
      // https://learn.microsoft.com/windows/win32/api/iphlpapi/nf-iphlpapi-getextendedtcptable
      final requested = size.value;
      const maxBytes = 16 * 1024 * 1024;
      if (requested < 4 || requested > maxBytes) {
        throw StateError('Invalid TCP table size');
      }
      final slack = requested ~/ 4 > 4096 ? requested ~/ 4 : 4096;
      final capacity = requested + slack;
      if (capacity > maxBytes) throw StateError('TCP table allocation limit');
      size.value = capacity;
      final table = calloc<Uint8>(capacity);
      try {
        final rc = query(table.cast(), size, 0, 2, tableClass, 0);
        if (rc == insufficient) continue;
        if (rc != 0 || size.value < 4 || size.value > capacity)
          throw StateError('TCP table unavailable');
        final words = table.cast<Uint32>();
        final count = words[0];
        if (count > (size.value - 4) ~/ 24)
          throw StateError('Invalid TCP table');
        final owners = <int>{};
        for (var n = 0; n < count; n++) {
          final i = 1 + 6 * n;
          if (_port(words[i + 2]) != rpcPort) continue;
          const loopback = 0x0100007f;
          if (clientPort == null) {
            if (words[i] == 2 &&
                (words[i + 1] == 0 || words[i + 1] == loopback)) {
              owners.add(words[i + 5]);
            }
          } else if (words[i] == 5 &&
              words[i + 1] == loopback &&
              words[i + 3] == loopback &&
              _port(words[i + 4]) == clientPort) {
            owners.add(words[i + 5]);
          }
        }
        return owners;
      } finally {
        calloc.free(table);
      }
    }
    throw StateError('TCP ownership changed during inspection');
  } finally {
    calloc.free(size);
  }
}

int _port(int word) => ((word & 255) << 8) | ((word >> 8) & 255);
