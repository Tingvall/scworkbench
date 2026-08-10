# File-backed dense-space PyBench interface checkpoint

Status: **incomplete integration checkpoint; not release-accepted**.

This note freezes the R-side interface needed for the matching PyBench change.
It does not authorize either runtime to write legacy `space_coords`, `space_2d`,
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

## Current blocker

PyBench `main` at `56dc588` still mutates `space_coords`. The focused command is:

```bash
SCWORKBENCH_PYBENCH_PYTHON=/home/dirk/Projects/pybench/.venv/bin/python \
Rscript - <<'RS'
devtools::load_all('.', quiet=TRUE)
contract_test_skip <- function(x) stop(x)
source('tests/test_pybench_durable_named_ops_v2_contract.R')
test_pybench_durable_peakvi_fit_v2_contract()
RS
```

It currently fails with:

```text
PYBENCH_OUT_OF_SCOPE_MUTATION: undeclared table/key scope: space_coords
```

Release gates and acceptance remain paused until PyBench implements this
interface and the composite tests pass.
