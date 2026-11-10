import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/coins_bloc/wallet_coin_projection.dart';
import 'package:web_dex/model/coin.dart';
import '../test_units/tests/utils/test_util.dart';

void main() {
  test('inactive catalog and active wallet remain distinct sources', () {
    final catalog = setCoin(coinAbbr: 'LCC-segwit');
    final active = catalog.copyWith(state: CoinState.active);
    final projected = projectWalletCoinStates(
      [catalog],
      {'LCC-segwit': active},
    );
    expect(catalog.isInactive, isTrue);
    expect(projected.single.isActive, isTrue);
    expect(projected.single.id, catalog.id);
    expect(projected.single.walletOnly, catalog.walletOnly);
  });
  test('no wallet entry can never be inferred active from a catalog', () {
    final stale = setCoin(coinAbbr: 'LCC').copyWith(state: CoinState.active);
    expect(projectWalletCoinStates([stale], {}).single.isInactive, isTrue);
    expect(walletCoinForTicker({}, 'LCC'), isNull);
  });
  test('variants are not merged and ticker mismatches fail closed', () {
    final native = setCoin(coinAbbr: 'LCC');
    final segwit = setCoin(
      coinAbbr: 'LCC-segwit',
    ).copyWith(state: CoinState.active);
    final result = projectWalletCoinStates(
      [native, segwit],
      {'LCC-segwit': segwit},
    );
    expect(result.first.isInactive, isTrue);
    expect(result.last.isActive, isTrue);
    expect(walletCoinForTicker({'LCC': segwit}, 'LCC'), isNull);
    expect(
      projectWalletCoinStates([native], {'LCC': segwit}).single.isInactive,
      isTrue,
    );
  });
  test('activating and suspended states do not become active', () {
    final catalog = setCoin(coinAbbr: 'LCC');
    for (final state in [
      CoinState.activating,
      CoinState.suspended,
      CoinState.inactive,
    ]) {
      final projected = projectWalletCoinStates(
        [catalog],
        {'LCC': catalog.copyWith(state: state)},
      ).single;
      expect(projected.state, state);
      expect(projected.isActive, isFalse);
    }
  });
}
