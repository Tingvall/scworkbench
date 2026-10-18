# Bounded typed-space prototype: prospective budgets

Base e9e561c940b482138456854f67970eca256966e7; isolated prototype only.
No benchmark or whole suite is authorized here. Before implementation:

- Symbolic file-backed typed-space inputs retain zero coordinate values in
  their bound primitive; axes/metadata remain O(axis length).
- Scientific temporary blocks target <=min(32MiB, ordinary configured guard),
  using conservative 64 bytes/element admission for JSON construction, with
  <=512 rows per semantic hashing read. No guard is raised.
- Ordinary typed-space callbacks read at most their declared cells and all
  declared dimensions; no whole scientific-data verification occurs per call.
- Full physical/provenance authentication remains at existing lifecycle
  boundaries. Semantic authority passes are constant with partition count.
- Both existing digests preserve bytes exactly: hydrated generic envelope
  (column-major flattened matrix) and space_slice.content.v1 (row-major rows).
  Frozen independent encoders and exact SHA comparison are mandatory.
- Caller-supplied coordinates and existing Python transport remain unchanged;
  any path not converted to bounded reading must be explicitly identified.

No throughput, total RSS, end-to-end boundedness, new backend support or final
qualification claim follows from source inspection or these prospective budgets.

## Implemented scope and resource ledger

Trusted native R symbolic HDF5 inputs use a fresh plan map owned by the runner,
not attributes supplied on incoming primitives. Plans retain axes/labels and a
charged row lookup, never coordinates. Their callbacks expose only fresh typed
blocks. No plan, callback, connection, path or handle enters JSON, receipts,
retained runs or checkpoints. Caller-supplied values and existing Python JSON
transport are unchanged. Existing non-POSIX and legacy-storage paths remain
materialized compatibility paths, not claimed bounded here. PyBench has shared
schema/receipt parity but no executable bounded read_typed_space transport;
this change adds no Python capability or wire field.

Registry byte extents/counts are queried before loading its full row. The plan
verifies the registered producer file SHA before axis decode. HDF5 cell IDs are
read in admitted chunks using the canonical core-cell UTF-8 maximum, validated
against narrow SQL membership queries, and retained charges grow with actual
bytes. Dimension labels use the precharged registry JSON bound and chunked
physical comparison. Canonical order is selected by SQLite ORDER BY rowid,
never narrowed to R integer/double rowids. File metadata and registry guards
operate between calls; independent final authentication still computes actual
source bytes. Stats/timestamps are not content authority.

This relies on the supported ordinary producer invariant: public R publication
validates canonical-cell membership before writing; Python's HDF5-v1 producer
uses UTF-8 VLEN axes with the same registered axis contract. The HDF5 library
allocates a selected VLEN element before R can check its length. This is NOT a
hard quota against arbitrary hostile HDF5 plus deliberately rehashed registry
metadata, nor an expansion of recovery/transfer/deep-validation guarantees.
Observed checksum/axis/registry disagreements always reject.

One conservative8MiB active HDF cache/chunk allowance is shared across an
invocation's plans (not multiplied by fields). It covers normal producer chunks
<=1024x16 float64 (128KiB) plus library cache/buffer headroom. This is a
source-informed reservation, not an absolute RSS guarantee across rhdf5/HDF5
versions. Existing ordinary/graph budgets are never raised. Metadata and
response blocks share the existing broker budget env; actual scoped graph
policies debit metadata, active blocks and scratch before decoding/writing and
restore on every exit. Tiny policies unable to admit these buffers reject.

The envelope consumes each source value once in bounded row/dimension tiles
and writes an owned column-major numeric spool. Its two existing canonical
digests then read only that spool. Semantic identity streams row-major values;
very wide rows are dimension-tiled rather than fully decoded. Canonical numeric
tokens need at most22 bytes;32/value covers token and separators. Envelope
peak raw8/value plus one JSON preimage<=32/value is admitted conservatively as
72/value; metadata uses a counted escaped UTF-8 upper bound before encoding.
Temporary files/connections are owned before opening and removed on errors.
There is no whole JSON scientific preimage string or per-source row-list.

Full file passes remain at lifecycle boundaries, not per callback. The native
fixture observed8 source file hashes for chunk8 and8 for chunk2, with9 versus33
reader calls. This proves constant partition cost, not optimal boundary count;
duplicate-boundary consolidation is separately pending. No benchmark was run.

## Focused evidence and corrections

All logs and numeric sidecars are retained in the coordinating task evidence
directory. Early synthetic-fixture failures are retained: missing manifest
reader/kind fields, wrong cell-vector constructor usage, fractional values
passing through the existing character-valued cell-vector constructor, and the
Python fixture missing the frozen HDF5 transpose/reversed-chunk portability
boundary. These were fixture corrections, not runtime relaxations. A zero-row
oracle fixture's paste0 behavior was similarly corrected.

`typed_space_final_focused.log/.exit` reports7 discovered/executed/passed,
0 skipped/failed, exit0 on the installed precursor. It includes independent
old dual-preimage oracles, actual native dispatch, receipt/publication faults,
zero residue/retry, source mutation and foreign/reordered/duplicate/oversized
selection rejection, metadata resource failure/retry, cleanup and Python VLEN
Unicode producer parity. The final source-review descendant additionally covers
negative and >2^53 SQLite rowids, shared native HDF allowance and explicit
session cleanup; final exact-pin focused results must be appended before audit.

G1/G2/derived-fitted model metadata hydration is a separate source-confirmed
framework MISS, not merely an unmeasured path or an accepted waiver. It will be
repaired in a distinct descendant using the same generic metadata/streaming
boundaries, with exact historical parent/linkage/identity checks retained.
