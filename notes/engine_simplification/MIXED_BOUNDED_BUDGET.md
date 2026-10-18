# Mixed reader and Matrix Market follow-up: prospective budgets

Recorded before implementation, based on frozen `fff50517` and the independent
Sable/Quill assessment. The preserved mixed fallback is a known acceptance
miss, not an approved deferral. This follow-up must remove it without changing
wire files, canonical identities, declared axes or scientific values.

Numerical targets:

- Eight versus 32 matrix blocks: one broker-lifetime full source admission,
  independent parent publication authentication, no block-count-proportional
  full source verification or complete private parsing.
- Core-generated Matrix Market writing: byte-exact old encoder; <=32 MiB
  ordinary block temporary target under the existing 256 MiB guard; two local
  value passes (count/finite check and emission). At 250,000 nonzeros, >=5x
  faster than the frozen old encoder; <=128 MiB additional RSS. At 100
  nonzeros, <=0.05-second extra fixed cost. No large performance jobs until the
  current suite and independent probes finish.
- Source startup must admit its buffers before decoding. Large private files
  use bounded BPCells import, never whole `readMM` followed by a size check.
  Small admitted caches must fit a conservative preparse envelope.
- Mixed retained private memory, all axes/guard records, SQLite connection
  caches, FD metadata, and the maximum of explicitly disjoint matrix/graph
  response workspaces must fit the existing graph/ordinary allowances. No
  manual increase to a memory guard or declared resource limit.
- Graph paging at ordinary 512 rows / 1 MiB: <=1.2x frozen old time +0.1 sec
  for 1,000 pages; metadata headers bounded by partition bytes +64 KiB.
  Exact old returned rows and payload identities; no whole graph verification
  added to ordinary pages.

Candidate implementation, subject to focused review:

1. Backed mixed reads keep `wb_slice` physical delivery, no new row index.
   Authenticate once, use supplementary guards around blocks, retain final
   parent full authentication.
2. Raw private file SHA/axis descriptors authenticate first. The file is
   core-generated finite, unique, column/row sorted `coordinate real general`;
   this is not a new importer for arbitrary external Matrix Market.
3. Stream-import oversized private files to column-major doubles using explicit
   bounded sorter buffers. Recompute the existing projected identity with
   bounded column reads. For feature reads, make one bounded row index only
   after authentication, then release/remove the column representation.
4. Source-derived importer disk reservation must cover simultaneous sorted
   runs, final data/index/name files, row transposition and filesystem metadata.
   A proposed conservative ceiling is 128 bytes/nonzero +64 bytes/axis ID
   +4 times UTF-8 axis bytes +16 MiB fixed allowance. This is NOT yet a proved
   guarantee; derive it against the actual BPCells sorter before relying on it.
5. Apply existing aggregate/scoped graph policy to actual broker connections;
   charge all live private reservations before graph cursor creation/service,
   preserve session-copy/WAL/token/unlinked-file accounting, restore on exits.
6. Release response locals before switching service branches. Replace graph's
   window/join page query only with snapshot-coherent bounded headers followed
   by their byte-admitted PK range. An engine-owned nested savepoint must not
   commit or roll back caller-owned writes.

Final evidence must retain every miss, actual BPCells version/build, logical
versus physical passes, and sampled versus source-derived peak bounds. Tiny
workstation probes do not establish cluster/native backend portability.
