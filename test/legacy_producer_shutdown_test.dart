import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/app_shutdown.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/blocs/orderbook_bloc.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import '../test_units/tests/utils/test_util.dart';

class _Sdk extends Mock implements KomodoDefiSdk {}

class _Auth extends Mock implements KomodoDefiLocalAuth {}

class _Coins extends Mock implements CoinsRepo {}

class _Dex extends Mock implements DexRepository {}

class _Api extends Mock implements Mm2Api {}

void main() {
  test(
    'Maker drains pending auth and cancels debounce before SDK disposal',
    () async {
      final sdk = _Sdk();
      final auth = _Auth();
      final authResult = Completer<bool>();
      when(() => sdk.auth).thenReturn(auth);
      when(() => auth.isSignedIn()).thenAnswer((_) => authResult.future);
      final maker = MakerFormBloc(
        api: _Api(),
        kdfSdk: sdk,
        coinsRepository: _Coins(),
        dexRepository: _Dex(),
      );
      maker.sellCoin = setCoin(coinAbbr: 'KMD');
      var drained = false;
      final closing = maker.dispose().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      authResult.complete(false);
      await closing.timeout(const Duration(seconds: 2));
      when(() => sdk.auth).thenThrow(StateError('SDK disposed'));
      clearInteractions(sdk);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      verifyNever(() => sdk.auth);
      await maker.dispose();
    },
  );
  test(
    'disposed Orderbook cannot start subscriptions or fallback RPCs',
    () async {
      final sdk = _Sdk();
      final orderbook = OrderbookBloc(sdk: sdk);
      await orderbook.dispose();
      expect(
        await orderbook.getOrderbookStream('LCC', 'LTC').toList(),
        isEmpty,
      );
      verifyZeroInteractions(sdk);
      await orderbook.dispose();
    },
  );
  test(
    'late Orderbook registration is cancelled before SDK disposal',
    () async {
      final sdk = _Sdk();
      final pending = Completer<StreamSubscription<OrderbookEvent>>();
      final source = StreamController<OrderbookEvent>.broadcast();
      when(
        () => sdk.subscribeToOrderbook(base: 'LCC', rel: 'LTC'),
      ).thenAnswer((_) => pending.future);
      when(
        () => sdk.client,
      ).thenThrow(StateError('synthetic offline RPC unavailable'));
      final orderbook = OrderbookBloc(sdk: sdk);
      final view = orderbook.getOrderbookStream('LCC', 'LTC').listen((_) {});
      final shutdown = AppShutdown()..register(orderbook, orderbook.dispose);
      var sdkDisposed = false;
      final closing = shutdown.stopConsumers().then((_) => sdkDisposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(sdkDisposed, isFalse);
      clearInteractions(sdk);
      pending.complete(source.stream.listen((_) {}));
      await closing;
      expect(source.hasListener, isFalse);
      expect(sdkDisposed, isTrue);
      verifyZeroInteractions(sdk);
      await view.cancel();
      await source.close();
    },
  );
}
