import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login_metadata.dart';

import '../test_units/support/legal_onboarding_harness.dart';

const _missingListener = KdfTcpOwnershipException(
  KdfTcpOwnershipCheck.listener,
  KdfTcpOwnershipEvidence.missing,
);

KdfUser _user(String name) => KdfUser(
  walletId: WalletId.fromName(
    name,
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

class _Auth extends Fake implements KomodoDefiLocalAuth {
  Future<List<KdfUser>> Function() read = () async => [];
  int calls = 0;
  @override
  Future<List<KdfUser>> getUsers() {
    calls++;
    return read();
  }
}

class _Sdk extends Fake implements KomodoDefiSdk {
  _Sdk(this.auth);
  @override
  final KomodoDefiLocalAuth auth;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('metadata deadline is finite and pending reads are shared', (
    tester,
  ) async {
    final result = Completer<KdfUser?>();
    var calls = 0;
    final metadata = WalletLoginMetadata(
      read: () {
        calls++;
        return result.future;
      },
    );
    addTearDown(metadata.dispose);
    final first = metadata.load();
    await metadata.load();
    await tester.pump(const Duration(seconds: 36));
    expect(metadata.status, WalletLoginMetadataStatus.unavailable);
    expect(metadata.canRetry, isFalse);
    await metadata.load();
    expect(calls, 1);
    result.complete(_user('sample'));
    await first;
    expect(metadata.status, WalletLoginMetadataStatus.ready);
  });

  testWidgets('metadata failure permits a fresh manual retry', (tester) async {
    var fail = true;
    final metadata = WalletLoginMetadata(
      read: () async {
        if (fail) throw _missingListener;
        return _user('sample');
      },
    );
    addTearDown(metadata.dispose);
    await metadata.load();
    expect(metadata.status, WalletLoginMetadataStatus.unavailable);
    expect(metadata.user, isNull);
    fail = false;
    await metadata.load();
    expect(metadata.status, WalletLoginMetadataStatus.ready);
  });

  testWidgets(
    'wallet type is not ready while its saved preference is pending',
    (tester) async {
      final preference = Completer<bool?>();
      final metadata = WalletLoginMetadata(
        read: () async => _user('sample'),
        readHdPreference: () => preference.future,
      );
      addTearDown(metadata.dispose);
      final read = metadata.load();
      await tester.pump();
      expect(metadata.status, WalletLoginMetadataStatus.loading);
      preference.complete(false);
      await read;
      expect(metadata.status, WalletLoginMetadataStatus.ready);
      expect(metadata.hdPreference, isFalse);
    },
  );

  testWidgets('failed preference read is not mistaken for the default mode', (
    tester,
  ) async {
    final metadata = WalletLoginMetadata(
      read: () async => _user('sample'),
      readHdPreference: () async =>
          throw StateError('test preference unavailable'),
    );
    addTearDown(metadata.dispose);
    await metadata.load();
    expect(metadata.status, WalletLoginMetadataStatus.unavailable);
    expect(metadata.user, isNull);
  });

  testWidgets('late failure after disposal is consumed without notifying', (
    tester,
  ) async {
    final result = Completer<KdfUser?>();
    final metadata = WalletLoginMetadata(read: () => result.future);
    var notices = 0;
    metadata.addListener(() => notices++);
    final read = metadata.load();
    metadata.dispose();
    result.completeError(_missingListener);
    await read;
    expect(notices, 1);
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpLogin(
    WidgetTester tester,
    LegalFormHarness harness,
    _Auth auth,
    void Function(String, Wallet, bool) onLogin,
  ) => harness.pump(
    tester,
    RepositoryProvider<KomodoDefiSdk>.value(
      value: _Sdk(auth),
      child: WalletLogIn(
        wallet: legalTestWallet(),
        onLogin: onLogin,
        onCancel: () {},
      ),
    ),
  );

  UiPrimaryButton submit(WidgetTester tester) => tester.widget<UiPrimaryButton>(
    find.byKey(const Key('wallet-login-submit')),
  );

  testWidgets(
    'actual login handles missing listener and retries without changing HD mode',
    (tester) async {
      final harness = LegalFormHarness();
      final auth = _Auth()..read = () async => throw _missingListener;
      Wallet? submitted;
      await pumpLogin(
        tester,
        harness,
        auth,
        (_, wallet, _) => submitted = wallet,
      );
      expect(tester.takeException(), isNull);
      expect(submit(tester).onPressed, isNull);
      expect(
        find.byKey(const Key('wallet-login-metadata-retry')),
        findsOneWidget,
      );
      auth.read = () async => [_user(legalTestWallet().name)];
      await tester.tap(find.byKey(const Key('wallet-login-metadata-retry')));
      await tester.pumpAndSettle();
      expect(auth.calls, 2);
      expect(submit(tester).onPressed, isNotNull);
      await tester.ensureVisible(find.byKey(const Key('wallet-login-submit')));
      await tester.tap(find.byKey(const Key('wallet-login-submit')));
      await tester.pumpAndSettle();
      expect(submitted?.config.type, WalletType.hdwallet);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual login blocks keyboard submission until metadata is confirmed',
    (tester) async {
      final harness = LegalFormHarness();
      final result = Completer<List<KdfUser>>();
      final auth = _Auth()..read = () => result.future;
      var submissions = 0;
      await pumpLogin(tester, harness, auth, (_, _, _) => submissions++);
      expect(submit(tester).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submissions, 0);
      result.complete([_user(legalTestWallet().name)]);
      await tester.pumpAndSettle();
      expect(submit(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual login stops visual loading after deadline without another query',
    (tester) async {
      final harness = LegalFormHarness();
      final result = Completer<List<KdfUser>>();
      final auth = _Auth()..read = () => result.future;
      await pumpLogin(tester, harness, auth, (_, _, _) {});
      await tester.pump(const Duration(seconds: 36));
      final retry = tester.widget<TextButton>(
        find.byKey(const Key('wallet-login-metadata-retry')),
      );
      expect(retry.onPressed, isNull);
      expect(submit(tester).onPressed, isNull);
      expect(auth.calls, 1);
      await tester.pumpWidget(const SizedBox());
      result.completeError(_missingListener);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual login rejects missing wallet metadata rather than guessing a type',
    (tester) async {
      final harness = LegalFormHarness();
      final auth = _Auth()..read = () async => [_user('another-sample')];
      await pumpLogin(tester, harness, auth, (_, _, _) {});
      expect(submit(tester).onPressed, isNull);
      expect(
        find.byKey(const Key('wallet-login-metadata-retry')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing wallet discards the previous in-flight metadata result',
    (tester) async {
      final harness = LegalFormHarness();
      final first = Completer<List<KdfUser>>();
      final second = Completer<List<KdfUser>>();
      final auth = _Auth();
      auth.read = () => auth.calls == 1 ? first.future : second.future;
      final wallet = ValueNotifier(legalTestWallet());
      addTearDown(wallet.dispose);
      Wallet? submitted;
      await harness.pump(
        tester,
        RepositoryProvider<KomodoDefiSdk>.value(
          value: _Sdk(auth),
          child: ValueListenableBuilder<Wallet>(
            valueListenable: wallet,
            builder: (_, selected, _) => WalletLogIn(
              wallet: selected,
              onLogin: (_, result, _) => submitted = result,
              onCancel: () {},
            ),
          ),
        ),
      );
      wallet.value = legalTestWallet().copyWith(
        id: 'other-id',
        name: 'Other sample',
      );
      await tester.pumpAndSettle();
      first.complete([_user(legalTestWallet().name)]);
      await tester.pumpAndSettle();
      expect(submit(tester).onPressed, isNull);
      second.complete([_user('Other sample')]);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('wallet-login-submit')));
      await tester.tap(find.byKey(const Key('wallet-login-submit')));
      await tester.pumpAndSettle();
      expect(submitted?.name, 'Other sample');
      expect(submitted?.config.type, WalletType.hdwallet);
      expect(tester.takeException(), isNull);
    },
  );
}
