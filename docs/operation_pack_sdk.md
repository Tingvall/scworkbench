# Operation Pack SDK

The author workflow is **declare typed inputs and outputs, request readers,
compute, emit primitives**. Core owns authentication, alignment, storage,
provenance and atomic publication. This SDK is an authoring facade over the
existing ABI, not another executor, schema language or authority.

Start with the [system overview](../inst/onboarding/SYSTEM_OVERVIEW.md) for
activation, primitive exchange, centralized slicing, and backend/trust limits.
No official pack or standard-profile modification is needed to author a pack.

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

## From Reference to Your Method

1. Run the installed tutorial unchanged and inspect its generated package.
2. Choose supported primitive profiles and grants from the capability catalog.
3. Update the manifest and runner together: typed input names, parameter schema
   and defaults, dependencies, output names/profiles, retention, and closure.
4. Replace the synthetic computation, retaining the issued readers and writers.
5. Add a scientific oracle and rejection, schedule, publication, and recipient
   cases. Fake-reader tests do not replace real registered-dispatch tests.
6. Run static, trusted installed, and contract checks; then run `R CMD check`.
7. Explicitly activate the installed pack and inspect its qualified interface.

The authoritative installed guide contains manifest, namespace, callback,
model-tree, family/axis, and publication recipes. Its generated companion
references enumerate supported policies; do not invent fields from examples
in an unrelated pack. A new primitive or missing generic authority requires an
engine capability decision, not a pack-specific core exception.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Operation missing after installation | Explicit activation in this process and its qualified catalog name |
| `OPERATION_PACK_REQUIRED` | Producing pack absent/incompatible; inspection and replay are different tasks |
| Unsupported grant despite valid JSON | Backend runtime support in the capability catalog |
| Output dimension/order rejection | Declared axis/cardinality policy and any required seal before writes |
| Reader coverage rejection | Exact declared partition discipline, including final partial partition |
| No derived parameters in provenance | Manifest-owned retained parameters, not arbitrary runner return fields |
| Scaffold publication unsupported | Linux libc/kernel/filesystem support; R source installation needs a C toolchain |
| Checks pass but no lasting logs | Save diagnostics and logs before the temporary check workspace disappears |

## Release Checklist

- Package metadata, namespace, entry point, version and manifest agree.
- Source/dependency identities and supported runtime profiles are recorded.
- Method-specific comparison policies cover all required terminals/parameters.
- Invalid inputs and faults reject without durable residue; retry is tested.
- Promoted output closure survives finalize, relocate, reopen and inspection.
- Static, installed, contract and package-check results retain counts and exits;
  skips, warnings, notes and reused evidence are explicit.
- Trust, model serialization, memory, hardware and backend limitations are stated.
- Independent conformance review precedes distribution; profile inclusion is a
  separate decision, not an SDK side effect.
