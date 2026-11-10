part of 'kdf_operations_local_executable.dart';

typedef _ControlRpc = Future<JsonMap> Function(int, String, bool Function());

/// The Process handle identifies a generation even if Windows reuses its PID.
class WindowsKdfSupervisor extends KdfOperationsLocalExecutable {
  WindowsKdfSupervisor({
    required LocalConfig config,
    required void Function(String) logCallback,
    required String executableName,
    required Future<Directory> Function() temporaryDirectory,
    Duration startupTimeout = const Duration(seconds: 30),
    this.stopTimeout = const Duration(seconds: 10),
    KdfExecutableFinder? executableFinder,
    JsonMap Function(JsonMap)? startParamsTransform,
    Future<(Process, Directory)> Function(JsonMap)? launch,
    bool Function()? portVacant,
    _ControlRpc? control,
    bool recoverEarlyLoginExit = false,
  }) : _launch = launch,
       _port = config.port,
       _endpoint = WindowsKdfEndpoint(
         config.rpcUrl,
         config.rpcPassword,
         ownershipLog: logCallback,
       ),
       _portVacant = portVacant,
       _control = control,
       _recoverEarlyLoginExit = recoverEarlyLoginExit,
       super._(
         logCallback,
         KdfOperationsRemote.create(
           logCallback: logCallback,
           rpcUrl: config.rpcUrl,
           userpass: config.rpcPassword,
         ),
         temporaryDirectory: temporaryDirectory,
         executableName: executableName,
         startupTimeout: startupTimeout,
         executableFinder: executableFinder,
         startParamsTransform: startParamsTransform,
       ) {
    config.supervisedVersion = version;
    WindowsKdfEndpoint.streams[config] = () {
      final child = _process;
      if (child == null) throw StateError('No owned KDF');
      bool valid() =>
          identical(_process, child) &&
          !_disposed &&
          !_needsStop &&
          _stopping == null;
      return (() => _endpoint.verifiedClient(child.pid, valid), valid);
    };
  }

  static final _reservedPorts = <int>{};
  final int _port;
  final WindowsKdfEndpoint _endpoint;
  final Future<(Process, Directory)> Function(JsonMap)? _launch;
  final bool Function()? _portVacant;
  final _ControlRpc? _control;
  final bool _recoverEarlyLoginExit;
  bool _cleanStop = false;
  final Duration stopTimeout;
  Future<KdfStartupResult>? _starting;
  Future<StopStatus>? _stopping;
  bool _needsStop = false;
  bool _disposed = false;

  @override
  Future<KdfStartupResult> kdfMain(JsonMap params, {int? logLevel}) {
    if (_disposed || _stopping != null || _needsStop) {
      return Future.value(KdfStartupResult.spawnError);
    }
    return _starting ??= _start(params).whenComplete(() => _starting = null);
  }

  Future<KdfStartupResult> _start(JsonMap params) async {
    final existing = _process;
    if (existing != null) {
      try {
        return await version() == null
            ? KdfStartupResult.spawnError
            : KdfStartupResult.alreadyRunning;
      } on KdfTransportException {
        return KdfStartupResult.spawnError;
      }
    }
    final mayRetry =
        _recoverEarlyLoginExit &&
        _cleanStop &&
        params['wallet_name'] is String &&
        (params['wallet_name'] as String).isNotEmpty &&
        params['allow_registrations'] == false &&
        !params.containsKey('passphrase');
    _cleanStop = false;
    final timer = Stopwatch()..start();
    int? earlyExit;
    final result = await _startGeneration(
      params,
      _startupTimeout,
      (code) => earlyExit = code,
    );
    if (!mayRetry ||
        result != KdfStartupResult.spawnError ||
        earlyExit != 1 ||
        _process != null ||
        _disposed ||
        _stopping != null) {
      return result;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final remaining = _startupTimeout - timer.elapsed;
    if (remaining <= Duration.zero || _disposed || _stopping != null) {
      return result;
    }
    // The new attempt reacquires the port reservation and passes the normal
    // vacancy and executable identity guards before spawning.
    _diagnose('start', 'early_login_exit_retry');
    return _startGeneration(params, remaining, (_) {});
  }

  Future<KdfStartupResult> _startGeneration(
    JsonMap params,
    Duration budget,
    void Function(int) recordEarlyExit,
  ) async {
    if (!_reservedPorts.add(_port)) {
      _diagnose('start', 'reserved');
      return KdfStartupResult.spawnError;
    }
    var installed = false;
    try {
      if (!(_portVacant?.call() ?? _endpoint.isVacant)) {
        _diagnose('start', 'port_busy');
        return KdfStartupResult.spawnError;
      }
      final (child, directory) = await (_launch ?? _launchKdf)(params);
      _process = child;
      installed = true;
      StreamSubscription<List<int>>? stdout;
      StreamSubscription<List<int>>? stderr;
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      var ready = false;
      final exited = child.exitCode.then((code) {
        final intent = _stopping != null ? 'requested_stop' : 'unrequested';
        if (!ready) recordEarlyExit(code);
        if (identical(child, _process)) {
          _process = null;
          _needsStop = false;
          _reservedPorts.remove(_port);
        }
        // Cleanup owns only this generation's streams and directory. It can
        // finish after another process starts without touching its state.
        unawaited(
          _releaseGeneration(
            stdout,
            stderr,
            directory,
            drain: ready || !_recoverEarlyLoginExit
                ? null
                : Future.wait([stdoutDone.future, stderrDone.future]),
          ),
        );
        _logCallback(
          'kdf phase=exit category=child_exit code=$code pid=${child.pid} port=${_endpoint.portState(child.pid)} ready=$ready intent=$intent',
        );
        return KdfStartupResult.spawnError;
      });
      stdout = _observePipe(
        child.stdout,
        'stdout',
        child.pid,
        () => _recoverEarlyLoginExit && !ready,
        stdoutDone,
      );
      stderr = _observePipe(
        child.stderr,
        'stderr',
        child.pid,
        () => _recoverEarlyLoginExit && !ready,
        stderrDone,
      );
      final result = await Future.any([
        exited,
        _waitForRpc(child),
      ]).timeout(budget, onTimeout: () => KdfStartupResult.spawnError);
      if (result == KdfStartupResult.ok) {
        if (!identical(child, _process)) return KdfStartupResult.spawnError;
        ready = true;
        if (kWindows8762Release && _launch == null) {
          await File(p.join(directory.path, 'next_kdf.json')).delete();
          if (!identical(child, _process)) return KdfStartupResult.spawnError;
        }
      }
      if (identical(child, _process) && result != KdfStartupResult.ok) {
        _diagnose('start', 'readiness_failed');
        _needsStop = true;
      }
      return result;
    } catch (_) {
      if (installed && _process != null) _needsStop = true;
      _diagnose('start', 'initialization_failed');
      return KdfStartupResult.initError;
    } finally {
      if (!installed) _reservedPorts.remove(_port);
    }
  }

  static const _startupSignals = {
    'address already in use': 'bind_address_in_use',
    'os error 10048': 'bind_address_in_use',
    'database is locked': 'database_locked',
    'sqlite_busy': 'database_locked',
    'sharing violation': 'sharing_violation',
    'os error 32)': 'sharing_violation',
    'failed to parse mm2.json': 'configuration_parse',
  };

  // Scan a bounded startup prefix in memory. Only fixed categories are logged.
  // Carry just the suffix needed to detect a signal split across pipe chunks.
  StreamSubscription<List<int>> _observePipe(
    Stream<List<int>> pipe,
    String channel,
    int pid,
    bool Function() starting,
    Completer<void> done,
  ) {
    var observed = false;
    var failed = false;
    var scanRemaining = 32768;
    var suffix = '';
    final seen = <String>{};
    return pipe.listen(
      (bytes) {
        if (!observed && bytes.isNotEmpty) {
          observed = true;
          _logCallback(
            'kdf phase=pipe category=activity channel=$channel pid=$pid',
          );
        }
        if (!starting()) {
          suffix = '';
          return;
        }
        final length = bytes.length < scanRemaining
            ? bytes.length
            : scanRemaining;
        if (length == 0) return;
        scanRemaining -= length;
        final text =
            suffix + String.fromCharCodes(bytes.take(length)).toLowerCase();
        for (final signal in _startupSignals.entries) {
          if (text.contains(signal.key) && seen.add(signal.value)) {
            _logCallback(
              'kdf phase=start category=${signal.value} channel=$channel pid=$pid',
            );
          }
        }
        suffix = scanRemaining == 0
            ? ''
            : text.substring(text.length > 32 ? text.length - 32 : 0);
      },
      onDone: done.complete,
      onError: (Object _) {
        if (!failed) {
          failed = true;
          _logCallback(
            'kdf phase=pipe category=read_error channel=$channel pid=$pid',
          );
        }
      },
    );
  }

  Future<void> _releaseGeneration(
    StreamSubscription<List<int>>? stdout,
    StreamSubscription<List<int>>? stderr,
    Directory directory, {
    Future<List<void>>? drain,
  }) async {
    try {
      if (drain != null) {
        await drain.timeout(
          const Duration(milliseconds: 250),
          onTimeout: () => [],
        );
      }
      await Future.wait([
        if (stdout != null) stdout.cancel(),
        if (stderr != null) stderr.cancel(),
      ]);
    } catch (_) {
      _logCallback('KDF stream cleanup failed');
    } finally {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        _logCallback('KDF temporary directory cleanup failed');
      }
    }
  }

  Future<KdfStartupResult> _waitForRpc(Process child) async {
    while (identical(child, _process) &&
        !_needsStop &&
        !_disposed &&
        _stopping == null) {
      try {
        if (await version() != null) return KdfStartupResult.ok;
      } on KdfTransportException {
        // Startup readiness is bounded by this loop. A listener may not yet
        // exist; that must not abort the first startup probe.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return KdfStartupResult.spawnError;
  }

  @override
  Future<String?> version() async =>
      (await _versionResponse())?['result'] as String?;

  Future<JsonMap?> _versionResponse() async {
    final child = _process;
    if (child == null || _disposed || _needsStop || _stopping != null)
      return null;
    bool valid() =>
        identical(child, _process) &&
        !_disposed &&
        !_needsStop &&
        _stopping == null;
    try {
      final data = await (_control ?? _endpoint.call)(
        child.pid,
        'version',
        valid,
      );
      if (!valid()) return null;
      final version = data['result'];
      if (version is! String || version.isEmpty) {
        throw const KdfTransportException(KdfTransportFailure.unknown);
      }
      return data;
    } catch (error) {
      if (!valid()) return null;
      final failure = _transportFailure(error);
      _diagnose(
        'version',
        'verified_transport_failed reason=${failure.reason.name}',
        failure: failure,
      );
      throw failure;
    }
  }

  @override
  Future<MainStatus> kdfMainStatus() async {
    // Read-shaped callers (including the login wallet catalogue) must join
    // the existing bounded startup, not race its first listener probe. The
    // startup loop itself uses version() directly, so this cannot await itself.
    final starting = _starting;
    if (starting != null) await starting;
    // Readiness is not an ownership cache: verify the current generation again.
    return await version() != null ? MainStatus.rpcIsUp : MainStatus.notRunning;
  }

  @override
  Future<StopStatus> kdfStop() =>
      _stopping ??= _stop().whenComplete(() => _stopping = null);

  void _diagnose(
    String phase,
    String category, {
    KdfTransportException? failure,
  }) {
    final pid = processId;
    final detail = failure is KdfTcpOwnershipException
        ? ' check=${failure.check.name} evidence=${failure.evidence.name}'
        : '';
    _logCallback(
      'kdf phase=$phase category=$category pid=${pid ?? 0} port=${_endpoint.portState(pid ?? 0)}$detail',
    );
  }

  Future<StopStatus> _stop() async {
    await _starting;
    final child = _process;
    if (child == null) return StopStatus.notRunning;
    _needsStop = true;
    bool valid() => identical(child, _process);
    try {
      // A successful response alone cannot release the port reservation.
      await (_control ?? _endpoint.call)(child.pid, 'stop', valid);
    } catch (_) {
      // The peer may have exited before sending its response.
    }
    try {
      final code = await child.exitCode.timeout(stopTimeout);
      _cleanStop = code == 0;
      return StopStatus.ok;
    } on TimeoutException {
      _diagnose('stop', 'exit_unconfirmed');
      return StopStatus.errorStopping;
    }
  }

  @override
  Future<JsonMap> mm2Rpc(JsonMap request) async {
    if (request['method'] == 'stop') {
      final result = await kdfStop();
      if (result == StopStatus.notRunning) return {'result': 'already_stopped'};
      if (result == StopStatus.ok) return {'result': 'success'};
      throw StateError('KDF exit unconfirmed');
    }
    if (request['method'] == 'version') {
      final response = await _versionResponse();
      if (response == null) {
        throw const KdfTransportException(
          KdfTransportFailure.generationUnavailable,
        );
      }
      return response;
    }
    final child = _process;
    bool valid() =>
        child != null &&
        identical(_process, child) &&
        !_disposed &&
        !_needsStop &&
        _stopping == null &&
        _starting == null;
    if (child == null || !valid()) {
      _diagnose('rpc', 'unavailable');
      throw const KdfTransportException(
        KdfTransportFailure.generationUnavailable,
      );
    }
    return _kdfRemote.sendRpc(request, (body) async {
      try {
        return await _endpoint.post(child.pid, body, valid);
      } catch (error) {
        final failure = _transportFailure(error);
        _diagnose(
          'rpc',
          'verified_transport_failed reason=${failure.reason.name}',
          failure: failure,
        );
        throw failure;
      }
    });
  }

  KdfTransportException _transportFailure(Object error) {
    if (error is KdfTransportException) return error;
    if (error is TimeoutException)
      return const KdfTransportException(KdfTransportFailure.timeout);
    if (error is SocketException)
      return const KdfTransportException(KdfTransportFailure.socket);
    if (error is HttpException)
      return const KdfTransportException(KdfTransportFailure.http);
    if (error is StateError &&
        (error.message == 'Unowned listener' ||
            error.message == 'Unowned connection')) {
      return const KdfTransportException(
        KdfTransportFailure.ownershipUnverified,
      );
    }
    if (error is StateError && error.message == 'Stale KDF generation') {
      return const KdfTransportException(
        KdfTransportFailure.generationUnavailable,
      );
    }
    return const KdfTransportException(KdfTransportFailure.unknown);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(kdfStop().whenComplete(_kdfRemote.dispose));
  }
}
