# Phase 0 historical compatibility policy

## Immutable identity rule

Existing bundles, run records, operation definitions, catalog digests and frozen evidence retain their recorded unqualified operation names. They are never rewritten to a future pack namespace. The accepted no-pack catalog at scworkbench `4f7420899db650d895505202e7e9827ea5814b62` has 60 operations and identity `e6a4e1713d1e8e4a3b044d285e6e510afdef46c6d56966f72a15725eea550445`.

Future executions use the approved fully qualified packed identity. A convenience command alias may help a user select that new operation, but the engine must resolve it before execution and record the immutable fully qualified definition identity. An alias must never change the meaning of a retained record or cause a historical replay plan to select new code.

## Inspection and replay

- Opening, listing, validating and inspecting retained outputs must work without the producing pack.
- Executing a migrated operation requires its exact compatible pack and fails before method dispatch when absent.
- Historical replay requires the exact historical core implementation/definition or an explicitly qualified compatibility implementation proven equivalent to that recorded identity. A same-named packed method is not automatically equivalent.
- Pack installation or activation order must not change catalog identity.
- Missing external source bytes remain an inspection boundary, not a bundle failure or proof that the source was verified.
- Retained warnings and historical identifiers remain intact.

`core_to_packs_phase0_historical_compatibility.csv` enumerates all 60 current identities and future proposals. Retained-bundle references come from read-only `prov_runs` queries against the five accepted final/reproduced bundles; publication references are exact-name occurrences in the definitive reports, claim maps and Phase 2 evidence records. Empty arrays mean no occurrence was located in those authorities; uses are not inferred from prompts or general catalog listings.

## Command compatibility

The proposed namespaces are working recommendations pending Controller approval. For a migrated method, an unqualified interactive name may resolve only when unambiguous and must report the selected fully qualified identity before execution. Ambiguous names fail closed. Core's four retained operations remain unqualified historical/public names unless a later versioned policy explicitly changes them.

`cell_vector_assoc` and `cell_vector_association` remain distinct definitions. No alias or consolidation is authorized until their contracts and historical uses are independently adjudicated.

Compatibility establishes technical identity, inspection and dispatch behavior. It does not authenticate operator identity, validate biology, rank branches, sandbox installed code or guarantee replay across arbitrary platforms.
