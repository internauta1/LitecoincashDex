import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

typedef FetchBalance = Future<BalanceInfo> Function();

enum BalanceConfirmationStatus { cached, loading, retrying, confirmed, failed }

/// Confirmation comes from the supplied fresh read, never a value-only replay.
/// A deadline stops the UI waiting; it does not cancel the underlying read.
class CoinDetailsBalanceConfirmationController extends ChangeNotifier {
  static int _nextDiagnosticId = 0;
  final int _diagnosticId = ++_nextDiagnosticId;
  final Stopwatch _elapsed = Stopwatch()..start();
  BalanceConfirmationStatus? _loggedStatus;
  CoinDetailsBalanceConfirmationController({
    required FetchBalance fetchConfirmedBalance,
    BalanceInfo? initialBalance,
    this.maxStartupRetries = 2,
    this.retryBackoffBase = const Duration(milliseconds: 300),
    this.requestTimeout = const Duration(seconds: 20),
  }) : _fetchConfirmedBalance = fetchConfirmedBalance,
       _latestBalance = initialBalance;
  final FetchBalance _fetchConfirmedBalance;
  final int maxStartupRetries;
  final Duration retryBackoffBase;
  final Duration requestTimeout;
  BalanceInfo? _latestBalance;
  BalanceConfirmationStatus _status = BalanceConfirmationStatus.cached;
  bool _disposed = false;
  int _attempts = 0;
  int _revision = 0;
  Future<BalanceInfo>? _underlying;
  Timer? _retry;
  Timer? _deadline;
  Completer<void>? _attemptDone;

  BalanceInfo? get latestBalance => _latestBalance;
  BalanceConfirmationStatus get status => _status;
  bool get isConfirmed => _status == BalanceConfirmationStatus.confirmed;
  bool get hasFailed => _status == BalanceConfirmationStatus.failed;
  bool get canRetry => !_disposed && _underlying == null && _retry == null;
  bool get isBootstrapping => _status == BalanceConfirmationStatus.loading;
  int get startupRetryAttempts => _attempts > 0 ? _attempts - 1 : 0;

  Future<void> bootstrap() {
    if (_disposed || isConfirmed || _underlying != null || _retry != null) {
      return _attemptDone?.future ?? Future.value();
    }
    return _startAttempt();
  }

  Future<void> _startAttempt() {
    _attempts++;
    final revision = ++_revision;
    final done = Completer<void>();
    _attemptDone = done;
    _status = BalanceConfirmationStatus.loading;
    final read = Future<BalanceInfo>.sync(_fetchConfirmedBalance);
    _underlying = read;
    _deadline = Timer(requestTimeout, () {
      if (_disposed || revision != _revision) return;
      _status = BalanceConfirmationStatus.failed;
      if (!done.isCompleted) done.complete();
      _notify();
    });
    read.then(
      (balance) {
        if (_disposed || revision != _revision) return;
        _deadline?.cancel();
        _underlying = null;
        _latestBalance = balance;
        _status = BalanceConfirmationStatus.confirmed;
        if (!done.isCompleted) done.complete();
        _notify();
      },
      onError: (Object error, StackTrace stack) {
        if (_disposed || revision != _revision) return;
        _deadline?.cancel();
        _underlying = null;
        if (!done.isCompleted) done.complete();
        _scheduleRetry();
      },
    );
    _notify();
    return done.future;
  }

  void _scheduleRetry() {
    if (_disposed || isConfirmed || _underlying != null || _retry != null) {
      return;
    }
    if (_attempts >= maxStartupRetries + 1) {
      _status = BalanceConfirmationStatus.failed;
      _notify();
      return;
    }
    _status = BalanceConfirmationStatus.retrying;
    _retry = Timer(retryBackoffBase * _attempts, () {
      _retry = null;
      if (!_disposed && !isConfirmed) unawaited(_startAttempt());
    });
    _notify();
  }

  Future<void> retry() {
    if (_disposed || _underlying != null || _retry != null) {
      return Future.value();
    }
    _attempts = 0;
    return _startAttempt();
  }

  void onStreamBalance(BalanceInfo balance) {
    if (_disposed) return;
    _latestBalance = balance;
    _notify();
  }

  Future<void> onStartupStreamError() async {
    if (_disposed || _underlying != null || isConfirmed) return;
    _scheduleRetry();
  }

  void _notify() {
    if (!_disposed) {
      if (_loggedStatus != _status) {
        _loggedStatus = _status;
        Logger('BalanceConfirmation').info(
          'Balance confirmation id=$_diagnosticId attempt=$_attempts status=${_status.name} elapsed_ms=${_elapsed.elapsedMilliseconds}',
        );
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _retry?.cancel();
    _deadline?.cancel();
    if (_attemptDone?.isCompleted == false) _attemptDone!.complete();
    super.dispose();
  }
}
