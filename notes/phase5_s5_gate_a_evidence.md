# S5 relation-family Gate A evidence

Status: old-core executions and resource review, before any schema/runtime edit. This is not S5 migration. Core source is `6e0438c90fe51bacda1604aa7c5cc3b1cd1e5646`; PyBench source is `9ad8a7a3bd2298fdc6f426032e54ccb07eee0402`.

## Executed old-core oracles

`tests/fixtures/phase5_s5_old_core_relation_capture.R` ran the actual old-core `wb_session_run_op()` paths, promoted complete outputs, and reopened the relation and model terminals. Its JSON output is `tests/fixtures/phase5_s5_old_core_relation_oracle.json`. The command used pinned installed core and PyBench:

```sh
R_LIBS=/tmp/forge-s2-ownership-final-20260925/exact-final/lib \
PYTHONPATH=/home/dirk/Projects/.pybench-worktrees/phase5-s5-relation-family-parity-quill-20260925/src \
SCWORKBENCH_PYBENCH_PYTHON=/home/dirk/Projects/pybench/.venv/bin/python \
Rscript --vanilla tests/fixtures/phase5_s5_old_core_relation_capture.R
```

Both executions passed twice; the frozen JSON matched byte-for-byte on repeat. Monocle3 has 24 nonlexicographically ordered source cells, 25 ordered relation rows, two lineage keys, one cell under both keys, and sparse per-key membership. Palantir has 30 source cells, 60 ordered rows, two branch keys, and exact finite weights. The fixture records every ordered `{key, cell_id, weight_hex}` row, optional-field presence, direct and reopened canonical content identities for every non-model terminal, complete terminal names, and reopened model engine/type/file presence. For each relation, direct and reopened `scworkbench.relation_family.content.v1` SHA-256 match. Palantir's old-core `branch_summary` direct/reopened content identities differ because its existing table persistence normalizes content; both observed identities are frozen separately. Monocle3 model RDS byte size changed by two bytes between otherwise identical runs; model file bytes are not a repeatable oracle. Model closure, type, and read-only reopen are asserted instead.

These are executed old-core operation oracles, not synthetic ABI fixtures. The later generic grant fixtures will consume the frozen rows without invoking or migrating the legacy method implementations.

## Zero-row boundary

The old-core Monocle3 helper explicitly rejects zero derived memberships. A terminal-free Palantir attempt on the 30-cell fixture failed inside Palantir's terminal inference with `ARPACK error -9` before producing an output; it is not a valid zero-row legacy result. A separate **synthetic** zero-row `wb_prim_relation_family(character(), character(), weight=numeric())` was accepted by the primitive constructor but failed during `wb_promote_analysis()` with `arguments imply differing number of rows: 1, 0`; the bundle retained zero artifacts, so no promoted ID existed to reopen. Current `wb_art_load()` also rejects zero relation rows. No valid legacy S5 zero-row execution was observed. If one is found later, stop rather than pad or discard it.

## Resource review before schema freeze

The proposed 1,000,000 source cells and 1,024 keys have a product of 1,024,000,000 possible unique pairs, below signed 32-bit maximum, but all multiplication and byte counters still require overflow-safe numeric checks. The proposed 10,000,000 rows with two 1,024-byte IDs can represent more than 20 GiB of raw identifier bytes before applying its 256 MiB declaration cap. R's structured list/JSON copies and escape expansion can exceed memory well before that ceiling; the 1,000,000-cell source axis is also outside the declaration-byte count. The real old-core oracles need at most 60 rows and 30 cells.

Quill confirmed the revised implementation ceiling: 1,000,000 source cells, 1,024 keys, 1,000,000 relation rows, 1,024 raw UTF-8 bytes per individual identifier, 67,108,864 total **encoded** identifier bytes, and 8,192 pairs per declaration chunk. The total counts every occurrence of each cell ID in the authenticated source axis, every key in the declared key axis, and both key and cell ID in every declared row. Each occurrence is counted as its canonical JSON string representation, including quotes and escape expansion. Manifest bounds may only narrow these limits. These bounds keep row and byte scale within the already tested S3 sparse-family envelope while preserving 1,024 possible keys; the combined encoded-byte rule covers source storage and JSON escape expansion. Check byte budgets incrementally before accumulating pairs or issuing a writer. Boundary tests must use multibyte IDs, escaping, and chunk-spanning duplicate pairs without allocating a maximum-size fixture. JSON Schema character `maxLength` is not a substitute for raw-byte enforcement.

## Palantir placement and rollback preparation

Quill executed an independent typed-only private Palantir computation from 30 R-generated cell IDs and numeric coordinates, passed over JSON stdin. Python returned 60 ordered relation rows, 30 pseudotimes, and 2,633 model pickle bytes through private output without a bundle path, artifact preregistration, registry API, or SQLite access. `/tmp/quill-s5-relation-gatea/typed_palantir_probe.R` and `typed_palantir_compute.py` are the probe, not an operation implementation. Actual core-issued typed-reader/G2-writer integration remains to be proved in Gate B.

Existing rollback hooks are `scworkbench.operation_pack_v2_test_hook` events `before_publication`, `published`, and `before_reopened`, plus the v3 sealed-writer hook used by the sparse-family tests. Gate B's relation fixture will inject each publication fault and compare the pre/post private stage directory, registry fingerprint, artifacts, run/provenance rows, and recipient state. It will also mutate staged rows after sealing and self-rehash a contradictory receipt; no new state may survive either failure.
