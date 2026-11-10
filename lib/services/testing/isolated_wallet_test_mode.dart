/// Capability granted only after main_isolated validates the disposable profile.
abstract final class IsolatedWalletTestMode {
  static const approvedRoot =
      r'E:\codex\LitecoinCashDEX-Next\.isolated-testing\mission-20261103';
  static const requested = bool.fromEnvironment('LCC_NEXT_WALLET_ONLY_TEST');
  static bool _profileApproved = false;
  static bool get enabled {
    if (!requested) return false;
    if (!_profileApproved) {
      throw StateError(
        'Wallet-only mode requires a validated disposable profile',
      );
    }
    return true;
  }

  static bool isScopeValid({
    required bool requested,
    required bool isolated,
    required bool fullTest,
    required String compiledRoot,
    required String validatedRoot,
    required int configuredRpcPort,
    required int actualRpcPort,
  }) =>
      requested &&
      isolated &&
      !fullTest &&
      compiledRoot == approvedRoot &&
      validatedRoot == approvedRoot &&
      configuredRpcPort == 17993 &&
      actualRpcPort == 17993;

  /// Called only after marker, path and environment checks in main_isolated.
  static void approveValidatedProfile({
    required String root,
    required int rpcPort,
  }) {
    _profileApproved = false;
    if (!requested) return;
    if (!isScopeValid(
      requested: requested,
      isolated: const bool.fromEnvironment('LCC_NEXT_ISOLATED'),
      fullTest: const bool.fromEnvironment('LCC_NEXT_FULL_TEST'),
      compiledRoot: const String.fromEnvironment('LCC_NEXT_TEST_ROOT'),
      validatedRoot: root,
      configuredRpcPort: const int.fromEnvironment('LCC_NEXT_TEST_RPC_PORT'),
      actualRpcPort: rpcPort,
    )) {
      throw StateError('Wallet-only mode requires the approved isolated scope');
    }
    _profileApproved = true;
  }
}
