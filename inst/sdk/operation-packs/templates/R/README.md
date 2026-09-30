# @PACKAGE@: an explicit ABI-v3 operation pack

Declare typed inputs and outputs, request readers, compute, emit primitives.
Installation and namespace loading are inert. Explicit validation/load is a
trust decision: checksum authentication is not a code sandbox.

From an R session with scworkbench installed:

```r
wb_operation_pack_check("/path/to/this/project", "static")
wb_operation_pack_check("/path/to/this/project", "contract", trusted = TRUE)
```

The second command installs locally without downloads and runs all named tests
through public session dispatch. It reports actual counts and separate command
exits. It is not an R CMD check or scientific endorsement. Change the maintainer
metadata before distribution. Inspect `inst/scworkbench/operation-pack.json`
and `R/matrix_cell_sum.R` together when changing declarations/calculation.

The reference uses nonlexicographic IDs, a selected cell axis, a zero column,
final partial partitions, two terminals and one complete promotion closure.
NA, NaN, infinities and numeric overflow reject. Matrix reads are bounded by the
issued chunk grant; accumulated output memory is not bounded. A summary's rows
and per-chunk sums intentionally depend on chunk size, while scientific cell
sums do not. Run-ID/allocation-ID/receipt identities are not scientific sums.

Installed SDK assets:

```r
system.file("sdk", "operation-packs", "GUIDE.md", package = "scworkbench")
wb_operation_pack_capabilities()
```

No pack runner may use bundle SQL, committed paths, internal core functions,
custom receipt hashes or recursive publication. Core authenticates, aligns,
stages, checks receipts and publishes atomically. Save no granted callbacks or
private model paths outside their invocation. Use separate processes for
conflicting versions. Missing packs reject new execution but do not prevent
inspection of retained promoted outputs. Identity-bound replay additionally
requires the original compatible pack/environment, source and parameters.
