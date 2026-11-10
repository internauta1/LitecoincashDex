import 'dart:async';

/// Batches only reads still waiting to start. A dispatched proof is never
/// reused by a later caller, and any intervening lock ticket/session change
/// closes admission to the older batch. There is no identity/result cache.
class QueuedFreshRead<T> {
  QueuedFreshRead({
    required Object Function() currentFence,
    required Future<void> Function(Future<void> Function()) enqueue,
  }) : _currentFence = currentFence,
       _enqueue = enqueue;

  final Object Function() _currentFence;
  final Future<void> Function(Future<void> Function()) _enqueue;
  _PendingRead<T>? _pending;

  Future<T> read(Future<T> Function() operation) async {
    var batch = _pending;
    if (batch == null || batch.started || batch.fence != _currentFence()) {
      batch = _PendingRead<T>();
      final owned = batch;
      _pending = owned;
      try {
        final scheduled = _enqueue(() async {
          owned.started = true;
          if (identical(_pending, owned)) _pending = null;
          try {
            owned.result.complete(_ReadOutcome<T>.value(await operation()));
          } catch (error, stack) {
            owned.result.complete(_ReadOutcome<T>.error(error, stack));
          }
        });
        // enqueue increments the lock ticket synchronously. Other lock users
        // increment it too, so a read arriving after a mutation cannot jump it.
        owned.fence = _currentFence();
        unawaited(
          scheduled.catchError((Object error, StackTrace stack) {
            if (identical(_pending, owned)) _pending = null;
            if (!owned.result.isCompleted) {
              owned.result.complete(_ReadOutcome<T>.error(error, stack));
            }
          }),
        );
      } catch (error, stack) {
        if (identical(_pending, owned)) _pending = null;
        owned.result.complete(_ReadOutcome<T>.error(error, stack));
      }
    }
    return (await batch.result.future).unwrap();
  }
}

class _PendingRead<T> {
  Object? fence;
  bool started = false;
  final result = Completer<_ReadOutcome<T>>();
}

// Failure values cross error zones; each caller receives the original failure
// in its own zone rather than an unhandled shared error in the first zone.
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
