import 'dart:ffi';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/native/windows_tcp_ownership.dart';

int wirePort(int value) => ((value & 255) << 8) | ((value >> 8) & 255);

class TcpTableFixture {
  int snapshots = 0;
  int owner = 1234;
  int state = 2;
  int remotePort = 45000;
  bool changing = false;
  bool neverSettles = false;
  bool corruptCount = false;
  int initialStatus = 122;
  int initialSize = 28;
  int query(
    Pointer<Void> table,
    Pointer<Uint32> size,
    int order,
    int af,
    int tableClass,
    int reserved,
  ) {
    if (table.address == 0) {
      size.value = initialSize;
      return initialStatus;
    }
    snapshots++;
    final capacity = size.value;
    final required = neverSettles
        ? capacity + 8192
        : changing
        ? 28 + snapshots * 64
        : 28;
    if (capacity < required) {
      size.value = required;
      return 122;
    }
    final words = table.cast<Uint32>();
    words[0] = corruptCount ? capacity : 1;
    words[1] = state;
    words[2] = 0x0100007f;
    words[3] = wirePort(17993);
    words[4] = 0x0100007f;
    words[5] = wirePort(remotePort);
    words[6] = owner;
    size.value = 28;
    return 0;
  }
}

void main() {
  test('moving TCP table can be verified within bounded snapshot reads', () {
    final api = TcpTableFixture()..changing = true;
    expect(readWindowsTcpOwners(query: api.query, rpcPort: 17993), {1234});
    expect(api.snapshots, lessThanOrEqualTo(3));
  });
  test('listener snapshot retains the actual foreign PID', () {
    final api = TcpTableFixture()..owner = 9999;
    expect(readWindowsTcpOwners(query: api.query, rpcPort: 17993), {9999});
  });
  test('connected socket must match its client port', () {
    final api = TcpTableFixture()..state = 5;
    expect(
      readWindowsTcpOwners(query: api.query, rpcPort: 17993, clientPort: 45000),
      {1234},
    );
    expect(
      readWindowsTcpOwners(query: api.query, rpcPort: 17993, clientPort: 45001),
      isEmpty,
    );
  });
  test('different RPC port cannot inherit ownership', () {
    final api = TcpTableFixture();
    expect(readWindowsTcpOwners(query: api.query, rpcPort: 17883), isEmpty);
  });
  test('snapshot which never settles fails closed within the retry bound', () {
    final api = TcpTableFixture()..neverSettles = true;
    expect(
      () => readWindowsTcpOwners(query: api.query, rpcPort: 17993),
      throwsStateError,
    );
    expect(api.snapshots, 3);
  });
  test('corrupt row count is rejected', () {
    final api = TcpTableFixture()..corruptCount = true;
    expect(
      () => readWindowsTcpOwners(query: api.query, rpcPort: 17993),
      throwsStateError,
    );
  });
  test('unavailable ownership API fails closed', () {
    final api = TcpTableFixture()..initialStatus = 5;
    expect(
      () => readWindowsTcpOwners(query: api.query, rpcPort: 17993),
      throwsStateError,
    );
  });
  test('absurd API size is rejected before allocating memory', () {
    final api = TcpTableFixture()..initialSize = 0xffffffff;
    expect(
      () => readWindowsTcpOwners(query: api.query, rpcPort: 17993),
      throwsStateError,
    );
    expect(api.snapshots, 0);
  });
}
