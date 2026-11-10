import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/router/navigators/app_router_delegate.dart';
import 'package:web_dex/router/parsers/fiat_route_parser.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/fiat_state.dart';
import 'package:web_dex/router/state/routing_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final link in ['/fiat', '/fiat/trading_details/old-order']) {
    test('retired bookmark $link returns to Wallet', () {
      final route = fiatRouteParser.getRoutePath(Uri.parse(link));
      expect(route, isA<WalletRoutePath>());
      expect(route.location, WalletRoutePath.wallet().location);
    });
  }

  late RoutingState savedRouting;
  late AppRouterDelegate router;
  setUp(() {
    savedRouting = routingState;
    routingState = RoutingState();
    router = AppRouterDelegate();
  });
  tearDown(() {
    router.dispose();
    routingState = savedRouting;
  });

  test(
    'in-memory legacy Buy/Sell route cannot reopen the removed page',
    () async {
      routingState.selectedMenu = MainMenuValue.dex;
      await router.setNewRoutePath(
        FiatRoutePath.swapDetails(FiatAction.tradingDetails, 'offline-fixture'),
      );
      expect(routingState.selectedMenu, MainMenuValue.wallet);
      expect(router.currentConfiguration, isA<WalletRoutePath>());
    },
  );

  test('Swap routes retain the selected pair, side and draft amount', () async {
    await router.setNewRoutePath(
      DexRoutePath.dex(
        fromCurrency: 'LCC-segwit',
        toCurrency: 'LTC',
        fromAmount: '1000',
        orderType: 'maker',
      ),
    );
    expect(routingState.selectedMenu, MainMenuValue.dex);
    final route = router.currentConfiguration! as DexRoutePath;
    expect(route.fromCurrency, 'LCC-segwit');
    expect(route.toCurrency, 'LTC');
    expect(route.fromAmount, '1000');
    expect(route.orderType, 'maker');
  });

  test('Wallet, NFTs and Settings remain reachable', () async {
    await router.setNewRoutePath(WalletRoutePath.coinDetails('ETH'));
    expect(routingState.walletState.selectedCoin, 'ETH');
    await router.setNewRoutePath(NftRoutePath.nfts());
    expect(routingState.selectedMenu, MainMenuValue.nft);
    expect(router.currentConfiguration, isA<NftRoutePath>());
    await router.setNewRoutePath(SettingsRoutePath.privacy());
    expect(routingState.selectedMenu, MainMenuValue.settings);
    expect(routingState.settingsState.selectedMenu, SettingsMenuValue.privacy);
  });
}
