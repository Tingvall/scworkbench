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

Primary exactbit64 source: CRAN Archive/bit64/bit64_4.0.5.tar.gz,
R/integer64.R2128–2160 `[.integer64`: preserves oldClass around NextMethod's
indexed subset; missing-index handling inspects INDEX only. Existing helper
creates ordinary nonmissing bounded indices, never reads payload as real.
RSQLitev2.3.7 src/SqliteResultImpl.cpp bind_parameter_pos distinguishes REAL
carriers inheritinginteger64 before ordinaryREALSXP and binds signed64 values/
NA64 via sqlite3_bind_int64/sqlite3_bind_null. No coercion/double arithmetic.

One fifth test adds exact SQLite CAST(id AS TEXT)/typeof proof across signed
extremes/2^53/NA64, supported actualbatchlength, unknownversion privatecopy
fallback, UNIQUE/CHECK/FK and ABORT/FAIL/ROLLBACK prefixes/ownedTX/retry. Existing
extendedfallback test now covers extra-attributed/cache, subclass and named
integer64 rather than incorrectly demanding fallback for newlysupported exact
class. No warning/assertion suppression; four earlier contract definitions stay.
