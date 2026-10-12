The original test treated dirname(find.package("scworkbench")) as an installed
library. Full525 had previously hot-loaded the source package; that lookup
therefore returned the worktree's parent. Its child could not find scworkbench.

The569 unchanged diagnostic used exact installed566 in the parent and a local
test-environment find.package stimulus that returned the canonical worktree.
The test itself was unchanged at launch; no parent namespace was hot-loaded.
It reproduced the exact missing-package child error and exited1. The original
tracked test source is preserved in569_runtime_fingerprint_unchanged_test_snapshot.R.
The unchanged diagnostic driver points at the original tracked source path as
it did at launch; replay must source the saved snapshot to repeat the old test.

The correction affects only child bootstrap in the owned test. It first uses
SCWB_CONTRACT_INSTALLED_LIBRARY when provided. Otherwise it detects a genuine
installed Meta/package.rds; a source-mode parent instead supplies canonical
SCWORKBENCH_SOURCE_ROOT or repository cwd to a source-only isolated child.
Each child verifies its selected target. All original unloaded-version,
missing/unreadable metadata, namespace-stability, marker-not-executed and
intentional loadability-rejection assertions remain intact.

The corrected focus repeats the same source-lookup stimulus with explicit566
installed child bootstrap. All three original metadata tests passed, exit0.
The parent namespace and registry identities stayed unchanged. Source-child
fallback received syntax/static checking, not additional runtime qualification.
Raw logs, exits, time records and both diagnostic drivers are in the569 family.
No production source, authority, runtime or full-suite state was changed;
no commit was made. Ownership assertion capture needs a later loadability-row
refresh after root review.
