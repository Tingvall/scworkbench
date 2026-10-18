# Issued-space schema admission consolidation

The original realistic-operation five-second budget remains unchanged. The
13de629 measurements (42.872/42.560 seconds) and sampled guard2.10 seconds,
registry-row2.05/schema-component1.89 seconds are overlapping attribution, not
additive costs. Prospective boundary budgets: zero full schema admissions per
issued-plan block; full admission on initial and independent final issuance;
mean lightweight guard at most5ms in a warm100-call component observation.
No measurement is implied by this source checkpoint.

Sable reviewed the policy before implementation. The issuing getter performs
explicit observational schema/ledger/FK/table admission once, before metadata
queries. Each guard still freshly queries the entire parameterized registry
row and compares exact row types/values, path, resolved target and file
observations. The same issuing connection reference must remain valid. No
registry values, schema verdicts or scientific hashes are cached across plans.
The fresh final plan repeats full schema and content authority; a callback's
lightweight observations are not a replacement schema/deep-validation boundary.

The old private registry helper can lazily run CREATE IF NOT EXISTS when its
component check returns FALSE. A separate diagnostic against installed13de629
actually reproduced `BEFORE_SCHEMA_STATUS=invalid_ledger
TYPED_READER_ADMITTED=TRUE` (typed_schema_ledger_before.log/.exit0). This is
a reproduced defect, not a passing invalid-state test. The new typed reader
does not invoke that creator and rejects invalid schema without writes. The
generic registry helper and its other callers are unchanged in this slice.

Missing/dropped rows or tables and changed bindings abort, and connection
replacement cannot inherit a plan. Tests separately exercise fresh rejection of
malformed ledger, missing table and malformed TEMP shadow, with zero SQL data
changes during rejection. Conforming TEMP shadow semantics are not silently
redefined. Exact callback data, file observations, source hashes, independent
final authority, publication and recovery checks remain mandatory.
