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
