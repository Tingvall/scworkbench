# Authoring ABI-v3 operation packs (SDK 1.0.0)

The additive ABI4 graph reference is documented in [GRAPH_GUIDE.md](GRAPH_GUIDE.md).
Use `template = "graph"` when scaffolding and `pack_abi_version = "4"` when
inspecting capabilities. Existing ABI3 defaults and authority remain unchanged.

## Quick start and trust

The installed [system overview](../../onboarding/SYSTEM_OVERVIEW.md) maps the
core/pack architecture and analyst workflow. This guide is for pack authors;
the source-distributed engine-extension loop is not required for a new method
over supported primitives.

Use `wb_operation_pack_scaffold(path, package, namespace, author, email)` into
a nonexistent directory with an existing parent. Spaces work; traversal,
reserved namespaces, overwrite and malformed maintainer metadata reject.
Generation stages then publishes with Linux `renameat2(RENAME_NOREPLACE)`:
even a destination created at the final boundary is preserved and rejected.
Unsupported OS/kernel/filesystem combinations fail closed, with no replacing
rename fallback. The core package now contains a small registered C component
and requires an R-compatible C toolchain for source installation; the scaffold
does not depend on Python. Generation performs no installation, network,
activation or Git changes. The MIT template is a real one-operation R package.
Its manifest is plain JSON validated by `wb_operation_pack_manifest_validate`.
There is no parallel SDK validator. Inspect/edit the runner and manifest as a
pair. Installed validation verifies the installed manifest, entry point and
package identity. New execution/replay requires explicit activation and the
proper compatible pack, source/parameters/runtime. Retained-output inspection
does not. Installation, entry points, tests and model deserialization execute
trusted code; checksums are not a sandbox.

Ordinary execution verifies the selected dependencies, not every unrelated
historical output. Recovery and selected promotion still verify their complete
required closures. Fresh ordinary RDS outputs retain final-byte verification
while avoiding duplicate semantic decoding only when the native writer has
sealed the complete payload and no special manifest or registry mutation is
involved. Eligibility is per output; special outputs in a mixed native-R
transition retain their deep checks and complete receipt/seal closure still
runs. Source associations, alignment, receipts and atomic rollback remain
core responsibilities; SQLite counters and file observations are not payload
content authority.

Registry readers retain an invocation-private, validated issued snapshot. Core
still obtains the actual registry snapshot before dispatch and publication.
Only exact equality of that value, its declaration, input descriptors and the
complete privately issued registry descriptor permits reuse of its already
computed canonical identities. This avoids re-encoding unchanged values, not
fresh registry reads. The private observation is not part of the protocol;
recovered and retained requests independently validate their persisted data.

Run `scripts/tutorial.R` with an installed scworkbench from any directory.
The script scaffolds, checks, installs into an isolated library, proves inert
namespace loading, validates then explicitly loads, inspects the interface,
assembles data, runs, promotes both terminals, finalizes, relocates, reopens
pack-free in a fresh process, verifies no writes, proves missing-pack failure,
then explicitly reruns the same source/parameters with the compatible pack.
This demonstrates replay prerequisites/canonical output values, not replay
across incompatible methods or reproduction of arbitrary allocated IDs.

## Runner contract

`function(readers, writers, params, context)` receives copied effective params
and read-only-by-contract context. Ordinary readers use input names; granted
readers use declaration names; G4/G5/G6 use their global named callbacks.
See `callbacks.json` for every field, signature, absence rule and return
channel, and `capabilities.json` for every accepted ABI constant/enum branch,
all eleven primitives/profiles, recipe and independent backend statuses.
Calls use exact authenticated cell/feature order. Numeric chunk sizes resolve
from admitted params. `wb_operation_pack_map_partitions` only delegates
`wb_partition_axis` and the issued reader; it supplies no new reader authority.
Never reslice storage using SQL or paths; never construct receipt hashes.

### Trusted in-process R matrix streaming

Matrix callbacks retain bounded selections and exact partition/coverage checks.
Core prepares physical readers once per invocation; feature-partitioned scans
may build one disposable row-major BPCells index, removed on success or failure.
This does not add a logical source fragment or change scientific parameters.
Matrix-slice content identities stream the existing canonical JSON v1 bytes;
they do not allocate a dense complete fragment or one R list per nonzero.
On Linux/glibc 2.34 or newer, an optional core-private SHA-256 sink can consume
those exact bytes without writing and rereading a temporary canonical JSON
file. It uses public EVP functions from the already loaded OpenSSL dependency,
with owned lifetime and checked completion. Unsupported builds/providers retain
the original file-based path. This is not a different identity scheme, reader
contract or source-authentication policy, and requires no pack changes.

Already-owned ordinary `dgCMatrix` projections can feed the same formatter
directly from validated sparse slots. This avoids temporary column copies and
coordinate vectors; its extra formatter workspace is constant, not the size of
the already-owned matrix. It does not request or materialize a whole source.
Unsupported, deferred, custom or malformed carriers retain the original bounded
callback/coercion path. Scientific reads, identities and authentication remain
unchanged; this is not a new public reader or storage contract.

The same applies when core already owns an ordinary double-valued R matrix:
its identity formatter can read that matrix directly without temporary sparse
or coordinate representations. This does not allocate a new dense source or
change a reader's bounded schedule. The existing canonical bytes, missing/zero
policy, value checks and source/publication authentication remain unchanged.
The input matrix still occupies its existing memory; only the extra formatter
workspace is constant. Opaque, classed or deferred carriers use the old path.

For trusted in-process R packs, complete source bytes are authenticated during
request preparation and independently before publication. For a fresh core-issued
backed-matrix request only, the middle predispatch check reuses the original
lightweight observation captured before, and checked after, initial full
authentication. Every private grant/input/source/ordered-selection binding,
issuing connection and bundle root remains checked, along with the actual
scientific registry state. Between chunks, core uses that same original guard
to check source registry and file inventory/size/timestamps/resolved paths,
not repeated whole-file hashes. An enduring source change rejects and rolls
back publication. A transient in-process mutation restored before final
authentication is **not guaranteed to be detected**. This approved trust model
is not a sandbox against malicious R code or concurrent host writers. Python's
non-mixed typed-matrix broker uses the same boundary-authentication model, with
independent response/acknowledgement validation. Small private Matrix Market
inputs may use an admitted in-memory cache; larger inputs use bounded BPCells
import and an owned temporary double-valued spill. Mixed graph/matrix requests
also prepare scoped readers rather than reauthenticate the complete matrix on
each block. Existing aggregate graph budgets admit caches, source axes, spills
and response carriers. These are scoped resource admissions, not an OS-level
quota or a global combined R/Python peak-RSS guarantee.
Alignment, source provenance, receipt verification and atomic publication remain
enforced.

Core's zero-filled public matrix selections also keep partial fragment blocks
sparse, including overlap replacement; complete disjoint typed-reader blocks
are assembled one fragment at a time. Explicit `missing = "NA"` reads retain
their dense output contract: they are not a bounded sparse alternative.

Repeated retained-graph inspection on one live connection can reuse a bounded
independently verified content observation while exact database epochs, relevant
table definitions and effective budgets remain unchanged. Headers, all retained
certificates and source associations are still checked freshly. Reopening,
recovery and explicit deep validation do not inherit a previous connection's
observation. This is not authority based on timestamps or a persistent cache.

### Native R typed-space streaming

For symbolic registered HDF5 spaces on the native POSIX R path, core issues a
metadata-only reader plan and reads coordinates in bounded row/dimension tiles.
The existing generic input identity and selected-space identity are streamed
with their distinct original canonical preimages; they are not new schemes.
Ordered cells and dimension labels are retained under aggregate admission.
HDF5 UTF-8 variable-length axes from Python remain supported, including the
existing HDF5/R-order portability boundary. Registered producer bytes are
authenticated before axis decoding; each block checks the source binding and
independent final authentication remains required. File observations are only
lightweight invalidation signals, never content authority.

Each issued typed-space plan admits the current schema and migration ledger
observationally once. Block reads freshly compare the exact registered binding
and issuing connection, without repeating complete schema admission. A new final
plan repeats full admission and content authentication. A freshly issued native-R
plan uses its original lightweight guard at the middle predispatch boundary,
while still checking every private grant/input/selection, connection and bundle
root binding. Initial and final full-byte authentication compare complete
logical/payload registry and ordered-axis authority; the same numerical JSON
need not be reconstructed again. Default/full helper calls, Python, recovered,
transferred and no-issued-plan requests retain their full existing checks;
no prior invocation inherits the native middle-boundary exemption. Canonical numeric tokens
may be formatted in bounded native batches; byte rules and identity schemes are
unchanged, and unsupported carriers retain the existing encoder and diagnostics.

This is not a Python typed-space execution capability: schema parity does not
supply a Python reader transport. Ordinary full-value readers, caller-provided
coordinate matrices, legacy storage and non-POSIX compatibility paths retain
their materialized contracts. Existing native RDS transport can likewise require
materializing a retained primitive on reopen; a bounded getter does not make RDS
a streaming format. Plans, scratch files and connection handles are private to
core and do not enter pack context, primitives, receipts or checkpoints.

Declare required outputs, allocation keys, dimension policies and complete
promotion closures. Writer calls use fixed methods plus declared output names,
and return opaque acknowledgments, not receipts. Finish all handles and reads
before returning `list(status = 'ok')`. Declared retained_parameters select
specific effective parameters or output observations. Arbitrary return fields
are not retained. G3 returns separate TRUE source-association/no-refit
attestations; G7 returns declared cell axes, which core seals and audits.
Runtime family, sparse family, relation layout and derived fitted-axis policies
require their declaration-before-write methods. No copying/modification of a
context grant changes authenticated authority.

## Primitive recipes

Symbolic `wb_prim_matrix('counts')`, `wb_prim_space('pca')` and model refs
identify registered inputs, not newly computed outputs. For terminal payloads
use public `wb_prim_cell_vector`, `wb_prim_cell_vector_family`,
`wb_prim_feature_table`, `wb_prim_obs_table`, `wb_prim_relation_family`,
`wb_prim_path_2d_family`, `wb_prim_space_path_family` with exact declared types,
axes and metadata. Continuous cell vectors use the established character
storage plus explicit continuous value_type; compare numeric scientific values
separately from their canonical storage. Metadata object keys must be unique.

Computed ordinary matrix/space envelopes are wb_primitive lists with kind,
values, dimensions, cell_id and (matrix) feature_id; spaces are cell-major,
matrices feature-major. Declare dimension labels/semantics through the accepted
output/axis policy, not a symbolic ref. Core validates these envelopes. Models
use `open_model_tree(output)` and its scoped path/write_bytes/finish handle.
Private staging paths are lawful for external libraries; durable bundle paths
are not. Only admitted contained entries may be used; reject traversal and
symlinks. A verified RDS/pickle may still be malicious. Some nested model
closures do not universally enforce retirement: saving/reusing any capability
or private path after return is prohibited, not claimed sandbox-safe.

For recipe-specific fields, inspect each catalog entry's manifest locations,
call discipline, source bindings, limits, empty/NA rule, seal timing and evidence.
The existing protocol documentation remains normative. G7 ordered union keeps
pack-declared order; display-path composition does not imply a fitted model.
G3 byte-unavailable admission is only manifest-authorized; an observed checksum
mismatch always rejects. Python shared-schema parity is not executable G3/G7
authority. Python's exact accepted/rejected policy table is embedded separately.

## Author tests and diagnostic tiers

Use `wb_operation_pack_sdk_fixture`, `sdk_run`, `sdk_assert`, `sdk_state`,
`sdk_cases`, `sdk_skip`, `sdk_recipient` (each prefixed wb_operation_pack_).
Scaffold author tests have no core-internal access. The run helper uses public
dispatch; core-owned test seams inject invalid reader schedules, reordered
outputs, incomplete closure, partial write and publication failures. All hooks
and runner wrappers restore on exit; these are isolated-test tools, not a
production authority interface. Durable state asserts registry and payload
identities, not mutable SQLite page layout. Recipient audit additionally checks
the complete filesystem fingerprint around read-only inspection.

Static mode never imports target code. Installed/contract modes require
`trusted = TRUE`, perform local installation without downloads, retain logs and
numeric exits, and test identity-bound explicit activation in fresh processes.
Contract counts reflect author cases; malicious author tests are not certified.
Missing fixtures/dependencies, invalid reports or skips make the tier
unqualified. Run R CMD check separately. Scientific correctness, total memory,
safe deserialization, pinned environment and method-specific numeric tolerance
remain author responsibilities. Use a separate process for conflicting pack
versions; unloading a used pack is deliberately prohibited.

The report's `diagnostics` retains complete command text in memory; save the
report for lasting evidence. Its `logs` and isolated library are temporary and
may disappear when the R process exits. Static mode has no author test counts.

## Checklist

During development use static checks and focused author tests. Qualify the
frozen installed candidate once across the required lifecycle; a documentation
correction does not require unrelated complete scientific suites. Keep method
tests pack-owned and real-pack composites explicitly invoked. Save check
diagnostics and any temporary logs before process exit.

- Match package/version/namespace/qualified operation/entry point.
- Declare closed input/output/schema/profile tuples, defaults and dependencies.
- Pick the correct backend-supported capability recipe and bounds.
- Define finite/missing/empty behavior and scientific comparison criteria.
- Finish reader schedules, handles, terminals and complete promotion closure.
- Test absent pack/dependencies, stale/wrong axes, rollback and retry.
- Inspect finalized relocated outputs in a fresh pack-free process.
- Record exact identities, counts, skips, exits and trust decisions.
- Run independent author review and package qualification before distribution.
