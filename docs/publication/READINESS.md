# Windows initial publication readiness

This isolated source tree targets Windows x64 first. Linux/macOS are retained as
future ports and remain unsupported by the native Windows 8762 implementation.

Prepared: vendored modified SDK, explicit 8762 defaults/startup guard, unchanged
legacy KDF provisioned by hash, pinned dependencies/static asset inputs, local
WebView fix, reviewed read-only Windows CI with no automatic releases, font/KDF
notices, offline regression tests and separate production/validation builds.

Required before publication: review the exact source import, source/dependency
manifests and secret scan; complete clean-checkout Windows build/test evidence;
authorized disposable visual trial; decide public KDF binary/source artifact URLs,
source availability and signing. GitHub Actions has not run until an authorized
push. Source code readiness and signed stable-binary readiness are different.

No original installation, wallet, private test profile, running KDF or classic
application may be modified by these preparation steps. No real transactions,
orders, transfers, publication or automatic wallet launch are authorized.

## Unmodified upstream candidate — 13 November 2026

This isolated follow-up replaces the community KDF only in a new candidate.
The approved R1, Preview 3 packages, existing installations and public history
remain intact. See `docs/KDF_PROVENANCE.md` for the exact signed upstream input.
A previous source-only release is not an exemption from conditions applicable
to its included patch. That earlier distribution remains within the review.

Remaining candidate checks are focused upstream compatibility and package/source
integrity. A new 30–60 minute trial is not an automatic requirement for this
experimental Preview. Do not record those longer tests as having been repeated.
A concrete security, essential-function or distribution failure must be reported;
no check may be bypassed to declare readiness. New hashes require new approval.
