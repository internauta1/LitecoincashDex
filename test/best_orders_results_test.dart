import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/dex/best_orders/best_orders_results.dart';

void main() {
  const lines = [
    BestOrdersResultLine(
      id: 'normal',
      amount: '3.05179000',
      ticker: 'VAL',
      variants: ['VAL'],
      usd: r'$1.42',
      comparison: '-5.83%',
      selected: true,
    ),
    BestOrdersResultLine(
      id: 'large',
      amount: '123456789.123456789123456789',
      ticker: 'LTC-segwit',
      variants: ['LTC', 'LTC-segwit'],
      usd: r'$123,456,789.12',
      comparison: '+123456.78%',
      selected: false,
    ),
  ];
  testWidgets('financial values stay visible across widths and text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [240.0, 300.0, 350.0, 420.0, 540.0, 800.0]) {
      for (final scale in [1.0, 1.25, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              textTheme: const TextTheme(
                bodyMedium: TextStyle(fontSize: 22),
                bodySmall: TextStyle(fontSize: 18),
              ),
            ),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: BestOrdersResults(
                        lines: lines,
                        buy: false,
                        onSelect: (_) {},
                        onVariant: (_, __) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final bounds = tester.getRect(
          find.byKey(const Key('best-orders-results')),
        );
        for (final line in lines) {
          for (final field in ['amount', 'usd', 'comparison']) {
            final finder = find.byKey(
              ValueKey('best-orders-$field-${line.id}'),
            );
            final rect = tester.getRect(finder);
            expect(
              rect.left,
              greaterThanOrEqualTo(bounds.left),
              reason: '$width/$scale/$field',
            );
            expect(
              rect.right,
              lessThanOrEqualTo(bounds.right + .01),
              reason: '$width/$scale/$field',
            );
            expect(
              tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
              isFalse,
            );
            final text = tester.widget<Text>(finder);
            expect(text.maxLines, isNull);
            expect(text.overflow, isNot(TextOverflow.ellipsis));
          }
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'width=$width scale=$scale',
        );
      }
    }
  });
  testWidgets(
    'row selection and variant controls retain their callbacks after resizing',
    (tester) async {
      String? selected;
      String? variant;
      Future<void> show(double width) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: BestOrdersResults(
                lines: lines,
                buy: true,
                onSelect: (id) => selected = id,
                onVariant: (id, value) => variant = '$id/$value',
              ),
            ),
          ),
        ),
      );
      await show(350);
      await tester.tap(find.byKey(const ValueKey('best-orders-row-normal')));
      expect(selected, 'normal');
      await show(780);
      expect(find.text('You send'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LTC').last);
      await tester.pumpAndSettle();
      expect(variant, 'large/LTC');
      expect(tester.takeException(), isNull);
    },
  );
}
