import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/community_build.dart';

void main() {
  test('public fork defaults to explicit legacy 8762 and local RPC', () {
    expect(kDefaultNetId, 8762);
    expect(kWindows8762Release, isTrue);
    expect(kUseLegacyKdf, isTrue);
    expect(kDefaultKdfRpcPort, 17883);
    final config = LocalConfig(https: true, rpcPassword: 'offline-fixture');
    expect(config.rpcUrl.toString(), 'http://127.0.0.1:17883');
    expect(validateCommunityBuild, returnsNormally);
  });
}
