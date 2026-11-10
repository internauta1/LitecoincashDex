import 'dart:async';

final appShutdown = AppShutdown();

/// App-owned consumers stop before the SDK they depend on. A failed drain
/// keeps the SDK alive and the window open; there is no forced process exit.
class AppShutdown {
  final _stops = <Object, Future<void> Function()>{};
  Future<void>? _stopping;
  bool isClosing = false;
  void beginClosing() => isClosing = true;
  void register(Object owner, FutureOr<void> Function() stop) {
    _stops.putIfAbsent(
      owner,
      () =>
          () => Future<void>.sync(stop),
    );
  }

  void unregister(Object owner) => _stops.remove(owner);
  Future<void> stopConsumers({Duration timeout = const Duration(seconds: 15)}) {
    beginClosing();
    final drain = _stopping ??= _drain().whenComplete(() => _stopping = null);
    return drain.timeout(timeout);
  }

  Future<void> _drain() async {
    while (_stops.isNotEmpty) {
      final batch = Map<Object, Future<void> Function()>.from(_stops);
      await Future.wait(
        batch.entries.map((entry) async {
          await entry.value();
          if (identical(_stops[entry.key], entry.value)) {
            _stops.remove(entry.key);
          }
        }),
      );
    }
  }
}
