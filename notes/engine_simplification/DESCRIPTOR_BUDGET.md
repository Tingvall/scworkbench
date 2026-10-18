# Descriptor preimage reuse (before implementation/probe)

Measured repaired baseline: 13,199-cell vector descriptor 1.628 s; two-key
26,398-row vector-family 3.581 s; relation-family 3.568 s. Ordinary provenance
object hashes were only .018/.041/.041 s. The descriptor separately canonicalizes
the same actual primitive for content, ancestry and payload identities; model
linkage and contained-payload identities repeat it again. The ancestry and
payload wrappers have identical canonical preimages, with distinct scheme labels
outside SHA-256.

Prospective budget communicated to Sable and Quill before edits: >=2x descriptor
speedup and peak RSS <=repaired baseline +10%, with every descriptor field and
identity byte-identical to the frozen repaired algorithm. Both independently
agreed the exact preimage rule; neither agreement is final qualification.

Canonicalize the actual value once and the input name with the existing full
canonical encoder. Hash the exact UTF-8 value bytes once and the sorted-key
`{"input":NAME,"value":VALUE}` bytes once. Reuse digests only under their
original distinct scheme labels. Never hash a digest instead of original bytes,
deduplicate metadata, relax canonical checks or persist a cross-call cache.
This optimizes ordinary complete-object authoring; it does not make that API
an arbitrarily large streaming primitive interface.
