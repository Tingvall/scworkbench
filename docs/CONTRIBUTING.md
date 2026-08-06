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

Before requesting review, run the focused tests, complete-discovery canonical
gate, source-package contract, and relevant cross-runtime tests. Do not commit
bundles, model payloads, credentials, local paths, SIF images, or generated
analysis outputs.

See [Release process](release_process.md) for release-level gates.
