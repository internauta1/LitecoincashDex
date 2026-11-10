import 'dart:async';
import 'dart:collection';

/// Shares concurrent equivalent reads, without caching identity or results.
class BalanceReadQueue<K, V> {
  BalanceReadQueue({this.maxConcurrent}) {
    if (maxConcurrent != null && maxConcurrent! < 1) {
      throw ArgumentError.value(maxConcurrent);
    }
  }
  // The SDK default shares equivalent work without a global cross-asset cap.
  // A slow background read must not hold a foreground ETH request behind it.
  final int? maxConcurrent;
  final _pending = Queue<void Function()>();
  final _reads = <K, Future<_ReadOutcome<V>>>{};
  int _active = 0;
  bool _closed = false;
  bool _pumping = false;

  Future<V> read(K key, Future<V> Function() operation) async {
    if (_closed) throw StateError('Balance read queue is closed');
    var shared = _reads[key];
    if (shared == null) {
      final completer = Completer<_ReadOutcome<V>>();
      shared = completer.future;
      _reads[key] = shared;
      final owned = shared;
      _pending.add(() {
        _active++;
        () async {
          try {
            if (_closed) throw StateError('Balance read queue is closed');
            completer.complete(_ReadOutcome.value(await operation()));
          } catch (error, stack) {
            completer.complete(_ReadOutcome.error(error, stack));
          } finally {
            if (identical(_reads[key], owned)) _reads.remove(key);
            _active--;
            _pump();
          }
        }();
      });
      _pump();
    }
    return (await shared).unwrap();
  }

  void _pump() {
    if (_pumping) return;
    _pumping = true;
    try {
      while ((_closed || maxConcurrent == null || _active < maxConcurrent!) &&
          _pending.isNotEmpty) {
        _pending.removeFirst()();
      }
    } finally {
      _pumping = false;
    }
  }

  void close() {
    _closed = true;
    _pump();
  }
}

// Values, including failures, safely cross Dart error-zone boundaries.
class _ReadOutcome<T> {
  _ReadOutcome.value(T value) : _value = value, _error = null, _stack = null;
  _ReadOutcome.error(this._error, this._stack) : _value = null;
  final T? _value;
  final Object? _error;
  final StackTrace? _stack;
  T unwrap() {
    if (_error != null) Error.throwWithStackTrace(_error, _stack!);
    return _value as T;
  }
}
