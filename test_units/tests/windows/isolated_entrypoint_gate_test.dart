import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/main_isolated.dart' as isolated;

void main() {
  test('experimental entry point refuses an unapproved/default profile', () async {
    // No profile define or approval environment is provided by the test runner.
    // The guard must fail before constructing the SDK or touching persistence.
    await expectLater(isolated.main(), throwsStateError);
  });
}
