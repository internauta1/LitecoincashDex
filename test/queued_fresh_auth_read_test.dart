import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/src/auth/queued_fresh_read.dart';

class _Lock {
  int ticket = 0;
  int generation = 0;
  Future<void> _tail = Future.value();
  Future<void> enqueue(Future<void> Function() operation) {
    ticket++;
    final next = _tail.then((_) => operation());
    _tail = next.catchError((Object _) {});
    return next;
  }

  QueuedFreshRead<String> get reader => QueuedFreshRead(
    currentFence: () => (generation, ticket),
    enqueue: enqueue,
  );
}

void main() {
  test(
    'twenty waiting callers share a proof started after all were admitted',
    () async {
      final lock = _Lock();
      final reader = lock.reader;
      final gate = Completer<void>();
      unawaited(lock.enqueue(() => gate.future));
      var proofs = 0;
      final reads = List.generate(
        20,
        (_) => reader.read(() async {
          proofs++;
          return 'A';
        }),
      );
      expect(proofs, 0);
      gate.complete();
      expect(await Future.wait(reads), List.filled(20, 'A'));
      expect(proofs, 1);
      await reader.read(() async {
        proofs++;
        return 'A';
      });
      expect(proofs, 2, reason: 'completed identity proofs are never cached');
    },
  );
  test(
    'caller arriving after dispatch gets a new proof, not the running result',
    () async {
      final lock = _Lock();
      final reader = lock.reader;
      final started = Completer<void>();
      final gate = Completer<String>();
      final first = reader.read(() {
        started.complete();
        return gate.future;
      });
      await started.future;
      final second = reader.read(() async => 'B');
      gate.complete('A');
      expect(await first, 'A');
      expect(await second, 'B');
    },
  );
  test('intervening mutation keeps read/write/read lock ordering', () async {
    final lock = _Lock();
    final reader = lock.reader;
    final gate = Completer<void>();
    unawaited(lock.enqueue(() => gate.future));
    var identity = 'A';
    final order = <String>[];
    Future<String> proof() async {
      order.add('read $identity');
      return identity;
    }

    final before = reader.read(proof);
    final write = lock.enqueue(() async {
      identity = 'B';
      order.add('write B');
    });
    final after = reader.read(proof);
    gate.complete();
    expect(await before, 'A');
    await write;
    expect(await after, 'B');
    expect(order, ['read A', 'write B', 'read B']);
  });
  test(
    'session invalidation closes admission even before its write is queued',
    () async {
      final lock = _Lock();
      final reader = lock.reader;
      final gate = Completer<void>();
      unawaited(lock.enqueue(() => gate.future));
      var proofs = 0;
      final a = reader.read(() async {
        proofs++;
        return 'A';
      });
      lock.generation++;
      final b = reader.read(() async {
        proofs++;
        return 'B';
      });
      gate.complete();
      expect(await a, 'A');
      expect(await b, 'B');
      expect(proofs, 2);
    },
  );
  test('batched failures cross zones and do not poison recovery', () async {
    final lock = _Lock();
    final reader = lock.reader;
    final gate = Completer<void>();
    unawaited(lock.enqueue(() => gate.future));
    final a = expectLater(
      reader.read(() async => throw StateError('synthetic')),
      throwsStateError,
    );
    final other = Completer<void>();
    runZonedGuarded(() async {
      await expectLater(
        reader.read(() async => 'must not start'),
        throwsStateError,
      );
      other.complete();
    }, (e, s) => other.completeError(e, s));
    gate.complete();
    await a;
    await other.future;
    expect(await reader.read(() async => 'recovered'), 'recovered');
  });
}
