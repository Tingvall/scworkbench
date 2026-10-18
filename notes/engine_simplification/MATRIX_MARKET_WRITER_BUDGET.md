# Isolated Matrix Market writer prototype

Base: fff50517c9838481ff2a49bb1ebd8f5f20ead8dd. No edits to the frozen
qualification tree. This is a new bounded prototype, not a qualified final
candidate or a claim that Xenopus has passed with these changes.

Prospective budgets received before any tests or measurements: byte-identical
old-encoder output for supported ordinary cases; ordinary block temporaries
target <=32MiB within the existing 256MiB guard; no source-sized per-nonzero R
list/string carrier; exactly two value passes (count/finite validation, emission)
independent of pack partition count. The guard is never raised. Column blocks
are <=128 and conservatively admit 64 bytes/element plus fixed-buffer headroom;
very tall inputs use row blocks within one column to preserve entry order.

Deferred isolated measurement budgets (NOT RUN while coordinated qualification
runs): >=5x old writer at250k nonzeros, additional peak RSS<=128MiB, fixed small
100-nonzero overhead<=.05s. Preserve any future misses. No performance claim is
made from focused byte/error/lifecycle tests.

Ordinary numeric/integer/logical matrices and Matrix-owned numeric/logical/pattern
classes preserve sparse projections until each bounded dense block is needed.
Exotic coercions retain the historical whole-object as.matrix/storage.mode
fallback: their startup is not claimed bounded. Native emission retains the
existing 15-digit canonical numeric formatter and column-major decimal row/column
coordinates. Locale-sensitive and range-edge errors retain R encoding fallback.
Core-generated finite coordinate Matrix Market transport only; no claim about
arbitrary external Matrix Market parsing or broker startup is introduced.

## Focused prototype evidence

Only three new focused contracts were run; no suite or performance probe.
`matrix_market_prototype_install.log/.exit` records isolated installation success
(exit0); `matrix_market_prototype_installed_focused.log/.exit` records3 passed,
0 skipped,0 failed (exit0). Evidence is retained under the engine-simplification
task's temporary evidence directory, not in the frozen qualification tree.

Installed command, from this prototype worktree:

```sh
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/matrix_market_prototype_installed_focused.log /tmp/scwb-engine-simplification-forge-20261018/matrix_market_prototype_installed_focused.exit -- Rscript -e '.libPaths(c("/tmp/scwb-engine-simplification-forge-20261018/library_matrix_market_prototype",.libPaths()));library(scworkbench);source("tests/test_engine_matrix_market_writer_contract.R");failed<-FALSE;for(n in ls(pattern="^test_engine_matrix_market_")){cat("RUN ",n,"\n",sep="");result<-tryCatch(get(n)(),error=identity);if(inherits(result,"error")){cat("FAIL ",n,": ",conditionMessage(result),"\n",sep="");failed<-TRUE}else cat("PASS ",n,"\n",sep="")};if(failed)quit(status=1)'
```

The byte contract independently uses the unchanged frozen fff50517 writer body.
It covers decimal/scientific rounding boundaries across exponents-307..308,
signed zero, finite extremes, fractions, zero axes, integer/logical values,
column/row-block boundaries, Matrix CSC/CSR/triplet/pattern/diagonal/triangular/
symmetric classes and exotic historical coercion. Instrumented ordinary reads
sum to exactly twice the input element count, with each block below the admitted
size. Failure cases preserve old typed error class/message, finite-before-range
precedence, original destination bytes, pending cleanup and successful retry.
Private grants retain Matrix class until writing, byte-identical source transport
and identical projected identities for numeric/logical dense and sparse inputs.

Earlier source-patched development evidence remains retained: first byte test
incorrectly classified9.99999999999999e-308 as an accepted value; the frozen
oracle rejected it. It now belongs to the exact typed-range-error regression.
No encoder behavior or accepted exponent range changed to satisfy the test.
