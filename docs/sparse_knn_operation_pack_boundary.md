# Sparse kNN operation-pack boundary

`knn_neighbors` and `knn_pseudobulk` are owned by the explicitly activated
`scwbRepresentation` operation pack. They are not core operations and their old
`wb_op_*` wrappers have been removed.

ABI v3 resolves `query_cells` and `candidate_cells` through the core cell
selector contract before dispatch. It grants ordered, identity-bearing typed
space reads for each axis. `candidate_cells = NULL` selects the declared bundle
cell universe; when `include_query = FALSE`, all query cells are removed from
the candidate axis before its identity is signed. Empty, foreign, duplicate,
stale, or reordered axes fail closed.

The sparse membership grant permits at most `min(k, eligible candidates)`
unique candidate rows per query. Rows are ordered by authenticated query order
and then one-based neighbor rank; distances must be finite and nonnegative.
The neighbor `obs_table` and distance `cell_vector_family` carry the same exact
edge ledger and must agree before the promotion transaction can publish either.

For pseudobulk, the accepted edge ledger additionally binds the requested
feature axis, query order, and `sum` or `mean` aggregation mode. Matrix access
is limited to authenticated candidate cells and feature chunks. The
`feature_table` and distance family form one promotion closure, so mismatch or
partial output leaves no analytical residue.

No bundle path, database handle, SQL surface, or committed payload path crosses
this boundary. A bundle containing promoted outputs remains inspectable and
valid without the pack; new execution requires explicit pack activation.
