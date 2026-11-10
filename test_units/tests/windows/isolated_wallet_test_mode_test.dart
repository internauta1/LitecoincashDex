import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/testing/isolated_wallet_test_mode.dart';

bool scope({
  bool requested = true,
  bool isolated = true,
  bool fullTest = false,
  String compiledRoot = IsolatedWalletTestMode.approvedRoot,
  String validatedRoot = IsolatedWalletTestMode.approvedRoot,
  int configuredRpcPort = 17993,
  int actualRpcPort = 17993,
}) => IsolatedWalletTestMode.isScopeValid(
  requested: requested,
  isolated: isolated,
  fullTest: fullTest,
  compiledRoot: compiledRoot,
  validatedRoot: validatedRoot,
  configuredRpcPort: configuredRpcPort,
  actualRpcPort: actualRpcPort,
);
void main() {
  test(
    'wallet-only scope accepts the approved disposable profile',
    () => expect(scope(), isTrue),
  );
  test('normal build cannot acquire experimental wallet policy', () {
    expect(IsolatedWalletTestMode.requested, isFalse);
    expect(IsolatedWalletTestMode.enabled, isFalse);
  });
  test(
    'mode must be explicitly requested',
    () => expect(scope(requested: false), isFalse),
  );
  test(
    'regular entry scope is rejected',
    () => expect(scope(isolated: false), isFalse),
  );
  test(
    'full test mode is incompatible with wallet-only validation',
    () => expect(scope(fullTest: true), isFalse),
  );
  test(
    'principal RPC is rejected',
    () =>
        expect(scope(configuredRpcPort: 17883, actualRpcPort: 17883), isFalse),
  );
  test(
    'classic RPC is rejected',
    () => expect(scope(configuredRpcPort: 7863, actualRpcPort: 7863), isFalse),
  );
  test(
    'other experimental ports are rejected',
    () =>
        expect(scope(configuredRpcPort: 17994, actualRpcPort: 17994), isFalse),
  );
  test(
    'runtime RPC cannot differ from its configured port',
    () => expect(scope(actualRpcPort: 17994), isFalse),
  );
  test(
    'a principal profile cannot be approved',
    () => expect(scope(validatedRoot: r'E:\LitecoinCashDEX-Next'), isFalse),
  );
  test(
    'compiled root must match the approved profile',
    () => expect(scope(compiledRoot: r'E:\other'), isFalse),
  );
}
