# Core, operation packs, and the SDK

scworkbench owns portable bundles, primitive contracts, authenticated access,
sessions, atomic publication, provenance, and recipient inspection. Operation
packs own scientific methods. Clients orchestrate those contracts; they do not
implement a second engine.

## Choose Your Route

| Task | Start here |
| --- | --- |
| Analyse an existing bundle | [Operator guide](AGENT_OPERATOR_GUIDE.md), then [recipes](RECIPES.md) |
| Import data or metadata | [Metadata import](METADATA_IMPORT.md) and the source-distributed ingestion guide |
| Write a reusable method | Installed [SDK guide](../sdk/operation-packs/GUIDE.md) and executable tutorial |
| Extend an engine capability | [Engineer guide](AGENT_ENGINEER_GUIDE.md) and the primitive exchange inventory |
| Transfer or inspect results | Operator guide and the source-distributed recipient audit guide |

Find these resources without a source checkout:

```r
library(scworkbench)
system.file("onboarding", "README.md", package = "scworkbench")
system.file("sdk", "operation-packs", "GUIDE.md", package = "scworkbench")
system.file("standard_profile", "README.md", package = "scworkbench")
wb_operation_pack_capabilities()
```

## Installation Is Not Activation

Core alone exposes five operations: `feature_set_import`,
`feature_set_namespace_transfer`, `cell_set_derive`, `metadata_cell_vector`,
and `slingshot_adopt`. The optional standard profile adds 56 operations from
seven pinned packs, for 61 total after explicit process-local activation.

| Pack | Method area | Operations | ABI |
| --- | --- | --- | --- |
| scwbStatistics | Statistical association | 6 | v2 |
| scwbGenePrograms | Gene programs and signatures | 10 | v3 |
| scwbRNA | RNA preprocessing | 4 | v3 |
| scwbRepresentation | Representations and neighbours | 6 | v3 |
| scwbTrajectory | Trajectory analysis | 25 | v3 |
| scwbLatent | Model-bound latent spaces | 4 | v3 |
| scwbATAC | Motif activity | 1 | v3 |

Install the profile using its source-verifying installer and keep its instance
receipt. Follow the profile README for activation in each new R process. For a
single independently installed R pack, the explicit trust boundary is:

```r
wb_operation_pack_validate("myMatrixPack")
wb_operation_pack_load("myMatrixPack")
wb_operation_packs()
wb_list_ops()
wb_op_interface("mymatrix::matrix_cell_sum")
```

The example names above belong to a new SDK scaffold, not an official pack.
Use qualified names from the activated catalog rather than guessing historical
aliases. Installed instance identities can differ between builds of identical
sources; package versions alone do not establish replay compatibility.

## Primitive Exchange

The eleven kinds are `matrix`, `space`, `space_2d`, `cell_vector`,
`cell_vector_family`, `relation_family`, `feature_table`, `obs_table`,
`model_ref`, `path_2d_family`, and `space_path_family`.

A kind identifies the data shape, not unlimited authority. A declaration also
specifies profiles, axes and order, missing/empty-value rules, source bindings,
reader schedules, output cardinality, and publication closure. Registry changes
are separate authenticated requests, not new primitive kinds or permission to
write registry tables.

For pack authors the workflow is:

1. Declare typed inputs, parameters, outputs, dependencies, and grants.
2. Read admitted primitives through invocation-scoped callbacks.
3. Compute the scientific result.
4. Write declared primitive outputs and finish any required handles.

Core resolves storage through getters and supplies private typed readers.
Packs must not reopen the bundle, access SQL, infer payload paths, or construct
receipts. A public export is not necessarily a lawful runner API: low-level
writers can be transaction-restricted. The SDK's `interface.json` and
`callbacks.json` identify the authoring surface and callback contract.

## Central Slicing and Chunking

Declare the typed-slice axis, chunk-size parameter/default, and call discipline.
Use the supplied reader and `wb_operation_pack_map_partitions()` rather than
implementing storage slicing. Core authenticates source content, axes, order,
partition coverage, and the final partial partition. Follow the discipline of
the particular grant; not every reader is single-use.

The pack owns its algorithm and any scientifically required reduction/merge.
Chunked reads bound input blocks, not total algorithm memory. Retaining every
block or materializing the full selection remains a materializing algorithm
and must be described and tested as such.

## Backend and Trust Boundaries

New R packs start with the ABI-v3 SDK scaffold. Existing ABI-v1/v2 contracts
remain distinct supported contracts, not automatically rewritten manifests.
Pack ABI versions and Python execution protocol versions are separate: a v3
Python pack uses `pybench-op-v4`.

Shared schemas and matching identity vectors do not establish Python runtime
support. Check the SDK capability catalog's backend statuses before choosing a
grant. Advanced R capabilities may lack Python callbacks or fail Python
admission. R-backed packs using private Python computation still have an R
authority boundary; they are not Python-backed packs.

Pack code, installers, tests, and model deserialization are trusted executable
code. Checksums authenticate content; they are not host-code isolation or proof
that a serialized model is safe. Never retain callbacks or private paths after
an invocation. Source installation of the R SDK requires a C toolchain; both
scaffold generators require supported Linux no-replace publication and fail
closed elsewhere.

## Evidence and Validation

Test the method against a scientific oracle, then test installed activation,
authenticated inputs, publication closure, rejection before dispatch,
rollback/retry, promotion, relocation, and pack-free recipient inspection.
The SDK separates static, installed, and contract checks; executing checks
require explicit trust. A skip is not a pass.

Use focused tests during development and a coordinated complete qualification
for the frozen integration candidate. Do not rerun unrelated complete suites
for a prose-only correction, or attribute parent evidence to a changed tree.
Record exact pins, executed coverage, numeric exits, and limitations.

Recipients can inspect promoted primitives and provenance without installing
the producing pack. Execution or replay still requires the compatible pack
and runtime. CPU tests do not qualify GPUs, ARM64, clusters, or every container.
An older SIF does not acquire a newly installed source SDK automatically.

The installed [SDK capability catalog](../sdk/operation-packs/CAPABILITIES.md),
[recipes](../sdk/operation-packs/RECIPES.md), and
[primitive exchange inventory](../phase8/primitive_exchange_inventory.csv)
provide the detailed supported boundary. If an existing primitive cannot be
exchanged lawfully, stop with a minimal reproducer and propose a generic
capability; do not add operation-name exceptions or weaken identity checks.
