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
