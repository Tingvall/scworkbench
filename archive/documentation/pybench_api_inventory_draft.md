# `pybench` API Inventory Draft (Bundle-Native Python Runtime)

## Scope

This draft inventories the Python-side functions needed for a **bundle-native** Python runtime (`pybench`) that:

- reads data directly from the scworkbench bundle (SQLite + BPCells payloads)
- runs Python-native methods (for example `scvi-tools`, `palantir`)
- writes outputs directly into bundle payload tables/files
- does **not** own run/provenance/registry semantics

Assumption for this draft (as discussed):

- **bench (R engine) handles**:
  - op registry / params provenance
  - run registration / run status
  - artifact registry rows (`artifacts`) and IDs
- **pybench handles**:
  - data getters
  - payload writes for pre-registered artifact IDs
  - success/failure receipt back to bench

This keeps cross-language transfer small and avoids `reticulate`.

## Design Principle

Do not mirror arbitrary `wb_*` functions 1:1.

Implement a **language-neutral bundle access contract** with stable semantics:

- canonical cell order (`cells.rowid`)
- canonical feature order (`features.rowid` within `matrix_id`)
- unified space reads (`space_2d` vs `space_coords`)
- payload table writes by primitive kind

## V1 Python Modules

Recommended package layout:

- `pybench.bundle`
- `pybench.getters`
- `pybench.artifacts_payload`
- `pybench.models`
- `pybench.io.bpcells`
- `pybench.receipts`
- `pybench.schema` (read-only checks at first)

## 1. Bundle / Connection Functions (Must Have)

These mirror the practical subset of `wb_open_bundle()` / `wb_close_bundle()`.

### `open_bundle(bundle_dir) -> BundleHandle`

Responsibilities:

- read `manifest.json`
- resolve SQLite path from `manifest.storage.sqlite.path`
- open SQLite connection
- expose:
  - `bundle_dir`
  - `manifest`
  - `con` (sqlite connection)

Notes:

- Python should **not** auto-migrate schemas in v1.
- Python should fail fast if required tables are missing.

### `close_bundle(bundle)`

- close SQLite connection cleanly

### `bundle_manifest(bundle) -> dict`

- return manifest object (cached from open)

## 2. Core Read Getters (Must Have)

These are the minimum reads needed for Python ops.

### 2.1 Cell universe + metadata

#### `cells(bundle, cell_set="core", dataset_id=None) -> list[str]`

Must match R semantics:

- `all` => `cells` table in `ORDER BY rowid`
- otherwise use `cell_set_membership` joined to `cells`, ordered by `cells.rowid`

Why this matters:

- canonical row alignment for spaces/matrices/vectors

#### `meta(bundle, cells=None, cols=None, dataset_id=None) -> DataFrame`

Must match R semantics:

- query from `cells`
- default `ORDER BY rowid`
- if `cells` provided, reorder to that exact input order

### 2.2 Matrices + features

#### `matrices(bundle) -> DataFrame`

Read `matrices` registry (ordered by `matrix_id`)

#### `matrix_info(bundle, matrix_id=None) -> DataFrame`

Registry row(s) from `matrices`

#### `features(bundle, matrix_id=None, feature_type=None) -> DataFrame`

Read `features` registry with canonical order:

- `ORDER BY matrix_id, rowid`

#### `feature_ids(bundle, matrix_id, feature_type=None) -> list[str]`

Must preserve canonical feature order:

- `ORDER BY rowid` within `matrix_id`

#### `matrix_handle(bundle, matrix_id)`

Open BPCells matrix directory from `matrices.path`

Use cases:

- direct method inputs
- sparse slicing

#### `matrix_read_features(bundle, matrix_id, feature_ids, cell_ids, missing="zero")`

Optional in V1 if Python methods can read BPCells directly and slice themselves.

Still useful as a convenience function if Python ops need stable bundle-aware slicing.

### 2.3 Spaces

#### `spaces(bundle) -> DataFrame`

Read space registry (`spaces`)

#### `space_info(bundle, space_id=None) -> DataFrame`

Read space metadata row(s)

#### `space(bundle, space_id, cells=None, dims=None)`

Unified getter matching `wb_space()` semantics:

- if 2D / `wide:space_2d` => return table (`cell_id`, `x`, `y`) aligned to `cells` if provided
- else read `space_coords` and materialize dense matrix (`cells x dims`)
- default cell order is canonical `wb_cells(bundle)`

Important:

- Python ops (e.g. monocle/scvi/palantir) depend on stable cell alignment.

## 3. Set Getters (Must Have for user-driven workflows)

If bench passes symbolic refs only, Python still needs to resolve them.

### 3.1 Cell sets

#### `cell_sets(bundle) -> list[str]`

Read distinct `cell_set` from `cell_set_membership`

#### `resolve_cell_set(bundle, cell_set) -> list[str]`

Must support:

- `"all"`
- concrete names (e.g. `"core"`)

Canonical ordering:

- current R behavior is `ORDER BY rowid` on membership query or `cells.rowid` depending path
- Python should match resolved output order used by bench for op execution

### 3.2 Feature sets (Recommended in V1)

Needed for Python ops that take marker sets / gene programs.

#### `feature_sets(bundle, matrix_id=None, namespace=None, organism=None, origin=None) -> DataFrame`

#### `feature_set_info(bundle, feature_set, matrix_id) -> DataFrame`

#### `feature_set_get(bundle, feature_set, matrix_id) -> list[str]`

Preserve saved order (`ORDER BY rank`)

## 4. Artifact Registry Reads (Must Have)

Bench owns provenance/run/artifact registration, but Python needs to discover and inspect artifact refs.

### `art_list(bundle, type=None) -> DataFrame`

Read `artifacts` rows (filterable by `type`)

### `art_get_row(bundle, artifact_id) -> dict`

Small helper to read one `artifacts` row (type, name, source_op, input refs)

### `art_load_payload_*` (selective, not full `wb_art_load`)

Python does not need a full generic primitive loader immediately.
Implement loaders only for kinds Python ops consume.

Recommended V1:

- `load_art_cell_vector(bundle, artifact_id)`
- `load_art_relation_family(bundle, artifact_id)` (for future probabilistic methods)
- `load_art_model_ref(bundle, artifact_id)` (for project/continue ops)
- `load_art_path_2d_family(bundle, artifact_id)` (optional)

Registry + payload table mapping:

- `cell_vector` -> `artifact_labels`
- `relation_family` -> `artifact_relation_rows`
- `cell_vector_family` -> `artifact_pseudotime`
- `path_2d_family` -> `artifact_curves_2d`
- `model_ref` -> `artifact_model_ref` (+ file path)
- tables -> `artifact_tables` + `artifact_table_rows`

## 5. Payload Write Functions (Must Have, Python-owned)

These write payload rows/files for an **artifact_id already created by bench**.

Bench pre-registers the `artifacts` row and passes:

- `artifact_id`
- expected `type`
- output name / kind contract

Python writes only the payload table/file and returns a receipt.

### General rules

- no writes to `artifacts` table in v1 (bench owns registry/provenance)
- payload writer should validate expected artifact `type`
- writes should be transactional per artifact payload
- delete/replace existing payload rows for that `artifact_id` before writing (idempotent retry)

### 5.1 `write_artifact_cell_vector_payload(...)`

Target table:

- `artifact_labels`

Columns written:

- `artifact_id`
- `cell_id`
- `label`
- `value_type` (`"continuous"` / `"categorical"`)
- `value_num` (nullable)

Semantics:

- preserve numeric fidelity for continuous values

### 5.2 `write_artifact_cell_vector_family_payload(...)`

Target table:

- `artifact_pseudotime`

Columns:

- `artifact_id`
- `cell_id`
- `lineage_id`
- `pseudotime`

### 5.3 `write_artifact_relation_family_payload(...)`

Target table:

- `artifact_relation_rows`

Columns:

- `artifact_id`
- `relation_key`
- `cell_id`
- `weight` (nullable)
- `value` (nullable)
- `distance` (nullable)

This is the key payload writer for:

- monocle branch membership
- palantir/cellrank fate probabilities (future)
- topic/program loadings (future)

### 5.4 `write_artifact_path_2d_family_payload(...)`

Target table:

- `artifact_curves_2d`

Columns:

- `artifact_id`
- `lineage_id`
- `point`
- `x`
- `y`

### 5.5 `write_artifact_space_2d_payload(...)` (optional in V1)

Target table:

- `artifact_space_2d`

Useful for Python methods producing display coordinate snapshots as artifacts.

### 5.6 `write_artifact_model_ref_payload(...)`

Targets:

- model file under bundle path (for example `artifact_models/<artifact_id>.rds` equivalent Python format)
- `artifact_model_ref` row

Columns:

- `artifact_id`
- `engine`
- `model_space_id`
- `in_space_id`
- `model_type`
- `model_path`

Note:

- For Python-native engines, `model_path` may point to `.pkl`, `.pt`, `.joblib`, `.h5ad`, etc.
- Bench/loader support must know how to consume them. If not, treat as opaque continuation artifact for Python-only ops.

### 5.7 `write_artifact_table_payload(...)` (optional but likely soon)

Targets:

- `artifact_tables`
- `artifact_table_rows`

Needed for Python ops producing ranked tables (DE-like, pathway, QC summaries).

## 6. Space / Matrix Write Functions (Non-artifact writes; Optional but High Value)

These are bundle writes outside artifact payloads.

### 6.1 `add_space(bundle, space_id, coords, source=None, description=None, overwrite=False)`

Python analog of `wb_add_space()`:

- registry row in `spaces`
- payload in `space_2d` or `space_coords`
- validate all `cell_id`s exist
- maintain storage tags:
  - `wide:space_2d` (2D)
  - `long:space_coords` (>2D)

This is important for Python methods like `scvi-tools` / `scanpy` that produce embeddings.

### 6.2 `upsert_space_row(...)` (internal helper)

Python internal helper mirroring `.wb_upsert_space_row()`

### 6.3 Matrix writes (defer)

Full matrix ingest/write is out of scope for pybench V1 unless a Python method must persist new matrices.

If needed later:

- BPCells matrix writer wrapper
- matrices registry writes
- features registry writes

## 7. Receipt / Handoff Functions (Must Have)

Bench handles provenance and run registry, but Python should send a structured receipt.

### `run_receipt_success(...)`

Return to bench:

- `status = "ok"`
- `outputs`:
  - output name
  - artifact_id
  - artifact_type
  - payload rows written / files written
- timing
- Python package versions (optional but useful)
- warnings

### `run_receipt_error(...)`

Return to bench:

- `status = "error"`
- error class
- message
- traceback (string)
- partial outputs written (if any)

Bench can then mark run status and provenance snapshots centrally.

## 8. Schema / Validation Helpers (Recommended)

### `assert_bundle_contract_v1(bundle)`

Check required tables/columns exist for the subset pybench uses.

At minimum:

- `cells`, `features`, `matrices`, `spaces`
- `space_2d` and/or `space_coords`
- `artifacts`
- payload tables needed by enabled writers

### `assert_artifact_payload_contract(bundle, artifact_id, expected_type)`

- ensure `artifacts` row exists and matches `type`
- fail before writing payload rows

### `with_sqlite_txn(con, fn)`

- one transaction per artifact payload write

## 9. Explicitly Out of Scope for Pybench V1

These stay in bench (R engine) for now:

- run/session DAG management
- op registry / `wb_op_interface`
- selectors execution (unless later ported intentionally)
- provenance JSON assembly
- artifact birth certificates / identity cards
- promotion planning / DAG promotion semantics
- generic `wb_resolve_primitive` across session refs

Bench should hand Python concrete refs and resolved params when possible.

## 10. Recommended V1 Function Inventory (Shortlist)

### Read getters (implement first)

- `open_bundle`
- `close_bundle`
- `bundle_manifest`
- `cells`
- `meta`
- `matrices`
- `matrix_info`
- `features`
- `feature_ids`
- `matrix_handle`
- `spaces`
- `space_info`
- `space`
- `cell_sets`
- `resolve_cell_set`
- `feature_sets`
- `feature_set_get`
- `art_list`
- `art_get_row`

### Payload writers (implement first)

- `write_artifact_cell_vector_payload`
- `write_artifact_relation_family_payload`
- `write_artifact_path_2d_family_payload`
- `write_artifact_model_ref_payload`

### Add immediately if first Python ops need them

- `write_artifact_table_payload`
- `add_space`

## 11. Why This Split Works

- no large R<->Python object transfer
- bench remains provenance/contract authority
- pybench remains compute + payload I/O runtime
- primitives stay primitive; civilization stays in birth certificates

