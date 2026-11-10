import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/src/balances/balance_read_queue.dart';

void main() {
  test('foreground ETH does not wait for unrelated cached asset reads', () async {
    final queue = BalanceReadQueue<(String, bool), int>();
    final gates = List.generate(4, (_) => Completer<int>());
    final background = List.generate(
      4,
      (i) => queue.read(('asset-$i', false), () => gates[i].future),
    );
    var foregroundStarted = false;
    final eth = queue.read(('ETH', true), () async {
      foregroundStarted = true;
      return 42;
    });
    await Future<void>.delayed(Duration.zero);
    expect(
      foregroundStarted,
      isTrue,
      reason:
          'the R4 global cap left ETH behind minutes of unrelated startup reads',
    );
    for (final gate in gates) {
      gate.complete(0);
    }
    expect(await eth, 42);
    await Future.wait(background);
  });
  test(
    'equivalent in-flight reads share work, completed values are not cached',
    () async {
      final queue = BalanceReadQueue<String, int>();
      final first = Completer<int>();
      var calls = 0;
      final requests = List.generate(
        20,
        (_) => queue.read('wallet/session/asset/fresh', () {
          calls++;
          return first.future;
        }),
      );
      expect(calls, 1);
      first.complete(7);
      expect(await Future.wait(requests), List.filled(20, 7));
      expect(
        await queue.read('wallet/session/asset/fresh', () async {
          calls++;
          return 8;
        }),
        8,
      );
      expect(calls, 2);
    },
  );
  test(
    'different session, asset and freshness keys remain separate and concurrency is bounded',
    () async {
      final queue = BalanceReadQueue<(int, String, bool), int>(
        maxConcurrent: 2,
      );
      final gates = List.generate(4, (_) => Completer<int>());
      final keys = [
        (1, 'ETH', false),
        (1, 'ETH', true),
        (2, 'ETH', true),
        (2, 'BNB', true),
      ];
      var active = 0;
      var peak = 0;
      var starts = 0;
      final reads = List.generate(
        4,
        (i) => queue.read(keys[i], () async {
          starts++;
          active++;
          if (active > peak) peak = active;
          try {
            return await gates[i].future;
          } finally {
            active--;
          }
        }),
      );
      expect(starts, 2);
      gates[0].complete(0);
      gates[1].complete(1);
      await Future<void>.delayed(Duration.zero);
      expect(starts, 4);
      gates[2].complete(2);
      gates[3].complete(3);
      expect(await Future.wait(reads), [0, 1, 2, 3]);
      expect(peak, 2);
    },
  );
  test('a failed read does not poison a later retry', () async {
    final queue = BalanceReadQueue<String, int>();
    await expectLater(
      queue.read('key', () async => throw StateError('fixture')),
      throwsStateError,
    );
    expect(await queue.read('key', () async => 9), 9);
  });
  test(
    'closing drains queued reads with errors without invoking their callbacks',
    () async {
      final queue = BalanceReadQueue<String, int>(maxConcurrent: 1);
      final gate = Completer<int>();
      var unwanted = false;
      final running = queue.read('one', () => gate.future);
      final pending = queue.read('two', () async {
        unwanted = true;
        return 2;
      });
      final rejected = expectLater(pending, throwsStateError);
      queue.close();
      await rejected.timeout(const Duration(seconds: 1));
      expect(unwanted, isFalse);
      gate.complete(1);
      expect(await running, 1);
      await expectLater(queue.read('new', () async => 0), throwsStateError);
    },
  );
  test(
    'shared failures cross error zones as outcomes and are rethrown to each caller',
    () async {
      final queue = BalanceReadQueue<String, int>();
      final gate = Completer<int>();
      final first = queue.read('same', () => gate.future);
      final firstError = expectLater(first, throwsStateError);
      final complete = Completer<void>();
      runZonedGuarded(() async {
        await expectLater(queue.read('same', () async => 0), throwsStateError);
        complete.complete();
      }, (error, stack) => complete.completeError(error, stack));
      gate.completeError(StateError('synthetic'));
      await firstError;
      await complete.future.timeout(const Duration(seconds: 2));
    },
  );
}
