# Prospective ordinary scalar table reconstruction

Baseline f315f7122ced2ec45d1c451311744fc0740e9464. Commit budget BEFORE code.
Target >=5x complete50000-row public getter, RSS<=matchedold+10%; exact original
dataframe types/values/order/metadata, parser errors and table.v2/stream.v1 hashes.
No success or performance qualification claimed at this source checkpoint.

Parent retained one50k×3 publicobs-table profile: total12.246s; disjoint10ms
buckets dataframeconstruction9.55,rbind1.20,JSONparser.50,SQL.03,other.95s.
Rprofmem6.9GB cumulative allocation is NOTpeakRSS; wholeprocessRSS318300KiB.
Values/order/types/meta/contentidentity and four fixturefileSHA were unchanged.
This supports framework assembly cost, not arbitrary JSON parsing replacement.

Keep ALL original fromJSON parsing and NULL normalization unchanged. After rr
is parsed/normalized, only ordinary flat scalar rows with unique unchanged
syntactic consistentlyordered names use one-column-at-a-time assembly. Original
already-parsed rr feeds untouched per-row as.data.frame/rbind on unsupported
shape/type/name/attribute/warning/error. No second parser or new rejection.

Additional local carriers<=64*N+1024*C+65536+8*sum(keybytes), within
min32MiB,existing plain ordinaryguard/4. NoN*C metadata/vector cache; source rr
and returned dataframe are existing materialized getter contract, not claimed
bounded whole-table output. Large/nested/deferred/classed/unknown guards fallback.
One current output column assembled at a time; temporary refs cleared before
next. Integer+double promotion supported; logicalNA neutral; allNA logical.
Other mixed types/reserved names/missing keys/duplicate names retain old behavior.

Source review required before installation/tests/performance. Focused literal
old-helper differentials, malformedlateJSON/errorprecedence, bounds/fallback,
complete legacyidentities and publicgetter filesystempurity must precede claims.

Implementation source scope: R/artifacts.R only, plus four focused test
definitions. No parser, serializer, hash scheme, SQL, storage or validation
authority changes. No R/jsonlite version-specific allocation optimization:
ordinary public base dataframe attributes and parsed scalar types are used;
the unchanged parser still determines integer/double/logical/string carriers.
The candidate calls make.names only after the complete key-byte envelope is
admitted, and requires its result to be identical (no repair or reordering).
Reserved data.frame formal names retain the original as.data.frame.list route.
The compact row.names representation is the ordinary public dataframe form.
No source-extent schedule or N*C type matrix is built. A C-length kind vector
and a single current output column are working carriers; completed columns
are the existing materialized return payload. This is not a bounded-output
API or a universal process-RSS claim; matched RSS remains an independent gate.
The original whole-row parser and its precedence over assembly errors remain.
