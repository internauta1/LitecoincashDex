import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/app_shutdown.dart';

void main() {
  test('consumers complete before the dependent SDK is destroyed', () async {
    final shutdown = AppShutdown();
    final order = <String>[];
    final gate = Completer<void>();
    shutdown.register('producer', () async {
      order.add('stop');
      await gate.future;
      order.add('drained');
    });
    final closing = shutdown.stopConsumers().then((_) => order.add('sdk'));
    expect(shutdown.isClosing, isTrue);
    expect(order, ['stop']);
    gate.complete();
    await closing;
    expect(order, ['stop', 'drained', 'sdk']);
  });
  test(
    'timeout preserves the SDK and retry shares the original drain',
    () async {
      final shutdown = AppShutdown();
      final gate = Completer<void>();
      var calls = 0;
      var sdkDisposed = false;
      shutdown.register('consumer', () async {
        calls++;
        await gate.future;
      });
      await expectLater(
        shutdown
            .stopConsumers(timeout: const Duration(milliseconds: 5))
            .then((_) => sdkDisposed = true),
        throwsA(isA<TimeoutException>()),
      );
      expect(sdkDisposed, isFalse);
      expect(calls, 1);
      final retry = shutdown.stopConsumers();
      gate.complete();
      await retry;
      expect(calls, 1);
    },
  );
  test('newly registered consumers during drain are stopped too', () async {
    final shutdown = AppShutdown();
    final stopped = <String>[];
    shutdown.register('first', () {
      stopped.add('first');
      shutdown.register('second', () => stopped.add('second'));
    });
    await shutdown.stopConsumers();
    expect(stopped, ['first', 'second']);
  });
}
