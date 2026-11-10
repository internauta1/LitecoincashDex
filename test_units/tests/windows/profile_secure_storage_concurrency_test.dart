import 'dart:async';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/testing/disposable_runtime_profile.dart';

class _Delegate extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => run('containsKey', true);
  final calls = <String>[];
  int active = 0;
  int maximum = 0;
  Completer<void>? writeGate;
  bool failWrite = false;
  Future<T> run<T>(String name, T result) async {
    calls.add(name);
    active++;
    if (active > maximum) {
      maximum = active;
    }
    try {
      if (name == 'write' && writeGate != null) {
        await writeGate!.future;
      }
      await Future<void>.delayed(Duration.zero);
      if (name == 'write' && failWrite) {
        throw StateError('synthetic storage failure');
      }
      return result;
    } finally {
      active--;
    }
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => run('read', 'fixture');
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) => run<void>('write', null);
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) => run<void>('delete', null);
  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      run<void>('deleteAll', null);
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      run('readAll', {'fixture': 'value'});
}

void main() {
  test('read waits for an unfinished encrypted-file write', () async {
    final delegate = _Delegate()..writeGate = Completer<void>();
    final storage = ProfileSecureStorage(delegate);
    final write = storage.write(key: 'fixture', value: 'value', options: {});
    await Future<void>.delayed(Duration.zero);
    final read = storage.read(key: 'fixture', options: {});
    await Future<void>.delayed(Duration.zero);
    final observed = List<String>.of(delegate.calls);
    delegate.writeGate!.complete();
    await Future.wait([write, read]);
    expect(observed, ['write']);
    expect(delegate.maximum, 1);
  });
  test('separate wrappers share the encrypted-file operation queue', () async {
    final delegate = _Delegate();
    final first = ProfileSecureStorage(delegate);
    final second = ProfileSecureStorage(delegate);
    await Future.wait([
      first.write(key: 'a', value: 'v', options: {}),
      second.deleteAll(options: {}),
      first.readAll(options: {}),
    ]);
    expect(delegate.maximum, 1);
    expect(delegate.calls, ['write', 'deleteAll', 'readAll']);
  });
  test(
    'operation failure reaches its caller without poisoning later reads',
    () async {
      final delegate = _Delegate()..failWrite = true;
      final storage = ProfileSecureStorage(delegate);
      await expectLater(
        storage.write(key: 'a', value: 'v', options: {}),
        throwsStateError,
      );
      expect(await storage.read(key: 'a', options: {}), 'fixture');
    },
  );
  test('nested wrappers finish without re-entering the shared queue', () async {
    final delegate = _Delegate();
    final storage = ProfileSecureStorage(ProfileSecureStorage(delegate));
    await storage
        .write(key: 'a', value: 'v', options: {})
        .timeout(const Duration(seconds: 2));
    expect(delegate.maximum, 1);
    expect(delegate.calls, ['write']);
  });
}
