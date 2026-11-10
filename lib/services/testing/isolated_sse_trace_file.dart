import 'dart:convert';
import 'dart:io';

import 'package:komodo_defi_framework/src/streaming/sse_diagnostics.dart';
import 'package:path/path.dart' as p;
import 'package:web_dex/services/testing/disposable_runtime_profile.dart';

/// Live, metadata-only evidence for the explicitly approved disposable runner.
/// It does not replace or intercept the application's SSE event stream.
class IsolatedSseTraceFile {
  IsolatedSseTraceFile._(this.file);

  final File file;
  static const _fields = {
    'utc',
    'connection',
    'frame',
    'stage',
    'kind',
    'reason',
    'count',
  };

  static IsolatedSseTraceFile create(DisposableRuntimeProfile profile) {
    final logs = Directory(p.join(profile.root, 'logs'));
    if (FileSystemEntity.typeSync(logs.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !p.equals(logs.path, logs.resolveSymbolicLinksSync())) {
      throw StateError('Disposable trace directory unavailable');
    }
    final file = File(
      p.join(
        logs.path,
        'sse-live-${DateTime.now().microsecondsSinceEpoch}.jsonl',
      ),
    );
    file.createSync(exclusive: true);
    return IsolatedSseTraceFile._(file);
  }

  bool write(String line) {
    if (!line.startsWith('LCC_SSE ') || line.length > 2048) return false;
    try {
      final value = jsonDecode(line.substring(8));
      if (value is! Map<String, dynamic> ||
          value.keys.any((key) => !_fields.contains(key)) ||
          value['utc'] is! String ||
          (value['utc'] as String).length > 40 ||
          value['connection'] is! int ||
          value['connection'] < 1 ||
          value['count'] is! int ||
          value['count'] < 1 ||
          !SseStage.values.any((stage) => stage.name == value['stage']) ||
          (value.containsKey('frame') &&
              (value['frame'] is! int || value['frame'] < 1)) ||
          (value.containsKey('kind') &&
              !SseEventKind.values.any((kind) => kind.name == value['kind'])) ||
          (value.containsKey('reason') &&
              !SseReason.values.any(
                (reason) => reason.name == value['reason'],
              ))) {
        return false;
      }
      final utc = DateTime.tryParse(value['utc'] as String);
      if (utc == null || !utc.isUtc) return false;
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          !p.equals(file.path, file.resolveSymbolicLinksSync())) {
        return false;
      }
      // Re-encode only the fixed schema; never persist an arbitrary log line.
      value['utc'] = utc.toUtc().toIso8601String();
      file.writeAsStringSync(
        'LCC_SSE ${jsonEncode(value)}\n',
        mode: FileMode.append,
        flush: true,
      );
      return true;
    } on Object {
      // Diagnostics must neither disclose failures nor interrupt the wallet.
      return false;
    }
  }
}
