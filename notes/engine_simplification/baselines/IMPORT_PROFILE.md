# Bounded import/recipient attribution (repaired baseline)

No runtime edits. Rprof interval .01 second, exact repaired installed library.
No full Xenopus scientific or import rerun: existing owned source-only bundle
was inspected read-only; the new import was synthetic 500 features x1,000 cells,
sparse counts, nine metadata columns, eight categorical columns/ten levels,
and a 2D source UMAP. Original experiments and source file untouched.

## Recipient profile: dominant existing table fold

Existing fixture before-source-import/before-import.bundle:
profile_recipient.R completed **exit0**, validation elapsed **52.319 seconds**,
sampled **52.30 seconds**, GNU wall52.55, RSS680,568 KiB, valid and unchanged
pre/post filesystem fingerprints.

| Function | Inclusive sampled seconds | Percent |
| --- | ---: | ---: |
| .wb_prov_stored_table_content_sha256 | 33.86 | 64.74 |
| .wb_prov_sha256_object | 43.28 | 82.75 |
| jsonlite::serializeJSON | 41.18 | 78.74 |
| .wb_manifest_registry_snapshot | 4.98 | 9.52 |
| .wb_prov_file_tree_sha256 / .wb_prov_sha256_file | 4.87 | 9.31 |
| .wb_graph_token_hash (filesystem fingerprints) | 3.80 | 7.27 |
| .wb_metadata_field_content_identity | 0.39 | 0.75 |

Nested inclusive times are not additive. Metadata-field identity is batched
at 5,000 cells and NOT a per-row digest loop: R/metadata_fields.R:73–115.
Do not optimize it based on a guessed row-fold explanation.
The dominant existing table helper in R/provenance_store.R:492–511 does fold
each stored row via serializeJSON(list(previous,row_sha256)). The already
root-owned table-fold optimization targets the measured dominant cost.

Read-only SQL inspection found a 31,535-row container_feature_metadata artifact
and a one-row ingest report. The large feature table has both CONSUMES and
PRODUCES bindings. R/validate.R:1148–1151 checks stored-table identities while
iterating bindings; R/validate.R:1424–1434 computes them again for content
completeness. This establishes repeated same-artifact work from source and
retained bindings; Rprof is sampling, not an exact invocation counter. A future
per-report consolidation must retain all scheme/hash/binding comparisons and
full payload authority; this helper implements no such cache or check removal.

## Synthetic import: schema-status and manifest work dominate

profile_synthetic_import.R **exit0**, import elapsed **34.594 seconds**,
sampled **34.24**, complete process wall41.00, RSS944,572 KiB.

| Function | Inclusive sampled seconds | Percent |
| --- | ---: | ---: |
| .wb_manifest_registry_snapshot | 15.41 | 45.01 |
| .wb_manifest_table_identity | 15.19 | 44.36 |
| .wb_refresh_manifest_committed | 14.80 | 43.22 |
| .wb_schema_status | 14.46 | 42.23 |
| .wb_schema_table_foreign_key_status | 14.17 | 41.38 |
| .wb_schema_component_is_current | 13.38 | 39.08 |
| .wb_ingest_label_cell_sets / wb_cell_set_replace | 10.78 /10.76 | 31.48 /31.43 |
| .wb_schema_actual_foreign_key_signatures | 5.43 | 15.86 |
| .wb_prov_sha256_object /serializeJSON | 1.49 /1.39 | 4.35 /4.06 |
| .wb_metadata_field_content_identity | 0.07 | 0.20 |

This is primarily repeated structural SQL/S4 dispatch and repeated manifest
work, not scientific arithmetic or metadata-field hashing. Anchors:
R/schema_migrations.R:56 component shim always calls full status;
R/schema_migrations.R:92 status and :397 FK checking;
R/bundle_ingest_containers.R:191 loops categorical sets;
R/cell_sets_membership.R:298 wb_cell_set_replace calls membership schema check;
R/bundle_init.R:354 refresh and :430 registry snapshot, :476 manifest builder.
The repaired baseline's manifest row representation helper was already
identity-preserving streaming; this profile does not imply naive per-row JSON
there. Current root source may contain subsequent improvements; measurements
are explicitly from the untouched repaired installed library.

Prospective budgets recorded in BUDGETS.md before new schema-related changes:
same synthetic import <=17.3 seconds, sampled schema-status <=3 seconds,
manifest snapshots <=4 seconds; preserve complete imported data/sets/provenance
and schema/FK diagnostics. No approval for semantic/identity changes follows
from these budgets. Root owns implementation/Sable review.

Complete profile CSVs and compressed logs/sidecars are adjacent evidence;
larger raw Rprof samples remain in the isolated temporary chambers. No full
suite, source repair, scientific rerun, merge, push or build performed here.
