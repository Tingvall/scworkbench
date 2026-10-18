# Explicit ownership: matrix formatting and SQLite binding

Basea726aee794ca3a700076103b74d899feb9cf5d58. Seven explicit core-engine
ownership rows, no inferred classification or runtime modification:

- Three append-local numeric-token byte/identity/error contracts introduced at
  28afd428c108ff278f81143bb2a530424d0d6b63.
- Four bounded SQLite binding/order/types/fault/fallback contracts at source
  2119fa8e0ad18c17b26989be600a3f5491bf33e6.

All are generic engine exchange/storage/integrity assertions; no scientific
method assertion assigned to core. Frozen Phase8 baseline242definitions/139files
and63 reference rows remain unchanged. Current-only generator observed515
definitions/214files, not assumed from prior508/212; engine ledger179 rows.

Planner observer-ordering test fix (rootecb9 / source9be checkpoint) does not
change the three earlier620054f introduced test ownership decisions. Diagnosis
identified initial SQL observer SHM creation, not planner/schema mutation.
The corrected observer-ordering fixture retains strict complete filesystem
comparison including SHM; current assertion extraction is refreshed, not waived.

Fresh graph handoff remains SOURCE-INSPECTED, NOT IMPLEMENTED, MEASURED or
QUALIFIED. Immediate duplicate graph imports are a source-confirmed remaining
cost. Sable's resource HOLD requires retained SQL stages/caches to be charged
across later ordinary/model closure, exact lifetime cleanup, and actual-fileSHA
checks after both reopen fault seams. No graph authority/cache changes included.

Literal lightweight checks:

```
Rscript inst/dev/phase8_test_ownership_inventory.R --current-only inst/phase8/core_test_ownership_inventory.csv inst/phase8/migrated_operation_test_references.csv inst/phase8/packed_operation_names.csv inst/phase8/current_core_test_ownership_inventory.csv
PHASE8_TEST_INVENTORY tests=242 files=139 migrated_reference_rows=63
PHASE8_CURRENT_TEST_INVENTORY tests=515 files=214 introduced=275 moved=2
exit0

Rscript -e 'source("tests/test_phase8_no_pack_core_surface_contract.R"); stopifnot(test_phase8_test_ownership_inventory_contract()); cat("OWNERSHIP_DISCOVERY_ASSERTIONS PASS\n"); x <- read.csv("inst/phase8/current_core_test_ownership_inventory.csv"); a <- read.csv("inst/phase8/engine_execution_test_additions_v1.csv"); cat("CURRENT", nrow(x), "FILES", length(unique(x$source_path)), "ENGINE_LEDGER", nrow(a), "\n")'
OWNERSHIP_DISCOVERY_ASSERTIONS PASS
CURRENT 515 FILES 214 ENGINE_LEDGER 179
exit0

git diff --check
exit0
```

No installation, suite or performance execution. Source parses and explicit
ownership assertions only; runtime/performance qualification owned separately.
