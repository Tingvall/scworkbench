# Selected-fragment getter validation: authorized boundary and fixed budget

Starting source06d70aea0886f585a80d24e42feee89b54f96f24, runtimeeb3791c;
installed parent DLL44fa1d27084f803b86aa10809e65975ff190e34e99a749a2f0c7e6565d3bbf54.
No runtime change has been made before committing this decision/budget.

## Controller decision

On2026-10-19 Controller explicitly approved: "Approve selected-fragment getter
validation; keep full checks at explicit validation boundaries." The question
specified deferring feature-axis JSON validation for cell-disjoint fragments
from ordinary reads to explicit content/recipient validation, with valid-source
results and selected-fragment alignment unchanged. This is an intentional error
boundary change, not a fixture correction, identity change or compatibility shim.

Cell-axis JSON still must be decoded to establish selection. A malformed cell
axis fails closed; selected malformed feature axes still fail. Cell parsing now
precedes feature parsing, so if BOTH are malformed the cell error may appear
first. Content/recipient validators continue checking every fragment; no
validator source may be weakened. Preserve default order, overwrite/zero/NA,
duplicate-selection and bounded physical read semantics. Apply consistently to
batch and single-feature matrix getters. No cross-call cache or decoded-axis
memo is needed.

The clean incomplete exact-preimage alternative59fd784c8ac20b660d96543d2a23137735dde5a7
is preserved separately, not integrated. Its original installed11/12 failure,
SHM-only writable-fixture diagnosis and corrected unqualified test remain
explicit. Its bracket-filename source finding is not waived or reintroduced.
The CSC branch842ff5b contains only prospective documentation, no runtime code.

## Measured premise and fixed budgets before code

T=/tmp/scwb-engine-simplification-forge-20261018.
Actual44fa attributionv2 outer0: public RNA512 identity1.345s contains1.057s
getter callbacks, parse_string self.48s. This is instrumented evidence, not a
plain median or production typed-plan attribution. All seven normalized
fragment feature-axis JSON strings are exactly430224bytes,31535 IDs; source
SHA inventory unchanged. Existing body decodes all seven axes before cell
intersection. Independent source gate and diagnostics are retained in T.

Three alternating fresh processes per revision, same owned immutable source,
default256MiB, exact installed namespaces and same numerical oracle:

- Four128-cell public batch reads of the first512 RNA_log_norm cells/all31535
  features: new median <=0.70*actual parent median+0.01s.
- Same pattern on one-fragment counts: <=1.10*parent median+0.01s.
- Maximum process RSS <=1.10*parent maximum, identical verification scope.
- Valid-source values, semantic identities, ordered axes and complete source
  filesystem inventory must match. Selected corruption and malformed cell
  axes reject; explicit content AND recipient checks must still report the
  unselected malformed feature axis after manifest refresh/finalization.

Actual plain medians remain pending. Whole-workflow171.124s, typed-space5s and
all other earlier budget misses remain failed. No complete performance claim,
retiming or waiver follows from selecting this narrower approved boundary.
No merge, push, profile/pack edit, container build or full-suite rerun.
