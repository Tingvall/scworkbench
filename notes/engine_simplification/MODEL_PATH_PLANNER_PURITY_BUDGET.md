# Model-path planning: observational schema admission

Parent source: `a2abafb2c2be7715bcdc8cb4878c726978b59063`.
Policy approved by Sable before implementation. No runtime qualification yet.

Only `dry_run = TRUE` replaces migration with existing observational schema
admission. Current writable and read-only bundles classify the same paths;
legacy or corrupt schemas reject with explicit writable-migration guidance.
Real repair retains migration, caller-transaction rejection, copy/transaction
rollback, post-commit publication ownership and retry unchanged. No external
path search/probe authority or identity contract changes.

Prospective component budget: repeated planning on the current small model
fixture <=0.1 seconds per call, zero migration/publication calls and zero extra
whole-manifest snapshots. This is not a full-workflow performance acceptance.
No measurement or runtime test has been run for this source checkpoint.

Focused qualification after exact-source review must execute these three new
purity contracts, existing three model-repair publication contracts and model
relocatability coverage against the actual installed candidate. Filesystem SHA
inventories and SQL counters bracket planning, not setup or teardown.
