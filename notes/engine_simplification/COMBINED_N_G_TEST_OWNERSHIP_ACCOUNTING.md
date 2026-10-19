# Combined N/G generic test ownership accounting

Source base: `c231bc390ec47b70e4a32d7c5bf3acb49fc26773`. This change explicitly adds31 generic core identities to the existing versioned engine ownership ledger and regenerates current discovery. It changes no runtime, protocol, schema, method test, official pack or historical ownership decision.

The31 additions are bounded-space row encoding5 (f3bb055), immutable auxiliary readers5 (8713872), exact epoch observation4 (fb47df4), cursor unwind1 (746066b), bounded metadata batches3 (f6b5605), projection admission3 (3a9c7d1), native scalar JSON first3 (6875fa6) plus compact row-name1 (c3960db), and fresh graph handoff6 (649c740). Each ledger row records its individual generic correctness/identity/resource justification, exact source path and original full author/source checkpoint. No excluded numeric-memo, same-owner SQL or R-ASCII tests are selected.

Actual source AST regeneration reports586 current test definitions across230 files,250 explicit engine additions, and346 introduced identities relative to the242-test frozen baseline (two historical identities moved). This is discovery/accounting, NOT586 executed or passed tests. The existing test_manifest_stream_small_batch_aggregate_and_fault_restoration_contract changed assertions without changing identity and receives no duplicate ledger row.

## Commands and actual lightweight results

Executed from the combined worktree using atomic numeric `inst/ci/run_logged_gate` sidecars:

```sh
Rscript --vanilla inst/dev/phase8_test_ownership_inventory.R --current-only \
  inst/phase8/core_test_ownership_inventory.csv \
  inst/phase8/migrated_operation_test_references.csv \
  inst/phase8/packed_operation_names.csv \
  inst/phase8/current_core_test_ownership_inventory.csv
```

Then sourced `tests/test_phase8_no_pack_core_surface_contract.R` and invoked only test_phase8_test_ownership_inventory_contract(), including its explicit unknown/duplicate/foreign-owner/bad-pin/empty-reason negative checks. Result: TRUE, exit0. This was a source-only ownership contract, not an installed package or whole-core execution. Four gates exited0: regenerate, ownership_contract, frozen_inventories, diff_check.

Raw logs/exits: `/tmp/scwb-engine-simplification-forge-20261018/combined_ownership_c231bc3/`.
Log SHA-256s: regenerate73ed4820eb514e088b9efd8231925ff183d1b1943876e40ebbed4fca641cd289;
ownership_contract afe06ba51667b664403d424b25b3d7811d97cc5c70dd86425ff72cb0b3cf7863;
frozen_inventories184cb88fc547d49d085280f979dbbb7c4c2083b25b704e6d93ce161ece945a73.

Frozen baseline inventory, migrated references, packed operation names and historical graph/core85 ledger all remained byte-identical against the prechange SHA manifest. No historical row was rewritten. The regenerated current CSV changed31 added rows plus one existing assertion row.

Result CSV SHA-256s: engine additions f0f2804ff58df958a7506cc0da779f23641b633304a34ebb83293d7821a2e28a;
current inventory c706ad3466c8dfb4129e92a89cfceff550df45094a1d0c7292f0595d1fe9a904.

No installation, scientific execution, benchmark, complete suite or independent acceptance is claimed. Historical complete-suite failures and component budget misses remain unchanged.
