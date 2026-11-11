import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:web_dex/services/testing/isolated_heartbeat_probe.dart';
import 'package:web_dex/services/testing/isolated_sse_indicator.dart';

void main() {
  testWidgets(
    'blocked before login is cleared for the next session; old result cannot overwrite it',
    (tester) async {
      final service = KdfEventStreamingService();
      final sessions = StreamController<Object?>.broadcast();
      addTearDown(service.dispose);
      addTearDown(sessions.close);
      var connected = false;
      var session = Object();
      final trace = <HeartbeatProbeDiagnostic>[];
      final probe = IsolatedHeartbeatProbe(
        scopeApproved: () => true,
        captureSession: () async => session,
        ensureCurrent: (value) {
          if (value != session) throw StateError('synthetic session');
        },
        sessionChanges: sessions.stream,
        isConnected: () => connected,
        knownDisposableWallet: () async => true,
        diagnostic: trace.add,
        enable: () async => 'HEARTBEAT',
      );
      await tester.pumpWidget(
        IsolatedSseIndicator(
          service: service,
          probe: probe,
          child: const SizedBox.expand(),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('isolated-heartbeat-start')));
      await tester.pumpAndSettle();
      expect(
        find.text('Not ready: authenticate and connect SSE'),
        findsOneWidget,
      );
      expect(trace.last.reason, HeartbeatProbeReason.disconnected);
      sessions.add(session);
      connected = true;
      await tester.pumpAndSettle();
      expect(find.text('Start heartbeat test'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('isolated-heartbeat-start')));
      await tester.pumpAndSettle();
      expect(find.text('Heartbeat requested; observe counter'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('isolated-heartbeat-start')));
      await tester.pumpAndSettle();
      expect(find.text('Already requested for this session'), findsOneWidget);
      expect(trace.last.reason, HeartbeatProbeReason.alreadyRequested);
      sessions.add(null);
      session = Object();
      sessions.add(session);
      await tester.pumpAndSettle();
      expect(find.text('Start heartbeat test'), findsOneWidget);
      expect(find.text('SSE heartbeats: 0'), findsOneWidget);
      expect(trace.where((r) => r.stage == 'invoked').length, 3);
      final encoded = jsonEncode(trace.map((r) => r.toJson()).toList());
      expect(encoded, isNot(contains('synthetic session')));
    },
  );

  test(
    'late old disconnect cannot invalidate a newer registered connection',
    () {
      void event(int connection, String stage) =>
          IsolatedHeartbeatProbe.observeSseMetadata(
            'LCC_SSE ${jsonEncode({'connection': connection, 'stage': stage})}',
          );
      event(1, 'registered');
      event(2, 'connecting');
      expect(IsolatedHeartbeatProbe.registeredConnection, isNull);
      event(2, 'registered');
      event(1, 'disconnected');
      expect(IsolatedHeartbeatProbe.registeredConnection, 2);
      event(2, 'disconnected');
      expect(IsolatedHeartbeatProbe.registeredConnection, isNull);
    },
  );
}
