# Phase 4D contained-model and 2D merge capability ledger

This ledger freezes the language-neutral additive ABI-v3 contract agreed by
Forge and Quill before shared protocol bytes changed. Documents which do not
declare these capabilities retain their existing canonical bytes and
identities. The contract is generic: no rule dispatches on an operation name.

## Manifest declarations

- A `model_ref` output may declare `contained_model_policy` with policy
  `staged_contained_model_tree_v1`, engine, model type, one safe POSIX-relative
  primary path, source-space input, paired `space_2d` output, UTF-8 path-byte
  lexical order, maximum file count, and maximum total bytes. The source must
  be a `space`; the paired output must share its promotion group. The pack
  receives a private staged-tree writer only for this declaration.
- `contained_model_reads` declares a named
  `read_contained_model_payload` capability over a `model_ref`, its expected
  engine/model type, linked source-space input, verified-private-copy access,
  and exactly-once call discipline.
- A `space_2d` publication declares the generic
  `authenticated_space_2d_publication_v1`, naming its target-ID parameter,
  authoritative cell-axis input, model binding, mode, and promotion-group
  transaction scope. Its two closed mode tuples are `add_only_v1` (fit, bound
  to a sibling model output) and `selected_merge_or_full_replace_v1`
  (transform, with overwrite parameter and authenticated model input). The
  candidate remains an ordinary `write_space_2d` output; the pack never owns
  the add, merge, or replacement.

## Contained tree and identities

Write trees live only below `outputs/<output>/model_tree/`; private input
copies live below `model_payload_reads/<read>/tree/`. A tree contains nonempty
regular files only. Absolute, empty, dot, parent, backslash, duplicate-normal,
non-UTF-8, symlink, socket, device and FIFO entries fail closed.

Entries are ordered by UTF-8 path bytes and contain `path`, integer `size`, and
raw-file `sha256`. The closed manifest uses schema
`scworkbench.operation_pack.contained_model_tree_manifest.v1` and records
engine, model type, primary path, file count, total size, entries, and a scoped
self-identity. Its payload-manifest identity uses
`scworkbench.operation_pack.payload_manifest.v2` over the unscoped tree
identity and ordered `scworkbench.operation_pack.payload_file.v1` entry
identities. Physical byte identity is not replay equivalence.

## Request grants

- `contained_model_write_grant.v1` binds the output, engine/model type,
  primary path, private root, limits, exact source-space descriptor/content/
  cell axis, normalized selected dimension count/order, and paired-space name,
  allocated ID, expected `n x 2` dimensions and cell order. The selected
  dimension linkage is persisted in core-owned model metadata. The model's
  existing expected linkage binds its source input; the publication closure
  binds model and embedding.
- `contained_model_read_grant.v1` binds the model input descriptor, content,
  model linkage, contained payload, exact tree manifest, private-copy root,
  query source-space descriptor and normalized selected dimension count/order,
  which must equal the retained fitted-model linkage before dispatch; distinct
  query-space content is permitted. It also binds access policy and call
  discipline. Grant identities appear in the execution capability and its
  closed reader-grant union. The reader exposes ordered entries, primary path,
  bounded reads, and the private path for an authenticated entry; never the
  bundle path. Core validates before and after dispatch.
- `space_2d_publication_grant.v1` binds the exact preimage, selected unique
  cells, recipient axis, expected final order, and exact source model. Fit uses
  `add`, requires an absent preimage, and binds the sibling model write by
  output name, allocated ID, engine, model type and source linkage without a
  grant-hash cycle; the sibling model and embedding share one closure.
  Transform binds an authenticated model input and overwrite authority:
  absent targets use `add`; present targets whose complete axis is selected
  use `full_replace`; other present targets use `selected_cell_merge`. With
  overwrite false, selected/preimage overlap is rejected before dispatch.
  Final order is recipient canonical order filtered to the union of old and
  selected cells, so untouched relative order and coordinates are preserved.

## Receipt observations

- A contained-model output records a
  `contained_model_tree` observation binding its manifest/payload identities,
  source-space binding and paired-space observed descriptor, with status
  `validated_not_published`.
- `observed_contained_model_read.v1` records the exact grant/input/linkage/
  payload identities, engine/model type, exactly-one use and unchanged status.
- `observed_space_2d_publication.v1` binds the grant, mode, preimage, source
  model, selected and final axes, candidate descriptor and complete closure,
  also only as `validated_not_published`. Packs cannot claim durability.

## Authority, atomicity and failures

Core owns containment, identities, linkage, merge construction, registry and
payload writes, provenance and atomic promotion. The pack sees no bundle, SQL
handle or arbitrary bundle path. Core closes and revalidates every tree and
publication preimage before commit. A fault leaves either the source-only state
or the exact old space/model state, no analytical receipt or binding, no
published candidate payload, and a retryable target.

Malformed declarations fail with
`OPERATION_PACK_MANIFEST_SEMANTICS_INVALID`; corrupt/missing/substituted input
bytes with `PYBENCH_INPUT_IDENTITY_MISMATCH`; capability, engine, linkage,
selection or pre-dispatch preimage mismatches with
`PYBENCH_CAPABILITY_MISMATCH`; escapes, special entries and undeclared files
with `PYBENCH_OUT_OF_SCOPE_MUTATION`; invalid or incomplete output trees and
candidate coordinates with `PYBENCH_OUTPUT_INVALID`; receipt/use mismatches
with `PYBENCH_RECEIPT_MISMATCH`; and locked publication drift or faults with
`PYBENCH_PUBLICATION_FAILED`.

## Replay policy and Python parity

`umap_fit` coordinates use `cell_aligned_embedding`; its model uses
`loadable_reference`. Neither policy claims serialized-byte, prediction,
geometric, behavioral, or biological equivalence. Python parity is limited to
the additive shared schemas, canonical identity fixtures, semantic admission,
grant/receipt validation, generic private tree readers/writers and adversarial
fixtures. PyBench does not acquire scientific UMAP code or committed-state
mutation authority.
