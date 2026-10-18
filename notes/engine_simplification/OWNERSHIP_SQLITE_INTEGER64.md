# Explicit integer64 binding ownership

One introduced engine-owned contract:
test_engine_sqlite_vector_bind_exact_integer64_contract, in the existing
test_engine_sqlite_vector_bind_contract.R. Source/decision checkpoint
8ec6f2336131b59aa9883f5819fd532cf2e7538d; same-definition test strengthening
f9826c833bd441cd2b37bdf24e5590d414e9f369 adds-1/-2 and explicit NA64 SQLNULL.
Prior four SQL test decisions remain2119fa8; no scientific pack assertion added.

Current-only generation preserves frozen historical242/139/reference63 ledgers:

```
Rscript inst/dev/phase8_test_ownership_inventory.R --current-only inst/phase8/core_test_ownership_inventory.csv inst/phase8/migrated_operation_test_references.csv inst/phase8/packed_operation_names.csv inst/phase8/current_core_test_ownership_inventory.csv
PHASE8_TEST_INVENTORY tests=242 files=139 migrated_reference_rows=63
PHASE8_CURRENT_TEST_INVENTORY tests=516 files=214 introduced=276 moved=2
exit0
```

Direct lightweight source-only assertion:
`source("tests/test_phase8_no_pack_core_surface_contract.R"); stopifnot(test_phase8_test_ownership_inventory_contract())`
exit0; CURRENT516 FILES214 ENGINE_LEDGER180. git diff--check exit0; no runtime,
historical ledger, public interface or installed package modification in this
ownership-only descendant. No suite/installation/performance execution.
