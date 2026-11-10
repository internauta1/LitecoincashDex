import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/native/windows_kdf_endpoint.dart';
import 'package:komodo_defi_framework/src/streaming/sse_diagnostics.dart';
import 'package:web_dex/services/testing/isolated_sse_indicator.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  testWidgets(
    'verified SSE stays idle until the fixture emits and renders a correlated heartbeat',
    (tester) async {
      const limit = Duration(seconds: 5);
      final records = <Map<String, dynamic>>[];
      final diagnostics = SseDiagnostics((line) {
        expect(line, startsWith('LCC_SSE '));
        records.add(jsonDecode(line.substring(8)) as Map<String, dynamic>);
      });
      late HttpServer server;
      late HttpResponse streamResponse;
      late WindowsKdfEndpoint endpoint;
      late KdfEventStreamingService service;
      var requestsToEnable = 0;
      final emitted = <int>[];
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final config = LocalConfig(
          https: false,
          rpcPassword: 'fixture-secret',
          port: server.port,
        );
        endpoint = WindowsKdfEndpoint(config.rpcUrl, config.rpcPassword);
        config.supervisedVersion = () async =>
            (await endpoint.call(pid, 'version', () => true))['result']
                as String;
        WindowsKdfEndpoint.streams[config] = () =>
            (() => endpoint.verifiedClient(pid, () => true), () => true);
        service = KdfEventStreamingService(
          hostConfig: config,
          diagnostics: diagnostics,
        );
        addTearDown(service.dispose);
        server.listen((request) async {
          if (request.method == 'GET' && request.uri.path == '/event-stream') {
            streamResponse = request.response..bufferOutput = false;
            streamResponse.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            streamResponse.write(': ready\n\n');
            await streamResponse.flush();
            return;
          }
          final payload =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          if (payload['method'] == 'stream::heartbeat::enable') {
            requestsToEnable++;
            request.response.write(
              '{"mmrpc":"2.0","result":{"streamer_id":"fixture-heartbeat"},"id":1}',
            );
            final frames = requestsToEnable == 1
                ? [
                    'invalid-json-fixture-secret',
                    '{"_type":"HEARTBEAT","message":{"timestamp":"fixture-secret"}}',
                    '{"_type":"fixture-secret","message":{"address":"fixture-secret"}}',
                    '{"_type":"NETWORK","message":{"netid":1,"peers":0}}',
                    '{"_type":"HEARTBEAT","message":{}}',
                  ]
                : ['{"_type":"HEARTBEAT","message":{"timestamp":42}}'];
            for (final frame in frames) {
              emitted.add(emitted.length + 1);
              streamResponse.write('data: $frame\n\n');
            }
            await streamResponse.flush();
            await request.response.close();
            return;
          }
          request.response.write('{"result":"fixture"}');
          await request.response.close();
        });
      });
      Future<void> enableHeartbeat() async {
        final response = await endpoint.post(
          pid,
          jsonEncode({
            'mmrpc': '2.0',
            'method': 'stream::heartbeat::enable',
            'id': 1,
            'userpass': 'fixture-secret',
            'params': {'client_id': 0},
          }),
          () => true,
        );
        expect(response.statusCode, 200);
      }

      void expectHeartbeatPath(int connection, int frame) {
        final path = records
            .where((r) => r['connection'] == connection && r['frame'] == frame)
            .toList();
        expect(path.map((r) => r['stage']), [
          'received',
          'decoded',
          'parsed',
          'published',
          'consumed',
          'rendered',
        ]);
        expect(path.skip(1).map((r) => r['kind']), everyElement('heartbeat'));
        expect(
          path.map((r) => DateTime.parse(r['utc'] as String).isUtc),
          everyElement(isTrue),
        );
      }

      await tester.pumpWidget(
        IsolatedSseIndicator(service: service, child: const SizedBox.expand()),
      );
      expect(find.text('SSE heartbeats: 0'), findsOneWidget);
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          service.connectIfNeeded();
          await service.firstByteReceived.timeout(limit);
          expect(service.isConnected, isTrue);
          expect(diagnostics.counts[SseStage.received] ?? 0, 0);
          expect(emitted, isEmpty);
          final heartbeat = service.heartbeatEvents.first.timeout(limit);
          await enableHeartbeat();
          expect((await heartbeat).timestamp, isNull);
        }, _LoopbackHttpOverrides()),
      );
      await tester.pump();
      expect(find.text('SSE heartbeats: 1'), findsOneWidget);
      expect(requestsToEnable, 1);
      expect(emitted, [1, 2, 3, 4, 5]);
      expectHeartbeatPath(1, 5);
      expect(
        records
            .where((r) => r['frame'] == 4 && r['stage'] == 'published')
            .single['kind'],
        'other',
      );
      expect(
        records.where((r) => r['frame'] == 4 && r['stage'] == 'consumed'),
        isEmpty,
      );
      expect(
        records.where((r) => r['stage'] == 'rejected').map((r) => r['reason']),
        ['invalidJson', 'invalidHeartbeat'],
      );
      expect(
        records.where((r) => r['stage'] == 'ignored').single['reason'],
        'unknownType',
      );
      expect(jsonEncode(records), isNot(contains('fixture-secret')));
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final disconnected = service.disconnections.first.timeout(limit);
          streamResponse.write('data: {"incomplete":true}\n');
          await streamResponse.close();
          expect((await disconnected).isManual, isFalse);
          expect(
            records
                .where((r) => r['reason'] == 'serverClosed')
                .single['connection'],
            1,
          );
          expect(
            records
                .where((r) => r['reason'] == 'incompleteFrame')
                .single['frame'],
            6,
          );
          service.connectIfNeeded();
          await service.firstByteReceived.timeout(limit);
          expect(
            records
                .where((r) => r['stage'] == 'registered')
                .map((r) => r['connection']),
            [1, 2],
          );
          final heartbeat = service.heartbeatEvents.first.timeout(limit);
          await enableHeartbeat();
          expect((await heartbeat).timestamp, 42);
          await service.disconnect();
        }, _LoopbackHttpOverrides()),
      );
      await tester.pump();
      expect(find.text('SSE heartbeats: 2'), findsOneWidget);
      expect(requestsToEnable, 2);
      expectHeartbeatPath(2, 1);
      expect(jsonEncode(records), isNot(contains('fixture-secret')));
      debugPrint(
        'R9_SSE_FIXTURE empty_heartbeat=1:5 legacy_heartbeat=2:1 widget_counter=0->1->2',
      );
    },
    skip: !Platform.isWindows,
  );
}
