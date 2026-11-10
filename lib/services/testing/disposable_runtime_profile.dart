import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

/// Used only by main_isolated.dart. Never discovers or migrates a real profile.
class DisposableRuntimeProfile {
  DisposableRuntimeProfile._(this.root);

  static const markerName = 'ISOLATED_NEXT_PROFILE';
  static const markerValue = 'next-disposable-no-funds-v1';
  final String root;

  static Future<DisposableRuntimeProfile> open(String root) async {
    if (!p.isAbsolute(root)) throw StateError('Absolute test profile required');
    final normalized = p.normalize(root);
    final directory = Directory(normalized);
    if (!await directory.exists() ||
        !p.equals(normalized, await directory.resolveSymbolicLinks())) {
      throw StateError('Test profile missing or redirected');
    }
    final marker = File(p.join(normalized, markerName));
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        (await marker.readAsString()).trim() != markerValue) {
      throw StateError('Disposable profile marker required');
    }
    final profile = DisposableRuntimeProfile._(normalized);
    for (final folder in [
      'home',
      'appdata',
      'localappdata',
      'documents',
      'support',
      'cache',
      'temp',
      'downloads',
      'logs',
      p.join('documents', 'LitecoinCashDEXNext'),
      p.join('documents', 'LitecoinCashDEXNext', 'secure-kdf-temp-legacy'),
    ]) {
      final child = Directory(p.join(normalized, folder));
      // Validate every parent in order; never create through a junction/link.
      if (await FileSystemEntity.type(child.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Redirected test directory');
      }
      await child.create();
      if (!p.isWithin(normalized, await child.resolveSymbolicLinks())) {
        throw StateError('Test directory outside profile');
      }
    }
    return profile;
  }

  void install() => installIsolatedProfileStorage(root);
}

/// Shared redirection only; each entry point validates its own marker and scope.
void installIsolatedProfileStorage(String root) {
  final paths = ProfilePathProvider(root);
  PathProviderPlatform.instance = paths;
  SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
    // The Windows plugin bypasses PathProviderPlatform's singleton.
    // ignore: invalid_use_of_visible_for_testing_member
    ..pathProvider = paths;
  SharedPreferencesAsyncPlatform.instance = SharedPreferencesAsyncWindows()
    // ignore: invalid_use_of_visible_for_testing_member
    ..pathProvider = paths;
  FlutterSecureStoragePlatform.instance = ProfileSecureStorage(
    FlutterSecureStoragePlatform.instance,
  );
}

class ProfilePathProvider extends PathProviderWindows {
  ProfilePathProvider(this.root);
  final String root;
  @override
  Future<String> getTemporaryPath() async => p.join(root, 'temp');
  @override
  Future<String> getApplicationSupportPath() async => p.join(root, 'support');
  @override
  Future<String> getApplicationDocumentsPath() async =>
      p.join(root, 'documents');
  @override
  Future<String> getApplicationCachePath() async => p.join(root, 'cache');
  @override
  Future<String> getDownloadsPath() async => p.join(root, 'downloads');
}

/// DPAPI uses the isolated support directory. The compatibility channel must
/// never read, migrate, or delete credentials from Windows' existing vault.
class ProfileSecureStorage extends FlutterSecureStoragePlatform {
  ProfileSecureStorage(FlutterSecureStoragePlatform delegate)
    : delegate = _unwrap(delegate);
  // All plugin instances share one DPAPI file in this isolate. Serialize the
  // entire read/modify/write operation, including native decryption and flush.
  static Future<void> _operationTail = Future<void>.value();
  static FlutterSecureStoragePlatform _unwrap(
    FlutterSecureStoragePlatform storage,
  ) {
    while (storage is ProfileSecureStorage) {
      storage = storage.delegate;
    }
    return storage;
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _operationTail.then<T>((_) => operation());
    // The caller still receives the original failure. Only the queue tail
    // recovers, so a failed operation cannot prevent later safe operations.
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  final FlutterSecureStoragePlatform delegate;
  Map<String, String> _options(Map<String, String> options) => {
    ...options,
    'useBackwardCompatibility': 'false',
  };
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => _serialized(() => delegate.read(key: key, options: _options(options)));
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) => _serialized(
    () => delegate.write(key: key, value: value, options: _options(options)),
  );
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) =>
      _serialized(() => delegate.delete(key: key, options: _options(options)));
  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _serialized(() => delegate.deleteAll(options: _options(options)));
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      _serialized(() => delegate.readAll(options: _options(options)));
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => _serialized(
    () => delegate.containsKey(key: key, options: _options(options)),
  );
}
