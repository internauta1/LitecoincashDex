import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/transformers.dart';

void main() {
  test(
    'debounce flushes the latest event and closes with its source',
    () async {
      final source = StreamController<int>();
      final result = debounceStream(
        source.stream,
        const Duration(seconds: 1),
      ).toList();
      source.add(1);
      source.add(2);
      await source.close();
      expect(await result.timeout(const Duration(seconds: 1)), [2]);
    },
  );
  test('cancel removes the source listener and its pending timer', () async {
    final source = StreamController<int>();
    final events = <int>[];
    final sub = debounceStream(
      source.stream,
      const Duration(milliseconds: 5),
    ).listen(events.add);
    source.add(1);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(source.hasListener, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events, isEmpty);
    await source.close();
  });
  test('source errors remain observable and do not prevent shutdown', () async {
    final source = StreamController<int>();
    final errors = <Object>[];
    final done = Completer<void>();
    debounceStream(
      source.stream,
      const Duration(milliseconds: 5),
    ).listen((_) {}, onError: errors.add, onDone: done.complete);
    source.addError(StateError('fixture'));
    await source.close();
    await done.future;
    expect(errors.single, isA<StateError>());
  });
}
