# File-backed dense-space R/PyBench interface

Status: **implemented composite interface**. R integration is based on
checkpoint `a62803cdf369cad05d749963dcaeec5f4c22a4c7`; the compatible PyBench
writer is commit `8418ca81601558dda3784039e7bf18440c8dac3c`.

This note freezes the shared interface. It does not authorize either runtime
to write legacy `space_coords`, `space_2d`,
or `artifact_space_2d` coordinate rows.

## HDF5 payload

The storage tag is `hdf5:dense-space:v1` and the HDF5 schema version is
`scworkbench.dense-space.hdf5.v1`. Each payload is a contained regular file at
`space_payloads/space_<token>.h5` with these root datasets:

| Dataset | Shape | Contract |
|---|---:|---|
| `coordinates` | `n_cells x n_dims` | finite IEEE-754 float64 values, chunked at `min(n_cells, 1024) x min(n_dims, 16)` |
| `cell_ids` | `n_cells` | unique, non-empty UTF-8 cell IDs in exact payload row order |
| `dim_labels` | `n_dims` | unique, non-empty UTF-8 dimension labels |

Root attributes are `schema_version`, `space_id`, `n_cells`, `n_dims`, `dtype`
(`float64`), `endianness` (`little` or `big`), `chunk_rows`, and `chunk_dims`.
The registered `content_sha256` is the lowercase SHA-256 of the complete HDF5
file. The ordered cell hash is the scworkbench canonical object SHA-256 of the
decoded `cell_ids` vector.

### HDF5/R-order portability boundary

The public and R-native shape is always `n_cells x n_dims`. HDF5 itself does
not define an R/NumPy memory order. The PyBench h5py writer therefore creates
the coordinate dataset with reversed C-order dimensions/chunks and writes the
transposed array; `rhdf5` then observes the canonical R shape and values.
PyBench getters reverse that representation back to the canonical NumPy view.
R writers use `rhdf5` directly in canonical R order. This transpose is an
intentional interoperability boundary, not a scientific transform. Composite
tests verify exact values, ordered cell IDs, labels, receipt identities, close/
reopen, promotion, and downstream reads across both runtimes. The qualified
boundary is little-endian Linux with h5py 3.15.1 and Bioconductor `rhdf5`.

## SQLite registry row

PyBench must insert one `spaces` row with `storage='hdf5:dense-space:v1'` and
one `space_payloads` row keyed by the same `space_id`:

```sql
space_payloads(
  space_id TEXT PRIMARY KEY REFERENCES spaces(space_id),
  path TEXT NOT NULL UNIQUE,
  schema_version TEXT NOT NULL,
  n_cells INTEGER NOT NULL,
  n_dims INTEGER NOT NULL,
  cell_ids_sha256 TEXT NOT NULL,
  dim_labels_json TEXT NOT NULL,
  dtype TEXT NOT NULL,
  endianness TEXT NOT NULL,
  chunk_rows INTEGER NOT NULL,
  chunk_dims INTEGER NOT NULL,
  content_sha256 TEXT NOT NULL,
  content_identity_scheme TEXT NOT NULL,
  provenance_identity TEXT,
  created_at TEXT NOT NULL
)
```

`content_identity_scheme` is
`scworkbench.content.dense-space-hdf5.sha256.v1`. `path` must be relative,
contained, non-symlinked, and resolve to the exact published payload.

## PyBench v2 capability and receipt

For an output space ID `<space_id>`, the request grants exactly these mutation
descriptors:

```text
sqlite_rows table=spaces        key_scope={column: space_id, values: [<space_id>]}
sqlite_rows table=space_payloads key_scope={column: space_id, values: [<space_id>]}
payload_tree path=space_payloads
```

The descriptors retain the request's `output_name`, `output_id=<space_id>`, and
`output_kind=space`. Model output authority remains separate:
`artifact_model_ref` scoped by `artifact_id`, plus
`artifact_models/<artifact_id>` as its payload tree.

The successful `pybench-op-v2` receipt must report every observed changed
descriptor in `write_manifest`:

- each SQLite descriptor above, with `row_count` and the canonical scoped-row
  `content_sha256` calculated by the existing PyBench v2 binary-value rules;
- one payload descriptor for each changed path below `space_payloads`, with the
  concrete relative `path`, `row_count=0`, and SHA-256 used by the protocol
  payload snapshot for that file or directory;
- no descriptor for a legacy coordinate table and no sibling row/path change.

The receipt capability echo, session/run IDs, outputs, and write manifest must
otherwise satisfy the existing `pybench-op-v2` validation contract exactly.

## Atomic publication

PyBench operates only in the engine-created private staging clone. It must
write and flush a unique pending HDF5 file, close and reopen it, verify schema,
shape, ordered identities, finite values, and SHA-256, then atomically rename
it within the same `space_payloads` filesystem. Registry rows may be committed
only for the complete renamed payload. Any failure must remove pending and
newly published paths and leave no registry row. Replacement must retain the
old payload until the registry transaction succeeds; superseded files are
retired only after commit. R-side promotion subsequently copies the validated
stage payload through its own private promotion workspace and commit boundary.

## Composite verification

The formerly blocked focused command is now:

```bash
SCWORKBENCH_PYBENCH_PYTHON="$PYBENCH_ROOT/.venv/bin/python" \
Rscript - <<'RS'
devtools::load_all('.', quiet=TRUE)
contract_test_skip <- function(x) stop(x)
source('tests/test_operation_pack_v3_matrix_model_boundary_contract.R')
test_operation_pack_v3_matrix_model_boundary_lifecycle_contract()
RS
```

The ABI-v3 matrix-model contract exercises the current generic fitted-space
and contained-model boundary. Historical core PeakVI named-op v2 tests have
been relocated to scwbLatent migration evidence; they are not live no-pack
operations. Other scVI durable recovery, staging capability, corruption, and
dense-storage contracts exercise the shared registry/payload interface. The
remaining PyBench performance
boundary is explicit: its complete-tree pre/post audit and mutable-tree clone
still hash or copy more than the current operation's changed dense payload.
