import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' hide BestOrder;
import 'package:mocktail/mocktail.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/app_shutdown.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/data_from_service.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/services/best_orders/best_offers.dart';
import 'best_offers_test.dart'
    show PendingOffers, fixtureQuery, fixtureOrder, fixtureResponse;

class _Sdk extends Mock implements KomodoDefiSdk {}

class _Auth extends Mock implements KomodoDefiLocalAuth {}

class _Coins extends Mock implements CoinsRepo {}

class _Coin extends Mock implements Coin {}

class _Analytics extends Mock implements AnalyticsBloc {}

class _Dex extends Mock implements DexRepository {}

void main() {
  late _Sdk sdk;
  late _Auth auth;
  late _Coins coins;
  late _Dex dex;
  late PendingOffers repository;
  late TakerBloc bloc;
  late StreamController<KdfUser?> users;
  late int generation;
  late Map<String, Coin> walletCoins;
  setUpAll(() => registerFallbackValue(Rational.one));
  setUp(() async {
    generation = 1;
    walletCoins = {};
    sdk = _Sdk();
    auth = _Auth();
    coins = _Coins();
    dex = _Dex();
    users = StreamController<KdfUser?>.broadcast(sync: true);
    when(() => sdk.auth).thenReturn(auth);
    when(() => auth.authGeneration).thenAnswer((_) => generation);
    when(() => auth.watchCurrentUser()).thenAnswer((_) => users.stream);
    for (final ticker in ['LCC', 'LTC']) {
      final coin = _Coin();
      when(() => coin.abbr).thenReturn(ticker);
      when(() => coin.isActive).thenReturn(true);
      when(() => coin.isSuspended).thenReturn(false);
      when(() => coin.walletOnly).thenReturn(false);
      when(() => coin.decimals).thenReturn(8);
      when(() => coins.getCoin(ticker)).thenReturn(coin);
      walletCoins[ticker] = coin;
    }
    when(
      () => dex.getMinTradingVolume(any()),
    ).thenAnswer((_) async => Rational.one);
    when(
      () => dex.getTradePreimage(any(), any(), any(), any(), any()),
    ).thenAnswer(
      (_) async =>
          DataFromService(error: TextError(error: 'offline fee fixture')),
    );
    repository = PendingOffers();
    GetIt.I.registerSingleton<KomodoDefiSdk>(sdk);
    bloc = TakerBloc(
      dexRepository: dex,
      coinsRepository: coins,
      kdfSdk: sdk,
      analyticsBloc: _Analytics(),
      bestOffersRepository: repository,
      walletCoinLookup: (ticker) => walletCoins[ticker],
    );
    users.add(
      KdfUser(
        walletId: WalletId(
          name: 'offline-test',
          authOptions: const AuthOptions(
            derivationMethod: DerivationMethod.iguana,
          ),
        ),
        isBip39Seed: true,
      ),
    );
  });
  tearDown(() async {
    for (final pending in repository.pending) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Fixture closed'));
      }
    }
    await bloc.close().timeout(const Duration(seconds: 2));
    await users.close().timeout(const Duration(seconds: 2));
    await GetIt.I.reset();
  });
  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 10));
  Future<void> choose({BestOfferSide side = BestOfferSide.sell}) async {
    final query = fixtureQuery(side: side);
    final offer = BestOffersSnapshot.fromRpc(
      query,
      fixtureResponse(),
    ).offers.single;
    bloc.add(TakerUseBestOffer(query, offer));
    await tick();
  }

  test(
    'sell offer is re-fetched and fills a draft without starting a swap',
    () async {
      await choose();
      expect(repository.calls.length, 1);
      expect(bloc.state.selectedOrder, isNull);
      repository.complete(0);
      await tick();
      expect(bloc.state.sellCoin!.abbr, 'LCC');
      expect(bloc.state.selectedOrder!.coin, 'LTC');
      expect(bloc.state.sellAmount, Rational.fromInt(100));
      expect(bloc.state.buyAmount, Rational.parse('0.2'));
      expect(bloc.state.inProgress, isFalse);
      verifyNever(() => sdk.client);
    },
  );
  test(
    'review uses the active wallet projection while the catalog remains inactive',
    () async {
      for (final ticker in ['LCC', 'LTC']) {
        final catalog = _Coin();
        when(() => catalog.abbr).thenReturn(ticker);
        when(() => catalog.isActive).thenReturn(false);
        when(() => catalog.walletOnly).thenReturn(false);
        when(() => catalog.decimals).thenReturn(8);
        when(() => coins.getCoin(ticker)).thenReturn(catalog);
      }
      await choose();
      expect(repository.calls, hasLength(1));
      repository.complete(0);
      await tick();
      expect(bloc.state.sellCoin, same(walletCoins['LCC']));
      expect(bloc.state.sellCoin!.isActive, isTrue);
      expect(bloc.state.selectedOrder!.coin, 'LTC');
      expect(coins.getCoin('LCC')!.isActive, isFalse);
      verifyNever(() => sdk.client);
    },
  );
  test(
    'a coin removed from the wallet during verification cannot be restored by the catalog',
    () async {
      await choose();
      walletCoins.remove('LTC');
      repository.complete(0);
      await tick();
      expect(bloc.state.selectedOrder, isNull);
      expect(bloc.state.errors, isNotEmpty);
      verifyNever(() => sdk.client);
    },
  );
  test('buy offer normalizes price, limits and outgoing coin', () async {
    await choose(side: BestOfferSide.buy);
    repository.complete(0);
    await tick();
    expect(bloc.state.sellCoin!.abbr, 'LTC');
    expect(bloc.state.selectedOrder!.coin, 'LCC');
    expect(bloc.state.selectedOrder!.price, Rational.fromInt(500));
    expect(bloc.state.selectedOrder!.minVolume, Rational.parse('0.02'));
    expect(bloc.state.selectedOrder!.maxVolume, Rational.fromInt(2));
    expect(bloc.state.sellAmount, Rational.parse('0.2'));
    expect(bloc.state.buyAmount, Rational.fromInt(100));
    verifyNever(() => sdk.client);
  });
  test('price changed while selecting prevents draft substitution', () async {
    await choose();
    repository.complete(0, rows: [fixtureOrder(price: '0.003')]);
    await tick();
    expect(bloc.state.selectedOrder, isNull);
    expect(bloc.state.errors, isNotEmpty);
  });
  test('removed or own offer cannot enter the form', () async {
    await choose();
    repository.complete(0, rows: [fixtureOrder(mine: true)]);
    await tick();
    expect(bloc.state.selectedOrder, isNull);
    expect(bloc.state.errors, isNotEmpty);
  });
  test(
    'editing form while verification is pending discards the result',
    () async {
      await choose();
      bloc.add(TakerSetSellAmount(Rational.fromInt(9)));
      await tick();
      repository.complete(0);
      await tick();
      expect(bloc.state.selectedOrder, isNull);
      expect(bloc.state.sellAmount, Rational.fromInt(9));
    },
  );
  test('session switch during verification discards the result', () async {
    await choose();
    generation = 2;
    repository.complete(0);
    await tick();
    expect(bloc.state.selectedOrder, isNull);
  });
  test('inactive assets are not activated by selecting a row', () async {
    final inactive = coins.getCoin('LTC')!;
    when(() => inactive.isActive).thenReturn(false);
    await choose();
    expect(repository.calls, isEmpty);
    expect(bloc.state.selectedOrder, isNull);
    verifyNever(() => sdk.client);
  });
  test('double click cannot queue a second selection verification', () async {
    await choose();
    await choose();
    expect(repository.calls.length, 1);
    repository.complete(0);
    await tick();
    expect(bloc.state.selectedOrder, isNotNull);
  });
  test(
    'buy amount exceeding the outgoing coin precision is rejected',
    () async {
      final query = fixtureQuery(side: BestOfferSide.buy);
      final response = fixtureResponse(
        rows: [fixtureOrder(price: '0.00000000001')],
      );
      final offer = BestOffersSnapshot.fromRpc(query, response).offers.single;
      bloc.add(TakerUseBestOffer(query, offer));
      await tick();
      repository.complete(0, rows: [fixtureOrder(price: '0.00000000001')]);
      await tick();
      expect(bloc.state.selectedOrder, isNull);
      expect(bloc.state.errors, isNotEmpty);
    },
  );
  test('reduced available order volume prevents selection', () async {
    await choose();
    final row = fixtureOrder()..['base_max_volume'] = {'decimal': '50'};
    repository.complete(0, rows: [row]);
    await tick();
    expect(bloc.state.selectedOrder, isNull);
    expect(bloc.state.errors, isNotEmpty);
  });
  test(
    'deactivation during verification cannot use a stale active coin',
    () async {
      await choose();
      final coin = coins.getCoin('LTC')!;
      when(() => coin.isActive).thenReturn(false);
      repository.complete(0);
      await tick();
      expect(bloc.state.selectedOrder, isNull);
      expect(bloc.state.errors, isNotEmpty);
    },
  );
  test(
    'queued best-orders event cannot access the SDK during app shutdown',
    () async {
      await tick();
      await appShutdown.stopConsumers();
      when(
        () => sdk.auth,
      ).thenThrow(StateError('KomodoDefiSdk has been disposed'));
      clearInteractions(sdk);
      bloc.add(TakerUpdateBestOrders());
      await tick();
      verifyNever(() => sdk.auth);
    },
  );
}
