import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:web_dex/services/testing/disposable_runtime_profile.dart';

class RecordingStorage extends FlutterSecureStoragePlatform {
  final optionsSeen = <Map<String, String>>[];
  void record(Map<String, String> options) => optionsSeen.add(options);
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    record(options);
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    record(options);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    record(options);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    record(options);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    record(options);
    return {};
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    record(options);
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('next-profile-unit-');
    await File(
      p.join(root.path, DisposableRuntimeProfile.markerName),
    ).writeAsString(DisposableRuntimeProfile.markerValue);
  });
  tearDown(() => root.delete(recursive: true));

  test('a profile requires an absolute path and disposable marker', () async {
    await expectLater(
      DisposableRuntimeProfile.open('relative'),
      throwsStateError,
    );
    await File(p.join(root.path, DisposableRuntimeProfile.markerName)).delete();
    await expectLater(
      DisposableRuntimeProfile.open(root.path),
      throwsStateError,
    );
  });

  test(
    'all storage and both preferences APIs stay inside the profile',
    () async {
      final oldPaths = PathProviderPlatform.instance;
      final oldPreferences = SharedPreferencesStorePlatform.instance;
      final oldAsync = SharedPreferencesAsyncPlatform.instance;
      final oldSecure = FlutterSecureStoragePlatform.instance;
      addTearDown(() {
        PathProviderPlatform.instance = oldPaths;
        SharedPreferencesStorePlatform.instance = oldPreferences;
        SharedPreferencesAsyncPlatform.instance = oldAsync;
        FlutterSecureStoragePlatform.instance = oldSecure;
      });
      final profile = await DisposableRuntimeProfile.open(root.path);
      profile.install();
      final paths = PathProviderPlatform.instance;
      for (final location in await Future.wait([
        paths.getTemporaryPath(),
        paths.getApplicationSupportPath(),
        paths.getApplicationDocumentsPath(),
        paths.getApplicationCachePath(),
        paths.getDownloadsPath(),
      ])) {
        expect(p.isWithin(root.path, location!), isTrue);
      }
      final prefs = SharedPreferencesStorePlatform.instance;
      expect(await prefs.getAll(), isEmpty);
      await prefs.setValue('String', 'flutter.synthetic', 'test-only');
      final file = File(
        p.join(root.path, 'support', 'shared_preferences.json'),
      );
      expect(await file.readAsString(), contains('test-only'));
      expect(await prefs.getAll(), {'flutter.synthetic': 'test-only'});
    final asyncPrefs = SharedPreferencesAsyncPlatform.instance!;
    await asyncPrefs.setString('synthetic_async', 'async-test-only',
        const SharedPreferencesOptions());
    expect(await asyncPrefs.getString('synthetic_async',
        const SharedPreferencesOptions()), 'async-test-only');
    expect(await file.readAsString(), contains('async-test-only'));
      expect(
        await Directory(
          p.join(
            root.path,
            'documents',
            'LitecoinCashDEXNext',
            'secure-kdf-temp-legacy',
          ),
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'secure storage never falls back to the existing Windows vault',
    () async {
      final recorded = RecordingStorage();
      final storage = ProfileSecureStorage(recorded);
      final options = {'useBackwardCompatibility': 'true'};
      await storage.read(key: 'synthetic', options: options);
      await storage.write(
        key: 'synthetic',
        value: 'test-only',
        options: options,
      );
      await storage.delete(key: 'synthetic', options: options);
      await storage.readAll(options: options);
      await storage.deleteAll(options: options);
      await storage.containsKey(key: 'synthetic', options: options);
      expect(recorded.optionsSeen, hasLength(6));
      expect(
        recorded.optionsSeen.every(
          (o) => o['useBackwardCompatibility'] == 'false',
        ),
        isTrue,
      );
      expect(options['useBackwardCompatibility'], 'true');
    },
  );
}
