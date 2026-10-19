# Same-state registry observation at the writer tail: prospective experiment

Parent source `8713872eca2e7bd6166630330c65901865816ce2` includes the narrow
immutable auxiliary-reader correction, qualified by separate5/5 and32/32
focused installed-package runs. This commit contains NO runtime change. Prior
failed performance gates remain failures. All new benchmark executions are
serialized; a source-only observational probe is being prepared first.

## Existing work and proposed boundary

`R/mutation_boundary.R:.wb_operation_pack_registry_snapshot` already obtains
an actual registry snapshot within one invocation and may reuse it under the
existing same-context epoch. Its context is torn down before the writer tail.
`R/writer_lock.R:.wb_with_bundle_writer_lock` then asks
`R/bundle_init.R:.wb_manifest_publish_current_locked` to publish, often using
a directory and a new connection; the builder scans the whole registry again.
Historical small HVG census shows actual acquisitions.339s and.328s on that
path, but does not prove an unchanged strong key at the tail. Historical392
has27 snapshots/98.623inclusive seconds; that total is NOT a savings estimate.
Simple live-handle routing alone previously missed its25% target (0.636% gain)
and is not the proposed change.

Investigate whether an independently observed registry state can feed ONLY its
own same-state writer-tail manifest rebuild. Source state must be actual, not a
retained claim or a weak-cache value retrospectively labeled stronger. Strong
connection/actual-main-path/owner/schema/data/change and serializer-policy
observations must bracket its ACTUAL acquisition. The same original still-live
connection and fresh complete key must hold at substitution, otherwise use the
unchanged full acquisition. No cross-connection or cross-writer handoff.

Retain only the existing scoped observation, NOT the active mutation-context
stack or capability. Mutation authority must still end before publication hooks.
The original directory-based nested/outermost publication decision must stay
exact: unconditionally passing a bundle handle changes nested_handle_ready and
can add publications. Ordinary counts/metadata construction, complete manifest
rebuild, atomic write and publication frequency remain. Do not let a new actual
handle route opportunistically skip the old unconditional tail publication via
an unrelated publication witness. Public migration, refresh, recovery, recipient
and deep-validation paths retain their original behavior.

No new global cache, replacement validation framework, callback API, optional
client authority or scientific-payload trust exemption is proposed. Existing
source hashes, rows/axes, writers, seals, output closure, receipts, rollback and
finalization remain independent. Mutable sources cannot be memoized by time.
Bound retained metadata and match graph/resource and serializer policy; unknown
or inadmissible cases take the old route.

## Evidence required BEFORE runtime implementation

Use the exact installed parent on a newly owned representative native R pack
terminal workflow. Observational wrappers may record strong keys around actual
snapshots and at the unchanged publisher's entry, but must not change behavior.
Record actual snapshot identities, exact live connection/path/owner key,
mutation-context presence at the tail, publication frequency and any candidate
same-key match. A match is a potential reuse opportunity, NOT an implemented
cache hit or a measured saving. If meaningful matches are absent, stop this
experiment without implementing a flag or weakening guards.

If the probe supports it, freeze fresh complete-workflow baseline medians and
absolute ceilings BEFORE code. Prospective component target: >=20% reduction
in complete public terminal-only workflow wall time against matched parent,
and actual repeated registry acquisitions2→1 on the demonstrated boundary.
Peak whole-process RSS may grow at most10%; no regression in physical/source
scan counts or publication frequency. Mutation/materialization workflows that
cannot reuse must be <=parent×1.10+.02s. Original typed-space<=5s, helper50%,
graph/mixed and full-Xenopus171.124s targets remain explicitly unwaived.
No repeated timing after a miss without a new attributed source change.

Required focused adversarial coverage before candidate measurements: own and
foreign writes; schema reset/DDL; TEMP/attachments; stale/foreign connection or
path; owner change; serializer/resource policy change; missing/unissued/oversize
observation; nested scopes; hooks invoking forbidden mutation authority; actual
publication fault and retry; complete old/new manifest registry identity;
source/payload filesystem equality on read-only paths; zero residue after failure.

External Sable principle assessment, not code/performance approval:
`/tmp/scwb-sable-registry-writer-tail-design-20261019/assessment.json`, SHA256
`564b27bd727e769f778754e066c0874ec8691b91deb3f3ccf3019ebaf810b224`.
Local Sable source-policy note `6e5ba61` identifies the nested-publication and
mutation-authority lifetime hazards. No reviewer has accepted unseen code.
