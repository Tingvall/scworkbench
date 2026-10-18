# Private matrix adapter: admission and lifetime ledger

This records implementation/source reasoning, not final performance acceptance.
The earlier `BPCELLS_NATIVE_BOUND_REVIEW_QUILL.md` is retained unchanged as an
independent c293 source review. Subsequent constants below are more conservative
for escaped axes and original physical selectors; they do not change budgets,
canonical identities, public grants or scientific parameters.

## Axes and backed plans

Before parsing an axis file, admit `128*count + 8*file_length + 65536` bytes.
The file must be contained; counts/lengths must be finite and exactly admitted.
The broker sums all live grant-axis envelopes before any axis decode, then
passes each admitted maximum to a fresh stat before parsing. Parent request
audit admits the two axes it processes together; the next grant replaces those
temporary carriers. Private validation accepts already authenticated axes from
that caller rather than parsing them again. A direct private validation admits
both axis files before decoding. No boolean bypass authorizes unbounded JSON.

For mixed backed readers, the existing getter plan admits physical fragment
metadata before its `fromJSON` calls or native selector construction, for cell
and feature orientations alike. Its retained envelope is
`256*physical_axis_count + 8*physical_JSON_and_path_bytes +
128*selected_axis_count + 8*selected_UTF8_bytes + 65536*fragment_count + 4MiB`.
Original dimensions matter: BPCells `MatrixRowSelect` creates a reverse map
over the original loader rows even for a tiny selected axis. This envelope
includes those native maps, decoded original axes and selected maps, not just
the returned block dimensions. A source's full axis metadata is not claimed
constant-space in axis cardinality.

Feature-oriented column storage needs one selected-entry count and one row
index construction. `matrix_stats(..., col_stats="nonzero", threads=1)` counts
stored entries, including explicit zeroes. These are constant preparation
passes, not verification per partition. The selected index uses the admitted
sort/load buffers and a separate disk credit. Cell-oriented/already-row-major
sources still receive physical-metadata admission but need no index pass.

## Native import, identity stream and transpose

The inspected R BPCells 0.3.1 source is c293a0a; see Quill's exact source ledger.
The adapter is for authenticated, core-generated finite unique-coordinate
Matrix Market, not a new arbitrary external-file importer. Header dimensions
and count must fit the existing INTMAX representation and count cannot exceed
the dimension product. Small whole-object caches are admitted before readMM.
Other private inputs use public streaming import with explicit bounded buffers.

Retained private metadata is `128*axis_count + 16*UTF8_bytes + 65536`, plus
4MiB fixed native overhead. `sort_bytes <= min(16MiB, workspace/16)`;
`load_bytes <= min(1MiB, sort_bytes/16)`, with minimum/alignment constraints.
For `N=ceil(stored_entries/(sort_bytes/32))`, require
`8*sort_bytes + 64*N <= workspace`. The two chunk-size vectors, their capacity
growth, merge fanout and fixed reader/writer buffers are accounted explicitly.
Backed plans own the fixed buffer allowance once, not once per retained index.

The disk reservation is `128*entries + 64*axis_count + 8*UTF8_bytes + 1MiB`.
It covers two native sort rounds and retained/imported columns during row
transpose. It ALSO covers the independent `scwb_matrix_identity_*` scratch
stream while imported columns remain: an INTMAX-coordinate canonical record
uses at most 80 bytes/entry; a final double/index column representation uses
roughly 12 bytes/entry plus axis/index metadata. Canonical escaped axes use at
most six bytes per original byte; the eight-byte multiplier covers this term.
These phases do not all coexist. The canonical scratch name is not silently
assumed covered by the graph scratch-name matcher. Source Matrix Market and
session-copy bytes retain their separate existing authorities/accounting.

Before native import, require workspace for at least one full feature column
(`128*nfeatures`). Choose verification width from this remaining workspace;
`max(1, ...)` is not used to waive a failing minimum-column admission.
Final owned index files are checked against their reservation; source-derived
overlap bounds, not a post-hoc final-size sample, justify intermediate peaks.

## Ownership and limits

Each reader/plan releases only its own memory/disk credit and scratch on close
or error. Source bytes authenticate at admission and again at parent publication;
light file/registry checks supplement, never replace, that authority. Mixed
graph connections are scoped before readers open, and private/index credits
reduce the subsequent R graph policy before graph cursors open. Parent-owned
session-copy bytes are transported privately to the R child and independently
checked; no source-authority handle or path is exposed to a pack.

Logical byte admission is not physical filesystem reservation or an RSS quota.
Physical free-space admission adds observed allocation/preallocation slack;
concurrent consumers can still cause an error requiring cleanup/rollback.
Existing R and Python graph allowances are not a new process-global quota.
The source proof applies to the inspected native build; tiny workstation tests
do not qualify a different cluster ABI/build. No new BPCells version gate,
container, public schema or identity scheme is introduced.
