# Phase 4E sparse kNN boundary freeze

`phase4e_sparse_knn_boundary.json` is the language-neutral v1 contract frozen
before any shared ABI-v3 protocol byte changes. It assigns selector resolution,
axis/source authentication, bounded typed exchange, receipt validation and
atomic publication to core. The pack owns distance search, chunking, neighbor
ordering within the authenticated boundary and sum/mean aggregation.

The wire contract retains existing terminal primitives. Sparse membership is
represented by an authenticated edge ledger shared by the neighbor
`obs_table` and distance `cell_vector_family`; pseudobulk binds its
`feature_table` rows to that same accepted ledger. No bundle, SQL or committed
payload path is granted to a pack.
