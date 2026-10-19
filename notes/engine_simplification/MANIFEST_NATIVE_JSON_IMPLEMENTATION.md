# Native bounded metadata row JSON: source checkpoint

Precode parent `c201b76` froze the actual P-parent follow-on ceilings BEFORE this code: large<=4.0509s, RSS<=219665.6KiB and tiny<=.4204s, with tighter retained older caps (including RSS219599.6) still unwaived. P4.501 and R-ASCII5.901 misses remain recorded; no causal claim about those misses is made. This branch contains P/f6, NOT the rejected R-ASCII serializer or graph handoff.

## Semantics and eligibility

One private registered three-argument `.Call` in the existing DLL returns NULL or a complete JSON string; no public primitive/wire/hash/API scheme changes. `src/manifest_json.c` is a separate module, not the scientific canonical-number formatter. R checks exact R4.4.1/jsonlite1.8.8 and symbol availability once per table. Unknown backend or absent symbol always retains the original `toJSON` call.

C inspects raw ATTRIB pairlists, not getAttrib(row.names), so compact c(NA,-N) rownames are not expanded. Exact ordinary data.frame attributes only; at most5000 rows/8 columns; no ALTREP/classes/custom attributes on columns or explicit rownames. All column metadata checks occur before reading lengths/values. Accept compact negative row count, or explicit plain nonnegative integer/digits-only rownames in exact row order. Nonnumeric names would introduce jsonlite `_row` and are rejected. Classed/ALTREP/deferred carriers return NULL before forcing their values. Exact dataframe class is checked directly.

Actual field names must independently be nonempty<=256 safe native ASCII strings, unique and in source column order. Each supplied key token must equal exactly quote+actual fieldname+quote by length/memcmp; no escaped/Unicode/odd fieldnames are handled. Ordinary native character values accept only<=256 bytes from `[A-Za-z0-9_.: /-]`, with NA null. Quote/backslash/controls/DEL/Unicode/other encodings fall back, never escaped by new code. Plain int32 decimal tokens use bounded `%d` only after NA sentinel handling; logical tokens true/false/null. REAL/int64/date/factor/list/unknown classes retain the original serializer. The global canonical scientific formatter is untouched.

## Two passes and byte/resource ledger

The first pass fully validates ALL actual values and counts exact JSON bytes with overflow-checked size_t addition, including keys, punctuation, all quoted lengths, row separators, decimal integers and nulls. The NUL-inclusive output extent must fit INT_MAX. No row-sized R vectors, lists, strings, growth arrays or output buffer are allocated on an unsupported path. Fixed stack metadata is eight column references/types/key pointers/lengths plus a16-byte integer buffer and scalar counters (conservatively<1KiB).

Require exactE<=old_admitted_E and `6*(exactE+1)+256 <=8*old_admitted_E` before allocation. This conservative ledger covers one R_alloc output buffer, final R CHARSXP/scalar headers, caller substring/encoding/raw emission and spare native/hash payload copies within the ORIGINAL8E allowance. It is not a new or raised quota. Fixed stack/header framing stays in the caller's existing B; selected dataframe/indices stay in Lt. Candidate/charge/prefix/eligibility arrays are cleared before the native call, retaining the existing128N reservation without simultaneous new speculative arrays. No graph/cache/policy changes occur. R string interning/global heap/RSS is not claimed as a hard quota; matched RSS remains an independent gate.

The second pass freshly reads each input element into that one buffer, with bounded checked appends and checked snprintf returns. Both passes check interrupts every128 rows. No allocation/callback occurs during ordinary emission except interrupt checks; inputs are non-ALTREP. A byte-count inconsistency errors before returning. Temporary storage unwinds with R; no FD/external ownership is introduced.

The caller preserves its final actual-byte<=old bound guard, complete5000 fold and all observer/file/source checks. `manifest_native_json` hook records native/fallback, rows, old encoded bound, actual byte count and the exact6E+256 ledger. Hook failures propagate OUTSIDE native/fallback logic. Whole-small-chunk path remains unchanged; no expected claim is memoized.

## Source tests, pending execution

Three definitions in `test_engine_manifest_native_json_contract.R`: literal unchanged jsonlite bytes/encoding for1/2/512/1000/5000 rows, compact/reordered/digits03 names, NA/stringNA/intlimits/bools/eight fields; complete unsupported/late invalid/duplicate field/key-association/rowname/ALTREP/size fallback; actual5001-row old registry identity plus known-backend positive native hook, fallback, fault cleanup/policy restoration/retry. Unknown backend expects actual fallback, not a fabricated native hit. Direct C-oracle tests are not backend admission claims. Existing P/f6/streaming/mixed/deferred/resource tests remain relevant.

No compilation, parsing, tests, installation or performance jobs ran while preparing this source checkpoint. Exact source review must precede execution; production eligibility and benefit are unknown.
