import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/testing/isolated_heartbeat_probe.dart';
import 'package:web_dex/services/testing/isolated_sse_indicator.dart';

void main() {
  late bool approved, connected, known, current;
  late int requests, identityReads;
  late Object session;
  late String response;
  late List<HeartbeatProbeStage> stages;
  IsolatedHeartbeatProbe probe({
    Future<bool> Function()? readIdentity,
    Future<String> Function()? request,
  }) => IsolatedHeartbeatProbe(
    scopeApproved: () => approved,
    captureSession: () async => session,
    ensureCurrent: (_) {
      if (!current) throw StateError('fixture');
    },
    isConnected: () => connected,
    knownDisposableWallet:
        readIdentity ??
        () async {
          identityReads++;
          return known;
        },
    enable:
        request ??
        () async {
          requests++;
          return response;
        },
    record: stages.add,
  );
  setUp(() {
    approved = connected = known = current = true;
    requests = identityReads = 0;
    session = Object();
    response = 'HEARTBEAT';
    stages = [];
  });
  test('rejects production scope before identity or heartbeat RPC', () async {
    approved = false;
    expect(await probe().start(), HeartbeatProbeStage.blocked);
    expect(identityReads, 0);
    expect(requests, 0);
  });
  test('rejects a disconnected SSE registration', () async {
    connected = false;
    expect(await probe().start(), HeartbeatProbeStage.blocked);
    expect(identityReads, 0);
    expect(requests, 0);
  });
  test('rejects any other active wallet or mixed wallet catalogue', () async {
    known = false;
    expect(await probe().start(), HeartbeatProbeStage.blocked);
    expect(requests, 0);
  });
  test('session change during identity read prevents activation', () async {
    final subject = probe(
      readIdentity: () async {
        current = false;
        return true;
      },
    );
    expect(await subject.start(), HeartbeatProbeStage.failed);
    expect(requests, 0);
  });
  test('disconnect during identity read prevents activation', () async {
    final subject = probe(
      readIdentity: () async {
        connected = false;
        return true;
      },
    );
    expect(await subject.start(), HeartbeatProbeStage.blocked);
    expect(requests, 0);
  });
  test('concurrent clicks share one request and cannot repeat it', () async {
    final reply = Completer<String>();
    final subject = probe(
      request: () {
        requests++;
        return reply.future;
      },
    );
    final a = subject.start(), b = subject.start();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    expect(identical(a, b), isTrue);
    reply.complete('HEARTBEAT');
    expect(await a, HeartbeatProbeStage.enabled);
    expect(await b, HeartbeatProbeStage.enabled);
    expect(await subject.start(), HeartbeatProbeStage.blocked);
    expect(requests, 1);
    expect(stages, [
      HeartbeatProbeStage.requested,
      HeartbeatProbeStage.enabled,
      HeartbeatProbeStage.blocked,
    ]);
  });
  test(
    'unknown acknowledgement fails and uncertain request is never retried',
    () async {
      response = 'unexpected';
      final subject = probe();
      expect(await subject.start(), HeartbeatProbeStage.failed);
      expect(await subject.start(), HeartbeatProbeStage.blocked);
      expect(requests, 1);
    },
  );
  test(
    'a new authenticated generation can request its own heartbeat',
    () async {
      final subject = probe();
      expect(await subject.start(), HeartbeatProbeStage.enabled);
      session = Object();
      expect(await subject.start(), HeartbeatProbeStage.enabled);
      expect(requests, 2);
    },
  );
  testWidgets('expired identity read cannot send a delayed heartbeat', (
    tester,
  ) async {
    final identity = Completer<bool>();
    final subject = probe(readIdentity: () => identity.future);
    final pending = subject.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(await pending, HeartbeatProbeStage.failed);
    identity.complete(true);
    await tester.pump();
    expect(requests, 0);
  });
  test('failed transport acknowledgement is not retried', () async {
    final subject = probe(
      request: () async {
        requests++;
        throw StateError('fixture');
      },
    );
    expect(await subject.start(), HeartbeatProbeStage.failed);
    expect(await subject.start(), HeartbeatProbeStage.blocked);
    expect(requests, 1);
  });
  testWidgets('button acknowledgement never fabricates a received heartbeat', (
    tester,
  ) async {
    final service = KdfEventStreamingService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      IsolatedSseIndicator(
        service: service,
        probe: probe(),
        child: const SizedBox.expand(),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('isolated-heartbeat-start')));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('SSE heartbeats: 0'), findsOneWidget);
    expect(find.text('Heartbeat requested; observe counter'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('isolated-heartbeat-start')));
    await tester.pumpAndSettle();
    expect(requests, 1);
  });
}
