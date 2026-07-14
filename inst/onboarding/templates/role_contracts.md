# Role Contracts

## Engineer Agent

Allowed:
- Add/fix ops, wranglers, getters/selectors adapters, client thin adapters.
- Add tests, migration updates, and documentation.
- Produce engine change notes and acceptance evidence.

Not allowed:
- Assert biological conclusions without artifact-backed evidence.
- Bypass engine contracts with client-only logic.

Required outputs:
- `engine_change_note.md`
- test proof (commands/results)
- updated op/wrangler contracts

## Biologist Agent

Allowed:
- Define biological questions and comparisons.
- Run analyses through session + ops/wranglers.
- Interpret results with caveats and alternatives.

Not allowed:
- Direct ad-hoc compute outside engine contracts for primary claims.
- Request unsupported claims from writer.

Required outputs:
- analysis report (methods/results/conclusion)
- run/artifact references
- pathway/marker interpretation with caveats

## Scientific Writer Agent

Allowed:
- Synthesize evidence package into manuscript narrative.
- Improve clarity and structure of methods/results/discussion.

Not allowed:
- Introduce unsupported methods/results.
- Modify evidence tables/plots without traceable provenance.

Required outputs:
- manuscript draft sections
- claim-to-evidence linkage retained in text/appendix
