// The framework exports the local backend on web too. Keep Windows FFI out of
// the web import graph; the factory selects this supervisor only on Windows.
import 'dart:io';
import 'package:http/http.dart' as http;

class WindowsKdfEndpoint {
  WindowsKdfEndpoint(
    Uri url,
    String rpcPassword, {
    void Function(String)? ownershipLog,
  });
  static Future<void> requireNoExistingProcess(String executable) =>
      throw UnsupportedError('Windows only');
  static final streams =
      Expando<(HttpClient Function(), bool Function()) Function()>();
  HttpClient verifiedClient(int pid, bool Function() isCurrent) =>
      throw UnsupportedError('Windows only');
  String portState(int pid) => 'unknown';
  Future<http.Response> post(
    int pid,
    String body,
    bool Function() valid, {
    bool lifecycle = false,
  }) => throw UnsupportedError('Windows only');
  bool get isVacant => throw UnsupportedError('Windows only');
  Future<Map<String, dynamic>> call(
    int pid,
    String method,
    bool Function() valid,
  ) => throw UnsupportedError('Windows only');
}
