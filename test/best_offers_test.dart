import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders_request.dart'
    as legacy;
import 'package:web_dex/services/best_orders/best_offers.dart';
import 'package:web_dex/services/best_orders/best_offers_controller.dart';
import 'package:web_dex/services/best_orders/sdk_best_offers_repository.dart';
import 'package:web_dex/views/dex/best_orders/best_orders_panel.dart';

Map<String, dynamic> fixtureOrder({
  String coin = 'LTC',
  String id = 'test-order-1',
  String price = '0.002',
  bool mine = false,
}) => {
  'coin': coin,
  'uuid': id,
  'is_mine': mine,
  'price': {'decimal': price},
  'base_min_volume': {'decimal': '10'},
  'base_max_volume': {'decimal': '1000'},
  'rel_min_volume': {'decimal': '0.02'},
  'rel_max_volume': {'decimal': '2'},
  'address': {'address_type': 'Transparent', 'address_data': 'offline-fixture'},
};

rpc.BestOrdersResponse fixtureResponse({
  List<Map<String, dynamic>>? rows,
  bool variants = false,
}) => rpc.BestOrdersResponse.parse({
  'mmrpc': '2.0',
  'result': {
    'orders': {
      'LTC': rows ?? [fixtureOrder()],
      if (variants) 'LTC-segwit': [fixtureOrder(coin: 'LTC-segwit')],
    },
    'original_tickers': {
      if (variants) 'LTC': ['LTC-segwit'],
    },
  },
});

BestOffersQuery fixtureQuery({
  int generation = 1,
  BestOfferSide side = BestOfferSide.sell,
  String coin = 'LCC',
  String volume = '100',
}) => BestOffersQuery(
  coin: coin,
  side: side,
  generation: generation,
  volume: Rational.parse(volume),
);

class PendingOffers implements BestOffersRepository {
  final calls = <BestOffersQuery>[];
  final pending = <Completer<BestOffersSnapshot>>[];
  @override
  Future<BestOffersSnapshot> fetch(BestOffersQuery query) {
    calls.add(query);
    final c = Completer<BestOffersSnapshot>();
    pending.add(c);
    return c.future;
  }

  void complete(int index, {List<Map<String, dynamic>>? rows}) =>
      pending[index].complete(
        BestOffersSnapshot.fromRpc(calls[index], fixtureResponse(rows: rows)),
      );
}

void main() {
  testWidgets('refresh timer stops when the panel query is cleared', (
    tester,
  ) async {
    final repo = PendingOffers();
    final controller = BestOffersController(repo);
    controller.configure(fixtureQuery());
    repo.complete(0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 45));
    expect(repo.calls.length, 2);
    controller.configure(null);
    repo.complete(1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 90));
    expect(repo.calls.length, 2);
    expect(controller.snapshot, isNull);
    controller.dispose();
  });
  test('legacy serialization preserves buy and sell directions', () {
    for (final side in ['buy', 'sell']) {
      final request = legacy.BestOrdersRequest(
        coin: 'LCC',
        action: side,
        type: legacy.BestOrdersRequestType.number,
        number: 1,
      )..userpass = '';
      expect((request.toJson()['params'] as Map)['action'], side);
    }
  });
  test('SDK preserves map groups, immutable lists and SegWit aliases', () {
    final response = fixtureResponse(variants: true);
    expect(response.orders.length, 2);
    expect(response.ordersByCoin.keys, ['LTC', 'LTC-segwit']);
    expect(response.originalTickers['LTC'], ['LTC-segwit']);
    expect(() => response.ordersByCoin['LTC']!.clear(), throwsUnsupportedError);
    expect(rpc.BestOrdersResponse.parse(response.toJson()).orders.length, 2);
  });
  test('SDK rejects invalid group shape instead of reporting no liquidity', () {
    expect(
      () => rpc.BestOrdersResponse.parse({
        'mmrpc': '2.0',
        'result': {'orders': []},
      }),
      throwsA(anything),
    );
    expect(
      () => rpc.BestOrdersResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'orders': {'LTC': 'invalid'},
        },
      }),
      throwsFormatException,
    );
  });
  test('empty valid response is distinct from malformed response', () {
    expect(fixtureResponse(rows: []).orders, isEmpty);
  });
  test('queries reject zero, negative and non-serializable volume', () {
    for (final volume in [
      Rational.zero,
      Rational.fromInt(-1),
      Rational(BigInt.one, BigInt.from(3)),
    ]) {
      expect(
        () => BestOffersQuery(
          coin: 'LCC',
          side: BestOfferSide.sell,
          generation: 1,
          volume: volume,
        ),
        throwsArgumentError,
      );
    }
  });
  test('SDK request contains direction, volume and own-order exclusion', () {
    final json = rpc.BestOrdersRequest(
      rpcPass: '',
      coin: 'LCC',
      action: rpc.OrderType.buy,
      requestBy: rpc.RequestBy.volume('100'),
      excludeMine: true,
    ).toJson();
    expect(json['method'], 'best_orders');
    expect(json['params'], {
      'coin': 'LCC',
      'action': 'buy',
      'exclude_mine': true,
      'request_by': {'type': 'volume', 'value': '100'},
    });
  });
  test(
    'address variants do not count the same order as two liquidity rows',
    () {
      final snapshot = BestOffersSnapshot.fromRpc(
        fixtureQuery(),
        fixtureResponse(variants: true),
      );
      expect(snapshot.groups().length, 1);
      expect(snapshot.groups().single.variants.length, 2);
    },
  );
  test('different networks are not grouped by similar names', () {
    final snapshot = BestOffersSnapshot(
      query: fixtureQuery(),
      receivedAt: DateTime.now(),
      offers: [
        BestOffer(
          coin: 'ETH',
          info: rpc.OrderInfo.fromJson(fixtureOrder(coin: 'ETH')),
        ),
        BestOffer(
          coin: 'ETH-ARB20',
          info: rpc.OrderInfo.fromJson(fixtureOrder(coin: 'ETH-ARB20')),
        ),
      ],
    );
    expect(snapshot.groups().length, 2);
  });
  test('own orders and repeated UUIDs within a ticker are excluded', () {
    final response = fixtureResponse(
      rows: [
        fixtureOrder(),
        fixtureOrder(),
        fixtureOrder(id: 'own', mine: true),
      ],
    );
    expect(
      BestOffersSnapshot.fromRpc(fixtureQuery(), response).offers.length,
      1,
    );
  });
  test('buy conversion inverts price and converts outgoing amount exactly', () {
    final offer = BestOffersSnapshot.fromRpc(
      fixtureQuery(),
      fixtureResponse(),
    ).offers.single;
    expect(offer.sellPrice(BestOfferSide.buy), Rational.fromInt(500));
    expect(
      offer.sellVolume(fixtureQuery(side: BestOfferSide.buy)),
      Rational.parse('0.2'),
    );
    expect(offer.sellPrice(BestOfferSide.sell), Rational.parse('0.002'));
    expect(offer.sellVolume(fixtureQuery()), Rational.fromInt(100));
  });
  test('volume bounds include both endpoints and reject uncovered amounts', () {
    final offer = BestOffersSnapshot.fromRpc(
      fixtureQuery(),
      fixtureResponse(),
    ).offers.single;
    expect(offer.fits(Rational.fromInt(10)), isTrue);
    expect(offer.fits(Rational.fromInt(1000)), isTrue);
    expect(offer.fits(Rational.fromInt(9)), isFalse);
    expect(offer.fits(Rational.fromInt(1001)), isFalse);
  });
  test('invalid price or reversed limits cannot enter the explorer', () {
    expect(
      () => BestOffersSnapshot.fromRpc(
        fixtureQuery(),
        fixtureResponse(rows: [fixtureOrder(price: '0')]),
      ),
      throwsFormatException,
    );
    final row = fixtureOrder()..['base_max_volume'] = {'decimal': '1'};
    expect(
      () => BestOffersSnapshot.fromRpc(
        fixtureQuery(),
        fixtureResponse(rows: [row]),
      ),
      throwsFormatException,
    );
  });
  test('fractions take precedence over rounded decimals', () {
    final row = fixtureOrder();
    row['price'] = {
      'decimal': '0.3333',
      'fraction': {'numer': '1', 'denom': '3'},
    };
    final offer = BestOffersSnapshot.fromRpc(
      fixtureQuery(),
      fixtureResponse(rows: [row]),
    ).offers.single;
    expect(offer.otherAmount(Rational.fromInt(3)), Rational.one);
  });
  test('large and tiny values never pass through double', () {
    expect(
      formatBestOfferNumber(Rational.parse('9007199254740993.00000001')),
      '9007199254740993.00000001',
    );
    expect(
      displayBestOfferNumber(Rational.parse('0.000000000000000001')),
      '<0.00000001',
    );
    expect(
      formatBestOfferNumber(Rational.parse('0.000000000000000001'), 18),
      '0.000000000000000001',
    );
  });
  test('USD comparison returns unavailable for missing or zero reference', () {
    final offer = BestOffersSnapshot.fromRpc(
      fixtureQuery(),
      fixtureResponse(),
    ).offers.single;
    expect(bestOfferDifference(offer, null, Rational.one), isNull);
    expect(bestOfferDifference(offer, Rational.zero, Rational.one), isNull);
    expect(
      bestOfferDifference(offer, Rational.parse('0.1'), Rational.fromInt(50)),
      Rational.zero,
    );
  });
  test(
    'amount validation respects asset precision and rejects malformed input',
    () {
      expect(
        parseBestOffersVolume('1.12345678', 8),
        Rational.parse('1.12345678'),
      );
      for (final value in [
        '',
        '0',
        '-1',
        '1,5',
        '1/3',
        'NaN',
        '1e8',
        '1.123456789',
      ]) {
        expect(parseBestOffersVolume(value, 8), isNull);
      }
    },
  );
  test(
    'shared repository coalesces requests without caching fresh results',
    () async {
      var calls = 0;
      final response = Completer<rpc.BestOrdersResponse>();
      final repo = SharedBestOffersRepository(
        currentGeneration: () => 1,
        request: (_) {
          calls++;
          return response.future;
        },
      );
      final a = repo.fetch(fixtureQuery());
      final b = repo.fetch(fixtureQuery());
      expect(calls, 1);
      response.complete(fixtureResponse());
      expect(identical(await a, await b), isTrue);
      await repo.fetch(fixtureQuery());
      expect(calls, 2);
    },
  );
  test('session change rejects a late response and old queries', () async {
    var generation = 1;
    final pending = Completer<rpc.BestOrdersResponse>();
    final repo = SharedBestOffersRepository(
      currentGeneration: () => generation,
      request: (_) => pending.future,
    );
    final result = repo.fetch(fixtureQuery());
    generation = 2;
    pending.complete(fixtureResponse());
    await expectLater(result, throwsStateError);
    expect(() => repo.fetch(fixtureQuery()), throwsStateError);
  });
  test('UI timeout does not start a duplicate underlying request', () async {
    var calls = 0;
    final pending = Completer<rpc.BestOrdersResponse>();
    final repo = SharedBestOffersRepository(
      currentGeneration: () => 1,
      timeout: const Duration(milliseconds: 5),
      request: (_) {
        calls++;
        return pending.future;
      },
    );
    await expectLater(
      repo.fetch(fixtureQuery()),
      throwsA(isA<TimeoutException>()),
    );
    final retry = repo.fetch(fixtureQuery());
    expect(calls, 1);
    pending.complete(fixtureResponse());
    await retry;
  });
  test(
    'controller ignores previous coin response and serializes queries',
    () async {
      final repo = PendingOffers();
      final controller = BestOffersController(repo);
      controller.configure(fixtureQuery());
      controller.configure(fixtureQuery(coin: 'BTC'));
      expect(repo.calls.length, 1);
      repo.complete(0);
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot, isNull);
      expect(repo.calls.length, 2);
      repo.complete(1);
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot!.query.coin, 'BTC');
      controller.dispose();
    },
  );
  test(
    'controller deduplicates refreshes and retains last result on error',
    () async {
      final repo = PendingOffers();
      final c = BestOffersController(repo);
      c.configure(fixtureQuery());
      final same = c.refresh();
      expect(repo.calls.length, 1);
      repo.complete(0);
      await same;
      final previous = c.snapshot;
      final failure = c.refresh();
      repo.pending[1].completeError(StateError('offline fixture failure'));
      await failure;
      expect(c.failed, isTrue);
      expect(identical(previous, c.snapshot), isTrue);
      await c.refresh();
      expect(repo.calls.length, 2);
      c.dispose();
    },
  );
  test('logout/disposal drops pending results and stops observation', () async {
    final repo = PendingOffers();
    final c = BestOffersController(repo);
    c.configure(fixtureQuery());
    c.configure(null);
    repo.complete(0);
    await Future<void>.delayed(Duration.zero);
    expect(c.snapshot, isNull);
    expect(c.loading, isFalse);
    c.dispose();
  });
}
