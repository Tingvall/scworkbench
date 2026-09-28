# Motif registry and chromVAR ownership

scworkbench owns peak-matrix, genome-provider, motif-library, and cached
motif-match registries. Their public getters and ingestion functions remain in
core. The chromVAR method is supplied by the separate `scwbATAC` operation
pack as `scwbatac::chromvar`; core no longer registers the unqualified method
or exports its runner.

Activate the installed pack before running the method. Its ABI-v3 manifest
requests bounded authenticated genomic and motif reads, a matrix-selected
provider preflight, and one ordered runtime-key seal for the two complete
cell-major deviation families plus `motif_summary`. The method materializes
the selected sparse matrix before chromVAR computation; typed chunk reads do
not make it a streaming algorithm. A recipient can inspect promoted artifacts
and provenance without activating the pack.

Historical bundles keep their original operation identities. Newly executed
pack runs use `scwbatac::chromvar` and do not claim byte-identical payloads or
deterministic reruns across dependency versions.

Since bundle schema v10, promoted `cell_vector_family` numeric values support
finite numbers and `NA_real_` only. Their key/cell order, metadata, and
content identity round-trip without changing historical finite-valued rows.
Opening a v9 bundle read-only with a v10 engine reports an upgrade requirement
without mutation. Open a copy writable to perform the transactional v10
migration; the normal sibling SQLite backup is retained.
