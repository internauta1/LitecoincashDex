import 'dart:convert';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/testing/isolated_wallet_test_mode.dart';

enum HeartbeatProbeStage { blocked, requested, enabled, failed }

enum HeartbeatProbeReason {
  invoked,
  scope,
  disconnected,
  sessionChanged,
  alreadyRequested,
  walletMismatch,
  deadline,
  acknowledgement,
  transport,
  pending,
}

class HeartbeatProbeDiagnostic {
  HeartbeatProbeDiagnostic(
    this.stage,
    this.reason,
    this.generation,
    this.connection,
  );
  final String stage;
  final HeartbeatProbeReason? reason;
  final int? generation;
  final int? connection;
  Map<String, Object?> toJson() => {
    'utc': DateTime.now().toUtc().toIso8601String(),
    'stage': stage,
    if (reason != null) 'reason': reason!.name,
    if (generation != null) 'generation': generation,
    if (connection != null) 'connection': connection,
  };
}

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
    this.sessionChanges,
    this.connectionId,
    this.diagnostic,
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
        diagnostic: (entry) => diagnosticSink?.call(entry),
        sessionChanges: sdk.auth.watchSessionContext(),
        connectionId: () => registeredConnection,
      );

  static void Function(HeartbeatProbeStage)? evidenceSink;
  static void Function(HeartbeatProbeDiagnostic)? diagnosticSink;
  static int? registeredConnection;

  /// Receives the fixed metadata emitted by the SSE diagnostics, never frames.
  static void observeSseMetadata(String line) {
    if (!line.startsWith('LCC_SSE ')) return;
    final row = jsonDecode(line.substring(8)) as Map<String, dynamic>;
    final id = row['connection'];
    if (id is! int) return;
    if (row['stage'] == 'connecting') registeredConnection = null;
    if (row['stage'] == 'registered') registeredConnection = id;
    if (row['stage'] == 'disconnected' && registeredConnection == id) {
      registeredConnection = null;
    }
  }

  final bool Function() scopeApproved;
  final Future<Object> Function() captureSession;
  final void Function(Object) ensureCurrent;
  final bool Function() isConnected;
  final Future<bool> Function() knownDisposableWallet;
  final Future<String> Function() enable;
  final void Function(HeartbeatProbeStage)? record;
  final Stream<Object?>? sessionChanges;
  final int? Function()? connectionId;
  final void Function(HeartbeatProbeDiagnostic)? diagnostic;
  HeartbeatProbeReason? lastReason;
  final _claimedSessions = <Object>{};
  Future<HeartbeatProbeStage>? _pending;

  Future<HeartbeatProbeStage> start() {
    lastReason = null;
    _observe('invoked', HeartbeatProbeReason.invoked);
    if (_pending != null) {
      _observe('pending', HeartbeatProbeReason.pending);
      return _pending!;
    }
    var expired = false;
    return _pending = _start(() => !expired)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            expired = true;
            _record(
              HeartbeatProbeStage.failed,
              reason: HeartbeatProbeReason.deadline,
            );
            return HeartbeatProbeStage.failed;
          },
        )
        .whenComplete(() => _pending = null);
  }

  void _observe(String stage, HeartbeatProbeReason? reason, [Object? session]) {
    lastReason = reason;
    try {
      diagnostic?.call(
        HeartbeatProbeDiagnostic(
          stage,
          reason,
          session is AuthSessionContext ? session.epoch : null,
          connectionId?.call(),
        ),
      );
    } on Object {
      /* Diagnostics never authorize or alter a request. */
    }
  }

  void _record(
    HeartbeatProbeStage stage, {
    HeartbeatProbeReason? reason,
    Object? session,
  }) {
    _observe(stage.name, reason, session);
    try {
      record?.call(stage);
    } on Object {
      /* Metadata must not affect RPC. */
    }
  }

  Future<HeartbeatProbeStage> _start(bool Function() alive) async {
    try {
      if (!scopeApproved()) {
        _record(
          HeartbeatProbeStage.blocked,
          reason: HeartbeatProbeReason.scope,
        );
        return HeartbeatProbeStage.blocked;
      }
      if (!isConnected()) {
        _record(
          HeartbeatProbeStage.blocked,
          reason: HeartbeatProbeReason.disconnected,
        );
        return HeartbeatProbeStage.blocked;
      }
      final connection = connectionId?.call();
      final session = await captureSession();
      ensureCurrent(session);
      if (!alive()) return HeartbeatProbeStage.failed;
      if (_claimedSessions.contains(session)) {
        _record(
          HeartbeatProbeStage.blocked,
          reason: HeartbeatProbeReason.alreadyRequested,
          session: session,
        );
        return HeartbeatProbeStage.blocked;
      }
      final known = await knownDisposableWallet();
      ensureCurrent(session);
      if (!scopeApproved()) {
        _record(
          HeartbeatProbeStage.blocked,
          reason: HeartbeatProbeReason.scope,
          session: session,
        );
        return HeartbeatProbeStage.blocked;
      }
      if (!alive() || !known || !scopeApproved() || !isConnected()) {
        _record(
          HeartbeatProbeStage.blocked,
          reason: !known
              ? HeartbeatProbeReason.walletMismatch
              : HeartbeatProbeReason.disconnected,
          session: session,
        );
        return HeartbeatProbeStage.blocked;
      }
      if (connectionId != null &&
          (connection == null || connection != connectionId!())) {
        _record(
          HeartbeatProbeStage.blocked,
          reason: HeartbeatProbeReason.disconnected,
          session: session,
        );
        return HeartbeatProbeStage.blocked;
      }
      // Never retry an uncertain request: it could have reached the KDF.
      _claimedSessions.add(session);
      _record(HeartbeatProbeStage.requested, session: session);
      final id = await enable();
      ensureCurrent(session);
      if (!alive()) return HeartbeatProbeStage.failed;
      final result = id == 'HEARTBEAT'
          ? HeartbeatProbeStage.enabled
          : HeartbeatProbeStage.failed;
      _record(
        result,
        reason: result == HeartbeatProbeStage.failed
            ? HeartbeatProbeReason.acknowledgement
            : null,
        session: session,
      );
      // Enabled is an RPC acknowledgement, never proof of event delivery.
      return result;
    } on WalletChangedDisconnectException {
      _record(
        HeartbeatProbeStage.blocked,
        reason: HeartbeatProbeReason.sessionChanged,
      );
      return HeartbeatProbeStage.blocked;
    } on Object {
      _record(
        HeartbeatProbeStage.failed,
        reason: HeartbeatProbeReason.transport,
      );
      return HeartbeatProbeStage.failed;
    }
  }
}
