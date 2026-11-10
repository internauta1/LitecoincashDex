import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:rational/rational.dart';
import 'package:app_theme/app_theme.dart' as app_theme;
import 'package:web_dex/services/best_orders/best_offers.dart';
import 'package:web_dex/views/dex/best_orders/best_orders_panel.dart';
import 'package:web_dex/views/dex/best_orders/market_orders_tabs.dart';
import 'best_offers_test.dart' show fixtureOrder;

class _PreviewOffers implements BestOffersRepository {
  @override
  Future<BestOffersSnapshot> fetch(BestOffersQuery query) async {
    final response = rpc.BestOrdersResponse.parse({
      'mmrpc': '2.0',
      'result': {
        'orders': {
          'LTC': [fixtureOrder(price: '0.000028')],
          'LTC-segwit': [fixtureOrder(coin: 'LTC-segwit', price: '0.000028')],
          'DOGE': [
            fixtureOrder(coin: 'DOGE', id: 'fixture-doge', price: '0.008'),
          ],
          'BTC': [
            fixtureOrder(coin: 'BTC', id: 'fixture-btc', price: '0.000000015'),
          ],
        },
        'original_tickers': {
          'LTC': ['LTC-segwit'],
        },
      },
    });
    final result = BestOffersSnapshot.fromRpc(query, response);
    return BestOffersSnapshot(
      query: query,
      offers: result.offers,
      originalTickers: result.originalTickers,
      receivedAt: DateTime.utc(2026, 11, 7, 17),
    );
  }
}

void main() {
  for (final (width, mode) in [
    (350.0, ThemeMode.dark),
    (540.0, ThemeMode.dark),
    (350.0, ThemeMode.light),
  ]) {
    testWidgets('styled Best Orders preview $width ${mode.name}', (
      tester,
    ) async {
      final font = FontLoader('Manrope')
        ..addFont(rootBundle.load('assets/fonts/Manrope-Regular.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final previousMode = app_theme.theme.mode;
      app_theme.theme.mode = mode;
      addTearDown(() => app_theme.theme.mode = previousMode);
      tester.view.physicalSize = Size(width, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('preview'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: app_theme.theme.currentGlobal,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Offline preview — fixture offers',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    MarketOrdersTabs(bestOrders: true, onChanged: (_) {}),
                    const SizedBox(height: 10),
                    BestOrdersPanel(
                      repository: _PreviewOffers(),
                      generation: 1,
                      assets: const [
                        BestOffersAsset('LCC', active: true),
                        BestOffersAsset('LTC', active: true),
                        BestOffersAsset('LTC-segwit', active: true),
                        BestOffersAsset('DOGE', active: true),
                        BestOffersAsset('BTC', active: true),
                      ],
                      initialCoin: 'LCC',
                      signedIn: true,
                      priceOf: (coin) => Rational.parse(switch (coin) {
                        'LCC' => '0.0013',
                        'LTC' || 'LTC-segwit' => '50',
                        'DOGE' => '0.15',
                        _ => '70000',
                      }),
                      onUse: (_, __) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('best-orders-amount')),
        '1000',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await expectLater(
        find.byKey(const Key('preview')),
        matchesGoldenFile(
          'goldens/best-orders-${width.toInt()}-${mode.name}.png',
        ),
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
