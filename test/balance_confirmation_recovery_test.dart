import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_balance_confirmation_controller.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_info.dart';
import '../test_units/tests/utils/test_util.dart';

void main() {
  test('deadline does not duplicate the read; late fresh zero confirms', () {
    fakeAsync((clock) {
      final gate = Completer<BalanceInfo>();
      var calls = 0;
      final controller = CoinDetailsBalanceConfirmationController(
        fetchConfirmedBalance: () {
          calls++;
          return gate.future;
        },
        requestTimeout: const Duration(seconds: 1),
      );
      controller.bootstrap();
      clock.elapse(const Duration(seconds: 2));
      expect(controller.hasFailed, isTrue);
      controller.retry();
      controller.bootstrap();
      clock.flushMicrotasks();
      expect(calls, 1);
      expect(controller.canRetry, isFalse);
      gate.complete(BalanceInfo.zero());
      clock.flushMicrotasks();
      expect(controller.isConfirmed, isTrue);
      expect(controller.latestBalance, BalanceInfo.zero());
      controller.dispose();
    });
  });
  test('manual retry recovers after three genuine failures', () {
    fakeAsync((clock) {
      var calls = 0;
      var succeeds = false;
      final controller = CoinDetailsBalanceConfirmationController(
        fetchConfirmedBalance: () async {
          calls++;
          if (!succeeds) throw StateError('offline');
          return BalanceInfo.zero();
        },
      );
      controller.bootstrap();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 3));
      clock.flushMicrotasks();
      expect(calls, 3);
      expect(controller.hasFailed, isTrue);
      succeeds = true;
      controller.retry();
      clock.flushMicrotasks();
      expect(calls, 4);
      expect(controller.isConfirmed, isTrue);
      controller.dispose();
    });
  });
  test('disposing page prevents late result notifications', () async {
    final gate = Completer<BalanceInfo>();
    final controller = CoinDetailsBalanceConfirmationController(
      fetchConfirmedBalance: () => gate.future,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    final loading = controller.bootstrap();
    controller.dispose();
    final before = notifications;
    gate.complete(BalanceInfo.zero());
    await loading;
    await Future<void>.delayed(Duration.zero);
    expect(notifications, before);
    expect(controller.isConfirmed, isFalse);
  });
  for (final cached in [false, true]) {
    testWidgets(
      'failed ${cached ? "cached zero" : "missing"} balance displays retry, not a spinner',
      (tester) async {
        var retries = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                updateScreenType(context);
                return Scaffold(
                  body: CoinDetailsBalanceContent(
                    coin: setCoin(coinAbbr: 'TRX'),
                    hideBalances: false,
                    isConfirmed: false,
                    latestBalance: cached ? BalanceInfo.zero() : null,
                    fiatBalance: const Text('fiat'),
                    hasFailed: true,
                    onRetry: () => retries++,
                  ),
                );
              },
            ),
          ),
        );
        expect(
          find.byKey(const Key('coin-details-balance-refreshing')),
          findsNothing,
        );
        expect(
          find.text(
            cached
                ? 'Balance not confirmed. Displaying the last known value.'
                : 'Unable to load balance.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Retry'));
        expect(retries, 1);
      },
    );
  }
}
