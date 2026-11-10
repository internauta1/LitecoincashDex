import 'dart:async';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import '../test_units/tests/utils/test_util.dart';

class _Sdk extends Mock implements KomodoDefiSdk {}

class _Assets extends Mock implements AssetManager {}

class _Selection extends Mock implements WalletAssetSelection {}

class _Market extends Mock implements MarketDataManager {}

class _Policy extends Mock implements TradingStatusService {}

class _Arrr extends Mock implements ArrrActivationService {}

class _Auth extends Mock implements KomodoDefiLocalAuth {}

class _QuoteRepo extends Mock implements CoinsRepo {}

void main() {
  setUpAll(() => registerFallbackValue(<Asset>[]));
  final asset = Asset.fromJson({
    'coin': 'ETH',
    'type': 'ETH',
    'fname': 'Ethereum',
    'chain_id': 1,
    'is_testnet': false,
    'nodes': [
      {'url': 'https://rpc.invalid'},
    ],
    'swap_contract_address': '0x0000000000000000000000000000000000000001',
    'fallback_swap_contract': '0x0000000000000000000000000000000000000001',
  });
  late _Sdk sdk;
  late _Assets assets;
  late _Selection selection;
  late _Market market;
  late _Policy policy;
  late CoinsRepo repo;
  setUp(() {
    sdk = _Sdk();
    assets = _Assets();
    selection = _Selection();
    market = _Market();
    policy = _Policy();
    when(() => sdk.assets).thenReturn(assets);
    when(() => assets.available).thenReturn({asset.id: asset});
    when(() => assets.findAssetsByConfigId('ETH')).thenReturn({asset});
    when(() => sdk.walletAssets).thenReturn(selection);
    when(() => selection.current).thenReturn({});
    when(() => selection.changes).thenAnswer((_) => const Stream.empty());
    when(() => sdk.marketData).thenReturn(market);
    when(
      () => sdk.watchActivationStates(),
    ).thenAnswer((_) => const Stream.empty());
    when(() => sdk.activationStates).thenReturn({});
    when(() => policy.statusStream).thenAnswer((_) => const Stream.empty());
    when(
      () => policy.filterAllowedAssets(any()),
    ).thenAnswer((i) => i.positionalArguments.single as List<Asset>);
    when(
      () => sdk.auth,
    ).thenThrow(StateError('authenticated reads are deliberately unavailable'));
    when(
      () => sdk.balances,
    ).thenThrow(StateError('balances are deliberately unavailable'));
    when(
      () => market.maybeFiatPrice(asset.id),
    ).thenAnswer((_) async => Decimal.parse('0.0015'));
    when(
      () => market.priceChange24h(asset.id),
    ).thenAnswer((_) async => Decimal.one);
    repo = CoinsRepo(
      kdfSdk: sdk,
      mm2: mm2,
      tradingStatusService: policy,
      arrrActivationService: _Arrr(),
    );
    addTearDown(repo.dispose);
  });
  for (final selected in [false, true]) {
    test(
      'public unit quote loads without auth or balances (local selection: $selected)',
      () async {
        when(() => selection.current).thenReturn(selected ? {'ETH'} : {});
        final quotes = await repo.fetchCurrentPrices();
        expect(quotes!['ETH']!.price, Decimal.parse('0.0015'));
        expect(quotes['ETH']!.change24h, Decimal.one);
        verifyNever(() => sdk.auth);
        verifyNever(() => sdk.balances);
      },
    );
  }
  test(
    'no eligible assets returns an empty snapshot without a zero-sized chunk error',
    () async {
      when(() => policy.filterAllowedAssets(any())).thenReturn([]);
      expect(await repo.fetchCurrentPrices(), isEmpty);
      verifyNever(() => market.maybeFiatPrice(asset.id));
    },
  );
  test(
    'unavailable price is not fabricated as zero; earlier valid quote is retained',
    () async {
      final first = await repo.fetchCurrentPrices();
      when(() => market.maybeFiatPrice(asset.id)).thenAnswer((_) async => null);
      final next = await repo.fetchCurrentPrices();
      expect(first!['ETH']!.price, Decimal.parse('0.0015'));
      expect(next!['ETH']!.price, Decimal.parse('0.0015'));
    },
  );
  test('zero wallet amount and the public unit price remain distinct', () {
    final coin = setCoin(
      coinAbbr: 'LCC',
      usdPrice: 0.0015,
      change24h: 1,
      balance: 0,
    );
    final state = CoinsState(
      coins: {'LCC': coin},
      walletCoins: {'LCC': coin},
      pubkeys: {},
      prices: {'LCC': coin.usdPrice!},
    );
    expect(state.getPriceForAsset(coin.id)!.price, Decimal.parse('0.0015'));
    expect(state.getUsdPriceForAmount(0, 'LCC'), 0);
    expect(state.getUsdPriceForAmount(1000, 'LCC'), 1.5);
    expect(state.get24hChangeForAsset(coin.id), 1);
    expect(state.copyWith(prices: {}).getPriceForAsset(coin.id), isNull);
  });
  test(
    'CoinsStarted publishes unit quotes before a blocked auth read; late auth after close adds no event',
    () async {
      final auth = _Auth();
      final identity = Completer<KdfUser?>();
      when(() => sdk.auth).thenReturn(auth);
      when(() => auth.currentUser).thenAnswer((_) => identity.future);
      final quoteRepo = _QuoteRepo();
      final changes = StreamController<Coin>.broadcast();
      final coin = setCoin(coinAbbr: 'LCC', usdPrice: 0.0015);
      when(
        () => quoteRepo.watchCoinActivationState(),
      ).thenAnswer((_) => const Stream.empty());
      when(() => quoteRepo.balanceChanges).thenReturn(changes);
      when(() => quoteRepo.getKnownCoinsMap()).thenReturn({'LCC': coin});
      when(
        () => quoteRepo.fetchCurrentPrices(),
      ).thenAnswer((_) async => {'LCC': coin.usdPrice!});
      final bloc = CoinsBloc(sdk, quoteRepo, policy);
      final published = bloc.stream.firstWhere(
        (s) => s.getPriceForAsset(coin.id)?.price == Decimal.parse('0.0015'),
      );
      bloc.add(CoinsStarted());
      await published.timeout(const Duration(seconds: 2));
      expect(identity.isCompleted, isFalse);
      await bloc.close();
      identity.complete(null);
      await Future<void>.delayed(Duration.zero);
      await changes.close();
    },
  );
}
