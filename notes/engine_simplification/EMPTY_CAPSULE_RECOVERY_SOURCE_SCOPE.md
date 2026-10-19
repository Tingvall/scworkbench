# Empty recovery source checkpoint — not executed

Only R/analysis_capsules.R is changed. Raw existing lock surrounds a full fresh
inventory and unchanged pending/orphan validation and final no-residue proof.
The current no-work path returns the same two-field list without publishing or
checkpointing. A verified successful deletion sets a lexical boolean; removal
of an empty.pending directory also counts as work. That directory's deletion is
explicitly checked with the existing CAPSULE_RESIDUE_RECOVERY_FAILED code, so a
failed unlink cannot masquerade as successful no-work. Errors/partial cleanup
do not run the success tail. Actual work forces the existing manifest publisher
while lock-held, then runs the original best-effort TRUNCATE checkpoint.

If the caller already has a SQLite transaction, the original generic writer
route remains in use with its old nested/outermost behavior; no caller commit or
rollback is added. Explicit migration/refresh source is untouched. There is no
cache, persisted observation, new scheme/public interface or authority.

Budget-first commit precedes this source checkpoint. Exact source/test review
must precede installed tests and measurements. No runtime or performance check
has run for this source. Focused tests are being authored separately.
