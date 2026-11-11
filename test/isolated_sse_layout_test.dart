import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:web_dex/services/testing/isolated_heartbeat_probe.dart';
import 'package:web_dex/services/testing/isolated_sse_indicator.dart';

void main() {
  for (final size in [
    const Size(1280, 720),
    const Size(640, 480),
    const Size(360, 480),
  ]) {
    for (final result in ['enabled', 'blocked', 'failed']) {
      testWidgets(
        'diagnostics reserve space for login and footer: $size $result',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final service = KdfEventStreamingService();
          addTearDown(service.dispose);
          var loginClicks = 0, footerClicks = 0, heartbeatRequests = 0;
          Size? appMediaSize;
          final session = Object();
          final probe = IsolatedHeartbeatProbe(
            scopeApproved: () => result != 'blocked',
            captureSession: () async => session,
            ensureCurrent: (_) {},
            isConnected: () => true,
            knownDisposableWallet: () async => true,
            enable: () async {
              heartbeatRequests++;
              return result == 'failed' ? 'unexpected' : 'HEARTBEAT';
            },
          );
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(size.width < 400 ? 2 : 1),
              ),
              child: IsolatedSseIndicator(
                service: service,
                probe: probe,
                child: Builder(
                  builder: (context) {
                    appMediaSize = MediaQuery.sizeOf(context);
                    return Material(
                      key: const ValueKey('fixture-app'),
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: SizedBox(
                              width: 180,
                              height: 64,
                              child: TextButton(
                                key: const ValueKey('fixture-login'),
                                onPressed: () => loginClicks++,
                                child: const Text('Connect wallet'),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: SizedBox(
                              width: 180,
                              height: 64,
                              child: TextButton(
                                key: const ValueKey('fixture-footer'),
                                onPressed: () => footerClicks++,
                                child: const Text('App footer action'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.tap(
            find.byKey(const ValueKey('isolated-heartbeat-start')),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          final panel = tester.getRect(
            find.byKey(const ValueKey('isolated-heartbeat-panel')),
          );
          final app = tester.getRect(find.byKey(const ValueKey('fixture-app')));
          expect(panel.overlaps(app), isFalse);
          expect(panel.top, greaterThanOrEqualTo(app.bottom));
          expect(appMediaSize, app.size);
          expect(app.height, greaterThan(150));
          await tester.tap(
            find.byKey(const ValueKey('fixture-login')),
            kind: PointerDeviceKind.mouse,
          );
          await tester.tap(
            find.byKey(const ValueKey('fixture-footer')),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          expect(loginClicks, 1);
          expect(footerClicks, 1);
          expect(heartbeatRequests, result == 'blocked' ? 0 : 1);
          expect(find.text('SSE heartbeats: 0'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
