import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:mocktail/mocktail.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/blocs/orderbook_bloc.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/orderbook/order.dart';
import 'package:web_dex/views/dex/orderbook/orderbook_table_item.dart';
import 'package:web_dex/views/dex/orderbook/orderbook_view.dart';

import '../test_units/tests/utils/test_util.dart';
import 'orderbook_ownership_test.dart' show ownUuid, otherUuid;

class _Coins extends Mock implements CoinsRepo {}

class _Orderbook extends Mock implements OrderbookBloc {}

class _Trading extends Mock implements TradingEntitiesBloc {}

Order _order(OrderDirection side, {String? id = ownUuid}) => Order(
  base: 'LCC',
  rel: 'VAL',
  direction: side,
  uuid: id,
  price: Rational.parse('0.00523622'),
  maxVolume: Rational.parse('555.55'),
);

void main() {
  for (final mode in ThemeMode.values.where((m) => m != ThemeMode.system)) {
    for (final side in OrderDirection.values) {
      testWidgets(
        '${mode.name} ${side.name}: own orange, foreign side color, refresh',
        (tester) async {
          theme.mode = mode;
          addTearDown(() => theme.mode = ThemeMode.dark);
          Future<void> show({
            required bool own,
            bool selected = false,
            String? id = ownUuid,
          }) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme.currentGlobal,
                home: Scaffold(
                  body: SizedBox(
                    width: 320,
                    child: OrderbookTableItem(
                      _order(side, id: id),
                      key: const ValueKey('same-row'),
                      isOwnOrder: own,
                      isSelected: selected,
                      volumeFraction: 0.5,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          await show(own: false);
          expect(find.byIcon(Icons.circle), findsNothing);
          final sideColor = side == OrderDirection.ask
              ? theme.custom.asksColor
              : theme.custom.bidsColor;
          Color? priceColor() =>
              tester.widget<Text>(find.text('0.00523622').first).style?.color;
          expect(priceColor(), sideColor);
          await show(own: true);
          expect(priceColor(), theme.custom.targetColor);
          expect(
            tester.widget<Icon>(find.byIcon(Icons.circle)).color,
            theme.custom.targetColor,
          );
          expect(find.byType(Tooltip), findsOneWidget);
          await show(own: true, selected: true);
          expect(find.byIcon(Icons.circle), findsOneWidget);
          expect(find.byIcon(Icons.forward), findsNothing);
          await show(own: false, id: otherUuid);
          expect(priceColor(), sideColor);
          expect(find.byIcon(Icons.circle), findsNothing);
          // A draft is an arrow and borders, never a published own-order dot.
          await show(own: true, id: orderPreviewUuid);
          expect(find.byIcon(Icons.forward), findsOneWidget);
          expect(find.byIcon(Icons.circle), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'UUID cache updates both sides, clears on wallet change and ignores same-price foreign rows',
    (tester) async {
      final coins = _Coins();
      final books = _Orderbook();
      final trading = _Trading();
      final bookEvents = StreamController<OrderbookResult?>.broadcast();
      final ownEvents = StreamController<List<MyOrder>>.broadcast();
      when(() => coins.getCoin(any())).thenReturn(null);
      when(
        () => books.getOrderbookStream('LCC', 'VAL'),
      ).thenAnswer((_) => bookEvents.stream);
      when(() => trading.myOrders).thenReturn([]);
      when(() => trading.outMyOrders).thenAnswer((_) => ownEvents.stream);
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<CoinsRepo>.value(value: coins),
            RepositoryProvider<OrderbookBloc>.value(value: books),
            RepositoryProvider<TradingEntitiesBloc>.value(value: trading),
          ],
          child: MaterialApp(
            theme: theme.global.dark,
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 500,
                child: OrderbookView(
                  base: setCoin(coinAbbr: 'LCC'),
                  rel: setCoin(coinAbbr: 'VAL'),
                ),
              ),
            ),
          ),
        ),
      );
      final response = rpc.OrderbookResponse(
        mmrpc: '2.0',
        base: 'LCC',
        rel: 'VAL',
        numAsks: 2,
        numBids: 2,
        timestamp: 1,
        asks: [ownUuid, otherUuid]
            .map(
              (id) => rpc.OrderInfo(
                uuid: id,
                price: rpc.NumericValue(decimal: '0.005'),
                baseMaxVolume: rpc.NumericValue(decimal: '555.55'),
              ),
            )
            .toList(),
        bids: [ownUuid, otherUuid]
            .map(
              (id) => rpc.OrderInfo(
                uuid: id,
                price: rpc.NumericValue(decimal: '0.005'),
                baseMaxVolume: rpc.NumericValue(decimal: '555.55'),
              ),
            )
            .toList(),
      );
      bookEvents.add(OrderbookResult(response: response));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.circle), findsNothing);
      ownEvents.add([
        MyOrder(
          base: 'LCC',
          rel: 'VAL',
          orderType: TradeSide.maker,
          relAmount: Rational.one,
          baseAmount: Rational.one,
          uuid: ownUuid.toUpperCase(),
          createdAt: 1,
          cancelable: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.circle), findsNWidgets(2));
      bookEvents.add(OrderbookResult(response: response));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.circle), findsNWidgets(2));
      ownEvents.add(
        [],
      ); // Existing TradingEntitiesBloc emits this on auth changes.
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.circle), findsNothing);
      // The classic KDF flag reaches both rendered sides without a local
      // own-order list, including after an SSE/RPC refresh.
      rpc.OrderInfo flagged(bool mine, String id) => rpc.OrderInfo(
        uuid: id,
        isMine: mine,
        price: rpc.NumericValue(decimal: '0.005'),
        baseMaxVolume: rpc.NumericValue(decimal: '555.55'),
      );
      bookEvents.add(
        OrderbookResult(
          response: rpc.OrderbookResponse(
            mmrpc: '2.0',
            base: 'LCC',
            rel: 'VAL',
            numAsks: 2,
            numBids: 2,
            timestamp: 2,
            asks: [flagged(true, ownUuid), flagged(false, otherUuid)],
            bids: [flagged(true, ownUuid), flagged(false, otherUuid)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.circle), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      await bookEvents.close();
      await ownEvents.close();
      verify(() => books.getOrderbookStream('LCC', 'VAL')).called(1);
      verifyNever(() => trading.fetch());
      expect(tester.takeException(), isNull);
    },
  );
}
