# Third-party notices

This community distribution derives from Gleec Wallet / Komodo Wallet:
https://github.com/GLEECBTC/gleec-wallet

The application repository contains the GNU GPL v3 license in `LICENSE`.
Existing upstream copyright notices remain applicable. Rebranding does not
remove upstream authorship or change the license of existing code.

The local SDK is derived from:
https://github.com/GLEECBTC/komodo-defi-sdk-flutter

Individual SDK packages contain their own `LICENSE` files, including MIT
licenses with GLEEC copyright. Preserve those files with the corresponding
package sources. The SDK has local modifications and must not be described
as an unchanged upstream checkout.

`third_party/flutter_inappwebview_windows` is distributed under its included
Apache License 2.0. Preserve its license and upstream notices along with the
local Windows build changes.

Flutter/Dart packages, fonts, coin logos and other assets retain their own
licenses and ownership. This document is a starting inventory, not a statement
that every third-party asset has completed redistribution review.

Before binary releases, record the exact source and applicable notices for the
bundled KDF, its native dependencies and each OS/architecture. An executable
hash alone does not identify complete corresponding source. Make required
corresponding source available alongside the release. See the release gates
in `docs/publication/READINESS.md`.

## Added distribution notices

Font metadata and licenses are retained under `LICENSES/` (Manrope/Rubik SIL OFL 1.1; Roboto Apache 2.0). KDF legal notices are retained separately under `LICENSES/KDF/`; they include their own copyright/usage restrictions and are not replaced by the GUI GPL. See `docs/KDF_PROVENANCE.md`.
