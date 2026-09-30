# Operation Pack SDK

The author workflow is **declare typed inputs and outputs, request readers,
compute, emit primitives**. Core owns authentication, alignment, storage,
provenance and atomic publication. This SDK is an authoring facade over the
existing ABI, not another executor, schema language or authority.

The SDK is installed with scworkbench. Read the installed
`sdk/operation-packs/GUIDE.md`, `CAPABILITIES.md`, `capabilities.json`,
`callbacks.json` and `interface.json`. They are available through `system.file`
and `wb_operation_pack_capabilities()`. Python support is classified per policy
by the bounded PyBench companion, not inferred from shared schemas.

```r
library(scworkbench)
project <- wb_operation_pack_scaffold("/existing/parent/My Pack",
  package = "myMatrixPack", namespace = "mymatrix", author = "Your Name",
  email = "you@example.org")
wb_operation_pack_check(project$path, "static")
wb_operation_pack_check(project$path, "contract", trusted = TRUE)
```

For the executable lifecycle, from any working directory:

```r
system2(file.path(R.home("bin"), "Rscript"), c("--vanilla",
  shQuote(system.file("sdk", "operation-packs", "scripts", "tutorial.R",
    package = "scworkbench")), shQuote("/existing/parent/new-tutorial")))
```

Static checking parses metadata/manifests without loading the pack. Trusted
installed checking executes installation/entry points in separate processes.
Contract checking executes author tests and reports discovered/executed/passed/
skipped/failed cases, reasons, runtime identities, logs and numeric exits.
Any skipped or missing required case leaves that tier unqualified. A successful
SDK check is not package-check Status OK, security certification, biological
validation, portability proof or GPU/large-data validation.

The reference emits finite continuous cell sums and a per-partition summary.
Both terminal primitives are in one promotion closure. Its real-reader tests
exercise chunk sizes 1, 2 and 3, selected cells, a final partial partition,
rollback, retry, relocation and fresh pack-free recipient inspection. Core
still enforces source identity, dimensions, row order and receipts regardless
of any pack assertion. The synthetic pack is never ambiently activated or
added to the standard profile; seven official packs remain unchanged.
