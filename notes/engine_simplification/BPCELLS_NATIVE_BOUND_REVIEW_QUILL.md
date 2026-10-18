# BPCells native sorter bound review (Quill)

Source-only review, 2026-10-18. No benchmark or runtime qualification is claimed.
The installed R BPCells 0.3.1 reports source revision
`c293a0a34e653c395c8e9bf9ed3133107324d7b7` (R 4.4.1, x86_64).
The importer, sorter and binary-file source files at that revision are
byte-unchanged at fork HEAD `2e7b83c93954d2ac34e5404952ba74a5e30267d9`.
This review applies to that inspected build, not an arbitrary BPCells backend.

## Resident admission

For double values, `StoredMatrixSorter.h` sets `sort_buffer_elements =
sort_bytes / 16`; its initial six row/column/value arrays total `sort_bytes`.
Each initial chunk contains at most `C = sort_bytes / 32` stored entries.
With `N = ceiling(nnz / C)`, `input_chunk_sizes` and
`output_chunk_sizes` are `uint64_t` vectors. Allowing capacity growth for
both, `64*N` bytes is conservative. Merge fanout is
`floor(sort_bytes / (4*load_bytes))`; its row, column and double-valued
`SliceReader` arrays total at most `sort_bytes`, apart from vector/heap
metadata. The sorter does not retain initial sort arrays during merge.
Its file reader/writer and wrapper buffers, merge heap/vector metadata,
BPCells matrix-open state and R carrier allocations need a separate fixed
allowance. The prototype reserves 4 MiB fixed native overhead and admits
`8*sort_bytes + 64*N <= workspace`, in addition to charged axis/guard
copies (`128*(nrow+ncol) + 4*axis_UTF8_bytes`). This is conservative for
the inspected source structure, not an RSS sandbox or a measurement.
`sort_bytes` and `load_bytes` must be supplied explicitly; the public
importer's 1 GiB default sort buffer is not admitted.

`MatrixOps.h`'s `NonZeroCount` increments once for every stored iterator
entry, including an explicit numeric zero. A one-thread
`BPCells::matrix_stats(..., col_stats = "nonzero")` pass therefore counts
the selected physical entries to be transposed rather than only nonzero
numeric values. Check the sum and every reservation multiplication for
finiteness/exactness before native work. The separate bounded identity
slice and any selected-axis copies remain part of the R-side working
admission; pack code receives neither a native path nor an index handle.

## Logical disk admission

`StoredMatrixSorter.h` writes an initial sorted round, merges rounds using
`deleteWriters(round-2)`, and retains at most two sorting rounds at once.
`binaryfile.cpp` writes double values as 8-byte elements. Row/column
BP128 data use at most 4 bytes per stored element each, plus bounded
per-128-element index/start/offset carriers and padded final blocks.
Final index pointers and shape/name/version files scale with axes; the
row-major transpose can retain the column-major output while its own
temporary and final files are built. The proposed
`128*nnz + 64*(nrow+ncol) + 4*axis_UTF8_bytes + 1 MiB` is a deliberately
loose upper envelope for those simultaneous *logical file lengths* on the
inspected implementation, conditional on a validated core-generated
Matrix Market header and entry count. It is not derived from arbitrary
Matrix Market syntax. Import with no stored BPCells names; authenticated
axis IDs remain external, preserving IDs containing newline or CR.

The source Matrix Market file, session copy, SQLite graph state and any
other independently charged stage files must not disappear from their
existing budgets merely because the adapter reserves this output/scratch
envelope. Reconcile the observed file inventory with the envelope after
import and transpose; remove the owned tree on every success/failure path.

## Limits and portability

The logical bound does not bound physical filesystem allocation. The
prototype's physical slack uses observed block size plus file-count and
preallocation margin, but concurrent filesystem consumers can exhaust
capacity after admission. It must fail and roll back cleanly in that case;
no hard quota or hostile-process RAM guarantee is claimed. The c293
source review must not silently become a new public BPCells version gate:
other builds require their own bound evidence or an explicitly retained
compatible path.

The existing `max_spill_bytes` contract is sampled bounded-operation
admission, not a documented process-global sum across the R broker and
Python writer. The broker must charge its BPCells scratch plus the
parent's session-copy reservation against its scoped R graph budget;
cross-process quota strengthening is a separate contract decision.
This review proposes no schema, canonical identity or Python runtime
change. PyBench remains at `0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e`;
the 44 shared protocol files remain byte-identical at the frozen pair.

Source anchors: `r/src/bpcells-cpp/matrixIterators/StoredMatrixSorter.h`
(constructor, `writeValues`, `openWriters`, `deleteWriters`, `SliceReader`),
`r/src/bpcells-cpp/matrixIterators/MatrixOps.h` (`NonZeroCount`),
`r/src/bpcells-cpp/arrayIO/bp128.cpp` (128-value packing/index carriers),
`r/src/bpcells-cpp/arrayIO/binaryfile.cpp` (raw element and name files), and
`r/R/matrix.R` (`import_matrix_market`, `matrix_stats`), all in
`/home/dirk/Projects/BPCells_python_fork` at the verified c293 source state.
