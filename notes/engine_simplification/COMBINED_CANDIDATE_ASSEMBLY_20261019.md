# Combined candidate assembly — not acceptance

This isolated local branch assembles previously measured components. No primary
branch, official pack, profile or Python source is changed. It is not a new
qualification result and does not inherit a green complete suite.

Selected component sources:

- Selected-fragment getter: a90b23453207fef6a940aa7e093d6f5b1844e90a,
  including the separately corrected relative-WAL test from 06d70ae.
- Graph durable recovery and owned-promotion closure:
  6c1c9ba003fa063698f5a9143f2280916ec7047c; runtime/tests match the
  independently focused f1b61b0f2e1e32cd6c7edd5d8a773496097a13e2.
- Matrix fragment axis JSON: 469d483b465119d8ebb84c5ab8378d794f447f70;
  runtime/tests match focused 1d162f0e4b64c8339c51a87425927aa39f74e06d.

The axis component is applied through its plan, implementation, bounded-gate,
explicit-ownership and measured-disposition commits. Its generated discovery
CSV is deliberately not copied over the graph branch's discovery. The ownership
ledger conflict was resolved by retaining all nine graph rows and all five axis
rows without altering their original decision/source pins. Current discovery
must be regenerated after the combined implementation stabilizes.

Explicitly excluded: unselected registry-observation 2a40ed6 and common-byte
space 011de78 candidates. The changed single-file space candidate b38b38b is
still undergoing its first matched measurement; its 30 focused passes do not
authorize integration or a performance claim. No no-load runtime-attestation
change is implemented; its provenance meaning awaits a Controller decision.

Historical whole-workflow 171.124s, graph, mixed and typed-space misses remain
unwaived. Component timing improvements are not overall acceptance. Final
combined source/protocol/documentation checks, one coordinated complete suite,
real Xenopus acceptance and independent reviews remain distinct future gates.
