import 'dart:async';
import 'package:flutter/foundation.dart';
import 'best_offers.dart';

/// Read-only state. No activation, authentication or trade commands live here.
class BestOffersController extends ChangeNotifier {
  BestOffersController(
    this.repository, {
    this.interval = const Duration(seconds: 45),
    this.retryDelay = const Duration(seconds: 10),
  });
  final BestOffersRepository repository;
  final Duration interval;
  final Duration retryDelay;
  BestOffersQuery? query;
  BestOffersSnapshot? snapshot;
  bool loading = false;
  bool failed = false;
  bool _disposed = false;
  int _revision = 0;
  Timer? _timer;
  Future<void>? _pending;
  int? _pendingRevision;
  DateTime? _retryAfter;

  void configure(BestOffersQuery? value) {
    if (query?.key == value?.key) return;
    _revision++;
    _timer?.cancel();
    _retryAfter = null;
    query = value;
    snapshot = null;
    failed = false;
    loading = false;
    notifyListeners();
    if (value != null) unawaited(refresh());
  }

  Future<void> refresh() async {
    final current = query;
    final revision = _revision;
    if (_disposed || current == null) return;
    if (_pending != null) {
      final sameRevision = _pendingRevision == revision;
      await _pending;
      if (sameRevision) return;
    }
    if (_disposed || revision != _revision) return;
    if (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)) return;
    loading = true;
    notifyListeners();
    bool owns() => !_disposed && revision == _revision;
    final task = () async {
      try {
        final result = await repository.fetch(current);
        if (!owns()) return;
        snapshot = result;
        failed = false;
      } catch (_) {
        if (!owns()) return;
        failed = true;
        _retryAfter = DateTime.now().add(retryDelay);
      } finally {
        if (owns()) {
          loading = false;
          notifyListeners();
          _timer?.cancel();
          _timer = Timer(interval, () => unawaited(refresh()));
        }
      }
    }();
    _pending = task;
    _pendingRevision = revision;
    await task;
    if (identical(_pending, task)) _pending = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _timer?.cancel();
    super.dispose();
  }
}
