# Authoring ABI-v3 operation packs (SDK 1.0.0)

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
