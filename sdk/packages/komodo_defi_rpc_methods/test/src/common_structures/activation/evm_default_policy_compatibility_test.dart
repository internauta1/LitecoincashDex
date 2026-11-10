import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

// Both the classic client and KDF's defaulted policy accept omission. Older
// KDFs reject {"type":"ContextPrivKey"} before any chain RPC is performed.
Map<String, dynamic> config(String ticker) => {
  'coin': ticker,
  'nodes': [
    {'url': 'https://rpc.invalid'},
  ],
  'swap_contract_address': '0x0000000000000000000000000000000000000001',
  'fallback_swap_contract': '0x0000000000000000000000000000000000000002',
};

void main() {
  for (final ticker in ['ETH', 'BNB', 'AVAX']) {
    test('$ticker software activation leaves policy to the KDF default', () {
      final params = EthWithTokensActivationParams.fromJson(config(ticker));
      expect(params.toRpcParams().containsKey('priv_key_policy'), isFalse);
      expect(
        params.copyWith(txHistory: true).toRpcParams()['tx_history'],
        true,
      );
      expect(params.toRpcParams()['nodes'], [
        {'url': 'https://rpc.invalid', 'komodo_proxy': false},
      ]);
    });
  }

  test(
    'ERC20 default and nullable policies omit the field instead of null',
    () {
      final params = Erc20ActivationParams.fromJsonConfig(config('TOKEN'));
      expect(params.toRpcParams().containsKey('priv_key_policy'), isFalse);
      expect(
        EthWithTokensActivationParams(
          nodes: params.nodes,
          swapContractAddress: params.swapContractAddress,
          fallbackSwapContract: params.fallbackSwapContract,
          erc20Tokens: [],
          txHistory: null,
          privKeyPolicy: null,
        ).toRpcParams().containsKey('priv_key_policy'),
        isFalse,
      );
    },
  );

  test('explicit hardware policy is preserved and never downgraded', () {
    final params = EthWithTokensActivationParams.fromJson(config('ETH'));
    expect(
      params
          .copyWith(privKeyPolicy: const PrivateKeyPolicy.trezor())
          .toRpcParams()['priv_key_policy'],
      {'type': 'Trezor'},
    );
    expect(
      Erc20ActivationParams.fromJsonConfig({
        ...config('TOKEN'),
        'priv_key_policy': 'Trezor',
      }).toRpcParams()['priv_key_policy'],
      {'type': 'Trezor'},
    );
  });
}
