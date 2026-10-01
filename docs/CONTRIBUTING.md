# Contributing

Contributions should preserve scworkbench's typed bundle and provenance
contracts. Open an issue before substantial API or schema work and describe the
scientific capability, durable entities affected, provenance edges, failure
atomicity, and expected recipient behavior.

Use a focused branch. Add executable contract coverage for behavior changes,
regenerate derived documentation, and run `git diff --check`. Registered
operations must declare typed inputs, outputs, terminal promotion routes, and
all parameters through `inputs`. New mutation paths must use the writer lock,
path-containment, atomic publication, and immutable-history APIs.

For a scientific method over supported primitives, start with the
[Operation Pack SDK](operation_pack_sdk.md). Do not add method-specific branches
to core or duplicate primitive slicing. A new primitive needs its storage,
identity, reader/writer, promotion, and backend contracts specified together.

Scale validation with scope: documentation-only changes need link, policy,
generation, and diff checks; narrow behavior corrections need the affected
contracts and relevant composites. Run complete-discovery canonical,
source-package and cross-runtime gates for the frozen integration/release
candidate. Reused parent evidence, skips, notes and unsupported runtimes must
remain explicit. Method tests live in packs; core tests exercise generic
authority. Do not commit
bundles, model payloads, credentials, local paths, SIF images, or generated
analysis outputs.

See [Release process](release_process.md) for release-level gates.

## Documentation Maintenance

The documentation policy inventories maintained guides, installed onboarding,
SDK resources and generated references. Historical audit notes and fixture
records retain their original qualification boundaries; they are not current
operator instructions. An old installed package or SIF is not refreshed by a
source-documentation edit.

From the core source root, check R examples against current exported APIs and,
optionally, the official pack manifests:

```bash
Rscript --vanilla inst/dev/audit_agent_documentation.R /path/to/operation_packs
Rscript --vanilla inst/dev/regenerate_public_docs.R
git diff --check
```

The static audit checks parsing, public function/argument names, literal pack
operation parameters and source references. It does not execute dataset-specific
examples or establish scientific equivalence. Run the focused documentation
contracts and installed SDK tutorial for their respective executable coverage.
Inspect generated changes before committing; the generator's `--check` mode
checks committed HEAD, not uncommitted edits.
