import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Refuse an accidental upstream network/policy build before opening storage.
void validateCommunityBuild() {
  if (!kWindows8762Release ||
      !kUseLegacyKdf ||
      kDefaultNetId != 8762 ||
      const String.fromEnvironment('GEO_BLOCK', defaultValue: 'disabled') !=
          'disabled') {
    throw StateError('Use the community Windows 8762 build configuration');
  }
}
