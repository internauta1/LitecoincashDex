import 'dart:convert';
import 'events/kdf_event.dart';

enum SseStage {
  connecting,
  handshake,
  registered,
  received,
  decoded,
  parsed,
  published,
  rejected,
  ignored,
  consumed,
  rendered,
  disconnected,
}

enum SseEventKind { heartbeat, other }

enum SseReason {
  manual,
  preflight,
  handshake,
  connection,
  transport,
  serverClosed,
  staleGeneration,
  invalidJson,
  invalidEvent,
  invalidHeartbeat,
  unknownType,
  emptyEvent,
  incompleteFrame,
}

/// Opt-in diagnostics with fixed labels, local counters and UTC observations.
class SseDiagnostics {
  SseDiagnostics(this._write);

  /// Installed by the validated experimental entry point only.
  static SseDiagnostics? isolatedRun;
  final void Function(String) _write;
  final _counts = <SseStage, int>{};
  final _origins = Expando<({SseConnectionTrace connection, int frame})>();
  int _connections = 0;
  Map<SseStage, int> get counts => Map.unmodifiable(_counts);
  SseConnectionTrace connect() {
    final connection = SseConnectionTrace._(this, ++_connections);
    connection.record(SseStage.connecting);
    return connection;
  }

  void published(KdfEvent event, SseConnectionTrace connection, int frame) {
    if (event is HeartbeatEvent) {
      _origins[event] = (connection: connection, frame: frame);
    }
    connection.record(
      SseStage.published,
      frame: frame,
      kind: event is HeartbeatEvent
          ? SseEventKind.heartbeat
          : SseEventKind.other,
    );
  }

  void heartbeatConsumed(HeartbeatEvent event) {
    final origin = _origins[event];
    origin?.connection.record(
      SseStage.consumed,
      frame: origin.frame,
      kind: SseEventKind.heartbeat,
    );
  }

  void rendered(HeartbeatEvent event) {
    final origin = _origins[event];
    if (origin == null) return;
    _origins[event] = null;
    origin.connection.record(
      SseStage.rendered,
      frame: origin.frame,
      kind: SseEventKind.heartbeat,
    );
  }

  void _record(
    int connection,
    SseStage stage,
    int? frame,
    SseReason? reason,
    SseEventKind? kind,
  ) {
    final count = _counts.update(
      stage,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    try {
      final record = {
        'utc': DateTime.now().toUtc().toIso8601String(),
        'connection': connection,
        if (frame != null) 'frame': frame,
        'stage': stage.name,
        if (kind != null) 'kind': kind.name,
        if (reason != null) 'reason': reason.name,
        'count': count,
      };
      _write('LCC_SSE ${jsonEncode(record)}');
    } catch (_) {
      // Observing a frame must never interfere with the wallet or its stream.
    }
  }
}

class SseConnectionTrace {
  SseConnectionTrace._(this.diagnostics, this.id);
  final SseDiagnostics diagnostics;
  final int id;
  int _frames = 0;
  int nextFrame() => ++_frames;
  void record(
    SseStage stage, {
    int? frame,
    SseReason? reason,
    SseEventKind? kind,
  }) => diagnostics._record(id, stage, frame, reason, kind);
}

/// Internal transport envelope. The payload is never passed to diagnostics.
class TracedSseFrame {
  const TracedSseFrame(this.frame, this.payload);
  final int frame;
  final Object? payload;
}
