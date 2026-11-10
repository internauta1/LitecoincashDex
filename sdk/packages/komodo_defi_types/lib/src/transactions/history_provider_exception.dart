enum HistoryProviderFailure {
  unavailable,
  timeout,
  invalidResponse,
  unsupported,
}

/// Metadata only: never retains request URLs, wallet addresses or response bodies.
class HistoryProviderException implements Exception {
  const HistoryProviderException(this.reason, {this.statusCode});
  final HistoryProviderFailure reason;
  final int? statusCode;
  @override
  String toString() => 'Transaction history provider unavailable';
}
