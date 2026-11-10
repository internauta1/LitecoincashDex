import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../exceptions/kdf_transport_exception.dart';
import 'windows_tcp_ownership.dart';

typedef _TableNative =
    Uint32 Function(
      Pointer<Void>,
      Pointer<Uint32>,
      Int32,
      Uint32,
      Int32,
      Uint32,
    );
typedef _TableDart =
    int Function(Pointer<Void>, Pointer<Uint32>, int, int, int, int);

/// Lifecycle RPC only. Ownership is checked on the *connected* server socket
/// before HttpClient is given the connection and can transmit credentials.
class WindowsKdfEndpoint {
  WindowsKdfEndpoint(
    this.url,
    this._rpcPassword, {
    WindowsTcpTableQuery? tcpQuery,
    void Function(String)? ownershipLog,
  }) : _query = tcpQuery ?? _tcpTable,
       _ownershipLog = ownershipLog;
  final WindowsTcpTableQuery _query;
  final void Function(String)? _ownershipLog;
  final Uri url;
  final String _rpcPassword;
  static final _tcpTable = DynamicLibrary.open(
    'iphlpapi.dll',
  ).lookupFunction<_TableNative, _TableDart>('GetExtendedTcpTable');

  static Future<void> requireNoExistingProcess(String executable) async {
    // Match the full image path; two products may use the same basename.
    // Neither command lines nor configuration contents are retrieved.
    final shell = Platform.environment['SystemRoot'];
    if (shell == null) throw StateError('Windows directory unavailable');
    final imageName = File(executable).uri.pathSegments.last;
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(imageName)) {
      throw StateError('Invalid KDF image name');
    }
    final result = await Process.run(
      '$shell\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
$ErrorActionPreference = 'Stop'
$existing = Get-CimInstance Win32_Process -Filter ("Name='{0}'" -f $env:NEXT_EXPECTED_NAME) -Property ExecutablePath
foreach ($item in $existing) {
  if (-not $item.ExecutablePath -or $item.ExecutablePath -eq $env:NEXT_EXPECTED_IMAGE) { exit 2 }
}
exit 0
''',
      ],
      environment: {
        'NEXT_EXPECTED_IMAGE': executable,
        'NEXT_EXPECTED_NAME': imageName,
      },
    ).timeout(const Duration(seconds: 8));
    if (result.exitCode != 0) {
      throw StateError('Existing KDF or image ownership unverifiable');
    }
  }

  // IPv4 MIB_TCPTABLE_OWNER_PID is a DWORD count followed by six DWORDs
  // per row. Only loopback peers can be used by the Next local transport.
  Set<int> _owners({int? clientPort}) => readWindowsTcpOwners(
    query: _query,
    rpcPort: url.port,
    clientPort: clientPort,
  );

  bool get isVacant => _owners().isEmpty;

  Future<Map<String, dynamic>> call(
    int pid,
    String method,
    bool Function() isCurrent,
  ) async {
    if (method != 'version' && method != 'stop') throw ArgumentError('method');
    final response = await post(
      pid,
      jsonEncode({'method': method, 'userpass': _rpcPassword}),
      isCurrent,
      lifecycle: true,
    );
    if (response.statusCode != 200) throw StateError('KDF control RPC failed');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String portState(int pid) {
    try {
      final owners = _owners();
      if (owners.isEmpty) return 'vacant';
      return owners.length == 1 && owners.contains(pid) ? 'owned' : 'foreign';
    } catch (_) {
      return 'unknown';
    }
  }

  static final streams =
      Expando<(HttpClient Function(), bool Function()) Function()>();

  Future<void> _verifyOwner(
    int pid,
    bool Function() isCurrent, {
    int? clientPort,
  }) async {
    final check = clientPort == null
        ? KdfTcpOwnershipCheck.listener
        : KdfTcpOwnershipCheck.connection;
    const delays = [
      Duration.zero,
      Duration(milliseconds: 2),
      Duration(milliseconds: 8),
    ];
    for (var index = 0; index < delays.length; index++) {
      if (index > 0) await Future<void>.delayed(delays[index]);
      if (!isCurrent()) {
        throw const KdfTransportException(
          KdfTransportFailure.generationUnavailable,
        );
      }
      final Set<int> owners;
      try {
        owners = _owners(clientPort: clientPort);
      } on StateError {
        throw KdfTcpOwnershipException(
          check,
          KdfTcpOwnershipEvidence.unavailable,
        );
      }
      if (pid > 0 && owners.length == 1 && owners.contains(pid)) {
        if (index > 0) {
          _ownershipLog?.call(
            'kdf ownership check=${check.name} evidence=missing recovered_after=${index + 1}',
          );
        }
        return;
      }
      if (owners.isNotEmpty) {
        throw KdfTcpOwnershipException(check, KdfTcpOwnershipEvidence.foreign);
      }
    }
    throw KdfTcpOwnershipException(check, KdfTcpOwnershipEvidence.missing);
  }

  HttpClient verifiedClient(int pid, bool Function() isCurrent) {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 5);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      var cancelled = false;
      ConnectionTask<Socket>? attempt;
      Socket? connectedSocket;
      bool valid() => !cancelled && isCurrent();
      Future<Socket> connect() async {
        await _verifyOwner(pid, valid);
        if (!valid()) {
          throw const KdfTransportException(
            KdfTransportFailure.generationUnavailable,
          );
        }
        final task = attempt = await Socket.startConnect(
          InternetAddress.loopbackIPv4,
          url.port,
        );
        if (!valid()) task.cancel();
        final socket = connectedSocket = await task.socket;
        try {
          // Recheck the same established socket. No HTTP bytes have been sent.
          await _verifyOwner(pid, valid, clientPort: socket.port);
          if (!valid()) {
            throw const KdfTransportException(
              KdfTransportFailure.generationUnavailable,
            );
          }
          return socket;
        } catch (_) {
          socket.destroy();
          rethrow;
        }
      }

      final socketFuture = connect();
      // A synchronous ownership refusal can complete before HttpClient has
      // unwrapped the ConnectionTask. It still receives the original error.
      socketFuture.ignore();
      return ConnectionTask.fromSocket(socketFuture, () {
        cancelled = true;
        attempt?.cancel();
        connectedSocket?.destroy();
      });
    };
    return client;
  }

  Future<http.Response> post(
    int pid,
    String body,
    bool Function() isCurrent, {
    bool lifecycle = false,
    Duration rpcTimeout = const Duration(minutes: 2),
  }) async {
    var expired = false;
    final client = verifiedClient(pid, () => !expired && isCurrent());
    Future<http.Response> send() async {
      final request = await client.postUrl(url);
      if (expired || !isCurrent()) throw StateError('Stale KDF generation');
      request.followRedirects = false;
      final bytes = utf8.encode(body);
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      return http.Response.bytes(
        await response.expand((bytes) => bytes).toList(),
        response.statusCode,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    try {
      return await send().timeout(
        lifecycle ? const Duration(seconds: 2) : rpcTimeout,
      );
    } finally {
      expired = true;
      client.close(force: true);
    }
  }
}
