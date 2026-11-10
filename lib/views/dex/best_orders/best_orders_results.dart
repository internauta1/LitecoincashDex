import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:app_theme/app_theme.dart';

class BestOrdersResultLine {
  const BestOrdersResultLine({
    required this.id,
    required this.amount,
    required this.ticker,
    required this.variants,
    required this.usd,
    required this.comparison,
    required this.selected,
    this.comparisonColor,
  });
  final String id;
  final String amount;
  final String ticker;
  final List<String> variants;
  final String usd;
  final String comparison;
  final Color? comparisonColor;
  final bool selected;
}

/// Uses actual font metrics. Financial values never depend on horizontal scroll.
class BestOrdersResults extends StatelessWidget {
  const BestOrdersResults({
    super.key,
    required this.lines,
    required this.buy,
    required this.onSelect,
    required this.onVariant,
  });
  final List<BestOrdersResultLine> lines;
  final bool buy;
  final ValueChanged<String> onSelect;
  final void Function(String, String) onVariant;

  double _width(BuildContext context, String text, [TextStyle? style]) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  Widget _ticker(BestOrdersResultLine line) => line.variants.length > 1
      ? DropdownButton<String>(
          isDense: true,
          isExpanded: true,
          value: line.ticker,
          items: line.variants
              .map(
                (ticker) => DropdownMenuItem(
                  value: ticker,
                  child: Tooltip(
                    message: ticker,
                    child: Text(ticker, overflow: TextOverflow.ellipsis),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onVariant(line.id, value);
          },
        )
      : Text(line.ticker, softWrap: true);

  Widget _columns(
    List<double> widths,
    Widget first,
    Widget second,
    Widget third,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: widths[0], child: first),
      const SizedBox(width: 12),
      SizedBox(width: widths[1], child: second),
      const SizedBox(width: 12),
      SizedBox(width: widths[2], child: third),
    ],
  );

  Widget _metrics(BuildContext context, BestOrdersResultLine line) {
    final small = Theme.of(context).textTheme.bodySmall;
    Widget metric(String label, String value, String key, Color? color) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: small),
            Text(
              value,
              key: ValueKey(key),
              style: TextStyle(color: color),
            ),
          ],
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final usd = metric(
          'Approx. USD',
          line.usd,
          'best-orders-usd-${line.id}',
          null,
        );
        final comparison = metric(
          'vs market',
          line.comparison,
          'best-orders-comparison-${line.id}',
          line.comparisonColor,
        );
        final usdWidth = math.max(
          _width(context, 'Approx. USD', small),
          _width(context, line.usd),
        );
        final comparisonWidth = math.max(
          _width(context, 'vs market', small),
          _width(context, line.comparison),
        );
        if (math.max(usdWidth, comparisonWidth) * 2 + 12 >
            constraints.maxWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [usd, const SizedBox(height: 6), comparison],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: usd),
            const SizedBox(width: 12),
            Expanded(child: comparison),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final direction = buy ? 'You send' : 'You receive';
      final widths = [
        _width(context, direction),
        _width(context, 'Approx. USD'),
        _width(context, 'vs market'),
      ];
      for (final line in lines) {
        widths[0] = math.max(
          widths[0],
          math.max(
            _width(context, line.amount),
            _width(context, line.ticker) + (line.variants.length > 1 ? 40 : 0),
          ),
        );
        widths[1] = math.max(widths[1], _width(context, line.usd));
        widths[2] = math.max(widths[2], _width(context, line.comparison));
      }
      final available = math.max(0.0, constraints.maxWidth - 16);
      final required = widths.reduce((a, b) => a + b) + 24;
      final wide = available >= required;
      if (wide) {
        final extra = (available - required) / 3;
        widths[0] += extra;
        widths[1] += extra;
        widths[2] = available - 24 - widths[0] - widths[1];
      }
      return Column(
        key: const Key('best-orders-results'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: wide
                ? _columns(
                    widths,
                    Text(direction),
                    const Text('Approx. USD'),
                    const Text('vs market'),
                  )
                : Text(direction),
          ),
          for (final (index, line) in lines.indexed)
            Material(
              color: line.selected
                  ? Theme.of(context).colorScheme.primary.withAlpha(20)
                  : index.isEven
                  ? dexPageColors.frontPlateInner.withAlpha(80)
                  : Colors.transparent,
              child: InkWell(
                key: ValueKey('best-orders-row-${line.id}'),
                onTap: () => onSelect(line.id),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: dexPageColors.coinPlateDivider),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 9,
                  ),
                  child: wide
                      ? _columns(
                          widths,
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.amount,
                                key: ValueKey('best-orders-amount-${line.id}'),
                              ),
                              _ticker(line),
                            ],
                          ),
                          Text(
                            line.usd,
                            key: ValueKey('best-orders-usd-${line.id}'),
                          ),
                          Text(
                            line.comparison,
                            key: ValueKey('best-orders-comparison-${line.id}'),
                            style: TextStyle(color: line.comparisonColor),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: Text(
                                    line.amount,
                                    key: ValueKey(
                                      'best-orders-amount-${line.id}',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(flex: 4, child: _ticker(line)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            _metrics(context, line),
                          ],
                        ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
