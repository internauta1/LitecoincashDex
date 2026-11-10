import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/validation/r9_sse_heartbeat_guard.dart';

void main() {
  final birth = DateTime.utc(2026, 11, 5, 14, 0, 0);
  final now = birth.add(const Duration(minutes: 2));
  String log(int id, String stage, [DateTime? utc]) =>
      'LCC_SSE ${jsonEncode({'connection': id, 'stage': stage, 'utc': (utc ?? birth).toIso8601String()})}';
  Future<int?> active(List<String> records) =>
      currentSseRegistration(Stream.fromIterable(records), birth, now);
  test('parses the WinPS 5.1 timestamp used for process creation', () {
    expect(readSseProbeUtc('/Date(${birth.millisecondsSinceEpoch})/'), birth);
  });
  test('requires registration on the current connection', () async {
    expect(await active([log(1, 'connecting'), log(1, 'handshake')]), isNull);
    expect(await active([log(1, 'connecting'), log(1, 'registered')]), 1);
  });
  test('rejects registration older than the current KDF', () async {
    expect(
      await active([
        log(1, 'connecting'),
        log(1, 'registered', birth.subtract(const Duration(seconds: 1))),
      ]),
      isNull,
    );
  });
  test('rejects future or orphan registration', () async {
    expect(await active([log(1, 'registered')]), isNull);
    expect(
      await active([
        log(1, 'connecting'),
        log(1, 'registered', now.add(const Duration(seconds: 1))),
      ]),
      isNull,
    );
  });
  test('disconnect and pending reconnect invalidate readiness', () async {
    final previous = [log(1, 'connecting'), log(1, 'registered')];
    expect(await active([...previous, log(1, 'disconnected')]), isNull);
    expect(await active([...previous, log(2, 'connecting')]), isNull);
    expect(
      await active([
        ...previous,
        log(2, 'connecting'),
        log(2, 'registered'),
        log(1, 'disconnected'),
      ]),
      2,
    );
  });
  test(
    'uses only structured diagnostics and rejects a truncated record',
    () async {
      expect(
        await active(['heartbeat registration', 'private-fixture-text']),
        isNull,
      );
      await expectLater(active(['LCC_SSE {']), throwsFormatException);
    },
  );
}
