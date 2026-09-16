# Proposed ABI v2 cell-set-family admission capability

Status: review required; not a live protocol change
Scope: generic core-registry capability required before `winner_cell_sets` can
leave scworkbench core

## Confirmed gap

The accepted `core_registry_request` / `cell_set_admission_v1` capability is a
single, statically declared, write-once output. Its payload contains only one
`name` and one non-empty `cells` vector. The output closure is an exact
bijection with manifest grants.

That shape cannot express the `winner_cell_sets` contract:

- the number of winner-derived sets is data-dependent and may be zero;
- a single execution may create several independently named sets;
- add versus replace is an explicit invocation policy;
- all names and memberships must be validated before the first registry row is
  written;
- the entire family, its manifest terminal and promotion receipts must commit
  or roll back together.

The existing transition retains an authenticated registry-request payload, but
`.wb_operation_pack_v2_runner()` returns only ordinary outputs to the session.
No registry request is bound into the staged run or promotion closure, and no
request is applied by the promotion transaction. A successful single request
therefore changes no governed cell-set state.

Executable evidence is in
`tests/test_operation_pack_v2_contract.R::test_operation_pack_v2_cell_set_family_capability_gap_contract`
and
`tests/fixtures/operation-pack-v2-cell-set-family-capability-gap.json`.

## Minimal generic amendment

Add one generic output contract; do not add a GenePrograms-specific callback:

```text
category:        core_registry_request
kind:            cell_set_family_admission
storage_profile: cell_set_family_admission_v1
writer:          request_cell_set_family_admission
```

The writer accepts exactly one family payload:

```json
{
  "sets": [
    {
      "name": "set:winner_alpha",
      "cells": ["cell_1", "cell_4"],
      "description": "Winner cells for alpha",
      "selection_rule": "winner == 'alpha' && passes_pruning == TRUE"
    }
  ],
  "mode": "replace",
  "source": "cell_vector_winners"
}
```

`sets` is an ordered array and may be empty. `mode` is exactly `add` or
`replace`. The pack supplies requested scientific names, memberships,
descriptions and selection rules; core supplies allocation, universe lookup,
canonical ordering, collision checks, lifecycle authority, provenance binding
and durable publication.

## Required core semantics

1. Validate the complete payload before staging any registry mutation:
   canonical unique names, non-duplicated membership, every member in the
   bundle universe, canonical bundle cell order, mode, collision policy and
   provenance inputs.
2. Bind the authenticated family request to the session run and its promotion
   group. It is not a terminal artifact and is not applied during pack
   execution.
3. Include the family request in the terminal manifest's promotion closure.
4. In the existing promotion SQLite transaction/workspace, apply the complete
   family, insert the terminal artifact/entity/provenance bindings and persist
   the complete transition/replay receipt set as one observable commit.
5. On validation, staging, receipt, publication or commit failure, retain no
   family member, manifest, analytical binding or promotion receipt. Retry must
   be safe.
6. A zero-set family is a valid authenticated no-op with a complete manifest
   and receipt, not an omitted required output.
7. Strict replay reconstructs the same family payload and checks exact ordered
   membership identities. Pack-free recipient inspection reads core-owned
   registry state and receipts without loading pack code.

The receipt descriptor needs a family content identity plus one ordered record
per requested set containing its canonical name and exact ordered-membership
identity. It must never select an arbitrary first record.

## Protocol and cross-repository impact

This amendment changes the shared language-neutral ABI surface. It requires a
focused Controller decision, Quill parity implementation and Sable review
before Phase 3B extraction resumes. At minimum the following shared files need
synchronized schema changes:

- `operation-pack-v2.schema.json`
- `operation-pack-transition-request-v2.schema.json`
- `operation-pack-transition-receipt-v2.schema.json`

PyBench must add the same family writer payload, request/receipt descriptor and
negative cases. Existing `cell_set_admission_v1` remains unchanged for the
single-set conformance contract.

## Required acceptance fixtures for the amendment

- multiple winner sets with deterministic name and cell ordering;
- zero winner sets;
- duplicate requested names;
- out-of-universe and duplicate members;
- existing-name collision with add mode;
- replacement disabled and replacement enabled;
- partial validation failure before any write;
- fault between family-member writes, after SQLite writes before commit, and
  during payload publication;
- promotion, reopen, strict replay and pack-free recipient validation;
- malformed request/receipt, missing family output and duplicate family write;
- row-order-independent family and receipt identities.

Every negative case must preserve the source-only destination fingerprint and
leave zero registry, artifact, provenance, lifecycle or receipt residue.
