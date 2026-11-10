import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/streaming/event_streaming_platform_io.dart';

void main() {
  test(
    'SSE dispatches complete multiline frames with optional field space',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final events = <Object?>[];
      final gotEvents = Completer<void>();
      final sendRemainder = Completer<void>();
      final sentPartial = Completer<void>();
      server.listen((request) async {
        await request.drain<void>();
        if (request.method == 'POST') {
          request.response.write('{"result":"synthetic"}');
        } else {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            ':comment\r\ndata:{"kind":\r\ndata: "synthetic"}\r\n',
          );
          await request.response.flush();
          sentPartial.complete();
          await sendRemainder.future;
          request.response.write(
            '\r\ndata:bad-json\n\ndata:{"second":true}\n\n',
          );
        }
        await request.response.close();
      });
      final cancel = connectEventStream(
        hostConfig: RemoteConfig(
          ipAddress: '127.0.0.1',
          port: server.port,
          https: false,
          rpcPassword: 'synthetic',
        ),
        onFirstByte: () {},
        onDisconnected: ({required registrationsMayPersist}) {},
        onMessage: (value) {
          events.add(value);
          if (events.length == 2 && !gotEvents.isCompleted)
            gotEvents.complete();
        },
      );
      addTearDown(cancel);
      await sentPartial.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(events, isEmpty, reason: 'A frame ends only at the blank line');
      sendRemainder.complete();
      await gotEvents.future.timeout(const Duration(seconds: 3));
      expect(events, [
        {'kind': 'synthetic'},
        {'second': true},
      ]);
    },
  );
}
