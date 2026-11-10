# Controlled visual validation

Do not launch production output on a development PC with an existing wallet or
KDF. A production package uses normal application storage and RPC 17883; it must
not be used as a disposable test launcher.

For the current operator environment, build a distinct candidate:

```powershell
./tool/windows/build.ps1 -Mode Validation -KdfFile 'C:\build-inputs\mm2_lccnext_8762.exe'
```

The validation target is `main_isolated.dart`, RPC 17993, netid 8762, wallet-only
mode with trading blocked. Its existing audited scope requires the separately
marked disposable profile under the operator workspace. This hardcoded local
scope intentionally fails closed on other PCs; it is not a public-user launcher.
Do not replace that scope with a private/production wallet directory. A portable
validation harness is a separate future change and needs its own security tests.

Before an authorized real-network trial: verify all package hashes, the KDF
hash, free RPC 17993, no duplicate experimental process, loopback ownership and
protected classic/main process identities. Redirect appdata/home/temp/logs and
all SDK/path-provider storage to the disposable profile. Never read private
profiles or copy them into a candidate.

Validate startup/prices, disposable login, 30–60 minutes of session stability,
three voluntary logout/login cycles, coin activation and receive-address display,
Best Orders and own-order markers, NFTs, real SSE heartbeat and normal close.
Use only no-fund wallets and read-only market operations. Monitor Windows GUI/KDF
crash events and process/port ownership. Stop and investigate an incident; never
hide it or kill a process without establishing ownership.

No network trial or wallet launch is part of source/build preparation. A visual
approval and its actual runtime evidence remain required before publication.
