import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:web_dex/services/testing/disposable_runtime_profile.dart';

/// Separate from the known disposable wallet. No wallet is created or imported.
class PrivateManualProfile {
  PrivateManualProfile._(this.root);
  static const approvedRoot =
      r'E:\codex\LitecoinCashDEX-Next\.private-testing\manual-20261109';
  static const markerName = 'NEXT_PRIVATE_MANUAL_PROFILE';
  static const markerValue = 'next-private-user-operated-v1';
  final String root;

  static bool scopeValid({
    required bool requested,
    required bool isolated,
    required bool walletOnly,
    required bool fullTest,
    required bool windows8762,
    required String root,
    required String approvedEnvironmentRoot,
    required int rpcPort,
    required String geoPolicy,
  }) =>
      requested &&
      isolated &&
      !walletOnly &&
      !fullTest &&
      windows8762 &&
      root == approvedRoot &&
      approvedEnvironmentRoot == approvedRoot &&
      rpcPort == 17993 &&
      geoPolicy == 'disabled';

  static Future<PrivateManualProfile> open(String root) async {
    if (!p.isAbsolute(root)) {
      throw StateError('Absolute private profile required');
    }
    final normalized = p.normalize(root);
    final directory = Directory(normalized);
    if (!await directory.exists() ||
        !p.equals(normalized, await directory.resolveSymbolicLinks())) {
      throw StateError('Private profile missing or redirected');
    }
    final marker = File(p.join(normalized, markerName));
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        (await marker.readAsString()).trim() != markerValue ||
        await File(
          p.join(normalized, DisposableRuntimeProfile.markerName),
        ).exists()) {
      throw StateError('A separate private manual profile is required');
    }
    for (final folder in [
      'home',
      'appdata',
      'localappdata',
      'documents',
      'support',
      'cache',
      'temp',
      'downloads',
      'logs',
    ]) {
      final child = Directory(p.join(normalized, folder));
      final type = await FileSystemEntity.type(child.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw StateError('Redirected private directory');
      }
      await child.create();
      if (!p.isWithin(normalized, await child.resolveSymbolicLinks())) {
        throw StateError('Private directory outside profile');
      }
    }
    return PrivateManualProfile._(normalized);
  }

  void install() => installIsolatedProfileStorage(root);
}
