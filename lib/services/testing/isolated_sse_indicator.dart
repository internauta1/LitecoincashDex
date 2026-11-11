import 'dart:async';
import 'package:flutter/material.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'isolated_heartbeat_probe.dart';

/// Shows actual heartbeat events from the experimental wallet's SSE connection.
class IsolatedSseIndicator extends StatefulWidget {
  const IsolatedSseIndicator({
    required this.service,
    required this.child,
    this.probe,
    super.key,
  });
  final KdfEventStreamingService service;
  final Widget child;
  final IsolatedHeartbeatProbe? probe;
  @override
  State<IsolatedSseIndicator> createState() => _IsolatedSseIndicatorState();
}

class _IsolatedSseIndicatorState extends State<IsolatedSseIndicator> {
  StreamSubscription<HeartbeatEvent>? _subscription;
  int _received = 0;
  bool _requesting = false;
  HeartbeatProbeStage? _probeState;

  Future<void> _startProbe() async {
    if (_requesting || widget.probe == null) return;
    setState(() => _requesting = true);
    final result = await widget.probe!.start();
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _probeState = result;
    });
  }

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
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final media =
                  MediaQuery.maybeOf(context) ?? const MediaQueryData();
              return MediaQuery(
                data: media.copyWith(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                ),
                child: widget.child,
              );
            },
          ),
        ),
        Material(
          key: const ValueKey('isolated-heartbeat-panel'),
          color: const Color(0xff182b1f),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'SSE heartbeats: $_received',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: Color(0xffffffff),
                      fontSize: 12,
                    ),
                  ),
                  if (widget.probe != null)
                    TextButton(
                      key: const ValueKey('isolated-heartbeat-start'),
                      onPressed: _requesting ? null : _startProbe,
                      child: Text(
                        _requesting
                            ? 'Requesting heartbeat…'
                            : _probeState == HeartbeatProbeStage.enabled
                            ? 'Heartbeat requested; observe counter'
                            : _probeState == HeartbeatProbeStage.failed
                            ? 'Heartbeat request failed'
                            : _probeState == HeartbeatProbeStage.blocked
                            ? 'Not ready or already requested'
                            : 'Start heartbeat test',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: Color(0xff55dd88),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
