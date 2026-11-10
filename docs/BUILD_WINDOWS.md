# Build Windows from source

Use Flutter 3.41.4 and Visual Studio 2022 with the C++ desktop workload. Resolve
dependencies with the committed lockfile, not a new version selection.
`pubspec_overrides.yaml` points to vendored SDK packages and the reviewed local
WebView plugin. SDK build transformers have been removed from the Flutter asset
pipeline: builds cannot replace the engine, metadata, icons or source commits.
Coin/seed assets in the SDK are pinned source inputs; current market/RPC services
remain ordinary runtime network services, not build-time fetches.

Canonical production build (does not launch the application):

```powershell
./tool/windows/build.ps1 -Mode Production -KdfFile 'C:\build-inputs\mm2_lccnext_8762.exe'
```

If the hash-verified artifact is already cached under `artifacts/kdf/windows/`,
the `-KdfFile` argument can be omitted. The cache is ignored by Git. The lockfile
is tracked. No KDF is stored in SDK platform `bin` directories.

For a disconnected build, pre-populate a Dart Pub cache with the exact locked
versions and a native dependency cache containing `packages/` (NuGet packages)
and `extracted/firebase_cpp_sdk_windows/` (Firebase C++ SDK 12.7.0):

```powershell
./tool/windows/build.ps1 -Mode Production -Offline -KdfFile 'C:\build-inputs\mm2_lccnext_8762.exe' -NativeDependencyCache 'C:\build-inputs\windows-native'
```

Only native SDK headers/libraries and package archives are consumed from this
cache. No previous application DLLs, AOT files or runner binaries are copied.
The same source also supports ordinary online native dependency acquisition.
A successful cache-assisted clean checkout does not prove all online download
endpoints remain available; GitHub Actions execution is verified separately.

Production output uses RPC 17883 and the dedicated production mutex/engine name.
Validation uses the isolated runner, RPC 17993, disposable profile and a trading
block. The two modes must not be mixed in the same distributed folder. Use separate clean checkouts for production and validation; the build refuses
to mix engine modes or rebuild an output containing a running process. Verify
each complete package manifest.

No code signing or installation is performed by the build. No auto-updater or
upstream Gleec release may replace this community distribution.
