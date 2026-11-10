import 'package:flutter/material.dart';
import 'package:web_dex/views/dex/common/dex_text_button.dart';

/// Shares the existing Taker/Maker control styling without trading actions.
class MarketOrdersTabs extends StatelessWidget {
  const MarketOrdersTabs({
    super.key,
    required this.bestOrders,
    required this.onChanged,
  });
  final bool bestOrders;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      Semantics(
        button: true,
        selected: !bestOrders,
        child: DexTextButton(
          key: const Key('order-book-tab'),
          text: 'Order book',
          isActive: !bestOrders,
          onTap: bestOrders ? () => onChanged(false) : null,
        ),
      ),
      Semantics(
        button: true,
        selected: bestOrders,
        child: DexTextButton(
          key: const Key('best-orders-tab'),
          text: 'Best Orders',
          isActive: bestOrders,
          onTap: bestOrders ? null : () => onChanged(true),
        ),
      ),
    ],
  );
}
