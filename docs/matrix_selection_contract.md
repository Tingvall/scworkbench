# Matrix selections and dense admission

`wb_slice()` and `wb_matrix_read_features()` preserve the requested order and
repeat numerical rows and columns for repeated IDs, independently of fragment
layout. They return the same values as ordinary matrix indexing of the logical
matrix. Sparse reads remain sparse. BPCells rejects repeated physical indices;
the fragment reader selects unique physical indices and expands their values
through sparse/base indexing after materializing the selected block.

This intentionally corrects the old named-position-map behavior: later repeated
positions were left as fabricated zeros (or NA in NA mode). The original test
expectation is retained in Git at parent `c6c5f7ce3030392fb47930988fc5caa76e16e3a8`,
in `tests/test_public_sparse_matrix_getter_contract.R`. A single-fragment
`wb_slice()` previously rejected repeats through BPCells while multiple fragments
returned the incorrect values. Neither result was conventional repeated indexing.

Empty selections return empty axes. `wb_slice()` still rejects unknown requested
IDs; the lower-level `wb_matrix_read_features()` retains its missing-entry fill
policy: zero by default, or NA when `missing="NA"`. Real stored zeros remain zero.
Fragment precedence, including overlapping historical fragments, is unchanged.

The NA mode returns a dense double matrix. Before allocating that output, the
reader estimates its size using floating-point dimensions and compares it with
`scworkbench.max_dense_materialize_mb` (default 256 MiB). A non-finite estimate
refuses allocation. Each selected fragment block, including repeated positions,
is a subrectangle of the admitted output, so its dense conversion cannot exceed
that per-allocation bound. This guard does not bound total RSS or the sum of live
objects. Ordinary sparse reads do not acquire a new allocation cap.
