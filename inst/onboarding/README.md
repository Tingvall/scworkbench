# scworkbench Onboarding Library

This directory is the canonical, shipped onboarding library for human and AI
operators of scworkbench. It is included in the source distribution and in an
installed R package.

## Find It

From a repository checkout:

```text
inst/onboarding/
```

From an installed R package:

```r
system.file("onboarding", package = "scworkbench")
```

For example:

```r
file.path(
  system.file("onboarding", package = "scworkbench"),
  "AGENT_OPERATOR_GUIDE.md"
)
```

## Start Here

Read [SYSTEM_OVERVIEW.md](SYSTEM_OVERVIEW.md) first for the current core/pack
partition, activation, eleven primitives, centralized chunking, and backend
limitations. For reusable scientific methods, use the installed
[Operation Pack SDK guide](../sdk/operation-packs/GUIDE.md), not the engine
extension loop. Run its tutorial before implementing a new method.

1. **Any scientific or computational operator:**
   `AGENT_OPERATOR_GUIDE.md`
2. **Scientific analysis role:** `AGENT_BIOLOGIST_GUIDE.md`
3. **Engine or consumer development role:** `AGENT_ENGINEER_GUIDE.md`
4. **Shared vocabulary and invariants:** `SHARED_FOUNDATION.md`
5. **Operational analysis/development loop:** `PLAYBOOK.md`
6. **Common analysis patterns:** `RECIPES.md`
All roles begin with the auditable-transformation law in the operator guide,
biologist guide, and playbook: scientific results must be recorded through
engine contracts, while reports consume rather than create evidence.

## Canonicality

Do not create project-specific copies of these guides. Local projects may link
to this directory and add data-specific constraints, but the engine operating
model belongs here.
