import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_theme/app_theme.dart';
import 'best_orders_card.dart';
import 'best_orders_results.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/services/best_orders/best_offers.dart';
import 'package:web_dex/services/best_orders/best_offers_controller.dart';

class BestOffersAsset {
  const BestOffersAsset(this.ticker, {required this.active, this.decimals = 8});
  final String ticker;
  final bool active;
  final int decimals;
}

Rational? parseBestOffersVolume(String text, int decimals) {
  if (!RegExp(r'^\d{1,30}(?:\.\d{0,18})?$').hasMatch(text)) return null;
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > decimals) return null;
  final value = Rational.parse(text.endsWith('.') ? '${text}0' : text);
  return value > Rational.zero ? value : null;
}

class BestOrdersPanel extends StatefulWidget {
  const BestOrdersPanel({
    super.key,
    required this.repository,
    required this.generation,
    required this.assets,
    required this.initialCoin,
    required this.priceOf,
    required this.onUse,
    required this.signedIn,
    this.canUseOffer = true,
  });
  final BestOffersRepository repository;
  final int generation;
  final List<BestOffersAsset> assets;
  final String initialCoin;
  final Rational? Function(String) priceOf;
  final void Function(BestOffersQuery, BestOffer) onUse;
  final bool signedIn;
  final bool canUseOffer;
  @override
  State<BestOrdersPanel> createState() => _BestOrdersPanelState();
}

class _BestOrdersPanelState extends State<BestOrdersPanel> {
  late final BestOffersController _controller;
  final _amount = TextEditingController();
  final _search = TextEditingController();
  final _variants = <String, String>{};
  Timer? _debounce;
  BestOfferSide _side = BestOfferSide.sell;
  String? _coin;
  String _filter = '';
  bool _bestFirst = true;
  String? _focusedGroup;
  int _visibleLimit = 20;

  @override
  void initState() {
    super.initState();
    _controller = BestOffersController(widget.repository);
    _coin = widget.assets.any((a) => a.ticker == widget.initialCoin)
        ? widget.initialCoin
        : widget.assets.firstOrNull?.ticker;
  }

  @override
  void didUpdateWidget(covariant BestOrdersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation ||
        oldWidget.signedIn != widget.signedIn) {
      _controller.configure(null);
      _variants.clear();
      _scheduleQuery();
    }
    if (!widget.assets.any((a) => a.ticker == _coin)) {
      _coin = widget.assets.firstOrNull?.ticker;
      _scheduleQuery();
    }
  }

  void _scheduleQuery() {
    _debounce?.cancel();
    _controller.configure(null);
    _variants.clear();
    _focusedGroup = null;
    _visibleLimit = 20;
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || !widget.signedIn) return;
      final asset = widget.assets.where((a) => a.ticker == _coin).firstOrNull;
      if (asset == null) return;
      final volume = parseBestOffersVolume(_amount.text, asset.decimals);
      if (volume == null) return;
      _controller.configure(
        BestOffersQuery(
          coin: asset.ticker,
          side: _side,
          generation: widget.generation,
          volume: volume,
        ),
      );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _amount.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        final query = _controller.query;
        final groups =
            snapshot
                ?.groups()
                .where(
                  (group) => group.variants.any(
                    (o) =>
                        widget.assets.any((a) => a.ticker == o.coin) &&
                        o.coin.toLowerCase().contains(_filter),
                  ),
                )
                .toList() ??
            <BestOfferGroup>[];
        BestOffer chosen(BestOfferGroup group) {
          final known = group.variants
              .where((o) => widget.assets.any((a) => a.ticker == o.coin))
              .toList();
          final key = '${group.coin}:${known.first.uuid}';
          return known.where((o) => o.coin == _variants[key]).firstOrNull ??
              known
                  .where(
                    (o) => widget.assets.any(
                      (a) => a.ticker == o.coin && a.active,
                    ),
                  )
                  .firstOrNull ??
              known.first;
        }

        groups.sort((a, b) {
          final first = chosen(a);
          final second = chosen(b);
          final aUsd = widget.priceOf(first.coin);
          final bUsd = widget.priceOf(second.coin);
          if (!_bestFirst) return first.coin.compareTo(second.coin);
          if (aUsd == null || bUsd == null) {
            return aUsd == bUsd
                ? first.coin.compareTo(second.coin)
                : aUsd == null
                ? 1
                : -1;
          }
          final cmp = (first.price * aUsd).compareTo(second.price * bUsd);
          return _side == BestOfferSide.buy ? cmp : -cmp;
        });
        final focusedGroup =
            groups
                .where((g) => '${g.coin}:${chosen(g).uuid}' == _focusedGroup)
                .firstOrNull ??
            groups.firstOrNull;
        final focused = focusedGroup == null ? null : chosen(focusedGroup);
        final focusedActive =
            focused != null &&
            query != null &&
            widget.assets.any((a) => a.ticker == query.coin && a.active) &&
            widget.assets.any((a) => a.ticker == focused.coin && a.active);
        final canUse =
            widget.canUseOffer &&
            focused != null &&
            query != null &&
            focused.fits(query.volume!) &&
            focusedActive &&
            !_controller.failed &&
            !_controller.loading;
        return BestOrdersCard(
          key: const Key('best-orders-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Best Orders',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    width: 180,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: dexPageColors.frontPlateInner,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      key: const Key('best-orders-coin'),
                      value: _coin,
                      items: widget.assets
                          .map(
                            (asset) => DropdownMenuItem(
                              value: asset.ticker,
                              child: Tooltip(
                                message: asset.ticker,
                                child: Text(
                                  asset.ticker,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _coin = value);
                        _scheduleQuery();
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: dexPageColors.frontPlateInner,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: DropdownButton<BestOfferSide>(
                      key: const Key('best-orders-side'),
                      value: _side,
                      items: const [
                        DropdownMenuItem(
                          value: BestOfferSide.buy,
                          child: Text('Buy'),
                        ),
                        DropdownMenuItem(
                          value: BestOfferSide.sell,
                          child: Text('Sell'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _side = value);
                        _scheduleQuery();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Amount of ${_coin ?? "coin"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              TextField(
                key: const Key('best-orders-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(49)],
                decoration: InputDecoration(
                  hintText: '0',
                  helperText: 'Use a decimal point. Offers exclude fees.',
                  helperMaxLines: 3,
                ),
                onChanged: (_) => _scheduleQuery(),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('best-orders-search'),
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Search coin',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _filter = value.trim().toLowerCase()),
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    key: const Key('best-orders-refresh'),
                    onPressed: query == null || _controller.loading
                        ? null
                        : _controller.refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _bestFirst = !_bestFirst),
                    child: Text(
                      _bestFirst ? 'Sort: best USD quote' : 'Sort: coin',
                    ),
                  ),
                ],
              ),
              if (_controller.loading) const LinearProgressIndicator(),
              if (!widget.signedIn)
                const Text('Sign in to inspect offers in this session.')
              else if (query == null)
                const Text('Enter a positive amount to see best orders.')
              else if (_controller.failed)
                const Text(
                  'Unable to update market offers. Previous results, if shown, are outdated.',
                  key: Key('best-orders-error'),
                )
              else if (snapshot != null && groups.isEmpty)
                const Text(
                  'No matching offers for this amount.',
                  key: Key('best-orders-empty'),
                ),
              if (snapshot != null) ...[
                Text(
                  'USD comparison uses the last available market quotes and may be outdated.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Updated ${snapshot.receivedAt.toLocal().toIso8601String().substring(11, 19)} · gross estimates',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                BestOrdersResults(
                  buy: _side == BestOfferSide.buy,
                  onSelect: (key) => setState(() => _focusedGroup = key),
                  onVariant: (key, value) =>
                      setState(() => _variants[key] = value),
                  lines: groups.take(_visibleLimit).map((group) {
                    final offer = chosen(group);
                    final usdPrice = widget.priceOf(offer.coin);
                    final difference = bestOfferDifference(
                      offer,
                      widget.priceOf(query!.coin),
                      usdPrice,
                    );
                    final favorable =
                        difference != null &&
                        (_side == BestOfferSide.buy
                            ? difference < Rational.zero
                            : difference > Rational.zero);
                    return BestOrdersResultLine(
                      id: '${group.coin}:${offer.uuid}',
                      amount: displayBestOfferNumber(
                        offer.otherAmount(query.volume!),
                      ),
                      ticker: offer.coin,
                      variants: group.variants
                          .where(
                            (o) => widget.assets.any((a) => a.ticker == o.coin),
                          )
                          .map((o) => o.coin)
                          .toList(),
                      usd: usdPrice == null
                          ? 'N/A'
                          : '\$${displayBestOfferNumber(offer.otherAmount(query.volume!) * usdPrice, 2)}',
                      comparison: difference == null
                          ? 'N/A'
                          : '${displayBestOfferNumber(difference, 2)}%',
                      comparisonColor:
                          difference == null || difference == Rational.zero
                          ? null
                          : favorable
                          ? theme.custom.bidsColor
                          : theme.custom.asksColor,
                      selected: identical(group, focusedGroup),
                    );
                  }).toList(),
                ),
                if (groups.length > _visibleLimit)
                  TextButton(
                    onPressed: () => setState(() => _visibleLimit += 20),
                    child: Text(
                      'Show more (${groups.length - _visibleLimit} remaining)',
                    ),
                  ),
                if (focused != null && query != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${focused.coin} · limits ${displayBestOfferNumber(focused.min)}–${displayBestOfferNumber(focused.max)} ${query.coin}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (!focusedActive)
                    const Text('Activate both coins manually in Wallet first.'),
                  if (!widget.canUseOffer)
                    const Text(
                      'Switch to Taker order to use an existing offer.',
                    ),
                  if (!focused.fits(query.volume!))
                    const Text(
                      'This offer does not cover the requested amount.',
                    ),
                  TextButton(
                    key: ValueKey(
                      'use-best-offer-${focused.coin}-${focused.uuid}',
                    ),
                    onPressed: canUse
                        ? () => widget.onUse(query, focused)
                        : null,
                    child: const Text('Use offer'),
                  ),
                  const Text(
                    'The offer is verified again before filling the form. Fees are estimated in the form.',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
