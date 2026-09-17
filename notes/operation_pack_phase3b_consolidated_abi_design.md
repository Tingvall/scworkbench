# Phase 3B consolidated ABI successor design ledger

Status: **CORRECTED JOINT DESIGN; SABLE REVIEW REQUIRED BEFORE SCHEMA FREEZE**

This is the joint Forge/Quill design checkpoint required before any shared
schema is frozen. It contains no runtime implementation and authorizes no
GenePrograms migration. The feature-set-registry pair has independent
acceptance. Controller commit `9c784db1097c8d671ad98ab610f6624787b586c3`
supersedes the previously accepted operation-shaped chunk schedule, merge, and
summary-finalizer design. Sable must accept this corrected ledger before the
successor protocol is frozen or implementation resumes.

## Inputs and gates

- Survey source: scworkbench
  `e601537e01f1ef381b1e0abb965a50ae5c6cf16e`.
- Surveyed implementation references only: scworkbench
  `dbe6bafb8290ddaca8066cec46615409bff3bdde` and PyBench
  `7f2c1df6fe04dfe7eecfa86241de22f7a8b1c945`.
- Independently accepted registry composite and implementation base:
  scworkbench
  `957af89e8825f5c1b299e0703eba5e2312a16c8c` and PyBench
  `3e02ea266862adc3ffa96c5d0d99e817f1e43e06`; Meridian-9 audit commit
  `969b6d5299496f06cee126aef6919eb5960c1aec` records `ACCEPTED` for this exact pair.
- Implementation starts from exactly that accepted pair.
- Sable accepted the cardinality and ancestry portions on 2026-09-17. Its
  earlier chunk disposition is superseded by the controller correction and is
  not schema-freeze authority for the typed reader below.

The amendment is generic. No rule selects an operation by name, pack namespace,
or implementation language. A pack opts into the successor explicitly; no v1
or v2 document is reinterpreted.

## Common identity and compatibility rules

All new identities use the existing byte-level
`scworkbench.operation_pack.canonical_json.v1` canonical JSON and SHA-256
algorithm. Map keys are UTF-8 byte-order sorted, arrays remain ordered, JSON is
compact UTF-8 with no terminal newline, integers remain integers, and finite
non-integral numbers use the existing canonical numeric spelling. Non-finite
numbers and duplicate object keys are invalid. An identity object is
`{"scheme": <versioned scheme>, "sha256": <64 lowercase hex>}`; scoped
identities also retain their exact `scope` string.

The successor is manifest `schema = "scworkbench.operation_pack.v3"`,
`pack_abi_version = "3"`, request
`schema = "scworkbench.operation_pack.transition_request.v3"`, receipt
`schema = "scworkbench.operation_pack.transition_receipt.v3"`, and process
transport `pybench-op-v4`. Existing v1/v2 definitions, schemas, fixtures,
requests, receipts, parsers, scheme meanings, and bytes remain frozen. The v3
implementation may reuse the accepted staged-transition machinery internally,
but version negotiation, validation, and identities are distinct. Unknown
versions or policies fail closed; there is no implicit upgrade, downgrade, or
fallback inference.

Compatibility is closed:

| Document | v1 reader | v2 reader | v3 reader |
| --- | --- | --- | --- |
| v1 | accept under frozen v1 rules | reject | reject |
| v2 | reject | accept under frozen v2 rules | reject |
| v3 | reject | reject | accept under this successor |

The engine may dispatch all three readers by the explicit schema/version tuple.
A pack stays on its declared ABI until its manifest is deliberately migrated.
The v3 schema carries forward the accepted semantic shapes for cell-set-family
admission and feature-set-registry reads without changing their policy meaning;
their v3 containing definition/request/receipt identities are necessarily new.
The frozen v2 documents and nested evidence remain inspectable under the v2
reader and are never rewritten during reopen or recipient validation.

The later implementation freezes exactly these four shared files once, after
Sable review, and copies them byte-for-byte to PyBench:

1. `inst/protocol/operation-pack-v3.schema.json`
2. `inst/protocol/operation-pack-transition-request-v3.schema.json`
3. `inst/protocol/operation-pack-transition-receipt-v3.schema.json`
4. `inst/protocol/fixtures/operation-pack-v3/identities.json`

The R and Python implementations must compute every identity independently;
one language may not authenticate JSON reserialized by the other.

The only new identity schemes are:

- `scworkbench.operation_pack.manifest.v3`
- `scworkbench.operation_pack.definition.v3`
- `scworkbench.operation_pack.pack.v3`
- `scworkbench.operation_pack.capability.v3`
- `scworkbench.operation_pack.transition_request.v3`
- `scworkbench.operation_pack.transition_receipt.v3`
- `scworkbench.operation_pack.output_grant.v3`
- `scworkbench.operation_pack.observed_output.v3`
- `scworkbench.operation_pack.runtime.v3`
- `scworkbench.operation_pack.output_cardinality_grant.v1`
- `scworkbench.operation_pack.observed_output_cardinality.v1`
- `scworkbench.operation_pack.typed_slice_grant.v1`
- `scworkbench.operation_pack.typed_slice_axis_manifest.v1`
- `scworkbench.operation_pack.typed_slice_response.v1`
- `scworkbench.operation_pack.observed_typed_slice_call.v1`
- `scworkbench.operation_pack.typed_slice_usage.v1`
- `scworkbench.artifact_ancestry.snapshot.v1`
- `scworkbench.operation_pack.provenance_read_descriptor.v1`
- `scworkbench.operation_pack.observed_provenance_read.v1`
- `scworkbench.provenance.snapshot_head.v1`
- `pybench.operation_pack.python_runtime.v4`

Existing output-grant, observed-output, feature-chunk, cell-set-family,
feature-set-registry, cell-order, row-order, request, receipt, and canonical
JSON schemes do not change meaning.

The v3 manifest/request/receipt copy every inherited field and validation rule
from the frozen v2 schemas, under the explicit v3 schema constants, then add
only the declarations and evidence defined here. The embedded outer
self-identities use exact scopes `capability excluding capability_identity`,
`request excluding request_identity`, and
`receipt excluding receipt_identity`. Each preimage is its complete v3 object
with only that self-identity field absent. The request adds
`typed_slice_grants` and `provenance_reads` only when declared, and nests
cardinality grants in the affected output descriptors. The receipt adds
`typed_slice_usage` and observed `provenance_reads` only when expected, and
nests observed cardinality in the affected output descriptors. These
conditional members are absent, never null. The capability binds every nested
grant and descriptor identity.

The other changed containing identities are closed as follows:

- `definition.v3` is the unscoped hash of the complete admitted v3 operation
  object.
- `manifest.v3` is the unscoped hash of the complete admitted v3 manifest.
- `pack.v3` is the unscoped hash of exactly
  `{scheme, manifest_sha256, namespace, package, backend, entry_point,
  operation_definition_sha256, pack_content_sha256}`, where `scheme` is
  `scworkbench.operation_pack.pack.v3`, the operation map is ordered by
  qualified operation name, and all other fields are nonempty strings.
- `output_grant.v3` has scope `descriptor excluding grant_identity` and hashes
  the complete v3 output descriptor. Its base members and kind-conditional
  presence rules are byte-for-byte the frozen v2 output descriptor with
  `grant_identity` absent; `cardinality_grant` is then present exactly when an
  `authenticated_output_axes_v1` policy targets the output and absent
  otherwise. No other member changes.
- `observed_output.v3` has scope
  `descriptor excluding observed_descriptor_identity` and hashes the complete
  v3 observed output descriptor. Its base members and kind-conditional rules
  are the frozen v2 observed descriptor with its identity absent;
  `observed_cardinality` is present exactly when the grant has
  `cardinality_grant` and absent otherwise. No other member changes.
- `runtime.v3` has scope `runtime attestation excluding runtime_identity` and
  hashes exactly `{schema, backend, pack_identity, manifest_source_identity,
  distribution_identity, operation_definition_identity, entry_point,
  declared_requirement_set_identity, selected_requirement_set_identity,
  dynamic_resolutions, preflight_report_identity, path_policy,
  runtime_identity}` with only `runtime_identity` omitted. `schema` is
  `scworkbench.operation_pack.runtime.v3`; the v3 pack/definition identities
  are required, while the other nested shapes retain their frozen meanings.
- The PyBench-owned sidecar is schema
  `pybench.operation_pack.python_runtime.v4`; its identity uses the same scheme
  and scope `python runtime sidecar excluding runtime_identity`, hashing the
  exact object `{schema, backend, distribution_identity, request_identity,
  capability_identity, operation_definition_identity, interpreter, seed,
  device, runtime_identity}` with only `runtime_identity` omitted. The inherited
  interpreter, seed, and device shapes are byte-for-byte those of the frozen
  v3 sidecar; all fields are required and none is nullable except inherited
  `seed.value` when its status is `not_declared`. There is no optional chunk
  field. Typed-slice usage evidence is authoritative only in the shared
  receipt. This Python-owned schema hash is recorded during composite
  qualification but is not a fifth cross-language shared protocol file.

Unchanged entry-point, installed-content, input-descriptor, dependency,
mutation-manifest, and typed-payload objects reuse their frozen schemes only
because their complete preimage shapes and meanings are unchanged.

### Self-identity preimage rule

Every new identity embedded in the object it authenticates is scoped. Its hash
preimage is the complete canonical object that contains it with only that
identity field omitted. Derived `definition.v3`, `manifest.v3`, and `pack.v3`
identities are the explicitly unscoped exceptions above and are not fields in
their hash preimages. The exact scopes are listed below. All shown fields are
required, unknown fields are forbidden, and arrays are ordered unless a field
is explicitly marked optional. Optional means absent, never implicit `null`;
only fields explicitly typed nullable may contain JSON `null`. Nested identity
objects are included verbatim in their parent's preimage. These rules, not
host-language insertion order or defaults, determine the bytes in both
languages.

## Capability 1: bounded output axes and cardinality

### Manifest declaration

The existing ordered `dimension_policies` admits a new closed branch. Every
entry is the tuple:

```
output
policy                    authenticated_output_axes_v1
shape                     cell_key_cartesian | one_per_cell
cell_axis.source          effective_cells_v1 | distinct_input_cells_first_occurrence_v1
cell_axis.input           required declared cell-indexed input for both sources
key_axis.source           resolved_parameter_feature_groups_v1 | input_keys_with_optional_selector_v1
row_order                 key_major_then_cell_v1 | input_cell_order_v1
missing_values            forbidden | canonical_null_allowed
```

`key_axis` is forbidden for `one_per_cell`. The referenced input,
parameter, output, primitive kinds, and row order are checked at manifest
admission. `cell_key_cartesian` is limited to `cell_vector_family` and
`one_per_cell` to `cell_vector`. No unbounded or `any size` policy
exists.

For `resolved_parameter_feature_groups_v1`, `key_axis` is exactly:

```
source                    resolved_parameter_feature_groups_v1
groups_parameter          declared string_vec_or_list parameter
matrix_input              declared matrix input
name_prefix_parameter     declared nonempty string parameter
matching                  exact_feature_id_v1
normalization             ordered_unique_features_v1
generated_names           legacy_module_group_names_v1
missing_feature_policy    {source: fixed_drop_v1} |
                          {source: parameter_v1, parameter: <choice parameter>}
empty_group_policy        drop | error
zero_key_policy           allow | error
```

A character vector is one group named exactly `module1`. An unnamed list is
named exactly `module1`, `module2`, ... in list order. A fully named list with
all names nonempty preserves those names. A partially named list discards all
supplied names and uses the normalized prefix parameter plus each 1-based
decimal position. This intentionally reproduces the frozen
`.wb_normalize_module_features()` behavior for AddModuleScore and UCell; the
prefix does not rename a character vector or wholly unnamed list. Duplicate or
empty resulting names are invalid because a Cartesian family cannot contain
duplicate `(key, cell_id)` pairs. Feature IDs are string-normalized,
deduplicated within each group by first occurrence, and matched exactly against
the authenticated ordered matrix feature axis. Input, matched, and missing
feature lists preserve group/input order. A parameter-selected `error` rejects
any missing feature; `drop` retains matched features and then applies the
declared empty-group policy. The zero-key policy is checked last. Core puts the
complete ordered result
`[{key, features_input, features_matched, features_missing}, ...]` in the
cardinality grant. This closes AddModuleScore/UCell key naming, feature
matching, missing-feature, empty-group, and zero-key behavior before dispatch.
Changing the legacy `name` behavior requires a separately authorized core
contract repair before migration; this ABI does not silently repair it.

For `input_keys_with_optional_selector_v1`, `key_axis` is exactly:

```
source                    input_keys_with_optional_selector_v1
input                     declared cell_vector_family input
selector_parameter        optional declared string-vector parameter
no_selector_order         first_occurrence_v1
selector_order            normalized_parameter_order_v1
unknown_key_policy        error
zero_key_policy           allow | error
```

The ordered distinct input keys are restricted by the normalized selector when
supplied. Selector order is authoritative; with no selector, first appearance
in the bound input is authoritative. Neither resolver is a callback, and the
pack cannot invent or drop a resolved key.

### Request and grant tuple

For each declaration, core adds `descriptor.cardinality_grant` to that output:

```
schema                    scworkbench.operation_pack.output_cardinality_grant.v1
output, kind, policy, shape, row_order, missing_values
cell_axis_source          {input_name, input_descriptor_identity, derivation}
cell_axis_count
cell_axis_order_identity   scworkbench.cell_order.v1
key_axis_count             absent for one_per_cell
key_axis                   exact ordered strings; absent for distinct cells
key_axis_resolution        exact resolver output; absent for one_per_cell
key_axis_order_identity    scworkbench.row_order.v1; absent as above
expected_row_count
row_order_identity         scworkbench.row_order.v1
cardinality_grant_identity scworkbench.operation_pack.output_cardinality_grant.v1
```

`cardinality_grant_identity` has exact scope
`grant excluding cardinality_grant_identity`. Its preimage is every preceding
field in this tuple, with the identity field absent. `key_axis_count`,
`key_axis`, `key_axis_resolution`, and `key_axis_order_identity` are required
for `cell_key_cartesian` and absent for `one_per_cell`.

For parameter groups, `key_axis_resolution` is exactly:

```
source                       resolved_parameter_feature_groups_v1
groups_parameter
matrix_input
matrix_input_descriptor_identity
matrix_feature_axis_identity
name_prefix_parameter
name_prefix_value
matching                     exact_feature_id_v1
normalization                ordered_unique_features_v1
generated_names              legacy_module_group_names_v1
missing_feature_policy       resolved literal drop | error
empty_group_policy           drop | error
zero_key_policy              allow | error
groups[]                     ordered {key, features_input,
                              features_matched, features_missing}
```

For input-family keys it is exactly:

```
source                       input_keys_with_optional_selector_v1
input
input_descriptor_identity
selector_parameter           declared name or JSON null
selector_value               ordered strings or JSON null
no_selector_order            first_occurrence_v1
selector_order               normalized_parameter_order_v1
unknown_key_policy           error
zero_key_policy              allow | error
keys                         exact ordered resolved strings
```

The two explicitly nullable selector fields are both null or both non-null.
No other resolution field is nullable or optional. The parent cardinality
grant authenticates the complete resolution; no host language recomputes a
different implicit default.

The distinct cell axis is the first occurrence of each cell in the already
bound input, after effective-cell selection. `cell_key_cartesian` authorizes
exactly `key_axis_count * cell_axis_count` rows in key-major/cell-minor order.
`one_per_cell` authorizes exactly one row per distinct cell in cell
axis order. Zero keys therefore authorizes zero family rows only when the
operation's parameter contract allows an empty resolved key axis; one key and
many keys use the same rule. Overflow is checked before multiplication.
The containing output descriptor sets `expected_dimensions` to
`[expected_row_count, 3]` for a family and `[expected_row_count]` for a vector;
no dynamic `[0,0]` sentinel is used.

The full cell vector is not duplicated in the request. Both runtimes must
independently rederive it from the authenticated staged typed input, validate
count and order identity before dispatch, and use that axis for every row and
pair check. Family inputs use distinct first occurrence, never the repeated raw
`cell_id` column. The pack obtains cell IDs only through its typed reader. The
usually small key vector is included in full; a hash-only key authorization is
forbidden.

### Writer, receipt, and publication

R and Python writers normalize neither rows nor keys. They verify exact row
count, unique `(key, cell_id)` pairs, the complete Cartesian product, the
declared row order, semantic value type, missing-value policy, and the expected
cell/key identities. A distinct-cell vector must contain every authorized cell
exactly once in order. Missing/extra rows or keys, duplicate cells, wrong cell
or key order, malformed missing values, and arithmetic overflow fail before a
staged output can become publishable. `canonical_null_allowed` admits canonical
JSON `null` only, never NaN, infinity, or a string sentinel. Method-specific
permitted-null masks remain comparator work unless a later authenticated mask
source is declared.

Each observed output descriptor adds this exact tuple:

```
schema                      scworkbench.operation_pack.observed_output_cardinality.v1
cardinality_grant_identity  exact copy from request
shape
observed_row_count
observed_cell_axis_count
observed_cell_axis_order_identity
observed_key_axis_count     required only for cell_key_cartesian
observed_key_axis_order_identity  required only for cell_key_cartesian
observed_row_order_identity
missing_count
semantic_validation        passed
observed_cardinality_identity
```

`observed_cardinality_identity` has exact scope
`observation excluding observed_cardinality_identity`; its preimage is the
preceding observed tuple with only that field absent. Receipt audit preserves
and compares `cardinality_grant_identity`, independently rederives the observed
tuple from the staged primitive, and validates its separate observed identity.
Receipt/output disagreement is fatal.

The authoritative deliberately non-sorted example has cell axis `[c2,c1,c3]`
and key axis `[sigB,sigA]`. Its family rows are
`[(sigB,c2),(sigB,c1),(sigB,c3),(sigA,c2),(sigA,c1),(sigA,c3)]`;
reduction produces `[(c2),(c1),(c3)]`.

## Capability 2: generic authenticated typed-slice delivery

Controller commit `9c784db1097c8d671ad98ab610f6624787b586c3`
requires the pack-facing reader to be a grant-scoped adapter over the ordinary
public getter. It explicitly forbids an operation-shaped core schedule,
fragment writer, scientific merge, or summary finalizer. UCell owns all of
those algorithmic choices and emits its ordinary granted terminal primitives.

### Public getter and manifest declaration

The public pure helper `wb_partition_axis(ids, chunk_size)` preserves the
caller-supplied unique order and returns consecutive nonempty partitions; an
empty axis produces zero partitions. The public `wb_slice_chunks()` iterator
uses that helper and calls `wb_slice()` once for each requested matrix slice.
It never preloads all chunks. Ordinary clients may instead call `wb_slice()`
repeatedly with the same partitions. The pack adapter delegates every actual
read to that exact `wb_slice()` backend; there is no pack-only storage reader.

The first closed typed-reader version supports only `kind = matrix`, axes
`cells` and `features`, and sparse numeric values with exact ordered feature
and cell IDs. Other primitive kinds are rejected rather than projected through
new storage code. A v3 operation opts in with ordered `typed_slice_reads`:

```
name                       unique capability name
input                      declared matrix input
reader                     read_typed_slices
supported_axes             nonempty subset of [cells, features]
chunk_axis                 one supported axis
chunk_size_parameter       normalized positive-integer parameter
call_discipline            ordered_partition_exactly_once | independent_slices
empty_selection_policy     allow_zero_axis | reject
duplicate_policy           reject
selection.cells            authenticated effective input cells or declared selector
selection.features         authenticated effective input features or declared selector
```

The declaration names no output, merge, summary, operation, or scientific
algorithm. `ordered_partition_exactly_once` requires the concatenated served
IDs on `chunk_axis` to equal the authenticated selected axis exactly, but the
pack chooses the requested chunk size, boundaries, call order, computation,
merge, and summary. `independent_slices` permits repeated or overlapping calls
between requests while still rejecting duplicate IDs within one axis vector.

### Grant, selected axes, and resource bounds

Core resolves both selected axes before dispatch from the authenticated input
and declared selector. Selection preserves source or explicit selector order,
contains no duplicates, and cannot add IDs. Each axis is staged as a canonical
manifest so the pack can learn the exact available IDs without placing a
bundle handle, database handle, storage path, or full matrix in its input:

```
schema                     scworkbench.operation_pack.typed_slice_axis_manifest.v1
axis                       cells | features
count
ids                        exact ordered strings
order_identity             cell_order.v1 or feature_order.v1
manifest_identity
```

`manifest_identity` has scope `axis manifest excluding manifest_identity`.
The request embeds the complete small fixture form and may use a separately
staged byte-identical axis manifest for large axes; in either form count,
order identity, manifest byte identity, and content identity are request-bound.
An empty selection is represented by `count = 0`, `ids = []`, and the canonical
empty-axis identity. An individual nonempty read may not contain an empty
fixed axis. Under `allow_zero_axis`, a zero-axis execution makes no calls and
returns no implicit scientific result; ordinary output grants still decide
whether an operation can publish outputs.

Each request grant is exactly:

```
schema                     scworkbench.operation_pack.typed_slice_grant.v1
name, input_name, kind     capability/input/matrix
reader                     read_typed_slices
input_descriptor_identity
input_content_identity
source_reference_identity
supported_axes, chunk_axis
cells_axis_manifest_identity
features_axis_manifest_identity
requested_chunk_size       exact normalized parameter value
call_discipline, empty_selection_policy, duplicate_policy
max_rows, max_columns, max_elements, max_response_bytes
max_outstanding_responses  1
grant_identity
```

`grant_identity` has scope `grant excluding grant_identity`. Limits are
positive integers fixed in the request. A call above any limit fails; core
never silently shrinks or repartitions it. A global default may select limits
only for a new run. Strict replay reconstructs the historical grant; if the
runtime can no longer honor it, replay fails before dispatch instead of using
a new default.

The pack learns its capability from a deep-copy execution-context descriptor
containing the grant and selected axis manifests. R and Python expose the same
call shape, `readers[[input]](features = ..., cells = ...)` and
`readers[input](features=..., cells=...)`. Both require explicit, unique,
in-grant axis vectors in the granted order. The normalized
`chunk_size_parameter` remains pack-owned algorithm metadata and durable run
input; core checks each call against it only for
`ordered_partition_exactly_once`. Core does not construct the partition.

### Genuinely bounded Python transport

Broker-enabled matrices are not written to `inputs/<name>/payload.json`.
Core starts a supervised read-only R broker child before Python dispatch. The
bundle path is passed only to that trusted child. The Python adapter receives
only a private transition-local endpoint token and the public grant/axis
descriptors. The broker uses a contained synchronous request/response spool:

1. Python atomically publishes one canonical control request with token, grant
   identity, monotonically increasing ordinal, and bounded feature/cell IDs.
2. The broker validates containment, token, ordinal, identities, subset/order,
   dimensions, product, and source currentness before calling `wb_slice()`.
3. It writes one response directory containing a Matrix Market sparse payload,
   canonical axis JSON, and a closed manifest of dimensions, byte hashes,
   semantic typed-payload identity, source/grant identities, and response
   identity. A ready marker is renamed into place only after all files close.
4. Python verifies regular-file containment, no symlinks, hashes, identities,
   dimensions, and limits before loading that one chunk, then acknowledges it.
   The broker deletes the response before accepting another request.

`max_outstanding_responses = 1`, plus the row/column/element/byte ceilings,
bounds both sides of the process boundary. The transition supervisor polls the
pack and broker, propagates either child's failure, enforces timeouts, and on
all exits terminates, then kills and waits for a surviving child. Request,
response, temporary, ready, acknowledgement, and token material are private
workspace data and are deleted before publication. A malformed or out-of-order
request, limit overflow, unexpected file, hash/axis mismatch, broker or pack
death, missing acknowledgement, getter error, or source mutation aborts the
transition with zero public residue.

The spool is transport, not a second getter: only the broker reads retained
state and every read calls canonical `wb_slice()`. Matrix Market bytes are
transport-authenticated but not scientific identity; semantic identity covers
the typed sparse values and exact axes.

### Durable usage and scientific boundary

Every served response records one call:

```
schema                     scworkbench.operation_pack.observed_typed_slice_call.v1
ordinal, grant_identity
feature_count, feature_order_identity
cell_count, cell_order_identity
dimensions
semantic_content_identity
response_identity
call_identity
```

`call_identity` has scope `call excluding call_identity`; the response uses
scheme `scworkbench.operation_pack.typed_slice_response.v1` and scope
`response excluding response_identity`. The receipt adds one ordered usage
object per grant:

```
schema                     scworkbench.operation_pack.typed_slice_usage.v1
request_identity, capability_identity, operation_definition_identity
grant_identity, requested_chunk_size
calls[]
call_count
concatenated_chunk_axis_order_identity
unique_chunk_axis_count, duplicate_chunk_axis_count
coverage_status            exact | independent | empty
usage_identity
```

`usage_identity` has scope `usage excluding usage_identity`. Receipt audit
rederives every call from broker-owned records and response manifests, checks
the declared discipline, and rejects a pack-only unobserved read. Strict
replay compares the exact grant and usage object. These records prove which
bounded core getter reads occurred; they do not prove UCell arithmetic.

UCell may partition cells, score each chunk, merge key-major results, and form
its summary entirely in its pack process, then write the complete family and
table through ordinary generic output grants. The later method comparator must
show one versus several chunks, backed versus in-memory input, identical
terminal identities, feature matching, missing values, and summary numbers.
Any difference is a method-migration failure, not a reason to move scientific
merge or summary code into core.

## Capability 3: core-attested artifact ancestry

### Manifest declaration

An operation may add ordered `provenance_reads` entries:

```
name
category                  authenticated_core_provenance_snapshot
kind                      artifact_ancestry
reader                    read_artifact_ancestry
input                     declared typed input
activation                when_resolved_from_artifact
lifecycle_policy          require_current
parameter_assertions      optional artifact_id/run_id/snapshot_id parameter names
```

The core retains the symbolic input reference alongside the resolved primitive.
The declaration grants no bundle, connection, SQL, filesystem, catalog, or
general provenance reader. A literal/session primitive does not fabricate
artifact ancestry; the attestation is required only when its bound input was
resolved from a promoted artifact reference.

Optional scientific metadata parameters are equality/compatibility assertions
only. They cannot select another artifact, suppress the input-bound read, or
launder a stale source.

### Attestation tuple and reader

Immediately before dispatch, core constructs:

```
schema                    scworkbench.artifact_ancestry.snapshot.v1
attestation_name, input_name
input_descriptor_identity
reference_kind            promoted_artifact
artifact_id
artifact_type
artifact_lineage_status   string or explicit JSON null from artifacts row
artifact_content_identity {scheme: content_identity_scheme,
                           sha256: content_sha256}
source_run_id
source_run_identity       {scheme: run_hash_scheme, sha256: run_hash}
source_snapshot_id
source_snapshot           exact provenance-head object including identity
source_output_name
source_output_content_identity
lifecycle                 exact lifecycle object
snapshot_identity
```

`snapshot_identity` has exact scope
`snapshot excluding snapshot_identity`; its preimage is every preceding field
with only that field absent.

Core obtains the artifact fields from the unique `artifacts` row. Its nonempty
`provenance_snapshot_id` is the authoritative source-snapshot anchor. Core then
selects `prov_run_outputs` by both that snapshot ID and `artifact_id`, requires
exactly one row within that snapshot, and uses that row's run/output fields.
Zero or multiple rows within the recorded snapshot fail closed. Matching
observations in later promoted snapshots neither replace the anchor nor create
ambiguity; they remain ordinary occurrence evidence outside this compact read.
The selected output must be `content_verified`; its stored
`content_identity_scheme` and `content_sha256` form both content-identity
objects and must equal the bound input descriptor's content identity. The
source run is the matching `prov_runs` row; its stored nonempty
`run_hash_scheme` and `run_hash` form `source_run_identity`. No invented
artifact revision or promotion-receipt identity is part of this contract.

`source_snapshot` is the unique `prov_heads` row whose `snapshot_id` equals the
producer snapshot, not the bundle's newest unrelated head. It is exactly:

```
snapshot_id
schema_version
head_run_ids              parsed ordered JSON strings
n_runs                    nonnegative integer
n_artifacts               nonnegative integer
commit_id                 nonempty string or explicit JSON null from row
replay_status             nonempty string or explicit JSON null from row
source_snapshot_identity  scworkbench.provenance.snapshot_head.v1
```

`source_snapshot_identity` has scheme
`scworkbench.provenance.snapshot_head.v1`, scope
`snapshot head excluding source_snapshot_identity`, and hashes the preceding
fields with only that identity absent. Only `commit_id` and `replay_status`
are nullable, matching accepted legacy `prov_heads` rows; no source field is
optional.
The registry `provenance_snapshot_id`, selected output `snapshot_id`, nested
head `snapshot_id`, and top-level `source_snapshot_id` must all be identical,
and the source run must occur in that snapshot.

`lifecycle` is constructed from the required `entity_lifecycle` artifact row,
all incident `entity_supersessions` rows, and `entity_tombstones`:

```
state                     lifecycle_state
identity                  {scheme: identity_scheme, sha256: identity_hash}
provenance_bound          integer 0 | 1
incoming_supersedes[]     ordered edges where artifact is successor
outgoing_superseded_by[]  ordered edges where artifact is predecessor
tombstone_state           rejected | retracted | explicit JSON null
```

Each edge is exactly
`{successor_kind, successor_id, predecessor_kind, predecessor_id,
relationship_type}` with `relationship_type = SUPERSEDES`; each array is
sorted by the UTF-8 tuple of those fields. `require_current` requires
`state = current`, nonempty lifecycle identity fields, `provenance_bound = 1`,
an empty `outgoing_superseded_by` array, and null `tombstone_state`. A current
successor may retain any canonical incoming history. A predecessor with an
outgoing successor is stale and rejected. The parent snapshot identity binds
the complete lifecycle object.

Every field comes from core's already validated artifact/provenance model and
must reconcile with the resolved typed input. Empty, ambiguous, stale,
superseded, cross-artifact, cross-run, cross-snapshot, or content-mismatched
evidence fails before runner dispatch. Exact historical/superseded revisions
are deliberately outside this policy; supporting them later requires a new
explicit policy rather than weakening `require_current`.

The canonical snapshot JSON is staged read-only at
`provenance_reads/<name>/payload.json`. Its manifest identity uses the existing
payload-manifest scheme over exactly
`{path: "provenance_reads/<name>/payload.json", sha256: <file bytes>}`. The
request carries this exact descriptor:

```
schema                    scworkbench.operation_pack.provenance_read_descriptor.v1
name
category                  authenticated_core_provenance_snapshot
kind                      artifact_ancestry
reader                    read_artifact_ancestry
input_name
input_descriptor_identity
lifecycle_policy          require_current
snapshot_identity
payload_manifest_identity
descriptor_identity
```

`descriptor_identity` has scope
`descriptor excluding descriptor_identity`. The capability reader grant copies
`name`, `reader`, and `descriptor_identity` exactly. The pack receives only
`read_artifact_ancestry(name)`, which returns a deep copy and records one exact
observation. The receipt observation is exactly:

```
schema                    scworkbench.operation_pack.observed_provenance_read.v1
name
descriptor_identity
snapshot_identity
payload_manifest_identity
use_count                 1
observed_descriptor_identity
```

`observed_descriptor_identity` has scope
`observation excluding observed_descriptor_identity`. Its preimage is the
preceding object with only that field absent. An absent required read, duplicate
read, undeclared read, forged payload, wrong binding, or descriptor mutation is
fatal.

Core repeats the lookup in the promotion transaction and requires exact tuple
identity. This closes the preflight/publication mutation window. The durable
transition receipt retains the descriptor and observed-read identity, so
pack-free reopen and recipient inspection need no pack installation. Strict
replay reconstructs the descriptor from the replay source and requires exact
identity before dispatch. No local bundle path is ever serialized.

## R and Python handler surfaces

The two languages expose the same authority, without a generic transaction
callback:

| Capability | R handler | Python handler |
| --- | --- | --- |
| bounded terminal | existing `writers$write_terminal_primitive(name, value, semantic_metadata)` | existing `writers.write_terminal_primitive(name, value, semantic_metadata)` |
| typed matrix slice | `readers[[name]](features = ..., cells = ...)`, direct `wb_slice()` delegation | `readers[name](features=..., cells=...)`, bounded broker delegation to `wb_slice()` |
| pure partition helper | `wb_partition_axis(ids, chunk_size)` | `partition_axis(ids, chunk_size)` |
| ancestry | `readers[[name]]()` | `readers[name]()` |

All new methods are adapter-owned closures scoped to one execution capability.
Handlers cannot construct grants, name a source artifact, obtain an underlying
bundle or storage path, or publish. Packs own partitioning, chunk work,
scientific merge, and summary formation. R and Python independently validate
their canonical tuples; core revalidates all broker records, staged payloads,
and receipt evidence before publication.

## Atomic lifecycle shared by all three capabilities

Request, staged payloads, receipt, outputs, registry requests, attestations,
run provenance, and replay evidence remain one existing transition workspace
and one publication transaction. Validation order is manifest admission,
source/currentness preflight, capability construction, runner execution,
staged-payload audit, receipt audit, source/currentness recheck, then atomic
publication. A failure at any point removes the private workspace and leaves
the source-only destination fingerprint, catalog, run graph, active/head state,
payload inventory, registry state, receipts, and materializations identical to
the preimage. Retry starts a new transition and capability.

Successful publication makes both terminal outputs and their complete receipt
set observable together. Pack-free reopen and recipient validation recompute
all descriptor/content identities. Strict replay authenticates the exact
operation definition, normalized parameters, input descriptors, typed-slice
grants and exact usage, ancestry reads, outputs, and receipts.

## Ten-method reconciliation

The exact machine-readable ledger is
`notes/operation_pack_phase3b_consolidated_readiness.csv`. In summary:

- `addmodulescore` uses parameter groups `features`, matrix input `matrix`,
  prefix `name`, fixed `drop`, empty-group `drop`, and zero-key `error`; it
  needs only the family axis/cardinality policy.
- `ucell` uses parameter groups `features`, matrix input `matrix`, prefix
  `name`, missing policy parameter `missing_features_policy`, empty-group
  `error`, and zero-key `error`; it additionally needs the generic matrix
  typed-slice reader with cell-axis `ordered_partition_exactly_once`. The pack,
  not core, owns chunk partitioning, score-family merge, and summary formation.
- `cell_vector_family_reduce` uses the distinct-first-occurrence cell axis of
  `signal` and needs one-per-cell vector cardinality.
- `cell_vector_family_qc` and `cell_vector_winners` need no new generic ABI;
  method equivalence remains unproven.
- `cell_vector_family_calibrate` and `cell_vector_family_graph_smooth` use the
  input-family resolver on `signal` with selector `signal_keys`, unknown-key
  `error`, and zero-key `error`; calibration's NA/tie semantics remain a method
  comparator.
- `cell_vector_family_graph_smooth` additionally needs artifact ancestry;
  query chunking remains method-private and is not a typed-reader declaration.
- `winner_cell_sets` uses the accepted family admission, but migration
  atomicity/equivalence remains unproven.
- `feature_set_overlap_qc` and `pathway_enrich` depend on the separately
  qualified feature-set-registry reader and remain gated on its independent
  acceptance.

This reconciliation does not claim that static inspection exhausts runtime
behavior. Every method still needs its frozen old-core/new-pack comparator in
the later extraction order; `winner_cell_sets` additionally needs its explicit
all-or-nothing comparator.

## Fixture ledger and review questions

`notes/operation_pack_phase3b_consolidated_fixture_plan.json` is the
authoritative positive/negative plan. Every capability has R, Python, and
cross-language cases plus promotion/reopen/recipient/replay/rollback coverage.
The three-cell/two-key family and three-cell reduction are shared canonical
fixtures, not prose-only examples.

Sable review must explicitly decide:

1. whether the explicit v3/`pybench-op-v4` successor and compatibility matrix
   preserve every frozen v1/v2 byte and identity;
2. whether the matrix-only axes, exact selected-axis manifests, limits, call
   disciplines, and usage identities form a closed generic reader grant;
3. whether the supervised one-response spool is genuinely bounded across the
   Python process boundary and delegates all retained-state reads to
   `wb_slice()` without exposing a bundle or storage path;
4. whether leaving UCell partitioning, merge, summary, and one-versus-many
   equivalence entirely to pack code plus its mandatory method comparator is
   the correct scientific boundary;
5. whether `require_current` is the correct closed policy for implicit
   artifact ancestry; and
6. whether any fixture lacks a fail-before-publication or zero-residue check.

No implementation, full suite, package check, pack migration, release pin,
merge, push, tag, release, publication, bundle edit, container build, or Phase
4 work is part of this checkpoint.
