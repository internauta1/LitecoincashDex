import 'package:flutter_test/flutter_test.dart';
import '../../../lib/mm2/sdk_bootstrap.dart';

void main() {
  test('failed generation stays failed; a new generation can initialize', () async {
    final old = SdkBootstrap<Object>();
    var calls = 0;
    final partial = Object();
    final failed = old.initialize(() async {
      calls++;
      throw StateError('startup failed');
    });
    expect(identical(failed, old.initialize(() async => partial)), isTrue);
    await expectLater(failed, throwsStateError);
    await expectLater(old.initialize(() async => partial), throwsStateError);
    expect(calls, 1);
    final fresh = Object();
    expect(await SdkBootstrap<Object>().initialize(() async => fresh), same(fresh));
  });
}
