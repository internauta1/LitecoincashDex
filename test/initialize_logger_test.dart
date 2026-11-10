import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/services/logger/get_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test(
    'logging can initialize before a Windows KDF generation exists',
    () async {
      final operations = KdfOperationsLocalExecutable.create(
        logCallback: (_) {},
        config: LocalConfig(https: false, rpcPassword: 'offline-test-only'),
        executableName: 'mm2_lccnext_8762',
      );
      addTearDown(operations.dispose);

      Future<String?> version() async {
        final response = await operations.mm2Rpc({'method': 'version'});
        return response['result'] as String?;
      }

      await expectLater(
        version(),
        throwsA(
          isA<KdfTransportException>().having(
            (error) => error.reason,
            'reason',
            KdfTransportFailure.generationUnavailable,
          ),
        ),
      );
      await initializeLogger(_VersionApi(version));
    },
    skip: !const bool.fromEnvironment('LCC_NEXT_WINDOWS_8762'),
  );

  test('logging still reports other version failures', () async {
    const failure = KdfTransportException(
      KdfTransportFailure.ownershipUnverified,
    );
    await expectLater(
      initializeLogger(_VersionApi(() async => throw failure)),
      throwsA(same(failure)),
    );
  });
}

class _VersionApi extends Fake implements Mm2Api {
  _VersionApi(this._version);

  final Future<String?> Function() _version;

  @override
  Future<String?> version() => _version();
}
