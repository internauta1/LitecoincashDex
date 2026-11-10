import 'package:web_dex/model/coin.dart';

/// Catalog entries describe assets, not activation. Only the current wallet's
/// projection can supply a live state; missing or mismatched entries stay off.
List<Coin> projectWalletCoinStates(
  Iterable<Coin> catalog,
  Map<String, Coin> walletCoins,
) => catalog.map((coin) {
  final current = walletCoins[coin.id.id];
  final matches =
      current != null && current.id == coin.id && current.abbr == coin.abbr;
  final state = matches ? current.state : CoinState.inactive;
  return coin.state == state ? coin : coin.copyWith(state: state);
}).toList();

Coin? walletCoinForTicker(Map<String, Coin> walletCoins, String ticker) {
  final coin = walletCoins[ticker];
  return coin != null && coin.abbr == ticker && coin.id.id == ticker
      ? coin
      : null;
}
