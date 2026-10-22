# Stabilization checks, 2026-10-23

This pass starts from main `04add51` and the equivalent local UUID ordering
fix `d24a596`. A normal merge preserves both histories. It does not truncate
main or import the unfinished polls or registration-invitation worktrees.

## Changes verified

- Migration 1024 adds typed suspension lookups and participation functions.
  It fixes comparisons between PostgreSQL timestamp text and an ISO-8601
  clock, and finds an older active suspension beyond ten newer expired rows.
  SQL and ORM tests cover UTC, Europe/Rome, Pacific/Honolulu and the exact
  end. The previous entry points remain installed for the preceding release.
- Suspension revocation preserves accounts that are now deleted or pending,
  and leaves a member suspended while another active suspension remains.
  Both paths test revocation and retry. Creating a suspension for a deleted
  account is refused.
- Password hashing accepts exact Unicode character sequences and retains
  existing hashes. New standard Argon2id PHC strings use a public salt
  encoding marker plus 128 random bits; old 16-byte salts retain their
  Latin-1 encoding. A candidate uses one encoding, with no fallback that
  could match a different password. CLI owner creation decodes UTF-8 stdin
  before hashing. HTTP registration and sign-in, old hashes and ambiguous
  byte sequences have regression coverage. Cost parameters are unchanged:
  Argon2id t=3, m=32768 KiB, p=1, 32-byte tag.
- TOTP replay tests generate the code from the step actually consumed,
  rather than from a wall clock that may have crossed into a fresh window.
  The production anti-replay implementation is unchanged.

The [upgrade guide](../ops/upgrade.md#suspension-timestamp-and-unicode-password-fixes)
includes the application rollback constraint for new Unicode passwords.
The [runtime role guide](../ops/sql-api-role.md) explains draining workers
and reprovisioning grants for the two new function signatures. A PostgreSQL
restart is unnecessary. The 1.0 baseline files are unchanged.

## Local verification

Host: Apple M4, 10 logical CPUs, 16 GiB RAM, macOS 27.0.1, PostgreSQL 18.6
(Homebrew, aarch64), Perl 5.44.0. PostgreSQL ran in an independent temporary
cluster over a private Unix socket, with its own databases. Existing
sessions' clusters and development servers were not changed.

| Check | Result |
| --- | --- |
| Unit tier, `script/gpforum-carton exec prove -l -j 4 t` | PASS: 458 files, 17,381 tests |
| PostgreSQL tier, `prove -l -j 3 -It/lib -r t/integration` through the project wrapper | PASS: 128 files, 11,633 tests |
| Explicit disposable-cluster tuning test, `GPFORUM_POSTGRES_CONTROLLED_TEST=1` | PASS: 1 file, 24 tests; apply, pending restart, privilege refusal, idempotence and restore |
| Core-Perl performance harness contracts, `prove -I script/lib -I t/lib -lr t/performance` | PASS: 11 files, 289 tests |
| Browser tests, `node --test t/js/*.test.cjs` | PASS: 14 tests |
| ASVS record and documentation consistency | PASS: 2 files, 11 tests |
| Perl syntax | PASS |
| Perl::Critic, unchanged brutal profile and empty baseline | PASS: 0 baseline violations, 0 new violations |
| Perl formatting of the staged source snapshot, architecture boundaries, ADR index, whitespace | PASS |

The first unit run caught a dependency scanner false positive in a POD line
beginning with “use UTF-8”. Rewording that line fixed it; the final complete
unit run above passed. Perl::Critic findings in the added tests were fixed
in code, without changing its profile or empty violation baseline. The final
formatting check uses an exported snapshot of the staged files, excluding
concurrent uncommitted renderer and interface edits from another session.

The PostgreSQL tier has optional external-service and drill skips where
those services or capabilities are absent. The controlled-cluster test was
run explicitly after the tier so that its reloads could not affect tests
running concurrently. Five existing attachment TODO assertions passed;
this pass does not relabel those separate findings.

## CI and performance evidence

On upstream `04add51`, [CI run 39861218841](https://github.com/gpicchiarelli/GPForum/actions/runs/39861218841)
passed lint and unit tests and failed the PostgreSQL tier in the TOTP replay
test. The UUID change fixed the earlier same-second held-post ordering
failure; it was not the remaining failure in that run.

The same revision's [performance run 39861218869](https://github.com/gpicchiarelli/GPForum/actions/runs/39861218869)
failed its 5,000-connection `/health/live` capacity gate in all three
repetitions, reporting about 1,973–2,159 requests/second. These are measurements
of the earlier CI revision and shared runner, not of this change. The gate
and its thresholds are unchanged. This pass makes no throughput or latency
improvement claim, and the local functional checks above are not an A/B
performance benchmark. CI must collect comparable evidence on the new
revision before any such claim.

## Still open

- A timed suspension's account status remains suspended until revocation;
  correcting its timestamp lookup does not implement automatic expiry.
- Creating and revoking suspensions still need serialization between
  concurrent transactions; the state guards do not claim to solve that race.
- Polls, invitation/manual-registration workflows and following members are
  not completed by this stabilization change. Uncommitted work in other
  worktrees is preserved.
- The [ASVS record](../security/asvs-5.0.md) now records 112 met, 98 not met
  and 36 not applicable requirements. This closes three listed requirements
  with regression evidence; GPForum still claims no ASVS level.
