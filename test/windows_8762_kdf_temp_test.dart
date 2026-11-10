import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:web_dex/services/testing/disposable_runtime_profile.dart';

void main() {
  Future<Directory> fixture() async {
    final created = await Directory.current.createTemp('next_8762_acl_');
    final root = Directory(await created.resolveSymbolicLinks());
    if (!p.isWithin(
      await Directory.current.resolveSymbolicLinks(),
      root.path,
    )) {
      throw StateError('Synthetic fixture outside checkout');
    }
    addTearDown(() => root.delete(recursive: true));
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = ProfilePathProvider(root.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
    return root;
  }

  Future<String> shell(String script, Map<String, String> environment) async {
    final systemRoot = Platform.environment['SystemRoot'];
    if (systemRoot == null) throw StateError('Windows directory unavailable');
    final result = await Process.run(
      p.join(
        systemRoot,
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      ),
      ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
      environment: environment,
    ).timeout(const Duration(seconds: 8));
    if (result.exitCode != 0) {
      throw StateError('Synthetic directory fixture operation failed');
    }
    return result.stdout as String;
  }

  Future<Map<String, dynamic>> security(String path) async =>
      jsonDecode(
            await shell(
              r'''
$ErrorActionPreference='Stop'
$acl=([IO.DirectoryInfo]::new($env:TEST_KDF_DIRECTORY)).GetAccessControl()
$user=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
$owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
$rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
$unexpected=@($rules|Where-Object {
 $_.IdentityReference.Value -notin @($user,'S-1-5-18') -or
 $_.IsInherited -or $_.AccessControlType -ne 'Allow' -or $_.FileSystemRights -ne 'FullControl'
})
$sddl=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::All)
$hash=[Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($sddl))
[pscustomobject]@{tokenElevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);ownerIsCurrentUser=($owner-eq $user);ownerIsAdministrators=($owner-eq 'S-1-5-32-544');protected=$acl.AreAccessRulesProtected;ruleCount=$rules.Count;unexpectedRules=$unexpected.Count;sddlSha256=([BitConverter]::ToString($hash)).Replace('-','')}|ConvertTo-Json -Compress
''',
              {'TEST_KDF_DIRECTORY': path},
            ),
          )
          as Map<String, dynamic>;

  void expectProtected(Map<String, dynamic> metadata) {
    expect(metadata['ownerIsCurrentUser'], isTrue);
    expect(metadata['protected'], isTrue);
    expect(metadata['ruleCount'], 2);
    expect(metadata['unexpectedRules'], 0);
  }

  Future<Directory> prepare() async {
    try {
      return await prepareWindows8762KdfTemp();
    } on WindowsKdfTempProtectionException catch (error) {
      // Fixed categories/codes only; never print paths, SIDs or shell output.
      stdout.writeln(
        'WINDOWS_KDF_TEMP_FAILURE ${jsonEncode({'exitCode': error.exitCode, 'category': error.category})}',
      );
      rethrow;
    }
  }

  test(
    'Windows protects a new and an existing 8762 temporary directory',
    () async {
      final root = await fixture();
      final expected = p.join(root.path, 'cache', 'secure-kdf-temp-8762');
      expect((await prepare()).path, expected);
      expectProtected(await security(expected));
      expect((await prepare()).path, expected);
      expectProtected(await security(expected));
    },
    skip: !Platform.isWindows,
  );

  test(
    'an existing foreign owner is refused without changing its ACL',
    () async {
      final root = await fixture();
      final directory = await Directory(
        p.join(root.path, 'cache', 'secure-kdf-temp-8762'),
      ).create(recursive: true);
      final before = await security(directory.path);
      if (before['ownerIsCurrentUser'] == true) {
        // A standard token creates a user-owned fixture; an elevated Windows
        // token normally creates an Administrators-owned one instead.
        await prepare();
        expectProtected(await security(directory.path));
      } else {
        await expectLater(
          prepare(),
          throwsA(
            isA<WindowsKdfTempProtectionException>()
                .having((e) => e.exitCode, 'exitCode', 3)
                .having(
                  (e) => e.category,
                  'category',
                  'owner_or_protection_mismatch',
                ),
          ),
        );
        expect(
          (await security(directory.path))['sddlSha256'],
          before['sddlSha256'],
        );
      }
      stdout.writeln(
        'WINDOWS_KDF_OWNER_POLICY ${jsonEncode({'tokenElevated': before['tokenElevated'], 'existingOwnerIsCurrentUser': before['ownerIsCurrentUser'], 'existingOwnerIsAdministrators': before['ownerIsAdministrators'], 'foreignOwnerRefusalExercised': before['ownerIsCurrentUser'] != true})}',
      );
    },
    skip: !Platform.isWindows,
  );

  for (final redirected in ['cache', 'leaf']) {
    test('rejects a redirected KDF $redirected directory', () async {
      final root = await fixture();
      final target = await Directory(
        p.join(root.path, 'empty-link-target'),
      ).create();
      final cache = Directory(p.join(root.path, 'cache'));
      if (redirected == 'leaf') await cache.create();
      final link = redirected == 'cache'
          ? cache.path
          : p.join(cache.path, 'secure-kdf-temp-8762');
      await shell(
        r"$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:TEST_KDF_LINK -Target $env:TEST_KDF_TARGET | Out-Null",
        {'TEST_KDF_LINK': link, 'TEST_KDF_TARGET': target.path},
      );
      addTearDown(() => Link(link).delete());
      await expectLater(prepare(), throwsStateError);
      expect(await target.list().toList(), isEmpty);
    }, skip: !Platform.isWindows);
  }

  test(
    'user-owned weak permissions are restricted before reuse',
    () async {
      await fixture();
      final directory = await prepare();
      await shell(
        r'''
$ErrorActionPreference='Stop'
$item=[IO.DirectoryInfo]::new($env:TEST_KDF_DIRECTORY)
$acl=$item.GetAccessControl()
$acl.SetAccessRuleProtection($false,$true)
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
 [Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'FullControl','ContainerInherit, ObjectInherit','None','Allow'))
$item.SetAccessControl($acl)
''',
        {'TEST_KDF_DIRECTORY': directory.path},
      );
      final before = await security(directory.path);
      expect(before['protected'], isFalse);
      expect(before['unexpectedRules'], greaterThan(0));
      await prepare();
      expectProtected(await security(directory.path));
    },
    skip: !Platform.isWindows,
  );
}
