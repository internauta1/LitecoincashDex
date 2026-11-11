import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/nft.dart';

enum NftProviderFailure { disabled, unavailable, invalidResponse, timeout }

class NftProviderUnavailable extends BaseError {
  const NftProviderUnavailable(this.reason);
  final NftProviderFailure reason;
  @override
  String get message => 'NFT service is unavailable. Try again later.';
  @override
  String toString() => 'NftProviderUnavailable(${reason.name})';
}

abstract interface class NftProviderStatus {
  Future<void> ensureAvailable(NftBlockchains chain);
}

/// Checks only the already configured provider with a fixed public zero ID.
/// KDF may silently accept a provider message without `result` as an empty
/// cache. This capability check prevents that from certifying an empty wallet.
/// It never uses a wallet address, credentials, redirects or insecure TLS.
class NftProviderAvailability implements NftProviderStatus {
  NftProviderAvailability({
    http.Client Function()? clientFactory,
    this.deadline = const Duration(seconds: 6),
    DateTime Function()? clock,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _clock = clock ?? DateTime.now;
  final http.Client Function() _clientFactory;
  final DateTime Function() _clock;
  final Duration deadline;
  final _pending = <NftBlockchains, Future<void>>{};
  final _checked =
      <NftBlockchains, ({DateTime at, NftProviderUnavailable? error})>{};

  @override
  Future<void> ensureAvailable(NftBlockchains chain) {
    final cached = _checked[chain];
    final age = cached == null ? null : _clock().difference(cached.at);
    if (cached != null &&
        age != null &&
        !age.isNegative &&
        age < const Duration(seconds: 30)) {
      return cached.error == null
          ? Future.value()
          : Future.error(cached.error!);
    }
    return _pending[chain] ??= _check(chain).whenComplete(() {
      _pending.remove(chain);
    });
  }

  Future<void> _check(NftBlockchains chain) async {
    final client = _clientFactory();
    NftProviderUnavailable? failure;
    try {
      await _request(client, chain).timeout(deadline);
    } on NftProviderUnavailable catch (error) {
      failure = error;
    } on TimeoutException {
      failure = const NftProviderUnavailable(NftProviderFailure.timeout);
    } catch (_) {
      failure = const NftProviderUnavailable(NftProviderFailure.unavailable);
    } finally {
      client.close();
    }
    _checked[chain] = (at: _clock(), error: failure);
    if (failure != null) throw failure;
  }

  Future<void> _request(http.Client client, NftBlockchains chain) async {
    final name = switch (chain) {
      NftBlockchains.eth => 'ETH',
      NftBlockchains.bsc => 'BSC',
      NftBlockchains.avalanche => 'AVALANCHE',
      _ => throw const NftProviderUnavailable(NftProviderFailure.unavailable),
    };
    final zero = '0x${List.filled(40, '0').join()}';
    final request = http.Request(
      'GET',
      Uri.https('moralis.gleec.com', '/api/v2/$zero/nft', {
        'chain': name,
        'format': 'decimal',
      }),
    )..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw const NftProviderUnavailable(NftProviderFailure.unavailable);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 65536) {
        throw const NftProviderUnavailable(NftProviderFailure.invalidResponse);
      }
      bytes.addAll(chunk);
    }
    Object? data;
    try {
      data = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const NftProviderUnavailable(NftProviderFailure.invalidResponse);
    }
    if (data is! Map || data['error'] != null || data['result'] is! List) {
      final disabled =
          data is Map && data['message'] == 'NFT feature termporary disabled.';
      throw NftProviderUnavailable(
        disabled
            ? NftProviderFailure.disabled
            : NftProviderFailure.invalidResponse,
      );
    }
  }
}
