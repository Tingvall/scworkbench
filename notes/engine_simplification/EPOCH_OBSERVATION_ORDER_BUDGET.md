# Observe the actual database list after metadata inspection

Before runtime changes: parent `fa9ab653f37bbc2514e6b3c6e3c828266cfa7f0a`
has unchanged871 runtime. The broad writer-tail experiment remains design-only.
This small preceding correction concerns the existing publication epoch itself,
not registry reuse, source authority transfer or a new cache.

The first observational workflow probe failed its final serialized-function
guard and retained ZERO candidate observations. Preserve its outer1/inner03=1:
`T/registry_writer_tail_samekey_probe`. It is not a passing acceptance probe.
The actual old strong key also differed before/after acquisition: database_list
contained main+TEMP before and main only afterward. Main counters and complete
TEMP version0/data1/empty definitions matched. Do not ignore that old key miss.

Independent owned-only diagnosis `T/registry_epoch_function_diagnosis`, six
inner gates0 and outer0, reproduced old-key mismatch and proved all other
fields exact. Actual database_list queried AFTER each epoch's own metadata
inspection matched exactly; diagnostic candidate keys using those actual final
observations matched too. No runtime key was changed by that diagnosis.
Actual keys SHA256 `70aeeb078eab5816c659fb63033598378d55045592704db2f8821a028daabf73`;
function findings SHA256
`c9e5ea2633df58c7212f98163a569e67e2a0c6fdea760a705b01fe2da912e735`.
All five helpers' function identity/AST/formals/environment/srcref/attributes
were equal while serialization v2 AND v3 bytes and function digests changed.
This establishes serialization instability with unchanged listed properties,
not JIT causation or retroactive success of the failed workflow probe. Future
source guards must eagerly capture AST/formals/environment/bindings and lock
actual installed/source files, not treat whole-function serialization as code.

Cause of metadata-order mismatch: publication_epoch records database_list
BEFORE explicitly inspecting TEMP, although those very queries can register
empty TEMP. The registry snapshot's existing scoped FILE/restore policy can
detach empty TEMP again. The returned key can therefore describe an earlier
bookkeeping state instead of the actual state after its own read-only queries.

Narrow proposed fix: retain initial database_list to select ALL schemas exactly
as before, perform all original actual schema/counter reads, then observe the
actual final database_list. Require exact initial/final NON-TEMP seq/name/file
rows and coverage of every final database name by inspected schemas, otherwise
return NULL so callers take their full path. R dataframe row labels are not
SQLite association fields; compare normalized carrier labels, never normalize
seq/name/file. Return the actual final TEMP row and its complete schema/counters,
not a synthetic entry or filtered view. No schema, scientific content identity,
wire protocol, migration, publication frequency or source/payload check changes.
Mutation context lifetime remains unchanged.

Prospective numerical budget BEFORE code:100 ordinary metadata-epoch calls
must be <=matched parent*1.15+.02 seconds, whole-process RSS <=parent*1.10.
The extra constant-size database-list query is expected and must be counted;
no scientific data scan or hash is added or removed. No lower bound or gain is
claimed. The writer-tail20%, typed-space5s/helper50% and full-Xenopus171.124s
targets remain unwaived. This is not permission to begin reuse implementation.

Focused qualification: actual empty-TEMP/scoped-resource transitions and stable
repeated keys; exact complete schema/counter retention; genuine TEMP definitions,
main DDL with reset cookie, attachments and foreign writes remain invalidating;
actual attachment changes during key acquisition return NULL; existing explicit
refresh/migration/publication/fault/close contracts remain unchanged. Source
review exact patch before one corrected observational workflow probe. No full
suite or new whole-workflow retiming for this intermediate correction.

Sable source-principle assessment, not candidate acceptance:
`/tmp/scwb-sable-epoch-temp-order-diagnosis-20261019/assessment.json`, SHA256
`0eab9aaf9adbfb38ca282c8a619232589fbc1ebb5e98be05c57697ec3e264a42`.
