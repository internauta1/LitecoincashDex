# Vendored SDK

Source copied from the locally validated community worktree on 2026-11-10.
Upstream: https://github.com/GLEECBTC/komodo-defi-sdk-flutter

This is modified source, not an upstream Git submodule. Original parent commit is not available;
no commit lineage is asserted. Preserve package LICENSE files. A source hash manifest is supplied.
Local changes include Windows 8762 supervision/TCP/SSE, activation and wallet reliability fixes.

The post-R1 Windows directory correction supplies an explicit current-user owner
and protected DACL when creating a new KDF temporary directory. It does not take
ownership of an existing foreign-owned directory or relax TCP/reparse checks.
Security failures expose only a fixed category and process exit code. The SDK
source manifest and its provenance hash are updated with this source change.
