import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';

/// Shows actual heartbeat events from the experimental wallet's SSE connection.
class IsolatedSseIndicator extends StatefulWidget {
  const IsolatedSseIndicator({
    required this.service,
    required this.child,
    super.key,
  });
  final KdfEventStreamingService service;
  final Widget child;
  @override
  State<IsolatedSseIndicator> createState() => _IsolatedSseIndicatorState();
}

class _IsolatedSseIndicatorState extends State<IsolatedSseIndicator> {
  StreamSubscription<HeartbeatEvent>? _subscription;
  int _received = 0;
  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    final service = widget.service;
    _subscription = service.heartbeatEvents.listen((event) {
      if (!mounted || !identical(widget.service, service)) return;
      service.diagnostics?.heartbeatConsumed(event);
      setState(() => _received++);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(widget.service, service)) {
          service.diagnostics?.rendered(event);
        }
      });
    });
  }

  @override
  void didUpdateWidget(IsolatedSseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      unawaited(_subscription?.cancel());
      _received = 0;
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    textDirection: TextDirection.ltr,
    children: [
      widget.child,
      Positioned(
        top: 6,
        right: 8,
        child: IgnorePointer(
          child: ColoredBox(
            color: const Color(0xff182b1f),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'SSE heartbeats: $_received',
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Color(0xffffffff), fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
