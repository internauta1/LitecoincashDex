import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class KdfOperationsRemote implements IKdfOperations {
  // TODO! Add wallet password and name or add the config object
  factory KdfOperationsRemote.create({
    required void Function(String) logCallback,
    // required String ipAddress,
    // required int port,
    required Uri rpcUrl,
    required String userpass,
  }) {
    return KdfOperationsRemote._(logCallback, rpcUrl, userpass);
  }

  KdfOperationsRemote._(this._logCallback, this._rpcUrl, this._userpass);
  final void Function(String) _logCallback;
  final String _userpass;

  final Uri _rpcUrl;

  Uri get _baseUrl => _safeRpcUrl(_rpcUrl);

  static const String _forwardProxy =
      'https://proxy-se-push.go-away-bugs.co.za/?target=';

  static const bool _proxyRequests = false;

  Uri _safeRpcUrl(Uri rpcUrl) {
    var url = rpcUrl;
    // If the scheme is not provided, default to http
    url = url.scheme.isEmpty ? url.replace(scheme: 'http') : url;

    // Normalize localhost to 127.0.0.1 to avoid DNS resolution issues on Android
    if (url.host == 'localhost') {
      return url.replace(host: '127.0.0.1');
    }
    if (url.host == '127.0.0.1') {
      return url;
    }

    // if (!kIsWeb) {
    //   return url;
    // }

    // NB: The code below is for a workaround to avoid CORS issues when
    // running in the browser. This is needed at least until the time when
    // the KDF releases the CORS failing OPTIONS preflight requests available
    // on `fix-allow-options-req` branch.
    // However, this may be needed long-term if we want to cater for users who
    // don't have CORS configured on their KDF servers.

    // If on the web, check if the cors preflight succeeds
    // TODO:

    // If the cors preflight fails, return a url that will be proxied by the
    // forward proxy 134.122.60.102
    // TODO:

    return Uri.parse('${_proxyRequests ? _forwardProxy : ''}$url');
  }

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async {
    // Check if the remote server is reachable
    try {
      final uri = Uri.parse(
        'http://${(hostConfig as RemoteConfig).ipAddress}:${hostConfig.port}',
      );
      final response = await http.get(uri);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _log(String message) => _logCallback(message);

  @override
  String operationsName = 'Remote RPC Server';

  @override
  Future<bool> isRunning() async {
    return await kdfMainStatus() == MainStatus.rpcIsUp;
  }

  @override
  Future<KdfStartupResult> kdfMain(JsonMap startParams, {int? logLevel}) async {
    const message =
        'KDF cannot be started using Remote client. '
        'Please start the KDF on the remote server manually.';
    _log(message);

    // return KdfStartupResult.invalidParams;
    throw UnimplementedError(message);
  }

  @override
  Future<MainStatus> kdfMainStatus() async {
    final versionResult = await version();
    return versionResult != null ? MainStatus.rpcIsUp : MainStatus.noRpc;
  }

  @override
  Future<StopStatus> kdfStop() async {
    try {
      final stopResultResponse = await mm2Rpc({'method': 'stop'});

      _log('KDF stop response received');

      return _parseStopResult(stopResultResponse);
    } on Exception {
      _log('KDF stop failed');
      return StopStatus.errorStopping;
    }
  }

  // Could be shared with other implementations?
  StopStatus _parseStopResult(dynamic stopResponse) {
    if (stopResponse['error'] != null) {
      return StopStatus.errorStopping;
    }

    switch (stopResponse['result']) {
      case 'already_stopped':
        return StopStatus.stoppingAlready;
      case 'success':
        return StopStatus.ok;
      default:
        final maybeResultCode = stopResponse is int?
            ? stopResponse
            : int.tryParse(stopResponse.toString());

        return maybeResultCode != null
            ? StopStatus.fromDefaultInt(maybeResultCode)
            : StopStatus.errorStopping;
    }
  }

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) => sendRpc(request,
      (body) => http.post(_baseUrl, body: body));

  Future<Map<String, dynamic>> sendRpc(Map<String, dynamic> request,
      Future<http.Response> Function(String body) post) async {
    if (request['userpass'] == null) {
      request['userpass'] = _userpass;
    }

    if (KdfLoggingConfig.verboseLogging) {
      _logCallback('KDF remote RPC request dispatched');
    }

    late final http.Response response;

    try {
      response = await post(json.encode(request));
    } on http.ClientException {
      // ClientException can include a credential-bearing URL. Keep the public
      // failure stable and free of transport internals.
      return ConnectionError('Remote KDF request failed');
    }

    if (response.statusCode != 200) {
      // Diagnostic only. Never log credentials or raw RPC responses.
      final rawMethod = request['method'];
      final safeMethod = rawMethod is String &&
              RegExp(r'^[A-Za-z0-9_]{1,64}$').hasMatch(rawMethod)
          ? rawMethod
          : 'unknown';

      String errorType = 'not_provided';
      String errorClass = 'unclassified';

      try {
        final payload = json.decode(response.body);

        if (payload is Map) {
          final nested = payload['error'];
          final candidate = nested is Map
              ? nested['error_type']
              : payload['error_type'];

          if (candidate is String &&
              RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$')
                  .hasMatch(candidate)) {
            errorType = candidate;
          }

          final details = [
            payload['message'],
            nested is Map ? nested['error'] : nested,
          ].whereType<String>().join(' ').toLowerCase();

          if (details.contains('method not found') ||
              details.contains('unknown method')) {
            errorClass = 'method_not_found';
          } else if (details.contains('invalid param') ||
              details.contains('invalid request')) {
            errorClass = 'invalid_parameters';
          } else if (details.contains('unauthorized') ||
              details.contains('authentication')) {
            errorClass = 'authentication';
          } else if (details.contains('timeout') ||
              details.contains('timed out')) {
            errorClass = 'timeout';
          } else if (details.contains('connection') ||
              details.contains('network')) {
            errorClass = 'network';
          }
        }
      } catch (_) {
        // A non-JSON error body is not included in diagnostics.
      }

      _log(
        'LCC_RPC_DIAG method=$safeMethod '
        'http=${response.statusCode} '
        'error_type=$errorType '
        'class=$errorClass',
      );
      // LCC_PRESERVE_KDF_ERROR
      // Preserve structured KDF errors for the existing SDK parser.
      // Never log raw response bodies or request credentials.
      try {
        final decodedError = json.decode(response.body);

        if (decodedError is Map<String, dynamic>) {
          final result = decodedError['result'];
          final details = result is Map ? result['details'] : null;

          final structuredError =
              decodedError.containsKey('error') ||
              decodedError.containsKey('error_type') ||
              decodedError['code'] == -1 ||
              (result is Map && result['status'] == 'Error') ||
              (details is Map && details.containsKey('error'));

          if (structuredError) {
            // Classify parser failures without exposing response contents.
            if (request['method'] == 'enable_eth_with_tokens') {
              final nested = decodedError['error'];
              final nestedMap = nested is Map ? nested : null;

              final rawPath =
                  decodedError['error_path'] ?? nestedMap?['error_path'];

              final safePath = rawPath is String &&
                      RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.]{0,95}$')
                          .hasMatch(rawPath)
                  ? rawPath
                  : 'unknown';

              final parts = <String>[];

              for (final value in [
                decodedError['error'],
                decodedError['error_data'],
                decodedError['message'],
                nestedMap?['error'],
                nestedMap?['error_data'],
                nestedMap?['message'],
              ]) {
                if (value is String) {
                  parts.add(value.toLowerCase());
                }
              }

              final reason = parts.join(' ');

              String issue = 'unclassified';

              if (reason.contains('unknown variant')) {
                issue = 'unknown_variant';
              } else if (reason.contains('missing field')) {
                issue = 'missing_field';
              } else if (reason.contains('unknown field')) {
                issue = 'unknown_field';
              } else if (reason.contains('invalid type')) {
                issue = 'invalid_type';
              } else if (reason.contains('invalid value')) {
                issue = 'invalid_value';
              } else if (reason.contains('error parsing')) {
                issue = 'parse_error';
              }

              String field = 'none';
              for (final candidate in [
                'priv_key_policy',
                'gap_limit',
                'rpc_mode',
                'nodes',
                'ticker',
                'erc20_tokens_requests',
                'swap_contract_address',
                'fallback_swap_contract',
                'get_balances',
                'tx_history',
                'mmrpc',
              ]) {
                if (reason.contains(candidate)) {
                  field = candidate;
                  break;
                }
              }

              String variant = 'none';
              for (final candidate in [
                'metamask',
                'walletconnect',
                'contextprivkey',
                'default',
                'trezor',
              ]) {
                if (reason.contains(candidate)) {
                  variant = candidate;
                  break;
                }
              }

              _log(
                'LCC_RPC_PARSE_DIAG '
                'path=$safePath issue=$issue '
                'field=$field variant=$variant',
              );
            }

            return decodedError;
          }
        }
      } catch (_) {
        // Retain the existing fallback for malformed responses.
      }

      return JsonRpcErrorResponse(
        code: response.statusCode,
        error: {
          'error': 'HTTP Error',
          'status': response.statusCode,
        }.toJsonString(),
        message: 'Remote KDF returned HTTP ${response.statusCode}',
      );
    }

    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Do not surface FormatException.source: it contains the upstream body.
    }
    return JsonRpcErrorResponse(
      code: response.statusCode,
      error: 'InvalidKdfResponse',
      message: 'Remote KDF returned a malformed JSON response',
    );
  }

  @override
  Future<void> validateSetup() async {
    final version = await this.version();
    if (version == null) {
      throw Exception('Failed to validate remote KDF setup');
    }
  }

  @override
  Future<String?> version() async {
    try {
      final response = await mm2Rpc({'method': 'version'});

      final maybeError = response.valueOrNull<String>('error');

      if (maybeError != null) {
        _log('Error getting remote KDF version');
        return null;
      }

      return response.valueOrNull<String?>('result');
    } on http.ClientException {
      return null;
    }
  }

  @override
  void resetHttpClient() {
    // No-op for remote operations - HTTP client is managed by http package
    _log('resetHttpClient called on remote operations (no-op)');
  }

  @override
  void dispose() {
    // No-op for remote operations - HTTP client is managed externally
  }
}
