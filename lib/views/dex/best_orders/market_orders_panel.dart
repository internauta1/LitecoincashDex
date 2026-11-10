import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/app_config/app_config.dart' show excludedAssetList;
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/coins_bloc/wallet_coin_projection.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/views/dex/simple/form/taker/taker_order_book.dart';
import 'best_orders_panel.dart';
import 'market_orders_tabs.dart';

class MarketOrdersPanel extends StatefulWidget {
  const MarketOrdersPanel({
    super.key,
    this.orderbook = const TakerOrderbook(),
    this.canUseOffer = true,
  });
  final Widget orderbook;
  final bool canUseOffer;
  @override
  State<MarketOrdersPanel> createState() => _MarketOrdersPanelState();
}

class _MarketOrdersPanelState extends State<MarketOrdersPanel> {
  bool _best = false;
  @override
  Widget build(BuildContext context) {
    final sdk = context.read<KomodoDefiSdk>();
    final taker = context.read<TakerBloc>();
    final coinsRepo = context.read<CoinsRepo>();
    final walletCoins = context.watch<CoinsBloc>().state.walletCoins;
    final auth = context.watch<AuthBloc>().state;
    final policy = context.watch<TradingStatusBloc>().state;
    final coins =
        projectWalletCoinStates(coinsRepo.getKnownCoins(), walletCoins)
            .where(
              (coin) =>
                  !coin.walletOnly &&
                  !excludedAssetList.contains(coin.abbr) &&
                  !coin.isTestCoin &&
                  !coin.isSuspended &&
                  !policy.isAssetBlocked(coin.id),
            )
            .toList()
          ..sort((a, b) => a.abbr.compareTo(b.abbr));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarketOrdersTabs(
          bestOrders: _best,
          onChanged: (value) => setState(() => _best = value),
        ),
        const SizedBox(height: 10),
        if (!_best)
          widget.orderbook
        else
          StreamBuilder<int>(
            stream: sdk.auth.authGenerationChanges,
            initialData: sdk.auth.authGeneration,
            builder: (context, snapshot) {
              final generation = sdk.auth.authGeneration;
              return BestOrdersPanel(
                key: ValueKey('best-orders-session-$generation'),
                repository: taker.bestOffersRepository,
                generation: generation,
                initialCoin: taker.state.sellCoin?.abbr ?? 'LCC',
                signedIn: auth.isSignedIn,
                canUseOffer: widget.canUseOffer,
                assets: coins
                    .map(
                      (coin) => BestOffersAsset(
                        coin.abbr,
                        active: coin.isActive,
                        decimals: coin.decimals,
                      ),
                    )
                    .toList(),
                priceOf: (ticker) {
                  final coin = coinsRepo.getCoin(ticker);
                  if (coin == null) return null;
                  try {
                    final price = sdk.marketData.priceIfKnown(coin.id);
                    if (price == null) return null;
                    final value = Rational.parse(price.toString());
                    return value > Rational.zero ? value : null;
                  } catch (_) {
                    return null;
                  }
                },
                onUse: (query, offer) =>
                    taker.add(TakerUseBestOffer(query, offer)),
              );
            },
          ),
      ],
    );
  }
}
