# Session/source scope budgets, pre-implementation

Use repaired 8f53e950 baseline. Five repeated source registry observations on
one unchanged live source connection must require one full content-derived
registry scan, subsequent checks <=0.05 s each. Same-connection DML, another
WAL connection's commit, schema change, rollback and explicit restore invalidate;
resume/new connection always recomputes. No active transaction may supply a
stale committed snapshot. Source comparison stays under source lock and again
under the destination promotion lock before writes. No timestamp authority.

An unrelated small operation should perform zero prior-output payload hashes.
A run-ref or recognized staged-ID input must verify its producer group once;
uncertain direct file-backed inputs keep conservative all-ledger verification.
Promotion verifies the full selected ancestor closure once under destination
ownership, not twice-all-session at entry. Recovery verifies all ledger entries.
The prior absolute/history budgets in baselines/BUDGETS.md remain unchanged.
Unselected corruption detection is deliberately deferred to consumption,
selection, recovery or explicit validation, not claimed to have vanished.
