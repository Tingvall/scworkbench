# File-backed dense-space storage

SQLite is the bundle control plane: it owns space identifiers, shape, storage
version, content identity, provenance, lifecycle, and the contained payload
path. Numerical coordinates are the data plane and live once in a versioned,
chunked HDF5 payload. Fresh bundles do not create or populate relational
`space_coords`, `space_2d`, or `artifact_space_2d` coordinate tables.

Operators continue to use `wb_spaces()` and `wb_space()`. The getter preserves
canonical cell identity, requested cell order, requested dimension order, and
the documented `cell_id/x/y` data-frame form for two-dimensional spaces.
Selected rows and dimensions are hyperslab reads; the
`scworkbench_payload_read` attribute records rows, dimensions, and values read
so bounded access is executable rather than inferred.

## Payload and identity

The storage tag is `hdf5:dense-space:v1`; the schema is
`scworkbench.dense-space.hdf5.v1`. A contained
`space_payloads/space_<token>.h5` file contains `coordinates`, ordered
`cell_ids`, and ordered `dim_labels`, with explicit shape, float64 dtype,
endianness, and chunk attributes. `space_payloads` is the sole payload registry.
The content identity scheme is
`scworkbench.content.dense-space-hdf5.sha256.v1`, calculated by streaming the
complete file. Provenance additionally binds the exact registry row, so a
payload-preserving registry mutation is not invisible.

R/Python array order is an explicit portability boundary. R exposes and writes
`n_cells x n_dims`. PyBench/h5py reverses HDF5 C-order dimensions and chunks
and transposes values so `rhdf5` reads the same canonical R shape; its Python
getter reverses the representation on read. This is verified at Quill commit
`8418ca81601558dda3784039e7bf18440c8dac3c`. The qualified platform is
little-endian Linux with h5py 3.15.1 and `rhdf5`.

## Publication and failure behavior

The central writer creates a unique same-filesystem pending file, flushes and
reopens it, validates schema/shape/identities/finiteness/hash, registers it
under the exclusive writer lock, and atomically renames it at the commit
boundary. Promotion repeats those guarantees through its private workspace.
Rollback removes pending and newly published files. A registry row can never
successfully point at an absent or partial file.

Structural/content/recipient validation fails closed for missing, truncated,
byte-mutated, wrong-order, wrong-shape, unknown-version, registry-mismatched,
symlinked, or escaped payloads. Lifecycle purge and branch operations resolve
payload ownership through the central registry; two-dimensional artifacts
reference that owner and do not duplicate coordinates.

## Benchmark and remaining audit boundary

Run the retained honeybee-scale benchmark with:

```bash
SCWORKBENCH_SOURCE_ROOT=. \
SCWORKBENCH_PYBENCH_PYTHON=/home/dirk/Projects/pybench/.venv/bin/python \
Rscript inst/acceptance/file_backed_dense_space_benchmark.R \
  --output=inst/acceptance/file_backed_dense_space_benchmark.json
```

It uses the historical 120,895-cell raw bundle read-only, builds a fresh 50D +
30D + 2D fixture, measures writers/getters/promotion/validation and the PyBench
hello audit, and reports the storage multiplier and bounded-read evidence. The
HDF5 change removes relational coordinate rows and their indexes. It does not
claim to remove PyBench's remaining complete-payload hashing and full mutable-
tree clone/audit overhead; those measurements are reported separately.
