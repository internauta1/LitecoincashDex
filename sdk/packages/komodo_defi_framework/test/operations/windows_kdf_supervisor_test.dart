import 'dart:convert';
import 'package:komodo_defi_framework/src/streaming/event_streaming_platform_io.dart'
    as sse;
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/native/windows_kdf_endpoint.dart';
import 'package:komodo_defi_framework/src/exceptions/kdf_transport_exception.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_local_executable.dart';

class _Child extends Fake implements Process {
  _Child(this.pid);
  @override
  final int pid;
  final exited = Completer<int>();
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  @override
  Future<int> get exitCode => exited.future;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
}

class _TestDirectory extends Fake implements Directory {
  final deleted = Completer<void>();
  @override
  Future<Directory> delete({bool recursive = false}) async {
    deleted.complete();
    return this;
  }
}

Future<Process> _responder(int rounds, {bool waitForRelease = false}) {
  return Process.start('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    r'''
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start()
[Console]::WriteLine($listener.LocalEndpoint.Port)
foreach ($round in 1..ROUNDS) {
$c = $listener.AcceptTcpClient()
$stream = $c.GetStream()
$reader = [IO.StreamReader]::new($stream)
while ($reader.ReadLine() -ne '') {}
$body = '{"result":"simulated"}'
$b = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n$body")
$stream.Write($b,0,$b.Length)
$c.Close()
}
WAIT_FOR_RELEASE
$listener.Stop()
'''
        .replaceFirst('ROUNDS', rounds.toString())
        .replaceFirst(
          'WAIT_FOR_RELEASE',
          waitForRelease ? '[Console]::ReadLine() | Out-Null' : '',
        ),
  ]);
}

void main() {
  late Directory root;
  late List<_TestDirectory> directories;
  late WindowsKdfSupervisor supervisor;
  late List<_Child> children;
  late List<int> stopRecipients;
  late Completer<void> launched;
  late int? listener;
  late bool vacant;
  late List<String> lifecycleLogs;
  Object? versionFailure;
  setUp(() async {
    root = _TestDirectory();
    directories = [];
    lifecycleLogs = [];
    versionFailure = null;
    children = [];
    stopRecipients = [];
    launched = Completer<void>();
    listener = 100;
    vacant = true;
    supervisor = WindowsKdfSupervisor(
      config: LocalConfig(https: false, rpcPassword: ''),
      executableName: 'simulated',
      temporaryDirectory: () async => root,
      logCallback: lifecycleLogs.add,
      startupTimeout: const Duration(milliseconds: 800),
      recoverEarlyLoginExit: true,
      stopTimeout: const Duration(milliseconds: 15),
      portVacant: () => vacant,
      launch: (_) async {
        final directory = _TestDirectory();
        directories.add(directory);
        final child = _Child(100 + children.length);
        children.add(child);
        if (!launched.isCompleted) launched.complete();
        return (child, directory);
      },
      control: (pid, method, valid) async {
        if (method == 'version' && versionFailure != null)
          throw versionFailure!;
        if (pid != listener || !valid()) throw StateError('Wrong owner');
        if (method == 'stop') stopRecipients.add(pid);
        return {'result': method == 'stop' ? 'success' : 'simulated'};
      },
    );
  });
  tearDown(() async {
    for (final child in children) {
      if (!child.exited.isCompleted) child.exited.complete(0);
    }
    await supervisor.kdfStop();
    await Future.wait(directories.map((directory) => directory.deleted.future));
  });

  test(
    'status joins startup readiness instead of probing the missing listener',
    () async {
      versionFailure = const KdfTcpOwnershipException(
        KdfTcpOwnershipCheck.listener,
        KdfTcpOwnershipEvidence.missing,
      );
      final start = supervisor.kdfMain({});
      await launched.future;
      await Future<void>.delayed(Duration.zero);
      var statusCompleted = false;
      final status = supervisor.kdfMainStatus().then((value) {
        statusCompleted = true;
        return value;
      });
      final statusCheck = expectLater(status, completion(MainStatus.rpcIsUp));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(statusCompleted, isFalse);
      expect(children, hasLength(1));
      versionFailure = null;
      expect(await start, KdfStartupResult.ok);
      await statusCheck;
      expect(stopRecipients, isEmpty);
    },
  );

  test('status does not turn failed startup into a ready process', () async {
    versionFailure = const KdfTcpOwnershipException(
      KdfTcpOwnershipCheck.listener,
      KdfTcpOwnershipEvidence.missing,
    );
    final start = supervisor.kdfMain({});
    await launched.future;
    final status = supervisor.kdfMainStatus();
    children.single.exited.complete(1);
    expect(await start, KdfStartupResult.spawnError);
    expect(await status, MainStatus.notRunning);
    expect(children, hasLength(1));
    expect(stopRecipients, isEmpty);
  });

  test(
    'status still requires a fresh ownership proof after joining startup',
    () async {
      final start = supervisor.kdfMain({});
      start.then((_) {
        versionFailure = const KdfTcpOwnershipException(
          KdfTcpOwnershipCheck.listener,
          KdfTcpOwnershipEvidence.foreign,
        );
      });
      final status = supervisor.kdfMainStatus();
      final check = expectLater(
        status,
        throwsA(isA<KdfTcpOwnershipException>()),
      );
      expect(await start, KdfStartupResult.ok);
      await check;
      expect(stopRecipients, isEmpty);
    },
  );

  test(
    'version read failure does not report a live generation as exited',
    () async {
      expect(await supervisor.kdfMain({}), KdfStartupResult.ok);
      versionFailure = StateError('Unowned listener');
      await expectLater(
        supervisor.version(),
        throwsA(
          isA<KdfTransportException>().having(
            (error) => error.reason,
            'reason',
            KdfTransportFailure.ownershipUnverified,
          ),
        ),
      );
      await expectLater(
        supervisor.isRunning(),
        throwsA(isA<KdfTransportException>()),
      );
      expect(stopRecipients, isEmpty);
      expect(children, hasLength(1));
      versionFailure = null;
      expect(await supervisor.version(), 'simulated');
      expect(await supervisor.isRunning(), isTrue);
    },
  );

  test(
    'startup retries an unavailable version probe without replacing its child',
    () async {
      final child = _Child(700);
      final directory = _TestDirectory();
      var probes = 0;
      final subject = WindowsKdfSupervisor(
        config: LocalConfig(https: false, rpcPassword: '', port: 17997),
        executableName: 'simulated',
        temporaryDirectory: () async => directory,
        logCallback: (_) {},
        startupTimeout: const Duration(seconds: 2),
        portVacant: () => true,
        launch: (_) async => (child, directory),
        control: (_, method, valid) async {
          if (method == 'version' && ++probes == 1)
            throw StateError('Unowned listener');
          return {'result': 'simulated'};
        },
      );
      try {
        expect(await subject.kdfMain({}), KdfStartupResult.ok);
        expect(probes, 2);
      } finally {
        child.exited.complete(0);
        await directory.deleted.future;
      }
    },
  );

  test(
    'foreign owner after successful start receives no authenticated request',
    () async {
      // A synthetic HTTP responder in a separate PID serves exactly one version.
      final responder = await _responder(1);
      final port = int.parse(
        await responder.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 8)),
      );
      var received = 0;
      final logs = <String>[];
      final child = _Child(responder.pid);
      final dir = _TestDirectory();
      final subject = WindowsKdfSupervisor(
        config: LocalConfig(
          https: false,
          rpcPassword: 'test-marker',
          port: port,
        ),
        executableName: 'simulated',
        temporaryDirectory: () async => dir,
        logCallback: logs.add,
        portVacant: () => true,
        launch: (_) async => (child, dir),
        startupTimeout: const Duration(seconds: 5),
      );
      try {
        expect(await subject.kdfMain({}), KdfStartupResult.ok);
        await responder.exitCode.timeout(const Duration(seconds: 5));
        final replacement = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        addTearDown(() => replacement.close(force: true));
        replacement.listen((r) async {
          received++;
          await r.response.close();
        });
        await expectLater(
          subject.mm2Rpc({'method': 'get_balance', 'private': 'body-marker'}),
          throwsA(
            isA<KdfTransportException>().having(
              (e) => e.reason,
              'reason',
              KdfTransportFailure.ownershipUnverified,
            ),
          ),
        );
        expect(received, 0);
        expect(logs.join(' '), contains('port=foreign'));
        expect(logs.join(' '), isNot(contains('marker')));
      } finally {
        child.exited.complete(0);
        await dir.deleted.future;
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'port takeover between preflight and SSE GET sends nothing and delivers no events',
    () async {
      // A synthetic HTTP responder in a separate PID serves exactly one version.
      final responder = await _responder(2, waitForRelease: true);
      final port = int.parse(
        await responder.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 8)),
      );
      var received = 0;
      final logs = <String>[];
      final child = _Child(responder.pid);
      final dir = _TestDirectory();
      final cfg = LocalConfig(
        https: false,
        rpcPassword: 'test-marker',
        port: port,
      );
      final subject = WindowsKdfSupervisor(
        config: cfg,
        executableName: 'simulated',
        temporaryDirectory: () async => dir,
        logCallback: logs.add,
        portVacant: () => true,
        launch: (_) async => (child, dir),
        startupTimeout: const Duration(seconds: 5),
      );
      try {
        expect(await subject.kdfMain({}), KdfStartupResult.ok);
        var ready = 0;
        var messages = 0;
        final lost = Completer<void>();
        final probe = cfg.supervisedVersion!;
        var passed = false;
        cfg.supervisedVersion = () async {
          final version = await probe();
          passed = version == 'simulated';
          // Keep the original listener alive until the authenticated version
          // read is complete, then deliberately create the ownership race.
          responder.stdin.writeln('release');
          await responder.exitCode.timeout(const Duration(seconds: 5));
          final other = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            port,
          );
          addTearDown(() => other.close(force: true));
          other.listen((r) async {
            received++;
            r.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            r.response.write('data: {"foreign":true}\n\n');
            await r.response.close();
          });
          return version;
        };
        final cancel = sse.connectEventStream(
          hostConfig: cfg,
          onFirstByte: () {
            ready++;
          },
          onMessage: (_) {
            messages++;
          },
          onDisconnected: ({required registrationsMayPersist}) {
            if (!lost.isCompleted) lost.complete();
          },
        );
        await lost.future.timeout(const Duration(seconds: 10));
        await cancel();
        expect(passed, isTrue);
        expect([received, ready, messages], [0, 0, 0]);
      } finally {
        // This exact synthetic responder was created by this fixture.
        responder.kill();
        child.exited.complete(0);
        await dir.deleted.future;
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'SSE preflight cannot post credentials after loss of ownership',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((r) async {
        requests++;
        await r.response.close();
      });
      final cfg = LocalConfig(
        https: false,
        rpcPassword: 'test-marker',
        port: server.port,
      )..supervisedVersion = () async => null;
      final lost = Completer<void>();
      final cancel = sse.connectEventStream(
        hostConfig: cfg,
        onMessage: (_) {},
        onFirstByte: () {},
        onDisconnected: ({required registrationsMayPersist}) {
          if (!lost.isCompleted) lost.complete();
        },
      );
      await lost.future.timeout(const Duration(seconds: 2));
      await cancel();
      expect(requests, 0);
    },
  );

  test(
    'verified SSE delivers an event from the owned listener',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final methods = <String>[];
      server.listen((request) async {
        methods.add(request.method);
        await request.drain<void>();
        if (request.method == 'POST') {
          request.response.write('{"result":"simulated"}');
        } else {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write('data: {"verified":true}\n\n');
        }
        await request.response.close();
      });
      final cfg = LocalConfig(https: false, rpcPassword: '', port: server.port);
      final child = _Child(pid);
      final dir = _TestDirectory();
      final subject = WindowsKdfSupervisor(
        config: cfg,
        logCallback: (_) {},
        executableName: 'simulated',
        temporaryDirectory: () async => dir,
        portVacant: () => true,
        launch: (_) async => (child, dir),
      );
      try {
        expect(await subject.kdfMain({}), KdfStartupResult.ok);
        var ready = 0;
        final event = Completer<Object?>();
        final cancel = sse.connectEventStream(
          hostConfig: cfg,
          onMessage: event.complete,
          onFirstByte: () {
            ready++;
          },
          onDisconnected: ({required registrationsMayPersist}) {},
        );
        try {
          expect(await event.future.timeout(const Duration(seconds: 3)), {
            'verified': true,
          });
          expect(ready, 1);
          expect(methods, ['POST', 'POST', 'GET']);
        } finally {
          await cancel();
        }
      } finally {
        child.exited.complete(0);
        await dir.deleted.future;
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'pipe diagnostics drain bursts without forwarding payloads or errors',
    () async {
      await supervisor.kdfMain({});
      for (final pipe in [children.single.output, children.single.errors]) {
        for (var i = 0; i < 100; i++) {
          pipe.add(utf8.encode('synthetic-private-marker'));
        }
        pipe.addError(StateError('synthetic-private-marker'));
        pipe.addError(StateError('synthetic-private-marker'));
      }
      await Future<void>.delayed(Duration.zero);
      expect(
        lifecycleLogs.where((s) => s.contains('phase=pipe')),
        hasLength(4),
      );
      expect(lifecycleLogs.join(), isNot(contains('synthetic-private-marker')));
    },
  );

  test(
    'owned HTTP sends fixed-length UTF-8 JSON and bounds silent RPCs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final endpoint = WindowsKdfEndpoint(
        Uri.http('127.0.0.1:${server.port}', '/'),
        '',
      );
      final observed = Completer<List<Object?>>();
      var count = 0;
      server.listen((req) async {
        final bytes = await req.expand((b) => b).toList();
        if (++count == 2) return;
        observed.complete([
          req.method,
          req.headers.contentType?.mimeType,
          req.headers.contentType?.charset,
          req.contentLength,
          req.headers.chunkedTransferEncoding,
          bytes,
        ]);
        req.response.statusCode = 400;
        req.response.write('{"error":"InvalidRequest"}');
        await req.response.close();
      });
      final body = jsonEncode({'method': 'simulated', 'label': 'ação 🟢'});
      final response = await endpoint.post(pid, body, () => true);
      expect(response.statusCode, 400);
      expect(jsonDecode(response.body)['error'], 'InvalidRequest');
      expect(await observed.future, [
        'POST',
        'application/json',
        'utf-8',
        utf8.encode(body).length,
        false,
        utf8.encode(body),
      ]);
      await expectLater(
        endpoint.post(
          pid,
          body,
          () => true,
          rpcTimeout: const Duration(milliseconds: 150),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(count, 2);
    },
    skip: !Platform.isWindows,
  );

  test('concurrent starts share launch and readiness', () async {
    final first = supervisor.kdfMain({});
    final second = supervisor.kdfMain({});
    expect(identical(first, second), isTrue);
    expect(await first, KdfStartupResult.ok);
    expect(children, hasLength(1));
  });

  test(
    'Windows verifies the owner of a connected loopback socket',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var received = 0;
      server.listen((request) async {
        await request.drain<void>();
        received++;
        request.response.write('{"result":"simulated"}');
        await request.response.close();
      });
      final endpoint = WindowsKdfEndpoint(
        Uri.http('127.0.0.1:${server.port}', '/'),
        '',
      );
      expect(endpoint.isVacant, isFalse);
      await expectLater(
        endpoint.call(pid + 1, 'stop', () => true),
        throwsA(
          isA<KdfTcpOwnershipException>().having(
            (error) => error.evidence,
            'evidence',
            KdfTcpOwnershipEvidence.foreign,
          ),
        ),
      );
      expect(received, 0);
      expect(
        (await endpoint.call(pid, 'version', () => true))['result'],
        'simulated',
      );
      expect(received, 1);
    },
    skip: !Platform.isWindows,
  );

  test('stop timeout retains generation until actual exit', () async {
    await supervisor.kdfMain({});
    expect(await supervisor.kdfStop(), StopStatus.errorStopping);
    expect(supervisor.processId, 100);
    expect(stopRecipients, [100]);
    expect(await supervisor.kdfMain({}), KdfStartupResult.spawnError);
    children.single.exited.complete(0);
    await Future<void>.delayed(Duration.zero);
    listener = 101;
    expect(await supervisor.kdfMain({}), KdfStartupResult.ok);
    expect(supervisor.processId, 101);
  });

  test('delayed cleanup of A cannot clear B or cancel its pipes', () async {
    await supervisor.kdfMain({});
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final cleaning = Completer<void>();
    children.single.output.onCancel = () {
      cleaning.complete();
      return release.future;
    };
    children.single.exited.complete(9);
    await cleaning.future;
    listener = 101;
    expect(await supervisor.kdfMain({}), KdfStartupResult.ok);
    release.complete();
    await directories.first.deleted.future;
    expect(supervisor.processId, 101);
    expect(children.last.output.hasListener, isTrue);
    expect(children.last.errors.hasListener, isTrue);
  });

  const login = {'wallet_name': 'fixture', 'allow_registrations': false};

  Future<void> stopInitialChild() async {
    expect(await supervisor.kdfMain({}), KdfStartupResult.ok);
    final stop = supervisor.kdfStop();
    await Future<void>.delayed(Duration.zero);
    children.single.exited.complete(0);
    expect(await stop, StopStatus.ok);
    expect(stopRecipients, [100]);
  }

  test(
    'isolated login retries once after early code one and keeps diagnostics safe',
    () async {
      await stopInitialChild();
      listener = 102;
      final start = supervisor.kdfMain(login);
      expect(identical(start, supervisor.kdfMain(login)), isTrue);
      await Future<void>.delayed(Duration.zero);
      final failed = children[1];
      failed.errors.add(utf8.encode('fixture-private database is '));
      failed.exited.complete(1);
      failed.errors.add(utf8.encode('locked fixture-private'));
      unawaited(failed.errors.close());
      unawaited(failed.output.close());
      expect(await start, KdfStartupResult.ok);
      expect(children.map((child) => child.pid), [100, 101, 102]);
      expect(supervisor.processId, 102);
      expect(stopRecipients, [100]);
      expect(lifecycleLogs.join(), isNot(contains('fixture-private')));
      expect(
        lifecycleLogs.where(
          (line) => line.contains('category=database_locked'),
        ),
        hasLength(1),
      );
      expect(
        lifecycleLogs.where(
          (line) => line.contains('category=early_login_exit_retry'),
        ),
        hasLength(1),
      );
    },
  );

  test('an occupied port after early exit prevents login retry', () async {
    await stopInitialChild();
    listener = null;
    final start = supervisor.kdfMain(login);
    await Future<void>.delayed(Duration.zero);
    vacant = false;
    children[1].exited.complete(1);
    expect(await start, KdfStartupResult.spawnError);
    expect(children, hasLength(2));
    expect(stopRecipients, [100]);
    expect(
      lifecycleLogs.any((line) => line.contains('category=port_busy')),
      isTrue,
    );
  });

  test(
    'a second early exit surfaces the failure without a third attempt',
    () async {
      await stopInitialChild();
      listener = null;
      final start = supervisor.kdfMain(login);
      await Future<void>.delayed(Duration.zero);
      children[1].exited.complete(1);
      while (children.length < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      children[2].exited.complete(1);
      expect(await start, KdfStartupResult.spawnError);
      expect(children, hasLength(3));
    },
  );

  test('registration or a cold login failure does not retry', () async {
    listener = null;
    final cold = supervisor.kdfMain(login);
    await Future<void>.delayed(Duration.zero);
    children[0].exited.complete(1);
    expect(await cold, KdfStartupResult.spawnError);
    expect(children, hasLength(1));

    listener = 101;
    expect(await supervisor.kdfMain({}), KdfStartupResult.ok);
    final stop = supervisor.kdfStop();
    await Future<void>.delayed(Duration.zero);
    children[1].exited.complete(0);
    expect(await stop, StopStatus.ok);
    listener = null;
    final register = supervisor.kdfMain({
      ...login,
      'allow_registrations': true,
    });
    await Future<void>.delayed(Duration.zero);
    children[2].exited.complete(1);
    expect(await register, KdfStartupResult.spawnError);
    expect(children, hasLength(3));
  });

  test('exit before bind, including code zero, is not readiness', () async {
    listener = null;
    final start = supervisor.kdfMain({});
    await launched.future;
    children.single.exited.complete(0);
    expect(await start, KdfStartupResult.spawnError);
    expect(supervisor.processId, isNull);
  });

  test('foreign listener during startup receives no stop', () async {
    listener = 999;
    expect(await supervisor.kdfMain({}), KdfStartupResult.spawnError);
    expect(await supervisor.version(), isNull);
    expect(await supervisor.kdfStop(), StopStatus.errorStopping);
    expect(stopRecipients, isEmpty);
    expect(supervisor.processId, 100);
  });

  test(
    'occupied port before launch blocks spawn and fallback version',
    () async {
      vacant = false;
      expect(await supervisor.kdfMain({}), KdfStartupResult.spawnError);
      expect(children, isEmpty);
      expect(await supervisor.version(), isNull);
      expect(await supervisor.kdfStop(), StopStatus.notRunning);
    },
  );
}
