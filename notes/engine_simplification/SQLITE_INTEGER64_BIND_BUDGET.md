# Prospective exact integer64 vector binding follow-through

Basef315f7122ced2ec45d1c451311744fc0740e9464. Ledger committed BEFORE edits.
No runtime execution. Retain scoped-binding budgets: >=5x complete100k insert
readback, >=25% actual promotion, RSS<=matchedold+10%. Additional recognized
family50000-row append target>=5x versus plainprototype's existing int64 fallback.
No microbenchmark result substitutes for actual promotion/workflow evidence.

ONLY double payload with EXACTclass integer64, soleclass attribute, loadedbit64
4.0.5 under existing RSQLite2.3.7/DBI1.2.3 gates. Indexed bit64[ subsetting only;
never numeric coercion/is.na/is.finite/arithmetic on int64 payload (validnegative
bit patterns can look like NaN). Unknownversion/subclass/names/cache/attrs retain
original rowwise path. Existing256*rows*columns+stringbytes+64KiB allowance covers
8-byte raw int64 slots plus class header; batch ceilings/statement/TX unchanged.

Required positive actualvectorlength and original orderedCAST(id AS TEXT)/typeof
near±2^63 and±2^53/NA64; unique/check/triggerprefix/callerTX/rollback+retry.
Former int64 fallback case becomes extra-attributed/subclassed int64, preserving
unsupported fallback coverage. Source review BEFORE jobs/install/benchmarks.
