import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';
// Frozen pre-fix source is intentionally imported to prove the reported defect.
// ignore: avoid_relative_lib_imports
import '../tool/validation-runs/20261107-best-orders-responsive/before/lib/views/dex/best_orders/best_orders_panel.dart'
    as before;
import 'best_orders_panel_test.dart' show WidgetOffers;

void main() {
  testWidgets(
    'original results reproduce clipped comparison with the application text size',
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
                child: before.BestOrdersPanel(
                  repository: WidgetOffers(),
                  generation: 1,
                  assets: const [
                    before.BestOffersAsset('LCC', active: true),
                    before.BestOffersAsset('LTC', active: true),
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
      // The original table also fixes two lines of large text to a 48px row.
      final originalOverflow = tester.takeException();
      expect(originalOverflow.toString(), contains('RenderFlex overflowed'));
      final viewport = tester.getRect(find.byType(before.BestOrdersPanel));
      expect(
        tester.getRect(find.text('0.00%')).right,
        greaterThan(viewport.right),
        reason:
            'Baseline reproduces the value outside the visible pane, even without a RenderFlex exception',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
