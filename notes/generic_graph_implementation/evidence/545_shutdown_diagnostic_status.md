545 isolated diagnostic stopped at shutdown request. The only launched worker,
exec session 83741, had already exited with status 1 before the stop check.
Its OS PID was not captured. No pinned-mode diagnostic was launched. Process
inspection found no matching diagnostic worker; no children remain to stop.

Raw log: 545_docs_sdk_v2_original.log. Final log timestamp:
2026-10-12 14:34:38.460806949 +0200; 2020 bytes. No dedicated elapsed-time
measurement was recorded. Initial tool yield measured 1.001895 seconds and
is not the total runtime.

Observed original installed namespace path was
/tmp/scwb-graph-final-valid-522.hxhra5_g/library/scworkbench. SDK catalog passed
before documentation generation. The unchanged documentation test passed,
but replaced namespace path with the worktree, changed namespace/registry
identity, and made base::system.file("sdk", "operation-packs",
"capabilities.json", package="scworkbench") return an empty string.

The subsequent SDK catalog still passed in this isolated process, so this
diagnostic does not reproduce the full-suite SDK error exactly. The v2 feature
registry case failed earlier with GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE:
RSQLite native byte API was not initialized. The script then exited 1 because
its predicted SDK failure did not occur. Preserve that mismatch honestly.

Confirmed finding is mid-suite installed-core namespace replacement, rather
than an independently reproduced identical downstream failure. No tracked
production/test edits or changes to live suite 525 were made. Proposed future
test isolation: run the unchanged documentation test in a dedicated child,
or use a copied diagnostic generator with the load_all call replaced by an
exact installed-namespace-path assertion. Verify identical generated text and
run subsequent unchanged SDK/v2 cases in the intact installed parent. Neither
alternative was launched before shutdown.
