# Provenance file SHA-256: prospective budget

Declared before implementation: matched large-file hashing target >=3x the
current digest(file=...) throughput; process peak RSS <=old+10 percent. Exact
lowercase SHA-256 bytes and existing scheme/claim shape are mandatory. No
measurements claimed here; the observed 9.9GB/75s digest cost is an upstream
attribution, not this component's matched benchmark.

Use the existing openssl Imports dependency and connection-input SHA-256,
already used by matrix, graph and space helpers. The installed openssl hashing
vignette explicitly documents binary connection streaming (Quill source review:
provenance_openssl_source_review.md, retained externally). No readBin of a whole
file into an R raw vector is introduced. Owned file connection opens at zero and
closes on success or hash error. Missing-file/directory checks remain unchanged;
no snapshot/TOCTOU guarantee, identity scheme, cache or publication change.

Focused source tests cover empty/binary/UTF8/buffer boundaries/16MiB byte parity,
actual mutation, original missing/directory assertion, deterministic open/read
faults and descriptor cleanup. >2GiB sparse-file parity belongs to an external
serial qualification harness, not an unconditional multi-GB canonical fixture.
No blanket platform/size/RSS or end-to-end performance claim follows from source.

Follow-up byte-boundary clarification: explicitly request file(raw=TRUE).
The original4a installed gzip probe PASSED on the current R/Linux runtime:
compressed1360-byte SHA161b273b96292005bf21be8d6a532037206ef05349ece63c4d5150583c6e20f7
was retained, distinct from decompressed262144-byte SHA
2312394bd99545d9de131c24efb781e765ac1aec243f2ed9347597a793a415e9.
Thus no decompression defect was observed; the explicit raw flag makes the
actual-file-byte contract unambiguous rather than repairing observed corruption.
Existing matrix/graph/space helpers use the same binary-connection backend;
they remain unchanged, with no demonstrated gzip failure inferred from API
wording alone. Their separate memory costs are not qualified by this change.
Original raw probe evidence and the RSS budget MISS remain retained externally.
