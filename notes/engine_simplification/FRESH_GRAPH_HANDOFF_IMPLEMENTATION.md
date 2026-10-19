# Private fresh-native graph custody

The prospective budgets and measured parent remain those frozen in
`FRESH_GRAPH_STAGE_HANDOFF_PARENT_BASELINE.md`; no limit is reset here.

An eligible one-graph native R record retains its **first independently decoded
and fully validated** graph stage until ordinary output construction. The
producer still finishes and discards normally. Early graph grant/seal/descriptor
checks remain; the actual graph import moves to the end of complete record
validation, after ordinary sibling payload and other capability checks. This
can change first-error precedence when multiple payloads are invalid; it does
not waive any check. Recovery, ordinary retained validation, Python, additional
graph stages and ineligible closures use the original independent import path.

The retained stage is closed and reopened immutable read-only **before** its
existing SQL semantic identity check. Actual byte hashes bracket that check.
Transport and compact record inventory are observed before import; original
executor request/receipt identities remain authoritative. Both actual stage
bytes and complete record inventory are checked after the existing reopen hooks
before transfer. Only the intentionally updated transition state is excluded
from the byte ledger: its contained, size-bounded exact reopened structure is
checked separately. Root path/device/inode and child path containment remain
part of the private observation. Original payload size admission precedes any
new raw transport hash.

This is invocation-local custody, not a stored freshness verdict or a graph
identity change. The stage is owned before hooks, discarded on failure and
transferred once on success. Existing graph resource budgets remain unchanged;
ordinary small sibling payloads retain their separate admission. There is no
new ABI, shared protocol, pack authority, executor or public interface.

The private proof retains COW copies of stage metadata and byte observations;
the mutable stage environment is never its own freshness authority. The
import's pre-semantic byte proof is lexical until validation succeeds. Stage
seal, observations, budgets and completion must remain equal to their private
validated copies at transfer, independently of the actual file-byte proof.

Proof traversal uses the minimum of grant and every live connection policy,
including inherited copy reservations. It subtracts 524288 bytes from the
existing native-name allowance before traversal, with the original caller
default reserve of zero. No headroom means ineligible/full original import,
not a new payload rejection. Only <=128 entries and <=8192 total UTF-8 name
bytes enter the additional proof carriers. A conservative framing ledger is
`4 * (32768 + 2 * 8192 + 128 * 512) = 458752` bytes, below the reservation:
fixed stage/root/seal metadata, both name carriers, per-entry vectors/SHA/DF
overhead, and concurrent/COW scratch. Existing native traversal allocations
are charged separately. The one-MiB side-file criterion bounds extra hashing,
not graph memory or a global R/RSS quota. Later proof invalidation rejects;
it never obtains a new baseline from changed bytes or mutable stage metadata.

Six new focused contracts cover actual single import versus retained full
revalidation, promotion, original identity binding and tampering, both hook
failures and byte mutations, immutable-stage mutation, eligibility and
pre-hash size admission, mixed sibling failure, cleanup and retry. Their presence
is not execution evidence. Clean installed qualification and matched workflow
measurement remain required before selecting this candidate.
