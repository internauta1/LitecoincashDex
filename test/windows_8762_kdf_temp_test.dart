import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:web_dex/services/testing/disposable_runtime_profile.dart';

void main() {
  test(
    'Windows protects a new and an existing 8762 temporary directory',
    () async {
      final root = await Directory.current.createTemp('next_8762_acl_');
      addTearDown(() => root.delete(recursive: true));
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = ProfilePathProvider(root.path);
      addTearDown(() => PathProviderPlatform.instance = previous);

      final expected = p.join(root.path, 'cache', 'secure-kdf-temp-8762');
      expect((await prepareWindows8762KdfTemp()).path, expected);
      expect((await prepareWindows8762KdfTemp()).path, expected);
    },
    skip: !Platform.isWindows,
  );
}
