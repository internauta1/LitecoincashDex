import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

enum WalletLoginMetadataStatus { loading, ready, unavailable }

/// Wallet settings must be confirmed before choosing a derivation mode.
/// A timeout ends the visual wait, but never starts a second concurrent read.
class WalletLoginMetadata extends ChangeNotifier {
  WalletLoginMetadata({
    required Future<KdfUser?> Function() read,
    Future<bool?> Function()? readHdPreference,
    this.timeout = const Duration(seconds: 35),
  }) : _read = read,
       _readHdPreference = readHdPreference ?? (() async => null);

  final Future<KdfUser?> Function() _read;
  final Future<bool?> Function() _readHdPreference;
  final Duration timeout;
  static final _log = Logger('WalletLoginMetadata');
  static int _nextDiagnosticId = 0;
  final int _diagnosticId = ++_nextDiagnosticId;
  int _attempt = 0;
  final _elapsed = Stopwatch();
  WalletLoginMetadataStatus status = WalletLoginMetadataStatus.loading;
  KdfUser? user;
  bool? hdPreference;
  bool _pending = false;
  bool _disposed = false;
  Timer? _deadline;

  bool get canRetry => !_pending && !_disposed;

  Future<void> load() async {
    if (_disposed || _pending) return;
    _pending = true;
    _attempt++;
    _elapsed
      ..reset()
      ..start();
    user = null;
    hdPreference = null;
    status = WalletLoginMetadataStatus.loading;
    _notify();
    _deadline = Timer(timeout, () {
      if (_disposed) return;
      status = WalletLoginMetadataStatus.unavailable;
      _log.warning('Wallet settings read exceeded its display deadline');
      _notify();
    });
    try {
      final (result, preference) = await (_read(), _readHdPreference()).wait;
      if (_disposed) return;
      user = result;
      hdPreference = preference;
      status = result == null
          ? WalletLoginMetadataStatus.unavailable
          : WalletLoginMetadataStatus.ready;
    } catch (_) {
      if (_disposed) return;
      // Do not log an exception or wallet data. TCP refusal remains a failure;
      // it must never become an assumed wallet type or authentication proof.
      status = WalletLoginMetadataStatus.unavailable;
      _log.warning('Wallet settings could not be confirmed');
    } finally {
      _deadline?.cancel();
      _pending = false;
      if (!_disposed) _notify();
    }
  }

  void _notify() {
    _log.info(
      'Wallet login settings id=$_diagnosticId attempt=$_attempt '
      'status=${status.name} elapsed_ms=${_elapsed.elapsedMilliseconds}',
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _deadline?.cancel();
    super.dispose();
  }
}
