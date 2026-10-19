# Source-only matrix fragment axis JSON candidate

Parent is selected a90b234, not the unselected native-registry experiment.
Prospective complete-operation budgets were committed first in45fb291f.

Only two existing assignments in `wb_register_matrix_fragment()` change.
Feature/cell coercion, path validation, missing/duplicate checks, disjointness,
identifier allocation, insertion order, savepoint/rollback and payload storage
remain in their original order. There is no SQL-copy or shared canonical encoder
change. No scientific operation, C/Python/backend or identity scheme changes.

The helper's proposed eligible envelope is intentionally narrow: postexisting-
coercion character vectors with no attributes, printable ASCII bytes, unknown
Encoding, jsonlite1.8.8, and conservative optional working-memory admission.
It uses `toJSON(ids, auto_unbox=FALSE)` rather than constructing a scalar list.
The literal old expression handles empty, named, attributed, unfamiliar encoding,
control/Unicode, missing and unknown-policy cases without a fast attempt. The
helper performs no extra axis coercion and no warning/error-catching retry.
The working estimate includes128bytes/element and8encoded upper-bound carriers,
limited to min32MiB and one eighth of the ordinary dense guard. Ineligibility
never introduces a public memory error. No observation or result is cached.

Five authored contracts use a literal pre-change encoder and captured ordered
warnings/errors, including supported31535-ID axes, locale alternatives, unusual
encoding/control cases, exactly-once coercion and opaque fallback side effects.
Public ingestion tests inspect persisted JSON and membership row order, numeric
getter results, finalized read-only purity, overlap refusal and an actual SQLite
membership-insert fault followed by rollback and immediate retry. Existing
legacy-overlap getter contracts and operation receipt/publication contracts
remain necessary affected checks; the new tests do not substitute for them.

SOURCE ONLY: no R/Python invocation, parse, install, test or measurement has run.
These are prospective parity assertions, not proof of byte equivalence or gain.
Ordinary deferred character vectors may be forced by the writer's unchanged
validity/duplicate checks and the eligibility scan. This does not claim support
for arbitrary externally supplied custom ALTREP implementations or hostile
method dispatch. Attributed inputs take the old route before optional scans.
Non-ASCII inputs remain supported by the unchanged fallback, not qualified as
fast inputs. Unsupported future jsonlite versions also retain the old route.

Next, coordinator-owned independent old/new byte/error/warning qualification and
focused installed lifecycle checks must pass before3alternating fresh complete
normalization trials per revision/fixture. Separate census must demonstrate
actual route use and unchanged authentication frequency. All old performance
misses remain unwaived. No source-only result implies whole-engine acceptance.
