# Contributing

Keep changes focused, explain the problem and resulting behavior, and include
the relevant offline tests. Do not claim native validation on an OS that has
not actually been tested.

Use Flutter 3.41.4 as pinned in `.fvmrc`. Preserve the resolved package lockfile,
local SDK changes, and the patched Windows WebView package. Do not replace the
local SDK with its upstream branch without reviewing the diff and regression
tests; RPC/SSE and Windows process protections depend on those changes.

Ordinary tests must not start real KDF instances or connect to financial
networks. Use mocked transports and explicit loopback fixtures. Real integration
tests require a separate profile, a distinct RPC port and explicit approval.

Do not include wallets, orders, private profiles, local build caches, dumps,
credentials or operator evidence in commits. Keep upstream license notices.
Before proposing the initial import, review the file inventory and the local
publication report. Verify the artifact contract and the vendored source snapshot:

```text
python -m unittest discover -s tool/windows -p "test_*.py"
python tool/windows/verify_sources.py
```

Native build and release gates are documented in
`docs/publication/READINESS.md`. No automatic release publication, trading or
wallet migration is part of the contribution process.
