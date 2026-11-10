/// Fixed categories only: never retain a request, credentials or raw cause.
enum KdfTransportFailure {
  ownershipUnverified,
  generationUnavailable,
  timeout,
  socket,
  http,
  unknown,
}

/// A transport failure is not evidence of a changed wallet identity.
class KdfTransportException implements Exception {
  const KdfTransportException(this.reason);
  final KdfTransportFailure reason;
  @override
  String toString() => 'KdfTransportException(${reason.name})';
}

enum KdfTcpOwnershipCheck { listener, connection }

enum KdfTcpOwnershipEvidence { missing, foreign, unavailable }

/// A failed ownership proof with no socket, address, or request data.
class KdfTcpOwnershipException extends KdfTransportException {
  const KdfTcpOwnershipException(this.check, this.evidence)
    : super(KdfTransportFailure.ownershipUnverified);
  final KdfTcpOwnershipCheck check;
  final KdfTcpOwnershipEvidence evidence;
}
