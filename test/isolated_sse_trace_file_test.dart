import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/streaming/sse_diagnostics.dart';
import 'package:path/path.dart' as p;
import 'package:web_dex/services/testing/disposable_runtime_profile.dart';
import 'package:web_dex/services/testing/isolated_sse_trace_file.dart';

void main() {
  late Directory root;
  late IsolatedSseTraceFile trace;
  setUp(() async {
    final created = await Directory.systemTemp.createTemp('sse-evidence-unit-');
    root = Directory(await created.resolveSymbolicLinks());
    await File(
      p.join(root.path, DisposableRuntimeProfile.markerName),
    ).writeAsString(DisposableRuntimeProfile.markerValue);
    trace = IsolatedSseTraceFile.create(
      await DisposableRuntimeProfile.open(root.path),
    );
  });
  tearDown(() => root.delete(recursive: true));

  test('registration is immediately readable without closing the GUI', () {
    final diagnostics = SseDiagnostics((line) => trace.write(line));
    diagnostics.connect().record(SseStage.registered);
    final rows = trace.file.readAsLinesSync();
    expect(rows.length, 2);
    final last = jsonDecode(rows.last.substring(8)) as Map;
    expect(last['stage'], 'registered');
    expect(last['connection'], 1);
    expect(last.keys, isNot(contains('payload')));
  });

  test(
    'invalid, oversized and payload-bearing messages are never persisted',
    () {
      final record = {
        'utc': '2026-11-10T00:00:00Z',
        'connection': 1,
        'stage': 'received',
        'count': 1,
      };
      for (final value in [
        {'message': 'payload-must-never-persist'},
        {...record, 'payload': 'payload-must-never-persist'},
        {...record, 'connection': 0},
        {...record, 'frame': -1},
        {...record, 'kind': 'payload-must-never-persist'},
        {...record, 'stage': 'payload-must-never-persist'},
        {...record, 'reason': 'payload-must-never-persist'},
        {...record, 'utc': 'not-a-timestamp'},
      ]) {
        expect(trace.write('LCC_SSE ${jsonEncode(value)}'), isFalse);
      }
      expect(trace.write('LCC_SSE ${'x' * 2049}'), isFalse);
      expect(trace.write('arbitrary app output'), isFalse);
      expect(trace.file.readAsStringSync(), isEmpty);
    },
  );

  test('stream lifecycle metadata survives separate reconnect generations', () {
    final diagnostics = SseDiagnostics((line) => trace.write(line));
    final first = diagnostics.connect();
    first.record(SseStage.registered);
    first.record(SseStage.disconnected, reason: SseReason.transport);
    diagnostics.connect().record(SseStage.registered);
    final rows = trace.file
        .readAsLinesSync()
        .map((line) => jsonDecode(line.substring(8)) as Map)
        .toList();
    expect(rows.last['connection'], 2);
    expect(rows.last['stage'], 'registered');
    expect(rows.where((row) => row['stage'] == 'disconnected').length, 1);
  });
}
