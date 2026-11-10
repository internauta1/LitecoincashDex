import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/dex/best_orders/market_orders_tabs.dart';

void main() {
  testWidgets(
    'market tabs select only the requested view and wrap at larger text scales',
    (tester) async {
      bool best = false;
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SizedBox(
                width: 240,
                child: StatefulBuilder(
                  builder: (context, setState) => MarketOrdersTabs(
                    bestOrders: best,
                    onChanged: (value) {
                      changes.add(value);
                      setState(() => best = value);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Order book'));
      expect(changes, isEmpty);
      await tester.tap(find.text('Best Orders'));
      await tester.pump();
      expect(changes, [true]);
      await tester.tap(find.text('Best Orders'));
      expect(changes, [true]);
      await tester.tap(find.text('Order book'));
      await tester.pump();
      expect(changes, [true, false]);
      expect(tester.takeException(), isNull);
    },
  );
}
