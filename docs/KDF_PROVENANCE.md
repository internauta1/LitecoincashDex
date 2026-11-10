# Pinned KDF provenance

Validated Windows executable:
`E752B26C8208111DA9AA2F4A1AF61CA0ED818C5BF65E745C1DB21ACF5C34B6D8`
(64,549,376 bytes). Its embedded version identifies
`2.4.0-beta_43251de1a`, timestamp 2026-09-27T19:32:35.529190+00:00.

The full corresponding local Git revision was found as
`43251de1a425d32334cd5830bc8ffba716812a0f`, descending from public upstream
`c800ea03f12dab33d2dc04a1d858ee6da111203f`. The two community commits modify
only `mm2src/mm2_main/src/lp_ordermatch.rs`: transient-zero-volume guard and
balance/cancellation diagnostics. Their aggregate source patch is retained in
`publication/KDF-COMMUNITY.patch`. The later dirty working tree was not copied.
An archive was created from the immutable commit object, not from that working
tree. Its hash is recorded in the engine lockfile. There are no Git submodules
in that source revision.

Public upstream reference:
https://github.com/GLEECBTC/komodo-defi-framework/commit/c800ea03f12dab33d2dc04a1d858ee6da111203f

The community commit was not found in the public upstream API. The exact KDF
source ZIP is prepared separately for eventual redistribution with the binary;
public URLs remain pending authorization. The binary has not been rebuilt or
changed here. Embedded version plus source history is provenance evidence, not
a claim of a bit-for-bit Rust rebuild or proof of original build flags.

Original `LEGAL/COPYING`, `LEGAL/LICENSE-COPYRIGHT-NOTICE` and third-party notices
are preserved under `LICENSES/KDF/`, and in the source ZIP. These include terms
beyond the GUI license. Do not remove those notices, modify fee-related protected
sections or describe the entire KDF solely as MIT/GPL GUI code. Publishing the
source ZIP, binary and notices together remains a release gate.
