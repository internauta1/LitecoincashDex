import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/community_build.dart';

void main() {
  test(
    'refuses an explicitly wrong network or upstream policy before startup',
    () => expect(validateCommunityBuild, throwsStateError),
    skip: !const bool.fromEnvironment('LCC_TEST_WRONG_CONFIG'),
  );
}
