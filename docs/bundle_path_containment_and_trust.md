# Bundle path containment and serialized-payload trust

Portable durable state uses the `scworkbench-bundle-path-v1` contract. Every
manifest SQLite path and every registered matrix, fragment, materialization,
space model, UMAP model, generic model artifact, bundled source sidecar, and
promotion payload is a non-empty bundle-relative path. `wb_bundle_path_status()`
is the public diagnostic for the same resolver used by getters, promotion,
provenance hashing, deletion, opening, and recipient validation.

The resolver normalizes separators, rejects absolute paths and every `..`
component, and walks each existing ancestor. Each ancestor and the final target
must resolve to the normalized bundle root or a descendant of it. This ancestor
walk detects symlink escape even when the final leaf is missing. Missing and
wrong-type payloads have distinct stable codes. Valid stored paths remain
relative; absolute paths are returned only to an engine function after the
containment check.

The stable failure codes are `PATH_EMPTY`, `PATH_ABSOLUTE`, `PATH_ESCAPE`,
`PATH_SYMLINK_ESCAPE`, `PATH_TYPE_MISMATCH`, and `PAYLOAD_MISSING`.

## External references and migration

Absolute model rows from old bundles are classified as
`LEGACY_EXTERNAL_MODEL_REFERENCE`. They are nonportable, untrusted state. Model
getters never probe the old location or guess a replacement by basename.
`wb_repair_model_ref_paths()` reports them as
`legacy_external_nonportable` without accessing the external filesystem.

An operator who trusts and controls the old source may call
`wb_repair_model_ref_paths(bundle, dry_run = FALSE, import_external = TRUE)`.
That explicit ingestion transaction copies the file or model directory into
`artifact_models/`, changes the registry to a contained relative path, records
the external source and checksum in provenance, and refreshes the authoritative
manifest. A missing source or copy/provenance failure leaves the registry row
unchanged and cleans an incomplete copy. Absolute paths already resolving
inside the current bundle can be normalized without an external import.

External analysis inputs and export destinations are not durable portable
paths. They are allowed only at explicit ingestion/export APIs and are recorded
as external sources or returned export locations. Recipient validation reports
such source declarations as uninspected and never reads outside the bundle.

## Deserialization trust

Containment is necessary but is not a claim that serialized bytes are safe.
`wb_bundle_validation_report(level = "recipient")` checks path, byte identity,
and trust metadata without calling `readRDS()`, `uwot::load_uwot()`, or a Python
model loader. Its `path_contract$unsafe_payloads_loaded` value is always false.

`wb_load_space_model()` and the model-loading branch of `wb_art_load()` load a
serialized model only when its lifecycle is provenance-bound or when a trusted
engine runtime is executing it. A caller may explicitly opt in to a contained
but otherwise untrusted payload with `allow_untrusted_deserialization = TRUE`.
That opt-in never overrides path containment. Replay-equivalence loadability is
an explicit trusted execution step, not recipient inspection. RDS files passed
to declared container or feature-set ingestion are likewise caller-selected
import sources and are outside recipient validation.

## PyBench boundary

Every engine-built `pybench-op-v1` request now includes a required
`path_contract` record. It declares bundle-relative durable paths, explicit-only
external inputs, and trusted-runtime-or-opt-in model loading. Python may receive
the absolute mounted bundle root as runtime context, but paths written to a
portable registry must be relative and resolve inside that root. Receipts and
registry rows remain subject to R-side containment validation.
