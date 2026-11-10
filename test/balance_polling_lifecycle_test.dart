import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart'
    show BalanceEvent;
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';

class _Auth extends Fake implements KomodoDefiLocalAuth {
  _Auth() {
    sessions.observe(user);
  }
  final sessions = AuthSessionTracker();
  final user = const KdfUser(
    walletId: WalletId(
      name: 'offline-poll',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
  );
  @override
  Future<KdfUser?> get currentUser async => user;
  @override
  Future<AuthSessionContext> captureSessionContext() async => sessions.current!;
  @override
  bool isSessionContextCurrent(AuthSessionContext context) =>
      sessions.isCurrent(context);
  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!sessions.isCurrent(context)) throw const AuthSessionChangedException();
  }

  @override
  Stream<AuthSessionContext?> watchSessionContext() => sessions.changes;
}

class _Activation extends Mock implements SharedActivationCoordinator {}

class _Pubkeys extends Mock implements PubkeyManager {}

class _Lookup extends Mock implements IAssetLookup {}

class _Events extends Mock implements EventStreamingManager {}

class _History extends Mock implements AssetHistoryStorage {}

void main() {
  test(
    'slow stale-guard reads do not overlap and disposal prevents re-arming',
    () {
      fakeAsync((clock) {
        final asset = Asset.fromJson({
          'coin': 'ETH',
          'type': 'ETH',
          'fname': 'Ethereum',
          'chain_id': 1,
          'is_testnet': false,
          'nodes': [
            {'url': 'https://rpc.invalid'},
          ],
          'swap_contract_address': '0x0000000000000000000000000000000000000001',
          'fallback_swap_contract':
              '0x0000000000000000000000000000000000000001',
        });
        final auth = _Auth();
        final activation = _Activation();
        final pubkeys = _Pubkeys();
        final lookup = _Lookup();
        final events = _Events();
        final history = _History();
        final frames = StreamController<BalanceEvent>.broadcast();
        final keys = AssetPubkeys(
          assetId: asset.id,
          keys: [
            PubkeyInfo(
              address: '0x0000000000000000000000000000000000000001',
              derivationPath: null,
              chain: null,
              balance: BalanceInfo.zero(),
              coinTicker: 'ETH',
            ),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        );
        final requests = <Completer<AssetPubkeys>>[];
        when(() => lookup.fromId(asset.id)).thenReturn(asset);
        when(
          () => activation.isAssetActive(asset.id),
        ).thenAnswer((_) async => true);
        when(
          () => activation.activateAsset(asset),
        ).thenAnswer((_) async => ActivationResult.success(asset.id));
        when(() => activation.wasFreshlyActivated(asset.id)).thenReturn(false);
        when(
          () => history.getWalletAssets(auth.user.walletId),
        ).thenAnswer((_) async => {'ETH'});
        when(() => pubkeys.getPubkeys(asset)).thenAnswer((_) async => keys);
        when(() => pubkeys.refreshPubkeys(asset)).thenAnswer((_) {
          final request = Completer<AssetPubkeys>();
          requests.add(request);
          return request.future;
        });
        when(
          () => events.subscribeToBalance(coin: 'ETH', streamerCoin: null),
        ).thenAnswer((_) async => frames.stream.listen((_) {}));
        final manager = BalanceManager(
          assetLookup: lookup,
          auth: auth,
          pubkeyManager: pubkeys,
          activationCoordinator: activation,
          eventStreamingManager: events,
          assetHistoryStorage: history,
        );
        final subscription = manager
            .watchBalance(asset.id)
            .listen((_) {}, onError: (Object _) {});
        clock.flushMicrotasks();
        expect(
          requests.length,
          1,
          reason: 'the streaming watcher must have started a fresh stale guard',
        );
        clock.elapse(const Duration(seconds: 90));
        clock.flushMicrotasks();
        expect(requests.length, 1);
        requests.single.complete(keys);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 29));
        expect(requests.length, 1);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(requests.length, 2);
        unawaited(manager.dispose());
        clock.flushMicrotasks();
        requests.last.complete(keys);
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 3));
        expect(requests.length, 2);
        unawaited(subscription.cancel());
        unawaited(frames.close());
        clock.flushMicrotasks();
      });
    },
  );
}
