# Homogeneous scalar-leaf object rows: prospective budget

31,535 feature annotation rows shaped `{feature_id,values:{feature_type}}`
are canonically encoded nine times by existing authority boundaries. Keep all
nine checks. The alternating outer/inner key shapes defeat the existing
last-key plan. This is a serializer implementation change, not a new identity.

Target before measurement: at least5x component speedup for31,535 nested rows
and the representative flat11-field row shape, byte-identical to the frozen
independent encoder. No timing result is claimed. Existing workflow performance
misses remain misses until measured.

Fast eligibility: ordinary unnamed outer list; homogeneous ordinary named-list
object shape, depth<=8, total keys<=128; plain scalar NULL/integer/double/logical/
character leaves only. NULL fields remain fields, not absent keys. Complete
nonthrowing eligibility over ALL rows precedes any optimized output assembly.
Anything mixed, attributed, invalid, unsupported, locale-ineligible or outside
the temporary budget returns to the untouched original row-major encoder.

At most1000 rows are gathered at once. Conservative temporary ledger per batch:
256 bytes per compiled node per row plus eight times the escaped-string/numeric
and structural byte upper bound, and64KiB fixed allowance. Strings use6*UTF8
input bytes+2; finite numeric scalar allowance32; logical/null allowance5;
escaped key prefixes are counted per object row and compiled once. Admission
caps temporary work at min(32MiB,the existing ordinary dense-memory guard).
No new limit/rejection: over-budget cases use the original encoder. Final
canonical output remains intentionally MATERIALIZED by the existing API; this
is not a claim of a universally bounded or streaming JSON interface.
