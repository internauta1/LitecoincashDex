import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/blocs/orderbook_bloc.dart';
import 'package:web_dex/model/orderbook/order.dart';
import 'package:web_dex/model/orderbook/orderbook.dart';

const ownUuid = '12345678-1234-1234-1234-123456789abc';
const otherUuid = '87654321-4321-4321-4321-cba987654321';

class _Sdk extends Mock implements KomodoDefiSdk {}

Map<String, dynamic> _streamEntry({Object? mine, String id = ownUuid}) => {
  'uuid': id,
  'price': '0.005',
  'max_volume': '555.55',
  if (mine != null) 'is_mine': mine,
};

void main() {
  for (final side in OrderDirection.values) {
    for (final mine in <bool?>[true, false, null]) {
      test('RPC preserves nullable ownership for ${side.name}: $mine', () {
        final info = rpc.OrderInfo.fromJson({
          'uuid': ownUuid,
          'price': {'decimal': '0.005'},
          'base_max_volume': {'decimal': '555.55'},
          if (mine != null) 'is_mine': mine,
        });
        final order = Order.fromOrderInfo(
          info,
          base: 'LCC',
          rel: 'VAL',
          direction: side,
        );
        expect(order.isMine, mine);
        expect(order.isOwnedBy({ownUuid}), mine ?? true);
      });
    }
  }

  test(
    'UUID fallback is exact, canonical, session-local and not a price match',
    () {
      Order order(String? id) => Order(
        base: 'LCC',
        rel: 'VAL',
        direction: OrderDirection.ask,
        price: Rational.one,
        maxVolume: Rational.one,
        uuid: id,
      );
      expect(order(ownUuid.toUpperCase()).isOwnedBy({ownUuid}), isTrue);
      expect(order(ownUuid).isOwnedBy({}), isFalse);
      expect(order(otherUuid).isOwnedBy({ownUuid}), isFalse);
      expect(order(null).isOwnedBy({ownUuid}), isFalse);
      expect(order('').isOwnedBy({''}), isFalse);
      expect(order('malformed').isOwnedBy({'malformed'}), isFalse);
    },
  );

  test('legacy JSON retains ownership without trusting non-boolean values', () {
    Map<String, dynamic> entry(Object? mine) => {
      'coin': 'LCC',
      'uuid': ownUuid,
      'is_mine': mine,
      'price': '1',
      'base_max_volume': '1',
      'base_min_volume': '0.1',
      'rel_min_volume': '0.1',
    };
    for (final mine in [true, false, 'true', 1, null]) {
      final order = Order.fromJson(
        entry(mine),
        direction: OrderDirection.ask,
        otherCoin: 'VAL',
      );
      expect(order.isMine, mine is bool ? mine : null);
    }
  });

  test('SSE parser retains booleans and leaves unknown ownership absent', () {
    final event = OrderbookEvent.fromJson({
      'base': 'LCC',
      'rel': 'VAL',
      'asks': [_streamEntry(mine: true), _streamEntry(mine: false)],
      'bids': [_streamEntry(), _streamEntry(mine: 'true')],
    });
    expect(event.asks.map((row) => row['is_mine']), [true, false]);
    expect(event.bids.every((row) => !row.containsKey('is_mine')), isTrue);
  });

  test(
    'SSE ownership survives publication, refresh and missing-flag fallback',
    () async {
      final sdk = _Sdk();
      final source = StreamController<OrderbookEvent>.broadcast();
      when(
        () => sdk.subscribeToOrderbook(base: 'LCC', rel: 'VAL'),
      ).thenAnswer((_) async => source.stream.listen((_) {}));
      // No actual RPC client or daemon exists in this test.
      when(() => sdk.client).thenThrow(StateError('offline fixture'));
      final bloc = OrderbookBloc(sdk: sdk);
      final results = <Orderbook>[];
      final listener = bloc.getOrderbookStream('LCC', 'VAL').listen((value) {
        if (value?.response case final response?) {
          results.add(Orderbook.fromSdkResponse(response));
        }
      });
      await Future<void>.delayed(Duration.zero);
      for (final mine in <bool?>[true, true, null, false]) {
        source.add(
          OrderbookEvent.fromJson({
            'base': 'LCC',
            'rel': 'VAL',
            'asks': [_streamEntry(mine: mine)],
            'bids': [_streamEntry(mine: mine)],
          }),
        );
        await Future<void>.delayed(Duration.zero);
      }
      expect(results, hasLength(4));
      for (final orders in results) {
        expect(orders.asks.single.isMine, orders.bids.single.isMine);
      }
      expect(results.map((r) => r.asks.single.isMine), [
        true,
        true,
        null,
        false,
      ]);
      expect(results[2].asks.single.isOwnedBy({ownUuid}), isTrue);
      expect(results[2].bids.single.isOwnedBy({}), isFalse);
      expect(results[3].bids.single.isOwnedBy({ownUuid}), isFalse);
      await listener.cancel();
      await bloc.dispose();
      await source.close();
    },
  );
}
