import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/services/best_orders/best_offers.dart';
import 'package:web_dex/views/dex/best_orders/best_orders_panel.dart';
import 'best_offers_test.dart' show fixtureResponse;

class WidgetOffers implements BestOffersRepository {
  final calls = <BestOffersQuery>[];
  Completer<BestOffersSnapshot>? pending;
  bool fail = false;
  bool empty = false;
  @override
  Future<BestOffersSnapshot> fetch(BestOffersQuery query) async {
    calls.add(query);
    if (pending != null) return pending!.future;
    if (fail) throw StateError('offline fixture');
    return BestOffersSnapshot.fromRpc(
      query,
      fixtureResponse(rows: empty ? [] : null),
    );
  }
}

void main() {
  Future<void> showPanel(
    WidgetTester tester,
    WidgetOffers repo, {
    bool active = true,
    bool signedIn = true,
    bool canUse = true,
    int generation = 1,
    void Function(BestOffersQuery, BestOffer)? onUse,
    double width = 420,
    List<BestOffersAsset>? assets,
    double fontScale = 1,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        theme: ThemeData(
          textTheme: TextTheme(
            bodyMedium: TextStyle(fontSize: 14 * fontScale),
            bodySmall: TextStyle(fontSize: 12 * fontScale),
            titleSmall: TextStyle(fontSize: 14 * fontScale),
            titleMedium: TextStyle(fontSize: 16 * fontScale),
            labelLarge: TextStyle(fontSize: 14 * fontScale),
          ),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: BestOrdersPanel(
                repository: repo,
                generation: generation,
                assets:
                    assets ??
                    [
                      const BestOffersAsset('LCC', active: true),
                      BestOffersAsset('LTC', active: active),
                    ],
                initialCoin: 'LCC',
                priceOf: (coin) => coin == 'LCC'
                    ? Rational.parse('0.1')
                    : Rational.fromInt(50),
                signedIn: signedIn,
                canUseOffer: canUse,
                onUse: onUse ?? (_, __) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Maker mode allows inspection but cannot replace a maker form', (
    tester,
  ) async {
    final repo = WidgetOffers();
    var selected = 0;
    await showPanel(tester, repo, canUse: false, onUse: (_, __) => selected++);
    await tester.enterText(find.byKey(const Key('best-orders-amount')), '100');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final button = tester.widget<TextButton>(
      find.byKey(const ValueKey('use-best-offer-LTC-test-order-1')),
    );
    expect(button.onPressed, isNull);
    expect(selected, 0);
    expect(
      find.text('Switch to Taker order to use an existing offer.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long asset identifiers cannot overflow a narrow selector', (
    tester,
  ) async {
    final repo = WidgetOffers();
    await showPanel(
      tester,
      repo,
      width: 300,
      assets: const [
        BestOffersAsset('LCC', active: true),
        BestOffersAsset('LTC', active: true),
        BestOffersAsset('EXAMPLE-TOKEN-ON-A-DIFFERENT-NETWORK', active: false),
      ],
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> amount(WidgetTester tester, String value) async {
    await tester.enterText(find.byKey(const Key('best-orders-amount')), value);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  testWidgets(
    'all quote columns remain inside a default-width panel with large application text',
    (tester) async {
      final repo = WidgetOffers();
      await showPanel(
        tester,
        repo,
        width: 350,
        fontScale: 22 / 14,
        textScale: 1.5,
      );
      await amount(tester, '100');
      final panel = tester.getRect(find.byType(BestOrdersPanel));
      final percentage = find.text('0.00%');
      expect(tester.getRect(percentage).right, lessThanOrEqualTo(panel.right));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'resizing retains amount and offers without another market request',
    (tester) async {
      final repo = WidgetOffers();
      await showPanel(tester, repo, width: 350, fontScale: 22 / 14);
      await amount(tester, '100');
      expect(repo.calls, hasLength(1));
      for (final width in [750.0, 300.0, 540.0]) {
        await showPanel(tester, repo, width: width, fontScale: 22 / 14);
        final input = tester.widget<TextField>(
          find.byKey(const Key('best-orders-amount')),
        );
        expect(input.controller!.text, '100');
        expect(find.text('0.00%'), findsOneWidget);
        expect(repo.calls, hasLength(1));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'viewing and searching offers does not select or activate anything',
    (tester) async {
      final repo = WidgetOffers();
      var selected = 0;
      await showPanel(tester, repo, onUse: (_, __) => selected++);
      expect(repo.calls, isEmpty);
      await amount(tester, '100');
      expect(repo.calls.single.volume, Rational.fromInt(100));
      expect(selected, 0);
      expect(find.text('LTC'), findsWidgets);
      await tester.enterText(
        find.byKey(const Key('best-orders-search')),
        'BTC',
      );
      await tester.pump();
      expect(find.byKey(const Key('best-orders-empty')), findsOneWidget);
      expect(repo.calls.length, 1);
      expect(selected, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('explicit Use offer supplies the selected query and order only', (
    tester,
  ) async {
    final repo = WidgetOffers();
    BestOffersQuery? query;
    BestOffer? offer;
    await showPanel(
      tester,
      repo,
      width: 1000,
      onUse: (q, o) {
        query = q;
        offer = o;
      },
    );
    await amount(tester, '100');
    await tester.ensureVisible(find.text('Use offer'));
    await tester.tap(find.text('Use offer'));
    await tester.pump();
    expect(query!.coin, 'LCC');
    expect(query!.side, BestOfferSide.sell);
    expect(offer!.coin, 'LTC');
    expect(repo.calls.length, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'inactive coin cannot be used and is not activated by the table',
    (tester) async {
      final repo = WidgetOffers();
      var selected = 0;
      await showPanel(
        tester,
        repo,
        active: false,
        onUse: (_, __) => selected++,
      );
      await amount(tester, '100');
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('use-best-offer-LTC-test-order-1')),
      );
      expect(button.onPressed, isNull);
      expect(selected, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('buy direction is carried to the query', (tester) async {
    final repo = WidgetOffers();
    await showPanel(tester, repo);
    await tester.tap(find.byKey(const Key('best-orders-side')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy').last);
    await tester.pumpAndSettle();
    await amount(tester, '100');
    expect(repo.calls.single.side, BestOfferSide.buy);
    expect(find.text('You send'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('P2P error is distinct from empty valid response', (
    tester,
  ) async {
    final repo = WidgetOffers()..fail = true;
    await showPanel(tester, repo);
    await amount(tester, '100');
    expect(find.byKey(const Key('best-orders-error')), findsOneWidget);
    expect(find.byKey(const Key('best-orders-empty')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    final empty = WidgetOffers()..empty = true;
    await showPanel(tester, empty);
    await amount(tester, '100');
    expect(find.byKey(const Key('best-orders-empty')), findsOneWidget);
    expect(find.byKey(const Key('best-orders-error')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('logout discards an in-flight result and disables selection', (
    tester,
  ) async {
    final repo = WidgetOffers()..pending = Completer<BestOffersSnapshot>();
    await showPanel(tester, repo);
    await amount(tester, '100');
    await showPanel(tester, repo, signedIn: false, generation: 2);
    repo.pending!.complete(
      BestOffersSnapshot.fromRpc(repo.calls.single, fixtureResponse()),
    );
    await tester.pump();
    expect(find.text('Use offer'), findsNothing);
    expect(
      find.text('Sign in to inspect offers in this session.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('narrow layout remains usable without horizontal overflow', (
    tester,
  ) async {
    final repo = WidgetOffers();
    await showPanel(tester, repo, width: 300, textScale: 2);
    await amount(tester, '100');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('best-orders-results')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
