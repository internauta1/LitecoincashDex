import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:path/path.dart' as p;
import 'package:web_dex/main.dart' as application;
import 'package:web_dex/services/testing/disposable_runtime_profile.dart';
import 'package:web_dex/services/testing/isolated_wallet_test_mode.dart';
import 'package:web_dex/services/testing/isolated_sse_trace_file.dart';

/// Experimental entry point: refuses startup without the approved profile.
Future<void> main() async {
  const root = String.fromEnvironment('LCC_NEXT_TEST_ROOT');
  if (!Platform.isWindows ||
      const bool.fromEnvironment('LCC_NEXT_FULL_TEST') ||
      root.isEmpty ||
      !const bool.fromEnvironment('LCC_NEXT_ISOLATED') ||
      Platform.environment['LCC_NEXT_APPROVED_PROFILE'] != root ||
      kDefaultKdfRpcPort < 1024 ||
      kDefaultKdfRpcPort > 65535 ||
      [17883, 7863].contains(kDefaultKdfRpcPort)) {
    throw StateError('Use the approved isolated-test launcher');
  }
  WidgetsFlutterBinding.ensureInitialized();
  for (final variable in [
    'APPDATA',
    'LOCALAPPDATA',
    'USERPROFILE',
    'HOME',
    'TEMP',
    'TMP',
  ]) {
    final value = Platform.environment[variable];
    if (value == null || !p.isWithin(root, value)) {
      throw StateError('Isolated environment required: $variable');
    }
  }
  final profile = await DisposableRuntimeProfile.open(root);
  profile.install();
  IsolatedWalletTestMode.approveValidatedProfile(
    root: profile.root,
    rpcPort: kDefaultKdfRpcPort,
  );
  if (const bool.fromEnvironment('LCC_NEXT_SSE_DIAGNOSTICS')) {
    final liveTrace = IsolatedSseTraceFile.create(profile);
    SseDiagnostics.isolatedRun = SseDiagnostics((line) {
      liveTrace.write(line);
    });
  }
  final trace = File(
    p.join(
      root,
      'logs',
      'startup-${DateTime.now().microsecondsSinceEpoch}.log',
    ),
  );
  await application.main(
    startupDiagnostic: kWindows8762Release && SseDiagnostics.isolatedRun != null
        ? (stage) {
            try {
              trace.writeAsStringSync(
                '${DateTime.now().toUtc().toIso8601String()} $stage\n',
                mode: FileMode.append,
              );
            } on FileSystemException {
              // Diagnostics must not prevent the disposable wallet opening.
            }
          }
        : null,
  );
}
