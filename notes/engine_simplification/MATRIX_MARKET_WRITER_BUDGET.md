# Isolated Matrix Market writer prototype

Base: fff50517c9838481ff2a49bb1ebd8f5f20ead8dd. No edits to the frozen
qualification tree. This is a new bounded prototype, not a qualified final
candidate or a claim that Xenopus has passed with these changes.

Prospective budgets received before any tests or measurements: byte-identical
old-encoder output for supported ordinary cases; ordinary block temporaries
target <=32MiB within the existing 256MiB guard; no source-sized per-nonzero R
list/string carrier; two visitor passes (count/finite validation, emission)
independent of pack partition count. Range-edge checks can additionally inspect
the current bounded block; this is not exactly two scalar examinations. The
guard is never raised. Column blocks
are <=128 and conservatively admit 64 bytes/element plus fixed-buffer headroom;
very tall inputs use row blocks within one column to preserve entry order.

Deferred isolated measurement budgets (NOT RUN while coordinated qualification
runs): >=5x old writer at250k nonzeros, additional peak RSS<=128MiB, fixed small
100-nonzero overhead<=.05s. Preserve any future misses. No performance claim is
made from focused byte/error/lifecycle tests.

The bounded claim covers only ordinary base numeric/integer/logical matrices
and genuine general dgCMatrix/lgCMatrix/ngCMatrix inputs. The CSC writer traverses
existing @p/@i/@x slots directly, checking ordered rows and emitting batches of
<=8192 stored values (further reduced by the guard). It never invokes Matrix's
subscript dispatch or makes dense arrays proportional to sparse source height.
Base matrices use bounded blocks. Other Matrix classes (CSR, triplet, symmetric,
triangular, diagonal), exotic classes and coercions retain the historical
whole-object as.matrix/storage.mode fallback ONCE before the two base visitor
passes: this preparation is explicitly not bounded, and no repeated per-block
source conversion is claimed. Native emission retains the
existing 15-digit canonical numeric formatter and column-major decimal row/column
coordinates. Locale-sensitive and range-edge errors retain R encoding fallback.
Core-generated finite coordinate Matrix Market transport only; no claim about
arbitrary external Matrix Market parsing or broker startup is introduced.

Full-axis private grants reuse eligible input values under R copy-on-write,
without an explicit Matrix row subset. Nontrivial eligible CSC selection uses
one private slot projection: selected-row lookup metadata is sorted once, selected
source column indices are visited twice (count, then copy), and final CSC payload
slots are allocated once. Paired in-place heapsort restores requested row order
within each selected output column, without a source-height map, per-column sort
carrier or dense projection. Final selected-object storage is O(selectedNNZ),
which is explicitly still a whole selected primitive, not a lazy object. Lookup
metadata is O(selected axes); each copied value is visited once during projection.
Existing typed-axis identifier matching/manifest work and selected-object validity
checks are separate costs, not removed or declared universally bounded here.

Other Matrix classes are normalized once before writing and semantic identity
streaming; their historical nontrivial subsetting/coercion remains explicitly
outside the bounded claim. No repeated per-block full conversion is introduced.
This preserves prior values/identities without claiming every private grant
preparation or unsupported backend class is bounded.

If an exotic as.matrix method retains custom object/subscript behavior, the
historical whole encoder remains in use, explicitly unbounded, rather than
silently changing its scientific scalar dispatch into block dispatch. A focused
custom-subscript fixture checks this and the original private-grant selection.

Native projection reads source slots with INTEGER_ELT/REAL_ELT/LOGICAL_ELT,
not source DATAPTR access. A compact million-entry ALTREP slot fixture tests that
only2 selected payload entries are allocated as output. Arbitrary custom ALTREP
extensions and their R-level subset/coercion hooks, including virtual base-array
backings, remain unmeasured; no universal allocation bound for third-party hooks,
new rejection or silent backend-version gate is claimed. Materialized base arrays
and stock general CSC are the ordinary source-qualified paths here.

Sable HOLD f344298 supersedes the initial bcaf750 sparse bounds claim: Matrix1.7
subsetting hid whole-source conversions and source-dimension workspaces before
the as.matrix spy could observe them. That finding is retained, not erased by
the earlier three passing format/lifecycle tests below. Corrected slot traversal
requires new source review and targeted installed tests; no broad qualification
or performance acceptance follows from this prototype.

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

## Corrected slot/projection checkpoint

The corrected installed development gate is `matrix_market_projection_focused.log`
with numeric sidecar `matrix_market_projection_focused.exit`: exit0,5 tests passed,
0 skipped/failed. Installation evidence is `matrix_market_projection_install_v2`
(.log/.exit, exit0). The earlier corrected-four-test gate's resource reference
incorrectly interpreted a pattern Matrix's explicitly stored zero structure as
false; its retained failure was fixed by applying the frozen oracle to a small
Matrix with identical slots, not by changing the writer's pattern semantics.

The warm allocation/dispatch contract writes a10,000,000-row CSC with3 nonzeros,
and projects reordered rows/columns, under a31,457.28-byte forced-small test guard.
Largest recorded R allocation:2024 bytes; Matrix1ary/2ary subscript dispatches:0.
This is a focused allocation check, not process peak RSS or an elapsed benchmark.
8193 stored-entry fixtures cover native8192 batch splitting under the normal256MiB
guard and further subdivision under the forced-small guard, numeric/logical/
pattern semantics, exact frozen-encoder bytes and unchanged input metadata.

Source proof for independent review:

- `R/operation_pack_v3_transition.R:510`: CSC visitor uses only existing slots,
  <=8192-entry vector subsets and native append; base-only branch uses bounded
  matrix subsetting. There is no Matrix subset in the CSC visitor.
- `:609`: only base atomic matrices and genuine general CSC classes qualify.
  Other classes take one whole coercion before the visitor, not each block.
- `:620`: CSC selection sorts selected-axis lookup metadata once; native output
  is wrapped as the new selected primitive without Matrix subsetting.
- `:707`: exact full axes reuse original eligible values; reordered/subset CSC
  axes use the slot projector, while other classes retain the declared fallback.
- `src/matrix_slice_identity.c:277`: native projection validates vector types,
  lengths, bounds and row-map uniqueness; counts selected entries, allocates
  final slots, fills them and in-place sorts paired row/value slots. No original
  source-height workspace or per-column temporary sorting carrier is allocated.

These are source proof and focused installed results. Performance budgets above,
whole-workflow timing/RSS and corrected independent source review remain pending.
No full suite, performance job, frozen-tree edit or integration was performed.

## Final corrected review evidence

Installed canonical-runner focused gate `matrix_market_slot_canonical_focused`
(.log/.exit) ended exit0 with the literal accounting:

```
CONTRACT TEST SUMMARY files=1 discovered=5 executed=5 passed=5 skipped=0 failed=0 excluded=0 accounted=5
```

Exact command from the isolated worktree:

```sh
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/matrix_market_slot_canonical_focused.log /tmp/scwb-engine-simplification-forge-20261018/matrix_market_slot_canonical_focused.exit -- Rscript -e '.libPaths(c("/tmp/scwb-engine-simplification-forge-20261018/library_matrix_market_corrected",.libPaths()));library(scworkbench);source("inst/tests/contract_test_runner.R");inventory<-contract_test_discover("tests",files="test_engine_matrix_market_writer_contract.R",parent_env=globalenv());cat("Discovered ",length(inventory$tests)," focused tests\n",sep="");run<-contract_test_execute(inventory,baseline_bundle_dir=tempdir(),reporter=TRUE);contract_test_assert_success(run)'
```

Final runtime installation is `matrix_market_slot_freeze_install.log/.exit`
(exit0). The installed engine includes direct CSC slots, selected-object native
projection, ELT source access and conservative exotic dispatch preservation.
S3 test methods are explicitly registered/restored so the same oracle assertions
execute in canonical per-file environments, not just global-source probes.
No complete canonical suite or benchmark was run here.

Private logical/pattern runtime admission remains an EXISTING unsupported
boundary: frozen fff50517 and corrected code both reject
PYBENCH_INPUT_IDENTITY_MISMATCH after real Matrix Market reload changes boolean
canonical tokens to numeric tokens. Serialization bytes/projected IDs for these
kinds are preserved, but are NOT evidence of successful logical private lifecycle.
Numeric private round-trip admission is actually exercised and passes for complete
and reordered/subset sources. No dtype bridge, identity/protocol change or weakened
check was introduced. The independent frozen/corrected characterization commands:

```sh
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/private_dtype_frozen.log /tmp/scwb-engine-simplification-forge-20261018/private_dtype_frozen.exit -- Rscript /tmp/scwb-engine-simplification-forge-20261018/probe_private_matrix_dtype_roundtrip.R /tmp/scwb-engine-simplification-forge-20261018/library_frozen frozen
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/private_dtype_corrected.log /tmp/scwb-engine-simplification-forge-20261018/private_dtype_corrected.exit -- Rscript /tmp/scwb-engine-simplification-forge-20261018/probe_private_matrix_dtype_roundtrip.R /tmp/scwb-engine-simplification-forge-20261018/library_matrix_market_corrected corrected
```

Both characterization sidecars are0 because the numeric success AND pre-existing
logical/pattern rejection were asserted, not counted as three admitted backends.
Numeric projected/reloaded SHA:
`d4e6af5d47c61402f1c03068037fb99821b6589d3f63fced564bc8ff48eb3322`.
Logical/pattern projected SHA:
`13fa30afc655a78aa3de63e95052d8efb90a1b6d690c378724bbc3ea97515d1c`;
real-MM reloaded SHA:
`0ccf01135ba7becc76a8b8652eb50cf4e43d2907cd17ebe62e0bb35fc7d9bd55`.

## CSC capacity review correction

Sable's subsequent capacity HOLD found a real supported-object compatibility
defect: stock Matrix 1.7 permits unused trailing i/x slot capacity. The writer
and projector now require last(p)<=length(i), and numeric/logical x capacity
exactly equals i capacity. Only active entries are traversed and validated;
unused NA, negative-index and nonfinite tails are not scientific payload and
remain untouched. The three tiny valid dgC/lgC/ngC fixtures check validObject,
old/new emitted bytes, reordered projection, projected identity, active
nonfinite rejection and serialized source nonmutation. This follows the
version-matched Matrix CsparseMatrix_validate and xgCMatrix_validate, not a
relaxation of active pointer/index or payload validation.

The native selected-column guard permits equality to INT_MAX because its
p-array allocation and iteration use R_xlen_t; selected indices remain ordinary
integer slots. This is not a new claim of executable INT_MAX-wide Matrix
support or a repair of Matrix's own practical long-vector limitations.

`matrix_market_capacity_install.log/.exit` ended0. The first six-test run
`matrix_market_capacity_focused.log/.exit` ended1 solely because the new first
alphabetical fixture constructed an S4 class before loading Matrix. Its explicit
loadNamespace correction is fixture-only, and the failed raw log is retained.
The final installed run `matrix_market_capacity_final_focused.log/.exit` ended0:

```
CONTRACT TEST SUMMARY files=1 discovered=6 executed=6 passed=6 skipped=0 failed=0 excluded=0 accounted=6
```

No performance measurement, full suite or frozen qualification-tree edit was
performed by this isolated prototype. Independent final source review remains
required before integration.
