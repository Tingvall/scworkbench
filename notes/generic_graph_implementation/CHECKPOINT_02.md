# Incomplete focused implementation checkpoint

This is a local development checkpoint under Controller's autonomous
implementation order at accepted design `fa929601c7b8c67c2947b400341bfd90bd80d925`.
It is NOT final acceptance, broad qualification, an audit handoff or a release.
Core primary remains untouched at `17bdc7bbfe7dd5f2a813d4e69b93d7d1537d1caf`;
Python primary remains untouched at `0e67612a915caf4168a6824084fe5c5446690567`.
Use this checkpoint's Git HEAD as its exact source identity, not its parent.

## Implemented focused boundary

The existing executor/broker now negotiates ABI4/process5 and mixes graph with
ordinary primitives. Core issues explicit retained CV/CVF or selected graph
binding source-axis authority, revalidates real scientific payload closure and
complete ordered source axes, and seals all graph roots and mixed output closure.
Native callbacks expose only constructors, bounded readers/writers and a
path-free source-axis projection. Output publication authenticates every binding;
content-only input reads authenticate no axis source, and selected-view reads
authenticate exactly their selected views without discarding unused associations.

Fresh CV/CVF durable row ordinals and bounded metadata chunks supplement, never
replace or rewrite, their legacy content identities. Their independent bounded
closure certificate is anchored in promotion provenance. Graph retained reopen
independently validates actual parts, count equality, grant ceilings, content,
binding and descriptor roots. Graph/table promotion publishes the complete
declared group through the existing transaction. Graph replay uses the exact
descriptor, including associations, rather than only the graph content root.

Failure cleanup explicitly closes graph staging connections, removes partial
returned graph stages when another mixed output fails, discards newly allocated
failed ABI4 session clones, and retires owned graph stages on session discard.
No new executor, pack-specific branch, scientific operation or profile change.

**Matrix source authority remains fail-closed**, pending the separately requested
Controller certificate decision. Matrix-to-unbound-graph is implemented; this
does not claim matrix-bound publication authority.

## Frozen independent interoperability subset

Quill affirmed the following byte-identical schema subset and synthetic fixture
before live cross-language integration. This is not a final whole-feature freeze:

| Asset | SHA-256 |
| --- | --- |
| graph-v1.schema.json | 760e031210948c1194183061472921520037f6dbb34bd1388233ce9476f0a007 |
| operation-pack-v4.schema.json | 9a994504e03c847bbc876c23f7bf06171da4ce8b2a5bc11f5e69d12084af71d7 |
| transition-request-v4 | e95e0dd7e86456edccc3b4097a9d10a9210d3371c64e3ce2e14159053d14bb1c |
| transition-receipt-v4 | 9eb38dc446aa0791d16868660c10901ad5db933ed73ba6cdf03abfd34173aa2e |
| process-v5 Python sidecar schema | d8a2c7cc15d276f3d72eeffbb153fa336f4fc6b8b6532907d58abf3920d642b1 |
| synthetic mixed fixture | 171c3a0dbbff36612c276a600e60b54da1558b68b3850efbbbd8748f7398def4 |

The process-v5 sidecar deliberately retains Python runtime schema/identity v4;
its request/capability/definition identities are v4. Closed-schema validation
rejects unknown/substituted schemes and self-rehashed malformed runtime evidence.
The synthetic fixture is only a protocol probe, not installed-wheel or actual
R-issued broker evidence. Its synthetic distribution identity must not be
reported as an installed pack identity.

Quill's constructor-cleanup peer is
`ff0f8d2958bd6fe25a8dc7751045411742a1a3df`, with unchanged protocol bytes.
The installed fixture pack identity is
`cc77d7634c53a3ce6dab3d3a492f22f1340f9bd8ac309d74fb93ab79f1778a09`.
The opt-in `test_graph_abi4_python_live_contract.R` is not yet a claimed pass.

## Retained focused evidence

All records use `inst/ci/run_logged_gate`; raw failures and numeric exits remain
unchanged under [evidence](evidence/). No canonical suite/package check ran here.

- 59: `Rscript notes/generic_graph_implementation/run_focused.R`:
  `GRAPH_FOCUSED_SUMMARY discovered=20 executed=20 passed=20 skipped=0 failed=0`.
  This earlier run still emitted the connection warning diagnosed below; it
  does not qualify later changes to that boundary.
- 56: sidecar scheme/adversarial function: `ABI4_RUNTIME_SCHEMES passed=1 skipped=0 failed=0`.
- 57: abandoned staging finalizers: `GRAPH_STAGE_FINALIZER passed=3 skipped=0 failed=0`.
- 58: actual count ceilings, self-rehashed count alteration, cleanup/retry and
  transport seal tests: `GRAPH_RETAINED_COUNTS passed=2 skipped=0 failed=0`.
- 60: explicit session discard: `GRAPH_SESSION_DISCARD passed=1 skipped=0 failed=0`.
- 63: exact new fixture admission/negative axis declarations and byte parity:
  `GRAPH_SHARED_SUBSET schemas_byte_identical=5 synthetic_fixture_identical=1 admission_passed=2 skipped=0 failed=0`.
- 64: public native matrix/graph/CV-bound graph/table, promotion/publication faults,
  partial mixed load cleanup, finalization and fresh-process pack-free relocated
  inspection: `GRAPH_PUBLIC_WORKSPACE_CLEANUP passed=1 skipped=0 failed=0`.
  Child: `GRAPH_RECIPIENT_PROCESS pack_free=TRUE read_only=TRUE relocated=TRUE descriptor_unchanged=TRUE sources_verified=TRUE recipient=PASS fingerprint_unchanged=TRUE`.
  No leaked-connection warning. Expected small-matrix compression/dense-conversion
  warnings are retained and are not test skips.
- 65: unchanged ABI2 activation and ABI3 native lifecycle:
  `LEGACY_ACTIVATION_REGRESSION passed=2 skipped=0 failed=0`.

Initial cached whitespace inspection reported trailing spaces in immutable raw
R diagnostic logs. A narrowly scoped Git attribute excludes only these raw
`evidence/*.log` records from whitespace checking; their bytes are unchanged.
Source, documentation and fixture checks remain enabled. Cached diff inspection
was rerun after recording this exception.

The leaked-connection warning was reproduced independently. Stage finalizer
registration preceded SQLite pointer registration, and failed public ABI4 calls
left newly created private session clones unreachable by the caller. Both
ownership paths now have explicit cleanup; the corrected public gate is 64.

## Focused review and unfinished qualification

Sable `/root/sable_graph_design` performed read-only source review, identified
retained-count and partial mixed-load cleanup defects, and confirmed both R
corrections in code. She also independently compared all five schemas and
identified a Python constructor cleanup defect, which Quill corrected at the
peer above. This is not final Sable/Meridian acceptance, live runtime parity or
measured core memory qualification.

Next work remains authorized: installed real R-issued Python broker execution,
SDK scaffold/catalog/documentation/tutorial completion, normative scenarios,
adversarial closure, measured complete core scale/lifecycle and the pending
matrix certificate decision. Broad core/Python/package qualification runs once
only after the exact clean full candidate tuple stabilizes. No merge, push,
tag, SIF/container or official-pack/profile modification.
