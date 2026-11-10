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
