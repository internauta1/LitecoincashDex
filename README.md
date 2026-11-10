# LitecoinCash DEX Next

Independent community desktop wallet and atomic-swap interface for Litecoin Cash,
derived from Gleec Wallet / Komodo Wallet and the Komodo DeFi SDK.

Project: https://github.com/internauta1/LitecoincashDex

Community: https://litecoincash.com.br/

## Support status

| Platform | Status |
| --- | --- |
| Windows x64 | Initial publication candidate; clean-checkout build verification and disposable-wallet validation required before release |
| Linux | Source retained for a future native port; not supported by this Windows 8762 release |
| macOS | Source retained for a future native port; not supported by this Windows 8762 release |

No signed installer or stable public release is claimed. Windows source builds
are unsigned unless the maintainer adds signing separately. This repository is
an independent community distribution, not an upstream company release.

## Features

Wallet, Swap (Order book and Best Orders), own-order orange markers, NFTs and
Settings. No Banxa or dedicated Buy/Sell LCC page. NFT lists show collectibles
owned by the connected wallet, not a public marketplace.

## Windows build

Requirements: Windows x64, Visual Studio 2022 with Desktop development with C++,
CMake/Ninja as installed with the toolchain, Git, Python 3.12 and Flutter **3.41.4**.

Use the reviewed source and its committed lockfile; SDK sources are vendored.
Do not initialize an upstream SDK submodule over this directory.

```powershell
git clone https://github.com/internauta1/LitecoincashDex.git
Set-Location LitecoincashDex
# Supply the exact approved KDF artifact, not another wallet or data directory.
./tool/windows/build.ps1 -KdfFile 'C:\build-inputs\mm2_lccnext_8762.exe'
```

The script resolves dependencies with `--enforce-lockfile`, verifies the engine
hash, compiles Windows and verifies the packaged engine. It never launches the
wallet or KDF. Standard dependency downloads may be needed on a fresh machine.
For offline native-cache builds see [BUILD_WINDOWS.md](docs/BUILD_WINDOWS.md).

Output: `build/windows/x64/runner/Release/`. Keep the whole folder together.
A standalone EXE is not a complete Flutter application.

The build defaults to **netid 8762**, loopback RPC **17883**, the original verified
legacy KDF and the independent community policy. An explicit upstream-network or
policy build is rejected before application storage is opened. No fees, wallet
identities or order rules are changed. Do not change these options to bypass a
failed build or connect the application to 6133.

The engine itself is not committed. Its exact SHA-256 is in
[windows.lock.json](artifacts/kdf/windows.lock.json). Public binary/source release
URLs are intentionally pending authorization. A complete clean build requires
provisioning that exact artifact. No automatic alternative KDF is downloaded.

## Verification

```powershell
python -m unittest discover -s tool/windows -p 'test_*.py'
flutter pub get --enforce-lockfile
flutter test --no-pub test/community_build_test.dart
```

The Windows workflow runs the reviewed offline regression suite using mocked
RPC and a loopback SSE fixture. No real KDF is started by ordinary CI. Optional
manual workflow builds accept a project release URL and verify the pinned hash;
they upload temporary CI artifacts, not GitHub releases. See
[validation](docs/VALIDATION.md) before running a disposable-wallet candidate.

## Source and licenses

[LICENSE](LICENSE) contains the application GPLv3 license. SDK package notices
and the Apache-2.0 WebView license are retained. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), [VENDORED_SDK.md](VENDORED_SDK.md)
and [KDF provenance](docs/KDF_PROVENANCE.md). The KDF includes its own LEGAL
notices and restrictions; it is not described as licensed solely by the GUI GPL.

Never upload wallets, seeds, private profiles, logs, databases, build caches,
memory dumps or signing keys. See [SECURITY.md](SECURITY.md) and
[CONTRIBUTING.md](CONTRIBUTING.md).
