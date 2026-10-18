# Additional private-stream resource contracts

Added only `tests/test_engine_private_stream_resource_contract.R` and this note.
No runtime, existing test, pack, scientific or frozen-worktree edits by helper;
no commits of coordinator changes. This is development evidence from source
copies over the immutable `library_frozen` namespace, not installed final-pin
qualification or a performance measurement.

Five new contracts extend, rather than weaken, the existing eleven broker
contracts:

1. Forced spill with `Matrix::readMM` traced to stop if called; 8/32 partitions
   independently retain exactly one source-byte/axis admission and one complete
   projection check. Literal newline/CR axis IDs survive via authenticated
   external axes, not physical BPCells line names. Signed/zero/15-digit values
   match the existing transport representation exactly; all-zero nonempty
   matrices import/read successfully. Empty control selections remain rejected.
2. Header-only bad NNZ/dimension/int-limit cases reject before BPCells native
   importer body. Importer is spy-stopped, never fed unsafe invalid coordinates.
   Byte seals are recomputed only to reach header admission. Includes NNZ
   1,025 >16*64, over-INTMAX NNZ/dimensions, negative/fractional NNZ and axis
   mismatch; all seven report native import count zero.
3. Checksum failure before exposure; live axis/private-payload changes retire
   reader and remove spill; distinct cached plus two spilled grants share one
   account, refund only their own credit and leave no retained spill/credit.
4. Actual graph scope across two SQLite connections lowers working/token policy,
   preserves nonzero session-copy reservation, restores cache/temp/policy/copy
   state on success and injected error, leaves total_changes unchanged, and
   rejects exhausted memory/token allowance with no new scratch residue.
5. Actual broker main consumes missing/zero/negative/fractional/huge copy-count
   environment values. Missing values measure a real staged copy or reserve zero
   without a source copy; invalid values reject; staged zero rejects; valid
   transported counts are retained; DB growth beyond a stale transported count
   rejects before observations. Broker connections close on all covered paths.

The main-loop environment test stubs only an empty graph cursor (routing/resource
test, not graph source-authority proof). It invokes actual graph policy helpers.
It does not launch Python or prove processx child-env propagation; the parent
producer at `R/operation_pack_python_v3.R` must be covered by final installed
composite qualification. No direct scientific fitting or extra execution
authority is introduced by these fixtures.

## Existing decimal contract

`R/operation_packs.R::.wb_operation_pack_number_token` uses formatC digits=15;
the private Matrix Market writer already emits those tokens. A source R `pi`
therefore need not reload with its original binary64 bits. The new test computes
that independent public formatC preimage and requires exact transported values
and unchanged existing canonical identity. It does not substitute a loose
tolerance or silently claim full-precision decimal transport.

## Development results and retained failures

All logs/atomic numeric sidecars are under
`/tmp/scwb-engine-simplification-forge-20261018/`:

- `private_resource_development1`: exit 1 after forced-spill and two-connection
  restoration PASS. The first header assertion incorrectly searched the error
  message for an error code which is stored separately in `error$code`. Corrected
  to exact code comparison; original failure retained. This is a harness error,
  not evidence that an unsafe native import ran. A static NNZ-product guard gap
  was independently reported to coordinator and repaired by coordinator before
  the next source reload.
- `private_resource_development2`: exit 0; header, main environment and
  tamper/aggregate contracts passed: `PRIVATE_RESOURCE_REMAINING discovered=3
  executed=3 passed=3 skipped=0 failed=0`. All seven bad headers logged imports=0.
- `private_resource_restore_development3`: exit 0 after strengthening restoration
  with scratch-inventory/SQLite total_changes assertions;
  `PRIVATE_GRAPH_RESTORE_ZERO_RESIDUE_PASS`.

Thus five added contracts have development passes across the retained scoped
runs; this is not one frozen-candidate five-test pass. Source continued changing
under coordinator ownership. Final installed qualification must discover and
run all five on its exact installed namespace, with original eleven retained.
No install, scientific benchmark, full suite or performance budget claim here.

## Source anchors

- `R/operation_pack_private_matrix_stream.R`: private_source_info,
  private_projection_assert, private_stream_open: preimport header guard,
  retained/shared credit, physical slack, omitted BPCells names and cleanup.
- `R/operation_pack_typed_slice_broker.R`: broker_graph_reservation and
  broker_main: actual graph scope and session-copy environment consumption.
- `R/operation_pack_python_v3.R`: parent broker_env transport producer.
- `R/graph_storage.R`: aggregate_connection_budget/scoped_connection_budget.
- `R/session_staging.R`: session_graph_copy_bytes fallback accounting.

Source development runner used `Rscript -e` to load public scworkbench, create
one environment parented by its namespace, sys.source v3_transition,
private_matrix_stream, typed_slice_broker and this new test file, then call only
named additional contracts. No live/shared namespace or installation was edited.
Parse-only check returned `PRIVATE_RESOURCE_PARSE_ONLY_OK`; `git diff --check`
returned 0. The newly added file is untracked for coordinator review/commit.

## Axis preadmission extension (prepared after the first five)

Appended only `test_engine_private_axis_preadmission_contract`. Reviewed current
dirty broker source: `.wb_operation_pack_v3_broker_axis_admission` estimates
count/file carriers before decoding; `.wb_operation_pack_v3_broker_axis_ids`
uses an optional exact `maximum_bytes` cap, with a fresh stat before JSON;
broker_main installs graph policy, charges aggregate admitted axes, then decodes
and only then constructs readers/cursors.

The new contract spies specifically on axis `jsonlite::read_json` calls:
ordinary valid IDs and an exact passed cap are unchanged; huge descriptor count
against a tiny file rejects before decode; missing/malformed/count-domain
metadata rejects before decode; a small count mismatch decodes then rejects
without returning IDs; one-byte file growth after pre-estimate exceeds the
exact cap and rejects before decode. An actual main-loop case has four axes
whose metadata estimates are each individually below the graph memory allowance
but exceed it in aggregate; no large JSON is generated or decoded. It must
reject before any axis decoder, matrix reader or graph cursor. The graph cursor
seam is routing-only; no graph source-authority claim is made.

Parse-only result: `AXIS_AND_EXTERNAL_SQL_PARSE_ONLY_OK`. Execution is scheduled
only after coordinator confirms the preceding eighteen-case source-WIP gate
has terminated; an existing sidecar from an earlier failed gate must not be
mistaken for the current process's completion. No performance jobs authorized.

Separately, the authorized external-only family comparator correction replaces
`dbReadTable` with `SELECT * ... ORDER BY row_ordinal` in
`/tmp/scwb-engine-simplification-forge-20261018/representative_remaining_families.R`.
This makes direct SQL row-order expectations explicit, preserving values,
types, metadata, budgets and old evidence. It was parsed, not benchmarked.
The coordinator separately corrected the graph comparator's fixture-local
canonical ordinal1 representation to `1e0`; no engine canonicalizer changed.

After coordinator explicitly confirmed the preceding gate had terminated,
ran only the new axis contract with a fresh source environment over
`library_frozen`. Retained log/atomic sidecar:
`/tmp/scwb-engine-simplification-forge-20261018/private_axis_preadmission_development1.log`
and `.exit` =0. Literal final result:
`PRIVATE_AXIS_PREADMISSION discovered=1 executed=1 passed=1 skipped=0 failed=0`.
No other test or benchmark was run for this extension. This source-WIP pass
does not resolve Sable's separate physical-axis/parser/scratch source-bound
review or replace the future installed qualification on a frozen candidate.
