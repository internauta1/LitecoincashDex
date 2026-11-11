import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/testing/isolated_wallet_test_mode.dart';

enum HeartbeatProbeStage { blocked, requested, enabled, failed }

/// Disposable-runner diagnostic only. Credentials remain inside the SDK.
class IsolatedHeartbeatProbe {
  IsolatedHeartbeatProbe({
    required this.scopeApproved,
    required this.captureSession,
    required this.ensureCurrent,
    required this.isConnected,
    required this.knownDisposableWallet,
    required this.enable,
    this.record,
  });

  factory IsolatedHeartbeatProbe.fromSdk(KomodoDefiSdk sdk) =>
      IsolatedHeartbeatProbe(
        scopeApproved: () =>
            const bool.fromEnvironment('LCC_NEXT_ISOLATED') &&
            kDefaultKdfRpcPort == 17993 &&
            IsolatedWalletTestMode.enabled &&
            SseDiagnostics.isolatedRun != null,
        captureSession: () => sdk.auth.captureSessionContext(),
        ensureCurrent: (session) =>
            sdk.auth.ensureSessionContextCurrent(session as AuthSessionContext),
        isConnected: () => sdk.streaming.isConnected,
        knownDisposableWallet: () async {
          final names = await sdk.client.rpc.wallet.getWalletNames();
          const name = 'codex_disposable_20261104';
          return names.activatedWallet == name &&
              names.walletNames.isNotEmpty &&
              names.walletNames.every((value) => value == name);
        },
        enable: () async => (await sdk.client.rpc.streaming.enableHeartbeat(
          clientId: 0,
          config: const StreamConfig(streamIntervalSeconds: 5),
          alwaysSend: true,
        )).streamerId,
        record: (stage) => evidenceSink?.call(stage),
      );

  static void Function(HeartbeatProbeStage)? evidenceSink;
  final bool Function() scopeApproved;
  final Future<Object> Function() captureSession;
  final void Function(Object) ensureCurrent;
  final bool Function() isConnected;
  final Future<bool> Function() knownDisposableWallet;
  final Future<String> Function() enable;
  final void Function(HeartbeatProbeStage)? record;
  final _claimedSessions = <Object>{};
  Future<HeartbeatProbeStage>? _pending;

  Future<HeartbeatProbeStage> start() {
    if (_pending != null) return _pending!;
    var expired = false;
    return _pending = _start(() => !expired)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            expired = true;
            _record(HeartbeatProbeStage.failed);
            return HeartbeatProbeStage.failed;
          },
        )
        .whenComplete(() => _pending = null);
  }

  void _record(HeartbeatProbeStage stage) {
    try {
      record?.call(stage);
    } on Object {
      /* Metadata must not affect RPC. */
    }
  }

  Future<HeartbeatProbeStage> _start(bool Function() alive) async {
    try {
      if (!scopeApproved() || !isConnected()) {
        _record(HeartbeatProbeStage.blocked);
        return HeartbeatProbeStage.blocked;
      }
      final session = await captureSession();
      ensureCurrent(session);
      if (!alive() || _claimedSessions.contains(session)) {
        return HeartbeatProbeStage.blocked;
      }
      final known = await knownDisposableWallet();
      ensureCurrent(session);
      if (!alive() || !known || !scopeApproved() || !isConnected()) {
        _record(HeartbeatProbeStage.blocked);
        return HeartbeatProbeStage.blocked;
      }
      // Never retry an uncertain request: it could have reached the KDF.
      _claimedSessions.add(session);
      _record(HeartbeatProbeStage.requested);
      final id = await enable();
      ensureCurrent(session);
      if (!alive()) return HeartbeatProbeStage.failed;
      final result = id == 'HEARTBEAT'
          ? HeartbeatProbeStage.enabled
          : HeartbeatProbeStage.failed;
      _record(result);
      // Enabled is an RPC acknowledgement, never proof of event delivery.
      return result;
    } on Object {
      _record(HeartbeatProbeStage.failed);
      return HeartbeatProbeStage.failed;
    }
  }
}
