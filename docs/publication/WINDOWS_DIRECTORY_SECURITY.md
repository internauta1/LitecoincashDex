# Windows directory security after R1

Base R1: `f6b1b10def02ad4f7d6ea58c101d05acc02bdd9a`.

The initial windows-2022 CI run failed in the private-profile fixture and KDF
temporary-directory test. Its logs did not retain canonical paths or the child
PowerShell exit code, so the exact historical values cannot be recovered.

Two conditions were reproduced with marked synthetic directories on Windows:

- A TEMP path containing an NTFS 8.3 alias makes the private-profile positive
  fixture differ from `resolveSymbolicLinks()`, even though the directory exists
  and is not a link. The security guard correctly rejects the supplied alias.
  The fixture now resolves its newly created directory before opening it. The
  application guard remains unchanged; raw aliases, junctions and redirected
  child directories are still rejected.
- An elevated token creates ordinary new directories with Administrators as
  owner. The original KDF guard requires the current user's SID and returns 3
  before changing that directory's ACL. New KDF directories now receive the
  explicit user owner and protected user/SYSTEM DACL at creation. Existing
  directories retain the same owner check; foreign owners are never adopted.

The final DACL must still be protected from inheritance, contain exactly two
non-inherited FullControl Allow rules for the current user and SYSTEM, and have
the current user as owner. A user-owned directory with weak inherited rules can
be restricted before use, as in R1; it is never returned with an unsafe DACL.
Foreign-owned and redirected directories remain refused.

The implementation checks canonical cache paths before creation and the leaf
again after protection. These metadata checks are not a claim of a general
defence against every hostile same-user filesystem race.

Tests report only boolean path/privilege/owner properties, ACL counts, hashes
and fixed failure categories. They never print actual SIDs, canonical profile
paths or shell output. `WindowsKdfTempProtectionException` retains the exit code
and category without copying stdout/stderr, which can contain local paths.

Local verification includes standard and elevated execution, a synthetic short
TEMP alias, a foreign-owned existing directory left unchanged, junctions and
protection of a new and existing directory. An elevated synthetic diagnostic
also verified symbolic-link rejection. No wallet, KDF or funds were used.

The original run used Windows Server 2022 build 20348, image
windows-2022/20261101.353.1. Local reproduction used Windows build 19045. A new
run on windows-2022 is still needed after authorization to push this correction.
The new test metadata makes its actual alias/token/owner conditions observable;
local reproduction is not a claim that the new remote CI has already passed.
