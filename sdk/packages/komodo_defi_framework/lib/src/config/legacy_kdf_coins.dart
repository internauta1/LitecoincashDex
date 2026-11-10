import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// KDF 2.4's ETH protocol is a unit variant. Its chain_id belongs at the coin
/// root; newer registries duplicate it under protocol_data, which 2.4 rejects.
/// Only the known, lossless shape is adapted. Application registry data stays
/// untouched, and structured token/NFT protocols retain their required data.
JsonList coinsForLegacyKdf(JsonList coins) => [
  for (final coin in coins) _legacyCoin(coin),
];

JsonMap _legacyCoin(JsonMap coin) {
  final protocol = coin['protocol'];
  if (protocol is! Map || protocol['type'] != 'ETH' ||
      !protocol.containsKey('protocol_data')) return coin;
  final data = protocol['protocol_data'];
  if (data is! Map || data.keys.any((key) => key != 'chain_id')) {
    throw UnsupportedError('Unsupported structured ETH protocol for legacy KDF');
  }
  final nestedId = data['chain_id'];
  final rootId = coin['chain_id'];
  if (nestedId != null && rootId != null && nestedId != rootId) {
    throw ArgumentError('Conflicting ETH chain identifiers');
  }
  final chainId = rootId ?? nestedId;
  if (chainId is! int || chainId <= 0) {
    throw ArgumentError('Positive ETH chain identifier required');
  }
  return {
    ...coin,
    'chain_id': chainId,
    'protocol': Map<String, dynamic>.from(protocol)..remove('protocol_data'),
  };
}
