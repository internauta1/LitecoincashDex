import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:web_dex/main_private_manual.dart' as private_entry;
import 'package:web_dex/services/testing/disposable_runtime_profile.dart';
import 'package:web_dex/services/testing/private_manual_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'private entry fails before SDK/storage without approved scope',
    () async {
      await expectLater(private_entry.main(), throwsStateError);
    },
  );
  test(
    'manual trading scope rejects mixed modes, principal ports and disposable root',
    () {
      bool valid({
        bool requested = true,
        bool isolated = true,
        bool walletOnly = false,
        bool fullTest = false,
        bool windows8762 = true,
        String root = PrivateManualProfile.approvedRoot,
        String environment = PrivateManualProfile.approvedRoot,
        int port = 17993,
        String policy = 'disabled',
      }) => PrivateManualProfile.scopeValid(
        requested: requested,
        isolated: isolated,
        walletOnly: walletOnly,
        fullTest: fullTest,
        windows8762: windows8762,
        root: root,
        approvedEnvironmentRoot: environment,
        rpcPort: port,
        geoPolicy: policy,
      );
      expect(valid(), isTrue);
      expect(valid(requested: false), isFalse);
      expect(valid(isolated: false), isFalse);
      expect(valid(walletOnly: true), isFalse);
      expect(valid(fullTest: true), isFalse);
      expect(valid(windows8762: false), isFalse);
      expect(valid(port: 17883), isFalse);
      expect(valid(port: 7863), isFalse);
      expect(
        valid(
          root:
              r'E:\codex\LitecoinCashDEX-Next\.isolated-testing\mission-20261103',
        ),
        isFalse,
      );
      expect(valid(environment: ''), isFalse);
      expect(valid(policy: ''), isFalse);
    },
  );
  late Directory directory;
  group('private profile persistence', () {
    setUp(() async {
      final created = await Directory.systemTemp.createTemp(
        'private-profile-unit-',
      );
      // Windows TEMP can use an 8.3 alias. The positive fixture must supply
      // its actual path; the production guard still rejects redirected input.
      directory = Directory(await created.resolveSymbolicLinks());
      stdout.writeln(
        'WINDOWS_PROFILE_FIXTURE ${jsonEncode({'exists': await created.exists(), 'normalizedEqualsCanonical': p.equals(p.normalize(created.path), directory.path), 'suppliedUsesShortAlias': created.path.contains('~'), 'rootIsLink': await FileSystemEntity.type(created.path, followLinks: false) == FileSystemEntityType.link})}',
      );
      await File(
        p.join(directory.path, PrivateManualProfile.markerName),
      ).writeAsString(PrivateManualProfile.markerValue);
    });
    tearDown(() => directory.delete(recursive: true));
    test(
      'requires private marker and rejects disposable or relative roots',
      () async {
        await expectLater(
          PrivateManualProfile.open('relative'),
          throwsStateError,
        );
        await File(
          p.join(directory.path, DisposableRuntimeProfile.markerName),
        ).writeAsString(DisposableRuntimeProfile.markerValue);
        await expectLater(
          PrivateManualProfile.open(directory.path),
          throwsStateError,
        );
        await File(
          p.join(directory.path, DisposableRuntimeProfile.markerName),
        ).delete();
        await File(
          p.join(directory.path, PrivateManualProfile.markerName),
        ).writeAsString('wrong');
        await expectLater(
          PrivateManualProfile.open(directory.path),
          throwsStateError,
        );
      },
    );
    test(
      'creates no wallet and does not migrate or read host credentials',
      () async {
        final profile = await PrivateManualProfile.open(directory.path);
        expect(profile.root, directory.path);
        expect(
          await Directory(p.join(directory.path, 'support')).list().toList(),
          isEmpty,
        );
        expect(
          await Directory(p.join(directory.path, 'documents')).list().toList(),
          isEmpty,
        );
        final paths = ProfilePathProvider(profile.root);
        for (final location in await Future.wait([
          paths.getTemporaryPath(),
          paths.getApplicationSupportPath(),
          paths.getApplicationDocumentsPath(),
          paths.getApplicationCachePath(),
          paths.getDownloadsPath(),
        ])) {
          expect(p.isWithin(directory.path, location), isTrue);
        }
        expect(PathProviderPlatform.instance, isNot(same(paths)));
      },
    );
    test(
      'rejects a junction root and a redirected child directory',
      () async {
        final shell = Platform.environment['SystemRoot'];
        if (shell == null) throw StateError('Windows directory unavailable');
        final outside = await directory.parent.createTemp(
          'profile-link-target-',
        );
        final link = p.join(
          directory.parent.path,
          '${p.basename(directory.path)}-junction',
        );
        addTearDown(() async {
          if (await FileSystemEntity.type(link, followLinks: false) ==
              FileSystemEntityType.link) {
            await Link(link).delete();
          }
          await outside.delete(recursive: true);
        });
        Future<void> junction(String path, String target) async {
          final result = await Process.run(
            p.join(
              shell,
              'System32',
              'WindowsPowerShell',
              'v1.0',
              'powershell.exe',
            ),
            [
              '-NoLogo',
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r"$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:TEST_PROFILE_LINK -Target $env:TEST_PROFILE_TARGET | Out-Null",
            ],
            environment: {
              'TEST_PROFILE_LINK': path,
              'TEST_PROFILE_TARGET': target,
            },
          );
          if (result.exitCode != 0) {
            throw StateError('Synthetic junction creation failed');
          }
        }

        await junction(link, directory.path);
        await expectLater(PrivateManualProfile.open(link), throwsStateError);
        final child = p.join(directory.path, 'support');
        await junction(child, outside.path);
        try {
          await expectLater(
            PrivateManualProfile.open(directory.path),
            throwsStateError,
          );
        } finally {
          await Link(child).delete();
        }
        expect(await outside.list().toList(), isEmpty);
      },
      skip: !Platform.isWindows,
    );
  });
}
