part of 'kdf_event.dart';

/// Heartbeat event from stream::heartbeat::enable
class HeartbeatEvent extends KdfEvent {
  HeartbeatEvent({required this.timestamp});

  @override
  EventTypeString get typeEnum => EventTypeString.heartbeat;

  factory HeartbeatEvent.fromJson(JsonMap json) {
    return HeartbeatEvent(
      timestamp: json.isEmpty ? null : json.value<int>('timestamp'),
    );
  }

  /// Producer timestamp when supplied. The KDF heartbeat can be an empty object.
  final int? timestamp;

  @override
  String toString() => 'HeartbeatEvent(timestamp: $timestamp)';
}
