# Operation-pack ABI v2 atomic transition state machine

Status: **PROPOSED, NON-RUNTIME PLANNING ARTIFACT**.

Inputs: scworkbench `368c864126b2e60880a81fab8dc0abbd34cf27a9`;
Quill specification `eb5334a7bec73490ccfbf106f83ba91b1ab39fb8` and handoff
`8f73acebe833606e5d733988cb3d253720fcd333`; Sable audit
`f05ce0923d2b9bfbd7cfd8447208a674fb21319a`.

The engine owns this state machine. Packs observe a single request and may
return a receipt; they cannot advance durable state.

## States and invariants

| State | Durable record | Required invariant | Permitted successor |
|---|---|---|---|
| `resolved` | transition ID, source/checkpoint and exact pack/definition/input identities | committed state unchanged; no writer exists | `preflighted`, `aborted` |
| `preflighted` | canonical requirement set and complete disposition report | no network/install; all required probes passed | `staged`, `aborted` |
| `staged` | private generation, output IDs/grants, lease and preimage fingerprint | generation is unreachable from getters | `dispatched`, `aborted` |
| `dispatched` | request/capability identities and one dispatch attempt | capability is single-use and bound to generation | `receipt_received`, `aborted` |
| `receipt_received` | raw closed receipt or process-failure diagnosis | no receipt claim is trusted yet | `audited`, `aborted` |
| `audited` | recomputed output, mutation, containment and receipt identities | exact declared closure exists; no undeclared mutation | `publishing`, `aborted` |
| `publishing` | fsync'd journal, all destination preimages, audited receipt identity, commit marker plan | only core can touch destinations | `published`, `aborted` |
| `published` | atomic SQLite commit marker plus payload/registry/provenance/receipt closure | all transition outputs visible together | `reopened`, `aborted` |
| `reopened` | fresh-handle validation receipt | getters reproduce all audited identities | terminal success |
| `aborted` | stable error phase/code and cleanup proof | committed source/recipient equals preimage | terminal failure, retry uses a new transition ID |

`resolved` through `audited` may be represented by a durable core journal so
host recovery can clean private state. They never make analytical outputs
getter-visible.

## Normal transition

1. **Prepare/resolution.** Under the source checkpoint generation, core resolves
   exact pack and operation identities, typed inputs, dimensions, cell/feature
   order, ancestry, model linkage, effective parameters, and promotion closure.
   It allocates all output and registry-request IDs. A generation/head change
   invalidates the transition.
2. **Preflight.** Core starts from the operation's complete declared set. It
   applies parameter selectors and resolves any input-metadata selector from
   the already resolved retained input, binding its input identity, metadata
   field/value, ecosystem, installed name/version/artifact and probe evidence.
   Core performs only allowlisted, read-only dependency probes and hashes the
   declared set, selected set, dynamic resolutions and result. Pack-level or
   ambient dependencies cannot participate. Missing/incompatible requirements
   fail before stage allocation or dispatch.
3. **Stage.** Core creates a private same-filesystem generation, records its
   identity and committed-state preimage, and mints the single-use named
   capability. Relative roots are resolved beneath the generation with
   no-follow containment.
4. **Dispatch.** Core first rereads every dynamic-provider field against the
   same retained input identity and aborts if it is absent, empty, malformed or
   changed. The R adapter then executes in an isolated staging context; the
   Python adapter sends canonical `pybench-op-v3`. Each gets identical logical
   readers/writers. The supervisor owns timeouts and process death.
5. **Receipt.** The adapter returns exactly one closed success or error receipt.
   Missing, duplicate, malformed, incomplete, or mismatched receipts abort.
6. **Audit/validate.** Independently of pack code, core inventories the complete
   stage and database delta; recomputes every content, order, ancestry,
   containment, linkage, metadata and mutation identity; checks exact output
   and registry-request closure; and compares the canonical receipt.
7. **Publish.** Core writes a journal and durable destination preimages before
   moving/copying payloads. Registry rows, provenance, transition receipt, and
   the commit marker are one SQLite transaction. Publication never exposes an
   output without its siblings and complete receipt/provenance closure.
8. **Reopen.** A fresh read-only handle loads each output through public getters
   and revalidates the source/head, payloads, identities, linkage, lineage, and
   receipt set. Only success moves to `reopened`.

## Rollback and zero-residue proof

For failures in `resolved` through `audited`, core consumes/revokes the
capability, removes the private generation, and proves that the committed
fingerprint, catalog, registries, provenance, active/head state, payload tree,
and published receipts equal the recorded preimage.

For failure in `publishing`, rollback restores **all** preimages, including
created, replaced, deleted, and nested payload paths, then rolls back/removes
all registry, provenance, transition and receipt rows. Payload removal alone is
not sufficient. Cleanup is idempotent.

For failure in `published` or during reopen, core uses the still-retained
journal/preimages to reverse the complete publication before reporting
`PYBENCH_REOPEN_VALIDATION_FAILED`. The transition cannot remain published with
an unvalidated receipt.

## Interrupted recovery

On lease recovery, the core locks the transition and branches only on durable
evidence:

- `resolved` through `audited`: mark `aborted`, revoke capability, discard the
  private generation, verify zero residue.
- `publishing`: verify the commit marker, audited receipt identity, exact
  SQLite closure, and every destination payload identity. If all match, finish
  cleanup and enter `published` exactly once. Otherwise restore every preimage,
  roll back rows, enter `aborted`, and verify zero residue.
- `published`: perform fresh reopen. Success enters `reopened`; failure performs
  full publication rollback and enters `aborted`.
- `reopened` or `aborted`: no mutation. Duplicate recovery is a no-op.

Filesystem presence, row presence, receipt presence, or “first matching row”
alone is never sufficient to select success. A complete conjunction is
required, making recovery independent of row and directory enumeration order.

## Promotion after successful transition

Promotion is not a transition state. It is a later core-owned transaction over
a valid `reopened` transition. Core expands the requested terminal to the exact
manifest closure, verifies the staged and destination generations, then commits
payloads, registry/provenance rows, materialization links, and all terminal and
replay receipts atomically. A promotion failure restores the recipient and
leaves the reopened source transition intact and retryable. A durable promotion
receipt makes repeat promotion an idempotent read of the same result.

## Fault-boundary result

| Boundary | Required diagnosis | Observable result |
|---|---|---|
| before dispatch | pack/input/dependency error | no stage residue and no catalog publication |
| runner or process death | `PYBENCH_PROCESS_FAILED` | private generation removed; committed preimage exact |
| receipt validation | `PYBENCH_RECEIPT_MISMATCH` | all sibling outputs discarded |
| independent audit | `PYBENCH_OUTPUT_INVALID` or `PYBENCH_OUT_OF_SCOPE_MUTATION` | no publication |
| before first payload | `PYBENCH_PUBLICATION_FAILED` | destination unchanged |
| between payloads / before SQLite commit | `PYBENCH_PUBLICATION_FAILED` | all payload and row preimages restored |
| after SQLite commit / before cleanup | recovery recognizes exact commit or fully restores | all outputs once or none |
| fresh reopen | `PYBENCH_REOPEN_VALIDATION_FAILED` | publication completely reversed |
| promotion | `PYBENCH_PROMOTION_FAILED` | recipient unchanged; source transition retryable |

The future adversarial fixtures and detection owners are enumerated in
`notes/operation_pack_abi_v2_conformance_matrix.csv`.
