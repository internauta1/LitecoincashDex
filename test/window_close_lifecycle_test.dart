import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/app_config/app_config.dart' show scaffoldKey;
import 'package:web_dex/bloc/app_shutdown.dart';
import 'package:web_dex/sdk/widgets/window_close_handler.dart';

class _WalletProbe extends StatefulWidget {
  const _WalletProbe(this.events);
  final List<String> events;
  @override
  State<_WalletProbe> createState() => _WalletProbeState();
}

class _WalletProbeState extends State<_WalletProbe> {
  @override
  void initState() {
    super.initState();
    widget.events.add('wallet mounted');
  }

  @override
  void dispose() {
    widget.events.add('wallet unmounted');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('disposable wallet');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();
  late List<String> platformCalls;
  setUp(() {
    platformCalls = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_window_close'),
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
  });
  Future<void> requestNativeClose(WidgetTester tester) async {
    final response = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter_window_close_notification',
      codec.encodeMethodCall(const MethodCall('onWindowClose')),
      (_) => response.complete(),
    );
    await tester.pump();
    expect(find.text('Do you really want to quit?'), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.pump();
    await tester.pump();
    // The native response may stay pending while consumer/SDK gates are held.
    unawaited(response.future);
  }

  Widget host(
    AppShutdown shutdown,
    List<String> events,
    Future<void> Function() dispose,
  ) => WindowCloseHandler(
    shutdown: shutdown,
    disposeServices: dispose,
    child: MaterialApp(
      home: Scaffold(key: scaffoldKey, body: _WalletProbe(events)),
    ),
  );

  testWidgets(
    'native close unmounts once before draining consumers and SDK',
    (tester) async {
      final shutdown = AppShutdown();
      final events = <String>[];
      final gate = Completer<void>();
      shutdown.register('producer', () async {
        events.add('consumer stopping');
        await gate.future;
        events.add('consumer stopped');
      });
      await tester.pumpWidget(
        host(shutdown, events, () async {
          events.add('sdk disposed');
        }),
      );
      await tester.pump();
      await requestNativeClose(tester);
      expect(shutdown.isClosing, isTrue);
      expect(events, [
        'wallet mounted',
        'wallet unmounted',
        'consumer stopping',
      ]);
      expect(find.text('Closing wallet...'), findsOneWidget);
      expect(platformCalls, isNot(contains('destroyWindow')));
      gate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(events, [
        'wallet mounted',
        'wallet unmounted',
        'consumer stopping',
        'consumer stopped',
        'sdk disposed',
      ]);
      expect(platformCalls, contains('destroyWindow'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets(
    'drain failure keeps SDK alive; retry does not recreate wallet',
    (tester) async {
      final shutdown = AppShutdown();
      final events = <String>[];
      var fail = true;
      shutdown.register('producer', () {
        if (fail) throw StateError('synthetic consumer failure');
      });
      await tester.pumpWidget(
        host(shutdown, events, () async {
          events.add('sdk disposed');
        }),
      );
      await tester.pump();
      await requestNativeClose(tester);
      await tester.pump();
      expect(find.text('Retry closing'), findsOneWidget);
      expect(events, ['wallet mounted', 'wallet unmounted']);
      expect(platformCalls, isNot(contains('destroyWindow')));
      fail = false;
      await tester.tap(find.text('Retry closing'));
      await tester.pump();
      await tester.pump();
      expect(events, ['wallet mounted', 'wallet unmounted', 'sdk disposed']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
