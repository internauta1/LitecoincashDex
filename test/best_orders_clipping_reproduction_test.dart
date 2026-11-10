import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/views/dex/best_orders/best_orders_panel.dart' as current;
import 'best_orders_panel_test.dart' show WidgetOffers;

void main() {
  testWidgets(
    'current results keep comparison within the panel at application text size',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(fontSize: 22),
              titleSmall: TextStyle(fontSize: 22),
              titleMedium: TextStyle(fontSize: 22),
              labelLarge: TextStyle(fontSize: 22),
            ),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 350,
                child: current.BestOrdersPanel(
                  repository: WidgetOffers(),
                  generation: 1,
                  assets: const [
                    current.BestOffersAsset('LCC', active: true),
                    current.BestOffersAsset('LTC', active: true),
                  ],
                  initialCoin: 'LCC',
                  signedIn: true,
                  priceOf: (coin) => coin == 'LCC'
                      ? Rational.parse('0.1')
                      : Rational.fromInt(50),
                  onUse: (_, __) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('best-orders-amount')),
        '100',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final viewport = tester.getRect(find.byType(current.BestOrdersPanel));
      expect(
        tester.getRect(find.text('0.00%')).right,
        lessThanOrEqualTo(viewport.right + 0.01),
        reason: 'The comparison must remain inside the narrow visible pane',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
