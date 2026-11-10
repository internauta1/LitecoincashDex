import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:path/path.dart' as p;
import 'package:web_dex/main.dart' as application;
import 'package:web_dex/services/testing/private_manual_profile.dart';

/// Real trading is user-operated. This entry point performs no financial call.
Future<void> main() async {
  const root = String.fromEnvironment('LCC_NEXT_TEST_ROOT');
  if (!Platform.isWindows ||
      !PrivateManualProfile.scopeValid(
        requested: const bool.fromEnvironment('LCC_NEXT_PRIVATE_MANUAL_TEST'),
        isolated: const bool.fromEnvironment('LCC_NEXT_ISOLATED'),
        walletOnly: const bool.fromEnvironment('LCC_NEXT_WALLET_ONLY_TEST'),
        fullTest: const bool.fromEnvironment('LCC_NEXT_FULL_TEST'),
        windows8762: kWindows8762Release,
        root: root,
        approvedEnvironmentRoot:
            Platform.environment['LCC_NEXT_APPROVED_PRIVATE_PROFILE'] ?? '',
        rpcPort: kDefaultKdfRpcPort,
        geoPolicy: const String.fromEnvironment('GEO_BLOCK'),
      ) ||
      const bool.fromEnvironment('LCC_NEXT_SSE_DIAGNOSTICS')) {
    throw StateError('Use the private manual-validation launcher');
  }
  for (final key in [
    'HOME',
    'USERPROFILE',
    'APPDATA',
    'LOCALAPPDATA',
    'TEMP',
    'TMP',
  ]) {
    final value = Platform.environment[key];
    if (value == null || !p.isWithin(root, value)) {
      throw StateError('Private profile environment required');
    }
  }
  WidgetsFlutterBinding.ensureInitialized();
  final profile = await PrivateManualProfile.open(root);
  profile.install();
  await application.main();
}
