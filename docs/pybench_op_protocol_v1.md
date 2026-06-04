# Pybench Op Protocol v1 (`pybench-op-v1`)

This document defines the handoff protocol between:

- `scworkbench` (R bench / orchestration authority)
- `pybench` (Python compute runtime)

Version string:

- `pybench-op-v1`

## Purpose

Run Python-native ops through the normal bench/session workflow while preserving:

- small reproducible param payloads
- bench-owned provenance/run registry
- direct bundle-native payload writes by Python

## Ownership Boundary

### Bench (R) owns

- op interface/registry
- run/session lifecycle
- provenance params (birth certificates)
- artifact registry rows (`artifacts`) and artifact IDs

### Pybench (Python) owns

- bundle reads (getters)
- compute
- payload writes for pre-registered artifact IDs
- success/error receipt

Pybench must not create/modify run registry or provenance rows in v1.

## Transport

Bench invokes a Python module as a subprocess and exchanges JSON files:

- `request.json`
- `receipt.json`

Recommended invocation:

```bash
/path/to/pybench/.venv/bin/python -m pybench.ops.<op_module> \
  --request /tmp/req.json \
  --receipt /tmp/rec.json
```

## Request JSON (bench -> pybench)

Required top-level fields:

- `protocol_version` (must equal `pybench-op-v1`)
- `bundle_dir` (string)
- `op_name` (string)
- `run` (object; at least `run_id`)
- `inputs` (object; symbolic refs + small values)
- `params` (object; op params)
- `outputs` (object mapping output name -> artifact spec)

Output artifact spec required fields:

- `artifact_id` (string; row already exists in `artifacts`)
- `type` (string; expected artifact type)

Example:

```json
{
  "protocol_version": "pybench-op-v1",
  "bundle_dir": "/path/to/bundle",
  "op_name": "py_protocol_hello",
  "run": { "run_id": "run_abc123" },
  "inputs": {
    "cell_set": "core",
    "space_id": "umap.peakvi_space"
  },
  "params": {
    "n_preview": 200
  },
  "outputs": {
    "vector": { "artifact_id": "cell_vector_...", "type": "cell_vector" },
    "membership": { "artifact_id": "relation_family_...", "type": "relation_family" },
    "summary": { "artifact_id": "obs_table_...", "type": "obs_table" }
  }
}
```

## Receipt JSON (pybench -> bench)

Required top-level fields:

- `protocol_version` (must equal `pybench-op-v1`)
- `status` (`"ok"` or `"error"`)
- `op_name` (string)
- `run_id` (string; echoed from request)

If `status == "ok"`:

- `outputs` (object mapping output name -> write summary)
- optional `warnings` (array of strings)
- optional `timings` (object)
- optional `pybench` metadata (version)

If `status == "error"`:

- `error_class` (string)
- `message` (string)
- optional `traceback` (string)

Example success:

```json
{
  "protocol_version": "pybench-op-v1",
  "status": "ok",
  "op_name": "py_protocol_hello",
  "run_id": "run_abc123",
  "outputs": {
    "vector": { "artifact_id": "cell_vector_...", "type": "cell_vector", "rows_written": 47335 },
    "membership": { "artifact_id": "relation_family_...", "type": "relation_family", "rows_written": 47335 },
    "summary": { "artifact_id": "obs_table_...", "type": "obs_table", "rows_written": 1 }
  },
  "warnings": [],
  "timings": { "total_sec": 0.42 },
  "pybench": { "version": "0.1.0" }
}
```

## Validation Rules

Bench and pybench must both validate:

- protocol version
- required top-level fields
- output artifact specs contain `artifact_id` + `type`
- receipt `outputs` keys (on success) are a subset of requested outputs
- returned `artifact_id`/`type` match requested output specs

## Symbolic Reference Rule

Bench should materialize literal `cell_ids` / `feature_ids` into sets before handoff.

Request payloads should prefer:

- `cell_set`
- `feature_set`
- `matrix_id`
- `space_id`
- artifact refs

over large literal vectors.

## PeakVI Matrix Handoff Note

For production/cluster PeakVI, the bench should provide staged sparse chunks
through `inputs.matrix_chunks_dir`. In that path, R reads the bundle matrix
through the R BPCells stack, stages sparse chunks plus manifest metadata, and
pybench assembles the staged chunks before running PeakVI.

`peakvi_fit` in pybench also supports native bundle matrix reads when
`matrix_chunks_dir` is absent. That path is local/development capable, but it is
not the current cluster production default because the native/forked Python
BPCells double-matrix path has hit segmentation faults on Tetralith. Returning
native BPCells reads to production requires a passing cluster smoke for that
forked/double-matrix path.

`peakvi_project` currently requires staged chunks.

## Idempotency Rule (payload writes)

Pybench payload writers should be safe for retry on the same artifact ID:

- `DELETE payload rows WHERE artifact_id = ?`
- reinsert payload rows

## Single-Writer Rule

Assume one writer at a time per bundle during Python op execution.
