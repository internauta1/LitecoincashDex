/// Shared constants used across the Komodo DeFi SDK packages.
library komodo_defi_types.constants;

/// Default network identifier used by seed nodes and framework configuration.
const int kDefaultNetId =
    bool.fromEnvironment('LCC_NEXT_WINDOWS_8762', defaultValue: true)
    ? 8762
    : 6133;
