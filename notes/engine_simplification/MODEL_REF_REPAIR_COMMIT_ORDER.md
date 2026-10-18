# Legacy model-path repair: commit before publication

Source checkpoint only, not installed qualification. Separate correctness fix
from recipient file observation performance work; no identity or schema change.

The unchanged relocatability test independently failed on old242 installed
namespace (DLL6f9ad522ccddd74db7b2638c7910074313c5a4672ba847ca6e348e7a8e755740),
exit1: manifest refresh ran inside dbWithTransaction. Raw exact command/stack:
`/tmp/scwb-engine-simplification-forge-20261018/model_ref_old242_diagnosis.log`
and numeric sidecar retained. The strict precommit-publication guard stays.

Existing writer context/lock remains. Reject caller-owned transaction before
repair mutation; successful dbWithTransaction return means COMMIT, then copied
payload ownership transfers to committed registry/provenance before refresh.
Precommit errors roll back and delete only this repair's copied targets.
Postcommit manifest publication error propagates but retains referenced bytes
and committed SQL/provenance; old manifest stays atomic and explicit guarded
refresh may retry. Never delete committed bytes to simulate rollback.

Focused tests add transaction-abort cleanup/retry, postcommit publication fault
with exact committed bytes/provenance/old manifest and explicit refresh/reopen,
and caller-owned transaction rejection. Existing relocatability and containment
contracts remain required. No tests or install run at source checkpoint.
