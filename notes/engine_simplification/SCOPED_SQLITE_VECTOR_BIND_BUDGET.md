# Prospective bounded SQLite binding optimization

Baseline exact163562a2f1704c6f2ccd6e97355b37fd93c6afcf. This ledger is committed
BEFORE runtime edits. No install/test/benchmark at this checkpoint.

Targets: >=5x faster complete10000/100000-row insert+ordered readback;100-row
absolute added overhead<=0.02s; RSS<=matchedold+10%; actual promotion>=25%
faster independently measured (never inferred from microbenchmark). Existing
workflow/promotion budgets and misses remain unchanged until actual evidence.

Scope ONLY .wb_db_append_chunked. Same preparedstatement/SQL/caller transaction/
order/resultcleanup. Exact loadedRSQLite2.3.7 andDBI1.2.3, realSQLiteconnection,
ordinarydata.frame/attrfree INT/REAL/LGL/ASCIIcharacter+NA columns. All unsupported
backend/version/class/list/BLOB/encoding/custom paths retain original rowwise
binding. No new identity/storage semantics or exception catch-and-retry.

Maximum batch=min(validatedchunk_size,1000). Before any row subset, conservative
additional carrier envelope256*N*C +8*actualsourceASCIIstringbytes +65536,
within min32MiB,existing ordinaryguard/4. Unknown/activegraphpolicy falls back
old rowwise (no unaccounted graphmemory). Oversize/unknown guard or eligibility
falls back untouched; no new resource error or raised guard. Eligibility must be
nonthrowing; actual bind errors propagate immediately with original prefix.

Required focused proof: copied literaloriginalhelper orderedrows/rowid/typeof/
hexNULLs; autocommit/ownedTX; UNIQUE/CHECK/FK/triggers and ABORT/FAIL/ROLLBACK late
inside andatbatchboundary, exact prefix/trigger effects/rollback+retry; supported
positive actual vectorbindlength; extendedtypes/encoding fallback; tinyguard/
wide/string admission fallback; closedstatement after faults. Source review
before execution. Unknown driver semantics are not silently widened support.

## Exact source assessment (not measured attribution)

RSQLite tagv2.3.7 primary src/DbResult.cpp47–84 verifies equal parameter lengths.
src/SqliteResultImpl.cpp128–148 sets groups/firstrow and immediately steps;
bind_row221–241 resets/clears SAMEstatement and binds each column at current
group; bind_parameter_pos244–300 preserves NULL/integer/double/logical/text
carrier semantics; after_bind303–307 and step334–366 iterate rows in order,
advance group only after SQLITE_DONE, throw actual sqlite message on failure.
These functions start no new transaction. R/db_bind.R applies its unchanged
factorwarning/stringUTF8 rules before nativebind; unsupported/classed/encoding
carriers therefore stay original rowwise to retain warning/error prefix behavior.
Primary URLs: https://github.com/r-dbi/RSQLite/tree/v2.3.7/src and /R/db_bind.R.

Native trusted-R is not a hostile sandbox. Small metadata-only column slices
for <=1000indices/Encoding/nchar/ASCII check fit initial256*N*C+64KiB admission;
full dataframe subsetting occurs ONLY after actual stringbytes complete the
carrier+8*stringbytes budget. Sourceframe already caller-owned; no whole-source
copy/preflight, source fingerprint, cache or new framework introduced. Active
graphpolicy and unknown guard simply retain original per-row path. Failed bind
is never retried under a different route: original caller-owned transaction and
SQLite partial prefix remain authoritative.

Focused tests include a literal copy of original preparedstatement/per-rowloop,
actual parameter vector-length spy with exact namespace cleanup, full ordered
rowid/typeof/texthex/NULL/numeric parity,72constraint/trigger/TX cases at bounded
chunk boundaries, extended/classed/raw/encodingfallback, string/wide/tiny/unknown
budgetfallback, and explicit caller rollback/retry/statementcleanup. They are
not installed qualification yet. Per-artifact/promotion binding census still
needed; earlier final242 trace did not instrument this helper or dbBind.
