# Immutable auxiliary SQLite readers: correction before further profiling

Parent `f3bb0552a2398ec7ff589533a30d106501c8d8ac`. No runtime implementation
in this commit. All other development qualification jobs are held.

The helper-only profiling prelude opened a closed WAL-mode test bundle through
the public immutable read-only route. The independent native byte observer and
manifest window connection instead reopened its physical filename using plain
read-only connections. Those connections created a zero-byte WAL and32768-byte
SHM. The profile's actual purity assertion and outer supervisor failed; those
exit1 records are retained, not converted to passing evidence.

This happened to the previous392 test fixture, not an experiment bundle. Its
three existing files remained byte-identical. Root verified no live file handles,
the empty WAL and all five hashes, then recoverably moved only the two files
created by that failed probe into its `preserved_new_sidecars` directory. The
original three-file tree and hashes were restored without SQL, checkpointing,
rewriting scientific data or deleting evidence. Exact logged command and exit0:
`/tmp/scwb-engine-simplification-forge-20261018/preserve_failed_probe_new_sidecars.sh`.
The failed profile and before/after inventories remain separately retained.

Proposed correction: propagate immutable mode only from a core-created actual
immutable connection, using private issuance on that live connection reference
bound to its real main filename, URI and original dbname. Independent native,
manifest-window and legacy-object selector readers inherit that exact mode.
Normal mutable and active-WAL connections retain their original plain-path
readers and mutation detection. No immutable inference from bundle flags, file
timestamps, read-only pragmas or absent sidecars is permitted.

Preserve the distinct existing admissions of all five constructors:
bundle-access/readiness and schema inspection require no WAL/SHM; the relevant
validator diagnostic admits an existing empty WAL, whereas its later independent
inspection also rejects journals. A common private connector must not silently
tighten those caller policies. URI path bytes must escape `?`, `#`, `%`, spaces
and UTF-8 correctly. Native URI mode must be explicit, not inferred from a
filename prefix. Existing plain literal filenames and NOFOLLOW behavior stay.

Prospective acceptance and numerical budgets, before implementation:

- Closed, checkpointed WAL-header fixtures with no sidecars must stay completely
  byte/path-pure through public read-only open, native/window/legacy readers,
  inspection and close. No source migrations or writes.
- Nonempty-WAL admission still rejects; the existing empty-WAL validator policy
  still accepts where it previously did. A stale/mismatched immutable issuance
  rejects, never silently falls back to a mutable open.
- Actual mutable-WAL reads, committed source mutation detection, containment,
  URI-escaped names, cleanup and resource guards retain focused coverage.
- No scientific source scan/hash/physical-payload observation count increases.
  Constant-size immutable target/admission guards at native finish are allowed;
  they never read scientific values or replace content authority. Normal mutable
  metadata paths keep the same number of primary filename queries and auxiliary
  connections. There is no new content cache or identity/schema change.
- Current parent full typed-space medians8.970s/8.992s are retained as regression
  baselines; correction ceilings are parent×1.10+.02s (9.887s/9.9112s).
  The original <=5s, helper50% and full-Xenopus targets remain unwaived. A
  correctness repair alone is not a new performance pass.

Source policy review: external Sable assessment552926da71ebbd8fbd99cd48b4c82d46
3222b01d7c2fe7391d180f2d3e8b4974 and addendum
b57b9f5cab6a5da734b4533c305ccdefd7a59c1fd0c266eb355da4b558a97ef4.
These are principle/source reviews, not executed qualification.
