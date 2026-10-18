# Explicit graph aggregate / object-row test ownership

Combined source reviewed here:
`24c4c493bfc2265f819cb0a5b4b9e957f92d78f0`.

Ten explicit `engine_execution_v1` decisions were added, not inferred by
discovery: five generic graph-storage aggregate tests from source checkpoint
`d32ed3e78baab2c1a94ddda380bf4c19c1eb60e9`, and five generic canonical
object-row tests from`b3e76da33ac6f56eca67f9d6406a7a82b8440355`.
Each CSV row names its exact function/path, core owner, retention disposition,
specific correctness boundary and immutable source/decision pin. These test
primitive storage, resource admission, cleanup, canonical bytes and fallback
semantics; none asserts a scientific operation's method behavior.

The existing generator classified nothing automatically. It validated those
decisions and refreshed current discovery/key assertions only. Frozen Phase8
ownership remains242tests/139files. Current discovery is462tests/201files
(previous452/199 plus10tests in2files);222introduced and2moved relative to
the frozen inventory. The existing85-row graph/core addition decisions,
historical references and packed-operation names were unchanged. Unknown,
missing and duplicate current identities remain rejected. The discovery
contract now also requires the classified source-path set to equal actual
top-level source-file discovery.

Lightweight commands (no scientific/runtime qualification or performance job):

```
Rscript inst/dev/phase8_test_ownership_inventory.R --current-only inst/phase8/core_test_ownership_inventory.csv inst/phase8/migrated_operation_test_references.csv inst/phase8/packed_operation_names.csv inst/phase8/current_core_test_ownership_inventory.csv
```

Literal output:

```
PHASE8_TEST_INVENTORY tests=242 files=139 migrated_reference_rows=63
PHASE8_CURRENT_TEST_INVENTORY tests=462 files=201 introduced=222 moved=2
```

The single source/discovery contract
`test_phase8_test_ownership_inventory_contract()` returnedTRUE after sourcing
its definition, including malformed-ledger/unknown/duplicate negatives.
Output:`FROZEN_TESTS=242 FROZEN_FILES=139 CURRENT_TESTS=462 CURRENT_FILES=201`
and`OWNERSHIP_DISCOVERY_ASSERTIONS=PASS`.

Both commands ran through`inst/ci/run_logged_gate`, with exit0 logs/atomic
sidecars retained under the coordinator's evidence directory as
`aggregate_object_ownership_regeneration` and
`aggregate_object_ownership_discovery`. This is ownership/source evidence,
NOT proof that the new graph/object execution tests have run or passed.
