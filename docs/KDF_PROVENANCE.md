# KDF provenance — unmodified upstream candidate

This candidate selects the official Windows x64 **v2.4.0-beta** engine, revision
`c800ea03f12dab33d2dc04a1d858ee6da111203f`. It excludes the later community
balance/order guard and its diagnostic logging. No KDF source or executable
bytes are modified. The runtime filename is changed for process isolation only.

Official release:
https://github.com/GLEECBTC/komodo-defi-framework/releases/tag/v2.4.0-beta

Official ZIP SHA-256:
`A50CEA582FEEB268924CC9591A6BDF3F7F00B344821D1A46463461050F435B1A`

Extracted `mm2.exe` SHA-256 (64,461,824 bytes):
`FB641F1DF1CEB46D7C26F71BCA6BED12ACC07DEB188C7A96F93D20DF61B24AB2`

Embedded identity:
`2.4.0-beta_c800ea03f2025-05-05T19:53:21.001330400+00:00`

The ZIP and clear-signed checksums were verified with GPG against the release's
published fingerprint `FD9A772C7300F4C894D1A819FE50480862E6451C`.
The key was obtained from the release-linked Keybase account. This verifies
signatures against that published key, not an independent identity certification.
The release tag resolves to the exact source revision above. No claim of a
bit-identical local Rust rebuild is made. The original source export is tracked
by hash in `artifacts/kdf/windows.lock.json`; it is not committed as a ZIP.

`LEGAL/COPYING`, `LEGAL/LICENSE-COPYRIGHT-NOTICE` and third-party notices of this
revision are preserved under `LICENSES/KDF/`. The notice identifies Pampex LTD
and TillyHK LTD (2023); a newer upstream notice must not replace it retroactively.
The notice covers source and binary. Retaining original bytes does not dispense
with applicable distribution obligations or confer a blanket legal clearance.

The community patch formerly distributed in earlier source references is not
included in the new source tree. Historical commits/releases are unchanged;
this removal does not undo that earlier distribution. Its assessment, including
the GPLv3 section 7 question, remains a separate documented issue.

This upstream candidate restores the original insufficient-balance order
handling. A positive balance is not assumed sufficient for fees or open orders.
No live compatibility result is claimed until a separately authorized trial.
No engine, new application package or source change is published automatically.
