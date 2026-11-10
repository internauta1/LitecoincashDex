import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/native/kdf_executable_finder.dart';
import 'package:path/path.dart' as p;

void main() {
  test('fixed bundle lookup cannot fall back to another KDF', () async {
    final root = await Directory.systemTemp.createTemp('next-finder-unit-');
    addTearDown(() => root.delete(recursive: true));
    final finder = KdfExecutableFinder(
      logCallback: (_) {},
      executableDirectory: root.path,
    );
    expect(await finder.findExecutable(), isNull);
    final file = File(
      p.join(root.path, Platform.isWindows ? 'kdf.exe' : 'kdf'),
    );
    await file.writeAsString('not-an-executable-test-fixture');
    expect((await finder.findExecutable())!.path, file.absolute.path);
    expect(
      await finder.findExecutable(executableName: 'mm2_lccnext_isolated'),
      isNull,
    );
  });
}
