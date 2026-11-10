import 'dart:async';
import 'package:web_dex/bloc/app_shutdown.dart';
import 'dart:io'
    if (dart.library.js_interop) 'window_close_handler_exit_stub.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_window_close/flutter_window_close.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/shared/utils/platform_tuner.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/utils/window/window.dart';

/// A widget that handles window close events and SDK disposal across all platforms.
///
/// This widget uses different strategies based on the platform:
/// - Desktop (Windows, macOS, Linux): Uses flutter_window_close for native window close handling
///   On Linux, native code uses workaround to bypass GTK cleanup to prevent crashes
/// - Web: Uses showMessageBeforeUnload for browser beforeunload event
/// - Mobile (iOS, Android): Uses WidgetsBindingObserver for lifecycle management
///   and PopScope for exit confirmation
///
/// In all cases, it ensures the SDK is properly disposed when the app is closed.
class WindowCloseHandler extends StatefulWidget {
  /// Creates a WindowCloseHandler.
  ///
  /// The [child] parameter must not be null.
  const WindowCloseHandler({
    super.key,
    required this.child,
    this.shutdown,
    this.disposeServices,
  });

  /// The widget below this widget in the tree.
  final Widget child;
  @visibleForTesting
  final AppShutdown? shutdown;
  @visibleForTesting
  final Future<void> Function()? disposeServices;

  @override
  State<WindowCloseHandler> createState() => _WindowCloseHandlerState();
}

class _WindowCloseHandlerState extends State<WindowCloseHandler>
    with WidgetsBindingObserver {
  /// Tracks if the SDK has been disposed to prevent multiple disposal attempts
  bool _hasSdkBeenDisposed = false;
  bool _closing = false;
  bool _detached = false;
  bool _closeFailed = false;
  Future<bool>? _closeAttempt;
  AppShutdown get _shutdown => widget.shutdown ?? appShutdown;

  @override
  void initState() {
    super.initState();
    _setupCloseHandler();
  }

  /// Sets up the appropriate close handler based on the platform.
  void _setupCloseHandler() {
    if (PlatformTuner.isNativeDesktop) {
      // Desktop platforms: Use flutter_window_close for all platforms
      // On Linux, we use flutter_window_close for dialog, but return false to prevent
      // standard window closing, then manually trigger exit via SystemNavigator
      FlutterWindowClose.setWindowShouldCloseHandler(() async {
        final shouldClose = await _handleWindowClose();

        // On Linux, if user confirmed, we need to manually exit instead of letting
        // flutter_window_close handle it, to avoid GTK cleanup issues
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.linux &&
            shouldClose) {
          // Hide window immediately
          // Then exit after a short delay to allow any final cleanup
          Future.delayed(const Duration(milliseconds: 200), () {
            exit(0);
          });
          // Return false to prevent flutter_window_close from closing the window
          return false;
        }

        return shouldClose;
      });
    } else if (kIsWeb) {
      // Web platform: Use beforeunload event
      showMessageBeforeUnload(
        'Closing $appShortTitle does not cancel existing orders or blockchain operations. Keep the wallet open while a swap is active.',
      );
    } else {
      // Mobile platforms: Use lifecycle observer
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Dispose SDK when app is terminated or detached from UI
    // This applies to mobile platforms
    if (state == AppLifecycleState.detached) {
      _disposeSDKIfNeeded();
    }
  }

  /// Handles the window close event.
  /// Returns true if the window should close, false otherwise.
  Future<bool> _handleWindowClose() async {
    final context =
        scaffoldKey.currentContext ?? (mounted ? this.context : null);

    // Show confirmation dialog
    final shouldClose = (context == null)
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Do you really want to quit?'),
                content: Text(
                  'Closing $appShortTitle does not cancel existing orders or blockchain operations. Keep the wallet open while a swap is active.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Yes'),
                  ),
                ],
              );
            },
          );

    log('Window close handler: User confirmed close - $shouldClose');

    // If user confirmed, dispose the SDK
    if (shouldClose == true) {
      return _disposeSDKIfNeeded();
    }

    return false;
  }

  Future<void> _handlePop() async {
    final shouldClose = await _handleWindowClose();
    if (shouldClose) {
      await SystemNavigator.pop();
    }
  }

  /// Disposes the SDK if it hasn't been disposed already.
  Future<bool> _disposeSDKIfNeeded() {
    if (_hasSdkBeenDisposed) return Future.value(true);
    return _closeAttempt ??= _closeInOrder().whenComplete(
      () => _closeAttempt = null,
    );
  }

  Future<bool> _closeInOrder() async {
    _shutdown.beginClosing();
    if (mounted) {
      setState(() {
        _closing = true;
        _detached = true;
        _closeFailed = false;
      });
    }
    try {
      if (mounted) {
        // Unmount the existing subtree once, while SDK/providers are alive.
        // Closing its blocs first caused live widgets to rebuild with closed
        // dependencies; moving it under a new Stack recreated the wallet.
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(seconds: 5),
        );
      }
      await _shutdown.stopConsumers();
      if (widget.disposeServices case final dispose?) {
        await dispose();
      } else {
        final getIt = GetIt.I;
        if (getIt.isRegistered<Mm2Api>()) {
          await getIt<Mm2Api>().dispose();
          getIt.unregister<Mm2Api>();
        }
        if (getIt.isRegistered<SparklineRepository>()) {
          await getIt<SparklineRepository>().dispose();
          getIt.unregister<SparklineRepository>();
        }
        await mm2.dispose();
      }
      _hasSdkBeenDisposed = true;
      return true;
    } catch (_) {
      // Leave the SDK alive if consumers have not stopped. No forced exit.
      log(
        'Window close handler: orderly shutdown did not finish',
        isError: true,
      );
      if (mounted) setState(() => _closeFailed = true);
      return false;
    }
  }

  @override
  void dispose() {
    // Clean up based on platform
    if (PlatformTuner.isNativeDesktop) {
      // Desktop platforms: Remove flutter_window_close handler
      FlutterWindowClose.setWindowShouldCloseHandler(null);
    } else if (!kIsWeb) {
      // Mobile platforms: Remove lifecycle observer
      WidgetsBinding.instance.removeObserver(this);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        if (!_detached) AbsorbPointer(absorbing: _closing, child: widget.child),
        if (_closing)
          Positioned.fill(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _closeFailed
                            ? 'Shutdown is still waiting for background work.'
                            : 'Closing wallet...',
                      ),
                      if (_closeFailed)
                        TextButton(
                          onPressed: () async {
                            if (await _disposeSDKIfNeeded()) {
                              await SystemNavigator.pop();
                            }
                          },
                          child: const Text('Retry closing'),
                        )
                      else
                        const CircularProgressIndicator(),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (PlatformTuner.isNativeMobile) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handlePop();
          }
        },
        child: body,
      );
    }

    return body;
  }
}
